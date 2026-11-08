"""Purpose: Unit tests for the 5-tier notification lifecycle state machine.
Data & Logic Flow: Verifies state transitions across lecture start, open, deadline, and expiration.
Key Components: test_state_1_class_started, test_state_2_lecturer_opened
"""

from __future__ import annotations

from datetime import datetime, time

from app.services.ntfy_service import NtfyDispatcher
from app.services.state_machine import (
    NotificationLevel,
    NotificationState,
    evaluate_notification_state,
)

# --------------------------------------------------------------------- #
# Helpers
# --------------------------------------------------------------------- #


def _dt(hour: int, minute: int = 0) -> datetime:
    return datetime(2026, 11, 9, hour, minute)


def _call(
    now: datetime,
    start: time,
    end: time,
    *,
    is_dosen_open: bool = False,
    is_student_present: bool = False,
    has_override: bool = False,
    last: NotificationLevel | None = None,
    lecturer_opened_at: datetime | None = None,
    deadline_at: datetime | None = None,
) -> NotificationLevel | None:
    return evaluate_notification_state(
        now=now,
        start_time=start,
        end_time=end,
        is_dosen_open=is_dosen_open,
        is_student_present=is_student_present,
        has_override=has_override,
        last_notified_level=last,
        lecturer_opened_at=lecturer_opened_at,
        deadline_at=deadline_at,
    )


# --------------------------------------------------------------------- #
# Alias
# --------------------------------------------------------------------- #


def test_notification_state_alias():
    assert NotificationState is NotificationLevel


# --------------------------------------------------------------------- #
# State 1: CLASS_STARTED
# --------------------------------------------------------------------- #


def test_state_1_class_started():
    state = _call(
        now=_dt(8, 5),
        start=time(8, 0),
        end=time(9, 40),
        is_dosen_open=False,
        last=None,
    )
    assert state == NotificationLevel.CLASS_STARTED


# --------------------------------------------------------------------- #
# State 2: LECTURER_OPENED
# --------------------------------------------------------------------- #


def test_state_2_lecturer_opened():
    state = _call(
        now=_dt(8, 10),
        start=time(8, 0),
        end=time(9, 40),
        is_dosen_open=True,
        is_student_present=False,
        has_override=False,
        last=NotificationLevel.CLASS_STARTED,
        lecturer_opened_at=_dt(8, 5),
    )
    assert state == NotificationLevel.LECTURER_OPENED


# --------------------------------------------------------------------- #
# State 3: PENDING_REMINDER
# --------------------------------------------------------------------- #


def test_state_3_pending_reminder():
    state = _call(
        now=_dt(8, 30),
        start=time(8, 0),
        end=time(9, 40),
        is_dosen_open=True,
        is_student_present=False,
        has_override=False,
        last=NotificationLevel.LECTURER_OPENED,
        lecturer_opened_at=_dt(8, 5),
        deadline_at=_dt(8, 35),
    )
    assert state == NotificationLevel.PENDING_REMINDER


# --------------------------------------------------------------------- #
# State 4: URGENT_CLOSING
# --------------------------------------------------------------------- #


def test_state_4_urgent_closing():
    state = _call(
        now=_dt(9, 35),
        start=time(8, 0),
        end=time(9, 40),
        is_dosen_open=True,
        is_student_present=False,
        has_override=False,
        last=NotificationLevel.PENDING_REMINDER,
        lecturer_opened_at=_dt(8, 5),
        deadline_at=_dt(9, 40),
    )
    assert state == NotificationLevel.URGENT_CLOSING


# --------------------------------------------------------------------- #
# State 5: WINDOW_EXPIRED
# --------------------------------------------------------------------- #


def test_state_5_window_expired():
    state = _call(
        now=_dt(9, 45),
        start=time(8, 0),
        end=time(9, 40),
        is_dosen_open=True,
        is_student_present=False,
        has_override=False,
        last=NotificationLevel.URGENT_CLOSING,
        lecturer_opened_at=_dt(8, 5),
        deadline_at=_dt(9, 40),
    )
    assert state == NotificationLevel.WINDOW_EXPIRED


# --------------------------------------------------------------------- #
# Suppression
# --------------------------------------------------------------------- #


def test_override_suppresses_notifications():
    state = _call(
        now=_dt(8, 15),
        start=time(8, 0),
        end=time(9, 40),
        is_dosen_open=True,
        is_student_present=False,
        has_override=True,
        last=NotificationLevel.CLASS_STARTED,
    )
    assert state is None


def test_student_present_suppresses_notifications():
    state = _call(
        now=_dt(8, 10),
        start=time(8, 0),
        end=time(9, 40),
        is_dosen_open=True,
        is_student_present=True,
        has_override=False,
        last=NotificationLevel.CLASS_STARTED,
    )
    assert state is None


def test_student_present_still_suppresses_after_window_expired():
    state = _call(
        now=_dt(9, 45),
        start=time(8, 0),
        end=time(9, 40),
        is_dosen_open=True,
        is_student_present=True,
        has_override=False,
        last=NotificationLevel.WINDOW_EXPIRED,
        deadline_at=_dt(9, 40),
    )
    assert state is None


# --------------------------------------------------------------------- #
# Monotonic progression guard
# --------------------------------------------------------------------- #


def test_does_not_regress_to_previous_level():
    # Once we've reached URGENT_CLOSING, going back earlier in time relative
    # to the window should not regress to CLASS_STARTED while open.
    state = _call(
        now=_dt(8, 10),
        start=time(8, 0),
        end=time(9, 40),
        is_dosen_open=True,
        is_student_present=False,
        has_override=False,
        last=NotificationLevel.URGENT_CLOSING,
        lecturer_opened_at=_dt(8, 5),
    )
    assert state == NotificationLevel.URGENT_CLOSING


# --------------------------------------------------------------------- #
# ntfy dispatch
# --------------------------------------------------------------------- #


class _FakeResponse:
    status_code = 200


class _FakeClient:
    """Records the outgoing ntfy request and returns a fake 200 response."""

    def __init__(self) -> None:
        self.last_request: tuple[str, bytes, dict] | None = None

    def post(self, url: str, content: bytes, headers: dict) -> _FakeResponse:
        self.last_request = (url, content, headers)
        return _FakeResponse()


def test_ntfy_dispatch_returns_true_on_success():
    client = _FakeClient()
    dispatcher = NtfyDispatcher(
        base_url="https://ntfy.sh",
        topic="presence-test",
        secret="test-secret-key-32-chars-long-123456",
        client=client,
    )
    result = dispatcher.dispatch(
        NotificationLevel.LECTURER_OPENED,
        context={
            "course_code": "INF201",
            "course_name": "Grafika Komputer",
            "room": "Ruang 301",
            "lecturer": "Dr. Dosen, M.Kom",
            "schedule_id": 1042,
            "meeting_no": 7,
        },
    )
    assert result is True
    assert client.last_request is not None
    _url, _content, headers = client.last_request
    assert _url == "https://ntfy.sh/presence-test"
    assert "X-Action-Token" in headers["Actions"]


def test_ntfy_dispatch_action_buttons_are_signed():
    client = _FakeClient()
    dispatcher = NtfyDispatcher(
        base_url="https://ntfy.sh",
        topic="presence-test",
        secret="test-secret-key-32-chars-long-123456",
        client=client,
    )
    dispatcher.dispatch(
        NotificationLevel.PENDING_REMINDER,
        context={
            "course_code": "INF201",
            "schedule_id": 1042,
            "meeting_no": 7,
        },
    )
    _url, _content, headers = client.last_request
    actions = headers["Actions"]
    for label in ("Presensi Sekarang", "Izin", "Sakit"):
        assert label in actions
    # Each action carries a signed X-Action-Token header.
    assert actions.count("X-Action-Token") >= 3
