-- Optional serving weight (grams) for a food_items row, so the UI can show
-- the scaled gram amount alongside scaled calories/protein when a quantity
-- multiplier is applied (e.g. 1.2x a 150g serving -> 180g).
-- Run with: wrangler d1 execute calorie --remote --file=migrations/0015_add_food_item_weight.sql

ALTER TABLE food_items ADD COLUMN weight_g REAL;
