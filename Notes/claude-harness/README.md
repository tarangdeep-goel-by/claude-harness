# claude-harness

> In-repo knowledge index for the `claude-harness` workspace. Stable entry point; temporal history in
> `PROJECT_LOG.md`, throughline in `PROJECT_ARC.md`, todos in `OPEN_ITEMS.md`.

## What this project is

Tarang's Claude Code harness configuration — the dotfiles-style layer over CC: hooks (`~/vault/scripts/`,
symlinked from `vault-scripts/`), skills (`~/.claude/skills/`, symlinked from `claude/skills/`), and the
**memory infrastructure** built on top (auto-memory corpus + review queue + quality rollup).

Deployment is **symlink-based** (no docker): `vault-scripts/<name>.sh` → `~/vault/scripts/<name>.sh`;
`claude/skills/<skill>/` → `~/.claude/skills/<skill>/`. The global `~/.claude/settings.json` wires hooks
(it is **not** version-controlled in this repo — a known gap).

Memory hook set: `memory-infer` (Stop, GLM-4.7 dialectic), `memory-validate` + `memory-consulted`
(PostToolUse Write|Edit / Read), `memory-staleness` (SessionStart). All non-blocking (`exit 0`).

## Current status (as of 2026-07-06)

- **Memory quality loop: CLOSED.** The 5-step loop (Write → Read → Test → Track → Improve) is built,
  merged to main (`03e9561`), and exercised end-to-end. `/memory health` rolls up capture/approval/
  utilization/corpus/hook-health; `/memory review` proposes advisory tweaks.
- **Built in two phases:** #1 dialectic infer loop + #2 temporal invalidation (2026-07-05), then the
  quality measurement layer Q1–Q5 (2026-07-06). See `PROJECT_ARC.md`.
- **Top finding (honest):** corpus is 193 files at **2% canonical-schema adoption** — staleness/overlap
  machinery has little to chew on. Addressing it = the deferred S3 safe-archive migration.

## Safety notes

- **Never commit** `~/.claude/settings.json` content into this repo — it carries `GEMINI_API_KEY`
  (`mcpServers.gemini-bridge.env`) and is global, not repo-tracked.
- `.gitignore` excludes `*.env`, `*secret*`, `*.pem`, `*.key`, `*-sa.json`, `*auth*.json`.
- `learning-detector.py` was deliberately disabled (2026-06-16); do not re-enable without a `/reflect`
  review habit.

## Key commands

| Want | Run |
|------|-----|
| Memory quality rollup | `python3 ~/.claude/skills/memory/scripts/memory_health.py` |
| Harness tweak proposals | `python3 ~/.claude/skills/memory/scripts/memory_review.py` |
| Apply/dismiss a candidate | `/reflect memory apply <N>` / `dismiss <N>` |
| Hook telemetry | `~/vault/scripts/infra-health` (or `/infra-health`) |
