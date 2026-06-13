# Validation & Calibration (MODE 6 hard gate + MODE 7 calibrate)

This file is loaded by **MODE 6 (validate)** — a hard gate — and **MODE 7 (calibrate)**. No synthetic result enters a publication without passing MODE 6.

> **THE CARDINAL RULE, restated.** Synthetic data is not a substitute for human data. Any synthetic result that enters a publication MUST be validated against a held-out human benchmark. Distributional mismatch is common (Bisbee et al. 2023) and must be reported transparently — including when it fails.

---

## MODE 6 — validate (HARD GATE)

Compare synthetic responses against a held-out human benchmark (GSS / ANES / CCES / your own survey) on five families of metrics, then **dispatch a verification subagent** to independently confirm the thresholds were met — do not self-certify.

### The engine workflow

```bash
# Compare synthetic responses to a human benchmark; write a fidelity JSON the gate consumes.
# --responses : the run's responses.jsonl (from MODE 3/4/5)
# --benchmark : human data on the SAME items/scales (CSV; the held-out validation sample)
# --out       : fidelity.json with per-variable + per-subgroup metrics and pass/fail flags
python3 "$SKILL_DIR/assets/simulate_engine.py" validate \
  --responses output/simulate/runs/trust-survey/responses.jsonl \
  --benchmark data/raw/gss-2022-trust.csv \
  --out output/simulate/validation/trust-fidelity.json
```

> **LOCAL_MODE.** The benchmark is real human data and routes through `.claude/safety-status.json`. `validate` reads it inside the engine and emits only aggregated metrics (no row-level values surface in the conversation); suppress subgroup cells with n < 10. Never `Read` the raw benchmark CSV into the conversation when status is `LOCAL_MODE`.

### Fidelity metrics and pass thresholds

`assets/validate.py` computes, **per key variable** and **per subgroup**:

| Metric | What it catches | Pass threshold (default) |
|--------|-----------------|--------------------------|
| **KS statistic** (two-sample Kolmogorov–Smirnov) | Any difference in distribution shape | < 0.10 |
| **Mean difference** (synthetic − real) | Location shift on the item scale | \|diff\| < 0.5 |
| **Jensen–Shannon divergence** | Symmetric distributional distance (0 = identical) | < 0.10 |
| **Subgroup correlation** | Whether synthetic *reproduces the cross-subgroup ordering* of real means | r ≥ 0.70 |
| **Coverage** | Whether the synthetic distribution spans the real support (not collapsed to the mean) | real central 90% inside synthetic range; report % |

A key item **passes** when its KS, mean-diff, and JSD all clear (these are per-item metrics). Subgroup correlation and coverage are computed **once, globally** across the run, not per item.

**Verdict rule (what `validate.py` actually returns — exit 0 PASS / exit 1 FAIL):** the gate PASSES only when **all three** hold: (1) coverage clears, (2) the subgroup correlation is met, and (3) **≥ 80% of key items** clear all per-item metrics (KS + mean-diff + JSD). The item-pass bar is `item_pass_rate_min = 0.80` by default and is configurable via `--thresholds '{"item_pass_rate_min": 1.0}'` (stricter) or lower (looser). Note this is **neither** "all items pass" **nor** a bare majority — the prior 0.50 bar let half the key variables miss their benchmark and still pass, which is why the default is 0.80. Report any failing item explicitly rather than dropping it.

**Missing subgroup correlation FAILS by default.** When the subgroup correlation cannot be computed (no `--subgroup-var`, or no subgroups shared between synthetic and real), the run **FAILS** (exit 1) unless you pass `--allow-missing-subgroup`, which records an auditable `allow_missing_subgroup: true` in the report and treats the missing correlation as a non-blocking opt-out. The default is fail-closed precisely because algorithmic fidelity (cross-subgroup ordering, Argyle 2023) is the single most important fidelity number — a silently-skipped subgroup check used to let structurally-wrong runs pass.

**Ambiguity diagnostic.** The report also surfaces `n_responses_ambiguous` — the count of reply cells where more than one number was found in mixed-format text and the first was taken. A high count signals the parser is guessing; tighten the response format or post-process before trusting the verdict.

```python
# Core distributional comparison (this is what validate.py runs per variable).
from scipy.stats import ks_2samp                    # two-sample KS: shape-sensitive
from scipy.special import rel_entr                  # KL terms for the JS divergence
import numpy as np

def fidelity(synth, real, scale_range):
    # synth, real: numeric responses on the SAME scale; scale_range=(lo,hi) for binning.
    ks_stat, ks_p = ks_2samp(synth, real)            # distribution-shape distance + p-value
    mean_diff = float(np.mean(synth) - np.mean(real))# location shift on the item scale
    lo, hi = scale_range                             # build matched histograms over the scale
    def hist(d):                                      # normalized probability mass per scale point
        c = [list(d).count(v) for v in range(lo, hi + 1)]
        return [x / (sum(c) or 1) for x in c]
    p, q = hist(synth), hist(real)
    m = [0.5 * (a + b) for a, b in zip(p, q)]        # mixture distribution for JS divergence
    jsd = 0.5 * sum(rel_entr(p, m)) + 0.5 * sum(rel_entr(q, m))  # symmetric, bounded distance
    return {                                          # everything the gate + Methods text need
        "n_synthetic": len(synth), "n_real": len(real),
        "mean_synthetic": round(float(np.mean(synth)), 3),
        "mean_real": round(float(np.mean(real)), 3),
        "mean_diff": round(mean_diff, 3),
        "ks_statistic": round(float(ks_stat), 3), "ks_p": round(float(ks_p), 4),
        "jsd": round(float(jsd), 4),
        "passes": (ks_stat < 0.10 and abs(mean_diff) < 0.5 and jsd < 0.10),  # the gate flag
    }
```

### Subgroup correlation (added metric — do not report aggregate only)

Aggregate alignment can hide subgroup failure. Compute each subgroup's mean in both synthetic and real data, then correlate the two vectors across subgroups — this tests whether the model gets the *ordering* of groups right (e.g., are Strong Republicans more anti-immigration than Strong Democrats by roughly the real margin?).

```python
def subgroup_correlation(synth_df, real_df, response_col, group_col):
    # Mean response per subgroup in each dataset, then correlate the aligned subgroup-mean vectors.
    import pandas as pd
    s = synth_df.groupby(group_col)[response_col].mean()         # synthetic subgroup means
    r = real_df.groupby(group_col)[response_col].mean()          # real subgroup means
    groups = sorted(set(s.index) & set(r.index))                 # subgroups present in BOTH
    sv = [s[g] for g in groups]; rv = [r[g] for g in groups]     # aligned mean vectors
    return {"subgroup_r": round(float(np.corrcoef(sv, rv)[0, 1]), 3),  # Pearson r across subgroups
            "n_subgroups": len(groups), "passes": np.corrcoef(sv, rv)[0, 1] >= 0.70}
```

### Coverage (added metric — guard against homogenization)

LLMs systematically over-concentrate around the scale midpoint (homogenization bias). Coverage checks whether the synthetic distribution actually spans the real one rather than collapsing toward the mean:

```python
def coverage(synth, real):
    # Fraction of the real distribution's central 90% mass that falls inside the synthetic range.
    lo, hi = np.percentile(real, [5, 95])                        # central 90% interval of real data
    inside = [v for v in synth if lo <= v <= hi]                 # synthetic mass within that interval
    # Also a direct homogenization check: is synthetic SD shrunken vs real?
    return {"coverage_frac": round(len(inside) / max(len(synth), 1), 3),
            "sd_ratio": round(float(np.std(synth) / (np.std(real) or 1)), 3),  # <1 => homogenized
            "homogenized": np.std(synth) < 0.85 * np.std(real)}  # flag if synthetic variance collapses
```

### Verification subagent (do not self-certify)

After `validate` writes `fidelity.json`, dispatch a verification subagent (Agent tool) to independently read the raw JSON and confirm thresholds were actually met. A `report` claiming publishability MUST reference a passing fidelity artifact confirmed by this subagent.

```
SYNTHETIC-DATA VALIDATION VERIFICATION
======================================
FIDELITY ARTIFACT
[ ] fidelity.json exists for this run_id and is non-empty
[ ] KS < 0.10, |mean diff| < 0.5, JSD < 0.10 for every KEY variable (not just some)
[ ] Subgroup correlation r >= 0.70; subgroups checked (race, party, education) not aggregate only
[ ] Coverage reported; homogenization flag inspected (sd_ratio, not assumed absent)
BENCHMARK INTEGRITY
[ ] Benchmark is a HELD-OUT human sample, disjoint from any calibration sample (no leakage)
[ ] Same items/scales in synthetic and benchmark; recodes documented
HONESTY
[ ] Failures reported, not dropped; mismatched variables named in Limitations
[ ] Known LLM limitations acknowledged for this population
RESULT: [PASS / NEEDS REVISION]   Issues: [list]
```

---

## Interactive paradigm (MODE 10) — validation is NOT bypassed

Multi-agent **conversation** output (MODE 10) is not a distribution, so the five distributional metrics above do not apply directly. The hard gate is **not** waived — it returns a distinct verdict:

- **No human-transcript benchmark → `UNVALIDATED-EXPLORATORY`.** The run may inform protocol/instrument design and generate hypotheses, but supports **no** substantive empirical claim. A `report` MUST carry this verdict explicitly; it may not be laundered into a fidelity PASS.
- **With a held-out human-transcript benchmark on the same scenario**, compare **descriptive interaction statistics** — turns per agent, message-length distributions, turn-taking balance/entropy, and (where coded) stance/topic trajectories — against the human transcripts and report the comparison. This is a weaker, descriptive form of fidelity; do not present it as distributional algorithmic fidelity.

```
INTERACTIVE-SIMULATION VALIDATION VERIFICATION
==============================================
[ ] transcripts.jsonl exists for this run_id and is non-empty
[ ] Validation status stated: UNVALIDATED-EXPLORATORY, or descriptive-benchmark comparison present
[ ] If a claim is made: a HELD-OUT human-transcript benchmark exists and interaction stats were compared
[ ] Interaction-specific limitation disclosed (LLM agents over-produce agreeable consensus; under-produce
    conflict, interruption, and silence relative to real deliberation)
[ ] Tool use NOT claimed (tool execution is not implemented in this version)
RESULT: [UNVALIDATED-EXPLORATORY / DESCRIPTIVE-BENCHMARK-PASS / NEEDS REVISION]   Issues: [list]
```

### Executable record: `validation.json` (this is the machine-checkable form of the block above)

`interactive_runner.py run` writes `<ckpt>/validation.json` in **both** branches (dry-run and live). It mirrors the verification checklist as booleans so a downstream consumer (MODE 9 report, full-paper Branch C) does not have to parse prose:

```json
{ "verdict": "UNVALIDATED-EXPLORATORY", "paradigm": "interactive", "run_id": "...",
  "n_conversations": 8, "max_turns": 12, "topology": "...", "dry_run": false,
  "checklist": { "transcripts_present": true, "benchmark_compared": false,
                 "tool_use_claimed": false, "interaction_limitation_disclosed": true },
  "disclaimer": "...human-data substitution caveat..." }
```

**Gate semantics differ from the MODE 6 distributional gate — read this carefully.** `validate.py` is a PASS/FAIL exit gate (exit 1 halts Branch C). The MODE 10 record is **intentionally non-PASS**: a conversation transcript has no benchmark distribution, so the verdict is *always* `UNVALIDATED-EXPLORATORY` and the runner therefore **never exits non-zero on account of it**. The contract is not "PASS vs FAIL"; it is **"the record EXISTS and is honestly labelled."** A consumer admits the result only as exploratory illustration (qualitative transcript reads), never as a confirmatory estimate; if `validation.json` is **absent**, the MODE 10 output must not be carried into the manuscript at all. Do not "upgrade" this verdict to a fidelity PASS, and do not treat the zero exit code as a distributional pass.

---

## MODE 7 — calibrate

Calibration tunes the simulation to maximize fidelity on a **held-out human sample**, then locks the winning configuration into the run manifest. The levers, in rough order of impact:

1. **Temperature** — controls within-persona variance. Too low → homogenization (collapsed variance); too high → noise drowns the signal. Sweep e.g. {0.2, 0.5, 0.7, 1.0}.
2. **Few-shot anchors** — prepend 1–3 example (persona → calibrated response) pairs to anchor the scale usage. Often the single largest fidelity gain. Draw anchors from the calibration sample only.
3. **Persona richness** — bare labels vs. life-history texture (`persona-construction.md`). Richer context usually improves subgroup ordering.
4. **Prompt wording** — item phrasing, scale presentation, the "reply only with the number" instruction. Small wording changes move response distributions.

```
CALIBRATION ↔ VALIDATION DISJOINTNESS (NON-NEGOTIABLE)
Split the human data into a CALIBRATION sample (used here to tune) and a
VALIDATION sample (used by MODE 6 to score). They MUST be disjoint — tuning on
the validation data is leakage and invalidates the fidelity result. Stratify the
split so both halves cover the key subgroups.
```

### The sweep (engine + R)

Run the engine once per configuration against the **calibration** personas, score each with the same fidelity metrics, pick the config that maximizes fidelity on calibration, then confirm it generalizes on the disjoint validation sample in MODE 6.

```bash
# Sweep temperature by running the engine per setting (each writes its own responses.jsonl).
for T in 0.2 0.5 0.7 1.0; do
  jq ".temperature = $T | .run_id = \"calib-t$T\"" base-manifest.json > "manifest-t$T.json"  # set temp + id
  python3 "$SKILL_DIR/assets/simulate_engine.py" run --manifest "manifest-t$T.json"          # generate
  python3 "$SKILL_DIR/assets/simulate_engine.py" validate \
    --responses "output/simulate/runs/calib-t$T/responses.jsonl" \
    --benchmark data/raw/gss-2022-calibration.csv \
    --out "output/simulate/validation/calib-t$T.json"                                          # score
done
```

```r
library(tidyverse); library(jsonlite)   # collect each config's fidelity and pick the best
# Read every calibration fidelity JSON and rank by a composite (lower JSD + |mean diff| is better).
files <- list.files("output/simulate/validation", "^calib-t.*\\.json$", full.names = TRUE)
scores <- map_dfr(files, ~ as_tibble(fromJSON(.x)$summary) |> mutate(config = basename(.x)))
best <- scores |> mutate(loss = jsd + abs(mean_diff)) |> arrange(loss) |> slice(1)  # smallest loss wins
print(best)   # lock best$temperature (and chosen anchors/prompt) into the production run manifest
```

Lock the winning `temperature` / few-shot anchors / prompt wording into the production manifest, then run MODE 6 on the **validation** sample to confirm it holds out of sample.

---

## Known limitations (mandatory disclosure)

Every report using synthetic data MUST disclose these in the Discussion → Limitations subsection (see `reporting-templates.md`):

1. **Homogenization bias** — LLMs tend toward centrist/moderate responses; within-group variance is understated (test via coverage / sd_ratio above).
2. **Demographic steerability** — some groups are steered more reliably than others; fidelity is uneven across personas.
3. **Training recency** — LLMs reflect data through their training cutoff; recent events and social change are not captured.
4. **Intersectionality gaps** — combinations of identities (thin cells) may not be well represented even when each marginal is.
5. **Rare populations** — truly marginalized or small groups are poorly simulated; do not make claims about them without matched human data.

If validation fails for a variable or subgroup, name it explicitly here — do not bury or drop it.

---

## What MODE 6 / MODE 7 hand off

- `fidelity.json` (per-variable + per-subgroup metrics, pass/fail) and the verification-subagent verdict.
- A locked, calibrated run manifest (from MODE 7) for the production run.
- The fidelity numbers and limitation list consumed by `reporting-templates.md`.

---

## Method citations (preserve; do not invent)

- Distributional-mismatch / validation caution: Bisbee et al. (2023), *Political Analysis*.
- Silicon sampling: Argyle et al. (2023), *Political Analysis*.

Citations are delegated to `/scholar-citation`; never hand-author `.bib`. Flag unverified claims `[CITATION NEEDED]`.
