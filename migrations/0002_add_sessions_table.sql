-- Session tokens issued at login. A request is only trusted to act as a given
-- user if it presents a valid, unexpired token bound to that user — the
-- client can no longer just claim a user_id.
-- Run with: wrangler d1 execute calorie --remote --file=migrations/0002_add_sessions_table.sql
CREATE TABLE IF NOT EXISTS sessions (
  token TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  created_at TEXT NOT NULL,
  expires_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_sessions_user_id ON sessions(user_id);
