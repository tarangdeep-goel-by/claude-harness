#!/bin/bash
# PostToolUse hook (Write|Edit): stamp temporal fields on canonical-schema memory
# files. Non-blocking + idempotent. Fires only on the memory dir.
#
# Contract:
#   - Skip non-memory files, MEMORY.md, SCHEMA.md, dotfiles, legacy/ subdir.
#   - Files without frontmatter (don't start with "---") are left untouched
#     (migration is a separate, human-gated stage).
#   - For frontmattered files: stamp created/last_verified/confidence if missing,
#     refresh last_verified when the body changed (mtime date > stored date),
#     migrate a flat top-level `type:` under `metadata:`.
#   - Write back IN PLACE only when something changed.
#   - Every path exit 0. Parse failures are logged, never written.
set -uo pipefail

HOOK_NAME=memory-validate
HOOK_EVENT=PostToolUse
source "$(dirname "$0")/hooklib.sh" 2>/dev/null \
  || { hook_outcome(){ :; }; hook_ctx(){ :; }; hook_tool(){ :; }; }

LOG="$HOME/vault/logs/memory-validate.log"
mkdir -p "$(dirname "$LOG")" 2>/dev/null || true

INPUT=$(cat 2>/dev/null || echo '{}')

# Memory dir is project-scoped, derived from the session cwd in the hook payload (portable —
# no hardcoded path; matches Claude Code's per-project memory layout).
PROJECTS_BASE="$HOME/.claude/projects"
SESSION_CWD="$(printf '%s' "$INPUT" | python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('cwd',''))" 2>/dev/null || true)"
if [ -n "$SESSION_CWD" ]; then
  MEMORY_DIR="$PROJECTS_BASE/$(echo "$SESSION_CWD" | tr '/' '-')/memory"
else
  MEMORY_DIR=""
fi

# Extract affected file path from PostToolUse payload (tool_input.file_path).
FILE_PATH=$(printf '%s' "$INPUT" | python3 -c '
import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    raise SystemExit(0)
ti = d.get("tool_input", {}) or {}
p = ti.get("file_path") or ti.get("filePath") or ti.get("path") or ""
print(p)
' 2>/dev/null || echo "")

[ -z "$FILE_PATH" ] && exit 0

hook_tool "$(printf '%s' "$INPUT" | python3 -c '
import sys, json
try:
    print(json.load(sys.stdin).get("tool_name", ""))
except Exception:
    pass
' 2>/dev/null || true)"

# Must be under the memory dir.
case "$FILE_PATH" in
  "$MEMORY_DIR"/*.md) ;;
  *) exit 0 ;;
esac

BASE=$(basename "$FILE_PATH")
# Skip special files.
case "$BASE" in
  MEMORY.md|SCHEMA.md) exit 0 ;;
esac
# Skip dotfiles.
case "$BASE" in
  .*) exit 0 ;;
esac
# Skip legacy subdir.
case "$FILE_PATH" in
  */legacy/*) exit 0 ;;
esac

# Hand off to Python for safe frontmatter parsing + stamping.
MV_PATH="$FILE_PATH" \
MV_TODAY="$(date +%Y-%m-%d)" \
MV_LOG="$LOG" \
python3 - <<'PY' 2>>"$LOG" || true
import os, sys, re, time

path   = os.environ.get("MV_PATH", "")
today  = os.environ.get("MV_TODAY", "")
logf   = os.environ.get("MV_LOG", "")

def log_err(msg):
    try:
        with open(logf, "a") as f:
            f.write("%s %s\n" % (time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), msg))
    except Exception:
        pass

try:
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()
except Exception as e:
    log_err("read-fail %s: %s" % (path, e))
    raise SystemExit(0)

# Must start with --- (skip files without frontmatter silently).
if not content.startswith("---"):
    raise SystemExit(0)

# Track newline style so the round-trip is byte-faithful.
if "\r\n" in content:
    content_lf = content.replace("\r\n", "\n")
    nl = "\r\n"
else:
    content_lf = content
    nl = "\n"

lines = content_lf.split("\n")
if not lines or lines[0].strip() != "---":
    raise SystemExit(0)

fm_end = None
for i in range(1, len(lines)):
    if lines[i].strip() == "---":
        fm_end = i
        break
if fm_end is None:
    raise SystemExit(0)  # malformed frontmatter — leave untouched

fm_lines = lines[1:fm_end]
body = "\n".join(lines[fm_end:])  # includes the closing "---"

KEY_RE     = re.compile(r'^([A-Za-z_][\w\-]*)\s*:\s*(.*)$')
META_RE    = re.compile(r'^metadata\s*:\s*$')
INDENT_RE  = re.compile(r'^([ \t]+)([A-Za-z_][\w\-]*)\s*:\s*(.*)$')

# Parse, preserving line positions for in-place edits.
top_keys  = {}   # key -> index in fm_lines
top_vals  = {}   # key -> value
meta_keys = {}   # key -> index in fm_lines
meta_vals = {}   # key -> value
meta_header_idx = None
in_meta = False
meta_indent = 0

for idx, line in enumerate(fm_lines):
    s = line.strip()
    if not s or s.startswith("#"):
        continue
    if META_RE.match(line):
        meta_header_idx = idx
        in_meta = True
        continue
    if in_meta:
        m = INDENT_RE.match(line)
        if m:
            indent = len(m.group(1).expandtabs(4))
            if meta_indent == 0:
                meta_indent = indent
            if indent >= meta_indent:
                key = m.group(2)
                meta_keys[key] = idx
                meta_vals[key] = m.group(3).strip().strip('"').strip("'")
                continue
        in_meta = False
    if not in_meta:
        m2 = KEY_RE.match(line)
        if m2:
            top_keys[m2.group(1)] = idx
            top_vals[m2.group(1)] = m2.group(2).strip().strip('"').strip("'")

# File mtime (date only) — used to detect body/content changes.
try:
    mtime_date = time.strftime("%Y-%m-%d", time.localtime(os.path.getmtime(path)))
except Exception:
    mtime_date = today

# Work on a mutable copy; we never insert into the middle, only replace/append,
# so original indices stay valid. None means "drop this line on rebuild".
new_fm = list(fm_lines)
modified = False

def ensure_meta_block():
    """Create a `metadata:` header at the end of the frontmatter if absent."""
    global meta_header_idx, new_fm
    if meta_header_idx is not None:
        return
    new_fm.append("metadata:")
    meta_header_idx = len(new_fm) - 1

def set_meta(key, value):
    """Set a metadata key: replace in place if present, else append under metadata."""
    global new_fm, modified
    ensure_meta_block()
    if key in meta_keys:
        oi = meta_keys[key]
        old = fm_lines[oi]
        m = INDENT_RE.match(old)
        indent = m.group(1) if m else "  "
        new_fm[oi] = "%s%s: %s" % (indent, key, value)
    else:
        new_fm.append("  %s: %s" % (key, value))
        meta_keys[key] = len(new_fm) - 1
    meta_vals[key] = value
    modified = True

# 1. created — only if missing at either level.
if "created" not in meta_vals and "created" not in top_vals:
    set_meta("created", today)

# 2. last_verified — missing, OR content changed since stored date.
cur_lv = meta_vals.get("last_verified") or top_vals.get("last_verified") or ""
need_lv = False
if not cur_lv:
    need_lv = True
else:
    try:
        if mtime_date > cur_lv:
            need_lv = True
    except Exception:
        pass
if need_lv:
    set_meta("last_verified", today)

# 3. confidence — default medium if missing at either level.
if "confidence" not in meta_vals and "confidence" not in top_vals:
    set_meta("confidence", "medium")

# 4. metadata.type migration: move a flat top-level `type:` under `metadata:`.
if "type" not in meta_vals and "type" in top_vals:
    set_meta("type", top_vals["type"])
    # Drop the old top-level type line.
    new_fm[top_keys["type"]] = None

# Idempotent: nothing changed → no write.
if not modified:
    raise SystemExit(0)

# Drop lines marked for removal.
new_fm = [l for l in new_fm if l is not None]

new_content_lf = "---\n" + "\n".join(new_fm) + "\n" + body
new_content = new_content_lf.replace("\n", nl) if nl != "\n" else new_content_lf

if new_content == content:
    raise SystemExit(0)

# Atomic write via temp + rename.
try:
    tmp = path + ".mvtmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(new_content)
    os.replace(tmp, path)
except Exception as e:
    log_err("write-fail %s: %s" % (path, e))
    raise SystemExit(0)

raise SystemExit(0)
PY

hook_outcome "ok" "validated"
exit 0
