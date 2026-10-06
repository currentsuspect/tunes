-- Account sync: what follows a listener from device to device.
--
-- One row per thing a listener owns (a like, a playlist, a title they fixed,
-- where they are in the music), keyed by account, not by device. A new device
-- that enrols into the account pulls everything from the beginning.
--
-- Last write wins per key, by the time the listener's device says the change
-- was made. That is the right size for this: two phones editing the same
-- playlist in the same minute is not the case being solved, a laptop and a
-- phone being the same person at different times is.
--
-- `seq` is the order the server learned things in, per account, and is what a
-- device pulls by ("everything after the last number I saw"). It is not the
-- change time: a phone that was offline for a day pushes old changes that are
-- new news to everyone else.

CREATE TABLE sync_doc (
  account_id TEXT NOT NULL REFERENCES account(id),
  -- 'like:<sha>', 'playlist:<uuid>', 'edit:<sha>:<field>', 'profile', 'now' (where it is playing), 'queue'
  -- (what is queued).
  -- The shapes are checked in the Worker; this table does not care.
  key        TEXT NOT NULL,
  -- JSON text, NULL once deleted. A deleted row is kept (a tombstone), or a
  -- device that was offline when it happened would bring the thing back.
  value      TEXT,
  deleted    INTEGER NOT NULL DEFAULT 0,
  -- When the listener made the change, in ms by the device clock corrected
  -- toward the server's. Decides which of two writes wins.
  updated_at INTEGER NOT NULL,
  device_id  TEXT NOT NULL,
  seq        INTEGER NOT NULL,
  PRIMARY KEY (account_id, key)
);

CREATE INDEX idx_sync_doc_seq ON sync_doc(account_id, seq);
