---
name: scholar-compute
description: "Design and execute computational social science analyses: text-as-data/NLP (STM, BERTopic dynamic topics, text scaling via Wordfish/Wordscores, BERT, embedding regression via conText, LLM annotation with Lin & Zhang 2025 risk framework, Design-based Supervised Learning (DSL/Egami) for bias-corrected downstream regression from predicted annotations, multilingual NLP via XLM-RoBERTa/mBERT for cross-lingual text analysis and multilingual topic modeling), machine learning (supervised ML, Double ML, Causal Forests, Bayesian regression with brms/Stan, conformal prediction for distribution-free uncertainty quantification via mapie/conformalInference), network analysis (ERGMs, SAOMs, relational event models via goldfish/relevent, GNN/node embeddings via node2vec/GCN/GraphSAGE with PyTorch Geometric for link prediction and node classification), agent-based modeling (Mesa 3.x with AgentSet/PropertyLayer API, NetLogo/nlrx, LLM-powered agents, ODD, SALib), computer vision (DINOv2, CLIP, ConvNeXt, ViT, multimodal LLMs, VideoMAE, multimodal text+image fusion with late/early/hybrid strategies), LLM-powered analysis workflows (structured extraction, CoT coding, computational grounded theory, RAG/document QA), LLM synthetic data generation (persona/context engineering, silicon sampling, survey and vignette simulation, organizational/group behavior simulation, multi-agent opinion dynamics), geospatial and spatial analysis (sf, tidycensus, spdep, spatialreg, Moran's I, spatial lag/error/SEM models, LISA maps), audio as data (Essentia statistical feature extraction: MFCCs/spectral/rhythm/mood; librosa preprocessing; Whisper/faster-whisper transcription with speaker diarization via pyannote; post-transcription NLP pipeline routed to MODULE 1; LLM-native audio analysis via Gemini 1.5 Pro + GPT-4o audio; PANNs/AudioCLIP/wav2vec2 audio classification; social science use cases: political speeches, oral history, broadcast news, music as culture), life-event sequence modeling (life2vec: transformer-based representation learning for individual life-trajectories from administrative/survey panel data; BERT-like encoder with Time2Vec temporal encoding; MLM + SOP pretraining on synthetic life-language; finetuning for mortality prediction, personality nuances, and arbitrary downstream outcomes; concept space visualization via PaCMAP; TCAV interpretability; PU-learning for censored outcomes; Savcisens et al. 2024 Nature Computational Science). Runs per-module verification subagents. Saves an internal log and a publication-ready Methods + Results document. Targets Nature Computational Science, Science Advances, and computational sociology venues."
tools: Read, Bash, Write, WebSearch
argument-hint: "[text|network|ml|abm|reproduce|spatial|bayesian|dsl|audio|life2vec] [description of data and research question]"
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
| `life2vec`, `life event`, `life sequence`, `life trajectory`, `event sequence`, `life course transformer`, `life outcome prediction`, `administrative data transformer`, `registry data transformer`, `person embedding`, `concept space`, `life-event embedding` | MODULE 11 |
| `bertopic`, `dynamic topics`, `hierarchical topics`, `topic over time` | MODULE 1 (Step 3b) |
| `wordfish`, `wordscores`, `text scaling`, `political positions`, `ideological scaling` | MODULE 1 (Step 3c) |
| `multilingual`, `cross-lingual`, `xlm-roberta`, `mbert`, `language detection`, `multilingual topic`, `cross-lingual transfer`, `multilingual nlp` | MODULE 1 (Step 3d) |
| `dsl`, `design supervised learning`, `bias correction annotation`, `predicted variable regression`, `predicted labels regression` | MODULE 1 (Step 8) |
| `bayesian`, `brms`, `stan`, `mcmc`, `posterior predictive`, `credible interval`, `prior`, `bayes factor`, `hierarchical bayes` | MODULE 2 (Step 5b) |
| `conformal`, `conformal prediction`, `prediction set`, `prediction interval`, `coverage guarantee`, `mapie`, `uncertainty quantification` | MODULE 2 (Step 5c) |
| `gnn`, `node embedding`, `node2vec`, `graphsage`, `gcn`, `graph neural`, `link prediction`, `node classification` | MODULE 3 (Step 2b) |
| `multimodal`, `multimodal fusion`, `text image`, `clip fusion`, `late fusion`, `early fusion`, `text-image alignment` | MODULE 6 (Step 7b) |

If multiple modules apply, run them in sequence. If unclear, ask the user to specify.

**Text-as-data ambiguity:** If the request involves *linguistic* variables or sociolinguistic theory (e.g., embedding regression on /t/-deletion, LLM annotation for phonological features, language attitudes), route to `/scholar-ling` instead. See `_shared/dispatch-precedence.md` for the full disambiguation table.

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
if (file.exists(viz_path)) source(viz_path) else stop("viz_setting.R not found at ", viz_path, " — do NOT define theme_Publication inline")
# Provides: theme_Publication(), scale_fill/colour_Publication() (Wong 2011),
#   scale_fill_continuous/diverging_Publication(), set_geom_defaults_Publication(),
#   assemble_panels(), save_fig_cmyk(), preview_grayscale()
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

Follow the script version control protocol defined in `.claude/skills/_shared/script-version-check.md`. **NEVER overwrite an existing script.**

1. **Consolidate** all R/Python code from the module into self-contained script(s)
2. **Add standard header** to each script:
   ```python
   # ============================================================
   # Script: [prefix]-[module-name][-vN].[ext]
   # Version: [v1 | v2 | v3 ...]
   # Purpose: [one-line description]
   # Module: MODULE [N] — [module name]
   # Input:   [data file or prior output]
   # Output:  [models, tables, figures produced]
   # Date:    [YYYY-MM-DD]
   # Seed:    42 (set in all stochastic steps)
   # Changes: [if v2+, one-line summary of what changed from prior version]
   # Key params: [K=20, window=6, n_estimators=500, etc.]
   # ============================================================
   ```
3. **Version-check before saving**: Run this before EVERY script Write tool call:
   ```bash
   OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
   SCRIPT_NAME="20-stm-topic-model"  # Replace with actual
   EXT="R"
   SCRIPT_BASE="${OUTPUT_ROOT}/scripts/${SCRIPT_NAME}"
   if [ -f "${SCRIPT_BASE}.${EXT}" ]; then
     V=2; while [ -f "${SCRIPT_BASE}-v${V}.${EXT}" ]; do V=$((V + 1)); done
     SCRIPT_BASE="${SCRIPT_BASE}-v${V}"
   fi
   echo "SCRIPT_PATH=${SCRIPT_BASE}.${EXT}"
   ```
   **Use the printed `SCRIPT_PATH` in the Write tool call.** Shell variables do NOT persist — re-derive in every call.
4. **Save** to the versioned path from step 3, using the module numbering ranges below
5. **Append decision entries** to `output/[slug]/scripts/coding-decisions-log.md`:
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
| `100-109` | MODULE 11: Life2Vec | `100-life2vec-preprocess.py`, `101-life2vec-pretrain.py` |

**No-data mode:** Save scripts with `# [CODE-TEMPLATE] — run when data available` as the first line after the header.

---


## Module Loading (On-Demand)

Each module is stored in a separate reference file. After routing to the correct module(s) in Step 2 above, load ONLY the matched module(s):

```bash
SKILL_DIR="${SCHOLAR_SKILL_DIR:-.}/.claude/skills/scholar-compute/references"
cat "$SKILL_DIR/module-NN-name.md"
```

| Module | File |
|--------|------|
| MODULE 1: Text-as-Data / NLP | `module-01-nlp.md` |
| MODULE 2: Machine Learning | `module-02-ml.md` |
| MODULE 3: Network Analysis | `module-03-network.md` |
| MODULE 4: Agent-Based Modeling | `module-04-abm.md` |
| MODULE 5: Computational Reproducibility | `module-05-reproducibility.md` |
| MODULE 6: Computer Vision | `module-06-cv.md` |
| MODULE 7: LLM-Powered Analysis | `module-07-llm-analysis.md` |
| MODULE 8: LLM Synthetic Data | `module-08-synthetic-data.md` |
| MODULE 9: Geospatial Analysis | `module-09-geospatial.md` |
| MODULE 10: Audio as Data | `module-10-audio.md` |
| MODULE 11: Life-Event Sequence (life2vec) | `module-11-life2vec.md` |

**Do NOT load all modules.** Only `cat` the file(s) for the routed module(s). If multiple modules apply, load them sequentially.

After loading and executing the module, continue with the Quality Checklist and Save Output sections below.

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

### Version Collision Avoidance (MANDATORY)

**Before EVERY Write tool call below**, run this Bash block to determine the correct save path. Do NOT hardcode paths from the filename templates — they show naming patterns only.

```bash
# MANDATORY: Replace [values] with actuals before running
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
# BASE pattern: ${OUTPUT_ROOT}/[slug]/compute/scholar-compute-log-[topic-slug]-[YYYY-MM-DD]
# Split into directory and stem for the gate script:
OUTDIR="$(dirname "${OUTPUT_ROOT}/[slug]/compute/scholar-compute-log-[topic-slug]-[YYYY-MM-DD]")"
STEM="$(basename "${OUTPUT_ROOT}/[slug]/compute/scholar-compute-log-[topic-slug]-[YYYY-MM-DD]")"
mkdir -p "$OUTDIR"
bash "${SCHOLAR_SKILL_DIR:-.}/scripts/gates/version-check.sh" "$OUTDIR" "$STEM"
```

**Use the printed `SAVE_PATH` as `file_path` in the Write tool call.** Re-run this block (with the appropriate BASE) for each additional file. The same version suffix must be used for all related output files (.md, .docx, .tex, .pdf).

For File 2, change the BASE to:
`${OUTPUT_ROOT}/[slug]/compute/scholar-compute-results-[topic-slug]-[YYYY-MM-DD]`

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

### Knowledge Graph Write-Back (post-save)

```bash
SKILL_DIR="${SCHOLAR_SKILL_DIR:-.}/.claude/skills"
KG_REF="$SKILL_DIR/scholar-knowledge/references/knowledge-graph-search.md"
if [ -f "$KG_REF" ]; then
  eval "$(cat "$KG_REF" | sed -n '/^```bash/,/^```/p' | sed '1d;$d')" 2>/dev/null
  if kg_available 2>/dev/null; then
    echo ""
    echo "═══ Knowledge Graph ═══"
    echo "File computational findings back into the knowledge graph:"
    echo "  /scholar-knowledge ingest from output [output-file-path]"
  fi
fi
```

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
