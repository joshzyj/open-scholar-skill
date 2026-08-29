# Packaged Data-Safety Runtime Contract

This is the self-contained recovery reference for the data guard shipped with
`scholar-auto-research`. It applies regardless of whether the host is Claude,
Codex, or another agent runner. The guard enforces access boundaries; it does
not establish review-evidence authority.

## 1. Core rule

Never expose row-level sensitive, restricted, or participant data to a remote
model. Run `scholar-safety`/`scholar-init` locally before Phase 0, import the
result with `auto-research-state.sh import-init`, and honor `HALT`,
`NEEDS_REVIEW`, and `LOCAL_MODE` decisions. Do not treat a missing status file,
unknown classification, or unavailable scanner as permission.

## 2. Safety states

- `PASS`: the recorded inventory has no unresolved high-risk file.
- `PASS_LOCAL_MODE`: governed inputs may be processed only by local scripts or
  approved local models; prompts and traces contain aggregates and file names,
  never raw rows.
- `BLOCKED`: stop data-touching work until the named issue is resolved and a
  fresh safety result is imported.
- Missing, stale, malformed, or contradictory state fails closed.

## 3. Local-mode execution

Keep sensitive reads inside a local script. The agent may author or inspect the
script without reading its raw stdout. Redirect row-level output to a governed
project file, then expose only disclosure-safe aggregates, diagnostics, and
schema summaries. Do not use shell expansion, command substitution, previews,
or exception messages that echo raw values.

### 3a. R loader pattern

An R loader should read the governed path internally, compute only the required
aggregate, suppress row previews, and write the aggregate artifact to the
approved project output. Logs contain counts, variable names when permitted,
and success/failure status only.

### 3b. Python loader pattern

A Python loader follows the same boundary: read inside the process, validate
columns without printing rows, compute aggregates, and write only the approved
result. Catch exceptions and report a bounded error category rather than raw
record content.

## 4. Trace privacy

RAO traces and review sidecars are durable, shareable artifacts. Record
reasoning, actions, verdicts, counts, severities, and project-relative file
references. Never record data rows, verbatim participant text, secrets, access
tokens, or direct identifiers. See `references/process-logger.md` and
`references/agent-trace-contract.md` for the packaged trace schemas.

## 5. Recovery

When the guard blocks a command, preserve the project and state files, inspect
the named safety status locally, correct or anonymize the input, rerun the
safety scan, and import the new result. Do not bypass the guard with another
shell, renamed command, copied raw file, or hand-edited PASS value.
