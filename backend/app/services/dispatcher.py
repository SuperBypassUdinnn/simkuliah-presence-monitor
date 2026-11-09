"""Purpose: Composite notification dispatcher fanning out to multiple transports.
Data & Logic Flow: Forwards each notification state to every registered dispatcher and succeeds when at least one transport accepts.
Key Components: MultiDispatcher
"""

from __future__ import annotations

import logging
from typing import Any

from app.services.state_machine import NotificationLevel

logger = logging.getLogger(__name__)


class MultiDispatcher:
    """Fan out notifications to several transports independently.

    Each dispatcher receives every state; a failure or disabled transport
    never suppresses the others. ``dispatch`` returns ``True`` when at least
    one transport accepted the notification.
    """

    def __init__(self, dispatchers: list[Any]) -> None:
        self.dispatchers = dispatchers

    def dispatch(self, state: NotificationLevel, context: dict) -> bool:
        delivered = False
        for dispatcher in self.dispatchers:
            try:
                if dispatcher.dispatch(state, context):
                    delivered = True
            except Exception as exc:  # noqa: BLE001 - isolate transport failures
                logger.warning(
                    "dispatcher %s failed for %s: %s",
                    type(dispatcher).__name__,
                    state.value,
                    exc,
                )
        return delivered
