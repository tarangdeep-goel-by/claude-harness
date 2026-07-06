#!/bin/bash
# Claude Code PreCompact hook: preserve state BEFORE compaction truncates it.
#
# Two layers (both non-blocking, exit 0):
#   1. export-session.py --precompact → full transcript .md in ~/vault/sessions/ (the bytes).
#   2. state snapshot → deterministic .md (git working tree + active goal) alongside it.
#      The transcript export already captures files-touched/tokens; the snapshot captures the
#      ENVIRONMENT state it doesn't (branch, uncommitted changes, last user prompts) — the
#      resume point a post-compact continuation or future /recall needs. No GLM (keeps the hot
#      path free + non-blocking-guaranteed); the rich synthesis stays vault-push's job at end.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EXPORT_SCRIPT="$SCRIPT_DIR/export-session.py"
PROJECTS_BASE="$HOME/.claude/projects"
HOOKS_LOG="$HOME/vault/logs/hooks.jsonl"
SNAPSHOT_ERR="$HOME/vault/logs/precompact.log"
START_TS=$(date +%s)

mkdir -p "$(dirname "$HOOKS_LOG")" "$(dirname "$SNAPSHOT_ERR")"

hook_log() {
  local outcome="$1" detail="${2:-}"
  local dur=$(( $(date +%s) - START_TS ))
  printf '{"ts":"%s","hook":"precompact","session":"%s","cwd":"%s","outcome":"%s","detail":"%s","duration_s":%d}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${SESSION_ID:-unknown}" "${SESSION_CWD:-}" "$outcome" "$detail" "$dur" >> "$HOOKS_LOG"
}

INPUT=$(cat)

SESSION_ID=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('session_id',''))" 2>/dev/null || true)
SESSION_CWD=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('cwd',''))" 2>/dev/null || true)

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

# Deterministic state snapshot: git working tree + recent user prompts. Args:
#   $1 jsonl, $2 session_id, $3 cwd, $4 transcript-export path (may be empty).
# Prints the snapshot path on stdout; never exits nonzero (best-effort).
write_state_snapshot() {
  local jsonl="$1" sid="$2" cwd="$3" transcript="${4:-}"
  [ -z "$jsonl" ] && return 0
  MS_JSONL="$jsonl" MS_SID="$sid" MS_CWD="$cwd" MS_TRANSCRIPT="$transcript" \
  MS_TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)" MS_DATE="$(date +%F)" MS_HHMMSS="$(date +%H%M%S)" \
    python3 - <<'PY' 2>>"$SNAPSHOT_ERR" || return 0
import os, sys, json, subprocess

jsonl     = os.environ["MS_JSONL"]
sid       = os.environ["MS_SID"]
cwd       = os.environ["MS_CWD"]
ts        = os.environ["MS_TS"]
date      = os.environ["MS_DATE"]
hhmmss    = os.environ["MS_HHMMSS"]
transcript= os.environ["MS_TRANSCRIPT"]
sessions  = os.path.expanduser("~/vault/sessions")
sid8      = (sid or "unknown")[:8]

# --- recent user prompts (skip tool_result/system noise) ---
prompts = []
try:
    with open(jsonl) as f:
        for line in f:
            try: d = json.loads(line)
            except Exception: continue
            if d.get("type") != "user": continue
            content = (d.get("message") or {}).get("content")
            text = ""
            if isinstance(content, str): text = content
            elif isinstance(content, list):
                for b in content:
                    if isinstance(b, dict) and b.get("type") == "text":
                        text += b.get("text", "")
            text = text.strip()
            # Skip CC-injected noise posed as user turns: tool_result payloads, slash-command/
            # skill-body expansions (<command-…>, "Base directory for this skill"), and the
            # compaction summary injected at the start of a post-compact window.
            NOISE = ("This session is being continued", "Base directory for this skill")
            if (text and not text.startswith("<") and "tool_result" not in text
                    and not any(text.startswith(p) for p in NOISE)):
                prompts.append(text)
    prompts = prompts[-3:]
except Exception:
    pass

def short(s, n=200):
    s = s.replace("\n", " ").strip()
    return s[:n] + ("…" if len(s) > n else "")

# --- git state (best-effort; cwd may not be a repo) ---
def git(args):
    try:
        r = subprocess.run(["git", "-C", cwd] + args, capture_output=True, text=True, timeout=3)
        return r.stdout.strip() if r.returncode == 0 else ""
    except Exception:
        return ""

branch      = git(["rev-parse", "--abbrev-ref", "HEAD"])
last_commit = git(["log", "-1", "--oneline"])
status      = [l for l in git(["status", "--short"]).splitlines() if l.strip()][:15]
project     = os.path.basename(cwd.rstrip("/")) or "unknown"

out = []
out.append("---")
out.append("session_id: " + sid)
out.append("compacted_at: " + ts)
out.append("project: " + project)
out.append("cwd: " + cwd)
if branch:      out.append("branch: " + branch)
if last_commit: out.append("last_commit: " + last_commit)
if transcript:  out.append("transcript: " + transcript)
out.append("type: precompact-state")
out.append("---")
out.append("")
out.append("# Pre-compact state snapshot — " + project)
out.append("")
out.append("Auto-written by the PreCompact hook (deterministic; no GLM). Captures the ENVIRONMENT")
out.append("state the transcript export omits — git working tree + active goal. Full conversation")
out.append("lives in the linked transcript; the curated session-end handoff in `System/handoffs/`.")
out.append("")
out.append("## Active goal (recent user prompts)")
if prompts:
    for p in prompts: out.append("- " + short(p, 200))
else:
    out.append("- (no user prompts recovered)")
out.append("")
out.append("## Git state")
if branch:
    out.append("- branch: `" + branch + "`")
    out.append("- last commit: " + last_commit)
    if status:
        out.append("- working tree:")
        for s in status: out.append("  - `" + s + "`")
    else:
        out.append("- working tree: clean")
else:
    out.append("- (not a git repo or git unavailable)")
out.append("")
out.append("## Resume")
out.append("- Full transcript: " + (transcript or "(not exported)"))
out.append("- cwd: `" + cwd + "`")
out.append("")

os.makedirs(sessions, exist_ok=True)
path = os.path.join(sessions, date + "_precompact_" + sid8 + "_" + hhmmss + ".md")
with open(path, "w") as f:
    f.write("\n".join(out))
print(path)
PY
}

JSONL=$(find_jsonl)
if [ -n "$JSONL" ]; then
  EXPORT_OUT=$(python3 "$EXPORT_SCRIPT" "$JSONL" --precompact 2>/dev/null || true)
  EXPORT_PATH=$(printf '%s\n' "$EXPORT_OUT" | sed -n 's/^Exported: //p' | tail -1)
  hook_log "ok" "precompact snapshot $(basename "$JSONL")"
  SNAP_PATH=$(write_state_snapshot "$JSONL" "$SESSION_ID" "$SESSION_CWD" "$EXPORT_PATH" || true)
  if [ -n "$SNAP_PATH" ]; then
    hook_log "ok" "state-snapshot $(basename "$SNAP_PATH")"
  else
    hook_log "skip" "state-snapshot not written"
  fi
else
  hook_log "skip" "no jsonl found"
fi

if command -v qmd &>/dev/null; then
  qmd update >/dev/null 2>&1 || true
  qmd embed >/dev/null 2>&1 || true
  hook_log "ok" "qmd indexed"
else
  hook_log "skip" "qmd not found"
fi
