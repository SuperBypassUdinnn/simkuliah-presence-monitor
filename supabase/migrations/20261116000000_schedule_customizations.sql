-- Migration: 20261116000000_schedule_customizations.sql
-- Description: Add user preferences and schedule customizations tables for schedule offsets and auto-presence

-- 1. User Global Preferences
CREATE TABLE IF NOT EXISTS user_preferences (
    id SERIAL PRIMARY KEY,
    user_id VARCHAR(64) NOT NULL DEFAULT 'default_user',
    default_reminder_minutes INT NOT NULL DEFAULT 15,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id)
);

-- 2. Schedule Customizations & Auto-Presence
CREATE TABLE IF NOT EXISTS schedule_customizations (
    id SERIAL PRIMARY KEY,
    schedule_id INT NOT NULL REFERENCES schedules(id) ON DELETE CASCADE,
    meeting_id INT REFERENCES meetings(id) ON DELETE CASCADE,
    -- Relative time shift applied to start and end times
    time_offset_minutes INT NOT NULL DEFAULT 0,
    -- Absolute rescheduling overrides (optional)
    custom_day_of_week INT, -- 1 = Monday, 7 = Sunday
    custom_start_time TIME,
    custom_end_time TIME,
    -- Automation flags
    auto_presence_enabled BOOLEAN NOT NULL DEFAULT FALSE,
    -- Notification lead-time override (null inherits user_preferences)
    reminder_lead_minutes INT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    -- Either schedule-wide (meeting_id IS NULL) or single-meeting specific
    UNIQUE(schedule_id, meeting_id)
);

-- RLS Policies
ALTER TABLE user_preferences ENABLE ROW LEVEL SECURITY;
ALTER TABLE schedule_customizations ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allow public read access on user_preferences"
    ON user_preferences FOR SELECT USING (true);
CREATE POLICY "Allow public write access on user_preferences"
    ON user_preferences FOR ALL USING (true);

CREATE POLICY "Allow public read access on schedule_customizations"
    ON schedule_customizations FOR SELECT USING (true);
CREATE POLICY "Allow public write access on schedule_customizations"
    ON schedule_customizations FOR ALL USING (true);
