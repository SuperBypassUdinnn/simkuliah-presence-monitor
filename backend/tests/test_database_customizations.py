"""Purpose: Tests for schedule customizations and user preferences in DatabaseRepository.
Data & Logic Flow: Verifies CRUD operations for schedule customizations and user preferences with deterministic resolution.
Key Components: test_resolve_effective_customization, test_upsert_schedule_customization
"""

from __future__ import annotations

from unittest.mock import MagicMock

import pytest

from app.core.database import DatabaseRepository


@pytest.mark.asyncio
async def test_resolve_effective_customization_prefers_meeting_over_schedule():
    repo = DatabaseRepository(client=MagicMock())
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
    assert eff is not None
    assert eff["time_offset_minutes"] == 30
    assert eff["auto_presence_enabled"] is True

    eff_sched = await repo.resolve_effective_customization(schedule_id=10, meeting_id=99)
    assert eff_sched is not None
    assert eff_sched["time_offset_minutes"] == 15
    assert eff_sched["auto_presence_enabled"] is False

    eff_none = await repo.resolve_effective_customization(schedule_id=999, meeting_id=1)
    assert eff_none is None


@pytest.mark.asyncio
async def test_get_schedule_customizations_filters_by_ids():
    repo = DatabaseRepository(client=MagicMock())
    expected = [{"id": 1, "schedule_id": 10}]
    repo.client.table().select().in_().execute.return_value.data = expected

    result = await repo.get_schedule_customizations([10, 11])

    assert result == expected
    repo.client.table.assert_called_with("schedule_customizations")
    repo.client.table().select().in_.assert_called_with("schedule_id", [10, 11])


@pytest.mark.asyncio
async def test_upsert_schedule_customization_resolves_existing_id_when_meeting_null():
    repo = DatabaseRepository(client=MagicMock())
    customization = {
        "schedule_id": 10,
        "meeting_id": None,
        "time_offset_minutes": 25,
        "auto_presence_enabled": True,
    }
    # Simulate finding existing course-wide row with id 42
    repo.client.table().select().eq().is_().limit().execute.return_value.data = [{"id": 42}]
    upsert_mock = repo.client.table().upsert
    upsert_mock.return_value.execute.return_value.data = [{**customization, "id": 42}]

    result = await repo.upsert_schedule_customization(customization)

    assert result["id"] == 42
    assert result["time_offset_minutes"] == 25
    upsert_mock.assert_called_once_with({**customization, "id": 42}, on_conflict="id")


@pytest.mark.asyncio
async def test_upsert_schedule_customization_inserts_without_conflict_target_when_new():
    """A brand-new row must use a plain insert.

    The migration replaces the full UNIQUE(schedule_id, meeting_id) constraint
    with partial unique indexes, which PostgreSQL refuses as an ON CONFLICT
    target. Only the resolved id path may use an upsert.
    """

    repo = DatabaseRepository(client=MagicMock())
    customization = {
        "schedule_id": 11,
        "meeting_id": None,
        "time_offset_minutes": 0,
        "auto_presence_enabled": True,
    }
    repo.client.table().select().eq().is_().limit().execute.return_value.data = []
    insert_mock = repo.client.table().insert
    insert_mock.return_value.execute.return_value.data = [{**customization, "id": 7}]
    upsert_mock = repo.client.table().upsert

    result = await repo.upsert_schedule_customization(customization)

    assert result["id"] == 7
    insert_mock.assert_called_once_with(customization)
    upsert_mock.assert_not_called()


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
