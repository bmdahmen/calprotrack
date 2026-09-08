-- Optional manual fat/carb goals (grams), same pattern as
-- cal_target_override: NULL means "use the auto default" (30% of calorie
-- target from fat, remainder from carbs — see updateUI() in index.html),
-- a set value overrides it.
-- Run with: wrangler d1 execute calorie --remote --file=migrations/0023_add_macro_targets.sql

ALTER TABLE users ADD COLUMN fat_target_override REAL;
ALTER TABLE users ADD COLUMN carbs_target_override REAL;
