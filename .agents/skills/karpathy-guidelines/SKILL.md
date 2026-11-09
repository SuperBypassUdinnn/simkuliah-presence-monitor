---
name: karpathy-guidelines
description: Behavioral guidelines to prevent common LLM coding mistakes - simplicity first, surgical edits, and goal-driven execution.
---

# Karpathy Behavioral Guidelines

Four foundational invariants governing every code modification:

## 1. Think Before Coding
- Never dive into writing code without inspecting existing patterns and state.
- Surface assumptions explicitly; explore the codebase autonomously via CodeGraph (`codegraph explore -p . "<query>"`).
- State architectural trade-offs clearly before implementation.

## 2. Simplicity First (KISS & YAGNI)
- Implement the minimum viable code that directly solves the problem.
- Forbid speculative abstractions, unnecessary design patterns, or unrequested features.
- Less code means fewer bugs and smaller context overhead.

## 3. Surgical Changes
- Restrict edits strictly to target symbols and lines.
- Never modify adjacent untouched lines, reformat unrelated files, or introduce drive-by refactorings.
- Keep diffs minimal, focused, and reviewable.

## 4. Goal-Driven Execution
- Define objective verification commands before making changes (e.g. `pytest backend/tests/test_foo.py`).
- Iterate in a test-driven loop until all tests and linters pass cleanly.
- Evidence before assertions: confirm real output before claiming completion.
