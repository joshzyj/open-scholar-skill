# Manuscript Quality Gate

Phase 18 targets the failure mode where a paper is technically consistent but still poor scholarship.

The governing principle for the full workflow is simple: a manuscript that passes contracts but is not plausibly publishable in its target journal should still fail. Contract completion is necessary, not sufficient.

## Engine

Use `scholar-respond` in `simulate` mode as the review engine. Reuse its strong practices:

- journal-aware panel selection;
- independent reviewer agents;
- at least one unprimed senior/editorial reviewer;
- severity-confidence matrix;
- revision roadmap.

Do not inherit weak orchestration from `scholar-full-paper`: Phase 18 is a gate, not advisory polish. It must not silently revise the manuscript or advance a paper with unresolved major defects.

## Required Reviewer Panel

Minimum reviewers:

- `methods-evidence`
- `theory-contribution`
- `senior-editor`
- `interpretive-skeptic`

Add a fifth reviewer when the manuscript is computational, qualitative, demographic, linguistic, mixed-methods, or otherwise journal-specialized.

The fifth reviewer must be method-specialized rather than generic. Expected specialization:

- computational -> reviewer explicitly calibrated to `scholar-compute`-type risks
- qualitative -> reviewer explicitly calibrated to `scholar-qual`-type risks
- linguistic -> reviewer explicitly calibrated to `scholar-ling`-type risks
- demographic / quantitative family -> reviewer explicitly calibrated to `scholar-analyze`-type empirical interpretation risks

Each reviewer report must be saved under `quality/agents/` and record reviewer id, role, agent name (must start with `peer-reviewer-`), task invocation id (must be a real dispatched id, not a placeholder like `tbd` or `todo`), reviewed inputs, score vector, decision, findings, and whether the reviewer was primed. The file itself must include role and task identifiers so it can be audited independently of the JSON wrapper. At least one senior/editorial reviewer must be unprimed.

`quality/manuscript-quality.json` must also include `reviewer_independence`, `adversarial_review_coverage`, and `method_specialist_review` objects. These are not narrative summaries: they must record whether reports were materially distinct, whether every report included concrete manuscript/artifact locators and risk or robustness concerns, and whether a method-specialized reviewer was required and used.

For quantitative empirical manuscripts, `quality/manuscript-quality.json` must also include `regression_table_audit`. This object must record `status`, `canonical_main_regression_table_present`, `registry_table_used_as_main_display`, `model_columns_as_columns`, `predictor_rows_as_rows`, `standard_errors_or_intervals_present`, `sample_size_present`, `reader_facing_labels_used`, and `notes_cover_design_features`. The status must be `PASS`, the canonical table flag must be true, the registry-as-main-display flag must be false, and `reader_facing_labels_used` must mean both concept-level variable labels and model labels such as `Model 1`/`Model 2` or `M1`/`M2`, not internal `S1`/`S2` specification IDs.

Self-reported `regression_table_audit` is necessary but not sufficient. Phase 18 must additionally COMPUTE shape evidence from the artifacts:

- The focal-summary detector inside `auto-research-verify.sh` (`registry_like_table_display_hits`) parses every embedded markdown table header and rejects focal-summary patterns whose first column is `Statistic` and whose visible rows collapse to one focal coefficient (e.g., headers `{Statistic, Focal adjusted association, p value, N}`).
- `scripts/gates/regression-table-export-check.sh` (regression-engine purity branch) RED-fails when `tables/table-main-regression.*` is rendered solely by descriptive engines such as `datasummary_df()`, `datasummary()`, or `tbl_summary()` without a regression-grade engine call (`modelsummary()`, `msummary()`, `stargazer()`, `texreg()`, `huxreg()`, `tbl_regression()`, `etable()`).
- `scripts/gates/locked-artifact-transclusion-check.sh` RED-fails when any artifact whose `artifact_role = main_regression_table` in `results-locked/manifest.json` no longer hash-matches its recorded sha256 — preventing Phase 13/19 from silently rebuilding Table 1 from CSV.
- `scripts/gates/regression-table-family-shape-check.sh` RED-fails sparse omnibus tables with many model columns and many empty predictor cells. Split unrelated outcomes, robustness checks, and model families rather than turning the model ladder into one publication table.
- `scripts/gates/descriptive-table-display-check.sh` RED-fails when descriptive tables exist or are journal-required but remain hidden in manifests instead of appearing as a reader-facing descriptive display.
- `scripts/gates/front-matter-check.sh`, `scripts/gates/abstract-boilerplate-check.sh`, `scripts/gates/journal-section-architecture-check.sh`, `scripts/gates/introduction-argument-architecture-check.sh`, `scripts/gates/theory-hypothesis-continuity-check.sh`, `scripts/gates/theory-structure-depth-check.sh`, `scripts/gates/methods-role-subsections-check.sh`, `scripts/gates/analytic-strategy-quality-check.sh`, `scripts/gates/analytic-formula-specificity-check.sh`, `scripts/gates/discussion-adjudication-check.sh`, `scripts/gates/conclusion-contribution-support-check.sh`, `scripts/gates/cross-section-continuity-check.sh`, `scripts/gates/manuscript-artifact-leakage-check.sh`, `scripts/gates/citation-cluster-quality-check.sh`, `scripts/gates/figure-style-source-check.sh`, and `scripts/gates/concept-to-measure-check.sh` RED-fail missing titles/keywords, display callouts or defensive limitation boilerplate in abstracts, generic methods blobs, weak introductions, post-results theory leakage, memo-style rival/scope paragraphs, thin theory/literature structure, canonical-hypothesis drift, missing dependent/independent/control role structure, prose-only formula surrogates, weak analytic-strategy prose, discussion sections that do not adjudicate theory/rivals, conclusions that reopen model/table reporting, cross-section promise drift, internal artifact leakage, oversized citation clusters, unpackaged/unapplied shared figure styles, and under-80% measurement coverage.

If any of these checks RED-fails, Phase 18 must NOT issue a PASS verdict regardless of the self-reported `regression_table_audit.status` or reviewer scores.

Reviewer reports must be adversarial and non-boilerplate. Each report must:

- cite at least one concrete manuscript section, line reference, table, figure, claim ID, or artifact path;
- name at least one risk, limitation, falsification check, robustness demand, rival explanation, or desk-reject concern, even when recommending proceed;
- explain why the score is justified for that role rather than only saying the manuscript is coherent;
- differ materially from the other reviewer reports in wording and role-specific focus.

Each reviewer report must additionally carry two structured fields that test intellectual quality directly rather than via mechanical coverage:

- `contribution_locator` — the reviewer's independent identification of the manuscript's contribution. Required keys: `sentences` (a nonempty list of verbatim sentences quoted from the manuscript, each at least 10 words long), `section` (the section the sentences come from), `clarity_score` (0–10; can the reviewer find the contribution?), `specificity_score` (0–10; is the claim concrete or boilerplate?). Both scores must be at least 7. The four reviewer agents quote independently — they do not see each other's locators while drafting.
- `rival_adjudication` — the reviewer's audit of rival explanations. Required keys: `rivals_in_lit_review` (a list of rival/alternative explanations the lit review names), `rivals_addressed_in_discussion` (a list of those the discussion explicitly adjudicates), `missing_adjudications` (a list of rivals named but never adjudicated), `adjudication_quality_score` (0–10; how convincingly does the discussion address the rivals it does engage?). The score must be at least 7.

## Score Dimensions

Score each dimension on 0-10:

- `contribution`
- `rq_answer`
- `argument_coherence`
- `theory_results_integration`
- `limitation_candor`
- `journal_fit`
- `abstract_intro_discussion_consistency`
- `substantive_conclusion_support`
- `prose_quality`
- `reviewer_consensus`

Pass thresholds:

- every dimension >= 7;
- mean score >= 8;
- no CRITICAL or MAJOR open finding;
- no reviewer decision of `REJECT` or `MAJOR_REVISION`;
- markdown summary agrees with the JSON decision;
- every reviewer's `contribution_locator.clarity_score` and `contribution_locator.specificity_score` >= 7;
- every reviewer's `rival_adjudication.adjudication_quality_score` >= 7;
- at least one pair of reviewers must independently quote contribution sentences with Jaccard token overlap >= 0.7 (cross-reviewer consensus on what the contribution IS);
- no rival explanation may be named in the lit review by >=2 reviewers AND simultaneously flagged as un-adjudicated in the discussion by >=2 reviewers.

## Non-Overridable Blockers

No user override is allowed for:

- unsupported empirical claims;
- fabricated or unverified citations;
- unresolved critical verification errors;
- no coherent answer to the research question;
- manuscript claims that contradict the active results lock;
- unresolved ethics, data availability, or replication blockers.
- raw citekeys or unrendered citation syntax in final/submission products;
- missing required title, empirical abstract, or keywords in ASR/JMF/AJS/Demography/Social Forces-style front matter;
- fake References sections that only list citekeys or key summaries;
- unresolved dataset-design, weight, clustering, panel, or denominator decisions for structured secondary data;
- high missingness, structural skip patterns, or complete-case restrictions without post-restriction diagnostics and sensitivity planning;
- outcome families that require a model ladder but only receive a single convenient headline estimator;
- omnibus citation clusters that treat a source inventory as claim support;
- duplicated rendered author-year citations inside a single citation cluster, such as `Author 2021, 2021`;
- reviewer reports that are generic, duplicated, pass-only, or detached from concrete manuscript locations;
- missing reader-facing figures when the Phase 13 draft manifest marked figures as display-required;
- missing reader-facing descriptive statistics table when the target journal/profile requires one or when descriptive artifacts were produced for a quantitative manuscript;
- missing canonical reader-facing regression tables when the manuscript is quantitative empirical;
- sparse omnibus regression tables that collapse unrelated outcomes, robustness checks, interactions, and auxiliary model families into one many-column display;
- any row-per-spec registry, model ladder, focal-coefficient extract, results registry, or verification table used as the main empirical Results table;
- visible internal specification IDs such as `S1`, `S2`, or `S3` used as model labels in prose or tables;
- workflow, phase, lock, manifest, registry, provenance, artifact, or verification vocabulary leaking into final or submission reader-facing prose;
- project metadata blocks, project slugs, manuscript word targets, pre-mortem/amendment labels, verification logs, or AI conversation logs leaking into reader-facing prose;
- weak empirical abstracts that omit the research purpose/theoretical importance, data, method, headline findings, or contribution/implication;
- abstract references to display artifacts such as `Table 1` or `Figure 1`;
- abstract boilerplate that says the estimates are "not causal," "observational associations only," or "evidence is associational" instead of using the abstract for purpose, data/design, findings, and contribution;
- manuscript prose that exposes internal artifacts such as `variable dictionary`, `reader-facing translations`, `results registry`, `spec registry`, `source hashes`, or `locked artifact`;
- analytic-strategy sections that list adjustment facts without explaining estimator/inference, model sequence, missing-data and denominator rules, survey-weight/design decisions, robustness checks, and claim boundaries in normal journal prose;
- OLS/logit/probit/count analytic-strategy sections that use prose translations such as "equals an intercept plus" instead of a formal estimating equation or symbolic model specification with the actual outcome, focal predictors, controls, and inference details;
- Methods sections in quantitative manuscripts that lack journal-native Data/Sample, Variables/Measures, and Analytic Strategy structure;
- Variables/Measures prose that does not distinguish dependent variables/outcomes, independent variables/predictors, and controls/covariates when those roles appear in the model specification;
- concept-to-measure coverage below 80% for modeled variables, excluding nuisance fixed effects and interaction terms;
- displayed `H1/H2/H3` hypotheses that appear as bare proposal-style checklists with no nearby theoretical motivation. Displayed hypotheses are allowed when the target journal/profile uses a theory-and-hypotheses structure, but each displayed hypothesis must follow a short mechanism, rival-account, or scope-condition explanation;
- Theory sections that rewrite, weaken, or reverse canonical Phase 2 hypotheses after seeing results; result-aware phrases such as "the evidence revises the opening expectation," "positive estimates," "null-compatible," coefficient/model/table language, or drafting-plan instructions that import locked findings into Theory are blockers rather than prose-style issues;
- reader-facing tables or figures that expose raw dataset variable names or machine labels instead of concept-level labels;
- literature/theory sections that cite heavily but do not synthesize;
- literature/theory sections that omit rival explanations or scope conditions;
- introductions that do not establish puzzle/importance, literature gap, theory/contribution, data/case, method, headline findings, and roadmap;
- discussions that only restate coefficients without limitations, scope, or contribution.
- discussions that do not adjudicate the paper's theory, hypotheses or expectations, and rival explanations;
- separate conclusions that lack a substantive contribution or reopen table/model/coefficient reporting;
- introduction, discussion, and conclusion sections that do not close the same argument.
- results sections that report coefficients without comparing specifications or returning the evidence to theory.
- no cross-reviewer consensus on the manuscript's contribution sentences (no reviewer pair clears the Jaccard 0.7 threshold on `contribution_locator.sentences`); a manuscript whose contribution cannot be independently located by two reviewers is intellectually unclear regardless of coverage scores.
- a rival explanation named in the lit review by two or more reviewers and simultaneously flagged in `rival_adjudication.missing_adjudications` by two or more reviewers; naming a rival without adjudicating it converts the lit review into a checklist rather than an argument.

Phase 18 must actively detect the failure mode where a manuscript is technically consistent yet intellectually thin. At minimum, reviewer findings must explicitly consider:

- whether each core section is more than a one-paragraph template;
- whether the literature review synthesizes rather than stacks citations;
- whether the literature review names rival explanations and scope conditions instead of presenting a single-path theory summary;
- whether the discussion interprets findings, states limitations, and explains contribution;
- whether tables and figures are integrated into the argument rather than dumped into the Results section.
- whether the main empirical table is an original publication regression table rather than a registry/model-ladder extract;
- whether the Results section actually says what each numbered table or figure shows or presents, rather than leaving evidence uninterpreted;
- whether reader-facing tables, figures, captions, and prose translate raw dataset variables into concept-level language drawn from the Phase 4 display semantics;
- whether the Results section compares headline and secondary specifications instead of listing estimates one by one;
- whether the Results section returns the empirical pattern to the paper's theoretical mechanism or rival explanations;
- whether numeric reporting is journal-calibrated rather than exposing raw registry precision or scientific notation in reader-facing prose;
- whether independent reviewers can locate the same contribution sentences in the manuscript (panel agreement on what the contribution IS, not just that one exists);
- whether each rival explanation named in the lit review receives an explicit adjudication sentence in the discussion, not merely a parenthetical mention.

Phase 18 must also run an independent manuscript-substance audit before trusting reviewer scores. The audit recomputes prose-only word counts from `manuscript/manuscript-draft.md`, using the Phase 13 approved article sections and excluding references, tables, figures, captions, declarations, trace anchors, workflow comments, and display blocks. For full empirical articles, the recomputed `main_text_word_count` must meet the target journal's `total_word_budget.min`, each non-abstract section must reach at least 85% of its journal-calibrated `target_words`, and the recomputed values must match `manuscript/draft-manifest.json.section_prose_word_counts` and `budget_compliance.main_text_word_count`. A full regression table, clean citations, or high reviewer scores cannot override this audit.

## Route-Back Rules

If Phase 18 fails, write a structured FAIL report with `source_phase: "18"`, nonempty `findings[]`, and the earliest valid `route_back_phase`.

- manuscript blueprint, argument hierarchy, or whole-paper coherence mismatch: route back to Phase 12;
- manuscript prose, organization, abstract/intro/discussion mismatch: route back to Phase 13;
- verification or traceability gap: Phase 14;
- citation, claim support, or missing locator: Phase 15;
- ethics, AI disclosure, IRB, COI, or data availability: Phase 16;
- replication/package/reproducibility issue: Phase 17;
- analysis/design/data defects: route to the earliest true source phase, not Phase 18.

Phase 18 must not directly rewrite the manuscript. Routed revision may invoke `scholar-write revise` or the appropriate upstream skill, then rerun downstream gates.
