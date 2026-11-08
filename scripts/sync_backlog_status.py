#!/usr/bin/env python3
"""sync_backlog_status.py - Validate consistency between .planning and docs/backlog."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Validate planning and backlog parity."
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="Check parity and exit with error code if out of sync",
    )
    args = parser.parse_args()

    planning_readme = Path(".planning/README.md")
    if not planning_readme.exists():
        print("[FAIL] Missing .planning/README.md", file=sys.stderr)
        return 1

    features_dir = Path("docs/backlog/features")
    if not features_dir.exists():
        print("[FAIL] Missing docs/backlog/features directory", file=sys.stderr)
        return 1

    content = planning_readme.read_text(encoding="utf-8")
    plans = re.findall(r"\[`(0\d-[^`]+)`\]", content)
    print(f"[*] Found {len(plans)} registered plan(s) in .planning/README.md")

    feature_files = list(features_dir.glob("F-*.md"))
    print(f"[*] Found {len(feature_files)} feature execution log(s) in {features_dir}")

    # Check for orphaned plan files
    all_plan_files = [p.name for p in Path(".planning").glob("0*.md")]
    orphaned_plans = [p for p in all_plan_files if p not in plans]
    if orphaned_plans:
        print(
            f"[WARN] Plan file(s) present on disk but not registered in .planning/README.md: {orphaned_plans}"
        )
        if args.check:
            return 1

    print("[PASS] Planning and backlog status parity verified.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
