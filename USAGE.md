# Open Scholar Skill — User Guide

A Claude Code project for social scientists writing for top-tier journals.
23 skills + 1 utility covering the full research pipeline from idea exploration to collaboration.

---

## Structure

Skills and agents live in the `.claude/` directory:

```
open-scholar-skill/
├── .claude/
│   ├── skills/           ← 23 skills (scholar-*) + 1 utility (sync-docs)
│   ├── agents/           ← 9 reviewer agents (peer-reviewer-*) + 4 verification agents (verify-*)
│   └── settings.local.json
├── README.md
└── USAGE.md
```

All 24 skills are available in any Claude Code session via `/skill-name` when working in this project directory.

---

## How to Invoke a Skill

Type the slash command followed by your argument:

```
/scholar-idea why do low-income neighborhoods have lower preventive care uptake
/scholar-lit-review residential segregation and health outcomes
/scholar-write introduction on racial disparities in school discipline for ASR
/scholar-citation insert ASA citations and build reference list for my draft
/scholar-journal prepare manuscript for Nature Human Behaviour
```

The text after the skill name is passed directly as context. The more specific the argument, the better the output.

---

## Skill Reference

| Skill | When to use | Example argument |
|-------|-------------|-----------------|
| `/scholar-idea` | Turn a broad topic into formal RQs | `why does AI exposure affect worker precarity` |
| `/scholar-brainstorm` | Generate RQs from codebooks, questionnaires, or datasets | `path/to/gss-codebook.pdf sociology, inequality` |
| `/scholar-lit-review-hypothesis` | Literature review + theory + hypotheses in one pass | `redlining and activity space segregation for AJS` |
| `/scholar-lit-review` | Literature review only (use when you want search/synthesis without theory) | `residential segregation and health` |
| `/scholar-hypothesis` | Theory + hypotheses only (use when lit review is already done) | `why does segregation affect health` |
| `/scholar-design` | After hypotheses | `causal ID for segregation-health panel` |
| `/scholar-causal` | Before analysis | `segregation → health; DiD or FE; SES confounder` |
| `/scholar-data` | Find datasets (100+ sources), collect new data, auto-fetch | `find dataset for immigration and earnings` |
| `/scholar-eda` | Before modeling | `pre-analysis for panel dataset` |
| `/scholar-analyze` | Run analyses, produce tables/figures, write results | `data.csv, OLS of earnings on education by race for Demography` |
| `/scholar-compute` | NLP / ML / networks | `STM topic model on news corpus` |
| `/scholar-write` | Drafting sections | `introduction on segregation and health for ASR` |
| `/scholar-citation` | Citations and references | `insert ASA citations and build reference list` |
| `/scholar-journal` | Submission prep | `prepare manuscript for Demography` |
| `/scholar-open` | Preregistration / data sharing | `preregistration for FE panel study` |
| `/scholar-replication` | Build & test replication package | `full for Demography` |
| `/scholar-respond` | Review simulation / R&R | `simulate paper.pdf for Demography` |
| `/scholar-qual` | Qualitative coding and analysis | `open-coding transcripts/*.txt grounded theory` |
| `/scholar-collaborate` | Multi-author collaboration management | `credit 4-author paper on immigrant integration` |
| `/scholar-ling` | Sociolinguistics work | `variationist analysis of t-deletion` |
| `/scholar-ethics` | Research ethics compliance | `pre-submission ethics check for Demography` |
| `/scholar-safety` | Real-time data privacy protection | `scan data.csv before analysis` |
| `/scholar-verify` | Verify analysis-to-manuscript consistency | `full output/drafts/full-paper-2026-03-10.md` |
| `/scholar-auto-improve` | Post-skill quality audit | `observe output/drafts/` |
| `/sync-docs` | Synchronize slides, script, and manuscript | `slides.tex script.tex manuscript.tex` |

---

## Full Research Workflow (Modular)

Use these skills individually when you want to run a single phase, iterate on a specific
section, or pick up the pipeline at a particular step.

---

### 0. Idea Exploration — `/scholar-idea`

```
/scholar-idea why does remote work change neighborhood ties and political participation
/scholar-idea AI automation and occupational mobility in low-wage service work
/scholar-idea intersectionality of immigration status and gender on wage penalties
```

Use this when you have a broad topic but need a publication-ready research question.
It generates 3–5 research angles, formalizes RQ1–RQ3 with explicit population/context/mechanism
structure, derives H1–H2 per question, runs a feasibility and novelty screen (High/Medium/Low),
and recommends the single best question with next-step skill invocations.

**Output format:**
1. `IDEA DIAGNOSIS` — what is promising vs. underspecified
2. `CANDIDATE RESEARCH ANGLES` — 3–5 with mechanism and rival explanation
3. `FORMAL RESEARCH QUESTIONS` — RQ1–RQ3
4. `HYPOTHESES` — H1–H2 per RQ
5. `FEASIBILITY + NOVELTY MATRIX`
6. `RECOMMENDED QUESTION` + why
7. `NEXT COMMANDS` — exact skill invocations to continue

---

### 0b. Data-Driven Brainstorming — `/scholar-brainstorm`

```
/scholar-brainstorm path/to/gss-codebook.pdf sociology, inequality
/scholar-brainstorm path/to/survey-data.csv health disparities for Demography
/scholar-brainstorm path/to/questionnaire.pdf immigration, labor market
```

Use this when you have existing materials — a codebook, survey questionnaire, or dataset — and
want to discover what publishable research questions the data can support. Works in two modes:

- **DATA mode** (auto-detected from `.csv`, `.dta`, `.rds`, `.parquet`, etc.): Runs a safety scan
  first (via `scholar-safety`), then explores variable distributions, cross-tabulations, and
  empirical signal tests to find promising patterns before proposing questions.
- **MATERIALS mode** (auto-detected from `.pdf`, `.docx`, `.md`): Reads codebooks or questionnaires
  and proposes theory-driven questions based on available measures, without touching actual data.

**Output format:**
1. `DATA LANDSCAPE` — inventory of variables, measures, and coverage
2. `EMPIRICAL SIGNALS` (DATA mode only) — cross-tabs, correlations, and patterns worth investigating
3. `TOP 10 RESEARCH QUESTIONS` — ranked by publishability, with mechanism, population, feasibility
4. `5-AGENT EVALUATION PANEL` — Theorist, Methodologist, Domain Expert, Journal Editor, Devil's Advocate score each RQ
5. `CONSENSUS RANKING` — final ordered list with recommended next skills

**When to use this vs. `/scholar-idea`:**
- `/scholar-idea` — you have a broad topic or puzzle but no specific data
- `/scholar-brainstorm` — you have data or materials and want to discover what questions they can answer

---

### 1. Literature Review — `/scholar-lit-review`

```
/scholar-lit-review residential segregation and cardiovascular health
/scholar-lit-review AI labor displacement and occupational mobility
```

Queries your **Zotero library** first (see [Zotero Integration](#zotero-integration)),
then searches the web to fill gaps. Produces:
- Theoretical landscape (2–4 paragraphs mapping dominant frameworks)
- Empirical state of knowledge (3–6 paragraphs)
- Research gaps (bulleted list + narrative)
- Draft literature review section ready to paste (ASR/AJS: 1,500–2,500 words; Demography: 1,000–2,000)

---

### 2. Theory and Hypotheses — `/scholar-hypothesis`

```
/scholar-hypothesis why does residential segregation affect cardiovascular health
/scholar-hypothesis intersectionality of race and gender in political donations
```

Selects a theoretical framework (stress process, cumulative disadvantage, social capital,
intersectionality, etc.), specifies the X → M → Y mechanism, and derives numbered hypotheses
(H1, H2, H3) formatted for direct use in the paper.

For intersectionality: applies the multiplicative specification (β₃ interaction term) and
generates explicit hypothesis language for both additive and intersectional effects.

---

### 3. Research Design — `/scholar-design`

```
/scholar-design causal identification for segregation-health link using panel data
/scholar-design conjoint experiment on racial bias in hiring decisions
```

Recommends identification strategy (FE, DiD, IV, RD, experiment), runs a power analysis
(R `pwr` package syntax included), specifies the analytic model, and flags required
robustness checks.

---

### 4. Causal Inference — `/scholar-causal`

```
/scholar-causal segregation → health; DiD design; SES confounder
/scholar-causal education → earnings; IV using distance to college; ability confounder
/scholar-causal minimum wage → employment; staggered DiD; Callaway-Sant'Anna
/scholar-causal policy adoption → outcomes; synthetic control; single treated state
/scholar-causal income → health; causal mediation via stress; ACME decomposition
```

Provides the full causal inference toolkit in one skill:
1. **DAG** — draws textual DAG, identifies backdoor paths, specifies minimal adjustment set
2. **Strategy selection** — 8-strategy decision tree (OLS, DiD, RD, IV, FE, matching, synthetic control, mediation)
3. **Deep-dives** — for the selected strategy: assumptions, standard workflow, diagnostics, R code, Stata code, write-up template, common pitfalls
4. **Sensitivity analysis** — Oster delta, E-values, Rosenbaum bounds, placebo tests, ρ* for mediation
5. **Identification argument** — ready-to-paste Methods paragraph

---

### 5. Data Collection & Open Data Directory — `/scholar-data`

```
/scholar-data find dataset for immigration and labor market outcomes
/scholar-data dataset for cross-national attitudes toward democracy
/scholar-data design a survey on neighborhood stress and health for NHANES sample
/scholar-data interview protocol for undocumented immigrants and labor market experiences
```

**Open data directory** with 100+ datasets across 14 categories: sociology/stratification,
demography/health, education, political behavior, immigration/ethnicity, neighborhoods/spatial,
text/digital/computational, crime/justice, international/cross-national surveys (ESS, WVS,
Afrobarometer, Eurobarometer, DHS, PISA), economic/labor/macro (FRED, OECD, Eurostat, Penn
World Table), global health/environment (WHO, GBD, FAOSTAT), science of science/bibliometrics
(OpenAlex, Semantic Scholar, Crossref), and 14 general-purpose repositories (Harvard Dataverse,
ICPSR, Zenodo, OSF, Figshare, Data.gov, Kaggle, Google Dataset Search).

**Auto-fetch**: for 25+ no-API-key sources, the skill downloads data directly into `data/raw/`
using R packages (`gssr`, `tidycensus`, `WDI`, `eurostat`, `openalexR`, `essurvey`, `dataverse`)
or Python (REST APIs for OpenAlex, WHO GHO, Eurostat, Zenodo, Harvard Dataverse).

Also generates survey instruments, interview protocols, codebook templates, IRB checklists
(exempt / expedited / full review determination), data management plans, web scraping pipelines,
and cleaning code in R or Stata.

---

### 6. Exploratory Data Analysis — `/scholar-eda`

```
/scholar-eda run pre-analysis on panel dataset before modeling
/scholar-eda missing data diagnosis for NLSY97 with 20% attrition
```

Guides missing data diagnosis (MCAR/MAR/MNAR tests; `mice` recommendation for MAR),
distribution checks, outlier detection, collinearity screening, and produces a
pre-analysis plan memo to lock analytical decisions before running main models.

---

### 7. Data Analysis — `/scholar-analyze`

```
# With dataset path + model specification
/scholar-analyze data.csv, OLS of earnings on education by race for Demography
/scholar-analyze nhanes_panel.dta, fixed effects model of activity space on BMI for ASR
/scholar-analyze survey.csv, logit of political participation on neighborhood SES by gender for AJS
/scholar-analyze nlsy.rds, Oaxaca-Blinder decomposition of racial wage gap for Demography
```

**Three input modes:**
- **File path**: `data.csv`, `panel.dta`, `clean.rds`
- **Inline/pasted data**: paste CSV rows or a variable summary directly — the skill writes a temp file and loads it
- **Online source**: name a public dataset and the skill fetches it automatically (NHANES, ACS/Census, GSS, World Bank, FRED, IPUMS extract, raw GitHub/OSF URL)

**Causal design gate**: if the argument includes a causal design (DiD, FE, RD, IV, matching, mediation), the skill **pauses and invokes `/scholar-causal` first** to confirm the DAG and identification strategy before running any models.

**What it produces (saved to disk):**
- `output/tables/table1-descriptives.html/.tex/.docx` — gtsummary descriptives table
- `output/tables/table2-regression.html/.tex/.docx` — modelsummary regression table
- `output/tables/table2-ame.html/.tex/.docx` — average marginal effects (for logit)
- `output/tables/tableA1-robustness.html/.tex/.docx` — robustness checks
- `output/figures/fig-dist-outcome.pdf/.png` — outcome distribution
- `output/figures/fig-coef-plot.pdf/.png` — coefficient forest plot
- `output/figures/fig-ame-[x].pdf/.png` — marginal effects plot (for logit)
- `scholar-analyze-[topic]-[date].md` — analytic summary + results draft

**Capabilities:**
- **Component A — Analytics**: OLS (HC3 SEs), panel FE (`fixest`), logit/probit + AME (`marginaleffects`), ordered logit, multilevel (`lme4`), survival (Cox PH), negative binomial; full diagnostics; Oster (2019) sensitivity; Oaxaca-Blinder decomposition
- **Component B — Visualization**: distribution, violin+box, coefficient/forest plot, marginal effects, predicted probabilities, event study (DiD), RD plot, love plot (matching), Kaplan-Meier; all saved as PDF + PNG at 300 DPI using `theme_Publication()`
- **Component C — Results writing**: journal-calibrated prose templates (AME language for ASR/AJS, 95% CI for NHB, decomposition language for Demography); journal-specific length norms

---

### 8. Computational Methods — `/scholar-compute`

```
/scholar-compute run STM topic model on news corpus about neighborhood conditions
/scholar-compute Double ML for heterogeneous treatment effects in mobility study
/scholar-compute ERGM for friendship network in high school panel
```

10 modules: NLP (STM, BERTopic, Wordfish/Wordscores, BERT, conText embedding regression, LLM annotation with DSL bias-correction), ML (Double ML, Causal Forests, Bayesian with brms/Stan), Networks (ERGM, SAOM, goldfish REM), ABM (Mesa, NetLogo/nlrx, LLM-powered agents), Reproducibility (renv, Docker, Makefile), Computer Vision (DINOv2, CLIP, ConvNeXt, multimodal LLM), LLM-Powered Analysis (Pydantic extraction, CoT coding, RAG), Synthetic Data (silicon sampling, persona simulation), Geospatial/Spatial (sf, tidycensus, spdep, Moran's I, LISA, spatial models), Audio as Data (Whisper, pyannote, Essentia, audio LLM).

---

### 9. Writing — `/scholar-write`

```
/scholar-write introduction on segregation and health for ASR
/scholar-write theory section linking stress process to cardiovascular outcomes
/scholar-write methods section for fixed effects panel design
/scholar-write discussion for Demography paper on mobility-based segregation
/scholar-write abstract for Science Advances structured format
```

Before drafting, automatically:
1. Reads `assets/index.md` and selects your closest matching published paper as a **voice reference**
   (e.g., your own *Demography* paper for spatial + health papers)
2. Reads a top-journal article for **structural depth reference**
   (e.g., a recent *AJS* paper for segregation papers)
3. Queries **Zotero** for relevant citations to use in the draft

Sections available: Introduction, Literature Review, Theory, Data & Methods, Results,
Discussion/Conclusion, Abstract. Each section is delivered as publication-ready prose
with word count and journal-specific formatting notes.

**Citation integrity:** scholar-write enforces a zero-tolerance rule for citation fabrication. Every citation inserted must be verified via Zotero/CrossRef or carried from prior pipeline phases. Unverifiable citations are flagged as `[CITATION NEEDED]` for follow-up with `/scholar-citation`.

---

### 9B. Verification — `/scholar-verify`

```
/scholar-verify full output/drafts/full-paper-2026-03-10.md
/scholar-verify stage1
/scholar-verify numerics
/scholar-verify logic
```

Two-stage consistency check between raw analysis outputs and the manuscript, using 4 specialized agents:

**Stage 1 — Raw Outputs → Manuscript Tables/Figures:**
- **verify-numerics**: Cell-by-cell comparison of raw CSVs/HTML tables against manuscript tables (transcription errors, rounding, dropped rows)
- **verify-figures**: Raw figure files vs. manuscript captions and descriptions (stale figures, caption mismatches)

**Stage 2 — Manuscript Tables/Figures → Prose Text:**
- **verify-logic**: Every statistical claim in prose traced back to a table/figure (misquoted numbers, significance errors, causal language overreach)
- **verify-completeness**: Full artifact chain integrity (orphaned/missing items, numbering, cross-references)

**Modes:** `full` (all 4 agents), `stage1`, `stage2`, `numerics`, `figures`, `logic`, `completeness`

**Output:**
- Consolidated verification report with severity-ranked issues (CRITICAL / WARNING / INFO)
- Fix checklist with exact locations and correction instructions
- ★★ markers for issues flagged by 2+ agents (highest confidence)
- Verdict: READY FOR SUBMISSION / REVISIONS NEEDED / MAJOR ISSUES — DO NOT SUBMIT

**Integration with other skills:**
- Runs automatically as Step 5b in `/scholar-write` (stage2, conditional on raw outputs existing)
- Runs as Step 3b in `/scholar-respond` REVISE mode (full, after R&R revisions)
- Runs as Step 6b item 6 in `/scholar-journal` (full, pre-submission gate)
- Recommended after `/scholar-analyze` (stage1, to catch output issues early)
- Consumed by `/scholar-replication` (verification checklist items)

---

### 10. Citation Management — `/scholar-citation`

```
/scholar-citation insert ASA citations and build reference list for my draft
/scholar-citation audit manuscript for orphan citations and missing references
/scholar-citation convert reference list from APA to ASA author-date style
```

#### ABSOLUTE RULE: Never fabricate citations

Every reference must be verified to exist via the 7-tier verification hierarchy (Zotero → CrossRef → Semantic Scholar → OpenAlex → Google Scholar → WebSearch) before inclusion. If a source cannot be verified, it is flagged as `[SOURCE NEEDED]` — never inserted as if real. This applies across all six modes.

#### Five modes

**`insert`** — for a manuscript that has claims but no citations yet:
1. Searches Zotero library for verified bibliographic metadata matching each claim
2. Falls back to CrossRef API for items not in Zotero
3. Inserts style-correct in-text citations throughout the text
4. Builds a complete reference list (every in-text citation → reference entry; no orphans)
5. Flags any claim without a verifiable source as `[SOURCE NEEDED: describe evidence type]`

**`audit`** — for a manuscript with existing citations that needs a consistency check:
1. Verifies every in-text citation appears in the reference list
2. Verifies every reference entry is cited in the text
3. Checks author name spelling consistency across text and list
4. Flags same-author same-year ambiguities needing `2020a`/`2020b` disambiguation
5. Cross-checks publication years in parenthetical citations against the reference list
6. Returns a citation audit log with all mismatches

**`convert-style`** — for a manuscript whose citations need reformatting:
1. Detects the current citation style
2. Converts all in-text citations and the full reference list to the target style
3. Handles ASA ↔ APA ↔ Chicago author-date ↔ numbered (for Science/Nature journals)

**`full-rebuild`** — end-to-end citation pipeline (runs all modes in sequence):
1. Audits existing citations → inventories claims → searches Zotero + CrossRef → inserts citations → assembles reference list → **verifies all references** → runs final audit
2. Saves two files: citation-complete draft + audit log with verification results

**`verify`** — systematic verification of every reference against databases:
1. Extracts all references into a structured inventory
2. **Tier 1 — Local Library:** checks each reference against your local Zotero library, Mendeley, BibTeX, or EndNote
3. **Tier 2a — CrossRef:** checks unmatched references via CrossRef API (by DOI or title+author)
4. **Tier 2b — Semantic Scholar:** checks remaining references via Semantic Scholar API (preprints, working papers, citation graphs)
5. **Tier 2c — OpenAlex:** checks remaining references via OpenAlex API (open metadata, 250M+ works)
6. **Tier 3 — WebSearch:** checks remaining references via web search (books, reports, preprints)
7. Assigns status per entry: `VERIFIED-LOCAL` / `VERIFIED-CROSSREF` / `VERIFIED-S2` / `VERIFIED-OPENALEX` / `VERIFIED-WEB` / `CORRECTED` / `UNVERIFIED`
8. Corrects metadata (year, volume, pages, DOI) from authoritative sources where discrepancies found
9. **Removes or flags UNVERIFIED references** — never silently includes them
10. Produces a verification report with per-entry status and all queries run
11. Optional `verify-claims` flag: checks PDF content to confirm cited sources support specific claims

**`export`** — generate BibTeX `.bib` file from a reference list:
1. Parses reference list into structured fields
2. Maps each reference to BibTeX entry types (`@article`, `@book`, `@incollection`, etc.)
3. Generates cite keys (AuthorYear format with disambiguation)
4. Enriches metadata from Zotero/CrossRef (DOI, abstract, keywords)
5. Saves `.bib` file to `output/citations/`

#### Supported citation styles

| Journal family | Style |
|---------------|-------|
| ASR, AJS, Demography, Social Forces | ASA author-date |
| Sociological Quarterly, SSR | ASA author-date |
| APSR, AJPS | APSA (author-date; "ed." for chapters; DOI as full URL) |
| Language in Society, J. Sociolinguistics | Unified Linguistics (lowercase titles; no DOI required) |
| PNAS | Author-date (NAS style) |
| Science Advances | Numbered superscript |
| Nature Human Behaviour, Nature Comp. Science | Numbered superscript |
| American Journal of Public Health | Vancouver numbered |

#### Output files

Saves 2–3 files to `output/citations/` (+ optional `.bib` in EXPORT mode):
- `scholar-citation-[slug]-[date]-draft.md` — citation-complete text + full reference list
- `scholar-citation-[slug]-[date]-log.md` — audit log with Zotero/CrossRef queries, verification results, SOURCE NEEDED items
- `scholar-citation-[slug]-[date]-verification.md` — (MODE 5 standalone) per-entry verification status + metadata corrections

---

### 11. Journal Formatting — `/scholar-journal`

```
/scholar-journal prepare manuscript for Demography
/scholar-journal which journal for computational paper on mobility and segregation
```

Five modes:
- **FULL-PACKAGE**: complete submission prep — structure audit + compliance checklist + cover letter + open science package
- **FORMAT-CHECK**: audit existing manuscript against journal requirements
- **COVER-LETTER**: draft journal-calibrated cover letter
- **SELECT-JOURNAL**: recommend target journals using 8-dimension scoring rubric (15 journals supported: ASR, AJS, Demography, Science Advances, NHB, NCS, Social Forces, Language in Society, Gender & Society, APSR, JMF, PDR, SMR, Poetics, PNAS)
- **RESUBMIT-PACKAGE**: post-rejection resubmission to a new journal

---

### 12. Open Science — `/scholar-open`

```
/scholar-open preregistration for fixed effects panel study
/scholar-open data sharing plan for survey with restricted interview data
/scholar-open replication package for computational paper with Twitter data
```

Five modes: PREREGISTER (OSF/AsPredicted/EGAP/Registered Reports + secondary-data preregistration), DATA-SHARE (FAIR principles, de-identification with sdcMicro, repository selection, platform-specific social media policies, computational data archiving via HuggingFace Hub), CODE-SHARE (replication packages with renv+conda+Docker+Makefile, CITATION.cff, Zenodo DOI; consumes `output/scripts/` from scholar-analyze/scholar-compute for pre-built script archive), FULL-PACKAGE (NSF/NIH DMP + CRediT + COI + IRB + OA strategy + APC waivers), REPLICATION-PACKAGE (audit: structure + clean-run test + data compliance).

---

### 12B. Replication Package — `/scholar-replication`

```
/scholar-replication full for Demography
/scholar-replication build existing scripts in output/scripts/
/scholar-replication test clean-run validation of replication package
/scholar-replication verify paper-to-code correspondence audit
/scholar-replication archive prepare Zenodo deposit
```

**Key distinction from `/scholar-open`:**
- `/scholar-open` = open science *declarations* (preregistration, data sharing policies, templates, audit checklists)
- `/scholar-replication` = replication package *construction and validation* (assemble, document, test, verify, archive)

Six modes:

**`build`** — Assemble replication package directory:
- Copies + renumbers scripts from `output/scripts/` into `replication-package/code/`
- Generates `00_master.R` controller script
- Copies tables/figures from both main pipeline (`output/tables/`, `output/figures/`) and EDA pipeline (`output/eda/tables/`, `output/eda/figures/`)
- Consumes artifact registry from `scholar-write` as authoritative table/figure numbering map
- Verifies table format coverage (at least one of HTML/TeX/docx) and figure formats (PDF/PNG/SVG/EPS)
- Handles data (public → copy; restricted → access instructions + mock data via `fabricatr`/`synthpop`; social media → IDs-only per TOS)
- Captures environment (`renv::snapshot()` / `conda env export`)
- Generates LICENSE (MIT + CC-BY-4.0), CITATION.cff, Makefile, Dockerfile (if NCS/computational)

**`document`** — Generate comprehensive documentation:
- README following the AEA Social Science Data Editors template (9 sections: overview, data provenance, dataset list, computational requirements, program descriptions, replicator instructions, output correspondence, known limitations, references)
- Data codebook with variable dictionary (auto-generated from data via `skimr` + `labelled` if available)
- Computational requirements document (software, hardware, runtime, seeds)
- Script dependency graph

**`test`** — Clean-run validation:
- Pre-flight checks: file existence, syntax validation, no absolute paths, random seeds, README completeness
- Environment isolation: restore `renv.lock` / `environment.yml` in fresh directory (or Docker build)
- Execute master script, time each sub-script, capture logs
- Compare reproduced outputs against originals — covers both main (`output/tables/`, `output/figures/`) and EDA (`output/eda/tables/`, `output/eda/figures/`) directories
- Generate `TEST-REPORT.md` with per-script PASS/FAIL status and overall verdict

**`verify`** — Paper-to-code correspondence audit:
- Consumes artifact registry (from `scholar-write`) as authoritative source if available
- Extract all tables, figures, placement markers (`[Table N about here]`), and in-text statistics from manuscript
- Map each claim to its producing script + output file (including EDA/appendix outputs)
- Flag MAPPED / PARTIAL / UNMAPPED items; cross-check with artifact registry for ORPHAN (output exists, not referenced) and MISSING (referenced, no output) items
- Generate `VERIFICATION-REPORT.md` with completeness score and unmapped item remediation

**`archive`** — Repository deposit preparation:
- Pre-deposit cleanup (remove test artifacts, `.DS_Store`, `__pycache__`)
- Journal-specific repository recommendation (NCS→Zenodo+CodeOcean; APSR→Harvard Dataverse; AJS→AJS Dataverse; general→Zenodo)
- GitHub release + Zenodo DOI integration instructions
- Deposit metadata template (title, authors with ORCID, abstract, keywords, license)
- Post-deposit checklist (DOI in CITATION.cff + README + manuscript)

**`full`** (default) — Run all modes in sequence: BUILD → DOCUMENT → TEST → VERIFY → ARCHIVE.

**Output files:**
- `replication-package/README.md` — comprehensive AEA-template README
- `replication-package/TEST-REPORT.md` — clean-run test results
- `replication-package/VERIFICATION-REPORT.md` — paper-to-code correspondence audit
- `output/replication/replication-report-[slug]-[YYYY-MM-DD].md` — internal log

---

### 13. Peer Review — `/scholar-respond`

Five modes:

**Before submission — simulate peer review:**
```
/scholar-respond simulate paper.pdf for Demography
```
Spawns 3–4 parallel reviewer agents (methods, theory, senior editor, + computational if applicable) calibrated to the target journal. Returns severity×confidence matrix, revision roadmap, and mock editorial decision.

**After receiving reviews — draft response letter:**
```
/scholar-respond respond reviews.txt paper.pdf
```
Categorizes each comment (MAJOR-FEASIBLE, MINOR, DISAGREE, INFEASIBLE), drafts
point-by-point responses, and handles conflicting reviewer demands with template language
for each situation.

**After R&R decision — revise manuscript:**
```
/scholar-respond revise paper.pdf reviews.txt response.txt
```

**After R&R decision — standalone cover letter:**
```
/scholar-respond cover-letter paper.pdf for R1 to Demography
```

Also covers: resubmission strategy after rejection (triage decision type → diagnose root
cause → journal ladder by subfield → rewrite introduction for new journal).

---

---

### 15. Data Safety — `/scholar-safety`

```
# Scan a data file before analysis (local scan — no file content read by Claude)
/scholar-safety scan data/interviews.csv

# Safety gate before loading data for scholar-eda or scholar-analyze
/scholar-safety gate about to load nhanes_restricted.dta for regression analysis

# Generate a full project data safety protocol
/scholar-safety protocol segregation-health project, NHANES restricted, IRB expedited

# Check what has been logged
/scholar-safety status
```

**The core problem it solves:** When Claude Code uses the `Read` tool or a `Bash cat` command on a data file, the entire file contents are transmitted to Anthropic's API servers. For restricted datasets (NHANES, PSID, NLSY, Census RDC), HIPAA-covered health data, interview transcripts, or IRB-protected participant data, this transmission may violate data use agreements, IRB protocols, or privacy regulations (GDPR, HIPAA).

**How it works:**
1. Runs local `Bash grep -c` pattern scans on data files — only match *counts* are returned; the actual sensitive values never enter Claude's context during the scan
2. Classifies each file as 🟢 LOW / 🟡 MEDIUM / 🔴 HIGH risk using a composite scoring matrix
3. For HIGH risk: displays a full warning with specific flags found, halts, and presents four options
4. For MEDIUM risk: displays a caution advisory and asks for confirmation
5. For LOW risk: logs green light and proceeds

**Three response options when risk is detected:**
- **[B] ANONYMIZE** — generates a ready-to-run R anonymization script (removes all 18 HIPAA identifiers, replaces participant IDs with sequential labels, generalizes geography and dates)
- **[C] LOCAL MODE** — generates Bash/R scripts that output ONLY aggregated results (means, SDs, regression coefficients, tables) — raw data never enters Claude's context; the researcher pastes only the printed output
- **[A] HALT** — stops all operations; provides IRB amendment template and data handling guidance


**Output files:**
- `output/logs/scholar-safety-log.md` — running log of every scan, risk level, and permission decision
- `output/protocols/scholar-safety-protocol-[slug]-[YYYY-MM-DD].md` — full project safety protocol (MODE: `protocol`)

**What it detects (locally, without reading file content into AI context):**
- SSN patterns, email addresses, phone numbers, street addresses
- HIPAA/PHI: diagnosis codes, medical records, medication, clinical terms
- Mental health: depression, suicide, psychiatric, substance use
- Legal/immigration status: undocumented, criminal record, deportation
- Restricted data markers: NHANES, PSID, NLSY, IPUMS, DUA, restricted-use
- Fine-grained geographic data: GPS coordinates, census tracts, geocodes
- IRB participant markers: participant IDs, consent, interview, transcript

---

### 16. Research Ethics — `/scholar-ethics`

```
# Pre-submission comprehensive ethics check
/scholar-ethics full paper.pdf for Nature Human Behaviour

# AI tool data privacy audit
/scholar-ethics ai-audit used Claude Code and ChatGPT for analysis and writing

# Plagiarism and originality check
/scholar-ethics plagiarism paper.pdf for ASR; prior conference paper exists

# Research authenticity audit (p-hacking, HARKing, data integrity)
/scholar-ethics integrity results suggest p-hacking concern; multiple DVs tested

# General ethics compliance (IRB, authorship, COI, data sharing)
/scholar-ethics general for Demography; survey data; 3 authors; NSF funded
```

Four modes, any of which can be run independently or together:

**MODE 1 — AI Tool Data Privacy Audit:**
Documents which AI tools (Claude Code, ChatGPT, GitHub Copilot, etc.) were used at each research stage, assesses privacy risk for each data type shared, checks GDPR / HIPAA / data use agreement compliance, and drafts a journal-required AI use disclosure statement. Recommends local LLM alternatives (Ollama) when sensitive data is involved.

**MODE 2 — Plagiarism & Originality Check:**
Section-by-section originality review; self-plagiarism and text-recycling assessment with journal-specific policies; AI-generated text evaluation and disclosure requirements; similarity score (iThenticate / Turnitin) interpretation guide; originality statement ready to paste into cover letter.

**MODE 3 — Research Authenticity Audit:**
Runs the full QRP (Questionable Research Practices) screen across data collection, analysis, and reporting. Detects p-hacking indicators; generates R code for multiverse analysis and specification curve. Checks for HARKing with remediation language. Data fabrication cross-check protocol (Benford's law, GRIM test, provenance verification). Result misinterpretation audit: causal language in observational studies, statistical vs. substantive significance, multiple comparisons, overgeneralization. Produces a research integrity self-certification.

**MODE 4 — General Ethics Standards:**
IRB determination checklist (Exempt / Expedited / Full); informed consent elements verification; CRediT author contribution statement; conflict of interest disclosure; data availability statement tailored to target journal; AI use declaration. Journal-specific ethics compliance checklists for Nature, Science Advances, ASR, AJS, Demography.

**Output files:**
- `scholar-ethics-log-[slug]-[YYYY-MM-DD].md` — internal checklist with PASS/FLAG for every item
- `scholar-ethics-report-[slug]-[YYYY-MM-DD].md` — all paste-ready declaration texts formatted for the target journal

---

### 17. Sociolinguistics — `/scholar-ling`

```
/scholar-ling variationist analysis of t-deletion in NYC corpus
/scholar-ling conversation analysis of patient-doctor interactions
/scholar-ling discourse analysis of immigration policy debates
/scholar-ling matched guise experiment for accent attitudes study
```

6 modules: Variation studies (Rbrul/VARBRUL/mixed-effects), Acoustic phonetics (Praat/Parselmouth/librosa + power analysis), Corpus linguistics (quanteda, keyness G², STM with prevalence effects), Conversation Analysis / Discourse (Jefferson notation, computational CDA with CADS workflow + STM framing + LLM topoi coding), Narrative / Grounded Theory / Matched Guise, Computational Sociolinguistics (conText embedding regression, LLM annotation for linguistic coding, BERT classification, semantic change detection). Methods templates by journal type.

---

### 18. Quality Audit — `/scholar-auto-improve`

```
/scholar-auto-improve observe output/drafts/
/scholar-auto-improve audit
/scholar-auto-improve improve
/scholar-auto-improve evolve
```

Continuous quality engine with four modes:

**`observe`** — Post-skill output audit. Spawns 3 parallel diagnostic agents (Structural Auditor, Academic Quality Reviewer, Cross-Skill Consistency Checker) to evaluate the most recent skill output. Produces health score (0–100: GREEN/YELLOW/RED) and improvement recommendations.

**`audit`** — Skill-suite structural health check. Runs 10 checks (A1–A10) across all skill SKILL.md files: frontmatter completeness, tool declaration accuracy, step numbering, quality checklist existence, save output section, reference files, cross-skill references, absolute rule consistency, output directory patterns, multi-format output. Spawns 3 audit agents (Architecture, Standards Compliance, Usability).

**`improve`** — Fix generation from audit/observe findings. Prioritizes issues by severity, generates fixes with user confirmation gate, runs post-fix verification.

**`evolve`** — Cross-session pattern analysis. Reviews improvement logs across sessions to identify systemic issues and propose structural improvements.

Available as a lightweight post-execution hook for individual skills.

**Output files:**
- `output/auto-improve/diagnostic-report-[date].md` — health score + issue inventory
- `output/auto-improve/improvement-log.md` — running log across sessions

### 19. Document Synchronization — `/sync-docs`

```
/sync-docs slides.tex script.tex manuscript.tex
/sync-docs
```

Synchronizes content across presentation slides, speaker script, and manuscript/paper. Auto-detects documents if paths are not provided.

**What it does:**
1. Identifies all related documents (LaTeX/Beamer slides, speaker scripts, manuscripts)
2. Audits for stale references, mismatched numbers, outdated citations, and version inconsistencies
3. Updates all files in parallel to ensure consistency
4. Compiles updated documents to PDF

Use after editing one document (e.g., updating a figure in slides) to propagate changes to the script and manuscript. Particularly useful for job talks and conference presentations where slides, speaking notes, and the underlying paper must stay in sync.

---

## Zotero Integration

Skills `/scholar-lit-review`, `/scholar-write`, and `/scholar-citation` all query your
Zotero library automatically — no API keys or running Zotero required.

**Library location:**
Auto-detected by `setup.sh`, or set `SCHOLAR_ZOTERO_DIR` in your `.env` file.
Common locations: `~/Zotero`, `~/Library/CloudStorage/*/zotero`

**What gets queried:**
- `zotero.sqlite.bak` — your journal articles and books
- `storage/[KEY]/[filename].pdf` — attached PDFs readable via `pdftotext`

**What each skill does:**
- `/scholar-lit-review` Step 0: keyword search of title + abstract before any web search; also supports author search, collection/folder search, and PDF reading for top results
- `/scholar-write` Step 0: pulls relevant citations by topic keyword when drafting a section
- `/scholar-citation` Step 1: retrieves full bibliographic metadata (author, year, title, journal, volume, issue, pages, DOI) for all cited sources; MODE 5 (VERIFY) uses Zotero as Tier 1 verification before CrossRef and WebSearch

**Manual search** (if you want to query Zotero yourself):
```bash
ZOTERO_DIR="$SCHOLAR_ZOTERO_DIR"  # Set in .env via setup.sh, or auto-detected
DB="$ZOTERO_DIR/zotero.sqlite.bak"
Q="%segregation%"

sqlite3 "$DB" "
SELECT c.lastName || ' (' || SUBSTR(year.value,1,4) || '). ' || title.value || '. ' || COALESCE(pub.value,'')
FROM items parent
JOIN itemTypes it ON parent.itemTypeID = it.itemTypeID
LEFT JOIN itemData title_d ON parent.itemID = title_d.itemID
  AND title_d.fieldID = (SELECT fieldID FROM fields WHERE fieldName='title')
LEFT JOIN itemDataValues title ON title_d.valueID = title.valueID
LEFT JOIN itemData year_d ON parent.itemID = year_d.itemID
  AND year_d.fieldID = (SELECT fieldID FROM fields WHERE fieldName='date')
LEFT JOIN itemDataValues year ON year_d.valueID = year.valueID
LEFT JOIN itemData pub_d ON parent.itemID = pub_d.itemID
  AND pub_d.fieldID = (SELECT fieldID FROM fields WHERE fieldName='publicationTitle')
LEFT JOIN itemDataValues pub ON pub_d.valueID = pub.valueID
LEFT JOIN itemCreators ic ON parent.itemID = ic.itemID AND ic.orderIndex=0
LEFT JOIN creators c ON ic.creatorID = c.creatorID
WHERE it.typeName IN ('journalArticle','book','bookSection','conferencePaper','preprint','thesis')
  AND (LOWER(title.value) LIKE '$Q' OR LOWER(abstract.value) LIKE '$Q')
GROUP BY parent.itemID
ORDER BY SUBSTR(year.value,1,4) DESC LIMIT 20;
" 2>/dev/null
```

---

## Example Article Assets

`/scholar-write` uses your published papers as a
**style and voice reference** when drafting. The catalog is at
`.claude/skills/scholar-write/assets/index.md`.

**How it works (3-tier knowledge graph, v3.0.0):**
1. **Tier 1** — Reads `assets/article-knowledge-base.md`: pre-extracted annotations for ~119 papers (verbatim opening lines, gap sentences, contribution claims, voice registers, citation density, paragraph length norms). No pdftotext needed for most selections.
2. **Tier 2** — Reads `assets/section-snippets.md`: verbatim quote library by 9 rhetorical functions (hooks, gap statements, contribution claims, theory/mechanism descriptions, methods leads, results leads, discussion openers, hedging, quantitative sentences) — each with an architecture note explaining the sentence pattern.
3. **Tier 3** — Optional `pdftotext` deep read of a specific paper when more context is needed.
4. The draft mirrors your established voice and targets the structural depth of the selected journal exemplars.

**Quick selection guide** — After populating your article library (see README Setup instructions), the skill automatically matches your papers to drafting tasks. Example table structure:

| Paper type | Your article (voice) | Top-journal reference (structure/depth) |
|-----------|-----------------------|-----------------------------------------|
| Your specialty area | Your published paper | Recent exemplar from target journal |
| Second topic area | Another of your papers | Another top-journal exemplar |
| ... | ... | ... |

The full catalog lives at `assets/index.md`. Add your own PDFs to `assets/example-articles/` and top-journal exemplars to `assets/top-journal-articles/`, then ask Claude Code to build the index (see README for the one-prompt setup).

---

## Tips

**Be specific in section arguments** — the more context you give `/scholar-write`, the better:
```
# Less useful
/scholar-write introduction

# More useful
/scholar-write introduction on activity space segregation and health for Demography,
fixed effects panel design, computational + demographic audience, ~800 words
```

**Run `/scholar-citation` after drafting, before formatting** — insert citations on the
full draft before running `/scholar-journal`. Use `verify` mode to confirm all references
actually exist before submission. This ensures the compliance check sees the final word
count including all in-text citations, and that zero fabricated references remain.

**Use `/scholar-journal` early** — run it before writing to know the word limit, abstract
format, and citation style for your target journal. Reformatting after the fact is slow.

**Chain modular skills in sequence** — each skill's output feeds the next. Paste your
H1–H3 from `/scholar-hypothesis` as context when running `/scholar-design`.

**For intersectionality arguments** — `/scholar-hypothesis` includes formal multiplicative
specification (interaction term β₃), hypothesis language templates, and non-Western
theoretical traditions (coloniality, Ubuntu, guanxi). Invoke with the specific axes:
```
/scholar-hypothesis intersectionality of race and gender in campaign donations
```

---

## Version

Current version: **5.3.0**
Project location: this repository's root directory
Skills: 23 + 1 utility (in `.claude/skills/`) | Agents: 13 (9 peer-reviewer + 4 verification, in `.claude/agents/`) | Reference files: ~44 | Asset articles: ~127 (pre-indexed in article-knowledge-base.md)
