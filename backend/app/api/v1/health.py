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
async def health(sync: bool = False) -> dict[str, object]:
    """Return the backend health status, waking a stale poller on demand.

    Pass ``?sync=true`` from interactive clients when opening or refreshing
    the app so a sleeping or newly woken Render container runs a fresh
    Simkuliah sync before the client reads Supabase. Plain ``/health`` stays
    instant for Render's liveness probe.

    Returns:
        ``{"status": "ok", "service": "simkuliah-presence-monitor",
        "simkuliah_status": "ok" | "degraded" | "pending" | "unknown",
        "synced_now": bool}``.
    """
    poller = runtime.get_poller()
    synced_now = False
    if sync and isinstance(poller, AdaptivePoller):
        try:
            synced_now = await poller.trigger_if_stale(max_age_seconds=30)
        except Exception:  # noqa: BLE001 - health probe must never 500
            synced_now = False

    payload: dict[str, object] = {
        "status": "ok",
        "service": SERVICE_NAME,
        "simkuliah_status": _simkuliah_status(),
        "synced_now": synced_now,
    }
    if isinstance(poller, AdaptivePoller):
        payload["last_tick"] = dict(poller.last_tick)
    return payload
