#!/usr/bin/env bash
# ingest-findings-inbox.sh — single-writer ingestion of a seat's findings
# inbox into the canonical ledger (system-fix plan v2 S1.3, 2026-08-23).
#
# WHY (handoff P2-4): the brief's findings-ndjson return contract used to
# instruct every seat to append to logs/findings.ndjson — at Phase 3.5 that
# order went to FOUR seats dispatched in parallel, the concurrent-write
# clobber CLAUDE.md §7a exists to forbid. Three of four seats independently
# declined the write citing §7a, so the contract was satisfiable only by
# agents disobeying it. Now each seat writes its OWN inbox file,
# logs/findings-inbox/<dispatch_nonce>.ndjson, and the ORCHESTRATOR — the
# ledger's single writer — ingests it through this tool after the seat
# returns.
#
# CONTRACT
#   - ATOMIC: if ANY inbox line fails validation, NOTHING is ingested
#     (a partial ingest is a split-brain ledger).
#   - Validation per line: parseable JSON object; required ledger keys
#     (id, ts, status, locus, report — _shared/findings-ledger.md); status
#     MUST be OPEN (a seat files findings; it never closes them);
#     verify.mode=check requires cmd AND expect.
#   - IDEMPOTENT: each ingested line is stamped with source_nonce and
#     source_line_sha (sha256 of the raw inbox line, first 16 hex); a line
#     whose (source_nonce, source_line_sha) already exists in the ledger is
#     skipped, so re-running after a partial session is safe.
#   - A MISSING inbox fails closed (exit 1): a typo'd nonce silently
#     ingesting zero findings is a false success. When the seat genuinely
#     returned no blocking findings, pass --allow-empty.
#
# USAGE
#   ingest-findings-inbox.sh <proj> <nonce> [--agentId <id>] [--allow-empty]
#
# OUTPUT: INGESTED= / SKIPPED_DUPLICATE= / REJECTED= counters + STATUS=.
# EXIT: 0 ingested (or legitimately empty with --allow-empty) | 1 missing
# inbox / validation failure | 2 usage.
#
# FIXTURES: tests/smoke/test-findings-inbox.sh
set -uo pipefail

PROJ="${1:-}"
NONCE="${2:-}"
AGENT_ID=""
ALLOW_EMPTY=0
if [ -n "$PROJ" ]; then shift; fi
if [ -n "$NONCE" ]; then shift; fi
while [ $# -gt 0 ]; do
  case "$1" in
    --agentId) AGENT_ID="${2:-}"; shift 2 ;;
    --allow-empty) ALLOW_EMPTY=1; shift ;;
    *) echo "Usage: ingest-findings-inbox.sh <proj> <nonce> [--agentId <id>] [--allow-empty]" >&2; exit 2 ;;
  esac
done
if [ -z "$PROJ" ] || [ ! -d "$PROJ" ] || [ -z "$NONCE" ]; then
  echo "Usage: ingest-findings-inbox.sh <proj> <nonce> [--agentId <id>] [--allow-empty]" >&2
  exit 2
fi
case "$NONCE" in
  *[!0-9a-f]*) echo "ERROR: nonce must be lowercase hex (got '$NONCE')" >&2; exit 2 ;;
esac

INBOX="$PROJ/logs/findings-inbox/$NONCE.ndjson"
LEDGER="$PROJ/logs/findings.ndjson"
echo "GATE=ingest-findings-inbox"
echo "INBOX=$INBOX"
if [ ! -f "$INBOX" ]; then
  if [ "$ALLOW_EMPTY" = 1 ]; then
    echo "INGESTED=0"
    echo "STATUS=GREEN"
    echo "REASON=no inbox file and --allow-empty passed (seat reported zero blocking findings)"
    exit 0
  fi
  echo "STATUS=RED"
  echo "REASON=inbox not found — a typo'd nonce ingesting nothing would be a false"
  echo "       success (fail closed). Pass --allow-empty only when the seat's final"
  echo "       message reported zero blocking findings."
  exit 1
fi

PROJ="$PROJ" NONCE="$NONCE" INBOX="$INBOX" LEDGER="$LEDGER" AGENT_ID="$AGENT_ID" python3 - <<'PY'
import hashlib, json, os, sys

nonce = os.environ["NONCE"]; agent_id = os.environ["AGENT_ID"]
ledger_path = os.environ["LEDGER"]

VOCAB_REQUIRED = ("id", "ts", "status", "locus", "report")

existing = set()
if os.path.isfile(ledger_path):
    for line in open(ledger_path, encoding="utf-8", errors="replace"):
        line = line.strip()
        if not line:
            continue
        try:
            r = json.loads(line)
        except ValueError:
            continue
        if r.get("source_nonce") and r.get("source_line_sha"):
            existing.add((r["source_nonce"], r["source_line_sha"]))

to_append, rejected, skipped = [], [], 0
for ln, raw in enumerate(open(os.environ["INBOX"], encoding="utf-8", errors="replace"), 1):
    raw = raw.strip()
    if not raw:
        continue
    line_sha = hashlib.sha256(raw.encode("utf-8")).hexdigest()[:16]
    if (nonce, line_sha) in existing:
        skipped += 1
        continue
    try:
        rec = json.loads(raw)
    except ValueError:
        rejected.append("line %d: unparseable JSON" % ln); continue
    if not isinstance(rec, dict):
        rejected.append("line %d: not a JSON object" % ln); continue
    missing = [k for k in VOCAB_REQUIRED if not rec.get(k)]
    if missing:
        rejected.append("line %d: missing required key(s) %s" % (ln, ",".join(missing))); continue
    if rec.get("status") != "OPEN":
        rejected.append("line %d (%s): status %r — a seat FILES findings (OPEN); it never "
                        "closes, fixes, or accepts them" % (ln, rec.get("id"), rec.get("status")))
        continue
    v = rec.get("verify") or {}
    if v.get("mode") == "check" and (not v.get("cmd") or not v.get("expect")):
        rejected.append("line %d (%s): verify.mode=check requires cmd AND expect" % (ln, rec.get("id")))
        continue
    rec["source_nonce"] = nonce
    rec["source_line_sha"] = line_sha
    if agent_id:
        rec["source_agent_id"] = agent_id
    to_append.append(rec)

# INGESTED reports what was WRITTEN, never what would have been — on a
# rejection nothing is written, so the counter must read 0 (printing the
# would-be count was itself a false success report, caught by T3).
print("SKIPPED_DUPLICATE=%d" % skipped)
print("REJECTED=%d" % len(rejected))
for msg in rejected:
    print("  FAIL: %s" % msg)
if rejected:
    print("INGESTED=0")
    print("WOULD_INGEST=%d" % len(to_append))
    print("STATUS=RED")
    print("REASON=validation failed — NOTHING ingested (atomic: a partial ingest is a "
          "split-brain ledger). Fix the inbox or have the seat re-file.")
    sys.exit(1)
print("INGESTED=%d" % len(to_append))
os.makedirs(os.path.dirname(ledger_path), exist_ok=True)
with open(ledger_path, "a", encoding="utf-8") as f:
    for rec in to_append:
        f.write(json.dumps(rec, ensure_ascii=False) + "\n")
print("STATUS=GREEN")
sys.exit(0)
PY
exit $?
