#!/usr/bin/env bash
# setup-telemetry-sink.sh — MAINTAINER, run once. Creates the shared Drive folder that
# adopters' `infra-health` skill uploads to, using rclone (your own `gdrive:` remote —
# no Google Cloud client to set up). The folder is created IN YOUR OWN Drive, so you own it
# and always have access.
#
# rclone can't set Drive sharing, so the ONE manual step is sharing the folder with your
# team (Drive UI → Share → Editor, or "anyone in <org> with link → Editor").
#
# Usage:  ./setup-telemetry-sink.sh [--remote gdrive] [--name harness-telemetry]
set -uo pipefail

REMOTE="gdrive"; FOLDER_NAME="harness-telemetry"
while [ $# -gt 0 ]; do
  case "$1" in
    --remote) REMOTE="${2:?}"; shift ;;
    --name)   FOLDER_NAME="${2:?}"; shift ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done

command -v rclone >/dev/null 2>&1 || { echo "✗ rclone not installed." >&2; exit 1; }
rclone listremotes 2>/dev/null | grep -qx "${REMOTE}:" || {
  echo "✗ rclone remote '${REMOTE}:' not found. Run: rclone config  (type 'drive', browser OAuth)." >&2
  exit 1
}

# Create (idempotent) and fetch the folder's Drive ID.
rclone mkdir "${REMOTE}:${FOLDER_NAME}" 2>/dev/null || true
FOLDER_ID="$(rclone lsf --dirs-only --format "ip" --max-depth 1 "${REMOTE}:" 2>/dev/null \
             | awk -F';' -v n="${FOLDER_NAME}/" '$2==n {print $1; exit}')"
[ -n "$FOLDER_ID" ] || { echo "✗ couldn't create/find folder '${FOLDER_NAME}' on ${REMOTE}:" >&2; exit 1; }
echo "✓ folder '${FOLDER_NAME}'  id=$FOLDER_ID  (owned by you)"

cat <<EOF

── NEXT: share it with your team (one manual step — rclone can't set permissions) ──
  https://drive.google.com/drive/folders/$FOLDER_ID
  → Share → add your team (or "anyone in <org> with the link") as **Editor**

── Then hand adopters this config (append to ~/.claude/harness-telemetry.conf) ──
DRIVE_FOLDER=$FOLDER_ID
RCLONE_REMOTE=$REMOTE
OPERATOR=your.name@company.com   # who this machine is — so fixes can be directed to you

Adopters also need their own rclone drive remote once:  rclone config  (no Cloud key needed).
Read incoming telemetry with:  ./collate-telemetry.sh --folder $FOLDER_ID
EOF
