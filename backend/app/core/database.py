"""Purpose: Supabase PostgreSQL database repository wrapper.
Data & Logic Flow: Manages persistence for course schedules, meeting logs, overrides, and incidents.
Key Components: DatabaseRepository
"""

from __future__ import annotations

import asyncio
import logging
from typing import Any

from supabase import create_client

from app.models.schemas import MeetingRecord, OverrideType
from app.services.simkuliah_parser import ParsedMeetingStatus, ParsedScheduleItem

logger = logging.getLogger(__name__)

# Supabase tables written to by this repository.
_TABLE_SCHEDULES = "schedules"
_TABLE_MEETINGS = "meetings"
_TABLE_OVERRIDES = "overrides"
_TABLE_INCIDENTS = "incidents"

# Maximum number of attempts for an intermittent database call.
_MAX_RETRIES = 3


class DatabaseRepository:
    """Async wrapper over the Supabase client with retry logic.

    Args:
        client: An optional Supabase client. When omitted, a real client is
            built from :data:`SUPABASE_URL` and
            :data:`SUPABASE_SERVICE_ROLE_KEY`. Injecting a client (e.g. a
            :class:`unittest.mock.MagicMock`) is the preferred path for
            offline tests.
    """

    def __init__(self, client: Any = None) -> None:
        if client is not None:
            self.client = client
        else:
            # Imported lazily so importing this module does not require the
            # Supabase environment variables to be present.
            from app.config import settings

            self.client = create_client(
                settings.SUPABASE_URL,
                settings.SUPABASE_SERVICE_ROLE_KEY,
            )

    # ------------------------------------------------------------------ #
    # Override-type validation
    # ------------------------------------------------------------------ #
    def is_valid_override(self, override_type: str) -> bool:
        """Return ``True`` when ``override_type`` is a valid override reason.

        Valid reasons are the members of :class:`OverrideType`: ``izin``,
        ``sakit``, and ``alpa`` (case-sensitive).
        """
        return override_type in {member.value for member in OverrideType}

    # ------------------------------------------------------------------ #
    # Internal helpers
    # ------------------------------------------------------------------ #
    def _require_valid_override(self, override_type: str) -> None:
        if not self.is_valid_override(override_type):
            raise ValueError(f"Invalid override type: {override_type!r}")

    async def _with_retry(self, operation: Any, label: str) -> Any:
        last_error: Exception | None = None
        for attempt in range(1, _MAX_RETRIES + 1):
            try:
                return await asyncio.to_thread(operation)
            except Exception as exc:  # noqa: BLE001 - retry any DB error
                last_error = exc
                logger.warning(
                    "database operation %s failed (attempt %d/%d): %s",
                    label,
                    attempt,
                    _MAX_RETRIES,
                    exc,
                )
        assert last_error is not None
        raise last_error

    # ------------------------------------------------------------------ #
    # Schedules
    # ------------------------------------------------------------------ #
    async def upsert_schedules(self, items: list[ParsedScheduleItem]) -> None:
        """Upsert parsed schedule items into the ``schedules`` table."""

        def operation() -> None:
            payload = [item.model_dump() for item in items]
            self.client.table(_TABLE_SCHEDULES).upsert(payload).execute()

        await self._with_retry(operation, "upsert_schedules")

    # ------------------------------------------------------------------ #
    # Meeting status
    # ------------------------------------------------------------------ #
    async def record_meeting_status(self, status: ParsedMeetingStatus) -> None:
        """Record a parsed meeting attendance status into ``meetings``."""

        def operation() -> None:
            payload = MeetingRecord(
                meeting_id=status.schedule_id or 0,
                schedule_id=status.schedule_id,
                meeting_number=status.meeting_number,
                is_open=status.is_open,
                deadline_time=status.deadline_time,
            )
            self.client.table(_TABLE_MEETINGS).insert(payload.model_dump()).execute()

        await self._with_retry(operation, "record_meeting_status")

    # ------------------------------------------------------------------ #
    # Overrides
    # ------------------------------------------------------------------ #
    async def save_override(self, meeting_id: int, override_type: str, note: str = "") -> None:
        """Save an override for a meeting, rejecting unknown override types."""
        self._require_valid_override(override_type)

        def operation() -> None:
            payload = {
                "meeting_id": meeting_id,
                "override_type": override_type,
                "note": note,
                "is_active": True,
            }
            self.client.table(_TABLE_OVERRIDES).upsert(payload).execute()

        await self._with_retry(operation, "save_override")

    async def get_active_override(self, meeting_id: int) -> str | None:
        """Return the active override type for a meeting, or ``None``."""

        def operation() -> Any:
            response = (
                self.client.table(_TABLE_OVERRIDES)
                .select("override_type")
                .eq("meeting_id", meeting_id)
                .eq("is_active", True)
                .execute()
            )
            data = response.data or []
            return data[0].get("override_type") if data else None

        return await self._with_retry(operation, "get_active_override")

    # ------------------------------------------------------------------ #
    # Incidents
    # ------------------------------------------------------------------ #
    async def log_incident(self, incident_type: str, status_code: int, snippet: str) -> None:
        """Log an incident into the ``incidents`` table."""

        def operation() -> None:
            payload = {
                "incident_type": incident_type,
                "status_code": status_code,
                "snippet": snippet,
            }
            self.client.table(_TABLE_INCIDENTS).insert(payload).execute()

        await self._with_retry(operation, "log_incident")
