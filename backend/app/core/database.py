"""Purpose: Supabase PostgreSQL database repository wrapper.
Data & Logic Flow: Manages persistence for course schedules, meeting logs, overrides, and incidents.
Key Components: DatabaseRepository
"""

from __future__ import annotations

import asyncio
import logging
from datetime import datetime, timezone
from typing import Any

from supabase import create_client

from app.models.schemas import OverrideType
from app.services.simkuliah_parser import ParsedMeetingStatus, ParsedScheduleItem

logger = logging.getLogger(__name__)

# Supabase tables written to by this repository.
_TABLE_SCHEDULES = "schedules"
_TABLE_MEETINGS = "meetings"
_TABLE_LOCAL_OVERRIDES = "local_overrides"
_TABLE_INCIDENTS = "incidents"
_TABLE_DEVICE_TOKENS = "device_tokens"

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
        ``sakit``, ``alpa``, ``lupa_absen``, and ``dosen_tidak_absen``
        (case-sensitive).
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
            payload = [
                {
                    "course_code": item.course_code,
                    "course_name": item.course_name,
                    "class_group": "A",
                    "lecturer_name": item.lecturer,
                    "day_of_week": 1,
                    "start_time": item.start_time,
                    "end_time": item.end_time,
                    "room": item.room,
                    "semester_id": "20261",
                }
                for item in items
            ]
            self.client.table(_TABLE_SCHEDULES).upsert(
                payload, on_conflict="course_code,class_group,semester_id"
            ).execute()

        await self._with_retry(operation, "upsert_schedules")

    # ------------------------------------------------------------------ #
    # Meeting status
    # ------------------------------------------------------------------ #
    async def record_meeting_status(
        self,
        status: ParsedMeetingStatus,
        *,
        now: datetime | None = None,
    ) -> None:
        """Upsert one meeting's live attendance status into ``meetings``.

        Only provided fields are written: PostgREST upserts leave missing
        columns untouched, so a closed session never clears an earlier
        ``lecturer_opened_at``. Requires both ``schedule_id`` and
        ``meeting_number`` — without them the target row is ambiguous and the
        call is skipped.
        """
        if status.schedule_id is None or status.meeting_number is None:
            return

        # Naive wall-clock "now" (local machine = Simkuliah's WIB). Attaching
        # the machine's offset keeps the stored instant unambiguous while the
        # wall time matches what Simkuliah's "Batas Absen" expresses.
        moment = (now or datetime.now()).astimezone()
        payload: dict[str, Any] = {
            "schedule_id": status.schedule_id,
            "meeting_number": status.meeting_number,
            "last_polled_at": moment.isoformat(),
        }
        if status.deadline_time:
            try:
                hh, mm, ss = (status.deadline_time.split(":") + ["0", "0"])[:3]
                payload["deadline_at"] = moment.replace(
                    hour=int(hh), minute=int(mm), second=int(ss), microsecond=0
                ).isoformat()
            except ValueError:
                logger.warning("unparsable deadline_time %r", status.deadline_time)
        if status.is_open:
            payload["lecturer_opened_at"] = moment.isoformat()
        if status.is_student_present:
            payload["simkuliah_status"] = "hadir"

        def operation() -> None:
            self.client.table(_TABLE_MEETINGS).upsert(
                payload,
                on_conflict="schedule_id,meeting_number",
            ).execute()

        await self._with_retry(operation, "record_meeting_status")

    async def upsert_meetings(self, records: list[dict[str, Any]]) -> None:
        """Bulk-upsert parsed meeting rows on ``(schedule_id, meeting_number)``.

        Each record carries ``schedule_id``, ``meeting_number``,
        ``meeting_date``, ``lecturer_name`` and ``simkuliah_status`` taken
        from the today-page matrix, whose column order matches Simkuliah's
        official meeting numbering.
        """
        if not records:
            return

        def operation() -> None:
            self.client.table(_TABLE_MEETINGS).upsert(
                records,
                on_conflict="schedule_id,meeting_number",
            ).execute()

        await self._with_retry(operation, "upsert_meetings")

    # ------------------------------------------------------------------ #
    # Overrides
    # ------------------------------------------------------------------ #
    async def save_override(self, meeting_id: int, override_type: str, note: str = "") -> None:
        """Save an override for a meeting, rejecting unknown override types.

        Upserts on ``meeting_id`` (the table has a UNIQUE constraint) to match
        the client's semantics: one active override per meeting.
        """
        self._require_valid_override(override_type)

        def operation() -> None:
            payload = {
                "meeting_id": meeting_id,
                "override_type": override_type,
                "note": note,
            }
            self.client.table(_TABLE_LOCAL_OVERRIDES).upsert(
                payload, on_conflict="meeting_id"
            ).execute()

        await self._with_retry(operation, "save_override")

    async def get_active_override(self, meeting_id: int) -> str | None:
        """Return the active override type for a meeting, or ``None``.

        A row's existence means the override is active; the client clears the
        row to remove it.
        """

        def operation() -> Any:
            response = (
                self.client.table(_TABLE_LOCAL_OVERRIDES)
                .select("override_type")
                .eq("meeting_id", meeting_id)
                .execute()
            )
            data = response.data or []
            return data[0].get("override_type") if data else None

        return await self._with_retry(operation, "get_active_override")

    async def resolve_meeting_id(self, schedule_id: int, meeting_no: int) -> int | None:
        """Return the meetings-table id for ``(schedule_id, meeting_no)``."""

        def operation() -> Any:
            response = (
                self.client.table(_TABLE_MEETINGS)
                .select("id")
                .eq("schedule_id", schedule_id)
                .eq("meeting_number", meeting_no)
                .limit(1)
                .execute()
            )
            data = response.data or []
            return data[0].get("id") if data else None

        return await self._with_retry(operation, "resolve_meeting_id")

    async def resolve_schedule_id(self, course_code: str, class_group: str = "A") -> int | None:
        """Return the schedules-table id for a course code + class group."""

        def operation() -> Any:
            response = (
                self.client.table(_TABLE_SCHEDULES)
                .select("id")
                .eq("course_code", course_code)
                .eq("class_group", class_group)
                .limit(1)
                .execute()
            )
            data = response.data or []
            return data[0].get("id") if data else None

        return await self._with_retry(operation, "resolve_schedule_id")

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

    # ------------------------------------------------------------------ #
    # Device tokens (FCM push registry)
    # ------------------------------------------------------------------ #

    async def upsert_device_token(self, token: str, platform: str = "android") -> None:
        """Register a device push token idempotently (by unique token)."""

        def operation() -> Any:
            return (
                self.client.table(_TABLE_DEVICE_TOKENS)
                .upsert(
                    {
                        "token": token,
                        "platform": platform,
                        "last_seen_at": datetime.now(timezone.utc).isoformat(),
                    },
                    on_conflict="token",
                )
                .execute()
            )

        await self._with_retry(operation, "upsert_device_token")

    async def delete_device_token(self, token: str) -> None:
        """Remove a device push token from the registry."""

        def operation() -> Any:
            return self.client.table(_TABLE_DEVICE_TOKENS).delete().eq("token", token).execute()

        await self._with_retry(operation, "delete_device_token")

    def list_device_tokens_sync(self) -> list[str]:
        """Return registered tokens (best-effort, synchronous).

        Used by the FCM dispatcher, which runs on the polling loop and cannot
        await. Any failure yields an empty list so a database hiccup never
        suppresses the ntfy transport.
        """
        try:
            response = (
                self.client.table(_TABLE_DEVICE_TOKENS)
                .select("token")
                .order("last_seen_at", desc=True)
                .limit(500)
                .execute()
            )
            return [row["token"] for row in response.data or []]
        except Exception as exc:  # noqa: BLE001 - best effort only
            logger.warning("device token fetch failed: %s", exc)
            return []

    def prune_device_tokens_sync(self, tokens: list[str]) -> None:
        """Remove tokens FCM reported as unregistered (best-effort)."""
        if not tokens:
            return
        try:
            (self.client.table(_TABLE_DEVICE_TOKENS).delete().in_("token", tokens).execute())
        except Exception as exc:  # noqa: BLE001 - best effort only
            logger.warning("device token prune failed: %s", exc)
