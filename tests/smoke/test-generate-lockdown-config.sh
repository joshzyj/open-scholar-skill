#!/usr/bin/env bash
# test-generate-lockdown-config.sh — validates scripts/gates/generate-lockdown-config.sh
# (Stage 3 OS-sandbox lockdown generator) without invoking any host API.
# Asserts: correct Claude sandbox.denyRead shape, correct Codex [permissions]
# deny profile, the --allow-escalation flag, non-destructive settings.json merge,
# and refusal to clobber a foreign Codex permissions/default_permissions config.
set -uo pipefail
export LC_ALL=C

HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
export SCHOLAR_SKILL_DIR="$ROOT"
GEN="$ROOT/scripts/gates/generate-lockdown-config.sh"

PASS=0; FAIL=0
pass() { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq required"; exit 0; }
[ -f "$GEN" ] || { echo "FAIL: generator not found at $GEN"; exit 1; }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

# helper: a fresh project with data/raw + a sidecar
mkproj() {
  local p="$1"; mkdir -p "$p/data/raw" "$p/.claude"
  printf 'id,x\n1,2\n' > "$p/data/raw/secret.csv"
  local sec; sec="$(cd "$p/data/raw" && pwd -P)/secret.csv"
  jq -n --arg s "$sec" '{($s):"LOCAL_MODE"}' > "$p/.claude/safety-status.json"
}

echo "=== generate-lockdown-config smoke tests ==="

# ── T1: Claude — hard wall shape ─────────────────────────────────────────
P1="$WORK/p1"; mkproj "$P1"
bash "$GEN" "$P1" --host claude-code >/dev/null 2>&1
S1="$P1/.claude/settings.json"
if jq -e '.sandbox.enabled==true and .sandbox.allowUnsandboxedCommands==false
         and (.sandbox.filesystem.denyRead | index("./data/raw"))
         and (.sandbox.filesystem.denyRead | index("./data/raw/**"))' "$S1" >/dev/null 2>&1; then
  pass "T1 — Claude sandbox denyRead includes data/raw, hard wall (no escalation)"
else
  fail "T1 — Claude sandbox shape wrong: $(jq -c .sandbox "$S1" 2>/dev/null)"
fi

# ── T2: Claude — --allow-escalation flips allowUnsandboxedCommands ────────
P2="$WORK/p2"; mkproj "$P2"
bash "$GEN" "$P2" --host claude-code --allow-escalation >/dev/null 2>&1
if jq -e '.sandbox.allowUnsandboxedCommands==true' "$P2/.claude/settings.json" >/dev/null 2>&1; then
  pass "T2 — --allow-escalation sets allowUnsandboxedCommands=true"
else
  fail "T2 — escalation flag not honored"
fi

# ── T3: Claude — non-destructive merge (preserve existing keys) ──────────
P3="$WORK/p3"; mkproj "$P3"
printf '{"model":"opus","permissions":{"deny":["Read(./secret)"]}}' > "$P3/.claude/settings.json"
bash "$GEN" "$P3" --host claude-code >/dev/null 2>&1
if jq -e '.model=="opus" and (.permissions.deny|index("Read(./secret)")) and .sandbox.enabled==true' "$P3/.claude/settings.json" >/dev/null 2>&1; then
  pass "T3 — merged sandbox, preserved existing model/permissions keys"
else
  fail "T3 — merge clobbered existing settings"
fi

# ── T4: Codex — permissions deny profile shape ───────────────────────────
P4="$WORK/p4"; mkproj "$P4"
bash "$GEN" "$P4" --host codex >/dev/null 2>&1
C4="$P4/.codex/config.toml"
if grep -qF 'default_permissions = "scholar-lockdown"' "$C4" \
   && grep -qE '\[permissions\.scholar-lockdown\.filesystem' "$C4" \
   && grep -qE '"data" = "deny"' "$C4" \
   && grep -qF "scholar-lockdown:BEGIN" "$C4"; then
  pass "T4 — Codex [permissions] deny-on-data profile written"
else
  fail "T4 — Codex profile shape wrong"
fi

# ── T5: Codex — refuse to clobber a foreign default_permissions ──────────
P5="$WORK/p5"; mkproj "$P5"; mkdir -p "$P5/.codex"
printf 'default_permissions = "mine"\n[permissions.mine.filesystem]\n":root" = "read"\n' > "$P5/.codex/config.toml"
BEFORE="$(cksum "$P5/.codex/config.toml")"
bash "$GEN" "$P5" --host codex >/dev/null 2>&1; RC=$?
AFTER="$(cksum "$P5/.codex/config.toml")"
if [ "$RC" -eq 3 ] && [ "$BEFORE" = "$AFTER" ]; then
  pass "T5 — refused to clobber foreign default_permissions (exit 3, unchanged)"
else
  fail "T5 — expected exit 3 + unchanged; got rc=$RC changed=$([ "$BEFORE" = "$AFTER" ] && echo no || echo yes)"
fi

# ── T6: idempotent Codex refresh (byte-stable) ───────────────────────────
SUM1="$(cksum "$C4")"; bash "$GEN" "$P4" --host codex >/dev/null 2>&1; SUM2="$(cksum "$C4")"
[ "$SUM1" = "$SUM2" ] && pass "T6 — Codex refresh byte-stable" || fail "T6 — Codex refresh not idempotent"

# ── T7: no data dirs → error (exit 1), no config written ─────────────────
P7="$WORK/p7"; mkdir -p "$P7/.claude"; printf '{}' > "$P7/.claude/safety-status.json"
bash "$GEN" "$P7" --host both >/dev/null 2>&1; RC=$?
[ "$RC" -eq 1 ] && [ ! -f "$P7/.codex/config.toml" ] && pass "T7 — no data dirs → exit 1, nothing written" \
  || fail "T7 — expected exit 1 with no output; got rc=$RC"

# ── T8: Codex — restricted sidecar file OUTSIDE data/ gets a per-file deny ──
P8="$WORK/p8"; mkproj "$P8"; mkdir -p "$P8/materials"
printf 'x\n' > "$P8/materials/notes.txt"
MAT="$(cd "$P8/materials" && pwd -P)/notes.txt"
jq --arg m "$MAT" '. + {($m):"HALTED"}' "$P8/.claude/safety-status.json" > "$P8/.claude/ss.tmp" && mv "$P8/.claude/ss.tmp" "$P8/.claude/safety-status.json"
bash "$GEN" "$P8" --host codex >/dev/null 2>&1
if grep -qE '"materials/notes\.txt" = "deny"' "$P8/.codex/config.toml"; then
  pass "T8 — Codex profile denies restricted sidecar file outside data/ (materials/notes.txt)"
else
  fail "T8 — outside-data file not denied: $(grep -A6 workspace_roots "$P8/.codex/config.toml" 2>/dev/null | tr '\n' '|')"
fi

# ── T9: Claude — same outside-data file appears as an absolute denyRead ──────
bash "$GEN" "$P8" --host claude-code >/dev/null 2>&1
if jq -e --arg m "$MAT" '.sandbox.filesystem.denyRead | index($m)' "$P8/.claude/settings.json" >/dev/null 2>&1; then
  pass "T9 — Claude denyRead includes the absolute outside-data file"
else
  fail "T9 — Claude denyRead missing the outside-data file"
fi

echo ""
echo "=== generate-lockdown-config: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
