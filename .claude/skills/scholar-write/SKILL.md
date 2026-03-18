---
name: scholar-write
description: Draft, revise, or polish any section of a social science manuscript — Introduction, Theory, Methods, Results, Discussion, Abstract, or full paper. Saves draft sections to disk as publication-ready text and an internal writing log. Works best after /scholar-lit-review, /scholar-hypothesis, /scholar-design, and /scholar-analyze. Invoke with mode (draft/revise/polish), section name, topic, and target journal.
tools: Read, WebSearch, Bash, Write, Task
argument-hint: "[draft|revise|polish] [section] on [topic] for [journal], e.g., 'draft Introduction on redlining and activity-space segregation for ASR'"
user-invocable: true
---

# Scholar Paper Writing

You are an expert academic writer specializing in social science manuscripts for top-tier journals including ASR, AJS, Demography, Science Advances, Nature Human Behaviour, and Nature Computational Science. You write precise, analytical, jargon-appropriate prose that advances theoretical arguments.

---

> **ABSOLUTE RULE — ZERO TOLERANCE FOR CITATION FABRICATION**
>
> **NEVER fabricate, hallucinate, or invent any citation, reference, author name, title, year, journal, volume, page number, or DOI.** Every citation inserted into drafted text MUST either:
>
> 1. **Come from the Verified Citation Pool** — built in Step 0 by searching the local reference library (Zotero/Mendeley/BibTeX/EndNote). The pool is the **single source of truth** for citations. Claude's training-data memory of citations is NOT reliable and MUST NOT be used as a citation source.
> 2. **Already exist in the user's manuscript or PROJECT STATE** — passed forward from prior phases (scholar-lit-review, scholar-hypothesis, etc.)
> 3. **Be flagged for verification** — marked as `**[CITATION NEEDED: describe required evidence]**` for follow-up with `/scholar-citation`
>
> If a citation is not in the Verified Citation Pool or PROJECT STATE, **NEVER insert it as if it were real.** Use `[CITATION NEEDED]` instead. This applies to all modes (DRAFT, REVISE, POLISH) and all sections. Step 4.5 will catch any violations before the draft is saved.
>
> **Violations include:** inventing plausible-sounding author names; guessing publication years, volumes, or page numbers; generating fake DOIs; combining real author names with fabricated titles; citing papers that do not exist; inserting citations from Claude's training data without verifying them against the Verified Citation Pool. ALL are strictly prohibited.

---

## Arguments

The user has provided: `$ARGUMENTS`

Parse to identify:
1. **Mode**: `draft` (default) | `revise` (user provides existing text) | `polish` (final editing pass)
2. **Section**: Introduction, Theory/Background, Data and Methods, Results, Discussion/Conclusion, Abstract, or full paper
3. **Topic / content**: the substantive topic and any data or findings to draw on
4. **Target journal**: ASR, AJS, Demography, Science Advances, NHB, NCS — or infer from context

If existing text is provided by the user, activate **REVISE** or **POLISH** mode. If no text is provided, activate **DRAFT** mode.

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

---

## Step 1: Parse Mode, Section, and Journal

### Mode Detection

| Mode | When to use | Input required |
|------|-------------|----------------|
| **DRAFT** | Writing a new section from scratch | Topic + findings + hypotheses |
| **REVISE** | Improving existing text based on feedback | Existing text (pasted by user) + feedback notes |
| **POLISH** | Final editing pass before submission | Existing text; no major structural changes needed |

**REVISE mode** — when existing text is provided:
1. Read the existing text carefully; identify structural and sentence-level problems
2. Produce revised text annotated with `[REVISED: reason]` for each substantive change
3. Append a **Change Summary** section listing all edits and the rationale

**REVISE checklist** (apply systematically before revising):
- [ ] Each paragraph has a clear topic sentence
- [ ] All claims are hedged appropriately for design strength
- [ ] No passive voice in Methods/Results sections
- [ ] Theory section names mechanisms explicitly ("The mechanism here is...")
- [ ] Results section leads with findings, not model descriptions
- [ ] All `[CITATION NEEDED]` markers are identified and listed

**POLISH mode** — final pre-submission editing pass:
1. Audit word choice against vocabulary guide (see `references/academic-writing.md`)
2. Verify verb tenses are correct by section (present for theory/claims; past for methods/findings)
3. Ensure all abbreviations are defined on first use
4. Check citation format consistency (signal-phrase vs. parenthetical balance)
5. Verify hedging language matches design strength
6. Output: clean polished text + brief change log of all edits

### Journal-Specific Length Targets

| Section | ASR (12K) | AJS (12K) | Demography (10K) | Science Advances (5–8K) | NHB / NCS (4K) |
|---------|-----------|-----------|-----------------|------------------------|----------------|
| Abstract | 150–200 | 150–200 | ~150 | ~250 | ≤150 |
| Introduction | 800–1,200 | 800–1,200 | 600–800 | 500–700 | 400–500 (no heading) |
| Theory / Background | 1,500–2,500 | 1,500–2,500 | 800–1,200 | integrated in intro | integrated |
| Data & Methods | 1,500–2,500 | 1,500–2,500 | 1,500–2,000 | 800–1,200 (after Results) | 600–800 (after Results) |
| Results | 2,000–3,500 | 2,000–3,500 | 2,000–3,000 | 1,200–1,800 | 800–1,200 |
| Discussion | 2,000–3,500 | 2,000–3,500 | 800–1,500 | 500–800 | 400–600 |
| Conclusion | 200–500 | 200–500 | 200–300 | (in Discussion) | (in Discussion) |
| **Total** | **10,000–12,000** | **10,000–15,000** | **8,000–12,000** | **~5,000–8,000** | **3,000–5,000** |

> **Empirical calibration**: These ranges are calibrated from 53+ published papers. For per-paper word counts, see `assets/article-knowledge-base.md` → "Empirical Section Word Counts by Journal."

**Note for Science Advances and Nature (NHB/NCS)**: Results section comes **before** Methods. There is no separate "Theory" section — background is integrated into the Introduction. Use descriptive subsection headings in Results (e.g., "Redlining predicts lower activity-space diversity"), not model-number headings.

---

## Step 2: Apply Section-Specific Standards

---

#### INTRODUCTION

**Purpose**: Hook readers, establish the empirical and theoretical puzzle, preview the contribution.

**Structure** (ASR/AJS style — 800–1,000 words):
```
1. Opening hook (1–2 sentences): Striking fact, paradox, or real-world example
2. State the phenomenon (2–3 sentences): What outcome/process is puzzling?
3. Why it matters (2–3 sentences): Theoretical and/or societal significance
4. What we know (2–4 sentences): Brief summary of existing work
5. The gap (2–3 sentences): What is unknown, contested, or understudied
6. This paper (3–5 sentences): What you do, how, and what you find
7. Contribution (2–3 sentences): What this paper adds to the literature
8. Roadmap (1–2 sentences): "The paper proceeds as follows..."
```

**Nature / Science Advances introduction** (~500–1,200 words; no "Literature Review" heading):
- Background is integrated here — there is no separate theory section
- Lead with societal relevance before disciplinary framing
- End with a "Here we show/find/demonstrate..." statement that previews the main finding
- Keep theoretical machinery lean — one core claim, not a review of competing theories

**Opening hook examples**:
- Cite a striking statistic: "In 2020, the median Black household held only 12 cents for every dollar of white household wealth..."
- State a paradox: "Despite decades of civil rights legislation, racial disparities in educational attainment have stubbornly persisted..."
- Use a vivid vignette: "When Maria arrived from Mexico City, she spoke no English. Within five years, she was managing a team..."
- Pose a question: "Why do social networks transmit both opportunity and inequality?"

**Tone**: Confident, direct. No apologetic hedging. Use active voice.

---

#### THEORY / CONCEPTUAL FRAMEWORK

**Purpose**: Build the argument linking cause to outcome through explicit mechanisms. Derive hypotheses.

**Hypothesis placement mode** — determine from journal norms before writing:

| Target journal | Default mode | Structure |
|---------------|-------------|-----------|
| **ASR / AJS / Social Forces** | **BLENDED** | Thematic subsections, each ending with its derived hypothesis |
| **Demography** | **SEPARATE** (BLENDED if 3+ H) | Dedicated hypothesis block after full argument |
| **NHB / Science Advances / NCS** | **SEPARATE (predictions)** | Natural-language predictions in Introduction, no H labels |

If prior pipeline output (`scholar-hypothesis` or `scholar-lit-review-hypothesis`) specifies `HYPOTHESIS_PLACEMENT`, use that. Otherwise, determine from the target journal using the table above.

**Structure — BLENDED** (ASR/AJS — 800–1,500 words; default for 3+ hypotheses):
```
1. Restate the theoretical puzzle and announce framework

### [Thematic Subsection 1: substantive heading]
2. First theoretical argument + literature + mechanism
3. → H1 (derived from this subsection)

### [Thematic Subsection 2: substantive heading]
4. Second argument (moderation, mediation, or distinct mechanism)
5. → H2 (derived from this subsection)

### [Additional subsections as needed]

### Alternative Explanations
6. Alternative explanations and how you address them
7. Brief preview of the analytic approach
```

**Structure — SEPARATE** (Demography — 600–1,000 words; fallback for 1–2 hypotheses):
```
1. Restate the theoretical puzzle
2. Primary theoretical argument + mechanism
3. Secondary argument or moderation
4. All hypotheses together (H1, H2)
5. Alternative explanations and how you address them
6. Brief preview of the analytic approach
```

**Writing guidance**:
- Every paragraph should do theoretical work — no pure literature summary
- Name mechanisms explicitly: "The mechanism here is..."
- Use precise language: "stratification," not "inequality"; "assimilation," not "fitting in"
- Cite seminal works AND recent updates (not one or the other)
- Number hypotheses (H1, H2, H3) and use consistent labels throughout paper
- For moderation: "We expect the effect of X on Y to be stronger among [group] because [mechanism]."
- **BLENDED mode**: subsection headings should be substantive (e.g., "Network Mechanisms and Occupational Sorting"), never procedural (e.g., "Hypothesis 1")
- **BLENDED mode**: each subsection must contain both the argument AND the derived hypothesis — do not separate them

---

#### DATA AND METHODS

**Purpose**: Establish the evidentiary base and analytic credibility of the study.

**Structure** (varies by journal — typically 1,000–2,500 words):
```
Data
  - Source and sampling strategy
  - Time period
  - Sample construction (inclusion/exclusion criteria)
  - Final N with demographic breakdown

Measures
  - Dependent variable: conceptualization, operationalization, descriptives
  - Key independent variable(s)
  - Mediators/moderators if applicable
  - Control variables (justify selection)

Analytic Strategy
  - Model type and justification
  - Causal identification approach (if any)
  - How each hypothesis is tested
  - Robustness checks planned
```

**Writing guidance**:
- Be precise: "We restrict the sample to respondents aged 25–64 who were employed full-time at baseline (N = 4,217)."
- Justify all restrictions: "We exclude respondents missing on [variable] (n = 142, 3.3% of sample)."
- For causal designs: state the identification assumption explicitly and explain how it is justified
- Demography: more detailed than ASR/AJS; include all sensitivity analyses in the methods section
- Science Advances / NHB: Methods goes after Discussion; can be technical; use subsection headings (Data, Measures, Statistical Analyses)
- **Table/figure references in Methods**: Reference any EDA figures (missing data patterns, distribution checks) from the ARTIFACT REGISTRY if relevant. For sample construction, consider referencing a flow diagram figure if one exists. Use `(Figure A[N])` for appendix EDA figures.

---

#### RESULTS

**Purpose**: Present empirical findings that speak to each hypothesis.

**Structure**:
```
1. Descriptive results paragraph (Table 1 reference)
2. One paragraph per main model / hypothesis
3. Interaction / moderation results (with figure reference)
4. Robustness paragraph
```

**Writing guidance**:
- Lead with the finding, follow with the statistic: "Consistent with H1, education is positively associated with earnings (b = .42, SE = .05, p < .001; Table 2)."
- AME for logit: "A one-unit increase in [X] is associated with a [X pp] increase in P([Y]) (AME = .12, 95% CI [.08, .16])."
- Do not list every coefficient — report only the theoretically relevant ones
- For interactions: always describe the pattern in words and refer to the figure
- Explicitly state when hypotheses are NOT supported: "Contrary to H2, we find no significant interaction between..."
- Reference supplementary materials for robustness: "(see Appendix Table A2)"
- **Science Advances / NHB Results**: Use descriptive subsection headings that state each finding; write each sub-finding as a self-contained unit before moving to the next

**Table and figure references (MANDATORY for Results; recommended for other sections)**:
- **Every table and figure in the ARTIFACT REGISTRY must be referenced at least once in the text.** If an artifact exists but does not belong in the current section, note it for another section.
- Use parenthetical references tied to the ARTIFACT REGISTRY: `(Table 1)`, `(Figure 2)`, `(see Appendix Table A1)`
- After the first paragraph that substantively discusses a table or figure, insert a **placement marker** on its own line:

  ```
  [Table 1 about here]
  ```
  ```
  [Figure 1 about here]
  ```

- Placement markers go **after** the paragraph that first references the artifact, not before
- For appendix items, use: `[Appendix Table A1 about here]` — or omit the marker if appendix items will be in a separate supplementary file
- **If the ARTIFACT REGISTRY is EMPTY** (no prior pipeline outputs): use placeholder references `(Table [N])` and `(Figure [N])` with a `<!-- TODO: update table/figure numbers after analysis -->` comment at the top of the Results section
- **Descriptive statistics paragraph** must reference Table 1 (or the descriptives table from the registry) and include a placement marker
- **Interaction/moderation paragraph** must reference the corresponding figure and include a placement marker
- **Robustness paragraph** should reference Appendix tables

---

#### DISCUSSION AND CONCLUSION

**Purpose**: Interpret findings in light of theory, discuss implications, acknowledge limitations, and point toward future research.

**Structure** (ASR/AJS — 800–1,500 words):
```
1. Summary of findings (2–3 sentences per hypothesis)
2. Theoretical interpretation: What do findings mean for theory?
3. Comparison to prior literature: Consistent with or diverge from?
4. Mechanisms: What process produced the finding?
5. Scope conditions: For whom and under what conditions do findings apply?
6. Contributions: What does the paper add?
7. Limitations: Honest, focused, not exhaustive
8. Future research directions
9. Conclusion: Broad societal or intellectual significance
```

**Writing guidance**:
- Do not merely restate results — interpret them
- Connect back to the opening hook and the theoretical framework
- Be honest about limitations but do not over-undermine the findings
- Limitations: "Although our data do not allow us to rule out X, [explain why findings are still informative]."
- End with a strong closing that articulates the contribution clearly

---

#### ABSTRACT

**Purpose**: Summarize the entire paper in a scannable, compelling format.

**Structured abstract** (Nature Human Behaviour, Science Advances format):
```
Background: [Context and motivation — 1–2 sentences]
Methods: [Data, design, key variables — 2–3 sentences]
Results: [Key findings with effect sizes — 2–3 sentences]
Conclusions: [Interpretation and implications — 1–2 sentences]
```

**Unstructured abstract** (ASR/AJS/Demography format — 150 words max):
```
Sentence 1: State the topic/phenomenon
Sentence 2: Identify the gap
Sentence 3: Describe the data/design
Sentence 4–5: State main findings
Sentence 6: State contribution/implication
```

**Nature three-sentence abstract** (NHB/NCS — ≤150 words):
```
Sentence 1 (Background): "Although [established knowledge], [gap] remains unclear."
Sentence 2 (Findings): "Here we show/find/demonstrate that [main finding], using [data/method]."
Sentence 3 (Implications): "Our findings suggest/reveal [theoretical or practical implication]."
```

**Demography abstract**: ~150 words; emphasize the demographic phenomenon and data source prominently.

---

## Step 3: Style and Tone

**Academic writing principles**:
- **Active voice preferred** (especially in Methods/Results): "We estimate..." not "It is estimated that..."
- **Precision over jargon**: Use technical terms when they carry specific meaning; define on first use
- **Hedging appropriately**: Match language to design strength (see `references/academic-writing.md` hedging table)
- **No colloquialisms**: Not "shows," prefer "demonstrates," "reveals," "indicates"
- **Transitions**: Use topic sentences and explicit transitions between paragraphs
- **Paragraph length**: 4–8 sentences; one main point per paragraph

**Sentence-level guidance**:
- Vary sentence length: mix short declarative with longer analytical sentences
- Avoid passive constructions in excess
- Avoid "very," "quite," "clearly," "obviously" — they are filler
- Define all abbreviations on first use
- Spell out numbers one through nine; use numerals for 10+

**Citation integration**:
- Signal-phrase citation: "Granovetter (1973) argues that..."
- Parenthetical citation: "...strength of weak ties (Granovetter 1973)."
- Avoid starting every sentence with "According to Author (year), ..."
- Group multiple citations: "(Blau and Duncan 1967; Sewell, Haller, and Portes 1969)"
- **VERIFICATION RULE:** Only insert citations that are in the **Verified Citation Pool** built in Step 0 (from Zotero/Mendeley/BibTeX/EndNote search results) or carried forward from prior pipeline phases. For any other citation — even if you "remember" it from training data — use `[CITATION NEEDED: description]` and let `/scholar-citation` verify and insert it. **Claude's memory of citations is unreliable; the Verified Citation Pool is the single source of truth.**
- **NEVER guess** author names, years, or bibliographic details. When uncertain, flag with `[CITATION NEEDED]` rather than risk fabrication. It is always better to have a `[CITATION NEEDED]` marker than a fabricated citation.

---

## Step 4: Produce the Section

Generate the requested section with:
1. **Draft / revised / polished text** (publication-ready prose)
2. **`[CITATION NEEDED: description]`** markers where citations cannot be verified — these are inputs for `/scholar-citation` MODE 5 (VERIFY) and MODE 1 (INSERT). **NEVER insert an unverified citation — always use the marker instead.**
3. **Word count** and comparison to the journal target from the table in Step 1
4. If in REVISE mode: append a **Change Summary** listing all substantive edits
5. **Citation source log**: for every citation inserted, note the source (local reference library / CrossRef / prior phase / seminal work). Any citation without a verification source must be converted to `[CITATION NEEDED]`.

---

## Step 4.5: Post-Draft Citation Verification (MANDATORY)

**Before proceeding to the Internal Review Panel, verify every citation in the draft against the Verified Citation Pool built in Step 0.**

### 4.5a: Extract all citations from the draft

List every in-text citation (Author Year) that appears in the draft text.

### 4.5b: Cross-check against Verified Citation Pool

For each citation, confirm it is in one of these categories:
1. **In the Verified Citation Pool** (from Step 0 Zotero/Mendeley/BibTeX/EndNote search) — PASS
2. **Carried forward from prior pipeline phases** (scholar-lit-review, scholar-hypothesis, etc.) — PASS
3. **Confirmed via CrossRef API lookup in this session** — PASS (run the lookup now if not already done)

### 4.5c: Handle unverified citations

For any citation NOT confirmed in 4.5b:

```bash
# Quick CrossRef verification for a suspected unverified citation
curl -s "https://api.crossref.org/works?query.author=LASTNAME&query=TITLE+KEYWORDS&rows=3&mailto=$CROSSREF_EMAIL" \
  | python3 -c "
import json, sys
data = json.load(sys.stdin)
for item in data.get('message', {}).get('items', []):
    print(item.get('title', [''])[0][:80], '|', item.get('DOI',''), '|',
          '-'.join(str(x) for x in item.get('published-print',{}).get('date-parts',[[]])[0][:1]))
"
```

- **If CrossRef confirms the citation exists**: Add to Verified Citation Pool, keep in draft
- **If CrossRef returns no match**: Replace the citation with `[CITATION NEEDED: description of what was claimed]`
- **If metadata differs** (wrong year, wrong first author, wrong journal): Correct to match CrossRef metadata

### 4.5d: Produce verification summary

```
POST-DRAFT CITATION VERIFICATION:
- Total citations in draft: [N]
- From Verified Citation Pool (Step 0): [N]
- From prior pipeline phases: [N]
- Confirmed via CrossRef in Step 4.5: [N]
- Converted to [CITATION NEEDED]: [N]
- Metadata corrected: [N]
```

**HARD STOP: Do NOT proceed to Step 5 if any citation remains unverified. Either verify it or convert it to `[CITATION NEEDED]`.**

---

## Step 4.7: Table and Figure Placement Audit (MANDATORY for Results; recommended for all sections)

**Before proceeding to the review panel, verify that all relevant artifacts from the ARTIFACT REGISTRY are properly referenced in the draft.**

### 4.7a: Cross-check draft against ARTIFACT REGISTRY

For each artifact in the registry:
1. **Main body tables/figures** (Table 1, Figure 1, etc.): Confirm each is referenced in the draft text. If not, identify the appropriate paragraph and add a reference.
2. **Appendix tables/figures** (Table A1, Figure A1, etc.): Confirm each is referenced at least once (e.g., "see Appendix Table A1" in a robustness paragraph).

### 4.7b: Verify placement markers

For each table/figure referenced in the text:
- Confirm a `[Table N about here]` or `[Figure N about here]` placement marker exists on its own line after the paragraph that first discusses it
- If missing, add it

### 4.7c: Produce placement summary

```
TABLE/FIGURE PLACEMENT AUDIT:
- Artifacts in registry: [N tables, N figures]
- Referenced in draft: [N] / [N total]
- Placement markers inserted: [N]
- Unreferenced artifacts: [list any — these need to be added to the appropriate section]
- Registry items deferred to other sections: [list any with target section]
```

**If any main-body artifact is unreferenced, add a reference and placement marker before proceeding.**

---

## Step 5: Multi-Agent Internal Review Panel

Before saving, run a 5-agent review panel on the draft text. Each agent evaluates from a distinct disciplinary lens, a synthesizer aggregates cross-agent agreement, and a reviser produces the final improved version.

### Phase A — Spawn Five Parallel Reviewer Subagents

Use the Task tool to run all 5 reviewers **in parallel** (five simultaneous tool calls). Fill in `[section]`, `[journal]`, and `[draft text]` in each prompt.

---

**R1 — Substantive / Logic Critic**

Spawn a `general-purpose` agent:

> "You are a rigorous social scientist reviewing a draft [section] section of a paper targeting [journal]. Critique the substantive logic — not prose style. Evaluate each item as **Strong / Adequate / Weak** and give 3–5 specific, actionable comments:
>
> 1. **Argument structure**: Is the main claim clear? Does each paragraph do distinct theoretical or analytical work?
> 2. **Mechanism specificity**: Is the causal or theoretical mechanism named explicitly and traced step by step? Or is it implied or vague?
> 3. **Evidence calibration**: Are claims supported with appropriate citations? Is hedging language (e.g., 'is associated with' vs. 'causes') calibrated to the research design?
> 4. **Section-specific logic**:
>    - Introduction: Is the gap statement convincing? Does the contribution specify what is new?
>    - Theory: Do hypotheses follow logically from the theoretical argument?
>    - Methods: Is the identification strategy or analytic choice justified?
>    - Results: Do reported findings align one-to-one with the stated hypotheses?
>    - Discussion: Does interpretation go beyond restating results?
> 5. **Completeness**: What critical element is missing that a reviewer at [journal] would flag?
>
> End with your single most important suggestion for improving this section.
>
> Draft text: [paste draft]"

---

**R2 — Rhetoric / Writing Critic**

Spawn a `general-purpose` agent:

> "You are a senior editor reviewing a draft [section] section of a paper targeting [journal]. Critique prose quality, paragraph structure, and communication — not substantive argument. Evaluate each item as **Strong / Adequate / Weak** and give 3–5 specific, actionable comments:
>
> 1. **Paragraph structure**: Does each paragraph open with a clear topic sentence? Is the PEEL pattern (Point → Evidence → Explanation → Link) followed?
> 2. **Transitions**: Are transitions between paragraphs explicit and logical, or does the text feel like disconnected blocks?
> 3. **Active voice and precision**: Is active voice used in Methods and Results? Are filler words ('important', 'significant', 'shows', 'clearly') replaced with precise alternatives?
> 4. **Contribution clarity**: Is the paper's specific contribution stated precisely — not just 'examines' or 'explores'?
> 5. **Journal register**: Does the prose match [journal]'s tone? (ASR/AJS: assertive, theoretical; Demography: technical, population-focused; NHB/NCS: accessible, broad scientific audience)
>
> End with your single most important suggestion for improving this section.
>
> Draft text: [paste draft]"

---

**R3 — Journal Fit Reviewer**

Spawn a `general-purpose` agent:

> "You are a former associate editor at [journal] reviewing a draft [section] section. Evaluate whether this section meets the specific expectations of [journal] — not generic academic writing quality. Evaluate each item as **Strong / Adequate / Weak** and give 3–5 specific, actionable comments:
>
> 1. **Length compliance**: Is the section within the expected word range for [journal]? (ASR/AJS Introduction: 800–1,000; Theory: 800–1,500; Results: 1,500–2,500. Demography Introduction: 600–800; Results: 2,000–3,000. NHB/NCS main text: 3,000–5,000 total.) Flag if over or under.
> 2. **Structural conventions**: Does the section follow [journal]'s expected structure? (e.g., NHB/NCS: no separate Theory section; Results before Methods; descriptive subsection headings. ASR/AJS: numbered hypotheses in Theory, BLENDED into thematic subsections with 3+ hypotheses. Demography: detailed sample construction, SEPARATE hypothesis block unless 3+ hypotheses.)
> 3. **Citation density and style**: Does the citation density match [journal]'s norms? (ASR/AJS: 2–4 citations per paragraph in lit review. NHB/NCS: leaner, 1–2 per paragraph. Demography: heavy in Methods.)
> 4. **Contribution framing**: Is the contribution framed the way [journal] expects? (ASR: theoretical advance. Demography: population/demographic insight. NHB/NCS: broad scientific finding with 'Here we show...' language.)
> 5. **Formatting signals**: Are there any formatting choices that would trigger a desk reject at [journal]? (e.g., wrong abstract format, missing keywords, section order violations.)
>
> End with your single most important suggestion for improving journal fit.
>
> Draft text: [paste draft]"

---

**R4 — Citation & Evidence Auditor**

Spawn a `general-purpose` agent:

> "You are a citation and evidence specialist auditing a draft [section] section of a paper targeting [journal]. Focus exclusively on citation coverage and evidence quality — not argument logic or prose style. Evaluate each item as **Strong / Adequate / Weak** and give 3–5 specific, actionable comments:
>
> 1. **Unsupported claims**: Identify every factual claim, empirical assertion, or theoretical statement that lacks a citation and should have one. Quote the specific sentence.
> 2. **Citation placement quality**: Are citations integrated naturally (signal-phrase: 'Granovetter (1973) argues...') or just appended parenthetically at sentence ends? Is there good balance between signal-phrase and parenthetical styles?
> 3. **[CITATION NEEDED] marker audit**: Are the existing `[CITATION NEEDED]` markers placed at critical load-bearing claims or only at peripheral mentions? Flag any missing markers where citations are urgently needed.
> 4. **Citation currency**: Are cited works reasonably current? Flag any claims citing only pre-2010 work where recent updates exist. Flag any claims relying solely on a single citation where the claim deserves corroboration.
> 5. **Evidence-claim alignment**: Do the cited sources actually support the claims being made? Flag any cases where a citation appears to be stretched beyond what the cited paper actually argues.
>
> End with a count: [N] unsupported claims found, [N] `[CITATION NEEDED]` markers present, [N] additional markers recommended.
>
> Draft text: [paste draft]"

---

**R5 — Accessibility / Clarity Reviewer**

Spawn a `general-purpose` agent:

> "You are an intelligent reader from an adjacent social science discipline (not the paper's primary field) reviewing a draft [section] section targeting [journal]. Your job is to flag anything that would confuse, bore, or lose a non-specialist reader. Evaluate each item as **Strong / Adequate / Weak** and give 3–5 specific, actionable comments:
>
> 1. **Jargon audit**: Flag any technical term, acronym, or field-specific concept that is used without definition on first use. Quote the specific instance.
> 2. **Buried contribution**: Can you identify the paper's main contribution within the first 2 paragraphs? Or is it buried deep in the section? State where you first understood what this paper adds.
> 3. **Narrative flow**: Does the section tell a clear story from start to finish? Or does it feel like a disconnected sequence of literature summaries? Identify the exact paragraph where flow breaks down (if any).
> 4. **Motivation clarity**: Would a reader outside the immediate subfield understand *why* this question matters? Is societal or scientific significance stated explicitly, or assumed?
> 5. **Takeaway test**: After reading this section, can you state in one sentence what it accomplished? Write that sentence. If you cannot, explain what is missing.
>
> End with your single most important suggestion for improving accessibility.
>
> Draft text: [paste draft]"

---

### Phase B — Synthesize Into Review Scorecard

After all 5 reviewers return, produce a **Review Scorecard** that aggregates their evaluations:

```
===== INTERNAL REVIEW PANEL — [Section] =====

Panel: R1 (Logic) | R2 (Rhetoric) | R3 (Journal Fit) | R4 (Citations) | R5 (Clarity)

| Dimension | R1 | R2 | R3 | R4 | R5 | Consensus |
|-----------|----|----|----|----|----|-----------|
| Argument structure | [S/A/W] | — | — | — | — | [S/A/W] |
| Mechanism specificity | [S/A/W] | — | — | — | — | [S/A/W] |
| Paragraph structure | — | [S/A/W] | — | — | — | [S/A/W] |
| Transitions | — | [S/A/W] | — | — | — | [S/A/W] |
| Active voice & precision | — | [S/A/W] | — | — | — | [S/A/W] |
| Length compliance | — | — | [S/A/W] | — | — | [S/A/W] |
| Structural conventions | — | — | [S/A/W] | — | — | [S/A/W] |
| Citation density & style | — | — | [S/A/W] | — | — | [S/A/W] |
| Unsupported claims | — | — | — | [S/A/W] | — | [S/A/W] |
| Citation placement | — | — | — | [S/A/W] | — | [S/A/W] |
| Jargon / accessibility | — | — | — | — | [S/A/W] | [S/A/W] |
| Narrative flow | — | — | — | — | [S/A/W] | [S/A/W] |
| **Weak items count** | [N] | [N] | [N] | [N] | [N] | **[total]** |

★★ Cross-agent agreement (raised by 2+ reviewers — highest priority):
1. [Issue] — flagged by [R1, R3] — [summary]
2. [Issue] — flagged by [R2, R5] — [summary]
...

Top suggestion from each reviewer:
- R1: [suggestion]
- R2: [suggestion]
- R3: [suggestion]
- R4: [N unsupported claims, N markers present, N additional markers recommended]
- R5: [suggestion]
```

---

### Phase C — Reviser Subagent (sequential, after Phase B)

After the scorecard is produced, spawn a **reviser subagent**:

> "You are an expert academic writer revising a draft [section] section for [journal]. You have feedback from a 5-agent review panel. Produce a revised version that addresses all valid concerns while maintaining the author's voice and argument.
>
> **Instructions**:
> 1. Address every ★★ item (cross-agent agreement) first — these are highest priority
> 2. Address every item rated **Weak** from any reviewer, unless doing so would contradict the paper's core argument — note any skipped items with a brief reason
> 3. Do not change anything rated **Strong** by 2+ reviewers — preserve those elements exactly
> 4. Add `[CITATION NEEDED]` markers for every unsupported claim identified by R4 that was not previously marked
> 5. Mark each substantive revision inline: `[REV: reason]`
> 6. After the revised text, append a **Revision Notes** block:
>    - ★★ items addressed (bulleted)
>    - Other changes made (bulleted)
>    - Reviewer comments not acted on and why
>
> **Original draft**: [paste draft]
> **Review Scorecard**: [paste scorecard from Phase B]
> **R1 feedback**: [paste R1 output]
> **R2 feedback**: [paste R2 output]
> **R3 feedback**: [paste R3 output]
> **R4 feedback**: [paste R4 output]
> **R5 feedback**: [paste R5 output]"

---

### Phase D — Accept the Revision

After the reviser returns:
1. Present the revised text and the Revision Notes to the user
2. Ask: **"Accept revised version? (`yes` / `accept with edits` / `keep original`)"**
3. Use the accepted version as the final text for Step 5b

---

## Step 5b: Verification Gate (Conditional)

**When to run:** This step runs automatically when raw analysis outputs exist in `output/tables/` or `output/figures/` (i.e., the user previously ran `/scholar-analyze`). If no raw outputs exist, skip to Step 6.

**Purpose:** Before saving the draft to disk, verify consistency between the accepted draft text and the underlying analysis outputs. This catches misquoted numbers, wrong table references, and stale figure descriptions before they become embedded in saved drafts.

### 5b.1 — Check for Raw Outputs

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
TABLE_COUNT=$(ls "${OUTPUT_ROOT}"/tables/*.{html,tex,csv,docx} 2>/dev/null | wc -l)
FIGURE_COUNT=$(ls "${OUTPUT_ROOT}"/figures/*.{pdf,png,svg} 2>/dev/null | wc -l)
echo "Tables: $TABLE_COUNT | Figures: $FIGURE_COUNT"
```

If both counts are 0, print: `"No raw analysis outputs found — skipping verification gate. Run /scholar-verify manually after /scholar-analyze."` and proceed to Step 6.

### 5b.2 — Run scholar-verify (stage2 mode)

Read the `scholar-verify` SKILL.md:

```bash
cat .claude/skills/scholar-verify/SKILL.md
```

Run `scholar-verify` in **stage2** mode (manuscript tables/figures → prose text) on the accepted draft text. This launches:
- **verify-logic**: Checks every statistical claim in the prose against the tables/figures in the draft
- **verify-completeness**: Ensures all artifacts from `output/tables/` and `output/figures/` are referenced in the draft

Pass the accepted draft text as the manuscript input (no need to read from disk — use the in-memory accepted version from Step 5 Phase D).

### 5b.3 — Present Verification Results

Display the verification scorecard and fix checklist to the user.

- If **0 CRITICAL issues**: Proceed to Step 6 automatically.
- If **1+ CRITICAL issues**: Present the fix checklist and ask: **"Fix these issues before saving? (`yes` / `save anyway` / `skip`)"**
  - `yes`: Apply fixes to the draft text, then proceed to Step 6
  - `save anyway`: Append the fix checklist as an addendum to the saved draft, then proceed to Step 6
  - `skip`: Proceed to Step 6 without changes

Log this step:
```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
SKILL_NAME="scholar-write"
LOG_DATE=$(date +%Y-%m-%d)
LOG_FILE="${OUTPUT_ROOT}/logs/process-log-${SKILL_NAME}-${LOG_DATE}.md"
if [ ! -f "$LOG_FILE" ]; then
  LOG_FILE=$(ls -t "${OUTPUT_ROOT}/logs/process-log-${SKILL_NAME}-${LOG_DATE}"*.md 2>/dev/null | head -1)
fi
echo "| 5b | $(date +%H:%M:%S) | Verification Gate | scholar-verify stage2 on accepted draft | [scorecard verdict] | ✓ |" >> "$LOG_FILE"
```

---

## Step 6: Save Output

After completing the section and the review loop, save two files using the Write tool.

**Create output directories**:
```bash
mkdir -p "${OUTPUT_ROOT}/drafts" "${OUTPUT_ROOT}/logs"
```

**Process Logging (REQUIRED):**

Initialize the process log NOW by running:

```bash
mkdir -p "${OUTPUT_ROOT}/logs"
SKILL_NAME="scholar-write"
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
SKILL_NAME="scholar-write"
LOG_DATE=$(date +%Y-%m-%d)
LOG_FILE="${OUTPUT_ROOT}/logs/process-log-${SKILL_NAME}-${LOG_DATE}.md"
if [ ! -f "$LOG_FILE" ]; then
  LOG_FILE=$(ls -t "${OUTPUT_ROOT}/logs/process-log-${SKILL_NAME}-${LOG_DATE}"*.md 2>/dev/null | head -1)
fi
echo "| [step#] | $(date +%H:%M:%S) | [Step Name] | [1-line action summary] | [output files or —] | ✓ |" >> "$LOG_FILE"
```

**IMPORTANT:** Shell variables do NOT persist across Bash tool calls. Every step MUST re-derive LOG_FILE before appending.

**Source Integrity (REQUIRED):**

Read and follow the Source Integrity Protocol in `.claude/skills/_shared/source-integrity.md`. This is MANDATORY for this skill. Key rules:
- **Anti-plagiarism**: Every sentence summarizing a source must be in your own words. No patchwork paraphrasing. Direct quotes require `"quoted phrase" (Author Year, p. N)`.
- **Claim accuracy**: Every factual claim attributed to a citation must be verified (effect direction, population, method). When Zotero PDFs are available, cross-check claims via pdftotext. Flag unverifiable claims as `[CLAIM UNVERIFIED]`.
- **Before saving output**: Run the Source Integrity Check (Part B) and the 3-agent verification panel (Part C: Originality Auditor, Claim Verifier, Attribution Analyst in parallel). Cross-validate with agreement matrix. Append panel report to output file.


### Version collision avoidance (MANDATORY — RUN BEFORE ANY Write tool call)

**⚠ STOP. You MUST run this Bash block BEFORE calling the Write tool.** Do NOT construct a file path manually. The Bash block below will print the correct path to use. Copy the printed path into your Write tool call.

**Step 6.0 — Determine save path (RUN THIS FIRST):**

```bash
# MANDATORY: Run this BEFORE saving. Replace [section], [slug], [YYYY-MM-DD] with actual values.
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
BASE="${OUTPUT_ROOT}/drafts/draft-[section]-[slug]-[YYYY-MM-DD]"

if [ -f "${BASE}.md" ]; then
  V=2
  while [ -f "${BASE}-v${V}.md" ]; do
    V=$((V + 1))
  done
  BASE="${BASE}-v${V}"
fi

# Print the path — use this EXACT path in the Write tool call
echo "SAVE_PATH=${BASE}.md"
echo "BASE=${BASE}"
```

**You MUST use the printed `SAVE_PATH` as the file_path in the Write tool call.** Do NOT hardcode the path. Do NOT skip this step. The same `BASE` value must also be used for the pandoc conversions in File 2b.

This ensures:
- First draft of the day: `draft-intro-slug-2026-03-03.md` (no suffix)
- Second run same day: `draft-intro-slug-2026-03-03-v2.md`
- Third run same day: `draft-intro-slug-2026-03-03-v3.md`

**NEVER overwrite an existing draft or log file.** Always increment the version suffix.

### File 1 — Writing Log (Internal Record)

**Purpose**: Internal record of drafting decisions. Not for submission.

**Filename**: `scholar-write-log-[section]-[slug]-[YYYY-MM-DD].md`

**Template**:

```markdown
# Writing Log — [Section] — [Topic Slug]

**Date**: [YYYY-MM-DD]
**Mode**: [DRAFT / REVISE / POLISH]
**Target journal**: [journal name]
**Section**: [section name]
**Word count**: [actual] / [target range]

## Example Articles Used
- your-article: [filename] — used for [voice/hook/structure note]
- top-journal: [filename] — used for [depth/citation-density note]

## Key Structural Decisions
- [Decision 1, e.g., "Opened with 2018 wage gap statistic rather than theoretical statement"]
- [Decision 2, e.g., "Separated H1 (main effect) and H2 (moderation) into distinct paragraphs"]
- [Decision 3, e.g., "Used 'associated with' rather than 'causes' — cross-sectional design"]

## Citations Needed
- [CITATION NEEDED: redlining measurement] — Theory ¶2
- [CITATION NEEDED: activity space measurement] — Methods ¶3
(List all [CITATION NEEDED] markers from the draft — feed to /scholar-citation)

## Tables and Figures (Step 4.7 Audit)
- **Artifact Registry**: [N tables, N figures] found in output directories
- **Referenced in draft**: [N] / [N total]
- **Placement markers**: [N] inserted
- **Tables appended**: Table 1 (descriptives), Table 2 (regression), ..., Table A1 (robustness)
- **Figures appended**: Figure 1 (coef plot), Figure 2 (AME interaction), ..., Figure A1 (missing data)
- **Unreferenced artifacts**: [list any deferred to other sections]

## Review Panel Summary (Step 5)
- **R1 (Logic)**: [top 2–3 concerns raised + rating]
- **R2 (Rhetoric)**: [top 2–3 concerns raised + rating]
- **R3 (Journal Fit)**: [top 2–3 concerns raised + rating]
- **R4 (Citations)**: [N unsupported claims found, N markers added]
- **R5 (Clarity)**: [top 2–3 concerns raised + rating]
- **★★ Cross-agent items**: [list items flagged by 2+ reviewers]
- **Weak item count**: [total across all 5 reviewers]
- **Changes made**: [bulleted list from Revision Notes]
- **Comments not acted on**: [item + reason]
- **Version accepted**: [original / revised / revised with edits]

## Known Gaps or Weaknesses
- [e.g., "H2 moderation paragraph is thin — needs more theoretical grounding"]
- [e.g., "Results section uses placeholder numbers — fill in after analysis"]
```

### Appendix / Supplementary Materials Structure

**Standard appendix organization**:
- **Appendix A**: Additional methodological details (variable construction, sample restrictions, matching diagnostics)
- **Appendix B**: Supplementary tables (full model results, alternative specifications, subgroup analyses)
- **Appendix C**: Supplementary figures (diagnostic plots, robustness visualizations)
- **Appendix D**: Data documentation (codebook excerpt, variable definitions, data access instructions)
- **Appendix E**: Formal proofs or derivations (if applicable)

**Nature Extended Data vs. Supplementary Information**:
- **Extended Data** (<=10 figures/tables): Peer-reviewed; referenced in main text as "Extended Data Fig. 1"
- **Supplementary Information**: Not peer-reviewed; referenced as "Supplementary Table 1"

### Section Word Budgets

| Section | ASR/AJS (12K) | Demography (10K) | Science Advances (5K) | NHB (4K) | NCS (4K) |
|---|---|---|---|---|---|
| Abstract | 150-200 | 150 | 250 | 150 | 150 |
| Introduction | 800-1200 | 600-800 | 500-700 | 400-500 | 400-500 |
| Theory/Background | 1500-2500 | 800-1200 | (in Intro) | (in Intro) | (in Intro) |
| Data & Methods | 1500-2500 | 1500-2000 | 800-1200 | 600-800 | 800-1000 |
| Results | 2000-3500 | 2000-3000 | 1200-1800 | 800-1200 | 800-1200 |
| Discussion | 2000-3500 | 800-1500 | 500-800 | 400-600 | 400-600 |
| Conclusion | 200-500 | 200-300 | (in Discussion) | (in Discussion) | (in Discussion) |
| References | ~50-80 refs | ~40-60 refs | ~40-60 refs | <=50 refs | <=50 refs |

> **Empirical calibration**: These ranges are calibrated from 53+ published papers. For per-paper word counts, see `assets/article-knowledge-base.md` → "Empirical Section Word Counts by Journal."

### Author Contributions (CRediT)

**Required by**: Science Advances, NHB, NCS. **Optional but recommended**: ASR, AJS, Demography.

Template: "Author contributions: [Author 1]: Conceptualization, Methodology, Formal analysis, Writing -- original draft. [Author 2]: Data curation, Visualization, Writing -- review & editing. [Author 3]: Supervision, Funding acquisition, Writing -- review & editing."

14 CRediT roles: Conceptualization, Data curation, Formal analysis, Funding acquisition, Investigation, Methodology, Project administration, Resources, Software, Supervision, Validation, Visualization, Writing -- original draft, Writing -- review & editing.

### File 2 — Draft Section (Publication-Ready)

**Purpose**: Clean section text ready to paste into the manuscript. All `[CITATION NEEDED]` markers are clearly visible for follow-up with `/scholar-citation`. No brackets should remain after the citation step.

**Filename**: `draft-[section]-[slug]-[YYYY-MM-DD].md`

**Template**:

```markdown
# [Section Title] — [Topic Slug]

<!-- Word count: [N] words | Target: [range] | Journal: [journal] -->
<!-- Mode: [DRAFT/REVISE/POLISH] | Date: [YYYY-MM-DD] -->
<!-- Artifact Registry: [N] tables, [N] figures referenced -->

[Full section text here — publication-ready prose.]
[Mark missing citations as: [CITATION NEEDED: brief description of what kind of source is needed]]
[These will be resolved by /scholar-citation in the next step.]

[In-text placement markers appear on their own line, e.g.:]

[Table 1 about here]

[Figure 1 about here]
```

**Close Process Log:**

Run the following to finalize the process log:

```bash
SKILL_NAME="scholar-write"
LOG_DATE=$(date +%Y-%m-%d)
LOG_FILE="${OUTPUT_ROOT}/logs/process-log-${SKILL_NAME}-${LOG_DATE}.md"
if [ ! -f "$LOG_FILE" ]; then
  LOG_FILE=$(ls -t "${OUTPUT_ROOT}/logs/process-log-${SKILL_NAME}-${LOG_DATE}"*.md 2>/dev/null | head -1)
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

### File 2a — Append Tables and Figures to Manuscript End (MANDATORY when ARTIFACT REGISTRY is non-empty)

After saving the main section text, append all tables and figures from the ARTIFACT REGISTRY at the end of the draft file. This follows standard journal convention where tables and figures appear after the main text, each on a separate "page."

**When to append**: Always for full-paper drafts. For individual section drafts (e.g., just Results), append only the tables/figures referenced in that section.

**CRITICAL RULE: Every table and figure MUST be embedded with actual content — never leave a placeholder like `[Insert table content here]` or `[Table content]` or just a file path. Read the source file and render the actual data.**

**Append to the draft markdown file** (`draft-[section]-[slug]-[YYYY-MM-DD].md`) using the procedure below.

**Procedure for TABLES** — for each table in the ARTIFACT REGISTRY:

1. **Read the source file** using the Read tool or Bash (e.g., `cat ${OUTPUT_ROOT}/tables/table1-descriptives.html`).
2. **Convert to markdown table**. For HTML tables, use this converter:
   ```bash
   python3 -c "
   import sys
   from html.parser import HTMLParser

   class TableExtractor(HTMLParser):
       def __init__(self):
           super().__init__()
           self.rows = []
           self.current_row = []
           self.current_cell = ''
           self.in_cell = False

       def handle_starttag(self, tag, attrs):
           if tag in ('td', 'th'):
               self.in_cell = True
               self.current_cell = ''
           elif tag == 'tr':
               self.current_row = []

       def handle_endtag(self, tag):
           if tag in ('td', 'th'):
               self.in_cell = False
               self.current_row.append(self.current_cell.strip())
           elif tag == 'tr':
               if self.current_row:
                   self.rows.append(self.current_row)

       def handle_data(self, data):
           if self.in_cell:
               self.current_cell += data

   with open(sys.argv[1]) as f:
       parser = TableExtractor()
       parser.feed(f.read())
       if parser.rows:
           header = parser.rows[0]
           print('| ' + ' | '.join(header) + ' |')
           print('|' + '|'.join(['---'] * len(header)) + '|')
           for row in parser.rows[1:]:
               while len(row) < len(header):
                   row.append('')
               print('| ' + ' | '.join(row[:len(header)]) + ' |')
   " "TABLE_PATH_HERE"
   ```
   If HTML conversion fails or for complex tables (merged cells, multi-level headers), include the raw HTML in a `<details>` block and note `<!-- See .tex or .docx version for formatted table -->`.
3. **Write the converted markdown table** into the draft file with this structure:
   ```markdown
   ---

   ## Table 1: [Descriptive Title]

   <!-- Source: ${OUTPUT_ROOT}/tables/table1-descriptives.html -->

   | Variable | Mean | SD | Min | Max |
   |----------|------|----|-----|-----|
   | Age      | 42.3 | 12.1 | 18 | 89 |
   | Income   | 54200 | 31000 | 0 | 250000 |

   **Notes**: N = 5,234. Data from [source]. Standard errors in parentheses. * p < 0.05, ** p < 0.01, *** p < 0.001.
   ```
   The pipe-delimited table above is an EXAMPLE — replace with the ACTUAL converted content from the source file.

**Procedure for FIGURES** — for each figure in the ARTIFACT REGISTRY:

1. **Verify the PNG file exists** using `ls` or Glob. If only PDF exists, convert: `convert "${OUTPUT_ROOT}/figures/fig-coef-plot.pdf" "${OUTPUT_ROOT}/figures/fig-coef-plot.png"` (ImageMagick) or `pdftoppm -png -singlefile "${OUTPUT_ROOT}/figures/fig-coef-plot.pdf" "${OUTPUT_ROOT}/figures/fig-coef-plot"` (poppler).
2. **Use an absolute path** in the markdown image syntax so pandoc can find the file during conversion:
   ```markdown
   ---

   ## Figure 1: [Descriptive Caption]

   <!-- Source PDF: ${OUTPUT_ROOT}/figures/fig-coef-plot.pdf -->

   ![Figure 1: Descriptive Caption](/absolute/path/to/output/figures/fig-coef-plot.png)

   **Notes**: [Figure notes — data source, sample, confidence interval description]
   ```
   **IMPORTANT**: The path inside `![caption](path)` MUST be an absolute path (e.g., `/Users/.../output/slug/figures/fig-coef-plot.png`), NOT a relative path or shell variable. Resolve `${OUTPUT_ROOT}` to its actual value before writing. This ensures pandoc embeds the image when converting to docx/pdf.

3. **After pandoc conversion to docx/pdf**, verify figures are actually embedded by checking file size — a docx with embedded figures will be significantly larger than one without. If the docx is suspiciously small (<50KB for a paper with figures), the paths were likely wrong.

**Verification after appending (MANDATORY)**:
- Grep the saved draft for `[Insert table content here]`, `[Table content]`, `${OUTPUT_ROOT}` — if any are found, the embedding is incomplete. Go back and replace with actual content.
- Grep for `![` lines and verify each path points to an existing file using `ls`.
- Count markdown table delimiters (`|`) to confirm tables have actual rows of data, not just headers.

3. **Table/figure captions**: Generate descriptive captions following journal conventions:
   - **ASR/AJS/Demography**: Table title above; notes below (sample size, significance levels, data source)
   - **NHB/NCS/Science Advances**: Figure caption below; includes methods summary in caption

4. **Table notes convention** (append below each table):
   ```
   **Notes**: N = [sample size]. [Data source]. [Variable definitions if needed].
   Standard errors in parentheses. † p < 0.10, * p < 0.05, ** p < 0.01, *** p < 0.001.
   [Additional notes: "Models include state and year fixed effects." etc.]
   ```

5. **If ARTIFACT REGISTRY is EMPTY**: Skip this step entirely. The draft will contain only prose with placeholder references like `(Table [N])`.

### File 2b — DOCX, PDF, and LaTeX Versions

After saving the markdown draft (including appended tables and figures), convert to docx, pdf, and tex using pandoc.

**CRITICAL: Re-derive `$BASE` using the SAME version collision avoidance logic from Step 6.0.** Shell variables do NOT persist between Bash tool calls, so you MUST re-run the version check to get the same `$BASE` value. Copy the exact same `BASE=...` line you used in Step 6.0, then run the same `if/while` check:

```bash
# RE-DERIVE $BASE — shell state does NOT persist between Bash calls
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
BASE="${OUTPUT_ROOT}/drafts/draft-[section]-[slug]-[YYYY-MM-DD]"
if [ -f "${BASE}.md" ]; then
  # The .md was JUST saved, so find the version that was actually written
  V=2
  while [ -f "${BASE}-v${V}.md" ]; do
    V=$((V + 1))
  done
  # The last existing version is V-1 (what we just saved)
  BASE="${BASE}-v$((V - 1))"
fi
echo "Converting: ${BASE}.md -> .docx, .tex, .pdf"

# Convert to docx
pandoc "${BASE}.md" -o "${BASE}.docx" \
  --reference-doc="$HOME/.pandoc/reference.docx" 2>/dev/null \
  || pandoc "${BASE}.md" -o "${BASE}.docx"

# Convert to LaTeX
pandoc "${BASE}.md" -o "${BASE}.tex" --standalone \
  -V geometry:margin=1in -V fontsize=12pt

# Convert to pdf (via LaTeX)
pandoc "${BASE}.md" -o "${BASE}.pdf" \
  -V geometry:margin=1in -V fontsize=12pt 2>/dev/null \
  || echo "PDF generation requires a LaTeX engine (pdflatex/xelatex). Install via: brew install --cask mactex-no-gui"
```

**Why this matters:** If the version check determined that `draft-intro-slug-2026-03-03.md` already exists and set `BASE` to `draft-intro-slug-2026-03-03-v2`, then the docx/tex/pdf must also be `*-v2.docx`, `*-v2.tex`, `*-v2.pdf`. Using a separate variable (like `DRAFT`) would overwrite the previous `.docx`.

This produces four versions of each section draft:
- `.md` — markdown (primary working format)
- `.docx` — Word document (for co-author review and track changes)
- `.tex` — LaTeX source (for journal submission systems and fine-grained typesetting)
- `.pdf` — PDF (for distribution and archiving)

Confirm all saved file paths to the user, including:
- `output/[slug]/manuscript/artifact-registry.md` (artifact registry for scholar-replication)

---

## Quality Checklist

### Universal
- [ ] Opens with a strong, specific hook or clear statement
- [ ] Each paragraph has one main point and a clear topic sentence
- [ ] Active voice dominates (especially Methods and Results)
- [ ] Arguments flow logically with explicit transitions between paragraphs
- [ ] Citations are integrated, not just appended at sentence end
- [ ] No undefined jargon
- [ ] Appropriate length for target journal (see Step 1 table)
- [ ] Tense consistent: present for theory/claims; past for methods/findings; present for describing tables
- [ ] All abbreviations defined on first use
- [ ] Hedging language matches design strength

### Citation Integrity (ABSOLUTE — check before any other section)
- [ ] **No fabricated citations** — every in-text citation verified via Verified Citation Pool (Step 0), CrossRef/Semantic Scholar/OpenAlex API, or carried from prior phases
- [ ] **Step 4.5 post-draft verification completed** — all citations cross-checked against pool; unverified citations converted to `[CITATION NEEDED]`
- [ ] All unverifiable citations replaced with `[CITATION NEEDED: description]` markers
- [ ] No guessed author names, years, volumes, pages, or DOIs
- [ ] Citation source log completed (verification source noted for each inserted citation)
- [ ] Post-draft verification summary included in writing log

### Tables and Figures Integration
- [ ] **Artifact Registry built** — all tables/figures from `output/[slug]/tables/`, `output/[slug]/figures/`, `output/[slug]/eda/` inventoried and numbered
- [ ] **Artifact Registry saved to disk** — `output/[slug]/manuscript/artifact-registry.md` written for `scholar-replication` VERIFY consumption
- [ ] **Every main-body artifact referenced in text** — each Table N and Figure N appears at least once in prose
- [ ] **Placement markers present** — `[Table N about here]` / `[Figure N about here]` on own line after first referencing paragraph
- [ ] **Tables appended at manuscript end** — each table on separate "page" with title, ACTUAL DATA CONTENT as markdown pipe table (not a placeholder or file path), and notes
- [ ] **Figures appended at manuscript end** — each figure on separate "page" with caption and ABSOLUTE path in `![caption](/absolute/path/to/file.png)` syntax (no `${OUTPUT_ROOT}` shell variables — resolve to actual path)
- [ ] **No unresolved placeholders** — grep draft for `[Insert table content here]`, `[Table content]`, `${OUTPUT_ROOT}` and confirm zero matches
- [ ] **Table notes complete** — sample size, significance levels, data source, model specifications noted
- [ ] **Figure captions descriptive** — self-contained; reader can understand figure without reading main text
- [ ] **Appendix items labeled correctly** — `Table A1`, `Figure A1` etc. for robustness/supplementary material
- [ ] **Step 4.7 placement audit completed** — all artifacts cross-checked, unreferenced items resolved

### Cross-Section Coherence (for full-paper drafts)
- [ ] Introduction hook connects back to the Discussion conclusion
- [ ] Every hypothesis in the Theory section is addressed in the Results (one-to-one)
- [ ] The Methods section describes the same variables as the Theory section
- [ ] Discussion does not introduce new evidence or hypotheses not in the Results
- [ ] Abstract accurately reflects the main finding and contribution as stated in the body text

### Journal-Specific
- [ ] **ASR/AJS**: Theory section ≥800 words; hypotheses numbered H1/H2/H3; BLENDED placement (thematic subsections) with 3+ H; AME used for logit models
- [ ] **Demography**: Sample construction paragraph has exact N and exclusion counts; all sensitivity analyses mentioned
- [ ] **Science Advances / NHB**: Results uses descriptive subsection headings; Methods follows Discussion; no separate Theory section
- [ ] **NHB/NCS**: Abstract ≤150 words; main text ≤5,000 words; reference list ≤50 items; exact p-values reported (not p < .05)

See [references/paper-structure.md](references/paper-structure.md) for journal-specific structural templates and paragraph-level writing templates.
See [references/academic-writing.md](references/academic-writing.md) for writing style guides, revision guidance, and transition library.
See [assets/index.md](assets/index.md) for the catalog of example articles (user1-articles + top-journal-articles).
