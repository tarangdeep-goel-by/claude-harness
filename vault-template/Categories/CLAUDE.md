# Categories

Bases views that cut across projects by **type** (what the note IS). These provide cross-project navigation — notes live in `Daily/` or `Notes/<project>/`, not here.

Each file here is a Bases view that queries all notes linking to it via the `categories` frontmatter property.

**Rules:**
- These are navigation views, NOT storage — notes do not live here
- Each view defines one note type
- A note can belong to multiple categories
- Do not create new categories without user approval
