#!/usr/bin/env bash
# scaffold-journal-profile.sh — create a starter journal profile JSON when a
# project targets a journal not yet in scholar-journal/references/profiles/.
#
# Audit 2026-05-02 (post-F4 user-friction fix): the get-journal-profile.sh
# helper correctly fails RED on unknown journals (which is the right safety
# behavior — generic-template fallback was the documented regression). But
# the resulting error ("add a profile JSON") is a friction wall for
# researchers who don't know the schema. This script bridges the gap:
# one command, starter profile authored from default.json template +
# journal-specific overrides scraped from top-journals.md when available.
#
# Usage:
#   bash scaffold-journal-profile.sh "Sociological Methods & Research"
#   bash scaffold-journal-profile.sh "Journal of Marriage and Family" --key jmf
#   bash scaffold-journal-profile.sh "Some Journal" --copy-from social-forces
#
# Behavior:
#   1. Derive a slug from the journal name (lowercase, alphanumeric + hyphens)
#      OR use --key <slug> if provided.
#   2. Refuse to overwrite an existing profile (unless --force).
#   3. Copy from --copy-from <key> (if specified) OR default.json (otherwise).
#   4. Set: key=<slug>, name=<as-given>, aliases=[<as-given>, <slug>].
#   5. Keep all section/word/structural-move scaffolding from the template.
#   6. Print the path + a 3-step "what to edit" checklist for the operator.
#
# Exit codes:
#   0 GREEN  — new profile written
#   1 RED    — invalid input, profile exists (without --force), or write failed
#   2 YELLOW — refused to overwrite (without --force); existing path printed

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

PROFILES_DIR="${SCHOLAR_SKILL_DIR}/.claude/skills/scholar-journal/references/profiles"
if [ ! -d "$PROFILES_DIR" ]; then
  echo "STATUS=RED"
  echo "REASON=profiles dir not found at $PROFILES_DIR"
  exit 1
fi

# ── Argument parsing ──────────────────────────────────────────────
JOURNAL_NAME=""
KEY=""
# Audit 2026-05-02 (user directive): when no template is named, fall back
# to ASR (the most-developed sociology profile) rather than the generic
# default.json. ASR's 7-section structure, ASA citation style, and ~12000-
# word budget cover the most likely targets a researcher would name. Use
# `--copy-from default` for the generic 6-section template if needed.
COPY_FROM="asr"
FORCE=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --key) KEY="${2:-}"; shift 2 ;;
    --key=*) KEY="${1#--key=}"; shift ;;
    --copy-from) COPY_FROM="${2:-}"; shift 2 ;;
    --copy-from=*) COPY_FROM="${1#--copy-from=}"; shift ;;
    --force) FORCE=1; shift ;;
    -h|--help)
      sed -n '2,30p' "$0" | sed 's/^# *//'
      exit 0 ;;
    -*)
      echo "STATUS=RED"
      echo "REASON=unknown flag: $1"
      exit 1 ;;
    *)
      if [ -z "$JOURNAL_NAME" ]; then JOURNAL_NAME="$1"; shift
      else echo "STATUS=RED"; echo "REASON=extra positional arg: $1"; exit 1; fi
      ;;
  esac
done

if [ -z "$JOURNAL_NAME" ]; then
  echo "STATUS=RED"
  echo "REASON=usage: $0 \"<Journal Name>\" [--key <slug>] [--copy-from <profile-key>] [--force]"
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "STATUS=RED"
  echo "REASON=jq not installed (required for JSON manipulation)"
  exit 1
fi

# ── Derive slug if not provided ───────────────────────────────────
if [ -z "$KEY" ]; then
  KEY=$(printf '%s' "$JOURNAL_NAME" | tr '[:upper:]' '[:lower:]' \
        | sed -E 's/&/and/g; s/[^a-z0-9]+/-/g; s/^-+|-+$//g')
fi

if [ -z "$KEY" ]; then
  echo "STATUS=RED"
  echo "REASON=could not derive a valid slug from '$JOURNAL_NAME'. Use --key <slug> explicitly."
  exit 1
fi

TARGET_PATH="${PROFILES_DIR}/${KEY}.json"

# ── Refuse overwrite without --force ──────────────────────────────
if [ -f "$TARGET_PATH" ] && [ "$FORCE" -eq 0 ]; then
  echo "STATUS=YELLOW"
  echo "REASON=profile already exists at $TARGET_PATH (pass --force to overwrite)"
  echo "EXISTING=$TARGET_PATH"
  exit 2
fi

# ── Resolve template ──────────────────────────────────────────────
TEMPLATE_PATH="${PROFILES_DIR}/${COPY_FROM}.json"
if [ ! -f "$TEMPLATE_PATH" ]; then
  echo "STATUS=RED"
  echo "REASON=template profile '$COPY_FROM' not found at $TEMPLATE_PATH"
  echo "AVAILABLE=$(ls "$PROFILES_DIR" | sed 's/\.json$//' | tr '\n' ' ')"
  exit 1
fi

# ── Build new profile from template ──────────────────────────────
# - key: new slug
# - name: as given
# - aliases: [given name, slug] (lowercased+deduped by jq)
# - canon_authors: null (must be authored separately for theory-canon coverage)
# - everything else: inherit from template
NEW_JSON=$(jq --arg k "$KEY" --arg n "$JOURNAL_NAME" --arg a1 "$JOURNAL_NAME" --arg a2 "$KEY" '
  .key = $k
  | .name = $n
  | .aliases = ([$a1, $a2] | unique)
  | .canon_authors = null
  | del(._warning, ._comment)
' "$TEMPLATE_PATH")

if [ -z "$NEW_JSON" ]; then
  echo "STATUS=RED"
  echo "REASON=jq failed to construct new profile from template"
  exit 1
fi

printf '%s\n' "$NEW_JSON" > "$TARGET_PATH" || {
  echo "STATUS=RED"
  echo "REASON=could not write $TARGET_PATH"
  exit 1
}

# ── Success: print actionable next steps ─────────────────────────
echo "STATUS=GREEN"
echo "REASON=starter profile authored from $COPY_FROM template"
echo "PROFILE_PATH=$TARGET_PATH"
echo "KEY=$KEY"
echo "NAME=$JOURNAL_NAME"
echo "TEMPLATE=$COPY_FROM"
echo ""
echo "NEXT STEPS (edit $TARGET_PATH to customize):"
echo "  1. Review .total_word_budget {min, max} — match the journal's word limit."
echo "  2. Review .section_order[] — does the journal use this section structure?"
echo "     Sociology journals: 7-section (abstract/intro/lit_review/theory/data_methods/results/discussion)"
echo "     Nature/PNAS family: 5-section (abstract/intro/results/discussion/methods, methods at end)"
echo "     APSR: 7-section with research_design separate from methods"
echo "  3. Review .sections.<id>.{min_words, max_words} per-section budgets."
echo "  4. Review .citation_style — ASA / Chicago AD / APA 7th / numbered / etc."
echo "  5. (Optional, for theory-canon gates) Add a canonical-author entry to"
echo "     scholar-journal/references/canon-authors.json with core[], threshold."
echo ""
echo "REFERENCE: scholar-journal/references/top-journals.md has narrative entries"
echo "for many journals — use it to populate the fields above."
exit 0
