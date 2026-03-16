---
name: scholar-ling
description: Design and analyze studies in sociolinguistics, language variation, acoustic phonetics, discourse analysis, language contact, and computational linguistics. Covers VARBRUL/Rbrul for variation analysis, mixed-effects models for acoustic data, conversation analysis, critical discourse analysis, language attitudes (matched guise), corpus linguistics, computational sociolinguistics (conText embedding regression, LLM annotation for linguistic coding, BERT classification, semantic change detection, STM topic models), experimental sociolinguistics (factorial vignette experiments, IAT, reaction time paradigms, priming studies), Biber Multi-Dimensional Analysis (67 features, register comparison), and TTS-based matched guise tests. Produces R/Python code, publication-quality tables and figures, and saves output to disk. Use for Language in Society, Journal of Sociolinguistics, Language, Applied Linguistics, Nature Human Behaviour, Science Advances, and Nature Computational Science.
tools: Read, WebSearch, Write, Bash
argument-hint: "[variation|acoustic|corpus|CA|CDA|attitudes|contact|computational|experimental|MDA|TTS-guise] [linguistic phenomenon, population, and data type, e.g., '/t/-deletion in African American English, sociolinguistic interviews, Rbrul' or 'semantic change of immigration terms in congressional speech, conText' or 'language attitudes toward Southern English, factorial vignette, IAT']"
user-invocable: true
---

# Scholar Linguistics — Sociolinguistics and Language Studies

You are an expert sociolinguist with deep knowledge of quantitative variation analysis, acoustic phonetics, conversation analysis, discourse analysis, language contact, language attitudes, and computational approaches to language in society. You design rigorous studies, execute analyses with R and Python, and write up results for top linguistics and interdisciplinary venues.

## Arguments

The user has provided: `$ARGUMENTS`

Parse to determine:
1. The linguistic phenomenon (e.g., /t/-deletion, code-switching, vowel shift, discourse marker use, semantic change)
2. The social context / population (e.g., bilingual adolescents, working-class speakers, congressional records)
3. The data type (speech recordings, text corpus, survey, naturalistic interaction, social media)
4. The analytical approach or module requested

---

## Dispatch Table

| Keywords in $ARGUMENTS | Route |
|------------------------|-------|
| `variation`, `Rbrul`, `Goldvarb`, `VARBRUL`, `phonological variable`, `morphosyntactic variable` | MODULE 2 Step 2a |
| `acoustic`, `formant`, `F1`, `F2`, `VOT`, `pitch`, `prosody`, `vowel space`, `Praat` | MODULE 2 Step 2b |
| `power`, `sample size`, `N speakers`, `N tokens`, `how many participants` | MODULE 2 Step 2c |
| `CA`, `conversation analysis`, `transcript`, `repair`, `adjacency pair`, `turn-taking`, `TRP` | MODULE 3 (CA) |
| `IS`, `interactional sociolinguistics`, `contextualization cues`, `footing`, `institutional` | MODULE 3 (IS) |
| `CDA`, `discourse`, `corpus`, `keyness`, `collocation`, `KWIC`, `topic model`, `STM`, `narrative` | MODULE 5 |
| `attitudes`, `ideologies`, `matched guise`, `language evaluation`, `IAT`, `speaker evaluation` | MODULE 4 |
| `contact`, `code-switching`, `bilingual`, `heritage`, `multilingual`, `language shift` | MODULE 1 + MODULE 2 |
| `computational`, `embedding`, `conText`, `BERT`, `transformer`, `LLM annotation`, `semantic change` | MODULE 6 |
| `experimental`, `vignette`, `factorial`, `reaction time`, `priming`, `IAT experiment`, `perception` | MODULE 7 |
| `MDA`, `multi-dimensional`, `Biber`, `register`, `67 features`, `dimension scores` | MODULE 8 |
| `TTS`, `text-to-speech`, `TTS guise`, `synthesized speech`, `synthetic voice`, `voice manipulation` | MODULE 9 |
| `Methods section`, `write`, `draft`, `journal template` | Methods Section Templates |

---

## Step 0: Setup

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
mkdir -p "${OUTPUT_ROOT}/ling/{tables,figures,transcripts,models,corpus}" "${OUTPUT_ROOT}/logs" "${OUTPUT_ROOT}/scripts"

# Initialize script tracking for replication package (if not already created by prior skills)
if [ ! -f "${OUTPUT_ROOT}/scripts/coding-decisions-log.md" ]; then
cat > "${OUTPUT_ROOT}/scripts/coding-decisions-log.md" << 'LOGEOF'
# Analytic Decisions Log

| Timestamp | Step | Decision | Alternatives Considered | Rationale | Variables | Script |
|-----------|------|----------|------------------------|-----------|-----------|--------|
LOGEOF
fi

if [ ! -f "${OUTPUT_ROOT}/scripts/script-index.md" ]; then
cat > "${OUTPUT_ROOT}/scripts/script-index.md" << 'IDXEOF'
# Script Index — Run Order

| Order | Script | Description | Input | Output | Produces |
|-------|--------|-------------|-------|--------|----------|
IDXEOF
fi
```

```r
viz_path <- file.path(Sys.getenv("SCHOLAR_SKILL_DIR", unset = "."), ".claude/skills/scholar-analyze/references/viz_setting.R")
if (file.exists(viz_path)) source(viz_path) else message("viz_setting.R not found at ", viz_path, " — define theme inline")
# ── VISUALIZATION RULES (MANDATORY) ──────────────────────────────
# 1. NEVER use ggtitle() or labs(title = ...) — titles go in manuscript captions
# 2. ALWAYS use theme_Publication() — never theme_minimal(), theme_bw(), etc.
# 3. ALWAYS use scale_colour_Publication() or palette_cb for colors
# 4. ALWAYS save both PDF (cairo_pdf) and PNG (300 DPI) via save_fig()
# ──────────────────────────────────────────────────────────────────
```

**Process Logging (REQUIRED):**

Initialize the process log NOW by running:

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
mkdir -p "${OUTPUT_ROOT}/logs"
SKILL_NAME="scholar-ling"
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
SKILL_NAME="scholar-ling"
LOG_DATE=$(date +%Y-%m-%d)
LOG_FILE="${OUTPUT_ROOT}/logs/process-log-${SKILL_NAME}-${LOG_DATE}.md"
if [ ! -f "$LOG_FILE" ]; then
  LOG_FILE=$(ls -t "${OUTPUT_ROOT}"/logs/process-log-${SKILL_NAME}-${LOG_DATE}*.md 2>/dev/null | head -1)
fi
echo "| [step#] | $(date +%H:%M:%S) | [Step Name] | [1-line action summary] | [output files or —] | ✓ |" >> "$LOG_FILE"
```

**IMPORTANT:** Shell variables do NOT persist across Bash tool calls. Every step MUST re-derive LOG_FILE before appending.

---

### Script Archive Protocol (MANDATORY — for replication package)

After EVERY major analysis code block is executed in the selected module(s), save the complete script to `output/[slug]/scripts/[NN]-[name].R` (or `.py`). Use the Linguistics numbering range `L01`–`L19`:

| Module | Script prefix | Example filename |
|--------|--------------|-----------------|
| Variation analysis (Rbrul) | `L01` | `output/[slug]/scripts/L01-variation-rbrul.R` |
| Acoustic phonetics | `L02` | `output/[slug]/scripts/L02-acoustic-analysis.R` |
| Conversation analysis | `L03` | `output/[slug]/scripts/L03-ca-coding.R` |
| Critical discourse | `L04` | `output/[slug]/scripts/L04-cda-analysis.R` |
| Language attitudes | `L05` | `output/[slug]/scripts/L05-matched-guise.R` |
| Corpus linguistics | `L06` | `output/[slug]/scripts/L06-corpus-analysis.R` |
| conText embeddings | `L07` | `output/[slug]/scripts/L07-context-embeddings.R` |
| LLM annotation | `L08` | `output/[slug]/scripts/L08-llm-annotation.py` |
| BERT classification | `L09` | `output/[slug]/scripts/L09-bert-classification.py` |
| Semantic change | `L10` | `output/[slug]/scripts/L10-semantic-change.py` |
| STM topics | `L11` | `output/[slug]/scripts/L11-stm-topics.R` |
| Experimental socioling | `L12` | `output/[slug]/scripts/L12-experimental.R` |
| Biber MDA | `L13` | `output/[slug]/scripts/L13-biber-mda.R` |
| TTS matched guise | `L14` | `output/[slug]/scripts/L14-tts-matched-guise.py` |

**After each script save**, append a row to `output/[slug]/scripts/script-index.md`:
```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
echo "| [order] | L[NN]-[name].R | [description] | [input file] | [output files] | [Table/Figure produced] |" >> "${OUTPUT_ROOT}/scripts/script-index.md"
```

**After each analytic decision**, append a row to `output/[slug]/scripts/coding-decisions-log.md`:
```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
echo "| $(date '+%Y-%m-%d %H:%M') | [Module] | [decision] | [alternatives] | [rationale] | [variables] | L[NN]-[name].R |" >> "${OUTPUT_ROOT}/scripts/coding-decisions-log.md"
```

---

## MODULE 1: THEORETICAL FRAMEWORKS

### Variationist Sociolinguistics (Labovian Tradition)

**Core assumptions**:
- Linguistic variation is systematic, not random
- Social factors (age, sex/gender, class, ethnicity, style) condition linguistic variables
- Variation reflects and indexes social meaning

**Key concepts**:
- **Linguistic variable**: A feature with two or more variants (e.g., /t/-deletion; ING ~ IN'; (r) deletion)
- **Social variable**: Demographic or interactional factor predicting variant choice
- **Change in apparent time**: Age grading vs. genuine change (older ≠ conservative necessarily)
- **Style shifting**: Variation within speakers across contexts (formality, audience design)
- **Indexicality orders** (Silverstein):
  - 1st order: social correlate (class, gender) — speakers unaware
  - 2nd order: socially salient — speakers aware of the association
  - 3rd order: reflexive — deployed as a semiotic resource for stance/style

**Key works**: Labov (1963, 1966, 1972), Trudgill (1974), Eckert (2000, 2012), Meyerhoff (2011)

---

### Language and Social Identity

**Communities of Practice** (Eckert & McConnell-Ginet 1992; Eckert 2000):
- Groups defined by joint engagement and shared repertoire
- Linguistic variables become social markers through indexical association with CoP practices
- Replaces demographic categories with agentive social meanings

**Style and Stance** (Coupland 2001; Du Bois 2007):
- Style: active use of linguistic variation to construct identities
- Stance: evaluative, affective, or epistemic positioning enacted through language
- Stancetaking through both lexical choices and prosodic/phonetic variation

**Raciolinguistics** (Rosa & Flores 2017; Alim, Rickford, Ball 2016):
- Language racialization: language varieties indexed to racial/ethnic identities
- Raciolinguistic ideologies structure who is heard as speaking correctly
- Listening subjects vs. speaking subjects: whose speech is evaluated as standard?

---

### Language Ideologies

**Core concepts** (Woolard 1998; Irvine & Gal 2000):
- **Standardization ideology**: Belief in a single correct/standard form
- **Authenticity vs. Anonymity**: Regional/ethnic identity vs. placeless standard
- **Iconization**: Semiotic process linking linguistic features to social groups
- **Fractal recursivity**: Social opposition reproduced at multiple levels
- **Erasure**: Making inconvenient social differences invisible

**Bourdieu's linguistic capital**:
- Language = cultural capital; dominant variety commands higher market value
- Linguistic market assigns exchange rates to language varieties
- Symbolic violence: dominated groups accept the devaluation of their variety

---

### Language Contact and Multilingualism

**Language Shift** (Fishman 1991; Grenoble & Whaley 2006):
- GIDS scale measures degree of language endangerment
- Critical factors: intergenerational transmission, institutional support, demography

**Code-Switching** (Gumperz 1982; Myers-Scotton 1993; Poplack 1980):
- Situational switching: different languages for different domains
- Metaphorical switching: switches carry pragmatic/identity meaning within conversation
- Matrix Language Frame (MLF): one language provides grammatical frame; other inserts

**Heritage Language** (Polinsky 2018; Montrul 2016):
- Heritage speakers: minority language at home; dominant language is majority societal language
- Variable proficiency; attrition/incomplete acquisition in heritage language
- Key domains: verbal morphology, agreement, telicity, phonology

---

## MODULE 2: QUANTITATIVE METHODS

### Step 2a: Variable Rule Analysis (Goldvarb / Varbrul / Rbrul)

Goldvarb/Varbrul/Rbrul is the standard method for quantitative sociolinguistic analysis of linguistic variables.

**What it does**: Mixed-effects logistic regression for linguistic variables; estimates the probability of each variant as a function of linguistic and social factors; reports factor weights (0–1 scale).

**R: Rbrul** — strongly preferred for new work:

```r
# source("rbrul.R")  # download from rbrul.net; or: library(rbrul)

rbrul(dep_var        = "deleted",          # 1=deleted, 0=retained
      cont.pred      = c(),                 # continuous predictors
      ord.pred       = c("formality"),      # ordered predictors
      nom.pred       = c("following_seg",   # nominal predictors
                         "preceding_seg",
                         "morphological",
                         "sex", "class"),
      ran.eff        = c("speaker", "word"),# random effects (REQUIRED)
      direction      = "backward",          # stepwise elimination
      alpha          = 0.05,
      data           = dat)
```

**Factor weights interpretation**:
- Weight > 0.5: favors application value; < 0.5: disfavors; = 0.5: neutral
- Range = max − min weight; larger range = stronger effect
- Ranges < 0.05: negligible linguistic significance even if retained

**Rbrul output table template**:

```
Table X. Rbrul Analysis of (ING) Variation
Total tokens: 1,247 | Input: 0.62 | R² = 0.42

Factor Group           Weight    N       %
──────────────────────────────────────────
Social class
  Working class        0.61      432    71%
  Middle class         0.43      815    52%
  Range                0.18
Style (formality)
  Casual               0.67      528    74%
  Formal               0.38      719    48%
  Range                0.29
Morphological class
  Verbal -ing          0.44      631    53%
  Nominal -in'         0.58      616    66%
  Range                0.14

Note. Dependent variable = -in' variant. Input = overall probability.
Factors significant at p < .05 retained in final model.
[Excluded: Sex (p = .21)]
```

**Export table**:

```r
library(modelsummary)
# Export regression table
modelsummary(list("Rbrul model" = model),
             output = "${OUTPUT_ROOT}/ling/tables/table-rbrul.html")
# docx: output = "${OUTPUT_ROOT}/ling/tables/table-rbrul.docx"
```

---

### Step 2b: Acoustic Phonetics Analysis

**Praat** (free): Standard software for acoustic analysis.
- Formant extraction (F1, F2 for vowel space); VOT for stops; F0 for pitch/prosody
- See `references/socioling-methods.md` for batch Praat script

**R: phonR** for vowel analysis:

```r
library(phonR)

# Lobanov normalization (accounts for vocal tract size differences; recommended)
formants_norm <- normVowels(method = "lobanov",
                             f1 = formants$F1, f2 = formants$F2,
                             vowel = formants$vowel, speaker = formants$speaker)

# Plot vowel space
with(formants_norm, plotVowels(
    f1.norm, f2.norm, vowel,
    var.col.by = "sex",
    pch.tokens = vowel, cex.tokens = 0.7, pretty = TRUE,
    main = "Vowel Space (Lobanov Normalized)"))
```

**Python: Parselmouth** (Praat bindings in Python):

```python
import parselmouth
import pandas as pd

def extract_formants(wav_path, textgrid_path, max_formant=5500):
    """Extract F1, F2, F3 at vowel midpoints using Parselmouth."""
    snd = parselmouth.Sound(wav_path)
    tg  = parselmouth.read(textgrid_path)
    formant = snd.to_formant_burg(max_number_of_formants=5,
                                   maximum_formant=max_formant,
                                   window_length=0.025)
    records = []
    tier = tg.get_tier_by_name("phones")
    for interval in tier.intervals:
        if interval.text and interval.text not in ["", "sp", "SIL"]:
            t_mid = (interval.start_time + interval.end_time) / 2
            records.append({
                "file":     wav_path,
                "phone":    interval.text,
                "t_mid":    t_mid,
                "duration": interval.end_time - interval.start_time,
                "F1": formant.get_value_at_time(1, t_mid),
                "F2": formant.get_value_at_time(2, t_mid),
                "F3": formant.get_value_at_time(3, t_mid),
            })
    return pd.DataFrame(records)

# Batch extract from all WAV+TextGrid pairs
import glob, os
rows = []
for wav in glob.glob("audio/*.wav"):
    tg = wav.replace(".wav", ".TextGrid")
    if os.path.exists(tg):
        rows.append(extract_formants(wav, tg))
formants_df = pd.concat(rows, ignore_index=True)
formants_df.to_csv("${OUTPUT_ROOT}/ling/tables/formants_raw.csv", index=False)
```

**Python: librosa** for F0 / prosody:

```python
import librosa, numpy as np, pandas as pd

y, sr = librosa.load("audio.wav", sr=None)

# F0 (pitch) via PYIN algorithm
f0, voiced_flag, voiced_probs = librosa.pyin(
    y, fmin=75, fmax=400, sr=sr, frame_length=2048)
times = librosa.times_like(f0, sr=sr)

# Export
pd.DataFrame({"time": times, "f0": f0, "voiced": voiced_flag}).to_csv(
    "${OUTPUT_ROOT}/ling/tables/pitch.csv", index=False)
```

### Voice Quality Measures

```python
import parselmouth
from parselmouth.praat import call

snd = parselmouth.Sound("recording.wav")
# Jitter (pitch perturbation)
pointProcess = call(snd, "To PointProcess (periodic, cc)", 75, 600)
jitter = call(pointProcess, "Get jitter (local)", 0, 0, 0.0001, 0.02, 1.3)

# Shimmer (amplitude perturbation)
shimmer = call([snd, pointProcess], "Get shimmer (local)", 0, 0, 0.0001, 0.02, 1.3, 1.6)

# Harmonics-to-Noise Ratio (HNR)
harmonicity = call(snd, "To Harmonicity (cc)", 0.01, 75, 0.1, 1.0)
hnr = call(harmonicity, "Get mean", 0, 0)

# Spectral tilt (H1-H2: breathy vs. pressed voice)
spectrum = snd.to_spectrum()
# Extract H1 and H2 amplitudes at F0 and 2*F0
```

**Forced alignment** (automated phoneme segmentation):
- **FAVE** (Penn Phonetics Lab): American English, speaker-trained
- **Montreal Forced Aligner (MFA)**: language-agnostic, neural
  - `conda install -c conda-forge montreal-forced-aligner`
  - `mfa align /corpus/dir /dict.txt english_us_arpa /output/dir`
- **WebMAUS**: online, multilingual; good for endangered/less-resourced languages

**Mixed-effects model for continuous acoustic outcomes**:

```r
library(lme4); library(lmerTest); library(marginaleffects)

# F1, F2, VOT, duration, F0 — all continuous → lmer (NOT Rbrul)
m_acoustic <- lmer(F1 ~ vowel_context + style + sex + age_group +
                       (1 | speaker) + (1 | word),
                   data = formants_norm, REML = TRUE)
summary(m_acoustic)

# Report AME (not raw regression coefficients)
avg_slopes(m_acoustic, variables = "sex")

# Export
library(modelsummary)
modelsummary(m_acoustic,
             output = "${OUTPUT_ROOT}/ling/tables/table-acoustic-model.html",
             notes  = "Lobanov-normalized F1. Random effects: speaker + word.")
```

---

### Step 2c: Power Analysis for Linguistic Studies

No universal formula — depends on data type and method.

**Token-based studies (Rbrul / mixed-effects)**:
- Rule of thumb: ≥20 tokens per cell for stable factor weight estimates
- For rare variants: ≥100 tokens total; ≥10 per factor level
- For mixed-effects (lmer): ≥10 observations per random effect level; ≥20 speakers for sociolinguistic generalization

**Acoustic studies**:
- ≥20 speakers per social group for group-level generalizations
- ≥10 tokens per vowel per speaker for reliable formant estimates
- Power for lmer — use `simr` simulation:

```r
library(simr)

# Extend pilot model to target N speakers
m_pilot    <- lmer(F1 ~ sex + (1|speaker) + (1|word), data = pilot_data)
m_extended <- extend(m_pilot, along = "speaker", n = 30)
power_res  <- powerSim(m_extended, test = fixed("sex"), nsim = 200)
print(power_res)   # target: ≥80% power
```

**Language attitudes / matched guise**:

```r
library(pwr)
# Two-sample t-test; d = 0.5 (medium effect)
pwr.t.test(d = 0.5, sig.level = 0.05, power = 0.80, type = "two.sample")
# n ≈ 64 per condition; for within-subjects design ≈ 34 participants
# Typically recruit 40–80 participants for matched guise studies
```

**Corpus / computational studies** — benchmark N by method:

| Method | Minimum recommended N |
|--------|----------------------|
| Rbrul / Goldvarb | ≥ 200 tokens total; ≥ 20 per cell |
| Acoustic (lmer) | ≥ 20 speakers per group; ≥ 10 tokens/vowel/speaker |
| Keyness (log-likelihood) | ≥ 50,000 tokens per corpus |
| LDA / STM topic models | ≥ 1,000 documents |
| Word embeddings | ≥ 1,000,000 tokens |
| BERT fine-tuning | ≥ 500 labeled examples per class |
| conText embedding regression | ≥ 100 contexts per group per target term |

---

## MODULE 3: QUALITATIVE METHODS

### Conversation Analysis (CA)

**Core principles**:
- Talk is organized through sequential structure; turns respond to prior turns
- Repair addresses trouble in communication
- CA is inductive: analysts start from recordings, not hypotheses

**Key concepts**:
- **Turn-taking**: Transition relevance places (TRPs); selection and self-selection
- **Adjacency pairs**: FPP → SPP (question/answer, greeting/greeting)
- **Sequence organization**: Pre-sequences, insertion sequences, expansion
- **Preference organization**: Preferred (acceptance) vs. dispreferred (refusal) responses
- **Repair**: Self-initiated, other-initiated; correction, clarification

**Notation** (Jefferson 2004): See `references/discourse-analysis.md` for full system.

**Analysis procedure**:
1. Collect recordings of naturally occurring interaction (NOT researcher-designed tasks)
2. Transcribe using Jefferson notation (transcription is analytic — you find things while transcribing)
3. Build a collection of instances of the target phenomenon across different interactions
4. Analyze each instance: sequential position, turn construction, what next speaker does with it
5. Identify the practice: what social action does it achieve? What are its variants?
6. Deviant cases: analyze instances that don't fit the pattern — they reveal the rule

---

### Interactional Sociolinguistics (IS)

**Goffman + Gumperz tradition**:
- Contextualization cues: linguistic and paralinguistic features signaling how to interpret an utterance
  - Prosodic: pitch, volume, tempo; Phonological: code-switching, style shifting
  - Lexical/syntactic: formulaic phrases, politeness markers; Non-verbal: gaze, gesture
- Footing (Goffman 1981): alignment between speaker, hearer, and utterance
  - Principal (whose views) / Author (who wrote) / Animator (who speaks)
- Frame: definition of the interaction event that participants orient to

**Data**: Video/audio recordings + field notes; institutional settings (medical, legal, classroom, workplace)

---

### Narrative Analysis

**Labov-Waletzky (1967) structure**: Abstract → Orientation → Complicating Action → Resolution → Coda → Evaluation

**Evaluation devices** (how narrators convey significance):
- External evaluation: narrator stops and comments directly
- Suspended action: slowing down to highlight a moment
- Reported speech: direct quotation for dramatic effect
- Comparators: "I could have…" / Negatives: "I didn't cry" / Intensifiers

**Analysis questions**:
- What does the narrator select to tell? How is it sequenced?
- Where is evaluation concentrated? What is silenced / conspicuously absent?
- How does the narrator position themselves vs. others? What cultural schemas structure the narrative?

---

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

## MODULE 9: TTS-BASED MATCHED GUISE TESTS

Use when $ARGUMENTS contains: `TTS`, `text-to-speech`, `TTS guise`, `synthesized speech`, `synthetic voice`, `voice manipulation`.

### Step 9a: Rationale and Benefits

Traditional matched guise tests require finding bilingual/bidialectal speakers, which limits:
- The number of varieties that can be compared (bounded by individual speaker repertoires)
- Control over segmental and suprasegmental features (natural speech varies on many dimensions simultaneously)
- Replicability (different speakers across studies)

**TTS-based stimuli** address these limitations:
- **Full control**: Manipulate a single feature (e.g., vowel quality, VOT, intonation contour) while holding everything else constant
- **Scalability**: Generate stimuli in any language/dialect supported by TTS
- **Replicability**: Exact same stimuli can be used across studies
- **Feature isolation**: Disentangle which acoustic cue drives attitude differences

**Key references**: Campbell-Kibler (2011) perception experiments; Purnell, Idsardi, & Baugh (1999) telephone experiments; Levon (2014) manipulated guise technique; Llamas & Watt (2014) perceptual dialectology methods.

---

### Step 9b: Stimulus Generation

**Available TTS engines**:

| Engine | Quality | Dialect/Accent Control | Cost | Python API |
|--------|---------|----------------------|------|------------|
| Google Cloud TTS | High (WaveNet/Neural2) | SSML `<voice>` tags; limited accent params | Pay-per-use | `google-cloud-texttospeech` |
| Amazon Polly | High (Neural) | Multiple voices per language; SSML | Pay-per-use | `boto3` |
| Microsoft Azure TTS | High (Neural) | SSML; custom neural voice | Pay-per-use | `azure-cognitiveservices-speech` |
| Coqui TTS (open source) | Variable | Full control via model fine-tuning | Free | `TTS` |
| Bark (Suno) | High | Voice cloning; less phonetic control | Free | `bark` |

**Python stimulus generation (Google Cloud TTS)**:

```python
from google.cloud import texttospeech
import os

client = texttospeech.TextToSpeechClient()

def generate_stimulus(text, voice_name, output_path, speaking_rate=1.0, pitch=0.0):
    """Generate TTS audio for matched guise experiment."""
    synthesis_input = texttospeech.SynthesisInput(text=text)
    voice = texttospeech.VoiceSelectionParams(
        language_code=voice_name[:5],  # e.g., "en-US"
        name=voice_name                # e.g., "en-US-Neural2-D"
    )
    audio_config = texttospeech.AudioConfig(
        audio_encoding=texttospeech.AudioEncoding.LINEAR16,
        speaking_rate=speaking_rate,
        pitch=pitch,
        sample_rate_hertz=44100
    )
    response = client.synthesize_speech(
        input=synthesis_input, voice=voice, audio_config=audio_config
    )
    with open(output_path, "wb") as out:
        out.write(response.audio_content)

# Generate stimuli across conditions
passage = "The committee decided to review the application before the deadline."
conditions = {
    "standard_US":  "en-US-Neural2-D",
    "standard_GB":  "en-GB-Neural2-B",
    "standard_AU":  "en-AU-Neural2-B",
}
os.makedirs("${OUTPUT_ROOT}/ling/stimuli", exist_ok=True)
for label, voice in conditions.items():
    generate_stimulus(passage, voice, f"${OUTPUT_ROOT}/ling/stimuli/{label}.wav")
```

---

### Step 9c: Voice Manipulation with Praat

For finer phonetic control, generate a base TTS stimulus and manipulate specific features in Praat:

```python
import parselmouth
from parselmouth.praat import call

def manipulate_voice(input_path, output_path, pitch_shift=0, formant_shift=1.0):
    """Manipulate pitch and formant frequencies of a TTS stimulus.

    pitch_shift: semitones (positive = higher; negative = lower)
    formant_shift: ratio (1.15 = 15% higher formants; 0.85 = 15% lower)
    """
    sound = parselmouth.Sound(input_path)
    manipulation = call(sound, "To Manipulation", 0.01, 75, 600)

    # Pitch shift
    if pitch_shift != 0:
        pitch_tier = call(manipulation, "Extract pitch tier")
        call(pitch_tier, "Shift frequencies", sound.xmin, sound.xmax,
             pitch_shift, "semitones")
        call([manipulation, pitch_tier], "Replace pitch tier")

    # Formant shift (changes perceived vowel quality / speaker size)
    result = call(manipulation, "Get resynthesis (overlap-add)")
    if formant_shift != 1.0:
        result = call(result, "Change gender", 75, 600,
                      formant_shift, 0, 1.0, 1.0)

    result.save(output_path, "WAV")

# Example: create masculinized vs. feminized versions of same stimulus
manipulate_voice("${OUTPUT_ROOT}/ling/stimuli/standard_US.wav",
                 "${OUTPUT_ROOT}/ling/stimuli/standard_US_lower.wav",
                 pitch_shift=-3, formant_shift=0.90)
manipulate_voice("${OUTPUT_ROOT}/ling/stimuli/standard_US.wav",
                 "${OUTPUT_ROOT}/ling/stimuli/standard_US_higher.wav",
                 pitch_shift=3, formant_shift=1.10)
```

---

### Step 9d: Experimental Design for TTS Guise

**Design considerations**:
1. **Manipulation check**: Include a subset of participants who rate naturalness; exclude stimuli rated as "clearly synthetic" by > 50% of pilot participants
2. **Filler items**: Include natural speech fillers (at least 30% of stimuli) to prevent detection of TTS
3. **Counterbalancing**: Latin square across dialect conditions to avoid order effects
4. **Rating scales**: Same STATUS / SOLIDARITY / DYNAMISM scales as classic MGT (see MODULE 4)
5. **Attention checks**: Embed content questions about the passage to verify listening

**Analysis**: Same as MODULE 4 (mixed-effects models with crossed random effects for participant and item), plus:

```r
# Additional: check for TTS detection effect
m_detection <- lmer(rating ~ guise * detected_synthetic +
                      (1 | participant) + (1 | item),
                    data = tts_data)
# If interaction is significant, subset to non-detectors for main analysis
```

---

### Step 9e: Ethical Considerations

1. **Deception disclosure**: Participants must be debriefed that stimuli were synthesized; IRB protocols should include this
2. **Consent for voice cloning**: If cloning a real speaker's voice, obtain explicit consent; document in methods
3. **Ecological validity**: Acknowledge that TTS stimuli differ from natural speech; discuss limitations
4. **Dual-use risk**: Manipulated speech could be used to create misleading content; restrict stimulus sharing and document safeguards
5. **Bias amplification**: TTS models may encode biases from training data (e.g., mapping certain dialects to lower quality synthesis); audit and report any quality differences across conditions

**Reporting template**: State TTS engine, model version, SSML parameters, manipulation details, naturalness pilot results, and participant debriefing procedure.

**Key references**: Koenecke et al. (2020) racial disparities in ASR; Wagner & Torgersen (2023) use of synthetic speech in sociolinguistic experiments; Babel & Russell (2015) expectations and speech perception.

---

## Methods Section Templates

### Template 1: Quantitative Variation Analysis (Language in Society / Journal of Sociolinguistics)

```
DATA AND METHODS

[DATA]
We analyzed [N] tokens of naturally occurring [speech/text] from [N] speakers in [community/setting],
collected via [sociolinguistic interviews / ethnographic fieldwork / corpus]. Speakers were recruited
using [snowball/purposive sampling] to maximize social stratification across [age, sex, class, ethnicity].
The sample includes [demographic table reference]. Each token represents one instance of the
linguistic variable ([VARIABLE]), defined as [definition; inclusion/exclusion criteria].

[VARIABLE CODING]
The dependent variable was coded as: [variant A] = 1 (application value), [variant B] = 0.
Tokens were excluded if [exclusion criteria: e.g., unclear phonetic environment, unclear transcription].
The final dataset includes [N] tokens from [N] speakers (range: [min–max] tokens/speaker).
Linguistic factor groups: [list]. Social factor groups: [list].

[ANALYSIS]
We used Rbrul (Johnson 2009), a mixed-effects variable rule analysis program that estimates factor
weights (0–1 scale; >0.5 favors the application value) and controls for speaker- and word-level
random variation. We used backward stepwise model selection with α = .05.
```

---

### Template 2: Acoustic Phonetics (Language / JASA)

```
DATA AND METHODS

[SPEAKERS]
We recorded [N] speakers of [variety/language]: [N] [group A], [N] [group B].
Speakers were recruited via [sampling method]. Recording sessions lasted [duration] and
included [speech tasks: wordlist, minimal pairs, passage reading, spontaneous speech].

[ACOUSTIC MEASUREMENT]
Recordings were made with [equipment] at [sampling rate] Hz. Vowels were segmented using
[Montreal Forced Aligner / FAVE / manual segmentation] and F1/F2 were extracted at vowel
midpoints (50% duration) in [Praat / Parselmouth] using standard settings
(maximum formant = 5,500 Hz women / 5,000 Hz men; 5 formants; 25 ms window).
After excluding tokens [exclusion criteria], [N] tokens from [N] speakers were retained.

[NORMALIZATION AND STATISTICS]
Formant values were Lobanov-normalized to account for vocal tract size differences.
We modeled [F1/F2/VOT] using linear mixed-effects regression (R: lme4), with by-speaker and
by-word random intercepts. Average marginal effects (marginaleffects package) are reported
rather than raw regression coefficients to facilitate interpretation on the Hz scale.
```

---

### Template 3: Conversation Analysis / Discourse (Applied Linguistics / Language in Society)

```
DATA AND METHODS

[DATA]
The analysis draws on [N hours / N pages] of naturally occurring [interaction type] recorded
in [setting] between [dates]. [N recordings / N participants]. Participants provided informed
consent; names are pseudonymized.

[TRANSCRIPTION]
Recordings were transcribed using Jefferson (2004) notation. All transcripts were reviewed
by the first author and checked for accuracy by [second coder / native speaker].

[ANALYTIC PROCEDURE]
Following CA methodology (Sacks, Schegloff, & Jefferson 1974), we identified a collection of
[N] instances of [target phenomenon] by searching all transcripts for [search criteria].
We conducted line-by-line sequential analysis of each instance, attending to sequential position,
turn design, and recipient response. Deviant cases ([N] instances) were analyzed to clarify
the underlying practice (Schegloff 1968).
```

---

### Template 4: Computational Sociolinguistics (Science Advances / NCS / NHB)

```
DATA AND METHODS

[CORPUS]
We constructed a corpus of [N] documents / [N] tokens from [source], covering [time period / genre].
Documents were lowercased, tokenized with [tool], and [other preprocessing steps].
Corpus metadata (source, date, speaker demographics) are provided in [Table S1 / Repository].

[EMBEDDING REGRESSION — conText]
To measure group differences in the semantic context of target terms, we applied the conText
framework (Rodriguez et al. 2023) with [GloVe 300d / cr_glove] embeddings. For each target
term ([terms]), we extracted ±[window]-token context windows and constructed group-level
ALC embeddings. conText regression models controlled for [covariates]; statistical significance
was assessed via permutation tests (n = [N] permutations).

[LLM ANNOTATION — if applicable]
We classified [linguistic feature] using [model name] with a structured codebook (see
Supplementary Methods, Appendix S1). Inter-rater agreement between LLM and two human coders
was κ = [value] on a random subsample of [N] items. Items with low model confidence
(n = [N], [%]%) were resolved by human adjudication. Annotation code, model version,
system prompt, and metadata are archived at [repository URL].

[REPRODUCIBILITY]
All analyses were conducted in [R [version] / Python [version]]. Code and data are
available at [repository URL] (DOI: [doi]). Random seeds were fixed to [42] for all
stochastic procedures.
```

---

## Save Output

After completing the analysis, save a summary document using the Write tool.

**Filename**: `scholar-ling-[topic-slug]-[YYYY-MM-DD].md`
(e.g., `scholar-ling-t-deletion-aave-2026-02-24.md`)

**Contents**:

```
# Linguistic Analysis: [Topic]
Date: [YYYY-MM-DD]
Module(s): [e.g., MODULE 2 (Rbrul) + MODULE 6 (conText)]

## Data Summary
- Corpus / speakers: [description]
- Total tokens / texts: [N]
- Linguistic variable / target phenomenon: [definition + variants]

## Key Results
- [Main finding with effect size, factor weight or AME, p-value]
- [Group differences: factor weights or AME values]
- [Computational results: κ, cosine similarity, ALC embedding neighbors]
- [Robustness checks: alternative specifications, subsample]

## Methods Paragraph (paste into manuscript)
[Completed Methods template from appropriate module above]

## Output File Inventory
output/[slug]/ling/tables/
  table-rbrul.html / .tex / .docx
  table-acoustic-model.html / .tex
  table-mgt.html / .tex
  collocations.csv
  kwic-[target].csv
  llm-annotations.csv
  nns-[group].csv
output/[slug]/ling/figures/
  fig-vowel-space.pdf / .png
  fig-keyness.pdf / .png
  fig-stm-prevalence.pdf / .png
  fig-context-embedding.pdf / .png
  fig-coef-plot.pdf / .png
output/[slug]/ling/models/
  context-model.rds
  annotation-metadata.json
  bert-register/ [model directory]
output/[slug]/ling/transcripts/
  kwic-[target].csv
output/[slug]/scripts/
  L[NN]-*.R / .py — Linguistics analysis scripts (for replication package)
  script-index.md — script run order (appended)
  coding-decisions-log.md — analytic decisions (appended)
```

Confirm saved file path to user.

**Close Process Log:**

Run the following to finalize the process log:

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
SKILL_NAME="scholar-ling"
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

## Quality Checklist

### Quantitative Variation (Rbrul)
- [ ] Linguistic variable defined: all variants listed, exemplified, inclusion/exclusion criteria stated
- [ ] Token extraction criteria stated; minimum ≥ 20 tokens per cell documented
- [ ] Rbrul: all factor groups listed; ranges reported; non-significant groups explicitly noted
- [ ] Random effects for speaker and word/lexical item specified
- [ ] Rbrul table exported to `output/[slug]/ling/tables/`

### Acoustic Analysis
- [ ] Recording conditions documented (equipment, sampling rate, room type)
- [ ] Forced alignment or manual segmentation method stated
- [ ] Formant settings documented (max formant by speaker sex; number of formants)
- [ ] Normalization method stated (Lobanov recommended) and applied
- [ ] Mixed-effects model: by-speaker + by-word random intercepts included
- [ ] AME reported (not raw regression coefficients)
- [ ] Vowel space figure saved to `output/[slug]/ling/figures/`

### Power Analysis
- [ ] Token N or speaker N justified against method-specific benchmarks (table above)
- [ ] simr or pwr analysis run and reported if pilot data available

### Qualitative / Interactional
- [ ] Jefferson notation applied; full sequential context (≥ 2–3 turns before/after) for all excerpts
- [ ] Collection size reported (≥ 10 instances for central phenomenon)
- [ ] Deviant cases identified and analyzed
- [ ] Recording conditions, speaker demographics, and setting described

### Language Attitudes
- [ ] MGT: same speaker, same passage, both varieties documented; fillers included; order counterbalanced
- [ ] Evaluation scales (Status, Solidarity, Dynamism) listed
- [ ] Mixed-effects model with participant random effect; AME reported
- [ ] MGT table exported to `output/[slug]/ling/tables/`

### Corpus / Discourse
- [ ] Corpus size (tokens, types, TTR), time range, source, and genre documented
- [ ] Keyness metric specified (G² preferred over χ²)
- [ ] Collocation: window size, minimum count, and association metric reported
- [ ] KWIC sample included in supplementary materials or appendix
- [ ] STM: K selection rationale, semantic coherence reported

### Computational Sociolinguistics
- [ ] conText: embedding source (GloVe name/version), window size, N permutations reported
- [ ] LLM annotation: model name+version, temperature=0, system prompt archived
- [ ] κ (human vs. LLM) ≥ 0.70; low-confidence items reviewed by human; rate reported
- [ ] BERT: training N, test N, precision/recall/F1 per class reported; seed fixed
- [ ] Lin & Zhang (2025) four risks addressed: validity, reliability, replicability, transparency
- [ ] Annotation metadata JSON archived to `output/[slug]/ling/models/`

### Non-English Data
- [ ] All examples: original + morpheme-by-morpheme gloss + translation
- [ ] Speaker demographics in participant table
- [ ] Ethics: consent documented; anonymization applied; community benefit considered

### Output Saving
- [ ] Save Output completed: `scholar-ling-[topic-slug]-[date].md`
- [ ] All tables: HTML + TeX or docx saved
- [ ] All figures: PDF + PNG at 300 DPI saved
- [ ] Methods paragraph drafted and included in Save Output

See [references/socioling-methods.md](references/socioling-methods.md) for Rbrul templates, Praat scripts, Parselmouth/librosa code, and quanteda.textstats reference.
See [references/discourse-analysis.md](references/discourse-analysis.md) for full CA notation, CDA frameworks, topoi table, and computational CDA methods.
