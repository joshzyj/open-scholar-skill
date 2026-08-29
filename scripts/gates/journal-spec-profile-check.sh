#!/usr/bin/env bash
# journal-spec-profile-check.sh — Phase 12/13 gate (audit 2026-05-03).
#
# Problem this gate solves
# ------------------------
# Phase 13 of scholar-auto-research invokes scholar-journal in `prepare` mode
# to author `${PROJ}/manuscript/journal-spec.json`. The contract for that
# write is described prose-only (manuscript-drafting-contract.md §51-53):
# the spec must include `total_word_range`, `abstract_word_cap`, and
# `section_word_budget`. Nothing pins those values to the journal profile
# at `scholar-journal/references/profiles/<key>.json` — so the LLM is free
# to invent the floor, and the in-skill fixture
# (auto-research-fixture-test.sh:4339,4612) seeds `total_word_range.min:
# 1300` regardless of the target journal. Result: a JMF empirical-article
# spec ships with `min: 1300` instead of the JMF profile's calibrated
# `total_word_budget.min: 7000`. Every downstream length gate that uses
# `total_word_range.min` then sees a hollowed-out floor and the realized
# manuscript ends up 2,500–3,500 words for a journal that wants 7,000+.
#
# This gate compares the project's `manuscript/journal-spec.json` against
# the resolved journal profile and fails RED when the spec's
# `total_word_range` does not match the profile's `total_word_budget`. It
# also flags an `abstract_word_cap` that is below the profile's abstract
# `max_words` (which would mean the spec is more restrictive than the
# journal — usually a sign of fixture leakage, not a deliberate choice).
#
# What is NOT enforced
# --------------------
# Per-section budgets are NOT compared field-by-field. Papers may legally
# collapse profile sections (e.g., merge `literature_review` + `theory`
# into a single `Background` per the blueprint's `theory_presentation:
# background_section` mode), so a strict per-section equality check would
# reject valid structural choices. The total-range gate already catches
# the canonical bug (compressed total floor) without forcing per-section
# equality. Per-section size is enforced separately by
# auto-research-verify.sh once `target_words` is in the spec.
#
# Usage
# -----
#   journal-spec-profile-check.sh <project_dir>
#
# Exit codes
# ----------
#   0 GREEN  — spec matches profile (or short-format paper, gate skipped)
#   1 RED    — spec total_word_range disagrees with profile total_word_budget
#   2 YELLOW — profile not found (unknown journal), spec missing, or
#              required tools unavailable; gate is advisory in this case

set -uo pipefail
export LC_ALL=C

PROJ="${1:-}"
if [ -z "$PROJ" ] || [ ! -d "$PROJ" ]; then
  echo "STATUS=YELLOW"
  echo "REASON=usage"
  echo "WARN: usage: journal-spec-profile-check.sh <project_dir>" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HELPER="${SCRIPT_DIR}/get-journal-profile.sh"

SPEC="${PROJ}/manuscript/journal-spec.json"
if [ ! -f "$SPEC" ]; then
  echo "STATUS=YELLOW"
  echo "REASON=spec_missing"
  echo "WARN: ${SPEC} not found — Phase 12/13 has not authored the spec yet." >&2
  exit 2
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "STATUS=YELLOW"
  echo "REASON=python3_missing"
  exit 2
fi

if [ ! -x "$HELPER" ]; then
  echo "STATUS=YELLOW"
  echo "REASON=helper_missing"
  echo "WARN: ${HELPER} is not executable; cannot resolve profile." >&2
  exit 2
fi

# ── Read target_journal + paper_type from the spec ──────────────────────
TARGET_JOURNAL=$(python3 -c "
import json, sys
try:
    d=json.load(open('$SPEC'))
    print(d.get('target_journal','') or '')
except Exception:
    pass
" 2>/dev/null)

PAPER_TYPE=$(python3 -c "
import json, sys
try:
    d=json.load(open('$SPEC'))
    fields=('paper_type','article_type','format')
    print(' '.join(str(d.get(f,'')) for f in fields))
except Exception:
    pass
" 2>/dev/null)

if [ -z "$TARGET_JOURNAL" ]; then
  echo "STATUS=YELLOW"
  echo "REASON=no_target_journal"
  echo "WARN: ${SPEC} has no target_journal field." >&2
  exit 2
fi

# ── Short-format paper exception ───────────────────────────────────────
# Skip when the paper_type matches the same short_format pattern that
# auto-research-verify.sh uses (research note / brief / commentary etc.).
# Those products are exempt from full-empirical word floors.
SHORT_FORMAT=0
case "$(printf '%s' "$PAPER_TYPE" | tr '[:upper:]' '[:lower:]')" in
  *"research note"*|*brief*|*"short report"*|*commentary*|\
  *"registered report"*|*stage*|*"replication note"*|*letter*)
    SHORT_FORMAT=1
    ;;
esac

if [ "$SHORT_FORMAT" -eq 1 ]; then
  echo "STATUS=GREEN"
  echo "REASON=short_format_skip"
  echo "TARGET_JOURNAL=$TARGET_JOURNAL"
  echo "PAPER_TYPE=$PAPER_TYPE"
  exit 0
fi

# ── Resolve the journal profile ────────────────────────────────────────
set +e
HELPER_OUT=$(bash "$HELPER" "$TARGET_JOURNAL" 2>&1)
HELPER_RC=$?
set -e

if [ "$HELPER_RC" -ne 0 ]; then
  echo "STATUS=YELLOW"
  echo "REASON=profile_not_found"
  echo "TARGET_JOURNAL=$TARGET_JOURNAL"
  printf '%s\n' "$HELPER_OUT" >&2
  exit 2
fi

PROFILE_PATH=$(printf '%s\n' "$HELPER_OUT" | grep -E '^PROFILE_PATH=' | head -1 | sed -E 's/^PROFILE_PATH=//')
if [ -z "$PROFILE_PATH" ] || [ ! -f "$PROFILE_PATH" ]; then
  echo "STATUS=YELLOW"
  echo "REASON=profile_path_unresolved"
  echo "TARGET_JOURNAL=$TARGET_JOURNAL"
  exit 2
fi

# ── Compare total_word_range against profile.total_word_budget ─────────
# python3 returns a STATUS line + per-violation lines on stdout.
COMPARE=$(python3 - <<PYEOF
import json, sys

try:
    spec = json.load(open("$SPEC"))
except Exception as exc:
    print(f"STATUS=YELLOW")
    print(f"REASON=spec_parse_failed:{exc}")
    sys.exit(0)

try:
    profile = json.load(open("$PROFILE_PATH"))
except Exception as exc:
    print(f"STATUS=YELLOW")
    print(f"REASON=profile_parse_failed:{exc}")
    sys.exit(0)

violations = []

def as_int(v):
    try:
        return int(v)
    except Exception:
        return None

p_budget = profile.get("total_word_budget") or {}
s_range  = spec.get("total_word_range") or {}

p_min = as_int(p_budget.get("min"))
p_max = as_int(p_budget.get("max"))
s_min = as_int(s_range.get("min"))
s_max = as_int(s_range.get("max"))

if p_min is None or p_max is None:
    print(f"STATUS=YELLOW")
    print(f"REASON=profile_missing_total_word_budget")
    sys.exit(0)

if s_min is None or s_max is None:
    violations.append(f"spec.total_word_range missing or invalid (got {s_range!r})")
else:
    if s_min != p_min:
        violations.append(
            f"spec.total_word_range.min={s_min} but profile.total_word_budget.min={p_min} "
            f"(journal {profile.get('name','?')}); the spec has been hollowed out below the journal's calibrated floor"
        )
    if s_max != p_max:
        violations.append(
            f"spec.total_word_range.max={s_max} but profile.total_word_budget.max={p_max}"
        )

# Soft check: abstract_word_cap should not be lower than the profile's
# abstract.max_words. A lower cap means the spec is more restrictive than
# the journal — usually a sign of stale defaults.
profile_abstract_max = as_int(((profile.get("sections") or {}).get("abstract") or {}).get("max_words"))
spec_abstract_cap = as_int(spec.get("abstract_word_cap"))
soft_warnings = []
if profile_abstract_max is not None and spec_abstract_cap is not None:
    if spec_abstract_cap < profile_abstract_max:
        soft_warnings.append(
            f"spec.abstract_word_cap={spec_abstract_cap} is below profile.sections.abstract.max_words={profile_abstract_max}"
        )

# Soft check: section_word_budget sum sanity. Sum of target_words must fit
# inside profile total_word_budget. This is a coarse check that catches
# every-section-shrunk-to-floor cases without forcing per-section equality.
sec_budget = spec.get("section_word_budget") or {}
sum_targets = 0
sum_targets_seen = 0
for sec_name, sec in sec_budget.items():
    if not isinstance(sec, dict):
        continue
    tw = as_int(sec.get("target_words"))
    if tw is not None and tw > 0:
        sum_targets += tw
        sum_targets_seen += 1

if sum_targets_seen >= 4:
    if sum_targets < int(p_min * 0.85):
        violations.append(
            f"sum of section_word_budget.target_words={sum_targets} is below 85% of profile.total_word_budget.min={p_min} "
            f"(journal {profile.get('name','?')}); section targets do not realize the journal's calibrated total floor"
        )

if violations:
    print("STATUS=RED")
    print(f"TARGET_JOURNAL={profile.get('name','')}")
    print(f"PROFILE_PATH=$PROFILE_PATH")
    print(f"PROFILE_TOTAL_MIN={p_min}")
    print(f"PROFILE_TOTAL_MAX={p_max}")
    print(f"SPEC_TOTAL_MIN={s_min}")
    print(f"SPEC_TOTAL_MAX={s_max}")
    print("VIOLATIONS:")
    for v in violations:
        print(f"  - {v}")
    if soft_warnings:
        print("WARNINGS:")
        for w in soft_warnings:
            print(f"  - {w}")
else:
    print("STATUS=GREEN")
    print(f"TARGET_JOURNAL={profile.get('name','')}")
    print(f"PROFILE_PATH=$PROFILE_PATH")
    print(f"PROFILE_TOTAL_MIN={p_min}")
    print(f"PROFILE_TOTAL_MAX={p_max}")
    print(f"SPEC_TOTAL_MIN={s_min}")
    print(f"SPEC_TOTAL_MAX={s_max}")
    if soft_warnings:
        print("WARNINGS:")
        for w in soft_warnings:
            print(f"  - {w}")
PYEOF
)

# ── Emit + exit ────────────────────────────────────────────────────────
printf '%s\n' "$COMPARE"

STATUS_LINE=$(printf '%s\n' "$COMPARE" | grep -E '^STATUS=' | head -1 | sed -E 's/^STATUS=//')
case "$STATUS_LINE" in
  GREEN)  exit 0 ;;
  YELLOW) exit 2 ;;
  RED)    exit 1 ;;
  *)      exit 2 ;;
esac
