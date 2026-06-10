#!/usr/bin/env bash
# regression-table-family-shape-check.sh — regression table shape gate.
#
# Catches "messy" omnibus regression tables: many model columns, many empty
# cells, and unrelated model families collapsed into one display. A
# modelsummary-style table can have several nested models, but it should not
# be a sparse registry-like matrix across different outcomes/spec families.

set -uo pipefail
export LC_ALL=C

PROJ="${1:-}"
if [ -z "$PROJ" ] || [ ! -d "$PROJ" ]; then
  echo "STATUS=YELLOW"
  echo "REASON=usage: regression-table-family-shape-check.sh <project_dir>"
  exit 2
fi

if [ ! -f "$PROJ/analysis/spec-registry.csv" ] && [ ! -d "$PROJ/tables" ]; then
  echo "STATUS=INERT"
  echo "REASON=no_regression_inputs"
  exit 3
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "STATUS=YELLOW"
  echo "REASON=no_python3"
  exit 2
fi

result=$(python3 - "$PROJ" <<'PY'
import csv
import re
import sys
from pathlib import Path

proj = Path(sys.argv[1])


def norm(value):
    return re.sub(r"[^a-z0-9]+", " ", str(value or "").lower()).strip()


def split_md_row(line):
    return [cell.strip() for cell in line.strip().strip("|").split("|")]


def parse_markdown_tables(text):
    lines = text.splitlines()
    tables = []
    i = 0
    while i < len(lines) - 1:
        if not lines[i].strip().startswith("|"):
            i += 1
            continue
        if not re.match(r"^\|(?:\s*:?-{3,}:?\s*\|)+\s*$", lines[i + 1].strip()):
            i += 1
            continue
        header = split_md_row(lines[i])
        rows = []
        i += 2
        while i < len(lines) and lines[i].strip().startswith("|"):
            rows.append(split_md_row(lines[i]))
            i += 1
        tables.append((header, rows))
    return tables


def html_to_markdownish(text):
    # Minimal fallback for simple HTML tables; keep the parser dependency-free.
    if "<table" not in text.lower():
        return ""
    rows = []
    for tr in re.findall(r"(?is)<tr\b.*?</tr>", text):
        cells = re.findall(r"(?is)<t[dh]\b[^>]*>(.*?)</t[dh]>", tr)
        clean = [re.sub(r"\s+", " ", re.sub(r"(?is)<.*?>", " ", c)).strip() for c in cells]
        if clean:
            rows.append(clean)
    if len(rows) < 2:
        return ""
    out = ["| " + " | ".join(rows[0]) + " |", "| " + " | ".join(["---"] * len(rows[0])) + " |"]
    for row in rows[1:]:
        out.append("| " + " | ".join(row) + " |")
    return "\n".join(out)


def candidate_files():
    preferred = [
        proj / "tables" / "table-main-regression.md",
        proj / "tables" / "table-main-regression.html",
    ]
    seen = set()
    for path in preferred:
        if path.exists():
            seen.add(path)
            yield path
    tables_dir = proj / "tables"
    if tables_dir.exists():
        for path in sorted(tables_dir.glob("*")):
            if path in seen or path.suffix.lower() not in {".md", ".html"}:
                continue
            if re.search(r"(regression|model|main)", path.name, re.I):
                yield path


def spec_family_evidence():
    spec_path = proj / "analysis" / "spec-registry.csv"
    if not spec_path.exists():
        return (0, 0)
    outcomes = set()
    families = set()
    try:
        with spec_path.open(newline="", encoding="utf-8") as f:
            for row in csv.DictReader(f):
                outcome = (row.get("outcome") or "").strip()
                if outcome:
                    outcomes.add(outcome)
                fam = (row.get("model_family") or row.get("family") or row.get("model_type") or "").strip()
                if fam:
                    families.add(fam)
    except Exception:
        return (0, 0)
    return (len(outcomes), len(families))


GOF = re.compile(
    r"^(observations?|n|sample size|r[- ]?squared|adj(?:usted)? r[- ]?squared|aic|bic|log likelihood|"
    r"deviance|rmse|sigma|fixed effects?|province indicators?|wave controls?|notes?)$",
    re.I,
)


def assess_table(header, rows):
    header_norm = [norm(cell) for cell in header]
    model_indexes = [
        idx
        for idx, cell in enumerate(header_norm)
        if re.match(r"^(model|m)\s*[0-9]+$", cell) or re.match(r"^[0-9]+$", cell)
    ]
    if not model_indexes and len(header) >= 5:
        # Assume every non-stub column is a model only when the title/stub
        # clearly looks like a regression table.
        model_indexes = list(range(1, len(header)))
    first = header_norm[0] if header_norm else ""
    row_stubs = [norm(row[0]) for row in rows if row]
    focal_summary = (
        first == "statistic"
        and any("focal adjusted association" in stub for stub in row_stubs)
        and any(stub in {"p value", "p"} for stub in row_stubs)
        and any(stub in {"n", "observations"} for stub in row_stubs)
    )
    if focal_summary:
        return {
            "status": "RED",
            "reason": "focal_summary_table_used_as_regression_table",
            "models": len(model_indexes),
            "blank_fraction": 0.0,
        }
    if len(model_indexes) < 2:
        return {"status": "INERT", "reason": "not_multi_model_table", "models": len(model_indexes), "blank_fraction": 0.0}
    blank = 0
    total = 0
    predictor_rows = 0
    for row in rows:
        if not row:
            continue
        stub = norm(row[0])
        if not stub or GOF.search(stub):
            continue
        values = []
        for idx in model_indexes:
            values.append(row[idx] if idx < len(row) else "")
        if not any(str(v).strip() for v in values):
            continue
        predictor_rows += 1
        for value in values:
            total += 1
            if not str(value).strip() or str(value).strip() in {"--", "-", "NA", "N/A"}:
                blank += 1
    blank_fraction = (blank / total) if total else 0.0
    outcomes, families = spec_family_evidence()
    if len(model_indexes) >= 7 and blank_fraction >= 0.35:
        return {
            "status": "RED",
            "reason": "sparse_omnibus_regression_table",
            "models": len(model_indexes),
            "blank_fraction": blank_fraction,
            "predictor_rows": predictor_rows,
            "outcomes": outcomes,
            "families": families,
        }
    return {
        "status": "GREEN",
        "reason": "regression_table_shape_ok",
        "models": len(model_indexes),
        "blank_fraction": blank_fraction,
        "predictor_rows": predictor_rows,
        "outcomes": outcomes,
        "families": families,
    }


checked = []
for path in candidate_files():
    raw = path.read_text(encoding="utf-8", errors="replace")
    content = raw if path.suffix.lower() == ".md" else html_to_markdownish(raw)
    for header, rows in parse_markdown_tables(content):
        assessment = assess_table(header, rows)
        if assessment["status"] == "INERT":
            continue
        checked.append((path, assessment))
        if assessment["status"] == "RED":
            print(
                "RED:{path}:{reason}:models={models}:blank_fraction={blank:.2f}:outcomes={outcomes}:families={families}".format(
                    path=path.relative_to(proj),
                    reason=assessment["reason"],
                    models=assessment.get("models", 0),
                    blank=assessment.get("blank_fraction", 0.0),
                    outcomes=assessment.get("outcomes", 0),
                    families=assessment.get("families", 0),
                )
            )
            raise SystemExit

if checked:
    details = [
        f"{path.relative_to(proj)}:models={item.get('models', 0)}:blank_fraction={item.get('blank_fraction', 0.0):.2f}"
        for path, item in checked
    ]
    print("GREEN:" + ";".join(details[:5]))
else:
    print("INERT:no_parseable_regression_table")
PY
)

echo "PROJECT=${PROJ}"

case "$result" in
  GREEN:*)
    echo "STATUS=GREEN"
    echo "REASON=regression_table_shape_ok"
    echo "DETAIL: ${result#GREEN:}"
    exit 0 ;;
  RED:*)
    echo "STATUS=RED"
    echo "REASON=regression_table_shape_failed"
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
