#!/usr/bin/env bash
# test-sidecar-schema.sh — smoke test for sidecar-schema.sh (FA-6).
#
# sidecar-schema.sh is the SHARED schema validator for .claude/safety-status.json,
# sourced by BOTH pretooluse-data-guard.sh and init-handshake.sh so they cannot
# diverge on what a valid sidecar entry is. It provides is_valid_status and
# validate_sidecar_schema. A regression here weakens the data-safety stack on
# both call sites at once, so it deserves a direct test.

set -uo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LIB="${REPO_ROOT}/scripts/gates/sidecar-schema.sh"
PASS=0; FAIL=0
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

echo "=== sidecar-schema.sh (FA-6) ==="
echo ""
[ -f "$LIB" ] || { echo "  FAIL: $LIB missing"; exit 1; }
if ! command -v jq >/dev/null 2>&1; then
  echo "  SKIP: jq not available — sidecar-schema requires jq"
  echo "Results: 0 passed, 0 failed"
  exit 0
fi

# shellcheck disable=SC1090
. "$LIB"

# ── is_valid_status: the allowed set ──
ok=1
for s in CLEARED ANONYMIZED OVERRIDE LOCAL_MODE HALTED NEEDS_REVIEW "NEEDS_REVIEW:GREEN" "NEEDS_REVIEW:RED"; do
  is_valid_status "$s" || { ok=0; echo "    rejected a valid status: $s"; }
done
[ "$ok" -eq 1 ] && pass "all canonical statuses accepted (incl. NEEDS_REVIEW:LEVEL)" || fail "a canonical status was rejected"

ok=1
for s in BOGUS cleared "" "NEEDS_REVIEW:" REVIEW; do
  is_valid_status "$s" && { ok=0; echo "    accepted an invalid status: '$s'"; }
done
[ "$ok" -eq 1 ] && pass "invalid/typoed/empty statuses rejected" || fail "an invalid status was accepted"

# ── validate_sidecar_schema: whole-file validation ──
TMP="$(mktemp -d -t sidecar.XXXXXX)"; trap 'rm -rf "$TMP"' EXIT

printf '{"/d/a.csv":"CLEARED","/d/b.dta":"NEEDS_REVIEW:RED"}' > "$TMP/valid.json"
validate_sidecar_schema "$TMP/valid.json" >/dev/null 2>&1
[ $? -eq 0 ] && pass "fully-valid sidecar → rc 0" || fail "valid sidecar wrongly rejected"

printf '{"/d/a.csv":{"nested":"obj"}}' > "$TMP/obj.json"
validate_sidecar_schema "$TMP/obj.json" >/dev/null 2>&1
[ $? -eq 1 ] && pass "object-valued entry (non-string) → rc 1" || fail "object value not caught"

printf '{"/d/a.csv":"TYPOED_STATUS"}' > "$TMP/typo.json"
validate_sidecar_schema "$TMP/typo.json" >/dev/null 2>&1
[ $? -eq 1 ] && pass "typoed status value → rc 1" || fail "typo status not caught"

validate_sidecar_schema "$TMP/missing.json" >/dev/null 2>&1
[ $? -eq 0 ] && pass "missing sidecar file → rc 0 (nothing to validate)" || fail "missing file wrongly failed"

# ── _safety_level meta key (safety-tier plumbing) ──
printf '{"/d/a.csv":"CLEARED","_safety_level":"strict"}' > "$TMP/lvl-ok.json"
validate_sidecar_schema "$TMP/lvl-ok.json" >/dev/null 2>&1
[ $? -eq 0 ] && pass "_safety_level=strict accepted → rc 0" || fail "valid _safety_level wrongly rejected"

printf '{"/d/a.csv":"CLEARED","_safety_level":"bogus"}' > "$TMP/lvl-bad.json"
validate_sidecar_schema "$TMP/lvl-bad.json" >/dev/null 2>&1
[ $? -eq 1 ] && pass "_safety_level=bogus → rc 1 (strictness preserved)" || fail "bad _safety_level not caught"

printf '{"/d/a.csv":"CLEARED","_unknown_meta":"x"}' > "$TMP/meta-bad.json"
validate_sidecar_schema "$TMP/meta-bad.json" >/dev/null 2>&1
[ $? -eq 1 ] && pass "unknown _meta key → rc 1 (typo-safe)" || fail "unknown meta key not caught"

# ── resolve_safety_level: project key > env > default ──
[ "$(resolve_safety_level "$TMP/lvl-ok.json")" = "strict" ] && pass "resolve: project _safety_level wins" || fail "resolve project level"
printf '{}' > "$TMP/empty.json"
[ "$(resolve_safety_level "$TMP/empty.json")" = "standard" ] && pass "resolve: default standard when unset" || fail "resolve default"
[ "$(SCHOLAR_SAFETY_LEVEL=lockdown resolve_safety_level "$TMP/empty.json")" = "lockdown" ] && pass "resolve: env fallback" || fail "resolve env fallback"

echo ""
echo "════════════════════"
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1
exit 0
