#!/usr/bin/env bash
# warm-start.sh - Project Intelligence for Claude Code
# SessionStart hook that gathers project state and injects it as context.
# Fires on: new sessions, resumes, /clear, and compaction.
#
# Output: JSON with additionalContext for the SessionStart hook.
# Target execution time: < 2 seconds.

set -uo pipefail

HOOKS_LOG="$HOME/vault/logs/hooks.jsonl"
ERR_LOG="$HOME/vault/logs/warm-start-errors.log"
START_TS=$(date +%s)
mkdir -p "$(dirname "$HOOKS_LOG")"

# Trap any unexpected failure and log it
# Capture $? into `rc` as the trap's FIRST statement — by the time the trap body
# runs, $? has been reset, so the old `code $?` always logged 0 (misleading FATALs).
trap 'rc=$?; echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] FATAL: warm-start.sh command failed (code $rc) at line $LINENO" >> "$ERR_LOG"' ERR

# Read hook input from stdin (JSON with session_id, source, cwd, etc.)
HOOK_INPUT=""
if [ ! -t 0 ]; then
  HOOK_INPUT=$(cat)
fi

if [ -z "$HOOK_INPUT" ]; then
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] WARN: no stdin received" >> "$ERR_LOG"
fi

SESSION_SOURCE=$(echo "$HOOK_INPUT" | jq -r '.source // "startup"' 2>/dev/null || echo "startup")
SESSION_ID=$(echo "$HOOK_INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null || echo "unknown")
PROJECT_DIR=$(echo "$HOOK_INPUT" | jq -r '.cwd // empty' 2>/dev/null || echo "")
if [ -z "$PROJECT_DIR" ]; then
  PROJECT_DIR="$(pwd)"
fi

echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] START: session=$SESSION_ID source=$SESSION_SOURCE cwd=$PROJECT_DIR" >> "$ERR_LOG"

cd "$PROJECT_DIR" 2>/dev/null || exit 0

# ── Helpers ──────────────────────────────────────────────────────────────

brief=""

emit() {
  brief+="$1"$'\n'
}

emit_section() {
  brief+=$'\n'"## $1"$'\n'
}

# Resolve a timeout binary once (macOS ships neither `timeout` nor `gtimeout`
# by default — coreutils provides `gtimeout`). Empty if none available.
TIMEOUT_BIN=""
if command -v timeout &>/dev/null; then TIMEOUT_BIN="timeout"
elif command -v gtimeout &>/dev/null; then TIMEOUT_BIN="gtimeout"; fi

# Run a command with a timeout (default 2s). Return empty on failure.
# Without a timeout binary this still runs the command (no time box) rather
# than silently no-op'ing on a bogus "command not found".
timed() {
  if [ -n "$TIMEOUT_BIN" ]; then
    "$TIMEOUT_BIN" 2 "$@" 2>/dev/null || true
  else
    "$@" 2>/dev/null || true
  fi
}

# Relative time description from unix timestamp
relative_time() {
  local now ts diff
  now=$(date +%s)
  ts=$1
  diff=$((now - ts))
  if [ $diff -lt 60 ]; then echo "${diff}s ago"
  elif [ $diff -lt 3600 ]; then echo "$((diff / 60))m ago"
  elif [ $diff -lt 86400 ]; then echo "$((diff / 3600))h ago"
  else echo "$((diff / 86400))d ago"; fi
}

# ── Git Intelligence ─────────────────────────────────────────────────────

gather_git() {
  if ! git rev-parse --is-inside-work-tree &>/dev/null; then
    return
  fi

  local branch head_msg head_ts head_rel stash_count
  branch=$(git branch --show-current 2>/dev/null || echo "detached")

  # Last commit info
  head_msg=$(git log -1 --format='%s' 2>/dev/null || echo "")
  head_ts=$(git log -1 --format='%ct' 2>/dev/null || echo "")
  head_rel=""
  if [ -n "$head_ts" ] && [ "$head_ts" != "" ]; then
    head_rel=$(relative_time "$head_ts")
  fi

  emit_section "Git State"
  emit "Branch: \`$branch\`"
  if [ -n "$head_msg" ]; then
    emit "Last commit: $head_msg ($head_rel)"
  fi

  # Uncommitted changes
  local status_output changed staged untracked
  status_output=$(git status --porcelain 2>/dev/null || echo "")
  if [ -n "$status_output" ]; then
    changed=$(echo "$status_output" | grep -c '^ M\|^MM\|^ D' || true)
    staged=$(echo "$status_output" | grep -c '^M \|^A \|^D \|^R ' || true)
    untracked=$(echo "$status_output" | grep -c '^??' || true)
    local parts=()
    [ "$staged" -gt 0 ] && parts+=("$staged staged")
    [ "$changed" -gt 0 ] && parts+=("$changed modified")
    [ "$untracked" -gt 0 ] && parts+=("$untracked untracked")
    emit "Working tree: $(IFS=', '; echo "${parts[*]}")"

    # List the actual changed files (max 15)
    local changed_files
    changed_files=$(echo "$status_output" | head -15 | awk '{print $2}' | sed 's/^/- /')
    emit "$changed_files"
    local total_changes
    total_changes=$(echo "$status_output" | wc -l | tr -d ' ')
    if [ "$total_changes" -gt 15 ]; then
      emit "- ... and $((total_changes - 15)) more"
    fi
  else
    emit "Working tree: clean"
  fi

  # Stashes
  stash_count=$(git stash list 2>/dev/null | wc -l | tr -d ' ')
  if [ "$stash_count" -gt 0 ]; then
    emit "Stashes: $stash_count"
  fi

  # Recent commits (last 7 days, max 10)
  local recent_log
  recent_log=$(timed git log --oneline --no-decorate --since="7 days ago" -10 2>/dev/null)
  if [ -n "$recent_log" ]; then
    emit_section "Recent Commits (7d)"
    emit "$recent_log"
  fi

  # Branches with recent activity
  local active_branches
  active_branches=$(timed git branch --sort=-committerdate --format='%(refname:short) (%(committerdate:relative))' -5 2>/dev/null | head -5)
  if [ -n "$active_branches" ] && [ "$(echo "$active_branches" | wc -l | tr -d ' ')" -gt 1 ]; then
    emit_section "Active Branches"
    emit "$active_branches"
  fi

  # Merge/rebase state
  local git_dir
  git_dir=$(git rev-parse --git-dir 2>/dev/null)
  if [ -d "$git_dir/rebase-merge" ] || [ -d "$git_dir/rebase-apply" ]; then
    emit_section "REBASE IN PROGRESS"
  elif [ -f "$git_dir/MERGE_HEAD" ]; then
    emit_section "MERGE IN PROGRESS"
  elif [ -f "$git_dir/CHERRY_PICK_HEAD" ]; then
    emit_section "CHERRY-PICK IN PROGRESS"
  fi

  # Upstream status
  local upstream
  upstream=$(git rev-parse --abbrev-ref '@{upstream}' 2>/dev/null || echo "")
  if [ -n "$upstream" ]; then
    local ahead behind
    ahead=$(git rev-list --count '@{upstream}..HEAD' 2>/dev/null || echo "0")
    behind=$(git rev-list --count 'HEAD..@{upstream}' 2>/dev/null || echo "0")
    if [ "$ahead" -gt 0 ] || [ "$behind" -gt 0 ]; then
      local sync_parts=()
      [ "$ahead" -gt 0 ] && sync_parts+=("$ahead ahead")
      [ "$behind" -gt 0 ] && sync_parts+=("$behind behind")
      emit "Upstream ($upstream): $(IFS=', '; echo "${sync_parts[*]}")"
    fi
  fi
}

# ── Stack Detection ──────────────────────────────────────────────────────

gather_stack() {
  local stack_parts=()
  local pkg_manager=""
  local scripts_info=""

  # Node.js ecosystem
  if [ -f "package.json" ]; then
    # Detect package manager
    if [ -f "bun.lockb" ] || [ -f "bun.lock" ]; then pkg_manager="bun"
    elif [ -f "pnpm-lock.yaml" ]; then pkg_manager="pnpm"
    elif [ -f "yarn.lock" ]; then pkg_manager="yarn"
    elif [ -f "package-lock.json" ]; then pkg_manager="npm"
    else pkg_manager="npm"; fi

    # Detect framework from dependencies
    local deps
    deps=$(cat package.json)
    if echo "$deps" | jq -e '.dependencies.next // .devDependencies.next' &>/dev/null; then
      stack_parts+=("Next.js")
    elif echo "$deps" | jq -e '.dependencies.react // .devDependencies.react' &>/dev/null; then
      stack_parts+=("React")
    elif echo "$deps" | jq -e '.dependencies.vue // .devDependencies.vue' &>/dev/null; then
      stack_parts+=("Vue")
    elif echo "$deps" | jq -e '.dependencies.svelte // .devDependencies.svelte' &>/dev/null; then
      stack_parts+=("Svelte")
    elif echo "$deps" | jq -e '.dependencies["@angular/core"] // .devDependencies["@angular/core"]' &>/dev/null; then
      stack_parts+=("Angular")
    fi

    # TypeScript?
    if [ -f "tsconfig.json" ]; then
      stack_parts+=("TypeScript")
    else
      stack_parts+=("JavaScript")
    fi

    stack_parts+=("Node ($pkg_manager)")

    # Extract useful scripts
    local scripts
    scripts=$(echo "$deps" | jq -r '.scripts // {} | to_entries[] | "\(.key)=\(.value)"' 2>/dev/null | head -10)
    if [ -n "$scripts" ]; then
      # Pick the most useful ones
      local useful_scripts=()
      for key in test build dev start lint typecheck check format; do
        local val
        val=$(echo "$scripts" | grep "^${key}=" | head -1 | cut -d= -f2-)
        if [ -n "$val" ]; then
          useful_scripts+=("$key: \`$pkg_manager run $key\` ($val)")
        fi
      done
      if [ ${#useful_scripts[@]} -gt 0 ]; then
        scripts_info=$(printf '%s\n' "${useful_scripts[@]}")
      fi
    fi
  fi

  # Python
  if [ -f "pyproject.toml" ]; then
    stack_parts+=("Python (pyproject.toml)")
    if [ -f "uv.lock" ]; then stack_parts+=("uv")
    elif [ -f "poetry.lock" ]; then stack_parts+=("Poetry")
    elif [ -f "Pipfile.lock" ]; then stack_parts+=("Pipenv")
    fi
  elif [ -f "requirements.txt" ]; then
    stack_parts+=("Python (pip)")
  elif [ -f "setup.py" ]; then
    stack_parts+=("Python (setup.py)")
  fi

  # Rust
  if [ -f "Cargo.toml" ]; then
    stack_parts+=("Rust")
  fi

  # Go
  if [ -f "go.mod" ]; then
    local go_module
    go_module=$(head -1 go.mod | awk '{print $2}')
    stack_parts+=("Go ($go_module)")
  fi

  # Ruby
  if [ -f "Gemfile" ]; then
    stack_parts+=("Ruby")
    [ -f "config/routes.rb" ] && stack_parts+=("Rails")
  fi

  # Java/Kotlin
  if [ -f "build.gradle" ] || [ -f "build.gradle.kts" ]; then
    stack_parts+=("Gradle")
  elif [ -f "pom.xml" ]; then
    stack_parts+=("Maven")
  fi

  # Docker
  if [ -f "Dockerfile" ] || [ -f "docker-compose.yml" ] || [ -f "docker-compose.yaml" ] || [ -f "compose.yml" ]; then
    stack_parts+=("Docker")
  fi

  if [ ${#stack_parts[@]} -gt 0 ]; then
    emit_section "Stack"
    local stack_str
    stack_str=$(IFS=', '; echo "${stack_parts[*]}")
    emit "$stack_str"
    if [ -n "$scripts_info" ]; then
      emit ""
      emit "**Key commands:**"
      emit "$scripts_info"
    fi
  fi
}

# ── Project Structure ────────────────────────────────────────────────────

gather_structure() {
  # Only on fresh starts in actual projects
  if [ "$SESSION_SOURCE" = "compact" ]; then return; fi
  if ! git rev-parse --is-inside-work-tree &>/dev/null && \
     ! [ -f "package.json" ] && ! [ -f "Cargo.toml" ] && ! [ -f "go.mod" ] && \
     ! [ -f "pyproject.toml" ] && ! [ -f "requirements.txt" ] && ! [ -f "Gemfile" ] && \
     ! [ -f "pom.xml" ] && ! [ -f "build.gradle" ] && ! [ -f "Makefile" ]; then
    return
  fi

  local top_dirs
  top_dirs=$(ls -d */ 2>/dev/null | head -20 | sed 's|/$||' | grep -v -E '^(node_modules|\.git|dist|build|\.next|__pycache__|\.venv|venv|target|\.cache|\.turbo|coverage)$' || true)
  if [ -n "$top_dirs" ]; then
    emit_section "Top-level Directories"
    local dir_listing=""
    while read -r d; do
      local count
      count=$(find "$d" -maxdepth 3 -type f 2>/dev/null | head -200 | wc -l | tr -d ' ')
      dir_listing+="- $d/ ($count files)"$'\n'
    done <<< "$top_dirs"
    emit "$dir_listing"
  fi
}

# ── Previous Session Learnings ───────────────────────────────────────────

gather_learnings() {
  local learnings_file="$PROJECT_DIR/.claude/warm-learnings.md"
  if [ -f "$learnings_file" ]; then
    local content
    content=$(head -50 "$learnings_file")
    if [ -n "$content" ]; then
      emit_section "Learnings from Previous Sessions"
      emit "$content"
    fi
  fi
}

# ── Previous Session (auto-inject most relevant session metadata) ────────

gather_previous_session() {
  # Skip on compact (context already has it) and resume (same session)
  if [ "$SESSION_SOURCE" = "compact" ] || [ "$SESSION_SOURCE" = "resume" ]; then return; fi

  # Derive project name from basename of PROJECT_DIR, lowercased
  local project
  project=$(basename "$PROJECT_DIR" | tr '[:upper:]' '[:lower:]')

  # Find candidate session files matching the project name
  local candidates
  candidates=$(ls "$HOME/vault/sessions/" 2>/dev/null | grep "_${project}_" | sort -r | head -5)
  if [ -z "$candidates" ]; then return; fi

  # For each candidate, extract frontmatter and check message_count
  local best_file="" best_count=0
  while IFS= read -r fname; do
    local fpath="$HOME/vault/sessions/$fname"
    # Extract message_count from YAML frontmatter (between first and second ---)
    local msg_count
    msg_count=$(sed -n '2,/^---$/p' "$fpath" | grep '^message_count:' | awk '{print $2}' | tr -d ' ')
    msg_count=${msg_count:-0}

    # Skip trivial sessions (message_count <= 2)
    if [ "$msg_count" -le 2 ]; then continue; fi

    # Pick candidate with highest message_count
    if [ "$msg_count" -gt "$best_count" ]; then
      best_count=$msg_count
      best_file=$fname
    fi
  done <<< "$candidates"

  if [ -z "$best_file" ]; then return; fi

  # Extract metadata from the best session
  local fpath="$HOME/vault/sessions/$best_file"
  local fm
  fm=$(sed -n '2,/^---$/p' "$fpath")

  local session_date session_title session_branch files_touched
  session_date=$(echo "$fm" | grep '^date:' | awk '{print $2}')
  session_title=$(echo "$fm" | grep '^title:' | sed 's/^title: *//' | sed 's/^"//;s/"$//')
  session_branch=$(echo "$fm" | grep '^branch:' | awk '{print $2}')
  # Extract top 5 files_touched from the YAML list
  files_touched=$(echo "$fm" | grep '^files_touched:' | sed 's/^files_touched: *\[//;s/\]$//' | tr ',' '\n' | sed 's/^ *//;s/ *$//' | head -5)

  # Emit section
  emit_section "Previous Session"
  [ -n "$session_date" ] && emit "Date: $session_date"
  [ -n "$session_title" ] && emit "Task: $session_title"
  [ -n "$session_branch" ] && emit "Branch: \`$session_branch\`"
  emit "Messages: $best_count"
  if [ -n "$files_touched" ]; then
    emit "Top files:"
    echo "$files_touched" | head -5 | while read -r f; do
      [ -n "$f" ] && emit "- $f"
    done
  fi
}

gather_resume() {
  # RESUME.md is a per-project BOARD (one `## <project>` section each), written by
  # /vault-push at every session END (it overwrites only the touched project's section
  # and sets `last_touched` in frontmatter). warm-start fires before the user states
  # intent, so it can't know this tab's project — it surfaces ONLY the freshest section
  # (the `last_touched` one) + a one-line index of the other tracked threads, keeping the
  # session-start footprint one-thread-sized. /recall <project> swaps to the right thread.
  # (start-work is the once-a-day deep read; this hook + /recall are the per-session readers.)
  # Skip on compact (context already present); show on startup/clear/resume.
  if [ "$SESSION_SOURCE" = "compact" ]; then return 0; fi
  local rf="$PROJECT_DIR/System/handoffs/RESUME.md"
  # `return 0`, not bare `return` — a bare return leaks the failing `[ -f ]` status
  # (1) as the function's exit, tripping the ERR trap at the call site on every
  # non-vault session (the misleading "FATAL ... line 559" in warm-start-errors.log).
  [ -f "$rf" ] || return 0

  local updated fresh
  updated=$(grep -m1 '^updated:' "$rf" | sed 's/^updated: *//')
  fresh=$(grep -m1 '^last_touched:' "$rf" | sed 's/^last_touched: *//' | tr -d '"' | sed 's/ *$//')

  # Fallback: old single-pointer format (no `last_touched:`) — emit the whole body as before.
  # NOTE: capture awk into a var, never `awk | while ...emit` — the pipe runs `while` in a
  # subshell so the emit-appends to $brief are lost (that was a real bug here).
  if [ -z "$fresh" ]; then
    emit_section "Where You Left Off (RESUME — last session)"
    [ -n "$updated" ] && emit "_resume pointer · updated ${updated}_"
    local body
    body=$(awk '/^# Resume/{p=1} /^## Touched/{p=0} p' "$rf")
    [ -n "$body" ] && emit "$body"
    return 0
  fi

  # Board format: inject only the freshest project's section (exact header match).
  # Stop at the next `## ` header OR a column-0 HTML comment (so a trailing template/
  # note comment never bleeds into the brief when last_touched is the bottom section).
  emit_section "Where You Left Off (RESUME — ${fresh}, last-touched thread)"
  [ -n "$updated" ] && emit "_board updated ${updated} · auto-surfacing the last-touched thread only; run \`/recall <project>\` to swap to the thread you're on_"
  local body
  body=$(awk -v hdr="## ${fresh}" '
    $0==hdr {f=1; print; next}
    /^## / {f=0}
    /^<!--/ {f=0}
    f {print}
  ' "$rf")
  [ -n "$body" ] && emit "$body"
  # Symmetry: a clickable pointer to the freshest thread's own full PROJECT_LOG history.
  local fhit
  fhit=$(grep -n -m1 -E '^## [0-9]{4}-[0-9]{2}-[0-9]{2}' "$PROJECT_DIR/Notes/${fresh}/PROJECT_LOG.md" 2>/dev/null)
  [ -n "$fhit" ] && emit "_history: Notes/${fresh}/PROJECT_LOG.md:${fhit%%:*}_"

  # Reference index for the OTHER active threads: the latest PROJECT_LOG entry per project.
  # Sourced from history (the `## YYYY-MM-DD — summary` head, newest-first per the format
  # standard) so it's always present even before a project has its own board section. One
  # clickable line each, most-recently-touched first, `/recall <project>` for depth.
  # Recency floor (ACTIVE_DAYS, aligned with the board's archive-after-days) so dormant
  # projects don't surface looking active; capped at REF_MAX. Keeps the footprint bounded.
  local ACTIVE_DAYS=30 REF_MAX=6
  local cutoff
  cutoff=$(date -v-${ACTIVE_DAYS}d +%Y-%m-%d 2>/dev/null || date -d "${ACTIVE_DAYS} days ago" +%Y-%m-%d 2>/dev/null || echo "")
  local refs="" plog proj hit lineno latest edate count=0
  while IFS= read -r plog; do
    [ -z "$plog" ] && continue
    [ "$count" -ge "$REF_MAX" ] && break
    proj=$(basename "$(dirname "$plog")")
    [ "$proj" = "$fresh" ] && continue
    hit=$(grep -n -m1 -E '^## [0-9]{4}-[0-9]{2}-[0-9]{2}' "$plog" 2>/dev/null)
    [ -z "$hit" ] && continue
    lineno=${hit%%:*}
    latest=$(printf '%s' "${hit#*:}" | sed 's/^## *//' | cut -c1-150)
    edate=$(printf '%s' "$latest" | grep -oE '^[0-9]{4}-[0-9]{2}-[0-9]{2}')
    if [ -n "$cutoff" ] && [ -n "$edate" ] && [[ "$edate" < "$cutoff" ]]; then continue; fi
    refs+="- **${proj}** — ${latest} · Notes/${proj}/PROJECT_LOG.md:${lineno}"$'\n'
    count=$((count + 1))
  done < <(ls -t "$PROJECT_DIR"/Notes/*/PROJECT_LOG.md 2>/dev/null)

  if [ -n "$refs" ]; then
    emit ""
    emit "_Other active threads (latest entry, touched <${ACTIVE_DAYS}d · \`/recall <project>\` for depth):_"
    emit "${refs%$'\n'}"
  fi
  return 0
}

# ── Open PRs (only if gh is available and fast) ──────────────────────────

gather_prs() {
  if ! command -v gh &>/dev/null; then return; fi
  if ! git rev-parse --is-inside-work-tree &>/dev/null; then return; fi

  # Only on fresh starts
  if [ "$SESSION_SOURCE" = "compact" ]; then return; fi

  local prs
  prs=$(timeout 3 gh pr list --author @me --limit 5 --json number,title,headRefName,state \
    --jq '.[] | "- #\(.number) [\(.headRefName)] \(.title)"' 2>/dev/null || true)
  if [ -n "$prs" ]; then
    emit_section "Your Open PRs"
    emit "$prs"
  fi
}

# ── Parallel Sessions + Day Marker ───────────────────────────────────────

gather_sessions() {
  local marker="$HOME/vault/scripts/session-marker-hook.sh"

  # (Day-marker /start-work nudge removed — PM-vault feature; not used in dev/in-repo mode.)

  # Other live sessions (parallel work in flight), excluding this one
  if [ -x "$marker" ]; then
    local live
    live=$("$marker" --list-live 2>/dev/null | grep -v "^- ${SESSION_ID:0:8}" || true)
    if [ -n "$live" ] && [ "$live" != "(no live sessions)" ]; then
      emit_section "Live Sessions (parallel)"
      emit "$live"
    fi
  fi

  # Substantive previous sessions that were never /vault-push'd
  local unpushed
  unpushed=$(ls "$HOME/vault/logs/active-sessions/"*.json 2>/dev/null | while read -r f; do
    python3 -c "
import json,sys
d=json.load(open('$f'))
if not d.get('pushed') and d.get('session_id','')[:8] != '${SESSION_ID:0:8}':
    print(f\"- {d.get('session_id','?')[:8]} · {d.get('project','?')} (run /vault-push before it's lost)\")
" 2>/dev/null
  done)
  if [ -n "$unpushed" ]; then
    emit_section "⚠ Unpushed sessions"
    emit "$unpushed"
  fi
}

# ── KB Freshness (daily glance) ──────────────────────────────────────────

gather_kb_freshness() {
  # Semantic-memory freshness nudge (System/KNOWLEDGE.md Pillar 3): surface rule books
  # past their verify_by horizon. Gated to the FIRST session of the day (day marker
  # absent), matching the "daily" cadence; skipped on compact/resume. Emits ONLY when
  # something is actually stale — stays silent when all KBs are within horizon (no noise).
  if [ "$SESSION_SOURCE" = "compact" ] || [ "$SESSION_SOURCE" = "resume" ]; then return; fi
  local vault="$PROJECT_DIR"
  local today; today=$(date +%F)
  [ -f "$vault/System/handoffs/$today/_day-started.json" ] && return
  [ -f "$vault/System/scripts/discrepancy-scan.py" ] || return
  local out
  out=$(timed python3 "$vault/System/scripts/discrepancy-scan.py" --freshness-only)
  if [ -n "$out" ] && printf '%s' "$out" | grep -q '⚠'; then
    emit_section "KB Freshness (daily — Pillar 3)"
    emit "$out"
    emit "_re-verify against source, then bump \`updated:\`/\`verify_by:\` (rule book leads)_"
  fi
}

# Nudge if the harness repo is behind upstream (adopter forgot to ./update.sh). No network in the
# hot path — compares the last-fetched upstream; a detached background fetch refreshes it for next
# time. Fully guarded (always returns 0).
gather_harness_update() {
  local src hp behind
  src="${BASH_SOURCE[0]}"; [ -L "$src" ] && src="$(readlink "$src" 2>/dev/null || echo "$src")"
  hp="$(cd "$(dirname "$src")/../.." 2>/dev/null && pwd -P)" || return 0
  [ -d "$hp/.git" ] || return 0
  git -C "$hp" rev-parse '@{upstream}' >/dev/null 2>&1 || return 0
  behind=$(git -C "$hp" rev-list --count 'HEAD..@{upstream}' 2>/dev/null || echo 0)
  ( git -C "$hp" fetch -q >/dev/null 2>&1 & ) 2>/dev/null || true   # refresh for NEXT session, detached
  case "${behind:-0}" in ''|0) return 0;; esac
  emit_section "Harness update available"
  emit "⚠ **${behind} commit(s) behind** origin — run \`(cd ${hp} && ./update.sh)\` to reconcile (relink new skills, prune removed, refresh settings)."
  return 0
}

# ── Main ─────────────────────────────────────────────────────────────────

emit "# Project Intelligence (auto-generated)"
emit "Session: $SESSION_SOURCE | $(date '+%Y-%m-%d %H:%M')"

gather_resume
gather_git
gather_harness_update
gather_stack
gather_structure
gather_learnings
gather_previous_session
gather_sessions
gather_kb_freshness
gather_prs

# ── Data Tool Connectivity Check — REMOVED 2026-06-16 ───────────────────
# The Metabase/Mixpanel curl health-check was removed. It depended on the
# `timeout` binary (absent on macOS), so it always reported HTTP 000 and
# trained the user to ignore a permanently-red "data tools down" banner.
# Warm-start does context-loading only now; data-tool auth surfaces at the
# actual call sites (where a 401/403 is meaningful and actionable).

# ── Flush previous session on clear/startup ──────────────────────────────
# When context is cleared or a new session starts, run export + qmd-index
# for the current/previous session to capture any unsynced work.

flush_previous_session() {
  local vault_scripts="$HOME/vault/scripts"
  local projects_base="$HOME/.claude/projects"

  # Find the most recent JSONL (current or previous session)
  local latest_jsonl=""
  latest_jsonl=$(find "$projects_base" -name "*.jsonl" -type f -not -path "*/subagents/*" -newer "$projects_base" 2>/dev/null | xargs ls -t 2>/dev/null | head -1)

  if [ -z "$latest_jsonl" ]; then return; fi

  local line_count
  line_count=$(wc -l < "$latest_jsonl" 2>/dev/null | tr -d ' ')
  if [ "${line_count:-0}" -lt 20 ]; then return; fi

  # Run everything in a single background subshell to avoid blocking warm-start
  (
    # 1. Export transcript
    local export_script="$vault_scripts/export-session.py"
    if [ -f "$export_script" ]; then
      python3 "$export_script" "$latest_jsonl" 2>/dev/null || true
    fi

    # 2. Update QMD index — serialized + time-boxed.
    # Overlapping sessions each fired `qmd update`/`qmd embed` unguarded, and
    # concurrent runs load multi-GB GGUF models into RAM at once, thrashing the
    # machine until every qmd op (incl. the query this session needs) hangs.
    # A non-blocking mkdir lock makes overlapping starts SKIP instead of pile up;
    # the timeout caps a stuck run so it can't orphan and hold resources forever.
    if command -v qmd &>/dev/null; then
      qmd_lock="${TMPDIR:-/tmp}/qmd-index.lock"
      # Clear a stale lock (>10 min old) left by a crashed run.
      if [ -d "$qmd_lock" ] && [ -z "$(find "$qmd_lock" -maxdepth 0 -mmin -10 2>/dev/null)" ]; then
        rmdir "$qmd_lock" 2>/dev/null || true
      fi
      if mkdir "$qmd_lock" 2>/dev/null; then
        trap 'rmdir "$qmd_lock" 2>/dev/null || true' EXIT
        if [ -n "$TIMEOUT_BIN" ]; then
          "$TIMEOUT_BIN" 120 qmd update 2>/dev/null || true
          "$TIMEOUT_BIN" 120 qmd embed  2>/dev/null || true
        else
          qmd update 2>/dev/null || true
          qmd embed 2>/dev/null || true
        fi
        rmdir "$qmd_lock" 2>/dev/null || true
        trap - EXIT
      fi
    fi

    printf '{"ts":"%s","ts_epoch":%s,"hook":"warm-start-flush","event":"SessionStart","session":"%s","cwd":"%s","outcome":"ok","detail":"flushed on %s","exit_code":0}\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$(date +%s)" "$SESSION_ID" "$PROJECT_DIR" "$SESSION_SOURCE" >> "$HOOKS_LOG"
  ) >/dev/null 2>&1 &
  # ^ MUST redirect the flush subshell's stdout/stderr to /dev/null: it inherits the
  # hook's fd 1, and export-session.py ("Exported: …") and qmd
  # update/embed (progress bars) all write to stdout. Un-redirected, that chatter
  # leaks into the hook's ONLY legitimate stdout output — the final jq JSON — making
  # it invalid. The Claude Code CLI tolerated the noise; the Claude Desktop app's
  # stricter JSON parser rejected it and crashed the session start. The explicit
  # ">> $HOOKS_LOG" redirect above survives this (per-command redirect wins).
  disown
}

case "$SESSION_SOURCE" in
  startup|clear)
    flush_previous_session
    ;;
esac

# Rotate hooks.jsonl — keep last 14 days. It's a write-only debug log (only read
# manually/for debug), so it grows unbounded otherwise (~2.6 MB / 12K lines by 2026-06-16).
# Lines without a parseable "ts" are KEPT (never drop data we can't date).
if [ -f "$HOOKS_LOG" ]; then
  _cutoff=$(date -u -v-14d +%Y-%m-%d 2>/dev/null || date -u -d '14 days ago' +%Y-%m-%d 2>/dev/null || true)
  if [ -n "${_cutoff:-}" ]; then
    awk -v c="$_cutoff" 'index($0,"\"ts\":\"")>0 { d=substr($0, index($0,"\"ts\":\"")+6, 10); if (d >= c) print; next } { print }' \
      "$HOOKS_LOG" > "$HOOKS_LOG.tmp" 2>/dev/null && mv "$HOOKS_LOG.tmp" "$HOOKS_LOG"
  fi
fi

# ── Degradation guard — LOUD in-context marker if expected context is missing ──
# Precise, not a blunt length floor: flag only when a section we SHOULD have (given
# what's on disk) didn't make it into the brief, so a bare/non-vault session that is
# legitimately short does NOT false-positive. Surfaces at the very top of the brief
# (what the model reads first) instead of dying silently in the error log.
ws_degraded=""
if [ -d "$PROJECT_DIR/.git" ] && ! printf '%s' "$brief" | grep -q '^## Git State'; then
  ws_degraded+="git-state "
fi
if [ -f "$PROJECT_DIR/System/handoffs/RESUME.md" ] && ! printf '%s' "$brief" | grep -q 'Where You Left Off'; then
  ws_degraded+="resume "
fi
if [ -n "$ws_degraded" ]; then
  brief="> ⚠ **warm-start degraded** — expected context missing: ${ws_degraded}· run \`/recall <project>\` for a full read (details in ~/vault/logs/warm-start-errors.log)"$'\n\n'"$brief"
fi

# Log hook execution — outcome + brief_len now reflect reality so /infra-health can
# see a truncated/degraded run (the old row was hardcoded outcome:ok / exit_code:0).
DUR=$(( $(date +%s) - START_TS ))
ws_outcome="ok"
[ -n "$ws_degraded" ] && ws_outcome="degraded"
printf '{"ts":"%s","ts_epoch":%s,"hook":"warm-start","event":"SessionStart","session":"%s","cwd":"%s","outcome":"%s","detail":"source=%s%s","duration_ms":%d,"brief_len":%d,"exit_code":0,"host":"%s"}\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$(date +%s)" "$SESSION_ID" "$PROJECT_DIR" "$ws_outcome" "$SESSION_SOURCE" "${ws_degraded:+ degraded=[${ws_degraded% }]}" "$(( DUR * 1000 ))" "${#brief}" "$(hostname -s 2>/dev/null || echo '')" >> "$HOOKS_LOG"

echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] END: session=$SESSION_ID duration=${DUR}s brief_len=${#brief}${ws_degraded:+ DEGRADED=[${ws_degraded% }]}" >> "$ERR_LOG"

# Output as SessionStart hook JSON
# The additionalContext field is injected into Claude's context.
jq -n --arg ctx "$brief" '{
  hookSpecificOutput: {
    hookEventName: "SessionStart",
    additionalContext: $ctx
  }
}'
