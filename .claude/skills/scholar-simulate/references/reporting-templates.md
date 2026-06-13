# Reporting Templates (MODE 9: report)

This file is loaded by **MODE 9 (report)**. Its job: assemble the Methods text, the journal-required reporting block, and the mandatory Limitations content so the write-up is reproducible and honest about what synthetic data can and cannot support.

**Division of labor.** Downstream estimation (AME tables, regression output) is produced by the **R** analysis pipeline, not here. Citations are delegated to **`/scholar-citation`** — never hand-author `.bib`; flag unverified claims `[CITATION NEEDED]`. Limitation content belongs to the **Discussion -> Limitations subsection only** (do not scatter it into Methods or Results).

A `report` claiming publishability MUST reference a passing fidelity artifact from MODE 6, confirmed by the verification subagent.

---

## Methods-text template (fill every bracket)

> "We use [exact model id, e.g., claude-haiku-4-5-20251001] to simulate [N] synthetic respondents using structured demographic personas (Argyle et al. 2023). Personas were sampled from [source -- e.g., ACS 2022 marginal distributions raked to a joint via iterative proportional fitting], encoding [list dimensions: age, gender, race/ethnicity, education, income, region, political affiliation, religious attendance, employment]. We elicited responses to [N_items] items covering [topic domains]. Each persona x item [x condition] was replicated [n_reps] times (temperature = [T]; seed = [42]) to capture within-persona stochasticity; the synthetic response is the replicate mean, weighted by the post-stratification weight. The run was executed via [batch / async / local] on [provider]; the full run manifest, prompts, and checkpoints are archived (Appendix [X]). To validate, we compared synthetic distributions against a held-out [GSS YYYY / ANES YYYY / CCES YYYY / original survey, N = ____] sample, disjoint from any calibration sample: Kolmogorov-Smirnov statistics ranged [lo]-[hi], Jensen-Shannon divergence [lo]-[hi], and subgroup-mean correlation was r = [____] (Table SX). Following Bisbee et al. (2023), synthetic data reproduces aggregate group-level patterns [adequately / imperfectly] but understates within-group variance for [groups]. We therefore use synthetic data for [pre-testing / power analysis / theory exploration] only, and confirm all substantive findings with [real human data source]."

The Methods text MUST name, explicitly: **paradigm; provider + exact model id; temperature + seed; persona source; N; n_reps; fidelity results.**

### Vignette / conjoint addendum

> "We embed a [2x2 / fully-crossed] experimental manipulation within the persona simulation: [factor 1] x [factor 2], holding other attributes constant. We collected [N] responses per condition. The outcome is [7-point rating / binary decision]. We estimate the simulated effect as an average marginal effect (AME), with standard errors clustered within persona (each persona contributes correlated responses across arms). The simulated [racial / gender] gap was AME = [____] (clustered SE = [____]); we benchmark this against [published audit study / own data]: real gap = [____]. This is a simulated effect, not a real-world causal estimate."

---

## NCS / Science Advances required-reporting block

> - Report KS statistic and Jensen-Shannon divergence between synthetic and real distributions for **every key variable**.
> - Report **subgroup-level** alignment (by race, party, education) and the subgroup-mean correlation -- not aggregate only.
> - Report coverage / homogenization diagnostics (synthetic-vs-real SD ratio); state whether the synthetic distribution collapses toward the scale midpoint.
> - Explicitly state that synthetic data is used for [pre-testing / power analysis / theory development], **not** as a substitute for human data.
> - If used for published substantive claims: provide matched real-data replication.
> - **ABM runs:** include the full ODD protocol (Appendix), the parameter sweep (SALib Saltelli; Sobol S1 and ST), network topology with justification, and sensitivity to >=2 alternative topologies.
> - Pin the exact model id and date; archive all prompts verbatim and a sample of raw responses; report the random seed.

---

## Opinion-dynamics reporting paragraph

> "We simulate opinion dynamics among N = [X] agents arranged on a Watts-Strogatz small-world network (k = [K], rewiring probability p = [P]; seed = 42). Agents are assigned demographic personas drawn proportionally from [source]. At each of [T] time steps, agents update their position on [topic] after observing the current opinions of their [K] network neighbors, using [exact model id] as the cognitive engine (temperature = [0.2]; synchronous update). We track the Gini coefficient of opinion heterogeneity and the partisan opinion gap (Strong Democrat - Strong Republican) across steps. Sensitivity to topology (Erdos-Renyi p = [0.08]; Barabasi-Albert m = [2]) is reported in Figure A[X]; qualitative patterns [hold / vary by topology]."

---

## Interactive paradigm (MODE 10) reporting paragraph

For multi-turn, multi-agent **conversations** (focus group, deliberation panel, negotiation dyad, simulated interview) run through `interactive_runner.py` (LangGraph + LangChain), the Methods text is conversational, not distributional. Name the topology, the agent roster and persona grounding, the turn budget, the exact model, and — critically — the validation status.

> "We ran [N_conversations] simulated [focus-group / deliberation / negotiation] conversations using a LangGraph multi-agent graph with a [round-robin / dyad / supervisor] topology. Each conversation seated [K] agents ([list roles]; agents [were / were not] grounded in synthetic personas drawn from our raked population, Argyle et al. 2023) and ran for up to [max_turns] turns ([termination rule: max_turns / agent-emitted stop signal]). Each agent was driven by [exact model id, e.g., llama3.1:8b via Ollama] at temperature = [T] (seed = [42]). The LangGraph native checkpointer persisted per-conversation state (thread_id = conversation_id); we exported a flattened transcript (`transcripts.jsonl`, one utterance per line keyed conversation|turn|agent) for analysis, and archive the manifest, the checkpoint store (`graph.sqlite`), and the transcript. **Because we have no held-out human-transcript benchmark on this scenario, these conversations are UNVALIDATED-EXPLORATORY: they informed [protocol design / hypothesis generation] only and support no substantive claim.** [If a human benchmark exists: We compared descriptive interaction statistics — turns per agent, message-length distribution, turn-taking balance[, and coded stance trajectories] — against [N] human transcripts of the same protocol (Table SX).]"

The interactive Methods text MUST name, explicitly: **paradigm (interactive); topology; agent roster + persona grounding; max_turns + termination rule; n_conversations; provider + exact model id; temperature + seed; validation status (UNVALIDATED-EXPLORATORY unless a human-transcript benchmark cleared).** Do NOT report turns-per-agent or message-length statistics as if they were validated population quantities — they describe the synthetic conversation, not a human one, unless benchmarked.

---

## Mandatory Limitations subsection content

Place this in **Discussion -> Limitations only**. Disclose, at minimum:

> "Several limitations follow from the use of language-model-simulated respondents. First, **homogenization bias**: the model concentrates responses near the scale midpoint, understating within-group variance (synthetic-to-real SD ratio = [____]); we therefore do not interpret synthetic variance estimates as population variance. Second, **uneven demographic steerability**: fidelity was higher for [groups] than [groups] (Table SX), so subgroup contrasts involving [low-fidelity groups] are reported with caution. Third, **training recency**: the model reflects data through its training cutoff and cannot capture [recent events / social change since then]. Fourth, **intersectionality gaps**: thin identity combinations [name them] are poorly represented even where each marginal is well represented. Fifth, **rare populations**: we make no claims about [marginalized/small groups] from synthetic data. For these reasons we treat all synthetic results as [pre-testing / power-analysis / theory-development] evidence and confirm substantive findings against [human data source]. Where validation failed ([name the variables/subgroups that did not clear the fidelity thresholds]), we report the mismatch rather than excluding the item."

Do NOT soften or omit failed-validation items -- naming them is the honesty requirement.

**Interactive paradigm (MODE 10) additional mandatory limitation.** When the run is a multi-agent *conversation*, the five limitations above still apply, **plus** an interaction-specific caveat that must be stated explicitly:

> "Sixth, **synthetic-conversation artifacts**: LLM agents converge toward agreeable, fluent consensus and systematically under-produce the conflict, interruption, overlapping talk, repair, and silence that characterize real human deliberation; turn-taking is also more orderly than human interaction. We therefore treat the simulated transcripts as exploratory — useful for pre-testing the protocol and generating hypotheses — and make no claim that the interaction dynamics, consensus rate, or stance trajectories match human groups. Absent a held-out human-transcript benchmark on the same scenario, this run is reported as UNVALIDATED-EXPLORATORY."

Do NOT report a synthetic consensus rate, agreement level, or "the group decided X" as a finding without this caveat.

---

## Reproducibility archive checklist

- [ ] Run manifest (provider, exact model id, temperature, seed, n_reps, scale_strategy, cost cap) committed.
- [ ] `personas.jsonl` + persona spec (margins, source) committed.
- [ ] `items.json` and all prompts (system + user) archived verbatim.
- [ ] `responses.jsonl` + a sample of raw model outputs saved.
- [ ] `fidelity.json` + verification-subagent verdict committed.
- [ ] Cost ledger saved; run stayed under `cost_cap_usd`.
- [ ] ABM: ODD protocol + sensitivity table + topology spec in the appendix.
- [ ] Interactive (MODE 10): manifest (topology, agents + persona_refs, max_turns, termination), `graph.sqlite` checkpoint store, and flattened `transcripts.jsonl` committed; validation status (UNVALIDATED-EXPLORATORY or descriptive-benchmark comparison) recorded.

---

## Method citations (preserve; do not invent)

- Silicon sampling: Argyle et al. (2023), *Political Analysis*.
- Distributional-mismatch caution: Bisbee et al. (2023), *Political Analysis*.
- LLMs as simulated economic agents: Horton (2023), *homo silicus*.
- Generative agents: Park et al. (2023).

Citations are delegated to `/scholar-citation`; never hand-author `.bib`. Flag unverified claims `[CITATION NEEDED]`.
