"""Purpose: Unit tests for application settings and configuration validation.
Data & Logic Flow: Tests environment parsing, .env file resolution, key resolution, and validation fallbacks.
Key Components: test_settings_with_secret_key, test_settings_with_service_role_key, test_settings_missing_keys, resolve_env_file
"""

from pathlib import Path

import pytest
from pydantic import ValidationError

from app.config import Settings, resolve_env_file

REQUIRED_ENV_KEYS = (
    "SIMKULIAH_NPM",
    "SIMKULIAH_PASSWORD",
    "NTFY_TOPIC",
    "ACTION_SECRET_KEY",
    "SUPABASE_URL",
    "SUPABASE_SECRET_KEY",
    "SUPABASE_SERVICE_ROLE_KEY",
)


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


def _write_env_file(path: Path) -> Path:
    """Write a fully populated .env fixture and return its path."""
    path.write_text(
        "\n".join(
            [
                "SIMKULIAH_NPM=file-npm",
                "SIMKULIAH_PASSWORD=file-password",
                "NTFY_TOPIC=file-topic",
                "ACTION_SECRET_KEY=file-secret-key-32-chars-long-123456",
                "SUPABASE_URL=https://file.supabase.co",
                "SUPABASE_SECRET_KEY=sb_secret_file_key",
            ]
        ),
        encoding="utf-8",
    )
    return path


def test_resolve_env_file_prefers_explicit_path(tmp_path: Path) -> None:
    env_file = _write_env_file(tmp_path / "custom.env")

    assert resolve_env_file(str(env_file)) == str(env_file)


def test_resolve_env_file_falls_back_to_local_dotenv(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.chdir(tmp_path)
    _write_env_file(tmp_path / ".env")

    assert resolve_env_file() == ".env"


def test_resolve_env_file_defaults_when_nothing_exists(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.chdir(tmp_path)

    assert resolve_env_file() == ".env"


def test_resolve_env_file_raises_when_explicit_path_missing() -> None:
    with pytest.raises(FileNotFoundError, match=r"missing\.env"):
        resolve_env_file("/nonexistent/missing.env")


def test_settings_loads_values_from_env_file(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    for key in REQUIRED_ENV_KEYS:
        monkeypatch.delenv(key, raising=False)
    env_file = _write_env_file(tmp_path / ".env")

    s = Settings(_env_file=str(env_file))

    assert s.SIMKULIAH_NPM == "file-npm"
    assert s.NTFY_TOPIC == "file-topic"
    assert s.SUPABASE_SECRET_KEY == "sb_secret_file_key"
    assert s.SUPABASE_SERVICE_ROLE_KEY == "sb_secret_file_key"


def test_real_environment_overrides_env_file(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    env_file = _write_env_file(tmp_path / ".env")
    monkeypatch.setenv("SIMKULIAH_NPM", "env-npm")

    s = Settings(_env_file=str(env_file))

    assert s.SIMKULIAH_NPM == "env-npm"
