"""Purpose: Adaptive poller engine coordinating schedule-aware polling and notifications.
Data & Logic Flow: Periodically polls Simkuliah, parses schedule, evaluates state machine, and triggers ntfy alerts.
Key Components: AdaptivePoller, calculate_next_poll_interval
"""

from __future__ import annotations

import asyncio
import logging
from datetime import datetime, time, timedelta
from typing import Any

from apscheduler.schedulers.asyncio import AsyncIOScheduler
from apscheduler.triggers.interval import IntervalTrigger

from app.core.database import DatabaseRepository
from app.services.ntfy_service import NtfyDispatcher
from app.services.simkuliah_client import SimkuliahClient
from app.services.simkuliah_parser import (
    ParsedMeetingStatus,
    ParsedScheduleItem,
    parse_attendance_status,
    parse_daily_schedule,
)
from app.services.state_machine import (
    NotificationLevel,
    evaluate_notification_state,
)

logger = logging.getLogger(__name__)

# Default idle interval (2 hours) — matches the application settings default.
_DEFAULT_IDLE_INTERVAL_SECONDS = 7200

# Exponential backoff tuning.
_BASE_BACKOFF_SECONDS = 30
_MAX_BACKOFF_SECONDS = 300


def calculate_next_poll_interval(
    now: datetime,
    active_lectures: list[tuple[time, time]],
    *,
    min_idle_interval_seconds: int = _DEFAULT_IDLE_INTERVAL_SECONDS,
) -> int:
    """Return the recommended poll interval in seconds.

    Args:
        now: Current time.
        active_lectures: List of ``(start_time, end_time)`` tuples for today's
            lectures.
        min_idle_interval_seconds: Minimum interval returned when idle
            (default 7200 seconds / 2 hours).

    Returns:
        60 when within an active lecture, 120 when within pre-class
        observation (10 minutes before a lecture starts), otherwise the idle
        interval.
    """
    now_time = now.time()

    for start_time, end_time in active_lectures:
        # Active lecture (inclusive of both boundaries).
        if start_time <= now_time <= end_time:
            return 60

    for start_time, _end_time in active_lectures:
        # Pre-class observation window: [start - 10m, start).
        pre_class_start = (
            datetime.combine(now.date(), start_time) - timedelta(minutes=10)
        ).time()
        if pre_class_start <= now_time < start_time:
            return 120

    return min_idle_interval_seconds


class AdaptivePoller:
    """Async background poller backed by APScheduler ``AsyncIOScheduler``.

    Coordinates one polling cycle per tick:

      1. Fetch today's schedule from Simkuliah (with exponential backoff on
         server errors).
      2. Parse the schedule HTML.
      3. Upsert parsed schedules into the database repository.
      4. Parse per-meeting attendance status.
      5. Evaluate the notification state machine per meeting (tracking the
         last notified level so notifications never repeat/regress).
      6. Dispatch ntfy notifications for non-suppressed states.
      7. Reschedule the APScheduler job to the computed adaptive interval.

    Args:
        client: Simkuliah HTTP client.
        repo: Database repository.
        dispatcher: ntfy dispatcher.
        scheduler: APScheduler asyncio scheduler.
        base_backoff_seconds: Initial backoff seconds on a server error
            (default 30).
        max_backoff_seconds: Backoff ceiling in seconds (default 300).
    """

    def __init__(
        self,
        client: SimkuliahClient,
        repo: DatabaseRepository,
        dispatcher: NtfyDispatcher,
        scheduler: AsyncIOScheduler,
        *,
        base_backoff_seconds: int = _BASE_BACKOFF_SECONDS,
        max_backoff_seconds: int = _MAX_BACKOFF_SECONDS,
    ) -> None:
        self.client = client
        self.repo = repo
        self.dispatcher = dispatcher
        self.scheduler = scheduler
        self.base_backoff_seconds = base_backoff_seconds
        self.max_backoff_seconds = max_backoff_seconds
        # Consecutive fetch failures; drives exponential backoff.
        self.consecutive_failures: int = 0
        # Last notified notification level per schedule_id / course_code (monotonic guard).
        self._last_levels: dict[int | str, NotificationLevel | None] = {}

    # ------------------------------------------------------------------ #
    # Helpers
    # ------------------------------------------------------------------ #

    def _current_backoff_seconds(self) -> int:
        """Return the current exponential backoff in seconds."""
        return min(
            self.max_backoff_seconds,
            self.base_backoff_seconds * (2 ** max(0, self.consecutive_failures - 1)),
        )

    def _reschedule(self, interval_seconds: int) -> None:
        """Reschedule the recurring poll job to ``interval_seconds``.

        No-op when the job already carries the requested interval.
        """
        job = self.scheduler.get_job("adaptive_poller_tick")
        if job is not None:
            try:
                current_interval = job.trigger.interval  # type: ignore[attr-defined]
            except AttributeError:
                current_interval = None
            if current_interval == interval_seconds:
                return
        self.scheduler.reschedule_job(
            "adaptive_poller_tick",
            trigger=IntervalTrigger(seconds=interval_seconds),
        )

    # ------------------------------------------------------------------ #
    # Lifecycle
    # ------------------------------------------------------------------ #

    async def start(self) -> None:
        """Start the scheduler and register the recurring poll job."""
        try:
            from app.config import settings

            interval = settings.POLL_IDLE_INTERVAL_SECONDS
        except Exception:  # noqa: BLE001 - offline/test environment
            interval = _DEFAULT_IDLE_INTERVAL_SECONDS

        self.scheduler.add_job(
            self._tick,
            "interval",
            seconds=interval,
            id="adaptive_poller_tick",
            replace_existing=True,
        )
        self.scheduler.start()

    async def stop(self) -> None:
        """Shut down the scheduler."""
        self.scheduler.shutdown()

    # ------------------------------------------------------------------ #
    # Polling tick
    # ------------------------------------------------------------------ #

    async def _tick(self) -> None:
        """Run a single polling cycle."""
        # Fetch today's schedule, backing off exponentially on server errors.
        html = ""
        try:
            html = await self.client.fetch_today_schedule()
        except Exception as exc:  # noqa: BLE001 - network failure backs off
            logger.warning("schedule fetch failed: %s", exc)
            self.consecutive_failures += 1
            await asyncio.sleep(self._current_backoff_seconds())
            return

        if not html:
            # Empty body indicates a 500/502/504 server error from the client.
            logger.warning("schedule fetch returned empty body (server error)")
            self.consecutive_failures += 1
            await asyncio.sleep(self._current_backoff_seconds())
            return

        # Successful fetch: reset backoff state.
        self.consecutive_failures = 0
        # Keep the fetched HTML so per-meeting status can be parsed without
        # refetching (which would double-count the schedule fetch).
        self._last_schedule_html = html

        # Parse and persist the schedule.
        items: list[ParsedScheduleItem] = parse_daily_schedule(html)
        await self.repo.upsert_schedules(items)

        # Build the list of active lectures (start, end) for interval calc.
        active_lectures: list[tuple[time, time]] = []
        for item in items:
            try:
                start_time = time.fromisoformat(item.start_time)
                end_time = time.fromisoformat(item.end_time)
            except ValueError:
                continue
            active_lectures.append((start_time, end_time))

        # Compute the adaptive interval and reschedule the job accordingly.
        now = datetime.now()
        interval = calculate_next_poll_interval(
            now, active_lectures, min_idle_interval_seconds=self._idle_interval()
        )
        self._reschedule(interval)

        # Evaluate the state machine and dispatch notifications per meeting.
        for item in items:
            start_time = time.fromisoformat(item.start_time)
            end_time = time.fromisoformat(item.end_time)

            schedule_id: int | None = None
            meeting_no: int | None = None
            is_dosen_open = False
            deadline_at: datetime | None = None

            # Per-meeting attendance status (open/closed, deadline, schedule
            # id, meeting number). Defensive: never crash a tick on failure.
            meeting_status: ParsedMeetingStatus | None = None
            try:
                meeting_status = await self._fetch_meeting_status(item)
            except Exception as exc:  # noqa: BLE001 - never crash a tick
                logger.warning(
                    "meeting status fetch failed for %s: %s",
                    item.course_code,
                    exc,
                )

            if meeting_status is not None:
                schedule_id = meeting_status.schedule_id
                meeting_no = meeting_status.meeting_number
                is_dosen_open = meeting_status.is_open
                if meeting_status.deadline_time:
                    try:
                        deadline_at = datetime.combine(
                            now.date(),
                            time.fromisoformat(meeting_status.deadline_time),
                        )
                    except ValueError:
                        deadline_at = None

            # Check the database for an active override on this meeting.
            has_override = False
            if schedule_id is not None:
                try:
                    override_type = await self.repo.get_active_override(schedule_id)
                    has_override = override_type is not None
                except Exception:  # noqa: BLE001 - DB failure is non-fatal
                    logger.warning("override lookup failed for meeting %s", schedule_id)
                    has_override = False

            meeting_key: int | str = (
                schedule_id if schedule_id is not None else item.course_code
            )
            last_level = self._last_levels.get(meeting_key)

            state = evaluate_notification_state(
                now=now,
                start_time=start_time,
                end_time=end_time,
                is_dosen_open=is_dosen_open,
                is_student_present=False,
                has_override=has_override,
                last_notified_level=last_level,
                deadline_at=deadline_at,
            )
            if state is None:
                continue

            # Monotonic guard: never re-dispatch a level equal to the last
            # notified level for this meeting.
            if last_level is not None and state == last_level:
                continue

            context: dict[str, Any] = {
                "course_code": item.course_code,
                "course_name": item.course_name,
                "room": item.room,
                "lecturer": item.lecturer,
                "schedule_id": schedule_id,
                "meeting_no": meeting_no,
            }
            self.dispatcher.dispatch(state, context)

            self._last_levels[meeting_key] = state

    # ------------------------------------------------------------------ #
    # Internal helpers
    # ------------------------------------------------------------------ #

    def _idle_interval(self) -> int:
        """Return the configured idle interval in seconds."""
        try:
            from app.config import settings

            return settings.POLL_IDLE_INTERVAL_SECONDS
        except Exception:  # noqa: BLE001 - offline/test environment
            return _DEFAULT_IDLE_INTERVAL_SECONDS

    async def _fetch_meeting_status(
        self, item: ParsedScheduleItem
    ) -> ParsedMeetingStatus | None:
        """Return parsed attendance status for a schedule item.

        Parses the schedule HTML already fetched during this tick (stored on
        the instance) through :func:`parse_attendance_status` to extract
        ``is_open``, ``deadline_time``, ``meeting_number``, and ``schedule_id``.
        Falls back to a fresh schedule fetch only when no HTML was cached.
        Returns ``None`` when no status could be determined.
        """
        html = getattr(self, "_last_schedule_html", "") or ""
        if not html:
            try:
                html = await self.client.fetch_today_schedule()
            except Exception:  # noqa: BLE001 - never crash a tick
                return None
        if not html or "alert" not in html.lower():
            return None
        try:
            return parse_attendance_status(html)
        except Exception:  # noqa: BLE001 - parse failure is non-fatal
            return None
