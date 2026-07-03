-- Adds the bulk-side counterpart to muscle_loss_pct: the assumed muscle share
-- of weight gained above the DEXA baseline (previously only weight lost below
-- baseline had a configurable split).
-- Run with: wrangler d1 execute calorie --remote --file=migrations/0005_add_muscle_gain_pct.sql
ALTER TABLE users ADD COLUMN muscle_gain_pct REAL;
