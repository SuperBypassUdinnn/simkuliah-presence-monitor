-- Migration: 20261109000000_init_schema.sql
-- Description: Initialize core schema for Simkuliah presence monitoring

-- 1. Courses and Schedules
CREATE TABLE IF NOT EXISTS schedules (
    id SERIAL PRIMARY KEY,
    course_code VARCHAR(32) NOT NULL,
    course_name VARCHAR(128) NOT NULL,
    class_group VARCHAR(16) NOT NULL,
    lecturer_name VARCHAR(128),
    day_of_week INT NOT NULL, -- 1 = Monday, 7 = Sunday
    start_time TIME NOT NULL,
    end_time TIME NOT NULL,
    room VARCHAR(64),
    semester_id VARCHAR(16) NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(course_code, class_group, semester_id)
);

-- 2. Meetings and Presence Tracking
CREATE TABLE IF NOT EXISTS meetings (
    id SERIAL PRIMARY KEY,
    schedule_id INT REFERENCES schedules(id) ON DELETE CASCADE,
    meeting_number INT NOT NULL,
    meeting_date DATE NOT NULL,
    topic TEXT,
    lecturer_opened_at TIMESTAMPTZ,
    deadline_at TIMESTAMPTZ,
    simkuliah_status VARCHAR(32) DEFAULT 'pending', -- pending, hadir, tidak_hadir
    student_confirmed_at TIMESTAMPTZ,
    last_polled_at TIMESTAMPTZ,
    UNIQUE(schedule_id, meeting_number)
);

-- 3. Custom Local Overrides (Izin, Sakit, Alpa)
CREATE TABLE IF NOT EXISTS local_overrides (
    id SERIAL PRIMARY KEY,
    meeting_id INT REFERENCES meetings(id) ON DELETE CASCADE,
    override_type VARCHAR(16) NOT NULL, -- izin, sakit, alpa
    note TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(meeting_id)
);

-- 4. Notification Dispatch Log
CREATE TABLE IF NOT EXISTS notification_logs (
    id SERIAL PRIMARY KEY,
    meeting_id INT REFERENCES meetings(id) ON DELETE CASCADE,
    state_level INT NOT NULL, -- 1 to 5
    dispatched_at TIMESTAMPTZ DEFAULT NOW(),
    acknowledged_at TIMESTAMPTZ,
    response_action VARCHAR(32)
);

-- 5. System Health & Downtime Incidents
CREATE TABLE IF NOT EXISTS system_incidents (
    id SERIAL PRIMARY KEY,
    incident_type VARCHAR(64) NOT NULL, -- gateway_timeout, 500_error, captcha_exhaustion
    http_status INT,
    error_snippet TEXT,
    started_at TIMESTAMPTZ DEFAULT NOW(),
    resolved_at TIMESTAMPTZ
);

-- Enable Row Level Security (RLS)
ALTER TABLE schedules ENABLE ROW LEVEL SECURITY;
ALTER TABLE meetings ENABLE ROW LEVEL SECURITY;
ALTER TABLE local_overrides ENABLE ROW LEVEL SECURITY;
ALTER TABLE notification_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE system_incidents ENABLE ROW LEVEL SECURITY;

-- Policies: service_role full access, anon read/override access
CREATE POLICY "Allow service_role full access on schedules" ON schedules FOR ALL USING (true);
CREATE POLICY "Allow anon read access on schedules" ON schedules FOR SELECT USING (true);

CREATE POLICY "Allow service_role full access on meetings" ON meetings FOR ALL USING (true);
CREATE POLICY "Allow anon read access on meetings" ON meetings FOR SELECT USING (true);

CREATE POLICY "Allow service_role full access on local_overrides" ON local_overrides FOR ALL USING (true);
CREATE POLICY "Allow anon read access on local_overrides" ON local_overrides FOR SELECT USING (true);
CREATE POLICY "Allow anon insert/update on local_overrides" ON local_overrides FOR ALL USING (true);

CREATE POLICY "Allow service_role full access on notification_logs" ON notification_logs FOR ALL USING (true);
CREATE POLICY "Allow service_role full access on system_incidents" ON system_incidents FOR ALL USING (true);
CREATE POLICY "Allow anon read access on system_incidents" ON system_incidents FOR SELECT USING (true);
