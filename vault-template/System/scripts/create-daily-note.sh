#!/bin/bash
# Create today's daily note if it doesn't exist

VAULT_DIR="${VAULT_DIR:-$HOME/Documents/vault-work}"
TODAY=$(date +%Y-%m-%d)
DAY_DIR="$VAULT_DIR/Daily/$TODAY"
NOTE="$DAY_DIR/$TODAY.md"

mkdir -p "$DAY_DIR"

if [ -f "$NOTE" ]; then
  exit 0
fi

DAY_NAME=$(date +"%A")

cat > "$NOTE" << EOF
---
title: "$TODAY"
type: daily
created: "$TODAY"
---

# $TODAY, $DAY_NAME

## Todos
- [ ]

## Context / Scratchpad


## Meetings Today


## Action Items from Meetings


## End of Day
**What got done:**

**Carrying over to tomorrow:**

**Notes for future self:**
EOF

echo "Created: $NOTE"
