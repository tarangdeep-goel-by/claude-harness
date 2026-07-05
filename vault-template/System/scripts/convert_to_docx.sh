#!/bin/bash

###############################################################################
# Convert Markdown to DOCX for Vault Projects
###############################################################################
#
# DESCRIPTION:
#   Converts markdown files in a vault project directory to DOCX format.
#   Output goes to a docs/ subfolder within the project directory.
#
# USAGE:
#   ./convert_to_docx.sh <project-name>
#   ./convert_to_docx.sh ai-data-analyst
#
#   <project-name> must match a folder under Notes/ in the vault.
#
# SKIPS:
#   CLAUDE.md, PROJECT_LOG.md, README.md, GOOGLE_DRIVE_UPLOAD.md, *TEMPLATE*
#
# REQUIRES:
#   pandoc (auto-installed via Homebrew if missing)
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

if [ ! -d "$PROJECT_DIR" ]; then
    echo "Error: Project directory not found: $PROJECT_DIR"
    echo ""
    echo "Available projects:"
    ls -1 "$NOTES_DIR" 2>/dev/null | grep -v '^\.' || echo "  (none found)"
    exit 1
fi

# Check if pandoc is installed
if ! command -v pandoc &> /dev/null; then
    echo "pandoc is not installed. Installing via Homebrew..."
    brew install pandoc
fi

# Create docs output directory
DOCS_DIR="$PROJECT_DIR/docs"
mkdir -p "$DOCS_DIR"

echo "Converting markdown documents to DOCX..."
echo "Project: $PROJECT_NAME"
echo "Source:  $PROJECT_DIR"
echo "Output:  $DOCS_DIR"
echo ""

# Track conversion count
CONVERTED=0

# Find and convert all markdown files
for MD_FILE in "$PROJECT_DIR"/*.md; do
    # Skip if no .md files found
    [ -e "$MD_FILE" ] || continue

    FILENAME=$(basename "$MD_FILE")

    # Skip specific files
    if [[ "$FILENAME" == "CLAUDE.md" ]] || \
       [[ "$FILENAME" == "PROJECT_LOG.md" ]] || \
       [[ "$FILENAME" == "README.md" ]] || \
       [[ "$FILENAME" == "GOOGLE_DRIVE_UPLOAD.md" ]] || \
       [[ "$FILENAME" == *"TEMPLATE"* ]]; then
        continue
    fi

    # Get base filename without extension
    BASE_NAME="${FILENAME%.md}"

    # Add project name prefix if not already present
    if [[ "$BASE_NAME" == "$PROJECT_NAME - "* ]]; then
        DOCX_FILE="${BASE_NAME}.docx"
    else
        DOCX_FILE="${PROJECT_NAME} - ${BASE_NAME}.docx"
    fi

    DOCX_PATH="$DOCS_DIR/$DOCX_FILE"

    echo "  Converting: $FILENAME -> $DOCX_FILE"
    pandoc "$MD_FILE" -o "$DOCX_PATH"

    SIZE=$(ls -lh "$DOCX_PATH" | awk '{print $5}')
    echo "  Created: $DOCX_FILE ($SIZE)"
    echo ""

    ((CONVERTED++))
done

if [ $CONVERTED -eq 0 ]; then
    echo "No markdown files found to convert in $PROJECT_DIR"
    echo "(Excluding CLAUDE.md, PROJECT_LOG.md, README.md, templates)"
    exit 1
fi

echo "Converted $CONVERTED document(s)"
echo "DOCX files saved in: $DOCS_DIR"
echo ""
echo "Next steps:"
echo "  Upload to Google Drive: $(dirname "$0")/upload_to_gdrive.sh $PROJECT_NAME"
