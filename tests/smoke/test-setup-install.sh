#!/usr/bin/env bash
# Smoke tests for setup.sh installation behavior.
#
# These tests drive setup.sh against a throwaway $HOME so the real
# user's ~/.claude/ is never touched. They cover the two regressions
# called out in CLAUDE_FIX_BRIEF P1 #5 and #6:
#
#   1. setup.sh must register the PreToolUse data-safety hook in
#      ~/.claude/settings.json (earlier versions only documented it).
#   2. setup.sh must succeed when ~/.claude/skills/ and ~/.claude/agents/
#      already exist as real directories (earlier versions exited 1).

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SETUP="${REPO_ROOT}/setup.sh"

if [ ! -f "$SETUP" ]; then
  echo "FATAL: setup.sh not found at $SETUP"
  exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not installed — setup.sh hook merge requires jq."
  exit 0
fi

TMPDIR_BASE="$(mktemp -d -t setup-smoke.XXXXXX)"

# setup.sh unconditionally writes $REPO_ROOT/.env. That's a side effect
# we don't want a smoke test to have on the developer's working copy.
# Back up the existing .env (if any) and restore it on exit.
ENV_BACKUP=""
if [ -f "$REPO_ROOT/.env" ]; then
  ENV_BACKUP="$TMPDIR_BASE/env-backup"
  cp "$REPO_ROOT/.env" "$ENV_BACKUP"
fi
restore_env() {
  if [ -n "$ENV_BACKUP" ] && [ -f "$ENV_BACKUP" ]; then
    cp "$ENV_BACKUP" "$REPO_ROOT/.env"
  else
    rm -f "$REPO_ROOT/.env"
  fi
}
trap 'restore_env; rm -rf "$TMPDIR_BASE"' EXIT

PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

echo "=== setup.sh Install Smoke Tests ==="
echo "Setup: $SETUP"
echo ""

# ─── Test 1: Hook registration in fresh HOME ───────────────────────────
# P1 #5: setup.sh must write a PreToolUse hook to ~/.claude/settings.json.
echo "Test 1: Hook registered in fresh ~/.claude/settings.json"
FAKE_HOME_1="$TMPDIR_BASE/home1"
mkdir -p "$FAKE_HOME_1"
# Feed empty answers to skip all interactive prompts.
HOME="$FAKE_HOME_1" bash "$SETUP" </dev/null >"$TMPDIR_BASE/setup1.log" 2>&1
RC1=$?
if [ "$RC1" != "0" ]; then
  fail "setup.sh exited $RC1 in fresh HOME"
  sed 's/^/    /' "$TMPDIR_BASE/setup1.log" | tail -30
else
  pass "setup.sh ran to completion"
fi
SETTINGS_1="$FAKE_HOME_1/.claude/settings.json"
if [ -f "$SETTINGS_1" ]; then
  pass "~/.claude/settings.json created"
  if jq -e '.hooks.PreToolUse' "$SETTINGS_1" >/dev/null 2>&1; then
    pass "settings.json has hooks.PreToolUse"
  else
    fail "settings.json missing hooks.PreToolUse"
    cat "$SETTINGS_1" | sed 's/^/    /'
  fi
  GUARD_CMD=$(jq -r '.hooks.PreToolUse[0].hooks[0].command // empty' "$SETTINGS_1" 2>/dev/null)
  case "$GUARD_CMD" in
    */scripts/gates/pretooluse-data-guard.sh) pass "hook command points to pretooluse-data-guard.sh" ;;
    *) fail "hook command was '$GUARD_CMD' (expected */pretooluse-data-guard.sh)" ;;
  esac
  MATCHER=$(jq -r '.hooks.PreToolUse[0].matcher // empty' "$SETTINGS_1" 2>/dev/null)
  case "$MATCHER" in
    *Read*) pass "hook matcher includes Read" ;;
    *) fail "hook matcher was '$MATCHER' (expected to include Read)" ;;
  esac
else
  fail "~/.claude/settings.json was not created"
fi

# ─── Test 2: Preexisting ~/.claude/skills and ~/.claude/agents ─────────
# P1 #6: earlier setup.sh exited 1 when these were real directories.
echo ""
echo "Test 2: setup.sh survives preexisting ~/.claude/skills and agents"
FAKE_HOME_2="$TMPDIR_BASE/home2"
mkdir -p "$FAKE_HOME_2/.claude/skills" "$FAKE_HOME_2/.claude/agents"
# Plant a user skill the installer must NOT clobber.
mkdir -p "$FAKE_HOME_2/.claude/skills/my-custom-skill"
echo "# My skill" > "$FAKE_HOME_2/.claude/skills/my-custom-skill/SKILL.md"
HOME="$FAKE_HOME_2" bash "$SETUP" </dev/null >"$TMPDIR_BASE/setup2.log" 2>&1
RC2=$?
if [ "$RC2" = "0" ]; then
  pass "setup.sh exited 0 with preexisting real skill/agent dirs"
else
  fail "setup.sh exited $RC2 with preexisting real dirs"
  sed 's/^/    /' "$TMPDIR_BASE/setup2.log" | tail -30
fi
# User's custom skill must still exist untouched.
if [ -f "$FAKE_HOME_2/.claude/skills/my-custom-skill/SKILL.md" ]; then
  pass "user's pre-existing skill survived install"
else
  fail "user's pre-existing skill was clobbered"
fi
# At least one of the scholar-* skills should be linked in.
if [ -e "$FAKE_HOME_2/.claude/skills/scholar-init" ]; then
  pass "scholar-init installed alongside user skill"
else
  fail "scholar-init not installed into preexisting skills dir"
fi
# settings.json still got the hook.
if jq -e '.hooks.PreToolUse' "$FAKE_HOME_2/.claude/settings.json" >/dev/null 2>&1; then
  pass "hook registered on second fake HOME"
else
  fail "hook NOT registered on second fake HOME"
fi

# ─── Test 3: Re-run idempotency — merge preserves other keys ───────────
echo ""
echo "Test 3: Re-running setup.sh preserves unrelated settings.json keys"
FAKE_HOME_3="$TMPDIR_BASE/home3"
mkdir -p "$FAKE_HOME_3/.claude"
cat > "$FAKE_HOME_3/.claude/settings.json" <<'JSON'
{
  "theme": "dark",
  "unrelatedKey": {"hello": "world"}
}
JSON
HOME="$FAKE_HOME_3" bash "$SETUP" </dev/null >"$TMPDIR_BASE/setup3.log" 2>&1
RC3=$?
[ "$RC3" = "0" ] && pass "setup.sh exited 0 with preexisting settings.json" || fail "setup.sh exited $RC3"
if jq -e '.theme == "dark"' "$FAKE_HOME_3/.claude/settings.json" >/dev/null 2>&1; then
  pass "theme key preserved across hook merge"
else
  fail "theme key lost — merge clobbered settings"
fi
if jq -e '.unrelatedKey.hello == "world"' "$FAKE_HOME_3/.claude/settings.json" >/dev/null 2>&1; then
  pass "nested unrelated keys preserved"
else
  fail "nested keys lost"
fi
if jq -e '.hooks.PreToolUse' "$FAKE_HOME_3/.claude/settings.json" >/dev/null 2>&1; then
  pass "hook added to preexisting settings.json"
else
  fail "hook not added to preexisting settings.json"
fi

# Run setup.sh AGAIN — make sure we don't duplicate the hook entry.
HOME="$FAKE_HOME_3" bash "$SETUP" </dev/null >"$TMPDIR_BASE/setup3b.log" 2>&1
HOOK_COUNT=$(jq '.hooks.PreToolUse | map(select(.hooks // [] | map(.command | test("pretooluse-data-guard.sh")) | any)) | length' "$FAKE_HOME_3/.claude/settings.json" 2>/dev/null)
if [ "${HOOK_COUNT:-0}" = "1" ]; then
  pass "re-running setup.sh leaves exactly one hook entry (idempotent)"
else
  fail "re-run produced $HOOK_COUNT hook entries (expected 1)"
fi

echo ""
echo "════════════════════"
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  echo ">>> FAILED"
  exit 1
else
  echo ">>> PASSED"
  exit 0
fi
