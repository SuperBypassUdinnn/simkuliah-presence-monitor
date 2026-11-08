"""FastAPI application for the Simkuliah Presence Monitor API.

Mounts the aggregated API router so all version-1 endpoints live at
``/api/v1/...``.
"""

from __future__ import annotations

from fastapi import FastAPI

from app.api.router import router as api_router

app = FastAPI(title="Simkuliah Presence Monitor API")

app.include_router(api_router)

__all__ = ["app"]
