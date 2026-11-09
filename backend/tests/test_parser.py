"""Purpose: Unit tests for Simkuliah schedule and attendance HTML scrapers.
Data & Logic Flow: Tests DOM extraction of daily schedules, presence alert boxes, and error handling.
Key Components: test_parse_daily_schedule, test_parse_attendance_status_open
"""

from __future__ import annotations

from datetime import datetime

from app.services.simkuliah_parser import (
    ParsedMeetingStatus,
    ParsedScheduleItem,
    parse_attendance_cards,
    parse_attendance_status,
    parse_daily_schedule,
    parse_meeting_matrix,
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


# --------------------------------------------------------------------------- #
# Meeting matrix (today page) — official meeting numbering
# --------------------------------------------------------------------------- #

MOCK_MATRIX_HTML = """
<table id="simpletable">
  <tr>
    <th>Kode</th><th>Mata Kuliah</th><th colspan="4">Pertemuan</th>
  </tr>
  <tr>
    <th>1</th><th>2</th><th>3</th><th>4</th>
  </tr>
  <tr>
    <td>SINF6045</td>
    <td>PENELUSURAN INFORMASI(Kelas : A)(SKS Mengajar : 2)</td>
    <td class="table-success">Nama :Prof. Dr. Dosen Satu, S.Si.NIP :197001011994031002Hari, tanggal : Senin, 24-08-2026Ruang : D.03.02Jam : 16.35 - 18.15</td>
    <td class="table-success">Nama :Fathia Sabrina, S.T., M.Inf.TechNIP :199107232024062001Hari, tanggal : Senin, 31-08-2026Ruang : D.03.02Jam : 16.35 - 18.15</td>
    <td class="table-danger">Nama :Fathia Sabrina, S.T., M.Inf.TechNIP :199107232024062001Hari, tanggal : Senin, 07-09-2026Ruang : D.03.02Jam : 16.35 - 18.15</td>
    <td></td>
  </tr>
</table>
"""


def test_parse_meeting_matrix_maps_official_numbering():
    courses = parse_meeting_matrix(MOCK_MATRIX_HTML)
    assert len(courses) == 1
    course = courses[0]
    assert course.course_code == "SINF6045"
    assert course.class_group == "A"

    assert len(course.meetings) == 3
    first, second, third = course.meetings
    assert first.meeting_number == 1
    assert first.meeting_date == "2026-08-24"
    assert first.lecturer == "Prof. Dr. Dosen Satu, S.Si."
    assert first.status == "hadir"
    assert second.meeting_number == 2
    assert second.meeting_date == "2026-08-31"
    assert second.lecturer == "Fathia Sabrina, S.T., M.Inf.Tech"
    assert third.meeting_number == 3
    assert third.meeting_date == "2026-09-07"
    assert third.status == "tidak_hadir"


def test_parse_meeting_matrix_skips_cells_without_date():
    # The empty fourth cell must be skipped, never guessed as "today".
    courses = parse_meeting_matrix(MOCK_MATRIX_HTML)
    assert all(m.meeting_date != datetime.now().strftime("%Y-%m-%d") for m in courses[0].meetings)


def test_parse_meeting_matrix_empty_and_header_rows_ignored():
    assert parse_meeting_matrix("") == []
    assert parse_meeting_matrix("<html><body>no table</body></html>") == []
    # Header-only table: numeric first cells are skipped.
    courses = parse_meeting_matrix('<table id="simpletable"><tr><th>1</th><th>2</th></tr></table>')
    assert courses == []


# --------------------------------------------------------------------------- #
# Dashboard cards — one card per open attendance session
# --------------------------------------------------------------------------- #

MOCK_CARD_HTML = """
<nav class="header-navbar"><a href="#"><span>Fadhlurrahman Alaudin</span></a></nav>
<div class="card">
  <div class="card-header"><h5>ABSENSI KELAS A | SINF6045 - PENELUSURAN INFORMASI | PERTEMUAN KE-12 | SKS MENGAJAR : 2</h5></div>
  <div class="card-body">
    Anda sudah absen
    <table><tbody>
      <tr><td>A</td><td>Gedung MIPA</td><td>D.03.02</td><td>16.35 - 18.15</td><td>17:45</td></tr>
    </tbody></table>
  </div>
</div>
<div class="card">
  <div class="card-header"><h5>ABSENSI KELAS B | INF201 - GRAFIKA KOMPUTER | PERTEMUAN KE-5 | SKS MENGAJAR : 2</h5></div>
  <div class="card-body">
    <button id="konfirmasi-kehadiran-77">Konfirmasi Kehadiran</button>
  </div>
</div>
"""


def test_parse_attendance_cards_parses_every_card():
    cards = parse_attendance_cards(MOCK_CARD_HTML)
    assert len(cards) == 2

    first, second = cards
    assert first.course_code == "SINF6045"
    assert first.meeting_number == 12
    assert first.is_student_present is True
    assert first.is_open is True
    assert first.deadline_time == "17:45"
    assert first.student_name == "Fadhlurrahman Alaudin"

    assert second.course_code == "INF201"
    assert second.meeting_number == 5
    assert second.is_student_present is False
    assert second.is_open is True
    assert second.schedule_id == 77


def test_parse_attendance_cards_without_cards_returns_empty():
    assert parse_attendance_cards("") == []
    assert parse_attendance_cards("<html><body>Belum masuk waktu absen.</body></html>") == []


def test_parse_attendance_status_returns_first_card():
    status = parse_attendance_status(MOCK_CARD_HTML)
    assert status.course_code == "SINF6045"
    assert status.meeting_number == 12
    assert status.is_student_present is True
