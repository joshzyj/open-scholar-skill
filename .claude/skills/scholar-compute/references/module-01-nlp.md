## MODULE 1: Text-as-Data / NLP

### Step 1 — Preprocessing

Choose preprocessing steps based on the downstream task. Do NOT apply all steps indiscriminately.

| Step | Apply for | Skip for |
|------|-----------|---------|
| Lowercase | Topic models, keyword matching | Sentiment, NER, transformers |
| Remove punctuation | Bag-of-words | Discourse analysis, syntax |
| Remove stopwords | Topic models, frequency | Stylometrics, language models |
| Lemmatization | Topic models, embedding regression | Character-level models |
| Remove URLs/HTML | Social media, web data | Always apply for scraped data |

**spaCy pipeline (R: use quanteda; Python: use spaCy):**

```python
import spacy
nlp = spacy.load("en_core_web_lg")

def preprocess(text, remove_stop=True, lemmatize=True, pos_keep=None):
    doc = nlp(text)
    tokens = []
    for tok in doc:
        if tok.is_space or tok.is_punct or not tok.is_alpha: continue
        if remove_stop and tok.is_stop: continue
        if pos_keep and tok.pos_ not in pos_keep: continue
        tokens.append(tok.lemma_.lower() if lemmatize else tok.text.lower())
    return tokens
```

---

### Step 2 — Method Selection

| Goal | Method | Package |
|------|--------|---------|
| Topic prevalence + covariates | **STM** | `stm` (R) — social science standard |
| Dynamic topics | BERTopic | `bertopic` (Python) |
| Sentiment / tone | VADER (social media), RoBERTa | `vaderSentiment`, `transformers` |
| Text classification | Fine-tuned BERT/RoBERTa | `transformers` |
| Semantic similarity | Sentence-BERT embeddings | `sentence-transformers` |
| Named entity recognition | spaCy NER | `spacy` |
| Semantic change over time | Word2Vec per period (aligned) | `gensim` |
| **How word meaning varies by covariate** | **Embedding Regression (conText)** | `conText` (R) |
| **Automated annotation at scale** | **LLM annotation (GPT-4/Claude)** | `openai`, `anthropic` |
| Stance / framing | Fine-tuned classifier or FrameAxis | `transformers` |

---

### Step 3 — Structural Topic Model (STM)

STM is the social science standard for topic modeling: covariates can influence both topic prevalence and topic content.

```r
library(stm); library(quanteda); library(tidyverse)

# 1. Build DFM
corp <- corpus(df, text_field = "text")
toks <- tokens(corp, remove_punct=TRUE, remove_numbers=TRUE,
               remove_symbols=TRUE, remove_url=TRUE) |>
        tokens_tolower() |>
        tokens_remove(stopwords("en")) |>
        tokens_wordstem()
dfm  <- dfm(toks) |> dfm_trim(min_docfreq=5, min_termfreq=10)
out  <- convert(dfm, to="stm")

# 2. Select K via held-out likelihood + semantic coherence
set.seed(42)
idx     <- sample(seq_len(nrow(out$documents)), round(0.2*nrow(out$documents)))
kresult <- searchK(out$documents[idx], out$vocab,
                   K = c(5,10,15,20,25,30),
                   prevalence = ~ year + group,
                   data = out$meta[idx,], init.type="Spectral")
plot(kresult)   # choose K maximizing held-out likelihood + coherence

# 3. Fit final model
K     <- 20     # replace with chosen K
model <- stm(out$documents, out$vocab, K=K,
             prevalence = ~ year + s(year) + group,
             data = out$meta, init.type="Spectral", seed=42)

# 4. Label topics (FREX = frequent AND exclusive)
labelTopics(model, n=10)
findThoughts(model, texts=out$meta$text, n=5, topics=1:K)

# 5. Estimate covariate effects
effects <- estimateEffect(1:K ~ year + group, model,
                          meta=out$meta, uncertainty="Global")
plot(effects, covariate="year", topics=5, method="continuous")
plot(effects, covariate="group", topics=5, method="difference",
     cov.value1="A", cov.value2="B")
```

**Required reporting**: K selection plot (held-out likelihood vs. K); topic labels (FREX words + top documents); human validation of ≥20 docs per topic; covariate effects plot.

---

### Step 3b — BERTopic: Dynamic and Hierarchical Topic Models

**When to use over STM**: When you need (a) topic evolution over time without pre-specifying temporal bins, (b) hierarchical topic trees from general → specific, or (c) very large corpora (>100K docs) where STM is slow. BERTopic uses transformer embeddings + HDBSCAN clustering; it does not natively estimate covariate effects on topic prevalence (use STM for that).

```python
from bertopic import BERTopic
from bertopic.representation import KeyBERTInspired, MaximalMarginalRelevance
from umap import UMAP
from hdbscan import HDBSCAN
import pandas as pd

# ── 1. Configure sub-models ─────────────────────────────────────────
umap_model  = UMAP(n_neighbors=15, n_components=5,
                   min_dist=0.0, metric="cosine", random_state=42)
hdbscan_model = HDBSCAN(min_cluster_size=50, metric="euclidean",
                         cluster_selection_method="eom", prediction_data=True)
representation_model = MaximalMarginalRelevance(diversity=0.3)

# ── 2. Fit BERTopic ──────────────────────────────────────────────────
topic_model = BERTopic(
    umap_model           = umap_model,
    hdbscan_model        = hdbscan_model,
    representation_model = representation_model,
    min_topic_size       = 50,       # minimum documents per topic
    nr_topics            = "auto",   # or set integer K
    calculate_probabilities = False, # set True if you need soft assignments
    verbose              = True
)
topics, probs = topic_model.fit_transform(docs)  # docs: list of strings

# ── 3. Inspect topics ────────────────────────────────────────────────
topic_info = topic_model.get_topic_info()
print(topic_info.head(20))
# Topic -1 = outlier/noise documents — report N and percentage

# Get top terms per topic
for t in topic_model.get_topic_freq()["Topic"][:10]:
    print(f"\nTopic {t}:", topic_model.get_topic(t)[:10])

# ── 4. Hierarchical topic reduction ──────────────────────────────────
# Merge similar topics into a coarser hierarchy
hierarchical_topics = topic_model.hierarchical_topics(docs)
topic_model.visualize_hierarchy().write_html("${OUTPUT_ROOT}/figures/bertopic-hierarchy.html")

# Reduce to K topics (coarser)
topic_model.reduce_topics(docs, nr_topics=20)

# ── 5. Dynamic topic modeling (topics over time) ──────────────────────
# timestamps: list of date strings or datetime objects, same length as docs
topics_over_time = topic_model.topics_over_time(
    docs, timestamps, nr_bins=20, global_tuning=True, evolution_tuning=True
)
fig = topic_model.visualize_topics_over_time(topics_over_time, top_n_topics=10)
fig.write_html("${OUTPUT_ROOT}/figures/bertopic-over-time.html")
fig.write_image("${OUTPUT_ROOT}/figures/bertopic-over-time.pdf")

# ── 6. Save model and results ─────────────────────────────────────────
topic_model.save("${OUTPUT_ROOT}/models/bertopic-model")
topic_info.to_csv("${OUTPUT_ROOT}/tables/bertopic-topic-info.csv", index=False)

# Assign topic labels to documents
docs_df = pd.DataFrame({"doc": docs, "topic": topics,
                         "topic_label": [topic_model.get_topic(t)[0][0]
                                          if t != -1 else "outlier" for t in topics]})
docs_df.to_csv("${OUTPUT_ROOT}/tables/bertopic-doc-assignments.csv", index=False)
```

**Required reporting**: K (number of topics + % outlier documents); top terms per topic; human validation (read ≥20 docs per top topic); if dynamic: evolution figure; if hierarchical: hierarchy figure saved as HTML + PDF.

**Reporting template:**
> "We fit a BERTopic model (Grootendorst 2022) to [N] documents using sentence transformer embeddings (all-MiniLM-L6-v2), UMAP dimensionality reduction (n_neighbors = 15, n_components = 5), and HDBSCAN clustering (min_cluster_size = 50). The model identified [K] topics; [X]% of documents were classified as outliers (topic −1). We applied dynamic topic modeling with [20] temporal bins to track topic prevalence over [time period]. Topic labels were assigned based on the top 10 most representative terms; two authors reviewed the top 20 documents per topic to validate interpretations."

---

### Step 3c — Text Scaling: Wordfish and Wordscores

**When to use**: You want to place documents or actors on a latent ideological or policy dimension (e.g., party manifestos, legislative speeches, editorial positions) without pre-labeling a dimension. Wordfish (Slapin & Proksch 2008) estimates document positions purely from word frequencies. Wordscores (Laver, Benoit & Garry 2003) maps new documents onto positions estimated from anchor/reference texts.

```r
library(quanteda)
library(quanteda.textmodels)
library(quanteda.textplots)
library(ggplot2)

# ── Wordfish: unsupervised scaling ───────────────────────────────────
corp  <- corpus(df, text_field = "text", docvars = df[, meta_cols])
toks  <- tokens(corp, remove_punct=TRUE, remove_numbers=TRUE) |>
          tokens_tolower() |>
          tokens_remove(stopwords("en"))
dfmat <- dfm(toks) |> dfm_trim(min_termfreq=10, min_docfreq=5)

# Fit Wordfish; dir = reference documents to anchor pole direction
# dir[1] = document expected to score low; dir[2] = expected to score high
wf_model <- textmodel_wordfish(dfmat, dir=c(1, nrow(dfmat)))

# Extract document positions with 95% CIs
positions <- data.frame(
  doc     = docnames(dfmat),
  theta   = wf_model$theta,
  se      = wf_model$se.theta,
  lower   = wf_model$theta - 1.96 * wf_model$se.theta,
  upper   = wf_model$theta + 1.96 * wf_model$se.theta
)
positions <- cbind(positions, docvars(dfmat))

# Visualize document positions
ggplot(positions, aes(x=theta, y=reorder(doc, theta), color=group)) +
  geom_point(size=3) +
  geom_errorbarh(aes(xmin=lower, xmax=upper), height=0.2) +
  labs(x="Wordfish Position (θ)", y="Document") +
  theme_Publication()
ggsave("${OUTPUT_ROOT}/figures/fig-wordfish-positions.pdf", width=10, height=7)

# Inspect "Eiffel" words (discriminating words driving the scale)
word_positions <- data.frame(
  word  = wf_model$features,
  beta  = wf_model$beta,   # word's discriminating power on the scale
  psi   = wf_model$psi     # word frequency (log-scale)
)
word_positions |> dplyr::arrange(desc(abs(beta))) |> head(30)

# Save
positions.to_csv <- write.csv(positions, "${OUTPUT_ROOT}/tables/wordfish-positions.csv")

# ── Wordscores: supervised scaling with reference texts ───────────────
# Assign known scores to reference documents (e.g., expert-coded manifestos)
ref_scores <- c(rep(NA, n_test), -1.5, 0.0, 1.5)  # NA for new docs; known for anchors
ws_model   <- textmodel_wordscores(dfmat, y=ref_scores, smooth=1)

# Predict scores for new (virgin) documents
ws_pred    <- predict(ws_model, newdata=dfmat[is.na(ref_scores), ],
                       rescaling="lbg")  # Laver-Benoit-Garry rescaling
print(ws_pred)
```

**Reporting template (Wordfish):**
> "We estimate document positions on a latent ideological dimension using Wordfish (Slapin and Proksch 2008), as implemented in the `quanteda.textmodels` package (Benoit et al. 2018). Wordfish estimates document-level positions (θ) and word-level discrimination parameters (β) via a Poisson scaling model, without imposing a priori assumptions about the dimension's content. We fix the direction of the scale using [reference documents] as poles. The resulting positions are validated by comparing to [external criterion: expert scores / party labels / vote shares]."

---

### Step 3d — Multilingual NLP: Cross-Lingual Text Analysis

**When to use**: When your corpus contains text in multiple languages (e.g., comparative social media research, cross-national surveys, multilingual interview transcripts, immigrant communities, language contact settings) and you need consistent analytical treatment across languages without translating everything to English.

| Task | Recommended model | Package |
|------|------------------|---------|
| Cross-lingual classification / embeddings | **XLM-RoBERTa-large** | `transformers` |
| Multilingual NER / POS tagging | **mBERT** or **XLM-RoBERTa** | `transformers`, `spacy-transformers` |
| Language detection | **lingua** (rule-based, fast) or **fasttext** | `lingua-language-detector`, `fasttext` |
| Multilingual topic modeling | **BERTopic + multilingual embeddings** | `bertopic`, `sentence-transformers` |
| Cross-lingual transfer (annotation) | Fine-tune on English labels, apply to target lang | `transformers` |
| Multilingual sentiment | **XLM-RoBERTa fine-tuned on multilingual sentiment** | `transformers` |

**Installation:**

```bash
pip install transformers sentence-transformers lingua-language-detector bertopic
# For spaCy multilingual pipeline:
pip install spacy-transformers
python -m spacy download xx_ent_wiki_sm   # multilingual NER
```

**Step 1 — Language detection and corpus profiling:**

```python
from lingua import Language, LanguageDetectorBuilder
import pandas as pd

# Build detector for expected languages (faster and more accurate than detect-all)
detector = LanguageDetectorBuilder.from_languages(
    Language.ENGLISH, Language.SPANISH, Language.CHINESE, Language.ARABIC,
    Language.FRENCH, Language.GERMAN, Language.PORTUGUESE
).with_preloaded_language_models().build()

def detect_language(text):
    if not text or len(text.strip()) < 10:
        return "UNKNOWN"
    result = detector.detect_language_of(text)
    return result.iso_code_639_1.name.lower() if result else "UNKNOWN"

df["lang"] = df["text"].apply(detect_language)
print(df["lang"].value_counts())
df.to_csv("${OUTPUT_ROOT}/tables/corpus-language-profile.csv", index=False)
```

**Step 2 — Cross-lingual embeddings with XLM-RoBERTa:**

```python
from sentence_transformers import SentenceTransformer
import numpy as np

# paraphrase-multilingual-mpnet-base-v2 supports 50+ languages
# Maps all languages into the SAME embedding space
model_multi = SentenceTransformer("paraphrase-multilingual-mpnet-base-v2")

# Encode texts regardless of language — embeddings are cross-lingually aligned
embeddings = model_multi.encode(
    df["text"].tolist(),
    batch_size=64,
    show_progress_bar=True,
    normalize_embeddings=True
)
np.save("${OUTPUT_ROOT}/models/multilingual-embeddings.npy", embeddings)

# Downstream: cosine similarity across languages works as expected
from sklearn.metrics.pairwise import cosine_similarity
# e.g., English tweet about immigration vs. Spanish tweet about immigration
# will have high cosine similarity if semantically similar
```

**Step 3 — Multilingual topic modeling (BERTopic + multilingual embeddings):**

```python
from bertopic import BERTopic
from sentence_transformers import SentenceTransformer
from sklearn.feature_extraction.text import CountVectorizer
from umap import UMAP
from hdbscan import HDBSCAN

# Use multilingual sentence transformer for embeddings
embedding_model = SentenceTransformer("paraphrase-multilingual-mpnet-base-v2")

# Custom UMAP and HDBSCAN for reproducibility
umap_model    = UMAP(n_neighbors=15, n_components=5, min_dist=0.0,
                      metric="cosine", random_state=42)
hdbscan_model = HDBSCAN(min_cluster_size=30, min_samples=10,
                          metric="euclidean", prediction_data=True)

# Multilingual stopword removal via spaCy or manual list
# For topic representation, use language-specific CountVectorizer or
# let BERTopic handle representation with multilingual c-TF-IDF
topic_model = BERTopic(
    embedding_model=embedding_model,
    umap_model=umap_model,
    hdbscan_model=hdbscan_model,
    top_n_words=15,
    verbose=True
)

topics, probs = topic_model.fit_transform(df["text"].tolist(), embeddings)
df["topic"] = topics

# Analyze topic distribution by language
topic_by_lang = pd.crosstab(df["topic"], df["lang"], normalize="columns")
topic_by_lang.to_csv("${OUTPUT_ROOT}/tables/topic-by-language.csv")

# Visualize
fig = topic_model.visualize_barchart(top_n_topics=15)
fig.write_html("${OUTPUT_ROOT}/figures/multilingual-topics.html")

topic_model.save("${OUTPUT_ROOT}/models/multilingual-bertopic")
```

**Step 4 — Cross-lingual transfer for annotation** (train on English, apply to other languages):

```python
from transformers import (AutoTokenizer, AutoModelForSequenceClassification,
                          TrainingArguments, Trainer)
from datasets import Dataset
import numpy as np, torch

SEED = 42
torch.manual_seed(SEED)

model_name = "xlm-roberta-large"
tokenizer  = AutoTokenizer.from_pretrained(model_name)
model      = AutoModelForSequenceClassification.from_pretrained(
                 model_name, num_labels=3)   # e.g., positive/negative/neutral

# Train on ENGLISH labeled data only
train_en = df[df["lang"] == "en"].sample(frac=0.8, random_state=SEED)
val_en   = df[df["lang"] == "en"].drop(train_en.index)

def tokenize_fn(batch):
    return tokenizer(batch["text"], truncation=True, padding="max_length",
                     max_length=256)

train_ds = Dataset.from_pandas(train_en[["text", "label"]]).map(tokenize_fn, batched=True)
val_ds   = Dataset.from_pandas(val_en[["text", "label"]]).map(tokenize_fn, batched=True)

args = TrainingArguments(
    output_dir="${OUTPUT_ROOT}/models/xlm-r-crosslingual",
    num_train_epochs=5,
    per_device_train_batch_size=16,
    per_device_eval_batch_size=32,
    eval_strategy="epoch",
    save_strategy="epoch",
    load_best_model_at_end=True,
    metric_for_best_model="f1",
    seed=SEED
)

from sklearn.metrics import f1_score, accuracy_score
def compute_metrics(eval_pred):
    preds = np.argmax(eval_pred.predictions, axis=1)
    return {"f1": f1_score(eval_pred.label_ids, preds, average="macro"),
            "accuracy": accuracy_score(eval_pred.label_ids, preds)}

trainer = Trainer(model=model, args=args, train_dataset=train_ds,
                  eval_dataset=val_ds, compute_metrics=compute_metrics)
trainer.train()

# Apply to OTHER languages (zero-shot cross-lingual transfer)
for lang in ["es", "zh", "ar", "fr"]:
    target = df[df["lang"] == lang]
    if len(target) == 0:
        continue
    target_ds = Dataset.from_pandas(target[["text"]]).map(tokenize_fn, batched=True)
    preds     = trainer.predict(target_ds)
    target_labels = np.argmax(preds.predictions, axis=1)
    print(f"Language {lang}: N={len(target)}, predicted class distribution: "
          f"{np.bincount(target_labels, minlength=3)}")
    # IMPORTANT: validate on a human-coded sample per target language
```

```r
# R alternative — multilingual text analysis with quanteda + spacyr
library(quanteda)
library(spacyr)

# Initialize spaCy with multilingual model
spacy_initialize(model = "xx_ent_wiki_sm")

# Parse multilingual corpus
parsed <- spacy_parse(corpus_texts, entity = TRUE, nounphrase = TRUE)

# Create DFM per language, then combine
dfm_en <- corpus_subset(corp, lang == "en") |> tokens() |> dfm()
dfm_es <- corpus_subset(corp, lang == "es") |> tokens() |> dfm()
```

**Validation approach:**
- Cross-lingual transfer: evaluate on human-coded sample in EACH target language (minimum 100 documents per language)
- Report per-language F1 and overall F1; note any language where performance degrades significantly
- Multilingual topic model: validate topic coherence per language; human-review 20 docs/topic/language
- Language detection: report accuracy on a manually verified sample; flag mixed-code / code-switching documents

**Reporting template:**
> "Our corpus contains [N] documents across [K] languages ([list with Ns]). We detect document language using lingua (Stahl 2023) and generate cross-lingually aligned embeddings with XLM-RoBERTa (Conneau et al. 2020) via paraphrase-multilingual-mpnet-base-v2 (Reimers & Gurevych 2020). [For cross-lingual classification], we fine-tune XLM-RoBERTa-large on [N] English-labeled documents and apply zero-shot cross-lingual transfer to [target languages]. Transfer performance was validated on [N] human-coded documents per language: English F1 = [X], [Spanish] F1 = [X], [Chinese] F1 = [X]. [For multilingual topic modeling], we fit BERTopic with multilingual embeddings, identifying K = [X] topics. Topic distributions differ by language ([describe pattern]), suggesting [interpretation]. All models use seed = 42."

---

### Step 3e — Named Entity Recognition (NER)

**Social science applications**: Extract organizations, locations, persons, dates from text corpora (congressional records, news, legal documents).

```python
import spacy
nlp = spacy.load("en_core_web_trf")  # transformer-based for accuracy

# Extract entities from corpus
entities = []
for doc in nlp.pipe(texts, batch_size=50):
    for ent in doc.ents:
        entities.append({"text": ent.text, "label": ent.label_,
                        "start": ent.start_char, "end": ent.end_char})
entity_df = pd.DataFrame(entities)

# Custom NER for domain-specific entities (e.g., policy names, legislation)
# Fine-tune with spaCy or Hugging Face token classification
from transformers import pipeline
ner_pipe = pipeline("ner", model="dslim/bert-base-NER", aggregation_strategy="simple")
results = ner_pipe("The Affordable Care Act was signed by President Obama in 2010.")
```

### Step 3f — Coreference Resolution

```python
# Resolve pronouns to entities (critical for narrative/discourse analysis)
# fastcoref (lightweight, fast)
from fastcoref import spacy_component
nlp = spacy.load("en_core_web_sm")
nlp.add_pipe("fastcoref")
doc = nlp("John went to the store. He bought milk.")
# doc._.coref_clusters → [('John', 'He')]
```

---

### Step 4 — Fine-Tuned BERT Classification

When you need supervised text classification with labeled training data:

```python
from datasets import Dataset
from transformers import (AutoTokenizer, AutoModelForSequenceClassification,
                          TrainingArguments, Trainer)
import numpy as np
from sklearn.metrics import classification_report, roc_auc_score
import torch

MODEL_NAME = "roberta-base"
tokenizer  = AutoTokenizer.from_pretrained(MODEL_NAME)

def tokenize_fn(examples):
    return tokenizer(examples["text"], truncation=True,
                     padding="max_length", max_length=256)

train_ds = Dataset.from_pandas(train_df).map(tokenize_fn, batched=True)
val_ds   = Dataset.from_pandas(val_df).map(tokenize_fn, batched=True)
test_ds  = Dataset.from_pandas(test_df).map(tokenize_fn, batched=True)

model = AutoModelForSequenceClassification.from_pretrained(MODEL_NAME, num_labels=2)

def compute_metrics(eval_pred):
    logits, labels = eval_pred
    preds = np.argmax(logits, axis=-1)
    proba = torch.softmax(torch.tensor(logits), dim=-1).numpy()[:,1]
    rep   = classification_report(labels, preds, output_dict=True)
    return {"f1": rep["weighted avg"]["f1-score"],
            "auc": roc_auc_score(labels, proba)}

args = TrainingArguments(
    output_dir="${OUTPUT_ROOT}/models/bert_clf",
    num_train_epochs=3,
    per_device_train_batch_size=16,
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

# Evaluate on held-out test set
test_preds = trainer.predict(test_ds)
print(classification_report(test_ds["label"],
                             np.argmax(test_preds.predictions, axis=-1)))
```

**Required**: 60/20/20 or 70/15/15 split; report precision, recall, F1 (macro + weighted), AUC-ROC on test set; human validation of labels with Cohen's κ ≥ 0.70.

---

### Step 5 — Word Embeddings and Semantic Change

```python
from gensim.models import Word2Vec
import numpy as np

def train_w2v(texts, seed=42):
    sentences = [t.split() for t in texts]
    return Word2Vec(sentences, vector_size=100, window=5,
                    min_count=10, workers=4, seed=seed, epochs=10)

# Train per time period
models = {yr: train_w2v(df[df.year==yr].text.tolist())
          for yr in [1990, 2000, 2010, 2020]}

# Align with Procrustes rotation before comparing across periods
# (use: https://github.com/williamleif/histwords or gensim alignment)

def cosine(v1, v2):
    return np.dot(v1,v2) / (np.linalg.norm(v1)*np.linalg.norm(v2))

for yr in [2000,2010,2020]:
    if "immigrant" in models[yr].wv:
        sim = cosine(models[1990].wv["immigrant"], models[yr].wv["immigrant"])
        print(f"{yr}: cosine(1990, {yr}) = {sim:.3f}")
```

---

### Step 6 — Embedding Regression (conText)

**When to use**: You want to test whether and how the *meaning* of a target word varies across groups, time periods, or other document-level covariates — with statistical inference.

Method: Rodriguez, Spirling & Stewart (2022, APSR). Uses "a la carte" embeddings (Khodak et al. 2018). Each context of the target word is embedded using pre-trained GloVe + a transformation matrix. Regression on those embeddings yields group-specific semantic vectors; statistical inference via bootstrapping or permutation tests.

```r
# Install once
# install.packages("conText")
library(conText)
library(quanteda)
library(dplyr)

# ── 1. Preprocess ────────────────────────────────────────────────────
toks <- tokens(corpus_obj,
               remove_punct=TRUE, remove_symbols=TRUE,
               remove_numbers=TRUE) |>
        tokens_tolower()
toks_nostop <- tokens_select(toks, stopwords("en"), selection="remove", min_nchar=3)

# Keep only features that appear ≥5 times (reduces noise)
feats           <- dfm(toks_nostop) |> dfm_trim(min_termfreq=5) |> featnames()
toks_clean      <- tokens_select(toks_nostop, feats, padding=TRUE)

# ── 2. Extract contexts around target word ───────────────────────────
# window = tokens on each side of the target
target_toks <- tokens_context(x=toks_clean, pattern="immigr*", window=6L)

# ── 3. Build document-embedding matrix (DEM) ─────────────────────────
# pre_trained  = GloVe embeddings (cr_glove_subset or load your own)
# transform    = apply Khodak transformation to improve context representation
# transform_matrix = cr_transform (bundled) or khodakA.rds
target_dfm <- dfm(target_toks)
target_dem <- dem(x=target_dfm,
                  pre_trained=cr_glove_subset,
                  transform=TRUE,
                  transform_matrix=cr_transform,
                  verbose=TRUE)

# ── 4. Group-specific embeddings ─────────────────────────────────────
# dem_group averages embeddings within each group
target_wv_party <- dem_group(target_dem, groups=target_dem@docvars$party)

# ── 5. Nearest neighbors per group ───────────────────────────────────
# What words are semantically closest to each party's usage of "immigr*"?
nns_results <- nns(target_wv_party,
                   pre_trained=cr_glove_subset,
                   N=10,
                   candidates=target_wv_party@features,
                   as_list=TRUE)
nns_results[["R"]]   # Republican nearest neighbors
nns_results[["D"]]   # Democrat nearest neighbors

# ── 6. Cosine similarity to specific concepts ────────────────────────
cos_sim(target_wv_party,
        pre_trained=cr_glove_subset,
        features=c("reform","enforcement","crime","family"),
        as_list=FALSE)

# ── 7. NNS ratio — partisan distinctiveness ──────────────────────────
# Values >1: word more associated with numerator group
nns_ratio(x=target_wv_party, N=10, numerator="R",
          candidates=target_wv_party@features,
          pre_trained=cr_glove_subset)

# ── 8. Nearest actual contexts ───────────────────────────────────────
ncs_results <- ncs(x=target_wv_party,
                   contexts_dem=target_dem,
                   contexts=target_toks,
                   N=5, as_list=TRUE)

# ── 9. Embedding regression with inference ───────────────────────────
# formula: target_word ~ covariates; bootstrapped CIs
model_ctx <- conText(
  formula         = immigr* ~ party + year,
  data            = corpus_obj,
  pre_trained     = cr_glove_subset,
  transform       = TRUE,
  transform_matrix= cr_transform,
  bootstrap       = TRUE,
  num_bootstraps  = 200,
  permute         = TRUE,
  num_permutations= 200,
  window          = 6L,
  valuetype       = "glob",
  verbose         = FALSE
)

# Coefficients: each row = embedding dimension; each column = covariate
# Norm of coefficient vector = overall effect size
print(model_ctx@normed_betas)   # normed beta + 95% CI per covariate

# ── 10. Visualize NNS comparison ─────────────────────────────────────
# Plot top 10 NNS for each group side-by-side
# Export via save_fig() convention
```

**Reporting template:**
> "We apply embedding regression (Rodriguez, Spirling, and Stewart 2022) to test whether the semantic meaning of *[target word]* varies by [covariate]. For each occurrence of *[target word]* in the corpus, we extract a context window of ±6 tokens and compute an 'a la carte' embedding using pre-trained GloVe vectors (Pennington et al. 2014) and a Khodak transformation matrix. We then regress these context embeddings on [covariates], with inference via [200] bootstrap iterations. The normed β for [party] = [X] (95% CI = [[lo], [hi]]), indicating [interpretation]."

See [references/nlp-pipeline.md](references/nlp-pipeline.md) for the full conText workflow with multiple keywords and temporal analysis.

---

### Step 7 — LLM-Based Annotation

**When to use**: You need to label a large corpus but have limited human annotators. GPT-4 / Claude can serve as a zero-shot or few-shot annotator. **Always benchmark against human coders** before treating LLM labels as ground truth.

**Epistemic Risk Assessment (REQUIRED — Lin & Zhang 2025)**

Before deploying LLMs for annotation, assess all four epistemic risks identified by Lin and Zhang (2025, *Social Science Computer Review*):

| Risk | Definition | Mitigation |
|------|-----------|-----------|
| **Validity** | LLM codes a proxy concept, not the intended construct | Pilot on 50 docs; inspect rationale field; compare NNS of construct |
| **Reliability** | Labels vary across runs, models, or prompt wordings | Fix temperature=0; run same docs twice; report run-to-run κ |
| **Replicability** | Future researchers cannot reproduce labels (model updates) | Record exact model + version + date; archive prompt verbatim; save raw outputs |
| **Transparency** | Annotation process opaque to readers | Disclose all prompts; report benchmark details; note known LLM limitations |

**LLM Role Decision**:
- **LLM as primary coder** (fully automated): requires κ ≥ 0.70 vs. human consensus; justified when corpus is too large for human annotation
- **LLM as coding assistant** (human-in-the-loop): LLM pre-labels; humans review low-confidence items; preferred when N < 10,000 or concept is theoretically sensitive

```python
import anthropic, json, time
from sklearn.metrics import cohen_kappa_score

client = anthropic.Anthropic()   # set ANTHROPIC_API_KEY in environment

# temperature=0 for reproducibility (Lin & Zhang 2025 — reliability risk)
SYSTEM_PROMPT = """You are a social science research assistant coding news articles.
Code each article for the following dimension:
  - Threat frame: 1 = article frames immigration primarily as a threat to safety/economy; 0 = does not.
Respond ONLY with a JSON object: {"label": 0_or_1, "confidence": "high|medium|low", "rationale": "one sentence"}"""

MODEL_NAME  = "claude-sonnet-4-6"
ANNOT_DATE  = "2026-02-23"   # record for replicability

def annotate(text, model=MODEL_NAME, max_tokens=150):
    msg = client.messages.create(
        model=model,
        max_tokens=max_tokens,
        temperature=0,   # deterministic — required for replicability
        system=SYSTEM_PROMPT,
        messages=[{"role":"user","content": f"Article:\n{text[:2000]}"}]
    )
    return json.loads(msg.content[0].text)

# Annotate in batches with rate limiting
results = []
for i, row in df.iterrows():
    try:
        res = annotate(row["text"])
        results.append({"id": row["id"], **res,
                         "model": MODEL_NAME, "annot_date": ANNOT_DATE})
        if i % 50 == 0: time.sleep(1)   # respect rate limits
    except Exception as e:
        results.append({"id": row["id"], "label": None, "error": str(e)})

llm_labels = pd.DataFrame(results)
# ALWAYS save raw LLM outputs with model + date (replicability)
llm_labels.to_csv("${OUTPUT_ROOT}/tables/llm-annotations-raw.csv", index=False)

# Benchmark: compare LLM labels to human codes on 200-doc sample
# (Lin & Zhang 2025 recommend ≥200 docs for stable κ estimate)
human_sample = pd.read_csv("human_annotation_sample.csv")
merged = human_sample.merge(llm_labels, on="id")
kappa  = cohen_kappa_score(merged["human_label"], merged["llm_label"])
print(f"LLM vs. human Cohen's κ = {kappa:.3f}")
# Target: κ ≥ 0.70 before using LLM labels as primary coder
# If 0.60 ≤ κ < 0.70: use LLM as coding assistant (human review of low-confidence)
# If κ < 0.60: revise prompt; consider fine-tuning; do not proceed with LLM-only

# Reliability check: re-annotate 50-doc subsample and compare
subsample_ids = human_sample.sample(50, random_state=42)["id"]
rerun = pd.DataFrame([{"id": i, "label_run2": annotate(
    df[df["id"]==i]["text"].iloc[0])["label"]} for i in subsample_ids])
merged_rel = llm_labels[llm_labels["id"].isin(subsample_ids)].merge(rerun, on="id")
kappa_rel = cohen_kappa_score(merged_rel["label"], merged_rel["label_run2"])
print(f"Run-to-run reliability κ = {kappa_rel:.3f}")

# Cost estimation before full run
avg_tokens_in  = 600   # approximate input tokens per document
avg_tokens_out = 50    # approximate output tokens
price_per_1k   = 0.003 # adjust to current model pricing
n_docs         = len(df)
est_cost = (n_docs * (avg_tokens_in + avg_tokens_out) / 1000) * price_per_1k
print(f"Estimated annotation cost: ${est_cost:.2f} for {n_docs} documents")
```

**Reporting template:**
> "We use [Claude Sonnet 4.6 / GPT-4o, annotation date: YYYY-MM-DD] as an automated annotator with a structured zero-shot prompt (reproduced in full in the Online Appendix). Following Lin and Zhang (2025), we assess four epistemic risks prior to deployment: validity (confirmed via pilot review of 50 documents and inspection of rationale outputs), reliability (run-to-run κ = [X] on a 50-document subsample with temperature = 0), replicability (model version, date, and prompt archived at [repo DOI]), and transparency (all prompts and raw outputs publicly available). Two trained research assistants independently coded a random sample of N = 200 documents; inter-rater reliability was κ = [X]. LLM agreement with human consensus labels was κ = [X], indicating [substantial/near-perfect] agreement; we therefore treat LLM labels as reliable for the full corpus (N = [X] documents)."

See [references/nlp-pipeline.md](references/nlp-pipeline.md) for the full LLM annotation workflow and Hao & Lin (2025) risk checklist.

---

### Step 8 — Design-Based Supervised Learning (DSL)

**When to use**: You used an automated method (LLM annotation, BERT classifier, GPT-4 labels) to predict a key variable and now want to use those predicted labels in a downstream regression analysis. **Directly substituting predicted labels for true labels introduces bias** — even when the automated method achieves 90%+ accuracy — because prediction errors are non-random and correlate with the outcome and covariates. DSL (Egami et al.) corrects this bias using a doubly-robust estimator that combines large-scale automated annotations with a smaller expert-annotated sample.

**Workflow**: (1) Obtain automated predictions for the full corpus; (2) Obtain expert human labels for a random subsample (N ≥ 200 recommended); (3) Run `dsl()` using both sets together.

**Reference**: Egami, Naoki, Gregory Eirich, Musashi Hinck, Reagan Kelly, and Tara Slough. "Using Predicted Variables in Downstream Analyses: Design-Based Supervised Learning." Working paper. See: https://naokiegami.com/dsl/

```r
# Install and load
# install.packages("dsl")
library(dsl)

# ── Data setup ───────────────────────────────────────────────────────
# The data frame must contain:
#   - predicted_var: expert-coded labels (NA for documents NOT in the expert sample)
#   - prediction:    automated predictions (GPT-4 / BERT / LLM) for ALL documents
#   - outcome + covariates for the downstream regression
#
# Expert sample must be drawn via RANDOM SAMPLING with equal probabilities.
# If stratified/unequal-probability sampling was used, specify sample_prob.

# Example using PanChen dataset (Pan & Chen 2018):
# Research question: Do corruption complaints naming county officials get forwarded upward?
# countyWrong: expert labels (NA for unlabeled obs); pred_countyWrong: GPT-4 predictions
data("PanChen")

# Always inspect NA pattern: how many expert-labeled vs. LLM-predicted?
cat("Expert-labeled (non-NA):", sum(!is.na(PanChen$countyWrong)), "\n")
cat("Total (LLM-predicted):  ", nrow(PanChen), "\n")
cat("Expert sample fraction: ", round(mean(!is.na(PanChen$countyWrong)), 3), "\n")

# ── Run DSL ─────────────────────────────────────────────────────────
# model: "lm" (linear), "logit" (logistic), "felm" (fixed effects via lfe)
# formula: standard regression formula; predicted_var appears as independent variable
# predicted_var: column with expert labels (has NA for unannotated obs)
# prediction:    column with automated predictions (no NAs)
out <- dsl(
  model         = "logit",
  formula       = SendOrNot ~ countyWrong + prefecWrong +
                    connect2b + prevalence + regionj + groupIssue,
  predicted_var = "countyWrong",
  prediction    = "pred_countyWrong",
  data          = PanChen
)

# ── Inspect results ──────────────────────────────────────────────────
summary(out)
# Output: coefficients with heteroskedasticity-robust SEs, CIs, p-values
# Interpretable as standard regression — no special transformation needed

# ── Compare to naive regression (for reporting) ──────────────────────
# Naive approach 1: use only expert-labeled subset (ignores automation)
naive_subset <- glm(SendOrNot ~ countyWrong + prefecWrong + connect2b +
                      prevalence + regionj + groupIssue,
                    data   = PanChen[!is.na(PanChen$countyWrong), ],
                    family = binomial)

# Naive approach 2: use LLM predictions as if error-free (biased)
naive_llm <- glm(SendOrNot ~ pred_countyWrong + prefecWrong + connect2b +
                   prevalence + regionj + groupIssue,
                 data   = PanChen, family = binomial)

cat("\n--- Coefficient on countyWrong / pred_countyWrong ---\n")
cat("DSL (bias-corrected):        ", coef(out)["countyWrong"], "\n")
cat("Naive subset (low N):        ", coef(naive_subset)["countyWrong"], "\n")
cat("Naive LLM-as-truth (biased): ", coef(naive_llm)["pred_countyWrong"], "\n")

# ── With stratified / unequal-probability expert sampling ───────────
# If you sampled the expert annotation set with unequal probabilities
# (e.g., oversampling rare categories), provide sample_prob:
# out_stratified <- dsl(
#   model         = "logit",
#   formula       = outcome ~ predicted_var + covariate1 + covariate2,
#   predicted_var = "predicted_var",
#   prediction    = "pred_predicted_var",
#   sample_prob   = PanChen$sampling_weight,  # inverse probability weights
#   data          = PanChen
# )

# ── Save results ─────────────────────────────────────────────────────
dsl_results <- broom::tidy(out, conf.int=TRUE)
write.csv(dsl_results, "${OUTPUT_ROOT}/tables/dsl-results.csv", row.names=FALSE)
```

**Multiple predicted variables** (e.g., two LLM-annotated constructs in the same regression):
```r
# Specify predicted_var and prediction as vectors
out_multi <- dsl(
  model         = "lm",
  formula       = outcome ~ var1 + var2 + covariate,
  predicted_var = c("var1", "var2"),
  prediction    = c("pred_var1", "pred_var2"),
  data          = df
)
```

**Fixed effects (felm) example**:
```r
out_fe <- dsl(
  model         = "felm",
  formula       = outcome ~ predicted_var + control | state + year,
  predicted_var = "predicted_var",
  prediction    = "pred_predicted_var",
  data          = df
)
```

**Required validation before DSL**:
- Run LLM annotation benchmark (Step 7) first: κ ≥ 0.70 vs. human coders
- Confirm expert sample drawn via random sampling (or specify `sample_prob`)
- Report N expert-labeled documents and sampling fraction

**Reporting template:**
> "We use [GPT-4 / Claude Sonnet 4.6] to predict [construct] for all [N] documents (annotation date: [date]; κ vs. human coders on [N] documents = [X]). To correct for potential bias from non-random prediction errors in downstream analyses, we apply Design-Based Supervised Learning (DSL; Egami et al.) using the `dsl` package in R. Expert human labels were obtained for a random sample of [N_expert] documents; these serve as the high-quality anchor for bias correction. The DSL estimator combines the large-scale automated predictions with the expert sample via a doubly robust bias-correction step, yielding valid coefficients and standard errors even when prediction errors are non-random. All results reported in Table [X] use DSL-corrected estimates."

**When NOT to use DSL**:
- When you are NOT using predicted labels as a covariate or outcome in a regression (e.g., only for descriptive counts)
- When your expert annotation is not a random sample of the full corpus (use `sample_prob` correction if unequal-probability sampling)
- When the automated method is used only for clustering/topic modeling (use STM or BERTopic instead)

---

### Step 9 — NLP Verification (Subagent)

Launch a verification subagent (`subagent_type: general-purpose`) after completing Steps 3–7. Provide: method used, code, output summaries, and target journal.

```
NLP VERIFICATION REPORT
========================

PREPROCESSING
[ ] Steps documented and justified (not all applied blindly)
[ ] Minimum document frequency threshold set for topic models (dfm_trim)

STM (if used)
[ ] searchK() run; K selection plot saved
[ ] Topics labeled using FREX words + top documents
[ ] Human validation: ≥20 docs per topic reviewed
[ ] Covariate effects estimated via estimateEffect()
[ ] seed=42 set

BERT CLASSIFICATION (if used)
[ ] 60/20/20 train/val/test split documented
[ ] Human labels: Cohen's κ ≥ 0.70 reported
[ ] Test-set F1 (macro), AUC-ROC reported (NOT train-set metrics)
[ ] Confusion matrix saved
[ ] seed=42 set in TrainingArguments

EMBEDDING REGRESSION (if used)
[ ] Pre-trained embeddings + transformation matrix documented
[ ] Window size reported
[ ] Bootstrap iterations ≥ 200; permutation test run
[ ] normed_betas reported with 95% CIs
[ ] NNS figures saved

LLM ANNOTATION (if used)
[ ] Prompt text documented verbatim
[ ] κ vs. human coders reported (≥ 0.70)
[ ] Model name + date of annotation recorded
[ ] Confidence filtering: low-confidence items reviewed

BERTOPIC (if used)
[ ] umap_model random_state=42 set
[ ] min_topic_size documented; % outlier documents (Topic -1) reported
[ ] Human validation: ≥20 docs per topic reviewed
[ ] Dynamic or hierarchical figures saved as HTML + PDF

TEXT SCALING (if used)
[ ] Wordfish: dir[] anchors documented and justified
[ ] Wordscores: reference texts and their scores documented
[ ] Validation against external criterion (expert scores / party labels) reported
[ ] Position plot with 95% CIs saved

DSL (if predicted labels used in regression)
[ ] Expert annotation sample is random (or sample_prob specified)
[ ] N expert-labeled documents reported (target ≥ 200)
[ ] model= type matches downstream regression family
[ ] Comparison to naive regression (subset-only and LLM-as-truth) reported
[ ] DSL results saved to output/[slug]/tables/dsl-results.csv

MULTILINGUAL NLP (if used)
[ ] Language detection run; corpus language profile saved
[ ] Language distribution reported (N per language)
[ ] Multilingual embedding model specified (paraphrase-multilingual-mpnet-base-v2 or XLM-RoBERTa)
[ ] Cross-lingual transfer: per-language F1 reported on human-coded sample (≥100 docs/language)
[ ] Multilingual topic model: topic coherence validated per language
[ ] Code-switching / mixed-language documents flagged and handled

SEEDS AND REPRODUCIBILITY
[ ] set.seed(42) / random.seed(42) called before every stochastic step
[ ] Model objects saved to output/[slug]/models/

RESULT: [PASS / NEEDS REVISION]
Issues: [list]
```

---

