"""Purpose: Shared notification copy and state policy for every dispatcher.
Data & Logic Flow: Turns a notification state plus its meeting context into one
canonical course label, title, and body, and declares which states are
actionable, so FCM and ntfy never drift apart.
Key Components: STATE_TITLES, ACTIONABLE_STATES, course_label, notification_text
"""

from __future__ import annotations

from app.services.state_machine import NotificationLevel

# Notification titles per state. A course label is appended so two
# simultaneous classes are distinguishable in the notification shade.
STATE_TITLES = {
    NotificationLevel.CLASS_STARTED: "Kelas Dimulai",
    NotificationLevel.LECTURER_OPENED: "Presensi Dibuka",
    NotificationLevel.PENDING_REMINDER: "Pengingat Presensi",
    NotificationLevel.URGENT_CLOSING: "Presensi Segera Ditutup",
    NotificationLevel.WINDOW_EXPIRED: "Presensi Ditutup",
}

# Only states where the student can still act carry action buttons. A
# "class started" alert fires before the lecturer opens presence, and an
# expired window can no longer be confirmed, so buttons there are noise.
ACTIONABLE_STATES = frozenset(
    {
        NotificationLevel.LECTURER_OPENED,
        NotificationLevel.PENDING_REMINDER,
        NotificationLevel.URGENT_CLOSING,
    }
)


def course_label(context: dict) -> str:
    """Course name first, code second: the code alone is hard to read.

    ``"Grafika Komputer (INF201)"`` keeps two simultaneous notifications
    distinguishable while staying short enough for a title.
    """
    course_code = context.get("course_code", "")
    course_name = context.get("course_name", "")
    label = course_name or course_code or "Kelas"
    if course_name and course_code and course_code not in course_name:
        label = f"{course_name} ({course_code})"
    return label


def notification_title(state: NotificationLevel, context: dict) -> str:
    return f"{STATE_TITLES[state]} - {course_label(context)}"


def notification_text(state: NotificationLevel, context: dict) -> str:
    label = course_label(context)
    room = context.get("room", "")
    lecturer = context.get("lecturer", "")
    where = f" di {room}" if room else ""
    who = f" - {lecturer}" if lecturer else ""
    base = f"{label}{where}{who}"
    texts = {
        NotificationLevel.CLASS_STARTED: f"Kelas dimulai: {base}.",
        NotificationLevel.LECTURER_OPENED: f"Dosen telah buka presensi: {base}.",
        NotificationLevel.PENDING_REMINDER: f"Pengingat: segera konfirmasi presensi {base}.",
        NotificationLevel.URGENT_CLOSING: f"Presensi hampir tutup: {base}.",
        NotificationLevel.WINDOW_EXPIRED: f"Jendela presensi telah tutup: {base}.",
    }
    return texts[state]
