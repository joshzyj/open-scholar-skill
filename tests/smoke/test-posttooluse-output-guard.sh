#!/usr/bin/env bash
# test-posttooluse-output-guard.sh — smoke test for the Strict-tier PostToolUse
# stdout redactor (scripts/gates/posttooluse-output-guard.sh).
#
# The redactor inspects a Bash tool's stdout/stderr (under .tool_response, the
# verified Claude Code 2.1.153 schema) and, when the project is at safety level
# >= strict AND holds restricted data, replaces PII / bulk-row output with a
# notice via hookSpecificOutput.updatedToolOutput (an OBJECT — string form is
# ignored by the harness). It is accident-mitigation, fails open, never blocks.
#
# Offline + deterministic. Asserts redact-vs-pass across levels and content.

set -uo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PT="${REPO_ROOT}/scripts/gates/posttooluse-output-guard.sh"
PASS=0; FAIL=0
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

echo "=== PostToolUse output guard (Strict tier) ==="
[ -f "$PT" ] || { echo "  FAIL: $PT missing"; exit 1; }
if ! command -v jq >/dev/null 2>&1; then
  echo "  SKIP: jq not installed"; echo "Results: 0 passed, 0 failed"; exit 0
fi

P="$(mktemp -d -t ptguard.XXXXXX)"; trap 'rm -rf "$P"' EXIT
mkdir -p "$P/.claude"

side() { # $1=level  $2=clean|restricted
  if [ "${2:-}" = clean ]; then jq -n --arg l "$1" '{"/d/a.csv":"CLEARED","_safety_level":$l}'
  else jq -n --arg l "$1" '{"/d/a.csv":"NEEDS_REVIEW:RED","_safety_level":$l}'; fi > "$P/.claude/safety-status.json"
}
pl() { jq -n --arg o "$1" --arg e "${2:-}" --arg cwd "$P" \
  '{cwd:$cwd,hook_event_name:"PostToolUse",tool_name:"Bash",tool_input:{command:"x"},tool_response:{stdout:$o,stderr:$e,interrupted:false,isImage:false,noOutputExpected:false}}'; }
verdict() { # payload -> REDACT|PASS
  local out; out="$(printf '%s' "$1" | bash "$PT" 2>/dev/null)"
  if [ -n "$out" ] && printf '%s' "$out" | jq -e '.hookSpecificOutput.updatedToolOutput' >/dev/null 2>&1; then echo REDACT; else echo PASS; fi
}
chk() { local want="$1" got="$2" d="$3"; [ "$got" = "$want" ] && pass "$d ($got)" || fail "$d — want $want got $got"; }

SSN=$'id,ssn\n1,123-45-6789\n2,987-65-4321'
AGG=$'N = 100\nmean = 3.2\nsd = 0.4\nVariables = 12'
BULK="$(python3 -c "print('\n'.join('a%d,b%d,c%d'%(i,i,i) for i in range(250)))" 2>/dev/null || awk 'BEGIN{for(i=0;i<250;i++)print "a"i",b"i",c"i}')"

side standard restricted; chk PASS   "$(verdict "$(pl "$SSN")")"        "standard level never redacts (no-op)"
side strict   restricted; chk REDACT "$(verdict "$(pl "$SSN")")"        "strict + PII stdout redacted"
side strict   restricted; chk PASS   "$(verdict "$(pl "$AGG")")"        "strict + aggregate output passes"
side strict   restricted; chk REDACT "$(verdict "$(pl "$BULK")")"       "strict + bulk delimited rows redacted"
side strict   restricted; chk REDACT "$(verdict "$(pl "ok" "$SSN")")"   "strict + PII in stderr redacted"
side strict   clean;      chk PASS   "$(verdict "$(pl "$SSN")")"        "strict but no restricted entry passes"
side lockdown restricted; chk REDACT "$(verdict "$(pl "$SSN")")"        "lockdown also redacts"

# non-Bash tool → never acts
chk PASS "$(verdict "$(jq -n --arg cwd "$P" '{cwd:$cwd,tool_name:"Read",tool_response:{stdout:"id,ssn\n1,123-45-6789"}}')")" "non-Bash tool no-op"

# redaction replaces stdout with the notice
side strict restricted
REPL="$(printf '%s' "$(pl "$SSN")" | bash "$PT" 2>/dev/null | jq -r '.hookSpecificOutput.updatedToolOutput.stdout')"
case "$REPL" in *"redacted"*) pass "redacted stdout carries the notice (no SSN)";; *) fail "redaction notice missing";; esac
case "$REPL" in *123-45-6789*) fail "SSN leaked into replacement!";; *) pass "original SSN absent from replacement";; esac

echo ""
echo "════════════════════"
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1
exit 0
