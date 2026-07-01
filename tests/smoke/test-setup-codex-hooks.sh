#!/usr/bin/env bash
# test-setup-codex-hooks.sh — validates scripts/phases/setup-codex-hooks.sh:
# creates a project .codex/config.toml PreToolUse hook, is idempotent, appends
# to an existing hookless config, and refuses to clobber a foreign [hooks] table.
set -uo pipefail
export LC_ALL=C

HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
export SCHOLAR_SKILL_DIR="$ROOT"
INSTALLER="$ROOT/scripts/phases/setup-codex-hooks.sh"

PASS=0; FAIL=0
pass() { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

[ -f "$INSTALLER" ] || { echo "FAIL: installer not found at $INSTALLER"; exit 1; }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

echo "=== setup-codex-hooks smoke tests ==="

# ── T1: fresh project → creates config with the hook ─────────────────────
P1="$WORK/p1"; mkdir -p "$P1"
bash "$INSTALLER" "$P1" >/dev/null 2>&1
CFG="$P1/.codex/config.toml"
if [ -f "$CFG" ] \
   && grep -qF "scholar-codex-hooks:BEGIN" "$CFG" \
   && grep -qE '\[\[hooks\.PreToolUse\]\]' "$CFG" \
   && grep -qE "command = \"bash '.*/scripts/gates/codex-pretooluse-hook.sh'\"" "$CFG"; then
  pass "T1 — fresh project created config with bash-quoted hook command"
else
  fail "T1 — config missing/mis-shaped: $(sed -n '1,40p' "$CFG" 2>/dev/null | tr '\n' '|')"
fi
# spaces-safety: the command MUST be wrapped in bash '...' (never a bare path)
if grep -qE '^command = "/' "$CFG"; then
  fail "T1b — command is a BARE path (fails open on spaces)"
else
  pass "T1b — command is not a bare path (bash-wrapped)"
fi

# ── T2: idempotent re-run → byte-stable ──────────────────────────────────
SUM1="$(cksum "$CFG")"
bash "$INSTALLER" "$P1" >/dev/null 2>&1
SUM2="$(cksum "$CFG")"
[ "$SUM1" = "$SUM2" ] && pass "T2 — idempotent re-run byte-stable" \
                      || fail "T2 — re-run changed the file"

# ── T3: existing hookless config → append, preserve prior content ────────
P3="$WORK/p3"; mkdir -p "$P3/.codex"
printf 'model = "gpt-5.5"\napproval_policy = "on-request"\n' > "$P3/.codex/config.toml"
bash "$INSTALLER" "$P3" >/dev/null 2>&1
if grep -qF 'model = "gpt-5.5"' "$P3/.codex/config.toml" \
   && grep -qF "scholar-codex-hooks:BEGIN" "$P3/.codex/config.toml"; then
  pass "T3 — appended hook, preserved existing settings"
else
  fail "T3 — append clobbered or missed existing content"
fi

# ── T4: foreign [hooks] table → refuse (exit 3), do not modify ───────────
P4="$WORK/p4"; mkdir -p "$P4/.codex"
printf '[[hooks.PreToolUse]]\nmatcher = ".*"\n[[hooks.PreToolUse.hooks]]\ntype = "command"\ncommand = "echo mine"\n' > "$P4/.codex/config.toml"
BEFORE="$(cksum "$P4/.codex/config.toml")"
bash "$INSTALLER" "$P4" >/dev/null 2>&1; RC=$?
AFTER="$(cksum "$P4/.codex/config.toml")"
if [ "$RC" -eq 3 ] && [ "$BEFORE" = "$AFTER" ]; then
  pass "T4 — refused to clobber foreign [hooks] (exit 3, file unchanged)"
else
  fail "T4 — expected exit 3 + unchanged; got rc=$RC changed=$([ "$BEFORE" = "$AFTER" ] && echo no || echo yes)"
fi

echo ""
echo "=== setup-codex-hooks: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
