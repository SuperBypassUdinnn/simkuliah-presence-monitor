# Backend Standards (Python FastAPI)

## 1. Asynchronous Architecture & Event Loop Safety
- All I/O operations (HTTP requests, file reads) must use `async/await` via `httpx.AsyncClient`.
- Synchronous blocking operations (such as the standard `supabase-py` client) **MUST** be wrapped in `await asyncio.to_thread(...)` to prevent stalling the FastAPI event loop or APScheduler ticks.

## 2. Strong Typing with Pydantic v2
- Use `pydantic.BaseModel` for all data transfer objects (DTOs), requests, and responses.
- Use `StrEnum` (or `enum.Enum`) for discrete status fields (`NotificationLevel`, `OverrideType`).
- Maintain strict typing: `str | None`, `int | None`, `list[...]`, `dict[...]`. Avoid bare `Any` where types are known.

## 3. Session Management & CAPTCHA Solver
- Reuse the `httpx.AsyncClient` cookie jar across requests to preserve `ci_session`.
- Refresh session every 12 minutes via `GET /index.php/mahasiswa/dashboard` during active lecture hours.
- CAPTCHA recognition must execute locally on CPU using `ddddocr` without external cloud APIs.
- Retries on incorrect CAPTCHA must be capped at 3 attempts with exponential backoff on server errors (30s to 300s).

## 4. Webhook Security & Idempotency
- All direct-action webhooks must validate the `X-Action-Token` header using `verify_action_token`.
- Tokens are signed with HMAC-SHA256 and carried as base64url envelopes with expiration timestamps.
- Idempotency guards must prevent duplicate processing of the same token.

## 5. File Hygiene & Architecture Headers
Every non-trivial Python file must begin with:
```python
"""
Purpose: <1-2 sentences on why this file exists>
Data & Logic Flow: <inputs -> processing -> outputs>
Key Components: <primary classes/functions>
"""
```
Maintain 2 blank lines between classes and top-level functions.
