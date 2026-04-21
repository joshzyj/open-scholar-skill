# Section-Specific Standards (Step 2)

This file is loaded on demand by `scholar-write/SKILL.md`. It contains the detailed structural templates and writing guidance for each manuscript section.

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

**Literature Claims Verification (MANDATORY for Theory/Lit Review and Introduction):**

When citing prior work, every characterization of what a study found or argued must be verifiable. LLMs frequently generate plausible-sounding but subtly inaccurate summaries of papers (e.g., attributing phrases the author never used, overstating the strength of a finding, conflating two different papers' contributions).

For each cited claim in the Theory/Lit Review section, apply this check:

| Claim type | Verification method | If unverifiable |
|---|---|---|
| "Author (Year) found/showed/documented [specific finding]" | Check against Verified Citation Pool entry, knowledge graph, or PDF. Does the paper actually report this finding? | Hedge: "Author (Year) studied [topic]" without specifying the finding, or mark `[VERIFY: does Author Year actually show X?]` |
| "Author (Year) argued/theorized [specific argument]" | Check if the paper actually makes this argument. LLMs often attribute theoretical claims to empirical papers. | Soften to "Building on Author's (Year) work on [topic], we argue..." |
| "Author (Year) coined/developed [concept/term]" | Verify the concept is actually from this paper, not a later interpretation of it. | Use "The concept of X (Author Year)" without claiming coinage unless verified. |
| "Studies have shown that [general claim] (Author1 Year; Author2 Year)" | Check each cited paper individually. LLMs often list citations that are topically related but do not actually support the specific claim. | Replace with the specific finding each paper does support, or flag `[CITATION SUPPORT NEEDED]`. |

**Common LLM distortion patterns to watch for:**
1. **Paraphrase drift**: "Zhou and Cai (2002) documented dual-function institutions" — did they actually use this term, or is the LLM imposing a label?
2. **Strength inflation**: "Barreto et al. (2009) showed that ethnic media *was the primary driver*" — did they actually claim primacy, or just a significant effect?
3. **Finding conflation**: Attributing a finding from Paper A to Paper B because both study the same topic.
4. **Anachronistic framing**: Describing an older paper using terminology that only emerged later.

If the Verified Citation Pool contains the paper's abstract, key findings, or knowledge graph entry, verify against those. If not available, hedge the characterization or flag for manual verification.

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

**HARD PROSE RULES for Analytic Strategy / Methods (enforced by scholar-polish P19–P24)**:

1. **No bulleted model ladders.** A specification registry or design pre-mortem table lists models M1–MN as flat rows because those artifacts are machine-readable. In the manuscript, translate each row into a clause within running prose, with the model ID in parentheses: `(Table 2, M3)` or `(M3)`. NEVER render models as a bullet list of `- M3 (label): formula` items. Downstream verification (e.g., `scholar-verify` Stage 2 verify-logic) matches IDs anywhere in prose, not just flat bullets.
2. **No bulleted robustness batteries.** Translate R1–RN into one or two paragraphs organized by *theme* (measurement, weighting, population, functional form), not by registry index. Registry IDs appear parenthetically at the end of each clause.
3. **No inline equations in prose.** Equations belong in a displayed-math block, a footnote, or the replication code — never inside a narrative bullet or sentence body.
4. **No named compliance subsections.** Do not create subsections titled "Language Discipline", "Inferential Approach", "Ethical Commitment", "Associational Framing", "Analytic Protocol", or similar. If the paper needs to signal associational framing, fold it into one or two sentences in the opening or closing paragraph of §4. Named compliance subsections are an LLM tell that seasoned reviewers read as machine output.
5. **At most two subsections under §4 Methods.** Typical pattern: `§4.1 Main specification`, `§4.2 Robustness`. Three-way splits (estimation / models / language) are pipeline-motivated, not reader-motivated — collapse.
6. **Paragraph count ≥ bullet count in §4.** §4 in a JMF/ASR/Demography paper is 600–1000 words across 3–5 paragraphs. If the draft has more bullets than paragraphs, rewrite to prose before sending the draft to verification.

See `scholar-write/references/methods-prose-examples.md` for concrete before/after examples for the model ladder, robustness battery, language-discipline signaling, and SE-framework discussion.

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

**Description vs. Interpretation Separation (MANDATORY):**

For each RQ/hypothesis subsection in Results, enforce this three-layer structure:

```
Layer 1 — DESCRIPTION (pure numbers):
  Report the raw distributions, percentages, means, or counts.
  No characterizing labels. Just: "X is [value], Y is [value]."
  Include BOTH cross-group and within-group comparisons when comparing groups.

Layer 2 — MODEL RESULTS (coefficients and significance):
  Report regression coefficients, AMEs, CIs, p-values.
  Reference the specific table and model.

Layer 3 — INTERPRETATION (what this means — CLEARLY MARKED):
  Begin with a signal phrase: "These patterns indicate...", "We interpret this as..."
  The interpretation MUST reference specific numbers from Layers 1-2.
  Flag any label or concept introduced here as an interpretive choice:
    "We term this pattern [X]" or "This is consistent with [theoretical concept]"
```

**Why this matters:** When description and interpretation are mixed in the same sentences, interpretive errors (mislabeling patterns, choosing framings that obscure within-group realities) become invisible because they look like empirical statements. Separating them forces the interpretation to be traceable to specific numbers and makes it easier for reviewers (human or automated) to check whether the label fits the data.

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
6. Generalizability assessment (see below)
7. Preemptive objections (see below)
8. Contributions: What does the paper add?
9. Limitations: Honest, focused, not exhaustive
10. Future research directions
11. Conclusion: Broad societal or intellectual significance
```

**Generalizability assessment** (include in every Discussion):
- Compare the analytic sample to the target population (representativeness check)
- Interpret the estimand (LATE/ATT/ATE) and what population the causal effect applies to
- Revisit scope conditions from the Theory section in light of actual results
- State explicitly: "These findings generalize to [population/context] but may not extend to [boundary]."

**Preemptive objections** (include in every Discussion):
- Retrieve the alternative explanations table from the Theory section (if available from scholar-hypothesis or scholar-lit-review-hypothesis output)
- Map each alternative explanation to the specific robustness check that addresses it
- Write 1–2 paragraphs preemptively addressing the most likely reviewer objections (endogeneity, omitted variable bias, measurement error, selection bias, reverse causality)
- Frame as: "One concern is that [objection]. We address this by [robustness check], which shows [result]."

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
