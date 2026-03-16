# Replication Standards Reference

Comprehensive reference for building journal-ready replication packages in the social sciences.

---

## 1. Journal Requirements Comparison Table

| Dimension | ASR / AJS | Demography | Science Advances | NHB | NCS | APSR | AJPS | AEA journals |
|-----------|-----------|------------|------------------|-----|-----|------|------|-------------|
| **Data statement** | Required in manuscript | Required in manuscript | Required; DOI for data | Required; data availability section | Required; data availability section | Required; Dataverse deposit | Required; Dataverse deposit | Required; openICPSR |
| **Code sharing** | Encouraged | Encouraged | Required; DOI for code | Required | Required; computational reproducibility | Required; Dataverse | Required; Dataverse | Required; openICPSR |
| **Replication package** | Encouraged (not enforced pre-acceptance) | Encouraged | Recommended | Recommended | Strongly recommended (Code Ocean) | **Required** (Harvard Dataverse) | **Required** (AJPS Dataverse) | **Required** (openICPSR; pre-acceptance verification) |
| **Third-party verification** | No | No | No | No | No | Yes (reviewers check code) | No | **Yes** (AEA Data Editor verifies) |
| **Repository** | Any reputable | Any reputable | Zenodo / Dryad / institutional | Zenodo / figshare | Zenodo / Code Ocean | Harvard Dataverse (required) | AJPS Dataverse (required) | openICPSR (required) |
| **Docker / container** | Not required | Not required | Not required | Not required | Recommended (Code Ocean capsule) | Not required | Not required | Not required (but helpful) |

### Key implications for package construction

- **APSR / AJPS / AEA**: strictest requirements — package must be complete and verified before acceptance; Harvard/AJPS/openICPSR deposit is mandatory
- **NCS**: computational reproducibility emphasized — Docker/Code Ocean capsule strongly recommended
- **Science Advances / NHB**: DOIs required for data and code; deposit in a DOI-minting repository
- **ASR / AJS / Demography**: more flexibility; a well-documented Zenodo or GitHub deposit meets expectations
- **All journals**: a comprehensive README is the single most important element

---

## 2. AEA Template README (Gold Standard)

The AEA Social Science Data Editors maintain the reference template for replication READMEs. This template has been widely adopted beyond economics — political science (APSR, AJPS), sociology, and interdisciplinary journals all recognize it.

Source: https://social-science-data-editors.github.io/template_README/

### Full 9-Section Template

```markdown
# [TITLE] — Replication Package

## Overview

> SUMMARY: Provide a summary description of the package, indicating what
> the reader can replicate with this package.

This package provides data and code to replicate all tables, figures, and
in-text statistics in "[Paper Title]" by [Authors], published in [Journal]
([Year]).

Computational requirements: [Software], approximately [N] hours on a
standard desktop ([Year]).

## Data Availability and Provenance Statements

> INSTRUCTIONS: For each data source, provide details on how the data
> was obtained, whether it is publicly available, and if not, how to
> obtain access. Include citations for each dataset.

### [Data Source 1]

The data were obtained from [source] on [date]. The data are [publicly
available / available under restricted access]. Access requires
[registration / application / DUA]. The data are provided as part of
this replication package [/ cannot be redistributed].

- **Citation**: [full dataset citation]
- **URL**: [URL]
- **Access**: [public / restricted / application required]

### Statement about Rights

> INSTRUCTIONS: Choose the appropriate statement(s).

- [x] I certify that the author(s) of the manuscript have legitimate
  access to and permission to use the data used in this manuscript.
- [ ] I certify that the author(s) of the manuscript have documented
  permission to redistribute/publish the data contained in this
  replication package. Appropriate permission is documented in
  the LICENSE.txt file.

## Dataset List

> INSTRUCTIONS: List all data files in the replication package.

| Data file | Source | Notes | Provided |
|-----------|--------|-------|----------|
| `data/raw/main_data.csv` | [source] | Main analytic dataset | Yes |
| `data/raw/supplementary.csv` | [source] | Auxiliary variables | Yes |

## Computational Requirements

> INSTRUCTIONS: Describe the hardware and software requirements.

### Software Requirements

- R 4.4.0 (https://cran.r-project.org/)
  - `fixest` (0.11.2)
  - `marginaleffects` (0.18.0)
  - `modelsummary` (2.0.0)
  - `ggplot2` (3.5.0)
  - [complete list in renv.lock]
- The code was last run on a Mac M1 with macOS 14.5.

### Controlled Randomness

- Random seed set at line [N] of `code/03_main_analysis.R`:
  `set.seed(42)` (for bootstrap standard errors)

### Memory and Runtime Requirements

The code was run on a [computer description]. Approximate time:

| Script | Runtime |
|--------|---------|
| 01_clean_data.R | < 1 min |
| 02_construct_sample.R | 2 min |
| 03_main_analysis.R | 15 min |
| 04_robustness_checks.R | 30 min |
| 05_generate_figures.R | 5 min |
| **Total** | **~53 min** |

## Description of Programs / Code

> INSTRUCTIONS: Describe what each program/script does and list them
> in the order they should be run.

- `code/00_master.R`: Master script that runs all programs in sequence.
  Run this to reproduce all results.
- `code/01_clean_data.R`: Loads raw data, applies sample restrictions,
  recodes variables. Output: `data/processed/clean.rds`
- `code/02_construct_sample.R`: Constructs the analytic sample, merges
  datasets. Output: `data/processed/analytic.rds`
- `code/03_main_analysis.R`: Produces Tables 1–3. Output:
  `output/tables/table1-3.html`
- `code/04_robustness_checks.R`: Produces Appendix Tables A1–A3.
  Output: `output/tables/tableA1-A3.html`
- `code/05_generate_figures.R`: Produces Figures 1–3. Output:
  `output/figures/fig1-3.pdf`

## Instructions to Replicators

> INSTRUCTIONS: Provide step-by-step instructions.

1. Install R 4.4.0 from https://cran.r-project.org/
2. Open R in the replication package directory
3. Run `renv::restore()` to install all required packages
4. [If restricted data: Place the data files in `data/raw/` per the
   instructions in Data Availability]
5. Run `source("code/00_master.R")` — this executes all scripts in order
6. Outputs will appear in `output/tables/` and `output/figures/`
7. Compare against published tables and figures

## List of Tables and Programs

> INSTRUCTIONS: Map each table/figure to its producing program.

| Figure/Table # | Program | Output file | Note |
|---------------|---------|-------------|------|
| Table 1 | `code/03_main_analysis.R` | `output/tables/table1.html` | |
| Table 2 | `code/03_main_analysis.R` | `output/tables/table2.html` | |
| Figure 1 | `code/05_generate_figures.R` | `output/figures/fig1.pdf` | |

## [Optional] Known Issues

- [Note any known reproducibility issues, e.g., stochastic results,
  platform dependencies, long runtimes]

## References

[Dataset citations]
[Software citations — use `citation("packagename")` in R]
```

---

## 3. Common Replication Failures

Based on the AEA Data Editor experience (Vilhuber 2020), replication verification reports from AJPS/APSR, and the social science replication crisis literature.

### Top 10 Failures (ordered by frequency)

| # | Failure | Frequency | Fix |
|---|---------|-----------|-----|
| 1 | **Missing files** — scripts reference files not in the package | Very common | Audit all `read.*()` / `load()` calls against `data/` contents |
| 2 | **Hardcoded paths** — `/Users/john/...` or `C:\Users\...` | Very common | `grep -rn '/Users\|/home\|C:\\' code/`; replace with `here::here()` |
| 3 | **Missing packages** — scripts load packages not in lockfile | Common | Run `renv::snapshot()` after final execution; verify lockfile |
| 4 | **No master script** — unclear run order | Common | Provide `00_master.R` that sources all scripts in sequence |
| 5 | **Unseeded randomness** — bootstrap/MCMC/imputation without `set.seed()` | Common | Grep for `sample\|boot\|mice\|mcmc` and verify `set.seed()` precedes |
| 6 | **Output discrepancies** — reproduced numbers differ from paper | Moderate | Usually due to (a) unseeded randomness, (b) different package versions, (c) intermediate data not saved |
| 7 | **No README or inadequate README** — package exists but no instructions | Moderate | Use AEA template; include all 9 sections |
| 8 | **Restricted data with no access instructions** — code references data the replicator cannot access | Moderate | Provide mock data + detailed access instructions |
| 9 | **Excessive runtime** — scripts take days without warning | Less common | Document runtime per script; provide intermediate checkpoints |
| 10 | **Platform dependency** — works on Mac but not Linux (or vice versa) | Less common | Document OS; use `here::here()` for paths; test on second platform if possible |

### How AEA Data Editor Reports Are Structured

The AEA Data Editor's reports follow a standardized format:
1. **Summary**: overall assessment (accept / conditional accept / revise & resubmit)
2. **Data**: are data available? properly documented? properly cited?
3. **Code**: does code run? are there errors? are paths correct?
4. **Outputs**: do reproduced outputs match the paper?
5. **Specific issues**: numbered list of problems found
6. **Recommendation**: specific changes needed

### Self-Checking Before Submission

From Vilhuber (2020) "Report by the AEA Data Editor":
1. Re-run all code on your own machine with a fresh workspace
2. Have a co-author or RA run the code from scratch
3. Check that all data files referenced actually exist in the package
4. Check that output numbers match the paper
5. Remove any files not needed for replication

---

## 4. Clean-Run Testing Protocol

Five levels of testing, from least to most rigorous.

### Level 1: Re-run on own machine (minimum)

```bash
# Clear R workspace, re-run master script
rm .RData .Rhistory 2>/dev/null
Rscript code/00_master.R
```
- **What it catches**: broken code, missing intermediate files
- **What it misses**: hardcoded paths, missing packages (already installed), platform issues

### Level 2: Document environment

```bash
# Capture exact package versions
Rscript -e "renv::snapshot()"
# OR
pip freeze > requirements.txt
```
- Ensures lockfile is current
- Record OS, R/Python version, hardware

### Level 3: Fresh environment on own machine

```bash
# Create fresh R library
mkdir test-env && cd test-env
cp -r ../replication-package .
cd replication-package

# Restore from lockfile
Rscript -e "renv::restore()"

# Run
Rscript code/00_master.R
```
- **What it catches**: missing packages not in lockfile, hidden dependencies
- This is the **minimum recommended level** for journal submission

### Level 4: Someone else runs it

- Give the package to a co-author, RA, or colleague
- They run it on their machine following only the README instructions
- They report any issues

### Level 5: Docker / VM from scratch

```bash
# Build from Dockerfile
docker build -t replication-test .
docker run --rm -v $(pwd)/output:/replication/output replication-test
```
- **What it catches**: everything — OS dependencies, system libraries, platform issues
- Recommended for NCS, computational papers, and any paper using GPU/HPC
- The most rigorous test possible without third-party verification

### Which Level for Which Journal?

| Journal | Minimum level | Recommended level |
|---------|--------------|-------------------|
| ASR / AJS | Level 2 | Level 3 |
| Demography | Level 2 | Level 3 |
| Science Advances | Level 3 | Level 4 |
| NHB | Level 3 | Level 4 |
| NCS | Level 4 | Level 5 (Docker) |
| APSR / AJPS | Level 3 | Level 4 |
| AEA journals | Level 4 (external verification mandatory) | Level 5 |

---

## 5. Data Documentation Standards

### Variable Dictionary Format

```markdown
| Variable | Label | Type | Values | Source | Missingness | Notes |
|----------|-------|------|--------|--------|-------------|-------|
| `pid` | Participant ID | integer | 1–5000 | — | 0% | Primary key |
| `age` | Age at interview | integer | 18–95 | Wave 1 Q3 | 2.1% | Top-coded at 95 |
| `female` | Female indicator | binary | 0/1 | Wave 1 Q1 | 0.3% | 1 = female |
| `educ` | Education level | ordered factor | 1=<HS, 2=HS, 3=SC, 4=BA+ | Wave 1 Q5 | 1.5% | |
| `income_hh` | Household income (2020$) | continuous | 0–500000 | Wave 1 Q12 | 8.3% | Top-coded at 500K |
```

### FAIR Data Principles Applied

| Principle | Implementation |
|-----------|---------------|
| **Findable** | DOI assigned via Zenodo/Dataverse; metadata in CITATION.cff; keywords in deposit |
| **Accessible** | Publicly downloadable (or access instructions for restricted data) |
| **Interoperable** | Open formats (CSV, RDS, Parquet); codebook with variable definitions |
| **Reusable** | License specified (CC-BY-4.0); provenance documented; preprocessing code included |

### Codebook Generation (R)

```r
library(skimr)
library(labelled)
library(dplyr)

df <- readRDS("data/processed/analytic.rds")

# Generate codebook from data
codebook <- tibble(
  variable = names(df),
  label = sapply(names(df), \(v) {
    l <- var_label(df[[v]]); if (is.null(l)) "—" else l
  }),
  type = sapply(df, \(x) paste(class(x), collapse = "/")),
  n_obs = sapply(df, \(x) sum(!is.na(x))),
  n_missing = sapply(df, \(x) sum(is.na(x))),
  pct_missing = sprintf("%.1f%%", sapply(df, \(x) mean(is.na(x)) * 100)),
  unique_values = sapply(df, \(x) length(unique(na.omit(x)))),
  range_or_levels = sapply(df, \(x) {
    if (is.numeric(x)) sprintf("[%.2f, %.2f]", min(x, na.rm=TRUE), max(x, na.rm=TRUE))
    else if (is.factor(x)) paste(levels(x), collapse = " / ")
    else paste(head(unique(na.omit(x)), 5), collapse = " / ")
  })
)

knitr::kable(codebook, format = "markdown")
```

---

## 6. Restricted Data Protocols

### DUA-Restricted Data Access Template

```markdown
## Accessing [Dataset Name]

The data used in this study are available through [organization] under
a Data Use Agreement (DUA).

### Application Process
1. Visit [URL]
2. Create an account / log in
3. Submit application describing intended use
4. Expected processing time: [N weeks/months]
5. Annual cost: [$amount or free]

### What You Will Receive
[Description of files, format, codebook]

### Placing Data Files
After obtaining access, place the following files in `data/raw/`:
- `[filename1]` — [description]
- `[filename2]` — [description]

Then run `code/01_clean_data.R` as described in the Instructions.

### Mock Data for Code Review
A synthetic dataset (`data/raw/mock_data.csv`) is provided so that
reviewers can verify the code runs without errors. Results from the
mock data will differ from published results.
```

### Synthetic Data Generation

**R — using fabricatr:**
```r
library(fabricatr)

mock <- fabricate(
  N = 5000,
  age = round(rnorm(N, mean = 45, sd = 15)),
  female = draw_binary(prob = 0.52, N = N),
  income = round(rlnorm(N, meanlog = 10.5, sdlog = 0.8)),
  treatment = draw_binary(prob = 0.5, N = N),
  outcome = 3.0 + 0.5 * treatment - 0.01 * age + 0.2 * female + rnorm(N)
)

write.csv(mock, "data/raw/mock_data.csv", row.names = FALSE)
```

**R — using synthpop (preserves statistical properties):**
```r
library(synthpop)

# Load original data (on secure machine)
real <- readRDS("restricted_data.rds")

# Generate synthetic version preserving correlations
synth <- syn(real, seed = 42)

write.csv(synth$syn, "data/raw/mock_data.csv", row.names = FALSE)
```

### Social Media Data (IDs-Only Approach)

Per platform Terms of Service, redistribute only post IDs:

```markdown
## Social Media Data

### Twitter/X Data
Per the Twitter/X Terms of Service, we provide tweet IDs rather than
full tweet content. The file `data/raw/tweet_ids.txt` contains [N] tweet
IDs collected between [start date] and [end date].

To rehydrate (retrieve full tweet data):
1. Obtain Twitter API credentials (Academic Research access recommended)
2. Run `code/00c_rehydrate.R` (uses `academictwitteR` or `twarc`)
3. Note: some tweets may no longer be available due to deletion/suspension

### Reddit Data
Post IDs are in `data/raw/reddit_post_ids.csv`.
Rehydrate using the Pushshift API or Reddit API:
```
```python
# code/00c_rehydrate_reddit.py
import praw
reddit = praw.Reddit(client_id="...", client_secret="...", user_agent="replication")
```
```

---

## 7. Environment Capture Reference

### renv (R — recommended)

```r
# Initialize renv in project
renv::init()

# After all packages are installed and code runs:
renv::snapshot()  # writes renv.lock

# To restore on another machine:
renv::restore()
```

Key `renv.lock` fields:
```json
{
  "R": { "Version": "4.4.0" },
  "Packages": {
    "fixest": { "Package": "fixest", "Version": "0.11.2", "Source": "Repository" },
    "ggplot2": { "Package": "ggplot2", "Version": "3.5.0", "Source": "Repository" }
  }
}
```

### conda (Python — recommended for complex environments)

```bash
# Create environment
conda create -n myproject python=3.11

# After all packages installed:
conda env export --no-builds > environment.yml

# To restore:
conda env create -f environment.yml
```

### pip (Python — simple projects)

```bash
pip freeze > requirements.txt
# To restore:
pip install -r requirements.txt
```

### Docker (maximum reproducibility)

R base image: `rocker/r-ver:4.4.0`
Python base image: `python:3.11-slim`
GPU (PyTorch): `pytorch/pytorch:2.1.0-cuda12.1-cudnn8-runtime`

Dockerfile pattern:
```dockerfile
FROM rocker/r-ver:4.4.0
RUN apt-get update && apt-get install -y [system deps]
COPY renv.lock renv.lock
RUN Rscript -e "install.packages('renv'); renv::restore()"
COPY . .
CMD ["Rscript", "code/00_master.R"]
```

### Makefile (pipeline orchestration)

```makefile
.PHONY: all clean

all: output/tables/table1.html output/figures/fig1.pdf

data/processed/clean.rds: code/01_clean_data.R data/raw/main_data.csv
	Rscript $<

data/processed/analytic.rds: code/02_construct_sample.R data/processed/clean.rds
	Rscript $<

output/tables/table1.html: code/03_main_analysis.R data/processed/analytic.rds
	Rscript $<

output/figures/fig1.pdf: code/05_generate_figures.R data/processed/analytic.rds
	Rscript $<

clean:
	rm -f data/processed/*.rds output/tables/*.html output/figures/*.pdf
```

### targets (R — advanced pipeline)

```r
# _targets.R
library(targets)
tar_option_set(packages = c("dplyr", "fixest", "ggplot2"))

list(
  tar_target(raw_data, read.csv("data/raw/main_data.csv")),
  tar_target(clean_data, clean_raw(raw_data)),
  tar_target(analytic, construct_sample(clean_data)),
  tar_target(table1, make_table1(analytic)),
  tar_target(fig1, make_figure1(analytic))
)
```

---

## 8. Dependency Graph Generation

### Manual documentation template

```markdown
## Script Dependency Graph

data/raw/*.csv
    │
    ▼
01_clean_data.R
    │ writes: data/processed/clean.rds
    ▼
02_construct_sample.R
    │ writes: data/processed/analytic.rds
    │
    ├───────────────────────┐
    ▼                       ▼
03_main_analysis.R      04_robustness_checks.R
    │                       │
    ▼                       ▼
output/tables/          output/tables/
  table1.html             tableA1.html
  table2.html             tableA2.html
  table3.html             tableA3.html
    │
    ▼
05_generate_figures.R
    │
    ▼
output/figures/
  fig1.pdf
  fig2.pdf
  fig3.pdf
```

### R code for targets visualization

```r
library(targets)
# After defining _targets.R:
tar_visnetwork()  # Interactive dependency graph
tar_manifest()    # Table of all targets and their commands
```

### Automated dependency extraction (R scripts)

```r
# Extract file reads/writes from R scripts to build dependency graph
extract_deps <- function(script_path) {
  lines <- readLines(script_path)

  # Find inputs (files read)
  reads <- grep("read[._]|load\\(|readRDS|fread|read_csv|source\\(",
                lines, value = TRUE)

  # Find outputs (files written)
  writes <- grep("write[._]|save\\(|saveRDS|fwrite|write_csv|ggsave|sink\\(",
                 lines, value = TRUE)

  list(
    script = basename(script_path),
    inputs = reads,
    outputs = writes
  )
}

# Apply to all scripts
scripts <- list.files("code/", pattern = "\\.[Rr]$", full.names = TRUE)
deps <- lapply(scripts, extract_deps)
```

---

## 9. Package Size Management

### File size guidelines

| Repository | Per-file limit | Total limit | Notes |
|-----------|---------------|-------------|-------|
| GitHub | 100 MB (hard); 50 MB warning | 1 GB recommended | Use Git LFS for large files |
| Zenodo | 50 GB | 50 GB | Free; generous |
| Harvard Dataverse | 2.5 GB per file | Varies | Contact for larger |
| ICPSR | 30 GB | 30 GB | Supports restricted access |
| openICPSR | 30 GB | 30 GB | AEA mandatory |

### Reducing package size

```bash
# Check what's large
du -sh replication-package/*
find replication-package/ -size +10M -exec ls -lh {} +

# Common large files to exclude:
# - .rds intermediate files (keep only final analytic dataset)
# - .pdf figures (keep; they're outputs)
# - model weights (.pt, .h5, .pkl) — provide download script instead
# - raw data (if large + public — provide download script)
```

### Git LFS for large files

```bash
git lfs install
git lfs track "*.rds"
git lfs track "data/raw/*.csv"
git add .gitattributes
```

---

## 10. Post-Submission Checklist by Journal

### Nature family (NHB, NCS, Nature, Nature Comms)

- [ ] Data availability statement in manuscript
- [ ] Code availability statement in manuscript
- [ ] Reporting Summary completed
- [ ] Supplementary Information properly formatted
- [ ] DOIs for data and code repositories
- [ ] CRediT author contribution statement
- [ ] Competing interests declaration

### Science family (Science Advances)

- [ ] Data and materials availability in manuscript
- [ ] Code DOI in references section
- [ ] Supplementary Materials properly structured
- [ ] Materials and Correspondence section
- [ ] MDAR (Materials Design Analysis Reporting) checklist

### APSR / AJPS

- [ ] Replication package uploaded to Harvard/AJPS Dataverse
- [ ] All data + code + README in Dataverse deposit
- [ ] Pre-analysis plan linked (if applicable)
- [ ] Dataverse DOI in manuscript

### ASR / AJS / Demography

- [ ] Data availability statement in manuscript
- [ ] Code availability statement (if applicable)
- [ ] Replication materials deposited in repository with DOI
- [ ] README follows AEA template or equivalent

### AEA journals (for reference — economics standard)

- [ ] Package uploaded to openICPSR
- [ ] README follows AEA template exactly (9 sections)
- [ ] All programs documented and commented
- [ ] AEA Data Editor approval received
- [ ] Reproducibility confirmed by third party
