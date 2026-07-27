#!/usr/bin/env python3
"""Doctor checks for the native Codex hook harness."""
from __future__ import annotations

import json
import shutil
import subprocess
import tomllib
from pathlib import Path

HOME = Path.home()
CODEX = HOME / ".codex"
SCRIPTS = CODEX / "scripts"
HOOKS = CODEX / "hooks.json"
CONFIG = CODEX / "config.toml"
LOG = HOME / "vault" / "logs" / "hooks.jsonl"


def check(name: str, ok: bool, detail: str = "") -> bool:
    status = "ok" if ok else "fail"
    print(f"{status:4} {name}{': ' + detail if detail else ''}")
    return ok


def run(cmd: list[str], input_text: str = "") -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, input=input_text, text=True, capture_output=True, check=False, timeout=20)


def main() -> int:
    failures = 0
    try:
        hooks_data = json.loads(HOOKS.read_text())
        failures += not check("hooks.json", isinstance(hooks_data.get("hooks"), dict), str(HOOKS))
    except Exception as exc:
        failures += not check("hooks.json", False, repr(exc))
        hooks_data = {}

    try:
        config_data = tomllib.loads(CONFIG.read_text())
        features = config_data.get("features", {})
        failures += not check("config.toml", True, str(CONFIG))
        failures += not check("codex_hooks", features.get("codex_hooks") is True, "enabled")
        failures += not check("qmd MCP absent", "qmd" not in config_data.get("mcp_servers", {}), "CLI-only")
    except Exception as exc:
        failures += not check("config.toml", False, repr(exc))

    failures += not check("qmd", shutil.which("qmd") is not None, shutil.which("qmd") or "missing")

    py_files = sorted(SCRIPTS.glob("*.py"))
    if py_files:
        proc = run(["python3", "-m", "py_compile", *map(str, py_files)])
        failures += not check("python compile", proc.returncode == 0, proc.stderr.strip())

    for path in sorted(SCRIPTS.glob("*.sh")):
        proc = run(["bash", "-n", str(path)])
        failures += not check(f"bash -n {path.name}", proc.returncode == 0, proc.stderr.strip())

    adapter = SCRIPTS / "codex_hook_adapter.py"
    proc = run(["python3", str(adapter), "SessionStart"], json.dumps({"source": "startup", "cwd": str(Path.cwd()), "session_id": "doctor"}))
    ok = proc.returncode == 0 and "additionalContext" in proc.stdout and len(proc.stdout.split()) < 1600
    failures += not check("SessionStart smoke", ok, f"{len(proc.stdout.split())} words")

    proc = run(["python3", str(adapter), "PreToolUse"], json.dumps({"tool_name": "Bash", "tool_input": {"command": "git reset --hard"}}))
    failures += not check("dangerous command block", '"decision":"block"' in proc.stdout, proc.stdout.strip())

    proc = run(["python3", str(adapter), "PermissionRequest"], json.dumps({"tool_name": "Bash", "tool_input": {"command": "python3 -m py_compile foo.py"}}))
    failures += not check("python permission allow", '"decision":"allow"' in proc.stdout, proc.stdout.strip())

    if LOG.exists():
        recent = LOG.read_text(errors="ignore").splitlines()[-5:]
        failures += not check("recent hook log", bool(recent), f"{len(recent)} entries")
    else:
        check("recent hook log", False, "not found")

    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
