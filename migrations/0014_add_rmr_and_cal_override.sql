-- Adds two profile-level fields for manual calorie-target control:
--   rmr                 — resting metabolic rate from a DEXA scan, used in
--                          place of the Mifflin-St Jeor estimate for TDEE
--                          when present.
--   cal_target_override — a manually chosen daily calorie target that
--                          replaces the aggressiveness-multiplier calculation
--                          when present. NULL means "use the calculation".
-- Run with: wrangler d1 execute calorie --remote --file=migrations/0014_add_rmr_and_cal_override.sql
ALTER TABLE users ADD COLUMN rmr REAL;
ALTER TABLE users ADD COLUMN cal_target_override INTEGER;
