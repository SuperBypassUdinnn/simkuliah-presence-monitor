-- Migration: 20261109120000_meetings_lecturer_name.sql
-- Description: Per-meeting lecturer for split-semester courses.
--
-- Simkuliah courses can change lecturer mid-semester (paruh 1 / paruh 2),
-- so the lecturer is a per-meeting attribute sourced from each matrix cell,
-- not a schedule-level constant.

ALTER TABLE meetings ADD COLUMN IF NOT EXISTS lecturer_name VARCHAR(128);
