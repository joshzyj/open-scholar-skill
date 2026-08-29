# Agent RAO Trace Contract (BINDING)

Every evidence-required reviewer leaves a short Reasoning · Action ·
Observation (RAO) sidecar in the `trace_path` reserved by `review-begin`.
This is host-neutral: the worker may write the path directly, or the pipeline
driver may persist a structured trace returned by a host API. No Bash tool,
stdout sentinel, provider session variable, or provider-specific task-ID shape
is required from the worker.

`_AR_SKILL` means the absolute directory containing the loaded
`scholar-auto-research/SKILL.md`.

## Worker/adapter output

The launch envelope returned by `auto-research-state.sh review-begin` pins the
role, `dispatch_id`, `report_path`, and `trace_path`. These reservation paths
are authoritative. The report is Markdown; the trace is NDJSON with one JSON
object per line:

```json
{"step":"read-scripts","reasoning":"check clustering and fixed effects before judging uncertainty","action":"review the declared analysis scripts","observation":"three models use HC3 and omit state fixed effects","refs":["analysis/scripts/04-main-models.R"],"status":"ok"}
{"step":"verdict","reasoning":"uncertainty must match the nesting structure","action":"compare implementation with the design blueprint","observation":"one critical and two warning findings","status":"fail"}
```

Each line requires `step` and at least one nonempty value among `reasoning`,
`action`, and `observation`. `refs` is an optional path array. `status` is
`ok`, `fail`, or `skipped`. The worker does not invent sequence numbers,
run IDs, or provider identities.

After a host terminally succeeds, the driver verifies that both reserved files
are nonempty and calls `review-complete`. That command binds the report, trace,
and reviewed inputs into the project-state evidence history. A host failure,
cancellation, timeout, or unknown terminal state must not call
`review-complete`; the driver calls `review-abort` with the observed reason.

For the optional human-readable master trace, fold the sidecar with the
packaged helper. Use the reservation's opaque `dispatch_id` as `--agentId`:

```bash
bash "${_AR_SKILL}/scripts/gates/ingest-agent-trace.sh" \
  --sidecar "$PROJ/<reserved-trace-path>" --skill scholar-auto-research \
  --agent "<reserved-role>" --agentId "<dispatch-id>" \
  --phase "<phase>" --proj "$PROJ" --output-root "$PROJ"
```

When `--proj` is supplied, the ingester fails closed unless `--agentId`, role,
phase, reserved trace path, and trace digest resolve through one current,
successful completion in locked state. It verifies both the state-recorded
session digest and completion digest before appending anything to the master
trace. The evidence ledger is the authority; a legacy dispatch manifest is
neither required nor sufficient.

## Privacy

The sidecar is durable and shareable. Rationale and observations contain only
verdicts, counts, severities, aggregate descriptions, and file references—no
raw data rows, verbatim participant quotes, or PII. Under `LOCAL_MODE`, the
worker may reference a governed artifact path but never reproduce its row-level
content in the trace.
