---
name: scholar-lit-review-hypothesis
description: Conduct a systematic literature review AND develop theory and hypotheses in one integrated workflow. Use when the user wants to map existing knowledge, identify gaps, select theoretical frameworks that address those gaps, specify mechanisms, and derive testable hypotheses — producing a publication-ready Literature Review and Theory section. Works best after /scholar-idea. Replaces running /scholar-lit-review and /scholar-hypothesis separately.
tools: WebSearch, WebFetch, Read, Bash, Write
argument-hint: "[RQ or topic] [optional: target journal, population, method preferences]"
user-invocable: true
---

# Scholar Literature Review and Hypothesis Development

You are an expert sociologist conducting a rigorous, publication-quality literature review that flows directly into theoretical framework development and hypothesis derivation. Your output should meet the standards of ASR, AJS, Demography, Nature Human Behaviour, and Science Advances.

## Core Logic

Literature review and theory are not sequential steps — they are a single integrated argument:
1. **What the literature has established** → grounds your contribution in existing knowledge
2. **What the literature has left unresolved** → defines the explanatory gap your paper fills
3. **Which theoretical framework addresses that gap** → your paper's theoretical contribution
4. **What mechanism the framework predicts** → the causal chain you will test
5. **What hypotheses follow from the mechanism** → the testable predictions

Every step feeds the next. Do not produce a generic theory section disconnected from what the literature says is missing.

## Arguments

The user has provided: `$ARGUMENTS`

Parse:
- Core research question or topic
- Target journal (if mentioned — determines prose style, word length, and theory depth)
- Population, context, time period
- Methodological preferences or constraints

---

## PHASE 1: LITERATURE SEARCH

### Step 0a: Initialize Incremental Search Log (CRITICAL — Do Before Any Search)

**Context compaction bug prevention:** Search results exist only in conversation context. If the context window compresses mid-search, all query hit counts and paper details are lost. To prevent this, create a search log file on disk **before any search** and **append to it after every search operation**.

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
mkdir -p "${OUTPUT_ROOT}/logs"

# Process Logging — see below
```

**Process Logging (REQUIRED):**

Initialize the process log NOW by running:

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
mkdir -p "${OUTPUT_ROOT}/logs"
SKILL_NAME="scholar-lit-review-hypothesis"
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
SKILL_NAME="scholar-lit-review-hypothesis"
LOG_DATE=$(date +%Y-%m-%d)
LOG_FILE="${OUTPUT_ROOT}/logs/process-log-${SKILL_NAME}-${LOG_DATE}.md"
if [ ! -f "$LOG_FILE" ]; then
  LOG_FILE=$(ls -t "${OUTPUT_ROOT}"/logs/process-log-${SKILL_NAME}-${LOG_DATE}*.md 2>/dev/null | head -1)
fi
echo "| [step#] | $(date +%H:%M:%S) | [Step Name] | [1-line action summary] | [output files or —] | ✓ |" >> "$LOG_FILE"
```

**IMPORTANT:** Shell variables do NOT persist across Bash tool calls. Every step MUST re-derive LOG_FILE before appending.

**Source Integrity (REQUIRED):**

Read and follow the Source Integrity Protocol in `.claude/skills/_shared/source-integrity.md`. This is MANDATORY for this skill. Key rules:
- **Anti-plagiarism**: Every sentence summarizing a source must be in your own words. No patchwork paraphrasing. Direct quotes require `"quoted phrase" (Author Year, p. N)`.
- **Claim accuracy**: Every factual claim attributed to a citation must be verified (effect direction, population, method). When Zotero PDFs are available, cross-check claims via pdftotext. Flag unverifiable claims as `[CLAIM UNVERIFIED]`.
- **Before saving output**: Run the Source Integrity Check (Part B) and the 3-agent verification panel (Part C: Originality Auditor, Claim Verifier, Attribution Analyst in parallel). Cross-validate with agreement matrix. Append panel report to output file.


```bash
# Build slug from topic (first 4-6 words, lowercased, hyphenated)
SLUG="[topic-slug]"  # ← replace with actual slug
DATE=$(date '+%Y-%m-%d')
SEARCH_LOG="${OUTPUT_ROOT}/logs/scholar-search-log-${SLUG}-${DATE}.md"

cat > "$SEARCH_LOG" << 'HEADER'
# Search Log
*Generated by /scholar-lit-review-hypothesis*
*Incremental — appended after each search operation*

## Search Queries and Results

| # | Source | Query / Keywords | Hits | Retained | Key papers found |
|---|--------|-----------------|------|----------|-----------------|
HEADER

echo "Search log initialized: $SEARCH_LOG"
```

**Rule: After EVERY search operation (each local library query, each WebSearch call, each Annual Reviews lookup), immediately append results to `$SEARCH_LOG` using this pattern:**

```bash
# Append after each search operation — run IMMEDIATELY after results are returned
cat >> "$SEARCH_LOG" << ROW
| [N] | [RefLib/WebSearch/AnnRev] | [query string or keywords] | [hit count] | [papers kept] | [Author Year; Author Year; ...] |
ROW
```

**After all searches in a step are done, also append a paper inventory snapshot:**

```bash
cat >> "$SEARCH_LOG" << SNAP

### Papers found after [Step 0/Step 2/Step 3] — [N] total

| Author(s) | Year | Title | Journal | Source |
|-----------|------|-------|---------|--------|
| [last name] | [year] | [title] | [journal] | [RefLib/Web/AnnRev] |
SNAP
```

This file is your **insurance against context compaction**. Even if the conversation window compresses, the search log survives on disk and can be re-read.

---

### Step 0b-pre: Query Knowledge Graph (if available)

Before searching Zotero, check the user-scoped knowledge graph for pre-extracted intellectual content — findings, mechanisms, theories, and inter-paper relationships.

```bash
SKILL_DIR="${SCHOLAR_SKILL_DIR:-.}/.claude/skills"
KG_REF="$SKILL_DIR/scholar-knowledge/references/knowledge-graph-search.md"
if [ -f "$KG_REF" ]; then
  eval "$(cat "$KG_REF" | sed -n '/^```bash/,/^```/p' | sed '1d;$d')" 2>/dev/null
  if kg_available; then
    echo "=== Knowledge Graph: topic search ==="
    kg_search_papers "[TOPIC]" 20 | kg_format_papers
    echo ""
    echo "=== Knowledge Graph: theories ==="
    kg_search_concepts "[TOPIC]" 10 theory
    echo ""
    echo "=== Knowledge Graph: mechanisms ==="
    kg_search_concepts "[TOPIC]" 10 mechanism
    echo ""
    echo "[KG] $(kg_count) — pre-extracted findings and relationships available"
  else
    echo "[KG] Knowledge graph empty or not configured — proceeding to Zotero"
  fi
else
  echo "[KG] scholar-knowledge not installed — proceeding to Zotero"
fi
```

Use KG results to: (1) identify already-known theories and mechanisms for hypothesis development, (2) find contested findings that motivate hypotheses, (3) avoid re-searching for papers already in the graph. Add KG-found papers to your working bibliography with source tag `knowledge-graph`.

**After KG query — append to search log:**
```bash
cat >> "$SEARCH_LOG" << ROW
| 0 | Knowledge-Graph | [topic] | [hit count] | [papers retained] | [key papers from KG] |
ROW
```

### Step 0b: Search Local Reference Library (Always Do First)

Before searching the web, query your **local reference library** (Zotero, Mendeley, BibTeX, or EndNote XML). This surfaces already-collected literature, avoids re-discovering known work, and gives access to attached PDFs.

#### Detect available reference sources

Load the reference manager backends and run auto-detection:

**IMPORTANT — Run the entire block below as a SINGLE Bash command.** Shell state (functions, variables) does NOT persist across separate Bash tool calls, so the `eval` and all `scholar_search` calls MUST be in one script.

```bash
# ── Load reference manager + run local library searches in ONE call ──
SKILL_DIR="${SCHOLAR_SKILL_DIR:-.}/.claude/skills"
eval "$(cat "$SKILL_DIR/scholar-citation/references/refmanager-backends.md" | sed -n '/^```bash/,/^```/p' | sed '1d;$d')" 2>/dev/null

# Detection priority: Zotero → Mendeley → BibTeX → EndNote XML
# Zotero: $SCHOLAR_ZOTERO_DIR/zotero.sqlite (auto-detected or set in .env; copy to /tmp; .bak fallback)
# If no backends detected, warn user and proceed with web-only search in Step 2.
echo "Detected backends: $REF_SOURCES (primary: $REF_PRIMARY)"

# ── Keyword search (title + abstract) ──
# Replace "keyword" with your topic keyword(s)
echo "=== Keyword search: [YOUR_TOPIC] ==="
scholar_search "[YOUR_TOPIC]" 25 keyword | scholar_format_citations

# ── Author search ──
# Replace "author_name" with relevant author last names
echo "=== Author search: [AUTHOR_NAME] ==="
scholar_search "[AUTHOR_NAME]" 20 author | scholar_format_citations
```

Run **multiple keyword searches** (replace placeholders above) to cover: core topic, mechanism, methods/data terms. Each search queries all detected backends (Zotero SQLite, BibTeX .bib files, etc.), merges results, and returns unified pipe-delimited records with a `SOURCE` column.

For **multiple keywords (AND logic)**, run separate queries and intersect:
```bash
scholar_search "segregation mobility" 25 keyword
# Or run two searches and keep papers appearing in both result sets
```

#### Author search

```bash
# Unified author search — queries all detected backends
scholar_search "smith" 20 author
```

Replace `"zhang"` with the target author's last name. Results include papers by that author from all detected reference sources.

#### Collection search (Zotero only)

> **Note:** Collection/folder search is a Zotero-specific feature. Skip this step if Zotero is not detected in `$REF_SOURCES`.

```bash
# Only run if Zotero is available
if [[ "$REF_SOURCES" == *zotero* ]]; then

COLLECTION="%keyword%"   # matches collection name
sqlite3 "$ZOTERO_DB" "
SELECT col.collectionName, c.lastName || ' (' || SUBSTR(year.value,1,4) || '). ' || title.value AS citation
FROM collections col
JOIN collectionItems ci ON col.collectionID = ci.collectionID
JOIN items parent ON ci.itemID = parent.itemID
LEFT JOIN itemData title_d ON parent.itemID = title_d.itemID
  AND title_d.fieldID = (SELECT fieldID FROM fields WHERE fieldName='title')
LEFT JOIN itemDataValues title ON title_d.valueID = title.valueID
LEFT JOIN itemData year_d ON parent.itemID = year_d.itemID
  AND year_d.fieldID = (SELECT fieldID FROM fields WHERE fieldName='date')
LEFT JOIN itemDataValues year ON year_d.valueID = year.valueID
LEFT JOIN itemCreators ic ON parent.itemID = ic.itemID AND ic.orderIndex=0
LEFT JOIN creators c ON ic.creatorID = c.creatorID
WHERE LOWER(col.collectionName) LIKE LOWER('$COLLECTION')
GROUP BY parent.itemID
ORDER BY SUBSTR(year.value,1,4) DESC;
" 2>/dev/null

fi
```

#### Read a PDF from local library storage

When results include a `PDF_PATH` column (from unified search results), extract text for deeper reading:

```bash
# Generic PDF reading (works for any backend that returns PDF_PATH)
if [ -n "$PDF_PATH" ] && [ -f "$PDF_PATH" ]; then
  pdftotext "$PDF_PATH" - | head -300
fi
```

For Zotero specifically, you can also construct the path from search results:
```bash
if [[ "$REF_SOURCES" == *zotero* ]]; then
  STORAGE="$ZOTERO_DIR/storage"
  PDF_KEY="2SEABU7Q"          # ← from search results
  PDF_FILE="filename.pdf"     # ← from search results
  pdftotext "$STORAGE/$PDF_KEY/$PDF_FILE" - | head -300
fi
```

**After EACH local library query — append to search log immediately:**
```bash
# Count results from the query that just ran
HITS=[number of rows returned]
KEPT=[number of relevant papers retained]
cat >> "$SEARCH_LOG" << ROW
| [N] | RefLib | [keyword used, e.g., "linguistic discrimination"] | $HITS | $KEPT | [Author Year; Author Year; ...] |
ROW
```

**After ALL local library queries are complete — append paper inventory snapshot:**
```bash
cat >> "$SEARCH_LOG" << 'SNAP'

### Papers found after Step 0 (Local Library) — [N] total

| Author(s) | Year | Title | Journal | Source |
|-----------|------|-------|---------|--------|
SNAP
# Then append one row per retained paper:
echo "| [LastName] | [Year] | [Title] | [Journal] | [RefLib] |" >> "$SEARCH_LOG"
```

**Then proceed with interpretation:**
- Flag the 5-10 most relevant papers; these must appear in the final review
- Read PDFs of the top 3-5 using pdftotext (where PDF paths are available)
- Identify gaps -- topics that should be covered but are absent from the library -- fill with web search in Step 2

---

### Step 1: Scope the Review

Define before searching:
- **RQ axis**: What outcome, what predictor, what population?
- **Theoretical traditions** most relevant (provisional — may revise after Step 2)
- **Empirical scope**: Which countries, time periods, datasets dominate this lit?
- **Review type**: Is this for an intro/background section (paper-style) or a standalone review (Annual Reviews style)?

Set a **word budget** based on target journal:
- ASR / AJS: 2,000–3,500 words for combined lit review + theory
- Demography / Social Forces: 1,500–2,500 words
- Nature journals / Science Advances: 800–1,500 words (integrated into intro)

---

### Step 2: Web Search

Run at least **3 search query types** per main angle using WebSearch:

**Query type 1 — Core topic:**
`"[main concept]" "[outcome]" sociology OR demography`

**Query type 2 — Mechanism:**
`"[proposed mechanism]" "[population]" "[outcome]"`

**Query type 3 — Methods/data:**
`"[topic]" "panel data" OR "natural experiment" OR "longitudinal"`

**Query type 4 — Recent frontier (last 5 years):**
`"[topic]" "[outcome]" after:2020`

**Query type 5 — Contested terrain:**
`"[topic]" "debate" OR "critique" OR "challenge" OR "revisit"`

Use [references/search-strategies.md](references/search-strategies.md) for discipline-specific journal targets and Boolean construction tips.

**After EACH WebSearch query — append to search log immediately:**
```bash
# After each WebSearch call returns results
cat >> "$SEARCH_LOG" << ROW
| [N] | WebSearch | [exact query string] | [results returned] | [papers retained] | [Author Year; Author Year; ...] |
ROW
```

**After ALL web searches are complete — append cumulative paper inventory snapshot:**
```bash
cat >> "$SEARCH_LOG" << 'SNAP'

### Papers found after Step 2 (Web Search) — [N] cumulative total

| Author(s) | Year | Title | Journal | Source |
|-----------|------|-------|---------|--------|
SNAP
# Append one row per NEW paper found in this step
```

---

### Step 3: Annual Reviews Checkpoint (Always Do)

Search `annualreviews.org` for a review article directly relevant to the topic:

1. Query: `site:annualreviews.org "[topic]" review`
2. Select the most relevant review article (prioritize Annual Review of Sociology; also check Annual Review of Political Science, Public Health, Linguistics as appropriate)
3. From the review article, extract:
   - Canonical foundational works (these must be cited)
   - Core theoretical debates (feed directly into Phase 3)
   - Frontier studies from the last 3–5 years
4. Add at least 5 papers from this step to the working bibliography if not already found

### Step 3b: Citation Chain Expansion (REQUIRED)

After Annual Reviews checkpoint (Step 3), expand the search via citation chains:
1. **Backward**: From the 5 most-cited papers in your search log, check their reference lists for relevant papers not yet found
2. **Forward**: For the 5 foundational papers, search "cited by" via Semantic Scholar API or Google Scholar
3. Add newly found papers to search log with source = "citation-chain"

**After Annual Reviews checkpoint — append to search log immediately:**
```bash
cat >> "$SEARCH_LOG" << ROW
| [N] | AnnRev | site:annualreviews.org "[topic]" | [results found] | [papers extracted] | [Author Year; Author Year; ...] |
ROW
```

**After citation chain expansion — append to search log:**
```bash
cat >> "$SEARCH_LOG" << ROW
| [N+1] | Citation-chain | backward/forward from [Author Year] | [papers found] | [retained] | [Author Year; ...] |
ROW
```

**Append final cumulative paper inventory:**
```bash
cat >> "$SEARCH_LOG" << 'SNAP'

### Final paper inventory after all searches — [N] total papers

| Author(s) | Year | Title | Journal | Source | Relevance (H/M/L) |
|-----------|------|-------|---------|--------|--------------------|
SNAP
# Append one row per paper in the final working bibliography
```

**Search log is now complete on disk.** If context compaction has occurred, re-read `$SEARCH_LOG` to recover all query results before proceeding to synthesis.

---

## PHASE 2: SYNTHESIS — WHAT WE KNOW AND DON'T KNOW

### Step 4: Build the Literature Map

Organize all papers found in Steps 0–3 into six analytical bins. This map is the intellectual backbone of everything that follows.

#### 4a. Established Findings
Claims that are replicated, cross-context, and rarely challenged. State with confidence.
- List 3–8 well-established findings as bullet points
- For each: 2–4 supporting citations + the dominant dataset/method used

#### 4b. Contested Findings
Claims where the evidence is split, context-dependent, or methods-dependent.
- For each: state the finding, the challenge, and the condition under which each holds
- These are productive tension points — a paper that resolves a contested finding has high value

#### 4c. Null / Absent Findings
Questions that have been asked but returned null results — or questions that *should* have been asked but haven't been.
- Distinguish: **null result** (asked, answered negatively) vs. **absent** (never studied)
- Absent findings are stronger publication opportunities than null results

#### 4d. Mechanisms Proposed
What explanations has the literature offered for why X relates to Y?
- List the main mechanisms: 3–6 candidates
- Note: which mechanisms have been *directly tested* vs. merely *assumed*?
- Untested mechanisms are opportunities

#### 4e. Methodological Landscape
- Dominant design (cross-sectional, panel, quasi-experimental, experimental, qualitative)
- Dominant data sources
- Key identification limitations in existing work
- New data or methods not yet applied to this question

#### 4f. The Explanatory Gap — Core Output of Phase 2

Write a **precise gap statement** — one of the four gap types:

| Gap type | Description | Opening phrase |
|----------|-------------|----------------|
| **Population gap** | Established finding hasn't been tested in this group/context | "Prior work has focused on… but no study has examined…" |
| **Mechanism gap** | The X→Y association is established but the pathway is untested | "While [finding] is well-established, the mechanism remains unspecified…" |
| **Identification gap** | Prior designs cannot establish causality | "Existing studies rely on cross-sectional data; no causal evidence exists…" |
| **Theoretical gap** | Competing theories make divergent predictions that haven't been adjudicated | "Theories A and B make conflicting predictions about… No study has tested this directly." |

The gap statement should:
- Name the closest prior work (the paper you are building on)
- State exactly what that work leaves open
- Explain why filling the gap matters theoretically

---

## PHASE 3: FRAMEWORK SELECTION AND MECHANISM

### Step 5: Map Available Theoretical Frameworks

Given the gap identified in Step 4f, survey which theoretical frameworks can generate predictions about it.

Use [references/theory-frameworks.md](references/theory-frameworks.md) as the primary catalog. For each candidate framework, assess:

| Framework | Core prediction for this gap | Fit: H or M or L | Why it fits or doesn't |
|-----------|------------------------------|-----------------|----------------------|
| [Name] | [What it predicts about X→Y] | H/M/L | [Mechanism match, scope match] |

**Include at minimum:**
- The 1–2 frameworks most commonly applied in this subfield (establish baseline)
- 1 framework from a different theoretical tradition (structural vs. cultural; macro vs. micro; Western vs. non-Western if appropriate)
- Explicitly note if the standard framework is **insufficient** — this is often the theoretical contribution

Consult [references/gap-to-hypothesis.md](references/gap-to-hypothesis.md) for guidance on matching gap types to framework types.

---

### Step 6: Select Framework(s) and Build the Argument

Choose **one primary framework** (and at most one secondary). Justify the choice:

1. **Why this framework fits the gap**: Name the gap type (Step 4f) and show the framework directly addresses it
2. **Why competing frameworks are insufficient**: Name 1–2 rivals and explain their limitations for *this specific question* (not in general)
3. **Extension or application**: Is this a straight application, a boundary condition test, or a genuine theoretical extension?

**Framework argument template:**
> "We draw on [Theory X] (Author Year) to explain [outcome Y]. [Theory X] argues that [core claim], predicting that [mechanism M] connects [X] to [Y]. Prior applications of [Theory X] have focused on [prior scope]; we extend this argument to [new population/context/mechanism] because [substantive reason]."

If existing frameworks are inadequate, build a **synthetic argument**:
> "Neither [Theory A] nor [Theory B] fully accounts for [gap], because [Theory A] assumes [X] and [Theory B] assumes [Y]. We propose that [new mechanism or integration] is needed to explain [outcome], combining [element from A] with [element from B] under [scope condition]."

---

### Step 7: Specify the Mechanism

Make the causal chain explicit and testable.

**Mechanism statement format:**
> "[X] leads to [Y] because [Mechanism M], operating through [Process P], under [Scope Condition C]."

**Mechanism diagram (text flowchart):**
```
[X: cause] → [M: mechanism/mediator] → [Y: outcome]
                    ↑
             [Z: moderator / scope condition]
```

**Mechanism types** — specify which applies:
- **Resource/material**: Access to money, time, infrastructure, information
- **Network/relational**: Exposure, diffusion, brokerage, closure, avoidance
- **Institutional/administrative**: Rules, gatekeeping, bureaucratic burden, legal status
- **Cultural/cognitive**: Meanings, norms, stigma, schemas, legitimacy
- **Psychological**: Stress, identity threat, efficacy, internalization
- **Spatial**: Distance, segregation, place-based constraint, environmental exposure

**Scope conditions** (who, where, when the mechanism should hold):
- Population: Which groups experience the mechanism most strongly?
- Context: Under what institutional/historical/geographic conditions?
- Threshold: Is there a dose-response or non-linearity?

---

## PHASE 4: HYPOTHESIS DERIVATION

### Step 8: Derive Hypotheses

Write 2–4 hypotheses directly from the mechanism in Step 7. Hypotheses must be:
- **Derived**: Stated as following from the named theory and mechanism — not atheoretically
- **Directional**: Predict positive, negative, or curvilinear direction, not just "X is related to Y"
- **Falsifiable**: Specifiable in terms of observable variables
- **Novel**: If the prediction is already well-established, frame as extension or scope condition
- **Traceable**: Every hypothesis must connect back through the full chain: literature gap (Step 4f) → framework (Step 6) → mechanism (Step 7) → prediction

**Derivation Chain Table (MANDATORY — complete before writing any hypothesis):**

| H# | Literature gap (from Step 4f) | Gap type | Framework prediction (from Step 6) | Mechanism link (from Step 7) | Hypothesis |
|----|------------------------------|----------|-----------------------------------|------------------------------|------------|
| H1 | "[Finding X] is established but [what's missing]" (Author Year) | Population / Mechanism / Identification / Debate | "[Framework] predicts [direction] because [core claim that addresses the gap]" | "[Specific step in X→M→Y chain]: [which part of the mechanism generates this prediction]" | "H1: [formal statement]" |
| H2 | "[Mechanism M] proposed but untested" (Author Year) | Mechanism | "[Framework] predicts M mediates X→Y because [logic]" | "[M is the mediating process identified in Step 7]" | "H2: [formal mediation statement]" |

**Derivation chain rule**: If you cannot fill every column, the hypothesis is not grounded in the literature-to-theory pipeline. Either (a) trace it back through a specific gap→framework→mechanism path, or (b) drop it.

**Common failures this table prevents:**
- **Generic theory application**: The "Framework prediction" column forces you to state which *specific claim* of the framework addresses *this specific gap* — not just that the framework "predicts" the direction
- **Floating mechanism**: The "Mechanism link" column forces each H to point to a specific step in the X→M→Y chain from Step 7
- **Literature-theory disconnect**: The "Literature gap" column forces each H to trace back to what the lit review found is actually missing

**Hypothesis formats:**

*Main effect (from mechanism):*
> H1: [X] is [positively/negatively] associated with [Y] among [population], because [mechanism M from Step 7].

*Mediation (mechanism test):*
> H2: The association between [X] and [Y] is partially explained by [Mediator M from Step 7], consistent with a [mechanism name] account.

*Moderation/heterogeneity (scope condition):*
> H3: The [positive/negative] effect of [X] on [Y] is stronger among [Group A] than [Group B], because [scope condition from Step 7].

*Competing prediction (adjudicating between frameworks):*
> H4 (Theory A predicts): [Direction 1]. H4' (Theory B predicts): [Direction 2]. Our design allows us to distinguish these.

**Hypothesis table:**

| # | Statement | Direction | Gap addressed | Theoretical basis | Mechanism link |
|---|-----------|-----------|---------------|-------------------|----------------|
| H1 | | + / − / ∪ | [Which gap from 4f] | [Theory, Author Year] | [Which step in X→M→Y from Step 7] |
| H2 | | + / − | [Which gap from 4f] | [Theory, Author Year] | [Mediation/moderation from Step 7] |

---

### Step 9: State Alternative Explanations

For each hypothesis, name the main competing prediction and explain how the design or data distinguishes them:

| Hypothesis | Our prediction | Alternative prediction | How design distinguishes |
|------------|---------------|----------------------|--------------------------|
| H1 | [Our direction, Theory A] | [Rival direction, Theory B] | [Control variable / exogenous variation / subsample test] |

State 1–2 robustness checks that will address the most likely confounds.

---

## PHASE 5: WRITE AND SAVE

### Step 9b: Integration Verification Check

Before saving, verify **every item**. This is the critical gate that prevents the literature-theory-hypothesis mismatch:

**Gap-to-Framework traceability:**
- [ ] Gap identified in literature (Step 4f) directly motivates framework selection (Step 6) — the framework was chosen *because* it addresses *this specific gap*, not generically applied
- [ ] The framework selection paragraph in Step 6 explicitly names the gap and explains why this framework (and not rivals) addresses it
- [ ] If the framework is commonly used in this field, the paper explains what is *new* about applying it here (not just "we use [Theory]")

**Framework-to-Hypothesis traceability:**
- [ ] **Derivation chain table** (Step 8) is complete — every H has all columns filled (literature gap, gap type, framework prediction, mechanism link, hypothesis)
- [ ] Every hypothesis traces back to a *specific* mechanism step in Step 7 — not just "consistent with [Framework]" but "because [specific process/link in the X→M→Y chain]"
- [ ] No hypothesis is derivable from common sense alone without the named framework (test: would someone unfamiliar with the framework still predict this? If yes, the derivation is too weak)
- [ ] Each hypothesis in the **prose draft** includes an explicit derivation sentence ("Because [mechanism step from Step 7], we expect [direction]...") immediately before the formal H statement

**Integration coherence:**
- [ ] Literature review and theory section form a continuous argument — the last paragraph of the lit review (the gap) leads directly into the first paragraph of the theory (the framework that addresses it)
- [ ] No "topic sentence pivot" where the theory section abruptly switches to a different concern than what the literature identified as missing
- [ ] All citations in theory section appeared in search log (no fabricated references)
- [ ] Competing predictions (Step 9) derive from frameworks identified in the theoretical landscape (Step 5), not introduced for the first time

**Common failures to check for:**
1. **Kitchen sink**: Multiple frameworks listed with equal weight, hypotheses drawn from different theories without integration → Fix: select 1 primary + 1 secondary at most
2. **Generic application**: "We use [Theory X] to predict [obvious direction]" → Fix: explain why Theory X's *specific mechanism* generates this prediction for *this specific gap*
3. **Floating H**: A hypothesis that sounds reasonable but doesn't trace back to any mechanism step → Fix: either derive it from a mechanism step or drop it

If any check fails, revise the relevant section before proceeding.

---

### Step 9c: Determine Hypothesis Placement Mode

Before writing, determine whether hypotheses should be **blended** into thematic subsections or appear as a **separate block** at the end. This is determined by journal norms:

| Target journal | Default mode | Rationale |
|---------------|-------------|-----------|
| **ASR / AJS / Social Forces** | **BLENDED** | Thematic subsections where each argument thread concludes with its derived hypothesis. Standard for papers with 3+ hypotheses. |
| **Demography** | **SEPARATE** (BLENDED if 3+ H) | Concise conceptual frameworks suit a dedicated hypothesis block. Switch to BLENDED with 3+ hypotheses for readability. |
| **NHB / Science Advances** | **SEPARATE (predictions)** | No numbered hypotheses. Predictions stated as natural-language sentences in the Introduction. |
| **NCS** | **SEPARATE (predictions)** | Brief prediction statements inline. No formal H labels. |
| **Language in Society / J. Sociolinguistics / Applied Linguistics / Language** | **INTEGRATED-RQ** | No formal numbered hypotheses. Expectations and theoretical reasoning are woven into thematic literature subsections. Section ends with a "The Present Study" subsection that reiterates research questions and previews the analytic approach. Common in sociolinguistic, discourse-analytic, and language variation studies. |
| **Qualitative / ethnographic** | **N/A** | Propositional claims, not numbered hypotheses. |

Record placement mode: `HYPOTHESIS_PLACEMENT: [BLENDED / SEPARATE / SEPARATE-PREDICTIONS / INTEGRATED-RQ / N/A]`

---

### Step 10: Write the Integrated Literature Review and Theory Section

Produce a single, publication-ready combined section. **Do not write two separate sections** — the literature review and theory should read as one coherent argument.

**Select the organizing structure** based on (1) gap type and (2) hypothesis placement mode from Step 9c.

---

#### BLENDED structures (ASR / AJS / Social Forces; Demography with 3+ H)

Each thematic subsection weaves literature, theory, and its derived hypothesis together. Subsection headings should be **substantive** (e.g., "Network Mechanisms and Occupational Sorting"), not procedural (e.g., "Hypothesis 1").

*BLENDED — for mechanism gap or population gap:*
```
¶1    Opening hook: empirical puzzle or unresolved societal question

### [Thematic Subsection 1: e.g., "Structural Barriers and Resource Access"]
¶2–3  What the literature has established on this dimension (key citations)
¶4    Theoretical framework: mechanism M1, why it fits the gap
¶5    → H1 (derived from this subsection's argument)

### [Thematic Subsection 2: e.g., "Group Heterogeneity in Mechanism Exposure"]
¶6–7  Literature on heterogeneity / moderation / scope conditions
¶8    Theoretical argument for why the mechanism differs across groups
¶9    → H2 (derived from this subsection's argument)

### [Additional subsections as needed, each ending with its hypothesis]

### Alternative Explanations
¶N    Address main alternative explanations
¶N+1  Closing preview of analytic strategy
```

*BLENDED — for theoretical debate gap:*
```
¶1    The debate: Theory A vs. Theory B

### [Theory A: e.g., "Social Capital and Information Advantages"]
¶2–3  Evidence for Theory A (with citations)
¶4    Theory A's mechanism and prediction
¶5    → H1 (Theory A's prediction)

### [Theory B: e.g., "Institutional Gatekeeping and Credential Devaluation"]
¶6–7  Evidence for Theory B, and the contradiction with A
¶8    Theory B's mechanism and prediction
¶9    → H2 (Theory B's prediction — stated as competing)

### Adjudication
¶10   Why prior work has not resolved the debate; how this study distinguishes
¶11   Alternatives and design response
```

---

#### SEPARATE structures (Demography with 1–2 H; fallback for ASR/AJS)

All hypotheses appear together after the full theoretical argument is developed.

*SEPARATE — for mechanism gap or population gap (most common):*
```
¶1    Opening hook: empirical puzzle or unresolved societal question
¶2–3  What the literature has established (established findings, key citations)
¶4    What remains unresolved — the gap (cite closest prior work; name what it leaves open)
¶5–6  Theoretical framework: core claim, mechanism, why it fits this gap
¶7    Derive H1 (main effect)
¶8    Scope conditions / moderation → derive H2 (if applicable)
¶9    Address main alternative explanation
¶10   Closing preview of analytic strategy
```

*SEPARATE — for theoretical debate gap:*
```
¶1    The debate: Theory A vs. Theory B
¶2–3  Evidence for Theory A (with citations)
¶4–5  Evidence for Theory B, and the contradiction with A
¶6    Why the debate is unresolved (population, design, or mechanism not tested)
¶7–8  Our argument: which theory applies here, why, and under what conditions
¶9    H1 (and H2 if adjudicating)
¶10   Alternatives and design response
```

*SEPARATE — for identification gap:*
```
¶1–3  What prior work finds (pattern is established)
¶4    Why causal inference remains uncertain (design limitations)
¶5    Our identification strategy and why it addresses this
¶6–7  Theoretical mechanism: why we expect X → Y causally
¶8    H1 (stated in causal language, bounded by design)
¶9    Alternatives ruled out by design
```

---

#### SEPARATE-PREDICTIONS structures (NHB / Science Advances / NCS)

No numbered hypotheses. Predictions embedded as natural-language sentences in the Introduction.

```
¶1    Opening hook: broad significance
¶2    State of knowledge (established findings)
¶3    Knowledge gap
¶4    Theoretical mechanisms and predictions (no H1/H2 labels):
      "We predicted that [X] would be positively associated with [Y]..."
      "We tested whether [mechanism M] accounts for the [X–Y] relationship..."
¶5    Brief analytic preview
```

#### INTEGRATED-RQ structures (Language in Society / J. Sociolinguistics / Applied Linguistics / Language)

No formal numbered hypotheses. Theoretical expectations and reasoning are woven into the literature discussion. Each thematic subsection builds an argument that leads readers to expect certain patterns, without stating formal H1/H2 labels. The section concludes with a **"The Present Study"** subsection that reiterates the research questions, summarizes expectations drawn from the preceding review, and previews the analytic approach.

*INTEGRATED-RQ — for sociolinguistic variation or language contact:*
```
¶1    Opening hook: sociolinguistic puzzle, language change phenomenon, or understudied variety/context

### [Thematic Subsection 1: e.g., "Style-Shifting and Social Meaning"]
¶2–3  Prior findings on this dimension (key citations, established patterns)
¶4    Theoretical reasoning: why we might expect [pattern X] in the present context
      (woven into the narrative — e.g., "These findings suggest that speakers in [context] would similarly...")

### [Thematic Subsection 2: e.g., "Indexicality and Regional Identity"]
¶5–6  Prior findings on this dimension (contradictions, scope conditions)
¶7    Theoretical reasoning for why this dimension interacts with the first
      (expectations stated as natural-language reasoning, not formal H labels)

### [Additional subsections as needed]

### The Present Study
¶N    Brief restatement of the gap: what prior work has not examined
¶N+1  Research questions restated (RQ1, RQ2 — using explicit RQ labels is conventional)
¶N+2  Summary of expectations drawn from the preceding review: "Based on [framework/prior work], we expect..."
¶N+3  Brief preview of analytic approach and data (community, corpus, or experimental design)
```

*INTEGRATED-RQ — for language attitudes or experimental sociolinguistics:*
```
¶1    Opening hook: the social evaluation puzzle, perceptual finding, or language ideology

### [Thematic Subsection 1: e.g., "Language Attitudes and Social Categorization"]
¶2–3  Prior experimental/perceptual findings (matched guise, implicit measures, etc.)
¶4    What these findings lead us to expect in the present study context

### [Thematic Subsection 2: e.g., "Intersections of Race, Gender, and Linguistic Features"]
¶5–6  Prior work on intersectional effects in language evaluation
¶7    Theoretical reasoning for expected interactions in the current design

### The Present Study
¶N    Gap restatement: what has not been tested
¶N+1  Research questions (RQ1, RQ2, RQ3)
¶N+2  Expected patterns: "Drawing on [prior work], we anticipate that..." (for each RQ)
¶N+3  Brief preview of experimental design / analytic strategy
```

*INTEGRATED-RQ — for discourse analysis or language and social structure:*
```
¶1    Opening hook: discourse phenomenon, ideological puzzle, or institutional language practice

### [Thematic Subsection 1: e.g., "Language Ideologies and Institutional Gatekeeping"]
¶2–4  Prior discourse-analytic and sociolinguistic work on this theme
¶5    What patterns we expect to observe in the present data

### [Thematic Subsection 2: e.g., "Metapragmatic Commentary and Social Positioning"]
¶6–7  Prior work on metalinguistic awareness, footing, or stance
¶8    How this framework leads us to expect certain discourse practices

### The Present Study
¶N    Gap and contribution: what this study adds
¶N+1  Research questions (RQ1, RQ2)
¶N+2  Summary of expected discourse patterns (qualitative expectations, not directional hypotheses)
¶N+3  Brief description of data and analytic framework (e.g., interactional sociolinguistics, CDA)
```

**Style standards by journal:**
- ASR/AJS: Dense theoretical framing; cite foundational works; name mechanisms explicitly; 2,000–3,500 words
- Demography: Concise but rigorous; less theory-for-theory's sake; favor life-course and demographic mechanisms; 1,500–2,500 words
- Nature journals / Science Advances: Accessible framing; broad significance in paragraph 1; lean theory section; 800–1,500 words
- Language in Society / J. Sociolinguistics: Thematic subsections with theoretical reasoning woven into literature; "The Present Study" closing subsection; expectations stated in natural language, not formal H labels; 2,000–3,500 words
- No bullet lists in the draft prose — synthesize into paragraphs

Use [references/synthesis-guide.md](references/synthesis-guide.md) for transition phrases, argumentative structures, and citation conventions.

---

### Step 11: Save Output to File

After Step 10 is complete, write the entire output to a Markdown file using the Write tool. **This is a required step, not optional.**

#### Version collision avoidance (MANDATORY — run BEFORE every Write tool call)

Run this Bash block before each Write call. It prints `SAVE_PATH=...` — use that exact path in the Write tool's `file_path` parameter.

```bash
# MANDATORY: Replace [values] with actuals before running
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
BASE="${OUTPUT_ROOT}/scholar-lrh-[topic-slug]-[YYYY-MM-DD]"

if [ -f "${BASE}.md" ]; then
  V=2
  while [ -f "${BASE}-v${V}.md" ]; do
    V=$((V + 1))
  done
  BASE="${BASE}-v${V}"
fi

echo "SAVE_PATH=${BASE}.md"
echo "BASE=${BASE}"
```

**Use the printed `SAVE_PATH` as the `file_path` in the Write tool call.** Do NOT hardcode the path. The same `BASE` must be used for pandoc conversions (.docx, .tex, .pdf).

**Filename convention:**
`scholar-lrh-[topic-slug]-[YYYY-MM-DD].md`

- `[topic-slug]`: first 4–6 significant words of the topic, lowercased, hyphenated (e.g., `redlining-activity-space-segregation`)
- `[YYYY-MM-DD]`: today's date
- Save to the current working directory

**Write the file with this exact structure — every section at full length, no placeholders:**

```markdown
# Literature Review and Theory: [original topic as stated by user]
*Generated by /scholar-lit-review-hypothesis on [YYYY-MM-DD]*
*Target journal: [journal if specified, else "unspecified"]*

---

## Quick Access
- [Search Summary](#search-summary)
- [Literature Map](#literature-map)
- [Theoretical Framework](#theoretical-framework)
- [Hypotheses](#hypotheses)
- [Alternative Explanations](#alternative-explanations)
- [**DRAFT: Literature Review and Theory Section**](#draft-literature-review-and-theory-section) ← primary deliverable
- [Working Bibliography](#working-bibliography)

---

## Search Summary
*Copy the full search log from `output/[slug]/logs/scholar-search-log-[slug]-[date].md` here.*
*If context was compacted, re-read that file to recover all query results.*

- Local library queries run and number of hits per query
- Web searches run (list each query string and hit count)
- Annual Reviews article(s) consulted and key papers extracted from them
- Total papers reviewed; number carried forward into the literature map
- **Search log file:** `output/[slug]/logs/scholar-search-log-[slug]-[date].md`

---

## Literature Map

### Established Findings
*Write full bullet list with citations — not a placeholder.*

### Contested Findings
*Write full description of each contested claim, rival evidence, and conditions.*

### Null / Absent Findings
*Write what has been asked but returned null, and what has never been asked.*

### Mechanisms Proposed
*List all mechanisms from the literature with notes on which have been directly tested.*

### Methodological Landscape
*Dominant designs, datasets, and identification limitations in the existing literature.*

### The Explanatory Gap
*Write the full gap statement: name the closest prior paper, state exactly what it leaves open, explain the theoretical stakes. Minimum 3–5 sentences.*

---

## Theoretical Framework

### Framework Evaluation Table
*Write the full comparison table (Framework | Core prediction | Fit H/M/L | Why).*

### Selected Framework and Argument
*Write the full framework argument (3–5 sentences minimum): why this framework addresses the identified gap, how it generates predictions, why rivals are insufficient.*

### Mechanism Diagram and Statement
*Write the full mechanism statement (X → M → Y [under C]) and text diagram.*

---

## Hypothesis Placement
- **Mode**: [BLENDED / SEPARATE / SEPARATE-PREDICTIONS / INTEGRATED-RQ]
- **Journal norm**: [journal → rationale]
- **Number of hypotheses/RQs**: [N]

## Hypotheses / Research Questions

*Format depends on placement mode:*

### If BLENDED / SEPARATE / SEPARATE-PREDICTIONS:

#### Derivation Chain Table

*Every hypothesis must trace through: literature gap → framework prediction → mechanism link → hypothesis.*

| H# | Literature gap (from Step 4f) | Gap type | Framework prediction (from Step 6) | Mechanism link (from Step 7) | Hypothesis |
|----|------------------------------|----------|-----------------------------------|------------------------------|------------|
| H1 | [gap statement] | [type] | [framework prediction] | [mechanism step] | [H1 formal statement] |
| H2 | [gap statement] | [type] | [framework prediction] | [mechanism step] | [H2 formal statement] |

#### Hypothesis Summary

*Write each hypothesis in full with theoretical derivation sentence.*

| # | Statement | Direction | Gap addressed | Theoretical basis | Mechanism link |
|---|-----------|-----------|---------------|-------------------|----------------|
| H1 | [full statement] | [+/−] | [which gap] | [Theory, Author Year] | [which mechanism step] |
| H2 | [full statement] | [+/−] | [which gap] | [Theory, Author Year] | [mediation/moderation from Step 7] |

### If INTEGRATED-RQ (sociolinguistic pattern):

#### Research Questions

| RQ# | Question | Literature basis | Expected pattern | Theoretical reasoning |
|-----|----------|-----------------|------------------|----------------------|
| RQ1 | [full question] | [key citations that motivate this question] | [what prior work leads us to expect] | [which framework/finding generates this expectation] |
| RQ2 | [full question] | [key citations] | [expected pattern] | [theoretical reasoning] |

#### "The Present Study" Preview

*Summarize: (1) what the review established, (2) what remains unexamined, (3) the RQs this study addresses, (4) expected patterns and why, (5) brief analytic preview. This becomes the closing subsection of the draft.*

---

## Alternative Explanations

*Write the full alternatives table (Hypothesis | Our prediction | Alternative | How design distinguishes).*
*Write 1–2 robustness check descriptions.*

---

## Draft: Literature Review and Theory Section

> **This is the primary deliverable.** Write the full publication-ready prose here — not an outline, not a summary. Apply the journal-appropriate structure from Step 10 and the word-count norms for the target journal. All paragraphs fully written, all citations in author-date format, no bullet lists in the prose body.

[Full draft begins here — minimum 1,500 words for sociology journals, 800 words for Nature-family journals]

---

## Working Bibliography

*List every cited work in ASA format, alphabetically by first author's last name.*

Example format:
> Author, First. Year. "Title of Article." *Journal Name* Volume(Issue):pages.
> Author, First and Second Author. Year. *Book Title*. City: Publisher.
```

**Close Process Log:**

Run the following to finalize the process log:

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
SKILL_NAME="scholar-lit-review-hypothesis"
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

After the Write tool completes, output this confirmation line:
> Output saved to `scholar-lrh-[slug]-[date].md`

---

## Reference Loading

Load these reference files as needed — do not load all at once:

- **[references/search-strategies.md](references/search-strategies.md)** — discipline-specific journals, Boolean search construction, citation mapping
- **[references/synthesis-guide.md](references/synthesis-guide.md)** — argumentative structures, transition phrases, gap identification checklist, citation conventions
- **[references/theory-frameworks.md](references/theory-frameworks.md)** — full catalog of sociological theories (stratification, networks, culture, immigration, life course, intersectionality, non-Western frameworks)
- **[references/gap-to-hypothesis.md](references/gap-to-hypothesis.md)** — bridge guide: matching gap types to framework types; mechanism specification templates; hypothesis derivation rules; common failure modes

Load the relevant domain section of theory-frameworks.md, not the whole file, unless the topic spans multiple theoretical traditions.

---

## Output Format

Return sections in this order:
1. `SEARCH SUMMARY` — Local library hits, searches run, Annual Reviews used, total papers reviewed (copied from the incremental search log on disk)
2. `LITERATURE MAP` — six bins (4a–4f), with gap statement clearly labeled
3. `THEORETICAL FRAMEWORK` — framework selection table, selected framework argument, mechanism diagram
4. `HYPOTHESES` — numbered hypothesis table + full H statements with theoretical derivation
5. `ALTERNATIVE EXPLANATIONS` — table of rivals + design responses
6. `DRAFT: LITERATURE REVIEW AND THEORY SECTION` — publication-ready prose, journal-appropriate length
7. `WORKING BIBLIOGRAPHY` — all cited works in ASA format
8. *(file saves — required)* — Two files:
   - `output/[slug]/logs/scholar-search-log-[slug]-[date].md` (already saved incrementally during Phase 1)
   - `scholar-lrh-[slug]-[date].md` (Write the complete file via the Write tool)
   - Confirm: `Output saved to scholar-lrh-[slug]-[date].md` and `Search log at output/[slug]/logs/scholar-search-log-[slug]-[date].md`

---

## Quality Rules

Before finalizing, verify:
- [ ] Incremental search log exists on disk at `output/[slug]/logs/scholar-search-log-[slug]-[date].md` with one row per search operation
- [ ] Search log contains hit counts for every local library query and every WebSearch query (not just "searched library" — actual numbers)
- [ ] Local reference library was searched first; foundational papers in library are cited
- [ ] At least one Annual Reviews article was consulted
- [ ] The gap statement (4f) names a specific prior paper and states precisely what it leaves open — not "this topic is understudied"
- [ ] The selected framework was chosen because it addresses the specific gap, not generically applied
- [ ] **Derivation chain table** is complete — every H has all columns filled (literature gap, gap type, framework prediction, mechanism link)
- [ ] Every hypothesis is traced to a named theory + specific mechanism step — not just "consistent with [Theory]" but "because [specific mechanism link]"
- [ ] No hypothesis is derivable from common sense alone without the named framework
- [ ] Each hypothesis in the prose includes a derivation sentence before the formal H statement
- [ ] Alternative explanations are named and the design response is specified
- [ ] The draft prose is an integrated argument — lit review flows into theory flows into hypotheses with no "topic pivot" between sections
- [ ] No "laundry list" paragraphs — all citations are synthesized into claims
- [ ] Word count of the draft prose matches the target journal's norms
- [ ] **Hypothesis placement** matches journal norms (Step 9c): BLENDED for ASR/AJS/Social Forces; SEPARATE for Demography (BLENDED if 3+ H); SEPARATE-PREDICTIONS for NHB/NCS/SciAdv; INTEGRATED-RQ for Language in Society/J. Sociolinguistics/Applied Linguistics/Language
- [ ] **If BLENDED**: thematic subsection headings are substantive (not "Hypothesis 1"); each subsection weaves literature + theory + derived H
- [ ] **If SEPARATE**: hypotheses appear as a block after the full theoretical argument
- [ ] **If INTEGRATED-RQ**: no formal H1/H2 labels; theoretical expectations woven into thematic subsections as natural-language reasoning; section ends with a "The Present Study" subsection containing restated RQs, summarized expectations, and analytic preview
- [ ] The draft section is full prose — no bullet lists, no placeholders, no outlines
- [ ] Working bibliography is complete and in ASA format
- [ ] Output is saved to a `.md` file via the Write tool — the skill is not complete until the file exists
