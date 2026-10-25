/**
 * D1 access. Every query is here so the handler never builds SQL inline and
 * the whole storage surface can be read in one file.
 */

export interface AccountRow {
  id: string;
  label: string;
  status: string;
  created_at: number;
}

export interface DeviceRow {
  id: string;
  account_id: string;
  label: string;
  refresh_hash: string;
  status: string;
  created_at: number;
  last_seen_at: number | null;
}

export interface InviteRow {
  code_hash: string;
  account_id: string;
  expires_at: number;
  redeemed_at: number | null;
  redeemed_device_id: string | null;
}

export interface BoxRow {
  id: string;
  account_id: string;
  publish_key_hash: string;
  status: string;
  created_at: number;
  last_publish_at: number | null;
}

/** A box id is its hostname's first label (<name>-box.aestra.studio), so its shape is fixed: lowercase letters, digits
 * and hyphens, ending in "-box". One level under the zone because the zone's certificate covers *.aestra.studio only:
 * box.aestra.studio's own subdomains had no certificate (25 Oct dry run). The "-box" ending is what the Worker's route
 * (*-box.aestra.studio) and its refusal of outside requests key on. */
export const BOX_ID = /^[a-z0-9](?:[a-z0-9-]{0,34}[a-z0-9])?-box$/;

/** The account's box when it has an active one (docs/BYOB.md). Null means the owner's box serves it. */
export async function activeBoxForAccount(db: D1Database, accountId: string): Promise<BoxRow | null> {
  return db
    .prepare("SELECT * FROM box WHERE account_id = ? AND status = 'active'")
    .bind(accountId)
    .first<BoxRow>();
}

/** The active box a publish key belongs to, by the key's hash. */
export async function activeBoxByPublishHash(db: D1Database, hash: string): Promise<BoxRow | null> {
  return db
    .prepare("SELECT * FROM box WHERE publish_key_hash = ? AND status = 'active'")
    .bind(hash)
    .first<BoxRow>();
}

export async function touchBoxPublish(db: D1Database, id: string, nowSec: number): Promise<void> {
  await db.prepare("UPDATE box SET last_publish_at = ? WHERE id = ?").bind(nowSec, id).run();
}

export async function accountById(db: D1Database, id: string): Promise<AccountRow | null> {
  return db.prepare("SELECT * FROM account WHERE id = ?").bind(id).first<AccountRow>();
}

export async function inviteByHash(db: D1Database, hash: string): Promise<InviteRow | null> {
  return db.prepare("SELECT * FROM invite WHERE code_hash = ?").bind(hash).first<InviteRow>();
}

export async function deviceByRefreshHash(
  db: D1Database,
  hash: string,
): Promise<DeviceRow | null> {
  return db
    .prepare("SELECT * FROM device WHERE refresh_hash = ?")
    .bind(hash)
    .first<DeviceRow>();
}

export async function deviceById(db: D1Database, id: string): Promise<DeviceRow | null> {
  return db.prepare("SELECT * FROM device WHERE id = ?").bind(id).first<DeviceRow>();
}

/**
 * Enrols a device against an invite, atomically, exactly once.
 *
 * Both statements are guarded by the same "invite is still unredeemed"
 * condition, and ordering matters in both directions:
 *
 * - The device must be inserted BEFORE the invite update, because
 *   `invite.redeemed_device_id` is a foreign key to `device(id)`. Updating
 *   first fails with SQLITE_CONSTRAINT_FOREIGNKEY.
 * - But a plain unconditional insert-then-update is worse than the FK error
 *   it fixes: when the invite was already redeemed the update matches zero
 *   rows while the insert still commits, leaving an orphan device row holding
 *   a valid refresh token. A device nobody enrolled, that mints access tokens
 *   forever, is the exact failure this service exists to prevent.
 *
 * So the insert carries `WHERE EXISTS (... redeemed_at IS NULL)`. A loser in
 * a race inserts nothing and updates nothing, and `changes` on the insert is
 * the authoritative "did I win" signal.
 */
export async function redeemInvite(
  db: D1Database,
  invite: InviteRow,
  device: Omit<DeviceRow, "last_seen_at">,
  nowSec: number,
): Promise<boolean> {
  const [claim] = await db.batch([
    db
      .prepare(
        `INSERT INTO device (id, account_id, label, refresh_hash, status, created_at)
         SELECT ?, ?, ?, ?, ?, ?
         WHERE EXISTS (SELECT 1 FROM invite WHERE code_hash = ? AND redeemed_at IS NULL)`,
      )
      .bind(
        device.id,
        device.account_id,
        device.label,
        device.refresh_hash,
        device.status,
        device.created_at,
        invite.code_hash,
      ),
    db
      .prepare(
        "UPDATE invite SET redeemed_at = ?, redeemed_device_id = ? WHERE code_hash = ? AND redeemed_at IS NULL",
      )
      .bind(nowSec, device.id, invite.code_hash),
  ]);
  return (claim?.meta?.changes ?? 0) > 0;
}

export async function touchDevice(
  db: D1Database,
  deviceId: string,
  nowSec: number,
): Promise<void> {
  await db
    .prepare("UPDATE device SET last_seen_at = ? WHERE id = ?")
    .bind(nowSec, deviceId)
    .run();
}

/** Revocation is a status flip, not a delete: which devices existed stays answerable. */
export async function revokeDevice(db: D1Database, deviceId: string): Promise<boolean> {
  const res = await db
    .prepare("UPDATE device SET status = 'revoked' WHERE id = ? AND status = 'active'")
    .bind(deviceId)
    .run();
  return (res.meta?.changes ?? 0) > 0;
}
