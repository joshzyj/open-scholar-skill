# Defect-Class Registry (cross-project)

A named, persistent catalogue of defect **classes** — not individual bugs. Individual bugs are
found once and fixed; classes recur across projects and recur *in the guards written to prevent
them*. This file is the memory that makes them findable.

**Why a registry rather than review-brief prose.** Measured on the 2026-08
a 2026-08 large-corpus annotation run: instances 1–5 of class DC-01 were found incidentally,
across four review iterations, by agents chasing unrelated symptoms. Instances 6–14 were found
**within hours of the class being named and written down**, by agents sweeping for the *pattern*
rather than the reported symptom. Naming is the intervention.

**And naming does not immunise the author.** Three DC-01 defects were introduced *in guards
written to enforce DC-01*, within one session of naming it. Treat every entry here as something
you are also capable of committing while fixing.

**Consumers.** All six `.claude/agents/review-code-*.md` briefs carry a standing sweep for
DC-01 and cross-reference this file. `scholar-auto-improve` reads it during AUDIT and IMPROVE.
Add a class here when a defect recurs in ≥2 places or survives ≥2 review passes.

---

## DC-01 — Three-valued logic collapse

**Statement.** Code converts *"not assessed"* into something that reads as *assessed*. A third
state (NA, unparseable, empty, absent, undefined) is silently folded into a definite one, and
every downstream reader treats the fold as a measurement.

**Frequency observed.** 14+ instances, four files, three independent agents, one run — none of
whom were looking for the same thing.

| site | collapse | consequence |
|---|---|---|
| FDR correction | `pv[!as.logical(below_floor),]` | phantom row inflates `nrow(pv)`, passed as **K** → every *other* cell's correction more conservative |
| diagnostic adjudication | `&&` short-circuits NA→FALSE | a diagnostic that *could not be computed* read as *computed and found nothing* — on every row |
| registry build | `length(dirs)>0 && all(...)` | **"pre-registration falsified"** emitted from an empty set |
| temporal trends | `length(unique(numeric(0)))<=1` | **"AGREE"** on a hypothesis from zero executed controls |
| feature build | NaN → `"NAN"` → no branch matches | a variety **KEPT with no evidence** |
| precision audit | `False == False` on two unparseables | scored as two codebooks **agreeing** |
| hurdle model | `!is.na(th) && th<1e-4` | NA→FALSE = "checked, not at boundary"; keeps a clean tag and an AIC advantage the file says must never happen |
| frequency weights | NaN / absent / UNMEASURABLE | all land in **KEEP**, disagreeing with a sibling whose docstring promises they cannot disagree |
| leak audit | bare `except: return []` | unreadable parquet indistinguishable from clean parquet |
| κ validation gate | `nan < 0.70` is False in IEEE-754 | an **undefined** κ passed a hard gate that printed "FAIL" on the same line |

### The countable trigger

The natural-language rule ("record how a conclusion was reached whenever more than one route can
produce the same value") has a flaw as a review trigger: it asks for exactly the awareness that
was missing. Every author who wrote a collapsing instance failed to notice the multiplicity.
Use the countable form instead — it needs no domain knowledge:

> **Count the branches that write a column; count the distinct values they can emit.
> If branches > values, the column is lossy and needs a companion.**

### Sibling shapes

- **Shape A — lazy evaluation (R).** `basename(x)` on an undefined variable inside a
  `stop()`/`warning()`/`message()` never evaluates until the fatal branch fires, so the guard
  crashes with `object not found` exactly when it is needed. **Invisible to parse checks and
  happy-path runs by construction.** *Remedy:* `force()` every message argument at entry.
  *Hunt:* grep for parameters appearing **only** inside `stop`/`warning`/`message`.

- **Shape B — a guard whose failure mode is a false alarm about something graver.** A
  locale-dependent integrity digest (R's default `sort()` is locale-collated) fails on a
  different node — and a failing integrity hash does not read as "this check is broken", it
  reads as **"the data have been altered"**, mid-run, with the authority of an alarm nobody will
  override. *Generalisation:* a guard whose failure mode falsely reports a graver condition is
  more expensive than no guard, because the response it triggers is proportional to the
  condition it falsely reports.

- **Shape C — a default propagating into rows where it does not apply.** An estimator string
  (`feglm`) copied onto two arms that are not logits. *A field whose value was copied rather
  than chosen is unassessed and must be detectable as such.*

- **Shape D — two *definite* states sharing one label.** Subtler than A–C, and **no NA-hunting
  grep finds it**: there is no missing value anywhere, only a lossy encoding.
  `precision_decisions.csv` printed `decision = DROP` for variety B under both audit
  vintages. At n=1,000 the Wilson **upper** bound sat below the floor — *measured below the
  floor*. At n=100 the interval merely **straddled** it — *could not tell, so the pre-stated
  tie-break decided*. Same verdict, entirely different epistemic status. Any prose describing
  variety B as "measured below the measurement floor" is true of one vintage and false of the
  other.

### Remedy, and two constraints on it

The companion column names the **deciding rule**, not just the verdict
(`measured_below_floor` / `indeterminate_resolved_by_tiebreak` / `measured_above_floor`), and
the registry surfaces the companion rather than the verdict alone. Two constraints, both learned
by watching them fail:

1. **The companion must be written by the deciding branch, never reconstructed afterwards.**
   Reconstruction is what `analysis_table_sha256` did — read from a manifest and stamped without
   hashing — and it is why a sampling frame would have been unrecoverable had it not been
   captured deliberately.
2. **The companion must have no default.** A companion defaulting to `measured` reintroduces
   shape D one level up. That is precisely the route by which `feglm` reached two arms that are
   not logits.

### Stated limit

The rule cannot reach a producer that never distinguished the states *in memory* — if the route
is lost before the write, there is no companion to write. The remedy there is upstream and is
the same sentence as the frame-capture lesson: **don't collapse before you record.**

### Mechanical detection (partial)

Lintable sub-cases: `&&` / `||` on NA-capable operands; `as.logical()` feeding a row index;
`identical()` assigning a verdict; a bare `except:` returning an empty container; a float
comparison against a value that can be NaN. Shapes C and D are **not** mechanically detectable
and need the countable trigger applied by a reader.

**Reference implementation of the remedy:** `scholar-annotate/assets/annotate_engine.py`
`cmd_validate` — every gold row excluded from κ carries `excluded_by` naming the branch that
excluded it (`annotator_absent` / `annotator_blank` / `gold_empty`), and `cohen_kappa: null` is
always accompanied by a non-null `kappa_undefined_reason`.

---

## DC-02 — Guards verified in their design state, never in the states they will meet

**Statement.** A guard is tested against the input it was written for and never against the
input it will actually meet. It looks protective and is decoration.

**Frequency observed.** 7 instances in one run, each of which had passed an ordinary
correctness review.

| guard | verified as | actually |
|---|---|---|
| cross-artifact drift check | "0.000% apart — PASS" | threshold `>0.01` against a real drift of **0.449%** — would have passed on its own motivating failure |
| vintage guard | fail-closed vs a *stale* file | skipped entirely on an *absent* file; the reader returns NULL before the provenance call |
| torn-checkpoint self-test | PASS | **constructed the buggy state and asserted it as PASS** |
| merge under-coverage | `rc=4` fatal | `os.replace()` published *before* the check ran |
| downloader exit-5 | correct on run 1 | self-disarming on run 2 — the skip-list its own first run wrote empties the todo set |
| local-mode leak audit | "0 leaks, PASS" | would print the same with the parquet library absent, having inspected **zero** schemas |
| analysis-table integrity | sha256 in manifest | verified by nobody — the DSL stamps a copied claim the registry compares against the same manifest |

**Why ordinary review misses it.** Every review brief asks whether the code is *correct*. None
asked the question that separates a guard from decoration: **what input makes this fire, and
what slips past?**

**Remedy — now a required report field.** `review-code-robustness` and `review-code-correctness`
must emit a per-guard `FIRES ON:` / `SLIPS PAST:` pair. Cheap, and it converts "looks
protective" into a falsifiable claim. When fix tracks were instructed to annotate every guard
this way, the next review round found materially fewer guard defects.

**Sub-shape — asserting presence where you mean to assert state.** A preflight required two
model arms to be *present* in a registry and to carry `assumed_inputs`. Correct when written.
Once those arms were legitimately retired, the preflight could not distinguish **"correctly
withdrawn"** from **"missing"**. *Generalisation:* when a guard checks for the presence of a
thing as a proxy for that thing being correct, it silently forbids the thing being legitimately
removed. Assert the state you mean (`status: retired` + a revision note), not a proxy for it.

---

## DC-03 — Fix commits are a fresh unaudited surface

**Statement.** Fixes fail at approximately the rate of original code, because they are written
under time pressure, in unfamiliar regions, by an author who has just been told they were wrong.

**Evidence.** CRITICAL counts by Phase 5.5 iteration: **40 → 15 → 26 → 11**. Iteration 3
reviewed six fixes written earlier the same day and found **two defective**. Iteration 4 reviewed
the iteration-3 fixes and found 11 CRITICALs, **8 of them in the assurance layer itself**.

> Fix commits are not evidence against a class; they are a fresh unaudited surface for it,
> written under exactly the conditions that produce the original.

**Remedy.** Enforce iter**N**, not iter2: any RED iteration requires a following iteration,
**scoped to the diff** (a full re-review re-finds settled issues; the diff-scoped iteration 4
found 11 real CRITICALs in one pass). Note what a pattern-absence check — one that confirms the
flagged pattern is gone once a fix has landed — can and cannot establish: it verifies the
original defect is absent, and nothing more. It cannot see a defect the fix *introduced*. Only
another review iteration can.

---

## DC-04 — A measurement consumed without the question that produced it

**Statement.** A constant derived from a measurement is consumed by a model that needs a
*different* construct than the instrument asked about. Both instruments validate well against
their own gold; the mismatch is invisible to reliability metrics by construction.

**Evidence.** `TARGET_RECALL <- 0.62`, measured under a prompt asking about "the superordinate category in the
sense used by domain experts" and crediting colloquial alternatives — consumed by a
model implementing a lexicon that deliberately excludes them. A codebook-matched re-draw on the
same item set measured **0.94**; the "surface-form asymmetry" that drove two declared sensitivity
arms and a planned manuscript caveat was **absent**. Survived four review iterations; surfaced
only when the estimator refused a degenerate fit.

**Three compounding reasons, each with its own remedy:**

1. **A literal is not a read.** Retracting the source artifact — renaming the discredited column,
   writing `claim_supported = False` on every row — reached none of the hard-coded
   number. *A number typed into source cannot be invalidated by fixing the artifact it came from.*
2. **A comment asserted the opposite.** The block header read *"NOTHING here is hard-coded from a
   count"* — true of the cell counts, false of the rate, and the rate was load-bearing.
3. **Nobody asked what the annotator was asked.** Six agents checked whether the number was
   *used* correctly; none checked whether it *measured the construct the model needed.*

**Remedies.** `design/measurement-constants.json` + `design/construct-match.json`, enforced by
`scripts/gates/measurement-instrument-check.sh`; the instrument block in
`validation_report.json`; and the U17 paragraph in the `review-code-statistics` /
`review-code-data-handling` briefs. Full treatment:
`scholar-annotate/references/construct-match.md`.

**Adjacent shape — prose fields inside artifacts are outputs.** When a claim is retracted from
code, it is not thereby retracted from the estimand strings, `*_NOTE` columns, drafter
instructions, and arm inventories that ship beside the numbers — some of which are lifted
**verbatim into the manuscript**. All six `review-code-*` agents read code; the `verify-*` agents
read the manuscript against the tables; **nobody reads the prose inside the analysis artifacts.**
Estimand strings destined for a manuscript should be generated from the same artifact the numbers
come from, never typed alongside them.

---

## DC-05 — A default that determines evidentiary strength

**Statement.** A CLI default or unset flag silently decides how strong the evidence behind a
shipped decision is.

**Evidence.** (a) A precision audit was authorised at n=400 (n=1,000 for a borderline case)
*specifically because* a KEEP/DROP gate rested on overlapping Wilson intervals. A rebuild re-ran
that node at the wrapper's default `PER_STRATUM=100` and overwrote it; variety A flipped from
0.925 [0.895, 0.947] KEEP to 0.83 [0.745, 0.891] INDETERMINATE→DROP — **a power artifact**, the
point estimate having moved within sampling noise. (b) A separate wrapper defaulted to a
full-pool relabel of ~90k comments (8h, 4 GPUs, under a *different quant* than the shipped
labels) unless `AUDIT_ONLY=1` was set; the driver simply never set it.

> **Any default that silently determines the evidentiary strength of a shipped decision is a
> trap, not a default.** The safe path is the default; expensive or destructive paths require an
> explicit opt-in that the caller must state.

**Remedies.** Design parameters (n, stratification, stopping rule) are declared properties in
`design/`, read by the wrapper and **stamped on the artifact** — see `measurement-design.json`
and the `<out>.design.json` sidecar written by `annotate_engine.py sample`, compared by
`measurement-instrument-check.sh` R4. Engine-side: `--allow-unreadable` defaults to 0, so a
corpus read that lost files fails closed rather than silently shrinking the sample.

---

## DC-06 — Presence checked where vintage is meant

**Statement.** `require_file`-style guards check that an input **exists**, not that it belongs to
the **current build**. A stale artifact from a previous build satisfies the check.

**Evidence.** A resubmission of an FDR node was refused by a track that noticed its required
input existed *from the previous build*. The node would not have failed — it would have
*succeeded*, writing a freshly-timestamped corrections table holding families 1/3/4 from build
63032 and family 2 from the current build: internally mixed, mtime-current, and invisible to per-row
vintage machinery because the registry never reads inside it.

**Remedy.** `require_file` → `require_artifact_of_build`: presence **plus** the artifact's own
recorded `build_id` matching the current manifest. Presence checks are the default idiom
throughout HPC wrapper code and every one of them has this hole. Guidance:
`scholar-annotate/references/scale-engine.md` §Build-vintage guards.

---

## DC-07 — A pin trusted by permission rather than verified by content

**Statement.** Freezing code for the duration of a long run by making it read-only prevents
nothing, because `chmod a-w` is advisory against the file's **owner** and every job runs as the
owner.

**Evidence.** A DAG node failed 37s in with `Error: unexpected symbol`; the script's mtime was
16 seconds before the failure — an agent was editing an analysis script while a 12-hour DAG was
reading it. Cascade: six nodes. A sibling track's blast-radius audit found its own margin was
**10 minutes** on one file; it held by luck.

The correction matters more than the finding, and it is itself an instance of DC-02: the
immutability test written to *demonstrate* the pin instead modified the pinned file
(`pin_mtime` moved), and a re-run on a second file confirmed it — `touch` SUCCEEDED. What
actually protected the resubmitted job was not the permission bit but a parse-check job printing
`sha=7b174349c0f34889` and the job executing that same content. **The chmod was decoration; the
digest was the guarantee.**

> **A pin must be verified by content at job start, never trusted by permission.** The strong
> form is a content-addressed store — the pinned path *is* the digest (`_pinned/<sha256>/`), so
> "has it moved?" becomes unanswerable-by-construction rather than checked. Failing that, the
> runner re-hashes the entry script and its first-party imports immediately before exec and
> refuses on mismatch. **An unset pin must refuse, not pass** — otherwise every hand-submitted
> job silently opts out, and those are the submissions most likely to be racing an edit.

Pinning prevents an **accident**, which is the actual failure mode that killed the node, but
prevents nothing an owner can do deliberately. Verification is the load-bearing half.

---

## DC-08 — A defaulted column read *(PROVISIONAL — single-project provenance)*

**Statement.** A consumer reads a column through a defaulting accessor (`get(name, default=NA)`
and friends). When the producer renames, splits, or drops that column, the read returns the
default — so a **contract break between two files becomes indistinguishable from a null value**,
and flows onward as if it were data.

**Evidence.** A registry terminal completed green — 12/12 declared inputs consumed, vintage
matching, 136 artifacts md5-verified, `rc=0`, every mechanical gate passing — and wrote the most
quotable field in the tree:

> `MAGNITUDE: NA of 10 DSL rows clear the pre-declared gate, while the UNCORRECTED naive row does`

The underlying data was correct and unambiguous. The columns the verdict read **did not exist**:
the producer had split them by variance convention precisely to stop conflating the two, and the
consumer kept reading the old names through a defaulted accessor. Three collapses in series —
*column absent → value NA → asserted sentence* — and the second prose field on the same row
carried the identical defect.

**Why the DC-01 lints do not reach it.** This is the three-valued class at the **schema** level,
not the value level. There is no NA-capable operand, no `as.logical()` feeding a row index, no
`identical()` assigning a verdict. The missing thing is a *column*; nothing local to the
expression is wrong.

**Trigger.** Grep for defaulting accessors on column reads, then ask of each: *what happens the
day the producer renames this column?* Any answer other than "it refuses" is an instance.

**Remedy — `req(nm)`, the column-level analogue of a declared-inputs list.** Name every column
you read; return a **recorded refusal** rather than a default; and distinguish **ABSENT** (a
contract break between two files) from **PRESENT-BUT-NA** (a missing measurement) — they need
different repairs, and collapsing them loses the distinction that tells you which. The registry
solved exactly this problem one level up with `DECLARED_INPUTS`; it was never applied to columns.

**Limits.** The remedy cannot reach a producer that never distinguished the states *in memory* —
if the route is lost before the write, there is no companion to record. That case is upstream:
*don't collapse before you record.*

**Consumers.** `review-code-*` briefs §Artifact Prose Fields Are Outputs (producer semantics);
Phase-7b `verify-*` agents (emitted-value consumption, scoped per agent).

---

## DC-10 — A verifier that does not exercise the real producer *(PROVISIONAL — single-project provenance)*

**Statement.** A verification script that holds **its own copy** of the logic under test, or
builds a fixture in a shape the producer never emits, certifies the copy rather than the code.
Its green result is about an artifact that does not exist in production.

**Evidence.** Three independent instances on one run. A self-test wrote a fixture containing a
literal `TRUE` in a column the producer emits as an **integer count** — it passed against a shape
the producer has never written, and the deferred item it "cleared" was reported closed on that
evidence. A guard's detector matched a column-name **prefix**, so it selected two count columns
and compared integers against boolean literals, making it structurally incapable of firing on the
one artifact family it was written for. And four wrappers verified `analysis_table.parquet` while
all four estimators read `analysis_table.csv`.

**Trigger.** For each verification script ask: *does this exercise the real producer, and would it
fail if the code under test were wrong?* If the fixture is hand-built, does its schema match what
the producer actually writes — dtypes included, not just column names?

**Remedy.** Extract the logic under test **from the module itself** rather than copying it; build
fixtures from a real producer run where possible; and give every guard test a **negative control**
— an input that must make it fire. A test with no negative control cannot distinguish "the guard
works" from "the guard cannot fire".

**Limits.** A negative control proves the guard fires on *the* case you thought of. It says
nothing about cases you did not.

---

## DC-11 — A guard that cannot look, but permits *(PROVISIONAL — single-project provenance)*

**Statement.** A protective check meets a state it cannot evaluate — unreadable file, unparseable
schema, absent dependency — and **grants permission** rather than refusing. It fails open in
exactly the state where its protection is most needed.

**Evidence.** A refusal guard protecting a file from being clobbered carried
`except Exception: return  # unreadable -> treat as absent`, so the one file it protects, in the
one state where it could verify nothing, was granted permission. A LOCAL_MODE leak audit reported
`0 leaks, PASS` and would have printed the same with its parser library absent, having inspected
zero schemas. A bare `except: return []` made unreadable parquet indistinguishable from clean
parquet, because `[]` was that function's word for *clean*.

**Trigger.** Read every `except`/`tryCatch`/`|| true` inside a guard and ask what the caller
concludes from the fallback value. If the fallback is the same value the guard returns for
"looked, found nothing", it fails open.

**Trigger 2 — the binary classifier (added 2026-08-16).** The trigger above searches for a
*swallowed error*, and on 2026-08-16 it missed a live instance for that reason: there was no
`except` and no `|| true` anywhere near it. Also ask, of every predicate a gate uses to reach a
verdict: **what does the FALSE branch mean?** If a two-valued predicate answers "did I find
failure?", then "no" silently merges *I looked and it is clean* with *I could not tell*, and the
pass path is reached by both. Greppable form: a helper whose body is a single `grep -q`, called
as `if is_bad "$f"; then …fi` with no third branch. Three instances found the day the shape was
named, all in gates written to enforce other classes:

| Site | Two-valued predicate | What "false" silently meant |
|---|---|---|
| A review-iteration gate's `is_red()` | one `grep -qE` for `^STATUS=(RED\|FAIL)$` | six reports each stating `STATUS: RED` (colon) were unreadable, so the gate printed `STATUS=GREEN` / "no agent's highest review iteration is RED" with 22 `NUMBER_EFFECT: YES` findings open |
| A model-specification lint | `FORMULAS_RESOLVED == 0` as the refusal boundary | resolving 2 of 14 formulas printed `STATUS=GREEN`, "no violations detected" — a claim about 14 established for 2 |
| That lint's arm in the phase gate | `exit 3` treated as one state | the gate's two INERT reasons ("nothing to lint" and "I could not assess") were both skipped silently, making a prior refusal fix unreachable by any human |

**Corollary — a refusal that reaches nobody is not a guard.** The third state must survive the
*consumer*, not merely be emitted. Two of the three sites above were gates that already refused
correctly; the defect was one layer out, in the code reading the refusal. When adding a
could-not-assess state, patch its consumer in the same change and prove it surfaces.

**Remedy.** Three states, never two: **clean / dirty / could-not-assess**. A guard that cannot
look must refuse, not permit — and the refusal must be distinguishable in the artifact, not only
on stdout. Gate-level analogue: never emit a verdict the check did not establish, and never print
a remediation instruction on a path where the check did not run.

**Limits.** Recording the third state on stdout while the *artifact* still carries the definite
one reproduces the class one layer out; the companion must be written where the consumer reads.

---

## Candidate classes — NOT yet standing review instructions

These have single-project provenance and, unlike DC-08/10/11, are **not** coupled to a shipped
contract. Per CLAUDE.md Working Discipline rule 10 they are recorded here so the evidence is not
lost, and deliberately **not** added to the six `review-code-*` sweep lists: every class added
there becomes standing reviewer workload on every project, and eight at once would dilute
attention and raise false-positive load faster than it raises yield.

**Promotion threshold.** A candidate becomes a DC-xx when *either* a peer project on a different
orchestrator path reproduces it, *or* hand-built fixtures cover every syntactic shape its trigger
could plausibly match (rule 10's two routes).

| Candidate | One-line mechanism | Evidence |
|---|---|---|
| `assert` disabled under optimization | Python strips `assert` under `-O`/`PYTHONOPTIMIZE=1`, and wrappers submitting with `--export=ALL` propagate it; a `--selftest` returns `rc=0` having asserted nothing. Remedy: a **canary** — the self-test first calls `_must(False, …)` and refuses to proceed unless it raises. | one run, one wrapper family |
| Success message counts arguments, not work | `OK: N file(s) match <pin>` where N was `len(argv)-2` — the number of arguments *offered*, printed nine times at several of which the checker hashed nothing. Generalizes U7 from linters to every guard's success line. | one run |
| `str(None)` is truthy | `str(None)` → the string `"None"`, which then satisfies a truthiness test and raises a **graver** false alarm ("labels drawn from a different build") than the truth (an unstamped manifest). | one run |
| Read-modify-write with a tolerant read | Two scripts both read-modify-**write** a shared manifest with `except: manifest = {}`, so a partial read caused each to silently delete the other's provenance and republish the file as whole. | one run |
| Prefix-vs-exact match in a stamp consumer | A detector matched a column-name prefix and so could never fire on the family it was written for. *(Folded into DC-10's evidence; listed here as its own trigger shape.)* | one run |

---

## DC-08 — A defaulted column read *(PROVISIONAL — single-project provenance)*

**Statement.** A consumer reads a column through a defaulting accessor (`get(name, default=NA)`
and friends). When the producer renames, splits, or drops that column, the read returns the
default — so a **contract break between two files becomes indistinguishable from a null value**,
and flows onward as if it were data.

**Evidence.** A registry terminal completed green — 12/12 declared inputs consumed, vintage
matching, 136 artifacts md5-verified, `rc=0`, every mechanical gate passing — and wrote the most
quotable field in the tree:

> `MAGNITUDE: NA of 10 DSL rows clear the pre-declared gate, while the UNCORRECTED naive row does`

The underlying data was correct and unambiguous. The columns the verdict read **did not exist**:
the producer had split them by variance convention precisely to stop conflating the two, and the
consumer kept reading the old names through a defaulted accessor. Three collapses in series —
*column absent → value NA → asserted sentence* — and the second prose field on the same row
carried the identical defect.

**Why the DC-01 lints do not reach it.** This is the three-valued class at the **schema** level,
not the value level. There is no NA-capable operand, no `as.logical()` feeding a row index, no
`identical()` assigning a verdict. The missing thing is a *column*; nothing local to the
expression is wrong.

**Trigger.** Grep for defaulting accessors on column reads, then ask of each: *what happens the
day the producer renames this column?* Any answer other than "it refuses" is an instance.

**Remedy — `req(nm)`, the column-level analogue of a declared-inputs list.** Name every column
you read; return a **recorded refusal** rather than a default; and distinguish **ABSENT** (a
contract break between two files) from **PRESENT-BUT-NA** (a missing measurement) — they need
different repairs, and collapsing them loses the distinction that tells you which. The registry
solved exactly this problem one level up with `DECLARED_INPUTS`; it was never applied to columns.

**Limits.** The remedy cannot reach a producer that never distinguished the states *in memory* —
if the route is lost before the write, there is no companion to record. That case is upstream:
*don't collapse before you record.*

**Consumers.** `review-code-*` briefs §Artifact Prose Fields Are Outputs (producer semantics);
Phase-7b `verify-*` agents (emitted-value consumption, scoped per agent).

---

## DC-10 — A verifier that does not exercise the real producer *(PROVISIONAL — single-project provenance)*

**Statement.** A verification script that holds **its own copy** of the logic under test, or
builds a fixture in a shape the producer never emits, certifies the copy rather than the code.
Its green result is about an artifact that does not exist in production.

**Evidence.** Three independent instances on one run. A self-test wrote a fixture containing a
literal `TRUE` in a column the producer emits as an **integer count** — it passed against a shape
the producer has never written, and the deferred item it "cleared" was reported closed on that
evidence. A guard's detector matched a column-name **prefix**, so it selected two count columns
and compared integers against boolean literals, making it structurally incapable of firing on the
one artifact family it was written for. And four wrappers verified `analysis_table.parquet` while
all four estimators read `analysis_table.csv`.

**Trigger.** For each verification script ask: *does this exercise the real producer, and would it
fail if the code under test were wrong?* If the fixture is hand-built, does its schema match what
the producer actually writes — dtypes included, not just column names?

**Remedy.** Extract the logic under test **from the module itself** rather than copying it; build
fixtures from a real producer run where possible; and give every guard test a **negative control**
— an input that must make it fire. A test with no negative control cannot distinguish "the guard
works" from "the guard cannot fire".

**Limits.** A negative control proves the guard fires on *the* case you thought of. It says
nothing about cases you did not.

---

## DC-11 — A guard that cannot look, but permits *(PROVISIONAL — single-project provenance)*

**Statement.** A protective check meets a state it cannot evaluate — unreadable file, unparseable
schema, absent dependency — and **grants permission** rather than refusing. It fails open in
exactly the state where its protection is most needed.

**Evidence.** A refusal guard protecting a file from being clobbered carried
`except Exception: return  # unreadable -> treat as absent`, so the one file it protects, in the
one state where it could verify nothing, was granted permission. A LOCAL_MODE leak audit reported
`0 leaks, PASS` and would have printed the same with its parser library absent, having inspected
zero schemas. A bare `except: return []` made unreadable parquet indistinguishable from clean
parquet, because `[]` was that function's word for *clean*.

**Trigger.** Read every `except`/`tryCatch`/`|| true` inside a guard and ask what the caller
concludes from the fallback value. If the fallback is the same value the guard returns for
"looked, found nothing", it fails open.

**Trigger 2 — the binary classifier (added 2026-08-16).** The trigger above searches for a
*swallowed error*, and on 2026-08-16 it missed a live instance for that reason: there was no
`except` and no `|| true` anywhere near it. Also ask, of every predicate a gate uses to reach a
verdict: **what does the FALSE branch mean?** If a two-valued predicate answers "did I find
failure?", then "no" silently merges *I looked and it is clean* with *I could not tell*, and the
pass path is reached by both. Greppable form: a helper whose body is a single `grep -q`, called
as `if is_bad "$f"; then …fi` with no third branch. Three instances found the day the shape was
named, all in gates written to enforce other classes:

| Site | Two-valued predicate | What "false" silently meant |
|---|---|---|
| `iter2-required-check.sh` `is_red()` | one `grep -qE` for `^STATUS=(RED\|FAIL)$` | six reports each stating `STATUS: RED` (colon) were unreadable, so the gate printed `STATUS=GREEN` / "no agent's highest review iteration is RED" with 22 `NUMBER_EFFECT: YES` findings open |
| `model-spec-lint.sh` | `FORMULAS_RESOLVED == 0` as the refusal boundary | resolving 2 of 14 formulas printed `STATUS=GREEN`, "no violations detected" — a claim about 14 established for 2 |
| `phase-verify.sh` model-spec-lint arm | `exit 3` treated as one state | the gate's two INERT reasons ("nothing to lint" and "I could not assess") were both skipped silently, making a prior U7 refusal fix unreachable by any human |

**Corollary — a refusal that reaches nobody is not a guard.** The third state must survive the
*consumer*, not merely be emitted. Two of the three sites above were gates that already refused
correctly; the defect was one layer out, in the code reading the refusal. When adding a
could-not-assess state, patch its consumer in the same change and prove it surfaces.

**Remedy.** Three states, never two: **clean / dirty / could-not-assess**. A guard that cannot
look must refuse, not permit — and the refusal must be distinguishable in the artifact, not only
on stdout. Gate-level analogue: never emit a verdict the check did not establish, and never print
a remediation instruction on a path where the check did not run.

**Limits.** Recording the third state on stdout while the *artifact* still carries the definite
one reproduces the class one layer out; the companion must be written where the consumer reads.

---

## Candidate classes — NOT yet standing review instructions

These have single-project provenance and, unlike DC-08/10/11, are **not** coupled to a shipped
contract. Per CLAUDE.md Working Discipline rule 10 they are recorded here so the evidence is not
lost, and deliberately **not** added to the six `review-code-*` sweep lists: every class added
there becomes standing reviewer workload on every project, and eight at once would dilute
attention and raise false-positive load faster than it raises yield.

**Promotion threshold.** A candidate becomes a DC-xx when *either* a peer project on a different
orchestrator path reproduces it, *or* hand-built fixtures cover every syntactic shape its trigger
could plausibly match (rule 10's two routes).

> **Second-project evidence for DC-01, DC-02, DC-03, DC-04, DC-07, DC-10 and DC-11** was produced by
> `premarital-cohab-mh-sociology` Phase 5A.5 (three six-seat review rounds, two fix rounds,
> 2026-08-25). It is recorded in one place rather than inlined into seven sections:
> `output/auto-improve/tooling-defects-from-premarital-cohab-2026-08-25.md`. That document also
> carries five concrete suite tooling defects with file:line and proposed fixes.
> **DC-03 is quantified there for the first time**: fix round 1 took 40 findings and created 11 new
> blocking defects; fix round 2 took 11 and created ~10 — with **zero regressions** in either round.
> Nothing broke twice; new surface generated new defects at roughly the rate old ones closed. Both
> fix agents were careful and their escalations were verified honest by three independent seats,
> which is the point: DC-03 is not a class about carelessness.

| Candidate | One-line mechanism | Evidence |
|---|---|---|
| `assert` disabled under optimization | Python strips `assert` under `-O`/`PYTHONOPTIMIZE=1`, and wrappers submitting with `--export=ALL` propagate it; a `--selftest` returns `rc=0` having asserted nothing. Remedy: a **canary** — the self-test first calls `_must(False, …)` and refuses to proceed unless it raises. | one run, one wrapper family |
| Success message counts arguments, not work | `OK: N file(s) match <pin>` where N was `len(argv)-2` — the number of arguments *offered*, printed nine times at several of which the checker hashed nothing. Generalizes U7 from linters to every guard's success line. | one run |
| `str(None)` is truthy | `str(None)` → the string `"None"`, which then satisfies a truthiness test and raises a **graver** false alarm ("labels drawn from a different build") than the truth (an unstamped manifest). | one run |
| Read-modify-write with a tolerant read | Two scripts both read-modify-**write** a shared manifest with `except: manifest = {}`, so a partial read caused each to silently delete the other's provenance and republish the file as whole. | one run |
| Prefix-vs-exact match in a stamp consumer | A detector matched a column-name prefix and so could never fire on the family it was written for. *(Folded into DC-10's evidence; listed here as its own trigger shape.)* | one run |
| A capability flag read as the capability | The platform's own self-report is wrong: `capabilities("cairo")` returns `TRUE` on a host where `cairo_pdf` cannot load its DLL, writes no file, and degrades as a **warning** — so `tryCatch(..., error=)` reports success while producing nothing (measured: `usable: TRUE \| file exists: FALSE`). Distinct from DC-10: the verifier *did* exercise the producer, but asked the platform instead of opening the device. Remedy: open the device, draw, close, and assert `file.size > 0`; never query a capability flag. | one run (premarital-cohab 5A.5); reached the orchestrator's own reported conclusion, then a fix that aborted every run, then a probe that passed on its own motivating failure — three rounds |
| A closeness threshold used to test provenance | A checker compares a recomputed value against a printed one within a magnitude tolerance and reports MATCH, when the defect is that the printed value was computed on a **superseded sample**. `42.3%` vs `41.7%` passed a ±1.0pp test; the `41.7%` was `2305/5530` from a withdrawn design, not `2056/4866` from the live one. A tolerance tests magnitude and cannot see provenance. Remedy: assert the *source* (script, sample definition, row count), not the number. | one run |
| A decision artifact invalidated by the fix made to unblock it | A fix removes a spec/branch/row, and the human-readable note a decision-maker reads to make the *blocked* decision still describes the pre-fix world. Twice in one run: a staleness constant, and `_families.H1.note` reading `K = 8 … three links` after the round's own fix deleted the third link — the exact text a PI reads to re-put a suspended ratification. Remedy: recompute decision-facing notes from the emitted rows; never type them. | one run, two sites |
| A brief that asserts the absence of a rule written minutes later | `emit-fix-brief.sh` stamps `PI scoping rule (ABSENT — do NOT infer one)` when the section is missing. The rule was written 15 minutes into the briefed agent's run; the agent found the live rule, and its override forbade two fixes it had already built and tested. An absent-field stamp and a not-yet-written field are indistinguishable, and the stamp hands the agent the **negation** of the rule. Remedy: stamp the source file's mtime+sha beside the rule *or* its absence. | one run; measured cost of two completed fixes discarded |

---

## How to add a class

1. Confirm it recurs — ≥2 independent sites, or it survived ≥2 review passes.
2. State it as a **mechanism**, not a symptom, in one sentence.
3. Give the evidence table: site → what the code does → what the reader concludes.
4. Give a **countable or greppable trigger** where one exists, and say plainly where none does.
5. Name the remedy AND its constraints — a remedy with an unstated constraint becomes the next
   entry (see DC-01 shape D, constraint 2).
6. Cross-reference the consuming briefs and gates so the class is swept, not just filed.


## DC-PARTIAL — the partial correction (CANDIDATE, orchestrator-side)

**Shape.** A factual claim is corrected at the instance the reporter named, and left standing at its
other instances. The corrected and uncorrected versions then coexist, and the author cannot see the
contradiction because their own record says "corrected".

**Distinguishing test.** After any correction, does a project-wide search for the claim return
survivors outside an explicitly SUPERSEDED block? If yes, the correction is partial.

**Why existing tooling misses it.** `fix-contract-verify.sh --phase AFTER` is a pattern-ABSENCE
check scoped to the reported instance. It returns GREEN on a partial correction by construction.

**Evidence.** 9 instances in `premarital-cohab-mh-sociology` (2026-08-25), 5 caught by >=2
independent seats, 1 reaching a manuscript-facing artifact. Full write-up:
`planning/2026-08-25-orchestrator-partial-fix-defect-class.md`.

**Status.** CANDIDATE — one project. Needs the rule-10 sweep across >=3 peers before promotion.

**Related.** DC-03 (a fix commit is a fresh unaudited surface) is the sibling: DC-03 is about defects
the fix INTRODUCES, DC-PARTIAL is about defects the fix FAILS TO REACH.

---

## DC-PROXY — the checker measures a correlate of the property (CANDIDATE)

**Shape.** A gate measures a **surface signal that accompanies** the property it is meant to
guarantee, and reports on the signal as though it were the property. The gate looks, succeeds, and
answers a different question than the one it is trusted to answer.

**Distinguishing test — and why DC-11 does not cover this.** DC-11 ("a guard that cannot look, but
permits") is a fail-open on an **unevaluable** state; its trigger is *read every
`except`/`tryCatch`/`|| true` and ask what the caller concludes from the fallback*. That trigger
finds **none** of the instances below, because there is no swallowed error to find — these gates
evaluate cleanly. The trigger here is different:

> Write down, in one sentence, the property the gate exists to guarantee. Write down what the code
> actually measures. If a reader could satisfy the second sentence while making the first false,
> the gate measures a proxy. Then ask the operative question: **is the gap reachable by ordinary
> work, or only by deliberate evasion?** A proxy that only a bad actor could exploit is acceptable;
> one that a diligent author crosses by accident is a defect.

**Evidence** (8 instances, 2 projects, 2026-08-25 → 2026-08-27):

| Gate | Measures (proxy) | Guarantees (property) |
|---|---|---|
| `phase-verify.sh 10` | reviewers were dispatched | the review was favourable |
| citation stack (22 gates) | the reference exists | the reference supports the sentence |
| `preregistration-url-check.sh` | the keyword appears | the manuscript claims pre-registration |
| apparatus prose (no gate) | a sentence says the code does X | the code does X |
| project digest coverage | a pattern list matches | every artifact is covered |
| `coef-map-check.sh` | `modelsummary()` is called | labels are human-readable |
| `control-set-coverage-check.sh` | gate B will check | the property is checked |
| trace protocol (pre-v5.39) | the skill declares an emit | a row was emitted |

Two were measured end to end on 2026-08-27: the pre-registration gate RED-failed an honest denial
under both `PREREG_TYPE` unset and `none`, and prescribed deleting the disclosure; the Phase-10 gate
PASSes a panel returning 3 MAJOR REVISION + 1 REJECT.

**The trap when fixing one.** The replacement check is itself liable to this class. While fixing the
bib-brace defect the ratchet was written as *"this regex text does not appear in the file"*, which
fired on the fix's own explanatory comment quoting the old regex — the proxy ("text appears") stood
in for the property ("code uses the pattern"), and satisfying it would have required deleting an
accurate comment. Assert against the code, not the file.

**The same substitution happens in the ANALYST, not only in the checker** (added 2026-08-27 from
four instances in one day, across two independent sessions). Reading code and concluding what it
does is a proxy for running it. All four wrong answers were *plausible*:

- reading `FIELD_RE` and concluding "truncates" — it drops the field (opposite direction, and the
  opposite severity: false negative, not false positive);
- naming `is_bulk_rows` as the cause of a redaction — the real trigger was an NER surname match on
  the eponym `Holm`, and the bulk-row floor (>200 lines) was never approached;
- comparing a gate's old and new behaviour by copying the old version to a scratch directory — the
  copy's `dirname "$0"` sibling lookup silently failed, so a helper that was *skipped* read as a
  helper that *passed*;
- filing a manuscript finding from a variable's name and its comments rather than dumping its
  labels (the 2026-08 false RETRACTION).

The failure is not carelessness. **Plausibility feels like verification and costs nothing to
produce; execution costs a command.** Both sessions caught their own only by running the thing.
Practical remedy: prefer filing *"unexplained — here is what I measured"* over a clean causal story
that was inferred. A stated mechanism that was never executed is a hypothesis, and should be
labelled as one.

**Status.** CANDIDATE — two projects, and deliberately **not** added to the six `review-code-*`
sweep lists. Per rule 10 and this registry's own promotion note, a class added there becomes
standing reviewer workload on every project; this one needs the ≥3-peer sweep first. Recorded here
so the evidence is not lost.

**Related.** DC-11 is the fail-open sibling (cannot look → permits); DC-PROXY looks and measures the
wrong thing. DC-06 ("presence checked where vintage is meant") is a narrow special case of this
shape, already promoted on its own evidence.
