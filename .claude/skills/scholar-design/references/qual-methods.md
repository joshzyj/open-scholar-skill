# Qualitative and Mixed-Methods Reference

## Qualitative Research Design

### Core Qualitative Approaches

#### In-Depth Interviews
**Purpose**: Understand subjective meanings, processes, and mechanisms; complement quantitative findings
**Sample size norms**: 20–60 interviews for most sociology papers; theoretical saturation guides stopping
**Sampling strategy**:
- Purposive sampling: Select cases that represent key variation
- Snowball sampling: Use referrals for hard-to-reach populations
- Theoretical sampling (grounded theory): Sample to develop/test emergent theory

**Interview guide structure**:
1. Grand tour questions: "Can you tell me about your experience with X?"
2. Mini-tour questions: "Can you walk me through a typical day/week?"
3. Probes: "Can you say more about that?" "What did you mean by...?"
4. Contrast questions: "How was that different from...?"
5. Hypothetical: "If you had to change one thing, what would it be?"

**Analysis**:
- Open coding → axial coding → selective coding (grounded theory: Strauss and Corbin)
- Thematic analysis (Braun and Clarke)
- Narrative analysis for biographical accounts
- Atlas.ti or NVivo for qualitative data management

**Reporting**: Direct quotations with context; link themes to hypotheses or concepts

---

#### Ethnography / Participant Observation
**Purpose**: Understand practices, meanings, and social interaction in naturalistic settings
**Duration**: Weeks to years; prolonged engagement required for credibility
**Field notes**: Write immediately after observation; descriptive AND reflective notes

**Types**:
- Full participant observation: Researcher participates fully
- Observer-as-participant: Primarily observes, some participation
- Ethnographic interview: Embedded interviews in the field

**Classic sociological ethnographies**:
- Goffman (1959) Presentation of Self (micro-interaction)
- Becker (1963) Outsiders (deviance)
- Duneier (1999) Sidewalk (urban poverty)
- Goffman, A. (2014) On the Run (policing and poverty)
- Lareau (2003) Unequal Childhoods (class and parenting)

**AJS especially receptive to ethnographic contributions**

---

#### Case Study Design
**Purpose**: In-depth understanding of a specific phenomenon in context; mechanism tracing

**Types** (Gerring 2007):
- Typical case: Representative instance of a broader pattern
- Deviant case: Anomaly that challenges existing theory
- Most-similar design: Compare cases similar on confounders, different on X
- Most-different design: Compare cases with same Y despite different contexts

**Process tracing**: Within-case causal inference by tracing the causal chain
- Sequence of events: A → B → C → Y
- Straw-in-the-wind tests, hoop tests, smoking gun tests

---

#### Historical and Archival Analysis
**Purpose**: Explain temporal sequences, path dependencies, institutional origins
**Data**: Newspapers, organizational records, census archives, court documents, letters

**Analytic approaches**:
- Sequence analysis: identify recurring patterns in event sequences
- Comparative historical analysis: Mill's method of difference/agreement
- Abbott's narrative: social processes as sequences of events

---

## Mixed Methods Designs

### Sequential Explanatory Design
1. Phase 1: Quantitative study (surveys, administrative data)
2. Phase 2: Qualitative (interviews, ethnography) to explain quantitative findings

**Best for**: When quant finds unexpected patterns and qual illuminates why
**Example**: Survey shows X is correlated with Y. Interviews reveal mechanism M.

**Integration point**: Sampling for qual phase uses quant results (e.g., interview outliers or representative cases from regression residuals)

---

### Sequential Exploratory Design
1. Phase 1: Qualitative (inductive; develop concepts, typology, hypotheses)
2. Phase 2: Quantitative (test what emerged in Phase 1)

**Best for**: Developing survey instruments; testing ethnographically-derived hypotheses
**Example**: Ethnography identifies 3 coping strategies → survey scale developed → tested in large sample

---

### Concurrent Triangulation
Both methods run simultaneously; convergence (or divergence) of findings is the goal
**Best for**: When both methods are equally important; validation purposes

---

## Qualitative Standards and Credibility

### Trustworthiness Criteria (Lincoln and Guba)
| Quantitative | Qualitative Equivalent | How to Establish |
|-------------|----------------------|-----------------|
| Internal validity | Credibility | Member checking, prolonged engagement, triangulation |
| External validity | Transferability | Rich description, purposive sampling for range |
| Reliability | Dependability | Audit trail, reflexivity memo |
| Objectivity | Confirmability | External audit, transparency about researcher position |

### Reflexivity
State researcher's positionality:
- Insider/outsider status to community studied
- How identity shaped access and interpretation
- Steps taken to reduce researcher bias

### Saturation
For interview studies: "We continued sampling until no new themes emerged (N = 38)."
Theoretical saturation: New cases no longer challenge or refine the emerging theory.

### Reflexivity Memo Template

Write a reflexivity memo before fieldwork begins and update throughout analysis:

```
REFLEXIVITY MEMO — [Project / Phase]
Author: [Name] | Date: [Date]

1. POSITIONALITY
   My relationship to the community/phenomenon: [insider / outsider / partial insider]
   Demographic similarities/differences from participants: [race, class, gender, immigration status, etc.]
   Prior assumptions or hypotheses I held before fieldwork:

2. ACCESS AND RAPPORT
   How I gained access: [gatekeeper? organizational affiliation? snowball?]
   Potential for reactivity: [How might my presence change participant behavior?]
   Power dynamics: [interviewer–participant; institutional affiliation effects]

3. ANALYTIC REFLEXIVITY
   Codes or themes that surprised me:
   Moments when I noticed my assumptions shaping interpretation:
   Steps taken to check interpretations: [member checking; colleague debriefs; negative case analysis]

4. IMPLICATIONS FOR CLAIMS
   Which claims are most vulnerable to my positionality?
   How I have tried to mitigate this [triangulation / multiple coders / member checking]:
```

### Member Checking Protocol

After analysis, share key themes or preliminary findings with a subset of participants:

1. Select 5–10 participants who represent key variation in your sample
2. Share a 1–2 page plain-language summary of major themes
3. Ask: "Does this resonate with your experience? Is anything missing or misrepresented?"
4. Document responses — whether they confirm, contradict, or nuance your interpretation
5. Report in Methods: "We conducted member checking with [N] participants; [summarize outcome]"

Note: Member checking does not require full participant agreement — divergence is analytically valuable and should be reported honestly.

---

## Qualitative Reporting Standards

### AJS Qualitative Paper Structure
```
1. Introduction: Puzzle and contribution
2. Prior Research: Literature situating the case
3. Data and Methods: Site, access, sample, analysis approach
4. Findings: Thematic or narrative (with quotes)
5. Discussion: Theoretical implications
6. Conclusion
```

### Presenting Quotes
- Use representative quotes, not just dramatic ones
- Provide enough context for the reader to assess the quote
- Signal whether the quote is typical or exceptional
- Format: block quotes for 3+ lines; inline with quotation marks for shorter

**Example**:
> "When I first got there, I didn't know anyone. But after a few weeks, you start to figure out who to trust." (Maria, 32, Dominican immigrant, interviewed June 2023)

### Tables in Qualitative Research
- Sample characteristics table: Demographics, selection criteria
- Thematic table: Theme → subthemes → illustrative quotes
- Case comparison table: Cases × key variables

---

## Computational Text Analysis (Hybrid)

For studies combining computational and qualitative approaches:

### When to use which:
| Goal | Method |
|------|--------|
| Topic prevalence over time | LDA / STM topic modeling |
| Sentiment and tone | Lexicon-based (LIWC, VADER) or transformer models |
| Semantic meaning | Word embeddings (Word2Vec, GloVe, BERT) |
| Named entities | spaCy NER |
| Classification | Supervised learning with labeled data |
| Close reading of mechanism | Human qualitative analysis |

### Validation hybrid approach:
1. Apply computational method to full corpus
2. Randomly sample 100–200 texts for human reading
3. Compute agreement between human coders and algorithm
4. Report Krippendorff's alpha or Cohen's kappa

### Reporting standards for NCS/Science Advances text papers:
- Report model architecture and hyperparameters
- Report cross-validation approach
- Report precision, recall, F1 for classification tasks
- Deposit code and (if possible) data
