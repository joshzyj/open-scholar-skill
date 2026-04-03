---
name: scholar-open
description: >
  Implement open science practices for a social science study. Five modes:
  (1) PREREGISTER — OSF / AsPredicted / EGAP / Registered Reports; secondary-data
  preregistration; deviation reporting; (2) DATA-SHARE — FAIR principles,
  de-identification, repository selection (Harvard Dataverse / ICPSR / Zenodo /
  QDR), platform-specific social media policies, computational data (model weights,
  embeddings), data availability statement templates; (3) CODE-SHARE — replication
  packages (minimum + gold-standard), README template, renv / conda / Docker /
  Makefile reproducibility environments, CITATION.cff, Zenodo DOI via GitHub;
  (4) FULL-PACKAGE — data management plan (NSF/NIH DMP template), CRediT authorship,
  COI declaration, IRB statement, preprint strategy, open access options with APC
  waiver guidance; (5) REPLICATION-PACKAGE — end-to-end audit against journal
  requirements. Required for Nature journals; increasingly expected at ASR,
  Demography, and Science Advances. Saves preregistration document, data management
  plan, and replication-package README to disk.
tools: Read, Write, Bash, WebSearch
argument-hint: "[PREREGISTER|DATA-SHARE|CODE-SHARE|FULL-PACKAGE|REPLICATION-PACKAGE] [study description or journal name]"
user-invocable: true
---

# Scholar Open Science

You are an expert in open science practices for social science research. You help
researchers implement transparency, preregistration, data sharing, and reproducibility
in ways that strengthen their work and meet the increasingly stringent requirements
of top journals.

---

## Dispatch Table

| If `$ARGUMENTS` contains | Route to |
|--------------------------|----------|
| `preregister` / `prereg` / `osf` / `registration` | Step 1 (Preregistration) |
| `registered reports` / `rr` / `stage 1` | Step 1 → Section 1c (Registered Reports) |
| `secondary data` / `secondary analysis` | Step 1 → Section 1f (Secondary-data prereg) |
| `data-share` / `data share` / `data availability` / `deposit` | Step 2 (Data Sharing) |
| `fair` / `fair data` | Step 2 → Section 2a (FAIR principles) |
| `social media` / `twitter` / `reddit` / `platform` | Step 2 → Section 2f (Platform policies) |
| `model weights` / `embeddings` / `computational data` | Step 2 → Section 2e (Computational data) |
| `code-share` / `code share` / `replication` / `github` | Step 3 (Code & Replication) |
| `docker` / `conda` / `renv` / `environment` | Step 3 → Section 3c (Reproducibility envs) |
| `full-package` / `full package` / `submission` / `dmp` | Step 4 (Full Open Science Package) |
| `credit` / `authorship` / `coi` | Step 4 → Section 4b/4c (CRediT / COI) |
| `replication-package` / `audit` / `check package` | Step 5 (Replication Package Audit) |
| Default (no keyword) | Run all steps in order |

---

## Step 0: Argument Parsing & Project State

Parse `$ARGUMENTS`:
1. **MODE**: PREREGISTER | DATA-SHARE | CODE-SHARE | FULL-PACKAGE | REPLICATION-PACKAGE | ALL
2. **STUDY_TYPE**: original collection | secondary data | qualitative | computational/CSS | RCT | mixed
3. **JOURNAL**: ASR | AJS | Demography | Science Advances | NHB | NCS | other (TBD)
4. **STAGE**: pre-data | mid-study | post-analysis | pre-submission | post-rejection

Print a project state header:
```
════════════════════════════════════════════════════════
 SCHOLAR-OPEN  |  MODE: [mode]
 STUDY TYPE: [type]  |  JOURNAL: [journal]  |  STAGE: [stage]
════════════════════════════════════════════════════════
```

---

## Step 1: PREREGISTRATION

### 1a. When to Preregister

**Strongly recommended (increasingly required)**:
- Original data collection (survey, experiment, field study)
- Nature Human Behaviour, Nature Computational Science: expected; non-preregistration must be stated in Methods
- Science Advances: encouraged; flag as "preregistered" in cover letter
- ASR/AJS: growing reviewer expectation; protects against p-hacking allegations

**Still valuable (optional)**:
- Secondary data analysis with pre-specified hypotheses (see Section 1f)
- Replication studies — use AsPredicted "registered replication" format
- Registered Reports (see Section 1c) — submit before data collection; two-stage review

**Not applicable (say so explicitly)**:
- Purely inductive qualitative work — note "inductive design; preregistration not applicable"
- Archival/historical analysis where hypotheses emerge from sources
- Exploratory computational work generating theory (label all analyses "exploratory")

### 1b. Preregistration Platforms

| Platform | Best For | Embargo | DOI | URL |
|----------|----------|---------|-----|-----|
| **OSF Preregistrations** | Social science; most flexible templates | Yes (4 years) | Yes | osf.io/registries |
| **AsPredicted** | Quick 9-question; confirmatory studies | Yes (until publication) | No | aspredicted.org |
| **EGAP** | Political science / field experiments | Yes | Yes | egap.org/registry |
| **AEA RCT Registry** | Economics / social science RCTs | Yes | Yes | socialscienceregistry.org |
| **OSF Registered Reports** | Pre-results peer review (any design) | No | Yes | osf.io/registries |

### 1c. Registered Reports (RR) Format

Registered Reports are a special journal format where peer review occurs in two stages:
- **Stage 1**: Methods + Introduction reviewed and conditionally accepted before data collection
- **Stage 2**: Full results submitted; accepted regardless of findings (in-principle acceptance)

**Journals accepting RRs in social/computational sciences**:
- *Nature Human Behaviour*, *Psychological Science*, *PLOS ONE*, *Collabra*, *Advances in Methods and Practices in Psychological Science (AMPPS)*, *Social Psychology* — growing list at cos.io/rr

**RR Manuscript Structure**:
```
Stage 1 Submission:
├── Introduction (full theory + hypotheses)
├── Methods (complete design, sampling, measures, analysis plan)
├── Power analysis (justify N)
└── No Results or Discussion

Stage 2 Submission (after data collection):
├── Introduction (unchanged)
├── Methods (unchanged; note any deviations)
├── Results
└── Discussion
```

**OSF RR Preregistration workflow**:
1. Write Stage 1 manuscript
2. Submit to journal; receive In-Principle Acceptance (IPA)
3. Register on OSF with IPA letter attached
4. Collect data; write Stage 2 manuscript
5. Submit Stage 2 to same journal; link OSF registration

### Registered Reports — Stage 1 Submission Template

**Required sections for Stage 1 (In-Principle Acceptance)**:

1. **Introduction & Rationale** (800--1500 words)
   - Research question and significance
   - Theoretical framework
   - Hypotheses (numbered, directional)

2. **Methods** (1500--3000 words)
   - Study design (with diagram if complex)
   - Participants: target N, sampling strategy, inclusion/exclusion criteria
   - Materials/measures: all instruments, scales, variable operationalization
   - Procedure: step-by-step protocol

3. **Analysis Plan** (1000--2000 words)
   - Primary analyses: exact model specifications for each hypothesis
   - Secondary/exploratory analyses (clearly labeled)
   - **Stopping rules**: minimum N for adequacy; interim analysis plan (if applicable)
   - **Exclusion criteria**: pre-specified rules for excluding observations/participants
   - **Multiple comparisons**: correction method + which outcomes are primary vs. exploratory
   - **Power analysis**: target power (>=0.80), assumed effect size (with justification from prior work), sample size calculation (with code)
   - **Robustness checks**: pre-specified alternative specifications
   - **Positive result criteria**: what constitutes support for each hypothesis?
   - **Interpretation of null results**: planned equivalence test bounds (if applicable)

4. **Timeline & Feasibility**
   - Data collection start/end dates
   - IRB status
   - Funding status
   - Data access confirmed (for secondary data)

5. **Stage 2 Deviation Documentation** (template for later)
   - Any deviations from Stage 1 protocol must be documented with justification
   - Classify deviations: minor (does not affect interpretation) vs. major (affects primary analyses)

**Journals accepting Registered Reports**: Nature Human Behaviour, Cortex, Royal Society Open Science, European Journal of Social Psychology, Political Science Research and Methods, others (see COS registry: cos.io/rr/).

### 1d. OSF Preregistration Workflow

**Step 1**: Create OSF account → New Project → Add collaborators → Organize folders
```
OSF Project structure:
├── Preregistration/   ← Lock registration here
├── Data/              ← Deposit analysis dataset
├── Code/              ← Link to GitHub repository
└── Papers/            ← Preprint + published version
```

**Step 2**: Write the preregistration document (use template below — save as PDF and upload)

```
═══════════════════════════════════════════════════════════
PREREGISTRATION: [Paper Title]
Date: [Today's date]
Authors: [Names + affiliations]
OSF Project: [URL]
═══════════════════════════════════════════════════════════

STUDY INFORMATION
─────────────────
Title: [Matches planned paper title]
Research questions:
  1. [RQ1 — specific, answerable]
  2. [RQ2 — if applicable]

Hypotheses (numbered, directional):
  H1: [Variable X] is positively/negatively associated with [Outcome Y]
      among [Population Z].
      Rationale: [2–3 sentences from theory section]
      Direction: Positive / Negative / Non-linear [specify shape]

  H2: The effect of X on Y is [stronger/weaker] for [Group A] vs. [Group B].
      Rationale: [...]

  H0 (null): [If testing null — e.g., "We expect no difference between groups
      if the mechanism requires [condition] that is absent here."]

DESIGN PLAN
───────────
Study type: Observational survey / RCT / Field experiment / Secondary data analysis
Blinding: [Yes — double-blind / No — observational / Partial]
Study design: Cross-sectional / Longitudinal (waves: N=?) / Experimental
Randomization: [How assigned to conditions — N/A if observational]

SAMPLING PLAN
─────────────
Existing data: Yes / No
If yes: [Describe what you know; confirm no confirmatory analyses run yet]
Data collection: [Detailed procedure]
Sample size: N = [X]; justify via power analysis
  Power analysis: We need N = [X] to detect d = [Y] / β = [Z] with 80%
  power at α = .05 (two-tailed), using [pwr::pwr.t.test / simr / MDES].
Stopping rule: [Pre-specified; e.g., "close survey after N = 1,000 completes
  or 90 days, whichever comes first"]

VARIABLES
─────────
Primary dependent variable: [Name], [operationalization], [scale/range]
Secondary DVs: [If any]
Primary independent variable: [Name], [operationalization]
Moderators: [If testing H2]
Covariates: [List each; one-phrase justification per covariate]
  - Age: [Controls for life course variation in X]
  - Female: [Controls for gender gap in Y]

ANALYSIS PLAN
─────────────
Primary model: [OLS / FE / logistic / Cox / multilevel] with
  [robust SEs / clustered SEs at level Z / bootstrapped SEs]
  Equation: Y_i = β₀ + β₁X_i + β₂C₁ + β₃C₂ + ε_i
  Test for H1: β₁ significantly positive (p < .05, two-tailed)
  Test for H2: β₃ (X × Group) significantly different from zero

Sample restrictions:
  Include: [Age range; employment status; geography]
  Exclude: [Missing on outcome (N ≈ ?); extreme outliers > 3 SD]

Transformations: [Log income; standardize continuous predictors (mean=0, SD=1)]
Missing data: [Listwise deletion / Multiple imputation (m=20, mice package)]
Multiple comparisons: [We test [N] hypotheses; apply [Bonferroni / BH-FDR /
  none — hypotheses derived from single theory and are not independent]]

Exploratory analyses (not pre-specified; will be labeled "exploratory"):
  - Heterogeneity by [demographic group]
  - [Other post-hoc analyses]

SOFTWARE AND VERSIONS
─────────────────────
Primary: R version [X.X.X] / Stata [version] / Python [version]
Key packages: [fixest, marginaleffects, mice, etc. with versions]
Seed: set.seed([fixed number, e.g., 42])

OTHER
─────
IRB approval: [Protocol number / pending / exempt — see Section 4d]
Funding: [Grant number if applicable]
Embargoed: [Yes — publish upon paper submission / No — make public now]
═══════════════════════════════════════════════════════════
```

**Step 3**: Lock the preregistration
- Upload PDF to OSF project
- Click "Register" → choose "OSF Preregistration" template
- Optionally set embargo (up to 4 years)
- Once locked, **cannot be modified** — deviations must be reported in paper

**Step 4**: Cite in manuscript
> "This study was preregistered prior to data collection at the Open Science
> Framework (https://osf.io/[ID], registered [date])."

### 1e. AsPredicted Quick Format (9 Questions)

Use when you want a quick preregistration before accessing data:

```
1. Data collection. Have any data been collected already?
   → [No / Yes, but I have not conducted any confirmatory analysis]

2. Hypothesis. What's the main question / hypothesis?
   H1: [Directional prediction]

3. Dependent variable. How measured?
   [Name; scale; reference period; e.g., "Income in USD, continuous, past year"]

4. Conditions. How many conditions?
   [Observational: N/A / Experimental: [list treatment arms]]

5. Analyses. Exact model?
   [OLS / logistic / FE with robust SEs; controls: age, gender, race, education]

6. Outliers and exclusions. Criteria?
   [Exclude missing on DV; winsorize income at 99th percentile]

7. Sample size. How many obs / what determines it?
   [N = 1,200; secondary data PSID 2019 wave]

8. Other. Anything else to preregister?
   [Exploratory: heterogeneity by race; will be labeled exploratory in paper]

9. Title. Give a title.
   [Preregistration of: Paper Title]
```

### 1f. Secondary Data Preregistration

Even with existing data, preregistering before confirmatory analysis retains value:

**Three scenarios and how to handle**:

| Scenario | Preregistration approach |
|----------|-------------------------|
| Downloaded but not looked at | Full preregistration; note data downloaded but analyses not run |
| Looked at descriptives only | Partial preregistration; note "examined descriptive statistics; no confirmatory analyses run" |
| Fully analyzed exploratory | Cannot preregister confirmatory analysis; label all results "exploratory" |

**Language for secondary data preregistration**:
```
Methods section:
"Although this study uses secondary data ([Dataset, year]), we preregistered
our hypotheses and analysis plan before conducting any confirmatory analyses
(OSF: https://osf.io/[code], registered [date]). Prior to registration, we
had examined [descriptive statistics / variable distributions] but had not
tested any directional hypotheses."
```

**Language for un-preregistered secondary data**:
```
"This study uses secondary data and was not preregistered. All reported
analyses should be interpreted as exploratory. To guard against inflated
Type I error, we [applied Bonferroni correction / report exact p-values
and encourage replication / conducted a pre-specified sensitivity analysis
with a held-out validation sample (N = [X])]."
```

### 1g. Reporting Deviations

Every deviation from the preregistration MUST be disclosed:

```
"Our preregistered analysis plan specified [X]. We deviate from this plan
in the following ways:
  (1) [Deviation]: [We added a covariate (household size) not in the original
      plan because reviewers of a related paper flagged it as a potential
      confounder.] The preregistered specification (without this control) is
      reported in Appendix Table A[X] and yields [consistent / slightly
      different] results.
  (2) [Deviation]: [We changed the SE clustering level from individual to
      county after discovering within-county clustering in the residuals.]"
```

See `references/preregistration.md` for templates and platform comparisons.

---

## Step 2: DATA SHARING

### 2a. FAIR Data Principles

FAIR = **F**indable, **A**ccessible, **I**nteroperable, **R**eusable.
Required for Nature journals; NHB/NCS reporting summary asks about each dimension.

| Principle | What it means | How to implement |
|-----------|---------------|-----------------|
| **Findable** | Data has persistent identifier (DOI) and rich metadata | Deposit in Zenodo/Dataverse with DOI; fill title, authors, subject, description |
| **Accessible** | Data retrievable via standard protocol; access conditions clear | Use HTTPS-accessible repository; specify who can access restricted data + how |
| **Interoperable** | Uses standard formats and vocabulary | Save as CSV/TSV (not Excel); use standard codebook with variable names + labels; apply domain ontologies where relevant |
| **Reusable** | Clear license; rich provenance; data described fully | Attach LICENSE (CC-BY or CC0); write codebook documenting all variables, value codes, missing codes, transformations |

**FAIR compliance checklist for manuscript**:
- [ ] Dataset deposited with DOI
- [ ] Metadata: title, authors, abstract, keywords, date, version filled
- [ ] Data in open format (CSV, TSV, JSON — not SPSS .sav or Stata .dta without conversion)
- [ ] Codebook documents all variables (name, label, type, range, missing code)
- [ ] LICENSE file present (CC0 for data; CC-BY or MIT for code)
- [ ] Provenance documented (where data came from, transformations applied)

### FAIR Principles — Operationalization Checklist

**Findable**:
- [ ] Dataset has a globally unique persistent identifier (DOI via Zenodo/Dataverse/ICPSR)
- [ ] Rich metadata (title, authors, description, keywords, temporal coverage, geographic scope)
- [ ] Metadata searchable in repository catalog
- [ ] README.md included with dataset

**Accessible**:
- [ ] Data retrievable via standard protocol (HTTPS download or API)
- [ ] Access conditions clearly stated (open / restricted / embargoed)
- [ ] If restricted: DUA template provided; contact information for access requests
- [ ] Metadata accessible even if data is restricted

**Interoperable**:
- [ ] Data in open format (CSV, TSV, Parquet — NOT proprietary Excel/SPSS/SAS)
- [ ] Variables use standard vocabularies where possible
- [ ] Codebook/data dictionary included with variable labels, value labels, missing data codes
- [ ] Character encoding: UTF-8

**Reusable**:
- [ ] Clear license specified (CC-BY 4.0 recommended; CC0 for maximum reuse)
- [ ] Provenance documented (data source, collection method, processing steps)
- [ ] Data cleaning scripts included (or referenced)
- [ ] Citation instructions provided (BibTeX entry for the dataset)

### 2b. Data Sensitivity Classification

```
Can you share the data?
│
├─ ORIGINAL COLLECTION
│   ├─ Fully de-identified + consent allows sharing
│   │   └─ → Deposit openly (Harvard Dataverse / Zenodo / OSF)
│   ├─ Sensitive (health, income, location) → de-identify first (Step 2d)
│   │   └─ → Deposit with access controls (ICPSR restricted / embargoed Dataverse)
│   └─ Cannot share (IRB restriction, no consent)
│       └─ → Code only; restricted-access data availability statement
│
├─ SECONDARY DATA
│   ├─ Public-use (ACS, GSS, CPS, HRS public, NLSY public)
│   │   └─ → Include processed data in package OR point to official download
│   ├─ Restricted-use (NLSY Geo, FSRDC, linkage files)
│   │   └─ → Code only; describe access pathway in paper
│   └─ Licensed/proprietary (Gallup, Nielsen, LexisNexis)
│       └─ → Code + derived aggregates if permitted; data access statement
│
├─ SOCIAL MEDIA (see Step 2f for platform-specific rules)
│   ├─ Twitter/X: Cannot redistribute raw; can share tweet IDs (rehydrate)
│   ├─ Reddit: pushshift data sharing restricted since 2023; share post IDs
│   └─ Derived data (DTM, embeddings, aggregated counts): usually shareable
│
└─ COMPUTATIONAL / ML (see Step 2e)
    ├─ Model weights: share via HuggingFace Hub or Zenodo
    └─ Embeddings / feature matrices: share as CSV/numpy array via Zenodo
```

### 2c. Repository Selection

| Repository | Field | Max size | Access control | Best for |
|------------|-------|----------|---------------|---------|
| **Harvard Dataverse** | Social science | 2.5 GB/file, 1 TB/dataset | Public / restricted / embargo | Survey data, population datasets, sociology |
| **ICPSR** | Social/behavioral | Unlimited | Restricted-use support | Large surveys, administrative data, longitudinal |
| **OSF** | Broad | 50 GB total | Public / private | Small datasets; integrates with preregistration |
| **Zenodo** | Broad/computational | 50 GB/record | Public (versioned) | Code + data; NCS requirement; GitHub integration |
| **QDR** | Qualitative SS | Moderate | Project-based | Interview transcripts, field notes, mixed methods |
| **UK Data Service** | UK social science | Large | Restricted | UK-based population data |

**Harvard Dataverse deposit steps**:
```
1. dataverse.harvard.edu → Log in → "Add Data" → "New Dataset"
2. Fill metadata: title, author, contact, description, subject, keywords
3. Upload files (data + codebook.pdf + README.md + code/)
4. Set access:
   - Public: available immediately on publication
   - Restricted: requestors must apply + sign DUA
   - Embargo: public after [date] (use for pre-publication)
5. Publish → receives DOI (e.g., https://doi.org/10.7910/DVN/...)
```

**Zenodo + GitHub auto-archive**:
```bash
# 1. Go to zenodo.org/account/settings/github
# 2. Toggle ON the repository
# 3. Create a GitHub release:
git tag v1.0.0
git push origin v1.0.0
# → Zenodo auto-creates DOI for this release
# Add badge to README:
# [![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.XXXXXXX.svg)]
```

### 2d. De-Identification Procedures

**Direct identifiers — remove entirely**:
- [ ] Full name → participant ID (store ID-name lookup table separately, encrypted)
- [ ] Exact address → state / county / 3-digit ZIP
- [ ] Date of birth → age in years (or 5-year age bands if N < 100 per cell)
- [ ] Exact event dates → year or year-quarter
- [ ] Phone numbers, email addresses, SSNs → remove
- [ ] Employer name → NAICS/SIC industry code
- [ ] School name → institution type/level
- [ ] Photos, voice recordings → store separately; do not deposit publicly

**Quasi-identifiers — suppress or aggregate**:
Apply k-anonymity: every combination of quasi-identifiers (sex × race × age × geography)
must appear at least k=5 times.

```r
library(sdcMicro)
sdc <- createSdcObj(dat = df,
                    keyVars = c("age_cat", "sex", "race", "state"),
                    numVars = c("income", "earnings"))
print(sdc)                       # Risk statistics
sdc <- localSuppression(sdc, k = 5)
clean_df <- extractManipData(sdc)

# Additional: top-code extremes
clean_df$income <- pmin(clean_df$income, quantile(clean_df$income, .99))
```

**Additional techniques**:
- **Cell suppression**: Replace cells with N < 5 with `NA` in public tables
- **Top/bottom-coding**: Income > $500K → "500K+" (report threshold in codebook)
- **Noise injection**: Add small random noise to continuous variables (document in codebook)

### 2e. Computational Data Sharing (Model Weights, Embeddings)

For computational papers (NCS, Science Advances, CSS venues):

| Artifact | Format | Repository | Notes |
|----------|--------|------------|-------|
| Fine-tuned model weights | HuggingFace Hub (safetensors) | HuggingFace + Zenodo for DOI | License: Apache-2.0 if based on Apache model |
| Pre-trained embeddings (dense vectors) | numpy `.npy` / CSV | Zenodo | Include column/row metadata |
| Document-term matrix | scipy sparse `.npz` / CSV | Zenodo | Include vocabulary file |
| Topic model (STM/LDA) | `.rds` (R) / `.pkl` (Python) | OSF or Zenodo | Include run script |
| Annotation labels (LLM/human) | CSV with doc_id, label, annotator | Zenodo | Include codebook + IAA scores |
| Network edgelist | CSV (source, target, weight) | Zenodo or Harvard Dataverse | Include node attribute file |

**HuggingFace Hub upload**:
```python
from huggingface_hub import HfApi
api = HfApi()
api.create_repo(repo_id="username/paper-model", repo_type="model")
api.upload_folder(
    folder_path="./model_weights",
    repo_id="username/paper-model",
    repo_type="model"
)
# Add model card README with paper citation, training details, intended use
```

**Linking to Zenodo for persistent DOI**:
```python
# After uploading to Zenodo manually or via API:
# In paper: "Model weights and embeddings are archived at [DOI]"
# In HuggingFace model card: "Archived version: [Zenodo DOI]"
```

### 2f. Social Media Platform Policies

| Platform | Raw data | Tweet/Post IDs | Derived features | Notes |
|----------|----------|---------------|-----------------|-------|
| **Twitter/X** | Cannot redistribute | Can share (rehydrate via API) | DTM, embeddings: OK | Use `twarc` to rehydrate IDs |
| **Reddit** | Cannot redistribute | Can share post/comment IDs | Aggregated metrics: OK | Pushshift no longer public post-2023; use Reddit API |
| **Facebook/Meta** | Cannot redistribute | Cannot share | Aggregated only | CrowdTangle shut down 2024; use Meta Content Library (academic) |
| **TikTok** | Cannot redistribute | Cannot share | Aggregated only | TikTok Research API (apply) |
| **YouTube** | Cannot redistribute | Video IDs: OK | Aggregated metrics: OK | YouTube Data API v3 |
| **Mastodon** | Federated — check instance ToS | Can share post URLs | Derived: OK | More permissive than corporate platforms |
| **LinkedIn** | Cannot redistribute | Cannot share | Aggregated only | Very restricted; academic access via approved partners |

**Tweet ID archive deposit**:
```python
# Save tweet IDs only (compliant with Twitter ToS)
import pandas as pd
df_ids = df[['tweet_id', 'created_at']].copy()  # IDs + timestamps only
df_ids.to_csv('tweet_ids.csv', index=False)
# Deposit tweet_ids.csv on Zenodo

# Rehydration instruction in README:
# twarc2 hydrate tweet_ids.csv --output hydrated_tweets.jsonl
```

**Data availability statement for social media**:
```
"The raw social media data cannot be redistributed per the platform's Terms of
Service. Tweet/post IDs sufficient for data reconstruction are available at
[Zenodo DOI]. The derived dataset (document-term matrix / aggregated engagement
counts) used in this analysis is also archived at [Zenodo DOI]. Data collection
and processing code is available at [GitHub URL]."
```

### 2g. Data Availability Statement Templates

**Fully open (deposited)**:
```
"The data that support the findings of this study are openly available at
[Harvard Dataverse / Zenodo] at https://doi.org/[DOI], reference number [X]."
```

**Restricted (apply for access)**:
```
"The data used in this study are available through [ICPSR / institutional
repository] under a restricted data use agreement. Instructions for obtaining
access are available at [URL]. The analysis code is available at [GitHub URL]."
```

**Secondary public data (no deposit)**:
```
"The [General Social Survey / American Community Survey / NLSY] data used in
this study are publicly available and can be downloaded from [official source URL].
The derived analytic dataset and replication code are archived at [Zenodo/Dataverse
DOI]."
```

**Qualitative (anonymized excerpts only)**:
```
"Interview transcripts cannot be publicly shared to protect participant
confidentiality per IRB protocol [number]. Anonymized excerpts supporting the
main findings are provided in the Online Supplementary Appendix. Requests for
additional access should be directed to the corresponding author."
```

**Social media (IDs + derived)**:
```
[See Section 2f template above]
```

See `references/data-sharing.md` for repository setup, de-identification code, and FAIR
implementation.

### Data Sharing Statements for Restricted Data

**When data cannot be shared publicly**:

Template 1 (Licensed data — PSID, NLSY, NHANES restricted):
```
"The data used in this study are available from [source] under a restricted-use Data Use Agreement. Researchers can apply for access at [URL]. Our analysis code is available at [repository URL] and can be applied to the data once access is granted."
```

Template 2 (IRB-restricted qualitative data):
```
"Interview transcripts contain identifying information and cannot be shared per our IRB protocol ([institution], #[number]). De-identified thematic summaries and the codebook are available at [repository URL]. Interested researchers may contact [email] to discuss data access."
```

Template 3 (Partner/proprietary data):
```
"The data were provided by [organization] under a data sharing agreement that prohibits redistribution. Interested researchers should contact [organization contact] to negotiate access. Our analysis code is available at [repository URL]."
```

---

## Step 3: CODE & REPLICATION PACKAGES

### 3-pre. Consume `output/[slug]/scripts/` (from scholar-analyze / scholar-compute)

If `output/[slug]/scripts/` exists from a prior `/scholar-analyze` or `/scholar-compute` run, use it as the primary source for replication package code:

1. **Copy and renumber** scripts from `output/[slug]/scripts/` into the replication package `code/` directory. Preserve the original numbering where possible; renumber only if gaps or collisions exist.
2. **Copy `coding-decisions-log.md`** into the package root as `DECISIONS.md` — this provides reviewers and replicators with the rationale behind every analytic choice.
3. **Use `script-index.md`** to populate the README run-order table and paper-element correspondence table (Step 3b).

This eliminates the need to reconstruct scripts from memory or scratch — all code is already saved, self-contained, and documented with decision rationale.

If `output/[slug]/scripts/` does not exist, proceed with the standard Step 3a approach below.

### 3a. Replication Package Structures

**Minimum standard** (ASR, AJS, Demography — Stata/R papers):
```
replication-[author-year]/
├── README.md                ← Software versions; data sources; run order
├── data/
│   ├── raw/                 ← Raw data files OR download instructions
│   └── analysis/            ← Processed analytic dataset (if shareable)
├── code/
│   ├── 01_clean.R           ← Data cleaning → writes analysis/analysis_data.rds
│   ├── 02_main_models.R     ← Tables 2–3
│   ├── 03_figures.R         ← All figures → output/figures/
│   └── 04_appendix.R        ← Supplementary analyses
└── output/
    ├── tables/
    └── figures/
```

**Gold standard** (NCS, Science Advances — computational papers):
```
replication-[author-year]/
├── README.md
├── LICENSE                  ← MIT (code) + CC-BY or CC0 (data)
├── CITATION.cff             ← Machine-readable citation metadata
├── Makefile                 ← Orchestrates full pipeline: make all
├── environment.yml          ← Conda environment (exact package versions)
├── renv.lock                ← R environment (if R code included)
├── Dockerfile               ← Full container (optional but valued by NCS)
├── data/
│   ├── README.md
│   ├── raw/
│   └── processed/
├── code/
│   ├── 01_data_prep.py
│   ├── 02_model_train.py
│   ├── 03_analysis.py
│   ├── 04_figures.py
│   └── utils/
├── output/
│   ├── figures/
│   ├── tables/
│   └── models/              ← Saved model weights / checkpoints
├── paper/
│   └── manuscript.tex       ← LaTeX source (if available)
└── tests/                   ← Unit tests for key functions (pytest)
```

### 3b. README Template

```markdown
# Replication Package for: [Paper Title]

## Citation
[Author(s)]. ([Year]). [Paper Title]. *[Journal]*, *[Vol]*([Issue]), [Pages].
https://doi.org/[DOI]

Replication package archived at: https://doi.org/[Zenodo DOI]

## Overview
[2–3 sentences describing what this package reproduces: which tables, figures,
and analyses from the paper.]

## Software Requirements

### R
- R version 4.3.2 (or later)
- Restore package environment: `Rscript -e "renv::restore()"`
- Key packages: fixest (0.11.2), modelsummary (1.4.5), marginaleffects (0.18.0)

### Python (if applicable)
- Python 3.11
- Install: `conda env create -f environment.yml && conda activate [env-name]`
- OR: `pip install -r requirements.txt`

### System dependencies
- [pdftotext, if used] — install via `brew install poppler` (macOS)

## Data Sources

| File | Source | Access | Notes |
|------|--------|--------|-------|
| `data/raw/gss_2022.csv` | GSS (NORC) | Download from gss.norc.org | Wave 2022 |
| `data/raw/acs_sample.rds` | ACS via tidycensus | Included (public) | 5-year 2019–2023 |
| `data/processed/analysis_data.rds` | Derived | Included | Output of 01_clean.R |

## Run Order

```bash
# Option A: Run full pipeline via Makefile
make all

# Option B: Run scripts manually in order
Rscript code/01_clean.R
Rscript code/02_main_models.R    # → output/tables/table2.tex, table3.tex
Rscript code/03_figures.R        # → output/figures/figure1.pdf – figure3.pdf
Rscript code/04_appendix.R       # → output/tables/tableA1.tex – tableA4.tex
```

## Output Files

| Script | Output | Corresponds to |
|--------|--------|----------------|
| 02_main_models.R | table2.tex, table3.tex | Tables 2–3 in paper |
| 03_figures.R | figure1.pdf, figure2.pdf | Figures 1–2 in paper |
| 04_appendix.R | tableA1.tex – tableA4.tex | Appendix Tables A1–A4 |

## Expected Runtime
Full replication: ~[X] minutes on a standard laptop ([RAM] RAM, [CPU]).
ML training step (02_model_train.py): ~[X] hours on GPU; pre-trained weights
provided in `output/models/` to skip this step.

## Random Seeds
All random seeds are set at the top of each script: `set.seed(42)` (R);
`np.random.seed(42); torch.manual_seed(42)` (Python).

## Contact
[Corresponding author name] — [email]
```

### 3c. Reproducibility Environments

#### R — renv

```r
# Initialize renv in project directory
renv::init()

# After installing all packages, snapshot:
renv::snapshot()
# → Creates renv.lock with exact package versions

# To restore on another machine:
renv::restore()
```

#### Python — Conda environment

```bash
# Create from scratch:
conda create -n paper-env python=3.11
conda activate paper-env
pip install -r requirements.txt

# Export to environment.yml:
conda env export > environment.yml
# Prune to essentials (remove build strings for portability):
conda env export --no-builds > environment.yml

# To recreate on another machine:
conda env create -f environment.yml
conda activate paper-env
```

#### Python — requirements.txt (pip only)

```bash
# Pin exact versions:
pip freeze > requirements.txt

# Install:
pip install -r requirements.txt
```

#### Makefile (pipeline orchestrator)

```makefile
# Makefile for replication pipeline

.PHONY: all data models analysis figures clean

all: figures

data: data/processed/analysis_data.rds

data/processed/analysis_data.rds: code/01_clean.R data/raw/
	Rscript code/01_clean.R

models: data/processed/analysis_data.rds
	Rscript code/02_main_models.R

figures: models
	Rscript code/03_figures.R
	Rscript code/04_appendix.R

clean:
	rm -rf output/tables/* output/figures/*
```

#### Docker (NCS gold standard)

```dockerfile
# Dockerfile
FROM rocker/tidyverse:4.3.2

# Install system dependencies
RUN apt-get update && apt-get install -y \
    libgdal-dev libproj-dev libgeos-dev \
    && rm -rf /var/lib/apt/lists/*

# Copy project
COPY . /paper

# Restore R environment
WORKDIR /paper
RUN Rscript -e "renv::restore()"

# Default command
CMD ["make", "all"]
```

```bash
# Build and run:
docker build -t paper-replication .
docker run --rm -v $(pwd)/output:/paper/output paper-replication
```

### 3d. Code Quality Standards

**Script header template** (use at top of every script):
```r
# ============================================================
# Script: 02_main_models.R
# Purpose: Estimate main OLS + FE models (Tables 2–3)
# Input:   data/processed/analysis_data.rds
# Output:  output/tables/table2.tex, output/tables/table3.tex
# Author:  [Name]
# Date:    [YYYY-MM-DD]
# Notes:   Clustered SEs at state level; AME via marginaleffects
# ============================================================

library(fixest)
library(modelsummary)
library(marginaleffects)

set.seed(42)  # For reproducibility

data <- readRDS("data/processed/analysis_data.rds")
```

**Anti-patterns to avoid**:
- Hardcoded absolute paths (`/Users/myname/Desktop/...`) — use project-relative paths
- No script-level comments
- Single 2,000-line omnibus script
- No run order documentation
- Results that require manually sourcing intermediate objects
- `rm(list=ls())` at top of script (destroys reproducibility)

### 3e. CITATION.cff

```yaml
cff-version: 1.2.0
message: "If you use this code, please cite it as below."
type: software
authors:
  - family-names: Zhang
    given-names: Yongjun
    orcid: "https://orcid.org/0000-0000-0000-0000"
    affiliation: "University Name, Department"
title: "Replication code for: [Paper Title]"
version: 1.0.0
doi: 10.5281/zenodo.XXXXXXX
date-released: 2025-01-15
url: "https://github.com/username/repository"
repository-code: "https://github.com/username/repository"
license: MIT
preferred-citation:
  type: article
  title: "[Paper Title]"
  authors:
    - family-names: Zhang
      given-names: Yongjun
  journal: "[Journal Name]"
  year: 2025
  doi: 10.XXXX/XXXXXXXXXX
```

**Add citation prompt to README**:
```markdown
## Citation

If you use this code or data, please cite the paper:

> [Author(s)]. ([Year]). [Title]. *[Journal]*. https://doi.org/[DOI]

And the replication package:

> [Author(s)]. ([Year]). *Replication code for: [Title]* (v1.0.0).
> Zenodo. https://doi.org/10.5281/zenodo.XXXXXXX
```

### 3f. Zenodo DOI via GitHub

```
Step-by-step GitHub → Zenodo integration:
1. Go to zenodo.org → Log in → "GitHub" tab
2. Toggle ON the repository you want to archive
3. On GitHub: create a Release (tag v1.0.0)
   → Releases → "Draft a new release" → Tag: v1.0.0 → Publish release
4. Zenodo auto-creates a DOI for this release (within minutes)
5. Copy DOI badge and add to README:
   [![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.XXXXXXX.svg)](...)
6. Every new Release = new Zenodo version with same concept DOI
```

---

## Step 4: FULL OPEN SCIENCE PACKAGE

Run after Steps 1–3 to assemble the complete open science package required for
journal submission (especially Nature journals).

### 4a. Data Management Plan (NSF/NIH DMP)

Required for NSF SBE proposals; increasingly expected by NIH; good practice for all.

```
═══════════════════════════════════════════════════════════════
DATA MANAGEMENT PLAN — [Project Title]
PI: [Name], [Institution], [email]
Grant Program: [NSF SBE / NIH NICHD / Unfunded academic study]
Date: [Date]
═══════════════════════════════════════════════════════════════

1. TYPES OF DATA, SAMPLES, COLLECTIONS, SOFTWARE, AND OTHER
   MATERIALS TO BE PRODUCED IN THE COURSE OF THE PROJECT

   Primary data:
   - [Dataset name]: [Brief description]. Format: CSV / SPSS / Stata .dta.
     Estimated size: [X] MB / GB. Collection period: [dates].
   - [Survey microdata / interview transcripts / scraped text corpus]: ...

   Derived data:
   - Analytic datasets (cleaned, de-identified): [format, size]
   - Model outputs (embeddings, predictions, topic distributions): [format, size]

   Software and code:
   - Analysis scripts: R / Python / Stata. Version-controlled on GitHub.
   - Configuration files: renv.lock / environment.yml

2. DATA FORMAT AND METADATA STANDARDS

   - Primary data: CSV with UTF-8 encoding; SPSS .sav for survey data
   - Metadata standard: [Dublin Core / DDI Codebook for surveys / schema.org]
   - Codebook: Variable name, label, type, range, missing code, source for
     each variable. Deposited with data.

3. POLICIES FOR ACCESS AND SHARING, REUSE, REDISTRIBUTION

   - De-identified public-use data: deposited at [Harvard Dataverse / ICPSR /
     Zenodo]; available publicly upon publication
   - Restricted data (PII / health / linked administrative): deposited at
     [ICPSR restricted] under DUA; available upon approved request
   - Social media data: tweet/post IDs deposited; raw data not redistributed
     per platform ToS
   - Code: deposited on GitHub + Zenodo under MIT license
   - Embargo period: [None / Until [date] / Until publication]

4. POLICIES AND PROVISIONS FOR RE-USE, RE-DISTRIBUTION, DERIVATIVES

   - License: CC-BY 4.0 for data; MIT for code
   - Attribution requirement: cite original paper using CITATION.cff
   - Prohibited uses: re-identification of individuals; direct commercial use
     without consent of PI

5. PLANS FOR ARCHIVING AND PRESERVING ACCESS TO DATA AND CODE

   - Repository: [Harvard Dataverse (social science data) + Zenodo (code)]
   - Preservation period: Minimum 10 years post-publication; indefinite for
     open repositories
   - Version control: Git; GitHub releases tagged at submission and publication
   - Backup: [Institutional server / cloud backup policy]
   - Format migration: CSV/TSV are open formats; no migration risk
   - DOI registration: Both datasets and code will receive persistent DOIs

6. DATA SECURITY AND PRIVACY PROTECTIONS

   - PII handling: all direct identifiers removed before analysis; ID lookup
     table stored encrypted on institutional server; not deposited
   - IRB compliance: IRB protocol [number] governs data collection;
     consent form includes data sharing language
   - Restricted data: HIPAA-compliant storage; DUA required for sharing
   - Secure storage during project: [institutional secure research storage /
     encrypted local drive]

═══════════════════════════════════════════════════════════════
```

**NSF-specific DMP notes** (SBE 2-page DMP):
- Must address: types of data; data format; metadata standards; policies for access/sharing; policies for re-use; plans for archiving
- NSF Public Access Plan (2023): NSF-funded papers must be deposited in an approved repository; data must have a DOI

**NIH-specific DMP notes** (DMSP — Data Management and Sharing Plan):
- Required for all NIH submissions since January 2023
- Must specify: data type, consent and IRB, de-identification, repository, timeline for sharing, responsible party
- NIH prefers: NIMH Data Archive; dbGaP (genetics); ICSPR; Zenodo
- Maximum 2 pages

### 4b. CRediT Authorship Table

CRediT (Contributor Roles Taxonomy) is required by NHB, NCS, and PNAS.
List all 14 roles; mark each author's contribution.

| Role | Author 1 | Author 2 | Author 3 | Author 4 |
|------|---------|---------|---------|---------|
| Conceptualization | ✓ | | ✓ | |
| Data curation | | ✓ | | |
| Formal analysis | ✓ | ✓ | | |
| Funding acquisition | ✓ | | | |
| Investigation | ✓ | ✓ | ✓ | |
| Methodology | ✓ | | | ✓ |
| Project administration | ✓ | | | |
| Resources | | | | ✓ |
| Software | | ✓ | | |
| Supervision | ✓ | | | |
| Validation | | ✓ | ✓ | |
| Visualization | | ✓ | | |
| Writing – original draft | ✓ | | | |
| Writing – review & editing | ✓ | ✓ | ✓ | ✓ |

**In-text CRediT statement template**:
```
"[Author 1]: Conceptualization, Methodology, Writing – original draft.
[Author 2]: Data curation, Formal analysis, Software, Visualization.
[Author 3]: Investigation, Validation, Writing – review & editing.
[Author 4]: Resources, Methodology support, Writing – review & editing."
```

### 4c. Conflict of Interest Declaration

```
Template 1 (No conflict):
"The authors declare no competing interests."

Template 2 (Funding conflict):
"[Author X] has received research funding from [organization] for projects
related to [topic]. This work was not funded by [organization]. The remaining
authors declare no competing interests."

Template 3 (Advisory role):
"[Author X] serves on the scientific advisory board of [organization], which
works in a domain related to this research. [Author X] was not involved in
[specific aspect]. The remaining authors declare no competing interests."

Template 4 (Equity/employment):
"[Author X] holds equity in [company] that produces products related to the
topic of this research. All analyses were conducted independently. The remaining
authors declare no competing interests."
```

### 4d. IRB Statement

```
Template 1 (IRB approved):
"All procedures were approved by the [University] Institutional Review Board
(protocol [number], approved [date]). [Participants / Subjects] provided
[written / verbal / electronic] informed consent prior to participation."

Template 2 (IRB exempt):
"The [University] Institutional Review Board determined this research to be
exempt from full review under 45 CFR 46.104(d), category [2/4]
(protocol [number])."

Template 3 (Secondary data — IRB exempt):
"This study uses publicly available secondary data with no individual
identifiers. The [University] IRB determined this research to be exempt
(protocol [number])."

Template 4 (Waived — social media public data):
"Data were collected from public social media profiles. The [University]
IRB reviewed this protocol and waived the requirement for informed consent
for publicly available data (protocol [number])."
```

### 4e. Open Access Strategy

| Scenario | Recommended action |
|----------|--------------------|
| NSF- or NIH-funded | Deposit preprint on SocArXiv/SSRN before submission; journal version goes through publisher OA after acceptance |
| Science Advances target | APC required (~$4,950); verify NSF/NIH public access compliance; APC waivers available for AAAS members + low-income affiliations |
| Nature journal (NHB/NCS) | Hybrid OA (~€9,500 APC); apply for APC waiver if low-income affiliation; check if institution has Springer Nature agreement |
| ASR/AJS/Demography target | Post preprint to SocArXiv (all allow preprints); journal version paywalled unless paying hybrid OA |
| Institutional read & publish deal | Check library portal — many universities have Springer/Elsevier/Wiley agreements that cover APCs |
| No funding for APC | SocArXiv/SSRN preprint provides open access; sufficient for most community visibility |

**Preprint server guide**:

| Server | Field | URL |
|--------|-------|-----|
| **SocArXiv** | Sociology, social science | osf.io/preprints/socarxiv |
| **SSRN** | Social science, law, economics | ssrn.com |
| **arXiv** (cs.SI, cs.CY, stat.AP) | Computational social science | arxiv.org |
| **PsyArXiv** | Psychology | psyarxiv.com |
| **EarthArXiv / ESSOAr** | Environmental / earth science | eartharxiv.org |
| **bioRxiv / medRxiv** | Biology / health | biorxiv.org |

**APC waiver procedures**:
```
Nature journals waiver:
1. Submit paper; if accepted, go to OA billing page
2. Search author institutional affiliation
3. If institution has Springer Nature deal → covered
4. If LMIC affiliation → automatic waiver option
5. If NSF/NIH funded → upload grant number; publisher checks compliance

AAAS / Science Advances:
1. After acceptance, AAAS membership number can reduce fee
2. Waivers: submit written request to oa@aaas.org before APC invoice
```

---

## Step 5: REPLICATION PACKAGE AUDIT

Run this step to verify an existing replication package meets journal standards before submission.

### 5a. Audit Checklist

**Structure** (required by all journals):
- [ ] README.md present and complete (software versions, data sources, run order, expected output)
- [ ] Scripts numbered and named descriptively (01_clean, 02_analyze, 03_figures)
- [ ] All relative paths — no hardcoded absolute paths
- [ ] Output files generated by scripts (not manually placed)
- [ ] Random seeds set and documented

**Run test** (do this before submission):
```bash
# Clone into a fresh directory and run from scratch
git clone [repo] test-replication
cd test-replication
# Restore environment
conda env create -f environment.yml  # OR: Rscript -e "renv::restore()"
# Run full pipeline
make all  # OR: run scripts in numbered order
# Check: all output files generated? All tables match paper?
```

**Data compliance**:
- [ ] No raw data with PII included
- [ ] Data availability statement matches what is actually deposited
- [ ] License file present
- [ ] CITATION.cff present

**Script archive integration** (if `output/[slug]/scripts/` was produced by scholar-analyze/compute/full-paper):
- [ ] Scripts from `output/[slug]/scripts/` incorporated into `code/` directory (not reconstructed from scratch)
- [ ] `DECISIONS.md` present in package root (copied from `coding-decisions-log.md`)
- [ ] All scripts have standard headers (purpose, input, output, date, seed)
- [ ] Script-index run-order table used to populate README

**Computational papers (NCS/Science Advances extras)**:
- [ ] environment.yml or renv.lock with pinned versions
- [ ] Docker file or documented container (for NCS)
- [ ] Model weights archived (Zenodo or HuggingFace Hub)
- [ ] Reporting Summary completed (NHB/NCS requirement)
- [ ] All figure error bars labeled with SE/SD/CI in caption

**Journal-specific extras**:

| Journal | Extra requirements |
|---------|-------------------|
| NCS | Docker; Reporting Summary; code ocean or GitHub; FAIR data statement |
| NHB | Ethics statement; ORCID for all authors; Reporting Summary |
| Science Advances | AAAS OA compliance; full methods + supplementary |
| ASR | AEA/AEJ-style data availability form (emerging) |
| Demography | Population Association data sharing policy |

---

## Step 6: Save Output

Use the Write tool to save three files:

```bash
# Determine output slug and date
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
SLUG=$(echo "$ARGUMENTS" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | cut -c1-40)
DATE=$(date +%Y-%m-%d)
mkdir -p "${OUTPUT_ROOT}/" "${OUTPUT_ROOT}/logs"
```

**Process Logging (REQUIRED):**

Initialize the process log NOW by running:

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
mkdir -p "${OUTPUT_ROOT}/logs"
SKILL_NAME="scholar-open"
LOG_DATE=$(date +%Y-%m-%d)
LOG_FILE="${OUTPUT_ROOT}/logs/process-log-${SKILL_NAME}-${LOG_DATE}.md"
if [ -f "$LOG_FILE" ]; then
  CTR=2; while [ -f "${OUTPUT_ROOT}/logs/process-log-${SKILL_NAME}-${LOG_DATE}-${CTR}.md" ]; do CTR=$((CTR+1)); done
  LOG_FILE="${OUTPUT_ROOT}/logs/process-log-${SKILL_NAME}-${LOG_DATE}-${CTR}.md"
fi
cat > "$LOG_FILE" << LOGHEADER
# Process Log: /${SKILL_NAME}
- **Date**: ${LOG_DATE}
- **Time started**: $(date +%H:%M:%S)
- **Arguments**: [raw arguments]
- **Working Directory**: $(pwd)

## Steps

| # | Timestamp | Step | Action | Output | Status |
|---|-----------|------|--------|--------|--------|
LOGHEADER
echo "Process log initialized: $LOG_FILE"
```

**After EVERY numbered step**, append a row by running:

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
SKILL_NAME="scholar-open"
LOG_DATE=$(date +%Y-%m-%d)
LOG_FILE="${OUTPUT_ROOT}/logs/process-log-${SKILL_NAME}-${LOG_DATE}.md"
if [ ! -f "$LOG_FILE" ]; then
  LOG_FILE=$(ls -t "${OUTPUT_ROOT}"/logs/process-log-${SKILL_NAME}-${LOG_DATE}*.md 2>/dev/null | head -1)
fi
echo "| [step#] | $(date +%H:%M:%S) | [Step Name] | [1-line action summary] | [output files or —] | ✓ |" >> "$LOG_FILE"
```

**IMPORTANT:** Shell variables do NOT persist across Bash tool calls. Every step MUST re-derive LOG_FILE before appending.

### Version Collision Avoidance (MANDATORY)

**Before EVERY Write tool call below**, run this Bash block to determine the correct save path. Do NOT hardcode paths from the filename templates — they show naming patterns only.

```bash
# MANDATORY: Replace [slug] and [YYYY-MM-DD] with actuals before running
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
# BASE pattern: ${OUTPUT_ROOT}/[slug]/preregistration-[slug]-[YYYY-MM-DD]
OUTDIR="$(dirname "${OUTPUT_ROOT}/[slug]/preregistration-[slug]-[YYYY-MM-DD]")"
STEM="$(basename "${OUTPUT_ROOT}/[slug]/preregistration-[slug]-[YYYY-MM-DD]")"
mkdir -p "$OUTDIR"
bash "${SCHOLAR_SKILL_DIR:-.}/scripts/gates/version-check.sh" "$OUTDIR" "$STEM"

mkdir -p "$(dirname "$BASE")"


echo "SAVE_PATH=${BASE}.md"
echo "BASE=${BASE}"
```

**Use the printed `SAVE_PATH` as `file_path` in the Write tool call.** Re-run this block (with the appropriate BASE) for each additional file. The same version suffix must be used for all related output files (.md, .docx, .tex, .pdf).

**File 1** — Preregistration document (if PREREGISTER mode):
```
Write tool → output/[slug]/preregistration-[SLUG]-[DATE].md
Contents: Complete preregistration document from Step 1d / 1e
```

**File 2** — Data Management Plan (if FULL-PACKAGE or DMP mode):
```
Write tool → output/[slug]/dmp-[SLUG]-[DATE].md
Contents: Completed DMP template from Step 4a
```

**File 3** — Replication Package README:
```
Write tool → output/[slug]/replication-readme-[SLUG]-[DATE].md
Contents: README.md template from Step 3b, filled in for this specific project
```

**Close Process Log:**

Run the following to finalize the process log:

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
SKILL_NAME="scholar-open"
LOG_DATE=$(date +%Y-%m-%d)
LOG_FILE="${OUTPUT_ROOT}/logs/process-log-${SKILL_NAME}-${LOG_DATE}.md"
if [ ! -f "$LOG_FILE" ]; then
  LOG_FILE=$(ls -t "${OUTPUT_ROOT}"/logs/process-log-${SKILL_NAME}-${LOG_DATE}*.md 2>/dev/null | head -1)
fi
cat >> "$LOG_FILE" << LOGFOOTER

## Output Files
[list each output file path as a bullet]

## Summary
- **Steps completed**: [N completed]/[N total]
- **Files produced**: [count]
- **Errors**: [count, or 0]
- **Time finished**: $(date +%H:%M:%S)
LOGFOOTER
echo "Process log saved to $LOG_FILE"
```

After saving, print:
```
════════════════════════════════════════════════════════
 SCHOLAR-OPEN: Output saved
 ├─ output/[slug]/preregistration-[slug]-[date].md
 ├─ output/[slug]/dmp-[slug]-[date].md
 └─ output/[slug]/replication-readme-[slug]-[date].md
════════════════════════════════════════════════════════
```

---

## Quality Checklist (18 items)

### Before Data Collection
- [ ] **Preregistration**: Study preregistered on OSF / AsPredicted / EGAP with directional hypotheses and exact analysis plan; OR non-preregistration statement prepared
- [ ] **Registered Reports** (if applicable): Stage 1 submitted; In-Principle Acceptance obtained; OSF registration locked
- [ ] **IRB approval**: Protocol approved / exempt determination obtained; consent form includes data sharing language
- [ ] **DMP written**: NSF/NIH DMP completed (if funded) or internal DMP for data governance
- [ ] **Pre-analysis plan**: Hypothesis, estimator, SE type, covariates, exclusions, and exploratory analyses pre-specified

### Data Sharing
- [ ] **FAIR compliance**: Dataset deposited with DOI; open format (CSV/TSV); codebook attached; license specified (CC-BY / CC0)
- [ ] **De-identification**: All 18 HIPAA identifiers removed; k-anonymity (k≥5) verified with sdcMicro
- [ ] **Repository**: Data deposited at Harvard Dataverse / ICPSR / Zenodo / QDR as appropriate for data type
- [ ] **Platform policies**: Social media data — raw not distributed; IDs or derived features only; platform ToS reviewed
- [ ] **Computational artifacts**: Model weights / embeddings / annotation labels archived at Zenodo or HuggingFace Hub

### Code & Reproducibility
- [ ] **Replication package structure**: Numbered scripts, README, output/, data/ with README
- [ ] **Environment pinned**: renv.lock (R) or environment.yml (Python) with exact package versions
- [ ] **Seeds documented**: All random seeds set and noted in scripts and README
- [ ] **Clean-run verified**: Package runs from scratch in fresh environment; all output files regenerated
- [ ] **CITATION.cff**: Present; includes paper DOI and package DOI

### In the Manuscript
- [ ] **Preregistration citation**: OSF URL + registration date in Methods section
- [ ] **Data availability statement**: Matches actual repository; includes DOI
- [ ] **Code availability statement**: GitHub URL + Zenodo DOI; includes version tag
- [ ] **Confirmatory vs. exploratory labeled**: All non-preregistered analyses explicitly marked "exploratory"
- [ ] **CRediT statement**: All 14 roles assigned (required by NHB, NCS, PNAS)
- [ ] **COI declaration**: "No competing interests" or specific conflicts named
- [ ] **Preprint posted**: SocArXiv / SSRN / arXiv preprint linked in cover letter

See `references/preregistration.md` for preregistration templates and platform comparisons.
See `references/data-sharing.md` for FAIR implementation, de-identification code, and repository setup.
