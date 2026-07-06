#!/bin/bash
# PostToolUse Read hook: track when memory files are consulted (utilization signal).
# Non-blocking. Runtime budget < 50ms.
#
# Captures explicit Read-tool consults of files under the memory dir →
# ~/vault/logs/memory-consulted.json  {<relpath>: {count, last_seen}}.
#
# LIMITATION (intended): captures Read-tool access only. Does NOT capture
# warm-start index injection (MEMORY.md is always loaded; a memory is
# "consulted" when its full body is pulled) or cat-via-Bash reads. A
# separate "delivered-to-context" signal is a future enhancement.
set -uo pipefail

MEMORY_DIR="/Users/tarang/.claude/projects/-Users-tarang-Documents-Projects/memory"
STATE="$HOME/vault/logs/memory-consulted.json"
HOOKS_LOG="$HOME/vault/logs/hooks.jsonl"
mkdir -p "$(dirname "$STATE")" "$(dirname "$HOOKS_LOG")" 2>/dev/null || true

START_MS=$(python3 -c 'import time;print(int(time.time()*1000))' 2>/dev/null || date +%s)

INPUT=$(cat 2>/dev/null || echo '{}')

# Extract the read file_path as a path relative to MEMORY_DIR (if under it).
REL=$(printf '%s' "$INPUT" | python3 -c '
import sys, json, os
mem = os.path.realpath(sys.argv[1])
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
fp = (d.get("tool_input") or {}).get("file_path") or ""
if not fp:
    sys.exit(0)
rp = os.path.realpath(fp)
rel = os.path.relpath(rp, mem)
if rel == "." or rel.startswith(".."):
    sys.exit(0)
if not rel.lower().endswith(".md"):
    sys.exit(0)
print(rel)
' "$MEMORY_DIR" 2>/dev/null || true)

if [ -n "$REL" ]; then
  MS_STATE="$STATE" MS_REL="$REL" python3 - <<'PY' 2>/dev/null || true
import os, json, time
path = os.environ["MS_STATE"]
rel  = os.environ["MS_REL"]
now  = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
try:
    with open(path) as f:
        data = json.load(f)
except Exception:
    data = {}
if not isinstance(data, dict):
    data = {}
e = data.get(rel, {"count": 0, "last_seen": None})
e["count"] = int(e.get("count", 0)) + 1
e["last_seen"] = now
data[rel] = e
tmp = path + ".tmp"
with open(tmp, "w") as f:
    json.dump(data, f, indent=2, sort_keys=True)
os.replace(tmp, path)
PY
  DETAIL="incremented:$REL"
else
  DETAIL="skip"
fi

END_MS=$(python3 -c 'import time;print(int(time.time()*1000))' 2>/dev/null || date +%s)
DUR_MS=$((END_MS - START_MS))
[ "$DUR_MS" -lt 0 ] && DUR_MS=0
DUR_S=$(python3 -c "print(round($DUR_MS/1000.0, 3))" 2>/dev/null || echo "0")

printf '{"ts":"%s","hook":"memory-consulted","outcome":"ok","detail":"%s","duration_s":%s}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$DETAIL" "$DUR_S" >> "$HOOKS_LOG" 2>/dev/null || true

exit 0
