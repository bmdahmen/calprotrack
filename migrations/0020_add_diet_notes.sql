-- Free-text dietary context/preferences the user can hand to the AI Coach
-- (day insight, day chat, history insight, history chat, and the food
-- estimator's commentary) — e.g. "I don't care about fiber" or "I'm
-- vegetarian" — so it stops raising things the user has said not to.
-- Run with: wrangler d1 execute calorie --remote --file=migrations/0020_add_diet_notes.sql

ALTER TABLE users ADD COLUMN diet_notes TEXT;
