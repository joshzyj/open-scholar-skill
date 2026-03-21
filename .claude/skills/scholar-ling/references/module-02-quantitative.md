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

