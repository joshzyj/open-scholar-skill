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
import openai, base64, json
client = openai.OpenAI()

def encode_audio_b64(path: str) -> str:
    with open(path, "rb") as f:
        return base64.b64encode(f.read()).decode("utf-8")

def analyze_audio_gpt4o(audio_path: str, prompt: str,
                          model: str = "gpt-4o-audio-preview") -> dict:
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

