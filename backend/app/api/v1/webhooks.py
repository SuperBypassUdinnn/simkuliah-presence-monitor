"""Action webhook endpoints for ntfy action buttons and clients.

Exposes ``POST /api/v1/webhook/action`` which validates an
``X-Action-Token`` header using :func:`app.core.security.verify_action_token`
and then dispatches to either ``SimkuliahClient.confirm_presence`` or
``DatabaseRepository.save_override`` depending on the requested action.

An in-memory idempotency guard rejects repeated submissions of the same token
so duplicate ntfy action-button clicks return success cleanly without
re-processing the action.
"""

from __future__ import annotations

from fastapi import APIRouter, Header, HTTPException
from pydantic import BaseModel

from app.config import settings
from app.core.database import DatabaseRepository
from app.core.security import verify_action_token
from app.services.simkuliah_client import SimkuliahClient

router = APIRouter(prefix="/webhook")

_VALID_ACTIONS = {"confirm_presence", "mark_override", "set_override"}
_VALID_OVERRIDE_TYPES = {"izin", "sakit", "alpa"}

# In-memory idempotency store: action tokens already processed. Re-processing
# the same token returns success cleanly instead of re-executing the action.
_processed_tokens: set[str] = set()

# Injectable dependencies (replaced by tests with MagicMock).
db_repo: DatabaseRepository | None = None
simkuliah_client: SimkuliahClient | None = None


def _get_db() -> DatabaseRepository:
    global db_repo
    if db_repo is None:
        db_repo = DatabaseRepository()
    return db_repo


def _get_client() -> SimkuliahClient:
    global simkuliah_client
    if simkuliah_client is None:
        simkuliah_client = SimkuliahClient(
            npm=settings.SIMKULIAH_NPM,
            password=settings.SIMKULIAH_PASSWORD,
        )
    return simkuliah_client


class ActionRequest(BaseModel):
    """Body of ``POST /api/v1/webhook/action``."""

    action: str
    schedule_id: int | None = None
    meeting_no: int | None = None
    meeting_id: int | None = None
    override_type: str | None = None
    note: str = ""


@router.post("/action")
async def webhook_action(
    x_action_token: str | None = Header(default=None, alias="X-Action-Token"),
    body: ActionRequest | None = None,
) -> dict[str, str]:
    """Confirm presence or record an override for a course meeting.

    Args:
        x_action_token: HMAC-signed action token from the ``X-Action-Token``
            header.
        body: Action payload carrying ``action`` plus action-specific fields.

    Returns:
        A ``{"status": "success"}`` dict on successful processing.

    Raises:
        HTTPException(401): when the token is missing, invalid, or expired.
        HTTPException(400): when the action or override type is unknown.
    """
    if not x_action_token:
        raise HTTPException(status_code=401, detail="Missing X-Action-Token header")

    payload = verify_action_token(x_action_token, secret=settings.ACTION_SECRET_KEY)
    if payload is None:
        raise HTTPException(status_code=401, detail="Invalid or expired action token")

    # Idempotency guard: ignore duplicate submissions of the same token.
    if x_action_token in _processed_tokens:
        return {"status": "success"}

    action = (body.action if body else None) or payload.get("action")
    if action not in _VALID_ACTIONS:
        raise HTTPException(status_code=400, detail=f"Unknown action: {action!r}")

    if action == "confirm_presence":
        schedule_id = (body.schedule_id if body else None) or payload.get("schedule_id")
        meeting_no = (body.meeting_no if body else None) or payload.get("meeting_no")
        if schedule_id is None or meeting_no is None:
            raise HTTPException(
                status_code=400,
                detail="confirm_presence requires schedule_id and meeting_no",
            )
        client = _get_client()
        ok = await client.confirm_presence(schedule_id, meeting_no)
        if not ok:
            raise HTTPException(status_code=502, detail="Presence confirmation failed")

    elif action in ("mark_override", "set_override"):
        override_type = (body.override_type if body else None) or payload.get(
            "override_type"
        )
        meeting_id = (body.meeting_id if body else None) or payload.get("meeting_id")
        if override_type not in _VALID_OVERRIDE_TYPES:
            raise HTTPException(
                status_code=400, detail=f"Invalid override type: {override_type!r}"
            )
        if meeting_id is None:
            raise HTTPException(
                status_code=400, detail="mark_override requires meeting_id"
            )
        note = (body.note if body else "") or payload.get("note", "")
        repo = _get_db()
        await repo.save_override(
            meeting_id=meeting_id, override_type=override_type, note=note
        )

    # Mark the token as processed only after the action succeeds.
    _processed_tokens.add(x_action_token)
    return {"status": "success"}


# Expose for tests and introspection.
__all__ = ["_get_client", "_get_db", "_processed_tokens", "router"]
