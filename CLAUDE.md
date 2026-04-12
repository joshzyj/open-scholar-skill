# Open Scholar Skill — Project Instructions

## Getting Started

After cloning, run `bash setup.sh` once. This creates symlinks, auto-detects Zotero, and writes `.env`. See `.env.example` for all options.

---

## Directory Structure

```
open-scholar-skill/
├── CLAUDE.md                    # THIS FILE
├── CHANGELOG.md                 # Version history
├── README.md / USAGE.md         # User-facing docs
├── scripts/gates/               # Executable gate scripts (version-check, safety-scan, verify-citations,
│                                #   pretooluse-data-guard, init-handshake, derive-proj, phase-verify)
├── scripts/init-project.sh      # Project initializer used by scholar-init
├── tests/smoke/                 # Smoke tests (run: bash tests/smoke/run-all.sh)
├── skills/ → .claude/skills/    # Symlink (DO NOT replace with directory)
├── agents/ → .claude/agents/    # Symlink (DO NOT replace with directory)
└── .claude/
    ├── skills/                  # 29 skill directories, each with SKILL.md + references/
    │   ├── _shared/             # Shared protocols (process-logger.md, version-check.md, data-handling-policy.md, tier-b-safety-gate.md)
    │   ├── scholar-init/        # v5.9.0 — project initializer + data safety sidecar populator (4 modes: init/review/add/status)
    │   ├── scholar-analyze/     # Components loaded on-demand via references/component-a-*.md
    │   ├── scholar-auto-improve/# Continuous quality engine (4 modes)
    │   ├── scholar-brainstorm/  # Data-driven RQ generation from codebooks/questionnaires/datasets
    │   ├── scholar-causal/      # 13 strategies loaded on-demand via references/strategies.md
    │   ├── scholar-citation/    # Citation management + verification
    │   ├── scholar-code-review/ # 6-agent code auditor for analysis scripts
    │   ├── scholar-collaborate/ # Multi-author collaboration (CRediT, tasks, mentoring)
    │   ├── scholar-compute/     # 11 modules (on-demand loading via references/module-*.md)
    │   ├── scholar-conceptual/  # Theory building + conceptual diagrams (TikZ/Mermaid)
    │   ├── scholar-data/        # Data collection, open data directory (100+ sources), web scraping
    │   ├── scholar-design/      # Research design + power analysis
    │   ├── scholar-eda/         # Exploratory data analysis
    │   ├── scholar-ethics/      # Research ethics toolkit
    │   ├── scholar-hypothesis/  # Theory + hypothesis formulation
    │   ├── scholar-idea/        # Broad idea → formal RQ (5-agent evaluation panel)
    │   ├── scholar-journal/     # Submission prep (22 journals)
    │   ├── scholar-knowledge/   # User-scoped knowledge graph (INGEST, SEARCH, RELATE, STATUS, EXPORT)
    │   ├── scholar-ling/        # 9 modules loaded on-demand via references/module-*.md
    │   ├── scholar-lit-review/  # Systematic literature review
    │   ├── scholar-lit-review-hypothesis/  # Integrated lit review + hypothesis
    │   ├── scholar-open/        # Open science practices
    │   ├── scholar-openai/      # External review via OpenAI Codex CLI agents
    │   ├── scholar-qual/        # Qualitative methods (coding, grounded theory, thematic analysis)
    │   ├── scholar-replication/ # Replication package builder + validator
    │   ├── scholar-respond/     # Peer review simulation + R&R
    │   ├── scholar-safety/      # Data safety layer
    │   ├── scholar-verify/      # Two-stage analysis-to-manuscript consistency (4-agent panel)
    │   ├── scholar-write/       # Section drafting (5-agent review panel)
    │   └── sync-docs/           # Cross-document synchronization utility
    └── agents/                  # 19 agents (9 peer-reviewer + 4 verify + 6 code-review)
```

**Version**: v5.9.0 — 29 skills, 19 agents (9 peer-reviewer + 4 verify + 6 code-review)

---

## Key Design Patterns

### Skill Architecture
- Each `SKILL.md` has YAML frontmatter: `name`, `description`, `tools`, `argument-hint`, `user-invocable: true`
- Skills invoked via `/scholar-[name] [arguments]`
- Pattern: dispatch table → numbered workflow steps → save output → quality checklist

### On-Demand Module Loading
Large skills are split into routing stubs + reference files loaded via `cat` on demand:
- **scholar-compute**: 11 module files (`references/module-01-nlp.md` through `module-11-life2vec.md`)
- **scholar-analyze**: 6 component files (`references/component-a-core.md`, etc.) + REVISE-FIGURE mode
- **scholar-causal**: 1 strategies file (`references/strategies.md` — 13 strategies)
- **scholar-ling**: 9 module files (`references/module-01-theory.md` through `module-09-tts-mgt.md`)

Skills route to the correct file, then `cat` only what's needed. This cuts context usage by 60-90%.

### Executable Gate Scripts
Critical gates are enforced by actual scripts in `scripts/gates/`:
- `version-check.sh <dir> <stem>` — prints `SAVE_PATH=...` (prevents overwriting drafts)
- `safety-scan.sh <file>` — local PII/HIPAA detection (exits RED/YELLOW/GREEN); routes to Presidio backend if installed. Binary formats (`.xlsx`, `.parquet`, `.dta`, `.sav`, `.rds`, etc.) are promoted to YELLOW even when scanners return GREEN.
- `safety-scan-presidio.py <file>` — Presidio NER-based PII detection backend (called by safety-scan.sh)
- `anonymize-presidio.py scan|anonymize|keygen|verify <file>` — Presidio-based anonymizer for qualitative data
- `pretooluse-data-guard.sh` — PreToolUse hook auto-registered in `~/.claude/settings.json` by `setup.sh`. Intercepts `Read` / `NotebookRead` / `NotebookEdit` / `Grep` / `Glob`, walks upward to discover nearest `.claude/safety-status.json` (ancestor lookup — works from subdirectories), validates sidecar schema, refuses `NEEDS_REVIEW:*`, `HALTED`, and qualitative-text `OVERRIDE`. Fails closed on missing `jq` or `python3`, unresolved symlinks, and system-directory paths.
- `sidecar-schema.sh` — shared sidecar schema validator. Sourced by both `pretooluse-data-guard.sh` and `init-handshake.sh`. Rejects non-string values and unknown status strings.
- `init-handshake.sh` — standalone handshake helper (bundled for parity; no in-repo caller since `scholar-full-paper` is deliberately absent).
- `derive-proj.sh` — canonical `${PROJ}` helper.
- `phase-verify.sh <phase> <project_dir>` — checks PROJECT STATE, output files, word counts per phase (shipped for parity; no in-repo orchestrator uses it).
- `verify-citations.sh <draft>` — checks for fabricated/orphaned citations

### Data Safety Stack (v5.9.0)
Three layers. See `CHANGELOG.md` v5.9.0 and README "Data Safety (v5.9.0)" for the full story.

1. **Policy** — `.claude/skills/_shared/data-handling-policy.md`. Defines 5 `SAFETY_STATUS` values (`CLEARED`, `LOCAL_MODE`, `ANONYMIZED`, `OVERRIDE`, `HALTED`) + LOCAL_MODE execution contract (`Rscript -e` / `python3 -c` heredocs, forbidden verbs `head(df)` / `print(df)` / `df.head()` / `df.sample()`).
2. **Ingestion** — `/scholar-init` + `scripts/init-project.sh`. Copies raw files into `data/raw/`, scans each, writes `.claude/safety-status.json`. Interactive `review` mode resolves every `NEEDS_REVIEW` entry — this is the "keep researchers in the loop" moment.
3. **Enforcement** — `scripts/gates/pretooluse-data-guard.sh`. Intended for global registration in `~/.claude/settings.json`. Refuses unsafe reads even if a sub-skill forgets to check.

The 11 data-touching skills in this repo are all gated (6 Tier A, 5 Tier B). `scholar-full-paper` is deliberately absent per the README — the init-handshake.sh script ships for parity but has no caller here.

### Citation Rules
- **ABSOLUTE RULE**: Zero tolerance for citation fabrication
- 7-tier verification: Local Library → CrossRef → Semantic Scholar → OpenAlex → Google Scholar → WebSearch
- Unverified claims flagged as `[CITATION NEEDED]`
- Run `bash scripts/gates/verify-citations.sh <draft>` before finalizing

### Process Logging
Every skill auto-generates `output/logs/process-log-[skill]-[YYYY-MM-DD].md`. Protocol in `_shared/process-logger.md`.

### Output Formats
Manuscript skills generate 4 formats: `.md`, `.docx`, `.tex`, `.pdf` via pandoc.

---

## Reference Manager Integration

Unified search layer: `.claude/skills/scholar-citation/references/refmanager-backends.md`

| Tier | Backend | Notes |
|------|---------|-------|
| 0 | Knowledge Graph | `scholar-knowledge` NDJSON files; guarded — works without it |
| 1 | Zotero / Mendeley / BibTeX / EndNote | Local; auto-detected; limit 100 |
| 2a-2d | CrossRef / Semantic Scholar / OpenAlex / Google Scholar | External APIs; limit 50 each |

**Config**: `SCHOLAR_ZOTERO_DIR`, `SCHOLAR_BIB_PATH`, `SCHOLAR_ENDNOTE_XML`, `SCHOLAR_CROSSREF_EMAIL`, `S2_API_KEY`, `SCHOLAR_KNOWLEDGE_DIR` — all in `.env`.

---

## User Preferences
- Focus: social sciences (sociology, demography, linguistics, computational social science)
- Journals: ASR, AJS, Demography, Science Advances, NHB, NCS
- ASR/AJS: AME preferred over odds ratios
- Nature journals: Reporting Summary, data/code availability, CRediT required

---

## Workflow Rules

### File Versioning (NEVER overwrite drafts)
- Run `bash scripts/gates/version-check.sh <output_dir> <filename_stem>` before every Write tool call
- Use the printed `SAVE_PATH` as the file path — never hardcode
- Shell variables do NOT persist between Bash calls — re-derive in every call

### LaTeX / Presentations
- Use `xelatex` (not `pdflatex`) for Unicode
- Account for section title pages when mapping slide numbers to PDF pages
- Verify compiled PDF output exists and spot-check content

### Document Synchronization
- Always update slides, script, and manuscript in sync — use `/sync-docs`

### Figures & Visualization
- Always use `viz_setting.R` (custom theme) — never default ggplot2 themes

### Verification Protocol
- After edits: (1) confirm file exists, (2) extract text to confirm changes, (3) report what you see, not what you expect

### Smoke Tests
Run `bash tests/smoke/run-all.sh` after editing any SKILL.md to catch regressions.
