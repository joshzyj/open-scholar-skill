# Silicon Sampling & Simulated Experiments (MODE 3 + MODE 5)

This file is loaded by **MODE 3 (silicon-survey)** and **MODE 5 (experiment)**. Its job: have thousands of personas answer survey / vignette / conjoint items (MODE 3), or randomize personas to conditions and estimate a simulated treatment effect (MODE 5). Everything runs through the engine and the run manifest — never hand-rolled in-conversation loops.

**Silicon sampling** (Argyle et al. 2023, *Political Analysis*): give an LLM a rich sociodemographic persona, then query it as if conducting a survey. LLMs encode statistical relationships between demographics and attitudes from their training corpora, so they can approximate the marginal and conditional response distributions of real social groups — for pre-testing and subgroup comparison without data-collection cost. It is not a substitute for human data (Bisbee et al. 2023); MODE 6 validation is a hard gate.

---

## The standard workflow: dry-run → run → validate

Every silicon-survey and experiment run follows the same three steps:

```bash
# 1) DRY RUN — build personas + assemble prompts + write the request manifest +
#    print a cost estimate and request count. Makes ZERO API calls. Always do this first.
python3 "$SKILL_DIR/assets/simulate_engine.py" run \
  --manifest output/simulate/runs/trust-survey/run-manifest.json --dry-run

# 2) RUN — submit the requests (batch/async/local per scale_strategy), checkpoint to JSONL.
python3 "$SKILL_DIR/assets/simulate_engine.py" run \
  --manifest output/simulate/runs/trust-survey/run-manifest.json

# 3) VALIDATE — compare responses against a held-out human benchmark (HARD GATE, MODE 6).
python3 "$SKILL_DIR/assets/simulate_engine.py" validate \
  --responses output/simulate/runs/trust-survey/responses.jsonl \
  --benchmark data/raw/gss-2022-trust.csv \
  --out output/simulate/validation/trust-fidelity.json
```

No substantive claim is made before step 3 passes. See `scale-engine.md` for batch/async/local mechanics and `validation-fidelity.md` for thresholds.

---

## The items file

Survey/vignette/conjoint items live in an `items.json` referenced by the manifest (`"items": "path/to/items.json"`). Schema: `assets/schema/item.schema.json`.

```json
{
  "items": [
    {
      "key": "trust_govt",
      "type": "likert",
      "question": "How much of the time do you think you can trust the government in Washington to do what is right?",
      "scale": ["Never", "Only some of the time", "About half the time", "Most of the time", "Always"],
      "scale_values": [1, 2, 3, 4, 5],
      "max_tokens": 80,
      "instruction": "Reply with ONLY the number, then a brief reason after a pipe: '2 | because...'"
    },
    {
      "key": "immigration_level",
      "type": "likert",
      "question": "Do you think the number of immigrants permitted to come to the United States should be...",
      "scale": ["Increased a lot", "Increased a little", "Left the same", "Decreased a little", "Decreased a lot"],
      "scale_values": [1, 2, 3, 4, 5]
    }
  ]
}
```

The engine pairs each persona's system prompt (from `persona-construction.md`) with each item's user prompt, submits, then parses `value | reason` from the response. Parsed responses land in `responses.jsonl`.

---

## The responses JSONL shape

One response per line; schema `assets/schema/response.schema.json`:

```json
{"custom_id": "p000001--trust_govt--rep0--baseline", "persona_id": "p000001", "item": "trust_govt", "condition": "baseline", "rep": 0, "value": 2, "label": "Only some of the time", "raw": "2 | I don't trust Washington much.", "model": "claude-haiku-4-5-20251001", "weight": 1.0, "attrs": {"race_ethnicity": "White non-Hispanic", "political_affiliation": "Strong Republican", "education": "HS"}}
```

`custom_id` is `persona--item--rep--condition` so checkpoint/resume is idempotent (re-running only re-queues missing custom_ids). `n_reps` captures within-persona stochasticity: each persona answers each item `n_reps` times; aggregate with the replicate mean.

### Aggregating to a response table

Aggregation and all downstream estimation hand off to **R** (house style: ASR/AJS/Demography/Social Forces; AME preferred over odds ratios). The engine is Python; estimation is R.

```r
library(tidyverse)   # data wrangling + read/write — the analysis lingua franca for this house

# Read the engine's JSONL responses (one per line) into a tidy data frame.
resp <- jsonlite::stream_in(file("output/simulate/runs/trust-survey/responses.jsonl"))

# Collapse replicates to one synthetic response per persona × item (replicate mean),
# because n_reps exists only to average out within-persona stochasticity, not to inflate n.
persona_item <- resp |>
  group_by(persona_id, item, race_ethnicity = attrs.race_ethnicity,
           party = attrs.political_affiliation, weight) |>
  summarise(value = mean(value, na.rm = TRUE), .groups = "drop")

# Subgroup means, WEIGHTED by the post-stratification weight so the synthetic
# population matches population totals (the raking weight from MODE 2 earns its keep here).
subgroup <- persona_item |>
  group_by(item, party) |>
  summarise(mean_value = weighted.mean(value, weight), n = n(), .groups = "drop")

write_csv(subgroup, "output/simulate/runs/trust-survey/subgroup-means.csv")  # for the validation join
```

---

## Vignette and conjoint items

**Factorial vignette** — manipulate one experimental condition while holding the persona constant (or vice versa). Encode the manipulated cells as `conditions[]` in the manifest (next section), with the vignette text templated per condition:

```json
{
  "key": "callback",
  "type": "rating",
  "question": "A {applicant_race} {applicant_gender} named {applicant_name} applies for a {position} at a {company_type}. They have {qualifications}. How likely are you to recommend an interview? Scale 1 (Very unlikely) to 7 (Very likely). Reply with ONLY the number.",
  "scale_values": [1, 2, 3, 4, 5, 6, 7]
}
```

**Conjoint** — present two profiles built from a fully-crossed attribute grid and ask for a forced choice:

```json
{
  "key": "vote_choice",
  "type": "choice",
  "question": "Candidate A: a {A_age}-year-old {A_race} {A_gender}, {A_party}, from {A_education}. Candidate B: a {B_age}-year-old {B_race} {B_gender}, {B_party}, from {B_education}. Which would you vote for? Reply ONLY 'A' or 'B'.",
  "choices": ["A", "B"]
}
```

The engine randomizes attribute levels per task and records the realized profile in the response row, so AMCEs (average marginal component effects) can be estimated downstream in R.

---

## Organizational and group behavior

To simulate how organizational roles and institutional contexts shape decisions (hiring committees, peer-review panels, performance evaluations, group negotiations), use the role-layered persona from `persona-construction.md` (`build_role_persona_prompt`) and encode the org context as the condition. Two patterns:

- **One-shot org decision** (hiring advance/reject, rating): a `choice`/`rating` item with `org_type`, `org_values`, `decision_maker_background` carried in the condition `overrides`. Vary `org_type` while holding the candidate constant to isolate the institutional effect.
- **Sequential group deliberation** (a panel converging on a view): this is a *stateful, multi-turn* process — each agent sees prior statements before responding. That belongs to the **generative ABM** path (`generative-abm.md`), because the checkpoint store must carry the conversation history between turns. A single-shot survey item cannot represent it.

---

## Experiment section (MODE 5)

A **simulated experiment** randomizes personas to `conditions[]`, estimates the **simulated** treatment effect, and reports it as an **AME** (average marginal effect — house style) with within-persona clustering. This estimates an effect *inside the simulation*, not a real-world causal effect. If the question is a real-world causal effect from observational data, route to `/scholar-causal`.

### Conditions in the manifest

```json
{
  "run_id": "callback-audit-sim",
  "paradigm": "experiment",
  "provider": "anthropic",
  "model": "claude-haiku-4-5-20251001",
  "temperature": 0.3, "seed": 42, "max_tokens": 10,
  "scale_strategy": "batch", "cache": true,
  "personas": "output/simulate/personas/pool.jsonl",
  "items": "output/simulate/runs/callback-audit-sim/items.json",
  "conditions": [
    {"name": "white_name",  "overrides": {"applicant_race": "White", "applicant_name": "Greg"}},
    {"name": "black_name",  "overrides": {"applicant_race": "Black", "applicant_name": "Jamal"}}
  ],
  "n_reps": 3,
  "checkpoint_dir": "output/simulate/runs/callback-audit-sim",
  "cost_cap_usd": 25.0
}
```

**Design choices:**

- **Hold persona constant across arms** (within-persona / repeated-measures): each persona evaluates both the white-name and black-name applicant. Maximizes power, isolates the manipulation, and makes within-persona clustering essential.
- **Or randomize personas to arms** (between-persona): each persona sees one condition. Use when within-persona carryover (the model remembering it just saw the other arm) would contaminate the response — but the engine sends each `custom_id` as an independent request, so carryover is not an issue unless you intentionally share conversation state. Default to within-persona for power.
- Randomize the order of conditions per persona; the engine does this when `n_reps > 1`.

### Estimating the simulated effect as AME (in R)

```r
library(tidyverse)    # wrangling
library(fixest)       # fast FE regression + clustered SEs — standard for this house style
library(marginaleffects)  # AMEs: report average marginal effects, not odds ratios (house rule)

# Read responses; binary outcome example: did the simulated decision-maker recommend (>=5 on 1-7)?
resp <- jsonlite::stream_in(file("output/simulate/runs/callback-audit-sim/responses.jsonl")) |>
  mutate(recommend = as.integer(value >= 5),                 # dichotomize the 7-pt rating at the top-3
         condition = factor(condition, levels = c("white_name", "black_name")))  # white_name = baseline

# Linear probability model with persona fixed effects (within-persona design),
# SEs clustered within persona because each persona contributes multiple correlated responses.
m <- feglm(recommend ~ condition | persona_id,
           data = resp, family = "binomial", cluster = ~ persona_id)

# Report the AME of the race manipulation (the simulated treatment effect), NOT an odds ratio.
ame <- avg_slopes(m, variables = "condition")   # average marginal effect of black_name vs white_name
print(ame)                                       # estimate is on the probability scale — house style

write_csv(broom::tidy(ame), "output/simulate/runs/callback-audit-sim/ame.csv")  # for the locked table
```

Report: "The simulated callback rate was X.X percentage points lower in the black-name condition (AME = −0.0XX, clustered SE = 0.0XX, p = ...), estimated within the simulation; this is not a real-world causal estimate." Then validate against a human benchmark (e.g., a published audit study) before any substantive claim — MODE 6.

> **Temperature for experiments.** Use a low temperature (0.2–0.4) for choice/rating items so the manipulation, not sampling noise, drives variation; keep `n_reps ≥ 3` to estimate within-persona stochasticity. Pin `seed` for reproducibility.

---

## What MODE 3 / MODE 5 hand off

- `responses.jsonl` (engine output) and an aggregated subgroup/AME table (R).
- The exact model id, temperature, seed, N, and n_reps (consumed by `reporting-templates.md`).

Next: MODE 6 (`validation-fidelity.md`) — mandatory before any claim.

---

## Method citations (preserve; do not invent)

- Silicon sampling: Argyle et al. (2023), *Political Analysis*.
- Distributional-mismatch caution: Bisbee et al. (2023), *Political Analysis*.
- LLMs as simulated economic agents: Horton (2023), *homo silicus*.

Citations are delegated to `/scholar-citation`; never hand-author `.bib`. Flag unverified claims `[CITATION NEEDED]`.
