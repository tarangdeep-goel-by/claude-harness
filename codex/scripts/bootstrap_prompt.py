#!/usr/bin/env python3
"""Generate a Codex bootstrap prompt from the shared warm-start infra."""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

WARM_START = Path.home() / ".codex" / "scripts" / "codex_warm_start.sh"


def run_warm_start(cwd: str, source: str) -> str:
    payload = json.dumps({"source": source, "cwd": cwd})
    try:
        proc = subprocess.run(
            [str(WARM_START)],
            input=payload,
            text=True,
            capture_output=True,
            check=False,
        )
    except OSError as exc:
        return f"Warm-start unavailable: {exc}"

    stdout = proc.stdout.strip()
    if not stdout:
        stderr = proc.stderr.strip()
        return f"Warm-start returned no context. {stderr}".strip()

    try:
        data = json.loads(stdout)
        return data.get("hookSpecificOutput", {}).get("additionalContext", "").strip() or stdout
    except json.JSONDecodeError:
        return stdout


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--cwd", default=".")
    parser.add_argument("--source", default="manual")
    args = parser.parse_args()

    cwd = str(Path(args.cwd).resolve())
    context = run_warm_start(cwd, args.source)

    prompt = f"""Use this warm-start brief as background context for the session.
Follow repo AGENTS.md, use Codex skills when they match, and prefer the shared vault/qmd workflows where relevant.

Warm-start brief:
{context}
""".strip()
    sys.stdout.write(prompt)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
