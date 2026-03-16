# Sociolinguistic Methods Reference

## Rbrul (Variable Rule Analysis) — Complete Guide

### Data Format
One row per token. Required columns:
- Dependent variable: binary (variant A = 1, variant B = 0) or binary for polyvariable
- Linguistic factors: following phonological context, preceding context, stress, syllable structure, morphological class, etc.
- Social factors: speaker ID, age, sex/gender, social class, ethnicity, style/register
- Speaker as random effect (obligatory in Rbrul)
- Word/lexical item as random effect (if studying phonological variable)

### Rbrul Workflow
```r
# Download Rbrul: http://www.rbrul.com
source("rbrul.R")

# Load data
dat <- read.csv("t_deletion_tokens.csv")

# Run analysis: backward stepwise model selection
rbrul(
  dep.var = "deleted",          # 1=deleted, 0=retained
  cont.pred = c(),              # continuous predictors (none here)
  ord.pred = c("formality"),    # ordered predictors
  nom.pred = c("following_seg", # nominal predictors
               "preceding_seg",
               "morphological",
               "sex", "class"),
  ran.eff = c("speaker", "word"),  # random effects
  direction = "backward",          # stepwise elimination
  alpha = 0.05,                    # threshold for retention
  data = dat
)
```

### Reading the Output

```
Application value: deleted (1)
Input: 0.47          [= overall probability of deletion]
Log likelihood: -812.3
Chi-square: 248.6, p < .001

                        Weight    N      %
Following segment
  Consonant             0.63     1284   61%
  Vowel                 0.42      892   38%
  Pause                 0.71      224   68%
  Range                 0.29

Social class
  Working class         0.59     956   58%
  Middle class          0.44     1444   43%
  Range                 0.15

[Factors NOT selected (p > .05)]
Sex: p = .21 (not significant; excluded)
```

**Interpretation rules**:
- Weight > 0.5: factor favors the application value (deletion in this case)
- Weight < 0.5: factor disfavors application
- Range = max weight − min weight: larger range = stronger effect
- Factors with range < 0.05 have negligible linguistic significance even if retained

### Goldvarb (older, still common in older literature)
- DOS/Windows program; free; limited to binary variables
- Produces same output format as Rbrul (weights, ranges, input)
- Use Rbrul for new work; Goldvarb for replication of older studies

---

## Corpus Linguistics Reference

### Building a Study Corpus (AntConc / Sketch Engine)

**Corpus design principles**:
- Define corpus inclusion criteria (genre, time period, source, language)
- Document corpus size (tokens, types), coverage, and metadata
- Report type-token ratio (TTR): lower TTR = less lexical diversity; higher = more
- Balance the corpus if comparing across groups (same genre, same N words per group)

### AntConc Functions

| Function | Use |
|---------|-----|
| Concordance (KWIC) | See every instance of a word in context |
| Concordance Plot | See distribution of word across corpus |
| File View | Read individual texts |
| Clusters / N-grams | Find frequent multi-word sequences |
| Collocates | Find words that co-occur with the search term |
| Word List | Frequency list of all types in corpus |
| Keyword List | Keyness analysis (compare two corpora) |

### Collocation Analysis (R: quanteda)
```r
library(quanteda)

corp <- corpus(df, text_field = "text")
toks <- tokens(corp, remove_punct = TRUE) %>% tokens_tolower()

# Collocations around target word
col <- tokens_select(toks, pattern = "immigrant*", padding = TRUE)
textstat_collocations(col, size = 2:3, min_count = 10) %>%
  head(20)
```

### Concordance Analysis (R: quanteda.kwic)
```r
# KWIC: keyword in context
kwic_results <- kwic(toks, pattern = "undocumented*", window = 5)
head(kwic_results, 20)

# Export for manual analysis
write.csv(as.data.frame(kwic_results), "kwic_undocumented.csv")
```

---

## Acoustic Phonetics Reference

### Praat Formant Extraction Script
```praat
# Batch extract F1, F2 at vowel midpoints from TextGrid
# Save as extract_formants.praat; run from Praat Objects

dir$ = "/path/to/audio/"
outfile$ = "/path/to/formants.csv"

writeFileLine: outfile$, "filename,vowel,time,F1,F2,F3,duration"

Create Strings as file list: "files", dir$ + "*.wav"
n = Get number of strings

for i from 1 to n
    selectObject: "Strings files"
    filename$ = Get string: i
    basename$ = filename$ - ".wav"

    Read from file: dir$ + filename$
    sound = selected("Sound")

    Read from file: dir$ + basename$ + ".TextGrid"
    tg = selected("TextGrid")

    selectObject: sound
    To Formant (burg): 0, 5, 5500, 0.025, 50
    formant = selected("Formant")

    selectObject: tg
    n_intervals = Get number of intervals: 1

    for j from 1 to n_intervals
        label$ = Get label of interval: 1, j
        if label$ <> "" and label$ <> "sp" and label$ <> "SIL"
            t_start = Get start time of interval: 1, j
            t_end = Get end time of interval: 1, j
            t_mid = (t_start + t_end) / 2
            duration = t_end - t_start

            selectObject: formant
            f1 = Get value at time: 1, t_mid, "Hertz", "Linear"
            f2 = Get value at time: 2, t_mid, "Hertz", "Linear"
            f3 = Get value at time: 3, t_mid, "Hertz", "Linear"

            appendFileLine: outfile$, basename$, ",", label$, ",",
            ...t_mid, ",", f1, ",", f2, ",", f3, ",", duration

            selectObject: tg
        endif
    endfor

    removeObject: sound, tg, formant
endfor
```

### Vowel Normalization (R: phonR)
```r
library(phonR)

formants <- read.csv("formants.csv")

# Lobanov normalization (speaker-specific z-scores; recommended)
# Accounts for differences in vocal tract size
formants_norm <- normVowels(method = "lobanov",
                             f1 = formants$F1,
                             f2 = formants$F2,
                             vowel = formants$vowel,
                             speaker = formants$speaker)

# Plot vowel space
with(formants_norm, plotVowels(
    f1.norm, f2.norm, vowel,
    var.col.by = "speaker",
    pch.tokens = vowel,
    cex.tokens = 0.7,
    pretty = TRUE,
    main = "Vowel Space (Lobanov Normalized)"
))
```

### Mixed Effects Model for Vowel Variation
```r
library(lme4)

# Model: F1 as function of social and linguistic variables
m1 <- lmer(F1 ~ vowel_context + style +
               sex + age_group + social_class +
               (1 | speaker) + (1 | word),
            data = formants_norm)
summary(m1)

# Use rbrul for variable rule analysis of categorical variables
# Use lmer for continuous acoustic outcomes (F1, F2, duration, VOT)
```

---

## Language Attitudes Survey Reference

### Matched Guise Technique — Full Protocol

**Recording protocol**:
1. Recruit 1 bilingual speaker (native-like competence in both varieties)
2. Record same passage twice: once in variety A, once in variety B
3. Mix stimuli with "fillers" (recordings from other speakers)
4. Counterbalance order across participants

**Evaluation scales** (standard):
```
Rate this speaker on the following traits (1 = not at all, 7 = very much):

STATUS dimension:         SOLIDARITY dimension:      DYNAMISM:
  Educated / Uneducated     Friendly / Unfriendly     Active / Passive
  Intelligent / Unintelligent Warm / Cold              Enthusiastic / Boring
  Ambitious / Unambitious   Trustworthy / Untrustworthy Confident / Insecure
  Successful / Unsuccessful Kind / Unkind
```

**Analysis**:
```r
# Compare ratings across guises (paired samples, same participants)
# Use multilevel model (participants as random effect)
library(lme4)
m <- lmer(status_rating ~ guise + (1 | participant) + (1 | rater_age),
          data = dat)
```

### Self-Report Language Use Scales

```
For each language (English / Heritage language), rate:
                        English    Heritage
How well do you speak?  1234       1234
How well do you understand? 1234   1234
How well do you read?   1234       1234
How well do you write?  1234       1234

Scale: 1=Not at all, 2=Not well, 3=Well, 4=Very well

How often do you use this language with:
                        English    Heritage
Parents?                12345      12345
Siblings?               12345      12345
Friends?                12345      12345
Coworkers?              12345      12345
TV/Media?               12345      12345

Scale: 1=Never, 2=Rarely, 3=Sometimes, 4=Often, 5=Always
```

---

## Python Acoustic Analysis Reference

### Parselmouth — Praat Bindings in Python

```python
# pip install praat-parselmouth pandas numpy
import parselmouth
import numpy as np
import pandas as pd
import glob, os

def extract_formants(wav_path: str, textgrid_path: str,
                     max_formant: float = 5500.0) -> pd.DataFrame:
    """
    Extract F1, F2, F3 at midpoint of each labeled interval.
    max_formant: 5500 for women; 5000 for men (or 5000 general default)
    """
    snd     = parselmouth.Sound(wav_path)
    tg      = parselmouth.read(textgrid_path)
    formant = snd.to_formant_burg(
        max_number_of_formants=5,
        maximum_formant=max_formant,
        window_length=0.025,
        pre_emphasis_from=50.0)
    records = []
    tier = tg.get_tier_by_name("phones")   # adjust tier name as needed
    for interval in tier.intervals:
        if interval.text and interval.text not in ["", "sp", "SIL", "sil"]:
            t_mid = (interval.start_time + interval.end_time) / 2
            dur   = interval.end_time - interval.start_time
            records.append({
                "file":     os.path.basename(wav_path),
                "phone":    interval.text,
                "t_mid":    round(t_mid, 4),
                "duration": round(dur, 4),
                "F1":       formant.get_value_at_time(1, t_mid),
                "F2":       formant.get_value_at_time(2, t_mid),
                "F3":       formant.get_value_at_time(3, t_mid),
            })
    return pd.DataFrame(records)

# Batch extraction from paired WAV + TextGrid files
rows = []
for wav in sorted(glob.glob("audio/*.wav")):
    tg = wav.replace(".wav", ".TextGrid")
    if os.path.exists(tg):
        rows.append(extract_formants(wav, tg))
formants_df = pd.concat(rows, ignore_index=True)
# Remove extreme outliers (>3 SD from speaker mean)
for col in ["F1", "F2"]:
    mean = formants_df.groupby("speaker")[col].transform("mean")
    std  = formants_df.groupby("speaker")[col].transform("std")
    formants_df = formants_df[np.abs(formants_df[col] - mean) <= 3 * std]
formants_df.to_csv("${OUTPUT_ROOT}/ling/tables/formants_raw.csv", index=False)
```

### Parselmouth — VOT Extraction

```python
def extract_vot(wav_path: str, textgrid_path: str,
                stops: list = ["p","t","k","b","d","g"]) -> pd.DataFrame:
    """Extract Voice Onset Time from stop + vowel pairs in TextGrid."""
    snd     = parselmouth.Sound(wav_path)
    tg      = parselmouth.read(textgrid_path)
    records = []
    tier    = tg.get_tier_by_name("phones")
    intervals = list(tier.intervals)
    for i, interval in enumerate(intervals):
        if interval.text in stops and i + 1 < len(intervals):
            following = intervals[i + 1]
            # Find first voicing onset using pitch
            t_stop_end = interval.end_time
            t_next_end = following.end_time
            pitch_obj  = snd.to_pitch_ac(time_step=0.001, pitch_floor=75,
                                          pitch_ceiling=400)
            vot = None
            for t in np.arange(t_stop_end, t_next_end, 0.001):
                if not np.isnan(pitch_obj.get_value_at_time(t)):
                    vot = (t - t_stop_end) * 1000  # ms
                    break
            records.append({"file": os.path.basename(wav_path),
                             "stop": interval.text,
                             "following": following.text,
                             "VOT_ms": vot})
    return pd.DataFrame(records)
```

---

### librosa — F0 (Pitch) and Prosody

```python
# pip install librosa soundfile
import librosa, numpy as np, pandas as pd

def extract_pitch(wav_path: str, fmin: float = 75, fmax: float = 400) -> pd.DataFrame:
    """Extract F0 trajectory using PYIN algorithm."""
    y, sr = librosa.load(wav_path, sr=None)
    f0, voiced_flag, voiced_probs = librosa.pyin(
        y, fmin=fmin, fmax=fmax, sr=sr, frame_length=2048)
    times = librosa.times_like(f0, sr=sr)
    return pd.DataFrame({"time": times, "f0": f0, "voiced": voiced_flag,
                          "voiced_prob": voiced_probs})

def prosody_summary(wav_path: str) -> dict:
    """Compute utterance-level prosodic summary statistics."""
    y, sr = librosa.load(wav_path, sr=None)
    f0, voiced, _ = librosa.pyin(y, fmin=75, fmax=400, sr=sr)
    f0_voiced = f0[voiced & ~np.isnan(f0)]
    # Speaking rate: syllable nuclei via RMS peak counting (rough proxy)
    rms  = librosa.feature.rms(y=y, frame_length=2048, hop_length=512)[0]
    n_peaks = int(np.sum(rms > np.percentile(rms, 70)))
    dur_s   = librosa.get_duration(y=y, sr=sr)
    return {"file":          os.path.basename(wav_path),
            "f0_mean_hz":    float(np.nanmean(f0_voiced)) if len(f0_voiced) else np.nan,
            "f0_sd_hz":      float(np.nanstd(f0_voiced))  if len(f0_voiced) else np.nan,
            "f0_range_hz":   float(np.nanmax(f0_voiced) - np.nanmin(f0_voiced)) if len(f0_voiced) else np.nan,
            "speech_rate_proxy": float(n_peaks / dur_s)}

# Batch prosody
results = [prosody_summary(f) for f in glob.glob("audio/*.wav")]
pd.DataFrame(results).to_csv("${OUTPUT_ROOT}/ling/tables/prosody-summary.csv", index=False)
```

---

## quanteda.textstats Quick Reference

| Function | Purpose | Key arguments |
|---------|---------|---------------|
| `textstat_summary()` | Token / sentence count per doc | `corp` |
| `textstat_lexdiv()` | TTR, MTLD, HD-D | `dfmat`, `measure=c("TTR","MTLD")` |
| `textstat_readability()` | Flesch, FOG, Dale-Chall | `corp`, `measure=c("Flesch","FOG")` |
| `textstat_keyness()` | G² / χ² keyness vs. reference | `dfm`, `target=`, `measure="lr"` |
| `textstat_collocations()` | PMI / t-test collocations | `toks`, `size=2:3`, `min_count=10` |
| `textstat_dist()` | Cosine / euclidean distance between docs | `dfmat`, `method="cosine"` |
| `textstat_simil()` | Cosine similarity matrix | `dfmat`, `method="cosine"` |
| `textstat_frequency()` | Term frequency + docfreq | `dfmat`, `n=`, `groups=` |

```r
# Common pipeline
library(quanteda); library(quanteda.textstats)

corp  <- corpus(df, text_field = "text")
toks  <- tokens(corp, remove_punct = TRUE) |> tokens_tolower() |>
         tokens_remove(stopwords("en"))
dfmat <- dfm(toks) |> dfm_trim(min_termfreq = 5)

# All stats in one pass
summary_stats  <- textstat_summary(corp)
lexdiv_stats   <- textstat_lexdiv(dfmat, measure = c("TTR","MTLD"))
readabil_stats <- textstat_readability(corp, measure = c("Flesch","FOG","Dale.Chall"))

# Save
write.csv(summary_stats,  "${OUTPUT_ROOT}/ling/tables/corpus-summary.csv")
write.csv(lexdiv_stats,   "${OUTPUT_ROOT}/ling/tables/lexdiv.csv")
write.csv(readabil_stats, "${OUTPUT_ROOT}/ling/tables/readability.csv")
```

---

## conText Quick Reference (R package)

| Function | Purpose |
|---------|---------|
| `tokens_context(toks, pattern, window)` | Extract ±window token contexts around target |
| `dem(toks_ctx, pre_trained)` | Build document-embedding matrix (DEM) |
| `dem_group(dem, groups)` | Average DEM within groups → group ALC embeddings |
| `nns(dem_group, pre_trained, N)` | Nearest semantic neighbors for each group |
| `cos_sim(vec_a, vec_b)` | Cosine similarity between two embedding vectors |
| `nns_ratio(dem_group, numerator, denominator)` | Ratio of NNS scores: which words favor group A vs. B? |
| `ncs(dem_group, contexts_search, pre_trained)` | Nearest context sentences |
| `conText(formula, data, pre_trained)` | ALC regression: group/covariate → embedding space |

```r
# Minimal reproducible conText example
library(conText)
data(cr_glove_subset); data(cr_corpus); data(cr_party)
toks     <- tokens(cr_corpus) |> tokens_tolower()
toks_ctx <- tokens_context(toks, pattern = "immigr*", window = 6L)
dem_imm  <- dem(toks_ctx, pre_trained = cr_glove_subset, transform = TRUE)
dem_grp  <- dem_group(dem_imm, groups = cr_party)
nns(dem_grp, pre_trained = cr_glove_subset, N = 5, as_list = TRUE)
```
