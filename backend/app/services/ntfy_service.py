"""Purpose: Push notification dispatcher targeting ntfy.sh topics.
Data & Logic Flow: Builds rich notification messages with HMAC-signed action buttons and dispatches via HTTP.
Key Components: NtfyDispatcher, dispatch_ntfy_notification
"""

from __future__ import annotations

import os
from typing import Any

import httpx

from app.core.security import create_action_token
from app.services.notification_content import (
    ACTIONABLE_STATES,
    notification_text,
    notification_title,
)
from app.services.state_machine import NotificationLevel, Priority, priority_for_state

# ntfy defaults. When the app settings are importable they are the single
# source of truth (which includes .env values); the os.environ fallback only
# covers offline/test environments where app.config cannot be imported.
try:
    from app.config import settings

    DEFAULT_BASE_URL = settings.NTFY_BASE_URL
    DEFAULT_TOPIC = settings.NTFY_TOPIC
    DEFAULT_SECRET = settings.ACTION_SECRET_KEY
    DEFAULT_API_BASE_URL = settings.SIMKULIAH_API_BASE_URL
except Exception:  # noqa: BLE001 - offline/test environment lacks settings
    DEFAULT_BASE_URL = os.environ.get("NTFY_BASE_URL", "https://ntfy.sh")
    DEFAULT_TOPIC = os.environ.get("NTFY_TOPIC", "simkuliah-presence")
    DEFAULT_SECRET = os.environ.get("NTFY_ACTION_SECRET", "change-me-in-production")
    DEFAULT_API_BASE_URL = os.environ.get("SIMKULIAH_API_BASE_URL", "")

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
        api_base_url: str = DEFAULT_API_BASE_URL,
    ) -> None:
        self.base_url = base_url.rstrip("/")
        self.topic = topic
        self.secret = secret
        self._client = client
        # Public origin of this backend. Action buttons are only emitted when
        # it is known; otherwise they would point at ntfy.sh and never work.
        self.api_base_url = api_base_url.rstrip("/") if api_base_url else ""

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
            "Priority": self._priority(state),
        }
        if actions:
            # ntfy header-based publishing: the raw body is the message text
            # and the Actions header carries the click-to-act buttons.
            headers["Actions"] = self._actions_header(actions)
        body = message.encode("utf-8")

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
        title = notification_title(state, context)
        message = notification_text(state, context)

        schedule_id = context.get("schedule_id")
        db_schedule_id = context.get("db_schedule_id")
        meeting_no = context.get("meeting_no")
        base_payload: dict[str, Any] = {}
        if schedule_id is not None:
            base_payload["schedule_id"] = schedule_id
        if db_schedule_id is not None:
            base_payload["db_schedule_id"] = db_schedule_id
        if meeting_no is not None:
            base_payload["meeting_no"] = meeting_no

        actions: list[dict[str, str]] = []

        if not self.api_base_url or state not in ACTIONABLE_STATES:
            # Without a resolvable backend origin, action buttons would point
            # at ntfy.sh and never work; send a plain notification instead.
            # Non-actionable states carry no buttons either.
            return title, message, actions

        # "Presensi Sekarang" - direct presence confirmation. Omitted when the
        # payload has no Simkuliah jadwal id, because confirm_presence cannot
        # act on the Supabase id.
        if base_payload.get("schedule_id") is not None:
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

    def _priority(self, state: NotificationLevel) -> str:
        # Shared priority policy: only lecturer-opened and urgent-closing are
        # elevated; ntfy "urgent" drives alarm-grade delivery in the app.
        return {
            Priority.NORMAL: "default",
            Priority.HIGH: "urgent",
        }[priority_for_state(state)]

    def _action_url(self, action: str) -> str:
        # Webhook endpoint that verifies the signed token and acts. Targets
        # this backend's public origin, never the ntfy relay.
        return f"{self.api_base_url}/api/v1/webhook/action"

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
