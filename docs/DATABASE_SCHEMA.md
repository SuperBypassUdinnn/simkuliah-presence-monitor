# simkuliah-presence-monitor Database Schema Specification

Single source of truth for database schema design, migrations, Row Level Security (RLS), and Realtime publications.

- **Database Engine**: `PostgreSQL 15+` (Hosted on Supabase Cloud)
- **Supabase Project Ref**: `ftznonanlbshweysliar`
- **Migration Manager**: Supabase CLI (`supabase/migrations/`)

---

## 1. Migration Discipline

1. Never edit a committed `.sql` migration file; always author a new forward migration via `supabase migration new <name>`.
2. Push migrations to the linked Supabase cloud database using `supabase db push --remote`.
3. Keep column naming conventions strictly snake_case (`created_at`, `updated_at`).
4. Every new table must explicitly enable Row Level Security (`ALTER TABLE <name> ENABLE ROW LEVEL SECURITY;`).

---

## 2. Core Entities & Tables

### `schedules`
Stores the student's enrolled courses and regular weekly lecture timetables.

| Column | Type | Constraints | Description |
| :--- | :--- | :--- | :--- |
| `id` | SERIAL | PRIMARY KEY | Unique schedule identifier |
| `course_code` | VARCHAR(32) | NOT NULL | Course code (e.g. `INF101`) |
| `course_name` | VARCHAR(128) | NOT NULL | Human-readable course title |
| `class_group` | VARCHAR(16) | NOT NULL | Class / section group (e.g. `01`) |
| `lecturer_name` | VARCHAR(128) | NULLABLE | Primary lecturer name |
| `day_of_week` | INT | NOT NULL | 1 = Monday .. 7 = Sunday |
| `start_time` | TIME | NOT NULL | Lecture start time |
| `end_time` | TIME | NOT NULL | Lecture end time |
| `room` | VARCHAR(64) | NULLABLE | Classroom / lab identifier |
| `semester_id` | VARCHAR(16) | NOT NULL | Academic semester code (e.g. `20261`) |
| `created_at` | TIMESTAMPTZ | DEFAULT NOW() | Record creation timestamp |
| `updated_at` | TIMESTAMPTZ | DEFAULT NOW() | Record last update timestamp |

*Unique constraint*: `UNIQUE(course_code, class_group, semester_id)`

---

### `meetings`
Tracks each lecture meeting, lecturer activation, attendance deadlines, and student presence status.

| Column | Type | Constraints | Description |
| :--- | :--- | :--- | :--- |
| `id` | SERIAL | PRIMARY KEY | Unique meeting identifier |
| `schedule_id` | INT | FK -> `schedules(id)` ON DELETE CASCADE | Associated schedule |
| `meeting_number` | INT | NOT NULL | Meeting sequence (1..16) |
| `meeting_date` | DATE | NOT NULL | Scheduled meeting date |
| `topic` | TEXT | NULLABLE | Lecture topic / description |
| `lecturer_opened_at` | TIMESTAMPTZ | NULLABLE | When lecturer activated attendance |
| `deadline_at` | TIMESTAMPTZ | NULLABLE | Attendance closing deadline |
| `simkuliah_status` | VARCHAR(32) | DEFAULT `'pending'` | `pending`, `hadir`, `tidak_hadir` |
| `student_confirmed_at` | TIMESTAMPTZ | NULLABLE | When presence was recorded |
| `last_polled_at` | TIMESTAMPTZ | NULLABLE | Last polling check timestamp |

*Unique constraint*: `UNIQUE(schedule_id, meeting_number)`

---

### `local_overrides`
Allows the student to record local attendance reasons (Izin, Sakit, Alpa) for accurate semester matrix calculation.

| Column | Type | Constraints | Description |
| :--- | :--- | :--- | :--- |
| `id` | SERIAL | PRIMARY KEY | Unique override identifier |
| `meeting_id` | INT | FK -> `meetings(id)` ON DELETE CASCADE | Associated meeting |
| `override_type` | VARCHAR(16) | NOT NULL | `izin`, `sakit`, `alpa` |
| `note` | TEXT | NULLABLE | Optional reason / doctor's note |
| `created_at` | TIMESTAMPTZ | DEFAULT NOW() | Creation timestamp |

*Unique constraint*: `UNIQUE(meeting_id)`

---

### `notification_logs`
Audit log of push notification state alerts dispatched via ntfy.sh.

| Column | Type | Constraints | Description |
| :--- | :--- | :--- | :--- |
| `id` | SERIAL | PRIMARY KEY | Unique log identifier |
| `meeting_id` | INT | FK -> `meetings(id)` ON DELETE CASCADE | Associated meeting |
| `state_level` | INT | NOT NULL | Notification level (1..5) |
| `dispatched_at` | TIMESTAMPTZ | DEFAULT NOW() | Dispatch timestamp |
| `acknowledged_at` | TIMESTAMPTZ | NULLABLE | When student tapped or dismissed |
| `response_action` | VARCHAR(32) | NULLABLE | Response action recorded |

---

### `system_incidents`
Monitors Simkuliah gateway downtime, 500 errors, or CAPTCHA exhaustion events.

| Column | Type | Constraints | Description |
| :--- | :--- | :--- | :--- |
| `id` | SERIAL | PRIMARY KEY | Unique incident identifier |
| `incident_type` | VARCHAR(64) | NOT NULL | `gateway_timeout`, `500_error`, `captcha_exhaustion` |
| `http_status` | INT | NULLABLE | HTTP status code observed |
| `error_snippet` | TEXT | NULLABLE | Truncated error snippet |
| `started_at` | TIMESTAMPTZ | DEFAULT NOW() | Incident start time |
| `resolved_at` | TIMESTAMPTZ | NULLABLE | Incident resolution time |

---

## 3. Row Level Security (RLS) & Access Policies

All tables enforce Row Level Security (`ALTER TABLE ... ENABLE ROW LEVEL SECURITY`).

| Table | Policy | Role / Command | Condition |
| :--- | :--- | :--- | :--- |
| `schedules` | Allow service_role full access | `service_role` (ALL) | `USING (true)` |
| `schedules` | Allow anon read access | `anon` (SELECT) | `USING (true)` |
| `meetings` | Allow service_role full access | `service_role` (ALL) | `USING (true)` |
| `meetings` | Allow anon read access | `anon` (SELECT) | `USING (true)` |
| `local_overrides` | Allow service_role full access | `service_role` (ALL) | `USING (true)` |
| `local_overrides` | Allow anon read access | `anon` (SELECT) | `USING (true)` |
| `local_overrides` | Allow anon insert/update | `anon` (INSERT, UPDATE) | `WITH CHECK (true)` |
| `notification_logs` | Allow service_role full access | `service_role` (ALL) | `USING (true)` |
| `system_incidents` | Allow service_role full access | `service_role` (ALL) | `USING (true)` |
| `system_incidents` | Allow anon read access | `anon` (SELECT) | `USING (true)` |

---

## 4. Realtime Streaming Publication

The following tables are published to `supabase_realtime` with `REPLICA IDENTITY FULL` so the Flutter client receives live database change notifications:
- `schedules`
- `meetings`
- `local_overrides`

---

## 5. API Keys Migration (Early 2027 Deprecation)

Supabase legacy JWT API keys (`anon`, `service_role`) are scheduled for retirement in early 2027. This repository natively supports the new API keys:

- **Flutter Client**: Uses **Publishable Key** (`sb_publishable_...`) via `--dart-define=SUPABASE_PUBLISHABLE_KEY=...` (with fallback to legacy `SUPABASE_ANON_KEY`).
- **Backend Daemon**: Uses **Secret Key** (`sb_secret_...`) via `SUPABASE_SECRET_KEY` (with fallback to legacy `SUPABASE_SERVICE_ROLE_KEY`).
