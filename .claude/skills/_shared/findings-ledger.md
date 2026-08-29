# Findings Ledger — `logs/findings.ndjson` (RCA Round 1 #3, 2026-08-22)

An append-only, machine-readable INDEX of review findings, kept BESIDE the full
reports — never a replacement for them. The reports remain the evidence; the
ledger is what the orchestrator, the gates, and future fix agents read, so that
finding state never lives only in a saturated conversation context.

**Why it exists.** The ses-polarization-gss review→fix loop passed 1.19MB of
prose and 199 finding IDs between rounds with zero machine contracts; briefs
were written from orchestrator recollection, findings were "WRONGLY CLOSED"
(cohab F-31), and two reviewers routed a decision to each other in prose so the
implementer took one half of it. One line per finding-event fixes the seam.

## Record schema (one JSON object per line; append-only)

```json
{"id": "CRIT-STAT-301",
 "ts": "2026-08-22T12:00:00Z",
 "phase": "5.5",
 "iter": 3,
 "locus": "scripts/p35-05-h4a-precision.R:294",
 "status": "OPEN",
 "class": "scale-transfer",
 "verify": {"mode": "check", "cmd": "Rscript -e 'source(...); stopifnot(is.function(KAPPA))'", "expect": "exit 0"},
 "claim_kind": "mechanism",
 "mechanism_status": "reproduced",
 "repro_cmd": "python3 -c \"import re; print(re.findall(PAT, S))\"",
 "affected_consumers": ["scripts/p35-07-smoke-harness.R", "T16"],
 "reviewed_at_sha": "sha256:...",
 "report": "reports/code-review-statistics-2026-08-21-iter3.md"}
```

Required keys: `id`, `ts`, `status`, `locus`, `report`. Everything else is
optional but load-bearing where present.

## `claim_kind`, `mechanism_status`, `repro_cmd` — what kind of claim is this?

Added 2026-08-28. Across one 5-round stretch, roughly **half of all filed
findings were wrong** — and they were wrong in a specific, repeatable way:
**every one was right about the symptom and wrong about the mechanism**, and the
mechanism was wrong exactly when it had been inferred from reading code rather
than established by running it. A `locus` is a *claim about cause*, and nothing
in this schema recorded whether that claim had ever been tested.

`verify{mode,cmd,expect}` does not cover this: it checks whether **the fix**
holds, not whether **the diagnosis** was ever true.

| Field | Values | Meaning |
|---|---|---|
| `claim_kind` | `observation` \| `mechanism` \| `absence` | what sort of claim the finding makes |
| `mechanism_status` | `reproduced` \| `hypothesis` | for `mechanism` only: was it executed? |
| `repro_cmd` | string | the command that produced the evidence |

Three kinds, because they fail differently and need different falsifiers:

- **`observation`** — "I ran X and saw Y." Fails by misreading output.
  Falsifier: re-run and compare.
- **`mechanism`** — "Y happens because of code Z." Fails by inference across
  layers, landing on the most visible one. Falsifier: isolate Z and execute it.
- **`absence`** — "nothing checks X" / "only one gate does Y." Fails by
  incomplete sweep. Falsifier: the search command, recorded in `repro_cmd`, so
  a reader can widen it. (A filed "only one checker reads Phase 5A.7" was wrong
  because six do; the enumeration that would have shown this is one grep.)

**Filing `mechanism_status: hypothesis` is legitimate and expected.** You do not
have to reproduce a mechanism to report a defect — a real symptom with an
unverified cause is worth filing, and making filing expensive suppresses
reports, which is worse. What the contract forbids is *presenting* an unexecuted
mechanism as an established cause. A stated mechanism that was never run is a
hypothesis and should be labelled as one.

**All three fields are OPTIONAL.** Existing ledgers stay valid; nothing fails
retroactively. When present they are validated (R7): `claim_kind` and
`mechanism_status` against their closed vocabularies, and `claim_kind: absence`
or `mechanism_status: reproduced` must carry a `repro_cmd` — a reproduced claim
with no command is a declaration, not evidence.

**Consumption rule.** A finding's `mechanism` is never promoted to a fix's
Verified Cause on the strength of the label alone. The fixer re-establishes it
by execution; where the fixer's mechanism differs, the finding is corrected in
place rather than silently rewritten, because the misattribution *rate* is
itself evidence and hiding instances corrupts it.

## Transport: per-seat inbox, single-writer append (system-fix S1.3, 2026-08-23)

Dispatched seats never append to this ledger. The old return contract told
four parallel Phase-3.5 seats to append to one file — the concurrent-write
clobber §7a forbids, and three of four seats declined it citing §7a (handoff
P2-4). Instead:

- each seat WRITES its own inbox, `logs/findings-inbox/<dispatch_nonce>.ndjson`
  (one writer per file), containing only `status: OPEN` lines in this schema;
- the ORCHESTRATOR — the ledger's single writer — ingests each inbox after the
  seat returns: `ingest-findings-inbox.sh <proj> <nonce> --agentId <id>`.
  Ingestion is ATOMIC (one invalid line → nothing ingested), IDEMPOTENT
  (re-runs skip already-ingested lines), and OPEN-only (a seat files findings;
  it never closes, fixes, or accepts them). A missing inbox fails closed;
  `--allow-empty` is the explicit zero-findings path.
- ingested lines carry provenance stamps: `source_nonce`, `source_line_sha`,
  and `source_agent_id` — additive keys; every ledger consumer parses
  per-line JSON and ignores keys it does not read.

- **`id`** — the stable finding id from the report heading (`CRIT-STAT-301`).
  The id in the ledger and the id in the report MUST match; the report is the
  evidence for the line.
- **`status`** — closed vocabulary: `OPEN | FIXED | VERIFIED | ACCEPTED |
  ESCALATED | WITHDRAWN`. A status change is a NEW line for the same id (the
  ledger is event-sourced, like gate-runs.ndjson); the latest line for an id is
  its current state. `ACCEPTED` lines carry `"decision_ref"` pointing into
  `logs/gate-acceptances.md`. Never delete or rewrite lines.

  **A close MUST reuse the EXACT id it closes** (handoff 2026-08-25 P1-D). Every
  replay consumer keys on the literal id string, so a close filed under any
  other id supersedes NOTHING. The measured failure: a fix round appended its
  36 closes as `p5a5-crit-corr-001-FIXED` (id suffix) instead of a `FIXED` line
  under `p5a5-crit-corr-001` — 36 orphan closes, and the ledger reported ~75%
  more OPEN RED findings than were genuinely open, untrustworthy in both directions
  (a real close hidden; an invented one equally invisible). Anti-pattern:

      WRONG  {"id": "CRIT-X-001-FIXED", "status": "FIXED", ...}   ← closes nothing
      RIGHT  {"id": "CRIT-X-001",       "status": "FIXED", ...}   ← supersedes the OPEN

  The same rule covers `ESCALATED`/`ACCEPTED`/`WITHDRAWN`: file them under the
  finding's own id. A cross-reference field such as `answers_finding_id` is NOT
  a close mechanism — no replay consumer reads it; it may exist as a human note
  only, and the status line still goes under the exact original id. Mis-filed
  orphan ids already on the record are repaired by appending (a) the proper
  close under the ORIGINAL id and (b) a `WITHDRAWN` line under the orphan id
  noting the mis-filing — appending a close with the matching id is how an
  append-only ledger records a close, not a history edit.
- **`verify.mode`** — three-way, because many statistical findings are not
  command-expressible and forcing them into escalate jams the loop:
    - `check`   — mechanically decidable: `cmd` + `expect` REQUIRED. A FIXED
                  line for this finding is only credible with the check re-run.
    - `review`  — needs an independent reviewer (name the agent type in
                  `"reviewer"`); a FIXED line must be followed by a VERIFIED
                  line filed from that re-review.
    - `escalate`— the PI's call (name it in `"to"`); terminal states are
                  ACCEPTED (via §7b ledger) or a PI-directed fix.
- **`class`** — optional slug from `_shared/defect-class-registry.md`.
  **Recurrence rule:** when OPEN lines share a `class` across two or more
  distinct `locus` values, the class is no longer an instance — it is a
  project invariant. File an invariant line carrying ALL required keys plus
  the promotion markers — e.g. `{"id": "INV-<class>", "ts": ..., "status":
  "OPEN", "locus": "project-wide", "report": "<the recurrence evidence>",
  "class": ..., "invariant": true, "verify": {"mode": "check", "cmd": ...,
  "expect": ...}}` — with a standing check, and close it only by a sweep
  (see `_shared/class-sweep-contract.md`), never by per-instance fixes.
  `findings-ledger-check.sh` flags unpromoted recurrences (and REDs an
  invariant line missing the required keys, like any other line).
- **`phase`** — the phase TAG of the dispatch that reviewed the finding, i.e.
  the same value the dispatch-manifest row carries and the same value passed
  to `pre-exec-review-check.sh --phase` / `emit-fix-brief.sh --phase`. One
  namespace, by convention: when a pre-execution review legitimately runs
  during the design pre-mortem, the tag is `3.5` everywhere — ledger lines,
  manifest rows, and receipt-gate invocations alike (guess log #11, eval
  2026-08-22). Do NOT file the phase the finding "belongs to" conceptually;
  file the tag the dispatch actually carried.
- **`verify.cmd` execution contract** — check commands use project-relative
  paths and RUN FROM `$PROJ` (guess log #5). Write them so
  `cd "$PROJ" && <cmd>` is the exact replay.
- **Who may amend `verify.cmd`** — the reviewer who filed the OPEN line, or
  the PI. The FIXER may file a corrected `cmd` in its FIXED line when the
  original check does not match the shipped fix shape, but the amendment is
  NOT self-certifying: `findings-ledger-check.sh` surfaces every
  FIXED-vs-OPEN `verify.cmd` drift as YELLOW (Y2), and the independent
  re-reviewer adjudicates it — honest correction vs weakened check (guess
  log #7 / finding 10).
- **`locus` grammar** — `path:line` for code; for artifacts with no
  meaningful line (JSON specs, design docs, directories), `path` alone or
  `path:<anchor>` where `<anchor>` names the key/section
  (`design/model-specs.json:seg_pre`) — anything a reader can locate
  mechanically (guess log #6).
- **`reviewed_at_sha`** — SHA256 of the reviewed artifact at filing time, so a
  fix agent's brief can be generated from the diff since review (Round 1 #1).
  For a line filed RETROACTIVELY about a review that predates hashing, use
  the literal string `"UNKNOWN"` rather than omitting the key or hashing
  today's bytes — hashing post-review bytes would assert the review saw a
  file it never saw (guess log, eval 2026-08-22).
- **`affected_consumers`** — producer→consumer impact edges. The ses 3→9
  return-arity change slipped through precisely because no edge existed.

## Appending safely (no CLI needed)

```bash
python3 - "$PROJ/logs/findings.ndjson" <<'PY'
import json, sys, datetime
rec = {"id": "CRIT-STAT-301", "ts": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
       "phase": "5.5", "iter": 3, "locus": "scripts/x.R:294", "status": "OPEN",
       "report": "reports/code-review-statistics-2026-08-21-iter3.md"}
open(sys.argv[1], "a", encoding="utf-8").write(json.dumps(rec, ensure_ascii=False) + "\n")
PY
```

## Who writes what, when

- **Phase 3.5 / 5A.7 / 5.5 consolidation** — and the pre-execution gates
  that share the fix loop (5A.5, 5B-gate, 6-gate; `_shared/code-review-fix-loop.md`):
  one `OPEN` line per blocking finding, filed when the consolidated blocker
  list is produced — in the same step, never reconstructed later.
  `emit-fix-brief.sh` refuses to generate a fix brief without the ledger.
- **Fix rounds**: a `FIXED` line per finding actually addressed (with the
  check re-run for `check`-verb findings), filed by whoever applied the fix.
  The fix receipt (`code-review/reviewed-scripts-fix-<round>.json`) points its
  `report` field at the fix log `logs/code-review-fixes-<date>.md`, and that
  file must embed the receipt's `review_id` verbatim — that is the pairing
  `pre-exec-review-check.sh` R1 verifies (guess log #1).
- **Re-review**: `VERIFIED` lines only from an independent re-review, never
  from the fixer's own claim (DC-03). For `check`-verb findings the check
  re-run may accompany an `OPEN`→`VERIFIED` transition directly; for
  `review`-verb findings a `FIXED` line precedes `VERIFIED`. The validator
  flags VERIFIED-with-no-prior-line as a DC-03 smell (YELLOW), not RED —
  it cannot know which verb applied when the earlier line was never filed.
- **PI decisions**: `ACCEPTED` (with `decision_ref`) or `ESCALATED` lines.

Validation: `bash scripts/gates/findings-ledger-check.sh "$PROJ"` — wired into
`phase-verify.sh 5.5`; INERT while no ledger exists (adoption is per-project).
