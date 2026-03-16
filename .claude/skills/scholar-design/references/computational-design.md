# Computational Methods Design Reference

## 1. Corpus Sampling and Construction

### 1a. Sampling strategies for large corpora

When the full population exceeds what can be processed (e.g., all tweets ever, all news articles), apply a principled sampling strategy:

```python
import pandas as pd, numpy as np

# Stratified random sample by time period
df["period"] = pd.to_datetime(df["date"]).dt.to_period("M")
df_sample = (
    df.groupby("period", group_keys=False)
      .apply(lambda g: g.sample(min(len(g), 500), random_state=42))
      .reset_index(drop=True)
)
print(f"Sample N = {len(df_sample)} from {df['period'].nunique()} periods")

# Stratified by source and year
df_sample = df.groupby(["source", "year"], group_keys=False).apply(
    lambda g: g.sample(frac=0.10, random_state=42)
)
```

### 1b. Corpus coverage reporting template

```
CORPUS DESCRIPTION
─────────────────────────────────────
Source:         [Twitter Academic API / GDELT / Congressional Record / etc.]
Population:     [All English tweets containing #redlining, 2018–2022]
Total universe: N = [X] documents before filtering
Filters applied:
  - Language: English (langdetect confidence ≥ 0.95)
  - Duplicates: Removed N = [X] exact duplicates
  - Bots: Removed N = [X] accounts flagged by [Botometer / rule-based]
  - Short texts: Removed N = [X] documents with < 20 tokens
Final corpus:   N = [Y] documents ([Z]% of universe)
Time span:      [start date] to [end date]
Median doc length: [X] tokens (IQR: [lo]–[hi])
```

### 1c. Text preprocessing decisions (document them all)

| Decision | Options | Recommendation |
|----------|---------|----------------|
| Tokenization | whitespace / spaCy / NLTK / BPE | spaCy for English NLP; BPE for transformer models |
| Lowercasing | yes / no | Yes for bag-of-words; no for cased transformers |
| Stopword removal | yes / no | Yes for LDA/STM; no for BERT embeddings |
| Stemming / lemmatization | stem / lemma / none | Lemma (spaCy) if reducing vocab; none for transformers |
| Min token count | filter docs with < K tokens | K = 20 typical; K = 5 for tweets |
| Minimum document frequency | remove terms with df < N | df < 5 typical for LDA |
| URL / mention removal | yes / no | Yes for topic models; depends for social media tasks |

---

## 2. Annotation Codebook Structure

### 2a. Codebook template

```
ANNOTATION CODEBOOK — [Task Name]
Version: [1.0] | Date: [Date]

TASK OVERVIEW
  Goal:    [What are coders asked to judge?]
  Unit:    [sentence / paragraph / document / post]
  Format:  [binary yes/no / multi-class / ordinal 1–5 / span extraction]

CATEGORIES
  [For each category:]
  Label:       [name]
  Definition:  [precise operational definition]
  Indicators:  [observable signals that indicate this category]
  Examples:    [3 positive examples with explanation]
  Non-examples: [3 negative examples with explanation]
  Boundary cases: [ambiguous cases and how to resolve them]

DECISION RULES
  1. [Rule for handling ambiguous cases]
  2. [Rule for ties / equal probability]
  3. [Default category when uncertain]

QUALITY CONTROL
  Training set:   N = [X] pre-labeled items; review with senior coder before proceeding
  IRR check:      Double-code [20% / all] of sample; resolve with [majority / third coder]
  Ongoing checks: Re-calibrate every [100 / 500] items
```

### 2b. Annotation workflow in R and Python

```r
# R: compute IRR on annotation batches
library(irr)

# Load annotation matrix: rows = items, cols = coders
anno <- read.csv("data/annotations/batch1_coded.csv")
coder1 <- anno$coder_a
coder2 <- anno$coder_b

# Cohen's kappa (2 coders)
kappa2(cbind(coder1, coder2))

# Krippendorff's alpha (N coders, nominal)
# Expects matrix: rows = coders, cols = items
kripp.alpha(t(as.matrix(anno[, c("coder_a","coder_b","coder_c")])),
            method = "nominal")

# Weighted kappa for ordinal categories
kappa2(cbind(coder1, coder2), weight = "equal")   # linear weights
```

```python
from sklearn.metrics import cohen_kappa_score
import krippendorff
import numpy as np

# Cohen's kappa
kappa = cohen_kappa_score(coder1, coder2)
print(f"Cohen's κ = {kappa:.3f}")

# Krippendorff's alpha (handles missing values; recommended for published work)
# matrix: rows = coders, cols = items; NaN for missing
data_matrix = np.array([coder1, coder2, coder3], dtype=float)
alpha = krippendorff.alpha(reliability_data=data_matrix, level_of_measurement="nominal")
print(f"Krippendorff's α = {alpha:.3f}")
```

### 2c. Gold standard creation for LLM validation

```python
# After human annotation, create gold standard from adjudicated items
# Use majority vote or adjudicated labels

import pandas as pd
from scipy import stats

df_anno = pd.read_csv("data/annotations/adjudicated.csv")

# Majority vote gold standard (3 coders)
df_anno["gold"] = df_anno[["coder_a","coder_b","coder_c"]].mode(axis=1)[0]

# Save gold standard
gold = df_anno[["doc_id","text","gold"]]
gold.to_csv("data/annotations/gold_standard.csv", index=False)
print(f"Gold standard N = {len(gold)}")
print(gold["gold"].value_counts(normalize=True))
```

---

## 3. ML Train / Test / Validation: Extended Patterns

### 3a. Cross-validation for small datasets

```python
from sklearn.model_selection import StratifiedKFold, cross_val_score
from sklearn.metrics import f1_score, make_scorer

cv = StratifiedKFold(n_splits=5, shuffle=True, random_state=42)
f1_scorer = make_scorer(f1_score, average="macro")

scores = cross_val_score(model, X, y, cv=cv, scoring=f1_scorer)
print(f"CV Macro F1: {scores.mean():.3f} ± {scores.std():.3f}")
```

### 3b. Temporal / sequential split (text panel data)

```python
# Ensure no future information leaks into training set
df = df.sort_values("date").reset_index(drop=True)
n = len(df)
train_end = int(n * 0.70)
val_end   = int(n * 0.85)

df_train = df.iloc[:train_end]
df_val   = df.iloc[train_end:val_end]
df_test  = df.iloc[val_end:]

print(f"Train: {df_train.date.min()} – {df_train.date.max()} (N={len(df_train)})")
print(f"Val:   {df_val.date.min()} – {df_val.date.max()} (N={len(df_val)})")
print(f"Test:  {df_test.date.min()} – {df_test.date.max()} (N={len(df_test)})")
```

### 3c. Class imbalance handling

```python
from imblearn.over_sampling import SMOTE
from imblearn.pipeline import Pipeline as ImbPipeline
from sklearn.ensemble import RandomForestClassifier

# Option 1: SMOTE oversampling (tabular features)
sm = SMOTE(random_state=42)
X_res, y_res = sm.fit_resample(X_train, y_train)

# Option 2: Class weights (for most sklearn / PyTorch models)
from sklearn.utils.class_weight import compute_class_weight
weights = compute_class_weight("balanced", classes=np.unique(y_train), y=y_train)
class_weights = dict(zip(np.unique(y_train), weights))

# For transformers: pass class_weights to Trainer
from transformers import TrainingArguments, Trainer
import torch
class WeightedLossTrainer(Trainer):
    def compute_loss(self, model, inputs, return_outputs=False):
        labels = inputs.pop("labels")
        outputs = model(**inputs)
        logits = outputs.logits
        weight = torch.tensor(list(class_weights.values()),
                              dtype=torch.float, device=logits.device)
        loss = torch.nn.CrossEntropyLoss(weight=weight)(logits, labels)
        return (loss, outputs) if return_outputs else loss
```

### 3d. Full evaluation suite

```python
from sklearn.metrics import (classification_report, confusion_matrix,
                              roc_auc_score, average_precision_score,
                              f1_score, precision_recall_curve)
import matplotlib.pyplot as plt

def evaluate_classifier(y_true, y_pred, y_prob=None, labels=None):
    print("=== Classification Report ===")
    print(classification_report(y_true, y_pred, target_names=labels, digits=3))
    print(f"Macro F1:  {f1_score(y_true, y_pred, average='macro'):.3f}")
    print(f"Micro F1:  {f1_score(y_true, y_pred, average='micro'):.3f}")
    print("\nConfusion Matrix:")
    print(confusion_matrix(y_true, y_pred))
    if y_prob is not None and len(np.unique(y_true)) == 2:
        auc_roc = roc_auc_score(y_true, y_prob)
        auc_pr  = average_precision_score(y_true, y_prob)
        print(f"\nAUC-ROC: {auc_roc:.3f}")
        print(f"AUC-PR:  {auc_pr:.3f} (preferred for imbalanced classes)")

evaluate_classifier(y_test, y_pred, y_prob=y_prob[:, 1])
```

---

## 4. Network Study Design — Extended Templates

### 4a. Boundary specification decision flowchart

```
Is the full network observable?
  YES → Complete network (document coverage rate; missing tie assumption)
  NO  → Choose:
          Ego network: N seeds × K alters (document K; report heterogeneity in alter counts)
          Snowball sample: document waves and stopping rule
          RDS (Respondent-Driven Sampling): use RDS-II estimator; report recruitment chains

Is the network static or dynamic?
  Static: snapshot at T; document T clearly
  Dynamic: timestamped edges; define temporal window and resolution (day / week / month)
```

### 4b. Network descriptives reporting table

```
NETWORK DESCRIPTIVES
─────────────────────────────────────
Nodes:          N = [X] ([definition])
Edges:          E = [Y] ([definition])
Directed:       [yes / no]
Density:        [X.XXX] (proportion of possible ties observed)
Mean degree:    [X.X] (SD = [Y.Y]; range: [min]–[max])
Largest component: [X]% of nodes
Clustering coeff: [X.XXX] (mean local; global: [X.XXX])
Mean path length: [X.X] hops (among connected pairs)
Modularity (Q):  [X.XXX] (N = [K] communities, Louvain algorithm)
Temporal span:  [start] to [end]; [X] time steps
```

### 4c. ERGM specification template

```r
library(ergm)
# Null model (Bernoulli graph)
m0 <- ergm(net ~ edges)

# Structural effects
m1 <- ergm(net ~ edges + mutual + gwesp(0.5, fixed=TRUE) + gwdegree(0.5, fixed=TRUE))

# Node covariate effects
m2 <- ergm(net ~ edges + mutual + gwesp(0.5, fixed=TRUE)
           + nodefactor("race") + nodematch("race") + nodecov("education"))

# GOF assessment (must pass before interpreting)
gof_m2 <- gof(m2, GOF = ~ degree + espartners + distance + triadcensus)
plot(gof_m2)

# Markov chain diagnostics
mcmc.diagnostics(m2)
```

**ERGM convergence check:** MCMC chain must mix well (Geweke test p > 0.05; trace plots show stationarity). GOF must show simulated networks match observed on degree distribution, edge-wise shared partners, and geodesic distance.

---

## 5. ABM Design — ODD Protocol Template and SALib Sensitivity

### 5a. Full ODD template (fill-in)

```
ODD PROTOCOL — [Model Name]
Version: [1.0] | Date: [Date] | Platform: [NetLogo / Mesa / custom Python]

─── OVERVIEW ────────────────────────────────────────────────

Purpose:
  [What research question does this model address?]
  [What social process does it represent?]

Entities, state variables, and scales:
  Agent types:
    [AgentType1]: state vars = [list]; N = [X] initialized
    [AgentType2]: state vars = [list]; N = [Y] initialized
  Environment: [grid X×Y / network / continuous / none]
  Time steps:  [1 tick = 1 day / month / year]
  Spatial scale: [if grid: cell size = X; if network: see network spec]

─── DESIGN CONCEPTS ─────────────────────────────────────────

Basic principles:   [Theoretical grounding — cite paper(s)]
Emergence:          [What macro outcome should emerge? How will you know if it did?]
Adaptation:         [Do agents change behavior? Based on what signal?]
Fitness / objectives: [What are agents maximizing/minimizing, if anything?]
Prediction:         [Do agents predict future states? How?]
Sensing:            [What can agents observe? Local / global / network neighborhood?]
Interaction:        [How do agents interact? Direct / via environment / via network?]
Stochasticity:      [Where is randomness? Which distributions? Seeds?]
Collectives:        [Groups, firms, households — how are they represented?]
Observation:        [What is recorded? At what interval? Outputs?]

─── DETAILS ─────────────────────────────────────────────────

Initialization:
  [Specify starting state completely — enough for another researcher to replicate]
  N agents = [X]; initial state drawn from [distribution or empirical data]

Input data:
  [Any external data read at initialization or each step]

Submodels (describe each behavioral rule):
  1. [SubmodelName]: [step-by-step description]
  2. [SubmodelName]: [step-by-step description]
  ...
```

### 5b. SALib global sensitivity analysis

```python
from SALib.sample import saltelli, latin
from SALib.analyze import sobol, morris
import numpy as np

# Define parameter space
problem = {
    "num_vars": 4,
    "names":    ["threshold",    "rewiring_prob", "influence_decay", "n_agents"],
    "bounds":   [[0.05, 0.95],   [0.0, 0.5],      [0.1, 1.0],        [50, 500]]
}

# Saltelli sampling for Sobol indices (requires 2^k * (D+2) model runs)
param_values = saltelli.sample(problem, N=512, calc_second_order=True)

# Run model for each parameter combination (replace with actual model call)
Y = np.array([run_model(*p) for p in param_values])

# Sobol sensitivity indices
Si = sobol.analyze(problem, Y, print_to_console=True)
# S1: first-order (direct effect); ST: total-order (includes interactions)

# Morris screening (cheaper for many parameters)
param_morris = morris.sample(problem, N=100, num_levels=4)
Y_morris = np.array([run_model(*p) for p in param_morris])
Si_morris = morris.analyze(problem, param_morris, Y_morris, print_to_console=True)
# mu_star: importance ranking; sigma: nonlinearity / interaction
```

---

## 6. Reproducibility Checklist and Reporting

### 6a. Full reproducibility stack

```
Reproducibility Checklist
─────────────────────────────────────
[ ] All random seeds set (data split, model init, sampling, simulation)
[ ] Package versions locked:
      R:      renv::snapshot() → renv.lock committed to git
      Python: pip freeze > requirements.txt OR conda env export > environment.yml
[ ] sessionInfo() / platform info logged in output files
[ ] No absolute file paths (use relative paths or config file)
[ ] Raw data preserved read-only; all derived data reproducible from scripts
[ ] Scripts numbered in execution order (01_collect.py, 02_clean.R, ...)
[ ] Makefile or snakemake workflow for full pipeline
[ ] Docker/Singularity image (optional; required for GPU-dependent models)
[ ] Code + data deposited to GitHub + Zenodo (DOI before submission)
[ ] README describes: software requirements, execution order, expected outputs
[ ] Git tag for paper submission version: git tag -a v1.0 -m "Submitted to [Journal]"
```

### 6b. Computational Methods reporting table (NCS Reporting Summary)

```
Statistical Reporting Summary (Nature Computational Science)
─────────────────────────────────────────────────────────────
Sample size:
  How was sample size determined? [Power analysis / all available data / corpus construction rule]

Replication:
  Were experiments replicated? [Yes — [N] runs with different seeds; mean ± SD reported]

Randomization:
  How were samples/conditions allocated? [Random seed X; stratified by Y]

Blinding:
  Were evaluators blind to conditions? [Yes — human annotators unaware of model predictions]

Outliers:
  Were outliers excluded? [No / Yes — criterion: [rule]]

Statistical tests:
  [Paired t-test / Wilcoxon / bootstrap CI for model comparisons]

Software:
  [R [version], Python [version], key packages with versions]

Model evaluation:
  Primary metric: [F1 macro / AUC-ROC / RMSE]
  Held-out test set: N = [X] (not used for any tuning decisions)
  Cross-validation: [k-fold / temporal split / leave-one-out]
  Hyperparameter tuning: [grid search / random search / Optuna; on validation set only]
```

### 6c. Computing environment documentation

```python
# Paste at end of every notebook or script; saves to log file
import os, platform, sys, subprocess

def log_environment(outfile=os.path.join(os.environ.get("OUTPUT_ROOT", "output"), "compute_env.txt")):
    info = [
        f"Python: {sys.version}",
        f"Platform: {platform.platform()}",
        f"CPU: {platform.processor()}",
    ]
    try:
        gpu = subprocess.check_output(
            ["nvidia-smi", "--query-gpu=name,memory.total",
             "--format=csv,noheader"], text=True).strip()
        info.append(f"GPU: {gpu}")
    except FileNotFoundError:
        info.append("GPU: not available")
    with open(outfile, "w") as f:
        f.write("\n".join(info))
    print("\n".join(info))

log_environment()
```

```r
# R environment log
output_root <- Sys.getenv("OUTPUT_ROOT", "output")
sink(file.path(output_root, "compute_env.txt"))
sessionInfo()
sink()
```

---

## 7. Computational Methods Word-Count and Structure by Journal

| Journal | Computational Methods location | Required content | Word budget |
|---------|-------------------------------|-----------------|-------------|
| NCS | Full Methods after Results | Model architecture, hyperparameters, CV strategy, compute, code/data DOI, Reporting Summary | 1,500–3,000 words |
| Science Advances | STAR Methods in supplement | Same as NCS; brief overview in main text | Main: 300–500 words; STAR: unlimited |
| NHB | Methods after Results | Model details, validation, Reporting Summary, OSF pre-reg | 1,000–2,000 words |
| PNAS | Methods section | Key parameters, validation, data/code statement | 800–1,500 words |
| ASR (comp) | Data and Methods section | Validation details, IRR, appendix for full pipeline | 1,500–2,500 words |
| AJS (comp) | Data and Methods section | Model rationale + validation; full pipeline as appendix | 1,500–2,000 words |

---

## 8. Computational Claim × Design Validity Matrix

| Claim type | Key validity threat | Design solution | Reporting requirement |
|-----------|--------------------|-----------------|-----------------------|
| Measurement | Construct validity: does the model measure the concept? | Validate against gold standard (κ, correlation with validated scales, expert review) | Report κ / α; show face validity examples; correlate with established measures |
| Description | Corpus coverage / representativeness | Define population; document sampling; compare corpus to known population benchmarks | Report corpus composition; coverage rate; limitations of corpus |
| Prediction | Overfitting / leakage | Strict train/test split; temporal split for panel data; no test set peeking | Report test-set-only metrics; CI via bootstrap; compare to baseline |
| Causal | Measurement error in computed variable biases causal estimates | Use measurement-error-robust estimators; sensitivity analysis; validate measure first | Report validation step before causal analysis; discuss attenuation bias |
