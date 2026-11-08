"""Pydantic schemas for Supabase database entities.

Defines the typed records persisted to Supabase (schedules, meetings,
overrides, incidents) and the :class:`OverrideType` enum that scopes valid
override reasons to ``izin``, ``sakit``, and ``alpa``.
"""

from __future__ import annotations

from enum import StrEnum

from pydantic import BaseModel


class OverrideType(StrEnum):
    """Valid override reasons for a course meeting presence."""

    IZIN = "izin"
    SAKIT = "sakit"
    ALPA = "alpa"


class ScheduleRecord(BaseModel):
    """A schedule row persisted to the ``schedules`` table."""

    course_code: str
    course_name: str
    room: str
    start_time: str
    end_time: str
    lecturer: str


class MeetingRecord(BaseModel):
    """A meeting attendance record persisted to the ``meetings`` table."""

    meeting_id: int
    schedule_id: int | None = None
    meeting_number: int | None = None
    is_open: bool
    deadline_time: str | None = None


class OverrideRecord(BaseModel):
    """An override (izin / sakit / alpa) recorded for a meeting."""

    meeting_id: int
    override_type: OverrideType
    note: str = ""
    is_active: bool = True


class IncidentRecord(BaseModel):
    """An incident log entry persisted to the ``incidents`` table."""

    incident_type: str
    status_code: int
    snippet: str
