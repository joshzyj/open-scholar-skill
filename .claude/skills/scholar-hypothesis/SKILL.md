---
name: scholar-hypothesis
description: "Develop theoretically grounded hypotheses and draft publication-ready Theory sections. Covers puzzle framing (5 types: anomaly, contradiction, extension, mechanism, scope), framework selection from 25+ sociological/linguistic theories (stratification, networks, culture, institutional, life course, analytical sociology via Coleman's boat + Hedström DBO, intersectionality, racial formation, social movements, status characteristics, signaling, non-Western: guanxi/Ubuntu/coloniality/world-systems), mechanism chain specification, hypothesis formalization (7 types: directional, interaction, mediation, curvilinear, comparative, boundary, null-as-finding) with formal and competing-prediction tables, text-based DAG construction (routes to /scholar-causal), and journal-calibrated drafts (ASR/AJS 1000–1500 words; Demography 600–1000; NHB/Science Advances 300–600 in Introduction; NCS 200–400; qualitative propositions). Saves internal theory log + section draft. Use after /scholar-lit-review and before /scholar-design."
tools: Write, Bash, WebSearch, Read
argument-hint: "[phenomenon or RQ] — optionally: [design type: quant/qual/comp/computational] [journal: ASR/AJS/Demography/NHB/NCS/SciAdv] [theory hint]"
user-invocable: true
---

# Scholar Hypothesis Development

You are an expert sociologist helping develop theoretically grounded, testable hypotheses and theory sections for publication-quality papers. Your output must meet the standards of ASR, AJS, Demography, Nature Human Behaviour, Science Advances, or Nature Computational Science.

## Arguments

The user has provided: `$ARGUMENTS`

Parse:
- **Focal phenomenon / RQ**: What is being explained?
- **Population / Context**: Who/where/when?
- **Design type**: quantitative observational | experimental | qualitative | comparative historical | computational
- **Target journal**: ASR / AJS / Demography / NHB / Science Advances / NCS / Language in Society / other
- **Theory hint**: Did the user name a theory? If so, start there.

---

## Step 0: Dispatch

### 0a. Create output directories

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
mkdir -p "${OUTPUT_ROOT}/theory" "${OUTPUT_ROOT}/logs"
```

**Process Logging (REQUIRED):**

Initialize the process log NOW by running:

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
mkdir -p "${OUTPUT_ROOT}/logs"
SKILL_NAME="scholar-hypothesis"
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
SKILL_NAME="scholar-hypothesis"
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


### 0b. Route

Use this table to route based on design type and $ARGUMENTS keywords.

| Design type | Route |
|-------------|-------|
| `regression`, `panel`, `survey`, `observational` | Full Steps 1–8 → directional H, mechanism chain |
| `experiment`, `RCT`, `conjoint`, `causal` | Steps 1–8 + Step 6 DAG; flag `/scholar-causal` for identification |
| `interview`, `ethnography`, `qualitative` | Steps 1–5 → propositional claims (not numbered H) |
| `comparative`, `historical`, `macro` | Steps 1–5 → comparative H; world-systems / institutional logics |
| `NLP`, `ML`, `text`, `network`, `ABM`, `computational` | Steps 1–4 → predictive vs. explanatory framing; NCS template in Step 7 |
| `intersectionality`, `race × gender`, `multiple axes` | Steps 1–5 + intersectionality module in Step 4 |
| `language`, `sociolinguistics`, `discourse` | Steps 1–7 → linguistic capital / accommodation / ideologies frameworks |

**Query knowledge graph first** (if available) — the KG stores pre-extracted theories, mechanisms, and inter-paper relationships from prior sessions:

```bash
SKILL_DIR="${SCHOLAR_SKILL_DIR:-.}/.claude/skills"
KG_REF="$SKILL_DIR/_shared/knowledge-graph-search.md"
if [ -f "$KG_REF" ]; then
  eval "$(cat "$KG_REF" | sed -n '/^```bash/,/^```/p' | sed '1d;$d')" 2>/dev/null
  if kg_available; then
    echo "=== Knowledge Graph: theories for [TOPIC] ==="
    kg_search_concepts "[TOPIC]" 15 theory
    echo ""
    echo "=== Knowledge Graph: mechanisms for [TOPIC] ==="
    kg_search_concepts "[TOPIC]" 10 mechanism
    echo ""
    echo "=== Knowledge Graph: papers on [TOPIC] ==="
    kg_search_papers "[TOPIC]" 15 | kg_format_papers
    echo ""
    echo "[KG] $(kg_count)"
  else
    echo "[KG] Knowledge graph empty — proceeding to local library search"
  fi
else
  echo "[KG] scholar-knowledge not installed — proceeding to local library search"
fi
```

Use KG results to: (1) pre-identify candidate theoretical frameworks before Step 2, (2) find contested findings that motivate puzzle framing in Step 1, (3) locate mechanism chains already tested in prior literature.

Then run a **local reference library search** for the focal phenomenon to identify foundational theory papers.

```bash
# Load multi-backend reference search infrastructure
# Sources all backend search functions and runs auto-detection to set $REF_SOURCES, $REF_PRIMARY, $ZOTERO_DB, etc.
SKILL_DIR="${SCHOLAR_SKILL_DIR:-.}/.claude/skills"
eval "$(cat "$SKILL_DIR/_shared/refmanager-backends.md" | sed -n '/^```bash/,/^```/p' | sed '1d;$d')"

# Unified search — queries all detected backends (Zotero, Mendeley, BibTeX, EndNote XML)
# Note: scholar_search now also queries the knowledge graph as Tier 0.5 if available
scholar_search "[focal_phenomenon]" 15 keyword
```

> **CITATION INTEGRITY:** Only cite papers found via the search above or carried forward from prior phases (e.g., scholar-lit-review). Claude's training-data memory of citations is NOT reliable. If a theoretical claim needs a citation not found in the search results, use `[CITATION NEEDED: description]` rather than guessing author names or publication details.

---

## Step 1: Frame the Explanatory Puzzle

Every strong theory section opens with a clearly stated puzzle. Choose the puzzle type that best fits the RQ:

| Puzzle type | Structure | Example opening |
|-------------|-----------|-----------------|
| **1. Anomaly** | Existing theory predicts X, but Y is observed — why? | "Theory A predicts [X]. Yet [evidence shows Y]. Why does [Y] occur?" |
| **2. Contradiction** | Theory A predicts +, Theory B predicts − → which is right and when? | "Two theoretical traditions offer opposing predictions for [phenomenon]. Theory A suggests [+]; Theory B suggests [−]. We adjudicate..." |
| **3. Extension** | Effect established for Group/Context A → does it generalize to B? | "Prior work has established [effect] among [Group A]. Whether this pattern holds for [Group B] in [Context C] remains unexplored." |
| **4. Mechanism** | Correlation is documented, but the mechanism is unknown | "[X] and [Y] are correlated (Cite). Yet the mechanism linking them remains underspecified..." |
| **5. Scope condition** | Effect known in C1 → does it hold under C2 / for Group B? | "The [effect] has been documented in [C1]. Whether it holds under [C2] — where [structural condition differs] — is an open question." |

For each puzzle, state:
1. **Theoretical stakes**: Which theoretical debate does resolution advance?
2. **Empirical contribution**: What data/context makes this test novel?
3. **Scope conditions**: Who / where / when does the puzzle apply?

---

## Step 2: Select Theoretical Framework(s)

Use the compact selection guide below, then consult `references/theory-frameworks.md` for full details, mechanism language, and key citations.

### Quick Selection Guide

| Research question | Primary framework | Useful secondary |
|-------------------|-------------------|-----------------|
| Why do early advantages persist? | Cumulative advantage (DiPrete & Eirich 2006) | Life course, social closure |
| How do people find jobs? | Strength of weak ties (Granovetter 1973); Structural holes (Burt 1992) | Social capital (Lin 2001) |
| Why do credentials matter beyond skills? | Signaling theory (Spence 1973); Credentialism (Collins 1979) | Social closure (Parkin 1979) |
| How do norms/practices spread? | Network diffusion (Centola & Macy 2007) | Isomorphism (DiMaggio & Powell 1983) |
| Why do racial/ethnic gaps persist? | Racial formation (Omi & Winant 1994); Social closure | Symbolic boundaries (Lamont) |
| How do categories and institutions sustain inequality? | Categorical inequality (Tilly 1998) | Institutional logics |
| Why do group outcomes differ after controlling for individual attributes? | Structural racism; Categorical inequality | Status characteristics (Berger) |
| How do inequalities differ by multiple axes? | Intersectionality (Collins; Crenshaw) | Status attainment (Blau & Duncan) |
| How do immigrants adapt? | Segmented assimilation (Portes & Zhou 1993) | New assimilation (Alba & Nee 2003) |
| Why does language change across generations? | Language shift (Fishman 1991) | Linguistic capital (Bourdieu 1991) |
| How do movements emerge and succeed? | Political opportunity structure (McAdam 1982) | Resource mobilization (McCarthy & Zald 1977) |
| Why do organizations converge on similar structures? | Isomorphism (DiMaggio & Powell 1983) | Institutional logics |
| What explains variation in well-being across life stages? | Life course (Elder 1994) | Cumulative disadvantage |
| How do people reason and act in ambiguous situations? | Frames/schemas (Goffman; Vaisey 2009) | Dual-process models |
| Why is inequality reproduced in education? | Cultural capital (Bourdieu 1984) | Status attainment; signaling |
| China / East Asia context | Guanxi (Bian 1997); Confucian social theory | Network theory, status attainment |
| Global South / comparative | World-systems (Wallerstein 1974); Coloniality (Quijano 2000) | Southern theory (Connell 2007) |
| Group status hierarchies in interaction | Status characteristics (Berger et al. 1977) | Expectation states theory |
| Individual rationality and incentives | Rational choice (Coleman 1990); Signaling | Social exchange theory |

**Framework pairing rule**: Most strong papers use one primary framework (main causal claim) + one secondary framework (moderating condition, scope condition, or alternative that is ruled out).

---

### Step 2b: Determine Hypothesis Placement Mode

Hypothesis placement — whether hypotheses appear as a **separate block** at the end of the theory section or are **blended into** each thematic subsection — is determined by journal norms:

| Target journal | Default mode | Rationale |
|---------------|-------------|-----------|
| **ASR / AJS / Social Forces** | **BLENDED** | These journals favor thematic subsections where each argument thread concludes with its own hypothesis. Especially appropriate with 3+ hypotheses covering distinct mechanisms or subgroups. |
| **Demography** | **SEPARATE** (BLENDED if 3+ H) | Demography papers use concise conceptual frameworks; 1–2 hypotheses work best in a dedicated block. With 3+ hypotheses, blend into subsections for readability. |
| **NHB / Science Advances** | **SEPARATE (predictions)** | No numbered hypotheses. State predictions as natural-language sentences in the Introduction. Hypotheses are embedded as prediction statements, not labeled H1/H2. |
| **NCS** | **SEPARATE (predictions)** | Brief prediction statements inline in Introduction or Methods framing. No formal H labels. |
| **Language in Society / qualitative** | **N/A** | Propositional claims, not numbered hypotheses. No placement choice needed. |

**Apply the mode:**
- **BLENDED**: Each hypothesis is stated at the end of the subsection that develops its theoretical argument. The theory section has thematic subsections (e.g., "Network Mechanisms and Occupational Sorting," "Institutional Barriers and Credential Devaluation"), each ending with its derived hypothesis.
- **SEPARATE**: All hypotheses appear together in a dedicated block after the full theoretical argument is developed.
- **SEPARATE (predictions)**: Hypotheses are stated as natural-language predictions without H1/H2 labels.

Record the placement mode for downstream use by `scholar-write`:
```
HYPOTHESIS_PLACEMENT: [BLENDED / SEPARATE / SEPARATE-PREDICTIONS / N/A]
```

---

## Step 3: Specify the Mechanism Chain

Make the mechanism **explicit and falsifiable**, not a black box. Use one of two analytical sociology frameworks:

### Option A — Coleman's Macro-Micro-Macro Boat

```
MACRO level ─────────────────────────────────► MACRO level
     │                                               ▲
     │ (situational         (aggregation             │
     │  mechanism)          mechanism)               │
     ▼                                               │
MICRO level:  Individual situation ──►  Individual action
              (beliefs, resources,       (choice, behavior,
               opportunities)            response)
```

**Fill in**:
- **Macro condition**: What structural or macro-level variable is the cause?
- **Situational mechanism** (macro→micro): How does the macro condition shape individuals' situations, opportunities, beliefs?
- **Action mechanism** (micro→micro): Given their situation, what do individuals do? Why? (Use Hedström's DBO below)
- **Aggregation mechanism** (micro→macro): How do many individuals' actions produce the macro outcome?

**Example (returns to education across racial groups)**:
```
Structural racism (macro) → Differential credential credibility by race (situational)
→ Employers discount credentials from Black workers (action: statistical discrimination)
→ Black-White wage gap persists above skill differences (macro outcome)
```

### Option B — Hedström's DBO (Desires-Beliefs-Opportunities)

Specify for the focal actor:

| Component | Question | Example |
|-----------|----------|---------|
| **Desires (D)** | What does the actor want? | Job security, status, belonging |
| **Beliefs (B)** | What does the actor believe about the situation? | "Employers will discount my degree" |
| **Opportunities (O)** | What can the actor realistically do? | Credential acquisition, network activation |
| **Action (A)** | Given D + B + O, what does the actor do? | Invest in additional signals; leave the field |
| **Aggregation** | How do many such actions produce the macro pattern? | → Occupational segregation |

### Mechanism Type Classification

Classify the mechanism using Elster's (1989) taxonomy to strengthen the theoretical claim:

| Mechanism type | Definition | Example |
|---------------|-----------|---------|
| **Cognitive** | How actors perceive, categorize, or interpret information | Schema activation, framing effects, stereotypes |
| **Motivational** | How incentives, expectations, or emotions drive action | Expected value, threat response, status anxiety |
| **Interactional** | How actors respond to and influence each other | Social comparison, peer effects, reference groups |
| **Institutional** | How rules, roles, and enforcement shape action | Credential requirements, organizational policies |
| **Material** | How resource access and constraints operate | Wealth accumulation, geographic access, time |

**Scope Condition Matrix** (required output):

| Dimension | Scope | Rationale | Prediction |
|---|---|---|---|
| Population | [Which groups?] | [Why mechanism differs by group] | [Direction/magnitude by group] |
| Institutional context | [Which settings?] | [Why context matters for mechanism] | [Stronger/weaker where?] |
| Temporal | [Which time periods?] | [Why mechanism is period-dependent] | [Effect before/after threshold] |
| Threshold/dosage | [Is there a minimum dose?] | [Why effect is nonlinear] | [Below X: null; above X: positive] |

---

## Step 4: Derive and Formalize Hypotheses

### Derivation Chain (MANDATORY — complete before writing any hypothesis)

Each hypothesis MUST trace through a full derivation chain. Before formalizing hypotheses, write this table:

| H# | Literature finding that creates the gap | Gap type (from Step 1 puzzle) | Framework prediction (from Step 2) | Mechanism chain link (from Step 3) | Hypothesis |
|----|----------------------------------------|-------------------------------|------------------------------------|------------------------------------|------------|
| H1 | "[Finding X] is established, but [gap]" (Author Year) | Mechanism / Population / Identification / Debate | "[Framework] predicts [direction] because [core claim]" | "[Step in Coleman's boat or DBO]: [specific link]" | "H1: [formal statement]" |
| H2 | "[Finding Y] holds for Group A but untested for Group B" | Population / Scope | "[Framework] predicts [moderation] because [scope condition]" | "[Situational mechanism differs for Group B because...]" | "H2: [formal statement]" |

**Derivation chain rule**: If you cannot fill every column for a hypothesis, the hypothesis is not theoretically grounded. Either (a) trace it back to a specific framework prediction and mechanism step, or (b) drop it and replace with a hypothesis that IS derivable from the theory.

**Common failure**: Hypotheses that match the framework's *general* predictions but don't connect to any *specific* mechanism step from Step 3. Fix: point to the exact situational, action, or aggregation mechanism that generates the prediction.

### Hypothesis Types (7)

Select the type(s) that match the mechanism chain from Step 3.

---

**Type 1 — Main effect (directional)**

Use when: Mechanism predicts a monotonic relationship.

> **H[N]**: [Variable X] is [positively/negatively] associated with [Outcome Y] among [Population Z].

Derivation note: State the causal logic in one sentence before the hypothesis: *"Because [mechanism M], individuals/groups with higher [X] should have [higher/lower] [Y]."*

---

**Type 2 — Moderation / Interaction**

Use when: The mechanism operates differently for different groups or contexts.

Two sub-types:

> **H[N]a (fan-spread)**: The [positive/negative] effect of [X] on [Y] is stronger for [Group A] than for [Group B].

> **H[N]b (crossover)**: The effect of [X] on [Y] is [positive] for [Group A] but [negative/null] for [Group B].

Derivation note: *"The mechanism [M] is stronger/absent for [Group B] because [scope condition], producing a [fan-spread/crossover] interaction."*

---

**Type 3 — Mediation / Mechanism test**

Use when: You are testing the process through which X affects Y.

> **H[N]**: The association between [X] and [Y] is [partially/fully] mediated by [Mediator M], consistent with [mechanism name].

Derivation note: *"If the mechanism is [M], then [X] should predict [M] (a), and [M] should predict [Y] net of [X] (b), and the indirect path [X→M→Y] should account for [a portion of / all of] the total effect."*

---

**Type 4 — Curvilinear / Threshold**

Use when: Theory predicts diminishing returns, saturation, or a threshold.

> **H[N]a (inverted-U / U-shape)**: The effect of [X] on [Y] follows an [inverted-U / U-shaped] curve, [increasing/decreasing] beyond [threshold T].

> **H[N]b (threshold)**: [X] affects [Y] only above [threshold T] / only when [condition C] is met.

---

**Type 5 — Comparative / Group-level difference**

Use when: The theoretical argument is about group-level outcomes, not individual-level regression coefficients.

> **H[N]**: [Group/Context A] has [higher/lower] [Outcome Y] than [Group/Context B] because [mechanism M] operates more strongly / is absent in [B].

---

**Type 6 — Boundary condition / Scope**

Use when: You are testing the limits of an established effect.

> **H[N]**: The effect of [X] on [Y] established in [prior context C1] does not generalize to [new context C2], because [mechanism M] does not operate under [structural condition Z].

---

**Type 7 — Null-as-finding (theoretically predicted null)**

Use when: Theory predicts *no* association, and the null is the interesting result.

> **H[N] (null)**: We expect no association between [X] and [Y] among [Population Z] because [mechanism is absent under condition C], in contrast to [prior study in different context C1].

---

### Intersectionality Hypotheses (special form)

When theory predicts multiplicative — not additive — effects:

> **H[N] (intersectional)**: The effect of [X] on [Y] differs for [intersection group, e.g., Black women] in ways not reducible to [race alone] or [gender alone], because [mechanism M] operates uniquely at the intersection.

Formal specification:
```
Additive (NOT intersectional): Y = α + β₁(Black) + β₂(Female) + ε
Intersectional test:            Y = α + β₁(Black) + β₂(Female) + β₃(Black×Female) + ε
  → H: β₃ ≠ 0; state predicted sign and mechanism for β₃
```

---

### Hypothesis Table

After deriving hypotheses, produce this table. The "Gap addressed" and "Mechanism chain link" columns enforce traceability — every H must connect to a specific gap and a specific step in the mechanism chain from Step 3.

| H# | Statement (one sentence) | Type | Direction | Gap addressed | Theoretical basis | Mechanism chain link | Analytic approach |
|----|--------------------------|------|-----------|---------------|-------------------|---------------------|-------------------|
| H1 | | Main effect | + | [Which gap from Step 1] | [Framework, Author Year] | [Which step: situational/action/aggregation] | OLS / logit / FE |
| H2 | | Moderation | crossover | [Which scope condition] | [Framework, Author Year] | [Which DBO component differs] | Interaction term |
| H3 | | Mediation | — | [Mechanism gap] | [Framework, Author Year] | [Which mediating process from Step 3] | Causal mediation / FE |
| H4 | | Boundary | null | [Scope condition gap] | [Framework, Author Year] | [Why mechanism absent here] | Subsample comparison |

**Traceability check**: Every row must have non-empty "Gap addressed" and "Mechanism chain link" entries. If a hypothesis cannot point to a specific mechanism step, it is under-theorized — revise it or trace it through the mechanism chain first.

---

## Step 5: Map Competing Predictions

For each hypothesis, state what a competing theory predicts and how the data distinguishes them:

| Hypothesis | Your theory → prediction | Competing theory → prediction | What the data would show if competitor is right | How to distinguish |
|------------|--------------------------|-------------------------------|------------------------------------------------|-------------------|
| H1 | [Theory A] → [+] | [Theory B] → [−/null] | [B's prediction would look like...] | [Key diagnostic test or subgroup] |
| H2 | [Theory A] → crossover | [Theory B] → fan-spread only | [B's prediction for Group A...] | [Interaction vs. main-effect comparison] |

**Alternative explanations checklist:**
- [ ] Selection into [X] (non-random exposure)
- [ ] Reverse causation ([Y] causing [X])
- [ ] Omitted variable bias (unobserved [Z] drives both)
- [ ] Measurement artifact (measurement error in [X] or [Y])
- [ ] Compositional differences (groups differ on [covariates])

State for each: "We address [alternative] by [design feature / robustness check]."

---

## Step 6: Build the Text-Based DAG / Causal Graph

Produce a text-based directed acyclic graph of the theoretical model:

```
CAUSAL STRUCTURE:

[Confounder C] ──────┐
                     ▼
[Treatment X] ──────► [Outcome Y]
        │                  ▲
        ▼                  │
[Mediator M] ─────────────►│

[Moderator Z] ─── (moderates X→Y pathway)

LEGEND:
  ──► : causal path
  - - : controlled/adjusted path
  [C] : measured confounder (include in model)
  [U] : unmeasured confounder (threat to identification)
```

**Fill in**:
- Treatment / independent variable: [X]
- Outcome: [Y]
- Mediators: [list]
- Moderators: [list]
- Key confounders (measured): [list]
- Key threats (unmeasured): [list]

**Causal identification flag**: If the goal is causal inference (not description), note:
> "For a complete causal identification strategy (DiD / RD / IV / FE / matching / synthetic control), invoke `/scholar-causal` after completing this theory section."

---

## Step 7: Write the Theory Section

Use the journal-specific template that matches the target journal from $ARGUMENTS.

---

### Template A — ASR / AJS (1,000–1,500 words; separate "Theory" section)

**Default placement: BLENDED** — each thematic subsection ends with its derived hypothesis. This mirrors the dominant pattern in recent ASR/AJS publications, especially with 3+ hypotheses.

#### Template A-BLENDED (default for ASR/AJS)

```
¶1 — THEORETICAL ORIENTATION (100–150 words)
[Restate the puzzle from Step 1. Announce the theoretical framework(s) you draw on.
Signal what is theoretically novel about this paper.]

"[Phenomenon] has received considerable attention [cite 2–3]. Yet the mechanisms
underlying [X → Y] remain underspecified. We draw on [Framework 1] and
[Framework 2] to argue that [core theoretical claim]."

### [Thematic Subsection 1: e.g., "Network Mechanisms and Occupational Sorting"]

¶2–3 — FIRST THEORETICAL ARGUMENT (300–500 words)
[Develop the first mechanism in detail. Review relevant literature for this
specific argument thread. Define key concepts. Cite foundational works.
Use Coleman's boat / DBO logic.]

"According to [Theory], [Mechanism M1] operates when [condition C]. In the
context of [this paper's setting], [X] creates [situation] for [actors], who
respond by [action], producing [outcome Y] in the aggregate."

¶4 — HYPOTHESIS 1 (1–2 sentences derivation + H1 statement)
[Derive H1 directly from the argument just developed.]

"Because [mechanism M1], we expect [direction]. We therefore hypothesize:
H1: [formal statement]."

### [Thematic Subsection 2: e.g., "Institutional Barriers and Credential Devaluation"]

¶5–6 — SECOND THEORETICAL ARGUMENT (200–400 words)
[Develop the second argument thread — moderation, mediation, or a distinct
mechanism. Review the literature specific to this sub-argument.]

"The [primary mechanism] should be stronger for [Group A] than [Group B] because
[scope condition logic]. [Group A] faces [structural position that amplifies/creates
the mechanism]; [Group B] does not because [reason]."

¶7 — HYPOTHESIS 2 (1–2 sentences derivation + H2 statement)
[Derive H2 from the subsection argument.]

"We therefore predict:
H2: [formal statement — moderation/mediation/boundary]."

### [Additional subsections as needed — each ending with its hypothesis]

### Alternative Explanations

¶N — ALTERNATIVE EXPLANATIONS (150–250 words)
[Acknowledge the strongest 2 alternative explanations. State briefly why
your design/data can adjudicate between your theory and the alternative.]

"One might argue that [alternative explanation]. We address this possibility
by [design feature]. A second alternative, [X], would predict [Y] regardless
of [mechanism]. Our analysis distinguishes between these predictions by [test]."

¶N+1 — ANALYTIC PREVIEW (50–100 words)
"To test these hypotheses, we use [data] and [analytic strategy]. [One sentence
on why the design maps onto the theoretical claims.]"
```

#### Template A-SEPARATE (fallback for ASR/AJS with 1–2 hypotheses)

```
¶1 — THEORETICAL ORIENTATION (100–150 words)
[Restate the puzzle. Announce framework(s).]

¶2–3 — PRIMARY THEORETICAL ARGUMENT (300–500 words)
[Develop the primary mechanism in detail.]

¶4–5 — SECONDARY ARGUMENT / MODERATION (200–400 words)
[Develop the second-order argument.]

¶6 — HYPOTHESES (all together)
"We derive the following predictions from this framework:
H1: [formal statement].
H2: [formal statement]."

¶7 — ALTERNATIVE EXPLANATIONS (150–250 words)

¶8 — ANALYTIC PREVIEW (50–100 words)
```

---

### Template B — Demography (600–1,000 words; "Conceptual Framework" or "Background")

**Default placement: SEPARATE** (switch to BLENDED if 3+ hypotheses).

#### Template B-SEPARATE (default for Demography with 1–2 hypotheses)

```
¶1 — DEMOGRAPHIC / POPULATION FRAMING (100–150 words)
[Start from the macro demographic pattern. State the population-level trend
or disparity to be explained. Anchor in vital statistics or census estimates.]

"[Population group] has experienced [demographic trend: rising/falling
X rate] since [period] [cite]. Understanding the determinants of this
[trend/disparity] requires specifying the mechanisms operating at
[individual / household / community] level."

¶2 — THEORETICAL MECHANISM (200–350 words)
[Specify the life-course / demographic mechanism. Common frameworks:
cohort and period effects; age-period-cohort decomposition; life-course
timing and linked lives; demographic metabolism.]

¶3 — HYPOTHESIS DERIVATION
"We derive two predictions from this framework:
H1: [main effect]
H2: [heterogeneity by cohort/age/parity/race]"

¶4 — HETEROGENEITY / SUBGROUP ARGUMENT (150–250 words)
[Demography papers must explain why effects differ by race, education,
parity, or cohort. Ground this in demographic heterogeneity theory.]

¶5 — ANALYTIC PREVIEW (50–100 words)
```

#### Template B-BLENDED (for Demography with 3+ hypotheses)

```
¶1 — DEMOGRAPHIC / POPULATION FRAMING (100–150 words)
[Same as above: macro trend, vital statistics anchor.]

### [Mechanism 1: e.g., "Cohort Differences in Exposure"]

¶2 — FIRST MECHANISM + LITERATURE (200–300 words)
[Develop the first demographic mechanism with supporting literature.]

¶3 — H1 DERIVATION
"Because [mechanism 1], we predict:
H1: [main effect]."

### [Mechanism 2: e.g., "Heterogeneity by Race and Education"]

¶4 — SECOND MECHANISM + LITERATURE (150–250 words)
[Develop the heterogeneity argument with subgroup-specific evidence.]

¶5 — H2 AND H3 DERIVATION
"H2: [heterogeneity prediction].
H3: [additional subgroup prediction]."

¶6 — ANALYTIC PREVIEW (50–100 words)
```

---

### Template C — NHB / Science Advances (300–600 words; embedded in Introduction)

```
[Do NOT write a separate Theory section. Embed hypotheses in ¶3–4 of
the Introduction, after the knowledge-gap sentence.]

"Despite this progress, it remains unclear [knowledge gap]. Three
theoretical mechanisms may account for [X → Y]. First, [Mechanism A]
predicts [+] because [brief logic]. Second, [Mechanism B] predicts [−]
under [scope condition]. Third, [Mechanism C] predicts [moderation] for
[group]. We test these mechanisms using [data + method]."

Hypotheses in NHB are stated as predictions, not as numbered formal
statements. Use language like:
— "We predicted that [X] would be positively associated with [Y]..."
— "We tested whether [mechanism M] accounts for the [X–Y] relationship..."

Length for this section in NHB: 3–5 sentences of theoretical framing
in the Introduction; explicit prediction sentences near the end of Introduction.
```

---

### Template D — NCS / Computational (200–400 words; in Introduction or Methods)

```
[Discovery framing — if the paper is descriptive/exploratory]:
"We use [method] to characterize [phenomenon] at scale. Rather than
testing a single theory, we describe [structural pattern] and examine
what theoretical frameworks best account for the variation we observe."

[Inferential framing — if the paper tests theoretical predictions]:
"Drawing on [Theory], we predict [X → Y], which we test using
[computational approach]. Our design allows us to [causal claim or scope]."

Hypotheses in NCS are often stated as predictive claims:
— "We hypothesize that [text/network feature] predicts [outcome]..."
— "Consistent with [theory], we expect [group difference]..."

Note: If the paper is a pre-registered computational study, state
explicitly: "These hypotheses were pre-registered at [OSF DOI] before
analysis commenced."
```

---

### Template E — Language in Society / Qualitative / Ethnographic

```
[Do NOT use numbered hypotheses. Use propositional claims.]

"Following [theoretical framework], we expect to find [pattern/practice/
discourse] among [community/group]. Our analysis examines whether
[Process P] operates differently for [Group A] vs. [Group B], and
what linguistic/interactional resources participants use to [accomplish goal]."

"We are particularly interested in how [macro-level discourse] is
instantiated in [interactional practice], as theorized by [framework]."
```

---

## Step 7b: Verification Check (before saving)

Before saving the theory section, run a self-verification checklist:
- [ ] Theory section reads as a single coherent argument, not a theory menu
- [ ] **Hypothesis placement mode** matches journal norms (Step 2b): BLENDED for ASR/AJS/Social Forces; SEPARATE for Demography (unless 3+ H); SEPARATE-PREDICTIONS for NHB/NCS/Science Advances
- [ ] **If BLENDED**: each thematic subsection ends with its derived hypothesis; subsection headings name the argument thread (not "Hypothesis 1")
- [ ] **If SEPARATE**: all hypotheses appear in a dedicated block; the theoretical argument is fully developed before any hypothesis is stated
- [ ] **Derivation chain table** (Step 4) is complete — every H has all columns filled (gap, framework prediction, mechanism chain link)
- [ ] Every hypothesis is logically derived from the stated framework + mechanism — not from the framework's *general* predictions but from a *specific* mechanism step in Step 3
- [ ] No hypothesis is derivable from "common sense" alone without the named framework — test: would a reader unfamiliar with [Framework] still predict this? If yes, the derivation is too weak
- [ ] At least 2 alternative explanations are named and addressed
- [ ] All hypotheses are directional, numbered, and mutually non-redundant
- [ ] Scope conditions are explicit (who, where, when the mechanism holds)
- [ ] All citations are from prior search results (no fabricated references)
- [ ] Mechanism specifies micro-foundations (beliefs, desires, opportunities, or equivalent)
- [ ] Each hypothesis in the **prose** includes a derivation sentence ("Because [specific mechanism step], we expect...") before the formal H statement
- [ ] Scope condition matrix is provided:

| Mechanism | Population Scope | Institutional Scope | Temporal Scope | Predicted Effect |
|---|---|---|---|---|

If any check fails, revise the draft before saving.

---

## Step 8: Save Output

Use the **Write tool** to save two files after completing all steps.

### Version Collision Avoidance (MANDATORY)

**Before EVERY Write tool call below**, run this Bash block to determine the correct save path. Do NOT hardcode paths from the filename templates — they show naming patterns only.

```bash
# MANDATORY: Replace [values] with actuals before running
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
# BASE pattern: ${OUTPUT_ROOT}/[slug]/theory/scholar-hypothesis-log-[topic-slug]-[YYYY-MM-DD]
# Split into directory and stem for the gate script:
OUTDIR="$(dirname "${OUTPUT_ROOT}/[slug]/theory/scholar-hypothesis-log-[topic-slug]-[YYYY-MM-DD]")"
STEM="$(basename "${OUTPUT_ROOT}/[slug]/theory/scholar-hypothesis-log-[topic-slug]-[YYYY-MM-DD]")"
mkdir -p "$OUTDIR"
bash "${SCHOLAR_SKILL_DIR:-.}/scripts/gates/version-check.sh" "$OUTDIR" "$STEM"
```

**Use the printed `SAVE_PATH` as `file_path` in the Write tool call.** Re-run this block (with the appropriate BASE) for each additional file. The same version suffix must be used for all related output files (.md, .docx, .tex, .pdf).

---

### File 1 — Internal Theory Log

**Filename**: `output/[slug]/theory/scholar-hypothesis-log-[topic-slug]-[YYYY-MM-DD].md`

```markdown
# Theory Log: [Topic] — [YYYY-MM-DD]

## Puzzle Type and Framing
- Type: [anomaly / contradiction / extension / mechanism / scope]
- Puzzle statement: [1–2 sentences]
- Theoretical stakes: [which debate does this resolve?]

## Hypothesis Placement
- Mode: [BLENDED / SEPARATE / SEPARATE-PREDICTIONS / N/A]
- Journal norm: [journal name → default mode rationale]
- Number of hypotheses: [N] (BLENDED threshold: 3+ for Demography)

## Framework(s) Selected
- Primary: [theory name, key author, year, mechanism]
- Secondary: [theory name, key author, year, role in argument]
- Rejected alternatives: [theory and reason not used]

## Mechanism Chain (Coleman's Boat / DBO)
- Macro condition: [X]
- Situational mechanism (macro→micro): [describe]
- Action mechanism (DBO): D=[...] B=[...] O=[...] A=[...]
- Aggregation mechanism (micro→macro): [describe]
- Mechanism type (Elster): [cognitive / motivational / interactional / institutional / material]

## Hypothesis Derivation Rationale
| H# | Derivation logic (why this type, why this direction) |
|----|------------------------------------------------------|
| H1 | |
| H2 | |

## Competing Predictions Assessment
| H# | Competitor | Prediction | Why data/design rules it out |
|----|------------|-----------|------------------------------|

## DAG Summary
- Treatment: [X]
- Outcome: [Y]
- Mediators: [list]
- Moderators: [list]
- Key measured confounders: [list]
- Key threats (unmeasured): [list]
- Identification flag: [/scholar-causal invoked: yes/no; strategy: ...]

## Reference Library Citations Found
[List key theory papers found in local reference library search]
```

---

### File 2 — Publication-Ready Theory Draft

**Filename**: `output/[slug]/theory/scholar-hypothesis-draft-[topic-slug]-[YYYY-MM-DD].md`

```markdown
# Theory Section Draft: [Topic] — [YYYY-MM-DD]
## Target journal: [journal]

---

## [Theory / Conceptual Framework / Background]

[Full prose theory section from Step 7, calibrated to target journal]

---

## Mechanism Diagram

[Text-based DAG from Step 6]

---

## Derivation Chain Table

| H# | Literature gap | Gap type | Framework prediction | Mechanism chain link | Hypothesis |
|----|---------------|----------|---------------------|---------------------|------------|
| H1 | | | | | |
| H2 | | | | | |

## Hypothesis Summary Table

| H# | Statement | Type | Direction | Gap addressed | Theoretical basis | Mechanism chain link |
|----|-----------|------|-----------|---------------|-------------------|---------------------|
| H1 | | | | | | |
| H2 | | | | | | |

---

## Competing Predictions

| H# | This paper predicts | Competing theory predicts | Key distinguishing test |
|----|--------------------|--------------------------|-----------------------|
```

**Close Process Log:**

Run the following to finalize the process log:

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
SKILL_NAME="scholar-hypothesis"
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

Confirm both file paths to user at end.

---

## Quality Checklist

- [ ] **Puzzle type** identified (anomaly / contradiction / extension / mechanism / scope condition)
- [ ] **Theoretical stakes** stated: which debate does this paper speak to?
- [ ] **Primary + secondary framework** selected and justified (not just listed)
- [ ] **Mechanism chain** specified using Coleman's boat or Hedström's DBO — NOT a black box
- [ ] **Mechanism type** classified (cognitive / motivational / interactional / institutional / material)
- [ ] **Scope conditions** stated: who / where / when does the mechanism operate?
- [ ] **Each hypothesis** derived from a named theory + specific mechanism — not atheoretical
- [ ] **Predictions are directional** — not "X is related to Y" but "X is positively/negatively associated with Y"
- [ ] **Hypothesis type correct**: interaction ≠ main effect; boundary ≠ moderation (direction vs. absence)
- [ ] **Intersectionality** (if applicable): multiplicative H stated; β₃ sign and mechanism specified
- [ ] **Competing predictions table** completed — at least 2 alternatives addressed
- [ ] **Alternative explanations** acknowledged with design response for each
- [ ] **Text-based DAG** produced — treatment, outcome, mediators, moderators, confounders labeled
- [ ] **Causal identification flag**: if causal inference is the goal, `/scholar-causal` flagged
- [ ] **Causal language calibrated to design**: if the study uses observational data without a causal identification strategy, hypothesis statements and theory prose use associational language ("is positively associated with," "predicts") rather than causal language ("causes," "leads to," "effect of"). Theory sections may describe hypothesized mechanisms with hedging ("may," "we theorize that"). See scholar-write SKILL.md for full rule
- [ ] **Hypothesis placement** matches journal norms: BLENDED for ASR/AJS/Social Forces; SEPARATE for Demography (BLENDED if 3+ H); SEPARATE-PREDICTIONS for NHB/NCS/SciAdv
- [ ] **If BLENDED**: thematic subsection headings are substantive (not "Hypothesis 1"); each subsection builds argument → derives H at end
- [ ] **Theory section** calibrated to journal word norms (ASR 1000–1500; Demo 600–1000; NHB 300–600)
- [ ] **Theory section reads as an argument**, not a textbook review of all theories
- [ ] **No fabricated citations** — all references from local library search or prior phases; uncertain citations flagged `[CITATION NEEDED]`
- [ ] **Claim verification** — all prose claims attributing findings to cited sources checked against KG/PDF; no `[CLAIM-REVERSED]`, `[CLAIM-MISCHARACTERIZED]`, `[CLAIM-OVERCAUSAL]`, or `[CLAIM-UNSUPPORTED]` markers remain. Run: `bash "${SCHOLAR_SKILL_DIR:-.}/scripts/gates/verify-claims.sh" "[output_file]"`
- [ ] **Theory log saved** to `output/[slug]/theory/scholar-hypothesis-log-[slug]-[date].md`
- [ ] **Theory draft saved** to `output/[slug]/theory/scholar-hypothesis-draft-[slug]-[date].md`

---

See [references/theory-frameworks.md](references/theory-frameworks.md) for detailed theoretical overviews, mechanism language, hypothesis language templates, and key citations for all 25+ frameworks.
