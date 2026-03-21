#!/usr/bin/env bash
# Run all smoke tests
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OVERALL=0

for test_script in "$SCRIPT_DIR"/test-*.sh; do
  [ -f "$test_script" ] || continue
  echo ""
  echo "========================================"
  echo "Running: $(basename "$test_script")"
  echo "========================================"
  if bash "$test_script"; then
    echo ">>> PASSED"
  else
    echo ">>> FAILED"
    OVERALL=1
  fi
  echo ""
done

if [ "$OVERALL" -eq 0 ]; then
  echo "All smoke tests passed."
else
  echo "Some smoke tests FAILED."
  exit 1
fi
