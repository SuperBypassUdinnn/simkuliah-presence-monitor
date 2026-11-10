"""Health endpoint for the Simkuliah Presence Monitor backend."""

from __future__ import annotations

from fastapi import APIRouter

from app.core import runtime
from app.services.poller import AdaptivePoller

router = APIRouter()

SERVICE_NAME = "simkuliah-presence-monitor"


def _simkuliah_status() -> str:
    """Summarize the poller's view of the Simkuliah upstream.

    ``ok`` when the last sync cycle succeeded, ``degraded`` while fetches are
    failing (Simkuliah gateway down, captcha failures, network errors), and
    ``pending`` when the poller has not completed a cycle since startup. The
    deployed poller is always an :class:`AdaptivePoller`; anything else (test
    doubles, mock builds) reports ``unknown`` so clients never alarm on data
    they cannot trust.
    """
    poller = runtime.get_poller()
    if not isinstance(poller, AdaptivePoller):
        return "unknown"
    if poller.consecutive_failures > 0:
        return "degraded"
    if poller.last_success_at is None:
        return "pending"
    return "ok"


@router.get("/health")
async def health() -> dict[str, object]:
    """Return the backend health status.

    Returns:
        ``{"status": "ok", "service": "simkuliah-presence-monitor",
        "simkuliah_status": "ok" | "degraded" | "pending" | "unknown"}``.
        ``simkuliah_status`` mirrors the poller's last sync so clients can
        warn about stale presence data while the backend itself is healthy.
    """
    return {
        "status": "ok",
        "service": SERVICE_NAME,
        "simkuliah_status": _simkuliah_status(),
    }
