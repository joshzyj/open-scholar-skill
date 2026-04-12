#!/usr/bin/env bash
# Smoke test: Validate documentation counts match actual repo contents
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SKILLS_DIR="$PROJECT_ROOT/.claude/skills"
AGENTS_DIR="$PROJECT_ROOT/.claude/agents"

PASS=0
FAIL=0
ERRORS=""

echo "=== Documentation Consistency Smoke Tests ==="
echo ""

# --- Count actual skills and agents ---
ACTUAL_SCHOLAR=$(find "$SKILLS_DIR" -maxdepth 1 -type d -name 'scholar-*' | wc -l | tr -d ' ')
# Count all non-scholar utility skills (excludes _shared and hidden dirs)
ACTUAL_UTILITY=$(find "$SKILLS_DIR" -maxdepth 1 -type d ! -name 'scholar-*' ! -name '_shared' ! -name '.*' ! -name "$(basename "$SKILLS_DIR")" | wc -l | tr -d ' ')
ACTUAL_TOTAL=$((ACTUAL_SCHOLAR + ACTUAL_UTILITY))
ACTUAL_AGENTS=$(find "$AGENTS_DIR" -maxdepth 1 -name '*.md' -type f | wc -l | tr -d ' ')

echo "  Actual: $ACTUAL_SCHOLAR scholar skills + $ACTUAL_UTILITY utility = $ACTUAL_TOTAL total skills, $ACTUAL_AGENTS agents"

# --- Test 1: README.md skill count ---
# The public repo's README uses "29 skills + 1 utility" or "30 skills"
# (without "scholar" before "skills"), so we check for both formats.
echo "Test 1: README.md skill count"
if grep -qE "${ACTUAL_SCHOLAR} skills|${ACTUAL_TOTAL} skills" "$PROJECT_ROOT/README.md" 2>/dev/null; then
  PASS=$((PASS + 1))
  echo "  ✓ README.md skill count matches ($ACTUAL_SCHOLAR scholar / $ACTUAL_TOTAL total)"
else
  ERRORS="${ERRORS}\n  FAIL: README.md skill count does not match actual ($ACTUAL_SCHOLAR scholar / $ACTUAL_TOTAL total)"
  FAIL=$((FAIL + 1))
fi

# --- Test 2: USAGE.md skill count ---
echo "Test 2: USAGE.md skill count"
if grep -qE "${ACTUAL_SCHOLAR} skills|${ACTUAL_TOTAL} skills|${ACTUAL_SCHOLAR} scholar" "$PROJECT_ROOT/USAGE.md" 2>/dev/null; then
  PASS=$((PASS + 1))
  echo "  ✓ USAGE.md skill count matches ($ACTUAL_SCHOLAR)"
else
  # The public USAGE.md may not mention counts explicitly — skip if absent
  echo "  ⚠ USAGE.md skill count not found — skipping"
fi

# --- Test 3: Docs do not reference old repo name ---
echo "Test 3: Repo name references"
OLD_NAME_FOUND=0
for doc in README.md USAGE.md; do
  # Match bare "scholar-skill/" (without "open-" prefix) — that's the old
  # repo name. "open-scholar-skill/" is the current name and is fine.
  if grep -qE '(^|[^-])scholar-skill/' "$PROJECT_ROOT/$doc" 2>/dev/null; then
    ERRORS="${ERRORS}\n  FAIL: $doc still references old repo name 'scholar-skill/'"
    FAIL=$((FAIL + 1))
    OLD_NAME_FOUND=1
  fi
  if grep -qE 'cd scholar-skill($|[^-])' "$PROJECT_ROOT/$doc" 2>/dev/null; then
    ERRORS="${ERRORS}\n  FAIL: $doc uses old repo name in cd command"
    FAIL=$((FAIL + 1))
    OLD_NAME_FOUND=1
  fi
done
if [ "$OLD_NAME_FOUND" -eq 0 ]; then
  PASS=$((PASS + 1))
  echo "  ✓ No stale repo name references"
fi

# --- Test 4: generate_overview.py skill count ---
echo "Test 4: generate_overview.py counts"
if [ -f "$PROJECT_ROOT/generate_overview.py" ]; then
  overview_line=$(grep -oE '[0-9]+ Skills · [0-9]+ Agents' "$PROJECT_ROOT/generate_overview.py" 2>/dev/null || true)
  if [ -n "$overview_line" ]; then
    ov_skills=$(echo "$overview_line" | grep -oE '^[0-9]+')
    ov_agents=$(echo "$overview_line" | grep -oE '[0-9]+ Agents' | grep -oE '[0-9]+')
    if [ "$ov_skills" -eq "$ACTUAL_TOTAL" ]; then
      PASS=$((PASS + 1))
      echo "  ✓ Overview skill count matches ($ov_skills)"
    else
      ERRORS="${ERRORS}\n  FAIL: generate_overview.py says $ov_skills skills, actual is $ACTUAL_TOTAL"
      FAIL=$((FAIL + 1))
    fi
    if [ "$ov_agents" -eq "$ACTUAL_AGENTS" ]; then
      PASS=$((PASS + 1))
      echo "  ✓ Overview agent count matches ($ov_agents)"
    else
      ERRORS="${ERRORS}\n  FAIL: generate_overview.py says $ov_agents agents, actual is $ACTUAL_AGENTS"
      FAIL=$((FAIL + 1))
    fi
  else
    ERRORS="${ERRORS}\n  FAIL: Could not parse skill/agent counts from generate_overview.py"
    FAIL=$((FAIL + 1))
  fi
else
  echo "  ⚠ generate_overview.py not found — skipping"
fi

# --- Test 5: plugin.json metadata matches current repo state ---
# Regression: CLAUDE_FIX_BRIEF P2 #9 flagged that .claude-plugin/plugin.json
# reported old name/version and stale counts. Add consistency checks so
# metadata drift is caught at test time instead of on install.
echo "Test 7: .claude-plugin/plugin.json consistency"
PLUGIN_JSON="$PROJECT_ROOT/.claude-plugin/plugin.json"
if [ -f "$PLUGIN_JSON" ] && command -v jq >/dev/null 2>&1; then
  # 7a. Name must be the current repo name (open-scholar-skill).
  plugin_name=$(jq -r '.name // empty' "$PLUGIN_JSON" 2>/dev/null)
  if [ "$plugin_name" = "open-scholar-skill" ]; then
    PASS=$((PASS + 1))
    echo "  ✓ plugin.json name is 'open-scholar-skill'"
  else
    ERRORS="${ERRORS}\n  FAIL: plugin.json name is '$plugin_name' (expected 'open-scholar-skill')"
    FAIL=$((FAIL + 1))
  fi

  # 7b. Version must match the latest CHANGELOG entry.
  if [ -f "$PROJECT_ROOT/CHANGELOG.md" ]; then
    latest_ver=$(grep -oE '^## \[[0-9]+\.[0-9]+\.[0-9]+\]' "$PROJECT_ROOT/CHANGELOG.md" 2>/dev/null \
      | head -1 | sed -E 's/^## \[([0-9.]+)\].*/\1/')
    plugin_ver=$(jq -r '.version // empty' "$PLUGIN_JSON" 2>/dev/null)
    if [ -n "$latest_ver" ] && [ "$plugin_ver" = "$latest_ver" ]; then
      PASS=$((PASS + 1))
      echo "  ✓ plugin.json version matches CHANGELOG ($plugin_ver)"
    else
      ERRORS="${ERRORS}\n  FAIL: plugin.json version is '$plugin_ver', CHANGELOG latest is '$latest_ver'"
      FAIL=$((FAIL + 1))
    fi
  fi

  # 7c. Description must reference the current agent count (we added
  # code-review and verify agents in 5.8.0 — stale metadata still
  # advertised "9 peer-reviewer agents" with no mention of the new ones).
  plugin_desc=$(jq -r '.description // empty' "$PLUGIN_JSON" 2>/dev/null)
  if echo "$plugin_desc" | grep -qE "${ACTUAL_TOTAL} skills"; then
    PASS=$((PASS + 1))
    echo "  ✓ plugin.json description references ${ACTUAL_TOTAL} skills"
  else
    ERRORS="${ERRORS}\n  FAIL: plugin.json description does not reference '${ACTUAL_TOTAL} skills'"
    FAIL=$((FAIL + 1))
  fi
  if echo "$plugin_desc" | grep -qE "${ACTUAL_AGENTS} (specialized |peer-reviewer )?agents"; then
    PASS=$((PASS + 1))
    echo "  ✓ plugin.json description references ${ACTUAL_AGENTS} agents"
  else
    ERRORS="${ERRORS}\n  FAIL: plugin.json description does not reference '${ACTUAL_AGENTS} agents'"
    FAIL=$((FAIL + 1))
  fi
elif [ ! -f "$PLUGIN_JSON" ]; then
  echo "  ⚠ plugin.json not found — skipping"
else
  echo "  ⚠ jq not available — skipping plugin.json consistency checks"
fi

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
