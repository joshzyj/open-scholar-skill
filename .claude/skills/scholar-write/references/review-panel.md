# Style, Production, Verification, and Review Panel (Steps 3–5b)

This file is loaded on demand by `scholar-write/SKILL.md`. It contains Step 3 (Style and Tone), Step 4 (Produce the Section), Step 4.5 (Post-Draft Citation Verification), Step 4.7 (Table and Figure Placement Audit), Step 5 (Multi-Agent Internal Review Panel), and Step 5b (Verification Gate).

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

## Step 4.6: Structured Reflection Diagnostics (MANDATORY before Review Panel)

**Purpose**: Before sending the draft to the 5-agent review panel, compute concrete diagnostic signals. These diagnostics (a) catch mechanical issues early (saving reviewer bandwidth for substantive feedback), and (b) provide structured context that makes reviewer evaluations more targeted.

### 4.6a: Compute Diagnostics

Run the following checks on the draft produced in Step 4 and compile a **DIAGNOSTIC REPORT**:

**1. Word Count vs. Target**
```bash
# Count words in the draft text (exclude YAML frontmatter and markdown comments)
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
DRAFT_FILE="[path to draft file]"
WORD_COUNT=$(sed '/^---$/,/^---$/d; /^<!--/,/-->$/d' "$DRAFT_FILE" 2>/dev/null | wc -w | tr -d ' ')
echo "Word count: $WORD_COUNT"
```
Compare against the journal-specific target from Step 1. Compute:
- `RATIO = actual / midpoint_of_target_range`
- Flag: `UNDER` if ratio < 0.6 (outline, not prose), `SHORT` if 0.6-0.85, `ON TARGET` if 0.85-1.15, `OVER` if > 1.15

**2. Citation Density**
Count in-text citations and `[CITATION NEEDED]` markers:
- `CITATION_COUNT`: Number of `(Author Year)` patterns
- `NEEDED_COUNT`: Number of `[CITATION NEEDED]` markers
- `PARAGRAPHS`: Number of paragraphs (double newline separated)
- `DENSITY = CITATION_COUNT / PARAGRAPHS`
- Flag: `SPARSE` if density < 1.0 for Theory/Lit Review, < 0.5 for other sections; `HEAVY` if > 4.0; `OK` otherwise

**3. Methods-Results Alignment** (only for Results sections or full papers)
If the draft contains a Results section AND a Methods/Design section or prior-phase design blueprint:
- List each hypothesis (H1, H2, H3...) from the design/theory
- Check whether each hypothesis is explicitly addressed in the Results text
- Flag any hypothesis that appears in theory but has no corresponding result as `UNTESTED`
- Flag any result that doesn't connect back to a hypothesis as `ORPHAN RESULT`

**4. Hedging Calibration**
Scan for causal language ("causes," "leads to," "produces," "results in") and check against the study design:
- If design is observational/cross-sectional: causal language should be absent; flag violations as `CAUSAL OVERREACH`
- If design is experimental/quasi-experimental: causal language is appropriate
- Count hedge phrases ("is associated with," "suggests," "may") vs. causal phrases

**5. Structural Balance**
For full papers or multi-paragraph sections:
- Compute word count per subsection or per major paragraph block
- Flag any subsection that is < 30% or > 200% of the average as `IMBALANCED`

### 4.6b: Compile Diagnostic Report

```
STRUCTURED REFLECTION DIAGNOSTICS — [Section] — [Journal]
═══════════════════════════════════════════════════════════

| Diagnostic | Value | Target | Flag |
|------------|-------|--------|------|
| Word count | [N] | [range] | [UNDER/SHORT/ON TARGET/OVER] |
| Citation density | [N]/para | [range] | [SPARSE/OK/HEAVY] |
| [CITATION NEEDED] markers | [N] | 0 ideal | [OK/HIGH] |
| Causal language instances | [N] | [0 if observational] | [OK/OVERREACH] |
| Hedge phrases | [N] | — | — |
| H-to-Result coverage | [N]/[N] | 100% | [COMPLETE/GAPS: list] |
| Structural balance | [min-max ratio] | — | [OK/IMBALANCED: which] |

ACTION ITEMS (fix before review panel):
1. [e.g., "Word count 580/1200 — expand Theory paragraphs 2 and 4"]
2. [e.g., "H2 not addressed in Results — add paragraph or note as untested"]
3. [e.g., "3 instances of causal language in cross-sectional study — replace with associational phrasing"]
```

### 4.6c: Self-Revision Pass (if action items exist)

If the diagnostic report contains any `UNDER`, `CAUSAL OVERREACH`, or `GAPS` flags:
1. Apply targeted fixes to the draft (expand thin sections, replace causal language, add missing hypothesis coverage)
2. Re-run the affected diagnostics to confirm improvement
3. Note changes in the diagnostic report: `SELF-REVISION: [N] items fixed`

If all diagnostics are clean (`ON TARGET`, `OK`, `COMPLETE`), skip self-revision and proceed directly to Step 5.

### 4.6d: Pass Diagnostics to Review Panel

Include the DIAGNOSTIC REPORT in the prompt for each reviewer agent in Step 5. This gives reviewers structured context so they can focus on substantive issues rather than mechanical ones.

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
>    - Discussion: Does interpretation go beyond restating results? Is generalizability assessed? Are preemptive objections addressed?
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
