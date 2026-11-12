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


def _open_card_html(schedule_id: int, course_code: str = "SINF3031", meeting_no: int = 4) -> str:
    return f"""
<div class="card">
  <div class="card-header"><h5>Absensi Kelas C | {course_code} - KECERDASAN ARTIFISIAL | Pertemuan ke-{meeting_no} | SKS Mengajar : 2</h5></div>
  <div class="card-block">
    <table><tbody>
      <tr><td>C</td><td>Gedung MIPA</td><td>E.03.05</td><td>09.50 - 11.30</td><td>10:31</td></tr>
    </tbody></table>
    <button id="konfirmasi-kehadiran-{schedule_id}">Konfirmasi Kehadiran</button>
  </div>
</div>
<script>
$("#konfirmasi-kehadiran-{schedule_id}").on("click", function() {{
  swal({{}}, function() {{
    var kelas = 'C';
    var kd_mt_kul_8 = '{course_code}';
    var jadwal_mulai = '12-11-2026 09:50:00';
    var jadwal_berakhir = '12-11-2026 11:30:59';
    var pertemuan = '{meeting_no}';
    var sks_mengajar = '2';
    var id = '{schedule_id}';
  }});
}});
</script>
"""


@pytest.mark.asyncio
async def test_webhook_action_valid_token_confirm_presence():
    from app.api.v1 import webhooks

    webhooks.db_repo = MagicMock()
    webhooks.db_repo.resolve_meeting_id = AsyncMock(return_value=57)
    webhooks.db_repo.get_meeting_context = AsyncMock(
        return_value={
            "id": 57,
            "schedule_id": 4,
            "meeting_number": 4,
            "schedules": {"id": 4, "course_code": "SINF3031", "class_group": "C"},
        }
    )
    webhooks.db_repo.mark_meeting_present = AsyncMock()
    webhooks.simkuliah_client = MagicMock()
    webhooks.simkuliah_client.is_authenticated = True
    webhooks.simkuliah_client.fetch_dashboard = AsyncMock(
        return_value=_open_card_html(101, "SINF3031", 4)
    )
    webhooks.simkuliah_client.confirm_presence = AsyncMock(return_value=True)
    webhooks._processed_tokens.clear()

    payload = {
        "action": "confirm_presence",
        "schedule_id": 101,
        "db_schedule_id": 4,
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
    webhooks.simkuliah_client.confirm_presence.assert_awaited_once()
    kwargs = webhooks.simkuliah_client.confirm_presence.call_args.kwargs
    assert kwargs["kelas"] == "C"
    assert kwargs["kd_mt_kul8"] == "SINF3031"
    assert kwargs["jadwal_mulai"] == "12-11-2026 09:50:00"
    webhooks.db_repo.mark_meeting_present.assert_awaited_once_with(57)


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
async def test_webhook_override_prefers_db_schedule_id_over_simkuliah_id():
    """The signed payload carries Simkuliah's jadwal id in ``schedule_id``
    and the Supabase id in ``db_schedule_id``; the override must resolve the
    meetings row with the Supabase id only."""
    from app.api.v1 import webhooks

    webhooks.db_repo = MagicMock()
    webhooks.db_repo.save_override = AsyncMock()
    webhooks.db_repo.resolve_meeting_id = AsyncMock(return_value=127)
    webhooks.simkuliah_client = MagicMock()
    webhooks._processed_tokens.clear()

    payload = {
        "action": "mark_override",
        "override_type": "sakit",
        "schedule_id": 6220432,
        "db_schedule_id": 9,
        "meeting_no": 11,
    }
    token = create_action_token(payload, secret=SECRET, expires_in_seconds=300)

    async with _client() as ac:
        response = await ac.post(
            "/api/v1/webhook/action",
            headers={"X-Action-Token": token},
            json=payload,
        )

    assert response.status_code == 200
    webhooks.db_repo.resolve_meeting_id.assert_called_once_with(9, 11)
    webhooks.db_repo.save_override.assert_called_once_with(
        meeting_id=127, override_type="sakit", note=""
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
    webhooks.db_repo.resolve_meeting_id = AsyncMock(return_value=12)
    webhooks.db_repo.get_meeting_context = AsyncMock(
        return_value={
            "id": 12,
            "schedule_id": 1,
            "meeting_number": 2,
            "schedules": {"id": 1, "course_code": "SINF3031", "class_group": "C"},
        }
    )
    webhooks.db_repo.mark_meeting_present = AsyncMock()
    webhooks.simkuliah_client = MagicMock()
    webhooks.simkuliah_client.is_authenticated = True
    webhooks.simkuliah_client.fetch_dashboard = AsyncMock(
        return_value=_open_card_html(7, "SINF3031", 2)
    )
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
    # Offline test builds register a real AdaptivePoller with mock deps that
    # never ran a tick, so the upstream status is "pending", not a failure.
    assert body["simkuliah_status"] == "pending"
    assert isinstance(body["last_tick"], dict)


@pytest.mark.asyncio
async def test_health_reports_degraded_while_simkuliah_failing():
    from app.core import runtime
    from app.services.poller import AdaptivePoller

    original = runtime.get_poller()
    poller = AdaptivePoller(
        client=MagicMock(),
        repo=MagicMock(),
        dispatcher=MagicMock(),
        scheduler=MagicMock(),
    )
    poller.consecutive_failures = 2
    runtime.set_poller(poller)
    try:
        async with _client() as ac:
            response = await ac.get("/api/v1/health")
    finally:
        runtime.set_poller(original)

    assert response.status_code == 200
    assert response.json()["simkuliah_status"] == "degraded"


@pytest.mark.asyncio
async def test_health_reports_ok_after_successful_sync():
    from datetime import datetime

    from app.core import runtime
    from app.services.poller import AdaptivePoller

    original = runtime.get_poller()
    poller = AdaptivePoller(
        client=MagicMock(),
        repo=MagicMock(),
        dispatcher=MagicMock(),
        scheduler=MagicMock(),
    )
    poller.last_success_at = datetime.now()
    runtime.set_poller(poller)
    try:
        async with _client() as ac:
            response = await ac.get("/api/v1/health")
    finally:
        runtime.set_poller(original)

    assert response.status_code == 200
    assert response.json()["simkuliah_status"] == "ok"
    assert response.json()["synced_now"] is False


@pytest.mark.asyncio
async def test_health_sync_flag_wakes_stale_poller():
    from app.core import runtime
    from app.services.poller import AdaptivePoller

    original = runtime.get_poller()
    poller = AdaptivePoller(
        client=MagicMock(),
        repo=MagicMock(),
        dispatcher=MagicMock(),
        scheduler=MagicMock(),
    )
    poller.trigger_if_stale = AsyncMock(return_value=True)
    runtime.set_poller(poller)
    try:
        async with _client() as ac:
            plain = await ac.get("/api/v1/health")
            poller.trigger_if_stale.assert_not_awaited()
            assert plain.json()["synced_now"] is False

            woken = await ac.get("/api/v1/health?sync=true")
            poller.trigger_if_stale.assert_awaited_once_with(max_age_seconds=30)
            assert woken.json()["synced_now"] is True
    finally:
        runtime.set_poller(original)
