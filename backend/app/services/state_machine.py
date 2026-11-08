"""5-tier notification state machine for the Simkuliah presence monitor.

Encodes the deterministic progression of notification levels for a course
meeting, from the moment class starts until the presence window expires.

Levels (in escalation order):

* :data:`CLASS_STARTED`        - class has begun, presence not yet opened.
* :data:`LECTURER_OPENED`      - lecturer has opened presence.
* :data:`PENDING_REMINDER`     - presence deadline is approaching.
* :data:`URGENT_CLOSING`       - presence window is about to close.
* :data:`WINDOW_EXPIRED`       - presence window has closed.

:func:`evaluate_notification_state` returns ``None`` (suppressed) when an
active override is in force or the student is already present, and otherwise
returns the highest applicable level, never regressing below the last notified
level.
"""

from __future__ import annotations

from datetime import datetime, time, timedelta
from enum import StrEnum

# --------------------------------------------------------------------------- #
# Notification level enum
# --------------------------------------------------------------------------- #


class NotificationLevel(StrEnum):
    """The five notification tiers, in escalation order."""

    CLASS_STARTED = "class_started"
    LECTURER_OPENED = "lecturer_opened"
    PENDING_REMINDER = "pending_reminder"
    URGENT_CLOSING = "urgent_closing"
    WINDOW_EXPIRED = "window_expired"


# Backwards-compatible alias required by the task interface.
NotificationState = NotificationLevel

# Module-level constant aliases for the five levels.
CLASS_STARTED = NotificationLevel.CLASS_STARTED
LECTURER_OPENED = NotificationLevel.LECTURER_OPENED
PENDING_REMINDER = NotificationLevel.PENDING_REMINDER
URGENT_CLOSING = NotificationLevel.URGENT_CLOSING
WINDOW_EXPIRED = NotificationLevel.WINDOW_EXPIRED

# Ordinal rank of each level, used for monotonic (non-regressing) progression.
_LEVEL_RANK: dict[NotificationLevel, int] = {
    NotificationLevel.CLASS_STARTED: 0,
    NotificationLevel.LECTURER_OPENED: 1,
    NotificationLevel.PENDING_REMINDER: 2,
    NotificationLevel.URGENT_CLOSING: 3,
    NotificationLevel.WINDOW_EXPIRED: 4,
}

# --------------------------------------------------------------------------- #
# Tuning constants
# --------------------------------------------------------------------------- #

# How close to the end of the window before URGENT_CLOSING is raised.
_URGENT_WINDOW_MINUTES = 10

# How close to the presence deadline before PENDING_REMINDER is raised.
_PENDING_WINDOW_MINUTES = 15


def _rank(level: NotificationLevel | None) -> int:
    if level is None:
        return -1
    return _LEVEL_RANK[level]


def _combine(date, t: time) -> datetime:
    return datetime.combine(date, t)


# --------------------------------------------------------------------------- #
# Public API
# --------------------------------------------------------------------------- #


def evaluate_notification_state(
    *,
    now: datetime,
    start_time: time,
    end_time: time,
    is_dosen_open: bool,
    is_student_present: bool,
    has_override: bool,
    last_notified_level: NotificationLevel | None,
    lecturer_opened_at: datetime | None = None,
    deadline_at: datetime | None = None,
) -> NotificationLevel | None:
    """Evaluate the current notification level for a meeting.

    Returns ``None`` when notifications are suppressed (active override or
    student already present) or when the class has not started yet.
    Otherwise returns the highest applicable :class:`NotificationLevel`,
    never regressing below ``last_notified_level``.

    Args:
        now: Current time.
        start_time: Class start time.
        end_time: Class / presence window end time.
        is_dosen_open: Whether the lecturer has opened presence.
        is_student_present: Whether the student is already marked present.
        has_override: Whether an active override (izin/sakit/alpa) exists.
        last_notified_level: The last level that was actually dispatched.
        lecturer_opened_at: When the lecturer opened presence (informational).
        deadline_at: The presence deadline (informational).
    """
    del lecturer_opened_at  # accepted for interface completeness; open state
    # is derived from is_dosen_open.

    # Suppression rules take precedence over everything.
    if has_override or is_student_present:
        return None

    # Class has not started yet.
    start_dt = _combine(now.date(), start_time)
    if now < start_dt:
        return None

    end_dt = _combine(now.date(), end_time)

    # ------------------------------------------------------------------ #
    # Determine the candidate level from current conditions.
    # ------------------------------------------------------------------ #
    if now > end_dt:
        candidate: NotificationLevel = NotificationLevel.WINDOW_EXPIRED
    elif now >= end_dt - _minutes(_URGENT_WINDOW_MINUTES):
        candidate = NotificationLevel.URGENT_CLOSING
    elif deadline_at is not None and now >= deadline_at - _minutes(
        _PENDING_WINDOW_MINUTES
    ):
        candidate = NotificationLevel.PENDING_REMINDER
    elif is_dosen_open:
        candidate = NotificationLevel.LECTURER_OPENED
    else:
        candidate = NotificationLevel.CLASS_STARTED

    # Monotonic progression: never regress below the last notified level.
    if _rank(last_notified_level) > _rank(candidate):
        return last_notified_level
    return candidate


def _minutes(count: int) -> timedelta:
    return timedelta(minutes=count)
