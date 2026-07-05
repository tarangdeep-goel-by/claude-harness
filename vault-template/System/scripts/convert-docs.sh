#!/bin/bash
# convert-docs.sh — Convert documents in docs-inbox to Markdown using markitdown
#
# Usage:
#   convert-docs.sh                  # Convert all files in docs-inbox
#   convert-docs.sh <file>           # Convert a specific file
#
# Supported: PDF, DOCX, PPTX, XLSX, images, HTML, CSV, JSON, XML, ZIP, EPUB

set -euo pipefail

VAULT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
INBOX="$VAULT_DIR/System/docs-inbox"

# Check markitdown is installed
if ! command -v markitdown &>/dev/null; then
  echo "Error: markitdown not found."
  echo "Install: pip install 'markitdown[all]'"
  exit 1
fi

convert_file() {
  local input="$1"
  local basename="${input%.*}"
  local output="${basename}.md"

  if [ -f "$output" ]; then
    echo "  ✓ $(basename "$input") (already converted)"
    return
  fi

  echo "  Converting: $(basename "$input")"
  markitdown "$input" > "$output" 2>/dev/null

  if [ -s "$output" ]; then
    echo "  ✓ → $(basename "$output") ($(wc -l < "$output") lines)"
  else
    rm -f "$output"
    echo "  ✗ Failed to convert $(basename "$input")"
  fi
}

if [ $# -ge 1 ]; then
  # Convert specific file
  convert_file "$1"
else
  # Convert all non-markdown files in docs-inbox
  echo "==> Converting docs in: $INBOX"
  CONVERTED=0

  for f in "$INBOX"/*; do
    [ -f "$f" ] || continue
    # Skip markdown, CLAUDE.md, hidden files
    case "$f" in
      *.md|*.DS_Store) continue ;;
    esac
    convert_file "$f"
    ((CONVERTED++))
  done

  if [ $CONVERTED -eq 0 ]; then
    echo "  No files to convert."
  else
    echo "==> Converted $CONVERTED file(s)"
  fi
fi
