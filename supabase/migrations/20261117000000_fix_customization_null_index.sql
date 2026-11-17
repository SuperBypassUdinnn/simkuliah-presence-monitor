-- Migration: 20261117000000_fix_customization_null_index.sql
-- Description: Replace multi-column unique constraint with partial unique indexes to properly handle NULL meeting_id

ALTER TABLE schedule_customizations DROP CONSTRAINT IF EXISTS schedule_customizations_schedule_id_meeting_id_key;

CREATE UNIQUE INDEX IF NOT EXISTS idx_schedule_customizations_course_unique
    ON schedule_customizations (schedule_id)
    WHERE meeting_id IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_schedule_customizations_meeting_unique
    ON schedule_customizations (schedule_id, meeting_id)
    WHERE meeting_id IS NOT NULL;
