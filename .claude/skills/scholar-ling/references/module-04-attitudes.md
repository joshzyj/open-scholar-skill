## MODULE 4: LANGUAGE ATTITUDES AND IDEOLOGIES METHODS

### Matched Guise Technique (MGT)

**Design**: Participants evaluate ostensibly different speakers (actually same bilingual speaker in different varieties) on personality, competence, and status dimensions.

**Procedure**:
1. Record 1 bilingual/bidialectal speaker in both varieties (same passage)
2. Mix stimuli with fillers from other speakers; counterbalance order
3. Participants rate each "speaker" on Likert scales (typically 7-point)
4. Compare ratings: within-subjects (paired) or between-subjects

**Standard evaluation scales**:

```
Rate this speaker (1 = not at all, 7 = very much):
  STATUS:      Educated  | Intelligent  | Ambitious  | Successful
  SOLIDARITY:  Friendly  | Warm         | Trustworthy | Kind
  DYNAMISM:    Active    | Enthusiastic | Confident
```

**Analysis**:

```r
library(lme4); library(marginaleffects); library(gtsummary)

m_guise <- lmer(status_rating ~ guise + (1|participant) + (1|item),
                data = mgt_data)
# AME (not raw coefficients):
avg_slopes(m_guise, variables = "guise")

# Summary table with group comparison
tbl_summary(mgt_data, by = guise,
            include = c(status_rating, solidarity_rating)) |>
  add_p() |> bold_labels() |>
  as_gt() |> gt::gtsave("${OUTPUT_ROOT}/ling/tables/table-mgt.html")
```

**Modern variants**:
- Verbal guise technique (different speakers, same content)
- Implicit Association Test (IAT) for language attitudes — `taat` R package
- Speaker evaluation experiments via Qualtrics / crowdsourced via Prolific

---

### Survey Methods for Language Use and Attitudes

**Validated scales**:
- LEAP-Q (Language Experience and Proficiency Questionnaire)
- Self-rated proficiency: 4 modalities (speak, understand, read, write; 0–10)
- Frequency of use by domain (home, work, friends, media)
- Linguistic security / insecurity scale; Standard language ideology scale (Lippi-Green items)

**Analysis**:

```r
library(lavaan)

# Confirmatory factor analysis to validate subscales
cfa_model <- "
  status    =~ item1 + item2 + item3
  solidarity =~ item4 + item5 + item6"
fit <- cfa(cfa_model, data = mgt_data, estimator = "MLR")
summary(fit, fit.measures = TRUE)

# SEM: language use → attitudes → behavior
sem_model <- "
  attitude ~ use_heritage + use_dominant
  behavior ~ attitude + age"
fit_sem <- sem(sem_model, data = df)
summary(fit_sem, standardized = TRUE)
```

---

