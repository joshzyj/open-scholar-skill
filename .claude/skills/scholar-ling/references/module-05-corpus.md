## MODULE 5: CORPUS AND DISCOURSE ANALYSIS

### Corpus Building and Design

**Design principles**:
- Define inclusion criteria (genre, time period, source, language, register)
- Document: token count, type count, type-token ratio, metadata schema
- Balance corpus if comparing groups (same genre, same N words per group)
- Diachronic analysis: control genre across time periods

**R: quanteda pipeline**:

```r
library(quanteda); library(quanteda.textstats); library(quanteda.textplots)

corp <- corpus(df, text_field = "text",
               docvars = df[, c("year", "source", "group")])
toks <- tokens(corp, remove_punct = TRUE, remove_numbers = TRUE) |>
  tokens_tolower() |>
  tokens_remove(stopwords("en"))
dfmat <- dfm(toks) |> dfm_trim(min_termfreq = 5)

# Descriptive statistics
textstat_summary(corp)                          # sentence count, token count
textstat_lexdiv(dfmat, measure = "TTR")         # lexical diversity
textstat_readability(corp, measure = c("Flesch","Dale.Chall"))  # readability
```

**Python: spaCy pipeline**:

```python
import spacy, pandas as pd
nlp = spacy.load("en_core_web_sm")

def parse_text(text):
    doc = nlp(text)
    return {"n_tokens": len(doc), "n_sents": len(list(doc.sents)),
            "nouns":  [t.lemma_ for t in doc if t.pos_ == "NOUN"],
            "verbs":  [t.lemma_ for t in doc if t.pos_ == "VERB"]}

df["parsed"] = df["text"].apply(parse_text)
```

---

### Keyness Analysis

```r
# Compare target corpus vs. reference corpus
dfm_grouped <- dfm_group(dfmat, groups = docvars(dfmat, "corpus_type"))
tstat_key   <- textstat_keyness(dfm_grouped, target = "political",
                                measure = "lr")   # G² (log-likelihood; preferred)

textplot_keyness(tstat_key, n = 20L,
                 labelsize = 3, color = c("#E69F00","#0072B2"))
ggsave("${OUTPUT_ROOT}/ling/figures/fig-keyness.pdf", device = cairo_pdf,
       width = 7, height = 5)
ggsave("${OUTPUT_ROOT}/ling/figures/fig-keyness.png", dpi = 300, width = 7, height = 5)

# Export table
write.csv(head(tstat_key, 50), "${OUTPUT_ROOT}/ling/tables/keyness-top50.csv")
```

**Keyness thresholds**: G² > 3.84 (df=1, p < .05); G² > 10.83 (p < .001)

---

### Collocation and KWIC Analysis

```r
# Collocations
col       <- tokens_select(toks, pattern = "immigrant*", padding = TRUE)
col_stats <- textstat_collocations(col, size = 2:3, min_count = 10)
write.csv(head(col_stats, 30), "${OUTPUT_ROOT}/ling/tables/collocations.csv")

# KWIC export (for manual reading / CDA)
kwic_out <- kwic(toks, pattern = "undocumented*", window = 6)
write.csv(as.data.frame(kwic_out), "${OUTPUT_ROOT}/ling/transcripts/kwic-undocumented.csv")
```

**Semantic prosody**: Does the target word co-occur predominantly with positive or negative evaluative terms?
- Classify top 30 collocates using sentiment lexicon (LIWC, VADER)
- Report: % positive collocates; compare across corpora or time periods

### Advanced Corpus Statistics

**Log-likelihood (Dunning 1993)** — preferred over chi-square for keyword analysis:
```r
library(quanteda.textstats)
# Keyness analysis (log-likelihood)
keyness <- textstat_keyness(dfm_grouped, target = "target_group", measure = "lr")
textplot_keyness(keyness, n = 20)
```

**Effect sizes for corpus comparisons**:
- **Log ratio** (Hardie 2012): ln(normalized_freq_A / normalized_freq_B). >1 = overrepresented in A.
- **%DIFF**: (freq_A - freq_B) / freq_B x 100. Intuitive percentage difference.
- **Mutual information**: Strength of word association in collocations.

```r
# Collocation strength (MI, t-score, log-likelihood)
collocations <- textstat_collocations(tokens_obj, size = 2, min_count = 5)
# Reports: lambda (log-likelihood), z (z-score)
```

**Corpus design guidance**:
- Minimum corpus size: ~1M words for lexical analysis; ~100K for grammatical features
- Balance by genre, register, time period, speaker demographics
- Document sampling: random vs. stratified (by publication, author, date)
- Representativeness: compare corpus composition to population of interest

---

### Structural Topic Models (STM)

Use when: mapping thematic content + testing how topic prevalence varies across social groups or time.

```r
library(stm)

processed <- textProcessor(df$text, metadata = df)
prep      <- prepDocuments(processed$documents, processed$vocab, processed$meta,
                           lower.thresh = 5)

# Fit model (select K via searchK or theoretical justification)
stm_fit <- stm(prep$documents, prep$vocab, K = 15,
               prevalence = ~ s(year) + group,
               data = prep$meta, init.type = "Spectral",
               seed = 42, max.em.its = 75)

# Inspect topics
labelTopics(stm_fit, n = 10)
plot(stm_fit, type = "summary", n = 5)

# Estimate prevalence effect of group on topic use
effects <- estimateEffect(~ group + s(year), stm_fit, meta = prep$meta,
                           uncertainty = "Global")
plot(effects, "group", method = "difference",
     cov.value1 = "Democrat", cov.value2 = "Republican",
     topics = c(1, 3, 7),
     main = "Topic prevalence: Democrat vs. Republican")
ggsave("${OUTPUT_ROOT}/ling/figures/fig-stm-prevalence.pdf",
       device = cairo_pdf, width = 8, height = 5)
```

**Reporting**: Report K selection rationale; top 5–10 words per topic; topic prevalence table; semantic coherence (exclusivity + coherence tradeoff)

---

