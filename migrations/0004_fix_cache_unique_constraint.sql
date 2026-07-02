-- cache had the same bug as measurements/history: PRIMARY KEY (key) alone, so
-- different users writing under the same cache key (e.g. insight-day-<date>,
-- which isn't user-scoped in the key itself) would silently overwrite each
-- other's cached value while leaving the row's user_id untouched — meaning a
-- user could read back another user's AI-generated insight text.
-- Run with: wrangler d1 execute calorie --remote --file=migrations/0004_fix_cache_unique_constraint.sql

CREATE TABLE cache_new (
  key TEXT NOT NULL,
  value TEXT NOT NULL,
  fingerprint TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  user_id TEXT NOT NULL DEFAULT 'default',
  PRIMARY KEY (key, user_id)
);
INSERT INTO cache_new (key, value, fingerprint, updated_at, user_id)
  SELECT key, value, fingerprint, updated_at, user_id FROM cache;
DROP TABLE cache;
ALTER TABLE cache_new RENAME TO cache;
