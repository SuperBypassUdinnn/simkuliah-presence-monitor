"""Purpose: Unit tests for application settings and configuration validation.
Data & Logic Flow: Tests environment parsing, key resolution, and validation fallbacks.
Key Components: test_settings_with_secret_key, test_settings_with_service_role_key, test_settings_missing_keys
"""

import pytest
from pydantic import ValidationError

from app.config import Settings


def test_settings_with_modern_secret_key(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("SIMKULIAH_NPM", "2408107010053")
    monkeypatch.setenv("SIMKULIAH_PASSWORD", "testpass")
    monkeypatch.setenv("NTFY_TOPIC", "test-topic")
    monkeypatch.setenv("ACTION_SECRET_KEY", "test-secret-key-32-chars-long-12345")
    monkeypatch.setenv("SUPABASE_URL", "https://example.supabase.co")
    monkeypatch.setenv("SUPABASE_SECRET_KEY", "sb_secret_test123")
    monkeypatch.delenv("SUPABASE_SERVICE_ROLE_KEY", raising=False)

    s = Settings(_env_file=None)
    assert s.SUPABASE_SECRET_KEY == "sb_secret_test123"
    assert s.SUPABASE_SERVICE_ROLE_KEY == "sb_secret_test123"


def test_settings_with_legacy_service_role_key(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("SIMKULIAH_NPM", "2408107010053")
    monkeypatch.setenv("SIMKULIAH_PASSWORD", "testpass")
    monkeypatch.setenv("NTFY_TOPIC", "test-topic")
    monkeypatch.setenv("ACTION_SECRET_KEY", "test-secret-key-32-chars-long-12345")
    monkeypatch.setenv("SUPABASE_URL", "https://example.supabase.co")
    monkeypatch.delenv("SUPABASE_SECRET_KEY", raising=False)
    monkeypatch.setenv("SUPABASE_SERVICE_ROLE_KEY", "legacy_service_role_key")

    s = Settings(_env_file=None)
    assert s.SUPABASE_SECRET_KEY == "legacy_service_role_key"
    assert s.SUPABASE_SERVICE_ROLE_KEY == "legacy_service_role_key"


def test_settings_missing_both_supabase_keys(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("SIMKULIAH_NPM", "2408107010053")
    monkeypatch.setenv("SIMKULIAH_PASSWORD", "testpass")
    monkeypatch.setenv("NTFY_TOPIC", "test-topic")
    monkeypatch.setenv("ACTION_SECRET_KEY", "test-secret-key-32-chars-long-12345")
    monkeypatch.setenv("SUPABASE_URL", "https://example.supabase.co")
    monkeypatch.delenv("SUPABASE_SECRET_KEY", raising=False)
    monkeypatch.delenv("SUPABASE_SERVICE_ROLE_KEY", raising=False)

    with pytest.raises(ValidationError, match=r"Either SUPABASE_SECRET_KEY.*must be provided"):
        Settings(_env_file=None)
