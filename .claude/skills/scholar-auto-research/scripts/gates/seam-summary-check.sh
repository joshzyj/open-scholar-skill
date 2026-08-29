#!/usr/bin/env bash
# seam-summary-check.sh — validate a seam summary as a DERIVED VIEW (RCA
# Round 2 #9, 2026-08-22).
#
# The seam summary (seams/<phase>-summary.json, emitted by phase-seam-emit.sh)
# is what the next session reads FIRST — but it is never authority. This gate
# re-hashes every file the summary names (sources[] + manuscript) against the
# bytes on disk. A STALE CARD IS A HARD ERROR (RED): the consumer must read
# the named artifact itself and re-emit the summary — a quietly-preferred
# stale card is exactly the binding-facts failure mode the RCA's Codex review
# demoted cards to views to prevent.
#
# Usage: seam-summary-check.sh <project_dir> [<phase>]
#   With <phase>: validate seams/<phase>-summary.json.
#   Without: validate the NEWEST summary.
# On GREEN prints the consumer-ready resolution lines:
#   MANUSCRIPT=<path>  MANUSCRIPT_SHA256=<sha>  LOCK_ID=<id>  NEXT_PHASE=<id>
# Exit: 0 GREEN | 1 RED (stale/malformed) | 3 INERT (no summaries yet)
set -uo pipefail

PROJ="${1:-}"; PHASE="${2:-}"
if [ -z "$PROJ" ] || [ ! -d "$PROJ" ]; then
  echo "GATE=seam-summary-check"; echo "STATUS=RED"
  echo "REASON=usage: seam-summary-check.sh <project_dir> [<phase>]"
  exit 1
fi
echo "GATE=seam-summary-check"
echo "PROJECT=$PROJ"

if [ -n "$PHASE" ]; then
  SUMMARY="$PROJ/seams/${PHASE}-summary.json"
  [ -f "$SUMMARY" ] || { echo "STATUS=INERT"; echo "REASON=no seams/${PHASE}-summary.json"; exit 3; }
else
  SUMMARY=$(ls -1t "$PROJ"/seams/*-summary.json 2>/dev/null | head -1 || true)
  [ -n "$SUMMARY" ] || { echo "STATUS=INERT"; echo "REASON=no seam summaries under $PROJ/seams/ — legacy project or seam emitter not yet run"; exit 3; }
fi
echo "SUMMARY=$SUMMARY"
command -v python3 >/dev/null 2>&1 || {
  echo "STATUS=INERT"
  echo "REASON=python3 unavailable — cannot validate the card; use the disk fallback (newest drafts/manuscript-*.md)"
  exit 3
}

SCRIPT_DIR_SSC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_OUT=$(PROJ="$PROJ" SUMMARY="$SUMMARY" SCRIPT_DIR_SSC="$SCRIPT_DIR_SSC" python3 - <<'PY'
import hashlib, json, os, sys
proj = os.environ["PROJ"]; sp = os.environ["SUMMARY"]
# Base for skill-relative sources: this helper is vendored inside
# scholar-auto-research, so resolve only against its own package.
skill_root = os.path.normpath(os.path.join(os.environ["SCRIPT_DIR_SSC"], "..", ".."))
try:
    d = json.load(open(sp, encoding="utf-8"))
except ValueError as e:
    print("RED\tsummary unparseable: %s" % e); sys.exit(0)
if d.get("schema") != "seam-summary/v1":
    print("RED\tunknown schema %r" % d.get("schema")); sys.exit(0)
def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for c in iter(lambda: f.read(65536), b""):
            h.update(c)
    return h.hexdigest()
def sha256_prefix(path, n):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        h.update(f.read(n))
    return h.hexdigest()
stale = []
for s in d.get("sources", []):
    if s["path"].startswith("references/"):
        p = os.path.join(skill_root, s["path"])
    else:
        p = os.path.join(proj, s["path"])
    if not os.path.isfile(p):
        stale.append("%s MISSING" % s["path"])
    elif s.get("mode") == "prefix":
        # append-tolerant: later appends are fine; a rewrite/truncation of
        # the pinned prefix is not.
        if os.path.getsize(p) < s["bytes"]:
            stale.append("%s truncated below its pinned %d bytes" % (s["path"], s["bytes"]))
        elif sha256_prefix(p, s["bytes"]) != s["sha256"]:
            stale.append("%s pinned prefix rewritten" % s["path"])
    elif sha256(p) != s["sha256"]:
        stale.append("%s sha mismatch" % s["path"])
m = d.get("manuscript")
if m:
    mp = os.path.join(proj, m["path"])
    if not os.path.isfile(mp):
        stale.append("%s MISSING (manuscript)" % m["path"])
    elif sha256(mp) != m["sha256"]:
        stale.append("%s sha mismatch (manuscript)" % m["path"])
if stale:
    print("RED\t" + "; ".join(stale)); sys.exit(0)
# "-" placeholders: tab is IFS-whitespace in the bash reader, so EMPTY
# fields would collapse and shift their neighbors left (observed on a real
# project with no manuscript yet: next_phase landed in the MANUSCRIPT slot).
# R3 verification round (2026-08-22): the GREEN card must ALSO surface the
# pending-work counters — the "read this first" consumer (resume Step R1.5)
# otherwise reads a card with 4 FIXED-awaiting-re-review findings as
# "nothing open", the exact miss fixed_unverified was added to prevent.
of = d.get("open_findings") or {}
fu = d.get("fixed_unverified") or {}
def fmt(bucket, present_in_card):
    # F2 (R3 eval): a missing ledger or a pre-R3 card must render UNKNOWN,
    # never a fabricated 0 — zeros are claims, and these would be unbacked.
    if not present_in_card:
        return "UNKNOWN(card-v1)"
    if bucket.get("basis") == "no-ledger" or bucket.get("count") is None:
        return "UNKNOWN(no-ledger)"
    ids = [i for i in (bucket.get("ids") or []) if isinstance(i, str)]
    n = bucket.get("count") or 0
    return "%s%s" % (n, (" (" + ",".join(ids[:6]) + ")") if ids else "")
acc = (d.get("accepted_findings") or {}).get("count")
print("OK\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s" % ((m or {}).get("path") or "-", (m or {}).get("sha256") or "-",
      d.get("lock_id") or "-", d.get("next_phase") or "-",
      fmt(of, "open_findings" in d) or "-", fmt(fu, "fixed_unverified" in d) or "-",
      d.get("verdict") or "-", d.get("gates_red") if d.get("gates_red") is not None else "-",
      acc if acc is not None else "-"))
PY
)
case "$_OUT" in
  OK*)
    IFS=$(printf '\t') read -r _tag _mpath _msha _lock _next _openf _fixedu _cverd _cred _cacc <<EOF_OK
$_OUT
EOF_OK
    [ "${_mpath:--}" != "-" ] && echo "MANUSCRIPT=$_mpath" && echo "MANUSCRIPT_SHA256=$_msha"
    [ "${_lock:--}" != "-" ] && echo "LOCK_ID=$_lock"
    [ "${_next:--}" != "-" ] && echo "NEXT_PHASE=$_next"
    echo "OPEN_FINDINGS=${_openf:-UNKNOWN}"
    echo "FIXED_UNVERIFIED=${_fixedu:-UNKNOWN}"
    echo "CARD_VERDICT=${_cverd:--}"
    echo "CARD_GATES_RED=${_cred:--}"
    [ "${_cacc:--}" != "-" ] && [ "${_cacc:-0}" != "0" ] && echo "ACCEPTED_FINDINGS=${_cacc} — the phase advanced over KNOWN, disclosed defects (§7b); read logs/gate-acceptances.md"
    case "${_openf:-}" in
      (UNKNOWN*) echo "NOTE: pending-work counts are UNKNOWN (no findings ledger backs them) — read the review reports directly; do NOT read this card as nothing-open" ;;
    esac
    case "${_fixedu:-0}" in
      (0|-|""|UNKNOWN*) : ;;
      (*) echo "NOTE: FIXED-awaiting-re-review findings are PENDING WORK (DC-03) — do not read this card as nothing-open" ;;
    esac
    echo "STATUS=GREEN"
    exit 0
    ;;
  RED*)
    echo "STATUS=RED"
    echo "REASON=STALE CARD (hard error) — ${_OUT#RED	}. The summary is a derived view, never authority: read the named artifact directly, then re-emit via phase-seam-emit.sh."
    exit 1
    ;;
  *)
    echo "STATUS=RED"
    echo "REASON=validator produced no verdict"
    exit 1
    ;;
esac
