-- Per-day-type calorie goals: rest-day target + repeating training cycle.
--   rest_cal_target — manual calorie target applied on rest days; NULL means
--                     "same as the training-day target".
--   cycle_length    — training-cycle length in days; NULL/blank means every
--                     day is a training day (previous behavior).
--   cycle_pattern   — one char per cycle day: 'T' = training, 'R' = rest
--                     (e.g. 'TTTR' = 4-day cycle, rest on day 4).
--   cycle_anchor    — YYYY-MM-DD of cycle day 1; the pattern repeats from it.
-- Run with: wrangler d1 execute calorie --remote --file=migrations/0025_add_rest_day_targets.sql
ALTER TABLE users ADD COLUMN rest_cal_target INTEGER;
ALTER TABLE users ADD COLUMN cycle_length INTEGER;
ALTER TABLE users ADD COLUMN cycle_pattern TEXT;
ALTER TABLE users ADD COLUMN cycle_anchor TEXT;
