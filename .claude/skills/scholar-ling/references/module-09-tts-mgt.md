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

