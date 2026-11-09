# Plan 03: Backend Environment Management

- **Target Issues**: #14
- **Status**: In Progress
- **Primary Stack**: Python

## 1. Context & Objectives
Move all backend configuration into a single `.env` file so rotating a
credential or onboarding a collaborator never requires editing individual
environment variables in the Render dashboard or shell profiles.

## 2. Architectural Boundaries & Decisions
- One resolution chain: `$ENV_FILE` override, Render secret-file locations
  (`/etc/secrets/.env`, `/etc/secrets/backend.env`), `backend/.env`, then
  `./.env` relative to the working directory.
- The resolved file is loaded into the process environment with
  `python-dotenv` so direct `os.environ` reads observe the same values as
  Pydantic settings; real environment variables always win.
- Secrets stay out of the repository and image: `backend/.env` is git-ignored
  and `backend/.dockerignore` keeps it out of the build context.
- `render.yaml` declares no `envVars`; production configuration is one Render
  Secret File named `.env` mounted at `/etc/secrets/.env`.

## 3. Implementation Steps
- [x] Add `.env` resolution and dotenv preload to `app/config.py`.
- [x] Source ntfy defaults from app settings instead of raw `os.environ`.
- [x] Provide `backend/.env.example` and `backend/.dockerignore`.
- [x] Simplify `render.yaml` to the secret-file convention.
- [x] Document local and Render setup in `backend/README.md`.
- [x] Cover resolution order and precedence with unit tests.

## 4. Verification Gate
```bash
python3 scripts/verify_pipeline.py
python3 scripts/sync_backlog_status.py --check
```
