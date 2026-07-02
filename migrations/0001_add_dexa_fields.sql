-- Adds DEXA body-composition baseline fields to users.
-- Run with: wrangler d1 execute calorie --remote --file=migrations/0001_add_dexa_fields.sql
ALTER TABLE users ADD COLUMN dexa_date TEXT;
ALTER TABLE users ADD COLUMN dexa_weight REAL;
ALTER TABLE users ADD COLUMN dexa_bf_pct REAL;
ALTER TABLE users ADD COLUMN muscle_loss_pct REAL;
