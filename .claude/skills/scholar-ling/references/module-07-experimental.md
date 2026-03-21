## MODULE 7: EXPERIMENTAL SOCIOLINGUISTICS

Use when $ARGUMENTS contains: `experimental`, `vignette`, `factorial`, `reaction time`, `priming`, `IAT experiment`, `perception`, `Likert`.

### Step 7a: Matched Guise Technique — Extended Designs

The classic MGT (see MODULE 4) presents one bilingual speaker in two guises. Extended experimental designs allow tighter control and richer inference.

**Factorial Vignette Experiments**:
- Fully crossed design: manipulate speaker variety/dialect x social context x topic
- Each participant rates multiple vignettes (within-subjects on vignettes, between-subjects on blocking factors)
- Use fractional factorial if full crossing is too large (D-optimal design via `AlgDesign` R package)

```r
library(AlgDesign); library(lme4); library(marginaleffects)

# Generate fractional factorial design
full <- gen.factorial(levels = c(3, 2, 2),  # 3 dialects x 2 contexts x 2 topics
                      nVars = 3, varNames = c("dialect", "context", "topic"))
frac <- optFederov(~ dialect * context + dialect * topic, data = full,
                   nTrials = 12, criterion = "D")

# Analysis: crossed random effects (participant + vignette)
m_vig <- lmer(rating ~ dialect * context + dialect * topic +
                (1 | participant) + (1 | vignette_id),
              data = vignette_data)
avg_slopes(m_vig, variables = "dialect", by = "context")
```

---

### Step 7b: Implicit Association Test (IAT) for Language Attitudes

Measures automatic (implicit) associations between language varieties and evaluative categories (e.g., Standard English = "pleasant" vs. regional dialect = "unpleasant").

**Design**:
1. Category pairs: Target (Standard vs. Nonstandard audio clips) x Attribute (Pleasant vs. Unpleasant words)
2. 7-block IAT protocol (practice + critical blocks; congruent vs. incongruent pairings)
3. D-score computation: difference in mean RT between incongruent and congruent blocks, divided by pooled SD

**R implementation** (`taat` package or manual D-score):

```r
library(tidyverse)

# Manual D-score calculation (Greenwald, Nosek, & Banaji 2003)
compute_d_score <- function(df) {
  # Remove trials > 10000ms; replace < 300ms with 300ms
  df <- df |>
    filter(rt <= 10000) |>
    mutate(rt = pmax(rt, 300))

  # Blocks 3+4 (congruent practice+critical) vs. 6+7 (incongruent practice+critical)
  congruent   <- df |> filter(block %in% c(3, 4)) |> pull(rt)
  incongruent <- df |> filter(block %in% c(6, 7)) |> pull(rt)

  pooled_sd <- sd(c(congruent, incongruent))
  d_score   <- (mean(incongruent) - mean(congruent)) / pooled_sd
  return(d_score)
}

# Compute per participant; positive D = implicit preference for standard
d_scores <- iat_data |>
  group_by(participant) |>
  summarise(d = compute_d_score(pick(everything())), .groups = "drop")

# Relate D-score to explicit attitudes and demographics
m_iat <- lm(d ~ explicit_attitude + age + gender + own_dialect, data = d_scores)
summary(m_iat)
```

**Key references**: Greenwald, McGhee, & Schwartz (1998); Campbell-Kibler (2012) linguistic IAT; Pantos & Perkins (2012) language attitudes IAT.

---

### Step 7c: Reaction Time Paradigms

**Lexical decision / sentence processing tasks** measuring processing cost for dialect-embedded stimuli.

**Common paradigms**:
- **Lexical decision**: Is the target a word? Faster RT = stronger priming; compare cross-dialect vs. within-dialect prime-target pairs
- **Self-paced reading**: Word-by-word reading time; spillover effects at critical region + 1/+2 words
- **Auditory naming / shadowing**: RT to repeat a word heard in a dialect vs. standard guise
- **Visual world eye-tracking**: Fixation proportions to target vs. competitor as speech unfolds

```r
library(lme4); library(lmerTest); library(emmeans)

# Self-paced reading: log-transform RT; model critical region
m_spr <- lmer(log(rt) ~ dialect_condition * region +
                (1 + dialect_condition | participant) + (1 | item),
              data = spr_data |> filter(region %in% c("critical", "spillover1")))
summary(m_spr)
emmeans(m_spr, pairwise ~ dialect_condition | region)
```

---

### Step 7d: Priming Studies

**Syntactic priming** (Bock 1986): Does hearing a structure in one dialect prime production of that structure?

**Social priming**: Does exposure to a dialect prime associated social categories?

```r
# Priming analysis: mixed logistic regression
# DV = 1 if target structure produced; 0 otherwise
m_prime <- glmer(target_structure ~ prime_condition * dialect_match +
                   (1 + prime_condition | participant) + (1 | item),
                 data = prime_data, family = binomial,
                 control = glmerControl(optimizer = "bobyqa"))
avg_slopes(m_prime, variables = "prime_condition", by = "dialect_match")
```

---

### Step 7e: Likert Analysis for Perception Data

**Ordinal vs. continuous treatment**: For 5+ point Likert scales with multiple items per construct, fit both ordinal (cumulative link mixed model) and linear mixed models; report both if conclusions converge.

```r
library(ordinal); library(lme4); library(performance)

# Ordinal approach (cumulative link mixed model)
m_clmm <- clmm(ordered(rating) ~ guise * dimension +
                  (1 | participant) + (1 | item),
                data = perception_data)
summary(m_clmm)

# Linear approach (if scale has 7+ points and near-normal distribution)
m_lmer <- lmer(rating ~ guise * dimension +
                 (1 | participant) + (1 | item),
               data = perception_data)
summary(m_lmer)

# Reliability: Cronbach's alpha per construct
library(psych)
alpha_status     <- psych::alpha(perception_wide[, c("item1","item2","item3")])
alpha_solidarity <- psych::alpha(perception_wide[, c("item4","item5","item6")])
```

**Reporting**: Report Cronbach's alpha (> 0.70 acceptable); if using ordinal model, report threshold coefficients; always report N participants, N items, and ICC for random effects.

**Key methodological references**: Schilling (2013) sociolinguistic fieldwork; Campbell-Kibler (2009, 2012) experimental sociolinguistics; Drager (2014) experimental approaches; Preston (1999) perceptual dialectology.

### Matched Guise / Perception Experiment Analysis

**Matched guise analysis (mixed-effects)**:
```r
library(lme4)
library(lmerTest)
# DV: attitude rating (1-7 Likert)
# Fixed: guise (standard vs. vernacular), listener demographics
# Random: listener, stimulus speaker
guise_mod <- lmer(rating ~ guise * listener_gender + (1 | listener_id) + (1 | speaker_id),
                  data = guise_data)
summary(guise_mod)
# Report: F tests via anova(guise_mod, type = 3)
emmeans::emmeans(guise_mod, pairwise ~ guise | listener_gender)
```

**Reaction time analysis**:
```r
# Pre-processing: remove RTs < 200ms (anticipatory) and > 2000ms (inattention)
rt_data <- rt_data |> filter(RT > 200, RT < 2000)
# Log-transform RT (positively skewed)
rt_data$log_RT <- log(rt_data$RT)
# Mixed-effects model
rt_mod <- lmer(log_RT ~ condition * frequency + (1 + condition | participant) + (1 | item),
               data = rt_data)
summary(rt_mod)
```

**IAT scoring (D-score, Greenwald et al. 2003)**:
```r
# D-score = (Mean_incompatible - Mean_compatible) / SD_all_correct_trials
d_score <- function(compatible_rt, incompatible_rt) {
  all_rt <- c(compatible_rt, incompatible_rt)
  (mean(incompatible_rt) - mean(compatible_rt)) / sd(all_rt)
}
```

---

