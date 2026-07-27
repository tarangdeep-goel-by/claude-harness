#!/usr/bin/env bash
# catalog-codex-sessions.sh - digest recent Codex session cache into a compact catalog.
# READ-ONLY: reads ~/.codex/sessions/*/*/*/*.jsonl and writes only the catalog file.
#   Usage: ./catalog-codex-sessions.sh [DAYS] [OUT_FILE]  (default: 30 -> ./codex-session-catalog.md)
set -uo pipefail

DAYS="${1:-30}"
OUT="${2:-./codex-session-catalog.md}"
SESSIONS="$HOME/.codex/sessions"

[ -d "$SESSIONS" ] || { echo "no ~/.codex/sessions - nothing to catalog"; exit 1; }

python3 - "$SESSIONS" "$DAYS" "$OUT" <<'PY'
from __future__ import annotations

import json
import sys
import time
from collections import defaultdict
from datetime import datetime
from pathlib import Path

sessions_dir = Path(sys.argv[1]).expanduser()
days = int(sys.argv[2])
out = Path(sys.argv[3]).expanduser()
cutoff = time.time() - days * 24 * 60 * 60

NOISE = (
    "Use this warm-start brief as background context",
    "Warm-start brief:",
    "# Project Intelligence (auto-generated)",
    "Skill Suggestions (auto-detected)",
    "<recommended_plugins>",
    "# AGENTS.md instructions",
    "<environment_context>",
    "<permissions instructions>",
)


def text_blocks(content) -> str:
    if isinstance(content, str):
        return content.strip()
    if not isinstance(content, list):
        return ""
    parts = []
    for block in content:
        if isinstance(block, dict) and block.get("type") in {"input_text", "output_text", "text"}:
            text = str(block.get("text") or "").strip()
            if text:
                parts.append(text)
    return " ".join(parts).strip()


def is_noise(text: str) -> bool:
    stripped = text.lstrip()
    return any(stripped.startswith(marker) or marker in stripped[:500] for marker in NOISE)


def parse(path: Path) -> dict:
    meta = {"cwd": "", "model": "", "cli_version": "", "session_id": path.stem}
    first_user = ""
    message_count = 0
    tool_count = 0
    first_ts = None
    try:
        handle = path.open()
    except OSError:
        return {}
    with handle:
        for raw in handle:
            try:
                obj = json.loads(raw)
            except json.JSONDecodeError:
                continue
            if not first_ts and obj.get("timestamp"):
                first_ts = obj["timestamp"]
            payload = obj.get("payload") or {}
            if obj.get("type") == "session_meta":
                meta["cwd"] = payload.get("cwd") or meta["cwd"]
                meta["model"] = payload.get("model") or payload.get("model_provider") or meta["model"]
                meta["cli_version"] = payload.get("cli_version") or meta["cli_version"]
                meta["session_id"] = payload.get("id") or meta["session_id"]
            if obj.get("type") != "response_item":
                continue
            if payload.get("type") == "message":
                role = payload.get("role") or ""
                text = text_blocks(payload.get("content"))
                if role in {"user", "assistant"} and text and not is_noise(text):
                    message_count += 1
                if role == "user" and text and not first_user and not is_noise(text):
                    first_user = next((line.strip() for line in text.splitlines() if line.strip()), text).strip()
            elif payload.get("type") == "function_call":
                tool_count += 1
    cwd = meta["cwd"]
    project = Path(cwd).name.lower() if cwd else "general"
    return {
        **meta,
        "path": str(path),
        "project": project,
        "title": (first_user or "Codex session")[:200],
        "date": datetime.fromtimestamp(path.stat().st_mtime).strftime("%Y-%m-%d"),
        "message_count": message_count,
        "tool_count": tool_count,
        "first_ts": first_ts or "",
        "mtime": path.stat().st_mtime,
    }


items = []
for path in sessions_dir.glob("*/*/*/*.jsonl"):
    try:
        if path.stat().st_mtime < cutoff:
            continue
    except OSError:
        continue
    item = parse(path)
    if item:
        items.append(item)

items.sort(key=lambda item: item["mtime"], reverse=True)
by_project = defaultdict(list)
for item in items:
    by_project[item["project"]].append(item)

lines = [
    f"# Codex session catalog - last {days} days",
    f"_generated {datetime.now().strftime('%Y-%m-%d')} - source ~/.codex/sessions - read-only digest_",
    "",
    "Per project: recent Codex sessions, newest first, with opening goal and local JSONL path.",
    "Use this with ADOPT_FROM_HISTORY.md alongside Claude Code and claude.ai exports.",
    "",
]
for project in sorted(by_project, key=lambda name: by_project[name][0]["mtime"], reverse=True):
    group = by_project[project]
    lines.extend([f"## {project}", f"_{len(group)} session(s)_", ""])
    for item in group:
        lines.append(f"- **{item['date']}** `{item['session_id'][:8]}` - {item['title']}")
        if item["cwd"]:
            lines.append(f"  - cwd: `{item['cwd']}`")
        lines.append(f"  - messages: {item['message_count']} - tools: {item['tool_count']} - path: `{item['path']}`")
    lines.append("")
lines.extend(["---", f"_{len(items)} Codex sessions cataloged._"])
out.write_text("\n".join(lines) + "\n")
print(f"wrote {out} - {len(items)} Codex sessions across the last {days} days")
PY
