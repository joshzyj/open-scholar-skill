#!/usr/bin/env bash
# emit-trace.sh — universal Reasoning-Action-Observation (RAO) trace writer.
#
# WHY THIS EXISTS
#   Every scholar skill and dispatched agent should leave a transparent,
#   auditable trace of what it reasoned, what it did, and what it observed —
#   a ReAct-style record. This helper is the ONE writer: skills call it once
#   per meaningful step; it appends a validated NDJSON record to the run's
#   append-only trace sink. render-trace.sh renders it to the human-readable
#   process-log-*.md; trace-coverage-check.sh enforces its presence.
#
# SINK
#   ${OUTPUT_ROOT}/logs/trace-<skill>-<date>.ndjson  (one JSON object per line)
#   The path is STABLE within a day+skill (no per-call counter) so it can be
#   re-derived in every stateless Bash block and appended to. `seq` is derived
#   from the current line count, so callers need not track state.
#
# RECORD SCHEMA
#   {"ts","seq","run_id","skill","phase","agent","agentId","session_id","step",
#    "reasoning","action","observation","refs":[...],"status","provenance"}
#   Required: skill, step, and >=1 non-empty of {reasoning, action, observation}.
#   provenance: "live" (default — emitted at the step it records) or
#   "reconstructed" (--reconstructed: written after the fact; P7-A correction
#   2026-08-25 — labelled reconstruction is auditable, silent reconstruction
#   is indistinguishable from fabrication).
#
#   `session_id` is the Claude Code session that produced the step. It is
#   auto-derived from $CLAUDE_CODE_SESSION_ID (fallback $CLAUDE_SESSION_ID) and
#   is what lets render-trace-html.sh deep-link a trace row into the rendered
#   raw-session transcript built by render-session-transcript.sh. It is NOT in
#   trace-coverage-check.sh's REQ set: that gate checks REQ is a SUBSET of the
#   record's keys, so adding a field is forward- and backward-compatible and
#   pre-existing traces do not retroactively RED. null when unavailable (e.g.
#   a Codex host, or a non-interactive runner).
#
# PRIVACY (C-01 / LOCAL_MODE)
#   `observation` MUST carry aggregate metrics, verdicts, counts, and file refs
#   ONLY — never raw data rows or PII. This helper emits a non-blocking WARN if
#   an obvious PII pattern (email / SSN-like) is detected; it never logs values
#   to a model-visible sink beyond what the caller passed.
#
# USAGE
#   bash scripts/gates/emit-trace.sh \
#     --skill scholar-analyze --phase 5B --agent self \
#     --step "M3-clustered-SE" \
#     --reasoning "units nested within states -> cluster SEs at state level" \
#     --action "feols(y ~ x | state, cluster=~state)" \
#     --observation "beta=0.42, p<0.01, N=1200" \
#     --refs "tables/results-registry.csv" --status ok
#
#   Optional: --agentId <id> (for ingested subagent steps; default null/self),
#             --session-id <id> (default $CLAUDE_CODE_SESSION_ID; null if unset),
#             --output-root <dir> (default $OUTPUT_ROOT or "output"),
#             --run-id <id> (default "<skill>-<date>").
#
# EXIT CODES
#   0  record appended
#   1  required arg missing / all-empty RAO triad / bad --status
#   2  cannot create the log directory

set -uo pipefail

SKILL=""
PHASE=""
AGENT="self"
AGENT_ID=""
SESSION_ID=""
STEP=""
REASONING=""
ACTION=""
OBSERVATION=""
REFS=""
STATUS="ok"
OUTPUT_ROOT_ARG=""
RUN_ID=""

while [ $# -gt 0 ]; do
  case "$1" in
    --skill)        SKILL="${2:-}"; shift 2 ;;
    --phase)        PHASE="${2:-}"; shift 2 ;;
    --agent)        AGENT="${2:-}"; shift 2 ;;
    --agentId)      AGENT_ID="${2:-}"; shift 2 ;;
    --session-id)   SESSION_ID="${2:-}"; shift 2 ;;
    --step)         STEP="${2:-}"; shift 2 ;;
    --reasoning)    REASONING="${2:-}"; shift 2 ;;
    --action)       ACTION="${2:-}"; shift 2 ;;
    --observation)  OBSERVATION="${2:-}"; shift 2 ;;
    --refs)         REFS="${2:-}"; shift 2 ;;
    --status)       STATUS="${2:-}"; shift 2 ;;
    --output-root)  OUTPUT_ROOT_ARG="${2:-}"; shift 2 ;;
    --run-id)       RUN_ID="${2:-}"; shift 2 ;;
    --reconstructed) PROVENANCE="reconstructed"; shift ;;
    -h|--help)      grep -E '^#' "$0" | sed 's/^# *//'; exit 0 ;;
    *)              echo "ERROR: unknown flag $1" >&2; exit 1 ;;
  esac
done

# ── Required-arg validation ─────────────────────────────────────────────────
if [ -z "$SKILL" ] || [ -z "$STEP" ]; then
  echo "ERROR: --skill and --step are required" >&2
  exit 1
fi
if [ -z "$REASONING" ] && [ -z "$ACTION" ] && [ -z "$OBSERVATION" ]; then
  echo "ERROR: at least one of --reasoning / --action / --observation must be non-empty (RAO triad)" >&2
  exit 1
fi
case "$STATUS" in
  ok|fail|skipped) : ;;
  *) echo "ERROR: --status must be one of ok|fail|skipped (got '$STATUS')" >&2; exit 1 ;;
esac
[ -n "$AGENT" ] || AGENT="self"

OUTPUT_ROOT="${OUTPUT_ROOT_ARG:-${OUTPUT_ROOT:-output}}"
LOG_DATE=$(date +%Y-%m-%d 2>/dev/null || echo "0000-00-00")
[ -n "$RUN_ID" ] || RUN_ID="${SKILL}-${LOG_DATE}"

LOG_DIR="${OUTPUT_ROOT}/logs"
mkdir -p "$LOG_DIR" 2>/dev/null || { echo "ERROR: cannot mkdir $LOG_DIR" >&2; exit 2; }
TRACE_FILE="${LOG_DIR}/trace-${SKILL}-${LOG_DATE}.ndjson"

# ── seq: derive from current line count (stateless across Bash blocks) ───────
if [ -f "$TRACE_FILE" ]; then
  SEQ=$(wc -l < "$TRACE_FILE" 2>/dev/null | tr -d ' ')
  SEQ=${SEQ:-0}
else
  SEQ=0
fi
SEQ=$((SEQ + 1))

# ── JSON-escape: backslash + doublequote; collapse newlines/tabs to spaces;
#    strip remaining control chars (NDJSON = one line per record). ───────────
esc() {
  printf '%s' "${1:-}" \
    | LC_ALL=C tr '\n\r\t' '   ' \
    | LC_ALL=C tr -d '[:cntrl:]' \
    | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

# ── refs -> JSON array (comma- or whitespace-separated) ─────────────────────
refs_json() {
  local raw="$1" out="" tok first=1
  # Split on commas and whitespace; keep it Bash-3.2-safe (no mapfile).
  raw=$(printf '%s' "$raw" | tr ',' ' ')
  for tok in $raw; do
    [ -n "$tok" ] || continue
    tok=$(esc "$tok")
    if [ "$first" -eq 1 ]; then out="\"$tok\""; first=0; else out="$out,\"$tok\""; fi
  done
  printf '[%s]' "$out"
}

# ── Non-blocking PII warn on the observation field ──────────────────────────
if printf '%s' "$OBSERVATION" | LC_ALL=C grep -qE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}|[0-9]{3}-[0-9]{2}-[0-9]{4}'; then
  echo "WARN: observation looks like it contains an email/SSN-like value — traces must carry aggregate metrics/verdicts/refs only, never raw data or PII (C-01)." >&2
fi

TS=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date)
AGENT_ID_JSON="null"
[ -n "$AGENT_ID" ] && AGENT_ID_JSON="\"$(esc "$AGENT_ID")\""
# Session id: explicit flag wins; else the host's env var; else null. Never fail
# on absence — a Codex host and a bare CI runner both legitimately lack one.
[ -n "$SESSION_ID" ] || SESSION_ID="${CLAUDE_CODE_SESSION_ID:-${CLAUDE_SESSION_ID:-}}"
SESSION_ID_JSON="null"
[ -n "$SESSION_ID" ] && SESSION_ID_JSON="\"$(esc "$SESSION_ID")\""
PHASE_JSON="null"
[ -n "$PHASE" ] && PHASE_JSON="\"$(esc "$PHASE")\""

# Provenance (handoff 2026-08-25, P7-A correction): "live" = emitted at the
# step it records; "reconstructed" = written after the fact from memory or
# notes (--reconstructed). The distinction is load-bearing for auditors:
# three real records carrying one identical timestamp across three separate
# script executions was DIRECT evidence of post-hoc reconstruction, but the
# schema had no honest way to say so — an emitter that reconstructs and
# labels it is auditable; one that reconstructs silently is indistinguishable
# from fabrication.
PROVENANCE="${PROVENANCE:-live}"
printf '{"ts":"%s","seq":%s,"run_id":"%s","skill":"%s","phase":%s,"agent":"%s","agentId":%s,"session_id":%s,"step":"%s","reasoning":"%s","action":"%s","observation":"%s","refs":%s,"status":"%s","provenance":"%s"}\n' \
  "$TS" "$SEQ" "$(esc "$RUN_ID")" "$(esc "$SKILL")" "$PHASE_JSON" "$(esc "$AGENT")" "$AGENT_ID_JSON" "$SESSION_ID_JSON" \
  "$(esc "$STEP")" "$(esc "$REASONING")" "$(esc "$ACTION")" "$(esc "$OBSERVATION")" "$(refs_json "$REFS")" "$(esc "$STATUS")" "$PROVENANCE" \
  >> "$TRACE_FILE"

echo "TRACE_APPENDED=$TRACE_FILE"
echo "SEQ=$SEQ"
exit 0
