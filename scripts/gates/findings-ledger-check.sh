#!/usr/bin/env bash
# findings-ledger-check.sh — validates logs/findings.ndjson (RCA Round 1 #3).
#
# The ledger is the machine-readable INDEX of review findings kept beside the
# full reports (protocol: skills/_shared/findings-ledger.md). This gate keeps
# it trustworthy: an index that can drift silently is worse than none.
#
# CHECKS
#   R1  every line parses as a JSON object                       -> RED on miss
#   R2  required keys present: id, ts, status, locus, report     -> RED on miss
#   R3  status in the closed vocabulary
#       OPEN|FIXED|VERIFIED|ACCEPTED|ESCALATED|WITHDRAWN         -> RED on miss
#   R4  verify.mode=check requires verify.cmd AND verify.expect  -> RED on miss
#   R5  a VERIFIED line requires a PRIOR FIXED (or OPEN) line
#       for the same id — verified-out-of-nowhere is the
#       fixer-verifies-itself smell (DC-03)                      -> YELLOW
#   R5b an id with a closing status (FIXED/ESCALATED/ACCEPTED)
#       but NO OPEN line ever — an orphan close that supersedes
#       nothing (P1-D: a close MUST reuse the exact id it
#       closes); discharged when its latest state is WITHDRAWN   -> YELLOW
#       (RED under SCHOLAR_LEDGER_CLOSE_ENFORCE=1)
#   Y1  recurrence: OPEN lines sharing a `class` across >= 2
#       distinct loci, with no `invariant` line for that class   -> YELLOW
#       ("promote to project invariant with a standing check")
#
# INERT when the ledger does not exist — adoption is per-project; absence is
# not an error, silence about malformed content would be.
#
# Exit: 0 GREEN | 1 RED | 2 YELLOW | 3 INERT
# Usage: findings-ledger-check.sh <project_dir>
set -uo pipefail

PROJ="${1:-}"
if [ -z "$PROJ" ] || [ ! -d "$PROJ" ]; then
  echo "GATE=findings-ledger-check"
  echo "STATUS=RED"
  echo "REASON=usage: findings-ledger-check.sh <project_dir> (got '${PROJ}')"
  exit 1
fi

LEDGER="$PROJ/logs/findings.ndjson"
echo "GATE=findings-ledger-check"
echo "PROJECT=$PROJ"

if [ ! -f "$LEDGER" ]; then
  # Demand-side signal (2026-08-22 verification round): INERT-when-reports-
  # exist is indistinguishable from "nothing to index" — exactly the silence
  # the RCA's gate-layer critique condemns (§2 #10). When iteration-numbered
  # review reports with heading-anchored CRIT ids are on disk, the ledger is
  # OWED: YELLOW, not INERT. Absence with no such reports stays INERT.
  _owed=$(grep -lE '^###.*CRIT-[A-Z0-9]+-[0-9]+' \
      "$PROJ"/reviews/phase-5.5-iter*-*.md "$PROJ"/reports/code-review-*-iter*.md \
      2>/dev/null | head -1 || true)
  if [ -n "$_owed" ]; then
    echo "STATUS=YELLOW"
    echo "REASON=review reports carry CRIT-* finding ids (e.g. $(basename "$_owed")) but logs/findings.ndjson does not exist — file one OPEN (or ACCEPTED, if logs/gate-acceptances.md already covers it) line per blocking finding (_shared/findings-ledger.md); the fix seam (emit-fix-brief.sh) refuses to run without the ledger"
    exit 2
  fi
  echo "STATUS=INERT"
  echo "REASON=no logs/findings.ndjson — ledger not adopted in this project"
  exit 3
fi

_OUT=$(python3 - "$LEDGER" <<'PY'
import json, os, sys
from collections import defaultdict

path = sys.argv[1]
VOCAB = {"OPEN", "FIXED", "VERIFIED", "ACCEPTED", "ESCALATED", "WITHDRAWN"}
red, yellow = [], []
seen_status = defaultdict(list)          # id -> [status, ...] in file order
last_open_verify = {}                    # id -> verify.cmd of the latest OPEN line
class_loci = defaultdict(set)            # class -> {locus, ...} from OPEN lines
class_open_ids = {}                      # class -> {id: locus} for latest-state replay
invariant_classes = set()
n = 0

with open(path, encoding="utf-8") as fh:
    for lineno, line in enumerate(fh, 1):
        line = line.strip()
        if not line:
            continue
        n += 1
        try:
            rec = json.loads(line)
        except ValueError as e:
            red.append("R1 line %d: unparseable JSON (%s)" % (lineno, e)); continue
        if not isinstance(rec, dict):
            red.append("R1 line %d: not a JSON object" % lineno); continue
        missing = [k for k in ("id", "ts", "status", "locus", "report") if not rec.get(k)]
        if missing:
            red.append("R2 line %d: missing required key(s) %s" % (lineno, ",".join(missing))); continue
        st = rec["status"]
        if st not in VOCAB:
            red.append("R3 line %d (%s): status '%s' outside closed vocabulary" % (lineno, rec["id"], st)); continue
        v = rec.get("verify") or {}
        if v.get("mode") == "check" and (not v.get("cmd") or not v.get("expect")):
            red.append("R4 line %d (%s): verify.mode=check requires cmd AND expect" % (lineno, rec["id"]))
        # R7 (2026-08-28): what KIND of claim is this, and was its mechanism
        # ever executed? Across one 5-round stretch ~half of filed findings were
        # right about the symptom and wrong about the mechanism, every time the
        # mechanism had been read rather than run. verify{} tests whether the
        # FIX holds; nothing recorded whether the DIAGNOSIS was ever true.
        # All three fields are OPTIONAL so existing ledgers stay valid — but a
        # claim that declares itself reproduced must carry the command, or the
        # label is a declaration rather than evidence.
        ck = rec.get("claim_kind")
        if ck is not None and ck not in ("observation", "mechanism", "absence"):
            red.append("R7 line %d (%s): claim_kind '%s' outside vocabulary "
                       "(observation|mechanism|absence)" % (lineno, rec["id"], ck))
        ms = rec.get("mechanism_status")
        if ms is not None and ms not in ("reproduced", "hypothesis"):
            red.append("R7 line %d (%s): mechanism_status '%s' outside vocabulary "
                       "(reproduced|hypothesis)" % (lineno, rec["id"], ms))
        if (ms == "reproduced" or ck == "absence") and not rec.get("repro_cmd"):
            red.append("R7 line %d (%s): %s requires repro_cmd — a claim asserted "
                       "as established must carry the command that established it"
                       % (lineno, rec["id"],
                          "mechanism_status=reproduced" if ms == "reproduced"
                          else "claim_kind=absence"))
        if ms is not None and ck is not None and ck != "mechanism":
            red.append("R7 line %d (%s): mechanism_status is meaningful only for "
                       "claim_kind=mechanism (got claim_kind=%s)" % (lineno, rec["id"], ck))
        # Y2 (real-project eval finding 10, ses 2026-08-22): the fixer can
        # rewrite the reviewer's verify contract unflagged — a FIXED line
        # whose verify.cmd differs from the latest OPEN line's is graded
        # against a DIFFERENT check than the reviewer specified. Nothing
        # distinguishes an honest correction from a self-serving weakening,
        # so the drift is surfaced (YELLOW) for the independent re-reviewer
        # to adjudicate; only the reviewer or the PI may amend the contract.
        if st == "FIXED" and v.get("cmd"):
            prev_open = last_open_verify.get(rec["id"])
            if prev_open and prev_open != v.get("cmd"):
                yellow.append("Y2 line %d (%s): FIXED line's verify.cmd differs from the reviewer's OPEN-line contract — the re-reviewer must adjudicate the amendment (honest correction vs weakened check); note it in the re-review" % (lineno, rec["id"]))
        if st == "OPEN" and v.get("cmd"):
            last_open_verify[rec["id"]] = v.get("cmd")
        # Y3 (R3 verification round, 2026-08-22): a locus with no path
        # separator and no extension is unattributable — fix-induced-check
        # classifies it UNKNOWN, which converts the >=50% HALT-ESCALATE into
        # a warning. Flag it AT FILING TIME, before it can launder the next
        # round's attribution. Grammar: path[:anchor] (findings-ledger.md).
        if st == "OPEN" and not rec.get("invariant") and rec.get("locus") != "project-wide":
            _lf = str(rec.get("locus") or "").split(":", 1)[0].strip()
            if _lf and ("/" not in _lf) and ("." not in _lf):
                yellow.append("Y3 line %d (%s): locus '%s' names no file (no / or .) — unattributable for fix-induced lineage; use path[:anchor] per findings-ledger.md" % (lineno, rec["id"], rec.get("locus")))
        if st == "VERIFIED" and not any(s in ("FIXED", "OPEN") for s in seen_status[rec["id"]]):
            yellow.append("R5 line %d (%s): VERIFIED with no prior FIXED/OPEN line — who verified what?" % (lineno, rec["id"]))
        # R5b (handoff 2026-08-25 P1-D): a CLOSING line (FIXED/ESCALATED/
        # ACCEPTED) whose id has NO prior OPEN line supersedes nothing —
        # every replay consumer keys on the literal id string. The measured
        # instance: 36 closes filed under `<id>-FIXED` suffixes left the
        # ledger reporting ~75% more OPEN RED than was true, untrustworthy
        # in BOTH directions (a real close hidden; an invented one equally
        # invisible). Verified 2026-08-25: 36/36 suffixed ids had their base
        # id present as a separate finding, plus 4 ESCALATED lines orphaned
        # the same way via an undocumented answers_finding_id convention.
        # WITHDRAWN is exempt as a FIRST line (withdrawing an id that was
        # never opened asserts nothing), and an orphan whose LATEST state is
        # WITHDRAWN is discharged — that is the sanctioned repair for a
        # mis-filed close (append the proper close under the ORIGINAL id +
        # a WITHDRAWN line under the orphan id).
        seen_status[rec["id"]].append(st)
        if rec.get("invariant") and rec.get("class"):
            invariant_classes.add(rec["class"])
        elif st == "OPEN" and rec.get("class"):
            class_loci[rec["class"]].add(rec["locus"])
            class_open_ids.setdefault(rec["class"], {})[rec["id"]] = rec["locus"]

for cls, loci in sorted(class_loci.items()):
    # RF8 (R3 eval rehearsal): recurrence is about CURRENTLY-open instances —
    # replay each id to its latest state; ids since FIXED/VERIFIED/ACCEPTED/
    # WITHDRAWN no longer count toward the promote-to-invariant demand.
    live_loci = {loc for fid, loc in class_open_ids.get(cls, {}).items()
                 if seen_status.get(fid, ["OPEN"])[-1] == "OPEN"}
    if len(live_loci) >= 2 and cls not in invariant_classes:
        yellow.append("Y1 class '%s' recurs at %d distinct OPEN loci — promote to a project invariant with a standing check (file an invariant line; close by sweep, not per-instance fixes)" % (cls, len(live_loci)))

# R5b (handoff 2026-08-25 P1-D): orphan closes — an id whose lines include a
# closing status (FIXED/ESCALATED/ACCEPTED) but NEVER an OPEN line closes
# nothing: every replay consumer keys on the literal id string. Measured on
# the motivating run: 36 closes filed under `<id>-FIXED` suffixes (all 36
# base ids existed as separate findings) plus 4 ESCALATED lines orphaned via
# an undocumented answers_finding_id cross-reference — the ledger reported
# ~75% more OPEN RED than was true. An orphan whose LATEST state is WITHDRAWN
# is discharged: that is the sanctioned repair (append the proper close under
# the ORIGINAL id + a WITHDRAWN line under the orphan id). Advisory YELLOW by
# default during rollout — the flagship ledger carries 40 historical orphans
# awaiting the PI's repair decision — and RED under
# SCHOLAR_LEDGER_CLOSE_ENFORCE=1 (flip once the motivating project's ledger
# is repaired; the id-reuse rule itself is pinned in findings-ledger.md and
# the emit-fix-brief Rule 4 text either way).
_orphans = []
for _fid, _sts in sorted(seen_status.items()):
    if "OPEN" in _sts:
        continue
    if not any(s in ("FIXED", "ESCALATED", "ACCEPTED") for s in _sts):
        continue
    if _sts[-1] == "WITHDRAWN":
        continue
    _orphans.append(_fid)
if _orphans:
    _sink = red if os.environ.get("SCHOLAR_LEDGER_CLOSE_ENFORCE", "") == "1" else yellow
    _sink.append("R5b %d orphan close id(s) — closing status with NO prior OPEN line under the same id, so each supersedes NOTHING (a close MUST reuse the exact id it closes; findings-ledger.md P1-D). First few: %s. Repair: proper close under the ORIGINAL id + WITHDRAWN under the orphan id."
                 % (len(_orphans), ", ".join(_orphans[:5])))
print("ORPHAN_CLOSES=%d" % len(_orphans))

print("RECORDS=%d" % n)
print("IDS=%d" % len(seen_status))
for r in red:    print("RED\t" + r)
for y in yellow: print("YELLOW\t" + y)
PY
)
_PYRC=$?
if [ "$_PYRC" -ne 0 ]; then
  echo "STATUS=RED"
  echo "REASON=validator failed to run (python3 rc=$_PYRC)"
  exit 1
fi

printf '%s\n' "$_OUT" | grep -E '^(RECORDS|IDS|ORPHAN_CLOSES)=' || true
RED_N=$(printf '%s\n' "$_OUT" | grep -c '^RED	' || true)
YEL_N=$(printf '%s\n' "$_OUT" | grep -c '^YELLOW	' || true)
printf '%s\n' "$_OUT" | grep -E '^(RED|YELLOW)	' | sed 's/^RED\t/  RED: /; s/^YELLOW\t/  YELLOW: /' || true

if [ "${RED_N:-0}" -gt 0 ]; then
  echo "STATUS=RED"
  echo "REASON=$RED_N malformed ledger line(s) — an index that can drift silently is worse than none"
  exit 1
fi
if [ "${YEL_N:-0}" -gt 0 ]; then
  echo "STATUS=YELLOW"
  echo "REASON=$YEL_N advisory finding(s) — see YELLOW lines above"
  exit 2
fi
echo "STATUS=GREEN"
exit 0
