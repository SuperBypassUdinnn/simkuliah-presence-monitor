"""Purpose: Wall-clock helpers for Simkuliah times, which are always WIB.
Data & Logic Flow: Simkuliah pages express every time as a naive WIB wall
clock ("08:31", 08.00 - 09.40). These helpers attach or normalize the WIB
offset so the stored instants are unambiguous on any host, including UTC
containers, without a zoneinfo dependency.
Key Components: WIB, now_wib, as_wib, naive_wib_now
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone

# Simkuliah serves West Indonesia Time year-round (no DST), so a fixed
# offset is exact and avoids tzdata availability concerns in containers.
WIB = timezone(timedelta(hours=7), name="WIB")


def now_wib() -> datetime:
    """Current instant, WIB-attached."""
    return datetime.now(WIB)


def as_wib(moment: datetime) -> datetime:
    """Return ``moment`` WIB-attached without shifting a wall clock.

    A naive datetime is interpreted as a Simkuliah wall clock, so WIB is
    attached verbatim (no conversion); an aware datetime is converted to WIB.
    """
    if moment.tzinfo is None:
        return moment.replace(tzinfo=WIB)
    return moment.astimezone(WIB)


def naive_wib_now() -> datetime:
    """Current WIB wall clock, naive, for code that compares against the
    naive schedule times Simkuliah prints."""
    return now_wib().replace(tzinfo=None)
