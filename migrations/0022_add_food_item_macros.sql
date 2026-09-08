-- Fat/carbs (grams) on a food_items row, so items in the reusable catalog
-- carry the same macro data meals do (migration 0021) — a preset or quick-
-- add logged from one can then log fat/carbs too instead of only cal/pro.
-- Run with: wrangler d1 execute calorie --remote --file=migrations/0022_add_food_item_macros.sql

ALTER TABLE food_items ADD COLUMN fat REAL;
ALTER TABLE food_items ADD COLUMN carbs REAL;
