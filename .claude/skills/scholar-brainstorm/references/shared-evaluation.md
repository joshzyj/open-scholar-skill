# Shared Evaluation — Steps 5-10

These steps are shared by all three modes (DATA, MATERIALS, PAPER). They run after mode-specific steps complete.

---

### Step 5: Quick Literature Scan

For each of the 15-20 candidate RQs, run a **lightweight literature scan** to assess novelty.

**This is a faster, targeted version of the scholar-idea Step 3 protocol — designed for scanning many RQs efficiently rather than deep-diving a few.**

#### 5a. Tier 1 — Local Library Batch Search (REQUIRED FIRST)

Load the unified reference manager layer and run keyword searches for each candidate RQ. **Run as a SINGLE Bash command:**

```bash
# ── Load reference manager + run local library searches in ONE call ──
SKILL_DIR="${SCHOLAR_SKILL_DIR:-.}"
[ -f "${SKILL_DIR}/.env" ] && . "${SKILL_DIR}/.env" 2>/dev/null || true
[ -f "$HOME/.claude/.env" ] && . "$HOME/.claude/.env" 2>/dev/null || true
SKILL_DIR="${SCHOLAR_SKILL_DIR:-.}"

# Source all backend functions
eval "$(cat "$SKILL_DIR/.claude/skills/scholar-citation/references/refmanager-backends.md" | sed -n '/^```bash/,/^```/p' | sed '1d;$d')" 2>/dev/null

# ── Run local keyword searches for top candidate RQs ──
echo "=== LOCAL LIBRARY: RQ1 keywords ==="
scholar_search "[RQ1_KEYWORDS]" 15 keyword | scholar_format_citations
echo ""
echo "=== LOCAL LIBRARY: RQ2 keywords ==="
scholar_search "[RQ2_KEYWORDS]" 15 keyword | scholar_format_citations
# ... repeat for each candidate RQ (use 2-3 keywords per RQ)
```

#### 5b. Tier 2 — External API Batch Search

For any RQ with <3 local hits, run external API searches. **Run in a SINGLE Bash block:**

```bash
SKILL_DIR="${SCHOLAR_SKILL_DIR:-.}"
[ -f "${SKILL_DIR}/.env" ] && . "${SKILL_DIR}/.env" 2>/dev/null || true
[ -f "$HOME/.claude/.env" ] && . "$HOME/.claude/.env" 2>/dev/null || true
SKILL_DIR="${SCHOLAR_SKILL_DIR:-.}"

eval "$(cat "$SKILL_DIR/.claude/skills/scholar-citation/references/refmanager-backends.md" | sed -n '/^```bash/,/^```/p' | sed '1d;$d')" 2>/dev/null

# ── External API searches for under-covered RQs ──
echo "=== EXTERNAL: RQ[N] ==="
scholar_search_crossref "[KEYWORDS]" 10
scholar_search_s2 "[KEYWORDS]" 10
# ... repeat for RQs with insufficient local coverage
```

#### 5c. Tier 3 — WebSearch (gap-filling only)

Only for RQs with <3 total hits after Tiers 1-2. Run 1-2 WebSearch queries per gap.

#### 5d. Novelty Assessment Per RQ

For each of the 15-20 candidates, assign a **novelty threat rating** using the same criteria as scholar-idea:

- **SATURATED**: ≥3 papers answer this exact RQ with same population and method → drop or substantially differentiate
- **INCREMENTAL**: 1-2 papers address the RQ but with different population, time, or weaker method → viable with clear contribution statement
- **GAP**: Papers address parts but not the full X→M→Y chain → strong potential
- **UNEXPLORED**: <1 paper addresses any component → high novelty, verify feasibility

### Step 6: Shortlist to Top 10

From the 15-20 candidates, select the **Top 10** using **mode-conditional scoring weights**.

**DATA mode** (6 criteria):

| Criterion | Weight | Description |
|-----------|--------|-------------|
| Novelty | 20% | Based on Step 5 novelty threat rating (UNEXPLORED/GAP > INCREMENTAL > SATURATED) |
| Data readiness | 15% | All key variables available and well-measured in this dataset |
| Theoretical significance | 20% | Speaks to an active debate, fills a named gap, or tests a mechanism |
| Identification strength | 15% | Data supports credible causal claim or strong descriptive contribution |
| Publication potential | 10% | Matches scope/norms of target journals (ASR, AJS, Demography, Science Advances, NHB, NCS) |
| **Empirical signal** | **20%** | From Step 4b signal table |

**Empirical signal scoring** (DATA mode): STRONG=5, MECHANISM PLAUSIBLE=4, MODERATE=3, MODERATION DETECTED=3, UNTESTABLE=2, WEAK=1, NULL=0.

**MATERIALS and PAPER modes** (5 criteria):

| Criterion | Weight | Description |
|-----------|--------|-------------|
| Novelty | 25% | Based on Step 5 novelty threat rating |
| Data readiness | 25% | All key variables available and well-measured in this dataset |
| Theoretical significance | 20% | Speaks to an active debate, fills a named gap, or tests a mechanism |
| Identification strength | 15% | Data supports credible causal claim or strong descriptive contribution |
| Publication potential | 15% | Matches scope/norms of target journals |

**Drop any candidate that is:**
- SATURATED AND data readiness LOW
- Missing the key outcome variable (Y)
- Tautological or trivial

**Present the shortlist:**

For **DATA mode**:
```
===== TOP 10 SHORTLIST (DATA mode — 6-criterion scoring) =====

| Rank | RQ | Novelty | Data Ready | Theory | ID Strength | Pub Potential | Signal | Score |
|------|----|---------|------------|--------|-------------|---------------|--------|-------|
| 1 | [RQ text] | [GAP] | [HIGH] | [HIGH] | [MED] | [HIGH] | [STRONG] | [weighted] |
| 2 | ... | ... | ... | ... | ... | ... | ... | ... |
...
```

For **MATERIALS/PAPER mode**:
```
===== TOP 10 SHORTLIST (MATERIALS mode — 5-criterion scoring) =====

| Rank | RQ | Novelty | Data Ready | Theory | ID Strength | Pub Potential | Score |
|------|----|---------|------------|--------|-------------|---------------|-------|
| 1 | [RQ text] | [GAP] | [HIGH] | [HIGH] | [MED] | [HIGH] | [weighted] |
| 2 | ... | ... | ... | ... | ... | ... | ... |
...
```

For each of the Top 10, expand with:
- **Full RQ text** (using formula from Step 4)
- **Variables**: X, Y, M, W, C (specific variable names from the data)
- **Theoretical puzzle** (2-3 sentences: what we don't know and why it matters)
- **Closest prior work** (1-2 citations from Step 5 with verification labels)
- **What's new** (1 sentence: what this RQ adds beyond prior work)
- **Identification strategy sketch** (1-2 sentences: how you'd estimate this)
- **Empirical signal** (DATA mode only): [STRONG/MODERATE/WEAK/NULL/UNTESTABLE] — effect size and p from Step 4b
- **Target journal(s)** (1-2 journals this best fits)

### Step 7: Multi-Agent Evaluation Panel

Submit the Top 10 to a panel of **5 specialized evaluator agents** — the same architecture as scholar-idea Step 8.

#### 7a. Spawn 5 Parallel Evaluator Agents

Use the Agent tool to run all 5 evaluators **in parallel** (five simultaneous Agent tool calls). Pass each agent the same input package:

**Input package** (include in every agent prompt):
```
OPERATING MODE: [DATA / MATERIALS / PAPER]
DATASET SUMMARY: [material summary from Step 1]
VARIABLE INVENTORY: [star variables + classification from Step 2]
TOP 10 RESEARCH QUESTIONS: [full RQ details from Step 6]
LITERATURE SCAN RESULTS: [novelty ratings + key citations from Step 5]
EMPIRICAL SIGNAL TABLE: [full signal table from Step 4b, or "N/A — MATERIALS/PAPER mode"]
TARGET JOURNAL: [journal name or "not yet determined"]
```

---

**Agent 1 — Theorist**

Spawn a `general-purpose` agent with:

> "You are a senior sociological theorist evaluating data-driven research questions. You are given a dataset's variable inventory and 10 candidate research questions derived from it. For each RQ, evaluate:
>
> 1. **Theoretical contribution** (Strong / Adequate / Weak): Does this adjudicate competing explanations, bridge disconnected literatures, or identify a new mechanism? Or is it a fishing expedition dressed up as theory?
> 2. **Mechanism specificity** (Strong / Adequate / Weak): Is the causal or explanatory mechanism named, explicit, and traceable step-by-step? Or is it implied, vague, or conflated with the outcome?
> 3. **Theory-data alignment** (Strong / Adequate / Weak): Does the RQ emerge naturally from a theoretical puzzle, or does it feel reverse-engineered from available variables? Would a reader believe this RQ was motivated by theory, not by data availability?
>
> For each RQ, provide:
> - Ratings on the 3 dimensions above
> - 2-3 specific comments explaining your ratings
> - 1 concrete suggestion to strengthen theoretical grounding (e.g., 'Frame as a test of [theory]' or 'The real puzzle is [X], not [Y]')
>
> End with a **rank ordering** of the 10 RQs from strongest to weakest on theoretical grounds. Select your Top 5.
>
> [INPUT PACKAGE]"

---

**Agent 2 — Methodologist**

Spawn a `general-purpose` agent with:

> "You are a quantitative methodologist evaluating data-driven research questions. You are given a dataset's variable inventory and 10 candidate research questions. For each RQ, evaluate:
>
> 1. **Identification strength** (Strong / Adequate / Weak): Given the dataset structure (cross-section vs. panel, available instruments, natural experiments), what is the strongest plausible identification strategy? Does the RQ overstate causal claims relative to what the data supports?
> 2. **Measurement validity** (Strong / Adequate / Weak): Are the proposed operationalizations valid, or do they rely on weak proxies? Flag any construct-measurement gaps.
> 3. **Statistical power** (Strong / Adequate / Weak): Given the sample size and expected effect sizes, is the study adequately powered? Are there enough observations for the proposed subgroup analyses?
> 4. **Empirical plausibility** (Strong / Adequate / Weak / N/A): If empirical signal test results are provided (DATA mode), evaluate whether the observed bivariate associations are consistent with the proposed theoretical model. Flag any suspiciously strong signals (possible confounding) or unexpected nulls.
>
> For each RQ, provide:
> - Ratings on the 3-4 dimensions above (4th only if DATA mode)
> - 2-3 specific comments naming exact variables and methods
> - 1 concrete suggestion to improve identification or measurement
>
> End with a **rank ordering** of the 10 RQs from strongest to weakest methodologically. Select your Top 5.
>
> [INPUT PACKAGE]"

---

**Agent 3 — Domain Expert**

Spawn a `general-purpose` agent with:

> "You are a specialist in [infer domain from the data: e.g., stratification, demography, health, migration, organizations, sociolinguistics] evaluating data-driven research questions. For each of the 10 RQs, evaluate:
>
> 1. **Literature gap accuracy** (Strong / Adequate / Weak): Does the claimed gap actually exist? Has the literature scan missed key papers? Name any missing citations.
> 2. **Subfield positioning** (Strong / Adequate / Weak): Where does this question sit in the field's current debates? Is it timely?
> 3. **Dataset-question fit** (Strong / Adequate / Weak): Is this dataset the RIGHT data to answer this question, or is there a better-known dataset that everyone in the field already uses? Would reviewers ask 'why not use [other dataset]?'
>
> For each RQ, provide:
> - Ratings on the 3 dimensions above
> - 2-3 specific comments citing papers from the field
> - 1 concrete suggestion to sharpen the contribution
>
> End with a **rank ordering** of the 10 RQs from strongest to weakest on domain-specific grounds. Select your Top 5.
>
> [INPUT PACKAGE]"

---

**Agent 4 — Journal Editor**

Spawn a `general-purpose` agent with:

> "You are a former associate editor at a top social science journal (ASR, AJS, Demography, or Science Advances) evaluating data-driven research questions for publication potential. For each of the 10 RQs, evaluate:
>
> 1. **Publication fit** (Strong / Adequate / Weak): Does this match the scope, audience, and norms of the target journal? Which 2-3 journals would be the best fit?
> 2. **Contribution framing** (Strong / Adequate / Weak): Can you articulate the contribution in one sentence? Would it survive the 'so what?' test? Is there a risk this reads as a 'data mining exercise' rather than a motivated study?
> 3. **Broad appeal** (Strong / Adequate / Weak): Will this interest readers beyond the immediate subfield?
>
> For each RQ, provide:
> - Ratings on the 3 dimensions above
> - 2-3 specific editorial comments
> - 1 concrete suggestion to improve publishability
> - Suggested target journal(s)
>
> End with a **rank ordering** of the 10 RQs from most to least publishable. Select your Top 5.
>
> [INPUT PACKAGE]"

---

**Agent 5 — Devil's Advocate**

Spawn a `general-purpose` agent with:

> "You are a skeptical, rigorous critic stress-testing data-driven research questions. Your special focus is detecting data-mining, HARKing risk, and post-hoc rationalization — common pitfalls when RQs are generated from existing data rather than from theory. For each of the 10 RQs, evaluate:
>
> 1. **HARKing / fishing risk**: Does this RQ feel genuinely motivated by theory, or does it feel reverse-engineered from what the data happens to contain? Would a pre-analysis plan have predicted this question?
> 2. **Null result risk**: What is the probability the main hypothesis is wrong or undetectably small? Is a null finding still publishable?
> 3. **Competitor threat**: Could someone with better data or a natural experiment scoop this? Is there a working paper that already answers it?
> 4. **Fatal assumptions**: What unstated assumptions does this RQ rely on? Which are most likely violated?
> 5. **Empirical signal interpretation** (DATA mode only): If empirical signal tests are provided, evaluate: Could the observed signal be spurious (confounding, selection, measurement error)? Does a STRONG bivariate signal actually increase HARKing risk? Does a NULL signal indicate a genuinely uninteresting question or just underpowered bivariate test?
>
> For each RQ, provide:
> - The single most serious threat
> - 1-2 additional risks
> - 1 concrete mitigation strategy
> - A **viability rating**: VIABLE / AT RISK / FATAL FLAW
>
> Be constructive but honest. Flag any RQ that is essentially a fishing expedition.
>
> [INPUT PACKAGE]"

---

#### 7b. Synthesize Into Consensus Scorecard

After all 5 agents return, produce a **Consensus Scorecard**:

```
===== MULTI-AGENT EVALUATION PANEL =====

Panel: Theorist (A1) | Methodologist (A2) | Domain Expert (A3) | Journal Editor (A4) | Devil's Advocate (A5)

===== CONSENSUS SCORECARD =====

| Dimension | A1 | A2 | A3 | A4 | A5 | Consensus |
|-----------|----|----|----|----|----|-----------|
| RQ1: [short label] |
| Theoretical contribution | [S/A/W] | — | — | — | — | [S/A/W] |
| Theory-data alignment | [S/A/W] | — | — | — | — | [S/A/W] |
| Identification strength | — | [S/A/W] | — | — | — | [S/A/W] |
| Measurement validity | — | [S/A/W] | — | — | — | [S/A/W] |
| Empirical plausibility | — | [S/A/W/N/A] | — | — | — | [S/A/W/N/A] |
| Literature gap accuracy | — | — | [S/A/W] | — | — | [S/A/W] |
| Dataset-question fit | — | — | [S/A/W] | — | — | [S/A/W] |
| Publication fit | — | — | — | [S/A/W] | — | [S/A/W] |
| HARKing/fishing risk | — | — | — | — | [L/M/H] | [L/M/H] |
| Devil's advocate viability | — | — | — | — | [V/AR/FF] | [V/AR/FF] |
| **Overall** | **Rank** | **Rank** | **Rank** | **Rank** | **[V/AR/FF]** | **[verdict]** |
| (repeat for RQ2–RQ10) |

Legend: S = Strong, A = Adequate, W = Weak, V = Viable, AR = At Risk, FF = Fatal Flaw
★★ = raised by 2+ agents (cross-agent agreement — high confidence)

===== CROSS-AGENT AGREEMENT =====

Issues flagged by 2+ agents (★★ — highest priority):
1. [Issue] — raised by [A1, A3] — [summary]
2. [Issue] — raised by [A2, A5] — [summary]
...

===== AGENT TOP-5 COMPARISON =====

| Agent | #1 | #2 | #3 | #4 | #5 |
|-------|----|----|----|----|----|
| A1 (Theorist) | RQ? | RQ? | RQ? | RQ? | RQ? |
| A2 (Methodologist) | RQ? | RQ? | RQ? | RQ? | RQ? |
| A3 (Domain Expert) | RQ? | RQ? | RQ? | RQ? | RQ? |
| A4 (Journal Editor) | RQ? | RQ? | RQ? | RQ? | RQ? |
| **Consensus ranking** | **RQ?** | **RQ?** | **RQ?** | **RQ?** | **RQ?** |
```

**Consensus rules:**
- RQs appearing in 3+ agents' Top 5 → strong consensus picks
- RQs appearing in only 1 agent's Top 5 → niche appeal; note which dimension they excel on
- Any RQ rated `FATAL FLAW` by A5 → automatically drop from final ranking
- Any RQ flagged `HIGH` HARKing risk by A5 AND `Weak` theory-data alignment by A1 → drop or substantially reframe

#### 7c. Refine Top 10 Based on Panel Feedback

For each RQ still in the running:

1. **Apply all ★★ suggestions** (cross-agent agreement items)
2. **Apply Devil's Advocate mitigations** — address top threats
3. **Revise the RQ text** (mark changes as `[REFINED: reason]`)
4. **Update hypotheses and identification strategies** if refinement changed the framing
5. **Re-rank** based on post-refinement quality

Present **original** and **refined** versions side-by-side:

```
RQ1 (original): [original text]
RQ1 (refined):  [refined text]  [REFINED: reframed as scope-condition test per A1 + added fixed-effects per A2]
```

### Step 8: Final Ranked Top 10

Produce the definitive **Final Top 10** ranking, incorporating all panel feedback and refinements.

For each RQ (in rank order):

```
===== FINAL TOP 10 RESEARCH QUESTIONS =====

━━━ #1 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

RQ: [refined RQ text]

Variables: X=[name], Y=[name], M=[name], W=[name]
Panel consensus: [Strong/Mixed/Weak] — [which agents ranked it highly]
Novelty: [UNEXPLORED/GAP/INCREMENTAL]
Data readiness: [HIGH/MEDIUM]
Empirical signal: [STRONG/MODERATE/WEAK/NULL/UNTESTABLE/N/A] — [effect size + p from Step 4b, or "MATERIALS mode"]

Theoretical puzzle: [2-3 sentences]
What's new: [1 sentence]
Identification strategy: [1-2 sentences]
Key risk: [1 sentence from Devil's Advocate + mitigation]
Target journal(s): [1-2 journals]

Verdict: PROCEED / REVISE [specify what]

Next step: /scholar-idea [this RQ] — for deep development
         /scholar-lit-review [this RQ] — for systematic review
         /scholar-design [this RQ + dataset] — for methods planning

(repeat for #2 through #10)
```

### Step 9: Research Program Overview

After the Top 10, provide a **research program overview** — a bird's-eye view of how these 10 RQs relate to each other:

**9a. Thematic map:**
- Which RQs cluster into the same research program? (Could become a multi-paper project)
- Which RQs are independent? (Could be developed in parallel by different team members)
- Which RQs build on each other? (RQ3 requires answering RQ1 first)

**9b. Quick-win vs. deep-investment:**

| Category | RQs | Rationale |
|----------|-----|-----------|
| **Quick wins** (3-6 months) | [RQ#s] | Data ready, straightforward identification, clear contribution |
| **Medium projects** (6-12 months) | [RQ#s] | Needs some data work or methodological development |
| **Deep investments** (12+ months) | [RQ#s] | Requires restricted data, novel methods, or extensive theory development |

**9c. Collaboration opportunities:**
- Which RQs could benefit from a methodologist collaborator?
- Which need domain expertise the user may not have?
- Which are suitable for student projects / RA-led papers?

### Step 10: Save Output (4 formats)

After displaying the full output to the user, save the complete brainstorm report in **4 formats**: `.md`, `.docx`, `.tex`, `.pdf`.

**10a. Version check FIRST** (REQUIRED):

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
mkdir -p "${OUTPUT_ROOT}"
# BASE pattern: ${OUTPUT_ROOT}/scholar-brainstorm-[topic-slug]-$(date +%Y-%m-%d)
OUTDIR="$(dirname "${OUTPUT_ROOT}/scholar-brainstorm-[topic-slug]-$(date +%Y-%m-%d)")"
STEM="$(basename "${OUTPUT_ROOT}/scholar-brainstorm-[topic-slug]-$(date +%Y-%m-%d)")"
mkdir -p "$OUTDIR"
bash "${SCHOLAR_SKILL_DIR:-.}/scripts/gates/version-check.sh" "$OUTDIR" "$STEM"
```

**10b. Write the FULL report** (Markdown) using the Write tool with the printed `SAVE_PATH` as `file_path`.

**File header to prepend:**
```
# Scholar Brainstorm: [dataset/material name]
*Generated by /scholar-brainstorm on [YYYY-MM-DD]*
*Operating mode: [DATA / MATERIALS / PAPER]*

---
```

Then write the full output (all 14 sections from the Output Format list) exactly as displayed on screen.

**10b-2. Write the EXECUTIVE SUMMARY** — a concise, shareable version containing only the top RQs, panel evaluation, and recommendation narrative.

**Version check for summary file:**

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
SUMBASE="${OUTPUT_ROOT}/scholar-brainstorm-[topic-slug]-summary-$(date +%Y-%m-%d)"

if [ -f "${SUMBASE}.md" ]; then
  V=2
  while [ -f "${SUMBASE}-v${V}.md" ]; do V=$((V+1)); done
  SUMBASE="${SUMBASE}-v${V}"
fi

echo "SUMMARY_PATH=${SUMBASE}.md"
echo "SUMBASE=${SUMBASE}"
```

Write the summary file using the Write tool. **Include ONLY these sections:**

```markdown
# Research Question Brainstorm — Executive Summary
## [dataset/material name]
*Generated by /scholar-brainstorm on [YYYY-MM-DD]*
*Operating mode: [DATA / MATERIALS / PAPER]*

---

## Dataset Overview

[2-3 sentence summary: dataset name, N, population, temporal coverage, key strengths]

## Final Top 10 Research Questions

[For each RQ in rank order, include the FULL block from Step 8:]

### #1: [short RQ label]

**RQ:** [refined RQ text]

**Variables:** X=[name], Y=[name], M=[name], W=[name]
**Panel consensus:** [Strong/Mixed/Weak] — [which agents ranked it highly]
**Novelty:** [UNEXPLORED/GAP/INCREMENTAL]
**Data readiness:** [HIGH/MEDIUM]
**Empirical signal:** [STRONG/MODERATE/WEAK/NULL/UNTESTABLE/N/A] — [effect + p]

**Theoretical puzzle:** [2-3 sentences]
**What's new:** [1 sentence]
**Identification strategy:** [1-2 sentences]
**Key risk:** [1 sentence + mitigation]
**Target journal(s):** [1-2 journals]

**Verdict:** PROCEED / REVISE [specify what]

[repeat for #2 through #10]

---

## Multi-Agent Evaluation Summary

[Consensus scorecard table from Step 7b — the main table only, not individual agent reports]
[Cross-agent agreement (★★ items)]
[Agent Top-5 comparison table]

---

## Recommendation Narrative

[Write a 300-500 word narrative synthesizing the brainstorm results. Cover:]
- Which 2-3 RQs are the strongest overall and why
- What makes this dataset particularly well-suited (or limited) for these questions
- Key risks across the portfolio (common threats from Devil's Advocate)
- Suggested sequencing: what to pursue first, what needs more groundwork
- Any cross-cutting themes that could define a research program

---

## Research Program Overview

[Thematic map, quick-win vs. deep-investment table, and collaboration opportunities from Step 9]

---

## Next Steps

For any RQ above:
- `/scholar-idea [RQ text]` — deep development with 5-agent evaluation
- `/scholar-lit-review [RQ text]` — systematic literature review
- `/scholar-design [RQ text + dataset]` — research design + power analysis
```

**10c. Convert BOTH files to .docx, .tex, .pdf** via pandoc (run all conversions in a single Bash block):

```bash
# ── Re-derive BASE and SUMBASE (shell vars don't persist) ──
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
BASE="${OUTPUT_ROOT}/scholar-brainstorm-[topic-slug]-$(date +%Y-%m-%d)"
SUMBASE="${OUTPUT_ROOT}/scholar-brainstorm-[topic-slug]-summary-$(date +%Y-%m-%d)"
# If versioned, find the most recent matching files
if [ ! -f "${BASE}.md" ]; then
  BASE=$(ls -t "${OUTPUT_ROOT}"/scholar-brainstorm-[topic-slug]-$(date +%Y-%m-%d)*.md 2>/dev/null | grep -v summary | head -1 | sed 's/\.md$//')
fi
if [ ! -f "${SUMBASE}.md" ]; then
  SUMBASE=$(ls -t "${OUTPUT_ROOT}"/scholar-brainstorm-[topic-slug]-summary-$(date +%Y-%m-%d)*.md 2>/dev/null | head -1 | sed 's/\.md$//')
fi

# ── Convert full report ──
for MD_FILE in "${BASE}.md" "${SUMBASE}.md"; do
  OUTBASE="${MD_FILE%.md}"
  LABEL=$(basename "$OUTBASE")
  echo ""
  echo "=== Converting: $LABEL ==="

  echo "  → .docx"
  pandoc "$MD_FILE" -o "${OUTBASE}.docx" \
    --from markdown \
    2>&1 && echo "  OK: ${OUTBASE}.docx" || echo "  WARN: docx failed"

  echo "  → .tex"
  pandoc "$MD_FILE" -o "${OUTBASE}.tex" \
    --from markdown \
    --standalone \
    -V geometry:margin=1in \
    -V fontsize=12pt \
    2>&1 && echo "  OK: ${OUTBASE}.tex" || echo "  WARN: tex failed"

  echo "  → .pdf"
  pandoc "$MD_FILE" -o "${OUTBASE}.pdf" \
    --from markdown \
    --pdf-engine=xelatex \
    -V geometry:margin=1in \
    -V fontsize=12pt \
    2>&1 && echo "  OK: ${OUTBASE}.pdf" || echo "  WARN: pdf failed"
done

echo ""
echo "=== All output files ==="
ls -lh "${BASE}".* "${SUMBASE}".* 2>/dev/null
```

**10d. Verify outputs exist:**

Check that at least `.md` and `.docx` were created. If `.pdf` fails (xelatex not installed), note it but do not block.

**10e. Close Process Log:**

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
SKILL_NAME="scholar-brainstorm"
LOG_DATE=$(date +%Y-%m-%d)
LOG_FILE="${OUTPUT_ROOT}/logs/process-log-${SKILL_NAME}-${LOG_DATE}.md"
if [ ! -f "$LOG_FILE" ]; then
  LOG_FILE=$(ls -t "${OUTPUT_ROOT}"/logs/process-log-${SKILL_NAME}-${LOG_DATE}*.md 2>/dev/null | head -1)
fi
cat >> "$LOG_FILE" << LOGFOOTER

## Output Files
[list each output file path as a bullet — .md, .docx, .tex, .pdf]

## Summary
- **Steps completed**: [N completed]/[N total]
- **Files produced**: [count — up to 4 formats]
- **Errors**: [count, or 0]
- **Time finished**: $(date +%H:%M:%S)
LOGFOOTER
echo "Process log saved to $LOG_FILE"
```

After saving, tell the user:
> Output saved to:
> - **Full report:** `[BASE].md` / `.docx` / `.tex` / `.pdf`
> - **Executive summary:** `[SUMBASE].md` / `.docx` / `.tex` / `.pdf`
