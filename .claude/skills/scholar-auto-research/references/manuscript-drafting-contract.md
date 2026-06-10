# Manuscript Drafting Contract

Phase 13 drafts the first full manuscript from the active Phase 11 results lock and the approved Phase 12 manuscript blueprint using `scholar-write` as the drafting engine. It is not a free-writing phase.

Product roles:

- `manuscript/manuscript-draft.md` is the trace-rich verifier-facing product. It may contain lock trace anchors, display anchors, and draft-only appendices permitted by the blueprint.
- `final/manuscript-final.md` is the reader-facing archival product assembled later from the approved draft.
- `submission/manuscript-submission.md` is the reviewer-facing product assembled later from approved content sections, not by inheriting draft-only provenance blocks.

Engine handoff:

- Invoke `scholar-journal` in prepare mode for the Phase 1 target journal and paper type before drafting. Save the result as `manuscript/journal-spec.json`.
- Invoke `scholar-write` in `draft full paper` mode.
- Load `scholar-write`'s writing protocol for prose structure, citation discipline, style, and section-level drafting.
- The auto-research Phase 13 contract overrides any conflicting `scholar-write` behavior: outputs must be `manuscript/manuscript-draft.md` and `manuscript/draft-manifest.json`, citations must come from the project `literature/references.bib`, the manuscript blueprint must govern paper-level argument, and result/table/figure reads must use the active lock under `results-locked/<lock_id>/`.
- Do not use `scholar-write` standalone output paths such as per-section `drafts/draft-*.md` as the authoritative Phase 13 output.
- Helper code may prepare governed inputs, compile manifests, or package outputs, but it must not replace `scholar-write` as the primary author of substantive manuscript prose. If the draft is mainly produced by local templates or builders rather than governed scholarly writing, Phase 13 should fail.

Journal-native writing constitution:

Before drafting, the writer must treat the target journal as a binding genre, not as a generic style label. The governing prompt for a full empirical manuscript is:

> Write a journal-native empirical article for the target journal. Use the approved research question, theory, design, measurement plan, locked results, and journal profile as constraints, but do not expose those artifacts as process language. Each section must perform its journal role: the abstract states purpose, data/methods, headline findings, and contribution; the introduction frames the puzzle and contribution; the theory section develops mechanisms and hypotheses; the methods section documents the evidentiary base, measures, estimator, inference, modeling strategy, and robustness checks; the results interpret the locked tables and figures; the discussion returns to theory, rivals, scope, and contribution. Write as an author of the article, not as a pipeline reporting what files contain.

This constitution exists because LLMs often know the surface features of ASR/JMF-style articles but fail under pipeline conditions: they overfit to the nearest artifact names, convert registries into prose, repeat defensive limitation boilerplate, and satisfy local section headings without a paper-level genre model. The pipeline must therefore supply a single paper-level writing prompt, section obligations, exemplar-derived methods architecture, and negative constraints before any prose is drafted.

Exemplar-derived methods architecture:

- JMF-style quantitative articles commonly use `Method` with `Data and Sample`, `Variables and Measures`, and estimator-specific subsections such as `Propensity Score Matching` and `Survival Analysis`. The methods prose defines each variable, states how it is measured, explains why the estimator is appropriate, and reports sensitivity analyses without treating the method as a pipeline ladder.
- ASR-style quantitative articles commonly use `Method` with `Empirical Setting and Data`, role-labeled measure subsections such as `Dependent Variables`, `Independent Variables`, and `Control Variables`, followed by `Estimation` or `Analytic Strategy`. The estimation subsection specifies the model, why it fits the outcome and theory, what variation identifies the estimates, how inference is handled, and where robustness checks appear.
- For full empirical articles, the main text normally reports theoretically selected full models. Stepwise models, auxiliary specifications, and alternative operationalizations should usually go to supplemental materials or appendix tables unless the stepwise comparison itself is the substantive test. Do not narrate a "model ladder" as the article's main analytic logic unless the journal-calibrated design explicitly requires a sequence of nested models.

Exemplar-derived whole-article architecture:

- JMF-style introductions move from a broad substantive puzzle to named theoretical perspectives, a concrete gap, the case/data setting, a method preview, headline results, and a contribution. They do not begin as a methods memo or display guide.
- ASR-style introductions make the theoretical dilemma legible early, identify the literatures being joined or revised, state the empirical setting and measurement innovation, preview the core results, and close with what the paper contributes to theory.
- Theory/background sections must be organized around constructs, mechanisms, rival accounts, scope conditions, and testable hypotheses or expectations. A single undifferentiated literature block is not acceptable for a full quantitative article unless the target journal explicitly uses that format.
- Discussion sections must return to the theory and hypotheses, explain which rival accounts remain plausible, state limitations and scope conditions, and identify the contribution. They should not be a second Results section.
- Separate conclusions, when required by the blueprint, synthesize what the study changes for the field and what remains open. They should not introduce new tables, figures, coefficients, or p-values.

Required inputs:

- `manuscript/manuscript-blueprint.json`
- `results-locked/manifest.json`
- `results-locked/LATEST.txt`
- `verify/stage1-verify.json`
- `literature/references.bib`
- `literature/lit-theory.md`
- `idea/research-question.json`
- `idea/journal-fit.json`
- `design/design-blueprint.md`
- `data/variable-dictionary.csv`
- `analysis/analysis-plan.md`
- `review/post-execution-review.json`

Required outputs:

- `manuscript/manuscript-draft.md`
- `manuscript/draft-manifest.json`
- `manuscript/drafting-plan.json`
- `manuscript/draft-self-critique.json`
- `manuscript/polish-report.json`
- `manuscript/journal-spec.json`

`manuscript/journal-spec.json` must include:

- `verdict`: `PASS`
- `source_engine`: `scholar-journal`
- `target_journal`: matching Phase 1 `target_journal.primary`
- `paper_type`: matching Phase 1 `paper_type`
- `journal_profile_resolution`: exact carried-forward profile resolution from Phase 1 / Phase 12
- `total_word_range`: object with `min` and `max`
- `abstract_word_cap`
- `section_word_budget`: object for every required manuscript section, with `target_words`, `min_words`, and optional `max_words`
- `numeric_reporting_policy`: object describing manuscript-facing rounding and p-value rules
- `journal_structure`: object matching the Phase 12 blueprint's journal-specific section-order and methods-placement policy
- `display_architecture`: object matching the Phase 12 blueprint's journal-specific table/figure policy
- `ready_for_drafting`: `true`

The section budget is an ex ante journal-calibrated plan, not a retrospective summary of the completed draft. Phase 13 fails if the budget is obviously reverse-engineered from the manuscript's realized word counts.

`manuscript/manuscript-draft.md` must follow the approved `journal_structure.section_sequence` rather than a generic article shell. The draft must always include `Abstract`, `Introduction`, `Results`, and `Discussion`, but the theory/background and methods headings must follow the journal-calibrated blueprint:

- if `journal_structure.theory_presentation = standalone_literature_theory`, use `## Literature Review and Theory`
- if `journal_structure.theory_presentation = theory_section`, use `## Theory`
- if `journal_structure.theory_presentation = background_section`, use `## Background`
- if `journal_structure.theory_presentation = embedded_in_introduction`, embed the theory/literature obligations inside `## Introduction` rather than creating a generic standalone theory heading
- use the exact journal-calibrated methods heading from `journal_structure.methods_section_label`, such as `## Data and Methods`, `## Materials and Methods`, or `## Methods`

The visible sections must still meet both the generic floor and the journal-specific budget:

- `Abstract`: 80-300 words
- `Introduction`: at least 250 words
- standalone theory/background section if present: at least 300 words
- methods section: at least 250 words
- `Results`: at least 250 words
- `Discussion`: at least 200 words

The default manuscript architecture uses a combined `Discussion` section. A separate `Conclusion` is allowed only when both `manuscript/manuscript-blueprint.json.discussion_mode` is `split` and the journal spec supports a split close. In that case, `Discussion` still remains required and `Conclusion` becomes an additional governed section rather than a replacement.

The blueprint's `appendix_policy` governs product-specific appendix handling. Phase 13 may include governed draft appendices, but those appendices do not automatically propagate to final or submission products. The blueprint's `journal_structure` and `display_architecture` govern the venue-specific section order and table/figure design rules that later final and submission products must satisfy.

The full draft MUST fall within `journal-spec.json.total_word_range`. The lower bound of `journal-spec.json.total_word_range` MUST equal the resolved journal profile's `total_word_budget.min` (i.e., `scholar-journal/references/profiles/<key>.json.total_word_budget.min`); inventing a smaller floor is forbidden, regardless of any global "1,300 word" minimum that may appear in legacy fixtures or scaffolding. The abstract must not exceed `journal-spec.json.abstract_word_cap`. For a full empirical article, every section MUST hit at least 85% of its journal-calibrated `target_words` — `min_words` is a short-format safety net (research notes, briefs, commentaries, etc.) and is NOT the binding floor for full empirical articles. The exception is the abstract, which is governed by `abstract_word_cap` rather than per-section `target_words`.

For a full empirical journal article, the journal-calibrated `total_word_range.min` MUST equal the resolved journal profile's `total_word_budget.min`. For typical sociology / demography / management journals this floor is 7,000-8,000 words; for ASR/AJS/Demography it is 8,000-10,000+ words. A lower minimum is allowed ONLY when `journal-spec.json.paper_type` or the target-journal profile explicitly marks the product as a research note, brief report, registered report stage document, commentary, replication note, or other short format.

`numeric_reporting_policy` is ex ante and journal-aware. If the target journal gives explicit guidance, use it. If the journal does not give clear guidance, the auto-research default is:

- `inferential_digits: 3` for coefficients, standard errors, confidence intervals, and exact p-values;
- `descriptive_digits: 2` for descriptive means, proportions, and rates;
- `p_value_rule`: report exact p-values to 3 decimals, but use `p < .001` below that floor;
- `allow_scientific_notation: false` for reader-facing manuscript text.

The draft may preserve raw full-precision values in comments, manifests, and trace anchors for verification, but reader-facing prose, tables, and figure captions must follow the journal-calibrated numeric policy.

The abstract must be a journal-native empirical abstract, not a miniature Results section or display guide. It must state the research purpose or theoretical importance of the topic, name the data source or sample, identify the method or modeling strategy, report the headline findings from locked results, and close with the contribution or implication. It must not reference display artifacts such as `Table 1`, `Figure 1`, or file paths; table and figure callouts belong in Results, not the abstract. The gate `scripts/gates/journal-section-architecture-check.sh` enforces these abstract moves.

Theory/hypothesis continuity is binding. Phase 2 `literature/lit-theory.md`
and `literature/literature-coverage-matrix.json.hypotheses` are the ex ante
source of the manuscript's theoretical claims and testable hypotheses. Phase
13 must preserve that theory/hypothesis architecture in the Theory or
Theory-and-Hypotheses section before turning to data. Results may later report
support, contradiction, mixed evidence, or null-compatible findings; Theory
must not pre-adjudicate those outcomes, say that evidence revises the opening
expectation, turn directional hypotheses into unfalsifiable "could be either
direction" prose, or insert coefficient/model/table/figure language. The
`manuscript/drafting-plan.json` theory brief must be literature/theory-facing:
it may mention mechanisms, rival accounts, and scope conditions, but it must
not use locked-result facts, artifact paths, or result-specific instructions to
shape Theory. The gate `scripts/gates/theory-hypothesis-continuity-check.sh`
enforces this rule in Phases 13, 18, and 20.

The manuscript must include real front matter. Every draft/final/submission manuscript needs a manuscript title before `## Abstract`; ASR/JMF/AJS/Demography/Social Forces-style targets also need a Keywords line, section, or YAML field with at least three substantive keywords. The title should foreground the substantive puzzle, construct, population, or theoretical tradeoff rather than use a generic placeholder.

The draft must also use reader-facing measurement language. Visible prose, rendered tables, rendered figures, captions, and display labels must follow the Phase 4 variable dictionary's `display_label`, `table_stub_label`, `manuscript_term`, and `levels_display` fields. Raw dataset-native variable names such as underscored fields, coded item names, or cryptic abbreviations should not appear in reader-facing manuscript content unless they are part of a quoted source instrument or a trace-only comment.

The draft must contain no placeholder text, cite at least 30 unique keys present in `references.bib`, and avoid unsupported overclaiming language such as `prove` or `guarantee`.

Before drafting, Phase 13 must write `manuscript/drafting-plan.json`. This is not optional scaffolding. It must include:

- `section_briefs`: entries for every required manuscript section, with section purpose, key claim, required evidence, source roles, forbidden moves, and blueprint obligations used;
- `paragraph_purpose_map`: planned paragraphs with section, paragraph id, purpose, claim, evidence artifacts, source roles, and theory/mechanism link;
- `source_use_plan`: cited sources and their argument role, target section, claim supported, and why the source is necessary;
- `results_interpretation_plan`: every headline/supporting result artifact and the claim, uncertainty language, mechanism link, and limitation language it authorizes;
- `revision_workflow`: `outline_completed: true`, `draft_after_plan: true`, and `self_critique_required: true`.

After drafting and before Phase 14 verification, Phase 13 must write `manuscript/draft-self-critique.json`. It must include the strongest plausible rejection reason, unsupported-leap scan, missing-rival scan, claim-strength scan, workflow-language scan, revision actions taken, and `ready_for_verification: true`. A pass-only self-critique is not acceptable; it must identify at least one concrete risk or explain why each required risk category is not applicable.

The draft must not satisfy section floors with one canned paragraph per section. Minimum prose structure:

- `Introduction`: at least 2 substantive prose paragraphs
- `Literature Review and Theory`: at least 3 substantive prose paragraphs and at least 20 unique citation keys in this section
- `Data and Methods`: at least 2 substantive prose paragraphs
- `Results`: at least 3 substantive prose paragraphs in addition to rendered tables/figures
- `Discussion`: at least 2 substantive prose paragraphs, including one limitations/scope paragraph and one contribution/implications paragraph

A substantive prose paragraph is a non-comment, non-table, non-figure block with at least 40 words. Recycled boilerplate that only renames the topic does not count as substantive prose.

Section-specific depth requirements:

- `Literature Review and Theory` must do more than stack citations. It must synthesize named mechanisms and competing theoretical accounts and build at least one hypothesis or expectation bridge to the later empirical test. Rival explanations and boundary conditions should be integrated in journal-native theory prose; do not create standalone memo paragraphs such as "Rival explanations are central" or "There are also scope conditions" unless the target journal explicitly uses those labels.
- ASR-style theory sections should be organized with subheadings that name constructs, theoretical accounts, mechanisms, baseline expectations, and main hypotheses. A single undifferentiated theory/literature block is not acceptable for a full quantitative article unless a separate `## Hypotheses` section follows a substantial motivated theory section.
- Hypotheses or empirical expectations must be journal-native. For ASR/JMF-style quantitative articles and journal profiles whose theory section is labeled with hypotheses, explicit `H1`, `H2`, `H3` statements are allowed inside the theory section or a short `## Hypotheses` section. Each displayed hypothesis must be preceded by a short theoretical explanation that names the mechanism, rival account, or scope condition motivating the test. Bare proposal-style bullet lists or standalone `H1:` display blocks with no nearby theoretical motivation fail even when displayed hypotheses are allowed.
- For ASR/JMF-style quantitative articles, the manuscript must visibly carry the canonical Phase 2 hypothesis IDs or their exact journal-native equivalents in the Theory/Hypotheses block. Do not replace `H1`/`H2`/`H3` with vague "first expectation" prose when Phase 2 already assigned stable IDs.
- `Results` must do more than restate coefficients. It must identify the headline result, compare at least one secondary specification or diagnostic against that headline result, interpret uncertainty or weakness where relevant, and explicitly return the evidence to the theory or mechanism developed earlier in the paper.

Whole-section role gates enforce these obligations. `scripts/gates/introduction-argument-architecture-check.sh` checks whether the Introduction contains the puzzle/gap/theory/data/method/findings/roadmap moves. `scripts/gates/theory-structure-depth-check.sh` checks whether Theory/Background is organized by mechanisms, rival accounts, scope conditions, and testable expectations. `scripts/gates/discussion-adjudication-check.sh` checks whether Discussion adjudicates hypotheses/theory/rivals and states limitations and contribution. `scripts/gates/conclusion-contribution-support-check.sh` checks whether a required separate Conclusion synthesizes contribution without table/model reporting. `scripts/gates/cross-section-continuity-check.sh` checks whether the paper closes the promises made in the Introduction.

The Results section must contain visible evidence, not only narrative references. By default, a passing Phase 13 draft must include at least one rendered table block if any display-required tables exist in the active lock, and at least one rendered figure block if any locked figures exist in the active lock.

For quantitative empirical manuscripts, the Results flow must include a reader-facing descriptive statistics table for all modeled variables when the target journal/profile requires it or when such a table is produced by the analysis phase. In ASR/JMF-style manuscripts, this should normally be `Table 1` before the main regression table. Generated descriptive artifacts with `used_in_manuscript: false` are not enough; the table must be rendered or explicitly governed as an appendix/end-matter display and called out in Results prose.

For quantitative empirical manuscripts, the visible main empirical table must be a canonical regression table, not a registry extract. It must preserve the original regression-table architecture: models as columns, predictors/covariates as rows, standard errors or confidence intervals, p-values or significance markers where appropriate, sample size, model-fit or event-count information where relevant, and table notes for weights, clustering, fixed effects, sample restrictions, and covariate blocks. A row-per-spec table with fields such as `spec_id`, `model_id`, `hypothesis`, `estimate`, `std_error`, `p_value`, `n`, or `interpretation` is a verification registry and fails as the main Results table even if numerically correct.

Quantitative empirical drafts must display at least one locked artifact with role `main_regression_table` or `regression_table` and a regression-table display type. `sensitivity_regression_table` may support robustness discussion but cannot replace the main table unless the manuscript explicitly has no primary model and the blueprint records that exception. `tables/results-registry.csv` and model-ladder/focal-coefficient extracts must remain trace-only unless the research question is explicitly about the pipeline or table registry itself.

The visible main regression table must be obtained by transcluding (or rendering in place from) the locked HTML/TeX/Markdown artifact named in `results-locked/manifest.json` for `artifact_role = main_regression_table`. Phase 13 must NOT reconstruct the regression table from `tables/model-estimates.csv`, `tables/results-registry.csv`, or any other source CSV. The gate `scripts/gates/locked-artifact-transclusion-check.sh` verifies the source-path file matches the locked sha256; a hash mismatch indicates a Phase 13 builder silently rewrote Table 1 and routes back with reason `rebuild-from-locked-artifact`.

A focal-summary extract — a row-per-statistic table whose first column is `Statistic` and whose rows are `Focal adjusted association`, `p value`, `N` (or equivalent collapse to one focal coefficient) — is NOT acceptable as the main regression table even if it is wrapped in a locked HTML file. The Phase 18 quality engine's focal-summary detector and `scripts/gates/regression-table-export-check.sh` (regression-engine purity branch) reject focal-summary tables whose underlying renderer was a descriptive engine such as `datasummary_df()` or `tbl_summary()`.

The main regression display must also have a coherent model family shape. Do not collapse unrelated outcomes, robustness checks, interactions, and alternative predictor families into one sparse omnibus table with many empty cells. Split by outcome or model family, keep the main table focused, and move robustness or auxiliary models to appendix/end-matter tables when needed. The gate `scripts/gates/regression-table-family-shape-check.sh` rejects sparse omnibus displays.

Every produced manuscript Markdown (draft, final, submission) must declare a manuscript title before the first `##` section heading. Acceptable forms: a YAML frontmatter `title:` field, or a top-level `# <Title>` H1 line. A document whose first non-comment, non-blank line is `## Abstract` (or any other `##` heading) fails the gate `scripts/gates/manuscript-title-check.sh`.

For quantitative manuscripts, the Methods section (`## Data and Methods`, `## Data and Method`, `## Materials and Methods`, or `## Methods`) must use journal-native architecture rather than a generic methods blob. At minimum it must contain Data/Sample material (`### Data and Sample`, `### Data Source`, `### Analytic Sample`, or equivalent), a `### Variables and Measures` / `### Measures` / `### Measurement` subsection, and an analytic-strategy subsection (`### Analytic Strategy`, `### Statistical Analysis`, model-family headings such as `### Survival Analysis`, or equivalent). The gate `scripts/gates/journal-section-architecture-check.sh` enforces this architecture.

For quantitative empirical manuscripts, Data/Sample prose must report the sample descent rather than only the final denominator. The section must name the original data source, wave(s), population, unit of analysis, and original source size; then state the main eligibility restrictions, exclusion or missing-data rules, and final analytic sample size. If different main models use different denominators, the section must disclose each major analytic denominator before Results. The prose must also justify why the final analytic sample is appropriate for the research question, estimator, and measurement design. This rule follows journal practice in JMF/ASR-style quantitative papers, where readers should be able to reconstruct how the raw survey or administrative file became the estimation sample. The gate `scripts/gates/data-sample-flow-check.sh` enforces original-N, final-N, restriction/missingness, and justification disclosure.

For quantitative manuscripts, the Methods section must include a measurement bridge that operationalizes every modeled variable. Acceptable forms: a `### Measurement` (or `### Variable Construction` / `### Measures` / `### Variables and Measures`) subsection, a `<!-- measurement-bridge -->` tagged paragraph block, or a sequence of paragraphs that pair each variable's `display_label` with operationalization-style language and concrete coding/type/source detail drawn from the Phase 4 variable dictionary (`construct`, `levels_display`, `operationalization`). Within Variables and Measures, organize measures by role when the design has those roles: dependent variables/outcomes, independent variables/predictors/treatment/exposure, and control variables/covariates. Compact journal styles may use explicit role-labeled paragraphs rather than sub-subheadings, but the role distinction must be visible. The gate `scripts/gates/concept-to-measure-check.sh` enforces ≥80% modeled-variable coverage and rejects repeated `conceptualized as ... operationalized as ...` dictionary-template prose; nuisance controls (`province_indicators`, `survey_wave_indicators`) and interaction terms are excluded from the denominator.

For quantitative and computational empirical manuscripts, the Analytic Strategy must include method-family-specific technical detail in reader-facing prose. The manuscript should briefly introduce the method for social scientists, explain why it fits the outcome, data structure, and theoretical question, and then specify the actual model or computational pipeline used in the analysis. Fixed-effects, panel, and DiD designs need an estimating equation with real manuscript variable names, unit/time fixed effects, uncertainty estimator, and focal-coefficient interpretation. Survival models need the hazard/event/time-scale/censoring specification. Matching designs need treatment, propensity model, covariates, matching algorithm, balance/common-support diagnostics, and post-match analysis. OLS/logit/probit/count models need a formal estimating equation or explicit symbolic model specification with real variables, covariates, and inference details. A prose translation such as "the model equals an intercept plus..." is not enough for ASR/JMF/Demography-style quantitative manuscripts. Computational designs need an equally explicit method paragraph: the corpus or input data, unit of analysis, preprocessing or feature construction, model or algorithm, validation/performance or reliability evidence, error analysis or sensitivity checks, and how computational outputs become social-science measures, predictions, networks, classes, embeddings, simulations, or visual/audio features. The gate `scripts/gates/analytic-formula-specificity-check.sh` rejects placeholder equations, prose-only formula surrogates, algorithm-name-only method prose, and computational methods that omit validation and interpretation.

Reader-facing model labels must be journal-native. Use `Model 1`, `Model 2`, `Model 3` in prose and table headers, or compact labels such as `M1`, `M2`, `M3` when the target journal/table style calls for compact columns. Do not expose internal specification IDs such as `S1`, `S2`, or `S3` in visible manuscript prose or publication table headers; those identifiers belong in trace anchors, lock coverage, registries, and verification metadata only.

The draft must also obey the journal-calibrated display architecture, not merely include some evidence somewhere. `display_architecture` governs whether tables are embedded or end-matter, whether figures are embedded or separate-file style, whether a descriptive Table 1 is mandatory, whether editable text tables are required, how table titles and notes are positioned, and what numbering/callout style the Results prose must use.

The Results section must also integrate that evidence into prose. Every display-required table or figure must have:

- a visible numbered label such as `Table 1` or `Figure 2`;
- a prose callout in the Results section that explicitly references that label;
- a reporting verb in the callout sentence, such as `shows`, `presents`, `reports`, `plots`, `displays`, `illustrates`, `documents`, or `summarizes`.

Acceptable style:

```markdown
Table 2 shows the adjusted logit estimates for the primary specification.
Figure 1 presents the predicted probabilities from the interaction model.
```

Unnumbered descriptions, raw artifact paths, or evidence blocks that are never referenced in prose should fail.

The manuscript must be project-native. Phase 13 may cite with markdown citekeys for downstream rendering, but it may not:

- copy bibliography material from another project without explicit Phase 15 provenance disclosure;
- use a fake References section consisting only of citekeys or key summaries;
- treat figure captions without a visible image or visible locked-figure link as sufficient reader-facing figure display.
- expose audit-only workflow terms in reader-facing prose, including results locks, registries, manifests, phases, provenance mechanics, project slugs, drafting targets, pre-mortem/amendment labels, verification logs, AI conversation logs, or route-back language, unless the article's research question is explicitly about that workflow.

Every reader-facing Phase 11 locked artifact must have a manuscript trace anchor that includes both its source path and locked path, for example:

```markdown
<!-- LOCKED_ARTIFACT: tables/model-results.csv | LOCKED_PATH: results-locked/LOCK-20260429-001/tables/model-results.csv -->
```

Reader-facing artifact roles are `result_table`, `model_output`, `main_regression_table`, `sensitivity_regression_table`, `regression_table`, `descriptive_table`, `reader_facing_descriptive_table`, and `figure_file`. These require manuscript trace anchors. Provenance-only artifacts such as `results_registry`, execution reports, figure registries, post-execution reviews, runtime sanity files, and diagnostics must be covered in the manifest but do not appear in reader-facing prose.

Display-required artifact roles are `result_table`, `model_output`, `main_regression_table`, `sensitivity_regression_table`, `regression_table`, `descriptive_table`, `reader_facing_descriptive_table`, and `figure_file`. These require a second, visible manuscript display block in addition to the trace anchor:

- Tables (`result_table`, `model_output`, `main_regression_table`, `sensitivity_regression_table`, `regression_table`, `descriptive_table`, `reader_facing_descriptive_table`): render a visible markdown or HTML table near the surrounding prose. Hidden comments and prose references such as "Table 1 shows" are not enough.
- Figures (`figure_file`): render a visible figure block with caption text and a visible link or preview for the locked figure artifact. A markdown image preview is preferred when available, but a visible caption plus visible locked-figure link is acceptable when the canonical artifact is a PDF.

Use explicit display anchors so Phase 13 can verify visible evidence separately from traceability. Recommended forms are:

```markdown
<!-- DISPLAY_TABLE: tables/model-results.csv -->
<!-- DISPLAY_FIGURE: figures/main-effect.pdf -->
```

`results_registry` is provenance-only and must not be rendered as a reader-facing table by default. It may be discussed or displayed only when the article's substantive object is a registry/preregistration system; otherwise it belongs in trace comments, manifests, verification reports, and replication documentation rather than manuscript Results tables.

`manuscript/draft-manifest.json` must include:

- `verdict`: `PASS`
- `degraded`: `false`
- `drafting_engine`: object declaring `skill: scholar-write`, `mode: draft`, `section: full paper`, `auto_research_contract: phase_13`, `lock_enforced: true`, and `live_output_reads_forbidden: true`
- `journal_spec`: object declaring `skill: scholar-journal`, `mode: prepare`, `path: manuscript/journal-spec.json`, and SHA-256 for the journal spec
- `blueprint`: object declaring `path: manuscript/manuscript-blueprint.json` and SHA-256 for the manuscript blueprint
- `drafting_plan`: object declaring `path: manuscript/drafting-plan.json` and SHA-256 for the drafting plan
- `self_critique`: object declaring `path: manuscript/draft-self-critique.json`, SHA-256 for the critique, and `ready_for_verification: true`
- `lock_id`: active Phase 11 lock ID
- `selected_manuscript_hash`: SHA-256 for `manuscript/manuscript-draft.md`
- `lock_manifest_sha256`: Phase 11 manifest self-hash
- `source_hashes`: SHA-256 hashes for the lock manifest, Stage 1 verification, BibTeX file, literature/theory, research question, journal fit report, design blueprint, Phase 4 variable dictionary, analysis plan, and post-execution review
- `section_word_budget`: exact budget copied from `manuscript/journal-spec.json`
- `section_word_counts`: exact raw word counts for every required manuscript section
- `section_prose_word_counts`: exact prose-only word counts for every required manuscript section after excluding references, tables, figures, captions, declarations, trace anchors, HTML/Markdown table blocks, and image/link-only display blocks
- `budget_compliance`: target journal, total manuscript word count, `main_text_word_count`, total word range, abstract cap status, and section budget status
- `reader_facing_language`: status, workflow-jargon hit count, and evidence that internal audit terms are absent from visible manuscript prose
- `draft_quality_gate`: anti-trash gate with `status: PASS`, `anti_stub_checked: true`, `repetition_checked: true`, `section_substance_checked: true`, `locked_evidence_integrated: true`, `journal_fit_checked: true`, `polish_applied: true`, `repeated_sentence_limit`, `max_repeated_sentence_count`, and `section_quality` entries for every required section
- `draft_quality_gate`: must also report `substantive_paragraph_counts` for every required section and `results_prose_paragraph_count`
- `draft_quality_gate`: must also report `reader_facing_translation_checked`, `raw_variable_name_count`, `theory_synthesis_checked`, `results_comparison_checked`, and `results_theory_link_checked`
- `locked_result_coverage`: one entry for every Phase 11 locked artifact, with `source_path`, `locked_path`, `artifact_role`, `manuscript_anchor`, and `used_in_manuscript`; reader-facing artifacts must have `used_in_manuscript: true`, provenance-only artifacts must have `used_in_manuscript: false`
- `locked_result_coverage` entries for display-required artifacts must also include `display_anchor`, `display_status`, `display_type`, and `caption_text`
- `locked_result_coverage` entries for display-required artifacts must also include `display_label` and `results_callout`
- `display_status` must be one of `rendered_inline`, `rendered_appendix`, `preview_link`, or `journal_exempt`; `journal_exempt` requires a substantive journal-calibration rationale in `caption_text`
- `display_type` must identify the visible rendering form such as `markdown_table`, `html_table`, `regression_table_markdown`, `regression_table_html`, `regression_table_tex`, `regression_table_docx`, `markdown_image`, `html_image`, or `figure_link_block`
- `display_evidence`: manuscript-level summary with `status: PASS`, `table_display_count`, `figure_display_count`, `required_table_display_min`, `required_figure_display_min`, and `displayed_sources`
- `display_evidence`: must also report `results_table_callouts`, `results_figure_callouts`, and `all_display_items_called_out_in_results: true`
- `locked_result_claims`: row-level claims for every reader-facing locked CSV result source other than provenance-only registries, including `claim_id`, `row_index`, `spec_id`, `estimate`, `std_error`, `p_value`, `n`, and a manuscript anchor containing those values
- `numeric_reporting_policy`: exact copy of `manuscript/journal-spec.json.numeric_reporting_policy`
- `citation_plan`: BibTeX entry count, unique draft citation count, `all_citations_in_bib: true`, and `unresolved_citation_count: 0`
- `claim_discipline`: `phase9_constraints_used: true`, `overclaim_count: 0`, and all Phase 9 required disclosures present
- `blueprint_execution`: confirms the draft follows the blueprint headline claim, contribution stack, result hierarchy, and section obligations
- `content_alignment`: confirms the draft answers the research question, integrates the mechanism, and discusses limitations
- `ready_for_phase_14`: `true`

The verifier computes exact sentence repetition from the manuscript. A passing draft may not repeat any substantive sentence more than the declared `repeated_sentence_limit` times. This is a hard anti-stub check because long repeated paragraphs can otherwise satisfy word-count gates while still producing a low-quality paper.

Phase 13 fails if Phase 11 validation fails, if Phase 12 blueprint approval fails, if the draft uses stale source hashes, if the draft quality gate fails, if any reader-facing locked artifact lacks a trace anchor, if any display-required locked artifact lacks a visible display block, if the Results section lacks visible evidence, if quantitative empirical Results lack a canonical regression table, if a required descriptive statistics table is generated but not reader-facing, if a registry/model-ladder/focal-coefficient extract is used as the main empirical table, if a sparse omnibus table collapses unrelated model families, if display-required evidence is not explicitly called out in Results prose, if front matter lacks title/abstract/required keywords, if reader-facing text uses scientific notation or excessive floating precision against the journal numeric policy, if the abstract omits purpose/data/method/findings/contribution moves or references tables/figures, if visible manuscript content exposes raw dataset-native variable names that should have been translated through Phase 4 display fields, if locked CSV values are not present in the manuscript where claimed, if citations are unresolved, if required sections are thin or missing, if quantitative Methods lacks Data/Sample, Variables/Measures, and Analytic Strategy structure, if Data/Sample omits original data size, final analytic sample size, restriction/missingness logic, or justification for the analytic sample, if quantitative or computational Analytic Strategy omits method-family-specific technical detail using the actual variables/data pipeline, if quantitative Variables/Measures does not distinguish dependent variables, independent variables, and controls/covariates, if the literature/theory section does not synthesize mechanisms and rival explanations, if a full quantitative theory section has no subheadings or motivated hypotheses structure, if displayed hypotheses appear without nearby theoretical motivation, if the Theory/Hypotheses block drifts from canonical Phase 2 hypotheses, if Theory contains post-results language or the drafting plan gives Theory result-aware instructions, if the Results section does not compare specifications or return findings to theory, if the manuscript drifts from the approved blueprint, if Phase 9 claim constraints are violated, or if the draft manifest hash differs from the manuscript.

Length compliance is prose-only. A draft cannot satisfy the journal total word range by adding references, end-matter tables, figure captions, appendix boilerplate, declarations, lock comments, or other trace metadata. For full empirical articles, `budget_compliance.main_text_word_count` must be the sum of `section_prose_word_counts` over the approved article sections and must meet `journal-spec.json.total_word_range.min`.
