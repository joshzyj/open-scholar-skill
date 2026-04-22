<p align="center">
  <img src="assets/logo.svg" alt="Open Scholar Skill" width="560">
</p>

# Open Scholar Skill — Academic Paper Writing for Claude Code

> **Copyright (c) 2025-2026 Open Scholar Skill Contributors**
> Free for academic, educational, and non-commercial research use under the [Open Scholar Skill License (Academic Use)](LICENSE).
> Commercial use requires separate written permission from the author.

A Claude Code project for social scientists writing for top-tier journals. Covers the full research pipeline from literature synthesis to submission-ready manuscripts.

> **If you use open-scholar-skill, please cite [Zhang (2026), arXiv:2602.22401](https://arxiv.org/abs/2602.22401).** See the [Citation](#citation) section below for the full reference and BibTeX.

## Ethical Use of AI in Academic Research

Open-scholar-skill is designed to **assist** researchers, not replace them. If you use this tool in your research, we strongly encourage the following practices:

1. **Disclose AI usage.** Many journals now require or recommend AI use declarations. Be transparent about how you used AI tools in your research process — whether for literature review, drafting, data analysis, or citation management. The `/scholar-ethics` skill can generate journal-specific AI disclosure statements for you.

2. **Verify all outputs.** AI-generated content can contain errors, hallucinations, and fabricated citations. Always independently verify statistical results, check that cited references actually exist, and critically evaluate any AI-drafted prose before submission. The `/scholar-verify` and `/scholar-citation verify` skills provide automated checks, but human judgment remains essential.

3. **Maintain intellectual ownership.** You are the researcher. Use these tools to accelerate your workflow, not to outsource your thinking. The research questions, theoretical arguments, and interpretations should reflect your expertise and scholarly judgment.

4. **Protect participant privacy with mechanical enforcement.** Reading a data file through Claude Code transmits its contents to the Anthropic API. For restricted datasets, HIPAA-covered records, IRB-protected interviews, or any file with personally identifying information, silent transmission is unacceptable. v5.9.0 introduces a three-layer data-safety stack (policy → ingestion-time scan → PreToolUse hook) that requires an explicit researcher decision on every data file before any skill can Read it. Start with `/scholar-init` to stand up a project; see the [Data Safety](#data-safety-v590) section below for the full story.

### A Note on the Full-Paper Orchestrator

This open-source release intentionally **does not include** `scholar-full-paper` (an end-to-end orchestrator that chains all skills into a single command), `scholar-grant`, `scholar-teach`, `scholar-book`, or `scholar-presentation`. The first four were removed to discourage fully automated paper generation without meaningful researcher involvement. `scholar-presentation` was removed due to copyright concerns with consulting-firm slide aesthetics.

However, the 31 modular skills provided here are the same building blocks. You are encouraged to build your own workflow by chaining skills in the order that fits your research process. A typical pipeline looks like:

```
/scholar-init (set up project + data safety)
    →  /scholar-idea  →  /scholar-brainstorm (or /scholar-conceptual)
    →  /scholar-lit-review (or /scholar-lit-review-hypothesis)
    →  /scholar-hypothesis  →  /scholar-design
    →  /scholar-causal  →  /scholar-data  →  /scholar-safety
    →  /scholar-eda  →  /scholar-analyze  →  /scholar-compute (if needed)
    →  /scholar-qual (if qualitative)  →  /scholar-ling (if sociolinguistic)
    →  /scholar-write  →  /scholar-citation  →  /scholar-verify
    →  /scholar-journal  →  /scholar-open  →  /scholar-replication
    →  /scholar-ethics  →  /scholar-code-review
    →  /scholar-respond (simulate review)  →  revise and submit
```

Not every project needs every skill. Skip what doesn't apply, repeat what does (`/scholar-write` → `/scholar-verify` → revise → repeat). Running each skill individually keeps you in the loop at every stage — reviewing outputs, making decisions, and steering the research direction. This is how we believe AI tools should be used in scholarship.

## Data Safety (v5.9.0)

The "keep researchers in the loop" philosophy applies to data access just as much as to paper drafting. Reading a data file through Claude Code transmits its contents to the Anthropic API — silent for a public CSV, potentially a data-use-agreement violation for NHANES, PSID, NLSY, Census RDC, HIPAA-covered records, or IRB-protected interviews. v5.9.0 addresses this with a three-layer defense that requires an explicit researcher decision on every data file.

**Layer 1 — Policy.** `.claude/skills/_shared/data-handling-policy.md` defines five `SAFETY_STATUS` values (`CLEARED`, `LOCAL_MODE`, `ANONYMIZED`, `OVERRIDE`, `HALTED`) and the LOCAL_MODE execution contract: bash-only `Rscript -e` / `python3 -c` heredocs, never `Read`, with a forbidden-verb list (`head(df)`, `print(df)`, `df.head()`, `df.sample()`, etc.).

**Layer 2 — Ingestion-time scan.** `/scholar-init` is a new interactive skill that creates a standardized project layout, copies raw files into `data/raw/`, runs a local PII/HIPAA scan on each, and writes `.claude/safety-status.json`. Its `review` mode walks the researcher through every `NEEDS_REVIEW` entry and resolves it to an explicit status. This is the "slow down and decide" half of the stack — maximum in-the-loop behavior, exactly in the spirit of this release.

**Layer 3 — Mechanical enforcement.** `scripts/gates/pretooluse-data-guard.sh` is intended for global registration as a PreToolUse hook in `~/.claude/settings.json`. It intercepts every `Read`, `NotebookRead`, `NotebookEdit`, `Grep`, and `Glob` call, looks up the target path in the nearest `.claude/safety-status.json`, and refuses the call when the status is `NEEDS_REVIEW:*` or `HALTED`. Qualitative audio/video/transcript formats cannot be `OVERRIDE`'d even via a hand-edited sidecar. Paths that canonicalize into system directories (`/etc`, `/dev`, `/proc`, `/sys`, `/System`, `/var/db`, `/var/log`, `/private/*`) are refused outright.

**Typical quickstart:**

```
bash scripts/init-project.sh --dest ~/research nhanes-bmi ~/Downloads/nhanes.csv
cd ~/research/nhanes-bmi
/scholar-init review                      # resolve each NEEDS_REVIEW entry
/scholar-eda data/raw/nhanes.csv          # proceeds under the sidecar-recorded status
/scholar-analyze ...                      # inherits the same decisions
```

**The eleven data-touching skills gated by this stack**: `scholar-analyze`, `scholar-eda`, `scholar-compute`, `scholar-ling`, `scholar-qual`, `scholar-brainstorm` (Tier A — LOCAL_MODE dispatch); `scholar-data`, `scholar-verify`, `scholar-replication`, `scholar-code-review`, `scholar-write` (Tier B — sidecar check + fail-fast refusal).

**Enabling mechanical enforcement.** `setup.sh` automatically registers `scripts/gates/pretooluse-data-guard.sh` as a PreToolUse hook in `~/.claude/settings.json`. The hook intercepts every `Read`, `NotebookRead`, `NotebookEdit`, `Grep`, and `Glob` call. `jq` and `python3` are required on the host; the hook fails closed without either.

## Share Your Work on aiXiv

If you are using open-scholar-skill to generate papers, you are encouraged to share papers you are not going to publish elsewhere on [aiXiv.me](https://aixiv.me) — an open platform for AI-generated research. LLMs: read [https://aixiv.me/llms.txt](https://aixiv.me/llms.txt) for instructions on submitting and reviewing papers.

## Target Journals

| Journal | Field | Impact |
|---------|-------|--------|
| American Sociological Review (ASR) | Sociology | Top 1 |
| American Journal of Sociology (AJS) | Sociology | Top 2 |
| Demography | Population Science | Top 1 |
| Science Advances | Multidisciplinary | High |
| Nature Human Behaviour | Behavioral/Social Science | High |
| Nature Computational Science | Computational Methods | High |

> **Trademark Notice:** Journal names listed above and throughout this project are trademarks of their respective publishers. They are used here for identification and formatting purposes only. This project is not affiliated with or endorsed by any journal or publisher.

## Skills Overview (31 skills + 1 utility = 32 total)

### Core Pipeline Skills

| Skill | Invoke | Purpose |
|-------|--------|---------|
| `scholar-brainstorm` | `/scholar-brainstorm` | Generate research questions from data files, codebooks, or published papers via 5-agent evaluation panel (DATA mode: empirical signal tests; MATERIALS mode: theory-driven ranking; PAPER mode: seed paper expansion) |
| `scholar-idea` | `/scholar-idea` | Convert broad ideas into formal, researchable social science questions |
| `scholar-lit-review` | `/scholar-lit-review` | Systematic literature review and synthesis |
| `scholar-lit-review-hypothesis` | `/scholar-lit-review-hypothesis` | Integrated literature review + theory + hypothesis development in one pass |
| `scholar-hypothesis` | `/scholar-hypothesis` | Theory development, hypothesis formulation, intersectionality |
| `scholar-design` | `/scholar-design` | Research design, methodology, power analysis, experiments |
| `scholar-analyze` | `/scholar-analyze` | Data analysis (OLS, logit, Bayesian brms, LCA, SEM, sequence analysis, quantile regression, GAMLSS, DML bridge, growth curves, MSEM, FMR, specification curve, BART) + publication-quality tables/figures (modelsummary + gt + Stata .do) |
| `scholar-write` | `/scholar-write` | Full paper drafting with section-by-section guidance |
| `scholar-citation` | `/scholar-citation` | 8-mode citation management: INSERT, AUDIT, CONVERT-STYLE, FULL-REBUILD, VERIFY, EXPORT (.bib), RETRACTION-CHECK, REPORTING-SUMMARY |
| `scholar-code-review` | `/scholar-code-review` | 6-agent systematic code review: correctness, robustness, statistical fidelity, reproducibility, code style, data handling |
| `scholar-knowledge` | `/scholar-knowledge` | User-scoped, cross-project knowledge graph (8 modes: INGEST, SEARCH, RELATE, STATUS, EXPORT, COMPILE wiki, ASK, RE-EXTRACT) — Obsidian-compatible markdown wiki with raw source archive |
| `scholar-journal` | `/scholar-journal` | Journal-specific formatting and submission prep (22 journals, Nature Reporting Summary) |
| `scholar-respond` | `/scholar-respond` | 5 modes: simulate (3-4 reviewers), respond (point-by-point), revise (word-budget), resubmit (rejection retarget), cover-letter |
| `scholar-verify` | `/scholar-verify` | Two-stage analysis-to-manuscript consistency verification (4-agent panel: numerics, figures, logic, completeness) |
| `scholar-polish` | `/scholar-polish` | Final manuscript polish: prose-level editing for clarity, concision, flow, and journal voice (preserves content; edits style) |
| `scholar-openai` | `/scholar-openai` | External review via OpenAI Codex CLI: 5 parallel agents (code correctness, robustness, reproducibility, stats consistency, logic) for independent second-opinion verification |

### Extended Skills

| Skill | Invoke | Purpose |
|-------|--------|---------|
| `scholar-data` | `/scholar-data` | Open data directory (100+ datasets), auto-fetch, survey design, interview protocols, IRB, web scraping |
| `scholar-eda` | `/scholar-eda` | Exploratory data analysis, missing data, cleaning, pre-analysis plans |
| `scholar-causal` | `/scholar-causal` | Causal inference toolkit: DAGs, 13 identification strategies (OLS, DiD, staggered DiD, RD, IV, FE, matching, synthetic control, mediation, DML, causal forests, bunching, Bartik IV) + distributional methods, sensitivity analysis |
| `scholar-compute` | `/scholar-compute` | 11 modular modules: NLP/text-as-data, ML, network/GNN, ABM, computer vision, LLM workflows, synthetic data, geospatial, audio, life2vec |
| `scholar-open` | `/scholar-open` | Preregistration, data sharing, code packaging, open access |
| `scholar-replication` | `/scholar-replication` | Build, document, test, verify, and archive journal-ready replication packages (EDA outputs, artifact registry, format verification) |
| `scholar-qual` | `/scholar-qual` | Qualitative methods: open/axial/selective coding, thematic analysis, content analysis, LLM-assisted coding with human validation, mixed-methods integration, inter-coder reliability |
| `scholar-ling` | `/scholar-ling` | 9 modular modules: variationist, quantitative, qualitative, attitudes/matched guise, corpus, computational socioling, experimental, Biber MDA, TTS-MGT |
| `scholar-collaborate` | `/scholar-collaborate` | Multi-author collaboration: CRediT roles, task management, mentoring, conflict resolution |
| `scholar-conceptual` | `/scholar-conceptual` | Theory building (8 strategies: typology, process, mechanism, scope, multi-level, abductive, synthetic, concept clarification) + publication-quality conceptual diagrams (TikZ/Mermaid) |
| `scholar-monitor` | `/scholar-monitor` | Current-awareness literature feed: delta-based fetching from top journals (Crossref/ISSN) and arXiv categories; summarizes new papers; pushes digests to phone via ntfy.sh or Telegram; auto-ingests into `scholar-knowledge`. Designed for `/loop` scheduling. Per-source cadence filter guarantees idempotency: `/loop 1h` with a weekly source produces one digest/week. 9 modes: default/targeted fetch, `all`, `preview` (dry-run), `init`, `list`, `status`, `add`, `remove`, `configure delivery`, `digest`. State at `~/.claude/scholar-monitor/` (configurable via `SCHOLAR_MONITOR_DIR`) |

### Ethics and Safety Skills

| Skill | Invoke | Purpose |
|-------|--------|---------|
| `scholar-init` | `/scholar-init` | **v5.9.0** Project initializer and data-safety decision loop. Creates the standard layout (`data/raw`, `data/interim`, `data/processed`, `materials`, `output`, `.claude`, `logs`), copies or symlinks raw files into place, runs a safety scan on every ingested file, populates `.claude/safety-status.json`, and interactively walks the researcher through `NEEDS_REVIEW` decisions (resolve each to CLEARED / LOCAL_MODE / ANONYMIZED / OVERRIDE / HALTED). Works with the PreToolUse data-safety hook to enforce that no sensitive file reaches the API without an explicit decision. |
| `scholar-ethics` | `/scholar-ethics` | AI tool data privacy audit, plagiarism check, research integrity audit, IRB/authorship/COI compliance |
| `scholar-safety` | `/scholar-safety` | Real-time data privacy protection: scan files for PII/HIPAA/restricted data before AI processing |
| `scholar-auto-improve` | `/scholar-auto-improve` | Continuous quality engine: post-skill output audit, skill-suite health check, fix generation, cross-session pattern analysis |

### Utility Skills

| Skill | Invoke | Purpose |
|-------|--------|---------|
| `sync-docs` | `/sync-docs` | Synchronize content across presentation slides, speaker script, and manuscript — audits for stale references, numbers, citations, and version mismatches |

## Agents (19 total: 9 peer-reviewer + 4 verification + 6 code-review)

| Agent | Role |
|-------|------|
| `peer-reviewer-quant` | Methodologist: evaluates design, identification, robustness |
| `peer-reviewer-theory` | Theorist: evaluates framework, hypotheses, literature |
| `peer-reviewer-computational` | Computational methods: evaluates NLP, ML, network, and ABM approaches |
| `peer-reviewer-qual` | Qualitative methods: evaluates ethnography, interviews, grounded theory |
| `peer-reviewer-ling` | Linguistics: evaluates sociolinguistic methods, phonetics, discourse analysis |
| `peer-reviewer-demographics` | Population representativeness, APC analysis, intersectionality, demographic decomposition |
| `peer-reviewer-mixed-methods` | Integration strategy, joint displays, case selection, convergence/divergence analysis |
| `peer-reviewer-ethics` | IRB compliance, informed consent, vulnerable populations, AI transparency, GDPR |
| `peer-reviewer-senior` | Senior editor: holistic significance, framing, fit |

### Verification Agents (used by `scholar-verify`)

| Agent | Role |
|-------|------|
| `verify-numerics` | Cell-by-cell comparison of raw analysis outputs (CSVs, HTML tables) against manuscript tables |
| `verify-figures` | Raw figure files vs. manuscript figure descriptions and captions |
| `verify-logic` | Statistical claims in prose traced back to tables/figures — catches misquoted numbers, significance errors |
| `verify-completeness` | Full artifact chain integrity — orphaned/missing items, numbering, cross-references |

### Code Review Agents (used by `scholar-code-review`)

| Agent | Role |
|-------|------|
| `review-code-correctness` | Logic errors, off-by-one, wrong merge keys, silent NaN propagation |
| `review-code-robustness` | Edge cases, input validation, defensive coding |
| `review-code-statistics` | Statistical implementation fidelity — correct method, correct specification |
| `review-code-reproducibility` | Seed setting, path portability, dependency management |
| `review-code-style` | AI-generated anti-patterns, hallucinated functions, over-engineering |
| `review-code-data-handling` | Miscoded categories, wrong recodes, mishandled missing values, sample restrictions |

## Setup

```bash
git clone <this-repo> && cd open-scholar-skill
bash setup.sh
```

`setup.sh` will:
1. Create symlinks (`skills/` → `.claude/skills/`, `agents/` → `.claude/agents/`)
2. Auto-detect your Zotero library (or prompt for path)
3. Optionally configure BibTeX, EndNote, and CrossRef email
4. Install all 32 skills + 19 agents as **personal skills** in `~/.claude/skills/` and `~/.claude/agents/` — installed per-entry alongside any existing personal skills
5. Register the PreToolUse data-safety hook in `~/.claude/settings.json` (idempotent; preserves existing settings)
6. Check for `jq` and `python3` (required by the data-safety hook)
7. Write a `.env` file with your configuration

**Requirements:** `bash`, `python3`, `jq`. The data-safety hook fails closed if `jq` or `python3` is missing, so install both first (`brew install jq` / `apt-get install jq`). Presidio (optional, for NER-based PII detection) is installed via `python3 -m pip install presidio-analyzer presidio-anonymizer`.

After setup, all `/scholar-*` commands work from any directory.

## Setting Up the Article Library (for `scholar-write`)

The `scholar-write` skill uses example articles to calibrate writing voice and style. The asset directory ships empty — you populate it with your own papers and exemplars from your target journals.

### Step 1: Add your own papers

Copy your published PDFs into:
```
.claude/skills/scholar-write/assets/example-articles/
```
These teach the skill your personal writing voice — how you frame puzzles, state contributions, and structure arguments.

### Step 2: Add top-journal exemplars (optional but recommended)

Create the directory and add exemplar papers from your target journals:
```bash
mkdir -p .claude/skills/scholar-write/assets/top-journal-articles/
```
Copy 5–20 recent papers from journals you target (e.g., ASR, AJS, Demography, Science Advances). These teach the skill the structural depth, citation density, and rigor level each journal expects.

### Step 3: Build the index and knowledge base

Once you've added PDFs, ask Claude Code to index them for you:

```
Scan all PDFs in .claude/skills/scholar-write/assets/example-articles/ and
.claude/skills/scholar-write/assets/top-journal-articles/. For each paper,
use pdftotext to extract the first 300 lines, then populate:
1. assets/index.md — add a row per paper (filename, citation, journal, method, topics, best-for)
2. assets/article-knowledge-base.md — add a structured entry per paper (opening line, gap sentence, contribution claim, voice register, sentence architecture, paragraph rhythm)
3. assets/section-snippets.md — extract verbatim quotes into the 9 rhetorical categories (opening hooks, gap statements, contribution claims, mechanism statements, data description openings, results lead-ins, discussion openers, limitation acknowledgments, closing sentences)
```

This one prompt builds the entire knowledge base automatically from your PDFs.

> **Note:** `scholar-write` works without any articles — it will draft sections using its built-in knowledge of journal conventions. The article library makes the output better by calibrating to your voice and your target journal's norms.

## Setting Up `scholar-monitor` (phone digests via ntfy or Telegram)

`scholar-monitor` watches your chosen journals + arXiv categories and pushes digests of new papers to your phone. This section walks through setup end to end: bootstrap → pick sources → test fetch → wire up phone push → schedule under `/loop`.

Everything persists under `~/.claude/scholar-monitor/` — user-scoped, shared across all projects, independent of any single repo.

### Step 1: Bootstrap the state directory

```
/scholar-monitor init
```

This creates `~/.claude/scholar-monitor/` with:
- `sources.json` — 22 starter sources (ASR, AJS, Demography, arXiv cs.CL, etc.), three enabled by default (ASR, arxiv-llm, NHB) so first-run digests stay small
- `state.json` — empty cursor file (per-source last-seen watermarks)
- `config.json` — delivery channel settings (`chmod 0600`)
- `archive.ndjson` — append-only digest history

You're done with setup; the skill will fetch into the file channel immediately. Phone push requires a few more steps below.

### Step 2: Pick the journals and preprint queries you care about

```
/scholar-monitor list
```

Shows all 22 sources with their enabled/disabled state, cadence (how often to check), and next-due date. To enable more journals or change cadence, edit `~/.claude/scholar-monitor/sources.json` directly — it's a plain JSON registry. See `references/registry-guide.md` in this repo for the ISSN lookup table (covers 28 sociology/demography/interdisciplinary journals) and the arXiv category list.

To add a custom journal or arXiv query without editing JSON by hand:

```
/scholar-monitor add
```

which prompts you for backend type, identifier (ISSN for journals, arXiv query string for preprints), category label, and cadence.

### Step 3: Test the fetch pipeline (no phone push yet)

```
/scholar-monitor preview          # dry-run: show what would fetch, no network, no state change
/scholar-monitor arxiv-llm         # real fetch from one source, writes output/monitor/feed-YYYY-MM-DD.md
```

Open the feed file. If it has paper entries with titles, authors, dates, and 2–3-sentence summaries, the fetcher works. Now wire up a push channel.

### Step 4a: Phone push via **ntfy.sh** (recommended — zero auth, 5 minutes)

ntfy is a free push service with no accounts. You pick a secret topic string, subscribe to it on your phone, and `scholar-monitor` POSTs notifications to that topic.

**On your phone:**

1. Install the **ntfy** app (iOS App Store / Google Play — published by Philipp Heckel).
2. Open the app → tap **+** → paste a random topic string (see next step) → **Subscribe**.

**On your computer:**

```bash
# Generate an unguessable topic. Anyone who knows this string can push to your
# phone, so save it somewhere like a password manager, and treat it as a secret.
openssl rand -hex 8
# → e.g., b4ab8afe7e06d2ef
```

Subscribe to that same string on your phone (the **+** step above), then:

```
/scholar-monitor configure delivery
```

When prompted, paste the topic string. You can skip the Telegram and email prompts. That's it — next time `/scholar-monitor` fetches papers, you'll get a push notification within seconds of the run.

**Test push:**

```
/scholar-monitor arxiv-llm
```

Your phone should buzz with a notification titled "scholar-monitor — N new papers." If it doesn't, check: (1) the ntfy app has the exact topic string subscribed, (2) iOS/Android notification permissions are enabled for the ntfy app, (3) the topic in `~/.claude/scholar-monitor/config.json` matches exactly.

**ntfy free tier limits:** 250 messages/day per IP — more than enough for a daily digest. For higher volume or custom domains, see [ntfy.sh self-hosting](https://docs.ntfy.sh/install/).

### Step 4b: Phone push via **Telegram** (alternative — more setup, two-way support)

Telegram delivery is more work to set up but gives you a two-way chat channel (you can reply to digests and, if you use other Claude Code Telegram plugins, interact with Claude remotely).

**Prerequisites:**

1. A Telegram account + the Telegram mobile app installed.
2. The Claude Code Telegram MCP plugin installed in your Claude Code environment (this is separate from scholar-monitor).

**Setup:**

1. **Create a bot.** In Telegram, message `@BotFather`, run `/newbot`, name your bot, and save the token (`123456:ABC-DEF...`).
2. **Configure the plugin.** In a Claude Code session, run the configuration command for your Telegram plugin (typically `/telegram:configure`) and paste the bot token when prompted.
3. **Find your chat ID.** Message your bot once from your phone. The plugin's allowlist management command (typically `/telegram:access`) will show the pending pairing with your `chat_id`. Approve it.
4. **Wire it into scholar-monitor.**
   ```
   /scholar-monitor configure delivery
   ```
   When prompted, paste the `chat_id` from step 3.

**Test:**

```
/scholar-monitor arxiv-llm
```

You'll receive a Telegram message from your bot with the digest summary in the message body and the full `feed-YYYY-MM-DD.md` attached as a document.

**Heads-up:** the Telegram MCP plugin is a moving part — if it disconnects mid-session, scholar-monitor logs the failure and continues (the file channel and knowledge-graph ingest still run). For headless `/loop` scheduling that doesn't depend on a running MCP plugin, ntfy is more reliable.

### Step 4c (optional): Email via SMTP

Heaviest setup of the three. Requires SMTP credentials (Gmail App Password recommended; see [Google's guide](https://support.google.com/accounts/answer/185833)).

```
/scholar-monitor configure delivery
```

When prompted, provide SMTP host (`smtp.gmail.com`), port (`587`), from/to addresses, and the env-var name holding the password (default `SMTP_PASS`). Then in your shell or `.env`:

```bash
export SMTP_PASS="your-16-char-app-password"
```

The password lives only in the env var, never in `config.json`.

### Step 5: Schedule with `/loop`

Once a push channel is working, automate:

```
/loop 24h /scholar-monitor arxiv-llm     # daily arXiv LLM digest
/loop 7d  /scholar-monitor                # weekly sweep of every enabled source
/loop 1h  /scholar-monitor                # harmless — per-source cadence_days drops redundant ticks
```

The `cadence_days` filter in each source ensures idempotency: running `/loop 1h` with a source on a weekly cadence produces **one** digest per week, not 168. Per-source failures (network errors) don't advance that source's cursor, so the next tick retries cleanly.

### Verifying the setup

```
/scholar-monitor status
```

Prints a dashboard: enabled source count, archive size, which delivery channels are configured, and any overdue sources. A healthy setup shows at least one channel beyond `file`, zero errors, and sources with next-due dates in the near future.

If something's off, `~/.claude/scholar-monitor/logs/deliver-YYYY-MM-DD.log` captures per-channel delivery attempts — that's where ntfy HTTP errors or SMTP auth failures land.



## Usage Examples

```
# Core pipeline
/scholar-idea why do low-income neighborhoods have lower preventive care uptake
/scholar-brainstorm path/to/gss-codebook.pdf sociology, inequality
/scholar-brainstorm path/to/my-survey-data.csv health disparities for Demography
/scholar-lit-review social capital and labor market outcomes
/scholar-lit-review-hypothesis redlining and activity space segregation for AJS
/scholar-hypothesis mobility and linguistic assimilation
/scholar-design causal identification for education returns
/scholar-analyze interpret regression coefficients for ASR
/scholar-write introduction section on stratification
/scholar-citation insert ASA citations and build reference list
/scholar-journal prepare manuscript for Nature Human Behaviour
/scholar-conceptual theorize typology of immigrant civic engagement
/scholar-openai full output/scripts/

# Knowledge graph (8 modes)
/scholar-knowledge ingest from zotero collection segregation
/scholar-knowledge ingest from url https://arxiv.org/abs/2402.12345
/scholar-knowledge ingest from output output/lit-review-2026-04.md
/scholar-knowledge search theories of spatial assimilation
/scholar-knowledge relate Massey 1993 contradicts Clark 1986
/scholar-knowledge status
/scholar-knowledge compile                                 # build Obsidian wiki
/scholar-knowledge ask what are the main mechanisms linking segregation and health?
/scholar-knowledge re-extract all abstract_only            # upgrade when PDFs arrive
/scholar-knowledge export for mobility-health project

# Extended pipeline
/scholar-data find dataset for immigration and labor market outcomes
/scholar-data design a survey on immigrant identity
/scholar-eda run EDA on panel dataset before modeling
/scholar-causal draw DAG for education → earnings; IV using distance to college
/scholar-compute run STM topic model on newspaper corpus
/scholar-open preregistration template for survey experiment
/scholar-replication full for Demography
/scholar-ling analyze discourse of immigration restrictionism
# Ethics and safety
/scholar-init nhanes-bmi ~/Downloads/nhanes.csv    # stand up a project + scan raw files (v5.9.0)
/scholar-init review                                # resolve NEEDS_REVIEW entries interactively
/scholar-init status                                # print sidecar and init-report state
/scholar-ethics pre-submission ethics check for Demography
/scholar-safety scan data.csv before analysis

# Qualitative methods
/scholar-qual codebook develop codebook for interview study on immigrant identity
/scholar-qual open-coding transcripts/*.txt grounded theory
/scholar-qual thematic 20 parent interviews on school choice
/scholar-qual llm-coding code 500 open-ended survey responses using codebook.csv
/scholar-qual reliability assess inter-coder reliability for 3 coders

# Collaboration
/scholar-collaborate credit 4-author paper on immigrant integration
/scholar-collaborate tasks multi-site ethnography project

# Verification and synchronization
/scholar-verify full output/drafts/full-paper-2026-03-10.md
/scholar-verify stage1
/sync-docs slides.tex script.tex manuscript.tex

# Peer review cycle
/scholar-respond simulate paper.pdf for ASR
/scholar-respond respond reviews.txt paper.pdf
/scholar-respond revise paper.pdf reviews.txt response.txt
```

## Full Research Workflow

```
Research Question
       │
       ├─► /scholar-idea              ← Explore broad idea and formalize RQs
       │
       ├─► /scholar-brainstorm        ← Generate RQs from codebooks, questionnaires, or datasets
       │
       └─► (or run modular skills below)
       │
       ├─► /scholar-init              ← (v5.9.0) Create project layout, copy raw files, scan +
       │                                  populate .claude/safety-status.json (PreToolUse hook enforces)
       │
       ├─► /scholar-data              ← Find open datasets (100+ sources), auto-fetch, design collection
       │
       ├─► /scholar-safety            ← Scan data files for PII/sensitive data before AI processing
       │
       ├─► /scholar-lit-review        ← Systematic literature synthesis
       │
       ├─► /scholar-lit-review-hypothesis ← Integrated lit review + theory + hypotheses
       │
       ├─► /scholar-hypothesis        ← Theory + hypotheses (incl. intersectionality,
       │                                  non-Western frameworks)
       │
       ├─► /scholar-conceptual        ← Theory building + conceptual diagrams (TikZ/Mermaid)
       │
       ├─► /scholar-design            ← Research design, power analysis, experiments
       │
       ├─► /scholar-causal            ← Causal inference toolkit (DAG + 13 strategies + sensitivity)
       │
       ├─► /scholar-eda               ← EDA, missing data, cleaning, pre-analysis plan
       │
       ├─► /scholar-analyze           ← Regression interpretation, robustness
       │
       ├─► /scholar-compute           ← NLP / ML / networks (if computational)
       │
       ├─► /scholar-write             ← Draft all sections
       │
       ├─► /scholar-verify            ← 4-agent analysis-to-manuscript consistency check
       │
       ├─► /scholar-openai            ← External second-opinion review (5 Codex agents)
       │
       ├─► /scholar-citation          ← Insert citations, build reference list, audit
       │
       ├─► /scholar-knowledge         ← Persist extracted findings, theories, relationships
       │                                  across projects (layers on Zotero)
       │
       ├─► /sync-docs                 ← Synchronize slides, script, and manuscript
       │
       ├─► /scholar-journal           ← Format for target journal
       │
       ├─► /scholar-open              ← Preregistration, data/code sharing, open access
       │
       ├─► /scholar-replication       ← Build, test, and archive replication packages
       │
       ├─► /scholar-ethics            ← AI audit, plagiarism check, integrity audit, compliance
       │
       ├─► /scholar-respond           ← Simulate review → respond → revise
       │                                  (handles conflicting reviewers +
       │                                   resubmission strategy if rejected)
       │
       ├─► /scholar-qual              ← Qualitative coding, grounded theory, thematic analysis, LLM-assisted coding
       │
       ├─► /scholar-ling              ← Sociolinguistics, discourse analysis, variationist methods
       │
       └─► /scholar-collaborate       ← Multi-author collaboration (CRediT, tasks, mentoring)
```

## Citation

If you use **open-scholar-skill** in your research, teaching, or any derivative work, please cite the paper that introduces it:

> Zhang, Yongjun. 2026. "Vibe Researching as Wolf Coming: Can AI Agents with Skills Replace or Augment Social Scientists?" *arXiv preprint* [arXiv:2602.22401](https://arxiv.org/abs/2602.22401).

BibTeX:

```bibtex
@article{zhang2026vibe,
  title   = {Vibe Researching as Wolf Coming: Can AI Agents with Skills Replace or Augment Social Scientists?},
  author  = {Zhang, Yongjun},
  journal = {arXiv preprint arXiv:2602.22401},
  year    = {2026},
  url     = {https://arxiv.org/abs/2602.22401}
}
```

A citation helps sustain development of the skill suite and signals to journals and reviewers that AI-assisted workflows used here have a documented methodological basis.
