-- Adds optional chest/neck/thigh/bicep measurements, replacing the free-text
-- notes field with structured optional fields (notes column is left in place,
-- unused going forward, since dropping it isn't necessary).
-- Run with: wrangler d1 execute calorie --remote --file=migrations/0007_add_extra_measurements.sql
ALTER TABLE measurements ADD COLUMN chest REAL;
ALTER TABLE measurements ADD COLUMN neck REAL;
ALTER TABLE measurements ADD COLUMN thigh REAL;
ALTER TABLE measurements ADD COLUMN bicep REAL;
ALTER TABLE history ADD COLUMN chest REAL;
ALTER TABLE history ADD COLUMN neck REAL;
ALTER TABLE history ADD COLUMN thigh REAL;
ALTER TABLE history ADD COLUMN bicep REAL;
