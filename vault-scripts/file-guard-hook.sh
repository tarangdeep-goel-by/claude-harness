#!/bin/bash
# Claude Code PreToolUse hook: blocks access to sensitive files.
# Reads JSON on stdin with tool_name and tool_input.
# Returns JSON with permissionDecision: "deny" if blocked, or allows through.
set -euo pipefail

INPUT=$(cat)

# Extract tool name and file path
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""')
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // ""')

# Fast exit: only check file-related tools
case "$TOOL_NAME" in
  Read|Write|Edit) ;;
  *) exit 0 ;;
esac

# Fast exit: no file path
[ -z "$FILE_PATH" ] && exit 0

# Normalize: expand ~ and resolve to basename for pattern matching
BASENAME=$(basename "$FILE_PATH")
EXPANDED="${FILE_PATH/#\~/$HOME}"

# --- Sensitive file patterns ---
BLOCKED=false
REASON=""

# Exact basenames
case "$BASENAME" in
  .env|.env.local|.env.production|.env.staging|.env.development)
    BLOCKED=true; REASON="environment file: $BASENAME" ;;
  id_rsa|id_ed25519|id_ecdsa|id_dsa)
    BLOCKED=true; REASON="SSH private key: $BASENAME" ;;
  credentials.json|credentials.yaml|credentials.yml)
    BLOCKED=true; REASON="credentials file: $BASENAME" ;;
  .netrc|.npmrc)
    BLOCKED=true; REASON="auth config: $BASENAME" ;;
  secrets.yaml|secrets.yml|secrets.json)
    BLOCKED=true; REASON="secrets file: $BASENAME" ;;
esac

# Extension patterns
if [ "$BLOCKED" = "false" ]; then
  case "$BASENAME" in
    *.pem|*.key|*.p12|*.pfx|*.jks|*.keystore)
      BLOCKED=true; REASON="key/certificate file: $BASENAME" ;;
    service-account*.json)
      BLOCKED=true; REASON="service account key: $BASENAME" ;;
  esac
fi

# Sensitive directory patterns (check expanded path)
if [ "$BLOCKED" = "false" ]; then
  case "$EXPANDED" in
    */.ssh/*)
      BLOCKED=true; REASON="SSH directory" ;;
    */.gnupg/*)
      BLOCKED=true; REASON="GPG directory" ;;
    */.aws/credentials|*/.aws/config)
      BLOCKED=true; REASON="AWS credentials" ;;
    */.config/gcloud/*)
      BLOCKED=true; REASON="GCloud config directory" ;;
    */.docker/config.json)
      BLOCKED=true; REASON="Docker credentials" ;;
    */.kube/config)
      BLOCKED=true; REASON="Kubernetes config" ;;
  esac
fi

if [ "$BLOCKED" = "true" ]; then
  # Log denial to workflow audit trail
  LOG_FILE="$HOME/vault/logs/workflow.jsonl"
  mkdir -p "$(dirname "$LOG_FILE")"
  echo "{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"skill\":\"hook:file-guard\",\"project\":\"workspace\",\"task\":\"blocked $TOOL_NAME on $REASON\"}" >> "$LOG_FILE"

  jq -n --arg reason "🛡️ File Guard: blocked access to $REASON" \
    '{"decision": "deny", "reason": $reason}'
fi
