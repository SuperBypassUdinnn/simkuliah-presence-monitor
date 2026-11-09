"""Purpose: Unit tests for Supabase database repository operations.
Data & Logic Flow: Tests CRUD operations, retry wrappers, and override validation logic.
Key Components: test_override_suppression_logic, DatabaseRepository
"""

from __future__ import annotations

from datetime import datetime
from unittest.mock import MagicMock

import pytest

from app.core.database import DatabaseRepository
from app.models.schemas import OverrideType
from app.services.simkuliah_parser import ParsedMeetingStatus, ParsedScheduleItem


def test_override_type_enum_values():
    assert OverrideType.IZIN.value == "izin"
    assert OverrideType.SAKIT.value == "sakit"
    assert OverrideType.ALPA.value == "alpa"
    assert OverrideType.LUPA_ABSEN.value == "lupa_absen"
    assert OverrideType.DOSEN_TIDAK_ABSEN.value == "dosen_tidak_absen"


def test_is_valid_override_accepts_valid_types():
    repo = DatabaseRepository(client=MagicMock())
    assert repo.is_valid_override("izin") is True
    assert repo.is_valid_override("sakit") is True
    assert repo.is_valid_override("alpa") is True
    assert repo.is_valid_override("lupa_absen") is True
    assert repo.is_valid_override("dosen_tidak_absen") is True


def test_is_valid_override_rejects_invalid_types():
    repo = DatabaseRepository(client=MagicMock())
    assert repo.is_valid_override("invalid_status") is False
    assert repo.is_valid_override("") is False
    assert repo.is_valid_override("IZIN") is False
    assert repo.is_valid_override("izin ") is False


@pytest.mark.asyncio
async def test_upsert_schedules_calls_client():
    repo = DatabaseRepository(client=MagicMock())
    items = [
        ParsedScheduleItem(
            course_code="INF201",
            course_name="Grafika Komputer",
            room="Ruang 301",
            start_time="08:00",
            end_time="09:40",
            lecturer="Dr. Dosen, M.Kom",
        )
    ]
    await repo.upsert_schedules(items)

    repo.client.table.assert_called_with("schedules")
    repo.client.table().upsert.assert_called_once()
    repo.client.table().upsert().execute.assert_called_once()


@pytest.mark.asyncio
async def test_record_meeting_status_upserts_live_state():
    repo = DatabaseRepository(client=MagicMock())
    status = ParsedMeetingStatus(
        is_open=True,
        deadline_time="17:45:00",
        meeting_number=12,
        schedule_id=1042,
        is_student_present=True,
    )
    now = datetime(2026, 11, 9, 17, 20)
    await repo.record_meeting_status(status, now=now)

    repo.client.table.assert_called_with("meetings")
    repo.client.table().upsert.assert_called_once()
    payload = repo.client.table().upsert.call_args[0][0]
    assert payload["schedule_id"] == 1042
    assert payload["meeting_number"] == 12
    assert payload["last_polled_at"] == now.astimezone().isoformat()
    assert payload["lecturer_opened_at"] == now.astimezone().isoformat()
    assert payload["simkuliah_status"] == "hadir"
    # Deadline keeps the wall clock from Simkuliah with the local offset.
    assert "T17:45:00" in payload["deadline_at"]
    assert repo.client.table().upsert.call_args[1] == {"on_conflict": "schedule_id,meeting_number"}


@pytest.mark.asyncio
async def test_record_meeting_status_skips_ambiguous_row():
    repo = DatabaseRepository(client=MagicMock())
    status = ParsedMeetingStatus(is_open=True)
    await repo.record_meeting_status(status)

    repo.client.table.assert_not_called()


@pytest.mark.asyncio
async def test_record_meeting_status_closed_card_only_touches_poll_time():
    repo = DatabaseRepository(client=MagicMock())
    status = ParsedMeetingStatus(is_open=False, meeting_number=3, schedule_id=1042)
    now = datetime(2026, 11, 9, 19, 0)
    await repo.record_meeting_status(status, now=now)

    payload = repo.client.table().upsert.call_args[0][0]
    assert "lecturer_opened_at" not in payload
    assert "deadline_at" not in payload
    assert "simkuliah_status" not in payload


@pytest.mark.asyncio
async def test_upsert_meetings_bulk_writes_matrix_rows():
    repo = DatabaseRepository(client=MagicMock())
    records = [
        {
            "schedule_id": 1,
            "meeting_number": 12,
            "meeting_date": "2026-11-09",
            "lecturer_name": "Fathia Sabrina, S.T., M.Inf.Tech",
            "simkuliah_status": "hadir",
        },
        {
            "schedule_id": 1,
            "meeting_number": 13,
            "meeting_date": "2026-11-16",
            "lecturer_name": "Fathia Sabrina, S.T., M.Inf.Tech",
            "simkuliah_status": "pending",
        },
    ]
    await repo.upsert_meetings(records)

    repo.client.table.assert_called_with("meetings")
    repo.client.table().upsert.assert_called_once_with(
        records, on_conflict="schedule_id,meeting_number"
    )


@pytest.mark.asyncio
async def test_upsert_meetings_empty_list_is_noop():
    repo = DatabaseRepository(client=MagicMock())
    await repo.upsert_meetings([])
    repo.client.table.assert_not_called()


@pytest.mark.asyncio
async def test_resolve_schedule_id_returns_id():
    repo = DatabaseRepository(client=MagicMock())
    repo.client.table().select().eq().eq().limit().execute.return_value.data = [{"id": 7}]
    result = await repo.resolve_schedule_id("SINF6045", "A")
    assert result == 7


@pytest.mark.asyncio
async def test_save_override_calls_client_with_payload():
    repo = DatabaseRepository(client=MagicMock())
    await repo.save_override(meeting_id=1042, override_type="izin", note="family matter")

    repo.client.table.assert_called_with("local_overrides")
    repo.client.table().upsert.assert_called_once()
    payload = repo.client.table().upsert.call_args[0][0]
    assert payload["meeting_id"] == 1042
    assert payload["override_type"] == "izin"
    assert payload["note"] == "family matter"
    assert "is_active" not in payload
    assert repo.client.table().upsert.call_args[1] == {"on_conflict": "meeting_id"}
    repo.client.table().upsert().execute.assert_called_once()


@pytest.mark.asyncio
async def test_save_override_rejects_invalid_type():
    repo = DatabaseRepository(client=MagicMock())
    with pytest.raises(ValueError):
        await repo.save_override(meeting_id=1, override_type="invalid", note="x")
    repo.client.table.assert_not_called()


@pytest.mark.asyncio
async def test_get_active_override_returns_type():
    repo = DatabaseRepository(client=MagicMock())
    repo.client.table().select().eq().execute.return_value.data = [{"override_type": "sakit"}]
    result = await repo.get_active_override(meeting_id=1042)
    assert result == "sakit"


@pytest.mark.asyncio
async def test_get_active_override_returns_none_when_empty():
    repo = DatabaseRepository(client=MagicMock())
    repo.client.table().select().eq().execute.return_value.data = []
    result = await repo.get_active_override(meeting_id=1042)
    assert result is None


@pytest.mark.asyncio
async def test_resolve_meeting_id_returns_id():
    repo = DatabaseRepository(client=MagicMock())
    repo.client.table().select().eq().eq().limit().execute.return_value.data = [{"id": 42}]
    result = await repo.resolve_meeting_id(schedule_id=7, meeting_no=12)
    assert result == 42


@pytest.mark.asyncio
async def test_resolve_meeting_id_returns_none_when_missing():
    repo = DatabaseRepository(client=MagicMock())
    repo.client.table().select().eq().eq().limit().execute.return_value.data = []
    result = await repo.resolve_meeting_id(schedule_id=7, meeting_no=12)
    assert result is None


@pytest.mark.asyncio
async def test_log_incident_calls_client_with_payload():
    repo = DatabaseRepository(client=MagicMock())
    await repo.log_incident(incident_type="timeout", status_code=504, snippet="gateway timeout")

    repo.client.table.assert_called_with("incidents")
    repo.client.table().insert.assert_called_once()
    payload = repo.client.table().insert.call_args[0][0]
    assert payload["incident_type"] == "timeout"
    assert payload["status_code"] == 504
    assert payload["snippet"] == "gateway timeout"
    repo.client.table().insert().execute.assert_called_once()
