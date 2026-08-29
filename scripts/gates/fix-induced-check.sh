#!/usr/bin/env bash
# fix-induced-check.sh — the ≥50%-fix-induced escalation rule (RCA Round 3
# #11, 2026-08-22; hardened same day by the R3 verification round).
#
# WHY
#   F-96 (cohab): a fix round's blast radius is the next review's finding
#   population. ses: 4 of 5 iteration-3 CRITICALs were CREATED by
#   iteration-2 fixes. A loop whose new findings are mostly self-inflicted
#   is not converging — it is churning; another unreviewed fix round is the
#   wrong move regardless of what the raw counts say.
#
# LINEAGE (all from disk; never from recollection)
#   - logs/findings.ndjson — finding INSTANCES: the first OPEN line per id,
#     PLUS every re-OPEN (an OPEN whose id's prior latest status was
#     FIXED/VERIFIED — regressions are new instances at the re-OPEN's iter;
#     without this, pure regression churn read as INERT).
#   - code-review/reviewed-scripts-fix-*.json receipts — write-sets:
#     scripts[] refined to the CHANGED set when supersedes_review_id names
#     a prior manifest. A receipt maps to the iteration it answered by the
#     majority first-OPEN iter of its fixed_finding_ids. TIME DISCIPLINE:
#     a receipt whose ts (field, else file mtime) post-dates the earliest
#     OPEN ts of the latest iteration cannot have caused those findings and
#     is excluded from that attribution (late cleanup rounds false-REDed).
#   - affected_consumers[] edges on the fixed findings' ledger lines —
#     unioned into the write-set (consumer-file damage diluted the ratio
#     GREEN before this; the ses 3→9 return-arity incident's exact shape).
#   - logs/surface-leases.ndjson write events falling between the previous
#     iteration's earliest OPEN ts and the latest iteration's earliest OPEN
#     ts (the plan's "leased write sets"; skipped when timestamps do not
#     parse).
#
# ATTRIBUTION of a latest-iteration instance:
#   induced   — a re-OPEN of an id some receipt claims in fixed_finding_ids
#               (direct regression), OR its locus FILE is in the write-set
#               (direct | consumer-edge | lease basis, reported per file)
#   not-induced — locus file VALID (exists in the project or named by a
#               receipt) and not in the write-set
#   UNKNOWN   — locus has no parseable/valid file, or no write-set exists
#               for the preceding round. Excluded from BOTH sides of the
#               ratio — the rule must not fire on guesses. (Deliberate
#               strengthening of the plan's "excluded from the numerator":
#               numerator-only exclusion would make unattributable findings
#               COUNT AGAINST escalation.)
#
# KNOWN LIMITS (documented, not silent): a fix whose damage lands in a file
# with NO ledger edge, NO lease, and NO receipt entry attributes NOT_INDUCED
# — file affected_consumers[] edges (findings-ledger.md) to close it; and
# non-script surfaces appear only via lease events.
#
# VERDICT (latest iteration with new instances):
#   RED    — attributable >= 2 AND induced >= 2 AND induced/attributable
#            >= 0.5. ESCALATE to the PI; another unreviewed fix round is
#            forbidden.
#   YELLOW — UNKNOWN > attributable, or a lone induced instance (signal,
#            not proof — never RED on one data point).
#   GREEN  — otherwise.
#   INERT  — no ledger, no instances at iteration >= 2, or no mappable fix
#            receipts.
#
# Exit: 0 GREEN | 1 RED | 2 YELLOW | 3 INERT
# Usage: fix-induced-check.sh <project_dir>
# FIXTURES: tests/smoke/test-fix-induced-check.sh
set -uo pipefail

PROJ="${1:-}"
if [ -z "$PROJ" ] || [ ! -d "$PROJ" ]; then
  echo "GATE=fix-induced-check"
  echo "STATUS=RED"
  echo "REASON=usage: fix-induced-check.sh <project_dir> (got '${PROJ}')"
  exit 1
fi

echo "GATE=fix-induced-check"
echo "PROJECT=$PROJ"

LEDGER="$PROJ/logs/findings.ndjson"
if [ ! -f "$LEDGER" ]; then
  echo "STATUS=INERT"
  echo "REASON=no logs/findings.ndjson — lineage not adopted; nothing to attribute"
  exit 3
fi

PROJ="$PROJ" python3 - <<'PY_FI'
import datetime, glob, json, os, sys

proj = os.environ["PROJ"]

def strip_dot(p):
    while p.startswith("./"):
        p = p[2:]
    return p

def parse_ts(s):
    if not isinstance(s, str) or not s:
        return None
    for fmt in ("%Y-%m-%dT%H:%M:%SZ", "%Y-%m-%dT%H:%M:%S"):
        try:
            return datetime.datetime.strptime(s, fmt)
        except ValueError:
            continue
    return None

# ── Ledger pass: instances + per-id history ──
first_open = {}        # id -> {"iter", "file_raw", "ts"}
instances = []         # each: {"id", "iter", "file_raw", "ts", "reopen": bool}
last_status = {}
consumers = {}         # id -> [affected_consumers]
iter_min_open_ts = {}  # iter -> earliest OPEN ts (parsed)

for line in open(os.path.join(proj, "logs", "findings.ndjson"), encoding="utf-8", errors="replace"):
    line = line.strip()
    if not line:
        continue
    try:
        r = json.loads(line)
    except ValueError:
        continue
    if not isinstance(r, dict):
        continue
    fid = r.get("id")
    st = r.get("status")
    if not fid or not st:
        continue
    # RF3 (R3 eval rehearsal, 2026-08-22): pre-mortem findings (PM35-* per
    # premortem-protocol Step P3, or any line tagged loop: premortem) live
    # in a DIFFERENT loop with its own iteration numbers. Mixing them in
    # let a PM35 line filed at "iter 4" start the code-review latest
    # iteration hours early, so the time discipline excluded the round's
    # legitimate receipt and the governor read INERT on exactly the kind
    # of project it was built for.
    if fid.startswith("PM35-") or r.get("loop") == "premortem":
        continue
    if st == "OPEN":
        it = r.get("iter")
        try:
            it = int(it)
        except (TypeError, ValueError):
            it = None
        ts = parse_ts(r.get("ts"))
        rec = {"id": fid, "iter": it, "locus": r.get("locus"), "ts": ts,
               "reopen": last_status.get(fid) in ("FIXED", "VERIFIED")}
        if fid not in first_open:
            first_open[fid] = rec
            instances.append(rec)
        elif rec["reopen"]:
            instances.append(rec)
        if isinstance(r.get("affected_consumers"), list):
            consumers.setdefault(fid, []).extend(
                strip_dot(c) for c in r["affected_consumers"] if isinstance(c, str))
        if it is not None and ts is not None:
            if it not in iter_min_open_ts or ts < iter_min_open_ts[it]:
                iter_min_open_ts[it] = ts
    else:
        if isinstance(r.get("affected_consumers"), list):
            consumers.setdefault(fid, []).extend(
                strip_dot(c) for c in r["affected_consumers"] if isinstance(c, str))
    last_status[fid] = st

iters = sorted(i["iter"] for i in instances if i["iter"] is not None)
if not iters or max(iters) < 2:
    print("STATUS=INERT")
    print("REASON=no finding instances at iteration >= 2 — no fix round has been reviewed yet")
    sys.exit(3)
latest = max(iters)
latest_min_ts = iter_min_open_ts.get(latest)

# ── Receipts → per-answered-iteration write-sets + claimed-id sets ──
by_id = {}
for rp in glob.glob(os.path.join(proj, "code-review", "reviewed-scripts-*.json")):
    try:
        m = json.load(open(rp, encoding="utf-8"))
        if isinstance(m, dict) and m.get("review_id"):
            by_id[m["review_id"]] = m
    except (OSError, ValueError):
        continue

write_sets = {}     # answered iter -> {file: basis}
claimed_ids = {}    # answered iter -> set of fixed ids
receipt_paths = set()
excluded_late = []

for rp in sorted(glob.glob(os.path.join(proj, "code-review", "reviewed-scripts-fix-*.json"))):
    try:
        m = json.load(open(rp, encoding="utf-8"))
    except (OSError, ValueError):
        continue
    if not isinstance(m, dict):
        continue
    fids = [f for f in (m.get("fixed_finding_ids") or []) if isinstance(f, str)]
    its = [first_open[f]["iter"] for f in fids if f in first_open and first_open[f]["iter"] is not None]
    if not its:
        continue
    answered = max(sorted(its), key=lambda x: (its.count(x), x))
    # time discipline (F6): a receipt written AFTER the latest iteration's
    # findings were filed cannot have caused them.
    rts = parse_ts(m.get("ts"))
    if rts is None:
        try:
            rts = datetime.datetime.utcfromtimestamp(os.path.getmtime(rp))
        except OSError:
            rts = None
    if answered == latest - 1 and rts is not None and latest_min_ts is not None and rts > latest_min_ts:
        excluded_late.append(os.path.basename(rp))
        continue
    paths = {strip_dot(s.get("path") or ""): s.get("sha256")
             for s in (m.get("scripts") or []) if isinstance(s, dict) and s.get("path")}
    receipt_paths.update(paths)
    prior = by_id.get(m.get("supersedes_review_id") or "")
    changed = set(paths)
    if prior:
        prior_sha = {strip_dot(s.get("path") or ""): s.get("sha256")
                     for s in (prior.get("scripts") or []) if isinstance(s, dict)}
        c2 = {p for p, sha in paths.items() if prior_sha.get(p) != sha}
        if c2:
            changed = c2
    ws = write_sets.setdefault(answered, {})
    for p in changed:
        ws.setdefault(p, "direct")
    for f in fids:
        for c in consumers.get(f, []):
            ws.setdefault(c, "consumer-edge")
    claimed_ids.setdefault(answered, set()).update(fids)

# lease write events in the inter-review interval (prev iter open -> latest open)
prev_min_ts = iter_min_open_ts.get(latest - 1)
lp = os.path.join(proj, "logs", "surface-leases.ndjson")
if os.path.isfile(lp) and prev_min_ts is not None and latest_min_ts is not None:
    for line in open(lp, encoding="utf-8", errors="replace"):
        try:
            e = json.loads(line)
        except ValueError:
            continue
        if not isinstance(e, dict) or e.get("event") != "write" or e.get("violation"):
            continue
        ets = parse_ts(e.get("ts"))
        pth = e.get("path")
        if ets is None or not isinstance(pth, str):
            continue
        if prev_min_ts <= ets <= latest_min_ts:
            write_sets.setdefault(latest - 1, {}).setdefault(strip_dot(pth), "lease")

if not write_sets:
    for rp in excluded_late:
        print("  NOTE: receipt %s post-dates the latest iteration's findings — excluded from attribution (time discipline)" % rp)
    print("STATUS=INERT")
    if excluded_late:
        print("REASON=every mappable fix receipt was excluded by time discipline (see NOTEs) — if a receipt is genuinely the round that preceded the latest review, give it a 'ts' field (ISO-8601, the moment the fixes landed); file mtimes are unreliable after any touch")
    else:
        print("REASON=no fix receipts (code-review/reviewed-scripts-fix-*.json) with ledger-mapped rounds — no write-set lineage to attribute against")
    sys.exit(3)

def locus_file(locus):
    # F7: `path:line`, `path line 44`, `path#L99` all reduce to path; a
    # candidate is only a FILE if it exists in the project or a receipt
    # names it — otherwise UNKNOWN, never a phantom NOT_INDUCED.
    if not isinstance(locus, str) or not locus:
        return None
    f = locus.split(":", 1)[0].strip()
    for sep in (" ", "\t", "#"):
        f = f.split(sep, 1)[0]
    f = strip_dot(f)
    if not f or (("/" not in f) and ("." not in f)):
        return None
    if os.path.exists(os.path.join(proj, f)) or f in receipt_paths:
        return f
    return None

ws = write_sets.get(latest - 1)
claimed = claimed_ids.get(latest - 1, set())
new_instances = [i for i in instances if i["iter"] == latest]
induced, not_induced, unknown = [], [], []
for inst in new_instances:
    if inst["reopen"] and inst["id"] in claimed:
        induced.append((inst["id"], "regression-reopen"))
        continue
    lf = locus_file(inst["locus"])
    if ws is None or lf is None:
        unknown.append(inst["id"])
    elif lf in ws:
        induced.append((inst["id"], "%s (%s)" % (lf, ws[lf])))
    else:
        not_induced.append(inst["id"])

n_att = len(induced) + len(not_induced)
print("LATEST_ITER=%d" % latest)
print("NEW_FINDINGS=%d" % len(new_instances))
print("FIX_INDUCED=%d" % len(induced))
print("NOT_INDUCED=%d" % len(not_induced))
print("UNKNOWN=%d (excluded from the ratio)" % len(unknown))
for fid, basis in induced:
    print("  INDUCED: %s via %s [round answering iter %d]" % (fid, basis, latest - 1))
for rp in excluded_late:
    print("  NOTE: receipt %s post-dates the latest iteration's findings — excluded from attribution (time discipline)" % rp)

if n_att >= 2 and len(induced) >= 2 and len(induced) * 2 >= n_att:
    print("STATUS=RED")
    print("REASON=HALT-ESCALATE: %d of %d attributable new finding(s) at iteration %d trace to the preceding fix round (>=50%% fix-induced, F-96). The loop is churning, not converging — escalate to the PI (fix under a reviewed brief with NARROWED scope, accept-and-disclose, or stop); another unreviewed fix round is forbidden." % (len(induced), n_att, latest))
    sys.exit(1)
if len(unknown) > n_att or (len(induced) == 1 and n_att <= 2):
    print("STATUS=YELLOW")
    print("REASON=fix-induced lineage inconclusive at iteration %d (attributable=%d, induced=%d, unknown=%d) — file loci as path[:anchor], keep receipts complete, and record affected_consumers[] edges so the next round is attributable" % (latest, n_att, len(induced), len(unknown)))
    sys.exit(2)
print("STATUS=GREEN")
print("REASON=%d of %d attributable new finding(s) at iteration %d are fix-induced (< 50%% or < 2 induced); the loop's new findings are mostly independent of the last fix round" % (len(induced), n_att, latest))
PY_FI
