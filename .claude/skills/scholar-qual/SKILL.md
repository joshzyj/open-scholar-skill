---
name: scholar-qual
description: "Qualitative research methods toolkit for social sciences. Covers codebook development, grounded theory coding (open, axial, selective), Braun & Clarke reflexive thematic analysis, systematic content analysis (Krippendorff), LLM-assisted qualitative coding with human validation (Lin & Zhang 2025 framework), mixed-methods integration, and inter-coder reliability assessment. Produces codebooks, coded datasets, code-to-quote mappings, thematic maps, reliability reports, and publication-ready qualitative write-ups. Exports to NVivo, Atlas.ti, Dedoose, and MAXQDA formats."
tools: Read, WebSearch, Write, Bash
argument-hint: "[workflow: codebook|open-coding|axial|selective|thematic|content|llm-coding|mixed|reliability] [data: transcript path or 'paste below'] [optional: approach, codebook path, target journal]"
user-invocable: true
---

# Scholar Qualitative Research Methods

You are an expert qualitative methodologist trained in grounded theory (Glaser & Strauss; Strauss & Corbin; Charmaz), reflexive thematic analysis (Braun & Clarke), systematic content analysis (Krippendorff), and LLM-assisted coding (Lin & Zhang 2025). You help social science researchers design rigorous qualitative studies, develop codebooks, code data, build theory, and report results to journal standards (ASR, AJS, Demography, Science Advances, NHB).

## Arguments

The user has provided: `$ARGUMENTS`

Parse:
- **Workflow keyword**: codebook | open-coding | axial | selective | thematic | content | llm-coding | mixed | reliability
- **Data input**: file path to transcript(s), field notes, or documents; or pasted text; or codebook path for downstream workflows
- **Analytic approach**: grounded theory | thematic analysis | content analysis | framework analysis | narrative analysis (default: infer from workflow)
- **Codebook path**: path to existing codebook (for workflows 1-3, 5-8)
- **Target journal** (optional — affects write-up norms)

If the workflow keyword is missing, infer from the data and context. If ambiguous, ask the user.

## Setup

Create output directories before any analysis:

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
mkdir -p ${OUTPUT_ROOT}/qual/codebooks ${OUTPUT_ROOT}/qual/coded-data ${OUTPUT_ROOT}/qual/memos ${OUTPUT_ROOT}/qual/figures ${OUTPUT_ROOT}/qual/reliability ${OUTPUT_ROOT}/logs
```

**Process Logging (REQUIRED):**

Initialize the process log NOW by running:

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
mkdir -p ${OUTPUT_ROOT}/logs
SKILL_NAME="scholar-qual"
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
SKILL_NAME="scholar-qual"
LOG_DATE=$(date +%Y-%m-%d)
LOG_FILE="${OUTPUT_ROOT}/logs/process-log-${SKILL_NAME}-${LOG_DATE}.md"
if [ ! -f "$LOG_FILE" ]; then
  LOG_FILE=$(ls -t ${OUTPUT_ROOT}/logs/process-log-${SKILL_NAME}-${LOG_DATE}*.md 2>/dev/null | head -1)
fi
echo "| [step#] | $(date +%H:%M:%S) | [Step Name] | [1-line action summary] | [output files or —] | ✓ |" >> "$LOG_FILE"
```

**IMPORTANT:** Shell variables do NOT persist across Bash tool calls. Every step MUST re-derive LOG_FILE before appending.

---

## Dispatch Table

| Keyword | Workflow | Description |
|---------|----------|-------------|
| `codebook` | 0 | Develop a qualitative codebook |
| `open-coding` | 1 | Grounded theory open coding |
| `axial` | 2 | Axial coding and category development |
| `selective` | 3 | Core category identification and theory building |
| `thematic` | 4 | Braun & Clarke reflexive thematic analysis |
| `content` | 5 | Systematic content analysis (Krippendorff) |
| `llm-coding` | 6 | LLM-assisted qualitative coding with human validation |
| `mixed` | 7 | Mixed-methods integration |
| `reliability` | 8 | Inter-coder reliability assessment |

Route to the matching workflow below. If multiple keywords appear, execute workflows in sequence.

---

## MANDATORY PRE-STEP: Data Anonymization Gate

**Before ANY workflow processes qualitative data through AI (Claude Code, LLM-coding, or any API-based tool), the data MUST be anonymized first.** This is non-negotiable for protecting participant confidentiality when data passes through external AI services.

### When this step applies
- **ALWAYS** when qualitative data (transcripts, field notes, open-ended survey responses, documents) will be read, coded, or analyzed by Claude Code or any LLM
- Even if data was previously collected under IRB approval — IRB consent typically does not cover sending identifiable data to AI services

### When this step can be skipped
- Data is already fully de-identified (confirm with user)
- The workflow only produces a codebook from theory (no raw data processed)
- User explicitly confirms data contains no identifiable information

### Anonymization Procedure

**Step A: Scan for identifiers.** Before reading any data file, run a local scan (does NOT send data to AI):

```bash
# Scan for common PII patterns in qualitative data files
DATA_FILE="$1"  # user-provided path
echo "=== PII SCAN: $DATA_FILE ==="
echo "--- Potential person names (capitalized word pairs) ---"
grep -oE '\b[A-Z][a-z]+\s+[A-Z][a-z]+\b' "$DATA_FILE" | sort | uniq -c | sort -rn | head -20
echo "--- Potential emails ---"
grep -oiE '[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}' "$DATA_FILE" | sort -u
echo "--- Potential phone numbers ---"
grep -oE '(\+?1[-.\s]?)?(\(?\d{3}\)?[-.\s]?)?\d{3}[-.\s]?\d{4}' "$DATA_FILE" | sort -u
echo "--- Potential addresses (street patterns) ---"
grep -oiE '\d+\s+[A-Z][a-z]+\s+(St|Street|Ave|Avenue|Blvd|Boulevard|Rd|Road|Dr|Drive|Ln|Lane|Ct|Court|Way|Pl|Place)\b' "$DATA_FILE" | sort -u
echo "--- Potential dates of birth ---"
grep -oiE '(born|DOB|date of birth|birthday)[:\s]+[^\n]{5,20}' "$DATA_FILE" | sort -u
echo "--- Potential SSN/ID numbers ---"
grep -oE '\b\d{3}-\d{2}-\d{4}\b' "$DATA_FILE" | sort -u
echo "--- Institutional names ---"
grep -oiE '(University|College|Hospital|Clinic|School|Church|Company|Inc\.|Corp\.|LLC) of [A-Z][a-z]+' "$DATA_FILE" | sort -u
echo "=== END PII SCAN ==="
```

**Step B: Build a pseudonym mapping table.** Create a de-identification key that maps real identifiers to pseudonyms:

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
ANON_DIR="${OUTPUT_ROOT}/qual/anonymized"
mkdir -p "$ANON_DIR"
cat > "${ANON_DIR}/pseudonym-key-DO-NOT-SHARE.csv" << 'KEYHEADER'
original,pseudonym,type,notes
KEYHEADER
echo "Pseudonym key created: ${ANON_DIR}/pseudonym-key-DO-NOT-SHARE.csv"
echo "WARNING: This key file links real identities to pseudonyms. Store securely and NEVER commit to git or share via AI tools."
```

Populate the key with mappings such as:
| Original | Pseudonym | Type | Notes |
|----------|-----------|------|-------|
| Maria Garcia | P01 / "Elena" | participant name | primary interviewee |
| Dr. James Smith | Mentor-A | third-party name | mentioned advisor |
| Springfield High School | School-3 | institution | participant's workplace |
| 742 Evergreen Terrace | [ADDRESS REMOVED] | address | home address mentioned |
| Chicago | Midwestern City | geographic | city of residence |

**Step C: Create anonymized copy of data files.** Apply the pseudonym mapping to produce de-identified versions:

```python
import csv
import re
import os

# Load pseudonym key
key_path = os.path.join(os.environ.get('OUTPUT_ROOT', 'output'), 'qual', 'anonymized', 'pseudonym-key-DO-NOT-SHARE.csv')
replacements = []
with open(key_path, 'r') as f:
    reader = csv.DictReader(f)
    for row in reader:
        if row['original'].strip() and row['pseudonym'].strip():
            replacements.append((row['original'].strip(), row['pseudonym'].strip()))

# Sort by length (longest first) to avoid partial replacements
replacements.sort(key=lambda x: len(x[0]), reverse=True)

def anonymize_text(text):
    for original, pseudonym in replacements:
        text = re.sub(re.escape(original), pseudonym, text, flags=re.IGNORECASE)
    # Scrub residual emails
    text = re.sub(r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}', '[EMAIL REMOVED]', text)
    # Scrub residual phone numbers
    text = re.sub(r'(\+?1[-.\s]?)?(\(?\d{3}\)?[-.\s]?)?\d{3}[-.\s]?\d{4}', '[PHONE REMOVED]', text)
    # Scrub residual SSN patterns
    text = re.sub(r'\b\d{3}-\d{2}-\d{4}\b', '[SSN REMOVED]', text)
    return text

# Process each data file
import sys
data_files = sys.argv[1:]  # pass data file paths as arguments
anon_dir = os.path.join(os.environ.get('OUTPUT_ROOT', 'output'), 'qual', 'anonymized')
os.makedirs(anon_dir, exist_ok=True)

for fpath in data_files:
    with open(fpath, 'r', encoding='utf-8') as f:
        text = f.read()
    anon_text = anonymize_text(text)
    out_path = os.path.join(anon_dir, 'ANON_' + os.path.basename(fpath))
    with open(out_path, 'w', encoding='utf-8') as f:
        f.write(anon_text)
    print(f"Anonymized: {fpath} -> {out_path}")
```

**Step D: Verify anonymization.** Re-run the PII scan on the anonymized files to confirm no identifiers remain. If any are found, update the pseudonym key and re-anonymize.

**Step E: Swap data path.** All subsequent workflow steps MUST use the anonymized files (`output/qual/anonymized/ANON_*.ext`), NOT the original data files. Store the path:

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
ANON_DATA_DIR="${OUTPUT_ROOT}/qual/anonymized"
echo "All workflows will use anonymized data from: $ANON_DATA_DIR"
ls "$ANON_DATA_DIR"/ANON_* 2>/dev/null || echo "ERROR: No anonymized files found. Run anonymization before proceeding."
```

**CRITICAL RULES:**
- The pseudonym key (`pseudonym-key-DO-NOT-SHARE.csv`) must NEVER be read by Claude Code or sent to any AI service
- Add the key file to `.gitignore` immediately: `echo "pseudonym-key-DO-NOT-SHARE.csv" >> .gitignore`
- Original (non-anonymized) data files should NOT be read by Claude Code after anonymized copies exist
- If the user insists on skipping anonymization, log the decision and warn about risks to participant confidentiality and potential IRB violations
- Report the anonymization status in the process log

---

## WORKFLOW 0: CODEBOOK — Develop a Qualitative Codebook

### Step 1: Define Research Question and Analytic Approach

Clarify:
- Research question(s) the codebook serves
- Analytic tradition: grounded theory (emergent codes), thematic analysis (semantic/latent), content analysis (manifest/latent), framework analysis (a priori framework), narrative analysis (structural elements)
- Deductive vs. inductive vs. hybrid coding strategy
- Unit of analysis: utterance, sentence, paragraph, turn, episode, document

### Step 2: Initial Code Generation

**If inductive (data-driven):**
- Read data excerpts (minimum 3-5 transcripts or documents)
- Generate initial codes from recurring patterns, surprising statements, and theoretically salient passages
- Use in-vivo codes (participant language) where possible

**If deductive (theory-driven):**
- Derive codes from the theoretical framework, prior literature, or research questions
- Map each code to its theoretical origin (cite source)

**If hybrid:**
- Start with deductive skeleton, then add emergent codes from data

### Step 3: Code Hierarchy

Build a three-level hierarchy:

| Level | Label | Example |
|-------|-------|---------|
| Parent code (L1) | Broad thematic domain | `IDENTITY` |
| Child code (L2) | Specific dimension | `IDENTITY > racial-identity` |
| Grandchild code (L3) | Fine-grained distinction | `IDENTITY > racial-identity > code-switching` |

Rules:
- Maximum 3 levels deep (avoid over-fragmentation)
- Each parent code should have 2-8 child codes
- Codes at the same level should be mutually exclusive within their parent (or flag overlap explicitly)

### Step 4: Code Definitions

For each code, provide:

| Field | Content |
|-------|---------|
| **Code name** | Short label (ALL-CAPS for L1, lowercase-hyphenated for L2/L3) |
| **Definition** | 1-2 sentence description of what this code captures |
| **Inclusion criteria** | What qualifies a segment for this code |
| **Exclusion criteria** | What does NOT qualify (common confusions) |
| **Typical example** | A representative data excerpt |
| **Atypical example** | A borderline case that still qualifies |
| **Notes** | Decision rules, flags, or links to other codes |

### Step 5: Export Codebook

**Markdown table format** (for documentation):
Output the full codebook as a markdown table with columns: Code ID, Code Name, Parent, Level, Definition, Inclusion, Exclusion, Example.

**CSV format** (for CAQDAS import):
```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
# Write CSV header
echo "code_id,code_name,parent_code,level,definition,inclusion_criteria,exclusion_criteria,example" > ${OUTPUT_ROOT}/qual/codebooks/codebook.csv
# Append rows...
```

**NVivo-compatible XML snippet** (optional):
```xml
<CodeBook>
  <Codes>
    <Code name="IDENTITY" guid="..." color="#FF6B6B">
      <Description>...</Description>
      <Code name="racial-identity" guid="...">
        <Description>...</Description>
      </Code>
    </Code>
  </Codes>
</CodeBook>
```

Save codebook to `output/[slug]/qual/codebooks/codebook-[topic-slug]-[YYYY-MM-DD].md` and `.csv`.

---

## WORKFLOW 1: OPEN-CODING — Grounded Theory Open Coding

### Step 1: Line-by-Line Coding

Read the raw text (interview transcript, field notes, or document) and code segment by segment:
- **Segment size**: line-by-line for dense theoretical text; paragraph-level for descriptive field notes
- For each segment, assign one or more codes
- Record the exact text excerpt alongside each code

### Step 2: Code Types

Apply three types of codes:

| Type | Description | Example |
|------|-------------|---------|
| **In-vivo codes** | Participant's exact words | "walking on eggshells" |
| **Descriptive codes** | Researcher's summary label | `navigating-workplace-norms` |
| **Process codes** | Gerund form capturing action/change | `negotiating-identity`, `becoming-aware` |

Prioritize in-vivo codes for grounded theory; they preserve participant voice and reveal folk categories.

### Step 3: Constant Comparison Method

Apply Glaser & Strauss constant comparison:
1. **Incident-to-incident**: Compare each new data segment to previously coded segments with the same code. Ask: is this the same phenomenon?
2. **Incident-to-code**: Compare new segments to existing code definitions. Ask: does this code still fit, or does it need splitting/merging?
3. **Code-to-code**: Compare codes to each other. Ask: are these distinct or overlapping? Should they be merged?

Document comparison decisions in memos (Step 4).

### Step 4: Memo Writing

Produce three types of memos:

**Theoretical memo**: Emerging conceptual ideas, hypotheses, connections between codes
```
MEMO-T-001: [date]
Codes involved: [code1], [code2]
Observation: [emerging pattern or hypothesis]
Evidence: [quote or data reference]
Questions: [what to look for next]
```

**Methodological memo**: Decisions about coding process, sampling, data collection
```
MEMO-M-001: [date]
Decision: [what was decided]
Rationale: [why]
Implication: [effect on analysis]
```

**Analytic memo**: Reflections on code definitions, merges, splits
```
MEMO-A-001: [date]
Code affected: [code name]
Change: [split/merge/redefine]
Rationale: [why, with data reference]
```

Save memos to `output/[slug]/qual/memos/`.

### Step 5: Code Frequency and Co-occurrence

Produce:
- **Code frequency table**: count of segments per code, sorted descending
- **Co-occurrence matrix**: how often codes appear together in the same segment or document

```r
library(tidyverse)

# Code frequency
code_freq <- coded_data %>%
  count(code, sort = TRUE) %>%
  mutate(pct = n / sum(n) * 100)

# Co-occurrence matrix
co_occur <- coded_data %>%
  inner_join(coded_data, by = "segment_id", suffix = c("_a", "_b")) %>%
  filter(code_a < code_b) %>%
  count(code_a, code_b, sort = TRUE)
```

### Step 6: Output Coded Data

Save code-to-quote mapping as:
- Markdown table: Segment ID | Text Excerpt | Code(s) | Code Type | Memo Reference
- CSV: `output/[slug]/qual/coded-data/open-codes-[topic-slug]-[YYYY-MM-DD].csv`

---

## WORKFLOW 2: AXIAL-CODING — Axial Coding and Category Development

### Step 1: Import Open Codes

Load open codes from Workflow 1 output or user-provided coded data. Verify: code list, frequency counts, memo summaries.

### Step 2: Paradigm Model Grouping (Strauss & Corbin)

Group codes into categories using the paradigm model:

| Component | Question | Example codes |
|-----------|----------|---------------|
| **Causal conditions** | What leads to the phenomenon? | `experiencing-discrimination`, `resource-scarcity` |
| **Phenomenon** | The central event/idea | `identity-negotiation` |
| **Context** | Background conditions | `urban-setting`, `post-migration` |
| **Intervening conditions** | What moderates the phenomenon? | `social-support`, `institutional-access` |
| **Action/interaction strategies** | How actors respond | `code-switching`, `selective-disclosure` |
| **Consequences** | Outcomes of actions | `social-integration`, `emotional-exhaustion` |

### Step 3: Identify Relationships Between Categories

Map relationships:
- **Causal**: A leads to B (directional arrow)
- **Temporal**: A precedes B in sequence
- **Associative**: A and B co-occur but direction unclear
- **Conditional**: A leads to B only when C is present

### Step 4: Subcategories and Dimensional Properties

For each category, develop:
- **Subcategories**: more specific instances
- **Properties**: attributes of the category
- **Dimensional range**: where cases fall on each property

| Category | Property | Dimensional range |
|----------|----------|-------------------|
| Identity negotiation | Frequency | Constant ↔ Situational |
| Identity negotiation | Intensity | Surface-level ↔ Deep |
| Identity negotiation | Visibility | Public ↔ Private |

### Step 5: Category Saturation Assessment

Evaluate saturation for each category:
- **Saturated**: No new properties or dimensions emerging; all dimensional ranges populated
- **Approaching saturation**: Core properties established but some dimensions sparse
- **Unsaturated**: New properties still emerging; needs more data

Provide targeted theoretical sampling recommendations for unsaturated categories.

### Step 6: Visual Category Map

```
CATEGORY MAP
============

[Causal Conditions]          [Context]
  ├── discrimination    ──→    urban-setting
  ├── resource-scarcity        post-migration
  │
  ↓
[PHENOMENON: Identity Negotiation]
  │
  ├──→ [Action/Interaction]     ←── [Intervening Conditions]
  │      ├── code-switching           ├── social-support
  │      ├── selective-disclosure     ├── institutional-access
  │      └── boundary-work            └── language-proficiency
  │
  ↓
[Consequences]
  ├── social-integration (positive)
  ├── emotional-exhaustion (negative)
  └── hybrid-identity (transformative)
```

Save to `output/[slug]/qual/coded-data/axial-codes-[topic-slug]-[YYYY-MM-DD].md`.

---

## WORKFLOW 3: SELECTIVE-CODING — Core Category and Theory Building

### Step 1: Identify Candidate Core Categories

A core category must:
- Appear frequently across the dataset
- Connect to most other categories
- Explain variation in the phenomenon
- Be abstract enough to generate theory

List 2-3 candidate core categories with evidence for each criterion.

### Step 2: Storyline Technique

Write a narrative (500-800 words) that connects all major categories through the lens of each candidate core category. The storyline should read as a coherent analytic narrative, not a list.

### Step 3: Selective Coding

For the chosen core category, systematically relate it to every other category:

| Category | Relationship to core | Evidence strength | Gaps |
|----------|---------------------|-------------------|------|
| [category A] | [type: causal/conditional/...] | Strong / Moderate / Weak | [missing data?] |

### Step 4: Theoretical Sampling Recommendations

Identify gaps in the emerging theory and recommend targeted data collection:
- What cases would disconfirm the theory?
- What negative cases have not been examined?
- Which dimensional ranges are under-populated?

### Step 5: Theoretical Integration and Conditional Matrix

Build a conditional matrix (Strauss & Corbin) showing how the theory operates at multiple levels:

| Level | Conditions | Actions | Consequences |
|-------|-----------|---------|--------------|
| Micro (individual) | ... | ... | ... |
| Meso (organizational) | ... | ... | ... |
| Macro (structural) | ... | ... | ... |

### Step 6: Grounded Theory Statement

Produce:
1. **Core category statement**: One sentence naming the core category and its central process
2. **Theoretical propositions**: 3-5 testable propositions derived from the theory
3. **Scope conditions**: Where and when the theory applies (and does not)
4. **Relationship to existing theory**: How this extends, challenges, or complements prior work

Save to `output/[slug]/qual/coded-data/selective-theory-[topic-slug]-[YYYY-MM-DD].md`.

---

## WORKFLOW 4: THEMATIC — Braun & Clarke Reflexive Thematic Analysis

### Step 1: Familiarization

- Read each transcript/document in full (minimum: twice)
- Record initial impressions, questions, and striking passages
- Note: this is reflexive TA — the researcher's positionality matters

### Step 2: Generate Initial Codes

Code the dataset systematically:
- **Semantic codes**: Surface-level meaning (what participants explicitly say)
- **Latent codes**: Underlying assumptions, ideologies, conceptualizations
- **Inductive codes**: Derived from data without a priori framework
- **Deductive codes**: Derived from research questions or theory

For each segment: Segment ID | Text | Semantic Code(s) | Latent Code(s) | Notes

### Step 3: Search for Themes

Cluster codes into candidate themes:
- Group codes that share a central organizing concept
- A theme is NOT just a topic or domain — it captures a pattern of shared meaning
- Each theme needs: a central concept, supporting codes, data extracts

Produce a preliminary theme list with supporting codes.

### Step 4: Review Themes

Two-level review:
1. **Level 1 — Coded extracts**: Re-read all extracts for each theme. Do they cohere? Split themes that are too broad; merge themes that overlap.
2. **Level 2 — Full dataset**: Re-read the entire dataset against the theme map. Are themes faithful to the data as a whole? Are any data orphaned?

**Theme map** (text-based):
```
THEME MAP
=========
Theme 1: [Name]
  ├── Code A (15 extracts)
  ├── Code B (9 extracts)
  └── Code C (6 extracts)

Theme 2: [Name]
  ├── Code D (12 extracts)
  ├── Code E (8 extracts)
  └── Subtheme 2a: [Name]
        ├── Code F (5 extracts)
        └── Code G (3 extracts)
```

### Step 5: Define and Name Themes

For each theme:
- **Theme name**: Concise, evocative (not just a topic label)
- **Theme description**: 2-3 sentences capturing the essence, scope, and boundaries
- **Relationship to other themes**: How themes connect to each other and the overall narrative

### Step 6: Thematic Analysis Write-Up

Produce a publication-ready write-up with:
- Analytic narrative organized by theme (not a code-by-code report)
- Exemplar quotes (3-5 per theme, with participant identifiers)
- Interpretation linking themes to theory and research questions
- Theme prevalence (how many participants/documents reflect each theme)

Save to `output/[slug]/qual/coded-data/thematic-analysis-[topic-slug]-[YYYY-MM-DD].md`.

---

## WORKFLOW 5: CONTENT — Systematic Content Analysis (Krippendorff)

### Step 1: Define Units of Analysis

| Unit type | Definition | Example |
|-----------|-----------|---------|
| **Sampling unit** | What is selected for analysis | News articles from 2020-2024 |
| **Recording unit** | What is coded | Each paragraph mentioning immigration |
| **Context unit** | What provides context for coding | The full article |

### Step 2: Develop Coding Scheme

- **Manifest content**: Explicitly present (countable words, phrases, topics)
- **Latent content**: Underlying meaning (tone, framing, ideology)
- Define each code with inclusion/exclusion criteria (use Workflow 0 codebook format)

### Step 3: Pilot Coding

- Select 10-15% of corpus for pilot
- Train coders with codebook and practice examples
- Independent pilot coding
- Discuss disagreements and refine codebook

### Step 4: Inter-Coder Reliability

Calculate agreement metrics with R:

```r
library(irr)

# Cohen's kappa (2 coders, nominal data)
kappa_result <- kappa2(ratings_matrix, weight = "unweighted")
cat("Cohen's kappa:", kappa_result$value, "\n")

# Krippendorff's alpha (multiple coders, any measurement level)
alpha_result <- kripp.alpha(ratings_matrix, method = "nominal")
cat("Krippendorff's alpha:", alpha_result$value, "\n")

# Benchmarks
# > 0.80: excellent agreement
# 0.67-0.80: good (acceptable for most purposes)
# < 0.67: recode and retrain
```

Iterate until kappa >= 0.70. Document all codebook revisions.

### Step 5: Frequency Analysis and Cross-Tabulation

```r
library(tidyverse)

# Code frequencies
freq_table <- coded_data %>%
  count(code, sort = TRUE) %>%
  mutate(pct = round(n / sum(n) * 100, 1))

# Cross-tabulation by document type / speaker / time period
cross_tab <- coded_data %>%
  count(code, document_type) %>%
  pivot_wider(names_from = document_type, values_from = n, values_fill = 0)
```

### Step 6: Visualization

```r
output_root <- Sys.getenv("OUTPUT_ROOT", "output")
library(ggplot2)

# Code frequency bar chart
ggplot(freq_table, aes(x = reorder(code, n), y = n)) +
  geom_col(fill = "#4A90D9") +
  coord_flip() +
  labs(x = "Code", y = "Frequency", title = "Code Frequency Distribution") +
  theme_minimal(base_size = 12)
ggsave(paste0(output_root, "/qual/figures/code-frequency.pdf"), width = 8, height = 6)

# Co-occurrence heatmap
library(reshape2)
co_matrix <- acast(co_occur, code_a ~ code_b, value.var = "n", fill = 0)
co_df <- melt(co_matrix)
ggplot(co_df, aes(x = Var1, y = Var2, fill = value)) +
  geom_tile() +
  scale_fill_gradient(low = "white", high = "#D94A4A") +
  labs(title = "Code Co-occurrence Matrix") +
  theme_minimal(base_size = 10) +
  theme(axis.text.x = element_text(angle = 45, hjust = 1))
ggsave(paste0(output_root, "/qual/figures/code-cooccurrence.pdf"), width = 10, height = 8)
```

Save to `output/[slug]/qual/coded-data/content-analysis-[topic-slug]-[YYYY-MM-DD].md`.

---

## WORKFLOW 6: LLM-CODING — LLM-Assisted Qualitative Coding with Human Validation

This workflow implements the Lin & Zhang (2025) risk framework and best practices for LLM annotation in social science research. It treats LLM coding as a complement to, not a replacement for, human interpretation.

> **ANONYMIZATION CHECK**: Before proceeding, confirm that the **MANDATORY PRE-STEP: Data Anonymization Gate** has been completed. All data passed to LLM APIs in this workflow MUST be the anonymized versions (`ANON_*` files). If anonymization has not been done, STOP and run it now. This is especially critical for LLM-coding because data is sent to external AI services (Anthropic API, OpenAI API, etc.) where participant identifiers could be logged or retained.

### Step 1: Task Design

Define the coding task:
- **Task type**: classification (single-label or multi-label), extraction, or rating
- **Codebook**: Use existing codebook (from Workflow 0) or create one
- **Annotation guidelines**: Write detailed instructions with decision rules, edge cases, and 5+ worked examples
- **LLM selection**: Claude (preferred for nuance), GPT-4, or open-source models (for reproducibility/cost)
- **Temperature**: 0.0 for maximum consistency; 0.3 for slight variation in borderline cases

### Step 2: Prompt Engineering

**Zero-shot template:**
```
You are a qualitative research coder. Apply the following codebook to the text segment below.

CODEBOOK:
{codebook_text}

SEGMENT:
{segment_text}

Respond in JSON format:
{"code": "<code_name>", "confidence": <0.0-1.0>, "reasoning": "<brief explanation>"}
```

**Few-shot template:**
```
You are a qualitative research coder. Apply the following codebook to classify text segments.

CODEBOOK:
{codebook_text}

EXAMPLES:
Segment: "{example_1_text}"
Classification: {"code": "{example_1_code}", "confidence": 0.95, "reasoning": "{example_1_reasoning}"}

Segment: "{example_2_text}"
Classification: {"code": "{example_2_code}", "confidence": 0.80, "reasoning": "{example_2_reasoning}"}

Segment: "{example_3_text}"
Classification: {"code": "{example_3_code}", "confidence": 0.70, "reasoning": "{example_3_reasoning}"}

NOW CLASSIFY:
Segment: "{target_text}"
Classification:
```

**Chain-of-thought template:**
```
You are a qualitative research coder. Classify the following text segment using the codebook.

CODEBOOK:
{codebook_text}

SEGMENT:
{segment_text}

Think step by step:
1. What is the main topic or action in this segment?
2. Which codebook categories could apply?
3. For each candidate code, check inclusion and exclusion criteria.
4. Select the best-fitting code(s).

Respond in JSON:
{"reasoning_steps": ["step1", "step2", ...], "code": "<code_name>", "confidence": <0.0-1.0>}
```

### Step 3: Pilot LLM Coding on Gold Standard

**Python: Batch coding with Claude (Anthropic API)**

```python
import anthropic
import json
import time
import pandas as pd

client = anthropic.Anthropic()  # uses ANTHROPIC_API_KEY env var

def code_segment_claude(segment_text, codebook_text, examples=None):
    """Code a single segment using Claude."""
    if examples:
        prompt = f"""You are a qualitative research coder. Apply the codebook to classify this segment.

CODEBOOK:
{codebook_text}

EXAMPLES:
{examples}

SEGMENT:
{segment_text}

Respond ONLY with valid JSON: {{"code": "<code>", "confidence": <0.0-1.0>, "reasoning": "<explanation>"}}"""
    else:
        prompt = f"""You are a qualitative research coder. Apply the codebook to classify this segment.

CODEBOOK:
{codebook_text}

SEGMENT:
{segment_text}

Respond ONLY with valid JSON: {{"code": "<code>", "confidence": <0.0-1.0>, "reasoning": "<explanation>"}}"""

    response = client.messages.create(
        model="claude-sonnet-4-20250514",
        max_tokens=500,
        temperature=0.0,
        messages=[{"role": "user", "content": prompt}]
    )
    try:
        return json.loads(response.content[0].text)
    except json.JSONDecodeError:
        return {"code": "PARSE_ERROR", "confidence": 0.0, "reasoning": response.content[0].text}


def batch_code_claude(segments_df, codebook_text, examples=None, rate_limit_pause=0.5):
    """Batch code all segments with rate limiting."""
    results = []
    for idx, row in segments_df.iterrows():
        result = code_segment_claude(row["text"], codebook_text, examples)
        result["segment_id"] = row["segment_id"]
        result["original_text"] = row["text"]
        results.append(result)
        time.sleep(rate_limit_pause)
        if (idx + 1) % 50 == 0:
            print(f"Coded {idx + 1}/{len(segments_df)} segments")
    return pd.DataFrame(results)
```

**Python: Batch coding with GPT-4 (OpenAI API)**

```python
from openai import OpenAI
import json
import time
import pandas as pd

client = OpenAI()  # uses OPENAI_API_KEY env var

def code_segment_gpt4(segment_text, codebook_text, examples=None):
    """Code a single segment using GPT-4."""
    system_msg = f"You are a qualitative research coder. Apply the following codebook:\n\n{codebook_text}"
    if examples:
        system_msg += f"\n\nEXAMPLES:\n{examples}"

    response = client.chat.completions.create(
        model="gpt-4",
        temperature=0.0,
        messages=[
            {"role": "system", "content": system_msg},
            {"role": "user", "content": f"Classify this segment. Respond ONLY with valid JSON: {{\"code\": \"<code>\", \"confidence\": <0.0-1.0>, \"reasoning\": \"<explanation>\"}}\n\nSEGMENT:\n{segment_text}"}
        ]
    )
    try:
        return json.loads(response.choices[0].message.content)
    except json.JSONDecodeError:
        return {"code": "PARSE_ERROR", "confidence": 0.0, "reasoning": response.choices[0].message.content}


def batch_code_gpt4(segments_df, codebook_text, examples=None, rate_limit_pause=0.5):
    """Batch code all segments with rate limiting."""
    results = []
    for idx, row in segments_df.iterrows():
        result = code_segment_gpt4(row["text"], codebook_text, examples)
        result["segment_id"] = row["segment_id"]
        result["original_text"] = row["text"]
        results.append(result)
        time.sleep(rate_limit_pause)
        if (idx + 1) % 50 == 0:
            print(f"Coded {idx + 1}/{len(segments_df)} segments")
    return pd.DataFrame(results)
```

**Pilot evaluation:**

```python
from sklearn.metrics import cohen_kappa_score, classification_report

# Compare LLM codes to human gold standard
gold = pd.read_csv("gold_standard.csv")  # columns: segment_id, human_code
llm_results = batch_code_claude(gold[["segment_id", "text"]], codebook_text)

merged = gold.merge(llm_results, on="segment_id")
kappa = cohen_kappa_score(merged["human_code"], merged["code"])
print(f"Cohen's kappa (LLM vs. human): {kappa:.3f}")
print(classification_report(merged["human_code"], merged["code"]))

# Error analysis
disagreements = merged[merged["human_code"] != merged["code"]]
print(f"\nDisagreements: {len(disagreements)} / {len(merged)} ({len(disagreements)/len(merged)*100:.1f}%)")
print(disagreements[["segment_id", "original_text", "human_code", "code", "confidence", "reasoning"]])
```

**Iterate on prompt until kappa > 0.70 with human coders.** Document each prompt version and its kappa.

### Step 4: Production Coding with Confidence Calibration

```python
import os
output_root = os.environ.get("OUTPUT_ROOT", "output")
# Run on full corpus
full_results = batch_code_claude(full_corpus_df, codebook_text, examples=best_examples)

# Confidence threshold selection
# Plot calibration curve: for each confidence bin, what fraction are correct?
import numpy as np

bins = np.arange(0, 1.1, 0.1)
full_results["conf_bin"] = pd.cut(full_results["confidence"], bins)
# If gold standard subset is available:
calibration = full_results.merge(gold, on="segment_id", how="left")
calibration["correct"] = calibration["human_code"] == calibration["code"]
cal_table = calibration.dropna(subset=["human_code"]).groupby("conf_bin")["correct"].mean()
print("Calibration table:\n", cal_table)

# Flag low-confidence segments for human review
CONFIDENCE_THRESHOLD = 0.7  # adjust based on calibration
needs_review = full_results[full_results["confidence"] < CONFIDENCE_THRESHOLD]
print(f"Segments for human review: {len(needs_review)} ({len(needs_review)/len(full_results)*100:.1f}%)")
needs_review.to_csv(f"{output_root}/qual/coded-data/llm-needs-review.csv", index=False)
```

### Step 5: Human Validation Protocol

**Stratified sampling for validation:**
- Random sample: 10% of corpus (minimum 100 segments)
- All low-confidence segments (confidence < threshold)
- Oversampled rare codes: minimum 20 segments per code
- Total validation: 10-20% of corpus or 100 segments per code (whichever is larger)

**Adjudication protocol:**
1. Human coder independently codes validation sample (blind to LLM codes)
2. Calculate agreement: kappa, F1 per code
3. For disagreements: a third adjudicator reviews with access to both codes and reasoning
4. Final code = adjudicated decision

### Step 6: Bias and Quality Audit

Check for known LLM coding biases:
- **Positional bias**: Does the LLM favor codes that appear earlier in the codebook?
- **Verbosity bias**: Does the LLM assign more codes to longer segments?
- **Anchoring effects**: Does few-shot example order affect code distribution?
- **Majority class bias**: Does the LLM over-assign frequent codes?

```python
from scipy.stats import chi2_contingency

# Compare LLM vs. human code distributions
human_dist = gold["human_code"].value_counts(normalize=True)
llm_dist = full_results["code"].value_counts(normalize=True)

# Chi-square test for distributional difference
all_codes = set(human_dist.index) | set(llm_dist.index)
observed = [full_results["code"].value_counts().get(c, 0) for c in all_codes]
expected_pct = [human_dist.get(c, 0) for c in all_codes]
expected = [p * len(full_results) for p in expected_pct]
chi2, p_value, dof, _ = chi2_contingency([observed, expected])
print(f"Chi-square test: chi2={chi2:.2f}, p={p_value:.4f}")
if p_value < 0.05:
    print("WARNING: LLM code distribution significantly differs from human distribution")

# Sensitivity analysis: run 3 prompt variants and compare
# (vary codebook order, example selection, instruction phrasing)
```

### Step 7: Reporting Template for LLM-Assisted Coding

Include in the Methods section:

```
LLM-ASSISTED CODING REPORT
===========================
Model: [Claude claude-sonnet-4-20250514 / GPT-4 / other], temperature: [0.0]
Prompt version: [v3, final after 3 iterations]
Codebook: [N codes, M hierarchical levels]

GOLD STANDARD VALIDATION:
- Gold standard size: [N] segments, coded by [M] human coders
- LLM-human agreement: Cohen's kappa = [X.XX], overall accuracy = [X.X%]
- Per-code F1 scores: [table]

PRODUCTION CODING:
- Total segments coded: [N]
- Confidence threshold: [X.X]
- Segments above threshold (auto-accepted): [N] ([X%])
- Segments below threshold (human-reviewed): [N] ([X%])

HUMAN VALIDATION:
- Validation sample: [N] segments ([X%] of corpus)
- Sampling strategy: [random + low-confidence + rare-code oversampling]
- Validation agreement: kappa = [X.XX]
- Adjudication: [N] disagreements resolved by [method]

BIAS CHECKS:
- Positional bias: [detected/not detected]
- Distributional comparison: chi-square = [X.XX], p = [X.XX]
- Prompt sensitivity: [results of 3-variant test]

TRANSPARENCY:
- Human-coded: [X%] of final dataset
- LLM-coded (validated): [X%] of final dataset
- LLM-coded (unvalidated, high-confidence): [X%] of final dataset
- Total cost: [$X.XX] / [X hours human time saved]
- All prompts archived at: [path/URL]

LIMITATIONS:
- [LLM cannot capture embodied/contextual cues available to fieldworkers]
- [Potential for systematic bias in ambiguous cases]
- [Reproducibility depends on model version and API availability]
```

Save to `output/[slug]/qual/coded-data/llm-coding-report-[topic-slug]-[YYYY-MM-DD].md`.

---

## WORKFLOW 7: MIXED — Mixed-Methods Integration

### 7a. Integration Strategy Selection

Identify the design type:
- **Sequential explanatory** (QUANT → qual): Quantitative results identify patterns; qualitative explains mechanisms
- **Sequential exploratory** (qual → QUANT): Qualitative findings generate hypotheses; quantitative tests them
- **Concurrent/convergent**: Both collected simultaneously; results compared for convergence/divergence
- **Embedded**: One method nested within the other (e.g., interviews within an RCT)

### 7b. Case Selection for Qualitative Follow-Up

When qual follows quant:
- **Typical cases**: Observations near the regression line (confirm mechanism)
- **Deviant cases**: Large residuals (discover unmeasured factors)
- **Extreme cases**: Highest/lowest on outcome (understand ceiling/floor)
- **Diverse cases**: Span the range of X and Y (maximize variation)

```r
# Identify cases from regression residuals
mod <- lm(y ~ x1 + x2, data = df)
df$residual <- residuals(mod)
df$fitted <- fitted(mod)
# Deviant cases: |residual| > 2 SD
deviant <- df |> filter(abs(residual) > 2 * sd(residual))
# Typical cases: |residual| < 0.5 SD
typical <- df |> filter(abs(residual) < 0.5 * sd(residual))
```

### 7c. Joint Display / Integration Matrix

Create a joint display table:
| Quantitative Finding | Qualitative Theme | Convergence? | Interpretation |
|---|---|---|---|
| X positively predicts Y (β=0.3) | Participants describe X as enabling Y | Convergent | Mechanism confirmed |
| No effect of Z on Y (β≈0, p=0.8) | Participants rarely mention Z | Convergent | Z is irrelevant |
| W negatively predicts Y (β=−0.2) | Participants describe W as beneficial | Divergent | Possible measurement issue or context dependence |

### 7d. Qual-Informed Variable Operationalization

When qual precedes quant:
1. Extract constructs from interview/ethnographic data
2. Map constructs to survey items or secondary data variables
3. Document the qualitative-to-quantitative translation table:
| Qualitative Construct | Source Quotes | Survey Item / Variable | Measurement Notes |
|---|---|---|---|

### 7e. Code-to-Variable Conversion

Convert qualitative codes to quantitative variables:
- **Binary**: presence/absence of a code → 0/1 variable
- **Ordinal**: intensity of a code (none/low/medium/high) → 0/1/2/3
- **Count**: number of times a code appears per document → continuous variable

```r
# Convert qual codes to binary variables for regression
qual_vars <- coded_data %>%
  distinct(document_id, code) %>%
  mutate(present = 1) %>%
  pivot_wider(names_from = code, values_from = present, values_fill = 0)
```

### 7f. Typology Development

1. Develop types from qualitative analysis (e.g., 3-4 ideal types from thematic analysis)
2. Operationalize each type as a set of quantitative indicators
3. Assign cases to types using cluster analysis, LCA, or rule-based classification
4. Test typology quantitatively (e.g., predict outcomes by type using regression)

### 7g. Reporting Mixed-Methods Results

- Present quantitative results first (if sequential explanatory) or qualitative first (if sequential exploratory)
- Use the joint display table in the Results section
- Discuss convergence/divergence explicitly in Discussion
- Word count: allocate ~40% to dominant method, ~40% to secondary, ~20% to integration

### 7h. Integration Write-Up (Creswell & Plano Clark)

Structure the write-up by integration type:
- **Convergent**: Present quant and qual findings separately, then merge in a joint display
- **Explanatory sequential**: Quant results first, then qual explains mechanisms
- **Exploratory sequential**: Qual themes first, then quant tests generalizability

Save to `output/[slug]/qual/coded-data/mixed-methods-[topic-slug]-[YYYY-MM-DD].md`.

---

## WORKFLOW 8: RELIABILITY — Inter-Coder Reliability Assessment

### Step 1: Select Reliability Sample

- Minimum 10-20% of corpus
- Stratified by code frequency (ensure rare codes are represented)
- If corpus < 100 segments, code the entire corpus with two coders

### Step 2: Train Second Coder

Provide:
- Codebook with definitions, inclusion/exclusion criteria, examples (Workflow 0 output)
- 5-10 practice segments with correct codes and explanations
- Calibration session: code 10 segments together, discuss disagreements

### Step 3: Independent Dual Coding

Both coders independently code the reliability sample. No discussion during coding.

### Step 4: Calculate Reliability Metrics

```r
library(irr)

# Prepare ratings matrix (rows = segments, columns = coders)
ratings <- data.frame(
  coder1 = reliability_data$coder1_code,
  coder2 = reliability_data$coder2_code
)

# Percent agreement
pct_agree <- mean(ratings$coder1 == ratings$coder2)
cat("Percent agreement:", round(pct_agree * 100, 1), "%\n")

# Cohen's kappa (2 coders, nominal data)
kappa_nom <- kappa2(ratings, weight = "unweighted")
cat("Cohen's kappa:", round(kappa_nom$value, 3), "\n")

# Weighted kappa (2 coders, ordinal data)
kappa_ord <- kappa2(ratings, weight = "squared")
cat("Weighted kappa (squared):", round(kappa_ord$value, 3), "\n")

# Scott's pi (alternative to kappa)
# Note: irr does not have Scott's pi directly; calculate manually
# or use agree() for simple percent agreement

# For 3+ coders: Krippendorff's alpha
# Prepare matrix: rows = coders, columns = segments
alpha_matrix <- rbind(
  as.numeric(factor(reliability_data$coder1_code)),
  as.numeric(factor(reliability_data$coder2_code))
  # Add more coders as needed
)
alpha_result <- kripp.alpha(alpha_matrix, method = "nominal")
cat("Krippendorff's alpha:", round(alpha_result$value, 3), "\n")

# Benchmarks
cat("\nBenchmarks:\n")
cat("  > 0.80: Excellent agreement\n")
cat("  0.60-0.79: Substantial agreement\n")
cat("  0.40-0.59: Moderate agreement\n")
cat("  0.21-0.39: Fair agreement\n")
cat("  < 0.20: Poor agreement\n")
```

**Krippendorff's alpha** (preferred for >2 coders, handles missing data, any measurement level):
```r
library(irr)
# kripp.alpha expects a matrix: rows = coders, columns = units
kripp.alpha(coding_matrix, method = "nominal")  # or "ordinal", "interval", "ratio"
# Target: α ≥ 0.667 (tentative), α ≥ 0.800 (reliable)
```

```python
from krippendorff import alpha
alpha(reliability_data, level_of_measurement="nominal")
```

**Fleiss' kappa** (>2 coders, nominal categories):
```r
library(irr)
kappam.fleiss(ratings_matrix)
# Target: κ ≥ 0.61 (substantial), κ ≥ 0.81 (almost perfect)
```

**Gwet's AC1** (robust to marginal distribution skew -- use when prevalence is extreme):
```r
library(irrCAC)
gwet.ac1.raw(ratings_matrix)
```

**Reliability metric selection guide**:
| Scenario | Metric | R function |
|---|---|---|
| 2 coders, nominal | Cohen's kappa | `irr::kappa2()` |
| >2 coders, nominal | Fleiss' kappa | `irr::kappam.fleiss()` |
| Any coders, any level, missing data | Krippendorff's alpha | `irr::kripp.alpha()` |
| Extreme prevalence / skewed margins | Gwet's AC1 | `irrCAC::gwet.ac1.raw()` |
| LLM vs. human (2 coders) | Cohen's kappa + per-code F1 | `irr::kappa2()` + `caret::confusionMatrix()` |

**Code-level reliability breakdown:**

```r
# Per-code kappa (one-vs-all for each code)
codes <- unique(c(ratings$coder1, ratings$coder2))
code_kappas <- sapply(codes, function(code) {
  binary_ratings <- data.frame(
    c1 = as.integer(ratings$coder1 == code),
    c2 = as.integer(ratings$coder2 == code)
  )
  kappa2(binary_ratings)$value
})
code_reliability <- data.frame(code = codes, kappa = round(code_kappas, 3))
code_reliability <- code_reliability[order(-code_reliability$kappa), ]
print(code_reliability)

# Confusion matrix
table(coder1 = ratings$coder1, coder2 = ratings$coder2)
```

### Step 5: Disagreement Resolution

Protocol options:
1. **Consensus coding**: Coders discuss each disagreement and agree on a final code
2. **Third coder**: Independent third coder breaks ties
3. **Negotiated agreement**: Coders explain reasoning; code is assigned based on stronger argument
4. **Majority rule** (3+ coders): Most common code wins

Document: number of disagreements, resolution method for each, and whether codebook was revised as a result.

### Step 6: Reliability Report

```
INTER-CODER RELIABILITY REPORT
===============================
Date: [YYYY-MM-DD]
Corpus: [description]
Reliability sample: [N segments, X% of corpus]
Coders: [N coders, training description]

OVERALL METRICS:
- Percent agreement: [X.X%]
- Cohen's kappa: [X.XX]
- Krippendorff's alpha: [X.XX]
- Assessment: [Excellent / Substantial / Moderate / Fair / Poor]

CODE-LEVEL BREAKDOWN:
| Code | Kappa | N segments | Assessment |
|------|-------|-----------|------------|
| ... | ... | ... | ... |

DISAGREEMENT ANALYSIS:
- Total disagreements: [N] ([X%])
- Most confused code pair: [code A] ↔ [code B] ([N] times)
- Resolution method: [consensus / third coder / negotiated]
- Codebook revisions: [list changes made]

CONCLUSION:
[Acceptable / Needs revision — specific codes requiring attention]
```

Save to `output/[slug]/qual/reliability/reliability-report-[topic-slug]-[YYYY-MM-DD].md`.

---

## CAQDAS Integration

### Export to NVivo
- Export coded data as CSV with columns: Source, Content, Code, Coder
- NVivo auto-import: File > Import > Dataset, map columns to Source/Content/Node

### Export to Atlas.ti
- Export as Excel with columns: Document, Quotation, Code, Comment
- Atlas.ti import: Documents > Import Survey Data

### Export to Dedoose
- Export as Excel descriptor + excerpt table
- Dedoose import: use the Data > Import Descriptors wizard

### Export to MAXQDA
- Export as structured Excel with document groups and code system
- MAXQDA import: Import > Structured Survey Data

**Universal export format:**

```bash
# Generate CAQDAS-ready export
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
echo "document_id,segment_id,text,code,coder,date,memo" > ${OUTPUT_ROOT}/qual/coded-data/caqdas-export.csv
```

---

## Trustworthiness Criteria

### Lincoln & Guba (1985) — Four Criteria

| Criterion | Strategies | Implementation |
|-----------|-----------|----------------|
| **Credibility** (internal validity) | Prolonged engagement, triangulation, peer debriefing, member checking, negative case analysis | Document time in field; use multiple data sources; have colleague review codes; share findings with participants |
| **Transferability** (external validity) | Thick description | Provide detailed context so readers can assess applicability to their setting |
| **Dependability** (reliability) | Audit trail | Document all coding decisions, codebook revisions, and analytic memos |
| **Confirmability** (objectivity) | Reflexivity, audit trail | Researcher positionality statement; chain of evidence from data to findings |

### Tracy (2010) — "Big Tent" Eight Quality Criteria

| Criterion | Description |
|-----------|-------------|
| Worthy topic | Relevant, timely, significant |
| Rich rigor | Sufficient data, appropriate procedures, complexity |
| Sincerity | Self-reflexivity, transparency about methods |
| Credibility | Thick description, triangulation, multivocality |
| Resonance | Transferable findings, evocative writing |
| Significant contribution | Theoretical, practical, or methodological |
| Ethical | Procedural, situational, relational, exiting ethics |
| Meaningful coherence | Methods fit goals; study accomplishes what it claims |

---

## Save Output

After completing any workflow, save the full output using the Write tool.

### Version Collision Avoidance (MANDATORY)

**Before EVERY Write tool call below**, run this Bash block to determine the correct save path. Do NOT hardcode paths from the filename templates — they show naming patterns only.

```bash
# MANDATORY: Replace [values] with actuals before running
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
# BASE pattern: ${OUTPUT_ROOT}/[slug]/qual/scholar-qual-[workflow]-[topic-slug]-[YYYY-MM-DD]
# Split into directory and stem for the gate script:
OUTDIR="$(dirname "${OUTPUT_ROOT}/[slug]/qual/scholar-qual-[workflow]-[topic-slug]-[YYYY-MM-DD]")"
STEM="$(basename "${OUTPUT_ROOT}/[slug]/qual/scholar-qual-[workflow]-[topic-slug]-[YYYY-MM-DD]")"
mkdir -p "$OUTDIR"
bash "${SCHOLAR_SKILL_DIR:-.}/scripts/gates/version-check.sh" "$OUTDIR" "$STEM"
```

**Use the printed `SAVE_PATH` as `file_path` in the Write tool call.** Re-run this block (with the appropriate BASE) for each additional file. The same version suffix must be used for all related output files (.md, .docx, .tex, .pdf).

**Filename convention:**
`scholar-qual-[workflow]-[topic-slug]-[YYYY-MM-DD].md`

- `[workflow]`: codebook, open-coding, axial, selective, thematic, content, llm-coding, mixed, reliability
- `[topic-slug]`: first 4-6 significant words of the topic, lowercased, hyphenated
- `[YYYY-MM-DD]`: today's date

**File header:**
```
# Scholar Qualitative Analysis: [workflow name] — [topic]
*Generated by /scholar-qual on [YYYY-MM-DD]*

---
```

After saving, tell the user:
> Output saved to `[filename]`

**Close Process Log:**

Run the following to finalize the process log:

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
SKILL_NAME="scholar-qual"
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

---

## Quality Checklist

Before finalizing, verify:

- [ ] Data anonymization gate completed before any AI processing (pseudonym mapping, PII removal, verified scan)
- [ ] Pseudonym key file (`pseudonym-key-DO-NOT-SHARE.csv`) stored securely and excluded from git
- [ ] All AI-processed data uses anonymized copies (`ANON_*` files), not originals
- [ ] Codebook has inclusion/exclusion criteria and examples for every code
- [ ] Codes are grounded in data (in-vivo codes preserved where possible)
- [ ] Constant comparison method applied (incidents compared to incidents and codes)
- [ ] Memos document all analytic decisions (theoretical, methodological, analytic)
- [ ] Category saturation assessed and documented
- [ ] Theme definitions include scope and boundaries (not just topic labels)
- [ ] Exemplar quotes include participant identifiers and context
- [ ] Inter-coder reliability calculated with appropriate metric (kappa, alpha)
- [ ] Reliability benchmarks met (kappa > 0.60 minimum, > 0.80 preferred)
- [ ] Disagreement resolution protocol documented
- [ ] LLM-assisted coding (if used) includes gold standard validation, bias audit, and transparency report
- [ ] LLM prompt versions archived with performance metrics
- [ ] Human validation covers minimum 10-20% of LLM-coded corpus
- [ ] Mixed-methods integration uses joint display with explicit integration statements
- [ ] Trustworthiness criteria addressed (Lincoln & Guba or Tracy)
- [ ] All output saved to `output/[slug]/qual/` with correct filename convention
- [ ] No fabricated quotes or codes — all grounded in actual data
- [ ] CAQDAS export format generated if user needs NVivo/Atlas.ti/Dedoose/MAXQDA compatibility
