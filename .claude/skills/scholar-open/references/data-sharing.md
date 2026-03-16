# Data Sharing and Open Science Reference

## FAIR Data Principles — Implementation Guide

FAIR = **F**indable, **A**ccessible, **I**nteroperable, **R**eusable
Required for NHB, NCS, and PNAS Reporting Summaries.

### Findable
- Deposit data in a repository that issues a **persistent identifier (DOI)**
- Fill all metadata fields: title, creator, subject, description, keywords, date
- Use controlled vocabulary where available (e.g., DDI subject classifications for surveys)

```bash
# Check DOI resolves correctly:
curl -I https://doi.org/10.7910/DVN/XXXXXX
# Should return: HTTP/1.1 302 Found → redirect to dataset page
```

### Accessible
- Data retrievable via standard HTTPS; no special software required for access
- Access conditions explicitly stated (open, restricted, embargoed)
- Restricted data: clear instructions on how to apply for access
- Metadata remains accessible even if data are not publicly available

### Interoperable
- Save in **open formats**: CSV, TSV, JSON (not Excel .xlsx, SPSS .sav, Stata .dta without conversion)
- Include codebook with standard variable names, labels, and value codes
- Use standard ontologies where applicable (DDI for survey data; schema.org for web data)
- Date variables: ISO 8601 format (YYYY-MM-DD)

```r
# Export Stata .dta to CSV with labels
library(haven)
df <- read_dta("data.dta")
df <- as_factor(df)      # Converts value labels to factor levels
write_csv(df, "data.csv")

# Export codebook
library(codebook)
codebook(df)             # Auto-generates variable documentation
```

### Reusable
- Attach **LICENSE file**: CC0 (public domain dedication) or CC-BY 4.0 (attribution required)
- Write **codebook** documenting every variable: name, label, type, range, missing code, source, transformation
- Describe all transformations applied to raw data
- Include CITATION.cff for machine-readable citation metadata

**Codebook template**:
```
Variable: income_log
  Label: Log annual household income (USD)
  Type: Continuous
  Range: [6.91, 13.12] (log scale); original range [1000, 500000]
  Missing code: NA (listwise; N_missing = 142, 3.2% of sample)
  Source: CPS 2022, HINCP variable
  Transformation: natural log after adding $1; winsorized at 99th pctile
  Notes: Use with caution for income below $1,000 (log close to 0)
```

---

## Data Availability Statement Decision Tree

```
Can you share the data?
│
├─ ORIGINAL COLLECTION
│   ├─ Fully de-identified + consent allows sharing
│   │   └─ → Deposit openly (Harvard Dataverse / Zenodo / OSF)
│   │       Use: "Fully open" statement template (below)
│   ├─ Sensitive (health, income, geo) but shareable with controls
│   │   └─ → De-identify (Step: De-Identification) → Deposit with
│   │         access controls (ICPSR restricted / embargoed Dataverse)
│   │         Use: "Restricted access" statement template
│   └─ Cannot share (IRB prohibition / no consent language / HIPAA)
│       └─ → Code + DMP only; restricted-access data availability statement
│
├─ SECONDARY DATA
│   ├─ Public-use (ACS, GSS, CPS, HRS public, NLSY public, IPUMS)
│   │   └─ → Include processed analytic dataset in replication package
│   │         OR point to official download URL
│   │         Use: "Secondary public data" statement template
│   ├─ Restricted-use (NLSY Geocode, FSRDC, Census RDC, linkage files)
│   │   └─ → Code only; describe access pathway; link to DUA form
│   │         Use: "Restricted secondary data" statement template
│   └─ Licensed/proprietary (Gallup, Nielsen, LexisNexis, Bloomberg)
│       └─ → Code + derived aggregates if ToS permits; access statement
│
├─ SOCIAL MEDIA (see Platform Policies section)
│   ├─ Twitter/X: tweet IDs only (rehydrate via twarc2)
│   ├─ Reddit: post/comment IDs (Pushshift no longer public post-2023)
│   └─ Derived data (DTM, embeddings, aggregated counts): usually shareable
│
└─ COMPUTATIONAL / ML DATA
    ├─ Model weights: HuggingFace Hub + Zenodo DOI
    ├─ Embeddings / feature matrices: Zenodo as numpy / CSV
    └─ Annotation labels: Zenodo CSV with codebook + IAA scores
```

---

## Repository Selection Guide

### Harvard Dataverse (recommended for social science survey data)
- **URL**: dataverse.harvard.edu
- **Cost**: Free
- **File size**: 2.5 GB per file; 1 TB per dataset
- **Access control**: Public / Restricted (DUA required) / Embargoed until date
- **DOI**: Automatic persistent DOI (10.7910/DVN/...)
- **Citation**: Auto-generates APA/MLA/BibTeX
- **FAIR**: Fully FAIR-compliant; Dublin Core metadata standard
- **Best for**: Survey microdata, population data, quantitative social science, sociology

```
Deposit steps:
1. dataverse.harvard.edu → Log in → Add Data → New Dataset
2. Fill metadata: title, author, contact, description, subject, keywords, language
3. Upload: data files + codebook (PDF/MD) + README + analysis code
4. Set access: Public / Restricted / Embargo until [YYYY-MM-DD]
5. Publish → DOI assigned (e.g., https://doi.org/10.7910/DVN/XXXXXX)
6. Update: new versions get version DOI; concept DOI always resolves to latest
```

### ICPSR (for population surveys with restricted-use needs)
- **URL**: icpsr.umich.edu
- **Cost**: Free for member institutions; $150–500 for non-member restricted deposits
- **Curation**: ICPSR staff review, clean, and document deposits
- **Restricted access**: Yes; requires virtual data enclave or DUA + secure download
- **Best for**: Large longitudinal surveys; administrative data; studies with restricted-use components

### Zenodo (for code and computational outputs)
- **URL**: zenodo.org
- **Cost**: Free; 50 GB limit per record
- **GitHub integration**: Toggle ON → each GitHub Release auto-archives with DOI
- **DOI**: Immediate versioned + concept DOI
- **FAIR**: Highly compliant; open API; Dublin Core + DataCite metadata
- **Best for**: Code + computational data; NCS requirement; small-to-medium datasets

```bash
# Zenodo + GitHub integration:
# 1. zenodo.org → GitHub tab → Toggle ON repository
# 2. GitHub → Create Release → tag v1.0.0
# → Zenodo auto-creates: https://doi.org/10.5281/zenodo.XXXXXXX

# Add to README.md:
# [![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.XXXXXXX.svg)](https://doi.org/10.5281/zenodo.XXXXXXX)
```

### OSF (for small datasets integrated with preregistrations)
- **URL**: osf.io
- **Cost**: Free; 50 GB total per project
- **Integration**: Linked to preregistrations; can connect GitHub, Dropbox, Google Drive
- **Best for**: Small supplementary datasets; qualitative appendices; study materials

### Qualitative Data Repository (QDR)
- **URL**: qdr.syr.edu
- **Cost**: Free for deposits under threshold; institutional membership
- **Specialization**: First FAIR-certified repository for qualitative social science data
- **Access control**: Flexible; can set access by researcher + agreement
- **Best for**: Interview transcripts, field notes, oral histories, qualitative coding files

---

## De-Identification Checklist

### Direct identifiers to remove (HIPAA Safe Harbor 18 + social science extensions)
- [ ] Full name → replace with participant ID (store ID-name lookup separately, encrypted)
- [ ] Geographic units smaller than state → recode to state / region / 3-digit ZIP
- [ ] Exact dates (birth, admission, event) → year, or year-quarter if < 100 in cell
- [ ] Phone numbers → remove
- [ ] Email addresses → remove
- [ ] Social security numbers → remove
- [ ] Medical record / health plan / account numbers → remove
- [ ] Certificate / license numbers → remove
- [ ] Vehicle identifiers → remove
- [ ] Device identifiers / serial numbers → remove
- [ ] Biometric identifiers (fingerprints, voiceprints) → remove
- [ ] Employer name → recode to NAICS/SIC industry code
- [ ] School name → recode to institution type / level
- [ ] URLs / social media handles → remove or replace with [handle]
- [ ] Photos, full-face images → do not deposit; store separately under IRB protocol
- [ ] IP addresses → remove or truncate to /24 subnet

### Quasi-identifiers — suppress or aggregate
Apply k-anonymity: every combination of quasi-identifiers (sex × race × age × geography)
must appear at least k=5 times in the released dataset.

```r
library(sdcMicro)

# Create SDC object
sdc <- createSdcObj(
  dat     = df,
  keyVars = c("age_cat", "sex", "race", "state", "educ_cat"),
  numVars = c("income", "earnings", "assets")
)

print(sdc)           # Check risk: % records at risk; global risk
# sdc@risk$individual: per-record re-identification risk

# Apply local suppression (k = 5)
sdc <- localSuppression(sdc, k = 5)

# Extract anonymized data
clean_df <- extractManipData(sdc)

# Also top-code extremes before release
clean_df$income <- pmin(clean_df$income,
                        quantile(clean_df$income, .99, na.rm = TRUE))

# Document all suppression decisions in codebook
cat("Suppressed cells:", sdc@localSuppression$totalSupps, "\n")
```

### Additional SDC techniques
- **Cell suppression**: Replace aggregated table cells with N < 5 as `*` (standard for public-use tables)
- **Top/bottom-coding**: Income > $250K → "250K+" (report threshold in codebook)
- **Noise injection**: Add U(-ε, ε) random noise to sensitive continuous variables; document in codebook
- **Microaggregation**: Replace individual values with group means for high-risk combinations

---

## Platform-Specific Social Media Data Policies

### Twitter / X (2024 policy)
- **Raw tweets**: Cannot redistribute (ToS Section 2F)
- **Tweet IDs**: CAN share — recipients must rehydrate via API
- **Derived data**: DTM, embeddings, aggregated counts — shareable
- **Academic Research API**: Requires application; approval gives full archive access

```python
# Share tweet IDs only (compliant with ToS)
import pandas as pd
df_ids = df[['tweet_id', 'created_at_year']].copy()
df_ids.to_csv('tweet_ids.csv', index=False)
# Deposit tweet_ids.csv on Zenodo

# Rehydration script (for README):
# twarc2 hydrate tweet_ids.csv --output hydrated_tweets.jsonl
# Note: rehydration success depends on tweet still being public at time of rehydration
```

### Reddit (2024 policy — Pushshift shutdown)
- **Raw posts**: Cannot redistribute under Reddit API ToS (changed June 2023)
- **Post/comment IDs**: Can share; users rehydrate via Reddit API (60 requests/min free)
- **Pushshift**: No longer publicly available post-June 2023; requires data sharing agreement with Pushshift/Reddit for academic access
- **Derived data**: Aggregates, topic distributions, embeddings — shareable

```python
# Share post IDs only
df_ids = df[['post_id', 'subreddit', 'created_year']].copy()
df_ids.to_csv('reddit_post_ids.csv', index=False)

# Rehydration via PRAW (Reddit's Python API):
# import praw
# reddit = praw.Reddit(client_id=..., client_secret=..., user_agent=...)
# post = reddit.submission(id='post_id')
```

### Facebook / Meta
- **Data**: Cannot redistribute; no ID sharing
- **Access**: Meta Content Library API (academic — apply at developers.facebook.com/programs/researcher-access)
- **Derived data**: Aggregated statistics only
- **Note**: CrowdTangle shut down August 2024

### TikTok
- **Data**: Cannot redistribute
- **Research API**: Apply at developers.tiktok.com/products/research-api
- **Derived data**: Aggregated metrics only (no video IDs)

### YouTube
- **Data**: Cannot redistribute raw
- **Video IDs**: Can share (YouTube Data API v3 for rehydration; 10,000 units/day free quota)
- **Derived data**: Aggregated metrics, topics — shareable

```python
# Share video IDs + metadata fields that don't require API rehydration
df_ids = df[['video_id', 'channel_category', 'upload_year']].copy()
df_ids.to_csv('youtube_video_ids.csv', index=False)
```

### Mastodon / Fediverse
- More permissive than corporate platforms; check individual instance ToS
- Generally: public posts can be scraped; can share post IDs; derived data OK
- Note: instance admins may have additional restrictions

### Best Practice for All Platforms

```
In README / Data Availability Statement:
"Raw [platform] data cannot be redistributed per platform Terms of Service.
[Tweet IDs / Post IDs / Video IDs] sufficient for data reconstruction are
available at [Zenodo DOI]. A derived dataset (document-term matrix with
[N]-word vocabulary; aggregated engagement metrics by [unit]) is also
archived at [Zenodo DOI]. Data collection code is at [GitHub URL].
Collection window: [dates]. N = [X] documents collected."
```

---

## Computational Data Sharing

### Model Weights and Checkpoints

| Model type | Format | Primary repository | DOI source | License guidance |
|------------|--------|-------------------|-----------|-----------------|
| HuggingFace-based (BERT, RoBERTa) | safetensors / pytorch_model.bin | HuggingFace Hub + Zenodo | Zenodo | Match base model license (Apache-2.0 / CC-BY) |
| Scikit-learn / XGBoost | joblib pickle (.pkl) | Zenodo | Zenodo | MIT or Apache-2.0 |
| Stan model | .stan file + RData posterior | OSF / Zenodo | Zenodo | CC-BY |
| NetLogo ABM | .nlogo file | CoMSES / Zenodo | CoMSES | GPL-2.0+ |

```python
# Upload fine-tuned BERT model to HuggingFace Hub
from transformers import AutoModel, AutoTokenizer
from huggingface_hub import HfApi

model.save_pretrained("./model_weights")
tokenizer.save_pretrained("./model_weights")

api = HfApi()
api.create_repo(repo_id="username/paper-model-name", repo_type="model", private=False)
api.upload_folder(
    folder_path="./model_weights",
    repo_id="username/paper-model-name",
    repo_type="model",
    commit_message="Upload fine-tuned model v1.0"
)
# Then archive a snapshot on Zenodo for persistent DOI:
# zenodo.org → upload model_weights.zip → get DOI
```

**Model card template** (required for HuggingFace Hub):
```markdown
# Model Name

## Model Details
- Base model: [e.g., roberta-base]
- Fine-tuning task: [text classification / NER / etc.]
- Training data: [description; NOT the data itself if sensitive]
- Paper: [Title + DOI]

## Intended Use
[What this model is for; limitations]

## Training
- Epochs: [N]; Batch size: [N]; Learning rate: [LR]
- Hardware: [GPU type]
- Evaluation: F1 = [X], Accuracy = [X] on test set

## Ethical Considerations
[Bias assessment; known failure modes]

## Citation
[BibTeX entry for paper]
```

### Embeddings and Feature Matrices

```python
import numpy as np

# Save dense embedding matrix (N documents × D dimensions)
embeddings = model.encode(texts)                    # numpy array (N, D)
np.save("document_embeddings.npy", embeddings)

# Save with document IDs for alignment
import pandas as pd
pd.DataFrame({'doc_id': doc_ids}).to_csv("embedding_doc_ids.csv", index=False)
# README: embeddings.npy row i corresponds to embedding_doc_ids.csv row i

# Save sparse DTM
from scipy.sparse import save_npz
save_npz("document_term_matrix.npz", dtm_sparse)
# Also save vocabulary
pd.Series(vocabulary).to_csv("vocabulary.csv", header=False)
```

### Annotation Labels (LLM / Human)

Deposit annotation files with full metadata for replication and meta-analysis:

```
Annotation archive structure:
annotation-labels/
├── README.md              ← Codebook; IAA scores; annotator info
├── human_labels.csv       ← doc_id, label, annotator_id, confidence
├── llm_labels.csv         ← doc_id, label, model, temperature, prompt_hash
├── adjudicated_labels.csv ← Final agreed-upon labels after reconciliation
├── codebook.md            ← Label definitions; examples; decision rules
└── iaa_report.csv         ← Pairwise κ / α / ICC by annotator pair
```

```csv
# human_labels.csv format
doc_id,label,annotator_id,annotation_date,confidence,notes
001,protest,A1,2024-03-15,high,
001,protest,A2,2024-03-15,high,
002,counter-protest,A1,2024-03-15,medium,"ambiguous; may be bypassers"
```

---

## Code Repository Standards

### GitHub Repository Structure
```
my-paper-replication/
├── README.md              ← Required; installation + run instructions
├── LICENSE                ← MIT (code) or CC-BY/CC0 (data)
├── CITATION.cff           ← Machine-readable citation metadata
├── Makefile               ← Orchestrates full pipeline: make all
├── environment.yml        ← Conda environment (Python)
├── renv.lock              ← R package environment
├── .gitignore             ← Excludes: data/raw/*, *.rds, .env, __pycache__
├── data/
│   ├── README.md          ← Documents each file; source; access instructions
│   ├── raw/               ← DO NOT commit raw data with PII; gitignored
│   └── processed/         ← De-identified analytic data (safe to share)
├── code/
│   ├── 01_clean.R
│   ├── 02_analyze.R
│   └── 03_figures.R
├── output/
│   ├── figures/
│   └── tables/
└── paper/
    └── manuscript.pdf     ← Latest preprint version
```

**Recommended .gitignore**:
```
# Data files with potential PII — never commit
data/raw/
*.rds
*.dta
*.sav
*.feather

# R environment (use renv.lock instead)
.Rproj.user/
.Rhistory

# Python cache
__pycache__/
*.pyc
.env

# OS files
.DS_Store
Thumbs.db

# Credentials
*.pem
.Renviron
secrets.yml
```

### CITATION.cff Template

```yaml
cff-version: 1.2.0
message: "If you use this code or data, please cite as below."
type: software
authors:
  - family-names: Smith
    given-names: Jane
    orcid: "https://orcid.org/0000-0000-0000-0000"
    affiliation: "University of X, Department of Sociology"
title: "Replication code for: [Paper Title]"
version: 1.0.0
doi: 10.5281/zenodo.XXXXXXX
date-released: 2025-01-15
url: "https://github.com/username/repository"
repository-code: "https://github.com/username/repository"
license: MIT
abstract: "Replication code and data for [Paper Title], published in [Journal] (Year)."
preferred-citation:
  type: article
  title: "[Paper Title]"
  authors:
    - family-names: Smith
      given-names: Jane
  journal: "[Journal Name]"
  year: 2025
  volume: 90
  issue: 1
  pages: "1-30"
  doi: 10.XXXX/XXXXXXXXXX
  issn: XXXX-XXXX
```

---

## Data Availability Statement Templates

**Fully open (deposited with DOI)**:
```
"The data that support the findings of this study are openly available at
[Harvard Dataverse / Zenodo] at https://doi.org/[DOI], reference
number [X]. The replication code is available at https://github.com/[user]/[repo]
(archived: https://doi.org/10.5281/zenodo.[ID])."
```

**Restricted access (apply via DUA)**:
```
"The data used in this study are available through [ICPSR / institutional
repository] under a data use agreement. Detailed instructions for obtaining
access are available at [URL]. The analysis code is available at [GitHub URL]
(archived: [Zenodo DOI])."
```

**Secondary public data (no deposit of original; only derived)**:
```
"The [General Social Survey / American Community Survey / NLSY79] data are
publicly available from [official URL]. The derived analytic dataset and
replication code are archived at [Zenodo DOI / Harvard Dataverse DOI]."
```

**Social media (IDs + derived features)**:
```
"The raw social media data cannot be redistributed per the platform's Terms of
Service. [Tweet IDs / Reddit post IDs] sufficient to reconstruct the corpus
are archived at [Zenodo DOI]. The derived dataset ([document-term matrix /
aggregated engagement metrics]) used in this analysis is also available at
[Zenodo DOI]. Data collection and preprocessing code is at [GitHub URL]."
```

**Qualitative (anonymized excerpts only)**:
```
"Interview transcripts cannot be shared publicly to protect participant
confidentiality per IRB protocol [number], approved [date]. Anonymized
excerpts supporting the key findings are provided in the Online Supplementary
Appendix. Requests for additional access to de-identified materials should be
directed to the corresponding author."
```

**Proprietary / licensed data (code only)**:
```
"This study uses proprietary data from [source] that we are not authorized
to redistribute. Researchers may obtain access through [process / URL].
The analysis code that operates on the raw data files is available at
[GitHub URL] (archived: [Zenodo DOI])."
```

---

## Open Access Strategy by Journal

| Journal | Default | OA option | APC | APC waiver path |
|---------|---------|-----------|-----|----------------|
| ASR | Subscription | Hybrid (ASA Open) | ~$2,600 | ASA member discounts; no LMIC waiver |
| AJS | Subscription | Hybrid (Chicago OA) | ~$3,000 | Contact journal; institutional agreements |
| Demography | Subscription | Hybrid (Duke UP) | ~$2,500 | Institutional agreements |
| Science Advances | **Mandatory OA** | — | ~$4,950 | AAAS members; LMIC full waivers; NSF/NIH compliance |
| NHB | Hybrid | Nature OA | ~€9,500 | Springer Nature agreements; LMIC waivers |
| NCS | Hybrid | Nature OA | ~€9,500 | Springer Nature agreements; LMIC waivers |
| PLOS ONE | **Mandatory OA** | — | ~$1,940 | LMIC full waivers; US NIH covered |
| Social Forces | Subscription | Oxford OA | ~$3,200 | Institutional agreements |
| APSR | Subscription | Cambridge OA | ~$3,200 | Institutional agreements |

### APC Waiver Procedures

**Nature (NHB/NCS) — Institutional agreement**:
```
1. After acceptance, billing page asks for institution
2. Search your institution → if Springer Nature deal exists → APC covered
3. If LMIC affiliation → select "Request full OA fee waiver"
4. If NSF/NIH funded → enter grant number; Springer checks compliance
```

**Science Advances — AAAS**:
```
1. After acceptance, AAAS membership number gives discount
2. For full waiver: submit request to oa@aaas.org before invoice
3. NSF/NIH compliance: send grant number; AAAS will apply public access compliance
```

### SocArXiv Preprint Deposit (Free OA)

```
1. osf.io/preprints/socarxiv → Log in → Add a preprint
2. Upload PDF; fill: title, abstract, authors, subject, tags
3. Link to OSF project if preregistered
4. After journal publication: update with DOI and link to published version
5. Cite in paper cover letter: "A preprint is available at [SocArXiv URL]"
```

All major sociology / social science journals allow preprints:
- ASR, AJS, Demography: allow preprints at any stage
- NHB, NCS: allow preprints before and after review
- Science Advances: preprints allowed; update with final DOI after publication
