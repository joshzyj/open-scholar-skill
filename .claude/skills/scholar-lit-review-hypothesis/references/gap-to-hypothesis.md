# From Gap to Hypothesis: The Bridge Guide

This file covers the critical transition from literature synthesis to theory to hypotheses — the step where most papers either succeed or fail. A paper that identifies a genuine gap but then applies a generic theory has weak theoretical contribution. A paper that selects a framework precisely because it addresses the identified gap makes a distinct intellectual move.

---

## 1. Matching Gap Types to Framework Types

Each type of explanatory gap calls for a different theoretical move.

### Gap Type 1: Population / Context Gap
*The X→Y relationship is established, but only in population A or context C. You are testing it in population B or context D.*

**Theoretical move**: Apply the existing framework to the new context AND specify why the mechanism should operate differently — or the same — there.
- If you expect the same mechanism: justify the generalization (scope conditions transfer)
- If you expect a different magnitude: specify a moderating condition that differs between contexts
- If you expect the mechanism to fail: name what structural condition in context D blocks the mechanism

**Framework selection**: The canonical framework for the X→Y relationship is your starting point. Your theoretical contribution is specifying scope — not importing a new framework wholesale.

**Weak version**: "We extend [Theory X] to [new population]."
**Strong version**: "We extend [Theory X] to [new population], predicting that the mechanism will be attenuated/amplified because [specific structural condition differs], which changes [the key assumption of Theory X]."

---

### Gap Type 2: Mechanism Gap
*The X→Y association is empirically established, but the pathway (M) has never been directly tested.*

**Theoretical move**: Select a framework that specifies the pathway — not just predicts the association. The framework must name the intermediate process.

**Framework selection checklist**:
- Does the framework name a specific intermediate state or process (M)?
- Can M be measured with available data?
- Does the framework predict a specific *pattern* of mediation — full, partial, or conditional?

**Common error**: Proposing a mediator that is implied by the outcome, not logically prior to it (circularity). Fix: confirm the temporal order and independence of X, M, and Y.

**Hypothesis format for mechanism tests**:
> H1: X is positively associated with Y.
> H2: The X→Y association is partially explained by M (mediation hypothesis).
> H3: The indirect effect of X on Y through M is stronger under condition Z (moderated mediation).

---

### Gap Type 3: Identification Gap
*The X→Y association is found in observational studies, but causality is uncertain due to confounding, selection, or reverse causation.*

**Theoretical move**: The theoretical contribution is not a new framework — it is articulating precisely WHY X causes Y (the mechanism), which also explains WHY selection/confounding are unlikely under your design.

**Framework selection**: The mechanism you specify is the argument FOR why you expect a causal effect. It should:
1. Be logically prior to Y (temporal ordering)
2. Be plausibly exogenous (not caused by Y or by unobserved confounders)
3. Operate through a named process that your design can partially test

**Hypothesis format for identification papers**:
> H1 (causal claim): Exposure to [X] *causes* [Y] through [mechanism M], as evidenced by [design feature: RD, IV, DiD].
> H2 (mechanism test): The effect of X on Y is attenuated when M is held constant — consistent with M as the operative pathway.

**Tone guidance**: Identification papers should state the causal hypothesis directly; hedge only where the design has clear limitations. Use "we estimate the effect of" rather than "we examine the association between."

---

### Gap Type 4: Theoretical Debate Gap
*Two or more theories make conflicting predictions about X→Y. No prior study has designed a test that adjudicates between them.*

**Theoretical move**: Explicitly derive the competing predictions from each theory and show that your data/design can distinguish them.

**Framework selection**: Present BOTH theories fairly. The contribution is the test, not declaring one theory correct a priori.

**Hypothesis format for debate adjudication**:
> H1a (Theory A): X is *positively* associated with Y because [mechanism A].
> H1b (Theory B): X is *negatively* associated with Y because [mechanism B].
> *Our design distinguishes H1a from H1b by [design feature or subgroup test].*

**Common error**: Framing as "we test Theory A" when you have already decided Theory A is correct. Fix: maintain genuine uncertainty; let the evidence adjudicate; discuss what a null result or a Theory B result would mean.

---

## 2. Mechanism Specification Templates

Use these to move from "I have a theory" to "I have a testable mechanism."

### Template A: Single Mediator Chain
```
[X] → [M: mediating state or process] → [Y]

Theoretical basis: [Theory] predicts X increases M because [logic].
                   [Theory] predicts M increases Y because [logic].
Testable implication: Controlling for M should attenuate the X→Y coefficient.
```

### Template B: Moderated Effect (Heterogeneity)
```
[X] → [Y]
      ↕ moderated by [Z: condition/group]

Theoretical basis: [Theory] predicts the X→Y relationship only holds when [Z condition].
Testable implication: Interaction term X×Z; effect size differs for Z=1 vs. Z=0.
```

### Template C: Moderated Mediation
```
[X] → [M] → [Y]
            mediation stronger when [Z = high]

Theoretical basis: M mediates X→Y, but the indirect path is conditional on Z.
Testable implication: Conditional indirect effects; test using moderated mediation.
```

### Template D: Competing Pathways
```
[X] → [M1: pathway 1] → [Y]   (Theory A)
[X] → [M2: pathway 2] → [Y]   (Theory B)

Both predict same X→Y direction but via different M.
Testable implication: Include both M1 and M2; test which attenuates X→Y coefficient more.
```

### Template E: Suppression / Countervailing Forces
```
[X] → [Y] directly: positive effect
[X] → [M] → [Y]: negative indirect effect via M

Net observed X→Y may be null even with both processes active.
Testable implication: Include M; the direct effect and indirect effect should have opposite signs.
```

---

## 3. Hypothesis Writing Rules

**Rule 1: Every hypothesis must name a theory.**
Bad: "We expect higher income to predict better health."
Good: "Consistent with fundamental cause theory (Link and Phelan 1995), we hypothesize that higher income is positively associated with health outcomes because income provides access to flexible resources that can be used to avoid or minimize multiple health risks (H1)."

**Rule 2: Directional predictions only.**
Bad: "Income and health will be related."
Good: "Income will be positively associated with self-rated health."

**Rule 3: Scope conditions in the hypothesis, not just in prose.**
Bad: "We expect income effects on health to be moderated by race."
Good: "We expect the positive income–health association to be weaker among Black Americans than white Americans, because [mechanism: structural racism limits the health-protective resources that income can purchase for Black Americans]."

**Rule 4: Distinguish confirmatory from exploratory.**
If a prediction is exploratory (you do not have a strong directional prior), flag it:
> "We have no strong directional expectation for [X₂] on Y; we examine this exploratorily."

**Rule 5: Intersectionality hypotheses require interaction language.**
Bad: "We expect effects to differ by race and gender."
Good: "We expect the effect of [X] on [Y] to be larger for Black women than for white women or Black men — a multiplicative disadvantage that cannot be predicted from race effects or gender effects alone (H3; Crenshaw 1989; Collins 1990)."

**Rule 6: Number hypotheses sequentially and refer back to them consistently.**
H1 in the theory section must match H1 in the analytic strategy and in the results. Renaming after submission is a common source of reviewer complaints.

---

## 4. Common Failure Modes in the Gap-to-Hypothesis Pipeline

### Failure 1: The Generic Theory Application
**Symptom**: "We draw on social capital theory, which has been widely applied to [topic], to predict that [X] increases [Y]."
**Problem**: No connection between what the lit review said is missing and why social capital theory addresses that absence.
**Fix**: State the specific gap; explain which claim of social capital theory generates the missing prediction; derive the hypothesis from that claim.

### Failure 2: The Floating Mechanism
**Symptom**: A mechanism is named in prose ("this occurs through network processes") but never operationalized or tested.
**Problem**: Cannot distinguish whether the framework is correct.
**Fix**: Identify a mediator variable that can be measured; include it in the analysis or acknowledge it as a scope limitation.

### Failure 3: The Kitchen Sink Theory Section
**Symptom**: 5–6 theories are reviewed with equal emphasis; hypotheses come from different theories with no integration.
**Problem**: Reviewers cannot identify the paper's theoretical contribution; the hypotheses feel arbitrary.
**Fix**: Select 1–2 frameworks; justify the selection; show the other frameworks are insufficient for this gap.

### Failure 4: Circular Gap Claim
**Symptom**: "No study has examined X in our specific sample."
**Problem**: Sample novelty is not a gap unless you can explain WHY findings should differ in your sample (a theoretical reason).
**Fix**: State why the mechanism should operate differently (or the same) in the new context; derive a prediction specific to that difference.

### Failure 5: Hypotheses That Follow Trivially From Prior Work
**Symptom**: H1 is already well-established; the paper replicates it with a slightly different dataset.
**Problem**: Low contribution; reviewers will ask "what is new here?"
**Fix**: Reframe H1 as a baseline; make the primary contribution H2 (a mechanism test, a heterogeneity finding, or a scope condition).

---

## 5. Transition Phrases: From Lit Review to Theory

These phrases bridge the synthesis of existing work to your theoretical argument:

**Introducing the gap from the lit review:**
- "Despite this progress, one question remains unaddressed: …"
- "What this literature cannot tell us is whether…"
- "Prior studies have documented the association but have not directly examined the mechanism."
- "The debate between Theory A and Theory B has not been resolved because no study has…"

**Introducing your theoretical argument:**
- "We draw on [Theory X] to address this gap."
- "To explain [outcome], we propose a [mechanism name] account, drawing on [theoretical tradition]."
- "Building on [Author Year]'s argument that [core claim], we extend this framework to [new context]."
- "We depart from prior applications of [Theory X] in one key respect: …"

**Deriving the hypothesis from the argument:**
- "This argument leads to our first hypothesis:"
- "If [mechanism] operates as theorized, we should observe that…"
- "The [framework] therefore predicts a positive / negative association between X and Y (H1)."
- "Extending this logic to [moderation condition], we further predict that… (H2)."

**Acknowledging alternatives:**
- "An alternative explanation is [Theory B], which predicts [rival outcome]."
- "We address this alternative by [control / design feature / subsample test]."
- "If [alternative] drives the results, we should also observe [implication]; we test this directly."

---

## 6. Checklist: Is Your Gap-to-Hypothesis Pipeline Complete?

Before finalizing the theory section, verify:

- [ ] The gap statement cites a specific prior paper and says exactly what it leaves open
- [ ] The selected framework was chosen BECAUSE it addresses that gap — the connection is explicit
- [ ] The mechanism is stated as X → M → Y [under condition C]
- [ ] M is measurable or the limitation is acknowledged
- [ ] H1 follows logically from the mechanism (not just from the framework in general)
- [ ] H2 (if present) tests a scope condition, mediation, or moderation — not a restatement of H1
- [ ] At least one alternative prediction is named and addressed
- [ ] All hypotheses are numbered and directional
- [ ] Intersectional hypotheses use interaction language
- [ ] The theory section reads as a single argument — not a menu of theories
