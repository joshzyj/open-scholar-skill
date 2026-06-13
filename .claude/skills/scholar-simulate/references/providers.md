# Provider Matrix (supporting reference)

This file is the full provider matrix behind the `provider` field in the run manifest. The engine's provider abstraction (`assets/providers.py`) exposes a uniform `submit_batch` / `poll` / `complete_async` across all four backends, so a run is portable: change `provider` + `model` in the manifest and the same personas/items run elsewhere. The model id is always pinned in the manifest for reproducibility.

| `provider` | Backend | Managed batch? | Env vars | Cost profile |
|------------|---------|----------------|----------|--------------|
| `anthropic` | Claude Messages + Message Batches API | **Yes** (≤24h, ~50% off) | `ANTHROPIC_API_KEY` | Per-token; batch-discounted; prompt caching |
| `openai` | OpenAI Chat Completions + Batch API | **Yes** (≤24h, ~50% off) | `OPENAI_API_KEY` | Per-token; batch-discounted; prompt caching |
| `openai-compatible` | Together / Groq / OpenRouter / vLLM / LM Studio | **No** → use `async` (or `local` if localhost) | `OPENAI_BASE_URL`, `OPENAI_API_KEY` | Varies by host; often cheap; no batch discount |
| `ollama` | Local open models (Llama / Qwen / Mistral / Gemma) | n/a → `local` async | `OLLAMA_HOST` (default `http://localhost:11434`) | **$0 per token**; bounded by your hardware |

---

## `anthropic` — Claude Messages + Message Batches

- **Batch support:** yes. Message Batches API: ~50% discount, completes ≤24h, up to ~100k requests/batch, `custom_id` routing. The default cost-efficient path for large cloud runs.
- **Env:** `ANTHROPIC_API_KEY`.
- **Prompt caching:** `cache_control: {type: ephemeral}` on the shared system scaffold + persona block (see `scale-engine.md`). Large saving when personas repeat across items.
- **Choose when:** you want thousands–hundreds-of-thousands of cloud calls cheaply and can tolerate up to 24h latency; you want strong instruction-following for persona role-play. Pair with `scale_strategy: batch`. For fast hundreds-scale, use `scale_strategy: async` against the same provider.

## `openai` — Chat Completions + Batch

- **Batch support:** yes. OpenAI Batch API: ~50% discount, ≤24h, up to ~100k requests/batch (and a per-file size cap; the engine chunks accordingly), `custom_id` routing.
- **Env:** `OPENAI_API_KEY`.
- **Prompt caching:** automatic prefix caching on the shared scaffold.
- **Choose when:** same large-cloud-run profile as `anthropic`, or when a specific OpenAI model is the required/calibrated engine. Pair with `scale_strategy: batch` (or `async` for speed).

## `openai-compatible` — Together / Groq / OpenRouter / vLLM / LM Studio

- **Batch support:** **no managed 24h batch.** Use `scale_strategy: async` (concurrent live requests, rate-limit bound). If the endpoint is a localhost vLLM/LM Studio server, use `scale_strategy: local`.
- **Env:** `OPENAI_BASE_URL` (points the OpenAI-style client at the host) + `OPENAI_API_KEY` (the host's key; some local hosts accept any non-empty string).
- **Choose when:** you want a specific open-weight model served cheaply/fast (Groq for speed; Together/OpenRouter for model breadth), or you self-host with vLLM for throughput and control. No batch discount, so cost = full per-token at the host's rate; Groq-class hosts are fast but RPM/TPM-capped.

## `ollama` — local open models

- **Batch support:** n/a — runs `scale_strategy: local` (async against the local server). **No per-token cost**; throughput is bounded by your GPU/CPU.
- **Env:** `OLLAMA_HOST` (default `http://localhost:11434`). Pull the model first (e.g., `ollama pull qwen2.5:14b`).
- **Models:** Llama, Qwen, Mistral, Gemma families (pin the exact tag, e.g., `llama3.1:8b`, in the manifest).
- **Choose when:** **sensitive persona seeds** (privacy — see below), **unlimited free volume** (no API bill), offline/air-gapped work, or when you need full control of the model version. Slower per call than cloud, but free and private.

---

## Privacy advantage of local / open models (LOCAL_MODE)

When persona seeds are derived from sensitive microdata, running against a **local open model** (`ollama`, or `openai-compatible` pointed at a localhost vLLM/LM Studio server) means **no respondent-derived prompt ever leaves the machine**. There is zero data egress: the seed attributes, the persona prompts, and the responses all stay local.

This is the right configuration under the project's `LOCAL_MODE` data-safety status: the prompts that embed persona attributes never transit a third-party API, so the data-handling policy is satisfied by construction rather than by trusting a vendor's retention terms. Cloud providers (`anthropic`, `openai`, hosted `openai-compatible`) send prompts off-machine and are therefore inappropriate for sensitive seeds under `LOCAL_MODE`. (Validation benchmarks — real human data — are likewise handled locally; the engine emits only aggregated fidelity metrics, never row-level values.)

---

## Choosing a provider — decision guide

```
Are the persona seeds / benchmark sensitive (LOCAL_MODE)?
  YES -> local open model: provider=ollama (or openai-compatible @ localhost), scale_strategy=local.
         No egress. Free. Slower; bounded by your hardware. This is non-negotiable for sensitive seeds.
  NO  -> continue.

How many calls, and how fast do you need them?
  Thousands+ and can wait up to 24h  -> provider=anthropic or openai, scale_strategy=batch (~50% off).
  Hundreds-low thousands, need now    -> any cloud provider, scale_strategy=async (full price, fast).
  Unlimited volume, cost must be $0   -> provider=ollama, scale_strategy=local.

Need a specific open-weight model cheaply/fast on the cloud?
  -> provider=openai-compatible (Groq=speed, Together/OpenRouter=breadth), scale_strategy=async.
     Remember: NO managed batch here -> no 50% discount.

Always: pin the exact model id in the manifest. Run --dry-run for the cost estimate before any paid batch.
```

Rule of thumb: **`batch` on `anthropic`/`openai` for cheap scale; `local`/`ollama` for privacy and free volume; `async` on anything for speed at hundreds-scale.** The manifest's pinned `model` makes whichever you pick reproducible.

---

See `scale-engine.md` for the mechanics of each `scale_strategy` (caching, checkpoint/resume, cost ledger) and `dynamic-orchestration.md` for adaptive multi-batch loops.
