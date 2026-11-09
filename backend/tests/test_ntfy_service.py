"""Purpose: Unit tests for ntfy dispatcher transport details.
Data & Logic Flow: Verifies priority mapping, action URL targeting, and payload structure.
Key Components: NtfyDispatcher
"""

from __future__ import annotations

from app.services.ntfy_service import NtfyDispatcher
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


class _FakeResponse:
    status_code = 200


class _FakeClient:
    """Records the outgoing ntfy request and returns a fake 200 response."""

    def __init__(self) -> None:
        self.last_request: tuple[str, bytes, dict] | None = None

    def post(self, url: str, content: bytes, headers: dict) -> _FakeResponse:
        self.last_request = (url, content, headers)
        return _FakeResponse()


def _dispatcher(client: _FakeClient, api_base_url: str = "https://simkuliah.example.com"):
    return NtfyDispatcher(
        base_url="https://ntfy.sh",
        topic="presence-test",
        secret="test-secret-key-32-chars-long-123456",
        client=client,
        api_base_url=api_base_url,
    )


# --------------------------------------------------------------------- #
# Priority policy
# --------------------------------------------------------------------- #


def test_urgent_levels_use_alarm_grade_ntfy_priority():
    client = _FakeClient()
    _dispatcher(client).dispatch(NotificationLevel.LECTURER_OPENED, context=_CONTEXT)

    _url, _content, headers = client.last_request
    assert headers["Priority"] == "urgent"


def test_urgent_closing_uses_alarm_grade_ntfy_priority():
    client = _FakeClient()
    _dispatcher(client).dispatch(NotificationLevel.URGENT_CLOSING, context=_CONTEXT)

    _url, _content, headers = client.last_request
    assert headers["Priority"] == "urgent"


def test_normal_levels_use_default_ntfy_priority():
    client = _FakeClient()
    for level in (
        NotificationLevel.CLASS_STARTED,
        NotificationLevel.PENDING_REMINDER,
        NotificationLevel.WINDOW_EXPIRED,
    ):
        _dispatcher(client).dispatch(level, context=_CONTEXT)
        _url, _content, headers = client.last_request
        assert headers["Priority"] == "default"


# --------------------------------------------------------------------- #
# Action buttons
# --------------------------------------------------------------------- #


def test_action_buttons_target_backend_webhook():
    client = _FakeClient()
    _dispatcher(client).dispatch(NotificationLevel.LECTURER_OPENED, context=_CONTEXT)

    _url, _content, headers = client.last_request
    actions = headers["Actions"]
    assert "https://simkuliah.example.com/api/v1/webhook/action" in actions
    assert "https://ntfy.sh/api" not in actions


def test_actions_omitted_without_public_base_url():
    client = _FakeClient()
    _dispatcher(client, api_base_url="").dispatch(
        NotificationLevel.LECTURER_OPENED, context=_CONTEXT
    )

    _url, _content, headers = client.last_request
    assert "Actions" not in headers


# --------------------------------------------------------------------- #
# Payload structure
# --------------------------------------------------------------------- #


def test_body_is_plain_message_text():
    client = _FakeClient()
    _dispatcher(client).dispatch(NotificationLevel.LECTURER_OPENED, context=_CONTEXT)

    _url, content, _headers = client.last_request
    text = content.decode("utf-8")
    assert text.startswith("Dosen telah buka presensi")
    assert not text.lstrip().startswith("{")


def test_title_contains_course_code():
    client = _FakeClient()
    _dispatcher(client).dispatch(NotificationLevel.LECTURER_OPENED, context=_CONTEXT)

    _url, _content, headers = client.last_request
    assert headers["Title"] == "Presensi INF201"
