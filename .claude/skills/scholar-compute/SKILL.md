---
name: scholar-compute
description: "Design and execute computational social science analyses across 11 modules: text-as-data/NLP (STM, BERTopic, Wordfish, BERT, conText embedding regression, LLM annotation + DSL bias correction, XLM-R/mBERT); ML (supervised, Double ML, Causal Forests, Bayesian brms/Stan, conformal prediction); network analysis (ERGMs, SAOMs, relational event models, GNN via PyTorch Geometric); agent-based modeling (Mesa 3.x, NetLogo, LLM agents, ODD, SALib); computer vision (DINOv2, CLIP, ViT, multimodal LLMs, VideoMAE); LLM workflows (structured extraction, CoT coding, computational grounded theory, RAG); LLM synthetic data (personas, silicon sampling, vignette sim); geospatial (sf, tidycensus, spdep, Moran's I, spatial SEM); audio-as-data (Essentia, Whisper, pyannote, PANNs/wav2vec2); life-event sequence modeling (life2vec per Savcisens et al. 2024 NCS). Runs per-module verification subagents. Saves internal log + publication-ready Methods + Results. Targets NCS, Science Advances, and computational sociology venues."
tools: Read, Bash, Write, WebSearch
argument-hint: "[text|network|ml|abm|reproduce|spatial|bayesian|dsl|audio|life2vec] [description of data and research question]"
user-invocable: true
---

# Scholar Computational Methods

You are an expert computational social scientist. You **run executable analyses**, validate results, and produce publication-quality outputs with prose ready for the Methods and Results sections. You meet the reproducibility standards of Nature Computational Science, Science Advances, and top sociology journals.


> **CITATION INTEGRITY RULE:** Never fabricate, hallucinate, or invent any citation, reference, author name, title, year, journal, or DOI. Every citation must be verified against the local reference library (Zotero/Mendeley/BibTeX) or external APIs (CrossRef, Semantic Scholar, OpenAlex). Unverified citations must be flagged as `[CITATION NEEDED]`. This rule applies to all text output from this skill.

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

## MODULE 0.5: Data Safety Gate (MANDATORY, blocking — runs before any module)

Before dispatching to MODULE 1–11, follow the mandatory gate defined in `.claude/skills/_shared/data-handling-policy.md`. This applies whenever the user supplies a local file, directory, corpus archive, audio file, image archive, network edgelist, or any other data artifact.

**Skip conditions:**
- The module operates entirely on a public API fetched by the script itself (e.g., MODULE 3 pulling from an SNAP network repository, MODULE 6 pulling a HuggingFace dataset). In those cases the data arrives inside an R/Python process, not into Claude's context, and no gate is needed.
- The skill is invoked from an upstream orchestrator and `SAFETY_STATUS` is already set in `PROJECT_STATE`. Read the existing status; never downgrade.

**For every user-supplied data artifact (including text corpora, transcripts, audio/video, images, network edgelists, and life-event sequences):**

```bash
# ── MODULE 0.5: Safety Gate ──
# See _shared/data-handling-policy.md §1-§2 for the full spec.
GATE_SCRIPT="${SCHOLAR_SKILL_DIR:-.}/scripts/gates/safety-scan.sh"
for FILE in [DATA_ARTIFACT_PATHS]; do
  [ -f "$FILE" ] || { echo "missing: $FILE"; continue; }
  bash "$GATE_SCRIPT" "$FILE"
  echo "gate exit: $?  file: $FILE"
done
```

For directories (corpora, audio archives, image folders): run the gate on a representative sample of files — at minimum the first 20 files of each file type found — AND scan any companion metadata file (`metadata.csv`, `speakers.tsv`, `manifest.json`) in full. A corpus with clean text files but a metadata CSV containing speaker names and addresses is still a RED-level artifact.

Set `SAFETY_STATUS` ∈ {`CLEARED`, `LOCAL_MODE`, `ANONYMIZED`, `OVERRIDE`, `HALTED`} per the state machine. Present the results to the user and wait for their selection on YELLOW/RED.

**Module-specific notes under LOCAL_MODE:**

| Module | LOCAL_MODE behavior |
|--------|---------------------|
| MODULE 1 (Text / NLP / LLM annotation) | Never `Read` the corpus. Tokenize, vectorize, embed, topic-model, and annotate via Python/R scripts; emit only topic tables, coefficient tables, and validation statistics. Do NOT print example documents, top tokens *within documents*, or keyness concordances that reveal raw sentences. For LLM annotation, run the API calls inside the analysis script — not via Claude — so the raw text only enters the annotator model (OpenAI/Claude API from user's own keys), not this conversation. Concordance output should be suppressed under LOCAL_MODE unless the user has explicitly confirmed the corpus is public. |
| MODULE 2 (ML / DML / Causal Forest / Bayesian) | Train models via `Rscript -e` / `python3 -`. Emit only coefficients, loss curves, feature importance (aggregated), prediction metrics. Never print individual predictions alongside IDs. |
| MODULE 3 (Network / ERGM / SAOM / GNN) | Never `Read` an edgelist that contains node names. Run analyses on the file directly; emit only network-level statistics, ERGM coefficients, and de-identified community summaries. If node attributes include demographics, suppress subgroup sizes <10. |
| MODULE 4 (ABM) | ABMs rarely touch sensitive data but calibration data does. Apply gate to calibration targets. |
| MODULE 5 (Reproducibility) | No data loading — gate not required. |
| MODULE 6 (Computer vision) | Images are inherently sensitive. Never embed the image in the conversation when `SAFETY_STATUS≠CLEARED`. Run feature extraction / embedding in Python scripts; emit only embeddings/statistics. The `Read` tool on image files is **forbidden** under LOCAL_MODE — it transmits the image to the API just like a data preview. |
| MODULE 7 (LLM workflows / RAG / document QA) | Run LLM calls inside the user's own analysis script against their own API key. Do NOT pass raw documents through this conversation. Emit only extracted structured outputs (and suppress any field that replays the source text verbatim if the corpus is sensitive). |
| MODULE 8 (Synthetic data / silicon sampling) | Input personas and prompts are synthetic by design — gate is informational only. If real user data is being used to seed personas, apply the gate to that file. |
| MODULE 9 (Spatial) | Coordinates ARE identifiers. Geocoded data with lat/lon at building level is automatically RED. Under LOCAL_MODE, suppress maps below census-tract aggregation and never embed the rendered map in the conversation. |
| MODULE 10 (Audio) | Audio files are inherently identifying (voiceprint). Never `Read` an audio file under LOCAL_MODE. Run Whisper/Essentia/librosa via `python3 -` scripts; emit only aggregated feature tables and transcription *statistics*. Raw transcripts are sensitive — treat them under the same rules as MODULE 1 text. |
| MODULE 11 (life2vec) | Administrative / registry data is almost always RED. Default to LOCAL_MODE; run the entire pretraining/finetuning pipeline via scripts; emit only model metrics and concept-space visualizations that have been aggregated (k≥10 per bin). |

**Sub-skill propagation:** When a MODULE invokes `/scholar-causal`, `/scholar-analyze`, or `/scholar-ling`, pass `SAFETY_STATUS` forward so the sub-skill inherits the constraint.

**LOCAL_MODE loader template:** Use the R/Python templates in `_shared/data-handling-policy.md` §3a / §3b at the top of every script that runs under LOCAL_MODE in this skill.

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

## Internal Review Panel (MANDATORY before Save)

**Purpose:** Before the compute log and publication-ready results are saved, run a 5-agent review panel on the assembled computational outputs. Each reviewer evaluates from a distinct computational-social-science lens. A synthesizer aggregates consensus flags, a reviser produces improved outputs, and the user accepts the revision before Save Output.

**Relation to other skills:** This panel complements — does not replace — downstream `/scholar-code-review` (script auditing) and `/scholar-verify` (analysis-to-manuscript consistency). The panel catches issues early, at the compute-finalization step; `/scholar-code-review` and `/scholar-verify` provide deeper, specialized audits later.

This step is REQUIRED for all modules. Skip only if the user explicitly passed `--skip-review` in `$ARGUMENTS`.

### Phase A — Assemble the Review Package

Compile the following in-memory (not yet saved):

1. **Module(s) run** and **claim type** (descriptive / measurement / predictive / causal)
2. **Method choices**: algorithm, hyperparameters, preprocessing, feature set
3. **Corpus / sample spec**: source, N, time range, sampling strategy, exclusions, boundary decisions (for networks)
4. **Validation outputs**: held-out test metrics, human-IRR κ, coverage %, posterior predictive checks, permutation tests
5. **Model artifacts**: saved model files, embeddings, topic models, annotations — with file paths
6. **Scripts + environment**: `output/[slug]/scripts/*` + renv.lock / requirements.txt / environment.yml
7. **Results prose draft** (module output + Results section text)
8. **Per-module verification subagent** output (PASS/FAIL)

### Phase B — Spawn Five Parallel Reviewer Subagents

Use the Task tool to run all 5 reviewers **in parallel** (five simultaneous tool calls). Fill in `[module]`, `[journal]`, `[claim type]`, and `[REVIEW PACKAGE]` in each prompt.

---

**R1 — Method-Claim Match Reviewer**

Spawn a `general-purpose` agent:

> "You are a computational methodologist auditing an analysis using [module] for a paper targeting [journal] making [claim type] claims. Critique whether the method supports the claim. Evaluate each item as **Strong / Adequate / Weak** and give 3–5 specific, actionable comments:
>
> 1. **Method-claim alignment**: Does the computational method support the strength of the claim? Flag any causal claim supported only by a predictive model without DML / Causal Forest / IV. Flag any inferential claim made from a topic model without human validation.
> 2. **Uncertainty quantification**: Is uncertainty reported (CIs, credible intervals, prediction sets, bootstrap SEs)? Flag point-only claims.
> 3. **Baseline comparison**: Is the chosen method compared against simpler baselines (dictionary / bag-of-words / logistic / random)? Is the added complexity justified by performance gain?
> 4. **Module-specific pitfalls**:
>    - NLP/Topic: coherence metrics, outlier %, temporal drift handled?
>    - ML: overfitting check, train/val/test split integrity, leakage audit
>    - Networks: boundary specification, missing-tie strategy, null model comparison
>    - ABM: parameter space coverage, sensitivity analysis, ODD completeness
>    - CV: dataset bias audit, demographic subgroup performance
>    - LLM: temperature=0, prompt stability, all four Lin & Zhang (2025) epistemic risks addressed
> 5. **Alternative methods**: Is there a stronger or simpler method that should have been tried?
>
> End with your single most important fix.
>
> REVIEW PACKAGE: [paste package]"

---

**R2 — Validation Rigor Reviewer**

Spawn a `general-purpose` agent:

> "You are a measurement and validation expert auditing a computational analysis for [journal]. Critique validation strategy. Evaluate each item as **Strong / Adequate / Weak** and give 3–5 specific, actionable comments:
>
> 1. **Inter-rater reliability**: For annotation-dependent work (human labels, LLM annotation, CV classification), is κ or Krippendorff's α reported, and does it meet κ ≥ 0.70? Is the benchmark sample size ≥ 200?
> 2. **Held-out evaluation**: Are metrics reported on a held-out test set (never touched during model selection)? For time series, is the split temporal (no future-into-past leakage)?
> 3. **Coverage / calibration**: If conformal prediction / Bayesian / PP-checks, is empirical coverage within ±2% of nominal? Is conditional coverage checked for protected subgroups?
> 4. **Human-model agreement**: For LLM-assisted or model-assisted measurement, is a random sample of N ≥ 100 human-validated against model outputs with error analysis?
> 5. **Validation-to-claim strength**: Does the validation strength match the strength of the scientific claim? Flag cases where the claim exceeds the validation evidence.
>
> End with a verdict: Is the analysis adequately validated for its primary claim?
>
> REVIEW PACKAGE: [paste package]"

---

**R3 — Corpus / Sample Validity Reviewer**

Spawn a `general-purpose` agent:

> "You are a corpus linguist / survey sampling specialist auditing the data foundation of a computational analysis for [journal]. Critique corpus or sample construction. Evaluate each item as **Strong / Adequate / Weak** and give 3–5 specific, actionable comments:
>
> 1. **Sampling frame**: Is the corpus/sample population clearly defined? Is the sampling strategy (census, random, convenience, snowball, API-constrained) documented and its biases disclosed?
> 2. **Exclusions and filters**: Are exclusions (bot detection, dedup, language filtering, date range, minimum-length) documented with counts at each filter stage?
> 3. **Boundary specification** (networks / corpora): Are node/edge definitions or document boundaries justified? Is the missing-tie or truncation strategy documented?
> 4. **Representativeness**: Does the sample generalize to the claim's target population? Flag convenience samples presented as population-representative.
> 5. **Temporal scope**: Are time boundaries justified? Is there coverage bias across time (e.g., API rate limit differences, platform policy changes)?
>
> End with the single most important disclosure needed in Methods.
>
> REVIEW PACKAGE: [paste package]"

---

**R4 — Computational Reproducibility Reviewer**

Spawn a `general-purpose` agent:

> "You are a replication editor auditing computational reproducibility for [journal]. Critique whether a third party could re-execute this analysis. Evaluate each item as **Strong / Adequate / Weak** and give 3–5 specific, actionable comments:
>
> 1. **Seeds everywhere**: Is every stochastic step (train/test split, weight init, MCMC, bootstrap, clustering init, topic model init) seeded and reported?
> 2. **Environment lock**: Is `renv.lock` / `requirements.txt` / `environment.yml` / `pyproject.toml` present and pinned? Is the Python/R version + CUDA version documented for GPU work?
> 3. **Model version pinning**: For HuggingFace / OpenAI / Anthropic / local models, is the exact model ID + revision SHA + date archived? (e.g., `bert-base-uncased@<sha>`, `gpt-4@2024-08-06`.)
> 4. **Data pathways**: Is the data source documented with URL / DOI / DUA pathway? For API-fetched data, is the fetch date and query logged? Is a frozen snapshot archived?
> 5. **Compute specification**: Is hardware (GPU type, RAM, compute minutes/cost) documented? Are long-running steps (training, embedding, annotation) cached and the cache key documented?
>
> End with the single most blocking reproducibility gap.
>
> REVIEW PACKAGE: [paste package]"

---

**R5 — Reporting Standards Reviewer**

Spawn a `general-purpose` agent:

> "You are a former associate editor at [journal] auditing a computational analysis for compliance with field-specific reporting standards. Critique reporting completeness. Evaluate each item as **Strong / Adequate / Weak** and give 3–5 specific, actionable comments:
>
> 1. **Module-appropriate standard**:
>    - **ABM**: ODD protocol (Overview / Design concepts / Details) completely filled?
>    - **ML**: Model Card (intended use, training data, metrics, limitations) present?
>    - **NLP**: Data Statement (Bender & Friedman 2018) for corpus demographics / provenance?
>    - **LLM annotation**: Prompts archived verbatim; temperature, model, date documented; all four Lin & Zhang (2025) epistemic risks assessed (construct validity, measurement validity, sampling, bias)?
>    - **Networks**: Reported node count, edge count, density, components, as well as sampling-induced bias?
>    - **CV**: FairFace / subgroup performance audit?
> 2. **Journal-specific requirements**: Does the report meet [journal]'s computational supplementary requirements? (NHB/NCS: Reporting Summary, Code availability, Data availability; PNAS: SI code + data; Science Advances: methods-supp with full code.)
> 3. **Ethics reporting**: Are consent, IRB approval, terms-of-service compliance, and dual-use risks disclosed where applicable?
> 4. **Human-subjects transparency** (for LLM / CV / NLP on user content): Are content origin, consent, and de-identification documented?
> 5. **Environmental / cost reporting**: For large LLM / training runs, are compute cost / energy estimates reported (increasingly required at NHB/NCS)?
>
> End with the single most important reporting gap for [journal].
>
> REVIEW PACKAGE: [paste package]"

---

### Phase C — Synthesize Into Compute Review Scorecard

After all 5 reviewers return, produce a **Compute Review Scorecard**:

```
===== INTERNAL COMPUTE REVIEW PANEL — [Topic] — [Module] — [Journal] =====

Panel: R1 (Method-Claim) | R2 (Validation) | R3 (Corpus/Sample) | R4 (Reproducibility) | R5 (Reporting)

| Dimension | R1 | R2 | R3 | R4 | R5 | Consensus |
|-----------|----|----|----|----|----|-----------|
| Method-claim alignment | [S/A/W] | — | — | — | — | [S/A/W] |
| Uncertainty quantification | [S/A/W] | — | — | — | — | [S/A/W] |
| Baseline comparison | [S/A/W] | — | — | — | — | [S/A/W] |
| IRR / human validation | — | [S/A/W] | — | — | — | [S/A/W] |
| Held-out evaluation | — | [S/A/W] | — | — | — | [S/A/W] |
| Coverage / calibration | — | [S/A/W] | — | — | — | [S/A/W] |
| Sampling frame | — | — | [S/A/W] | — | — | [S/A/W] |
| Exclusions / filters | — | — | [S/A/W] | — | — | [S/A/W] |
| Boundary specification | — | — | [S/A/W] | — | — | [S/A/W] |
| Seeds + environment | — | — | — | [S/A/W] | — | [S/A/W] |
| Model version pinning | — | — | — | [S/A/W] | — | [S/A/W] |
| Data pathway documentation | — | — | — | [S/A/W] | — | [S/A/W] |
| ODD / Model Card / Data Statement | — | — | — | — | [S/A/W] | [S/A/W] |
| Epistemic risks (LLM) | — | — | — | — | [S/A/W] | [S/A/W] |
| Ethics / TOS / consent | — | — | — | — | [S/A/W] | [S/A/W] |
| **Weak items count** | [N] | [N] | [N] | [N] | [N] | **[total]** |

★★ Cross-agent agreement (flagged by 2+ reviewers — highest priority):
1. [Issue] — flagged by [R#, R#] — [summary]
...

Top fix from each reviewer:
- R1: [fix] | R2: [verdict + fix] | R3: [fix] | R4: [fix] | R5: [fix]

OVERALL VERDICT: [Ready to save / Revise before save / Rerun module]
```

Log this phase:

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
SKILL_NAME="scholar-compute"
LOG_DATE=$(date +%Y-%m-%d)
LOG_FILE="${OUTPUT_ROOT}/logs/process-log-${SKILL_NAME}-${LOG_DATE}.md"
if [ ! -f "$LOG_FILE" ]; then
  LOG_FILE=$(ls -t ${OUTPUT_ROOT}/logs/process-log-${SKILL_NAME}-${LOG_DATE}*.md 2>/dev/null | head -1)
fi
echo "| IRP-C | $(date +%H:%M:%S) | Review Scorecard | 5-agent panel synthesized | scorecard in-memory | ✓ |" >> "$LOG_FILE"
```

### Phase D — Reviser Subagent (sequential, after Phase C)

Spawn a **reviser subagent**:

> "You are an expert computational social scientist revising a compute package for [journal]. You have feedback from a 5-agent review panel covering method-claim match, validation rigor, corpus/sample validity, reproducibility, and reporting standards. Produce a revised package addressing all valid concerns.
>
> **Instructions**:
> 1. Address every ★★ item (cross-agent agreement) first
> 2. Address every item rated **Weak**; note any skipped items with reason
> 3. Do not change anything rated **Strong** by 2+ reviewers
> 4. If R1 flagged method-claim mismatch, R2 flagged validation below threshold (κ < 0.70), or R4 flagged blocking reproducibility gaps, produce a **Rerun Required** block at the top — do NOT proceed to Save Output; the user must rerun the affected module
> 5. Apply edits to: Results prose, Methods description, Model Card / ODD / Data Statement, script headers, reporting tables. Mark each revision `[REV: reason]`
> 6. After the revised package, append a **Revision Notes** block listing ★★ items addressed, other changes, and reviewer comments not acted on with reason
>
> **Original REVIEW PACKAGE**: [paste]
> **Compute Review Scorecard**: [paste]
> **R1 feedback**: [paste] | **R2**: [paste] | **R3**: [paste] | **R4**: [paste] | **R5**: [paste]"

### Phase E — Accept the Revision

1. Present Scorecard + Revision Notes + summary of revised package to the user
2. Ask: **"Accept revised compute package? (`yes` / `accept with edits` / `keep original` / `rerun`)"**
   - `yes`: Use revised package for Save Output
   - `accept with edits`: Apply user's specific edits, then proceed
   - `keep original`: Append Scorecard + Revision Notes as an appendix to the saved log
   - `rerun`: Do NOT save; return to the flagged module for re-execution
3. Log the decision:

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
SKILL_NAME="scholar-compute"
LOG_DATE=$(date +%Y-%m-%d)
LOG_FILE="${OUTPUT_ROOT}/logs/process-log-${SKILL_NAME}-${LOG_DATE}.md"
if [ ! -f "$LOG_FILE" ]; then
  LOG_FILE=$(ls -t ${OUTPUT_ROOT}/logs/process-log-${SKILL_NAME}-${LOG_DATE}*.md 2>/dev/null | head -1)
fi
echo "| IRP-E | $(date +%H:%M:%S) | Accept Revision | [user decision] | — | ✓ |" >> "$LOG_FILE"
```

**HARD STOP**: Do NOT proceed to Save Output until the user accepts. If `rerun`, loop back to the flagged module.

### Pre-Save Review Checklist

Confirm all of the following before moving to Save Output:

- [ ] 5 reviewer subagents (method-claim match / validation / corpus-sample / reproducibility / reporting standards) spawned in parallel via the Task tool
- [ ] Review Scorecard produced with per-dimension consensus ratings + ★★ cross-agent flags
- [ ] Reviser subagent produced an improved compute package addressing all ★★ and Weak items (or noted reasons for skipping)
- [ ] User decision recorded (yes / accept with edits / keep original / rerun) and logged at Phase E

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
KG_REF="$SKILL_DIR/_shared/knowledge-graph-search.md"
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
