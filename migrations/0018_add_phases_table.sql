-- Goal-mode phase history — a user's deficit/maintain/bulk timeline, so the
-- History chart can annotate when phases started/stopped and offer a "since
-- this phase started" range. Follows the compound (id, user_id) PRIMARY KEY
-- pattern used by meals/food_items/presets (migrations 0003/0008/0013).
-- end_date NULL means the phase is still ongoing (at most one such row per
-- user in practice, but not enforced at the DB level).
-- Run with: wrangler d1 execute calorie --remote --file=migrations/0018_add_phases_table.sql

CREATE TABLE IF NOT EXISTS phases (
  id TEXT NOT NULL,
  user_id TEXT NOT NULL DEFAULT 'default',
  mode TEXT NOT NULL,
  start_date TEXT NOT NULL,
  end_date TEXT,
  created_at TEXT NOT NULL,
  PRIMARY KEY (id, user_id)
);
