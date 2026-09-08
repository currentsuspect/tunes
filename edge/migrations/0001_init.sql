-- Tunes auth: accounts, devices, invites.
--
-- Deliberately small. This is a device registry with revocation, not an
-- identity platform: no roles, no permissions, no quotas, no subscription
-- state. Those can be added without changing the token protocol, and adding
-- them now would be inventing requirements (SPEC §1.5, AGENTS.md §1).
--
-- Times are unix epoch seconds. SQLite has no native timestamp and D1 offers
-- no clock, so every time is supplied by the Worker.

CREATE TABLE account (
  id         TEXT PRIMARY KEY,
  label      TEXT NOT NULL,
  -- 'active' | 'disabled'. Disabling an account must not require walking its
  -- devices: token minting checks the account row on every refresh.
  status     TEXT NOT NULL DEFAULT 'active',
  created_at INTEGER NOT NULL
);

CREATE TABLE device (
  id           TEXT PRIMARY KEY,
  account_id   TEXT NOT NULL REFERENCES account(id),
  label        TEXT NOT NULL,
  -- sha256 of the refresh token, hex. The token itself is shown once, at
  -- enrolment, and never stored -- a dump of this table grants nothing.
  refresh_hash TEXT NOT NULL UNIQUE,
  -- 'active' | 'revoked'. Revoked rows are kept rather than deleted so that
  -- "which devices did this account ever have" stays answerable.
  status       TEXT NOT NULL DEFAULT 'active',
  created_at   INTEGER NOT NULL,
  last_seen_at INTEGER
);

CREATE INDEX idx_device_account ON device(account_id);
CREATE INDEX idx_device_refresh ON device(refresh_hash);

CREATE TABLE invite (
  -- sha256 of the invite code, hex. Same reasoning as refresh_hash.
  code_hash          TEXT PRIMARY KEY,
  account_id         TEXT NOT NULL REFERENCES account(id),
  expires_at         INTEGER NOT NULL,
  -- Single use. Set together, and only inside the redeem transaction.
  redeemed_at        INTEGER,
  redeemed_device_id TEXT REFERENCES device(id)
);

CREATE INDEX idx_invite_account ON invite(account_id);
