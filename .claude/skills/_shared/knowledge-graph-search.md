# Knowledge Graph Search Layer

Reusable bash functions for querying the user-scoped knowledge graph. Load via `eval` in any skill's setup block, identical to `refmanager-backends.md`.

All search functions produce **pipe-delimited records**:
```
ID|AUTHORS|YEAR|TITLE|JOURNAL|DOI|FINDINGS|THEORIES|METHODS|SOURCE
```

`FINDINGS`, `THEORIES`, and `METHODS` are semicolon-separated lists within their field.

---

## 1. Initialization

```bash
# ── Knowledge Graph Initialization ─────────────────────────────
# Load .env for SCHOLAR_KNOWLEDGE_DIR
[ -f "${SCHOLAR_SKILL_DIR:-.}/.env" ] && . "${SCHOLAR_SKILL_DIR:-.}/.env" 2>/dev/null || true
[ -f "$HOME/.claude/.env" ] && . "$HOME/.claude/.env" 2>/dev/null || true

KNOWLEDGE_DIR="${SCHOLAR_KNOWLEDGE_DIR:-$HOME/.claude/scholar-knowledge}"
KG_PAPERS="$KNOWLEDGE_DIR/papers.ndjson"
KG_CONCEPTS="$KNOWLEDGE_DIR/concepts.ndjson"
KG_EDGES="$KNOWLEDGE_DIR/edges.ndjson"
KG_META="$KNOWLEDGE_DIR/meta.json"
```

---

## 2. Availability Check

```bash
kg_available() {
  [ -f "$KG_PAPERS" ] && [ -s "$KG_PAPERS" ]
}
```

---

## 3. Paper Search (keyword — title + findings + theories + methods + abstract)

```bash
kg_search_papers() {
  local QUERY="$1" LIMIT="${2:-20}"
  [ ! -f "$KG_PAPERS" ] && return

  # Case-insensitive grep for any word in the query across key fields
  local PATTERN=""
  for word in $(echo "$QUERY" | tr '[:upper:]' '[:lower:]' | tr ' ' '\n'); do
    [ -z "$word" ] && continue
    if [ -z "$PATTERN" ]; then
      PATTERN="$word"
    else
      PATTERN="${PATTERN}\\|${word}"
    fi
  done
  [ -z "$PATTERN" ] && return

  # Search across title, findings, theories, methods, abstract, mechanisms, gap_claims
  grep -i "$PATTERN" "$KG_PAPERS" 2>/dev/null | head -n "$LIMIT" | while IFS= read -r line; do
    # Extract fields using lightweight parsing (no jq dependency)
    local id=$(echo "$line" | sed 's/.*"id":"\([^"]*\)".*/\1/')
    local authors=$(echo "$line" | sed 's/.*"authors":\["\([^]]*\)"\].*/\1/' | tr '"' ' ' | tr ',' ';')
    local year=$(echo "$line" | sed 's/.*"year":\([0-9]*\).*/\1/')
    local title=$(echo "$line" | sed 's/.*"title":"\([^"]*\)".*/\1/')
    local journal=$(echo "$line" | sed 's/.*"journal":"\([^"]*\)".*/\1/')
    local doi=$(echo "$line" | sed 's/.*"doi":"\([^"]*\)".*/\1/')
    local findings=$(echo "$line" | sed 's/.*"findings":\[\([^]]*\)\].*/\1/' | tr '"' ' ' | tr ',' ';' | head -c 300)
    local theories=$(echo "$line" | sed 's/.*"theories":\[\([^]]*\)\].*/\1/' | grep -o '"name":"[^"]*"' | sed 's/"name":"//;s/"//' | tr '\n' ';')
    local methods=$(echo "$line" | sed 's/.*"methods":\[\([^]]*\)\].*/\1/' | tr '"' ' ' | tr ',' ';' | head -c 200)
    echo "${id}|${authors}|${year}|${title}|${journal}|${doi}|${findings}|${theories}|${methods}|knowledge-graph"
  done
}
```

---

## 4. Paper Search by Author

```bash
kg_search_papers_author() {
  local AUTHOR="$1" LIMIT="${2:-20}"
  [ ! -f "$KG_PAPERS" ] && return
  local AUTHOR_LOWER=$(echo "$AUTHOR" | tr '[:upper:]' '[:lower:]')
  grep -i "\"authors\".*${AUTHOR_LOWER}" "$KG_PAPERS" 2>/dev/null | head -n "$LIMIT" | while IFS= read -r line; do
    local id=$(echo "$line" | sed 's/.*"id":"\([^"]*\)".*/\1/')
    local authors=$(echo "$line" | sed 's/.*"authors":\["\([^]]*\)"\].*/\1/' | tr '"' ' ' | tr ',' ';')
    local year=$(echo "$line" | sed 's/.*"year":\([0-9]*\).*/\1/')
    local title=$(echo "$line" | sed 's/.*"title":"\([^"]*\)".*/\1/')
    local journal=$(echo "$line" | sed 's/.*"journal":"\([^"]*\)".*/\1/')
    local doi=$(echo "$line" | sed 's/.*"doi":"\([^"]*\)".*/\1/')
    echo "${id}|${authors}|${year}|${title}|${journal}|${doi}|||knowledge-graph"
  done
}
```

---

## 5. Concept Search (theories, methods, mechanisms, datasets)

```bash
kg_search_concepts() {
  local QUERY="$1" LIMIT="${2:-10}" CATEGORY="${3:-}"
  [ ! -f "$KG_CONCEPTS" ] && return
  local FILTER=""
  if [ -n "$CATEGORY" ]; then
    FILTER="\"category\":\"${CATEGORY}\""
  fi
  local PATTERN=$(echo "$QUERY" | tr '[:upper:]' '[:lower:]')
  if [ -n "$FILTER" ]; then
    grep -i "$PATTERN" "$KG_CONCEPTS" 2>/dev/null | grep "$FILTER" | head -n "$LIMIT"
  else
    grep -i "$PATTERN" "$KG_CONCEPTS" 2>/dev/null | head -n "$LIMIT"
  fi
}
```

---

## 6. Edge / Relationship Search

```bash
kg_search_edges() {
  local PAPER_ID="$1" REL_TYPE="${2:-}"
  [ ! -f "$KG_EDGES" ] && return
  if [ -n "$REL_TYPE" ]; then
    grep "\"$PAPER_ID\"" "$KG_EDGES" 2>/dev/null | grep "\"relationship\":\"${REL_TYPE}\""
  else
    grep "\"$PAPER_ID\"" "$KG_EDGES" 2>/dev/null
  fi
}

kg_search_edges_by_type() {
  local REL_TYPE="$1" LIMIT="${2:-50}"
  [ ! -f "$KG_EDGES" ] && return
  grep "\"relationship\":\"${REL_TYPE}\"" "$KG_EDGES" 2>/dev/null | head -n "$LIMIT"
}
```

---

## 7. Get Single Paper by ID or DOI

```bash
kg_get_paper() {
  local LOOKUP="$1"
  [ ! -f "$KG_PAPERS" ] && return
  # Try ID first, then DOI
  grep "\"id\":\"${LOOKUP}\"" "$KG_PAPERS" 2>/dev/null | head -1 \
    || grep "\"doi\":\"${LOOKUP}\"" "$KG_PAPERS" 2>/dev/null | head -1
}
```

---

## 8. Count Statistics

```bash
kg_count() {
  local papers=0 concepts=0 edges=0
  [ -f "$KG_PAPERS" ] && papers=$(wc -l < "$KG_PAPERS" | tr -d ' ')
  [ -f "$KG_CONCEPTS" ] && concepts=$(wc -l < "$KG_CONCEPTS" | tr -d ' ')
  [ -f "$KG_EDGES" ] && edges=$(wc -l < "$KG_EDGES" | tr -d ' ')
  echo "Papers: $papers | Concepts: $concepts | Relationships: $edges"
}
```

---

## 9. Check for Duplicate (by DOI or title similarity)

```bash
kg_has_paper() {
  local DOI="$1" TITLE="$2"
  [ ! -f "$KG_PAPERS" ] && echo "no" && return
  if [ -n "$DOI" ] && grep -q "\"doi\":\"${DOI}\"" "$KG_PAPERS" 2>/dev/null; then
    echo "yes_doi"
    return
  fi
  local TITLE_LOWER=$(echo "$TITLE" | tr '[:upper:]' '[:lower:]' | head -c 80)
  if [ -n "$TITLE_LOWER" ] && grep -qi "$(echo "$TITLE_LOWER" | head -c 40)" "$KG_PAPERS" 2>/dev/null; then
    echo "yes_title"
    return
  fi
  echo "no"
}
```

---

## 10. Append Paper Node

```bash
kg_append_paper() {
  local JSON_LINE="$1"
  mkdir -p "$KNOWLEDGE_DIR"
  echo "$JSON_LINE" >> "$KG_PAPERS"
}
```

---

## 11. Append Concept Node

```bash
kg_append_concept() {
  local JSON_LINE="$1"
  mkdir -p "$KNOWLEDGE_DIR"
  echo "$JSON_LINE" >> "$KG_CONCEPTS"
}
```

---

## 12. Append Edge

```bash
kg_append_edge() {
  local JSON_LINE="$1"
  mkdir -p "$KNOWLEDGE_DIR"
  echo "$JSON_LINE" >> "$KG_EDGES"
}
```

---

## 13. Update Meta File

```bash
kg_update_meta() {
  mkdir -p "$KNOWLEDGE_DIR"
  local papers=0 concepts=0 edges=0
  [ -f "$KG_PAPERS" ] && papers=$(wc -l < "$KG_PAPERS" | tr -d ' ')
  [ -f "$KG_CONCEPTS" ] && concepts=$(wc -l < "$KG_CONCEPTS" | tr -d ' ')
  [ -f "$KG_EDGES" ] && edges=$(wc -l < "$KG_EDGES" | tr -d ' ')
  cat > "$KG_META" << METAEOF
{
  "version": "1.0.0",
  "last_updated": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "paper_count": $papers,
  "concept_count": $concepts,
  "edge_count": $edges
}
METAEOF
}
```

---

## 14. Wiki Compile Helpers

```bash
kg_last_compile_time() {
  [ -f "$KG_META" ] && grep -o '"last_compiled":"[^"]*"' "$KG_META" 2>/dev/null | sed 's/.*"last_compiled":"//;s/"//'
}

kg_papers_since() {
  local SINCE="$1"
  [ ! -f "$KG_PAPERS" ] && return
  [ -z "$SINCE" ] && cat "$KG_PAPERS" && return
  grep "\"ingested_at\":\"" "$KG_PAPERS" | awk -v since="$SINCE" -F'"ingested_at":"' '{split($2,a,"\""); if(a[1] >= since) print}'
}

kg_wiki_exists() {
  [ -d "$KNOWLEDGE_DIR/wiki/papers" ] && [ -f "$KNOWLEDGE_DIR/wiki/index.md" ]
}

kg_paper_slug() {
  # Generate filename slug from first author + year: "fiel-2017"
  local AUTHORS="$1" YEAR="$2"
  local FIRST=$(echo "$AUTHORS" | sed 's/,.*//' | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//')
  echo "${FIRST}-${YEAR}"
}

# ── Raw Storage Helpers ──
kg_raw_dir() {
  echo "$KNOWLEDGE_DIR/raw"
}

kg_save_raw_abstract() {
  # Save abstract/text to raw/abstracts/[slug].txt (append-only: skip if exists)
  local SLUG="$1" TEXT="$2"
  local RAW_DIR="$KNOWLEDGE_DIR/raw/abstracts"
  mkdir -p "$RAW_DIR"
  if [ ! -f "$RAW_DIR/${SLUG}.txt" ]; then
    echo "$TEXT" > "$RAW_DIR/${SLUG}.txt"
    echo "raw/abstracts/${SLUG}.txt"
  else
    echo "raw/abstracts/${SLUG}.txt"
  fi
}

kg_save_raw_api() {
  # Save API JSON response to raw/api-responses/[slug].json (append-only)
  local SLUG="$1" JSON_FILE="$2"
  local RAW_DIR="$KNOWLEDGE_DIR/raw/api-responses"
  mkdir -p "$RAW_DIR"
  if [ ! -f "$RAW_DIR/${SLUG}.json" ]; then
    cp "$JSON_FILE" "$RAW_DIR/${SLUG}.json"
    echo "raw/api-responses/${SLUG}.json"
  else
    echo "raw/api-responses/${SLUG}.json"
  fi
}

kg_link_raw_pdf() {
  # Symlink a PDF to raw/pdfs/[slug].pdf (append-only)
  local SLUG="$1" PDF_PATH="$2"
  local RAW_DIR="$KNOWLEDGE_DIR/raw/pdfs"
  mkdir -p "$RAW_DIR"
  if [ ! -L "$RAW_DIR/${SLUG}.pdf" ] && [ -f "$PDF_PATH" ]; then
    ln -sf "$PDF_PATH" "$RAW_DIR/${SLUG}.pdf"
    echo "raw/pdfs/${SLUG}.pdf"
  else
    echo "raw/pdfs/${SLUG}.pdf"
  fi
}

kg_get_raw_text() {
  # Read raw text for a paper (tries PDF first, then abstract)
  local SLUG="$1"
  local RAW_DIR="$KNOWLEDGE_DIR/raw"
  if [ -f "$RAW_DIR/pdfs/${SLUG}.pdf" ]; then
    pdftotext "$RAW_DIR/pdfs/${SLUG}.pdf" - 2>/dev/null | head -400
  elif [ -f "$RAW_DIR/abstracts/${SLUG}.txt" ]; then
    cat "$RAW_DIR/abstracts/${SLUG}.txt"
  fi
}

kg_extraction_tier_for() {
  # Determine best extraction tier for a paper based on available raw sources
  local SLUG="$1"
  local RAW_DIR="$KNOWLEDGE_DIR/raw"
  if [ -f "$RAW_DIR/pdfs/${SLUG}.pdf" ]; then
    echo "full_pdf"
  elif [ -f "$RAW_DIR/abstracts/${SLUG}.txt" ]; then
    echo "abstract_only"
  else
    echo "metadata_only"
  fi
}
```

---

## 15. Format for Display

```bash
kg_format_papers() {
  # Reads pipe-delimited KG search output, formats as a readable table
  echo "| # | Authors | Year | Title | Journal | Findings (excerpt) |"
  echo "|---|---------|------|-------|---------|-------------------|"
  local n=0
  while IFS='|' read -r id authors year title journal doi findings theories methods source; do
    [ -z "$id" ] && continue
    n=$((n + 1))
    local short_findings=$(echo "$findings" | head -c 80)
    echo "| $n | $authors | $year | $title | $journal | ${short_findings}... |"
  done
}
```

---

## Usage from Other Skills

Load the knowledge graph search layer in any skill:

```bash
# Load knowledge graph functions (if scholar-knowledge is installed)
SKILL_DIR="${SCHOLAR_SKILL_DIR:-.}/.claude/skills"
KG_REF="$SKILL_DIR/scholar-knowledge/references/knowledge-graph-search.md"
if [ -f "$KG_REF" ]; then
  eval "$(cat "$KG_REF" | sed -n '/^```bash/,/^```/p' | sed '1d;$d')" 2>/dev/null
  if kg_available; then
    echo "[KG] Knowledge graph loaded — $(kg_count)"
    # Example: search for papers on a topic
    kg_search_papers "residential segregation" 15 | kg_format_papers
  else
    echo "[KG] Knowledge graph empty — run /scholar-knowledge ingest to populate"
  fi
else
  echo "[KG] scholar-knowledge not installed — skipping knowledge graph"
fi
```

**Verification label**: Papers found via knowledge graph use `VERIFIED-LOCAL(knowledge-graph)`.
