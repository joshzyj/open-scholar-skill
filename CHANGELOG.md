# Changelog

All notable changes to open-scholar-skill are documented in this file.
Format follows [Keep a Changelog](https://keepachangelog.com/).

## [5.8.0] - 2026-04-03

### Added
- **scholar-knowledge MODE 6 COMPILE**: Generate a browsable Obsidian-compatible markdown wiki from the NDJSON graph. Produces paper pages, concept pages, auto-clustered topic pages, `contradictions.md`, `gaps.md`, and an `index.md` dashboard, plus a networkx/matplotlib knowledge map PNG. Uses `[[wikilinks]]` throughout for Obsidian graph view. Auto-detects incremental vs full rebuild (pass `full` to force rebuild). Wiki is auto-maintained incrementally on every ingest — the LLM writes and updates the wiki, users rarely touch it directly (Karpathy principle).
- **scholar-knowledge MODE 7 ASK**: Answer complex research questions against the *compiled wiki* (not raw NDJSON) for synthesized answers. Saves answers to `wiki/answers/` as a feedback loop. Assigns confidence levels based on graph coverage. Supports comparative, mechanistic, and synthesis questions.
- **scholar-knowledge MODE 8 RE-EXTRACT**: Re-run extraction on archived raw sources. Upgrades papers from `abstract_only → full_pdf` when PDFs become available, or applies new schema fields to existing papers without re-downloading.
- **Raw source storage layer** (`raw/` subdirectory): `raw/pdfs/` (Zotero symlinks), `raw/abstracts/`, `raw/api-responses/`, `raw/web/` (URL ingest), `raw/images/` (PDF figure extraction). Append-only archive. New paper-node fields: `raw_path`, `extraction_tier`.
- **New ingest sources**: `from url [URL]` (web-based papers, arXiv, etc.) and `from output [path]` (lit-review and analyze outputs).
- **Cross-skill write-back hooks**: findings/results auto-flow back into the knowledge graph from scholar-analyze, scholar-lit-review, scholar-compute, and scholar-respond.
- **Obsidian setup guide**: `.claude/skills/scholar-knowledge/references/obsidian-setup.md` — recommended vault config for browsing the compiled wiki.

### Changed
- **scholar-knowledge**: Expanded from 5 modes to 8 modes. `SKILL.md` grew from ~160 to ~1,100 lines (+934).
- **README.md, USAGE.md**: Updated to document the 8-mode scholar-knowledge architecture, wiki/ask/re-extract flows, raw storage, new ingest sources, and cross-skill write-back hooks.

## [5.7.0] - 2026-03-22

### Added
- **scholar-conceptual**: New skill for original theory building (8 strategies: typology, process, mechanism, scope, multi-level, abductive, synthetic, concept clarification) + publication-quality conceptual diagrams (TikZ/Mermaid: mechanism diagrams, multi-level models, typology matrices, process models, concept maps, feedback loops)
- **scholar-openai**: External review via OpenAI Codex CLI agents. Spawns multiple parallel Codex agents to independently review analysis scripts, verify manuscript-to-output consistency, check statistical logic, and audit reproducibility
- **scholar-brainstorm PAPER mode**: Third mode alongside DATA/MATERIALS. Accepts published paper PDF, DOI, or pasted abstract. Extracts seed paper elements, optionally calls SciThinker-30B (HuggingFace) for AI-generated follow-up ideas, then Claude expands to 15-20 candidates across 8 dimensions before multi-agent evaluation
- **scholar-analyze REVISE-FIGURE mode**: Mode 4 for modifying existing figures without re-running analysis. 14-item revision catalog (rotate labels, resize, relabel, add reference lines, change colors, refacet, convert R↔Python)
- **scholar-knowledge limitations + future_directions**: Two new fields in paper node schema for extracting what papers acknowledge they couldn't do and what they suggest as next steps. New search modes: `limitations of`, `future directions for`, `opportunities in`
- **viz-templates-python.md**: Full 25-template Python/matplotlib/seaborn library (P1-P25) matching every ggplot2 template
- **RQ-to-model mapping check**: Mandatory table ensuring every hypothesis has a corresponding regression

### Changed
- **viz-standards.md**: Split 974-line monolith into 209-line routing stub + `viz-templates-ggplot.md` (742 lines) loaded on demand (78% reduction)

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
