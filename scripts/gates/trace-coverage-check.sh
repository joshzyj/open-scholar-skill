#!/usr/bin/env bash
# trace-coverage-check.sh — hard gate: a skill/phase must produce a valid RAO
# trace (reasoning + action + observation), and every dispatched agent must
# appear in it.
#
# CONTRACT
#   Reads the run's trace sink(s) at <root>/logs/trace-<skill>-*.ndjson (written
#   by emit-trace.sh; agent steps folded in by ingest-agent-trace.sh) and the
#   dispatch manifest at <root>/logs/dispatch-manifest.jsonl.
#
# VERDICT
#   GREEN  (exit 0) — a non-empty, well-formed trace exists; every record has the
#           required fields + a non-empty RAO triad; and (if a manifest + --phase
#           are present) every dispatched agentId appears as a trace event.
#   RED    (exit 1) — trace present but empty / malformed line / missing field /
#           all-empty triad; OR the target skill has no trace while the project
#           is clearly a CURRENT run (a manifest or some other trace exists); OR
#           a dispatched agentId has no trace event.
#   YELLOW (exit 2) — no trace AND no trace/manifest infrastructure at all
#           (a legacy project predating trace adoption — bounded migration
#           window, mirrors the codex-prose-coverage legacy path).
#
#   Prints a `STATUS=GREEN|YELLOW|RED` line so it composes with
#   normalize-gate-status.sh.
#
# USAGE
#   bash scripts/gates/trace-coverage-check.sh <root> [--skill X] [--phase P]
#     <root> = project dir / OUTPUT_ROOT containing logs/

set -uo pipefail

ROOT="" SKILL="" PHASE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --skill) SKILL="${2:-}"; shift 2 ;;
    --phase) PHASE="${2:-}"; shift 2 ;;
    -h|--help) grep -E '^#' "$0" | sed 's/^# *//'; exit 0 ;;
    *) if [ -z "$ROOT" ]; then ROOT="$1"; shift; else echo "ERROR: unexpected arg $1" >&2; exit 64; fi ;;
  esac
done

if [ -z "$ROOT" ] || [ ! -d "$ROOT" ]; then
  echo "Usage: trace-coverage-check.sh <root> [--skill X] [--phase P]" >&2
  echo "ABORT: root dir not found: ${ROOT:-<none>}" >&2
  exit 64
fi

LOG_DIR="$ROOT/logs"
MANIFEST="$LOG_DIR/dispatch-manifest.jsonl"

# ── Discover trace files ────────────────────────────────────────────────────
TARGET_TRACES=()
ANY_TRACE=0
if [ -d "$LOG_DIR" ]; then
  for f in "$LOG_DIR"/trace-*.ndjson; do
    [ -f "$f" ] || continue
    ANY_TRACE=1
    if [ -n "$SKILL" ]; then
      case "$(basename "$f")" in
        trace-"$SKILL"-*.ndjson) TARGET_TRACES+=("$f") ;;
      esac
    else
      TARGET_TRACES+=("$f")
    fi
  done
fi
HAS_MANIFEST=0
[ -f "$MANIFEST" ] && HAS_MANIFEST=1

# ── No target trace → YELLOW (migration-safe) ───────────────────────────────
# A project that predates trace adoption (or a skill that has not yet run) has
# no trace. During the rollout window this is advisory, NOT a hard failure —
# otherwise every legacy project would RED. The hard teeth are: (a) the static
# ratchet that every skill/agent CALLS emit-trace, and (b) the RED verdicts
# below for a trace that IS present but broken/incomplete.
if [ "${#TARGET_TRACES[@]}" -eq 0 ]; then
  echo "STATUS=YELLOW"
  echo "WARN: no RAO trace for ${SKILL:-<skill>} under $LOG_DIR — legacy/not-yet-run"
  echo "      (advisory during the trace-adoption migration window). Emit a trace via"
  echo "      emit-trace.sh per _shared/process-logger.md."
  exit 2
fi

# ── Validate present traces + agent-dispatch cross-link (python3) ───────────
if ! command -v python3 >/dev/null 2>&1; then
  echo "STATUS=YELLOW"
  echo "WARN: python3 unavailable — cannot validate NDJSON trace schema; advisory only."
  exit 2
fi

VERDICT=$(python3 - "$MANIFEST" "$PHASE" "$SKILL" "${SCHOLAR_TRACE_XLINK_ENFORCE:-0}" "${TARGET_TRACES[@]}" <<'PY'
import json, sys
manifest, phase = sys.argv[1], sys.argv[2]
skill_arg, xlink_enforce = sys.argv[3], sys.argv[4] == "1"
trace_files = sys.argv[5:]
REQ = {"ts","seq","run_id","skill","phase","agent","agentId","step","reasoning","action","observation","refs","status"}

seen_agent_ids = set()
run_ids_seen = set()
records = 0
for tf in trace_files:
    ln = 0
    for line in open(tf):
        line = line.strip()
        if not line:
            continue
        ln += 1
        try:
            r = json.loads(line)
        except Exception:
            print(f"RED|malformed NDJSON line {ln} in {tf}")
            sys.exit(0)
        miss = REQ - set(r)
        if miss:
            print(f"RED|record {ln} in {tf} missing fields: {sorted(miss)}")
            sys.exit(0)
        if not str(r.get("step") or "").strip():
            print(f"RED|record {ln} in {tf} has empty step")
            sys.exit(0)
        if not (str(r.get('reasoning') or '') or str(r.get('action') or '') or str(r.get('observation') or '')):
            print(f"RED|record {ln} in {tf} has an all-empty reasoning/action/observation triad")
            sys.exit(0)
        aid = r.get("agentId")
        if aid:
            seen_agent_ids.add(aid)
        if r.get("run_id"):
            run_ids_seen.add(r["run_id"])
        records += 1

if records == 0:
    print("RED|trace file(s) present but contain zero records")
    sys.exit(0)

# ── Agent-dispatch cross-link (trace plan D2, 2026-08-26) ───────────────────
# Every dispatched agentId in scope must have a trace event. Two corrections
# to the pre-2026-08-26 behaviour, both measured:
#
# 1. It was DORMANT for the skill it mattered most to. The whole block was
#    gated on `if phase and ...`, and scholar-idea's own invocation
#    (SKILL.md:52) passes --skill but never --phase — so a run with five real
#    dispatches and zero agent events printed GREEN. Reproduced before fixing.
# 2. The phase path cross-linked by phase ALONE while traces are filtered to
#    one skill, so two skills both using phase "0" demanded each other's
#    agentIds. Preserving that "unchanged" would have preserved a bug.
#
# Scope now = rows matching this skill (and phase too, when given). Rows that
# predate the skill/run_id fields cannot be scoped: they are COUNTED and
# reported, never silently passed — "could not check" is not "checked".
unscoped = 0
missing = []
if manifest:
    import os
    if os.path.isfile(manifest):
        for line in open(manifest):
            line = line.strip()
            if not line:
                continue
            try:
                m = json.loads(line)
            except Exception:
                # A malformed row can HIDE a dispatch; never skip it silently.
                unscoped += 1
                continue
            aid = m.get("agentId")
            if not aid:
                continue
            row_skill = m.get("skill")
            row_run = m.get("run_id")
            if phase and str(m.get("phase")) != str(phase):
                continue
            if not row_skill:
                # legacy row: no identity to scope by
                unscoped += 1
                continue
            if skill_arg and row_skill != skill_arg:
                continue          # another skill's dispatch — not our business
            # run_id REPORTS, it does not EXCLUDE. Filtering out rows whose
            # run_id is absent from the trace would silently drop exactly the
            # rows this gate exists to catch — a dispatch whose entire run
            # left no trace, or one carrying a wrong/bogus run id, would read
            # as "a different run" and vanish. (Caught by this gate's own
            # suite: the missing-aid case flipped to GREEN.) Same-skill,
            # same-day runs share one trace file, so scoping by skill alone
            # does not create cross-run false positives.
            if aid not in seen_agent_ids:
                missing.append((aid, m.get("trace_mirror_status") or "unknown"))

print(f"XLINK_CHECKED|{len(seen_agent_ids)}")
print(f"XLINK_UNSCOPED|{unscoped}")

if missing:
    uniq = sorted({a for a, _ in missing})
    fails = sorted({s for _, s in missing if str(s).startswith("failed")})
    detail = f"{len(uniq)} dispatched agentId(s) have no trace event: {uniq[:5]}"
    if fails:
        detail += f" (mirror status: {fails[:3]})"
    # A row carrying full identity (skill, and run_id when the skill uses one)
    # is NOT legacy ambiguity — a real panel is indistinguishable from five
    # inline personas without its trace events, so this REDs on sight. Legacy
    # unscoped rows are reported above and cannot reach here.
    print(f"RED|{detail}")
    sys.exit(0)

if unscoped:
    # Bounded, not merely counted: unscoped rows could belong to this run, so
    # the verdict is explicitly degraded rather than green.
    lvl = "RED" if xlink_enforce else "YELLOW"
    print(f"{lvl}|{unscoped} dispatch row(s) lack skill/run_id identity — cross-link could not scope them (legacy rows; re-emit with --skill to bind, or set SCHOLAR_TRACE_XLINK_ENFORCE=1 to fail on them)")
    sys.exit(0)

print(f"GREEN|{records} valid RAO record(s); {len(seen_agent_ids)} agent event(s)")
PY
)

# The validator emits diagnostic counters (XLINK_*) before its verdict, so the
# VERDICT is the LAST line — not the first. Taking the first would read
# "XLINK_CHECKED" as the code and fail closed on every run (caught by this
# gate's own suite before it shipped).
XLINK_INFO=$(printf '%s\n' "$VERDICT" | grep -E '^XLINK_' || true)
VERDICT_LINE=$(printf '%s\n' "$VERDICT" | grep -E '^(GREEN|RED|YELLOW)\|' | tail -1)
[ -z "$XLINK_INFO" ] || printf '%s\n' "$XLINK_INFO" | tr '|' '='

CODE="${VERDICT_LINE%%|*}"
MSG="${VERDICT_LINE#*|}"
case "$CODE" in
  GREEN)  echo "STATUS=GREEN";  echo "PASS: $MSG"; exit 0 ;;
  YELLOW) echo "STATUS=YELLOW"; echo "WARN: $MSG"; exit 2 ;;
  RED)    echo "STATUS=RED";    echo "FAIL: $MSG"; exit 1 ;;
  *)      echo "STATUS=RED"; echo "FAIL: trace validation produced no verdict (fail closed): ${VERDICT:-<empty>}"; exit 1 ;;
esac
