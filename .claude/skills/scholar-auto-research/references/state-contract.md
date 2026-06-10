# State Contract

State lives at:

`<project>/.auto-research/state.json`

State must record:

- contract hash
- completed phases
- phase completion timestamps
- artifact paths and hashes
- selected manuscript hash where applicable
- stale phases when hashes change
- scholar-init import metadata when safety is inherited
- persistent run mode (`unset`, `autonomous`, or `human_in_loop`)
- pending human-in-the-loop transitions and append-only transition decisions

Rules:

- If state update fails, the phase fails.
- `next` is determined by the contract, not by prose headings.
- If a recorded artifact hash changes, the completed phase and downstream dependent phases are stale.
- If a verification phase emits a structured `FAIL` report with `route_back_phase`, run `auto-research-state.sh route-back "$PROJ" <report-json>`. This marks the target phase and all completed downstream phases stale, preserves finding IDs and fix instructions, and increments retry counts for repeated findings.
- Default submission completion is Phase 20. The next token after Phase 20 is `DONE`.
- If run mode is `unset`, `next` returns `NEXT_PHASE=MODE_SELECTION` and `complete` must fail with `RUN_MODE_REQUIRED`.
- In `autonomous` mode, `next` and `complete` follow the contract order without phase-boundary approval.
- In `human_in_loop` mode, completing a phase creates `pending_transition` for the next non-DONE phase. While this transition is pending, `next` returns `APPROVAL_REQUIRED=1` and `complete` for the next phase must fail with `HUMAN_DECISION_REQUIRED`.

## Run Mode And Human Decisions

Every project must choose a run mode before Phase 0 can be completed. The state command is:

```bash
bash .claude/skills/scholar-auto-research/scripts/auto-research-state.sh set-mode "$PROJ" autonomous
bash .claude/skills/scholar-auto-research/scripts/auto-research-state.sh set-mode "$PROJ" human-in-loop
```

`autonomous` preserves the normal forward pipeline. `human_in_loop` records a user decision at each phase boundary. After a phase completes, state stores:

- `pending_transition.from_phase`
- `pending_transition.to_phase`
- `pending_transition.reason`
- `pending_transition.status: pending`

The operator must record a decision before completing the next phase:

```bash
bash .claude/skills/scholar-auto-research/scripts/auto-research-state.sh decision "$PROJ" <next_phase> approve
bash .claude/skills/scholar-auto-research/scripts/auto-research-state.sh decision "$PROJ" <next_phase> revise
bash .claude/skills/scholar-auto-research/scripts/auto-research-state.sh decision "$PROJ" <next_phase> pause
bash .claude/skills/scholar-auto-research/scripts/auto-research-state.sh decision "$PROJ" <next_phase> switch-autonomous
```

Only `approve` and `switch-autonomous` clear `pending_transition`. `revise` and `pause` remain blocking decisions so the agent cannot silently advance. Route-back and hash-staleness transitions also create approval gates in `human_in_loop` mode.

## Route Back

Route-back is used when a later quality gate finds an error that belongs to an earlier phase.

```bash
bash .claude/skills/scholar-auto-research/scripts/auto-research-state.sh route-back "$PROJ" "$PROJ/verify/manuscript-verification.json"
```

The report must have `verdict: FAIL`, a valid `route_back_phase`, and nonempty open `findings[]`. Each finding must include `finding_id`, `route_back_phase`, and `status: open`.

After route-back:

- `next` returns the route-back target.
- The target and completed downstream phases are listed in `stale_phases`.
- `active_route_back` stores the source report, finding IDs, and retry maximum.
- Running route-back again with the same finding ID increments its retry count.
- Completing the target phase clears only that phase from `stale_phases`; downstream stale phases must still be rerun.
- After all invalidated downstream phases are completed, `active_route_back` is cleared.

## Scholar Init Import

If a project was initialized with `scholar-init`, run:

```bash
bash .claude/skills/scholar-auto-research/scripts/auto-research-state.sh import-init "$PROJ"
```

This imports:

`$PROJ/.claude/safety-status.json`

into:

`$PROJ/safety/safety-status.json`

Import blocks if any source value starts with `NEEDS_REVIEW`, `HALT`, or `HALTED`. `LOCAL_MODE`, `ANONYMIZED`, and `CLEARED` are normalized into a Phase 0 artifact, with original statuses preserved under `status_by_file`.

`OVERRIDE` is allowed only when the source value includes a non-empty rationale after a colon, for example `OVERRIDE: public synthetic demo file`. Bare `OVERRIDE` blocks Phase 0.

If no files were scanned, the normalized artifact must set `no_data_declared: true`; otherwise `files_scanned: 0` is treated as an ambiguous safety gap.
