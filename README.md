# simkuliah-presence-monitor

Production project initialized with **project-scaffold**.

- **Architecture Mode**: `monorepo`
- **Active Stacks**: `python, flutter`
- **Database**: `postgres`
- **Infrastructure**: `docker`

## Getting Started

### 1. Workstation Setup & Git Hooks
Run the automated git hooks installer:
```bash
bash scripts/install_git_hooks.sh
```

### 2. Verification Pipeline
Verify that all tests, linters, and analysis pass cleanly:
```bash
# Fast iteration check
python3 scripts/verify_pipeline.py --fast

# Full comprehensive check
python3 scripts/verify_pipeline.py
```

### 3. Backlog Status Check
Verify parity between `.planning/README.md` and feature logs in `docs/backlog/features/`:
```bash
python3 scripts/sync_backlog_status.py --check
```

### 4. Database Migrations
Migrations live in `supabase/migrations/` and are applied to the hosted project
(`ftznonanlbshweysliar`) automatically.

- **Automatic**: merging a change under `supabase/migrations/**` into `main`
  triggers `.github/workflows/supabase-deploy.yml`, which runs a dry run and
  then `supabase db push --remote --yes`.
- **Manual**: run the same workflow from the Actions tab via `workflow_dispatch`.
- **Required secret**: `SUPABASE_ACCESS_TOKEN` (repository secret). No database
  password is needed because the CLI authenticates through the Management API.

Local inspection without Docker:
```bash
# List local vs remote migration state
supabase migration list --remote

# Preview what would be applied
supabase db push --remote --dry-run
```

## Repository Structure

```text
.
├── .github/workflows/        # CI/CD pipeline definitions
├── .githooks/                # Pre-commit quality gate hooks
├── .planning/                # Architectural roadmap and plan catalog
├── docs/
│   ├── ARCHITECTURE.md       # High-level system design
│   ├── api/                  # OpenAPI contracts
│   └── backlog/features/     # Task-level feature execution logs
├── scripts/                  # Automated verification and sync tools
├── AGENTS.md                 # AI agent governance and rules
├── opencode.jsonc            # OpenCode workspace configuration
└── README.md
```

## AI Agent Governance
This project follows strict AI worker invariants documented in [`AGENTS.md`](AGENTS.md).
