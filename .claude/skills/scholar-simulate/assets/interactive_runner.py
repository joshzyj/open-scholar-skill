#!/usr/bin/env python3
"""scholar-simulate INTERACTIVE paradigm runner (LangGraph + LangChain).

Standalone CLI for the `interactive` paradigm: small-N, multi-turn, multi-agent
*conversations* (simulated focus group / deliberation / negotiation / interview).
This is the deliberate complement to the bulk batch engine (simulate_engine.py):

  * simulate_engine.py  -> large-N, single-shot, distributional, batch-discounted,
                           framework-free (reproducibility-sensitive bulk path).
  * interactive_runner.py (this file) -> small-N, multi-turn, branching control flow,
                           served by LangGraph with LangChain chat models.

Design contract (matches the rationale in the methods appendix, §A.3.1 / §A.10):
  - DECISION A: model clients are LangChain chat adapters (ChatOpenAI / ChatAnthropic /
    ChatOllama), selected from the manifest's provider/model.
  - DECISION B: persistence is LangGraph's NATIVE checkpointer (file-backed SqliteSaver,
    thread_id = conversation_id). At end of run we EXPORT a flattened transcripts.jsonl
    keyed `conversation_id|t{turn}|{agent_id}` so downstream reporting/replication stay
    uniform with the rest of scholar-simulate.
  - QUARANTINE: langchain/langgraph are imported LAZILY, only in the live run path. The
    `--dry-run` path is pure stdlib (no third-party packages, no API key), so the smoke
    layer exercises plan construction + cost estimation offline — exactly like the base
    engine's dry-run.

HONESTY CAVEATS (do not overstate this module):
  - The LIVE LangGraph path is written against the documented LangGraph/LangChain API but
    has NOT been executed in this environment (no deps/keys installed). The exact import
    path / constructor for SqliteSaver and the chat adapters can vary across langgraph
    versions; `_import_live()` centralizes those so a version mismatch fails loudly with an
    actionable message rather than silently.
  - TOOL USE IS NOT IMPLEMENTED in this version. The manifest `tools[]` field is accepted
    for forward compatibility, but agents run tool-free; a non-empty `tools[]` triggers a
    loud warning. This keeps us from claiming a capability we do not ship (and is the safe
    default under LOCAL_MODE, where external-egress tools are prohibited anyway).
  - Multi-agent LLM conversation is the LEAST-validated simulation use. Without a held-out
    HUMAN-transcript benchmark, MODE 6 returns UNVALIDATED-EXPLORATORY (see
    references/validation-fidelity.md). This runner never asserts fidelity.
"""

from __future__ import annotations  # lazy annotation evaluation (keeps stdlib-only import light)

import os                           # filesystem + environment lookups
import sys                          # argv / stderr / exit codes
import json                         # manifest, plan, transcript, ledger I/O
import argparse                     # subcommand parsing

# Reuse the base engine's pricing + token-estimate helpers (providers.py is stdlib-only for
# these two functions; vendor SDKs inside it are lazy-imported and never touched on this path).
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))  # make sibling modules importable
import providers as providers_mod   # get_price() + Provider.estimate_tokens() (no network on import)

# --- hard limits (the interactive paradigm is small-N BY DESIGN) -----------------------------
HARD_CONV_CAP = 50      # refuse runs above this many conversations; this is not the bulk engine
DEFAULT_MAX_TURNS = 12  # default per-conversation turn ceiling when the manifest omits it
LOCAL_PROVIDERS = {"ollama", "openai-compatible"}  # the only providers allowed under LOCAL_MODE


# ---------------------------------------------------------------------------------------------
# Manifest + safety helpers (stdlib only)
# ---------------------------------------------------------------------------------------------
def _load_manifest(path: str) -> dict:
    """Load the run manifest JSON (fails loudly on malformed input)."""
    with open(path) as f:                       # open the manifest file
        return json.load(f)                      # parse and return the dict


def _safety_status() -> str:
    """Return SAFETY_STATUS from .claude/safety-status.json, or 'NONE' if absent/unreadable.

    The interactive runner enforces LOCAL_MODE the same way the rest of the plugin does:
    sensitive persona seeds must never transit a third-party API.
    """
    path = os.path.join(".claude", "safety-status.json")  # conventional sidecar location (cwd-relative)
    if not os.path.exists(path):                          # no sidecar -> nothing to enforce here
        return "NONE"                                     # caller treats this as unconstrained
    try:                                                  # be defensive: a corrupt sidecar must not crash dry-run
        with open(path) as f:                             # open the safety sidecar
            data = json.load(f)                           # parse it
        return str(data.get("SAFETY_STATUS", data.get("status", "NONE")))  # tolerate either key
    except Exception:                                     # unreadable/corrupt -> fail safe to NONE (loudly via stderr)
        print("WARNING: could not parse .claude/safety-status.json; treating as NONE", file=sys.stderr)
        return "NONE"


def _is_localhost(url: str | None) -> bool:
    """True if a base_url points at the local machine (used for the LOCAL_MODE egress gate)."""
    if not url:                                           # no base_url set
        return False                                      # cannot confirm locality -> treat as remote
    return any(h in url for h in ("localhost", "127.0.0.1", "0.0.0.0", "::1"))  # common local hosts


def _enforce_local_mode(manifest: dict) -> None:
    """Refuse to run an interactive simulation that would egress persona-derived prompts under LOCAL_MODE.

    Exits the process (non-zero) on violation — this is a hard safety gate, not a warning.
    """
    if _safety_status() != "LOCAL_MODE":                 # gate only applies under LOCAL_MODE
        return                                           # other statuses handled by the global data guard
    provider = manifest.get("provider")                  # which backend the manifest selected
    base_url = os.environ.get("OPENAI_BASE_URL")         # openai-compatible endpoint, if any
    local_ok = (provider == "ollama") or (provider == "openai-compatible" and _is_localhost(base_url))  # local?
    if not local_ok:                                     # a cloud endpoint under LOCAL_MODE is forbidden
        print(f"ERROR (LOCAL_MODE): provider '{provider}' would send persona prompts off-machine. "
              f"Use provider=ollama, or openai-compatible with a localhost OPENAI_BASE_URL.", file=sys.stderr)
        raise SystemExit(5)                              # hard stop; no egress
    if manifest.get("tools"):                            # tools could exfiltrate even on a local model
        print("ERROR (LOCAL_MODE): tools[] must be empty (external-egress tools are prohibited).", file=sys.stderr)
        raise SystemExit(5)                              # hard stop


# ---------------------------------------------------------------------------------------------
# Conversation plan + cost estimate (stdlib only; this is what --dry-run exercises)
# ---------------------------------------------------------------------------------------------
def build_conversation_plan(manifest: dict) -> list:
    """Expand the manifest into a list of conversation specs (no model calls).

    Each conversation runs up to `max_turns` turns; under round-robin/dyad one agent speaks
    per turn, so a conversation is ~max_turns model calls. This plan is what the operator
    inspects before spending, and what the cost estimate sums over.
    """
    agents = manifest.get("agents") or []                # the conversational roles
    n_conv = int(manifest.get("n_conversations", 1))     # how many independent conversations
    max_turns = int(manifest.get("max_turns", DEFAULT_MAX_TURNS))  # per-conversation turn ceiling
    topology = manifest.get("topology", "round-robin")   # graph shape (affects who speaks each turn)
    plan = []                                            # accumulator of conversation specs
    for c in range(n_conv):                              # one entry per conversation
        conv_id = f"conv{c:03d}"                         # stable conversation id (thread_id for the checkpointer)
        # Round-robin / dyad: agents speak in order, cycling, one call per turn.
        turn_speakers = [agents[t % len(agents)]["id"] for t in range(max_turns)] if agents else []
        plan.append({                                   # the inspectable conversation spec
            "conversation_id": conv_id,
            "topology": topology,
            "n_agents": len(agents),
            "max_turns": max_turns,
            "turn_speakers": turn_speakers,             # who speaks at each turn (custom_id agent component)
        })
    return plan                                         # list of conversation specs


def estimate_cost_interactive(manifest: dict, plan: list) -> dict:
    """Approximate USD cost for an interactive run (honest, conservative, never billing-authoritative).

    Per turn the speaking agent is prompted with its system brief plus the transcript so far.
    We approximate input tokens at turn t as (agent-system tokens) + (t * max_tokens) for the
    growing transcript, and output tokens as max_tokens. No batch discount: interactive runs
    are live multi-turn, so cost is full per-token. Local providers are ~$0.
    """
    model = manifest["model"]                            # pinned model id
    in_price, out_price = providers_mod.get_price(            # $/Mtok; pass provider so local backends
        model, manifest.get("price_per_mtok"), manifest.get("provider"))  # suppress the $0 mispricing warn
    max_out = int(manifest.get("max_tokens", 256))       # output cap per turn
    est = providers_mod.Provider.estimate_tokens         # 4-chars/token heuristic (shared with the bulk engine)
    agents = {a["id"]: a for a in (manifest.get("agents") or [])}  # id -> agent (for system-prompt sizing)

    total_in = 0                                         # summed estimated input tokens
    total_out = 0                                        # summed estimated output tokens
    for conv in plan:                                   # walk each planned conversation
        for t, speaker_id in enumerate(conv["turn_speakers"]):   # each turn = one model call
            sys_txt = agents.get(speaker_id, {}).get("system", "")  # the speaker's role brief
            global_txt = manifest.get("scenario", "")     # optional shared scenario framing
            sys_tok = est(sys_txt) + est(global_txt)      # input tokens in the (stable) system prefix
            transcript_tok = t * max_out                  # rough size of the transcript-so-far at turn t
            total_in += sys_tok + transcript_tok          # accumulate input tokens for this turn
            total_out += max_out                          # assume the agent uses its output cap (upper bound)
    is_local = manifest.get("provider") == "ollama" or (
        manifest.get("provider") == "openai-compatible" and _is_localhost(os.environ.get("OPENAI_BASE_URL")))
    input_cost = (total_in * in_price) / 1_000_000        # $ for input tokens (no cache credit; transcripts differ)
    output_cost = (total_out * out_price) / 1_000_000     # $ for output tokens
    total = 0.0 if is_local else (input_cost + output_cost)  # local servers cost ~$0 per token
    n_calls = sum(len(c["turn_speakers"]) for c in plan)  # total model calls across all conversations
    return {                                             # structured estimate for the operator
        "paradigm": "interactive",
        "n_conversations": len(plan),
        "n_model_calls": n_calls,
        "model": model,
        "provider": manifest.get("provider"),
        "est_input_tokens": total_in,
        "est_output_tokens": total_out,
        "est_cost_usd": round(total, 4),
        "is_local": is_local,
        "note": "approximate; multi-turn transcripts grow per turn. reconcile against the provider invoice.",
    }


def _validate_interactive_manifest(manifest: dict) -> None:
    """Structural checks specific to the interactive paradigm (fail loudly before any spend)."""
    if manifest.get("paradigm") != "interactive":        # this runner is only for the interactive paradigm
        print(f"ERROR: paradigm must be 'interactive' (got '{manifest.get('paradigm')}'). "
              f"Use simulate_engine.py for silicon-survey/experiment/generative-abm.", file=sys.stderr)
        raise SystemExit(2)                              # wrong tool for the manifest
    agents = manifest.get("agents") or []                # the conversational roles
    if len(agents) < 2:                                  # multi-agent interaction needs >= 2 agents
        print(f"ERROR: interactive runs require >= 2 agents (got {len(agents)}).", file=sys.stderr)
        raise SystemExit(2)                              # not a multi-agent conversation
    n_conv = int(manifest.get("n_conversations", 1))     # requested conversation count
    if n_conv > HARD_CONV_CAP:                           # enforce the small-N design ceiling
        print(f"ERROR: n_conversations={n_conv} exceeds the small-N cap ({HARD_CONV_CAP}). "
              f"The interactive paradigm is not the bulk engine; reduce N or use simulate_engine.py.", file=sys.stderr)
        raise SystemExit(2)                              # refuse to misuse this path at scale
    if manifest.get("tools"):                            # tools are accepted but not executed in this version
        print("WARNING: tools[] is set but TOOL EXECUTION IS NOT IMPLEMENTED in this version; "
              "agents will run tool-free. Remove tools[] to silence this warning.", file=sys.stderr)


def _write_validation_record(manifest: dict, plan: list, ckpt_dir: str, *, live: bool) -> str:
    """Emit validation.json — the MODE 10 hard gate's EXECUTABLE record (UNVALIDATED-EXPLORATORY).

    Multi-agent conversation is not a distribution, so validate.py's PASS/FAIL metrics do not
    apply. The gate semantics therefore DIFFER from the bulk MODE 6 gate: the verdict here is
    INTENTIONALLY non-PASS, so this never exits non-zero. The contract is that an honestly-
    labelled validation record EXISTS alongside the transcripts; downstream (MODE 9 reporting,
    full-paper Branch C) reads this verdict and admits the run as exploratory-only, never
    confirmatory. The checklist mirrors the verification block in references/validation-fidelity.md.
    """
    transcripts_path = os.path.join(ckpt_dir, "transcripts.jsonl")  # the live export, if one was produced
    transcripts_nonempty = (live                                    # dry-run makes no calls -> no transcript
                            and os.path.exists(transcripts_path)    # the export file is present
                            and os.path.getsize(transcripts_path) > 0)  # and it actually has content
    tools_declared = bool(manifest.get("tools"))                   # tools[] is accepted but NEVER executed here
    record = {                                                     # the executable validation artifact
        "verdict": "UNVALIDATED-EXPLORATORY",                      # intentionally non-PASS (no human benchmark)
        "paradigm": "interactive",                                 # which simulation paradigm produced this
        "run_id": manifest.get("run_id", "interactive"),           # ties the record to its run
        "n_conversations": len(plan),                              # how many conversations were planned/run
        "max_turns": int(manifest.get("max_turns", DEFAULT_MAX_TURNS)),  # per-conversation turn ceiling
        "topology": manifest.get("topology", "round-robin"),       # graph shape
        "dry_run": (not live),                                     # True when no API calls were made
        "checklist": {                                             # mirrors validation-fidelity.md verification block
            "transcripts_nonempty": bool(transcripts_nonempty),    # item 1: a non-empty transcript exists
            "validation_status_stated": True,                      # item 2: this very record states the verdict
            "benchmark_compared": False,                           # item 3: no held-out human-transcript benchmark wired
            "interaction_limitation_disclosed": True,              # item 4: the disclaimer below carries it
            "tool_use_not_claimed": (not tools_declared),          # item 5: tools are never executed in this version
        },
        "disclaimer": ("Synthetic interaction is NOT a substitute for human interaction data. LLM agents "
                       "over-produce agreeable, fluent consensus and under-produce conflict, interruption, "
                       "overlapping talk, repair, and silence relative to real deliberation. This run supports "
                       "protocol/instrument design and hypothesis generation only — no substantive empirical "
                       "claim absent a held-out human-transcript benchmark."),
    }
    out_path = os.path.join(ckpt_dir, "validation.json")           # written alongside transcripts.jsonl
    with open(out_path, "w") as f:                                 # persist the record
        json.dump(record, f, indent=2)                            # human-readable, version-controllable
    return out_path                                               # path to the validation record


# ---------------------------------------------------------------------------------------------
# Live execution (LangGraph + LangChain) — lazy-imported; NOT exercised by the smoke layer
# ---------------------------------------------------------------------------------------------
def _import_live():
    """Lazily import LangGraph/LangChain, returning the symbols the runner needs.

    Centralizes the version-sensitive imports so a missing dep or a moved symbol fails with a
    single actionable message (install assets/requirements-interactive.txt) instead of a deep
    stack trace. Returns a dict of the pieces used by _build_graph / _run_conversations.
    """
    try:                                                                  # all live deps are optional extras
        from langgraph.graph import StateGraph, START, END                # the graph builder + sentinels
        from langgraph.graph.message import add_messages                  # reducer that appends messages to state
        try:                                                              # SqliteSaver import path varies by version
            from langgraph.checkpoint.sqlite import SqliteSaver           # newer layout
        except ImportError:                                              # fall back to the standalone package name
            from langgraph_checkpoint_sqlite import SqliteSaver           # older/standalone layout
        from langchain_core.messages import SystemMessage, HumanMessage, AIMessage  # message types
        return {                                                         # bundle the symbols for the caller
            "StateGraph": StateGraph, "START": START, "END": END,
            "add_messages": add_messages, "SqliteSaver": SqliteSaver,
            "SystemMessage": SystemMessage, "HumanMessage": HumanMessage, "AIMessage": AIMessage,
        }
    except ImportError as e:                                             # any missing piece -> actionable error
        print("ERROR: interactive (live) path needs LangGraph + LangChain. Install the quarantined extras:\n"
              "  pip install -r \"$SKILL_DIR/assets/requirements-interactive.txt\"\n"
              f"(import error: {e})", file=sys.stderr)
        raise SystemExit(6)                                             # cannot run live without the extras


def _make_chat_model(manifest: dict):
    """Build a LangChain chat model from the manifest's provider/model (DECISION A).

    Lazy-imports the provider-specific adapter so only the needed package is required.
    """
    # Offline test seam: SCHOLAR_FAKE_CHAT=1 returns a deterministic stub chat model so the
    # StateGraph loop can be exercised end-to-end with NO provider SDK, NO network, and NO API
    # key (used by the smoke layer when langgraph is installed). The stub mimics the only part of
    # the LangChain chat interface the graph consumes: .invoke(messages) -> object with .content.
    if os.environ.get("SCHOLAR_FAKE_CHAT") == "1":       # test-only deterministic offline stub
        class _FakeReply:                                # minimal stand-in for an AIMessage-like reply
            def __init__(self, content): self.content = content  # only .content is read downstream (line ~295)
        class _FakeChat:                                 # minimal stand-in for a LangChain chat model
            def invoke(self, messages):                  # mirror ChatModel.invoke(messages)
                depth = len(messages)                    # vary the reply by transcript depth (cheap determinism)
                return _FakeReply(f"[FAKE reply @ depth {depth}]")  # canned utterance; never calls a vendor
        return _FakeChat()                               # offline seam — never reaches a provider adapter
    provider = manifest.get("provider")                  # vendor selection
    model = manifest["model"]                             # pinned model id
    temperature = float(manifest.get("temperature", 0.7))  # sampling temperature
    if provider == "anthropic":                          # Claude via langchain-anthropic
        from langchain_anthropic import ChatAnthropic    # lazy import
        return ChatAnthropic(model=model, temperature=temperature)  # API key from ANTHROPIC_API_KEY
    if provider == "ollama":                             # local open models via langchain-ollama
        from langchain_ollama import ChatOllama          # lazy import
        base = os.environ.get("OLLAMA_HOST", "http://localhost:11434")  # local server
        return ChatOllama(model=model, temperature=temperature, base_url=base)  # $0/token, local
    if provider in ("openai", "openai-compatible"):      # OpenAI or any OpenAI-compatible server via langchain-openai
        from langchain_openai import ChatOpenAI          # lazy import
        base = os.environ.get("OPENAI_BASE_URL")         # set for vLLM/LM Studio/Together/Groq/OpenRouter
        kwargs = {"model": model, "temperature": temperature}  # common args
        if base:                                         # route to the compatible endpoint if configured
            kwargs["base_url"] = base                     # langchain-openai honors base_url
        return ChatOpenAI(**kwargs)                       # API key from OPENAI_API_KEY (local servers ignore it)
    print(f"ERROR: unknown provider '{provider}' for the interactive chat model.", file=sys.stderr)  # guard
    raise SystemExit(2)                                  # unknown vendor


def _build_graph(manifest: dict, live: dict):
    """Construct the multi-agent LangGraph StateGraph (round-robin / dyad / supervisor).

    State holds the running message list (reduced by add_messages) and a turn counter. Each
    agent is a node that prompts the chat model with its system brief + the transcript so far
    and appends its reply. A conditional edge advances to the next speaker until max_turns or a
    termination signal. NOT executed in this environment — written against the documented API.
    """
    from typing import Annotated, TypedDict              # local imports (only needed on the live path)
    StateGraph, START, END = live["StateGraph"], live["START"], live["END"]  # unpack graph pieces
    add_messages = live["add_messages"]                  # the message-appending reducer
    SystemMessage, HumanMessage, AIMessage = live["SystemMessage"], live["HumanMessage"], live["AIMessage"]
    agents = manifest.get("agents") or []                # conversational roles
    max_turns = int(manifest.get("max_turns", DEFAULT_MAX_TURNS))  # per-conversation turn ceiling
    scenario = manifest.get("scenario", "")              # optional shared framing prepended to each agent
    term = (manifest.get("termination") or {})           # termination config
    stop_signal = term.get("signal", "[[END]]")          # token an agent may emit to end early (agent_signal mode)
    chat = _make_chat_model(manifest)                     # one shared chat model (per-agent temperature is uniform here)

    class State(TypedDict):                              # the graph's shared state schema
        messages: Annotated[list, add_messages]          # the running transcript (append-reduced)
        turn: int                                        # how many turns have elapsed

    def agent_node(agent):                               # factory: build a node function bound to one agent
        def _node(state: State):                         # the node receives + returns a partial state update
            # Assemble this agent's input: its system brief + shared scenario, then the transcript so far
            # rendered so the agent's own prior turns are AIMessages and others are HumanMessages (labelled).
            sys_text = (scenario + "\n\n" + agent.get("system", "")).strip()  # role brief + framing
            convo = [SystemMessage(content=sys_text)]    # start from the system message
            for m in state["messages"]:                  # replay the transcript so far
                speaker = getattr(m, "name", None)       # who said it (we tag messages with the agent id)
                if speaker == agent["id"]:               # the agent's own prior turns
                    convo.append(AIMessage(content=m.content))  # presented as the assistant's own voice
                else:                                    # other agents' turns
                    convo.append(HumanMessage(content=f"[{speaker}] {m.content}"))  # labelled as input
            reply = chat.invoke(convo)                   # one model call -> this agent's next utterance
            tagged = AIMessage(content=reply.content, name=agent["id"])  # tag the reply with the speaker id
            return {"messages": [tagged], "turn": state["turn"] + 1}     # append + advance the turn counter
        return _node                                     # the bound node function

    g = StateGraph(State)                                # new graph over the State schema
    for a in agents:                                     # add one node per agent
        g.add_node(a["id"], agent_node(a))               # register the agent node
    g.add_edge(START, agents[0]["id"])                   # the first agent opens the conversation

    def router(state: State):                            # decide who speaks next (or stop)
        if state["turn"] >= max_turns:                   # hit the turn ceiling -> stop
            return END                                   # terminate the graph
        last = state["messages"][-1] if state["messages"] else None  # most recent utterance
        if last is not None and stop_signal in (last.content or ""):  # an agent emitted the stop token
            return END                                   # early termination (agent_signal mode)
        nxt = agents[state["turn"] % len(agents)]["id"]  # round-robin to the next speaker
        return nxt                                       # continue with that agent

    for a in agents:                                     # every agent routes through the same conditional edge
        g.add_conditional_edges(a["id"], router)         # after an agent speaks, the router picks the next node
    saver = live["SqliteSaver"]                          # DECISION B: native file-backed checkpointer
    return g, saver                                      # caller compiles with the saver + a per-conversation thread_id


def _run_conversations(manifest: dict, ckpt_dir: str) -> str:
    """Run all conversations live and export a flattened transcripts.jsonl (the uniform artifact).

    Provenance lives in the LangGraph SqliteSaver (DECISION B); we additionally write
    transcripts.jsonl keyed `conversation_id|t{turn}|{agent_id}` so MODE 9 reporting and the
    replication package consume the same shape as the bulk engine's responses.jsonl.
    """
    live = _import_live()                                # lazy-import the live stack (or exit with guidance)
    g, SqliteSaver = _build_graph(manifest, live)        # build the multi-agent graph + the checkpointer class
    db_path = os.path.join(ckpt_dir, "graph.sqlite")     # file-backed checkpoint store (inspectable, durable)
    transcripts_path = os.path.join(ckpt_dir, "transcripts.jsonl")  # the exported uniform artifact
    scenario = manifest.get("scenario", "")              # opening framing seeded into each conversation
    n_conv = int(manifest.get("n_conversations", 1))     # number of conversations to run

    # SqliteSaver is a context manager in current langgraph; open it once for all conversations.
    with SqliteSaver.from_conn_string(db_path) as saver:  # durable, resumable persistence
        app = g.compile(checkpointer=saver)              # compile the graph with native checkpointing
        with open(transcripts_path, "w") as out:         # (re)write the flattened export
            for c in range(n_conv):                      # one thread per conversation
                conv_id = f"conv{c:03d}"                 # stable conversation id == thread_id
                config = {"configurable": {"thread_id": conv_id}}  # bind this conversation's checkpoint thread
                seed = scenario or "Begin the conversation."  # opening prompt that kicks off turn 0
                final = app.invoke({"messages": [live["HumanMessage"](content=seed)], "turn": 0}, config)  # run it
                for t, m in enumerate(final["messages"]):  # flatten the final transcript
                    out.write(json.dumps({               # one line per utterance, engine-uniform custom_id
                        "custom_id": f"{conv_id}|t{t}|{getattr(m, 'name', 'seed')}",
                        "conversation_id": conv_id,
                        "turn": t,
                        "agent_id": getattr(m, "name", "seed"),  # speaker (or 'seed' for the opener)
                        "text": m.content,               # the utterance text
                    }) + "\n")
                print(f"  {conv_id}: {len(final['messages'])} utterances -> {transcripts_path}")
    return transcripts_path                              # path to the uniform export


# ---------------------------------------------------------------------------------------------
# Subcommands
# ---------------------------------------------------------------------------------------------
def cmd_run(args) -> int:
    """Dry-run (stdlib) or live-run (LangGraph) an interactive manifest."""
    manifest = _load_manifest(args.manifest)             # load the run manifest
    _validate_interactive_manifest(manifest)             # structural checks (fail loudly)
    plan = build_conversation_plan(manifest)             # expand to conversation specs (no calls)
    est = estimate_cost_interactive(manifest, plan)      # pre-flight cost estimate
    print(json.dumps(est, indent=2))                     # show the operator the call count + $ estimate

    ckpt = manifest.get("checkpoint_dir") or os.path.join(
        "output", "simulate", "runs", manifest.get("run_id", "interactive"))  # run directory
    os.makedirs(ckpt, exist_ok=True)                     # ensure it exists

    if args.dry_run:                                     # dry-run: write the plan + estimate, make NO calls
        plan_path = os.path.join(ckpt, "conversation-plan.jsonl")  # inspectable plan
        with open(plan_path, "w") as f:                  # one line per planned conversation
            for c in plan:                               # write each conversation spec
                f.write(json.dumps(c) + "\n")
        with open(os.path.join(ckpt, "cost-estimate.json"), "w") as f:  # persist the estimate
            json.dump(est, f, indent=2)
        vpath = _write_validation_record(manifest, plan, ckpt, live=False)  # honest UNVALIDATED-EXPLORATORY record
        print(f"DRY RUN — wrote {len(plan)} conversation plan(s) to {plan_path}; "
              f"validation record -> {vpath}; no API calls made.")
        return 0                                         # success without spending

    _enforce_local_mode(manifest)                        # HARD safety gate before any live call
    cap = manifest.get("cost_cap_usd")                   # optional hard ceiling
    if cap is not None and not est["is_local"] and est["est_cost_usd"] > float(cap):  # budget guard (local ~free)
        print(f"ERROR: estimated ${est['est_cost_usd']} exceeds cost_cap_usd ${cap}. No calls made.", file=sys.stderr)
        return 3                                         # refuse to exceed the budget
    transcripts = _run_conversations(manifest, ckpt)     # LIVE: run the graph + export transcripts.jsonl
    vpath = _write_validation_record(manifest, plan, ckpt, live=True)  # honest verdict alongside the transcripts
    print(f"Run complete. Transcripts: {transcripts}  Checkpoints: {os.path.join(ckpt, 'graph.sqlite')}  "
          f"Validation: {vpath}")
    return 0                                             # success


def cmd_export(args) -> int:
    """Re-derive transcripts.jsonl from an existing SqliteSaver checkpoint store.

    Convenience for when the live run wrote graph.sqlite but the flattened export is missing or
    stale. Reads each conversation thread's final state back out of the native checkpointer.
    """
    manifest = _load_manifest(args.manifest)             # load the manifest (for run_id + n_conversations)
    ckpt = manifest.get("checkpoint_dir") or os.path.join(
        "output", "simulate", "runs", manifest.get("run_id", "interactive"))  # run directory
    db_path = os.path.join(ckpt, "graph.sqlite")         # the native checkpoint store
    if not os.path.exists(db_path):                      # nothing to export from
        print(f"ERROR: no checkpoint store at {db_path}; run the simulation first.", file=sys.stderr)
        return 2                                         # cannot export
    live = _import_live()                                # need the SqliteSaver to read state back
    SqliteSaver = live["SqliteSaver"]                    # the checkpointer class
    out_path = args.out or os.path.join(ckpt, "transcripts.jsonl")  # export destination
    n_conv = int(manifest.get("n_conversations", 1))     # how many conversation threads to read
    with SqliteSaver.from_conn_string(db_path) as saver:  # open the store read-side
        with open(out_path, "w") as out:                 # (re)write the flattened export
            for c in range(n_conv):                      # one thread per conversation
                conv_id = f"conv{c:03d}"                 # the thread_id used at run time
                config = {"configurable": {"thread_id": conv_id}}  # bind the thread
                tup = saver.get_tuple(config)            # fetch the latest checkpoint for this thread
                if not tup:                              # thread never ran / no state
                    continue                             # skip silently (count mismatch is the operator's concern)
                msgs = tup.checkpoint.get("channel_values", {}).get("messages", [])  # the stored transcript
                for t, m in enumerate(msgs):             # flatten it
                    name = getattr(m, "name", "seed")    # speaker id
                    text = getattr(m, "content", "")     # utterance text
                    out.write(json.dumps({               # engine-uniform record
                        "custom_id": f"{conv_id}|t{t}|{name}", "conversation_id": conv_id,
                        "turn": t, "agent_id": name, "text": text}) + "\n")
    print(f"Exported transcripts -> {out_path}")         # report the export path
    return 0                                             # success


def main(argv: list) -> int:
    """Top-level argument parser for the interactive runner."""
    ap = argparse.ArgumentParser(prog="interactive_runner.py",
                                 description="LangGraph multi-agent interactive simulation (small-N)")
    sub = ap.add_subparsers(dest="cmd", required=True)   # require a subcommand

    p_run = sub.add_parser("run", help="dry-run or live-run an interactive manifest")
    p_run.add_argument("--manifest", required=True)      # the run manifest
    p_run.add_argument("--dry-run", action="store_true") # build plan + estimate, no API calls (stdlib only)
    p_run.add_argument("--resume", action="store_true")  # accepted for parity; SqliteSaver resumes by thread_id
    p_run.set_defaults(func=cmd_run)

    p_exp = sub.add_parser("export", help="re-derive transcripts.jsonl from the checkpoint store")
    p_exp.add_argument("--manifest", required=True)      # the manifest (for run_id + conversation count)
    p_exp.add_argument("--out", default=None)            # optional explicit export path
    p_exp.set_defaults(func=cmd_export)

    args = ap.parse_args(argv)                            # parse the command line
    return args.func(args)                               # dispatch to the chosen subcommand


if __name__ == "__main__":                               # script entrypoint
    raise SystemExit(main(sys.argv[1:]))                 # propagate the subcommand's exit code
