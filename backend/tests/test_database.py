"""Purpose: Unit tests for Supabase database repository operations.
Data & Logic Flow: Tests CRUD operations, retry wrappers, and override validation logic.
Key Components: test_override_suppression_logic, DatabaseRepository
"""

from __future__ import annotations

from unittest.mock import MagicMock

import pytest
from app.core.database import DatabaseRepository
from app.models.schemas import OverrideType
from app.services.simkuliah_parser import ParsedMeetingStatus, ParsedScheduleItem


def test_override_type_enum_values():
    assert OverrideType.IZIN.value == "izin"
    assert OverrideType.SAKIT.value == "sakit"
    assert OverrideType.ALPA.value == "alpa"


def test_is_valid_override_accepts_valid_types():
    repo = DatabaseRepository(client=MagicMock())
    assert repo.is_valid_override("izin") is True
    assert repo.is_valid_override("sakit") is True
    assert repo.is_valid_override("alpa") is True


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
async def test_record_meeting_status_calls_client():
    repo = DatabaseRepository(client=MagicMock())
    status = ParsedMeetingStatus(
        is_open=True,
        deadline_time="08:35:00",
        meeting_number=7,
        schedule_id=1042,
    )
    await repo.record_meeting_status(status)

    repo.client.table.assert_called_with("meetings")
    repo.client.table().insert.assert_called_once()
    repo.client.table().insert().execute.assert_called_once()


@pytest.mark.asyncio
async def test_save_override_calls_client_with_payload():
    repo = DatabaseRepository(client=MagicMock())
    await repo.save_override(
        meeting_id=1042, override_type="izin", note="family matter"
    )

    repo.client.table.assert_called_with("overrides")
    repo.client.table().upsert.assert_called_once()
    payload = repo.client.table().upsert.call_args[0][0]
    assert payload["meeting_id"] == 1042
    assert payload["override_type"] == "izin"
    assert payload["note"] == "family matter"
    assert payload["is_active"] is True
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
    repo.client.table().select().eq().eq().execute.return_value.data = [
        {"override_type": "sakit"}
    ]
    result = await repo.get_active_override(meeting_id=1042)
    assert result == "sakit"


@pytest.mark.asyncio
async def test_get_active_override_returns_none_when_empty():
    repo = DatabaseRepository(client=MagicMock())
    repo.client.table().select().eq().eq().execute.return_value.data = []
    result = await repo.get_active_override(meeting_id=1042)
    assert result is None


@pytest.mark.asyncio
async def test_log_incident_calls_client_with_payload():
    repo = DatabaseRepository(client=MagicMock())
    await repo.log_incident(
        incident_type="timeout", status_code=504, snippet="gateway timeout"
    )

    repo.client.table.assert_called_with("incidents")
    repo.client.table().insert.assert_called_once()
    payload = repo.client.table().insert.call_args[0][0]
    assert payload["incident_type"] == "timeout"
    assert payload["status_code"] == 504
    assert payload["snippet"] == "gateway timeout"
    repo.client.table().insert().execute.assert_called_once()
