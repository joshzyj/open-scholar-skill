#!/usr/bin/env bash
# codex-trigger-check.sh — auto-research-vendored copy
#
# Independent (no parent-plugin lookups) codex cross-model review trigger
# gate for scholar-auto-research. Mirrors the canonical scholar-skill
# parent gate but trimmed to ONLY the two auto-research phase tokens:
#
#   ar-6   — Phase 6 pre-execution code review   → codex code mode (A1+A2+A3)
#   ar-14  — Phase 14 manuscript verification    → codex full mode (A4+A5)
#
# This is an explicit optional diversity lane. Set SCHOLAR_CODEX_REVIEW=1 to
# request it. Ambient Codex availability never changes the portable phase
# requirement.
#
# Excuse mechanism (per-phase): add `[EXCUSED:codex-review:<reason>]` to
# the phase report at:
#   ar-6   → review/pre-execution-review.{md,json}
#   ar-14  → verify/manuscript-verification.{md,json}
#
# Test override: CODEX_AVAILABLE_OVERRIDE=true|false bypasses
# `command -v codex` so smoke tests can deterministically simulate
# "codex installed" or "codex missing" states.
#
# Exit codes:
#   0 GREEN    — trigger satisfied (fired, excused, or no trigger met)
#   1 RED      — strong trigger met but no dispatch and no excuse
#   2 YELLOW   — recommendation only, or env=true with codex CLI missing

set -euo pipefail

if [ $# -lt 2 ]; then
  echo "Usage: codex-trigger-check.sh <project_dir> <phase:ar-6|ar-14>" >&2
  exit 1
fi

PROJ="$1"
PHASE="$2"

case "$PHASE" in
  ar-6|ar-14) ;;
  *)
    echo "ERROR: phase must be one of: ar-6 | ar-14 (got '$PHASE')" >&2
    exit 1 ;;
esac

# Derive MODE (code|full) from PHASE
case "$PHASE" in
  ar-6)   MODE=code ;;
  ar-14)  MODE=full ;;
esac

# ─── Detect codex CLI availability ───────────────────────────────────────
if [ -n "${CODEX_AVAILABLE_OVERRIDE:-}" ]; then
  CODEX_AVAILABLE="$CODEX_AVAILABLE_OVERRIDE"
elif command -v codex >/dev/null 2>&1; then
  CODEX_AVAILABLE=true
else
  CODEX_AVAILABLE=false
fi

CODEX_REQUESTED=false
case "${SCHOLAR_CODEX_REVIEW:-0}" in
  1|true|TRUE|yes|YES) CODEX_REQUESTED=true ;;
esac

# ─── Locate the phase report ─────────────────────────────────────────────
case "$PHASE" in
  ar-6)
    REPORT=$(ls -t \
      "$PROJ"/review/pre-execution-review.md \
      "$PROJ"/review/pre-execution-review.json \
      2>/dev/null | head -1 || true) ;;
  ar-14)
    REPORT=$(ls -t \
      "$PROJ"/verify/manuscript-verification.md \
      "$PROJ"/verify/manuscript-verification.json \
      2>/dev/null | head -1 || true) ;;
esac

# ─── Check for critical findings in the phase report ─────────────────────
CRITICAL_FOUND=false
if [ -n "$REPORT" ] && [ -f "$REPORT" ]; then
  CRIT_HITS=$(grep -vE '^\[EXCUSED:' "$REPORT" 2>/dev/null \
              | grep -cE '★★[[:space:]]*CRITICAL|^[[:space:]]*-?[[:space:]]*CRITICAL:|\| CRITICAL \|' \
              || true)
  CRIT_HITS=${CRIT_HITS:-0}
  if [ "$CRIT_HITS" -gt 0 ]; then
    CRITICAL_FOUND=true
  fi
fi

# ─── Determine whether codex dispatch SHOULD have fired ──────────────────
TRIGGER_KIND=none
if [ "$CODEX_REQUESTED" = "true" ]; then
  TRIGGER_KIND=strong
elif [ "$CRITICAL_FOUND" = "true" ]; then
  TRIGGER_KIND=recommend
fi

# ─── Detect dispatch artifacts ───────────────────────────────────────────
DID_FIRE=false
glob_has_match() {
  # F3 (audit 2026-07-07): use `compgen -G`, not `ls $1`. The unquoted `ls $1`
  # word-split any project path containing a space ("Dropbox Project/", "o'brien/") so
  # a PRESENT dispatch artifact was reported fired=false — a false RED that
  # forced a redundant re-dispatch. `compgen -G "$1"` globs the quoted pattern
  # (spaces and A[1-3] classes intact) and returns nonzero ONLY when there is
  # truly no match. The nonzero return is safe: glob_has_match is only ever
  # evaluated as an `if`/`||` condition, which is exempt from `set -e`.
  compgen -G "$1" > /dev/null 2>&1
}
if [ "$MODE" = "code" ]; then
  if glob_has_match "$PROJ/reviews/codex/A[1-3]-*.md" \
     || glob_has_match "$PROJ/output/reviews/codex/A[1-3]-*.md"; then
    DID_FIRE=true
  fi
else
  if glob_has_match "$PROJ/reviews/codex/codex-review-consolidated-*.md" \
     || glob_has_match "$PROJ/output/reviews/codex/codex-review-consolidated-*.md" \
     || glob_has_match "$PROJ/reviews/codex/A[4-5]-*.md" \
     || glob_has_match "$PROJ/output/reviews/codex/A[4-5]-*.md"; then
    DID_FIRE=true
  fi
fi

# ─── Detect excuse annotation in the phase report ────────────────────────
EXCUSED=false
EXCUSE_REASON=""
if [ -n "$REPORT" ] && [ -f "$REPORT" ]; then
  EXCUSE_LINE=$(grep -E '\[EXCUSED:[[:space:]]*codex-review[[:space:]]*:' "$REPORT" 2>/dev/null | head -1 || true)
  if [ -n "$EXCUSE_LINE" ]; then
    EXCUSED=true
    EXCUSE_REASON=$(printf '%s' "$EXCUSE_LINE" | sed -E 's/.*\[EXCUSED:[[:space:]]*codex-review[[:space:]]*:[[:space:]]*([^]]*)\].*/\1/' | head -c 200)
  fi
fi

# ─── Emit structured log line (always observable) ────────────────────────
echo "CODEX_TRIGGER: phase=$PHASE requested=$CODEX_REQUESTED cli=$CODEX_AVAILABLE critical=$CRITICAL_FOUND trigger=$TRIGGER_KIND fired=$DID_FIRE excused=$EXCUSED"

# ─── Verdict ─────────────────────────────────────────────────────────────
if [ "$TRIGGER_KIND" = "none" ]; then
  echo "STATUS=GREEN"
  echo "REASON=no_trigger"
  echo "DETAIL: optional Codex diversity lane not requested and no CRITICAL findings."
  exit 0
fi

if [ "$DID_FIRE" = "true" ]; then
  echo "STATUS=GREEN"
  echo "REASON=fired"
  echo "DETAIL: scholar-openai dispatched ($TRIGGER_KIND trigger; codex artifacts present)."
  exit 0
fi

if [ "$EXCUSED" = "true" ]; then
  echo "STATUS=GREEN"
  echo "REASON=excused"
  echo "DETAIL: scholar-openai excused via [EXCUSED:codex-review:$EXCUSE_REASON]"
  exit 0
fi

# Explicitly requested but CLI missing → cannot fire → YELLOW
if [ "$CODEX_REQUESTED" = "true" ] && [ "$CODEX_AVAILABLE" = "false" ]; then
  echo "STATUS=YELLOW"
  echo "REASON=cli_missing"
  echo "DETAIL: SCHOLAR_CODEX_REVIEW=1 but codex CLI is unavailable. Install it, unset the explicit request, or annotate the phase report with [EXCUSED:codex-review: codex CLI not available]."
  exit 2
fi

if [ "$TRIGGER_KIND" = "strong" ]; then
  echo "STATUS=RED"
  echo "REASON=strong_trigger_no_dispatch"
  if [ "$MODE" = "code" ]; then
    echo "DETAIL: SCHOLAR_CODEX_REVIEW=1 and Codex is present, but no code-mode artifacts exist and no excuse was recorded."
  else
    echo "DETAIL: SCHOLAR_CODEX_REVIEW=1 and Codex is present, but no full-mode artifacts exist and no excuse was recorded."
  fi
  exit 1
fi

# TRIGGER_KIND=recommend → CRITICAL found but no env, no dispatch, no excuse
echo "STATUS=YELLOW"
echo "REASON=recommend_no_dispatch"
if [ "$MODE" = "code" ]; then
  echo "DETAIL: phase $PHASE found CRITICAL issues; cross-validation via scholar-openai code mode is recommended. To dispatch: /scholar-openai code <manuscript-path> <scripts-dir>. To opt out: [EXCUSED:codex-review: <reason>]"
else
  echo "DETAIL: phase $PHASE found CRITICAL issues; cross-validation via scholar-openai full mode is recommended. To dispatch: /scholar-openai full <manuscript-path>. To opt out: [EXCUSED:codex-review: <reason>]"
fi
exit 2
