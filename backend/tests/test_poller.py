"""Unit tests for the adaptive poller engine and FastAPI lifespan.

Covers :func:`calculate_next_poll_interval` (active / pre-class / idle), the
:class:`AdaptivePoller` polling tick execution (schedule fetch, parse, database
update, state machine evaluation, ntfy dispatch, backoff on server errors), and
the FastAPI lifespan startup/shutdown of the APScheduler-backed poller.

All external dependencies (SimkuliahClient, DatabaseRepository, NtfyDispatcher,
APScheduler) are mocked so tests run offline and deterministic.
"""

from __future__ import annotations

from datetime import datetime, time
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from app.services.poller import (
    AdaptivePoller,
    calculate_next_poll_interval,
)

# --------------------------------------------------------------------------- #
# Helpers
# --------------------------------------------------------------------------- #


def _dt(hour: int, minute: int = 0) -> datetime:
    return datetime(2026, 11, 9, hour, minute)


# --------------------------------------------------------------------------- #
# calculate_next_poll_interval
# --------------------------------------------------------------------------- #


def test_interval_during_active_class():
    now = _dt(8, 30)
    # Active lecture 08:00 - 09:40
    interval = calculate_next_poll_interval(
        now, active_lectures=[(time(8, 0), time(9, 40))]
    )
    assert interval == 60  # 60 seconds


def test_interval_at_exact_start_is_active():
    now = _dt(8, 0)
    interval = calculate_next_poll_interval(
        now, active_lectures=[(time(8, 0), time(9, 40))]
    )
    assert interval == 60


def test_interval_at_exact_end_is_active():
    now = _dt(9, 40)
    interval = calculate_next_poll_interval(
        now, active_lectures=[(time(8, 0), time(9, 40))]
    )
    assert interval == 60


def test_interval_during_pre_class():
    now = _dt(7, 55)
    # Class starts in 5 minutes
    interval = calculate_next_poll_interval(
        now, active_lectures=[(time(8, 0), time(9, 40))]
    )
    assert interval == 120  # 120 seconds


def test_interval_at_pre_class_boundary_is_pre_class():
    # start_time - 10m == 07:50 counts as pre-class observation.
    now = _dt(7, 50)
    interval = calculate_next_poll_interval(
        now, active_lectures=[(time(8, 0), time(9, 40))]
    )
    assert interval == 120


def test_interval_just_outside_pre_class_is_idle():
    now = _dt(7, 49)
    interval = calculate_next_poll_interval(
        now, active_lectures=[(time(8, 0), time(9, 40))]
    )
    assert interval >= 3600


def test_interval_when_idle():
    now = _dt(14, 0)
    # No classes in afternoon
    interval = calculate_next_poll_interval(now, active_lectures=[])
    assert interval >= 3600  # Idle interval (at least 1 hour)


def test_interval_idle_respects_configured_minimum():
    now = _dt(14, 0)
    interval = calculate_next_poll_interval(
        now, active_lectures=[], min_idle_interval_seconds=5000
    )
    assert interval >= 5000


def test_interval_multiple_lectures_uses_first_match():
    now = _dt(10, 30)
    interval = calculate_next_poll_interval(
        now,
        active_lectures=[
            (time(8, 0), time(9, 40)),
            (time(10, 0), time(11, 30)),
        ],
    )
    assert interval == 60


# --------------------------------------------------------------------------- #
# AdaptivePoller tick execution
# --------------------------------------------------------------------------- #


@pytest.fixture
def poller_deps():
    """Bundle of mocked dependencies for AdaptivePoller."""
    client = MagicMock()
    client.login = AsyncMock(return_value=True)
    client.fetch_today_schedule = AsyncMock(return_value="<html>schedule</html>")
    client.aclose = AsyncMock()

    repo = MagicMock()
    repo.upsert_schedules = AsyncMock()
    repo.record_meeting_status = AsyncMock()
    repo.get_active_override = AsyncMock(return_value=None)

    dispatcher = MagicMock()
    dispatcher.dispatch = MagicMock(return_value=True)

    scheduler = MagicMock()
    scheduler.add_job = MagicMock()
    scheduler.start = MagicMock()
    scheduler.shutdown = MagicMock()
    scheduler.running = False

    return {
        "client": client,
        "repo": repo,
        "dispatcher": dispatcher,
        "scheduler": scheduler,
    }


@pytest.mark.asyncio
async def test_poller_tick_parses_and_updates_database(poller_deps):
    from app.services.simkuliah_parser import ParsedScheduleItem

    deps = poller_deps
    items = [
        ParsedScheduleItem(
            course_code="INF201",
            course_name="Grafika Komputer",
            room="Ruang 301",
            start_time="08:00",
            end_time="09:40",
            lecturer="Dr. Dosen, M.Kom",
        )
    ]

    with (
        patch(
            "app.services.poller.parse_daily_schedule", return_value=items
        ) as mock_parse,
        patch(
            "app.services.poller.evaluate_notification_state", return_value=None
        ) as mock_eval,
    ):
        poller = AdaptivePoller(
            client=deps["client"],
            repo=deps["repo"],
            dispatcher=deps["dispatcher"],
            scheduler=deps["scheduler"],
        )
        await poller._tick()

        deps["client"].fetch_today_schedule.assert_awaited_once()
        mock_parse.assert_called_once()
        deps["repo"].upsert_schedules.assert_awaited_once()
        assert mock_eval.call_count == 1


@pytest.mark.asyncio
async def test_poller_tick_dispatches_notification(poller_deps):
    from app.services.simkuliah_parser import ParsedScheduleItem

    deps = poller_deps
    items = [
        ParsedScheduleItem(
            course_code="INF201",
            course_name="Grafika Komputer",
            room="Ruang 301",
            start_time="08:00",
            end_time="09:40",
            lecturer="Dr. Dosen, M.Kom",
        )
    ]

    from app.services.state_machine import NotificationLevel

    with (
        patch("app.services.poller.parse_daily_schedule", return_value=items),
        patch(
            "app.services.poller.evaluate_notification_state",
            return_value=NotificationLevel.LECTURER_OPENED,
        ),
    ):
        poller = AdaptivePoller(
            client=deps["client"],
            repo=deps["repo"],
            dispatcher=deps["dispatcher"],
            scheduler=deps["scheduler"],
        )
        await poller._tick()

        deps["dispatcher"].dispatch.assert_called_once()


@pytest.mark.asyncio
async def test_poller_tick_backoff_on_server_error(poller_deps):
    deps = poller_deps
    deps["client"].fetch_today_schedule = AsyncMock(return_value="")

    with (
        patch("app.services.poller.parse_daily_schedule", return_value=[]),
        patch("app.services.poller.evaluate_notification_state", return_value=None),
        patch(
            "app.services.poller.asyncio.sleep", new_callable=AsyncMock
        ) as mock_sleep,
    ):
        poller = AdaptivePoller(
            client=deps["client"],
            repo=deps["repo"],
            dispatcher=deps["dispatcher"],
            scheduler=deps["scheduler"],
            backoff_seconds=5,
        )
        await poller._tick()

        mock_sleep.assert_awaited_once_with(5)


@pytest.mark.asyncio
async def test_poller_start_and_stop(poller_deps):
    deps = poller_deps
    poller = AdaptivePoller(
        client=deps["client"],
        repo=deps["repo"],
        dispatcher=deps["dispatcher"],
        scheduler=deps["scheduler"],
    )

    await poller.start()
    deps["scheduler"].start.assert_called_once()
    deps["scheduler"].add_job.assert_called()

    await poller.stop()
    deps["scheduler"].shutdown.assert_called_once()


# --------------------------------------------------------------------------- #
# FastAPI lifespan
# --------------------------------------------------------------------------- #


@pytest.mark.asyncio
async def test_lifespan_starts_and_stops_poller():
    from app.main import app, lifespan

    with (
        patch("app.main.poller", create=True) as mock_poller,
    ):
        mock_poller.start = AsyncMock()
        mock_poller.stop = AsyncMock()

        async with lifespan(app):
            mock_poller.start.assert_awaited_once()

        mock_poller.stop.assert_awaited_once()


@pytest.mark.asyncio
async def test_lifespan_poller_is_module_singleton():
    import app.main as main_module

    # The poller instance created on the module should be reused across the
    # app's lifetime (startup and shutdown reference the same object).
    assert hasattr(main_module, "poller")
    assert isinstance(main_module.poller, AdaptivePoller)
