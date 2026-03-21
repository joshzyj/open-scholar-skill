#!/usr/bin/env bash
# Smoke test: Validate module routing tables match actual module files
# Checks scholar-compute and scholar-analyze routing consistency
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SKILLS_DIR="$PROJECT_ROOT/.claude/skills"

PASS=0
FAIL=0
ERRORS=""

echo "=== Module Routing Smoke Tests ==="
echo ""

# --- Test 1: scholar-compute module files exist ---
echo "Test 1: scholar-compute module files"
COMPUTE_REFS="$SKILLS_DIR/scholar-compute/references"
for i in 01-nlp 02-ml 03-network 04-abm 05-reproducibility 06-cv 07-llm-analysis 08-synthetic-data 09-geospatial 10-audio 11-life2vec; do
  if [ -f "$COMPUTE_REFS/module-${i}.md" ]; then
    # Verify non-empty
    lines=$(wc -l < "$COMPUTE_REFS/module-${i}.md" | tr -d ' ')
    if [ "$lines" -gt 10 ]; then
      PASS=$((PASS + 1))
    else
      ERRORS="${ERRORS}\n  FAIL: module-${i}.md has only $lines lines (suspiciously short)"
      FAIL=$((FAIL + 1))
    fi
  else
    ERRORS="${ERRORS}\n  FAIL: module-${i}.md not found"
    FAIL=$((FAIL + 1))
  fi
done

# --- Test 2: scholar-compute SKILL.md references all modules ---
echo "Test 2: scholar-compute routing table completeness"
COMPUTE_SKILL="$SKILLS_DIR/scholar-compute/SKILL.md"
for i in 01-nlp 02-ml 03-network 04-abm 05-reproducibility 06-cv 07-llm-analysis 08-synthetic-data 09-geospatial 10-audio 11-life2vec; do
  if grep -q "module-${i}.md" "$COMPUTE_SKILL" 2>/dev/null; then
    PASS=$((PASS + 1))
  else
    ERRORS="${ERRORS}\n  FAIL: scholar-compute SKILL.md does not reference module-${i}.md"
    FAIL=$((FAIL + 1))
  fi
done

# --- Test 3: scholar-analyze component files exist ---
echo "Test 3: scholar-analyze component files"
ANALYZE_REFS="$SKILLS_DIR/scholar-analyze/references"
for comp in core regression bayesian export-robustness specialized verification; do
  if [ -f "$ANALYZE_REFS/component-a-${comp}.md" ]; then
    lines=$(wc -l < "$ANALYZE_REFS/component-a-${comp}.md" | tr -d ' ')
    if [ "$lines" -gt 5 ]; then
      PASS=$((PASS + 1))
    else
      ERRORS="${ERRORS}\n  FAIL: component-a-${comp}.md has only $lines lines"
      FAIL=$((FAIL + 1))
    fi
  else
    ERRORS="${ERRORS}\n  FAIL: component-a-${comp}.md not found"
    FAIL=$((FAIL + 1))
  fi
done

# --- Test 4: scholar-causal strategies file exists ---
echo "Test 4: scholar-causal strategies file"
CAUSAL_STRAT="$SKILLS_DIR/scholar-causal/references/strategies.md"
if [ -f "$CAUSAL_STRAT" ]; then
  lines=$(wc -l < "$CAUSAL_STRAT" | tr -d ' ')
  # Should have all 13 strategies
  strat_count=$(grep -c '^### Strategy' "$CAUSAL_STRAT" 2>/dev/null || true)
  if [ "$strat_count" -ge 13 ]; then
    PASS=$((PASS + 1))
    echo "  Found $strat_count strategies in strategies.md"
  else
    ERRORS="${ERRORS}\n  FAIL: strategies.md has only $strat_count strategies (expected 13)"
    FAIL=$((FAIL + 1))
  fi
else
  ERRORS="${ERRORS}\n  FAIL: scholar-causal/references/strategies.md not found"
  FAIL=$((FAIL + 1))
fi

# --- Test 5: No MODULE headers remain in slimmed SKILL.md files ---
echo "Test 5: Verify modules were fully extracted"
for skill in scholar-compute scholar-ling; do
  module_headers=$(grep -c '^## MODULE [1-9]' "$SKILLS_DIR/$skill/SKILL.md" 2>/dev/null || true)
  if [ "$module_headers" -gt 0 ]; then
    ERRORS="${ERRORS}\n  FAIL: $skill/SKILL.md still contains $module_headers MODULE headers (should be in references/)"
    FAIL=$((FAIL + 1))
  else
    PASS=$((PASS + 1))
  fi
done
# scholar-analyze: check no COMPONENT A subsections remain (A3-A9 headers)
analyze_a_headers=$(grep -c '^### A[3-9]' "$SKILLS_DIR/scholar-analyze/SKILL.md" 2>/dev/null || true)
if [ "$analyze_a_headers" -gt 0 ]; then
  ERRORS="${ERRORS}\n  FAIL: scholar-analyze/SKILL.md still contains $analyze_a_headers Component A section headers"
  FAIL=$((FAIL + 1))
else
  PASS=$((PASS + 1))
fi
# scholar-causal: check no Strategy deep-dive headers remain
causal_strat_headers=$(grep -c '^### Strategy [0-9]' "$SKILLS_DIR/scholar-causal/SKILL.md" 2>/dev/null || true)
if [ "$causal_strat_headers" -gt 0 ]; then
  ERRORS="${ERRORS}\n  FAIL: scholar-causal/SKILL.md still contains $causal_strat_headers Strategy headers"
  FAIL=$((FAIL + 1))
else
  PASS=$((PASS + 1))
fi

# --- Test 6: scholar-ling module files exist and routing table references them ---
echo "Test 6: scholar-ling module files"
LING_REFS="$SKILLS_DIR/scholar-ling/references"
LING_SKILL="$SKILLS_DIR/scholar-ling/SKILL.md"
for i in 01-theory 02-quantitative 03-qualitative 04-attitudes 05-corpus 06-computational 07-experimental 08-biber-mda 09-tts-mgt; do
  if [ -f "$LING_REFS/module-${i}.md" ]; then
    lines=$(wc -l < "$LING_REFS/module-${i}.md" | tr -d ' ')
    if [ "$lines" -gt 10 ]; then
      PASS=$((PASS + 1))
    else
      ERRORS="${ERRORS}\n  FAIL: scholar-ling module-${i}.md has only $lines lines"
      FAIL=$((FAIL + 1))
    fi
  else
    ERRORS="${ERRORS}\n  FAIL: scholar-ling module-${i}.md not found"
    FAIL=$((FAIL + 1))
  fi
  # Check routing table reference
  if grep -q "module-${i}.md" "$LING_SKILL" 2>/dev/null; then
    PASS=$((PASS + 1))
  else
    ERRORS="${ERRORS}\n  FAIL: scholar-ling SKILL.md does not reference module-${i}.md"
    FAIL=$((FAIL + 1))
  fi
done

# --- Summary ---
echo ""
echo "=== Results ==="
echo "  PASS: $PASS"
echo "  FAIL: $FAIL"

if [ "$FAIL" -gt 0 ]; then
  echo ""
  echo "Failures:"
  echo -e "$ERRORS"
  exit 1
else
  echo "  All checks passed."
  exit 0
fi
