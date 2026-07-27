#!/usr/bin/env bash
set -uo pipefail

SESSION_PATH="${1:-}"
CWD_VALUE="${2:-}"
HOME_DIR="$HOME"
EXPORT_SCRIPT="$HOME_DIR/.codex/scripts/export_codex_session.py"
MEMORY_SCRIPT="$HOME_DIR/.codex/scripts/memory_sync_codex.py"
QMD_REFRESH="$HOME_DIR/.codex/scripts/codex_qmd_refresh.sh"
HOOKS_LOG="$HOME_DIR/vault/logs/hooks.jsonl"

mkdir -p "$(dirname "$HOOKS_LOG")"

log_hook() {
  local outcome="$1"
  local detail="${2:-}"
  printf '{"ts":"%s","hook":"codex-stop-worker","outcome":"%s","detail":"%s"}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$outcome" "$detail" >> "$HOOKS_LOG"
}

latest_session() {
  python3 - <<'PY'
from pathlib import Path
paths = sorted(Path.home().joinpath(".codex", "sessions").glob("*/*/*/*.jsonl"), key=lambda p: p.stat().st_mtime, reverse=True)
if paths:
    print(paths[0])
PY
}

if [ -z "$SESSION_PATH" ]; then
  SESSION_PATH="$(latest_session)"
fi

if [ -z "$SESSION_PATH" ] || [ ! -f "$SESSION_PATH" ]; then
  log_hook "skip" "no session file"
  exit 0
fi

SESSION_ID="$(basename "$SESSION_PATH" .jsonl)"

if [ -z "$CWD_VALUE" ]; then
  CWD_VALUE="$(python3 - "$SESSION_PATH" <<'PY'
import json, sys
from pathlib import Path
path = Path(sys.argv[1])
for line in path.open():
    try:
        obj = json.loads(line)
    except json.JSONDecodeError:
        continue
    if obj.get("type") == "session_meta":
        print(obj.get("payload", {}).get("cwd", ""))
        break
PY
)"
fi

if [ -x "$EXPORT_SCRIPT" ]; then
  "$EXPORT_SCRIPT" "$SESSION_PATH" >/dev/null 2>&1 || log_hook "warn" "export failed"
fi

if [ "${CODEX_HARNESS_MEMORY_SYNC:-0}" = "1" ] && [ -x "$MEMORY_SCRIPT" ]; then
  python3 - "$SESSION_ID" "$SESSION_PATH" "$CWD_VALUE" <<'PY' | "$MEMORY_SCRIPT" >/dev/null 2>&1 || log_hook "warn" "memory sync failed"
import json, sys
print(json.dumps({"session_id": sys.argv[1], "session_path": sys.argv[2], "cwd": sys.argv[3]}))
PY
fi

if [ -x "$QMD_REFRESH" ]; then
  "$QMD_REFRESH" >/dev/null 2>&1 || true
fi

log_hook "ok" "$SESSION_ID"
exit 0
