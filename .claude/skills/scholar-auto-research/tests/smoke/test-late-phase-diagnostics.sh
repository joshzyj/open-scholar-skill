#!/usr/bin/env bash
# Regression for F18: diagnostics inside Phase 18 and Phase 19 verifier blocks
# must identify the phase that is actually running and the true upstream owner.
set -euo pipefail

SKILL_DIR="${SCHOLAR_AUTO_RESEARCH_TEST_SKILL_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
VERIFY="$SKILL_DIR/scripts/auto-research-verify.sh"
[ -f "$VERIFY" ] || { echo "FATAL: missing $VERIFY" >&2; exit 1; }

python3 - "$VERIFY" <<'PY'
import sys
text = open(sys.argv[1], encoding="utf-8").read()

def block(phase, next_phase):
    start_token = f'if phase_id == "{phase}":'
    end_token = f'if phase_id == "{next_phase}":'
    start = text.find(start_token)
    end = text.find(end_token, start + len(start_token))
    if start < 0 or end < 0:
        raise SystemExit(f"FAIL: could not isolate Phase {phase} verifier block")
    return text[start:end]

p18 = block("18", "19")
p19 = block("19", "20")
checks = {
    'Phase-18 block containing "FAIL: Phase 17"': p18.count("FAIL: Phase 17"),
    'Phase-18 block containing "Phase 17 checker"': p18.count("Phase 17 checker"),
    'Phase-18 block containing "Phase 12 scholar-polish report"': p18.count("Phase 12 scholar-polish report"),
    'Phase-19 block containing "FAIL: Phase 18"': p19.count("FAIL: Phase 18"),
}
bad = False
for label, count in checks.items():
    print(f"{label}: {count}")
    bad = bad or count != 0
correct = {
    'Phase-18 block containing "FAIL: Phase 18"': (p18.count("FAIL: Phase 18"), 75),
    'Phase-18 block containing "Phase 18 checker"': (p18.count("Phase 18 checker"), 1),
    'Phase-18 block containing "Phase 13 scholar-polish report"': (p18.count("Phase 13 scholar-polish report"), 1),
    'Phase-19 block containing "FAIL: Phase 19"': (p19.count("FAIL: Phase 19"), 97),
    'Phase-19 authenticity diagnostic': (p19.count("FAIL: Phase 19 final deliverable authenticity checks failed"), 1),
}
for label, (count, expected) in correct.items():
    print(f"{label}: {count} (expected {expected})")
    bad = bad or count != expected
if bad:
    raise SystemExit(1)
PY

echo "PASS: Phase 18/19 diagnostics identify their actual phases and upstream owners"
