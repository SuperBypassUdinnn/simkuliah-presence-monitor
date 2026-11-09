"""Purpose: Firebase Cloud Messaging dispatcher for native Android push.
Data & Logic Flow: Loads registered device tokens, applies the shared priority policy, and sends the presence payload through the FCM v1 API.
Key Components: FcmDispatcher, create_fcm_dispatcher
"""

from __future__ import annotations

import json
import logging
from datetime import timedelta
from typing import Any, Callable

from app.core.security import create_action_token
from app.services.state_machine import NotificationLevel, Priority, priority_for_state

logger = logging.getLogger(__name__)

# Signed action tokens live for 15 minutes, mirroring the ntfy dispatcher.
_ACTION_TOKEN_TTL_SECONDS = 900

# Maximum number of registered devices addressed in one multicast batch.
_MAX_TOKENS_PER_BATCH = 500

# FCM error codes that indicate the token is permanently unusable.
_PERMANENT_TOKEN_ERRORS = ("unregistered", "invalid-registration", "not-registered")


class FcmDispatcher:
    """Dispatch presence notifications to Android devices through FCM.

    Args:
        token_provider: Zero-argument callable returning the currently
            registered device tokens.
        credentials_path: Path to the Firebase service-account JSON. When
            falsy (and no ``send_fn`` is injected), the dispatcher is disabled
            and :meth:`dispatch` is a safe no-op.
        send_fn: Optional test injection point with the signature
            ``(tokens, title, message, data, android_priority) ->
            list[str | None]`` where each element is ``None`` on success or
            the FCM error code for that token.
        token_remover: Optional callable invoked with the tokens FCM reported
            as permanently unregistered.
        data_only: When ``True``, omit the ``notification`` block and send a
            pure data message so the client fully controls rendering.
    """

    def __init__(
        self,
        token_provider: Callable[[], list[str]] | None = None,
        credentials_path: str | None = None,
        send_fn: Callable[..., list[str | None]] | None = None,
        token_remover: Callable[[list[str]], None] | None = None,
        data_only: bool = False,
        secret: str | None = None,
    ) -> None:
        if secret is None:
            secret = self._default_secret()
        self._token_provider = token_provider
        self._credentials_path = credentials_path
        self._send_fn = send_fn
        self._token_remover = token_remover
        self._data_only = data_only
        self._secret = secret
        self._messaging: Any = None

    # ------------------------------------------------------------------ #
    # Public API
    # ------------------------------------------------------------------ #

    def dispatch(self, state: NotificationLevel, context: dict) -> bool:
        """Dispatch a notification for ``state`` with the given ``context``.

        Returns ``True`` when at least one device accepted the message,
        ``False`` otherwise (including when disabled or no devices exist).
        """
        if self._send_fn is None and not self._credentials_path:
            logger.debug("FCM dispatch skipped: no credentials configured")
            return False
        if self._token_provider is None:
            logger.debug("FCM dispatch skipped: no token provider")
            return False

        tokens = list(self._token_provider() or [])[:_MAX_TOKENS_PER_BATCH]
        if not tokens:
            logger.info("FCM dispatch skipped: no registered devices")
            return False

        title, message, data = self._build_payload(state, context)
        android_priority = self._android_priority(state)
        try:
            results = self._send(tokens, title, message, data, android_priority)
        except Exception as exc:  # noqa: BLE001 - network failure means no dispatch
            logger.warning("FCM dispatch failed: %s", exc)
            return False

        self._prune_dead_tokens(tokens, results)
        sent = sum(1 for result in results if result is None)
        logger.info(
            "FCM dispatch: %d/%d delivered (state=%s, priority=%s)",
            sent,
            len(tokens),
            state.value,
            android_priority,
        )
        return sent > 0

    # ------------------------------------------------------------------ #
    # Payload construction
    # ------------------------------------------------------------------ #

    def _build_payload(
        self, state: NotificationLevel, context: dict
    ) -> tuple[str, str, dict[str, str]]:
        course = context.get("course_code", "Kelas")
        room = context.get("room", "")
        lecturer = context.get("lecturer", "")

        title = f"Presensi {course}".strip()
        message = self._message_text(state, course, room, lecturer)

        schedule_id = context.get("schedule_id")
        meeting_no = context.get("meeting_no")
        base_payload: dict[str, Any] = {"action_kind": state.value}
        if schedule_id is not None:
            base_payload["schedule_id"] = schedule_id
        if meeting_no is not None:
            base_payload["meeting_no"] = meeting_no

        data = {
            key: str(value)
            for key, value in {
                **base_payload,
                "course_code": course,
                "course_name": context.get("course_name", ""),
                "room": room,
                "lecturer": lecturer,
                "actions": json.dumps(self._build_actions(base_payload)),
            }.items()
        }
        return title, message, data

    def _build_actions(self, base_payload: dict[str, Any]) -> list[dict[str, str]]:
        """Signed action buttons, rendered natively by the Android client."""
        confirm = dict(base_payload, action="confirm_presence")
        actions = [
            {
                "label": "Presensi Sekarang",
                "action": "confirm_presence",
                "token": self._sign(confirm),
            }
        ]
        for label, override_type in (("Izin", "izin"), ("Sakit", "sakit")):
            override = dict(base_payload, action="mark_override", override_type=override_type)
            actions.append(
                {
                    "label": label,
                    "action": "mark_override",
                    "token": self._sign(override),
                }
            )
        return actions

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

    def _sign(self, payload: dict[str, Any]) -> str:
        return create_action_token(
            payload, secret=self._secret, expires_in_seconds=_ACTION_TOKEN_TTL_SECONDS
        )

    @staticmethod
    def _android_priority(state: NotificationLevel) -> str:
        return "high" if priority_for_state(state) is Priority.HIGH else "normal"

    # ------------------------------------------------------------------ #
    # Transport
    # ------------------------------------------------------------------ #

    def _send(
        self,
        tokens: list[str],
        title: str,
        message: str,
        data: dict[str, str],
        android_priority: str,
    ) -> list[str | None]:
        if self._send_fn is not None:
            return self._send_fn(tokens, title, message, data, android_priority)
        return self._send_via_firebase(tokens, title, message, data, android_priority)

    def _send_via_firebase(
        self,
        tokens: list[str],
        title: str,
        message: str,
        data: dict[str, str],
        android_priority: str,
    ) -> list[str | None]:
        messaging = self._ensure_messaging()
        android_config = messaging.AndroidConfig(
            priority=android_priority,
            ttl=timedelta(seconds=_ACTION_TOKEN_TTL_SECONDS),
        )
        multicast = messaging.MulticastMessage(
            tokens=tokens,
            data=data,
            android=android_config,
        )
        if not self._data_only:
            multicast.notification = messaging.Notification(title=title, body=message)
        batch = messaging.send_each_for_multicast(multicast)
        return [self._error_code(response) for response in batch.responses]

    def _ensure_messaging(self) -> Any:
        if self._messaging is None:
            import firebase_admin
            from firebase_admin import credentials, messaging

            try:
                firebase_admin.get_app()
            except ValueError:
                firebase_admin.initialize_app(credentials.Certificate(self._credentials_path))
            self._messaging = messaging
        return self._messaging

    @staticmethod
    def _error_code(response: Any) -> str | None:
        if response.success:
            return None
        exception = response.exception
        code = getattr(exception, "code", None)
        if code:
            return str(code)
        return str(exception)

    def _prune_dead_tokens(self, tokens: list[str], results: list[str | None]) -> None:
        dead = [
            token
            for token, result in zip(tokens, results)
            if result is not None
            and any(marker in result.lower() for marker in _PERMANENT_TOKEN_ERRORS)
        ]
        if dead and self._token_remover is not None:
            logger.info("Pruning %d unregistered FCM token(s)", len(dead))
            self._token_remover(dead)

    # ------------------------------------------------------------------ #
    # Defaults
    # ------------------------------------------------------------------ #

    @staticmethod
    def _default_secret() -> str:
        try:
            from app.config import settings

            return settings.ACTION_SECRET_KEY
        except Exception:  # noqa: BLE001 - offline/test environment
            return "change-me-in-production"


def create_fcm_dispatcher(repo: Any | None = None) -> FcmDispatcher | None:
    """Build an :class:`FcmDispatcher` from application settings.

    Returns ``None`` when Firebase credentials are not configured, so callers
    can simply omit the transport.
    """
    try:
        from app.config import settings

        if not settings.FIREBASE_CREDENTIALS_PATH:
            return None
        if repo is None:
            from app.core.database import DatabaseRepository

            repo = DatabaseRepository()
        return FcmDispatcher(
            token_provider=repo.list_device_tokens_sync,
            credentials_path=settings.FIREBASE_CREDENTIALS_PATH,
            token_remover=repo.prune_device_tokens_sync,
            data_only=settings.FCM_DATA_ONLY,
        )
    except Exception as exc:  # noqa: BLE001 - degraded environments
        logger.warning("FCM dispatcher unavailable: %s", exc)
        return None
