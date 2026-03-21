## MODULE 9: Geospatial and Spatial Analysis

### Step 1 — When to Use Spatial Methods

Spatial methods are appropriate when:
- Outcome or covariates vary across geographic units (census tracts, counties, states)
- **Spatial autocorrelation** is present in residuals (Moran's I test is significant)
- Research involves **neighborhood spillover effects** — outcomes in one unit affect neighbors
- You need to map geographic patterns as evidence (choropleth visualization)
- You are linking individual-level survey data to area-level characteristics (contextual effects)

Ignoring spatial autocorrelation when present produces invalid SEs (analogous to ignoring clustering). Run a diagnostic before choosing the model.

**Method selection:**
| Pattern in Moran's I | Recommendation |
|---------------------|---------------|
| Residuals spatially autocorrelated; substantive neighbor spillovers | **Spatial lag model** (SAR) |
| Residuals spatially autocorrelated; no theoretical spillover | **Spatial error model** (SEM) |
| Both substantive spillovers and error autocorrelation | **SARAR** (Kelejian-Prucha) |
| Autocorrelation present only in specific covariate | **Spatial Durbin model** |
| No autocorrelation detected | OLS / standard GLM (use `/scholar-causal`) |

---

### Step 2 — Build Spatial Data with sf + tidycensus

```r
library(sf)
library(tidycensus)
library(tidyverse)

# ── ACS data (Census tract / county) ──────────────────────────────────
# Set Census API key once:  tidycensus::census_api_key("YOUR_KEY", install=TRUE)

# Download ACS 5-year estimates at county level
acs_county <- get_acs(
  geography = "county",
  variables = c(
    poverty_rate    = "B17001_002",   # population in poverty
    total_pop       = "B01003_001",
    median_income   = "B19013_001",
    pct_college     = "B15003_022",
    pct_unemployed  = "B23025_005"
  ),
  year       = 2022,
  survey     = "acs5",
  geometry   = TRUE,           # download spatial geometries as sf object
  output     = "wide",
  state      = NULL            # NULL = all states; or "CA" for single state
) |>
  mutate(
    poverty_rate = poverty_rateE / total_popE * 100,
    pct_college  = pct_collegeE  / total_popE * 100
  )

# Coordinate reference system: project to Albers Equal Area for CONUS
acs_county <- st_transform(acs_county, crs=5070)

# ── Join external data to spatial object ──────────────────────────────
df_county <- read_csv("data/county-outcome.csv")  # must have GEOID column (5-digit county FIPS)
spatial_df <- acs_county |>
  left_join(df_county, by="GEOID")

# ── Basic spatial visualization ────────────────────────────────────────
library(tmap)
tmap_mode("plot")

tm_shape(spatial_df) +
  tm_fill("median_incomeE",
          palette   = "Blues",
          style     = "jenks",   # natural breaks
          title     = "Median Household Income") +
  tm_borders(alpha=0.3) +
  tm_layout(main.title="County-Level Median Income, ACS 2022",
            legend.outside=TRUE)
tmap_save(filename="${OUTPUT_ROOT}/figures/fig-choropleth-income.pdf", width=10, height=7)

# ggplot2 alternative (for publication formatting)
ggplot(spatial_df) +
  geom_sf(aes(fill=median_incomeE), color="white", linewidth=0.1) +
  scale_fill_viridis_c(option="B", labels=scales::comma,
                       name="Median Income ($)") +
  coord_sf(crs=5070) +
  labs(fill="Median Income ($)") +
  theme_void()
ggsave("${OUTPUT_ROOT}/figures/fig-choropleth-ggplot.pdf", width=12, height=8)
```

---

### Step 3 — Spatial Weights Matrix + Moran's I Diagnostic

```r
library(spdep)

# ── Build spatial weights matrix ──────────────────────────────────────
# Queen contiguity (share at least one point, including corners)
nb_queen <- poly2nb(spatial_df, queen=TRUE)

# K-nearest neighbors alternative (use when many islands / non-contiguous units)
coords   <- st_centroid(spatial_df) |> st_coordinates()
nb_knn   <- knearneigh(coords, k=5) |> knn2nb()

# Convert to listw object (row-standardized)
lw_queen <- nb2listw(nb_queen, style="W", zero.policy=TRUE)

# ── Moran's I test on OLS residuals ──────────────────────────────────
ols_fit <- lm(outcome ~ poverty_rate + median_incomeE + pct_college,
              data=spatial_df)
moran_test <- moran.test(residuals(ols_fit), lw_queen, zero.policy=TRUE)
print(moran_test)
# If p < 0.05: spatial autocorrelation present → proceed to spatial regression
# If p > 0.05: no autocorrelation → standard OLS is sufficient

# ── Moran scatterplot ─────────────────────────────────────────────────
moran.plot(residuals(ols_fit), lw_queen, zero.policy=TRUE,
           main="Moran Scatterplot of OLS Residuals",
           xlab="OLS Residuals", ylab="Spatially Lagged Residuals")

# ── Lagrange Multiplier tests (guide model selection) ─────────────────
lm_tests <- lm.LMtests(ols_fit, lw_queen,
                        test=c("LMlag", "LMerr", "RLMlag", "RLMerr"),
                        zero.policy=TRUE)
print(lm_tests)
# If RLMlag significant (not RLMerr) → spatial lag model
# If RLMerr significant (not RLMlag) → spatial error model
# If both → SARAR or spatial Durbin model

# ── Local Moran's I (LISA) — identify spatial clusters ────────────────
local_moran <- localmoran(spatial_df$outcome, lw_queen, zero.policy=TRUE)
spatial_df$local_I     <- local_moran[, "Ii"]
spatial_df$local_p     <- local_moran[, "Pr(z != E(Ii))"]
spatial_df$LISA_cluster <- case_when(
  spatial_df$outcome    > mean(spatial_df$outcome) &
    lag.listw(lw_queen, spatial_df$outcome) > mean(spatial_df$outcome) &
    spatial_df$local_p < 0.05 ~ "High-High",
  spatial_df$outcome    < mean(spatial_df$outcome) &
    lag.listw(lw_queen, spatial_df$outcome) < mean(spatial_df$outcome) &
    spatial_df$local_p < 0.05 ~ "Low-Low",
  spatial_df$outcome    > mean(spatial_df$outcome) &
    lag.listw(lw_queen, spatial_df$outcome) < mean(spatial_df$outcome) &
    spatial_df$local_p < 0.05 ~ "High-Low",
  spatial_df$local_p < 0.05 ~ "Low-High",
  TRUE ~ "Not significant"
)

# LISA map
ggplot(spatial_df) +
  geom_sf(aes(fill=LISA_cluster), color="white", linewidth=0.1) +
  scale_fill_manual(
    values=c("High-High"="#d7191c", "Low-Low"="#2c7bb6",
             "High-Low"="#fdae61", "Low-High"="#abd9e9",
             "Not significant"="grey90")) +
  labs(fill="Cluster Type") +
  theme_void()
ggsave("${OUTPUT_ROOT}/figures/fig-lisa-map.pdf", width=10, height=7)
```

---

### Step 4 — Spatial Regression Models

```r
library(spatialreg)

# ── Spatial Lag Model (SAR) — y = ρWy + Xβ + ε ───────────────────────
# Use when: substantive neighbor spillovers (H: neighbors' outcomes affect focal unit)
sar_model <- lagsarlm(
  formula     = outcome ~ poverty_rate + median_incomeE + pct_college,
  data        = spatial_df,
  listw       = lw_queen,
  zero.policy = TRUE
)
summary(sar_model, Nagelkerke=TRUE)
# ρ (spatial lag coefficient): positive = high-[outcome] neighbors increase focal outcome

# ── Spatial Error Model (SEM) — y = Xβ + u, u = λWu + ε ─────────────
# Use when: autocorrelation is a nuisance (omitted spatial variable) not substantive
sem_model <- errorsarlm(
  formula     = outcome ~ poverty_rate + median_incomeE + pct_college,
  data        = spatial_df,
  listw       = lw_queen,
  zero.policy = TRUE
)
summary(sem_model, Nagelkerke=TRUE)
# λ (spatial error coefficient): mops up unmeasured spatial structure

# ── Model comparison ─────────────────────────────────────────────────
AIC(ols_fit, sar_model, sem_model)
# Also compare Moran's I on residuals after spatial correction
moran.test(residuals(sar_model), lw_queen, zero.policy=TRUE)
moran.test(residuals(sem_model), lw_queen, zero.policy=TRUE)

# ── Impacts (direct, indirect, total) in spatial lag model ────────────
# In SAR, each covariate has: direct effect (own-unit) + indirect (spillover)
impacts_sar <- impacts(sar_model, listw=lw_queen, R=500)
print(summary(impacts_sar, zstats=TRUE, short=TRUE))
# Report: direct impact + indirect (spillover) impact + total impact per covariate

# ── Export tables ─────────────────────────────────────────────────────
library(modelsummary)
modelsummary(list("OLS"=ols_fit, "Spatial Lag"=sar_model, "Spatial Error"=sem_model),
             gof_omit   = "IC|Log|Adj",
             output     = "${OUTPUT_ROOT}/tables/table-spatial-regression.html",
             title      = "Spatial Regression Models",
             notes      = "Spatial weights: Queen contiguity, row-standardized.")
```

**Spatial panel data** (units × time, with spatial autocorrelation):
```r
library(splm)
# spdm() for spatial panel with fixed/random effects
spanel <- spml(
  formula  = outcome ~ treatment + poverty_rate,
  data     = panel_df,
  listw    = lw_queen,
  lag      = TRUE,    # spatial lag
  spatial.error = "none",
  model    = "within",  # fixed effects
  index    = c("GEOID", "year")
)
summary(spanel)
```

---

### Step 5 — Geospatial Verification (Subagent)

```
GEOSPATIAL VERIFICATION REPORT
================================

DATA AND CRS
[ ] CRS documented (EPSG code reported); projection appropriate for study region
[ ] Units of analysis (tract / county / state) documented and justified
[ ] Spatial weights type (queen contiguity / KNN / distance-band) documented and justified
[ ] N units reported; any islands / disconnected units handled (zero.policy=TRUE)

MORAN'S I DIAGNOSTIC
[ ] Moran's I computed on OLS residuals (not raw outcome)
[ ] Moran's I statistic and p-value reported
[ ] LM tests (LMlag, LMerr, RLMlag, RLMerr) run to guide model selection
[ ] Model selection (SAR / SEM / SARAR / OLS) justified based on LM tests

SPATIAL REGRESSION (if used)
[ ] ρ (SAR) or λ (SEM) reported with SE and p-value
[ ] SAR impacts table (direct / indirect / total) computed and reported
[ ] Moran's I on spatial model residuals confirms autocorrelation removed
[ ] AIC comparison OLS vs. spatial model reported
[ ] Tables exported to output/[slug]/tables/

VISUALIZATION
[ ] Choropleth map uses colorblind-safe palette (viridis / Blues / diverging)
[ ] LISA cluster map uses correct 4-category color scheme
[ ] Maps saved as PDF + PNG

REPORTING
[ ] Data source cited (ACS year, variables, tidycensus version)
[ ] Spatial weights construction described
[ ] Limitations of spatial weights choice discussed (e.g., queen contiguity for irregular shapes)

RESULT: [PASS / NEEDS REVISION]
Issues: [list]
```

**Reporting template:**
> "We estimate [spatial lag / spatial error] models using the `spatialreg` package (Bivand and Piras 2015) with queen-contiguity spatial weights (row-standardized). We first confirmed the presence of spatial autocorrelation using Moran's I test on OLS residuals (Moran's I = [X], p = [p]). Lagrange Multiplier tests indicated [spatial lag / spatial error] specification (RLMlag = [X], p = [p]; RLMerr = [X], p = [p]). In the spatial lag model, the spatial autoregressive parameter ρ = [X] (SE = [SE]; p = [p]), indicating that [higher / lower] [outcome] in neighboring counties is associated with [higher / lower] focal county [outcome]. Direct, indirect (spillover), and total impacts are reported in Table [X]. After accounting for spatial dependence, residual Moran's I = [X] (p = [p]), confirming adequate correction."

---

