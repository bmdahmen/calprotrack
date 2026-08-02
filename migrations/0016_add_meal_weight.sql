-- Weight (grams) as a first-class field on logged meals, so a meal already
-- carries its own scale-adjustable weight instead of it only ever living
-- inside the free-text description. Populated when the source is known
-- (a food item/preset with a saved weight, or a Weigh & Calculate /
-- Calories->Weight entry with an exact gram amount); NULL otherwise.
-- Run with: wrangler d1 execute calorie --remote --file=migrations/0016_add_meal_weight.sql

ALTER TABLE meals ADD COLUMN weight_g REAL;
