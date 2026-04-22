# Changelog

All notable changes to open-scholar-skill are documented in this file.
Format follows [Keep a Changelog](https://keepachangelog.com/).

## [5.12.0] - 2026-04-22

Sync with upstream `open-scholar-skills` (private). Adds `scholar-monitor`, a current-awareness literature feed designed for recurring `/loop` scheduling with push delivery to the researcher's phone. Fits the researcher-in-the-loop philosophy of this fork: it surfaces new publications and enriches the knowledge graph without automating downstream writing.

### Added

**New skill: `scholar-monitor`**

- **`.claude/skills/scholar-monitor/SKILL.md`** — routing stub with 9 modes: default / targeted fetch, `all`, `preview` (dry-run), `init`, `list`, `status`, `add`, `remove`, `configure delivery`, `digest`. Fully idempotent under `/loop`: each invocation computes a delta against `state.json` (last-seen DOIs/arXiv IDs per source) plus the knowledge graph, fetches only publications newer than the cursor, summarizes them, pushes to configured channels, and atomically advances state.
- **`.claude/skills/scholar-monitor/assets/fetch.py`** — stdlib-only Python fetcher with four backends:
  - **Crossref** by ISSN (polite-pool honored via `--email`)
  - **arXiv** Atom API with 3s inter-call sleep (respects arXiv rate limits)
  - **OpenAlex** by ISSN with inverted-index abstract reconstruction
  - **RSS/Atom** generic parser for sources without dedicated APIs

  Version-strips trailing `v\d+` from `arxiv_id` so dedup is version-agnostic (a v2 paper won't re-deliver if v1 was already seen). Emits a normalized paper record as JSONL: `{source_id, category, doi, arxiv_id, title, authors, year, published_date, journal, abstract, url}`. 1s courtesy sleep after Crossref/OpenAlex calls to avoid rate-limit pressure under `/loop`.

- **`.claude/skills/scholar-monitor/assets/deliver.py`** — delivery dispatcher for:
  - **ntfy.sh** — POST-based push with ASCII-safe Title header (replaces `—`/`–`/`…`/curly quotes with ASCII equivalents; body stays UTF-8), 3.5 KB body cap to stay under ntfy's 4 KB limit.
  - **SMTP email** — stdlib `smtplib` with starttls; password read from env var, never from config.
  - Telegram routes through the `mcp__plugin_telegram_telegram__reply` MCP tool (not via deliver.py); file attachment supported when the Telegram MCP plugin is available.

- **`.claude/skills/scholar-monitor/assets/default-sources.json`** — 22 starter sources: 14 sociology journals (ASR, AJS, Social Forces, Demography, PDR, Gender & Society, SoE, JMF, Ethnic & Racial Studies, Du Bois Review, SSR, SMR, Social Problems, ARS), 5 interdisciplinary (NHB, Science Advances, NCS, APSR, PNAS), and 3 arXiv categories (cs.CL with LLM filter, cs.CY, econ.GN). Three enabled by default (ASR, arxiv-llm, NHB) to keep the first-run digest manageable.

- **`.claude/skills/scholar-monitor/references/fetcher-protocols.md`** — call patterns per backend, normalized paper schema, quirks per source (Crossref ingestion lag for SAGE publishers, arXiv cross-listing, OpenAlex inverted-index lossiness), and instructions for adding new backends (e.g., Semantic Scholar, bioRxiv).

- **`.claude/skills/scholar-monitor/references/registry-guide.md`** — `sources.json` schema, ISSN lookup for 28 sociology/linguistics/interdisciplinary journals, arXiv category list (cs.CL/AI/LG/CY/SI, stat.ML/AP, econ.GN/EM), cadence rules-of-thumb, archive-rotation policy.

- **`.claude/skills/scholar-monitor/references/delivery-protocol.md`** — Telegram / ntfy / email / file channel specs, long-message chunking, `config.json` schema, security notes (chmod 0600, SMTP password in env var only, ntfy topic treated as shared secret).

**User-scoped state (mirrors `SCHOLAR_KNOWLEDGE_DIR` pattern):**

- `~/.claude/scholar-monitor/sources.json` — user-editable source registry (populated from `default-sources.json` on first run).
- `~/.claude/scholar-monitor/state.json` — machine-maintained per-source cursors (`last_run`, `last_seen_date`, 200-deep `last_seen_ids`, `total_seen`, `last_error`).
- `~/.claude/scholar-monitor/config.json` (`chmod 0600`) — delivery channel configuration.
- `~/.claude/scholar-monitor/archive.ndjson` — append-only full digest history (enables `digest` mode without network re-fetching).
- `~/.claude/scholar-monitor/tmp/run-<timestamp>-<pid>/` — stable per-run scratch space for cross-Bash-call state handoff. Keeps last 5 run-dirs for postmortem.

**Knowledge-graph integration:** each new paper is appended to `~/.claude/scholar-knowledge/papers.ndjson` (via the `_shared/knowledge-graph-search.md` helpers) with `source: "scholar-monitor"`, `extraction_tier: "abstract_only"`, and monitor-specific fields (`monitor_source_id`, `monitor_category`, `monitor_url`). Future `/scholar-lit-review` runs pick up these papers at Tier 0 before external APIs.

**`/loop` compatibility:** `/loop 24h /scholar-monitor arxiv-llm`, `/loop 7d /scholar-monitor`, `/loop 1h /scholar-monitor`. The `cadence_days` filter (per source) guarantees idempotency — invocations more frequent than cadence return empty without contacting APIs. Per-source failures don't advance that source's cursor; the next tick retries cleanly.

### Changed

- Skill count: **31 → 32**. `scholar-monitor` added; `scholar-full-paper`, `scholar-grant`, `scholar-teach`, `scholar-book`, `scholar-presentation` remain excluded (orchestrator-bound or feature-heavy, preserved in the private fork).
- `README.md` — Skills Overview count 30+1 → 31+1; `scholar-monitor` row in Extended Skills table; `4. Install all 31 skills` → `32 skills` in setup notes.
- `USAGE.md` — opening skill count 30+1 → 31+1; `scholar-monitor` row in Skill Reference table; new Section 21 "Literature Monitoring" covering all 9 modes, the 22-source starter registry, `/loop` recipes, 4-row delivery-channel comparison, and positioning vs. `scholar-lit-review`.
- `CLAUDE.md` — version bumped v5.11.0 → v5.12.0; skill count 31 → 32.
- `.claude-plugin/plugin.json` — version bumped; description "31 skills" → "32 skills".

### Adapted (private → public)

Scholar-monitor's original Phase 0a/0b referenced `scripts/gates/derive-scholar-dir.sh` and `scripts/gates/init-log.sh` from the private fork. Replaced both with the public fork's existing idioms: `${SCHOLAR_SKILL_DIR:-.}` parameter-expansion fallback with `.env` sourcing, and inline log-init matching the pattern used by other public skills (e.g., `scholar-lit-review` lines 38–56). No private-only orchestrator references (`scholar-full-paper`, Phase 3.5, results-lock, Phase 11.5) were present in the source — the skill is intrinsically orthogonal to the paper pipeline.

### Why

The public fork's researcher-in-the-loop design treats the human as the primary agent making editorial decisions. `scholar-monitor` serves that model: it surfaces what's new, lets the researcher decide what matters, and quietly enriches the knowledge graph in the background. It doesn't write, it doesn't analyze, it doesn't decide — it watches the feed and tells you when something new arrives. Best companion to `scholar-lit-review` (retrospective) and `scholar-knowledge` (accumulation).

## [5.11.0] - 2026-04-16

Sync with upstream `open-scholar-skills` (private). Adds `scholar-polish`, moves shared reference files into `_shared/`, and propagates citation-integrity, verification, and auto-improve hardening. Orchestrator-bound features (results-lock, Phase 6.5/7b, `scholar-full-paper` wiring) are intentionally excluded — this release preserves the researcher-in-the-loop design of the public fork.

### Added

**New skill**
- **`scholar-polish`** (`/scholar-polish`) — final prose-level polish pass for manuscripts. Edits style (clarity, concision, flow, journal voice) while preserving content; distinct from `scholar-write` (drafting) and `scholar-verify` (consistency checking).

**Shared reference files (`_shared/`)**
- **`knowledge-graph-search.md`** — moved from `scholar-knowledge/references/` to `_shared/` so non-knowledge skills (lit-review, lit-review-hypothesis, write) can source KG helpers without cross-skill coupling.
- **`refmanager-backends.md`** — moved from `scholar-citation/references/` to `_shared/` so every skill that needs reference-library search (citation, write, lit-review, brainstorm, hypothesis, conceptual, idea, causal, knowledge) points to one authoritative copy.

**Agent upgrades (`agents/`)**
- **`verify-figures.md`** — adds Rule #6 value-level traceability and VLM visual inspection for figure content.
- **`verify-logic.md`** — adds Rule #8 directional comparison accuracy (verifies arithmetic behind "exceeds," "is greater than," etc.).
- **`verify-numerics.md`** — extends UNTRACEABLE / DERIVED-UNVERIFIED severity tiers from table-level to individual prose values.

**Skill updates**
- **`scholar-citation`** — mandates claim verification (not just reference verification). Step V-3.5 extracts every prose claim attributing findings to a cited source and checks it against Knowledge Graph findings (fast path) or PDF text. New claim-tier codes: `CLAIM-REVERSED`, `CLAIM-MISCHARACTERIZED`, `CLAIM-OVERCAUSAL`, `CLAIM-WRONG-POPULATION`, `CLAIM-IMPRECISE`, `CLAIM-NOT-CHECKABLE`. The absolute rule is renamed "ZERO TOLERANCE FOR CITATION FABRICATION **AND MISCHARACTERIZATION**" — attributing a real paper to a claim it doesn't make is as misleading as a fabricated citation.
- **`scholar-verify`** — three new universal rules: Rule 6 (number traceability with UNTRACEABLE/DERIVED-UNVERIFIED tiers), Rule 7 (period-label consistency across sections), Rule 8 (directional comparison accuracy). New `--no-manuscript` flag enables pre-draft verification (Stage 1 agents cross-check raw outputs against `results-registry.csv` when no manuscript exists yet).
- **`scholar-lit-review`** — adds `Agent` to tools; mandatory claim-verification gate (`verify-claims.sh`) before saving. Literature reviews are citation-dense; every finding characterization must survive the CLAIM-* checks.
- **`scholar-lit-review-hypothesis`** — same claim-verification quality-checklist item; paths updated to `_shared/`.
- **`scholar-auto-improve`** — adds `Agent` tool. Step 3b is now an **Agentic Error Analyst**: a bounded ReAct diagnostic loop (max 3 hypothesis-test cycles, max 6 tool calls) that produces a verified causal explanation before emitting any patch. Patches without a verified cause are routed to `unexplained-issues-[date].md` and excluded from the confirmation gate. Design draws on Trace2Skill (arXiv:2603.25158): agentic error analysis outperforms single-pass LLM by up to +13.3pp and correctly attributes parse failures 14% of the time vs 57% for LLM-only.
- **`scholar-safety`** — Presidio-based anonymizer (`scripts/gates/anonymize-presidio.py`) is now the preferred path for qualitative-data anonymization (NER-based person/location/institution detection); regex fallback preserved for environments without Presidio installed.
- **`scholar-analyze`** — adds specification curve analysis note (Simonsohn, Simmons & Nelson 2020, *Nat Hum Behav*) pointing to the A8o template in `references/component-a-specialized.md`.
- **`scholar-causal`** — expands staggered DiD estimator list: Callaway-Sant'Anna; Sun-Abraham; de Chaisemartin-D'Haultfoeuille; Borusyak-Jaravel-Spiess. Adds absolute CITATION INTEGRITY rule.
- **`scholar-conceptual`, `scholar-hypothesis`, `scholar-idea`** — path updates to `_shared/refmanager-backends.md` and `_shared/knowledge-graph-search.md`; absolute CITATION INTEGRITY rule added to conceptual and causal.
- **`scholar-brainstorm`** — Save Output section added listing all 5 output files (brainstorm report, summary, process log, `signal-tests.R`, `signal-tests.log`).
- **`sync-docs`** — Save Output section added with process-log path.
- **`scholar-open`** — bumps dependency pins: `fixest (>= 0.12.1)`, `rocker/tidyverse:4.4.1`.
- **`scholar-openai`** — adds `Agent` to tools.
- **`scholar-code-review`** — Variable Construction Completeness Check + Directional Coding Audit appended after Agent 6.
- **`_shared/pandoc-multiformat.md`** — adds `--metadata reference-section-title="References"` flag; scholar-polish added to consumer list.
- **`_shared/script-version-check.md`** — adds Rule #0: every line of code must have an inline comment explaining what it does and why (no exceptions for "obvious" lines).
- **`_shared/version-check.md`** — simpler gate-script re-run idiom: `MD_FILE="[saved-md-path]"; BASE="${MD_FILE%.md}"`.
- **`_shared/data-handling-policy.md`** — §9 intermediate data files (`data/interim/`) with jq sidecar auto-registration bash snippet.
- **`_shared/results-registry-contract.md`** — Study-Type Dispatch section distinguishing REGRESSION vs NON-REGRESSION schemas.

### Changed

- Skill count: **30 → 31**. `scholar-polish` added; `scholar-full-paper`, `scholar-grant`, `scholar-teach`, `scholar-book`, `scholar-presentation` remain excluded.
- Path migration: 12 files updated from `scholar-citation/references/refmanager-backends.md` / `scholar-knowledge/references/knowledge-graph-search.md` → `_shared/` equivalents (except within `scholar-knowledge/SKILL.md` and `scholar-write/references/writing-protocol.md` which continue to point at the original locations for backward compatibility with the private upstream).

### Why

Private upstream hardened citation integrity, verification, and auto-improve in parallel with the public fork. This sync brings the public fork up to date with those universal quality improvements while preserving the public fork's core design constraint: no orchestrator, researcher in the loop at every stage.

---

## [5.10.0] - 2026-04-13

Pipeline hardening against wrong-results propagation. A real project run surfaced a failure class where a buggy coefficient (sign-flip from missing fixed effects + NA-as-0 recoding) shaped a 9,000-word manuscript before post-hoc review caught the underlying bug. Because this fork intentionally excludes `scholar-full-paper` / `scholar-grant` / `scholar-book` to keep researchers in the loop, the fixes land in `scholar-analyze`, `scholar-respond`, and shared reference files in `_shared/`.

### Added

**Shared reference files (`_shared/`)**
- **`code-review-fix-loop.md`**: fix-loop spec for any pre-execution code-review gate. Classifies CRITICAL findings as AUTO_FIX (mechanical / design-blueprint-specified: missing clustering, FE, wrong SE type, NA-as-0, missing AME export, missing seed, hardcoded paths, deprecated APIs) or ESCALATE (design-level: tautological outcome, sample-restriction mismatch, identification-strategy violation). AUTO_FIX uses the Edit tool with max 2 iterations; all changes logged to `code-review-fixes-[date].md`; ESCALATE halts with `code-review-escalation-[date].md`.
- **`results-registry-contract.md`**: mandates machine-readable analysis artifacts that replace Task agent prose as source of truth. Every analysis run emits `results-registry.csv` (hypothesis × model spec mapping), `adjudication-log.csv`, `ame-*.csv` (mandatory for every logit / probit via `marginaleffects::avg_slopes()`), and `coefficients-*.csv`. Orchestrators read from disk, never from agent return text; disagreements logged to `reconcile-[date].md` and the CSV wins.
- **`phase-runtime-sanity.md`**: five runtime checks script review cannot see — plausibility scan (AME > 1, |β/SE| > 100, zero-N, NaN, inverted CIs, out-of-range p), direction consistency across M1–M4 specifications (`DIRECTION_UNSTABLE` flag), clean-room re-run in isolated R session (auto-on for ASR/AJS/Demography/Nature/Science; opt-in elsewhere via `SCHOLAR_FORCE_CLEANROOM=1`), runtime invariants via `stopifnot()`, pre-analysis-plan compliance (missing pre-registered tests CRITICAL, extra tests label EXPLORATORY).

**New scholar-analyze reference**
- **`scholar-analyze/references/adjudication-rule.md`**: deterministic coded rule replacing prose adjudication. Maps (direction, p-value, α) → `adjudication_code ∈ {SUPPORTED, SUPPORTED_NULL, CONTRADICTED, AMBIGUOUS, NOT_SUPPORTED, INCONSISTENT_FLAG}` with corresponding `prose_verb`. Includes reusable R helper `adjudicate()` and schema for `adjudication-log.csv`. Results prose must cite the log verbatim — "directionally consistent" is reserved for `AMBIGUOUS`.

**scholar-respond — New-Analysis Gate (MANDATORY)**
- New Step 3a in `scholar-respond/SKILL.md`. When R&R reviewers request additional analyses (the #1 R&R failure mode: "run with state FE", "cluster differently", "subset sample"), the new analysis flows through script generation → code-review + fix loop → registry emission (`rr-results-registry.csv`, `rr-adjudication-log.csv`) → runtime sanity → disk citation. Previously these analyses bypassed every gate and numbers were dropped into the response letter via Task agent prose paraphrase.
- `response-templates.md` "Analysis added" block rewritten to require `[rr-results-registry.csv row=X model_id=Y]` disk citations for every numeric claim. Step 3b verify-numerics now cross-checks response-letter numbers against the registry cell-for-cell.

### Changed

- **`scholar-analyze/SKILL.md`**: replaced the permissive "Avoid 'proves' — use 'is consistent with,' 'supports,' 'suggests'" writing rule with a pointer to `adjudication-rule.md`. Every hypothesis statement must use the `prose_verb` column from `adjudication-log.csv` verbatim. Quality Checklist now requires `results-registry.csv`, `adjudication-log.csv`, `ame-[model].csv` for every logit / probit, and `coefficients-[model].csv` for every fitted model.

### Why

A real project run showed a Task agent returning prose that claimed "H1c is precisely negative" while the disk CSV showed the opposite sign. Post-hoc code review caught 33 CRITICAL issues (missing clustering, missing province fixed effects, NA-as-0 recoding, a tautological outcome) — but only after results had shaped a 9,000-word manuscript. After fixes, the coefficient was null (p=0.48), invalidating the theoretical re-framing the manuscript had been built around. Root cause: review gates ran sequentially after generation, so errors propagated forward before being caught backward. This release makes gates concurrent with generation. Smoke tests: 238 PASS, 0 FAIL.

---

## [5.9.1] - 2026-04-12

Data-safety guard hardening based on external code review. Fixes 4 critical bypass routes in the PreToolUse hook, strengthens installer, and adds comprehensive regression tests.

### Fixed
- **Sidecar subdirectory bypass (P0):** Guard now walks upward from cwd to find nearest `.claude/safety-status.json` via `find_project_root()`. Previously only checked `$CWD/.claude/`, so tool calls from `project/subdir/` bypassed the project-root sidecar entirely.
- **Glob enumeration bypass (P0):** Non-empty Glob patterns like `**/*` from a scholar-init project root are now blocked. Previously only empty patterns triggered the project-root check.
- **Grep/Glob qualitative text leak (P0):** `is_rawdata_path()` now includes `materials/`, `transcripts/`, `interviews/`, `field-notes/`, `fieldnotes/` so Grep and Glob on qualitative-text directories are blocked the same way Read is.
- **OVERRIDE on text transcripts (P0):** OVERRIDE refusal now uses path classification (`is_qual_path()`), not just extension. A `.txt` or `.docx` in `transcripts/` can no longer bypass the qualitative-data OVERRIDE ban via hand-edited sidecar.
- **Relative-path classifier evasion:** `canonicalize()` now prepends `${CWD}` to relative inputs before resolution. Previously a Grep with `path="data/raw"` (relative) bypassed `is_rawdata_path`'s `*/data/raw` pattern.
- **Sidecar schema validation:** New shared `sidecar-schema.sh` library used by both guard and handshake. Rejects non-string values, unknown status strings, and non-object roots.
- **setup.sh hook registration:** `setup.sh` now actually registers the PreToolUse hook in `~/.claude/settings.json` (idempotent jq merge, preserves existing settings). Previously only documented.
- **setup.sh per-entry install:** Skills and agents are now installed as individual symlinks inside `~/.claude/skills/` and `~/.claude/agents/`, preserving pre-existing user skills. Previously replaced the entire directory.
- **Presidio install path:** `setup.sh` now installs both `presidio-analyzer` and `presidio-anonymizer`.

### Added
- `scripts/gates/sidecar-schema.sh` — shared sidecar validator sourced by guard + handshake
- `python3` hard-dependency check in the guard for gated tools (Read/Grep/Glob/NotebookRead/NotebookEdit)
- Case-insensitive SAFE_SCOPE allowlist for macOS compatibility
- 7 new smoke test files with 66 guard assertions, 14 setup assertions, and init-project/phase-verify/consistency coverage
- Error-checked destructive operations in `setup.sh` (`link_entry`, `repo_convenience_link`)

### Changed
- `init-handshake.sh` re-entry detection uses its own markers instead of generic `## Phase` headers
- `setup.sh` uses `set -uo pipefail` instead of `set -euo pipefail` for non-interactive stdin compatibility

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
