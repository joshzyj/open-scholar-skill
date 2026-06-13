"""Persona sampler for scholar-simulate.

Builds a persona pool from REAL joint distributions instead of hand-invented exemplars.
Given marginal (and optional multi-way) target distributions from a real source — census
tables, GSS/ANES crosstabs — it fits a full joint via Iterative Proportional Fitting (IPF,
a.k.a. raking), then draws N personas from the fitted joint with a seeded RNG so the pool is
reproducible. Pure stdlib (no numpy/pandas) so the dry-run path and smoke tests need nothing
installed.

Spec format (JSON):
{
  "variables": {                       # categorical variables and their category labels
    "age":       {"categories": ["18-29","30-49","50-64","65+"]},
    "education": {"categories": ["<HS","HS","College","Grad"]},
    "party":     {"categories": ["Dem","Ind","Rep"]}
  },
  "marginals": [                        # target distributions to rake toward (must sum ~1 each)
    {"vars": ["age"],          "target": {"18-29":0.21,"30-49":0.34,"50-64":0.25,"65+":0.20}},
    {"vars": ["education"],    "target": {"<HS":0.10,"HS":0.28,"College":0.42,"Grad":0.20}},
    {"vars": ["party"],        "target": {"Dem":0.33,"Ind":0.34,"Rep":0.33}},
    {"vars": ["age","party"],  "target": {"18-29|Dem":0.09, ...}}   # OPTIONAL associations
  ],
  "context":  {"time_period":"2024","country":"US"},   # macro context merged into every persona
  "source":   "ANES 2020 weighted marginals",          # provenance string (REQUIRED for the methods text)
  "persona_prefix": "p"                                  # id prefix
}

Multi-variable marginal keys join category labels with "|" in the order of `vars`.
"""

from __future__ import annotations  # lazy annotations so type hints never import at runtime

import json                         # read the spec and write personas.jsonl
import itertools                    # cartesian product of category labels -> joint cells
import random                       # seeded RNG for reproducible sampling
import sys                          # stderr warnings / exit codes


def _project(cell: dict, vars_: list) -> str:
    """Project a full cell (var->label dict) onto a subset of vars, as a '|'-joined key."""
    return "|".join(cell[v] for v in vars_)             # e.g. {"age":"30-49","party":"Dem"} on ["age","party"] -> "30-49|Dem"


def fit_joint(spec: dict, max_iter: int = 50, tol: float = 1e-6) -> tuple[list, list]:
    """Fit a full joint distribution to the marginal targets via IPF.

    Returns (cells, probs) where cells is a list of var->label dicts and probs the matched
    probability for each cell (parallel lists, summing to 1).
    """
    variables = spec["variables"]                        # the categorical schema
    var_names = list(variables.keys())                   # stable variable order
    cat_lists = [variables[v]["categories"] for v in var_names]  # category labels per variable

    # Enumerate every combination of categories = the support of the joint distribution.
    cells = []                                           # list of var->label dicts (one per cell)
    for combo in itertools.product(*cat_lists):          # cartesian product across all variables
        cells.append({var_names[i]: combo[i] for i in range(len(var_names))})  # build the cell dict

    n_cells = len(cells)                                 # total number of joint cells
    if n_cells == 0:                                     # nothing to fit -> fail loudly
        raise ValueError("no joint cells: check `variables` in the spec")

    # Initialize from a seed joint if provided, else uniform (maximum entropy starting point).
    seed_joint = spec.get("seed_joint")                  # optional prior joint keyed by full '|' label
    if seed_joint:                                       # user supplied a starting joint (e.g., independence model)
        probs = [max(seed_joint.get(_project(c, var_names), 0.0), 1e-12) for c in cells]  # floor to avoid zeros
    else:                                                # default: uniform over all cells
        probs = [1.0 / n_cells] * n_cells                # every combination equally likely a priori

    # IPF: repeatedly rescale cells so each marginal constraint is satisfied; iterate to convergence.
    for _ in range(max_iter):                            # bounded iterations (IPF converges fast for consistent targets)
        max_delta = 0.0                                  # track the largest adjustment this pass (for the tol check)
        for constraint in spec.get("marginals", []):     # each raking target
            cvars = constraint["vars"]                    # which variables this constraint is over
            target = constraint["target"]                 # desired distribution over those variables
            # Current marginal implied by `probs`, summed over the cells matching each projected key.
            current = {}                                  # projected-key -> current probability mass
            for i, c in enumerate(cells):                 # walk every cell once
                key = _project(c, cvars)                  # its projection onto the constraint vars
                current[key] = current.get(key, 0.0) + probs[i]  # accumulate mass into that margin bucket
            # Rescale each cell by target/current for its margin bucket (the IPF update step).
            for i, c in enumerate(cells):                 # second pass applies the multiplicative adjustment
                key = _project(c, cvars)                  # same projection
                tgt = target.get(key, 0.0)                # desired mass for this bucket (0 if unspecified)
                cur = current.get(key, 0.0)               # current mass for this bucket
                if cur > 0:                               # avoid divide-by-zero on empty buckets
                    factor = tgt / cur                    # adjustment factor toward the target
                    new = probs[i] * factor               # rescaled cell probability
                    max_delta = max(max_delta, abs(new - probs[i]))  # record the change magnitude
                    probs[i] = new                        # commit the update
        # Renormalize so the joint remains a proper distribution after the pass.
        s = sum(probs)                                    # current total mass (drifts from 1 during updates)
        probs = [p / s for p in probs] if s > 0 else probs  # back to sum=1
        if max_delta < tol:                               # converged: last pass barely moved anything
            break                                         # stop early
    return cells, probs                                   # the fitted joint


def sample_personas(spec: dict, n: int, seed: int = 42) -> list:
    """Draw N personas from the fitted joint. Deterministic given (spec, n, seed)."""
    cells, probs = fit_joint(spec)                        # fit the joint once
    rng = random.Random(seed)                             # seeded RNG for reproducibility
    # Build a cumulative distribution for inverse-CDF sampling.
    cum = []                                              # running cumulative probabilities
    running = 0.0                                         # accumulator
    for p in probs:                                       # walk cells in fitted order
        running += p                                      # add this cell's mass
        cum.append(running)                               # store the cumulative boundary
    context = spec.get("context", {})                     # macro context merged into every persona
    prefix = spec.get("persona_prefix", "p")              # id prefix
    personas = []                                         # output list
    for k in range(n):                                    # draw N independent personas
        u = rng.random()                                  # uniform draw in [0,1)
        # Find the first cell whose cumulative boundary exceeds u (inverse-CDF lookup).
        idx = next((i for i, b in enumerate(cum) if u <= b), len(cum) - 1)  # fallback to last cell on rounding edge
        cell = cells[idx]                                 # the selected category combination
        persona = dict(cell)                              # copy the var->label assignments
        persona["persona_id"] = f"{prefix}{k+1:05d}"      # zero-padded stable id (p00001 ...)
        persona["_context"] = context                     # attach macro context
        persona["description"] = _describe(cell, context) # natural-language micro scaffold for the prompt builder
        personas.append(persona)                          # collect
    return personas


def _describe(cell: dict, context: dict) -> str:
    """Render a cell + context into a compact natural-language persona description.

    The prompt builder uses this as the persona scaffold. We keep it neutral and factual;
    richer narratives can be layered in by the caller via the spec's persona template.
    """
    parts = [f"{k}: {v}" for k, v in cell.items()]        # "age: 30-49", "party: Dem", ...
    ctx = [f"{k}: {v}" for k, v in context.items()]       # macro context as "time_period: 2024", ...
    attrs = "; ".join(parts)                              # join individual attributes
    macro = ("; ".join(ctx)) if ctx else ""               # join context attributes
    base = f"You are a person with the following characteristics — {attrs}."  # micro description
    return base + (f" Context — {macro}." if macro else "")  # append macro context when present


def write_personas(personas: list, out_path: str) -> None:
    """Write personas as JSONL (one persona per line)."""
    with open(out_path, "w") as f:                        # truncate/create the output file
        for p in personas:                                # one line per persona
            f.write(json.dumps(p) + "\n")                 # compact JSON line


def main(argv: list) -> int:
    """Standalone CLI: `personas.py --spec spec.json --n 1000 --out personas.jsonl [--seed 42]`."""
    import argparse                                       # stdlib arg parsing
    ap = argparse.ArgumentParser(description="Sample personas from a joint distribution (IPF/raking).")
    ap.add_argument("--spec", required=True, help="path to the persona spec JSON")  # required spec
    ap.add_argument("--n", type=int, required=True, help="number of personas to sample")  # pool size
    ap.add_argument("--out", required=True, help="output personas.jsonl path")  # destination
    ap.add_argument("--seed", type=int, default=42, help="RNG seed for reproducibility")  # determinism
    args = ap.parse_args(argv)                            # parse
    with open(args.spec) as f:                            # load the spec
        spec = json.load(f)
    if not spec.get("source"):                            # provenance is mandatory for the methods text
        print("WARNING: spec has no `source` provenance string; required for reproducible reporting.", file=sys.stderr)
    personas = sample_personas(spec, args.n, args.seed)   # draw the pool
    write_personas(personas, args.out)                    # persist as JSONL
    print(f"wrote {len(personas)} personas -> {args.out} (seed={args.seed}, source={spec.get('source','UNSPECIFIED')})")
    return 0                                              # success exit code


if __name__ == "__main__":                                # allow direct execution
    raise SystemExit(main(sys.argv[1:]))                  # pass through the exit code
