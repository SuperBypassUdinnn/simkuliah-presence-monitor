"""Purpose: Unit tests for the Firebase Cloud Messaging dispatcher.
Data & Logic Flow: Verifies priority mapping, payload structure, token pruning, and disabled behavior.
Key Components: FcmDispatcher
"""

from __future__ import annotations

import json

from app.services.fcm_service import FcmDispatcher
from app.services.state_machine import NotificationLevel

# --------------------------------------------------------------------- #
# Helpers
# --------------------------------------------------------------------- #

_CONTEXT = {
    "course_code": "INF201",
    "course_name": "Grafika Komputer",
    "room": "Ruang 301",
    "lecturer": "Dr. Dosen, M.Kom",
    "schedule_id": 1042,
    "meeting_no": 7,
}


def _recording_dispatcher(tokens: list[str], results: list[str | None] | None = None):
    """Build a dispatcher with a recording fake FCM sender."""
    calls: list[tuple[list[str], str, str, dict, str]] = []
    removed: list[str] = []

    def send_fn(
        tokens: list[str], title: str, message: str, data: dict, android_priority: str
    ) -> list[str | None]:
        calls.append((list(tokens), title, message, dict(data), android_priority))
        return list(results) if results is not None else [None] * len(tokens)

    dispatcher = FcmDispatcher(
        token_provider=lambda: list(tokens),
        credentials_path="/tmp/fake-service-account.json",
        send_fn=send_fn,
        token_remover=removed.extend,
        secret="test-secret-key-32-chars-long-123456",
    )
    return dispatcher, calls, removed


# --------------------------------------------------------------------- #
# Disabled / empty behavior
# --------------------------------------------------------------------- #


def test_disabled_without_credentials_or_injected_sender():
    provider_calls: list[str] = []

    def provider() -> list[str]:
        provider_calls.append("called")
        return ["token-1"]

    dispatcher = FcmDispatcher(token_provider=provider, credentials_path=None)

    assert dispatcher.dispatch(NotificationLevel.LECTURER_OPENED, _CONTEXT) is False
    assert provider_calls == []


def test_skips_when_no_registered_devices():
    dispatcher, send_calls, _removed = _recording_dispatcher([])

    assert dispatcher.dispatch(NotificationLevel.LECTURER_OPENED, _CONTEXT) is False
    assert send_calls == []


# --------------------------------------------------------------------- #
# Priority policy
# --------------------------------------------------------------------- #


def test_high_priority_only_for_urgent_levels():
    dispatcher, send_calls, _removed = _recording_dispatcher(["token-1"])

    dispatcher.dispatch(NotificationLevel.LECTURER_OPENED, _CONTEXT)
    dispatcher.dispatch(NotificationLevel.URGENT_CLOSING, _CONTEXT)
    dispatcher.dispatch(NotificationLevel.CLASS_STARTED, _CONTEXT)
    dispatcher.dispatch(NotificationLevel.PENDING_REMINDER, _CONTEXT)
    dispatcher.dispatch(NotificationLevel.WINDOW_EXPIRED, _CONTEXT)

    priorities = [call[4] for call in send_calls]
    assert priorities == ["high", "high", "normal", "normal", "normal"]


# --------------------------------------------------------------------- #
# Payload structure
# --------------------------------------------------------------------- #


def test_payload_carries_signed_action_buttons():
    dispatcher, send_calls, _removed = _recording_dispatcher(["token-1"])

    dispatcher.dispatch(NotificationLevel.LECTURER_OPENED, _CONTEXT)

    _tokens, title, message, data, _priority = send_calls[0]
    assert title == "Presensi INF201"
    assert message.startswith("Dosen telah buka presensi")
    actions = json.loads(data["actions"])
    assert [action["label"] for action in actions] == [
        "Presensi Sekarang",
        "Izin",
        "Sakit",
    ]
    for action in actions:
        assert action["token"]
    assert data["schedule_id"] == "1042"
    assert data["meeting_no"] == "7"


# --------------------------------------------------------------------- #
# Delivery results and pruning
# --------------------------------------------------------------------- #


def test_returns_true_when_at_least_one_device_accepts():
    dispatcher, _calls, removed = _recording_dispatcher(
        ["dead-token", "device-a", "device-b"],
        results=["UNREGISTERED", None, None],
    )

    assert dispatcher.dispatch(NotificationLevel.LECTURER_OPENED, _CONTEXT) is True
    assert removed == ["dead-token"]


def test_returns_false_when_all_devices_fail():
    dispatcher, _calls, removed = _recording_dispatcher(
        ["device-a"], results=["INTERNAL_SERVER_ERROR"]
    )

    assert dispatcher.dispatch(NotificationLevel.LECTURER_OPENED, _CONTEXT) is False
    # Transient errors must not prune the token.
    assert removed == []


def test_send_exception_returns_false():
    def failing_sender(*args: object, **kwargs: object) -> list[str | None]:
        raise RuntimeError("boom")

    dispatcher = FcmDispatcher(
        token_provider=lambda: ["token-1"],
        credentials_path="/tmp/fake-service-account.json",
        send_fn=failing_sender,
        secret="test-secret-key-32-chars-long-123456",
    )

    assert dispatcher.dispatch(NotificationLevel.LECTURER_OPENED, _CONTEXT) is False
