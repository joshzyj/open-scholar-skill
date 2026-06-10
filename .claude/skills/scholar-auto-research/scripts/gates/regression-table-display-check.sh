#!/usr/bin/env bash
# regression-table-display-check.sh — reader-facing FULL regression table gate.
#
# Structural twin of descriptive-table-display-check.sh, for regression tables.
# Quantitative-regression manuscripts must give readers the FULL model table
# (all controls, standard errors, N, and fit statistics / fixed-effects rows),
# not merely a compact focal-coefficient grid (Beta/SE/p/N for the focal
# predictor only). This gate catches the audited failure mode (project
# experienced-seg-health-us, 2026-06-04): tables/table-main-regression.html/.tex
# were generated and SHA-locked at Phase 6.5, but the manuscript surfaced only
# a compact CSV-derived grid (table2-focal-results.csv) as "Table 2" — readers
# never saw the controls, SEs, or specification ladder.
#
# WHY a separate gate (not regression-table-export-check.sh):
#   export-check verifies the full table EXISTS as .html/.tex/.docx (artifact
#   production). This gate verifies the full table is SURFACED to readers
#   (display) — a different failure mode. regression-table-family-shape-check.sh
#   has a narrow focal_summary RED branch but only for .md/.html files at the
#   regression-table path with a "statistic"/"focal adjusted association" stub;
#   it cannot see a .csv-derived compact grid embedded in the manuscript.
#
# CONTRACT (mirrors descriptive-table-display-check.sh):
#   Quantitative-regression designs only — gated on spec-registry.csv at EITHER
#   tables/ or analysis/ (the same quantitative signal the descriptive twin uses;
#   the path varies across the corpus). INERT when no spec-registry exists, OR
#   when no locked FULL regression table artifact exists to surface (this gate
#   audits display, not production).
#
# RULE-SET:
#   D1  INERT if spec-registry.csv absent at both tables/ and analysis/
#       (non-quantitative paper).
#   D2  Locate the manuscript via derive-manuscript-path.sh (works under BOTH
#       scholar-full-paper drafts/ and scholar-auto-research manuscript/ layouts
#       — the descriptive twin hardcoded auto-research paths and silently no-op'd
#       under full-paper; this gate fixes that by sourcing the shared helper).
#       YELLOW if no manuscript yet (gate runs at Phase 7+).
#   D3  INERT if no locked FULL regression table artifact is present
#       (tables/table-main-regression.{html,tex,md,docx} on disk, OR a
#       regression-role item in a draft/final/submission/lock manifest).
#   D4  GREEN if the full table is surfaced by ANY of:
#         (a) a manifest item (regression role) flagged used_in_manuscript:true;
#         (b) an in-text FULL regression table — a markdown/HTML table whose
#             first-column row stubs include a regression GOF row
#             (Observations/Num.Obs/R²/AIC/BIC/Log.Lik/RMSE/Deviance/Fixed
#             effects) AND the body shows parenthesized SEs or ≥2 model columns;
#             a compact focal grid (focal-coef-only, GOF as columns not rows)
#             does NOT qualify;
#         (c) an explicit supplement/appendix reference to the full regression
#             results ("full models in Supplementary Table S3", etc.).
#   D5  RED otherwise — a full table was locked but readers see only a compact
#       grid or nothing, with no supplement pointer.
#
# Exit codes:
#   0 GREEN  — full regression table is reader-facing (in-text or cited supplement)
#   1 RED    — full table locked but not surfaced anywhere readers can reach
#   2 YELLOW — no manuscript yet / no python3 (advisory, non-blocking)
#   3 INERT  — non-quantitative paper, or no full regression table to surface
#
# Fixtures: tests/smoke/test-regression-table-display-check.sh

set -uo pipefail
export LC_ALL=C

PROJ="${1:-}"
# Validate the single positional arg up front — fail loud, never assume cwd.
if [ -z "$PROJ" ] || [ ! -d "$PROJ" ]; then
  echo "STATUS=YELLOW"
  echo "REASON=usage: regression-table-display-check.sh <project_dir>"
  exit 2
fi

# D1 — quantitative-paper guard: the spec-registry is the same signal the
# descriptive twin uses; without it this is not a regression paper → INERT.
# Path is split across the corpus: `tables/spec-registry.csv` (the more common
# location, and the one the audited project experienced-seg-health-us uses) and
# `analysis/spec-registry.csv` (the descriptive twin's assumption). Accept BOTH
# specific paths — checking only analysis/ INERT-ed on the real audited project
# and silently missed the very defect this gate exists to catch (caught by the
# 2026-06-04 falsifiable-fix replay). Tightening with a named alternative, NOT a
# glob (CLAUDE.md rule 3).
SPEC=""
for cand in "$PROJ/tables/spec-registry.csv" "$PROJ/analysis/spec-registry.csv"; do
  [ -f "$cand" ] && { SPEC="$cand"; break; }
done
if [ -z "$SPEC" ]; then
  echo "STATUS=INERT"
  echo "REASON=no_quantitative_spec_registry"
  exit 3
fi

# D2 — resolve the active manuscript across BOTH pipeline layouts by sourcing
# the shared helper (sets MANUSCRIPT_PATH/STAGE/PIPELINE; returns non-zero when
# none found). Sourcing — not hardcoding — is the fix for the orphaning bug
# documented in derive-manuscript-path.sh's own header.
DMP="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/derive-manuscript-path.sh"
MANUSCRIPT_PATH=""
if [ -f "$DMP" ]; then
  # shellcheck disable=SC1090
  . "$DMP" final || true   # prefer the final/assembled draft; tolerate "not found"
fi
# Belt-and-suspenders fallback if the helper is unavailable: try the canonical
# auto-research triple directly so the gate still works in a minimal checkout.
if [ -z "${MANUSCRIPT_PATH:-}" ]; then
  for cand in \
    "$PROJ/manuscript/manuscript-draft.md" \
    "$PROJ/final/manuscript-final.md" \
    "$PROJ/submission/manuscript-submission.md"
  do
    [ -f "$cand" ] && { MANUSCRIPT_PATH="$cand"; break; }
  done
fi
if [ -z "${MANUSCRIPT_PATH:-}" ]; then
  echo "STATUS=YELLOW"
  echo "REASON=no_manuscript_yet"
  exit 2
fi

# python3 carries the JSON-manifest + table-shape parsing; without it the gate
# cannot adjudicate, so degrade to advisory YELLOW rather than a false RED.
if ! command -v python3 >/dev/null 2>&1; then
  echo "STATUS=YELLOW"
  echo "REASON=no_python3"
  exit 2
fi

result=$(python3 - "$PROJ" "$MANUSCRIPT_PATH" <<'PY'
import json
import re
import sys
from pathlib import Path

proj = Path(sys.argv[1])                       # project root
text = Path(sys.argv[2]).read_text(encoding="utf-8", errors="replace")  # manuscript prose


def norm(value):
    # Lowercase + collapse non-alphanumerics so heading/stub matching is robust
    # to punctuation and Unicode noise (e.g., "R²" vs "R2", "Num. Obs.").
    return re.sub(r"[^a-z0-9]+", " ", str(value or "").lower()).strip()


def load_json(path):
    # Tolerant JSON loader — a malformed manifest must not crash the gate.
    try:
        return json.loads(Path(path).read_text(encoding="utf-8"))
    except Exception:
        return {}


# --- D3: is there a LOCKED full regression table to surface? -----------------
# Primary signal: the canonical Phase-5 export artifact on disk. This is exactly
# the artifact the audited project locked (table-main-regression.html/.tex).
canonical = []
tables_dir = proj / "tables"
if tables_dir.exists():
    # Exact canonical Phase-5 export names (covers .md/.docx intermediates too).
    for stem_suffix in (
        "table-main-regression.html", "table-main-regression.tex",
        "table-main-regression.md", "table-main-regression.docx",
    ):
        p = tables_dir / stem_suffix
        if p.exists():
            canonical.append(str(p.relative_to(proj)))
    # Named-alternative widening (CLAUDE.md rule 3): a project may lock the full
    # regression table under a NON-canonical filename (e.g. main-regression.tex,
    # table-regression-main.html). Probe the specific "*regression*" token with
    # publication suffixes only — NOT a bare *.html/*.tex glob — so a compact
    # focal CSV (table2-focal-results.csv) still cannot satisfy D3. Without this,
    # a locked full table at a non-canonical name false-INERTs the gate, masking
    # the very defect it exists to catch (audit 2026-06-04).
    for pat in ("*regression*.html", "*regression*.htm", "*regression*.tex"):
        for p in sorted(tables_dir.glob(pat)):
            rel = str(p.relative_to(proj))
            if rel not in canonical:
                canonical.append(rel)

# Secondary signal: a regression-role item in any draft/final/submission/lock
# manifest. Mirrors the manifest paths + array names the descriptive twin reads.
manifest_paths = [
    proj / "manuscript" / "draft-manifest.json",
    proj / "final" / "final-manifest.json",
    proj / "submission" / "submission-package-manifest.json",
    proj / "results-locked" / "manifest.json",
]
REG_ROLE_RX = re.compile(
    r"\b(regression|modelsummary|model[-_ ]?table|coef\w*[-_ ]?table|"
    r"full[-_ ]?model|main[-_ ]?regression|table[-_ ]?main[-_ ]?regression)\b",
    re.I,
)


def is_regression_item(item):
    # An artifact is a regression table if its role/path/label/caption mentions
    # a regression-table token (broad enough to catch modelsummary exports).
    if not isinstance(item, dict):
        return False
    hay = " ".join(
        str(item.get(k, ""))
        for k in ("artifact_role", "source_path", "locked_path", "path",
                  "display_label", "caption_text", "display_type")
    )
    return bool(REG_ROLE_RX.search(hay))


manifest_reg_items = []     # all regression-table manifest items found
manifest_reg_used = []      # those flagged used_in_manuscript:true (D4a)
for mp in manifest_paths:
    data = load_json(mp)
    for arr_key in ("locked_result_coverage", "locked_artifacts",
                    "artifact_manifest", "locked_result_claims"):
        arr = data.get(arr_key)
        if not isinstance(arr, list):
            continue
        for item in arr:
            if not is_regression_item(item):
                continue
            src = str(item.get("source_path") or item.get("path")
                      or item.get("locked_path") or "").strip()
            manifest_reg_items.append(src or "<manifest-item>")
            if item.get("used_in_manuscript") is True:
                manifest_reg_used.append(src or "<manifest-item>")

# No locked full regression table anywhere → this gate has nothing to audit.
# (Production of the table is regression-table-export-check.sh's job, not ours.)
if not canonical and not manifest_reg_items:
    print("INERT:no_full_regression_table_to_surface")
    raise SystemExit


# --- D4b: is a FULL regression table rendered in the manuscript prose? --------
# A modelsummary full table puts goodness-of-fit quantities (Observations, R²,
# AIC, ...) as ROW STUBS in the first column, and SEs in parentheses under each
# estimate. A compact focal grid puts N/SE as COLUMNS and has no GOF rows — so
# GOF-as-row-stub is the clean discriminator between the two.
GOF_STUB_RX = re.compile(
    r"^(num\.?\s*obs\.?|observations?|n\s*obs|r2|r squared|adj\.?\s*r2|"
    r"adjusted r2|aic|bic|log lik\w*|rmse|deviance|sigma|"
    r"fixed effects?|fe\b|std\.? errors?|standard errors?)",
    re.I,
)
SE_PAREN_RX = re.compile(r"\(\s*\d+\.\d+\s*\)")   # "(0.034)" — modelsummary SE row


def split_md_row(line):
    # Split a markdown table row "| a | b |" into trimmed cells.
    return [c.strip() for c in line.strip().strip("|").split("|")]


def md_tables(md):
    # Yield (header_cells, body_rows) for each GitHub-style markdown table
    # (a header row followed by a |---|---| delimiter row).
    lines = md.splitlines()
    i = 0
    while i < len(lines) - 1:
        if not lines[i].strip().startswith("|"):
            i += 1
            continue
        if not re.match(r"^\|(?:\s*:?-{2,}:?\s*\|)+\s*$", lines[i + 1].strip()):
            i += 1
            continue
        header = split_md_row(lines[i])
        rows = []
        i += 2
        while i < len(lines) and lines[i].strip().startswith("|"):
            rows.append(split_md_row(lines[i]))
            i += 1
        yield header, rows


def html_tables(html):
    # Minimal dependency-free HTML table extraction → (header, rows). Covers the
    # case where a manuscript embeds a raw <table> (e.g., a modelsummary kable).
    for tbl in re.findall(r"(?is)<table\b.*?</table>", html):
        rows = []
        for tr in re.findall(r"(?is)<tr\b.*?</tr>", tbl):
            cells = re.findall(r"(?is)<t[dh]\b[^>]*>(.*?)</t[dh]>", tr)
            clean = [re.sub(r"\s+", " ", re.sub(r"(?is)<.*?>", " ", c)).strip()
                     for c in cells]
            if clean:
                rows.append(clean)
        if len(rows) >= 2:
            yield rows[0], rows[1:]


def qualifies_as_full_table(header, rows):
    # A table qualifies as a FULL regression table when it carries regression
    # fit statistics as ROW STUBS *and* independently confirms it is a model
    # table — not a focal grid — by EITHER:
    #   • parenthesized SEs under estimates (the modelsummary default), OR
    #   • ≥2 distinct GOF row stubs (e.g. Num.Obs AND R²): a compact grid at
    #     most appends a SINGLE summary row (e.g. an "Observations" footer), so
    #     two GOF stubs is a strong model-table signal.
    # Column count alone is NOT sufficient and was the false-GREEN vector: a
    # compact "Predictor | Beta | SE | p | N" focal grid has ≥2 columns yet
    # shows no parenthesized SEs (SE/N live in columns as bare numbers) and ≤1
    # GOF row stub, so it must stay RED (audit 2026-06-04 — qualifies_as_full_table
    # false-GREEN: one "Observations" footer row + ≥2 columns previously passed).
    stubs = [norm(r[0]) for r in rows if r]
    n_gof = sum(1 for s in stubs if GOF_STUB_RX.match(s))
    if n_gof < 1:
        return False
    body_text = "\n".join(" | ".join(r) for r in rows)
    has_se = bool(SE_PAREN_RX.search(body_text))
    return has_se or n_gof >= 2


in_text_full = False
for header, rows in md_tables(text):
    if qualifies_as_full_table(header, rows):
        in_text_full = True
        break
if not in_text_full:
    for header, rows in html_tables(text):
        if qualifies_as_full_table(header, rows):
            in_text_full = True
            break

# --- D4c: does the prose point readers to the full table in a supplement? -----
# A GENUINE pointer to the full regression table requires an explicit fullness
# qualifier (full/complete/all) on a regression noun co-occurring with a
# supplement/appendix locator — in either order, within a short window. The
# earlier form `supplement\w*...(table|regression|model|coefficient|full)`
# false-GREEN'd the audited project: "Supplementary Table S1 summarizes these
# robustness patterns" and "Supplementary Table S2 ... coverage patterns" both
# matched on the bare word "table", even though neither supplement holds the
# full model table. Caught by the 2026-06-04 falsifiable-fix replay against
# experienced-seg-health-us. Now the supplement reference only counts when it
# explicitly names the FULL/COMPLETE regression/model/coefficients (rule-10
# fixture T8 locks the robustness/coverage false-positive shape to RED).
_FULL_MODEL = (
    r"(full|complete|all)\s+(set\s+of\s+)?"
    r"(regression|model|coefficient|covariate|control|specification)s?"
)
_SUPP_LOC = r"(supplement\w*|appendix|online|supporting information)"
# Allow the fullness qualifier and the supplement locator to sit in ADJACENT
# sentences (one sentence boundary): a 2-sentence pointer like "Full regression
# results are reported separately. See Supplementary Table S3." previously
# false-RED'd because [^.\n]{0,80} forbade any period in the window
# (audit 2026-06-04). Cap at exactly ONE period and ≤80 non-period chars per
# fragment so the window still cannot span a whole paragraph (newlines remain
# forbidden), and the fullness-qualified regression noun (_FULL_MODEL) keeps the
# bare-"table" false-positive locked to RED (rule-10 fixture T8).
_GAP = r"[^.\n]{0,80}(?:\.[^.\n]{0,80})?"
SUPP_REF_RX = re.compile(
    _FULL_MODEL + _GAP + _SUPP_LOC      # "full models ... Supplementary Table SX"
    + r"|" + _SUPP_LOC + _GAP + _FULL_MODEL,  # "Appendix ... full coefficients"
    re.I,
)
supp_ref = bool(SUPP_REF_RX.search(text))

# --- D4/D5 verdict -----------------------------------------------------------
if manifest_reg_used:
    print("GREEN:full_regression_table_flagged_used:" + ",".join(sorted(set(manifest_reg_used))[:4]))
elif in_text_full:
    print("GREEN:full_regression_table_rendered_in_text")
elif supp_ref:
    print("GREEN:full_regression_table_cited_to_supplement")
else:
    # Locked full table exists but readers cannot reach it → the audited defect.
    where = sorted(set(canonical + manifest_reg_items))[:6]
    print("RED:full_regression_table_locked_but_not_reader_facing=" + ",".join(where))
PY
)

echo "PROJECT=${PROJ}"
echo "MANUSCRIPT=${MANUSCRIPT_PATH#"$PROJ"/}"

# Map the python sentinel line to the STATUS/REASON/DETAIL contract + exit code.
case "$result" in
  GREEN:*)
    echo "STATUS=GREEN"
    echo "REASON=full_regression_table_reader_facing"
    echo "DETAIL: ${result#GREEN:}"
    exit 0 ;;
  RED:*)
    echo "STATUS=RED"
    echo "REASON=full_regression_table_not_reader_facing"
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
