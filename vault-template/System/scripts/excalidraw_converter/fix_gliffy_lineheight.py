#!/usr/bin/env python3
"""Fix line-height and text backgrounds in Gliffy JSON for draw.io import.

Usage:
    python3 fix_gliffy_lineheight.py <input.gliffy> <output.gliffy>

If no arguments given, prompts for file paths.
"""

import json
import re
import sys


def fix_line_height(gliffy_file, output_file):
    """Fix line-height in Gliffy JSON to prevent overlapping text in draw.io"""

    with open(gliffy_file, 'r') as f:
        data = json.load(f)

    def fix_html_line_height(html):
        """Replace line-height values with 1.2x the font size"""
        def replace_line_height(match):
            font_size = match.group(1)
            new_line_height = str(int(float(font_size) * 1.2))
            return f'font-size: {font_size}px; line-height: {new_line_height}px;'

        html = re.sub(
            r'font-size:\s*(\d+(?:\.\d+)?)px;\s*line-height:\s*\d+(?:\.\d+)?px;',
            replace_line_height,
            html
        )
        return html

    def fix_objects(obj):
        if isinstance(obj, dict):
            if 'graphic' in obj and isinstance(obj['graphic'], dict):
                if 'Text' in obj['graphic'] and isinstance(obj['graphic']['Text'], dict):
                    text_obj = obj['graphic']['Text']
                    if 'html' in text_obj:
                        text_obj['html'] = fix_html_line_height(text_obj['html'])

                if 'Shape' in obj['graphic'] and isinstance(obj['graphic']['Shape'], dict):
                    shape_obj = obj['graphic']['Shape']
                    if 'children' in obj and obj['children']:
                        shape_obj['fillColor'] = 'none'

                if 'Text' in obj['graphic'] and 'Shape' not in obj['graphic']:
                    if obj.get('uid') == 'com.gliffy.shape.basic.basic_v1.default.text':
                        obj['graphic']['Shape'] = {
                            'fillColor': 'none',
                            'strokeColor': 'none',
                            'strokeWidth': 0,
                            'opacity': 1
                        }

            if 'children' in obj and isinstance(obj['children'], list):
                for child in obj['children']:
                    fix_objects(child)

            for value in obj.values():
                if isinstance(value, (dict, list)):
                    fix_objects(value)

        elif isinstance(obj, list):
            for item in obj:
                fix_objects(item)

    if 'stage' in data and 'objects' in data['stage']:
        fix_objects(data['stage']['objects'])

    with open(output_file, 'w') as f:
        json.dump(data, f, indent=2)

    print(f"Fixed line heights and text backgrounds in {gliffy_file}")
    print(f"Output saved to {output_file}")


if __name__ == '__main__':
    if len(sys.argv) >= 3:
        fix_line_height(sys.argv[1], sys.argv[2])
    else:
        print("Usage: python3 fix_gliffy_lineheight.py <input.gliffy> <output.gliffy>")
        sys.exit(1)
