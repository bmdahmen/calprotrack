-- measurements and history were keyed by date alone (PRIMARY KEY (date)), so two
-- different users logging on the same calendar date would silently overwrite
-- each other's row. Recreate both tables with a compound (date, user_id) key.
-- SQLite can't ALTER a primary key in place, so this recreates + copies + swaps.
-- Run with: wrangler d1 execute calorie --remote --file=migrations/0003_fix_date_user_unique_constraint.sql

CREATE TABLE measurements_new (
  date TEXT NOT NULL,
  weightAM REAL,
  weightPM REAL,
  waistNavel REAL,
  waistSmallest REAL,
  notes TEXT,
  user_id TEXT NOT NULL DEFAULT 'default',
  dailyActivity TEXT DEFAULT 'sedentary',
  PRIMARY KEY (date, user_id)
);
INSERT INTO measurements_new (date, weightAM, weightPM, waistNavel, waistSmallest, notes, user_id, dailyActivity)
  SELECT date, weightAM, weightPM, waistNavel, waistSmallest, notes, user_id, dailyActivity FROM measurements;
DROP TABLE measurements;
ALTER TABLE measurements_new RENAME TO measurements;

CREATE TABLE history_new (
  date TEXT NOT NULL,
  calories INTEGER,
  protein INTEGER,
  weightAM REAL,
  weightPM REAL,
  waistNavel REAL,
  waistSmallest REAL,
  notes TEXT,
  user_id TEXT NOT NULL DEFAULT 'default',
  PRIMARY KEY (date, user_id)
);
INSERT INTO history_new (date, calories, protein, weightAM, weightPM, waistNavel, waistSmallest, notes, user_id)
  SELECT date, calories, protein, weightAM, weightPM, waistNavel, waistSmallest, notes, user_id FROM history;
DROP TABLE history;
ALTER TABLE history_new RENAME TO history;
