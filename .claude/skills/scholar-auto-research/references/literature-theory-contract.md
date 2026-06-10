# Literature and Theory Contract

Phase 2 prevents citation padding and undertheorized papers.

Required files:

- `literature/lit-theory.md`
- `literature/literature-coverage-matrix.json`
- `literature/references.bib`
- `literature/search-log.md`
- `literature/review-protocol.json`
- `literature/lit-theory-manifest.json`

Required inputs:

- `idea/research-question.json`
- `idea/journal-fit.json`

`literature-coverage-matrix.json` must include:

- `verdict`
- `engine_handoff`
- `review_protocol`
- `coverage_matrix.constructs`
- `coverage_matrix.theories`
- `coverage_matrix.methods`
- `coverage_matrix.datasets_populations`
- `coverage_matrix.competing_findings`
- `must_cite_coverage`
- `source_role_matrix`
- `mechanism_chain`
- `hypotheses`
- `journal_calibration`
- `ready_for_phase_3`

Canonical hypothesis rule:

- Phase 2 is the ex ante theory/hypothesis source of truth. Its `hypotheses`
  array must preserve stable hypothesis IDs, statements, directions, focal
  variables, mechanisms or moderators when relevant, and scope conditions.
- Downstream phases may report whether each hypothesis is supported,
  contradicted, mixed, or null-compatible, but they may not rewrite the Phase 2
  hypothesis statements inside the Theory section after seeing results.
- If `citations/hypotheses-canonical.json` is emitted later, it must be a
  faithful structured copy of Phase 2 hypotheses rather than a post-results
  restatement.

Engine handoff:

- Invoke `scholar-lit-review-hypothesis` as the primary integrated literature/theory engine. It replaces separate `scholar-lit-review` and `scholar-hypothesis` calls in the default route because Phase 2 needs literature landscape, gap, mechanism, and hypotheses in one coherent argument.
- Invoke `scholar-write` after the integrated review to write or revise `literature/lit-theory.md` as the formal Literature Review and Theory section handoff. The writing pass must preserve verified citations, mechanisms, hypotheses, target-journal calibration, and claim-strength limits from Phase 1.
- Optional support: use `scholar-lit-review` only for a deeper standalone landscape map, and `scholar-hypothesis` only when the integrated output leaves mechanisms or hypotheses weak. If used, record them as supporting engines, not replacements for the primary engine.

`engine_handoff` must include:

- `lit_review_engine.skill`: `scholar-lit-review-hypothesis`
- `lit_review_engine.mode`: `integrated_literature_theory_hypotheses`
- `writing_engine.skill`: `scholar-write`
- `writing_engine.mode`: `draft` or `revise`
- `writing_engine.section`: `Literature Review and Theory`
- `target_journal`

Review-protocol proof:

- Phase 2 must preserve auditable proof that `scholar-lit-review-hypothesis` actually followed its own workflow rather than being manually emulated.
- Canonical artifacts are `literature/search-log.md` and `literature/review-protocol.json`.
- `review-protocol.json` must include: `verdict`, `source_phase`, `primary_skill`, `local_library_first`, `reference_backend_detected`, `knowledge_graph_checked`, `ref_queries`, `author_queries`, `web_queries`, `search_log_path`, `source_integrity_completed`, `verification_panel_completed`, `prior_project_bibliographies_used`, and `ready_for_phase_3`.
- `local_library_first` must be `true`. If no local reference backend is available, Phase 2 must stop rather than silently fall back to web-only or ad hoc prior-project bibliography reuse.
- `reference_backend_detected` must list at least one of `Zotero`, `Mendeley`, `BibTeX`, or `EndNote XML`.
- `ref_queries` must be at least 3, `author_queries` at least 1, and `literature/search-log.md` must show `RefLib` searches before any `WebSearch` rows.
- If prior project bibliographies are consulted, they must be logged under the local-library-first protocol and listed in `prior_project_bibliographies_used`; they do not substitute for the required local reference search.

`lit-theory-manifest.json` must include:

- `verdict`: `PASS`
- `source_phase`: `2`
- `engine_handoff`
- `selected_rq_hash`
- `journal_fit_hash`
- `coverage_matrix_hash`
- `lit_theory_hash`
- `references_bib_hash`
- `source_hashes`
- `protocol_artifacts`: object with canonical `search_log` and `review_protocol` paths
- `ready_for_phase_3`: `true`

Rules:

- Each coverage category must contain at least one item.
- `must_cite_coverage` must include more than 30 works, and every work must be marked covered.
- `source_role_matrix` must assign important sources to argument roles rather than treating the bibliography as coverage inventory. Required roles include theory, mechanism, rival or competing explanation, method/design, and context/population/domain where applicable. Each entry must state the source key or title, argument role, claim supported, target manuscript section, and why that source matters.
- `mechanism_chain` must have at least two linked steps.
- `hypotheses` must include at least one directional hypothesis.
- `references.bib` must contain more than 30 BibTeX entries.
- `search-log.md` must record the local-library-first search sequence, including at least three `RefLib` rows and at least one author search before web expansion.
- `review-protocol.json` must PASS and attest that the integrated skill's source-integrity workflow was completed.
- `journal_calibration` must carry the Phase 1 target journal and paper type into the literature/theory handoff, including expected theory depth, citation density, and must-cite strategy.
- `lit-theory.md` must be written through `scholar-write`; handwritten or untracked prose does not satisfy the default auto-research contract.
- The Phase 2 package fails if it only mimics the outputs of `scholar-lit-review-hypothesis` without the underlying search/logging/verification protocol.
- Novelty claims require explicit prior-work contrast in the matrix or prose.
