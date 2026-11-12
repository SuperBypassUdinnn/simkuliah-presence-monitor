"""Purpose: Tests for interactive Simkuliah presence confirmation and 7-field AJAX parsing.
Data & Logic Flow: Exercises parse_attendance_cards script extraction,
confirm_meeting_on_simkuliah session/retry/error guards, and POST /api/v1/presence/confirm.
Key Components: test_confirm_presence_endpoint_submits_7_fields, test_confirm_presence_closed_card_never_marks_hadir
"""

from __future__ import annotations

import os
from unittest.mock import AsyncMock, MagicMock

import pytest

os.environ.setdefault("SIMKULIAH_NPM", "2408107010053")
os.environ.setdefault("SIMKULIAH_PASSWORD", "test_password")
os.environ.setdefault("NTFY_TOPIC", "test-topic")
os.environ.setdefault("ACTION_SECRET_KEY", "test-secret-key-32-chars-long-123456")
os.environ.setdefault("SUPABASE_URL", "https://example.supabase.co")
os.environ.setdefault("SUPABASE_SERVICE_ROLE_KEY", "service-role-key")

from app.main import app  # noqa: E402
from app.services.simkuliah_parser import parse_attendance_cards  # noqa: E402

_REALISTIC_OPEN_HTML = """
<div class="card">
  <div class="card-header">
    <h5>Absensi Kelas C | SINF3031 - KECERDASAN ARTIFISIAL | Pertemuan ke-13 | SKS Mengajar : 2</h5>
  </div>
  <div class="card-block">
    <p>Anda belum absen</p>
    <table><tbody>
      <tr><td>C</td><td>Gedung MIPA</td><td>E.03.05</td><td>09.50 - 11.30</td><td>10:31</td></tr>
    </tbody></table>
    <button class="btn btn-success" id="konfirmasi-kehadiran-7319575">Konfirmasi Kehadiran</button>
  </div>
</div>
<script>
$(function() {
  $("#konfirmasi-kehadiran-7319575").on("click", function() {
    swal({title: "Konfirmasi kehadiran?"}, function() {
      var kelas = 'C';
      var kd_mt_kul_8 = 'SINF3031';
      var jadwal_mulai = '12-11-2026 09:50:00';
      var jadwal_berakhir = '12-11-2026 11:30:59';
      var pertemuan = '13';
      var sks_mengajar = '2';
      var id = '7319575';
    });
  });
});
</script>
"""


def _client():
    from httpx import ASGITransport, AsyncClient

    return AsyncClient(transport=ASGITransport(app=app), base_url="http://test")


def _mock_repo(found: bool = True) -> MagicMock:
    repo = MagicMock()
    if found:
        repo.get_meeting_context = AsyncMock(
            return_value={
                "id": 57,
                "schedule_id": 4,
                "meeting_number": 13,
                "simkuliah_status": "pending",
                "schedules": {
                    "id": 4,
                    "course_code": "SINF3031",
                    "class_group": "C",
                },
            }
        )
    else:
        repo.get_meeting_context = AsyncMock(return_value=None)
    repo.mark_meeting_present = AsyncMock()
    return repo


def test_parser_extracts_7_field_ajax_payload():
    cards = parse_attendance_cards(_REALISTIC_OPEN_HTML)
    assert len(cards) == 1
    card = cards[0]
    assert card.is_open is True
    assert card.schedule_id == 7319575
    assert card.class_group == "C"
    assert card.course_code == "SINF3031"
    assert card.meeting_number == 13
    assert card.jadwal_mulai == "12-11-2026 09:50:00"
    assert card.jadwal_berakhir == "12-11-2026 11:30:59"
    assert card.sks_mengajar == "2"


@pytest.mark.asyncio
async def test_confirm_presence_endpoint_submits_7_fields():
    from app.api.v1 import presence

    presence.db_repo = _mock_repo()
    client = MagicMock()
    client.is_authenticated = False
    client.login = AsyncMock(return_value=True)
    client.fetch_dashboard = AsyncMock(return_value=_REALISTIC_OPEN_HTML)
    client.confirm_presence = AsyncMock(return_value=True)
    presence.simkuliah_client = client

    async with _client() as ac:
        resp = await ac.post("/api/v1/presence/confirm", json={"meeting_id": 57})

    assert resp.status_code == 200
    assert resp.json()["status"] == "success"
    client.login.assert_awaited_once()
    client.confirm_presence.assert_awaited_once_with(
        schedule_id=7319575,
        meeting_no=13,
        kelas="C",
        kd_mt_kul8="SINF3031",
        jadwal_mulai="12-11-2026 09:50:00",
        jadwal_berakhir="12-11-2026 11:30:59",
        sks_mengajar="2",
        presence_id="7319575",
    )
    presence.db_repo.mark_meeting_present.assert_awaited_once_with(57)


@pytest.mark.asyncio
async def test_confirm_presence_closed_card_never_marks_hadir():
    from app.api.v1 import presence

    presence.db_repo = _mock_repo()
    client = MagicMock()
    client.is_authenticated = True
    client.fetch_dashboard = AsyncMock(
        return_value=_REALISTIC_OPEN_HTML.replace("10:31", "Dosen belum absen")
    )
    client.confirm_presence = AsyncMock()
    presence.simkuliah_client = client

    async with _client() as ac:
        resp = await ac.post("/api/v1/presence/confirm", json={"meeting_id": 57})

    assert resp.status_code == 409
    client.confirm_presence.assert_not_awaited()
    presence.db_repo.mark_meeting_present.assert_not_awaited()


@pytest.mark.asyncio
async def test_confirm_presence_simkuliah_failure_never_marks_hadir():
    from app.api.v1 import presence

    presence.db_repo = _mock_repo()
    client = MagicMock()
    client.is_authenticated = True
    client.login = AsyncMock(return_value=True)
    client.fetch_dashboard = AsyncMock(return_value=_REALISTIC_OPEN_HTML)
    client.confirm_presence = AsyncMock(return_value=False)
    presence.simkuliah_client = client

    async with _client() as ac:
        resp = await ac.post("/api/v1/presence/confirm", json={"meeting_id": 57})

    assert resp.status_code == 502
    presence.db_repo.mark_meeting_present.assert_not_awaited()


@pytest.mark.asyncio
async def test_confirm_presence_already_present_syncs_db_without_posting():
    from app.api.v1 import presence

    presence.db_repo = _mock_repo()
    client = MagicMock()
    client.is_authenticated = True
    client.fetch_dashboard = AsyncMock(
        return_value=_REALISTIC_OPEN_HTML.replace("Anda belum absen", "Anda sudah absen")
    )
    client.confirm_presence = AsyncMock()
    presence.simkuliah_client = client

    async with _client() as ac:
        resp = await ac.post("/api/v1/presence/confirm", json={"meeting_id": 57})

    assert resp.status_code == 200
    assert resp.json()["already_present"] is True
    client.confirm_presence.assert_not_awaited()
    presence.db_repo.mark_meeting_present.assert_awaited_once_with(57)


@pytest.mark.asyncio
async def test_confirm_presence_unknown_meeting_returns_404():
    from app.api.v1 import presence

    presence.db_repo = _mock_repo(found=False)
    presence.simkuliah_client = MagicMock()

    async with _client() as ac:
        resp = await ac.post("/api/v1/presence/confirm", json={"meeting_id": 9999})

    assert resp.status_code == 404
