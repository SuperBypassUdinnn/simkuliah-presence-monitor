"""Tests for the action webhook API and health endpoint.

Covers:
    * valid action token execution (confirm_presence + mark_override)
    * missing / invalid / expired token rejection (401)
    * idempotency: duplicate action calls return success cleanly
    * GET /api/v1/health returns ok status

All external calls (Supabase, Simkuliah HTTP) are mocked so tests run offline
and deterministically.
"""

from __future__ import annotations

import os
from unittest.mock import AsyncMock, MagicMock

import pytest

# Application configuration requires environment variables at import time, so
# seed them before importing app.main (which imports the API router -> webhooks
# -> app.config.settings).
os.environ.setdefault("SIMKULIAH_NPM", "2408107010053")
os.environ.setdefault("SIMKULIAH_PASSWORD", "test_password")
os.environ.setdefault("NTFY_TOPIC", "test-topic")
os.environ.setdefault("ACTION_SECRET_KEY", "test-secret-key-32-chars-long-123456")
os.environ.setdefault("SUPABASE_URL", "https://example.supabase.co")
os.environ.setdefault("SUPABASE_SERVICE_ROLE_KEY", "service-role-key")

from app.core.security import create_action_token
from app.main import app

SECRET = "test-secret-key-32-chars-long-123456"


def _client():
    from httpx import ASGITransport, AsyncClient

    transport = ASGITransport(app=app)
    return AsyncClient(transport=transport, base_url="http://test")


@pytest.mark.asyncio
async def test_webhook_action_valid_token_confirm_presence():
    from app.api.v1 import webhooks

    webhooks.db_repo = MagicMock()
    webhooks.simkuliah_client = MagicMock()
    webhooks.simkuliah_client.confirm_presence = AsyncMock(return_value=True)
    webhooks._processed_tokens.clear()

    payload = {
        "action": "confirm_presence",
        "schedule_id": 101,
        "meeting_no": 4,
    }
    token = create_action_token(payload, secret=SECRET, expires_in_seconds=300)

    async with _client() as ac:
        response = await ac.post(
            "/api/v1/webhook/action",
            headers={"X-Action-Token": token},
            json=payload,
        )

    assert response.status_code == 200
    assert response.json()["status"] == "success"


@pytest.mark.asyncio
async def test_webhook_action_valid_token_mark_override():
    from app.api.v1 import webhooks

    webhooks.db_repo = MagicMock()
    webhooks.db_repo.save_override = AsyncMock()
    webhooks.simkuliah_client = MagicMock()
    webhooks._processed_tokens.clear()

    payload = {
        "action": "mark_override",
        "meeting_id": 42,
        "override_type": "izin",
    }
    token = create_action_token(payload, secret=SECRET, expires_in_seconds=300)

    async with _client() as ac:
        response = await ac.post(
            "/api/v1/webhook/action",
            headers={"X-Action-Token": token},
            json=payload,
        )

    assert response.status_code == 200
    assert response.json()["status"] == "success"
    webhooks.db_repo.save_override.assert_called_once_with(
        meeting_id=42, override_type="izin", note=""
    )


@pytest.mark.asyncio
async def test_webhook_action_missing_token():
    async with _client() as ac:
        response = await ac.post(
            "/api/v1/webhook/action",
            json={"action": "confirm_presence"},
        )
    assert response.status_code == 401


@pytest.mark.asyncio
async def test_webhook_action_invalid_token():
    async with _client() as ac:
        response = await ac.post(
            "/api/v1/webhook/action",
            headers={"X-Action-Token": "tampered_token"},
            json={"action": "confirm_presence"},
        )
    assert response.status_code == 401


@pytest.mark.asyncio
async def test_webhook_action_expired_token():
    from app.api.v1 import webhooks

    webhooks.db_repo = MagicMock()
    webhooks.simkuliah_client = MagicMock()
    webhooks._processed_tokens.clear()

    payload = {"action": "confirm_presence", "schedule_id": 1, "meeting_no": 1}
    token = create_action_token(payload, secret=SECRET, expires_in_seconds=-10)

    async with _client() as ac:
        response = await ac.post(
            "/api/v1/webhook/action",
            headers={"X-Action-Token": token},
            json=payload,
        )
    assert response.status_code == 401


@pytest.mark.asyncio
async def test_webhook_action_idempotency_duplicate_returns_success():
    from app.api.v1 import webhooks

    calls = {"n": 0}

    async def fake_confirm(*a, **k):
        calls["n"] += 1
        return True

    webhooks.db_repo = MagicMock()
    webhooks.simkuliah_client = MagicMock()
    webhooks.simkuliah_client.confirm_presence = fake_confirm
    webhooks._processed_tokens.clear()

    payload = {
        "action": "confirm_presence",
        "schedule_id": 7,
        "meeting_no": 2,
    }
    token = create_action_token(payload, secret=SECRET, expires_in_seconds=300)

    async with _client() as ac:
        first = await ac.post(
            "/api/v1/webhook/action",
            headers={"X-Action-Token": token},
            json=payload,
        )
        second = await ac.post(
            "/api/v1/webhook/action",
            headers={"X-Action-Token": token},
            json=payload,
        )

    assert first.status_code == 200
    assert second.status_code == 200
    assert first.json()["status"] == "success"
    assert second.json()["status"] == "success"
    # The presence call must only happen once despite two identical requests.
    assert calls["n"] == 1


@pytest.mark.asyncio
async def test_health_endpoint():
    async with _client() as ac:
        response = await ac.get("/api/v1/health")

    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "ok"
    assert body["service"] == "simkuliah-presence-monitor"
