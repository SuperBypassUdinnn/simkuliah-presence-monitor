# Automation Settings Tab, Persistence Fix, and Linux Runner Repair Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver version 1.1.1+7 featuring a dedicated "Pengaturan & Automasi" tab, direct 1-click auto-absen toggles on lecture cards, robust Supabase customization persistence via partial unique indexes, and fixing the blank screen bug when waking the Linux desktop runner from the background.

**Architecture:** Database uniqueness is enforced deterministically via two partial indexes (`WHERE meeting_id IS NULL` vs `WHERE meeting_id IS NOT NULL`) so course-level and meeting-level overrides never create duplicate rows on upsert. The client's `MainHomeScreen` introduces a 4th tab (`SettingsAutomationView`) cleanly separating global class reminders, full-course timing offsets, and course-wide auto-presence from daily lecture cards, while `ActiveLectureCard` provides a rapid 1-click switch for single-meeting auto-presence. The native Linux GTK runner uses `gtk_widget_show_all` to recursively map child `FlView` surfaces upon single-instance reactivation.

**Tech Stack:** Flutter 3.x (Dart 3), GTK 3 (C++ Runner), Supabase (PostgreSQL), Python 3.11 / FastAPI.

**Spec:** `docs/superpowers/specs/2026-11-17-automation-settings-tab-and-linux-runner-fix-design.md`

## Global Constraints

- Python code must conform to `ruff check .` and `ruff format .` without warnings or suppressions.
- Flutter/Dart code must conform to `flutter analyze --no-pub` and `dart format --set-exit-if-changed .` without issues.
- Client version in `client/pubspec.yaml` must increment to `1.1.1+7`.
- Clean text policy: No decorative icons or emojis in Git commit messages or technical artifacts.
- Plain-text conventional commit messages (`<type>(<scope>): <subject>`).

## Review Focus

1. **Course-wide customization with NULL meeting_id**: Supabase upsert must update the existing course row rather than creating duplicates or throwing unique key violation.
2. **Linux desktop wake from `--hidden` autostart**: Reactivating an existing background instance must paint the Flutter UI immediately without rendering a blank black canvas.
3. **Card 1-click auto-absen toggle failure handling**: If the network is unreachable when toggling auto-absen on a lecture card, the switch must revert gracefully and show an error notification.
4. **Customization data sync into daily feeds**: `fetchTodaysMeetings` and `fetchSemesterMatrix` must reliably join active customizations so badges and adjusted times render without requiring manual reloads.
5. **Global reminder lead time fallback**: If `user_preferences` has no row yet, `SettingsAutomationView` and poller must fall back to 15 minutes seamlessly.

---

### Task 1: Supabase Migration for Partial Unique Indexes & Database Upsert Methods

**Files:**
- Create: `supabase/migrations/20261117000000_fix_customization_null_index.sql`
- Modify: `backend/app/core/database.py`
- Test: `backend/tests/test_database_customizations.py`

**Interfaces:**
- Consumes: `schedule_customizations` table schema
- Produces:
  - Partial unique indexes in PostgreSQL
  - `DatabaseRepository.upsert_schedule_customization` with deterministic course vs meeting conflict handling

- [ ] **Step 1: Write failing test in `backend/tests/test_database_customizations.py` for course-wide upsert updating instead of duplicating**

```python
@pytest.mark.asyncio
async def test_upsert_course_wide_customization_replaces_existing():
    repo = DatabaseRepository(supabase_url="http://mock", supabase_key="key")
    repo.client = MagicMock()
    
    # Mock upsert operation returning updated data
    mock_upsert = MagicMock()
    mock_upsert.execute.return_value = MagicMock(data=[{
        "id": 1,
        "schedule_id": 10,
        "meeting_id": None,
        "time_offset_minutes": 30,
        "auto_presence_enabled": True
    }])
    repo.client.table.return_value.upsert.return_value = mock_upsert
    
    result = await repo.upsert_schedule_customization({
        "schedule_id": 10,
        "meeting_id": None,
        "time_offset_minutes": 30,
        "auto_presence_enabled": True
    })
    assert result["time_offset_minutes"] == 30
    assert result["meeting_id"] is None
```

- [ ] **Step 2: Run test to verify behavior**

Run: `backend/.venv/bin/python -m pytest backend/tests/test_database_customizations.py -v`
Expected: PASS/FAIL depending on mock constraints

- [ ] **Step 3: Create migration `supabase/migrations/20261117000000_fix_customization_null_index.sql`**

Write SQL migration dropping `schedule_customizations_schedule_id_meeting_id_key` and creating the two partial unique indexes `idx_schedule_customizations_course_unique` and `idx_schedule_customizations_meeting_unique`.

- [ ] **Step 4: Update `backend/app/core/database.py`**

In `upsert_schedule_customization`, if `meeting_id` is None, specify conflict target matching the course partial index or check existing ID before updating.

- [ ] **Step 5: Run tests to verify they pass**

Run: `backend/.venv/bin/python -m pytest backend/tests/test_database_customizations.py -v`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add supabase/migrations/20261117000000_fix_customization_null_index.sql backend/app/core/database.py backend/tests/test_database_customizations.py
git commit -m "feat(backend): add partial unique indexes and deterministic upsert for customizations"
```

---

### Task 2: Linux Runner Repair for Single-Instance Background Window Mapping

**Files:**
- Modify: `client/linux/runner/my_application.cc`

**Interfaces:**
- Consumes: GTK 3 and Flutter Linux C++ embedder APIs
- Produces: Correct window realization and recursive mapping of `FlView` upon reactivation

- [ ] **Step 1: Inspect `client/linux/runner/my_application.cc` around `my_application_activate`**

Review line 51 to 65 of `my_application.cc`.

- [ ] **Step 2: Update `my_application_activate` in `client/linux/runner/my_application.cc`**

Replace:
```cpp
  if (self->first_window != nullptr) {
    gtk_widget_show(GTK_WIDGET(self->first_window));
    gtk_window_present(self->first_window);
    return;
  }
```
with:
```cpp
  if (self->first_window != nullptr) {
    gtk_widget_show_all(GTK_WIDGET(self->first_window));
    gtk_window_present(self->first_window);
    return;
  }
```
Also ensure child widgets and Flutter view receive focus upon activation.

- [ ] **Step 3: Build Linux bundle to verify compilation**

Run: `cd client && flutter build linux --dart-define-from-file=.env`
Expected: `✓ Built build/linux/x64/release/bundle/simkuliah_client`

- [ ] **Step 4: Commit**

```bash
git add client/linux/runner/my_application.cc
git commit -m "fix(linux): recursively map child widgets on single instance activation"
```

---

### Task 3: Client Data Syncing in PresenceService

**Files:**
- Modify: `client/lib/services/presence_service.dart`
- Modify: `client/lib/models/meeting_model.dart`
- Test: `client/test/presence_service_test.dart`

**Interfaces:**
- Consumes: Supabase `schedule_customizations` and `user_preferences` tables
- Produces:
  - `MeetingModel.customization` field
  - `PresenceService.saveMeetingAutoPresence({required int scheduleId, required int meetingId, required bool enabled})`
  - `PresenceService.fetchTodaysMeetings` populated with effective customizations

- [ ] **Step 1: Write failing test in `client/test/presence_service_test.dart` for customization resolution**

```dart
test('fetchTodaysMeetings attaches active customization to meeting model', () async {
  // Test that MeetingModel receives its resolved customization
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/presence_service_test.dart`
Expected: FAIL

- [ ] **Step 3: Update `MeetingModel` in `client/lib/models/meeting_model.dart`**

Add `final ScheduleCustomizationModel? customization;` property and `copyWith` support so meetings carry their customization.

- [ ] **Step 4: Update `PresenceService` in `client/lib/services/presence_service.dart`**

In `fetchTodaysMeetings`, after fetching meeting rows:
1. Extract unique `schedule_id`s.
2. Query `schedule_customizations` using `inFilter('schedule_id', scheduleIds)`.
3. Resolve meeting-level or course-level customization for each meeting and attach to the model.
Add helper `saveMeetingAutoPresence(...)`.

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd client && flutter test test/presence_service_test.dart`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add client/lib/models/meeting_model.dart client/lib/services/presence_service.dart client/test/presence_service_test.dart
git commit -m "feat(client): attach customizations to meetings and add quick auto-presence api"
```

---

### Task 4: Interactive Quick Toggle for Auto-Absen on Lecture Cards

**Files:**
- Modify: `client/lib/views/widgets/active_lecture_card.dart`
- Modify: `client/lib/views/today_feed_view.dart`
- Modify: `client/lib/views/active_presence_view.dart`
- Test: `client/test/active_lecture_card_customization_test.dart`

**Interfaces:**
- Consumes: `PresenceService.saveMeetingAutoPresence`, `MeetingModel.customization`
- Produces:
  - Inline 1-click Switch/FilterChip for "Auto-Absen" on `ActiveLectureCard`
  - Instant optimistic state update with rollback on network failure

- [ ] **Step 1: Write failing test in `client/test/active_lecture_card_customization_test.dart`**

```dart
testWidgets('renders 1-click auto-absen quick switch and toggles state', (tester) async {
  // Verify switch presence and tap callback
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/active_lecture_card_customization_test.dart`
Expected: FAIL

- [ ] **Step 3: Update `ActiveLectureCard` in `client/lib/views/widgets/active_lecture_card.dart`**

- Remove the tune icon popup dialog from the header.
- In the actions row, add an interactive Switch/FilterChip:
  - Label: "Auto-Absen Pertemuan Ini"
  - Value: `widget.customization?.autoPresenceEnabled ?? false`
  - OnChanged: invokes `_service.saveMeetingAutoPresence(...)` with optimistic UI update and error toast on failure.

- [ ] **Step 4: Update `TodayFeedView` and `ActivePresenceView`**

Pass `customization: meeting.customization` into `ActiveLectureCard`.

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd client && flutter test test/active_lecture_card_customization_test.dart`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add client/lib/views/widgets/active_lecture_card.dart client/lib/views/today_feed_view.dart client/lib/views/active_presence_view.dart client/test/active_lecture_card_customization_test.dart
git commit -m "feat(client): add 1-click auto-absen toggle on active lecture cards"
```

---

### Task 5: Dedicated "Pengaturan & Automasi" Tab (`SettingsAutomationView`)

**Files:**
- Create: `client/lib/views/settings_automation_view.dart`
- Modify: `client/lib/main.dart`
- Test: `client/test/settings_automation_view_test.dart`

**Interfaces:**
- Consumes: `PresenceService.fetchSemesterMatrix`, `PresenceService.fetchCustomizations`, `PresenceService.fetchUserPreferences`, `PresenceService.saveCustomization`, `PresenceService.saveUserPreferences`
- Produces:
  - 4th tab in navigation (`SettingsAutomationView`)
  - Full-course configuration UI (global reminder, per-course auto-presence, relative/absolute timings)

- [ ] **Step 1: Write failing test in `client/test/settings_automation_view_test.dart`**

```dart
testWidgets('SettingsAutomationView renders global reminder and course list', (tester) async {
  // Verify global reminder templates and course cards render
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/settings_automation_view_test.dart`
Expected: FAIL (file does not exist)

- [ ] **Step 3: Implement `SettingsAutomationView` in `client/lib/views/settings_automation_view.dart`**

- Section 1: Global class entry reminder card with `10m`, `15m`, `30m`, and custom input chips. Persists to `user_preferences`.
- Section 2: Course schedule list:
  - Course header (Code, Name, Class Group, Official Portal Time).
  - Switch: "Auto-Absen (Semua Pertemuan)".
  - Timing adjustment: Segmented button (*Asli*, *Relatif (+/-)*, *Pindah Hari/Jam*).
  - Specific reminder override dropdown/chip.
  - Reset button to delete customization.

- [ ] **Step 4: Register 4th Tab in `client/lib/main.dart`**

- Add `SettingsAutomationView()` to `_views` list in `_MainHomeScreenState`.
- Add 4th navigation item with icon `Icons.tune_outlined` / `Icons.tune` and label `'Pengaturan'`.

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd client && flutter test test/settings_automation_view_test.dart`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add client/lib/views/settings_automation_view.dart client/lib/main.dart client/test/settings_automation_view_test.dart
git commit -m "feat(client): add dedicated automation and schedule settings tab"
```

---

### Task 6: Version Bump (1.1.1+7), Feature Log, & Pipeline Verification

**Files:**
- Modify: `client/pubspec.yaml` (bump to `1.1.1+7`)
- Create: `docs/backlog/features/F-034-automation-settings-tab-and-linux-runner-fix.md`
- Test: Full pipeline verification scripts

**Interfaces:**
- Consumes: All completed modules from Tasks 1-5
- Produces: Clean pre-release gate passing all checks

- [ ] **Step 1: Bump version in `client/pubspec.yaml`**

Change `version: 1.1.0+6` to `version: 1.1.1+7`.

- [ ] **Step 2: Create feature execution log `docs/backlog/features/F-034-automation-settings-tab-and-linux-runner-fix.md`**

Author complete log detailing problems solved, implementation steps, and verification matrices.

- [ ] **Step 3: Run full automated verification pipeline**

Run: `python3 scripts/verify_pipeline.py`
Expected:
```
[PASS] ruff check
[PASS] ruff format
[PASS] pytest (backend)
[PASS] flutter analyze (client)
[PASS] dart format (client)
All verification checks PASSED successfully.
```

- [ ] **Step 4: Run backlog status parity gate**

Run: `python3 scripts/sync_backlog_status.py --check`
Expected: `[PASS] Planning and backlog status parity verified.`

- [ ] **Step 5: Commit**

```bash
git add client/pubspec.yaml docs/backlog/features/F-034-automation-settings-tab-and-linux-runner-fix.md
git commit -m "chore(release): bump client version to 1.1.1+7 and record F-034 log"
```
