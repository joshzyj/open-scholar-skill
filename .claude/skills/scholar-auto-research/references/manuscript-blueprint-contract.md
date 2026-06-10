# Manuscript Blueprint Contract

Phase 12 converts the active results lock and upstream research plan into a single paper-level governing artifact before any prose drafting begins. It is the control layer for whole-paper argument, not a writing phase.

Engine handoff:

- Use `scholar-auto-research`'s internal manuscript-blueprint compiler as the primary engine.
- Load the Phase 1 research question and journal fit, Phase 2 literature/theory, Phase 3 design, Phase 5 analysis plan, Phase 9 post-execution interpretation constraints, Phase 11 results lock, and the locked result/figure registries.
- Do not draft prose, render final manuscript sections, or invoke `scholar-write` as the authoritative output engine in Phase 12.
- The blueprint must decide what the paper now is after the results are known, including how null-compatible, mixed, or demoted findings change the final contribution.

Required inputs:

- `results-locked/manifest.json`
- `results-locked/LATEST.txt`
- `verify/stage1-verify.json`
- `idea/research-question.json`
- `idea/journal-fit.json`
- `literature/lit-theory.md`
- `design/design-blueprint.md`
- `design/identification-strategy.json`
- `analysis/analysis-plan.md`
- `review/post-execution-review.json`
- `tables/results-registry.csv`
- `figures/figure-registry.csv`

Required outputs:

- `manuscript/manuscript-blueprint.json`
- `manuscript/manuscript-blueprint.md`

`manuscript/manuscript-blueprint.json` must include:

- `verdict`: `PASS`
- `degraded`: `false`
- `blueprint_engine`: object declaring `skill: scholar-auto-research`, `mode: manuscript_blueprint`, `lock_enforced: true`, and `live_output_reads_forbidden: true`
- `lock_id`: active Phase 11 lock ID
- `lock_manifest_sha256`: active lock manifest self-hash
- `source_hashes`: SHA-256 hashes for the lock manifest, Stage 1 verification, research question, journal fit, literature/theory, design blueprint, identification strategy, analysis plan, post-execution review, results registry, and figure registry
- `paper_type`: matching Phase 1 `paper_type`
- `target_journal`: matching Phase 1 `target_journal.primary`
- `journal_profile_resolution`: exact carried-forward resolution of the target journal profile from Phase 1, including `requested_journal`, `resolved_profile_name`, `profile_origin`, `profile_source_engine`, `source_strategy`, `web_lookup_attempted`, `fallback_used`, `fallback_reason`, `journal_structure`, and `display_architecture`
- `paper_claim`: one-sentence final headline claim the manuscript is allowed to make
- `claim_strength`: matching or narrower than the design / post-execution claim strength
- `publication_readiness`: object with `status: PASS`, `ready_for_drafting: true`, a concrete contribution sentence, target-journal novelty claim, mechanism/rival matrix, evidence-to-claim map, reviewer-risk register, and `route_back_if_not_ready: false`
- `contribution_stack`: ranked non-empty list of 2-4 contribution entries, each with `rank`, `contribution_type`, `claim_text`, `depends_on_results`, and `scope_note`
- `result_hierarchy`: non-empty list covering every registered result/figure artifact used for interpretation, each with `artifact_path`, `artifact_role`, `spec_id` or `figure_id`, `narrative_role`, and `headline_status` where `headline_status` is one of `headline`, `supporting`, `sensitivity`, `diagnostic`, or `appendix_only`
- `hypothesis_resolution`: one entry for every Phase 3 hypothesis or accepted unmodeled hypothesis limitation, each with `hypothesis_id`, `resolution_status`, `evidence_specs`, and `manuscript_implication`
- `mechanism_integration_plan`: non-empty list of mechanism entries, each with `mechanism_id` or `mechanism_label`, `theory_role`, `evidence_role`, and `integration_status` where `integration_status` is one of `tested_directly`, `tested_indirectly`, `discussion_only`, or `drop_from_claim`
- `journal_structure`: object encoding journal-specific manuscript architecture, including `profile_source`, ordered `section_sequence`, `results_before_methods`, `theory_presentation`, `methods_section_label`, `discussion_conclusion_policy`, and `supplement_policy`
- `display_architecture`: object encoding journal-specific table/figure policy, including `table_placement_policy`, `figure_placement_policy`, `descriptive_table_requirement`, `editable_text_tables`, `image_tables_forbidden`, `main_text_display_cap`, `main_text_table_cap`, `main_text_figure_cap`, `supplement_label_prefix`, `panel_label_style`, `table_rendering_mode`, `figure_rendering_mode`, `table_title_position`, `table_notes_policy`, and `display_callout_style`
- `front_matter_policy`: object or section-obligation entry specifying title form, abstract moves, keyword requirement, and the rule that abstracts may not reference display labels such as `Table 1` or `Figure 1`
- `discussion_mode`: `combined` or `split`; default is `combined` and `split` is allowed only when journal calibration requires a separate conclusion
- `appendix_policy`: object declaring which appendices belong in the `draft`, `final`, and `submission` products; `submission` may be empty and should exclude workflow/provenance appendices unless the journal explicitly requires them
- `section_obligations`: object with entries for `abstract`, `introduction`, `literature_review_and_theory`, `data_and_methods`, `results`, and `discussion`; each entry must include `required_moves`, `required_artifacts`, `required_disclosures`, and `forbidden_moves`
- if `discussion_mode` is `split`, `section_obligations` must also include `conclusion`; otherwise the final synthesis, limitations, and implications belong inside `discussion`
- `required_disclosures`: non-empty list of manuscript-wide disclosures inherited from Phase 9 and any result-specific limits
- `forbidden_moves`: non-empty list of paper-level argumentative moves that the manuscript may not make
- `table_figure_narrative_map`: non-empty list mapping displayed artifacts to their narrative purpose, with `artifact_path`, `display_expected`, `section`, `paragraph_role`, and `claim_role`
- `abstract_alignment`: object specifying required abstract elements in order
- `discussion_alignment`: object specifying how the discussion must answer the research question, delimit scope, and frame limitations
- `null_result_framing`: object specifying how null-compatible or mixed findings must be framed in the manuscript; if the project is not null-compatible it must still state `status: not_primary`
- `route_back_phase`: `null` for PASS; earliest upstream phase for FAIL
- `ready_for_phase_13`: `true`

Blueprint rules:

- The blueprint is the single source of truth for manuscript-level claim hierarchy. Phase 13 may not invent a stronger claim, elevate a demoted result, or suppress a required disclosure.
- The blueprint is also the publication-readiness gate. It must fail or route back when the project lacks a clear contribution, target-journal novelty, mechanism/rival logic, evidence-to-claim support, or a credible answer to anticipated reviewer objections.
- `discussion_mode: combined` is the auto-research default. Do not split discussion and conclusion unless the target journal or paper type clearly requires it.
- `appendix_policy` is the single source of truth for product-specific appendix handling. Do not let draft-only provenance or workflow appendices leak into `submission/manuscript-submission.md`.
- `journal_structure` and `display_architecture` are the single sources of truth for journal-calibrated manuscript order and display-item policy. Do not flatten Science Advances / NHB / PNAS into a conventional sociology structure, and do not flatten ASR / Social Forces / JMF / Demography into a generic embedded-display structure.
- `journal_profile_resolution` must remain explicit. If a custom journal was imported in Phase 1, do not silently replace it with a built-in journal. If Phase 1 fell back to `ASR`, keep that fallback visible rather than pretending the paper still targets the unresolved requested journal.
- `display_architecture` must be specific enough to distinguish journal families on actual table design, not just table counts. It must encode whether tables are embedded or end-matter, whether figures are embedded or separate-file style, whether editable text tables are required, whether a descriptive Table 1 is mandatory, how table titles and notes are handled, and how displays are numbered and called out in prose.
- For ASR/JMF/AJS/Demography/Social Forces-style quantitative manuscripts, `display_architecture.descriptive_table_requirement` must be `table_1_required_for_quantitative` or stricter, not `journal_optional`. The blueprint must reserve a reader-facing descriptive statistics table covering all modeled variables, normally `Table 1`, before the main regression evidence.
- If the headline paper claim changed materially relative to the original research question framing, the blueprint must explain why in `paper_claim` plus `contribution_stack`.
- If the main finding is null-compatible or mixed, the blueprint must explicitly define the contribution form rather than allowing the manuscript to drift into directional spin.
- `publication_readiness.mechanism_rival_matrix` must include both focal mechanisms and rival or alternative explanations. A paper that has mechanisms but no rivals is not ready for drafting.
- `publication_readiness.evidence_claim_map` must map headline, supporting, null-compatible, and limitation claims to specific artifacts, hypotheses, robustness checks, or accepted limitations.
- `publication_readiness.reviewer_risk_register` must include at least three anticipated reviewer objections, including the strongest plausible rejection reason and the phase to route back to if the objection cannot be answered.
- Every `headline` result in `result_hierarchy` must appear in `section_obligations.results.required_artifacts` and `section_obligations.discussion.required_artifacts`.
- For quantitative empirical manuscripts, `result_hierarchy` must include at least one canonical regression table artifact with `artifact_role: main_regression_table` or `artifact_role: regression_table`. A row-per-spec results registry, model ladder, focal-coefficient extract, or verification table may not be the headline or main empirical display.
- For quantitative empirical manuscripts, `result_hierarchy` and `table_figure_narrative_map` must also include the descriptive table when one is produced or required. Acceptable roles are `descriptive_table` or `reader_facing_descriptive_table`, and these entries do not need a `spec_id` because they summarize the analytic sample rather than one model specification.
- Regression-table display planning must split unrelated outcomes or model families into separate reader-facing tables or appendix tables. Do not plan a sparse omnibus model matrix with seven or more model columns and many blank predictor cells; that table shape signals that the registry/model ladder has been collapsed into a manuscript table.
- Internal `spec_id` values may be retained for traceability in `result_hierarchy`, but the blueprint must instruct the manuscript to use reader-facing model labels (`Model 1`, `Model 2`, `M1`, `M2`) in prose and table headers. Visible manuscript text must not refer to internal specification IDs such as `S1` or `S2`.
- Any `diagnostic` or `appendix_only` result may not appear as a headline contribution.
- The blueprint must preserve journal-specific section order, methods placement, theory placement, and table/figure policy strongly enough that later drafting and assembly can distinguish, for example, Demography from JMF and Science Advances from Social Forces.
- The blueprint must be auditable enough that an independent reviewer can tell what the final paper is arguing without reading the prose draft.

`manuscript/manuscript-blueprint.md` must be a readable companion that includes:

- final paper claim
- ranked contributions
- result hierarchy summary
- hypothesis resolution summary
- section-by-section obligations
- required disclosures
- forbidden argumentative moves

Phase 12 fails if the lock is stale, if the blueprint uses live outputs instead of the active lock, if the paper claim exceeds the allowed claim strength, if result hierarchy is incomplete, if a quantitative empirical paper lacks a canonical regression-table display artifact, if a required quantitative manuscript lacks a display-expected descriptive table, if a registry/model-ladder extract is elevated into the main empirical display, if the planned regression display collapses unrelated model families into a sparse omnibus table, if hypotheses are unresolved without an accepted limitation note, if section obligations are missing or generic, if null-compatible findings are not explicitly framed, or if the blueprint hash differs from the manifest fields it declares.
