#!/usr/bin/env bash
# test-pii-method-eponyms.sh — a statistical-method eponym is not respondent PII.
#
# WHY (P19-A D2, reproduced 2026-08-27 by the peer session and confirmed here):
# Presidio's NER scores a bare surname as PERSON 0.85, which safety-scan.sh
# classifies RED, which posttooluse-output-guard.sh treats as "PII detected"
# and redacts the ENTIRE tool output. Statistical vocabulary is eponymous, so
#   echo "the correction applied was Holm"      -> RED (all output redacted)
#   echo "VERDICT: it SURVIVES at K=2 -> False" -> clean
# Same line, eponym removed. This blocked a reviewer from independently
# verifying arithmetic about a paper's central result, and had earlier blocked
# bibliography author lists — the same detector, another legitimate input.
#
# NOTE ON THE ORIGINAL DIAGNOSIS: the finding was first filed as a
# "digit density" threshold, and this session's own first hypothesis was
# is_bulk_rows (>200 delimited lines). BOTH were wrong. There is no
# digit-density rule, and a 5-line print never approaches the bulk-row floor.
# The guard was correctly identifying a surname; the surname just isn't
# respondent data.
#
# The suppression is narrow BY DESIGN, because a respondent can be named Cox
# or Lee. All three conditions must hold, and this suite pins each one:
#   1. the span is an allowlisted method eponym,
#   2. it sits in a method context (a roster of names has none),
#   3. no other PII is present in the file (real PII re-promotes it).
# The hit is DOWNGRADED to YELLOW and reported, never deleted.
set -uo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCAN="$REPO_ROOT/scripts/gates/safety-scan.sh"
PASS=0; FAIL=0
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

TMP="$(mktemp -d -t eponym.XXXXXX)"; trap 'rm -rf "$TMP"' EXIT

if [ ! -f "$SCAN" ]; then
  echo "  FAIL: safety-scan.sh not found"; exit 1
fi
# Presidio is optional; without it there is no PERSON NER and nothing to assert.
if ! python3 -c "from presidio_analyzer import AnalyzerEngine; AnalyzerEngine()" 2>/dev/null; then
  echo "  SKIP: presidio-analyzer unavailable — PERSON NER cannot be exercised"
  echo "Results: 0 passed, 0 failed"
  exit 0
fi

verdict() {  # <file> -> GREEN|YELLOW|RED
  bash "$SCAN" "$1" >/dev/null 2>&1
  case $? in 0) echo GREEN;; 1) echo RED;; 2) echo YELLOW;; *) echo OTHER;; esac
}
expect() {  # <label> <file> <want>
  local got; got="$(verdict "$2")"
  [ "$got" = "$3" ] && pass "$1 ($got)" || fail "$1 — want $3, got $got"
}

printf 'the correction applied was Holm\n' > "$TMP/eponym.txt"
printf 'Holm-Bonferroni adjustment; Rosenbaum bounds; Oster delta = 1.2\n' > "$TMP/many.txt"
printf 'respondent name: Michael Brennan, interviewed in March\n' > "$TMP/person.txt"
printf 'Holm correction applied.\nrespondent SSN 123-45-6789\n' > "$TMP/mixed.txt"
printf 'Participants: Holm, Sarah; Cox, Daniel; Lee, Jennifer\n' > "$TMP/roster.txt"
printf 'contrast = 0.164, se = 0.041, z = 4.00, p = 0.00006\n' > "$TMP/numbers.txt"

# 1. the defect itself: eponymous method output must not read as respondent PII
expect "method eponym in method context is not RED" "$TMP/eponym.txt" YELLOW
expect "several eponyms in method context are not RED" "$TMP/many.txt" YELLOW

# 2. the guard must still catch real people
expect "a real person name still REDs" "$TMP/person.txt" RED

# 3. condition 3 — other PII re-promotes the downgraded eponym
expect "eponym alongside real PII still REDs" "$TMP/mixed.txt" RED

# 4. condition 2 — a roster of names has no method context
expect "name roster without method context still REDs" "$TMP/roster.txt" RED

# 5. unchanged baseline
expect "pure numeric output stays GREEN" "$TMP/numbers.txt" GREEN

# 6. the escape hatch restores the old behaviour
GOT_OFF="$(SCHOLAR_PII_EPONYM_ALLOWLIST=0 bash "$SCAN" "$TMP/eponym.txt" >/dev/null 2>&1; echo $?)"
[ "$GOT_OFF" = "1" ] \
  && pass "SCHOLAR_PII_EPONYM_ALLOWLIST=0 restores the pre-fix RED" \
  || fail "allowlist could not be disabled (got rc=$GOT_OFF) — the suppression must be switchable"

# 7. the downgrade is REPORTED, not silent — a declaration, not a bypass
OUT="$(bash "$SCAN" "$TMP/eponym.txt" 2>&1 || true)"
if printf '%s' "$OUT" | grep -qi "eponym\|downgrad"; then
  pass "the downgrade is disclosed in the scan output"
else
  fail "downgrade is silent — a suppression nobody can see is a bypass"
fi

# 8. the redaction path is what actually matters: YELLOW must not redact
GUARD="$REPO_ROOT/scripts/gates/posttooluse-output-guard.sh"
if grep -q '\[ "$rc" = 1 \]' "$GUARD" 2>/dev/null; then
  pass "output guard redacts on RED only, so a YELLOW eponym no longer redacts"
else
  fail "output guard's PII condition changed — re-check that YELLOW does not redact"
fi

# ── 9. the guard must NAME the detector that fired ─────────────────────────
# The notice used to say output matched "PII patterns OR a bulk row dump". The
# guard knows which — `scan_pii || is_bulk_rows` — and discarded the
# distinction. Two independent investigators each picked the wrong disjunct and
# spent rounds chasing a threshold that does not exist. A disjunctive
# explanation is not an explanation.
GUARD="$REPO_ROOT/scripts/gates/posttooluse-output-guard.sh"
mkdir -p "$TMP/proj/.claude"
printf '{"data/raw/x.dta":"LOCAL_MODE — restricted"}\n' > "$TMP/proj/.claude/safety-status.json"
_trigger() {  # <stdout-json-string> -> first line of the redacted stdout
  printf '{"tool_name":"Bash","cwd":"%s","tool_response":{"stdout":%s,"stderr":""}}' "$TMP/proj" "$1" \
    | SCHOLAR_SAFETY_LEVEL=strict bash "$GUARD" 2>/dev/null \
    | python3 -c "import json,sys; d=sys.stdin.read().strip(); print(json.loads(d)['hookSpecificOutput']['updatedToolOutput']['stdout'].splitlines()[0] if d else 'NOT_REDACTED')" 2>/dev/null
}
if [ ! -f "$GUARD" ]; then
  fail "posttooluse-output-guard.sh missing"
else
  T="$(_trigger '"respondent Michael Brennan, interviewed March 2020"')"
  case "$T" in
    *"REDACTION_TRIGGER: PII scan matched entity type(s): "*PERSON*)
      pass "PII redaction names the entity type that fired" ;;
    *) fail "PII redaction did not name its entity type: $T" ;;
  esac
  BULK="$(python3 -c "print('\\\\n'.join('a,b,c' for _ in range(250)))")"
  T="$(_trigger "\"$BULK\"")"
  case "$T" in
    *"REDACTION_TRIGGER: bulk row dump ("*"delimited lines, threshold 200)"*)
      pass "bulk-row redaction names the line count and threshold" ;;
    *) fail "bulk-row redaction did not name its counts: $T" ;;
  esac
  # The two triggers must be DISTINGUISHABLE — that is the whole point.
  A="$(_trigger '"respondent Michael Brennan, interviewed March 2020"')"
  B="$(_trigger "\"$BULK\"")"
  [ "$A" != "$B" ] \
    && pass "the two detectors produce different messages (no disjunction to guess)" \
    || fail "both detectors produce the same message — the reader must still guess"
fi

echo ""
echo "════════════════════"
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
