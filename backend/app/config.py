"""Purpose: Centralized application configuration and environment settings.
Data & Logic Flow: Validates environment variables into strongly-typed Pydantic settings.
Key Components: Settings, settings
"""

from __future__ import annotations

from typing import Self

from pydantic import model_validator
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
    # Supports modern Secret Key (sb_secret_...) and legacy service_role key (retiring early 2027)
    SUPABASE_URL: str
    SUPABASE_SECRET_KEY: str | None = None
    SUPABASE_SERVICE_ROLE_KEY: str | None = None

    # Adaptive polling intervals (seconds)
    POLL_ACTIVE_INTERVAL_SECONDS: int = 60
    POLL_PRE_CLASS_INTERVAL_SECONDS: int = 120
    POLL_IDLE_INTERVAL_SECONDS: int = 7200

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
