"""Purpose: Unit tests for schedule customizations and user preferences repository methods.
Data & Logic Flow: Mocks the Supabase client and verifies CRUD behavior plus effective customization resolution.
Key Components: test_resolve_effective_customization_prefers_meeting_over_schedule, DatabaseRepository
"""

from __future__ import annotations

from unittest.mock import MagicMock

import pytest

from app.core.database import DatabaseRepository


@pytest.mark.asyncio
async def test_resolve_effective_customization_prefers_meeting_over_schedule():
    repo = DatabaseRepository(supabase_url="http://mock", supabase_key="key")
    repo.client = MagicMock()
    # Mock return rows: one schedule-level and one meeting-level
    mock_data = [
        {
            "id": 1,
            "schedule_id": 10,
            "meeting_id": None,
            "time_offset_minutes": 15,
            "auto_presence_enabled": False,
        },
        {
            "id": 2,
            "schedule_id": 10,
            "meeting_id": 50,
            "time_offset_minutes": 30,
            "auto_presence_enabled": True,
        },
    ]
    repo.get_schedule_customizations = MagicMock(return_value=mock_data)

    eff = await repo.resolve_effective_customization(schedule_id=10, meeting_id=50)
    assert eff["time_offset_minutes"] == 30
    assert eff["auto_presence_enabled"] is True

    eff_sched = await repo.resolve_effective_customization(schedule_id=10, meeting_id=99)
    assert eff_sched["time_offset_minutes"] == 15


@pytest.mark.asyncio
async def test_get_schedule_customizations_filters_by_schedule_ids():
    repo = DatabaseRepository(client=MagicMock())
    rows = [
        {"id": 1, "schedule_id": 10, "meeting_id": None},
        {"id": 2, "schedule_id": 10, "meeting_id": 50},
    ]
    repo.client.table().select().in_().execute.return_value.data = rows

    result = await repo.get_schedule_customizations([10])

    assert result == rows
    repo.client.table.assert_called_with("schedule_customizations")


@pytest.mark.asyncio
async def test_get_schedule_customizations_without_filter_selects_all():
    repo = DatabaseRepository(client=MagicMock())
    repo.client.table().select().execute.return_value.data = []

    result = await repo.get_schedule_customizations()

    assert result == []
    repo.client.table.assert_called_with("schedule_customizations")


@pytest.mark.asyncio
async def test_upsert_schedule_customization_writes_payload():
    repo = DatabaseRepository(client=MagicMock())
    customization = {
        "schedule_id": 10,
        "meeting_id": 50,
        "time_offset_minutes": 30,
        "auto_presence_enabled": True,
    }
    upsert_mock = repo.client.table().upsert
    upsert_mock.return_value.execute.return_value.data = [customization]

    result = await repo.upsert_schedule_customization(customization)

    assert result == customization
    repo.client.table.assert_called_with("schedule_customizations")
    upsert_mock.assert_called_once_with(customization, on_conflict="schedule_id,meeting_id")
    upsert_mock.return_value.execute.assert_called_once()


@pytest.mark.asyncio
async def test_delete_schedule_customization_returns_bool():
    repo = DatabaseRepository(client=MagicMock())

    repo.client.table().delete().eq().execute.return_value.data = [{"id": 7}]
    assert await repo.delete_schedule_customization(7) is True

    repo.client.table().delete().eq().execute.return_value.data = []
    assert await repo.delete_schedule_customization(7) is False

    repo.client.table().delete().eq.assert_called_with("id", 7)


@pytest.mark.asyncio
async def test_get_user_preferences_returns_row():
    repo = DatabaseRepository(client=MagicMock())
    row = {"id": 1, "user_id": "default_user", "default_reminder_minutes": 15}
    repo.client.table().select().eq().limit().execute.return_value.data = [row]

    result = await repo.get_user_preferences()

    assert result == row
    repo.client.table.assert_called_with("user_preferences")


@pytest.mark.asyncio
async def test_get_user_preferences_returns_none_when_missing():
    repo = DatabaseRepository(client=MagicMock())
    repo.client.table().select().eq().limit().execute.return_value.data = []

    result = await repo.get_user_preferences(user_id="unknown")

    assert result is None


@pytest.mark.asyncio
async def test_upsert_user_preferences_writes_payload():
    repo = DatabaseRepository(client=MagicMock())
    preferences = {"user_id": "default_user", "default_reminder_minutes": 30}
    upsert_mock = repo.client.table().upsert
    upsert_mock.return_value.execute.return_value.data = [preferences]

    result = await repo.upsert_user_preferences(preferences)

    assert result == preferences
    upsert_mock.assert_called_once_with(preferences, on_conflict="user_id")
