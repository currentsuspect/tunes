-- Daily Telegram-fetch budget for the cloud path (per-worker, separate from
-- the box cap: different session, different risk surface, same conservatism).
-- One row per UTC day; takeCap() increments, dates roll on their own.
CREATE TABLE IF NOT EXISTS fetch_cap (
  day   TEXT PRIMARY KEY,
  count INTEGER NOT NULL DEFAULT 0
);
