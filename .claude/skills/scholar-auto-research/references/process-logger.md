# Process Logging Protocol — Reasoning · Action · Observation (RAO) Trace

Every `/scholar-*` skill run MUST leave a transparent, auditable trace of **what it reasoned, what it did, and what it observed** — a ReAct-style record. This is enforced: `trace-coverage-check.sh` RED-fails a phase/skill that produced no valid trace.

For these snippets, `_AR_SKILL` is the absolute directory containing the loaded `scholar-auto-research/SKILL.md`, re-established in the same Bash tool call. It is never derived from cwd or a parent plugin.

**Source of truth = an append-only NDJSON trace.** The human-readable `process-log-*.md` is now a *rendered view* of it — do not hand-write table rows. One writer helper (`emit-trace.sh`) and one renderer (`render-trace.sh`) do the work; skills just call them.

> What "reasoning" means: the harness cannot log a model's hidden chain-of-thought. Log the **stated rationale** — a short "why" you can articulate — alongside the action and the observation.

---

## The sink

```
${OUTPUT_ROOT}/logs/trace-<skill>-<YYYY-MM-DD>.ndjson     # append-only, one record per step
${OUTPUT_ROOT}/logs/process-log-<skill>-<YYYY-MM-DD>.md   # rendered markdown view (generated)
${OUTPUT_ROOT}/logs/run-html/index.html                   # whole-run HTML view (generated, optional)
```

Record schema (written by `emit-trace.sh`; you never hand-author these):

```json
{"ts","seq","run_id","skill","phase","agent","agentId","session_id","step",
 "reasoning","action","observation","refs":[...],"status"}
```

Required per record: `skill`, `step`, and **≥1 non-empty of** `{reasoning, action, observation}`. A well-formed step carries all three.

`session_id` is optional observability metadata. The emitter may record a
host-provided session environment variable when available, but it is null under
generic runners and is never review-evidence authority. It is deliberately not
required by `trace-coverage-check.sh`.

---

## STEP — emit one record per meaningful step

After each meaningful step (a decision, a tool/script run, a subagent dispatch, a gate call), append a record. **Shell variables do NOT persist across Bash tool calls** — but you do not need to track any state: `emit-trace.sh` re-derives the path and the monotonic `seq` from the file itself. Just call it:

```bash
_AR_GATES="${_AR_SKILL}/scripts/gates"
bash "$_AR_GATES/emit-trace.sh" \
  --skill scholar-XXXX --phase "<phase-or-omit>" --step "<label>" \
  --reasoning "<why — the stated rationale, 1–2 lines>" \
  --action    "<what you did — tool/script/gate/subagent call + key args>" \
  --observation "<what came back — verdict/metric/count/error/file>" \
  --refs "<comma-separated artifact paths, or omit>" \
  --status ok            # ok | fail | skipped
```

- **step**: the skill's own step id (e.g. `A0-parse-args`, `5B-main-models`).
- **reasoning**: the *why* (`"units nested within states → cluster SEs at state level"`). Do not restate the action.
- **action**: the *what* (`"feols(y ~ x | state, cluster=~state)"`).
- **observation**: the *result* — aggregate metrics, verdicts, counts, or file refs.
- On failure/skip, still emit the record with `--status fail|skipped` and put the reason in `--observation`.

`--phase` is for orchestrated runs (scholar-full-paper phases); standalone skills may omit it.

---

## END — render the human-readable log

At the end of the run (Save Output section), render the markdown view from the trace:

```bash
_AR_GATES="${_AR_SKILL}/scripts/gates"
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"; TRACE="${OUTPUT_ROOT}/logs/trace-scholar-XXXX-$(date +%Y-%m-%d).ndjson"
bash "$_AR_GATES/render-trace.sh" "$TRACE"
# Optional self-check (the phase gate runs this too):
bash "$_AR_GATES/trace-coverage-check.sh" "$OUTPUT_ROOT" --skill scholar-XXXX
```

`init-log.sh` remains available to pre-create a markdown header, but with `render-trace.sh` generating the full file it is optional.

---

## Visual inspection — local whole-run view

The markdown log is the portable, greppable view. The bundled run-view helpers
can also render the whole pipeline—every phase, gate, registered review
session, excuse, lock generation, and artifact—without a parent plugin tree or
network access:

```bash
_AR_GATES="${_AR_SKILL}/scripts/gates"
bash "$_AR_GATES/refresh-run-html.sh" "$PROJ" --force
# -> PROJ/logs/run-model.json   (normalized, versioned; the contract)
# -> PROJ/logs/run-html/index.html
```

It reads the bundled `phase-contract.json`, draws route-back arcs where the run looped, collects every excuse/force-complete/halt/bypass into one Anomalies panel, and opens with a banner naming whatever it could not show.

**Live monitoring.** You do not have to run this by hand: `refresh-run-html.sh` is wired into both state machines' phase-boundary commands, so `logs/run-html/index.html` refreshes itself as a run advances. To watch it in a browser tab, export `SCHOLAR_RUN_HTML_REFRESH=20` before starting the run and the page will reload itself every 20 seconds. `SCHOLAR_RUN_HTML_AUTO=0` turns the whole thing off. The hooks always exit 0 and print nothing, so they cannot affect a gate.

## Subagents (Task/Agent dispatches)

Workers may have a shell, a file-writing API, or only a structured return
channel. In every case, the driver persists the RAO sidecar at the path reserved
by `review-begin`, then may fold it into the master trace. See
`agent-trace-contract.md` and use `ingest-agent-trace.sh`:

```bash
_AR_GATES="${_AR_SKILL}/scripts/gates"
bash "$_AR_GATES/ingest-agent-trace.sh" \
  --sidecar "<report>.trace.ndjson" --skill scholar-XXXX \
  --agent "<reserved-role>" --agentId "<reserved-dispatch-id>" --phase "<phase>" --proj "$PROJ"
```

With `--proj`, ingestion fails unless locked state contains one current,
successful role completion for that opaque dispatch ID and the state-recorded
session, completion, and trace digests still match. The check happens before
the master trace is appended, so orphaned or tampered sidecars cannot pollute
the run log. The review-evidence ledger remains the only reviewer-execution
gate authority; RAO is observability. `logs/dispatch-manifest.jsonl`, when
present, is legacy display metadata and is never consulted by this check.

---

## Privacy (C-01 / LOCAL_MODE) — MANDATORY

The trace is a durable, shareable artifact. `observation` and `reasoning` carry **aggregate metrics, verdicts, counts, and file references ONLY — never raw data rows, quotes, or PII** (names, emails, IDs, DOBs, addresses). Under `LOCAL_MODE`, log derived aggregates, never row-level values. `emit-trace.sh` warns on obvious email/SSN-like values, but the discipline is yours: describe *that* you observed something and its shape, not the sensitive value itself.

**Scope clarification (Evidence Ledger):** this no-verbatim-quotes rule applies to *traces* (`logs/trace-*.ndjson`). Evidence artifacts under `${PROJ}/evidence/` may hold separately governed, quote-capped source anchors and remain excluded from replication packages. A trace step that captures an anchor references it by `anchor_id` in `refs[]`; it never inlines the quote. Do not flag `evidence/*.ndjson` as a trace-privacy violation.

---

## Notes

- One trace file per skill per day (records accumulate; `seq` stays monotonic; `render-trace.sh` orders by `seq`). Distinguish same-day reruns with `--run-id` if needed.
- Orchestrators (`scholar-full-paper`, `scholar-book`, `scholar-grant`, `scholar-auto-research`): emit a trace record at each phase boundary (`--phase`), and `ingest-agent-trace.sh` every dispatched agent's sidecar so the phase's subagent reasoning lands in the master trace.
- The trace/log file itself is not listed among a run's "Output Files".
