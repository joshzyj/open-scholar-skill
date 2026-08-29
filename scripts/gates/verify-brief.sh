#!/usr/bin/env bash
# verify-brief.sh — input verification for agent-brief/v1 and /v2 packets.
#
# Since 2026-08-23 (system-fix S1.1) this runs ORCHESTRATOR-SIDE, immediately
# pre-dispatch, via emit-verification-receipt.sh — reviewer seats hold no
# Bash, so agent-side execution was never possible for them (handoff P1-3),
# and granting a shell was rejected (the data guard fails open by design).
# Direct agent-side use remains valid for Bash-holding agents.
#
# WHY (real-project eval, ses 2026-08-22, finding 15): every brief's strip
# directive says "verify each input's sha256 before reading; a mismatch is
# STOP-and-report (DC-07)" — but no helper existed, so verification was
# honor-system and every agent hand-rolled it (or skipped it). This closes
# the gap between directive and practice: one command, run FIRST by the
# dispatched agent, before any input is opened.
#
# CONTRACT
#   Reads the brief JSON, re-hashes every inputs[] entry against the recorded
#   sha256, and reports per-file. A mismatch means the surface MOVED after
#   the brief was emitted — the agent must STOP and report, never adapt
#   around it (DC-07: content-verified, not mtime-trusted). The pinned
#   seam_summary is re-hashed too; its drift is a WARN (seam cards re-emit
#   legitimately at later phase boundaries) — the agent should say so in its
#   return, but inputs govern the verdict.
#
# USAGE
#   verify-brief.sh <proj> <brief-path-relative-or-absolute>
#
# EXIT
#   0 GREEN  every input exists and hashes match (agent may proceed)
#   1 RED    >=1 input missing or sha-mismatched (STOP-and-report, DC-07)
#   2 usage error / brief missing or not agent-brief/v1 (fail closed — a
#     brief that cannot be read verifies nothing)
#
# FIXTURES: tests/smoke/test-verify-brief.sh
set -uo pipefail

PROJ="${1:-}"
BRIEF="${2:-}"
if [ -z "$PROJ" ] || [ ! -d "$PROJ" ] || [ -z "$BRIEF" ]; then
  echo "usage: verify-brief.sh <proj> <brief-path>" >&2
  exit 2
fi
# Resolution order (handoff 2026-08-25 P1-A): absolute as-is; else the
# project-relative form if it exists (prefer the project copy on collision);
# else the argument as given (emit-agent-brief.sh prints an already
# PROJ-prefixed BRIEF= value, and $PROJ is canonically relative); else fail
# closed naming both candidates.
BRIEF_RAW="$BRIEF"
case "$BRIEF" in
  /*) : ;;
  *)
    if [ -f "$PROJ/$BRIEF" ]; then
      BRIEF="$PROJ/$BRIEF"
    fi ;;
esac
if [ ! -f "$BRIEF" ]; then
  echo "GATE=verify-brief"
  echo "STATUS=RED"
  echo "REASON=brief not found at $PROJ/$BRIEF_RAW or $BRIEF_RAW — a brief that cannot be read verifies nothing (fail closed)"
  exit 2
fi

PROJ="$PROJ" BRIEF="$BRIEF" python3 - <<'PY_VB'
import hashlib, json, os, sys

proj = os.environ["PROJ"]; bp = os.environ["BRIEF"]

def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for c in iter(lambda: f.read(65536), b""):
            h.update(c)
    return h.hexdigest()

print("GATE=verify-brief")
print("BRIEF=%s" % bp)
try:
    brief = json.load(open(bp, encoding="utf-8"))
except (OSError, ValueError) as e:
    print("STATUS=RED")
    print("REASON=brief unreadable as JSON (%s) — fail closed" % e.__class__.__name__)
    sys.exit(2)
if brief.get("schema") not in ("agent-brief/v1", "agent-brief/v2"):
    print("STATUS=RED")
    print("REASON=schema is %r, not agent-brief/v1 or /v2 — fail closed" % brief.get("schema"))
    sys.exit(2)

bad = 0
inputs = brief.get("inputs") or []
for rec in inputs:
    path = rec.get("path") or ""
    want = rec.get("sha256") or ""
    ap = path if os.path.isabs(path) else os.path.join(proj, path)
    if not os.path.isfile(ap):
        print("  MISSING: %s (pinned %s…)" % (path, want[:12]))
        bad += 1
        continue
    got = sha256(ap)
    if got != want:
        print("  MISMATCH: %s (brief pinned %s…, disk has %s…)" % (path, want[:12], got[:12]))
        bad += 1
    else:
        print("  OK: %s" % path)
print("INPUTS_TOTAL=%d" % len(inputs))
print("INPUTS_BAD=%d" % bad)

seam = brief.get("seam_summary")
if isinstance(seam, dict) and seam.get("path"):
    sp = os.path.join(proj, seam["path"])
    if not os.path.isfile(sp):
        print("WARN: pinned seam summary %s is gone — note it in your return" % seam["path"])
    elif sha256(sp) != (seam.get("sha256") or ""):
        print("WARN: seam summary %s changed since this brief was emitted — the seam card you" % seam["path"])
        print("      will read is NOT the one the dispatcher saw; note it in your return")

if bad:
    print("STATUS=RED")
    print("REASON=%d of %d input(s) missing or moved since the brief was emitted. STOP and" % (bad, len(inputs)))
    print("       report the mismatch to the dispatcher (DC-07) — do NOT re-derive, adapt")
    print("       around it, or proceed on the moved bytes; the brief no longer describes")
    print("       the world you were dispatched into.")
    sys.exit(1)
print("STATUS=GREEN")
print("REASON=all %d input(s) verified against the brief; proceed" % len(inputs))
PY_VB
