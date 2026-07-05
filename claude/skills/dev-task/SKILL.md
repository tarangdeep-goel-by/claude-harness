---
name: dev-task
description: "Run a code change end-to-end in an isolated git worktree: branch → build → test + /code-review + /verify → PR → watch CI → squash-merge on remote → cleanup → write the session handoff. Use for ANY code work in ~/code/* so parallel sessions never collide. Triggers: \"dev task\", \"make a change to <repo>\", \"fix/implement X in <repo>\", \"open a PR for\"."
---

# /dev-task — Worktree → PR → CI → Merge

**Rule: no code work on a repo's primary checkout.** Every dev task gets its own git worktree,
so the N parallel sessions you run never corrupt each other's working tree. We always test →
PR → check CI → merge on remote.

## Inputs
- **repo** (under `~/code/`), **goal** (one line), optional **branch slug**.
- If unclear, ask. Derive `<slug>` (kebab) and `<type>` ∈ `feature|fix|analysis|chore`.

## Steps

### 1. Scope + record
- Confirm repo, goal, branch `<type>/<slug>`.
- Stamp the session marker so `/start-work` and `/status` show this as a live dev session:
  ```bash
  # THIS session's id (the harness sets it). Prefer the env var — the cwd-match
  # fallback can pick a different parallel session sharing this cwd.
  SID="$CLAUDE_CODE_SESSION_ID"
  [ -z "$SID" ] && SID=$(ls ~/vault/logs/active-sessions/*.json 2>/dev/null | while read -r f; do
    python3 -c "import json;d=json.load(open('$f'));print(d['last_active_ts'],d['session_id'],d['cwd'])" 2>/dev/null
  done | awk -v cwd="$PWD" '$3==cwd' | sort -rn | head -1 | awk '{print $2}')
  # set type=dev, branch, goal on the marker (python edit of ~/vault/logs/active-sessions/$SID.json)
  ```

### 2. Create the worktree
```bash
REPO=~/code/<repo>; WT=~/code/<repo>-<slug>
git -C "$REPO" fetch origin
git -C "$REPO" worktree add "$WT" -b <type>/<slug> origin/<default-branch>
cd "$WT"
```
- One worktree = one session-task. The `auto-checkpoint` Stop hook keeps stashing per-worktree.

### 3. Build
- Make the change in `$WT`. Follow the repo's conventions (read its CLAUDE.md if present).

### 4. Verify locally (before pushing)
- Run the repo's tests (detect: `pytest`, `npm test`, etc.; ask if ambiguous).
- Run **`/code-review`** on the working diff and address findings.
- Run **`/verify`** for behavioral confirmation when the change is user-facing/runtime.
- Do not proceed to PR until tests pass and review is clean.

### 5. PR
```bash
git push -u origin <type>/<slug>
gh pr create --fill   # or --title/--body; include the goal + a test-plan line
```

### 6. Watch CI
```bash
gh pr checks <pr> --watch
```
- If red: read the failing job logs, fix in `$WT`, push, re-watch. **Bound the loop: 3 red
  cycles on the same failure → STOP.** Post the failing log excerpt + your current hypothesis and
  ask — endless fix-guessing burns CI minutes, and a failure that survives 3 targeted fixes is
  usually environmental or an approach problem, not a typo.

### 7. Merge on remote
```bash
gh pr merge <pr> --squash --delete-branch
```
- Only on green CI. Use `--squash` unless the repo convention differs.

### 8. Cleanup
```bash
cd "$REPO"
git worktree remove "$WT"
git -C "$REPO" checkout <default-branch> && git -C "$REPO" pull   # refresh primary checkout
```

### 9. Persist
- Record into this session's handoff (via `/vault-push`, project mode): branch, **PR URL**, and
  **merge SHA**, plus the goal/outcome. Set the marker `type: dev`.
- If a lib SHA bump is owed (step 3), add it to the Open Items inbox.

## Notes
- For purely parallel mechanical work, the Agent tool's `isolation: 'worktree'` achieves the same
  isolation inside a subagent — use that when fanning out; use this skill for the interactive
  single-task flow.
- Never `git push` to the default branch directly. Always via PR.
