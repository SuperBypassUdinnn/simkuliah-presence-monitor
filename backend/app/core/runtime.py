"""Purpose: Process-wide runtime singletons shared by routers and the lifespan.
Data & Logic Flow: main.py builds the AdaptivePoller and registers it here at import time; the health router reads it to report Simkuliah sync status without importing main (which would create a circular import).
Key Components: set_poller, get_poller
"""

from __future__ import annotations

from typing import TYPE_CHECKING, Optional

if TYPE_CHECKING:
    from app.services.poller import AdaptivePoller

_poller: Optional["AdaptivePoller"] = None


def set_poller(poller: Optional["AdaptivePoller"]) -> None:
    """Register the process-wide poller singleton."""
    global _poller
    _poller = poller


def get_poller() -> Optional["AdaptivePoller"]:
    """Return the registered poller, or ``None`` when nothing registered one."""
    return _poller
