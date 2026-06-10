#!/usr/bin/env bash
# survey-weights-check.sh — Phase 8 substantive-quality gate.
#
# Rationale: a common failure is a Table 1 note admitting "models are
# unweighted because the local public files do not contain a verified
# survey weight variable" — when the survey in fact publishes design
# weights that were never loaded, while the manuscript still makes a
# population-level claim. A national-survey population claim without survey
# weights is a classic methodological gap.
#
# Contract
# --------
# When `data/data-status.json` indicates the dataset matches an entry in
# `references/weighted-survey-registry.json`, the design blueprint MUST
# declare `measurement_strategy.weights_policy ∈
# {apply_published_weights, apply_constructed_weights, unweighted_with_justification}`.
# When the policy is `apply_published_weights` or `apply_constructed_weights`,
# the analysis scripts MUST invoke a weighted-estimator function.
#
# Detection
# ---------
# Dataset detection tries (1) top-level `dataset_id`, (2) fuzzy match of
# files[].source / files[].path against registry long_name / dataset_id.
# Registry path is configurable via SCHOLAR_WEIGHTED_SURVEY_REGISTRY env
# var; default is the auto-research references file.
#
# Severity
# --------
#   RED    — dataset matches registry; weights_policy declared as
#            apply_*; analysis scripts contain no weighted-estimator call
#   RED    — dataset matches registry; weights_policy NOT declared
#   YELLOW — weights_policy = unweighted_with_justification but no
#            justification text in design blueprint
#   GREEN  — policy applied (or correctly declared as unweighted with
#            justification)
#   INERT  — dataset not in registry (gate doesn't apply)
#
# Inputs
# ------
#   $1   project directory (required)
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
if [ -z "$PROJ" ] || [ ! -d "$PROJ" ]; then
  echo "STATUS=YELLOW"
  echo "REASON=usage: survey-weights-check.sh <project_dir>"
  exit 2
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "STATUS=YELLOW"
  echo "REASON=no_python3"
  exit 2
fi

# Resolve registry location
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_REGISTRY="$SELF_DIR/../../skills/scholar-auto-research/references/weighted-survey-registry.json"
REGISTRY="${SCHOLAR_WEIGHTED_SURVEY_REGISTRY:-$DEFAULT_REGISTRY}"

if [ ! -f "$REGISTRY" ]; then
  echo "STATUS=YELLOW"
  echo "REASON=registry_missing"
  echo "DETAIL: ${REGISTRY}"
  exit 2
fi

DATA_STATUS="$PROJ/data/data-status.json"
BLUEPRINT="$PROJ/design/design-blueprint.json"

if [ ! -f "$DATA_STATUS" ]; then
  echo "STATUS=INERT"
  echo "REASON=no_data_status"
  exit 3
fi

# Collect analysis script paths
SCRIPT_PATHS=()
for d in "$PROJ/scripts" "$PROJ/analysis/scripts"; do
  if [ -d "$d" ]; then
    while IFS= read -r f; do
      [ -n "$f" ] && SCRIPT_PATHS+=("$f")
    done < <(find "$d" -maxdepth 2 -type f \( -name "*.R" -o -name "*.py" \) 2>/dev/null)
  fi
done

result=$(python3 - "$DATA_STATUS" "$BLUEPRINT" "$REGISTRY" "${SCRIPT_PATHS[@]+"${SCRIPT_PATHS[@]}"}" <<'PY'
import json, pathlib, re, sys

data_status_path = pathlib.Path(sys.argv[1])
blueprint_path = pathlib.Path(sys.argv[2])
registry_path = pathlib.Path(sys.argv[3])
script_list = list(sys.argv[4:])

try:
    registry = json.loads(registry_path.read_text(encoding="utf-8"))
except Exception as exc:
    print(f"YELLOW:bad_registry:{exc}")
    sys.exit(0)

try:
    ds = json.loads(data_status_path.read_text(encoding="utf-8"))
except Exception as exc:
    print(f"YELLOW:bad_data_status:{exc}")
    sys.exit(0)

datasets = registry.get("datasets") or []
known = {(d.get("dataset_id") or "").strip().lower(): d for d in datasets if isinstance(d, dict)}
known_long = {(d.get("long_name") or "").strip().lower(): d for d in datasets if isinstance(d, dict)}

# 1. Detect dataset
matched = None

top_id = (ds.get("dataset_id") or "").strip().lower()
if top_id and top_id in known:
    matched = known[top_id]

if matched is None:
    # Fuzzy match files[].source / files[].path against registry
    files = ds.get("files") or []
    for f in files:
        if not isinstance(f, dict):
            continue
        text = " ".join([
            str(f.get("source") or ""),
            str(f.get("path") or ""),
            str(f.get("provenance") or ""),
        ]).lower()
        if not text:
            continue
        # exact dataset_id token match
        for did, dentry in known.items():
            # avoid false positives — require word-boundary match for short ids
            if re.search(rf"\b{re.escape(did)}\b", text):
                matched = dentry; break
        if matched: break
        # long_name substring match (covers "China Family Panel Studies")
        for ln, dentry in known_long.items():
            if ln and ln in text:
                matched = dentry; break
        if matched: break

if matched is None:
    print("INERT:dataset_not_in_registry")
    sys.exit(0)

dataset_id = matched.get("dataset_id") or "<unknown>"

# 2. Read declared policy from blueprint
declared_policy = None
declared_justification = None
if blueprint_path.exists():
    try:
        bp = json.loads(blueprint_path.read_text(encoding="utf-8"))
        ms = bp.get("measurement_strategy") or {}
        declared_policy = (ms.get("weights_policy") or "").strip() or None
        declared_justification = (ms.get("weights_justification") or "").strip() or None
    except Exception:
        pass

if declared_policy is None:
    print(f"RED:weights_policy_undeclared:{dataset_id}")
    sys.exit(0)

if declared_policy == "unweighted_with_justification":
    if not declared_justification or len(declared_justification) < 30:
        print(f"YELLOW:unweighted_without_justification:{dataset_id}")
        sys.exit(0)
    print(f"GREEN:unweighted_with_justification:{dataset_id}")
    sys.exit(0)

if declared_policy not in {"apply_published_weights", "apply_constructed_weights"}:
    print(f"YELLOW:unknown_policy_value:{declared_policy}")
    sys.exit(0)

# 3. Verify scripts invoke a weighted estimator
WEIGHTED_PATTERNS = [
    r"\bsvyglm\s*\(",
    r"\bsvy_lm\s*\(",
    r"\bsvy_glm\s*\(",
    r"\bsurvey::svydesign\s*\(",
    r"(?<![A-Za-z_])svydesign\s*\(",
    r"\bsvrepdesign\s*\(",
    r"\blm\s*\([^)]*\bweights\s*=",
    r"\bglm\s*\([^)]*\bweights\s*=",
    r"\bfeols\s*\([^)]*\bweights\s*=",
    r"\bfeglm\s*\([^)]*\bweights\s*=",
    r"\blmer\s*\([^)]*\bweights\s*=",
    r"\bglmer\s*\([^)]*\bweights\s*=",
    r"\bcoxph\s*\([^)]*\bweights\s*=",
    # Python statsmodels
    r"\bWLS\s*\(",
    r"\bGLM\s*\([^)]*\bfreq_weights\s*=",
    r"\.fit\s*\([^)]*\bweights\s*=",
]

found = []
for script in script_list:
    try:
        with open(script, "r", encoding="utf-8", errors="ignore") as fh:
            text = fh.read()
    except Exception:
        continue
    for p in WEIGHTED_PATTERNS:
        if re.search(p, text):
            found.append(pathlib.Path(script).name)
            break

if not found:
    print(f"RED:declared_but_not_invoked:{dataset_id}")
    sys.exit(0)

print(f"GREEN:weighted_estimator_invoked:{dataset_id}:" + ",".join(sorted(set(found))[:5]))
PY
)

echo "PROJECT=${PROJ}"

case "$result" in
  GREEN:*)
    rest="${result#GREEN:}"
    echo "STATUS=GREEN"
    echo "REASON=${rest%%:*}"
    echo "DETAIL: ${rest#*:}"
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
    reason="${rest%%:*}"
    detail="${rest#*:}"
    echo "STATUS=RED"
    echo "REASON=${reason}"
    echo "DETAIL: ${detail}"
    cat >&2 <<EOF
FAIL: survey weights — the dataset matches the weighted-survey registry
but the analysis is not weighted. A national-population claim from a
weighted-survey dataset requires either applying the published weights
(via svyglm / svydesign / lm-with-weights / feols-with-weights) or an
explicit unweighted_with_justification declaration in the design
blueprint with prose justification at measurement_strategy.weights_justification.
EOF
    exit 1 ;;
  *)
    echo "STATUS=YELLOW"
    echo "REASON=unexpected_python_output"
    echo "DETAIL: ${result}"
    exit 2 ;;
esac
