-- Bring your own box (docs/BYOB.md): an account whose library runs on its own
-- machine, behind its own Cloudflare Tunnel.
--
-- At most one box per account. An account with no active box is served by the
-- owner's box, as before this table existed. The box's hostname is derived
-- from its id (<name>-box.aestra.studio), so it is not stored: nothing here can
-- point a request at an arbitrary host.
--
-- `publish_key_hash` is sha256 of the box's own service key, the one it uses
-- for /internal/*. It identifies the box on publish and lets that box write its
-- own manifest only.
CREATE TABLE box (
  id               TEXT PRIMARY KEY,
  account_id       TEXT NOT NULL UNIQUE REFERENCES account(id),
  publish_key_hash TEXT NOT NULL UNIQUE,
  status           TEXT NOT NULL DEFAULT 'active',
  created_at       INTEGER NOT NULL,
  last_publish_at  INTEGER
);
