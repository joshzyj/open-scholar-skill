# Generative & Mechanistic ABM (MODE 4: generative-abm)

This file is loaded by **MODE 4 (generative-abm)**. It covers a spectrum:

```
mechanistic ABM  ←─────────────────────────────────────→  LLM-powered generative ABM
(hard-coded rules:                                          (LLM as the cognitive engine:
 Schelling, Deffuant,                                        agents reason in natural language,
 SIR, Axelrod culture)                                       opinion dynamics, deliberation)
```

Pick by how complex agent cognition is. If a decision rule is a clean threshold (Schelling: move if < X% similar), use a **mechanistic** agent — it is cheaper, faster, fully reproducible, and easier to sweep. If the decision is too context-dependent to encode as a threshold (job-seeking, migration, deliberation, persuasion), use an **LLM-powered** agent. Hybrid models mix both.

Either way: an ABM is appropriate when emergence, heterogeneity, feedback/path-dependence, or empirically-infeasible counterfactuals are the question (see `paradigms.md`). An ABM is NOT a substitute for causal inference from observational data. **Every ABM paper must ship an ODD protocol** (required for NCS / Science Advances) and a parameter sweep.

---

## ODD protocol template (REQUIRED)

```
## ODD Protocol for [Model Name]

### 1. Purpose
[What social process does this model represent? What question does it address?]

### 2. Entities, State Variables, and Scales
Agents: [type; state variables: list]
Environment: [spatial structure or network; size; boundary conditions]
Time: [step = X; total T steps; corresponds to Y real-world time units]

### 3. Process Overview and Scheduling
Each time step:
  1. [Agent process 1] — executed in [random / fixed] order
  2. [Agent process 2]
  3. [Data collection]

### 4. Design Concepts
Emergence: [what macro-level outcomes emerge from micro rules]
Adaptation: [do agents update rules based on outcomes? how?]
Stochasticity: [where is randomness introduced?]
Observation: [what is recorded each step?]

### 5. Initialization
[Starting conditions: N agents, initial distribution of attributes, initial network structure]
[Random seed: 42]

### 6. Input Data (if any)
[Empirical data used to calibrate parameters or initialize]

### 7. Submodels
[For each process: precise mathematical or algorithmic specification]
```

---

## Mechanistic ABM in Mesa 3.x (Python)

**Important**: Mesa 3.x (2024+) replaced the scheduler-based API with `AgentSet`, `PropertyLayer`, and `model.agents`. If you encounter legacy Mesa 2.x code (`RandomActivation`, `self.schedule`, `self.next_id()`), migrate it.

| Mesa 2.x (deprecated) | Mesa 3.x (current) |
|------------------------|---------------------|
| `from mesa.time import RandomActivation` | No scheduler needed; use `model.agents` |
| `self.schedule = RandomActivation(self)` | Agents auto-registered via `Agent.__init__` |
| `self.schedule.add(agent)` | Automatic on `Agent(model)` |
| `self.schedule.step()` | `self.agents.shuffle_do("step")` |
| `self.schedule.agents` | `self.agents` (returns `AgentSet`) |
| `self.schedule.get_agent_count()` | `len(self.agents)` |
| `self.next_id()` | Auto-assigned `agent.unique_id` |
| `super().__init__(uid, model)` | `super().__init__(model)` |
| N/A | `PropertyLayer` for grid-level continuous variables |

```python
# pip install mesa>=3.0
from mesa import Agent, Model              # core ABM primitives
from mesa.space import MultiGrid           # 2-D grid that allows multiple agents per cell
from mesa.datacollection import DataCollector  # records model/agent state each step

class SchellingAgent(Agent):
    def __init__(self, model, agent_type):
        super().__init__(model)            # Mesa 3.x: no uid arg; unique_id is auto-assigned
        self.type  = agent_type            # group label (0 or 1) driving the similarity rule
        self.happy = False                 # satisfaction state, recomputed each step

    def step(self):
        # Read the Moore neighborhood and compute the share of same-type neighbors.
        neighbors = self.model.grid.get_neighbors(self.pos, moore=True, radius=1)
        similar   = sum(1 for n in neighbors if n.type == self.type)
        # Agent is happy iff similar-share meets the tolerance threshold (the micro rule).
        self.happy = similar / max(len(neighbors), 1) >= self.model.threshold
        if not self.happy:                 # unhappy agents relocate — the source of macro segregation
            self.model.grid.move_to_empty(self)

class SchellingModel(Model):
    def __init__(self, width=20, height=20, density=0.8,
                 frac_A=0.5, threshold=0.3, seed=42):
        super().__init__(seed=seed)        # Mesa 3.x: pass seed to Model.__init__ for reproducibility
        self.threshold = threshold         # the tolerance parameter we will sweep later
        self.grid      = MultiGrid(width, height, torus=True)  # torus = no edge effects

        # Mesa 3.x: agents auto-register on creation; seed the grid stochastically by density.
        for _, (x, y) in self.grid.coord_iter():
            if self.random.random() < density:                 # occupy this cell with prob = density
                a_type = 0 if self.random.random() < frac_A else 1  # assign group by frac_A
                agent  = SchellingAgent(self, a_type)
                self.grid.place_agent(agent, (x, y))

        # Macro reporter: fraction of happy agents = the emergent outcome we track over time.
        self.datacollector = DataCollector(
            model_reporters={"Pct_Happy": lambda m: m.agents.agg("happy", sum) / len(m.agents)}
        )

    def step(self):
        self.datacollector.collect(self)   # record macro state BEFORE agents act this step
        self.agents.shuffle_do("step")     # Mesa 3.x: random-order activation (replaces schedule.step)

# Run one simulation for 100 steps and save the macro trajectory.
model = SchellingModel(threshold=0.3)
for _ in range(100):
    model.step()
results = model.datacollector.get_model_vars_dataframe()        # per-step macro reporters
results.to_csv("output/simulate/runs/schelling/abm-run-results.csv")  # downstream plotting in R
```

**Other classic social-science mechanistic agents** (drop-in `step` rules):

```python
# Opinion dynamics — bounded-confidence (Deffuant): converge toward a neighbor only if close enough.
class OpinionAgent(Agent):
    def __init__(self, model):
        super().__init__(model)
        self.opinion = self.random.uniform(0, 1)               # continuous opinion in [0,1]
    def step(self):
        neighbor = self.random.choice(list(self.model.agents)) # random dyadic interaction
        if abs(self.opinion - neighbor.opinion) < self.model.confidence_bound:  # bounded confidence
            self.opinion += self.model.mu * (neighbor.opinion - self.opinion)   # partial convergence

# Epidemic spread (SIR): infected agents infect susceptible neighbors and recover stochastically.
class SIRAgent(Agent):
    def __init__(self, model, state="S"):
        super().__init__(model)
        self.state = state                                     # S (susceptible), I, or R (recovered)
    def step(self):
        if self.state == "I":
            for n in self.model.grid.get_neighbors(self.pos, radius=1):
                if n.state == "S" and self.random.random() < self.model.beta:   # transmission prob beta
                    n.state = "I"
            if self.random.random() < self.model.gamma:        # recovery prob gamma per step
                self.state = "R"

# Cultural transmission (Axelrod): interact with prob ∝ similarity; copy one differing feature.
class CulturalAgent(Agent):
    def __init__(self, model, n_features=5, n_traits=10):
        super().__init__(model)
        self.culture = [self.random.randint(0, n_traits-1) for _ in range(n_features)]  # feature vector
    def step(self):
        neighbor = self.random.choice(self.model.grid.get_neighbors(self.pos))
        sim = sum(a == b for a, b in zip(self.culture, neighbor.culture)) / len(self.culture)
        if self.random.random() < sim:                         # homophily: similar agents interact more
            diffs = [i for i, (a, b) in enumerate(zip(self.culture, neighbor.culture)) if a != b]
            if diffs:
                idx = self.random.choice(diffs)                # copy one trait where they differ
                self.culture[idx] = neighbor.culture[idx]
```

`PropertyLayer` adds grid-level continuous fields (pollution, rent, resources): `model.grid.add_property_layer(PropertyLayer("pollution", w, h, default_value=0.0))`; agents read `self.model.grid.properties["pollution"].data[self.pos]`.

### NetLogo via nlrx (R interface)

When NetLogo's spatial primitives, link topologies, or GIS extension are preferable, drive NetLogo from R with `nlrx` and a Latin-hypercube sweep:

```r
library(nlrx)        # R wrapper that scripts NetLogo headless runs
library(tidyverse)   # collect/save results
NETLOGO_PATH <- "/Applications/NetLogo 6.4.0"                 # adjust to your install
nl <- nl(nlversion = "6.4.0", nlpath = NETLOGO_PATH,          # bind the NetLogo binary + model
         modelpath = file.path(getwd(), "models/schelling.nlogo"), jvmmem = 1024)
nl@experiment <- experiment(                                  # define metrics + parameter ranges
  expname = "schelling-sweep", outpath = file.path(getwd(), "output/simulate/runs/netlogo/"),
  repetition = 5, tickmetrics = "true", idsetup = "setup", idgo = "go", runtime = 200,
  metrics = c("percent-similar", "percent-unhappy"),
  variables = list("%-similar-wanted" = list(min=10, max=60, step=10, qfun="qunif")),
  constants = list("number-of-ethnicities" = 2))
nl@simdesign <- simdesign_lhs(nl=nl, samples=100, nseeds=3, precision=3)  # space-filling LHS design
library(future); plan(multisession, workers=4)               # parallelize across cores
results <- run_nl_all(nl=nl)                                  # execute the full sweep
write_csv(results, "output/simulate/runs/netlogo/netlogo-sweep.csv")
```

> Reporting: "We implement the model in NetLogo 6.4 (Wilensky 1999) and conduct a Latin hypercube sweep (N = 100 samples × 3 seeds) driven from R via `nlrx` (Salecker et al. 2019). Findings are robust across the explored parameter space."

### Parameter sweep and sensitivity (SALib Sobol — required for NCS/Science Advances)

Report how key outcomes respond across the parameter space — not just at one point.

```python
from SALib.sample import saltelli      # quasi-random design for variance-based sensitivity
from SALib.analyze import sobol        # Sobol first-order + total-order indices
import numpy as np, pandas as pd

problem = {"num_vars": 3,                                     # the parameters we vary
           "names": ["density", "frac_A", "threshold"],
           "bounds": [[0.5, 0.95], [0.3, 0.7], [0.1, 0.7]]}   # plausible ranges per parameter
N = 256                                                       # base size; total runs = N*(2*3+2) = 2048
param_values = saltelli.sample(problem, N, calc_second_order=True)  # Saltelli sequence (not ad-hoc grid)

def run_model(p, steps=100):                                  # map a parameter vector to the macro outcome
    m = SchellingModel(density=p[0], frac_A=p[1], threshold=p[2], seed=42)
    for _ in range(steps): m.step()
    return m.datacollector.get_model_vars_dataframe()["Pct_Happy"].iloc[-1]  # final happiness

Y = np.array([run_model(p) for p in param_values])           # outcome at every sampled point
Si = sobol.analyze(problem, Y, calc_second_order=True)       # S1 = direct effect; ST = incl. interactions
pd.DataFrame({"param": problem["names"], "S1": Si["S1"], "ST": Si["ST"]}).to_csv(
    "output/simulate/runs/schelling/abm-sensitivity.csv", index=False)
```

---

## LLM-powered generative ABM

Replace hard-coded decision rules with an LLM as the agent's cognitive engine when decisions are too complex or context-dependent to encode as thresholds, or when you want agents to reason in natural language. Use a small/cheap model (e.g., Claude Haiku) for large simulations; reserve larger models for complex reasoning.

The defining requirement of generative ABM is **statefulness across turns**. Unlike silicon-sampling (independent one-shot personas), a generative agent must remember its prior state and what it observed. Because thousands of live concurrent threads are infeasible (Task tool ~20 practical; Agent SDK multiagent ceiling 25), the engine keeps agent state in an **external checkpoint store** between turns and re-submits each turn as a fresh batched/async call seeded with the agent's persisted state. See `scale-engine.md` and `dynamic-orchestration.md` for how this scales to thousands of stateful agents without thousands of live threads.

**Mid-run steering.** To introduce a shock or treatment at step *t* (e.g., a misinformation injection, a policy announcement), insert a **mid-run system message** into the affected agents' context at that turn — the engine supports this via context editing between turns (see `dynamic-orchestration.md`). This is how a simulated experiment is embedded inside a generative ABM.

### Cost check first (always)

```python
N_AGENTS, STEPS = 200, 100                     # simulation size drives the call budget
CALLS_PER_STEP = N_AGENTS                       # one LLM call per agent per step
TOK_IN, TOK_OUT = 300, 50                        # context tokens in, decision tokens out, per call
PRICE_IN, PRICE_OUT = 0.25, 1.25                 # $/1M tokens (Haiku-class; pin to current pricing)
cost = (N_AGENTS*STEPS*TOK_IN/1e6)*PRICE_IN + (N_AGENTS*STEPS*TOK_OUT/1e6)*PRICE_OUT
print(f"Estimated simulation cost: ${cost:.2f}")  # if > cost_cap_usd, cut N/STEPS or pre-filter heuristically
```

### Stateful LLM agent over a network (opinion dynamics)

This is the canonical generative ABM: opinions form, diffuse, and polarize across a social network of LLM agents. Each agent is a persona from MODE 2; at each step it updates after observing its neighbors' current opinions. The pattern below shows the logic; at scale the per-turn calls are routed through the engine (batched), with `opinion`/`opinion_history` persisted in the checkpoint store between steps.

```python
import networkx as nx        # network topology
import pandas as pd

def update_opinion_after_exposure(persona_system, my_opinion, neighbor_views, topic, client, model):
    # Build the user turn: the agent's current state + what it just observed from neighbors.
    n_summary = "; ".join(f"Person (party={p}, opinion={o}/10)" for o, p in neighbor_views)
    user = (f"You currently rate your support for '{topic}' as {my_opinion}/10.\n"
            f"You just heard these views from people around you: {n_summary}.\n\n"
            f"After hearing these perspectives, what is your new rating (1-10)? Reply ONLY the number.")
    msg = client.messages.create(model=model, max_tokens=5, temperature=0.2,  # low temp: update, not noise
                                 system=persona_system, messages=[{"role": "user", "content": user}])
    try:    return int(msg.content[0].text.strip()[0])   # parse the new opinion
    except: return my_opinion                            # on parse failure, keep prior opinion (no drift)

def run_opinion_dynamics(agents, G, topic, n_steps, client, model):
    # agents: list of dicts {id, persona_system, opinion, opinion_history, party}; G: nx.Graph
    records = [{"step": 0, "agent_id": a["id"], "opinion": a["opinion"], "party": a["party"]}
               for a in agents]                          # log the initial state at step 0
    for step in range(1, n_steps + 1):
        new = {}                                         # compute all updates from the SAME prior state
        for node in G.nodes():                           # synchronous update: read t, write t+1
            nbrs = list(G.neighbors(node))
            if not nbrs:
                new[node] = agents[node]["opinion"]; continue   # isolates do not move
            views = [(agents[n]["opinion"], agents[n]["party"]) for n in nbrs]  # neighbors' current views
            new[node] = update_opinion_after_exposure(
                agents[node]["persona_system"], agents[node]["opinion"], views, topic, client, model)
        for node, op in new.items():                     # commit the new opinions after the full pass
            agents[node]["opinion"] = op
            agents[node]["opinion_history"].append(op)    # the per-agent trajectory = the state we persist
            records.append({"step": step, "agent_id": node, "opinion": op, "party": agents[node]["party"]})
    df = pd.DataFrame(records)
    df.to_csv("output/simulate/runs/opinion/opinion-dynamics-trajectory.csv", index=False)
    return df

# Build a small-world social network (Watts-Strogatz): high clustering + short paths, like real ties.
N, K, P = 50, 4, 0.1
G = nx.watts_strogatz_graph(N, K, P, seed=42)            # seed fixes the topology for reproducibility
```

### Required safeguards (LLM agents)

- Pin the exact model id + date; set a low temperature (and seed where supported) for reproducibility.
- Archive all prompts and a sample of raw LLM responses as supplementary material.
- Run a **baseline mechanistic model** (rule-based agents) and compare aggregate patterns — does the LLM cognition change the macro story, or just dress it up?
- Cache the shared system scaffold so repeated personas do not re-pay input tokens (`scale-engine.md`).

### Opinion-dynamics reporting template

> "We simulate opinion dynamics among N = [X] agents arranged on a Watts-Strogatz small-world network (k = [K], rewiring probability p = [P]; seed = 42). Agents are assigned demographic personas drawn proportionally from [source; e.g., ACS marginal distributions raked to a joint]. At each of [T] time steps, agents update their position on [topic] after observing the current opinions of their [K] network neighbors, using [exact model id] as the cognitive engine (temperature = [0.2]; synchronous update). We track the Gini coefficient of opinion heterogeneity and the partisan opinion gap (Strong Democrat − Strong Republican) across steps. Sensitivity to topology (Erdős-Rényi p = [0.08]; Barabási-Albert m = [2]) is reported in Figure A[X]; qualitative patterns [hold / vary by topology]. All synthetic opinion trajectories are validated against [human benchmark] per the fidelity protocol (Table SX)."

---

## ABM verification checklist (dispatch a verification subagent)

```
ABM VERIFICATION REPORT
=======================
ODD PROTOCOL
[ ] All 7 ODD sections present (Purpose, Entities, Process, Design Concepts, Init, Input, Submodels)
[ ] Precise algorithmic specification of each submodel
IMPLEMENTATION
[ ] seed=42 set in model initialization
[ ] DataCollector (or checkpoint store) records model state each step
[ ] Results saved under output/simulate/runs/<run_id>/
PARAMETER SWEEP
[ ] SALib Saltelli sample used (not ad-hoc grid); Sobol S1 and ST reported and saved
NETLOGO (if used)
[ ] NetLogo version documented; nlrx spec reproduced; LHS/Saltelli design (not ad-hoc grid)
LLM AGENTS (if used)
[ ] Cost estimate run and reported; low temperature set; exact model id + date recorded
[ ] Prompts archived verbatim; sample of raw responses saved
[ ] Baseline rule-based model run for comparison
VALIDATION
[ ] Validated against >=2 empirical patterns (pattern-oriented modeling)
[ ] Behavior across parameter space described; robust to +/-20% in key parameters
RESULT: [PASS / NEEDS REVISION]   Issues: [list]
```

---

## Figures

When plotting trajectories or sweep results in R, always `source("viz_setting.R")` for the custom publication theme — never default ggplot2 themes, never define `theme_Publication()` inline.

**Provisioning note (do not ship a copy here).** `scholar-simulate` is not a figure-authoring skill and deliberately does NOT ship its own `viz_setting.R`. The canonical file is provisioned into the project by `scholar-analyze` / `scholar-auto-research` (auto-research enforces a `sha256` contract on it); a 4th divergent copy under this skill would drift against that contract. The `source("viz_setting.R")` call below therefore reads the **project-provided** file at the project root — when a simulation produces figures inside the full-paper pipeline it inherits the same `viz_setting.R` the analysis branch already materialized. If you are running `scholar-simulate` standalone with no analysis branch, run `/scholar-analyze` (or copy its `references/viz_setting.R`) into the project root first so the `source()` resolves.

```r
library(tidyverse)
source("viz_setting.R")      # load the project's custom ggplot theme (house requirement)
traj <- read_csv("output/simulate/runs/opinion/opinion-dynamics-trajectory.csv")
p <- traj |>
  group_by(step, party) |>
  summarise(mean_op = mean(opinion), .groups = "drop") |>    # mean opinion per party over time
  ggplot(aes(step, mean_op, color = party)) +                # trajectory of polarization
  geom_line(linewidth = 1) +
  labs(x = "Step", y = "Mean opinion (1-10)", color = "Party") +
  theme_Publication()                                         # from viz_setting.R — never inline
ggsave("output/simulate/runs/opinion/opinion-trajectory.pdf", p, width = 7, height = 4.5)
```

---

## Method citations (preserve; do not invent)

- Generative agents: Park et al. (2023).
- LLMs as simulated economic agents: Horton (2023), *homo silicus*.
- Silicon sampling (persona basis): Argyle et al. (2023), *Political Analysis*.
- Distributional-mismatch caution: Bisbee et al. (2023), *Political Analysis*.

Citations are delegated to `/scholar-citation`; never hand-author `.bib`. Flag unverified claims `[CITATION NEEDED]`.
