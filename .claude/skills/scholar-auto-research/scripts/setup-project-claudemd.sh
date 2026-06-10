#!/usr/bin/env bash
# setup-project-claudemd.sh — Phase 0 helper: ensure project CLAUDE.md carries
# the scholar-auto-research workflow contract (idempotent, self-contained).
#
# CONTRACT
#   Auto-managed sections of <project>/CLAUDE.md are wrapped in markers:
#     <!-- scholar-auto-research:BEGIN auto-rules v1 -->
#     ...
#     <!-- scholar-auto-research:END auto-rules -->
#   This script:
#     1. Reads the rule template from
#        scripts/templates/claudemd-auto-rules.md (vendored under this skill).
#     2. Writes/merges <project>/CLAUDE.md:
#        - if absent → create with template
#        - if present with markers → refresh content between markers
#        - if present without markers → append markers + template at end,
#          preserving all existing content
#
# This script is SELF-CONTAINED per scholar-auto-research's design (see
# auto-research-verify.sh line 81-84). It does NOT depend on scholar-skill/
# scripts/phases/setup-project-claudemd.sh.
#
# IDEMPOTENT: running twice with the same template produces a byte-identical
# CLAUDE.md (no churn on repeat invocations).
# NON-DESTRUCTIVE: user content outside the markers is preserved verbatim.
#
# EXITS
#   0 — CLAUDE.md created / refreshed / already-current (all success cases)
#   1 — error (project dir not found, template missing, etc.)
#
# Usage:
#   bash skills/scholar-auto-research/scripts/setup-project-claudemd.sh <project_dir>

set -uo pipefail
export LC_ALL=C

if [ $# -lt 1 ]; then
  echo "Usage: setup-project-claudemd.sh <project_dir>" >&2
  exit 1
fi

PROJ="$1"
VERSION="v1"

if [ ! -d "$PROJ" ]; then
  echo "FAIL: project directory not found: $PROJ" >&2
  exit 1
fi

# ── Locate the template ─────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="$SCRIPT_DIR/templates/claudemd-auto-rules.md"

if [ ! -f "$TEMPLATE" ]; then
  echo "FAIL: template not found at $TEMPLATE" >&2
  exit 1
fi

MARK_BEGIN="<!-- scholar-auto-research:BEGIN auto-rules ${VERSION} -->"
MARK_END="<!-- scholar-auto-research:END auto-rules -->"

# ── User-facing notices ─────────────────────────────────────────────
# Two formats: a FULL banner (CREATE / APPEND — operator's first encounter
# with this file) that includes the auto-managed content for review, and a
# SHORT banner (REFRESH / MIGRATE — the operator has seen the file before)
# that only signals an update. NO-OP is silent (idempotent).
#
# Output goes to stdout so the surrounding Claude agent sees it and relays
# to the user. Fixture tests redirect to /dev/null so this output is harmless.
HLINE="────────────────────────────────────────────────────────────────────"
_notice_full() {
  local action_phrase="$1"  # "created" or "added to your existing"
  local target_path="$2"    # the file written (CLAUDE.md or AGENTS.md)
  printf '\n%s\n' "$HLINE"
  printf 'PROJECT %s — scholar-auto-research workflow contract\n' "$(basename "$target_path")"
  printf '%s\n\n' "$HLINE"
  printf 'A project %s was %s:\n' "$(basename "$target_path")" "$action_phrase"
  printf '  %s\n\n' "$target_path"
  printf 'This file carries the workflow contract that auto-loads in every Claude\n'
  printf 'or Codex session for this project. It contains:\n\n'
  printf '  - Principles (load-bearing): quality over speed; no content\n'
  printf '    fabrication (citations, data, coauthors, JSON); no sycophancy.\n'
  printf '  - Operational rules (auto-research-specific): run mode persistence,\n'
  printf '    self-contained vendoring, Phase 15 gate cross-check + skip-flag,\n'
  printf '    prereq chain integrity, JSON-shape strictness, codex defaults.\n\n'
  printf '═══════════════ BEGIN auto-managed content ════════════════════════\n'
  # Print the marker block (BEGIN..END) so the operator sees what was written
  sed -n "/^${MARK_BEGIN//\//\\/}\$/,/^${MARK_END//\//\\/}\$/p" "$target_path"
  printf '═══════════════ END auto-managed content ══════════════════════════\n\n'
  printf 'You can add your own project-specific content OUTSIDE the marker\n'
  printf 'block above — it is preserved verbatim on every future refresh.\n\n'
  printf 'To review later:  cat "%s"\n' "$target_path"
  printf '%s\n\n' "$HLINE"
}
_notice_short() {
  local action_phrase="$1"  # "refreshed" or "migrated to ${VERSION}"
  local target_path="$2"
  printf '\n%s\n' "$HLINE"
  printf 'PROJECT %s — workflow contract %s\n' "$(basename "$target_path")" "$action_phrase"
  printf '%s\n' "$HLINE"
  printf 'The auto-managed rules block in %s was updated.\n' "$target_path"
  printf 'Your content outside the marker block is unchanged.\n'
  printf 'To review:  cat "%s"\n' "$target_path"
  printf '%s\n\n' "$HLINE"
}

# ── Assemble the marker block ───────────────────────────────────────
RENDERED=$(cat "$TEMPLATE")
AUTO_BLOCK="${MARK_BEGIN}
${RENDERED}
${MARK_END}"

# ── Detect host AI agent and compute target file list ───────────────
# 2026-05-28: support both CLAUDE.md (Claude Code) and AGENTS.md (Codex,
# cross-tool standard via agents.md). Behaviour matches the canonical
# scripts/phases/setup-project-claudemd.sh:
#   - Existing project: refresh whichever of CLAUDE.md / AGENTS.md is present;
#     do NOT backfill the other (the "only apply to new" decision).
#   - Fresh project + detected agent: write only that agent's file.
#   - Fresh project + unknown agent: write both (safest default).
# The detection helper is vendored under this skill per the self-contained
# contract (auto-research-verify.sh line 81-84).
HELPER="$SCRIPT_DIR/detect-host-agent.sh"
if [ -f "$HELPER" ]; then
  HOST_AGENT=$(bash "$HELPER" 2>/dev/null || echo "unknown")
else
  HOST_AGENT="unknown"
fi

HAS_CLAUDE=0; [ -f "$PROJ/CLAUDE.md" ] && HAS_CLAUDE=1
HAS_AGENTS=0; [ -f "$PROJ/AGENTS.md" ] && HAS_AGENTS=1
TARGET_FILES=()
if [ "$HAS_CLAUDE" -eq 1 ] || [ "$HAS_AGENTS" -eq 1 ]; then
  [ "$HAS_CLAUDE" -eq 1 ] && TARGET_FILES+=("CLAUDE.md")
  [ "$HAS_AGENTS" -eq 1 ] && TARGET_FILES+=("AGENTS.md")
else
  case "$HOST_AGENT" in
    claude-code) TARGET_FILES=("CLAUDE.md") ;;
    codex)       TARGET_FILES=("AGENTS.md") ;;
    *)           TARGET_FILES=("CLAUDE.md" "AGENTS.md") ;;
  esac
fi

# Hoisted norm() helper — used in Case 2 for idempotent byte-compare.
norm() { printf '%s' "$1" | awk 'NF || found {found=1; out = out (out?"\n":"") $0} END {print out}'; }

# ── Per-target write / merge ────────────────────────────────────────
# Runs the 3-case create / refresh / append logic against a single target
# path. Uses `return` (not `exit`) so the caller can iterate targets.
process_target() {
  local CLAUDE_MD="$1"  # name retained to minimize diff; may be CLAUDE.md or AGENTS.md
  local EXISTING_BEGIN EXISTING_END EXISTING_VERSION EXISTING_BLOCK TMP

  # Case 1: file doesn't exist → create from scratch
  if [ ! -f "$CLAUDE_MD" ]; then
    printf '%s\n' "$AUTO_BLOCK" > "$CLAUDE_MD"
    echo "setup-project-claudemd: created $CLAUDE_MD (${VERSION})"
    _notice_full "created" "$CLAUDE_MD"
    return 0
  fi

  # Case 2 vs 3: existing file. Find existing marker positions.
  EXISTING_BEGIN=$(grep -nE "^<!-- scholar-auto-research:BEGIN auto-rules v[0-9]+ -->$" "$CLAUDE_MD" | head -1 | cut -d: -f1)
  EXISTING_END=$(grep -nE "^<!-- scholar-auto-research:END auto-rules -->$" "$CLAUDE_MD" | head -1 | cut -d: -f1)

  if [ -n "$EXISTING_BEGIN" ] && [ -n "$EXISTING_END" ]; then
    # Case 2: refresh content between markers
    EXISTING_VERSION=$(sed -n "${EXISTING_BEGIN}p" "$CLAUDE_MD" | grep -oE "v[0-9]+")

    EXISTING_BLOCK=$(sed -n "${EXISTING_BEGIN},${EXISTING_END}p" "$CLAUDE_MD")
    if [ "$(norm "$EXISTING_BLOCK")" = "$(norm "$AUTO_BLOCK")" ]; then
      echo "setup-project-claudemd: $CLAUDE_MD already at ${VERSION}, no-op"
      return 0
    fi

    # Replace lines BEGIN..END with new AUTO_BLOCK.
    # GUARD: BSD sed treats `sed -n "1,0p"` as `sed -n "1p"` (prints line 1)
    # instead of an empty range. When EXISTING_BEGIN=1 (auto-rules block at the
    # top of the file), the pre-block sed must be skipped entirely.
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
      echo "setup-project-claudemd: migrated $CLAUDE_MD from ${EXISTING_VERSION} to ${VERSION}"
      _notice_short "migrated to ${VERSION}" "$CLAUDE_MD"
    else
      echo "setup-project-claudemd: refreshed $CLAUDE_MD auto-rules block (${VERSION})"
      _notice_short "refreshed (${VERSION})" "$CLAUDE_MD"
    fi
    return 0
  fi

  # Case 3: existing file without markers → append (preserve content)
  {
    printf '\n'
    printf '%s\n' "$AUTO_BLOCK"
  } >> "$CLAUDE_MD"
  echo "setup-project-claudemd: appended auto-rules block to $CLAUDE_MD (${VERSION}, existing content preserved)"
  _notice_full "added to your existing" "$CLAUDE_MD"
  return 0
}

for tf in "${TARGET_FILES[@]}"; do
  process_target "$PROJ/$tf"
done
exit 0
