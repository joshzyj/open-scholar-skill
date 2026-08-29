#!/usr/bin/env bash
# pre-exec-review-check.sh — standalone pre-execution code-review gate.
#
# CONTRACT
#   Verifies that a DRAFTED analysis-script set passed independent code
#   review and that the reviewed bytes are the bytes on disk, BEFORE any
#   of those scripts execute. Companion to _shared/pre-execution-review.md.
#   Consumed by scholar-analyze A2.5, scholar-eda Phase 11, scholar-compute
#   MODULE 0.7, scholar-data W4/W6/W7, scholar-simulate, scholar-ling —
#   AND, since 2026-08-22 (RCA Round 1 #1), wired HARD into phase-verify.sh
#   at 5A.5 (--phase 5A.5) and at 5.5 (--phase 5.5, the fix path: the
#   reviewed-scripts-fix-<round>.json receipt matches the default manifest
#   glob, so a fix round that changed bytes without a receipt REDs).
#
# RULE-SET
#   R1  Manifest pairing: the reviewed-scripts manifest (code-review-manifest/v1,
#       emitted by scholar-code-review) names the report; the report must exist
#       and contain the manifest's review_id verbatim. Pairing is by review_id,
#       never by file mtime.
#   R2  Hash binding: every scripts[] entry must exist on disk and its SHA-256
#       must match. Any mismatch/missing => RED (review-then-edit-then-execute
#       is the loophole this gate exists to close).
#   R2b Out-of-scope hash binding: when supersedes_review_id is set, every
#       out_of_scope[] path must still match the SHA-256 the PRIOR manifest
#       recorded for it. A fix round can declare a file "out of scope — not
#       touched" while having silently rewritten it; R2 only hashes scripts[]
#       and R3 only checks name-coverage, so nothing else catches this.
#   R3  Completeness: reviewable scripts on disk (in --scripts-dir, matching
#       *.R *.r *.py *.do *.jl) that appear in NEITHER scripts[] NOR
#       out_of_scope[] => RED (unreviewed script in scope).
#   R4  Verdict: report must not carry a blocking verdict
#       (CRITICAL|HALT|FAIL|MAJOR ISSUES|FIXES NEEDED|DO NOT TRUST — same
#       enum as phase-verify.sh Phase 5A.5).
#   R5  Escalation: logs/code-review-escalation-*.md (maxdepth 1) non-empty => RED.
#   R6  Fix chain: manifest remaining_blocking_count > 0 => RED;
#       supersedes_review_id names a manifest that does not exist => RED.
#   R7  Coverage: delegated to code-review-coverage-check.sh with the caller's
#       --required mode and --phase tag. Delegated rc=1 => RED. Delegated
#       rc=2 (missing manifest/report there) => RED here — scripts-without-
#       provenance is never a warning pre-execution (legacy exception: R8).
#   R8  Legacy: with --legacy-ok, a project with scripts but no manifest
#       exits YELLOW instead of RED. YELLOW is NON-EXECUTABLE under the
#       protocol — it means "re-review", not "proceed".
#
# USAGE
#   pre-exec-review-check.sh <proj> [--manifest <file>] [--scripts-dir <dir>]
#                            [--required=fast|full] [--phase <tag>] [--legacy-ok]
#
#   --manifest     reviewed-scripts sidecar. Default: newest
#                  <proj>/code-review/reviewed-scripts-*.json (reported).
#   --scripts-dir  where reviewable scripts live. Default: <proj>/scripts
#   --required     coverage mode handed to code-review-coverage-check.sh
#                  (default fast).
#   --phase        dispatch-manifest phase tag handed to the coverage check
#                  (default pre-exec). MUST equal the tag used at the ORIGINAL
#                  reviewer dispatch (emit-task-dispatch.sh --phase, i.e. the
#                  dispatch manifest rows' "phase" field) — the coverage check
#                  counts dispatches by this tag, so a mismatched tag reads an
#                  empty dispatch set and REDs an honestly-reviewed round.
#                  Convention (findings-ledger.md): a finding's ledger `phase`
#                  equals the phase tag of the dispatch that reviewed it.
#
# EXIT CODES
#   0 GREEN   review is current, hash-bound, clean — reviewed files may execute
#   1 RED     any R1–R7 failure — fix + re-review; do NOT execute
#   2 YELLOW  legacy-only (R8) — non-executable; re-review first — OR
#             R6b: fixed_finding_ids whose latest ledger state is FIXED with no
#             VERIFIED line (receipt valid, closure pending; DC-03)
#   3 INERT   no reviewable scripts in scope
#
# FIXTURES: tests/smoke/test-pre-exec-review-check.sh

set -uo pipefail

PROJ=""
MANIFEST=""
SCRIPTS_DIR=""
MODE="fast"
PHASE_TAG="pre-exec"
LEGACY_OK=0

while [ $# -gt 0 ]; do
  case "$1" in
    --manifest)      MANIFEST="${2:-}"; shift 2 ;;
    --scripts-dir)   SCRIPTS_DIR="${2:-}"; shift 2 ;;
    --required=fast) MODE="fast"; shift ;;
    --required=full) MODE="full"; shift ;;
    --required=*)    echo "ERR: unknown --required value (expected fast|full)" >&2; exit 1 ;;
    --phase)         PHASE_TAG="${2:-}"; shift 2 ;;
    --legacy-ok)     LEGACY_OK=1; shift ;;
    -h|--help)       grep -E '^#' "$0" | sed 's/^# *//'; exit 0 ;;
    *)
      if [ -z "$PROJ" ]; then PROJ="$1"; shift
      else echo "ERR: unexpected positional arg: $1" >&2; exit 1
      fi
      ;;
  esac
done

if [ -z "$PROJ" ] || [ ! -d "$PROJ" ]; then
  echo "Usage: pre-exec-review-check.sh <proj> [--manifest <file>] [--scripts-dir <dir>] [--required=fast|full] [--phase <tag>] [--legacy-ok]" >&2
  exit 1
fi
[ -z "$SCRIPTS_DIR" ] && SCRIPTS_DIR="$PROJ/scripts"

if ! command -v jq >/dev/null 2>&1; then
  echo "STATUS=RED"
  echo "FAIL: jq is required to parse the reviewed-scripts manifest."
  exit 1
fi

_sha256() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" 2>/dev/null | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" 2>/dev/null | awk '{print $1}'
  else echo ""; fi
}

# ── Resolve reviewable scripts on disk ────────────────────────────────────
DISK_SCRIPTS=""
if [ -d "$SCRIPTS_DIR" ]; then
  DISK_SCRIPTS=$(find "$SCRIPTS_DIR" -maxdepth 1 -type f \
    \( -name '*.R' -o -name '*.r' -o -name '*.py' -o -name '*.do' -o -name '*.jl' \) \
    2>/dev/null | sort || true)
fi

# INERT: nothing in scope at all.
if [ -z "$DISK_SCRIPTS" ]; then
  echo "STATUS=INERT"
  echo "INFO: no reviewable scripts found under $SCRIPTS_DIR — nothing to gate."
  exit 3
fi

# ── Locate the manifest ───────────────────────────────────────────────────
if [ -z "$MANIFEST" ]; then
  MANIFEST=$(ls -t "$PROJ"/code-review/reviewed-scripts-*.json 2>/dev/null | head -1 || true)
  [ -n "$MANIFEST" ] && echo "INFO: --manifest not given; using newest sidecar $(basename "$MANIFEST")"
fi

if [ -z "$MANIFEST" ] || [ ! -f "$MANIFEST" ]; then
  if [ "$LEGACY_OK" = "1" ]; then
    echo "STATUS=YELLOW"
    echo "WARN: scripts exist but no reviewed-scripts manifest found (legacy mode declared)."
    echo "      YELLOW is non-executable — run scholar-code-review (pre-execution mode) first."
    exit 2
  fi
  echo "STATUS=RED"
  echo "FAIL: scripts exist under $SCRIPTS_DIR but no reviewed-scripts manifest found."
  echo "      Run scholar-code-review in pre-execution mode (emits code-review/reviewed-scripts-<review_id>.json)."
  exit 1
fi

# ── R1: manifest schema + report pairing ──────────────────────────────────
if ! jq -e '.schema == "code-review-manifest/v1" and (.review_id | type == "string" and length > 0) and (.scripts | type == "array")' "$MANIFEST" >/dev/null 2>&1; then
  echo "STATUS=RED"
  echo "FAIL: manifest $(basename "$MANIFEST") is not valid code-review-manifest/v1 (need schema, review_id, scripts[])."
  exit 1
fi
REVIEW_ID=$(jq -r '.review_id' "$MANIFEST")
REPORT_REL=$(jq -r '.report // empty' "$MANIFEST")
REPORT_PATH=""
if [ -n "$REPORT_REL" ]; then
  case "$REPORT_REL" in
    /*) REPORT_PATH="$REPORT_REL" ;;
    *)  REPORT_PATH="$PROJ/$REPORT_REL" ;;
  esac
fi
if [ -z "$REPORT_PATH" ] || [ ! -f "$REPORT_PATH" ]; then
  echo "STATUS=RED"
  echo "FAIL: manifest names report '$REPORT_REL' but the file does not exist under $PROJ."
  exit 1
fi
if ! grep -qF "$REVIEW_ID" "$REPORT_PATH" 2>/dev/null; then
  echo "STATUS=RED"
  echo "FAIL: report $(basename "$REPORT_PATH") does not contain review_id '$REVIEW_ID' — report/manifest pair mismatch."
  exit 1
fi

# ── R2: hash binding ──────────────────────────────────────────────────────
HASH_FAILS=""
N_SCRIPTS=$(jq -r '.scripts | length' "$MANIFEST")
i=0
while [ "$i" -lt "$N_SCRIPTS" ]; do
  S_PATH=$(jq -r ".scripts[$i].path" "$MANIFEST")
  S_SHA=$(jq -r ".scripts[$i].sha256" "$MANIFEST")
  case "$S_PATH" in
    /*) ABS="$S_PATH" ;;
    *)  ABS="$PROJ/$S_PATH" ;;
  esac
  if [ ! -f "$ABS" ]; then
    HASH_FAILS="${HASH_FAILS}\n  - MISSING: $S_PATH (reviewed but not on disk)"
  else
    DISK_SHA=$(_sha256 "$ABS")
    if [ -z "$DISK_SHA" ] || [ "$DISK_SHA" != "$S_SHA" ]; then
      HASH_FAILS="${HASH_FAILS}\n  - HASH MISMATCH: $S_PATH (edited after review — re-review required)"
    fi
  fi
  i=$((i + 1))
done
if [ -n "$HASH_FAILS" ]; then
  echo "STATUS=RED"
  echo "FAIL: reviewed-script hash binding failed (review_id=$REVIEW_ID):"
  printf '%b\n' "$HASH_FAILS"
  echo "The reviewed bytes must be the executed bytes. Fix + re-review (scholar-code-review Step 6) before executing."
  exit 1
fi

# ── R2b: out_of_scope[] is a CLAIM of non-modification — hash-bind it ─────
# A lying fix receipt can declare a silently-rewritten file "out of scope —
# not touched" and the rest of the gate clears it for execution: R2 hashes
# only scripts[], R3 checks name-coverage only, and nothing anywhere hashed
# an out_of_scope[] path. When the manifest names a superseded manifest,
# every out_of_scope[] path that the PRIOR manifest hashed must still match
# the PRIOR sha on disk — "out of scope" defers to the review that DID cover
# the file, so drift since that review makes the claim false. No prior
# manifest => no baseline to bind against (the R3 name-coverage rule still
# applies); this is the documented limit, not a silent one.
_R2B_SUP=$(jq -r '.supersedes_review_id // empty' "$MANIFEST")
if [ -n "$_R2B_SUP" ]; then
  _R2B_PRIOR=""
  for _pm in "$PROJ"/code-review/reviewed-scripts-*.json; do
    [ -f "$_pm" ] || continue
    if [ "$(jq -r '.review_id // empty' "$_pm" 2>/dev/null)" = "$_R2B_SUP" ]; then
      _R2B_PRIOR="$_pm"
      break
    fi
  done
  if [ -n "$_R2B_PRIOR" ]; then
    R2B_FAILS=""
    N_OOS=$(jq -r '.out_of_scope | length' "$MANIFEST" 2>/dev/null || echo 0)
    case "$N_OOS" in ''|*[!0-9]*) N_OOS=0 ;; esac
    i=0
    while [ "$i" -lt "$N_OOS" ]; do
      O_PATH=$(jq -r ".out_of_scope[$i].path // empty" "$MANIFEST")
      i=$((i + 1))
      [ -n "$O_PATH" ] || continue
      PRIOR_SHA=$(jq -r --arg p "$O_PATH" '.scripts[] | select(.path == $p) | .sha256' "$_R2B_PRIOR" 2>/dev/null | head -1)
      [ -n "$PRIOR_SHA" ] || continue
      case "$O_PATH" in
        /*) O_ABS="$O_PATH" ;;
        *)  O_ABS="$PROJ/$O_PATH" ;;
      esac
      [ -f "$O_ABS" ] || continue
      O_DISK=$(_sha256 "$O_ABS")
      if [ -n "$O_DISK" ] && [ "$O_DISK" != "$PRIOR_SHA" ]; then
        R2B_FAILS="${R2B_FAILS}\n  - $O_PATH (declared out_of_scope, but its bytes MOVED since review $_R2B_SUP — the claim of non-modification is false)"
      fi
    done
    if [ -n "$R2B_FAILS" ]; then
      echo "STATUS=RED"
      echo "FAIL: out_of_scope[] hash binding failed (review_id=$REVIEW_ID supersedes $_R2B_SUP):"
      printf '%b\n' "$R2B_FAILS"
      echo "A file declared out of scope defers to the review that covered it; changed bytes"
      echo "make that declaration a lie. Either move the file into scripts[] (it was touched"
      echo "— review the new bytes) or restore the reviewed bytes."
      exit 1
    fi
  fi
fi
unset _R2B_SUP _R2B_PRIOR R2B_FAILS N_OOS O_PATH PRIOR_SHA O_ABS O_DISK 2>/dev/null || true

# ── R2b: out_of_scope[] is a CLAIM of non-modification — hash-bind it ─────
# (R3 verification round, 2026-08-22, spiral-walk s3b): a lying fix receipt
# declared a silently-rewritten file "out of scope — not touched" and the
# full gate cleared it for execution: R2 hashes only scripts[], R3 checks
# name-coverage only, and nothing anywhere hashed an out_of_scope[] path.
# When the manifest names a superseded manifest, every out_of_scope[] path
# that the PRIOR manifest hashed must still match the PRIOR sha on disk —
# "out of scope" defers to the review that DID cover the file, so drift
# since that review makes the claim false. No prior manifest → no baseline
# to bind against (the R3 name-coverage rule still applies); this is the
# documented limit, not a silent one.
_R2B_SUP=$(jq -r '.supersedes_review_id // empty' "$MANIFEST")
if [ -n "$_R2B_SUP" ]; then
  _R2B_PRIOR=""
  for _pm in "$PROJ"/code-review/reviewed-scripts-*.json; do
    [ -f "$_pm" ] || continue
    if [ "$(jq -r '.review_id // empty' "$_pm" 2>/dev/null)" = "$_R2B_SUP" ]; then
      _R2B_PRIOR="$_pm"
      break
    fi
  done
  if [ -n "$_R2B_PRIOR" ]; then
    R2B_FAILS=""
    N_OOS=$(jq -r '.out_of_scope | length' "$MANIFEST" 2>/dev/null || echo 0)
    case "$N_OOS" in ''|*[!0-9]*) N_OOS=0 ;; esac
    i=0
    while [ "$i" -lt "$N_OOS" ]; do
      O_PATH=$(jq -r ".out_of_scope[$i].path // empty" "$MANIFEST")
      i=$((i + 1))
      [ -n "$O_PATH" ] || continue
      PRIOR_SHA=$(jq -r --arg p "$O_PATH" '.scripts[] | select(.path == $p) | .sha256' "$_R2B_PRIOR" 2>/dev/null | head -1)
      [ -n "$PRIOR_SHA" ] || continue
      case "$O_PATH" in
        /*) O_ABS="$O_PATH" ;;
        *)  O_ABS="$PROJ/$O_PATH" ;;
      esac
      [ -f "$O_ABS" ] || continue
      O_DISK=$(_sha256 "$O_ABS")
      if [ -n "$O_DISK" ] && [ "$O_DISK" != "$PRIOR_SHA" ]; then
        R2B_FAILS="${R2B_FAILS}\n  - $O_PATH (declared out_of_scope, but its bytes MOVED since review $_R2B_SUP — the claim of non-modification is false)"
      fi
    done
    if [ -n "$R2B_FAILS" ]; then
      echo "STATUS=RED"
      echo "FAIL: out_of_scope[] hash binding failed (review_id=$REVIEW_ID supersedes $_R2B_SUP):"
      printf '%b\n' "$R2B_FAILS"
      echo "A file declared out of scope defers to the review that covered it; changed bytes"
      echo "make that declaration a lie. Either move the file into scripts[] (it was touched"
      echo "— review the new bytes) or restore the reviewed bytes."
      exit 1
    fi
  fi
fi
unset _R2B_SUP _R2B_PRIOR R2B_FAILS N_OOS O_PATH PRIOR_SHA O_ABS O_DISK 2>/dev/null || true

# ── R3: completeness (no unreviewed script in scope) ──────────────────────
COVERED=$( { jq -r '.scripts[].path' "$MANIFEST"; jq -r '.out_of_scope[]?.path // empty' "$MANIFEST"; } 2>/dev/null | sort -u)
EXTRA=""
while IFS= read -r F; do
  [ -z "$F" ] && continue
  REL="${F#"$PROJ"/}"
  if ! printf '%s\n' "$COVERED" | grep -qxF "$REL" && ! printf '%s\n' "$COVERED" | grep -qxF "$F"; then
    EXTRA="${EXTRA}\n  - $REL"
  fi
done <<EOF_DISK
$DISK_SCRIPTS
EOF_DISK
if [ -n "$EXTRA" ]; then
  echo "STATUS=RED"
  echo "FAIL: script(s) on disk are in neither scripts[] nor out_of_scope[] of manifest $REVIEW_ID:"
  printf '%b\n' "$EXTRA"
  echo "Every reviewable script in scope must be reviewed (or explicitly declared out of scope) before execution."
  exit 1
fi

# ── R4: blocking verdict (same enum as phase-verify.sh Phase 5A.5) ────────
if grep -qE '([Oo]verall[[:space:]]+[Vv]erdict|^VERDICT)[[:space:]]*:[[:space:]]*(CRITICAL|HALT|FAIL|MAJOR[[:space:]]+ISSUES|FIXES[[:space:]]+NEEDED|DO[[:space:]]+NOT[[:space:]]+TRUST)' "$REPORT_PATH" 2>/dev/null; then
  echo "STATUS=RED"
  echo "FAIL: report $(basename "$REPORT_PATH") carries a blocking verdict (CRITICAL/HALT/FAIL/MAJOR ISSUES/FIXES NEEDED/DO NOT TRUST)."
  echo "Apply the fix loop (_shared/code-review-fix-loop.md), re-review, and re-run this gate."
  echo "If instead a finding is being formally ACCEPTED rather than fixed, use the §7b"
  echo "acceptance lane: draft a PROPOSED-ACCEPTANCE entry in logs/gate-acceptances.md for"
  echo "the PI to ratify ([ACCEPTED: <phase> | NUMBER_EFFECT=…]), then RE-REVIEW to a clean"
  echo "verdict that cites the acceptance — this gate reads the report's verdict; it does"
  echo "not (and must not) resolve acceptances itself."
  exit 1
fi

# ── R5: escalation log ────────────────────────────────────────────────────
ESCALATION=$(find "$PROJ/logs" -maxdepth 1 -name "code-review-escalation-*.md" -type f 2>/dev/null | head -1 || true)
if [ -n "$ESCALATION" ] && [ -s "$ESCALATION" ]; then
  echo "STATUS=RED"
  echo "FAIL: escalation log is non-empty: $(basename "$ESCALATION") — a CRITICAL finding was escalated to the user."
  echo "Resolve the escalation (and re-review) before executing."
  exit 1
fi

# ── R6: fix chain ─────────────────────────────────────────────────────────
REMAINING=$(jq -r '.remaining_blocking_count // 0' "$MANIFEST")
if [ "$REMAINING" != "0" ] && [ "$REMAINING" != "null" ]; then
  echo "STATUS=RED"
  echo "FAIL: manifest $REVIEW_ID reports remaining_blocking_count=$REMAINING — blocking findings unresolved."
  exit 1
fi
# R6c (R3 eval rehearsal, 2026-08-22): remaining_blocking_count=0 was pure
# self-report — an understated count sailed through every gate. Cross-check
# it against the findings ledger: any id whose LATEST state is OPEN and
# whose locus file is among this manifest's scripts[] contradicts the
# claim of zero remaining blockers on these very files.
R6C_LEDGER="$PROJ/logs/findings.ndjson"
if [ -f "$R6C_LEDGER" ]; then
  R6C_OPEN=$(MANIFEST="$MANIFEST" LEDGER="$R6C_LEDGER" python3 - <<'PY_R6C' 2>/dev/null
import json, os
paths = set()
try:
    m = json.load(open(os.environ["MANIFEST"], encoding="utf-8"))
    for s in (m.get("scripts") or []):
        if isinstance(s, dict) and s.get("path"):
            p = s["path"]
            while p.startswith("./"):
                p = p[2:]
            paths.add(p)
except (OSError, ValueError):
    pass
latest = {}
for line in open(os.environ["LEDGER"], encoding="utf-8", errors="replace"):
    try:
        r = json.loads(line)
    except ValueError:
        continue
    if isinstance(r, dict) and r.get("id") and r.get("status"):
        latest[r["id"]] = (r["status"], str(r.get("locus") or ""))
out = []
for fid, (st, locus) in sorted(latest.items()):
    if st != "OPEN":
        continue
    lf = locus.split(":", 1)[0].strip()
    while lf.startswith("./"):
        lf = lf[2:]
    if lf in paths:
        out.append("%s (%s)" % (fid, locus))
print("; ".join(out))
PY_R6C
)
  if [ -n "$R6C_OPEN" ]; then
    echo "STATUS=RED"
    echo "FAIL: manifest $REVIEW_ID claims remaining_blocking_count=0, but the findings"
    echo "      ledger's LATEST state holds OPEN finding(s) on this manifest's own files:"
    echo "      ${R6C_OPEN}"
    echo "      The count is not self-certifying — fix and FIXED-file the finding(s), get"
    echo "      them ACCEPTED via §7b, or report the honest nonzero count."
    exit 1
  fi
fi
unset R6C_LEDGER R6C_OPEN 2>/dev/null || true
SUPERSEDES=$(jq -r '.supersedes_review_id // empty' "$MANIFEST")
if [ -n "$SUPERSEDES" ]; then
  if ! ls "$PROJ"/code-review/reviewed-scripts-*.json 2>/dev/null | xargs grep -lF "\"review_id\": \"$SUPERSEDES\"" >/dev/null 2>&1 \
     && ! ls "$PROJ"/code-review/reviewed-scripts-*.json 2>/dev/null | xargs grep -lF "\"review_id\":\"$SUPERSEDES\"" >/dev/null 2>&1; then
    echo "STATUS=RED"
    echo "FAIL: manifest claims supersedes_review_id=$SUPERSEDES but no such prior manifest exists — broken fix chain."
    exit 1
  fi
fi

# ── R7: coverage delegation ───────────────────────────────────────────────
CRC_GATE="$(dirname "$0")/code-review-coverage-check.sh"
if [ -f "$CRC_GATE" ]; then
  set +e
  CRC_OUT=$(bash "$CRC_GATE" "$PROJ" "$REPORT_PATH" "--required=$MODE" "--phase=$PHASE_TAG" 2>&1)
  CRC_RC=$?
  set -e 2>/dev/null || true
  if [ "$CRC_RC" != "0" ]; then
    echo "STATUS=RED"
    echo "FAIL: reviewer coverage check did not pass (rc=$CRC_RC, mode=$MODE, phase=$PHASE_TAG):"
    printf '%s\n' "$CRC_OUT" | sed 's/^/  | /'
    if [ "$CRC_RC" = "2" ]; then
      echo "NOTE: a coverage YELLOW (missing provenance) maps to RED pre-execution — scripts without review provenance never execute."
    fi
    exit 1
  fi
else
  echo "STATUS=RED"
  echo "FAIL: code-review-coverage-check.sh not found next to this gate — cannot verify reviewer coverage."
  exit 1
fi

# ── R6b: fix receipts are necessary, NOT sufficient (DC-03) ───────────────
# A fix-round manifest lists fixed_finding_ids, but the fixer never verifies
# itself: closure needs an independent VERIFIED line in the findings ledger.
# When the ledger's LATEST state for a listed id is still FIXED, surface it as
# YELLOW — the receipt is real and the bytes are bound (execution may proceed
# under it), but phase-verify 5.5 is the only closure authority and it will
# want the VERIFIED lines (real-project eval, ses 2026-08-22).
LEDGER="$PROJ/logs/findings.ndjson"
FIXED_IDS=$(jq -r '.fixed_finding_ids[]? // empty' "$MANIFEST" 2>/dev/null || true)
if [ -n "$FIXED_IDS" ] && [ -f "$LEDGER" ]; then
  UNVERIFIED=""
  while IFS= read -r _fid; do
    [ -n "$_fid" ] || continue
    _st=$(jq -r --arg id "$_fid" 'select(.id == $id) | .status' "$LEDGER" 2>/dev/null | tail -1 || true)
    [ "$_st" = "FIXED" ] && UNVERIFIED="${UNVERIFIED}${_fid} "
  done <<EOF_FIDS
$FIXED_IDS
EOF_FIDS
  if [ -n "$UNVERIFIED" ]; then
    echo "STATUS=YELLOW"
    echo "WARN: fix receipt $REVIEW_ID is hash-bound and clean, but the findings ledger's"
    echo "      latest state for the following fixed_finding_ids is FIXED with no VERIFIED"
    echo "      line: ${UNVERIFIED}"
    echo "      DC-03: the fixer never verifies itself — dispatch the independent re-review"
    echo "      to file VERIFIED lines. This receipt is necessary but not sufficient;"
    echo "      phase-verify.sh 5.5 is the closure authority."
    exit 2
  fi
fi

echo "STATUS=GREEN"
echo "PASS: review $REVIEW_ID is hash-bound to $N_SCRIPTS script(s), verdict clean, coverage verified (mode=$MODE, phase=$PHASE_TAG)."
echo "Reviewed files may now be executed DIRECTLY (invoke the script files; do not re-type code inline)."
exit 0
