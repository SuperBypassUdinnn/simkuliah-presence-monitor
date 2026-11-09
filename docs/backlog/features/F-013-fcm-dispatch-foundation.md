# Feature Log: F-013 Firebase FCM Dispatch Foundation

- **Parent Plan**: [`.planning/04-hybrid-push-notifications.md`](../../../.planning/04-hybrid-push-notifications.md)
- **Target Issue**: #18
- **Status**: In Progress
- **Author**: AI Agent / Developer

## 1. Problem Statement & Scope
Push delivery depends entirely on ntfy, which requires an external Android app.
Lay the backend foundation for Firebase Cloud Messaging so the Android client
(Phase 2) can receive native push without any external app.

## 2. Implementation Checklist
- [x] Add `device_tokens` table (migration `20261109110000`, service-role-only RLS).
- [x] Device token repository methods (idempotent upsert, delete, sync list/prune).
- [x] `FcmDispatcher` with the shared priority policy (high only for
      `lecturer_opened` and `urgent_closing`).
- [x] `MultiDispatcher` dual dispatch: one failing transport never blocks the other.
- [x] `POST /api/v1/devices/register` and `/unregister` endpoints.
- [x] `FIREBASE_CREDENTIALS_PATH` and `FCM_DATA_ONLY` settings; graceful no-op
      when credentials are absent.
- [x] Automatic pruning of tokens FCM reports as unregistered.

## 3. Objective Verification Matrix
| Command | Result | Notes |
| :--- | :--- | :--- |
| `pytest -q` (backend) | PASS | 102 tests incl. FCM and devices suites |
| `ruff check backend` | PASS | No issues |
| Firebase credential smoke test | PASS | Admin SDK initializes with the service account |
| `python3 scripts/verify_pipeline.py` | PASS | Full local gate |
