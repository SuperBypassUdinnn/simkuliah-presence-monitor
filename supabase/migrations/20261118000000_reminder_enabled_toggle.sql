-- Migration: 20261118000000_reminder_enabled_toggle.sql
-- Description: Add reminder_enabled toggle columns to user_preferences (global)
-- and schedule_customizations (per-course override).

-- Global reminder on/off flag. Defaults to TRUE (existing behaviour preserved).
ALTER TABLE user_preferences
  ADD COLUMN IF NOT EXISTS reminder_enabled BOOLEAN NOT NULL DEFAULT TRUE;

-- Nullable per-course override. NULL = inherit the global flag.
ALTER TABLE schedule_customizations
  ADD COLUMN IF NOT EXISTS reminder_enabled BOOLEAN;
