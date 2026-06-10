---
name: scholar-auto-research
description: "Stable, deterministic social-science research-paper pipeline from idea or data to verified manuscript, citations, replication package, and final md/docx/tex/pdf outputs. Use when the user wants a reliable end-to-end auto-research chain that avoids the evolving scholar-full-paper workflow."
tools: Read, Bash, WebSearch, WebFetch, Task, Write, Glob, Agent
argument-hint: "[research idea OR data/codebook paths | resume <project-dir> | verify <project-dir>]"
user-invocable: true
---

# Scholar Auto Research

Stable default pipeline for one defensible social-science paper. This skill is intentionally smaller than `scholar-full-paper`: no grants, presentations, resubmission, teaching, monitoring, or auto-improve in the default route.

## Operating Rule

## MUST FOLLOW RULE

The main goal of `scholar-auto-research` is to produce a publishable, high-quality paper for the target journal. Passing contracts, phases, manifests, and hashes is required, but those are means rather than the end.

Therefore:

- Do not treat contract compliance as success if the manuscript remains thin, generic, mechanically templated, poorly cited, weakly argued, or visually incomplete.
- Do not let deterministic builders, helper scripts, or manifest generators replace substantive scholarly work. They may package artifacts, enforce paths, render outputs, and record provenance, but they must not become the primary author of the paper's argument, literature synthesis, methods reasoning, discussion, or citation judgment.
- In Phase 13, `scholar-write` must remain the primary prose engine. If the workflow needs helpers, they must prepare governed inputs or package outputs, not substitute for real drafting.
- In Phase 15, `scholar-citation` must remain the primary citation and claim-support engine. If the workflow needs helpers, they must package inventories or manifests, not substitute for source verification, claim checking, or bibliography judgment.
- If a phase can be passed only by weakening scholarly quality, bypassing the intended skill, or generating low-value boilerplate, that is a workflow failure. Route back, revise the integration, or fail the project rather than shipping a poor paper.
- When a phase names a specialist skill, follow that skill's mandatory workflow rather than manually recreating its outputs. Output-shape compliance is not enough if the required search order, logging, verification, or handoff protocol was skipped.
- Phase 2 is a hard example: `scholar-lit-review-hypothesis` must run its local-library-first search protocol, maintain its search and process logs, and carry forward its source-integrity checks. Do not substitute ad hoc prior-project bibliographies, generic web-only searching, or hand-assembled citation pools for that workflow.

System-level publication-quality gates:

- Do not let any empirical secondary-data project pass without a dataset-design decision: weights, clustering/design variables, panel structure, sampling frame, and the accepted limitations of any simpler analysis must be explicit before analysis planning.
- Do not let bounded, skewed, zero-inflated, count, duration, or time-use outcomes pass with only one convenient headline estimator. Phase 5 must plan a defensible model ladder or explain why the outcome does not need one.
- Do not let high missingness, skip patterns, complete-case restrictions, or changing denominators pass as a table note. Phase 5 must plan post-restriction diagnostics and sensitivity checks before Phase 8 execution.
- Do not let literature review become citation inventory. Phase 15 must reject omnibus claim-source maps that attach most or all references to one generic background claim.
- Do not let peer review become ceremony. Phase 18 reviewer reports must be independently written, adversarial, manuscript-specific, and tied to concrete locations or artifacts.
- Do not let reader-facing manuscripts expose pipeline scaffolding. Locks, registries, manifests, phases, provenance mechanics, and audit language belong in trace artifacts unless the journal article itself is about the workflow.

Use the phase contract as the source of truth:

- Machine-readable contract: `references/phase-contract.json`
- Human guide: `references/phase-contract.md`
- Artifact rules: `references/artifact-contract.md`
- State rules: `references/state-contract.md`
- Skill routing rules: `references/skill-routing-contract.md`
- Research question rules: `references/research-question-contract.md`
- Literature and theory rules: `references/literature-theory-contract.md`
- Design rules: `references/design-contract.md`
- Data and measurement rules: `references/data-measurement-contract.md`
- Analysis plan rules: `references/analysis-plan-contract.md`
- Pre-execution review rules: `references/pre-execution-review-contract.md`
- Analysis premortem rules: `references/analysis-premortem-contract.md`
- Execution rules: `references/execution-contract.md`
- Post-execution review rules: `references/post-execution-review-contract.md`
- Runtime sanity rules: `references/runtime-sanity-contract.md`
- Results lock rules: `references/results-lock-contract.md`
- Manuscript drafting rules: `references/manuscript-drafting-contract.md`
- Verification rules: `references/verification-contract.md`
- Citation/claim rules: `references/citation-claim-contract.md`
- Ethics/open-science rules: `references/ethics-open-science-contract.md`
- Replication rules: `references/replication-contract.md`
- Manuscript quality rules: `references/quality-gate.md`
- Final assembly rules: `references/final-assembly-contract.md`
- Submission hygiene rules: `references/submission-hygiene-contract.md`

Do not infer completion from prose headings. A phase completes only when its required outputs exist, its structured verdict passes, and state is updated.

## Context Management

A full run spans 21 phases and accumulates many manifests, registries, reviewer reports, and locked artifacts. Because every decision is persisted to disk (state.json, manifests, locks), the conversation context can be cleared between phases without losing project state. After clearing, resume cold with `bash .claude/skills/scholar-auto-research/scripts/auto-research-state.sh next "$PROJ"`.

The state machine emits an advisory when the most recently completed phase is a context-rot seam. After running `next`, look for these lines in addition to `NEXT_PHASE`:

```
CONTEXT_CLEAR_RECOMMENDED=1
CONTEXT_CLEAR_REASON=<seam-specific reason>
```

Recommended `/clear` seams (5 total across 21 phases):

- After Phase 5 — planning epoch complete; Phase 6 spawns 6 independent code reviewers.
- After Phase 7 — premortem GO; Phase 8 execution will dump heavy command traces.
- After Phase 11 — results locked; Phase 12+ only need the lock manifest and Stage 1 verify.
- After Phase 14 — manuscript verified; Phases 15-18 audit independent dimensions.
- After Phase 18 — quality gate passed; Phases 19-20 are deterministic assembly and hygiene.

Do not clear inside Phase 6 or 7 fix-rereview loops, inside Phase 13 drafting passes, or during an active route-back rerun: those work best with continuity. Subagent reviewers in Phases 6, 7, 9, 14, and 18 already isolate their own context, so their dispatch does not by itself require a clear.

## Default Chain

0. Safety
1. Research Question
2. Literature and Theory
3. Design
4. Data and Measurement
5. Analysis Plan
6. Pre-Execution Review
7. Analysis Premortem
8. Execute Analysis
9. Post-Execution Review
10. Runtime Sanity
11. Results Lock
12. Manuscript Blueprint
13. Draft Manuscript
14. Verify Manuscript
15. Citation and Claim Support
16. Ethics and Open Science
17. Replication Package
18. Manuscript Quality Gate
19. Final Assembly
20. Submission Hygiene

The default route ends at Phase 20. Optional products must be requested explicitly and should use other scholar skills.

## Phase 0 Safety And Run Mode

Phase 0 initializes or resumes the project, verifies local data-safety status, and records whether the run is autonomous or human-in-the-loop. Do not begin Phase 1 until Phase 0 verification passes.

1. Parse the user's idea, data paths, target journal, method orientation, constraints, and requested run mode.
2. Create or locate a project directory under `output/<slug>/`.
3. Initialize project state before setting run mode.

If the project was initialized by `scholar-init`, import its safety sidecar:

```bash
bash .claude/skills/scholar-auto-research/scripts/auto-research-state.sh import-init "$PROJ"
```

This reads `$PROJ/.claude/safety-status.json`, writes `$PROJ/safety/safety-status.json`, and initializes `.auto-research/state.json` if needed. If any file still has `NEEDS_REVIEW` or `HALTED`, stop and run `scholar-init review` before completing Phase 0.

Bare `OVERRIDE` does not pass. Overrides must retain the scholar-init rationale, e.g. `OVERRIDE: public synthetic demo file`. If no files were scanned, the safety artifact must explicitly declare `no_data_declared: true`.

If the project was not initialized by `scholar-init`, initialize state:

```bash
bash .claude/skills/scholar-auto-research/scripts/auto-research-state.sh init "$PROJ"
```

Then produce `safety/safety-status.json` before attempting Phase 0 verification.

4. Before Phase 0 can be completed, set a persistent run mode. If the user has not already made the choice, ask: `Run scholar-auto-research in autonomous mode or human-in-the-loop step-by-step mode?`

Use autonomous mode when the user asks to proceed, continue, or finish without step-by-step review:

```bash
bash .claude/skills/scholar-auto-research/scripts/auto-research-state.sh set-mode "$PROJ" autonomous "user requested autonomous run"
```

Use human-in-the-loop mode when the user asks for step-by-step review, explicit approval, or decisions between phases:

```bash
bash .claude/skills/scholar-auto-research/scripts/auto-research-state.sh set-mode "$PROJ" human-in-loop "user requested phase-by-phase approval"
```

If `next` returns `NEXT_PHASE=MODE_SELECTION`, stop and get this choice before completing any phase. Do not infer autonomous mode from silence.

5. Refresh the project's auto-managed memory file (idempotent, non-destructive; auto-detects host AI tool):

```bash
bash .claude/skills/scholar-auto-research/scripts/setup-project-claudemd.sh "$PROJ"
```

This writes (or refreshes) the workflow-contract block — principles (quality, no-fabrication, no-sycophancy) plus auto-research-specific operational rules (run mode persistence, self-contained vendoring, Phase 15 cross-check, prereq-chain integrity, JSON-shape strictness, codex defaults) — inside the marker block `<!-- scholar-auto-research:BEGIN/END auto-rules v1 -->`. User content OUTSIDE the markers is preserved verbatim. The setup is idempotent — running twice produces a byte-identical file.

The target filename is chosen by the vendored `detect-host-agent.sh` helper (added 2026-05-28): Claude Code → `CLAUDE.md`; Codex → `AGENTS.md` ([agents.md](https://agents.md) cross-tool standard); unknown host → both files. Existing projects refresh whichever file is already present and do not backfill the other.

The script prints a one-time user-facing notice on CREATE / APPEND (full banner with the file path, a summary of what's in it, the auto-managed content for review, and a reminder that the operator can add content outside the markers) and a short banner on REFRESH / MIGRATE. NO-OP runs are silent. **Do not redirect this script's stdout to `/dev/null`** — the notice is intended for the operator to see on first invocation.

6. At the start of each turn, read next phase:

```bash
bash .claude/skills/scholar-auto-research/scripts/auto-research-state.sh next "$PROJ"
```

If `next` returns `APPROVAL_REQUIRED=1`, the project is in human-in-the-loop mode. Summarize the completed phase, name the proposed next phase, and ask the user for a decision before doing next-phase work. Valid decisions are `approve`, `revise`, `pause`, or `switch-autonomous`:

```bash
bash .claude/skills/scholar-auto-research/scripts/auto-research-state.sh decision "$PROJ" <next_phase> approve "user approved next phase"
```

Only `approve` or `switch-autonomous` clears the gate. `revise` and `pause` are recorded but keep the transition blocked.

7. After producing a phase's artifacts, verify then complete:

```bash
bash .claude/skills/scholar-auto-research/scripts/auto-research-verify.sh <phase_id> "$PROJ"
bash .claude/skills/scholar-auto-research/scripts/auto-research-state.sh complete "$PROJ" <phase_id> <artifact-paths...>
```

If verification fails or state completion fails, stop and report the blocker. Do not continue. In human-in-the-loop mode, successful completion of a phase creates a pending transition; do not start the next phase until `decision ... approve` has been recorded.

If a phase emits a structured `FAIL` report with `route_back_phase`, apply it to state before continuing:

```bash
bash .claude/skills/scholar-auto-research/scripts/auto-research-state.sh route-back "$PROJ" <fail-report-json>
bash .claude/skills/scholar-auto-research/scripts/auto-research-state.sh next "$PROJ"
```

Do not manually skip invalidated downstream phases. Rerun forward from the route-back target.

## Phase 1 Research Question Formation

Phase 1 formalizes the project question and target journal calibration. Read `references/research-question-contract.md` before running it.

Workflow:

1. Confirm Phase 0 safety passed.
2. Classify the input mode: `idea`, `data`, `materials`, or `paper`.
3. Invoke `scholar-idea` when the user provided a broad topic, puzzle, rough question, or theoretical interest.
4. Invoke `scholar-brainstorm` when the user provided data, codebooks, questionnaires, data dictionaries, a paper, an abstract, or other materials without a clear research question.
5. Generate at least three candidate research questions. Each candidate must include X, Y, mechanism, confounders, scope, claim strength, recommended dataset or data strategy, novelty risk, data feasibility, and fatal-flaw status.
6. Evaluate candidates with independent lenses for theory, methods/data fit, domain/literature gap, journal-editor fit, and devil's-advocate failure modes.
7. Select or infer a target journal or journal family. Record paper type, method bar, theory bar, fit rationale, desk-reject risks, and per-candidate journal fit.
8. Invoke `scholar-journal` at Phase 1 for journal calibration. `idea/journal-fit.json` must preserve a `journal_profile_resolution` record stating whether the profile is built-in, imported from a web-fetched custom journal, or an explicit fallback.
9. When the requested journal is outside the built-in journal catalog, try a web-backed imported journal profile first. If that fails, the explicit fallback profile is `ASR / American Sociological Review`, not a generic article shell.
   Use `scripts/emit-journal-profile-resolution.py` or `references/journal-profile-resolution-templates.json` for fallback metadata; do not hand-write fallback ASR `journal_structure` or `display_architecture` objects.
10. Refine the selected candidate after panel feedback. Do not select any candidate with a fatal flaw or infeasible data path.
11. Save `idea/candidate-rqs.json`, `idea/rq-evaluation-panel.json`, `idea/journal-fit.json`, `idea/rq-selection-rationale.md`, `idea/research-question.json`, and `idea/research-question.md`.
12. Run `auto-research-verify.sh 1 "$PROJ"`. Phase 2 may start only after the selected RQ, target journal, journal-profile resolution, and selection rationale pass.

Phase 1 must not perform the full literature review. Its job is to avoid choosing a bad question; Phase 2 builds the full literature and theory base.

## Phase 2 Literature And Theory

Phase 2 builds the journal-calibrated literature, theory, mechanism, and hypotheses for the selected Phase 1 question. Read `references/literature-theory-contract.md` before running it.

Workflow:

1. Confirm Phase 1 passed and load `idea/research-question.json` plus `idea/journal-fit.json`.
2. Invoke `scholar-lit-review-hypothesis` as the primary integrated engine. It must produce the literature landscape, gap statement, theory selection, mechanism chain, hypotheses, must-cite coverage, and target-journal calibration.
3. Preserve the specialist-skill protocol artifacts in canonical Phase 2 outputs: copy the integrated skill's search log to `literature/search-log.md`, write `literature/review-protocol.json`, and keep the process/source-integrity traces needed to prove the local-library-first workflow actually ran.
4. Build `literature/literature-coverage-matrix.json` with `engine_handoff`, coverage categories, must-cite coverage, mechanism chain, hypotheses, journal calibration, and `ready_for_phase_3: true`. Treat the Phase 2 `hypotheses` array as the ex ante canonical hypothesis set for all downstream design, analysis, drafting, and interpretation.
5. Export `literature/references.bib` with more than 30 verified BibTeX entries. Every must-cite work must be represented and marked covered.
6. Invoke `scholar-write` to draft or revise the formal `literature/lit-theory.md` section from the integrated review output. The writing pass must preserve verified citations, Phase 1 claim strength, mechanism, hypotheses, and target-journal expectations.
7. Write `literature/lit-theory-manifest.json` with `scholar-lit-review-hypothesis` and `scholar-write` engine metadata, protocol artifact paths, source hashes, output hashes, and `ready_for_phase_3: true`.
8. Run `auto-research-verify.sh 2 "$PROJ"`. Phase 3 may start only after the integrated review, protocol proof, writing handoff, coverage matrix, and bibliography pass.

Do not hand-author a generic literature memo. Phase 2 must be both review-driven and write-polished. If the literature package cannot prove the named specialist workflow was followed, Phase 2 fails even if the prose and bibliography look plausible.

## Phase 3 Design

Phase 3 turns the selected question and integrated literature/theory into a design that Phase 4 can operationalize. Read `references/design-contract.md` before running it.

Workflow:

1. Confirm Phase 2 passed and load `idea/research-question.json`, `idea/journal-fit.json`, `literature/lit-theory.md`, `literature/lit-theory-manifest.json`, and `literature/literature-coverage-matrix.json`.
2. Invoke `scholar-design` as the primary engine. The design must inherit the Phase 1 target journal, paper type, method bar, and claim strength, plus the Phase 2 mechanism chain and hypotheses.
3. Route the project through the correct specialist method skill before finalizing the design. Computational projects must invoke `scholar-compute`; qualitative projects must invoke `scholar-qual`; linguistic projects must invoke `scholar-ling`; mixed-methods projects must record a primary execution skill plus supporting specialist skills. Quantitative observational/demographic projects may stay on the default `scholar-analyze` route.
4. If the design makes causal or quasi-causal claims, or uses DiD, fixed effects for identification, RD, IV, matching/reweighting, mediation, synthetic control, DML/causal forests, or related strategies, invoke `scholar-causal` before finalizing the design.
5. Write `design/design-blueprint.md`, including a literal `outcome_mechanism_alignment: <class>` line where the class is `entry-process`, `prevalence-stock`, `dissolution`, or `multi-state`.
6. Write `design/identification-strategy.json` with claim strength, estimand, identification strategy, assumptions, X/Y measures, journal method bar, hypothesis-model coverage, feasibility or power assessment, causal gate, method-specialist routing, threats, and robustness plan.
7. Write `design/model-specs.json`. Every Phase 2 hypothesis must appear in at least one model's `hypothesis_ids`, unless the design records an accepted unmodeled limitation.
8. Evaluate the design with independent lenses for identification, measurement, theory/mechanism, feasibility/data, and journal skepticism. Fix critical issues inside Phase 3 and record the revision loop.
9. Write `design/design-manifest.json` with `scholar-design` metadata, conditional `scholar-causal` metadata, method-specialist engine metadata, source hashes, output hashes, target journal, claim strength, design-to-writing continuity matrices (`claim_continuity`, `mechanism_result_matrix`, `robustness_claim_matrix`, `limitation_scope_matrix`), and `ready_for_phase_4: true`.
10. Run `auto-research-verify.sh 3 "$PROJ"`. Phase 4 may start only after the design, evaluation, revision log, routing plan, and manifest pass.

Do not let a generic methods memo pass as a design. Phase 3 must prove that the design is journal-calibrated, hypothesis-linked, feasible, and strong enough for the claim.

## Phase 4 Data And Measurement

Phase 4 turns the hardened design into a data and measurement plan. Read `references/data-measurement-contract.md` before running it.

Workflow:

1. Confirm Phase 3 passed and load `safety/safety-status.json`, `design/design-blueprint.md`, `design/design-manifest.json`, `design/identification-strategy.json`, and `design/model-specs.json`.
2. Invoke `scholar-data` as the data and measurement engine. Use it to verify dataset fit, access path, IRB implications, variable availability, sample feasibility, data security, and sharing constraints.
3. Write `data/data-status.json` with data status, access status, IRB status, source type, concrete file/provenance entries, and dataset fit.
4. Write `data/variable-dictionary.csv`. It must cover every Phase 3 X/Y measure and every outcome, predictor, and covariate used in `design/model-specs.json`; each row must state design source, missing-value handling, post-treatment status, measurement quality, and reader-facing translation fields (`display_label`, `table_stub_label`, `manuscript_term`, `levels_display`).
5. Write `data/measurement-plan.md` with measurement validity, missing data handling, sample restrictions, data provenance, access/IRB implications, security, sharing constraints, dataset fit, model-variable coverage, and post-treatment-control review.
6. Write `data/data-measurement-manifest.json` with `scholar-data` metadata, Phase 3 and safety source hashes, output hashes, dataset-fit verdict, variable coverage, safety provenance, post-treatment review, and `ready_for_phase_5: true`.
7. Run `auto-research-verify.sh 4 "$PROJ"`. Phase 5 may start only after data status, variable coverage, measurement plan, safety provenance, and the manifest pass.

Do not let Phase 4 pass with vague dataset promises. If data access, IRB, key variables, sample feasibility, or post-treatment-control status are unresolved, keep the project in Phase 4 or route back to Phase 3 if the design must change.

## Phase 5 Analysis Plan

Phase 5 turns the design and measurement plan into an executable analysis plan without executing it. Read `references/analysis-plan-contract.md` before running it.

Workflow:

1. Confirm Phase 4 passed and load `design/design-manifest.json`, `design/identification-strategy.json`, `design/model-specs.json`, `data/variable-dictionary.csv`, `data/data-measurement-manifest.json`, and `data/measurement-plan.md`.
2. Use `scholar-auto-research`'s internal `analysis_plan_compiler`. Do not invoke `scholar-analyze`, load raw data, estimate models, generate tables, or produce figures in Phase 5.
3. Write `analysis/spec-registry.csv`. Every Phase 3 model and every Phase 3 hypothesis must have at least one planned `spec_id`; every spec variable must appear in the Phase 4 variable dictionary.
4. Write `analysis/scripts-inventory.json` with planned scripts, script order, dependency graph, expected inputs/outputs, and planned tests. Every script and test must remain `planned`.
5. Write `analysis/analysis-plan.md` explaining model sequence, hypothesis/spec mapping, robustness checks, missing-data strategy, variable-construction plan, script/test inventory, no-execution boundary, and Phase 6 pre-execution review handoff.
6. Write `analysis/analysis-plan-manifest.json` with `scholar-auto-research` / `analysis_plan_compiler` metadata, source hashes, output hashes, model/spec/hypothesis coverage, variable coverage, robustness coverage, missing-data alignment, script DAG validation, test coverage, and `ready_for_phase_6: true`.
7. Control variables in regressions are enforced at two design-aware layers, both keyed on `method_specialist_routing.primary_execution_skill`. Layer 1 (in `auto-research-verify.sh`): every spec-registry row's required columns must be non-empty, but the `covariates` column is skipped when the resolver helper (`scripts/gates/_phase5-skill-resolver.sh`) reports `primary_execution_skill ∈ {scholar-compute, scholar-qual, scholar-ling}`. Layer 2 (`scripts/gates/control-variables-check.sh`): non-regression families return GREEN N/A; regression family (`scholar-analyze`) requires ≥1 spec with controls, with RCT/DAG refinements via free-form `design_type` pattern match. Opt out per-phase by adding `[EXCUSED:control-variables: <reason>]` to `analysis/analysis-plan.md` (suppresses Layer 2 only — Layer 1 still applies).
8. Run `auto-research-verify.sh 5 "$PROJ"`. Phase 6 may start only after planned specs, scripts, tests, coverage, hashes, control-variable enforcement, and the no-execution boundary pass.

Do not allow generic script lists. Phase 5 must make the planned analysis reviewable enough that Phase 6 can audit exact scripts, exact specs, exact tests, and exact design promises before execution.

## Phase 6 Fixing Function

Phase 6 is an active review-fix-rereview loop, not a passive report. Read `references/pre-execution-review-contract.md` before running it.

Workflow:

1. Load `analysis/analysis-plan.md`, `analysis/analysis-plan-manifest.json`, `analysis/scripts-inventory.json`, `analysis/spec-registry.csv`, `design/identification-strategy.json`, `design/model-specs.json`, `data/variable-dictionary.csv`, and `data/data-measurement-manifest.json`.
2. Invoke `scholar-code-review` in `pre_execution_planned` mode.
3. Spawn independent reviewers for `correctness`, `robustness`, `statistical`, `reproducibility`, `style_ai_patterns`, and `data_handling`. Each reviewer must inspect every planned script, every planned test, every planned spec, the script DAG, Phase 5 coverage fields, and the upstream design/data artifacts.
4. Save each reviewer report under `review/agents/` and record its `reviewer_id`, `agent_type`, `task_invocation_id`, reviewed scripts/specs/tests/upstream artifacts, findings, and verdict.
5. If any reviewer finds a blocker, critical issue, major issue, stale inventory, unreviewed script/test/spec, unsafe data handling, missing DAG coverage, missing robustness coverage, missing no-execution proof, or impossible execution path, fix it inside Phase 6. Do not defer it to Phase 7 or Phase 8.
6. Record every same-phase fix in `review/pre-execution-fix-log.json` and `review/pre-execution-fix-log.md`.
7. Run an independent re-review of every fixed finding. Re-review may reuse the same role but must produce a separate `review/pre-execution-rereview.json`.
8. Write the final `review/pre-execution-review.json` only after blockers are resolved. Its final verdict must be `PASS`, `degraded: false`, `review_engine.skill: scholar-code-review`, `review_engine.mode: pre_execution_planned`, `blocking_findings: []`, and `ready_for_phase_7: true`.
9. Codex cross-model review (mandatory by default). The Phase 6 verifier runs `scripts/gates/codex-trigger-phase6.sh`, which requires Codex code-mode artifacts under `${PROJ}/reviews/codex/A[1-3]-*.md` whenever `SCHOLAR_CODEX_DEFAULT=true` (the default) AND the `codex` CLI is on PATH. Dispatch via `/scholar-openai code <manuscript-path> <scripts-dir>`. To opt out, either set `SCHOLAR_CODEX_DEFAULT=false` at the shell level OR add `[EXCUSED:codex-review: <reason>]` to `review/pre-execution-review.md` (or to a string field in the .json). If the `codex` CLI is missing, the gate emits YELLOW (cannot fire) rather than RED.
10. Run `auto-research-verify.sh 6 "$PROJ"`. Complete Phase 6 only if verification passes.

If fixes require changing `analysis/scripts-inventory.json`, recompute and record the new inventory hash after the changes. If fixes change the research design, data plan, or analysis plan rather than just the planned scripts/tests, route back to the earliest affected phase instead of papering over the mismatch in Phase 6.

## Phase 7 Analysis Premortem

Phase 7 is the last design-risk gate before execution. Read `references/analysis-premortem-contract.md` before running it.

Workflow:

1. Confirm Phase 6 final review and re-review both passed and `ready_for_phase_7` is true.
2. Invoke the routed specialist premortem engine from Phase 3 `method_specialist_routing`. Default quantitative projects use `scholar-analyze`; computational projects use `scholar-compute`; qualitative projects use `scholar-qual`; linguistic projects use `scholar-ling`. Record the selected skill in `premortem_engine.skill`, `mode: premortem`, `auto_research_contract: phase_7`, and `skip_premortem_ignored: true`.
3. Spawn independent premortem reviewers for `identification`, `measurement_missingness`, `model_robustness`, and `interpretation_claims`. Use real peer-reviewer style provenance: reviewer id, role, agent name, task invocation id, dispatch timestamp, model id, and report path.
4. Each reviewer must stress-test Phase 3 design artifacts, Phase 4 measurement artifacts, `analysis/analysis-plan.md`, `analysis/spec-registry.csv`, `analysis/scripts-inventory.json`, and Phase 6 review artifacts.
5. Build a traffic-light summary covering identification, variable construction, sample restrictions, model specification, standard errors, missing data, robustness, power/effect-size realism, heterogeneity/multi-comparison policy, mechanism evidence, table/figure plan, preregistration/deviation alignment, and interpretive reach.
6. Build a null-falsification table for every hypothesis id represented in `analysis/spec-registry.csv`; every hypothesis needs an observable null pattern, precommitment status, and planned interpretation rule.
7. Build a risk register covering red/major risks, mitigations, accepted limitations, and execution decision rules. For estimator/specification/reporting mitigations, add a reporting-depth checklist naming diagnostic outputs, sensitivity range, failure-mode disclosure, and reporting location.
8. Fix red, major, critical, high, or blocker items before Phase 8, unless the correction belongs to an earlier phase. If so, route back to that phase and do not mark Phase 7 complete. Iteration 3 with unresolved red/high/major/critical/blocker risk halts for human decision.
9. Save `review/analysis-premortem-fix-log.json`, `review/analysis-premortem.json`, and `review/analysis-premortem.md`.
10. Run `auto-research-verify.sh 7 "$PROJ"`. Phase 8 may start only when the Phase 7 decision is `GO`.

## Phase 8 Execute Analysis

Phase 8 executes only the approved Phase 7 handoff. Read `references/execution-contract.md` before running it.

Workflow:

1. Confirm Phase 7 premortem passed, `go_no_go.decision` is `GO`, and `ready_for_phase_8` is true.
2. Invoke the routed specialist execution engine from Phase 3 `method_specialist_routing`. Default quantitative projects use `scholar-analyze`; computational projects use `scholar-compute`; qualitative projects use `scholar-qual`; linguistic projects use `scholar-ling`. Record the selected skill in `execution_engine.skill`, `mode: execute_analysis`, `auto_research_contract: phase_8`, and `phase7_handoff_only: true`.
For `scholar-analyze`-routed quantitative work, inherit the stronger full-paper defaults unless the execution report records a justified exception: use `R` as the primary execution language, `modelsummary` for regression-table export, `ggplot2` for figures, and `marginaleffects` when nonlinear probability models are central to the paper. Before execution, copy this skill's bundled canonical `references/viz_setting.R` into the project as `analysis/scripts/viz_setting.R`; do not author a local replacement or simplified style file. Use that copied file plus `theme_Publication()` for shared ggplot styling, and record `analysis_stack.viz_style_source: analysis/scripts/viz_setting.R`, `analysis_stack.viz_style_reference: references/viz_setting.R`, and the canonical `analysis_stack.viz_style_sha256` in `analysis/execution-report.json`. Use the Phase 4 variable dictionary as the authoritative source for reader-facing labels in tables, figures, captions, and manuscript prose.
3. Before running any script, verify that Phase 7 source hashes still match the current analysis plan, spec registry, scripts inventory, and premortem fix log. Route back if they drifted.
4. Run scripts exactly in `review/analysis-premortem.json.phase8_handoff.script_order`.
5. Record run context, command trace, every command, script hash, exit code, output, test, and halt check in `analysis/execution-report.json`.
6. Write `tables/results-registry.csv` with one row for every planned `spec_id` in `analysis/spec-registry.csv`.
7. For quantitative empirical work, write at least one canonical publication regression table under `tables/` and register it as `main_regression_table` or `regression_table`. The table must preserve the original regression-table shape with model columns and predictor rows; a result registry, model ladder, or focal-coefficient extract is not a publication table.
8. Write `figures/figure-registry.csv` for every produced figure or an explicit no-figure row if none are planned.
9. Write an `artifact_manifest` in `analysis/execution-report.json` covering every produced Phase 8 table, figure, model output, diagnostic, and intermediate output with path, role, producer, registration status, and hash.
10. Halt immediately on nonzero exit codes, missing expected outputs, failed tests, stale hashes, Phase 7 source drift, unregistered result specs, unregistered table artifacts, or unregistered figure artifacts.
11. Run `auto-research-verify.sh 8 "$PROJ"`. Phase 9 may start only after the execution report and registries pass.

## Phase 9 Post-Execution Review

Phase 9 evaluates the executed outputs before any result is treated as lockable evidence. Read `references/post-execution-review-contract.md` before running it.

Workflow:

1. Confirm Phase 8 execution passed and `ready_for_phase_9` is true.
2. Invoke `scholar-verify` in Stage 1 pre-draft mode (`stage1_no_manuscript`) to compare raw tables/figures against `tables/results-registry.csv` and `figures/figure-registry.csv`.
3. Spawn independent reviewers for `statistical_results`, `robustness_consistency`, `sample_data_integrity`, and `interpretation_claims`; record reviewer provenance with agent name, task id, dispatch time, model id, and report path.
4. Review every planned `spec_id`, every result row, every figure registry row, execution warnings/errors, Phase 7 decision rules, Phase 7 null-falsification rules, and Phase 7 reporting-depth checklist.
5. Bind reviewed numeric values to the actual result registry. Do not alter estimates, standard errors, p-values, or sample sizes in the review.
6. Classify null, opposite-sign, weak, or conflicting results as substantive findings when technically valid. Do not rerun analysis just to force expected results.
7. If the problem is a failed execution, bad registry, missing spec, invalid numeric output, stale artifact, or unverified figure/table output, route back to Phase 8.
8. If the problem is the analysis plan, design, measurement, or identification, route back to the earliest affected phase.
9. Save `review/post-execution-review.json`, `review/post-execution-review.md`, and `review/post-execution-fix-log.json`.
10. Run `auto-research-verify.sh 9 "$PROJ"`. Phase 10 may start only if there are no unresolved critical issues and no route-back phase.

## Phase 10 Runtime Sanity

Phase 10 is the final anti-drift and anti-nonsense gate before results are locked. Read `references/runtime-sanity-contract.md` before running it.

Workflow:

1. Confirm Phase 9 passed with `decision: PROCEED_TO_RUNTIME_SANITY`.
2. Recompute source hashes for the execution report, result registry, figure registry, post-execution review, and post-execution fix log.
3. Record `runtime_engine.skill: scholar-auto-research`, `mode: runtime_sanity`, `auto_research_contract: phase_10`, and `deterministic_gate: true`.
4. Check plausibility of estimates, uncertainty, sample sizes, p-values, and interpretation constraints.
5. Confirm Phase 9 weak/null/unexpected-result classifications and claim constraints are carried forward unchanged.
6. Check clean-room consistency: the artifacts being locked must be the same artifacts reviewed by Phase 8 and Phase 9.
7. Check invariants: planned specs equal executed specs, expected outputs exist, figure registry is complete, Phase 8 artifact manifest is current, Phase 9 constraints are current, and no critical artifact is unregistered.
8. Check plan/PAP drift: executed specs and claims must not drift from the approved analysis plan and premortem handoff.
9. Reconcile lock candidates exactly against required execution/report/registry artifacts and Phase 8 artifact manifest paths.
10. Save `verify/runtime-sanity.json` and `verify/runtime-sanity.md`.
11. Run `auto-research-verify.sh 10 "$PROJ"`. Phase 11 may lock results only if Phase 10 passes.

## Phase 11 Results Lock

Phase 11 freezes the verified analysis artifacts for drafting. Read `references/results-lock-contract.md` before running it.

Workflow:

1. Rerun `auto-research-verify.sh 10 "$PROJ"` and confirm Phase 10 passed with `decision: PROCEED_TO_RESULTS_LOCK`.
2. Rebuild the lock-candidate set from the current execution report, result registry, figure registry, and `tables/`/`figures/` folders; it must exactly match Phase 10 `artifact_inventory`.
3. Copy every lock candidate under `results-locked/<lock_id>/` and record it in `results-locked/manifest.json`.
4. Write `results-locked/LATEST.txt` with exactly the active `lock_id`.
5. Record `lock_engine`, `latest_matches: true`, `stage1_verdict: PASS`, and each locked artifact with source path, locked path, SHA-256, artifact role, and `lock_status: copied`.
6. Walk `results-locked/<lock_id>/` and fail if it contains any file not listed in the manifest.
7. Write `verify/stage1-verify.json` to prove every lock artifact matches the source artifact reviewed by Phase 10; Stage 1 scanner provenance must identify the Phase 11 contract.
8. Run `auto-research-verify.sh 11 "$PROJ"`. Phase 12 blueprint construction may use only locked artifacts.

## Phase 12 Manuscript Blueprint

Phase 12 converts the active results lock and upstream research plan into a single whole-paper governance artifact. Read `references/manuscript-blueprint-contract.md` before running it.

Workflow:

1. Rerun `auto-research-verify.sh 11 "$PROJ"`; do not build a blueprint if the active lock fails.
2. Load the active `results-locked/manifest.json`, `verify/stage1-verify.json`, research question, journal fit, literature/theory, design blueprint, identification strategy, analysis plan, post-execution review, results registry, and figure registry.
3. Use the manuscript-blueprint compiler to decide what the paper now is after the results are known: headline claim, contribution hierarchy, result hierarchy, hypothesis resolution, journal-specific manuscript structure, journal-specific display architecture, and section obligations.
4. Calibrate the blueprint to the target venue rather than a generic article shell. The blueprint must preserve journal-specific section order, theory placement, methods placement, supplement policy, and table/figure policy. Science Advances / NHB / PNAS should not collapse into ASR/JMF style, and Demography / JMF / Social Forces should not collapse into a generic multidisciplinary structure.
5. Carry forward the Phase 1 `journal_profile_resolution` explicitly. Imported custom profiles must survive unchanged into the blueprint, and an `ASR` fallback must remain explicit rather than silently becoming a generic structure.
6. Encode actual display conventions, not only counts. The blueprint's `display_architecture` must say whether tables are embedded or end-matter, whether figures are embedded or separate-file style, whether editable text tables are required, whether a descriptive Table 1 is mandatory, how table titles and notes are handled, and how displays are numbered and called out in prose.
7. Set `discussion_mode` in the blueprint from the venue-specific structure. Default to a combined `Discussion` only when the target journal supports it; use a separate `Conclusion` when the journal or paper type clearly requires one.
8. Write `manuscript/manuscript-blueprint.json` as the authoritative paper-level control artifact. It must include `publication_readiness` with a contribution sentence, journal-specific novelty claim, mechanism/rival matrix, evidence-to-claim map, reviewer-risk register, and `ready_for_drafting: true`.
9. Write `manuscript/manuscript-blueprint.md` as a readable summary of the final paper claim, contributions, result hierarchy, venue-specific structure, display policy, and section obligations.
10. Run `auto-research-verify.sh 12 "$PROJ"`. Phase 13 may start only after the blueprint and publication-readiness gate pass.

## Phase 13 Draft Manuscript

Phase 13 drafts from the active results lock and the approved manuscript blueprint using `scholar-journal` for journal preparation and `scholar-write` as the drafting engine. Read `references/manuscript-drafting-contract.md` before running it.

Workflow:

1. Rerun `auto-research-verify.sh 12 "$PROJ"`; do not draft if the blueprint is stale or invalid.
2. Load `manuscript/manuscript-blueprint.json` as the single source of truth for headline claim, contribution stack, result hierarchy, section obligations, and discussion mode.
3. Invoke `scholar-journal` in prepare mode for the Phase 1 target journal and paper type. Save `manuscript/journal-spec.json` with total word range, abstract cap, section-level word budgets, a numeric reporting policy, and the carried-forward `journal_profile_resolution`. If the journal gives no clear rule, default to 3 decimals for inferential statistics and 2 decimals for descriptive statistics, with `p < .001` below the reporting floor.
4. Invoke `scholar-write` in `draft full paper` mode as the prose engine. Load its writing protocol and style rules, but override any conflicting output-path or live-output behavior with this Phase 13 contract.
5. Pass `scholar-write` only the blueprint, active lock, Stage 1 verification, verified `references.bib`, journal spec, the Phase 4 variable dictionary, and upstream planning/review artifacts. It must not read live `tables/` or `figures/` except through locked paths under `results-locked/<lock_id>/`.
6. Write `manuscript/drafting-plan.json` before prose. It must include section briefs, paragraph purpose map, source-use plan, results interpretation plan, and revision workflow.
7. Draft `manuscript/manuscript-draft.md` from the journal-specific structure rather than from a generic sociology shell. Use the blueprint's theory placement and methods label directly: some journals need `Background`, some need `Theory`, some embed theory in `Introduction`, and multidisciplinary journals may require `Methods` or `Materials and Methods` after `Discussion`. A separate `Conclusion` is allowed only if the blueprint sets `discussion_mode: split`. The draft must be section-rich rather than template-rich: Introduction and the methods section require at least two substantive prose paragraphs, a standalone theory/background section if present requires at least three substantive prose paragraphs with synthesis rather than citation stacking and subheadings for full quantitative articles, Results requires at least three substantive prose paragraphs in addition to displayed evidence, and Discussion requires at least two substantive prose paragraphs. Front matter must include a real title, an empirical abstract, and required keywords. Empirical abstracts must state the research purpose or theoretical importance, data, method, headline findings, and contribution/implication without `Table 1` / `Figure 1` callouts. The Introduction must perform the ASR/JMF-style article-opening moves: puzzle/importance, literature gap, theory/contribution, data/case preview, method preview, headline findings preview, and article roadmap. Quantitative Methods must expose Data/Sample, Variables/Measures, and Analytic Strategy structure; Variables/Measures must visibly distinguish dependent variables/outcomes, independent variables/predictors, and controls/covariates when present. Explicit `H1/H2/H3` displays are allowed for ASR/JMF-style theory-and-hypotheses manuscripts, but each displayed hypothesis must be preceded by short theoretical motivation; bare proposal-style hypothesis checklists remain forbidden. The Theory/Hypotheses block must preserve the Phase 2 canonical hypotheses and remain pre-results: do not revise opening expectations, insert positive/negative estimate language, mention models/tables/figures, or let `drafting-plan.json` theory briefs import locked-result facts. The Discussion must adjudicate theory, hypotheses, rivals, limitations, scope, and contribution rather than restating coefficients; a separate Conclusion, when required, must synthesize the contribution and future scope without reopening table/model reporting.
8. Write `manuscript/draft-self-critique.json` after prose and before verification. It must identify the strongest plausible rejection reason, unsupported leaps, missing rivals, claim-strength risks, workflow-language leakage, revision actions, and `ready_for_verification: true`.
9. Treat the Phase 4 display semantics as binding reader-facing language. Visible prose, tables, figure captions, and labels must use concept-level terms rather than raw dataset-native variable names.
10. Invoke `scholar-polish` in `full` mode on `manuscript/manuscript-draft.md` before verification. It may remove generic AI writing patterns, hedging stacks, formulaic transitions, over-enumeration, em-dash overuse, and flat prose, but it must not alter citations, statistics, table/figure references, locked trace anchors, or argument structure.
11. Write `manuscript/polish-report.json` with polish engine metadata, patterns checked, before/after manuscript hashes, factual-anchor preservation checks, generic marker counts, and `ready_for_verification: true`.
12. Use Phase 9 interpretation constraints, the Phase 11 locked copies, and the Phase 12 blueprint. Every reader-facing locked result artifact must have a trace anchor, and every display-required artifact must have a visible display block.
The Results prose must explicitly reference numbered evidence blocks. Do not leave displays as unlabeled dumps. Write sentences such as `Table 1 shows...` and `Figure 2 presents...`, keep reader-facing numerics rounded to the journal policy rather than raw registry precision or scientific notation, and honor the journal's actual table/figure rendering mode rather than flattening all venues into the same display style. For ASR/JMF-style quantitative manuscripts, Table 1 should normally be descriptive statistics for all modeled variables, with regression tables split by outcome or model family rather than collapsed into a sparse omnibus matrix.
For quantitative empirical work, the main Results table must be a canonical regression table with model columns and predictor rows. Do not present `results-registry.csv`, a model ladder, or a focal-coefficient extract as the original regression table.
13. Write `manuscript/draft-manifest.json` with drafting engine metadata, blueprint metadata, drafting-plan metadata, self-critique metadata, polish report metadata, journal spec metadata, manuscript hash, source hashes, blueprint execution checks, display evidence, row-level locked result claims, citation plan, claim discipline, content alignment, and `ready_for_phase_14: true`.
14. Run `auto-research-verify.sh 13 "$PROJ"`. Phase 14 may start only after the journal-calibrated polished draft manifest and manuscript pass.

## Phase 14 Verify Manuscript

Phase 14 uses `scholar-verify` as the verification engine. Read `references/verification-contract.md` before running it.

Workflow:

1. Rerun `auto-research-verify.sh 13 "$PROJ"`; do not verify a stale or invalid draft.
2. Invoke `scholar-verify` in `full` mode against `manuscript/manuscript-draft.md`, `manuscript/manuscript-blueprint.json`, and the active lock from `results-locked/LATEST.txt`.
3. Run four independent verifier roles with unique task IDs, unique report paths, and role-specific scopes: `verify-numerics`, `verify-figures`, `verify-logic`, and `verify-completeness`.
4. Stage 1 must compare every Phase 13 reader-facing locked artifact against the manuscript anchors/displays. Figure checks must record visual inspection proof.
5. Stage 2 must compare the blueprint and every Phase 13 row-level locked result claim against prose claims, direction, uncertainty, and claim constraints.
6. Save individual agent reports under `verify/agents/`.
7. If any issue is found, write a structured `FAIL` report with `findings[]`, `owner_phase`, `route_back_phase`, affected artifacts, and required fixes. Stop and rerun from the earliest affected phase.
8. Write `verify/manuscript-verification.json` and `verify/manuscript-verification.md` with `ready_for_phase_15: true` only if no critical, stale, partial, unverified, or live-read issue remains.
9. Codex cross-model review (mandatory by default). The Phase 14 verifier runs `scripts/gates/codex-trigger-phase14.sh`, which requires Codex full-mode artifacts under `${PROJ}/reviews/codex/codex-review-consolidated-*.md` (or `A[4-5]-*.md`) whenever `SCHOLAR_CODEX_DEFAULT=true` (the default) AND the `codex` CLI is on PATH. Dispatch via `/scholar-openai full <manuscript-path>`. To opt out, either set `SCHOLAR_CODEX_DEFAULT=false` at the shell level OR add `[EXCUSED:codex-review: <reason>]` to `verify/manuscript-verification.md` (or to a string field in the .json). If the `codex` CLI is missing, the gate emits YELLOW (cannot fire) rather than RED.
10. Run `auto-research-verify.sh 14 "$PROJ"`. Phase 15 may start only after the four-agent verification passes.

## Phase 15 Citation And Claim Support

Phase 15 uses `scholar-citation` as the citation and claim-support engine. Read `references/citation-claim-contract.md` before running it.

Workflow:

1. Rerun `auto-research-verify.sh 13 "$PROJ"`; do not audit citations on an unverified manuscript.
2. Invoke `scholar-citation` in `verify` mode against `manuscript/manuscript-draft.md`, `manuscript/draft-manifest.json`, `literature/references.bib`, and `verify/manuscript-verification.json`.
3. Build a manuscript citation inventory from every cited BibTeX key in the draft and reconcile it against the project BibTeX.
4. Verify every cited key exists in the project BibTeX, every exported citation remains in `citation/references.bib`, and no fabricated or unresolved reference is present. Record bibliography provenance explicitly: the active source bibliography must be the project `literature/references.bib`, and any cross-project imports or hand-added entries must be declared and justified.
5. Build `citation/claim-source-map.json` for cite-bearing claims. Each claim must list manuscript location, manuscript anchor, claim type, cited keys, source locator, support verdict, and contradiction status.
6. Run retraction/status checks for every cited key and record the result.
7. Write `citation/citation-audit.json`, `citation/claim-source-map.json`, and `citation/references.bib`.
8. If the audit finds unsupported claims, contradicted claims, missing locators, missing references, stale source hashes, retraction flags, or a citation pool problem, write a structured `FAIL` report with `findings[]`, `owner_phase`, `route_back_phase`, affected artifacts, and required fixes. Stop and rerun from the earliest affected phase.
9. Mark `ready_for_phase_16: true` only when all references are verified, all claims are supported, no locator is missing, no cited work is retracted, and all source hashes are current.
10. Run `auto-research-verify.sh 15 "$PROJ"`. Phase 16 may start only after citation and claim support passes.

## Phase 16 Ethics And Open Science

Phase 16 uses `scholar-ethics` and `scholar-open` as the ethics/open-science engines. Read `references/ethics-open-science-contract.md` before running it.

Workflow:

1. Rerun `auto-research-verify.sh 15 "$PROJ"`; do not write ethics or open-science declarations for an unverified manuscript or unresolved citation audit.
2. Invoke `scholar-ethics` in `full` mode against the manuscript, safety status, data status, citation audit, and project context.
3. Invoke `scholar-open` in `full-package` mode against the same project context.
4. Reconcile the two outputs into `ethics/ethics-open-science.json` and `ethics/ethics-open-science.md`.
5. The JSON must cover AI use/privacy disclosure, IRB/consent status, COI, CRediT/authorship, data availability, preregistration/open-science status, originality/integrity review, and replication readiness.
6. Source hashes must cover `safety/safety-status.json`, `data/data-status.json`, `manuscript/manuscript-draft.md`, `manuscript/draft-manifest.json`, and `citation/citation-audit.json`.
7. If any ethics, privacy, IRB, COI, data availability, or open-science issue is unresolved, write a structured `FAIL` report with `findings[]`, `owner_phase`, `route_back_phase`, affected artifacts, and required fixes. Stop and rerun from the earliest affected phase.
8. Mark `ready_for_phase_17: true` only when all declarations are submission-ready, critical flags are empty, and the replication package plan is coherent with the data status.
9. Run `auto-research-verify.sh 16 "$PROJ"`. Phase 17 may start only after ethics and open science passes.

## Phase 17 Replication Package

Phase 17 uses `scholar-replication` as the package construction and validation engine. Read `references/replication-contract.md` before running it.

Workflow:

1. Rerun `auto-research-verify.sh 16 "$PROJ"`; do not assemble a replication package when ethics/open-science declarations are unresolved.
2. Invoke `scholar-replication` in `FULL` mode against the active results lock, execution report, data status, and ethics/open-science report.
3. Build `replication-package/` with README, manifest, code/docs/data stubs as appropriate, locked outputs, test report, and paper-to-code verification report.
4. Set `replication_mode` from Phase 16 `data_availability.sharing_mode`: `public-data-full`, `restricted-data-code-only`, `synthetic-demo`, or `no-data-conceptual`.
5. For `public-data-full`, run or record a clean-room test and compare reproduced outputs to the active results lock.
6. For restricted or synthetic modes, do not bundle restricted raw data; include access instructions, restriction rationale, schema/synthetic validation, and a clear non-equivalence statement where needed.
7. Write `replication-package/replication-report.json` with package inventory, source hashes, locked artifact coverage, Phase 8 script coverage with source hashes, data handling, path safety, environment, test result, verification result, and route-back fields.
8. If packaging reveals stale locks, missing scripts, unsafe data, path leaks, output mismatches, or data availability contradictions, write a structured `FAIL` report and route back to the earliest affected phase.
9. Mark `ready_for_phase_18: true` only when the package mode is coherent with Phase 16, all required package files exist, all locked artifacts are accounted for, and the test/verification status is acceptable for the declared mode.
10. Run `auto-research-verify.sh 17 "$PROJ"`. Phase 18 may start only after the replication package passes.

## Phase 18 Manuscript Quality Gate

Phase 18 uses `scholar-respond` in `simulate` mode as the journal-calibrated quality review engine. Read `references/quality-gate.md` before running it.

Workflow:

1. Rerun `auto-research-verify.sh 17 "$PROJ"`; do not evaluate quality until verification, citation support, ethics, and replication have all passed.
2. Invoke `scholar-respond simulate` against `manuscript/manuscript-draft.md`, using the active results lock, Phase 14 verification, Phase 15 citation/claim map, Phase 16 ethics/open-science report, and Phase 17 replication report as locked context.
3. Spawn independent reviewers for `methods-evidence`, `theory-contribution`, `senior-editor`, and `interpretive-skeptic`. Add a computational, qualitative, demographic, linguistic, or journal-specific reviewer when the manuscript type or target journal requires it.
4. Use the good `scholar-full-paper` practice of journal-aware reviewer panels and a severity-confidence matrix, but do not inherit its loose pass behavior. Every reviewer must write an individual report under `quality/agents/` with role, agent name (must start with `peer-reviewer-`), task id (must be a real dispatched id, not a placeholder), reviewed inputs, score vector, decision, and findings. Each reviewer must additionally produce two structured fields that probe intellectual quality directly: `contribution_locator` (verbatim sentences from the manuscript that constitute the contribution, plus clarity and specificity scores) and `rival_adjudication` (rivals named in the lit review, rivals adjudicated in the discussion, missing adjudications, and an adjudication-quality score). Reviewers must produce these locators independently — do not show one reviewer another reviewer's locator while drafting; cross-reviewer Jaccard consensus on the contribution sentences is what tests panel agreement on what the contribution IS.
5. Invoke `scholar-polish` in `scan` mode as a final prose-pattern audit. Phase 18 must not rewrite the manuscript. If the scan finds unresolved high-severity AI writing patterns, route back to Phase 13 for polish/reverification.
6. For quantitative empirical work, audit table architecture explicitly. `quality/manuscript-quality.json.regression_table_audit` must confirm that the main empirical display is a canonical regression table, not a registry/model-ladder extract, and that reader-facing labels and design notes are present.
7. Score contribution, research-question answer, argument coherence, theory-results integration, limitation candor, journal fit, abstract/introduction/discussion consistency, substantive conclusion support, prose quality, and reviewer consensus.
8. Write `quality/manuscript-quality.json` and `quality/manuscript-quality.md` with source hashes, reviewer reports, polish audit, regression table audit when applicable, dimension scores, threshold policy, severity-confidence matrix, decision, findings, fix checklist, route-back fields, and `ready_for_phase_19`.
9. If the manuscript needs substantive revision, write a structured `FAIL` report and route back to the earliest affected phase. Use Phase 12 for manuscript blueprint or whole-paper claim revisions, Phase 13 for manuscript prose/structure/polish revisions, Phase 14 for verification gaps, Phase 15 for citation/claim gaps, Phase 16 for ethics/open-science disclosure gaps, Phase 17 for replication/package gaps, and earlier phases only when design, data, or analysis defects are the true source.
10. Do not let Phase 18 directly rewrite the manuscript. If revision is needed, route back; the routed phase may invoke `scholar-write revise`, `scholar-polish full`, or the relevant upstream skill, then rerun downstream gates.
11. Mark `ready_for_phase_19: true` only when all dimensions meet threshold, no non-overridable blocker remains, every reviewer report is represented, any required regression table audit passes, polish audit passes, and the markdown summary matches the JSON decision.
12. Run `auto-research-verify.sh 18 "$PROJ"`. Phase 19 may start only after the quality gate passes.

## Phase 19 Final Assembly

Phase 19 turns the verified, quality-approved manuscript into the canonical four-format final output set. Read `references/final-assembly-contract.md` before running it.

Workflow:

1. Rerun `auto-research-verify.sh 18 "$PROJ"`; do not assemble final outputs from an unapproved quality report.
2. Use `manuscript/manuscript-draft.md` as the only prose source. Do not assemble from live tables, live figures, old drafts, reviewer memos, or manually edited final files.
3. Copy or transform that source into `final/manuscript-final.md`, adding only final front matter, references, declarations, and formatting metadata that are already supported by Phase 15-18 artifacts.
   - Normalize visible front matter during this transformation: title, `## Abstract`, abstract text, `Keywords: ...`, then `## Introduction`. Do not carry a draft prefix where `Keywords:` sits above `## Abstract`.
4. Generate `final/manuscript-final.docx`, `final/manuscript-final.tex`, and `final/manuscript-final.pdf` from the same `final/manuscript-final.md` source. Prefer Pandoc for conversion. If conversion tooling is unavailable, Phase 19 must fail with a structured route-back to Phase 19 rather than emitting placeholders.
5. Create a version id in UTC timestamp form, e.g. `2026-04-30T153012Z-v001`. Save immutable versioned copies under `final/versions/<version_id>/` using filenames that include the version id, and write `final/LATEST.txt` containing exactly the active version id.
6. Write `final/final-manifest.json` with `version_id`, `created_at_utc`, canonical paths, versioned paths, source hashes, output hashes, generation commands/status, same-source proof, section/declaration checks, citation/bibliography checks, and route-back fields.
7. The stable canonical outputs must remain `final/manuscript-final.{md,docx,tex,pdf}` for Phase 20 automation. The versioned copies are for audit/history and must have byte-identical hashes to the canonical files.
8. The four outputs must share the same stem: `final/manuscript-final.{md,docx,tex,pdf}`. Missing formats, missing versioned copies, separate stems, dummy binaries, placeholder text, stale hashes, or failed conversion logs are blockers.
9. If Phase 19 finds a stale quality report, route back to Phase 18. If it finds missing/unsupported references, route back to Phase 15. If it finds ethics/declaration contradictions, route back to Phase 16. If it finds replication/package contradiction, route back to Phase 17. Pure conversion, manifest, versioning, or packaging defects stay in Phase 19.
10. Mark `ready_for_phase_20: true` only after all four same-source canonical formats exist, all versioned copies exist, hashes match, manifest checks pass, and no assembly finding remains open.
11. Run `auto-research-verify.sh 19 "$PROJ"`. Phase 20 may start only after final assembly passes.

## Phase 20 Submission Hygiene

Phase 20 creates the reviewer-facing submission manuscript and final package manifest. Read `references/submission-hygiene-contract.md` before running it.

Phase 20 is a two-stage hygiene gate. Stage A is deterministic and catches known machinery-prose leaks. Stage B is a mandatory semantic body-prose read by an independent subagent after Stage A is clean. Both stages must pass before the default route is complete.

Workflow:

1. Rerun `auto-research-verify.sh 19 "$PROJ"`; do not build submission files from an invalid final assembly.
2. Use `final/manuscript-final.md` as the only source of substantive content, but do not treat submission assembly as a scrub-only pass. Assemble `submission/manuscript-submission.md` as a reviewer-facing product with an explicit section allowlist and product policy: preserve title, abstract, keywords, introduction, theory, methods, results, discussion, and references; exclude internal workflow appendices, trace anchors, lock metadata, and pipeline scaffolding by construction.
   - Reconstruct front matter explicitly rather than copying the pre-section prefix wholesale. The required visible order is title, `## Abstract`, abstract text, `Keywords: ...`, then `## Introduction`.
3. Generate `submission/manuscript-submission.docx`, `submission/manuscript-submission.tex`, and `submission/manuscript-submission.pdf` from `submission/manuscript-submission.md`. The submission package must therefore include all four reviewer-facing formats: `md`, `docx`, `tex`, and `pdf`.
4. Preserve substantive prose, references, declarations, tables, and figure placement markers. If a figure embed uses a local file path, replace it with a reviewer-safe figure placement marker rather than leaking the path. Submission hygiene should be structural first and regex cleanup only as a backstop, not the primary assembly strategy.
5. Run Stage A deterministic hygiene before dispatching Stage B. The manuscript must have zero known machinery-prose leaks: `[VERIFIED-*]` citation markers, pipeline-jargon headers such as `Robustness Ladder` or `BH Correction Summary`, "we carry N accepted limitations" / "pre-registered families" enumeration prose, 3+ consecutive bulleted spec-ID lines, and proposal-style hypothesis bullet/list blocks.
6. After Stage A clears, dispatch an independent semantic body-prose reader subagent. It must read `submission/manuscript-submission.md` top-to-bottom for novel structural prose that reads as pipeline output rather than social-science article prose, including leftover `H1/H2` hypothesis lists that read like a proposal or PAP rather than a journal article. Save its report to `submission/semantic-body-prose-read.md` with `STATUS: GREEN`, `REVIEWED_ARTIFACT: submission/manuscript-submission.md`, `MANUSCRIPT_SHA256: <current sha>`, `BLOCKING_ISSUES: 0`, and `STRUCTURAL_PATTERN_COUNT: 0`. Missing, stale, YELLOW, or RED reports block Phase 20.
7. Normalize the References section so entries are not rendered as a Markdown bullet list. Confirm no unresolved citation markers, missing citekeys, `SOURCE NEEDED`, or `UNVERIFIED` text remains.
8. Write `submission/submission-hygiene.json` with final-version binding, source hashes, Stage A checks, Stage B semantic-body-prose metadata, citation rendering checks, placeholder scan, internal metadata scan, format-generation checks, findings, route-back fields, and `pipeline_complete`.
9. Write `submission/submission-package-manifest.json` with canonical submission outputs in all four formats, the semantic body-prose report, timestamped versioned copies, hashes, final version id, package inventory, and completion status.
10. Create `submission/LATEST.txt` and immutable copies under `submission/versions/<submission_version_id>/`, including the semantic body-prose report.
11. If hygiene defects are found, write a structured `FAIL` report and route back to the earliest affected phase: Phase 13 for body-prose machinery introduced during drafting, Phase 19 for final assembly/source defects, Phase 15 for citation/reference defects, Phase 16 for declaration defects, Phase 17 for replication disclosure contradictions, and Phase 20 for scrub/manifest/versioning/format-generation defects.
12. Mark `pipeline_complete: true` only when the reviewer-facing manuscript is clean, Stage A is GREEN, Stage B is GREEN and current-hash-bound, all four submission formats exist, manifests are complete, canonical and versioned hashes match, and no open finding remains.
13. Run `auto-research-verify.sh 20 "$PROJ"`. The auto-research default route is complete only after this gate passes.

## Hard Rules

- No file-exists-only pass for phases 11-20.
- Phase 6 blockers must be fixed and re-reviewed inside Phase 6; the next phase must not be used as the repair mechanism.
- Phase 7 red or major risks must be mitigated before Phase 8, or routed back to the earliest affected phase.
- Phase 8 must not run unapproved scripts or silently skip planned specs, tests, or expected outputs.
- Phase 9 must not rewrite or rerun valid results because they are surprising; it either accepts them with interpretation constraints or routes back for a real defect.
- Phase 10 must not lock results with stale hashes, unresolved drift, implausible runtime artifacts, or missing invariant checks.
- Phase 11 must not omit, alter, or silently add lock artifacts; drafting must use the active results lock.
- Phase 12 must not skip whole-paper governance. The manuscript blueprint must govern the headline claim, contribution stack, result hierarchy, and discussion mode before drafting begins.
- Phase 13 must not draft from live tables or figures outside the active lock; every reader-facing locked artifact must be traceable from the manuscript and every provenance artifact must be covered in the draft manifest.
- Phase 13 must not use `results-registry.csv`, a model ladder, or a focal-coefficient extract as the main empirical table. Quantitative empirical papers need a canonical regression table with model columns and predictor rows.
- Phase 13 must not replace `scholar-write` with a local template assembler or builder that authors the substantive manuscript by itself. Helper code may package governed inputs or outputs, but publishable prose quality remains the binding requirement.
- No blueprint or manuscript edit after Phase 14 without invalidating and rerunning 14.
- No manuscript edit after Phase 15 without invalidating and rerunning 15.
- Phase 15 must not replace `scholar-citation` with a local key scanner or manifest writer that skips real source verification, claim support checks, or bibliography judgment.
- No unresolved ethics, privacy, IRB, COI, or data-availability blocker may be deferred into replication or final assembly.
- Any Phase 18 quality revision or peer-review revision must route back to the earliest affected phase.
- No fabricated, unverified, or unsupported citations may be overridden.
- Replication must declare one mode: `public-data-full`, `restricted-data-code-only`, `synthetic-demo`, or `no-data-conceptual`.
- Public-data replication must prove clean-room output reproduction against the active results lock; restricted/synthetic/no-data replication must explicitly justify why full reproduction is not possible.
- Final outputs must include same-source `md`, `docx`, `tex`, and `pdf`, unless the user explicitly requests a narrower package.
- Final and submission manuscripts must not leak internal phase, workflow, lock, manifest, registry, provenance, artifact, or verification language into reader-facing prose.

## Validation

Before using or modifying this skill, run:

```bash
bash .claude/skills/scholar-auto-research/scripts/auto-research-contract-lint.sh
bash .claude/skills/scholar-auto-research/scripts/auto-research-fixture-test.sh
```

These tests validate the contract shape, default route, state behavior, positive fixture, and selected negative fixtures.
