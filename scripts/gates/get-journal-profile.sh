#!/usr/bin/env bash
# get-journal-profile.sh — single source of truth for per-journal data.
# Audit 2026-05-02 (architectural consolidation): all gates that need
# journal-specific data (section structure, word budgets, citation style,
# author canon) MUST query this helper instead of carrying their own
# hardcoded journal lists / case statements / Python dicts.
#
# Profiles live at:
#   ${SCHOLAR_SKILL_DIR}/.claude/skills/scholar-journal/references/profiles/<key>.json
#
# Usage:
#   bash get-journal-profile.sh <journal-name-or-alias> [--allow-default] [--json]
#
# Exit codes:
#   0 — GREEN  (profile found; PROFILE_PATH on stdout)
#   1 — RED    (no matching profile and --allow-default not set)
#   2 — RED    (--allow-default set but default.json absent)
#
# Stdout (success):
#   PROFILE_PATH=/abs/path/to/<key>.json
#   PROFILE_KEY=<key>
#   PROFILE_NAME=<human name>
#   CITATION_STYLE=<asa|chicago|numbered|...>
#   HOUSE_STYLE=<asa|nature|...>
#   (when --json passed: JSON content also dumped to stdout after the metadata block)
#
# Stdout (failure):
#   STATUS=RED
#   REASON=<message>
#   KNOWN_KEYS=<space-separated list of profile keys that exist>
#
# Resolution:
#   1. Normalize input (lowercase, collapse whitespace, strip non-alphanumeric)
#   2. Try exact match against profile.key
#   3. Try exact match against any alias in profile.aliases[]
#   4. Try substring match (input is contained in alias OR alias is contained in input)
#   5. If no match: RED unless --allow-default → load default.json

set -uo pipefail

# ── Bootstrap SCHOLAR_SKILL_DIR ────────────────────────────────────
_b="$HOME/.claude/scholar-skill-bootstrap.sh"
if [ ! -f "$_b" ]; then
  _self="$(cd "$(dirname "$0")" && pwd)"
  if [ -d "$_self/../.." ]; then
    SCHOLAR_SKILL_DIR="$(cd "$_self/../.." && pwd)"
  fi
fi
[ -f "$_b" ] && . "$_b"
unset _b _self

PROFILES_DIR=""
if [ -n "${SCHOLAR_SKILL_DIR:-}" ] && [ -d "${SCHOLAR_SKILL_DIR}/.claude/skills/scholar-journal/references/profiles" ]; then
  PROFILES_DIR="${SCHOLAR_SKILL_DIR}/.claude/skills/scholar-journal/references/profiles"
fi

if [ -z "$PROFILES_DIR" ] || [ ! -d "$PROFILES_DIR" ]; then
  echo "STATUS=RED"
  echo "REASON=journal-profiles directory not found at ${SCHOLAR_SKILL_DIR}/.claude/skills/scholar-journal/references/profiles/"
  exit 1
fi

# ── Argument parsing ──────────────────────────────────────────────
JOURNAL=""
ALLOW_DEFAULT=0
EMIT_JSON=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --allow-default) ALLOW_DEFAULT=1 ;;
    --json) EMIT_JSON=1 ;;
    -h|--help)
      sed -n '2,30p' "$0" | sed 's/^# *//'
      exit 0 ;;
    *)
      [ -z "$JOURNAL" ] && JOURNAL="$1" || { echo "STATUS=RED"; echo "REASON=extra arg: $1"; exit 1; }
      ;;
  esac
  shift
done

if ! command -v jq >/dev/null 2>&1; then
  echo "STATUS=RED"
  echo "REASON=jq not installed (required to parse profile JSONs)"
  exit 1
fi

# Normalize a journal name for fuzzy matching.
normalize() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/ /g' | sed -E 's/^ +| +$//g'
}

# ── Resolve profile ───────────────────────────────────────────────
PROFILE_PATH=""

if [ -n "$JOURNAL" ]; then
  J_NORM=$(normalize "$JOURNAL")
  # Pass 1: exact match (key OR alias). Most-specific wins.
  for prof in "$PROFILES_DIR"/*.json; do
    [ -f "$prof" ] || continue
    KEY=$(jq -r '.key // empty' "$prof" 2>/dev/null || true)
    [ -n "$KEY" ] || continue
    KEY_NORM=$(normalize "$KEY")
    if [ "$KEY_NORM" = "$J_NORM" ]; then
      PROFILE_PATH="$prof"; break
    fi
    # Exact alias match (no substring tolerance — too risky for journal names
    # where "Nature" vs "Nature Communications" differ critically).
    EXACT_ALIAS=$(jq -r --arg t "$J_NORM" '
      (.aliases // [])
      | map(. | ascii_downcase | gsub("[^a-z0-9]+"; " ") | gsub("^ +| +$"; ""))
      | map(select(. == $t))
      | length' "$prof" 2>/dev/null || echo 0)
    if [ "${EXACT_ALIAS:-0}" -gt 0 ]; then
      PROFILE_PATH="$prof"; break
    fi
  done
  # Pass 2: substring tolerance ONLY if no exact match found. Bind alias to
  # a variable so contains() doesn't rebind . to its own input.
  if [ -z "$PROFILE_PATH" ]; then
    for prof in "$PROFILES_DIR"/*.json; do
      [ -f "$prof" ] || continue
      KEY=$(jq -r '.key // empty' "$prof" 2>/dev/null || true)
      [ -n "$KEY" ] || continue
      SUB_HIT=$(jq -r --arg t "$J_NORM" '
        (.aliases // []) + [.key // ""]
        | map(. | ascii_downcase | gsub("[^a-z0-9]+"; " ") | gsub("^ +| +$"; ""))
        | map(select(length > 0))
        | map(. as $a | select(($a | contains($t)) or ($t | contains($a))))
        | length' "$prof" 2>/dev/null || echo 0)
      if [ "${SUB_HIT:-0}" -gt 0 ]; then
        PROFILE_PATH="$prof"; break
      fi
    done
  fi
fi

# Fallback to ASR (sociology default) if explicitly authorized.
# Audit 2026-05-02 (user directive): --allow-default falls back to ASR, NOT
# the generic default.json. Rationale: ASR is the most-developed sociology
# profile (full 7-section structure, ASA citation style, ~12000-word budget)
# and covers the modal use case better than the generic 6-section template.
# Generic default.json is still loadable via `--copy-from default` from
# scaffold-journal-profile.sh, but no longer the silent fallback here.
if [ -z "$PROFILE_PATH" ]; then
  if [ "$ALLOW_DEFAULT" -eq 1 ]; then
    if [ -f "${PROFILES_DIR}/asr.json" ]; then
      PROFILE_PATH="${PROFILES_DIR}/asr.json"
    elif [ -f "${PROFILES_DIR}/default.json" ]; then
      # Backstop: ASR profile somehow missing; try default.json.
      PROFILE_PATH="${PROFILES_DIR}/default.json"
    else
      echo "STATUS=RED"
      echo "REASON=--allow-default specified but neither asr.json nor default.json found in $PROFILES_DIR"
      exit 2
    fi
  else
    KNOWN_KEYS=$(for p in "$PROFILES_DIR"/*.json; do
      [ -f "$p" ] && jq -r '.key' "$p" 2>/dev/null
    done | sort | tr '\n' ' ' | sed -E 's/ +$//')
    SCAFFOLD_PATH="$(cd "$(dirname "$0")" && pwd)/scaffold-journal-profile.sh"
    echo "STATUS=RED"
    echo "REASON=no journal profile matches '${JOURNAL:-<empty>}'. Known keys: ${KNOWN_KEYS}."
    echo ""
    echo "TO ADD THIS JOURNAL (one command):"
    echo "  bash ${SCAFFOLD_PATH} \"${JOURNAL:-<journal name>}\""
    echo "  → creates a starter profile from default.json template; edit to customize"
    echo "  → then re-run this command to verify"
    echo ""
    echo "OR copy from a similar profile (preserves section structure + budgets):"
    echo "  bash ${SCAFFOLD_PATH} \"${JOURNAL:-<journal name>}\" --copy-from <similar-key>"
    echo "  Choose --copy-from based on field: sociology→social-forces|asr|ajs|demography;"
    echo "  political-science→apsr; multidisciplinary→pnas|nature|nature-human-behaviour."
    echo ""
    echo "OR use generic template (NOT recommended for submission-grade drafts):"
    echo "  pass --allow-default to this helper"
    echo ""
    echo "KNOWN_KEYS=$KNOWN_KEYS"
    exit 1
  fi
fi

# ── Emit metadata ─────────────────────────────────────────────────
PROFILE_KEY=$(jq -r '.key' "$PROFILE_PATH")
PROFILE_NAME=$(jq -r '.name' "$PROFILE_PATH")
CITATION_STYLE=$(jq -r '.citation_style // "unknown"' "$PROFILE_PATH")
HOUSE_STYLE=$(jq -r '.house_style // "unknown"' "$PROFILE_PATH")

echo "STATUS=GREEN"
echo "PROFILE_PATH=$PROFILE_PATH"
echo "PROFILE_KEY=$PROFILE_KEY"
echo "PROFILE_NAME=$PROFILE_NAME"
echo "CITATION_STYLE=$CITATION_STYLE"
echo "HOUSE_STYLE=$HOUSE_STYLE"

if [ "$EMIT_JSON" -eq 1 ]; then
  echo "---JSON---"
  cat "$PROFILE_PATH"
fi

exit 0
