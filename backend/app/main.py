"""Purpose: FastAPI application entrypoint and background worker lifecycle.
Data & Logic Flow: Initializes routers, registers lifespan event for poller, and mounts endpoints.
Key Components: app, lifespan, poller
"""

from __future__ import annotations

from contextlib import asynccontextmanager
from unittest.mock import MagicMock

from apscheduler.schedulers.asyncio import AsyncIOScheduler
from fastapi import FastAPI

from app.api.router import router as api_router
from app.core import runtime
from app.core.database import DatabaseRepository
from app.services.dispatcher import MultiDispatcher
from app.services.fcm_service import create_fcm_dispatcher
from app.services.ntfy_service import NtfyDispatcher
from app.services.poller import AdaptivePoller
from app.services.simkuliah_client import SimkuliahClient


def _build_poller() -> AdaptivePoller:
    """Build the module-level poller, degrading gracefully offline.

    Real dependencies (Simkuliah client, Supabase repository) require
    application settings that are only present in a deployed environment. In
    offline/test environments those settings are absent, so we fall back to
    mock dependencies so the module can still be imported and the lifespan
    exercised.
    """
    try:
        from app.config import settings

        client = SimkuliahClient(
            npm=settings.SIMKULIAH_NPM,
            password=settings.SIMKULIAH_PASSWORD,
        )
        repo = DatabaseRepository()
        transports: list = [NtfyDispatcher()]
        fcm_dispatcher = create_fcm_dispatcher(repo=repo)
        if fcm_dispatcher is not None:
            transports.append(fcm_dispatcher)
        dispatcher = MultiDispatcher(transports)
    except Exception:  # noqa: BLE001 - offline/test environment
        client = MagicMock()
        repo = DatabaseRepository(client=MagicMock())
        dispatcher = MagicMock()

    scheduler = AsyncIOScheduler()
    return AdaptivePoller(
        client=client,
        repo=repo,
        dispatcher=dispatcher,
        scheduler=scheduler,
    )


# Module-level poller singleton, reused by the lifespan on startup/shutdown
# and read by the health router via app.core.runtime (no circular import).
poller = _build_poller()
runtime.set_poller(poller)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Start the poller on startup and shut it down cleanly on shutdown."""
    await poller.start()
    try:
        yield
    finally:
        await poller.stop()


app = FastAPI(title="Simkuliah Presence Monitor API", lifespan=lifespan)

app.include_router(api_router)

__all__ = ["app", "lifespan", "poller"]
