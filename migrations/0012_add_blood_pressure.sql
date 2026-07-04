-- Adds systolic/diastolic blood pressure (mmHg) as another optional daily
-- measurement, alongside resting HR (migration 0009).
-- Run with: wrangler d1 execute calorie --remote --file=migrations/0012_add_blood_pressure.sql
ALTER TABLE measurements ADD COLUMN bpSystolic INTEGER;
ALTER TABLE measurements ADD COLUMN bpDiastolic INTEGER;
ALTER TABLE history ADD COLUMN bpSystolic INTEGER;
ALTER TABLE history ADD COLUMN bpDiastolic INTEGER;
