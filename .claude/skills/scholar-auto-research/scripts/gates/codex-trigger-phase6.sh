#!/usr/bin/env bash
# codex-trigger-phase6.sh — auto-research Phase 6 codex cross-model review gate.
# Self-contained within scholar-auto-research; calls the sibling
# codex-trigger-check.sh in this same gates/ dir.
#
# Called by auto-research-verify.sh `run_external_gate("codex-trigger-phase6.sh", ...)`.
# Emits STATUS=GREEN|YELLOW|RED on stdout.

set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "STATUS=RED"
  echo "REASON=usage_error"
  echo "DETAIL: usage: codex-trigger-phase6.sh <project_dir>"
  exit 2
fi

PROJ="$1"
GATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SIBLING="$GATE_DIR/codex-trigger-check.sh"

if [ ! -x "$SIBLING" ]; then
  echo "STATUS=RED"
  echo "REASON=sibling_gate_missing"
  echo "DETAIL: $SIBLING not executable"
  exit 2
fi

exec bash "$SIBLING" "$PROJ" ar-6
