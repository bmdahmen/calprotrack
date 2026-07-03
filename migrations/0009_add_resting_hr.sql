-- Adds resting heart rate (bpm) as another optional daily measurement,
-- alongside chest/neck/thigh/bicep (migration 0007). Stored on both the
-- per-day measurements table and the denormalized history table.
-- Run with: wrangler d1 execute calorie --remote --file=migrations/0009_add_resting_hr.sql
ALTER TABLE measurements ADD COLUMN restingHR INTEGER;
ALTER TABLE history ADD COLUMN restingHR INTEGER;
