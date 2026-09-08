-- Marks a food item as preset-only: it's still a full catalog row
-- (reusable across presets, editable, shows up in the preset builder's
-- item picker) but is filtered out of the everyday Food Items quick-grab
-- list by default. NULL/0 = visible (default), 1 = hidden.
-- Run with: wrangler d1 execute calorie --remote --file=migrations/0024_add_food_item_hidden.sql

ALTER TABLE food_items ADD COLUMN hidden INTEGER DEFAULT 0;
