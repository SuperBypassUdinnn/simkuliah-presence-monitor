# System Design Specification: Simkuliah Multi-Platform Presence Monitor

**Date**: 2026-11-08  
**Author**: Antigravity  
**Status**: Draft for Review  
**Target Repository**: `SuperBypassUdinnn/simkuliah-presence-monitor`  

---

## 1. Executive Summary

The **Simkuliah Multi-Platform Presence Monitor** is an automated scheduling, presence monitoring, and instant-confirmation system designed for Universitas Syiah Kuala (USK) students. It bridges the operational gap of the university's academic portal (*Simkuliah*, running on CodeIgniter), which imposes strict, short attendance confirmation windows (typically 15 to 30 minutes) that only unlock after a lecturer records their own attendance.

The system operates across **Android, Linux, and Windows** using a centralized headless daemon running on a cloud PaaS. The daemon automatically maintains session authentication through optical character recognition (OCR) of Simkuliah's 5-digit CAPTCHA, executes adaptive schedule-aware polling, models a 5-tier notification lifecycle, and dispatches actionable push notifications via `ntfy.sh`. Students can confirm presence or mark local statuses (Izin, Sakit, Alpa) directly from OS notification banners in one second without opening a browser or the native application.

---

## 2. High-Level System Architecture

The architecture follows a decoupled **Client-Server & Push Relay** pattern composed of four primary subsystems:

```
+---------------------------------------------------------------------------------+
|                                 USK SIMKULIAH                                   |
|                          https://simkuliah.usk.ac.id                            |
+---------------------------------------+-----------------------------------------+
                                        ^
                                        | HTTPS (Cookie: ci_session)
                                        v
+---------------------------------------+-----------------------------------------+
|                         BACKEND MONITORING DAEMON                               |
|                  Runtime: Python 3.11+ / FastAPI / AsyncIO                      |
|                                                                                 |
|  +-----------------------+ +-----------------------+ +-----------------------+  |
|  |   Session & CAPTCHA   | |    Adaptive Poller    | |      HTML Parser      |  |
|  |  (ddddocr ONNX Engine)| |   (APScheduler Async) | | (Selectolax / bs4)    |  |
|  +-----------------------+ +-----------------------+ +-----------------------+  |
|  +-----------------------+ +-----------------------+ +-----------------------+  |
|  |     State Machine     | |   Webhook Receiver    | |    ntfy Dispatcher    |  |
|  | (5-Tier Notification) | | (Action Token Auth)   | |  (HTTP Action Buttons)|  |
|  +-----------------------+ +-----------------------+ +-----------------------+  |
+-----------------------+-----------------------------------+---------------------+
                        |                                   |
                        v                                   v
        +---------------+---------------+   +---------------+---------------+
        |    MANAGED DB (Supabase PG)   |   |     PUSH NOTIFICATION RELAY   |
        | - Course schedules & meetings |   |            (ntfy.sh)          |
        | - Presence & override records |   | - Private encrypted topic     |
        | - Downtime & error logs       |   | - Action webhooks payload     |
        +---------------+---------------+   +---------------+---------------+
                        |                                   |
                        +-----------------+-----------------+
                                          |
                                          v
+-----------------------------------------+---------------------------------------+
|                       MULTI-PLATFORM CLIENT (Flutter)                           |
|                    Targets: Android, Linux Desktop, Windows                     |
|                                                                                 |
|  - Real-Time Today Feed & Attendance Countdown Timer                            |
|  - Full Semester Course Matrix & Attendance Percentages                         |
|  - Simkuliah Downtime / Gateway Timeout Alert Banner                            |
|  - Manual Confirmation & Local Override Controls                                |
+---------------------------------------------------------------------------------+
```

## 3. Simkuliah Reverse Engineering & Session Management

### 3.1 Authentication & Session Lifecycle
* **Authentication Endpoint**: `POST https://simkuliah.usk.ac.id/index.php/login/auth`
* **Form Payload**:
  * `username`: Student NIP/NPM.
  * `password`: Student password.
  * `captcha_answer`: 5 numeric characters.
* **Session Cookie**: `ci_session` (CodeIgniter session cookie, default `Max-Age: 1800` seconds / 30 minutes, `HttpOnly`, `Path=/`).
* **CAPTCHA Endpoint**: `GET https://simkuliah.usk.ac.id/index.php/login/captcha_image?t=<unix_timestamp>`

### 3.2 Automated CAPTCHA Solving Pipeline
1. **Challenge Extraction**: During login or session re-authentication, the daemon issues a `GET` request to `/index.php/login/captcha_image?t=<timestamp>` preserving the current session cookie jar.
2. **Inference with `ddddocr`**: The raw image bytes (PNG/JPEG) are passed to a local `ddddocr.DdddOcr(show_ad=False)` instance. The model executes ONNX-based neural character classification and returns the recognized 5-digit string in ~10 ms on standard CPU without external network dependencies.
3. **Submission & Verification**: The daemon submits the credentials and recognized digits. If the response redirects to the dashboard (`/index.php/mahasiswa/dashboard` or HTTP 302), authentication succeeds.
4. **Retry & Backoff**: If Simkuliah returns a "Kode verifikasi salah" response, the daemon re-fetches a fresh CAPTCHA image and retries immediately (up to a maximum of 3 consecutive attempts). If all 3 fail, an alert notification is dispatched to the user.

### 3.3 Keep-Alive Heartbeat
To prevent unexpected session invalidation during active lecture hours, the daemon executes a lightweight `GET` request to `/index.php/mahasiswa/dashboard` every 12 minutes whenever a lecture is within its active observation window. This resets the 30-minute `ci_session` expiration timer.

### 3.4 Presence Confirmation Protocol
* **Presence Action Endpoint**: `POST https://simkuliah.usk.ac.id/index.php/mahasiswa/presensi/simpan_presensi` (or corresponding form action on the attendance screen).
* **Payload Structure**:
  * `id_jadwal`: Identifier of the lecture schedule.
  * `pertemuan`: Target meeting number (e.g., 1 to 16).
  * `status`: Presence confirmation flag.
* The daemon replicates this exact form submission using the authenticated cookie jar when the user triggers the confirmation action.

---

## 4. Adaptive Polling & Notification State Machine

### 4.1 Schedule-Aware Adaptive Polling
To avoid unnecessary network traffic and prevent triggering rate-limiting or firewall defenses at USK Network Operations Center (TIK USK), the daemon uses dynamic polling frequency:
* **Idle / Off-Hours Mode**: When no classes are scheduled for the current day, or when current time is outside any class observation window, the poller sleeps. A single synchronization run occurs at 05:00 local time daily to pull updated schedules.
* **Pre-Class Observation Mode**: Polling activates 10 minutes prior to a scheduled class start time (`T_start - 10m`) at an interval of **120 seconds**.
* **Active Lecture Window**: From `T_start` until attendance is confirmed or class ends, polling runs every **60 seconds** to detect the exact moment the lecturer opens attendance.
* **Post-Completion Mode**: Once presence is successfully confirmed (or local override is applied, or the class ends), polling for that course terminates immediately and transitions back to idle.

### 4.2 The 5-Tier Notification State Machine

Each lecture instance is evaluated against a deterministic finite state machine (FSM):

```
+-----------------------------------------------------------------------------+
|                            [IDLE / SCHEDULED]                               |
+--------------------------------------+--------------------------------------+
                                       |
                   Current Time >= T_start & Dosen NOT Open
                                       v
+-----------------------------------------------------------------------------+
|                      STATE 1: CLASS_STARTED                                 |
| - Notification: "Class [Course] has started. Remind lecturer to open."      |
| - Actions: [Remind Lecturer] [Izin] [Sakit]                                 |
+--------------------------------------+--------------------------------------+
                                       |
                      Lecturer records attendance (Open)
                                       v
+-----------------------------------------------------------------------------+
|                      STATE 2: LECTURER_OPENED                               |
| - Notification: "Attendance OPEN for [Course]! Deadline: HH:MM"             |
| - Actions: [Confirm Presence (Instant)] [Izin] [Sakit]                      |
+--------------------------------------+--------------------------------------+
                                       |
                   T >= Dosen_Open + 5m & Student NOT Present
                                       v
+-----------------------------------------------------------------------------+
|                      STATE 3: PENDING_REMINDER                              |
| - Notification: "URGENT: You haven't confirmed presence for [Course]!"      |
| - Actions: [Confirm Presence (Instant)] [Izin] [Sakit]                      |
+--------------------------------------+--------------------------------------+
                                       |
                Time >= T_end - 15m & Lecturer STILL NOT Open
                                       v
+-----------------------------------------------------------------------------+
|                      STATE 4: URGENT_CLOSING                                |
| - Notification: "CRITICAL: [Course] ends soon and attendance is still closed"|
| - Actions: [Remind Lecturer] [Izin] [Sakit]                                 |
+--------------------------------------+--------------------------------------+
                                       |
     Time > Deadline OR (Time >= T_end & Attendance Never Opened)
                                       v
+-----------------------------------------------------------------------------+
|                      STATE 5: WINDOW_EXPIRED                                |
| - Notification: "Attendance window passed for [Course]. Report to lecturer."|
| - Actions: [Reported] [Mark Alpa]                                           |
+-----------------------------------------------------------------------------+
```

### 4.3 Local Overrides (Izin, Sakit, Alpa)
Simkuliah only provides a binary presence model for students and represents excused absence (Izin) and medical leave (Sakit) as generic attendance handled manually by lecturers. To prevent false reminders:
1. When the user taps **[Izin]**, **[Sakit]**, or **[Alpa]**, the action is dispatched to the backend.
2. The state machine for that lecture immediately transitions to `TERMINATED_BY_OVERRIDE`.
3. All pending reminders and timers for that lecture are cancelled instantly.
4. The override is saved in Supabase PostgreSQL to maintain a personal audit record.

## 5. Notification Delivery & Direct Webhook Actions

### 5.1 ntfy.sh Push Relay Protocol
Notifications are dispatched via `ntfy.sh` (or a self-hosted ntfy instance) to a cryptographically unguessable topic ID (e.g., `simkuliah-usr-<uuid_v4>`).

#### Payload Structure for State 2 (Lecturer Opened):
```json
{
  "topic": "simkuliah-usr-9c8a412b-3e5f-4a88-9d21-f09c2b4a1122",
  "title": "Presensi Dibuka: Grafika Komputer",
  "message": "Dosen telah membuka presensi pertemuan ke-7. Batas waktu konfirmasi hingga 10:15 WIB.",
  "priority": 4,
  "tags": ["hourglass_flowing_sand", "computer"],
  "actions": [
    {
      "action": "http",
      "label": "Presensi Sekarang",
      "url": "https://<daemon-domain>/api/v1/webhook/action",
      "method": "POST",
      "headers": {
        "Content-Type": "application/json",
        "X-Action-Token": "<ephemeral_action_token>"
      },
      "body": "{\"action\": \"confirm_presence\", \"meeting_id\": 7, \"course_id\": 1042}"
    },
    {
      "action": "http",
      "label": "Izin",
      "url": "https://<daemon-domain>/api/v1/webhook/action",
      "method": "POST",
      "headers": {
        "Content-Type": "application/json",
        "X-Action-Token": "<ephemeral_action_token>"
      },
      "body": "{\"action\": \"mark_override\", \"override_type\": \"izin\", \"course_id\": 1042}"
    },
    {
      "action": "http",
      "label": "Sakit",
      "url": "https://<daemon-domain>/api/v1/webhook/action",
      "method": "POST",
      "headers": {
        "Content-Type": "application/json",
        "X-Action-Token": "<ephemeral_action_token>"
      },
      "body": "{\"action\": \"mark_override\", \"override_type\": \"sakit\", \"course_id\": 1042}"
    }
  ]
}
```

### 5.2 Webhook Security & Execution Flow
1. **Token Generation**: Each notification action payload includes a short-lived cryptographically signed token (`X-Action-Token` generated using HMAC-SHA256 with an internal daemon secret).
2. **Instant Execution**: When the user taps the action button on their Android notification or Linux/Windows notification popup, the OS HTTP client immediately sends the POST request to the daemon.
3. **Receipt & Follow-up**: Upon successful execution in Simkuliah, the daemon immediately publishes a low-priority confirmation notification: *"Presensi Berhasil: Kehadiran Anda pada Grafika Komputer telah tercatat."*

---

## 6. Database Schema & Persistence (Supabase PostgreSQL)

Because the cloud backend runs in an ephemeral container environment (e.g., Koyeb, Fly.io), all persistent state is maintained in Supabase PostgreSQL:

```sql
-- 1. Courses and Schedules
CREATE TABLE schedules (
    id SERIAL PRIMARY KEY,
    course_code VARCHAR(32) NOT NULL,
    course_name VARCHAR(128) NOT NULL,
    class_group VARCHAR(16) NOT NULL,
    lecturer_name VARCHAR(128),
    day_of_week INT NOT NULL, -- 1 = Monday, 7 = Sunday
    start_time TIME NOT NULL,
    end_time TIME NOT NULL,
    room VARCHAR(64),
    semester_id VARCHAR(16) NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(course_code, class_group, semester_id)
);

-- 2. Meetings and Presence Tracking
CREATE TABLE meetings (
    id SERIAL PRIMARY KEY,
    schedule_id INT REFERENCES schedules(id) ON DELETE CASCADE,
    meeting_number INT NOT NULL,
    meeting_date DATE NOT NULL,
    topic TEXT,
    lecturer_opened_at TIMESTAMPTZ,
    deadline_at TIMESTAMPTZ,
    simkuliah_status VARCHAR(32) DEFAULT 'pending', -- pending, hadir, tidak_hadir
    student_confirmed_at TIMESTAMPTZ,
    last_polled_at TIMESTAMPTZ,
    UNIQUE(schedule_id, meeting_number)
);

-- 3. Custom Local Overrides (Izin, Sakit, Alpa)
CREATE TABLE local_overrides (
    id SERIAL PRIMARY KEY,
    meeting_id INT REFERENCES meetings(id) ON DELETE CASCADE,
    override_type VARCHAR(16) NOT NULL, -- izin, sakit, alpa
    note TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(meeting_id)
);

-- 4. Notification Dispatch Log
CREATE TABLE notification_logs (
    id SERIAL PRIMARY KEY,
    meeting_id INT REFERENCES meetings(id) ON DELETE CASCADE,
    state_level INT NOT NULL, -- 1 to 5
    dispatched_at TIMESTAMPTZ DEFAULT NOW(),
    acknowledged_at TIMESTAMPTZ,
    response_action VARCHAR(32)
);

-- 5. System Health & Downtime Incidents
CREATE TABLE system_incidents (
    id SERIAL PRIMARY KEY,
    incident_type VARCHAR(64) NOT NULL, -- gateway_timeout, 500_error, captcha_exhaustion
    http_status INT,
    error_snippet TEXT,
    started_at TIMESTAMPTZ DEFAULT NOW(),
    resolved_at TIMESTAMPTZ
);
```

## 7. Multi-Platform Client Design (Flutter)

### 7.1 Cross-Platform Architecture
The client application is built with **Flutter 3.x**, targeting:
* **Android**: Material 3 UI with native background notification handling and quick-tile/widget support.
* **Linux (KDE / Wayland & X11)**: Native desktop window with system tray integration and DBus notification action handling.
* **Windows (10/11)**: Native desktop window with system tray and Windows Toast notification integration.

### 7.2 Core User Interfaces
1. **Today's Feed (Home Screen)**:
   * **Active Lecture Hero Card**: Highlights current or upcoming lecture. Displays a live countdown timer to the attendance deadline when the lecturer has opened presence.
   * **Direct Action Floating Trigger**: If presence is currently open and unconfirmed, an elevated button `[Konfirmasi Kehadiran]` is displayed prominently.
   * **Local Override Chips**: Buttons for `[Izin]`, `[Sakit]`, and `[Alpa]` with instant UI feedback.
2. **Semester Schedule & Presence Matrix**:
   * Complete overview of all enrolled courses.
   * Meeting-by-meeting presence history (Meetings 1 through 16).
   * Aggregate attendance percentage calculated against the 75% minimum university threshold.
   * Differentiates true `Hadir` from local `Izin`, `Sakit`, and `Alpa` notes.
3. **Simkuliah Health & Gateway Banner**:
   * If Simkuliah returns HTTP 500/502/504 errors or is unreachable, an amber or red status strip appears at the top:
     *"Peringatan: Server Simkuliah sedang mengalami Gateway Timeout / Gangguan. Sistem akan mencoba kembali secara otomatis."*

---

## 8. Resilience, Rate Limiting & Error Handling

### 8.1 Simkuliah Gateway Timeout & Server Outages
* **Detection**: HTTP status codes 500, 502, 503, 504, or network timeout (> 15 seconds).
* **Mitigation Strategy**: The poller enters exponential backoff (retry after 30s, 60s, 120s, up to a cap of 300s).
* **User Notification**: If the outage persists for more than 5 minutes during an active lecture window, a warning notification is sent to the student so they are aware that Simkuliah is experiencing downtime.

### 8.2 CAPTCHA Solver Failure Fallback
* If `ddddocr` fails to solve the CAPTCHA 3 consecutive times during a login cycle:
  1. An alert is sent to ntfy: *"Gagal melakukan login otomatis ke Simkuliah (CAPTCHA gagal). Ketuk untuk verifikasi."*
  2. The notification payload includes a deep-link to the Flutter client, opening an embedded web view or manual CAPTCHA input dialog.

### 8.3 Anti-Ban Network Hygiene
* Daemon requests mimic standard desktop Chrome headers (`User-Agent`, `Accept-Language`, `Sec-Ch-Ua`).
* Requests maintain HTTP/1.1 persistent connections with cookie reuse to prevent connection thrashing on the university NGINX reverse proxy.

---

## 9. Deployment & Configuration Specification

### 9.1 Environment Variables
```env
# Simkuliah Credentials
SIMKULIAH_NPM=2408107010053
SIMKULIAH_PASSWORD=REDACTED_SECURE_STORE

# Push Notification Settings
NTFY_BASE_URL=https://ntfy.sh
NTFY_TOPIC=simkuliah-usr-REDACTED_UUID
ACTION_SECRET_KEY=REDACTED_HMAC_SECRET

# Managed Database (Supabase)
SUPABASE_URL=https://<project-ref>.supabase.co
SUPABASE_SERVICE_ROLE_KEY=REDACTED_SERVICE_KEY

# Polling Config
POLL_ACTIVE_INTERVAL_SECONDS=60
POLL_PRE_CLASS_INTERVAL_SECONDS=120
POLL_IDLE_INTERVAL_SECONDS=7200
```

### 9.2 Containerization (Dockerfile)
```dockerfile
FROM python:3.11-slim
WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    libgl1 libglib2.0-0 curl \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .
EXPOSE 8000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

---

## 10. Verification Matrix

| Test ID | Scenario | Expected Behavior |
| :--- | :--- | :--- |
| **V-01** | CAPTCHA Solving | `ddddocr` achieves $\ge 90\%$ accuracy on test batch of 20 Simkuliah CAPTCHA samples; automatic retry handles misclassifications. |
| **V-02** | Session Keep-Alive | Session remains active without re-login during a continuous 2-hour lecture block. |
| **V-03** | 5-Tier FSM Transition | Transitions trigger at exact thresholds (`T_start`, lecturer open, +5m, `T_end - 15m`, window expiration). |
| **V-04** | Direct Action Webhook | Tapping "Presensi Sekarang" on notification executes presence on Simkuliah within 2.0 seconds and logs success. |
| **V-05** | Local Override Muting | Tapping "Izin" or "Sakit" updates Supabase and cancels all remaining reminder timers for that lecture. |
| **V-06** | Gateway Timeout Recovery | Simulated HTTP 504 returns display alert banner in Flutter app and poller backs off cleanly without crash. |