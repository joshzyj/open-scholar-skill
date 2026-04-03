# Writing Protocol — Pre-Writing Setup (Step 0)

This file is loaded on demand by `scholar-write/SKILL.md`. It contains Step 0: article loading, knowledge base, citation pool building, and artifact registry construction.

---

## Step 0: Load Example Articles and Knowledge Base (Always Do First)

Before drafting or revising any section, use the pre-built knowledge base to calibrate voice, structure, and rhetorical moves — no per-session pdftotext calls required.

**Set output root** (respects orchestrator override; defaults to `output` when standalone):
```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
```

**Assets location**:
```bash
SKILL_DIR="${SCHOLAR_SKILL_DIR:-.}/.claude/skills"
ASSETS="$SKILL_DIR/scholar-write/assets"
```

### Tier 1: Read the Article Knowledge Base (Fast — Always Do)

```bash
SKILL_DIR="${SCHOLAR_SKILL_DIR:-.}/.claude/skills"
cat "$SKILL_DIR/scholar-write/assets/article-knowledge-base.md"
```

This file contains pre-extracted structured annotations for ~127 papers (32 user1-articles + 8 user2-articles + 87 top-journal exemplars). For each fully-annotated paper it provides:
- **Opening line** (verbatim first sentence of the introduction)
- **Gap sentence** (verbatim gap statement)
- **Contribution claim** (verbatim contribution statement)
- **Theory/mechanism** (1-sentence synthesis)
- **Voice register** (formal-dense | accessible-broad | technical-interdisciplinary | etc.)
- **Citation density** and **paragraph length** norms
- **Best for** guidance

**Select from the knowledge base**:
- Choose **1–2 user1-articles** whose domain/method most closely matches → defines the author's voice
- Choose **1–2 user2-articles** if the paper involves applied linguistics, sociolinguistics, language ideology, study abroad, heritage language, intercultural communication, conversation analysis, or discourse analysis → defines discipline-specific voice and framing
- Choose **1–2 top-journal articles** that match the target journal → defines required structural depth and citation density

### Tier 2: Read the Section Snippets Library (Fast — Do for Targeted Sections)

```bash
cat "$SKILL_DIR/scholar-write/assets/section-snippets.md"
```

This file contains **verbatim quotes organized by rhetorical function** across 9 categories:
1. Opening Hooks (puzzle/paradox, empirical anomaly, urgency, broad claim)
2. Research Problem / Gap Statements
3. Contribution Claims ("Here, we..." / "In this article, we argue..." / systematic analysis claims)
4. Theory & Mechanism Descriptions
5. Methods Section Lead Sentences
6. Results Lead Sentences
7. Discussion / Implications Opening
8. Hedging & Scope Conditions
9. High-Impact Quantitative Sentences

Use snippets as **structural templates** — the sentence architecture, not the content — to build each section move by move.

### Tier 3: Deep Read of Specific PDFs (Optional — Only When Needed)

If a specific paper's full text is needed beyond what the knowledge base provides:

```bash
ASSETS="$SKILL_DIR/scholar-write/assets"

# Read a user1-article (first 300 lines = abstract + intro + early theory + methods)
pdftotext "$ASSETS/user1-articles/[FILENAME].pdf" - | head -300

# Read a user2-article (applied linguistics, sociolinguistics, study abroad, discourse analysis)
pdftotext "$ASSETS/user2-articles/[FILENAME].pdf" - | head -300

# Read a top-journal article
pdftotext "$ASSETS/top-journal-articles/[FILENAME].pdf" - | head -300
```

### Apply to Draft

After loading the knowledge base:
- **Voice**: Mirror the opening hook structure and sentence rhythm from the closest user1-article or user2-article entry
- **Structure**: Match the theoretical depth, paragraph length, and citation density from the target-journal example
- **Rhetorical moves**: Use section-snippets.md to select the right move architecture for each paragraph type
- **Contribution language**: Copy the grammatical pattern from the matching contribution claim in Tier 2 (e.g., "Here, we..." for Nature/PNAS; "In this article, we argue..." for ASR/Demography)

#### Retrieve Citations from Local Reference Library (MANDATORY — Run Before Drafting)

### Tier 0: Query Knowledge Graph for Topic Findings (Fast — Always Try)

Before building the Verified Citation Pool from Zotero, check the knowledge graph for pre-extracted findings and theoretical framings on this section's topic.

```bash
SKILL_DIR="${SCHOLAR_SKILL_DIR:-.}/.claude/skills"
KG_REF="$SKILL_DIR/scholar-knowledge/references/knowledge-graph-search.md"
if [ -f "$KG_REF" ]; then
  eval "$(cat "$KG_REF" | sed -n '/^```bash/,/^```/p' | sed '1d;$d')" 2>/dev/null
  if kg_available; then
    echo "=== Knowledge Graph: findings for [SECTION TOPIC] ==="
    kg_search_papers "[SECTION TOPIC]" 15 | kg_format_papers
    echo ""
    echo "=== Knowledge Graph: theories ==="
    kg_search_concepts "[SECTION TOPIC]" 10 theory
    echo ""
    echo "[KG] $(kg_count)"
  else
    echo "[KG] Knowledge graph empty — proceeding to Zotero"
  fi
else
  echo "[KG] scholar-knowledge not installed — proceeding to Zotero"
fi
```

Use KG results to:
- Pre-populate the Verified Citation Pool with papers whose findings are relevant
- Identify which theories/mechanisms to foreground in the section
- Find contradiction pairs that strengthen the "gap" argument
- **Do NOT use KG findings as direct prose** — use them to guide which Zotero PDFs to read for verbatim quotes

### Tier 0b: Build Verified Citation Pool from Local Reference Library

Query the user's local reference library to find stored papers for use as citations. The search infrastructure supports multiple backends (Zotero, Mendeley, BibTeX, EndNote) and auto-detects which are available.

```bash
# Load multi-backend reference search infrastructure
# See .claude/skills/scholar-citation/references/refmanager-backends.md
# Run auto-detection to set $REF_SOURCES, $REF_PRIMARY, $ZOTERO_DB, etc.
eval "$(cat "$SKILL_DIR/scholar-citation/references/refmanager-backends.md" | sed -n '/^```bash/,/^```/p' | sed '1d;$d')"

# Search for papers by keyword (returns up to 15 results across all detected backends)
scholar_search "your_keyword" 15 keyword
```

**Run multiple searches** to build a verified citation pool before writing.

**IMPORTANT — Run as a SINGLE Bash command** (shell state doesn't persist across calls):

```bash
# Re-load reference manager (shell state lost between Bash calls)
SKILL_DIR="${SCHOLAR_SKILL_DIR:-.}/.claude/skills"
eval "$(cat "$SKILL_DIR/scholar-citation/references/refmanager-backends.md" | sed -n '/^```bash/,/^```/p' | sed '1d;$d')" 2>/dev/null

# Search by topic keywords (run 3-5 keyword searches covering the section's main claims)
scholar_search "keyword1" 15 keyword | scholar_format_citations
scholar_search "keyword2" 15 keyword | scholar_format_citations
scholar_search "keyword3" 15 keyword | scholar_format_citations

# Search by known author last names
scholar_search "AuthorLastName" 20 author | scholar_format_citations

# Search by Zotero collection or tag if applicable
scholar_search "collection_name" 20 collection
scholar_search "tag_name" 20 tag
```

To read a retrieved PDF for citation context (available for backends with PDF storage, e.g., Zotero, Mendeley):
```bash
# Use the pdf_path returned by scholar_search results
pdftotext "[PDF_PATH]" - | head -150
```

See `scholar-lit-review` Step 0 for author search, collection search, and multi-keyword queries.

#### Build Verified Citation Pool

**Before writing ANY prose**, compile a list of verified citations from the search results above. This is the **ONLY** source of citations allowed during drafting:

```
VERIFIED CITATION POOL (from Zotero/Mendeley/BibTeX/EndNote search):
1. Author(s) (Year). "Title." Journal. [source: zotero/mendeley/bibtex/endnote]
2. Author(s) (Year). "Title." Journal. [source: ...]
...
```

Also include citations carried forward from prior pipeline phases (scholar-lit-review, scholar-hypothesis, etc.) — these count as pre-verified.

**HARD RULE: During Steps 2-4 below, ONLY cite references from this Verified Citation Pool or prior-phase carry-forwards. If a claim needs a citation that is NOT in the pool, do NOT guess — use `[CITATION NEEDED: description]` instead.**

#### Build Table and Figure Artifact Registry (MANDATORY — Run Before Drafting)

Scan the output directories for tables and figures produced by prior pipeline phases (`scholar-eda`, `scholar-analyze`, `scholar-compute`). This registry drives in-text references and the end-of-manuscript Tables & Figures section.

```bash
# Inventory all existing tables
echo "=== TABLE INVENTORY ==="
for dir in "${OUTPUT_ROOT}/tables" "${OUTPUT_ROOT}/eda/tables"; do
  [ -d "$dir" ] && find "$dir" -type f \( -name "*.html" -o -name "*.tex" -o -name "*.docx" -o -name "*.csv" \) | sort
done

echo ""
echo "=== FIGURE INVENTORY ==="
for dir in "${OUTPUT_ROOT}/figures" "${OUTPUT_ROOT}/eda/figures"; do
  [ -d "$dir" ] && find "$dir" -type f \( -name "*.pdf" -o -name "*.png" \) | sort
done
```

From the inventory, build a numbered **ARTIFACT REGISTRY**. Assign sequential numbers following journal convention (Tables first, then Figures; Appendix items use A-prefix):

```
ARTIFACT REGISTRY:
Tables:
  Table 1: ${OUTPUT_ROOT}/tables/table1-descriptives.html — Descriptive Statistics
  Table 2: ${OUTPUT_ROOT}/tables/table2-regression.html — Main Regression Results
  Table 3: ${OUTPUT_ROOT}/tables/table2-ame.html — Average Marginal Effects
  Table A1: ${OUTPUT_ROOT}/tables/tableA1-robustness.html — Robustness Checks (Appendix)
  ...

Figures:
  Figure 1: ${OUTPUT_ROOT}/figures/fig-coef-plot.pdf — Coefficient Plot
  Figure 2: ${OUTPUT_ROOT}/figures/fig-ame-interaction.pdf — Marginal Effects by Group
  Figure 3: ${OUTPUT_ROOT}/figures/fig-event-study.pdf — Event Study Estimates
  Figure A1: ${OUTPUT_ROOT}/figures/fig-missing-by-var.pdf — Missing Data Patterns (Appendix)
  ...
```

**Numbering rules:**
- Tables and Figures are numbered independently (Table 1, Table 2...; Figure 1, Figure 2...)
- Main body artifacts: `Table 1`, `Figure 1` etc. — descriptive stats, main models, key figures
- Appendix artifacts: `Table A1`, `Figure A1` etc. — robustness checks, EDA diagnostics, sensitivity analyses
- Assign EDA outputs (from `output/[slug]/eda/`) to Appendix by default unless the section being drafted is EDA-focused
- If no artifacts exist in the output directories, note `ARTIFACT REGISTRY: EMPTY — no prior pipeline outputs found` and proceed; in-text references will use placeholder format `(Table [N])` / `(Figure [N])`

**The ARTIFACT REGISTRY is the single source of truth for all table/figure references in the manuscript.** Every in-text reference must correspond to an entry here.

**Save artifact registry to disk (MANDATORY):**

```bash
mkdir -p "${OUTPUT_ROOT}/manuscript"
```

Write the complete artifact registry to `${OUTPUT_ROOT}/manuscript/artifact-registry.md`:

```markdown
# Artifact Registry
<!-- Generated by scholar-write — single source of truth for table/figure numbering -->
<!-- Used by scholar-replication VERIFY mode for paper-to-code correspondence -->

## Tables
| Number | File Path | Description |
|--------|-----------|-------------|
| Table 1 | ${OUTPUT_ROOT}/tables/table1-descriptives.html | Descriptive Statistics |
| Table 2 | ${OUTPUT_ROOT}/tables/table2-regression.html | Main Regression Results |
| ... | ... | ... |

## Figures
| Number | File Path | Description |
|--------|-----------|-------------|
| Figure 1 | ${OUTPUT_ROOT}/figures/fig-coef-plot.pdf | Coefficient Plot |
| ... | ... | ... |

## Appendix
| Number | File Path | Description |
|--------|-----------|-------------|
| Table A1 | ${OUTPUT_ROOT}/tables/tableA1-robustness.html | Robustness Checks |
| Figure A1 | ${OUTPUT_ROOT}/eda/figures/fig-missing-by-var.pdf | Missing Data Patterns |
| ... | ... | ... |
```

This file will be consumed by `scholar-replication` VERIFY mode to map every in-text reference to a producing script.
