#!/usr/bin/env bash
# emit-verification-receipt.sh — pre-dispatch brief verification receipt
# (system-fix plan v2, P0.3 + S1.1, 2026-08-23).
#
# WHY: every peer-reviewer-* seat is provisioned Read/Write/WebSearch, so the
# brief's old "run verify-brief.sh FIRST" directive was unrunnable for the
# agents briefs exist for (handoff P1-3) — the manifest recorded a brief hash
# NO dispatched reviewer could check, and brief verification never actually
# ran on any gated reviewer dispatch. Granting Bash was REJECTED (Codex
# REWORK): the data guard documents that it FAILS OPEN on ambiguity, so a
# shell trades a provenance gap for a confidentiality gap.
#
# Instead the ORCHESTRATOR verifies, immediately before dispatch:
#   1. emit-agent-brief.sh writes the packet and mints a dispatch_nonce;
#   2. THIS tool runs verify-brief.sh and writes a receipt bound to that
#      nonce — per-input path/sha/result, the brief's sha256, the verifier's
#      own sha256 (version-by-content), timestamp, verdict;
#   3. the Task prompt carries the nonce; the agent (tool-free) echoes it;
#   4. emit-task-dispatch.sh --receipt binds the receipt into the manifest
#      row; receipt-binding-check.sh audits the chain.
#
# A RED verification still WRITES the receipt (the failed check is audit
# evidence) but exits 1 — the orchestrator must NOT dispatch on a RED.
#
# USAGE
#   emit-verification-receipt.sh <proj> <brief-path-relative-or-absolute>
#
# OUTPUT: <proj>/briefs/receipts/<nonce>.json (REFUSES an existing receipt —
# one nonce, one verification); prints RECEIPT=, NONCE=, STATUS=.
# EXIT: 0 GREEN (dispatch may proceed) | 1 RED (do NOT dispatch) or nonce
# reuse | 2 usage / unreadable brief / legacy v1 brief without a nonce.
#
# FIXTURES: tests/smoke/test-verification-receipt.sh
set -uo pipefail

PROJ="${1:-}"
BRIEF="${2:-}"
if [ -z "$PROJ" ] || [ ! -d "$PROJ" ] || [ -z "$BRIEF" ]; then
  echo "usage: emit-verification-receipt.sh <proj> <brief-path>" >&2
  exit 2
fi
# Resolve the brief argument WITHOUT double-prefixing (handoff 2026-08-25
# P1-A): $PROJ is canonically relative (derive-proj.sh emits output/<slug>),
# and emit-agent-brief.sh prints an ALREADY PROJ-prefixed BRIEF= value — so
# blindly prepending $PROJ broke both documented invocation forms. Try the
# project-relative form first (prefer the project copy on collision), then
# the argument as given (covers the printed BRIEF= form), else fail closed
# naming both candidates. The RAW argument is delegated to verify-brief.sh,
# which applies this same resolution independently.
BRIEF_RAW="$BRIEF"
case "$BRIEF" in
  /*) : ;;
  *)
    if [ -f "$PROJ/$BRIEF" ]; then
      BRIEF="$PROJ/$BRIEF"
    fi ;;
esac
if [ ! -f "$BRIEF" ]; then
  echo "STATUS=RED"
  echo "REASON=brief not found at $PROJ/$BRIEF_RAW or $BRIEF_RAW — nothing to verify (fail closed)"
  exit 2
fi

VB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/verify-brief.sh"
if [ ! -f "$VB" ]; then
  echo "STATUS=RED"
  echo "REASON=verify-brief.sh not found beside this script — cannot verify"
  exit 2
fi

# Run the verifier ONCE, keep its full output for the receipt. Delegate the
# RAW argument — verify-brief.sh performs its own (identical) resolution, and
# handing it the resolved form would re-prefix $PROJ (the P1-A double-prefix).
set +e
VB_OUT="$(bash "$VB" "$PROJ" "$BRIEF_RAW" 2>&1)"
VB_RC=$?
set -u
if [ "$VB_RC" -eq 2 ]; then
  # Usage/schema failure inside the verifier — no receipt can attest anything.
  printf '%s\n' "$VB_OUT"
  echo "STATUS=RED"
  echo "REASON=verify-brief.sh could not read the brief (rc=2); no receipt written"
  exit 2
fi

PROJ="$PROJ" BRIEF="$BRIEF" VB="$VB" VB_OUT="$VB_OUT" VB_RC="$VB_RC" python3 - <<'PY'
import hashlib, json, os, sys
from datetime import datetime, timezone

proj = os.environ["PROJ"]; bp = os.environ["BRIEF"]
vb_out = os.environ["VB_OUT"]; vb_rc = int(os.environ["VB_RC"])

def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for c in iter(lambda: f.read(65536), b""):
            h.update(c)
    return h.hexdigest()

brief = json.load(open(bp, encoding="utf-8"))
nonce = brief.get("dispatch_nonce")
if not nonce:
    sys.stdout.write("STATUS=RED\n")
    sys.stdout.write("REASON=brief carries no dispatch_nonce (agent-brief/v1 legacy) — "
                     "re-emit it with the current emit-agent-brief.sh before dispatch\n")
    sys.exit(2)

# Per-input results, matched against the brief's KNOWN input paths — never
# split on " (", which truncated any path containing " (" (independent
# review 2026-08-23, M2; reference managers emit exactly such names). The
# receipt records what the verifier SAW; the GREEN/RED verdict below depends
# only on the verifier's EXIT CODE, never on this parsing.
vb_lines = [l.strip() for l in vb_out.splitlines()]
results = []
for rec in brief.get("inputs") or []:
    p = rec.get("path") or ""
    if ("OK: %s" % p) in vb_lines:
        res = "OK"
    elif any(l == "MISSING: %s" % p or l.startswith("MISSING: %s (" % p) for l in vb_lines):
        res = "MISSING"
    elif any(l == "MISMATCH: %s" % p or l.startswith("MISMATCH: %s (" % p) for l in vb_lines):
        res = "MISMATCH"
    else:
        res = "UNREPORTED"   # named honestly, never guessed from the verdict
    results.append({"path": p, "result": res, "sha256": rec.get("sha256")})

status = "GREEN" if vb_rc == 0 else "RED"
receipt = {
    "schema": "verification-receipt/v1",
    "nonce": nonce,
    "phase": brief.get("phase"), "role": brief.get("role"),
    "brief_path": os.path.relpath(bp, proj) if bp.startswith(proj) else bp,
    "brief_sha256": sha256(bp),
    "verifier": "verify-brief.sh",
    "verifier_sha256": sha256(os.environ["VB"]),
    "verified_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "inputs": results,
    "status": status,
}
rd = os.path.join(proj, "briefs", "receipts")
os.makedirs(rd, exist_ok=True)
out = os.path.join(rd, "%s.json" % nonce)
if os.path.exists(out):
    sys.stdout.write("STATUS=RED\n")
    sys.stdout.write("REASON=receipt %s already exists — one nonce, one verification; "
                     "a re-verify means a re-emitted brief (new nonce), never an "
                     "overwritten receipt\n" % out)
    sys.exit(1)
with open(out, "w", encoding="utf-8") as f:
    json.dump(receipt, f, indent=1, ensure_ascii=False)
    f.write("\n")
print("RECEIPT=%s" % out)
print("NONCE=%s" % nonce)
print("STATUS=%s" % status)
if status != "GREEN":
    sys.stdout.write("REASON=verify-brief reported rc=%d — do NOT dispatch; the receipt "
                     "records the failed check as audit evidence\n" % vb_rc)
    sys.exit(1)
PY
