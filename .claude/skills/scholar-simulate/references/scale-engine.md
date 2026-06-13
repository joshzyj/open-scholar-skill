# Scale Engine (MODE 8: run)

This file is loaded by **MODE 8 (run)** and underlies the run step of modes 3/4/5. It documents how the engine (`assets/simulate_engine.py`) scales from dozens to hundreds of thousands of agent-calls: the three scale strategies, prompt caching, idempotent checkpoint/resume, the cost ledger and pre-flight estimate, and the headless poll loop. All scaled work runs through the engine — never hand-rolled in-conversation loops.

```bash
# The three engine verbs (stable CLI contract):
python3 "$SKILL_DIR/assets/simulate_engine.py" personas --spec <spec.json> --n <N> --out <personas.jsonl>
python3 "$SKILL_DIR/assets/simulate_engine.py" run      --manifest <run-manifest.json> [--dry-run] [--resume]
python3 "$SKILL_DIR/assets/simulate_engine.py" validate --responses <responses.jsonl> --benchmark <human.csv> --out <fidelity.json>
```

---

## The three scale strategies (`scale_strategy` in the manifest)

| Strategy | Backend | Best for | Throughput | Cost |
|----------|---------|----------|------------|------|
| **`batch`** | Managed Batch API (Anthropic Message Batches / OpenAI Batch) | Thousands–hundreds of thousands of calls, not time-critical | High aggregate; latency up to 24h | ~50% off standard token price |
| **`async`** | Concurrent live requests against any cloud provider | Hundreds–low thousands, need fast turnaround | Rate-limit bound (RPM/TPM caps) | Full standard price |
| **`local`** | Async against a local Ollama/vLLM server | Sensitive seeds (no egress), unlimited free volume | Bounded by your hardware | $0 per token |

### `batch` — managed Batch API

The cost-efficient path for large runs. Both Anthropic Message Batches and OpenAI Batch:

- Discount **~50%** off standard per-token pricing.
- Complete within **≤24 hours** (often much faster); asynchronous — you submit, then poll.
- Accept up to **~100,000 requests per batch** (chunk larger runs into multiple batches; the engine does this automatically and tracks each batch id).
- Route results back by **`custom_id`** — the engine sets `custom_id = persona--item--rep--condition`, so every returned result maps deterministically to its request. This is also what makes resume idempotent.

Honest tradeoff: batch is cheapest and highest aggregate throughput but you wait (minutes to 24h). Do not use `batch` when you need a response in the next few seconds — use `async`.

### `async` — concurrent live requests

Fire many requests concurrently (bounded semaphore) against any cloud provider. Fast turnaround (seconds–minutes) but **rate-limit bound**: the provider's requests-per-minute (RPM) and tokens-per-minute (TPM) caps set the ceiling, and exceeding them triggers 429s. The engine backs off exponentially on 429 and caps concurrency to stay under the limits. Use for hundreds to low-thousands of calls where you cannot wait for a batch window. No batch discount — you pay full price.

### `local` — async against a local server

Async, but the endpoint is a local Ollama or vLLM server (`provider: ollama` or `openai-compatible` with a localhost `OPENAI_BASE_URL`). No per-token cost; throughput is bounded by your GPU/CPU. This is the right path for **sensitive persona seeds** (nothing leaves the machine — good under `LOCAL_MODE`) and for **truly large free runs** where cloud cost would be prohibitive. See `providers.md`.

> **Note: there is no managed batch for `openai-compatible` or `ollama`.** Together/Groq/OpenRouter/vLLM/LM Studio and local models have no 24h batch endpoint, so the engine falls back to `async`/`local` for them automatically. Only `anthropic` and `openai` support `scale_strategy: batch`.

---

## Prompt caching (do not re-pay for the shared scaffold)

In silicon sampling the **system prompt is mostly shared** across calls: the task framing, the response-format instruction, and (within a persona) the persona block repeat across every item, rep, and condition. Mark these stable prefixes with `cache_control` so the provider charges the (much cheaper) cache-read rate instead of re-billing the full input tokens each time.

```python
# The engine builds messages cache-first: stable prefix marked once, variable suffix appended fresh.
system = [
    {"type": "text", "text": TASK_FRAMING,                              # identical across ALL calls
     "cache_control": {"type": "ephemeral"}},                           # cache the global scaffold
    {"type": "text", "text": persona_block,                             # identical across this persona's calls
     "cache_control": {"type": "ephemeral"}},                           # cache the per-persona block
]
# Only the item/condition text differs per call -> it is the uncached, cheap-to-vary suffix.
user = [{"type": "text", "text": item_prompt}]                          # the variable part, not cached
```

Order matters: the cache key is a prefix match, so put the most-shared text first (global framing), then the persona, then the variable item last. With caching on (`"cache": true` in the manifest), a 2,000-persona × 20-item run re-pays the persona block once per persona rather than 20× — a large saving on input tokens. Caching composes with `batch` and `async`; it does nothing for `local` (no per-token cost anyway).

---

## Idempotent checkpoint / resume (survives session close)

Every completed response is appended to a JSONL checkpoint in `checkpoint_dir` keyed by `custom_id`. On `--resume`, the engine reads the checkpoint, computes the set of expected `custom_id`s from the manifest (personas × items × reps × conditions), and **re-queues only the gaps** — already-completed ids are never re-called.

```bash
# Resume a partially-completed run: only missing custom_ids are re-submitted. Safe to run repeatedly.
python3 "$SKILL_DIR/assets/simulate_engine.py" run \
  --manifest output/simulate/runs/trust-survey/run-manifest.json --resume
```

Properties this buys:

- **Idempotent** — re-running `--resume` after a partial failure costs nothing for work already done; it converges to a complete `responses.jsonl`.
- **Crash/close-safe** — because the checkpoint is on disk (not in memory), a closed session, a killed process, or a 24h batch window that spans an overnight all resume cleanly.
- **No double-billing** — completed `custom_id`s are skipped, so a resume never re-pays for them.

The checkpoint IS the run state; there is no separate database.

---

## Cost ledger + pre-flight estimate

`--dry-run` builds personas, assembles every prompt, writes the request manifest, and prints a **cost estimate + request count** while making **zero API calls**. Always dry-run before a paid batch.

```bash
# Pre-flight: see exactly how many requests and how many dollars BEFORE spending anything.
python3 "$SKILL_DIR/assets/simulate_engine.py" run --manifest <manifest>.json --dry-run
# -> prints: N_requests, est_input_tokens, est_output_tokens, est_cost_usd (batch-discounted if batch),
#            and whether est_cost_usd exceeds cost_cap_usd.
```

- The estimate multiplies request count × per-call token estimate × the provider's current per-token price (batch-discounted when `scale_strategy: batch`), and accounts for cache hits when `cache: true`.
- During a real run the engine writes a **cost ledger** (`<checkpoint_dir>/cost-ledger.jsonl`): one line per batch/chunk with realized input/output tokens and dollar cost, so the final cost is observed, not just estimated.
- **`cost_cap_usd`** in the manifest is a hard stop: if the pre-flight estimate or the running ledger exceeds the cap, the engine refuses to submit (or halts) rather than silently overspending. Raise the cap deliberately, never bypass it.

---

## Headless run wrapper (long/large runs)

A thousands-agent batch can outlive an interactive session (especially a 24h batch window). Run it headless so it survives session close — the wrapper submits, then poll-loops until the batch completes, writing checkpoints as results land:

```bash
# Launch detached; the wrapper polls the batch and resumes from checkpoint until complete.
nohup bash "$SKILL_DIR/assets/run-simulate.sh" \
  output/simulate/runs/<run_id>/run-manifest.json \
  > output/simulate/runs/<run_id>/run.log 2>&1 &
# Check progress any time by tailing the log or counting checkpoint lines:
#   wc -l output/simulate/runs/<run_id>/responses.jsonl
```

`run-simulate.sh` wraps `simulate_engine.py run --resume` in a poll loop (same pattern as `scholar-monitor/run-monitor.sh`): submit → sleep → poll batch status → on partial completion append to checkpoint → repeat → exit when all `custom_id`s are present. Because it calls `--resume`, killing and relaunching it is safe.

---

## What MODE 8 hands off

- `responses.jsonl` (complete, checkpoint-backed) for the run.
- `cost-ledger.jsonl` with realized cost (consumed by the reproducibility archive).
- A run that is reproducible from the pinned manifest (provider, exact model id, temperature, seed, scale strategy).

Next: MODE 6 (`validation-fidelity.md`) — mandatory before any claim. For adaptive multi-batch orchestration (conditionally generating batch N+1 from batch N's results), see `dynamic-orchestration.md`.
