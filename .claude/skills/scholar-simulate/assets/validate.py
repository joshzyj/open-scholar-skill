"""Fidelity validation for scholar-simulate (the MODE 6 hard gate).

Compares synthetic LLM responses against a real human benchmark and reports algorithmic
fidelity. "Algorithmic fidelity" (Argyle et al. 2023) asks not just whether marginal means
match, but whether the model reproduces the BETWEEN-GROUP structure of real attitudes — so
the subgroup-correlation metric is the most important single number here.

Metrics (per item):
  - mean difference        synthetic mean - human mean
  - KS statistic           two-sample Kolmogorov-Smirnov D on the empirical CDFs
  - Jensen-Shannon div.    JSD (base-2, in [0,1]) on the categorical/binned distributions
Aggregate:
  - subgroup correlation   Pearson r between synthetic and human subgroup means (needs --personas
                           + a `subgroup` column in the benchmark). The key fidelity number.
  - coverage               fraction of items whose synthetic mean falls within the human mean +/-
                           2 SE band (a simple calibration check)

Pure stdlib (math/csv/json) so it runs anywhere. Thresholds are configurable; defaults are
deliberately strict and should be justified per scale in the methods text.

Inputs:
  responses.jsonl   rows {custom_id: "cond|persona_id|item_id|rep", text: "...", ...}
  benchmark.csv     long format: columns item_id,value[,subgroup]
  --personas FILE   optional personas.jsonl to map persona_id -> attributes for subgroups
  --subgroup-var V  optional persona attribute name to use as the subgroup key
"""

from __future__ import annotations  # lazy annotations

import re                           # parse a numeric response out of model text
import csv                          # read the human benchmark CSV
import json                         # read responses, write fidelity.json
import math                         # logs for JSD, sqrt for correlation
import sys                          # argv / stderr / exit codes

# Default pass thresholds (override via --thresholds JSON). Strict by design.
DEFAULT_THRESHOLDS = {
    "ks_max": 0.20,                 # KS D below this = distributions acceptably close
    "jsd_max": 0.10,                # JSD below this = categorical shapes acceptably close
    "abs_mean_diff_max": 0.50,      # |mean diff| below this (scale-dependent — justify per item)
    "subgroup_r_min": 0.70,         # Argyle-style between-group fidelity floor
    "coverage_min": 0.80,           # >=80% of items within the human +/-2SE band
    "item_pass_rate_min": 0.80,     # >=80% of items must clear ALL per-item metrics (was a silent 0.5)
}

_NUM = re.compile(r"-?\d+(?:\.\d+)?")  # first signed integer/decimal in a string


def _parse_value(row: dict, value_field: str | None) -> tuple[float | None, bool]:
    """Extract a numeric response from a response row.

    If `value_field` is set and present, use it directly; otherwise parse the FIRST number
    out of the model's `text` (works for Likert/numeric replies). Returns a (value, ambiguous)
    pair: `value` is None when unparseable; `ambiguous` is True only when the value was scanned
    from free text that contained MORE THAN ONE number (e.g. "On a 1-7 scale I'd say 5" → first
    number is 1, not the intended 5). We keep the first-number behavior for back-compat but flag
    the ambiguity so a silent parsing bias becomes a reported diagnostic, not a hidden error.
    """
    if value_field and value_field in row:               # caller pre-parsed a numeric field
        try:
            return float(row[value_field]), False        # use it directly; no text-scan ambiguity
        except (TypeError, ValueError):
            return None, False                           # malformed -> treat as missing
    nums = _NUM.findall(str(row.get("text", "")))        # ALL numbers in the model's text answer
    if not nums:                                         # no number at all -> unparseable
        return None, False
    return float(nums[0]), len(nums) > 1                 # first number; ambiguous if >1 present


def _item_of(custom_id: str) -> str:
    """Recover the item_id from a 'cond|persona|item|rep' custom_id."""
    parts = custom_id.split("|")                         # split the join key
    return parts[2] if len(parts) >= 3 else "item"       # third field is the item_id


def _persona_of(custom_id: str) -> str:
    """Recover the persona_id from a 'cond|persona|item|rep' custom_id."""
    parts = custom_id.split("|")                         # split the join key
    return parts[1] if len(parts) >= 2 else "p"          # second field is the persona_id


def ks_statistic(a: list, b: list) -> float:
    """Two-sample Kolmogorov-Smirnov D: max gap between the two empirical CDFs."""
    if not a or not b:                                   # need both samples
        return 1.0                                       # worst case when one side is empty
    grid = sorted(set(a) | set(b))                       # evaluate CDFs on the pooled support
    na, nb = len(a), len(b)                              # sample sizes
    d = 0.0                                              # running max gap
    for x in grid:                                       # at each support point
        fa = sum(1 for v in a if v <= x) / na            # empirical CDF of sample a
        fb = sum(1 for v in b if v <= x) / nb            # empirical CDF of sample b
        d = max(d, abs(fa - fb))                         # track the largest vertical distance
    return d                                             # the KS statistic


def jsd(a: list, b: list) -> float:
    """Jensen-Shannon divergence (base-2, in [0,1]) between two value distributions."""
    if not a or not b:                                   # need both samples
        return 1.0                                       # maximal divergence on empty input
    support = sorted(set(a) | set(b))                    # discrete bins = observed values
    pa = [a.count(x) / len(a) for x in support]          # categorical distribution of a
    pb = [b.count(x) / len(b) for x in support]          # categorical distribution of b
    m = [(pa[i] + pb[i]) / 2 for i in range(len(support))]  # the mixture distribution

    def _kl(p, q):                                       # KL(p||q) with 0*log0 = 0 convention
        s = 0.0                                          # accumulator
        for pi, qi in zip(p, q):                         # term by term
            if pi > 0 and qi > 0:                        # skip zero-probability bins
                s += pi * math.log2(pi / qi)             # base-2 KL contribution
        return s                                         # the divergence
    return 0.5 * _kl(pa, m) + 0.5 * _kl(pb, m)           # symmetric JS divergence


def _pearson(x: list, y: list) -> float | None:
    """Pearson correlation; None if undefined (n<2 or zero variance)."""
    n = len(x)                                           # number of paired points
    if n < 2:                                            # need at least two subgroups
        return None
    mx = sum(x) / n; my = sum(y) / n                     # means
    sxy = sum((x[i] - mx) * (y[i] - my) for i in range(n))  # covariance numerator
    sxx = sum((x[i] - mx) ** 2 for i in range(n))        # variance of x
    syy = sum((y[i] - my) ** 2 for i in range(n))        # variance of y
    if sxx == 0 or syy == 0:                             # a flat series has undefined correlation
        return None
    return sxy / math.sqrt(sxx * syy)                    # Pearson r


def validate(responses_path: str, benchmark_path: str, thresholds: dict,
             personas_path: str | None = None, subgroup_var: str | None = None,
             value_field: str | None = None, allow_missing_subgroup: bool = False) -> dict:
    """Run all fidelity metrics and return a structured report with an overall verdict.

    `allow_missing_subgroup`: by default a run whose subgroup correlation is not computable
    (no personas/subgroup column, or <2 subgroups) FAILS — the Argyle fidelity floor is the
    single most important number and must not be silently skipped. Pass True to explicitly
    opt out (e.g. a design with no subgroup structure); the opt-out is recorded in the report.
    """
    # --- load synthetic responses, grouped by item and (optionally) by persona ---
    syn_by_item = {}                                     # item_id -> [values]
    syn_by_persona = {}                                  # persona_id -> {item_id -> [values]}
    n_parsed = 0; n_unparsed = 0; n_ambiguous = 0        # parse diagnostics (incl. multi-number replies)
    for row in (json.loads(l) for l in open(responses_path) if l.strip()):  # stream responses.jsonl
        if row.get("error"):                             # skip errored generations
            continue
        v, ambiguous = _parse_value(row, value_field)    # extract a numeric value + ambiguity flag
        if v is None:                                    # could not parse a response
            n_unparsed += 1; continue                    # count and skip
        n_parsed += 1                                    # successful parse
        if ambiguous:                                    # parsed from text with >1 number present
            n_ambiguous += 1                             # surface as a diagnostic, don't silently bias
        item = _item_of(row["custom_id"])                # which item
        pid = _persona_of(row["custom_id"])              # which persona
        syn_by_item.setdefault(item, []).append(v)       # collect per item
        syn_by_persona.setdefault(pid, {}).setdefault(item, []).append(v)  # collect per persona x item

    # --- load human benchmark, grouped by item and (optionally) subgroup ---
    hum_by_item = {}                                     # item_id -> [values]
    hum_by_item_subgroup = {}                            # item_id -> {subgroup -> [values]}
    with open(benchmark_path) as f:                      # read the long-format CSV
        for row in csv.DictReader(f):                    # one human response per row
            try:
                v = float(row["value"])                  # numeric human value
            except (KeyError, ValueError):
                continue                                 # skip malformed rows
            item = row.get("item_id", "item")            # item key
            hum_by_item.setdefault(item, []).append(v)   # collect per item
            sg = row.get("subgroup")                     # optional subgroup label
            if sg is not None:                           # build subgroup buckets when present
                hum_by_item_subgroup.setdefault(item, {}).setdefault(sg, []).append(v)

    # --- optional persona -> subgroup map for the fidelity correlation ---
    persona_subgroup = {}                                # persona_id -> subgroup label
    if personas_path and subgroup_var:                   # only when both are supplied
        for p in (json.loads(l) for l in open(personas_path) if l.strip()):  # read personas.jsonl
            persona_subgroup[p["persona_id"]] = str(p.get(subgroup_var))     # map id -> attribute value

    # --- per-item metrics ---
    items_report = {}                                    # item_id -> metric dict
    for item in sorted(set(syn_by_item) | set(hum_by_item)):  # union of items on both sides
        a = syn_by_item.get(item, [])                    # synthetic values
        b = hum_by_item.get(item, [])                    # human values
        mean_a = sum(a) / len(a) if a else float("nan")  # synthetic mean
        mean_b = sum(b) / len(b) if b else float("nan")  # human mean
        # Human standard error for the coverage band.
        se_b = (math.sqrt(sum((x - mean_b) ** 2 for x in b) / (len(b) - 1)) / math.sqrt(len(b))
                if len(b) > 1 else float("nan"))         # SE of the human mean
        d_ks = ks_statistic(a, b)                        # KS statistic
        d_js = jsd(a, b)                                 # Jensen-Shannon divergence
        diff = mean_a - mean_b                           # mean difference (synthetic - human)
        in_band = (not math.isnan(se_b)) and abs(diff) <= 2 * se_b  # within human +/-2SE?
        items_report[item] = {                           # collect the per-item metrics
            "n_synthetic": len(a), "n_human": len(b),
            "mean_synthetic": round(mean_a, 4), "mean_human": round(mean_b, 4),
            "mean_diff": round(diff, 4), "ks": round(d_ks, 4), "jsd": round(d_js, 4),
            "within_2se_band": bool(in_band),
            "pass_ks": d_ks <= thresholds["ks_max"],     # per-metric pass flags
            "pass_jsd": d_js <= thresholds["jsd_max"],
            "pass_mean": abs(diff) <= thresholds["abs_mean_diff_max"],
        }

    # --- subgroup-correlation (algorithmic fidelity): synthetic vs human subgroup means ---
    subgroup_r = None                                    # default null when not computable
    subgroup_detail = {}                                 # item -> {subgroup -> (syn_mean, hum_mean)}
    if persona_subgroup and hum_by_item_subgroup:        # need both maps
        syn_means = []; hum_means = []                   # paired series across (item, subgroup)
        for item, sg_map in hum_by_item_subgroup.items():  # for each item with subgroup human data
            # Compute synthetic subgroup means by routing each persona's responses to its subgroup.
            syn_sg = {}                                  # subgroup -> [values] (synthetic)
            for pid, items_map in syn_by_persona.items():  # walk personas
                sg = persona_subgroup.get(pid)           # this persona's subgroup
                if sg is None or item not in items_map:  # skip if unknown subgroup or no response
                    continue
                syn_sg.setdefault(sg, []).extend(items_map[item])  # accumulate values
            for sg, hvals in sg_map.items():             # for each human subgroup on this item
                if sg in syn_sg and syn_sg[sg]:          # need a matching synthetic subgroup
                    sm = sum(syn_sg[sg]) / len(syn_sg[sg])   # synthetic subgroup mean
                    hm = sum(hvals) / len(hvals)             # human subgroup mean
                    syn_means.append(sm); hum_means.append(hm)  # add the paired point
                    subgroup_detail.setdefault(item, {})[sg] = [round(sm, 4), round(hm, 4)]
        subgroup_r = _pearson(syn_means, hum_means)      # correlation across all (item,subgroup) pairs

    # --- coverage + overall verdict ---
    covered = sum(1 for r in items_report.values() if r["within_2se_band"])  # items within the band
    coverage = covered / len(items_report) if items_report else 0.0          # fraction covered
    pass_coverage = coverage >= thresholds["coverage_min"]                   # coverage threshold
    pass_subgroup = (subgroup_r is not None) and (subgroup_r >= thresholds["subgroup_r_min"])  # fidelity floor
    # An item "passes" only if all three of its per-item metrics pass.
    item_pass_rate = (sum(1 for r in items_report.values()
                          if r["pass_ks"] and r["pass_jsd"] and r["pass_mean"])
                      / len(items_report)) if items_report else 0.0
    # Overall verdict requires ALL THREE: (1) coverage clears its floor; (2) at least
    # `item_pass_rate_min` (default 80%) of items pass every per-item metric; (3) the Argyle
    # subgroup fidelity floor is cleared when computable, and is NOT silently skipped when it
    # is not — a non-computable subgroup correlation FAILS unless explicitly opted out (recorded).
    subgroup_ok = pass_subgroup or (subgroup_r is None and allow_missing_subgroup)
    verdict_pass = (pass_coverage
                    and item_pass_rate >= thresholds["item_pass_rate_min"]
                    and subgroup_ok)

    return {                                             # the full fidelity report
        "verdict": "PASS" if verdict_pass else "FAIL",
        "thresholds": thresholds,
        "n_responses_parsed": n_parsed, "n_responses_unparsed": n_unparsed,
        "n_responses_ambiguous": n_ambiguous,            # parsed from text w/ >1 number (first taken)
        "coverage": round(coverage, 4), "pass_coverage": pass_coverage,
        "item_pass_rate": round(item_pass_rate, 4),
        "subgroup_correlation": (round(subgroup_r, 4) if subgroup_r is not None else None),
        "pass_subgroup_correlation": pass_subgroup,
        "allow_missing_subgroup": allow_missing_subgroup,  # records the opt-out for auditability
        "subgroup_detail": subgroup_detail,
        "items": items_report,
        "note": ("Synthetic data is not a substitute for human data. A PASS means coverage holds, "
                 ">=item_pass_rate_min of items clear all per-item metrics, AND (unless opted out) "
                 "the subgroup-correlation fidelity floor is met — not that it is valid for any "
                 "other population, item, or model version. Report all numbers, not just the verdict."),
    }


def main(argv: list) -> int:
    """CLI: validate --responses R --benchmark B --out O [--personas P --subgroup-var V --thresholds J]."""
    import argparse                                       # stdlib arg parsing
    ap = argparse.ArgumentParser(description="Validate synthetic responses against a human benchmark.")
    ap.add_argument("--responses", required=True)         # responses.jsonl
    ap.add_argument("--benchmark", required=True)         # human benchmark CSV
    ap.add_argument("--out", required=True)               # fidelity.json output
    ap.add_argument("--personas", default=None)           # optional personas.jsonl for subgroups
    ap.add_argument("--subgroup-var", default=None)       # optional subgroup attribute name
    ap.add_argument("--value-field", default=None)        # optional pre-parsed numeric field name
    ap.add_argument("--thresholds", default=None)         # optional JSON string/file overriding defaults
    ap.add_argument("--allow-missing-subgroup", action="store_true",  # explicit, recorded opt-out
                    help="PASS even when subgroup correlation is not computable (default: FAIL)")
    args = ap.parse_args(argv)                            # parse

    thresholds = dict(DEFAULT_THRESHOLDS)                 # start from strict defaults
    if args.thresholds:                                   # allow inline JSON or a path
        raw = args.thresholds                             # the argument value
        if raw.strip().startswith("{"):                   # inline JSON object
            thresholds.update(json.loads(raw))
        else:                                             # treat as a file path
            thresholds.update(json.load(open(raw)))

    report = validate(args.responses, args.benchmark, thresholds,           # run all metrics
                      personas_path=args.personas, subgroup_var=args.subgroup_var,
                      value_field=args.value_field,
                      allow_missing_subgroup=args.allow_missing_subgroup)    # honor the recorded opt-out
    with open(args.out, "w") as f:                        # persist the full report
        json.dump(report, f, indent=2)
    # Print a compact summary and set the exit code from the verdict (so gates can branch on it).
    print(json.dumps({k: report[k] for k in
                      ("verdict", "coverage", "item_pass_rate", "subgroup_correlation",
                       "n_responses_ambiguous", "allow_missing_subgroup")}, indent=2))
    print(f"fidelity report -> {args.out}")
    return 0 if report["verdict"] == "PASS" else 1        # non-zero exit on FAIL (hard-gate friendly)


if __name__ == "__main__":                                # direct execution
    raise SystemExit(main(sys.argv[1:]))                  # propagate verdict as exit code
