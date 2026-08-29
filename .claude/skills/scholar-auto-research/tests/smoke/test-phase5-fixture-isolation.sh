#!/usr/bin/env bash
# F20 harness regression: Phase 5 unit/integration tests must use the vendored
# lightweight seed and never discover or materialize a global /tmp fixture.
set -euo pipefail

SKILL_DIR="${SCHOLAR_AUTO_RESEARCH_TEST_SKILL_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
LAYER="$SKILL_DIR/tests/smoke/test-layer1-design-aware.sh"
RESOLVER="$SKILL_DIR/tests/smoke/test-phase5-skill-resolver.sh"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/scholar-auto-research-fixture-isolation.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

for test_file in "$LAYER" "$RESOLVER"; do
  [ -f "$test_file" ] || fail "missing focused test: $test_file"
  if grep -nE '/tmp/scholar-auto-research-fixture-|auto-research-fixture-test\.sh' "$test_file"; then
    fail "$(basename "$test_file") still discovers/materializes a global fixture"
  fi
  set +e
  out="$(TMPDIR="$TMP_ROOT" bash "$test_file" 2>&1)"
  rc=$?
  set -e
  [ "$rc" -eq 0 ] || fail "$(basename "$test_file") failed in isolated TMPDIR: $out"
  case "$out" in
    *"/tmp/scholar-auto-research-fixture-"*|*"skipped (no /tmp/"*)
      fail "$(basename "$test_file") observed global fixture state: $out" ;;
    *) ;;
  esac
done

echo "PASS: Phase 5 focused tests use only the vendored seed and isolated TMPDIR"
