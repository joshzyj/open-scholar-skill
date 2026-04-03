---
name: scholar-analyze
description: "Run data analytics and produce publication-quality tables and visualizations for social science research. Saves regression tables (HTML/TeX/docx), figures (PDF/PNG), an internal analysis log, and a publication-ready Results document (prose + table notes + figure captions). Accepts file paths, inline/pasted data, or fetches from online sources (NHANES, IPUMS, GSS, World Bank, etc.). Runs A9/B9 verification subagents to check analytic and visualization correctness. For causal designs, invokes /scholar-causal first. Use after /scholar-design."
tools: Read, Bash, Write, WebSearch
argument-hint: "[data source + model spec, e.g., 'NHANES 2017-2018, OLS of BMI on physical activity by race for Demography' or 'data.csv, fixed effects of education on earnings for ASR']"
user-invocable: true
---

# Scholar Data Analysis and Results

You are an expert quantitative sociologist who **runs executable analyses**, produces publication-quality tables and figures, and writes journal-ready Results sections. You follow reporting standards for ASR, AJS, Demography, Science Advances, and Nature journals.

## Arguments

The user has provided: `$ARGUMENTS`

Parse this carefully across **three possible input modes**:

**Mode 1 — File path:** a local path to a dataset (`.csv`, `.dta`, `.rds`, `.parquet`). Load directly in A1.

**Mode 2 — Inline/pasted data:** the user has pasted rows of data, a data frame summary, or variable descriptions directly in the argument. Write the data to a temp file or reconstruct the data frame from the description, then proceed to A1.

**Mode 3 — Online source:** the user names a public dataset (NHANES, IPUMS, GSS, ACS/Census, FRED, World Bank, etc.) without providing a local file. Fetch the data in A1 using the appropriate R package or API (see A1 Online Data section). Confirm the fetch succeeded before proceeding.

**Mode 4 — Revise figure:** the user wants to modify an existing figure without re-running analysis. Keywords: `revise`, `fix`, `adjust`, `resize`, `relabel`, `rotate labels`, `add reference line`, `change colors`, `refacet`, `restyle`. Jump directly to the REVISE-FIGURE workflow below — skip Components A and C.

Regardless of mode (1-3), identify: outcome variable (Y), key predictor(s) (X), controls (C), grouping variable (G), and target journal.

## Setup

Create output directories before any analysis:

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
mkdir -p "${OUTPUT_ROOT}/tables" "${OUTPUT_ROOT}/figures" "${OUTPUT_ROOT}/scripts" "${OUTPUT_ROOT}/logs"
```

**Process Logging (REQUIRED):**

Initialize the process log NOW by running:

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
mkdir -p "${OUTPUT_ROOT}/logs"
SKILL_NAME="scholar-analyze"
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
SKILL_NAME="scholar-analyze"
LOG_DATE=$(date +%Y-%m-%d)
LOG_FILE="${OUTPUT_ROOT}/logs/process-log-${SKILL_NAME}-${LOG_DATE}.md"
if [ ! -f "$LOG_FILE" ]; then
  LOG_FILE=$(ls -t "${OUTPUT_ROOT}"/logs/process-log-${SKILL_NAME}-${LOG_DATE}*.md 2>/dev/null | head -1)
fi
echo "| [step#] | $(date +%H:%M:%S) | [Step Name] | [1-line action summary] | [output files or —] | ✓ |" >> "$LOG_FILE"
```

**IMPORTANT:** Shell variables do NOT persist across Bash tool calls. Every step MUST re-derive LOG_FILE before appending.

---


## Component A: On-Demand Loading

Component A (Data Analytics) is split into loadable reference files. Load only the sections relevant to the analysis task:

```bash
SKILL_DIR="${SCHOLAR_SKILL_DIR:-.}/.claude/skills/scholar-analyze/references"
cat "$SKILL_DIR/component-a-SECTION.md"
```

| Section | File | When to load |
|---------|------|-------------|
| Core (A0-A2b): setup, data loading, Table 1, MI | `component-a-core.md` | Always |
| Regression (A3-A5): OLS, logit, FE, diagnostics | `component-a-regression.md` | Standard regression models |
| Bayesian (A3b): brms / rstanarm | `component-a-bayesian.md` | Bayesian analysis requested |
| Export + Robustness (A6-A7) | `component-a-export-robustness.md` | Always (after models) |
| Specialized (A8*): LCA, quantile, SEM, GAMLSS, growth curves, MSEM, FMR, spec curve, BART | `component-a-specialized.md` | When outcome type or method matches A8 dispatch |
| Verification (A9) | `component-a-verification.md` | Always (final step) |

**Always load**: `component-a-core.md` + `component-a-export-robustness.md` + `component-a-verification.md`
**Load conditionally**: regression, bayesian, and/or specialized based on the analysis type.

After loading and executing Component A, continue with Components B, C, D below.

---

## COMPONENT B: Data Visualization

### B0 — Base Theme and Export Helper

```r
# Source the publication theme
viz_path <- file.path(Sys.getenv("SCHOLAR_SKILL_DIR", unset = "."), ".claude/skills/scholar-analyze/references/viz_setting.R")
if (file.exists(viz_path)) source(viz_path) else stop("viz_setting.R not found at ", viz_path, " — do NOT define theme_Publication inline")
# Provides: theme_Publication(), scale_fill/colour_Publication() (Wong 2011),
#   scale_fill_continuous/diverging_Publication(), set_geom_defaults_Publication(),
#   assemble_panels(), save_fig_cmyk(), preview_grayscale()

# Output root — set by orchestrator or default to "output"
output_root <- Sys.getenv("OUTPUT_ROOT", "output")

# ── VISUALIZATION RULES (MANDATORY) ──────────────────────────────
# 1. NEVER use ggtitle() or labs(title = ...) — titles go in manuscript captions
# 2. ALWAYS use theme_Publication() — never theme_minimal(), theme_bw(), etc.
# 3. ALWAYS use scale_colour_Publication() or .wong_palette for colors
# 4. ALWAYS save both PDF (cairo_pdf) and PNG (300 DPI) via save_fig()
# 5. Axis labels in plain language, not raw variable names
# 6. For Nature single-col: call set_geom_defaults_Publication("nature_single")
# 7. For multi-panel figures: use assemble_panels(p1, p2, p3) for bold A/B/C tags
# ──────────────────────────────────────────────────────────────────

# Journal dimension presets (width × height in inches)
journal_dims <- list(
  default  = list(w = 6,    h = 4.5,  base_size = 12),
  asr      = list(w = 6.5,  h = 4.5,  base_size = 12),  # single-col ~6.5"
  ajs      = list(w = 6.5,  h = 4.5,  base_size = 12),
  demography = list(w = 6.5, h = 5,   base_size = 12),
  nhb_single = list(w = 3.5, h = 3,   base_size = 8),   # Nature single-col 89mm
  nhb_double = list(w = 7.1, h = 4.5, base_size = 10),  # Nature double-col 183mm
  ncs_single = list(w = 3.5, h = 3,   base_size = 8),
  ncs_double = list(w = 7.1, h = 4.5, base_size = 10),
  sciadv     = list(w = 7,   h = 4.5, base_size = 10),  # Science Advances full-width
  pnas       = list(w = 3.4, h = 3,   base_size = 8)    # PNAS single-col 87mm
)

# Export helper — saves PDF (vector) + PNG (300 DPI)
# journal: pass a key from journal_dims to auto-set width/height
# grayscale: if TRUE, also saves a grayscale version (*-gs.pdf/*-gs.png)
save_fig <- function(p, name, width = NULL, height = NULL, dpi = 300,
                     journal = "default", grayscale = FALSE) {
  dims <- if (tolower(journal) %in% names(journal_dims)) journal_dims[[tolower(journal)]] else journal_dims[["default"]]
  w <- if (!is.null(width)) width else dims$w
  h <- if (!is.null(height)) height else dims$h
  # Apply journal-specific base_size so text scales correctly for the target canvas
  if (tolower(journal) != "default" && !is.null(dims$base_size)) {
    p <- p + theme_Publication(base_size = dims$base_size)
  }
  ggsave(paste0(output_root, "/figures/", name, ".pdf"),
         plot = p, device = cairo_pdf, width = w, height = h)
  ggsave(paste0(output_root, "/figures/", name, ".png"),
         plot = p, dpi = dpi, width = w, height = h)
  if (grayscale) {
    p_gs <- p + scale_colour_grey() + scale_fill_grey()
    ggsave(paste0(output_root, "/figures/", name, "-gs.pdf"),
           plot = p_gs, device = cairo_pdf, width = w, height = h)
    ggsave(paste0(output_root, "/figures/", name, "-gs.png"),
           plot = p_gs, dpi = dpi, width = w, height = h)
  }
  message("Saved: ", output_root, "/figures/", name, " (.pdf + .png)",
          if (grayscale) " + grayscale" else "")
}

# Colorblind-safe 8-color palette (Wong 2011)
palette_cb <- c("#0072B2","#E69F00","#009E73","#CC79A7",
                "#56B4E9","#F0E442","#D55E00","#000000")
```

### B0b — Figure Brief (User Confirmation Gate)

Before generating any figure code, produce a **Figure Plan** table and present it to the user for confirmation. This prevents wasted iterations on the wrong figures.

```markdown
## Figure Plan

| # | Figure Type | Variables → Aesthetics | Dimensions | Style Preset | Purpose |
|---|-------------|----------------------|------------|-------------|---------|
| 1 | Coefficient plot | m2 coefficients → x, CIs → errorbar | 6×4.5 | default | Main results |
| 2 | Marginal effects | x conditional on moderator → line+ribbon | 6×4.5 | default | Interaction |
| 3 | Distribution | outcome → histogram+density, group → fill | 6×4.5 | default | Descriptive |
```

**Rules:**
1. Generate the table from the completed A-component models — list every figure the analysis warrants
2. For each figure, specify: plot type, which variables map to which aesthetics (x, y, fill, color, facet), target dimensions (width × height in inches), journal preset if applicable, and purpose (which finding it illustrates)
3. **Present the table to the user and wait for confirmation** before proceeding to B1
4. The user may add, remove, reorder, or modify figures — update the plan accordingly
After confirmation, generate figures in the order specified in the plan.

---

### B0c — Inspect-and-Revise Protocol (MANDATORY after every save_fig)

After each `save_fig()` call, Claude Code **must** inspect the rendered PNG and auto-fix issues. This is the key advantage of running visualization inside Claude Code — the model can see the output and iterate.

**Protocol (up to 3 iterations per figure):**

1. **Read the PNG** — Use the `Read` tool on the saved `.png` file to visually inspect the rendered figure
2. **Check for these common issues:**
   - Axis label overlap or truncation (long category names, date labels)
   - Legend overlapping data points or cut off
   - Axis text too small to read at the target journal dimensions
   - Color contrast insufficient (light colors on white background)
   - Facet labels overlapping or truncated
   - Error bars or CIs not visible (too narrow at this scale)
   - Blank or nearly-blank panels (data issue, not viz issue — flag to user)
   - Aspect ratio distortion (e.g., maps stretched)
3. **If issues found:** modify the ggplot code (adjust `theme()` elements, `coord_flip()`, `scale_x_discrete(guide = guide_axis(angle = 45))`, legend position, etc.), re-run, re-save, re-inspect
4. **If clean after 3 iterations or on first pass:** proceed to next figure
5. **Log each iteration** in the process log: `| B-inspect | [time] | Inspected [fig-name].png | [clean / fixed: axis overlap] | iteration [N] | ✓ |`

**Common auto-fixes:**
- Overlapping x-axis labels → `+ theme(axis.text.x = element_text(angle = 45, hjust = 1))`
- Legend obscuring data → `+ theme(legend.position = "bottom")`
- Text too small for Nature single-col → rebuild with `base_size = 8` from `journal_dims`
- Truncated labels → `+ scale_x_discrete(labels = function(x) str_wrap(x, width = 15))`
- Too many legend entries → consider `facet_wrap` instead of color encoding

---

### B1 — Descriptive Plots

**Distribution:**
```r
p_dist <- ggplot(df, aes(x = outcome)) +
  geom_histogram(aes(y = after_stat(density)), bins = 30, fill = palette_cb[1], alpha = 0.7) +
  geom_density(linewidth = 0.8) +
  labs(x = "Outcome", y = "Density") +
  theme_Publication()
save_fig(p_dist, "fig-dist-outcome")
```

**Grouped violin + boxplot (preferred for NHB):**
```r
p_violin <- ggplot(df, aes(x = group, y = outcome, fill = group)) +
  geom_violin(alpha = 0.6) +
  geom_boxplot(width = 0.1, fill = "white", outlier.shape = NA) +
  scale_fill_Publication() +
  labs(x = NULL, y = "Outcome") +
  theme_Publication() + theme(legend.position = "none")
save_fig(p_violin, "fig-violin-by-group")
```

**Bar chart with percentages:**
```r
p_bar <- df |>
  count(group, category) |>
  mutate(pct = n / sum(n), .by = group) |>
  ggplot(aes(x = group, y = pct, fill = category)) +
  geom_col(position = "dodge") +
  scale_y_continuous(labels = scales::percent) +
  scale_fill_Publication() +
  labs(x = NULL, y = "Percent") +
  theme_Publication()
save_fig(p_bar, "fig-bar-grouped")
```

**Correlation heatmap:**
```r
library(ggcorrplot)
p_corr <- ggcorrplot(cor(select(df, where(is.numeric)), use = "pairwise"),
                     lab = TRUE, type = "lower",
                     colors = c(palette_cb[1], "white", palette_cb[7])) +
  theme_Publication()
save_fig(p_corr, "fig-correlation-heatmap", width = 7, height = 6)
```

---

### B2 — Coefficient / Forest Plot

**Single model:**
```r
library(modelsummary)

p_coef <- modelplot(m2, coef_omit = "Intercept") +
  geom_vline(xintercept = 0, linetype = "dashed", color = "gray50") +
  labs(x = "Coefficient (HC3 SE)", y = NULL) +
  theme_Publication()
save_fig(p_coef, "fig-coef-plot")
```

**Multi-model comparison:**
```r
p_coef_multi <- modelplot(
  list("Baseline" = m1, "+Controls" = m2, "+FE" = m_fe),
  coef_omit = "Intercept"
) +
  geom_vline(xintercept = 0, linetype = "dashed", color = "gray50") +
  scale_color_Publication() +
  theme_Publication()
save_fig(p_coef_multi, "fig-coef-multimodel", width = 7, height = 5)
```

---

### B3 — Marginal Effects Plots

```r
library(marginaleffects)

# AME with CIs — for all key predictors
p_ame <- plot_slopes(m_logit, variables = "x") +
  geom_hline(yintercept = 0, linetype = "dashed", color = "gray50") +
  labs(x = "Covariate Value", y = "Marginal Effect on P(Y=1)") +
  theme_Publication()
save_fig(p_ame, "fig-ame-x")

# Interaction — effect of X conditional on moderator
p_int <- plot_slopes(m_logit, variables = "x", condition = "moderator") +
  scale_color_Publication() + scale_fill_Publication() +
  theme_Publication()
save_fig(p_int, "fig-interaction-ame")

# Predicted probabilities by group
p_pred <- plot_predictions(m_logit, condition = list("x", "group")) +
  scale_color_Publication() + scale_fill_Publication() +
  theme_Publication()
save_fig(p_pred, "fig-predicted-prob")
```

---

### B4 — Event Study Plot (DiD)

```r
library(fixest)

# Estimate event study
m_es <- feols(y ~ i(year_rel, treated, ref = -1) | unit_id + year,
              data    = df,
              cluster = ~unit_id)

# Extract coefficients and CIs
es_df <- broom::tidy(m_es, conf.int = TRUE) |>
  filter(str_detect(term, "year_rel")) |>
  mutate(year_rel = as.numeric(str_extract(term, "-?\\d+")))

p_es <- ggplot(es_df, aes(x = year_rel, y = estimate)) +
  geom_point(size = 2) +
  geom_errorbar(aes(ymin = conf.low, ymax = conf.high), width = 0.2) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "gray40") +
  geom_vline(xintercept = -0.5, linetype = "dotted", color = "red") +
  labs(x = "Years Relative to Treatment", y = "Estimated Effect (95% CI)") +
  theme_Publication()
save_fig(p_es, "fig-event-study")
```

---

### B5 — RD Plot

```r
library(rdrobust); library(rddensity)

# Main RD plot
rdplot(y = df$outcome, x = df$running_var, c = cutoff,
       title = "RD Plot", x.label = "Running Variable", y.label = "Outcome")

# McCrary density test for manipulation
rdd <- rddensity(df$running_var, c = cutoff)
rdplotdensity(rdd, df$running_var)
```

---

### B6 — Balance / Love Plot (Matching)

```r
library(MatchIt); library(cobalt)

# After running matchit:
# m_match <- matchit(treatment ~ x1 + x2 + x3, data = df, method = "nearest")

p_love <- love.plot(m_match,
                    thresholds  = c(m = 0.1),
                    abs         = TRUE,
                    var.order   = "standardized",
                    colors      = palette_cb[c(1,7)]) +
  theme_Publication()
save_fig(p_love, "fig-love-plot")
```

---

### B7 — Kaplan-Meier Survival Plot

```r
library(survival); library(survminer)

km_fit <- survfit(Surv(time, event) ~ group, data = df)

ggsurvplot(km_fit,
           pval         = TRUE,
           conf.int     = TRUE,
           risk.table   = TRUE,
           palette      = palette_cb[1:2],
           legend.labs  = levels(df$group),
           ggtheme      = theme_Publication())
# Save manually via ggsave after ggsurvplot renders
```

---

### B8 — Python Figure Equivalents

Use Python when the user requests it, when R is unavailable, or for interactive/web figures. The `VIZ_ENGINE` env var can be set to `python` to default to this path.

```python
import os, matplotlib.pyplot as plt, matplotlib as mpl
import seaborn as sns
import numpy as np, pandas as pd

output_root = os.environ.get("OUTPUT_ROOT", "output")

# ── Publication style (matches theme_Publication in R) ──
palette_cb = ["#0072B2","#E69F00","#009E73","#CC79A7",
              "#56B4E9","#F0E442","#D55E00","#000000"]
sns.set_palette(palette_cb)
mpl.rcParams.update({
    'font.family': 'Helvetica Neue', 'font.size': 12,
    'axes.spines.top': False, 'axes.spines.right': False,
    'figure.dpi': 150, 'savefig.dpi': 300, 'savefig.bbox': 'tight'
})

# ── Journal dimension presets ──
JOURNAL_DIMS = {
    'default': (6, 4.5), 'asr': (6.5, 4.5), 'ajs': (6.5, 4.5),
    'demography': (6.5, 5), 'nhb_single': (3.5, 3), 'nhb_double': (7.1, 4.5),
    'ncs_single': (3.5, 3), 'ncs_double': (7.1, 4.5),
    'sciadv': (7, 4.5), 'pnas': (3.4, 3),
}

# ── Export helper (mirrors R save_fig) ──
def save_fig(fig, name, journal='default', grayscale=False):
    w, h = JOURNAL_DIMS.get(journal.lower(), JOURNAL_DIMS['default'])
    fig.set_size_inches(w, h)
    for fmt in ['pdf', 'png']:
        fig.savefig(f"{output_root}/figures/{name}.{fmt}", dpi=300, bbox_inches='tight')
    if grayscale:
        # Convert to grayscale copy
        import matplotlib.image as mpimg
        from PIL import Image
        img = Image.open(f"{output_root}/figures/{name}.png").convert('L')
        img.save(f"{output_root}/figures/{name}-gs.png")
    print(f"Saved: {output_root}/figures/{name} (.pdf + .png)")
```

**B8 figure templates (parallel to B1-B7):**

```python
# B8-B1: Distribution with KDE
fig, ax = plt.subplots()
sns.histplot(df, x='outcome', hue='group', kde=True, stat='density', ax=ax)
ax.set_xlabel('Outcome'); ax.set_ylabel('Density')
save_fig(fig, 'fig-dist')

# B8-B2: Coefficient plot
import statsmodels.formula.api as smf
model = smf.ols('y ~ x + c1 + c2', data=df).fit(cov_type='HC3')
coef_df = (model.params.to_frame('coef')
           .join(model.conf_int().rename(columns={0:'lo',1:'hi'}))
           .drop('Intercept'))
fig, ax = plt.subplots(figsize=(5, len(coef_df)*0.5+1))
ax.errorbar(coef_df['coef'], range(len(coef_df)),
            xerr=[coef_df['coef']-coef_df['lo'], coef_df['hi']-coef_df['coef']],
            fmt='o', color=palette_cb[0], capsize=3)
ax.axvline(0, ls='--', color='gray', lw=0.8)
ax.set_yticks(range(len(coef_df))); ax.set_yticklabels(coef_df.index)
ax.set_xlabel('Coefficient (95% CI)')
save_fig(fig, 'fig-coef')

# B8-B3: Marginal effects
from marginaleffects import avg_slopes, plot_slopes
ame = avg_slopes(model)
fig = plot_slopes(model, variables='x')
save_fig(fig.figure, 'fig-ame')

# B8-B4: Event study (linearmodels)
# Use pyfixest for Python FE: import pyfixest as pf; m = pf.feols(...)

# B8-B7: Survival
from lifelines import KaplanMeierFitter
kmf = KaplanMeierFitter()
fig, ax = plt.subplots()
for grp in df['group'].unique():
    mask = df['group'] == grp
    kmf.fit(df.loc[mask, 'time'], df.loc[mask, 'event'], label=grp)
    kmf.plot_survival_function(ax=ax)
ax.set_xlabel('Time'); ax.set_ylabel('Survival Probability')
save_fig(fig, 'fig-km')
```

**B8-interactive: Plotly for interactive/web figures:**

```python
import plotly.express as px
import plotly.io as pio

# Interactive scatter with hover
fig = px.scatter(df, x='x', y='y', color='group', hover_data=['id','x','y'],
                 color_discrete_sequence=palette_cb)
fig.update_layout(template='simple_white', font_size=12)
pio.write_html(fig, f"{output_root}/figures/fig-scatter-interactive.html")
pio.write_image(fig, f"{output_root}/figures/fig-scatter-interactive.pdf", width=700, height=450)
pio.write_image(fig, f"{output_root}/figures/fig-scatter-interactive.png", width=700, height=450, scale=3)

# Interactive coefficient plot
fig = px.scatter(coef_df.reset_index(), x='coef', y='index',
                 error_x_minus=coef_df['coef']-coef_df['lo'],
                 error_x=coef_df['hi']-coef_df['coef'])
fig.add_vline(x=0, line_dash='dash', line_color='gray')
pio.write_html(fig, f"{output_root}/figures/fig-coef-interactive.html")
```

**Engine selection:** If `VIZ_ENGINE=python` is set in `.env`, default to Python for all B1-B7 equivalents. Otherwise default to R.

---

### B9 — Visualization Verification (Subagent)

After completing B0–B8, launch a **visualization verification subagent** via the Task tool (`subagent_type: general-purpose`) to audit all figures before writing results.

**Prompt the subagent with the following context:**
- Full list of figures generated (filenames + figure types)
- The ggplot2 / Python code used for each figure
- Bash output from `ls ${OUTPUT_ROOT}/figures/` showing saved files
- Target journal

**The subagent performs these checks and returns a VISUALIZATION REPORT:**

```
VISUALIZATION VERIFICATION REPORT
===================================

FILE EXPORT
[ ] save_fig() called for every ggplot figure (or equivalent savefig for Python)
[ ] Every figure exists in both .pdf and .png in output/[slug]/figures/
[ ] PNG DPI = 300 confirmed (check ggsave dpi= argument)
[ ] PDF uses cairo_pdf device (vector, embeds fonts correctly)
[ ] Interactive figures (plotly) saved as .html via htmlwidgets::saveWidget()

COLORBLIND SAFETY
[ ] scale_colour_Publication() or palette_cb (Wong 2011) used — not default ggplot2 colors
[ ] No red-green pair used together (#FF0000 + #00FF00 or similar)
[ ] Continuous scales use viridis or ColorBrewer diverging (not rainbow)

LABELS AND LEGIBILITY
[ ] X-axis and Y-axis labels present and human-readable (not raw variable names like "inc_log")
[ ] Legend title and levels labeled clearly (not "0 / 1" or raw factor codes)
[ ] Error bars explicitly labeled in caption: "Error bars = 95% CI" (or SEM / SD)
[ ] Figure caption is self-explanatory without reading main text

JOURNAL-SPECIFIC REQUIREMENTS
[ ] ASR/AJS: predicted probability or marginal effect plots used (not raw odds ratio forest plots)
[ ] Science Advances: panel labels in uppercase (A, B, C, …) for multi-panel figures
[ ] Science Advances: error bar type (SEM / SD / 95% CI) labeled in figure or legend
[ ] NHB: violin plot or boxplot used for group comparisons (not bar + error bar)
[ ] NHB: individual data points overlaid when N < 30 per group (geom_jitter or geom_point)
[ ] NHB: panel labels uppercase if multi-panel

FIGURE TYPE CORRECTNESS
[ ] Distribution: density/histogram appropriate; not a pie chart
[ ] Coefficient plot: reference line at zero present
[ ] Marginal effect plot: zero reference line present; y-axis labeled as AME or Pr(Y=1)
[ ] Event study: vertical dotted line at treatment onset (year_rel = -0.5); zero hline
[ ] RD plot: cutoff marked; separate trend lines each side
[ ] Love plot: threshold lines at ±0.1; pre- and post-match shown
[ ] Choropleth: legend shows units (%, $, rate); NA counties handled (fill="gray90")
[ ] Interactive: tooltip text informative; not just raw variable value

FILES ON DISK
[ ] output/[slug]/figures/ directory has at least one PDF and one PNG
[ ] All figure filenames follow fig-[type]-[variable] convention

RESULT: [PASS / NEEDS REVISION]

Issues to fix before proceeding:
1. [Specific issue + corrected code if applicable]
```

If the verification subagent returns **NEEDS REVISION**, fix all flagged issues and re-save affected figures before proceeding to B10 or Component C.

---

### B10 — Conceptual Diagrams (Non-Data Figures)

For theoretical frameworks, causal DAGs, process models, and flowcharts that don't require a data pipeline. These are generated as code and rendered to PDF/PNG.

**B10a — Mermaid Diagrams** (theoretical frameworks, process models, flowcharts):

```bash
# Write the Mermaid source
cat > "${OUTPUT_ROOT}/figures/fig-theoretical-framework.mmd" << 'EOF'
graph TD
    A[Neighborhood Disadvantage] --> B[Institutional Resources]
    A --> C[Social Cohesion]
    B --> D[Health Outcomes]
    C --> D
    A --> D
    E[Race/Ethnicity] --> A
    E --> D
EOF

# Render via mmdc (Mermaid CLI) — install: npm install -g @mermaid-js/mermaid-cli
npx mmdc -i "${OUTPUT_ROOT}/figures/fig-theoretical-framework.mmd" \
         -o "${OUTPUT_ROOT}/figures/fig-theoretical-framework.pdf" \
         -w 800 -H 600 --backgroundColor white
npx mmdc -i "${OUTPUT_ROOT}/figures/fig-theoretical-framework.mmd" \
         -o "${OUTPUT_ROOT}/figures/fig-theoretical-framework.png" \
         -w 800 -H 600 --backgroundColor white -s 3
```

**Common social science diagram templates:**

| Diagram | Mermaid type | Use case |
|---------|-------------|----------|
| Mediation model | `graph LR` with A→M→Y + A→Y | Causal mediation |
| Moderation model | `graph LR` with M moderating A→Y edge | Interaction effects |
| Coleman's boat | `graph TD` with macro→micro→micro→macro | Analytical sociology |
| Lifecycle model | `graph LR` with temporal stages | Life course analysis |
| Research design flowchart | `flowchart TD` with decision nodes | CONSORT / sample flow |
| Multi-level structure | `graph TD` with nested boxes | MLM / HLM |

**B10b — TikZ DAGs** (for causal diagrams requiring precise layout):

```bash
cat > "${OUTPUT_ROOT}/figures/fig-dag.tex" << 'TIKZ'
\documentclass[tikz,border=5pt]{standalone}
\usepackage{tikz}
\usetikzlibrary{positioning,arrows.meta}
\begin{document}
\begin{tikzpicture}[
    node distance=2cm,
    var/.style={circle,draw,minimum size=1cm,font=\small},
    arr/.style={-{Stealth[length=3mm]},thick}
]
\node[var] (X) {$X$};
\node[var,right=of X] (Y) {$Y$};
\node[var,above right=1cm and 1cm of X] (Z) {$Z$};
\draw[arr] (X) -- (Y);
\draw[arr] (Z) -- (X);
\draw[arr] (Z) -- (Y);
\end{tikzpicture}
\end{document}
TIKZ

# Render via xelatex
cd "${OUTPUT_ROOT}/figures" && xelatex -interaction=nonstopmode fig-dag.tex
# Convert to PNG for inspection
convert -density 300 fig-dag.pdf fig-dag.png 2>/dev/null || \
  sips -s format png fig-dag.pdf --out fig-dag.png 2>/dev/null || true
```

**B10c — SVG Diagrams** (for web / supplementary materials):

When Mermaid or TikZ are unavailable, generate SVG directly for simple diagrams. Claude Code can write SVG markup and save it, then convert to PDF via `rsvg-convert` or `inkscape --export-pdf`.

**Rules for B10:**
- Conceptual diagrams do NOT go through the inspect-and-revise loop (B0c) — they are layout-checked manually
- Always save both source file (.mmd / .tex / .svg) and rendered output (.pdf + .png)
- Use `Read` tool to inspect the rendered PNG and verify layout before proceeding

---

## REVISE-FIGURE Workflow (Mode 4)

Triggered when the user wants to modify an existing figure without re-running the full analysis pipeline. This mode reads an existing figure file, applies the requested changes, and saves the revised version using the version-check protocol.

### RF1 — Locate the figure

Parse the user's request to identify:
- **Target figure**: file path (e.g., `output/figures/fig-coef-plot.pdf`) or figure name
- **Requested changes**: one or more from the revision catalog below

If no file path is given, scan `${OUTPUT_ROOT}/figures/` for matching files:
```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
ls -la "${OUTPUT_ROOT}/figures/"*.pdf "${OUTPUT_ROOT}/figures/"*.png 2>/dev/null
```

### RF2 — Read the existing figure

Use the `Read` tool to inspect the existing PNG to understand current layout, then identify the R or Python script that produced it:
```bash
# Check if a generating script exists
grep -rl "[figure_name]" "${OUTPUT_ROOT}/scripts/" 2>/dev/null
```

If the generating script exists, read it to understand the current code. If not, reconstruct from the figure type.

### RF3 — Apply revisions

| Revision type | What to change |
|---------------|---------------|
| **Rotate labels** | `theme(axis.text.x = element_text(angle = 45, hjust = 1))` |
| **Resize** | Update `save_fig(p, name, w = NEW_W, h = NEW_H)` dimensions |
| **Relabel axes** | `labs(x = "New Label", y = "New Label")` |
| **Add reference line** | `geom_hline(yintercept = VALUE)` or `geom_vline(xintercept = VALUE)` |
| **Change colors** | Swap palette or use `scale_fill_manual(values = c(...))` |
| **Adjust faceting** | Change `facet_wrap(~var, ncol = N)` or switch to `facet_grid()` |
| **Add/remove legend** | `theme(legend.position = "bottom"/"none"/"right")` |
| **Reorder categories** | `mutate(var = fct_reorder(var, sort_var))` |
| **Add annotations** | `annotate("text", x = X, y = Y, label = "text")` |
| **Change to journal preset** | Apply `journal_dims$nhb_single` or `$asr` dimensions from B0 |
| **Add panel labels** | `library(patchwork); plot_annotation(tag_levels = "A")` |
| **Switch to grayscale** | `scale_colour_grey()` + `scale_fill_grey()` |
| **Convert R to Python** | Load `viz-templates-python.md` and rewrite using equivalent template |
| **Convert Python to R** | Load `viz-templates-ggplot.md` and rewrite using equivalent template |

### RF4 — Execute and inspect

1. Run the modified code via Bash
2. Read the new PNG to verify the changes took effect
3. Apply the B0c Inspect-and-Revise protocol (auto-fix overlapping labels, truncated axes, etc.)
4. Save using version-check — the revised figure gets a new version suffix (never overwrites)

### RF5 — Update script archive

If a generating script exists in `${OUTPUT_ROOT}/scripts/`, save the revised version using the script version-check protocol. Append a decision entry to `coding-decisions-log.md` noting the revision and rationale.

---

## COMPONENT C: Results Section Writing

Using the actual numerical results from Components A and B, **write complete, publication-ready prose**. Replace every placeholder with real values. No brackets should remain in the final text.

### Journal-Specific Reporting Norms

| Journal | Effect estimate | Uncertainty | Significance | Target length |
|---------|----------------|-------------|--------------|---------------|
| ASR | AME required for logit | SE in parentheses | Stars in tables + exact p in text | 1,500–2,500 words |
| AJS | AME preferred | SE in parentheses | Stars | 1,500–2,500 words |
| Demography | AME or OR + decomposition | Either | Stars | 2,000–3,000 words |
| Science Advances | AME preferred | 95% CI | Stars + `ns` marker | 1,500–2,000 words (main) |
| NHB | AME preferred | 95% CI + test stat + df | Stars + `ns` marker | 1,500–2,000 words (main) |

---

### Sentence Templates by Model Type

**OLS:**
> "A one-unit increase in [X] is associated with a [β]-unit change in [Y], holding other variables constant (b = [β], SE = [SE], p = [p])."

**AME from logit (ASR/AJS/Demography):**
> "A one-unit increase in [X] is associated with a [β×100] percentage point change in the probability of [Y] (AME = [β], 95% CI = [[lo], [hi]])."

**AME from logit (NHB/Science Advances):**
> "A one-unit increase in [X] is associated with a [β×100] percentage point increase in the probability of [Y] (AME = [β], 95% CI = [[lo], [hi]], z = [z], p = [p])."

**Fixed effects:**
> "Among [units] that changed [X] over time, a one-unit increase is associated with a [β]-unit change in [Y] (b = [β], SE = [SE], p = [p])."

**Interaction:**
> "The effect of [X] on [Y] is [β₁] for [Group A] and [β₂] for [Group B]; this difference is [significant/not distinguishable from zero] (b_interaction = [Δβ], SE = [SE], p = [p])."

**Null result:**
> "We find no statistically significant association between [X] and [Y] (b = [β], SE = [SE], p = [p])."

**Practical significance:**
> "While statistically significant, the effect (b = [β]) represents [X]% of the outcome's SD, a [small/moderate/large] magnitude."

**Robustness:**
> "Results are robust to [alternative sample restriction / alternative operationalization / alternative specification] (Table A1). Following Oster (2019), we estimate δ = [X], indicating that unobserved confounders would need to be [X] times more predictive of [Y] than our observed controls to explain away the finding."

**LCA / Mixture models:**
> "Latent class analysis identified [K] distinct [typologies/profiles] based on [indicators] (Table X). A [K]-class solution provided the best fit (BIC = [X]; entropy = [X]). Class 1 ([X]%) was characterized by [pattern]; Class 2 ([X]%) by [pattern]."

**Quantile regression:**
> "Quantile regression reveals that the association between [X] and [Y] varies across the outcome distribution (Table X; Figure X). At the 10th percentile, [X] is associated with [b] (SE = [SE], p = [p]), whereas at the 90th percentile the effect is [b] (SE = [SE], p = [p]). The OLS estimate of [b] masks this heterogeneity."

**Zero-inflated / Hurdle:**
> "Given the excess zeros in [Y] ([X]% of observations), we estimated a zero-inflated negative binomial model (Table X). In the count process, [X] was associated with a [X]% [increase/decrease] in expected [Y] (IRR = [X], 95% CI = [[lo], [hi]], p = [p]). In the zero-inflation process, [Z] [increased/decreased] the probability of being a structural zero (OR = [X], 95% CI = [[lo], [hi]], p = [p])."

**Beta regression:**
> "Because [Y] is a bounded proportion, we estimated beta regression (Table X). [X] is associated with a [direction] in [Y] (b = [b], SE = [SE], p = [p]). The average marginal effect indicates a [AME] percentage-point change per one-unit increase in [X] (AME = [AME], 95% CI = [[lo], [hi]])."

**Competing risks:**
> "The cumulative incidence of [event] at [T] years was [X]% (95% CI = [[lo]%, [hi]%]). In the Fine-Gray model, [X] was associated with a [X]% [higher/lower] subdistribution hazard of [event] (SHR = [X], 95% CI = [[lo], [hi]], p = [p]), accounting for the competing risk of [competing event]."

**RI-CLPM:**
> "The RI-CLPM (Hamaker et al., 2015) separated stable between-person differences from within-person dynamics across [T] waves (Table X). At the within-person level, [X at time t] [predicted/did not predict] [Y at t+1] (b = [b], SE = [SE], p = [p]), while the reverse path was [significant/nonsignificant] (b = [b], SE = [SE], p = [p])."

**Sequence analysis:**
> "Sequence analysis with optimal matching identified [K] distinct [trajectory] typologies (Table X; Figure X). Cluster 1 ('[label],' [X]%) was characterized by [pattern]. [Covariate] was associated with [higher/lower] odds of following the '[label]' trajectory (RRR = [X], 95% CI = [[lo], [hi]], p = [p])."

**SEM / CFA:**
> "Confirmatory factor analysis established the measurement model (Table X). All loadings exceeded [.40] (p < .001). The model fit well (CFI = [X], TLI = [X], RMSEA = [X] [90% CI: [lo], [hi]], SRMR = [X]). In the structural model, [latent predictor] was [positively/negatively] associated with [latent outcome] (b = [b], beta = [beta], p = [p])."

**Multiple testing correction:**
> "To account for [X] simultaneous tests, we applied [Benjamini-Hochberg / Holm] correction (Table X). After adjustment, [X] of [Y] hypotheses remained significant at FDR < .05."

---

### Results Section Structure

Write the following four paragraph types in order. Each must contain actual numbers.

```
¶1 SAMPLE DESCRIPTION
   Overall N; group sizes if stratified; means and SDs for key variables; reference Table 1.
   Note exclusions and reason.

¶2 MAIN FINDINGS (H1 test)
   State whether H1 is supported. Report focal coefficient with full statistics.
   Describe attenuation (or lack thereof) from M1 → M2. Reference Table 2.

¶3 EXTENDED MODEL (H2/moderation/mediation if applicable)
   M3 results; conditional effects at key moderator values; reference the marginal effects figure.
   Skip if no moderation/mediation hypothesis.

¶4 ROBUSTNESS
   2–4 sentences summarizing Table A1. Confirm main finding holds.
   Report Oster delta if OLS + causal language.
```

**Within-Group / Between-Group Interpretation Check (MANDATORY when comparing two or more groups):**

When the analysis compares groups (e.g., language corpora, treatment vs. control, racial groups), report BOTH perspectives before writing any interpretive claim:

```
INTERPRETATION CHECK — [Group comparison: e.g., Chinese vs English]

Between-group (cross-group AMEs / coefficient differences):
  - [Variable]: Group A has [X more/less] than Group B (AME = [value])

Within-group (absolute distributions for each group separately):
  - Group A: [key metric] = [value] (e.g., 18.4% positive, 20.1% negative → net -1.7pp)
  - Group B: [key metric] = [value] (e.g., 13.5% positive, 35.1% negative → net -21.6pp)

⚠ CONSISTENCY CHECK:
  - Do between-group and within-group comparisons support the SAME interpretation?
  - If not, flag: "WARNING: Cross-group framing suggests [X]; within-group shows [Y].
    Both perspectives must be reported in the Results prose."
```

Example of a flagged inconsistency:
> Cross-group: "CN has less negative Dem content than EN (AME = -6.8pp)" suggests CN is *less hostile*
> Within-group: "CN Dem sentiment is 29.2% neg vs 5.5% pos (5:1 ratio); CN Trump is 20.1% neg vs 18.4% pos (nearly balanced)" shows CN is *selectively critical of Democrats*
> → Both must be reported; the within-group framing is more consequential for interpretation

Append this check to the analysis log and include it in the Results prose output (File 2).

---

**Writing rules:**
- Lead every paragraph with the substantive finding, not a method description
- Report exact p-values in text (p = .034); use stars only in tables
- Reference tables and figures inline: "(Table 2, Column 3)"; "(Figure 2)"
- Report effect sizes alongside p-values — p < .001 without β is uninterpretable
- Avoid "proves" — use "is consistent with," "supports," "suggests"
- Null findings must be reported with full statistics, not just "not significant"
- No passive voice constructions ("was found to be") — active voice only

---

## COMPONENT D: Script Archiving and Coding Decisions

This component runs **cross-cuttingly** throughout Components A and B. It ensures every executed code block is saved as a self-contained script, every analytic decision is logged with rationale, and a master script index maps scripts to paper elements — so that building a replication package later (via `/scholar-open`) requires assembly, not reconstruction.

### D0 — Initialize Script Log Files

Run at the start of every `scholar-analyze` session, immediately after `mkdir`:

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"

# Initialize coding decisions log
cat > "${OUTPUT_ROOT}/scripts/coding-decisions-log.md" << 'LOGEOF'
# Coding Decisions Log
<!-- Append-only log. Each entry records one analytic decision with rationale. -->

| Timestamp | Step | Decision | Alternatives Considered | Rationale | Variables Affected | Script |
|-----------|------|----------|------------------------|-----------|-------------------|--------|
LOGEOF

# Initialize script index
cat > "${OUTPUT_ROOT}/scripts/script-index.md" << 'IDXEOF'
# Script Index

## Run Order

| # | Script | Purpose | Input | Output | Paper Element |
|---|--------|---------|-------|--------|---------------|
IDXEOF
```

### D1 — Script Save Protocol (with Version Control)

Follow the version control protocol defined in `.claude/skills/_shared/script-version-check.md`. **NEVER overwrite an existing script.** Always version-check before saving.

After each code block is executed (or written as `[CODE-TEMPLATE]`) in steps A1–A8 and B0–B8, save the complete script to `${OUTPUT_ROOT}/scripts/[NN]-[name].[ext]` — but **run the version check first**:

```bash
# MANDATORY: Run before EVERY script Write tool call
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
SCRIPT_NAME="04-main-models"  # Replace with actual script name
EXT="R"                        # R, py, do, jl
SCRIPT_DIR="${OUTPUT_ROOT}/scripts"
mkdir -p "$SCRIPT_DIR"

SCRIPT_BASE="${SCRIPT_DIR}/${SCRIPT_NAME}"
if [ -f "${SCRIPT_BASE}.${EXT}" ]; then
  V=2
  while [ -f "${SCRIPT_BASE}-v${V}.${EXT}" ]; do V=$((V + 1)); done
  SCRIPT_BASE="${SCRIPT_BASE}-v${V}"
fi
echo "SCRIPT_PATH=${SCRIPT_BASE}.${EXT}"
```

**Use the printed `SCRIPT_PATH` as `file_path` in the Write tool call.** Shell variables do NOT persist between Bash tool calls — re-derive in every new call.

**Standard script header** (prepend to every saved script):
```r
# ============================================================
# Script: [NN]-[name][-vN].R
# Version: [v1 | v2 | v3 ...]
# Purpose: [one-line description]
# Input:   [data file or prior script output]
# Output:  [tables, figures, or objects produced]
# Date:    [YYYY-MM-DD]
# Seed:    set.seed(42)
# Changes: [if v2+, one-line summary of what changed from prior version]
# Notes:   [SE type, sample restrictions, key parameters]
# ============================================================
```

**Scripts must be self-contained**: include explicit `library()` calls, data loading (`readRDS()`/`read_csv()`), and `set.seed()`. No reliance on in-memory objects from prior scripts.

**Step-to-filename mapping:**

| Step | Script name | Description |
|------|-------------|-------------|
| A1 | `01-data-loading.R` | Load + inspect data |
| A2 | `03-descriptives-table1.R` | Descriptive statistics table |
| A3 | `04-main-models.R` | Regression model ladder |
| A4 | `05-marginal-effects.R` | AME computation |
| A5 | `06-diagnostics.R` | VIF, BP test, Cook's D |
| A6 | `07-export-tables.R` | modelsummary export |
| A7 | `08-robustness.R` | Robustness checks + Oster |
| A8 | `09-decomposition.R` | Oaxaca-Blinder (if applicable) |
| A8a | `09a-lca-mixture.R` | Latent class analysis (if applicable) |
| A8b | `09b-quantile-regression.R` | Quantile regression (if applicable) |
| A8c | `09c-zero-inflated.R` | Zero-inflated / hurdle models (if applicable) |
| A8d | `09d-beta-regression.R` | Beta regression (if applicable) |
| A8e | `09e-competing-risks.R` | Competing risks models (if applicable) |
| A8f | `09f-riclpm.R` | RI-CLPM (if applicable) |
| A8g | `09g-sequence-analysis.R` | Sequence analysis (if applicable) |
| A8h | `09h-sem-cfa.R` | Full SEM / CFA (if applicable) |
| A8i | `09i-multiple-testing.R` | Multiple testing correction (if applicable) |
| A8j | `09j-gamlss.R` | GAMLSS distributional regression (if applicable) |
| A8k | `09k-dml-bridge.R` | DML / Causal Forest bridge (if high-dim controls) |
| A8l | `09l-growth-curve.R` | Growth curve models (if trajectory data) |
| A8m | `09m-multilevel-sem.R` | Multilevel SEM (if nested + latent) |
| A8n | `09n-finite-mixture-regression.R` | Finite mixture regression (if latent heterogeneity) |
| A8o | `09o-specification-curve.R` | Specification curve / multiverse (if robustness) |
| A8p | `09p-bart.R` | BART causal / predictive (if nonparametric) |
| — | `04-main-models.do` | Stata parallel `.do` file (if Stata requested) |
| B0 | `10-viz-setup.R` | Theme + palette + save_fig() + journal presets |
| B0b | — | Figure brief (user confirmation, not a script) |
| B0c | — | Inspect-and-revise protocol (not a script) |
| B1 | `11-viz-descriptive.R` | Distribution + violin + bar |
| B2 | `12-viz-coefficient.R` | Coefficient / forest plot |
| B3 | `13-viz-marginal.R` | AME + interaction + predicted |
| B4 | `14-viz-event-study.R` | Event study (if DiD) |
| B5 | `15-viz-rd.R` | RD plot (if RD) |
| B6 | `16-viz-balance.R` | Love plot (if matching) |
| B7 | `17-viz-survival.R` | Kaplan-Meier (if survival) |
| B8 | `18-viz-python.py` | Python figures (if VIZ_ENGINE=python) |
| B10 | `19-viz-diagrams.*` | Conceptual diagrams (Mermaid/TikZ/SVG) |

**No-data mode:** Save with `# [CODE-TEMPLATE] — run when data available` as the first line after the header.

### D2 — Coding Decisions Log Protocol

After EVERY analytic step in A0–A8, append an entry to `${OUTPUT_ROOT}/scripts/coding-decisions-log.md` via Bash `>>`. Each entry records one decision:

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
echo "| $(date '+%Y-%m-%d %H:%M') | A3 | OLS with HC3 robust SEs | Default SEs, clustered SEs | HC3 chosen because heteroskedasticity detected (BP p < .05) | Y, X, C1-C4 | 04-main-models.R |" >> "${OUTPUT_ROOT}/scripts/coding-decisions-log.md"
```

**Required decision categories** (log at least one entry for each when applicable):
- **Model type selection**: Why OLS vs. logit vs. FE vs. MLM
- **Standard error type**: Why HC3 vs. clustered vs. default
- **Control variable selection**: Which controls included and why; which excluded and why
- **Sample restrictions**: Any observations dropped; rationale
- **Missing data strategy**: Listwise deletion vs. MI; justification
- **Robustness design**: Which alternative specs and why they test the right threat

This incremental-persistence pattern protects against context compaction — decisions are on disk the moment they are made.

### D3 — Script Index Update

After each script is saved in D1, append a row to the run-order table in `${OUTPUT_ROOT}/scripts/script-index.md`:

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
echo "| 4 | 04-main-models.R | Main regression ladder (M1-M3) | data/analysis_data.rds | ${OUTPUT_ROOT}/tables/table2-regression.html | Table 2 |" >> "${OUTPUT_ROOT}/scripts/script-index.md"
```

At the end of the run, finalize `script-index.md` by appending:

```markdown
## Dependencies
- Scripts 03–09 depend on 01-data-loading.R output
- Scripts 10–18 depend on model objects from 04 and 05

## Seeds
All scripts use `set.seed(42)`.

## Paper-Element Correspondence
| Paper element | Script(s) | Output file(s) |
|---------------|-----------|----------------|
| Table 1 | 03-descriptives-table1.R | output/[slug]/tables/table1-descriptives.html/.tex/.docx/.csv |
| Table 2 | 04-main-models.R, 07-export-tables.R | output/[slug]/tables/table2-regression.html/.tex/.docx/.csv |
| Figure 1 | 11-viz-descriptive.R | output/[slug]/figures/fig-dist-outcome.pdf/.png |
| ... | ... | ... |

## Coding Decisions
See [coding-decisions-log.md](coding-decisions-log.md) for the full decision rationale log.
```

---

## Quality Checklist

- [ ] Output directories created (`output/[slug]/tables/`, `output/[slug]/figures/`, `output/[slug]/scripts/`)
- [ ] Data loaded successfully (file / inline / online fetch confirmed)
- [ ] **Causal gate**: if causal design detected, `/scholar-causal` invoked (or confirmed already run)
- [ ] Table 1 descriptives saved as HTML + TeX + docx + CSV
- [ ] Regression table saved as HTML + TeX + docx
- [ ] AME table saved (HTML + TeX + docx) for any logit/ordered logit model
- [ ] Robustness table saved as HTML + TeX + docx
- [ ] **A9 Analysis Verification subagent run** — PASS confirmed (or all issues fixed)
- [ ] At least one figure saved as PDF + PNG (300 DPI)
- [ ] All figures use colorblind-safe palette; no red-green pairs
- [ ] **B0b Figure Brief** — figure plan confirmed by user (or auto-confirmed in pipeline)
- [ ] **B0c Inspect-and-Revise** — every figure PNG visually inspected; issues fixed (≤3 iterations each)
- [ ] **B9 Visualization Verification subagent run** — PASS confirmed (or all issues fixed)
- [ ] Each hypothesis has a corresponding results paragraph
- [ ] Effect sizes reported alongside significance
- [ ] Journal's reporting norms applied (AME / SE / CI / star format)
- [ ] Null findings reported honestly
- [ ] No causal language without causal design
- [ ] **Scripts saved** for every executed code block in `output/[slug]/scripts/` (D1)
- [ ] **Script headers present**: every script has purpose, input, output, date, seed (D1)
- [ ] **Coding decisions log** has entries for model selection, SE type, variable selection, sample restrictions, missing data, robustness design (D2)
- [ ] **Script index** has rows for all scripts + paper-element correspondence table (D3)
- [ ] **Internal log saved** (`scholar-analyze-log-[topic]-[date].md`) — decisions, verification, file inventory
- [ ] **Publication-ready results saved** (`scholar-analyze-results-[topic]-[date].md`) — Results prose + table notes + figure captions; no brackets remaining

---

## Save Output

Use the Write tool to save **two separate files** after completing all components.

### Version Collision Avoidance (MANDATORY)

**Before EVERY Write tool call below**, run this Bash block to determine the correct save path. Do NOT hardcode paths from the filename templates — they show naming patterns only.

```bash
# MANDATORY: Replace [values] with actuals before running
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
# BASE pattern: ${OUTPUT_ROOT}/[slug]/analysis/scholar-analyze-log-[topic-slug]-[YYYY-MM-DD]
# Split into directory and stem for the gate script:
OUTDIR="$(dirname "${OUTPUT_ROOT}/[slug]/analysis/scholar-analyze-log-[topic-slug]-[YYYY-MM-DD]")"
STEM="$(basename "${OUTPUT_ROOT}/[slug]/analysis/scholar-analyze-log-[topic-slug]-[YYYY-MM-DD]")"
mkdir -p "$OUTDIR"
bash "${SCHOLAR_SKILL_DIR:-.}/scripts/gates/version-check.sh" "$OUTDIR" "$STEM"
```

**Use the printed `SAVE_PATH` as `file_path` in the Write tool call.** Re-run this block (with the appropriate BASE) for each additional file. The same version suffix must be used for all related output files (.md, .docx, .tex, .pdf).

For File 2, change the BASE to:
`${OUTPUT_ROOT}/[slug]/analysis/scholar-analyze-results-[topic-slug]-[YYYY-MM-DD]`

---

### File 1 — Internal Analysis Log

**Filename:** `scholar-analyze-log-[topic-slug]-[YYYY-MM-DD].md`

**Purpose:** Technical record for your own reference — decisions, verification results, file inventory. Not for submission.

**Template:**
```markdown
# Analysis Log: [Topic] — [YYYY-MM-DD]

## Data Source
- Mode: [1 / 2 / 3]
- Source: [file path / inline description / package + dataset name + citation]
- N (raw): [X]; N (analytic): [X]; exclusions: [reason]

## Analytic Decisions
- Outcome (Y): [variable name + measurement]
- Key predictor (X): [variable name + measurement]
- Controls: [list]
- Model type: [OLS / logit / FE / Cox / etc.]
- SE type: [HC3 / clustered by unit / default]
- Causal design: [/scholar-causal invoked: yes/no; strategy: DiD / RD / IV / none]

## Verification Results
- A9 Analysis Verification: [PASS / issues fixed: ...]
- B9 Visualization Verification: [PASS / issues fixed: ...]

## Key Estimates (Quick Reference)
| Predictor | β / AME | SE / 95% CI | p |
|-----------|---------|-------------|---|
| [X]       | [β]     | [SE]        | [p] |
| ...       |         |             |   |

## Robustness Summary
- No outliers: [β, p] vs. main [β, p] — [holds / attenuates]
- Alt measure: [β, p] vs. main [β, p] — [holds / attenuates]
- Oster δ: [X] — [interpretation]

## File Inventory
output/[slug]/tables/table1-descriptives.html / .tex / .docx
output/[slug]/tables/table2-regression.html / .tex / .docx
output/[slug]/tables/table2-ame.html / .tex / .docx       (if logit)
output/[slug]/tables/tableA1-robustness.html / .tex / .docx
output/[slug]/figures/fig-dist-outcome.pdf / .png
output/[slug]/figures/fig-coef-plot.pdf / .png
output/[slug]/figures/fig-ame-[x].pdf / .png              (if plotted)
output/[slug]/figures/fig-event-study.pdf / .png          (if DiD)
[list all actual figures generated]

## Script Archive
output/[slug]/scripts/coding-decisions-log.md
output/[slug]/scripts/script-index.md
output/[slug]/scripts/[list all saved scripts, e.g.:]
  01-data-loading.R
  03-descriptives-table1.R
  04-main-models.R
  05-marginal-effects.R
  [... etc.]
```

---

### File 2 — Publication-Ready Results Document

**Filename:** `scholar-analyze-results-[topic-slug]-[YYYY-MM-DD].md`

**Purpose:** Drop-in material for the manuscript. Contains the complete Results section prose, table notes, and figure captions — all formatted for the target journal. Ready to paste into `/scholar-write`.

**Template — fill every placeholder with actual values before saving:**

```markdown
# Results: [Paper Title or Topic]
*Target journal: [ASR / AJS / Demography / Science Advances / NHB]*
*Word count: ~[XXX] words (target: [journal limit])*

---

## Results

[¶1 — SAMPLE DESCRIPTION]
The analytic sample comprises [N] [units/respondents/observations] drawn from [data source].
[Key group sizes if stratified.] Table 1 presents descriptive statistics. [Outcome variable]
averages [M] (SD = [SD]) overall[; Group A: M = [Ma], Group B: M = [Mb], p = [p]].
[Note any exclusions and reason.]

[¶2 — MAIN FINDINGS]
[State H1 support.] [Focal predictor] is [positively/negatively] associated with [outcome]
after adjusting for [list key controls] (b = [β], SE = [SE], p = [p]; Table 2, Column 2).
[For logit:] The average marginal effect indicates a [β×100] percentage point [increase/decrease]
in the probability of [outcome] per one-unit increase in [X] (AME = [β], 95% CI = [[lo], [hi]]).
[Describe coefficient stability M1 → M2.] [Reference figure if applicable: Figure 1.]

[¶3 — EXTENDED MODEL / INTERACTION / MEDIATION — omit if not applicable]
[M3 results. Conditional effects at key moderator values. Reference Figure X.]

[¶4 — ROBUSTNESS]
Results are robust to [alternative sample restriction / alternative operationalization /
alternative specification] (Table A1, Columns 2–3). [Report Oster delta if applicable:
Following Oster (2019), we estimate δ = [X], indicating that unobserved confounders
would need to be [X] times more predictive of [Y] than our observed controls to
explain away the finding.]

---

## Table Notes

**Table 1. Descriptive Statistics[, by Group]**
*Note.* [Describe statistics shown (mean/SD or N/%); sample; any weighting applied.]
[N = X.]

**Table 2. [Regression Results / Average Marginal Effects]: [Outcome] on [Predictor(s)]**
*Note.* [SE type] in parentheses. [Reference category for key categorical predictors.]
[Sample description.] [Significance: * p < .05, ** p < .01, *** p < .001.]
[N = X per column or as shown.]

**Table A1. Robustness Checks**
*Note.* Column 1 replicates the main model (Table 2, Column [X]).
Column 2 [description of restriction/change]. Column 3 [description].
[SE type] in parentheses. * p < .05, ** p < .01, *** p < .001.

---

## Figure Captions

**Figure 1. [Descriptive title: what is shown and for whom]**
[Self-explanatory caption: describe what each axis represents, what the shading/color codes, what error bars show (95% CI / SE / SD), data source, and analytic sample. Do not rely on main text to interpret.] N = [X].

**Figure 2. [Title]**
[Caption.] [Error bars = 95% CI.] N = [X].

[Add one caption block per figure generated in Component B.]
```

---

Confirm all three output paths to user at end of run.

---

See [references/analysis-standards.md](references/analysis-standards.md) for journal-specific reporting requirements and [references/viz-standards.md](references/viz-standards.md) for figure type guide and export standards.

**Output files produced by this skill:**
- `output/[slug]/tables/` — regression tables and descriptive stats (.html / .tex / .docx)
- `output/[slug]/figures/` — all figures (.pdf / .png; interactive as .html)
- `output/[slug]/scripts/` — self-contained analysis scripts (`[NN]-[name].R/.py`), `coding-decisions-log.md`, `script-index.md`
- `scholar-analyze-log-[topic]-[date].md` — internal technical log (decisions, verification, file inventory)
- `scholar-analyze-results-[topic]-[date].md` — **publication-ready**: Results section prose + table notes + figure captions; ready to paste into `/scholar-write`

**Post-analysis verification (recommended):**

After all tables and figures are produced, suggest to the user:

> "Analysis outputs saved. Consider running:
> - `/scholar-code-review full` to audit all analysis scripts for correctness, data handling errors (miscoded variables, wrong recodes), statistical misimplementation, and AI-generated code issues.
> - `/scholar-verify stage1` to verify raw outputs (tables, figures) are internally consistent before writing.
> These catch errors early — before they propagate into the manuscript."

This is a recommendation, not a gate — the user may proceed directly to `/scholar-write` if preferred. If run, `scholar-code-review` launches 6 review agents on scripts in `output/scripts/`; `scholar-verify stage1` launches verify-numerics and verify-figures on the raw outputs in `output/tables/` and `output/figures/`.

**Close Process Log:**

Run the following to finalize the process log:

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
SKILL_NAME="scholar-analyze"
LOG_DATE=$(date +%Y-%m-%d)
LOG_FILE="${OUTPUT_ROOT}/logs/process-log-${SKILL_NAME}-${LOG_DATE}.md"
if [ ! -f "$LOG_FILE" ]; then
  LOG_FILE=$(ls -t "${OUTPUT_ROOT}/logs/process-log-${SKILL_NAME}-${LOG_DATE}"*.md 2>/dev/null | head -1)
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
