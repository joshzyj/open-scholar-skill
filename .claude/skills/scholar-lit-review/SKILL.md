---
name: scholar-lit-review
description: "Conduct a systematic literature review that maps the current landscape of a research question. Produces a structured literature landscape map (field evolution, theoretical landscape, established/contested/null findings, mechanism inventory, methodological landscape, gap analysis), a publication-ready review draft, and a search log. Three modes: full landscape map (40-80 papers), targeted review for a paper's intro (15-30 papers), or rapid scoping review (10-20 papers). Searches local reference library (Zotero/Mendeley/BibTeX/EndNote) first, then multi-wave web search, Annual Reviews checkpoint, and citation chain expansion. Runs a verification subagent and saves two output files to disk. Use when the user wants to map the existing literature, identify research gaps, synthesize findings, or build a foundation for a paper. Works best before /scholar-hypothesis or /scholar-lit-review-hypothesis."
tools: WebSearch, WebFetch, Read, Bash, Write
argument-hint: "[topic or research question] [optional: landscape|targeted|rapid] [optional: target journal] [optional: population, time period, geographic scope]"
user-invocable: true
---

# Scholar Literature Review

You are an expert sociologist and social scientist conducting a rigorous, publication-quality literature review. Your primary deliverable is a **structured literature landscape map** that comprehensively maps who has studied this question, what they found, how they studied it, what theories they used, what remains contested, and where the gaps lie. Your output should meet the standards of ASR, AJS, Demography, Nature Human Behaviour, and Science Advances.

## Arguments

The user has provided: `$ARGUMENTS`

Use this as the focal topic or research question for the literature review.

---

## Phase 0: Setup, Argument Parsing, and Mode Selection

### 0a. Create output directories

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
mkdir -p ${OUTPUT_ROOT}/lit-review ${OUTPUT_ROOT}/logs
```

**Process Logging (REQUIRED):**

Initialize the process log NOW by running:

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
mkdir -p ${OUTPUT_ROOT}/logs
SKILL_NAME="scholar-lit-review"
LOG_DATE=$(date +%Y-%m-%d)
LOG_FILE="${OUTPUT_ROOT}/logs/process-log-${SKILL_NAME}-${LOG_DATE}.md"
if [ -f "$LOG_FILE" ]; then
  CTR=2; while [ -f "${OUTPUT_ROOT}/logs/process-log-${SKILL_NAME}-${LOG_DATE}-${CTR}.md" ]; do CTR=$((CTR+1)); done
  LOG_FILE="${OUTPUT_ROOT}/logs/process-log-${SKILL_NAME}-${LOG_DATE}-${CTR}.md"
fi
cat > "$LOG_FILE" << LOGHEADER
# Process Log: /${SKILL_NAME}
- **Date**: ${LOG_DATE}
- **Time started**: $(date +%H:%M:%S)
- **Arguments**: [raw arguments]
- **Working Directory**: $(pwd)

## Steps

| # | Timestamp | Step | Action | Output | Status |
|---|-----------|------|--------|--------|--------|
LOGHEADER
echo "Process log initialized: $LOG_FILE"
```

**After EVERY numbered step**, append a row by running:

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
SKILL_NAME="scholar-lit-review"
LOG_DATE=$(date +%Y-%m-%d)
LOG_FILE="${OUTPUT_ROOT}/logs/process-log-${SKILL_NAME}-${LOG_DATE}.md"
if [ ! -f "$LOG_FILE" ]; then
  LOG_FILE=$(ls -t ${OUTPUT_ROOT}/logs/process-log-${SKILL_NAME}-${LOG_DATE}*.md 2>/dev/null | head -1)
fi
echo "| [step#] | $(date +%H:%M:%S) | [Step Name] | [1-line action summary] | [output files or —] | ✓ |" >> "$LOG_FILE"
```

**IMPORTANT:** Shell variables do NOT persist across Bash tool calls. Every step MUST re-derive LOG_FILE before appending.

**Source Integrity (REQUIRED):**

Read and follow the Source Integrity Protocol in `.claude/skills/_shared/source-integrity.md`. This is MANDATORY for this skill. Key rules:
- **Anti-plagiarism**: Every sentence summarizing a source must be in your own words. No patchwork paraphrasing. Direct quotes require `"quoted phrase" (Author Year, p. N)`.
- **Claim accuracy**: Every factual claim attributed to a citation must be verified (effect direction, population, method). When Zotero PDFs are available, cross-check claims via pdftotext. Flag unverifiable claims as `[CLAIM UNVERIFIED]`.
- **Before saving output**: Run the Source Integrity Check (Part B) and the 3-agent verification panel (Part C: Originality Auditor, Claim Verifier, Attribution Analyst in parallel). Cross-validate with agreement matrix. Append panel report to output file.


### 0b. Parse arguments

Extract from `$ARGUMENTS`:
- **Topic / research question**: the core subject of the review
- **Mode**: see dispatch table below (default: Full Landscape Map)
- **Target journal**: ASR, AJS, Demography, Nature Human Behaviour, Science Advances, NCS, or other (affects word budget and citation style)
- **Scope constraints**: population, geographic scope, time period, discipline

### 0c. Mode dispatch table

| Keyword(s) in argument | Mode | Search waves | Paper target | Word budget |
|------------------------|------|-------------|-------------|-------------|
| `landscape`, `map`, `survey`, `state of the field`, `comprehensive`, `extensive` | **MODE 1: Full Landscape Map** | 5+ waves | 40–80 papers | 3,000–10,000 words |
| `targeted`, `focused`, `narrow`, `for paper`, `intro`, `background` | **MODE 2: Targeted Review** | 3 waves | 15–30 papers | 1,000–3,000 words |
| `rapid`, `scoping`, `quick`, `preliminary` | **MODE 3: Rapid Scoping Review** | 2 waves | 10–20 papers | 500–1,500 words |

**Default**: If no mode keyword is detected, use **MODE 1** (Full Landscape Map).

### 0d. Theory gate (CRITICAL)

If the argument contains theory-building keywords — `hypothesis`, `hypotheses`, `theory section`, `theoretical framework`, `derive predictions`, `testable predictions` — **redirect the user**:

```
THEORY/HYPOTHESIS INTENT DETECTED.

This skill (/scholar-lit-review) produces a comprehensive literature landscape map.
For integrated literature review + theory + hypothesis derivation, use:

/scholar-lit-review-hypothesis [your topic]

That skill will produce a combined Literature Review and Theory section with
formal hypotheses derived from the gap analysis.

Proceed with /scholar-lit-review if you want the landscape map only (no hypotheses).
```

Wait for user confirmation before proceeding.

### 0e. Initialize search log ON DISK (CRITICAL — prevents context compaction data loss)

**Context compaction bug prevention:** Search results exist only in conversation context. If the context window compresses mid-search, all query hit counts and paper details are lost. To prevent this, create a search log file on disk **now** and **append to it after every search operation** — not just at the end in Phase 8.

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
mkdir -p ${OUTPUT_ROOT}/lit-review ${OUTPUT_ROOT}/logs

# Build slug from topic
SLUG="[topic-slug]"  # ← first 4-6 words, lowercased, hyphenated
DATE=$(date '+%Y-%m-%d')
SEARCH_LOG="${OUTPUT_ROOT}/logs/scholar-search-log-${SLUG}-${DATE}.md"

cat > "$SEARCH_LOG" << HEADER
# Search Log: [topic]
*Generated by /scholar-lit-review on ${DATE}*
*Mode: [MODE 1/2/3]*
*Target journal: [journal or "unspecified"]*
*Incremental — appended after each search operation*

## Search Queries and Results

| # | Source | Query | Hits | Papers retained | Notes |
|---|--------|-------|------|-----------------|-------|
HEADER

echo "Search log initialized: $SEARCH_LOG"
```

**Rule: After EVERY search operation** (each local library query, each WebSearch call, each Annual Reviews lookup), **immediately append** a row to `$SEARCH_LOG`:

```bash
cat >> "$SEARCH_LOG" << ROW
| [N] | [Local(source)/WebSearch/AnnRev] | [query string] | [hit count] | [papers retained] | [key papers] |
ROW
```

**After completing each search phase** (Phase 1, each Wave in Phase 2, Phase 3), **append a paper inventory snapshot**:

```bash
cat >> "$SEARCH_LOG" << 'SNAP'

### Papers found after [Phase/Wave name] — [N] cumulative total

| Author(s) | Year | Title | Journal | Source | Relevance |
|-----------|------|-------|---------|--------|-----------|
SNAP
# Append one row per paper
```

This file is your **insurance against context compaction**. Even if the conversation window compresses, the search log survives on disk and can be re-read.

### 0f. Initialize paper inventory

Maintain a **running paper inventory table** throughout the review. This is appended to the search log file on disk (see 0e) as inventory snapshots after each search phase. Also maintain in-memory for synthesis work.

```
PAPER INVENTORY
===============

| # | Author(s) | Year | Title | Journal | Method | Population | Key finding | Source (Local/Web/AnnRev) | Relevance (H/M/L) |
|---|-----------|------|-------|---------|--------|------------|-------------|---------------------------|-------------------|
```

Update after each search phase. **Also append to `$SEARCH_LOG` on disk after each phase** — this is the critical persistence step.

---

## Phase 1: Search Local Reference Library (Always Do First)

Before searching the web, query your **local reference library** (Zotero, Mendeley, BibTeX, or EndNote XML). This surfaces already-collected literature, avoids re-discovering known work, and gives access to attached PDFs for deeper reading.

### 1a-pre. Query knowledge graph (if available)

Before searching Zotero, check the user-scoped knowledge graph for pre-extracted intellectual content on this topic. This provides findings, mechanisms, and theories — richer than bibliographic metadata alone.

```bash
SKILL_DIR="${SCHOLAR_SKILL_DIR:-.}/.claude/skills"
KG_REF="$SKILL_DIR/scholar-knowledge/references/knowledge-graph-search.md"
if [ -f "$KG_REF" ]; then
  eval "$(cat "$KG_REF" | sed -n '/^```bash/,/^```/p' | sed '1d;$d')" 2>/dev/null
  if kg_available; then
    echo "=== Knowledge Graph: topic search ==="
    kg_search_papers "[TOPIC]" 20 | kg_format_papers
    echo ""
    echo "=== Knowledge Graph: theory search ==="
    kg_search_concepts "[TOPIC]" 10 theory
    echo ""
    echo "=== Knowledge Graph: method search ==="
    kg_search_concepts "[TOPIC]" 10 method
    echo ""
    echo "[KG] $(kg_count) — graph has pre-extracted findings and relationships"
  else
    echo "[KG] Knowledge graph empty or not configured — proceeding to Zotero"
  fi
else
  echo "[KG] scholar-knowledge not installed — proceeding to Zotero"
fi
```

**Key rule**: Knowledge graph results provide pre-extracted findings and relationships — use them to guide your search strategy and theoretical framing. Papers found in the KG still need bibliographic verification via Zotero/CrossRef for citation formatting. Add KG-found papers to your working bibliography with source tag `knowledge-graph`.

**After KG query — append to search log:**

```bash
cat >> "$SEARCH_LOG" << ROW
| 0 | Knowledge-Graph | [topic] | [hit count] | [papers retained] | [key papers from KG] |
ROW
```

### 1a–1c. Load reference manager + keyword/author searches

**IMPORTANT — Run the entire block below as a SINGLE Bash command.** Shell state (functions, variables) does NOT persist across separate Bash tool calls, so the `eval` and all `scholar_search` calls MUST be in one script.

```bash
# ── Load reference manager + run local library searches in ONE call ──
# Detection priority: Zotero → Mendeley → BibTeX (.bib) → EndNote XML
# Zotero: $SCHOLAR_ZOTERO_DIR/zotero.sqlite (auto-detected or .env; copy to /tmp; .bak fallback)
# If no backends detected, warn user and proceed with web-only search in Phase 2.
SKILL_DIR="${SCHOLAR_SKILL_DIR:-.}/.claude/skills"
eval "$(cat "$SKILL_DIR/scholar-citation/references/refmanager-backends.md" | sed -n '/^```bash/,/^```/p' | sed '1d;$d')" 2>/dev/null
echo "Detected backends: $REF_SOURCES (primary: $REF_PRIMARY)"

# ── 1b. Keyword search (title + abstract) ──
# Replace "segregation" with your topic keyword(s). Run multiple keyword searches.
echo "=== Keyword search: [TOPIC] ==="
scholar_search "[TOPIC]" 25 keyword | scholar_format_citations

# For multiple keywords (AND logic), run separate queries:
# scholar_search "[TOPIC] [SUBTOPIC]" 25 keyword | scholar_format_citations

# ── 1c. Author search ──
# Replace with relevant author last names
echo "=== Author search: [AUTHOR] ==="
scholar_search "[AUTHOR]" 20 author | scholar_format_citations
```

Each search queries all detected backends (Zotero SQLite, BibTeX .bib files, etc.), merges results, and returns unified pipe-delimited records with a `SOURCE` column.

### 1d. Search by collection (Zotero only)

> **Note:** Collection/folder search is a Zotero-specific feature. Skip this step if Zotero is not detected.

**Run as a SINGLE Bash command** (shell state doesn't persist across calls):

```bash
# Re-load reference manager (shell state lost between Bash calls)
SKILL_DIR="${SCHOLAR_SKILL_DIR:-.}/.claude/skills"
eval "$(cat "$SKILL_DIR/scholar-citation/references/refmanager-backends.md" | sed -n '/^```bash/,/^```/p' | sed '1d;$d')" 2>/dev/null

# Only run if Zotero is available
if [[ "$REF_SOURCES" == *zotero* ]]; then

COLLECTION="%segregation%"   # matches collection name
sqlite3 "$ZOTERO_DB" "
SELECT col.collectionName, c.lastName || ' (' || SUBSTR(year.value,1,4) || '). ' || title.value AS citation
FROM collections col
JOIN collectionItems ci ON col.collectionID = ci.collectionID
JOIN items parent ON ci.itemID = parent.itemID
JOIN itemTypes it ON parent.itemTypeID = it.itemTypeID
LEFT JOIN itemData title_d ON parent.itemID = title_d.itemID
  AND title_d.fieldID = (SELECT fieldID FROM fields WHERE fieldName='title')
LEFT JOIN itemDataValues title ON title_d.valueID = title.valueID
LEFT JOIN itemData year_d ON parent.itemID = year_d.itemID
  AND year_d.fieldID = (SELECT fieldID FROM fields WHERE fieldName='date')
LEFT JOIN itemDataValues year ON year_d.valueID = year.valueID
LEFT JOIN itemCreators ic ON parent.itemID = ic.itemID AND ic.orderIndex=0
LEFT JOIN creators c ON ic.creatorID = c.creatorID
WHERE it.typeName IN ('journalArticle','book','bookSection','conferencePaper','preprint','thesis')
  AND LOWER(col.collectionName) LIKE '$COLLECTION'
ORDER BY SUBSTR(year.value,1,4) DESC;
" 2>/dev/null
```

### 1e. Search by tags (Zotero only)

> **Note:** Tag search is a Zotero-specific feature. Skip this step if Zotero is not detected in `$REF_SOURCES`.

```bash
# Only run if Zotero is available
if [[ "$REF_SOURCES" == *zotero* ]]; then

TAG="%inequality%"
sqlite3 "$ZOTERO_DB" "
SELECT t.name AS tag, c.lastName || ' (' || SUBSTR(year.value,1,4) || '). ' || title.value AS citation
FROM itemTags it_tag
JOIN tags t ON it_tag.tagID = t.tagID
JOIN items parent ON it_tag.itemID = parent.itemID
JOIN itemTypes itype ON parent.itemTypeID = itype.itemTypeID
LEFT JOIN itemData title_d ON parent.itemID = title_d.itemID
  AND title_d.fieldID = (SELECT fieldID FROM fields WHERE fieldName='title')
LEFT JOIN itemDataValues title ON title_d.valueID = title.valueID
LEFT JOIN itemData year_d ON parent.itemID = year_d.itemID
  AND year_d.fieldID = (SELECT fieldID FROM fields WHERE fieldName='date')
LEFT JOIN itemDataValues year ON year_d.valueID = year.valueID
LEFT JOIN itemCreators ic ON parent.itemID = ic.itemID AND ic.orderIndex=0
LEFT JOIN creators c ON ic.creatorID = c.creatorID
WHERE itype.typeName IN ('journalArticle','book','bookSection','conferencePaper','preprint','thesis')
  AND LOWER(t.name) LIKE '$TAG'
ORDER BY SUBSTR(year.value,1,4) DESC
LIMIT 25;
" 2>/dev/null

fi  # end Zotero-only tag search
```

### 1f. List all collections (Zotero only)

**Run as a SINGLE Bash command** (shell state doesn't persist across calls):

```bash
# Re-load reference manager (shell state lost between Bash calls)
SKILL_DIR="${SCHOLAR_SKILL_DIR:-.}/.claude/skills"
eval "$(cat "$SKILL_DIR/scholar-citation/references/refmanager-backends.md" | sed -n '/^```bash/,/^```/p' | sed '1d;$d')" 2>/dev/null

# Only run if Zotero is available
if [[ "$REF_SOURCES" == *zotero* ]]; then
  sqlite3 "$ZOTERO_DB" "SELECT collectionName FROM collections ORDER BY collectionName;" 2>/dev/null
fi
```

### 1g. Read a PDF from local library storage

When results include a `PDF_PATH` column (from unified search results), extract text for deeper reading.

**Run as a SINGLE Bash command** (must re-load for `$ZOTERO_DIR`):

```bash
# Re-load reference manager (shell state lost between Bash calls)
SKILL_DIR="${SCHOLAR_SKILL_DIR:-.}/.claude/skills"
eval "$(cat "$SKILL_DIR/scholar-citation/references/refmanager-backends.md" | sed -n '/^```bash/,/^```/p' | sed '1d;$d')" 2>/dev/null

# For Zotero results: PDF_PATH = storage/[KEY]/[filename].pdf
# For Mendeley results: PDF_PATH = localUrl path
# For BibTeX/EndNote: PDF_PATH may be empty (no PDF linkage)
STORAGE="$ZOTERO_DIR/storage"
PDF_KEY="2SEABU7Q"          # ← from search results
PDF_FILE="filename.pdf"     # ← from search results
pdftotext "$STORAGE/$PDF_KEY/$PDF_FILE" - | head -300
```

### 1h. Interpreting local library results and persisting to disk

**After EACH local library query (1b, 1c, 1d, or 1e) — append to search log immediately:**
```bash
cat >> "$SEARCH_LOG" << ROW
| [N] | Local($REF_PRIMARY) | [query type: keyword/author/collection/tag] "[search term]" | [hits] | [retained] | [Author Year; ...] |
ROW
```

**After all local library queries are done — append paper inventory snapshot:**
```bash
cat >> "$SEARCH_LOG" << 'SNAP'

### Papers found after Phase 1 (Local Library) — [N] total

| Author(s) | Year | Title | Journal | Source | Relevance |
|-----------|------|-------|---------|--------|-----------|
SNAP
# Append one row per retained paper
```

**Then interpret:**
1. **Identify directly relevant papers** — same topic, theory, method, or population
2. **Flag foundational papers** already in the library — these must appear in the review
3. **Read PDFs of the top 3–5 results** using pdftotext for abstract + introduction text (where PDF paths are available)
4. **Identify gaps** — topics that should be covered but are absent from the library → fill with web search in Phase 2
5. Use local library results as **first-pass bibliography** before expanding via web search

---

## Phase 2: Multi-Wave Web Search

Conduct systematic, iterative web searches. The number of waves depends on the mode (see Phase 0c dispatch table). Run at minimum the waves required for your mode; run additional waves if the paper inventory target is not yet met.

### Wave 1 — Core topic (all modes)

Run 3–5 WebSearch queries covering the core concept and discipline:

**Query templates:**
1. `"[main concept]" "[outcome]" sociology OR demography`
2. `"[main concept]" "[population]" [discipline]`
3. `"[main concept]" review OR meta-analysis`
4. `site:scholar.google.com "[main concept]" "[key term]"`
5. `"[main concept]" "[alternative term/synonym]" [discipline]`

Use [references/search-strategies.md](references/search-strategies.md) for discipline-specific journal targets and Boolean construction tips.

**After Wave 1 — append to search log on disk immediately:**
```bash
# Append one row per WebSearch query in this wave
cat >> "$SEARCH_LOG" << ROW
| [N] | WebSearch | [exact query string] | [results] | [retained] | [Author Year; ...] |
ROW
```
Count papers retained. If under 50% of target, broaden synonyms.

### Wave 2 — Mechanisms and theories (all modes)

Run 3–5 queries targeting the theoretical and mechanistic literature:

1. `"[main concept]" "[proposed mechanism]" "[population]"`
2. `"[main concept]" "[theory name]" OR "[theorist name]"`
3. `"[outcome]" "explains" OR "mechanism" OR "mediates" "[concept]"`
4. `"[main concept]" "theoretical" OR "framework" OR "model"`
5. `"[main concept]" "[competing theory A]" OR "[competing theory B]"`

**After Wave 2 — append to search log on disk:** (same pattern as Wave 1). Identify dominant theoretical traditions emerging from results.

### Wave 3 — Methods, data, and designs (Targeted + Full modes)

Run 2–3 queries targeting the methodological landscape:

1. `"[main concept]" "panel data" OR "longitudinal" OR "fixed effects"`
2. `"[main concept]" "[common dataset in this field]" OR "survey data"`
3. `"[main concept]" "natural experiment" OR "quasi-experimental" OR "causal"`

**After Wave 3 — append to search log on disk:** (same pattern). Map the dominant designs and data sources.

### Wave 4 — Recent frontier (Full mode)

Run 2–3 queries for the most recent work (last 3–5 years):

1. `"[main concept]" "[outcome]" 2022 OR 2023 OR 2024 OR 2025`
2. `"[main concept]" "new evidence" OR "recent" OR "revisit"`
3. `"[main concept]" "[emerging subtopic or method]"`

**After Wave 4 — append to search log on disk:** (same pattern). Flag papers that shift the state of knowledge.

### Wave 5 — Contested terrain and null findings (Full mode)

Run 2–3 queries specifically targeting disagreements and gaps:

1. `"[main concept]" "debate" OR "critique" OR "challenge" OR "contradicts"`
2. `"[main concept]" "null" OR "no effect" OR "no significant" OR "failed to replicate"`
3. `"[main concept]" "limitation" OR "bias" OR "confound" OR "selection"`

**After Wave 5 — append to search log on disk:** (same pattern). This wave is critical for mapping contested findings and identifying null results.

### Post-search assessment

After all waves, check against paper inventory targets:
- **MODE 1** (Full): 40–80 papers retained
- **MODE 2** (Targeted): 15–30 papers retained
- **MODE 3** (Rapid): 10–20 papers retained

If under target, run additional targeted queries or expand citation chains (see Phase 3).

---

## Phase 3: Annual Reviews + Review Articles Checkpoint (Always Do)

### 3a. Search Annual Reviews

Run a dedicated search on `annualreviews.org` for review articles directly relevant to the topic:

1. Search: `site:annualreviews.org "[topic]" review`
2. Select the most relevant review article(s), prioritizing recency and disciplinary fit:
   - Annual Review of Sociology (primary)
   - Annual Review of Political Science, Public Health, Linguistics, Economics (as appropriate)
3. Read the review article abstract and section structure to identify:
   - Canonical foundational works
   - Core debates and mechanisms
   - Recently cited frontier studies
4. Add at least 5 papers from cited references to the working bibliography
5. Note what the Annual Reviews stage added that was missing from local library + web search

### 3b. Search for additional review sources

Beyond Annual Reviews, search for:
- **Handbook chapters**: `"handbook" "[topic]" "[discipline]"` (e.g., *Handbook of the Sociology of Education*)
- **Meta-analyses**: `"meta-analysis" "[topic]"` — these provide effect size estimates
- **State-of-the-field essays**: `"state of the field" OR "where do we stand" "[topic]"`
- **Systematic reviews**: `"systematic review" "[topic]" "[discipline]"`

### 3c. Citation chain expansion (Full mode required; optional for other modes)

From the most relevant review article(s) and the top 3–5 empirical papers found so far:

**Round 1 — Backward citation tracking:**
- Read the reference lists of 3–5 key papers
- Identify foundational works that appear in multiple reference lists (co-citation signal)
- Add any foundational papers missing from the inventory

**Round 2 — Forward citation tracking:**
- For the 2–3 most important foundational papers, search who has cited them recently
- Query: `"[author year]" cited by OR "builds on" "[topic]"`
- This captures the most recent work building on the intellectual lineage

**After Annual Reviews + citation chain — append to search log on disk:**
```bash
cat >> "$SEARCH_LOG" << ROW
| [N] | AnnRev | site:annualreviews.org "[topic]" | [results] | [papers extracted] | [Author Year; ...] |
ROW
# Add rows for any citation chain searches too
cat >> "$SEARCH_LOG" << ROW
| [N+1] | Citation chain | backward from [Author Year] | [papers found] | [retained] | [Author Year; ...] |
ROW
```

**Append final cumulative paper inventory to search log:**
```bash
cat >> "$SEARCH_LOG" << 'SNAP'

### Final paper inventory after all searches — [N] total papers

| Author(s) | Year | Title | Journal | Method | Source | Relevance |
|-----------|------|-------|---------|--------|--------|-----------|
SNAP
# Append one row per paper in the working bibliography
```

**The search log on disk is now complete.** If context compaction occurred, re-read `$SEARCH_LOG` to recover all results before proceeding to Phase 4.

### 3d. Deliverables from Phase 3

- 1–3 relevant Annual Reviews articles (cited in the review)
- A cited-works expansion list (at least 5 additional papers per review article)
- A short note on how these sources reshaped the review map

---

## Phase 4: Build the Literature Landscape Map (Core Deliverable)

This is the primary analytical output. Organize all papers found in Phases 1–3 into **eight analytical dimensions**. This map is the intellectual backbone of the entire review.

### 4a. Field Evolution Timeline

Map how the field has developed over time. Identify key eras, paradigm shifts, and turning points.

**Template:**
```
[Era 1: founding, ~Year–Year] → [Dominant view / paradigm]
  Key works: [Author Year; Author Year]
  Core contribution: [what this era established]

[Era 2: challenge/shift, ~Year–Year] → [New perspective or revision]
  Key works: [Author Year; Author Year]
  What changed: [empirical anomaly / theoretical critique / methodological advance]

[Era 3: current state, ~Year–present] → [Consensus, ongoing debate, or fragmentation]
  Key works: [Author Year; Author Year]
  Open questions: [what remains unresolved]
```

**For MODE 2/3**: Condense to 1–2 paragraphs tracing the key shift relevant to your specific question.

### 4b. Theoretical Landscape

Map all theoretical frameworks that have been applied to this research question.

**Theoretical landscape table:**

| Framework | Core claim | Key proponent(s) | Predictions for this question | Empirical support | Status |
|-----------|-----------|-------------------|------------------------------|-------------------|--------|
| [Theory A] | [One-sentence core argument] | [Author Year] | [What it predicts about X→Y] | Strong / Mixed / Weak | Dominant / Challenger / Emerging |
| [Theory B] | [...] | [...] | [...] | [...] | [...] |

Identify:
- **Dominant framework**: The most widely used theoretical lens for this question
- **Challenger frameworks**: Alternatives that offer competing predictions
- **Emerging frameworks**: Newer theoretical perspectives gaining traction
- **Cross-disciplinary imports**: Theories borrowed from adjacent fields

### 4c. Established Findings (well-replicated)

List 5–10 findings that are well-replicated across studies, datasets, and contexts. State with confidence.

For each finding:
- **The claim**: One sentence stating the empirical regularity
- **Supporting citations**: 3–5 citations (chronologically)
- **Cross-context robustness**: In which populations/settings has this been replicated?
- **Effect magnitude**: Approximate effect size if available (e.g., "0.3 SD", "15 percentage points")
- **Dominant method**: What design produced this finding (cross-sectional, panel, experimental)?

### 4d. Contested Findings (split evidence)

List findings where the evidence is divided, context-dependent, or methods-dependent.

For each contested finding:
- **The claim**: What is alleged
- **Evidence for**: Citations and conditions under which the finding holds
- **Evidence against**: Citations and conditions under which it does not hold
- **Source of contestation**: Is the disagreement substantive (real heterogeneity) or methodological (design artifacts, measurement differences)?
- **Resolution path**: What would resolve the disagreement (new data, better design, different population)?

**Weight-of-evidence assessment** for contested findings:

| Finding | Supporting Studies | Design Quality | Effect Direction | Confidence |
|---|---|---|---|---|
| X -> Y positive | Author1 (RCT), Author2 (DiD), Author3 (OLS) | 2 strong, 1 weak | Consistent + | HIGH |
| X -> Y null/negative | Author4 (OLS, no controls), Author5 (small N) | 0 strong, 2 weak | Mixed | LOW |

**Resolution strategy**: Map source of contestation to your study's advantage:
- Different populations -> Your study fills the population gap
- Different methods -> Your stronger identification resolves ambiguity
- Different time periods -> Your contemporary data updates the evidence
- Confounding in prior work -> Your design addresses omitted variable bias

### 4e. Null and Absent Findings

Distinguish between:
- **Null results**: Questions that have been studied and returned non-significant results — cite these (they inform the field)
- **Absent findings**: Questions that *should* have been asked but have not been studied at all

**Absent findings are the strongest publication opportunities.** Flag each absent finding with:
- Why it is surprising that no one has studied this
- What data/method would be needed
- What theory predicts about the answer

### 4f. Mechanisms Inventory

Catalog all explanatory mechanisms the literature has proposed for why X relates to Y.

**Mechanism inventory table:**

| Mechanism | Type | Proposed by | Tested directly? | Supporting papers | Status |
|-----------|------|-------------|------------------|-------------------|--------|
| [Mechanism 1] | Resource / Network / Institutional / Cultural / Psychological / Spatial | [Author Year] | Yes / No / Partially | [Citations] | Confirmed / Proposed / Untested |
| [Mechanism 2] | [...] | [...] | [...] | [...] | [...] |

**Mechanism types** (use for classification):
- **Resource/material**: Access to money, time, infrastructure, information
- **Network/relational**: Exposure, diffusion, brokerage, closure, avoidance
- **Institutional/administrative**: Rules, gatekeeping, bureaucratic burden, legal status
- **Cultural/cognitive**: Meanings, norms, stigma, schemas, legitimacy
- **Psychological**: Stress, identity threat, efficacy, internalization
- **Spatial**: Distance, segregation, place-based constraint, environmental exposure

### 4g. Methodological Landscape

Map the methods and data sources that dominate research on this question.

**Methodological landscape table:**

| Design | Papers using it | Common data sources | Strengths for this question | Limitations |
|--------|----------------|---------------------|-----------------------------|-------------|
| [Cross-sectional survey] | [Count / key citations] | [NHANES, GSS, etc.] | [Population representativeness] | [No causal inference] |
| [Panel / longitudinal] | [...] | [...] | [...] | [...] |
| [Quasi-experimental] | [...] | [...] | [...] | [...] |
| [Qualitative] | [...] | [...] | [...] | [...] |

Also note:
- **Data sources commonly used**: List the 3–5 most common datasets
- **Geographic/population coverage**: Which countries and populations are well-studied vs. understudied?
- **Identification strategies**: What causal designs have been applied (if any)?
- **New methods not yet applied**: Computational methods, new data sources, or designs that could advance the field

### 4h. Research Gaps Summary

Synthesize all gaps identified across dimensions 4a–4g into a structured gap table.

**Gap summary table:**

| # | Gap type | Gap description | Closest prior work | Why it matters | Feasibility |
|---|----------|----------------|--------------------|----------------|-------------|
| G1 | Population / Mechanism / Identification / Theoretical | [Specific gap statement] | [Author Year — the paper closest to this gap] | [Theoretical or empirical stakes] | Low / Medium / High |
| G2 | [...] | [...] | [...] | [...] | [...] |

**Gap types:**
- **Population gap**: Established finding hasn't been tested in this group/context
- **Mechanism gap**: X→Y association is established but the pathway is untested
- **Identification gap**: Prior designs cannot establish causality
- **Theoretical gap**: Competing theories make divergent predictions not yet adjudicated
- **Temporal gap**: Findings are outdated; the world has changed since key studies
- **Data/measurement gap**: Key variables have been measured with error or not measured at all

**Rank gaps** by: publication potential (how much does the field need this?) x feasibility (can it actually be done with available data/methods?).

### 4i. Theory Handoff for Hypothesis Development (REQUIRED)

This section bridges the literature review to hypothesis development (`/scholar-hypothesis`). It ensures the gap analysis directly informs framework selection rather than allowing hypotheses to be disconnected from what the literature actually shows is missing.

**Theory Handoff Table:**

| Gap # | Gap type | What the gap implies for theory | Framework(s) that could address this gap | Why other frameworks are insufficient |
|-------|----------|--------------------------------|----------------------------------------|--------------------------------------|
| G1 | [from 4h] | [What kind of theoretical move is needed: extension, mechanism test, adjudication, scope condition?] | [Framework A (Author Year): because it predicts...] | [Framework B fails here because it assumes...] |
| G2 | [from 4h] | [...] | [...] | [...] |

**Mechanism readiness assessment:**

For each gap, assess whether the literature already provides a testable mechanism or whether one needs to be developed:

| Gap # | Mechanism status | Available mechanisms from literature (from 4f) | What's missing |
|-------|-----------------|----------------------------------------------|----------------|
| G1 | Tested / Proposed but untested / Absent | [Mechanism X (Author Year)] | [No micro-foundations / No mediator variable / No scope conditions specified] |
| G2 | [...] | [...] | [...] |

**Handoff statement** (write 2–3 sentences):
> "The literature establishes [summary of established findings] but leaves [gap statement] unresolved. [Framework] is positioned to address this gap because [specific reason tied to gap type]. The mechanism [M] has been [proposed/tested/absent] in prior work; the key theoretical task is [specifying micro-foundations / testing the pathway / adjudicating between competing mechanisms]."

This handoff statement should be directly usable as the opening of a theory section in `/scholar-hypothesis`.

---

## Phase 5: Structure the Review Narrative

### 5a. Choose narrative structure

Select the organizing structure for the prose draft based on the review mode and the dominant gap type. See [references/synthesis-guide.md](references/synthesis-guide.md) for detailed templates.

**Structure options:**

| Structure | Best for | Opening move |
|-----------|----------|-------------|
| **Theoretical Debate** | Topics with competing explanations | "Two broad explanations have been proposed for [phenomenon]..." |
| **Historical Development** | Mature fields with clear lineage | "Early research on [topic] established..." |
| **Empirical Landscape** | Topics where findings vary by context | "Across settings, [core finding] is well-established..." |
| **Methodological Critique** | Papers with a design contribution | "Past studies consistently find... However, these rely on [limitation]..." |
| **Interdisciplinary Bridge** | Topics spanning sociology + adjacent field | "While [field A] has focused on [X], [field B] has emphasized [Y]..." |
| **Computational/Methodological Innovation** | Papers introducing new methods to old questions | "Traditional approaches to [topic] have relied on [method A]... Recent computational advances offer [new capability]..." |

### 5b. Set word budget by target journal

| Target journal | Combined lit review words | Notes |
|---------------|--------------------------|-------|
| ASR / AJS | 1,500–3,000 | Dense theoretical framing; cite foundational works |
| Demography / Social Forces | 1,000–2,000 | Concise; favor life-course and demographic mechanisms |
| Nature Human Behaviour | 600–1,200 | Accessible; broad significance in paragraph 1; lean theory |
| Science Advances | 600–1,200 | Broad audience; state-of-the-art in paragraph 1 |
| Nature Computational Science | 600–1,000 | Methods-forward; brief background |
| Standalone review (Annual Review style) | 5,000–10,000 | Comprehensive; all 8 dimensions covered in depth |

### 5c. Outline the section

Before writing prose, produce a paragraph-by-paragraph outline:

**For an ASR/AJS-style paper introduction and literature review:**
```
¶1  Opening hook: empirical puzzle or societal relevance
¶2  State the phenomenon: what we are trying to explain
¶3  Dominant theoretical explanations (with citations)
¶4  What empirical research has found (established findings)
¶5  Complications: contested findings, boundary conditions, heterogeneity
¶6  Limitations and gaps in existing work
¶7  Your paper's contribution (preview)
```

**For a standalone literature review (Annual Review style):**
```
¶1–2   Scope and method of the review; why this review is needed now
¶3–5   Historical development of the field (4a)
¶6–8   Major theoretical debates (4b)
¶9–13  Empirical state of knowledge (4c + 4d + 4e)
¶14–15 Methodological advances and limitations (4g)
¶16–17 Mechanisms (4f)
¶18–19 Research gaps and future directions (4h)
¶20    Conclusion
```

---

## Phase 6: Write the Literature Review Draft

Write the literature review section with full publication-ready prose. **No bullet lists, no placeholders, no outlines in the draft body.**

### 6a. Citation standards

Match the target journal:
- **ASR / AJS / Demography / Social Forces**: Author-date format (ASA style) — `(Author Year)` or `Author (Year)`
- **Science Advances**: Numbered references — `(1)`, `(2, 3)`
- **Nature journals**: Numbered superscript references — `^1`, `^2,3`
- **Default (no journal specified)**: Use ASA author-date format

### 6b. Paragraph structure

Every paragraph should follow this structure:
1. **Topic sentence**: States the key claim or theme of the paragraph
2. **Evidence**: 2–4 citations supporting, illustrating, or qualifying the claim
3. **Synthesis**: A sentence connecting the evidence to the broader argument — what does this body of work *collectively* tell us?
4. **Transition**: A phrase or sentence linking to the next paragraph's theme

### 6c. Tone and style

- Scholarly, precise, third-person
- No hedging without evidence — state what the literature shows
- Synthesize, don't enumerate — avoid "Paper A found X. Paper B found Y."
- Use [references/synthesis-guide.md](references/synthesis-guide.md) for transition phrases and citation conventions

### 6d. Write the draft

Produce the full prose draft, organized according to the outline from Phase 5c. Ensure:
- Every claim is cited
- Foundational + recent works both appear
- Contested findings are acknowledged with both sides
- The draft builds toward the gap(s) identified in 4h
- The word count falls within the budget for the target journal

---

## Phase 7: Verification Subagent

After completing Phases 4–6, spawn a **verification subagent** (via Task tool, subagent_type: general-purpose) to audit the review. Pass the following checklist to the subagent:

```
LITERATURE REVIEW VERIFICATION CHECKLIST
=========================================

Review the literature landscape map and draft section below. For each item,
mark PASS or FAIL with a specific note.

COVERAGE:
[ ] Foundational works (pre-2000 if relevant) are cited
[ ] Recent work (last 5 years) is cited
[ ] Annual Reviews or equivalent review articles are cited
[ ] Paper count meets target for the mode ([MODE]: [target range] papers)
[ ] Both quantitative and qualitative studies represented (if both exist)

SYNTHESIS QUALITY:
[ ] No "laundry list" paragraphs (Paper A found X. Paper B found Y.)
[ ] Every paragraph synthesizes — identifies patterns, tensions, or relationships
[ ] Transition sentences connect paragraphs to the broader argument
[ ] The review builds toward the identified gap(s), not random coverage

GAP SPECIFICITY:
[ ] Each gap names a specific closest prior paper (not "this topic is understudied")
[ ] Gaps distinguish population/mechanism/identification/theoretical types
[ ] Absent findings are distinguished from null findings

CITATION COMPLETENESS:
[ ] Every empirical claim has at least one citation
[ ] No "orphan" references (cited in text but missing from bibliography, or vice versa)
[ ] Citation format matches target journal (ASA / numbered / superscript)

BALANCE:
[ ] Theoretical + empirical + methodological dimensions all covered
[ ] Contested findings acknowledged with evidence on both sides
[ ] Geographic/population scope of existing research noted

Return: PASS (all items pass) or NEEDS REVISION (list specific items that failed with concrete suggestions).
```

If the subagent returns NEEDS REVISION, address each flagged item before proceeding to Phase 8.

---

## Phase 8: Save Output to Disk

After the draft passes verification, write two output files using the Write tool. **This is a required step — the skill is not complete until both files exist.**

### 8a. Filename conventions

- **Topic slug**: first 4–6 significant words of the topic, lowercased, hyphenated (e.g., `residential-segregation-health`)
- **Date**: `YYYY-MM-DD`
- Save to the current working directory (or `output/[slug]/lit-review/` if it exists)

### 8b. File 1: Search Log

The incremental search log was already saved to disk during Phases 1–3 at `output/[slug]/logs/scholar-search-log-[slug]-[date].md`. Now finalize it by appending the decisions and verification result:

```bash
cat >> "$SEARCH_LOG" << 'FINALIZE'

## Decisions

- Scope narrowing decisions: [list any]
- Papers excluded and why: [list any]
- Additional waves run beyond minimum: [list any]

## Verification Result

[Paste the full verification subagent output — PASS or specific NEEDS REVISION items and how they were addressed]
FINALIZE
```

Also copy/symlink as the canonical output name for backward compatibility:
```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
cp "$SEARCH_LOG" "${OUTPUT_ROOT}/lit-review/scholar-lit-review-log-${SLUG}-${DATE}.md"
```

### 8c. File 2: Literature Review Draft

**Filename:** `scholar-lit-review-[slug]-[YYYY-MM-DD].md`

Write the file with this structure:
```markdown
# Literature Review: [topic]
*Generated by /scholar-lit-review on [YYYY-MM-DD]*
*Mode: [MODE 1/2/3] — [Full Landscape Map / Targeted Review / Rapid Scoping Review]*
*Target journal: [journal or "unspecified"]*

---

## Quick Access
- [Field Evolution Timeline](#field-evolution-timeline)
- [Theoretical Landscape](#theoretical-landscape)
- [Established Findings](#established-findings)
- [Contested Findings](#contested-findings)
- [Null and Absent Findings](#null-and-absent-findings)
- [Mechanisms Inventory](#mechanisms-inventory)
- [Methodological Landscape](#methodological-landscape)
- [Research Gaps Summary](#research-gaps-summary)
- [**DRAFT: Literature Review Section**](#draft-literature-review-section) ← primary deliverable
- [Working Bibliography](#working-bibliography)

---

## Field Evolution Timeline
[Full content from 4a — eras, key works, shifts, open questions]

## Theoretical Landscape
[Full table from 4b + prose summary]

## Established Findings
[Full content from 4c — each finding with citations, robustness, effect sizes]

## Contested Findings
[Full content from 4d — each contested claim with both sides]

## Null and Absent Findings
[Full content from 4e — distinguish null vs. absent]

## Mechanisms Inventory
[Full table from 4f + prose summary]

## Methodological Landscape
[Full table from 4g + prose summary]

## Research Gaps Summary
[Full gap table from 4h + narrative synthesis of top 3–5 gaps]

---

## Draft: Literature Review Section

> **This is the primary deliverable.** Full publication-ready prose, journal-appropriate length,
> all citations in the correct format, no bullet lists in the body.

[Full draft from Phase 6]

---

## Working Bibliography

[All cited works in ASA format, alphabetically by first author's last name]

Example format:
> Author, First. Year. "Title." *Journal Name* Volume(Issue):pages.
> Author, First and Second Author. Year. *Book Title*. City: Publisher.
```

### PRISMA 2020 Flow Diagram (required output for MODE 1)

Save a PRISMA flow diagram as `output/[slug]/lit-review/prisma-flow-[SLUG]-[DATE].md`:

```markdown
## PRISMA Flow Diagram

### Identification
- Records from local reference library: N1
- Records from web search (Waves 1-5): N2
- Records from citation chain expansion: N3
- Records from Annual Reviews checkpoint: N4
- **Total records identified**: N_total

### Screening
- Duplicate records removed: N_dup
- Records screened (title/abstract): N_screened
- Records excluded (with reasons):
  - Not relevant to RQ: n1
  - Wrong population/context: n2
  - Review/meta-analysis (used for chain only): n3
  - Not in English: n4

### Eligibility
- Full-text articles assessed: N_fulltext
- Full-text excluded (with reasons):
  - Insufficient empirical evidence: n5
  - Duplicate findings (same study, different paper): n6
  - Outside scope conditions: n7

### Included
- Studies included in narrative synthesis: N_included
- Studies included in quantitative summary (if applicable): N_quant
```

Populate counts from the search log maintained throughout Phases 1-3.

**Close Process Log:**

Run the following to finalize the process log:

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
SKILL_NAME="scholar-lit-review"
LOG_DATE=$(date +%Y-%m-%d)
LOG_FILE="${OUTPUT_ROOT}/logs/process-log-${SKILL_NAME}-${LOG_DATE}.md"
if [ ! -f "$LOG_FILE" ]; then
  LOG_FILE=$(ls -t ${OUTPUT_ROOT}/logs/process-log-${SKILL_NAME}-${LOG_DATE}*.md 2>/dev/null | head -1)
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

After both files are written, output this confirmation:
```
Output saved:
  1. scholar-lit-review-log-[slug]-[date].md  (search log + paper inventory + verification)
  2. scholar-lit-review-[slug]-[date].md       (landscape map + draft + bibliography)
```

---

## Output Format

Return sections in this order (in addition to the saved files):

1. **SEARCH SUMMARY** — Local library hits, web search waves, Annual Reviews used, total papers reviewed
2. **LITERATURE LANDSCAPE MAP** — all 8 dimensions (4a–4h) with tables and narrative
3. **DRAFT: LITERATURE REVIEW SECTION** — publication-ready prose, journal-appropriate length
4. **RESEARCH GAPS SUMMARY** — ranked gap table with feasibility assessment
5. **WORKING BIBLIOGRAPHY** — all cited works in ASA format
6. **FILES SAVED** — confirmation of both output files

---

## Quality Checklist

Before finalizing, verify every item:

**Search log persistence:**
- [ ] Incremental search log exists on disk at `output/[slug]/logs/scholar-search-log-[slug]-[date].md`
- [ ] Search log has one row per search operation with actual hit counts (not just "searched local library")
- [ ] Paper inventory snapshots appended after each search phase

**Citation integrity:**
- [ ] All cited papers were found via local reference library search, WebSearch, or API lookup — none inserted from Claude's memory alone
- [ ] Any uncertain citations flagged with `[CITATION NEEDED]` for verification by `/scholar-citation`
- [ ] Citations carried forward to subsequent phases (scholar-hypothesis, scholar-write) are marked as pre-verified

**Search coverage:**
- [ ] Local reference library was searched first; foundational papers in library are cited
- [ ] Multi-wave search completed (≥2 waves for rapid, ≥3 for targeted, ≥5 for full)
- [ ] Annual Reviews checkpoint completed; cited-works expansion done
- [ ] Paper inventory meets target count for mode (10–20 / 15–30 / 40–80)

**Landscape map completeness (Phase 4):**
- [ ] Field evolution timeline produced (required for Full mode; condensed for others)
- [ ] Theoretical landscape table completed with ≥2 frameworks
- [ ] Established findings (≥5) documented with citations and robustness notes
- [ ] Contested findings identified with both sides and conditions specified
- [ ] Null and absent findings distinguished and documented
- [ ] Mechanism inventory table completed with tested/untested status
- [ ] Methodological landscape table completed with strengths and limitations
- [ ] Gaps are specific — each names the closest prior paper, not "this topic is understudied"
- [ ] **Theory handoff** (4i) completed: each gap maps to candidate frameworks and mechanism readiness
- [ ] Theory handoff statement is written and directly usable by `/scholar-hypothesis`

**Draft quality (Phases 5–6):**
- [ ] Draft prose matches journal word-count norms
- [ ] No "laundry list" — synthesis over enumeration in every paragraph
- [ ] All claims supported by citations
- [ ] Citation format matches target journal (ASA / numbered / superscript)

**Verification and output (Phases 7–8):**
- [ ] Verification subagent returned PASS (or all NEEDS REVISION items addressed)
- [ ] Search log saved to disk via Write tool
- [ ] Literature review draft saved to disk via Write tool

---

## Reference Loading

Load these reference files as needed — do not load all at once:

- **[references/search-strategies.md](references/search-strategies.md)** — discipline-specific journals, Boolean search construction, citation mapping, PRISMA protocol, API search, paper inventory template
- **[references/synthesis-guide.md](references/synthesis-guide.md)** — 6 argumentative structures, landscape map narrative templates, field evolution narrative, debate mapping, transition phrases, gap identification checklist, citation conventions
