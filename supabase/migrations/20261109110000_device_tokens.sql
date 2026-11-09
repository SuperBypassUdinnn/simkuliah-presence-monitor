-- Migration: 20261109110000_device_tokens.sql
-- Description: Registry of FCM device tokens for native push delivery.
--
-- Only the backend (service_role) reads and writes this table; service_role
-- bypasses RLS entirely, so RLS is enabled here with NO anon policies on
-- purpose. Clients register tokens through the backend API, never directly.

CREATE TABLE IF NOT EXISTS device_tokens (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    token TEXT NOT NULL UNIQUE,
    platform TEXT NOT NULL DEFAULT 'android',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE device_tokens ENABLE ROW LEVEL SECURITY;
