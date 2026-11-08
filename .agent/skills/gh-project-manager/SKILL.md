---
name: gh-project-manager
description: Manage GitHub issues, labels, milestones, and pull request workflows via ghx CLI.
---

# GitHub Project Management Workflow

Standardized procedures for managing repository issues, labels, and PR lifecycles using `ghx`.

## Trigger Keywords

`backlog`, `issue`, `milestone`, `progress report`, `assign`, `pr`

## 1. Issue Lifecycle

- **Create Issue**:
  ```bash
  ghx issue create --title "feat: <title>" --body "<description>" --label "component: backend,status: backlog"
  ```
- **Start Work**:
  Update label to `status: in-progress` and assign:
  ```bash
  ghx issue edit <id> --add-label "status: in-progress" --add-assignee "@me"
  ghx issue comment <id> --body "Starting implementation on feature F-XXX."
  ```
- **PR In Review**:
  Update label to `status: in-review` once PR is created.
- **Completion**:
  Close issue with an outcome summary comment once merged.

## 2. Commit & PR Invariants

- **Conventional Commits**: `<type>(<scope>): <subject>` in plain text.
- **Pull Request**: Use rich GitHub Flavored Markdown adhering to `.github/pull_request_template.md`.
- Never include internal developer indexing tools (`codegraph sync`) in commit messages or PR descriptions.
