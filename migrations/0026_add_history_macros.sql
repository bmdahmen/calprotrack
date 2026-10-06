-- Fat/carbs (grams) on history rows, so the trend chart can graph them
-- alongside calories/protein.
-- Run with: wrangler d1 execute calorie --remote --file=migrations/0026_add_history_macros.sql

ALTER TABLE history ADD COLUMN fat REAL;
ALTER TABLE history ADD COLUMN carbs REAL;
