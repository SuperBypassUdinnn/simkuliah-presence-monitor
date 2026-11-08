"""Simkuliah session authenticator built on ``Settings`` and ``SimkuliahClient``.

Consumes the application :class:`~app.config.Settings` (for credentials) and the
local :func:`~app.services.captcha.solve_captcha` solver, exposing a small
session-management surface: login with CAPTCHA retry, keep-alive heartbeat,
schedule/semester fetching, and presence confirmation.
"""

from __future__ import annotations

from typing import Self

from app.config import Settings
from app.services.captcha import solve_captcha
from app.services.simkuliah_client import SimkuliahClient


class SimkuliahAuth:
    """Higher-level session authenticator that reads credentials from ``Settings``.

    Wraps a :class:`SimkuliahClient` and delegates every operation to it, so the
    rest of the daemon depends on this single auth seam rather than the raw
    HTTP client.
    """

    def __init__(self, settings: Settings | None = None) -> None:
        self.settings = settings or Settings()
        self.client = SimkuliahClient(
            npm=self.settings.SIMKULIAH_NPM,
            password=self.settings.SIMKULIAH_PASSWORD,
        )
        # Expose the solver for callers that want to drive the flow manually.
        self.solve_captcha = solve_captcha

    async def login(self) -> bool:
        """Authenticate and establish a persistent ``ci_session``."""
        return await self.client.login()

    async def keep_alive(self) -> bool:
        """Refresh the session by GETting the dashboard."""
        return await self.client.keep_alive()

    async def fetch_today_schedule(self) -> str:
        """Return the raw HTML of today's schedule page."""
        return await self.client.fetch_today_schedule()

    async def fetch_semester_matrix(self) -> str:
        """Return the raw HTML of the semester presence matrix page."""
        return await self.client.fetch_semester_matrix()

    async def confirm_presence(self, schedule_id: int, meeting_no: int) -> bool:
        """Confirm presence for the given schedule meeting."""
        return await self.client.confirm_presence(schedule_id, meeting_no)

    async def aclose(self) -> None:
        """Close the underlying HTTP client and release its connection pool."""
        await self.client.aclose()

    async def __aenter__(self) -> Self:
        return self

    async def __aexit__(self, exc_type, exc, tb) -> None:
        await self.aclose()
