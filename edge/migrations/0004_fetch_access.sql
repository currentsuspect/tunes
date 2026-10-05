-- Last-served time per cached track, written by the fetch worker when it
-- serves a hit straight from R2 (off the Durable Object). The nightly sweep
-- evicts least-recently-used first. Additive: nothing reads it until the
-- worker that writes it is deployed.
CREATE TABLE IF NOT EXISTS fetch_access (
  sha  TEXT PRIMARY KEY,
  at   INTEGER NOT NULL,
  size INTEGER NOT NULL
);
