-- Migration: 20261109010000_enable_realtime.sql
-- Description: Enable Supabase Realtime publication for Flutter client live streaming

-- Enable replica identity full for accurate real-time payload updates
ALTER TABLE schedules REPLICA IDENTITY FULL;
ALTER TABLE meetings REPLICA IDENTITY FULL;
ALTER TABLE local_overrides REPLICA IDENTITY FULL;

-- Add tables to the supabase_realtime publication
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' AND tablename = 'schedules'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE schedules;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' AND tablename = 'meetings'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE meetings;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' AND tablename = 'local_overrides'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE local_overrides;
    END IF;
END $$;
