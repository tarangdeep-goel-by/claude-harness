#!/bin/bash

###############################################################################
# Google Drive Setup (One-Time)
###############################################################################
#
# DESCRIPTION:
#   One-time setup for Google Drive integration via rclone.
#   After setup, use upload_to_gdrive.sh to upload project documents.
#
# USAGE:
#   ./setup_gdrive.sh
#
# REQUIRES:
#   rclone (auto-installed via Homebrew if missing)
#
###############################################################################

set -e

echo "Setting up Google Drive integration..."
echo ""
echo "This is a ONE-TIME setup for ALL projects."
echo ""

# Check if rclone is installed
if ! command -v rclone &> /dev/null; then
    echo "Installing rclone..."
    brew install rclone
    echo ""
fi

# Check if already configured
if rclone listremotes 2>/dev/null | grep -q "gdrive:"; then
    echo "Google Drive is already configured!"
    echo ""
    rclone listremotes
    echo ""
    echo "You can now upload files from any project:"
    echo "  $(dirname "$0")/upload_to_gdrive.sh <project-name>"
    echo ""
    exit 0
fi

echo "Starting Google Drive authentication..."
echo ""
echo "A browser window will open for you to:"
echo "  1. Sign in with your Google account"
echo "  2. Grant rclone access to Google Drive"
echo "  3. Return here when done"
echo ""
read -p "Press Enter to continue..."
echo ""

# Create the Google Drive remote with automatic browser authentication
rclone config create gdrive drive scope=drive

if [ $? -eq 0 ]; then
    echo ""
    echo "Google Drive setup complete!"
    echo ""
    echo "Commands available:"
    echo "  # Convert markdown to DOCX"
    echo "  $(dirname "$0")/convert_to_docx.sh <project-name>"
    echo ""
    echo "  # Upload to Google Drive"
    echo "  $(dirname "$0")/upload_to_gdrive.sh <project-name>"
    echo ""
else
    echo ""
    echo "Setup failed. Please try again."
    exit 1
fi
