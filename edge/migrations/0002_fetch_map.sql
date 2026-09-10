-- sha -> source message map for the cloud fetcher (ORIGIN step 3).
--
-- The box daemon owns sightings: every markSeen upserts one row. The fetch
-- Worker reads by sha and never writes. One row per (sha, chat, msg): a
-- re-posted track has several rows and the fetcher tries each in turn.
--
-- Times are unix epoch seconds, supplied by the writer (D1 offers no clock).
CREATE TABLE IF NOT EXISTS fetch_map (
  sha        TEXT NOT NULL,
  chat       INTEGER NOT NULL,
  msg        INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  PRIMARY KEY (sha, chat, msg)
);
CREATE INDEX IF NOT EXISTS idx_fetch_map_sha ON fetch_map (sha);
