# Code-Review Fix Loop (shared by 5A.5, 5B-gate, 6-gate)

When any pre-execution code-review gate returns CRITICAL findings, the orchestrator applies this loop. Goal: auto-fix cheap/unambiguous issues, escalate the rest, leave a full audit trail — never silently bypass.

## Loop

```
iteration = 0
while gate_verdict == CRITICAL and iteration < 2:
  iteration += 1
  for each CRITICAL finding:
    classify finding (see table below)
    if class = AUTO_FIX:
      apply Edit to the offending script using the reviewer's suggested fix
      append row to ${PROJ}/logs/code-review-fixes-[date].md
    elif class = ESCALATE:
      add to user-escalation list
  if user-escalation list is non-empty:
    break and hand to user (do NOT run scripts)
  re-run the same scholar-code-review invocation against updated scripts

if iteration == 2 and gate_verdict still == CRITICAL:
  escalate the remaining CRITICALs to the user; do NOT proceed to execution
```

## Classification table

Use this to decide AUTO_FIX vs ESCALATE for each CRITICAL finding:

| Finding pattern | Class | Rationale |
|---|---|---|
| Missing `cluster = ~unit` matching Phase 3 blueprint | AUTO_FIX | Blueprint names the cluster; mechanical insertion |
| Missing fixed effect matching Phase 3 blueprint | AUTO_FIX | Blueprint names the FE; mechanical insertion |
| Wrong SE type (default where HC3 / CR1 required) | AUTO_FIX | Blueprint specifies SE type |
| `NA` recoded as `0` on a non-pre-registered variable | AUTO_FIX | Replace with `NA_real_`; if pre-registered, Edit comment to document |
| `marginaleffects::avg_slopes()` / AME CSV missing for logit/probit | AUTO_FIX | Add the `avg_slopes(model) %>% write.csv(...)` block |
| `set.seed()` missing on stochastic scripts | AUTO_FIX | Insert `set.seed(20260412)` (or project-standard seed) at top |
| Hardcoded path under `/Users/` / `~/` | AUTO_FIX | Replace with `${OUTPUT_ROOT}` / `file.path(Sys.getenv(...))` |
| Hallucinated function argument / deprecated API | AUTO_FIX | Remove or rename per reviewer suggestion |
| Tautological outcome (Y is a function of X) | **ESCALATE** | Design-level bug; re-specifying outcome requires Phase 3 decision |
| Outcome mis-operationalized relative to hypothesis | **ESCALATE** | Same — design-level |
| Sample restriction inconsistent with pre-analysis memo | **ESCALATE** | Re-definition of analytic sample affects Phase 4/5 |
| Identification strategy violates blueprint (e.g., DiD without parallel-trends test) | **ESCALATE** | Design-level |
| Cross-script variable-coding inconsistency (e.g., `low_ed` coded differently in two scripts) | AUTO_FIX if both scripts have a canonical source; else ESCALATE | Depends on whether reviewer identifies the canonical definition |
| Results-registry / adjudication-log emission missing | AUTO_FIX | Append the registry-write block from `results-registry-contract.md` |
| LLM annotation missing Lin & Zhang 2025 risk checks (compute only) | AUTO_FIX | Append the 4-risk block per scholar-compute MODULE 1 |
| Unknown / ambiguous CRITICAL | **ESCALATE** | Default to escalation when uncertain |

When in doubt, escalate. Auto-fix is for mechanical, blueprint-specified changes; anything requiring a design judgment is user territory.

## Fix log format

Append one row per auto-fix to `${PROJ}/logs/code-review-fixes-[date].md`:

```markdown
| Timestamp | Gate | Script | Finding (abbrev) | Reviewer agent | Fix applied | Class |
|---|---|---|---|---|---|---|
| 2026-04-12T14:30 | 5B-gate | 04-main-models.R | missing cluster=~state | review-code-statistics | added `cluster = ~state` to feols() | AUTO_FIX |
```

## Escalation format

When handing to user, write `${PROJ}/logs/code-review-escalation-[date].md`:

```markdown
## Escalated CRITICAL findings — [gate name] — [date]

The following CRITICAL findings were NOT auto-fixed. Review and address before re-running the gate.

1. **Script:** `path/to/script.R`
   **Finding:** [one-sentence description]
   **Reviewer agent:** review-code-[dimension]
   **Why not auto-fixed:** [design-level / ambiguous / requires Phase N decision]
   **Suggested action:** [reviewer's recommendation verbatim]

2. ...
```

Then halt the orchestrator with a clear message naming this file.

## Invocation (insert at end of each gate)

```bash
. "${SCHOLAR_SKILL_DIR:-.}/scripts/gates/derive-proj.sh"
cat "${SCHOLAR_SKILL_DIR:-.}/.claude/skills/scholar-full-paper/references/code-review-fix-loop.md"
# Apply the loop described above against the current gate's CRITICAL list.
# Max 2 iterations; escalate on iteration 3 or on any ESCALATE-class finding.
```

## Why 2 iterations, not unlimited

Unlimited looping masks root causes — if the same finding survives 2 auto-fix passes, either the classification was wrong (should have been ESCALATE) or the fix introduced a new CRITICAL. In either case the user needs to see it.
