# Changelog

All notable changes to open-scholar-skill are documented in this file.
Format follows [Keep a Changelog](https://keepachangelog.com/).

## [5.6.0] - 2026-03-21

### Added
- `scripts/gates/` — executable gate scripts for version-check, safety-scan, and citation verification
- `tests/smoke/` — smoke test suite (259 checks across structure, routing, and gates)
- `CHANGELOG.md` — this file (extracted from CLAUDE.md)
- `scholar-code-review/references/code-review-standards.md` — missing reference file (caught by smoke tests)

### Changed
- **scholar-compute**: Split 7,232-line monolithic SKILL.md into 583-line routing stub + 11 on-demand module files in `references/module-*.md` (92% reduction)
- **scholar-analyze**: Split 3,363-line SKILL.md into 947-line stub + 6 component files in `references/component-a-*.md` (72% reduction); fixed Bayesian duplication
- **scholar-causal**: Split 1,737-line SKILL.md into 588-line stub + `references/strategies.md` (66% reduction)
- **scholar-ling**: Split 1,848-line SKILL.md into 381-line routing stub + 9 module files in `references/module-*.md` (79% reduction)
- **CLAUDE.md**: Trimmed to essentials (~120 lines); version history moved to CHANGELOG.md
- **`_shared/version-check.md`**: Now calls `scripts/gates/version-check.sh` instead of inline bash
- **scholar-safety**: Added Step 1.0 gate check using `scripts/gates/safety-scan.sh`
- **`.gitignore`**: Expanded with output/, Python, R, and editor patterns
- All 28 skills: inline version-check blocks replaced with gate script calls

## [5.5.0] - 2026-03-18

### Added
- **scholar-knowledge**: User-scoped, cross-project knowledge graph (5 modes: INGEST, SEARCH, RELATE, STATUS, EXPORT)
- NDJSON data model: `papers.ndjson`, `concepts.ndjson`, `edges.ndjson`
- Reusable search layer: `references/knowledge-graph-search.md`
- Integration hooks in scholar-lit-review, scholar-lit-review-hypothesis, scholar-write, scholar-citation

### Changed
- `setup.sh`: Added knowledge graph directory configuration + `SCHOLAR_KNOWLEDGE_DIR` in `.env`

## [5.4.0] - 2026-03-16

### Added
- **scholar-compute MODULE 11**: Life-event sequence modeling (life2vec) — transformer-based representation learning
- **scholar-compute MODULE 2 Step 5**: Full Double ML implementation (R DoubleML + Python EconML)
- 7 new model types in scholar-analyze: GAMLSS, DML/Causal Forest bridge, Growth Curves, MSEM, FMR, Specification Curve, BART
- `gt` tables via `gtsummary` + Stata `.do` file generation
- Cell-by-cell table verification in scholar-analyze A9

## [5.3.0] - 2026-03-10

### Added
- **scholar-verify** cross-skill integration into downstream skills (scholar-analyze, scholar-write, scholar-respond, scholar-journal, scholar-replication)

## [5.2.0] - 2026-03-05

### Added
- 3 new peer-reviewer agents: peer-reviewer-demographics, peer-reviewer-mixed-methods, peer-reviewer-ethics
- Process logging across all skills (`output/logs/process-log-[skill]-[date].md`)

### Changed
- **scholar-analyze**: Outcome-type dispatch (11 types), multiple imputation, Arellano-Bond GMM, E-values
- **scholar-causal**: Expanded from 10 to 13 strategies — added bunching, Bartik IV, distributional methods
- **scholar-design**: Multilevel power, DiD/RD/mediation power, multiple comparisons correction
- **scholar-compute**: Docker templates, NER, coreference, ABM, temporal ERGMs, SBM, ego-network
- **scholar-ling**: Corpus statistics, experimental sociolinguistics, voice quality measures
- **scholar-write**: Appendix/SI structure, section word budgets, CRediT template
- **scholar-respond**: Desk-reject risk assessment, reviewer personality calibration
- **scholar-hypothesis**: Scope condition matrix, 6 new theory frameworks
- **scholar-lit-review**: PRISMA 2020 flow diagram, weight-of-evidence assessment
- **scholar-journal**: Nature Reporting Summary template, cross-skill integration checks
- **scholar-open**: Registered Reports Stage 1, FAIR checklist, restricted data sharing
- **scholar-replication**: AEA README template, reproducibility tolerance table
- **scholar-data**: 10 additional international datasets, variable dictionary template, web scraping checklist
- **scholar-safety**: International restricted data markers, cloud AI API risk matrix, GDPR
- **scholar-citation**: Semantic duplicate detection (Jaccard > 0.6)
- **scholar-qual**: Mixed-methods workflow, inter-rater reliability
- **scholar-eda**: Condition number, DFBETAS/DFFITS, panel diagnostics
- **scholar-ethics**: AI-generated text disclosure with journal-specific requirements
- **scholar-auto-improve**: Prescriptive diagnostic-to-action mapping
- **scholar-collaborate**: CRediT edge case guidance
- **scholar-idea**: Novelty threat criteria, feasibility matrix
