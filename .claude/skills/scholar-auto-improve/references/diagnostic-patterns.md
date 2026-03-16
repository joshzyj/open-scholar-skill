# Diagnostic Patterns Reference

## Expected Output Specifications by Skill

Use this reference to verify that each skill produces its expected output files.

### scholar-idea
```
${OUTPUT_ROOT}/ideas/
  scholar-idea-[slug]-[date].md    (all 12 sections including multi-agent panel)
```

### scholar-lit-review
```
${OUTPUT_ROOT}/lit-review/
  scholar-lit-review-[slug]-[date]-search-log.md
  scholar-lit-review-[slug]-[date]-draft.md
```

### scholar-hypothesis
```
${OUTPUT_ROOT}/hypotheses/
  scholar-hypothesis-[slug]-[date]-log.md
  scholar-hypothesis-[slug]-[date]-draft.md
```

### scholar-design
```
${OUTPUT_ROOT}/design/
  scholar-design-[slug]-[date].md
```

### scholar-eda
```
${OUTPUT_ROOT}/eda/
  scholar-eda-[slug]-[date].md
```

### scholar-analyze
```
${OUTPUT_ROOT}/analysis/
  scholar-analyze-[slug]-[date].md
  (+ HTML/TeX/docx tables)
  (+ PNG/PDF figures)
```

### scholar-write
```
${OUTPUT_ROOT}/drafts/
  writing-log-[section]-[slug]-[date].md     (File 1: log with 5-agent review panel)
  draft-[section]-[slug]-[date].md           (File 2: draft section)
  draft-[section]-[slug]-[date].docx         (File 2b: Word version)
  draft-[section]-[slug]-[date].tex          (File 2b: LaTeX version)
  draft-[section]-[slug]-[date].pdf          (File 2b: PDF version)
```

### scholar-citation
```
${OUTPUT_ROOT}/citations/
  scholar-citation-[slug]-[date]-draft.md
  scholar-citation-[slug]-[date]-audit.md
  scholar-citation-[slug]-[date]-verification.md  (Mode 5 only)
```

### scholar-journal
```
${OUTPUT_ROOT}/submission/
  readiness-report-[slug]-[date].md
  cover-letter-[slug]-[date].md
  open-science-[slug]-[date].md
```

### scholar-respond
```
${OUTPUT_ROOT}/response/
  scholar-respond-[slug]-[date]-log.md
  scholar-respond-[slug]-[date]-letter.md
  scholar-respond-[slug]-[date]-plan.md
```

### scholar-replication
```
${OUTPUT_ROOT}/replication/
  replication-package/                  (directory)
    code/                               (numbered scripts)
    data/                               (public data or access instructions)
    output/
      tables/                           (reproduced tables — HTML/TeX/docx)
      figures/                          (reproduced figures — PDF/PNG)
      eda/tables/                       (EDA tables from scholar-eda)
      eda/figures/                      (EDA figures from scholar-eda)
      artifact-registry.md              (from scholar-write — table/figure numbering map)
    README.md                           (AEA 9-section template)
    TEST-REPORT.md                      (clean-run test results)
    VERIFICATION-REPORT.md              (paper-to-code correspondence)
    LICENSE
    CITATION.cff
    Makefile
  replication-report-[slug]-[date].md   (internal log)
```

### scholar-open
```
${OUTPUT_ROOT}/open-science/
  preregistration-[slug]-[date].md
  data-management-plan-[slug]-[date].md
  replication-README-[slug]-[date].md
```

---

## Common Issue Categories

### Category 1: Citation Integrity
- `[CITATION NEEDED]` markers left in output
- `UNVERIFIED` references not resolved
- `SOURCE NEEDED` flags not addressed
- Fabricated citations (no Local Library/CrossRef/Semantic Scholar/OpenAlex/WebSearch match)
- Year mismatches between in-text and reference list
- Author name inconsistencies

### Category 2: Format Compliance
- Missing metadata comments (word count, target, journal, mode, date)
- Incorrect section ordering for target journal
- Word count outside target range (>10% over or under)
- Missing required sections (e.g., Data Availability for Nature journals)
- Incorrect citation style for target journal

### Category 3: Cross-Skill Consistency
- Hypothesis numbering mismatch between scholar-hypothesis and scholar-write
- Variable names differ between scholar-eda and scholar-analyze
- Dataset references inconsistent across pipeline stages
- Theory framework described differently in lit-review vs. write
- Journal target changed mid-pipeline without propagation

### Category 4: Output Completeness
- Missing output files (expected but not generated)
- Empty or near-empty files (<100 characters)
- Missing multi-format outputs (docx/tex/pdf not generated)
- Incomplete quality checklists
- Missing writing log or audit log

### Category 5: Structural Issues
- Frontmatter field missing or malformed
- Step numbering gaps or duplicates
- Quality checklist items without clear pass/fail criteria
- Reference file not found at declared path
- Tool declared in frontmatter but never used (or used but not declared)

### Category 6: Academic Quality
- Unsupported claims (assertion without evidence or citation)
- Logical gaps in argumentation
- Inappropriate hedging (too strong or too weak)
- Methods insufficient for replication
- Results reporting missing effect sizes or confidence intervals

---

## Severity Definitions

| Severity | Definition | Action Required |
|----------|-----------|-----------------|
| CRITICAL | Output is unusable or contains fabricated content | Immediate fix required; block pipeline |
| ERROR    | Major quality issue; output missing key components | Fix before submission; flag to user |
| WARN     | Minor quality issue; output usable but suboptimal | Suggest improvement; log for tracking |
| INFO     | Observation for tracking; no immediate action needed | Log only |

---

## Health Score Calculation

Suite health score (0–100) is computed as:

```
base_score = 100
For each CRITICAL issue: base_score -= 20
For each ERROR issue:    base_score -= 5
For each WARN issue:     base_score -= 1
Floor at 0.

Health interpretation:
  90-100: GREEN  — Suite in excellent shape
  70-89:  YELLOW — Issues need attention
  50-69:  ORANGE — Significant problems
  0-49:   RED    — Suite needs major repair
```

---

## Structural Check Specifications (A1–A10)

### A1: Frontmatter Completeness
Required fields: `name`, `description`, `tools`, `argument-hint`, `user-invocable`
Check: YAML parse succeeds AND all 5 fields present AND non-empty.

### A2: Tool Declaration Accuracy
Scan the SKILL.md body for tool usage patterns:
- `Read tool` / `using Read` / `Read(` → must declare `Read`
- `Bash` / `Run command` → must declare `Bash`
- `Write tool` / `using Write` → must declare `Write`
- `Task tool` / `spawn` / `parallel agents` → must declare `Task`
- `WebSearch` → must declare `WebSearch`
- `Glob` → must declare `Glob`
- `Grep` → must declare `Grep`

### A3: Step Numbering Continuity
Parse `### Step [N]` headers. Verify:
- Starts at Step 0 or Step 1
- No gaps (e.g., Step 1 → Step 3 without Step 2)
- No duplicates

### A4: Quality Checklist Exists
Grep for `## Quality` or `## Quality Checklist` section.
Must contain at least 5 `- [ ]` checkbox items.

### A5: Save Output Section Exists
Grep for `## Save Output` or `### Save Output` or `## Save`.
Must specify at least 1 output file path.

### A6: Reference Files Exist
Parse references to `references/*.md` in the SKILL.md body.
For each reference, verify file exists at the declared path.

### A7: Cross-Skill References Valid
Parse mentions of other `scholar-*` skills.
Verify each referenced skill directory exists under `.claude/skills/`.

### A8: Absolute Rule Consistency
For skills that produce manuscript text (scholar-write, scholar-citation, scholar-respond):
Must contain "ZERO TOLERANCE FOR CITATION FABRICATION" or equivalent absolute rule.

### A9: Output Directory Pattern
All output paths should follow `output/[slug]/[type]/[name]-[slug]-[date].[ext]` pattern.
Flag skills using non-standard output locations.

### A10: Multi-Format Output
Skills producing final manuscript text must include pandoc conversion step for:
- `.docx` (Word)
- `.tex` (LaTeX)
- `.pdf` (PDF)
In addition to base `.md`.
