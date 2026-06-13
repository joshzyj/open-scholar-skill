# Interactive Multi-Agent Simulation (MODE 10)

This file is loaded by **MODE 10 (interactive)** — small-N, multi-turn, multi-agent **conversations** served by `assets/interactive_runner.py` (LangGraph + LangChain). It is the deliberate complement to the bulk batch engine: where MODE 3/5 fan out thousands of single-shot completions, MODE 10 runs *a few dozen* branching, stateful conversations (simulated focus group, deliberation panel, negotiation dyad, interview).

> **THE CARDINAL RULE STILL HOLDS.** Synthetic interaction is **not** a substitute for human interaction data. Multi-agent LLM conversation is the **least-validated** simulation use — it is seductive and easy to over-read. Use it for pre-testing protocols, theory exploration, and hypothesis generation. Any substantive claim requires a held-out **human-transcript** benchmark; absent one, MODE 6 returns `UNVALIDATED-EXPLORATORY` (see `validation-fidelity.md`).

---

## When MODE 10 vs MODE 4 (disambiguation — read this first)

Both involve "agents," so route by **mechanism**, not topic:

| Use | Mode | Mechanism | Scale | Output |
|-----|------|-----------|-------|--------|
| Opinion dynamics, diffusion, segregation, mechanistic/hybrid ABM over a network | **MODE 4 generative-abm** | Mechanistic kernels (Schelling/Deffuant/SIR) or batched LLM turns with state in the engine checkpoint store | 10²–10⁵ agents | Distributional / emergent statistics |
| Focus group, deliberation, negotiation, debate, simulated interview — a *conversation* with branching turn-taking | **MODE 10 interactive** | LangGraph multi-agent graph; LangChain chat models; native SqliteSaver state | ≤ ~50 conversations | Transcripts (+ descriptive interaction stats) |

If you need **breadth** (thousands of agents, distributional fidelity) → MODE 4. If you need **depth** (a handful of agents holding a real multi-turn conversation that branches on what was said) → MODE 10. Do not route a thousands-agent run here; the runner refuses `n_conversations > 50`.

---

## Why a framework here (and not in the bulk engine)

The bulk engine is framework-free by design (single-shot, large-N, batch-discounted, reproducibility-sensitive — see the methods appendix §A.3.1). MODE 10 is the one case that genuinely *is* a stateful graph: conditional turn-taking, per-agent memory, multi-agent topologies. The dependency is **quarantined**:

- `langchain` / `langgraph` are **lazy-imported only in the live run path**. `--dry-run` is pure stdlib.
- Extras live in `assets/requirements-interactive.txt` (opt-in; the base engine never imports them).
- **DECISION A**: model clients are LangChain chat adapters (`ChatOpenAI` / `ChatAnthropic` / `ChatOllama`), selected from the manifest `provider`/`model`.
- **DECISION B**: persistence is LangGraph's **native** file-backed `SqliteSaver` (`thread_id = conversation_id`). At end of run the runner **exports** a flattened `transcripts.jsonl` keyed `conversation_id|t{turn}|{agent_id}`, so reporting and the replication package consume the same shape as the bulk engine's `responses.jsonl`.

---

## Manifest fields (interactive paradigm)

Set `"paradigm": "interactive"`. In addition to the shared fields (`run_id`, `provider`, `model`, `temperature`, `seed`, `max_tokens`, `checkpoint_dir`, `cost_cap_usd`):

```json
{
  "run_id": "council-deliberation",
  "paradigm": "interactive",
  "provider": "ollama",
  "model": "llama3.1:8b",
  "temperature": 0.7,
  "max_tokens": 256,
  "topology": "round-robin",
  "max_turns": 12,
  "n_conversations": 8,
  "termination": {"on": "max_turns", "signal": "[[END]]"},
  "scenario": "A city council deliberates a proposed protected bike lane.",
  "tools": [],
  "agents": [
    {"id": "moderator", "role": "moderator", "system": "You moderate the deliberation; prompt each member in turn."},
    {"id": "member_pro", "role": "pro", "persona_ref": "p000123", "system": "You support the lane on safety grounds."},
    {"id": "member_con", "role": "con", "persona_ref": "p000456", "system": "You worry about parking and business access."}
  ],
  "checkpoint_dir": "output/simulate/runs/council-deliberation",
  "cost_cap_usd": 5.0
}
```

- **`agents[]`** (≥ 2 required): each is a node in the graph. `persona_ref` optionally grounds an agent in a `personas.jsonl` row (MODE 2), so a conversation can be staffed from the raked synthetic population.
- **`topology`**: `round-robin` (agents cycle), `dyad` (two-party exchange), `supervisor` (a router agent picks the next speaker — simplified in this version).
- **`max_turns`**: hard per-conversation ceiling (also caps cost).
- **`termination`**: `max_turns`, or `agent_signal` (an agent emits `signal` to end early).
- **`n_conversations`**: small-N by design; the runner refuses > 50.
- **`tools[]`**: accepted for forward compatibility but **TOOL EXECUTION IS NOT IMPLEMENTED in this version** — agents run tool-free, and a non-empty `tools[]` triggers a loud warning. Under LOCAL_MODE `tools[]` must be empty (external-egress tools are prohibited).

---

## Running it

The interactive runner is a **standalone CLI** (separate from `simulate_engine.py`):

```bash
# 1) ALWAYS dry-run first (stdlib only; no deps, no API key, zero calls):
python3 "$SKILL_DIR/assets/interactive_runner.py" run --manifest <manifest.json> --dry-run
#    -> writes conversation-plan.jsonl + cost-estimate.json; prints the model-call count + $ estimate.

# 2) Install the quarantined extras once, then live-run:
pip install -r "$SKILL_DIR/assets/requirements-interactive.txt"
python3 "$SKILL_DIR/assets/interactive_runner.py" run --manifest <manifest.json>
#    -> runs the LangGraph multi-agent graph; persists to graph.sqlite; exports transcripts.jsonl.

# 3) Re-derive the flattened transcript from the checkpoint store if needed:
python3 "$SKILL_DIR/assets/interactive_runner.py" export --manifest <manifest.json> [--out transcripts.jsonl]
```

Outputs in `checkpoint_dir`:
- `conversation-plan.jsonl` — who speaks each turn, per conversation (dry-run).
- `cost-estimate.json` — model-call count + token/cost estimate (dry-run).
- `graph.sqlite` — LangGraph native checkpoint store (durable, resumable; live run).
- `transcripts.jsonl` — flattened export, one utterance per line: `{custom_id, conversation_id, turn, agent_id, text}`.
- `validation.json` — machine-checkable validation record (verdict `UNVALIDATED-EXPLORATORY`); written in **both** dry-run and live branches (see Validation below).

---

## Data safety (LOCAL_MODE)

When agents are grounded in sensitive persona seeds, the runner enforces a **hard egress gate** before any live call: under `LOCAL_MODE` it refuses any provider that would send prompts off-machine (only `ollama`, or `openai-compatible` with a localhost `OPENAI_BASE_URL`, are allowed) and requires `tools[]` to be empty. This mirrors the bulk engine's privacy posture — no respondent-derived prompt leaves the machine.

---

## Validation (MODE 6 is not bypassed)

Interactive output is conversation, not a distribution, so the distributional metrics (KS/JSD/mean-diff) do not apply directly. The honest contract:

- Without a held-out **human-transcript** benchmark on the same scenario, MODE 6 returns **`UNVALIDATED-EXPLORATORY`** — the run may inform protocol design and hypotheses but supports **no** substantive claim.
- With a human-transcript benchmark, compare **descriptive interaction statistics** (turns per agent, message-length distributions, turn-taking balance, and — where coded — topic/stance trajectories) against the human transcripts, and report the comparison.
- The mandatory limitations (homogenization, steerability, training recency, intersectionality, rare populations) all still apply, **plus** an interaction-specific caveat: LLM agents converge to agreeable, fluent consensus and underproduce the conflict, interruption, and silence of real deliberation. State this explicitly.

**Executable record (`validation.json`) — different gate semantics from the MODE 6 exit gate.** The runner writes `<checkpoint_dir>/validation.json` on every `run` (dry-run and live), mirroring the verification checklist in `validation-fidelity.md` as booleans (`transcripts_present`, `benchmark_compared`, `tool_use_claimed`, `interaction_limitation_disclosed`) under verdict `UNVALIDATED-EXPLORATORY`. Unlike `validate.py` (a PASS/FAIL gate that exits 1 to halt full-paper Branch C), this record is **intentionally non-PASS** and the runner **never exits non-zero on account of it** — a conversation transcript has no benchmark distribution to pass. The contract is **"the record EXISTS and is honestly labelled,"** not "PASS." MODE 9 reporting and Branch C consume it as exploratory-only; if it is absent, the output is not carried into the manuscript. Never launder this verdict into a fidelity PASS or read its zero exit code as a distributional pass.

---

## Reporting

Hand the write-up to **MODE 9** (`reporting-templates.md`, interactive section): name the topology, agent roles + persona grounding, `max_turns`, `n_conversations`, provider + exact model id, temperature/seed, and the validation status (`UNVALIDATED-EXPLORATORY` unless a human-transcript benchmark cleared). Archive the manifest, `graph.sqlite`, and `transcripts.jsonl`. Citations are delegated to `/scholar-citation` — never hand-author `.bib`; flag unverified claims `[CITATION NEEDED]`.

---

## Method citations (preserve; do not invent)

- Generative agents / believable multi-agent behavior: Park et al. (2023).
- Silicon sampling (persona grounding): Argyle et al. (2023), *Political Analysis*.
- Distributional-mismatch / validation caution: Bisbee et al. (2023), *Political Analysis*.

Citations are delegated to `/scholar-citation`; never hand-author `.bib`.
