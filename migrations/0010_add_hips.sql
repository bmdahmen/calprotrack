-- Adds hip circumference (in) as another optional daily measurement.
-- Run with: wrangler d1 execute calorie --remote --file=migrations/0010_add_hips.sql
ALTER TABLE measurements ADD COLUMN hips REAL;
ALTER TABLE history ADD COLUMN hips REAL;
