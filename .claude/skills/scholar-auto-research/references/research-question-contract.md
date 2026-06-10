# Research Question Contract

Phase 1 produces the research question, target journal calibration, and selection rationale that the rest of the pipeline must answer.

Engine routing:

- Use `scholar-idea` when the user provides a broad topic, puzzle, rough research question, or theoretical interest.
- Use `scholar-brainstorm` when the user provides data files, codebooks, questionnaires, data dictionaries, published papers, abstracts, or other materials without a clear research question.
- Both engines must write the same normalized Phase 1 artifacts. Downstream phases consume the normalized artifacts, not engine-specific prose.
- When `engine` is `scholar-brainstorm`, Phase 1 must also preserve a brainstorm provenance record. DATA mode has additional empirical-signal requirements.

Required files:

- `idea/candidate-rqs.json`
- `idea/rq-evaluation-panel.json`
- `idea/journal-fit.json`
- `idea/rq-selection-rationale.md`
- `idea/research-question.json`
- `idea/research-question.md`

Conditional files for `scholar-brainstorm`:

- `idea/brainstorm-mode.json`
- `idea/brainstorm-report.md`
- `idea/brainstorm-summary.md`

Additional conditional files for `scholar-brainstorm` DATA mode:

- `idea/variable-inventory.json`
- `idea/empirical-signal-table.csv`
- `scripts/brainstorm-signal-tests.R`
- `scripts/brainstorm-signal-tests.log`

`idea/research-question.json` must include:

- `verdict`: `PASS`
- `engine`: `scholar-idea` or `scholar-brainstorm`
- `engine_provenance`: object with `task_invocation_id`, `invoked_at_utc`, `input_artifacts`, and `output_artifacts`
- `input_mode`: `idea`, `data`, `materials`, or `paper`
- `selected_rq_id`: ID of the selected candidate
- `selected_rq`: the exact research question
- `x`: focal predictor, treatment, exposure, condition, or explanatory construct
- `y`: focal outcome, response, or phenomenon to explain
- `directional_relation`: expected relationship or estimand direction; use `exploratory` only with rationale
- `mechanism`: why X should relate to Y
- `confounders`: non-empty list of likely threats or adjustment concepts
- `scope`: object with population, place, time, and unit
- `target_journal`: object with primary target, journal family, fit rationale, method bar, theory bar, and desk-reject risks
- `paper_type`: article type
- `method_orientation`: expected design orientation
- `recommended_dataset`: named dataset or data strategy
- `claim_strength`: `causal`, `associational`, `descriptive`, or `exploratory`
- `rationale`: why the question is worth answering
- `selection_evidence`: object summarizing candidate count, panel consensus, fatal-flaw status, data feasibility, novelty risk, and journal fit
- `ready_for_phase_2`: `true`

`candidate-rqs.json` must include at least three candidates. Each candidate must include:

- `rq_id`
- `question`
- `x`
- `y`
- `mechanism`
- `confounders`
- `scope`
- `claim_strength`
- `recommended_dataset`
- `novelty_risk`
- `data_feasible`
- `fatal_flaw`

For `scholar-brainstorm` DATA mode, each selected or shortlisted candidate must also include:

- `empirical_signal.status`: `STRONG`, `MODERATE`, `WEAK`, `NULL`, `UNTESTABLE`, `MECHANISM PLAUSIBLE`, `MODERATION DETECTED`, or `ERROR`
- `empirical_signal.effect_size`
- `empirical_signal.p_value`
- `empirical_signal.n_obs`
- `empirical_signal.selection_allowed`
- `empirical_signal.interpretation`

DATA-mode selection rules:

- `STRONG`, `MODERATE`, `MECHANISM PLAUSIBLE`, and `MODERATION DETECTED` are selection-eligible by default.
- `WEAK` is selection-eligible only with a written theory/journal justification.
- `NULL`, `UNTESTABLE`, and `ERROR` are not selection-eligible by default.
- A `NULL`, `UNTESTABLE`, or `ERROR` selected RQ requires an explicit `user_override` object with `confirmed: true`, `reason`, and `pursue_despite_signal: true`.
- The empirical signal is exploratory and bivariate; it must guide feasibility/usefulness ranking but must not be described as causal evidence.

`rq-evaluation-panel.json` must include at least five independent review roles:

- `theorist`
- `methodologist`
- `domain_expert`
- `journal_editor`
- `devils_advocate`

The panel must select the same `selected_rq_id` as `research-question.json`, must not mark the selected RQ with a fatal flaw, and must declare readiness for selection.

`journal-fit.json` must include:

- `verdict`: `PASS`
- `target_source`: `user_provided` or `inferred`
- `selected_rq_id`
- `primary_target`
- `journal_family`
- `paper_type`
- `journal_profile_resolution`: object with `requested_journal`, `resolved_profile_name`, `profile_origin`, `profile_source_engine`, `source_strategy`, `web_lookup_attempted`, `fallback_used`, `fallback_reason`, `journal_structure`, and `display_architecture`
- per-candidate journal fit scores
- `ready_for_phase_2`: `true`

`journal_profile_resolution` rules:

- `profile_origin` must be one of `built_in`, `imported_custom`, or `fallback_asr`.
- `profile_source_engine` must be `scholar-journal`.
- `source_strategy` must be `built_in_catalog`, `web_fetched_profile`, or `asr_fallback`.
- `journal_structure` and `display_architecture` must already be concrete enough for downstream blueprinting and verification.
- If the requested journal is outside the built-in journal catalog, `profile_origin` must be `imported_custom` unless the workflow explicitly falls back to `ASR`.
- `imported_custom` may not be used to bypass a journal that is already covered by the built-in catalog. Built-in journals must remain `built_in`.
- If `profile_origin = fallback_asr`, then `primary_target` must be `American Sociological Review`, `resolved_profile_name` must be `American Sociological Review`, `fallback_used` must be `true`, and `fallback_reason` must explain why the requested journal could not be resolved.
- For `fallback_asr`, generate the resolution from `scripts/emit-journal-profile-resolution.py` or the shared `references/journal-profile-resolution-templates.json`; do not hand-author a generic fallback structure.
- If `profile_origin = imported_custom`, then `web_lookup_attempted` must be `true` and `fallback_used` must be `false`.

The JSON must not use placeholders such as `TBD`, `unknown`, or `to be determined`. Phase 1 should fail before literature review if the question cannot identify X, Y, mechanism, and scope.

`method_orientation` must be specific enough to route the project into a recognized method family for downstream execution. Acceptable families are:

- quantitative / demographic / survey / observational / experimental
- computational social science
- qualitative
- linguistic / sociolinguistic
- mixed-methods

The value may be a richer phrase, but it must clearly signal at least one of those families. Examples that should pass include `observational panel quantitative`, `computational text-as-data`, `qualitative interview study`, `sociolinguistic variation analysis`, and `mixed-methods survey plus interview design`.

Phase 1 must not conduct the full literature review. It does enough novelty, feasibility, and journal-fit checking to avoid selecting a bad question. Phase 2 remains responsible for systematic literature/theory development and the 30+ must-cite corpus.

For `scholar-brainstorm` DATA mode, Phase 1 must not silently select a no-signal question. It may show such questions to the user, but selecting one requires a recorded user override and the caveat must carry forward in `selection_evidence`.
