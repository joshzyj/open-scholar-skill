# Open Scholar Skill — Project Instructions

## Getting Started

After cloning this repository, run the setup script once:
```bash
bash setup.sh
```
This creates symlinks, auto-detects your Zotero library, and writes a `.env` file with your local paths. See `.env.example` for all configurable options.

---

## Directory Structure: Symlinks

The top-level `skills/` and `agents/` directories are **symlinks** pointing to `.claude/skills/` and `.claude/agents/` respectively. There is only one copy of each file — edits to either path modify the same file. No sync step is needed.

```
skills/  →  .claude/skills/   (symlink)
agents/  →  .claude/agents/   (symlink)
```

**Do NOT replace these symlinks with regular directories.** If a symlink breaks, restore it:
```bash
ln -sf .claude/skills skills
ln -sf .claude/agents agents
```

---

## Project Overview

A Claude Code plugin for academic paper writing in social sciences (sociology, demography, linguistics, computational social science). Targets journals: ASR, AJS, Demography, Science Advances, Nature Human Behaviour, Nature Computational Science.

**Version**: v5.4.0 — 23 skills, 13 agents (9 peer-reviewer + 4 verification)

---

## Project Structure

```
open-scholar-skill/
├── CLAUDE.md                        # THIS FILE — portable project instructions
├── README.md
├── USAGE.md                         # User guide (all 23 skills)
├── agents/ → .claude/agents/        # Symlink to active reviewer agents
├── skills/ → .claude/skills/        # Symlink to active skills
├── .claude/
│   ├── settings.local.json          # Permissions config
│   ├── agents/                      # Active reviewer agents (9 files)
│   │   ├── peer-reviewer-quant.md
│   │   ├── peer-reviewer-theory.md
│   │   ├── peer-reviewer-senior.md
│   │   ├── peer-reviewer-computational.md
│   │   ├── peer-reviewer-qual.md
│   │   ├── peer-reviewer-ling.md
│   │   ├── peer-reviewer-demographics.md
│   │   ├── peer-reviewer-mixed-methods.md
│   │   ├── peer-reviewer-ethics.md
│   │   ├── verify-numerics.md
│   │   ├── verify-figures.md
│   │   ├── verify-logic.md
│   │   └── verify-completeness.md
│   └── skills/                      # Active skills (23 directories)
│       ├── _shared/                 # Shared protocols (process-logger.md)
│       ├── scholar-brainstorm/       # Data-driven RQ generation from codebooks/questionnaires/datasets
│       ├── scholar-idea/            # Broad idea → formal RQ (5-agent evaluation panel)
│       ├── scholar-lit-review/      # Systematic literature review
│       ├── scholar-lit-review-hypothesis/  # Integrated lit review + hypothesis
│       ├── scholar-hypothesis/      # Theory + hypothesis formulation
│       ├── scholar-design/          # Research design + power analysis
│       ├── scholar-data/            # Data collection, open data directory (100+ sources), web scraping
│       ├── scholar-eda/             # Exploratory data analysis
│       ├── scholar-causal/          # Causal inference toolkit (13 strategies incl. staggered DiD, DML, bunching, Bartik IV, quantile DiD)
│       ├── scholar-analyze/         # Analytics + visualization + results (incl. MI, outcome-type dispatch, panel/GMM, Bayesian brms, LCA, SEM)
│       ├── scholar-compute/         # Computational methods (10+ modules incl. GNN, multilingual NLP, conformal prediction)
│       ├── scholar-ling/            # Sociolinguistics (9 modules incl. experimental, Biber MDA, TTS-MGT)
│       ├── scholar-write/           # Section drafting (5-agent review panel)
│       ├── scholar-verify/          # Two-stage analysis-to-manuscript consistency (4-agent panel)
│       ├── scholar-citation/        # Citation management + verification
│       ├── scholar-journal/         # Submission prep (22 journals)
│       ├── scholar-respond/         # Peer review simulation + R&R
│       ├── scholar-open/            # Open science practices
│       ├── scholar-replication/     # Replication package builder + validator
│       ├── scholar-safety/          # Data safety layer
│       ├── scholar-ethics/          # Research ethics toolkit
│       ├── scholar-qual/            # Qualitative methods (coding, grounded theory, thematic analysis, LLM-assisted coding, mixed-methods integration)
│       ├── scholar-collaborate/     # Multi-author collaboration (CRediT, tasks, mentoring)
│       └── scholar-auto-improve/    # Continuous quality engine (4 modes)
```

Each skill directory contains `SKILL.md` (main workflow) and `references/` (supporting material).

---

## Key Design Patterns

### Skill Architecture
- Each `SKILL.md` has YAML frontmatter: `name`, `description`, `tools`, `argument-hint`, `user-invocable: true`
- Skills are invoked via `/scholar-[name] [arguments]`
- Most skills have: dispatch table → numbered workflow steps → save output → quality checklist

### Multi-Agent Patterns
- **scholar-idea Step 8**: 5 evaluator agents (Theorist, Methodologist, Domain Expert, Journal Editor, Devil's Advocate) → consensus scorecard → RQ refinement
- **scholar-write Step 5**: 5 reviewer agents (R1 Logic, R2 Rhetoric, R3 Journal Fit, R4 Citation, R5 Accessibility) → scorecard with ★★ cross-agent agreement → reviser → user confirm
- **scholar-respond**: 3-4 journal-calibrated reviewer agents (R4 computational conditional) → severity×confidence matrix → revision roadmap
- **scholar-verify**: 4 verification agents in 2 stages — Stage 1: verify-numerics (raw output → manuscript tables), verify-figures (raw figures → manuscript figures); Stage 2: verify-logic (manuscript tables/figures → prose text), verify-completeness (full artifact chain integrity) → consolidated scorecard with ★★ cross-agent agreement → fix checklist
- **scholar-auto-improve OBSERVE**: 3 diagnostic agents (Structural Auditor, Academic Quality Reviewer, Cross-Skill Consistency Checker)

### Process Logging
- Every skill run automatically produces a process log at `output/logs/process-log-[skill]-[YYYY-MM-DD].md`
- Protocol defined in `.claude/skills/_shared/process-logger.md`
- Logs capture: timestamp, step name, action summary, output files, and pass/fail status for every step
- Each SKILL.md includes the protocol via a "Process Logging (REQUIRED)" block in Setup and a "Close Process Log" block in Save Output
- Sub-skills produce their own logs

### Output Formats
- All manuscript-producing skills generate 4 formats: `.md`, `.docx`, `.tex`, `.pdf`
- Conversion via pandoc: `pandoc input.md -o output.docx` / `.tex` (with `--standalone -V geometry:margin=1in -V fontsize=12pt`) / `.pdf`

### Citation Rules
- **ABSOLUTE RULE**: Zero tolerance for citation fabrication
- 7-tier verification: Local Library (1) → CrossRef API (2a) → Semantic Scholar API (2b) → OpenAlex API (2c) → Google Scholar (2d) → WebSearch (3)
- Unverified claims flagged as `[CITATION NEEDED]`
- 6 modes: INSERT, AUDIT, CONVERT-STYLE (with in-text marker conversion), FULL-REBUILD, VERIFY (with optional PDF claim check), EXPORT (.bib)
- 7 style templates: ASA, APA, Chicago, APSA, Unified Linguistics, Nature/NCS (numbered), custom

---

## Reference Manager Integration

All citation-dependent skills use a **unified reference search layer** defined in `.claude/skills/scholar-citation/references/refmanager-backends.md`. The unified `scholar_search` dispatcher queries all local backends AND external APIs in a single call, returning relevance-ranked results.

### Local backends (Tier 1 — limit 100)

| Backend | Source | Detection | Features |
|---------|--------|-----------|----------|
| **Zotero** (primary) | SQLite DB (`zotero.sqlite`) | Auto-detect at known path | Keyword (AND-split, relevance-ranked), author, collection, tag search; PDF access via `storage/` |
| **Mendeley Desktop** | SQLite DB (`*.sqlite`) | Auto-detect in `~/Library/Application Support/Mendeley Desktop/` | Keyword, author search; PDF via `localUrl` |
| **BibTeX** | `.bib` files | `$SCHOLAR_BIB_PATH` env var or auto-scan (`./`, `./references/`, `~/Documents/`) | Keyword, author search; no PDF linkage |
| **EndNote XML** | Exported `.xml` | `$SCHOLAR_ENDNOTE_XML` env var or auto-scan | Keyword, author search; no PDF linkage |

### External APIs (Tiers 2a–2d — limit 50 each)

| Tier | API | Features | Auth |
|------|-----|----------|------|
| 2a | **CrossRef API** | 150M+ DOI-registered works; keyword + author search | No key; `SCHOLAR_CROSSREF_EMAIL` for polite pool |
| 2b | **Semantic Scholar API** | 200M+ papers; citation graphs; keyword + author search | `S2_API_KEY` recommended (100 req/5 min without) |
| 2c | **OpenAlex API** | 250M+ works; open metadata; keyword + author search | No key; `SCHOLAR_CROSSREF_EMAIL` for polite pool |
| 2d | **Google Scholar** | Broad coverage incl. books/theses; citation counts; HTML scraping | No key; may CAPTCHA-block high-frequency requests |

**Unified search API:** `scholar_search "KEYWORD" LIMIT keyword|author|collection|tag` — queries all local backends + all external APIs, returns merged pipe-delimited records (deduplication left to caller).

**Zotero relevance scoring:** Multi-word queries use AND-split matching (each word matched independently). Results ranked by: +3 per word in title, +1 per word in abstract, +5 bonus for exact phrase in title, +2 bonus for exact phrase in abstract.

**Verification labels:** `VERIFIED-LOCAL(zotero)`, `VERIFIED-LOCAL(mendeley)`, `VERIFIED-LOCAL(bibtex)`, `VERIFIED-LOCAL(endnote-xml)`, `VERIFIED-CROSSREF`, `VERIFIED-S2`, `VERIFIED-OPENALEX`, `VERIFIED-GSCHOLAR`, `VERIFIED-WEB`

### Zotero (primary backend)
- Library dir: auto-detected (set `SCHOLAR_ZOTERO_DIR` in `.env` to override; `setup.sh` configures this)
- DB: `zotero.sqlite` (copy to /tmp to avoid lock); Backup: `zotero.sqlite.bak`
- No API keys or running Zotero required — pure SQLite + pdftotext

### Configuration
- `SCHOLAR_BIB_PATH` — path to a `.bib` file (overrides auto-scan)
- `SCHOLAR_ENDNOTE_XML` — path to an EndNote `.xml` export (overrides auto-scan)
- `SCHOLAR_CROSSREF_EMAIL` — email for CrossRef/OpenAlex polite pool (optional but recommended)
- `S2_API_KEY` — Semantic Scholar API key for higher rate limits (free at semanticscholar.org)

## Asset Library (scholar-write)
- `assets/example-articles/` — Your own published papers (add your PDFs here for voice/style reference)
- `assets/top-journal-articles/` — Exemplar articles from target journals (add PDFs here)
- `assets/index.md` — Full catalog with Quick Selection Guide
- `assets/article-knowledge-base.md` — Pre-extracted annotations for example papers
- `assets/section-snippets.md` — Verbatim quote library by 9 rhetorical functions

---

## v5.2.0 Improvements (2026-03-05)

### New Peer-Reviewer Agents (3)
- **peer-reviewer-demographics**: Population representativeness, APC analysis, intersectionality, demographic decomposition (Kitagawa, Oaxaca-Blinder, DFL). Calibrated for Demography, PDR, ASR.
- **peer-reviewer-mixed-methods**: Integration strategy, joint displays, case selection, convergence/divergence analysis. Calibrated for ASR, AJS, JMMR.
- **peer-reviewer-ethics**: IRB compliance, informed consent, vulnerable populations, AI transparency, dual-use concerns, GDPR. Calibrated for Nature/NHB/NCS, Science Advances, ASR/AJS.

### Skill Enhancements

**Process Logging**: All skills now auto-generate `output/logs/process-log-[skill]-[date].md` audit trails.

**scholar-analyze**: Outcome-type dispatch table (11 types: binary, ordinal, count, zero-inflated, truncated, Tobit, beta, survival, competing risks), multiple imputation (mice/Rubin's rules), Arellano-Bond GMM, crossed random effects, diagnostic residual plots, E-values.

**scholar-causal**: Expanded from 10 to 13 strategies — added bunching estimation (Kleven & Waseem), shift-share/Bartik IV (Goldsmith-Pinkham), distributional/quantile methods (RIF-OLS, Changes-in-Changes, DFL decomposition).

**scholar-design**: Multilevel/3-level power analysis (simr), DiD power (DeclareDesign), RD power (rdpower), mediation power, SEM sample size guidance, multiple comparisons correction (Bonferroni, BH FDR, Westfall-Young).

**scholar-eda**: Condition number/variance decomposition, DFBETAS/DFFITS/Mahalanobis, panel diagnostics (Durbin-Watson, Pesaran CD, ADF/KPSS stationarity), formal distribution tests.

**scholar-compute**: Docker/containerization templates (R/Python, Code Ocean, Singularity), NER pipeline (spaCy), coreference resolution, ABM models (opinion dynamics, SIR, cultural transmission), temporal ERGMs, stochastic block models, ego-network analysis.

**scholar-ling**: Advanced corpus statistics (log-likelihood keyness, collocation strength), experimental sociolinguistics code (matched guise, RT, IAT), voice quality measures (jitter, shimmer, HNR via parselmouth).

**scholar-qual**: Mixed-methods WORKFLOW 7 (case selection, joint displays, qual-to-quant), inter-rater reliability (Krippendorff's alpha, Fleiss' kappa, Gwet's AC1).

**scholar-write**: Appendix/SI structure (A-E, Nature Extended Data), section word budgets by journal, CRediT author contributions template.

**scholar-respond**: Desk-reject risk assessment (8-item checklist, 3 risk levels), reviewer personality calibration (5 types).

**scholar-hypothesis**: Scope condition matrix, 8-item verification check, 6 new theory frameworks (neo-institutional, organizational ecology, practice theory, feminist epistemology, labor process theory, ANT).

**scholar-lit-review**: PRISMA 2020 flow diagram as required output, weight-of-evidence assessment for contested findings.

**scholar-lit-review-hypothesis**: Citation chain expansion (backward + forward), integration verification check.

**scholar-journal**: Nature Reporting Summary auto-generation template, cross-skill integration checks (Step 6b).

**scholar-open**: Registered Reports Stage 1 template, FAIR operationalization checklist, restricted data sharing guidance (3 templates).

**scholar-replication**: Full AEA README template (9 sections), reproducibility tolerance table.

**scholar-data**: 10 additional international datasets (UKHLS, GSOEP, IHDS, CFPS, etc.), variable dictionary template, web scraping legal/ethical checklist.

**scholar-safety**: International restricted data markers (UK Biobank, ALSPAC, GSOEP, etc.), cloud AI API risk matrix, GDPR compliance.

**scholar-idea**: Operationalized novelty threat criteria, feasibility assessment matrix with timeline estimates.

**scholar-collaborate**: CRediT edge case guidance, first-author convention options.

**scholar-ethics**: AI-generated text disclosure assessment with journal-specific requirements table.

**scholar-citation**: Semantic duplicate detection (Jaccard > 0.6), 6 new reference format templates.

**scholar-auto-improve**: Prescriptive diagnostic-to-action mapping (7 common findings → exact skill invocations).

### scholar-verify Cross-Skill Integration (v5.3.0)

`scholar-verify` is now integrated into 4 downstream skills:

| Skill | Integration Point | Mode | Gate? |
|-------|-------------------|------|-------|
| **scholar-analyze** | Post-save recommendation to user | `stage1` | No |
| **scholar-write** | Step 5b (after review panel, before save) | `stage2` | Conditional (skips if no raw outputs) |
| **scholar-respond** | Step 3b (after consistency check, REVISE mode) | `full` | Yes — CRITICAL blocks Step 4 |
| **scholar-journal** | Step 6b item 6 (pre-submission integration check) | `full` | Yes — MAJOR ISSUES halts submission |
| **scholar-replication** | Verification checklist (2 items consume existing report) | reads report | Checklist items |

---

## User Preferences
- Focus: social sciences (sociology, demography, linguistics, computational social science)
- Journals supported: ASR, AJS, Demography, Social Forces, Science Advances, NHB, NCS, Language in Society, Journal of Sociolinguistics, APSR, and more (see scholar-journal for full list)
- ASR/AJS: AME preferred over odds ratios
- Nature journals: Reporting Summary, data/code availability, CRediT required

---

## Workflow Rules

### LaTeX / Presentations
- When editing LaTeX/Beamer slides, **account for section title pages** when mapping slide numbers to PDF page numbers. Verify edits by checking the compiled PDF page, not just the source slide number.
- Use `xelatex` (not `pdflatex`) for PDF compilation to handle Unicode characters.
- After compiling PDFs, **verify the output exists** and spot-check key content (e.g., updated citations, figure placement) rather than just reporting success.

### Document Synchronization
- When updating content across presentation slides, speaker script, and manuscript/paper, **always update ALL files in sync**. Never update one without checking the others for stale references, numbers, or facts.
- Use `/sync-docs` to automate cross-document synchronization.

### Figures & Visualization
- **Always check for and use** the user's custom visualization settings file (`viz_setting.R`) before generating any plots or figures. Do not use default ggplot2 themes when a custom theme exists.

### File Versioning (NEVER overwrite drafts)
- **NEVER overwrite an existing draft, manuscript, or output file.** All scholar skills MUST use the version collision avoidance protocol in `.claude/skills/_shared/version-check.md`.
- **Before every Write tool call** that saves a draft or manuscript, run the version-check Bash block first. It prints `SAVE_PATH=...` — use that exact path in the Write tool's `file_path` parameter.
- Do NOT hardcode paths from filename templates (e.g., `draft-intro-slug-2026-03-03.md`). The template shows the naming pattern; the Bash block determines the actual versioned path (`-v2`, `-v3`, etc.).
- Shell variables do NOT persist between Bash tool calls. Re-derive `$BASE` in every new Bash call (including pandoc conversions).

### Verification Protocol
- After applying edits, verify changes by: (1) confirming the output file exists and checking its size/page count, (2) extracting text from relevant pages to confirm updates appear, (3) reporting what you **actually see**, not what you expect.
