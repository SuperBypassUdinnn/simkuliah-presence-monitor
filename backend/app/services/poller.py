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
    parse_attendance_cards,
    parse_daily_schedule,
    parse_meeting_matrix,
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
        pre_class_start = (datetime.combine(now.date(), start_time) - timedelta(minutes=10)).time()
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
        # Completion time of the last successful sync cycle; surfaced by the
        # health endpoint so clients can detect stale Simkuliah data.
        self.last_success_at: datetime | None = None
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
            next_run_time=datetime.now(),
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
        if not await self._ensure_session():
            # No session and login failed: back off and retry next tick.
            self.consecutive_failures += 1
            await asyncio.sleep(self._current_backoff_seconds())
            return

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
            # Empty body is either a genuine 500/502/504 server error or a
            # sessionless 307 redirect to the login page (which carries an
            # empty body): re-authenticate unconditionally and retry once
            # before counting a failure. A lost or stale session recovers
            # here; a real server outage fails again and backs off below.
            if not await self._ensure_session(force=True):
                self.consecutive_failures += 1
                await asyncio.sleep(self._current_backoff_seconds())
                return
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
        self.last_success_at = datetime.now()
        # Keep the fetched HTML so per-meeting data can be parsed without
        # refetching (which would double-count the schedule fetch).
        self._last_schedule_html = html
        # The dashboard must be re-fetched every tick: caching it across
        # ticks froze open-presence state at whatever the first tick saw.
        self._last_dashboard_html = None

        # Parse and persist the schedule.
        items: list[ParsedScheduleItem] = parse_daily_schedule(html)
        await self.repo.upsert_schedules(items)

        # Sync per-meeting rows (official numbering, per-meeting lecturer,
        # dates, and Simkuliah status) from the same today-page matrix.
        await self._sync_meetings_from_today(html)

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
            is_student_present = False
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
                is_student_present = meeting_status.is_student_present
                if meeting_status.deadline_time:
                    try:
                        deadline_at = datetime.combine(
                            now.date(),
                            time.fromisoformat(meeting_status.deadline_time),
                        )
                    except ValueError:
                        deadline_at = None

                # Cards without a konfirmasi button (e.g. "anda sudah
                # absen") carry no schedule id; resolve it from the course.
                if schedule_id is None:
                    try:
                        schedule_id = await self.repo.resolve_schedule_id(item.course_code)
                    except Exception:  # noqa: BLE001 - non-fatal
                        schedule_id = None

                # Persist the live card data (deadline, lecturer-opened,
                # hadir when already absen) so the client sees real state.
                if schedule_id is not None and meeting_no is not None:
                    try:
                        await self.repo.record_meeting_status(meeting_status, now=now)
                    except Exception as exc:  # noqa: BLE001 - non-fatal
                        logger.warning(
                            "record meeting status failed for %s: %s",
                            item.course_code,
                            exc,
                        )

            # Check the database for an active override on this meeting.
            has_override = False
            meeting_id: int | None = None
            if schedule_id is not None and meeting_no is not None:
                try:
                    meeting_id = await self.repo.resolve_meeting_id(schedule_id, meeting_no)
                    override_type = (
                        await self.repo.get_active_override(meeting_id)
                        if meeting_id is not None
                        else None
                    )
                    has_override = override_type is not None
                except Exception:  # noqa: BLE001 - DB failure is non-fatal
                    logger.warning("override lookup failed for %s P%s", schedule_id, meeting_no)
                    has_override = False

            meeting_key: int | str = schedule_id if schedule_id is not None else item.course_code
            last_level = self._last_levels.get(meeting_key)

            state = evaluate_notification_state(
                now=now,
                start_time=start_time,
                end_time=end_time,
                is_dosen_open=is_dosen_open,
                is_student_present=is_student_present,
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
            if meeting_id is not None:
                context["meeting_id"] = meeting_id
            self.dispatcher.dispatch(state, context)

            self._last_levels[meeting_key] = state

    # ------------------------------------------------------------------ #
    # Internal helpers
    # ------------------------------------------------------------------ #

    async def _ensure_session(self, *, force: bool = False) -> bool:
        """Establish a Simkuliah session, by default only when one is missing.

        The ``ci_session`` cookie lives only in the client's in-memory jar,
        so every deploy or restart starts sessionless; without an explicit
        login every fetch 307-redirects to the login page (empty body) and
        the poller degrades forever. Mock clients expose no real cookie
        jar, so the default is to treat them as authenticated. ``force``
        re-authenticates even when a cookie is present, because a cookie
        can be stale after the server expired it.
        """
        if not force and getattr(self.client, "is_authenticated", True):
            return True
        logger.info("logging in to simkuliah")
        try:
            return await self.client.login()
        except Exception as exc:  # noqa: BLE001 - login failure backs off
            logger.warning("simkuliah login failed: %s", exc)
            return False

    async def _sync_meetings_from_today(self, html: str) -> None:
        """Upsert per-meeting rows from the today-page meeting matrix.

        The today page orders meeting cells by Simkuliah's official meeting
        numbering (verified against the absensi dashboard), so column
        position maps directly to ``meeting_number``. Each cell also carries
        the real meeting date, the per-meeting lecturer (split-semester
        courses change lecturer), and the attendance color. This replaces the
        old semester-matrix sync, whose chronological column order desynced
        meeting numbers by a week whenever a week was skipped.
        """
        try:
            courses = parse_meeting_matrix(html)
            if not courses:
                return

            records: list[dict[str, Any]] = []
            for course in courses:
                schedule_id = await self.repo.resolve_schedule_id(
                    course.course_code, course.class_group
                )
                if schedule_id is None:
                    continue
                for meeting in course.meetings:
                    records.append(
                        {
                            "schedule_id": schedule_id,
                            "meeting_number": meeting.meeting_number,
                            "meeting_date": meeting.meeting_date,
                            "lecturer_name": meeting.lecturer,
                            "simkuliah_status": meeting.status,
                        }
                    )
            await self.repo.upsert_meetings(records)
        except Exception as exc:  # noqa: BLE001 - sync failure is non-fatal
            logger.warning("meeting matrix sync failed: %s", exc)

    def _idle_interval(self) -> int:
        """Return the configured idle interval in seconds."""
        try:
            from app.config import settings

            return settings.POLL_IDLE_INTERVAL_SECONDS
        except Exception:  # noqa: BLE001 - offline/test environment
            return _DEFAULT_IDLE_INTERVAL_SECONDS

    async def _fetch_meeting_status(self, item: ParsedScheduleItem) -> ParsedMeetingStatus | None:
        """Return the dashboard card matching ``item``'s course, if open.

        The dashboard renders one card per open attendance session; several
        can be open simultaneously, so all cards are parsed and matched by
        course code. Returns ``None`` when the session's presence is closed
        or no card matches.
        """
        dashboard_html = getattr(self, "_last_dashboard_html", None)
        if dashboard_html is None:
            try:
                dashboard_html = await self.client.fetch_dashboard()
            except Exception:  # noqa: BLE001 - never crash a tick
                dashboard_html = ""
            self._last_dashboard_html = dashboard_html or ""

        if not dashboard_html:
            return None
        try:
            cards = parse_attendance_cards(dashboard_html)
        except Exception:  # noqa: BLE001 - parse failure is non-fatal
            return None
        for card in cards:
            if card.course_code and card.course_code == item.course_code:
                return card
        return None
