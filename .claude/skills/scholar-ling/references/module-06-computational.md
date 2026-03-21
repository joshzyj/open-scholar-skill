## MODULE 6: COMPUTATIONAL SOCIOLINGUISTICS

Use when $ARGUMENTS contains: `computational`, `embedding`, `conText`, `BERT`, `NLP`, `LLM`, `annotation`, `semantic change`, `large corpus`, `classification`.

### Step 6a: Claim Taxonomy

Before proceeding, classify the computational claim:

| Claim type | Example | Validation approach |
|-----------|---------|---------------------|
| Measurement | "This LLM classifier detects code-switching" | κ vs. human annotators; F1 ≥ 0.80 |
| Description | "Lexical complexity in court speech declined 2000–2020" | Corpus representativeness + model validity |
| Prediction | "Dialect features predict racial classification" | AUC on held-out test set |
| Causal | "Exposure to standard language changes code use" | → invoke `/scholar-causal` before proceeding |

---

### Step 6b: conText Embedding Regression (Rodriguez et al. 2023)

**Purpose**: Estimate how a target word (e.g., *immigrant*) is used differently across social groups (Democrat vs. Republican), controlling for other textual covariates.

```r
# install.packages("conText")
library(conText); library(quanteda); library(ggplot2)

data(cr_glove_subset)  # pre-trained GloVe embeddings (Congress)
data(cr_corpus)
data(cr_party)

# Step 1: Tokenize
toks <- tokens(cr_corpus, remove_punct = TRUE) |> tokens_tolower()

# Step 2: Extract tokens-in-context around target (±6 token window)
toks_ctx <- tokens_context(toks, pattern = "immigr*", window = 6L)

# Step 3: Build document-embedding matrix (DEM)
dem_immigr <- dem(x = toks_ctx, pre_trained = cr_glove_subset,
                  transform = TRUE, verbose = FALSE)

# Step 4: Group-level ALC embeddings
dem_party <- dem_group(dem_immigr, groups = cr_party)

# Step 5: Nearest semantic neighbors per group
nns_party <- nns(dem_party, pre_trained = cr_glove_subset,
                 N = 10, as_list = TRUE)
print(nns_party)  # what concepts are closest to "immigr*" for D vs. R?

# Step 6: Cosine similarity between groups
cos_sim(dem_party["D", ], dem_party["R", ])

# Step 7: NNS ratio (D/R — which words are more D-like?)
nns_ratio(x = dem_party, N = 10, pre_trained = cr_glove_subset,
          numerator = "D", denominator = "R")

# Step 8: conText regression (ALC embedding ~ group + year)
model_ctx <- conText(formula  = immigr ~ party + year,
                     data     = cr_corpus,
                     pre_trained = cr_glove_subset,
                     transform   = TRUE, verbose = FALSE,
                     permute     = TRUE, num_permutations = 100)
summary(model_ctx)  # coefficients = ALC embeddings; permutation p-values

# Step 9: Visualize
plot(model_ctx) + theme_Publication()
ggsave("${OUTPUT_ROOT}/ling/figures/fig-context-embedding.pdf",
       device = cairo_pdf, width = 7, height = 5)
ggsave("${OUTPUT_ROOT}/ling/figures/fig-context-embedding.png", dpi = 300,
       width = 7, height = 5)

# Save model and nearest-neighbor tables
saveRDS(model_ctx, "${OUTPUT_ROOT}/ling/models/context-model.rds")
write.csv(nns_party$D, "${OUTPUT_ROOT}/ling/tables/nns-democrat.csv")
write.csv(nns_party$R, "${OUTPUT_ROOT}/ling/tables/nns-republican.csv")
```

**Reporting template**:
> "We used the conText framework (Rodriguez et al. 2023) with [GloVe 300d / cr_glove] embeddings to estimate group differences in the semantic context of *[target term]*. For each target instance, we extracted a ±[window]-token context window and constructed group-level ALC embeddings. [Group A] used *[target term]* in contexts most similar to [neighbor 1, 2], while [Group B] used it closer to [neighbor 3, 4] (cosine similarity = [X]). The conText regression coefficient for [Group B] vs. [Group A] was significant (permutation p = [p], N = [N] contexts, n_permutations = 100)."

---

### Step 6c: LLM Annotation for Linguistic Coding

**Use cases**: code-switching detection, stance labeling, register classification, politeness coding, pragmatic act tagging, discourse marker function, sentiment in non-standard varieties.

```python
import anthropic, json, pandas as pd
from tqdm import tqdm

client = anthropic.Anthropic()  # uses ANTHROPIC_API_KEY env variable

CODEBOOK = """
Label each utterance for CODE-SWITCHING (switch between two languages/varieties):
  0 = Monolingual / no switching
  1 = Single lexical insertion (1–3 words from L2 embedded in L1 structure)
  2 = Intrasentential switching (switch within a clause)
  3 = Intersentential switching (switch between complete sentences/clauses)

Rules:
  - Proper nouns do NOT count as code-switching
  - Established loanwords (pizza, sushi) do NOT count
  - If ambiguous, choose the lower code

Return valid JSON ONLY:
{"label": <int>, "confidence": "high|medium|low", "rationale": "<brief explanation>"}
"""

def annotate_batch(texts: list[str], batch_size: int = 20) -> list[dict]:
    results = []
    for i in tqdm(range(0, len(texts), batch_size)):
        batch = texts[i : i + batch_size]
        prompt = CODEBOOK + "\n\nAnnotate each utterance:\n"
        for j, t in enumerate(batch):
            prompt += f"\n[{j+1}] {t}"
        msg = client.messages.create(
            model="claude-haiku-4-5-20251001",  # cost-efficient for annotation
            max_tokens=2048, temperature=0,
            messages=[{"role": "user", "content": prompt}])
        raw = msg.content[0].text.strip()
        # Parse: look for JSON array or line-by-line JSON objects
        try:
            parsed = json.loads(raw) if raw.startswith("[") else \
                     [json.loads(line) for line in raw.splitlines() if line.strip().startswith("{")]
        except Exception:
            parsed = [{"label": None, "confidence": "low", "rationale": "parse error"}] * len(batch)
        results.extend(parsed)
    return results

annots = annotate_batch(df["text"].tolist())
df["llm_label"] = [r.get("label") for r in annots]
df["llm_conf"]  = [r.get("confidence") for r in annots]
df.to_csv("${OUTPUT_ROOT}/ling/tables/llm-annotations.csv", index=False)
```

**Benchmarking against human coders** (REQUIRED for publication):

```python
from sklearn.metrics import cohen_kappa_score, classification_report
import krippendorff, numpy as np

# Cohen's κ: LLM vs. human gold standard (N=100–200 items)
kappa = cohen_kappa_score(df_gold["human_label"], df_gold["llm_label"])
print(f"Cohen's κ (LLM vs. Human): {kappa:.3f}")
# κ ≥ 0.70 = acceptable; ≥ 0.80 = good; ≥ 0.90 = excellent

# Krippendorff's α (≥3 coders including LLM)
alpha = krippendorff.alpha(
    reliability_data=np.array([df_gold["coder1"], df_gold["coder2"], df_gold["llm_label"]]))
print(f"Krippendorff's α: {alpha:.3f}")

# Per-class precision/recall/F1
print(classification_report(df_gold["human_label"], df_gold["llm_label"], digits=3))

# Flag low-confidence items for human adjudication
low_conf = df[df["llm_conf"] == "low"]
print(f"{len(low_conf)} items flagged for human review ({len(low_conf)/len(df)*100:.1f}%)")
low_conf.to_csv("${OUTPUT_ROOT}/ling/tables/low-conf-for-review.csv", index=False)
```

**Lin & Zhang (2025) four-risk framework** (report in Methods):
- **Validity**: Does LLM coding match the theoretical construct? (compare κ with human gold standard)
- **Reliability**: Inter-run reliability — run same 50–100 items twice at temperature=0; report % agreement
- **Replicability**: Archive system prompt, model version (e.g., `claude-haiku-4-5-20251001`), temperature, date
- **Transparency**: Report model, prompt, κ, low-confidence rate, and human adjudication procedure in Methods

**Archive metadata**:

```python
import json, hashlib
metadata = {
    "model":            "claude-haiku-4-5-20251001",
    "task":             "code-switching annotation",
    "prompt_hash":      hashlib.md5(CODEBOOK.encode()).hexdigest(),
    "temperature":      0,
    "date":             "2026-02-24",
    "N_annotated":      len(df),
    "kappa_llm_human":  round(float(kappa), 4),
    "low_conf_rate":    round(float(len(low_conf)/len(df)), 4)
}
with open("${OUTPUT_ROOT}/ling/models/annotation-metadata.json", "w") as f:
    json.dump(metadata, f, indent=2)
```

---

### Step 6d: BERT-based Linguistic Classification

```python
from transformers import pipeline, AutoTokenizer, AutoModelForSequenceClassification
from transformers import TrainingArguments, Trainer
from datasets import Dataset
from sklearn.model_selection import train_test_split
from sklearn.metrics import classification_report
import numpy as np

# Option A: Zero-shot (no labeled data — fast baseline)
clf = pipeline("zero-shot-classification", model="facebook/bart-large-mnli")
labels = ["formal", "informal", "academic", "colloquial"]
results = [clf(text, labels) for text in df["text"].tolist()]
df["predicted_register"] = [r["labels"][0] for r in results]

# Option B: Fine-tune on labeled data (recommended if ≥ 500 labeled examples per class)
MODEL_NAME = "bert-base-uncased"
tokenizer  = AutoTokenizer.from_pretrained(MODEL_NAME)

label2id = {v: i for i, v in enumerate(df["label"].unique())}
df["label_id"] = df["label"].map(label2id)

train_df, test_df = train_test_split(df[df["label_id"].notna()], test_size=0.20,
                                      stratify=df["label_id"], random_state=42)
def tokenize(batch): return tokenizer(batch["text"], truncation=True, max_length=256)

train_ds = Dataset.from_pandas(train_df[["text","label_id"]].rename(columns={"label_id":"labels"}))
test_ds  = Dataset.from_pandas(test_df[["text","label_id"]].rename(columns={"label_id":"labels"}))
train_ds = train_ds.map(tokenize, batched=True)
test_ds  = test_ds.map(tokenize, batched=True)

model = AutoModelForSequenceClassification.from_pretrained(MODEL_NAME,
            num_labels=len(label2id))
args  = TrainingArguments(output_dir="${OUTPUT_ROOT}/ling/models/bert-register",
            num_train_epochs=3, per_device_train_batch_size=16,
            evaluation_strategy="epoch", save_strategy="epoch",
            load_best_model_at_end=True, seed=42)
trainer = Trainer(model=model, args=args, train_dataset=train_ds, eval_dataset=test_ds)
trainer.train()

# Evaluate on test set
preds      = trainer.predict(test_ds)
pred_labels = np.argmax(preds.predictions, axis=-1)
print(classification_report(test_df["label_id"], pred_labels,
                             target_names=list(label2id.keys()), digits=3))
```

**Required reporting**: model name and version, training N, test N, precision/recall/F1 per class, cross-validation approach, seed.

---

### Step 6e: Semantic Change Detection (Diachronic)

```python
from gensim.models import Word2Vec
from scipy.linalg import orthogonal_procrustes
from scipy.spatial.distance import cosine
import numpy as np, pandas as pd

# 1. Train Word2Vec on time-sliced corpora
models = {}
for period, texts in corpus_by_period.items():
    tokenized = [t.split() for t in texts]  # or spaCy tokenizer
    models[period] = Word2Vec(sentences=tokenized, vector_size=100,
                               window=5, min_count=10, workers=4, seed=42)

# 2. Procrustes alignment: align all models to base period
BASE = "1990s"
base_model = models[BASE]
for period, m in models.items():
    if period != BASE:
        common = list(set(base_model.wv.key_to_index) & set(m.wv.key_to_index))
        A = np.array([base_model.wv[w] for w in common])
        B = np.array([m.wv[w] for w in common])
        R, _ = orthogonal_procrustes(B, A)
        m.wv.vectors = m.wv.vectors @ R  # aligned embeddings

# 3. Measure cosine distance from base period
target = "immigrant"
changes = {p: cosine(base_model.wv[target], models[p].wv[target])
           for p in models if p != BASE}
pd.Series(changes).sort_index().to_frame("semantic_drift").to_csv(
    "${OUTPUT_ROOT}/ling/tables/semantic-drift.csv")
```

**Key methodological references**: Hamilton et al. (2016) cultural shift + semantic drift; Kutuzov et al. (2018) systematic review of diachronic word embeddings; di Mauro & Eger (2019) SCAN model.

---

