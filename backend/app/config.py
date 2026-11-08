"""Application configuration backed by Pydantic Settings.

Consumes environment variables:
    SIMKULIAH_NPM, SIMKULIAH_PASSWORD, NTFY_TOPIC, ACTION_SECRET_KEY,
    SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY

Optional overrides with sensible defaults:
    NTFY_BASE_URL, POLL_ACTIVE_INTERVAL_SECONDS,
    POLL_PRE_CLASS_INTERVAL_SECONDS, POLL_IDLE_INTERVAL_SECONDS
"""

from __future__ import annotations

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
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

    # Managed database (Supabase)
    SUPABASE_URL: str
    SUPABASE_SERVICE_ROLE_KEY: str

    # Adaptive polling intervals (seconds)
    POLL_ACTIVE_INTERVAL_SECONDS: int = 60
    POLL_PRE_CLASS_INTERVAL_SECONDS: int = 120
    POLL_IDLE_INTERVAL_SECONDS: int = 7200


settings = Settings()
