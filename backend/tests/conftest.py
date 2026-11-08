"""Pytest configuration for the Simkuliah presence monitor backend.

Provides dummy application settings so the FastAPI app (and its module-level
import of ``app.config.settings`` via the webhooks router) can be imported
without real deployment credentials.
"""

from __future__ import annotations

import os

os.environ.setdefault("SIMKULIAH_NPM", "test-npm")
os.environ.setdefault("SIMKULIAH_PASSWORD", "test-password")
os.environ.setdefault("NTFY_TOPIC", "test-topic")
os.environ.setdefault("ACTION_SECRET_KEY", "test-secret-key-32-chars-long-123456")
os.environ.setdefault("SUPABASE_URL", "https://test.supabase.co")
os.environ.setdefault("SUPABASE_SERVICE_ROLE_KEY", "test-service-role-key")
