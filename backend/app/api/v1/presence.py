"""Purpose: Interactive presence confirmation endpoint for Flutter clients.
Data & Logic Flow: Receives POST /api/v1/presence/confirm with a meeting_id,
delegates to confirm_meeting_on_simkuliah (which verifies the live Simkuliah
card, submits the 7-field AJAX confirmation, and updates Supabase only on
success), and maps domain errors to clean HTTP status codes.
Key Components: PresenceConfirmRequest, confirm_presence_endpoint
"""

from __future__ import annotations

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from app.config import settings
from app.core import runtime
from app.core.database import DatabaseRepository
from app.services.presence_confirmer import (
    PresenceConfirmError,
    confirm_meeting_on_simkuliah,
)
from app.services.simkuliah_client import SimkuliahClient

router = APIRouter(prefix="/presence", tags=["presence"])

# Injectable dependencies (replaced by tests with mocks).
db_repo: DatabaseRepository | None = None
simkuliah_client: SimkuliahClient | None = None


def _get_db() -> DatabaseRepository:
    global db_repo
    if db_repo is None:
        db_repo = DatabaseRepository()
    return db_repo


def _get_client() -> SimkuliahClient:
    global simkuliah_client
    if simkuliah_client is not None:
        return simkuliah_client
    poller = runtime.get_poller()
    if poller is not None and hasattr(poller, "client"):
        return poller.client
    simkuliah_client = SimkuliahClient(
        npm=settings.SIMKULIAH_NPM,
        password=settings.SIMKULIAH_PASSWORD,
    )
    return simkuliah_client


class PresenceConfirmRequest(BaseModel):
    """Body of ``POST /api/v1/presence/confirm``."""

    meeting_id: int


@router.post("/confirm")
async def confirm_presence_endpoint(body: PresenceConfirmRequest) -> dict[str, object]:
    """Confirm attendance against Simkuliah for ``body.meeting_id``."""
    try:
        return await confirm_meeting_on_simkuliah(
            client=_get_client(),
            repo=_get_db(),
            meeting_id=body.meeting_id,
        )
    except PresenceConfirmError as exc:
        raise HTTPException(status_code=exc.status_code, detail=exc.detail) from exc
