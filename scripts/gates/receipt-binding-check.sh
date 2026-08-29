#!/usr/bin/env bash
# receipt-binding-check.sh — audits the pre-dispatch verification chain
# (system-fix plan v2, P0.3 + S1.1, 2026-08-23).
#
# CONTRACT
#   For every dispatch-manifest row that carries a `brief`, a briefed
#   dispatch is only VERIFIED provenance when a pre-dispatch verification
#   receipt binds to the same brief content and dispatch nonce:
#     - the row's `receipt` file exists at briefs/receipts/<nonce>.json,
#     - the receipt's status is GREEN,
#     - receipt.nonce == row.dispatch_nonce == receipt filename stem,
#     - receipt.brief_sha256 == row.brief_sha256 (the brief the agent was
#       dispatched on is the brief that was verified — not a re-emitted or
#       mutated one),
#     - no two rows share a nonce (a receipt attests ONE dispatch).
#
#   This closes handoff P1-3's second half: recording a `--brief` row used
#   to make "what the agent was told" LOOK verifiable while nothing ever
#   verified it — the manifest stored a hash no reviewer seat could check.
#
# ROLLOUT (compatibility-first, plan §Sequencing)
#   Briefed rows WITHOUT receipt/nonce fields are LEGACY: YELLOW by default
#   (advisory, counted and named), RED when SCHOLAR_RECEIPTS_ENFORCE=1.
#   Flip condition: enforce once every gated-dispatch doc site instructs the
#   receipt step (SKILL.md §Briefing packets, phase-lit-review.md MAP) and
#   one full project run has produced receipted rows end-to-end.
#   Structural violations on rows that DO carry receipt fields (missing
#   file, RED receipt, sha/nonce mismatch, reused nonce) are ALWAYS RED —
#   a wrong attestation is worse than an absent one.
#
# USAGE
#   receipt-binding-check.sh <project_dir> [--phase P]
#
# EXIT: 0 GREEN | 1 RED | 2 YELLOW (legacy-unreceipted rows or no manifest)
#
# FIXTURES: tests/smoke/test-verification-receipt.sh
set -uo pipefail

PROJ="${1:-}"
PHASE=""
shift $(( $# > 0 ? 1 : 0 ))
while [ $# -gt 0 ]; do
  case "$1" in
    --phase) PHASE="${2:-}"; shift 2 ;;
    *) echo "Usage: receipt-binding-check.sh <project_dir> [--phase P]" >&2; exit 2 ;;
  esac
done
if [ -z "$PROJ" ] || [ ! -d "$PROJ" ]; then
  echo "Usage: receipt-binding-check.sh <project_dir> [--phase P]" >&2
  exit 2
fi

MANIFEST="$PROJ/logs/dispatch-manifest.jsonl"
echo "GATE=receipt-binding-check"
echo "PROJECT=$PROJ"
if [ ! -f "$MANIFEST" ]; then
  echo "STATUS=YELLOW"
  echo "REASON=no_manifest"
  exit 2
fi

PROJ="$PROJ" MANIFEST="$MANIFEST" PHASE="$PHASE" \
ENFORCE="${SCHOLAR_RECEIPTS_ENFORCE:-0}" python3 - <<'PY'
import hashlib, json, os, sys

proj = os.environ["PROJ"]; phase = os.environ["PHASE"]
enforce = os.environ["ENFORCE"] == "1"

def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for c in iter(lambda: f.read(65536), b""):
            h.update(c)
    return h.hexdigest()

def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for c in iter(lambda: f.read(65536), b""):
            h.update(c)
    return h.hexdigest()

# Parse ALL rows first: nonce-reuse bookkeeping must be GLOBAL (independent
# review 2026-08-23, C2 — a phase-scoped reuse check misses one nonce riding
# two rows in different phases), while the per-row structural checks below
# honor the --phase filter.
rows = []
for ln, line in enumerate(open(os.environ["MANIFEST"], encoding="utf-8", errors="replace"), 1):
    line = line.strip()
    if not line:
        continue
    try:
        row = json.loads(line)
    except ValueError:
        continue   # malformed rows are manifest-binding-check's problem
    rows.append((ln, row))

red, legacy = [], []
nonce_lines = {}
for ln, row in rows:
    n = row.get("dispatch_nonce")
    if n:
        nonce_lines.setdefault(n, []).append(ln)
for n, lns in nonce_lines.items():
    if len(lns) > 1:
        red.append("nonce %s REUSED on manifest lines %s — a receipt attests ONE dispatch "
                   "(cross-phase reuse is still reuse)" % (n, lns))

proj_canon = os.path.realpath(proj)
receipts_root = os.path.join(proj_canon, "briefs", "receipts")
def phase_match(rp):
    # Exact match, plus canonical sub-phases (10.5 also covers 10.5a/10.5b —
    # the same tolerance manifest-binding-check's own regex applies).
    if not phase:
        return True
    rp = str(rp)
    return rp == phase or (rp.startswith(phase) and len(rp) == len(phase) + 1
                           and rp[-1] in "ab")

briefed = receipted = 0
for ln, row in rows:
    if not phase_match(row.get("phase")):
        continue
    if not row.get("brief"):
        continue
    briefed += 1
    nonce = row.get("dispatch_nonce")
    rcpt = row.get("receipt")
    if not nonce or not rcpt:
        legacy.append("line %d (agentId %s): briefed row has no receipt/nonce"
                      % (ln, row.get("agentId")))
        continue
    receipted += 1
    rp = rcpt if os.path.isabs(rcpt) else os.path.join(proj, rcpt)
    # C3 (independent review 2026-08-23): CONTAINMENT before content — a row
    # naming a receipt outside THIS project's briefs/receipts/ is not
    # provenance, wherever that file points.
    rp_canon = os.path.realpath(rp)
    if os.path.dirname(rp_canon) != receipts_root:
        red.append("line %d: receipt %s resolves outside %s — out-of-project receipts "
                   "are not provenance" % (ln, rcpt, receipts_root)); continue
    if not os.path.isfile(rp):
        red.append("line %d: receipt %s MISSING" % (ln, rcpt)); continue
    # C1 (independent review 2026-08-23): re-hash the receipt FILE and compare
    # to the hash recorded at dispatch time — self-declared JSON fields alone
    # let a copied receipt with an edited nonce pass. A receipted row without
    # receipt_sha256 is structural RED, not legacy: the field ships with
    # --receipt itself, so its absence means a hand-written row.
    row_rsha = row.get("receipt_sha256")
    if not row_rsha or row_rsha == "null":
        red.append("line %d: receipted row carries no receipt_sha256 — the row was not "
                   "written by emit-task-dispatch --receipt" % ln); continue
    if sha256_file(rp) != row_rsha:
        red.append("line %d: receipt %s on disk hashes differently from the recorded "
                   "receipt_sha256 — the receipt changed (or was swapped) after the "
                   "dispatch was recorded" % (ln, rcpt)); continue
    stem = os.path.basename(rp)
    stem = stem[:-5] if stem.endswith(".json") else stem
    try:
        r = json.load(open(rp, encoding="utf-8"))
    except (OSError, ValueError):
        red.append("line %d: receipt %s unreadable as JSON" % (ln, rcpt)); continue
    if r.get("nonce") != nonce or stem != nonce:
        red.append("line %d: nonce mismatch (row %s, receipt %s, filename %s)"
                   % (ln, nonce, r.get("nonce"), stem)); continue
    if r.get("status") != "GREEN":
        red.append("line %d: receipt %s status is %r — dispatched on a non-GREEN verification"
                   % (ln, rcpt, r.get("status"))); continue
    if r.get("brief_sha256") != row.get("brief_sha256"):
        red.append("line %d: receipt attests brief sha %s… but the row dispatched sha %s… — "
                   "the agent was briefed on content the receipt never verified"
                   % (ln, (r.get("brief_sha256") or "")[:12], (row.get("brief_sha256") or "")[:12]))
        continue

print("BRIEFED_ROWS=%d" % briefed)
print("RECEIPTED_ROWS=%d" % receipted)
print("LEGACY_UNRECEIPTED=%d" % len(legacy))
for msg in red:
    print("  FAIL: %s" % msg)
for msg in legacy:
    print("  %s: %s" % ("FAIL" if enforce else "WARN", msg))
if red or (enforce and legacy):
    print("STATUS=RED")
    sys.exit(1)
if legacy:
    print("STATUS=YELLOW")
    print("REASON=legacy-unreceipted-rows (advisory; RED under SCHOLAR_RECEIPTS_ENFORCE=1)")
    sys.exit(2)
print("STATUS=GREEN")
sys.exit(0)
PY
exit $?
