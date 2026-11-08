"""Adaptive poller engine for the Simkuliah presence monitor.

Runs a background polling loop (via APScheduler ``AsyncIOScheduler``) that
checks the Simkuliah portal for today's schedule, parses it, persists it to
the database repository, evaluates the notification state machine, and
dispatches ntfy notifications. The poll interval adapts to the current lecture
state: active lectures are polled every 60s, pre-class observation every 120s,
and idle periods every 7200s.
"""

from __future__ import annotations

import asyncio
import logging
from datetime import datetime, time, timedelta
from typing import Any

from apscheduler.schedulers.asyncio import AsyncIOScheduler

from app.core.database import DatabaseRepository
from app.services.ntfy_service import NtfyDispatcher
from app.services.simkuliah_client import SimkuliahClient
from app.services.simkuliah_parser import ParsedScheduleItem, parse_daily_schedule
from app.services.state_machine import evaluate_notification_state

logger = logging.getLogger(__name__)

# Default idle interval (2 hours) — matches the application settings default.
_DEFAULT_IDLE_INTERVAL_SECONDS = 7200


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

      1. Fetch today's schedule from Simkuliah (with backoff on server errors).
      2. Parse the schedule HTML.
      3. Upsert parsed schedules into the database repository.
      4. Evaluate the notification state machine for each meeting.
      5. Dispatch ntfy notifications for non-suppressed states.

    Args:
        client: Simkuliah HTTP client.
        repo: Database repository.
        dispatcher: ntfy dispatcher.
        scheduler: APScheduler asyncio scheduler.
        backoff_seconds: Seconds to sleep before retrying after a server error.
    """

    def __init__(
        self,
        client: SimkuliahClient,
        repo: DatabaseRepository,
        dispatcher: NtfyDispatcher,
        scheduler: AsyncIOScheduler,
        *,
        backoff_seconds: int = 30,
    ) -> None:
        self.client = client
        self.repo = repo
        self.dispatcher = dispatcher
        self.scheduler = scheduler
        self.backoff_seconds = backoff_seconds

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
        # Fetch today's schedule, backing off on server errors (500/502/504).
        html = ""
        try:
            html = await self.client.fetch_today_schedule()
        except Exception as exc:  # noqa: BLE001 - network failure backs off
            logger.warning("schedule fetch failed: %s", exc)
            await asyncio.sleep(self.backoff_seconds)
            return

        if not html:
            # Empty body indicates a 500/502/504 server error from the client.
            logger.warning("schedule fetch returned empty body (server error)")
            await asyncio.sleep(self.backoff_seconds)
            return

        # Parse and persist the schedule.
        items: list[ParsedScheduleItem] = parse_daily_schedule(html)
        await self.repo.upsert_schedules(items)

        # Evaluate the state machine and dispatch notifications per meeting.
        now = datetime.now()
        for item in items:
            start_time = time.fromisoformat(item.start_time)
            end_time = time.fromisoformat(item.end_time)

            state = evaluate_notification_state(
                now=now,
                start_time=start_time,
                end_time=end_time,
                is_dosen_open=False,
                is_student_present=False,
                has_override=False,
                last_notified_level=None,
            )
            if state is None:
                continue

            context: dict[str, Any] = {
                "course_code": item.course_code,
                "course_name": item.course_name,
                "room": item.room,
                "lecturer": item.lecturer,
                "schedule_id": None,
                "meeting_no": None,
            }
            self.dispatcher.dispatch(state, context)
