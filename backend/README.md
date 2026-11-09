# Simkuliah Backend

Python FastAPI daemon that polls the Simkuliah USK portal, syncs attendance into
Supabase, and dispatches ntfy.sh push notifications with signed action buttons.

## Configuration through a single `.env` file

All runtime configuration is read from one `.env` file. There is no need to add
individual environment variables in the Render dashboard or shell profiles.

### Resolution order

The backend probes these locations at startup and uses the first that exists
(see `backend/app/config.py`):

1. `$ENV_FILE` — explicit override (optional).
2. `/etc/secrets/.env` — Render Secret File convention (auto-detected).
3. `/etc/secrets/backend.env` — alternative Render Secret File name.
4. `backend/.env` — local development next to the app package.
5. `./.env` — relative to the current working directory (repository root).

Precedence within a resolved file: real environment variables always override
`.env` values, so a one-off `SIMKULIAH_NPM=... uvicorn app.main:app` still wins.

### Local development

```bash
cd backend
cp .env.example .env        # then fill in the values
.venv/bin/uvicorn app.main:app --reload
```

`backend/.env` is git-ignored and docker-ignored, so credentials never reach the
repository or the image build context.

### Render deployment

1. Open the `simkuliah-backend` service in the Render dashboard.
2. Go to **Environment -> Secret Files -> + Add Secret File**.
3. Set the filename to `.env` and paste the filled contents of
   `backend/.env.example`.
4. Save. Render mounts the file at `/etc/secrets/.env`, which the backend
   auto-detects — no per-variable environment entries are required.

To rotate a credential or change polling behavior, edit the secret file
contents and save; Render redeploys with the new values. `render.yaml` mirrors
this setup and intentionally declares no `envVars`.

## API surface

- `GET /api/v1/health` — liveness probe used by Render health checks.
- `POST /api/v1/webhook/action` — HMAC-verified endpoint targeted by ntfy
  action buttons.

## Verification

```bash
python3 scripts/verify_pipeline.py          # full multi-stack gate
cd backend && pytest -q                     # backend tests only
```
