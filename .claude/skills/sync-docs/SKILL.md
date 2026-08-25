---
name: sync-docs
description: "Synchronize content across presentation slides, speaker script, and manuscript/paper. Audits for stale references, numbers, citations, and version mismatches, then updates all files in parallel and compiles to PDF."
argument-hint: "[slides.tex] [script.tex] [manuscript.tex] — paths to the files to sync (auto-detected if omitted)"
tools: Read, Edit, Write, Bash, Glob, Grep, Agent
user-invocable: true
---

# Sync Documents

Synchronize presentation slides, speaker script, and manuscript/paper so all share consistent content (citations, statistics, version numbers, skill counts, taxonomy references).

## Process Logging (REQUIRED) — Reasoning · Action · Observation trace

This skill emits an append-only RAO trace at `${OUTPUT_ROOT}/logs/trace-sync-docs-<date>.ndjson` — the source of truth. The human-readable `process-log-sync-docs-<date>.md` is *rendered* from it. Full protocol + privacy rule: `_shared/process-logger.md`.

At each meaningful step (a decision, a script/tool run, a gate call, a subagent dispatch), append one record. `emit-trace.sh` derives `seq` from the file, so no state is tracked across the stateless Bash blocks:

```bash
bash "${SCHOLAR_SKILL_DIR:-.}/scripts/gates/emit-trace.sh" --skill sync-docs --step "<label>" \
  --reasoning "<the WHY — stated rationale, 1–2 lines>" \
  --action "<the WHAT — tool/script/gate call + key args>" \
  --observation "<the RESULT — verdict/metric/count/error/file ref>" --status ok    # ok|fail|skipped
```

At the end (Close Process Log), render the human-readable log and self-check:

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
bash "${SCHOLAR_SKILL_DIR:-.}/scripts/gates/render-trace.sh" "${OUTPUT_ROOT}/logs/trace-sync-docs-$(date +%Y-%m-%d).ndjson"
bash "${SCHOLAR_SKILL_DIR:-.}/scripts/gates/trace-coverage-check.sh" "${OUTPUT_ROOT}" --skill sync-docs
```

Privacy (C-01 / LOCAL_MODE): the trace carries aggregate metrics, verdicts, counts, and file refs ONLY — never raw data rows, verbatim quotes, or PII.

---

## Step 1 — Identify Documents

If the user provides file paths, use those. Otherwise, auto-detect by scanning the current project directory:

```bash
# Find candidate files
echo "=== LaTeX/Beamer slides ==="
find . -maxdepth 3 -name "*.tex" -exec grep -l '\\begin{frame}\|\\documentclass.*beamer' {} \; 2>/dev/null | head -5
echo "=== Scripts ==="
find . -maxdepth 3 \( -name "*script*" -o -name "*notes*" \) \( -name "*.tex" -o -name "*.md" \) 2>/dev/null | head -5
echo "=== Manuscripts ==="
find . -maxdepth 3 \( -name "*manuscript*" -o -name "*paper*" -o -name "*draft*" \) \( -name "*.tex" -o -name "*.md" -o -name "*.docx" \) 2>/dev/null | head -5
```

Present the detected files to the user for confirmation. Require at least 2 documents to proceed.

## Step 2 — Audit for Stale Content

Read all identified documents. For each document, extract and catalog:

1. **Version numbers** — any `v[0-9]` patterns, skill counts, agent counts
2. **Statistics** — percentages, sample sizes, coefficients, counts
3. **Citations** — author-year references, numbered references
4. **Key terms** — project names, institution names, method names
5. **Dates** — years, submission dates, conference dates

Build a **cross-document comparison table**:

```markdown
| Content Item | Slides | Script | Manuscript | Match? |
|-------------|--------|--------|------------|--------|
| Version     | v5.1.0 | v5.2.0 | v5.2.0     | STALE  |
| Skill count | 23     | 26     | 26         | STALE  |
| ...         | ...    | ...    | ...        | ...    |
```

Flag all mismatches as `STALE`.

## Step 3 — Present Audit Results

Show the user:
1. The comparison table with all STALE items highlighted
2. The **authoritative value** for each item (from the most recently updated document or user specification)
3. Ask for confirmation before proceeding with updates

## Step 4 — Apply Updates

For each STALE item, update all documents to use the authoritative value.

**Important rules:**
- When editing LaTeX/Beamer slides, account for section title pages when mapping slide numbers to PDF page numbers
- Preserve document-specific formatting (e.g., a slides version might be abbreviated)
- Do NOT change content that is intentionally different between documents (e.g., slides may have shorter text)

## Step 5 — Compile to PDF

Compile all LaTeX documents using `xelatex` (not `pdflatex`):

**A compile FAILURE must not be masked as success.** `xelatex ... 2>&1 | tail -20`
discards xelatex's exit code (the pipe returns `tail`'s status, which is
always 0 as long as it can read stdin), so a broken LaTeX run can leave a
STALE PDF from a previous compile while being reported as "compiled." Fixes:
add `-halt-on-error`, capture the compiler exit via `${PIPESTATUS[0]}`, and
require the output PDF's mtime to be NEWER than the source before trusting it.

```bash
# For each .tex file — capture xelatex's real exit code (not tail's).
cd "$(dirname "$FILE")"
BASE="$(basename "$FILE")"; PDF="${BASE%.tex}.pdf"
xelatex -halt-on-error -interaction=nonstopmode "$BASE" 2>&1 | tail -20; rc=${PIPESTATUS[0]}
# Run twice for cross-references (only if the first pass succeeded).
if [ "$rc" -eq 0 ]; then
  xelatex -halt-on-error -interaction=nonstopmode "$BASE" 2>&1 | tail -5; rc=${PIPESTATUS[0]}
fi
# Fail loudly: non-zero exit OR a PDF that is not newer than its source ⇒ the
# render is stale/failed. Do NOT report success.
if [ "$rc" -ne 0 ] || [ ! -f "$PDF" ] || [ "$PDF" -ot "$BASE" ]; then
  echo "❌ xelatex FAILED for $BASE (rc=$rc; PDF stale or missing) — fix the LaTeX error; do NOT ship the old PDF." >&2
  exit 1
fi
echo "✓ compiled $PDF"
```

For Markdown documents, compile with pandoc (same fail-loud discipline):
```bash
PDF="${FILE%.md}.pdf"
if ! pandoc "$FILE" -o "$PDF" --pdf-engine=xelatex -V geometry:margin=1in -V fontsize=12pt 2>&1; then
  echo "❌ pandoc FAILED for $FILE — do NOT ship a stale PDF." >&2; exit 1
fi
[ -f "$PDF" ] && [ ! "$PDF" -ot "$FILE" ] || { echo "❌ $PDF not newer than $FILE — render did not update." >&2; exit 1; }
```

## Step 6 — Verify Output

For each compiled PDF:
1. Confirm the file exists and check its size
2. Extract text from key pages where changes were made
3. Report what you **actually see** in the compiled output, not what you expect

```bash
# Verify PDF exists and get page count
pdfinfo "$PDF_FILE" 2>/dev/null | grep Pages
# Extract text from specific pages to verify changes
pdftotext "$PDF_FILE" - 2>/dev/null | grep -i "SEARCH_TERM" | head -5
```

## Step 7 — Summary Report

Output a final report:

```markdown
## Sync Report

### Documents Synchronized
- [list of files updated]

### Changes Applied
| Item | Old Value | New Value | Files Updated |
|------|-----------|-----------|---------------|
| ...  | ...       | ...       | ...           |

### Compilation Results
| File | Status | Pages | Size |
|------|--------|-------|------|
| ...  | ...    | ...   | ...  |

### Verification
- [list of verified content checks with PASS/FAIL]
```

**Close Process Log:**

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
SKILL_NAME="sync-docs"
LOG_DATE=$(date +%Y-%m-%d)
LOG_FILE="${OUTPUT_ROOT}/logs/process-log-${SKILL_NAME}-${LOG_DATE}.md"
if [ ! -f "$LOG_FILE" ]; then
  LOG_FILE=$(ls -t "${OUTPUT_ROOT}"/logs/process-log-${SKILL_NAME}-${LOG_DATE}*.md 2>/dev/null | head -1)
fi
cat >> "$LOG_FILE" << LOGFOOTER

## Summary
- **Steps completed**: [N completed]/[N total]
- **Files synchronized**: [count]
- **Stale items fixed**: [count]
- **Errors**: [count, or 0]
- **Time finished**: $(date +%H:%M:%S)
LOGFOOTER
echo "Process log saved to $LOG_FILE"
```

---

## Save Output

- **Updated files**: All synchronized documents (slides, speaker script, manuscript) are updated in place
- **Process log**: `output/[slug]/logs/process-log-sync-docs-[date].md`
- **Sync report**: Displayed inline (stale items found, changes applied, verification results)

---

## Quality Checklist

- [ ] At least 2 documents identified and confirmed by user
- [ ] Cross-document comparison table produced with all content items
- [ ] All STALE items identified with authoritative values
- [ ] User confirmed changes before applying
- [ ] All documents updated consistently
- [ ] LaTeX compiled with `xelatex` (not `pdflatex`)
- [ ] Markdown compiled with pandoc where applicable
- [ ] Each compiled PDF verified: file exists, correct page count, content spot-checked
- [ ] No unintended content changes (document-specific formatting preserved)
- [ ] Final sync report produced with changes table and verification results
