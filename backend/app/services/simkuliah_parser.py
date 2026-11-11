"""Purpose: High-performance DOM parsing for Simkuliah HTML pages.
Data & Logic Flow: Parses the today-page meeting matrix, multi-card dashboard statuses, and daily schedule tables via Lexbor.
Key Components: parse_daily_schedule, parse_meeting_matrix, parse_attendance_cards, parse_attendance_status
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
    # Class group parsed from the row's "(Kelas : X)" paren. The schedule
    # table carries it exactly like the meeting matrix does; defaulting to
    # "A" would phantom-create a second schedule row for every course whose
    # real group is not A (the row key includes class_group).
    class_group: str = "A"


class ParsedMeetingStatus(BaseModel):
    """Parsed attendance/presence status for a course meeting.

    ``is_open`` is ``False`` and every optional field is ``None`` when the
    lecturer has not opened presence yet (or the HTML is empty/malformed).
    ``schedule_id`` is Simkuliah's own jadwal id (from the konfirmasi
    button), which is what ``confirm_presence`` expects; it is NOT a
    ``schedules.id`` from Supabase and must never be written to
    ``meetings.schedule_id``.
    """

    is_open: bool
    deadline_time: str | None = None
    meeting_number: int | None = None
    schedule_id: int | None = None
    is_student_present: bool = False
    student_name: str | None = None
    course_code: str | None = None


class ParsedMeetingCell(BaseModel):
    """One meeting cell from a course row of the Simkuliah matrix.

    ``meeting_number`` follows Simkuliah's official numbering (the matrix
    column order on ``jadwal_kuliah_hari_ini``), which the attendance system
    itself uses on the absensi dashboard.
    """

    meeting_number: int
    meeting_date: str  # ISO YYYY-MM-DD
    lecturer: str = ""
    status: str = "pending"  # hadir | tidak_hadir | pending


class ParsedCourseMeetings(BaseModel):
    """All parsed meeting cells for one course row of the matrix."""

    course_code: str
    course_name: str
    class_group: str = "A"
    meetings: list[ParsedMeetingCell] = []


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
            # The row's "(Kelas : X)" paren identifies the real class group;
            # dropping it used to upsert every course as group A, creating a
            # phantom schedule row for courses whose real group differs.
            m_group = _CLASS_GROUP_RE.search(raw_name)

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
                    class_group=m_group.group(1).strip() if m_group else "A",
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


_DATE_RE = re.compile(r"tanggal\s*:\s*(?:[A-Za-z]+,\s*)?(\d{2})-(\d{2})-(\d{4})")
_LECTURER_RE = re.compile(r"Nama\s*:\s*(.+?)(?:NIP|$)", re.DOTALL)
_CLASS_GROUP_RE = re.compile(r"\(Kelas\s*:\s*([^)]+)\)")

# A real presence deadline ("Batas Absen") is a wall-clock time such as
# "08:31" or "08:31:00". The same cell reads "Dosen belum absen" while the
# lecturer has not opened presence, which must never be treated as a time.
_CLOCK_RE = re.compile(r"\d{1,2}[:.]\d{2}(?::\d{2})?")

# Matrix cell background classes -> normalized simkuliah_status.
_CELL_STATUS_CLASSES = (
    ("table-success", "hadir"),
    ("table-danger", "tidak_hadir"),
)


def parse_meeting_matrix(html: str) -> list[ParsedCourseMeetings]:
    """Parse the Simkuliah meeting matrix into per-course meeting cells.

    The source page must be ``jadwal_kuliah_hari_ini`` (or a matrix sharing
    its layout): ``table#simpletable`` with two header rows and one row per
    course whose cells 2..N are that course's meetings, numbered 1..N-2 in
    Simkuliah's official order. Meeting numbers follow the column position —
    NOT the chronological date order, which the semester matrix page uses
    and which desyncs meeting numbers whenever a week is skipped.

    Cells without a parsable date are skipped entirely; guessing "today"
    corrupts meeting dates (the original off-by-one bug).
    """
    if not html or not html.strip():
        return []

    root = HTMLParser(html)
    table = root.css_first("table#simpletable")
    if table is None:
        return []

    courses: list[ParsedCourseMeetings] = []
    for row in table.css("tr"):
        tds = row.css("td")
        if len(tds) < 3:
            continue
        code = tds[0].text(strip=True)
        if not code or code.isdigit():
            # Header rows: "Kode | Mata Kuliah | Pertemuan" and the numeric
            # column labels.
            continue
        raw_name = tds[1].text(strip=True)
        course_name = re.sub(r"\(.*?\)", "", raw_name).strip()
        m_class = _CLASS_GROUP_RE.search(raw_name)
        class_group = m_class.group(1).strip() if m_class else "A"

        meetings: list[ParsedMeetingCell] = []
        for offset, td in enumerate(tds[2:]):
            text = td.text(strip=True)
            m_date = _DATE_RE.search(text)
            if not m_date:
                continue
            d, m, y = m_date.group(1), m_date.group(2), m_date.group(3)
            m_lecturer = _LECTURER_RE.search(text)
            status = "pending"
            td_class = td.attributes.get("class", "") or ""
            for marker, value in _CELL_STATUS_CLASSES:
                if marker in td_class:
                    status = value
                    break
            meetings.append(
                ParsedMeetingCell(
                    meeting_number=offset + 1,
                    meeting_date=f"{y}-{m}-{d}",
                    lecturer=m_lecturer.group(1).strip() if m_lecturer else "",
                    status=status,
                )
            )

        courses.append(
            ParsedCourseMeetings(
                course_code=code,
                course_name=course_name,
                class_group=class_group,
                meetings=meetings,
            )
        )
    return courses


def parse_attendance_cards(html: str) -> list[ParsedMeetingStatus]:
    """Parse every absensi card on the dashboard into meeting statuses.

    The dashboard renders one card per open attendance session; several
    classes can be open at once, so callers match cards to schedule items by
    ``course_code`` instead of relying on the first card.
    """
    statuses: list[ParsedMeetingStatus] = []
    if not html or not html.strip():
        return statuses

    root = HTMLParser(html)

    name_span = root.css_first("nav.header-navbar a span")
    student_name = name_span.text(strip=True) if name_span else None

    for card in root.css(".card"):
        header = card.css_first(".card-header h5")
        if not header or "absensi" not in header.text().lower():
            continue
        status = ParsedMeetingStatus(is_open=False, student_name=student_name)

        header_text = header.text(strip=True)
        m_course = re.search(r"\|\s*([A-Z0-9]+)\s*-", header_text)
        if m_course:
            status.course_code = m_course.group(1).strip()
        m_meet = re.search(r"pertemuan ke-(\d+)", header_text, re.IGNORECASE)
        if m_meet:
            status.meeting_number = int(m_meet.group(1))

        card_html = card.html or ""
        if "anda sudah absen" in card_html.lower():
            status.is_student_present = True
            status.is_open = True

        tbody = card.css_first("tbody")
        deadline_time: str | None = None
        if tbody:
            tds = [td.text(strip=True) for td in tbody.css("td")]
            if len(tds) >= 5:
                # Kelas, Gedung, Ruang, Jam, Batas Absen. Only a real clock
                # value means the lecturer opened presence; "Dosen belum
                # absen" is the closed marker.
                candidate = tds[4]
                if _CLOCK_RE.fullmatch(candidate):
                    deadline_time = candidate
        status.deadline_time = deadline_time

        btn = card.css_first('button[id^="konfirmasi-kehadiran-"]')
        if btn:
            # The button id is Simkuliah's own jadwal id (what
            # confirm_presence must send), NOT the Supabase schedules.id.
            btn_id = btn.attributes.get("id", "")
            try:
                status.schedule_id = int(btn_id.replace("konfirmasi-kehadiran-", ""))
            except ValueError:
                pass

        # A konfirmasi button alone is not proof of an open window: Simkuliah
        # renders it even when "Batas Absen" says "Dosen belum absen". Open
        # state comes from a real deadline (or from the student already
        # having absen, which resolves the meeting).
        if deadline_time is not None:
            status.is_open = True

        statuses.append(status)
    return statuses


def parse_attendance_status(html: str) -> ParsedMeetingStatus:
    """Parse the first presence status from dashboard HTML.

    Backward-compatible wrapper over :func:`parse_attendance_cards`: returns
    the first card when one exists, otherwise falls back to the generic/
    legacy success-alert layout.
    """
    cards = parse_attendance_cards(html)
    if cards:
        return cards[0]

    status = ParsedMeetingStatus(is_open=False)
    if not html or not html.strip():
        return status

    root = HTMLParser(html)
    lowered = html.lower()

    name_span = root.css_first("nav.header-navbar a span")
    if name_span:
        status.student_name = name_span.text(strip=True)

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
