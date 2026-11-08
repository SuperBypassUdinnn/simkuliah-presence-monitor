# simkuliah-presence-monitor Agent Governance & System Rules

Canonical repository governance contract for OpenCode and Antigravity AI agents.

## Session Start (Mandatory)

1. Read `.planning/README.md` to identify the active architectural roadmap and target issues.
2. Read `docs/ARCHITECTURE.md` before proposing or modifying structural boundaries.
3. Review `docs/backlog/features/` for in-flight task execution logs (`F-XXX-name.md`).
4. Execute the verification pipeline (`python3 scripts/verify_pipeline.py --fast`) to ensure clean initial state.

## Session End

1. Verify all automated pipeline checks pass (`python3 scripts/verify_pipeline.py`).
2. Run backlog status check (`python3 scripts/sync_backlog_status.py --check`).
3. Persist technical gotchas and architectural decisions to workspace memory. Notify user upon completion.

## Tool Mapping (Dual-Support)

| Antigravity Native | OpenCode Native |
| :--- | :--- |
| `grep_search` | `grep` |
| `find_by_name` | `glob` |
| `view_file` | `read` |
| `ask_question` | `question` |
| skill trigger keywords | `skill` tool or `@<skill-id>` mention |

## Verification Defaults

- Backend/Scripts (Python): `pytest -q`, `ruff check .`, `ruff format --check .`
- Mobile/Desktop (Flutter): `flutter analyze --no-pub`, `dart format --output=none --set-exit-if-changed .`
- Automated Pipeline Gate: `python3 scripts/verify_pipeline.py --fast` (fast iterations) or `python3 scripts/verify_pipeline.py` (full pre-PR)
- Backlog Parity Gate: `python3 scripts/sync_backlog_status.py --check`

## Architectural & Behavioral Governance

### 1. Karpathy Behavioral Guidelines
1. **Think Before Coding**: Surface assumptions explicitly, inspect the codebase autonomously before asking questions, and state trade-offs.
2. **Simplicity First (KISS & YAGNI)**: Implement the minimum code that solves the problem. Forbid speculative abstractions, unrequested features, or unnecessary indirection.
3. **Surgical Changes**: Restrict code edits strictly to target symbols. Never modify adjacent lines, reformat untouched code, or refactor unrelated files.
4. **Goal-Driven Execution**: Define objective verification commands before applying changes and iterate until all checks pass.

### 2. Code File Hygiene & Architecture Headers
1. **Top-of-File Architecture Header**: Every non-trivial source file must begin with an architectural header comment detailing:
   - `Purpose`: Why the file exists and its primary responsibility.
   - `Data & Logic Flow`: High-level summary of inputs, processing pipeline, and outputs.
   - `Key Components`: Primary structs, classes, handlers, or services.
2. **Visual Breathing Room**: Maintain 2 blank lines between major functions, classes, structs, endpoint handlers, and distinct logic sections.

### 3. Persistent Planning & Archiving Lifecycle
1. **Hybrid Planning Hierarchy**:
   - `.planning/`: High-level architectural roadmaps, domain epic specifications, and technical designs (`NN-name.md`), cataloged in `.planning/README.md`.
   - `docs/backlog/features/`: Task-level feature execution logs (`F-XXX-name.md`) tied to specific issues. Every feature log must link to its parent plan in `.planning/`.
2. **Active Frontier in Root**: Plans under active consideration (`Draft`, `Backlog`, `In Progress`) or completed in the current cycle (`Merged`) remain in `.planning/`.
3. **Milestone Release Archiving Trigger**: When cutting a release and incrementing `VERSION` (e.g. `v1.0.0`), all plans marked `Merged` during that cycle MUST be archived into `.planning/archive/<version>/`.


## Git & Operational Constraints

1. **Strictly No Uninstructed Commits/Pushes**: AI workers must never create Git commits, push branches, or open Pull Requests unless specifically commanded by the user in the current turn.
2. **Concise Plain-Text Commit Messages vs Rich Detailed PRs**:
   - **Commit Messages**: Keep commit messages short, concise, and focused. Follow Conventional Commits (`<type>(<scope>): <subject>`) with an optional brief 1-3 line plain-text explanation of WHY. Never use Markdown formatting (no `#`, `**`, code fences) in commit messages.
   - **Pull Request Descriptions**: Place comprehensive breakdowns (problem context, architectural rationale, component updates, verification matrix) in the PR description where rich GitHub Flavored Markdown is supported.
3. **Exclude Local Tooling from PRs & Commits**: Never include status, checkboxes, or verification logs for developer-side indexing tools (like `codegraph sync`) in commit messages or PR descriptions.
4. **Language Policy**:
   - All written code, repository artifacts, documentation, and agent task files must be authored in formal **technical English**.
   - Interactive chat dialogue adapts to the user's conversational preference.
