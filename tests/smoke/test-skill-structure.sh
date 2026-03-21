#!/usr/bin/env bash
# Smoke test: Validate SKILL.md structure across all skills
# Checks: YAML frontmatter fields, referenced files exist, bash syntax
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SKILLS_DIR="$PROJECT_ROOT/.claude/skills"
AGENTS_DIR="$PROJECT_ROOT/.claude/agents"

PASS=0
FAIL=0
ERRORS=""

echo "=== Skill Structure Smoke Tests ==="
echo ""

# --- Test 1: Every SKILL.md has required frontmatter fields ---
echo "Test 1: YAML frontmatter validation"
for skill_md in "$SKILLS_DIR"/*/SKILL.md; do
  skill_name="$(basename "$(dirname "$skill_md")")"

  # Check frontmatter delimiter
  if ! head -1 "$skill_md" | grep -q '^---$'; then
    ERRORS="${ERRORS}\n  FAIL: $skill_name — missing opening --- in frontmatter"
    FAIL=$((FAIL + 1))
    continue
  fi

  # Extract frontmatter (between first and second ---)
  fm=$(awk 'NR>1 && /^---$/{exit} NR>1{print}' "$skill_md")

  for field in name description user-invocable; do
    if ! echo "$fm" | grep -q "^${field}:"; then
      ERRORS="${ERRORS}\n  FAIL: $skill_name — missing frontmatter field: $field"
      FAIL=$((FAIL + 1))
    else
      PASS=$((PASS + 1))
    fi
  done
done
echo "  Checked $(ls -d "$SKILLS_DIR"/*/SKILL.md 2>/dev/null | wc -l | tr -d ' ') skills"

# --- Test 2: Every agent file has required frontmatter ---
echo "Test 2: Agent frontmatter validation"
for agent_md in "$AGENTS_DIR"/*.md; do
  [ -f "$agent_md" ] || continue
  agent_name="$(basename "$agent_md" .md)"

  if ! head -1 "$agent_md" | grep -q '^---$'; then
    ERRORS="${ERRORS}\n  FAIL: agent/$agent_name — missing opening ---"
    FAIL=$((FAIL + 1))
    continue
  fi

  fm=$(awk 'NR>1 && /^---$/{exit} NR>1{print}' "$agent_md")
  for field in name description; do
    if ! echo "$fm" | grep -q "^${field}:"; then
      ERRORS="${ERRORS}\n  FAIL: agent/$agent_name — missing field: $field"
      FAIL=$((FAIL + 1))
    else
      PASS=$((PASS + 1))
    fi
  done
done
echo "  Checked $(ls "$AGENTS_DIR"/*.md 2>/dev/null | wc -l | tr -d ' ') agents"

# --- Test 3: Referenced files in references/ exist ---
echo "Test 3: Cross-reference validation"
for skill_md in "$SKILLS_DIR"/*/SKILL.md; do
  skill_name="$(basename "$(dirname "$skill_md")")"
  skill_dir="$(dirname "$skill_md")"

  # Find references to local files like references/foo.md
  # Skip cross-skill references (e.g., scholar-citation/references/refmanager-backends.md)
  # which are loaded via $SKILL_DIR paths at runtime, not relative paths
  refs=$(grep -oE 'references/[a-zA-Z0-9_-]+\.md' "$skill_md" 2>/dev/null | sort -u || true)
  for ref in $refs; do
    ref_basename="$(basename "$ref")"
    # Check local first, then check if it exists anywhere in the skills tree (cross-skill ref)
    if [ -f "$skill_dir/$ref" ]; then
      PASS=$((PASS + 1))
    elif find "$SKILLS_DIR" -name "$ref_basename" -type f 2>/dev/null | grep -q .; then
      PASS=$((PASS + 1))  # Cross-skill reference — exists elsewhere
    else
      ERRORS="${ERRORS}\n  FAIL: $skill_name — references missing file: $ref (not found anywhere)"
      FAIL=$((FAIL + 1))
    fi
  done
done

# --- Test 4: Symlinks are intact ---
echo "Test 4: Symlink validation"
for link in skills agents; do
  if [ -L "$PROJECT_ROOT/$link" ]; then
    target=$(readlink "$PROJECT_ROOT/$link")
    if [ -d "$PROJECT_ROOT/$link" ]; then
      PASS=$((PASS + 1))
    else
      ERRORS="${ERRORS}\n  FAIL: $link symlink broken (target: $target)"
      FAIL=$((FAIL + 1))
    fi
  else
    ERRORS="${ERRORS}\n  FAIL: $link is not a symlink"
    FAIL=$((FAIL + 1))
  fi
done

# --- Test 5: Gate scripts are executable ---
echo "Test 5: Gate scripts validation"
for gate in "$PROJECT_ROOT/scripts/gates"/*.sh; do
  [ -f "$gate" ] || continue
  gate_name="$(basename "$gate")"
  if [ -x "$gate" ]; then
    # Syntax check
    if bash -n "$gate" 2>/dev/null; then
      PASS=$((PASS + 1))
    else
      ERRORS="${ERRORS}\n  FAIL: scripts/gates/$gate_name — bash syntax error"
      FAIL=$((FAIL + 1))
    fi
  else
    ERRORS="${ERRORS}\n  FAIL: scripts/gates/$gate_name — not executable"
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
