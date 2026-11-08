"""Purpose: Push notification dispatcher targeting ntfy.sh topics.
Data & Logic Flow: Builds rich notification messages with HMAC-signed action buttons and dispatches via HTTP.
Key Components: NtfyDispatcher, dispatch_ntfy_notification
"""

from __future__ import annotations

import json
import os
from typing import Any

import httpx

from app.core.security import create_action_token
from app.services.state_machine import NotificationLevel

# ntfy defaults, overridable through environment variables.
DEFAULT_BASE_URL = os.environ.get("NTFY_BASE_URL", "https://ntfy.sh")
DEFAULT_TOPIC = os.environ.get("NTFY_TOPIC", "simkuliah-presence")

try:
    from app.config import settings

    DEFAULT_SECRET = settings.ACTION_SECRET_KEY
except Exception:  # noqa: BLE001 - offline/test environment lacks settings
    DEFAULT_SECRET = os.environ.get("NTFY_ACTION_SECRET", "change-me-in-production")

# Lifetime of a signed action token (15 minutes).
_ACTION_TOKEN_TTL_SECONDS = 900


class NtfyDispatcher:
    """Sends ntfy notifications with signed HTTP action buttons.

    Args:
        base_url: ntfy origin (default ``https://ntfy.sh``).
        topic: ntfy topic to publish to.
        secret: HMAC secret used to sign action tokens.
        client: Optional HTTP client with a ``post(url, content, headers)``
            interface returning an object with a ``status_code`` attribute.
            Defaults to :mod:`httpx`, which performs a real network POST.
    """

    def __init__(
        self,
        base_url: str = DEFAULT_BASE_URL,
        topic: str = DEFAULT_TOPIC,
        secret: str = DEFAULT_SECRET,
        client: Any = None,
    ) -> None:
        self.base_url = base_url.rstrip("/")
        self.topic = topic
        self.secret = secret
        self._client = client

    # ------------------------------------------------------------------ #
    # Public API
    # ------------------------------------------------------------------ #

    def dispatch(self, state: NotificationLevel, context: dict) -> bool:
        """Dispatch a notification for ``state`` with the given ``context``.

        Returns ``True`` when the ntfy request was accepted (2xx), ``False``
        otherwise.
        """
        url = f"{self.base_url}/{self.topic}"
        title, message, actions = self._build_payload(state, context)
        headers = {
            "Title": title,
            "Message": message,
            "Actions": self._actions_header(actions),
            "Priority": self._priority(state),
        }
        body = json.dumps({"message": message, "actions": actions}).encode("utf-8")

        client = self._client if self._client is not None else httpx
        try:
            response = client.post(url, content=body, headers=headers)
            return 200 <= int(getattr(response, "status_code", 0)) < 300
        except Exception:  # noqa: BLE001 - network failure means no dispatch
            return False

    # ------------------------------------------------------------------ #
    # Payload construction
    # ------------------------------------------------------------------ #

    def _build_payload(
        self, state: NotificationLevel, context: dict
    ) -> tuple[str, str, list[dict[str, str]]]:
        course = context.get("course_code", "Kelas")
        room = context.get("room", "")
        lecturer = context.get("lecturer", "")

        title = f"Presensi {course}".strip()
        message = self._message_text(state, course, room, lecturer)

        schedule_id = context.get("schedule_id")
        meeting_no = context.get("meeting_no")
        base_payload: dict[str, Any] = {}
        if schedule_id is not None:
            base_payload["schedule_id"] = schedule_id
        if meeting_no is not None:
            base_payload["meeting_no"] = meeting_no

        actions: list[dict[str, str]] = []

        # "Presensi Sekarang" - direct presence confirmation.
        confirm_payload = dict(base_payload, action="confirm_presence")
        actions.append(
            {
                "label": "Presensi Sekarang",
                "type": "http",
                "target": self._action_url("confirm_presence"),
                "token": self._sign(confirm_payload),
            }
        )

        # "Izin" and "Sakit" overrides.
        for label, override_type in (("Izin", "izin"), ("Sakit", "sakit")):
            override_payload = dict(
                base_payload, action="mark_override", override_type=override_type
            )
            actions.append(
                {
                    "label": label,
                    "type": "http",
                    "target": self._action_url("mark_override"),
                    "token": self._sign(override_payload),
                }
            )

        return title, message, actions

    def _message_text(self, state: NotificationLevel, course: str, room: str, lecturer: str) -> str:
        where = f" ({room})" if room else ""
        who = f" - {lecturer}" if lecturer else ""
        base = f"{course}{where}{who}"
        texts = {
            NotificationLevel.CLASS_STARTED: f"Kelas dimulai: {base}.",
            NotificationLevel.LECTURER_OPENED: f"Dosen telah buka presensi: {base}.",
            NotificationLevel.PENDING_REMINDER: f"Pengingat: segera konfirmasi presensi {base}.",
            NotificationLevel.URGENT_CLOSING: f"Presensi hampir tutup: {base}.",
            NotificationLevel.WINDOW_EXPIRED: f"Jendela presensi telah tutup: {base}.",
        }
        return texts[state]

    def _priority(self, state: NotificationLevel) -> str:
        return {
            NotificationLevel.CLASS_STARTED: "default",
            NotificationLevel.LECTURER_OPENED: "high",
            NotificationLevel.PENDING_REMINDER: "high",
            NotificationLevel.URGENT_CLOSING: "urgent",
            NotificationLevel.WINDOW_EXPIRED: "max",
        }[state]

    def _action_url(self, action: str) -> str:
        # Webhook endpoint (Task 7) that verifies the signed token and acts.
        return f"{self.base_url.rstrip('/')}/api/v1/webhook/action"

    def _sign(self, payload: dict[str, Any]) -> str:
        return create_action_token(
            payload, secret=self.secret, expires_in_seconds=_ACTION_TOKEN_TTL_SECONDS
        )

    def _actions_header(self, actions: list[dict[str, str]]) -> str:
        parts = []
        for action in actions:
            parts.append(
                f'http, "{action["label"]}", {action["target"]}, '
                f"Method=POST, headers=X-Action-Token:{action['token']}"
            )
        return "; ".join(parts)


# --------------------------------------------------------------------------- #
# Module-level convenience function
# --------------------------------------------------------------------------- #


def dispatch_ntfy_notification(state: NotificationLevel, context: dict) -> bool:
    """Dispatch a ntfy notification using a default dispatcher.

    A thin wrapper around :class:`NtfyDispatcher` for call sites that do not
    need to customize the base URL, topic, or HTTP client.
    """
    dispatcher = NtfyDispatcher()
    return dispatcher.dispatch(state, context)
