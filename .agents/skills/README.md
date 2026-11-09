# Agent Skills Catalog — Simkuliah Presence Monitor

This directory contains all **agent skills and technical workflow guides** for the Simkuliah Presence Monitor project.

---

## Directory Structure

```
.agent/skills/
├── README.md                           <- You are here (catalog + activation guide)
├── stacks.md                           <- System topology, credentials, endpoints, priorities
├── devops-workflow/
│   └── SKILL.md                        <- Multi-stage Docker, Koyeb PaaS, ntfy relay, CI/CD
├── gh-project-manager/
│   └── SKILL.md                        <- ghx issue management, PR rulesets, milestones
├── karpathy-guidelines/
│   └── SKILL.md                        <- Simplicity first, surgical edits, goal-driven TDD
└── feature-dev-workflow/
    ├── SKILL.md                        <- Contract-first pipeline for Python FastAPI + Flutter
    ├── backend-standards.md            <- FastAPI, Pydantic v2, async safety, error handling
    ├── flutter-standards.md            <- Flutter Material 3, mounted checks, responsive
    └── supabase-patterns.md            <- Supabase CLI migrations, RLS, async to_thread
```

---

## Skill Catalog

| Skill | Trigger Keywords | Directory | Description |
| :--- | :--- | :--- | :--- |
| **feature-dev-workflow** | `new feature`, `feature`, `endpoint`, `screen`, `scraper`, `state machine`, `migration` | [`feature-dev-workflow/`](feature-dev-workflow/SKILL.md) | Contract-first pipeline for Python FastAPI + Flutter feature development |
| **devops-workflow** | `deploy`, `koyeb`, `docker`, `compose`, `ntfy`, `ci`, `cd`, `branch protection` | [`devops-workflow/`](devops-workflow/SKILL.md) | Deployment, multi-stage Docker build, ntfy relay, and CI/CD rules |
| **gh-project-manager** | `backlog`, `issue`, `milestone`, `progress report`, `assign`, `pr` | [`gh-project-manager/`](gh-project-manager/SKILL.md) | Manage GitHub issues, labels, PR status, and branch merges via `ghx` CLI |
| **karpathy-guidelines** | `karpathy`, `surgical change`, `clean code`, `simplicity`, `kiss`, `yagni` | [`karpathy-guidelines/`](karpathy-guidelines/SKILL.md) | Behavioral guidelines for non-speculative, goal-driven engineering |

---

## Execution Invariants

1. **Check Backlog & Architecture First**: Run `python3 scripts/sync_backlog_status.py --check` and read `.planning/README.md` before starting work.
2. **Deterministic Verification**: Verify code changes locally using `python3 scripts/verify_pipeline.py --fast` (or full suite) before opening PRs.
3. **Canonical Ruleset**: All agent behaviors adhere to the root `AGENTS.md` and repository standards.
