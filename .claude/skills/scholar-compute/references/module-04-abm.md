## MODULE 4: Agent-Based Modeling (ABM)

### Step 1 — Feasibility Check

ABM is appropriate when:
- **Emergence** is the key question: macro patterns arising from micro interactions
- **Heterogeneity** matters and aggregates non-linearly
- **Feedbacks / path dependence** are central
- **Counterfactuals** not feasible empirically

ABM is NOT appropriate as a substitute for causal inference from observational data.

### Step 2 — ODD Protocol (Required for NCS / Science Advances)

All ABM papers must include an ODD (Overview, Design concepts, Details) description:

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

### Step 3 — Mesa 3.x Implementation (Python)

**Important**: Mesa 3.x (2024+) replaced the scheduler-based API with `AgentSet`, `PropertyLayer`, and `model.agents`. The code below uses the **Mesa 3.x API**. If you encounter legacy Mesa 2.x code (using `RandomActivation`, `self.schedule`, `self.next_id()`), migrate it to the patterns shown here.

**Key Mesa 3.x changes** (vs. 2.x):
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
from mesa import Agent, Model
from mesa.space import MultiGrid
from mesa.datacollection import DataCollector

class SchellingAgent(Agent):
    def __init__(self, model, agent_type):
        super().__init__(model)          # Mesa 3.x: no uid arg; auto-assigned unique_id
        self.type  = agent_type
        self.happy = False

    def step(self):
        neighbors = self.model.grid.get_neighbors(self.pos, moore=True, radius=1)
        similar   = sum(1 for n in neighbors if n.type == self.type)
        self.happy = similar / max(len(neighbors), 1) >= self.model.threshold
        if not self.happy:
            self.model.grid.move_to_empty(self)

class SchellingModel(Model):
    def __init__(self, width=20, height=20, density=0.8,
                 frac_A=0.5, threshold=0.3, seed=42):
        super().__init__(seed=seed)      # Mesa 3.x: pass seed to Model.__init__
        self.threshold = threshold
        self.grid      = MultiGrid(width, height, torus=True)

        # Mesa 3.x: no scheduler — agents are auto-registered on creation
        for _, (x, y) in self.grid.coord_iter():
            if self.random.random() < density:
                a_type = 0 if self.random.random() < frac_A else 1
                agent  = SchellingAgent(self, a_type)
                self.grid.place_agent(agent, (x, y))

        self.datacollector = DataCollector(
            model_reporters={
                "Pct_Happy": lambda m: (
                    m.agents.agg("happy", sum) / len(m.agents)
                )
            }
        )

    def step(self):
        self.datacollector.collect(self)
        self.agents.shuffle_do("step")   # Mesa 3.x: replaces schedule.step()

# Run single simulation
model = SchellingModel(threshold=0.3)
for _ in range(100):
    model.step()

results = model.datacollector.get_model_vars_dataframe()
results.to_csv("${OUTPUT_ROOT}/tables/abm-run-results.csv")
```

**Mesa 3.x AgentSet operations** (replaces scheduler loops):

```python
# Filter agents by type
type_0 = model.agents.select(lambda a: a.type == 0)
print(f"N type-0 agents: {len(type_0)}")

# Aggregate attributes across agents
avg_happy = model.agents.agg("happy", func=lambda vals: sum(vals) / len(vals))

# Get attribute as array (useful for plotting)
happy_arr = model.agents.get("happy")

# Apply method to all agents in random order
model.agents.shuffle_do("step")

# Apply method to subset
type_0.do("step")
```

**Mesa 3.x PropertyLayer** (for grid-level continuous variables like pollution, rent, resources):

```python
from mesa.space import PropertyLayer

# Add a continuous property to the grid
pollution = PropertyLayer("pollution", width=20, height=20, default_value=0.0)
model.grid.add_property_layer(pollution)

# Set values
model.grid.properties["pollution"].set_cell((5, 5), 0.8)

# Agents can read local property
class PollutionAgent(Agent):
    def step(self):
        local_pollution = self.model.grid.properties["pollution"].data[self.pos]
        if local_pollution > 0.5:
            self.model.grid.move_to_empty(self)
```

### Step 3b — NetLogo via nlrx (R Interface)

For models where NetLogo's built-in spatial primitives, link topologies, or GIS extension are preferable, use the `nlrx` package to drive NetLogo from R:

```r
# install.packages(c("nlrx", "future"))
library(nlrx)
library(tidyverse)

# Path to NetLogo installation (adjust for your system)
NETLOGO_PATH <- "/Applications/NetLogo 6.4.0"
MODEL_PATH   <- file.path(getwd(), "models/schelling.nlogo")

# Create nlrx object
nl <- nl(
  nlversion   = "6.4.0",
  nlpath      = NETLOGO_PATH,
  modelpath   = MODEL_PATH,
  jvmmem      = 1024
)

# Experiment specification
nl@experiment <- experiment(
  expname     = "schelling-sweep",
  outpath     = file.path(getwd(), paste0(Sys.getenv("OUTPUT_ROOT", "output"), "/")),
  repetition  = 5,         # runs per parameter set
  tickmetrics = "true",
  idsetup     = "setup",
  idgo        = "go",
  runtime     = 200,
  evalticks   = seq(50, 200, 50),
  metrics     = c("percent-similar", "percent-unhappy"),
  variables   = list(
    "%-similar-wanted" = list(min=10, max=60, step=10, qfun="qunif"),
    "number"           = list(min=500, max=2000, step=500, qfun="qunif")
  ),
  constants   = list("number-of-ethnicities" = 2)
)

# Latin Hypercube Sampling design
nl@simdesign <- simdesign_lhs(nl=nl, samples=100, nseeds=3, precision=3)

# Run (parallel with future)
library(future); plan(multisession, workers=4)
results <- run_nl_all(nl=nl)

# Collect and save
results_df <- setsim(nl, "simoutput")
write_csv(results_df, "${OUTPUT_ROOT}/tables/netlogo-sweep.csv")
```

**Reporting template:**
> "We implement the model in NetLogo 6.4 (Wilensky 1999) and conduct a Latin hypercube parameter sweep (N = 100 samples × 3 seeds) driven from R via the `nlrx` package (Salecker et al. 2019). Results are robust across the explored parameter space; key findings are presented for [parameter range]."

### Additional ABM Models for Social Science

**Opinion dynamics (Bounded Confidence / Deffuant model)**:
```python
class OpinionAgent(mesa.Agent):
    def __init__(self, model):
        super().__init__(model)
        self.opinion = self.random.uniform(0, 1)

    def step(self):
        neighbor = self.random.choice(self.model.agents)
        if abs(self.opinion - neighbor.opinion) < self.model.confidence_bound:
            self.opinion += self.model.mu * (neighbor.opinion - self.opinion)
```

**Epidemic spreading (SIR)**:
```python
class SIRAgent(mesa.Agent):
    def __init__(self, model, state="S"):
        super().__init__(model)
        self.state = state  # S, I, R

    def step(self):
        if self.state == "I":
            neighbors = self.model.grid.get_neighbors(self.pos, radius=1)
            for n in neighbors:
                if n.state == "S" and self.random.random() < self.model.beta:
                    n.state = "I"
            if self.random.random() < self.model.gamma:
                self.state = "R"
```

**Norm evolution / cultural transmission**:
```python
class CulturalAgent(mesa.Agent):
    def __init__(self, model, n_features=5, n_traits=10):
        super().__init__(model)
        self.culture = [self.random.randint(0, n_traits-1) for _ in range(n_features)]

    def step(self):
        neighbor = self.random.choice(self.model.grid.get_neighbors(self.pos))
        similarity = sum(a == b for a, b in zip(self.culture, neighbor.culture)) / len(self.culture)
        if self.random.random() < similarity:
            idx = self.random.choice([i for i, (a, b) in enumerate(zip(self.culture, neighbor.culture)) if a != b])
            self.culture[idx] = neighbor.culture[idx]
```

---

### Step 3c — LLM-Powered Agents

Replace hard-coded decision rules with an LLM as an agent's cognitive engine. Use **Claude Haiku** (fastest, cheapest) for large simulations; switch to Sonnet for complex reasoning.

**When appropriate**: When agent decision rules are too complex or context-dependent to encode as simple thresholds; when you want agents to reason in natural language about their situation (e.g., job-seeking, housing choice, migration decision).

**Cost check first**:

```python
# Estimate LLM cost before running a large simulation
N_AGENTS = 200
STEPS    = 100
CALLS_PER_STEP = N_AGENTS      # each agent calls LLM once per step
TOKENS_PER_CALL_IN  = 300      # context (agent state + world state)
TOKENS_PER_CALL_OUT = 50       # decision output
PRICE_PER_1M_IN  = 0.25        # claude-haiku-4-5 (adjust to current pricing)
PRICE_PER_1M_OUT = 1.25

total_in  = N_AGENTS * STEPS * TOKENS_PER_CALL_IN  / 1e6
total_out = N_AGENTS * STEPS * TOKENS_PER_CALL_OUT / 1e6
cost = total_in * PRICE_PER_1M_IN + total_out * PRICE_PER_1M_OUT
print(f"Estimated simulation cost: ${cost:.2f}")
# If cost > $50, reduce N_AGENTS, STEPS, or add heuristic pre-filters
```

```python
import anthropic, json
from mesa import Agent, Model

client = anthropic.Anthropic()

DECISION_SYSTEM = """You are simulating a household making a residential location decision.
Based on the household's current state and neighborhood conditions, decide whether to STAY or MOVE.
Respond ONLY with: {"action": "STAY" or "MOVE", "reason": "one sentence"}"""

class LLMAgent(Agent):
    def __init__(self, model, income, race, threshold=0.3):
        super().__init__(model)          # Mesa 3.x: no uid arg
        self.income    = income
        self.race      = race
        self.threshold = threshold
        self.happy     = True

    def _get_decision(self, neighbor_summary: str) -> dict:
        """Use Claude Haiku as cognitive engine."""
        context = (
            f"Household: income={self.income}, race={self.race}.\n"
            f"Current neighborhood: {neighbor_summary}.\n"
            f"Similarity preference threshold: {self.threshold:.0%}."
        )
        msg = client.messages.create(
            model="claude-haiku-4-5-20251001",
            max_tokens=80,
            temperature=0,   # deterministic for reproducibility
            system=DECISION_SYSTEM,
            messages=[{"role": "user", "content": context}]
        )
        return json.loads(msg.content[0].text)

    def step(self):
        neighbors = self.model.grid.get_neighbors(self.pos, moore=True, radius=1)
        if not neighbors:
            return
        same_race   = sum(1 for n in neighbors if n.race == self.race)
        pct_similar = same_race / len(neighbors)
        summary     = (f"{len(neighbors)} neighbors; {pct_similar:.0%} same race; "
                       f"avg income={sum(n.income for n in neighbors)/len(neighbors):.0f}")
        decision    = self._get_decision(summary)
        self.happy  = decision["action"] == "STAY"
        if not self.happy:
            self.model.grid.move_to_empty(self)
```

**Required safeguards**:
- Cache LLM responses for identical inputs (`functools.lru_cache` or dict) to reduce cost and improve reproducibility
- Archive all prompts and a sample of LLM responses as supplementary material
- Run a baseline simulation with rule-based agents to compare aggregate patterns

### Step 4 — Parameter Sweep and Sensitivity Analysis (SALib)

**Required for NCS / Science Advances**: Report how key outcomes respond across the parameter space.

```python
from SALib.sample import saltelli
from SALib.analyze import sobol
import numpy as np, pandas as pd

# Define parameter space
problem = {
    "num_vars": 3,
    "names":    ["density", "frac_A", "threshold"],
    "bounds":   [[0.5, 0.95], [0.3, 0.7], [0.1, 0.7]]
}

# Generate Saltelli samples (N*(2D+2) model runs)
N           = 256   # base sample size; total runs = N*(2*3+2) = 2048
param_values= saltelli.sample(problem, N, calc_second_order=True)

# Run model for each parameter set
def run_model(params, steps=100):
    m = SchellingModel(density=params[0], frac_A=params[1],
                       threshold=params[2], seed=42)
    for _ in range(steps):
        m.step()
    return m.datacollector.get_model_vars_dataframe()["Pct_Happy"].iloc[-1]

Y = np.array([run_model(p) for p in param_values])

# Sobol sensitivity indices
Si = sobol.analyze(problem, Y, calc_second_order=True, print_to_console=True)
# Si["S1"]: first-order (direct effect of each parameter)
# Si["ST"]: total-order (includes interactions)

pd.DataFrame({"param": problem["names"],
              "S1": Si["S1"], "ST": Si["ST"]}).to_csv(
              "${OUTPUT_ROOT}/tables/abm-sensitivity.csv", index=False)
```

### Step 5 — ABM Verification (Subagent)

```
ABM VERIFICATION REPORT
========================

ODD PROTOCOL
[ ] All 7 ODD sections present (Purpose, Entities, Process, Design Concepts,
    Init, Input, Submodels)
[ ] Precise algorithmic specification of each submodel

IMPLEMENTATION
[ ] seed=42 set in model initialization
[ ] DataCollector used to record model state each step
[ ] Simulation results saved to output/[slug]/tables/

PARAMETER SWEEP
[ ] SALib Saltelli sample used (not ad hoc grid)
[ ] Sobol S1 and ST indices reported
[ ] Sensitivity table saved

NETLOGO (if used)
[ ] NetLogo version documented
[ ] nlrx experiment specification reproduced in supplementary
[ ] LHS or Saltelli design used (not ad hoc grid)

LLM AGENTS (if used)
[ ] Cost estimation run and reported
[ ] temperature=0 set for reproducibility
[ ] Prompts archived verbatim in supplementary
[ ] Baseline rule-based model run for comparison
[ ] LLM model name + version + date recorded

VALIDATION
[ ] Model validated against ≥2 empirical patterns (pattern-oriented modeling)
[ ] Behavior across parameter space described (not just one parameter set)
[ ] Results robust to ±20% variation in key parameters

REPORTING
[ ] ODD protocol in supplementary or appendix
[ ] All parameters and initial conditions tabulated
[ ] Random seed reported

RESULT: [PASS / NEEDS REVISION]
Issues: [list]
```

---

