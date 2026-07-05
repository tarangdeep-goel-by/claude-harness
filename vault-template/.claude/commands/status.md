# /status — Current Status Overview

Show me the current state of everything.

## Steps:
1. Read `System/dashboards/Open Items.md` (the active ledger)
2. Read today's daily note + the latest `System/handoffs/YYYY-MM-DD/_day.md` rollup
3. Check `Meta/agent-messages.md` for pending messages
4. List live parallel sessions from `~/vault/logs/active-sessions/*.json`
5. Scan recent notes (last 7 days) for open action items

## Output format:
```
## Status — [date]

### Active Initiatives
[from execution plan, with status indicators 🟢🟡🔴]

### Today's Focus
[from daily note todos]

### Blockers
[blocked items from execution plan]

### Pending Agent Messages
[any unresolved messages]

### Open Action Items
[from recent meeting notes and daily notes]
```
