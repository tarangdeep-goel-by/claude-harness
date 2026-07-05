#!/bin/bash
# transcribe.sh — Convert audio to text using whisper-cpp with VAD
#
# Usage:
#   transcribe.sh <audio-file>           # Transcribe to text file next to audio
#   transcribe.sh <audio-file> <output>  # Transcribe to specific output path
#
# Supports: m4a, mp3, wav, ogg, aac, mp4, webm

set -euo pipefail

WHISPER_MODEL="${WHISPER_MODEL:-$HOME/.local/share/whisper-models/ggml-large-v3-turbo.bin}"
VAD_MODEL="${VAD_MODEL:-$HOME/.local/share/whisper-models/ggml-silero-v6.2.0.bin}"
THREADS="${WHISPER_THREADS:-8}"

if [ $# -lt 1 ]; then
  echo "Usage: transcribe.sh <audio-file> [output-path]"
  exit 1
fi

INPUT="$1"
BASENAME="${INPUT%.*}"
OUTPUT="${2:-${BASENAME}_transcript.txt}"
WAV_TMP="${BASENAME}_16k.wav"

if [ ! -f "$INPUT" ]; then
  echo "Error: File not found: $INPUT"
  exit 1
fi

# Check dependencies
command -v ffmpeg >/dev/null 2>&1 || { echo "Error: ffmpeg not found. Install with: brew install ffmpeg"; exit 1; }
command -v whisper-cli >/dev/null 2>&1 || { echo "Error: whisper-cli not found. Install with: brew install whisper-cpp"; exit 1; }
[ -f "$WHISPER_MODEL" ] || { echo "Error: Whisper model not found at $WHISPER_MODEL"; exit 1; }
[ -f "$VAD_MODEL" ] || { echo "Error: VAD model not found at $VAD_MODEL"; exit 1; }

echo "==> Converting to 16kHz mono WAV..."
ffmpeg -y -i "$INPUT" -ar 16000 -ac 1 -c:a pcm_s16le "$WAV_TMP" 2>/dev/null

echo "==> Transcribing with whisper-cpp (VAD enabled)..."
whisper-cli \
  -m "$WHISPER_MODEL" \
  -f "$WAV_TMP" \
  -l auto \
  -t "$THREADS" \
  --vad \
  -vm "$VAD_MODEL" \
  --no-context \
  -et 2.0 \
  --output-txt \
  -of "${OUTPUT%.txt}" \
  2>/dev/null

# Clean up temp WAV
rm -f "$WAV_TMP"

echo "==> Done: $OUTPUT"
echo "Lines: $(wc -l < "$OUTPUT")"
