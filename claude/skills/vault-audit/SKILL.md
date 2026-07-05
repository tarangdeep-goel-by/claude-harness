---
name: vault-audit
description: "Audit the workflow and vault health. Use when the user says /vault audit to check if skills are being invoked and pushes are happening."
---

# /vault audit — Workflow & Vault Health Check

Check whether the workflow engine, skills, and vault pushes are actually working.

> **Role:** vault-audit is the cheap, deterministic **finder** — it reads the logs + scans
> files and reports mechanical/process issues, but changes nothing. Its sibling, the
> **librarian** agent, is the **fixer/consolidator** that takes these findings and does the
> judgement work (merge overlapping research, reconcile contradictions, update the KB).
> Friday `/wrap-up` runs vault-audit first, then hands the issue list to the librarian.

## Usage

```
/vault audit              # Full audit
/vault audit today        # Only today's activity
/vault audit last 7 days  # Last 7 days
```

## Steps

### 1. Count skill invocations from the session transcripts (authoritative)

Skill invocations are recorded as `Skill` tool-use entries inside the session
JSONL transcripts. **As of 2026-06-16, a PreToolUse hook on the `Skill` tool
(`~/vault/scripts/skill-log-hook.sh`) also logs every Skill-tool invocation to
`workflow.jsonl`** — so for activity *after* that date, `workflow.jsonl` is
complete and you can count from it directly (fast). For anything *before*
2026-06-16, or as a cross-check, count from the transcripts (the complete
historical record). Note `workflow.jsonl` still does NOT capture user-typed
`/slash-commands` that the harness injects as prompts (those bypass the Skill
tool) — transcripts' `<command-name>` tags do.

Count from the transcripts:

```bash
# Skill-tool invocations, ranked (all sessions for this project).
# Find your project slug: ls ~/.claude/projects/  (Claude Code encodes the cwd
# as a slug like -Users-...-<repo>). Glob all if you don't care about scoping:
grep -oh '"skill":"[^"]*"' ~/.claude/projects/*/*.jsonl \
  | sort | uniq -c | sort -rn

# User-typed slash commands (commands inject as prompts, so they show 0 Skill
# calls by design — count them separately, don't flag them as "skipped"):
grep -oh '<command-name>[^<]*' ~/.claude/projects/*/*.jsonl \
  | sort | uniq -c | sort -rn
```

To scope to a time window, filter files by mtime first
(`find … -newermt 'YYYY-MM-DD'`) and feed that list to grep.

### 2. Generate a report

Report the ranked skill-invocation table from step 1, then add push cadence
from `workflow.jsonl` (still the right source for vault-push + learning-detector
timing):

```bash
cat ~/vault/logs/workflow.jsonl | grep -E 'vault-push|learning-detector' | tail -50
```

**Skill invocation counts** (from transcripts, for the time period) — rank every
skill that fired, and explicitly list which configured skills had ZERO
invocations (dormant). Distinguish situational-but-valid (e.g. `flutter-dev`,
`docs-gen`, `export`, `design-system`) from genuinely abandoned.

**Vault push health:**
- Last completion note push: <date> (<project>)
- Last daily summary: <date>
- Last plan push: <date>
- Notes count: N files
- Daily count: N files

**Gaps detected:**
- Flag days with sessions (from `~/vault/sessions/`) but no workflow log entries (means skills were skipped entirely)
- Flag if vault-push has 0 entries for days that had active sessions (means push was skipped)
- Flag if planner has 0 invocations across multiple active days (means planning is not happening)
- Flag if transcriber has 0 invocations but daily folders contain recordings (means meetings aren't being processed)

### 3. Cross-reference with sessions

```bash
# Count sessions in the time period
ls ~/vault/sessions/ | grep "YYYY-MM-DD" | wc -l
```

Compare session count vs skill invocation count. If sessions >> skill invocations, the workflow is being skipped.

### 4. Summary verdict

End with a one-line verdict:
- "Workflow healthy — all skills firing, vault pushes happening"
- "Workflow partially compliant — [specific gaps]"
- "Workflow not being followed — [specific issues]"
