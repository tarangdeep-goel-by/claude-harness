#!/bin/bash

###############################################################################
# Excalidraw to Draw.io Converter Workflow
###############################################################################
#
# DESCRIPTION:
#   Converts Excalidraw diagrams to draw.io format with automatic formatting fixes:
#   - Adjusts line heights to prevent text overlap (1.2x multiplier)
#   - Makes all text backgrounds transparent
#   - Fixes arrow label backgrounds
#
# USAGE:
#   ./excalidraw_to_drawio.sh <input.excalidraw> [output.gliffy]
#
# EXAMPLES:
#   # Basic usage (output = input name with .gliffy extension)
#   ./excalidraw_to_drawio.sh MyDiagram.excalidraw
#
#   # Custom output name
#   ./excalidraw_to_drawio.sh MyDiagram.excalidraw CustomName.gliffy
#
# REQUIREMENTS:
#   - macOS with Homebrew
#   - Python 3 (pre-installed on macOS)
#   - excalidraw-converter (auto-installed by script)
#
# IMPORT TO DRAW.IO:
#   1. Go to https://app.diagrams.net
#   2. File -> Import from -> Device
#   3. Select your .gliffy file
#
# DOCUMENTATION:
#   See QUICK_START.md for quick reference
#
###############################################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if input file is provided
if [ -z "$1" ]; then
    echo -e "${RED}Error: No input file specified${NC}"
    echo "Usage: $0 <input.excalidraw> [output.gliffy]"
    echo "Example: $0 ~/Downloads/MyDiagram.excalidraw"
    exit 1
fi

INPUT_FILE="$1"

# Check if input file exists
if [ ! -f "$INPUT_FILE" ]; then
    echo -e "${RED}Error: File not found: $INPUT_FILE${NC}"
    exit 1
fi

# Determine output filename
if [ -z "$2" ]; then
    # If no output specified, use input filename with .gliffy extension
    OUTPUT_FILE="${INPUT_FILE%.excalidraw}.gliffy"
else
    OUTPUT_FILE="$2"
fi

TEMP_FILE="${OUTPUT_FILE%.gliffy}_temp.gliffy"

echo -e "${GREEN}===================================================${NC}"
echo -e "${GREEN}Excalidraw to Draw.io Converter${NC}"
echo -e "${GREEN}===================================================${NC}"
echo ""
echo -e "Input:  ${YELLOW}$INPUT_FILE${NC}"
echo -e "Output: ${YELLOW}$OUTPUT_FILE${NC}"
echo ""

# Step 1: Check if excalidraw-converter is installed
echo -e "${GREEN}[1/3]${NC} Checking for excalidraw-converter..."
if ! command -v exconv &> /dev/null; then
    echo -e "${YELLOW}excalidraw-converter not found. Installing...${NC}"
    brew install excalidraw-converter
else
    echo -e "${GREEN}OK${NC} excalidraw-converter is installed"
fi
echo ""

# Step 2: Convert Excalidraw to Gliffy format
echo -e "${GREEN}[2/3]${NC} Converting Excalidraw to Gliffy format..."
exconv gliffy -i "$INPUT_FILE" -o "$TEMP_FILE"
echo -e "${GREEN}OK${NC} Conversion complete"
echo ""

# Step 3: Fix line heights and make backgrounds transparent
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
echo -e "${GREEN}[3/3]${NC} Fixing line heights and text backgrounds..."

python3 "$SCRIPT_DIR/fix_gliffy_lineheight.py" "$TEMP_FILE" "$OUTPUT_FILE"

# Remove temporary file
rm -f "$TEMP_FILE"

echo -e "${GREEN}OK${NC} Line heights adjusted to 1.2x font size"
echo -e "${GREEN}OK${NC} Text backgrounds set to transparent"
echo ""

echo -e "${GREEN}===================================================${NC}"
echo -e "${GREEN}Conversion Complete!${NC}"
echo -e "${GREEN}===================================================${NC}"
echo ""
echo -e "Import into draw.io:"
echo -e "  1. Go to ${YELLOW}https://app.diagrams.net${NC}"
echo -e "  2. File -> Import from -> Device"
echo -e "  3. Select: ${YELLOW}$OUTPUT_FILE${NC}"
echo ""
