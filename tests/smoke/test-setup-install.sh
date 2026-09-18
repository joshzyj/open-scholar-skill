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
HOME="$FAKE_HOME_1" bash "$SETUP" --harness claude </dev/null >"$TMPDIR_BASE/setup1.log" 2>&1
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
  # The command MUST be wrapped as `bash '<path>'` — a bare spaced path is
  # word-split by Claude Code and silently fails to execute (fail-open). A
  # regression to the bare form is a hard FAIL.
  case "$GUARD_CMD" in
    "bash '"*"/scripts/gates/pretooluse-data-guard.sh'") pass "PreToolUse command is wrapped: bash '<path>/pretooluse-data-guard.sh' (spaced-path safe)" ;;
    */scripts/gates/pretooluse-data-guard.sh) fail "PreToolUse command is a BARE path '$GUARD_CMD' — must be wrapped 'bash <path>' or it fails open on spaced paths" ;;
    *) fail "PreToolUse command was '$GUARD_CMD' (expected bash '<path>/pretooluse-data-guard.sh')" ;;
  esac
  MATCHER=$(jq -r '.hooks.PreToolUse[0].matcher // empty' "$SETTINGS_1" 2>/dev/null)
  case "$MATCHER" in
    *Read*) pass "hook matcher includes Read" ;;
    *) fail "hook matcher was '$MATCHER' (expected to include Read)" ;;
  esac
  case "$MATCHER" in
    *Bash*) pass "hook matcher includes Bash (Bash channel gated)" ;;
    *) fail "hook matcher was '$MATCHER' (expected to include Bash)" ;;
  esac
  PT_CMD=$(jq -r '.hooks.PostToolUse[0].hooks[0].command // empty' "$SETTINGS_1" 2>/dev/null)
  case "$PT_CMD" in
    "bash '"*"/scripts/gates/posttooluse-output-guard.sh'") pass "PostToolUse redactor registered (wrapped)" ;;
    *) fail "PostToolUse command was '$PT_CMD' (expected bash '<path>/posttooluse-output-guard.sh')" ;;
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
HOME="$FAKE_HOME_2" bash "$SETUP" --harness claude </dev/null >"$TMPDIR_BASE/setup2.log" 2>&1
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
HOME="$FAKE_HOME_3" bash "$SETUP" --harness claude </dev/null >"$TMPDIR_BASE/setup3.log" 2>&1
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
HOME="$FAKE_HOME_3" bash "$SETUP" --harness claude </dev/null >"$TMPDIR_BASE/setup3b.log" 2>&1
HOOK_COUNT=$(jq '.hooks.PreToolUse | map(select(.hooks // [] | map(.command | test("pretooluse-data-guard.sh")) | any)) | length' "$FAKE_HOME_3/.claude/settings.json" 2>/dev/null)
if [ "${HOOK_COUNT:-0}" = "1" ]; then
  pass "re-running setup.sh leaves exactly one hook entry (idempotent)"
else
  fail "re-run produced $HOOK_COUNT hook entries (expected 1)"
fi

# ─── Test 4: ZCode harness — own config file, own schema ───────────────
# ZCode never reads ~/.claude/settings.json. Its hooks live in
# ~/.zcode/cli/config.json under .hooks.events.<Event>, need
# .hooks.enabled=true, and carry a per-hook timeout.
echo ""
echo "Test 4: --harness zcode writes ~/.zcode/cli/config.json in ZCode's schema"
FAKE_HOME_4="$TMPDIR_BASE/home4"
mkdir -p "$FAKE_HOME_4/.zcode/cli"
cat > "$FAKE_HOME_4/.zcode/cli/config.json" <<'JSON'
{
  "mcp": {"servers": {"mine": {"command": "my-mcp"}}},
  "hooks": {
    "enabled": false,
    "events": {
      "PreToolUse": [
        {"matcher": "Bash", "hooks": [{"type": "command", "command": "my-own-hook", "timeout": 5}]}
      ]
    }
  }
}
JSON
ZCFG="$FAKE_HOME_4/.zcode/cli/config.json"
HOME="$FAKE_HOME_4" bash "$SETUP" --harness zcode </dev/null >"$TMPDIR_BASE/setup4.log" 2>&1
RC4=$?
if [ "$RC4" = "0" ]; then
  pass "setup.sh --harness zcode exited 0"
else
  fail "setup.sh --harness zcode exited $RC4"
  sed 's/^/    /' "$TMPDIR_BASE/setup4.log" | tail -30
fi
if jq -e '.hooks.enabled == true' "$ZCFG" >/dev/null 2>&1; then
  pass "zcode: hooks.enabled forced true (a disabled hook table guards nothing)"
else
  fail "zcode: hooks.enabled is not true"
fi
Z_CMD=$(jq -r '[.hooks.events.PreToolUse[].hooks[].command | select(test("pretooluse-data-guard.sh"))][0] // empty' "$ZCFG")
case "$Z_CMD" in
  "bash '"*"/scripts/gates/pretooluse-data-guard.sh'") pass "zcode: guard under .hooks.events.PreToolUse, wrapped bash '<path>'" ;;
  *) fail "zcode: guard command was '$Z_CMD' (expected wrapped form under .hooks.events.PreToolUse)" ;;
esac
if jq -e '[.hooks.events.PreToolUse[] | select(.hooks[].command | test("pretooluse-data-guard.sh"))][0]
          | (.matcher | test("ApplyPatch")) and (.hooks[0].timeout == 30)' "$ZCFG" >/dev/null 2>&1; then
  pass "zcode: matcher uses ZCode tool names (ApplyPatch) and hook has timeout=30"
else
  fail "zcode: matcher/timeout not in ZCode's schema"
fi
# The redactor speaks only Claude's updatedToolOutput wire. Registering it
# where the host ignores that wire would be a fake control — it must be absent.
if jq -e '.hooks.events.PostToolUse // [] | length == 0' "$ZCFG" >/dev/null 2>&1; then
  pass "zcode: PostToolUse redactor NOT registered (host cannot rewrite Bash output)"
else
  fail "zcode: an inert PostToolUse redactor was registered"
fi
if jq -e '.hooks.PreToolUse // null | . == null' "$ZCFG" >/dev/null 2>&1; then
  pass "zcode: nothing written at the Claude path .hooks.PreToolUse"
else
  fail "zcode: hook leaked into Claude's .hooks.PreToolUse path"
fi
if jq -e '.mcp.servers.mine.command == "my-mcp"' "$ZCFG" >/dev/null 2>&1 \
   && jq -e '[.hooks.events.PreToolUse[].hooks[].command] | index("my-own-hook") != null' "$ZCFG" >/dev/null 2>&1; then
  pass "zcode: user's mcp servers and own hook preserved"
else
  fail "zcode: merge clobbered the user's existing config"
fi
if [ -e "$FAKE_HOME_4/.zcode/skills/scholar-init" ] && ls "$FAKE_HOME_4/.zcode/agents/"*.md >/dev/null 2>&1; then
  pass "zcode: skills and agents linked under ~/.zcode/"
else
  fail "zcode: skills/agents not installed under ~/.zcode/"
fi
if [ ! -e "$FAKE_HOME_4/.claude/settings.json" ] && [ ! -e "$FAKE_HOME_4/.claude/skills" ]; then
  pass "zcode: Claude's settings.json and skills/ untouched (harness isolation)"
else
  fail "zcode: a zcode-only install wrote into ~/.claude/"
fi
BAK_COUNT_A=$(find "$FAKE_HOME_4/.zcode/cli" -name 'config.json.bak-*' | wc -l | tr -d ' ')
[ "$BAK_COUNT_A" = "1" ] && pass "zcode: previous config backed up once" \
                         || fail "zcode: expected 1 backup, found $BAK_COUNT_A"
# Re-run: exactly one guard entry, and an unchanged file makes no new backup.
HOME="$FAKE_HOME_4" bash "$SETUP" --harness zcode </dev/null >"$TMPDIR_BASE/setup4b.log" 2>&1
Z_COUNT=$(jq '[.hooks.events.PreToolUse[].hooks[].command | select(test("pretooluse-data-guard.sh"))] | length' "$ZCFG")
BAK_COUNT_B=$(find "$FAKE_HOME_4/.zcode/cli" -name 'config.json.bak-*' | wc -l | tr -d ' ')
if [ "$Z_COUNT" = "1" ] && [ "$BAK_COUNT_B" = "1" ]; then
  pass "zcode: re-run is idempotent (1 guard entry, no new backup)"
else
  fail "zcode: re-run left $Z_COUNT guard entries and $BAK_COUNT_B backups (expected 1 and 1)"
fi

# ─── Test 5: Codex harness — skills only, guard is per-project ─────────
echo ""
echo "Test 5: --harness codex installs skills and writes NO global hook config"
FAKE_HOME_5="$TMPDIR_BASE/home5"
mkdir -p "$FAKE_HOME_5"
HOME="$FAKE_HOME_5" bash "$SETUP" --harness codex </dev/null >"$TMPDIR_BASE/setup5.log" 2>&1
RC5=$?
# Exit 0: the Codex guard is installed per project by /scholar-init, so its
# absence here is by design and must not read as a failed install.
[ "$RC5" = "0" ] && pass "setup.sh --harness codex exited 0" || fail "setup.sh --harness codex exited $RC5"
[ -e "$FAKE_HOME_5/.codex/skills/scholar-init" ] && pass "codex: skills linked under ~/.codex/skills/" \
                                                  || fail "codex: skills not installed under ~/.codex/skills/"
[ ! -e "$FAKE_HOME_5/.codex/agents" ] && pass "codex: no agents/ dir created (Codex does not load agent files)" \
                                      || fail "codex: an unused ~/.codex/agents/ was created"
[ ! -e "$FAKE_HOME_5/.codex/config.toml" ] && pass "codex: user's global config.toml not written" \
                                           || fail "codex: setup.sh wrote ~/.codex/config.toml"
[ ! -e "$FAKE_HOME_5/.claude/settings.json" ] && pass "codex: Claude's settings.json untouched" \
                                              || fail "codex: a codex-only install wrote ~/.claude/settings.json"
if grep -q "PER PROJECT" "$TMPDIR_BASE/setup5.log" && grep -q "codex   guard: per project" "$TMPDIR_BASE/setup5.log"; then
  pass "codex: output says plainly that the guard is per-project"
else
  fail "codex: output does not explain where the Codex guard comes from"
fi

# ─── Test 6: harness selection — all / bad value / auto-detect ─────────
echo ""
echo "Test 6: harness selection"
FAKE_HOME_6="$TMPDIR_BASE/home6"
mkdir -p "$FAKE_HOME_6"
HOME="$FAKE_HOME_6" bash "$SETUP" --harness bogus </dev/null >"$TMPDIR_BASE/setup6.log" 2>&1
RC6=$?
if [ "$RC6" = "2" ] && [ ! -e "$FAKE_HOME_6/.claude" ]; then
  pass "unknown --harness value exits 2 before touching anything"
else
  fail "unknown --harness value: exit $RC6 (expected 2, and no ~/.claude)"
fi
HOME="$FAKE_HOME_6" bash "$SETUP" --harness all </dev/null >"$TMPDIR_BASE/setup6b.log" 2>&1
if [ -e "$FAKE_HOME_6/.claude/skills/scholar-init" ] && [ -e "$FAKE_HOME_6/.codex/skills/scholar-init" ] \
   && [ -e "$FAKE_HOME_6/.zcode/skills/scholar-init" ]; then
  pass "--harness all installs skills for claude, codex and zcode"
else
  fail "--harness all did not install for every harness"
fi
# Auto-detect keys off which config dirs exist. Neutralize the host signals so
# the result does not depend on which harness is running this test.
FAKE_HOME_6C="$TMPDIR_BASE/home6c"
mkdir -p "$FAKE_HOME_6C/.zcode"
env -u ZCODE_SESSION_ID HOME="$FAKE_HOME_6C" SCHOLAR_HOST_AGENT_OVERRIDE=unknown \
  bash "$SETUP" </dev/null >"$TMPDIR_BASE/setup6c.log" 2>&1
if [ -e "$FAKE_HOME_6C/.zcode/cli/config.json" ] && [ ! -e "$FAKE_HOME_6C/.claude/settings.json" ]; then
  pass "auto-detect: only ~/.zcode present → zcode only"
else
  fail "auto-detect did not resolve to zcode-only"
  grep -n "Detected\|Installing for" "$TMPDIR_BASE/setup6c.log" | sed 's/^/    /'
fi

# ─── Test 7: forced redactor is registered but flagged as inert ────────
echo ""
echo "Test 7: SCHOLAR_SETUP_POSTTOOLUSE=force on zcode"
FAKE_HOME_7="$TMPDIR_BASE/home7"
mkdir -p "$FAKE_HOME_7"
HOME="$FAKE_HOME_7" SCHOLAR_SETUP_POSTTOOLUSE=force bash "$SETUP" --harness zcode </dev/null >"$TMPDIR_BASE/setup7.log" 2>&1
if jq -e '.hooks.events.PostToolUse[0].hooks[0].command | test("posttooluse-output-guard.sh")' \
     "$FAKE_HOME_7/.zcode/cli/config.json" >/dev/null 2>&1 && grep -q "INERT" "$TMPDIR_BASE/setup7.log"; then
  pass "force registers the redactor AND warns that it is inert"
else
  fail "force path did not register-and-warn"
fi
if grep -q "zcode   guard: installed · redactor: n/a" "$TMPDIR_BASE/setup7.log"; then
  pass "summary still reports zcode redactor as n/a (force does not claim protection)"
else
  fail "summary overstated the forced redactor"
  grep -n "zcode  " "$TMPDIR_BASE/setup7.log" | sed 's/^/    /'
fi
# Dropping the flag must remove the stale redactor entry, not leave it behind.
HOME="$FAKE_HOME_7" bash "$SETUP" --harness zcode </dev/null >"$TMPDIR_BASE/setup7b.log" 2>&1
if jq -e '.hooks.events.PostToolUse // [] | length == 0' "$FAKE_HOME_7/.zcode/cli/config.json" >/dev/null 2>&1; then
  pass "re-run without force removes the stale redactor entry"
else
  fail "stale forced redactor entry survived a normal re-run"
fi

# ─── Test 8: a second checkout's guard is reported, never removed ──────
# Common on a dev machine: a dev clone and a release clone both registered.
# setup.sh must not delete the other checkout's entry, but two guards both run
# on every tool call, so it has to say so.
echo ""
echo "Test 8: another checkout's guard is preserved and warned about"
FAKE_HOME_8="$TMPDIR_BASE/home8"
mkdir -p "$FAKE_HOME_8/.claude"
OTHER_CMD="bash '/elsewhere/other-checkout/scripts/gates/pretooluse-data-guard.sh'"
jq -n --arg c "$OTHER_CMD" \
  '{hooks: {PreToolUse: [{matcher: "Read|Bash", hooks: [{type: "command", command: $c}]}]}}' \
  > "$FAKE_HOME_8/.claude/settings.json"
HOME="$FAKE_HOME_8" bash "$SETUP" --harness all </dev/null >"$TMPDIR_BASE/setup8.log" 2>&1
GUARD_CMDS=$(jq -r '[.hooks.PreToolUse[].hooks[].command | select(test("pretooluse-data-guard.sh"))] | length' "$FAKE_HOME_8/.claude/settings.json")
if [ "$GUARD_CMDS" = "2" ] && jq -e --arg c "$OTHER_CMD" '[.hooks.PreToolUse[].hooks[].command] | index($c) != null' \
     "$FAKE_HOME_8/.claude/settings.json" >/dev/null 2>&1; then
  pass "other checkout's guard entry left in place alongside ours"
else
  fail "expected 2 guard entries incl. the other checkout's, found $GUARD_CMDS"
fi
if grep -q "another checkout's data guard is also registered" "$TMPDIR_BASE/setup8.log" \
   && grep -qF "/elsewhere/other-checkout/" "$TMPDIR_BASE/setup8.log"; then
  pass "duplicate guard is called out by path"
else
  fail "no warning about the second checkout's guard"
fi

# SETUP_SMOKE_VERBOSE=1 prints what a user actually sees for an all-harness
# install (hook section + summary), for eyeballing wording changes.
if [ "${SETUP_SMOKE_VERBOSE:-0}" = "1" ]; then
  echo ""
  echo "── sample output: --harness all (Test 8 run) ──"
  sed -n '/Registering data-safety hooks/,/Setting up shell environment/p;/Setup Complete/,$p' \
    "$TMPDIR_BASE/setup8.log" | sed 's/^/  | /'
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
