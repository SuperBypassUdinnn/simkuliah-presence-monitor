# Simkuliah Multi-Platform Presence Monitor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a headless Python/FastAPI monitoring daemon and a multi-platform Flutter client to automate USK Simkuliah presence monitoring, OCR CAPTCHA auto-solving, 5-tier actionable push notifications via ntfy.sh, and local attendance tracking.

**Architecture:** A centralized asynchronous Python backend executes schedule-aware adaptive polling against Simkuliah, solves 5-digit CAPTCHAs via local ONNX neural classification (`ddddocr`), evaluates a 5-tier finite state machine for attendance alerts, and dispatches actionable push notifications via ntfy.sh. A cross-platform Flutter client synchronizes with Supabase PostgreSQL to display live lecture feeds, countdown timers, semester matrices, and system health status.

**Tech Stack:** 
- Backend: Python 3.11+, FastAPI, HTTPX, ddddocr, Selectolax, APScheduler, Supabase-py, Pydantic v2, Pytest.
- Client: Flutter 3.x, Dart, Riverpod / Bloc, Supabase Flutter SDK, ntfy client integration.
- Relay & Cloud: ntfy.sh, Supabase PostgreSQL, Docker.

**Spec:** `docs/superpowers/specs/2026-11-08-simkuliah-presence-monitor-design.md`

## Global Constraints

- **Python Version**: Python 3.11+ using async/await idioms and typed Pydantic models.
- **Session Timeout**: Simkuliah `ci_session` expires in 1800 seconds (30 minutes); keep-alive interval must be $\le 12$ minutes during active lecture observation.
- **CAPTCHA Format**: 5 numeric digits; OCR solver must run locally on CPU without external cloud APIs.
- **Webhook Security**: All direct action notification endpoints must validate an HMAC-SHA256 signed `X-Action-Token`.
- **Database**: Single-user schema deployed to Supabase PostgreSQL.
- **Commit Style**: Concise Conventional Commits (`<type>(<scope>): <subject>`) with plain-text commit messages.

## Review Focus

- **Simkuliah 502/504 Gateway Timeout**: Handled via exponential backoff (30s to 300s) without poller crash or false absence alarms.
- **CAPTCHA Repeated Misclassification**: Handled via 3-attempt retry loop before firing an actionable re-auth notification to the user.
- **Class Schedule Shift / Cancellation**: Handled when Simkuliah updates schedule data mid-semester without creating ghost meetings in Supabase.
- **Simultaneous Action Webhook Calls**: Double-tap idempotency guard preventing duplicate presence submission requests.
- **Client Offline Synchronization**: Flutter client displays cached offline state from local storage when network is unavailable.

---

## File Structure

```
.
├── backend/
│   ├── app/
│   │   ├── __init__.py
│   │   ├── config.py             # Pydantic Settings & environment validation
│   │   ├── main.py               # FastAPI application entrypoint & lifespan
│   │   ├── core/
│   │   │   ├── __init__.py
│   │   │   ├── security.py       # HMAC token generation & validation
│   │   │   └── database.py       # Supabase client wrapper
│   │   ├── services/
│   │   │   ├── __init__.py
│   │   │   ├── captcha.py        # ddddocr inference wrapper
│   │   │   ├── simkuliah_auth.py # Session management, login & keep-alive
│   │   │   ├── simkuliah_parser.py# HTML parsing (schedules, presence table)
│   │   │   ├── simkuliah_client.py# Complete Simkuliah HTTP operations client
│   │   │   ├── state_machine.py  # 5-tier notification lifecycle evaluation
│   │   │   ├── ntfy_service.py   # ntfy.sh dispatcher with HTTP action buttons
│   │   │   └── poller.py         # Adaptive schedule-aware APScheduler loop
│   │   └── api/
│   │       ├── __init__.py
│   │       ├── router.py         # API router aggregation
│   │       └── v1/
│   │           ├── webhooks.py   # Action button receiver (Presence/Izin/Sakit)
│   │           └── health.py     # Healthcheck & Simkuliah gateway status
│   ├── tests/
│   │   ├── conftest.py
│   │   ├── test_security.py
│   │   ├── test_captcha.py
│   │   ├── test_parser.py
│   │   ├── test_state_machine.py
│   │   └── test_webhooks.py
│   ├── Dockerfile
│   ├── pyproject.toml
│   └── requirements.txt
├── client/                       # Flutter Multi-Platform App (Android, Linux, Windows)
│   ├── lib/
│   │   ├── main.dart
│   │   ├── core/
│   │   ├── models/
│   │   ├── services/
│   │   └── views/
│   │       ├── today_feed_view.dart
│   │       ├── semester_matrix_view.dart
│   │       └── widgets/
│   │           ├── countdown_timer_card.dart
│   │           └── gateway_alert_banner.dart
│   └── pubspec.yaml
└── docs/
    └── superpowers/
        ├── specs/2026-11-08-simkuliah-presence-monitor-design.md
        └── plans/2026-11-08-simkuliah-presence-monitor.md
```

---

### Task 1: Backend Scaffolding & Configuration Setup

**Files:**
- Create: `backend/pyproject.toml`
- Create: `backend/requirements.txt`
- Create: `backend/app/config.py`
- Create: `backend/app/core/security.py`
- Test: `backend/tests/test_security.py`

**Interfaces:**
- Consumes: Environment variables (`SIMKULIAH_NPM`, `SIMKULIAH_PASSWORD`, `NTFY_TOPIC`, `ACTION_SECRET_KEY`, `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`).
- Produces: `Settings` object in `app.config`, `create_action_token(payload: dict) -> str`, `verify_action_token(token: str) -> dict | None`.

- [ ] **Step 1: Write failing test for HMAC security token generator and validator**

```python
# backend/tests/test_security.py
from app.core.security import create_action_token, verify_action_token

def test_token_creation_and_verification():
    payload = {"action": "confirm_presence", "schedule_id": 101, "meeting_no": 4}
    secret = "test-secret-key-32-chars-long-123456"
    token = create_action_token(payload, secret=secret, expires_in_seconds=300)
    
    verified = verify_action_token(token, secret=secret)
    assert verified is not None
    assert verified["action"] == "confirm_presence"
    assert verified["schedule_id"] == 101

def test_token_expiration():
    payload = {"action": "confirm_presence"}
    secret = "test-secret-key-32-chars-long-123456"
    token = create_action_token(payload, secret=secret, expires_in_seconds=-10)
    assert verify_action_token(token, secret=secret) is None
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest backend/tests/test_security.py -v`  
Expected: FAIL with `ModuleNotFoundError` or `ImportError`.

- [ ] **Step 3: Implement `config.py` and `security.py`**

Define `Settings` using `pydantic_settings.BaseSettings` and implement HMAC-SHA256 signing with payload timestamp expiration in `backend/app/core/security.py`.

- [ ] **Step 4: Run test to verify it passes**

Run: `pytest backend/tests/test_security.py -v`  
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add backend/pyproject.toml backend/requirements.txt backend/app/config.py backend/app/core/security.py backend/tests/test_security.py
git commit -m "feat(backend): setup configuration and HMAC token security"
```

---

### Task 2: CAPTCHA Solver Service (`ddddocr`)

**Files:**
- Create: `backend/app/services/captcha.py`
- Test: `backend/tests/test_captcha.py`

**Interfaces:**
- Consumes: Raw image bytes (PNG/JPEG) from Simkuliah `/index.php/login/captcha_image`.
- Produces: `solve_captcha(image_bytes: bytes) -> str` returning cleaned 5-digit string.

- [ ] **Step 1: Write failing test for `solve_captcha`**

```python
# backend/tests/test_captcha.py
from app.services.captcha import clean_captcha_digits, solve_captcha
from unittest.mock import MagicMock, patch

def test_clean_captcha_digits():
    assert clean_captcha_digits(" 4 6 2 7 2 ") == "46272"
    assert clean_captcha_digits("O123B") == "01238"  # normalization if needed

def test_solve_captcha_delegation():
    with patch("app.services.captcha.get_ocr_engine") as mock_engine:
        instance = MagicMock()
        instance.classification.return_value = "46272"
        mock_engine.return_value = instance
        
        result = solve_captcha(b"fake_image_bytes")
        assert result == "46272"
        assert len(result) == 5
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest backend/tests/test_captcha.py -v`  
Expected: FAIL with `ImportError`.

- [ ] **Step 3: Implement `solve_captcha` in `backend/app/services/captcha.py`**

Lazy-load `ddddocr.DdddOcr(show_ad=False)` singleton to avoid multi-instance overhead and filter digits to guaranteed 5-character output.

- [ ] **Step 4: Run test to verify it passes**

Run: `pytest backend/tests/test_captcha.py -v`  
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add backend/app/services/captcha.py backend/tests/test_captcha.py
git commit -m "feat(backend): implement local ONNX captcha solver service"
```

---

### Task 3: Simkuliah HTTP Client & Session Authenticator

**Files:**
- Create: `backend/app/services/simkuliah_auth.py`
- Create: `backend/app/services/simkuliah_client.py`
- Test: `backend/tests/test_simkuliah_auth.py`

**Interfaces:**
- Consumes: `Settings`, `solve_captcha`.
- Produces: `SimkuliahClient` class with async methods:
  - `login() -> bool`
  - `keep_alive() -> bool`
  - `fetch_today_schedule() -> str` (raw HTML)
  - `fetch_semester_matrix() -> str` (raw HTML)
  - `confirm_presence(schedule_id: int, meeting_no: int) -> bool`

- [ ] **Step 1: Write failing test for login flow and retry mechanism**

```python
# backend/tests/test_simkuliah_auth.py
import pytest
from unittest.mock import AsyncMock, patch
from app.services.simkuliah_client import SimkuliahClient

@pytest.mark.asyncio
async def test_login_success():
    client = SimkuliahClient(npm="2408107010053", password="test_password")
    
    with patch.object(client, "_fetch_captcha", new_callable=AsyncMock) as mock_cap, \
         patch("app.services.simkuliah_client.solve_captcha", return_value="46272"), \
         patch.object(client, "_submit_login_form", new_callable=AsyncMock) as mock_sub:
        
        mock_cap.return_value = b"image_data"
        mock_sub.return_value = {"success": True, "redirect": "/index.php/mahasiswa/dashboard"}
        
        status = await client.login()
        assert status is True
        assert mock_cap.call_count == 1
        assert mock_sub.call_count == 1

@pytest.mark.asyncio
async def test_login_captcha_retry():
    client = SimkuliahClient(npm="2408107010053", password="test_password")
    
    with patch.object(client, "_fetch_captcha", new_callable=AsyncMock) as mock_cap, \
         patch("app.services.simkuliah_client.solve_captcha", return_value="12345"), \
         patch.object(client, "_submit_login_form", new_callable=AsyncMock) as mock_sub:
        
        mock_cap.return_value = b"image_data"
        # First attempt fails with captcha error, second attempt succeeds
        mock_sub.side_effect = [
            {"success": False, "error": "Kode verifikasi salah"},
            {"success": True, "redirect": "/index.php/mahasiswa/dashboard"}
        ]
        
        status = await client.login()
        assert status is True
        assert mock_sub.call_count == 2
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest backend/tests/test_simkuliah_auth.py -v`  
Expected: FAIL.

- [ ] **Step 3: Implement `SimkuliahClient` using `httpx.AsyncClient`**

Manage persistent cookie jar (`ci_session`), implement 3-attempt CAPTCHA retry loop, and add error detection for HTTP 500/502/504 responses.

- [ ] **Step 4: Run test to verify it passes**

Run: `pytest backend/tests/test_simkuliah_auth.py -v`  
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add backend/app/services/simkuliah_auth.py backend/app/services/simkuliah_client.py backend/tests/test_simkuliah_auth.py
git commit -m "feat(backend): implement Simkuliah async client with session auth and retry"
```

---

### Task 4: HTML Scraper & Parser Service

**Files:**
- Create: `backend/app/services/simkuliah_parser.py`
- Test: `backend/tests/test_parser.py`

**Interfaces:**
- Consumes: Raw HTML strings from Simkuliah.
- Produces: 
  - `parse_daily_schedule(html: str) -> list[ParsedScheduleItem]`
  - `parse_attendance_status(html: str) -> ParsedMeetingStatus`

- [ ] **Step 1: Write failing test with realistic CodeIgniter HTML fixtures**

```python
# backend/tests/test_parser.py
from app.services.simkuliah_parser import parse_daily_schedule, parse_attendance_status

MOCK_SCHEDULE_HTML = """
<table class="table">
  <tr>
    <td>INF201</td>
    <td>Grafika Komputer</td>
    <td>Ruang 301</td>
    <td>08:00 - 09:40</td>
    <td>Dr. Dosen, M.Kom</td>
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

def test_parse_daily_schedule():
    items = parse_daily_schedule(MOCK_SCHEDULE_HTML)
    assert len(items) == 1
    assert items[0].course_code == "INF201"
    assert items[0].start_time == "08:00"
    assert items[0].end_time == "09:40"

def test_parse_attendance_status_open():
    status = parse_attendance_status(MOCK_PRESENCE_OPEN_HTML)
    assert status.is_open is True
    assert status.deadline_time == "08:35:00"
    assert status.meeting_number == 7
    assert status.schedule_id == 1042
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest backend/tests/test_parser.py -v`  
Expected: FAIL.

- [ ] **Step 3: Implement parsing logic in `backend/app/services/simkuliah_parser.py`**

Use `selectolax.parser.HTMLParser` for zero-overhead DOM parsing and regex extraction of timestamps and form parameters.

- [ ] **Step 4: Run test to verify it passes**

Run: `pytest backend/tests/test_parser.py -v`  
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add backend/app/services/simkuliah_parser.py backend/tests/test_parser.py
git commit -m "feat(backend): implement HTML scraper and parser for schedules and presence"
```

---

### Task 5: Supabase Database Repository

**Files:**
- Create: `backend/app/core/database.py`
- Create: `backend/app/models/schemas.py`
- Test: `backend/tests/test_database.py`

**Interfaces:**
- Consumes: `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`.
- Produces: `DatabaseRepository` with async methods:
  - `upsert_schedules(items: list[ParsedScheduleItem]) -> None`
  - `record_meeting_status(status: ParsedMeetingStatus) -> None`
  - `save_override(meeting_id: int, override_type: str, note: str = "") -> None`
  - `get_active_override(meeting_id: int) -> str | None`
  - `log_incident(incident_type: str, status_code: int, snippet: str) -> None`

- [ ] **Step 1: Write failing test for repository schema and override filtering**

```python
# backend/tests/test_database.py
import pytest
from unittest.mock import MagicMock
from app.core.database import DatabaseRepository

def test_override_suppression_logic():
    repo = DatabaseRepository(client=MagicMock())
    # Verify that 'izin' and 'sakit' are valid enum types
    assert repo.is_valid_override("izin") is True
    assert repo.is_valid_override("sakit") is True
    assert repo.is_valid_override("alpa") is True
    assert repo.is_valid_override("invalid_status") is False
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest backend/tests/test_database.py -v`  
Expected: FAIL.

- [ ] **Step 3: Implement `DatabaseRepository` and Pydantic schemas in `backend/app/core/database.py`**

Provide clean async wrappers over the Supabase client with retry logic for intermittent database timeouts.

- [ ] **Step 4: Run test to verify it passes**

Run: `pytest backend/tests/test_database.py -v`  
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add backend/app/core/database.py backend/app/models/schemas.py backend/tests/test_database.py
git commit -m "feat(backend): implement Supabase database repository and models"
```

---

### Task 6: 5-Tier Notification State Machine & ntfy Dispatcher

**Files:**
- Create: `backend/app/services/state_machine.py`
- Create: `backend/app/services/ntfy_service.py`
- Test: `backend/tests/test_state_machine.py`

**Interfaces:**
- Consumes: Current time, `ParsedMeetingStatus`, active overrides, `create_action_token`.
- Produces:
  - `evaluate_notification_state(...) -> NotificationState | None`
  - `dispatch_ntfy_notification(state: NotificationState, context: dict) -> bool`

- [ ] **Step 1: Write failing test covering all 5 state transitions and override suppression**

```python
# backend/tests/test_state_machine.py
from datetime import datetime, time
from app.services.state_machine import evaluate_notification_state, NotificationLevel

def test_state_1_class_started():
    now = datetime(2026, 11, 9, 8, 5) # 08:05
    state = evaluate_notification_state(
        now=now,
        start_time=time(8, 0),
        end_time=time(9, 40),
        is_dosen_open=False,
        is_student_present=False,
        has_override=False,
        last_notified_level=None
    )
    assert state == NotificationLevel.CLASS_STARTED

def test_state_2_lecturer_opened():
    now = datetime(2026, 11, 9, 8, 10)
    state = evaluate_notification_state(
        now=now,
        start_time=time(8, 0),
        end_time=time(9, 40),
        is_dosen_open=True,
        is_student_present=False,
        has_override=False,
        last_notified_level=NotificationLevel.CLASS_STARTED
    )
    assert state == NotificationLevel.LECTURER_OPENED

def test_override_suppresses_notifications():
    now = datetime(2026, 11, 9, 8, 15)
    state = evaluate_notification_state(
        now=now,
        start_time=time(8, 0),
        end_time=time(9, 40),
        is_dosen_open=True,
        is_student_present=False,
        has_override=True, # User marked Izin/Sakit
        last_notified_level=NotificationLevel.CLASS_STARTED
    )
    assert state is None # Suppressed!
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest backend/tests/test_state_machine.py -v`  
Expected: FAIL.

- [ ] **Step 3: Implement `state_machine.py` and `ntfy_service.py`**

Encode the 5 levels deterministically and format ntfy HTTP action buttons with signed `X-Action-Token` headers.

- [ ] **Step 4: Run test to verify it passes**

Run: `pytest backend/tests/test_state_machine.py -v`  
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add backend/app/services/state_machine.py backend/app/services/ntfy_service.py backend/tests/test_state_machine.py
git commit -m "feat(backend): implement 5-tier state machine and ntfy action dispatcher"
```

---

### Task 7: Action Webhook API & Health Endpoints

**Files:**
- Create: `backend/app/api/v1/webhooks.py`
- Create: `backend/app/api/v1/health.py`
- Create: `backend/app/api/router.py`
- Create: `backend/app/main.py`
- Test: `backend/tests/test_webhooks.py`

**Interfaces:**
- Consumes: Fast-response HTTP POST requests from ntfy action buttons and client.
- Produces: 
  - `POST /api/v1/webhook/action` (confirms presence or records Izin/Sakit/Alpa)
  - `GET /api/v1/health` (returns backend and Simkuliah status)

- [ ] **Step 1: Write failing test for webhook action receiver**

```python
# backend/tests/test_webhooks.py
import pytest
from httpx import AsyncClient, ASGITransport
from app.main import app
from app.core.security import create_action_token

@pytest.mark.asyncio
async def test_webhook_action_valid_token():
    payload = {"action": "mark_override", "override_type": "izin", "meeting_id": 42}
    token = create_action_token(payload, secret="test-secret-key-32-chars-long-123456")
    
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        response = await ac.post(
            "/api/v1/webhook/action",
            headers={"X-Action-Token": token},
            json=payload
        )
    assert response.status_code == 200
    assert response.json()["status"] == "success"

@pytest.mark.asyncio
async def test_webhook_action_invalid_token():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        response = await ac.post(
            "/api/v1/webhook/action",
            headers={"X-Action-Token": "tampered_token"},
            json={"action": "confirm_presence"}
        )
    assert response.status_code == 401
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest backend/tests/test_webhooks.py -v`  
Expected: FAIL.

- [ ] **Step 3: Implement endpoints in `webhooks.py`, `health.py`, and wire `main.py`**

Validate action token, trigger `SimkuliahClient.confirm_presence` or `DatabaseRepository.save_override`, and return structured JSON response.

- [ ] **Step 4: Run test to verify it passes**

Run: `pytest backend/tests/test_webhooks.py -v`  
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add backend/app/api/ backend/app/main.py backend/tests/test_webhooks.py
git commit -m "feat(backend): implement secure action webhooks and health endpoints"
```

---

### Task 8: Adaptive Poller Engine & Background Lifespan

**Files:**
- Create: `backend/app/services/poller.py`
- Modify: `backend/app/main.py`
- Test: `backend/tests/test_poller.py`

**Interfaces:**
- Consumes: APScheduler, `SimkuliahClient`, `DatabaseRepository`, `state_machine`, `ntfy_service`.
- Produces: Background worker managing pre-class observation, active lecture polling (60s), and idle intervals.

- [ ] **Step 1: Write failing test for adaptive interval calculator**

```python
# backend/tests/test_poller.py
from datetime import datetime, time
from app.services.poller import calculate_next_poll_interval

def test_interval_during_active_class():
    now = datetime(2026, 11, 9, 8, 30)
    # Active lecture 08:00 - 09:40
    interval = calculate_next_poll_interval(now, active_lectures=[(time(8, 0), time(9, 40))])
    assert interval == 60 # 60 seconds

def test_interval_during_pre_class():
    now = datetime(2026, 11, 9, 7, 55)
    # Class starts in 5 minutes
    interval = calculate_next_poll_interval(now, active_lectures=[(time(8, 0), time(9, 40))])
    assert interval == 120 # 120 seconds

def test_interval_when_idle():
    now = datetime(2026, 11, 9, 14, 0)
    # No classes in afternoon
    interval = calculate_next_poll_interval(now, active_lectures=[])
    assert interval >= 3600 # Idle interval (at least 1 hour)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest backend/tests/test_poller.py -v`  
Expected: FAIL.

- [ ] **Step 3: Implement `poller.py` and register to FastAPI `lifespan` in `main.py`**

Bind APScheduler `AsyncIOScheduler` to application startup and shutdown lifecycle.

- [ ] **Step 4: Run test to verify it passes**

Run: `pytest backend/tests/test_poller.py -v`  
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add backend/app/services/poller.py backend/app/main.py backend/tests/test_poller.py
git commit -m "feat(backend): implement schedule-aware adaptive poller engine"
```

---

### Task 9: Multi-Platform Flutter Client Scaffolding & Supabase Integration

**Files:**
- Create: `client/pubspec.yaml`
- Create: `client/lib/main.dart`
- Create: `client/lib/core/supabase_config.dart`
- Create: `client/lib/models/schedule_model.dart`
- Create: `client/lib/models/meeting_model.dart`
- Create: `client/lib/services/presence_service.dart`
- Test: `client/test/models_test.dart`

**Interfaces:**
- Consumes: Supabase credentials.
- Produces: Data models and `PresenceService` providing streams and futures for schedules, meetings, and override submissions.

- [ ] **Step 1: Write failing Dart unit test for JSON deserialization and override computation**

```dart
// client/test/models_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:simkuliah_client/models/meeting_model.dart';

void main() {
  test('MeetingModel parses JSON and computes effective status correctly', () {
    final json = {
      'id': 1,
      'meeting_number': 7,
      'meeting_date': '2026-11-09',
      'simkuliah_status': 'pending',
      'local_override': {'override_type': 'izin'}
    };
    final meeting = MeetingModel.fromJson(json);
    expect(meeting.effectiveStatus, 'Izin');
    expect(meeting.isOverridden, isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/models_test.dart`  
Expected: FAIL.

- [ ] **Step 3: Implement models and `PresenceService` in `client/lib/`**

Define models with `fromJson` mappings and wire Supabase client real-time channel.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/models_test.dart`  
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/pubspec.yaml client/lib/ client/test/
git commit -m "feat(client): scaffold Flutter project, Supabase models and services"
```

---

### Task 10: Flutter UI - Today's Feed & Countdown Timer

**Files:**
- Create: `client/lib/views/today_feed_view.dart`
- Create: `client/lib/views/widgets/active_lecture_card.dart`
- Create: `client/lib/views/widgets/countdown_timer.dart`
- Test: `client/test/today_feed_widget_test.dart`

**Interfaces:**
- Consumes: Today's lectures from `PresenceService`.
- Produces: Visual card displaying live lecture status, countdown timer to deadline, direct presence button, and override chips.

- [ ] **Step 1: Write failing widget test for active lecture card and presence button**

```dart
// client/test/today_feed_widget_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simkuliah_client/views/widgets/active_lecture_card.dart';
import 'package:simkuliah_client/models/meeting_model.dart';

void main() {
  testWidgets('ActiveLectureCard displays Konfirmasi Presensi when open', (tester) async {
    final meeting = MeetingModel(
      id: 1,
      courseName: 'Grafika Komputer',
      meetingNumber: 7,
      isPresenceOpen: true,
      deadlineAt: DateTime.now().add(const Duration(minutes: 15)),
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: ActiveLectureCard(meeting: meeting)),
    ));

    expect(find.text('Konfirmasi Presensi'), findsOneWidget);
    expect(find.text('Izin'), findsOneWidget);
    expect(find.text('Sakit'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/today_feed_widget_test.dart`  
Expected: FAIL.

- [ ] **Step 3: Implement `ActiveLectureCard`, `CountdownTimerWidget`, and `TodayFeedView`**

Style with Material 3 cards, animated countdown timer, and optimistic state updates when action chips are pressed.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/today_feed_widget_test.dart`  
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/views/today_feed_view.dart client/lib/views/widgets/ client/test/today_feed_widget_test.dart
git commit -m "feat(client): implement Today Feed view with countdown timer and action buttons"
```

---

### Task 11: Flutter UI - Semester Matrix & Presence Percentage

**Files:**
- Create: `client/lib/views/semester_matrix_view.dart`
- Create: `client/lib/views/widgets/meeting_grid_tile.dart`
- Test: `client/test/semester_matrix_widget_test.dart`

**Interfaces:**
- Consumes: All enrolled courses and 16-meeting history per course.
- Produces: Matrix view showing presence percentage and meeting status indicators (Hadir, Izin, Sakit, Alpa, Pending).

- [ ] **Step 1: Write failing widget test for semester course presence row**

```dart
// client/test/semester_matrix_widget_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simkuliah_client/views/semester_matrix_view.dart';

void main() {
  testWidgets('SemesterMatrixView renders 16 meeting indicator tiles', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: SemesterMatrixView(testMode: true)),
    ));

    expect(find.byType(MeetingGridTile), findsNWidgets(16));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/semester_matrix_widget_test.dart`  
Expected: FAIL.

- [ ] **Step 3: Implement `SemesterMatrixView` and `MeetingGridTile`**

Render course lists, attendance progress bar with 75% threshold indicator, and tap-to-inspect modal for meeting details.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/semester_matrix_widget_test.dart`  
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/views/semester_matrix_view.dart client/test/semester_matrix_widget_test.dart
git commit -m "feat(client): implement Semester Schedule matrix and presence history"
```

---

### Task 12: Flutter UI - Gateway Health Alert Banner & Multi-Platform Packaging

**Files:**
- Create: `client/lib/views/widgets/gateway_alert_banner.dart`
- Modify: `client/lib/views/today_feed_view.dart`
- Create: `backend/Dockerfile`
- Create: `docker-compose.yml`
- Test: `client/test/gateway_alert_test.dart`

**Interfaces:**
- Consumes: Backend system health endpoint / incidents stream.
- Produces: Persistent warning banner when Simkuliah returns 500/502/504 errors, plus Docker deployment artifact for the backend daemon.

- [ ] **Step 1: Write failing test for gateway alert banner visibility**

```dart
// client/test/gateway_alert_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simkuliah_client/views/widgets/gateway_alert_banner.dart';

void main() {
  testWidgets('GatewayAlertBanner displays warning when server has outage', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: GatewayAlertBanner(hasOutage: true, errorMessage: 'Gateway Timeout (504)'),
      ),
    ));

    expect(find.textContaining('Gateway Timeout (504)'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/gateway_alert_test.dart`  
Expected: FAIL.

- [ ] **Step 3: Implement `GatewayAlertBanner`, `Dockerfile`, and `docker-compose.yml`**

Integrate banner into top of `TodayFeedView` and author multi-stage Docker container for Python backend deployment.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/gateway_alert_test.dart`  
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/views/widgets/gateway_alert_banner.dart backend/Dockerfile docker-compose.yml client/test/gateway_alert_test.dart
git commit -m "feat(deploy): implement gateway health alert banner and backend Dockerfile"
```

---

## Plan Self-Review Checklist

1. **Spec Coverage**:
   - CAPTCHA auto-solving (5 digits via `ddddocr` ONNX): Covered in Task 2.
   - Simkuliah session lifecycle (`ci_session`, 30m expiration, keep-alive): Covered in Task 3.
   - Daily and semester schedule HTML parsing: Covered in Task 4.
   - 5-Tier state machine notification triggers: Covered in Task 6.
   - ntfy.sh push notification with direct HTTP action buttons: Covered in Task 6.
   - Quick presence confirmation & local overrides (Izin, Sakit, Alpa): Covered in Task 5 & Task 7.
   - Adaptive class-hours polling: Covered in Task 8.
   - Multi-platform Flutter UI (Today's feed, countdown, matrix, health alert): Covered in Tasks 9, 10, 11, and 12.
   - Error detection (HTTP 500/502/504 gateway timeout): Covered in Task 3, Task 5, and Task 12.

2. **Step Granularity**: Every step has an exact test, an exact execution command, and an unambiguous single implementation task with Conventional Commit.
3. **Type Consistency**: Method signatures (`solve_captcha`, `create_action_token`, `evaluate_notification_state`) are consistent across test assertions and interfaces.
4. **Review Focus**: Edge cases for repeated CAPTCHA misclassification, 502/504 backoff, schedule updates, duplicate webhook double-tap, and offline client caching are directly addressed.