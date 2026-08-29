#!/usr/bin/env bash
# emit-agent-brief.sh — mechanical briefing packet for a gated agent dispatch
# (RCA Round 2 #10, 2026-08-22).
#
# WHY: the pipeline verified an agent RAN (return-side provenance) but never
# WHAT IT WAS TOLD. Briefs were composed from orchestrator recollection in a
# saturated context: the ses iteration-3 reviewer was dispatched 50 minutes
# BEFORE the decision it needed was recorded; 2 of 16 agents read
# project-state; the senior reviewer graded prose while quant graded the
# JSONs — the panel graded different objects (RCA §2 #8). The brief is the
# machine record of the input side: every input named BY PATH + SHA-256 with
# a why, the forbidden reads, the lock id, the return contract, and the
# strip directives — written to disk BEFORE dispatch, referenced by path in
# the prompt, and bindable to the dispatch-manifest row via
# `emit-task-dispatch.sh --brief`.
#
# This is the GENERIC packet (JSON). The Phase 5.5 FIX agent keeps its
# specialized mechanical brief (emit-fix-brief.sh, Round 1 #1) — that one is
# derived from the findings ledger; this one is for reviewer/verifier/
# assembly/reader dispatches.
#
# USAGE
#   emit-agent-brief.sh <proj> <phase> <role> \
#     --report-to "rel/path.md" \
#     [--trace-to "rel/path.trace.ndjson"] \
#     [--inputs "rel/path[:why],rel/path[:why],..."] \
#     [--forbid "rel/path,rel/path,..."] \
#     [--return findings-ndjson|report-md|checklist-json|records-json] \
#     [--purpose "<one line>"]
#
#   Inputs are relative to <proj> (or absolute). Each is REQUIRED to exist —
#   a brief naming a nonexistent input fails closed (exit 1): briefing an
#   agent on files that are not there is the dispatched-before-recorded
#   failure this tool exists to stop.
#
#   --report-to is REQUIRED (system-fix S1.4, 2026-08-23): without it a
#   dispatched report was stdout-only and left no trace event, which
#   trace-coverage-check.sh then RED-failed — the default path produced
#   artifacts a later gate rejects (handoff P3-3). Emission REFUSES (exit 2)
#   when the flag is absent, and FAILS CLOSED (exit 1) when the report path
#   already exists on disk — retries must version their report path, never
#   overwrite a prior attempt. --trace-to defaults to <report>.trace.ndjson.
#
#   The packet carries a `dispatch_nonce` (agent-brief/v2, system-fix P0.3):
#   a pre-dispatch identifier the verification receipt, the prompt, the
#   manifest row, and the returned report all bind to — task_invocation_id
#   only exists AFTER a Task returns, so it cannot anchor pre-dispatch
#   provenance, and phase+role alone collides on retries and parallel
#   same-role dispatches.
#
# OUTPUT: <proj>/briefs/<phase>-<role>.json (versioned -2, -3 on collision);
# prints BRIEF=<path> and NONCE=<hex>. Exit 0 ok | 1 missing input /
# report-path collision | 2 usage.
set -uo pipefail

PROJ="${1:-}"; PHASE="${2:-}"; ROLE="${3:-}"
if [ -z "$PROJ" ] || [ ! -d "$PROJ" ] || [ -z "$PHASE" ] || [ -z "$ROLE" ]; then
  echo "usage: emit-agent-brief.sh <proj> <phase> <role> [--inputs ...] [--forbid ...] [--return findings-ndjson|report-md|checklist-json|records-json] [--purpose ...]" >&2
  exit 2
fi
shift 3
case "$PHASE$ROLE" in */*) echo "emit-agent-brief: phase/role must not contain '/'" >&2; exit 2 ;; esac
INPUTS=""; FORBID=""; RETURN_FMT="report-md"; PURPOSE=""; REPORT_TO=""; TRACE_TO=""
PAIR_INPUTS=""   # newline-separated "path<TAB>why" records from --input/--why —
                 # safe for the colon/comma-bearing filenames reference managers
                 # produce ("Autor, Dorn, Hanson - 2013.pdf", "Title: Sub.pdf");
                 # the --inputs CSV form remains for simple paths.
_LAST_INPUT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --inputs)  INPUTS="${2:-}"; shift 2 ;;
    # Pair accumulation is FLUSH-ON-NEXT, never rewrite-last: the previous
    # form deleted the placeholder line with `PAIR_INPUTS=$(... | sed '$d')`,
    # and the command substitution ALSO stripped the trailing newline joining
    # the kept lines — from the second pair on, every record concatenated
    # onto the first line and all but input #1 silently vanished from the
    # brief (caught re-emitting the ses round-5 brief, 2026-08-22).
    --input)   if [ -n "$_LAST_INPUT" ]; then
                 PAIR_INPUTS="${PAIR_INPUTS}${_LAST_INPUT}	input for this dispatch
"
               fi
               _LAST_INPUT="${2:-}"
               shift 2 ;;
    --why)     [ -n "$_LAST_INPUT" ] || { echo "emit-agent-brief: --why must follow an --input" >&2; exit 2; }
               PAIR_INPUTS="${PAIR_INPUTS}${_LAST_INPUT}	${2:-}
"
               _LAST_INPUT=""
               shift 2 ;;
    --forbid)  FORBID="${2:-}"; shift 2 ;;
    --return)  RETURN_FMT="${2:-}"; shift 2 ;;
    --purpose) PURPOSE="${2:-}"; shift 2 ;;
    --report-to) REPORT_TO="${2:-}"; shift 2 ;;
    --trace-to)  TRACE_TO="${2:-}"; shift 2 ;;
    *) echo "emit-agent-brief: unknown flag $1" >&2; exit 2 ;;
  esac
done
# Flush a trailing --input that never received its --why.
if [ -n "$_LAST_INPUT" ]; then
  PAIR_INPUTS="${PAIR_INPUTS}${_LAST_INPUT}	input for this dispatch
"
  _LAST_INPUT=""
fi
# C10 (2026-08-22 verification round): an unknown --return silently fell back
# to report-md — fail-open in a fail-closed tool.
case "$RETURN_FMT" in
  findings-ndjson|report-md|checklist-json|records-json) : ;;
  *) echo "emit-agent-brief: unknown --return '$RETURN_FMT' (findings-ndjson|report-md|checklist-json|records-json)" >&2; exit 2 ;;
esac
# S1.4 fail-closed output contract: a gated dispatch without a report path
# leaves its report in stdout only and its agentId with no trace event —
# artifacts trace-coverage-check.sh later RED-fails. Refuse to emit.
if [ -z "$REPORT_TO" ]; then
  echo "emit-agent-brief: --report-to <rel/path> is REQUIRED (S1.4 fail-closed)." >&2
  echo "  A gated dispatch without a persisted report path produces artifacts" >&2
  echo "  trace-coverage-check.sh rejects. Name the report file the agent must" >&2
  echo "  Write; --trace-to defaults to <report>.trace.ndjson." >&2
  exit 2
fi
[ -n "$TRACE_TO" ] || TRACE_TO="${REPORT_TO}.trace.ndjson"

# Handoff 2026-08-25 P2-B: the read-time data guard, run predictively at
# brief time (see the python block). Located beside this script so the
# emitter and the enforcer cannot drift apart silently.
DATA_GUARD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/pretooluse-data-guard.sh"

PROJ="$PROJ" PHASE="$PHASE" ROLE="$ROLE" INPUTS="$INPUTS" PAIR_INPUTS="$PAIR_INPUTS" FORBID="$FORBID" \
RETURN_FMT="$RETURN_FMT" PURPOSE="$PURPOSE" REPORT_TO="$REPORT_TO" TRACE_TO="$TRACE_TO" \
DATA_GUARD="$DATA_GUARD" python3 - <<'PY'
import hashlib, json, os, secrets, sys
from datetime import datetime, timezone

proj = os.environ["PROJ"]; phase = os.environ["PHASE"]; role = os.environ["ROLE"]

# S1.4: a report path that already exists means a prior attempt wrote there —
# retries version their report path (version-check.sh discipline), never
# overwrite. Fail closed before hashing anything.
report_to = os.environ["REPORT_TO"]; trace_to = os.environ["TRACE_TO"]
_report_abs = report_to if os.path.isabs(report_to) else os.path.join(proj, report_to)
if os.path.exists(_report_abs):
    sys.stderr.write("emit-agent-brief: FAIL-CLOSED — report path %r already exists; "
                     "a retry must use a versioned path, never overwrite a prior "
                     "attempt's report (S1.4)\n" % report_to)
    sys.exit(1)

# P0.3: the dispatch nonce exists BEFORE the Task returns, so pre-dispatch
# artifacts (receipt, prompt, report header) can bind to it — unlike
# task_invocation_id, which only exists after.
nonce = secrets.token_hex(12)

def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for c in iter(lambda: f.read(65536), b""):
            h.update(c)
    return h.hexdigest()

inputs, missing = [], []
specs = []
for spec in [s for s in os.environ["INPUTS"].split(",") if s.strip()]:
    path, _, why = spec.partition(":")
    specs.append((path.strip(), why.strip(), spec))
for line in [l for l in os.environ.get("PAIR_INPUTS", "").split("\n") if l.strip()]:
    path, _, why = line.partition("\t")
    specs.append((path.strip(), why.strip(), line))
for path, why, raw in specs:
    ap = path if os.path.isabs(path) else os.path.join(proj, path)
    if not os.path.isfile(ap):
        missing.append("%r (from spec %r)" % (path, raw))
        continue
    inputs.append({"path": path, "sha256": sha256(ap),
                   "bytes": os.path.getsize(ap),
                   "why": why or "input for this dispatch"})
if missing:
    sys.stderr.write("emit-agent-brief: FAIL-CLOSED — input(s) do not exist "
                     "(dispatching an agent on files that are not there is the "
                     "dispatched-before-recorded failure): %s\n"
                     "hint: paths containing ':' or ',' must use --input \"<path>\" [--why \"<text>\"]\n"
                     % "; ".join(missing))
    sys.exit(1)
if not inputs:
    sys.stderr.write("emit-agent-brief: WARN zero inputs — legitimate only for "
                     "search-only agents; a review/fix/assembly brief without "
                     "inputs is a recollection brief\n")

# Handoff 2026-08-25 P2-B (verified on the premarital-cohab run): a brief
# named tables/spec-registry.csv as an input for four seats; the read-time
# guard then denied it, and each seat's only honest move was to record its
# coverage as UNVERIFIABLE — one refusal cost four review surfaces. Predict
# the guard's decision HERE, at brief time, by running the SAME script the
# host runs at read time. This is a point-in-time prediction, not an
# equivalence: sidecar or file state can change between brief and Read
# (the receipt chain re-verifies at dispatch), but a deny NOW is certain
# enough to refuse on. Payload uses the ABSOLUTE resolved path and the
# ABSOLUTE project cwd — the guard anchors relative paths and sidecar
# discovery there (Codex review 2026-08-25, item 2).
guard = os.environ.get("DATA_GUARD", "")
guard_waive = os.environ.get("SCHOLAR_BRIEF_GUARD_WAIVE", "") == "1"
proj_abs = os.path.abspath(proj)
input_guard = "verified"
if not os.path.isfile(guard):
    if guard_waive:
        sys.stderr.write("emit-agent-brief: WARN data guard not found at %r — proceeding "
                         "ONLY because SCHOLAR_BRIEF_GUARD_WAIVE=1; the waiver is recorded "
                         "in the brief for audit\n" % guard)
        input_guard = "WAIVED (guard absent; SCHOLAR_BRIEF_GUARD_WAIVE=1)"
    else:
        sys.stderr.write("emit-agent-brief: FAIL-CLOSED — pretooluse-data-guard.sh not found "
                         "at %r, so brief-named inputs cannot be checked against the read-time "
                         "policy. An unassessed check is not a passed check. If this host "
                         "genuinely has no guard, set SCHOLAR_BRIEF_GUARD_WAIVE=1 (recorded "
                         "in the brief as an auditable waiver).\n" % guard)
        sys.exit(1)
else:
    import subprocess
    _denied = []
    for rec in inputs:
        _ap = rec["path"] if os.path.isabs(rec["path"]) else os.path.join(proj_abs, rec["path"])
        _payload = json.dumps({"tool_name": "Read",
                               "tool_input": {"file_path": _ap},
                               "cwd": proj_abs})
        try:
            _r = subprocess.run(["bash", guard], input=_payload.encode("utf-8"),
                                capture_output=True, cwd=proj_abs, timeout=60)
        except Exception as e:  # timeout / spawn failure — fail closed, never skip
            _denied.append((rec["path"], "guard could not run (%s)" % e.__class__.__name__))
            continue
        if _r.returncode == 2:
            _msg = (_r.stdout or _r.stderr).decode("utf-8", errors="replace")
            _first = next((l for l in _msg.splitlines() if l.strip()), "denied")
            _denied.append((rec["path"], _first.strip()))
        elif _r.returncode != 0:
            _denied.append((rec["path"], "guard exited abnormally (rc=%d) — treated as deny"
                            % _r.returncode))
    if _denied:
        sys.stderr.write("emit-agent-brief: FAIL-CLOSED — the read-time data guard would DENY "
                         "%d brief-named input(s); dispatching anyway would cost the seat its "
                         "coverage at read time (handoff 2026-08-25 P2-B):\n" % len(_denied))
        for _p, _why in _denied:
            sys.stderr.write("  - %s: %s\n" % (_p, _why))
        sys.stderr.write("remedy: register the aggregate in .claude/safety-status.json "
                         "(CLAUDE.md §14; scholar-init review resolves NEEDS_REVIEW entries; "
                         "OVERRIDE entries need a typed rationale in logs/init-report.md), or "
                         "anonymize first, or drop the input from the brief.\n")
        sys.exit(1)

forbid = [s.strip() for s in os.environ["FORBID"].split(",") if s.strip()]
# Standing forbidden reads — always present, per the data-safety stack and
# the surface-lease discipline.
forbid = ["data/raw/ (any non-CLEARED file; LOCAL_MODE contract)",
          "other agents' in-flight report files (one writer per surface)"] + forbid

lock_id = None
lp = os.path.join(proj, "results-locked", "LATEST.txt")
if os.path.isfile(lp):
    lock_id = open(lp, encoding="utf-8", errors="replace").read().strip()[:120]

seam = None
sd = os.path.join(proj, "seams")
if os.path.isdir(sd):
    def phase_key(fname):
        # order by pipeline position parsed from the filename, mtime tiebreak —
        # newest-by-mtime alone let a re-verified EARLY phase's summary (or a
        # Dropbox-touched file) outrank the true latest (2026-08-22 round).
        tok = fname[:-len("-summary.json")]
        order = ["-1","0-PRE","0","0.D","1","2","3","3.5","4","5","5A.5","5A.7",
                 "5.5","5C","6","6.2","6.5","6.8","7","7b","7c","7c.5","8","9",
                 "9b","10","10.5","11","11b","11.5","12"]
        pos = order.index(tok) if tok in order else -1
        return (pos, os.path.getmtime(os.path.join(sd, fname)))
    cands = sorted((f for f in os.listdir(sd) if f.endswith("-summary.json")), key=phase_key)
    if cands:
        sp = os.path.join(sd, cands[-1])
        seam = {"path": "seams/" + cands[-1], "sha256": sha256(sp)}

fmt = os.environ["RETURN_FMT"]
contracts = {
    "records-json": "Return structured per-item records (one JSON object per unit — e.g., per paper: citekey, claims with anchors, mechanisms, methods, findings_class) written via the Write tool to the output_contract report_path; the orchestrator synthesizes FROM the records and never re-reads your raw inputs.",
    # S1.3 (handoff P2-4): the previous contract told four parallel seats to
    # append to ONE shared ledger — the concurrent-write clobber §7a exists
    # to forbid, and three of four seats declined it citing §7a. Each seat
    # now writes its own nonce-named inbox file; the ORCHESTRATOR is the
    # canonical ledger's only writer, via ingest-findings-inbox.sh.
    "findings-ndjson": "Write one OPEN line per blocking finding, as findings-ledger NDJSON (_shared/findings-ledger.md), to logs/findings-inbox/<DISPATCH_NONCE>.ndjson via the Write tool — you are that file's only writer — and return the consolidated blocker list in your final message, never raw prose. Do NOT append to logs/findings.ndjson: the orchestrator is the canonical ledger's single writer (CLAUDE.md §7a) and ingests your inbox after you return.",
    "report-md": "Write the full report via the Write tool to the output_contract report_path; if it exceeds 50KB, ALSO write a line-range INDEX file beside it (the cohab pipeline-friction-audit-INDEX pattern) — the orchestrator reads the index and returns, never the whole report.",
    "checklist-json": "Return a machine-readable checklist JSON (one entry per item: id, status PASS|FAIL|BLOCKED, evidence path) — the orchestrator adjudicates entries; it does not re-derive them.",
}
brief = {
    "schema": "agent-brief/v2",
    "phase": phase, "role": role,
    "dispatch_nonce": nonce,
    "ts": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "purpose": os.environ["PURPOSE"] or None,
    "inputs": inputs,
    "input_guard": input_guard,
    "forbidden_reads": forbid,
    "lock_id": lock_id,
    "seam_summary": seam,
    "output_contract": {
        "report_path": report_to,
        "trace_path": trace_to,
    },
    "return_contract": {
        "format": fmt,
        "rule": contracts.get(fmt, contracts["report-md"]),
        "provenance": "your dispatch is recorded in logs/dispatch-manifest.jsonl bound to THIS brief's sha256 and dispatch_nonce; a pre-dispatch verification receipt (briefs/receipts/<nonce>.json) attests your inputs were hash-verified; your report must open with 'DISPATCH_NONCE: <nonce>' and carry your task_invocation_id",
    },
    # S1.1 (handoff P1-3): the previous first directive ordered every seat to
    # `bash scripts/gates/verify-brief.sh` — unrunnable for Read/Write/
    # WebSearch reviewer seats, so brief verification never actually ran on a
    # gated reviewer dispatch. Verification now happens ORCHESTRATOR-side,
    # pre-dispatch (emit-verification-receipt.sh); the seat's obligations are
    # tool-free: echo the nonce, honor the paths, stop on inconsistency.
    "strip_directives": [
        "no verbatim data rows, no PII, aggregates and verdicts only (traces C-01)",
        "do not quote this brief back; act on it",
        "your inputs were sha256-verified pre-dispatch (verification receipt bound to dispatch_nonce %s); begin your report with the line 'DISPATCH_NONCE: %s'" % (nonce, nonce),
        "write your report to the output_contract report_path and your RAO trace sidecar to trace_path (_shared/agent-trace-contract.md)",
        "if an input contradicts its stated why, or looks stale against the purpose, STOP and report the inconsistency (DC-07) — never adapt around it",
    ],
}
bd = os.path.join(proj, "briefs")
os.makedirs(bd, exist_ok=True)
out = os.path.join(bd, "%s-%s.json" % (phase, role))
n = 2
while os.path.exists(out):
    out = os.path.join(bd, "%s-%s-%d.json" % (phase, role, n)); n += 1
with open(out, "w", encoding="utf-8") as f:
    json.dump(brief, f, indent=1, ensure_ascii=False)
    f.write("\n")
print("BRIEF=%s" % out)
print("NONCE=%s" % nonce)
PY
