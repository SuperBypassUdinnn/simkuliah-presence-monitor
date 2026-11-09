# Feature Log: F-012 Priority Policy & ntfy Action Fixes

- **Parent Plan**: [`.planning/04-hybrid-push-notifications.md`](../../../.planning/04-hybrid-push-notifications.md)
- **Target Issue**: #17
- **Status**: In Progress
- **Author**: AI Agent / Developer

## 1. Problem Statement & Scope
ntfy action buttons targeted `ntfy.sh` with an invalid JSON schema, and
priority was mapped ad-hoc. Introduce the shared priority policy (high only
for `lecturer_opened` and `urgent_closing`) and fix the action transport.

## 2. Implementation Checklist
- [x] Add `Priority` enum and `priority_for_state()` to the state machine.
- [x] Map ntfy priorities through the policy (high → `urgent`, normal → `default`).
- [x] Add `SIMKULIAH_API_BASE_URL` setting with `RENDER_EXTERNAL_URL` fallback.
- [x] Target action buttons at the backend webhook.
- [x] Omit actions when no public base URL is known.
- [x] Publish the plain message body with header-based actions (drop invalid JSON payload).

## 3. Objective Verification Matrix
| Command | Result | Notes |
| :--- | :--- | :--- |
| `pytest -q tests/test_ntfy_service.py tests/test_state_machine.py` | PASS | Priority and payload covered |
| `ruff check backend` | PASS | No issues |
| `python3 scripts/verify_pipeline.py` | PASS | Full local gate |
