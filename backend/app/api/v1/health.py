"""Health endpoint for the Simkuliah Presence Monitor backend."""

from __future__ import annotations

from fastapi import APIRouter

router = APIRouter()

SERVICE_NAME = "simkuliah-presence-monitor"


@router.get("/health")
async def health() -> dict[str, str]:
    """Return the backend health status.

    Returns:
        ``{"status": "ok", "service": "simkuliah-presence-monitor"}``.
    """
    return {"status": "ok", "service": SERVICE_NAME}
