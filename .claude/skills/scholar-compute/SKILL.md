---
name: scholar-compute
description: "Design and execute computational social science analyses: text-as-data/NLP (STM, BERTopic dynamic topics, text scaling via Wordfish/Wordscores, BERT, embedding regression via conText, LLM annotation with Lin & Zhang 2025 risk framework, Design-based Supervised Learning (DSL/Egami) for bias-corrected downstream regression from predicted annotations, multilingual NLP via XLM-RoBERTa/mBERT for cross-lingual text analysis and multilingual topic modeling), machine learning (supervised ML, Double ML, Causal Forests, Bayesian regression with brms/Stan, conformal prediction for distribution-free uncertainty quantification via mapie/conformalInference), network analysis (ERGMs, SAOMs, relational event models via goldfish/relevent, GNN/node embeddings via node2vec/GCN/GraphSAGE with PyTorch Geometric for link prediction and node classification), agent-based modeling (Mesa 3.x with AgentSet/PropertyLayer API, NetLogo/nlrx, LLM-powered agents, ODD, SALib), computer vision (DINOv2, CLIP, ConvNeXt, ViT, multimodal LLMs, VideoMAE, multimodal text+image fusion with late/early/hybrid strategies), LLM-powered analysis workflows (structured extraction, CoT coding, computational grounded theory, RAG/document QA), LLM synthetic data generation (persona/context engineering, silicon sampling, survey and vignette simulation, organizational/group behavior simulation, multi-agent opinion dynamics), geospatial and spatial analysis (sf, tidycensus, spdep, spatialreg, Moran's I, spatial lag/error/SEM models, LISA maps), audio as data (Essentia statistical feature extraction: MFCCs/spectral/rhythm/mood; librosa preprocessing; Whisper/faster-whisper transcription with speaker diarization via pyannote; post-transcription NLP pipeline routed to MODULE 1; LLM-native audio analysis via Gemini 1.5 Pro + GPT-4o audio; PANNs/AudioCLIP/wav2vec2 audio classification; social science use cases: political speeches, oral history, broadcast news, music as culture). Runs per-module verification subagents. Saves an internal log and a publication-ready Methods + Results document. Targets Nature Computational Science, Science Advances, and computational sociology venues."
tools: Read, Bash, Write, WebSearch
argument-hint: "[text|network|ml|abm|reproduce|spatial|bayesian|dsl|audio] [description of data and research question]"
user-invocable: true
---

# Scholar Computational Methods

You are an expert computational social scientist. You **run executable analyses**, validate results, and produce publication-quality outputs with prose ready for the Methods and Results sections. You meet the reproducibility standards of Nature Computational Science, Science Advances, and top sociology journals.

## Arguments and Module Routing

The user has provided: `$ARGUMENTS`

**Step 1 — Detect causal intent (CRITICAL):**
If the argument contains causal keywords — `effect of`, `impact of`, `causal`, `DiD`, `IV`, `RD`, `instrumental variable`, `matching`, `mediation` — and the method is NOT Double ML or Causal Forest being used to estimate that effect: **stop and invoke `/scholar-causal` first** to establish the identification strategy.

**Step 2 — Route to module:**

| Keyword(s) in argument | Module |
|------------------------|--------|
| `text`, `nlp`, `topic`, `bert`, `stm`, `embedding`, `corpus`, `tweets`, `news`, `interview` | MODULE 1 |
| `ml`, `predict`, `classify`, `random forest`, `xgboost`, `dml`, `causal forest`, `double ml` | MODULE 2 |
| `network`, `graph`, `ergm`, `siena`, `edge`, `node`, `tie`, `community`, `interaction sequence`, `relational event` | MODULE 3 |
| `abm`, `simulation`, `agent`, `schelling`, `mesa`, `netlogo`, `emergence` | MODULE 4 |
| `reproduce`, `replication`, `environment`, `docker`, `conda`, `pipeline` | MODULE 5 |
| `image`, `video`, `photo`, `visual`, `clip`, `vit`, `convnet`, `street view`, `satellite`, `protest image`, `aerial`, `computer vision` | MODULE 6 |
| `llm analysis`, `gpt analysis`, `claude analysis`, `agent workflow`, `structured extraction`, `grounded theory`, `document qa`, `llm pipeline` | MODULE 7 |
| `synthetic data`, `synthetic respondents`, `silicon sampling`, `simulate survey`, `simulate respondents`, `persona simulation`, `context engineering`, `prompt engineering simulation`, `llm survey`, `llm respondents`, `vignette simulation`, `conjoint simulation`, `opinion formation`, `synthetic population`, `simulated behavior`, `hiring simulation`, `organizational simulation`, `group behavior simulation` | MODULE 8 |
| `spatial`, `geospatial`, `choropleth`, `moran`, `spatial lag`, `spatial error`, `spdep`, `census tract`, `county-level`, `geographic clustering`, `neighborhood effects`, `local indicators`, `LISA`, `spatial autocorrelation`, `spatial regression` | MODULE 9 |
| `audio`, `speech`, `sound`, `whisper`, `transcribe`, `transcription`, `essentia`, `mfcc`, `acoustic`, `podcast`, `debate`, `oral history`, `voice`, `speaker diarization`, `audio classification`, `audio features`, `waveform` | MODULE 10 |
| `bertopic`, `dynamic topics`, `hierarchical topics`, `topic over time` | MODULE 1 (Step 3b) |
| `wordfish`, `wordscores`, `text scaling`, `political positions`, `ideological scaling` | MODULE 1 (Step 3c) |
| `multilingual`, `cross-lingual`, `xlm-roberta`, `mbert`, `language detection`, `multilingual topic`, `cross-lingual transfer`, `multilingual nlp` | MODULE 1 (Step 3d) |
| `dsl`, `design supervised learning`, `bias correction annotation`, `predicted variable regression`, `predicted labels regression` | MODULE 1 (Step 8) |
| `bayesian`, `brms`, `stan`, `mcmc`, `posterior predictive`, `credible interval`, `prior`, `bayes factor`, `hierarchical bayes` | MODULE 2 (Step 5b) |
| `conformal`, `conformal prediction`, `prediction set`, `prediction interval`, `coverage guarantee`, `mapie`, `uncertainty quantification` | MODULE 2 (Step 5c) |
| `gnn`, `node embedding`, `node2vec`, `graphsage`, `gcn`, `graph neural`, `link prediction`, `node classification` | MODULE 3 (Step 2b) |
| `multimodal`, `multimodal fusion`, `text image`, `clip fusion`, `late fusion`, `early fusion`, `text-image alignment` | MODULE 6 (Step 7b) |

If multiple modules apply, run them in sequence. If unclear, ask the user to specify.

---

## MODULE 0: Setup (All Modules)

Run before any module:

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
mkdir -p "${OUTPUT_ROOT}/tables" "${OUTPUT_ROOT}/figures" "${OUTPUT_ROOT}/models" "${OUTPUT_ROOT}/logs" "${OUTPUT_ROOT}/scripts"
```

**Process Logging (REQUIRED):**

Initialize the process log NOW by running:

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
mkdir -p "${OUTPUT_ROOT}/logs"
SKILL_NAME="scholar-compute"
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
SKILL_NAME="scholar-compute"
LOG_DATE=$(date +%Y-%m-%d)
LOG_FILE="${OUTPUT_ROOT}/logs/process-log-${SKILL_NAME}-${LOG_DATE}.md"
if [ ! -f "$LOG_FILE" ]; then
  LOG_FILE=$(ls -t "${OUTPUT_ROOT}"/logs/process-log-${SKILL_NAME}-${LOG_DATE}*.md 2>/dev/null | head -1)
fi
echo "| [step#] | $(date +%H:%M:%S) | [Step Name] | [1-line action summary] | [output files or —] | ✓ |" >> "$LOG_FILE"
```

**IMPORTANT:** Shell variables do NOT persist across Bash tool calls. Every step MUST re-derive LOG_FILE before appending.

**Source the publication visualization theme (MANDATORY for all figures):**

```r
# R — source at the top of every R script that produces figures
viz_path <- file.path(Sys.getenv("SCHOLAR_SKILL_DIR", unset = "."), ".claude/skills/scholar-analyze/references/viz_setting.R")
if (file.exists(viz_path)) source(viz_path) else message("viz_setting.R not found at ", viz_path, " — define theme inline")
# Provides: theme_Publication(), scale_fill_Publication(), scale_colour_Publication()
# ── VISUALIZATION RULES (MANDATORY) ──────────────────────────────
# 1. NEVER use ggtitle() or labs(title = ...) — titles go in manuscript captions
# 2. ALWAYS use theme_Publication() — never theme_minimal(), theme_bw(), etc.
#    Exception: theme_void() is OK for maps/choropleths
# 3. ALWAYS use scale_colour_Publication() or palette_cb for colors
# 4. ALWAYS save both PDF (cairo_pdf) and PNG (300 DPI) via save_fig()
# 5. Axis labels in plain language, not raw variable names
# ──────────────────────────────────────────────────────────────────

# Colorblind-safe 8-color palette (Wong 2011)
palette_cb <- c("#000000","#E69F00","#56B4E9","#009E73",
                "#F0E442","#0072B2","#D55E00","#CC79A7")

# Save helper — always export PDF (print) + PNG (screen)
save_fig <- function(p, name, w = 7, h = 5) {
  ggsave(paste0("${OUTPUT_ROOT}/figures/", name, ".pdf"), p, width = w, height = h)
  ggsave(paste0("${OUTPUT_ROOT}/figures/", name, ".png"), p, width = w, height = h, dpi = 300)
}
```

```python
# Python — use for all matplotlib/seaborn figures
import matplotlib.pyplot as plt
plt.rcParams.update({
    "font.family": "Helvetica Neue",
    "font.size": 12,
    "axes.spines.top": False,
    "axes.spines.right": False,
    "axes.grid": False,
    "figure.dpi": 300,
    "savefig.bbox": "tight"
})
PALETTE_CB = ["#000000","#E69F00","#56B4E9","#009E73",
              "#F0E442","#0072B2","#D55E00","#CC79A7"]
```

**All R figures MUST use `theme_Publication()` instead of `theme_minimal()` or other defaults.** All Python figures MUST apply the rcParams above. This ensures visual consistency with `scholar-analyze` and `scholar-eda` outputs.

**Set all random seeds (report these in the Methods section):**

```python
# Python
import random, numpy as np, torch
SEED = 42
random.seed(SEED); np.random.seed(SEED); torch.manual_seed(SEED)
if torch.cuda.is_available(): torch.cuda.manual_seed_all(SEED)
```

```r
# R
set.seed(42)
```

---

## Script Archive Protocol (All Modules)

This protocol applies to **every module** in scholar-compute. It ensures all executed code is saved as self-contained scripts with decision rationale, so that `/scholar-open` CODE-SHARE can assemble replication packages from actual artifacts rather than reconstructed approximations.

### Initialize (if not already done)

If `output/[slug]/scripts/coding-decisions-log.md` does not exist, create it:

```bash
if [ ! -f ${OUTPUT_ROOT}/scripts/coding-decisions-log.md ]; then
cat > ${OUTPUT_ROOT}/scripts/coding-decisions-log.md << 'LOGEOF'
# Coding Decisions Log
<!-- Append-only log. Each entry records one analytic decision with rationale. -->

| Timestamp | Module | Step | Decision | Alternatives Considered | Rationale | Key Parameters | Script |
|-----------|--------|------|----------|------------------------|-----------|----------------|--------|
LOGEOF
fi

if [ ! -f ${OUTPUT_ROOT}/scripts/script-index.md ]; then
cat > ${OUTPUT_ROOT}/scripts/script-index.md << 'IDXEOF'
# Script Index

## Run Order

| # | Script | Module | Purpose | Input | Output | Paper Element |
|---|--------|--------|---------|-------|--------|---------------|
IDXEOF
fi
```

### After Each Module Completes

1. **Consolidate** all R/Python code from the module into self-contained script(s)
2. **Add standard header** to each script:
   ```python
   # ============================================================
   # Script: [prefix]-[module-name].[ext]
   # Purpose: [one-line description]
   # Module: MODULE [N] — [module name]
   # Input:   [data file or prior output]
   # Output:  [models, tables, figures produced]
   # Date:    [YYYY-MM-DD]
   # Seed:    42 (set in all stochastic steps)
   # Key params: [K=20, window=6, n_estimators=500, etc.]
   # ============================================================
   ```
3. **Save** to `output/[slug]/scripts/[prefix]-[module-name].[ext]` using the module numbering ranges below
4. **Append decision entries** to `output/[slug]/scripts/coding-decisions-log.md`:
   - Method selection (why STM vs. BERTopic vs. LDA; why DML vs. Causal Forest)
   - Parameter choices (K, window size, learning rate, number of estimators)
   - Validation approach (train/test split ratio, cross-validation folds, human benchmark N)
   - Preprocessing decisions (stopword removal, lemmatization, normalization)
5. **Append rows** to `output/[slug]/scripts/script-index.md`

### Module → Prefix Mapping

| Prefix range | Module | Example filename |
|-------------|--------|-----------------|
| `20-29` | MODULE 1: NLP/Text | `20-stm-topic-model.R`, `21-conText-embedding.R` |
| `30-39` | MODULE 2: ML/DML | `30-dml-estimation.R`, `31-causal-forest.R` |
| `40-49` | MODULE 3: Networks | `40-ergm-estimation.R`, `41-rem-goldfish.R` |
| `50-59` | MODULE 4: ABM | `50-mesa-abm.py`, `51-netlogo-nlrx.R` |
| `60-69` | MODULE 6: CV | `60-clip-zero-shot.py`, `61-dinov2-features.py` |
| `70-79` | MODULE 7: LLM Analysis | `70-structured-extraction.py`, `71-grounded-theory-loop.py` |
| `80-89` | MODULE 8: Synthetic Data | `80-synthetic-survey.py`, `81-validation-ks.R` |
| `90-94` | MODULE 9: Geospatial | `90-spatial-lag-model.R`, `91-lisa-map.R` |
| `95-99` | MODULE 10: Audio | `95-whisper-transcription.py`, `96-essentia-features.py` |

**No-data mode:** Save scripts with `# [CODE-TEMPLATE] — run when data available` as the first line after the header.

---

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

## MODULE 2: Machine Learning for Social Science

### Step 1 — Goal Gate

Before choosing a model, be explicit about the goal:

| Goal | Appropriate method |
|------|--------------------|
| Does X *cause* Y? | Causal identification strategy → `/scholar-causal` |
| Predict Y as accurately as possible | ML (RF, XGBoost, NN) |
| Classify records / text into categories | Supervised ML with held-out test set |
| Causal effect with many confounders | Double ML / Causal Forest (Step 4) |

**Do NOT interpret ML feature importance as a causal effect.**

### Step 2 — Causal Gate

If the research question involves causal inference AND the user is not already running DML/Causal Forest as the primary estimator: invoke `/scholar-causal` first.

### Step 3 — Supervised Learning Workflow

```python
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler
from sklearn.ensemble import GradientBoostingClassifier, RandomForestClassifier
from sklearn.model_selection import StratifiedKFold, cross_validate
from sklearn.metrics import make_scorer, f1_score, roc_auc_score
import joblib

# Define pipeline
pipe = Pipeline([
    ("scaler", StandardScaler()),
    ("clf",    GradientBoostingClassifier(
                   n_estimators=200, max_depth=4,
                   learning_rate=0.05, random_state=42))
])

# 5-fold stratified cross-validation
cv      = StratifiedKFold(n_splits=5, shuffle=True, random_state=42)
scoring = {"auc": "roc_auc",
           "f1":  make_scorer(f1_score, average="weighted"),
           "acc": "accuracy"}
results = cross_validate(pipe, X_train, y_train, cv=cv, scoring=scoring)

print(f"CV AUC: {results['test_auc'].mean():.3f} ± {results['test_auc'].std():.3f}")
print(f"CV F1:  {results['test_f1'].mean():.3f}  ± {results['test_f1'].std():.3f}")

# Fit on full training set; evaluate on held-out test set
pipe.fit(X_train, y_train)
joblib.dump(pipe, "${OUTPUT_ROOT}/models/clf_final.pkl")

from sklearn.metrics import classification_report
print(classification_report(y_test, pipe.predict(X_test)))
```

### Step 4 — Hyperparameter Tuning (Optuna)

```python
import optuna
from sklearn.ensemble import GradientBoostingClassifier
from sklearn.model_selection import cross_val_score, StratifiedKFold

def objective(trial):
    params = {
        "n_estimators":  trial.suggest_int("n_estimators", 100, 500),
        "max_depth":     trial.suggest_int("max_depth", 2, 6),
        "learning_rate": trial.suggest_float("learning_rate", 1e-3, 0.3, log=True),
        "subsample":     trial.suggest_float("subsample", 0.6, 1.0),
        "random_state":  42
    }
    clf    = GradientBoostingClassifier(**params)
    cv     = StratifiedKFold(n_splits=5, shuffle=True, random_state=42)
    scores = cross_val_score(clf, X_train, y_train, cv=cv, scoring="roc_auc")
    return scores.mean()

study = optuna.create_study(direction="maximize",
                             sampler=optuna.samplers.TPESampler(seed=42))
study.optimize(objective, n_trials=100, show_progress_bar=True)

print("Best AUC:", study.best_value)
print("Best params:", study.best_params)

# Report: "Hyperparameters were selected via Bayesian optimization (Optuna;
# Akiba et al. 2019) with 100 trials and 5-fold CV; best AUC = [X]."
```

### Step 5 — Double ML / Causal Forests

For causal estimation with high-dimensional controls:

```python
from econml.dml import LinearDML, CausalForestDML
from sklearn.ensemble import GradientBoostingRegressor, GradientBoostingClassifier

# Average treatment effect (ATE) via Double ML
dml = LinearDML(
    model_y = GradientBoostingRegressor(random_state=42),
    model_t = GradientBoostingClassifier(random_state=42),
    discrete_treatment = True, cv=5, random_state=42
)
dml.fit(Y=y, T=treatment, X=None, W=W_controls)
ate    = dml.ate()
ate_ci = dml.ate_interval(alpha=0.05)
print(f"ATE = {ate:.4f}, 95% CI = [{ate_ci[0]:.4f}, {ate_ci[1]:.4f}]")

# Heterogeneous treatment effects (CATE) via Causal Forest
cf = CausalForestDML(
    model_y=GradientBoostingRegressor(random_state=42),
    model_t=GradientBoostingClassifier(random_state=42),
    n_estimators=500, discrete_treatment=True, random_state=42
)
cf.fit(Y=y, T=treatment, X=X_moderators, W=W_controls)

# CATE summary by subgroup
from econml.cate_interpreter import SingleTreeCATEInterpreter
interp = SingleTreeCATEInterpreter(max_depth=3)
interp.interpret(cf, X_moderators)
interp.plot(feature_names=feature_names)
```

```r
# Causal Forest in R (grf package)
library(grf)
cf  <- causal_forest(X=X_matrix, Y=outcome, W=treatment,
                     num.trees=2000, seed=42)
ate <- average_treatment_effect(cf)
best_linear_projection(cf, X_matrix)  # linear summary of heterogeneity
```

### Step 5b — Bayesian Regression with brms / Stan

**When to use over frequentist regression**: (1) Small N with sparse data where MLE estimates are unstable; (2) Complex hierarchical / cross-classified models that are hard to fit with `lme4`; (3) Uncertainty propagation is important (posterior predictive checks); (4) Informative priors are available from prior literature or meta-analyses; (5) Estimating full posterior distributions for complex quantities (e.g., ratios, products of parameters).

**Not needed when**: N is large, standard MLE converges, and credible intervals ≈ confidence intervals.

```r
library(brms)
library(tidybayes)
library(bayesplot)
library(ggplot2)

# ── Step 1: Specify model ─────────────────────────────────────────────
# brms uses lme4-style formula syntax; priors specified with prior()
# bf(): brmsformula; allows custom non-linear or mixture models

# Example: multilevel logistic regression (cross-classified by state + year)
m_bayes <- brm(
  formula  = outcome ~ treatment + education + income + (1 | state) + (1 | year),
  data     = df,
  family   = bernoulli(link = "logit"),
  prior    = c(
    prior(normal(0, 1),   class = b),           # weakly informative for fixed effects
    prior(normal(0, 0.5), class = Intercept),   # logit scale
    prior(exponential(1), class = sd)            # half-exponential for random effect SDs
  ),
  chains   = 4,
  iter     = 4000,
  warmup   = 2000,
  cores    = 4,
  seed     = 42,
  backend  = "cmdstanr",   # faster than rstan; install: install.packages("cmdstanr")
  file     = "${OUTPUT_ROOT}/models/brms-multilevel-logit"  # cache — skip refit if unchanged
)

# ── Step 2: Check convergence ─────────────────────────────────────────
summary(m_bayes)   # check Rhat ≈ 1.00; Bulk_ESS and Tail_ESS > 400

# Trace plots (visual convergence check)
mcmc_trace(m_bayes, pars = c("b_treatment", "b_education"))
ggsave("${OUTPUT_ROOT}/figures/bayes-trace.pdf", width=10, height=6)

# ── Step 3: Posterior predictive check ───────────────────────────────
pp_check(m_bayes, ndraws=100, type="dens_overlay")
ggsave("${OUTPUT_ROOT}/figures/bayes-ppc.pdf", width=8, height=5)

# ── Step 4: Extract and summarize posterior ───────────────────────────
# Posterior draws for all parameters
draws <- as_draws_df(m_bayes)

# Credible intervals (95% central CI)
posterior_summary(m_bayes, probs=c(0.025, 0.975))[, c("Estimate","Q2.5","Q97.5")]

# Probability of direction (P(β > 0))
hypothesis(m_bayes, "treatment > 0")

# ── Step 5: Marginal effects / conditional means ──────────────────────
library(marginaleffects)
# Average marginal effect (AME) on the probability scale
avg_slopes(m_bayes, variables="treatment")

# Conditional effects plot
conditional_effects(m_bayes, effects="treatment:education") |>
  plot(points=FALSE)

# ── Step 6: Model comparison ──────────────────────────────────────────
# LOO-CV (leave-one-out cross-validation; preferred over WAIC for finite N)
loo_m1 <- loo(m_bayes)
loo_m0 <- loo(m_bayes_null)
loo_compare(loo_m1, loo_m0)   # elpd_diff > 4 SE units → clear preference

# ── Step 7: Table export ──────────────────────────────────────────────
library(modelsummary)
modelsummary(m_bayes,
             statistic    = "conf.int",  # report 95% CIs instead of SEs
             conf_level   = 0.95,
             output       = "${OUTPUT_ROOT}/tables/table-bayes.html")
```

**Prior selection guidance**:
| Parameter | Weakly informative prior | Informative prior (if meta-analysis available) |
|-----------|--------------------------|------------------------------------------------|
| Fixed effect (log-odds scale) | `normal(0, 1)` | `normal(μ_meta, σ_meta)` |
| Fixed effect (standardized continuous) | `normal(0, 0.5)` | From prior literature |
| Intercept (logit) | `normal(0, 1.5)` | Based on base rate |
| Random effect SD | `exponential(1)` | `half-normal(0, σ)` |
| Correlation of random effects | `lkj(2)` (regularizing) | Default |

**Reporting template:**
> "We fit a Bayesian multilevel logistic regression using `brms` (Bürkner 2017) with `cmdstanr` as the backend. We specified weakly informative priors: normal(0, 1) for fixed effects (log-odds scale), exponential(1) for random-effect standard deviations. We ran 4 chains of 4,000 iterations (2,000 warmup), with all chains showing convergence (R̂ ≤ 1.01; bulk ESS > 400 for all parameters). Posterior predictive checks confirmed adequate model fit. We report posterior means and 95% central credible intervals (CI). The average marginal effect of [treatment] on the probability of [outcome] was [X] (95% CI = [[lo], [hi]]), indicating [interpretation]."

### Step 5c — Conformal Prediction: Distribution-Free Uncertainty Quantification

**When to use**: When you need calibrated uncertainty estimates for ML predictions without distributional assumptions. Conformal prediction provides **prediction sets** (classification) or **prediction intervals** (regression) with guaranteed finite-sample coverage, regardless of the underlying model. This is valuable for: (1) Reporting honest uncertainty around ML-based classifications in social science; (2) Identifying ambiguous cases that need human review; (3) Communicating prediction reliability to non-technical audiences; (4) Complementing point predictions with principled intervals for policy-relevant research.

**Not needed when**: You already use Bayesian methods (brms/Stan) that produce posterior credible intervals, or when the goal is purely causal inference (use `/scholar-causal`).

| Task | Method | Package |
|------|--------|---------|
| Classification prediction sets | Split conformal, APS, RAPS | `mapie` (Python) |
| Regression prediction intervals | Split conformal, CV+ | `mapie` (Python) |
| Classification (R) | Split conformal, jackknife+ | `conformalInference` |
| Regression (R) | Conformal intervals | `conformalInference`, `cfcausal` |
| Conditional coverage | Mondrian conformal | `mapie` with grouping |

**Installation:**

```bash
# Python
pip install mapie

# R
# install.packages("conformalInference")
# Or from GitHub for latest: devtools::install_github("ryantibs/conformal/conformalInference")
```

**Option A — Conformal classification (Python, MAPIE):**

```python
# pip install mapie
from mapie.classification import MapieClassifier
from sklearn.ensemble import GradientBoostingClassifier
from sklearn.model_selection import train_test_split
from sklearn.metrics import f1_score
import numpy as np, pandas as pd

SEED = 42
np.random.seed(SEED)

# Split: train (60%), calibration (20%), test (20%)
X_trainval, X_test, y_trainval, y_test = train_test_split(
    X, y, test_size=0.2, random_state=SEED, stratify=y
)
X_train, X_calib, y_train, y_calib = train_test_split(
    X_trainval, y_trainval, test_size=0.25, random_state=SEED, stratify=y_trainval
)

# Fit base classifier on training set
base_clf = GradientBoostingClassifier(n_estimators=200, max_depth=4,
                                       random_state=SEED)
base_clf.fit(X_train, y_train)

# Wrap with MAPIE for conformal prediction sets
# method="score": Adaptive Prediction Sets (APS); provides smaller sets
mapie_clf = MapieClassifier(estimator=base_clf, cv="prefit", method="score")
mapie_clf.fit(X_calib, y_calib)

# Predict with coverage guarantee (1 - alpha)
alpha = 0.10   # target 90% coverage
y_pred, y_sets = mapie_clf.predict(X_test, alpha=alpha)
# y_sets: boolean array (N_test, N_classes, 1) — True = class in prediction set

# Evaluate
empirical_coverage = y_sets[np.arange(len(y_test)), y_test, 0].mean()
avg_set_size       = y_sets[:, :, 0].sum(axis=1).mean()
print(f"Target coverage: {1-alpha:.0%}")
print(f"Empirical coverage: {empirical_coverage:.3f}")
print(f"Average prediction set size: {avg_set_size:.2f}")
print(f"Point prediction F1 (macro): {f1_score(y_test, y_pred, average='macro'):.3f}")

# Identify ambiguous cases (prediction set size > 1)
ambiguous_mask = y_sets[:, :, 0].sum(axis=1) > 1
print(f"Ambiguous cases (set size > 1): {ambiguous_mask.sum()} / {len(y_test)} "
      f"({ambiguous_mask.mean():.1%})")

# Save results
results_df = pd.DataFrame({
    "y_true": y_test,
    "y_pred": y_pred,
    "set_size": y_sets[:, :, 0].sum(axis=1),
    "ambiguous": ambiguous_mask,
    **{f"class_{c}_in_set": y_sets[:, c, 0] for c in range(y_sets.shape[1])}
})
results_df.to_csv("${OUTPUT_ROOT}/tables/conformal-classification.csv", index=False)
```

**Option B — Conformal regression intervals (Python, MAPIE):**

```python
from mapie.regression import MapieRegressor
from sklearn.ensemble import GradientBoostingRegressor

# Fit base regressor
base_reg = GradientBoostingRegressor(n_estimators=200, max_depth=4,
                                      random_state=SEED)

# CV+ method: uses cross-validation residuals (no separate calibration set needed)
mapie_reg = MapieRegressor(estimator=base_reg, cv=5, method="plus")
mapie_reg.fit(X_train, y_train)

# Predict with 90% prediction interval
alpha = 0.10
y_pred, y_intervals = mapie_reg.predict(X_test, alpha=alpha)
# y_intervals: (N_test, 2, 1) — lower and upper bounds

lower = y_intervals[:, 0, 0]
upper = y_intervals[:, 1, 0]

# Evaluate coverage and interval width
coverage      = ((y_test >= lower) & (y_test <= upper)).mean()
avg_width     = (upper - lower).mean()
median_width  = np.median(upper - lower)
print(f"Target coverage: {1-alpha:.0%}")
print(f"Empirical coverage: {coverage:.3f}")
print(f"Mean interval width: {avg_width:.3f}")
print(f"Median interval width: {median_width:.3f}")

# Save
pd.DataFrame({
    "y_true": y_test, "y_pred": y_pred,
    "lower": lower, "upper": upper,
    "width": upper - lower
}).to_csv("${OUTPUT_ROOT}/tables/conformal-regression.csv", index=False)

# Visualization: prediction intervals sorted by predicted value
import matplotlib.pyplot as plt
order = np.argsort(y_pred)
fig, ax = plt.subplots(figsize=(10, 5))
ax.fill_between(range(len(y_pred)), lower[order], upper[order],
                alpha=0.3, color=PALETTE_CB[2], label=f"{1-alpha:.0%} prediction interval")
ax.scatter(range(len(y_pred)), y_test[order], s=8, color=PALETTE_CB[0],
           label="Observed", zorder=3)
ax.plot(range(len(y_pred)), y_pred[order], color=PALETTE_CB[1],
        linewidth=1, label="Predicted")
ax.set_xlabel("Test observations (sorted by prediction)")
ax.set_ylabel("Outcome")
ax.legend()
plt.savefig("${OUTPUT_ROOT}/figures/conformal-intervals.pdf", dpi=300, bbox_inches="tight")
plt.savefig("${OUTPUT_ROOT}/figures/conformal-intervals.png", dpi=300, bbox_inches="tight")
```

**Option C — Conformal prediction in R (conformalInference):**

```r
# install.packages("conformalInference")
library(conformalInference)
library(randomForest)
library(tidyverse)

set.seed(42)

# Define training and prediction functions for conformalInference
train_fn   <- function(x, y, ...) randomForest(x, y, ntree = 500)
predict_fn <- function(obj, newx, ...) predict(obj, newx)

# Split conformal regression intervals
conf_result <- conformal.pred.split(
  x      = as.matrix(X_train),
  y      = y_train,
  x0     = as.matrix(X_test),
  train.fun   = train_fn,
  predict.fun = predict_fn,
  alpha  = 0.10   # 90% coverage
)

# Results
test_results <- tibble(
  y_true = y_test,
  y_pred = conf_result$pred,
  lower  = conf_result$lo,
  upper  = conf_result$up,
  width  = conf_result$up - conf_result$lo
)

coverage <- mean(test_results$y_true >= test_results$lower &
                 test_results$y_true <= test_results$upper)
cat(sprintf("Empirical coverage: %.3f\n", coverage))
cat(sprintf("Mean interval width: %.3f\n", mean(test_results$width)))

write_csv(test_results, "${OUTPUT_ROOT}/tables/conformal-regression-r.csv")

# Conditional coverage by subgroup (Mondrian-style)
# Check if coverage is uniform across key groups
test_results$group <- X_test_df$race   # example grouping variable
test_results |>
  group_by(group) |>
  summarize(
    n        = n(),
    coverage = mean(y_true >= lower & y_true <= upper),
    avg_width = mean(width)
  ) |>
  write_csv("${OUTPUT_ROOT}/tables/conformal-conditional-coverage.csv")
```

**Validation approach:**
- Report empirical coverage on the test set; it should match the nominal level (e.g., 90% +/- 2%)
- Report average and median prediction set size (classification) or interval width (regression)
- Check conditional coverage across key subgroups (race, gender, SES) to detect unfairness
- Compare conformal intervals to naive percentile bootstrap intervals and Bayesian credible intervals
- For classification, report the fraction of ambiguous cases (set size > 1) and analyze what makes them ambiguous

**Reporting template:**
> "We quantify prediction uncertainty using conformal prediction (Vovk et al. 2005), which provides distribution-free prediction [sets / intervals] with finite-sample coverage guarantees. We use the [APS / CV+ / split conformal] method implemented in `mapie` (Taquet et al. 2022) [/ `conformalInference` (Tibshirani et al. 2019)]. At the 90% nominal coverage level, the empirical coverage on the held-out test set (N = [X]) is [X]%, with an average prediction [set size of [X] classes / interval width of [X] units]. [X]% of test observations have ambiguous prediction sets (size > 1), suggesting [interpretation about boundary cases]. Conditional coverage across [demographic subgroups] ranges from [X]% to [X]%, indicating [uniform / non-uniform] reliability across groups. All models use seed = 42."

---

### Step 6 — SHAP Interpretability

Required by NCS and Science Advances for ML-based findings:

```python
import shap

explainer   = shap.TreeExplainer(pipe["clf"])
shap_values = explainer.shap_values(X_test)

# Summary plot: feature importance + direction
shap.summary_plot(shap_values, X_test, feature_names=feature_names,
                  show=False)
import matplotlib.pyplot as plt
plt.savefig("${OUTPUT_ROOT}/figures/fig-shap-summary.pdf", bbox_inches="tight", dpi=300)

# Dependence plot for key feature
shap.dependence_plot("education", shap_values, X_test,
                     feature_names=feature_names, show=False)
plt.savefig("${OUTPUT_ROOT}/figures/fig-shap-education.pdf", bbox_inches="tight", dpi=300)
```

### Step 7 — ML Verification (Subagent)

```
ML VERIFICATION REPORT
=======================

GOAL / METHOD ALIGNMENT
[ ] Prediction goal → ML used; causal goal → /scholar-causal invoked or DML used
[ ] Feature importances NOT interpreted as causal effects

VALIDATION
[ ] Train/val/test split documented (ratios reported)
[ ] Cross-validation used (not train-set performance)
[ ] F1 (macro + weighted), AUC-ROC reported on test set
[ ] Accuracy NOT reported as sole metric for imbalanced classes
[ ] N per class reported alongside metrics

HYPERPARAMETERS
[ ] All hyperparameters and search space reported
[ ] Selection method documented (grid search / Optuna / random)
[ ] Best hyperparameters tabulated in supplementary

SHAP
[ ] SHAP values computed and saved
[ ] Summary plot saved to output/[slug]/figures/
[ ] Direction of SHAP effects discussed in text

DOUBLE ML / CAUSAL FOREST (if used)
[ ] Nuisance model specifications reported
[ ] Cross-fitting folds specified (cv=5)
[ ] ATE with 95% CI reported
[ ] CATE heterogeneity plot saved

BAYESIAN brms (if used)
[ ] Rhat ≤ 1.01 for all parameters
[ ] Bulk ESS and Tail ESS > 400 for all key parameters
[ ] Trace plots saved (visual convergence check)
[ ] Posterior predictive check (pp_check) run and saved
[ ] Prior specifications documented and justified
[ ] LOO-CV used for model comparison (not WAIC alone)
[ ] 95% credible intervals reported (not p-values)
[ ] file= argument set to cache model (avoid refitting)

CONFORMAL PREDICTION (if used)
[ ] Separate calibration set held out (or CV+ method used)
[ ] Nominal coverage level stated (e.g., 90%)
[ ] Empirical coverage on test set reported and matches nominal level (±2%)
[ ] Average prediction set size (classification) or interval width (regression) reported
[ ] Conditional coverage checked across key subgroups
[ ] Ambiguous cases (set size > 1) analyzed and reported
[ ] Prediction interval figure saved to output/[slug]/figures/
[ ] Comparison to alternative UQ methods (bootstrap / Bayesian) if applicable

SEEDS AND MODELS
[ ] random_state=42 / seed=42 set in all stochastic objects
[ ] Fitted model saved to output/[slug]/models/

RESULT: [PASS / NEEDS REVISION]
Issues: [list]
```

---

## MODULE 3: Network Analysis

### Step 1 — Build Network

```python
import networkx as nx, pandas as pd

# From edge list
edges = pd.read_csv("edges.csv")   # source, target, [weight, time, type]
G = nx.from_pandas_edgelist(edges, "sender", "receiver",
                             edge_attr=["weight"],
                             create_using=nx.DiGraph())
# Attach node attributes
nodes = pd.read_csv("nodes.csv")   # id, [age, sex, education, ...]
nx.set_node_attributes(G, nodes.set_index("id").to_dict("index"))
print(f"N={G.number_of_nodes()}, E={G.number_of_edges()}, density={nx.density(G):.4f}")
```

```r
library(igraph)
g <- graph_from_data_frame(edges_df, directed=TRUE, vertices=nodes_df)
```

### Step 2 — Descriptive Network Measures

```python
def compute_centrality(G):
    G_u = G.to_undirected()
    return pd.DataFrame({
        "degree":      nx.degree_centrality(G),
        "indegree":    nx.in_degree_centrality(G),
        "outdegree":   nx.out_degree_centrality(G),
        "betweenness": nx.betweenness_centrality(G, normalized=True),
        "closeness":   nx.closeness_centrality(G),
        "pagerank":    nx.pagerank(G),
        "clustering":  nx.clustering(G_u),
    })

centrality_df = compute_centrality(G)
centrality_df.to_csv("${OUTPUT_ROOT}/tables/network-centrality.csv")
```

**Report**: N nodes, N edges, density, directed/undirected, weighted/binary, whether isolates included, data period.

### Step 2b — GNN / Node Embedding for Social Network Analysis

**When to use**: When you need low-dimensional node representations that capture structural position *and* node attributes for downstream tasks (link prediction, node classification, community detection). GNNs learn embeddings that outperform hand-crafted centrality measures when the network is large (N > 1,000 nodes), attributed, and the task is predictive rather than inferential.

| Goal | Recommended approach | Package |
|------|---------------------|---------|
| Unsupervised node embeddings (no labels) | **node2vec** | `node2vec`, `torch_geometric` |
| Node classification (labeled nodes) | **GraphSAGE** or **GCN** | `torch_geometric` (PyG) |
| Link prediction (predict missing/future ties) | **GCN + link decoder** | `torch_geometric` |
| Community detection via learned embeddings | node2vec + k-means / HDBSCAN | `node2vec`, `sklearn` |
| Heterogeneous graphs (multiple node/edge types) | **R-GCN** | `torch_geometric` |

**Installation:**

```bash
# PyTorch Geometric (PyG) — check https://pytorch-geometric.readthedocs.io for CUDA-specific install
pip install torch-geometric node2vec
# Alternative: DGL (Deep Graph Library)
# pip install dgl
```

**Option A — node2vec (unsupervised, scalable):**

```python
# pip install node2vec
import networkx as nx, numpy as np, pandas as pd
from node2vec import Node2Vec

# G: networkx graph (from Step 1)
node2vec = Node2Vec(
    G, dimensions=128, walk_length=30, num_walks=200,
    p=1.0,  # return parameter (1.0 = balanced BFS/DFS)
    q=1.0,  # in-out parameter (< 1 = BFS-like; > 1 = DFS-like)
    workers=4, seed=42
)
model_n2v = node2vec.fit(window=10, min_count=1, batch_words=4)

# Extract embeddings as DataFrame
embeddings = pd.DataFrame(
    [model_n2v.wv[str(n)] for n in G.nodes()],
    index=list(G.nodes())
)
embeddings.to_csv("${OUTPUT_ROOT}/models/node2vec-embeddings.csv")

# Downstream: cluster embeddings for community detection
from sklearn.cluster import KMeans
kmeans = KMeans(n_clusters=5, random_state=42)
communities = kmeans.fit_predict(embeddings.values)
```

**Option B — GCN for node classification (PyTorch Geometric):**

```python
import torch
import torch.nn.functional as F
from torch_geometric.nn import GCNConv
from torch_geometric.utils import from_networkx
from sklearn.model_selection import train_test_split

SEED = 42
torch.manual_seed(SEED)

# Convert networkx graph to PyG Data object
# Requires node features: set as node attributes in G before conversion
# Example: nx.set_node_attributes(G, features_dict)  where features_dict = {node: {"x": [f1, f2, ...]}}
data = from_networkx(G, group_node_attrs=["x"])   # "x" = feature attribute name
data.y = torch.tensor(labels, dtype=torch.long)   # node labels

# Train/val/test masks (60/20/20)
nodes = list(range(data.num_nodes))
train_idx, test_idx = train_test_split(nodes, test_size=0.4, random_state=SEED,
                                        stratify=labels)
val_idx, test_idx   = train_test_split(test_idx, test_size=0.5, random_state=SEED,
                                        stratify=[labels[i] for i in test_idx])
data.train_mask = torch.zeros(data.num_nodes, dtype=torch.bool)
data.val_mask   = torch.zeros(data.num_nodes, dtype=torch.bool)
data.test_mask  = torch.zeros(data.num_nodes, dtype=torch.bool)
data.train_mask[train_idx] = True
data.val_mask[val_idx]     = True
data.test_mask[test_idx]   = True

class GCN(torch.nn.Module):
    def __init__(self, in_channels, hidden_channels, out_channels, dropout=0.5):
        super().__init__()
        self.conv1   = GCNConv(in_channels, hidden_channels)
        self.conv2   = GCNConv(hidden_channels, out_channels)
        self.dropout = dropout

    def forward(self, x, edge_index):
        x = self.conv1(x, edge_index)
        x = F.relu(x)
        x = F.dropout(x, p=self.dropout, training=self.training)
        x = self.conv2(x, edge_index)
        return x

device = "cuda" if torch.cuda.is_available() else "cpu"
model  = GCN(data.num_node_features, 64, len(torch.unique(data.y))).to(device)
data   = data.to(device)
optimizer = torch.optim.Adam(model.parameters(), lr=0.01, weight_decay=5e-4)

# Training loop
model.train()
for epoch in range(200):
    optimizer.zero_grad()
    out  = model(data.x, data.edge_index)
    loss = F.cross_entropy(out[data.train_mask], data.y[data.train_mask])
    loss.backward()
    optimizer.step()

# Evaluation
model.eval()
with torch.no_grad():
    pred = model(data.x, data.edge_index).argmax(dim=1)
    test_acc = (pred[data.test_mask] == data.y[data.test_mask]).float().mean().item()
    print(f"Test accuracy: {test_acc:.3f}")

# Save embeddings (penultimate layer)
model.eval()
with torch.no_grad():
    x = model.conv1(data.x, data.edge_index)
    x = F.relu(x)
    node_embeddings = x.cpu().numpy()
np.save("${OUTPUT_ROOT}/models/gcn-node-embeddings.npy", node_embeddings)

torch.save(model.state_dict(), "${OUTPUT_ROOT}/models/gcn-model.pt")
```

**Option C — GraphSAGE for inductive node classification** (generalizes to unseen nodes):

```python
from torch_geometric.nn import SAGEConv

class GraphSAGE(torch.nn.Module):
    def __init__(self, in_channels, hidden_channels, out_channels, dropout=0.5):
        super().__init__()
        self.conv1   = SAGEConv(in_channels, hidden_channels)
        self.conv2   = SAGEConv(hidden_channels, out_channels)
        self.dropout = dropout

    def forward(self, x, edge_index):
        x = self.conv1(x, edge_index)
        x = F.relu(x)
        x = F.dropout(x, p=self.dropout, training=self.training)
        x = self.conv2(x, edge_index)
        return x

# Training follows the same pattern as GCN above
# GraphSAGE is preferred for large graphs (>50K nodes) with mini-batch training:
from torch_geometric.loader import NeighborLoader
train_loader = NeighborLoader(
    data, num_neighbors=[10, 10], batch_size=256,
    input_nodes=data.train_mask, shuffle=True
)
```

**Option D — Link prediction** (predict missing/future ties):

```python
from torch_geometric.nn import GCNConv
from torch_geometric.utils import negative_sampling
from sklearn.metrics import roc_auc_score

class LinkPredictor(torch.nn.Module):
    def __init__(self, in_channels, hidden_channels):
        super().__init__()
        self.conv1 = GCNConv(in_channels, hidden_channels)
        self.conv2 = GCNConv(hidden_channels, hidden_channels)

    def encode(self, x, edge_index):
        x = F.relu(self.conv1(x, edge_index))
        return self.conv2(x, edge_index)

    def decode(self, z, edge_label_index):
        return (z[edge_label_index[0]] * z[edge_label_index[1]]).sum(dim=-1)

# Split edges into train/val/test using RandomLinkSplit
from torch_geometric.transforms import RandomLinkSplit
transform = RandomLinkSplit(num_val=0.1, num_test=0.1, is_undirected=True,
                             add_negative_train_samples=True, neg_sampling_ratio=1.0)
train_data, val_data, test_data = transform(data)

# Training: BCE loss on positive + negative edges
# Evaluation: AUC-ROC on held-out test edges
```

**Validation approach:**
- Node classification: F1 (macro) and accuracy on held-out test nodes (60/20/20 split)
- Link prediction: AUC-ROC on held-out test edges; compare vs. common-neighbors / Adamic-Adar baselines
- Community detection: compare GNN-derived communities vs. Leiden; report NMI and modularity
- Embedding quality: visualize with UMAP; check that known groups cluster

**Reporting template:**
> "We learn 128-dimensional node embeddings using [node2vec (Grover & Leskovec 2016) / a two-layer GCN (Kipf & Welling 2017) / GraphSAGE (Hamilton et al. 2017)] implemented in PyTorch Geometric (Fey & Lenssen 2019). The model takes as input the adjacency structure and [X] node-level features [list features]. For [node classification], we train on 60% of labeled nodes, validate on 20%, and evaluate on the held-out 20%, achieving test F1 (macro) = [X] and accuracy = [X]. [For link prediction], we hold out 10% of edges for testing and achieve AUC-ROC = [X], compared to [X] for a common-neighbors baseline. [For community detection], we cluster the learned embeddings via k-means (K = [X]), obtaining modularity Q = [X], compared to Q = [X] from Leiden on the raw adjacency. All models use seed = 42."

---

### Step 3 — Community Detection

```python
import leidenalg as la, igraph as ig   # Leiden preferred for research

G_u    = G.to_undirected()
ig_g   = ig.Graph.from_networkx(G_u)
leiden = la.find_partition(ig_g, la.ModularityVertexPartition, seed=42)
print(f"Leiden: {len(leiden)} communities, Q={leiden.modularity:.3f}")
```

```r
library(igraph)
cl_leiden  <- cluster_leiden(g, objective_function="modularity", resolution=1.0)
modularity(g, cl_leiden)
```

### Step 4 — ERGMs

```r
library(ergm); library(network)

net <- asNetwork(g)    # convert igraph to network

# Progressive model ladder
m0 <- ergm(net ~ edges)
m1 <- ergm(net ~ edges + nodematch("race"))
m2 <- ergm(net ~ edges
               + nodematch("race")
               + nodematch("education")
               + mutual
               + gwesp(0.5, fixed=TRUE),
           control=control.ergm(MCMC.samplesize=2000, seed=42))
summary(m2)

# Goodness-of-fit (REQUIRED — must match degree dist., triad census, geodesics)
gof_m2 <- gof(m2); plot(gof_m2)

# Export table
texreg::texreg(list(m0,m1,m2),
               file="${OUTPUT_ROOT}/tables/table-ergm.tex",
               caption="ERGM Results")
```

**Reporting template:**
> "We estimate ERGMs (Robins et al. 2007) to test whether tie formation is conditioned on node attributes and endogenous network structure. We include terms for density (edges), racial homophily (nodematch), reciprocity (mutual), and transitivity (GWESP). MCMC chains converged based on visual inspection of trace plots. GOF statistics indicate the model reproduces the observed degree distribution, triad census, and geodesic distances (Figure A[X])."

### Step 4b — Temporal ERGMs (tERGMs)

```r
library(btergm)
# Fit TERGM to panel of networks
tergm_mod <- btergm(networks ~ edges + mutual + gwesp(0.5, fixed = TRUE)
                    + nodematch("gender") + memory(type = "stability"),
                    R = 100, verbose = TRUE)
summary(tergm_mod)
# Interpretation: coefficients represent tendency controlling for prior network state
```

### Step 4c — Stochastic Block Models (SBM)

```python
import graph_tool.all as gt
# Fit SBM to detect latent community structure (allows overlapping membership)
g = gt.Graph(directed=False)
# ... add edges ...
state = gt.minimize_blockmodel_dl(g)
state.draw(output="sbm_communities.pdf")
b = state.get_blocks()  # Block assignments
```

### Step 4d — Ego-Network Analysis

```r
library(egor)
# Load ego-network data (alter attributes + ties between alters)
ego_data <- read_egor(egos = ego_df, alters = alter_df, aaties = tie_df)
# Constraint (Burt 1992)
ego_data <- ego_constraint(ego_data)
# Effective size
ego_data <- ego_effsize(ego_data)
summary(ego_data$ego$constraint)
```

### Step 5 — SAOMs / RSiena (Longitudinal Network Dynamics)

```r
library(RSiena)

friend_net <- sienaDependent(array(c(net_w1, net_w2), dim=c(N,N,2)))
behavior   <- sienaDependent(cbind(beh_w1, beh_w2), type="behavior")
sex        <- coCovar(sex_vec)

data    <- sienaDataCreate(friend_net, behavior, sex)
effects <- getEffects(data) |>
           includeEffects(transTrip, recip) |>
           includeEffects(egoX, altX, name="friend_net", interaction1="sex") |>
           includeEffects(name="behavior", totSim)

algo   <- sienaAlgorithmCreate(projname="siena_run", seed=42)
result <- siena07(algo, data=data, effects=effects)
summary(result)
```

### Step 6 — Relational Event Analysis

**When to use**: Your data is a *time-ordered sequence of dyadic interactions* (e.g., emails, messages, citations, observed conversations) rather than a static or panel network snapshot. Relational Event Models (Butts 2008) model the *rate* at which each sender-receiver pair interacts as a function of endogenous history statistics and exogenous covariates.

**Key endogenous statistics:**

| Statistic | Meaning |
|-----------|---------|
| Inertia | i→j recently sent to j; predicts repetition |
| Reciprocity | j recently sent to i; predicts reciprocation |
| Transitivity | shared partners predict new ties |
| Popularity shift | nodes receiving many recent events attract more |
| Activity shift | nodes sending many events continue sending |
| Recency | decay function — recent events matter more |

**Option A — `goldfish` (ETH Zurich; recommended for new papers):**

```r
# install.packages("goldfish")
library(goldfish)

# Define actors and network
actors  <- defineActors(node_data)                       # node_data: data.frame with id col
network <- defineNetwork(matrix(0, nrow=N, ncol=N),      # initial empty network
                         nodes=actors, directed=TRUE)

# Register dynamic updates: each event updates the network state
network <- linkEvents(x=network, changeEvents=events_df, nodes=actors)
# events_df must have columns: time, sender, receiver (and optionally weight, replace)

# Define dependent event sequence
dv <- defineDependentEvents(events=events_df, nodes=actors,
                             defaultNetwork=network)

# Specify model effects
# inertia: repetition of i→j
# recip:   reciprocity j→i predicts i→j
# trans:   transitivity via shared partners
# ego.attribute / alter.attribute: node-level covariates
model_formula <- dv ~ inertia(network) + recip(network) +
                       trans(network)  +
                       ego(actors$attribute) +
                       alter(actors$attribute) +
                       same(actors$group)

# Estimate (REM with Cox partial likelihood)
result <- estimate(model_formula, model="REM",
                   estimationInit=list(engine="default",
                                       startingParameters=NULL,
                                       returnEventProbabilities=FALSE))
summary(result)

# Model fit: compare log-likelihood across nested models
# Export
saveRDS(result, "${OUTPUT_ROOT}/models/rem-goldfish.rds")
```

**Option B — `relevent` (Butts 2008; classic implementation):**

```r
# install.packages("relevent")
library(relevent)

# events_mat: N_events × 3 matrix with columns [time, sender, receiver]
# n: number of actors
result_rem <- rem.dyad(
  edgelist = events_mat,
  n        = N_actors,
  effects  = c("PSAB-BA",   # inertia: prior i→j predicts i→j
               "PSAB-BY",   # activity: i sent to anyone recently
               "PSAB-AY",   # popularity: j received from anyone recently
               "PSAB-AB",   # reciprocity: j→i predicts i→j
               "NTDSnd",    # recency decay (sender)
               "NTDRec"),   # recency decay (receiver)
  covar    = list(node=node_attr_matrix),  # exogenous node attributes
  timing   = "interval"   # or "ordinal" if only order of events is known
)
summary(result_rem)

# Goodness of fit
# Compare predicted vs. observed event rates per dyad
```

**Reporting template:**
> "We model the sequence of [N] interaction events among [N_actors] actors using a Relational Event Model (REM; Butts 2008), estimated via the `goldfish` package (Stadtfeld et al. 2017). The model captures how the rate of a directed event from actor *i* to actor *j* depends on endogenous network history — including inertia (prior i→j interactions), reciprocity (prior j→i interactions), and transitivity (shared partners) — as well as actor-level covariates [list]. Table [X] reports log-likelihood coefficients. A positive coefficient on inertia indicates that dyads with recent prior interactions are more likely to interact again, consistent with H[X]."

**Required diagnostics:**
- Compare null model (intercept only) vs. full model via log-likelihood ratio test
- Plot predicted vs. observed event rate per sender/receiver
- Check temporal stability: does the model hold across sub-periods?

### Step 7 — Network Visualization

```python
import matplotlib.pyplot as plt, networkx as nx

fig, ax = plt.subplots(figsize=(12,10))
pos     = nx.spring_layout(G, seed=42, k=0.5)
colors  = [leiden.membership[list(G.nodes()).index(n)] for n in G.nodes()]
sizes   = [G.degree(n)*50+100 for n in G.nodes()]

nx.draw_networkx_nodes(G, pos, node_color=colors, node_size=sizes,
                       alpha=0.8, cmap=plt.cm.tab20, ax=ax)
nx.draw_networkx_edges(G, pos, alpha=0.15, arrows=True, arrowsize=10, ax=ax)
ax.set_title("Network colored by community (Leiden)")
plt.axis("off"); plt.tight_layout()
plt.savefig("${OUTPUT_ROOT}/figures/fig-network.pdf", dpi=300, bbox_inches="tight")
plt.savefig("${OUTPUT_ROOT}/figures/fig-network.png", dpi=300, bbox_inches="tight")
```

For interactive network figures, see `viz-standards.md` T17 (visNetwork + networkD3).

### Step 8 — Network Verification (Subagent)

```
NETWORK VERIFICATION REPORT
=============================

DESCRIPTIVES
[ ] N nodes, N edges, density reported
[ ] Directed/undirected and weighted/binary specified
[ ] Isolates inclusion/exclusion documented

COMMUNITY DETECTION
[ ] Leiden or Louvain used (not Girvan-Newman for large graphs)
[ ] random_state / seed=42 set
[ ] Modularity Q reported

ERGM (if used)
[ ] Progressive model ladder (m0 → m1 → m2)
[ ] MCMC trace plots inspected for convergence
[ ] GOF run and plot saved (degree dist., triad census, geodesics)
[ ] Coefficients are log-odds (NOT exp(β) unless reported as odds ratios)
[ ] Table exported to output/[slug]/tables/

SAOM (if used)
[ ] seed=42 in sienaAlgorithmCreate
[ ] Convergence ratio < 0.25 for all parameters
[ ] GOF run

RELATIONAL EVENT MODEL (if used)
[ ] Event sequence sorted by time
[ ] N events, N actors, time range reported
[ ] Model includes at minimum inertia + reciprocity terms
[ ] Null model comparison (log-likelihood ratio test)
[ ] goldfish or relevent used (not manual)

GNN / NODE EMBEDDING (if used)
[ ] Method specified (node2vec / GCN / GraphSAGE)
[ ] Node features documented (what attributes used as input)
[ ] Train/val/test split documented (60/20/20 for node classification)
[ ] Test F1 (macro) and accuracy reported (not train-set metrics)
[ ] Link prediction: AUC-ROC on held-out test edges reported
[ ] Baseline comparison (common neighbors / Adamic-Adar / Leiden) included
[ ] Embedding dimensionality documented
[ ] Embeddings saved to output/[slug]/models/
[ ] UMAP visualization of embeddings saved
[ ] torch.manual_seed(42) set

VISUALIZATION
[ ] Network figure saved as .pdf + .png
[ ] Colorblind-safe palette used (not default matplotlib tab10 if >8 communities)

RESULT: [PASS / NEEDS REVISION]
Issues: [list]
```

---

## MODULE 4: Agent-Based Modeling (ABM)

### Step 1 — Feasibility Check

ABM is appropriate when:
- **Emergence** is the key question: macro patterns arising from micro interactions
- **Heterogeneity** matters and aggregates non-linearly
- **Feedbacks / path dependence** are central
- **Counterfactuals** not feasible empirically

ABM is NOT appropriate as a substitute for causal inference from observational data.

### Step 2 — ODD Protocol (Required for NCS / Science Advances)

All ABM papers must include an ODD (Overview, Design concepts, Details) description:

```
## ODD Protocol for [Model Name]

### 1. Purpose
[What social process does this model represent? What question does it address?]

### 2. Entities, State Variables, and Scales
Agents: [type; state variables: list]
Environment: [spatial structure or network; size; boundary conditions]
Time: [step = X; total T steps; corresponds to Y real-world time units]

### 3. Process Overview and Scheduling
Each time step:
  1. [Agent process 1] — executed in [random / fixed] order
  2. [Agent process 2]
  3. [Data collection]

### 4. Design Concepts
Emergence: [what macro-level outcomes emerge from micro rules]
Adaptation: [do agents update rules based on outcomes? how?]
Stochasticity: [where is randomness introduced?]
Observation: [what is recorded each step?]

### 5. Initialization
[Starting conditions: N agents, initial distribution of attributes, initial network structure]
[Random seed: 42]

### 6. Input Data (if any)
[Empirical data used to calibrate parameters or initialize]

### 7. Submodels
[For each process: precise mathematical or algorithmic specification]
```

### Step 3 — Mesa 3.x Implementation (Python)

**Important**: Mesa 3.x (2024+) replaced the scheduler-based API with `AgentSet`, `PropertyLayer`, and `model.agents`. The code below uses the **Mesa 3.x API**. If you encounter legacy Mesa 2.x code (using `RandomActivation`, `self.schedule`, `self.next_id()`), migrate it to the patterns shown here.

**Key Mesa 3.x changes** (vs. 2.x):
| Mesa 2.x (deprecated) | Mesa 3.x (current) |
|------------------------|---------------------|
| `from mesa.time import RandomActivation` | No scheduler needed; use `model.agents` |
| `self.schedule = RandomActivation(self)` | Agents auto-registered via `Agent.__init__` |
| `self.schedule.add(agent)` | Automatic on `Agent(model)` |
| `self.schedule.step()` | `self.agents.shuffle_do("step")` |
| `self.schedule.agents` | `self.agents` (returns `AgentSet`) |
| `self.schedule.get_agent_count()` | `len(self.agents)` |
| `self.next_id()` | Auto-assigned `agent.unique_id` |
| `super().__init__(uid, model)` | `super().__init__(model)` |
| N/A | `PropertyLayer` for grid-level continuous variables |

```python
# pip install mesa>=3.0
from mesa import Agent, Model
from mesa.space import MultiGrid
from mesa.datacollection import DataCollector

class SchellingAgent(Agent):
    def __init__(self, model, agent_type):
        super().__init__(model)          # Mesa 3.x: no uid arg; auto-assigned unique_id
        self.type  = agent_type
        self.happy = False

    def step(self):
        neighbors = self.model.grid.get_neighbors(self.pos, moore=True, radius=1)
        similar   = sum(1 for n in neighbors if n.type == self.type)
        self.happy = similar / max(len(neighbors), 1) >= self.model.threshold
        if not self.happy:
            self.model.grid.move_to_empty(self)

class SchellingModel(Model):
    def __init__(self, width=20, height=20, density=0.8,
                 frac_A=0.5, threshold=0.3, seed=42):
        super().__init__(seed=seed)      # Mesa 3.x: pass seed to Model.__init__
        self.threshold = threshold
        self.grid      = MultiGrid(width, height, torus=True)

        # Mesa 3.x: no scheduler — agents are auto-registered on creation
        for _, (x, y) in self.grid.coord_iter():
            if self.random.random() < density:
                a_type = 0 if self.random.random() < frac_A else 1
                agent  = SchellingAgent(self, a_type)
                self.grid.place_agent(agent, (x, y))

        self.datacollector = DataCollector(
            model_reporters={
                "Pct_Happy": lambda m: (
                    m.agents.agg("happy", sum) / len(m.agents)
                )
            }
        )

    def step(self):
        self.datacollector.collect(self)
        self.agents.shuffle_do("step")   # Mesa 3.x: replaces schedule.step()

# Run single simulation
model = SchellingModel(threshold=0.3)
for _ in range(100):
    model.step()

results = model.datacollector.get_model_vars_dataframe()
results.to_csv("${OUTPUT_ROOT}/tables/abm-run-results.csv")
```

**Mesa 3.x AgentSet operations** (replaces scheduler loops):

```python
# Filter agents by type
type_0 = model.agents.select(lambda a: a.type == 0)
print(f"N type-0 agents: {len(type_0)}")

# Aggregate attributes across agents
avg_happy = model.agents.agg("happy", func=lambda vals: sum(vals) / len(vals))

# Get attribute as array (useful for plotting)
happy_arr = model.agents.get("happy")

# Apply method to all agents in random order
model.agents.shuffle_do("step")

# Apply method to subset
type_0.do("step")
```

**Mesa 3.x PropertyLayer** (for grid-level continuous variables like pollution, rent, resources):

```python
from mesa.space import PropertyLayer

# Add a continuous property to the grid
pollution = PropertyLayer("pollution", width=20, height=20, default_value=0.0)
model.grid.add_property_layer(pollution)

# Set values
model.grid.properties["pollution"].set_cell((5, 5), 0.8)

# Agents can read local property
class PollutionAgent(Agent):
    def step(self):
        local_pollution = self.model.grid.properties["pollution"].data[self.pos]
        if local_pollution > 0.5:
            self.model.grid.move_to_empty(self)
```

### Step 3b — NetLogo via nlrx (R Interface)

For models where NetLogo's built-in spatial primitives, link topologies, or GIS extension are preferable, use the `nlrx` package to drive NetLogo from R:

```r
# install.packages(c("nlrx", "future"))
library(nlrx)
library(tidyverse)

# Path to NetLogo installation (adjust for your system)
NETLOGO_PATH <- "/Applications/NetLogo 6.4.0"
MODEL_PATH   <- file.path(getwd(), "models/schelling.nlogo")

# Create nlrx object
nl <- nl(
  nlversion   = "6.4.0",
  nlpath      = NETLOGO_PATH,
  modelpath   = MODEL_PATH,
  jvmmem      = 1024
)

# Experiment specification
nl@experiment <- experiment(
  expname     = "schelling-sweep",
  outpath     = file.path(getwd(), paste0(Sys.getenv("OUTPUT_ROOT", "output"), "/")),
  repetition  = 5,         # runs per parameter set
  tickmetrics = "true",
  idsetup     = "setup",
  idgo        = "go",
  runtime     = 200,
  evalticks   = seq(50, 200, 50),
  metrics     = c("percent-similar", "percent-unhappy"),
  variables   = list(
    "%-similar-wanted" = list(min=10, max=60, step=10, qfun="qunif"),
    "number"           = list(min=500, max=2000, step=500, qfun="qunif")
  ),
  constants   = list("number-of-ethnicities" = 2)
)

# Latin Hypercube Sampling design
nl@simdesign <- simdesign_lhs(nl=nl, samples=100, nseeds=3, precision=3)

# Run (parallel with future)
library(future); plan(multisession, workers=4)
results <- run_nl_all(nl=nl)

# Collect and save
results_df <- setsim(nl, "simoutput")
write_csv(results_df, "${OUTPUT_ROOT}/tables/netlogo-sweep.csv")
```

**Reporting template:**
> "We implement the model in NetLogo 6.4 (Wilensky 1999) and conduct a Latin hypercube parameter sweep (N = 100 samples × 3 seeds) driven from R via the `nlrx` package (Salecker et al. 2019). Results are robust across the explored parameter space; key findings are presented for [parameter range]."

### Additional ABM Models for Social Science

**Opinion dynamics (Bounded Confidence / Deffuant model)**:
```python
class OpinionAgent(mesa.Agent):
    def __init__(self, model):
        super().__init__(model)
        self.opinion = self.random.uniform(0, 1)

    def step(self):
        neighbor = self.random.choice(self.model.agents)
        if abs(self.opinion - neighbor.opinion) < self.model.confidence_bound:
            self.opinion += self.model.mu * (neighbor.opinion - self.opinion)
```

**Epidemic spreading (SIR)**:
```python
class SIRAgent(mesa.Agent):
    def __init__(self, model, state="S"):
        super().__init__(model)
        self.state = state  # S, I, R

    def step(self):
        if self.state == "I":
            neighbors = self.model.grid.get_neighbors(self.pos, radius=1)
            for n in neighbors:
                if n.state == "S" and self.random.random() < self.model.beta:
                    n.state = "I"
            if self.random.random() < self.model.gamma:
                self.state = "R"
```

**Norm evolution / cultural transmission**:
```python
class CulturalAgent(mesa.Agent):
    def __init__(self, model, n_features=5, n_traits=10):
        super().__init__(model)
        self.culture = [self.random.randint(0, n_traits-1) for _ in range(n_features)]

    def step(self):
        neighbor = self.random.choice(self.model.grid.get_neighbors(self.pos))
        similarity = sum(a == b for a, b in zip(self.culture, neighbor.culture)) / len(self.culture)
        if self.random.random() < similarity:
            idx = self.random.choice([i for i, (a, b) in enumerate(zip(self.culture, neighbor.culture)) if a != b])
            self.culture[idx] = neighbor.culture[idx]
```

---

### Step 3c — LLM-Powered Agents

Replace hard-coded decision rules with an LLM as an agent's cognitive engine. Use **Claude Haiku** (fastest, cheapest) for large simulations; switch to Sonnet for complex reasoning.

**When appropriate**: When agent decision rules are too complex or context-dependent to encode as simple thresholds; when you want agents to reason in natural language about their situation (e.g., job-seeking, housing choice, migration decision).

**Cost check first**:

```python
# Estimate LLM cost before running a large simulation
N_AGENTS = 200
STEPS    = 100
CALLS_PER_STEP = N_AGENTS      # each agent calls LLM once per step
TOKENS_PER_CALL_IN  = 300      # context (agent state + world state)
TOKENS_PER_CALL_OUT = 50       # decision output
PRICE_PER_1M_IN  = 0.25        # claude-haiku-4-5 (adjust to current pricing)
PRICE_PER_1M_OUT = 1.25

total_in  = N_AGENTS * STEPS * TOKENS_PER_CALL_IN  / 1e6
total_out = N_AGENTS * STEPS * TOKENS_PER_CALL_OUT / 1e6
cost = total_in * PRICE_PER_1M_IN + total_out * PRICE_PER_1M_OUT
print(f"Estimated simulation cost: ${cost:.2f}")
# If cost > $50, reduce N_AGENTS, STEPS, or add heuristic pre-filters
```

```python
import anthropic, json
from mesa import Agent, Model

client = anthropic.Anthropic()

DECISION_SYSTEM = """You are simulating a household making a residential location decision.
Based on the household's current state and neighborhood conditions, decide whether to STAY or MOVE.
Respond ONLY with: {"action": "STAY" or "MOVE", "reason": "one sentence"}"""

class LLMAgent(Agent):
    def __init__(self, model, income, race, threshold=0.3):
        super().__init__(model)          # Mesa 3.x: no uid arg
        self.income    = income
        self.race      = race
        self.threshold = threshold
        self.happy     = True

    def _get_decision(self, neighbor_summary: str) -> dict:
        """Use Claude Haiku as cognitive engine."""
        context = (
            f"Household: income={self.income}, race={self.race}.\n"
            f"Current neighborhood: {neighbor_summary}.\n"
            f"Similarity preference threshold: {self.threshold:.0%}."
        )
        msg = client.messages.create(
            model="claude-haiku-4-5-20251001",
            max_tokens=80,
            temperature=0,   # deterministic for reproducibility
            system=DECISION_SYSTEM,
            messages=[{"role": "user", "content": context}]
        )
        return json.loads(msg.content[0].text)

    def step(self):
        neighbors = self.model.grid.get_neighbors(self.pos, moore=True, radius=1)
        if not neighbors:
            return
        same_race   = sum(1 for n in neighbors if n.race == self.race)
        pct_similar = same_race / len(neighbors)
        summary     = (f"{len(neighbors)} neighbors; {pct_similar:.0%} same race; "
                       f"avg income={sum(n.income for n in neighbors)/len(neighbors):.0f}")
        decision    = self._get_decision(summary)
        self.happy  = decision["action"] == "STAY"
        if not self.happy:
            self.model.grid.move_to_empty(self)
```

**Required safeguards**:
- Cache LLM responses for identical inputs (`functools.lru_cache` or dict) to reduce cost and improve reproducibility
- Archive all prompts and a sample of LLM responses as supplementary material
- Run a baseline simulation with rule-based agents to compare aggregate patterns

### Step 4 — Parameter Sweep and Sensitivity Analysis (SALib)

**Required for NCS / Science Advances**: Report how key outcomes respond across the parameter space.

```python
from SALib.sample import saltelli
from SALib.analyze import sobol
import numpy as np, pandas as pd

# Define parameter space
problem = {
    "num_vars": 3,
    "names":    ["density", "frac_A", "threshold"],
    "bounds":   [[0.5, 0.95], [0.3, 0.7], [0.1, 0.7]]
}

# Generate Saltelli samples (N*(2D+2) model runs)
N           = 256   # base sample size; total runs = N*(2*3+2) = 2048
param_values= saltelli.sample(problem, N, calc_second_order=True)

# Run model for each parameter set
def run_model(params, steps=100):
    m = SchellingModel(density=params[0], frac_A=params[1],
                       threshold=params[2], seed=42)
    for _ in range(steps):
        m.step()
    return m.datacollector.get_model_vars_dataframe()["Pct_Happy"].iloc[-1]

Y = np.array([run_model(p) for p in param_values])

# Sobol sensitivity indices
Si = sobol.analyze(problem, Y, calc_second_order=True, print_to_console=True)
# Si["S1"]: first-order (direct effect of each parameter)
# Si["ST"]: total-order (includes interactions)

pd.DataFrame({"param": problem["names"],
              "S1": Si["S1"], "ST": Si["ST"]}).to_csv(
              "${OUTPUT_ROOT}/tables/abm-sensitivity.csv", index=False)
```

### Step 5 — ABM Verification (Subagent)

```
ABM VERIFICATION REPORT
========================

ODD PROTOCOL
[ ] All 7 ODD sections present (Purpose, Entities, Process, Design Concepts,
    Init, Input, Submodels)
[ ] Precise algorithmic specification of each submodel

IMPLEMENTATION
[ ] seed=42 set in model initialization
[ ] DataCollector used to record model state each step
[ ] Simulation results saved to output/[slug]/tables/

PARAMETER SWEEP
[ ] SALib Saltelli sample used (not ad hoc grid)
[ ] Sobol S1 and ST indices reported
[ ] Sensitivity table saved

NETLOGO (if used)
[ ] NetLogo version documented
[ ] nlrx experiment specification reproduced in supplementary
[ ] LHS or Saltelli design used (not ad hoc grid)

LLM AGENTS (if used)
[ ] Cost estimation run and reported
[ ] temperature=0 set for reproducibility
[ ] Prompts archived verbatim in supplementary
[ ] Baseline rule-based model run for comparison
[ ] LLM model name + version + date recorded

VALIDATION
[ ] Model validated against ≥2 empirical patterns (pattern-oriented modeling)
[ ] Behavior across parameter space described (not just one parameter set)
[ ] Results robust to ±20% variation in key parameters

REPORTING
[ ] ODD protocol in supplementary or appendix
[ ] All parameters and initial conditions tabulated
[ ] Random seed reported

RESULT: [PASS / NEEDS REVISION]
Issues: [list]
```

---

## MODULE 5: Computational Reproducibility

For preregistration, data sharing, and Zenodo DOI archiving, invoke `/scholar-open`.

This module covers compute-specific reproducibility only.

### Project Directory Structure

```
project/
├── README.md              ← How to reproduce; hardware specs; estimated runtime
├── environment.yml        ← Conda environment (Python)
├── renv.lock              ← renv lockfile (R)
├── Makefile               ← Pipeline automation (optional; see below)
├── data/
│   ├── raw/               ← Never modified; README with source + access date
│   ├── clean/
│   └── analysis/
├── code/
│   ├── 01_clean.py / .R
│   ├── 02_eda.py / .R
│   ├── 03_model.py / .R
│   └── 04_figures.py / .R
├── output/
│   ├── figures/
│   ├── tables/
│   └── models/
└── paper/
    └── manuscript.tex
```

### Environment Files

```yaml
# environment.yml (Python)
name: scholar-project
channels: [conda-forge, defaults]
dependencies:
  - python=3.11
  - numpy=1.26
  - pandas=2.1
  - scikit-learn=1.3
  - transformers=4.35
  - gensim=4.3
  - networkx=3.2
  - econml=0.15
  - shap=0.43
  - mesa=2.1
  - SALib=1.5
  - optuna=3.5
  - anthropic
  - matplotlib=3.8
  - seaborn=0.13
```

```r
# R reproducibility — use renv
renv::init()
# install packages...
renv::snapshot()   # writes renv.lock
# Restore on another machine:
# renv::restore()
```

### Makefile Pipeline

```makefile
all: clean model figures

clean:
	Rscript code/01_clean.R

model:
	python code/03_model.py

figures:
	Rscript code/04_figures.R

.PHONY: all clean model figures
```

### Seed Discipline

```python
# Python: set at top of every script
import random, numpy as np, torch
SEED = 42
random.seed(SEED); np.random.seed(SEED); torch.manual_seed(SEED)
```

```r
# R: set at top of every script
set.seed(42)
```

Report in the Methods section: *"All stochastic analyses used random seed 42."*

### Computational Reproducibility: Containerization

**Docker** (recommended for NCS, Science Advances):
```dockerfile
# Dockerfile for reproducible analysis
FROM rocker/verse:4.3.2
# Install system dependencies
RUN apt-get update && apt-get install -y libxml2-dev libcurl4-openssl-dev
# Install R packages from renv.lock
COPY renv.lock renv.lock
RUN R -e "install.packages('renv'); renv::restore()"
# Copy analysis code
COPY . /project
WORKDIR /project
CMD ["Rscript", "run_all.R"]
```

```dockerfile
# Python Dockerfile
FROM python:3.11-slim
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . /project
WORKDIR /project
CMD ["python", "run_all.py"]
```

**Build & run**:
```bash
docker build -t my-analysis .
docker run --rm -v $(pwd)/output:/project/output my-analysis
```

**Code Ocean**: For NCS submissions, create a Code Ocean capsule (https://codeocean.com) with the same Dockerfile. Include `postInstall` script for dependencies.

**Singularity** (for HPC clusters):
```bash
singularity build analysis.sif docker://my-analysis:latest
singularity run analysis.sif
```

---

## MODULE 6: Computer Vision — Image and Video as Data

### Step 1 — Method Selection

| Goal | Recommended model | Package |
|------|------------------|---------|
| General visual features (unsupervised) | **DINOv2-Large** | `transformers` (Hugging Face) |
| Zero-shot classification / similarity | **CLIP ViT-L/14** | `transformers` |
| Fine-tuned classification (N > 500 labeled) | **ConvNeXt-Base** or **EfficientNet-B4** | `timm`, `torchvision` |
| Large-scale zero-shot with rich reasoning | **ViT-B/16** via HF | `transformers` |
| Multimodal annotation (VQA, description) | **GPT-4o** / **Claude** / **LLaVA** | `openai`, `anthropic` |
| Video temporal dynamics | **VideoMAE-Base** | `transformers` |
| Street view / satellite coding | DINOv2 + CLIP zero-shot | `transformers` |

**Social science use cases**: protest / event imagery coding; facial expression / crowd density; historical photograph analysis; housing condition from street view; land use from satellite; social media video content analysis.

---

### Step 2 — Data Preparation

```python
import os, PIL.Image, torch
from torchvision import transforms
from torch.utils.data import Dataset, DataLoader

# Standard preprocessing for pretrained ViT-family models
TRANSFORM = transforms.Compose([
    transforms.Resize(256),
    transforms.CenterCrop(224),
    transforms.ToTensor(),
    transforms.Normalize(mean=[0.485, 0.456, 0.406],
                         std =[0.229, 0.224, 0.225])
])

class ImageDataset(Dataset):
    def __init__(self, img_dir, label_df, transform=TRANSFORM):
        self.img_dir   = img_dir
        self.label_df  = label_df.reset_index(drop=True)
        self.transform = transform

    def __len__(self):
        return len(self.label_df)

    def __getitem__(self, idx):
        row    = self.label_df.iloc[idx]
        img    = PIL.Image.open(os.path.join(self.img_dir, row["filename"])).convert("RGB")
        label  = int(row["label"]) if "label" in row else -1
        return self.transform(img), label, row["filename"]

loader = DataLoader(ImageDataset("data/images/", label_df),
                    batch_size=32, shuffle=False, num_workers=4)
```

---

### Step 3 — Feature Extraction with DINOv2 (Best for Unsupervised / Clustering)

DINOv2 (Oquab et al. 2023, Meta) produces the strongest general-purpose visual features. Ideal for clustering images without labels.

```python
from transformers import AutoImageProcessor, AutoModel
import torch, numpy as np

device     = "cuda" if torch.cuda.is_available() else "cpu"
processor  = AutoImageProcessor.from_pretrained("facebook/dinov2-large")
dino_model = AutoModel.from_pretrained("facebook/dinov2-large").to(device).eval()

def extract_features(img_paths, batch_size=32):
    all_feats = []
    for i in range(0, len(img_paths), batch_size):
        imgs   = [PIL.Image.open(p).convert("RGB") for p in img_paths[i:i+batch_size]]
        inputs = processor(images=imgs, return_tensors="pt").to(device)
        with torch.no_grad():
            out = dino_model(**inputs)
        # CLS token = 1024-dim feature vector per image
        feats = out.last_hidden_state[:, 0, :].cpu().numpy()
        all_feats.append(feats)
    return np.vstack(all_feats)

features = extract_features(img_paths)   # shape: (N_images, 1024)
np.save("${OUTPUT_ROOT}/models/dinov2-features.npy", features)

# Downstream: cluster with k-means or UMAP + HDBSCAN
from sklearn.cluster import KMeans
kmeans = KMeans(n_clusters=10, random_state=42)
labels = kmeans.fit_predict(features)
```

---

### Step 4 — Zero-Shot Classification with CLIP

CLIP (Radford et al. 2021, OpenAI) enables zero-shot image classification using natural language labels — no training data required.

```python
from transformers import CLIPProcessor, CLIPModel
import torch

device     = "cuda" if torch.cuda.is_available() else "cpu"
clip_model = CLIPModel.from_pretrained("openai/clip-vit-large-patch14").to(device).eval()
clip_proc  = CLIPProcessor.from_pretrained("openai/clip-vit-large-patch14")

# Define category descriptions (natural language)
categories = [
    "a photograph of a protest or demonstration",
    "a photograph of a peaceful public gathering",
    "a photograph of police presence or riot control",
    "a photograph of a celebration or festival"
]

def zero_shot_classify(img_paths, categories, batch_size=32):
    text_inputs = clip_proc(text=categories, return_tensors="pt",
                             padding=True).to(device)
    with torch.no_grad():
        text_feats = clip_model.get_text_features(**text_inputs)
        text_feats = text_feats / text_feats.norm(dim=-1, keepdim=True)

    all_probs = []
    for i in range(0, len(img_paths), batch_size):
        imgs   = [PIL.Image.open(p).convert("RGB") for p in img_paths[i:i+batch_size]]
        inputs = clip_proc(images=imgs, return_tensors="pt").to(device)
        with torch.no_grad():
            img_feats = clip_model.get_image_features(**inputs)
            img_feats = img_feats / img_feats.norm(dim=-1, keepdim=True)
        logits = (100.0 * img_feats @ text_feats.T).softmax(dim=-1)
        all_probs.append(logits.cpu().numpy())

    return np.vstack(all_probs)   # shape: (N_images, N_categories)

probs = zero_shot_classify(img_paths, categories)
predicted = [categories[p] for p in probs.argmax(axis=1)]
```

**Required**: Validate on 200-image human-labeled sample; report Cohen's κ before using at scale.

---

### Step 5 — Fine-Tuning ConvNeXt / ViT (When You Have Labeled Data)

Use when N_labeled ≥ 500 images. ConvNeXt-Base is preferred for most social science tasks.

```python
import timm, torch, torch.nn as nn
from torch.optim import AdamW
from torch.optim.lr_scheduler import CosineAnnealingLR
from sklearn.metrics import classification_report

device = "cuda" if torch.cuda.is_available() else "cpu"

# Load pretrained ConvNeXt-Base
model = timm.create_model("convnext_base.fb_in22k_ft_in1k",
                           pretrained=True, num_classes=N_CLASSES)
model = model.to(device)

# Replace classification head (transfer learning)
# For ViT-B/16: model = timm.create_model("vit_base_patch16_224", pretrained=True, num_classes=N_CLASSES)

optimizer = AdamW(model.parameters(), lr=2e-5, weight_decay=0.01)
scheduler = CosineAnnealingLR(optimizer, T_max=NUM_EPOCHS)
criterion = nn.CrossEntropyLoss()

torch.manual_seed(42)
for epoch in range(NUM_EPOCHS):
    model.train()
    for imgs, labels, _ in train_loader:
        imgs, labels = imgs.to(device), labels.to(device)
        loss = criterion(model(imgs), labels)
        optimizer.zero_grad(); loss.backward(); optimizer.step()
    scheduler.step()

# Evaluate on test set
model.eval()
all_preds, all_labels = [], []
with torch.no_grad():
    for imgs, labels, _ in test_loader:
        preds = model(imgs.to(device)).argmax(dim=-1).cpu()
        all_preds.extend(preds.tolist())
        all_labels.extend(labels.tolist())

print(classification_report(all_labels, all_preds))
torch.save(model.state_dict(), "${OUTPUT_ROOT}/models/convnext-finetuned.pt")
```

---

### Step 6 — Multimodal LLM Annotation

When fine-tuning is impractical or semantic nuance requires reasoning. GPT-4o and Claude are preferred for complex social science coding tasks.

```python
import anthropic, base64, json

client = anthropic.Anthropic()

def encode_image_b64(path: str) -> str:
    with open(path, "rb") as f:
        return base64.standard_b64encode(f.read()).decode("utf-8")

VISION_SYSTEM = """You are a social science research assistant coding protest photographs.
For each image, code:
  - presence: 1 = protest/demonstration visible; 0 = not
  - crowd_size: "small" (<50), "medium" (50-500), "large" (>500)
  - police: 1 = police/security forces visible; 0 = not
  - violence: 1 = signs of violence or property destruction; 0 = not
Respond ONLY with JSON: {"presence":_, "crowd_size":"_", "police":_, "violence":_, "confidence":"high|medium|low"}"""

def annotate_image(img_path: str, model="claude-sonnet-4-6") -> dict:
    img_b64     = encode_image_b64(img_path)
    ext         = img_path.rsplit(".", 1)[-1].lower()
    media_types = {"jpg": "image/jpeg", "jpeg": "image/jpeg",
                   "png": "image/png", "gif": "image/gif", "webp": "image/webp"}
    msg = client.messages.create(
        model=model,
        max_tokens=200,
        temperature=0,
        system=VISION_SYSTEM,
        messages=[{
            "role": "user",
            "content": [{
                "type": "image",
                "source": {"type": "base64",
                           "media_type": media_types.get(ext, "image/jpeg"),
                           "data": img_b64}
            }, {"type": "text", "text": "Code this image:"}]
        }]
    )
    return json.loads(msg.content[0].text)

# Batch annotation
results = []
for path in img_paths:
    try:
        res = annotate_image(path)
        results.append({"path": path, **res})
    except Exception as e:
        results.append({"path": path, "error": str(e)})

import pandas as pd
pd.DataFrame(results).to_csv("${OUTPUT_ROOT}/tables/vision-annotations.csv", index=False)
```

**Required validation**: Human-code 200-image sample; compute κ per dimension ≥ 0.70.

---

### Step 7 — Video Analysis

**Frame sampling** (extract representative frames before running image models):

```python
import cv2, os

def extract_frames_uniform(video_path, n_frames=16, out_dir="${OUTPUT_ROOT}/frames"):
    os.makedirs(out_dir, exist_ok=True)
    cap     = cv2.VideoCapture(video_path)
    total   = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    indices = [int(i * total / n_frames) for i in range(n_frames)]
    paths   = []
    for idx in indices:
        cap.set(cv2.CAP_PROP_POS_FRAMES, idx)
        ret, frame = cap.read()
        if ret:
            path = os.path.join(out_dir, f"frame_{idx:06d}.jpg")
            cv2.imwrite(path, frame)
            paths.append(path)
    cap.release()
    return paths

def extract_frames_scene_change(video_path, threshold=30.0, out_dir="${OUTPUT_ROOT}/frames"):
    """Extract frames at scene boundaries using frame-diff heuristic."""
    os.makedirs(out_dir, exist_ok=True)
    cap  = cv2.VideoCapture(video_path)
    prev = None
    paths, idx = [], 0
    while True:
        ret, frame = cap.read()
        if not ret: break
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        if prev is not None:
            diff = cv2.absdiff(prev, gray).mean()
            if diff > threshold:
                path = os.path.join(out_dir, f"scene_{idx:06d}.jpg")
                cv2.imwrite(path, frame)
                paths.append(path)
        prev = gray; idx += 1
    cap.release()
    return paths
```

**VideoMAE for temporal features** (video understanding):

```python
from transformers import VideoMAEFeatureExtractor, VideoMAEModel
import torch, numpy as np

vmae_processor = VideoMAEFeatureExtractor.from_pretrained(
    "MCG-NJU/videomae-base")
vmae_model     = VideoMAEModel.from_pretrained(
    "MCG-NJU/videomae-base").to(device).eval()

def extract_video_features(frame_paths, n_frames=16):
    """Load N uniformly spaced frames; extract VideoMAE CLS token."""
    frames = [PIL.Image.open(p).convert("RGB") for p in frame_paths[:n_frames]]
    inputs = vmae_processor(frames, return_tensors="pt").to(device)
    with torch.no_grad():
        out = vmae_model(**inputs)
    return out.last_hidden_state[:, 0, :].cpu().numpy()  # (1, 768)
```

---

### Step 7b — Multimodal Fusion: Combining Text + Image Data

**When to use**: When your data has paired text and image modalities (e.g., social media posts with photos, news articles with images, product listings, dating profiles, protest documentation, housing ads with photos) and you want to leverage both for classification, clustering, or retrieval. Multimodal fusion captures information that neither modality alone provides.

| Fusion strategy | Description | When to use |
|----------------|-------------|-------------|
| **Late fusion** | Train separate unimodal models, combine predictions | Simple baseline; modalities are independently informative |
| **Early fusion** | Concatenate raw features before model | Features are low-dimensional; interaction effects expected |
| **Hybrid / joint embedding** | Map both modalities to shared space (CLIP) | Need cross-modal similarity; zero-shot capability |
| **Attention-based fusion** | Cross-attention between modality representations | Complex interaction patterns; sufficient labeled data |

**Installation:**

```bash
pip install transformers sentence-transformers open_clip_torch
```

**Option A — CLIP joint embeddings (zero-shot, no training required):**

```python
import torch, numpy as np, pandas as pd
from transformers import CLIPProcessor, CLIPModel
from PIL import Image

device     = "cuda" if torch.cuda.is_available() else "cpu"
clip_model = CLIPModel.from_pretrained("openai/clip-vit-large-patch14").to(device).eval()
clip_proc  = CLIPProcessor.from_pretrained("openai/clip-vit-large-patch14")

def extract_multimodal_features(texts, image_paths, batch_size=32):
    """Extract aligned text and image embeddings from CLIP."""
    text_embs, img_embs = [], []
    for i in range(0, len(texts), batch_size):
        batch_texts = texts[i:i+batch_size]
        batch_imgs  = [Image.open(p).convert("RGB") for p in image_paths[i:i+batch_size]]

        inputs = clip_proc(text=batch_texts, images=batch_imgs,
                           return_tensors="pt", padding=True,
                           truncation=True, max_length=77).to(device)
        with torch.no_grad():
            outputs = clip_model(**inputs)
            text_embs.append(outputs.text_embeds.cpu().numpy())
            img_embs.append(outputs.image_embeds.cpu().numpy())

    text_embs = np.vstack(text_embs)  # (N, 768)
    img_embs  = np.vstack(img_embs)   # (N, 768)
    return text_embs, img_embs

text_embs, img_embs = extract_multimodal_features(
    df["text"].tolist(), df["image_path"].tolist()
)

# Late fusion: concatenate normalized embeddings
from sklearn.preprocessing import normalize
text_norm = normalize(text_embs)
img_norm  = normalize(img_embs)
fused     = np.hstack([text_norm, img_norm])  # (N, 1536)

np.save("${OUTPUT_ROOT}/models/clip-text-embeddings.npy", text_embs)
np.save("${OUTPUT_ROOT}/models/clip-image-embeddings.npy", img_embs)
np.save("${OUTPUT_ROOT}/models/clip-fused-embeddings.npy", fused)
```

**Option B — Late fusion classifier (text model + image model + meta-learner):**

```python
from sklearn.linear_model import LogisticRegression
from sklearn.ensemble import GradientBoostingClassifier
from sklearn.model_selection import StratifiedKFold, cross_val_score
from sklearn.metrics import f1_score, classification_report
import joblib

# Assume: text_embs (N, d_text), img_embs (N, d_img), labels (N,)
# Option 1: Concatenate features, train single classifier
fused = np.hstack([text_embs, img_embs])  # early fusion on embeddings
clf_fused = GradientBoostingClassifier(n_estimators=200, max_depth=4,
                                        random_state=42)
cv = StratifiedKFold(n_splits=5, shuffle=True, random_state=42)
scores_fused = cross_val_score(clf_fused, fused, labels, cv=cv,
                                scoring="f1_macro")
print(f"Fused (text+image) F1: {scores_fused.mean():.3f} +/- {scores_fused.std():.3f}")

# Option 2: Late fusion — separate classifiers, combine probabilities
from sklearn.calibration import CalibratedClassifierCV
clf_text = CalibratedClassifierCV(
    GradientBoostingClassifier(n_estimators=200, random_state=42), cv=5)
clf_img  = CalibratedClassifierCV(
    GradientBoostingClassifier(n_estimators=200, random_state=42), cv=5)
clf_text.fit(text_embs[train_idx], labels[train_idx])
clf_img.fit(img_embs[train_idx], labels[train_idx])

# Average calibrated probabilities
prob_text = clf_text.predict_proba(text_embs[test_idx])
prob_img  = clf_img.predict_proba(img_embs[test_idx])
prob_late = 0.5 * prob_text + 0.5 * prob_img   # equal weighting; or tune weights
pred_late = prob_late.argmax(axis=1)
print(f"Late fusion F1: {f1_score(labels[test_idx], pred_late, average='macro'):.3f}")

# Compare: text-only, image-only, early fusion, late fusion
for name, X in [("Text only", text_embs), ("Image only", img_embs),
                ("Early fusion", fused)]:
    s = cross_val_score(GradientBoostingClassifier(n_estimators=200, random_state=42),
                        X, labels, cv=cv, scoring="f1_macro")
    print(f"{name} F1: {s.mean():.3f} +/- {s.std():.3f}")

joblib.dump(clf_fused, "${OUTPUT_ROOT}/models/multimodal-fused-clf.pkl")
```

**Option C — Cross-modal similarity for social media analysis:**

```python
# Use case: find text-image alignment / mismatch in social media posts
from sklearn.metrics.pairwise import cosine_similarity

# Per-post text-image alignment score
alignment_scores = np.array([
    cosine_similarity(text_embs[i:i+1], img_embs[i:i+1])[0, 0]
    for i in range(len(text_embs))
])
df["text_image_alignment"] = alignment_scores

# Low alignment = potential irony, sarcasm, misinformation, or mismatch
# Use as feature in downstream models or analyze directly
print(f"Mean alignment: {alignment_scores.mean():.3f}")
print(f"Low-alignment posts (< 0.2): {(alignment_scores < 0.2).sum()}")

df.to_csv("${OUTPUT_ROOT}/tables/multimodal-alignment.csv", index=False)
```

```r
# R alternative — use reticulate to call Python CLIP, then analyze in R
library(reticulate)
library(tidyverse)

# Load pre-computed embeddings from Python
text_embs <- as.matrix(read.csv("${OUTPUT_ROOT}/models/clip-text-embeddings.csv"))
img_embs  <- as.matrix(read.csv("${OUTPUT_ROOT}/models/clip-image-embeddings.csv"))

# Fuse and run classification in R
fused <- cbind(text_embs, img_embs)
library(caret)
set.seed(42)
ctrl <- trainControl(method="cv", number=5, classProbs=TRUE,
                     summaryFunction=multiClassSummary)
fit  <- train(x=fused, y=as.factor(labels),
              method="gbm", trControl=ctrl, metric="F1",
              verbose=FALSE)
print(fit$results)
```

**Validation approach:**
- Always compare multimodal vs. unimodal baselines (text-only, image-only)
- Report F1 (macro) for all modality combinations on the same held-out test set
- For late fusion, report calibration metrics (Brier score) to ensure probability combination is meaningful
- For cross-modal alignment, validate interpretation on a manual sample of high/low alignment posts

**Reporting template:**
> "We combine text and image modalities using [late / early / CLIP-based joint embedding] fusion. Text features are encoded with [CLIP text encoder / sentence-transformers / XLM-RoBERTa] ([d_text]-dimensional); image features with [CLIP image encoder / DINOv2] ([d_img]-dimensional). [For early fusion], we concatenate L2-normalized embeddings and train a gradient boosting classifier (5-fold CV). [For late fusion], we train separate calibrated classifiers per modality and average predicted probabilities. The multimodal model achieves F1 (macro) = [X], compared to text-only = [X] and image-only = [X] on the held-out test set (N = [X]). [For text-image alignment analysis], we compute per-post cosine similarity between CLIP text and image embeddings; posts with alignment < [threshold] are flagged as potential [irony / misinformation / mismatched] content. All models use seed = 42."

---

### Step 8 — CV Verification (Subagent)

```
CV VERIFICATION REPORT
=======================

DATA PREPARATION
[ ] Image preprocessing (resize, normalize) documented and matches pretrained model specs
[ ] Image resolution and format documented
[ ] Number of images, class distribution reported

METHOD ALIGNMENT
[ ] DINOv2 / CLIP / fine-tuned model choice justified vs. alternatives
[ ] Zero-shot: CLIP category descriptions validated on pilot set
[ ] Fine-tuning: N_labeled ≥ 500; train/val/test split documented

VALIDATION
[ ] Human-coded 200-image sample for benchmark
[ ] Cohen's κ ≥ 0.70 per coded dimension
[ ] Confusion matrix saved (for multi-class tasks)
[ ] LLM annotation: model name + date + temperature=0 documented

VIDEO (if used)
[ ] Frame sampling method documented (uniform or scene-change)
[ ] Number of frames per video reported
[ ] VideoMAE or image-level classification justified

MULTIMODAL FUSION (if used)
[ ] Fusion strategy documented (late / early / hybrid / CLIP joint embedding)
[ ] Both modality embeddings saved to output/[slug]/models/
[ ] Unimodal baselines reported (text-only F1, image-only F1)
[ ] Multimodal F1 reported and compared to unimodal baselines
[ ] For late fusion: calibrated classifiers used; probability weights documented
[ ] For text-image alignment: cosine similarity distribution analyzed
[ ] Ambiguous / mismatched cases manually inspected on sample

REPRODUCIBILITY
[ ] random seed reported (torch.manual_seed(42))
[ ] Model checkpoints saved to output/[slug]/models/
[ ] All annotation outputs saved as CSV

RESULT: [PASS / NEEDS REVISION]
Issues: [list]
```

---

## MODULE 7: LLM-Powered Analysis Workflows

### Step 1 — Goal and Risk Assessment

Before designing the LLM pipeline, classify the workflow type and apply corresponding safeguards:

| Workflow type | Goal | Key risk | Safeguard |
|--------------|------|----------|-----------|
| **Structured extraction** | Pull named entities, dates, amounts from documents | Hallucination of non-existent values | Schema validation + spot-check 10% |
| **Multi-step coding** | Assign substantive codes to text (theory-driven) | Validity drift; confidential leakage | κ ≥ 0.70 vs. humans; few-shot anchors |
| **Computational grounded theory** | Inductive category discovery | Premature closure; category proliferation | 3-iteration loop; researcher review each cycle |
| **Document QA / RAG** | Answer questions about a document corpus | Retrieval failures; fabricated citations | Always cite retrieved passage; human audit |

Apply all four Lin & Zhang (2025) epistemic risk checks (from MODULE 1 Step 7) before full deployment: validity, reliability, replicability, transparency.

---

### Step 2 — Structured Extraction (Pydantic + Claude)

```python
from anthropic import Anthropic
from pydantic import BaseModel, Field
from typing import Optional
import json

client = Anthropic()

class PolicyEvent(BaseModel):
    date:            Optional[str]   = Field(description="Date of policy event (YYYY-MM-DD)")
    jurisdiction:    Optional[str]   = Field(description="Jurisdiction (state, city, country)")
    policy_type:     Optional[str]   = Field(description="Type of policy (housing, immigration, labor, etc.)")
    direction:       Optional[str]   = Field(description="'restrictive' or 'permissive'")
    affected_group:  Optional[str]   = Field(description="Primary affected group if mentioned")
    confidence:      str             = Field(description="'high', 'medium', or 'low'")

EXTRACT_SYSTEM = f"""Extract structured information about policy events from news articles.
If a field cannot be determined from the text, return null for that field.
Return ONLY a JSON object matching this schema:
{PolicyEvent.schema_json(indent=2)}"""

def extract_event(text: str) -> PolicyEvent:
    msg = client.messages.create(
        model="claude-sonnet-4-6",
        max_tokens=300,
        temperature=0,
        system=EXTRACT_SYSTEM,
        messages=[{"role": "user",
                   "content": f"Article:\n{text[:3000]}"}]
    )
    raw  = json.loads(msg.content[0].text)
    return PolicyEvent(**raw)

# Batch extraction with schema validation
records = []
errors  = []
for _, row in df.iterrows():
    try:
        event = extract_event(row["text"])
        records.append({"doc_id": row["id"], **event.dict()})
    except Exception as e:
        errors.append({"doc_id": row["id"], "error": str(e)})

import pandas as pd
pd.DataFrame(records).to_csv("${OUTPUT_ROOT}/tables/policy-events-extracted.csv", index=False)
print(f"Extracted: {len(records)} / Errors: {len(errors)}")
```

---

### Step 3 — Chain-of-Thought Multi-Step Coding

For theoretically nuanced coding tasks, use step-by-step reasoning before assigning the final code. This improves validity (Lin & Zhang 2025) by making the inference process auditable.

```python
COT_SYSTEM = """You are a sociologist coding newspaper articles about immigration using schema theory.
Follow these steps before assigning a frame code:
STEP 1: Identify the main subject of the article.
STEP 2: Note the most prominent metaphors or analogies used.
STEP 3: Identify the primary causal attribution (who/what is responsible?).
STEP 4: Based on steps 1-3, assign a frame code:
  - ECONOMIC: immigration framed primarily in terms of labor, economy, costs/benefits
  - SECURITY: immigration framed primarily in terms of crime, border security, national safety
  - HUMANITARIAN: immigration framed primarily in terms of human rights, family, asylum
  - CULTURAL: immigration framed primarily in terms of identity, values, national character
  - OTHER: does not fit cleanly into above categories
Respond with JSON: {"step1":"...", "step2":"...", "step3":"...", "frame":"ECONOMIC|SECURITY|HUMANITARIAN|CULTURAL|OTHER", "confidence":"high|medium|low"}"""

def code_frame_cot(text: str) -> dict:
    msg = client.messages.create(
        model="claude-sonnet-4-6",
        max_tokens=400,
        temperature=0,
        system=COT_SYSTEM,
        messages=[{"role": "user", "content": f"Article:\n{text[:3000]}"}]
    )
    return json.loads(msg.content[0].text)
```

---

### Step 4 — Computational Grounded Theory Loop

Nelson (2020, *Sociological Methods & Research*) proposes an iterative cycle: unsupervised induction → manual interpretation → supervised deduction.

```python
# CYCLE 1: Inductive discovery via STM or k-means on embeddings
# (Run Step 3 or Step 6 from MODULE 1 to get initial topics/clusters)

# CYCLE 2: Researcher reviews top documents per cluster;
#           defines theoretically-grounded categories

categories_cycle2 = {
    "displacement_threat": "Articles framing immigrants as displacing native workers",
    "cultural_dilution":   "Articles framing immigration as threatening cultural values",
    "humanitarian_appeal": "Articles emphasizing suffering, rights, and asylum needs",
    "economic_benefit":    "Articles emphasizing immigrants' economic contributions"
}

# CYCLE 3: LLM assigns documents to researcher-defined categories (deductive)
DEDUCTIVE_SYSTEM = (
    "You are coding news articles into one of these categories defined by a sociologist:\n"
    + "\n".join(f"- {k}: {v}" for k, v in categories_cycle2.items())
    + "\nRespond ONLY with JSON: {\"category\": \"category_name\", \"confidence\": \"high|medium|low\"}"
)

def classify_grounded(text: str) -> dict:
    msg = client.messages.create(
        model="claude-sonnet-4-6",
        max_tokens=100,
        temperature=0,
        system=DEDUCTIVE_SYSTEM,
        messages=[{"role": "user", "content": f"Article:\n{text[:2000]}"}]
    )
    return json.loads(msg.content[0].text)

# Validate Cycle 3 against human codes (κ ≥ 0.70 required)
```

**Reporting template:**
> "Following Nelson's (2020) computational grounded theory approach, we proceeded in three cycles. In Cycle 1, we applied Structural Topic Modeling (K = [X]) to inductively identify latent themes in the corpus. In Cycle 2, two authors reviewed the top [N] documents per topic and developed a [K]-category coding scheme. In Cycle 3, we used [Claude Sonnet 4.6] to classify all [N] documents into this scheme (agreement with human codes on 200-document sample: κ = [X]). All prompts and a random sample of LLM reasoning chains are reproduced in the Online Appendix."

---

### Step 5 — RAG / Document QA with FAISS

For large document collections where you need to answer specific questions or retrieve relevant passages:

```python
from sentence_transformers import SentenceTransformer
import faiss, numpy as np

# Build vector index
embedder = SentenceTransformer("all-mpnet-base-v2")   # 768-dim embeddings

def build_index(texts: list[str], chunk_size: int = 500) -> tuple:
    """Chunk documents and build FAISS index."""
    chunks, chunk_ids = [], []
    for doc_id, text in enumerate(texts):
        words  = text.split()
        for i in range(0, len(words), chunk_size):
            chunks.append(" ".join(words[i:i+chunk_size]))
            chunk_ids.append(doc_id)

    embeddings = embedder.encode(chunks, show_progress_bar=True,
                                 batch_size=64, normalize_embeddings=True)
    index = faiss.IndexFlatIP(embeddings.shape[1])   # inner product = cosine for L2-normalized
    index.add(embeddings.astype("float32"))
    return index, chunks, chunk_ids

def query(question: str, index, chunks, top_k=5) -> list[str]:
    q_emb = embedder.encode([question], normalize_embeddings=True).astype("float32")
    _, ids = index.search(q_emb, top_k)
    return [chunks[i] for i in ids[0]]

def answer_with_rag(question: str, context_chunks: list[str]) -> str:
    context = "\n\n---\n\n".join(context_chunks)
    msg = client.messages.create(
        model="claude-sonnet-4-6",
        max_tokens=500,
        temperature=0,
        system="You are a research assistant. Answer the question based ONLY on the provided passages. If the answer is not in the passages, say 'Not found in corpus.'",
        messages=[{"role": "user",
                   "content": f"Passages:\n{context}\n\nQuestion: {question}"}]
    )
    return msg.content[0].text

# Example usage
index, chunks, chunk_ids = build_index(df["text"].tolist())
context   = query("What are the main arguments for restrictive immigration policy?", index, chunks)
answer    = answer_with_rag("What are the main arguments for restrictive immigration policy?", context)
print(answer)
```

---

### Step 6 — LLM Analysis Reproducibility

```python
import hashlib, json, datetime

def reproducible_prompt_call(system: str, user_msg: str,
                              model="claude-sonnet-4-6") -> dict:
    """Wrapper that records prompt hash, model, date for replicability."""
    prompt_hash = hashlib.sha256(
        (system + user_msg).encode()).hexdigest()[:12]
    result = client.messages.create(
        model=model,
        max_tokens=500,
        temperature=0,   # REQUIRED for replicability
        system=system,
        messages=[{"role": "user", "content": user_msg}]
    )
    return {
        "response":     result.content[0].text,
        "model":        model,
        "date":         datetime.date.today().isoformat(),
        "prompt_hash":  prompt_hash,
        "input_tokens": result.usage.input_tokens,
        "output_tokens":result.usage.output_tokens
    }
```

**Reproducibility checklist for LLM analysis:**
- temperature = 0 for all production annotation calls
- Exact model ID (including version suffix) archived
- Annotation date recorded (model behavior can change across releases)
- Full system + user prompts archived verbatim
- Raw LLM outputs saved alongside derived codes

---

### Step 7 — LLM Analysis Verification (Subagent)

```
LLM ANALYSIS VERIFICATION REPORT
==================================

RISK ASSESSMENT (Lin & Zhang 2025)
[ ] Validity: LLM coding of intended construct confirmed via pilot + rationale review
[ ] Reliability: run-to-run κ on 50-doc subsample reported; temperature=0 used
[ ] Replicability: model name + version + date + prompts archived
[ ] Transparency: prompts reproduced in supplementary; limitations discussed

STRUCTURED EXTRACTION (if used)
[ ] Pydantic schema documented and reproduced
[ ] Error rate (extraction failures / schema violations) reported
[ ] 10% spot-check against source documents conducted

CHAIN-OF-THOUGHT CODING (if used)
[ ] Reasoning steps documented in prompt
[ ] Sample CoT chains included in supplementary

GROUNDED THEORY (if used)
[ ] All 3 cycles documented (inductive → interpretive → deductive)
[ ] Category definitions reproduced verbatim
[ ] κ from Cycle 3 deductive coding ≥ 0.70

RAG / DOCUMENT QA (if used)
[ ] Chunk size and embedding model documented
[ ] Retrieval quality assessed (sample queries spot-checked)
[ ] Answers grounded in retrieved passages (no hallucinated citations)

COST
[ ] Total token usage and estimated cost reported
[ ] Cost included in Methods or budget note

RESULT: [PASS / NEEDS REVISION]
Issues: [list]
```

---

## MODULE 8: LLM Synthetic Data Generation

Use LLMs as simulated participants to generate synthetic behavioral, attitudinal, or organizational data for social science research. This module covers context/persona engineering, silicon sampling (survey simulation), vignette and conjoint simulation, organizational and group behavior simulation, and multi-agent opinion dynamics.

**Core logic**: An LLM given a rich sociodemographic and contextual persona can approximate the response distribution of that social group. This is *not* a substitute for human data — it is a tool for pre-testing, power analysis, theory development, and exploring counterfactual scenarios.

---

### Step 1 — Feasibility and Ethics Gate

Before running any simulation, assess whether synthetic data is appropriate:

| Use case | Appropriate | Caution |
|----------|------------|---------|
| Pre-testing survey instruments | ✓ Low cost, fast iteration | Validate with cognitive interviews before fielding |
| Power analysis / sample size estimation | ✓ | Treat as priors, not ground truth |
| Exploring counterfactual scenarios ("what if policy X?") | ✓ with limitations | LLMs reflect historical training data; future behavior may differ |
| Rare or hard-to-reach populations | Partial | LLMs may poorly represent truly marginalized groups |
| **Replacing human survey data in published findings** | **✗ Not appropriate** | Bisbee et al. (2023) show significant distributional mismatch |
| Generating labeled training data for classifiers | With validation | Must validate synthetic labels against human-coded gold standard |

**Validation is mandatory**: Any synthetic data used in a published paper must be compared against actual human data (ANES, GSS, CCES, or original survey) using distributional tests. Report alignment metrics (KS statistic, Jensen-Shannon divergence, mean differences).

**IRB**: Check with your IRB whether LLM simulation of specific real-world groups requires review, especially if used to make claims about marginalized populations.

---

### Step 2 — Persona / Context Engineering

The quality of synthetic data depends entirely on the richness and consistency of the persona prompt. Structure personas at three levels:

**Macro context** (societal): time period, country/region, political environment
**Meso context** (group/organization): industry, workplace, neighborhood, social network
**Micro context** (individual): demographics, life history, values, current situation

```python
import anthropic, json
from dataclasses import dataclass, asdict
from typing import Optional

client = anthropic.Anthropic()

@dataclass
class SocialPersona:
    """Structured persona for LLM social simulation."""
    # Demographics
    age:              int
    gender:           str
    race_ethnicity:   str
    education:        str          # "less than high school" / "high school" / "some college" /
                                   # "bachelor's" / "graduate degree"
    household_income: str          # "$0-$30K" / "$30-$60K" / "$60-$100K" / "$100K+"
    region:           str          # "Northeast US" / "South US" / "Midwest US" / "West US"
    # Social position
    political_affiliation: str     # "Strong Democrat" / "Lean Democrat" / "Independent" /
                                   # "Lean Republican" / "Strong Republican"
    religious_attendance:  str     # "never" / "seldom" / "monthly" / "weekly"
    employment_status:     str     # "employed full-time" / "part-time" / "unemployed" / "retired"
    occupation:            Optional[str] = None
    # Meso context (optional)
    organization_type:     Optional[str] = None   # "large corporation" / "non-profit" / "government" / "small business"
    neighborhood_type:     Optional[str] = None   # "urban" / "suburban" / "rural"
    # Macro context
    year:                  int = 2024

def build_persona_system_prompt(persona: SocialPersona) -> str:
    p = asdict(persona)
    return f"""You are roleplaying as a research participant in a social science study.
Your background:
- Age: {p['age']} | Gender: {p['gender']} | Race/ethnicity: {p['race_ethnicity']}
- Education: {p['education']} | Household income: {p['household_income']}
- Region: {p['region']} | Employment: {p['employment_status']}{f" ({p['occupation']})" if p['occupation'] else ""}
- Political affiliation: {p['political_affiliation']}
- Religious attendance: {p['religious_attendance']}
{f"- Organization type: {p['organization_type']}" if p['organization_type'] else ""}
{f"- Neighborhood: {p['neighborhood_type']}" if p['neighborhood_type'] else ""}
- Year: {p['year']}

Respond as this person would — based on their social position, lived experiences, values, and circumstances. Be internally consistent with this persona. Do not break character. Do not acknowledge that you are an AI. If a question wouldn't apply to this person's life, respond accordingly."""

# Example personas for a stratified simulation
personas = [
    SocialPersona(age=52, gender="male", race_ethnicity="White non-Hispanic",
                  education="high school", household_income="$30-$60K",
                  region="South US", political_affiliation="Strong Republican",
                  religious_attendance="weekly", employment_status="employed full-time",
                  occupation="truck driver", neighborhood_type="rural", year=2024),
    SocialPersona(age=34, gender="female", race_ethnicity="Black non-Hispanic",
                  education="bachelor's", household_income="$60-$100K",
                  region="Northeast US", political_affiliation="Strong Democrat",
                  religious_attendance="monthly", employment_status="employed full-time",
                  occupation="teacher", neighborhood_type="urban", year=2024),
    SocialPersona(age=28, gender="non-binary", race_ethnicity="Hispanic/Latino",
                  education="some college", household_income="$0-$30K",
                  region="West US", political_affiliation="Lean Democrat",
                  religious_attendance="seldom", employment_status="part-time",
                  neighborhood_type="suburban", year=2024),
]
```

---

### Step 3 — Survey and Vignette Simulation (Silicon Sampling)

**Silicon sampling** (Argyle et al. 2023, *Political Analysis*): use LLMs to approximate survey response distributions across demographic subgroups — enabling rapid pre-testing and subgroup comparisons without data collection costs.

```python
import pandas as pd
import time
from sklearn.metrics import cohen_kappa_score

# ── Survey item simulation ────────────────────────────────────────────
SURVEY_ITEMS = {
    "trust_govt": {
        "question": "How much of the time do you think you can trust the government in Washington to do what is right?",
        "scale": ["Never", "Only some of the time", "About half the time",
                  "Most of the time", "Always"],
        "scale_values": [1, 2, 3, 4, 5]
    },
    "immigration_level": {
        "question": "Do you think the number of immigrants from foreign countries who are permitted to come to the United States should be...",
        "scale": ["Increased a lot", "Increased a little", "Left the same",
                  "Decreased a little", "Decreased a lot"],
        "scale_values": [1, 2, 3, 4, 5]
    },
    "healthcare_govt_responsibility": {
        "question": "Do you think it is the responsibility of the federal government to make sure all Americans have health care coverage?",
        "scale": ["Definitely should be", "Probably should be",
                  "Probably should not be", "Definitely should not be"],
        "scale_values": [1, 2, 3, 4]
    }
}

def simulate_survey_item(persona: SocialPersona, item_key: str,
                          model="claude-sonnet-4-6", temperature=0.5) -> dict:
    """
    Simulate a single survey response for a given persona.
    temperature=0.5: some variation across respondents (not fully deterministic)
    """
    item      = SURVEY_ITEMS[item_key]
    scale_str = " | ".join([f"({v}) {l}" for v, l in
                             zip(item["scale_values"], item["scale"])])
    system = build_persona_system_prompt(persona)
    user   = (f"Survey question: {item['question']}\n\n"
              f"Response options: {scale_str}\n\n"
              f"Please choose your response. Reply ONLY with the number corresponding "
              f"to your answer (e.g., '2'), then a brief explanation on the same line "
              f"separated by a pipe: '2 | Because...'")
    msg = client.messages.create(
        model=model, max_tokens=80, temperature=temperature,
        system=system, messages=[{"role": "user", "content": user}]
    )
    raw = msg.content[0].text.strip()
    # Parse: "2 | explanation"
    parts = raw.split("|", 1)
    try:
        value = int(parts[0].strip())
        label = item["scale"][item["scale_values"].index(value)]
    except (ValueError, IndexError):
        value, label = None, raw
    return {"persona_id": id(persona), "item": item_key, "value": value,
            "label": label, "raw": raw, "model": model}

# ── Run stratified simulation ─────────────────────────────────────────
# Each persona responds N_REPS times to capture within-persona stochasticity
N_REPS = 5

rows = []
for persona in personas:
    for item_key in SURVEY_ITEMS:
        for rep in range(N_REPS):
            row = simulate_survey_item(persona, item_key)
            row.update({
                "rep":        rep,
                "age":        persona.age,
                "gender":     persona.gender,
                "race":       persona.race_ethnicity,
                "education":  persona.education,
                "party":      persona.political_affiliation,
                "region":     persona.region
            })
            rows.append(row)
            time.sleep(0.3)

synth_df = pd.DataFrame(rows)
synth_df.to_csv("${OUTPUT_ROOT}/tables/synthetic-survey-responses.csv", index=False)

# Aggregate: mean response per persona × item
summary = synth_df.groupby(["race", "party", "item"])["value"].agg(
    ["mean", "std", "count"]).reset_index()
print(summary)
```

**Factorial vignette simulation**: manipulate one experimental condition while holding persona constant, or hold condition constant while varying persona:

```python
VIGNETTE_TEMPLATE = """Imagine the following situation:
A {applicant_race} {applicant_gender} named {applicant_name} applies for a {position} position
at a {company_type}. They have {qualifications}.

How likely are you to recommend this applicant for an interview?
Scale: 1 (Very unlikely) to 7 (Very likely).
Reply with ONLY the number."""

VIGNETTE_CONDITIONS = [
    {"applicant_race": "White", "applicant_gender": "man", "applicant_name": "Greg",
     "position": "manager", "company_type": "Fortune 500 company",
     "qualifications": "a bachelor's degree and 5 years of experience"},
    {"applicant_race": "Black", "applicant_gender": "man", "applicant_name": "Jamal",
     "position": "manager", "company_type": "Fortune 500 company",
     "qualifications": "a bachelor's degree and 5 years of experience"},
    {"applicant_race": "White", "applicant_gender": "woman", "applicant_name": "Emily",
     "position": "manager", "company_type": "Fortune 500 company",
     "qualifications": "a bachelor's degree and 5 years of experience"},
    {"applicant_race": "Black", "applicant_gender": "woman", "applicant_name": "Lakisha",
     "position": "manager", "company_type": "Fortune 500 company",
     "qualifications": "a bachelor's degree and 5 years of experience"},
]

def simulate_vignette(persona: SocialPersona, condition: dict,
                      model="claude-sonnet-4-6") -> dict:
    system = build_persona_system_prompt(persona)
    vignette_text = VIGNETTE_TEMPLATE.format(**condition)
    msg = client.messages.create(
        model=model, max_tokens=10, temperature=0.3, system=system,
        messages=[{"role": "user", "content": vignette_text}]
    )
    try:
        rating = int(msg.content[0].text.strip()[0])
    except (ValueError, IndexError):
        rating = None
    return {"rating": rating, **condition,
            "persona_party": persona.political_affiliation,
            "persona_race": persona.race_ethnicity}
```

**Conjoint experiment simulation**:

```python
import itertools, random

CONJOINT_ATTRIBUTES = {
    "candidate_race":      ["White", "Black", "Hispanic", "Asian American"],
    "candidate_gender":    ["man", "woman"],
    "candidate_party":     ["Democrat", "Republican", "Independent"],
    "candidate_age":       ["35", "52", "68"],
    "candidate_education": ["state university", "Ivy League university", "community college"],
}

def build_conjoint_profile(attributes: dict) -> str:
    return (f"Candidate A: A {attributes['candidate_age']}-year-old "
            f"{attributes['candidate_race']} {attributes['candidate_gender']}, "
            f"{attributes['candidate_party']}, graduated from {attributes['candidate_education']}.")

def simulate_conjoint_choice(persona: SocialPersona, profile_a: dict,
                              profile_b: dict, model="claude-sonnet-4-6") -> dict:
    system = build_persona_system_prompt(persona)
    user   = (f"{build_conjoint_profile(profile_a)}\n\n"
              f"{build_conjoint_profile(profile_b).replace('Candidate A', 'Candidate B')}\n\n"
              f"Which candidate would you vote for? Reply ONLY with 'A' or 'B'.")
    msg = client.messages.create(
        model=model, max_tokens=5, temperature=0.3, system=system,
        messages=[{"role": "user", "content": user}]
    )
    choice = msg.content[0].text.strip()[0].upper()
    return {"choice": choice,
            **{f"A_{k}": v for k, v in profile_a.items()},
            **{f"B_{k}": v for k, v in profile_b.items()},
            "persona_party": persona.political_affiliation,
            "persona_race": persona.race_ethnicity}
```

---

### Step 4 — Organizational and Group Behavior Simulation

Simulate how organizational roles and institutional contexts shape decisions: hiring committees, peer review panels, performance evaluations, or group negotiations.

```python
# ── Hiring committee simulation ───────────────────────────────────────
HIRING_SYSTEM = """You are roleplaying as a hiring manager at a {org_type} organization.
You are evaluating job applications for a {position} role.
Your organization's stated values: {org_values}.
Your professional background: {years_exp} years in {industry}.
Make decisions as this person would, shaped by their organizational context and professional norms."""

def simulate_hiring_decision(org_context: dict, candidate_profile: str,
                              model="claude-sonnet-4-6") -> dict:
    system = HIRING_SYSTEM.format(**org_context)
    user   = (f"Candidate profile:\n{candidate_profile}\n\n"
              f"Would you advance this candidate to the next round? "
              f"Reply with JSON: {{\"advance\": true/false, "
              f"\"rating\": 1-10, \"rationale\": \"one sentence\"}}")
    msg = client.messages.create(
        model=model, max_tokens=120, temperature=0.4, system=system,
        messages=[{"role": "user", "content": user}]
    )
    result = json.loads(msg.content[0].text)
    result.update(org_context)
    return result

# Experimental conditions: vary org_type while keeping candidate constant
ORG_CONDITIONS = [
    {"org_type": "large technology corporation", "position": "software engineer",
     "org_values": "innovation, efficiency, technical excellence",
     "years_exp": 12, "industry": "tech"},
    {"org_type": "non-profit social services organization", "position": "program coordinator",
     "org_values": "equity, community impact, lived experience",
     "years_exp": 8, "industry": "non-profit"},
    {"org_type": "federal government agency", "position": "policy analyst",
     "org_values": "public service, neutrality, thoroughness",
     "years_exp": 15, "industry": "government"},
]

# ── Group deliberation simulation ────────────────────────────────────
def simulate_group_deliberation(group_personas: list[SocialPersona],
                                 topic: str, n_rounds: int = 3,
                                 model="claude-sonnet-4-6") -> pd.DataFrame:
    """
    Simulate sequential group deliberation on a topic.
    Each agent sees the previous agents' statements before responding.
    """
    history    = []
    all_rounds = []

    for round_num in range(n_rounds):
        for i, persona in enumerate(group_personas):
            system = build_persona_system_prompt(persona)
            # Build context from prior statements
            prior = "\n".join([f"Person {s['agent_id']}: {s['statement']}"
                                for s in history[-len(group_personas):]])
            user  = (f"Your group is discussing: {topic}\n\n"
                     f"{'Previous statements:\n' + prior if prior else 'You speak first.'}\n\n"
                     f"Share your view in 2–3 sentences. Be authentic to your background.")
            msg = client.messages.create(
                model=model, max_tokens=150, temperature=0.6, system=system,
                messages=[{"role": "user", "content": user}]
            )
            entry = {"round": round_num, "agent_id": i,
                     "race": persona.race_ethnicity, "party": persona.political_affiliation,
                     "statement": msg.content[0].text.strip()}
            history.append(entry)
            all_rounds.append(entry)

    df = pd.DataFrame(all_rounds)
    df.to_csv("${OUTPUT_ROOT}/tables/group-deliberation-transcript.csv", index=False)
    return df
```

---

### Step 5 — Multi-Agent Opinion Dynamics

Simulate how opinions form, diffuse, and polarize across a social network of LLM agents. Extends MODULE 4 (ABM) with LLM-powered cognition at each step.

```python
import networkx as nx
import numpy as np

def initialize_opinion_agents(n_agents: int, topic: str,
                               model="claude-haiku-4-5-20251001") -> list[dict]:
    """Initialize agents with diverse starting opinions on a topic."""
    # Sample demographic diversity proportional to US Census
    personas_sample = random.choices(personas, k=n_agents)
    agents = []
    for i, persona in enumerate(personas_sample):
        system = build_persona_system_prompt(persona)
        user   = (f"On a scale of 1–10, where 1 = strongly oppose and "
                  f"10 = strongly support, what is your initial view on: {topic}?\n"
                  f"Reply ONLY with the number.")
        msg = client.messages.create(
            model=model, max_tokens=5, temperature=0.4, system=system,
            messages=[{"role": "user", "content": user}]
        )
        try:    opinion = int(msg.content[0].text.strip()[0])
        except: opinion = 5
        agents.append({"id": i, "persona": persona, "opinion": opinion,
                        "opinion_history": [opinion], "party": persona.political_affiliation})
    return agents

def update_opinion_after_exposure(agent: dict, neighbor_opinions: list[int],
                                   neighbor_parties: list[str], topic: str,
                                   model="claude-haiku-4-5-20251001") -> int:
    """Agent updates opinion after hearing neighbors' views."""
    system = build_persona_system_prompt(agent["persona"])
    n_summary = "; ".join([f"Person (party={p}, opinion={o}/10)"
                           for o, p in zip(neighbor_opinions, neighbor_parties)])
    user = (f"You currently rate your support for '{topic}' as {agent['opinion']}/10.\n"
            f"You just heard these views from people around you: {n_summary}.\n\n"
            f"After hearing these perspectives, what is your new rating (1–10)? "
            f"Reply ONLY with the number.")
    msg = client.messages.create(
        model=model, max_tokens=5, temperature=0.2, system=system,
        messages=[{"role": "user", "content": user}]
    )
    try:    return int(msg.content[0].text.strip()[0])
    except: return agent["opinion"]

def run_opinion_dynamics(agents: list[dict], G: nx.Graph,
                          topic: str, n_steps: int = 10,
                          model="claude-haiku-4-5-20251001") -> pd.DataFrame:
    """
    Run opinion dynamics simulation on network G.
    Each step: each agent updates opinion based on neighbors' current opinions.
    """
    records = [{"step": 0, "agent_id": a["id"],
                "opinion": a["opinion"], "party": a["party"]} for a in agents]

    for step in range(1, n_steps + 1):
        new_opinions = {}
        for node in G.nodes():
            agent     = agents[node]
            neighbors = list(G.neighbors(node))
            if not neighbors:
                new_opinions[node] = agent["opinion"]
                continue
            nb_opinions = [agents[n]["opinion"] for n in neighbors]
            nb_parties  = [agents[n]["party"]   for n in neighbors]
            new_opinions[node] = update_opinion_after_exposure(
                agent, nb_opinions, nb_parties, topic, model)

        for node, new_op in new_opinions.items():
            agents[node]["opinion"] = new_op
            agents[node]["opinion_history"].append(new_op)
            records.append({"step": step, "agent_id": node,
                             "opinion": new_op, "party": agents[node]["party"]})

    df = pd.DataFrame(records)
    df.to_csv("${OUTPUT_ROOT}/tables/opinion-dynamics-trajectory.csv", index=False)
    return df

# Build a small-world social network (Watts-Strogatz)
N, K, P = 50, 4, 0.1
G = nx.watts_strogatz_graph(N, K, P, seed=42)

# Note: estimate cost before running full simulation
# N_agents=50, N_steps=10, 1 call/agent/step = 500 calls (haiku ~$0.05 total)

**Reporting template:**
> "We simulate opinion dynamics among N = [X] agents organized in a Watts-Strogatz small-world network (k = [K], p = [P]). Each agent is assigned a demographic persona drawn from [source; e.g., US Census marginal distributions]. At each of [T] time steps, agents update their position on [topic] after observing their immediate network neighbors' views, using Claude Haiku as the cognitive engine (temperature = 0.2; seed = 42). We track the Gini coefficient of opinion heterogeneity and partisan opinion gap across steps. Results are reported for [T] steps; sensitivity to network topology (Erdős-Rényi and scale-free alternatives) is shown in Figure A[X]."
```

---

### Step 6 — Validation Against Human Data (REQUIRED)

**All synthetic data used in publication must be validated against real human responses.** Distributional mismatch is common (Bisbee et al. 2023); report it transparently.

```python
from scipy.stats import ks_2samp
import numpy as np

# ── Compare synthetic to GSS / ANES / CCES distributions ──────────────
def validate_synthetic_vs_real(synthetic_responses: list[int],
                                real_responses: list[int],
                                variable_name: str) -> dict:
    """
    Compare synthetic and real response distributions.
    Returns alignment metrics for Methods reporting.
    """
    ks_stat, ks_p = ks_2samp(synthetic_responses, real_responses)
    mean_diff     = np.mean(synthetic_responses) - np.mean(real_responses)

    # Jensen-Shannon divergence (0 = identical; 1 = maximally different)
    from scipy.special import rel_entr
    def js_divergence(p, q):
        p, q = np.array(p)/sum(p), np.array(q)/sum(q)
        m = 0.5 * (p + q)
        return 0.5 * (sum(rel_entr(p, m)) + sum(rel_entr(q, m)))

    scale_vals = sorted(set(synthetic_responses) | set(real_responses))
    p_dist = [synthetic_responses.count(v)/len(synthetic_responses) for v in scale_vals]
    q_dist = [real_responses.count(v)/len(real_responses)            for v in scale_vals]
    jsd = js_divergence(p_dist, q_dist)

    return {
        "variable":        variable_name,
        "n_synthetic":     len(synthetic_responses),
        "n_real":          len(real_responses),
        "mean_synthetic":  round(np.mean(synthetic_responses), 3),
        "mean_real":       round(np.mean(real_responses), 3),
        "mean_diff":       round(mean_diff, 3),
        "ks_statistic":    round(ks_stat, 3),
        "ks_p":            round(ks_p, 4),
        "js_divergence":   round(jsd, 3),
        "aligned":         ks_stat < 0.10 and abs(mean_diff) < 0.5
    }

# ── Known limitations to report ───────────────────────────────────────
# 1. Homogenization bias: LLMs tend toward centrist/moderate responses
# 2. Demographic steerability: some groups are steered more reliably than others
# 3. Training recency: LLMs reflect data through training cutoff; recent events not captured
# 4. Intersectionality gaps: combinations of identities may not be well-represented
# 5. Rare populations: LLMs may poorly simulate truly marginalized groups
```

**Required validation reporting (Nature Computational Science / Science Advances):**
- Report KS statistic and Jensen-Shannon divergence between synthetic and real distributions for every key variable
- Report subgroup-level alignment (by race, party, education) not just aggregate
- Explicitly state that synthetic data is used for [pre-testing / power analysis / theory development], not as a substitute for human data
- If used for published substantive claims: requires matched real-data replication

---

### Step 7 — Synthetic Data Verification (Subagent)

```
SYNTHETIC DATA VERIFICATION REPORT
=====================================

FEASIBILITY GATE
[ ] Use case is appropriate (pre-testing / power analysis / theory; NOT substitute for human data)
[ ] IRB consideration documented (or exemption justified)
[ ] Known LLM limitations for this population acknowledged

PERSONA ENGINEERING
[ ] Personas cover the theoretical range of the key moderating variable
[ ] Persona prompts include macro + meso + micro context
[ ] Temperature documented (survey: 0.3–0.5; deliberation: 0.5–0.6; choice: 0.2–0.4)
[ ] Model name + version + date recorded
[ ] Prompts archived verbatim (system + user)

SIMULATION DESIGN
[ ] N personas and N reps per persona/condition documented
[ ] Experimental condition (vignette / conjoint attribute) manipulated cleanly
[ ] Randomization / counterbalancing applied where needed
[ ] Estimated cost computed before full run; reported in Methods

VALIDATION (if using synthetic data in analysis)
[ ] Compared to actual human survey data (GSS / ANES / CCES / original survey)
[ ] KS statistic and JSD reported per variable
[ ] Subgroup alignment checked (not just aggregate)
[ ] Homogenization bias assessed (are synthetic responses more centrist than real?)
[ ] Limitations section explicitly names known failure modes

OPINION DYNAMICS (if used)
[ ] Network topology specified and justified (small-world / random / scale-free)
[ ] N agents, N steps, update rule documented
[ ] Sensitivity to topology in robustness (at minimum 2 alternative networks)
[ ] Cost estimate computed (N_agents × N_steps × price/call)

REPRODUCIBILITY
[ ] set.seed(42) / random.seed(42) for persona sampling and network initialization
[ ] Raw LLM outputs (full responses, not just derived values) saved to CSV
[ ] Simulation results saved to output/[slug]/tables/

RESULT: [PASS / NEEDS REVISION]
Issues: [list]
```

---

## MODULE 9: Geospatial and Spatial Analysis

### Step 1 — When to Use Spatial Methods

Spatial methods are appropriate when:
- Outcome or covariates vary across geographic units (census tracts, counties, states)
- **Spatial autocorrelation** is present in residuals (Moran's I test is significant)
- Research involves **neighborhood spillover effects** — outcomes in one unit affect neighbors
- You need to map geographic patterns as evidence (choropleth visualization)
- You are linking individual-level survey data to area-level characteristics (contextual effects)

Ignoring spatial autocorrelation when present produces invalid SEs (analogous to ignoring clustering). Run a diagnostic before choosing the model.

**Method selection:**
| Pattern in Moran's I | Recommendation |
|---------------------|---------------|
| Residuals spatially autocorrelated; substantive neighbor spillovers | **Spatial lag model** (SAR) |
| Residuals spatially autocorrelated; no theoretical spillover | **Spatial error model** (SEM) |
| Both substantive spillovers and error autocorrelation | **SARAR** (Kelejian-Prucha) |
| Autocorrelation present only in specific covariate | **Spatial Durbin model** |
| No autocorrelation detected | OLS / standard GLM (use `/scholar-causal`) |

---

### Step 2 — Build Spatial Data with sf + tidycensus

```r
library(sf)
library(tidycensus)
library(tidyverse)

# ── ACS data (Census tract / county) ──────────────────────────────────
# Set Census API key once:  tidycensus::census_api_key("YOUR_KEY", install=TRUE)

# Download ACS 5-year estimates at county level
acs_county <- get_acs(
  geography = "county",
  variables = c(
    poverty_rate    = "B17001_002",   # population in poverty
    total_pop       = "B01003_001",
    median_income   = "B19013_001",
    pct_college     = "B15003_022",
    pct_unemployed  = "B23025_005"
  ),
  year       = 2022,
  survey     = "acs5",
  geometry   = TRUE,           # download spatial geometries as sf object
  output     = "wide",
  state      = NULL            # NULL = all states; or "CA" for single state
) |>
  mutate(
    poverty_rate = poverty_rateE / total_popE * 100,
    pct_college  = pct_collegeE  / total_popE * 100
  )

# Coordinate reference system: project to Albers Equal Area for CONUS
acs_county <- st_transform(acs_county, crs=5070)

# ── Join external data to spatial object ──────────────────────────────
df_county <- read_csv("data/county-outcome.csv")  # must have GEOID column (5-digit county FIPS)
spatial_df <- acs_county |>
  left_join(df_county, by="GEOID")

# ── Basic spatial visualization ────────────────────────────────────────
library(tmap)
tmap_mode("plot")

tm_shape(spatial_df) +
  tm_fill("median_incomeE",
          palette   = "Blues",
          style     = "jenks",   # natural breaks
          title     = "Median Household Income") +
  tm_borders(alpha=0.3) +
  tm_layout(main.title="County-Level Median Income, ACS 2022",
            legend.outside=TRUE)
tmap_save(filename="${OUTPUT_ROOT}/figures/fig-choropleth-income.pdf", width=10, height=7)

# ggplot2 alternative (for publication formatting)
ggplot(spatial_df) +
  geom_sf(aes(fill=median_incomeE), color="white", linewidth=0.1) +
  scale_fill_viridis_c(option="B", labels=scales::comma,
                       name="Median Income ($)") +
  coord_sf(crs=5070) +
  labs(fill="Median Income ($)") +
  theme_void()
ggsave("${OUTPUT_ROOT}/figures/fig-choropleth-ggplot.pdf", width=12, height=8)
```

---

### Step 3 — Spatial Weights Matrix + Moran's I Diagnostic

```r
library(spdep)

# ── Build spatial weights matrix ──────────────────────────────────────
# Queen contiguity (share at least one point, including corners)
nb_queen <- poly2nb(spatial_df, queen=TRUE)

# K-nearest neighbors alternative (use when many islands / non-contiguous units)
coords   <- st_centroid(spatial_df) |> st_coordinates()
nb_knn   <- knearneigh(coords, k=5) |> knn2nb()

# Convert to listw object (row-standardized)
lw_queen <- nb2listw(nb_queen, style="W", zero.policy=TRUE)

# ── Moran's I test on OLS residuals ──────────────────────────────────
ols_fit <- lm(outcome ~ poverty_rate + median_incomeE + pct_college,
              data=spatial_df)
moran_test <- moran.test(residuals(ols_fit), lw_queen, zero.policy=TRUE)
print(moran_test)
# If p < 0.05: spatial autocorrelation present → proceed to spatial regression
# If p > 0.05: no autocorrelation → standard OLS is sufficient

# ── Moran scatterplot ─────────────────────────────────────────────────
moran.plot(residuals(ols_fit), lw_queen, zero.policy=TRUE,
           main="Moran Scatterplot of OLS Residuals",
           xlab="OLS Residuals", ylab="Spatially Lagged Residuals")

# ── Lagrange Multiplier tests (guide model selection) ─────────────────
lm_tests <- lm.LMtests(ols_fit, lw_queen,
                        test=c("LMlag", "LMerr", "RLMlag", "RLMerr"),
                        zero.policy=TRUE)
print(lm_tests)
# If RLMlag significant (not RLMerr) → spatial lag model
# If RLMerr significant (not RLMlag) → spatial error model
# If both → SARAR or spatial Durbin model

# ── Local Moran's I (LISA) — identify spatial clusters ────────────────
local_moran <- localmoran(spatial_df$outcome, lw_queen, zero.policy=TRUE)
spatial_df$local_I     <- local_moran[, "Ii"]
spatial_df$local_p     <- local_moran[, "Pr(z != E(Ii))"]
spatial_df$LISA_cluster <- case_when(
  spatial_df$outcome    > mean(spatial_df$outcome) &
    lag.listw(lw_queen, spatial_df$outcome) > mean(spatial_df$outcome) &
    spatial_df$local_p < 0.05 ~ "High-High",
  spatial_df$outcome    < mean(spatial_df$outcome) &
    lag.listw(lw_queen, spatial_df$outcome) < mean(spatial_df$outcome) &
    spatial_df$local_p < 0.05 ~ "Low-Low",
  spatial_df$outcome    > mean(spatial_df$outcome) &
    lag.listw(lw_queen, spatial_df$outcome) < mean(spatial_df$outcome) &
    spatial_df$local_p < 0.05 ~ "High-Low",
  spatial_df$local_p < 0.05 ~ "Low-High",
  TRUE ~ "Not significant"
)

# LISA map
ggplot(spatial_df) +
  geom_sf(aes(fill=LISA_cluster), color="white", linewidth=0.1) +
  scale_fill_manual(
    values=c("High-High"="#d7191c", "Low-Low"="#2c7bb6",
             "High-Low"="#fdae61", "Low-High"="#abd9e9",
             "Not significant"="grey90")) +
  labs(fill="Cluster Type") +
  theme_void()
ggsave("${OUTPUT_ROOT}/figures/fig-lisa-map.pdf", width=10, height=7)
```

---

### Step 4 — Spatial Regression Models

```r
library(spatialreg)

# ── Spatial Lag Model (SAR) — y = ρWy + Xβ + ε ───────────────────────
# Use when: substantive neighbor spillovers (H: neighbors' outcomes affect focal unit)
sar_model <- lagsarlm(
  formula     = outcome ~ poverty_rate + median_incomeE + pct_college,
  data        = spatial_df,
  listw       = lw_queen,
  zero.policy = TRUE
)
summary(sar_model, Nagelkerke=TRUE)
# ρ (spatial lag coefficient): positive = high-[outcome] neighbors increase focal outcome

# ── Spatial Error Model (SEM) — y = Xβ + u, u = λWu + ε ─────────────
# Use when: autocorrelation is a nuisance (omitted spatial variable) not substantive
sem_model <- errorsarlm(
  formula     = outcome ~ poverty_rate + median_incomeE + pct_college,
  data        = spatial_df,
  listw       = lw_queen,
  zero.policy = TRUE
)
summary(sem_model, Nagelkerke=TRUE)
# λ (spatial error coefficient): mops up unmeasured spatial structure

# ── Model comparison ─────────────────────────────────────────────────
AIC(ols_fit, sar_model, sem_model)
# Also compare Moran's I on residuals after spatial correction
moran.test(residuals(sar_model), lw_queen, zero.policy=TRUE)
moran.test(residuals(sem_model), lw_queen, zero.policy=TRUE)

# ── Impacts (direct, indirect, total) in spatial lag model ────────────
# In SAR, each covariate has: direct effect (own-unit) + indirect (spillover)
impacts_sar <- impacts(sar_model, listw=lw_queen, R=500)
print(summary(impacts_sar, zstats=TRUE, short=TRUE))
# Report: direct impact + indirect (spillover) impact + total impact per covariate

# ── Export tables ─────────────────────────────────────────────────────
library(modelsummary)
modelsummary(list("OLS"=ols_fit, "Spatial Lag"=sar_model, "Spatial Error"=sem_model),
             gof_omit   = "IC|Log|Adj",
             output     = "${OUTPUT_ROOT}/tables/table-spatial-regression.html",
             title      = "Spatial Regression Models",
             notes      = "Spatial weights: Queen contiguity, row-standardized.")
```

**Spatial panel data** (units × time, with spatial autocorrelation):
```r
library(splm)
# spdm() for spatial panel with fixed/random effects
spanel <- spml(
  formula  = outcome ~ treatment + poverty_rate,
  data     = panel_df,
  listw    = lw_queen,
  lag      = TRUE,    # spatial lag
  spatial.error = "none",
  model    = "within",  # fixed effects
  index    = c("GEOID", "year")
)
summary(spanel)
```

---

### Step 5 — Geospatial Verification (Subagent)

```
GEOSPATIAL VERIFICATION REPORT
================================

DATA AND CRS
[ ] CRS documented (EPSG code reported); projection appropriate for study region
[ ] Units of analysis (tract / county / state) documented and justified
[ ] Spatial weights type (queen contiguity / KNN / distance-band) documented and justified
[ ] N units reported; any islands / disconnected units handled (zero.policy=TRUE)

MORAN'S I DIAGNOSTIC
[ ] Moran's I computed on OLS residuals (not raw outcome)
[ ] Moran's I statistic and p-value reported
[ ] LM tests (LMlag, LMerr, RLMlag, RLMerr) run to guide model selection
[ ] Model selection (SAR / SEM / SARAR / OLS) justified based on LM tests

SPATIAL REGRESSION (if used)
[ ] ρ (SAR) or λ (SEM) reported with SE and p-value
[ ] SAR impacts table (direct / indirect / total) computed and reported
[ ] Moran's I on spatial model residuals confirms autocorrelation removed
[ ] AIC comparison OLS vs. spatial model reported
[ ] Tables exported to output/[slug]/tables/

VISUALIZATION
[ ] Choropleth map uses colorblind-safe palette (viridis / Blues / diverging)
[ ] LISA cluster map uses correct 4-category color scheme
[ ] Maps saved as PDF + PNG

REPORTING
[ ] Data source cited (ACS year, variables, tidycensus version)
[ ] Spatial weights construction described
[ ] Limitations of spatial weights choice discussed (e.g., queen contiguity for irregular shapes)

RESULT: [PASS / NEEDS REVISION]
Issues: [list]
```

**Reporting template:**
> "We estimate [spatial lag / spatial error] models using the `spatialreg` package (Bivand and Piras 2015) with queen-contiguity spatial weights (row-standardized). We first confirmed the presence of spatial autocorrelation using Moran's I test on OLS residuals (Moran's I = [X], p = [p]). Lagrange Multiplier tests indicated [spatial lag / spatial error] specification (RLMlag = [X], p = [p]; RLMerr = [X], p = [p]). In the spatial lag model, the spatial autoregressive parameter ρ = [X] (SE = [SE]; p = [p]), indicating that [higher / lower] [outcome] in neighboring counties is associated with [higher / lower] focal county [outcome]. Direct, indirect (spillover), and total impacts are reported in Table [X]. After accounting for spatial dependence, residual Moran's I = [X] (p = [p]), confirming adequate correction."

---

## MODULE 10: Audio as Data

Social science use cases for audio: political speeches and debates (prosody, affect, rhetoric); oral history interviews processed at scale; broadcast news and podcast content analysis; music as cultural data; field recordings (protest sound, ambient environment); phone-in programs and legislative proceedings.

**Boundary with `scholar-ling`**: MODULE 10 focuses on audio *as content* — transcription, thematic coding, feature-based classification across corpora. For fine-grained acoustic phonetics (formant trajectories, VOT, F0 contours, Rbrul/VARBRUL) use `/scholar-ling MODULE 2`.

---

### Step 1 — Method Selection

| Goal | Recommended method |
|------|--------------------|
| Transcribe speech for text analysis | **Whisper / faster-whisper** (Step 3) |
| Transcribe + attribute speech to speakers | **faster-whisper + pyannote diarization** (Step 3b) |
| Extract acoustic statistics (MFCCs, rhythm, mood) | **Essentia** (Step 4) |
| Lightweight waveform features + visualization | **librosa** (Step 4) |
| Direct thematic / rhetorical analysis of audio | **Gemini 1.5 Pro or GPT-4o audio** (Step 5) |
| Classify audio into categories (music genre, event type, emotion) | **PANNs / AudioCLIP / wav2vec2** (Step 6) |
| Large-scale corpus thematic coding | Transcribe → route to **MODULE 1** (Step 7) |
| Measure affect / emotional valence in speech | Essentia mood models + prosodic features (Step 4) |

**Privacy / ethics gate (REQUIRED before any processing):**
- Does the audio contain identifiable voices? → check IRB protocol and `/scholar-safety` before uploading to cloud APIs (Whisper API, Gemini, GPT-4o)
- For sensitive data (therapy sessions, oral history with vulnerable subjects): use **local Whisper** (`faster-whisper` runs fully offline) and local LLM (Ollama) — no data leaves the machine
- For broadcast / public speech: cloud APIs generally acceptable; document in Methods

---

### Step 2 — Audio Loading and Preprocessing (librosa + pydub)

```python
import librosa
import librosa.display
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
from pathlib import Path
from pydub import AudioSegment
import os

# ── Constants ──────────────────────────────────────────────────────────
SR          = 22050    # target sample rate (Hz); 16000 for ASR/Whisper
HOP_LENGTH  = 512
N_MELS      = 128
N_MFCC      = 40
DURATION    = None     # None = load full file; or set seconds to truncate

# ── Load single audio file ────────────────────────────────────────────
def load_audio(path: str, sr: int = SR) -> tuple:
    """Load audio; convert stereo → mono; resample to target SR."""
    y, sr_orig = librosa.load(path, sr=sr, mono=True, duration=DURATION)
    return y, sr

# ── Batch conversion: mp3/m4a/wav → 16kHz mono wav (for Whisper) ──────
def convert_to_wav(input_dir: str, output_dir: str, sr: int = 16000):
    """Convert all audio files to 16kHz mono WAV for Whisper processing."""
    os.makedirs(output_dir, exist_ok=True)
    for p in Path(input_dir).glob("**/*"):
        if p.suffix.lower() in {".mp3", ".m4a", ".ogg", ".flac", ".aac", ".mp4"}:
            audio = AudioSegment.from_file(str(p))
            audio = audio.set_channels(1).set_frame_rate(sr)
            out   = Path(output_dir) / (p.stem + ".wav")
            audio.export(str(out), format="wav")
            print(f"Converted: {p.name} → {out.name}")

# ── Silence detection and segmentation ───────────────────────────────
def segment_on_silence(path: str, min_silence_ms: int = 1000,
                        silence_thresh_db: int = -40,
                        out_dir: str = "${OUTPUT_ROOT}/audio_segments") -> list[str]:
    """Split audio on silence (useful for long-form interviews/podcasts)."""
    from pydub.silence import split_on_silence
    os.makedirs(out_dir, exist_ok=True)
    audio  = AudioSegment.from_file(path)
    chunks = split_on_silence(audio,
                               min_silence_len  = min_silence_ms,
                               silence_thresh   = silence_thresh_db,
                               keep_silence     = 300)
    paths = []
    for i, chunk in enumerate(chunks):
        out = os.path.join(out_dir, f"segment_{i:04d}.wav")
        chunk.export(out, format="wav")
        paths.append(out)
    print(f"Segmented into {len(chunks)} chunks → {out_dir}/")
    return paths

# ── Waveform and spectrogram visualization ────────────────────────────
def plot_waveform_and_spectrogram(y, sr, title: str = "Audio",
                                   out_path: str = "${OUTPUT_ROOT}/figures/fig-audio-spectrogram.pdf"):
    fig, axes = plt.subplots(2, 1, figsize=(12, 6))
    # Waveform
    librosa.display.waveshow(y, sr=sr, ax=axes[0], alpha=0.7)
    axes[0].set_title(f"{title} — Waveform")
    # Mel spectrogram
    S_db = librosa.power_to_db(librosa.feature.melspectrogram(y=y, sr=sr,
                                n_mels=N_MELS), ref=np.max)
    img  = librosa.display.specshow(S_db, sr=sr, hop_length=HOP_LENGTH,
                                     x_axis="time", y_axis="mel", ax=axes[1])
    fig.colorbar(img, ax=axes[1], format="%+2.0f dB")
    axes[1].set_title("Mel Spectrogram")
    plt.tight_layout()
    plt.savefig(out_path, dpi=300, bbox_inches="tight")
    plt.close()
```

---

### Step 3 — Transcription with Whisper / faster-whisper

**Option A — faster-whisper (recommended: 4× faster, runs locally, no API costs)**

```python
from faster_whisper import WhisperModel
import json, os, pandas as pd

# Model sizes: "tiny" (fast, lower accuracy) → "base" → "small" → "medium" → "large-v3"
# Use "large-v3" for publication-quality transcription
# Runs CPU or CUDA; set device="cuda" if GPU available
model = WhisperModel("large-v3", device="cpu", compute_type="int8")

def transcribe_file(audio_path: str, language: str = None) -> dict:
    """
    Transcribe a single audio file. Returns full transcript + timestamped segments.
    language: ISO 639-1 code (e.g., "en", "zh", "es") or None for auto-detection.
    """
    segments, info = model.transcribe(
        audio_path,
        language          = language,
        beam_size         = 5,
        word_timestamps   = True,    # enable word-level timestamps
        vad_filter        = True,    # voice activity detection (skip silence)
        vad_parameters    = dict(min_silence_duration_ms=500)
    )
    seg_list = []
    for seg in segments:
        seg_list.append({
            "start":   round(seg.start, 3),
            "end":     round(seg.end,   3),
            "text":    seg.text.strip(),
            "avg_log_prob": round(seg.avg_logprob, 4),  # confidence proxy
            "no_speech_prob": round(seg.no_speech_prob, 4)
        })
    transcript = " ".join(s["text"] for s in seg_list)
    return {
        "path":        audio_path,
        "language":    info.language,
        "duration_s":  round(info.duration, 1),
        "transcript":  transcript,
        "segments":    seg_list
    }

# Batch transcription
audio_files = list(Path("data/audio/").glob("*.wav"))
records     = []
for fp in audio_files:
    try:
        result = transcribe_file(str(fp), language="en")
        records.append(result)
        print(f"✓ {fp.name} ({result['duration_s']}s) → {len(result['segments'])} segments")
    except Exception as e:
        records.append({"path": str(fp), "error": str(e)})

# Save transcript table (one row per file)
trans_df = pd.DataFrame([{k: v for k, v in r.items() if k != "segments"}
                          for r in records])
trans_df.to_csv("${OUTPUT_ROOT}/tables/transcripts.csv", index=False)

# Save segment-level table (one row per timed segment — useful for alignment)
seg_rows = []
for r in records:
    if "segments" in r:
        for s in r["segments"]:
            seg_rows.append({"file": r["path"], **s})
pd.DataFrame(seg_rows).to_csv("${OUTPUT_ROOT}/tables/transcript-segments.csv", index=False)

print(f"\nTranscribed {len(records)} files. Saved to output/[slug]/tables/")
```

**Option B — OpenAI Whisper API (cloud, faster setup but data leaves machine)**
```python
from openai import OpenAI
client = OpenAI()   # set OPENAI_API_KEY

def transcribe_api(path: str, language: str = "en") -> dict:
    with open(path, "rb") as f:
        result = client.audio.transcriptions.create(
            model       = "whisper-1",
            file        = f,
            language    = language,
            response_format = "verbose_json",  # includes word timestamps
            timestamp_granularities = ["segment", "word"]
        )
    return {"path": path, "transcript": result.text,
            "segments": result.segments, "language": result.language}
# ⚠ Do NOT use for IRB-sensitive audio — data transmitted to OpenAI servers
```

---

### Step 3b — Speaker Diarization (Who Said What)

Diarization assigns each speech segment to a speaker label ("SPEAKER_00", "SPEAKER_01"), enabling speaker-level analysis (e.g., who speaks more, whose turns are interrupted, gender-linked patterns).

```python
# pip install pyannote.audio
# Requires Hugging Face token + model acceptance at hf.co/pyannote/speaker-diarization-3.1
from pyannote.audio import Pipeline as DiarizationPipeline
import torch, json, pandas as pd
from faster_whisper import WhisperModel

# ── 1. Initialize models ─────────────────────────────────────────────
HF_TOKEN = "hf_YOUR_TOKEN"   # set once; free at huggingface.co
diarize_pipeline = DiarizationPipeline.from_pretrained(
    "pyannote/speaker-diarization-3.1",
    use_auth_token = HF_TOKEN
)
asr_model = WhisperModel("large-v3", device="cpu", compute_type="int8")

# ── 2. Diarize ──────────────────────────────────────────────────────
def diarize(audio_path: str, num_speakers: int = None) -> list[dict]:
    """Return list of {speaker, start, end} segments."""
    diarization = diarize_pipeline(
        audio_path,
        num_speakers     = num_speakers,   # None = auto-detect
        min_speakers     = 1,
        max_speakers     = 10
    )
    segs = []
    for turn, _, speaker in diarization.itertracks(yield_label=True):
        segs.append({"speaker": speaker,
                     "start":   round(turn.start, 3),
                     "end":     round(turn.end,   3)})
    return segs

# ── 3. Align: merge ASR timestamps with diarization ──────────────────
def align_transcript_with_speakers(asr_segments: list[dict],
                                    diar_segments: list[dict]) -> list[dict]:
    """
    For each ASR segment, assign the speaker that dominates its time window.
    Simple overlap-based majority vote.
    """
    aligned = []
    for asr in asr_segments:
        best_spk, best_overlap = "UNKNOWN", 0.0
        for d in diar_segments:
            overlap = max(0, min(asr["end"], d["end"]) - max(asr["start"], d["start"]))
            if overlap > best_overlap:
                best_overlap, best_spk = overlap, d["speaker"]
        aligned.append({**asr, "speaker": best_spk})
    return aligned

# ── 4. Full pipeline per file ─────────────────────────────────────────
def transcribe_with_speakers(audio_path: str, language: str = "en",
                              num_speakers: int = None) -> pd.DataFrame:
    # ASR
    segments, _ = asr_model.transcribe(audio_path, language=language,
                                        word_timestamps=True, vad_filter=True)
    asr_segs    = [{"start": s.start, "end": s.end, "text": s.text.strip()}
                   for s in segments]
    # Diarize
    diar_segs   = diarize(audio_path, num_speakers=num_speakers)
    # Align
    aligned     = align_transcript_with_speakers(asr_segs, diar_segs)
    df          = pd.DataFrame(aligned)
    df["file"]  = audio_path
    return df

# Run on all files
all_aligned = []
for fp in audio_files:
    df = transcribe_with_speakers(str(fp), language="en")
    all_aligned.append(df)

diarized_df = pd.concat(all_aligned, ignore_index=True)
diarized_df.to_csv("${OUTPUT_ROOT}/tables/transcript-diarized.csv", index=False)

# Speaker-level summaries: speaking time, turn count, word count per speaker
speaker_stats = (diarized_df
    .assign(duration  = diarized_df.end - diarized_df.start,
            word_count= diarized_df.text.str.split().str.len())
    .groupby(["file", "speaker"])
    .agg(total_speaking_s = ("duration",   "sum"),
         n_turns           = ("start",      "count"),
         total_words        = ("word_count", "sum"))
    .reset_index())
speaker_stats.to_csv("${OUTPUT_ROOT}/tables/speaker-statistics.csv", index=False)
print(speaker_stats)
```

---

### Step 4 — Acoustic Feature Extraction: Essentia + librosa

**Essentia** (Music Technology Group, Barcelona) is the standard for high-level audio descriptors and pre-trained mood/emotion models. **librosa** handles lower-level frame-by-frame features efficiently.

```python
import essentia
import essentia.standard as es
import librosa
import numpy as np
import pandas as pd
from pathlib import Path

essentia.log.infoActive   = False   # suppress verbose output
essentia.log.warningActive= False

# ── A. Low-level features via Essentia (frame-level → statistics) ─────
def extract_low_level_features(audio_path: str, sr: int = 44100) -> dict:
    """
    Compute per-file summary statistics of frame-level acoustic features.
    Returns a flat dict of mean/std/median per feature — suitable for a CSV row.
    """
    loader = es.MonoLoader(filename=audio_path, sampleRate=sr)
    audio  = loader()

    # Frame-based analysis
    frame_size = 2048
    hop_size   = 512
    features   = {"file": audio_path}

    # ── Spectral features ──────────────────────────────────────────
    spec        = es.Spectrum(size=frame_size)
    centroid_fn = es.SpectralCentroidTime()
    rolloff_fn  = es.RollOff()
    flux_fn     = es.Flux()
    zcr_fn      = es.ZeroCrossingRate()
    rms_fn      = es.RMS()

    centroids, rolloffs, fluxes, zcrs, rmss = [], [], [], [], []
    for frame in es.FrameGenerator(audio, frameSize=frame_size,
                                    hopSize=hop_size, startFromZero=True):
        windowed = es.Windowing(type="hann")(frame)
        spectrum = spec(windowed)
        centroids.append(centroid_fn(frame))
        rolloffs.append(rolloff_fn(spectrum))
        fluxes.append(flux_fn(spectrum))
        zcrs.append(zcr_fn(frame))
        rmss.append(rms_fn(frame))

    for name, vals in [("spectral_centroid", centroids),
                        ("spectral_rolloff",  rolloffs),
                        ("spectral_flux",     fluxes),
                        ("zcr",               zcrs),
                        ("rms_energy",        rmss)]:
        arr = np.array(vals)
        features.update({
            f"{name}_mean":   float(np.mean(arr)),
            f"{name}_std":    float(np.std(arr)),
            f"{name}_median": float(np.median(arr))
        })

    # ── MFCCs (40 coefficients) ────────────────────────────────────
    mfcc_fn = es.MFCC(numberCoefficients=40, sampleRate=sr)
    mfccs   = []
    for frame in es.FrameGenerator(audio, frameSize=frame_size,
                                    hopSize=hop_size, startFromZero=True):
        windowed  = es.Windowing(type="hann")(frame)
        spectrum  = spec(windowed)
        _, mfcc_v = mfcc_fn(spectrum)
        mfccs.append(mfcc_v)
    mfcc_arr = np.array(mfccs)
    for i in range(mfcc_arr.shape[1]):
        features[f"mfcc_{i}_mean"] = float(np.mean(mfcc_arr[:, i]))
        features[f"mfcc_{i}_std"]  = float(np.std(mfcc_arr[:, i]))

    # ── Rhythm / tempo ─────────────────────────────────────────────
    rhythm_extractor = es.RhythmExtractor2013(method="multifeature")
    bpm, beats, bpm_confidence, _, bpm_intervals = rhythm_extractor(audio)
    features.update({
        "bpm":            float(bpm),
        "bpm_confidence": float(bpm_confidence),
        "n_beats":        len(beats)
    })

    # ── Tonal features ─────────────────────────────────────────────
    key_extractor = es.KeyExtractor()
    key, scale, key_strength = key_extractor(audio)
    features.update({
        "key":          key,
        "scale":        scale,      # "major" or "minor"
        "key_strength": float(key_strength)
    })

    # ── Loudness / dynamics ────────────────────────────────────────
    loudness_fn = es.Loudness()
    features["loudness_db"] = float(loudness_fn(audio))

    # ── Duration ──────────────────────────────────────────────────
    features["duration_s"] = float(len(audio) / sr)

    return features


# ── B. High-level mood / emotion via Essentia-TensorFlow models ───────
# Requires: pip install essentia-tensorflow
# Models: valence (positive/negative), arousal (calm/energetic), mood categories
def extract_mood_features(audio_path: str) -> dict:
    """
    Compute mood + emotion predictions using Essentia pre-trained TF models.
    Models available: MSD-MusicCNN (music), Discogs-EffNet (genre + mood)
    Download from: https://essentia.upf.edu/models/
    """
    try:
        from essentia.standard import (MonoLoader, TensorflowPredictEffnetDiscogs,
                                        TensorflowPredict2D)
        audio       = MonoLoader(filename=audio_path, sampleRate=16000,
                                  resampleQuality=4)()

        # EffNet-Discogs embeddings (replace path with your downloaded model)
        embeddings_model = TensorflowPredictEffnetDiscogs(
            graphFilename = "models/discogs-effnet-bs64-1.pb",
            output        = "PartitionedCall:1"
        )
        embeddings = embeddings_model(audio)

        # Mood classification on top of embeddings (approachable / not; happy / sad etc.)
        mood_model = TensorflowPredict2D(
            graphFilename = "models/mood_happy-discogs-effnet-1.pb",
            input         = "serving_default_model_Placeholder",
            output        = "PartitionedCall:0"
        )
        mood_probs = mood_model(embeddings)
        return {
            "audio_path":        audio_path,
            "mood_happy_prob":   float(mood_probs.mean(axis=0)[0]),
            "mood_unhappy_prob": float(mood_probs.mean(axis=0)[1])
        }
    except ImportError:
        return {"audio_path": audio_path,
                "mood_note": "essentia-tensorflow not installed — run: pip install essentia-tensorflow"}


# ── C. Quick prosodic features via librosa (for speech data) ──────────
def extract_prosodic_features(audio_path: str, sr: int = 22050) -> dict:
    """
    Extract prosodic features relevant for speech analysis:
    F0 (fundamental frequency / pitch), speaking rate proxy, pause ratio.
    """
    y, _     = librosa.load(audio_path, sr=sr, mono=True)
    duration = librosa.get_duration(y=y, sr=sr)

    # F0 estimation via pyin (probabilistic YIN)
    f0, voiced_flag, voiced_probs = librosa.pyin(
        y, fmin=librosa.note_to_hz("C2"),
        fmax=librosa.note_to_hz("C7"),
        sr=sr
    )
    f0_voiced = f0[voiced_flag]

    # Speech rate proxy: zero-crossing rate (higher = more consonants/fricatives)
    zcr_mean  = float(np.mean(librosa.feature.zero_crossing_rate(y)))

    # Pause ratio: fraction of frames classified as unvoiced
    pause_ratio = float(1 - np.mean(voiced_flag))

    return {
        "file":             audio_path,
        "duration_s":       round(duration, 2),
        "f0_mean_hz":       float(np.mean(f0_voiced)) if len(f0_voiced) > 0 else np.nan,
        "f0_std_hz":        float(np.std(f0_voiced))  if len(f0_voiced) > 0 else np.nan,
        "f0_range_hz":      float(np.ptp(f0_voiced))  if len(f0_voiced) > 0 else np.nan,
        "speaking_zcr":     zcr_mean,
        "pause_ratio":      round(pause_ratio, 4),
        "voiced_fraction":  round(1 - pause_ratio, 4)
    }


# ── D. Batch feature extraction pipeline ────────────────────────────
audio_files = list(Path("data/audio/").glob("*.wav"))

ll_features  = [extract_low_level_features(str(fp)) for fp in audio_files]
pro_features = [extract_prosodic_features(str(fp))  for fp in audio_files]

pd.DataFrame(ll_features ).to_csv("${OUTPUT_ROOT}/tables/audio-low-level-features.csv", index=False)
pd.DataFrame(pro_features).to_csv("${OUTPUT_ROOT}/tables/audio-prosodic-features.csv", index=False)
print(f"Extracted features for {len(audio_files)} files.")
```

**Feature interpretation guide:**

| Feature | Social science meaning |
|---------|----------------------|
| `rms_energy_mean` | Average loudness — higher in aroused/passionate speech |
| `f0_mean_hz` | Average pitch — varies by gender, emotion, language variety |
| `f0_std_hz` | Pitch variation — higher in expressive / emotional speech |
| `f0_range_hz` | Pitch range — monotone speeches have low range |
| `pause_ratio` | Proportion of silence — higher in hesitant / deliberative speech |
| `bpm` | Rhythmic tempo — for music; also proxy for speech rate in some contexts |
| `mfcc_0_mean` | Log energy — overall loudness level |
| `mfcc_1–12_mean` | Timbre / vocal quality — discriminates speakers, dialects |
| `spectral_centroid_mean` | Brightness — higher in excited/high-energy speech |
| `scale` (major/minor) | Music mood marker — minor keys associated with negative valence |
| `mood_happy_prob` | Essentia pre-trained mood probability (music) |

---

### Step 5 — LLM-Native Audio Analysis

Modern LLMs can process audio directly, enabling semantic understanding beyond transcription — tone, intent, rhetorical structure, emotional affect, topic identification.

**Option A — Google Gemini 1.5 Pro (best native audio understanding)**

```python
import google.generativeai as genai
import json, time, pandas as pd
from pathlib import Path

genai.configure(api_key="YOUR_GEMINI_API_KEY")  # set GOOGLE_API_KEY in env
model = genai.GenerativeModel("gemini-1.5-pro")

# ── Upload audio file to Gemini Files API (handles files up to 2GB) ──
def upload_audio(path: str) -> genai.types.File:
    """Upload once; reuse across multiple prompts (files expire after 48h)."""
    audio_file = genai.upload_file(path=path,
                                    display_name=Path(path).stem)
    # Wait for processing
    while audio_file.state.name == "PROCESSING":
        time.sleep(2)
        audio_file = genai.get_file(audio_file.name)
    if audio_file.state.name == "FAILED":
        raise ValueError(f"File upload failed: {path}")
    return audio_file

# ── Structured audio coding (e.g., political speech analysis) ────────
AUDIO_CODING_SYSTEM = """You are a social science research assistant coding political speeches.
For each audio segment, analyze:
1. Dominant rhetorical frame (economic / security / humanitarian / cultural / other)
2. Emotional tone (positive / negative / neutral / mixed)
3. Primary target audience (supporters / opponents / undecided / general public)
4. Key policy domain mentioned (immigration / economy / healthcare / education / other)
5. Confidence: high / medium / low

Respond ONLY with valid JSON:
{"frame": "...", "tone": "...", "target_audience": "...", "policy_domain": "...",
 "confidence": "...", "rationale": "one sentence"}"""

def analyze_audio_llm(audio_file: genai.types.File,
                       prompt: str = "Analyze this audio clip.") -> dict:
    """Send audio file reference + prompt to Gemini; return structured result."""
    response = model.generate_content(
        [audio_file, prompt],
        generation_config = genai.GenerationConfig(
            temperature     = 0,      # deterministic for replicability
            response_mime_type = "application/json"
        )
    )
    return json.loads(response.text)

# ── Batch analysis pipeline ──────────────────────────────────────────
audio_files = list(Path("data/audio/").glob("*.wav"))
results     = []
for fp in audio_files:
    try:
        uploaded = upload_audio(str(fp))
        result   = analyze_audio_llm(
            uploaded,
            prompt = f"System: {AUDIO_CODING_SYSTEM}\n\nAnalyze this audio clip."
        )
        results.append({"file": fp.name, **result})
        time.sleep(1)   # respect rate limits
    except Exception as e:
        results.append({"file": fp.name, "error": str(e)})

pd.DataFrame(results).to_csv("${OUTPUT_ROOT}/tables/audio-llm-coding-gemini.csv", index=False)

# ── Content summary / thematic extraction ─────────────────────────────
def summarize_audio(audio_file: genai.types.File,
                     research_question: str) -> str:
    """Extract key themes relevant to a specific research question."""
    prompt = f"""Listen to this audio carefully.

Research question: {research_question}

Please provide:
1. A 2-3 sentence summary of the main content
2. Key themes or arguments relevant to the research question (bullet list)
3. Any notable rhetorical devices, emotional appeals, or framing strategies
4. Approximate duration breakdown: what proportion is spent on each major theme?

Be specific and quote key phrases when relevant."""
    response = model.generate_content(
        [audio_file, prompt],
        generation_config = genai.GenerationConfig(temperature=0)
    )
    return response.text
```

**Option B — GPT-4o Audio (OpenAI)**

```python
import openai, base64, json, os
client = openai.OpenAI()

# Model selection: set OPENAI_AUDIO_MODEL env var or change default
# Audio-capable models: "gpt-4o-audio-preview", "gpt-5", "gpt-5-mini"
OPENAI_AUDIO_MODEL = os.getenv("OPENAI_AUDIO_MODEL", "gpt-4o-audio-preview")

def encode_audio_b64(path: str) -> str:
    with open(path, "rb") as f:
        return base64.b64encode(f.read()).decode("utf-8")

def analyze_audio_openai(audio_path: str, prompt: str,
                          model: str = None) -> dict:
    model = model or OPENAI_AUDIO_MODEL
    """
    Send audio directly to GPT-4o audio model.
    Supports WAV / MP3 / M4A (max ~25MB per file).
    ⚠ Data transmitted to OpenAI servers — do not use for sensitive audio.
    """
    audio_b64  = encode_audio_b64(audio_path)
    ext        = audio_path.rsplit(".", 1)[-1].lower()
    mime_types = {"wav": "audio/wav", "mp3": "audio/mpeg",
                  "m4a": "audio/mp4", "ogg": "audio/ogg"}
    response = client.chat.completions.create(
        model    = model,
        messages = [{
            "role": "user",
            "content": [
                {"type": "input_audio",
                 "input_audio": {"data": audio_b64,
                                  "format": ext}},
                {"type": "text",
                 "text": prompt}
            ]
        }],
        temperature = 0
    )
    return {"response": response.choices[0].message.content,
            "model":    model,
            "file":     audio_path}

# ── Example: debate turn-by-turn analysis ────────────────────────────
DEBATE_PROMPT = """Analyze this debate clip. Identify:
1. Speaker A and Speaker B's main argument (one sentence each)
2. Which speaker uses more emotional appeal vs. factual evidence?
3. Any logical fallacies present?
4. Who appears more confident / authoritative based on delivery?
Respond as JSON: {"speaker_a_arg":"...", "speaker_b_arg":"...",
"emotional_vs_factual":"...", "fallacies":"...", "confidence_winner":"..."}"""
```

**Option C — Claude via transcription + analysis (privacy-safe for sensitive content)**

For audio that cannot be sent to third-party cloud APIs, transcribe locally with `faster-whisper` then analyze the transcript with Claude:

```python
import anthropic, json
client = anthropic.Anthropic()

def analyze_transcript_claude(transcript: str, coding_prompt: str,
                               model: str = "claude-sonnet-4-6") -> dict:
    """Analyze a locally-produced transcript. Audio never leaves the machine."""
    msg = client.messages.create(
        model      = model,
        max_tokens = 500,
        temperature= 0,
        system     = coding_prompt,
        messages   = [{"role": "user",
                       "content": f"Transcript:\n{transcript[:6000]}"}]
    )
    try:
        return json.loads(msg.content[0].text)
    except json.JSONDecodeError:
        return {"raw_response": msg.content[0].text}
```

**LLM audio analysis — required documentation (Lin & Zhang 2025 risk framework):**
- Validity: pilot on 20 clips; inspect rationale field
- Reliability: temperature=0; re-run 10% sample; report run-to-run agreement κ
- Replicability: record model + version + date; archive exact prompt
- Transparency: report what audio content was analyzed and how clips were selected

---

### Step 6 — Audio Classification (PANNs, AudioCLIP, wav2vec2)

```python
# ── PANNs: Pretrained Audio Neural Networks (sound event detection) ──
# Best for: classifying non-speech audio (environmental sounds, music events,
# crowd noise, protest sounds, nature sounds)
# pip install panns-inference

from panns_inference import AudioTagging
import numpy as np, librosa, pandas as pd

at = AudioTagging(checkpoint_path=None, device="cpu")  # auto-downloads CNN14 weights

def classify_audio_panns(audio_path: str, top_k: int = 10) -> list[dict]:
    """Classify audio into AudioSet classes (527 categories) with probabilities."""
    y, _  = librosa.load(audio_path, sr=32000, mono=True)
    y_in  = y[np.newaxis, :]            # shape: (1, T)
    _, probs = at.inference(y_in)        # probs shape: (1, 527)
    labels = at.labels                   # list of 527 AudioSet class names
    top_idx = probs[0].argsort()[::-1][:top_k]
    return [{"label": labels[i], "prob": round(float(probs[0][i]), 4)}
            for i in top_idx]

# ── wav2vec2: speech features and emotion detection ─────────────────
# Best for: speech-specific tasks — speaker verification, emotion, accent
# pip install transformers
from transformers import (Wav2Vec2Processor, Wav2Vec2ForSequenceClassification,
                           pipeline)
import torch, librosa

# Pre-trained emotion recognition from speech (categorical: anger, joy, sadness...)
emotion_pipe = pipeline(
    "audio-classification",
    model    = "ehcalabres/wav2vec2-lg-xlsr-en-speech-emotion-recognition",
    device   = 0 if torch.cuda.is_available() else -1
)

def classify_emotion_speech(audio_path: str, top_k: int = 4) -> list[dict]:
    """Classify emotion from speech using wav2vec2 fine-tuned on emotion data."""
    y, sr = librosa.load(audio_path, sr=16000, mono=True)
    # HuggingFace audio pipeline expects raw array
    result = emotion_pipe({"array": y, "sampling_rate": sr}, top_k=top_k)
    return result  # list of {"label": "...", "score": ...}

# ── AudioCLIP: zero-shot audio-text matching ─────────────────────────
# Best for: flexible zero-shot classification using text descriptions
# pip install git+https://github.com/AndreyGuzhov/AudioCLIP
# AudioCLIP maps audio and text into shared embedding space (like CLIP for images)
# Useful when you want to search for specific sound events with natural language

# Example: does this clip contain "crowd chanting", "police sirens", "gunshots"?
AUDIO_TEXT_QUERIES = [
    "crowd chanting political slogans",
    "police sirens and crowd control sounds",
    "peaceful public assembly",
    "violent confrontation with screaming",
    "speech from a podium with applause"
]
# Use cosine similarity between audio embedding and text embeddings
# (requires AudioCLIP model weights download — see github.com/AndreyGuzhov/AudioCLIP)

# ── Batch classification pipeline ────────────────────────────────────
audio_files = list(Path("data/audio/").glob("*.wav"))
panns_results   = []
emotion_results = []

for fp in audio_files:
    # PANNs sound event classification
    tags = classify_audio_panns(str(fp), top_k=5)
    panns_results.append({"file": fp.name,
                           **{f"top{i+1}_label": t["label"],
                              f"top{i+1}_prob":  t["prob"]
                              for i, t in enumerate(tags)}})
    # Speech emotion
    emotions = classify_emotion_speech(str(fp), top_k=3)
    emotion_results.append({"file": fp.name,
                             **{f"emotion_{e['label']}": round(e["score"], 4)
                                for e in emotions}})

pd.DataFrame(panns_results ).to_csv("${OUTPUT_ROOT}/tables/audio-panns-classification.csv",  index=False)
pd.DataFrame(emotion_results).to_csv("${OUTPUT_ROOT}/tables/audio-emotion-classification.csv", index=False)
```

**Social science use cases:**
- **Protest audio**: PANNs to classify crowd chanting, sirens, gunshots → measure event escalation
- **Oral history**: wav2vec2 emotion to code narrator affect across life-course episodes
- **Political speeches**: prosodic features (F0, pause ratio) + wav2vec2 emotion + LLM frame coding
- **Broadcast news**: PANNs for background sound events + Whisper transcription + STM on transcripts
- **Music as culture**: Essentia BPM + key + mood across genres, eras, or demographic groups

---

### Step 7 — Post-Transcription Text Analysis (Route to MODULE 1)

Once audio is transcribed, apply the full MODULE 1 NLP pipeline to the transcript corpus:

```python
import pandas as pd

# Load transcript corpus
trans_df = pd.read_csv("${OUTPUT_ROOT}/tables/transcripts.csv")
# Each row = one audio file; trans_df["transcript"] = full text

# ── Option A: STM with metadata covariates ────────────────────────────
# Add document-level metadata (speaker identity, date, party, region, etc.)
# Then run MODULE 1 Step 3 with:
#   prevalence = ~ speaker_party + s(year)
# → Which topics vary by party? Which topics are increasing over time?

# ── Option B: Embedding regression (conText) ─────────────────────────
# Test how the meaning of key policy terms varies across speakers/groups
# Run MODULE 1 Step 6 on the transcript corpus

# ── Option C: LLM annotation with DSL ────────────────────────────────
# If coding a variable from transcripts:
#   1. Run MODULE 1 Step 7 (LLM annotation) on full corpus
#   2. Expert-code random subsample (N ≥ 200)
#   3. Run MODULE 1 Step 8 (DSL) for bias-corrected downstream regression
#   Predicted_var = "llm_coded_frame"; prediction = "gpt4_pred_frame"

# ── Option D: Speaker-level analysis ─────────────────────────────────
# Merge diarized transcript with features
diarized_df = pd.read_csv("${OUTPUT_ROOT}/tables/transcript-diarized.csv")
speaker_texts = (diarized_df
    .groupby(["file", "speaker"])["text"]
    .apply(lambda x: " ".join(x))
    .reset_index()
    .rename(columns={"text": "speaker_transcript"}))
# Now treat each speaker-turn corpus as a "document" for NLP analysis

# ── Quick sentiment analysis on transcript segments ───────────────────
from transformers import pipeline as hf_pipeline
sentiment_pipe = hf_pipeline("sentiment-analysis",
                               model="cardiffnlp/twitter-roberta-base-sentiment-latest",
                               device=-1)

def batch_sentiment(texts: list[str], batch_size: int = 32) -> list[dict]:
    results = []
    for i in range(0, len(texts), batch_size):
        batch = texts[i:i+batch_size]
        # Truncate to 512 tokens
        batch = [t[:1500] for t in batch]
        results.extend(sentiment_pipe(batch, truncation=True, max_length=512))
    return results

trans_df["sentiment"] = batch_sentiment(trans_df["transcript"].tolist())
trans_df.to_csv("${OUTPUT_ROOT}/tables/transcripts-with-sentiment.csv", index=False)
```

**Downstream analyses integrating audio + text features:**

```python
# Merge acoustic features with transcript-derived variables for regression
acoustic_df  = pd.read_csv("${OUTPUT_ROOT}/tables/audio-prosodic-features.csv")
emotion_df   = pd.read_csv("${OUTPUT_ROOT}/tables/audio-emotion-classification.csv")
llm_codes_df = pd.read_csv("${OUTPUT_ROOT}/tables/audio-llm-coding-gemini.csv")
trans_df     = pd.read_csv("${OUTPUT_ROOT}/tables/transcripts-with-sentiment.csv")

# Merge on filename
merged = (trans_df
    .merge(acoustic_df,  on="file", suffixes=("", "_acoustic"))
    .merge(emotion_df,   on="file")
    .merge(llm_codes_df, on="file"))

merged.to_csv("${OUTPUT_ROOT}/tables/audio-features-merged.csv", index=False)

# Example regression: does high F0 range (expressive pitch) predict
# audience engagement (measured by applause events via PANNs)?
# → Use scholar-analyze for this step
```

---

### Step 8 — Audio Verification Subagent

Launch a verification subagent (`subagent_type: general-purpose`) after completing Steps 2–7.

```
AUDIO VERIFICATION REPORT
==========================

PRIVACY / ETHICS GATE
[ ] IRB protocol reviewed for audio data
[ ] Sensitive audio (identifiable voices) processed locally (faster-whisper offline)
[ ] Cloud API use (Whisper API, Gemini, GPT-4o) documented; data type justified
[ ] scholar-safety scan run before processing if audio contains PII/PHI

PREPROCESSING
[ ] Sample rate documented (16kHz for ASR; 22050 or 44100 for Essentia)
[ ] Stereo → mono conversion performed
[ ] Audio format conversion documented (mp3/m4a → wav where required)
[ ] Segment boundaries (silence threshold) documented if used

TRANSCRIPTION (if used)
[ ] Whisper model size documented ("large-v3" recommended for publication)
[ ] Language specified (or auto-detection result reported)
[ ] Confidence filter applied (low no_speech_prob; avg_log_prob threshold documented)
[ ] Word-level timestamps retained for alignment
[ ] Transcription saved to output/[slug]/tables/transcripts.csv

SPEAKER DIARIZATION (if used)
[ ] pyannote version and model (speaker-diarization-3.1) documented
[ ] num_speakers specified or auto-detect result reported
[ ] Alignment method (overlap-majority) documented
[ ] Speaker statistics (speaking time, turns) saved

ESSENTIA / librosa FEATURES
[ ] Sample rate consistent across all files
[ ] Frame size + hop size documented
[ ] MFCC coefficients: n=40 documented
[ ] Mood/emotion models: model filename + source URL documented
[ ] Feature CSV saved to output/[slug]/tables/audio-low-level-features.csv

LLM AUDIO ANALYSIS (if used, Lin & Zhang 2025 framework)
[ ] Validity: pilot on ≥20 clips; rationale inspected
[ ] Reliability: run-to-run κ on 10% subsample; temperature=0 used
[ ] Replicability: model + version + annotation date archived; prompt verbatim
[ ] Transparency: prompt and sampling strategy reproduced in supplementary
[ ] Cloud API used (Gemini/GPT-4o): document data type (public/private); privacy justified

AUDIO CLASSIFICATION (if used)
[ ] PANNs / wav2vec2 / AudioCLIP model checkpoint documented
[ ] Human validation: ≥50 clips human-coded; κ vs. model labels ≥ 0.70
[ ] Confusion matrix saved

POST-TRANSCRIPTION NLP (if used)
[ ] MODULE 1 verification subagent run on transcript corpus
[ ] DSL used if LLM annotations feed into downstream regression

REPRODUCIBILITY
[ ] Whisper model version pinned (faster-whisper==X.X; model="large-v3")
[ ] Essentia version documented (essentia==X.X)
[ ] All output files inventoried in compute log

RESULT: [PASS / NEEDS REVISION]
Issues: [list]
```

**Reporting template:**
> "We collected [N] audio files ([describe source: broadcast news / debate recordings / oral history interviews]; total duration: [X] hours). Audio files were converted to 16kHz mono WAV using `pydub`. We transcribed all files locally using `faster-whisper` (model: `large-v3`; Radford et al. 2023) to avoid transmitting sensitive audio to external servers. Speaker attribution was performed using `pyannote.audio` (speaker-diarization-3.1; Bredin et al. 2023). Low-level acoustic features — including 40 MFCCs, spectral centroid, RMS energy, BPM, and pitch (F0) via `pyin` — were extracted using `Essentia` (Bogdanov et al. 2013) and `librosa` (McFee et al. 2015) at a frame size of 2,048 samples and hop size of 512 (22,050 Hz). [If mood models:] Pre-trained mood classification used the Discogs-EffNet model from Essentia's model repository. [If LLM analysis:] We coded [N] audio clips for [construct] using [Gemini 1.5 Pro / GPT-4o; annotation date: YYYY-MM-DD; temperature = 0]. Coding validity was confirmed on a 20-clip pilot; run-to-run reliability κ = [X] on a 10% subsample. The full system prompt is reproduced in the Online Appendix. Transcripts were then analyzed using [MODULE 1 method] (see Section [X])."

---

## Quality Checklist

- [ ] Module routing: correct module(s) identified from `$ARGUMENTS`
- [ ] **Causal gate**: causal design detected → `/scholar-causal` invoked (or DML/Causal Forest confirmed as estimator)
- [ ] MODULE 0 setup: output directories created; seeds set
- [ ] Appropriate method chosen for research goal (inferential vs. predictive vs. descriptive)
- [ ] Per-module verification subagent run — PASS confirmed (or all issues fixed)
- [ ] All model objects saved to `output/[slug]/models/`
- [ ] All figures saved as PDF + PNG to `output/[slug]/figures/` (colorblind-safe palette)
- [ ] All tables saved to `output/[slug]/tables/`
- [ ] Random seeds reported in Methods section
- [ ] Human validation conducted for automated annotation (κ ≥ 0.70)
- [ ] Performance reported on held-out test set only (not train set)
- [ ] **MODULE 6 (CV)**: κ ≥ 0.70 on 200-image human-coded benchmark; model name + date archived
- [ ] **MODULE 7 (LLM Analysis)**: all four Lin & Zhang (2025) epistemic risks assessed; temperature=0; prompts archived
- [ ] **MODULE 8 (Synthetic Data)**: use case appropriate gate passed; validation vs. real human data run; KS/JSD reported; prompts archived
- [ ] **MODULE 9 (Geospatial)**: Moran's I diagnostic run on OLS residuals; LM tests guide SAR/SEM selection; ρ or λ reported with direct/indirect impacts; LISA map saved; CRS documented
- [ ] **DSL (if used)**: expert sample is random; N expert labels ≥ 200; bias-corrected estimates compared to naive regression; results saved
- [ ] **Bayesian brms (if used)**: Rhat ≤ 1.01; ESS > 400; pp_check saved; priors documented; LOO-CV for model comparison
- [ ] **Conformal prediction (if used)**: calibration set held out; empirical coverage matches nominal (±2%); set size / interval width reported; conditional coverage by subgroup checked
- [ ] **BERTopic (if used)**: outlier % reported; human validation ≥20 docs/topic; dynamic/hierarchical figures saved
- [ ] **Text scaling (if used)**: anchor documents justified; external validation reported
- [ ] **Multilingual NLP (if used)**: language detection run; per-language F1 on human-coded sample; multilingual embedding model documented
- [ ] **GNN / Node embedding (if used)**: method specified; test F1 / AUC-ROC reported; baseline comparison included; embeddings saved
- [ ] **Multimodal fusion (if used)**: fusion strategy documented; unimodal baselines compared; multimodal F1 on test set reported
- [ ] **MODULE 10 (Audio, if used)**: privacy gate passed (local faster-whisper for sensitive data); Whisper model + version documented; Essentia feature CSV saved; LLM audio analysis: all four Lin & Zhang (2025) epistemic risks assessed; classification (PANNs/wav2vec2) κ ≥ 0.70 vs. human benchmark; post-transcription NLP routed to MODULE 1
- [ ] **Scripts saved** for all code executed in each module to `output/[slug]/scripts/` (Script Archive Protocol)
- [ ] **Coding decisions log** updated with method selection, parameter choices, validation approach, preprocessing decisions
- [ ] **Script index** updated with rows for all module scripts + paper-element correspondence
- [ ] **Internal log saved** (`scholar-compute-log-[topic]-[date].md`)
- [ ] **Publication-ready results saved** (`scholar-compute-results-[topic]-[date].md`)

---

## Save Output

Use the Write tool to save **two separate files** after completing all modules.

---

### File 1 — Internal Compute Log

**Filename:** `scholar-compute-log-[topic-slug]-[YYYY-MM-DD].md`

**Purpose:** Technical record for your own reference — module decisions, parameter choices, verification results, file inventory. Not for submission.

**Template:**
```markdown
# Compute Log: [Topic] — [YYYY-MM-DD]

## Module(s) Run
[text / ml / network / abm / cv / llm-analysis / synthetic-data / reproduce / geospatial / audio]

## Data
- Source: [file path / URL / package + dataset + citation]
- N documents / nodes / events / images / agents: [X]
- Time period: [X–Y]
- Exclusions: [reason and N excluded]

## Computational Decisions
- Module: [MODULE 1 / 2 / 3 / 4 / 5 / 6 / 7 / 8 / 9 / 10]
- Method: [STM / BERTopic / Wordfish / conText / LLM annotation / DSL / BERT / Multilingual NLP / ERGM / REM / GNN / node2vec / GCN / GraphSAGE / DML / Causal Forest / brms / Conformal Prediction / ABM / CV / Multimodal Fusion / RAG / Synthetic / Spatial Lag / Spatial Error / Whisper / Essentia / PANNs / AudioCLIP / wav2vec2]
- Key parameters: [K=[X]; window=[X]; clusters=[X]; n_estimators=[X]; etc.]
- Random seed: 42 (set in all stochastic steps)
- Causal design: [/scholar-causal invoked: yes/no; strategy: DML / Causal Forest / none]
- Validation approach: [human κ benchmark / train-test split / GOF / ODD / SALib / etc.]

## Verification Results
- [Module] Verification Subagent: [PASS / issues fixed: ...]
- [Module] Verification Subagent: [PASS / issues fixed: ...]

## Key Results (Quick Reference)
| Method | Key statistic | Value |
|--------|--------------|-------|
| [STM]  | N topics (K); top topic label | [X]; "[label]" |
| [BERT] | Test F1 (macro); AUC-ROC | [X]; [X] |
| [conText] | Normed β for [covariate] | [X] (95% CI [lo, hi]) |
| [LLM] | κ vs. human (N=[X]) | [X] |
| [ERGM] | Homophily coef (nodematch) | [β] (SE=[SE]) |
| [REM]  | Inertia coef | [β] (SE=[SE]) |
| [DML]  | ATE (95% CI) | [X] ([lo], [hi]) |
| [ABM]  | Key outcome at baseline params | [X] |
| [CV]   | κ vs. human; F1 (macro) | [X]; [X] |
| [Synth] | KS stat vs. real data; JSD | [X]; [X] |
| [Synth] | Mean diff (synthetic − real) per key variable | [Δ] |
| [Spatial lag] | ρ (SE); Moran's I before/after | [ρ] ([SE]); [before] → [after] |
| [Spatial error] | λ (SE); Moran's I before/after | [λ] ([SE]); [before] → [after] |
| [DSL]   | β for predicted_var (bias-corrected vs. naive) | [β_dsl] vs. [β_naive] |
| [brms]  | Posterior mean + 95% CI; Rhat | [X] ([lo], [hi]); ≤1.01 |
| [BERTopic] | K topics; % outlier docs | [K]; [X]% |
| [Wordfish] | θ range; Moran correlation with [external criterion] | [[min],[max]]; r=[X] |
| [Multilingual] | Languages; per-language F1; embedding model | [K] langs; en=[X], es=[X]; [model] |
| [GNN/node2vec] | Test F1 (node classif.) or AUC (link pred.); embedding dim | [X]; d=[X] |
| [Conformal] | Empirical coverage; avg set size / interval width | [X]%; [X] |
| [Multimodal] | Fused F1 vs. text-only vs. image-only | [X] vs. [X] vs. [X] |
| [Audio/Whisper] | N files; total hours; WER (if known) | [N]; [X] hrs; [X]% |
| [Audio/Essentia] | N features extracted; MFCCs + rhythm + mood | [X] features / file |
| [Audio/LLM] | κ vs. human (N=[X]); Lin & Zhang risks cleared | [X]; [list] |
| [Audio/PANNs] | Top AudioSet class(es); κ vs. human | [label] ([prob]); [X] |
| ...    |              |       |

## Robustness Summary
- Alternative spec / K / threshold: [key stat] vs. main [key stat] — [holds / attenuates]
- Alternative sample: [key stat] vs. main [key stat] — [holds / attenuates]
- Parameter sweep (ABM): outcome range across param space — [stable / sensitive to X]

## File Inventory
output/[slug]/models/[list all saved model files]
output/[slug]/tables/[list all saved table files]
output/[slug]/figures/[list all saved figure files]

## Script Archive
output/[slug]/scripts/coding-decisions-log.md
output/[slug]/scripts/script-index.md
output/[slug]/scripts/[list all saved scripts, e.g.:]
  20-stm-topic-model.R
  21-conText-embedding.R
  [... etc.]
```

---

### File 2 — Publication-Ready Methods + Results Document

**Filename:** `scholar-compute-results-[topic-slug]-[YYYY-MM-DD].md`

**Purpose:** Drop-in material for the manuscript. Contains the complete Data and Methods section prose, Results prose, table notes, and figure captions — all formatted for the target journal. Ready to paste into `/scholar-write`. Replace every placeholder with actual values before saving. No brackets should remain in the final file.

**Template — fill every placeholder with actual values before saving:**
```markdown
# Methods and Results: [Paper Title or Topic]
*Target journal: [NCS / Science Advances / ASR / AJS / Demography]*
*Word count: ~[XXX] words (target: [journal limit])*

---

## Data and Computational Methods

[¶1 — DATA]
[Describe corpus / network / dataset / image collection: source, collection method or
sampling frame, N (raw and analytic), time period, filtering/exclusion criteria,
access restrictions or data availability. For text: describe corpus composition.
For networks: N nodes, N edges, density, directed/undirected. For images: N images,
collection method, any filtering.] All analyses used R [version] / Python [version];
code and data are available at [repo URL / DOI].

[¶2 — COMPUTATIONAL METHOD]
[Describe the method in enough detail for replication. Include: full method name and
citation (e.g., "Structural Topic Model; Roberts et al. 2019"); software package +
version; key parameters (K, window, n_estimators, etc.); random seed (42 for all
stochastic steps). For LLM annotation: model name + version + annotation date +
temperature setting. For CV: model architecture + pretrained checkpoint + preprocessing.
For ABM: ODD reference + parameter table. For REM: package (goldfish / relevent) +
endogenous statistics included.]

[¶3 — VALIDATION]
[Describe validation procedure. For supervised ML/CV: train/val/test split (proportions
and N); CV folds. For LLM/CV annotation: human benchmark — N images/documents,
annotator description, κ vs. human labels. For ERGM: MCMC convergence and GOF results.
For ABM: pattern-oriented validation (≥2 empirical patterns matched). For DML:
nuisance model specifications; cross-fitting folds.]

---

## Results

[¶4 — MAIN COMPUTATIONAL FINDINGS]
[State the primary finding with key statistics. Use the appropriate reporting format for
the method:
- STM: topic prevalence by covariate (effect = [X], 95% CI = [[lo],[hi]]), reference Figure X
- BERT/CV: F1 (macro) = [X], AUC = [X]; highest-importance feature [name] (SHAP = [X])
- conText: normed β for [party/group] = [X] (95% CI = [[lo],[hi]]), NNS comparison in Figure X
- ERGM: log-odds for nodematch([race]) = [β] (SE = [SE]); GOF confirmed
- REM: inertia coef = [β] (SE = [SE]); LRT χ² = [X], df = [X], p = [p]
- DML: ATE = [X], 95% CI = [[lo],[hi]]; nuisance model AUC = [X]
- ABM: at threshold=[X], [X]% of agents reach stable state after [T] steps
- CV: κ (human benchmark, N=[X]) = [X]; test F1 (macro) = [X]
- Spatial lag: ρ = [X] (SE = [SE]); direct effect [covariate] = [X]; indirect spillover = [X]
- Spatial error: λ = [X] (SE = [SE]); Moran's I on residuals → [X] (p = [p])
- DSL: β(predicted_var) = [X] (95% CI = [[lo],[hi]]); naive approach yielded [direction] bias
- brms: posterior mean = [X] (95% CI = [[lo],[hi]]); Rhat = [X]; pp_check passed
- BERTopic: K = [X] topics ([X]% outlier); topic [N] ("[label]") shows [dynamic trend]
- Wordfish: θ range = [[min],[max]]; [reference] positions corroborate external criterion (r = [X])
- Multilingual NLP: cross-lingual transfer F1 = [X] (English), [X] ([target lang]); K = [X] multilingual topics
- GNN: test F1 (macro) = [X] (node classification); AUC-ROC = [X] (link prediction); embedding dim = [d]
- Conformal: empirical coverage = [X]% (nominal = [X]%); avg prediction [set size = [X] / interval width = [X]]
- Multimodal fusion: F1 (macro) = [X] (fused) vs. [X] (text-only) vs. [X] (image-only); fusion = [late / early / CLIP]
- Audio/Whisper: N = [X] files ([X] hrs); Whisper large-v3; mean WER = [X]%
- Audio/Essentia: [X] low-level features extracted per file; mean BPM = [X]; top mood = [label] (prob = [X])
- Audio/LLM (Gemini/GPT-4o): κ vs. human = [X] (N = [X] files); top coded theme = "[label]"
- Audio/PANNs: dominant AudioSet class = "[label]" (mean prob = [X]); κ vs. human = [X]
Reference tables and figures inline: (Table 2); (Figure 3).]

[¶5 — HETEROGENEITY / SUBGROUP ANALYSIS]
[If applicable: group differences in topic prevalence; CATE variation by subgroup;
community-level differences in network position; parameter sensitivity in ABM;
per-category F1 variation in supervised learning.]

[¶6 — ROBUSTNESS]
[Describe how core findings were validated: alternative K or threshold; alternative
model specification; parameter sweep range; held-out test set; human validation.
State whether results hold or attenuate under each check.]

---

## Table Notes

**Table 1. [Descriptive Statistics / Network Summary / Data Overview]**
*Note.* [Describe what is shown: means/SDs, or N/%, or network statistics.
State sample, time period, and any weighting.] N = [X].

**Table 2. [Method Results: e.g., STM Covariate Effects / ERGM Coefficients / Model Performance]**
*Note.* [Software package + version. Key model parameters. SE type or CI method.
Random seed = 42.] [Significance: * p < .05, ** p < .01, *** p < .001 where applicable.]
N = [X].

**Table A1. [Robustness / Sensitivity / Alternative Specification]**
*Note.* Column 1 replicates the main model (Table 2). Column 2 [description of change].
Column 3 [description]. [SE / CI method.] * p < .05, ** p < .01, *** p < .001.

---

## Figure Captions

**Figure 1. [Descriptive title: what is shown, for what data, with what method]**
[Self-explanatory caption: state what each axis/color/size/shape encodes.
Error bars = [95% CI / SE / bootstrapped interval]. Software: [R/Python package + version].
Data source: [X]. N = [X].]

**Figure 2. [Title]**
[Caption.] [Error bars = 95% CI.] N = [X].

[Add one caption block per figure generated in the modules above.]
```

---

Confirm both file paths to user at end of run.

**Close Process Log:**

Run the following to finalize the process log:

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
SKILL_NAME="scholar-compute"
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

---

See [references/nlp-pipeline.md](references/nlp-pipeline.md) for full STM, BERT, conText, LLM annotation workflows, and the Lin & Zhang (2025) four-risk checklist.
See [references/ml-methods.md](references/ml-methods.md) for DML, SHAP, and hyperparameter tuning.
See [references/network-analysis.md](references/network-analysis.md) for ERGM, RSiena, and relational event model reference code.
See [references/computer-vision.md](references/computer-vision.md) for full CV reference code (DINOv2, CLIP, ConvNeXt, ViT, VideoMAE, multimodal LLM annotation, social science use cases).
See [references/synthetic-data.md](references/synthetic-data.md) for full silicon sampling workflow, persona libraries, validation code, and known limitations of LLM synthetic data.
