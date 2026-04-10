# Changelog

All notable changes to open-scholar-skill are documented in this file.
Format follows [Keep a Changelog](https://keepachangelog.com/).

## [5.9.0] - 2026-04-10

End-to-end data-safety hardening. Extends open-scholar-skill's "keep researchers in the loop" philosophy with mechanical enforcement against unsafe data reads. Scholar skills previously loaded user data via the `Read` tool, which transmits file contents to the Anthropic API. v5.9.0 introduces a three-layer defense — policy, ingestion-time scanning, and a PreToolUse hook — so no sensitive file can reach the API without an explicit researcher decision.

This release is a natural fit for the open-scholar-skill philosophy: `/scholar-init review` is an interactive, slow-down-and-decide skill that walks the researcher through every ingested file and records an explicit `SAFETY_STATUS` before any analysis begins. Maximum "in the loop" behavior.

**Note on the deliberate exclusions:** This repo does not ship `scholar-full-paper` (see the README's "Note on the Full-Paper Orchestrator" for rationale). The `scripts/gates/init-handshake.sh` helper is bundled for standalone script use but has no in-repo caller. The 11 data-touching skills present here (analyze, eda, compute, ling, qual, brainstorm, data, verify, replication, code-review, write) are all gated.

### Added

**New skill and policies**
- **scholar-init**: Project initializer skill (4 modes: `init`, `review`, `add`, `status`). Creates the standard project layout (`data/raw/`, `data/interim/`, `data/processed/`, `materials/`, `output/<slug>/`, `.claude/`, `logs/`), copies or symlinks raw files into place, scans each one, and writes `.claude/safety-status.json`. The interactive `review` mode walks the researcher through every `NEEDS_REVIEW` entry and resolves it to one of `CLEARED`, `LOCAL_MODE`, `ANONYMIZED`, `OVERRIDE`, or `HALTED` with logged rationale.
- **`_shared/data-handling-policy.md`**: Canonical data-handling policy (§0–§11). Defines the five `SAFETY_STATUS` values, the LOCAL_MODE execution contract (`Rscript -e` / `python3 -c` heredocs with a forbidden-verb list), the image-file path classification rules, the binary-format YELLOW promotion rule, and a Known Limitations section.
- **`_shared/tier-b-safety-gate.md`**: Canonical Tier B gate doc describing the lightweight sidecar check, allowed/refused status matrix, and integration contract for skills that do not implement the full LOCAL_MODE dispatch.
- **`scripts/init-project.sh`**: Executable project initializer used by `scholar-init`. Validates the slug (`^[a-z][a-z0-9]*(-[a-z0-9]+)*$`), ingests raw files (copy by default, `--link` for symlinks), calls `safety-scan.sh` on every file, writes `.claude/safety-status.json`, and generates `logs/init-report.md` + a project README teaching the researcher how the layout works.
- **`scripts/gates/pretooluse-data-guard.sh`**: The PreToolUse hook intended for `~/.claude/settings.json`. Intercepts every `Read`, `NotebookRead`, `NotebookEdit`, `Grep`, and `Glob` call. Looks up the target path in the nearest `.claude/safety-status.json` (canonicalized via `python3 → realpath → readlink -f`, falling closed if no resolver is available). Refuses the call when the status is `NEEDS_REVIEW:*` or `HALTED`. Classifies image files by path. Blocks any path that canonicalizes into a system directory. Refuses qualitative-format `OVERRIDE` entries (audio/video/transcripts) at the hook level.
- **`scripts/gates/init-handshake.sh`**: Standalone handshake helper. Bundled for parity with other scholar-skill variants. Not wired to any caller in this repo since `scholar-full-paper` is deliberately absent.
- **`scripts/gates/derive-proj.sh`**: Canonical `${PROJ}` derivation helper.
- **`scripts/gates/safety-scan-presidio.py`**: Presidio NER-based PII detection backend (invoked by `safety-scan.sh` when Presidio is installed).
- **`scripts/gates/anonymize-presidio.py`**: Presidio-based anonymizer for qualitative data (`scan`, `keygen`, `anonymize`, `verify` subcommands).

**Tier A Step 0 safety gates** (dispatch to LOCAL_MODE Bash heredocs)
- `scholar-analyze`, `scholar-eda`, `scholar-compute`, `scholar-ling`, `scholar-qual`, `scholar-brainstorm` — every data-loading path now checks `.claude/safety-status.json` before Reading and dispatches to a LOCAL_MODE Bash heredoc (`Rscript -e` / `python3 -c`) when the status is `LOCAL_MODE`. Forbidden-verb lists (`head(df)`, `print(df)`, `View(df)`, `df.head()`, `df.sample()`, etc.) are embedded in each skill. `scholar-qual` adds a sidecar check on top of its existing anonymization gate.

**Tier B Step 0 safety gates** (lightweight sidecar check, no LOCAL_MODE dispatch)
- `scholar-data`, `scholar-verify`, `scholar-replication`, `scholar-code-review`, `scholar-write` — consult `.claude/safety-status.json` and fail fast with a clear message when a referenced data file is `NEEDS_REVIEW:*`, `HALTED`, or `LOCAL_MODE`. Tier B skills do not implement the full LOCAL_MODE dispatch contract — they refuse and direct the researcher to `/scholar-analyze` or `/scholar-eda`.

### Changed
- **`scripts/gates/safety-scan.sh`**: Binary-format YELLOW promotion — `.xlsx`, `.parquet`, `.dta`, `.sav`, `.rds`, `.sqlite`, `.feather`, `.h5`, `.hdf5`, `.pkl`, `.pickle`, `.zip`, `.7z`, `.gz`, `.tar`, `.arrow`, `.orc` are promoted to YELLOW (`NEEDS_REVIEW:BINARY`) even when Presidio/regex return GREEN, because text scanners cannot inspect compressed content. Unreadable-file fail-closed — files that exist but are not readable by the scanner are returned as YELLOW rather than silently GREEN. System-directory list expanded to include `/private/etc`, `/private/var/db`, and `/private/var/log` (the canonicalized macOS paths).
- **`scripts/gates/phase-verify.sh`**: Phase-entry regex now uses a whitelist-alternation boundary. Shipped for parity; no in-repo orchestrator uses it here.
- **`setup.sh`**: Adds a hard check for `jq` (the PreToolUse data guard requires it); installs Presidio via `python3 -m pip`; `link_dir` now refuses to recursively delete a real (non-symlink) directory unless `SCHOLAR_FORCE_MIGRATE=1` is set (prevents clobbering existing skill trees in `~/.claude/`).
- **`.claude-plugin/plugin.json`**: Version bumped from stale `5.4.0` → `5.9.0` to match CHANGELOG. Skill count updated in description.

### Security
- **Qualitative OVERRIDE refusal**: the PreToolUse hook refuses `OVERRIDE` entries for audio/video/transcript formats (`wav mp3 flac m4a ogg aac aiff mp4 mov avi mkv webm eaf textgrid trs cha praat`) even when a researcher has hand-edited the sidecar. These formats cannot be safely loaded in LOCAL_MODE and must use dedicated qualitative pipelines.
- **System-directory escape blocking**: the hook refuses any path that canonicalizes to `/etc`, `/dev`, `/proc`, `/sys`, `/System`, `/var/db`, `/var/log`, `/private/etc`, `/private/var/db`, or `/private/var/log`, blocking symlink escape attempts.
- **Canonicalize with symlink resolution**: the hook canonicalizes paths via `python3 → realpath → readlink -f`. If none of these are available, the hook fails closed on any symlink rather than risking a traversal bypass.
- **jq-missing fail-closed**: when `jq` is not available and a gated tool call cannot be parsed via the `sed` fallback, the hook refuses the call rather than allowing it through.

### Upgrade note — register the PreToolUse hook

This release ships the hook script at `scripts/gates/pretooluse-data-guard.sh` but does NOT auto-register it in `~/.claude/settings.json`. To enable mechanical enforcement across all Claude Code sessions, add a PreToolUse entry pointing to the full absolute path of the script in your global settings. Without this step, the hook scripts and `.claude/safety-status.json` sidecars still function as documentation, but nothing is blocked mechanically.

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
