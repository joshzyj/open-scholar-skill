#!/usr/bin/env bash
# setup-codex-hooks.sh — install the scholar data-safety guard as a Codex CLI
# PreToolUse hook in <project>/.codex/config.toml.
#
# WHY THIS EXISTS
#   pretooluse-data-guard.sh only runs under Claude Code (registered in
#   ~/.claude/settings.json). A **Codex** host never reads that file, so the
#   guard is inert there. Codex has its OWN PreToolUse hook mechanism, keyed off
#   a project's .codex/config.toml [hooks] table. This script registers the
#   guard there via the codex-pretooluse-hook.sh adapter, giving a Codex host
#   automatic, blocking data-safety enforcement (verified end-to-end against
#   codex v0.142.5, 2026-07-01).
#
# ACTIVATION: the hook fires only once the user TRUSTS the project in Codex
#   (trust prompt on first `codex` run here, or trust_level="trusted" under
#   [projects."<abs>"] in ~/.codex/config.toml). Until then AGENTS.md instructs
#   the agent to self-enforce against the sidecar.
#
# SPACES: the `command` is written as  bash '<abs adapter path>'  — a BARE path
#   with spaces (Google Drive "My Drive") FAILS OPEN under Codex (it word-splits
#   the command string → hook fails → data leaks; live-verified). The bash-quoted
#   form preserves the spaces and Blocks. Same footgun as Claude hooks
#   (_shared/data-handling-policy.md §9).
#
# IDEMPOTENT + NON-DESTRUCTIVE: writes a marker-guarded block; refreshes it in
#   place on re-run; refuses to clobber a pre-existing NON-scholar [hooks] table
#   (TOML forbids duplicate tables — merging that is the user's call).
#
# Usage:  setup-codex-hooks.sh <project_dir>
# Exits:  0 created/refreshed/no-op | 1 error | 3 skipped (foreign [hooks] present)

set -uo pipefail
export LC_ALL=C

PROJ="${1:-}"
[ -n "$PROJ" ] || { echo "FAIL: usage: setup-codex-hooks.sh <project_dir>" >&2; exit 1; }
[ -d "$PROJ" ] || { echo "FAIL: project dir not found: $PROJ" >&2; exit 1; }

_b="$HOME/.claude/scholar-skill-bootstrap.sh"
[ -f "$_b" ] || _b="${SCHOLAR_SKILL_DIR:-.}/scripts/scholar-skill-bootstrap.sh"
[ -f "$_b" ] && . "$_b"; unset _b

ADAPTER_REL="${SCHOLAR_SKILL_DIR:-.}/scripts/gates/codex-pretooluse-hook.sh"
if [ ! -f "$ADAPTER_REL" ]; then
  echo "FAIL: codex adapter not found at $ADAPTER_REL — cannot install Codex hook" >&2
  exit 1
fi
# Absolutize (the hook command must be an absolute path — Codex resolves it
# against its own cwd, not the project).
ADAPTER="$(cd "$(dirname "$ADAPTER_REL")" && pwd)/$(basename "$ADAPTER_REL")"

CODEX_DIR="$PROJ/.codex"
CONFIG="$CODEX_DIR/config.toml"
MARK_BEGIN="# scholar-codex-hooks:BEGIN v1"
MARK_END="# scholar-codex-hooks:END"

read -r -d '' BLOCK <<EOF || true
${MARK_BEGIN}
# Auto-managed by /scholar-init. Registers the scholar data-safety guard as a
# Codex PreToolUse hook so restricted data files (LOCAL_MODE / HALTED /
# NEEDS_REVIEW in .claude/safety-status.json) cannot be read into model context
# via the shell tool. ACTIVATES ONLY once you TRUST this project in Codex.
# The bash '<path>' form is required so the adapter path survives spaces.
# Edits between the markers are overwritten on the next /scholar-init run.
[[hooks.PreToolUse]]
matcher = ".*"

[[hooks.PreToolUse.hooks]]
type = "command"
command = "bash '${ADAPTER}'"
timeoutSec = 30
${MARK_END}
EOF

mkdir -p "$CODEX_DIR"

# ── Case 1: no config yet → create ───────────────────────────────────────
if [ ! -f "$CONFIG" ]; then
  printf '%s\n' "$BLOCK" > "$CONFIG"
  echo "setup-codex-hooks: created $CONFIG (data-safety PreToolUse hook)"
  echo "  → TRUST this project on first \`codex\` run here to activate the guard."
  exit 0
fi

# ── Case 2: our marker present → refresh in place ────────────────────────
if grep -qF "$MARK_BEGIN" "$CONFIG"; then
  BLOCK_TMP="$(mktemp)"; printf '%s\n' "$BLOCK" > "$BLOCK_TMP"
  TMP="$(mktemp)"
  awk -v b="$MARK_BEGIN" -v e="$MARK_END" -v bf="$BLOCK_TMP" '
    $0==b {inblk=1; while ((getline l < bf) > 0) print l; close(bf); next}
    inblk && $0==e {inblk=0; next}
    inblk {next}
    {print}
  ' "$CONFIG" > "$TMP"
  mv "$TMP" "$CONFIG"; rm -f "$BLOCK_TMP"
  echo "setup-codex-hooks: refreshed data-safety hook block in $CONFIG"
  exit 0
fi

# ── Case 3: foreign [hooks] table present → refuse to clobber ─────────────
if grep -qE '^[[:space:]]*\[\[?hooks' "$CONFIG"; then
  {
    echo "setup-codex-hooks: WARN $CONFIG already defines a [hooks] table (not scholar's)."
    echo "  Refusing to clobber it (TOML forbids duplicate tables). To enable the"
    echo "  data-safety guard, add this hook under your existing [hooks] manually:"
    echo "    [[hooks.PreToolUse]]"
    echo "    matcher = \".*\""
    echo "    [[hooks.PreToolUse.hooks]]"
    echo "    type = \"command\""
    echo "    command = \"bash '${ADAPTER}'\""
    echo "    timeoutSec = 30"
  } >&2
  exit 3
fi

# ── Case 4: config exists, no [hooks] → append our block ──────────────────
{ printf '\n'; printf '%s\n' "$BLOCK"; } >> "$CONFIG"
echo "setup-codex-hooks: appended data-safety hook block to $CONFIG"
echo "  → TRUST this project on first \`codex\` run here to activate the guard."
exit 0
