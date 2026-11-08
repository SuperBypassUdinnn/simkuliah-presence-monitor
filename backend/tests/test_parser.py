"""Unit tests for the Simkuliah HTML scraper and parser service.

Covers daily schedule parsing (course code, name, room, time range, lecturer)
and attendance status parsing (open / closed / not yet opened by lecturer),
plus graceful handling of empty or malformed HTML. All tests run offline
against static CodeIgniter HTML fixtures.
"""

from __future__ import annotations

from app.services.simkuliah_parser import (
    ParsedMeetingStatus,
    ParsedScheduleItem,
    parse_attendance_status,
    parse_daily_schedule,
)

MOCK_SCHEDULE_HTML = """
<table class="table">
  <tr>
    <td>INF201</td>
    <td>Grafika Komputer</td>
    <td>Ruang 301</td>
    <td>08:00 - 09:40</td>
    <td>Dr. Dosen, M.Kom</td>
  </tr>
  <tr>
    <td>INF202</td>
    <td>Basis Data</td>
    <td>Ruang 205</td>
    <td>10:00 - 11:40</td>
    <td>Dra. Asisten, M.Kom</td>
  </tr>
</table>
"""

MOCK_PRESENCE_OPEN_HTML = """
<div class="alert alert-success">
  Dosen telah membuka presensi pada 08:05:00 WIB.
  Batas waktu presensi: 08:35:00 WIB.
  <form action="/index.php/mahasiswa/presensi/simpan" method="POST">
    <input type="hidden" name="id_jadwal" value="1042">
    <input type="hidden" name="pertemuan" value="7">
    <button type="submit" class="btn btn-primary">Konfirmasi Presensi</button>
  </form>
</div>
"""

MOCK_PRESENCE_CLOSED_HTML = """
<div class="alert alert-warning">
  Belum ada presensi yang dibuka oleh dosen untuk pertemuan ini.
  <form action="/index.php/mahasiswa/presensi/simpan" method="POST">
    <input type="hidden" name="id_jadwal" value="1042">
    <input type="hidden" name="pertemuan" value="7">
  </form>
</div>
"""


def test_parse_daily_schedule_returns_all_fields():
    items = parse_daily_schedule(MOCK_SCHEDULE_HTML)
    assert len(items) == 2
    assert items[0] == ParsedScheduleItem(
        course_code="INF201",
        course_name="Grafika Komputer",
        room="Ruang 301",
        start_time="08:00",
        end_time="09:40",
        lecturer="Dr. Dosen, M.Kom",
    )
    assert items[1] == ParsedScheduleItem(
        course_code="INF202",
        course_name="Basis Data",
        room="Ruang 205",
        start_time="10:00",
        end_time="11:40",
        lecturer="Dra. Asisten, M.Kom",
    )


def test_parse_attendance_status_open():
    status = parse_attendance_status(MOCK_PRESENCE_OPEN_HTML)
    assert status.is_open is True
    assert status.deadline_time == "08:35:00"
    assert status.meeting_number == 7
    assert status.schedule_id == 1042


def test_parse_attendance_status_closed():
    status = parse_attendance_status(MOCK_PRESENCE_CLOSED_HTML)
    assert status.is_open is False
    assert status.deadline_time is None
    assert status.meeting_number == 7
    assert status.schedule_id == 1042


def test_parse_daily_schedule_empty_html_returns_empty_list():
    assert parse_daily_schedule("") == []
    assert parse_daily_schedule("<html><body>no schedule table</body></html>") == []


def test_parse_attendance_status_empty_html_returns_closed_status():
    status = parse_attendance_status("")
    assert status == ParsedMeetingStatus(
        is_open=False,
        deadline_time=None,
        meeting_number=None,
        schedule_id=None,
    )


def test_parse_attendance_status_malformed_html_does_not_crash():
    status = parse_attendance_status("not really html <<< <unclosed")
    assert status.is_open is False
    assert status.deadline_time is None
    assert status.meeting_number is None
    assert status.schedule_id is None
