#!/usr/bin/env python3
"""scholar-simulate execution engine.

CLI entrypoint for LLM-powered social simulation at scale. Three subcommands:

  personas  --spec spec.json --n N --out personas.jsonl [--seed 42]
            Sample a persona pool from a real joint distribution (delegates to personas.py).

  run       --manifest run-manifest.json [--dry-run] [--resume]
            Fan out (condition x persona x item x rep) into model calls, execute via the
            chosen provider/scale-strategy, and checkpoint every response. --dry-run builds
            everything and prints a cost estimate but makes ZERO API calls.

  validate  --responses responses.jsonl --benchmark human.csv --out fidelity.json
            Score synthetic responses against a human benchmark (delegates to validate.py).

Design goals: the dry-run / persona / cost-estimate paths run on pure stdlib (no third-party
packages, no API key), so the smoke test exercises the full request-construction pipeline
offline. Provider SDKs are imported lazily only when a real call is made.
"""

from __future__ import annotations  # lazy annotation evaluation

import os                           # filesystem + environment
import sys                          # argv / stderr / exit codes
import json                         # manifest, items, checkpoints, ledger
import time                         # batch poll sleeps
import argparse                     # subcommand parsing

# Make sibling modules importable whether invoked as a script or a module.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))  # add assets/ dir to the path
import personas as personas_mod     # the IPF persona sampler
import providers as providers_mod   # the multi-provider abstraction


# --------------------------------------------------------------------------
# Request construction
# --------------------------------------------------------------------------
def _load_jsonl(path: str) -> list:
    """Read a JSONL file into a list of dicts (skips blank lines)."""
    rows = []                                            # accumulator
    with open(path) as f:                                # open the JSONL
        for line in f:                                   # one record per line
            line = line.strip()                          # drop trailing newline/space
            if line:                                     # ignore blank lines defensively
                rows.append(json.loads(line))            # parse and collect
    return rows                                          # list of dicts


def build_requests(manifest: dict, personas: list, items_doc: dict) -> list:
    """Expand the manifest into a flat list of providers.Request objects.

    Fan-out = conditions x personas x items x n_reps. The persona scaffold and global
    instructions go in the SYSTEM prompt (so they are prompt-cacheable across a persona's many
    items/reps); only the per-item text varies in the USER turn. Requests are grouped by
    (condition, persona) so cache locality is maximized for the async path.
    """
    conditions = manifest.get("conditions") or [{"name": "base", "overrides": {}}]  # default single arm
    n_reps = int(manifest.get("n_reps", 1))              # repetitions per (persona,item) for within-persona stochasticity
    base_system = items_doc.get("system", "You are simulating a survey respondent. Stay in character and answer concisely.")  # global instruction
    template = items_doc.get("task_template", "{item_text}\n\nOptions: {options}\nReply with ONLY the option label.")  # user-turn template
    items = items_doc.get("items", [])                   # the survey/vignette/conjoint items

    requests = []                                        # output list of Request objects
    for cond in conditions:                              # outer loop: experimental conditions/arms
        cond_name = cond.get("name", "base")             # arm name (part of the custom_id)
        ov = cond.get("overrides", {})                   # per-arm overrides (extra system text, item substitutions)
        cond_system_extra = ov.get("system", "")         # optional extra system text for this arm (the treatment)
        for p in personas:                               # middle loop: personas (grouped for cache locality)
            # System = global instruction + arm treatment + persona scaffold. Constant across this
            # persona's items/reps -> cacheable prefix.
            system = base_system                         # start with the global instruction
            if cond_system_extra:                        # append the treatment manipulation if any
                system += "\n\n" + cond_system_extra
            system += "\n\n" + p.get("description", "")   # the persona micro/macro scaffold from personas.py
            for it in items:                             # inner loop: items
                # Render the user turn from the template; tolerate missing fields gracefully.
                user = template.format(
                    item_text=it.get("text", ""),        # the question/vignette text
                    options=" | ".join(it.get("options", [])) or "(open-ended)",  # response options or open
                    **{k: v for k, v in it.items() if k not in ("text", "options")},  # any extra item fields
                )
                for rep in range(n_reps):                # repetitions to capture stochasticity
                    cid = f"{cond_name}|{p['persona_id']}|{it.get('item_id','item')}|r{rep}"  # join key
                    requests.append(providers_mod.Request(custom_id=cid, system=system, user=user,
                                                          cacheable_system=bool(manifest.get("cache", True))))
    return requests                                      # flat request list


# --------------------------------------------------------------------------
# Cost estimation (dry-run)
# --------------------------------------------------------------------------
def estimate_cost(manifest: dict, requests: list) -> dict:
    """Approximate USD cost for the run. Honest and conservative; never billing-authoritative.

    Accounts for: the batch ~50% discount when scale_strategy=batch; a rough prompt-cache
    credit when cache=True (repeated persona/system prefixes billed at ~10% after first hit).
    """
    model = manifest["model"]                            # pinned model id
    in_price, out_price = providers_mod.get_price(            # $/Mtok; pass provider so local backends
        model, manifest.get("price_per_mtok"), manifest.get("provider"))  # suppress the $0 mispricing warn
    max_out = int(manifest.get("max_tokens", 256))       # output token cap per call
    est = providers_mod.Provider.estimate_tokens         # the 4-chars/token heuristic

    total_in = 0                                         # estimated input tokens (sum)
    total_out = 0                                        # estimated output tokens (sum)
    cached_in = 0                                        # estimated input tokens served from cache
    seen_system = {}                                     # system-prefix -> times seen (for cache credit)
    for r in requests:                                   # walk every request
        sys_tok = est(r.system)                          # input tokens in the (cacheable) system prefix
        usr_tok = est(r.user)                            # input tokens in the per-item user turn
        total_in += sys_tok + usr_tok                    # accumulate input tokens
        total_out += max_out                             # assume the model uses its output cap (upper bound)
        if manifest.get("cache", True):                  # model the cache: first occurrence pays full, rest ~cached
            n = seen_system.get(r.system, 0)             # how many times we've seen this exact system prefix
            if n >= 1:                                   # a repeat -> system tokens are cache hits
                cached_in += sys_tok                     # count them as cached (cheaper)
            seen_system[r.system] = n + 1                # update the counter

    # Cached input billed at ~10% of the input price; uncached at full price.
    uncached_in = total_in - cached_in                   # full-price input tokens
    input_cost = (uncached_in * in_price + cached_in * in_price * 0.10) / 1_000_000  # $ for input
    output_cost = (total_out * out_price) / 1_000_000    # $ for output
    subtotal = input_cost + output_cost                  # before batch discount
    batch = manifest.get("scale_strategy") == "batch"    # is the managed batch discount in play?
    total = subtotal * (0.5 if batch else 1.0)           # apply ~50% batch discount when batching
    return {                                             # structured estimate for the operator to review
        "n_requests": len(requests),
        "model": model,
        "scale_strategy": manifest.get("scale_strategy"),
        "est_input_tokens": total_in,
        "est_cached_input_tokens": cached_in,
        "est_output_tokens": total_out,
        "est_cost_usd": round(total, 4),
        "batch_discount_applied": batch,
        "note": "approximate; reconcile against the provider invoice. local providers are ~$0.",
    }


# --------------------------------------------------------------------------
# Checkpoint store
# --------------------------------------------------------------------------
def _done_ids(responses_path: str) -> set:
    """Return the set of custom_ids already written (for idempotent --resume)."""
    done = set()                                         # ids we have completed
    if os.path.exists(responses_path):                   # only if a prior run wrote something
        for row in _load_jsonl(responses_path):          # read existing responses
            if not row.get("error"):                     # treat errored rows as NOT done so they re-queue
                done.add(row["custom_id"])               # record completed id
    return done                                          # used to skip already-finished requests


def _append_responses(responses_path: str, completions: list) -> None:
    """Append completions to the checkpoint JSONL (one per line)."""
    with open(responses_path, "a") as f:                 # append mode preserves prior progress
        for c in completions:                            # one line per completion
            f.write(json.dumps({                         # normalized response record
                "custom_id": c.custom_id, "text": c.text,
                "input_tokens": c.input_tokens, "output_tokens": c.output_tokens,
                "cached_tokens": c.cached_tokens, "error": c.error,
            }) + "\n")


def _log_cost(ledger_path: str, entry: dict) -> None:
    """Append one line to the cost ledger."""
    with open(ledger_path, "a") as f:                    # append mode (audit trail across flushes)
        f.write(json.dumps(entry) + "\n")                # one JSON record per flush/batch


# --------------------------------------------------------------------------
# run subcommand
# --------------------------------------------------------------------------
def cmd_run(args) -> int:
    """Execute (or dry-run) a simulation manifest."""
    with open(args.manifest) as f:                       # load the manifest
        manifest = json.load(f)

    # --- validate the manifest's provider/strategy up front (fail loudly) ---
    provider = manifest.get("provider")                  # vendor selection
    if provider not in providers_mod.PROVIDERS:          # guard against typos / unknown vendors
        print(f"ERROR: provider '{provider}' not in {sorted(providers_mod.PROVIDERS)}", file=sys.stderr)
        return 2
    strategy = manifest.get("scale_strategy", "async")   # batch | async | local
    if strategy not in ("batch", "async", "local"):      # guard the strategy field
        print(f"ERROR: scale_strategy '{strategy}' invalid (batch|async|local)", file=sys.stderr)
        return 2

    # --- load personas + items, build the request fan-out ---
    personas = _load_jsonl(manifest["personas"])         # the persona pool (from MODE 2)
    with open(manifest["items"]) as f:                   # the items document (survey/vignette/conjoint)
        items_doc = json.load(f)
    requests = build_requests(manifest, personas, items_doc)  # full (condition x persona x item x rep) fan-out

    # --- checkpoint directory + paths ---
    ckpt = manifest.get("checkpoint_dir") or os.path.join("output", "simulate", "runs", manifest.get("run_id", "run"))
    os.makedirs(ckpt, exist_ok=True)                     # ensure the run directory exists
    responses_path = os.path.join(ckpt, "responses.jsonl")   # per-response checkpoint store
    ledger_path = os.path.join(ckpt, "cost-ledger.jsonl")    # cost audit trail
    batch_state_path = os.path.join(ckpt, "batch-state.json")  # remembers a submitted batch id for resume

    # --- cost estimate (always computed; the only thing --dry-run does beyond this is stop) ---
    est = estimate_cost(manifest, requests)              # pre-flight estimate
    print(json.dumps(est, indent=2))                     # show the operator the request count + $ estimate

    if args.dry_run:                                     # dry-run path: write the request manifest, make NO calls
        req_dump = os.path.join(ckpt, "requests-preview.jsonl")  # human-inspectable request preview
        with open(req_dump, "w") as f:                   # write a preview of what WOULD be sent
            for r in requests:                           # one line per request (truncated for readability)
                f.write(json.dumps({"custom_id": r.custom_id,
                                    "system_preview": r.system[:200],
                                    "user_preview": r.user[:200]}) + "\n")
        with open(os.path.join(ckpt, "cost-estimate.json"), "w") as f:  # persist the estimate
            json.dump(est, f, indent=2)
        print(f"DRY RUN — wrote {len(requests)} request previews to {req_dump}; no API calls made.")
        return 0                                         # success without spending anything

    # --- enforce the cost cap before spending real money ---
    cap = manifest.get("cost_cap_usd")                   # optional hard ceiling
    if cap is not None and est["est_cost_usd"] > float(cap) and strategy != "local":  # local is ~free, skip the cap
        print(f"ERROR: estimated ${est['est_cost_usd']} exceeds cost_cap_usd ${cap}. "
              f"Raise the cap or reduce scope. No calls made.", file=sys.stderr)
        return 3                                         # refuse to exceed the budget

    # --- resume: skip requests already completed ---
    done = _done_ids(responses_path) if args.resume else set()  # completed ids (empty unless --resume)
    pending = [r for r in requests if r.custom_id not in done]  # only the gaps
    if args.resume:                                      # report what resume is doing
        print(f"RESUME — {len(done)} already done, {len(pending)} pending.")
    if not pending:                                      # nothing left to do
        print("All requests already completed.")
        return 0

    # --- construct the provider ---
    params = {k: manifest.get(k) for k in ("temperature", "top_p", "seed", "max_tokens")}  # sampling params
    prov = providers_mod.make_provider(provider, manifest["model"], params)  # concrete backend

    # --- execute ---
    if strategy == "batch":                              # managed Batch API path (anthropic/openai)
        if not prov.supports_batch:                      # compatible/local servers cannot batch
            print(f"ERROR: provider '{provider}' has no managed batch API; use async or local.", file=sys.stderr)
            return 4
        # Submit once, remember the batch id, then poll until ended (resumable across restarts).
        if os.path.exists(batch_state_path):             # a batch was already submitted earlier -> resume polling
            batch_id = json.load(open(batch_state_path))["batch_id"]  # recover the id
            print(f"Resuming poll of existing batch {batch_id}")
        else:                                            # fresh submission
            batch_id = prov.submit_batch(pending)        # submit all pending requests as one batch
            json.dump({"batch_id": batch_id, "submitted": time.time()}, open(batch_state_path, "w"))  # persist id
            print(f"Submitted batch {batch_id} ({len(pending)} requests). Polling…")
        while True:                                      # poll loop (the headless wrapper can also drive this)
            status, results = prov.poll_batch(batch_id)  # check status; results non-empty only when ended
            if results:                                  # batch finished -> persist and account
                _append_responses(responses_path, results)  # checkpoint every response
                got = sum(1 for c in results if not c.error)  # successful count
                errs = sum(1 for c in results if c.error)     # error count
                in_tok = sum(c.input_tokens for c in results)  # billed input tokens
                out_tok = sum(c.output_tokens for c in results)  # billed output tokens
                _log_cost(ledger_path, {"batch_id": batch_id, "ok": got, "errors": errs,
                                        "input_tokens": in_tok, "output_tokens": out_tok, "ts": time.time()})
                print(f"Batch {batch_id} done: {got} ok, {errs} errors -> {responses_path}")
                break                                    # exit the poll loop
            print(f"  batch status={status}; sleeping 30s…")  # progress heartbeat
            time.sleep(30)                               # back off between polls (batches take minutes–24h)
    else:                                                # async / local concurrency path
        # Chunk the pending requests so we checkpoint frequently (crash-safe progress).
        chunk = int(manifest.get("flush_every", 50))     # responses per checkpoint flush
        for i in range(0, len(pending), chunk):          # walk the pending list in chunks
            batch = pending[i:i + chunk]                 # this flush's requests
            results = prov.complete_async(batch, max_concurrency=int(manifest.get("max_concurrency", 8)))  # call
            _append_responses(responses_path, results)   # checkpoint immediately (idempotent on resume)
            in_tok = sum(c.input_tokens for c in results)   # input tokens this flush
            out_tok = sum(c.output_tokens for c in results)  # output tokens this flush
            errs = sum(1 for c in results if c.error)        # errors this flush
            _log_cost(ledger_path, {"flush": i // chunk, "n": len(results), "errors": errs,
                                    "input_tokens": in_tok, "output_tokens": out_tok, "ts": time.time()})
            print(f"  flush {i//chunk}: {len(results)-errs}/{len(results)} ok (cumulative -> {responses_path})")

    print(f"Run complete. Responses: {responses_path}  Ledger: {ledger_path}")
    return 0                                              # success


# --------------------------------------------------------------------------
# personas + validate subcommands (delegate to sibling modules)
# --------------------------------------------------------------------------
def cmd_personas(args) -> int:
    """Delegate to personas.py's CLI (kept as one engine entrypoint for users)."""
    return personas_mod.main(
        ["--spec", args.spec, "--n", str(args.n), "--out", args.out, "--seed", str(args.seed)]
    )


def cmd_validate(args) -> int:
    """Delegate to validate.py's CLI, forwarding the optional subgroup/threshold flags."""
    import validate as validate_mod                      # lazy import (keeps numpy/scipy off other paths)
    fwd = ["--responses", args.responses, "--benchmark", args.benchmark, "--out", args.out]  # required args
    if args.personas:      fwd += ["--personas", args.personas]         # optional persona map for subgroups
    if args.subgroup_var:  fwd += ["--subgroup-var", args.subgroup_var] # optional subgroup attribute
    if args.value_field:   fwd += ["--value-field", args.value_field]   # optional pre-parsed value field
    if args.thresholds:    fwd += ["--thresholds", args.thresholds]     # optional threshold override
    if args.allow_missing_subgroup: fwd += ["--allow-missing-subgroup"]  # recorded opt-out of the fidelity floor
    return validate_mod.main(fwd)                         # run validation, propagate the PASS/FAIL exit code


def main(argv: list) -> int:
    """Top-level argument parser dispatching to the three subcommands."""
    ap = argparse.ArgumentParser(prog="simulate_engine.py", description="LLM-powered social simulation engine")
    sub = ap.add_subparsers(dest="cmd", required=True)   # require a subcommand

    p_per = sub.add_parser("personas", help="sample a persona pool from a joint distribution")
    p_per.add_argument("--spec", required=True); p_per.add_argument("--n", type=int, required=True)
    p_per.add_argument("--out", required=True); p_per.add_argument("--seed", type=int, default=42)
    p_per.set_defaults(func=cmd_personas)

    p_run = sub.add_parser("run", help="execute or dry-run a simulation manifest")
    p_run.add_argument("--manifest", required=True)      # the run manifest
    p_run.add_argument("--dry-run", action="store_true") # build + estimate, no API calls
    p_run.add_argument("--resume", action="store_true")  # skip already-completed requests
    p_run.set_defaults(func=cmd_run)

    p_val = sub.add_parser("validate", help="score synthetic responses vs a human benchmark")
    p_val.add_argument("--responses", required=True); p_val.add_argument("--benchmark", required=True)
    p_val.add_argument("--out", required=True)
    p_val.add_argument("--personas", default=None)       # optional personas.jsonl for subgroup correlation
    p_val.add_argument("--subgroup-var", default=None)   # optional persona attribute as the subgroup key
    p_val.add_argument("--value-field", default=None)    # optional pre-parsed numeric field name
    p_val.add_argument("--thresholds", default=None)     # optional JSON string/path overriding pass thresholds
    p_val.add_argument("--allow-missing-subgroup", action="store_true",  # recorded opt-out: PASS w/o subgroup r
                       help="PASS even when subgroup correlation is not computable (default: FAIL)")
    p_val.set_defaults(func=cmd_validate)

    args = ap.parse_args(argv)                            # parse the command line
    return args.func(args)                               # dispatch to the chosen subcommand


if __name__ == "__main__":                               # script entrypoint
    raise SystemExit(main(sys.argv[1:]))                 # propagate the subcommand's exit code
