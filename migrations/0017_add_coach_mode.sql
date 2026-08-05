-- AI Coach generation mode per user: 'auto' (default, generates on its own
-- once food logging settles) or 'manual' (only generates when the user taps
-- the Generate button in the coach bar).
-- Run with: wrangler d1 execute calorie --remote --file=migrations/0017_add_coach_mode.sql

ALTER TABLE users ADD COLUMN coach_mode TEXT DEFAULT 'auto';
