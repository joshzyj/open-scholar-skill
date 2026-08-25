# Pre-Execution Code Review Protocol (shared)

**Who loads this:** every skill that AUTHORS executable analysis code and then EXECUTES it — `scholar-analyze`, `scholar-eda` (handoff variant), `scholar-compute`, `scholar-data`, `scholar-simulate`, `scholar-ling` — plus any skill run that authors ad-hoc executable analysis code outside these named seams (§7). Orchestrated runs are governed by their own phases instead (§6).

**Why it exists:** model-authored analysis code fails silently — wrong clustering, NA-as-0 recodes, tautological outcomes, miscoded variables produce plausible-looking but wrong results. The orchestrator (scholar-auto-research Phase 6) and two standalone flows (scholar-brainstorm DATA mode, scholar-respond R&R) already review code with independent agents BEFORE it executes; this protocol extends the same duty to every other authoring skill. Fixes are cheap before execution (edit a script) and expensive after (re-run analysis, re-draft, re-verify).

---

## §1 The state sequence (BINDING)

Model-bearing / at-scale / data-transforming code moves through three states, in order:

```
DRAFTED  →  REVIEWED+HASHED  →  EXECUTABLE
```

1. **DRAFTED** — the code is WRITTEN TO ITS SCRIPT FILE first (the skill's own naming + header conventions), never executed inline. No `Rscript -e` / `python3 -c` / REPL execution of model-bearing logic.
2. **REVIEWED+HASHED** — the script set passes independent review (§3) and the consolidated report carries a reviewed-script manifest with a SHA-256 per script (§4).
3. **EXECUTABLE** — the gate (§5) returns GREEN; the **reviewed file itself is invoked** (`Rscript path/to/04-main-models.R`). Copying a reviewed block back into a REPL is PROHIBITED — the reviewed bytes must be the executed bytes.

**Which code qualifies:** anything that fits any of: fits a statistical model or estimator; constructs, recodes, merges, or restricts analysis variables/samples; scrapes or transforms collected data; runs at scale (see §2); produces a number that could reach a manuscript, results registry, or downstream skill. Plot-only cosmetic revisions and pure scaffolding (mkdir, git init) do not qualify.

## §2 Pilot exemption (mechanical definition)

A run is a **pilot** — exempt from pre-execution review — ONLY if ALL of the following hold:

- Declared, capped input set (each skill/module declares its cap; e.g. scholar-compute MODULE 1 ≤50-document pilots, MODULE 6 ≤200-image validation samples — the module's existing checkpoint numbers ARE the caps).
- No output feeds a manuscript, results registry, final estimator, or another skill.
- No paid batch submission (API batches are never pilots).
- No pilot checkpoint/artifact is reused by the production run.
- The run is logged as `pilot` in the process trace.

Any run outside these limits is **at scale** and reviews first. "Full corpus" is one trigger for at-scale, not the definition of it.

## §3 Review dispatch

The integrating skill loads and executes `scholar-code-review` (`cat "${SCHOLAR_SKILL_DIR:-.}/.claude/skills/scholar-code-review/SKILL.md"`) in **pre-execution mode** with the fast 3-agent subset — `statistics` + `data-handling` + `correctness` — against the DRAFTED script set, passing the design blueprint / codebook / variable dictionary where they exist.

- scholar-code-review issues **N separate Agent dispatches in parallel** — one assistant message containing N distinct Agent tool-use blocks, each returning its own `task_invocation_id`. NEVER one combined "review everything" agent (CLAUDE.md real-agent-dispatch heuristic; `code-review-coverage-check.sh` REDs shared agent IDs).
- Each dispatch is recorded to `${PROJ}/logs/dispatch-manifest.jsonl` via `scripts/gates/emit-task-dispatch.sh --phase <phase-tag>` using the skill-scoped phase tag from the table below.
- **Allowed narrower subset:** code with no statistical models (scrapers, cleaning pipelines, fetch post-processing) may use `correctness` + `data-handling` only (2 agents). Model-bearing code always includes `statistics`.

| Integrating skill | Phase tag | Agent subset |
|---|---|---|
| scholar-analyze A2.5 | `pre-exec-analyze` | fast 3 |
| scholar-eda Phase 11 (handoff) | `pre-exec-eda` | correctness + data-handling |
| scholar-compute MODULE 0.7 | `pre-exec-compute` | fast 3 |
| scholar-data (W4/W6/W7) | `pre-exec-data` | correctness + data-handling |
| scholar-simulate (analysis scripts) | `pre-exec-simulate` | statistics + correctness |
| scholar-ling (model-fitting) | `pre-exec-ling` | fast 3 |

## §4 The reviewed-script manifest (hash binding)

scholar-code-review emits, alongside the consolidated report, a machine-readable sidecar `${PROJ}/code-review/reviewed-scripts-<review_id>.json`:

```json
{"schema": "code-review-manifest/v1",
 "review_id": "cr-YYYYMMDD-<slug>",
 "report": "code-review/code-review-report-YYYY-MM-DD.md",
 "mode": "fast",
 "phase_tag": "pre-exec-analyze",
 "ts": "ISO-8601",
 "scripts": [{"path": "scripts/04-main-models.R", "sha256": "<hex64>"}],
 "out_of_scope": [{"path": "scripts/E01-load-data.R", "reason": "already executed; reviewed as context only"}],
 "supersedes_review_id": null,
 "fixed_finding_ids": [],
 "remaining_blocking_count": 0}
```

- `scripts[]` paths are relative to `${PROJ}`; every DRAFTED script in scope MUST appear.
- The same `review_id` appears verbatim in the consolidated report header — the gate pairs report↔manifest by id, never by file mtime.
- After a fix round, the re-review manifest sets `supersedes_review_id`, lists `fixed_finding_ids`, hashes the FIXED bytes, and sets `remaining_blocking_count`.

## §5 The gate

Before executing ANY reviewed script:

```bash
_b="$HOME/.claude/scholar-skill-bootstrap.sh"; [ -f "$_b" ] || _b="${SCHOLAR_SKILL_DIR:-.}/scripts/scholar-skill-bootstrap.sh"; [ -f "$_b" ] && . "$_b"; unset _b
bash "${SCHOLAR_SKILL_DIR:-.}/scripts/gates/pre-exec-review-check.sh" "$PROJ" \
  --manifest "$PROJ/code-review/reviewed-scripts-<review_id>.json" \
  --required=fast --phase <phase-tag> \
  || { echo "HALT: pre-execution review gate failed — apply the fix loop (§6) or escalate; do NOT execute."; exit 1; }
```

Exit codes: `0 GREEN` (execute the reviewed files) / `1 RED` (fix + re-review; never execute) / `2 YELLOW` (legacy-only; non-executable — re-review before executing) / `3 INERT` (no scripts in scope). YELLOW is NOT a pass for execution under this protocol.

**Countable receipt (REQUIRED):** immediately BEFORE the first model-bearing execution command — not only in a final output log — emit one row to the skill's own log/trace:

```
Pre-execution review: report <path> · review_id <id> · scripts N hashed · gate GREEN
```

## §6 Fix loop, skip, and orchestration

- **Fix loop:** on CRITICAL findings apply `_shared/code-review-fix-loop.md` — AUTO_FIX-class items go to a freshly dispatched Task subagent (never the orchestrator's own Edit — see the loop for why), ESCALATE design-level items to the user, max 2 iterations, log to `${PROJ}/logs/code-review-fixes-[date].md`. After fixes, **re-review is mandatory** (scholar-code-review Step 6): re-dispatch the affected agents against the fixed bytes; the new manifest supersedes the old; re-run the gate.
- **Skip:** `--skip-preexec-review` is honored in standalone invocation only. The skip MUST emit a trace row (`status: skipped`, with the flag as reason) and MUST be justified in the output's Limitations. Under orchestration the flag is ignored.
- **Orchestration interplay:** under scholar-auto-research (Phase 6), the orchestrator's review phases SUPERSEDE this duty — do not double-review. scholar-brainstorm DATA mode keeps its own equivalent gate (`references/mode-data.md` Step 4b.ii.5, different artifact schema — documented divergence, equally binding).

## §7 Catch-all

Any skill run that authors ad-hoc executable analysis code outside the named seams — e.g., pre/post-processing scripts around the annotate/rag/simulate vendored engines, one-off merge scripts, reliability recomputation — inherits this protocol in full: draft to file, review (narrowest allowed subset), gate, then execute. Vendored engine code itself (shipped in `assets/`, smoke-tested with the plugin) is NOT in scope — only what the model authors at run time.
