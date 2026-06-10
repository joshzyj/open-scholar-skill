#!/usr/bin/env bash
# figure-style-source-check.sh — verify shared visualization style is used and packaged.
#
# When a project reports ggplot2 figures governed by analysis/scripts/viz_setting.R,
# the figure-producing scripts must source and apply that style, and the
# replication package must include the shared style file if it includes scripts
# that source it.

set -uo pipefail
export LC_ALL=C
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CANONICAL_STYLE="$(cd "$SCRIPT_DIR/../.." && pwd)/references/viz_setting.R"

PROJ="${1:-}"
if [ -z "$PROJ" ] || [ ! -d "$PROJ" ]; then
  echo "STATUS=YELLOW"
  echo "REASON=usage: figure-style-source-check.sh <project_dir>"
  exit 2
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "STATUS=YELLOW"
  echo "REASON=no_python3"
  exit 2
fi

result=$(python3 - "$PROJ" "$CANONICAL_STYLE" <<'PY'
import json
import hashlib
import re
import sys
from pathlib import Path

proj = Path(sys.argv[1])
canonical_style = Path(sys.argv[2])

def sha256(path):
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()

def read_text(path):
    try:
        return path.read_text(encoding="utf-8", errors="replace")
    except Exception:
        return ""

def load_json(path):
    try:
        return json.loads(read_text(path))
    except Exception:
        return {}

execution = load_json(proj / "analysis" / "execution-report.json")
style_source = ""
if isinstance(execution.get("analysis_stack"), dict):
    style_source = str(execution["analysis_stack"].get("viz_style_source") or "")
if not style_source:
    style_source = str(execution.get("viz_style_source") or "")
if not style_source:
    provenance = load_json(proj / "tables" / "analysis-output-provenance.json")
    style_source = str(provenance.get("shared_visual_style") or "")

figure_registry = proj / "figures" / "figure-registry.csv"
r_scripts = list((proj / "scripts").glob("**/*.R")) + list((proj / "analysis").glob("**/*.R"))
script_text = "\n".join(read_text(path) for path in r_scripts)
uses_ggplot = bool(re.search(r"\bggplot\s*\(|ggsave\s*\(|geom_", script_text)) or figure_registry.exists()

if not uses_ggplot and not style_source:
    print("INERT:no_ggplot_style_requirement_detected")
    raise SystemExit

issues = []
if not style_source:
    issues.append("missing_viz_style_source_in_execution_report")
else:
    style_path = proj / style_source
    if not style_path.exists():
        issues.append(f"missing_style_file:{style_source}")
    elif not canonical_style.exists():
        issues.append("missing_bundled_canonical_style:references/viz_setting.R")
    elif sha256(style_path) != sha256(canonical_style):
        issues.append(f"style_file_not_copied_from_canonical:{style_source}")
    stack = execution.get("analysis_stack") if isinstance(execution.get("analysis_stack"), dict) else {}
    if stack:
        if str(stack.get("viz_style_reference") or "") != "references/viz_setting.R":
            issues.append("missing_or_wrong_viz_style_reference")
        canonical_hash = sha256(canonical_style) if canonical_style.exists() else ""
        if str(stack.get("viz_style_sha256") or "") != canonical_hash:
            issues.append("missing_or_wrong_viz_style_sha256")

if uses_ggplot:
    if "viz_setting.R" not in script_text:
        issues.append("figure_scripts_do_not_source_viz_setting")
    if not re.search(r"\b(theme_Publication|scale_(?:color|fill)_publication)\s*\(", script_text):
        issues.append("figure_scripts_do_not_apply_publication_theme_or_scales")

rep = proj / "replication-package"
if rep.is_dir():
    rep_scripts = list((rep / "scripts").glob("**/*.R"))
    rep_text = "\n".join(read_text(path) for path in rep_scripts)
    if "viz_setting.R" in rep_text:
        expected = rep / style_source
        if not expected.exists():
            issues.append(f"replication_package_missing_style_file:{style_source}")

if issues:
    print("RED:" + ";".join(issues))
else:
    print("GREEN:style_source=" + (style_source or "none"))
PY
)

echo "PROJECT=${PROJ}"
case "$result" in
  GREEN:*)
    echo "STATUS=GREEN"
    echo "REASON=figure_style_source_packaged_and_applied"
    echo "DETAIL: ${result#GREEN:}"
    exit 0 ;;
  RED:*)
    echo "STATUS=RED"
    echo "REASON=figure_style_source_failure"
    echo "DETAIL: ${result#RED:}"
    exit 1 ;;
  INERT:*)
    echo "STATUS=INERT"
    echo "REASON=${result#INERT:}"
    exit 3 ;;
  YELLOW:*)
    echo "STATUS=YELLOW"
    echo "REASON=${result#YELLOW:}"
    exit 2 ;;
  *)
    echo "STATUS=YELLOW"
    echo "REASON=unexpected_python_output"
    echo "DETAIL: ${result}"
    exit 2 ;;
esac
