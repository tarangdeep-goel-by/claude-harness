#!/bin/bash
# record-meeting.sh — Record system audio (online meetings) via BlackHole
#
# Prerequisites:
#   1. BlackHole 2ch installed (brew install blackhole-2ch)
#   2. Multi-Output Device created in Audio MIDI Setup:
#      - Open Audio MIDI Setup (Cmd+Space → "Audio MIDI Setup")
#      - Click "+" → Create Multi-Output Device
#      - Check: MacBook Air Speakers (or your output) + BlackHole 2ch
#      - Set Multi-Output Device as system output (System Settings → Sound → Output)
#   3. ffmpeg installed (brew install ffmpeg)
#
# Usage:
#   record-meeting.sh                    # Start recording, Ctrl+C to stop
#   record-meeting.sh <name>             # Name the recording
#   record-meeting.sh --list-devices     # List available audio devices
#
# Output: ~/Documents/vault-work/Daily/YYYY-MM-DD/meeting_HHMMSS.m4a

set -euo pipefail

DAILY_DIR="$HOME/Documents/vault-work/Daily/$(date +%Y-%m-%d)"
TIMESTAMP=$(date +%H%M%S)

if [ "${1:-}" = "--list-devices" ]; then
  ffmpeg -f avfoundation -list_devices true -i "" 2>&1 | grep -E "^\[AVFoundation" | grep -i "audio"
  exit 0
fi

NAME="${1:-meeting}"
OUTPUT="$DAILY_DIR/${NAME}_${TIMESTAMP}.m4a"

# Ensure daily directory exists
mkdir -p "$DAILY_DIR"

# Find BlackHole device index
BH_INDEX=$(ffmpeg -f avfoundation -list_devices true -i "" 2>&1 | grep -i "blackhole" | head -1 | grep -oE '\[([0-9]+)\]' | tr -d '[]')

if [ -z "$BH_INDEX" ]; then
  echo "Error: BlackHole not found. Install with: brew install blackhole-2ch"
  echo "Then create a Multi-Output Device in Audio MIDI Setup."
  echo ""
  echo "Available audio devices:"
  ffmpeg -f avfoundation -list_devices true -i "" 2>&1 | grep -E "^\[AVFoundation" | grep -i "audio"
  exit 1
fi

echo "┌─────────────────────────────────────┐"
echo "│  Recording system audio             │"
echo "│  Device: BlackHole 2ch (index $BH_INDEX)    │"
echo "│  Output: ${NAME}_${TIMESTAMP}.m4a   │"
echo "│  Press Ctrl+C to stop               │"
echo "└─────────────────────────────────────┘"
echo ""

# Record from BlackHole — AAC encoding, mono, good quality
ffmpeg -f avfoundation -i ":$BH_INDEX" \
  -c:a aac -b:a 128k -ac 1 -ar 16000 \
  -y "$OUTPUT" \
  2>/dev/null

echo ""
echo "==> Saved: $OUTPUT"
echo "==> Size: $(du -h "$OUTPUT" | cut -f1)"
echo ""
echo "To transcribe:"
echo "  bash ~/Documents/vault-work/System/scripts/transcribe-whisperx.sh $OUTPUT"
