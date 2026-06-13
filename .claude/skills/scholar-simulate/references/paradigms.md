# Paradigms — When to Use Which (MODE 1: design)

This file is loaded by **MODE 1 (design)**. Its job: pick the right simulation paradigm for the research question, pass the feasibility + ethics gate, and emit a **simulation design doc** that names a validation target before any API call is made.

> **THE CARDINAL RULE.** Synthetic data is not a substitute for human data. It is a tool for pre-testing, power analysis, theory development, and counterfactual exploration. Any synthetic result that enters a publication MUST be validated against real human data (MODE 6 is a hard gate). Distributional mismatch is common (Bisbee et al. 2023) and must be reported transparently.

---

## The three paradigms

| Paradigm | Core question | Unit | Engine path | Reference file |
|----------|---------------|------|-------------|----------------|
| **Silicon sampling** | "What is the *distribution* of attitudes/responses in a population?" | Independent personas answering items once or `n_reps` times | `run` (`paradigm: silicon-survey`) | `silicon-sampling.md` |
| **Generative ABM** | "What macro pattern *emerges* from agents interacting over time/network?" | Stateful agents updating across turns | `run` (`paradigm: generative-abm`) | `generative-abm.md` |
| **Simulated experiment** | "What is the *treatment effect* of a manipulation, in the simulation?" | Personas randomized to `conditions[]` | `run` (`paradigm: experiment`) | `silicon-sampling.md` (experiment section) |

**Decision guide:**

- The question is about a **static cross-sectional distribution** (e.g., "how do partisans differ on immigration?") → **silicon sampling**. No agent interaction; personas are independent.
- The question is about **emergence, diffusion, polarization, or feedback over time** (e.g., "does cross-cutting exposure depolarize a network?") → **generative ABM**. Agents are stateful and influence each other.
- The question is about a **causal contrast under a manipulation** (e.g., "does a Black-coded name lower the simulated callback rate?") → **simulated experiment**. Randomize personas to arms; estimate the simulated effect as AME.
- The question asks for a **real-world causal effect from observational data** (`effect of`, `impact of`, DiD, IV, RD, matching) → simulation is NOT a substitute. Route to `/scholar-causal`. A *simulated* experiment estimates an effect *inside the simulation*, not a real-world causal effect.

---

## Feasibility and ethics gate (run before any design doc is finalized)

### Is synthetic data appropriate?

| Use case | Verdict | Caution |
|----------|---------|---------|
| Pre-testing survey instruments | Appropriate — low cost, fast iteration | Validate with cognitive interviews before fielding |
| Power analysis / sample-size estimation | Appropriate | Treat synthetic variance as a prior, not ground truth |
| Theory development ("what would we expect if…?") | Appropriate | Explore implications before data collection, not in lieu of it |
| Exploring counterfactual / hypothetical conditions | Appropriate with limitations | LLMs reflect historical training data; future behavior may differ |
| Exploring rare or hard-to-reach populations | Partial | LLMs may poorly represent truly marginalized groups; intersectional cells are thin |
| Generating labeled training data for classifiers | With validation | Validate synthetic labels against a human-coded gold standard (e.g., κ ≥ 0.70 on a 200-item sample) |
| **Replacing human survey data in published findings** | **NOT appropriate** | Bisbee et al. (2023): significant distributional mismatch; aggregate patterns may reproduce while within-subgroup variance does not |
| Claims about minority/marginalized populations | NOT appropriate without matched human data | Known underrepresentation of rare identity combinations; stereotyping effects |
| Predictions about future social behavior | NOT appropriate | LLMs cannot anticipate social change beyond their training cutoff |

### ABM-specific feasibility

A generative or mechanistic ABM is appropriate when:

- **Emergence** is the key question — macro patterns arising from micro interactions.
- **Heterogeneity** matters and aggregates non-linearly.
- **Feedbacks / path dependence** are central.
- **Counterfactuals** are not feasible empirically (you cannot run the policy experiment in the real world).

An ABM is NOT a substitute for causal inference from observational data.

### Ethics / IRB

- If the simulation makes claims about **real-world groups** — especially marginalized populations — check with your IRB whether LLM simulation requires review. Document the determination (review obtained, or exemption justified) in the design doc.
- **Never present synthetic output as human data.** Every downstream artifact must label the source as simulated.
- **Privacy of seed data.** Persona construction from real microdata and validation benchmarks are real human data and route through the project's data-safety stack (`.claude/safety-status.json`). Under `LOCAL_MODE`, build personas from aggregated marginal tables (not row-level microdata) and run validation inside scripts that emit only aggregated distributions (suppress cells with n < 10). When seeds are sensitive, run against a local open model (`provider: ollama` / `openai-compatible`) so no respondent-derived prompt leaves the machine — see `providers.md`.

If the gate fails (use case is in the NOT-appropriate column with no matched human-data plan), **stop and tell the user** rather than proceeding to a run.

---

## Simulation design doc template

MODE 1 writes this to `output/simulate/design/<slug>-design.md`. No run starts without a design doc naming its validation target.

```markdown
# Simulation Design Doc — <project slug>

## 1. Research question
<One sentence. State whether this is descriptive (distribution), dynamic
 (emergence over time), or causal-within-simulation (treatment effect).>

## 2. Paradigm choice
Paradigm: <silicon-survey | generative-abm | experiment>
Why this paradigm (not the others): <2–3 sentences tied to the RQ form above.>
If the RQ implies a real-world causal effect from observational data:
  → NOT this skill. Route to /scholar-causal. Stop here.

## 3. Persona specification
Source of joint distribution: <census ACS / GSS <year> / ANES <year> / CCES <year>>
Marginal tables used: <list the margins to be raked/IPF'd to a joint>
Persona dimensions: <age, gender, race/ethnicity, education, income, region,
                     party, religious attendance, employment, occupation, ...>
Target N personas: <N>; n_reps per persona: <K>
Context levels included: macro (period/region/climate),
                         meso (org/neighborhood/network), micro (individual).

## 4. Provider / model choice
Provider: <anthropic | openai | openai-compatible | ollama>   (see providers.md)
Model (exact id, pinned): <e.g., claude-haiku-4-5-20251001>
Scale strategy: <batch | async | local>
Rationale: <cost vs. privacy vs. turnaround — cite the constraint that decided it.>

## 5. Validation plan  (REQUIRED — names the benchmark up front)
Named human benchmark: <GSS 2022 / ANES 2020 / CCES 2022 / original survey N=____>
Calibration sample vs. validation sample: <how they are split; MUST be disjoint>
Fidelity metrics + pass thresholds:
  - KS statistic       < 0.10   (per key variable)
  - |mean difference|  < 0.5    (on the item scale)
  - Jensen-Shannon div < 0.10
  - Subgroup correlation (synthetic vs. real subgroup means) r ≥ 0.70
  - Coverage of real distribution within synthetic range: report
Subgroup axes to check: <race, party, education — not aggregate only>

## 6. Cost + power estimate (pre-flight)
Requests = N_personas × N_items × n_reps × N_conditions = <number>
Estimated tokens in/out per call: <in> / <out>
Pre-flight cost (from --dry-run): $<X>   (cost_cap_usd in manifest: $<cap>)
Power: if used for sample-size planning, state the synthetic effect size and
       variance feeding the power calc, and that these are priors not truth.

## 7. Ethics / IRB gate
Use-case verdict (from feasibility table): <Appropriate | Partial | NOT appropriate>
IRB determination: <review obtained | exemption justified | N/A — no real-group claim>
Marginalized-population caveat: <state explicitly if relevant>
Synthetic-not-human statement: confirmed — outputs labeled as simulated.

## 8. ABM-only: ODD protocol pointer
If paradigm = generative-abm, an ODD protocol is REQUIRED before the run
(NCS / Science Advances). Draft it now per generative-abm.md.
```

---

## What MODE 1 hands off

- A design doc at `output/simulate/design/`.
- A named validation benchmark and pass thresholds (consumed by MODE 6).
- A provider/model/scale decision (consumed by the run manifest).
- A cost cap (`cost_cap_usd`) the engine will enforce.

Next: MODE 2 (`persona-construction.md`) builds the persona pool; or for an ABM, draft the ODD protocol in `generative-abm.md` first.

---

## Method citations (preserve; do not invent)

- Silicon sampling: Argyle et al. (2023), *Political Analysis*.
- Distributional-mismatch caution: Bisbee et al. (2023), *Political Analysis*.
- LLMs as simulated economic agents: Horton (2023), *homo silicus*.
- Generative agents: Park et al. (2023), *Generative Agents*.

All citations are delegated to `/scholar-citation`; never hand-author `.bib`. Unverified claims are flagged `[CITATION NEEDED]`.
