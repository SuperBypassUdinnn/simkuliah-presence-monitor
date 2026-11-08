"""API router aggregating version-1 sub-routers under ``/api/v1``."""

from __future__ import annotations

from fastapi import APIRouter

from app.api.v1 import health, webhooks

router = APIRouter(prefix="/api/v1")

router.include_router(webhooks.router)
router.include_router(health.router)

__all__ = ["router"]
