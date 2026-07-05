---
name: warm
description: Refresh project intelligence mid-session. Use when context feels stale, after switching branches, or after pulling changes.
disable-model-invocation: true
allowed-tools: Bash
---

Refresh the project intelligence brief by running the warm-start script:

```bash
~/.claude/scripts/warm-start.sh <<< '{"source":"manual","cwd":"'"$(pwd)"'"}'
```

Read the output carefully. It contains the current git state, recent changes,
stack information, and learnings from previous sessions. Use this to re-orient
yourself on what the user is working on.

If the script errors or hangs (>60s): report the error verbatim, retry ONCE at
most, then re-orient manually instead — `git status` + `git log --oneline -10` +
the newest `System/handoffs/**` entry cover the same ground. Don't loop on the
script and don't silently skip re-orientation.

If the user passed arguments, focus your attention on: $ARGUMENTS
