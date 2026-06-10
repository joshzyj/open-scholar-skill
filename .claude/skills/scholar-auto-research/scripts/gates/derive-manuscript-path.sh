#!/usr/bin/env bash
# derive-manuscript-path.sh — locate the active reader-facing manuscript file.
#
# Both scholar-full-paper and scholar-auto-research produce manuscripts but
# at different paths:
#
#   scholar-full-paper layout (procedural pipeline):
#     ${PROJ}/drafts/draft-manuscript-<slug>-<date>.md       (Phase 7 draft)
#     ${PROJ}/drafts/manuscript-final-<slug>-<date>.md       (Phase 11 assembly)
#     ${PROJ}/drafts/manuscript-submission-<slug>-<date>.md  (Phase 11b)
#
#   scholar-auto-research layout (contract pipeline):
#     ${PROJ}/manuscript/manuscript-draft.md   (Phase 13)
#     ${PROJ}/final/manuscript-final.md        (Phase 19)
#     ${PROJ}/submission/manuscript-submission.md (Phase 20)
#
# Per-section gates that previously hardcoded the auto-research triple
# (manuscript-title-check.sh, methods-role-subsections-check.sh,
# concept-to-measure-check.sh, descriptive-table-display-check.sh,
# effect-size-narrative-check.sh, journal-section-architecture-check.sh,
# section-existence-check.sh, title-outcome-check.sh) silently failed when
# wired into scholar-full-paper because no `manuscript/manuscript-draft.md`
# existed. This helper centralizes the search so the same gate scripts work
# under both pipelines.
#
# Usage (sourced into another shell script):
#     PROJ="<project root>"
#     . "$(dirname "${BASH_SOURCE[0]}")/derive-manuscript-path.sh"
#     # MANUSCRIPT_PATH is set; STAGE is "draft"|"final"|"submission"|""
#
# Usage (executed directly to print path + stage):
#     bash derive-manuscript-path.sh "$PROJ"           # default: prefer-final
#     bash derive-manuscript-path.sh "$PROJ" draft     # only Phase-7-stage drafts
#     bash derive-manuscript-path.sh "$PROJ" submission # prefer reviewer-facing
#
# Output (executed mode):
#   MANUSCRIPT_PATH=<absolute path>
#   STAGE=<draft|final|submission>
#   PIPELINE=<full-paper|auto-research>
# Exit codes:
#   0 — manuscript found
#   1 — no manuscript file located
#   2 — invalid arguments
#
# This file is safe to source (must NOT `exit` when sourced) and safe to
# execute as a script. The boundary is detected via $0 vs ${BASH_SOURCE[0]}.

set -u

_dmp_is_sourced() {
  [ "${BASH_SOURCE[0]:-}" != "${0}" ]
}

_dmp_emit() {
  printf 'MANUSCRIPT_PATH=%s\n' "$1"
  printf 'STAGE=%s\n' "$2"
  printf 'PIPELINE=%s\n' "$3"
}

_dmp_fail() {
  if _dmp_is_sourced; then
    MANUSCRIPT_PATH=""
    STAGE=""
    PIPELINE=""
    return 1
  fi
  printf 'MANUSCRIPT_PATH=\n'
  printf 'STAGE=\n'
  printf 'PIPELINE=\n'
  printf 'REASON=%s\n' "${1:-no-manuscript-found}"
  exit 1
}

_dmp_main() {
  local proj="${1:-${PROJ:-}}"
  local prefer="${2:-final}"

  if [ -z "$proj" ] || [ ! -d "$proj" ]; then
    if _dmp_is_sourced; then
      MANUSCRIPT_PATH=""; STAGE=""; PIPELINE=""
      return 1
    fi
    printf 'REASON=invalid-or-missing-PROJ\n' >&2
    exit 2
  fi

  # Build candidate list ordered by ${prefer} then fall back to all stages.
  # Newest mtime wins within each glob (handles versioned drafts like
  # draft-manuscript-slug-2026-05-08-v2.md).
  local fp_draft fp_final fp_submission
  local ar_draft ar_final ar_submission

  # Find newest file under a directory matching a name pattern. Uses
  # find -print0 to be safe with spaces in paths (Google Drive paths
  # commonly have spaces).
  _dmp_newest_in() {
    local dir="$1" name_glob="$2"
    [ -d "$dir" ] || { printf ''; return 0; }
    local newest="" newest_mt=0 mt
    while IFS= read -r -d '' f; do
      [ -f "$f" ] || continue
      if stat --version >/dev/null 2>&1; then
        mt=$(stat -c %Y "$f" 2>/dev/null || echo 0)
      else
        mt=$(stat -f %m "$f" 2>/dev/null || echo 0)
      fi
      mt=${mt:-0}
      if [ "$mt" -gt "$newest_mt" ]; then
        newest_mt=$mt
        newest=$f
      fi
    done < <(find "$dir" -maxdepth 1 -type f -name "$name_glob" -print0 2>/dev/null)
    printf '%s' "$newest"
  }

  # full-paper candidates (drafts/ directory). Canonical patterns first;
  # then a generic fallback for non-canonical hand-named experimental
  # outputs (e.g., manuscript-<slug>-v2-<date>.md). The fallback is
  # treated as `final` stage since it is the user's most-recent intended
  # reader-facing output when nothing canonical exists.
  fp_final=$(_dmp_newest_in "$proj/drafts" "manuscript-final-*.md")
  fp_submission=$(_dmp_newest_in "$proj/drafts" "manuscript-submission-*.md")
  fp_draft=$(_dmp_newest_in "$proj/drafts" "draft-manuscript-*.md")
  if [ -z "$fp_final" ] && [ -z "$fp_submission" ] && [ -z "$fp_draft" ]; then
    # Generic fallback: any drafts/manuscript-*.md (excluding scholar-lrh-,
    # scholar-write-log-, etc. which are not manuscripts).
    local generic=""
    local newest_mt=0 mt
    while IFS= read -r -d '' f; do
      [ -f "$f" ] || continue
      local base
      base=$(basename "$f")
      case "$base" in
        scholar-lrh-*|scholar-write-log-*|scholar-polish-*) continue ;;
        manuscript-tables-figures-captions-*|manuscript-section-*) continue ;;
      esac
      if stat --version >/dev/null 2>&1; then
        mt=$(stat -c %Y "$f" 2>/dev/null || echo 0)
      else
        mt=$(stat -f %m "$f" 2>/dev/null || echo 0)
      fi
      mt=${mt:-0}
      if [ "$mt" -gt "$newest_mt" ]; then
        newest_mt=$mt; generic=$f
      fi
    done < <(find "$proj/drafts" -maxdepth 1 -type f -name "manuscript-*.md" -print0 2>/dev/null)
    [ -n "$generic" ] && fp_final=$generic
  fi
  # auto-research candidates (canonical paths)
  ar_draft="$proj/manuscript/manuscript-draft.md"
  ar_final="$proj/final/manuscript-final.md"
  ar_submission="$proj/submission/manuscript-submission.md"
  [ -f "$ar_draft" ] || ar_draft=""
  [ -f "$ar_final" ] || ar_final=""
  [ -f "$ar_submission" ] || ar_submission=""

  # Resolution order by stage preference. Within each preference we try
  # full-paper first (because this helper is primarily for full-paper
  # gates) and auto-research second.
  local ms="" stage="" pipeline=""
  case "$prefer" in
    submission)
      if [ -n "$fp_submission" ]; then ms=$fp_submission; stage=submission; pipeline=full-paper
      elif [ -n "$ar_submission" ]; then ms=$ar_submission; stage=submission; pipeline=auto-research
      elif [ -n "$fp_final" ]; then ms=$fp_final; stage=final; pipeline=full-paper
      elif [ -n "$ar_final" ]; then ms=$ar_final; stage=final; pipeline=auto-research
      elif [ -n "$fp_draft" ]; then ms=$fp_draft; stage=draft; pipeline=full-paper
      elif [ -n "$ar_draft" ]; then ms=$ar_draft; stage=draft; pipeline=auto-research
      fi ;;
    final)
      if [ -n "$fp_final" ]; then ms=$fp_final; stage=final; pipeline=full-paper
      elif [ -n "$ar_final" ]; then ms=$ar_final; stage=final; pipeline=auto-research
      elif [ -n "$fp_submission" ]; then ms=$fp_submission; stage=submission; pipeline=full-paper
      elif [ -n "$ar_submission" ]; then ms=$ar_submission; stage=submission; pipeline=auto-research
      elif [ -n "$fp_draft" ]; then ms=$fp_draft; stage=draft; pipeline=full-paper
      elif [ -n "$ar_draft" ]; then ms=$ar_draft; stage=draft; pipeline=auto-research
      fi ;;
    draft)
      if [ -n "$fp_draft" ]; then ms=$fp_draft; stage=draft; pipeline=full-paper
      elif [ -n "$ar_draft" ]; then ms=$ar_draft; stage=draft; pipeline=auto-research
      elif [ -n "$fp_final" ]; then ms=$fp_final; stage=final; pipeline=full-paper
      elif [ -n "$ar_final" ]; then ms=$ar_final; stage=final; pipeline=auto-research
      fi ;;
    *)
      if _dmp_is_sourced; then
        MANUSCRIPT_PATH=""; STAGE=""; PIPELINE=""
        return 2
      fi
      printf 'REASON=invalid-stage-preference: %s\n' "$prefer" >&2
      exit 2 ;;
  esac

  if [ -z "$ms" ]; then
    _dmp_fail "no-manuscript-found-under-$proj"
    return 1
  fi

  if _dmp_is_sourced; then
    MANUSCRIPT_PATH=$ms
    STAGE=$stage
    PIPELINE=$pipeline
    return 0
  fi
  _dmp_emit "$ms" "$stage" "$pipeline"
  return 0
}

if _dmp_is_sourced; then
  # Sourced — caller has already set PROJ; default to prefer=final.
  _dmp_main "${PROJ:-}" "${1:-final}"
else
  # Executed — accept positional args.
  _dmp_main "$@"
fi
