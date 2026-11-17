"""Purpose: Deterministic 5-tier notification lifecycle state machine.
Data & Logic Flow: Evaluates time and lecture status against thresholds to determine notification levels.
Key Components: evaluate_notification_state, NotificationLevel
"""

from __future__ import annotations

from datetime import datetime, time, timedelta
from enum import StrEnum

# --------------------------------------------------------------------------- #
# Notification level enum
# --------------------------------------------------------------------------- #


class NotificationLevel(StrEnum):
    """The notification tiers, in escalation order."""

    CLASS_REMINDER = "class_reminder"
    CLASS_STARTED = "class_started"
    LECTURER_OPENED = "lecturer_opened"
    AUTO_CONFIRMED = "auto_confirmed"
    AUTO_PRESENCE_FAILED = "auto_presence_failed"
    PENDING_REMINDER = "pending_reminder"
    URGENT_CLOSING = "urgent_closing"
    WINDOW_EXPIRED = "window_expired"


class Priority(StrEnum):
    """Delivery priority tier for a dispatched notification."""

    NORMAL = "normal"
    HIGH = "high"


# Backwards-compatible alias required by the task interface.
NotificationState = NotificationLevel

# Module-level constant aliases for the levels.
CLASS_REMINDER = NotificationLevel.CLASS_REMINDER
CLASS_STARTED = NotificationLevel.CLASS_STARTED
LECTURER_OPENED = NotificationLevel.LECTURER_OPENED
AUTO_CONFIRMED = NotificationLevel.AUTO_CONFIRMED
AUTO_PRESENCE_FAILED = NotificationLevel.AUTO_PRESENCE_FAILED
PENDING_REMINDER = NotificationLevel.PENDING_REMINDER
URGENT_CLOSING = NotificationLevel.URGENT_CLOSING
WINDOW_EXPIRED = NotificationLevel.WINDOW_EXPIRED

# Ordinal rank of each level, used for monotonic (non-regressing) progression.
_LEVEL_RANK: dict[NotificationLevel, int] = {
    NotificationLevel.CLASS_REMINDER: 0,
    NotificationLevel.CLASS_STARTED: 1,
    NotificationLevel.LECTURER_OPENED: 2,
    NotificationLevel.AUTO_CONFIRMED: 2,
    NotificationLevel.AUTO_PRESENCE_FAILED: 2,
    NotificationLevel.PENDING_REMINDER: 3,
    NotificationLevel.URGENT_CLOSING: 4,
    NotificationLevel.WINDOW_EXPIRED: 5,
}

# --------------------------------------------------------------------------- #
# Tuning constants
# --------------------------------------------------------------------------- #

# How close to the end of the window before URGENT_CLOSING is raised.
_URGENT_WINDOW_MINUTES = 10

# How close to the presence deadline before PENDING_REMINDER is raised.
_PENDING_WINDOW_MINUTES = 15

# Only high-priority levels escalate: the lecturer opening presence,
# failed auto-presence requiring immediate manual action, and the final
# minutes before the window closes. Every other level stays normal.
_HIGH_PRIORITY_LEVELS = frozenset(
    {
        NotificationLevel.LECTURER_OPENED,
        NotificationLevel.URGENT_CLOSING,
        NotificationLevel.AUTO_PRESENCE_FAILED,
    }
)


def priority_for_state(state: NotificationLevel) -> Priority:
    """Return the delivery priority tier for ``state``."""
    if state in _HIGH_PRIORITY_LEVELS:
        return Priority.HIGH
    return Priority.NORMAL


def rank_for_level(level: NotificationLevel | None) -> int:
    """Public ordinal rank accessor (used by restart-safe dedupe persistence)."""
    if level is None:
        return -1
    return _LEVEL_RANK[level]


def _rank(level: NotificationLevel | None) -> int:
    """Backwards-compatible private alias for :func:`rank_for_level`."""
    return rank_for_level(level)


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
    reminder_lead_minutes: int | None = None,
) -> NotificationLevel | None:
    """Evaluate the current notification level for a meeting.

    Returns ``None`` when notifications are suppressed (active override or
    student already present) or when the class has not started yet (unless
    within the advance reminder lead window).
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
        reminder_lead_minutes: Advance notice in minutes before class start.
    """
    del lecturer_opened_at  # accepted for interface completeness; open state
    # is derived from is_dosen_open.

    # Suppression rules take precedence over everything.
    if has_override or is_student_present:
        return None

    # Class has not started yet.
    start_dt = _combine(now.date(), start_time)
    if now < start_dt:
        if reminder_lead_minutes is not None and reminder_lead_minutes > 0:
            reminder_dt = start_dt - _minutes(reminder_lead_minutes)
            if now >= reminder_dt:
                candidate = NotificationLevel.CLASS_REMINDER
                if _rank(last_notified_level) > _rank(candidate):
                    return last_notified_level
                return candidate
        return None

    end_dt = _combine(now.date(), end_time)

    # ------------------------------------------------------------------ #
    # Determine the candidate level from current conditions.
    # ------------------------------------------------------------------ #
    if now > end_dt:
        candidate: NotificationLevel = NotificationLevel.WINDOW_EXPIRED
    elif now >= end_dt - _minutes(_URGENT_WINDOW_MINUTES):
        candidate = NotificationLevel.URGENT_CLOSING
    elif deadline_at is not None and now >= deadline_at - _minutes(_PENDING_WINDOW_MINUTES):
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
