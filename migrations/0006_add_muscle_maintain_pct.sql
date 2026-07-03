-- Third counterpart to muscle_loss_pct / muscle_gain_pct: the assumed muscle
-- share of small weight fluctuations within a pound of the DEXA baseline,
-- treated as "maintaining" rather than clearly bulking/cutting.
-- Run with: wrangler d1 execute calorie --remote --file=migrations/0006_add_muscle_maintain_pct.sql
ALTER TABLE users ADD COLUMN muscle_maintain_pct REAL;
