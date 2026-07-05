---
session_id: "{{sid}}"
date: {{date}}
project: {{project}}
type: dev | analysis | pm
branch: "{{branch}}"
worktree: "{{worktree}}"
goal: "{{one-line goal of this session}}"
status: shipped | in-progress | blocked
pr: "{{pr-url-if-any}}"
---

# Session {{sid}} — {{date}}

## What I did
- {{bullet per task/topic}}

## Decisions (+ why)
- {{decision — rationale}}

## State now / where to resume
- {{exactly where this left off so the next session can pick up}}

## Open threads
- [ ] {{unfinished item}}

## Artifacts
- scripts: {{paths}}
- research: {{Notes/<project>/research/<topic>.md}}
- PR / commit: {{url / sha}}
