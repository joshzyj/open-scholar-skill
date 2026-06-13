"""Provider abstraction for scholar-simulate.

One uniform interface over four backends so the rest of the engine never branches on
vendor: `anthropic`, `openai`, `openai-compatible` (vLLM / Together / Groq / OpenRouter /
LM Studio), and `ollama` (local open models). Vendor SDKs and network I/O are imported
lazily *inside* the methods that need them, so `--dry-run`, persona sampling, and the smoke
tests run on pure stdlib with zero external packages and zero API keys.

Each backend exposes the same three operations:
  - complete_async(reqs, ...) -> list of Completion   (concurrent one-shot, rate-limit bound)
  - submit_batch(reqs, ...)   -> batch_id              (managed Batch API; anthropic/openai only)
  - poll_batch(batch_id, ...) -> (status, [Completion])
Providers without a managed batch API (openai-compatible, ollama) set supports_batch=False;
the engine falls back to async concurrency for those, which is the correct path for local
models anyway (no per-token cost, throughput bounded by your hardware, not by a price cap).
"""

from __future__ import annotations  # postpone annotation eval so type hints never import at runtime

import os                # read provider credentials / base URLs from the environment
import sys               # stderr warnings when a model is priced by guess (prefix/_local fallback)
import json              # serialize request bodies and parse batch result lines
from dataclasses import dataclass, field  # lightweight typed records for requests/completions

# Set of accepted provider identifiers; the engine validates the manifest's `provider` against this.
PROVIDERS = {"anthropic", "openai", "openai-compatible", "ollama"}

# Approximate USD pricing per 1M tokens (input, output) for cost ESTIMATION only.
# These are deliberately conservative defaults and are easy to override via the manifest's
# `price_per_mtok` field. They are NOT billing-authoritative — always reconcile against the
# provider's invoice. Local providers (ollama / self-hosted vLLM) are priced at zero because
# inference runs on hardware you already own.
DEFAULT_PRICES = {
    # Anthropic Claude 4.x family (standard tier; batch applies a ~50% discount handled in the engine).
    # Exact dotted ids are listed FIRST so they win the exact-id lookup before the bare-family prefix
    # fallback fires — without these rows `claude-opus-4-7` silently reused the `claude-opus-4` price.
    "claude-opus-4-7": (15.0, 75.0),      # Opus 4.7 input/output $/Mtok (current default Opus)
    "claude-opus-4-5": (15.0, 75.0),      # Opus 4.5 input/output $/Mtok
    "claude-sonnet-4-5": (3.0, 15.0),     # Sonnet 4.5 input/output $/Mtok
    "claude-haiku-4-5": (0.80, 4.0),      # Haiku 4.5 input/output $/Mtok
    # Bare-family rows kept as the deliberate prefix fallback for unlisted point releases.
    "claude-opus-4": (15.0, 75.0),        # Opus-class input/output $/Mtok (prefix fallback)
    "claude-sonnet-4": (3.0, 15.0),       # Sonnet-class input/output $/Mtok (prefix fallback)
    "claude-haiku-4": (0.80, 4.0),        # Haiku-class input/output $/Mtok (cheapest Claude for bulk sim)
    # OpenAI (representative; pin exact ids in the manifest).
    "gpt-4o": (2.5, 10.0),                # GPT-4o input/output $/Mtok
    "gpt-4o-mini": (0.15, 0.60),          # GPT-4o-mini — cheap bulk option
    # Local / open-source models cost nothing per token.
    "_local": (0.0, 0.0),                 # sentinel used for ollama and self-hosted endpoints
}


@dataclass
class Request:
    """One normalized model call, independent of provider wire format."""
    custom_id: str                         # stable key used to match a response back to its persona/item/turn
    system: str                            # system prompt (the part we prompt-cache when it repeats across personas)
    user: str                              # the user turn (persona scaffold + item); varies per request
    cacheable_system: bool = True          # whether `system` is eligible for prompt caching (repeats across the run)


@dataclass
class Completion:
    """One model response, normalized across providers."""
    custom_id: str                         # echoes Request.custom_id so the engine can join on it
    text: str                              # the model's text output (the simulated answer)
    input_tokens: int = 0                  # prompt tokens billed (for the cost ledger)
    output_tokens: int = 0                 # completion tokens billed (for the cost ledger)
    cached_tokens: int = 0                 # input tokens served from cache (billed at ~10%; excluded from ITPM)
    error: str = ""                        # non-empty if the call failed (engine records and can re-queue)


def get_price(model: str, override: dict | None = None,
              provider: str | None = None) -> tuple[float, float]:
    """Return (input_$per_Mtok, output_$per_Mtok) for cost estimation.

    Resolution order: explicit manifest override -> exact model id -> prefix match (WARN) -> 0 (WARN).
    Prefix matching lets an unlisted point release reuse its bare-family row, but that is a GUESS, so
    we surface it on stderr rather than mispricing silently. `provider` (when supplied) suppresses the
    zero-price warning for genuinely local backends (ollama / localhost openai-compatible), where $0 is
    correct rather than a missing-row symptom.
    """
    if override:                                           # manifest may carry an explicit price table
        return tuple(override)                             # trust the user-supplied (input, output) pair
    if model in DEFAULT_PRICES:                            # exact id hit (e.g., "gpt-4o", "claude-opus-4-7")
        return DEFAULT_PRICES[model]
    for prefix, price in DEFAULT_PRICES.items():           # fall back to longest sensible prefix
        if prefix != "_local" and model.startswith(prefix):
            # Inexact: a newer point release may be priced differently than its family row — say so.
            print(f"WARN: price for '{model}' not in table; using '{prefix}' row by prefix match — "
                  f"estimate may be inaccurate", file=sys.stderr)
            return price
    if provider not in ("ollama", "openai-compatible"):    # cloud model with no row => real mispricing, not local
        print(f"WARN: price for '{model}' not in table; assuming $0 (local) — "
              f"estimate may be inaccurate", file=sys.stderr)
    return DEFAULT_PRICES["_local"]                        # unknown model -> assume local/zero


class Provider:
    """Base class. Subclasses fill in the three operations; shared logic lives here."""

    supports_batch = False                                 # default: no managed batch API for this backend

    def __init__(self, model: str, params: dict):
        self.model = model                                 # exact, pinned model id from the manifest
        self.params = params                               # temperature / top_p / seed / max_tokens, already validated

    # --- token accounting -------------------------------------------------
    @staticmethod
    def estimate_tokens(text: str) -> int:
        """Cheap, dependency-free token estimate (~4 chars/token) for --dry-run cost math.

        This is intentionally approximate; it is used ONLY for the pre-flight estimate, never
        for billing. Real token counts come back from the provider in each Completion.
        """
        return max(1, len(text) // 4)                      # 4 chars/token heuristic, floor of 1

    # --- the three operations (overridden by subclasses) ------------------
    def complete_async(self, reqs, max_concurrency: int = 8):
        raise NotImplementedError                          # subclass must implement concurrent one-shot calls

    def submit_batch(self, reqs) -> str:
        raise NotImplementedError                          # subclass must implement (or inherit the no-batch guard)

    def poll_batch(self, batch_id: str):
        raise NotImplementedError                          # subclass must implement result retrieval


class AnthropicProvider(Provider):
    """Claude via the Anthropic SDK; supports the Message Batches API for thousands of calls."""

    supports_batch = True                                  # Anthropic offers a managed Batch API (~50% off, <=24h)

    def _client(self):
        # Lazy import keeps the SDK off the dry-run / smoke-test path.
        import anthropic                                   # requires `pip install anthropic` only when actually calling
        return anthropic.Anthropic(api_key=os.environ["ANTHROPIC_API_KEY"])  # key read at call time, not import time

    def _body(self, r: Request) -> dict:
        # Build a Messages API body; cache the system prompt when it repeats across personas.
        sys_block = [{"type": "text", "text": r.system}]   # system as a content block so we can attach cache_control
        if r.cacheable_system:                             # only mark cacheable when the system text repeats
            sys_block[0]["cache_control"] = {"type": "ephemeral"}  # 5-min TTL cache; cached input billed ~10%
        return {
            "model": self.model,                           # pinned model id
            "max_tokens": self.params.get("max_tokens", 256),  # cap output length (cost control)
            "temperature": self.params.get("temperature", 0.7),  # sampling temperature from manifest
            "top_p": self.params.get("top_p", 1.0),        # nucleus sampling from manifest
            "system": sys_block,                           # cacheable system prompt
            "messages": [{"role": "user", "content": r.user}],  # the persona+item user turn
        }

    def submit_batch(self, reqs) -> str:
        client = self._client()                            # construct SDK client (reads API key now)
        requests = [                                       # one batch entry per Request, keyed by custom_id
            {"custom_id": r.custom_id, "params": self._body(r)} for r in reqs
        ]
        batch = client.messages.batches.create(requests=requests)  # submit the whole batch in one call
        return batch.id                                    # return the batch id for later polling/resume

    def poll_batch(self, batch_id: str):
        client = self._client()                            # SDK client
        batch = client.messages.batches.retrieve(batch_id)  # current batch status
        if batch.processing_status != "ended":             # not finished yet
            return batch.processing_status, []             # engine will sleep and poll again
        out = []                                           # collect normalized completions
        for entry in client.messages.batches.results(batch_id):  # stream per-request results
            cid = entry.custom_id                          # the key we set at submit time
            if entry.result.type == "succeeded":           # a successful generation
                msg = entry.result.message                 # the Message object
                text = "".join(b.text for b in msg.content if b.type == "text")  # concat text blocks
                u = msg.usage                              # token usage for the ledger
                out.append(Completion(cid, text,
                                      input_tokens=getattr(u, "input_tokens", 0),
                                      output_tokens=getattr(u, "output_tokens", 0),
                                      cached_tokens=getattr(u, "cache_read_input_tokens", 0)))
            else:                                          # errored / expired / canceled
                out.append(Completion(cid, "", error=str(entry.result.type)))  # record so engine can re-queue
        return "ended", out                                # signal completion plus the results

    def complete_async(self, reqs, max_concurrency: int = 8):
        # Synchronous fallback loop (small/fast runs). Anthropic SDK calls are blocking;
        # for true concurrency the engine prefers submit_batch. We keep this simple and correct.
        client = self._client()                            # SDK client
        out = []                                           # normalized results
        for r in reqs:                                     # iterate requests one at a time
            try:
                msg = client.messages.create(**self._body(r))  # single blocking call
                text = "".join(b.text for b in msg.content if b.type == "text")  # extract text
                u = msg.usage                              # usage object
                out.append(Completion(r.custom_id, text,
                                      input_tokens=getattr(u, "input_tokens", 0),
                                      output_tokens=getattr(u, "output_tokens", 0),
                                      cached_tokens=getattr(u, "cache_read_input_tokens", 0)))
            except Exception as e:                          # never let one bad call abort the whole run
                out.append(Completion(r.custom_id, "", error=str(e)))  # record the error; engine may retry
        return out


class OpenAICompatProvider(Provider):
    """OpenAI and any OpenAI-compatible server (vLLM/Together/Groq/OpenRouter/LM Studio).

    `native_batch=True` (set for the genuine OpenAI endpoint) enables the managed Batch API.
    Compatible third-party/local servers usually lack batch, so they run via complete_async.
    """

    def __init__(self, model: str, params: dict, native_batch: bool = False):
        super().__init__(model, params)                    # store model + sampling params
        self.supports_batch = native_batch                 # only the real OpenAI endpoint sets this True

    def _client(self):
        from openai import OpenAI                           # lazy import; the `openai` pkg also drives compatible servers
        base = os.environ.get("OPENAI_BASE_URL")            # set this for vLLM/Together/Groq/OpenRouter/LM Studio
        key = os.environ.get("OPENAI_API_KEY", "not-needed")  # local servers often ignore the key
        return OpenAI(api_key=key, base_url=base) if base else OpenAI(api_key=key)  # route to the right endpoint

    def _messages(self, r: Request) -> list:
        # OpenAI-style chat messages: a system role plus the user turn.
        return [{"role": "system", "content": r.system},   # system prompt (caching is automatic server-side on OpenAI)
                {"role": "user", "content": r.user}]        # the persona+item user turn

    def complete_async(self, reqs, max_concurrency: int = 8):
        client = self._client()                            # construct the (possibly redirected) client
        out = []                                           # normalized completions
        for r in reqs:                                     # sequential, robust loop (one failure never aborts the run)
            try:
                resp = client.chat.completions.create(     # standard chat-completions call
                    model=self.model,                      # pinned model id (or local model name)
                    messages=self._messages(r),            # system + user
                    temperature=self.params.get("temperature", 0.7),  # sampling temperature
                    top_p=self.params.get("top_p", 1.0),   # nucleus sampling
                    max_tokens=self.params.get("max_tokens", 256),  # output cap
                    seed=self.params.get("seed"),          # OpenAI honors seed for best-effort determinism
                )
                text = resp.choices[0].message.content or ""  # the generated answer
                u = resp.usage                             # usage block (may be None on some compatible servers)
                out.append(Completion(r.custom_id, text,
                                      input_tokens=getattr(u, "prompt_tokens", 0) if u else 0,
                                      output_tokens=getattr(u, "completion_tokens", 0) if u else 0))
            except Exception as e:                          # capture and continue
                out.append(Completion(r.custom_id, "", error=str(e)))  # engine can re-queue errored ids
        return out

    def submit_batch(self, reqs) -> str:
        if not self.supports_batch:                        # compatible/local servers have no managed batch
            raise RuntimeError("batch not supported by this endpoint; use scale_strategy=async or local")
        client = self._client()                            # real OpenAI client
        # Build a JSONL of /v1/chat/completions requests, upload it, then create a batch job.
        lines = []                                         # accumulate one JSON object per request
        for r in reqs:                                     # each persona/item/turn becomes a batch line
            lines.append(json.dumps({
                "custom_id": r.custom_id,                  # join key
                "method": "POST",                          # batch requests are POSTs
                "url": "/v1/chat/completions",             # target endpoint
                "body": {                                  # the actual chat-completions body
                    "model": self.model,
                    "messages": self._messages(r),
                    "temperature": self.params.get("temperature", 0.7),
                    "top_p": self.params.get("top_p", 1.0),
                    "max_tokens": self.params.get("max_tokens", 256),
                },
            }))
        import io                                          # in-memory file for the upload (no temp file on disk)
        buf = io.BytesIO("\n".join(lines).encode())        # JSONL payload as bytes
        buf.name = "batch.jsonl"                           # the SDK uses the .name attribute as the filename
        up = client.files.create(file=buf, purpose="batch")  # upload the request file
        job = client.batches.create(input_file_id=up.id,   # create the batch job over the uploaded file
                                    endpoint="/v1/chat/completions",
                                    completion_window="24h")  # 24h window unlocks the ~50% discount
        return job.id                                      # batch job id for polling

    def poll_batch(self, batch_id: str):
        client = self._client()                            # OpenAI client
        job = client.batches.retrieve(batch_id)            # current job status
        if job.status != "completed":                      # still validating / in_progress / finalizing
            return job.status, []                          # engine sleeps and polls again
        content = client.files.content(job.output_file_id).text  # download the result JSONL
        out = []                                           # normalized completions
        for line in content.splitlines():                  # one JSON object per line
            if not line.strip():                           # skip blank lines defensively
                continue
            try:
                obj = json.loads(line)                     # parse the result record
            except json.JSONDecodeError as e:              # one malformed line must not crash the whole poll
                print(f"WARN: skipping unparseable batch result line: {e}", file=sys.stderr)
                continue                                   # drop the bad record; recover the rest of the JSONL
            cid = obj.get("custom_id", "")                 # the join key we set at submit
            body = (obj.get("response") or {}).get("body") or {}  # nested response body
            choices = body.get("choices") or [{}]          # choices array (guard against malformed records)
            text = (choices[0].get("message") or {}).get("content", "")  # the generated answer
            u = body.get("usage") or {}                    # usage dict
            out.append(Completion(cid, text,
                                  input_tokens=u.get("prompt_tokens", 0),
                                  output_tokens=u.get("completion_tokens", 0)))
        return "completed", out                            # done plus results


class OllamaProvider(Provider):
    """Local open-source models via an Ollama server. No managed batch; runs local async.

    Uses only stdlib urllib so the engine needs no extra package to drive a local model.
    Ideal for sensitive persona seeds: nothing leaves the machine, and there is no per-token cost.
    """

    supports_batch = False                                 # Ollama has no batch endpoint; engine uses local async

    def _host(self) -> str:
        return os.environ.get("OLLAMA_HOST", "http://localhost:11434").rstrip("/")  # default local daemon

    def complete_async(self, reqs, max_concurrency: int = 8):
        import urllib.request                              # stdlib HTTP client (no third-party dep)
        out = []                                           # normalized completions
        for r in reqs:                                     # iterate requests (local server; loop is fine)
            payload = json.dumps({                         # Ollama /api/chat request body
                "model": self.model,                       # local model name, e.g. "llama3.1" / "qwen2.5"
                "messages": [{"role": "system", "content": r.system},  # system prompt
                             {"role": "user", "content": r.user}],     # user turn
                "stream": False,                           # return a single JSON object, not a token stream
                "options": {                               # Ollama sampling options
                    "temperature": self.params.get("temperature", 0.7),  # temperature
                    "top_p": self.params.get("top_p", 1.0),              # nucleus sampling
                    "seed": self.params.get("seed", 0),                  # seed for reproducibility
                    "num_predict": self.params.get("max_tokens", 256),   # output token cap
                },
            }).encode()                                    # bytes for the POST body
            req = urllib.request.Request(self._host() + "/api/chat",  # local chat endpoint
                                         data=payload,
                                         headers={"Content-Type": "application/json"})
            try:
                with urllib.request.urlopen(req, timeout=600) as resp:  # generous timeout for slow local GPUs
                    obj = json.loads(resp.read().decode())  # parse the JSON response
                text = (obj.get("message") or {}).get("content", "")  # the generated answer
                # Ollama returns prompt/eval counts; surface them for the (zero-cost) ledger.
                out.append(Completion(r.custom_id, text,
                                      input_tokens=obj.get("prompt_eval_count", 0),
                                      output_tokens=obj.get("eval_count", 0)))
            except Exception as e:                          # local server down / model not pulled / OOM
                out.append(Completion(r.custom_id, "", error=str(e)))  # record; engine can re-queue
        return out


def make_provider(provider: str, model: str, params: dict) -> Provider:
    """Factory: map a manifest `provider` string to a concrete Provider instance."""
    if provider == "anthropic":                            # native Claude path (has batch)
        return AnthropicProvider(model, params)
    if provider == "openai":                               # native OpenAI path (has batch)
        return OpenAICompatProvider(model, params, native_batch=True)
    if provider == "openai-compatible":                    # vLLM/Together/Groq/OpenRouter/LM Studio (no batch)
        return OpenAICompatProvider(model, params, native_batch=False)
    if provider == "ollama":                               # local open models (no batch)
        return OllamaProvider(model, params)
    raise ValueError(f"unknown provider '{provider}'; expected one of {sorted(PROVIDERS)}")  # fail loudly
