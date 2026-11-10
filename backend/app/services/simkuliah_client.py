"""Purpose: Asynchronous HTTP client for Simkuliah portal interaction.
Data & Logic Flow: Handles session authentication, cookie persistence, scraping, and presence actions.
Key Components: SimkuliahClient
"""

from __future__ import annotations

import time
from typing import Any

import httpx

from app.services.captcha import solve_captcha

BASE_URL = "https://simkuliah.usk.ac.id"

LOGIN_PATH = "/index.php/login/auth"
CAPTCHA_PATH = "/index.php/login/captcha_image"
DASHBOARD_PATH = "/index.php/absensi"
TODAY_SCHEDULE_PATH = "/index.php/jadwal_kuliah/jadwal_kuliah_hari_ini"
SEMESTER_MATRIX_PATH = "/index.php/jadwal_kuliah/index"
PRESENCE_PATH = "/index.php/absensi/konfirmasi_kehadiran"

MAX_LOGIN_ATTEMPTS = 3

# HTTP status codes treated as Simkuliah gateway/server errors that must be
# handled cleanly without crashing the caller.
SERVER_ERROR_STATUS_CODES = {500, 502, 503, 504}

_CAPTCHA_ERROR_MARKERS = ("kode verifikasi salah", "captcha", "verifikasi")

# Markers that indicate a 3xx Location header points back to the login page
# (authentication failed) rather than an authenticated destination.
_LOGIN_REDIRECT_MARKERS = ("/login", "login")

# Markers that indicate a 3xx Location header points to an authenticated
# destination (dashboard or mahasiswa area).
_AUTHENTICATED_DESTINATION_MARKERS = ("dashboard", "mahasiswa", "absensi")

# Name of the CodeIgniter session cookie established by a successful login.
_SESSION_COOKIE_NAME = "ci_session"


class SimkuliahClient:
    """Async HTTP client for Simkuliah with a persistent ``ci_session`` cookie jar.

    Args:
        npm: Student NIP/NPM used as the login username.
        password: Student account password.
        base_url: Base Simkuliah origin (default production USK portal).
    """

    def __init__(
        self,
        npm: str,
        password: str,
        base_url: str = BASE_URL,
    ) -> None:
        self.npm = npm
        self.password = password
        self.base_url = base_url.rstrip("/")
        # httpx.AsyncClient keeps a persistent cookie jar, so ci_session set by
        # the login response is automatically reused on subsequent requests.
        self._client = httpx.AsyncClient()

    # ------------------------------------------------------------------ #
    # Internal request helpers
    # ------------------------------------------------------------------ #

    async def _fetch_captcha(self) -> bytes:
        """Fetch a fresh CAPTCHA image and return its raw bytes."""
        url = f"{self.base_url}{CAPTCHA_PATH}"
        params = {"t": int(time.time())}
        response = await self._client.get(url, params=params)
        response.raise_for_status()
        return response.content

    async def _submit_login_form(self, captcha_answer: str) -> dict[str, Any]:
        """Submit the login form and return a normalised result dict.

        Returns a dict with a ``success`` boolean plus either a ``redirect``
        location (on success) or an ``error`` message (on failure).
        """
        response = await self._client.post(
            f"{self.base_url}{LOGIN_PATH}",
            data={
                "username": self.npm,
                "password": self.password,
                "captcha_answer": captcha_answer,
            },
            follow_redirects=False,
        )
        if response.status_code in SERVER_ERROR_STATUS_CODES:
            return {"success": False, "error": f"HTTP {response.status_code}"}

        if response.status_code in (301, 302, 303, 307, 308):
            location = response.headers.get("location", "")
            if self._is_authenticated_redirect(location):
                return {"success": True, "redirect": location}
            return {
                "success": False,
                "error": "Login redirected back to login page",
            }

        body = response.text
        if any(marker in body.lower() for marker in _CAPTCHA_ERROR_MARKERS):
            return {"success": False, "error": "Kode verifikasi salah"}

        return {"success": False, "error": "Login rejected by server"}

    def _is_authenticated_redirect(self, location: str) -> bool:
        """Return True when a 3xx Location points to an authenticated destination.

        A redirect back to the login page is treated as a failed authentication
        even though the HTTP status is 3xx. A redirect to the dashboard or
        mahasiswa area, or the presence of a ``ci_session`` cookie in the
        client's cookie jar, counts as authenticated.
        """
        lowered = location.lower()
        if any(marker in lowered for marker in _LOGIN_REDIRECT_MARKERS):
            return False
        if any(marker in lowered for marker in _AUTHENTICATED_DESTINATION_MARKERS):
            return True
        return _SESSION_COOKIE_NAME in self._client.cookies

    # ------------------------------------------------------------------ #
    # Public API
    # ------------------------------------------------------------------ #

    @property
    def is_authenticated(self) -> bool:
        """True when the cookie jar holds a ``ci_session`` cookie.

        The jar is in-memory, so this is False on every fresh process (right
        after a deploy or restart) until :meth:`login` succeeds.
        """
        return _SESSION_COOKIE_NAME in self._client.cookies

    async def login(self) -> bool:
        """Authenticate against Simkuliah with up to 3 CAPTCHA retry attempts.

        Each attempt fetches a fresh CAPTCHA image, solves it via
        :func:`solve_captcha`, and submits the login form. A "Kode verifikasi
        salah" (or similar CAPTCHA) failure triggers a retry with a new image.
        Returns ``True`` on successful authentication, ``False`` when all
        attempts are exhausted.
        """
        last_error: str | None = None
        for _attempt in range(1, MAX_LOGIN_ATTEMPTS + 1):
            try:
                image_bytes = await self._fetch_captcha()
            except httpx.HTTPError:
                # Transient CAPTCHA fetch error; try again with a fresh image.
                continue

            captcha_answer = solve_captcha(image_bytes)
            result = await self._submit_login_form(captcha_answer)

            if result.get("success") is True:
                return True

            last_error = result.get("error", "unknown error")
            if not self._is_captcha_error(last_error):
                # Non-CAPTCHA rejection is not worth retrying.
                break

        return False

    async def keep_alive(self) -> bool:
        """Refresh the ``ci_session`` by GETting the dashboard.

        Returns ``True`` when the dashboard is reachable (session alive),
        ``False`` on server errors (500/502/503/504) or network failure.
        """
        try:
            response = await self._client.get(f"{self.base_url}{DASHBOARD_PATH}")
            if response.status_code in SERVER_ERROR_STATUS_CODES:
                return False
            response.raise_for_status()
            return True
        except httpx.HTTPError:
            return False

    async def fetch_dashboard(self) -> str:
        """Return the raw HTML of the main absensi dashboard page."""
        return await self._get_html(DASHBOARD_PATH)

    async def fetch_today_schedule(self) -> str:
        """Return the raw HTML of today's schedule page."""
        return await self._get_html(TODAY_SCHEDULE_PATH)

    async def fetch_semester_matrix(self) -> str:
        """Return the raw HTML of the semester presence matrix page."""
        return await self._get_html(SEMESTER_MATRIX_PATH)

    async def confirm_presence(
        self,
        schedule_id: int | None = None,
        meeting_no: int | None = None,
        *,
        kelas: str = "",
        kd_mt_kul8: str = "",
        jadwal_mulai: str = "",
        jadwal_berakhir: str = "",
        sks_mengajar: str = "2",
        presence_id: str | None = None,
    ) -> bool:
        """Confirm presence for a schedule meeting.

        POSTs actual Simkuliah AJAX payload or falls back to legacy parameters
        using the authenticated cookie jar.
        """
        try:
            if kelas and kd_mt_kul8:
                payload = {
                    "kelas": kelas,
                    "kd_mt_kul8": kd_mt_kul8,
                    "jadwal_mulai": jadwal_mulai,
                    "jadwal_berakhir": jadwal_berakhir,
                    "pertemuan": str(meeting_no or 1),
                    "sks_mengajar": sks_mengajar,
                    "id": presence_id or str(schedule_id or ""),
                }
            else:
                payload = {
                    "id_jadwal": schedule_id,
                    "pertemuan": meeting_no,
                    "status": "hadir",
                }

            response = await self._client.post(
                f"{self.base_url}{PRESENCE_PATH}",
                data=payload,
            )
            if response.status_code in SERVER_ERROR_STATUS_CODES:
                return False
            response.raise_for_status()
            text = response.text if isinstance(response.text, str) else ""
            return "success" in text.lower() or response.status_code == 200
        except httpx.HTTPError:
            return False

    async def aclose(self) -> None:
        """Close the underlying HTTP client and release its connection pool."""
        await self._client.aclose()

    # ------------------------------------------------------------------ #
    # Private helpers
    # ------------------------------------------------------------------ #

    async def _get_html(self, path: str) -> str:
        """GET ``path`` and return its body as text, or ``""`` on server error."""
        try:
            response = await self._client.get(f"{self.base_url}{path}")
            if response.status_code in SERVER_ERROR_STATUS_CODES:
                return ""
            response.raise_for_status()
            return response.text
        except httpx.HTTPError:
            return ""

    @staticmethod
    def _is_captcha_error(error: str | None) -> bool:
        if not error:
            return False
        lowered = error.lower()
        return any(marker in lowered for marker in _CAPTCHA_ERROR_MARKERS)
