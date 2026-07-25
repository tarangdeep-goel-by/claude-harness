#!/usr/bin/env bash
# build-skill-index.sh — build/refresh the QMD `skills` collection from skill descriptions.
#
# The skill-retrieval UserPromptSubmit hook runs `qmd query "<prompt>" -c skills` to surface the
# top-k skills matching the user's prompt. This script stages one .md per skill (body = the
# `description` frontmatter) under ~/.claude/.cache/skill-index/, registers the qmd collection
# (idempotent), and (re)embeds. Mtime-guarded: fast no-op when no SKILL.md is newer than the marker.
#
# Wired into install.sh (on install/update) and warm-start.sh (before qmd update/embed, so newly
# added skills are indexed on the next session start). Follows symlinks, so repo-backed skills AND
# real-dir skills are both indexed.
set -uo pipefail

SKILLS_DIR="${HOME}/.claude/skills"
STAGE_DIR="${HOME}/.claude/.cache/skill-index"
MARKER="${STAGE_DIR}/.built"

mkdir -p "$STAGE_DIR"
[ -d "$SKILLS_DIR" ] || exit 0

# --- mtime guard: skip if no SKILL.md is newer than the marker ---
# -L follows symlinks (repo-backed skills); -print -quit stops at the first match.
if [ -f "$MARKER" ]; then
  if ! find -L "$SKILLS_DIR" -name SKILL.md -type f -newer "$MARKER" -print -quit 2>/dev/null | grep -q .; then
    exit 0
  fi
fi

# --- extract {name, description} from each SKILL.md frontmatter → one staging file per skill ---
count=$(python3 - "$SKILLS_DIR" "$STAGE_DIR" <<'PY'
import os, sys, glob, re
skills_dir, stage_dir = sys.argv[1], sys.argv[2]

def parse_fm(text):
    """Parse YAML frontmatter (between leading --- and the next ---). Handles double-quoted
    single-line values AND `|` block scalars. Bounded read — frontmatter only."""
    if not text.startswith("---"):
        return {}
    lines = text.split("\n")
    end = next((i for i in range(1, min(len(lines), 80)) if lines[i].strip() == "---"), None)
    if end is None:
        return {}
    fm = {}
    i = 1
    while i < end:
        m = re.match(r'^([A-Za-z_][\w-]*):\s*(.*)$', lines[i])
        if not m:
            i += 1
            continue
        key, val = m.group(1), m.group(2).rstrip()
        if val.strip().startswith("|"):           # YAML block scalar
            block = []
            i += 1
            while i < end and (lines[i].startswith("  ") or lines[i].startswith("\t")):
                block.append(lines[i].strip())
                i += 1
            fm[key] = " ".join(b for b in block if b)
        elif val.strip() == "":
            i += 1                                # empty value, skip
        else:
            fm[key] = val.strip().strip('"').strip("'")
            i += 1
    return fm

seen = set()
for skill_md in sorted(glob.glob(os.path.join(skills_dir, "*", "SKILL.md"))):
    try:
        with open(skill_md, encoding="utf-8") as f:
            fm = parse_fm(f.read(8192))
    except Exception:
        continue
    name = (fm.get("name") or "").strip()
    desc = (fm.get("description") or "").strip()
    if not name:
        continue
    seen.add(name)
    with open(os.path.join(stage_dir, name + ".md"), "w", encoding="utf-8") as f:
        f.write(f"# Skill: {name}\n\n{desc}\n")

# prune stale staging files (skill uninstalled)
for stale in glob.glob(os.path.join(stage_dir, "*.md")):
    if os.path.splitext(os.path.basename(stale))[0] not in seen:
        try:
            os.remove(stale)
        except OSError:
            pass
print(len(seen))
PY
)

# --- register the qmd collection (idempotent) + (re)embed (delta) ---
if command -v qmd >/dev/null 2>&1; then
  if ! qmd collection list 2>/dev/null | grep -qiE '^skills\b'; then
    qmd collection add "$STAGE_DIR" --name skills --mask '*.md' >/dev/null 2>&1 || true
    qmd context add "$STAGE_DIR" "Skill descriptions — for task-start skill retrieval (UserPromptSubmit hook)." >/dev/null 2>&1 || true
  fi
  qmd embed >/dev/null 2>&1 || true
else
  echo "[skill-index] qmd not installed — staged ${count} skills but no index built" >&2
fi

touch "$MARKER"
