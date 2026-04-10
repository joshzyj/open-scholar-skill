#!/usr/bin/env bash
# Phase Verification Gate — scholar-full-paper
# Usage: bash scripts/gates/phase-verify.sh <phase> <project_dir>
# Example: bash scripts/gates/phase-verify.sh 2 output/immigrant-wage-penalty
# Checks: PROJECT STATE exists, phase entry present, expected files exist, word counts
# Exit: 0 = PASS, 1 = FAIL (with details)
set -euo pipefail

if [ $# -lt 2 ]; then
  echo "Usage: phase-verify.sh <phase_number> <project_dir>" >&2
  echo "Example: phase-verify.sh 2 output/immigrant-wage-penalty" >&2
  exit 1
fi

PHASE="$1"
PROJ="$2"
ISSUES=0
WARNINGS=0
REPORT=""

check_file() {
  local label="$1" path="$2"
  if [ -f "$path" ]; then
    local lines
    lines=$(wc -l < "$path" | tr -d ' ')
    if [ "$lines" -lt 3 ]; then
      REPORT="${REPORT}\n  FAIL: $label exists but is nearly empty ($lines lines): $path"
      ISSUES=$((ISSUES + 1))
    fi
  else
    REPORT="${REPORT}\n  FAIL: $label not found: $path"
    ISSUES=$((ISSUES + 1))
  fi
}

check_word_count() {
  local label="$1" file="$2" min="$3"
  if [ -f "$file" ]; then
    local wc_actual
    wc_actual=$(wc -w < "$file" | tr -d ' ')
    if [ "$wc_actual" -lt "$min" ]; then
      REPORT="${REPORT}\n  FAIL: $label has $wc_actual words (minimum: $min): $file"
      ISSUES=$((ISSUES + 1))
    fi
  fi
}

echo "=== PHASE $PHASE VERIFICATION GATE ==="
echo "Project: $PROJ"
echo ""

# --- Check 1: Project directory exists ---
if [ ! -d "$PROJ" ]; then
  echo "FAIL: Project directory does not exist: $PROJ"
  exit 1
fi

# --- Check 2: PROJECT STATE file exists ---
STATE_FILE=$(find "$PROJ" \( -name "project-state*.md" -o -name "PROJECT-STATE*" \) 2>/dev/null | head -1 || true)
if [ -z "$STATE_FILE" ]; then
  # Also check if it's inline in any log file
  STATE_IN_LOG=$(grep -rl "=== PROJECT STATE ===" "$PROJ/logs/" 2>/dev/null | head -1 || true)
  if [ -z "$STATE_IN_LOG" ]; then
    REPORT="${REPORT}\n  FAIL: No PROJECT STATE file found in $PROJ"
    ISSUES=$((ISSUES + 1))
  fi
fi

# --- Check 2b: Requested phase is actually recorded in PROJECT STATE ---
# The header said this was checked but it wasn't — a phase could "pass"
# its verifier with only heuristic artifact checks, even if the
# orchestrator never wrote a phase entry. Fail closed when the phase
# section is absent. Phase headers look like:
#   ## Phase -1 — Safety Gate (2026-04-09 11:41)
#   ## Phase 0-PRE — Brainstorm ...
#   ## Phase 0 — Idea Exploration ...
#   ## Phase 7 — Drafting ...
#   ## Phase 7b — Verify ...
#
# The boundary matcher uses an explicit WHITELIST (space, em-dash,
# colon, open paren, end-of-line) rather than a blacklist. An earlier
# blacklist `[^0-9A-Za-z.]` wrongly allowed `-`, so `Phase 0` matched
# `Phase 0-PRE` and `Phase 0.POST` was excluded only because `.` was
# in the blacklist. The whitelist is unambiguous: `Phase 7` followed
# by `b` does NOT match (b is not whitelisted), and `Phase 0` followed
# by `-` does NOT match (dash is not whitelisted).
if [ -n "$STATE_FILE" ] && [ -f "$STATE_FILE" ]; then
  PHASE_ESCAPED=$(printf '%s' "$PHASE" | sed 's/[][\.*^$/]/\\&/g')
  # ERE: `## Phase <N>( |\t|—|:|(|$)` — note the alternation includes
  # end-of-line via `$` which anchors in ERE.
  if ! grep -qE "^(## |### |- )?Phase ${PHASE_ESCAPED}([[:space:]]|—|:|\(|$)" "$STATE_FILE" 2>/dev/null; then
    REPORT="${REPORT}\n  FAIL: Phase $PHASE not recorded in PROJECT STATE ($STATE_FILE)"
    REPORT="${REPORT}\n        The orchestrator must write a '## Phase $PHASE — ...' heading before gate verification."
    ISSUES=$((ISSUES + 1))
  fi
fi

# --- Check 3: Phase-specific checks ---
case "$PHASE" in
  -1|safety)
    # Safety gate: check safety log exists
    check_file "Safety log" "$(find "$PROJ/logs" -name "*safety*" 2>/dev/null | head -1 || echo "$PROJ/logs/safety-log.md")"
    ;;
  0-PRE|0pre|brainstorm)
    # Brainstorm phase: check brainstorm report exists
    BRAINSTORM=$(find "$PROJ" -name "*brainstorm*" 2>/dev/null | head -1 || true)
    if [ -z "$BRAINSTORM" ]; then
      REPORT="${REPORT}\n  WARN: No brainstorm report found (expected scholar-brainstorm-*.md)"
      WARNINGS=$((WARNINGS + 1))
    fi
    ;;
  0|idea)
    # Idea phase: check idea output exists
    IDEA_FILE=$(find "$PROJ" \( -name "*idea*" -o -name "*scholar-idea*" \) 2>/dev/null | head -1 || true)
    if [ -z "$IDEA_FILE" ]; then
      REPORT="${REPORT}\n  FAIL: No idea output found (expected scholar-idea-*.md)"
      ISSUES=$((ISSUES + 1))
    fi
    ;;
  1|brief)
    # Intake/brief: check PROJECT STATE has journal and scope
    if [ -n "$STATE_FILE" ] && [ -f "$STATE_FILE" ]; then
      HAS_JOURNAL=$(grep -ci "target.*journal\|journal.*:" "$STATE_FILE" 2>/dev/null || true)
      if [ "$HAS_JOURNAL" -eq 0 ]; then
        REPORT="${REPORT}\n  FAIL: No target journal found in PROJECT STATE"
        ISSUES=$((ISSUES + 1))
      fi
    else
      REPORT="${REPORT}\n  FAIL: PROJECT STATE file missing — Phase 1 should initialize it"
      ISSUES=$((ISSUES + 1))
    fi
    ;;
  2|lit|theory)
    # Lit review + theory: check LRH output exists with minimum length
    LRH_FILE=$(find "$PROJ" \( -name "*lit-review*" -o -name "*scholar-lrh*" -o -name "*lrh-*" \) 2>/dev/null | head -1 || true)
    if [ -z "$LRH_FILE" ]; then
      REPORT="${REPORT}\n  FAIL: No lit review output found (expected scholar-lrh-*.md)"
      ISSUES=$((ISSUES + 1))
    else
      check_word_count "Lit review + theory" "$LRH_FILE" 2000
    fi
    # Check search log exists
    SEARCH_LOG=$(find "$PROJ/logs" -name "*search-log*" 2>/dev/null | head -1 || true)
    if [ -z "$SEARCH_LOG" ]; then
      REPORT="${REPORT}\n  WARN: No search log found (expected scholar-search-log-*.md)"
      WARNINGS=$((WARNINGS + 1))
    fi
    ;;
  3|design)
    # Design: check design blueprint exists
    DESIGN_FILE=$(find "$PROJ" \( -name "*design*" -o -name "*blueprint*" \) 2>/dev/null | head -1 || true)
    if [ -z "$DESIGN_FILE" ]; then
      REPORT="${REPORT}\n  FAIL: No design blueprint found"
      ISSUES=$((ISSUES + 1))
    fi
    ;;
  4|data)
    # Data plan: check variable dictionary and data blueprint exist
    VAR_DICT=$(find "$PROJ" \( -name "*variable*" -o -name "*var-dict*" -o -name "*data-blueprint*" -o -name "*data-plan*" \) 2>/dev/null | head -1 || true)
    if [ -z "$VAR_DICT" ]; then
      # Also check PROJECT STATE for variable dictionary entries
      STATE_HAS_VARS=""
      if [ -n "$STATE_FILE" ] && [ -f "$STATE_FILE" ]; then
        STATE_HAS_VARS=$(grep -ci "variable\|var.*dict\|data.*source\|sample.*N" "$STATE_FILE" 2>/dev/null || true)
      fi
      if [ -z "$STATE_HAS_VARS" ] || [ "$STATE_HAS_VARS" -eq 0 ]; then
        REPORT="${REPORT}\n  FAIL: No variable dictionary or data blueprint found"
        ISSUES=$((ISSUES + 1))
      fi
    fi
    # Check data status is defined
    if [ -n "$STATE_FILE" ] && [ -f "$STATE_FILE" ]; then
      DATA_STATUS=$(grep -ci "data.*status\|existing-data\|no-data\|collecting" "$STATE_FILE" 2>/dev/null || true)
      if [ "$DATA_STATUS" -eq 0 ]; then
        REPORT="${REPORT}\n  WARN: Data status not found in PROJECT STATE"
        WARNINGS=$((WARNINGS + 1))
      fi
    fi
    ;;
  5|analysis)
    # Analysis: check tables and figures directories have content
    TABLE_COUNT=$(find "$PROJ/tables" -type f 2>/dev/null | wc -l | tr -d ' ')
    FIG_COUNT=$(find "$PROJ/figures" -type f 2>/dev/null | wc -l | tr -d ' ')
    # Check if data-available mode (existing-data in PROJECT STATE)
    DATA_AVAILABLE=""
    if [ -n "$STATE_FILE" ] && [ -f "$STATE_FILE" ]; then
      DATA_AVAILABLE=$(grep -ci "existing-data\|DATA-AVAILABLE" "$STATE_FILE" 2>/dev/null || true)
    fi
    if [ "$TABLE_COUNT" -eq 0 ]; then
      if [ -n "$DATA_AVAILABLE" ] && [ "$DATA_AVAILABLE" -gt 0 ]; then
        REPORT="${REPORT}\n  FAIL: No table files in $PROJ/tables/ (data-available mode — tables should exist)"
        ISSUES=$((ISSUES + 1))
      else
        REPORT="${REPORT}\n  WARN: No table files in $PROJ/tables/ (no-data mode — code templates expected)"
        WARNINGS=$((WARNINGS + 1))
      fi
    fi
    if [ "$FIG_COUNT" -eq 0 ]; then
      if [ -n "$DATA_AVAILABLE" ] && [ "$DATA_AVAILABLE" -gt 0 ]; then
        REPORT="${REPORT}\n  FAIL: No figure files in $PROJ/figures/ (data-available mode — figures should exist)"
        ISSUES=$((ISSUES + 1))
      else
        REPORT="${REPORT}\n  WARN: No figure files in $PROJ/figures/ (no-data mode — code templates expected)"
        WARNINGS=$((WARNINGS + 1))
      fi
    fi
    # Check table format coverage (should have CSV for replication)
    if [ "$TABLE_COUNT" -gt 0 ]; then
      CSV_COUNT=$(find "$PROJ/tables" -name "*.csv" -type f 2>/dev/null | wc -l | tr -d ' ')
      if [ "$CSV_COUNT" -eq 0 ]; then
        REPORT="${REPORT}\n  WARN: No CSV tables in $PROJ/tables/ — CSV needed for replication package"
        WARNINGS=$((WARNINGS + 1))
      fi
    fi
    # Check scripts directory
    SCRIPT_COUNT=$(find "$PROJ/scripts" -type f \( -name "*.R" -o -name "*.py" \) 2>/dev/null | wc -l | tr -d ' ')
    if [ "$SCRIPT_COUNT" -eq 0 ]; then
      REPORT="${REPORT}\n  WARN: No scripts in $PROJ/scripts/ — script archiving may have failed"
      WARNINGS=$((WARNINGS + 1))
    fi
    # Check coding decisions log and script index
    if [ ! -f "$PROJ/scripts/coding-decisions-log.md" ]; then
      REPORT="${REPORT}\n  WARN: coding-decisions-log.md missing in $PROJ/scripts/"
      WARNINGS=$((WARNINGS + 1))
    fi
    if [ ! -f "$PROJ/scripts/script-index.md" ]; then
      REPORT="${REPORT}\n  WARN: script-index.md missing in $PROJ/scripts/"
      WARNINGS=$((WARNINGS + 1))
    fi
    ;;
  5.5|code-review)
    # Code review gate: check code review report exists
    CR_FILE=$(find "$PROJ" -name "*code-review*" 2>/dev/null | head -1 || true)
    if [ -z "$CR_FILE" ]; then
      REPORT="${REPORT}\n  FAIL: No code review report found (expected reports/code-review-*.md)"
      ISSUES=$((ISSUES + 1))
    fi
    ;;
  6|compute|ling)
    # Specialized branch: check branch outputs exist (similar to Phase 5)
    # This phase is conditional — only runs for computational/sociolinguistic methods
    BRANCH_OUTPUT=$(find "$PROJ" \( -name "*compute*" -o -name "*ling*" \) 2>/dev/null | grep -v "log\|SKILL" | head -1 || true)
    if [ -z "$BRANCH_OUTPUT" ]; then
      REPORT="${REPORT}\n  WARN: No branch-specific output found (Phase 6 may have been skipped if method is quantitative)"
      WARNINGS=$((WARNINGS + 1))
    fi
    ;;
  7|draft|write)
    # Drafting: check manuscript draft exists with minimum word count
    DRAFT_FILE=$(find "$PROJ/drafts" -name "*.md" 2>/dev/null | head -1 || true)
    if [ -z "$DRAFT_FILE" ]; then
      REPORT="${REPORT}\n  FAIL: No manuscript draft found in $PROJ/drafts/"
      ISSUES=$((ISSUES + 1))
    else
      # Minimum 5000 words (60% of ~8000 floor for any journal)
      check_word_count "Manuscript draft" "$DRAFT_FILE" 5000
      # Also count total words across all section drafts
      TOTAL_WORDS=0
      while IFS= read -r f; do
        [ -f "$f" ] && TOTAL_WORDS=$((TOTAL_WORDS + $(wc -w < "$f" | tr -d ' ')))
      done < <(find "$PROJ/drafts" -name "draft-*.md" -type f 2>/dev/null)
      if [ "$TOTAL_WORDS" -gt 0 ]; then
        REPORT="${REPORT}\n  INFO: Total words across all section drafts: $TOTAL_WORDS"
        if [ "$TOTAL_WORDS" -lt 3000 ]; then
          REPORT="${REPORT}\n  FAIL: Total draft word count ($TOTAL_WORDS) is below minimum viable threshold (3000)"
          ISSUES=$((ISSUES + 1))
        elif [ "$TOTAL_WORDS" -lt 6000 ]; then
          REPORT="${REPORT}\n  WARN: Total draft word count ($TOTAL_WORDS) may be too low for ASR/AJS/Demography (target 8000-12000)"
          WARNINGS=$((WARNINGS + 1))
        fi
      fi
    fi
    ;;
  7b|verify)
    # Verification: check verification report exists
    VERIFY_FILE=$(find "$PROJ" \( -name "*verification*" -o -name "*verify*" \) 2>/dev/null | grep -v "log" | head -1 || true)
    if [ -z "$VERIFY_FILE" ]; then
      REPORT="${REPORT}\n  FAIL: No verification report found"
      ISSUES=$((ISSUES + 1))
    fi
    ;;
  7c|polish)
    # Style polish: check polished draft exists and em-dash density
    POLISH_FILE=$(find "$PROJ" \( -name "*polish*" -o -name "*style*" \) 2>/dev/null | grep -v "log" | head -1 || true)
    if [ -z "$POLISH_FILE" ]; then
      # Check if latest draft has been updated after Phase 7b
      DRAFT_FILE=$(find "$PROJ/drafts" -name "*.md" -type f -print0 2>/dev/null | xargs -0 ls -t 2>/dev/null | head -1 || true)
      if [ -z "$DRAFT_FILE" ]; then
        REPORT="${REPORT}\n  FAIL: No draft found for polish check"
        ISSUES=$((ISSUES + 1))
      fi
    fi
    # Em-dash density check on latest draft
    DRAFT_FILE=$(find "$PROJ/drafts" -name "*.md" -type f -print0 2>/dev/null | xargs -0 ls -t 2>/dev/null | head -1 || true)
    if [ -n "$DRAFT_FILE" ] && [ -f "$DRAFT_FILE" ]; then
      DASH_COUNT=$(LC_ALL=C grep -o $'\xe2\x80\x94' "$DRAFT_FILE" 2>/dev/null | wc -l | tr -d ' ')
      TOTAL_LINES=$(wc -l < "$DRAFT_FILE" | tr -d ' ')
      APPROX_PAGES=$(( (TOTAL_LINES + 49) / 50 ))
      if [ "$APPROX_PAGES" -gt 0 ]; then
        DASH_PER_PAGE=$(( DASH_COUNT / APPROX_PAGES ))
        if [ "$DASH_PER_PAGE" -gt 2 ]; then
          REPORT="${REPORT}\n  FAIL: Em-dash density too high: $DASH_COUNT dashes across ~$APPROX_PAGES pages ($DASH_PER_PAGE/page, max 2). Re-run /scholar-polish."
          ISSUES=$((ISSUES + 1))
        else
          REPORT="${REPORT}\n  INFO: Em-dash density OK: $DASH_COUNT dashes across ~$APPROX_PAGES pages ($DASH_PER_PAGE/page)"
        fi
      fi
    fi
    ;;
  8|citation)
    # Citation: check for CITATION NEEDED and SOURCE NEEDED markers in draft
    DRAFT_FILE=$(find "$PROJ/drafts" -name "*.md" 2>/dev/null | head -1 || true)
    if [ -n "$DRAFT_FILE" ]; then
      NEEDED=$(grep -c '\[CITATION NEEDED' "$DRAFT_FILE" 2>/dev/null || true)
      if [ "$NEEDED" -gt 0 ]; then
        REPORT="${REPORT}\n  WARN: $NEEDED [CITATION NEEDED] markers remain in draft"
        WARNINGS=$((WARNINGS + 1))
      fi
      SOURCE_NEEDED=$(grep -c '\[SOURCE NEEDED' "$DRAFT_FILE" 2>/dev/null || true)
      if [ "$SOURCE_NEEDED" -gt 0 ]; then
        REPORT="${REPORT}\n  WARN: $SOURCE_NEEDED [SOURCE NEEDED] markers remain in draft"
        WARNINGS=$((WARNINGS + 1))
      fi
      # Check claim verification markers (errors block advancement)
      CLAIM_ERRORS=$(grep -cE '\[CLAIM-(REVERSED|MISCHARACTERIZED|OVERCAUSAL|UNSUPPORTED)[:\]]' "$DRAFT_FILE" || true)
      if [ "$CLAIM_ERRORS" -gt 0 ]; then
        REPORT="${REPORT}\n  FAIL: $CLAIM_ERRORS unresolved claim error markers (REVERSED/MISCHARACTERIZED/OVERCAUSAL/UNSUPPORTED)"
        ISSUES=$((ISSUES + 1))
      fi
      CLAIM_WARNS=$(grep -cE '\[CLAIM-(WRONG-POPULATION|IMPRECISE|NOT-CHECKABLE)[:\]]' "$DRAFT_FILE" || true)
      if [ "$CLAIM_WARNS" -gt 0 ]; then
        REPORT="${REPORT}\n  WARN: $CLAIM_WARNS claim warning markers (WRONG-POPULATION/IMPRECISE/NOT-CHECKABLE)"
        WARNINGS=$((WARNINGS + 1))
      fi
    fi
    ;;
  10|review)
    # Review simulation: check triage dashboard exists
    TRIAGE=$(find "$PROJ" \( -name "*triage*" -o -name "*review-sim*" -o -name "*respond*" \) 2>/dev/null | head -1 || true)
    if [ -z "$TRIAGE" ]; then
      REPORT="${REPORT}\n  FAIL: No review simulation output found"
      ISSUES=$((ISSUES + 1))
    fi
    ;;
  9|submission)
    # Submission package: check cover letter, compliance, AND replication package
    COVER=$(find "$PROJ" -name "*cover-letter*" 2>/dev/null | head -1 || true)
    if [ -z "$COVER" ]; then
      REPORT="${REPORT}\n  WARN: No cover letter found"
      WARNINGS=$((WARNINGS + 1))
    fi
    # Check replication package exists (Phase 9c — most commonly skipped)
    if [ -d "$PROJ/replication-package" ]; then
      REPL_CODE=$(find "$PROJ/replication-package/code" -type f \( -name "*.R" -o -name "*.py" \) 2>/dev/null | wc -l | tr -d ' ')
      REPL_README=$([ -f "$PROJ/replication-package/README.md" ] && echo "1" || echo "0")
      if [ "$REPL_CODE" -eq 0 ]; then
        REPORT="${REPORT}\n  WARN: Replication package exists but code/ is empty"
        WARNINGS=$((WARNINGS + 1))
      fi
      if [ "$REPL_README" -eq 0 ]; then
        REPORT="${REPORT}\n  WARN: Replication package missing README.md"
        WARNINGS=$((WARNINGS + 1))
      fi
    else
      REPORT="${REPORT}\n  FAIL: No replication-package/ directory — Phase 9c (scholar-replication) was skipped"
      ISSUES=$((ISSUES + 1))
    fi
    ;;
  9b|ethics)
    # Ethics compliance: check ethics report exists
    ETHICS=$(find "$PROJ" -name "*ethics*" 2>/dev/null | grep -v "log" | head -1 || true)
    if [ -z "$ETHICS" ]; then
      REPORT="${REPORT}\n  FAIL: No ethics compliance report found"
      ISSUES=$((ISSUES + 1))
    fi
    ;;
  11|assembly)
    # Final assembly: check all 4 output formats exist
    for ext in md docx tex pdf; do
      FINAL=$(find "$PROJ/drafts" -name "manuscript-final*.$ext" 2>/dev/null | head -1 || true)
      if [ -z "$FINAL" ]; then
        REPORT="${REPORT}\n  FAIL: No manuscript-final*.$ext found"
        ISSUES=$((ISSUES + 1))
      fi
    done
    # Check that tables/figures are EMBEDDED in the final manuscript (not just placeholders)
    FINAL_MD=$(find "$PROJ/drafts" -name "manuscript-final*.md" 2>/dev/null | head -1 || true)
    if [ -n "$FINAL_MD" ] && [ -f "$FINAL_MD" ]; then
      # Check for actual table content (markdown pipe tables or ## Table headings)
      TABLE_EMBEDS=$(grep -cE '^## Table|^\|.*\|.*\|' "$FINAL_MD" 2>/dev/null || true)
      # Check for figure embeds (![...] image syntax)
      FIGURE_EMBEDS=$(grep -c '!\[' "$FINAL_MD" 2>/dev/null || true)
      if [ "$TABLE_EMBEDS" -eq 0 ]; then
        REPORT="${REPORT}\n  FAIL: No embedded tables in final manuscript — only placeholders. Run Phase 11 Step 2c to embed actual table content."
        ISSUES=$((ISSUES + 1))
      fi
      if [ "$FIGURE_EMBEDS" -eq 0 ]; then
        REPORT="${REPORT}\n  FAIL: No embedded figures in final manuscript — only placeholders. Run Phase 11 Step 2c to embed actual figures."
        ISSUES=$((ISSUES + 1))
      fi
    fi
    ;;
  12|grant|13|presentation|14|auto-improve)
    # Optional phases — minimal checks
    REPORT="${REPORT}\n  INFO: Phase $PHASE is optional — no mandatory checks"
    ;;
  *)
    REPORT="${REPORT}\n  WARN: Unrecognized phase '$PHASE' — only generic checks applied"
    WARNINGS=$((WARNINGS + 1))
    ;;
esac

# --- Check 4: Process log updated for this phase ---
PROCESS_LOG=$(find "$PROJ/logs" -name "process-log-scholar-full-paper*" 2>/dev/null | head -1 || true)
if [ -n "$PROCESS_LOG" ]; then
  PHASE_LOGGED=$(grep -cF "Phase $PHASE" "$PROCESS_LOG" 2>/dev/null || true)
  if [ "$PHASE_LOGGED" -eq 0 ]; then
    REPORT="${REPORT}\n  WARN: Phase $PHASE not found in process log"
    WARNINGS=$((WARNINGS + 1))
  fi
fi

# --- Report ---
echo ""
if [ "$ISSUES" -gt 0 ]; then
  echo "FAIL: $ISSUES issue(s), $WARNINGS warning(s)"
  echo -e "$REPORT"
  echo ""
  echo "Fix all FAIL items before advancing to the next phase."
  exit 1
elif [ "$WARNINGS" -gt 0 ]; then
  echo "PASS with $WARNINGS warning(s)"
  echo -e "$REPORT"
  exit 0
else
  echo "PASS: Phase $PHASE verification complete"
  exit 0
fi
