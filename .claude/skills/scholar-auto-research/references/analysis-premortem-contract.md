# Analysis Premortem Contract

Phase 7 stress-tests the analysis plan after pre-execution review and before any analysis execution. It must invoke the routed specialist premortem engine from Phase 3 `method_specialist_routing` and treat the `scholar-full-paper` analysis pre-mortem protocol as the baseline pattern: traffic-light dimensions, real reviewer provenance, falsification rules, reporting-depth requirements, and a hard go/no-go gate.

Required files:

- `review/analysis-premortem.json`
- `review/analysis-premortem.md`
- `review/analysis-premortem-fix-log.json`

Required independent reviewer roles:

- `identification`
- `measurement_missingness`
- `model_robustness`
- `interpretation_claims`

The premortem asks: if this analysis produced a misleading or low-quality paper, what likely failed? It must inspect Phase 3 design artifacts, Phase 4 measurement artifacts, `analysis/analysis-plan.md`, `analysis/spec-registry.csv`, `analysis/scripts-inventory.json`, and Phase 6 review artifacts.

Phase 7 is mandatory under `scholar-auto-research`. Any standalone skip behavior from the routed specialist skill is ignored here. Silent skipping is not allowed.

## Premortem Loop

1. `invoke_specialist_premortem`: record the routed `premortem_engine.skill`, `mode: premortem`, and `skip_premortem_ignored: true`.
2. `dispatch_premortem_reviewers`: run all four roles independently, using real peer-reviewer style agents/provenance rather than inline roleplay.
3. `traffic_light_review`: score the plan on identification, variable construction, sample restrictions, model specification, standard errors, missing data, robustness, power/effect-size realism, heterogeneity/multi-comparison policy, mechanism evidence, table/figure plan, preregistration/deviation alignment, and interpretive reach.
4. `null_falsification_review`: for every hypothesis represented in `analysis/spec-registry.csv`, record the observable null pattern that would count against the claim, whether it was pre-committed, and whether planned interpretation concedes the null.
5. `collect_risks`: build a risk register across identification, measurement, missing data, model fragility, robustness gaps, null/conflicting results, and overclaiming.
6. `mitigate_red_items`: fix red, high, major, critical, or blocker risks before execution. If mitigation changes the research question, literature/theory, design, data plan, or analysis plan, route back to the earliest affected phase.
7. `reporting_depth_review`: for any risk mitigated by estimator/specification/reporting choices, require diagnostic outputs, sensitivity range, failure-mode disclosure, and the manuscript/table/figure location where the diagnostic will be reported.
8. `record_fix_log`: write `review/analysis-premortem-fix-log.json`.
9. `go_no_go`: proceed to Phase 8 only if the decision is `GO`.

`analysis-premortem.json` must include:

- `verdict`: `PASS`
- `degraded`: `false`
- `ready_for_phase_8`: `true`
- `premortem_engine`: object with the routed specialist skill, `mode: premortem`, `auto_research_contract: phase_7`, and `skip_premortem_ignored: true`
- `iteration`: integer from 1 to 3; iteration 3 with any unresolved red/high/major/critical/blocker risk must halt for human decision
- `source_hashes`: SHA-256 hashes for `identification_strategy`, `model_specs`, `measurement_plan`, `variable_dictionary`, `analysis_plan`, `spec_registry`, `scripts_inventory`, `pre_execution_review`, `pre_execution_fix_log`, and `pre_execution_rereview`
- `reviewer_provenance`: list covering every reviewer, each with `reviewer_id`, `role`, `agent_name`, `task_invocation_id`, `dispatched_at_utc`, `model_id`, and `report_path`
- `reviewers`: list covering all required roles, each with `reviewer_id`, `role`, `agent_type`, `task_invocation_id`, `report_path`, `reviewed_inputs`, `risks`, and `verdict`
- `traffic_light_summary`: list of analysis-premortem dimensions with `dimension`, `verdict`, `lead_reviewer`, and `evidence`; no `RED` may remain unresolved at pass
- `null_falsification_table`: list covering every hypothesis id in `analysis/spec-registry.csv`, each with `hypothesis_id`, `null_pattern`, `precommitted`, `discussion_concedes_null`, and `status`
- `reporting_depth_checklist`: list for estimator/specification/reporting mitigations. Each item must include `risk_id`, `diagnostic_outputs`, `sensitivity_range`, `failure_mode_disclosure`, and `reporting_location`.
- `reviewed_scripts`: all planned scripts from `analysis/scripts-inventory.json`
- `reviewed_specs`: all specs from `analysis/spec-registry.csv`
- `reviewed_tests`: all planned tests from `analysis/scripts-inventory.json`
- `risk_register`: list of risks with `risk_id`, `domain`, `severity`, `description`, `evidence`, `affected_specs`, `affected_scripts`, `mitigation`, `status`, `owner_phase`, and `route_back_phase`
- `blocking_items_resolved`: `true`
- `unresolved_blocking_count`: `0`
- `accepted_limitations`: list of nonblocking limitations, each with `limitation_id`, `severity`, `rationale`, and `monitoring_plan`
- `decision_rules`: non-empty list of execution decision rules, each with `rule_id`, `condition`, and `action`
- `phase8_handoff`: object with `script_order`, `expected_outputs`, `expected_result_registry`, `expected_figure_registry`, and `halt_checks`
- `go_no_go`: object with `decision: GO`, `route_back_phase: null`, and `ready_for_phase_8: true`

Risk register domains must cover `design_plan_alignment`, `identification`, `measurement`, `missing_data`, `model_fragility`, `robustness`, `null_or_conflicting_results`, `claim_support`, and `execution_readiness`.

Red, high, critical, blocker, or major risks cannot be accepted as limitations. They must be mitigated or routed back. `accepted_limitations` is only for nonblocking minor or moderate risks.

Traffic-light verdicts may be `GREEN`, `YELLOW`, or `RED`. A `RED` dimension may appear in the final JSON only when it has `resolution_status: resolved` and a matching fix-log entry. Unresolved `RED` dimensions block Phase 8.

The null-falsification table is mandatory even for descriptive or associational studies. The null pattern can be a descriptive or associational pattern, but it must be observable and specific enough to constrain later manuscript prose.

Reporting-depth checklist rows are mandatory for any risk whose mitigation depends on a model choice, estimator choice, robustness specification, diagnostic output, table/figure reporting, or interpretation constraint. A mitigation that says "report this carefully" without naming diagnostics, sensitivity range, failure-mode disclosure, and reporting location is not complete.

`analysis-premortem-fix-log.json` must include:

- `required_fixes_completed`: `true`
- `unresolved_blocking_count`: `0`
- `final_verdict`: `PASS`
- `fixed_risks`: list of fixed risk records

If no blocking risks were found, `fixed_risks` may be empty. If fixes were required, every fixed risk must include `risk_id`, `status`, `action_taken`, and `affected_files`.

Phase 7 fails if any execution artifacts already exist. Execution belongs to Phase 8.

Markdown summaries must not contradict JSON pass status. If markdown says a red, major, critical, or blocking risk remains open, Phase 7 fails even when JSON says `PASS`.

Expected routed skills:

- quantitative / demographic / survey / observational / experimental -> `scholar-analyze`
- computational -> `scholar-compute`
- qualitative -> `scholar-qual`
- linguistic -> `scholar-ling`
- mixed-methods -> the declared `primary_execution_skill` from Phase 3, with supporting skills preserved in routing metadata
