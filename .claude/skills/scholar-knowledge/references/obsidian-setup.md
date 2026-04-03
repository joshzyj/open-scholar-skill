# Obsidian Setup Guide for Scholar Knowledge Wiki

The compiled wiki (`~/.claude/scholar-knowledge/wiki/`) is designed to be opened as an Obsidian vault. This guide covers setup, recommended plugins, and usage tips.

## Quick Start

1. **Install Obsidian**: `brew install --cask obsidian` (macOS) or download from [obsidian.md](https://obsidian.md)
2. **Open vault**: In Obsidian → "Open folder as vault" → press `Cmd+Shift+G` → type `~/.claude/scholar-knowledge/wiki`
3. **Alternative**: Create a symlink for easier access:
   ```bash
   ln -s ~/.claude/scholar-knowledge/wiki ~/Desktop/scholar-wiki
   ```
   Then open `~/Desktop/scholar-wiki` as your vault.

## Recommended Obsidian Settings

### Core Settings
- **Files & Links → Detect all file extensions**: ON
- **Files & Links → Default location for new notes**: "In the folder specified below" → `answers/`
- **Files & Links → Use [[Wikilinks]]**: ON (already the default)
- **Editor → Readable line length**: ON

### Core Plugins to Enable
- **Graph view** (`Cmd+G`): Visual network of papers ↔ concepts ↔ topics
- **Backlinks**: See which papers reference a concept (shown in sidebar)
- **Outgoing links**: See what a paper page links to
- **Quick switcher** (`Cmd+O`): Jump to any page by typing part of its name
- **Search** (`Cmd+Shift+F`): Full-text search across all wiki pages
- **Tags**: If you add `#topic/segregation` tags to pages

### Recommended Community Plugins
- **Dataview**: Query wiki pages as a database (e.g., "show all papers from 2020+ using DiD")
- **Graph Analysis**: Advanced graph metrics (centrality, clustering)
- **Breadcrumbs**: Navigate paper → concept → topic hierarchies
- **Calendar**: View papers by ingest date
- **Kanban**: Organize research tasks (pairs well with `answers/` for Q&A tracking)

## Graph View Configuration

Open Graph View (`Cmd+G`), then configure:

### Filters
- **Tags**: Show/hide by tag
- **Orphans**: Toggle to find isolated papers (candidates for relationship mapping)

### Groups (color by node type)
Add groups to color-code nodes:
1. **Papers** (blue): Path contains `papers/`
2. **Concepts** (red): Path contains `concepts/`
3. **Topics** (green): Path contains `topics/`
4. **Answers** (yellow): Path contains `answers/`
5. **Aggregates** (purple): Files named `contradictions`, `gaps`, `index`

### Display
- **Node size**: By number of links (highlights well-connected papers)
- **Arrow**: ON (shows relationship direction)
- **Line thickness**: By number of connections

## Usage Patterns

### Browse the research landscape
1. Open `index.md` — the dashboard
2. Click a topic (e.g., `[[residential-segregation]]`) to see all papers
3. Click a paper to see its findings, theories, methods
4. Use backlinks to see what cites or extends it

### Find connections
1. Open Graph View (`Cmd+G`)
2. Search for a concept — it highlights in the graph
3. Papers connected to it are visible as linked nodes
4. Identify bridge papers (connecting two topic clusters)

### Ask research questions
1. Run `/scholar-knowledge ask [question]` in Claude Code
2. Answer is saved to `wiki/answers/`
3. Open in Obsidian — backlinks show which papers were consulted
4. The answer becomes part of the wiki for future reference

### Track research progress
1. `wiki/gaps.md` shows what remains unstudied
2. `wiki/contradictions.md` shows debated findings
3. `wiki/answers/` shows questions you've explored
4. Graph View shows coverage: dense clusters = well-studied; sparse areas = gaps

## Directory Structure

```
wiki/
├── index.md              ← Start here: dashboard with stats and links
├── knowledge-map.png     ← Visual network graph (if generated)
├── contradictions.md     ← Contested findings
├── gaps.md               ← Research gaps and future directions
├── papers/               ← One page per paper (670+ files)
│   ├── fiel-zhang-2017.md
│   └── massey-denton-1993.md
├── concepts/             ← One page per theory/method/mechanism
│   ├── spatial-assimilation.md
│   └── diff-in-diff.md
├── topics/               ← Auto-clustered topic pages
│   ├── residential-segregation.md
│   └── immigration.md
└── answers/              ← Q&A archive (grows with each /scholar-knowledge ask)
    └── competing-explanations-segregation-2026-04-03.md
```

## Keeping the Wiki Updated

The wiki is auto-maintained by Claude Code:
- **After each ingest**: Paper pages, concept pages, and `index.md` are updated automatically (Step 1.10)
- **Full rebuild**: Run `/scholar-knowledge compile full` to regenerate everything (topic clusters, contradictions, gaps, visualizations)
- **Incremental rebuild**: Run `/scholar-knowledge compile` — only processes papers added since last compile

You should rarely need to edit wiki pages directly. If you do make manual edits, they will be preserved during incremental updates but may be overwritten during a full rebuild.
