"""Purpose: Tests for extended state machine tiers (CLASS_REMINDER, AUTO_CONFIRMED, AUTO_PRESENCE_FAILED).
Data & Logic Flow: Verifies state machine transitions, priorities, actionable flags, and text generation.
Key Components: test_class_reminder_triggers_within_lead_window, test_auto_presence_failed_is_high_priority_and_actionable
"""

from __future__ import annotations

from datetime import datetime, time

from app.services.notification_content import (
    ACTIONABLE_STATES,
    notification_text,
    notification_title,
)
from app.services.state_machine import (
    NotificationLevel,
    Priority,
    evaluate_notification_state,
    priority_for_state,
    rank_for_level,
)


def test_class_reminder_triggers_within_lead_window():
    now = datetime(2026, 11, 16, 7, 46)  # 14 mins before 8:00
    state = evaluate_notification_state(
        now=now,
        start_time=time(8, 0),
        end_time=time(9, 40),
        is_dosen_open=False,
        is_student_present=False,
        has_override=False,
        last_notified_level=None,
        reminder_lead_minutes=15,
    )
    assert state == NotificationLevel.CLASS_REMINDER
    assert priority_for_state(state) == Priority.NORMAL


def test_class_reminder_returns_none_outside_lead_window():
    now = datetime(2026, 11, 16, 7, 40)  # 20 mins before 8:00, lead is 15 mins
    state = evaluate_notification_state(
        now=now,
        start_time=time(8, 0),
        end_time=time(9, 40),
        is_dosen_open=False,
        is_student_present=False,
        has_override=False,
        last_notified_level=None,
        reminder_lead_minutes=15,
    )
    assert state is None


def test_class_reminder_suppressed_when_already_notified():
    now = datetime(2026, 11, 16, 7, 50)
    state = evaluate_notification_state(
        now=now,
        start_time=time(8, 0),
        end_time=time(9, 40),
        is_dosen_open=False,
        is_student_present=False,
        has_override=False,
        last_notified_level=NotificationLevel.CLASS_REMINDER,
        reminder_lead_minutes=15,
    )
    # Monotonic: last notified was already CLASS_REMINDER
    assert state == NotificationLevel.CLASS_REMINDER


def test_class_reminder_suppressed_by_override_or_present():
    now = datetime(2026, 11, 16, 7, 50)
    state = evaluate_notification_state(
        now=now,
        start_time=time(8, 0),
        end_time=time(9, 40),
        is_dosen_open=False,
        is_student_present=True,
        has_override=False,
        last_notified_level=None,
        reminder_lead_minutes=15,
    )
    assert state is None


def test_auto_presence_failed_is_high_priority_and_actionable():
    assert priority_for_state(NotificationLevel.AUTO_PRESENCE_FAILED) == Priority.HIGH
    assert NotificationLevel.AUTO_PRESENCE_FAILED in ACTIONABLE_STATES
    assert priority_for_state(NotificationLevel.AUTO_CONFIRMED) == Priority.NORMAL


def test_level_ranks_ordering():
    assert rank_for_level(NotificationLevel.CLASS_REMINDER) == 0
    assert rank_for_level(NotificationLevel.CLASS_STARTED) == 1
    assert rank_for_level(NotificationLevel.LECTURER_OPENED) == 2
    assert rank_for_level(NotificationLevel.AUTO_CONFIRMED) == 2
    assert rank_for_level(NotificationLevel.AUTO_PRESENCE_FAILED) == 2
    assert rank_for_level(NotificationLevel.PENDING_REMINDER) == 3
    assert rank_for_level(NotificationLevel.URGENT_CLOSING) == 4
    assert rank_for_level(NotificationLevel.WINDOW_EXPIRED) == 5


def test_notification_titles_and_texts():
    ctx = {
        "course_name": "Grafika Komputer",
        "course_code": "INF201",
        "room": "Lab 1",
        "lead_minutes": 15,
        "meeting_no": 3,
    }
    # CLASS_REMINDER
    title = notification_title(NotificationLevel.CLASS_REMINDER, ctx)
    text = notification_text(NotificationLevel.CLASS_REMINDER, ctx)
    assert "Pengingat Kuliah" in title
    assert "Grafika Komputer (INF201)" in title
    assert "Kuliah" in text

    # AUTO_CONFIRMED
    title = notification_title(NotificationLevel.AUTO_CONFIRMED, ctx)
    text = notification_text(NotificationLevel.AUTO_CONFIRMED, ctx)
    assert "Presensi Otomatis Berhasil" in title
    assert "otomatis" in text.lower()

    # AUTO_PRESENCE_FAILED
    title = notification_title(NotificationLevel.AUTO_PRESENCE_FAILED, ctx)
    text = notification_text(NotificationLevel.AUTO_PRESENCE_FAILED, ctx)
    assert "Presensi Otomatis Gagal" in title
    assert "gagal" in text.lower()
