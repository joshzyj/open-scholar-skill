### T1 — Distribution (histogram + density)

```r
p <- ggplot(df, aes(x = outcome)) +
  geom_histogram(aes(y = after_stat(density)), bins = 30,
                 fill = palette_cb[1], color = "white", alpha = 0.8) +
  geom_density(linewidth = 0.9, color = palette_cb[7]) +
  labs(x = "Outcome Variable", y = "Density",
       title = "Distribution of [Outcome]") +
  theme_Publication()
save_fig(p, "fig-dist-outcome")
```

---

### T2 — Grouped Violin + Boxplot

```r
p <- ggplot(df, aes(x = group, y = outcome, fill = group)) +
  geom_violin(alpha = 0.55, trim = FALSE) +
  geom_boxplot(width = 0.12, fill = "white",
               outlier.shape = NA, coef = 0) +
  # For small N (<30 per group): add individual points
  # geom_jitter(width = 0.05, alpha = 0.4, size = 0.9)
  scale_fill_Publication() +
  labs(x = NULL, y = "Outcome") +
  theme_Publication() + theme(legend.position = "none")
save_fig(p, "fig-violin-group")
```

---

### T3 — Bar Chart with Percentages

```r
p <- df |>
  count(group, category) |>
  mutate(pct = n / sum(n), .by = group) |>
  ggplot(aes(x = group, y = pct, fill = category)) +
  geom_col(position = "dodge") +
  scale_y_continuous(labels = percent_format(accuracy = 1)) +
  scale_fill_Publication() +
  labs(x = NULL, y = "Percent", fill = NULL) +
  theme_Publication()
save_fig(p, "fig-bar-pct")
```

---

### T4 — Coefficient / Forest Plot (single model)

```r
p <- modelplot(m2, coef_omit = "Intercept|factor") +
  geom_vline(xintercept = 0, linetype = "dashed", color = "gray50") +
  labs(x = "Coefficient (95% CI)", y = NULL) +
  theme_Publication()
save_fig(p, "fig-coef-single")
```

---

### T5 — Multi-Model Coefficient Plot

```r
p <- modelplot(
  list("Baseline" = m1, "+Controls" = m2, "+Fixed Effects" = m_fe),
  coef_omit = "Intercept|factor"
) +
  geom_vline(xintercept = 0, linetype = "dashed", color = "gray50") +
  scale_color_Publication() +
  labs(x = "Coefficient (95% CI)", y = NULL, color = "Model") +
  theme_Publication()
save_fig(p, "fig-coef-multimodel", width = 7, height = 5)
```

---

### T6 — Marginal Effects (AME with CI)

```r
library(marginaleffects)

p <- plot_slopes(m_logit, variables = "x") +
  geom_hline(yintercept = 0, linetype = "dashed", color = "gray50") +
  labs(x = "Predictor Value", y = "Average Marginal Effect",
       title = "AME of X on P(Y=1)") +
  theme_Publication()
save_fig(p, "fig-ame-x")
```

---

### T7 — Interaction Marginal Effects

```r
# Continuous moderator — ribbon
p <- plot_slopes(m_logit, variables = "x", condition = "moderator") +
  scale_color_Publication() + scale_fill_Publication() +
  labs(x = "Moderator", y = "Marginal Effect of X",
       color = NULL, fill = NULL) +
  theme_Publication()
save_fig(p, "fig-ame-interaction")

# Categorical moderator — dodge points
p <- plot_slopes(m_logit, variables = "x",
                 condition = list("x", "group" = levels(df$group))) +
  scale_color_Publication() +
  theme_Publication()
save_fig(p, "fig-ame-by-group")
```

---

### T8 — Predicted Probabilities

```r
p <- plot_predictions(m_logit,
                      condition = list("x", "group")) +
  scale_color_Publication() + scale_fill_Publication() +
  labs(x = "X", y = "Predicted Probability", color = "Group", fill = "Group") +
  theme_Publication()
save_fig(p, "fig-predicted-prob")
```

---

### T9 — Event Study (DiD)

```r
library(fixest); library(broom); library(stringr)

m_es <- feols(y ~ i(year_rel, treated, ref = -1) | unit_id + year,
              data = df, cluster = ~unit_id)

es_df <- tidy(m_es, conf.int = TRUE) |>
  filter(str_detect(term, "year_rel")) |>
  mutate(
    year_rel = as.numeric(str_extract(term, "-?\\d+")),
    sig = if_else(p.value < 0.05, "p < .05", "p ≥ .05")
  )

p <- ggplot(es_df, aes(x = year_rel, y = estimate,
                       ymin = conf.low, ymax = conf.high)) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "gray50") +
  geom_vline(xintercept = -0.5, linetype = "dotted", color = "firebrick") +
  geom_ribbon(alpha = 0.15, fill = palette_cb[1]) +
  geom_line(color = palette_cb[1]) +
  geom_point(aes(color = sig), size = 2.5) +
  scale_color_manual(values = c("p < .05" = palette_cb[7],
                                "p ≥ .05" = palette_cb[1])) +
  labs(x = "Years Relative to Treatment", y = "Estimated Effect (95% CI)",
       color = NULL) +
  theme_Publication()
save_fig(p, "fig-event-study")
```

---

### T10 — RD Plot (custom ggplot)

```r
# Custom ggplot version (more control than rdplot)
p <- ggplot(df, aes(x = running_var, y = outcome)) +
  geom_point(alpha = 0.3, size = 0.8, color = "gray40") +
  geom_smooth(data = filter(df, running_var < cutoff),
              method = "lm", se = TRUE, color = palette_cb[1]) +
  geom_smooth(data = filter(df, running_var >= cutoff),
              method = "lm", se = TRUE, color = palette_cb[2]) +
  geom_vline(xintercept = cutoff, linetype = "dashed") +
  labs(x = "Running Variable", y = "Outcome") +
  theme_Publication()
save_fig(p, "fig-rd-plot")
```

---

### T11 — Balance / Love Plot

```r
library(cobalt)

p <- love.plot(m_match,
               thresholds = c(m = 0.1),
               abs        = TRUE,
               var.order  = "standardized",
               colors     = palette_cb[c(1, 7)],
               shapes     = c("circle", "triangle")) +
  theme_Publication()
save_fig(p, "fig-love-plot")
```

---

### T12 — Correlation Heatmap

```r
library(ggcorrplot)

cor_mat <- cor(select(df, where(is.numeric)), use = "pairwise.complete.obs")

p <- ggcorrplot(cor_mat,
                lab        = TRUE,
                lab_size   = 3,
                type       = "lower",
                colors     = c(palette_cb[1], "white", palette_cb[7])) +
  theme_Publication()
save_fig(p, "fig-corr-heatmap", width = 7, height = 6)
```

---

### T13 — Faceted Scatter (Gapminder style)

```r
library(gapminder)

p <- ggplot(gapminder, aes(x = gdpPercap, y = lifeExp,
                           size = pop, color = continent)) +
  geom_point(alpha = 0.7) +
  scale_x_log10(labels = scales::comma) +
  scale_size_continuous(range = c(1, 12), guide = "none") +
  scale_color_Publication() +
  facet_wrap(~year) +
  labs(x = "GDP per Capita (log scale)", y = "Life Expectancy",
       color = NULL) +
  theme_Publication() +
  theme(legend.position = "bottom")
save_fig(p, "fig-facet-scatter-gapminder", width = 9, height = 6)
```

For your own data (e.g., group × time):
```r
p <- ggplot(df, aes(x = x_var, y = outcome, color = group)) +
  geom_point(alpha = 0.6) +
  geom_smooth(method = "lm", se = FALSE, linewidth = 0.8) +
  facet_wrap(~year, ncol = 3) +
  scale_color_Publication() +
  labs(x = "X", y = "Outcome", color = NULL) +
  theme_Publication()
save_fig(p, "fig-facet-scatter")
```

---

### T14 — ACS / Survey Estimate + Margin of Error

```r
# Pattern taught in SOC 591 (Week 3): tidycensus ACS data with MOE
library(tidycensus)

ny <- get_acs(geography = "county",
              variables = "B19013_001",   # median household income
              state     = "NY",
              geometry  = FALSE,
              year      = 2022)

p <- ny |>
  mutate(NAME = gsub(" County, New York", "", NAME)) |>
  ggplot(aes(x = estimate, y = reorder(NAME, estimate))) +
  geom_errorbar(aes(xmin = estimate - moe, xmax = estimate + moe),
                width = 0.3, linewidth = 0.5, color = "gray50") +
  geom_point(color = palette_cb[1], size = 2.5) +
  scale_x_continuous(labels = scales::dollar) +
  labs(title  = "Median Household Income by County",
       subtitle = "2022 ACS 5-Year Estimates (bars = margin of error)",
       x = "ACS Estimate", y = NULL) +
  theme_Publication()
save_fig(p, "fig-acs-moe-income", width = 7, height = 8)
```

---

### T15 — Choropleth / Geospatial Map

**US county choropleth (sf + tidycensus + tigris):**
```r
library(tidycensus); library(sf); library(tigris)

# Fetch all-state county data with geometry
census_df <- map_dfr(
  state.abb,
  ~ get_acs(geography = "county",
            variables = c(foreign_born = "B99051_005",
                          tot_pop      = "B01001_001"),
            state     = .x, year = 2022,
            survey    = "acs5", output = "wide",
            geometry  = TRUE)
) |>
  mutate(fb_rate = foreign_bornE / tot_popE) |>
  shift_geometry()   # rescale Alaska + Hawaii for national map

p <- ggplot(census_df, aes(fill = fb_rate)) +
  geom_sf(color = NA, linewidth = 0.05) +
  scale_fill_viridis_c(labels = scales::percent, name = "% Foreign-Born") +
  theme_void() +
  theme(legend.position = "bottom",
        legend.key.width = unit(1.5, "cm"))
save_fig(p, "fig-choropleth-foreign-born", width = 9, height = 6)
```

**State boundaries only:**
```r
us_states <- states(cb = TRUE, resolution = "20m")

p <- ggplot(us_states) +
  geom_sf(fill = "white", color = "gray60", linewidth = 0.3) +
  theme_void()
save_fig(p, "fig-us-states-base")
```

**County with labels:**
```r
ny_counties <- counties("NY", cb = TRUE, year = 2022)

p <- ggplot(ny_counties, aes(fill = AWATER / 1e6)) +
  geom_sf(color = "white", linewidth = 0.2) +
  geom_sf_text(aes(label = NAME), size = 2.5) +
  scale_fill_viridis_c("Water Area (km²)") +
  theme_void()
save_fig(p, "fig-ny-counties-water")
```

**Key tigris boundary functions:**
```r
states()                          # State boundaries
counties("TX")                    # County boundaries for Texas
tracts("NY", county = "Queens")   # Census tracts
zctas(state = "NY", starts_with = "100")  # ZIP codes (Manhattan)
congressional_districts()         # Congressional districts
options(tigris_use_cache = TRUE)  # Cache downloads locally
```

---

### T16 — Interactive Plots (plotly)

All ggplot figures can be made interactive with one line:
```r
library(plotly)
ggplotly(p)   # wrap any ggplot object — adds hover, zoom, pan
```

**Native plotly scatter with custom tooltips:**
```r
fig <- plot_ly(
  data = df,
  x    = ~x_var,
  y    = ~outcome,
  type = "scatter",
  mode = "markers",
  marker = list(size = 8, color = palette_cb[1], opacity = 0.7),
  text      = ~paste0(name_var, "<br>X: ", round(x_var, 2),
                      "<br>Y: ", round(outcome, 2)),
  hoverinfo = "text"
) |>
  layout(xaxis = list(title = "X Variable"),
         yaxis = list(title = "Outcome"))
fig
# htmlwidgets::saveWidget(fig, paste0(output_root, "/figures/fig-interactive-scatter.html"))
```

**Heatmap:**
```r
plot_ly(z = cor_matrix, type = "heatmap",
        colorscale = "RdBu", zmid = 0) |>
  layout(title = "Correlation Heatmap")
```

**3D surface (e.g., volcano elevation or response surface):**
```r
plot_ly(z = volcano, type = "surface") |>
  layout(scene = list(
    xaxis = list(title = "X"),
    yaxis = list(title = "Y"),
    zaxis = list(title = "Z")
  ))
```

**Ternary plot (three-part composition — e.g., racial composition):**
```r
plot_ly(data = df_composition,
        a = ~pct_white, b = ~pct_black, c = ~pct_hispanic,
        type = "scatterternary",
        mode = "markers",
        marker = list(color = palette_cb[1], size = 6))
```

**Save interactive plots:**
```r
library(htmlwidgets)
output_root <- Sys.getenv("OUTPUT_ROOT", "output")
saveWidget(fig, paste0(output_root, "/figures/fig-interactive.html"), selfcontained = TRUE)
# Also export static PNG via:
kaleido::save_image(fig, paste0(output_root, "/figures/fig-interactive.png"))
```

---

### T17 — Network Visualization

**visNetwork (recommended for most social network papers):**
```r
library(visNetwork)

# nodes: id, label, group (optional), value (size), color
# edges: from, to, weight (optional)
nodes <- data.frame(
  id    = 1:nrow(actor_df),
  label = actor_df$name,
  group = actor_df$type,       # colors groups automatically
  value = actor_df$degree      # scales node size by degree
)
edges <- data.frame(
  from   = edge_df$source,
  to     = edge_df$target,
  weight = edge_df$weight
)

visNetwork(nodes, edges) |>
  visGroups(groupname = "Group A", color = palette_cb[1]) |>
  visGroups(groupname = "Group B", color = palette_cb[2]) |>
  visLayout(randomSeed = 42) |>
  visOptions(highlightNearest = TRUE, nodesIdSelection = TRUE) |>
  visPhysics(stabilization = FALSE)
```

**Hierarchical / org-chart layout:**
```r
visNetwork(nodes_h, edges_h) |>
  visHierarchicalLayout(direction = "UD", sortMethod = "directed")
```

**networkD3 force-directed (D3.js — for larger networks):**
```r
library(networkD3)

forceNetwork(
  Links   = edge_df,    # data frame with 'source', 'target', 'value' (0-indexed)
  Nodes   = node_df,    # data frame with 'name', 'group'
  Source  = "source",
  Target  = "target",
  Value   = "value",
  NodeID  = "name",
  Group   = "group",
  opacity = 0.85,
  zoom    = TRUE
)
```

**networkD3 Sankey diagram (flows, alluvial — e.g., occupational mobility):**
```r
sankeyNetwork(
  Links  = flow_df,     # 'source', 'target', 'value'
  Nodes  = node_df,     # 'name'
  Source = "source", Target = "target", Value = "value",
  NodeID = "name",
  sinksRight = FALSE
)
```

**Save network widgets:**
```r
library(htmlwidgets)
net <- visNetwork(nodes, edges)
output_root <- Sys.getenv("OUTPUT_ROOT", "output")
saveWidget(net, paste0(output_root, "/figures/fig-network.html"), selfcontained = TRUE)
```

**visNetwork vs networkD3 decision guide:**

| Need | Package |
|------|---------|
| General network with UI controls | `visNetwork` |
| Tree / hierarchy / org chart | `visNetwork` with `visHierarchicalLayout()` |
| Sankey / flow diagram | `networkD3::sankeyNetwork()` |
| Large network (>5k nodes) + D3 control | `networkD3::forceNetwork()` |
| Static publication figure | `ggraph` + `igraph` → `save_fig()` |

---

### T18 — Raincloud Plot (distribution + box + raw data)

Combines half-violin, boxplot, and jittered points — superior to bar+errorbar for showing full distribution shape. Increasingly preferred in Nature journals and Science Advances.

```r
library(ggdist); library(gghalves)

p <- ggplot(df, aes(x = group, y = outcome, fill = group)) +
  # Half-violin (density)
  ggdist::stat_halfeye(
    adjust = 0.5, width = 0.6, justification = -0.2,
    .width = 0, point_colour = NA, alpha = 0.7
  ) +
  # Boxplot (narrow)
  geom_boxplot(width = 0.12, outlier.shape = NA, alpha = 0.5) +
  # Jittered raw points
  gghalves::geom_half_point(
    side = "l", range_scale = 0.4, alpha = 0.3, size = 1.2
  ) +
  scale_fill_Publication() +
  coord_flip() +
  labs(x = NULL, y = "Outcome") +
  theme_Publication() + theme(legend.position = "none")
save_fig(p, "fig-raincloud")
```

---

### T19 — Ridgeline Plot (distribution across many groups or time)

Shows density distributions stacked vertically — ideal for comparing distributions across many categories (e.g., income by state, sentiment by year).

```r
library(ggridges)

p <- ggplot(df, aes(x = outcome, y = reorder(group, outcome, FUN = median),
                    fill = after_stat(x))) +
  geom_density_ridges_gradient(
    scale = 1.5, rel_min_height = 0.01,
    quantile_lines = TRUE, quantiles = 2    # add median line
  ) +
  scale_fill_viridis_c(option = "plasma", name = "Value") +
  labs(x = "Outcome", y = NULL) +
  theme_Publication() +
  theme(legend.position = "right")
save_fig(p, "fig-ridgeline", width = 7, height = 6)

# Time-based ridgeline (e.g., income distribution by decade)
p <- ggplot(df, aes(x = income, y = factor(decade), fill = factor(decade))) +
  geom_density_ridges(alpha = 0.6, scale = 1.3) +
  scale_fill_Publication() +
  labs(x = "Income ($)", y = "Decade") +
  theme_Publication() + theme(legend.position = "none")
save_fig(p, "fig-ridgeline-time")
```

---

### T20 — Alluvial / Sankey Flow Diagram (categorical transitions)

Shows flows between categorical states across time — ideal for occupational mobility, educational pathways, migration flows, class transitions.

```r
library(ggalluvial)

# Data must be in lodes (long) or alluvia (wide) format
# Wide format: one row per individual, columns = time points
p <- ggplot(df_wide,
            aes(axis1 = status_t1, axis2 = status_t2, axis3 = status_t3,
                y = freq)) +
  geom_alluvium(aes(fill = status_t1), width = 1/12, alpha = 0.7) +
  geom_stratum(width = 1/12, fill = "grey90", color = "grey40") +
  geom_text(stat = "stratum", aes(label = after_stat(stratum)),
            size = 3) +
  scale_x_discrete(limits = c("Time 1", "Time 2", "Time 3"),
                   expand = c(0.1, 0.05)) +
  scale_fill_Publication() +
  labs(y = "Count", fill = "Origin Status") +
  theme_Publication() +
  theme(axis.text.y = element_blank(), axis.ticks.y = element_blank())
save_fig(p, "fig-alluvial-mobility", width = 8, height = 5)

# Long (lodes) format alternative
p <- ggplot(df_long,
            aes(x = time, stratum = status, alluvium = id,
                fill = status, label = status)) +
  geom_flow(stat = "alluvium", alpha = 0.5) +
  geom_stratum() +
  geom_text(stat = "stratum", size = 3) +
  scale_fill_Publication() +
  theme_Publication()
save_fig(p, "fig-alluvial-long")
```

---

### T21 — CATE / Heterogeneous Treatment Effect Plot

Shows conditional average treatment effects across subgroups or covariate values — pairs with `grf::causal_forest()` from scholar-causal Strategy 10.

```r
# From grf causal forest (see scholar-causal Strategy 10b)
library(grf)

# Option A: CATE by subgroup (forest plot style)
cate_df <- data.frame(
  subgroup = c("Male", "Female", "Age < 30", "Age 30-50", "Age > 50",
               "Low Educ", "High Educ"),
  estimate = c(0.15, 0.08, 0.22, 0.10, 0.05, 0.18, 0.07),
  ci_lo    = c(0.05, 0.01, 0.10, 0.02, -0.05, 0.08, -0.01),
  ci_hi    = c(0.25, 0.15, 0.34, 0.18, 0.15, 0.28, 0.15)
)

p <- ggplot(cate_df, aes(x = estimate, y = reorder(subgroup, estimate))) +
  geom_vline(xintercept = 0, linetype = "dashed", color = "gray50") +
  geom_errorbarh(aes(xmin = ci_lo, xmax = ci_hi),
                 height = 0.2, color = palette_cb[1]) +
  geom_point(size = 3, color = palette_cb[1]) +
  labs(x = "Conditional Average Treatment Effect (95% CI)",
       y = NULL, title = "Treatment Effect Heterogeneity") +
  theme_Publication()
save_fig(p, "fig-cate-subgroup")

# Option B: CATE as function of continuous covariate
tau_hat <- predict(cf)$predictions
p <- ggplot(data.frame(x = X[, "age"], tau = tau_hat),
            aes(x = x, y = tau)) +
  geom_point(alpha = 0.2, size = 0.8) +
  geom_smooth(method = "loess", color = palette_cb[1], se = TRUE) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "gray50") +
  labs(x = "Age", y = "Estimated CATE",
       title = "Treatment Effect by Age") +
  theme_Publication()
save_fig(p, "fig-cate-continuous")

# Option C: CATE heatmap (two covariates)
grid_df <- expand.grid(
  age = seq(20, 70, 5),
  income = seq(20000, 100000, 10000)
)
grid_X <- model.matrix(~ age + income - 1, data = grid_df)
grid_df$tau <- predict(cf, newdata = grid_X)$predictions

p <- ggplot(grid_df, aes(x = age, y = income / 1000, fill = tau)) +
  geom_tile() +
  scale_fill_viridis_c(name = "CATE") +
  labs(x = "Age", y = "Income ($1000s)",
       title = "Treatment Effect Surface") +
  theme_Publication()
save_fig(p, "fig-cate-heatmap")
```

---

### T22 — Cleveland Dot Plot (ranked comparisons)

Preferred over bar charts for comparing ranked values across categories — cleaner, less ink, better for many categories. Common in Demography and population studies.

```r
p <- ggplot(df_summary, aes(x = value, y = reorder(category, value))) +
  geom_segment(aes(xend = 0, yend = category),
               color = "gray70", linewidth = 0.4) +
  geom_point(size = 3, color = palette_cb[1]) +
  labs(x = "Value", y = NULL) +
  theme_Publication()
save_fig(p, "fig-cleveland-dot", width = 6, height = 7)

# Paired Cleveland dot (before/after, two groups)
p <- ggplot(df_paired) +
  geom_segment(aes(x = value_before, xend = value_after,
                   y = reorder(category, value_after),
                   yend = category),
               color = "gray70", linewidth = 0.4) +
  geom_point(aes(x = value_before, y = category),
             color = palette_cb[2], size = 3) +
  geom_point(aes(x = value_after, y = category),
             color = palette_cb[1], size = 3) +
  labs(x = "Value", y = NULL,
       subtitle = "Orange = Before, Blue = After") +
  theme_Publication()
save_fig(p, "fig-cleveland-paired", width = 6, height = 7)
```

---

### T23 — Slope Chart (change between two time points)

Shows change direction and magnitude between exactly two time points — cleaner than grouped bar charts for before/after comparisons.

```r
p <- ggplot(df_slope) +
  geom_segment(aes(x = 1, xend = 2,
                   y = value_t1, yend = value_t2,
                   color = direction),
               linewidth = 0.6, alpha = 0.7) +
  geom_point(aes(x = 1, y = value_t1), size = 2.5, color = palette_cb[2]) +
  geom_point(aes(x = 2, y = value_t2), size = 2.5, color = palette_cb[1]) +
  geom_text(aes(x = 0.9, y = value_t1, label = category),
            hjust = 1, size = 3) +
  scale_x_continuous(breaks = c(1, 2), labels = c("Time 1", "Time 2"),
                     limits = c(0.3, 2.3)) +
  scale_color_manual(values = c("increase" = palette_cb[3],
                                "decrease" = palette_cb[7])) +
  labs(x = NULL, y = "Value") +
  theme_Publication() + theme(legend.position = "none")
save_fig(p, "fig-slope-chart", width = 6, height = 5)
```

---

### T24 — Waffle Chart (proportions as unit squares)

Alternative to pie charts — shows proportions as discrete units. Better for communicating "X out of 100" to general audiences (Science Advances, Nature).

```r
library(waffle)

# Named vector of counts (per 100 or per N)
vals <- c("Group A" = 35, "Group B" = 25, "Group C" = 20, "Other" = 20)

p <- waffle(vals, rows = 10, size = 0.5,
            colors = palette_cb[1:4]) +
  labs(title = "Distribution by Group (per 100)") +
  theme_Publication() +
  theme(legend.position = "bottom")
save_fig(p, "fig-waffle")
```

---

### T25 — Posterior Distribution Plot (Bayesian — pairs with A3b)

Shows posterior densities with credible intervals — standard for Bayesian analysis reporting.

```r
library(tidybayes); library(ggdist)

p <- m_bayes |>
  spread_draws(b_x, b_control1, b_control2) |>
  pivot_longer(cols = starts_with("b_"), names_to = "param", values_to = "value") |>
  mutate(param = gsub("b_", "", param)) |>
  ggplot(aes(x = value, y = param)) +
  ggdist::stat_halfeye(
    .width = c(0.66, 0.95),
    fill = palette_cb[1], alpha = 0.7,
    point_interval = "median_hdi"
  ) +
  geom_vline(xintercept = 0, linetype = "dashed", color = "gray50") +
  labs(x = "Posterior Estimate", y = NULL,
       title = "Posterior Distributions (66% and 95% CrI)") +
  theme_Publication()
save_fig(p, "fig-posterior-halfeye")

# Posterior predictive check overlay
p <- pp_check(m_bayes, ndraws = 50) +
  scale_color_manual(values = c("y" = "black", "yrep" = palette_cb[5])) +
  theme_Publication()
save_fig(p, "fig-pp-check")
```

---

