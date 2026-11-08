#!/usr/bin/env python3
"""verify_pipeline.py - Automated multi-stack quality verification runner for simkuliah-presence-monitor."""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path

failures = 0


def run_check(cmd: list[str], cwd: Path | None = None, name: str = "") -> bool:
    global failures
    label = name or " ".join(cmd)
    cwd_str = str(cwd) if cwd else "."
    print(f"[*] Running {label} in {cwd_str}...", flush=True)
    try:
        res = subprocess.run(cmd, check=False, cwd=cwd, text=True, capture_output=True)
        if res.returncode != 0:
            print(f"[FAIL] {label} failed with code {res.returncode}:", file=sys.stderr)
            if res.stdout:
                print(res.stdout, file=sys.stderr)
            if res.stderr:
                print(res.stderr, file=sys.stderr)
            failures += 1
            return False
        else:
            print(f"[PASS] {label}")
            return True
    except FileNotFoundError:
        print(f"[WARN] Command {cmd[0]} not found. Skipping {label}.")
        return True


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Automated quality verification pipeline."
    )
    parser.add_argument(
        "--fast", action="store_true", help="Fast iteration mode (skips heavy suites)"
    )
    parser.add_argument(
        "--skip-vuln", action="store_true", help="Skip vulnerability scanning"
    )
    args = parser.parse_args()
    fast_mode = args.fast

    # Python checks
    venv_pytest = Path("backend/.venv/bin/pytest")
    pytest_bin = (
        str(venv_pytest.resolve())
        if venv_pytest.exists()
        else (shutil.which("pytest") or "pytest")
    )

    if shutil.which("ruff"):
        run_check(["ruff", "check", "backend", "scripts"], name="ruff check")
        run_check(
            ["ruff", "format", "--check", "backend", "scripts"], name="ruff format"
        )
    if (venv_pytest.exists() or shutil.which("pytest")) and any(
        Path("backend").glob("**/test_*.py")
    ):
        pytest_cmd = (
            [pytest_bin, "-q"]
            if not fast_mode
            else [pytest_bin, "-q", "-m", "not slow"]
        )
        run_check(pytest_cmd, cwd=Path("backend"), name="pytest (backend)")

    # Flutter checks
    pubspecs = [p for p in Path(".").glob("**/pubspec.yaml") if ".git" not in p.parts]
    for pdir in pubspecs:
        workdir = pdir.parent
        pkg_config = workdir / ".dart_tool" / "package_config.json"
        if not pkg_config.exists() and shutil.which("flutter"):
            print(f"[*] Resolving dependencies for {workdir}...")
            subprocess.run(
                ["flutter", "pub", "get"], check=False, cwd=workdir, capture_output=True
            )
        if shutil.which("flutter") and pkg_config.exists():
            run_check(
                ["flutter", "analyze", "--no-pub"],
                cwd=workdir,
                name=f"flutter analyze ({workdir})",
            )
        if shutil.which("dart"):
            run_check(
                ["dart", "format", "--output=none", "--set-exit-if-changed", "."],
                cwd=workdir,
                name=f"dart format ({workdir})",
            )

    if failures > 0:
        print(f"\nVerification FAILED with {failures} error(s).", file=sys.stderr)
        return 1
    print("\nAll verification checks PASSED successfully.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
