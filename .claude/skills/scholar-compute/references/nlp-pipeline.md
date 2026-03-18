# NLP Pipeline Reference for Computational Social Science

## Text Preprocessing Decision Guide

### When to apply each step

| Step | Apply for | Skip for |
|------|-----------|---------|
| Lowercase | Most topic models; keyword matching | Sentiment (negation matters); NER |
| Remove punctuation | Bag-of-words models | Discourse analysis; syntax parsing |
| Remove stopwords | Topic models; keyword frequency | Stylometrics; language models |
| Stemming | Small corpora; vocabulary compression | Semantic analysis (use lemmatization instead) |
| Lemmatization | Preferred over stemming | Very large corpora where speed matters |
| Remove numbers | Topics; sentiment | Event detection; financial text |
| Remove HTML/URLs | Social media, web data | Always apply to web-scraped data |

### SpaCy NLP pipeline (comprehensive)
```python
import spacy
nlp = spacy.load("en_core_web_lg")  # or en_core_web_trf for transformer

def preprocess_spacy(text, remove_stop=True, lemmatize=True, pos_filter=None):
    """
    pos_filter: e.g., ["NOUN","VERB","ADJ"] to keep only specific POS
    """
    doc = nlp(text)
    tokens = []
    for token in doc:
        if token.is_space or token.is_punct: continue
        if remove_stop and token.is_stop: continue
        if token.is_alpha is False: continue
        if pos_filter and token.pos_ not in pos_filter: continue
        word = token.lemma_.lower() if lemmatize else token.text.lower()
        tokens.append(word)
    return tokens
```

---

## STM (Structural Topic Model) Full Workflow

```r
library(stm)
library(quanteda)
library(tidyverse)

# ── 1. Build document-feature matrix ─────────────────────────────
corp <- corpus(df, text_field = "text")
toks <- tokens(corp,
               remove_punct = TRUE, remove_numbers = TRUE,
               remove_symbols = TRUE, remove_url = TRUE) %>%
        tokens_tolower() %>%
        tokens_remove(stopwords("en")) %>%
        tokens_wordstem()
dfm  <- dfm(toks) %>%
        dfm_trim(min_docfreq = 5, min_termfreq = 10)
out  <- convert(dfm, to = "stm")

# ── 2. Select K using searchK ─────────────────────────────────────
# Run on a random 20% sample to save time
set.seed(42)
idx <- sample(1:nrow(out$documents), round(0.2*nrow(out$documents)))
kresult <- searchK(out$documents[idx], out$vocab,
                   K = c(5, 10, 15, 20, 25, 30),
                   prevalence = ~ year + group,
                   data = out$meta[idx, ],
                   init.type = "Spectral")
plot(kresult)
# Choose K that maximizes held-out likelihood + semantic coherence

# ── 3. Fit final STM ──────────────────────────────────────────────
K <- 20
model <- stm(out$documents, out$vocab, K = K,
             prevalence = ~ year + s(year) + group,
             content   = ~ group,          # optional: words differ by group
             data      = out$meta,
             init.type = "Spectral",
             seed = 42,
             verbose = FALSE)

# ── 4. Label topics ───────────────────────────────────────────────
# FREX words (frequent + exclusive) are best for labeling
labelTopics(model, n = 10)
# Read top documents per topic for human labeling
findThoughts(model, texts = out$meta$text,
             n = 5, topics = 1:K)

# ── 5. Estimate covariate effects ─────────────────────────────────
effects <- estimateEffect(1:K ~ year + group, model,
                           meta = out$meta,
                           uncertainty = "Global")
# Plot prevalence over time for topic 5
plot(effects, covariate = "year", topics = 5,
     method = "continuous",
     xlab = "Year", main = "Topic 5 Prevalence Over Time")
# Plot group difference for topic 5
plot(effects, covariate = "group", topics = 5,
     method = "difference",
     cov.value1 = "A", cov.value2 = "B")
```

---

## BERT Text Classification Workflow

```python
from datasets import Dataset
from transformers import (AutoTokenizer, AutoModelForSequenceClassification,
                          TrainingArguments, Trainer)
import numpy as np
from sklearn.metrics import classification_report, roc_auc_score
import torch

MODEL_NAME = "roberta-base"

# ── 1. Prepare data ────────────────────────────────────────────────
tokenizer = AutoTokenizer.from_pretrained(MODEL_NAME)

def tokenize_fn(examples):
    return tokenizer(examples["text"], truncation=True,
                     padding="max_length", max_length=256)

train_ds = Dataset.from_pandas(train_df[["text","label"]])
val_ds   = Dataset.from_pandas(val_df[["text","label"]])
test_ds  = Dataset.from_pandas(test_df[["text","label"]])

train_ds = train_ds.map(tokenize_fn, batched=True)
val_ds   = val_ds.map(tokenize_fn, batched=True)
test_ds  = test_ds.map(tokenize_fn, batched=True)

# ── 2. Load model ──────────────────────────────────────────────────
model = AutoModelForSequenceClassification.from_pretrained(
    MODEL_NAME, num_labels=2)

# ── 3. Train ───────────────────────────────────────────────────────
def compute_metrics(eval_pred):
    logits, labels = eval_pred
    preds = np.argmax(logits, axis=-1)
    proba = torch.softmax(torch.tensor(logits), dim=-1).numpy()[:,1]
    report = classification_report(labels, preds, output_dict=True)
    return {"f1": report["weighted avg"]["f1-score"],
            "auc": roc_auc_score(labels, proba)}

args = TrainingArguments(
    output_dir="./clf_output",
    num_train_epochs=3,
    per_device_train_batch_size=16,
    per_device_eval_batch_size=32,
    warmup_ratio=0.1,
    evaluation_strategy="epoch",
    save_strategy="epoch",
    load_best_model_at_end=True,
    metric_for_best_model="f1",
    fp16=torch.cuda.is_available(),
    seed=42
)

trainer = Trainer(model=model, args=args,
                  train_dataset=train_ds, eval_dataset=val_ds,
                  compute_metrics=compute_metrics)
trainer.train()

# ── 4. Evaluate on held-out test set ──────────────────────────────
test_preds = trainer.predict(test_ds)
print(classification_report(test_ds["label"],
                             np.argmax(test_preds.predictions, axis=-1)))
```

---

## Human Validation Protocol

Required for NCS/Science Advances; strongly recommended for all computational classification:

```python
import random
import pandas as pd

# Sample 200 documents for human annotation
random.seed(42)
sample_idx = random.sample(range(len(df)), 200)
sample_df = df.iloc[sample_idx][["id","text"]].copy()
sample_df.to_csv("human_annotation_sample.csv", index=False)

# Two annotators code independently → merge → compute agreement
from sklearn.metrics import cohen_kappa_score
kappa = cohen_kappa_score(coder1_labels, coder2_labels)
print(f"Cohen's κ = {kappa:.3f}")  # Target: ≥ 0.70

# Reporting template:
# "Two trained research assistants independently coded a random sample
# of N=200 documents. Inter-rater reliability was κ = [X] (Cohen 1960),
# indicating [substantial/near-perfect] agreement. Disagreements were
# resolved by [adjudication / majority rule]."
```

---

## Word Embedding Applications

### Measuring Semantic Change Over Time
```python
from gensim.models import Word2Vec
import numpy as np

# Train separate models per decade
def train_model(texts, seed=42):
    sentences = [t.split() for t in texts]
    return Word2Vec(sentences, vector_size=100, window=5,
                    min_count=10, workers=4, seed=seed, epochs=10)

models = {}
for decade in [1980, 1990, 2000, 2010, 2020]:
    decade_texts = df[df.decade == decade].text.tolist()
    models[decade] = train_model(decade_texts)

# Align models using Procrustes rotation (required for comparison)
# Use: https://github.com/williamleif/histwords or gensim.test.utils

# Measure semantic drift of "immigrant" over decades
def cosine_sim(v1, v2):
    return np.dot(v1, v2) / (np.linalg.norm(v1) * np.linalg.norm(v2))

# After alignment:
for decade in [1990, 2000, 2010, 2020]:
    if "immigrant" in models[decade].wv:
        sim = cosine_sim(models[1980].wv["immigrant"],
                         models[decade].wv["immigrant"])
        print(f"{decade}: cosine similarity to 1980 = {sim:.3f}")
```

### Cultural Dimensions via Word Embeddings (FrameAxis)
```python
# Measure how biased a concept is along a cultural dimension
# (e.g., competence vs. warmth; masculine vs. feminine)
def framaxis_score(word, positive_pole, negative_pole, model):
    """
    positive_pole: list of seed words for + end (e.g., ["competent","skilled"])
    negative_pole: list of seed words for - end (e.g., ["incompetent","unskilled"])
    """
    pos_vecs = [model.wv[w] for w in positive_pole if w in model.wv]
    neg_vecs = [model.wv[w] for w in negative_pole if w in model.wv]
    if word not in model.wv or not pos_vecs or not neg_vecs:
        return None
    word_vec = model.wv[word]
    pos_sim = np.mean([cosine_sim(word_vec, v) for v in pos_vecs])
    neg_sim = np.mean([cosine_sim(word_vec, v) for v in neg_vecs])
    return pos_sim - neg_sim  # positive = biased toward positive pole
```

---

## Embedding Regression (conText) — Full Reference Workflow

Rodriguez, Spirling & Stewart (2022, APSR). Tests how word meaning varies across document-level covariates using "a la carte" embeddings (Khodak et al. 2018) + OLS regression on the resulting dense vectors. Inference via bootstrap / permutation.

### Installation and Required Objects

```r
install.packages("conText")
library(conText); library(quanteda); library(dplyr)

# Three required objects:
# 1. A quanteda corpus with docvars (covariates on each document)
# 2. Pre-trained GloVe embeddings — bundled: cr_glove_subset
#    For your own corpus: download GloVe from https://nlp.stanford.edu/projects/glove/
#    and load with: glove <- as.matrix(read.table("glove.6B.300d.txt"))
# 3. Transformation matrix — bundled: cr_transform
#    (cr_transform is fit on Congressional Record; re-fit for other domains
#     using khodakA estimation on your corpus if needed)
```

### Step 1 — Prepare Corpus

```r
toks <- tokens(corpus_obj,
               remove_punct=TRUE, remove_symbols=TRUE,
               remove_numbers=TRUE, remove_url=TRUE) |>
        tokens_tolower()
toks_nostop <- tokens_select(toks, stopwords("en"),
                             selection="remove", min_nchar=3)
feats <- dfm(toks_nostop) |> dfm_trim(min_termfreq=5) |> featnames()
toks_clean <- tokens_select(toks_nostop, feats, padding=TRUE)
# padding=TRUE is required — preserves position information for context windows
```

### Step 2 — Extract Contexts Around Target

```r
# Glob pattern: "immigr*" matches immigr, immigrant, immigrants, immigration, ...
# window = tokens on each side; 6L is the standard from Rodriguez et al.
target_toks <- tokens_context(x=toks_clean, pattern="immigr*", window=6L)
cat("N contexts:", ndoc(target_toks), "\n")

# Multiple keywords simultaneously:
multi_toks <- tokens_context(x=toks_clean,
                             pattern=c("immigration", "welfare", "economy"),
                             window=6L)
```

### Step 3 — Build Document-Embedding Matrix (DEM)

```r
target_dfm <- dfm(target_toks)
target_dem <- dem(x=target_dfm,
                  pre_trained=cr_glove_subset,
                  transform=TRUE,
                  transform_matrix=cr_transform,
                  verbose=TRUE)
# Each row of target_dem is a D-dimensional context embedding
# Dimensions = embedding dimensions (e.g., 300 for GloVe-300d)
```

### Step 4 — Group-Specific Embeddings

```r
# Average embeddings within each group → one vector per group level
target_wv_party <- dem_group(target_dem, groups=target_dem@docvars$party)
# Result: a matrix with one row per group, D columns

# Single corpus-wide embedding:
target_wv_all <- matrix(colMeans(target_dem), ncol=ncol(target_dem)) |>
                 `rownames<-`("all")
```

### Step 5 — Nearest Neighbors

```r
# Top N words from the corpus vocabulary with highest cosine similarity
nns_results <- nns(target_wv_party,
                   pre_trained=cr_glove_subset,
                   N=10,
                   candidates=target_wv_party@features,  # restrict to observed vocab
                   as_list=TRUE)
nns_results[["R"]]   # Republican nearest neighbors (cosine sim)
nns_results[["D"]]   # Democrat nearest neighbors

# With stemming (groups word forms: reform/reforms/reformed)
nns_stem <- nns(target_wv_party, pre_trained=cr_glove_subset, N=10,
                candidates=feats, stem=TRUE, as_list=TRUE)
```

### Step 6 — Cosine Similarity to Specific Concepts

```r
# Test specific hypotheses: is "immigration" semantically closer to
# "enforcement" for Republicans or "reform" for Democrats?
cos_sim(target_wv_party,
        pre_trained=cr_glove_subset,
        features=c("reform","enforcement","crime","family","economy"),
        as_list=FALSE)
# Returns: matrix [group × feature] of cosine similarities (0 to 1)
```

### Step 7 — NNS Ratio (Partisan Distinctiveness)

```r
# For each word in the vocabulary, compute:
#   ratio = cosine_sim(word, R_embedding) / cosine_sim(word, D_embedding)
# Values > 1: word more associated with Republicans
# Values < 1: word more associated with Democrats
nns_ratio(x=target_wv_party, N=10, numerator="R",
          candidates=target_wv_party@features,
          pre_trained=cr_glove_subset)
```

### Step 8 — Nearest Contexts (Readable Interpretation)

```r
# Returns the actual context strings (surrounding text) most similar
# to each group's embedding — enables qualitative reading
ncs_results <- ncs(x=target_wv_party,
                   contexts_dem=target_dem,
                   contexts=target_toks,
                   N=5, as_list=TRUE)
```

### Step 9 — Embedding Regression with Statistical Inference

```r
# OLS regression: context embeddings ~ covariates
# bootstrap=TRUE: confidence intervals via bootstrapped samples
# permute=TRUE:   p-values via permutation test of the covariate
model_ctx <- conText(
  formula          = immigr* ~ party + year,
  data             = corpus_obj,
  pre_trained      = cr_glove_subset,
  transform        = TRUE,
  transform_matrix = cr_transform,
  bootstrap        = TRUE,
  num_bootstraps   = 200,
  permute          = TRUE,
  num_permutations = 200,
  window           = 6L,
  valuetype        = "glob",
  verbose          = FALSE
)

# normed_betas: norm of the regression coefficient vector per covariate
# Larger norm = greater semantic shift attributable to that covariate
# Columns: normed_beta, lower_ci, upper_ci, p_value
print(model_ctx@normed_betas)

# Save
saveRDS(model_ctx, "${OUTPUT_ROOT}/models/context-embedding-model.rds")
```

### Step 10 — Figures

```r
# NNS comparison bar chart (side-by-side, one bar per group)
library(ggplot2)

nns_df <- bind_rows(
  lapply(names(nns_results), function(g)
    data.frame(group=g, word=nns_results[[g]]$feature,
               sim=nns_results[[g]]$value))
)

p_nns <- ggplot(nns_df, aes(x=reorder(word,sim), y=sim, fill=group)) +
  geom_col(position="dodge") +
  coord_flip() +
  scale_fill_manual(values=c("#0072B2","#D55E00")) +
  labs(x=NULL, y="Cosine Similarity", fill="Party") +
  facet_wrap(~group, scales="free_y") +
  theme_Publication()
ggsave("${OUTPUT_ROOT}/figures/fig-nns-party.pdf", p_nns,
       device=cairo_pdf, width=8, height=5)

# Normed betas plot
betas_df <- as.data.frame(model_ctx@normed_betas)
betas_df$covariate <- rownames(betas_df)

p_beta <- ggplot(betas_df, aes(x=covariate, y=normed_beta,
                               ymin=lower_ci, ymax=upper_ci)) +
  geom_point(size=3) +
  geom_errorbar(width=0.2) +
  geom_hline(yintercept=0, linetype="dashed", color="gray50") +
  labs(x=NULL, y="Normed β (95% CI)") +
  theme_Publication()
ggsave("${OUTPUT_ROOT}/figures/fig-context-regression.pdf", p_beta,
       device=cairo_pdf, width=5, height=3.5)
```

### Reporting Standards

**Required in Methods**:
- Target word(s) and glob pattern
- Context window size (default: 6)
- Pre-trained embeddings source (GloVe version, dimensions)
- Whether domain-specific transformation matrix was used
- Number of bootstrap / permutation iterations
- N contexts per group

**Reporting template:**
> "We apply embedding regression (Rodriguez, Spirling, and Stewart 2022) using the `conText` R package to test whether the semantic meaning of *[target word]* varies by [covariate]. For each instance of *[target word]* in the corpus, we extract a ±6 token context window and compute an 'a la carte' context embedding using 300-dimensional GloVe vectors (Pennington et al. 2014) and the Khodak transformation matrix. We regress context embeddings on [covariates] via OLS; statistical inference uses [200] bootstrap iterations and [200] permutation tests. The normed regression coefficient for [party] is [X] (95% CI = [[lo], [hi]], p = [p]), indicating that [interpretation of semantic shift]."

---

## LLM-Based Annotation — Full Reference

### When to Use vs. Human Annotation

| Scenario | Recommendation |
|----------|---------------|
| N < 500 documents, theory-driven codes | Human annotation only |
| N = 500–5,000, straightforward codes | Human + LLM (benchmark κ first) |
| N > 5,000, well-defined categories | LLM annotation (benchmark on 200-doc sample) |
| Nuanced / interpretive codes | Human annotation; LLM as pre-screener only |

### Annotation Workflow

```python
import anthropic, json, time, pandas as pd
from sklearn.metrics import cohen_kappa_score

client = anthropic.Anthropic()   # export ANTHROPIC_API_KEY="..."

# ── 1. Design prompt ─────────────────────────────────────────────────
# Be specific: define the construct, give clear decision rules, provide
# 1-2 examples in the prompt if few-shot
SYSTEM_PROMPT = """You are a social science research assistant.
Code each news article for ONE dimension:
  Threat frame (threat): Does the article primarily frame [topic] as a threat
  to public safety, economic security, or national identity?
  Code 1 = yes; 0 = no.
Respond ONLY with valid JSON: {"label": 0_or_1, "confidence": "high|medium|low", "rationale": "one sentence max"}
Do not add any text outside the JSON object."""

def annotate_one(text, model="claude-sonnet-4-6", max_tokens=120):
    resp = client.messages.create(
        model=model, max_tokens=max_tokens,
        system=SYSTEM_PROMPT,
        messages=[{"role":"user","content":f"Article:\n{text[:3000]}"}]
    )
    return json.loads(resp.content[0].text)

# ── 2. Benchmark on 200-doc human sample first ───────────────────────
sample = pd.read_csv("human_annotation_sample.csv")   # columns: id, text, human_label
llm_on_sample = []
for _, row in sample.iterrows():
    res = annotate_one(row["text"])
    llm_on_sample.append({"id": row["id"], "llm_label": res["label"],
                           "confidence": res["confidence"]})
    time.sleep(0.5)

sample = sample.merge(pd.DataFrame(llm_on_sample), on="id")
kappa  = cohen_kappa_score(sample["human_label"], sample["llm_label"])
print(f"LLM vs. human κ = {kappa:.3f}")
# Proceed only if κ ≥ 0.70; otherwise revise prompt or switch to human annotation

# ── 3. Annotate full corpus ──────────────────────────────────────────
results = []
for i, row in df.iterrows():
    try:
        res = annotate_one(row["text"])
        results.append({"id": row["id"], **res})
    except Exception as e:
        results.append({"id": row["id"], "label": None, "confidence": None,
                        "rationale": None, "error": str(e)})
    if i > 0 and i % 100 == 0:
        time.sleep(2)    # rate limiting

annotations = pd.DataFrame(results)

# ── 4. Handle low-confidence items ──────────────────────────────────
low_conf = annotations[annotations["confidence"]=="low"]
print(f"{len(low_conf)} low-confidence items → manual review recommended")
# Options: (a) human review of low-confidence items; (b) re-prompt with context
annotations.to_csv("${OUTPUT_ROOT}/tables/llm-annotations.csv", index=False)

# ── 5. Cost estimation ───────────────────────────────────────────────
# Run this BEFORE full annotation
avg_in_tokens  = 650   # ~500 text + ~150 prompt
avg_out_tokens = 40
# Current pricing (check https://anthropic.com/pricing):
# claude-sonnet-4-6: $3/MTok in, $15/MTok out
cost = len(df) * (avg_in_tokens * 3 + avg_out_tokens * 15) / 1_000_000
print(f"Estimated cost: ${cost:.2f} for {len(df):,} documents")
```

### Reporting Requirements

**In Methods:**
- LLM model name + version + date of annotation (model behavior can change)
- Full prompt text (in supplementary)
- N documents in benchmark sample; human annotator description (training, instructions)
- Cohen's κ on benchmark sample
- How low-confidence items were handled

**Reporting template:**
> "We annotated N = [X] documents using [Claude Sonnet 4.6] (accessed [month year]) with a structured zero-shot prompt (see Supplementary Text S1). To validate this approach, two trained research assistants independently coded a random sample of N = 200 documents (κ_human = [X]). We then applied the same coding instructions to the LLM; agreement with human consensus labels was κ = [X], indicating [substantial/near-perfect] agreement. We therefore applied LLM annotation to the full corpus. Items coded with low confidence (N = [X], [X]%) were manually reviewed by [coder description]."

---

## LLM Annotation Epistemic Risk Checklist (Lin & Zhang 2025)

Lin, H., & Zhang, Y. (2025). Navigating the risks of using large language models for text annotation in social science research. *Social Science Computer Review*. DOI: 10.1177/08944393251366243.

The paper identifies four epistemic risks that must be addressed before using LLMs as annotators in social science research:

### Risk 1 — Validity

*Definition*: The LLM may operationalize a proxy construct rather than the intended theoretical concept.

**Mitigation checklist**:
- [ ] Pilot on 50 documents; manually review LLM rationale for each
- [ ] Compare nearest semantic neighbors of the construct across LLM and human annotation
- [ ] Ensure the annotation prompt is grounded in the study's theoretical definition, not a lay definition
- [ ] For complex sociological constructs (e.g., "threat frame," "legitimate violence"), include 2–3 positive and 2–3 negative examples in the prompt (few-shot)

### Risk 2 — Reliability

*Definition*: Labels vary across runs, model versions, prompt wordings, or context window positions.

**Mitigation checklist**:
- [ ] Set `temperature=0` for all production annotation calls (deterministic output)
- [ ] Re-annotate a 50-document subsample a second time; compute run-to-run κ
- [ ] Report run-to-run κ alongside human-benchmark κ
- [ ] Test sensitivity to prompt wording: run 2–3 prompt variants on 50 docs; choose the one with highest human agreement

```python
# Run-to-run reliability check
import time
from sklearn.metrics import cohen_kappa_score

subsample = df.sample(50, random_state=42)

run1 = [annotate_one(t)["label"] for t in subsample["text"]]
time.sleep(5)
run2 = [annotate_one(t)["label"] for t in subsample["text"]]

print(f"Run-to-run κ: {cohen_kappa_score(run1, run2):.3f}")
# Target: κ ≥ 0.80 for run-to-run (deterministic at temperature=0 should be near 1.0)
# If κ < 0.80 at temperature=0: check for context-length truncation or API instability
```

### Risk 3 — Replicability

*Definition*: Future researchers cannot reproduce the same annotations because the model has been updated, retrained, or discontinued.

**Mitigation checklist**:
- [ ] Record the **exact model ID** including version suffix (e.g., `claude-sonnet-4-6`, `gpt-4.1-mini`, `gpt-5-nano`)
- [ ] Record the **date of annotation** (model behavior can change across releases without version change)
- [ ] Archive the **full system prompt and user prompt** verbatim (as supplementary appendix)
- [ ] Save raw LLM outputs (full JSON response, not just derived label) to a CSV alongside the dataset
- [ ] Deposit the saved outputs at a persistent repository (Zenodo, OSF, Harvard Dataverse) with a DOI

```python
import datetime, json, pandas as pd

# Always record these fields in your annotation output
ANNOT_METADATA = {
    "model":       "claude-sonnet-4-6",
    "annot_date":  datetime.date.today().isoformat(),   # "2026-02-23"
    "temperature": 0,
    "system_prompt_hash": None   # fill with hashlib.sha256 of SYSTEM_PROMPT
}

import hashlib
ANNOT_METADATA["system_prompt_hash"] = (
    hashlib.sha256(SYSTEM_PROMPT.encode()).hexdigest()[:16])

# Save metadata alongside results
with open("${OUTPUT_ROOT}/tables/llm-annotation-metadata.json", "w") as f:
    json.dump(ANNOT_METADATA, f, indent=2)
```

### Risk 4 — Transparency

*Definition*: The annotation process is opaque to readers, reviewers, and replicators.

**Mitigation checklist**:
- [ ] Disclose **all prompts** (system + user) in the supplementary appendix — not a summary, the verbatim text
- [ ] Report the benchmark design: who are the human coders? what were their instructions? how were disagreements resolved?
- [ ] Acknowledge known limitations of the specific LLM for this task (e.g., language coverage, cultural context, political bias)
- [ ] If the annotation was done for a politically sensitive construct (race, crime, immigration), explicitly note potential LLM political leanings and mitigation steps
- [ ] Provide a data/code repository link where readers can run the annotation pipeline on the same sample

### Summary Checklist (pre-submission)

```
LLM ANNOTATION EPISTEMIC RISK AUDIT (Lin & Zhang 2025)
========================================================

VALIDITY
[ ] Pilot on ≥50 docs; LLM rationale reviewed for construct validity
[ ] Few-shot examples included for theoretically complex constructs
[ ] Annotation prompt grounded in paper's theoretical definition

RELIABILITY
[ ] temperature=0 used for all production annotation
[ ] Run-to-run κ ≥ 0.80 confirmed on 50-doc subsample
[ ] Prompt wording tested and selected for highest human agreement

REPLICABILITY
[ ] Exact model ID + annotation date recorded
[ ] Full prompt archived verbatim (supplementary)
[ ] Raw LLM outputs saved to CSV (not just derived labels)
[ ] Outputs deposited at persistent repository with DOI

TRANSPARENCY
[ ] All prompts reproduced in supplementary appendix
[ ] Human benchmark described (N, coder qualifications, instructions, adjudication)
[ ] Known LLM limitations and potential biases acknowledged
[ ] Repository URL for annotation code provided in paper
```
