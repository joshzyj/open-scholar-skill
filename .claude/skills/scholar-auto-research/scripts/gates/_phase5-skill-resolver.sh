#!/usr/bin/env bash
# _phase5-skill-resolver.sh — internal helper for Phase 5 design-aware checks.
#
# Resolves the controlled-vocabulary `primary_execution_skill` field from
# identification-strategy.json and emits design-aware decisions as
# KEY=VALUE shell-evalable output.
#
# Consumed by:
#   - auto-research-verify.sh Phase 5 (Layer 1: per-row covariates emptiness check)
#   - control-variables-check.sh    (Layer 2: design-aware control-variables gate)
#
# Single source of truth for which method families allow empty `covariates`.
# Per design-contract.md lines 51-60, primary_execution_skill is one of:
#   scholar-analyze   — quantitative/observational/experimental (regression family)
#   scholar-compute   — computational
#   scholar-qual      — qualitative
#   scholar-ling      — linguistic
#
# Output format (always emits both lines, even on failure paths):
#   PRIMARY_EXECUTION_SKILL=<value-or-empty>
#   COVARIATES_OPTIONAL=true|false
#
# Exit codes:
#   0 — success (output is authoritative)
#   2 — usage error
#
# Safe-default semantic: when the file is missing, malformed, or the routing
# object is absent, emit empty PRIMARY and COVARIATES_OPTIONAL=false (strict).
# Callers can ALWAYS trust that COVARIATES_OPTIONAL=true means "verified
# non-regression family"; the default never relaxes.

set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "PRIMARY_EXECUTION_SKILL="
  echo "COVARIATES_OPTIONAL=false"
  echo "ERROR=usage: _phase5-skill-resolver.sh <project_dir>" >&2
  exit 2
fi

PROJ="$1"
ID_JSON="$PROJ/design/identification-strategy.json"

PRIMARY=""
if [ -f "$ID_JSON" ] && command -v python3 >/dev/null 2>&1; then
  PRIMARY=$(python3 -c "
import json, sys
try:
    d = json.load(open('$ID_JSON'))
    r = d.get('method_specialist_routing') or {}
    v = r.get('primary_execution_skill') or ''
    print(str(v).strip())
except Exception:
    pass
" 2>/dev/null) || PRIMARY=""
fi

# Skills where covariates may be legitimately empty.
# MUST stay in sync with design-contract.md lines 51-60.
case "$PRIMARY" in
  scholar-compute|scholar-qual|scholar-ling) COV_OPT=true ;;
  *)                                          COV_OPT=false ;;
esac

echo "PRIMARY_EXECUTION_SKILL=$PRIMARY"
echo "COVARIATES_OPTIONAL=$COV_OPT"
exit 0
