#!/usr/bin/env bash
# read-codex-session.sh - print one Codex session's user/assistant prose, stripping tool noise.
# READ-ONLY.
#   Usage: ./read-codex-session.sh <session-id | /path/to.jsonl> [maxchars-per-message]
set -uo pipefail

ARG="${1:?session id (8+ chars) or path to a .jsonl}"
CAP="${2:-1500}"
SESSIONS="$HOME/.codex/sessions"
FILE="$ARG"

if [ ! -f "$FILE" ]; then
  FILE="$(find "$SESSIONS" -name "${ARG}*.jsonl" 2>/dev/null | head -1)"
fi
if [ ! -f "$FILE" ]; then
  FILE="$(find "$SESSIONS" -name "*${ARG}*.jsonl" 2>/dev/null | head -1)"
fi
if [ ! -f "$FILE" ]; then
  FILE="$(python3 - "$SESSIONS" "$ARG" <<'PY'
from __future__ import annotations

import json
import sys
from pathlib import Path

sessions = Path(sys.argv[1]).expanduser()
prefix = sys.argv[2]
matches = []
for path in sorted(sessions.glob("*/*/*/*.jsonl"), key=lambda p: p.stat().st_mtime, reverse=True):
    try:
        handle = path.open()
    except OSError:
        continue
    with handle:
        for raw in handle:
            try:
                obj = json.loads(raw)
            except json.JSONDecodeError:
                continue
            if obj.get("type") != "session_meta":
                continue
            session_id = str((obj.get("payload") or {}).get("id") or "")
            if session_id.startswith(prefix):
                matches.append(str(path))
            break
    if matches:
        break
print(matches[0] if matches else "")
PY
)"
fi
[ -f "$FILE" ] || { echo "Codex session not found: $ARG"; exit 1; }

python3 - "$FILE" "$CAP" <<'PY'
from __future__ import annotations

import json
import sys
from datetime import datetime
from pathlib import Path

path = Path(sys.argv[1]).expanduser()
cap = int(sys.argv[2])

NOISE = (
    "Use this warm-start brief as background context",
    "Warm-start brief:",
    "# Project Intelligence (auto-generated)",
    "Skill Suggestions (auto-detected)",
    "<recommended_plugins>",
    "# AGENTS.md instructions",
    "<environment_context>",
    "<permissions instructions>",
    "[external_agent_tool_call",
    "[external_agent_tool_result",
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
    return "\n\n".join(parts).strip()


def clean(text: str) -> str:
    stripped = text.lstrip()
    if any(stripped.startswith(marker) or marker in stripped[:500] for marker in NOISE):
        return ""
    return text[:cap]


date = datetime.fromtimestamp(path.stat().st_mtime).strftime("%Y-%m-%d")
print(f"# Codex session {path.stem} - {date}")
print()

with path.open() as handle:
    for raw in handle:
        try:
            obj = json.loads(raw)
        except json.JSONDecodeError:
            continue
        if obj.get("type") != "response_item":
            continue
        payload = obj.get("payload") or {}
        if payload.get("type") != "message":
            continue
        role = payload.get("role") or "message"
        if role not in {"user", "assistant"}:
            continue
        text = clean(text_blocks(payload.get("content")))
        if not text:
            continue
        label = "USER" if role == "user" else "ASSISTANT" if role == "assistant" else role.upper()
        print(f"{label}: {text}")
        print()
PY
