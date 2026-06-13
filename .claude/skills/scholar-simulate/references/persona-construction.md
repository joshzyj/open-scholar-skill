# Persona Construction (MODE 2: personas)

This file is loaded by **MODE 2 (personas)**. Its job: build the persona pool the run will use. The key upgrade over hand-invented personas is to **sample personas from a real joint distribution** — rake/IPF marginal tables (census/GSS/ANES) to a joint, then sample N personas so the pool is demographically representative rather than a convenience set of exemplars.

The quality of any silicon-sampling or generative-ABM result depends entirely on the richness, consistency, and representativeness of the persona pool. A biased persona pool guarantees a biased synthetic distribution no matter how good the model is.

---

## The persona JSONL shape

The engine reads and writes personas as JSONL — one persona object per line. This is the contract `silicon_sampling`, `experiment`, and `generative-abm` runs all consume.

```json
{"persona_id": "p000001", "weight": 1.0, "attrs": {"age": 52, "gender": "male", "race_ethnicity": "White non-Hispanic", "education": "high school", "household_income": "$30-$60K", "region": "South US", "political_affiliation": "Strong Republican", "religious_attendance": "weekly", "employment_status": "employed full-time", "occupation": "truck driver", "neighborhood_type": "rural", "year": 2024}}
{"persona_id": "p000002", "weight": 1.0, "attrs": {"age": 34, "gender": "female", "race_ethnicity": "Black non-Hispanic", "education": "bachelor's", "household_income": "$60-$100K", "region": "Northeast US", "political_affiliation": "Strong Democrat", "religious_attendance": "monthly", "employment_status": "employed full-time", "occupation": "teacher", "neighborhood_type": "urban", "year": 2024}}
```

- `persona_id` — stable id; becomes the `custom_id` prefix for the request, so checkpoint/resume is idempotent.
- `weight` — survey weight from the raking step (post-stratification). Carried through so downstream aggregation can weight synthetic responses to match population totals.
- `attrs` — the demographic dimensions. The system-prompt builder reads these. Schema: `assets/schema/persona.schema.json`.

---

## Building personas from REAL joint distributions (raking / IPF)

Hand-invented personas (a few exemplars typed by the researcher) bias the pool toward whatever cells the author thought of. The fix: take **marginal** tables — which official statistics actually publish — and **rake** them into a **joint** distribution via Iterative Proportional Fitting (IPF), then sample N personas from that joint.

**Why IPF.** Census/GSS/ANES publish margins (e.g., the age distribution, the education distribution, the region distribution) but rarely the full cross-tabulation. IPF starts from a seed table (often uniform or a coarse known cross-tab) and iteratively rescales rows/columns until every margin matches the published totals. The result is a joint distribution consistent with all known margins — the standard demographic post-stratification move.

**Engine workflow:**

```bash
# Build N personas by IPF-raking the margins in spec.json to a joint, then sampling.
# --spec : JSON with margin tables + (optional) a seed cross-tab + scale-label maps.
# --n    : number of personas to draw (sampled with probability ∝ joint cell mass).
# --out  : JSONL written one persona per line, each with a post-strat weight.
python3 "$SKILL_DIR/assets/simulate_engine.py" personas \
  --spec output/simulate/design/persona-spec.json \
  --n 2000 \
  --out output/simulate/personas/pool.jsonl
```

**`persona-spec.json` shape** (the input to `personas`):

```json
{
  "source": "ACS 2022 + ANES 2020",
  "dimensions": ["age_bracket", "education", "race_ethnicity", "region", "party"],
  "margins": {
    "age_bracket":    {"18-29": 0.21, "30-44": 0.26, "45-64": 0.33, "65+": 0.20},
    "education":      {"<HS": 0.10, "HS": 0.28, "some college": 0.27, "BA": 0.21, "grad": 0.14},
    "race_ethnicity": {"White non-Hispanic": 0.59, "Black non-Hispanic": 0.12, "Hispanic/Latino": 0.19, "Asian American": 0.06, "Other": 0.04},
    "region":         {"Northeast US": 0.17, "Midwest US": 0.21, "South US": 0.38, "West US": 0.24},
    "party":          {"Strong Democrat": 0.18, "Lean Democrat": 0.22, "Independent": 0.18, "Lean Republican": 0.21, "Strong Republican": 0.21}
  },
  "seed_crosstab": null,
  "seed": 42
}
```

- `margins` — each dimension's published marginal proportions. IPF rakes the joint to match all of these simultaneously.
- `seed_crosstab` — optional known partial cross-tab to start IPF from (e.g., a published party × education table). `null` → start from the independence (product-of-margins) table.
- `seed` — fixes the sampling RNG so the pool is reproducible.

> **LOCAL_MODE.** Margins are *aggregated* statistics, not row-level microdata, so they are safe to inline in `persona-spec.json`. Do NOT read raw microdata (`.dta`/`.csv` extracts) to compute the margins inside the conversation — compute them inside a script that emits only the aggregated proportions, or use published margin tables directly. See `paradigms.md` ethics gate.

**Sketch of the IPF step** (this is what `assets/personas.py` implements; shown so the logic is auditable):

```python
import numpy as np  # numerics: tensor of joint cell masses indexed by dimension levels

def ipf_rake(margins, seed_table, n_iter=50, tol=1e-6):
    # margins: list of (axis, target_vector) — published marginal proportions per dimension
    # seed_table: starting joint (independence table if no partial cross-tab is known)
    table = seed_table.astype(float)            # work in float so rescaling is exact
    for _ in range(n_iter):                     # iterate: each pass rescales every margin once
        max_delta = 0.0                         # track convergence across this pass
        for axis, target in margins:            # rescale one dimension's margin to its target
            current = table.sum(axis=tuple(a for a in range(table.ndim) if a != axis))
            factor = np.where(current > 0, target / current, 0.0)  # avoid div-by-zero on empty cells
            shape = [1] * table.ndim; shape[axis] = -1             # broadcast factor along this axis
            table = table * factor.reshape(shape)                  # apply the marginal correction
            max_delta = max(max_delta, float(np.abs(current - target).max()))
        if max_delta < tol:                     # converged once every margin matches within tol
            break
    return table / table.sum()                  # normalize to a proper joint probability table
```

After raking, `personas.py` samples N cells with probability proportional to the joint mass, assigns each sampled persona a post-stratification `weight`, fills in finer attributes (e.g., a specific age within the sampled bracket) by conditional draw, and writes the JSONL.

---

## Persona context engineering (macro / meso / micro)

Once the demographic attributes are sampled, the **system prompt** turns attributes into a believable person. Structure the persona at three context levels:

- **Macro context** (societal): time period, country/region, political/economic climate.
- **Meso context** (group/organization): industry, workplace, neighborhood, social network.
- **Micro context** (individual): demographics, life history, values, current situation.

Add *experiential texture* beyond bare labels — life-history cues approximate behavior better than category names alone.

```python
def build_persona_system_prompt(attrs: dict) -> str:
    # Map coarse education/income labels to lived-experience cues — texture beats labels
    # because the model conditions on narrative context, not just category tokens.
    education_history = {                         # turn a category into a life-history sentence
        "<HS":           "left school early to work",
        "HS":            "graduated high school; has not pursued college",
        "some college":  "attended college but did not complete a degree",
        "BA":            "has a four-year college degree",
        "grad":          "has an advanced degree (master's or PhD)",
    }
    income_context = {                            # convey material circumstances, not a dollar bin
        "$0-$30K":   "lives paycheck to paycheck; budgets carefully",
        "$30-$60K":  "gets by but has limited savings",
        "$60-$100K": "solidly middle class; some savings and benefits",
        "$100K+":    "financially comfortable; has investments and savings",
    }
    # Assemble macro (year/region) + meso (neighborhood/work) + micro (demographics/values).
    return f"""You are roleplaying as a research participant in a social science study.

Demographics: {attrs['age']}-year-old {attrs['gender']}, {attrs['race_ethnicity']}
Location: {attrs['region']}{f", {attrs['neighborhood_type']} area" if attrs.get('neighborhood_type') else ""}
Education: {education_history.get(attrs['education'], attrs['education'])}
Finances: {income_context.get(attrs['household_income'], attrs.get('household_income',''))}
Work: {attrs['employment_status']}{f" — {attrs['occupation']}" if attrs.get('occupation') else ""}
Politics: {attrs['political_affiliation']}
Religion: attends religious services {attrs['religious_attendance']}
Year: {attrs.get('year', 2024)}

Respond as this person would — shaped by their social position, lived experiences, and values. Be internally consistent. Do not break character. Do not acknowledge that you are an AI. If a question would not apply to this person's life, respond accordingly."""
```

### Role-based layering (for organizational / group simulations)

When the simulation is about an organizational decision (hiring, peer review, evaluation), layer a **role identity** over the demographic identity so both shape the response:

```python
def build_role_persona_prompt(attrs: dict, role: dict, scenario: str) -> str:
    demo = build_persona_system_prompt(attrs)     # demographic base persona (above)
    # Append the institutional context so org norms AND demographics both condition the answer.
    return f"""{demo}

Current role and context:
- Organization type: {role['org_type']}
- Your position/background: {role.get('decision_maker_background', '')}
- Organizational values: {role.get('org_values', '')}
- You are now: {scenario}

Let your demographic background AND your professional role shape your response."""
```

### Caching note

The shared system-prompt scaffold (everything except the per-persona attributes) and the persona block can be marked with `cache_control` so repeated personas across items/reps/conditions do not re-pay input tokens. The engine handles this when `cache: true` in the manifest — see `scale-engine.md`.

---

## Validation hook (close the loop)

The persona pool is the lever for fidelity. If MODE 6 validation shows a subgroup is off, MODE 7 (calibrate) may revise the persona prompt (richer texture, different framing) — but the *pool composition* itself should match the population by construction (that is what raking buys you). If a subgroup is sparse in the real margins, it will be sparse in the pool; do not over-sample it without weighting, or you will distort the synthetic population.

---

## What MODE 2 hands off

- `output/simulate/personas/pool.jsonl` — N personas with post-strat weights.
- The persona source documented for the Methods text (consumed by `reporting-templates.md`).

Next: MODE 3 (`silicon-sampling.md`) for survey/vignette/conjoint, or MODE 4 (`generative-abm.md`) for stateful agents.

---

## Method citations (preserve; do not invent)

- Structured demographic personas / silicon sampling: Argyle et al. (2023), *Political Analysis*.
- Generative agents (rich memory-bearing personas): Park et al. (2023).

Citations are delegated to `/scholar-citation`; never hand-author `.bib`. Flag unverified claims `[CITATION NEEDED]`.
