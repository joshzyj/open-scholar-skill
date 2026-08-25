#!/usr/bin/env bash
# effect-size-narrative-check.sh — Phase 13 / Phase 11.5 substantive-quality gate.
#
# VENDORED COPY for scholar-auto-research (F1, audit 2026-07-07). Kept in sync
# with the repo-root scripts/gates/ original; system-gate-smoke now discovers it
# via the `GATE_DIR / "<name>.sh"` extraction pattern and REDs if it is missing.
# Delta from the repo-root copy: the PHASE_TAG default falls back to
# $AUTO_RESEARCH_VERIFY_PHASE (exported by the verifier's run_external_gate) so
# an env-only invocation still resolves to the current phase; the auto-research
# verifier ALSO passes an explicit "18" positional at the Phase 18 call site, so
# the RED-at-18 behavior does not depend on the env default alone.
#
# Audit 2026-05-06 (cfps-platform-trust-asr-auto): nine focal models with
# R² ranging 0.025–0.064 — the headline associations explain at most 6%
# of variance in trust. The manuscript never acknowledged this in prose
# while claiming to "speak to ASR-level debates." Small explanatory power
# isn't disqualifying, but unacknowledged small explanatory power
# combined with strong interpretive prose is overclaim.
#
# Contract
# --------
# When `tables/model-fit-stats.csv` records any focal-status spec with
# r_squared / pseudo_r_squared / mcfadden_r2 < 0.05, the manuscript
# (Methods OR Results OR Discussion) MUST contain a sentence that:
#   - mentions R² / explanatory power / variance explained, AND
#   - is paired with at least one of: small, modest, limited, restricted,
#     narrow, low, partial, "among many factors", "one factor among"
#
# Override: `[ALLOW-SMALL-R2: <reason>]` annotation in the same paragraph.
#
# Severity
# --------
#   RED at Phase 11.5 hygiene if absent and at least one focal model has R² < 0.05
#   YELLOW at Phase 13 (still time to fix in revision)
#   GREEN if no small-R² focal models OR acknowledgment present
#   INERT if no model-fit-stats.csv (gate skipped, no quant work)
#
# Inputs
# ------
#   $1   project directory (required)
#   $2   optional phase tag (`13` for YELLOW; `11.5` or `19` or `20` for RED)
#
# Exit codes
# ----------
#   0  STATUS=GREEN
#   1  STATUS=RED
#   2  STATUS=YELLOW
#   3  STATUS=INERT
#

set -uo pipefail
export LC_ALL=C

PROJ="${1:-}"
# Vendored delta (F1): fall back to the verifier-exported phase before the
# literal 13, so an env-only call still RED-tags at hygiene phases. The Phase 18
# call site passes an explicit "18" positional regardless.
PHASE_TAG="${2:-${AUTO_RESEARCH_VERIFY_PHASE:-13}}"
if [ -z "$PROJ" ] || [ ! -d "$PROJ" ]; then
  echo "STATUS=YELLOW"
  echo "REASON=usage: effect-size-narrative-check.sh <project_dir> [phase]"
  exit 2
fi

FIT_STATS="$PROJ/tables/model-fit-stats.csv"
if [ ! -f "$FIT_STATS" ]; then
  echo "STATUS=INERT"
  echo "REASON=no_model_fit_stats"
  exit 3
fi

# Pick a manuscript file
MS=""
for cand in "$PROJ/manuscript/manuscript-draft.md" "$PROJ/final/manuscript-final.md" "$PROJ/submission/manuscript-submission.md"; do
  if [ -f "$cand" ]; then
    MS="$cand"; break
  fi
done

if [ -z "$MS" ]; then
  echo "STATUS=YELLOW"
  echo "REASON=no_manuscript_yet"
  exit 2
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "STATUS=YELLOW"
  echo "REASON=no_python3"
  exit 2
fi

result=$(python3 - "$FIT_STATS" "$MS" "$PHASE_TAG" <<'PY'
import csv, pathlib, re, sys

fit_path = pathlib.Path(sys.argv[1])
ms_path = pathlib.Path(sys.argv[2])
phase_tag = sys.argv[3]

THRESHOLD = 0.05

# Identify small-R² focal specs
small_focal = []
with fit_path.open(newline="", encoding="utf-8") as f:
    reader = csv.DictReader(f)
    for row in reader:
        spec_id = (row.get("spec_id") or "").strip()
        status = (row.get("status") or "").strip().lower()
        if status != "focal":
            continue
        # Try multiple fit-statistic columns
        for col in ("r_squared", "pseudo_r_squared", "mcfadden_r2", "adj_r_squared"):
            val = (row.get(col) or "").strip()
            if not val:
                continue
            try:
                v = float(val)
            except ValueError:
                continue
            if v < THRESHOLD:
                small_focal.append({"spec_id": spec_id, "stat": col, "value": v})
                break

if not small_focal:
    print("GREEN:no_small_r2_focal_models")
    sys.exit(0)

# Read manuscript
text = ms_path.read_text(encoding="utf-8", errors="replace")

# Override
if re.search(r"\[ALLOW-SMALL-R2:", text):
    print("GREEN:override_present")
    sys.exit(0)

# Acknowledgment detection: a sentence that mentions R²/explanatory
# power AND a small-magnitude qualifier.
SENTENCE_SPLIT = re.compile(r"(?<=[.!?])\s+")
R2_TERMS = re.compile(
    r"\bR(?:-?)?(?:\^?2|squared)\b"
    r"|explanatory power"
    r"|variance explained"
    r"|model fit"
    r"|adjusted R(?:-?)?(?:\^?2|squared)"
    r"|McFadden",
    re.IGNORECASE,
)
SMALL_QUALIFIERS = re.compile(
    r"\b(?:small|modest|limited|restricted|narrow|low|partial|"
    r"weak|tiny|moderate|among many|one factor|one of many|"
    r"explains?\s+only)\b",
    re.IGNORECASE,
)

acknowledged = False
for sentence in SENTENCE_SPLIT.split(text):
    if R2_TERMS.search(sentence) and SMALL_QUALIFIERS.search(sentence):
        acknowledged = True
        break

if acknowledged:
    print(f"GREEN:acknowledgment_present:{len(small_focal)}")
    sys.exit(0)

# Mismatch — emit RED at hygiene-tier phases, YELLOW at Phase 13
spec_list = ",".join(s["spec_id"] for s in small_focal[:8])
if phase_tag in {"11.5", "19", "20", "18"}:
    print(f"RED:small_r2_unacknowledged:{spec_list}")
else:
    print(f"YELLOW:small_r2_unacknowledged:{spec_list}")
PY
)

echo "PROJECT=${PROJ}"
echo "MANUSCRIPT=${MS#$PROJ/}"
echo "PHASE_TAG=${PHASE_TAG}"

case "$result" in
  GREEN:*)
    rest="${result#GREEN:}"
    echo "STATUS=GREEN"
    echo "REASON=${rest%%:*}"
    detail="${rest#*:}"
    [ "$detail" != "$rest" ] && echo "DETAIL: ${detail}"
    exit 0 ;;
  INERT:*)
    echo "STATUS=INERT"
    echo "REASON=${result#INERT:}"
    exit 3 ;;
  YELLOW:*)
    rest="${result#YELLOW:}"
    echo "STATUS=YELLOW"
    echo "REASON=${rest%%:*}"
    echo "DETAIL: ${rest#*:}"
    exit 2 ;;
  RED:*)
    rest="${result#RED:}"
    echo "STATUS=RED"
    echo "REASON=${rest%%:*}"
    echo "DETAIL: ${rest#*:}"
    cat >&2 <<EOF
FAIL: effect-size narrative — at least one focal-status spec has
R² (or pseudo-R² / McFadden R²) below 0.05 and the manuscript prose
does not acknowledge the small explanatory power. Add a sentence in
Methods, Results, or Discussion that mentions R² (or "explanatory
power" / "variance explained") paired with a magnitude qualifier
(small, modest, limited, "among many factors"). Override available via
[ALLOW-SMALL-R2: <reason>] annotation.
EOF
    exit 1 ;;
  *)
    echo "STATUS=YELLOW"
    echo "REASON=unexpected_python_output"
    echo "DETAIL: ${result}"
    exit 2 ;;
esac
