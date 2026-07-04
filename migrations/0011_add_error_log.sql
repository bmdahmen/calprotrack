-- Records AI-call failures (real Anthropic API errors, and cases where the
-- model responded but didn't return parseable output) so intermittent
-- failures can be investigated instead of just flashing a toast and vanishing.
-- Run with: wrangler d1 execute calorie --remote --file=migrations/0011_add_error_log.sql
CREATE TABLE IF NOT EXISTS error_log (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id TEXT,
  source TEXT NOT NULL,   -- where it happened, e.g. 'server_ai_call', 'weigh_calculate', 'food_estimate', '/meals/save'
  type TEXT,              -- the _type sent to the AI proxy: food/image/ai_coach/default (null for non-AI calls)
  message TEXT NOT NULL,
  detail TEXT,            -- raw model/API output snippet, truncated
  created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_error_log_created_at ON error_log(created_at);
