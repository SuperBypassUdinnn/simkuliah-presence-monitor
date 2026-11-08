"""Purpose: High-performance DOM parsing for Simkuliah HTML pages.
Data & Logic Flow: Parses daily schedule tables and real-time attendance alert indicators via Lexbor.
Key Components: parse_daily_schedule, parse_attendance_status
"""

from __future__ import annotations

import re

from pydantic import BaseModel
from selectolax.lexbor import LexborHTMLParser as HTMLParser

_TIME_RANGE_RE = re.compile(r"(\d{1,2}:\d{2})\s*-\s*(\d{1,2}:\d{2})")
_DEADLINE_RE = re.compile(r"batas waktu presensi:\s*(\d{1,2}:\d{2}:\d{2})", re.IGNORECASE)
_OPEN_MARKERS = ("membuka presensi", "presensi telah dibuka")


class ParsedScheduleItem(BaseModel):
    """A single row from today's schedule table."""

    course_code: str
    course_name: str
    room: str
    start_time: str
    end_time: str
    lecturer: str


class ParsedMeetingStatus(BaseModel):
    """Parsed attendance/presence status for a course meeting.

    ``is_open`` is ``False`` and every optional field is ``None`` when the
    lecturer has not opened presence yet (or the HTML is empty/malformed).
    """

    is_open: bool
    deadline_time: str | None = None
    meeting_number: int | None = None
    schedule_id: int | None = None


def parse_daily_schedule(html: str) -> list[ParsedScheduleItem]:
    """Parse today's schedule HTML into a list of :class:`ParsedScheduleItem`.

    Each table row must hold at least five ``<td>`` cells in this order:
    course code, course name, room, time range (``HH:MM - HH:MM``), lecturer.
    Rows that do not match are skipped. Empty or table-less HTML yields
    an empty list.
    """
    if not html or not html.strip():
        return []

    root = HTMLParser(html)
    items: list[ParsedScheduleItem] = []

    for tr in root.css("table tr"):
        cells = [td.text(strip=True) for td in tr.css("td")]
        if len(cells) < 5:
            continue
        course_code, course_name, room, time_range, lecturer = cells[:5]
        match = _TIME_RANGE_RE.search(time_range)
        if not match:
            continue
        items.append(
            ParsedScheduleItem(
                course_code=course_code,
                course_name=course_name,
                room=room,
                start_time=match.group(1),
                end_time=match.group(2),
                lecturer=lecturer,
            )
        )

    return items


def parse_attendance_status(html: str) -> ParsedMeetingStatus:
    """Parse presence status HTML into a :class:`ParsedMeetingStatus`.

    Presence is considered open when the page carries a success alert
    announcing that the lecturer has opened presence. The deadline time and
    hidden form parameters (``id_jadwal`` / ``pertemuan``) are extracted with
    regular expressions whenever present. Empty or malformed HTML yields a
    closed status with all optional fields set to ``None``.
    """
    status = ParsedMeetingStatus(is_open=False)
    if not html or not html.strip():
        return status

    root = HTMLParser(html)

    lowered = html.lower()
    status.is_open = bool(root.css("div.alert.alert-success")) or any(
        marker in lowered for marker in _OPEN_MARKERS
    )

    deadline_match = _DEADLINE_RE.search(lowered)
    if deadline_match:
        status.deadline_time = deadline_match.group(1)

    for input_node in root.css('input[name="id_jadwal"]'):
        value = input_node.attributes.get("value")
        if value:
            try:
                status.schedule_id = int(value)
            except ValueError:
                pass
            break

    for input_node in root.css('input[name="pertemuan"]'):
        value = input_node.attributes.get("value")
        if value:
            try:
                status.meeting_number = int(value)
            except ValueError:
                pass
            break

    return status
