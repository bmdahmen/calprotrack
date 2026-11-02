-- Cardio eat-back calories on history rows: added cardio the user chose to
-- eat back that day, added to the day's calorie budget in the day tab.
-- Run with: wrangler d1 execute calorie --remote --file=migrations/0027_add_cardio_eatback.sql

ALTER TABLE history ADD COLUMN cardio_eatback INTEGER;
