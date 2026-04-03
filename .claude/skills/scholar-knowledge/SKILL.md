---
name: scholar-knowledge
description: >
  User-scoped, cross-project knowledge graph that persists extracted intellectual
  content (findings, mechanisms, theories, paper relationships) across projects
  and sessions. Layers on top of Zotero to provide richer content than raw
  bibliographic metadata. Five modes: (1) INGEST — add papers from Zotero, PDF,
  lit-review output, DOI, or manual entry, extracting findings/theories/methods;
  (2) SEARCH — query the knowledge graph by topic, author, theory, method, or
  finding; (3) RELATE — add or view relationships between papers (cites,
  contradicts, extends, replicates, uses-method, uses-theory); (4) STATUS —
  show graph stats, recent additions, coverage by topic/method/theory;
  (5) EXPORT — export a project-specific subset as markdown or NDJSON.
  Storage: ~/.claude/scholar-knowledge/ (configurable via SCHOLAR_KNOWLEDGE_DIR).
tools: Read, Bash, Write, WebSearch, WebFetch
argument-hint: "[ingest|search|relate|status|export] [arguments], e.g., 'search theories of spatial assimilation' or 'ingest from zotero collection segregation' or 'relate Massey 1993 contradicts Clark 1986'"
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

echo "Knowledge graph directory: $KNOWLEDGE_DIR"
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
  "projects": ["segregation-paper-2026"]
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
| `from lit-review [path]` | Scholar-lit-review output | Parse existing literature review file |
| `from doi [DOI]` | CrossRef + Semantic Scholar | Fetch metadata from APIs |
| `from search-log [path]` | Search log file | Parse existing search log |
| `from manual` | User input | User provides structured entry |
| (no sub-argument with topic) | Zotero keyword | Default: search Zotero for topic |

### Step 1.2: Retrieve bibliographic metadata

**For Zotero source** — load refmanager-backends and search:

```bash
# Load reference manager backends
SKILL_DIR="${SCHOLAR_SKILL_DIR:-.}/.claude/skills"
eval "$(cat "$SKILL_DIR/scholar-citation/references/refmanager-backends.md" | sed -n '/^```bash/,/^```/p' | sed '1d;$d')" 2>/dev/null

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

**For lit-review output** — read the file and parse the paper inventory table.

**For search-log** — read the search log and parse the paper inventory snapshots.

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

- [ ] All paper IDs are deterministic (SHA-256 of DOI or lowercase title)
- [ ] No duplicate papers in `papers.ndjson` (checked via `kg_has_paper`)
- [ ] Each JSON line is valid single-line JSON
- [ ] Extracted findings are based on actual paper text, not hallucinated
- [ ] Limitations and future directions extracted from Discussion/Conclusion sections (not invented)
- [ ] Uncertain extractions marked with `[UNCERTAIN]` prefix
- [ ] Concepts are deduplicated (checked before append)
- [ ] `meta.json` updated after any write operation
- [ ] Process log captures all steps

---

## Integration with Other Skills

This skill provides the knowledge graph search layer used by:

| Skill | Integration Point | What it provides |
|---|---|---|
| `scholar-lit-review` | Step 1a-pre (before Zotero search) | Pre-discovered papers with extracted findings |
| `scholar-lit-review-hypothesis` | Step 1a-pre (before Zotero search) | Theories and mechanisms for hypothesis development |
| `scholar-write` | Step 0 Tier 0 (before citation pool build) | Pre-extracted findings to guide writing |
| `scholar-citation` | `scholar_search` Tier 0.5 | Enriched paper records in unified search |


Skills load the integration via:
```bash
SKILL_DIR="${SCHOLAR_SKILL_DIR:-.}/.claude/skills"
KG_REF="$SKILL_DIR/scholar-knowledge/references/knowledge-graph-search.md"
if [ -f "$KG_REF" ]; then
  eval "$(cat "$KG_REF" | sed -n '/^```bash/,/^```/p' | sed '1d;$d')" 2>/dev/null
fi
```

All integration hooks are guarded by `if [ -f "$KG_REF" ]` — skills work identically when scholar-knowledge is not installed.
