# Excalidraw to Draw.io - Quick Start Guide

## One-Command Conversion

```bash
./excalidraw_to_drawio.sh MyDiagram.excalidraw
```

That's it! Your `MyDiagram.gliffy` file is ready to import.

---

## Step-by-Step

### 1. Convert

```bash
cd ~/Downloads
/path/to/excalidraw_converter/excalidraw_to_drawio.sh Profile.excalidraw
```

**Output:** `Profile.gliffy`

### 2. Import to Draw.io

1. Open **https://app.diagrams.net**
2. **File** -> **Import from** -> **Device**
3. Select `Profile.gliffy`
4. Done!

---

## What Gets Fixed Automatically

- **Text spacing** - No more overlapping text
- **Transparent backgrounds** - No white boxes on labels
- **Arrow labels** - Clean, transparent text on connections

---

## Custom Output Name

```bash
./excalidraw_to_drawio.sh input.excalidraw custom_name.gliffy
```

---

## Need Help?

**Script won't run?**
```bash
chmod +x excalidraw_to_drawio.sh
```

---

## Common Issues

| Issue | Solution |
|-------|----------|
| Text has white background | Use **draw.io online** (not desktop app) |
| Text still overlapping | Adjust the 1.2x multiplier in fix_gliffy_lineheight.py |
| File not found | Use full path: `~/Downloads/file.excalidraw` |

---

## Workflow Summary

```
Excalidraw -> Download -> Convert -> Import -> Edit in Draw.io
```

---

**Pro Tip:** Drag your `.excalidraw` file directly onto the Terminal window to auto-fill the path!

```bash
./excalidraw_to_drawio.sh [drag file here]
```
