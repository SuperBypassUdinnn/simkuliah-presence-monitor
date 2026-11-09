"""Purpose: Centralized application configuration and environment settings.
Data & Logic Flow: Resolves a single .env file (ENV_FILE override, Render secret files, backend/.env, then CWD/.env),
loads it into the process environment, and validates the merged values into strongly-typed Pydantic settings.
Key Components: Settings, settings, resolve_env_file, dotenv_candidates
"""

from __future__ import annotations

import os
from pathlib import Path
from typing import Self

from dotenv import load_dotenv
from pydantic import model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

# Candidate .env locations in priority order. Render mounts dashboard "Secret
# Files" under /etc/secrets/, so a single uploaded .env file covers production
# without any per-variable dashboard entries.
_SECRETS_DIR = Path("/etc/secrets")
_BACKEND_DIR = Path(__file__).resolve().parents[1]
_LOCAL_ENV_FILE = ".env"


def dotenv_candidates(env_file: str | None = None) -> list[str]:
    """Return the .env paths to probe, most significant first.

    Args:
        env_file: Explicit path (typically from the ``ENV_FILE`` environment
            variable). When set, it is probed before every default location.
    """
    candidates: list[str] = []
    if env_file:
        candidates.append(env_file)
    candidates.append(str(_SECRETS_DIR / ".env"))
    candidates.append(str(_SECRETS_DIR / "backend.env"))
    candidates.append(str(_BACKEND_DIR / _LOCAL_ENV_FILE))
    candidates.append(_LOCAL_ENV_FILE)
    return candidates


def resolve_env_file(env_file: str | None = None) -> str:
    """Return the first existing .env candidate path.

    Args:
        env_file: Explicit path probed before the default locations.

    Returns:
        The resolved file path, or ``".env"`` when nothing exists yet so
        first-run setups simply behave as if no file were present.

    Raises:
        FileNotFoundError: When an explicit ``env_file`` is set but missing,
            so a misconfigured deployment fails fast instead of silently
            starting without credentials.
    """
    for candidate in dotenv_candidates(env_file):
        if os.path.isfile(candidate):
            return candidate
    if env_file:
        raise FileNotFoundError(f"ENV_FILE points to a missing file: {env_file}")
    return _LOCAL_ENV_FILE


# Load the resolved file into os.environ as well, so modules that read the
# environment directly observe the same values as Pydantic settings. Real
# environment variables always win (override=False).
_ACTIVE_ENV_FILE = resolve_env_file(os.environ.get("ENV_FILE"))
load_dotenv(_ACTIVE_ENV_FILE, override=False)


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=_ACTIVE_ENV_FILE,
        env_file_encoding="utf-8",
        extra="ignore",
    )

    # Simkuliah credentials
    SIMKULIAH_NPM: str
    SIMKULIAH_PASSWORD: str

    # Push notification relay (ntfy.sh)
    NTFY_TOPIC: str
    ACTION_SECRET_KEY: str
    NTFY_BASE_URL: str = "https://ntfy.sh"

    # Public base URL of this backend, used as the target for signed ntfy
    # action buttons. When empty, falls back to Render's automatically
    # injected RENDER_EXTERNAL_URL.
    SIMKULIAH_API_BASE_URL: str = ""

    # Managed database (Supabase)
    # Supports modern Secret Key (sb_secret_...) and legacy service_role key (retiring early 2027)
    SUPABASE_URL: str
    SUPABASE_SECRET_KEY: str | None = None
    SUPABASE_SERVICE_ROLE_KEY: str | None = None

    # Adaptive polling intervals (seconds)
    POLL_ACTIVE_INTERVAL_SECONDS: int = 60
    POLL_PRE_CLASS_INTERVAL_SECONDS: int = 120
    POLL_IDLE_INTERVAL_SECONDS: int = 7200

    @model_validator(mode="after")
    def _resolve_api_base_url(self) -> Self:
        if not self.SIMKULIAH_API_BASE_URL:
            self.SIMKULIAH_API_BASE_URL = os.environ.get("RENDER_EXTERNAL_URL", "")
        return self

    @model_validator(mode="after")
    def _validate_supabase_keys(self) -> Self:
        if not self.SUPABASE_SECRET_KEY and not self.SUPABASE_SERVICE_ROLE_KEY:
            raise ValueError(
                "Either SUPABASE_SECRET_KEY (modern sb_secret_...) "
                "or SUPABASE_SERVICE_ROLE_KEY must be provided."
            )
        # Bi-directional fallback for seamless compatibility
        if not self.SUPABASE_SECRET_KEY:
            self.SUPABASE_SECRET_KEY = self.SUPABASE_SERVICE_ROLE_KEY
        if not self.SUPABASE_SERVICE_ROLE_KEY:
            self.SUPABASE_SERVICE_ROLE_KEY = self.SUPABASE_SECRET_KEY
        return self


settings = Settings()
