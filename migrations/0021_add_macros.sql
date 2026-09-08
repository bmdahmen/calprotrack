-- Optional fat/carb tracking. track_macros is a per-user on/off switch
-- (0/1, default off) set from Profile; fat/carbs on meals are grams, NULL
-- when not tracked or not yet estimated for an older meal.
-- Run with: wrangler d1 execute calorie --remote --file=migrations/0021_add_macros.sql

ALTER TABLE users ADD COLUMN track_macros INTEGER DEFAULT 0;
ALTER TABLE meals ADD COLUMN fat REAL;
ALTER TABLE meals ADD COLUMN carbs REAL;
