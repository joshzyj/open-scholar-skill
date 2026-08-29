#!/usr/bin/env bash
# emit-fix-brief.sh — mechanically generate a fix-agent brief (RCA Round 1 #1).
#
# WHY: fix briefs used to be written from orchestrator recollection inside a
# saturated context — cohab F-31 closed a finding that was not fixed
# ("WRONGLY CLOSED"), and the R10 proof showed a clean-context fixer WITHOUT
# the reviewer's reasoning ships broken fixes (an FE structure that absorbed
# its own design matrix). Delegation and briefing are ONE change: this script
# derives the brief entirely from disk state — the findings ledger, the
# reports, and the recorded SHAs — never from what the orchestrator remembers.
#
# SOURCES (all mechanical):
#   logs/findings.ndjson       — the OPEN findings in scope (id, locus, verify
#                                contract, report path, reviewed_at_sha)
#   the report files           — the fix agent reads each finding's FULL text
#                                at its evidence path; the brief never
#                                paraphrases a finding
#   current script SHA-256s    — drift since the reviewed SHA is FLAGGED; a
#                                drifted script means the review no longer
#                                describes the bytes on disk
#   logs/surface-leases.ndjson — write events since review, so the agent knows
#                                what moved and who moved it
#
# USAGE
#   emit-fix-brief.sh <proj> <round_id> [--ids id1,id2,...] [--phase 5.5]
#     --ids    restrict scope to these finding ids (default: every OPEN
#              finding in the ledger, optionally filtered by --phase)
#     --phase  ledger phase filter when --ids is not given
#
# OUTPUT: briefs/fix-<round_id>.md (path printed). Exit 0 on success,
#         1 when the scope resolves to zero findings, 2 usage.
set -uo pipefail

PROJ="${1:-}"; ROUND="${2:-}"
if [ -z "$PROJ" ] || [ ! -d "$PROJ" ] || [ -z "$ROUND" ]; then
  echo "usage: emit-fix-brief.sh <proj> <round_id> [--ids id1,id2,...] [--phase <p>]" >&2
  exit 2
fi
case "$ROUND" in
  */*) echo "emit-fix-brief: round_id must not contain '/' (got '$ROUND')" >&2; exit 2 ;;
esac
shift 2
IDS=""; PHASE_FILTER=""
while [ $# -gt 0 ]; do
  case "$1" in
    --ids) IDS="${2:-}"; shift 2 ;;
    --phase) PHASE_FILTER="${2:-}"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

LEDGER="$PROJ/logs/findings.ndjson"
[ -f "$LEDGER" ] || { echo "emit-fix-brief: no logs/findings.ndjson — file OPEN findings first (see _shared/findings-ledger.md)" >&2; exit 1; }

mkdir -p "$PROJ/briefs"
OUT="$PROJ/briefs/fix-${ROUND}.md"

PROJ="$PROJ" ROUND="$ROUND" IDS="$IDS" PHASE_FILTER="$PHASE_FILTER" OUT="$OUT" \
SKILL_DIR_HINT="${SCHOLAR_SKILL_DIR:-}" python3 - <<'PY'
import hashlib, json, os, re, sys
from datetime import datetime, timezone

proj = os.environ["PROJ"]; round_id = os.environ["ROUND"]
ids = set(x.strip() for x in os.environ["IDS"].split(",") if x.strip())
phase_filter = os.environ["PHASE_FILTER"]
out_path = os.environ["OUT"]

# Latest state per finding id (event-sourced replay).
latest = {}
with open(os.path.join(proj, "logs", "findings.ndjson"), encoding="utf-8") as fh:
    for line in fh:
        line = line.strip()
        if not line:
            continue
        try:
            rec = json.loads(line)
        except ValueError:
            continue
        if isinstance(rec, dict) and rec.get("id"):
            latest[rec["id"]] = {**latest.get(rec["id"], {}), **rec}

scope = []
for fid, rec in sorted(latest.items()):
    if rec.get("status") != "OPEN":
        continue
    if ids and fid not in ids:
        continue
    if not ids and phase_filter and str(rec.get("phase", "")) != phase_filter:
        continue
    scope.append(rec)

if not scope:
    sys.stderr.write("emit-fix-brief: scope resolved to zero OPEN findings\n")
    sys.exit(1)

def sha256_of(relpath):
    p = os.path.join(proj, relpath)
    if not os.path.isfile(p):
        return "absent"
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()

# Per-script drift table: reviewed_at_sha (from the ledger) vs bytes on disk.
scripts = {}
for rec in scope:
    locus = rec.get("locus", "")
    path = locus.split(":")[0] if locus else ""
    if not path:
        continue
    reviewed = (rec.get("reviewed_at_sha") or "").replace("sha256:", "")
    entry = scripts.setdefault(path, {"reviewed": set(), "current": sha256_of(path)})
    if reviewed:
        entry["reviewed"].add(reviewed)

# Ledger write events since review, so what moved is on the record.
lease_events = []
lease_path = os.path.join(proj, "logs", "surface-leases.ndjson")
if os.path.isfile(lease_path):
    with open(lease_path, encoding="utf-8") as fh:
        for line in fh:
            try:
                ev = json.loads(line)
            except ValueError:
                continue
            if ev.get("event") == "write" and ev.get("path") in scripts:
                lease_events.append(ev)

# The PI's standing repair-vs-disclose rule travels IN the brief (a Phase-1
# brief deliverable) — a fix agent must never have to infer it (RCA §4b
# precondition 3: clean context removes knowledge too).
#
# Provenance (handoff 2026-08-25 P2-A, measured cost: two completed fixes
# discarded): a brief generated minutes before a rule exists hands every agent
# the negation of that rule, indistinguishable from an empty field. Both
# branches now stamp WHAT was read and WHEN — the found rule carries its
# source's mtime+sha256; the ABSENT marker names every probed candidate with
# its state at generation time, so "no rule" and "no rule YET" are
# distinguishable after the fact.
def _prov_of(bp):
    try:
        mt = datetime.fromtimestamp(os.path.getmtime(bp), timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    except OSError:
        return "unreadable"
    h = hashlib.sha256()
    with open(bp, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return "mtime=%s sha256=%s…" % (mt, h.hexdigest()[:16])

PI_RULE_CANDS = ("design/project-brief.md", "logs/project-brief.md", "project-brief.md", "brief.md")

def pi_scoping_rule():
    """Returns (body, provenance_line) — body empty when no rule exists."""
    probed = []
    for cand in PI_RULE_CANDS:
        bp = os.path.join(proj, cand)
        if not os.path.isfile(bp):
            probed.append("%s: absent" % cand)
            continue
        try:
            btxt = open(bp, encoding="utf-8").read()
        except OSError:
            probed.append("%s: unreadable" % cand)
            continue
        m = re.search(r"^#{1,4}\s*PI scoping rule\s*$(.*?)(?=^#{1,4}\s|\Z)", btxt,
                      re.M | re.S | re.I)
        if m:
            body = m.group(1).strip()
            if body:
                return body, "_source: %s (%s)_" % (cand, _prov_of(bp))
        probed.append("%s: no 'PI scoping rule' section (%s)" % (cand, _prov_of(bp)))
    return "", "_probed: %s_" % "; ".join(probed)

GENERATED_AT = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

lines = []
w = lines.append
w("# Fix brief — round %s (mechanically generated by emit-fix-brief.sh)" % round_id)
w("")
w("generated: %s" % GENERATED_AT)
w("")
w("SCOPE: fix these %d finding(s); do NOT widen. Anything you notice outside this" % len(scope))
w("list goes into your return as a NEW proposed finding — never into the code.")
w("")
_rule, _rule_prov = pi_scoping_rule()
if _rule:
    w("## PI scoping rule (from the project brief — apply it to every judgment call)")
    w("")
    w(_rule_prov)
    w("")
    for _ln in _rule.split("\n"):
        w(_ln)
    w("")
else:
    # Real-project eval, ses 2026-08-22: no project brief carries a
    # "PI scoping rule" section, so the fix agent silently gets NO
    # repair-vs-disclose guidance — the exact inference burden the brief
    # exists to remove. Say so loudly in both channels.
    sys.stderr.write("emit-fix-brief: WARN no 'PI scoping rule' section found in any project brief "
                     "(design/project-brief.md, logs/project-brief.md, project-brief.md, brief.md) — "
                     "the fix agent gets the STOP-and-escalate default below. Adding the section is "
                     "the PI's/orchestrator's job before the NEXT round; the fix agent must not wait on it\n")
    w("## PI scoping rule")
    w("")
    w("(ABSENT at %s — no 'PI scoping rule' section existed in the project brief" % GENERATED_AT)
    w("WHEN THIS BRIEF WAS GENERATED. A rule written after this timestamp is not")
    w("negated by this marker — if you find a live rule in the project brief that")
    w("postdates it, the live rule governs; say so in your return. Otherwise do NOT")
    w("infer one: when a fix could either repair a number or disclose a limitation,")
    w("STOP and escalate that finding to the PI instead of choosing.)")
    w("")
    w(_rule_prov)
    w("")
w("## Rules")
w("")
skill_dir = os.environ.get("SKILL_DIR_HINT") or "<plugin>"
w("1. ONE writer per surface: acquire a lease on every file you will edit —")
w("   `bash \"%s/scripts/gates/surface-lease.sh\" \"$PROJ\" acquire <path> fix-%s` —" % (skill_dir, round_id))
w("   and `verify` each at start and again before you return. A verify failure is")
w("   a STOP-and-report, not a work-around (DC-07). RELEASE every lease at")
w("   return — `bash \"%s/scripts/gates/surface-lease.sh\" \"$PROJ\" release <path> fix-%s` —" % (skill_dir, round_id))
w("   an unreleased lease from a finished round is a manufactured zombie the")
w("   next check will flag (F-65/67/89).")
w("2. Read each finding's FULL text at its report path below. This brief does not")
w("   paraphrase findings; the report is the evidence.")
w("3. A script whose current SHA differs from its reviewed SHA has MOVED since")
w("   review — the finding's line anchors may be stale. Re-locate the defect")
w("   before editing; note the drift in your return.")
w("4. Return contract: (a) one FIXED line per addressed finding appended to")
w("   logs/findings.ndjson, filed under the EXACT id shown in this brief's")
w("   heading for that finding — never a new id, never a suffix (an id like")
w("   'CRIT-X-001-FIXED' supersedes NOTHING: every replay consumer keys on the")
w("   literal id string, so a suffixed close leaves the finding OPEN forever;")
w("   handoff 2026-08-25 P1-D, 36 measured orphan closes). With the check")
w("   re-run for check-verb findings;")
w("   (b) a code-review-manifest/v1 sidecar `code-review/reviewed-scripts-fix-%s.json`" % round_id)
w("   with per-script sha256 of the FIXED bytes, fixed_finding_ids,")
w("   remaining_blocking_count, and supersedes_review_id naming the review")
w("   round these fixes answer, and a `ts` field (ISO-8601, the moment the fixed")
w("   bytes landed) — fix-induced-check's time discipline runs on it, and file")
w("   mtimes are unreliable after any touch. supersedes_review_id must name a PRIOR")
w("   manifest's review_id; when the answered round produced only a report (no")
w("   manifest era), set it to null. The manifest's `report` field ALWAYS points at")
w("   the FIX LOG (logs/code-review-fixes-<date>.md) with this receipt's review_id")
w("   embedded there verbatim — pre-exec R1 pairs report<->manifest by that id;")
w("   pointing `report` at the answered round's REVIEW report fails the pairing.")
w("   The manifest must ALSO")
w("   cover completeness: every reviewable script in the scripts dir that you did")
w("   NOT touch goes into out_of_scope[] with a reason (R3 refuses any script in")
w("   neither list — an agent that hashes only its edited files REDs the gate);")
w("   (c) your fixes are NOT verified until an")
w("   independent diff-scoped re-review passes (DC-03 — the fixer never")
w("   verifies itself).")
w("")
w("## Findings in scope")
w("")
for rec in scope:
    w("### %s" % rec["id"])
    w("- locus: `%s`" % rec.get("locus", "?"))
    w("- evidence: `%s` (read the full finding there)" % rec.get("report", "?"))
    v = rec.get("verify") or {}
    if v.get("mode") == "check":
        w("- verify: check — run `%s`, expect: %s" % (v.get("cmd", "?"), v.get("expect", "?")))
    elif v.get("mode") == "review":
        w("- verify: independent re-review by %s" % v.get("reviewer", "a reviewer"))
    elif v.get("mode") == "escalate":
        w("- verify: ESCALATED to %s — do not fix without the recorded decision" % v.get("to", "the PI"))
    if rec.get("affected_consumers"):
        w("- affected consumers (check them after your fix): %s" % ", ".join(rec["affected_consumers"]))
    w("")
w("## Script state (reviewed SHA vs bytes on disk)")
w("")
w("| script | reviewed sha256 | current sha256 | drift |")
w("|---|---|---|---|")
for path, s in sorted(scripts.items()):
    revs = sorted(s["reviewed"])
    if not revs:
        drift = "UNKNOWN (no reviewed sha)"
    elif len(revs) > 1:
        drift = "**AMBIGUOUS — findings disagree on the reviewed sha; reconcile before editing**"
    elif revs[0] == s["current"]:
        drift = "no"
    else:
        drift = "**MOVED since review**"
    w("| `%s` | %s | %s | %s |" % (path, "<br>".join(revs) or "—", s["current"], drift))
w("")
if lease_events:
    w("## Recorded writes to these surfaces since review")
    w("")
    for ev in lease_events:
        w("- %s: `%s` written by %s%s" % (ev.get("ts", "?"), ev.get("path"), ev.get("holder"),
                                          " **(VIOLATION)**" if ev.get("violation") else ""))
    w("")
with open(out_path, "w", encoding="utf-8") as f:
    f.write("\n".join(lines) + "\n")
print(out_path)
PY
