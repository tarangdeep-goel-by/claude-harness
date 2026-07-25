#!/usr/bin/env bash
# bootstrap.sh — install the dependencies the harness relies on. Best-effort:
# reports what's missing rather than failing hard. Run AFTER install.sh.
set -uo pipefail

echo "== claude-harness bootstrap =="
# --check: report missing deps and install NOTHING (safe to run anywhere, incl. CI).
CHECK=""; [ "${1:-}" = "--check" ] && { CHECK=1; echo "(--check: report-only, installs nothing)"; }

# Homebrew (macOS) — used for jq.
if ! command -v brew >/dev/null 2>&1; then
  echo "⚠ Homebrew not found. Install from https://brew.sh then re-run."
fi

# jq — required by warm-start.sh.
if command -v jq >/dev/null 2>&1; then
  echo "✓ jq: $(jq --version)"
elif [ -n "$CHECK" ]; then
  echo "▶ jq MISSING (would: brew install jq)"
else
  echo "▶ installing jq…"; brew install jq || echo "⚠ install jq manually"
fi

# python3 — required by hook scripts.
command -v python3 >/dev/null 2>&1 && echo "✓ python3: $(python3 --version)" || echo "⚠ python3 missing"

# qmd — the hybrid search engine that indexes the vaults. Custom binary (not brew/pip).
if command -v qmd >/dev/null 2>&1; then
  echo "✓ qmd: present"
  echo "  ensure ~/.config/qmd/index.yml lists the collections (see vault System/docs/WORK_MACHINE_SETUP.md)"
else
  echo "⚠ qmd not found — install it and configure ~/.config/qmd/index.yml."
  echo "  recall + vault-push + session-export all degrade gracefully without it, but search won't work."
fi

# gh — used by /dev-task (PR → CI → merge).
command -v gh >/dev/null 2>&1 && echo "✓ gh: $(gh --version | head -1)" || echo "⚠ gh (GitHub CLI) missing — /dev-task needs it"

# Python libs used by harness scripts (best-effort).
python3 -c "import requests" 2>/dev/null && echo "✓ python: requests" || echo "▶ pip install requests"

echo ""
echo "▶ When done, run ./verify-setup.sh to confirm the harness is wired and spot silent gaps."
echo ""
echo "Day-0 still needs (NOT automated — see README 'Day-0 tools & access' + WORK_MACHINE_SETUP.md):"
echo "  • clone your data/analysis repos under ~/code/ and set up their venvs"
echo "  • connect claude.ai MCP connectors: Slack, Linear, or others (then RESTART — MCP loads at session start)"
echo "  • copy creds into ~/code/.env (your analytics API keys, if any)"
echo ""
echo "Done. Restart Claude Code so the hooks in ~/.claude/settings.json reload."
