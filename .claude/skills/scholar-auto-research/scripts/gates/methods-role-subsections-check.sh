#!/usr/bin/env bash
# methods-role-subsections-check.sh — role-aware Variables/Measures gate.
#
# Quantitative sociology articles normally make measurement roles visible:
# dependent variables / outcomes, independent variables / predictors, and
# control variables / covariates. Some ASR-style articles do this with
# separate Method subheadings; some JMF-style articles use compact
# role-marked prose. This gate accepts either pattern, but rejects an
# undifferentiated methods
# blob that leaves readers to infer variable roles from a model table.

set -uo pipefail
export LC_ALL=C

PROJ="${1:-}"
if [ -z "$PROJ" ] || [ ! -d "$PROJ" ]; then
  echo "STATUS=YELLOW"
  echo "REASON=usage: methods-role-subsections-check.sh <project_dir>"
  exit 2
fi

SPEC="$PROJ/analysis/spec-registry.csv"
DICT="$PROJ/data/variable-dictionary.csv"
if [ ! -f "$SPEC" ] && [ ! -f "$DICT" ]; then
  echo "STATUS=INERT"
  echo "REASON=no_quantitative_role_inputs"
  exit 3
fi

# Path-adapt (master-plan-v4 P1+Update 6): use derive-manuscript-path.sh
# helper to find the active manuscript across BOTH pipeline layouts —
# scholar-auto-research's manuscript/ + final/ + submission/, and
# scholar-full-paper's drafts/ (manuscript-final-*, manuscript-submission-*,
# draft-manuscript-*, plus generic fallback).
_dmp_helper="$(dirname "${BASH_SOURCE[0]:-$0}")/derive-manuscript-path.sh"
if [ -f "$_dmp_helper" ]; then
  # shellcheck disable=SC1090
  . "$_dmp_helper" final 2>/dev/null || true
  MS="${MANUSCRIPT_PATH:-}"
  unset _dmp_helper
fi
# Backup: if helper unavailable, use the original auto-research-only candidate list.
if [ -z "${MS:-}" ]; then
  for cand in \
    "$PROJ/manuscript/manuscript-draft.md" \
    "$PROJ/final/manuscript-final.md" \
    "$PROJ/submission/manuscript-submission.md"
  do
    if [ -f "$cand" ]; then MS="$cand"; break; fi
  done
fi
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

result=$(python3 - "$PROJ" "$MS" <<'PY'
import csv
import re
import sys
from pathlib import Path

proj = Path(sys.argv[1])
ms_path = Path(sys.argv[2])


def norm(value):
    return re.sub(r"[^a-z0-9]+", " ", str(value or "").lower()).strip()


roles = {"outcome": set(), "predictor": set(), "covariate": set()}
spec_path = proj / "analysis" / "spec-registry.csv"
if spec_path.exists():
    with spec_path.open(newline="", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            for col, role in (("outcome", "outcome"), ("predictors", "predictor"), ("covariates", "covariate")):
                for raw in (row.get(col, "") or "").split(";"):
                    raw = raw.strip()
                    if raw and raw not in {"province_indicators", "survey_wave_indicators"}:
                        roles[role].add(raw)

dict_path = proj / "data" / "variable-dictionary.csv"
if dict_path.exists():
    with dict_path.open(newline="", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            var = (row.get("variable") or "").strip()
            role = norm(row.get("role"))
            if not var:
                continue
            if role in {"y", "outcome", "dependent", "dependent variable", "dv"}:
                roles["outcome"].add(var)
            elif role in {"x", "predictor", "independent", "independent variable", "treatment", "exposure", "iv"}:
                roles["predictor"].add(var)
            elif role in {"control", "controls", "covariate", "covariates", "confounder", "fixed effect"}:
                roles["covariate"].add(var)

required = [role for role, vars_ in roles.items() if vars_]
if not required:
    print("INERT:no_roles_detected")
    raise SystemExit

text = ms_path.read_text(encoding="utf-8", errors="replace")
methods_match = re.search(
    r"^##\s+(?:Data,\s*Measures,\s*and Methods|Data and Methods|Data and Method|Materials and Methods|Methods|Method)\s*$"
    r"([\s\S]*?)(?=^##\s+|\Z)",
    text,
    flags=re.I | re.M,
)
if not methods_match:
    print("RED:no_methods_section")
    raise SystemExit

methods = methods_match.group(1)
measures_match = re.search(
    r"^###\s+(?:Variables? and Measures?|Measures?|Measurement|Variable Construction)\s*$"
    r"([\s\S]*?)(?=^###\s+|^##\s+|\Z)",
    methods,
    flags=re.I | re.M,
)
scope = measures_match.group(1) if measures_match else methods

role_patterns = {
    "outcome": [
        r"dependent variables?",
        r"dependent measures?",
        r"outcomes?",
        r"response variables?",
    ],
    "predictor": [
        r"independent variables?",
        r"key independent variables?",
        r"predictors?",
        r"treatments?",
        r"exposures?",
        r"main explanatory variables?",
        r"focal variables?",
    ],
    "covariate": [
        r"control variables?",
        r"covariates?",
        r"adjustment variables?",
        r"controls?",
        r"fixed effects?",
    ],
}


def has_heading(role):
    pattern = "|".join(role_patterns[role])
    return bool(re.search(rf"^####?\s+(?:{pattern})(?:\s|:|$)", methods, re.I | re.M))


def has_role_paragraph(role):
    pattern = "|".join(role_patterns[role])
    paragraphs = [p.strip() for p in re.split(r"\n\s*\n", scope) if p.strip()]
    for paragraph in paragraphs:
        first = " ".join(paragraph.split()[:18])
        if re.search(rf"\b(?:{pattern})\b", first, re.I):
            return True
    return False

missing = [role for role in required if not (has_heading(role) or has_role_paragraph(role))]
if missing:
    print("RED:missing_role_structure=" + ",".join(missing))
else:
    print("GREEN:roles=" + ",".join(required))
PY
)

echo "PROJECT=${PROJ}"
echo "MANUSCRIPT=${MS#$PROJ/}"

case "$result" in
  GREEN:*)
    echo "STATUS=GREEN"
    echo "REASON=method_variable_roles_visible"
    echo "DETAIL: ${result#GREEN:}"
    exit 0 ;;
  RED:*)
    echo "STATUS=RED"
    echo "REASON=method_variable_roles_missing"
    echo "DETAIL: ${result#RED:}"
    exit 1 ;;
  INERT:*)
    echo "STATUS=INERT"
    echo "REASON=${result#INERT:}"
    exit 3 ;;
  *)
    echo "STATUS=YELLOW"
    echo "REASON=unexpected_python_output"
    echo "DETAIL: ${result}"
    exit 2 ;;
esac
