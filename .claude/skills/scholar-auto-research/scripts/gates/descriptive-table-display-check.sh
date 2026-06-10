#!/usr/bin/env bash
# descriptive-table-display-check.sh — reader-facing descriptives gate.
#
# Quantitative sociology manuscripts normally give readers a descriptive
# statistics table for all modeled variables. This gate catches the failure
# mode where descriptives were generated and locked, but never rendered or
# called out in the manuscript.

set -uo pipefail
export LC_ALL=C

PROJ="${1:-}"
if [ -z "$PROJ" ] || [ ! -d "$PROJ" ]; then
  echo "STATUS=YELLOW"
  echo "REASON=usage: descriptive-table-display-check.sh <project_dir>"
  exit 2
fi

SPEC="$PROJ/analysis/spec-registry.csv"
if [ ! -f "$SPEC" ]; then
  echo "STATUS=INERT"
  echo "REASON=no_quantitative_spec_registry"
  exit 3
fi

MS=""
for cand in \
  "$PROJ/manuscript/manuscript-draft.md" \
  "$PROJ/final/manuscript-final.md" \
  "$PROJ/submission/manuscript-submission.md"
do
  if [ -f "$cand" ]; then
    MS="$cand"
    break
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

result=$(python3 - "$PROJ" "$MS" <<'PY'
import json
import re
import sys
from pathlib import Path

proj = Path(sys.argv[1])
ms_path = Path(sys.argv[2])
text = ms_path.read_text(encoding="utf-8", errors="replace")


def norm(value):
    return re.sub(r"[^a-z0-9]+", " ", str(value or "").lower()).strip()


def load_json(path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {}


def nested_values(obj, key):
    if isinstance(obj, dict):
        for k, v in obj.items():
            if k == key:
                yield v
            yield from nested_values(v, key)
    elif isinstance(obj, list):
        for item in obj:
            yield from nested_values(item, key)


def target_journal():
    candidates = []
    for path in (
        proj / "manuscript" / "journal-spec.json",
        proj / "manuscript" / "manuscript-blueprint.json",
        proj / "idea" / "journal-fit.json",
        proj / "idea" / "research-question.json",
    ):
        data = load_json(path)
        candidates.extend(nested_values(data, "target_journal"))
        candidates.extend(nested_values(data, "primary_target"))
        if isinstance(data.get("target_journal"), dict):
            candidates.extend(data["target_journal"].values())
    for candidate in candidates:
        if str(candidate or "").strip():
            return norm(candidate)
    return ""


def descriptive_requirement():
    reqs = set()
    for path in (
        proj / "manuscript" / "journal-spec.json",
        proj / "manuscript" / "manuscript-blueprint.json",
        proj / "idea" / "journal-fit.json",
    ):
        data = load_json(path)
        reqs.update(norm(v) for v in nested_values(data, "descriptive_table_requirement"))
    if reqs & {"table 1 mandatory", "table 1 required for quantitative"}:
        return True
    journal = target_journal()
    default_required = {
        "american sociological review",
        "asr",
        "american journal of sociology",
        "ajs",
        "journal of marriage and family",
        "jmf",
        "demography",
        "social forces",
        "social problems",
        "population and development review",
        "pdr",
        "poetics",
        "sociological methods and research",
        "smr",
    }
    return any(journal == item or (len(item) > 3 and item in journal) for item in default_required)


if not descriptive_requirement():
    print("INERT:descriptive_table_not_required_by_profile")
    raise SystemExit


def descriptive_item(item):
    if not isinstance(item, dict):
        return False
    hay = " ".join(
        str(item.get(key, ""))
        for key in (
            "artifact_role",
            "source_path",
            "locked_path",
            "display_label",
            "caption_text",
            "display_type",
            "results_callout",
        )
    )
    return bool(re.search(r"\b(descript\w*|summary statistics|sample characteristics|table1|table-1)\b", hay, re.I))


def visible_descriptive_table(markdown):
    label_rx = r"(?:Table\s+1|Appendix\s+Table\s+A?1|Table\s+A?1)"
    title_rx = r"(?:Descriptive|Summary Statistics|Sample Characteristics|Sample Description)"
    if re.search(rf"{label_rx}[^\n]{{0,140}}{title_rx}", markdown, re.I):
        return True
    if re.search(rf"{title_rx}[^\n]{{0,140}}{label_rx}", markdown, re.I):
        return True
    for match in re.finditer(label_rx, markdown, re.I):
        window = markdown[max(0, match.start() - 400) : min(len(markdown), match.end() + 1200)]
        if re.search(title_rx, window, re.I) and re.search(r"(?m)^\s*\|.+\|\s*$", window):
            return True
    return False


manifest_paths = [
    proj / "manuscript" / "draft-manifest.json",
    proj / "final" / "final-manifest.json",
    proj / "submission" / "submission-package-manifest.json",
    proj / "results-locked" / "manifest.json",
]
descriptive_items = []
displayed_items = []
unused_items = []
for path in manifest_paths:
    data = load_json(path)
    lists = []
    if isinstance(data.get("locked_result_coverage"), list):
        lists.append(data["locked_result_coverage"])
    if isinstance(data.get("locked_artifacts"), list):
        lists.append(data["locked_artifacts"])
    if isinstance(data.get("artifact_manifest"), list):
        lists.append(data["artifact_manifest"])
    for items in lists:
        for item in items:
            if not descriptive_item(item):
                continue
            source = str(item.get("source_path") or item.get("path") or "").strip()
            descriptive_items.append(source)
            used = item.get("used_in_manuscript") is True
            rendered = str(item.get("display_status", "")).strip() not in {"", "journal_exempt"}
            role = norm(item.get("artifact_role"))
            if used and (rendered or role in {"reader facing descriptive table", "descriptive table"}):
                displayed_items.append(source)
            elif item.get("used_in_manuscript") is False:
                unused_items.append(source)

visible = visible_descriptive_table(text)
if visible or displayed_items:
    print("GREEN:visible_descriptive_table")
elif descriptive_items:
    unique_unused = sorted(set(x for x in unused_items if x))[:8]
    print("RED:descriptive_artifacts_not_reader_facing=" + ",".join(unique_unused or sorted(set(descriptive_items))[:8]))
else:
    print("RED:no_descriptive_table_artifact_or_display")
PY
)

echo "PROJECT=${PROJ}"
echo "MANUSCRIPT=${MS#$PROJ/}"

case "$result" in
  GREEN:*)
    echo "STATUS=GREEN"
    echo "REASON=descriptive_table_reader_facing"
    echo "DETAIL: ${result#GREEN:}"
    exit 0 ;;
  RED:*)
    echo "STATUS=RED"
    echo "REASON=descriptive_table_not_reader_facing"
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
