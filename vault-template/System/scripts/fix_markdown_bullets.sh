#!/bin/bash

###############################################################################
# Markdown Bullet List Fixer for Pandoc DOCX Conversion
###############################################################################
#
# DESCRIPTION:
#   Fixes markdown files by adding empty lines between headings and bullet lists.
#   This ensures proper DOCX conversion via pandoc.
#
# USAGE:
#   ./fix_markdown_bullets.sh [directory]
#
#   If no directory specified, fixes all .md files in current directory.
#
# WHAT IT FIXES:
#   - Bold headings followed by bullets (**Heading:** -> bullets)
#   - All heading levels followed by bullets (# ## ### etc.)
#   - Ensures empty line exists between heading and list
#
# SKIPS:
#   CLAUDE.md, README.md, GEMINI.md, *TEMPLATE* files, and vault system files
#
###############################################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Determine target directory
TARGET_DIR="${1:-.}"

echo -e "${GREEN}========================================================${NC}"
echo -e "${GREEN}  Markdown Bullet List Fixer for Pandoc Conversion${NC}"
echo -e "${GREEN}========================================================${NC}"
echo ""
echo -e "${BLUE}Target directory:${NC} $TARGET_DIR"
echo ""

# Create backup directory
BACKUP_DIR="${TARGET_DIR}/.markdown_backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
echo -e "${YELLOW}Backups will be saved to:${NC} $BACKUP_DIR"
echo ""

# Counter for files processed
FILES_PROCESSED=0
FILES_FIXED=0
FILES_SKIPPED=0

# Find all markdown files (excluding certain patterns)
while IFS= read -r -d '' file; do
    # Skip if it's in the backup directory
    if [[ "$file" == *"/.markdown_backup_"* ]]; then
        continue
    fi

    # Skip certain files (vault system files included)
    filename=$(basename "$file")
    if [[ "$filename" == "README.md" ]] || \
       [[ "$filename" == *"TEMPLATE"* ]] || \
       [[ "$filename" == "CLAUDE.md" ]] || \
       [[ "$filename" == "GEMINI.md" ]] || \
       [[ "$filename" == "PROJECT_LOG.md" ]] || \
       [[ "$filename" == "PLANNER.md" ]] || \
       [[ "$filename" == "PROJECT_STATUS.md" ]] || \
       [[ "$filename" == "DEVELOPMENT_WORKFLOW.md" ]]; then
        echo -e "${YELLOW}Skipping:${NC} $file"
        ((FILES_SKIPPED++))
        continue
    fi

    echo -e "${BLUE}Processing:${NC} $file"

    # Create backup
    cp "$file" "$BACKUP_DIR/$(basename "$file")"

    # Create temporary file for output
    TEMP_FILE="${file}.tmp"

    # Process the file with awk
    awk '
    # Track previous line
    {
        if (NR > 1) {
            # Check if previous line was a heading and current line is a bullet
            if (prev_line ~ /^(#+ |.*\*\*.*:\*\*$)/ && $0 ~ /^[[:space:]]*[-*+]/) {
                # Insert empty line between heading and bullet
                print prev_line
                print ""
                print $0
                prev_line = ""
                next
            } else if (prev_line != "") {
                print prev_line
            }
        }
        prev_line = $0
    }
    END {
        if (prev_line != "") {
            print prev_line
        }
    }
    ' "$file" > "$TEMP_FILE"

    # Check if file was modified
    if ! cmp -s "$file" "$TEMP_FILE"; then
        mv "$TEMP_FILE" "$file"
        echo -e "${GREEN}Fixed:${NC} $file"
        ((FILES_FIXED++))
    else
        rm "$TEMP_FILE"
        echo -e "${BLUE}No changes needed:${NC} $file"
    fi

    ((FILES_PROCESSED++))
    echo ""

done < <(find "$TARGET_DIR" -type f -name "*.md" -print0)

# Summary
echo -e "${GREEN}========================================================${NC}"
echo -e "${GREEN}  Processing Complete!${NC}"
echo -e "${GREEN}========================================================${NC}"
echo ""
echo -e "${BLUE}Files processed:${NC} $FILES_PROCESSED"
echo -e "${GREEN}Files fixed:${NC}     $FILES_FIXED"
echo -e "${YELLOW}Files skipped:${NC}   $FILES_SKIPPED"
echo ""
echo -e "${YELLOW}Backups saved to:${NC} $BACKUP_DIR"
echo ""

if [ $FILES_FIXED -gt 0 ]; then
    echo -e "${GREEN}Ready for pandoc DOCX conversion!${NC}"
else
    echo -e "${BLUE}All files already correctly formatted.${NC}"
fi
echo ""
