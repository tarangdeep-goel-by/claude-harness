#!/bin/bash

###############################################################################
# Upload DOCX Files to Google Drive for Vault Projects
###############################################################################
#
# DESCRIPTION:
#   Uploads DOCX files from a project's docs/ subfolder to Google Drive.
#   Creates a Google Drive folder named after the project.
#
# USAGE:
#   ./upload_to_gdrive.sh <project-name>
#   ./upload_to_gdrive.sh ai-data-analyst
#
# REQUIRES:
#   rclone with gdrive remote configured (see setup_gdrive.sh)
#
###############################################################################

set -e

VAULT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
NOTES_DIR="$VAULT_ROOT/Notes"

# Check args
if [ -z "$1" ]; then
    echo "Usage: $0 <project-name>"
    echo ""
    echo "Available projects:"
    ls -1 "$NOTES_DIR" 2>/dev/null | grep -v '^\.' || echo "  (none found)"
    exit 1
fi

PROJECT_NAME="$1"
PROJECT_DIR="$NOTES_DIR/$PROJECT_NAME"
DOCS_DIR="$PROJECT_DIR/docs"

if [ ! -d "$PROJECT_DIR" ]; then
    echo "Error: Project directory not found: $PROJECT_DIR"
    exit 1
fi

echo "Uploading documents to Google Drive..."
echo "Project: $PROJECT_NAME"
echo ""

# Check if rclone is configured
if ! rclone listremotes | grep -q "gdrive:"; then
    echo "Google Drive not configured yet!"
    echo ""
    echo "Run this first:"
    echo "  $(dirname "$0")/setup_gdrive.sh"
    echo ""
    exit 1
fi

# Check if docs directory exists with DOCX files
if [ ! -d "$DOCS_DIR" ]; then
    echo "No docs/ directory found at: $DOCS_DIR"
    echo ""
    echo "Run this first to create DOCX files:"
    echo "  $(dirname "$0")/convert_to_docx.sh $PROJECT_NAME"
    echo ""
    exit 1
fi

DOCX_FILES=("$DOCS_DIR"/*.docx)

if [ ! -e "${DOCX_FILES[0]}" ]; then
    echo "No DOCX files found in: $DOCS_DIR"
    echo ""
    echo "Run this first:"
    echo "  $(dirname "$0")/convert_to_docx.sh $PROJECT_NAME"
    echo ""
    exit 1
fi

# Upload each DOCX file
UPLOADED=0
for DOCX_FILE in "$DOCS_DIR"/*.docx; do
    [ -e "$DOCX_FILE" ] || continue

    FILENAME=$(basename "$DOCX_FILE")
    echo "  Uploading: $FILENAME"
    rclone copy "$DOCX_FILE" gdrive:"$PROJECT_NAME" -P --stats-one-line
    echo "  Uploaded to: $PROJECT_NAME/$FILENAME"
    echo ""

    ((UPLOADED++))
done

echo "Uploaded $UPLOADED document(s) to Google Drive"
echo "Files available at: Google Drive > $PROJECT_NAME"
echo ""
echo "Access your files: https://drive.google.com"
