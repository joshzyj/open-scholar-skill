# Portable Review-Evidence Contract

## Purpose

Several phases require independent reviewers, but a manuscript can contain
plausible-looking reviewer names and task IDs without any reviewer ever having
run. This layer closes that procedural gap. Before dispatch, the pipeline
reserves the required roles and records the exact inputs. After the host has
finished a role, the pipeline records the persisted report, RAO sidecar, their
digests, and the driver-observed successful return. Phase verification accepts
only sessions and completions registered in locked project state.

This is useful across Claude, Codex, local runners, HPC schedulers, and future
hosts because the contract describes evidence, not a provider API. It is not a
universal launcher and it does not prove that a review was intelligent or
independent in the philosophical sense.

## Authority boundaries

- `review-evidence/phase-XX/...` is the procedural evidence ledger and the
  single gate authority for whether required reviewer roles were reserved and
  completed over byte-bound inputs.
- The phase's canonical JSON remains the authority for substantive findings,
  verdicts, fixes, and role-specific scientific checks. Its reviewer records
  must point back to the selected evidence reports and dispatch identities.
- RAO traces are observability: they explain the reviewer's stated rationale,
  actions, and observations. A trace alone cannot authorize phase completion.
- `logs/dispatch-manifest.jsonl`, when present, is display/legacy metadata. It
  is not a second completion authority.

## Assurance profiles

`normal` is the default and yields `process_recorded`. It proves that this
packaged state process reserved roles before completion, observed a successful
driver return, and bound the reports, traces, and reviewed inputs by digest.
Opaque provider task/model identities are accepted. A host that does not expose
either identity must use the structured `unavailable` form with a nonempty
reason. This level is honest procedural bookkeeping, not cryptographic host
attestation and not protection against a same-user editor who can rewrite both
the installed runtime and project state.

`strict` requires `host_verified` for every claim named by the phase policy,
including task identity, terminal status, completion time, report digest, and
reviewed-input digest. The bundled generic adapter does not fabricate those
claims. A host adapter that cannot verify every required claim must remain
unsupported, and strict verification blocks.

`artifact_bound` describes files and hashes without a registered process. It is
insufficient for every review-required phase in this pipeline. `unsupported`
is a claim-level host-verification status, not a failure under `normal`.

## Lifecycle

Run the host-neutral preflight once from the loaded skill directory:

```bash
python3 "${_AR_SKILL}/scripts/runtime-preflight.py" --skill-dir "${_AR_SKILL}"
```

Then, for the authoritative next phase:

In human-in-loop mode, a pending transition approval blocks both
`review-begin` and `review-complete`. `review-abort` remains available so a
failed or cancelled host job can be retired safely without authorizing new
phase work.

1. Begin the declared round before any destination report or sidecar exists.

   ```bash
   bash "${_AR_SKILL}/scripts/auto-research-state.sh" review-begin \
     "$PROJ" 6 initial_panel generic-host
   ```

   The returned `REVIEW_SESSION_JSON` is the launch envelope. Each reservation
   carries an opaque `dispatch_id`, role, exact reviewed-input list and hashes,
   and fixed project-relative `report_path`/`trace_path`.

2. Dispatch each role using any host. Give the worker the reserved role, input
   paths, report path, and trace path. The pipeline driver—not the worker's
   stdout convention—owns persistence checks and completion registration.

3. After the host reports success and both files exist, complete the role. Use
   either a reported opaque value or structured unavailability for task and
   model identity; blank placeholders are invalid.

   ```bash
   bash "${_AR_SKILL}/scripts/auto-research-state.sh" review-complete \
     "$PROJ" 6 "$REVIEW_SESSION_ID" correctness --driver-status succeeded \
     --host-task-unavailable "host exposes no stable task identity" \
     --model-unavailable "host exposes no model identity"
   ```

4. Bind the selected session and computed assurance into the canonical phase
   JSON, using the schema declared by `phase-contract.json`. Bind each semantic
   reviewer record's report path and task invocation ID to its evidence
   completion (`dispatch_id` or a reported host task ID).

At any point, inspect reservations, completion registration, assurance policy,
orphans, and actionable diagnostics without changing state:

```bash
python3 "${_AR_SKILL}/scripts/review_evidence.py" status \
  --project "$PROJ" --phase 6 \
  --contract "${_AR_SKILL}/references/phase-contract.json"
```

5. Run phase verification and state completion normally. Any input/report/trace
   mutation, missing state event, replayed attempt epoch, or role mismatch
   invalidates the evidence. Abandon a failed partial session explicitly:

   ```bash
   bash "${_AR_SKILL}/scripts/auto-research-state.sh" review-abort \
     "$PROJ" 6 "$REVIEW_SESSION_ID" --reason "host job failed before completion"
   ```

   Abort is recoverable across a crash between writing `aborted.json` and
   publishing its state event: `status` reports `abort_pending_publication`,
   and retrying the identical abort command publishes the missing event.

For a declared fix/rereview sequence, completed historical rounds remain bound
to their immutable session snapshots. The last active round is the authority
for current input bytes. Thus a legitimate fix does not retroactively corrupt
the initial-panel record, while the fix-rereview cannot pass over stale bytes.

## Host mappings (non-normative)

- Claude: map a successful Agent/Task result to driver success; store any
  returned task/model identity as an opaque value. Do not require a
  Claude-specific ID prefix or environment variable.
- Codex: map a completed collaboration or CLI task the same way. Codex is an
  optional diversity reviewer only when the operator explicitly enables that
  lane; its presence on `PATH` never changes the base phase requirement.
- Generic/local/HPC: use a scheduler/job ID if one exists, otherwise use the
  structured unavailable reason. The reports and RAO sidecars still use their
  reservation paths.

Conflicting `CLAUDE_*`, `CODEX_*`, or other provider environment variables do
not select assurance and are never read by this evidence contract.

## Attempts, locking, and migration

Project state is locked first; the phase review lock under
`.auto-research/review-evidence-locks/` is acquired second. Locks live outside
the recursively hashed evidence root. Safety re-import, route-back, input-hash
staleness, assurance-profile change, and affected contract migration advance a
per-phase attempt epoch so old byte-identical sessions cannot be replayed.

Existing projects on the allowlisted predecessor contract migrate with:

```bash
bash "${_AR_SKILL}/scripts/auto-research-state.sh" migration-status "$PROJ"
bash "${_AR_SKILL}/scripts/auto-research-state.sh" migrate-contract \
  "$PROJ" "<eligible-id-from-migration-status>" \
  --operator "<name>" --reason "adopt portable registered review evidence"
```

Use the single exact ID in `eligible_migration_ids`. Both legacy projects and
projects on the first portable-evidence contract have predecessor-specific
allowlisted transitions, so do not guess or reuse a migration ID.

Legacy reviewer assertions remain `legacy_unverified`; the migration never
mints historical reservations or completions. Completed affected review phases
and their completed downstream phases become stale and must be rerun.
