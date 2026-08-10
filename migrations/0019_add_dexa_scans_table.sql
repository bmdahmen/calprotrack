-- Multiple DEXA scans per user, replacing the single dexa_date/dexa_weight/
-- dexa_bf_pct columns on users as the source of truth for body-fat-%
-- estimation. Those columns are left in place unused (same convention as
-- migration 0007's notes column) rather than dropped, and are backfilled
-- here as each user's first scan so existing baselines aren't lost.
-- Run with: wrangler d1 execute calorie --remote --file=migrations/0019_add_dexa_scans_table.sql

CREATE TABLE IF NOT EXISTS dexa_scans (
  id TEXT NOT NULL,
  user_id TEXT NOT NULL DEFAULT 'default',
  date TEXT NOT NULL,
  weight REAL NOT NULL,
  bf_pct REAL NOT NULL,
  created_at TEXT NOT NULL,
  PRIMARY KEY (id, user_id)
);

INSERT INTO dexa_scans (id, user_id, date, weight, bf_pct, created_at)
  SELECT 'seed-' || id, id, dexa_date, dexa_weight, dexa_bf_pct,
         COALESCE(dexa_date, '2026-01-01') || 'T00:00:00.000Z'
  FROM users
  WHERE dexa_weight IS NOT NULL AND dexa_bf_pct IS NOT NULL AND dexa_date IS NOT NULL;
