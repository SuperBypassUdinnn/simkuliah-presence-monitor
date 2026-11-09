"""Purpose: Unit tests for FCM device token registration endpoints.
Data & Logic Flow: Exercises register/unregister against an injected mock repository.
Key Components: devices router
"""

from __future__ import annotations

from unittest.mock import AsyncMock, MagicMock

from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.api.v1 import devices

app = FastAPI()
app.include_router(devices.router, prefix="/api/v1")
client = TestClient(app)


def test_register_device_upserts_token():
    repo = MagicMock()
    repo.upsert_device_token = AsyncMock(return_value=None)
    devices.db_repo = repo

    response = client.post(
        "/api/v1/devices/register",
        json={"token": "fcm-token-1", "platform": "android"},
    )

    assert response.status_code == 200
    assert response.json()["code"] == 200
    repo.upsert_device_token.assert_awaited_once_with("fcm-token-1", "android")


def test_unregister_device_deletes_token():
    repo = MagicMock()
    repo.delete_device_token = AsyncMock(return_value=None)
    devices.db_repo = repo

    response = client.post("/api/v1/devices/unregister", json={"token": "fcm-token-1"})

    assert response.status_code == 200
    repo.delete_device_token.assert_awaited_once_with("fcm-token-1")


def test_register_rejects_invalid_platform():
    repo = MagicMock()
    repo.upsert_device_token = AsyncMock(return_value=None)
    devices.db_repo = repo

    response = client.post(
        "/api/v1/devices/register",
        json={"token": "fcm-token-1", "platform": "windows-phone"},
    )

    assert response.status_code == 422
    repo.upsert_device_token.assert_not_awaited()


def test_register_requires_token():
    response = client.post("/api/v1/devices/register", json={"platform": "android"})

    assert response.status_code == 422
