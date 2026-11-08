---
name: feature-dev-workflow
description: End-to-end contract-first feature pipeline for Python FastAPI and Flutter multi-platform development.
---

# Feature Development Workflow

Build Python FastAPI backend services and Flutter multi-platform components contract-first from backlog to PR.

## Trigger Keywords

`new feature`, `feature`, `endpoint`, `screen`, `scraper`, `state machine`, `migration`, `presence`, `override`

## Workflow Summary

| Step | Action | Artifacts |
| :--- | :--- | :--- |
| **-3: Backlog Audit** | Run `python3 scripts/sync_backlog_status.py --check` to verify parity. Read `docs/DATABASE_SCHEMA.md` and `.planning/README.md`. | Backlog parity check |
| **-2: Discovery** | Inspect existing code via CodeGraph (`codegraph explore -p . "<query>"`). State assumptions explicitly. Write feature plan. | Discovery notes |
| **-1: Feature Log** | Create execution log in `docs/backlog/features/F-XXX-name.md` linked to parent plan in `.planning/`. | Feature log file |
| **0: Branching** | Create `feature/F-XXX-name` from `main`. Assign issue via `ghx`. | Git branch |
| **1: Database First** | If schema changes are needed, author migration via Supabase CLI (`supabase migration new <name>`) and update `docs/DATABASE_SCHEMA.md`. | Migration SQL |
| **2: API Contract** | Update `docs/api/openapi.yaml` with any new endpoint or schema contracts. | Updated OpenAPI spec |
| **3: Backend (TDD)** | Implement logic in `backend/app/` using test-driven development (write failing test in `backend/tests/`, verify RED, implement, verify GREEN). | Python source + tests |
| **4: Client (Flutter)** | Implement screens/models/services in `client/lib/` and tests in `client/test/`. | Dart source + widget tests |
| **5: Quality Gate** | Run `python3 scripts/verify_pipeline.py`. Ensure linters (`ruff`, `flutter analyze`, `dart format`) and test suites pass 100%. | Passing pipeline |
| **6: Review & PR** | Push branch and open Pull Request with rich GFM description. Verify CI checks pass. | GitHub Pull Request |

---

## Technical Standards Reference

- Backend Standards: [backend-standards.md](backend-standards.md)
- Flutter Standards: [flutter-standards.md](flutter-standards.md)
- Supabase Patterns: [supabase-patterns.md](supabase-patterns.md)
