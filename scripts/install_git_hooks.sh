#!/usr/bin/env bash
# install_git_hooks.sh - Configure git to use version-controlled .githooks/
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

if [ ! -d ".git" ]; then
    echo "ERROR: Not a git repository. Run 'git init' first." >&2
    exit 1
fi

if [ -d ".githooks" ]; then
    chmod +x .githooks/* 2>/dev/null || true
    git config core.hooksPath .githooks
    echo "[SUCCESS] Configured git core.hooksPath to .githooks/"
else
    echo "ERROR: .githooks directory not found." >&2
    exit 1
fi
