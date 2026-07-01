#!/usr/bin/env bash
# setup-project-claudemd.sh — /scholar-init Step 1.2.5 helper: write/refresh the
# auto-managed cross-skill rules block in a project's CLAUDE.md / AGENTS.md.
#
# WHY THIS EXISTS
#   Open Scholar Skill is modular: researchers run each skill individually
#   (/scholar-eda, /scholar-analyze, /scholar-write, ...) rather than through a
#   single orchestrator. This block auto-loads in every future session in the
#   project directory, so cross-skill rules (no-destructive-regex, Objectivity
#   Mandate, data-safety/LOCAL_MODE scope, citation rules, workflow rules) bind
#   even when only a standalone skill is invoked.
#
#   This fork ships ONE profile — lean. There is no full-paper orchestrator and
#   therefore no "full" profile to upgrade to; the lean block is terminal.
#
# CONTRACT
#   Auto-managed content is wrapped in markers:
#     <!-- open-scholar-skill:BEGIN auto-rules v2-lean -->
#     ...
#     <!-- open-scholar-skill:END auto-rules -->
#   This script:
#     1. Renders scripts/templates/claudemd-auto-rules-lean.md, substituting a
#        conditional rules block based on the project's
#        .claude/safety-status.json (currently: CFPS LOCAL_MODE block).
#     2. Writes/merges each target memory file:
#        - if absent  → create with the rendered block
#        - if present with markers → refresh content between markers
#        - if present without markers → append markers + block at end,
#          preserving all existing content (including anything written by
#          Claude Code's built-in /init or a pre-existing AGENTS.md)
#
# HOST-AGENT DETECTION
#   Calls detect-host-agent.sh to choose the target filename:
#     - Existing project (CLAUDE.md or AGENTS.md present): refresh whichever
#       exists; never backfill the other.
#     - Fresh project + Claude Code  → CLAUDE.md only
#     - Fresh project + Codex        → AGENTS.md only (agents.md cross-tool std)
#     - Fresh project + unknown host → both
#   Override for tests: SCHOLAR_HOST_AGENT_OVERRIDE=claude-code|codex|unknown
#
# IDEMPOTENT: running twice produces a byte-identical memory file (no-op).
# NON-DESTRUCTIVE: user content outside the markers is preserved.
#
# EXITS
#   0 — created/refreshed (idempotent if already current)
#   1 — error (project dir not found, template missing, invalid --mode, etc.)
#
# Usage:
#   bash scripts/phases/setup-project-claudemd.sh <project_dir> [--mode lean]

set -uo pipefail
export LC_ALL=C

# Resolve our own location so template + helper paths are independent of cwd
# and of whether SCHOLAR_SKILL_DIR is exported (mirrors init-project.sh).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # scripts/phases
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"               # scripts

# ── Argument parsing: positional <project_dir> + optional --mode lean
MODE="lean"
PROJ=""

while [ $# -gt 0 ]; do
  case "$1" in
    --mode)
      if [ $# -lt 2 ]; then
        echo "FAIL: --mode requires an argument (lean)" >&2
        exit 1
      fi
      MODE="$2"; shift 2 ;;
    --mode=*)
      MODE="${1#--mode=}"; shift ;;
    -h|--help)
      cat >&2 <<EOF
Usage: setup-project-claudemd.sh <project_dir> [--mode lean]
  <project_dir>   Project root containing .claude/safety-status.json
  --mode lean     Write the cross-skill rules block (the only mode in this fork)
EOF
      exit 0 ;;
    -*)
      echo "FAIL: unknown option '$1' (try --help)" >&2
      exit 1 ;;
    *)
      if [ -z "$PROJ" ]; then
        PROJ="$1"
      else
        echo "FAIL: extra positional argument '$1' (expected only <project_dir>)" >&2
        exit 1
      fi
      shift ;;
  esac
done

if [ -z "$PROJ" ]; then
  echo "Usage: setup-project-claudemd.sh <project_dir> [--mode lean]" >&2
  exit 1
fi

# This fork ships only the lean profile. Accept --mode lean for forward-compat;
# reject anything else loudly rather than silently doing the wrong thing.
if [ "$MODE" != "lean" ]; then
  echo "FAIL: invalid --mode '$MODE' — this fork supports only 'lean'" >&2
  exit 1
fi

if [ ! -d "$PROJ" ]; then
  echo "FAIL: project directory not found: $PROJ" >&2
  exit 1
fi

TEMPLATE="${SCRIPTS_ROOT}/templates/claudemd-auto-rules-lean.md"
VERSION="v2-lean"

if [ ! -f "$TEMPLATE" ]; then
  echo "FAIL: template not found at $TEMPLATE" >&2
  exit 1
fi

MARK_BEGIN="<!-- open-scholar-skill:BEGIN auto-rules ${VERSION} -->"
MARK_END="<!-- open-scholar-skill:END auto-rules -->"

# ── Build conditional rules block ────────────────────────────────────────
SAFETY_JSON="$PROJ/.claude/safety-status.json"
CONDITIONAL_RULES=""

if [ -f "$SAFETY_JSON" ]; then
  # Detect CFPS LOCAL_MODE entries: any *.dta with status LOCAL_MODE
  if grep -E '\.dta"\s*:\s*"LOCAL_MODE"' "$SAFETY_JSON" >/dev/null 2>&1; then
    CONDITIONAL_RULES=$(cat <<'COND'

## CFPS data handling — LOCAL_MODE (project-specific)

This project contains CFPS `.dta` files marked `LOCAL_MODE` in `.claude/safety-status.json`. Never transmit raw CFPS data values, rows, or data-derived content to any cloud agent or external service. All analysis must run locally via `Rscript` invoked from Bash; the agent reads only aggregated outputs (`tables/*.csv`, registry CSVs), never the raw `.dta` files. See `_shared/data-handling-policy.md` §3.
COND
)
  fi
fi

# Render the template with conditional + enforcement substitution. awk -v can't
# carry multi-line values; write each substituted block to a temp file and slurp
# it in with awk's getline. COND_TMP is target-independent; the enforcement block
# is host-conditional (CLAUDE.md vs AGENTS.md), re-selected per target below.
COND_TMP=$(mktemp)
printf '%s' "$CONDITIONAL_RULES" > "$COND_TMP"

# ── Enforcement block variants (host-conditional) ────────────────────────
# The data-safety "Enforcement" bullet MUST be host-accurate. Claude Code fires
# a global PreToolUse hook from ~/.claude/settings.json; a Codex host does NOT
# read that file, so telling a Codex session the same hook protects it is FALSE
# (a false-security bug). CLAUDE.md keeps the accurate global-hook line; AGENTS.md
# documents the Codex-native .codex/config.toml PreToolUse hook + trust
# requirement + the actionable sidecar contract.
ENFORCEMENT_CLAUDE='3. **Enforcement** — `pretooluse-data-guard.sh` registered as a global PreToolUse hook in `~/.claude/settings.json`; Claude Code fires it before every `Read`/`Bash`/`Grep`/`Glob` and blocks reads of `LOCAL_MODE`/`HALTED`/`NEEDS_REVIEW` files.'
ENFORCEMENT_CODEX='3. **Enforcement (Codex host)** — Codex does NOT read `~/.claude/settings.json`, so the Claude PreToolUse hook does NOT run in this session. A Codex-native PreToolUse hook is registered in this project'\''s `.codex/config.toml` and **activates only once you trust this project** (accept the trust prompt on first `codex` run in this directory, or set `trust_level = "trusted"` under `[projects."<abs-path>"]` in `~/.codex/config.toml`). **Until it is trusted, YOU are the enforcement:** before reading ANY file under `data/`, look it up in `.claude/safety-status.json` — `CLEARED`/`ANONYMIZED`/`OVERRIDE` may be read; `LOCAL_MODE`/`HALTED`/`NEEDS_REVIEW` must NEVER be read (analyze those via a single `Rscript -e` / `python3 -c` Bash call emitting summary-only output — forbidden: `head(df)`, `print(df)`, `df.head()`, `df.sample()`).'

# render_auto_block <target_basename> — sets the global AUTO_BLOCK by rendering
# $TEMPLATE with {{CONDITIONAL_RULES}} and the host-appropriate
# {{ENFORCEMENT_BLOCK}} substituted. AGENTS.md → Codex variant; anything else
# (CLAUDE.md) → Claude variant. Templates without the token render unchanged.
ENF_TMP=$(mktemp)
render_auto_block() {
  local target_base="$1" rendered
  case "$target_base" in
    AGENTS.md) printf '%s' "$ENFORCEMENT_CODEX"  > "$ENF_TMP" ;;
    *)         printf '%s' "$ENFORCEMENT_CLAUDE" > "$ENF_TMP" ;;
  esac
  rendered=$(awk -v cond_file="$COND_TMP" -v enf_file="$ENF_TMP" '
    /\{\{CONDITIONAL_RULES\}\}/ {
      while ((getline line < cond_file) > 0) print line
      close(cond_file)
      next
    }
    /\{\{ENFORCEMENT_BLOCK\}\}/ {
      while ((getline line < enf_file) > 0) print line
      close(enf_file)
      next
    }
    { print }
  ' "$TEMPLATE")
  # ── Assemble the marker block ──────────────────────────────────────────
  AUTO_BLOCK="${MARK_BEGIN}
${rendered}
${MARK_END}"
}

# ── Detect host AI agent and compute target file list ───────────────────
HELPER="${SCRIPTS_ROOT}/detect-host-agent.sh"
if [ -f "$HELPER" ]; then
  HOST_AGENT=$(bash "$HELPER" 2>/dev/null || echo "unknown")
else
  HOST_AGENT="unknown"
fi

HAS_CLAUDE=0; [ -f "$PROJ/CLAUDE.md" ] && HAS_CLAUDE=1
HAS_AGENTS=0; [ -f "$PROJ/AGENTS.md" ] && HAS_AGENTS=1
TARGET_FILES=()
if [ "$HAS_CLAUDE" -eq 1 ] || [ "$HAS_AGENTS" -eq 1 ]; then
  # Existing project — refresh what's there, never backfill.
  [ "$HAS_CLAUDE" -eq 1 ] && TARGET_FILES+=("CLAUDE.md")
  [ "$HAS_AGENTS" -eq 1 ] && TARGET_FILES+=("AGENTS.md")
else
  # Fresh project — host-agent-driven file choice.
  case "$HOST_AGENT" in
    claude-code) TARGET_FILES=("CLAUDE.md") ;;
    codex)       TARGET_FILES=("AGENTS.md") ;;
    *)           TARGET_FILES=("CLAUDE.md" "AGENTS.md") ;;
  esac
fi

# Normalize-trailing-whitespace helper: compare normalized content so a
# byte-identical block does not re-write on every run ($AUTO_BLOCK lacks the
# trailing newline that sed -p adds).
norm() { printf '%s' "$1" | awk 'NF || found {found=1; out = out (out?"\n":"") $0} END {print out}'; }

# ── Per-target write / merge ───────────────────────────────────────────
process_target() {
  local CLAUDE_MD="$1"  # this target's path (CLAUDE.md or AGENTS.md)
  local EXISTING_BEGIN EXISTING_END EXISTING_VERSION EXISTING_BLOCK TMP

  if [ ! -f "$CLAUDE_MD" ]; then
    # Case 1: create from scratch
    printf '%s\n' "$AUTO_BLOCK" > "$CLAUDE_MD"
    echo "setup-project-claudemd: created $CLAUDE_MD (${VERSION})"
    return 0
  fi

  # Find existing marker positions (matches any prior auto-rules version).
  EXISTING_BEGIN=$(grep -nE "^<!-- open-scholar-skill:BEGIN auto-rules v[0-9]+(-(lean|full))? -->$" "$CLAUDE_MD" | head -1 | cut -d: -f1)
  EXISTING_END=$(grep -nE "^<!-- open-scholar-skill:END auto-rules -->$" "$CLAUDE_MD" | head -1 | cut -d: -f1)

  if [ -n "$EXISTING_BEGIN" ] && [ -n "$EXISTING_END" ]; then
    # Case 2: refresh content between markers
    EXISTING_VERSION=$(sed -n "${EXISTING_BEGIN}p" "$CLAUDE_MD" | grep -oE "v[0-9]+(-(lean|full))?")

    EXISTING_BLOCK=$(sed -n "${EXISTING_BEGIN},${EXISTING_END}p" "$CLAUDE_MD")
    if [ "$(norm "$EXISTING_BLOCK")" = "$(norm "$AUTO_BLOCK")" ]; then
      echo "setup-project-claudemd: $CLAUDE_MD already at ${VERSION}, no-op"
      return 0
    fi
    # Replace lines BEGIN..END with the new AUTO_BLOCK.
    # GUARD: BSD sed treats `sed -n "1,0p"` as `sed -n "1p"`; when
    # EXISTING_BEGIN=1 (block at top of file) the pre-block sed must be skipped
    # entirely, or the old BEGIN marker survives and the file ends up with two.
    TMP=$(mktemp)
    {
      if [ "$EXISTING_BEGIN" -gt 1 ]; then
        sed -n "1,$((EXISTING_BEGIN - 1))p" "$CLAUDE_MD"
      fi
      printf '%s\n' "$AUTO_BLOCK"
      sed -n "$((EXISTING_END + 1)),\$p" "$CLAUDE_MD"
    } > "$TMP"
    mv "$TMP" "$CLAUDE_MD"
    if [ "$EXISTING_VERSION" != "$VERSION" ]; then
      echo "setup-project-claudemd: migrated $CLAUDE_MD from ${EXISTING_VERSION:-legacy} to ${VERSION}"
    else
      echo "setup-project-claudemd: refreshed $CLAUDE_MD auto-rules block (${VERSION})"
    fi
    return 0
  fi

  # Case 3: existing file without markers — append
  {
    printf '\n'
    printf '%s\n' "$AUTO_BLOCK"
  } >> "$CLAUDE_MD"
  echo "setup-project-claudemd: appended auto-rules block to $CLAUDE_MD (existing content preserved)"
  return 0
}

# Iterate every chosen target. Each call is independent. render_auto_block picks
# the host-accurate enforcement variant (CLAUDE.md vs AGENTS.md) before each write.
for tf in "${TARGET_FILES[@]}"; do
  render_auto_block "$tf"
  process_target "$PROJ/$tf"
done
rm -f "$COND_TMP" "$ENF_TMP"
exit 0
