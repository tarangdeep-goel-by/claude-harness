#!/bin/bash
# SessionStart hook: flag stale + overlapping memory files for review.
# Non-blocking, debounced. Runtime budget < 3s.
#
# Contract:
#   - Scan memory/*.md (skip legacy/, MEMORY.md, SCHEMA.md, dotfiles). Cap 150 files.
#   - STALENESS: confidence==high AND age>90 (age = today - last_verified).
#     (Files without last_verified are pre-migration/untracked, NOT stale — they
#     skip staleness but are still checked for OVERLAP. The write-time validator
#     and the S3 migration backfill last_verified going forward.)
#   - OVERLAP: Jaccard > 0.5 over name+description tokens → flag both.
#   - Append ONE json line per flag to ~/vault/memory-review-queue.jsonl.
#   - Debounce per slug via ~/vault/logs/memory-staleness-state.json (7-day window,
#     prune entries >30d old).
#   - Log run to ~/vault/logs/hooks.jsonl. Always exit 0.
set -uo pipefail

# MEMORY_DIR derived below from the session cwd (portable — no hardcoded path).
QUEUE="$HOME/vault/memory-review-queue.jsonl"
STATE="$HOME/vault/logs/memory-staleness-state.json"
HOOKS_LOG="$HOME/vault/logs/hooks.jsonl"
ERR_LOG="$HOME/vault/logs/memory-staleness.log"

mkdir -p "$(dirname "$QUEUE")" "$(dirname "$STATE")" "$(dirname "$HOOKS_LOG")" "$(dirname "$ERR_LOG")" 2>/dev/null || true
[ -f "$QUEUE" ] || : > "$QUEUE"

START_MS=$(python3 -c 'import time;print(int(time.time()*1000))' 2>/dev/null || date +%s)

INPUT=$(cat 2>/dev/null || echo '{}')

PROJECT=$(printf '%s' "$INPUT" | python3 -c '
import sys, json, os
try:
    d = json.load(sys.stdin)
except Exception:
    raise SystemExit(0)
cwd = d.get("cwd", "") or ""
print(os.path.basename(cwd.rstrip("/")) or "unknown")
' 2>/dev/null || echo "unknown")

# Memory dir is project-scoped, derived from the session cwd (portable — matches Claude Code's
# per-project memory layout). Guard: no dir → log skip + exit 0 (avoids a root-level glob).
PROJECTS_BASE="$HOME/.claude/projects"
SESSION_CWD="$(printf '%s' "$INPUT" | python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('cwd',''))" 2>/dev/null || true)"
if [ -n "$SESSION_CWD" ]; then
  MEMORY_DIR="$PROJECTS_BASE/$(echo "$SESSION_CWD" | tr '/' '-')/memory"
else
  MEMORY_DIR=""
fi
if [ ! -d "$MEMORY_DIR" ]; then
  printf '{"ts":"%s","hook":"memory-staleness","outcome":"skip","detail":"no-memory-dir"}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$HOOKS_LOG" 2>/dev/null || true
  exit 0
fi

MS_MEMORY_DIR="$MEMORY_DIR" \
MS_QUEUE="$QUEUE" \
MS_STATE="$STATE" \
MS_PROJECT="$PROJECT" \
python3 - <<'PY' 2>>"$ERR_LOG"
import os, sys, re, json, time, glob

MD    = os.environ["MS_MEMORY_DIR"]
Q     = os.environ["MS_QUEUE"]
ST    = os.environ["MS_STATE"]
PROJ  = os.environ["MS_PROJECT"]

today       = time.strftime("%Y-%m-%d")
today_epoch = time.mktime(time.strptime(today, "%Y-%m-%d"))

def now_utc():
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())

# --- Load + prune debounce state (slug -> last_flagged_date) ---
state = {}
try:
    with open(ST) as f:
        s = json.load(f)
    if isinstance(s, dict):
        state = s
except Exception:
    state = {}
pruned = {}
for k, v in state.items():
    try:
        flagged = time.strptime(str(v), "%Y-%m-%d")
        if (today_epoch - time.mktime(flagged)) / 86400.0 <= 30:
            pruned[k] = v
    except Exception:
        continue
state = pruned

SKIP_BASENAMES = {"memory.md", "schema.md"}
STOPWORDS = {
    "the","a","an","and","or","but","of","to","in","for","on","at","by","with",
    "is","are","was","were","be","been","being","this","that","these","those",
    "it","its","as","from","into","about","how","what","when","where","why",
    "use","used","using","via","etc","note","notes","see","ref","v1","v2",
    "do","does","not","no","yes","if","then","else","than","so","can","will",
    "your","you","i","we","they","he","she","s","t","d","ll","re","ve","m",
}

KEY_RE    = re.compile(r'^([A-Za-z_][\w\-]*)\s*:\s*(.*)$')
META_RE   = re.compile(r'^metadata\s*:\s*$')
INDENT_RE = re.compile(r'^([ \t]+)([A-Za-z_][\w\-]*)\s*:\s*(.*)$')

def parse_frontmatter(path):
    try:
        with open(path, encoding="utf-8") as f:
            content = f.read(8192)  # frontmatter only — bounded read
    except Exception:
        return None
    if not content.startswith("---"):
        return None
    lines = content.split("\n")
    fm_end = None
    for i in range(1, min(len(lines), 60)):
        if lines[i].strip() == "---":
            fm_end = i
            break
    if fm_end is None:
        return None
    top, meta = {}, {}
    in_meta = False
    meta_indent = 0
    for line in lines[1:fm_end]:
        s = line.strip()
        if not s or s.startswith("#"):
            continue
        if META_RE.match(line):
            in_meta = True
            continue
        if in_meta:
            m = INDENT_RE.match(line)
            if m:
                indent = len(m.group(1).expandtabs(4))
                if meta_indent == 0:
                    meta_indent = indent
                if indent >= meta_indent:
                    meta[m.group(2)] = m.group(3).strip().strip('"').strip("'")
                    continue
            in_meta = False
        if not in_meta:
            m2 = KEY_RE.match(line)
            if m2:
                top[m2.group(1)] = m2.group(2).strip().strip('"').strip("'")
    merged = dict(top)
    merged.update(meta)
    return merged

def tokens(s):
    parts = re.split(r'[^a-z0-9]+', (s or "").lower())
    return set(p for p in parts if p and len(p) > 1 and p not in STOPWORDS)

def days_since(date_str):
    try:
        return (today_epoch - time.mktime(time.strptime(date_str, "%Y-%m-%d"))) / 86400.0
    except Exception:
        return None

def should_flag(slug):
    """Per-slug debounce: skip if flagged within the last 7 days."""
    last = state.get(slug)
    if not last:
        return True
    try:
        age = (today_epoch - time.mktime(time.strptime(str(last), "%Y-%m-%d"))) / 86400.0
        return age >= 7
    except Exception:
        return True

def mark_flagged(slug):
    state[slug] = today

def emit(slug, reason, body_text, conf, mtype, raw_name):
    rec = {
        "ts": now_utc(),
        "session_id": "startup",
        "project": PROJ,
        "kind": "invalidation",
        "type": mtype or "unknown",
        "name": slug,
        "description": reason,
        "body": body_text,
        "confidence": conf or "medium",
        "source": "memory-staleness-check",
        "status": "pending",
    }
    try:
        with open(Q, "a") as f:
            f.write(json.dumps(rec, ensure_ascii=False) + "\n")
    except Exception:
        pass

# --- Gather files (cap 150) ---
files = []
try:
    all_md = sorted(glob.glob(os.path.join(MD, "*.md")))
except Exception:
    all_md = []
for p in all_md:
    base = os.path.basename(p).lower()
    if base in SKIP_BASENAMES:
        continue
    if base.startswith("."):
        continue
    if "/legacy/" in p.replace(os.sep, "/"):
        continue
    files.append(p)
    if len(files) >= 150:
        break

# --- Parse all frontmattered files ---
records = []
for p in files:
    fm = parse_frontmatter(p)
    if fm is None:
        continue
    # Skip superseded memories (inactive by convention).
    if fm.get("superseded_by"):
        continue
    name = fm.get("name", "") or os.path.splitext(os.path.basename(p))[0]
    desc = fm.get("description", "")
    slug = name.strip()
    mtype = fm.get("type", "unknown")
    conf  = fm.get("confidence", "medium")
    lv    = fm.get("last_verified", "")
    age   = days_since(lv) if lv else None
    toks  = tokens((name or "") + " " + (desc or ""))
    records.append({
        "slug": slug, "mtype": mtype, "confidence": conf,
        "last_verified": lv, "age": age, "tokens": toks,
        "name": name,
    })

# --- STALENESS flags ---
for r in records:
    slug = r["slug"]
    if not r["last_verified"]:
        continue  # pre-migration/untracked — not stale; still eligible for OVERLAP below
    if r["confidence"] == "high" and r["age"] is not None and r["age"] > 90:
        if should_flag(slug):
            emit(slug, "stale-90d",
                 "High-confidence memory last verified %dd ago (>90d) — re-verify, refresh, or supersede." % int(r["age"]),
                 r["confidence"], r["mtype"], r["name"])
            mark_flagged(slug)

# --- OVERLAP flags (pairwise Jaccard > 0.5) ---
n = len(records)
for i in range(n):
    ri = records[i]
    ti = ri["tokens"]
    if not ti:
        continue
    for j in range(i + 1, n):
        rj = records[j]
        tj = rj["tokens"]
        if not tj:
            continue
        inter = len(ti & tj)
        if inter == 0:
            continue
        union = len(ti | tj)
        if union == 0:
            continue
        jacc = inter / union
        if jacc > 0.5:
            reason_i = "overlap-with:%s" % rj["slug"]
            reason_j = "overlap-with:%s" % ri["slug"]
            if should_flag(ri["slug"]):
                emit(ri["slug"], reason_i,
                     "Potential duplicate of '%s' (Jaccard %.2f) — merge, supersede, or differentiate." % (rj["slug"], jacc),
                     ri["confidence"], ri["mtype"], ri["name"])
                mark_flagged(ri["slug"])
            if should_flag(rj["slug"]):
                emit(rj["slug"], reason_j,
                     "Potential duplicate of '%s' (Jaccard %.2f) — merge, supersede, or differentiate." % (ri["slug"], jacc),
                     rj["confidence"], rj["mtype"], rj["name"])
                mark_flagged(rj["slug"])

# --- Persist debounce state ---
try:
    with open(ST, "w") as f:
        json.dump(state, f, indent=2, sort_keys=True)
except Exception:
    pass
PY
PY_RC=$?

END_MS=$(python3 -c 'import time;print(int(time.time()*1000))' 2>/dev/null || date +%s)
DUR_MS=$((END_MS - START_MS))
[ "$DUR_MS" -lt 0 ] && DUR_MS=0
DUR_S=$(python3 -c "print(round($DUR_MS/1000.0, 3))" 2>/dev/null || echo "0")

OUTCOME="ok"
[ "$PY_RC" -ne 0 ] && OUTCOME="error"
printf '{"ts":"%s","hook":"memory-staleness","outcome":"%s","duration_s":%s}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$OUTCOME" "$DUR_S" >> "$HOOKS_LOG" 2>/dev/null || true

exit 0
