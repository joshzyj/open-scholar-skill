# MODE 8: REPORTING-SUMMARY — NHB/NCS Reporting Summary Generation

**Input:** Draft manuscript (or structured metadata about the study: design, statistics, data sources)

**Purpose:** Generate a pre-filled Reporting Summary for Nature Human Behaviour (NHB) or Nature Computational Science (NCS). These journals require a structured checklist covering study design, statistical methods, data and code availability, and ethical compliance. This mode parses the manuscript to auto-fill as many fields as possible, flagging gaps for the author.

## Step RS-1: Detect Target Journal

If not specified, infer from manuscript metadata or ask. NHB and NCS use slightly different templates:
- **NHB**: Life Sciences Reporting Summary + Behavioural & Social Sciences addendum
- **NCS**: Life Sciences Reporting Summary + Computational Science addendum

## Step RS-2: Parse Manuscript for Key Metadata

Extract from the manuscript (or prompt the user for missing items):

| Field | Source in Manuscript |
|-------|---------------------|
| Study design | Methods section: experimental, observational, computational, mixed |
| Sample size | Methods: N participants, N observations, N texts/documents |
| Sample size justification | Methods: power analysis, full population, saturation |
| Data exclusions | Methods: exclusion criteria, missing data handling |
| Replication | Methods/Results: internal replication, robustness checks |
| Randomization | Methods: random assignment, stratification |
| Blinding | Methods: blinding of coders, analysts |
| Statistical tests | Results: test names, software, version |
| Effect sizes | Results: coefficients, CIs, Cohen's d, AME |
| Multiple comparisons | Results: correction method (Bonferroni, FDR, etc.) |
| Bayesian analysis | Results: priors, MCMC diagnostics, Bayes factors |
| Data availability | Data availability statement, repository, DOI |
| Code availability | Code availability statement, repository, DOI |
| Ethics | IRB approval number, informed consent, ethical review |

## Step RS-3: Generate NHB Reporting Summary

```markdown
# Nature Human Behaviour — Reporting Summary

## Study Design

### 1. Study type
- [ ] Observational — cross-sectional
- [ ] Observational — longitudinal / panel
- [ ] Experimental — randomized
- [ ] Experimental — quasi-experimental
- [ ] Computational / simulation
- [ ] Mixed methods
- [ ] Secondary data analysis
- [ ] Systematic review / meta-analysis

**Description:** [AUTO-FILLED from manuscript or USER INPUT NEEDED]

### 2. Sample size
- **N:** [AUTO-FILLED or USER INPUT NEEDED]
- **Justification:** [power analysis details / full population / theoretical saturation]
- **Power analysis:** [tool, parameters, target power, minimum detectable effect]

### 3. Data exclusions
- **Exclusion criteria:** [AUTO-FILLED from Methods]
- **N excluded:** [AUTO-FILLED or USER INPUT NEEDED]
- **Pre-registered:** [Yes — link / No]

### 4. Replication
- **Internal replication:** [Yes — describe / No]
- **Robustness checks:** [list from Results section]

### 5. Randomization
- **Applied:** [Yes — method / No / N/A (observational)]
- **Stratification variables:** [if applicable]

### 6. Blinding
- **Data collection:** [Yes — describe / No / N/A]
- **Data analysis:** [Yes — describe / No]
- **Outcome assessment:** [Yes — describe / No / N/A]

---

## Statistical Analysis

### 7. Statistical tests
| Test | Variables | Software | Version |
|------|-----------|----------|---------|
| [AUTO-FILLED from Results] | | | |

### 8. Effect sizes and confidence intervals
- **Reported:** [Yes / No — USER INPUT NEEDED]
- **Type:** [AME, Cohen's d, odds ratio, correlation, etc.]
- **Confidence level:** [95% CI / other]

### 9. Multiple comparisons
- **Applicable:** [Yes / No]
- **Correction method:** [Bonferroni / FDR / Holm / None — justify]
- **Number of tests:** [N]

### 10. Bayesian analysis (if applicable)
- **Priors:** [informative / weakly informative / flat — specify]
- **MCMC diagnostics:** [R-hat, ESS, trace plots]
- **Software:** [Stan / JAGS / brms — version]

---

## Data and Code Availability

### 11. Data availability
- **Statement:** [AUTO-FILLED from Data Availability section]
- **Repository:** [Harvard Dataverse / ICPSR / Zenodo / OSF / other]
- **DOI / URL:** [AUTO-FILLED or USER INPUT NEEDED]
- **Access restrictions:** [public / restricted — reason]
- **De-identification:** [method applied]

### 12. Code availability
- **Statement:** [AUTO-FILLED from Code Availability section]
- **Repository:** [GitHub / Zenodo / CodeOcean / other]
- **DOI / URL:** [AUTO-FILLED or USER INPUT NEEDED]
- **Language and version:** [R x.x.x / Python x.x / Stata xx]

---

## Ethics

### 13. Ethical approval
- **IRB / Ethics board:** [name and approval number]
- **Informed consent:** [obtained / waived — reason]
- **Data protection:** [GDPR compliance / anonymization method]

### 14. AI tool use disclosure
- **AI tools used:** [list tools, e.g., Claude Code for analysis scripts]
- **Role of AI:** [code generation / text editing / analysis — specify]
- **Human oversight:** [all AI outputs reviewed and validated by authors]

---

## NCS Addendum (Nature Computational Science only)

### 15. Computational methodology
- **Algorithm / model:** [name, version, reference]
- **Training data:** [source, size, preprocessing]
- **Validation strategy:** [cross-validation, held-out test set, external validation]
- **Hyperparameter selection:** [method: grid search, Bayesian optimization, etc.]
- **Computational resources:** [hardware, runtime, carbon footprint estimate]

### 16. Reproducibility
- **Random seeds:** [set and reported / not applicable]
- **Deterministic execution:** [Yes / No — describe sources of non-determinism]
- **Docker / container:** [provided / not provided]
- **Replication package:** [DOI / URL — link to scholar-replication output]
```

## Step RS-4: Gap Analysis

After auto-filling, scan for remaining `USER INPUT NEEDED` fields and produce a checklist:

```markdown
## Gaps Requiring Author Input

- [ ] [Field name] — [what is needed]
- [ ] [Field name] — [what is needed]
...
```

## Step RS-5: Save Reporting Summary

Path: `output/[slug]/citations/scholar-citation-[slug]-[date]-reporting-summary.md`

Also save a companion gap-analysis file if gaps remain:
Path: `output/[slug]/citations/scholar-citation-[slug]-[date]-reporting-gaps.md`
