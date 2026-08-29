# Agent RAO Trace Contract (BINDING)

Every dispatched agent (peer-reviewer-*, review-code-*, verify-*, extract-section-exemplar, …) must leave a **Reasoning · Action · Observation** trace of how it reached its verdict — not just the final report. This composes with the existing "Output persistence override" (`--write-to` / `WROTE:`).

**Why a sidecar, not an append:** agents have `Write` but usually **no Bash tool**, so they cannot `>>`-append to the run's shared NDJSON. Instead, accumulate your steps and, in one `Write`, emit a **sidecar file next to your report**. The orchestrator folds it into the master trace with `ingest-agent-trace.sh`.

---

## What you MUST do

Your report and sidecar paths come from your dispatch: a briefed dispatch
(agent-brief/v2, 2026-08-23) pins them in the brief's `output_contract`
(`report_path` / `trace_path`) — those are authoritative; a `--write-to` /
`--trace-to` line in your prompt is the same value in transport form. A gated
dispatch always carries them: `emit-agent-brief.sh` refuses to emit a brief
without a report path, because a stdout-only report leaves no trace event and
`trace-coverage-check.sh` RED-fails the phase (handoff P3-3).

When dispatched with `--write-to <report-path>` (and, when provided, `--trace-to <sidecar-path>`; otherwise default the sidecar to `<report-path>.trace.ndjson`):

1. As you work, keep a short list of RAO steps — each is one decision / check / observation you made (e.g. "read scripts", "checked clustering", "assessed identification", "final verdict").
2. Persist your report via `Write` as before.
3. **Also `Write` the sidecar** `<report-path>.trace.ndjson` — **one JSON object per line**, using this schema (you do NOT set `seq`/`run_id`/`agentId`; the orchestrator stamps those on ingest):

   ```json
   {"step":"read-scripts","reasoning":"scan for clustering/FE before judging SEs","action":"read 04-main-models.R, 05-marginal-effects.R","observation":"3 models; HC3 SEs; no state FE","refs":["scripts/04-main-models.R"],"status":"ok"}
   {"step":"verdict","reasoning":"SEs not clustered on the nesting unit","action":"assess identification vs design blueprint","observation":"1 CRITICAL, 2 WARN","status":"fail"}
   ```

   Required per line: `step`, and **≥1 non-empty of** `{reasoning, action, observation}`. `refs` is an optional array of file paths; `status` ∈ `ok|fail|skipped` (default `ok`).
4. **Final stdout MUST end with two literal lines:**
   ```
   WROTE: <report-path>
   TRACE: <sidecar-path>
   ```
   so the dispatcher can confirm both artifacts by grepping your last lines.
5. If a `Write` fails, report it in stdout and **exit non-zero** — do not silently degrade.

If `--write-to` is absent AND your brief carries no `output_contract` (standalone debugging only — a gated dispatch always has one), emit the report to stdout and you may skip the sidecar.

---

## Privacy (C-01 / LOCAL_MODE) — MANDATORY

The sidecar is durable and shareable. `reasoning` and `observation` carry **verdicts, counts, severities, and file references ONLY — never raw data rows, verbatim participant quotes, or PII** (names, emails, IDs, DOBs). Describe *that* you observed something and its shape/severity, not the sensitive value. This holds even for files marked `CLEARED`.

---

## Orchestrator side (for reference)

After the agent returns, the dispatching skill records the dispatch (`emit-task-dispatch.sh`, unchanged) and folds the sidecar into the master trace:

```bash
bash "${SCHOLAR_SKILL_DIR:-.}/scripts/gates/ingest-agent-trace.sh" \
  --sidecar "<report-path>.trace.ndjson" --skill <dispatching-skill> \
  --agent <subagent_type> --agentId <id-from-Task> --phase <phase> --proj "$PROJ"
```

`ingest-agent-trace.sh` stamps `seq`/`run_id`/`agentId`, appends via `emit-trace.sh`, and cross-checks the `agentId` against `logs/dispatch-manifest.jsonl`. `trace-coverage-check.sh` then RED-fails the phase if any dispatched `agentId` has no trace event.
