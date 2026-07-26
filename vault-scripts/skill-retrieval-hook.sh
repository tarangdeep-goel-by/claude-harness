#!/bin/bash
# UserPromptSubmit hook: semantic skill retrieval at task-start.
#
# Runs qmd top-k retrieval of skill `description`s against the user's prompt and injects the
# matches as additionalContext — so the model loads the right skill before answering. Especially
# helps GLM, which under-triggers skills. Observe-only: always allows the prompt (exit 0); only
# ADDS context. Silent when nothing clears the score threshold (no noise on irrelevant prompts).
#
# Depends on the `skills` qmd collection, built/refreshed by vault-scripts/build-skill-index.sh
# (install.sh + warm-start keep it fresh). If qmd or the collection is absent, the hook no-ops.
set -uo pipefail

# Pause sentinel: if present, no-op immediately. Used while `qmd embed` runs, to keep this
# hook's queries from contending with the embedder for the local GGUF model session (which
# otherwise surfaces as SessionReleasedError on one side or the other).
[ -f "${HOME}/.cache/qmd/.skill-hook-paused" ] && exit 0

INPUT=$(cat 2>/dev/null || echo '{}')

# Extract the prompt (skip cleanly if the payload isn't JSON).
PROMPT=$(printf '%s' "$INPUT" | python3 -c "import sys,json
try: print(json.load(sys.stdin).get('prompt',''))
except Exception: sys.exit(0)" 2>/dev/null || true)
[ -z "$PROMPT" ] && exit 0

# Skip slash commands — the user is already invoking a skill explicitly.
case "$PROMPT" in /*) exit 0 ;; esac

# Skip short prompts (<5 words) — not enough signal to retrieve against.
words=$(printf '%s' "$PROMPT" | wc -w | tr -d ' ')
[ "$words" -lt 5 ] && exit 0

# Skip meta-discussion ABOUT skills/hooks/infra (talking about the machinery, not doing the work).
printf '%s' "$PROMPT" | grep -qiE 'skill|hook|route|routing|invoke|trigger' && exit 0

# Need qmd + the skills collection, else no-op (graceful degradation).
command -v qmd >/dev/null 2>&1 || exit 0
qmd collection list 2>/dev/null | grep -qiE '^skills\b' || exit 0

MIN_SCORE="${SKILL_RETRIEVAL_MIN_SCORE:-0.5}"

# Detect a timeout binary (GNU `timeout` or macOS `gtimeout`); empty if neither available.
TIMEOUT_BIN=""
command -v timeout  >/dev/null 2>&1 && TIMEOUT_BIN=timeout
[ -z "$TIMEOUT_BIN" ] && command -v gtimeout >/dev/null 2>&1 && TIMEOUT_BIN=gtimeout

# Top-k retrieval (hybrid BM25 + vector + rerank). Threshold filtering is done in python below
# (qmd's --min-score filters on a different/internal score and behaves inconsistently — trust the
# rerank `score` field in the JSON, which the python checks against MIN_SCORE).
# stderr discarded (qmd progress chatter); the sed cuts any preamble before the JSON array.
# Internal cap (3s) sits below the harness hook timeout (10s) so a slow qmd exits cleanly as a
# silent no-op here, instead of being killed by the outer harness timeout (which surfaces as a
# noisy "hook timed out" error). Graceful degradation: skill suggestions no-op while qmd is slow.
RAW=$(${TIMEOUT_BIN:+$TIMEOUT_BIN 3} qmd query "$PROMPT" -c skills -n 3 --json 2>/dev/null || true)
[ -z "$RAW" ] && exit 0
JSON=$(printf '%s' "$RAW" | sed -n '/^[[:space:]]*\[/,$p' | head -c 20000)
[ -z "$JSON" ] && exit 0

# Parse, derive skill name from the file path, keep score >= MIN_SCORE, format the message.
# JSON goes via env (not stdin — `python3 -` already reads the script from stdin via the heredoc).
MSG=$(SKILL_JSON="$JSON" MIN_SCORE="$MIN_SCORE" python3 - <<'PY' 2>/dev/null
import sys, os, json, re
min_score = float(os.environ.get("MIN_SCORE", "0.5"))
try:
    hits = json.loads(os.environ.get("SKILL_JSON", ""))
except Exception:
    sys.exit(0)
if not isinstance(hits, list):
    sys.exit(0)
lines = []
for h in hits:
    if not isinstance(h, dict):
        continue
    try:
        score = float(h.get("score", 0))
    except Exception:
        score = 0.0
    if score < min_score:
        continue
    # file looks like qmd://skills/<name>.md (collection rooted at the staging dir).
    f = h.get("file", "")
    m = re.search(r'(?:^|/)skills/([^/]+?)\.md(?:$|[?#])', f) or re.search(r'/([^/]+)\.md$', f)
    name = (m.group(1) if m else "").strip()
    if not name:
        continue
    # description hint: snippet (strip any @@ line-range prefix), else title, else context.
    snip = re.sub(r'^@@[^@]*@@\s*', '', h.get("snippet", "")).strip()
    desc = re.sub(r'\s+', ' ', snip or h.get("title", "") or h.get("context", "")).strip()
    if len(desc) > 140:
        desc = desc[:137] + "…"
    lines.append(f"- /{name} — {desc}  (score {score:.2f})")
if not lines:
    sys.exit(0)
print("## Skill match — consider loading the relevant skill(s) BEFORE answering:\n" + "\n".join(lines))
PY
)

[ -z "$MSG" ] && exit 0

# Inject as additionalContext (the UserPromptSubmit contract).
printf '%s' "$MSG" | python3 -c "import json,sys
print(json.dumps({'hookSpecificOutput':{'hookEventName':'UserPromptSubmit','additionalContext':sys.stdin.read()}}))" 2>/dev/null || true

# Best-effort outcome log (non-blocking).
LOG="$HOME/vault/logs/hooks.jsonl"
if [ -d "$(dirname "$LOG")" ]; then
  n=$(printf '%s' "$MSG" | grep -c '^- /' || true)
  printf '{"ts":"%s","hook":"skill-retrieval","outcome":"ok","matches":%s}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${n:-0}" >> "$LOG" 2>/dev/null || true
fi
exit 0
