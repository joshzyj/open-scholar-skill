# Python Visualization Templates (P1-P25)

Full matplotlib/seaborn equivalents of the 25 ggplot2 templates in `viz-templates-ggplot.md`. Each template follows the same publication-quality standards: no in-figure titles, colorblind-safe palette, dual export (PDF + PNG), plain-language axis labels.

## Setup — always run first

```python
import os
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
import matplotlib.ticker as mticker
import seaborn as sns

# Publication style (matches theme_Publication in R)
plt.rcParams.update({
    "font.family": "Helvetica Neue",
    "font.size": 12,
    "axes.spines.top": False,
    "axes.spines.right": False,
    "axes.grid": False,
    "axes.linewidth": 0.8,
    "figure.dpi": 300,
    "savefig.bbox": "tight",
    "legend.frameon": False,
})

# Colorblind-safe palette (Wong 2011)
PALETTE_CB = ["#0072B2", "#E69F00", "#009E73", "#CC79A7",
              "#56B4E9", "#F0E442", "#D55E00", "#000000"]
sns.set_palette(PALETTE_CB)

# Output root
OUTPUT_ROOT = os.environ.get("OUTPUT_ROOT", "output")

def save_fig(fig, name, w=6, h=4.5):
    """Save both PDF (vector) and PNG (raster)."""
    fig.set_size_inches(w, h)
    for fmt in ["pdf", "png"]:
        fig.savefig(f"{OUTPUT_ROOT}/figures/{name}.{fmt}", dpi=300, bbox_inches="tight")
    print(f"Saved: {OUTPUT_ROOT}/figures/{name}.pdf, .png")
```

---

### P1 — Distribution (histogram + density)

```python
fig, ax = plt.subplots()
sns.histplot(df, x="outcome", hue="group", kde=True,
             stat="density", common_norm=False, palette=PALETTE_CB, ax=ax)
ax.set_xlabel("Outcome Variable")
ax.set_ylabel("Density")
save_fig(fig, "fig-dist")
```

### P2 — Grouped Violin + Boxplot

```python
fig, ax = plt.subplots()
sns.violinplot(data=df, x="group", y="outcome", inner=None,
               palette=PALETTE_CB, alpha=0.3, ax=ax)
sns.boxplot(data=df, x="group", y="outcome", width=0.15,
            boxprops=dict(facecolor="white"), ax=ax)
ax.set_xlabel("Group")
ax.set_ylabel("Outcome")
save_fig(fig, "fig-violin")
```

### P3 — Bar Chart with Percentages

```python
counts = df.groupby("category")["outcome"].mean().sort_values()
fig, ax = plt.subplots()
counts.plot.barh(ax=ax, color=PALETTE_CB[0])
ax.set_xlabel("Proportion")
ax.set_ylabel("")
ax.xaxis.set_major_formatter(mticker.PercentFormatter(1.0))
save_fig(fig, "fig-bar-pct")
```

### P4 — Coefficient / Forest Plot (single model)

```python
import statsmodels.formula.api as smf

model = smf.ols("y ~ x1 + x2 + x3", data=df).fit(cov_type="HC3")
coef_df = (model.params.to_frame("coef")
           .join(model.conf_int().rename(columns={0: "lo", 1: "hi"}))
           .drop("Intercept"))

fig, ax = plt.subplots(figsize=(5, len(coef_df) * 0.5 + 1))
y_pos = range(len(coef_df))
ax.errorbar(coef_df["coef"], y_pos,
            xerr=[coef_df["coef"] - coef_df["lo"],
                  coef_df["hi"] - coef_df["coef"]],
            fmt="o", color=PALETTE_CB[0], capsize=3)
ax.axvline(0, linestyle="--", color="gray", linewidth=0.8)
ax.set_yticks(y_pos)
ax.set_yticklabels(coef_df.index)
ax.set_xlabel("Coefficient (95% CI)")
save_fig(fig, "fig-coef")
```

### P5 — Multi-Model Coefficient Plot

```python
# models = [model1, model2, model3] — fitted statsmodels results
offsets = [-0.15, 0, 0.15]
colors = PALETTE_CB[:3]
labels = ["Model 1", "Model 2", "Model 3"]

coefs = []
for m, off, c, lbl in zip(models, offsets, colors, labels):
    tidy = (m.params.to_frame("coef")
            .join(m.conf_int().rename(columns={0: "lo", 1: "hi"}))
            .drop("Intercept"))
    tidy["offset"] = off
    tidy["color"] = c
    tidy["label"] = lbl
    coefs.append(tidy)

fig, ax = plt.subplots(figsize=(6, len(coefs[0]) * 0.6 + 1))
for tidy in coefs:
    y = np.arange(len(tidy)) + tidy["offset"].iloc[0]
    ax.errorbar(tidy["coef"], y,
                xerr=[tidy["coef"] - tidy["lo"], tidy["hi"] - tidy["coef"]],
                fmt="o", color=tidy["color"].iloc[0], capsize=3,
                label=tidy["label"].iloc[0])
ax.axvline(0, linestyle="--", color="gray", linewidth=0.8)
ax.set_yticks(range(len(coefs[0])))
ax.set_yticklabels(coefs[0].index)
ax.set_xlabel("Coefficient (95% CI)")
ax.legend(loc="lower right")
save_fig(fig, "fig-coef-multi")
```

### P6 — Marginal Effects (AME with CI)

```python
from marginaleffects import avg_slopes

ame = avg_slopes(model).to_pandas()
fig, ax = plt.subplots(figsize=(5, len(ame) * 0.5 + 1))
y_pos = range(len(ame))
ax.errorbar(ame["estimate"], y_pos,
            xerr=[ame["estimate"] - ame["conf_low"],
                  ame["conf_high"] - ame["estimate"]],
            fmt="s", color=PALETTE_CB[0], capsize=3)
ax.axvline(0, linestyle="--", color="gray", linewidth=0.8)
ax.set_yticks(y_pos)
ax.set_yticklabels(ame["term"])
ax.set_xlabel("Average Marginal Effect (95% CI)")
save_fig(fig, "fig-ame")
```

### P7 — Interaction Marginal Effects

```python
from marginaleffects import plot_slopes

fig = plot_slopes(model, variables="x", condition="moderator").draw()
save_fig(fig, "fig-interaction-me")
```

### P8 — Predicted Probabilities

```python
from marginaleffects import plot_predictions

fig = plot_predictions(model, condition=["x", "group"]).draw()
save_fig(fig, "fig-predicted-prob")
```

### P9 — Event Study (DiD)

```python
# es_df has columns: period, estimate, ci_lo, ci_hi
fig, ax = plt.subplots()
ax.errorbar(es_df["period"], es_df["estimate"],
            yerr=[es_df["estimate"] - es_df["ci_lo"],
                  es_df["ci_hi"] - es_df["estimate"]],
            fmt="o-", color=PALETTE_CB[0], capsize=3)
ax.axhline(0, linestyle="--", color="gray", linewidth=0.8)
ax.axvline(-0.5, linestyle=":", color="red", alpha=0.5, label="Treatment")
ax.set_xlabel("Periods Relative to Treatment")
ax.set_ylabel("Estimate")
ax.legend()
save_fig(fig, "fig-event-study")
```

### P10 — RD Plot

```python
from rdrobust import rdplot

fig = rdplot(y=df["outcome"], x=df["running_var"], c=0,
             ci=95, title="", x_label="Running Variable",
             y_label="Outcome")
plt.gcf().savefig(f"{OUTPUT_ROOT}/figures/fig-rd.pdf", dpi=300, bbox_inches="tight")
plt.gcf().savefig(f"{OUTPUT_ROOT}/figures/fig-rd.png", dpi=300, bbox_inches="tight")
```

### P11 — Balance / Love Plot

```python
# balance_df has columns: variable, smd_before, smd_after
fig, ax = plt.subplots(figsize=(6, len(balance_df) * 0.4 + 1))
y = range(len(balance_df))
ax.scatter(balance_df["smd_before"], y, marker="x", color=PALETTE_CB[6], label="Before", s=50)
ax.scatter(balance_df["smd_after"], y, marker="o", color=PALETTE_CB[0], label="After", s=50)
ax.axvline(0.1, linestyle="--", color="gray", linewidth=0.8)
ax.axvline(-0.1, linestyle="--", color="gray", linewidth=0.8)
ax.set_yticks(y)
ax.set_yticklabels(balance_df["variable"])
ax.set_xlabel("Standardized Mean Difference")
ax.legend()
save_fig(fig, "fig-balance")
```

### P12 — Correlation Heatmap

```python
corr = df[numeric_cols].corr()
mask = np.triu(np.ones_like(corr, dtype=bool))
fig, ax = plt.subplots(figsize=(8, 6))
sns.heatmap(corr, mask=mask, annot=True, fmt=".2f", cmap="RdBu_r",
            center=0, vmin=-1, vmax=1, square=True, ax=ax)
save_fig(fig, "fig-corr-heatmap", w=8, h=6)
```

### P13 — Faceted Scatter (Gapminder style)

```python
g = sns.FacetGrid(df, col="continent", col_wrap=3, height=3, aspect=1.2)
g.map_dataframe(sns.scatterplot, x="gdp_per_cap", y="life_exp",
                hue="year", palette="viridis", alpha=0.7)
g.set_axis_labels("GDP per Capita (log)", "Life Expectancy")
g.add_legend()
g.savefig(f"{OUTPUT_ROOT}/figures/fig-facet-scatter.pdf", dpi=300, bbox_inches="tight")
g.savefig(f"{OUTPUT_ROOT}/figures/fig-facet-scatter.png", dpi=300, bbox_inches="tight")
```

### P14 — Survey Estimate + Margin of Error

```python
fig, ax = plt.subplots(figsize=(8, len(est_df) * 0.4 + 1))
y = range(len(est_df))
ax.errorbar(est_df["estimate"], y,
            xerr=est_df["moe"],
            fmt="o", color=PALETTE_CB[0], capsize=3)
ax.set_yticks(y)
ax.set_yticklabels(est_df["geography"])
ax.set_xlabel("Estimate (+/- Margin of Error)")
save_fig(fig, "fig-survey-moe")
```

### P15 — Choropleth / Geospatial Map

```python
import geopandas as gpd

fig, ax = plt.subplots(figsize=(10, 8))
gdf.plot(column="outcome", cmap="viridis", legend=True,
         edgecolor="white", linewidth=0.3, ax=ax)
ax.set_axis_off()
save_fig(fig, "fig-choropleth", w=10, h=8)
```

### P16 — Interactive Plots (plotly)

```python
import plotly.express as px

fig = px.scatter(df, x="x", y="y", color="group", hover_data=["label"],
                 color_discrete_sequence=PALETTE_CB)
fig.update_layout(template="plotly_white")
fig.write_html(f"{OUTPUT_ROOT}/figures/fig-interactive.html")
```

### P17 — Network Visualization

```python
import networkx as nx

fig, ax = plt.subplots(figsize=(8, 8))
pos = nx.spring_layout(G, seed=42)
nx.draw_networkx_nodes(G, pos, node_size=50, node_color=PALETTE_CB[0],
                       alpha=0.7, ax=ax)
nx.draw_networkx_edges(G, pos, alpha=0.3, ax=ax)
ax.set_axis_off()
save_fig(fig, "fig-network", w=8, h=8)
```

### P18 — Raincloud Plot

```python
import ptitprince as pt

fig, ax = plt.subplots(figsize=(8, 5))
pt.RainCloud(x="group", y="outcome", data=df, palette=PALETTE_CB,
             bw=0.2, width_viol=0.6, orient="h", ax=ax)
ax.set_xlabel("Outcome")
ax.set_ylabel("")
save_fig(fig, "fig-raincloud", w=8, h=5)
```

### P19 — Ridgeline Plot

```python
from joypy import joyplot

fig, axes = joyplot(df, by="group", column="outcome",
                    colormap=plt.cm.viridis, alpha=0.6,
                    figsize=(6, 5))
plt.xlabel("Outcome")
save_fig(plt.gcf(), "fig-ridgeline")
```

### P20 — Alluvial / Sankey Flow Diagram

```python
import plotly.graph_objects as go

fig = go.Figure(go.Sankey(
    node=dict(label=node_labels, color=PALETTE_CB[:len(node_labels)]),
    link=dict(source=sources, target=targets, value=values)
))
fig.update_layout(font_size=12)
fig.write_image(f"{OUTPUT_ROOT}/figures/fig-sankey.pdf")
fig.write_image(f"{OUTPUT_ROOT}/figures/fig-sankey.png", scale=3)
```

### P21 — CATE / Heterogeneous Treatment Effect Plot

```python
# cate_df has columns: subgroup, cate, ci_lo, ci_hi
fig, ax = plt.subplots(figsize=(6, len(cate_df) * 0.5 + 1))
y = range(len(cate_df))
ax.errorbar(cate_df["cate"], y,
            xerr=[cate_df["cate"] - cate_df["ci_lo"],
                  cate_df["ci_hi"] - cate_df["cate"]],
            fmt="D", color=PALETTE_CB[0], capsize=3)
ax.axvline(0, linestyle="--", color="gray", linewidth=0.8)
# Add ATE reference line
ax.axvline(ate, linestyle="-", color=PALETTE_CB[1], linewidth=1, alpha=0.7, label=f"ATE = {ate:.3f}")
ax.set_yticks(y)
ax.set_yticklabels(cate_df["subgroup"])
ax.set_xlabel("Conditional Average Treatment Effect (95% CI)")
ax.legend()
save_fig(fig, "fig-cate")
```

### P22 — Cleveland Dot Plot

```python
# ranked_df has columns: category, value, sorted by value
fig, ax = plt.subplots(figsize=(6, len(ranked_df) * 0.35 + 1))
y = range(len(ranked_df))
ax.scatter(ranked_df["value"], y, color=PALETTE_CB[0], s=60, zorder=3)
ax.hlines(y, 0, ranked_df["value"], color="gray", linewidth=0.5)
ax.set_yticks(y)
ax.set_yticklabels(ranked_df["category"])
ax.set_xlabel("Value")
save_fig(fig, "fig-cleveland")
```

### P23 — Slope Chart (change between two time points)

```python
fig, ax = plt.subplots(figsize=(4, 5))
for _, row in paired_df.iterrows():
    ax.plot([0, 1], [row["time1"], row["time2"]], "o-",
            color=PALETTE_CB[0], alpha=0.5)
ax.set_xticks([0, 1])
ax.set_xticklabels(["Time 1", "Time 2"])
ax.set_ylabel("Outcome")
save_fig(fig, "fig-slope", w=4, h=5)
```

### P24 — Waffle Chart

```python
from pywaffle import Waffle

fig = plt.figure(
    FigureClass=Waffle,
    rows=10,
    values=proportions,  # list of counts
    labels=labels,
    colors=PALETTE_CB[:len(labels)],
    legend={"loc": "lower left", "bbox_to_anchor": (0, -0.2), "ncol": len(labels)}
)
save_fig(fig, "fig-waffle")
```

### P25 — Posterior Distribution Plot (Bayesian)

```python
import arviz as az

fig, ax = plt.subplots()
az.plot_posterior(trace, var_names=["x_coef"],
                 hdi_prob=0.95, ref_val=0,
                 color=PALETTE_CB[0], ax=ax)
ax.set_xlabel("Posterior of coefficient")
save_fig(fig, "fig-posterior")
```

---

## Package Reference

| Template | Required packages |
|----------|------------------|
| P1-P5, P12 | `matplotlib`, `seaborn`, `statsmodels` |
| P6-P8 | `marginaleffects` |
| P9, P11, P14, P21-P23 | `matplotlib` (core) |
| P10 | `rdrobust` |
| P13 | `seaborn` (FacetGrid) |
| P15 | `geopandas`, `matplotlib` |
| P16, P20 | `plotly` |
| P17 | `networkx`, `matplotlib` |
| P18 | `ptitprince` |
| P19 | `joypy` |
| P24 | `pywaffle` |
| P25 | `arviz` |
