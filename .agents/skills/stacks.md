# Stacks & Project Configuration — Simkuliah Presence Monitor

## Tech Stack

| Layer | Technology | Directory |
| :--- | :--- | :--- |
| **Backend Daemon** | Python 3.11+ / FastAPI / AsyncIO / HTTPX / APScheduler | `backend/` |
| **CAPTCHA Solver** | `ddddocr` (ONNX CPU Inference) | `backend/app/services/captcha.py` |
| **Database** | PostgreSQL 15 via Supabase Cloud | `supabase/migrations/` |
| **Push Notification** | ntfy.sh with signed `X-Action-Token` HTTP buttons | `backend/app/services/ntfy_service.py` |
| **Multi-Platform Client**| Flutter 3.47+ / Dart 3.13+ (Android, Linux, Windows) | `client/` |
| **Containerization** | Multi-stage Docker (`python:3.11-slim`), Docker Compose | `backend/Dockerfile`, `docker-compose.yml` |

## Project Configuration

```
Repo Owner     : SuperBypassUdinnn
Repo Name      : SuperBypassUdinnn/simkuliah-presence-monitor
Default Branch : main
Dev Branch     : main (or feature/* branches via Pull Request)
```

## Branch Strategy

- **Feature Branch**: `feature/F-XXX-name` (e.g., `feature/F-001-setup`, `feature/F-002-scraper`)
- **Bugfix Branch**: `fix/F-XXX-name`
- **Main Branch**: Protected by GitHub Ruleset (requires PR and passing `Lint, Test, & Contract Verification` status check).

## GitHub Labels

- **Priority**: `priority: P0`, `priority: P1`, `priority: P2`
- **Status**: `status: backlog`, `status: in-progress`, `status: in-review`, `status: ready`, `status: done`
- **Component**: `component: backend`, `component: client`, `component: database`, `component: infra`, `component: docs`
