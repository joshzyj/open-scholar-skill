#!/usr/bin/env bash
# locked-artifact-transclusion-check.sh — Phase 13 / 19 / 20 lock-fidelity
# gate.
#
# Rationale: a common failure is Phase 13 / Phase 19 rebuilding the main
# regression Table 1 from `tables/model-estimates.csv` using hardcoded
# focal-coefficient + SE + p + N rows. The locked HTML/TeX regression
# artifact exists and is correct, but the manuscript embeds a hand-built
# focal extract instead — so the lock contract is satisfied at the artifact
# level but defeated at the display level.
#
# Contract
# --------
# For every artifact whose `artifact_role` in `results-locked/manifest.json`
# is `main_regression_table` (or `regression_table`), the file referenced
# by `source_path` must:
#   1. EXIST at `${PROJ}/${source_path}`;
#   2. HASH-MATCH `sha256` recorded in the manifest.
# This catches the "Phase 13 silently rewrote Table 1" failure mode.
#
# This gate is a sibling of (and lighter than) the existing
# `manuscript-shape-check.sh`. It is not a content-shape check — it is
# a lock-fidelity check. If the locked artifact was a focal extract,
# this gate will pass; the engine-purity gate
# `regression-table-export-check.sh` and the focal-summary detector in
# `auto-research-verify.sh` are the gates that catch a focal-extract
# locked artifact.
#
# Inputs
# ------
#   $1   project directory (required)
#
# Exit codes
# ----------
#   0  STATUS=GREEN   every regression-table locked artifact is intact
#   1  STATUS=RED     ≥1 main_regression_table source_path missing or
#                     hash mismatch
#   2  STATUS=YELLOW  manifest absent / no regression-table entries yet
#   3  STATUS=INERT   no results-locked directory at all

set -uo pipefail
export LC_ALL=C

PROJ="${1:-}"
if [ -z "$PROJ" ] || [ ! -d "$PROJ" ]; then
  echo "STATUS=YELLOW"
  echo "REASON=usage: locked-artifact-transclusion-check.sh <project_dir>"
  exit 2
fi

LOCK_DIR="$PROJ/results-locked"
MANIFEST="$LOCK_DIR/manifest.json"

if [ ! -d "$LOCK_DIR" ]; then
  echo "STATUS=INERT"
  echo "REASON=no_results_locked_dir"
  exit 3
fi

if [ ! -f "$MANIFEST" ]; then
  echo "STATUS=YELLOW"
  echo "REASON=no_manifest_yet"
  exit 2
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "STATUS=YELLOW"
  echo "REASON=no_python3"
  exit 2
fi

result=$(python3 - "$PROJ" "$MANIFEST" <<'PY'
import hashlib, json, pathlib, sys

proj = pathlib.Path(sys.argv[1])
manifest_path = pathlib.Path(sys.argv[2])

REG_ROLES = {"main_regression_table", "regression_table"}

try:
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
except Exception as exc:
    print(f"YELLOW:bad_manifest:{exc}")
    sys.exit(0)

artifacts = manifest.get("locked_artifacts") or []
reg_entries = [a for a in artifacts if isinstance(a, dict) and a.get("artifact_role") in REG_ROLES]

if not reg_entries:
    print("YELLOW:no_regression_table_entries")
    sys.exit(0)

def sha256(path):
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()

failures = []
for entry in reg_entries:
    src = (entry.get("source_path") or "").strip()
    expected = (entry.get("sha256") or "").strip()
    if not src or not expected:
        failures.append(f"manifest_entry_incomplete:{src}")
        continue
    src_path = proj / src
    if not src_path.exists():
        failures.append(f"missing_source:{src}")
        continue
    actual = sha256(src_path)
    if actual != expected:
        failures.append(f"hash_mismatch:{src}:expected={expected[:12]}:actual={actual[:12]}")

if failures:
    print("RED:" + "|".join(failures))
else:
    print(f"GREEN:{len(reg_entries)}")
PY
)

echo "PROJECT=${PROJ}"

case "$result" in
  GREEN:*)
    n="${result#GREEN:}"
    echo "STATUS=GREEN"
    echo "REASON=locked_regression_artifacts_intact"
    echo "DETAIL: ${n} regression-table entries verified"
    exit 0 ;;
  YELLOW:*)
    echo "STATUS=YELLOW"
    echo "REASON=${result#YELLOW:}"
    exit 2 ;;
  RED:*)
    echo "STATUS=RED"
    echo "REASON=locked_regression_artifact_drift"
    echo "DETAIL: ${result#RED:}"
    cat >&2 <<EOF
FAIL: locked artifact transclusion — at least one regression-table
artifact recorded in results-locked/manifest.json no longer matches its
recorded sha256. A Phase 13 / 19 / 20 builder probably rebuilt the
table from CSV instead of carrying the locked HTML/TeX forward. Restore
the source_path file from the locked snapshot, or regenerate the lock
if the table was legitimately re-rendered.
EOF
    exit 1 ;;
  *)
    echo "STATUS=YELLOW"
    echo "REASON=unexpected_python_output"
    echo "DETAIL: ${result}"
    exit 2 ;;
esac
