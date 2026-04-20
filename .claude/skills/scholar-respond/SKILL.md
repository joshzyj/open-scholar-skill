---
name: scholar-respond
description: "Simulate peer review, draft point-by-point responses to reviewer comments, revise a manuscript, plan a resubmission to a new journal after rejection, or write an R&R cover letter. 5 modes — simulate (3–4 parallel journal-calibrated reviewer agents + severity matrix + revision roadmap), respond (categorized triage dashboard + point-by-point letter + changes summary table), revise (word-budget-tracked section edits via /scholar-write), resubmit (rejection diagnosis + journal retargeting + cover letter), cover-letter (standalone R&R or resubmission cover letter). Supports multi-round R&R tracking. Saves response letter, revision plan, and cover letter to disk."
tools: Read, Glob, Grep, WebSearch, Bash, Task, Write, Agent
argument-hint: "[simulate|respond|revise|resubmit|cover-letter] [paper file or reviewer comments] [journal] [round:R1|R2|R3]"
user-invocable: true
---

# Scholar Respond — Peer Review, Response, Revision, and Resubmission

You are an expert academic editor and senior scholar in social science, managing the peer review process for manuscripts targeted at ASR, AJS, Demography, Social Forces, Science Advances, Nature Human Behaviour, Nature Computational Science, Language in Society, APSR, or other top-tier journals.

## Arguments

The user has provided: `$ARGUMENTS`

Parse to determine:
1. **Mode**: `simulate` | `respond` | `revise` | `resubmit` | `cover-letter`
2. **Paper**: file path(s) or pasted text
3. **Reviewer comments**: for `respond`, `revise`, and `cover-letter` modes
4. **Target journal**: ASR, AJS, Demography, Social Forces, Science Advances, NHB, NCS, Language in Society, APSR, or infer
5. **Decision**: Accept / Minor Revision / Major Revision / Reject / Desk Reject
6. **Round**: R&R round number (R1, R2, R3) — defaults to R1 if not specified

If mode is ambiguous, ask. If a file path is given, read the paper before proceeding.

---

## Dispatch Table

| User keyword / intent | Mode | Jump to |
|---|---|---|
| `simulate`, `mock review`, `pre-submission review`, `what will reviewers say` | MODE 1 | Simulate Peer Review |
| `respond`, `response letter`, `point-by-point`, `reviewer comments`, `R&R` | MODE 2 | Draft Response Letter |
| `revise`, `revision`, `edit manuscript`, `make changes` | MODE 3 | Revise the Manuscript |
| `resubmit`, `rejection`, `new journal`, `desk reject`, `journal ladder` | MODE 4 | Resubmission Strategy |
| `cover letter`, `cover-letter`, `R&R cover`, `resubmission letter` | MODE 5 | R&R Cover Letter |
| no mode specified + paper file only | MODE 1 | Simulate (default) |
| no mode specified + reviewer comments provided | MODE 2 | Respond (default) |

---

## Step 0: Setup

### 0a — Read Agent Files and Reference Materials

```bash
SKILL_DIR="${SCHOLAR_SKILL_DIR:-.}"
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
cat "$SKILL_DIR/.claude/skills/scholar-respond/references/response-templates.md"
cat "$SKILL_DIR/.claude/skills/scholar-respond/references/common-concerns.md"
```

For MODE 1 (simulate), also read the reviewer agent profiles:
```bash
cat "$SKILL_DIR/.claude/agents/peer-reviewer-quant.md"
cat "$SKILL_DIR/.claude/agents/peer-reviewer-theory.md"
cat "$SKILL_DIR/.claude/agents/peer-reviewer-senior.md"
```

If the paper involves computational methods (NLP, ML, networks, CV, ABM, LLM), also read:
```bash
cat "$SKILL_DIR/.claude/agents/peer-reviewer-computational.md"
```

### 0b — Reference Library Setup

```bash
# Load multi-backend reference search infrastructure
# See .claude/skills/_shared/refmanager-backends.md
# Run auto-detection to set $REF_SOURCES, $REF_PRIMARY, $ZOTERO_DB, etc.
eval "$(cat "$SKILL_DIR/.claude/skills/_shared/refmanager-backends.md" | sed -n '/^```bash/,/^```/p' | sed '1d;$d')"
```

### 0c — Create Output Directory

```bash
mkdir -p "${OUTPUT_ROOT}/responses" "${OUTPUT_ROOT}/logs"
```

**Process Logging (REQUIRED):**

Initialize the process log NOW by running:

```bash
mkdir -p "${OUTPUT_ROOT}/logs"
SKILL_NAME="scholar-respond"
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
SKILL_NAME="scholar-respond"
LOG_DATE=$(date +%Y-%m-%d)
LOG_FILE="${OUTPUT_ROOT}/logs/process-log-${SKILL_NAME}-${LOG_DATE}.md"
if [ ! -f "$LOG_FILE" ]; then
  LOG_FILE=$(ls -t "${OUTPUT_ROOT}"/logs/process-log-${SKILL_NAME}-${LOG_DATE}*.md 2>/dev/null | head -1)
fi
echo "| [step#] | $(date +%H:%M:%S) | [Step Name] | [1-line action summary] | [output files or —] | ✓ |" >> "$LOG_FILE"
```

**IMPORTANT:** Shell variables do NOT persist across Bash tool calls. Every step MUST re-derive LOG_FILE before appending.

### 0d — Paper-Type Detection

After reading the manuscript, classify it:

| Paper type | Signals | Reviewer emphasis |
|---|---|---|
| **Quantitative-causal** | DiD, IV, RD, FE, matching, causal claims | R1 (quant) priority; causal design focus |
| **Quantitative-descriptive** | OLS, logit, decomposition, associational | R1 (quant) priority; robustness focus |
| **Computational** | NLP, ML, networks, LLM, ABM, CV, text-as-data | Add R4 (computational) reviewer |
| **Qualitative** | Interviews, ethnography, case study, discourse analysis | R2 (theory) priority; adjust R1 for qual rigor |
| **Mixed methods** | Sequential/concurrent qual+quant | All reviewers; integration quality focus |
| **Theoretical** | No primary data; theoretical argument | R2 (theory) priority; R3 framing priority |

---

## MODE 1: SIMULATE PEER REVIEW

Use when the user wants mock reviews before submission.

### Step 1: Read the Manuscript

Identify:
- Target journal (from title page or user input)
- Paper type (from 0d classification)
- Type of contribution (empirical, theoretical, methodological, computational, mixed)
- Core argument and hypotheses
- Data, design, and methods
- Key findings
- Claimed contribution
- Word count (estimate or exact)

### Step 1.5: Desk-Reject Risk Assessment (before full review simulation)

Before spawning reviewer agents, assess desk-reject probability:

**Desk-reject risk factors** (flag if >=3 present):
- [ ] Word count exceeds journal limit by >10%
- [ ] Missing required sections (e.g., no Theory section for ASR; no Reporting Summary for NHB)
- [ ] Contribution claim is unclear or absent from Introduction
- [ ] Topic outside journal scope (check journal aims & scope)
- [ ] No causal identification strategy (for methods-demanding journals)
- [ ] Writing quality issues (>5 grammatical errors per page; unclear prose)
- [ ] Citation count outside norms (too few or too many)
- [ ] Missing data/code availability statement (for Nature family)

**Risk levels**:
- 0-1 flags: LOW risk -- proceed to full review simulation
- 2-3 flags: MODERATE risk -- warn user; recommend FORMAT-CHECK via scholar-journal first
- 4+ flags: HIGH risk -- recommend addressing flags before simulating review

### Step 2: Journal-Calibrated Reviewer Configuration

Before spawning agents, identify journal-specific reviewer priorities:

| Journal | R1 (Methods) emphasis | R2 (Theory) emphasis | R3 (Editor) emphasis |
|---------|----------------------|---------------------|---------------------|
| **ASR** | Causal claims vs. design; AME not OR; robustness; N | Theory depth ≥800 words; mechanism specification; H↔results | Contribution clarity; word count ≤12K; framing |
| **AJS** | Same as ASR + historical/comparative scope | Classical theory engagement (Weber/Durkheim/Marx); theoretical innovation | Essay-style coherence; AJS readership fit |
| **Demography** | Sensitivity analyses; missing data; decomposition; online appendix | Data-population connection; demographic framework | Replication package; data availability |
| **Social Forces** | Solid empirical design; clear operationalization | Engagement with middle-range theories; clear literature positioning | Accessible framing; moderate theoretical ambition |
| **Science Advances** | Replication materials; code availability; interdisciplinary methods | Interdisciplinary framing; sociological terms defined for broader audience | Broad significance; CRediT statement; word count |
| **NHB** | Reporting Summary; power analysis; all test statistics (t, df, p); error bars labeled | Cross-disciplinary theory; claims accessible to psychologists/economists | Word limit (5K main); 50-reference limit; figure standards |
| **NCS** | Code mandatory; computational rigor; benchmarks; reproducibility | Methodological contribution clarity; computational advance stated | NCS Reporting Summary; Results-before-Methods; word limit |
| **Language in Society** | Sociolinguistic method rigor; transcription standards; speaker metadata | Language ideology frameworks; indexicality; language and power | Engagement with LiS readership; ethnographic depth |
| **APSR** | Causal identification; pre-registration; replication data | Democratic theory; institutional frameworks; power | Political significance; policy relevance; generalizability |
| **JMF** | Family demography methods; longitudinal design; selection | Life course theory; family process mechanisms | Applied significance; family policy implications |
| **PDR** | Demographic techniques; formal demography; decomposition | Population theory; demographic transition | Broad demographic significance; data quality |
| **SMR** | Methodological innovation; simulation evidence; proof | Clear methodological advance over existing tools | Sociological applicability; tutorial clarity |
| **Gender & Society** | Feminist methodology; intersectional analysis | Gender theory; intersectionality; power structures | Feminist praxis; social justice implications |
| **Poetics** | Cultural methods; text analysis; computational culture | Cultural theory; meaning-making; boundary work | Cultural sociology audience; symbolic boundaries |
| **Social Problems** | Applied methods; policy-relevant design | Social constructionism; claims-making; inequality | Public relevance; policy implications; accessibility |

### Step 3: Spawn Reviewer Agents

Use the Task tool to run reviewers **in parallel**. The reviewer prompts come from the agent .md files read in Step 0.

**Always spawn these three**:

**Reviewer 1 — Methodologist / Empiricist** (from `peer-reviewer-quant.md`)

> "You are a rigorous methodologist reviewing a [journal] paper. Follow the evaluation criteria and output format in your agent profile. Additionally, apply the journal-specific emphasis: [insert from calibration table above]. Paper type: [from 0d]. Be specific: quote the paper. Rate your recommended decision (Accept / Minor Revision / Major Revision / Reject). Manuscript: [full text]"

**Reviewer 2 — Theorist / Conceptual Critic** (from `peer-reviewer-theory.md`)

> "You are a theoretical sociologist reviewing a [journal] paper. Follow the evaluation criteria and output format in your agent profile. Additionally, apply the journal-specific emphasis: [insert from calibration table above]. Paper type: [from 0d]. Be specific: quote the paper. Rate your recommended decision. Manuscript: [full text]"

**Reviewer 3 — Senior Editor / Holistic Reviewer** (from `peer-reviewer-senior.md`)

> "You are a senior sociologist and former associate editor at [journal]. Follow the evaluation criteria and output format in your agent profile. Additionally, apply the journal-specific emphasis: [insert from calibration table above]. Paper type: [from 0d]. Be specific: quote the paper. Rate your recommended decision. Manuscript: [full text]"

**Always spawn a fourth reviewer**:

**Reviewer 4 — Interpretive Skeptic**

> "You are a devil's advocate reviewer whose sole job is to check whether the authors' *interpretive labels* for their findings are accurate and whether the same numbers could support a different (possibly opposite) story. You are NOT reviewing methods, theory depth, or writing quality — only the alignment between data and interpretation. For each major finding or interpretive claim in the manuscript:
> 1. Identify the specific numbers cited in support of the claim.
> 2. Check: does the claim hold from BOTH cross-group AND within-group perspectives? If the paper compares groups, compute within-group distributions (e.g., positive-to-negative ratios within each group) and check if these tell the same story as the cross-group comparison.
> 3. Check: are the labels accurate? Could a skeptical reader look at the same table and conclude something different? If yes, state the alternative interpretation.
> 4. Check: are mechanism claims (in Theory or Discussion) actually supported by data the authors collected, or are they imported from other literatures without verification? Flag any claim about the study context that is asserted without measurement (e.g., 'absence of editorial gatekeeping' when editorial processes were not measured).
> 5. Check: does the paper use consistent terminology for its core concepts, or do competing labels appear across sections?
> Rate: PASS (interpretations are well-supported) or NEEDS REVISION (specific claims need re-examination). For each NEEDS REVISION item, state the claim, the numbers, and the alternative interpretation. Manuscript: [full text]"

**Conditionally spawn a fifth reviewer**:

If paper type is **computational** (NLP, ML, networks, CV, ABM, LLM annotation), add:

**Reviewer 5 — Computational Methods Specialist** (from `peer-reviewer-computational.md`)

> "You are a computational social scientist reviewing a [journal] paper. Follow the evaluation criteria and output format in your agent profile. The paper uses [specific computational methods]. Apply the journal-specific emphasis: [insert from calibration table]. Be specific: quote the paper. Rate your recommended decision. Manuscript: [full text]"

**For qualitative papers**, modify R1's prompt:
> "You are reviewing a qualitative/mixed-methods paper. Instead of statistical rigor, evaluate: (1) methodological transparency (sampling, data collection, analysis steps); (2) analytical rigor (coding procedure, inter-coder agreement if applicable, saturation); (3) reflexivity and positionality; (4) evidence quality (thick description, triangulation); (5) transferability claims."

### Step 3.5: Reviewer Personality Calibration

When simulating, optionally assign personality types to increase realism:

| Personality | Behavior | Tone Adaptation |
|---|---|---|
| **Constructive** (default) | Identifies issues + suggests solutions | Standard response templates |
| **Skeptical** | Questions every assumption; demands robustness | Provide extra evidence; preemptively address concerns |
| **Hostile** | Dismissive of contribution; tone is harsh | Acknowledge valid points diplomatically; do not be defensive |
| **Perfectionist** | Demands minor fixes on every page | Address each point briefly; batch similar concerns |
| **Confused** | Misunderstands methodology or contribution | Clarify with patience; consider if writing was unclear |

**Tone adaptation for hostile reviewer**: "We appreciate the reviewer's [specific valid concern]. We have addressed this by [concrete change]. We respectfully note that [evidence/citation supporting our approach]."

### Step 4: Synthesize and Produce Simulation Output

After all agents return, synthesize into a formatted decision letter with a **Severity × Confidence Matrix**:

```
===== SIMULATED EDITORIAL DECISION =====
Journal: [journal]
Paper Type: [quantitative-causal / descriptive / computational / qualitative / mixed / theoretical]
Decision: [Major Revision / Minor Revision / Accept / Reject]
Reviewer Consensus: [unanimous / split — describe]

Dear [Author],

Thank you for submitting "[Paper Title]" to [Journal]. We have received
[three/four] independent reviews. [Summary of overall assessment — 2 sentences.]

[Decision rationale — 2–3 sentences]

We invite you to revise and resubmit addressing the following concerns.

===== REVIEWER 1 (METHODOLOGIST) =====
[Full review from Agent 1]

===== REVIEWER 2 (THEORIST) =====
[Full review from Agent 2]

===== REVIEWER 3 (SENIOR/HOLISTIC) =====
[Full review from Agent 3]

===== REVIEWER 4 (COMPUTATIONAL) ===== [if applicable]
[Full review from Agent 4]

===== SEVERITY × CONFIDENCE MATRIX =====

| # | Issue | Severity | Raised by | Confidence | Est. Effort |
|---|-------|----------|-----------|------------|-------------|
| 1 | [issue] | CRITICAL | R1, R2 | HIGH (2+ reviewers) | [hours/days] |
| 2 | [issue] | MAJOR | R1 | HIGH (methodological) | [hours/days] |
| 3 | [issue] | MAJOR | R2 | MEDIUM | [hours/days] |
| 4 | [issue] | MINOR | R3 | LOW (stylistic) | [hours] |
| ... | ... | ... | ... | ... | ... |

Severity: CRITICAL (paper cannot be published without fix) > MAJOR (substantive change needed) > MINOR (should fix) > COSMETIC (nice to fix)
Confidence: HIGH (raised by 2+ reviewers or factually correct) > MEDIUM (single reviewer, substantive) > LOW (opinion/preference)

===== REVISION ROADMAP =====

Phase 1 — Critical fixes (do first):
1. [Issue] — [what to do] — est. [effort]
2. ...

Phase 2 — Major revisions:
1. [Issue] — [what to do] — est. [effort]
2. ...

Phase 3 — Minor improvements:
1. ...

Phase 4 — Cosmetic/polish:
1. ...

Strengths to preserve (do not change):
1. ...
2. ...

Estimated total revision effort: [X days/weeks]
Estimated word count impact: [+/- N words] → projected total: [N] (limit: [N])
```

---

## MODE 2: DRAFT RESPONSE LETTER

Use when the user has received actual reviewer comments and needs to draft a professional, persuasive response.

### Step 1: Parse Round and Decision Context

Identify:
- **R&R round**: R1 (first revision), R2 (second revision), R3 (third revision)
- **Decision received**: Major Revision, Minor Revision, Conditional Accept
- **Editor's letter**: Does the editor highlight specific priorities? (Editor priorities override individual reviewer preferences)
- **Number of reviewers**: 2, 3, or 4
- **Previous response letter** (for R2+): If available, check for continuity

**Round-specific calibration**:

| Round | Tone | Scope of changes | Editor expectations |
|-------|------|-------------------|---------------------|
| **R1** (Major Revision) | Thorough, appreciative, demonstrate substantial engagement | Large revisions expected; new analyses OK | Show you took every comment seriously |
| **R1** (Minor Revision) | Efficient, precise; don't over-revise | Targeted fixes only; don't introduce new material | Quick turnaround; minimal new concerns |
| **R2** | More direct; less deferential | Only address remaining concerns; do NOT add new content beyond what was requested | Editor wants to accept; don't create new problems |
| **R3** | Extremely concise; surgical | Only the specific remaining items; absolutely nothing new | Paper should be nearly final; any new issue = reject |

### Step 2: Parse and Categorize All Comments

Read every reviewer comment and assign:
- **[CRITICAL]**: Raised by 2+ reviewers or editor-flagged — must address first
- **[MAJOR-FEASIBLE]**: Major concern, addressable
- **[MAJOR-INFEASIBLE]**: Major concern, not fully addressable (data limitations, etc.)
- **[MINOR-SUBSTANTIVE]**: Minor but non-trivial (add table, rephrase argument)
- **[MINOR-EASY]**: Minor fix (typo, citation, clarification)
- **[DISAGREE]**: Reviewer misunderstood or is factually wrong — respectful pushback needed
- **[CONFLICT]**: Contradicts another reviewer's demand
- **[NEW-IN-R2+]**: Comment raised for the first time in R2 or later — flag separately

Also note: **cross-reviewer overlaps** — the same concern raised by 2+ reviewers is the top priority.

**For R2+ rounds**: Flag any comment that was NOT raised in the previous round. New R2 concerns are lower priority than carried-over concerns, unless the editor specifically elevates them.

### Step 3: Local Library + CrossRef Lookup for Reviewer-Requested Citations

When a reviewer recommends citing a specific paper or author:

**Step 3a — Search local reference library first**:

```bash
# Re-load reference manager (shell state lost between Bash calls)
SKILL_DIR="${SCHOLAR_SKILL_DIR:-.}/.claude/skills"
eval "$(cat "$SKILL_DIR/_shared/refmanager-backends.md" | sed -n '/^```bash/,/^```/p' | sed '1d;$d')" 2>/dev/null
# Fallback: try with .claude/skills prefix if direct path fails
if ! type scholar_search &>/dev/null 2>&1; then
  eval "$(cat "${SCHOLAR_SKILL_DIR:-.}/.claude/skills/_shared/refmanager-backends.md" | sed -n '/^```bash/,/^```/p' | sed '1d;$d')" 2>/dev/null
fi

# Uses the multi-backend search function from Step 0b
# Searches across all detected backends (Zotero, BibTeX, etc.)
scholar_search "KEYWORD" 15 keyword
```

**Step 3b — CrossRef API fallback** (if not found in local library):

```bash
# Search CrossRef for a citation the reviewer requested
curl -s "https://api.crossref.org/works?query.bibliographic=AUTHOR+KEYWORD&rows=5&select=DOI,title,author,published-print,container-title" \
  | python3 -c "
import json, sys
data = json.load(sys.stdin)
for item in data.get('message',{}).get('items',[]):
    authors = ', '.join([a.get('family','') for a in item.get('author',[])])
    title = item.get('title',[''])[0]
    year = str(item.get('published-print',{}).get('date-parts',[['']])[0][0])
    journal = item.get('container-title',[''])[0]
    doi = item.get('DOI','')
    print(f'{authors} ({year}). {title}. {journal}. DOI: {doi}')
" 2>/dev/null
```

If found in local library, use the stored metadata. If found via CrossRef, note the DOI. If not found via either, use WebSearch.

### Step 4: Produce the Response Triage Dashboard

Before drafting the letter, present a structured overview:

```
===== RESPONSE TRIAGE DASHBOARD =====
Round: [R1 / R2 / R3]
Decision: [Major Revision / Minor Revision]
Date received: [YYYY-MM-DD]

| #    | Reviewer | Comment Summary              | Category         | Priority | Section Affected | Word Impact | Action Planned                     |
|------|----------|------------------------------|------------------|----------|------------------|-------------|-----------------------------------|
| R1.1 | R1       | Parallel trends not tested   | CRITICAL         | ★★★      | Methods, App.    | +200        | Add event study + pre-trend test   |
| R1.2 | R1       | Report AME not odds ratios   | MAJOR-FEASIBLE   | ★★       | Results          | ±0          | Replace OR with AME in Tables 2–3  |
| R2.1 | R2       | Mechanism is vague           | MAJOR-FEASIBLE   | ★★       | Theory           | +300        | Add mechanism ¶ to Theory §        |
| R2.2 | R2       | Missing citation: Lee 2019   | MINOR-EASY       | ★        | Theory           | +20         | Add to Theory ¶3 (library ✓)      |
| R3.1 | R3       | Introduction too long        | MINOR-EASY       | ★        | Introduction     | −300        | Cut intro from 1,200 to 900 words  |
| Ed.1 | Editor   | Clarify contribution         | CRITICAL         | ★★★      | Introduction     | +100        | Rewrite final intro ¶              |

Summary statistics:
  Total comments: [N] | Critical: [N] | Major: [N] | Minor: [N]
  Sections affected: [list]
  Estimated net word change: [+/- N words]
  Current word count: [N] → Projected: [N] (limit: [N])

Cross-reviewer overlaps (must fix first):
- [Issue] raised by R1 + R2: [description]

Conflicting demands:
- R1 says [X]; R2 says [opposite] → proposed resolution: [approach]

Infeasible requests:
- [R#.#] [reason why infeasible] → closest alternative: [what you will do instead]

Editor priorities (from decision letter):
- [Priority 1 — often the single most important thing to address]
- [Priority 2]

[R2+ only] New comments not in previous round:
- [R#.#] [NEW-IN-R2+] — [description] — priority: [lower unless editor-elevated]
```

Present the dashboard to the user and ask for confirmation before drafting.

### Step 5: Develop Response Strategy

For each comment, determine:
1. **Action**: What changes in the manuscript?
2. **Where**: Which section/paragraph/table?
3. **Tone**: Agree fully / Agree partially / Respectfully disagree
4. **Word impact**: How many words added/removed?

**Decision rules**:
- If raised by 2+ reviewers → must address fully, note the overlap in the response
- If editor highlighted → treat as highest priority regardless of reviewer count
- If reviewer is factually wrong → correct politely with citation
- If request is genuinely infeasible → explain why; offer the closest feasible alternative
- If reviewers conflict → name the conflict and explain your resolution (see `references/common-concerns.md` conflict templates)
- If paper's core argument is challenged → defend with evidence and logic, not just assertion
- **R2+ rule**: Do not introduce new analyses, new citations, or new arguments beyond what reviewers asked for. Scope creep in R2 is the #1 cause of R3 rejection.

### Step 6: Draft the Response Letter

```
===== RESPONSE TO REVIEWERS =====

[Title of Paper]
[Journal Name] | Manuscript #: [if available]
Round: [R1 / R2 / R3]
[Date]

Dear [Dr. LastName / "Editor"],

[Round-appropriate opening — see templates below]

In the revised manuscript, we have [1–2 sentence summary of the most
significant changes]. All revisions are indicated in [blue text / tracked
changes]. The most significant changes include:
• [Major change 1]
• [Major change 2]
• [Major change 3]

We respond to each comment in turn below.

─────────────────────────────────────────────
REVIEWER 1
─────────────────────────────────────────────

Comment 1.1: "[Exact quote of reviewer comment]"

Response: [See tone guidelines below]

Revision: [What changed, specific location: "We have revised the third
paragraph of the Methods section (p. 12) to read: '...'"]

---

Comment 1.2: "[Exact quote]"

Response: ...
Revision: ...

[Continue for all comments]

─────────────────────────────────────────────
REVIEWER 2
─────────────────────────────────────────────

[Same format]

─────────────────────────────────────────────
REVIEWER 3 (if applicable)
─────────────────────────────────────────────

[Same format]

─────────────────────────────────────────────
EDITOR'S COMMENTS (if applicable)
─────────────────────────────────────────────

[Same format]

─────────────────────────────────────────────
CHANGES SUMMARY TABLE
─────────────────────────────────────────────

| Section | Changes Made | Comments Addressed | Word Δ |
|---------|-------------|-------------------|--------|
| Abstract | Updated to reflect revised framing | R3.1 | −15 |
| Introduction | Rewritten contribution ¶; cut background | Ed.1, R3.1 | −200 |
| Theory | Added mechanism ¶; added Lee (2019) | R2.1, R2.2 | +320 |
| Methods | Added pre-trend test description | R1.1 | +200 |
| Results | Replaced OR with AME; added Table A1 | R1.2, R1.1 | +50 |
| Discussion | Updated interpretation of H2 | R2.1 | +80 |
| Appendix | New event study figure (Fig A1) | R1.1 | +100 |
| **Total** | | | **[net Δ]** |

Final word count: [N] (limit: [N])

─────────────────────────────────────────────

We believe the revised manuscript is substantially stronger and addresses
all reviewer concerns. We hope it is now suitable for publication in [Journal].

Sincerely,
[Corresponding Author Name]
[Title, Affiliation, Email]
```

**Round-specific openings**:

**R1 (Major Revision)**:
> "We are grateful to the Editor and [two/three] reviewers for their careful reading and constructive feedback. The comments have helped us substantially improve the paper. We have made significant revisions in response to all concerns."

**R1 (Minor Revision)**:
> "We thank the Editor and reviewers for their positive assessment and helpful suggestions. We have addressed all remaining points as detailed below."

**R2**:
> "We thank the Editor for the opportunity to revise further and the reviewers for their continued engagement with our work. We have carefully addressed each remaining concern. The changes in this round are targeted to the specific points raised."

**R3**:
> "We appreciate the reviewers' and Editor's patience in guiding this manuscript to its final form. We have made the remaining [N] requested changes, which are detailed below."

### Step 7: Apply Response Tone Guidelines

**Full agreement**:
> "We thank Reviewer [N] for this observation. We agree that [restate concern]. We have [specific action]. The revised text now reads: '[new text]' (p. X, lines Y–Z)."

**Partial agreement**:
> "We appreciate this comment and agree that [aspect X]. We have revised [section] accordingly. However, we respectfully note that [your position], because [reason + citation]. We have revised the text to clarify this: '[new text]' (p. X)."

**Respectful disagreement**:
> "We appreciate Reviewer [N]'s concern about [topic]. After careful consideration, we respectfully maintain our original approach for the following reasons: [1–3 specific reasons with logic or citation]. We have, however, revised p. X to make our rationale explicit: '[new text]'."

**Infeasible request**:
> "Reviewer [N] recommends [request]. We share the reviewer's interest in [the goal]. Unfortunately, [specific reason why infeasible]. As an alternative, we [closest feasible action]. We believe this addresses the reviewer's underlying concern, though we acknowledge this limitation in the Discussion (p. X)."

**Reviewer misunderstood**:
> "We appreciate Reviewer [N]'s close reading and believe this comment may reflect an ambiguity in our presentation. To clarify: [explanation]. We have revised p. X to make this explicit: '[new text]'."

**Cross-reviewer overlap** (note it explicitly):
> "Both Reviewers 1 and 2 raise concerns about [issue]. We agree this is a priority and have [action]. [Describe revision with location.]"

**R2+ new comment not in previous round**:
> "We appreciate Reviewer [N]'s new observation regarding [topic]. We have [action]. We note that this concern was not raised in the first round, and we have addressed it within the scope of the current revision."

---

## MODE 3: REVISE THE MANUSCRIPT

Use to execute section-by-section revisions based on the response letter.

### Step 1: Build a Revision Plan with Word Budget

From the response letter (Mode 2) or user-provided comments, extract all revision actions:

```
===== REVISION PLAN =====

Word Budget:
  Current manuscript: [N] words
  Journal limit: [N] words
  Available budget: [+/- N] words

─────────────────────────────────────────────
Priority 1 — Critical (editor + multi-reviewer):
[R1.1] Methods §, para 3    → Add pre-trend test + event study figure     [+200 words]
[Ed.1] Introduction, last ¶ → Rewrite contribution statement              [+100 words]

Priority 2 — Major:
[R1.2] Table 2              → Replace odds ratios with AME + 95% CI       [±0 words]
[R2.1] Theory §             → Add mechanism paragraph (X → M → Y)         [+300 words]

Priority 3 — Minor:
[R2.2] Theory § ¶3          → Add citation: Lee (2019)                    [+20 words]
[R3.1] Introduction         → Cut from 1,200 to 900 words                 [−300 words]

Consistency updates (always do last):
[Consist.] Abstract         → Update to reflect revised finding framing    [±0 words]
[Consist.] H labels         → Verify H1–H3 match across Theory, Results, Discussion
─────────────────────────────────────────────
Total revisions: [N] | Critical: [N] | Major: [N] | Minor: [N]
Estimated word count change: [+/- N words]
New estimated total: [N] words (limit: [N])

⚠ WORD COUNT WARNING: [if projected total exceeds limit, flag which sections to cut]
```

Confirm the revision plan with the user before executing.

### Step 2: Load Reference Manager and Writing Skill

**Step 2a — Re-load reference manager** (shell state does not persist between Bash calls):
```bash
SKILL_DIR="${SCHOLAR_SKILL_DIR:-.}/.claude/skills"
eval "$(cat "$SKILL_DIR/_shared/refmanager-backends.md" | sed -n '/^```bash/,/^```/p' | sed '1d;$d')" 2>/dev/null
echo "REF_SOURCES=$REF_SOURCES | ZOTERO_DB=${ZOTERO_DB:-not found}"
```

This ensures `scholar_search` is available for any citation additions during revisions. When a revision item requires a new citation, call `scholar_search "KEYWORD" 15 keyword` to verify against Zotero/local backends before inserting. Flag any unverified citations as `[CITATION NEEDED]`.

**Step 2b — Load writing skill** for revision execution:
```bash
SKILL_DIR="${SCHOLAR_SKILL_DIR:-.}"
cat "$SKILL_DIR/.claude/skills/scholar-write/SKILL.md"
```

For each revision item, apply `/scholar-write revise [section]`:
- Paste the relevant existing section text as input
- Specify the reviewer concern and required change as the revision instruction
- Use the REVISE mode's `[REVISED: reason]` annotation system

For each revision, produce a **diff**:
```
─── REVISION [R#.#] ───────────────────────
SECTION: [Methods § para 3]
COMMENT: [R1.1 — Parallel trends not tested]

ORIGINAL:
"[original text]"

REVISED:
"[new text]"

REASON: Addresses R1.1 (parallel trends) and partially addresses Ed.1 (identification)
WORD Δ: [+200 words]
RUNNING TOTAL: [N] words ([N] remaining in budget)
─────────────────────────────────────────────
```

**Revision writing standards**:
- Match the voice and tense of the surrounding text
- Do not introduce new claims not in the response letter
- Solve exactly the reviewer's concern — no over-revision
- Preserve strong existing text; change only what is needed
- **R2+ rule**: Minimal changes only. Do not rewrite paragraphs that were not flagged.

### Step 3: Consistency Check

After all revisions:
- [ ] Table and figure references in text still match the actual tables/figures
- [ ] Table and figure numbering is sequential (no gaps or duplicates)
- [ ] Abstract accurately reflects any changed findings or framing
- [ ] Contribution statement in Introduction reflects revisions
- [ ] Hypothesis labels (H1, H2...) are consistent across Theory, Results, Discussion
- [ ] All hypothesis results are discussed (no orphan hypotheses)
- [ ] Word count is within journal limit after all revisions
- [ ] All [CITATION NEEDED] markers from revision are flagged for `/scholar-citation`
- [ ] **NEW citations introduced during R&R** are verified via local library, CrossRef, Semantic Scholar, or OpenAlex — not inserted from Claude's memory alone
- [ ] **Claim verification (MANDATORY):** All prose claims attributing findings to newly added citations are checked against Knowledge Graph or PDF text — run `scholar-citation` Step V-3.5. R&R citations added under time pressure are the highest risk for mischaracterization. Flag all 7 marker types: `[CLAIM-REVERSED]`, `[CLAIM-MISCHARACTERIZED]`, `[CLAIM-OVERCAUSAL]`, `[CLAIM-UNSUPPORTED]`, `[CLAIM-WRONG-POPULATION]`, `[CLAIM-IMPRECISE]`, `[CLAIM-NOT-CHECKABLE]`. Correct all error-level markers before saving.
- [ ] Reference list includes all newly cited works and removes any dropped citations
- [ ] Tracked changes / blue text marking is applied consistently
- [ ] No new typos or grammatical errors introduced by revisions

**Run the claim verification gate on the revised manuscript:**
```bash
bash "${SCHOLAR_SKILL_DIR:-.}/scripts/gates/verify-claims.sh" "[revised_manuscript_path]"
```

### Step 3a: New-Analysis Gate (MANDATORY when reviewers request new analyses)

**Purpose:** R&R reviewers routinely ask for new regressions (add state FE, cluster SEs differently, subset sample, different outcome). The highest failure mode in R&R is running the new analysis without the rigor of the original pipeline, then dropping numbers into the response letter via prose paraphrase. This gate forces new analyses through the same contract as the initial study.

**Trigger:** any "Items Requiring Author Action" in the response strategy that involves re-running or adding a regression / subset / specification.

**Protocol — every new analysis dispatched from an R&R response must:**

1. Generate the analysis script under `${PROJ}/scripts/rr-NN-[description].R`, do NOT execute yet.
2. Run `scholar-code-review` in `statistics` + `data-handling` + `correctness` mode against the new script, using the Phase 3 design blueprint (if available) or the reviewer's specification as compliance reference. Apply the **Code-Review Fix Loop** from `cat "${SCHOLAR_SKILL_DIR:-.}/.claude/skills/_shared/code-review-fix-loop.md"`. CRITICAL halts.
3. Load the registry contract and adjudication rule:
   ```bash
   cat "${SCHOLAR_SKILL_DIR:-.}/.claude/skills/_shared/results-registry-contract.md"
   cat "${SCHOLAR_SKILL_DIR:-.}/.claude/skills/scholar-analyze/references/adjudication-rule.md"
   ```
   The new script must emit `${PROJ}/tables/rr-results-registry.csv` and (if hypothesis-bearing) `${PROJ}/tables/rr-adjudication-log.csv` in the same schemas as the originals, appended or separate.
4. Execute in a clean R session, then run plausibility + direction-consistency + (for ASR/AJS/Demography/Nature/Science) clean-room re-run checks from `cat "${SCHOLAR_SKILL_DIR:-.}/.claude/skills/_shared/phase-runtime-sanity.md"`. CRITICAL halts.
5. Disk-citation discipline in the response letter (Step 4 below): every numeric claim from a new analysis must carry `[rr-results-registry.csv row=X model_id=Y]` — never a prose paraphrase of the agent's return text.

**Skip only if:** the reviewer's comment is handled without new statistics (rewording, adding citations, arguing against the request, noting a limitation).

---

### Step 3b: Verification Gate (scholar-verify)

**Purpose:** R&R revisions often introduce new numbers, change table references, or alter statistical claims. Run `scholar-verify` on the revised manuscript to catch inconsistencies introduced during revision. When new analyses were run in Step 3a, `verify-numerics` and `verify-logic` MUST also compare prose claims against `rr-results-registry.csv` and `rr-adjudication-log.csv`.

**Check for raw outputs:**
```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
TABLE_COUNT=$(ls "${OUTPUT_ROOT}"/tables/*.{html,tex,csv,docx} 2>/dev/null | wc -l)
FIGURE_COUNT=$(ls "${OUTPUT_ROOT}"/figures/*.{pdf,png,svg} 2>/dev/null | wc -l)
echo "Tables: $TABLE_COUNT | Figures: $FIGURE_COUNT"
```

**If raw outputs exist** (tables or figures found):

Read the `scholar-verify` SKILL.md:
```bash
cat .claude/skills/scholar-verify/SKILL.md
```

Run `scholar-verify` in **full** mode on the revised manuscript. This launches all 4 agents:
- **Stage 1**: verify-numerics + verify-figures (raw outputs → revised manuscript tables/figures)
- **Stage 2**: verify-logic + verify-completeness (revised manuscript tables/figures → revised prose)

This is especially important for R&R because:
1. New analyses requested by reviewers may have been transcribed incorrectly
2. Revised text may reference old (pre-revision) numbers
3. New tables/figures added during revision need completeness verification

**If no raw outputs exist**: The manual consistency checklist in Step 3 above is sufficient. Proceed to Step 4.

**Gate decision:**
- **0 CRITICAL issues**: Proceed to Step 4.
- **1+ CRITICAL issues**: Fix before proceeding. Include fixes in the response letter as additional revisions made during consistency checking.

Add any verification-driven fixes to the revision tracking in Step 4's Revision Summary under a "Post-revision verification fixes" subsection.

#### Step 3c (Optional): External Review via Codex (scholar-openai)

**Purpose:** For R&R revisions that involved substantial new analysis or major rewriting, run an independent external review via OpenAI Codex agents for a second opinion.

**Trigger:** User opts in, OR Step 3b found CRITICAL issues (cross-validate with external model).

```bash
cat .claude/skills/scholar-openai/SKILL.md
```

Run `scholar-openai` in the appropriate mode:
- `code` — if R&R involved new analysis scripts
- `stats` — if R&R involved new tables/numbers
- `full` — if R&R was comprehensive

Cross-reference Codex findings with Step 3b findings. Issues confirmed by both get highest confidence.

### Step 4: Produce Revision Summary

```
===== REVISION SUMMARY =====

Round: [R1 / R2 / R3]
Total revisions: [N] | Critical: [N] | Major: [N] | Minor: [N]

Changes by section:
  Abstract:       [description]
  Introduction:   [description]
  Theory:         [description]
  Methods:        [description]
  Results:        [description]
  Discussion:     [description]
  Tables/Figures: [description]
  Appendix:       [description]

Word count: Original [N] → Revised [N] (limit: [N])

Consistency check: [PASSED / FAILED — list failures]

Items requiring author attention (beyond what was revised here):
  • [Any items beyond what was revised — e.g., new analysis to run, data to check]
  • [e.g., "Run new event study specification — requires re-running regression in R"]
  • [e.g., "Obtain original data for sensitivity analysis R2.3 requested"]

Recommended next steps:
  1. [Run pending analyses]
  2. [/scholar-citation insert — to add all new citations to reference list]
  3. [/scholar-respond cover-letter — to write the R&R cover letter]
```

---

## MODE 4: RESUBMISSION STRATEGY

Use after a rejection to diagnose the root cause, select a new target journal, reframe the manuscript, and write a cover letter for resubmission.

### Step 1: Triage the Rejection Decision

| Decision type | What it means | Your response |
|--------------|--------------|---------------|
| **Desk reject** | Out of scope or below threshold; no external review | Reframe for a different journal; do not resubmit to same journal without major restructuring |
| **Reject after review** | External review; editor says fatal flaws | Diagnose root cause (Step 2); major revision before next submission |
| **Reject with invitation** | Rare; signals openness if specific concerns are addressed | Treat as conditional R&R; respond to each concern; resubmit as new submission with detailed cover letter |
| **R&R declined / expired** | You declined or missed deadline | Same as reject after review |

### Step 2: Diagnose Root Cause

Before resubmitting anywhere, identify the failure mode:

| Root cause | Diagnosis signs | Fix | Typical time |
|------------|----------------|-----|-------------|
| **Scope mismatch** | Desk reject; "outside our scope"; no substantive critique | Change framing and opening, not the paper | 1–2 weeks |
| **Contribution threshold** | "Interesting but not transformative enough for [journal]" | Assess if genuine advance is possible; or move down the journal ladder | 2–4 weeks |
| **Fatal methodological flaw** | "Identification assumption untenable"; "N too small for the claims" | Fix before resubmitting ANYWHERE — new reviewers will raise it too | 1–3 months |
| **Framing mismatch** | Sociology paper rejected by Nature: "too specialized"; Nature paper rejected by sociology: "not theoretical enough" | Substantive reframing of introduction and contribution | 2–4 weeks |
| **Theory too thin** | ASR/AJS: "insufficient theoretical contribution"; "too descriptive" | Expand Theory section; strengthen mechanism argument | 3–6 weeks |
| **Writing quality** | "Poorly written"; "hard to follow"; "argument unclear" | Substantial rewrite of Introduction and Theory | 2–4 weeks |
| **Data/reproducibility** | NCS/NHB: "code not available"; "not reproducible" | Deposit code and data; add Reporting Summary | 1–2 weeks |

### Step 3: Select Target Journal

Use expanded journal ladders by subfield:

**Computational sociology**:
NCS → Science Advances → NHB → PNAS → Sociological Methods & Research → AJS/ASR

**Stratification / inequality**:
ASR → AJS → Social Forces → Social Problems → Sociological Quarterly → Research in Social Stratification & Mobility

**Demography / population**:
Demography → Population and Development Review → Population Studies → Journal of Marriage and Family → Social Science Research

**Race / ethnicity**:
ASR → AJS → Du Bois Review → Social Forces → Ethnic and Racial Studies → Sociology of Race and Ethnicity

**Gender / family**:
ASR → Gender & Society → Journal of Marriage and Family → Social Forces → Journal of Family Issues

**Political sociology**:
ASR → APSR → AJS → Social Forces → Mobilization → Political Research Quarterly

**Culture / knowledge**:
AJS → ASR → Poetics → Cultural Sociology → Theory and Society

**Linguistics / language & society**:
Language in Society → Journal of Sociolinguistics → Language Variation and Change → Journal of Language and Social Psychology → Applied Linguistics

**Interdisciplinary / broad**:
Nature/Science → Science Advances → NHB → NCS → PNAS → PLOS ONE

**Decision rules**:
- Move down the ladder only if the contribution cannot clear the next tier's bar
- Address fatal flaws before moving anywhere on the ladder
- If rejected for scope mismatch, consider a lateral move (same tier, different subfield journal) rather than moving down
- Do not "shotgun" submissions — one active submission at a time

### Step 4: Reframe the Introduction for the New Journal

The analysis stays the same; the introduction framing changes for the new audience:

| Element | What to change | Why |
|---------|---------------|-----|
| Opening hook | Match the new journal's entry point (ASR: theoretical puzzle; AJS: historical question; Science Advances: societal significance; Demography: demographic trend; NCS: computational advance; LiS: language ideological puzzle; APSR: democratic/institutional puzzle) | Different readers care about different things |
| Contribution claim | Restate what is new relative to what the new journal's readers know | Contribution is always relative to an audience |
| Literature cited | Cite the new target journal's own recent articles | Show you know the conversation |
| Theory emphasis | ASR: mechanism; AJS: theoretical innovation; Science Advances: interdisciplinary significance; NCS: methodological advance; LiS: ideological critique | Each journal has a different theoretical register |
| Word count | Adjust to the new journal's limits | |
| Section structure | NCS: Results before Methods; Nature journals: brief Methods in main text + detailed in Supplementary | Journal-specific conventions |

**Reframed contribution paragraph template**:
> "[Target journal]'s readership will recognize [the puzzle or debate that motivates the paper]. Despite [what is known], [what remains unknown or contested]. We address this gap by [what we do]. Our contribution is [specific advance: new method / new population / resolved debate / boundary condition]. This matters because [why the target audience cares, in their own terms]."

### Step 5: Write the Resubmission Cover Letter

```
Dear [Dr. LastName / Editor],

Please find enclosed our manuscript, "[Title]," for consideration for
publication in [New Journal Name].

[1–2 sentences on why this paper is a strong fit for this journal's scope
and readership — be specific about the journal, not generic.]

[1–2 sentences summarizing the key contribution and findings.]

This manuscript has been substantially revised since an earlier version
was reviewed elsewhere. The current version includes [summary of major
revisions: e.g., "a new event study analysis, an expanded theory section,
and a reframed contribution argument"]. We believe these revisions
significantly strengthen the paper.

[Optional — pre-empt a predictable concern]:
"We note that while our design is observational, we conduct [specific
robustness checks] in Appendix B that bound the potential confounding."

The manuscript is [N] words (within [journal]'s [N]-word limit), has
not been published elsewhere, and is not under review at another journal.

We look forward to your consideration.

Sincerely,
[Name, Title, Affiliation, Email]
```

### Step 6: Lessons Learned Log

Document what went wrong and what was fixed for future reference:

```
===== POST-REJECTION LESSONS LEARNED =====

Previous journal: [journal]
Decision: [desk reject / reject after review]
Root cause: [from Step 2]

What reviewers said (key themes):
1. [Theme 1]
2. [Theme 2]

What we changed:
1. [Change 1 — addresses theme 1]
2. [Change 2 — addresses theme 2]

What we did NOT change (and why):
1. [Element preserved — rationale]

New target: [journal]
Key differences in framing:
1. [Difference 1]
2. [Difference 2]

Pre-emptive defenses added to manuscript:
1. [Defense 1 — anticipating concern X]
```

---

## MODE 5: R&R COVER LETTER

Use to write a standalone cover letter for an R&R resubmission (separate from the point-by-point response letter).

### Step 1: Gather Information

Identify:
- Journal name and manuscript number
- Editor name (if known)
- R&R round (R1, R2, R3)
- Key changes made (from Mode 3 revision summary, or user input)
- Decision received (Major Revision / Minor Revision)

### Step 2: Draft the Cover Letter

**R1 Cover Letter (Major Revision)**:

```
Dear [Dr. LastName / Editor],

Please find enclosed our revised manuscript, "[Title]" (Manuscript #:
[xxx]), submitted in response to the [Major/Minor] Revision decision of
[date].

We are grateful to the Editor and [N] reviewers for their constructive
and detailed feedback. We have carefully revised the manuscript to
address all concerns raised. The major changes include:

1. [Major change 1 — briefly, 1 sentence]
2. [Major change 2]
3. [Major change 3]

[Optional: 1–2 sentences addressing the editor's specific priority if
one was identified in the decision letter.]

A detailed, point-by-point response to each reviewer comment is enclosed
separately. All changes in the manuscript are marked in [blue text /
tracked changes].

The revised manuscript is [N] words, within the journal's word limit.
We believe the revisions significantly strengthen the paper and address
all reviewer concerns.

Thank you for the opportunity to revise. We look forward to your
decision.

Sincerely,
[Name, Title, Affiliation, Email]
```

**R2 Cover Letter (second revision)**:

```
Dear [Dr. LastName / Editor],

Please find enclosed our second revision of "[Title]" (Manuscript #:
[xxx]).

We thank the Editor and reviewers for their continued engagement with
our work. In this revision, we have addressed all [N] remaining points:

1. [Change 1]
2. [Change 2]

The changes in this round are limited to the specific concerns raised.
A point-by-point response is enclosed.

The manuscript is [N] words. We hope the revised version is now suitable
for publication in [Journal].

Sincerely,
[Name, Title, Affiliation, Email]
```

**R1 Cover Letter (Minor Revision)**:

```
Dear [Dr. LastName / Editor],

Please find enclosed our revised manuscript, "[Title]" (Manuscript #:
[xxx]), addressing the Minor Revision points from [date].

We have made all requested changes, which are detailed in the enclosed
response letter. The key revisions are:

1. [Change 1]
2. [Change 2]

We believe the manuscript is now ready for publication in [Journal].

Sincerely,
[Name, Title, Affiliation, Email]
```

---

## Full Pipeline: Simulate → Respond → Revise

When invoked without a specific mode, or with `all`:

```
1. Read the manuscript
2. SIMULATE: Run 3–4 journal-calibrated reviewer agents in parallel
   → produce severity matrix + revision roadmap
3. Ask: "These are your simulated reviews. Would you like to:
   (a) Draft a response letter treating these as real reviews
   (b) Use these to identify weaknesses before submitting
   (c) Both"
4. RESPOND: Produce triage dashboard → draft response letter
5. REVISE: Build word-budget revision plan → execute via /scholar-write revise
6. Final check: word count, consistency, formatting
7. COVER-LETTER: Draft the R&R cover letter
```

---

## Verification Subagent

After completing any mode, run a verification check via Task tool:

> "You are verifying a scholar-respond output. Check the following:
>
> **For MODE 1 (simulate)**: (1) Each reviewer addresses journal-specific concerns from the calibration table; (2) reviews are realistic in length and tone; (3) severity matrix is consistent with review content; (4) revision roadmap addresses all critical and major items; (5) no reviewer concern is missing from the action plan.
>
> **For MODE 2 (respond)**: (1) Every reviewer comment has a numbered response — no skipped items; (2) every response includes specific revision text or explains why none was made; (3) cross-reviewer overlaps are noted; (4) conflicting demands are resolved with rationale; (5) Changes Summary Table matches the actual changes described; (6) word count is tracked and within limits; (7) all reference library/CrossRef lookups are documented.
>
> **For MODE 3 (revise)**: (1) All revision plan items are executed; (2) diffs are provided for each change; (3) word budget is tracked; (4) consistency check passes; (5) no over-revision beyond what reviewers asked.
>
> **For MODE 4 (resubmit)**: (1) Root cause diagnosis is specific and actionable; (2) journal selection is justified; (3) reframed introduction matches new journal's conventions; (4) cover letter is journal-specific, not generic.
>
> **For MODE 5 (cover-letter)**: (1) Tone matches the R&R round; (2) key changes are listed concisely; (3) manuscript number and editor name included if available; (4) word count stated.
>
> Flag any issues found. Output: [pass/fail] + [list of issues if any]."

---

## Save Output

After completing any mode, save files using the Write tool.

**Version collision avoidance (MANDATORY — RUN BEFORE EVERY Write tool call):** Read and follow the version collision avoidance protocol in `.claude/skills/_shared/version-check.md`. You MUST run the version-check Bash block to determine the correct save path BEFORE calling the Write tool. The Bash block prints `SAVE_PATH=...` — use that exact printed path in the Write tool call. Do NOT hardcode a path from the filename template. Shell variables do NOT persist between Bash calls, so re-derive `$BASE` in every new Bash call. **NEVER overwrite an existing file.**

### File 1 — Response Log (Internal Record)

**Purpose**: Internal record of strategy decisions. Not for submission.

**Filename**: `output/[slug]/responses/scholar-respond-log-[slug]-[YYYY-MM-DD].md`

```markdown
# Response Log — [Paper Title Slug]

**Date**: [YYYY-MM-DD]
**Mode**: [simulate / respond / revise / resubmit / cover-letter]
**Journal**: [journal name]
**Round**: [R1 / R2 / R3]
**Decision received**: [Major Revision / Reject / etc.]

## Paper Classification
- Type: [quantitative-causal / descriptive / computational / qualitative / mixed / theoretical]
- Methods: [list key methods used]
- Computational reviewer needed: [yes / no]

## Triage Dashboard
[Paste the full triage table from Mode 2 Step 4]

## Reference Library / CrossRef Lookups
- Reviewer-requested: [Author Year] → [found in local library / found via CrossRef / not found]
- Added to manuscript: [yes / no]

## Strategy Decisions
- [Decision 1, e.g., "Chose FE over OLS for R1.1 because identification is cleaner"]
- [Decision 2, e.g., "Agreed with R2 over R1 on sample restriction — explained in letter"]

## Conflicting Reviewer Resolutions
- [Conflict + resolution chosen + rationale]

## Word Count Tracking
- Original: [N] → After revisions: [N] → Limit: [N]
- Net change: [+/- N words]

## Items Requiring Author Action (beyond Claude's revision)
- [e.g., "Run new event study specification — requires re-running regression in R"]
- [e.g., "Obtain original data for sensitivity analysis R2.3 requested"]

## Lessons Learned (for resubmit mode)
[Paste from Mode 4 Step 6 if applicable]
```

### File 2 — Response Letter / Cover Letter (Publication-Ready)

**Purpose**: Complete letter ready to submit with the revised manuscript. No placeholders should remain.

**Filename**: `output/[slug]/responses/scholar-respond-letter-[slug]-[YYYY-MM-DD].md`

Contains the full formatted response letter (Mode 2), R&R cover letter (Mode 5), or resubmission cover letter (Mode 4) with all reviewer comments, responses, and revision descriptions filled in.

### File 3 — Revision Plan (if Mode 3)

**Filename**: `output/[slug]/responses/scholar-respond-revision-plan-[slug]-[YYYY-MM-DD].md`

Contains the full revision plan with word budgets, diffs, and consistency check results.

Confirm all saved file paths to the user.

### Convert Response Letter to Submission Formats (MANDATORY for Modes 2, 4, 5)

Journals require the response letter as `.docx` or `.pdf`, not `.md`. After writing File 2 (the submission-ready letter) via the Write tool, convert it with pandoc. Shell variables do NOT persist across Bash tool calls, so derive `BASE` from the **exact** path used in the preceding Write call — do not attempt to re-derive from `SLUG` / `OUTPUT_ROOT` (those are not set in this Bash block).

```bash
set -euo pipefail
# CRITICAL: Replace [saved-md-path] with the EXACT path you used in the Write tool call
# for File 2 (the submission-ready letter). This is the SAVE_PATH version-check.sh printed.
MD_FILE="[saved-md-path]"
if [ ! -f "$MD_FILE" ]; then
  echo "FAIL: response-letter .md not found at $MD_FILE — re-check the File 2 save path." >&2
  exit 1
fi
BASE="${MD_FILE%.md}"
echo "Converting: ${BASE}.md -> .docx, .pdf"
pandoc "${BASE}.md" -o "${BASE}.docx" \
  --reference-doc="$HOME/.pandoc/reference.docx" 2>/dev/null \
  || pandoc "${BASE}.md" -o "${BASE}.docx"
pandoc "${BASE}.md" -o "${BASE}.pdf" --pdf-engine=xelatex 2>/dev/null \
  || pandoc "${BASE}.md" -o "${BASE}.pdf"
ls -la "${BASE}".docx "${BASE}".pdf 2>/dev/null
```

Notes:
- Mode 3 (revised manuscript) is exported via the scholar-write pandoc block — scholar-respond does NOT re-convert the manuscript.
- If `xelatex` is missing, pandoc falls back to the default PDF engine; the letter is short so this is acceptable.
- Verify both files exist and spot-check the `.docx` opens cleanly before submission.

### Knowledge Graph Write-Back (post-save)

```bash
SKILL_DIR="${SCHOLAR_SKILL_DIR:-.}/.claude/skills"
KG_REF="$SKILL_DIR/_shared/knowledge-graph-search.md"
if [ -f "$KG_REF" ]; then
  eval "$(cat "$KG_REF" | sed -n '/^```bash/,/^```/p' | sed '1d;$d')" 2>/dev/null
  if kg_available 2>/dev/null; then
    echo ""
    echo "═══ Knowledge Graph ═══"
    echo "Reviewers may have suggested references not in your knowledge graph. Ingest them:"
    echo "  /scholar-knowledge ingest from doi [DOI]  (for each new reference from reviewers)"
  fi
fi
```

**Close Process Log:**

Run the following to finalize the process log:

```bash
SKILL_NAME="scholar-respond"
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

### Response Letter Quality
- [ ] Every reviewer comment has a numbered response — no skipped items
- [ ] Every response includes a specific revision action or explains why none was made
- [ ] Exact new text is quoted in the response (not just "we revised this")
- [ ] Page/line numbers given for all revisions in the response letter
- [ ] Response tone is respectful throughout, even when disagreeing
- [ ] Changes Summary Table included and matches actual changes

### Cross-Reviewer Handling
- [ ] Cross-reviewer overlaps identified and noted explicitly in letter
- [ ] Conflicting reviewer demands named and resolved with rationale
- [ ] Editor priorities addressed first and most thoroughly

### Citation and Reference Integrity
- [ ] Local reference library checked for all reviewer-requested citations
- [ ] CrossRef API used as fallback for citations not in local library
- [ ] All newly cited works added to reference list
- [ ] No orphaned citations (cited in text but missing from references)

### Word Count and Formatting
- [ ] Word count verified against journal limit after revisions
- [ ] Word impact tracked per revision item
- [ ] Abstract updated if findings or framing changed
- [ ] Tracked changes / blue text applied consistently

### Causal Language
- [ ] **Causal language audit passed**: response letter and revised text maintain the manuscript's language precision — if study is non-causal, do not upgrade to causal language even when responding to reviewers. See scholar-write SKILL.md for full rule

### Consistency
- [ ] Table/figure references match actual tables/figures
- [ ] Hypothesis labels (H1, H2...) consistent across all sections
- [ ] Contribution statement in Introduction reflects revisions
- [ ] No new analyses or content added beyond what reviewers requested (R2+ rule)

### Round-Specific
- [ ] R&R round noted in all output files
- [ ] Tone calibrated to round (R1 thorough; R2 direct; R3 surgical)
- [ ] R2+ new comments flagged as [NEW-IN-R2+]
- [ ] Cover letter matches round and revision scope

See [references/response-templates.md](references/response-templates.md) for complete letter templates and phrase bank.
See [references/common-concerns.md](references/common-concerns.md) for common reviewer concerns by journal and method type, conflict resolution templates, reviewer personality guide, and resubmission strategy.
