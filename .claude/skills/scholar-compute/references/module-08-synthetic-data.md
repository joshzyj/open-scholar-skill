## MODULE 8: LLM Synthetic Data Generation

Use LLMs as simulated participants to generate synthetic behavioral, attitudinal, or organizational data for social science research. This module covers context/persona engineering, silicon sampling (survey simulation), vignette and conjoint simulation, organizational and group behavior simulation, and multi-agent opinion dynamics.

**Core logic**: An LLM given a rich sociodemographic and contextual persona can approximate the response distribution of that social group. This is *not* a substitute for human data — it is a tool for pre-testing, power analysis, theory development, and exploring counterfactual scenarios.

---

### Step 1 — Feasibility and Ethics Gate

Before running any simulation, assess whether synthetic data is appropriate:

| Use case | Appropriate | Caution |
|----------|------------|---------|
| Pre-testing survey instruments | ✓ Low cost, fast iteration | Validate with cognitive interviews before fielding |
| Power analysis / sample size estimation | ✓ | Treat as priors, not ground truth |
| Exploring counterfactual scenarios ("what if policy X?") | ✓ with limitations | LLMs reflect historical training data; future behavior may differ |
| Rare or hard-to-reach populations | Partial | LLMs may poorly represent truly marginalized groups |
| **Replacing human survey data in published findings** | **✗ Not appropriate** | Bisbee et al. (2023) show significant distributional mismatch |
| Generating labeled training data for classifiers | With validation | Must validate synthetic labels against human-coded gold standard |

**Validation is mandatory**: Any synthetic data used in a published paper must be compared against actual human data (ANES, GSS, CCES, or original survey) using distributional tests. Report alignment metrics (KS statistic, Jensen-Shannon divergence, mean differences).

**IRB**: Check with your IRB whether LLM simulation of specific real-world groups requires review, especially if used to make claims about marginalized populations.

---

### Step 2 — Persona / Context Engineering

The quality of synthetic data depends entirely on the richness and consistency of the persona prompt. Structure personas at three levels:

**Macro context** (societal): time period, country/region, political environment
**Meso context** (group/organization): industry, workplace, neighborhood, social network
**Micro context** (individual): demographics, life history, values, current situation

```python
import anthropic, json
from dataclasses import dataclass, asdict
from typing import Optional

client = anthropic.Anthropic()

@dataclass
class SocialPersona:
    """Structured persona for LLM social simulation."""
    # Demographics
    age:              int
    gender:           str
    race_ethnicity:   str
    education:        str          # "less than high school" / "high school" / "some college" /
                                   # "bachelor's" / "graduate degree"
    household_income: str          # "$0-$30K" / "$30-$60K" / "$60-$100K" / "$100K+"
    region:           str          # "Northeast US" / "South US" / "Midwest US" / "West US"
    # Social position
    political_affiliation: str     # "Strong Democrat" / "Lean Democrat" / "Independent" /
                                   # "Lean Republican" / "Strong Republican"
    religious_attendance:  str     # "never" / "seldom" / "monthly" / "weekly"
    employment_status:     str     # "employed full-time" / "part-time" / "unemployed" / "retired"
    occupation:            Optional[str] = None
    # Meso context (optional)
    organization_type:     Optional[str] = None   # "large corporation" / "non-profit" / "government" / "small business"
    neighborhood_type:     Optional[str] = None   # "urban" / "suburban" / "rural"
    # Macro context
    year:                  int = 2024

def build_persona_system_prompt(persona: SocialPersona) -> str:
    p = asdict(persona)
    return f"""You are roleplaying as a research participant in a social science study.
Your background:
- Age: {p['age']} | Gender: {p['gender']} | Race/ethnicity: {p['race_ethnicity']}
- Education: {p['education']} | Household income: {p['household_income']}
- Region: {p['region']} | Employment: {p['employment_status']}{f" ({p['occupation']})" if p['occupation'] else ""}
- Political affiliation: {p['political_affiliation']}
- Religious attendance: {p['religious_attendance']}
{f"- Organization type: {p['organization_type']}" if p['organization_type'] else ""}
{f"- Neighborhood: {p['neighborhood_type']}" if p['neighborhood_type'] else ""}
- Year: {p['year']}

Respond as this person would — based on their social position, lived experiences, values, and circumstances. Be internally consistent with this persona. Do not break character. Do not acknowledge that you are an AI. If a question wouldn't apply to this person's life, respond accordingly."""

# Example personas for a stratified simulation
personas = [
    SocialPersona(age=52, gender="male", race_ethnicity="White non-Hispanic",
                  education="high school", household_income="$30-$60K",
                  region="South US", political_affiliation="Strong Republican",
                  religious_attendance="weekly", employment_status="employed full-time",
                  occupation="truck driver", neighborhood_type="rural", year=2024),
    SocialPersona(age=34, gender="female", race_ethnicity="Black non-Hispanic",
                  education="bachelor's", household_income="$60-$100K",
                  region="Northeast US", political_affiliation="Strong Democrat",
                  religious_attendance="monthly", employment_status="employed full-time",
                  occupation="teacher", neighborhood_type="urban", year=2024),
    SocialPersona(age=28, gender="non-binary", race_ethnicity="Hispanic/Latino",
                  education="some college", household_income="$0-$30K",
                  region="West US", political_affiliation="Lean Democrat",
                  religious_attendance="seldom", employment_status="part-time",
                  neighborhood_type="suburban", year=2024),
]
```

---

### Step 3 — Survey and Vignette Simulation (Silicon Sampling)

**Silicon sampling** (Argyle et al. 2023, *Political Analysis*): use LLMs to approximate survey response distributions across demographic subgroups — enabling rapid pre-testing and subgroup comparisons without data collection costs.

```python
import pandas as pd
import time
from sklearn.metrics import cohen_kappa_score

# ── Survey item simulation ────────────────────────────────────────────
SURVEY_ITEMS = {
    "trust_govt": {
        "question": "How much of the time do you think you can trust the government in Washington to do what is right?",
        "scale": ["Never", "Only some of the time", "About half the time",
                  "Most of the time", "Always"],
        "scale_values": [1, 2, 3, 4, 5]
    },
    "immigration_level": {
        "question": "Do you think the number of immigrants from foreign countries who are permitted to come to the United States should be...",
        "scale": ["Increased a lot", "Increased a little", "Left the same",
                  "Decreased a little", "Decreased a lot"],
        "scale_values": [1, 2, 3, 4, 5]
    },
    "healthcare_govt_responsibility": {
        "question": "Do you think it is the responsibility of the federal government to make sure all Americans have health care coverage?",
        "scale": ["Definitely should be", "Probably should be",
                  "Probably should not be", "Definitely should not be"],
        "scale_values": [1, 2, 3, 4]
    }
}

def simulate_survey_item(persona: SocialPersona, item_key: str,
                          model="claude-sonnet-4-6", temperature=0.5) -> dict:
    """
    Simulate a single survey response for a given persona.
    temperature=0.5: some variation across respondents (not fully deterministic)
    """
    item      = SURVEY_ITEMS[item_key]
    scale_str = " | ".join([f"({v}) {l}" for v, l in
                             zip(item["scale_values"], item["scale"])])
    system = build_persona_system_prompt(persona)
    user   = (f"Survey question: {item['question']}\n\n"
              f"Response options: {scale_str}\n\n"
              f"Please choose your response. Reply ONLY with the number corresponding "
              f"to your answer (e.g., '2'), then a brief explanation on the same line "
              f"separated by a pipe: '2 | Because...'")
    msg = client.messages.create(
        model=model, max_tokens=80, temperature=temperature,
        system=system, messages=[{"role": "user", "content": user}]
    )
    raw = msg.content[0].text.strip()
    # Parse: "2 | explanation"
    parts = raw.split("|", 1)
    try:
        value = int(parts[0].strip())
        label = item["scale"][item["scale_values"].index(value)]
    except (ValueError, IndexError):
        value, label = None, raw
    return {"persona_id": id(persona), "item": item_key, "value": value,
            "label": label, "raw": raw, "model": model}

# ── Run stratified simulation ─────────────────────────────────────────
# Each persona responds N_REPS times to capture within-persona stochasticity
N_REPS = 5

rows = []
for persona in personas:
    for item_key in SURVEY_ITEMS:
        for rep in range(N_REPS):
            row = simulate_survey_item(persona, item_key)
            row.update({
                "rep":        rep,
                "age":        persona.age,
                "gender":     persona.gender,
                "race":       persona.race_ethnicity,
                "education":  persona.education,
                "party":      persona.political_affiliation,
                "region":     persona.region
            })
            rows.append(row)
            time.sleep(0.3)

synth_df = pd.DataFrame(rows)
synth_df.to_csv("${OUTPUT_ROOT}/tables/synthetic-survey-responses.csv", index=False)

# Aggregate: mean response per persona × item
summary = synth_df.groupby(["race", "party", "item"])["value"].agg(
    ["mean", "std", "count"]).reset_index()
print(summary)
```

**Factorial vignette simulation**: manipulate one experimental condition while holding persona constant, or hold condition constant while varying persona:

```python
VIGNETTE_TEMPLATE = """Imagine the following situation:
A {applicant_race} {applicant_gender} named {applicant_name} applies for a {position} position
at a {company_type}. They have {qualifications}.

How likely are you to recommend this applicant for an interview?
Scale: 1 (Very unlikely) to 7 (Very likely).
Reply with ONLY the number."""

VIGNETTE_CONDITIONS = [
    {"applicant_race": "White", "applicant_gender": "man", "applicant_name": "Greg",
     "position": "manager", "company_type": "Fortune 500 company",
     "qualifications": "a bachelor's degree and 5 years of experience"},
    {"applicant_race": "Black", "applicant_gender": "man", "applicant_name": "Jamal",
     "position": "manager", "company_type": "Fortune 500 company",
     "qualifications": "a bachelor's degree and 5 years of experience"},
    {"applicant_race": "White", "applicant_gender": "woman", "applicant_name": "Emily",
     "position": "manager", "company_type": "Fortune 500 company",
     "qualifications": "a bachelor's degree and 5 years of experience"},
    {"applicant_race": "Black", "applicant_gender": "woman", "applicant_name": "Lakisha",
     "position": "manager", "company_type": "Fortune 500 company",
     "qualifications": "a bachelor's degree and 5 years of experience"},
]

def simulate_vignette(persona: SocialPersona, condition: dict,
                      model="claude-sonnet-4-6") -> dict:
    system = build_persona_system_prompt(persona)
    vignette_text = VIGNETTE_TEMPLATE.format(**condition)
    msg = client.messages.create(
        model=model, max_tokens=10, temperature=0.3, system=system,
        messages=[{"role": "user", "content": vignette_text}]
    )
    try:
        rating = int(msg.content[0].text.strip()[0])
    except (ValueError, IndexError):
        rating = None
    return {"rating": rating, **condition,
            "persona_party": persona.political_affiliation,
            "persona_race": persona.race_ethnicity}
```

**Conjoint experiment simulation**:

```python
import itertools, random

CONJOINT_ATTRIBUTES = {
    "candidate_race":      ["White", "Black", "Hispanic", "Asian American"],
    "candidate_gender":    ["man", "woman"],
    "candidate_party":     ["Democrat", "Republican", "Independent"],
    "candidate_age":       ["35", "52", "68"],
    "candidate_education": ["state university", "Ivy League university", "community college"],
}

def build_conjoint_profile(attributes: dict) -> str:
    return (f"Candidate A: A {attributes['candidate_age']}-year-old "
            f"{attributes['candidate_race']} {attributes['candidate_gender']}, "
            f"{attributes['candidate_party']}, graduated from {attributes['candidate_education']}.")

def simulate_conjoint_choice(persona: SocialPersona, profile_a: dict,
                              profile_b: dict, model="claude-sonnet-4-6") -> dict:
    system = build_persona_system_prompt(persona)
    user   = (f"{build_conjoint_profile(profile_a)}\n\n"
              f"{build_conjoint_profile(profile_b).replace('Candidate A', 'Candidate B')}\n\n"
              f"Which candidate would you vote for? Reply ONLY with 'A' or 'B'.")
    msg = client.messages.create(
        model=model, max_tokens=5, temperature=0.3, system=system,
        messages=[{"role": "user", "content": user}]
    )
    choice = msg.content[0].text.strip()[0].upper()
    return {"choice": choice,
            **{f"A_{k}": v for k, v in profile_a.items()},
            **{f"B_{k}": v for k, v in profile_b.items()},
            "persona_party": persona.political_affiliation,
            "persona_race": persona.race_ethnicity}
```

---

### Step 4 — Organizational and Group Behavior Simulation

Simulate how organizational roles and institutional contexts shape decisions: hiring committees, peer review panels, performance evaluations, or group negotiations.

```python
# ── Hiring committee simulation ───────────────────────────────────────
HIRING_SYSTEM = """You are roleplaying as a hiring manager at a {org_type} organization.
You are evaluating job applications for a {position} role.
Your organization's stated values: {org_values}.
Your professional background: {years_exp} years in {industry}.
Make decisions as this person would, shaped by their organizational context and professional norms."""

def simulate_hiring_decision(org_context: dict, candidate_profile: str,
                              model="claude-sonnet-4-6") -> dict:
    system = HIRING_SYSTEM.format(**org_context)
    user   = (f"Candidate profile:\n{candidate_profile}\n\n"
              f"Would you advance this candidate to the next round? "
              f"Reply with JSON: {{\"advance\": true/false, "
              f"\"rating\": 1-10, \"rationale\": \"one sentence\"}}")
    msg = client.messages.create(
        model=model, max_tokens=120, temperature=0.4, system=system,
        messages=[{"role": "user", "content": user}]
    )
    result = json.loads(msg.content[0].text)
    result.update(org_context)
    return result

# Experimental conditions: vary org_type while keeping candidate constant
ORG_CONDITIONS = [
    {"org_type": "large technology corporation", "position": "software engineer",
     "org_values": "innovation, efficiency, technical excellence",
     "years_exp": 12, "industry": "tech"},
    {"org_type": "non-profit social services organization", "position": "program coordinator",
     "org_values": "equity, community impact, lived experience",
     "years_exp": 8, "industry": "non-profit"},
    {"org_type": "federal government agency", "position": "policy analyst",
     "org_values": "public service, neutrality, thoroughness",
     "years_exp": 15, "industry": "government"},
]

# ── Group deliberation simulation ────────────────────────────────────
def simulate_group_deliberation(group_personas: list[SocialPersona],
                                 topic: str, n_rounds: int = 3,
                                 model="claude-sonnet-4-6") -> pd.DataFrame:
    """
    Simulate sequential group deliberation on a topic.
    Each agent sees the previous agents' statements before responding.
    """
    history    = []
    all_rounds = []

    for round_num in range(n_rounds):
        for i, persona in enumerate(group_personas):
            system = build_persona_system_prompt(persona)
            # Build context from prior statements
            prior = "\n".join([f"Person {s['agent_id']}: {s['statement']}"
                                for s in history[-len(group_personas):]])
            user  = (f"Your group is discussing: {topic}\n\n"
                     f"{'Previous statements:\n' + prior if prior else 'You speak first.'}\n\n"
                     f"Share your view in 2–3 sentences. Be authentic to your background.")
            msg = client.messages.create(
                model=model, max_tokens=150, temperature=0.6, system=system,
                messages=[{"role": "user", "content": user}]
            )
            entry = {"round": round_num, "agent_id": i,
                     "race": persona.race_ethnicity, "party": persona.political_affiliation,
                     "statement": msg.content[0].text.strip()}
            history.append(entry)
            all_rounds.append(entry)

    df = pd.DataFrame(all_rounds)
    df.to_csv("${OUTPUT_ROOT}/tables/group-deliberation-transcript.csv", index=False)
    return df
```

---

### Step 5 — Multi-Agent Opinion Dynamics

Simulate how opinions form, diffuse, and polarize across a social network of LLM agents. Extends MODULE 4 (ABM) with LLM-powered cognition at each step.

```python
import networkx as nx
import numpy as np

def initialize_opinion_agents(n_agents: int, topic: str,
                               model="claude-haiku-4-5-20251001") -> list[dict]:
    """Initialize agents with diverse starting opinions on a topic."""
    # Sample demographic diversity proportional to US Census
    personas_sample = random.choices(personas, k=n_agents)
    agents = []
    for i, persona in enumerate(personas_sample):
        system = build_persona_system_prompt(persona)
        user   = (f"On a scale of 1–10, where 1 = strongly oppose and "
                  f"10 = strongly support, what is your initial view on: {topic}?\n"
                  f"Reply ONLY with the number.")
        msg = client.messages.create(
            model=model, max_tokens=5, temperature=0.4, system=system,
            messages=[{"role": "user", "content": user}]
        )
        try:    opinion = int(msg.content[0].text.strip()[0])
        except: opinion = 5
        agents.append({"id": i, "persona": persona, "opinion": opinion,
                        "opinion_history": [opinion], "party": persona.political_affiliation})
    return agents

def update_opinion_after_exposure(agent: dict, neighbor_opinions: list[int],
                                   neighbor_parties: list[str], topic: str,
                                   model="claude-haiku-4-5-20251001") -> int:
    """Agent updates opinion after hearing neighbors' views."""
    system = build_persona_system_prompt(agent["persona"])
    n_summary = "; ".join([f"Person (party={p}, opinion={o}/10)"
                           for o, p in zip(neighbor_opinions, neighbor_parties)])
    user = (f"You currently rate your support for '{topic}' as {agent['opinion']}/10.\n"
            f"You just heard these views from people around you: {n_summary}.\n\n"
            f"After hearing these perspectives, what is your new rating (1–10)? "
            f"Reply ONLY with the number.")
    msg = client.messages.create(
        model=model, max_tokens=5, temperature=0.2, system=system,
        messages=[{"role": "user", "content": user}]
    )
    try:    return int(msg.content[0].text.strip()[0])
    except: return agent["opinion"]

def run_opinion_dynamics(agents: list[dict], G: nx.Graph,
                          topic: str, n_steps: int = 10,
                          model="claude-haiku-4-5-20251001") -> pd.DataFrame:
    """
    Run opinion dynamics simulation on network G.
    Each step: each agent updates opinion based on neighbors' current opinions.
    """
    records = [{"step": 0, "agent_id": a["id"],
                "opinion": a["opinion"], "party": a["party"]} for a in agents]

    for step in range(1, n_steps + 1):
        new_opinions = {}
        for node in G.nodes():
            agent     = agents[node]
            neighbors = list(G.neighbors(node))
            if not neighbors:
                new_opinions[node] = agent["opinion"]
                continue
            nb_opinions = [agents[n]["opinion"] for n in neighbors]
            nb_parties  = [agents[n]["party"]   for n in neighbors]
            new_opinions[node] = update_opinion_after_exposure(
                agent, nb_opinions, nb_parties, topic, model)

        for node, new_op in new_opinions.items():
            agents[node]["opinion"] = new_op
            agents[node]["opinion_history"].append(new_op)
            records.append({"step": step, "agent_id": node,
                             "opinion": new_op, "party": agents[node]["party"]})

    df = pd.DataFrame(records)
    df.to_csv("${OUTPUT_ROOT}/tables/opinion-dynamics-trajectory.csv", index=False)
    return df

# Build a small-world social network (Watts-Strogatz)
N, K, P = 50, 4, 0.1
G = nx.watts_strogatz_graph(N, K, P, seed=42)

# Note: estimate cost before running full simulation
# N_agents=50, N_steps=10, 1 call/agent/step = 500 calls (haiku ~$0.05 total)

**Reporting template:**
> "We simulate opinion dynamics among N = [X] agents organized in a Watts-Strogatz small-world network (k = [K], p = [P]). Each agent is assigned a demographic persona drawn from [source; e.g., US Census marginal distributions]. At each of [T] time steps, agents update their position on [topic] after observing their immediate network neighbors' views, using Claude Haiku as the cognitive engine (temperature = 0.2; seed = 42). We track the Gini coefficient of opinion heterogeneity and partisan opinion gap across steps. Results are reported for [T] steps; sensitivity to network topology (Erdős-Rényi and scale-free alternatives) is shown in Figure A[X]."
```

---

### Step 6 — Validation Against Human Data (REQUIRED)

**All synthetic data used in publication must be validated against real human responses.** Distributional mismatch is common (Bisbee et al. 2023); report it transparently.

```python
from scipy.stats import ks_2samp
import numpy as np

# ── Compare synthetic to GSS / ANES / CCES distributions ──────────────
def validate_synthetic_vs_real(synthetic_responses: list[int],
                                real_responses: list[int],
                                variable_name: str) -> dict:
    """
    Compare synthetic and real response distributions.
    Returns alignment metrics for Methods reporting.
    """
    ks_stat, ks_p = ks_2samp(synthetic_responses, real_responses)
    mean_diff     = np.mean(synthetic_responses) - np.mean(real_responses)

    # Jensen-Shannon divergence (0 = identical; 1 = maximally different)
    from scipy.special import rel_entr
    def js_divergence(p, q):
        p, q = np.array(p)/sum(p), np.array(q)/sum(q)
        m = 0.5 * (p + q)
        return 0.5 * (sum(rel_entr(p, m)) + sum(rel_entr(q, m)))

    scale_vals = sorted(set(synthetic_responses) | set(real_responses))
    p_dist = [synthetic_responses.count(v)/len(synthetic_responses) for v in scale_vals]
    q_dist = [real_responses.count(v)/len(real_responses)            for v in scale_vals]
    jsd = js_divergence(p_dist, q_dist)

    return {
        "variable":        variable_name,
        "n_synthetic":     len(synthetic_responses),
        "n_real":          len(real_responses),
        "mean_synthetic":  round(np.mean(synthetic_responses), 3),
        "mean_real":       round(np.mean(real_responses), 3),
        "mean_diff":       round(mean_diff, 3),
        "ks_statistic":    round(ks_stat, 3),
        "ks_p":            round(ks_p, 4),
        "js_divergence":   round(jsd, 3),
        "aligned":         ks_stat < 0.10 and abs(mean_diff) < 0.5
    }

# ── Known limitations to report ───────────────────────────────────────
# 1. Homogenization bias: LLMs tend toward centrist/moderate responses
# 2. Demographic steerability: some groups are steered more reliably than others
# 3. Training recency: LLMs reflect data through training cutoff; recent events not captured
# 4. Intersectionality gaps: combinations of identities may not be well-represented
# 5. Rare populations: LLMs may poorly simulate truly marginalized groups
```

**Required validation reporting (Nature Computational Science / Science Advances):**
- Report KS statistic and Jensen-Shannon divergence between synthetic and real distributions for every key variable
- Report subgroup-level alignment (by race, party, education) not just aggregate
- Explicitly state that synthetic data is used for [pre-testing / power analysis / theory development], not as a substitute for human data
- If used for published substantive claims: requires matched real-data replication

---

### Step 7 — Synthetic Data Verification (Subagent)

```
SYNTHETIC DATA VERIFICATION REPORT
=====================================

FEASIBILITY GATE
[ ] Use case is appropriate (pre-testing / power analysis / theory; NOT substitute for human data)
[ ] IRB consideration documented (or exemption justified)
[ ] Known LLM limitations for this population acknowledged

PERSONA ENGINEERING
[ ] Personas cover the theoretical range of the key moderating variable
[ ] Persona prompts include macro + meso + micro context
[ ] Temperature documented (survey: 0.3–0.5; deliberation: 0.5–0.6; choice: 0.2–0.4)
[ ] Model name + version + date recorded
[ ] Prompts archived verbatim (system + user)

SIMULATION DESIGN
[ ] N personas and N reps per persona/condition documented
[ ] Experimental condition (vignette / conjoint attribute) manipulated cleanly
[ ] Randomization / counterbalancing applied where needed
[ ] Estimated cost computed before full run; reported in Methods

VALIDATION (if using synthetic data in analysis)
[ ] Compared to actual human survey data (GSS / ANES / CCES / original survey)
[ ] KS statistic and JSD reported per variable
[ ] Subgroup alignment checked (not just aggregate)
[ ] Homogenization bias assessed (are synthetic responses more centrist than real?)
[ ] Limitations section explicitly names known failure modes

OPINION DYNAMICS (if used)
[ ] Network topology specified and justified (small-world / random / scale-free)
[ ] N agents, N steps, update rule documented
[ ] Sensitivity to topology in robustness (at minimum 2 alternative networks)
[ ] Cost estimate computed (N_agents × N_steps × price/call)

REPRODUCIBILITY
[ ] set.seed(42) / random.seed(42) for persona sampling and network initialization
[ ] Raw LLM outputs (full responses, not just derived values) saved to CSV
[ ] Simulation results saved to output/[slug]/tables/

RESULT: [PASS / NEEDS REVISION]
Issues: [list]
```

---

