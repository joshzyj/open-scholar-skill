#!/usr/bin/env bash
# Regression test for emit-trace.sh — the universal RAO trace writer.
# Verifies: valid NDJSON output, required-field + triad validation (fail-loud),
# monotonic seq across stateless calls, refs-array parsing, control-char/quote
# escaping, status validation, and the non-blocking PII warn.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
EMIT="$REPO_ROOT/scripts/gates/emit-trace.sh"
[ -f "$EMIT" ] || { echo "FATAL: missing $EMIT"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: python3 needed for JSON validation"; exit 0; }

FAILS=0
ok()  { echo "  ok: $1"; }
bad() { echo "  FAIL: $1"; FAILS=$((FAILS + 1)); }
TMP=$(mktemp -d "${TMPDIR:-/tmp}/emittrace.XXXXXX"); trap 'rm -rf "$TMP"' EXIT
OR="$TMP/output"
DATE=$(date +%Y-%m-%d)
TRACE="$OR/logs/trace-scholar-analyze-$DATE.ndjson"

run() { OUTPUT_ROOT="$OR" bash "$EMIT" --skill scholar-analyze "$@"; }

bash -n "$EMIT" && ok "emit-trace.sh parses" || bad "syntax error"

# 1. Valid record with quotes + a real newline in reasoning + refs list.
printf -v NL 'line1\nline2'
run --phase 5B --step "M3-clustered-SE" \
    --reasoning "$NL" \
    --action 'feols(y ~ x | state, cluster=~state)' \
    --observation 'beta=0.42, p<0.01, N=1200' \
    --refs "tables/r.csv, figures/f1.png" >/dev/null 2>&1 \
  && ok "valid record accepted (rc=0)" || bad "valid record rejected"

# 2. Every line is valid JSON; required keys present; refs is an array;
#    newline collapsed (no raw newline inside the JSON string).
python3 - "$TRACE" <<'PY' && ok "output is well-formed NDJSON with required keys" || bad "NDJSON/schema invalid"
import json,sys
req={"ts","seq","run_id","skill","phase","agent","agentId","step","reasoning","action","observation","refs","status"}
n=0
for line in open(sys.argv[1]):
    line=line.rstrip("\n")
    if not line: continue
    r=json.loads(line)                       # raises on malformed
    assert req<=set(r), f"missing keys: {req-set(r)}"
    assert isinstance(r["refs"], list), "refs not a list"
    assert "\n" not in r["reasoning"], "raw newline leaked into field"
    n+=1
assert n>=1
PY

# 3. seq is monotonic across separate (stateless) invocations.
run --step "M4" --action "second step" >/dev/null 2>&1
run --step "M5" --action "third step" >/dev/null 2>&1
SEQS=$(python3 -c "import json;print(','.join(str(json.loads(l)['seq']) for l in open('$TRACE') if l.strip()))")
[ "$SEQS" = "1,2,3" ] && ok "seq monotonic across stateless calls (1,2,3)" || bad "seq not monotonic: $SEQS"

# 4. refs parsed into 2 elements.
NREFS=$(python3 -c "import json;print(len(json.loads(open('$TRACE').readline())['refs']))")
[ "$NREFS" = "2" ] && ok "refs parsed into array (2 elements)" || bad "refs count=$NREFS (want 2)"

# 5. Fail-loud cases.
run --step only-step >/dev/null 2>&1;               [ $? -eq 1 ] && ok "empty RAO triad -> rc 1" || bad "empty triad not rejected"
OUTPUT_ROOT="$OR" bash "$EMIT" --step s --action a >/dev/null 2>&1; [ $? -eq 1 ] && ok "missing --skill -> rc 1" || bad "missing skill not rejected"
run --step s --action a --status bogus >/dev/null 2>&1; [ $? -eq 1 ] && ok "bad --status -> rc 1" || bad "bad status not rejected"

# 6. PII warn (non-blocking: still rc 0, but warns).
OUT=$(run --step s --observation "contact a@b.edu" 2>&1); rc=$?
{ [ $rc -eq 0 ] && printf '%s' "$OUT" | grep -q WARN; } && ok "PII-looking observation -> non-blocking WARN" || bad "PII warn missing (rc=$rc)"

echo ""
if [ "$FAILS" -eq 0 ]; then echo "ALL emit-trace checks passed"; exit 0
else echo "$FAILS emit-trace check(s) FAILED"; exit 1; fi
