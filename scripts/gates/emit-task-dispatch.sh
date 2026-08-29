#!/usr/bin/env bash
# emit-task-dispatch.sh — P3 dispatch-manifest helper (audit 2026-05-19,
# V4-SD-V4-1 follow-up).
#
# Why this exists:
#   The orchestrator's Phase 11.5 Stage B (and other gated-Task) flows
#   need to bind the artifact a subagent produces to a real Task
#   dispatch. F6/V4-SD-V4-1 added artifact↔log binding; this helper
#   adds a third binding point: a per-project dispatch manifest at
#   ${PROJ}/logs/dispatch-manifest.jsonl. Each Task dispatch the
#   orchestrator runs at a gated site SHOULD append one line here.
#
# Honest framing (per V-6 adversarial audit):
#   This is a SPEED-BUMP, not a structural barrier. A determined forger
#   can write artifact + log + manifest all consistently. The manifest
#   adds:
#     - 3-way binding (artifact + log + manifest agentId all match)
#     - manuscript-SHA cross-binding (manifest entry records the SHA
#       that was current at dispatch time; the gate verifies it matches
#       artifact + current manuscript)
#     - first-seen-wins for duplicate agentId entries (raises cost of
#       id-recycling bypass per V-6 bypass #2)
#     - purpose-binding (an agentId's first-recorded purpose is canonical;
#       later entries claiming the same id for a different purpose are
#       evidence of tampering)
#
#   True structural resistance requires runtime-level support (sidecar
#   non-writable sink, harness-signed entries) — see
#   scholar-full-paper/references/structural-bypass-limits.md for the
#   threat-model writeup. (Corrected 2026-08-24: this pointed at
#   references/dispatch-manifest-limits.md, which the plugin has never
#   shipped — the concept-gap class CLAUDE.md warns about, found by an
#   independent adjudication rather than by any gate.)
#
# Usage:
#   emit-task-dispatch.sh \
#     --proj PROJ \
#     --subagent <type> \
#     --purpose "<one-line description>" \
#     --phase <X.X> \
#     --agentId <id-from-Task-tool-result> \
#     [--manuscript PATH]    # optional; auto-discovers newest manuscript
#     [--brief PATH]         # optional; binds the dispatch to its on-disk
#                            # briefing packet (path + sha256 recorded —
#                            # input-side provenance, RCA Round 2 #10)
#
# Example (Phase 11.5 Stage B after a real Task dispatch):
#   emit-task-dispatch.sh --proj $PROJ \
#     --subagent general-purpose \
#     --purpose "Phase 11.5 semantic body-prose read" \
#     --phase 11.5 \
#     --agentId a95ed96414f4a35dd
#
# Exit codes:
#   0  manifest line appended
#   1  required arg missing / invalid agentId format
#   2  manuscript not found AT A MANUSCRIPT PHASE (numeric --phase >= 7);
#      the line is still appended with manuscript_sha256=null and a warning.
#      At pre-manuscript phases (numeric < 7, or non-numeric tags like
#      pre-exec-simulate / R1) a missing manuscript is the DESIGNED state:
#      the same null-SHA line is appended, the warning still prints, and the
#      exit is 0 so set -e orchestrator blocks recording mandated dispatches
#      do not die (real-project eval, ses 2026-08-22).

set -uo pipefail

PROJ=""
SKILL=""
RUN_ID=""
SUBAGENT=""
PURPOSE=""
PHASE=""
AGENT_ID=""
MANUSCRIPT=""
BRIEF=""
RECEIPT=""

while [ $# -gt 0 ]; do
  case "$1" in
    --skill)       SKILL="${2:-}"; shift 2 ;;
    --run-id)      RUN_ID="${2:-}"; shift 2 ;;
    --proj)        PROJ="${2:-}"; shift 2 ;;
    --subagent)    SUBAGENT="${2:-}"; shift 2 ;;
    --purpose)     PURPOSE="${2:-}"; shift 2 ;;
    --phase)       PHASE="${2:-}"; shift 2 ;;
    --agentId)     AGENT_ID="${2:-}"; shift 2 ;;
    --manuscript)  MANUSCRIPT="${2:-}"; shift 2 ;;
    --brief)       BRIEF="${2:-}"; shift 2 ;;
    --receipt)     RECEIPT="${2:-}"; shift 2 ;;
    -h|--help)     grep -E '^#' "$0" | sed 's/^# *//'; exit 0 ;;
    *)             echo "ERROR: unknown flag $1" >&2; exit 1 ;;
  esac
done

# Required-arg validation
if [ -z "$PROJ" ] || [ -z "$SUBAGENT" ] || [ -z "$PURPOSE" ] || [ -z "$PHASE" ] || [ -z "$AGENT_ID" ]; then
  echo "ERROR: --proj, --subagent, --purpose, --phase, --agentId all required" >&2
  exit 1
fi

if [ ! -d "$PROJ" ]; then
  echo "ERROR: --proj path is not a directory: $PROJ" >&2
  exit 1
fi

# agentId format check — real Task tool ids are `^[a-z][a-z0-9_-]{12,}$`
# (matches the regex tighten from V1 round). Reject placeholders.
if ! echo "$AGENT_ID" | grep -qE '^[a-z][a-z0-9_-]{12,}$'; then
  echo "ERROR: --agentId '$AGENT_ID' does not match Task tool id format (^[a-z][a-z0-9_-]{12,}\$)" >&2
  echo "       Pass the actual agentId returned by the Task tool, not a placeholder." >&2
  exit 1
fi

# Manuscript SHA — used for cross-binding to the artifact.
if [ -z "$MANUSCRIPT" ]; then
  # Auto-discover: newest reader-facing manuscript.
  for pat in manuscript-submission manuscript-final draft-manuscript manuscript; do
    cand=$(ls -t "$PROJ/drafts/${pat}"-*.md 2>/dev/null | head -1 || true)
    if [ -n "$cand" ] && [ -f "$cand" ]; then
      MANUSCRIPT="$cand"; break
    fi
  done
fi

MS_SHA="null"
if [ -n "$MANUSCRIPT" ] && [ -f "$MANUSCRIPT" ]; then
  if command -v shasum >/dev/null 2>&1; then
    MS_SHA=$(shasum -a 256 "$MANUSCRIPT" 2>/dev/null | awk '{print $1}')
  elif command -v sha256sum >/dev/null 2>&1; then
    MS_SHA=$(sha256sum "$MANUSCRIPT" 2>/dev/null | awk '{print $1}')
  fi
  MS_SHA=${MS_SHA:-null}
fi

# Append the manifest line. JSON values are escaped via simple bash
# (no special chars expected in agent-issued ids; purpose is one-line).
LOG_DIR="$PROJ/logs"
mkdir -p "$LOG_DIR" 2>/dev/null || {
  echo "ERROR: cannot mkdir $LOG_DIR" >&2; exit 1
}
MANIFEST="$LOG_DIR/dispatch-manifest.jsonl"

# Input-side provenance (RCA Round 2 #10, 2026-08-22): the pipeline verified
# an agent RAN but never what it was TOLD. --brief binds the dispatch row to
# the on-disk briefing packet (emit-agent-brief.sh / emit-fix-brief.sh) by
# path + sha256. A named-but-missing brief FAILS (exit 1) — recording a
# dispatch against a brief that is not there is the recollection-brief hole.
BRIEF_REL="null"; BRIEF_SHA="null"
if [ -n "$BRIEF" ]; then
  # $PROJ-first for relative paths (2026-08-22 verification round: cwd-first
  # bound another project's identically-templated brief while the row LOOKED
  # proj-relative — a sha mismatch indistinguishable from tampering).
  # $PROJ-ONLY resolution for relative paths (independent review 2026-08-23,
  # M1): the old fallback `[ -f "$BRIEF_ABS" ] || BRIEF_ABS="$BRIEF"` silently
  # re-resolved against the CWD, which is the cross-project mis-binding shape
  # the 2026-08-22 fix reordered but did not eliminate.
  case "$BRIEF" in
    /*) BRIEF_ABS="$BRIEF" ;;
    *)  BRIEF_ABS="$PROJ/$BRIEF" ;;
  esac
  if [ ! -f "$BRIEF_ABS" ]; then
    echo "ERROR: --brief '$BRIEF' not found (neither absolute nor under --proj)" >&2
    exit 1
  fi
  if command -v shasum >/dev/null 2>&1; then
    BRIEF_SHA=$(shasum -a 256 "$BRIEF_ABS" 2>/dev/null | awk '{print $1}')
  else
    BRIEF_SHA=$(sha256sum "$BRIEF_ABS" 2>/dev/null | awk '{print $1}')
  fi
  BRIEF_SHA=${BRIEF_SHA:-null}
  case "$BRIEF_ABS" in
    "$PROJ"/*) BRIEF_REL="${BRIEF_ABS#"$PROJ"/}" ;;
    *)         BRIEF_REL="$BRIEF_ABS" ;;
  esac
fi

# Pre-dispatch verification receipt (system-fix P0.3/S1.1, 2026-08-23):
# --receipt binds the row to the orchestrator-side verification that ran
# BEFORE the Task was dispatched (emit-verification-receipt.sh). Recorded
# checks fail LOUDLY at record time — a row bound to a RED, stale, or
# renamed receipt is worse than an unbound row, because it reads as
# verified provenance.
RECEIPT_REL="null"; DISPATCH_NONCE="null"; RECEIPT_SHA="null"
if [ -n "$RECEIPT" ]; then
  if [ -z "$BRIEF" ]; then
    echo "ERROR: --receipt requires --brief (a receipt attests a brief)" >&2
    exit 1
  fi
  # $PROJ-only relative resolution (no CWD fallback — see --brief above), and
  # CONTAINMENT: a receipt must live in THIS project's briefs/receipts/ (C3,
  # independent review 2026-08-23) — a row naming an out-of-project receipt
  # is provenance theater.
  case "$RECEIPT" in
    /*) RECEIPT_ABS="$RECEIPT" ;;
    *)  RECEIPT_ABS="$PROJ/$RECEIPT" ;;
  esac
  if [ ! -f "$RECEIPT_ABS" ]; then
    echo "ERROR: --receipt '$RECEIPT' not found (relative paths resolve under --proj ONLY)" >&2
    exit 1
  fi
  _PROJ_CANON=$(cd "$PROJ" 2>/dev/null && pwd -P) || _PROJ_CANON="$PROJ"
  _RCPT_DIR_CANON=$(cd "$(dirname "$RECEIPT_ABS")" 2>/dev/null && pwd -P) || _RCPT_DIR_CANON=""
  case "$_RCPT_DIR_CANON" in
    "$_PROJ_CANON"/briefs/receipts) : ;;
    *) echo "ERROR: --receipt must live under <proj>/briefs/receipts/ (got: ${_RCPT_DIR_CANON:-unresolvable})" >&2
       exit 1 ;;
  esac
  if command -v shasum >/dev/null 2>&1; then
    RECEIPT_SHA=$(shasum -a 256 "$RECEIPT_ABS" 2>/dev/null | awk '{print $1}')
  else
    RECEIPT_SHA=$(sha256sum "$RECEIPT_ABS" 2>/dev/null | awk '{print $1}')
  fi
  RECEIPT_SHA=${RECEIPT_SHA:-null}
  RCPT_CHECK=$(RECEIPT_ABS="$RECEIPT_ABS" BRIEF_SHA="$BRIEF_SHA" python3 - <<'PY'
import json, os, sys
p = os.environ["RECEIPT_ABS"]
try:
    r = json.load(open(p, encoding="utf-8"))
except (OSError, ValueError):
    print("ERR|receipt unreadable as JSON"); sys.exit(0)
nonce = r.get("nonce") or ""
stem = os.path.basename(p)[:-len(".json")] if p.endswith(".json") else os.path.basename(p)
if not nonce:
    print("ERR|receipt carries no nonce"); sys.exit(0)
if stem != nonce:
    print("ERR|receipt filename %r does not match its nonce %r (renamed receipt)" % (stem, nonce)); sys.exit(0)
if r.get("status") != "GREEN":
    print("ERR|receipt status is %r — a dispatch must not be recorded against a non-GREEN verification" % r.get("status")); sys.exit(0)
if r.get("brief_sha256") != os.environ["BRIEF_SHA"]:
    print("ERR|receipt attests brief sha %s… but the brief on disk hashes %s… — the brief changed AFTER verification (stale receipt); re-verify before recording" % ((r.get("brief_sha256") or "")[:12], os.environ["BRIEF_SHA"][:12])); sys.exit(0)
print("OK|%s" % nonce)
PY
)
  case "$RCPT_CHECK" in
    OK\|*) DISPATCH_NONCE="${RCPT_CHECK#OK|}" ;;
    *)     echo "ERROR: --receipt rejected: ${RCPT_CHECK#ERR|}" >&2; exit 1 ;;
  esac
  case "$RECEIPT_ABS" in
    "$PROJ"/*) RECEIPT_REL="${RECEIPT_ABS#"$PROJ"/}" ;;
    *)         RECEIPT_REL="$RECEIPT_ABS" ;;
  esac
fi

TS=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date)
# Escape backslashes and double-quotes in user-supplied fields.
esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
PURPOSE_E=$(esc "$PURPOSE")
SUBAGENT_E=$(esc "$SUBAGENT")
PHASE_E=$(esc "$PHASE")

# ── Trace mirror (trace plan D0/D1, 2026-08-26) ──────────────────────────────
# The manifest and the trace are separate sinks, and NOTHING used to bridge
# them: a run whose central step was five real dispatched agents produced a
# trace reporting "0 agent event(s)", so an auditor reading the trace could
# not tell a real panel from five inline personas — the very thing this
# script exists to prevent. A skill-text reminder cannot fix that (a skill
# can forget); the bridge belongs in the emitter.
#
# ORDER: the trace row is emitted BEFORE the manifest row, deliberately.
# The alternative (manifest first, then mirror) needs a `pending` state and a
# row rewrite on an append-only file, and leaves a window where a gate sees a
# dispatch with no trace event. Emitting trace-first inverts the window into
# the harmless direction — a trace event with no manifest row yet is an extra
# record, never a missing dispatch — and lets the row carry the mirror's REAL
# outcome, durably, instead of a stderr warning nobody can audit later.
#
# Identity: (skill, run_id, agentId) is the cross-link key. skill+date is not
# enough — traces are one file per skill per DAY, so two same-day runs would
# collapse into one identity.
TRACE_MIRROR_STATUS="skipped-unscoped"
if [ "${SCHOLAR_DISPATCH_TRACE_MIRROR:-1}" = "0" ]; then
  TRACE_MIRROR_STATUS="disabled-by-env"
elif [ -z "$SKILL" ]; then
  # No skill identity: the mirror cannot know which trace file this dispatch
  # belongs to, and INFERRING it (newest trace-*.ndjson) would be a guess in a
  # provenance path — refused. Loud, and recorded on the row so the gate can
  # treat the dispatch as legacy-unscoped rather than silently green.
  echo "emit-task-dispatch: WARN --skill not given; dispatch NOT mirrored into the trace." >&2
  echo "emit-task-dispatch:   The trace will show no agent event for ${AGENT_ID}. Pass --skill <name>" >&2
  echo "emit-task-dispatch:   (and --run-id when the skill uses one) to bind this dispatch to its run." >&2
  if [ "${SCHOLAR_DISPATCH_SKILL_REQUIRED:-0}" = "1" ]; then
    echo "emit-task-dispatch: REFUSED — SCHOLAR_DISPATCH_SKILL_REQUIRED=1 and no --skill given." >&2
    exit 2
  fi
else
  _ET="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/emit-trace.sh"
  if [ ! -f "$_ET" ]; then
    TRACE_MIRROR_STATUS="failed:emitter-missing"
    echo "emit-task-dispatch: WARN emit-trace.sh not found beside this script — dispatch not mirrored" >&2
  else
    _mirror_args=(--skill "$SKILL" --step "dispatch:${SUBAGENT}" --agentId "$AGENT_ID"
                  --action "Task dispatch: ${SUBAGENT}"
                  --observation "dispatched agentId=${AGENT_ID}; purpose=${PURPOSE}"
                  --refs "$MANIFEST" --status ok)
    [ -n "$PHASE" ]  && _mirror_args+=(--phase "$PHASE")
    [ -n "$RUN_ID" ] && _mirror_args+=(--run-id "$RUN_ID")
    if OUTPUT_ROOT="$(dirname "$MANIFEST")/.." bash "$_ET" "${_mirror_args[@]}" >/dev/null 2>&1; then
      TRACE_MIRROR_STATUS="ok"
    else
      TRACE_MIRROR_STATUS="failed:emit-error"
      echo "emit-task-dispatch: WARN trace mirror FAILED for ${AGENT_ID} — recorded on the manifest row as trace_mirror_status=failed:emit-error; the coverage gate will flag it" >&2
    fi
  fi
fi
SKILL_E=$(esc "$SKILL")
RUN_ID_E=$(esc "$RUN_ID")
# Appended verbatim to every row shape below (three branches, one fragment —
# so a new field cannot land in two of three and silently differ).
XFIELDS=$(printf ',"skill":"%s","run_id":"%s","trace_mirror_status":"%s"' \
  "$SKILL_E" "$RUN_ID_E" "$TRACE_MIRROR_STATUS")

if [ "$BRIEF_REL" != "null" ] && [ "$RECEIPT_REL" != "null" ]; then
  BRIEF_E=$(esc "$BRIEF_REL")
  RECEIPT_E=$(esc "$RECEIPT_REL")
  printf '{"ts":"%s","agentId":"%s","subagent":"%s","purpose":"%s","manuscript_sha256":"%s","phase":"%s","brief":"%s","brief_sha256":"%s","receipt":"%s","receipt_sha256":"%s","dispatch_nonce":"%s"%s}\n' \
    "$TS" "$AGENT_ID" "$SUBAGENT_E" "$PURPOSE_E" "$MS_SHA" "$PHASE_E" "$BRIEF_E" "$BRIEF_SHA" "$RECEIPT_E" "$RECEIPT_SHA" "$DISPATCH_NONCE" "$XFIELDS" \
    >> "$MANIFEST"
elif [ "$BRIEF_REL" != "null" ]; then
  BRIEF_E=$(esc "$BRIEF_REL")
  printf '{"ts":"%s","agentId":"%s","subagent":"%s","purpose":"%s","manuscript_sha256":"%s","phase":"%s","brief":"%s","brief_sha256":"%s"%s}\n' \
    "$TS" "$AGENT_ID" "$SUBAGENT_E" "$PURPOSE_E" "$MS_SHA" "$PHASE_E" "$BRIEF_E" "$BRIEF_SHA" "$XFIELDS" \
    >> "$MANIFEST"
else
  printf '{"ts":"%s","agentId":"%s","subagent":"%s","purpose":"%s","manuscript_sha256":"%s","phase":"%s"%s}\n' \
    "$TS" "$AGENT_ID" "$SUBAGENT_E" "$PURPOSE_E" "$MS_SHA" "$PHASE_E" "$XFIELDS" \
    >> "$MANIFEST"
fi

# Output for observability (the orchestrator may log this).
echo "MANIFEST_APPENDED=$MANIFEST"
echo "AGENT_ID=$AGENT_ID"
echo "PURPOSE=$PURPOSE"
echo "MS_SHA=${MS_SHA:0:12}…"
if [ "$MS_SHA" = "null" ]; then
  # Pre-manuscript phases (real-project eval, ses 2026-08-22): the mandated
  # Phase 3.5 reviewer dispatch and Step 5.5c fix dispatch both happen BEFORE
  # any manuscript exists — a missing manuscript there is the designed state,
  # not a fault, and rc=2 was killing `set -e` orchestrator blocks that were
  # doing exactly what the docs mandate. The line is appended either way; the
  # exit code distinguishes "expected null" from "manuscript should exist":
  #   phase < 7 or a non-numeric tag (pre-exec-*, R1, …) -> rc 0 + WARN
  #   phase >= 7 (manuscript phases)                     -> rc 2 (unchanged)
  _MS_EXPECTED=$(printf '%s' "$PHASE" | awk '{ if ($0 + 0 >= 7 && $0 ~ /^[0-9]/) print "yes"; else print "no" }')
  if [ "$_MS_EXPECTED" = "yes" ]; then
    echo "WARN: manuscript not found at $MANUSCRIPT — manifest entry has null SHA" >&2
    exit 2
  fi
  echo "WARN: manuscript not found at $MANUSCRIPT — manifest entry has null SHA (expected pre-manuscript; phase=$PHASE)" >&2
fi
exit 0
