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
    is_student_present: bool = False
    student_name: str | None = None
    course_code: str | None = None


def parse_daily_schedule(html: str) -> list[ParsedScheduleItem]:
    """Parse today's schedule HTML into a list of :class:`ParsedScheduleItem`.

    Supports both real Simkuliah matrix tables (#simpletable) and standard
    5-column timetable rows. Empty or table-less HTML yields an empty list.
    """
    if not html or not html.strip():
        return []

    root = HTMLParser(html)
    items: list[ParsedScheduleItem] = []

    # Check for real Simkuliah matrix table first (#simpletable)
    simpletable = root.css_first("table#simpletable")
    if simpletable is not None:
        rows = simpletable.css("tr")
        for row in rows[2:]:  # skip header rows
            tds = row.css("td")
            if len(tds) < 2:
                continue
            code = tds[0].text(strip=True)
            raw_name = tds[1].text(strip=True)
            course_name = re.sub(r"\(.*?\)", "", raw_name).strip()

            # Extract meeting details from cells
            start_time = "08:00"
            end_time = "09:40"
            room = "D.03.02"
            lecturer = "Dosen"

            for td in tds[2:]:
                txt = td.text(strip=True)
                if not txt:
                    continue
                m_jam = re.search(r"Jam\s*:\s*(\d{2}[.:]\d{2})\s*-\s*(\d{2}[.:]\d{2})", txt)
                if m_jam:
                    start_time = m_jam.group(1).replace(".", ":")
                    end_time = m_jam.group(2).replace(".", ":")
                m_ruang = re.search(r"Ruang\s*:\s*([^J]+?)(?:Jam|$)", txt)
                if m_ruang:
                    room = m_ruang.group(1).strip()
                m_dosen = re.search(r"Nama\s*:\s*([^N]+?)(?:NIP|$)", txt)
                if m_dosen:
                    lecturer = m_dosen.group(1).strip()
                break

            items.append(
                ParsedScheduleItem(
                    course_code=code,
                    course_name=course_name,
                    room=room,
                    start_time=start_time,
                    end_time=end_time,
                    lecturer=lecturer,
                )
            )
        if items:
            return items

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

    Supports both Simkuliah dashboard card layout (/index.php/absensi) and
    generic/legacy success alerts. Extracts student presence, deadline, and
    presence parameters.
    """
    status = ParsedMeetingStatus(is_open=False)
    if not html or not html.strip():
        return status

    root = HTMLParser(html)
    lowered = html.lower()

    # Extract student name if present in navbar
    name_span = root.css_first("nav.header-navbar a span")
    if name_span:
        status.student_name = name_span.text(strip=True)

    # Check for real Simkuliah card on /index.php/absensi
    for card in root.css(".card"):
        header = card.css_first(".card-header h5")
        if not header or "absensi" not in header.text().lower():
            continue
        header_text = header.text(strip=True)
        m_course = re.search(r"\|\s*([A-Z0-9]+)\s*-", header_text)
        if m_course:
            status.course_code = m_course.group(1).strip()
        m_meet = re.search(r"pertemuan ke-(\d+)", header_text, re.IGNORECASE)
        if m_meet:
            status.meeting_number = int(m_meet.group(1))

        card_html = card.html
        if "anda sudah absen" in card_html.lower():
            status.is_student_present = True
            status.is_open = True

        tbody = card.css_first("tbody")
        if tbody:
            tds = [td.text(strip=True) for td in tbody.css("td")]
            if len(tds) >= 5:
                # Kelas, Gedung, Ruang, Jam, Batas Absen
                status.deadline_time = tds[4]

        btn = card.css_first('button[id^="konfirmasi-kehadiran-"]')
        if btn:
            status.is_open = True
            btn_id = btn.attributes.get("id", "")
            try:
                status.schedule_id = int(btn_id.replace("konfirmasi-kehadiran-", ""))
            except ValueError:
                pass
        return status

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
