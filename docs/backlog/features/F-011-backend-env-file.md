# Feature Log: F-011 Backend `.env` Configuration

- **Parent Plan**: [`.planning/03-backend-env-management.md`](../../../.planning/03-backend-env-management.md)
- **Target Issue**: #14
- **Status**: In Progress
- **Author**: AI Agent / Developer

## 1. Problem Statement & Scope
Backend configuration required typing each environment variable into the Render
dashboard. Move everything into one `.env` file with a deterministic resolution
chain so local development and production share the same mechanism.

## 2. Implementation Checklist
- [x] Resolve `ENV_FILE` override, Render secret files, `backend/.env`, then `./.env`.
- [x] Preload the resolved file into the process environment via `python-dotenv`.
- [x] Source ntfy dispatcher defaults from app settings.
- [x] Add `backend/.env.example` and `backend/.dockerignore`.
- [x] Remove per-variable entries from `render.yaml`.
- [x] Document local and Render workflows in `backend/README.md`.
- [x] Add unit tests for resolution order and env-over-file precedence.

## 3. Objective Verification Matrix
| Command | Result | Notes |
| :--- | :--- | :--- |
| `pytest -q tests/test_config.py` | PASS | 9 tests incl. resolution chain |
| `ruff check backend` | PASS | No issues |
| `ruff format --check backend` | PASS | Formatted |
| `python3 scripts/verify_pipeline.py` | PASS | Full local gate |
