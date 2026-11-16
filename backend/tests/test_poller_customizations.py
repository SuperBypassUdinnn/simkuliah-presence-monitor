"""Purpose: Tests for poller schedule customizations, auto-presence, and interval clamping.
Data & Logic Flow: Verifies auto-presence execution, failure alerts, offset handling, and reminder clamping.
Key Components: test_poller_triggers_auto_presence_when_open, test_calculate_next_poll_interval_clamps_reminder
"""

from __future__ import annotations

from datetime import datetime, time
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from app.services.poller import AdaptivePoller, calculate_next_poll_interval
from app.services.simkuliah_parser import ParsedMeetingStatus, ParsedScheduleItem
from app.services.state_machine import NotificationLevel


@pytest.fixture
def poller_deps():
    """Bundle of mocked dependencies for AdaptivePoller."""
    client = MagicMock()
    client.login = AsyncMock(return_value=True)
    client.fetch_today_schedule = AsyncMock(return_value="<html>schedule</html>")
    client.fetch_dashboard = AsyncMock(return_value="")
    client.fetch_semester_matrix = AsyncMock(return_value="")
    client.aclose = AsyncMock()

    repo = MagicMock()
    repo.upsert_schedules = AsyncMock()
    repo.record_meeting_status = AsyncMock()
    repo.get_active_override = AsyncMock(return_value=None)
    repo.resolve_meeting_id = AsyncMock(return_value=42)
    repo.resolve_schedule_id = AsyncMock(return_value=7)
    repo.upsert_meetings = AsyncMock()
    repo.list_today_meeting_ids = AsyncMock(return_value=[42])
    repo.load_notified_levels = AsyncMock(return_value={})
    repo.log_notification = AsyncMock()
    repo.get_user_preferences = AsyncMock(return_value={"default_reminder_minutes": 15})
    repo.resolve_effective_customization = AsyncMock(return_value=None)

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


def _make_item() -> ParsedScheduleItem:
    return ParsedScheduleItem(
        course_code="INF201",
        course_name="Grafika Komputer",
        room="Lab 1",
        start_time="08:00",
        end_time="09:40",
        lecturer="Dr. X",
        class_group="A",
    )


@pytest.mark.asyncio
async def test_poller_triggers_auto_presence_when_open(poller_deps):
    deps = poller_deps
    deps["repo"].resolve_schedule_id = AsyncMock(return_value=10)
    deps["repo"].resolve_meeting_id = AsyncMock(return_value=50)
    deps["repo"].resolve_effective_customization = AsyncMock(
        return_value={
            "auto_presence_enabled": True,
            "time_offset_minutes": 0,
            "reminder_lead_minutes": 15,
        }
    )
    poller = AdaptivePoller(
        client=deps["client"],
        repo=deps["repo"],
        dispatcher=deps["dispatcher"],
        scheduler=deps["scheduler"],
    )

    item = _make_item()
    meeting_status = ParsedMeetingStatus(
        schedule_id=123,
        meeting_number=1,
        is_open=True,
        is_student_present=False,
    )

    with (
        patch("app.services.poller.parse_daily_schedule", return_value=[item]),
        patch.object(poller, "_sync_meetings_from_today", new_callable=AsyncMock),
        patch.object(poller, "_fetch_meeting_status", return_value=meeting_status),
        patch(
            "app.services.poller.confirm_meeting_on_simkuliah", new_callable=AsyncMock
        ) as mock_confirm,
        patch("app.services.poller.naive_wib_now", return_value=datetime(2026, 11, 16, 8, 5)),
    ):
        mock_confirm.return_value = {"status": "success"}
        await poller._run_tick()

        mock_confirm.assert_awaited_once()
        deps["dispatcher"].dispatch.assert_called_once()
        assert deps["dispatcher"].dispatch.call_args[0][0] == NotificationLevel.AUTO_CONFIRMED


@pytest.mark.asyncio
async def test_poller_auto_presence_failure_dispatches_alert(poller_deps):
    deps = poller_deps
    deps["repo"].resolve_schedule_id = AsyncMock(return_value=10)
    deps["repo"].resolve_meeting_id = AsyncMock(return_value=50)
    deps["repo"].resolve_effective_customization = AsyncMock(
        return_value={
            "auto_presence_enabled": True,
            "time_offset_minutes": 0,
        }
    )
    poller = AdaptivePoller(
        client=deps["client"],
        repo=deps["repo"],
        dispatcher=deps["dispatcher"],
        scheduler=deps["scheduler"],
    )

    item = _make_item()
    meeting_status = ParsedMeetingStatus(
        schedule_id=123,
        meeting_number=1,
        is_open=True,
        is_student_present=False,
    )

    with (
        patch("app.services.poller.parse_daily_schedule", return_value=[item]),
        patch.object(poller, "_sync_meetings_from_today", new_callable=AsyncMock),
        patch.object(poller, "_fetch_meeting_status", return_value=meeting_status),
        patch(
            "app.services.poller.confirm_meeting_on_simkuliah", new_callable=AsyncMock
        ) as mock_confirm,
        patch("app.services.poller.naive_wib_now", return_value=datetime(2026, 11, 16, 8, 5)),
    ):
        mock_confirm.side_effect = RuntimeError("Simkuliah gateway timeout")
        await poller._run_tick()

        mock_confirm.assert_awaited_once()
        deps["dispatcher"].dispatch.assert_called_once()
        assert deps["dispatcher"].dispatch.call_args[0][0] == NotificationLevel.AUTO_PRESENCE_FAILED


@pytest.mark.asyncio
async def test_poller_applies_schedule_offset_to_times(poller_deps):
    deps = poller_deps
    deps["repo"].resolve_schedule_id = AsyncMock(return_value=10)
    deps["repo"].resolve_meeting_id = AsyncMock(return_value=50)
    # Class shifted +60m from 08:00 to 09:00
    deps["repo"].resolve_effective_customization = AsyncMock(
        return_value={
            "auto_presence_enabled": False,
            "time_offset_minutes": 60,
            "reminder_lead_minutes": 15,
        }
    )
    poller = AdaptivePoller(
        client=deps["client"],
        repo=deps["repo"],
        dispatcher=deps["dispatcher"],
        scheduler=deps["scheduler"],
    )

    item = _make_item()  # 08:00 - 09:40
    meeting_status = ParsedMeetingStatus(
        schedule_id=123,
        meeting_number=1,
        is_open=False,
        is_student_present=False,
    )

    # At 08:10 (before shifted start 09:00, before reminder window 08:45)
    with (
        patch("app.services.poller.parse_daily_schedule", return_value=[item]),
        patch.object(poller, "_sync_meetings_from_today", new_callable=AsyncMock),
        patch.object(poller, "_fetch_meeting_status", return_value=meeting_status),
        patch("app.services.poller.naive_wib_now", return_value=datetime(2026, 11, 16, 8, 10)),
    ):
        await poller._run_tick()
        # Should not dispatch CLASS_STARTED because effective start is 09:00
        deps["dispatcher"].dispatch.assert_not_called()

    # At 08:50 (within 15m reminder window before 09:00)
    with (
        patch("app.services.poller.parse_daily_schedule", return_value=[item]),
        patch.object(poller, "_sync_meetings_from_today", new_callable=AsyncMock),
        patch.object(poller, "_fetch_meeting_status", return_value=meeting_status),
        patch("app.services.poller.naive_wib_now", return_value=datetime(2026, 11, 16, 8, 50)),
    ):
        await poller._run_tick()
        deps["dispatcher"].dispatch.assert_called_once()
        assert deps["dispatcher"].dispatch.call_args[0][0] == NotificationLevel.CLASS_REMINDER


def test_calculate_next_poll_interval_clamps_reminder():
    now = datetime(2026, 11, 16, 7, 30)
    active_lectures = [(time(8, 0), time(9, 40))]
    # Upcoming reminder at 7:45 (15 mins from 7:30 = 900 seconds)
    upcoming_reminders = [datetime(2026, 11, 16, 7, 45)]

    interval = calculate_next_poll_interval(
        now,
        active_lectures,
        upcoming_reminders=upcoming_reminders,
        min_idle_interval_seconds=7200,
    )
    # The normal pre-class window at 7:50 would be 20 mins (1200s).
    # But reminder is at 7:45 (15 mins = 900s), so interval must clamp to 900s!
    assert interval == 900
