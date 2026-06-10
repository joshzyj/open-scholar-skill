# scholar-auto-research Workflow Contract — v1

This block is **auto-managed** by `scholar-auto-research` Phase 0 via `scripts/setup-project-claudemd.sh`. Do not edit content between the BEGIN/END markers — your edits will be overwritten on the next pipeline run. Add your project-specific content OUTSIDE the markers.

---

## Principles (load-bearing — read first)

### Quality over speed

scholar-auto-research is optimized for producing a publishable, high-quality social-science paper, not for completing the pipeline quickly. Every phase exists to surface defects EARLY — unsupported claims, fabricated citations, malformed manuscripts, broken prereq chains — rather than to push through to a submission packet. When a phase fails verification, the correct response is to **route back to the earliest affected phase and fix the root cause** — not to weaken the gate, fabricate the JSON, or rerun the same phase until it accidentally passes.

### No content fabrication

This is non-negotiable. Concrete prohibitions:

- **No invented citations.** Every `@bibkey` in the manuscript must correspond to a real `@entry` in `literature/references.bib`, AND the cited paper must actually exist. Phase 15 cross-checks bib metadata against CrossRef (`verify-citation-metadata.sh`), the rendered `## References` section against the bib (`verify-rendered-references-against-bib.sh`), and the bib against the operator's local Zotero (`verify-citation-local-library.sh`). LLMs fill missing fields (first names, issue numbers, page ranges, coauthors) from plausibility distributions; the gates catch this. **Never** hand-author a `@entry` from in-memory recall — route through `/scholar-citation materialize` (canonical-source-driven).
- **No invented data, findings, results, or statistics.** Every numerical claim in the manuscript must trace to a producing script and a recorded value in the analytic outputs. If a number doesn't appear in `analysis/` or `results/`, it doesn't appear in the manuscript.
- **No invented quotations.** If a paragraph claims a paper "argues X," that argument must be present in the cited source's body, not paraphrased from the title or inferred from the journal name.
- **No invented coauthors.** Real-paper-with-wrong-coauthor is the most common fabrication shape (Chen+Liu when actual is Chen+Tong; Bumpass+Sweet's third coauthor dropped). Phase 15 cross-checks use set-equality on normalized surnames.
- **No hand-crafted JSON to satisfy verifiers.** If a phase verify fails on JSON shape, fix by invoking the source skill that produces the artifact (`scholar-citation` for Phase 15, `scholar-write` for Phase 13, `scholar-ethics` for Phase 16), not by hand-editing the JSON. Fabricated JSON is detectable — Phase 15's gate cross-check exists for exactly this case.

### No sycophancy

- **Do not agree with the user when they are wrong.** If the user proposes an analytic decision that would weaken the paper — selecting a different specification because it yields a more favorable result, dropping a robustness check that surfaced a contradiction, softening a limitation that the design genuinely has — say so directly and offer the rigorous alternative.
- **Do not inflate the contribution.** The Discussion section should claim only what the design supports. Sample limitations, identification limitations, generalizability limitations get stated plainly, not buried under hedges or relocated to an appendix.
- **Do not pad sections to look thorough.** Length is a side-effect of substance, not the goal. Brevity that engages every required point beats verbosity that recycles the same observation.
- **Do not suppress methodological concerns.** When Phase 14 (manuscript verification), Phase 18 (quality gates), or any peer-reviewer-style audit flags a serious issue, surface it as a CRITICAL finding with `required_fix` — never downgrade severity without an explicit operator decision recorded in the verdict.
- **Do not flatter the user's prior decisions.** If a Phase 5 design choice produces a Phase 14 problem, the right move is to route back to Phase 5 and revise — not to defend the original choice because it's already been made.

### Factual honesty about your own state

- **Do not fabricate file paths, function names, line numbers, citations, or claims that artifacts exist, run, or are done.** Before claiming X works / exists / is done, run the check — do not infer from naming. When you haven't verified, say "I haven't checked — verifying now" and verify.
- **When the answer is unknown, say "I don't know"** and either look it up or stop. Confabulating around a gap is the most common LLM failure mode auto-research's Phase 14 / 15 / 18 gates exist to surface.
- **Task completion requires the artifact present and the gate passing.** Partial work is partial; report it as partial. Hand-edited JSON that exists but was fabricated to satisfy a verifier is NOT completion — Phase 15's gate cross-check tests for exactly this case (see "No hand-crafted JSON" above).
- **Memory claims are claims, not facts.** A memory entry that names a function / file / flag is a claim that needs verification against the current code before you recommend acting on it.

---

## Phase 0 — Initialization contract

Phase 0 must complete, in order:

1. **Safety scan.** Run `scholar-init` and resolve every `NEEDS_REVIEW` / `HALTED` status in `.claude/safety-status.json` before proceeding. If any file remains unresolved, stop and run `scholar-init review`.
2. **Run-mode selection.** Set `autonomous` or `human-in-the-loop` mode in `.auto-research/state.json`. The mode persists across sessions.
3. **Auto-managed CLAUDE.md refresh** (this block — invoked by `bash "${SCHOLAR_SKILL_DIR}/skills/scholar-auto-research/scripts/setup-project-claudemd.sh" "$PROJ"`).
4. **Verification:** `auto-research-verify.sh 0 "$PROJ"` confirms safety, run mode, and CLAUDE.md marker block are all in place.

Do not begin Phase 1 until Phase 0 verification passes.

---

## Run mode persistence

Before asking the operator for any confirmation, read `.auto-research/state.json`'s `run_mode` field:

- **Autonomous:** proceed without confirmation for routine decisions (phase advancement, gate-clean outputs, expected route-backs). Continue surfacing destructive actions (file deletion, force-completing past failing gates, modifying shared state) for confirmation regardless of mode.
- **Human-in-the-loop:** surface choices at each phase boundary; do not advance phases without operator approval.

Re-asking the operator to set the run mode at every phase is friction. If the mode is already recorded, honor it.

---

## Self-contained vendoring contract

scholar-auto-research is self-contained: every verifier gate is vendored under `scripts/gates/` (33+ gates as of v1). Do NOT introduce runtime dependencies on `scholar-skill/scripts/gates/` from inside this skill.

Three citation gates (`verify-citation-metadata.sh`, `verify-rendered-references-against-bib.sh`, `verify-citation-local-library.sh`) are vendored from the plugin layer at `scholar-skill/scripts/gates/`. When those plugin sources update, re-sync the vendored copies — drift can be detected by SHA comparison. The fallback flag `AUTO_RESEARCH_ALLOW_ROOT_GATE_FALLBACK=1` is for legacy debugging only; do not enable it in production runs.

---

## Phase 15 gate cross-check + skip-flag

Phase 15 verify, after the `citation/citation-audit.json` JSON-shape validation, runs three vendored citation gates as a cross-check against the JSON's declared PASS verdict:

- **RED** from any gate fails the verify (closes the trust-based loophole where a fabricated `citation-audit.json` declares the right `fabrication_guard: true` flags without actually invoking scholar-citation).
- **YELLOW** (gate cannot run — network down, no Zotero installed) does NOT contradict the JSON; an unavailable gate is informational, not a counterexample.

The skip-flag `SCHOLAR_AUTO_RESEARCH_SKIP_GATE_RECHECK=1` exists only for fixture tests that exercise the JSON-shape contract in isolation. Do not set it for real verification runs — it disables the structural defense against citation fabrication.

---

## Prereq chain integrity

Phase verifiers recursively re-check prereqs (Phase 15 → 14 → 13 → … → 0). There is NO skip flag for the prereq chain by design. To test a single phase in isolation, build complete upstream artifacts (see `auto-research-fixture-test.sh` for the canonical recipe). Never patch the verifier to disable the chain, and never synthesize a prereq's outputs by hand to bypass a failing upstream verify — fix the prereq first.

---

## JSON-shape contracts are strict

Phase artifacts (`citation-audit.json`, `manuscript-verification.json`, `ethics-open-science.json`, etc.) must satisfy strict JSON-shape validators with 20+ field checks per phase (`citation_engine.skill`, `source_hashes`, `bibliography_provenance`, `selected_manuscript_hash`, …). If a phase verify fails on shape, the fix is to invoke the source skill that produces the artifact (`scholar-citation` for Phase 15, `scholar-write` for Phase 13, `scholar-ethics` for Phase 16, `scholar-replication` for Phase 17) — not to hand-craft the JSON. Hand-crafted JSON is fabrication, and Phase 15's gate cross-check detects it.

---

## Codex trigger defaults

Phases 6 and 14 invoke a codex-trigger gate (cross-model review) that defaults to STRONG (RED if no codex review is dispatched). The fixture suite sets `SCHOLAR_CODEX_DEFAULT=false` to skip this gate; real runs must dispatch the codex agent. Setting the flag in production silently weakens Phase 6 + Phase 14 quality checks.

---

## When auditing or editing the skill — read the live plugin path

When auditing scholar-auto-research / open-scholar-skills, always read from the live plugin path:

```
~/.claude/plugins/marketplaces/scholar-marketplace/plugins/scholar-skill/skills/scholar-auto-research/
```

This is a symlink to the Drive dev tree (`open-scholar-skills/`). The `cache/` copy is stale. Verify version via the live `package.json`.

---

*Auto-generated by `scholar-auto-research` Phase 0 — v1 — 2026-05-25. To bump rule contents: edit `skills/scholar-auto-research/scripts/templates/claudemd-auto-rules.md` and re-run `bash scripts/setup-project-claudemd.sh "$PROJ"` — existing project CLAUDE.md files will be refreshed on next pipeline run, with user content outside the markers preserved verbatim.*
