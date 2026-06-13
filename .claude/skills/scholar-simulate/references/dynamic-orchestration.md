# Dynamic Orchestration (supporting reference)

This file is a supporting reference loaded when a run needs **adaptive** behavior — generating later work conditional on earlier results, running thousands of stateful agents, or injecting shocks mid-run.

> **HONESTY FIRST.** There is **no officially-named Anthropic "dynamic workflows" feature.** Do not cite one. The adaptive behavior researchers want is real, but it is achieved by composing concrete, documented mechanisms — the engine's checkpoint store, the Batch API, mid-conversation system messages / context editing, and (for a small number of rich agents) the in-session Task tool. This file maps each desired behavior to the real mechanism that delivers it.

And the load-bearing scale claim, stated plainly:

> **"Thousands of agents" means thousands of batched persona-calls orchestrated by the engine — NOT thousands of concurrent live sub-agents.** Live concurrency is bounded: the in-session **Task tool is ~20 practical**, and the **Agent SDK multiagent ceiling is 25 threads**. Scale comes from the Batch API processing many requests asynchronously, with per-agent state held in the external checkpoint store between turns — not from spinning up thousands of live threads.

---

## (a) Adaptive fan-out — generate batch N+1 from batch N's results

The orchestrator inspects a completed batch and conditionally constructs the next one. The loop is: run a batch → read its checkpoint/fidelity → decide what (if anything) to queue next → run again. Each iteration is an ordinary `simulate_engine.py run`; the adaptivity lives in the orchestrator's between-batch decision, not in any special API.

Two canonical uses:

- **Add personas where fidelity is low.** After MODE 6 validation on batch N, if a subgroup fails its fidelity threshold, generate additional personas/items targeting that subgroup (or re-run it under a calibrated config from MODE 7) as batch N+1. Stop when all subgroups pass or a budget cap is hit.
- **Add agent-network rounds until convergence.** In a generative ABM, run T steps as one batch, check a convergence statistic (e.g., change in the Gini coefficient of opinion heterogeneity, or the partisan opinion gap), and queue more steps only if opinions have not yet stabilized. Stop at convergence or a max-steps cap.

```python
# Adaptive fan-out skeleton: each round is a normal engine run; the loop decides whether to continue.
budget_left = manifest["cost_cap_usd"]                       # respect the hard cost cap across rounds
round_id = 0
while True:
    run_engine(manifest, run_id=f"round{round_id}", resume=True)   # one batch (idempotent on resume)
    metrics = read_fidelity_or_convergence(round_id)              # inspect THIS round's checkpoint output
    if metrics["converged"] or metrics["all_subgroups_pass"]:     # stopping rule, decided here not by an API
        break
    if budget_left <= 0 or round_id >= MAX_ROUNDS:               # honest budget/iteration guard
        log("stopped before convergence: budget/round cap reached"); break
    manifest = extend_manifest(manifest, metrics)                # e.g., add low-fidelity personas / +N steps
    budget_left -= round_spend(round_id)                         # decrement realized spend from the ledger
    round_id += 1
```

There is nothing magic here — it is a plain loop over the engine. Naming it honestly (an orchestrator-driven adaptive loop) avoids implying a feature that does not exist.

---

## (b) External-state multi-turn loops — thousands of STATEFUL agents, no thousands of live threads

A generative ABM needs each agent to **remember** its state across turns. Holding thousands of live conversation threads open simultaneously is infeasible (see the ceilings above). The engine instead persists each agent's state to the **checkpoint store** between turns and re-submits each turn as a fresh batched/async call seeded with that state.

The pattern for each step *t* → *t+1*:

1. Read every agent's persisted state (opinion, history, memory summary) from the checkpoint store.
2. For each agent, assemble the turn-*t* prompt = persona scaffold (cached) + its persisted state + what it observed this step (neighbors' current opinions).
3. Submit all agents' turn-*t* calls as **one batch** (thousands of requests, one custom_id each).
4. Parse results, write the new state back to the checkpoint store.
5. Repeat for step *t+1*.

So 5,000 agents × 20 steps = 100,000 requests processed across 20 batches — at no point are 5,000 live threads open. State lives on disk between batches; concurrency is whatever the Batch API absorbs. This is the mechanism that makes "5,000-agent opinion dynamics" real without violating the live-thread ceiling.

---

## (c) Mid-run steering — inject shocks/treatments at step t

To introduce a shock or treatment partway through a run (a misinformation injection, a policy announcement, a norm change), modify the affected agents' context **at the turn where the shock occurs** via a **mid-conversation system message** / context edit. Because the engine rebuilds each turn's prompt from persisted state anyway (mechanism b), inserting a steering message at step *t* is just adding a block to those agents' turn-*t* prompt.

```python
# At the shock step, prepend a steering system message to the treated agents' turn prompt.
def build_turn_prompt(agent, step, treated_ids, shock_text):
    blocks = [persona_scaffold(agent), persisted_state_block(agent), observation_block(agent, step)]
    if step == SHOCK_STEP and agent["id"] in treated_ids:        # only treated agents, only at step t
        blocks.insert(1, {"role": "system", "content": shock_text})  # inject the shock into context here
    return blocks                                                # control agents get the same prompt minus shock
```

This is how a **simulated experiment is embedded inside a generative ABM**: treated agents receive the mid-run shock at step *t*, control agents do not, and the divergence in their trajectories after *t* is the simulated treatment effect (estimate as AME, cluster within agent — see `silicon-sampling.md`).

Context editing also lets you **trim** stale context between turns (drop old observations, keep a running memory summary) so long ABMs stay within the context window without losing the agent's identity.

---

## (d) Bounded live deep-agents — the qualitative complement

For a **small number** of rich, multi-turn agents — e.g., a 6-person deliberation panel, a focus group, a negotiation dyad, or a simulated interview where you want full multi-turn reasoning and long memory per agent — there are two distinct mechanisms, and they are NOT interchangeable:

1. **MODE 10 interactive runner (`assets/interactive_runner.py`)** — the supported, reproducible path for a *structured conversation* (`paradigm: "interactive"`). It runs a **LangGraph** multi-agent graph (round-robin / dyad / supervisor topology) with **LangChain** chat-model adapters (`ChatOpenAI` / `ChatAnthropic` / `ChatOllama`), persists per-conversation state to LangGraph's native file-backed `SqliteSaver` (`thread_id = conversation_id`), and exports a flattened `transcripts.jsonl` for provenance uniformity with the bulk engine's `responses.jsonl`. It is a standalone CLI (`run --dry-run` is stdlib-only and free; `run` lazy-imports the quarantined extras), refuses `n_conversations > 50`, and enforces the LOCAL_MODE egress gate. **Tool execution is NOT implemented in this version** — agents run tool-free; a non-empty `tools[]` triggers a loud warning. See `interactive-multiagent.md` for the full contract and `validation-fidelity.md` for the UNVALIDATED-EXPLORATORY rule. This is the right choice when you want an archivable, restartable conversation graph.
2. **In-session Task tool** — for ad-hoc, *one-off* rich sub-agents that need real tool use and the orchestrator's own context (practical ceiling ~20; Agent SDK multiagent ceiling 25 threads). These are expensive, few, and **not** persisted to a checkpoint store or exported as transcripts — use them for exploratory in-session reasoning, not for an archived, reproducible simulation run.

Use the right tool for the scale and the goal:

| Need | Mechanism | Scale |
|------|-----------|-------|
| Thousands of agents, single-/few-turn, distributional | Batch API via the engine, state in checkpoint store | 10^3–10^5 |
| A handful of agents holding an archived, reproducible multi-turn *conversation* | MODE 10 `interactive_runner.py` (LangGraph + LangChain; `graph.sqlite` → `transcripts.jsonl`) | ≤ 50 conversations |
| Ad-hoc rich, tool-using sub-agents in-session (not persisted) | Live Task-tool sub-agents | ≤ ~20 |

Do not try to run thousands of agents through the Task tool or the interactive runner — both hit the live-thread / small-N ceiling. Do not try to run a rich multi-turn deliberation through a single batched call — it cannot carry that much live reasoning. Pick by whether you need *breadth* (batch), an *archived conversation* (MODE 10), or *ad-hoc in-session depth* (live Task agents).

---

## Summary: claims you may and may not make

- MAY: "We orchestrate N batched persona-calls adaptively, generating each batch conditional on the previous batch's fidelity/convergence."
- MAY: "Thousands of stateful agents are simulated by persisting per-agent state to an external checkpoint store between batched turns."
- MAY: "We inject a treatment at step t via a mid-conversation system message to the treated agents."
- MAY NOT: "We use Anthropic's dynamic-workflows feature" (no such named feature).
- MAY NOT: "We run thousands of concurrent live sub-agents" (live concurrency is ~20–25).

When in doubt, describe the concrete mechanism (batch + checkpoint + context edit), not a branded capability.
