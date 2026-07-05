# Hook Telemetry

Every hook emits **exactly one** JSON line to `~/vault/logs/hooks.jsonl` per
invocation, via the shared `hooklib.sh`. The rollup lives in the `infra-health`
skill (`infra_health.py`), which reads this file plus rotated backups.

## What we track (and why)

| Field | Type | Why it's tracked |
|-------|------|------------------|
| `ts` | ISO8601 UTC | human-readable when |
| `ts_epoch` | int (s) | robust, timezone-free windowing |
| `hook` | string | which hook ran |
| `event` | string | which Claude Code event fired it (`Stop`, `PreToolUse`, `PreCompact`, `SessionStart`, `SubagentStart`, `PostToolUse`, `PermissionRequest`) — one script can serve >1 event (e.g. session-marker) |
| `outcome` | enum | `ok` / `skip` / `block` / `deny` / `allow` / `pass` / `error` |
| `detail` | string | short human context (what it did / why it skipped) |
| `duration_ms` | int | **latency** — the number that tells you if a hook is slow |
| `exit_code` | int | real process exit status — catches silent crashes even when `outcome` was never set |
| `session` | string(8) | correlate to a session |
| `cwd` | string | correlate to a repo/project |
| `tool` | string | for Pre/PostToolUse + PermissionRequest: which tool matched (`Bash`, `Read`…) |
| `host` | string | which machine (multi-machine setup) |
| `pid` | int | debugging concurrent runs |

Design principles behind the list:
- **Latency + reliability are the two questions** infra-health answers, so every
  hook must carry `duration_ms` and `exit_code`. These are captured automatically
  by an `EXIT` trap, so no hook can forget — even a `set -e` abort is logged.
- **Outcome ≠ exit code.** A guard hook blocking (`outcome=block`, `exit=2`) is
  *working*, not failing. `exit_code` flags genuine crashes separately.
- **Attribution** (`event`, `session`, `cwd`, `tool`, `host`) lets you slice
  "which event / repo / machine is slow or failing".

## Using it in a hook

```bash
set -euo pipefail
HOOK_NAME=my-hook            # required
HOOK_EVENT=Stop              # optional but recommended
source "$(dirname "$0")/hooklib.sh" 2>/dev/null \
  || { hook_outcome(){ :;}; hook_ctx(){ :;}; hook_tool(){ :;}; }

# ... parse stdin ...
hook_ctx "$SID" "$CWD"       # optional: attach session + cwd
hook_tool "$TOOL_NAME"       # optional: attach matched tool
hook_outcome ok "did the thing"   # last call wins; trap emits once on exit
```

Notes:
- The emit writes **only** to the log file, never stdout — safe for hooks that
  print a permission-decision / `additionalContext` JSON.
- If `hook_outcome` is never called, `outcome` is derived from the exit code
  (`0→ok`, `2→block`, `*→error`).
- The log rotates at ~8MB (`hooks.jsonl.1`, `.2`); `infra_health.py` reads all three.

## Coverage

All hooks route through `hooklib.sh` except `warm-start.sh` (lives in
`~/.claude/scripts`, has its own `ERR` trap + background subshell) — it emits the
same schema by hand. Run `/infra-health` (or `infra_health.py [days]`) for the report.

---

# Skill Telemetry

Skills can't be measured from a `PostToolUse` hook — the `Skill` tool call only
*loads* SKILL.md and returns before the skill does any work. So skill telemetry is
computed **offline** by `skill_analyzer.py`, which runs in the session-export
pipeline (no hot-path cost) and reconstructs each invocation's *work window* from
the session JSONL. It captures **both** invocation paths:

- model calls the `Skill` tool → `source=auto`
- user types a `/slash-command` skill → `source=explicit` (the legacy
  `workflow.jsonl` counter misses these entirely — it undercounts slash-heavy skills)

### Sinks

`~/vault/logs/skills.jsonl` — one record per invocation (the **cost + quality** signal):

| Field | Drives |
|-------|--------|
| `skill`, `kind` (skill/agent), `source` | usage breakdown; auto vs explicit routing |
| `output_tokens`, `tool_calls`, `duration_ms` | **cost** — which skills are expensive |
| `errors` | friction inside the skill's window |
| `correction_next` | **rework** — did the next user turn correct the skill's output? |

`~/vault/logs/routing.jsonl` — one record per trigger-matched user turn (the
**invocation-quality** signal): `verdict` (`ok`/`missed`/`misfire`), `matched`,
`fired`, `prompt`. `missed` = a prompt matched a skill's triggers but no skill
fired (a CLAUDE.md routing-rule miss candidate).

### The four metrics (in `infra-health`)

1. **Routing adherence %** = `ok / (ok + missed)` — are skills firing when they should?
2. **Correction rate per skill** (`corr%`) — quality proxy; flagged at ≥25%.
3. **Median output tokens per skill** — cost, to target optimization.
4. **Dead skills** = registry (`~/.claude/skills/*/SKILL.md`) minus ever-invoked.

Notes / honesty:
- Routing matching is heuristic (trigger phrases from each SKILL.md `description`).
  Single bare words only count near the prompt start; multi-word phrases match
  anywhere. `missed`/`misfire` are **candidates to review**, not hard failures.
- Idempotent: records are dedup-keyed (`session:seq`/`session:turn`), so the
  Stop/PreCompact/debounce re-runs over a growing JSONL never double-count.
  To re-evaluate routing verdicts after changing the matcher, truncate the sinks
  and re-run `skill_analyzer.py` over `~/.claude/projects/**/*.jsonl`.
