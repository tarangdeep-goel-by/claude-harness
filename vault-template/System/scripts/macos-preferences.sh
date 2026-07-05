#!/bin/bash
# macos-preferences.sh — Starter template for macOS system preferences
#
# Customize and run on a new machine to apply your preferred macOS defaults.
# Usage:  bash System/scripts/macos-preferences.sh

set -euo pipefail

echo "==> Applying macOS preferences..."

# ── Trackpad ──────────────────────────────────────────────────────────────────
# defaults write NSGlobalDomain com.apple.trackpad.scaling -float 2.5
# defaults write com.apple.AppleMultitouchTrackpad Clicking -bool true  # Tap to click

# ── Dock ──────────────────────────────────────────────────────────────────────
# defaults write com.apple.dock autohide -bool true
# defaults write com.apple.dock orientation -string "right"
# defaults write com.apple.dock tilesize -int 48

# ── Finder ────────────────────────────────────────────────────────────────────
# defaults write com.apple.finder ShowPathbar -bool true

# ── Appearance ────────────────────────────────────────────────────────────────
# defaults write NSGlobalDomain AppleInterfaceStyle -string "Dark"

# ── Keyboard — disable autocorrect annoyances ─────────────────────────────────
# defaults write NSGlobalDomain NSAutomaticCapitalizationEnabled -bool false
# defaults write NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -bool false
# defaults write NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled -bool false
# defaults write NSGlobalDomain NSAutomaticDashSubstitutionEnabled -bool false
# defaults write NSGlobalDomain NSAutomaticPeriodSubstitutionEnabled -bool false

# ── Hot corners ───────────────────────────────────────────────────────────────
# defaults write com.apple.dock wvous-br-corner -int 11   # 11 = Launchpad
# defaults write com.apple.dock wvous-br-modifier -int 0

# Uncomment the lines you want, then restart affected services:
# killall Dock 2>/dev/null || true
# killall Finder 2>/dev/null || true

echo "==> Done. Uncomment and customize the settings you want above."
echo ""
echo "Tip: use 'defaults read <domain> <key>' to discover current values."
echo "Some changes require a logout or restart to take effect."
