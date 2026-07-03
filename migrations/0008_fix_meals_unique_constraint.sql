-- meals was keyed by id alone (PRIMARY KEY (id)), the last table not hardened
-- against cross-user collision. Meal ids are Date.now()+Math.random() so a
-- real collision is astronomically unlikely, but this closes the gap for
-- consistency with measurements/history/cache (migrations 0003/0004).
-- SQLite can't ALTER a primary key in place, so this recreates + copies + swaps.
-- Applied 2026-07-03 via the D1 connector with row-count verification between
-- each step (1416 = 1416).
-- Run with: wrangler d1 execute calorie --remote --file=migrations/0008_fix_meals_unique_constraint.sql

CREATE TABLE meals_new (
  id TEXT NOT NULL,
  date TEXT NOT NULL,
  "desc" TEXT,
  cal INTEGER,
  pro INTEGER,
  time TEXT,
  user_id TEXT DEFAULT 'default',
  PRIMARY KEY (id, user_id)
);
INSERT INTO meals_new (id, date, "desc", cal, pro, time, user_id)
  SELECT id, date, "desc", cal, pro, time, user_id FROM meals;
DROP TABLE meals;
ALTER TABLE meals_new RENAME TO meals;
