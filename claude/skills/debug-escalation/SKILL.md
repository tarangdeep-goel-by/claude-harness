---
name: debug-escalation
description: "Use when encountering any bug, test failure, unexpected behavior, or error during development, before proposing or attempting fixes."
---

# Debugging with Escalation

## Process

### Phase 1: Understand Before Fixing

Do NOT propose a fix until you have:
1. Read the complete error message (full stack trace, exit code, line numbers)
2. Identified the failing line and the actual vs expected values
3. Traced backward through the call stack to find the origin of the bad value
4. Checked recent changes (`git diff`) that might have caused it

**If the user reports an error:** Ask for specific input/output before guessing.

### Phase 2: Single Hypothesis

1. Form ONE hypothesis: "I think X happens because Y"
2. Test with the SMALLEST possible change
3. Verify: did it work? Check the actual output.
4. If it didn't work, form a NEW hypothesis — do NOT layer another fix on top

### Phase 3: Escalation

**Track your fix attempts.** After each failed attempt, note what you tried and why it failed.

**After 3 failed fix attempts: STOP.**

This means your mental model is wrong. Do not attempt a 4th fix. Instead:

1. Summarize what you've tried and why each failed
2. State what this tells you about the actual problem
3. Ask: "This might be an architectural issue rather than a simple fix. Here's what I've found — how do you want to proceed?"

### Escalation Signals from User

If the user says any of these, change your approach IMMEDIATELY:
- "Stop guessing"
- "That's not it"
- "Try something different"
- "Why does this keep happening?"
- Any sign of frustration with repeated attempts

When you hear these: stop, summarize findings, ask for direction.

## Logging (MANDATORY)

When invoked, and on escalation (3rd failure), log via Bash:

```bash
echo '{"ts":"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'","skill":"debug-escalation","project":"<project>","attempt":<1|2|3>,"escalated":<true|false>,"task":"<brief description>"}' >> ~/vault/logs/workflow.jsonl
```

## Example Walkthrough

**Error:** `TypeError: Cannot read properties of undefined (reading 'map')` at `Dashboard.tsx:42`

**Phase 1 (Understand):**
- Line 42: `data.items.map(...)` — `data` is defined but `data.items` is undefined
- Check the API response shape — the endpoint returns `{ results: [...] }`, not `{ items: [...] }`
- `git diff` shows the API was recently changed from `items` to `results`

**Phase 2 (Hypothesis):**
- Hypothesis: "The frontend still expects `items` but the API now returns `results`"
- Smallest fix: change `data.items` to `data.results` on line 42
- Run the app → works

If instead the fix didn't work, form a NEW hypothesis — don't add a fallback on top.

## Anti-Patterns

| Pattern | Fix |
|---------|-----|
| Stacking fixes without verifying each | One change at a time, verify between each |
| "Let me try one more thing" after 3 failures | STOP. Escalate. |
| Guessing without reading the error | Read the full error message first |
| Changing multiple things at once | Isolate: one variable at a time |
| Assuming the fix worked without running it | Run the command. Read the output. |
