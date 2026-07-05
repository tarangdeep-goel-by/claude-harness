#!/usr/bin/env bash
# qmd-recall.sh — proves the SEARCH SPINE end-to-end: a seeded markdown doc gets indexed, embedded,
# and surfaced by BOTH `qmd search` (BM25) and `qmd query` (semantic). Also sanity-checks the global
# index.yml the setup writes. This is the /recall value-prop the CI clean-room can't cover (CI has no
# qmd; models are ~2GB). LOCAL / opt-in — run on a machine with qmd installed:  bash evals/qmd-recall.sh
# Isolation: uses a throwaway project-local index (`qmd init`) so the global index is never touched.
set -uo pipefail
FAIL=0
chk(){ if [ "$2" = 0 ]; then printf '  ✓ %s\n' "$1"; else printf '  ✗ %s\n' "$1"; FAIL=1; fi; }
command -v qmd >/dev/null 2>&1 || { echo "SKIP: qmd not installed — this is a local-only eval"; exit 0; }

VAULT="${1:-$HOME/Documents/vault-work}"

echo "== isolated index: seed → index → embed → recall =="
T="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/qmd-recall.XXXXXX")" && pwd -P)"; cd "$T"
printf '# Widget Pricing Analysis\nQMDRECALLMARKER region A averages higher; recommend tiered pricing across the northeast corridor.\n' > doc.md
qmd init >/dev/null 2>&1
qmd collection add . >/dev/null 2>&1
qmd update >/dev/null 2>&1
qmd embed >/dev/null 2>&1
vec=$(qmd status 2>/dev/null | grep -oE 'Vectors:[[:space:]]*[0-9]+' | grep -oE '[0-9]+' || echo 0)
[ "${vec:-0}" -ge 1 ]; chk "embeddings generated (Vectors >= 1)" $?
qmd search "QMDRECALLMARKER" 2>/dev/null | grep -q "doc.md\|QMDRECALLMARKER"; chk "qmd search (BM25) surfaces the seeded doc" $?
qmd query "widget pricing tiered northeast corridor" 2>/dev/null | grep -q "doc.md\|Widget Pricing"; chk "qmd query (semantic) surfaces the seeded doc" $?
cd /; rm -rf "$T"

echo "== global index.yml the setup writes actually resolves =="
if [ -f "$HOME/.config/qmd/index.yml" ]; then
  ( cd "$HOME" && qmd collection list 2>/dev/null ) | grep -q "sessions"; chk "global index resolves the 'sessions' collection" $?
else
  echo "  (no ~/.config/qmd/index.yml — run setup-work-machine.sh first; skipping)"
fi

echo
if [ "$FAIL" = 0 ]; then echo "✓ qmd-recall PASSED"; else echo "✗ qmd-recall FAILED"; exit 1; fi
