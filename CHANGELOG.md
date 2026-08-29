# Changelog

All notable changes to open-scholar-skill are documented in this file.
Format follows [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased] - 2026-08-28

### Added: scholar-auto-research F20/L4 — production completion authority (ported from dev)

- `.claude/skills/scholar-auto-research/` is now **byte-exact with the development tree** (81 -> 227 files, no deletions — the prior contents were a strict subset). Completion authority is production-driven across Phases 0-20 and the terminal `DONE` transition, with the coverage manifest and its bidirectional lint packaged inside the skill.
- `_AR_SKILL` absolute skill-directory resolution replaces hardcoded `.claude/skills/...` paths. The skill dir is resolved from the loaded `SKILL.md`, never inferred from the working directory, `$HOME`, a marketplace symlink, or a parent plugin tree — so an installed copy no longer depends on repository layout.
- **Why the whole subtree, not a patch:** `tests/helpers/coverage_lint.py` pins `scripts/auto-research-fixture-test.sh` by SHA-256 and parses it for exactly 90 call stanzas. Any local adaptation of a pinned file breaks the pin, so this feature cannot be ported file-by-file.
- Verified in this repository after the port: `test-coverage-manifest.sh` PASS — findings=20, phases=21, phase_invariants=705, external_gates=69, cases=427; all 6 coverage probes PASS.
- Also ported: `_shared/agent-trace-contract.md`, evidence/receipt gates, and assorted `scripts/gates/` and `tests/smoke/` additions reached by dependency closure.

### Not included

- Repo-level files whose local versions have diverged too far from the development tree to accept the change safely — notably `scripts/gates/phase-verify.sh`, `tests/smoke/test-phase-verify.sh`, the `scholar-rag` assets, and the `review-code-*` / `verify-*` agent definitions. These remain at their previous versions and are unaffected by this change.
- Gates and suites this repository intentionally does not ship are unchanged; references to them in ported comments are design provenance, not instructions to run.

## [5.21.0] - 2026-08-14

### Added: Traceability section in project CLAUDE.md auto-rules (§F)

- `scripts/templates/claudemd-auto-rules-lean.md` — new **§F. Traceability — log every step, archive every script**: (1) every skill run appends a per-step RAO trace via `emit-trace.sh` (protocol `_shared/process-logger.md`; agent sidecars folded via `ingest-agent-trace.sh`; `trace-coverage-check.sh` RED on missing trace); (2) every executed R/Python/Stata/Julia script — including LOCAL_MODE `Rscript -e` / `python3 -c` heredocs — is archived verbatim to the project `scripts/` dir (`${OUTPUT_ROOT}/scripts/`) with the skill's numbering prefix and run header (protocol `_shared/script-version-check.md`); (3) trace-privacy rule (aggregate metrics only, never raw rows/PII). Rationale: project memory files previously carried zero traceability rules, relying entirely on each skill remembering its own protocol.
- `scholar-init/SKILL.md` Step 1.2.5 — cross-skill rule list updated to name traceability.
- Existing projects pick the section up automatically on the next `setup-project-claudemd.sh` invocation (content-diff refresh; `v2-lean` marker unchanged).

## [5.20.0] - 2026-08-13

### New: Pre-Execution Code Review — hash-bound independent review before model-authored code executes

Ported (surgically, adapted to this repo's roster — orchestration references target `scholar-auto-research` Phase 6) from the dev line's v5.29.0–5.29.2. Before this release, the six skills that author and execute analysis code (`scholar-analyze`, `scholar-eda`, `scholar-compute`, `scholar-data`, `scholar-simulate`, `scholar-ling`) ran that code with no independent review outside `scholar-auto-research`, three of them could not even dispatch reviewer agents (no `Agent` tool grant), and a fixed script could silently diverge from what was reviewed.

- **`_shared/pre-execution-review.md`** (NEW) — the shared protocol: `DRAFTED → REVIEWED+HASHED → EXECUTABLE` state sequence (the reviewed bytes are the executed bytes; no inline re-typing), mechanical pilot exemption (declared caps, no manuscript/registry output, no paid batches, logged provenance), N-separate-reviewer-dispatch rule, per-skill phase tags, `--skip-preexec-review` (logged + Limitations-justified), catch-all for ad-hoc code around vendored engines.
- **`scripts/gates/pre-exec-review-check.sh`** (NEW) — hash-binding gate: pairs report↔manifest by `review_id`, recomputes SHA-256 per reviewed script, REDs any mismatch/missing/extra script, ports the blocking-verdict enum, checks escalation logs and the supersedes fix chain, delegates reviewer coverage. GREEN/RED/YELLOW(legacy, non-executable)/INERT.
- **`scripts/gates/code-review-coverage-check.sh` + `emit-task-dispatch.sh`** (NEW here) — reviewer-coverage verification with dispatch-manifest provenance (`--phase=<tag>`; prose token-counting can never GREEN a new pre-execution review) and the dispatch-recording helper it binds against.
- **`scholar-code-review`** — Planned-Script (Pre-Execution) mode documented (incl. the `pre_execution_planned` crosswalk scholar-auto-research's Phase 6 contract asserts); reviewed-scripts manifest (`code-review-manifest/v1`) emitted with every report; every reviewer dispatch recorded (separate parallel Agent calls, distinct agentIds); **Step 6: Post-Fix Re-Review (MANDATORY)** — fixes are never self-certified: affected reviewers re-adjudicate the fixed bytes, superseding report+manifest, max 2 cycles then escalate; Integration table rewritten to the real integrations.
- **Six skill integrations** — analyze: sub-stage A2.5 (model ladder drafted → reviewed → reviewed files execute; banners in the model-bearing cookbooks); eda: Phase 11 handoff review of E-scripts (+ `E08`/`E09` numbering so every code-running phase is covered); compute: MODULE 0.7 pre-scale review with per-module pilot caps; data: W4/W6/W7 authored-code duty (byte-unmodified fetch templates exempt); simulate: generated analysis scripts archived as `5N-*` + reviewed, and **engine-enforced dry-run receipts** (`simulate_engine.py` refuses paid runs without a manifest-hash-matched receipt; `--override-dry-run <reason>` is ledger-logged); ling: draft-first for model-fitting L-scripts. `Agent` tool granted to compute/data/ling. respond: R&R reviews now hash-bound before `rr-NN-*.R` executes.
- **Tests** — `test-pre-exec-review-check.sh` (16 cases incl. the full blocking-verdict shape matrix and the single-byte hash-mismatch drill), `test-code-review-coverage-check.sh` (14), `test-scholar-simulate-dryrun.sh` (28 incl. 5 receipt-enforcement cases), `test-preexec-doc-integrity.sh` (roster-adapted).

## [5.19.0] - 2026-08-12

### New: Evidence Ledger — write-time source-passage provenance for literature claims

Ported (surgically, adapted to this repo's skill roster and architecture) from the dev line's evidence-ledger feature. Before this release, skills read verbatim source passages — `rag_search` hits, `pdftotext` extracts, KG findings, abstracts — and discarded them: no artifact linked "what the source said" to "what we wrote", and a claim checked by V-3.5 left no positive record. Now every literature-touching skill writes ONE anchor per source passage used at claim finalization into a per-project Evidence Ledger, and a rendered Evidence Dossier puts the prose and the verbatim passages side by side.

- **`schema/claim-anchor.schema.json` + `schema/claim-audit-record.schema.json`** (NEW) — claim-anchor/v1 (verbatim `evidence_quote` ≤60 words + context, page/section locator, T0–T4 access tier, honest `evidence_form` incl. `kg_paraphrase`/`metadata_only`, `stance` for contested findings, source-side `anchor_id` so prose rewrites don't churn identity) and claim-audit-record/v1 (the format `verify-claim-faithfulness` has referenced since it shipped — now materialized, with `anchor_refs[]` + `claim_fingerprint`).
- **`.claude/skills/_shared/evidence-ledger.md`** (NEW) — the single shared protocol: two-stage rule (search logging ≠ capture; anchors only at claim finalization), tier-honest capture table per read site, `<!--ev: id-->` tag grammar, eval-loadable bash helpers (`ev_capture` with dedup, `ev_ingest_sidecar` for Task-subagent sidecars), quote caps, privacy rule (`evidence/` is the sanctioned verbatim-quote home; excluded from replication packages).
- **`scripts/gates/evidence-anchor-check.sh`** (NEW) — countable coverage gate: `--phase 2` (ledger schema-lite validation + many-to-many claim-inventory join), `--phase 7` (every `<!--ev:-->` tag resolves; cite-key adjacency; tag coverage), `--phase 8` (audit exists + consistent + zero HIGH severities + coverage + metadata-only rate). Exit 0/1/2/3 = GREEN/RED/YELLOW/INERT; legacy projects (no `evidence/` dir) are INERT, never failed retroactively. The `--phase 11-entry` reconciliation mode degrades to INERT here (this repo ships no Phase-11 orchestrator or canonical-draft resolver).
- **`scripts/gates/check-claim-audit-consistency.sh`** (NEW) — R1–R7 audit validation: canonical verdict→severity map, evidence_quote REQUIRED for SUPPORTED/CONTRADICTED sub-claims, precision rule (UNSUPPORTED requires full text — abstract-only absence is never UNSUPPORTED).
- **`scripts/render-evidence-dossier.py`** (NEW) — renders the Evidence Dossier (dashboard with action-required view; per-claim cards ordered by manuscript section; unused-anchor + source-index sections; UNADJUDICATED stamp until an audit exists) and section-scoped Evidence Briefs for drafting.
- **Producer duties added** (each a compact pointer to the shared protocol + a required `Evidence anchors: N created / M reused` log row): `scholar-lit-review` + `scholar-lit-review-hypothesis` (capture at rag/pdftotext/KG read sites, claim-inventory emission, dossier render + gate step; LRH also gains the previously missing `scholar-rag` full-text tier), `scholar-write` (new Step 0a-evidence: read the section Evidence Brief before drafting Introduction/Theory/Discussion; stay faithful to anchored passages; tag sentences), `scholar-citation` (INSERT-time tier-honest capture — "cited on metadata alone" becomes visible; V-3.5 gains the ledger fast path and now persists every adjudication incl. supported claims), `scholar-hypothesis`, `scholar-conceptual`, `scholar-respond` (R&R citations + inherited-tag semantics through revisions), `scholar-idea`, `scholar-brainstorm`.
- **`scholar-polish`** — new Absolute Rule 6: preserve all inline HTML comments (especially `<!--ev:-->` bindings) verbatim through rewrites; consistency check + checklist rows compare pre/post comment counts.
- **`scholar-auto-research`** — `lit-theory-manifest.json` gains the `"evidence_ledger": {"path", "records"}` assertion; `auto-research-verify.sh` Phase 2 validates it (file exists, actual lines ≥ records; legacy manifests without the key pass unchanged). Fixture suite updated atomically, including a negative fixture (overclaimed record count must FAIL).
- **`verify-claim-faithfulness` agent** — Phase 4 fast path reads the real ledger (`evidence/claim-anchors.ndjson`); records `anchor_refs[]`; Phase 6 emits a record for every adjudicated claim including CLAIM-VERIFIED, with `claim_fingerprint` for future rewrite detection.
- **Privacy scope** (`_shared/process-logger.md`, CLAUDE.md) — the no-verbatim-quotes rule governs *traces*; `evidence/*.ndjson` is the sanctioned quote home. `_shared/source-integrity.md` panel claim-accuracy rows gain a REQUIRED verbatim evidence-quote column.
- **`tests/smoke/test-evidence-ledger.sh`** (NEW) — 47 checks incl. negative fixtures (schema-invalid ledger lines, unresolvable inventory ids, dangling tags, adjacency mismatches, HIGH-severity audits, overclaimed manifests) and this repo's documented degradations.

## [5.18.2] - 2026-08-12

### Fixed: `scholar-annotate` MODE 7 — the hard reliability gate could be passed by a failing annotator

**If you use `/scholar-annotate`, update.** The κ gate that is supposed to block a full-corpus
run had three independent defects, any one of which could clear an annotator that should have
been rejected. Run against a fixture where the annotator failed **40% of documents** and scored
κ = 0.000 on its second field, the shipped gate printed `FAIL` on both fields and then
`PASS — cleared for MODE 8`, exit 0.

- **The gate excused the annotator's own failures.** `cmd_validate` inner-joined predictions
  onto gold, so every document the annotator failed on left the denominator. Failing the hard
  cases and answering the easy ones *raised* the reported κ. Gold is now the denominator: the
  report carries `n_gold_labeled`, `n_scored`, `n_unscored` and `coverage`, and RED-fails below
  `--min-coverage` (default 0.95). Each excluded row records the branch that excluded it
  (`annotator_absent` / `annotator_blank` / `gold_empty`). The `g.notna()` mask was also dead
  code after `.fillna("")`.
- **An undefined κ passed.** A degenerate single-label column — which is what a high failure
  rate produces — yields κ = NaN, and `nan < 0.70` is `False` in IEEE-754, so the gate flag was
  never cleared. `cohen_kappa` is now `null` with a companion `kappa_undefined_reason`, and
  never passes.
- **Only the first `--on` field could fail the gate.** A secondary field at κ = 0.000 printed
  `FAIL` and still exited 0. All named fields are gated by default; `--primary-only` restores
  the old behaviour and records that choice in the report.

Also in the engine: `validation_report.json` is now strict JSON (it previously emitted bare
`NaN`, which non-Python parsers reject); unreadable corpus files fail closed rather than
silently shrinking the sample (`--allow-unreadable N` to opt in, count stamped on the output);
`sample` writes a `<out>.design.json` sidecar recording n / pool / seed / strata / lexicon
digest, so a measurement's design parameters stop living only in whoever last typed the command.

### Added: construct-match — a measurement is a number *plus the question that produced it*

The κ gate certifies an annotator **for the task as prompted**. It structurally cannot detect
that the prompt asked a broader or narrower question than the model consuming the number needs
— both instruments validate well against their own gold, so no reliability metric sees the
mismatch. That gap is now closed by a second blocking check at MODE 7.

- **New** `scripts/gates/measurement-instrument-check.sh` — binds every measurement-derived
  constant to the instrument that produced it, and every instrument to a recorded `asked` vs
  `needed` verdict (`MATCH` / `BROADER` / `NARROWER` / `UNASSESSED`, no default). Also catches
  constants that drifted from their declaration, and artifacts produced under design parameters
  that disagree with `design/measurement-design.json`. Exit 0/1/2/3; **INERT on any project that
  never used the measurement path**, so it is silent for everyone else.
- **New** `.claude/skills/scholar-annotate/references/construct-match.md` — the schema, the
  verdict table, and the failure mode it prevents.
- `validation_report.json` now carries an `instrument` block (model, api_base, codebook digest,
  program hash, timestamp). Absent provenance RED-fails unless explicitly waived with
  `--no-instrument`, which records the waiver on the artifact.
- Wired into `phase-verify.sh` Phase 6.

### Added: `_shared/defect-class-registry.md` — cross-project defect classes

Seven named classes (three-valued logic collapse and its four shapes; guards verified only in
the state they were designed for; fix commits as a fresh unaudited surface; a measurement
consumed without its instrument; defaults that determine evidentiary strength; presence checked
where vintage is meant; pins trusted by permission rather than verified by content) — each with
a mechanism, an evidence table, a countable trigger where one exists, and the remedy *plus its
constraints*. All six `review-code-*` agents now sweep for the class registry on every dispatch,
and `scholar-auto-improve` loads it during AUDIT and IMPROVE.

**Provenance note:** these classes are documented from a single large annotation run, not
validated across a corpus of projects. Treat them as named patterns to sweep for, not as
established base rates.

### Changed

- **`scholar-compute` MODULE 7 now redirects annotation-as-measurement to `/scholar-annotate`**
  (new Step 1d). MODULE 7 keeps the ad-hoc half — one-off extraction, RAG / document QA,
  grounded-theory discovery, prompt-optimization technique. The dividing line is whether the
  output is an artifact a researcher *reads* or a variable a model *consumes*. Previously
  `scholar-annotate` claimed to replace MODULE 7 while MODULE 7 never referenced it, so the
  skill carrying the reliability gate was reachable only by direct invocation.
- **`review-code-robustness` and `review-code-correctness`** must now emit a per-guard
  **FIRES ON / SLIPS PAST** pair — what input makes a guard trigger, and what it is meant to
  catch but does not.
- **`review-code-statistics` and `review-code-data-handling`** must now trace every
  measurement-derived constant to its instrument and judge construct match.
- **All six `review-code-*` agents** additionally distinguish findings **verified at time of
  writing** from those **inherited earlier in the session**.
- **`scholar-auto-improve` IMPROVE Step 3a** ingests three sources rather than one: prior
  auto-improve reports, **hand-authored run ledgers**, and the defect-class registry. Ledger
  rows are treated as claims to re-verify against the live tree, never as facts.
- **`_shared/objectivity-mandate.md`** gains rule 9: state whether a relayed claim was
  **verified** or **forwarded**.

### Tests

Five new smoke suites (`test-annotate-engine-gate`, `test-measurement-instrument-check`,
`test-annotate-routing`, `test-defect-class-registry`, `test-agent-tool-grants`). Suites that
assert on components this distribution does not ship (`scholar-full-paper`,
`model-spec-lint.sh`) report **INERT** for those checks rather than passing silently.

## [5.18.1] - 2026-08-06

### Fixed: `scholar-rag` section detection was labelling 98% of chunks `front`

Two upstream bugs made `chunk_embed.detect_sections` almost entirely inert, so section-filtered retrieval (`rag_search(section="methods")`) returned nothing useful and reference lists were indexed as if they were body prose.

- **`assets/extract.py` — `_dehyphenate` destroyed line structure.** The rule `re.sub(r"(?<!\n)\n(?!\n)", " ", text)` collapsed *every* single newline to reflow PDF-wrapped prose, which also flattened standalone heading lines; a 30-page paper arrived as a handful of giant blobs. It now decides per line break: a line that ran to the body column width wrapped and is joined, a line that stopped short ended deliberately (heading, author line, list item, paragraph end) and keeps its break. A line whose successor opens lowercase is always joined, which keeps prose intact — headings are followed by capitalised text and so are never swallowed. Column width is estimated per page from the 75th percentile of line lengths, since a plain median is dragged down by table cells and figure labels.

- **`assets/chunk_embed.py` — `detect_sections` only matched standalone heading lines.** It now anchors headings on structural boundaries (start of text, page break, end of the previous sentence) so it works on inline headings too, with case-sensitive surface forms to reject prose mentions ("as noted in the introduction"), position windows to reject implausible placements, and a DP pass that forces marks to progress in canonical section order. The original line-based pass is retained for extractor output that did preserve newlines.

Measured over 300 documents from a real 4,000-paper library: documents with ≥3 identified sections went from **0.7% → 42%**, reference-list detection from **1.7% → 64%**, and chunks labelled `front` from **98.3% → 41%**. Re-extracting with the `_dehyphenate` fix as well raises those to 62% and 85%. Because `chunk_document` excludes the `references` span from the chunk pool, roughly **12–19% of indexed text stops being bibliography**.

Both fixes apply to newly ingested documents. Existing indexes keep their labels until re-ingested: `python extract.py run --force && python chunk_embed.py run --force`.

## [5.18.0] - 2026-07-31

### New skill: `scholar-rag` — local vector database + GraphRAG over your reference library

A fully-local, self-contained retrieval layer for literature review. It turns your whole Zotero library (or a folder of PDFs) into a searchable, cited knowledge base and exposes it to Claude Code + Codex via MCP. Complements `scholar-knowledge` (symbolic extracted findings, keyword-searched) with dense full-text **passage** retrieval — the exact paragraphs nearest a query, with author-year citation + page number, plus the papers near them.

- **`.claude/skills/scholar-rag/SKILL.md`** — thin dispatcher (6 modes: `setup`, `ingest`, `query`, `mcp`, `graph`, `status`) over a real `assets/` execution engine, plus `references/engine.md`. Keeps `tools: Read, Bash, Write`.
- **Engine (`assets/`)** — `zotero_reader.py` (reads `zotero.sqlite` read-only, resolves `storage/<key>/<file>` attachment paths), `extract.py` (PyMuPDF → `pdftotext` → optional ollama vision-OCR ladder), `chunk_embed.py` (section-aware chunking + **bge-m3** → **LanceDB** + BM25 full-text index), `query.py` (dense + hybrid RRF + cross-encoder rerank + section/year filters, page-anchored citations), `fetch.py` (open-access PDF fetch: Unpaywall → OpenAlex → arXiv, `%PDF`-verified, OA-only), `graphrag.py` (seed from `scholar-knowledge` → local-LLM entity/relation extraction → Leiden communities → community summaries → `local`/`global`/`neighbors` search), `mcp_server.py` (stdio MCP: `rag_search` / `rag_get_document` / `rag_neighbors` / `rag_stats`), `store.py` (corpus.sqlite manifest). Shell: `setup-venv.sh` (uv-provisioned CPython 3.12 venv), resumable `run-ingest.sh` / `run-graph.sh` / `build-all.sh`, `mcp-setup.sh` (Claude Code + Codex registration).
- **Fully local / private** — bge-m3 embeddings + ollama (gpt-oss / qwen / deepseek, via `/api/chat` with `think:low`) + LanceDB + local MCP. Only the optional open-access fetch touches the network. Self-contained: provisions its own venv and bundles an RAO-trace fallback; no hard dependency on the rest of the plugin. User-scoped store at `~/.claude/scholar-rag/` (`SCHOLAR_RAG_DIR`).
- **Integration** — GraphRAG seeds its entity graph from `scholar-knowledge` (concepts + citation edges). `scholar-lit-review` (Phase 1 full-text tier), `scholar-write` (evidence grounding), and `scholar-citation` (Step V-3.5 claim-verification retrieval by DOI) call `rag_search` when the index exists — citations still flow through the existing verification ladder / Verified Citation Pool. Extracted full text can also feed `/scholar-knowledge re-extract`.
- **Docs** — README skills table + counts (36 total), USAGE table row + Zotero-Integration note, `plugin.json` description. Passes `tests/smoke/test-all-skills-emit-trace.sh` (RAO-trace instrumentation present).

## [5.17.0] - 2026-07-04

### Bilingual documentation — Simplified Chinese README + USAGE, multi-agent positioning

- **`README.zh-CN.md` + `USAGE.zh-CN.md`:** full Simplified Chinese translations of the two user-facing docs (prose translated to academic-register 简体中文; commands, code blocks, file paths, skill names, BibTeX, and journal names kept in English; internal anchors re-slugged for the translated headings). Language-switcher links added at the top of all four files.
- **Codex / other-agents positioning:** new top-of-doc paragraph in both languages and both docs — the skills are plain-markdown instruction folders that OpenAI Codex and other coding agents can load (`~/.codex/skills` + natural-language invocation), with the data-safety guard traveling to the Codex host via the `/scholar-init`-installed adapter hook.

## [5.16.2] - 2026-07-04

### Data-guard fix — Bash tokenizer dropped the final token (fail-open) + metadata trues-up

- **`pretooluse-data-guard.sh`:** `_bash_tokenize`'s historical pass emitted its token stream WITHOUT a trailing newline, and the `while read` consumer drops a final unterminated line — so the LAST token of any unquoted command was never classified. Net effect: plain `cat data/raw/x.csv` (also `head`/`od`/`base64`/`env`-wrapper/`<`-redirection/row-`grep`) sailed through the Bash-channel speed-bump; quoted commands were unaffected (python-shlex branch prints with newlines, which is why `sed -n '1,5p' …` still denied). Fixed by terminating the stream (`printf '%s\n'`) and hardening the read loop (`|| [ -n "$tok" ]`). `test-pretooluse-guard.sh` 98/98 (was 91/7); `test-codex-data-guard.sh` 5/5 (T1 shared this root cause via the Codex adapter).
- **Agent-count metadata:** plugin.json description corrected to 20 agents (9 peer-reviewer + 6 code-review + 5 verification — `verify-claim-faithfulness` shipped in 5.16.0 without the metadata update); CLAUDE.md version/agents lines refreshed.
- **Stale bootstrap references removed:** `scholar-skill-bootstrap.sh` sourcing dropped from scholar-safety Step 5.1b and scholar-auto-research step 5b — the script is not shipped in this repo; the lines were `[ -f ]`-guarded no-ops.

## [5.16.1] - 2026-07-04

### Audit remediation — scholar-init / scholar-safety corrections + pandoc array propagation

Ported from the upstream dev audit of the data-safety skills. Fixes:

- **Qualitative-OVERRIDE classification drift (P1).** scholar-init's review matrix classified qualitative files by extension only while the PreToolUse guard refuses OVERRIDE by path-or-extension — the loop could offer `[D] OVERRIDE` for `interviews/*.txt` and then every Read was refused. Step 2.3(b) and Hard Rule 3 now mirror the guard's `is_qual_path` + text-extension rule.
- **Anonymizer output path (P1).** Docs re-scanned `ANON_<file>` "next to the original"; `anonymize-presidio.py` actually writes `${OUTPUT_ROOT:-output}/qual/anonymized/ANON_<basename>`. Also documented the exit-0-without-output "No PII detected" branch.
- **eval-pandoc array propagation (P1).** The array/no-eval pandoc pattern (spaced-path + `$(…)`-injection safe) applied to `_shared/pandoc-multiformat.md` (canonical recipe), `_shared/version-check.md`, scholar-write, and scholar-polish; string `CITEPROC_FLAGS` replaced by the `CITEPROC_ARGS` array. Zero executable `eval pandoc` remains.
- **scholar-safety doc/robustness corrections (P2).** INTL markers SHARE/HILDA/Add Health matched case-sensitively (prose collisions like "income share" produced false 🔴); strict-tier redactor activation preconditions documented + Step 5.2 registration check; safety-scan exit-code claim corrected (1 = missing, 2 = unreadable); `resolve_safety_level` wiring claim corrected (PostToolUse redactor only); safety-log path unified to `${PROJ}/logs/` via `derive-proj.sh`; ZIP-scan PCRE fallback rewritten as a probe-branch (grep-count-capture bug class); fail-closed existence preamble moved ahead of Step 1.1.
- **scholar-init doc/robustness corrections (P2).** Bare `NEEDS_REVIEW` (no level suffix) now included in the review enumeration; `_safety_level` meta key excluded from MODE 4 status counts (+ level line printed); sidecar absolute-key notes in Steps 2.3(f)/3.2; HALTED-note schema clarification (annotated values are schema-invalid and fail the guard closed project-wide); anonymizer regex-fallback claim corrected (scanning falls back to regex; anonymization requires Presidio).

## [5.16.0] - 2026-07-02

### Data-safety stack — Codex-host enforcement + OS-enforced lockdown wall

Ports the full Codex data-safety feature from the dev repo (`open-scholar-skills`, branch `codex-host-data-safety`) to this release repo (`c051460`). Previously the data-safety stack assumed a **Claude Code** host: under a **Codex** host the PreToolUse guard was inert (Codex never reads `~/.claude/settings.json`), and the `AGENTS.md` written for Codex projects *falsely* claimed the Claude hook protected the session.

- **Codex PreToolUse guard.** `scripts/gates/codex-pretooluse-hook.sh` (delegates to the same `pretooluse-data-guard.sh`) + `scripts/phases/setup-codex-hooks.sh`; installed by `/scholar-init` Step 1.2.5 and `/scholar-auto-research` Phase 0 for codex/unknown hosts.
- **Honest `AGENTS.md` prose.** A `{{ENFORCEMENT_BLOCK}}` token (lean template + per-target `render_auto_block` in `setup-project-claudemd.sh`): `AGENTS.md` no longer falsely claims the Claude PreToolUse hook protects a Codex session, and carries an actionable sidecar self-enforcement contract instead.
- **OS-lockdown wall.** `scripts/gates/generate-lockdown-config.sh` writes the per-host kernel read-deny (Claude `sandbox.filesystem.denyRead` / Codex `[permissions]` `"data"="deny"`, plus per-file denies for restricted sidecar files that live inside the workspace but outside `data/`), wired into `/scholar-safety` MODE 5 (Step 5.1b). Default is the hard wall (`allowUnsandboxedCommands:false`) — which also blocks the sanctioned LOCAL_MODE `Rscript` read, so run analysis before locking or pass `--allow-escalation` for a human-approved escape hatch.
- **Docs.** `data-handling-policy` §9, CLAUDE.md, README, USAGE updated (lockdown "not yet shipped" → shipped). *(This release also completes the README fix the port commit missed — the "Coming next: an OS-level sandbox" / "until the `lockdown` sandbox ships" text that still contradicted the now-shipped feature.)*

Validated in this repo: `test-codex-data-guard` 5/0, `test-setup-codex-hooks` 5/0, `test-generate-lockdown-config` 9/0, `test-setup-project-claudemd` 11/0. Deviations from the dev repo: safety-level is MODE 5 here (Step 5.1b, not 6); lean template only (no full template in this release). The dev-repo source is live-verified against codex 0.142.5 + Claude Code 2.1.197.

## [5.15.0] - 2026-06-13

Ports `scholar-simulate` from upstream `open-scholar-skills` (private), reviewed and confirmed free of project-specific and personal data, with its dev-only bootstrap shim removed in favor of this fork's `${SCHOLAR_SKILL_DIR:-.}` convention. **LLM-powered social simulation is a research instrument, not a substitute for human data.** The skill enforces this in its own contract: simulated respondents (silicon sampling, generative agents) may only support a publishable claim *after* fidelity validation against real human data — the skill treats an unvalidated simulated result as inadmissible, not as evidence. Use it to prototype designs, stress-test theory, and bound expectations; do not report its outputs as findings about people without the human-data check.

### Added

**New skill: `scholar-simulate`** (34 skills total)

- **`.claude/skills/scholar-simulate/SKILL.md`** — LLM-powered social simulation at scale across paradigms: silicon sampling (LLMs as survey respondents), generative agent-based models, survey/vignette/conjoint experiments, and opinion-dynamics simulation. Modes: `design`, `personas`, `silicon-survey`, `generative-abm`, `experiment`, `interactive`, `validate`, `calibrate`, `run`, `report`.
- **Ships a real execution engine** under `assets/` (not in-context snippets): `simulate_engine.py`, `providers.py` (multi-provider — Anthropic / OpenAI / open-source / local), `personas.py`, `interactive_runner.py`, and `validate.py`, scaling from dozens to hundreds of thousands of agent-calls via managed Batch APIs and local async concurrency. JSON schemas (`assets/schema/`) for personas, items, responses, and run manifests.
- **Mandatory human-data fidelity validation.** `validate.py` and the validation/calibration modes compare simulated distributions against human reference data before any result is treated as publishable; the contract forbids reporting unvalidated simulated output as a finding.
- **10 reference files** (`references/`): silicon-sampling, generative-abm, persona-construction, paradigms, providers, scale-engine, validation-fidelity, dynamic-orchestration, interactive-multiagent, reporting-templates.
- Cross-references existing skills (`scholar-citation`, `scholar-causal`, `scholar-analyze`, `scholar-compute`, `scholar-monitor`) and `_shared/data-handling-policy.md` — all resolve in this fork.

## [5.14.0] - 2026-06-10

Ports `scholar-auto-research` from upstream `open-scholar-skills` (private), scrubbed of all project-specific and personal data and adapted for this fork's researcher-in-the-loop philosophy. **This release adds an end-to-end pipeline, but it is not autonomous research, and we do not endorse using it as such.** Unlike the deliberately-absent `scholar-full-paper` orchestrator, `scholar-auto-research` is *stable and deterministic*: it ships a mandatory human-in-the-loop mode that stops for explicit researcher approval between phases, gates every phase with auditable deterministic checks rather than loose advisory passes, and forbids helper scripts from substituting for the specialist skills that do the substantive scholarly work. We encourage running it in human-in-the-loop mode — and, when it is run autonomously, holding every output to the same independent-verification standard the README's [Ethical Use](README.md#ethical-use-of-ai-in-academic-research) section requires. The researcher remains the author of the question, the argument, and every interpretation.

### Added

**New skill: `scholar-auto-research`**

- **`.claude/skills/scholar-auto-research/SKILL.md`** — a 21-phase pipeline (safety → research question → literature/theory → design → data/measurement → analysis plan → pre-execution review → premortem → execution → post-execution review → runtime sanity → results lock → blueprint → draft → verify → citation → ethics/open science → replication → quality gate → final assembly → submission hygiene). Two persistent run modes — `autonomous` and `human-in-loop` — with the Phase 0 prompt asking which; the default does not infer autonomous mode from silence.
- **Self-contained.** Bundles its own state machine (`scripts/auto-research-state.sh`), verifier (`scripts/auto-research-verify.sh`), gate scripts (`scripts/gates/`), and contracts (`references/*-contract.md`) under the skill directory, with no dependency on the parent `scripts/gates/`.
- **Deterministic, auditable gates** at each phase: results lock with a SHA-256 manifest, citation-metadata verification against CrossRef, rendered-references-against-bib checks, four-agent manuscript verification, and a journal-calibrated quality review — enforced by scripts, not prose.
- **Quality over compliance** is baked in: passing contracts, hashes, and manifests is a floor, not the goal. `scholar-write` remains the prose engine and `scholar-citation` the citation engine; a phase that can only be passed by weakening scholarly quality or bypassing the intended skill is treated as a workflow failure.

**Sensitive-data scrub (dev → public)**

- All upstream audit-provenance comments were generalized: real (unpublished) project slugs, local filesystem paths, project-specific variable names, a contributor's real name, and the specific citations from a private manuscript were replaced with neutral "Rationale:" explanations that preserve *why* each gate exists without exposing private research. Gate logic is unchanged; the full validation suite (contract lint, the 21-phase fixture test, the publication-quality fixture test, and the four bundled smoke tests) passes.

### Changed

- Skill counts updated across `README.md`, `CLAUDE.md`, and `.claude-plugin/plugin.json` to 32 scholar skills + 1 utility = 33 total. README's "Note on the Full-Paper Orchestrator" now explains why `scholar-auto-research` is included despite the no-black-box-orchestrator stance.

## [5.13.0] - 2026-05-31

Updates `scholar-init` from upstream `open-scholar-skills` (private), adapted for this fork's modular, researcher-in-the-loop philosophy. Two features land: an auto-managed project memory file and a scaffold-first init flow. The upstream bootstrap infrastructure (the P2-R `scholar-skill-bootstrap.sh` stanzas and the full-paper "upgrade" path) was deliberately **not** ported — it depends on orchestrator-only scripts this fork does not ship, and there is no full-paper orchestrator here.

### Added

**Auto-managed project memory file (`/scholar-init` Step 1.2.5)**

- **`scripts/phases/setup-project-claudemd.sh`** — writes/refreshes an auto-managed cross-skill rules block in each project's `CLAUDE.md` (Claude Code) or `AGENTS.md` (Codex, via the [agents.md](https://agents.md) cross-tool standard). The block auto-loads in every future session in the project directory, so standalone skill invocations (`/scholar-eda`, `/scholar-analyze`, `/scholar-write`, `/scholar-respond`, …) inherit the cross-skill rules — exactly the "run each skill individually, stay in the loop" use case this fork is built for. Idempotent (byte-stable re-run = no-op) and non-destructive (preserves content outside the marker block, including anything from Claude Code's built-in `/init`). Reads `.claude/safety-status.json` to conditionally inject a CFPS LOCAL_MODE data-handling block.
  - Ships **only** the lean profile — the complete, terminal cross-skill contract. There is no "full" profile to upgrade to (this fork has no full-paper orchestrator). The marker namespace is `open-scholar-skill:` (not the upstream `scholar-full-paper:`).
- **`scripts/templates/claudemd-auto-rules-lean.md`** — the lean block: no-destructive-regex rule, Objectivity Mandate, data-safety/LOCAL_MODE scope, citation rules, cross-skill workflow rules.
- **`scripts/detect-host-agent.sh`** — detects the host AI tool (Claude Code → `CLAUDE.md`; Codex → `AGENTS.md`; unknown → both). Override for tests: `SCHOLAR_HOST_AGENT_OVERRIDE`.
- **`.claude/skills/_shared/objectivity-mandate.md`** — the canonical anti-sycophancy / scientific-objectivity rule referenced by the lean block.

**Scaffold-first init (slug-only invocation)**

- `scripts/init-project.sh` gains a **`--scaffold`** flag: `/scholar-init <slug>` with no file paths now stands up the empty standard layout (`data/raw`, `data/interim`, `data/processed`, `materials`, `output`, `logs`, `.claude` with an empty `{}` sidecar, plus `README.md`, `.gitignore`, `logs/init-report.md`) and then prompts the user to point at their data and materials, ingesting them via the `add` flow. Lets researchers create the skeleton first and bring data later. `--scaffold` rejects input files (use the normal path to ingest); a slug-only invocation without `--scaffold` still errors as before.

**Tests**

- `tests/smoke/test-setup-project-claudemd.sh` (11 cases) and 6 new cases in `tests/smoke/test-init-project.sh` covering `--scaffold` and the slug-only path.

### Fixed

- `scripts/init-project.sh` README template and header comments no longer reference the (deliberately absent) `scholar-full-paper` orchestrator, and the plural "Open-scholar-skills" was corrected to "Open Scholar Skill".

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
