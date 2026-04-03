# Visualization Standards for Social Science Papers

Source `viz_setting.R` at the start of every figure script:
```r
viz_path <- file.path(Sys.getenv("SCHOLAR_SKILL_DIR", unset = "."), ".claude/skills/scholar-analyze/references/viz_setting.R")
if (file.exists(viz_path)) source(viz_path) else stop("viz_setting.R not found — do NOT define theme_Publication inline")
# Provides: theme_Publication(), scale_fill/colour_Publication() (Wong 2011),
#   scale_fill_continuous/diverging_Publication(), set_geom_defaults_Publication(),
#   assemble_panels(), save_fig_cmyk(), preview_grayscale()
```

---

## Figure Type Guide

| Figure type | Purpose | Recommended approach |
|------------|---------|---------------------|
| Distribution | Show outcome spread, skew, group differences | `geom_histogram` + `geom_density`; violin+box for groups |
| Grouped comparison | Compare means/distributions across categories | Violin + boxplot; avoid plain bar+errorbar |
| Faceted scatter | Show relationship across subgroups or time periods | `geom_point()` + `facet_wrap(~var)` — classic Gapminder style |
| Coefficient / forest plot | Show regression estimates with CIs | `modelsummary::modelplot`; `broom::tidy()` → ggplot; custom `geom_point + geom_errorbarh` |
| Marginal effects | Show effect of X conditional on moderator | `marginaleffects::plot_slopes`; `effects::plot()` for interactions |
| Predicted probabilities | Show model-implied values across covariate range | `marginaleffects::plot_predictions` |
| ACS / survey estimate + MOE | Show point estimates with margin of error as error bars | `geom_errorbar(aes(xmin=estimate-moe, xmax=estimate+moe))` + `geom_point()` |
| Event study | Test pre-trends; show dynamic treatment effects | `feols` + `i()` + custom ggplot with ref line |
| RD plot | Visualize discontinuity at cutoff | `rdrobust::rdplot`; `geom_smooth` by side |
| Balance / love plot | Show covariate balance before/after matching | `cobalt::love.plot` |
| Kaplan-Meier | Show survival function by group | `survminer::ggsurvplot` with risk table |
| Correlation heatmap | Show pairwise correlations among numeric vars | `ggcorrplot::ggcorrplot` with `lab=TRUE` |
| Choropleth / geospatial map | Show geographic variation in outcomes | `geom_sf()` + `scale_fill_viridis_c()` + `theme_void()`; `tigris` + `tidycensus` boundaries |
| Interactive scatter / hover | Exploratory analysis; presentations | `plotly::plot_ly()` or `plotly::ggplotly(ggplot_obj)` |
| Interactive heatmap / 3D surface | Show matrix data or mathematical surfaces | `plotly::plot_ly(z=mat, type="heatmap"/"surface")` |
| Network graph | Show relational / social network structure | `visNetwork(nodes, edges)` (static/interactive); `networkD3::forceNetwork()` (D3 force) |
| RD plot | Visualize discontinuity at cutoff | `rdrobust::rdplot` (built-in); custom `geom_smooth` by side |
| Balance / love plot | Show covariate balance before/after matching | `cobalt::love.plot` |
| Kaplan-Meier | Show survival function by group | `survminer::ggsurvplot` with risk table |
| Correlation heatmap | Show pairwise correlations among numeric vars | `ggcorrplot::ggcorrplot` with `lab = TRUE, type = "lower"` |
| Raincloud | Distribution + box + raw data; replaces bar+errorbar | `ggdist::stat_halfeye` + `geom_boxplot` + `gghalves::geom_half_point` |
| Ridgeline | Compare distributions across many groups/time | `ggridges::geom_density_ridges` |
| Alluvial / Sankey flow | Categorical transitions (mobility, pathways) | `ggalluvial::geom_alluvium` + `geom_stratum` |
| CATE / HTE plot | Treatment effect heterogeneity by subgroup | Custom `geom_errorbarh` forest or `geom_smooth` CATE curve |
| Cleveland dot | Ranked comparisons across many categories | `geom_point` + `geom_segment` — cleaner than bar charts |
| Slope chart | Change between two time points | `geom_segment` connecting paired values |
| Waffle chart | Proportions as unit squares (alt to pie) | `waffle::waffle` |
| Posterior distribution | Bayesian posterior with CrI (pairs with A3b) | `ggdist::stat_halfeye` + `tidybayes::spread_draws` |

---

## ggplot2 Template Library

### Setup — always run first

```r
library(ggplot2); library(scales); library(modelsummary); library(marginaleffects)
viz_path <- file.path(Sys.getenv("SCHOLAR_SKILL_DIR", unset = "."), ".claude/skills/scholar-analyze/references/viz_setting.R")
if (file.exists(viz_path)) source(viz_path) else stop("viz_setting.R not found — do NOT define theme_Publication inline")

# Export helper — see SKILL.md B0 for full version with journal presets + grayscale
# This simplified version is used in template examples; the full version is defined in B0
save_fig <- function(p, name, width = 6, height = 4.5, dpi = 300,
                     journal = "default", grayscale = FALSE) {
  output_root <- Sys.getenv("OUTPUT_ROOT", "output")
  # Journal presets (subset — full table in SKILL.md B0)
  jdims <- list(default=list(w=6, h=4.5, base_size=12),
                nhb_single=list(w=3.5, h=3, base_size=8),
                nhb_double=list(w=7.1, h=4.5, base_size=10),
                sciadv=list(w=7, h=4.5, base_size=10),
                asr=list(w=6.5, h=4.5, base_size=12),
                pnas=list(w=3.4, h=3, base_size=8))
  if (journal != "default" && tolower(journal) %in% names(jdims)) {
    d <- jdims[[tolower(journal)]]
    width <- d$w; height <- d$h
    p <- p + theme_Publication(base_size = d$base_size)
  }
  ggsave(paste0(output_root, "/figures/", name, ".pdf"),
         plot = p, device = cairo_pdf, width = width, height = height)
  ggsave(paste0(output_root, "/figures/", name, ".png"),
         plot = p, dpi = dpi, width = width, height = height)
  if (grayscale) {
    p_gs <- p + scale_colour_grey() + scale_fill_grey()
    ggsave(paste0(output_root, "/figures/", name, "-gs.pdf"),
           plot = p_gs, device = cairo_pdf, width = width, height = height)
  }
  message("Saved: ", output_root, "/figures/", name, " (.pdf + .png)")
}

# Colorblind-safe palette (Wong 2011 — 8 colors)
palette_cb <- c("#0072B2","#E69F00","#009E73","#CC79A7",
                "#56B4E9","#F0E442","#D55E00","#000000")
```

---


## Template Loading (On-Demand)

Templates are stored in separate reference files. Load only when you need specific figure types:

```bash
SKILL_DIR="${SCHOLAR_SKILL_DIR:-.}/.claude/skills/scholar-analyze/references"
# For R/ggplot2 templates (T1-T25):
cat "$SKILL_DIR/viz-templates-ggplot.md"
# For Python/matplotlib/seaborn templates:
cat "$SKILL_DIR/viz-templates-python.md"
```

| File | Contents | When to load |
|------|----------|-------------|
| `viz-templates-ggplot.md` | 25 ggplot2 templates (T1-T25): distributions, coefficients, marginal effects, event studies, maps, networks, Bayesian posteriors, etc. | When producing R figures |
| `viz-templates-python.md` | 25 matplotlib/seaborn templates (P1-P25): full Python equivalents of every ggplot2 template | When producing Python figures or `VIZ_ENGINE=python` |

**Do NOT load both** unless the user needs cross-language comparison. Load the file matching the analysis language.

---

## Export Standards by Journal

### ASR / AJS (sociology)
- Format: EPS or TIFF (print-quality); PDF also accepted
- Resolution: 300 DPI minimum for raster; EPS/PDF preferred (vector)
- Color: no mandatory colorblind rule, but colorblind-safe palettes are expected
- Size: figures typically 3.5" (single column) or 7" (full width)
- Labels: clear axis labels; legend outside plot area; no figure title in file (title in caption)

### Demography
- Format: PDF or high-resolution TIFF (300 DPI)
- Decomposition figures: bar charts with labeled between/within components
- Survival figures: Kaplan-Meier with risk table

### Science Advances (AAAS)
- Format: vector (PDF/EPS/AI) strongly preferred; raster at ≥300 DPI
- Panel labels: **uppercase (A, B, C...)** inside figure, bold
- Color: colorblind-accessible required (no red-green); use ColorBrewer or Wong palette
- Error bars: must be labeled explicitly in figure legend (SEM vs. SD vs. 95% CI)
- Individual data points: show raw data for small N or small groups

### Nature Human Behaviour (NHB)
- Format: PDF (vector) preferred; TIFF at 300 DPI minimum
- Panel labels: **uppercase (A, B, C...)** using `patchwork::plot_annotation(tag_levels='A')`
- Individual data points: **required** when N < 30 per group
- Preferred plot types: violin + box (not bar + error); scatter over heatmap when possible
- Effect sizes: 95% CI always shown; test statistic in legend or caption
- Colorblind: mandatory — use palette_cb or viridis

---

## Colorblind-Safe Palettes

### Main palette (Wong 2011 — 8 colors, discrete)

| Color | Hex | Use for |
|-------|-----|---------|
| Blue | `#0072B2` | Primary group / treatment |
| Orange | `#E69F00` | Secondary group / control |
| Green | `#009E73` | Third category |
| Pink/purple | `#CC79A7` | Fourth category |
| Sky blue | `#56B4E9` | Fifth category |
| Yellow | `#F0E442` | Highlight (avoid for lines) |
| Vermillion | `#D55E00` | Emphasis / significant |
| Black | `#000000` | Reference line / text |

```r
palette_cb <- c("#0072B2","#E69F00","#009E73","#CC79A7",
                "#56B4E9","#F0E442","#D55E00","#000000")
```

### Continuous — viridis (sequential, colorblind-safe)
```r
scale_fill_viridis_c(option = "viridis")    # default
scale_fill_viridis_c(option = "plasma")     # warmer
scale_fill_viridis_d()                       # discrete version
```

### Diverging — ColorBrewer RdBu (for correlation matrices, change scores)
```r
scale_fill_distiller(palette = "RdBu", direction = -1)
# Or via ggcorrplot: colors = c("#2166AC","white","#D6604D")
```

---

## Labeling Standards

### Axis labels
- Use full variable names, not code names: `"Years of Education"` not `"educ_yrs"`
- Include units where applicable: `"Earnings ($, log)"`, `"Age (years)"`
- For probability outcomes: `"Probability"` or `"P(Y = 1)"`

### Panel labels (Nature journals)
```r
library(patchwork)
(p_a | p_b) / p_c +
  plot_annotation(tag_levels = "A") &
  theme(plot.tag = element_text(face = "bold", size = 14))
```

### Legend placement
- Single group variable: `theme(legend.position = "right")` (default in `theme_Publication`)
- Long legend labels: `theme(legend.position = "bottom", legend.direction = "horizontal")`
- No legend needed: `theme(legend.position = "none")`

### Figure captions (write in manuscript, not in file)
- Start with panel letter if multi-panel: "**Figure 2. (A)** Distribution of … **(B)** Regression coefficients …"
- State N, error bar type, and statistical test in caption: "Error bars represent 95% confidence intervals. * p < .05, ** p < .01, *** p < .001."

---


---

## Python Templates

For the full Python template library (25 templates, P1-P25), load `viz-templates-python.md`:

```bash
cat "${SCHOLAR_SKILL_DIR:-.}/.claude/skills/scholar-analyze/references/viz-templates-python.md"
```
