"""Unit tests for the Simkuliah async HTTP client and session authenticator.

Covers the login flow with CAPTCHA retry, keep-alive heartbeat, schedule /
semester matrix fetching, presence confirmation, and HTTP 500/502/504 error
handling. All external HTTP is mocked so tests run offline and deterministic.
"""

from __future__ import annotations

from unittest.mock import AsyncMock, patch

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
    client._client.get = AsyncMock(return_value=mock_response)

    status = await client.keep_alive()
    assert status is True


@pytest.mark.asyncio
async def test_keep_alive_server_error():
    client = SimkuliahClient(npm="2408107010053", password="test_password")
    mock_response = AsyncMock()
    mock_response.status_code = 502
    client._client.get = AsyncMock(return_value=mock_response)

    status = await client.keep_alive()
    assert status is False


@pytest.mark.asyncio
async def test_fetch_today_schedule_returns_html():
    client = SimkuliahClient(npm="2408107010053", password="test_password")
    mock_response = AsyncMock()
    mock_response.status_code = 200
    mock_response.text = "<html><body>today schedule</body></html>"
    client._client.get = AsyncMock(return_value=mock_response)

    html = await client.fetch_today_schedule()
    assert html == "<html><body>today schedule</body></html>"


@pytest.mark.asyncio
async def test_fetch_semester_matrix_returns_html():
    client = SimkuliahClient(npm="2408107010053", password="test_password")
    mock_response = AsyncMock()
    mock_response.status_code = 200
    mock_response.text = "<html><body>semester matrix</body></html>"
    client._client.get = AsyncMock(return_value=mock_response)

    html = await client.fetch_semester_matrix()
    assert html == "<html><body>semester matrix</body></html>"


@pytest.mark.asyncio
async def test_confirm_presence_success():
    client = SimkuliahClient(npm="2408107010053", password="test_password")
    mock_response = AsyncMock()
    mock_response.status_code = 200
    client._client.post = AsyncMock(return_value=mock_response)

    status = await client.confirm_presence(schedule_id=101, meeting_no=4)
    assert status is True


@pytest.mark.asyncio
async def test_confirm_presence_server_error():
    client = SimkuliahClient(npm="2408107010053", password="test_password")
    mock_response = AsyncMock()
    mock_response.status_code = 500
    client._client.post = AsyncMock(return_value=mock_response)

    status = await client.confirm_presence(schedule_id=101, meeting_no=4)
    assert status is False
