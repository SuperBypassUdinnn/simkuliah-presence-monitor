-- Migration: 20261109020000_widen_override_type.sql
-- Description: Widen override_type to VARCHAR(32) to support extended manual statuses

ALTER TABLE local_overrides ALTER COLUMN override_type TYPE VARCHAR(32);
