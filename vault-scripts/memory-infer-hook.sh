#!/usr/bin/env bash
# Memory-infer hook (Claude Code Stop): at session end, call glm-4.7 to infer
# DURABLE facts about how the user works. Appends candidate memories to a review
# queue consumed by `/reflect memory`.
#
# NON-BLOCKING: every failure path exits 0 after logging. Never blocks a session.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECTS_BASE="$HOME/.claude/projects"
QUEUE_FILE="$HOME/vault/memory-review-queue.jsonl"
HOOKS_LOG="$HOME/vault/logs/hooks.jsonl"
INFER_LOG="$HOME/vault/logs/memory-infer.log"
# Default memory dir (used when cwd-derived path is missing); this is the
# canonical memory location for the Projects umbrella on this harness.
MEMORY_DIR_DEFAULT="$PROJECTS_BASE/-Users-tarang-Documents-Projects/memory"
START_TS=$(date +%s)

mkdir -p "$(dirname "$HOOKS_LOG")" "$(dirname "$INFER_LOG")" "$(dirname "$QUEUE_FILE")"

SESSION_ID=""
SESSION_CWD=""

# ---------- helpers ----------

# Logs to the unified hooks.jsonl (same schema as session-export/precompact).
hook_log() {
  local outcome="$1" detail="${2:-}"
  local dur=$(( $(date +%s) - START_TS ))
  printf '{"ts":"%s","hook":"memory-infer","session":"%s","outcome":"%s","detail":"%s","duration_s":%d}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${SESSION_ID:-selftest}" "$outcome" "$detail" "$dur" >> "$HOOKS_LOG"
}

# Hook-specific log for skip/debug detail.
infer_log() {
  printf '{"ts":"%s","session":"%s","outcome":"%s","detail":"%s"}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${SESSION_ID:-selftest}" "$1" "${2:-}" >> "$INFER_LOG"
}

# find_jsonl — copied VERBATIM from precompact-hook.sh (with SESSION_* referenced
# as globals, matching that script's contract).
find_jsonl() {
  if [ -n "$SESSION_CWD" ] && [ -n "$SESSION_ID" ]; then
    DERIVED_DIR="$PROJECTS_BASE/$(echo "$SESSION_CWD" | tr '/' '-')"
    JSONL_PATH="$DERIVED_DIR/$SESSION_ID.jsonl"
    if [ -f "$JSONL_PATH" ]; then echo "$JSONL_PATH"; return; fi
  fi
  if [ -n "$SESSION_ID" ]; then
    FOUND=$(find "$PROJECTS_BASE" -name "$SESSION_ID.jsonl" -type f 2>/dev/null | head -1)
    if [ -n "$FOUND" ]; then echo "$FOUND"; return; fi
  fi
  LATEST=$(find "$PROJECTS_BASE" -name "*.jsonl" -type f -not -path "*/subagents/*" -newer "$PROJECTS_BASE" 2>/dev/null | xargs ls -t 2>/dev/null | head -1)
  if [ -n "$LATEST" ]; then echo "$LATEST"; fi
}

# Build the existing-memories seed list from a memory dir. Reads up to 6 lines
# per file, pulls name+description. Emits one "- name: description" line each.
build_existing_memories() {
  local mdir="${1:-}"
  python3 - "$mdir" <<'PY'
import sys, os, glob
mdir = sys.argv[1] if len(sys.argv) > 1 and sys.argv[1] else ""
items = []
if mdir and os.path.isdir(mdir):
    for p in sorted(glob.glob(os.path.join(mdir, "*.md"))):
        base = os.path.basename(p)
        if base == "MEMORY.md" or base.startswith("AGENTS"):
            continue
        try:
            with open(p) as f:
                head = [next(f, "") for _ in range(6)]
            txt = "".join(head)
            if not txt.startswith("---"):
                continue
            name, desc = "", ""
            for line in txt.splitlines():
                if line.startswith("name:") and not name:
                    name = line.split(":", 1)[1].strip()
                elif line.startswith("description:") and not desc:
                    desc = line.split(":", 1)[1].strip().strip('"').strip("'")
            if name:
                items.append(f"- {name}: {desc}")
        except Exception:
            continue
print("\n".join(items[:40]))
PY
}

# Build transcript digest from a jsonl: last ~20 user/assistant turns, role+text,
# tool results truncated to one line, capped at ~6000 chars. Also returns count.
build_digest() {
  local jsonl_path="${1:-}"
  python3 - "$jsonl_path" <<'PY'
import sys, json
path = sys.argv[1] if len(sys.argv) > 1 else ""
turns, user_count = [], 0
if path:
    try:
        with open(path) as f:
            for line in f:
                try:
                    d = json.loads(line)
                except Exception:
                    continue
                if d.get("type") not in ("user", "assistant"):
                    continue
                msg = d.get("message") or {}
                role = msg.get("role") or d.get("type")
                if role == "user":
                    user_count += 1
                content = msg.get("content")
                bits = []
                if isinstance(content, str):
                    bits.append(content)
                elif isinstance(content, list):
                    for block in content:
                        if not isinstance(block, dict):
                            continue
                        bt = block.get("type")
                        if bt == "text":
                            bits.append(block.get("text", ""))
                        elif bt == "tool_use":
                            bits.append(f"[tool_use:{block.get('name','tool')}]")
                        elif bt == "tool_result":
                            c = block.get("content", "")
                            if isinstance(c, list):
                                c = " ".join(
                                    b.get("text", "") if isinstance(b, dict) else str(b)
                                    for b in c
                                )
                            first = str(c).split("\n", 1)[0][:200]
                            bits.append(f"[tool_result] {first}")
                text = " ".join(t for t in bits if t).strip()
                if text:
                    turns.append(f"{'USER' if role == 'user' else 'ASSISTANT'}: {text}")
    except Exception:
        pass
digest = "\n".join(turns[-20:])
if len(digest) > 6000:
    digest = digest[:6000]
print(json.dumps({"user_turns": user_count, "digest": digest}))
PY
}

# Call glm-4.7 via the z.ai anthropic-compatible endpoint. Writes raw response to
# the path in $1. Returns curl exit code.
call_glm() {
  local out_path="$1" sys_prompt="$2" user_prompt="$3"
  local payload key
  payload=$(python3 - "$sys_prompt" "$user_prompt" <<'PY'
import json, sys
print(json.dumps({
    "model": "glm-4.7",
    "max_tokens": 1024,
    "system": sys.argv[1],
    "messages": [{"role": "user", "content": sys.argv[2]}],
}))
PY
)
  if [ ! -f "$HOME/.config/claude-glm/key" ]; then
    echo '{"error":"missing-key"}' > "$out_path"
    return 1
  fi
  key=$(tr -d '[:space:]' < "$HOME/.config/claude-glm/key")
  curl -sS --max-time 45 \
    -H "Authorization: Bearer $key" \
    -H "anthropic-version: 2023-06-01" \
    -H "content-type: application/json" \
    -d "$payload" \
    https://api.z.ai/api/anthropic/v1/messages > "$out_path" 2>&1
}

# Parse glm response from $1 and append candidates to the queue. Args:
#   $1 raw response file, $2 queue file, $3 session id, $4 project, $5 ts.
# Prints appended count on stdout; errors go to stderr (never exits nonzero).
parse_and_append() {
  local raw_path="$1" queue="$2" sid="$3" proj="$4" ts="$5"
  python3 - "$raw_path" "$queue" "$sid" "$proj" "$ts" <<'PY'
import sys, json, re
raw_path, queue, sid, proj, ts = sys.argv[1:6]
count = 0
try:
    raw = open(raw_path).read()
    d = json.loads(raw)
    if isinstance(d, dict) and d.get("error") and not d.get("content"):
        sys.stderr.write(f"api-error: {d.get('error')}\n")
        sys.exit(0)
    txt = d["content"][0]["text"]
    # Strip ```json fences if present.
    s = txt.strip()
    s = re.sub(r"^\s*```(?:json)?\s*", "", s, flags=re.IGNORECASE)
    s = re.sub(r"\s*```\s*$", "", s).strip()
    parsed = json.loads(s)
    cands = parsed.get("candidates", []) if isinstance(parsed, dict) else []
    with open(queue, "a") as f:
        for c in cands:
            if not isinstance(c, dict):
                continue
            entry = {
                "ts": ts,
                "session_id": sid,
                "project": proj,
                "kind": "memory_candidate",
                "type": c.get("type", "user"),
                "name": c.get("name", ""),
                "description": c.get("description", ""),
                "body": c.get("body", ""),
                "confidence": c.get("confidence", "low"),
                "source": "memory-infer-hook",
                "status": "pending",
            }
            f.write(json.dumps(entry) + "\n")
            count += 1
except Exception as e:
    sys.stderr.write(f"parse-error: {e}\n")
print(count)
PY
}

# Print parsed candidates from a raw response file (for selftest display).
show_parsed() {
  python3 - "$1" <<'PY'
import sys, json, re
raw = open(sys.argv[1]).read()
try:
    d = json.loads(raw)
    if isinstance(d, dict) and d.get("error") and not d.get("content"):
        print(f"[api-error] {d.get('error')}")
        print("[]")
        sys.exit(0)
    txt = d["content"][0]["text"]
    s = txt.strip()
    s = re.sub(r"^\s*```(?:json)?\s*", "", s, flags=re.IGNORECASE)
    s = re.sub(r"\s*```\s*$", "", s).strip()
    parsed = json.loads(s)
    cands = parsed.get("candidates", []) if isinstance(parsed, dict) else []
    print(json.dumps(cands, indent=2, ensure_ascii=False))
except Exception as e:
    print(f"[parse-error] {e}")
    print("[]")
PY
}

SYS_PROMPT='You infer DURABLE facts about how Tarang works, prefers, and decides — NOT ephemeral task details. Given a session transcript digest and his existing-memory list, output ONLY strict JSON: {"candidates":[{"type":...,"name":...,"description":...,"body":...,"confidence":...}]}. type ∈ user|feedback|project. name = kebab-slug. description = one line. body = concrete fact (1-3 sentences). confidence ∈ high|medium|low. If nothing durable+novel, return {"candidates":[]}. Never echo session text verbatim.'

# ---------- selftest branch ----------

if [ "${1:-}" = "selftest" ]; then
  SESSION_ID="selftest"
  SESSION_CWD="/Users/tarang/Documents/Projects/claude-harness"
  echo "[selftest] mode — canned digest, no stdin/guards"
  CANNED_DIGEST='USER: implement the foo() function in service.py
ASSISTANT: I will create foo() using the pymongo driver.
USER: no — always prefer motor (async) over pymongo in this repo; it is an async codebase
ASSISTANT: got it, switching to motor.
USER: also run prettier on save, that is a hard rule here
ASSISTANT: configured prettier-on-save in the workspace settings.
USER: before opening a PR run /verify, never skip it
ASSISTANT: acknowledged — /verify is mandatory pre-PR.'

  EXISTING=$(build_existing_memories "$MEMORY_DIR_DEFAULT")
  echo "[selftest] existing memories seeded: $(echo "$EXISTING" | grep -c '^-' || true)"

  USER_PROMPT="EXISTING MEMORIES:
$EXISTING

TRANSCRIPT DIGEST:
$CANNED_DIGEST"

  TMP=$(mktemp -t meminfer)
  trap 'rm -f "$TMP"' EXIT
  echo "[selftest] calling glm-4.7 ..."
  T0=$(date +%s)
  call_glm "$TMP" "$SYS_PROMPT" "$USER_PROMPT" || echo "[selftest] curl returned nonzero (continuing)"
  T1=$(date +%s)
  echo "[selftest] latency: $((T1 - T0))s"
  echo "[selftest] RAW RESPONSE:"
  cat "$TMP"
  echo ""
  echo "[selftest] PARSED CANDIDATES:"
  show_parsed "$TMP"
  hook_log "ok" "selftest"
  rm -f "$TMP"
  trap - EXIT
  exit 0
fi

# ---------- normal hook branch ----------

INPUT=$(cat)

SESSION_ID=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('session_id',''))" 2>/dev/null || true)
SESSION_CWD=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('cwd',''))" 2>/dev/null || true)
STOP_HOOK_ACTIVE=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('stop_hook_active',''))" 2>/dev/null || true)

# Guard: prevent re-entrant loop when CC's own stop-hook firing fires us again.
if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
  hook_log "skip" "stop_hook_active"
  exit 0
fi

JSONL=$(find_jsonl)
if [ -z "$JSONL" ]; then
  infer_log "skip:no-transcript" ""
  hook_log "skip" "no-transcript"
  exit 0
fi

DIGEST_JSON=$(build_digest "$JSONL")
USER_TURNS=$(echo "$DIGEST_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('user_turns',0))" 2>/dev/null || echo 0)
DIGEST=$(echo "$DIGEST_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('digest',''))" 2>/dev/null || echo "")

if [ "${USER_TURNS:-0}" -lt 12 ]; then
  infer_log "skip:ephemeral" "user_turns=$USER_TURNS"
  hook_log "skip" "ephemeral user_turns=$USER_TURNS"
  exit 0
fi

# Derive memory dir from cwd; fall back to the canonical default.
MEMORY_DIR=""
if [ -n "$SESSION_CWD" ]; then
  MEMORY_DIR="$PROJECTS_BASE/$(echo "$SESSION_CWD" | tr '/' '-')/memory"
fi
if [ -z "$MEMORY_DIR" ] || [ ! -d "$MEMORY_DIR" ]; then
  MEMORY_DIR="$MEMORY_DIR_DEFAULT"
fi

EXISTING=$(build_existing_memories "$MEMORY_DIR")
USER_PROMPT="EXISTING MEMORIES:
$EXISTING

TRANSCRIPT DIGEST:
$DIGEST"

TMP=$(mktemp -t meminfer)
trap 'rm -f "$TMP"' EXIT
if ! call_glm "$TMP" "$SYS_PROMPT" "$USER_PROMPT"; then
  infer_log "error:curl" "$(head -c 200 "$TMP" 2>/dev/null | tr '\n' ' ')"
  hook_log "error" "glm=err curl-failed"
  rm -f "$TMP"
  trap - EXIT
  exit 0
fi

PROJECT_NAME="$(basename "${SESSION_CWD:-unknown}")"
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
APPEND_COUNT=$(parse_and_append "$TMP" "$QUEUE_FILE" "$SESSION_ID" "$PROJECT_NAME" "$TS" 2>/tmp/meminfer-err)
APPEND_COUNT="${APPEND_COUNT:-0}"
# Classify GLM outcome so hook-health can separate real errors from genuine empties:
#   err = api/parse error surfaced on stderr; empty = model returned no durable facts; ok = N appended.
ERR_DETAIL="$(head -c 200 /tmp/meminfer-err 2>/dev/null | tr '\n' ' ')"
if [ -n "$ERR_DETAIL" ]; then
  infer_log "error:glm" "$ERR_DETAIL"
  hook_log "error" "glm=err appended=0"
elif [ "$APPEND_COUNT" = "0" ]; then
  hook_log "ok" "glm=empty appended=0"
else
  hook_log "ok" "glm=ok appended=$APPEND_COUNT"
fi
rm -f "$TMP"
trap - EXIT
exit 0
