"""Purpose: Unit tests for Simkuliah asynchronous HTTP client and session management.
Data & Logic Flow: Tests login flow, CAPTCHA retries, keep-alive heartbeats, and error responses.
Key Components: test_login_success, test_login_captcha_retry
"""

from __future__ import annotations

from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from app.services.simkuliah_client import SimkuliahClient


@pytest.mark.asyncio
async def test_login_success():
    client = SimkuliahClient(npm="2408107010053", password="test_password")

    with (
        patch.object(client, "_fetch_captcha", new_callable=AsyncMock) as mock_cap,
        patch("app.services.simkuliah_client.solve_captcha", return_value="46272"),
        patch.object(client, "_submit_login_form", new_callable=AsyncMock) as mock_sub,
    ):
        mock_cap.return_value = b"image_data"
        mock_sub.return_value = {
            "success": True,
            "redirect": "/index.php/mahasiswa/dashboard",
        }

        status = await client.login()
        assert status is True
        assert mock_cap.call_count == 1
        assert mock_sub.call_count == 1


@pytest.mark.asyncio
async def test_login_captcha_retry():
    client = SimkuliahClient(npm="2408107010053", password="test_password")

    with (
        patch.object(client, "_fetch_captcha", new_callable=AsyncMock) as mock_cap,
        patch("app.services.simkuliah_client.solve_captcha", return_value="12345"),
        patch.object(client, "_submit_login_form", new_callable=AsyncMock) as mock_sub,
    ):
        mock_cap.return_value = b"image_data"
        mock_sub.side_effect = [
            {"success": False, "error": "Kode verifikasi salah"},
            {"success": True, "redirect": "/index.php/mahasiswa/dashboard"},
        ]

        status = await client.login()
        assert status is True
        assert mock_sub.call_count == 2


@pytest.mark.asyncio
async def test_login_all_attempts_exhausted():
    client = SimkuliahClient(npm="2408107010053", password="test_password")

    with (
        patch.object(client, "_fetch_captcha", new_callable=AsyncMock) as mock_cap,
        patch("app.services.simkuliah_client.solve_captcha", return_value="00000"),
        patch.object(client, "_submit_login_form", new_callable=AsyncMock) as mock_sub,
    ):
        mock_cap.return_value = b"image_data"
        mock_sub.return_value = {"success": False, "error": "Kode verifikasi salah"}

        status = await client.login()
        assert status is False
        assert mock_sub.call_count == 3


@pytest.mark.asyncio
async def test_keep_alive_success():
    client = SimkuliahClient(npm="2408107010053", password="test_password")
    mock_response = AsyncMock()
    mock_response.status_code = 200
    mock_response.raise_for_status = MagicMock()
    client._client.get = AsyncMock(return_value=mock_response)

    status = await client.keep_alive()
    assert status is True


@pytest.mark.asyncio
async def test_keep_alive_server_error():
    client = SimkuliahClient(npm="2408107010053", password="test_password")
    mock_response = AsyncMock()
    mock_response.status_code = 502
    mock_response.raise_for_status = MagicMock()
    client._client.get = AsyncMock(return_value=mock_response)

    status = await client.keep_alive()
    assert status is False


@pytest.mark.asyncio
async def test_fetch_today_schedule_returns_html():
    client = SimkuliahClient(npm="2408107010053", password="test_password")
    mock_response = AsyncMock()
    mock_response.status_code = 200
    mock_response.text = "<html><body>today schedule</body></html>"
    mock_response.raise_for_status = MagicMock()
    client._client.get = AsyncMock(return_value=mock_response)

    html = await client.fetch_today_schedule()
    assert html == "<html><body>today schedule</body></html>"


@pytest.mark.asyncio
async def test_fetch_semester_matrix_returns_html():
    client = SimkuliahClient(npm="2408107010053", password="test_password")
    mock_response = AsyncMock()
    mock_response.status_code = 200
    mock_response.text = "<html><body>semester matrix</body></html>"
    mock_response.raise_for_status = MagicMock()
    client._client.get = AsyncMock(return_value=mock_response)

    html = await client.fetch_semester_matrix()
    assert html == "<html><body>semester matrix</body></html>"


@pytest.mark.asyncio
async def test_confirm_presence_success():
    client = SimkuliahClient(npm="2408107010053", password="test_password")
    mock_response = AsyncMock()
    mock_response.status_code = 200
    mock_response.raise_for_status = MagicMock()
    client._client.post = AsyncMock(return_value=mock_response)

    status = await client.confirm_presence(schedule_id=101, meeting_no=4)
    assert status is True


@pytest.mark.asyncio
async def test_confirm_presence_server_error():
    client = SimkuliahClient(npm="2408107010053", password="test_password")
    mock_response = AsyncMock()
    mock_response.status_code = 500
    mock_response.raise_for_status = MagicMock()
    client._client.post = AsyncMock(return_value=mock_response)

    status = await client.confirm_presence(schedule_id=101, meeting_no=4)
    assert status is False


@pytest.mark.asyncio
async def test_login_redirect_back_to_login_fails():
    """A 3xx redirect back to /login must be rejected even though HTTP is 3xx."""
    client = SimkuliahClient(npm="2408107010053", password="test_password")

    with (
        patch.object(client, "_fetch_captcha", new_callable=AsyncMock) as mock_cap,
        patch("app.services.simkuliah_client.solve_captcha", return_value="00000"),
    ):
        mock_cap.return_value = b"image_data"
        mock_response = MagicMock()
        mock_response.status_code = 302
        mock_response.headers = {"location": "/index.php/login?error=1"}
        client._client.post = AsyncMock(return_value=mock_response)

        status = await client.login()
        assert status is False


@pytest.mark.asyncio
async def test_login_redirect_to_dashboard_succeeds():
    """A 3xx redirect to the dashboard is accepted as authenticated."""
    client = SimkuliahClient(npm="2408107010053", password="test_password")

    with (
        patch.object(client, "_fetch_captcha", new_callable=AsyncMock) as mock_cap,
        patch("app.services.simkuliah_client.solve_captcha", return_value="46272"),
    ):
        mock_cap.return_value = b"image_data"
        mock_response = MagicMock()
        mock_response.status_code = 302
        mock_response.headers = {"location": "/index.php/mahasiswa/dashboard"}
        client._client.post = AsyncMock(return_value=mock_response)

        status = await client.login()
        assert status is True


@pytest.mark.asyncio
async def test_auth_async_context_manager_closes_client():
    """SimkuliahAuth supports async context manager protocol and closes on exit."""
    import os

    os.environ.setdefault("SIMKULIAH_NPM", "2408107010053")
    os.environ.setdefault("SIMKULIAH_PASSWORD", "test_password")
    os.environ.setdefault("NTFY_TOPIC", "test-topic")
    os.environ.setdefault("ACTION_SECRET_KEY", "test-secret-key-32-chars-long-123456")
    os.environ.setdefault("SUPABASE_URL", "https://example.supabase.co")
    os.environ.setdefault("SUPABASE_SERVICE_ROLE_KEY", "service-role-key")

    from app.services.simkuliah_auth import SimkuliahAuth

    auth = SimkuliahAuth.__new__(SimkuliahAuth)
    auth.client = SimkuliahClient(npm="2408107010053", password="test_password")
    auth.client.aclose = AsyncMock()

    async with auth:
        pass

    auth.client.aclose.assert_awaited_once()


def test_is_authenticated_reflects_cookie_jar():
    client = SimkuliahClient(npm="2408107010053", password="secret")
    # A fresh client has an empty in-memory cookie jar.
    assert client.is_authenticated is False
    client._client.cookies.set("ci_session", "session-token")
    assert client.is_authenticated is True
