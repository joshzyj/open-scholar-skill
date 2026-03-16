# LLM Synthetic Data Generation Reference

## Conceptual Framework

**Silicon sampling** (Argyle et al. 2023): give an LLM a rich sociodemographic persona, then query it as if conducting a survey. The core claim is that LLMs encode the statistical relationship between demographics and attitudes from their training corpora, enabling them to approximate the marginal and conditional response distributions of real social groups.

**Key distinction from MODULE 7 (LLM Analysis)**: MODULE 7 uses LLMs to analyze existing human-generated text data. MODULE 8 uses LLMs to *generate* synthetic behavioral or attitudinal data where no real data yet exists — for pre-testing, theory development, or controlled experimentation.

---

## When Synthetic Data Is and Is Not Appropriate

| Appropriate use | Rationale |
|----------------|-----------|
| Survey instrument pre-testing | Catch confusing items, double-barreled questions, scale compression before human fielding |
| Power analysis / sample size estimation | Use synthetic response variance as prior for Bayesian power calculation |
| Theory development — "what would we expect if…?" | Explore theoretical implications of models before data collection |
| Exploring rare or hypothetical conditions | Conditions that cannot be manipulated empirically (e.g., "what if everyone had college education?") |
| Generating labeled training data for classifiers | With mandatory human validation (κ ≥ 0.70 on a 200-document sample) |

| Inappropriate use | Why |
|------------------|-----|
| Replacing human respondents in substantive published findings | Bisbee et al. (2023): significant distributional mismatch; synthetic data reproduces aggregate patterns but not within-subgroup variance |
| Claims about minority or marginalized populations | LLMs underrepresent rare identity combinations; known stereotyping effects |
| Predictions about future social behavior | LLMs reflect historical training data; cannot anticipate social change |
| Any use without explicit validation against real data | Argyle et al. (2023) results do not replicate uniformly across topics or countries |

---

## Persona Library

### US General Social Survey (GSS) — Representative Personas

Use these to compare synthetic responses against GSS time-series data.

```python
from dataclasses import dataclass
from typing import Optional

@dataclass
class SocialPersona:
    age: int; gender: str; race_ethnicity: str
    education: str; household_income: str; region: str
    political_affiliation: str; religious_attendance: str
    employment_status: str; occupation: Optional[str] = None
    neighborhood_type: Optional[str] = None
    organization_type: Optional[str] = None
    year: int = 2024

# Quadrant personas (2×2: party × education)
PERSONA_LIBRARY = {
    "white_noncollege_repub": SocialPersona(
        age=51, gender="male", race_ethnicity="White non-Hispanic",
        education="high school", household_income="$30-$60K",
        region="South US", political_affiliation="Strong Republican",
        religious_attendance="weekly", employment_status="employed full-time",
        occupation="skilled trades", neighborhood_type="rural"),

    "white_college_dem": SocialPersona(
        age=38, gender="female", race_ethnicity="White non-Hispanic",
        education="graduate degree", household_income="$100K+",
        region="Northeast US", political_affiliation="Strong Democrat",
        religious_attendance="never", employment_status="employed full-time",
        occupation="professional/managerial", neighborhood_type="urban"),

    "black_college_dem": SocialPersona(
        age=35, gender="female", race_ethnicity="Black non-Hispanic",
        education="bachelor's", household_income="$60-$100K",
        region="South US", political_affiliation="Strong Democrat",
        religious_attendance="weekly", employment_status="employed full-time",
        occupation="healthcare", neighborhood_type="suburban"),

    "hispanic_noncollege_indep": SocialPersona(
        age=42, gender="male", race_ethnicity="Hispanic/Latino",
        education="some college", household_income="$30-$60K",
        region="West US", political_affiliation="Independent",
        religious_attendance="monthly", employment_status="employed full-time",
        occupation="service sector", neighborhood_type="urban"),

    "asian_college_dem": SocialPersona(
        age=30, gender="female", race_ethnicity="Asian American",
        education="graduate degree", household_income="$100K+",
        region="West US", political_affiliation="Lean Democrat",
        religious_attendance="seldom", employment_status="employed full-time",
        occupation="technology", neighborhood_type="suburban"),

    "white_noncollege_dem": SocialPersona(
        age=58, gender="female", race_ethnicity="White non-Hispanic",
        education="high school", household_income="$0-$30K",
        region="Midwest US", political_affiliation="Lean Democrat",
        religious_attendance="seldom", employment_status="part-time",
        occupation="retail/service", neighborhood_type="rural"),
}
```

### Organizational Role Personas

```python
ORG_PERSONAS = {
    "tech_hiring_manager": {
        "org_type": "large technology corporation",
        "position_evaluated": "software engineer",
        "org_values": "innovation, engineering excellence, speed",
        "decision_maker_background": "15 years software engineering, now senior manager",
        "region": "West Coast US"
    },
    "nonprofit_executive": {
        "org_type": "community non-profit organization",
        "position_evaluated": "program coordinator",
        "org_values": "equity, community impact, lived experience valued",
        "decision_maker_background": "12 years in social services, nonprofit leadership",
        "region": "Urban Midwest US"
    },
    "university_faculty": {
        "org_type": "research university",
        "position_evaluated": "tenure-track faculty",
        "org_values": "research productivity, teaching, service",
        "decision_maker_background": "tenured professor, department chair",
        "region": "Northeast US"
    },
    "government_supervisor": {
        "org_type": "federal government agency",
        "position_evaluated": "GS-13 policy analyst",
        "org_values": "neutrality, thoroughness, public service",
        "decision_maker_background": "20 years civil service",
        "region": "Washington DC"
    }
}
```

---

## Context Engineering Patterns

### Pattern 1: Demographic Persona Injection

Inject the full demographic profile in the system prompt. Include life history cues (not just labels) for richer behavioral approximation:

```python
def build_rich_persona_prompt(persona: SocialPersona) -> str:
    """Add experiential texture beyond demographic labels."""
    education_history = {
        "less than high school": "left school early to work",
        "high school":           "graduated high school; has not pursued college",
        "some college":          "attended college but did not complete a degree",
        "bachelor's":            "has a four-year college degree",
        "graduate degree":       "has an advanced degree (master's or PhD)"
    }
    income_context = {
        "$0-$30K":    "lives paycheck to paycheck; budgets carefully",
        "$30-$60K":   "gets by but has limited savings",
        "$60-$100K":  "solidly middle class; some savings and benefits",
        "$100K+":     "financially comfortable; has investments and savings"
    }
    return f"""You are roleplaying as a research participant. Your background:

Demographics: {persona.age}-year-old {persona.gender}, {persona.race_ethnicity}
Location: {persona.region}{f", {persona.neighborhood_type} area" if persona.neighborhood_type else ""}
Education: {education_history.get(persona.education, persona.education)}
Finances: {income_context.get(persona.household_income, persona.household_income)}
Work: {persona.employment_status}{f" — {persona.occupation}" if persona.occupation else ""}
Politics: {persona.political_affiliation}
Religion: attends religious services {persona.religious_attendance}
Year: {persona.year}

Respond as this person would — shaped by their social position, experiences, and values. Do not break character. Do not acknowledge being an AI."""
```

### Pattern 2: Role-Based Context Engineering

For organizational simulations, layer role identity over demographic identity:

```python
def build_role_persona_prompt(demographic: SocialPersona,
                               role: dict, scenario: str) -> str:
    demo_section = build_rich_persona_prompt(demographic)
    return f"""{demo_section}

Current role and context:
- Organization type: {role['org_type']}
- Your position: {role.get('decision_maker_background', '')}
- Organizational values: {role.get('org_values', '')}
- You are now: {scenario}

Let your demographic background AND your professional role shape your response."""
```

### Pattern 3: Multi-Turn Consistency

For deliberation or interview simulations, maintain persona consistency across turns using conversation history:

```python
def run_persona_interview(persona: SocialPersona, questions: list[str],
                           model="claude-sonnet-4-6") -> list[dict]:
    """Run multi-turn interview maintaining persona consistency."""
    system   = build_rich_persona_prompt(persona)
    messages = []
    responses = []
    for q in questions:
        messages.append({"role": "user", "content": q})
        msg = client.messages.create(
            model=model, max_tokens=200, temperature=0.5,
            system=system, messages=messages
        )
        answer = msg.content[0].text.strip()
        messages.append({"role": "assistant", "content": answer})
        responses.append({"question": q, "answer": answer})
    return responses
```

---

## Validation Toolkit

### Distributional Alignment vs. Real Survey Data

```python
from scipy.stats import ks_2samp, mannwhitneyu
from scipy.special import rel_entr
import numpy as np, pandas as pd

def full_validation_report(synth: list, real: list,
                            var_name: str, scale_range: tuple) -> dict:
    """
    Full distributional alignment report for one variable.
    synth, real: lists of numeric responses on the same scale.
    """
    # KS test (sensitive to any shape difference)
    ks_stat, ks_p = ks_2samp(synth, real)

    # Mann-Whitney (sensitive to mean shift)
    mw_stat, mw_p = mannwhitneyu(synth, real, alternative="two-sided")

    # Jensen-Shannon divergence (symmetric; 0 = identical)
    lo, hi = scale_range
    bins = list(range(lo, hi + 2))
    def hist(data):
        counts = [data.count(v) for v in range(lo, hi + 1)]
        total  = sum(counts) or 1
        return [c/total for c in counts]
    p, q = hist(synth), hist(real)
    m = [0.5*(a + b) for a, b in zip(p, q)]
    jsd = 0.5 * sum(rel_entr(p, m)) + 0.5 * sum(rel_entr(q, m))

    # Mean and SD
    mean_diff = np.mean(synth) - np.mean(real)

    return {
        "variable":       var_name,
        "n_synthetic":    len(synth),
        "n_real":         len(real),
        "mean_synthetic": round(np.mean(synth), 3),
        "mean_real":      round(np.mean(real), 3),
        "sd_synthetic":   round(np.std(synth), 3),
        "sd_real":        round(np.std(real), 3),
        "mean_diff":      round(mean_diff, 3),
        "ks_statistic":   round(ks_stat, 3),
        "ks_p":           round(ks_p, 4),
        "jsd":            round(jsd, 4),
        "aligned":        ks_stat < 0.10 and abs(mean_diff) < 0.5
    }

def subgroup_alignment_report(synth_df: pd.DataFrame,
                               real_df: pd.DataFrame,
                               response_col: str,
                               group_col: str,
                               scale_range: tuple) -> pd.DataFrame:
    """Check alignment separately per demographic subgroup."""
    groups = sorted(set(synth_df[group_col].unique()) |
                    set(real_df[group_col].unique()))
    rows = []
    for g in groups:
        s = synth_df[synth_df[group_col] == g][response_col].dropna().tolist()
        r = real_df[real_df[group_col]   == g][response_col].dropna().tolist()
        if len(s) > 5 and len(r) > 5:
            rows.append({**full_validation_report(s, r, response_col, scale_range),
                         "subgroup": g})
    return pd.DataFrame(rows)
```

### Homogenization Bias Check

LLMs systematically produce more centrist responses than real humans. Always test for this:

```python
def check_homogenization_bias(synth: list, real: list,
                               midpoint: float, var_name: str) -> dict:
    """
    Test whether synthetic responses are more concentrated around the scale midpoint
    than real responses (homogenization / centrism bias).
    """
    synth_dist_from_mid = [abs(v - midpoint) for v in synth]
    real_dist_from_mid  = [abs(v - midpoint) for v in real]
    stat, p = mannwhitneyu(synth_dist_from_mid, real_dist_from_mid,
                            alternative="less")  # H1: synthetic closer to midpoint
    return {
        "variable":                  var_name,
        "mean_deviation_synthetic":  round(np.mean(synth_dist_from_mid), 3),
        "mean_deviation_real":       round(np.mean(real_dist_from_mid), 3),
        "homogenization_detected":   p < 0.05,
        "mw_p":                      round(p, 4)
    }
```

---

## Reporting Standards

### Methods Paragraph Template

> "We use [Claude Sonnet 4.6 / GPT-4o] to simulate [N] synthetic survey respondents using structured demographic personas (Argyle et al. 2023). Each persona encodes [list dimensions: age, gender, race/ethnicity, education, income, region, political affiliation, religious attendance, employment]. We elicited responses to [N_items] survey items covering [topic domains]. Each persona × item combination was replicated [K] times (temperature = [0.3–0.5]) to capture within-persona stochasticity; we use the replicate mean as the synthetic response. All personas were sampled from [US Census-calibrated marginal distributions / the list in Table SX]. Model: [model ID], annotation date [YYYY-MM-DD]; all prompts reproduced in Appendix [X]. To validate, we compare synthetic response distributions to [GSS [year] / ANES [year] / CCES [year]] across [N_items] items. [Kolmogorov-Smirnov statistics ranged from [lo] to [hi]; Jensen-Shannon divergence ranged from [lo] to [hi]]; see Table SX.] Following Bisbee et al. (2023), we note that synthetic data replicates aggregate group-level patterns [adequately / imperfectly] but understates within-group variance for [describe groups]. We therefore use synthetic data for [pre-testing / power analysis / theory exploration] only, and confirm all substantive findings with [real human data source]."

### Vignette / Conjoint Template

> "We embed a [2×2 / fully-crossed] experimental vignette within the persona simulation. The focal manipulation is [candidate race: {White, Black}] × [candidate gender: {man, woman}], holding all other attributes constant. We collected [N] ratings per condition × [N_personas] persona types. The dependent variable is the [7-point likelihood-of-hire rating / binary advance-to-next-round decision]. We estimate a linear model regressing the rating on [condition dummies + persona fixed effects], clustering SEs by persona type. Synthetic data validation: compared against [Bertrand & Mullainathan 2004 / own audit study data]: mean ratings in the White-man condition were [X_synth] (real: [X_real]); the racial gap was [Δ_synth] (real: [Δ_real])."

### Opinion Dynamics Template

> "We simulate opinion dynamics among [N] LLM agents arranged on a Watts-Strogatz small-world network (k = [K], rewiring probability p = [P]; seed = 42). Agents are assigned demographic personas drawn proportionally from [source]. At each of [T] time steps, agents update their position on [topic] after observing the current opinions of their [K] network neighbors, using Claude Haiku as the cognitive engine (temperature = [0.2]; deterministic update rule). We track the Gini coefficient of opinion variance and the partisan opinion gap (Strong Democrat − Strong Republican) across steps. Sensitivity analyses with Erdős-Rényi (p = 0.08) and Barabási-Albert (m = 2) networks are reported in Figure A[X]; qualitative patterns [hold / vary by topology]."

---

## Key References

- Argyle, L. P., Busby, E. C., Fulda, N., Gubler, J. R., Rytting, C., & Wingate, D. (2023). Out of One, Many: Using Language Models to Simulate Human Samples. *Political Analysis*, 31(3), 337–351.
- Bisbee, J., Clinton, J., Dorff, C., Kenkel, B., & Larson, J. (2023). Synthetic Replacements for Human Survey Data? The Perils of Large Language Models. *Political Analysis*.
- Horton, J. J. (2023). Large Language Models as Simulated Economic Agents: What Can We Learn from Homo Silicus? *NBER Working Paper 31122*.
- Park, J. S., O'Brien, J., Cai, C. J., Morris, M. R., Liang, P., & Bernstein, M. S. (2023). Generative Agents: Interactive Simulacra of Human Behavior. *UIST 2023*.
- Bail, C. A. (2024). Can Generative AI Improve Social Science? *PNAS*, 121(21), e2314021121.
- Santurkar, S., Durmus, E., Ladd, F., Lee, E., Liang, P., & Hashimoto, T. (2023). Whose Opinions Do Language Models Reflect? *ICML 2023*.
- Lin, H., & Zhang, Y. (2025). Navigating the Risks of Using Large Language Models for Text Annotation in Social Science Research. *Social Science Computer Review*. DOI: 10.1177/08944393251366243.
