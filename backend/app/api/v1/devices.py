"""Device push-token registration endpoints for Firebase Cloud Messaging.

The Flutter client registers its FCM token on startup (and on token rotation)
so the backend can address it. Registration is idempotent: re-registering an
existing token refreshes ``last_seen_at`` instead of duplicating the row.
"""

from __future__ import annotations

from fastapi import APIRouter
from pydantic import BaseModel, Field

from app.core.database import DatabaseRepository

router = APIRouter(prefix="/devices", tags=["devices"])

# Injectable dependency (replaced by tests with a MagicMock).
db_repo: DatabaseRepository | None = None


def _get_db() -> DatabaseRepository:
    global db_repo
    if db_repo is None:
        db_repo = DatabaseRepository()
    return db_repo


class DeviceRegistration(BaseModel):
    """Body of ``POST /api/v1/devices/register``."""

    token: str = Field(min_length=1, max_length=4096)
    platform: str = Field(default="android", pattern="^(android|ios|web)$")


class DeviceRemoval(BaseModel):
    """Body of ``POST /api/v1/devices/unregister``."""

    token: str = Field(min_length=1, max_length=4096)


@router.post("/register")
async def register_device(payload: DeviceRegistration) -> dict:
    """Register or refresh a device push token."""
    repo = _get_db()
    await repo.upsert_device_token(payload.token, payload.platform)
    return {"code": 200, "message": "Device registered successfully", "data": None}


@router.post("/unregister")
async def unregister_device(payload: DeviceRemoval) -> dict:
    """Remove a device push token from the registry."""
    repo = _get_db()
    await repo.delete_device_token(payload.token)
    return {"code": 200, "message": "Device unregistered successfully", "data": None}
