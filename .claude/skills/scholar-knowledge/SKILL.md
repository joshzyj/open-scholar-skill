---
name: scholar-knowledge
description: >
  User-scoped, cross-project knowledge graph that persists extracted intellectual
  content (findings, mechanisms, theories, paper relationships) across projects
  and sessions. Layers on top of Zotero to provide richer content than raw
  bibliographic metadata. Eight modes: (1) INGEST — add papers from Zotero, PDF,
  lit-review output, DOI, or manual entry, extracting findings/theories/methods;
  (2) SEARCH — query the knowledge graph by topic, author, theory, method, or
  finding; (3) RELATE — add or view relationships between papers (cites,
  contradicts, extends, replicates, uses-method, uses-theory); (4) STATUS —
  show graph stats, recent additions, coverage by topic/method/theory;
  (5) EXPORT — export a project-specific subset as markdown or NDJSON;
  (6) COMPILE — generate a browsable Obsidian-compatible markdown wiki from
  the knowledge graph (paper pages, concept pages, topic clusters, contradiction
  map, research gaps); (7) ASK — answer complex research questions by reading
  the compiled wiki and saving answers back into it (feedback loop);
  (8) RE-EXTRACT — re-run intellectual content extraction on raw sources to
  upgrade papers (e.g., abstract-only → full-PDF) or apply new schema fields.
  Storage: ~/.claude/scholar-knowledge/ (configurable via SCHOLAR_KNOWLEDGE_DIR).
  Raw sources archived in raw/ subdirectory (PDFs symlinked, API responses saved).
tools: Read, Bash, Write, WebSearch, WebFetch
argument-hint: "[ingest|search|relate|status|export|compile|ask|re-extract] [arguments], e.g., 'compile' or 'ask what are the main theories of segregation?' or 're-extract all abstract_only'"
user-invocable: true
---

# Scholar Knowledge Graph

You are a knowledge management specialist for social science research. You maintain a persistent, user-scoped knowledge graph that accumulates extracted intellectual content — findings, mechanisms, theories, methods, and inter-paper relationships — across projects and sessions. This graph layers on top of Zotero (bibliographic metadata) to provide the rich intellectual content that reference managers don't store.

## Arguments

The user has provided: `$ARGUMENTS`

Parse the **mode** and **sub-arguments** using the dispatch table below.

---

## Mode Dispatch Table

| Keyword(s) in argument | Mode | Description |
|---|---|---|
| `ingest`, `add`, `import`, `extract` | **MODE 1: INGEST** | Add papers and extract intellectual content |
| `search`, `find`, `query`, `lookup`, `what do we know about` | **MODE 2: SEARCH** | Query the knowledge graph |
| `relate`, `link`, `connect`, `relationship`, `contradicts`, `extends` | **MODE 3: RELATE** | Add or view inter-paper relationships |
| `status`, `stats`, `coverage`, `summary`, `dashboard` | **MODE 4: STATUS** | Graph statistics and coverage analysis |
| `export`, `subset`, `for project` | **MODE 5: EXPORT** | Export subset for a specific project |
| `compile`, `build wiki`, `rebuild`, `wiki` | **MODE 6: COMPILE** | Generate browsable markdown wiki from knowledge graph |
| `ask`, `question`, `what do`, `what are`, `why`, `how do`, `compare`, `summarize` | **MODE 7: ASK** | Answer complex research questions using the compiled wiki |
| `re-extract`, `reextract`, `refresh`, `enrich` | **MODE 8: RE-EXTRACT** | Re-run extraction on raw sources (upgrade papers from abstract-only to full-PDF, or apply new schema fields) |

If the mode is ambiguous, ask the user.

---

## Phase 0: Setup (All Modes)

### 0a. Initialize knowledge graph directory

```bash
# Load .env for SCHOLAR_KNOWLEDGE_DIR
[ -f "${SCHOLAR_SKILL_DIR:-.}/.env" ] && . "${SCHOLAR_SKILL_DIR:-.}/.env" 2>/dev/null || true
[ -f "$HOME/.claude/.env" ] && . "$HOME/.claude/.env" 2>/dev/null || true

KNOWLEDGE_DIR="${SCHOLAR_KNOWLEDGE_DIR:-$HOME/.claude/scholar-knowledge}"
mkdir -p "$KNOWLEDGE_DIR"

KG_PAPERS="$KNOWLEDGE_DIR/papers.ndjson"
KG_CONCEPTS="$KNOWLEDGE_DIR/concepts.ndjson"
KG_EDGES="$KNOWLEDGE_DIR/edges.ndjson"
KG_META="$KNOWLEDGE_DIR/meta.json"

# Raw source storage (append-only archive of original sources)
KG_RAW="$KNOWLEDGE_DIR/raw"
mkdir -p "$KG_RAW/pdfs" "$KG_RAW/abstracts" "$KG_RAW/api-responses" "$KG_RAW/web" "$KG_RAW/images"

echo "Knowledge graph directory: $KNOWLEDGE_DIR"
echo "Raw storage: $KG_RAW"
[ -f "$KG_PAPERS" ] && echo "Papers: $(wc -l < "$KG_PAPERS" | tr -d ' ')" || echo "Papers: 0 (new graph)"
[ -f "$KG_CONCEPTS" ] && echo "Concepts: $(wc -l < "$KG_CONCEPTS" | tr -d ' ')" || echo "Concepts: 0"
[ -f "$KG_EDGES" ] && echo "Edges: $(wc -l < "$KG_EDGES" | tr -d ' ')" || echo "Edges: 0"
```

### 0b. Load knowledge graph search functions

```bash
SKILL_DIR="${SCHOLAR_SKILL_DIR:-.}/.claude/skills"
eval "$(cat "$SKILL_DIR/scholar-knowledge/references/knowledge-graph-search.md" | sed -n '/^```bash/,/^```/p' | sed '1d;$d')" 2>/dev/null
```

### 0c. Process Logging (REQUIRED)

Read and follow the process logging protocol in `.claude/skills/_shared/process-logger.md`.

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
SKILL_NAME="scholar-knowledge"
LOG_DATE=$(date +%Y-%m-%d)
mkdir -p "${OUTPUT_ROOT}/logs"
LOG_FILE="${OUTPUT_ROOT}/logs/process-log-${SKILL_NAME}-${LOG_DATE}.md"
if [ -f "$LOG_FILE" ]; then
  V=2
  while [ -f "${OUTPUT_ROOT}/logs/process-log-${SKILL_NAME}-${LOG_DATE}-${V}.md" ]; do V=$((V+1)); done
  LOG_FILE="${OUTPUT_ROOT}/logs/process-log-${SKILL_NAME}-${LOG_DATE}-${V}.md"
fi
cat > "$LOG_FILE" << LOGHEADER
# Process Log: /scholar-knowledge
- **Date**: $LOG_DATE
- **Time started**: $(date +%H:%M:%S)
- **Arguments**: $ARGUMENTS
- **Working Directory**: $(pwd)
- **Knowledge Dir**: $KNOWLEDGE_DIR

## Steps

| # | Timestamp | Step | Action | Output | Status |
|---|-----------|------|--------|--------|--------|
LOGHEADER
echo "Process log: $LOG_FILE"
```

---

## NDJSON Data Model

### Paper Node (`papers.ndjson` — one JSON object per line)

```json
{
  "id": "sha256_first_12_of_doi_or_title",
  "type": "paper",
  "doi": "10.1177/0003122420948793",
  "title": "Three Dimensions of Change in School Segregation",
  "authors": ["Fiel, Jeremy E.", "Zhang, Yongjun"],
  "year": 2017,
  "journal": "American Sociological Review",
  "volume": "82",
  "issue": "4",
  "pages": "859-886",
  "abstract": "We examine changes in school segregation...",
  "zotero_key": "",
  "pdf_path": "",
  "findings": [
    "School segregation decreased along racial lines but increased along socioeconomic lines between 1999 and 2010."
  ],
  "mechanisms": [
    "compositional change (demographic shifts in school-age population)"
  ],
  "theories": [
    {"name": "spatial assimilation", "role": "tests"}
  ],
  "methods": ["decomposition analysis", "multilevel models"],
  "populations": ["K-12 students in US public schools"],
  "data_sources": ["Common Core of Data (CCD)"],
  "key_quotes": [
    {"text": "Changes in segregation reflect three distinct processes...", "page": 860}
  ],
  "gap_claims": [
    "Prior work has not decomposed segregation change into compositional vs. structural components."
  ],
  "limitations": [
    "Data limited to public schools; private school enrollment may bias estimates."
  ],
  "future_directions": [
    "Future work should examine within-district heterogeneity at the classroom level.",
    "Extending the decomposition framework to activity-space segregation beyond residential neighborhoods."
  ],
  "ingested_at": "2026-03-18T14:30:00Z",
  "updated_at": "2026-03-18T14:30:00Z",
  "source": "zotero",
  "projects": ["segregation-paper-2026"],
  "raw_path": "abstracts/fiel-zhang-2017.txt",
  "extraction_tier": "full_pdf"
}
```

### Concept Node (`concepts.ndjson`)

```json
{
  "id": "concept_sha256_first_12",
  "type": "concept",
  "category": "theory|method|mechanism|dataset|population",
  "name": "spatial assimilation",
  "aliases": ["spatial assimilation theory", "spatial assimilation model"],
  "description": "Predicts that socioeconomic advancement leads to residential mobility into less segregated neighborhoods.",
  "key_authors": ["Massey, Douglas S."],
  "seminal_paper_id": "paper_abc123",
  "paper_count": 15,
  "created_at": "2026-03-18T14:30:00Z"
}
```

### Relationship Edge (`edges.ndjson`)

```json
{
  "id": "edge_sha256_first_12",
  "type": "edge",
  "source_id": "paper_abc123",
  "target_id": "paper_def456",
  "relationship": "extends|contradicts|cites|replicates|uses-method|uses-theory|responds-to|same-dataset",
  "note": "Extends Massey & Denton's approach by adding entropy-based measures.",
  "created_at": "2026-03-18T14:30:00Z",
  "created_by": "auto|user"
}
```

### Relationship Types

| Type | Meaning | Directionality |
|---|---|---|
| `cites` | A cites B in references | A → B |
| `contradicts` | A's findings contradict B's | A ↔ B |
| `extends` | A extends B's theory/method/findings | A → B |
| `replicates` | A replicates B's study | A → B |
| `uses-method` | A uses the method introduced/refined by B | A → B |
| `uses-theory` | A applies the theoretical framework from B | A → B |
| `responds-to` | A is a direct response/commentary on B | A → B |
| `same-dataset` | A and B use the same dataset | A ↔ B |

---

## MODE 1: INGEST

Add papers to the knowledge graph with extracted intellectual content.

### Step 1.1: Determine ingest source

Parse sub-mode from arguments:

| Sub-argument | Source | Description |
|---|---|---|
| `from zotero [keyword\|collection\|tag] [query]` | Zotero SQLite | Bulk ingest from Zotero search results |
| `from pdf [path]` | Local PDF file | Ingest single PDF via pdftotext |
| `from url [URL]` | Web page | Fetch web article/preprint, convert to markdown, save raw + extract |
| `from lit-review [path]` | Scholar-lit-review output | Parse existing literature review file |
| `from doi [DOI]` | CrossRef + Semantic Scholar | Fetch metadata from APIs |
| `from search-log [path]` | Search log file | Parse existing search log |
| `from output [path]` | Scholar skill output | Ingest findings from scholar-write, scholar-analyze, or other skill outputs back into the graph |
| `from manual` | User input | User provides structured entry |
| (no sub-argument with topic) | Zotero keyword | Default: search Zotero for topic |

### Step 1.2: Retrieve bibliographic metadata

**For Zotero source** — load refmanager-backends and search:

```bash
# Load reference manager backends
SKILL_DIR="${SCHOLAR_SKILL_DIR:-.}/.claude/skills"
eval "$(cat "$SKILL_DIR/_shared/refmanager-backends.md" | sed -n '/^```bash/,/^```/p' | sed '1d;$d')" 2>/dev/null

# Also load KG functions for dedup checking
eval "$(cat "$SKILL_DIR/scholar-knowledge/references/knowledge-graph-search.md" | sed -n '/^```bash/,/^```/p' | sed '1d;$d')" 2>/dev/null

echo "Detected backends: $REF_SOURCES (primary: $REF_PRIMARY)"

# Search for papers
echo "=== Searching: [QUERY] ==="
scholar_search "[QUERY]" 30 keyword | scholar_format_citations
```

**For PDF source** — extract text:

```bash
pdftotext "[PDF_PATH]" - | head -400
```

**For DOI source** — use CrossRef API:

```bash
DOI="[DOI]"
curl -sL "https://api.crossref.org/works/${DOI}" | python3 -c "
import json, sys
d = json.load(sys.stdin)['message']
print(f\"Title: {d.get('title',[''])[0]}\")
print(f\"Authors: {'; '.join(a.get('family','') + ', ' + a.get('given','') for a in d.get('author',[]))}\")
print(f\"Year: {d.get('published',{}).get('date-parts',[['']])[0][0]}\")
print(f\"Journal: {d.get('container-title',[''])[0]}\")
print(f\"DOI: {d.get('DOI','')}\")
print(f\"Abstract: {d.get('abstract','')[:500]}\")
" 2>/dev/null
```

**For URL source** — fetch web article and convert to markdown:

Use the WebFetch tool to retrieve the page content. This handles working papers, preprints, blog posts about research, institutional reports, and news articles about studies.

```bash
KNOWLEDGE_DIR="${SCHOLAR_KNOWLEDGE_DIR:-$HOME/.claude/scholar-knowledge}"
KG_RAW="$KNOWLEDGE_DIR/raw"
URL="[URL]"
SLUG="[derived-from-title-after-fetch]"

# Save raw HTML
mkdir -p "$KG_RAW/web"
```

After fetching with WebFetch:
1. Extract title, author(s), date, and body text from the page
2. Save the full fetched content as `raw/web/[slug].md` (markdown conversion)
3. If the page contains images (figures, diagrams, charts), download them:

```bash
KNOWLEDGE_DIR="${SCHOLAR_KNOWLEDGE_DIR:-$HOME/.claude/scholar-knowledge}"
mkdir -p "$KNOWLEDGE_DIR/raw/images/[slug]"
# For each image URL found in the article:
curl -sL "[IMAGE_URL]" -o "$KNOWLEDGE_DIR/raw/images/[slug]/[filename]"
```

4. Rewrite image references in the saved markdown to point to local paths
5. Proceed to extraction (Step 1.3) using the fetched text

**Supported URL types**:
- Preprint servers: arXiv, SSRN, SocArXiv, OSF Preprints
- Working paper series: NBER, IZA, CEPR
- Blog posts: Contexts.org, Scatterplot, OrgTheory, institutional blogs
- News about research: press releases, science journalism citing specific papers
- Reports: Census Bureau, Pew, Russell Sage Foundation

**For output source** — ingest findings from other scholar skill outputs:

Read the output file (typically a Results document, analysis log, or manuscript section from `scholar-write`, `scholar-analyze`, `scholar-compute`, etc.) and extract:
- New empirical findings produced by the user's own analysis
- Methods used
- Data sources
- Any cited papers mentioned in the output

This creates the **feedback loop**: skill outputs enrich the knowledge graph, which then informs future skills. The paper type is `"own_work"` rather than `"published"`.

```bash
# Read the skill output file
OUTPUT_FILE="[path]"
echo "Ingesting from skill output: $OUTPUT_FILE"
# Save raw
KNOWLEDGE_DIR="${SCHOLAR_KNOWLEDGE_DIR:-$HOME/.claude/scholar-knowledge}"
SLUG="own-work-$(date +%Y-%m-%d)-$(basename "$OUTPUT_FILE" .md | head -c 30)"
cp "$OUTPUT_FILE" "$KNOWLEDGE_DIR/raw/abstracts/${SLUG}.md"
```

**For lit-review output** — read the file and parse the paper inventory table.

**For search-log** — read the search log and parse the paper inventory snapshots.

### Step 1.2b: Save raw source (before extraction)

Before extracting intellectual content, archive the raw source material. This enables re-extraction later if the schema changes, and provides an audit trail.

```bash
KNOWLEDGE_DIR="${SCHOLAR_KNOWLEDGE_DIR:-$HOME/.claude/scholar-knowledge}"
KG_RAW="$KNOWLEDGE_DIR/raw"
mkdir -p "$KG_RAW/pdfs" "$KG_RAW/abstracts" "$KG_RAW/api-responses" "$KG_RAW/web" "$KG_RAW/images"
```

**For each paper, save the raw source based on ingest type:**

| Source | What to save | Where | How |
|--------|-------------|-------|-----|
| Zotero (with PDF) | Symlink to Zotero's PDF | `raw/pdfs/[slug].pdf` | `ln -sf "[zotero_storage_path]" "$KG_RAW/pdfs/[slug].pdf"` |
| Zotero (abstract only) | Abstract text | `raw/abstracts/[slug].txt` | Write abstract text to file |
| `from pdf [path]` | pdftotext output (first 400 lines) | `raw/abstracts/[slug].txt` | `pdftotext "[path]" - \| head -400 > "$KG_RAW/abstracts/[slug].txt"` |
| `from pdf [path]` (images) | Key figures extracted from PDF | `raw/images/[slug]/` | `pdfimages -png "[path]" "$KG_RAW/images/[slug]/fig"` (if pdfimages available) |
| `from url [URL]` | Full page as markdown + images | `raw/web/[slug].md` + `raw/images/[slug]/` | WebFetch → markdown conversion; curl images to local |
| `from doi` | Full CrossRef API JSON response | `raw/api-responses/[DOI-slugified].json` | `curl -sL "https://api.crossref.org/works/[DOI]" > "$KG_RAW/api-responses/[slug].json"` |
| `from output [path]` | Skill output file | `raw/abstracts/[slug].md` | Copy the output file |
| `from lit-review [path]` | Path reference | `raw/abstracts/[slug].ref` | Write the source file path (one line) |
| `from manual` | User's structured input | `raw/abstracts/[slug].md` | Write the user-provided text |

**Image extraction from PDFs** (optional — requires `pdfimages` from poppler):

```bash
KNOWLEDGE_DIR="${SCHOLAR_KNOWLEDGE_DIR:-$HOME/.claude/scholar-knowledge}"
SLUG="[paper-slug]"
PDF_PATH="[path-to-pdf]"
if command -v pdfimages &>/dev/null; then
  mkdir -p "$KNOWLEDGE_DIR/raw/images/${SLUG}"
  pdfimages -png "$PDF_PATH" "$KNOWLEDGE_DIR/raw/images/${SLUG}/fig" 2>/dev/null
  IMG_COUNT=$(ls "$KNOWLEDGE_DIR/raw/images/${SLUG}/" 2>/dev/null | wc -l | tr -d ' ')
  echo "Extracted $IMG_COUNT images from PDF"
else
  echo "pdfimages not available — skipping image extraction (install: brew install poppler)"
fi
```

**Slug convention**: Same as wiki paper page slug — `first-author-year` (e.g., `fiel-zhang-2017`). Generated via `kg_paper_slug()` from the knowledge-graph-search.md helpers.

**Raw storage rules**:
- `raw/` is **append-only** — never modify or delete raw sources
- If a paper is re-ingested (update), keep the original raw file; do NOT overwrite
- For Zotero PDFs, use **symlinks** (not copies) to avoid duplicating large files
- Store the relative path from `$KNOWLEDGE_DIR` in the paper node's `raw_path` field

**Zotero PDF symlink**:

```bash
KNOWLEDGE_DIR="${SCHOLAR_KNOWLEDGE_DIR:-$HOME/.claude/scholar-knowledge}"
# Zotero stores PDFs in storage/[KEY]/filename.pdf
ZOTERO_PDF_PATH="[resolved path from Zotero SQLite attachment query]"
SLUG="[paper-slug]"
if [ -f "$ZOTERO_PDF_PATH" ] && [ ! -L "$KNOWLEDGE_DIR/raw/pdfs/${SLUG}.pdf" ]; then
  ln -sf "$ZOTERO_PDF_PATH" "$KNOWLEDGE_DIR/raw/pdfs/${SLUG}.pdf"
  echo "Symlinked PDF: raw/pdfs/${SLUG}.pdf → $ZOTERO_PDF_PATH"
fi
```

**Abstract text save**:

```bash
KNOWLEDGE_DIR="${SCHOLAR_KNOWLEDGE_DIR:-$HOME/.claude/scholar-knowledge}"
SLUG="[paper-slug]"
ABSTRACT_FILE="$KNOWLEDGE_DIR/raw/abstracts/${SLUG}.txt"
if [ ! -f "$ABSTRACT_FILE" ]; then
  cat > "$ABSTRACT_FILE" << 'RAWEOF'
[ABSTRACT_TEXT or PDFTOTEXT_OUTPUT]
RAWEOF
  echo "Saved raw text: raw/abstracts/${SLUG}.txt"
fi
```

**DOI API response save**:

```bash
KNOWLEDGE_DIR="${SCHOLAR_KNOWLEDGE_DIR:-$HOME/.claude/scholar-knowledge}"
DOI="[DOI]"
SLUG="[paper-slug]"
API_FILE="$KNOWLEDGE_DIR/raw/api-responses/${SLUG}.json"
if [ ! -f "$API_FILE" ]; then
  curl -sL "https://api.crossref.org/works/${DOI}" > "$API_FILE"
  echo "Saved API response: raw/api-responses/${SLUG}.json"
fi
```

**Set `raw_path` and `extraction_tier` in the paper node** (used in Step 1.6):
- `raw_path`: relative path from `$KNOWLEDGE_DIR` (e.g., `"raw/abstracts/fiel-zhang-2017.txt"` or `"raw/pdfs/fiel-zhang-2017.pdf"`)
- `extraction_tier`: one of `"full_pdf"`, `"abstract_only"`, `"metadata_only"` — records what level of extraction was possible

### Step 1.3: Extract intellectual content

For each paper retrieved, read available text (abstract, or PDF via pdftotext first 300 lines) and extract:

1. **findings[]** — 1-3 key empirical findings, stated with direction/magnitude where available
2. **mechanisms[]** — causal mechanisms proposed or tested
3. **theories[]** — theoretical frameworks invoked, with role: `"tests"`, `"extends"`, `"proposes"`, `"critiques"`, `"applies"`
4. **methods[]** — methodological approaches (e.g., "diff-in-diff", "multilevel models", "matched guise")
5. **populations[]** — study populations
6. **data_sources[]** — datasets used
7. **key_quotes[]** — 1-2 verbatim quotes worth citing (with page numbers if from PDF)
8. **gap_claims[]** — what the paper says remains unstudied in the literature (typically from the Introduction or Literature Review)
9. **limitations[]** — the paper's own acknowledged limitations (typically from the Discussion/Conclusion: data constraints, measurement issues, generalizability bounds, methodological caveats)
10. **future_directions[]** — explicit suggestions for future research stated by the authors (typically from the Discussion/Conclusion: proposed extensions, alternative designs, new populations, unanswered follow-up questions)

**Extraction quality tiers:**
- **Full PDF available**: Extract all 10 fields from abstract + intro + results + discussion/conclusion. Limitations and future directions are typically in the final 2-3 paragraphs of the Discussion or Conclusion section.
- **Abstract only**: Extract findings, theories, methods, populations (4 fields minimum). Limitations and future directions are rarely in abstracts — leave as empty arrays for later enrichment via PDF.
- **Metadata only**: Store bibliographic data; leave extraction fields as empty arrays for later enrichment

**Extraction guidance for limitations vs. gap_claims vs. future_directions:**
- `gap_claims`: What the *literature* lacks — stated in the Introduction/Literature Review to motivate the study. These are gaps the paper aims to fill. (e.g., "No prior study has examined X in context Y.")
- `limitations`: What *this paper* acknowledges it could not do — stated in the Discussion/Conclusion. These are constraints on the current study. (e.g., "Our data does not include...", "We cannot rule out...", "Generalizability is limited to...")
- `future_directions`: What the authors explicitly suggest *someone else* should do next — stated in the Discussion/Conclusion. These are actionable research opportunities. (e.g., "Future work should...", "A promising extension would be...", "An important next step is...")

**IMPORTANT**: Extract only what the paper actually states. Do NOT hallucinate findings or mechanisms from memory. If reading a PDF, base extraction solely on the text shown. If only abstract is available, extract only from the abstract. Mark uncertain extractions with `[UNCERTAIN]` prefix.

### Step 1.4: Check for duplicates

Before appending each paper, check if it already exists:

```bash
# Re-load KG functions (shell state resets between calls)
SKILL_DIR="${SCHOLAR_SKILL_DIR:-.}/.claude/skills"
eval "$(cat "$SKILL_DIR/scholar-knowledge/references/knowledge-graph-search.md" | sed -n '/^```bash/,/^```/p' | sed '1d;$d')" 2>/dev/null

# Check by DOI or title
STATUS=$(kg_has_paper "[DOI]" "[TITLE]")
echo "Duplicate check: $STATUS"
```

- If `yes_doi` or `yes_title`: offer to UPDATE (replace) the existing entry rather than create a duplicate
- If `no`: proceed to append

**To update an existing entry**, remove the old line and append the new one:

```bash
# Remove old entry by ID, then append updated version
KNOWLEDGE_DIR="${SCHOLAR_KNOWLEDGE_DIR:-$HOME/.claude/scholar-knowledge}"
grep -v "\"id\":\"[PAPER_ID]\"" "$KNOWLEDGE_DIR/papers.ndjson" > "$KNOWLEDGE_DIR/papers.ndjson.tmp"
mv "$KNOWLEDGE_DIR/papers.ndjson.tmp" "$KNOWLEDGE_DIR/papers.ndjson"
# Then append new version via kg_append_paper
```

### Step 1.5: Generate paper ID

```bash
# Generate deterministic ID from DOI or title
if [ -n "$DOI" ]; then
  PAPER_ID=$(echo -n "$DOI" | shasum -a 256 | head -c 12)
else
  PAPER_ID=$(echo -n "$TITLE" | tr '[:upper:]' '[:lower:]' | shasum -a 256 | head -c 12)
fi
echo "Paper ID: $PAPER_ID"
```

### Step 1.6: Build and append JSON

Construct the paper node JSON on a single line (NDJSON format). Use the Write tool or bash `echo` to append:

```bash
KNOWLEDGE_DIR="${SCHOLAR_KNOWLEDGE_DIR:-$HOME/.claude/scholar-knowledge}"
echo '[SINGLE_LINE_JSON]' >> "$KNOWLEDGE_DIR/papers.ndjson"
```

**CRITICAL**: Each paper MUST be a single line of valid JSON. No newlines within a record.

### Step 1.7: Extract and append concepts

For each new theory, method, mechanism, or dataset encountered that is NOT already in `concepts.ndjson`, append a concept node:

```bash
KNOWLEDGE_DIR="${SCHOLAR_KNOWLEDGE_DIR:-$HOME/.claude/scholar-knowledge}"
# Check if concept already exists
if ! grep -qi "\"name\":\"[CONCEPT_NAME]\"" "$KNOWLEDGE_DIR/concepts.ndjson" 2>/dev/null; then
  echo '[CONCEPT_JSON]' >> "$KNOWLEDGE_DIR/concepts.ndjson"
fi
```

### Step 1.8: Auto-detect relationships

If the newly ingested paper's references section is readable (from PDF), check whether any cited papers are already in the knowledge graph. For each match, auto-create a `cites` edge:

```bash
KNOWLEDGE_DIR="${SCHOLAR_KNOWLEDGE_DIR:-$HOME/.claude/scholar-knowledge}"
echo '{"id":"[EDGE_ID]","type":"edge","source_id":"[NEW_PAPER_ID]","target_id":"[CITED_PAPER_ID]","relationship":"cites","note":"auto-detected from references","created_at":"[TIMESTAMP]","created_by":"auto"}' >> "$KNOWLEDGE_DIR/edges.ndjson"
```

For `extends` or `contradicts` relationships: only create these if you can confirm from reading the text. Ask the user to confirm if uncertain.

### Step 1.9: Update meta and report

```bash
# Re-load KG functions
SKILL_DIR="${SCHOLAR_SKILL_DIR:-.}/.claude/skills"
eval "$(cat "$SKILL_DIR/scholar-knowledge/references/knowledge-graph-search.md" | sed -n '/^```bash/,/^```/p' | sed '1d;$d')" 2>/dev/null
kg_update_meta
echo "=== Ingest Summary ==="
kg_count
```

Report to user:
- Papers ingested (new vs. updated)
- Concepts extracted (theories, methods, mechanisms)
- Relationships created (auto-detected citations + any user-confirmed)
- Extraction quality (full PDF / abstract only / metadata only)

### Step 1.10: Incremental wiki update

If a compiled wiki already exists, auto-update it with the newly ingested papers:

```bash
KNOWLEDGE_DIR="${SCHOLAR_KNOWLEDGE_DIR:-$HOME/.claude/scholar-knowledge}"
WIKI_DIR="$KNOWLEDGE_DIR/wiki"
if [ -d "$WIKI_DIR/papers" ]; then
  echo "Wiki detected — updating paper pages for newly ingested papers..."
else
  echo "No compiled wiki found. Run /scholar-knowledge compile to generate one."
fi
```

**If wiki exists**, for each newly ingested paper:

1. **Generate/update paper page**: Create `wiki/papers/[slug].md` using the paper page template (see MODE 6 Step 6.4). If the paper has images in `raw/images/[slug]/`, add image references to the paper page.
2. **Update affected concept pages**: If the paper introduced new theories/methods, add it to the relevant concept page's paper table. If the concept page doesn't exist, create it.
3. **Auto-maintain `wiki/index.md`**: This is critical — the index must stay current after every ingest, not just during full compile. Update:
   - Paper count in the header
   - "Recently Added" table (prepend new papers, keep last 20)
   - Topic list counts (if new paper clearly matches an existing topic)
   - Quick Stats table counts
4. **Do NOT regenerate** topic pages, `contradictions.md`, or `gaps.md` — these require the full COMPILE pass to maintain quality. But do append a note to `gaps.md` if the new paper has `gap_claims` or `future_directions`.

**The LLM auto-maintains the wiki** — the user should rarely need to edit wiki pages directly. Every ingest operation keeps the wiki current. This follows Karpathy's principle: "the LLM writes and maintains all of the data of the wiki, I rarely touch it directly."

Log in the process log:
```
Wiki updated: [N] paper pages added/updated, [N] concept pages touched, index.md refreshed
```

---

## MODE 2: SEARCH

Query the knowledge graph for papers, findings, theories, or methods.

### Step 2.1: Parse query type

| Sub-argument pattern | Search type |
|---|---|
| Free text (default) | Topic search across all fields |
| `by author [name]` | Author filter |
| `by theory [name]` | Theory/framework filter |
| `by method [name]` | Method filter |
| `by finding [keyword]` | Findings-specific search |
| `contradictions about [topic]` | Find opposing findings on same topic |
| `gaps about [topic]` | Search gap_claims field |
| `limitations of [topic/method]` | Search limitations field — what studies acknowledge they couldn't do |
| `future directions for [topic]` | Search future_directions field — what scholars say should be done next |
| `opportunities in [topic]` | Search both future_directions and gap_claims — actionable research ideas |
| `for project [name]` | Filter by project tag |

### Step 2.2: Execute search

```bash
# Re-load KG functions (shell state resets between calls)
SKILL_DIR="${SCHOLAR_SKILL_DIR:-.}/.claude/skills"
eval "$(cat "$SKILL_DIR/scholar-knowledge/references/knowledge-graph-search.md" | sed -n '/^```bash/,/^```/p' | sed '1d;$d')" 2>/dev/null

echo "=== Knowledge Graph Search: [QUERY] ==="
echo "Graph size: $(kg_count)"
echo ""

# Topic search (default)
echo "=== Papers ==="
kg_search_papers "[QUERY]" 20 | kg_format_papers

echo ""
echo "=== Theories ==="
kg_search_concepts "[QUERY]" 10 theory

echo ""
echo "=== Methods ==="
kg_search_concepts "[QUERY]" 10 method
```

### Step 2.3: Semantic enrichment

After the bash grep-based search returns results, Claude reads the matching JSON lines and performs **semantic ranking**:

1. Read each matched paper's full JSON record
2. Score relevance to the user's query (considering findings, mechanisms, theories — not just keyword match)
3. Re-rank by semantic relevance
4. Present top results in a structured table

### Step 2.4: Show relationship context

For the top 5 most relevant papers, show any relationships in the graph:

```bash
SKILL_DIR="${SCHOLAR_SKILL_DIR:-.}/.claude/skills"
eval "$(cat "$SKILL_DIR/scholar-knowledge/references/knowledge-graph-search.md" | sed -n '/^```bash/,/^```/p' | sed '1d;$d')" 2>/dev/null

for ID in [TOP_5_PAPER_IDS]; do
  EDGES=$(kg_search_edges "$ID")
  if [ -n "$EDGES" ]; then
    echo "--- Relationships for $ID ---"
    echo "$EDGES"
  fi
done
```

### Step 2.5: Coverage assessment

If the graph has fewer than 3 relevant results:

> **Low coverage warning**: The knowledge graph has limited content on "[topic]". Consider running:
> ```
> /scholar-knowledge ingest from zotero [topic]
> ```
> to populate the graph from your Zotero library, or proceed to `/scholar-lit-review` for a full literature search.

### Step 2.6: Present results

Format output as:

```markdown
## Knowledge Graph Search: [query]

### Papers Found: [N]

| # | Authors | Year | Title | Journal | Key Finding | Theory | Method |
|---|---------|------|-------|---------|-------------|--------|--------|
| 1 | ... | ... | ... | ... | ... | ... | ... |

### Relationship Map

Paper A (2020) --extends--> Paper B (2015)
Paper A (2020) --contradicts--> Paper C (2018)
Paper B (2015) --cites--> Paper D (2010)

### Contested Findings (if any)
- **Finding**: "[X effect on Y]"
  - **For**: Paper A (2020), Paper D (2010) — positive association
  - **Against**: Paper C (2018) — null finding

### Coverage Notes
- Graph coverage on this topic: [HIGH/MEDIUM/LOW]
- Suggested enrichment: [if LOW, suggest ingest commands]
```

---

## MODE 3: RELATE

Add or view relationships between papers.

### Step 3.1: Parse relationship specification

Accept formats:
- `[Paper A title/DOI] contradicts [Paper B title/DOI]` — add a specific relationship
- `[Paper A] extends [Paper B]` — add a relationship
- `show relationships for [Paper A]` — view all edges for a paper
- `show all [contradicts|extends|replicates]` — view all edges of a type
- `map [topic]` — show the relationship graph for papers on a topic

### Step 3.2: Validate papers exist

For adding relationships, both papers must exist in `papers.ndjson`. If a paper is not found:

> Paper "[title]" not found in the knowledge graph. Options:
> 1. Run `/scholar-knowledge ingest from doi [DOI]` to add it first
> 2. Run `/scholar-knowledge ingest from zotero [author keyword]` to search and add
> 3. Skip this relationship

### Step 3.3: Add relationship edge

```bash
KNOWLEDGE_DIR="${SCHOLAR_KNOWLEDGE_DIR:-$HOME/.claude/scholar-knowledge}"
EDGE_ID=$(echo -n "[SOURCE_ID]-[REL_TYPE]-[TARGET_ID]" | shasum -a 256 | head -c 12)
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Check if edge already exists
if grep -q "\"id\":\"${EDGE_ID}\"" "$KNOWLEDGE_DIR/edges.ndjson" 2>/dev/null; then
  echo "Relationship already exists"
else
  echo "{\"id\":\"${EDGE_ID}\",\"type\":\"edge\",\"source_id\":\"[SOURCE_ID]\",\"target_id\":\"[TARGET_ID]\",\"relationship\":\"[REL_TYPE]\",\"note\":\"[USER_NOTE]\",\"created_at\":\"${TIMESTAMP}\",\"created_by\":\"user\"}" >> "$KNOWLEDGE_DIR/edges.ndjson"
  echo "Added: [Paper A] --[REL_TYPE]--> [Paper B]"
fi
```

### Step 3.4: View relationships

For viewing, read `edges.ndjson`, resolve paper IDs to titles, and render as a text-based directed graph:

```
=== Relationship Map for: [Paper Title] ===

INCOMING (papers that reference this one):
  Paper X (2022) --extends--> [THIS PAPER]
  Paper Y (2021) --cites--> [THIS PAPER]

OUTGOING (papers this one references):
  [THIS PAPER] --cites--> Paper A (2015)
  [THIS PAPER] --contradicts--> Paper B (2018)
  [THIS PAPER] --uses-theory--> Paper C (2010)
```

---

## MODE 4: STATUS

Show knowledge graph statistics and coverage analysis.

### Step 4.1: Compute statistics

```bash
KNOWLEDGE_DIR="${SCHOLAR_KNOWLEDGE_DIR:-$HOME/.claude/scholar-knowledge}"

echo "=== Knowledge Graph Status ==="
echo ""
echo "Storage: $KNOWLEDGE_DIR"
echo ""

# Counts
PAPER_COUNT=0; CONCEPT_COUNT=0; EDGE_COUNT=0
[ -f "$KNOWLEDGE_DIR/papers.ndjson" ] && PAPER_COUNT=$(wc -l < "$KNOWLEDGE_DIR/papers.ndjson" | tr -d ' ')
[ -f "$KNOWLEDGE_DIR/concepts.ndjson" ] && CONCEPT_COUNT=$(wc -l < "$KNOWLEDGE_DIR/concepts.ndjson" | tr -d ' ')
[ -f "$KNOWLEDGE_DIR/edges.ndjson" ] && EDGE_COUNT=$(wc -l < "$KNOWLEDGE_DIR/edges.ndjson" | tr -d ' ')
echo "Papers: $PAPER_COUNT | Concepts: $CONCEPT_COUNT | Relationships: $EDGE_COUNT"
echo ""

# Raw storage stats
KG_RAW="$KNOWLEDGE_DIR/raw"
RAW_PDFS=0; RAW_ABSTRACTS=0; RAW_API=0
[ -d "$KG_RAW/pdfs" ] && RAW_PDFS=$(ls "$KG_RAW/pdfs/" 2>/dev/null | wc -l | tr -d ' ')
[ -d "$KG_RAW/abstracts" ] && RAW_ABSTRACTS=$(ls "$KG_RAW/abstracts/" 2>/dev/null | wc -l | tr -d ' ')
[ -d "$KG_RAW/api-responses" ] && RAW_API=$(ls "$KG_RAW/api-responses/" 2>/dev/null | wc -l | tr -d ' ')
echo "Raw storage: $RAW_PDFS PDFs (symlinks) | $RAW_ABSTRACTS abstracts | $RAW_API API responses"

# Extraction tier breakdown
if [ -f "$KNOWLEDGE_DIR/papers.ndjson" ]; then
  echo ""
  echo "=== Extraction Tiers ==="
  grep -o '"extraction_tier":"[^"]*"' "$KNOWLEDGE_DIR/papers.ndjson" 2>/dev/null | sed 's/"extraction_tier":"//;s/"//' | sort | uniq -c | sort -rn
  NO_TIER=$(grep -cvl '"extraction_tier"' "$KNOWLEDGE_DIR/papers.ndjson" 2>/dev/null || echo 0)
  echo "  (no tier recorded): $NO_TIER"
fi

# Wiki status
if [ -d "$KNOWLEDGE_DIR/wiki/papers" ]; then
  WIKI_PAGES=$(ls "$KNOWLEDGE_DIR/wiki/papers/" 2>/dev/null | wc -l | tr -d ' ')
  LAST_COMPILED=$(grep -o '"last_compiled":"[^"]*"' "$KNOWLEDGE_DIR/meta.json" 2>/dev/null | sed 's/.*"last_compiled":"//;s/"//')
  echo ""
  echo "Wiki: $WIKI_PAGES paper pages | Last compiled: ${LAST_COMPILED:-never}"
else
  echo ""
  echo "Wiki: not compiled (run /scholar-knowledge compile)"
fi
echo ""

# Papers by decade
if [ -f "$KNOWLEDGE_DIR/papers.ndjson" ]; then
  echo "=== Papers by Decade ==="
  grep -o '"year":[0-9]*' "$KNOWLEDGE_DIR/papers.ndjson" | sed 's/"year"://' | awk '{d=int($1/10)*10; count[d]++} END {for(d in count) printf "%ds: %d\n", d, count[d]}' | sort
  echo ""

  echo "=== Top Journals ==="
  grep -o '"journal":"[^"]*"' "$KNOWLEDGE_DIR/papers.ndjson" | sed 's/"journal":"//;s/"//' | sort | uniq -c | sort -rn | head -10
  echo ""

  echo "=== Recent Additions (last 7 days) ==="
  WEEK_AGO=$(date -v-7d +%Y-%m-%d 2>/dev/null || date -d '7 days ago' +%Y-%m-%d 2>/dev/null || echo "")
  if [ -n "$WEEK_AGO" ]; then
    grep "\"ingested_at\":\"${WEEK_AGO}" "$KNOWLEDGE_DIR/papers.ndjson" 2>/dev/null | wc -l | tr -d ' '
  fi
fi

# Concepts by category
if [ -f "$KNOWLEDGE_DIR/concepts.ndjson" ]; then
  echo "=== Concepts by Category ==="
  grep -o '"category":"[^"]*"' "$KNOWLEDGE_DIR/concepts.ndjson" | sed 's/"category":"//;s/"//' | sort | uniq -c | sort -rn
fi

# Edge types
if [ -f "$KNOWLEDGE_DIR/edges.ndjson" ]; then
  echo ""
  echo "=== Relationship Types ==="
  grep -o '"relationship":"[^"]*"' "$KNOWLEDGE_DIR/edges.ndjson" | sed 's/"relationship":"//;s/"//' | sort | uniq -c | sort -rn
fi
```

### Step 4.2: Coverage analysis

Claude reads the papers and concepts to identify:

1. **Well-covered topics**: Areas with 5+ papers and multiple theories
2. **Thin areas**: Topics with 1-2 papers only
3. **Theory gaps**: Theories mentioned in gap_claims but with no paper testing them
4. **Methodological blind spots**: Methods appearing only once
5. **Most-connected papers**: Papers with highest edge count (central to the graph)
6. **Isolated papers**: Papers with no edges (candidates for relationship mapping)
7. **Common limitations**: Recurring limitations across papers (e.g., "cross-sectional data" appears in N papers — signals demand for longitudinal designs)
8. **Research frontier**: Most frequently mentioned future directions — these are the field's stated next steps. Cluster by theme and count how many papers point to each direction.

### Step 4.3: Present dashboard

```markdown
## Knowledge Graph Dashboard

| Metric | Value |
|--------|-------|
| Total papers | [N] |
| Total concepts | [N] |
| Total relationships | [N] |
| Storage size | [X KB] |
| Last updated | [date] |

### Coverage Map
| Topic Area | Papers | Theories | Methods | Coverage |
|-----------|--------|----------|---------|----------|
| [topic 1] | N | N | N | HIGH/MED/LOW |

### Most Connected Papers (knowledge hubs)
1. [Paper] — [N] connections
2. ...

### Suggested Enrichment
- Run `/scholar-knowledge ingest from zotero [topic]` to add papers on [thin area]
- Run `/scholar-knowledge relate [Paper A] extends [Paper B]` to connect isolated papers
```

---

## MODE 5: EXPORT

Export a subset of the knowledge graph for a specific project or topic.

### Step 5.1: Parse export scope

| Sub-argument | Scope |
|---|---|
| `for project [topic/keyword]` | Filter papers relevant to a topic |
| `for collection [zotero collection]` | Match papers from a Zotero collection |
| `by author [name]` | All papers by author |
| `all` | Full graph export |
| `as bibtex` | Export as .bib file |
| `as markdown` | Export as structured markdown (default) |

### Step 5.2: Filter and extract

```bash
SKILL_DIR="${SCHOLAR_SKILL_DIR:-.}/.claude/skills"
eval "$(cat "$SKILL_DIR/scholar-knowledge/references/knowledge-graph-search.md" | sed -n '/^```bash/,/^```/p' | sed '1d;$d')" 2>/dev/null

# Search for papers matching the export scope
kg_search_papers "[SCOPE_QUERY]" 100
```

### Step 5.3: Generate output

**Markdown export** (default):

```markdown
# Knowledge Graph Export: [scope]
**Exported**: [date] | **Papers**: [N] | **Relationships**: [N]

## Paper Summaries

### 1. [Authors] ([Year]). [Title]. *[Journal]*.
- **DOI**: [doi]
- **Findings**: [findings list]
- **Theories**: [theories with roles]
- **Methods**: [methods list]
- **Population**: [populations]
- **Data**: [data sources]
- **Gap claims**: [gaps]
- **Limitations**: [limitations]
- **Future directions**: [future directions]

### 2. ...

## Relationship Map
[text-based graph]

## Concept Index
### Theories
- [theory name] — used by [N] papers — [description]

### Methods
- [method name] — used by [N] papers
```

**BibTeX export**:

Generate `.bib` entries with enriched `note` fields containing findings and theories.

### Step 5.4: Save output

Use the version collision avoidance protocol from `.claude/skills/_shared/version-check.md`.

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
mkdir -p "${OUTPUT_ROOT}/knowledge"
# BASE pattern: ${OUTPUT_ROOT}/knowledge/kg-export-[SCOPE_SLUG]-$(date +%Y-%m-%d)
OUTDIR="$(dirname "${OUTPUT_ROOT}/knowledge/kg-export-[SCOPE_SLUG]-$(date +%Y-%m-%d)")"
STEM="$(basename "${OUTPUT_ROOT}/knowledge/kg-export-[SCOPE_SLUG]-$(date +%Y-%m-%d)")"
mkdir -p "$OUTDIR"
bash "${SCHOLAR_SKILL_DIR:-.}/scripts/gates/version-check.sh" "$OUTDIR" "$STEM"
```

Save the export using the Write tool at the path printed above.

---

## MODE 6: COMPILE

Generate a browsable, Obsidian-compatible markdown wiki from the NDJSON knowledge graph. The wiki is a directory of interlinked `.md` files that can be opened in Obsidian, VS Code, or any markdown viewer.

### Step 6.1: Determine compile mode (auto-detect)

```bash
KNOWLEDGE_DIR="${SCHOLAR_KNOWLEDGE_DIR:-$HOME/.claude/scholar-knowledge}"
WIKI_DIR="$KNOWLEDGE_DIR/wiki"

# Check for existing wiki and last compile time
if [ -d "$WIKI_DIR" ] && grep -q '"last_compiled"' "$KNOWLEDGE_DIR/meta.json" 2>/dev/null; then
  LAST_COMPILED=$(grep -o '"last_compiled":"[^"]*"' "$KNOWLEDGE_DIR/meta.json" | sed 's/.*"last_compiled":"//;s/"//')
  echo "Existing wiki found. Last compiled: $LAST_COMPILED"
  echo "Mode: INCREMENTAL (only papers ingested after $LAST_COMPILED)"
  echo "Use 'compile full' to force a full rebuild."
  COMPILE_MODE="incremental"
else
  echo "No existing wiki or no compile timestamp. Mode: FULL BUILD"
  COMPILE_MODE="full"
fi

# User can override: "compile full" forces full rebuild, "compile incremental" forces incremental
```

If user argument contains `full`, set `COMPILE_MODE="full"`. If `incremental`, set accordingly.

### Step 6.2: Create wiki directory structure

```bash
KNOWLEDGE_DIR="${SCHOLAR_KNOWLEDGE_DIR:-$HOME/.claude/scholar-knowledge}"
WIKI_DIR="$KNOWLEDGE_DIR/wiki"
mkdir -p "$WIKI_DIR/papers" "$WIKI_DIR/concepts" "$WIKI_DIR/topics" "$WIKI_DIR/answers"
echo "Wiki directory: $WIKI_DIR"
```

### Step 6.3: Read NDJSON data

Read the knowledge graph files. For large graphs (>100 papers), read in batches of 50 lines to stay within context limits.

```bash
KNOWLEDGE_DIR="${SCHOLAR_KNOWLEDGE_DIR:-$HOME/.claude/scholar-knowledge}"

# Count records
PAPER_COUNT=$(wc -l < "$KNOWLEDGE_DIR/papers.ndjson" 2>/dev/null | tr -d ' ')
CONCEPT_COUNT=$(wc -l < "$KNOWLEDGE_DIR/concepts.ndjson" 2>/dev/null | tr -d ' ')
EDGE_COUNT=$(wc -l < "$KNOWLEDGE_DIR/edges.ndjson" 2>/dev/null | tr -d ' ')
echo "Compiling wiki from: $PAPER_COUNT papers, $CONCEPT_COUNT concepts, $EDGE_COUNT edges"
```

**For incremental mode**: Only read papers where `ingested_at` or `updated_at` is after `$LAST_COMPILED`.

```bash
# Get papers since last compile (incremental mode)
KNOWLEDGE_DIR="${SCHOLAR_KNOWLEDGE_DIR:-$HOME/.claude/scholar-knowledge}"
SINCE="$LAST_COMPILED"
# Read new/updated papers
grep "\"ingested_at\":\"" "$KNOWLEDGE_DIR/papers.ndjson" | awk -v since="$SINCE" -F'"ingested_at":"' '{split($2,a,"\""); if(a[1] >= since) print}' > /tmp/kg-new-papers.ndjson
echo "New papers since $SINCE: $(wc -l < /tmp/kg-new-papers.ndjson | tr -d ' ')"
```

### Step 6.4: Generate paper pages

For each paper (or each new paper in incremental mode), generate a markdown page.

**Filename convention**: `[first-author-last-name]-[year].md` (lowercase, hyphens). If collision, append `-b`, `-c`, etc.

**Paper page template**:

```markdown
# [Authors] ([Year]). [Title]
*[Journal]*, [Volume]([Issue]), [Pages]. [DOI link]

## Key Findings
- [finding 1]
- [finding 2]

## Theories
- [[concept-slug]] ([role: tests/extends/proposes/critiques/applies])

## Methods
- [method 1], [method 2]

## Data
- [data_source 1]

## Population
- [population 1]

## Key Quotes
> "[quote text]" (p. [page])

## Gaps Identified
- [gap_claim 1]

## Limitations
- [limitation 1]

## Future Directions
- [future_direction 1]

## Relationships
- [relationship_type] → [[target-paper-slug]]
- [relationship_type] ← [[source-paper-slug]]

---
*ID: [id] | Ingested: [ingested_at] | Source: [source] | Projects: [projects]*
```

**Implementation**: Read each paper's JSON line, extract all fields, resolve edge IDs to paper slugs for the Relationships section, and write the page using the Write tool.

For large graphs, batch the work: process 20-30 papers per batch, writing each page with the Write tool before moving to the next batch.

### Step 6.5: Generate concept pages

For each concept in `concepts.ndjson`, generate a page.

**Filename convention**: `[concept-name-slugified].md`

**Concept page template**:

```markdown
# [Concept Name]
*[Category: theory/method/mechanism/dataset/population]* | Key author: [key_authors]

[description]

## Papers ([paper_count])

| Year | Authors | Title | Role |
|------|---------|-------|------|
| [year] | [authors] | [[paper-slug]] | [role] |

## Related Concepts
- [[related-concept-slug]] ([relationship basis])

---
*ID: [id] | Created: [created_at]*
```

**Implementation**: For each concept, search `papers.ndjson` for papers that reference this concept in their `theories[]` or `methods[]` fields. Build the papers table from those matches.

### Step 6.6: Cluster topics and generate topic pages

This is the most creative step — Claude reads paper titles, findings, and theories to identify 10-20 topic clusters.

**Approach**:
1. Read all paper titles and the first finding from each paper (batch-read from NDJSON)
2. Identify recurring themes/topics (e.g., "segregation", "immigration", "language", "health", "education", "inequality", "mobility")
3. For each topic, collect all papers whose title, findings, or theories match
4. Generate a topic page with Claude-written synthesis

**Topic page template**:

```markdown
# [Topic Name]
*[N] papers in knowledge graph*

## Overview
[Claude-generated 2-3 paragraph synthesis of what the KG knows about this topic.
Identify the main research questions, dominant theoretical perspectives, and
key empirical findings. Note any evolution over time.]

## Papers

| Year | Authors | Title | Key Finding |
|------|---------|-------|-------------|
| [year] | [authors] | [[paper-slug]] | [first finding excerpt] |

## Theoretical Landscape
- [[theory-1]] — used by [N] papers ([supports/challenges] main findings)
- [[theory-2]] — used by [N] papers

## Methods Used
| Method | Papers |
|--------|--------|
| [method] | [N] |

## Key Debates
[Auto-extracted from papers with contradicting findings on this topic]

## Open Questions
[Aggregated from gap_claims and future_directions of papers on this topic]
```

### Step 6.7: Generate aggregate pages

**`wiki/index.md`** — master dashboard:

```markdown
# Research Knowledge Graph
*Last compiled: [timestamp] | [N] papers | [N] concepts | [N] relationships*

## Quick Stats
| Metric | Count |
|--------|-------|
| Papers | [N] |
| Theories | [N] |
| Methods | [N] |
| Mechanisms | [N] |
| Relationships | [N] |

## Topics
- [[topics/segregation]] ([N] papers)
- [[topics/immigration]] ([N] papers)
- ...

## Recently Added
| Date | Paper |
|------|-------|
| [date] | [[papers/author-year]] |

## Most Connected Papers
| Paper | Connections |
|-------|------------|
| [[papers/author-year]] | [N] edges |

## Browse
- [All Papers](papers/) — individual paper summaries
- [Concepts](concepts/) — theories, methods, mechanisms
- [Topics](topics/) — thematic clusters
- [[contradictions]] — contested findings
- [[gaps]] — research opportunities
- [Q&A Archive](answers/) — past research questions and answers
```

**`wiki/contradictions.md`** — papers with opposing findings:

```markdown
# Contested Findings

Pairs or groups of papers in the knowledge graph that report contradicting findings on the same topic.

## [Topic 1]
**Finding in dispute**: "[description of contested claim]"

| Position | Paper | Year | Finding |
|----------|-------|------|---------|
| Supports | [[papers/author-year]] | [year] | [finding] |
| Challenges | [[papers/author-year]] | [year] | [finding] |

**Note**: [Any context about why findings differ — methods, populations, time periods]

## [Topic 2]
...
```

Build this by: reading all `contradicts` edges from `edges.ndjson`, resolving paper IDs, and grouping by topic.

**`wiki/gaps.md`** — aggregated research gaps and future directions:

```markdown
# Research Gaps & Future Directions

Aggregated from [N] papers in the knowledge graph.

## Frequently Cited Gaps
[Cluster gap_claims by theme, count how many papers mention each gap]

| Gap Theme | Papers Citing | Example |
|-----------|--------------|---------|
| [theme] | [N] | "[quote]" — [[papers/author-year]] |

## Suggested Future Directions
[Cluster future_directions by theme]

| Direction | Papers Suggesting | Example |
|-----------|------------------|---------|
| [theme] | [N] | "[quote]" — [[papers/author-year]] |

## Limitations Patterns
[Recurring limitations across papers — signals systematic constraints]

| Limitation Pattern | Papers | Implication |
|--------------------|--------|-------------|
| Cross-sectional data | [N] | Demand for longitudinal designs |
| Single-country samples | [N] | Need for comparative work |
```

### Step 6.8: Generate visual knowledge map

Generate a visual network graph of the knowledge graph using Python matplotlib/networkx. This produces a PNG image that can be viewed in Obsidian or any image viewer.

```python
#!/usr/bin/env python3
"""Generate knowledge map visualization."""
import json, os
KNOWLEDGE_DIR = os.path.expanduser("~/.claude/scholar-knowledge")
WIKI_DIR = os.path.join(KNOWLEDGE_DIR, "wiki")

try:
    import networkx as nx
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
except ImportError:
    print("networkx or matplotlib not available — skipping visualization")
    print("Install: pip install networkx matplotlib")
    exit(0)

# Build graph
G = nx.Graph()

# Load papers
papers = {}
with open(os.path.join(KNOWLEDGE_DIR, "papers.ndjson")) as f:
    for line in f:
        p = json.loads(line.strip())
        pid = p['id']
        papers[pid] = p
        label = f"{(p.get('authors') or ['?'])[0].split(',')[0]} {p.get('year','')}"
        G.add_node(pid, label=label, node_type='paper')

# Load concepts
with open(os.path.join(KNOWLEDGE_DIR, "concepts.ndjson")) as f:
    for line in f:
        c = json.loads(line.strip())
        G.add_node(c['id'], label=c['name'][:20], node_type='concept')

# Load edges (paper-to-paper)
with open(os.path.join(KNOWLEDGE_DIR, "edges.ndjson")) as f:
    for line in f:
        e = json.loads(line.strip())
        if e.get('source_id') in G and e.get('target_id') in G:
            G.add_edge(e['source_id'], e['target_id'], rel=e.get('relationship',''))

# Paper-to-concept edges (from theories/methods)
for pid, p in papers.items():
    for t in p.get('theories', []):
        tname = t.get('name','') if isinstance(t, dict) else t
        # Find matching concept node
        for nid, ndata in G.nodes(data=True):
            if ndata.get('node_type') == 'concept' and ndata.get('label','').lower().startswith(tname.lower()[:15]):
                G.add_edge(pid, nid, rel='uses-theory')
                break

# Layout and draw
fig, ax = plt.subplots(1, 1, figsize=(20, 16))
pos = nx.spring_layout(G, k=0.5, iterations=50, seed=42)

# Color by type
paper_nodes = [n for n,d in G.nodes(data=True) if d.get('node_type')=='paper']
concept_nodes = [n for n,d in G.nodes(data=True) if d.get('node_type')=='concept']

nx.draw_networkx_nodes(G, pos, nodelist=paper_nodes, node_color='#4A90D9',
                       node_size=30, alpha=0.7, ax=ax)
nx.draw_networkx_nodes(G, pos, nodelist=concept_nodes, node_color='#E74C3C',
                       node_size=120, alpha=0.9, ax=ax)
nx.draw_networkx_edges(G, pos, alpha=0.15, ax=ax)

# Label only concepts (papers are too dense)
concept_labels = {n: d['label'] for n,d in G.nodes(data=True) if d.get('node_type')=='concept'}
nx.draw_networkx_labels(G, pos, concept_labels, font_size=7, font_weight='bold', ax=ax)

ax.set_title(f"Knowledge Graph: {len(paper_nodes)} papers, {len(concept_nodes)} concepts, {G.number_of_edges()} edges",
             fontsize=14, fontweight='bold')
ax.axis('off')
plt.tight_layout()

out_path = os.path.join(WIKI_DIR, "knowledge-map.png")
plt.savefig(out_path, dpi=150, bbox_inches='tight', facecolor='white')
print(f"Knowledge map saved: {out_path}")

# Also generate a topic-level summary map (smaller, cleaner)
# ... (optional: topic nodes + inter-topic edge weights)
```

Save the script to `$KNOWLEDGE_DIR/wiki/generate-map.py` and run it. The output `knowledge-map.png` is embedded in `wiki/index.md`:

```markdown
## Knowledge Map
![Knowledge Map](knowledge-map.png)
```

If `networkx` or `matplotlib` is not installed, skip this step and note it in the report. The wiki works fine without the visualization.

**Additional visual outputs** (generate if matplotlib available):
- **Timeline**: Papers by year (bar chart) → `wiki/timeline.png`
- **Method frequency**: Horizontal bar chart of most-used methods → `wiki/methods-chart.png`

### Step 6.9: Update meta.json and report

```bash
KNOWLEDGE_DIR="${SCHOLAR_KNOWLEDGE_DIR:-$HOME/.claude/scholar-knowledge}"

# Update meta.json with compile timestamp
python3 -c "
import json, datetime
with open('$KNOWLEDGE_DIR/meta.json', 'r') as f:
    meta = json.load(f)
meta['last_compiled'] = datetime.datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ')
with open('$KNOWLEDGE_DIR/meta.json', 'w') as f:
    json.dump(meta, f, indent=2)
print('meta.json updated with last_compiled timestamp')
" 2>/dev/null || echo "meta.json update failed — update manually"
```

Report to user:
- Pages generated: [N] paper pages, [N] concept pages, [N] topic pages
- Aggregate pages: index.md, contradictions.md, gaps.md
- Visual outputs: knowledge-map.png, timeline.png, methods-chart.png (if generated)
- Wiki location: `$KNOWLEDGE_DIR/wiki/`
- Tip: "Open this directory in Obsidian for graph view and backlink navigation"

---

## MODE 7: ASK

Answer complex research questions by reading the compiled wiki. Unlike MODE 2 (SEARCH), which returns raw paper records, ASK synthesizes a narrative answer and saves it as a wiki page.

### Step 7.1: Check wiki exists

```bash
KNOWLEDGE_DIR="${SCHOLAR_KNOWLEDGE_DIR:-$HOME/.claude/scholar-knowledge}"
WIKI_DIR="$KNOWLEDGE_DIR/wiki"

if [ ! -d "$WIKI_DIR" ] || [ ! -f "$WIKI_DIR/index.md" ]; then
  echo "ERROR: No compiled wiki found. Run /scholar-knowledge compile first."
  echo "The ASK mode reads the compiled wiki, not raw NDJSON."
  exit 1
fi

echo "Wiki found: $WIKI_DIR"
echo "Papers: $(ls "$WIKI_DIR/papers/" 2>/dev/null | wc -l | tr -d ' ') pages"
echo "Concepts: $(ls "$WIKI_DIR/concepts/" 2>/dev/null | wc -l | tr -d ' ') pages"
echo "Topics: $(ls "$WIKI_DIR/topics/" 2>/dev/null | wc -l | tr -d ' ') pages"
```

If no wiki exists, instruct the user to run `/scholar-knowledge compile` first and stop.

### Step 7.2: Parse question and identify relevant wiki pages

Read the user's question from `$ARGUMENTS` (everything after the `ask` keyword).

Then read `wiki/index.md` to get an overview of available topics and concepts.

**Routing strategy**:
1. Read `wiki/index.md` (the dashboard) to identify which topics and concepts are relevant to the question
2. Read the most relevant topic page(s) from `wiki/topics/` (up to 3)
3. Read the most relevant concept page(s) from `wiki/concepts/` (up to 5)
4. If the question involves contradictions, read `wiki/contradictions.md`
5. If the question asks about gaps/opportunities, read `wiki/gaps.md`
6. Read individual paper pages only if specific papers need deeper examination (up to 10)

**Do NOT read raw NDJSON** — the wiki is the source for ASK mode. This ensures the compiled synthesis layer (topic overviews, clustered gaps) is leveraged.

### Step 7.3: Read relevant wiki pages

Use the Read tool to read the identified pages. For a typical question, this means reading:
- `wiki/index.md` (always)
- 1-3 topic pages
- 2-5 concept pages
- 0-1 aggregate pages (contradictions or gaps)
- 0-10 individual paper pages (for depth)

### Step 7.4: Synthesize answer

Based on the wiki content, compose a structured answer as a markdown document.

**Answer template**:

```markdown
# Q: [user's question]
*Asked: [date] | Papers consulted: [N] | Wiki pages read: [N]*

## Answer

[Claude-generated synthesis — 3-8 paragraphs answering the question based on
what the knowledge graph contains. Use specific paper citations in (Author Year)
format. Note confidence level based on graph coverage.]

## Evidence Summary

| [Column relevant to question] | Support | Key Papers |
|-------------------------------|---------|------------|
| [item] | [strength] | [[papers/author-year]], [[papers/author-year]] |

## Contested Points
[If the question touches on debated findings, summarize them here]

## What the Knowledge Graph Doesn't Cover
[Identify aspects of the question that the KG has limited or no coverage on.
Suggest enrichment commands.]

## Sources Consulted
Wiki pages read:
- [[topics/topic-name]]
- [[concepts/concept-name]]
- [[papers/author-year]]
- ...
```

**Confidence levels**:
- **HIGH**: 10+ relevant papers, multiple theories, consistent findings
- **MEDIUM**: 3-9 papers, some theoretical grounding
- **LOW**: 1-2 papers or no direct coverage (note this prominently)

### Step 7.5: Save answer

Save the answer to the wiki for future reference (the feedback loop).

```bash
KNOWLEDGE_DIR="${SCHOLAR_KNOWLEDGE_DIR:-$HOME/.claude/scholar-knowledge}"
WIKI_DIR="$KNOWLEDGE_DIR/wiki"
mkdir -p "$WIKI_DIR/answers"

# Slugify the question for the filename
QUESTION_SLUG=$(echo "[QUESTION]" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | head -c 60)
DATE=$(date +%Y-%m-%d)
ANSWER_FILE="$WIKI_DIR/answers/${QUESTION_SLUG}-${DATE}.md"
echo "Answer will be saved to: $ANSWER_FILE"
```

Write the answer using the Write tool.

### Step 7.6: Feedback loop (optional)

After saving the answer, check if any topic pages should be updated with new insights:

1. If the answer identified a new cross-cutting theme not in any topic page → suggest user runs `compile full`
2. If the answer synthesized findings in a novel way → append a "See also" link to relevant topic pages pointing to the answer
3. Update `wiki/index.md` to add the answer to a "Recent Q&A" section if one exists

This feedback loop is what makes the wiki grow organically — each question potentially enriches the wiki for future queries.

### Step 7.7: Present to user

Display the answer in the terminal AND inform the user where it was saved:

> **Answer saved to**: `~/.claude/scholar-knowledge/wiki/answers/[slug].md`
> Open in Obsidian to see backlinks and navigate to referenced papers.

---

## MODE 8: RE-EXTRACT

Re-run intellectual content extraction on papers using their archived raw sources. This is useful when:
- New schema fields were added (e.g., `limitations`, `future_directions`)
- A paper was originally ingested as `abstract_only` but now has a PDF available
- The extraction quality needs improvement (e.g., better findings/mechanisms)

### Step 8.1: Parse scope

| Sub-argument | Scope |
|---|---|
| `all` | Re-extract ALL papers that have raw sources |
| `all abstract_only` | Re-extract only papers with `extraction_tier: "abstract_only"` (upgrade candidates) |
| `all metadata_only` | Re-extract only papers with `extraction_tier: "metadata_only"` |
| `[paper title or DOI]` | Re-extract a single specific paper |
| `missing [field]` | Re-extract papers where a specific field is empty (e.g., `missing limitations`) |

### Step 8.2: Identify papers and their raw sources

```bash
KNOWLEDGE_DIR="${SCHOLAR_KNOWLEDGE_DIR:-$HOME/.claude/scholar-knowledge}"
KG_RAW="$KNOWLEDGE_DIR/raw"

# For "all abstract_only" scope:
echo "=== Papers eligible for re-extraction ==="
grep '"extraction_tier":"abstract_only"' "$KNOWLEDGE_DIR/papers.ndjson" 2>/dev/null | while IFS= read -r line; do
  id=$(echo "$line" | sed 's/.*"id":"\([^"]*\)".*/\1/')
  title=$(echo "$line" | sed 's/.*"title":"\([^"]*\)".*/\1/' | head -c 60)
  raw=$(echo "$line" | sed 's/.*"raw_path":"\([^"]*\)".*/\1/')
  echo "  $id | $title | raw: $raw"
done
```

For each paper, check if a better raw source is now available:
1. If `extraction_tier` is `abstract_only` and a PDF symlink exists in `raw/pdfs/[slug].pdf` → upgrade to `full_pdf`
2. If `extraction_tier` is `metadata_only` and an abstract exists in `raw/abstracts/[slug].txt` → upgrade to `abstract_only`
3. Check Zotero for newly added PDFs since original ingest

### Step 8.3: Check for upgraded raw sources

For `abstract_only` papers, check if Zotero now has a PDF:

```bash
KNOWLEDGE_DIR="${SCHOLAR_KNOWLEDGE_DIR:-$HOME/.claude/scholar-knowledge}"
SLUG="[paper-slug]"

# Check if PDF symlink already exists
if [ -L "$KNOWLEDGE_DIR/raw/pdfs/${SLUG}.pdf" ] && [ -f "$KNOWLEDGE_DIR/raw/pdfs/${SLUG}.pdf" ]; then
  echo "PDF available for $SLUG — can upgrade to full_pdf extraction"
  EXTRACTION_TIER="full_pdf"
  RAW_TEXT=$(pdftotext "$KNOWLEDGE_DIR/raw/pdfs/${SLUG}.pdf" - 2>/dev/null | head -400)
elif [ -f "$KNOWLEDGE_DIR/raw/abstracts/${SLUG}.txt" ]; then
  echo "Abstract available for $SLUG — re-extracting from abstract"
  EXTRACTION_TIER="abstract_only"
  RAW_TEXT=$(cat "$KNOWLEDGE_DIR/raw/abstracts/${SLUG}.txt")
else
  echo "No raw source for $SLUG — skipping"
fi
```

### Step 8.4: Re-extract using Step 1.3 logic

Read the raw source text and apply the same extraction process as Step 1.3 (Extract intellectual content). The extraction targets the same 10 fields: findings, mechanisms, theories, methods, populations, data_sources, key_quotes, gap_claims, limitations, future_directions.

**Key difference from initial extraction**: Re-extraction PRESERVES any manually added or user-confirmed content. Specifically:
- If a field was populated during initial extraction AND re-extraction produces a different value, present both to the user and ask which to keep
- If a field was empty and re-extraction fills it, auto-accept the new value
- Edges (relationships) created by `user` are never modified; only `auto` edges may be refreshed

### Step 8.5: Update paper node

Remove the old paper record and append the updated one:

```bash
KNOWLEDGE_DIR="${SCHOLAR_KNOWLEDGE_DIR:-$HOME/.claude/scholar-knowledge}"
PAPER_ID="[PAPER_ID]"
# Remove old record
grep -v "\"id\":\"${PAPER_ID}\"" "$KNOWLEDGE_DIR/papers.ndjson" > "$KNOWLEDGE_DIR/papers.ndjson.tmp"
mv "$KNOWLEDGE_DIR/papers.ndjson.tmp" "$KNOWLEDGE_DIR/papers.ndjson"
# Append updated record (with new extraction_tier, updated_at, and enriched fields)
echo '[UPDATED_SINGLE_LINE_JSON]' >> "$KNOWLEDGE_DIR/papers.ndjson"
```

Update `updated_at` to current timestamp. Update `extraction_tier` if upgraded.

### Step 8.6: Update wiki (if exists)

If the wiki has been compiled, regenerate the paper page for each re-extracted paper (same as Step 1.10 incremental wiki update).

### Step 8.7: Report

```markdown
## Re-extraction Summary

| Metric | Count |
|--------|-------|
| Papers processed | [N] |
| Upgraded abstract_only → full_pdf | [N] |
| Upgraded metadata_only → abstract_only | [N] |
| Fields enriched | [N] new field values added |
| Skipped (no raw source) | [N] |

### Enrichment Details
| Paper | Previous Tier | New Tier | New Fields |
|-------|--------------|----------|------------|
| [title] | abstract_only | full_pdf | +limitations, +future_directions, +key_quotes |
```

---

## Close Process Log

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
SKILL_NAME="scholar-knowledge"
LOG_DATE=$(date +%Y-%m-%d)
LOG_FILE="${OUTPUT_ROOT}/logs/process-log-${SKILL_NAME}-${LOG_DATE}.md"
if [ ! -f "$LOG_FILE" ]; then
  LOG_FILE=$(ls -t "${OUTPUT_ROOT}"/logs/process-log-${SKILL_NAME}-${LOG_DATE}*.md 2>/dev/null | head -1)
fi
cat >> "$LOG_FILE" << LOGFOOTER

## Output Files
[list each output file path as a bullet]

## Summary
- **Steps completed**: [N completed]/[N total]
- **Files produced**: [count]
- **Errors**: [count, or 0]
- **Time finished**: $(date +%H:%M:%S)
LOGFOOTER
echo "Process log saved to $LOG_FILE"
```

---

## Quality Checklist

Before completing any mode, verify:

**All modes:**
- [ ] All paper IDs are deterministic (SHA-256 of DOI or lowercase title)
- [ ] No duplicate papers in `papers.ndjson` (checked via `kg_has_paper`)
- [ ] Each JSON line is valid single-line JSON
- [ ] Extracted findings are based on actual paper text, not hallucinated
- [ ] Limitations and future directions extracted from Discussion/Conclusion sections (not invented)
- [ ] Uncertain extractions marked with `[UNCERTAIN]` prefix
- [ ] Concepts are deduplicated (checked before append)
- [ ] `meta.json` updated after any write operation
- [ ] Process log captures all steps

**COMPILE mode (MODE 6):**
- [ ] All `[[wikilinks]]` in paper pages point to existing concept page filenames
- [ ] Paper page filenames follow `first-author-year.md` convention
- [ ] Concept pages list all papers that reference them (cross-checked against NDJSON)
- [ ] Topic clusters are meaningful (not single-paper topics unless truly unique)
- [ ] `contradictions.md` only includes papers connected by `contradicts` edges
- [ ] `gaps.md` aggregations are based on actual `gap_claims` and `future_directions` fields
- [ ] `index.md` counts match actual page counts in wiki directories
- [ ] `meta.json` has `last_compiled` timestamp updated

**ASK mode (MODE 7):**
- [ ] Answer is based on wiki content, not hallucinated knowledge
- [ ] All cited papers actually exist as wiki pages
- [ ] Confidence level accurately reflects graph coverage
- [ ] Answer saved to `wiki/answers/` with correct slug and date
- [ ] "What the Knowledge Graph Doesn't Cover" section is honest about gaps

**INGEST mode — raw storage (Step 1.2b):**
- [ ] Raw source saved BEFORE extraction (not after)
- [ ] `raw/` directory is append-only — no overwrites of existing raw files
- [ ] Zotero PDFs are symlinked, not copied
- [ ] Paper node includes `raw_path` (relative to `$KNOWLEDGE_DIR`) and `extraction_tier`
- [ ] API responses saved as complete JSON (not just parsed fields)

**RE-EXTRACT mode (MODE 8):**
- [ ] Re-extraction reads from `raw/` archive, not from original external source
- [ ] User-confirmed content (manual edits, user-created edges) is preserved
- [ ] `updated_at` timestamp refreshed; `extraction_tier` upgraded if applicable
- [ ] Wiki pages updated if wiki exists

---

## Integration with Other Skills

### Skills that READ from the knowledge graph:

| Skill | Integration Point | What it provides |
|---|---|---|
| `scholar-lit-review` | Step 1a-pre (before Zotero search) | Pre-discovered papers with extracted findings |
| `scholar-lit-review-hypothesis` | Step 1a-pre (before Zotero search) | Theories and mechanisms for hypothesis development |
| `scholar-write` | Step 0 Tier 0 (before citation pool build) | Pre-extracted findings to guide writing |
| `scholar-citation` | `scholar_search` Tier 0.5 | Enriched paper records in unified search |

### Skills that WRITE back to the knowledge graph (feedback loop):

The knowledge graph grows organically as you use other skills. These cross-skill filing integrations feed outputs back into the graph:

| Skill | What gets filed back | How |
|---|---|---|
| `scholar-analyze` | New empirical findings, methods used, data sources | Post-save: user prompted to run `/scholar-knowledge ingest from output [results-file]` |
| `scholar-write` | Cited papers, theoretical framing, identified gaps | Post-save: new citations can be ingested; gap claims from the Discussion section filed to graph |
| `scholar-lit-review` | Full paper inventory with findings | Post-save: auto-ingest via `/scholar-knowledge ingest from lit-review [output-file]` |
| `scholar-respond` | Reviewer-identified gaps, suggested references | Post-R&R: new references from reviewers can be ingested |
| `scholar-compute` | Computational findings, model outputs | Post-save: user prompted to file key results back |

**The feedback loop in practice**: You write a Results section with `scholar-write` → it cites papers from the knowledge graph → you file the new findings back via `ingest from output` → the graph knows your own findings → next time `scholar-write` runs, it can reference your prior work. This is Karpathy's "filing outputs back into the wiki to enhance it for further queries."

### Obsidian integration

The **compiled wiki** (`MODE 6: COMPILE`) is designed for Obsidian:
- Open `$KNOWLEDGE_DIR/wiki/` as an Obsidian vault for graph view, backlink navigation, and visual exploration
- See `references/obsidian-setup.md` for recommended plugins, graph view configuration, and usage patterns
- The `wiki/answers/` directory accumulates Q&A history — a growing research notebook
- Visual outputs (`knowledge-map.png`, `timeline.png`) render inline in Obsidian

Skills load the integration via:
```bash
SKILL_DIR="${SCHOLAR_SKILL_DIR:-.}/.claude/skills"
KG_REF="$SKILL_DIR/scholar-knowledge/references/knowledge-graph-search.md"
if [ -f "$KG_REF" ]; then
  eval "$(cat "$KG_REF" | sed -n '/^```bash/,/^```/p' | sed '1d;$d')" 2>/dev/null
fi
```

All integration hooks are guarded by `if [ -f "$KG_REF" ]` — skills work identically when scholar-knowledge is not installed.
