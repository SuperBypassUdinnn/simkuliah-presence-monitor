# Architecture Governance Rules — Simkuliah Presence Monitor

Adheres to `docs/ARCHITECTURE.md` and repository standards.

## 1. Boundary & Layer Isolation
- **Backend (`backend/app/`)**: Fast, stateless REST endpoints and autonomous polling daemon.
  - `core/`: Database repository, encryption/HMAC tokens, settings.
  - `services/`: Scraper, session manager, CAPTCHA solver, state machine, ntfy dispatcher, adaptive poller.
  - `api/`: Route definitions and direct-action webhooks (`/api/v1/webhooks`).
- **Client (`client/lib/`)**: Multi-platform Flutter application.
  - `core/`: Supabase configuration and theme tokens.
  - `models/`: Immutable domain DTOs.
  - `services/`: Supabase client data access and Realtime listeners.
  - `views/`: Flutter widgets (today feed, matrix, countdown, alert banner).
- **Database (`supabase/`)**: Supabase PostgreSQL with Row Level Security (RLS) and Realtime replication.

## 2. Invariants
- Asynchronous database calls in Python must wrap synchronous client calls with `await asyncio.to_thread(...)`.
- Flutter widgets must check `if (!context.mounted) return;` before navigating or triggering state mutations.
- Every migration must be authored through Supabase CLI and committed under `supabase/migrations/`.
