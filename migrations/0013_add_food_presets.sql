-- Adds two new tables for the meal-preset / quick-add feature:
--   food_items — reusable line items (e.g. "Mango (40cal serving)", "Yogurt")
--     with a fixed cal/pro value, quick-added to a day's log in multiples.
--   presets    — a named group of food_items (each with its own qty), e.g.
--     "Yogurt Bowl", logged in one click as separate meal line items.
-- Both follow the compound (id, user_id) PRIMARY KEY pattern used by
-- meals/measurements/history/cache (migrations 0003/0004/0008) so two users
-- can never collide on the same row.
-- Run with: wrangler d1 execute calorie --remote --file=migrations/0013_add_food_presets.sql

CREATE TABLE IF NOT EXISTS food_items (
  id TEXT NOT NULL,
  user_id TEXT NOT NULL DEFAULT 'default',
  name TEXT NOT NULL,
  cal INTEGER NOT NULL,
  pro INTEGER NOT NULL DEFAULT 0,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL,
  PRIMARY KEY (id, user_id)
);

-- items is a JSON array of {food_item_id, name, cal, pro, qty} snapshotted at
-- save time, so editing/deleting a food_item later never changes a preset
-- that already references it.
CREATE TABLE IF NOT EXISTS presets (
  id TEXT NOT NULL,
  user_id TEXT NOT NULL DEFAULT 'default',
  name TEXT NOT NULL,
  items TEXT NOT NULL,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL,
  PRIMARY KEY (id, user_id)
);
