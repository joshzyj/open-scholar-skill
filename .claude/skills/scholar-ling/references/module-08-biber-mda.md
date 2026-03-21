## MODULE 8: BIBER MULTI-DIMENSIONAL ANALYSIS (MDA)

Use when $ARGUMENTS contains: `MDA`, `multi-dimensional`, `Biber`, `register`, `67 features`, `dimension scores`, `register comparison`.

### Step 8a: Overview

Biber's (1988) Multi-Dimensional Analysis identifies co-occurring clusters of linguistic features across registers (conversation, academic prose, fiction, etc.) via factor analysis. The framework extracts counts of 67 linguistic features per text, standardizes them, then uses factor analysis to derive interpretable "dimensions" of variation (e.g., Dimension 1: Involved vs. Informational Production).

**The 67 features** (grouped):

| Category | Features (examples) |
|----------|-------------------|
| Tense & aspect | Past tense, perfect aspect, present tense |
| Place & time adverbials | Place adverbs, time adverbs, demonstratives |
| Pronouns & pro-forms | 1st person pronouns, 2nd person pronouns, 3rd person pronouns, `it`, demonstrative pronouns |
| Questions | WH-questions, DO as pro-verb |
| Nominal forms | Nominalizations, gerunds, total nouns |
| Passives | Agentless passives, BY-passives |
| Stative forms | BE as main verb, existential THERE |
| Subordination | THAT-clauses, WH-clauses, infinitives, adverbial subordinators |
| Coordination | Phrasal coordination, independent clause coordination |
| Negation | Analytic negation, synthetic negation |
| Modals | Possibility modals, necessity modals, predictive modals |
| Specialized verb classes | Public verbs, private verbs, suasive verbs, SEEM/APPEAR |
| Adjectives & adverbs | Attributive adjectives, predicative adjectives, total adverbs, hedges, amplifiers, emphatics, downtoners |
| Lexical specificity | Type-token ratio, word length, conjuncts |
| Discourse markers | Discourse particles, sentence relatives |

**Canonical dimensions** (Biber 1988):
1. **Involved vs. Informational Production** (+ private verbs, contractions, 1st/2nd person pronouns vs. + nouns, prepositions, attributive adjectives)
2. **Narrative vs. Non-Narrative Concerns** (+ past tense, 3rd person pronouns, perfect aspect)
3. **Explicit vs. Situation-Dependent Reference** (+ WH-relative clauses, nominalizations vs. time/place adverbs)
4. **Overt Expression of Persuasion** (+ prediction modals, suasive verbs, conditionals)
5. **Abstract vs. Non-Abstract Information** (+ conjuncts, agentless passives, adverbial subordinators)
6. **On-Line Informational Elaboration** (+ THAT-deletion, demonstratives)

---

### Step 8b: Feature Extraction — R (`biber.dim` package)

```r
# install.packages("biber.dim")
library(biber.dim); library(tidyverse)

# Input: data frame with columns 'doc_id' and 'text'
# biber.dim tags each text and returns per-text counts of 67 features
features <- biber_dim(df$text)

# Merge with metadata
feat_df <- bind_cols(df |> select(doc_id, register, year), features)

# Standardize features (per 1000 words, then z-score)
feat_z <- feat_df |>
  mutate(across(where(is.numeric), ~ scale(.)[,1]))

write.csv(feat_df, "${OUTPUT_ROOT}/ling/tables/biber-67-features-raw.csv", row.names = FALSE)
write.csv(feat_z,  "${OUTPUT_ROOT}/ling/tables/biber-67-features-zscore.csv", row.names = FALSE)
```

---

### Step 8c: Feature Extraction — Manual (Python + spaCy)

If `biber.dim` is not available, extract features manually:

```python
import spacy, pandas as pd, numpy as np
nlp = spacy.load("en_core_web_sm")

def extract_biber_features(text):
    doc = nlp(text)
    n_words = len([t for t in doc if not t.is_punct])
    if n_words == 0:
        return {}
    features = {}
    # Tense
    features["past_tense"]    = sum(1 for t in doc if t.tag_ == "VBD") / n_words * 1000
    features["present_tense"] = sum(1 for t in doc if t.tag_ in ("VBP","VBZ")) / n_words * 1000
    # Pronouns
    features["first_person"]  = sum(1 for t in doc if t.lower_ in ("i","me","my","mine","we","us","our","ours")) / n_words * 1000
    features["second_person"] = sum(1 for t in doc if t.lower_ in ("you","your","yours")) / n_words * 1000
    features["third_person"]  = sum(1 for t in doc if t.lower_ in ("he","she","him","her","his","hers","they","them","their","theirs")) / n_words * 1000
    # Nouns, adjectives, adverbs
    features["nouns"]              = sum(1 for t in doc if t.pos_ == "NOUN") / n_words * 1000
    features["attributive_adj"]    = sum(1 for t in doc if t.pos_ == "ADJ" and t.dep_ == "amod") / n_words * 1000
    features["adverbs"]            = sum(1 for t in doc if t.pos_ == "ADV") / n_words * 1000
    # Prepositions
    features["prepositions"]       = sum(1 for t in doc if t.pos_ == "ADP") / n_words * 1000
    # Nominalizations (-tion, -ment, -ness, -ity)
    features["nominalizations"]    = sum(1 for t in doc if t.pos_ == "NOUN" and
                                         any(t.text.lower().endswith(s) for s in ("tion","ment","ness","ity"))) / n_words * 1000
    # Type-token ratio
    types = set(t.lower_ for t in doc if t.is_alpha)
    features["ttr"] = len(types) / n_words if n_words > 0 else 0
    # Word length
    features["avg_word_length"] = np.mean([len(t.text) for t in doc if t.is_alpha])
    # Contractions
    features["contractions"] = sum(1 for t in doc if "'" in t.text and t.pos_ in ("AUX","VERB")) / n_words * 1000
    # ... extend to cover all 67 features as needed
    return features

feat_df = pd.DataFrame([extract_biber_features(t) for t in df["text"]])
feat_df.insert(0, "doc_id", df["doc_id"])
feat_df.to_csv("${OUTPUT_ROOT}/ling/tables/biber-features-manual.csv", index=False)
```

---

### Step 8d: Factor Analysis and Dimension Scores

```r
library(psych); library(ggplot2)

# Select numeric feature columns (z-scored)
feat_mat <- feat_z |> select(where(is.numeric))

# Determine number of factors (parallel analysis)
fa.parallel(feat_mat, fa = "fa", n.iter = 100)

# Fit factor analysis (oblimin rotation; Biber uses promax)
fa_fit <- fa(feat_mat, nfactors = 6, rotate = "promax", fm = "ml")
print(fa_fit, cut = 0.30, sort = TRUE)

# Extract dimension scores per text
dim_scores <- as.data.frame(fa_fit$scores)
colnames(dim_scores) <- paste0("Dim", 1:6)
result <- bind_cols(feat_z |> select(doc_id, register, year), dim_scores)

write.csv(result, "${OUTPUT_ROOT}/ling/tables/biber-dimension-scores.csv", row.names = FALSE)

# Visualize: mean dimension scores by register
result |>
  pivot_longer(starts_with("Dim"), names_to = "dimension", values_to = "score") |>
  ggplot(aes(x = register, y = score, fill = register)) +
  geom_boxplot() +
  facet_wrap(~ dimension, scales = "free_y") +
  theme_Publication() +
  labs(y = "Dimension Score")  # NO title — goes in caption; use theme_Publication()
ggsave("${OUTPUT_ROOT}/ling/figures/fig-biber-dimensions.pdf", device = cairo_pdf,
       width = 10, height = 7)
ggsave("${OUTPUT_ROOT}/ling/figures/fig-biber-dimensions.png", dpi = 300, width = 10, height = 7)
```

---

### Step 8e: Register Comparison

```r
# MANOVA: do registers differ across all dimensions simultaneously?
manova_fit <- manova(cbind(Dim1, Dim2, Dim3, Dim4, Dim5, Dim6) ~ register, data = result)
summary(manova_fit, test = "Pillai")

# Post-hoc: pairwise comparisons per dimension
library(emmeans)
for (d in paste0("Dim", 1:6)) {
  cat("\n===", d, "===\n")
  m <- lm(reformulate("register", d), data = result)
  print(emmeans(m, pairwise ~ register)$contrasts)
}
```

**Key references**: Biber (1988) *Variation across speech and writing*; Biber & Conrad (2009) *Register, genre, and style*; Biber & Gray (2016) *Grammatical complexity in academic English*; Nini (2019) MAT R package.

---

