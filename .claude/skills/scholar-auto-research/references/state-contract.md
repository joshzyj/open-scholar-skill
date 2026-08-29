# State Contract

State lives at:

`<project>/.auto-research/state.json`

State must record:

- contract hash
- completed phases
- phase completion timestamps
- artifact paths and hashes
- run nonce, verifier hash, exact contract-derived required-output map, and dynamic auxiliary-input hashes
- selected manuscript hash where applicable
- stale phases when hashes change
- scholar-init import metadata when safety is inherited
- persistent run mode (`unset`, `autonomous`, or `human_in_loop`)
- pending human-in-the-loop transitions and append-only transition decisions
- locked review assurance profile, per-review-phase attempt epochs,
  append-only registered session/completion/abort events, and evidence selected
  by each completed review phase
- allowlisted contract-migration history, including exact predecessor/target
  schemas and hashes plus operator, reason, and invalidated phases

Rules:

- If state update fails, the phase fails.
- Every state command holds the same OS advisory lock, so readers cannot observe provisional completion and writers cannot lose updates. `complete` hashes/parses one contract generation, snapshots the verifier plus exact outputs and inputs, requires the verifier's post-semantic descriptor to match that entry generation, and rechecks contract/verifier/artifacts before and after publication. Any post-publication observation failure restores the exact prior state bytes. Project-local receipts/stamps are post-commit audit-only and are never read as authority.
- Review lifecycle commands acquire the project state lock first and then a
  phase-specific lock under `.auto-research/review-evidence-locks/`. Lock files
  stay outside hashed session roots. `review-begin` registers reservations
  before outputs exist; `review-complete` accepts only reserved, current-epoch,
  byte-bound reports/traces after a driver-observed successful return;
  `review-abort` prevents a partial session from becoming authority.
- `next` is determined by the contract, not by prose headings.
- If a recorded artifact hash changes, the completed phase and downstream dependent phases are stale.
- If a verification phase emits a structured `FAIL` report with `route_back_phase`, run `auto-research-state.sh route-back "$PROJ" <report-json>`. This marks the target phase and all completed downstream phases stale, preserves finding IDs and fix instructions, and increments retry counts for repeated findings.
- Default submission completion is Phase 20. The next token after Phase 20 is `DONE`.
- If run mode is `unset`, `next` returns `NEXT_PHASE=MODE_SELECTION` and `complete` must fail with `RUN_MODE_REQUIRED`.
- In `autonomous` mode, `next` and `complete` follow the contract order without phase-boundary approval.
- In `human_in_loop` mode, completing a phase creates `pending_transition` for the next non-DONE phase. While this transition is pending, `next` returns `APPROVAL_REQUIRED=1` and `complete` for the next phase must fail with `HUMAN_DECISION_REQUIRED`.
- Safety re-import, route-back, relevant hash staleness, and assurance-profile
  changes advance review attempt epochs. Old sessions cannot be replayed even
  when their inputs later return to byte-identical content.

## Review Evidence And Assurance

State schema `1.3.0` stores `review_assurance_profile` (`normal` or `strict`),
`review_attempt_epochs`, and `review_evidence_history`. Normal mode accepts the
portable `process_recorded` guarantee; strict mode requires every host claim
listed by the phase policy to be verified. Changing profiles is stateful and
invalidates completed affected review phases and their completed downstream
phases:

```bash
bash "${_AR_SKILL}/scripts/auto-research-state.sh" set-review-profile \
  "$PROJ" strict --operator "<name>" --reason "require host-verified receipts"
```

Review sessions are valid only for the authoritative next phase. Canonical
phase JSON selects the registered session for each declared round; selection
does not create authority by itself. Full lifecycle and claim boundaries are in
`review-evidence-contract.md`.

## Contract Migration

Contract drift fails closed. During drift, ordinary state-driving mutations
remain blocked; only an exactly allowlisted migration may update state:

```bash
bash "${_AR_SKILL}/scripts/auto-research-state.sh" migration-status "$PROJ"
bash "${_AR_SKILL}/scripts/auto-research-state.sh" migrate-contract \
  "$PROJ" "<eligible-id-from-migration-status>" \
  --operator "<name>" --reason "adopt registered portable review evidence"
```

Use the single exact ID in `eligible_migration_ids`; do not reuse an ID from a
different predecessor generation. The migration verifies the exact predecessor state schema/contract hash and
the installed target hash, then atomically records the transition. Legacy
review claims remain `legacy_unverified`; the migration never backfills
sessions or completions. If an affected review phase was completed, it and all
completed downstream phases become stale and resume routes to the earliest
affected review phase.

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

Import blocks if any source value starts with `NEEDS_REVIEW`, `HALT`, or `HALTED`. `LOCAL_MODE`, `ANONYMIZED`, and `CLEARED` are normalized into a Phase 0 artifact, with original statuses and current content digests preserved under `status_by_file`.

The auto-research boundary uses a strict copy-only identity policy: safety keys must resolve to regular files inside the project, and data symlinks are rejected. Materialize linked inputs inside the project and rescan before import. Import prepares the normalized safety receipt and invalidated state before publishing either; a publication failure rolls the safety receipt back and retains prior audit receipts.

`OVERRIDE` is allowed only when the source value includes a non-empty rationale after a colon, for example `OVERRIDE: public synthetic demo file`. Bare `OVERRIDE` blocks Phase 0.

If no files were scanned, the normalized artifact must set `no_data_declared: true`; otherwise `files_scanned: 0` is treated as an ambiguous safety gap.
