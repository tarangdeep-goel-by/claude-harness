# /new-project — Create a New Project

Scaffold a complete project folder with all standard subfolders and starter files.

## Steps:

### 1. Ask for project details (skip what's already provided):
- **Project name** (will be used as folder name, kebab-case)
- **One-line description**
- **Which subjects does it relate to?** (Product Strategy, Growth & Metrics, Engineering, etc.)

### 2. Create the project structure:

```bash
Notes/<project-name>/
├── README.md
├── KNOWLEDGE_BASE.md
├── PROJECT_LOG.md
├── decisions/
├── research/
├── supporting_docs/
├── docs/
└── meetings/
```

> **Doc-type contract** (see `CLAUDE.md` → Knowledge-base conventions): `KNOWLEDGE_BASE.md` is durable
> **fundamentals only** (what it is + how it works) — no metrics, no status. Findings → `research/`;
> rationale → `decisions/`; status/history → `PROJECT_LOG`/`PROJECT_ARC`; instrumentation → skills.

### 3a. Create KNOWLEDGE_BASE.md:
Use `System/templates/knowledge-base.md`. Leave the section scaffolding; it gets filled as the project's
durable fundamentals become clear. (It can start near-empty — the point is the home exists from day one.)

### 3. Populate README.md:
Use the Project README template from `System/templates/Project README.md`. Fill in:
- Title from project name
- Description from one-liner
- Subjects from user input
- Owner: (from Meta/memory.md — your name)
- Status: active
- Created date: today

### 4. Populate PROJECT_LOG.md:
Use the Project Log template from `System/templates/Project Log.md`. Add initial entry:
```
### [today's date] — Project Created

**Context:** New project scaffolded

**Discussed:**
- Project created with initial structure

**Next:**
- Fill in README overview and problem statement
- Gather supporting docs
```

### 5. Create empty subfolders:
Create placeholder `.gitkeep` files in each subfolder so they're tracked:
- `decisions/.gitkeep`
- `research/.gitkeep`
- `supporting_docs/.gitkeep`
- `docs/.gitkeep`
- `meetings/.gitkeep`

### 6. Create NotebookLM notebook:
Create a matching NotebookLM notebook for this project:
```bash
nlm notebook create "<Project Name>"
```
Save the notebook ID in the project's README.md under Links.
This notebook will be used for source-grounded Q&A and audio overviews.

### 7. Report:
Show the user the created structure and suggest next steps:
- Fill in the README with problem statement, goals, team
- Start collecting supporting docs
- Begin Phase 0 (One Pager) if ready
- NotebookLM notebook created — add sources as the project grows
