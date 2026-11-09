---
name: devops-workflow
description: Automated containerization, deployment to Koyeb PaaS, ntfy push setup, and CI/CD quality gates.
---

# DevOps Workflow & Deployment Guide

## Trigger Keywords

`deploy`, `koyeb`, `docker`, `compose`, `ntfy`, `ci`, `cd`, `branch protection`

## 1. Multi-Stage Containerization (`backend/Dockerfile`)
The daemon image builds in two stages:
- **Stage 1 (`builder`)**: Uses `python:3.11-slim`, installs build tooling (`curl`, `build-essential`, `git`), and compiles dependencies into `/opt/venv`.
- **Stage 2 (`runner`)**: Uses `python:3.11-slim`, installs runtime libraries (`libgl1`, `libglib2.0-0`, `curl`), copies `/opt/venv` from builder, and executes `uvicorn app.main:app --host 0.0.0.0 --port 8000`.

## 2. Cloud PaaS Deployment (Koyeb)
- **Runtime**: Python container running 24/7 on Koyeb Nano tier (512MB RAM).
- **Build Method**: GitHub repository auto-deployment from branch `main`.
- **Build Context**: `/`
- **Dockerfile Path**: `backend/Dockerfile`
- **Required Environment Variables**:
  - `SIMKULIAH_NPM`: Student NPM.
  - `SIMKULIAH_PASSWORD`: Portal password.
  - `NTFY_TOPIC`: Private topic identifier.
  - `ACTION_SECRET_KEY`: 32-character random HMAC signing key.
  - `SUPABASE_URL`: Supabase project URL (`https://<ref>.supabase.co`).
  - `SUPABASE_SECRET_KEY`: Supabase Secret API key (`sb_secret_...`) or legacy `SUPABASE_SERVICE_ROLE_KEY`.

## 3. Local Verification Pipeline
Always verify pipeline before creating pull requests:
```bash
# Fast iteration check
python3 scripts/verify_pipeline.py --fast

# Full pipeline run
python3 scripts/verify_pipeline.py
```

## 4. Branch Protection Rules
The `main` branch is governed by a GitHub Ruleset:
- Deletion: Blocked.
- Force push (non-fast-forward): Blocked.
- Pull request: Required.
- Status check: `Lint, Test, & Contract Verification` from `.github/workflows/ci.yml` must pass.
