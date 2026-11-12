"""Purpose: End-to-end Simkuliah attendance confirmation orchestrator.
Data & Logic Flow: Resolves the meeting context from Supabase, ensures an
authenticated Simkuliah session, fetches the live dashboard to extract the
7-field AJAX payload for the target card, confirms presence on Simkuliah, and
updates Supabase only after Simkuliah returns "success".
Key Components: PresenceConfirmError, confirm_meeting_on_simkuliah
"""

from __future__ import annotations

from typing import Any

from app.core.database import DatabaseRepository
from app.services.simkuliah_client import SimkuliahClient
from app.services.simkuliah_parser import ParsedMeetingStatus, parse_attendance_cards


class PresenceConfirmError(Exception):
    """Domain error raised when Simkuliah presence cannot be confirmed."""

    def __init__(self, status_code: int, detail: str) -> None:
        super().__init__(detail)
        self.status_code = status_code
        self.detail = detail


def _match_card(
    cards: list[ParsedMeetingStatus],
    *,
    simkuliah_schedule_id: int | None = None,
    course_code: str | None = None,
    class_group: str | None = None,
    meeting_no: int | None = None,
) -> ParsedMeetingStatus | None:
    """Find the dashboard card matching the requested lecture meeting."""
    if simkuliah_schedule_id is not None:
        for card in cards:
            if card.schedule_id == simkuliah_schedule_id:
                return card

    if not course_code:
        return None

    candidates = [card for card in cards if card.course_code == course_code]
    if not candidates:
        return None

    if class_group:
        group_matches = [
            c
            for c in candidates
            if not c.class_group or c.class_group.lower() == class_group.lower()
        ]
        if group_matches:
            candidates = group_matches

    if meeting_no is not None:
        meet_matches = [c for c in candidates if c.meeting_number == meeting_no]
        if meet_matches:
            return meet_matches[0]

    return candidates[0]


async def _fetch_live_cards(
    client: SimkuliahClient, *, force_login: bool = False
) -> list[ParsedMeetingStatus]:
    """Ensure a live authenticated session and parse current dashboard cards."""
    if force_login or not getattr(client, "is_authenticated", False):
        if not await client.login():
            raise PresenceConfirmError(
                502,
                "Gagal login ke Simkuliah untuk konfirmasi presensi. Coba lagi nanti.",
            )

    html = await client.fetch_dashboard()
    cards = parse_attendance_cards(html)
    if not cards and not force_login and "login" in html.lower():
        # Stale cookie redirected to login page; re-authenticate and retry once.
        if not await client.login():
            raise PresenceConfirmError(
                502,
                "Sesi Simkuliah kedaluwarsa dan gagal login ulang. Coba lagi nanti.",
            )
        html = await client.fetch_dashboard()
        cards = parse_attendance_cards(html)
    return cards


async def confirm_meeting_on_simkuliah(
    *,
    client: SimkuliahClient,
    repo: DatabaseRepository,
    meeting_id: int | None = None,
    schedule_id: int | None = None,
    db_schedule_id: int | None = None,
    meeting_no: int | None = None,
    course_code: str | None = None,
    class_group: str | None = None,
) -> dict[str, Any]:
    """Confirm attendance against Simkuliah and persist to Supabase only on success."""
    resolved_meeting_id = meeting_id
    resolved_course = course_code
    resolved_group = class_group
    resolved_meeting_no = meeting_no

    if resolved_meeting_id is None and (db_schedule_id or schedule_id) and meeting_no is not None:
        for cand in dict.fromkeys(c for c in (db_schedule_id, schedule_id) if c is not None):
            found = await repo.resolve_meeting_id(cand, meeting_no)
            if found is not None:
                resolved_meeting_id = found
                break

    if resolved_meeting_id is not None:
        ctx = await repo.get_meeting_context(resolved_meeting_id)
        if ctx is None:
            raise PresenceConfirmError(404, "Pertemuan tidak ditemukan.")
        sched = ctx.get("schedules")
        if isinstance(sched, list) and sched:
            sched = sched[0]
        if isinstance(sched, dict):
            resolved_course = resolved_course or sched.get("course_code")
            resolved_group = resolved_group or sched.get("class_group")
        if resolved_meeting_no is None:
            resolved_meeting_no = ctx.get("meeting_number")
    elif meeting_id is not None:
        raise PresenceConfirmError(404, "Pertemuan tidak ditemukan.")

    cards = await _fetch_live_cards(client, force_login=False)
    card = _match_card(
        cards,
        simkuliah_schedule_id=schedule_id if resolved_course is None else None,
        course_code=resolved_course,
        class_group=resolved_group,
        meeting_no=resolved_meeting_no,
    )
    if card is None and schedule_id is not None:
        card = _match_card(
            cards,
            simkuliah_schedule_id=schedule_id,
            course_code=resolved_course,
            class_group=resolved_group,
            meeting_no=resolved_meeting_no,
        )

    if card is None:
        raise PresenceConfirmError(
            409,
            "Presensi belum dibuka atau tidak tersedia di dashboard Simkuliah.",
        )

    if card.is_student_present:
        if resolved_meeting_id is not None:
            await repo.mark_meeting_present(resolved_meeting_id)
        return {
            "status": "success",
            "already_present": True,
            "message": "Kehadiran sudah tercatat di Simkuliah.",
        }

    if not card.is_open or card.schedule_id is None:
        raise PresenceConfirmError(
            409,
            "Dosen belum membuka presensi atau batas waktu presensi sudah tutup di Simkuliah.",
        )

    ok = await _submit_card(client, card, resolved_meeting_no, resolved_course, resolved_group)
    if not ok:
        # Session cookie may have expired silently before the POST; refresh once.
        cards = await _fetch_live_cards(client, force_login=True)
        refreshed = _match_card(
            cards,
            simkuliah_schedule_id=card.schedule_id,
            course_code=resolved_course or card.course_code,
            class_group=resolved_group or card.class_group,
            meeting_no=resolved_meeting_no or card.meeting_number,
        )
        if refreshed is not None and refreshed.is_student_present:
            ok = True
        elif refreshed is not None and refreshed.is_open:
            ok = await _submit_card(
                client,
                refreshed,
                resolved_meeting_no,
                resolved_course,
                resolved_group,
            )

    if not ok:
        raise PresenceConfirmError(
            502,
            "Konfirmasi presensi ke Simkuliah gagal. Silakan lakukan absen langsung di website Simkuliah.",
        )

    if resolved_meeting_id is not None:
        await repo.mark_meeting_present(resolved_meeting_id)
    return {
        "status": "success",
        "already_present": False,
        "message": "Kehadiran berhasil dikonfirmasi di Simkuliah.",
    }


async def _submit_card(
    client: SimkuliahClient,
    card: ParsedMeetingStatus,
    fallback_meeting_no: int | None,
    fallback_course: str | None,
    fallback_group: str | None,
) -> bool:
    return await client.confirm_presence(
        schedule_id=card.schedule_id,
        meeting_no=card.meeting_number or fallback_meeting_no,
        kelas=card.class_group or fallback_group or "",
        kd_mt_kul8=card.course_code or fallback_course or "",
        jadwal_mulai=card.jadwal_mulai,
        jadwal_berakhir=card.jadwal_berakhir,
        sks_mengajar=card.sks_mengajar,
        presence_id=str(card.schedule_id),
    )
