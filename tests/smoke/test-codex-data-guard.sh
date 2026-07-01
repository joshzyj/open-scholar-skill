#!/usr/bin/env bash
# test-codex-data-guard.sh — validates scripts/gates/codex-pretooluse-hook.sh
# (the Codex CLI PreToolUse adapter) WITHOUT invoking the Codex API.
#
# The adapter delegates to pretooluse-data-guard.sh and translates its exit
# code into Codex's decision wire. This test feeds synthetic Codex PreToolUse
# payloads (the exact shape verified live against codex v0.142.5:
# tool_name="Bash", tool_input={command:"..."}, cwd) and asserts:
#   - sensitive reads (LOCAL_MODE / HALTED / raw-data path)  → exit 2 + deny wire
#   - benign reads                                            → exit 0 + no stdout
# Rule 10 (CLAUDE.md): cover every payload shape the matcher can plausibly see
# — Bash `cat`, Bash python row-dump, and a Read-tool file_path payload.
set -uo pipefail
export LC_ALL=C

HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
ADAPTER="$ROOT/scripts/gates/codex-pretooluse-hook.sh"

PASS=0; FAIL=0
pass() { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not installed (adapter + this test require jq)"; exit 0
fi
[ -f "$ADAPTER" ] || { echo "FAIL: adapter not found at $ADAPTER"; exit 1; }

# ── Build an isolated fixture project ────────────────────────────────────
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
mkdir -p "$FIX/data/raw" "$FIX/.claude"
printf 'id,income\n1,52000\n2,61000\n' > "$FIX/data/raw/secret.csv"
printf 'id,voice\n1,wav\n'             > "$FIX/data/raw/halted.csv"
printf '# readme\n'                    > "$FIX/README.md"
SECRET="$(cd "$FIX/data/raw" && pwd -P)/secret.csv"
HALTED="$(cd "$FIX/data/raw" && pwd -P)/halted.csv"
jq -n --arg s "$SECRET" --arg h "$HALTED" \
  '{($s):"LOCAL_MODE", ($h):"HALTED"}' > "$FIX/.claude/safety-status.json"

# run_adapter <payload-json> → sets RC + OUT globals
run_adapter() {
  OUT="$(printf '%s' "$1" | bash "$ADAPTER" 2>/dev/null)"; RC=$?
}

# assert_deny <label> <payload>
assert_deny() {
  run_adapter "$2"
  if [ "$RC" -eq 2 ] && printf '%s' "$OUT" | jq -e '.hookSpecificOutput.permissionDecision=="deny"' >/dev/null 2>&1; then
    pass "$1 — exit 2 + permissionDecision:deny"
  else
    fail "$1 — expected deny (exit 2 + deny wire); got exit=$RC out=[${OUT:0:60}]"
  fi
}

# assert_allow <label> <payload>
assert_allow() {
  run_adapter "$2"
  if [ "$RC" -eq 0 ] && [ -z "$OUT" ]; then
    pass "$1 — exit 0 + empty stdout"
  else
    fail "$1 — expected allow (exit 0 + empty); got exit=$RC out=[${OUT:0:60}]"
  fi
}

echo "=== codex-pretooluse-hook adapter smoke tests ==="

# T1: Bash cat of a LOCAL_MODE raw-data file → deny
assert_deny "T1 Bash cat LOCAL_MODE" \
  "$(jq -nc --arg c "$FIX" '{tool_name:"Bash",tool_input:{command:"cat data/raw/secret.csv"},cwd:$c,hook_event_name:"PreToolUse"}')"

# T2: Bash python row-dump of the HALTED file → deny
assert_deny "T2 Bash python row-dump HALTED" \
  "$(jq -nc --arg c "$FIX" '{tool_name:"Bash",tool_input:{command:"python3 -c \"import pandas as pd; print(pd.read_csv(\\\"data/raw/halted.csv\\\").head())\""},cwd:$c,hook_event_name:"PreToolUse"}')"

# T3: Read tool on a LOCAL_MODE file (guard also covers Read) → deny
assert_deny "T3 Read tool file_path LOCAL_MODE" \
  "$(jq -nc --arg c "$FIX" --arg f "$SECRET" '{tool_name:"Read",tool_input:{file_path:$f},cwd:$c,hook_event_name:"PreToolUse"}')"

# T4: benign Bash cat of README → allow
assert_allow "T4 Bash cat benign README" \
  "$(jq -nc --arg c "$FIX" '{tool_name:"Bash",tool_input:{command:"cat README.md"},cwd:$c,hook_event_name:"PreToolUse"}')"

# T5: benign aggregate command (wc -l on the sensitive file is counts-only) → allow
assert_allow "T5 Bash wc -l counts-only" \
  "$(jq -nc --arg c "$FIX" '{tool_name:"Bash",tool_input:{command:"wc -l data/raw/secret.csv"},cwd:$c,hook_event_name:"PreToolUse"}')"

echo ""
echo "=== codex-data-guard: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
