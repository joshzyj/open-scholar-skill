# Network Analysis Reference

## Network Data Preparation

```python
import networkx as nx
import pandas as pd

# From edge list (most common format)
edges = pd.read_csv("edges.csv")  # columns: source, target, [weight, year, type]
G = nx.from_pandas_edgelist(edges, source="sender", target="receiver",
                             edge_attr=["weight"], create_using=nx.DiGraph())

# Add node attributes
nodes = pd.read_csv("nodes.csv")  # columns: id, [age, sex, education, ...]
nx.set_node_attributes(G, nodes.set_index("id").to_dict("index"))

print(f"Nodes: {G.number_of_nodes()}, Edges: {G.number_of_edges()}")
print(f"Density: {nx.density(G):.4f}")
```

```r
library(igraph)
g <- graph_from_data_frame(edges_df, directed = TRUE, vertices = nodes_df)
summary(g)
```

---

## Key Centrality Measures

```python
# Compute all centrality measures
def compute_centrality(G):
    results = {}
    G_undir = G.to_undirected()

    results["degree"]       = nx.degree_centrality(G)
    results["indegree"]     = nx.in_degree_centrality(G)
    results["outdegree"]    = nx.out_degree_centrality(G)
    results["betweenness"]  = nx.betweenness_centrality(G, normalized=True)
    results["closeness"]    = nx.closeness_centrality(G)
    results["eigenvector"]  = nx.eigenvector_centrality(G, max_iter=1000)
    results["pagerank"]     = nx.pagerank(G)
    results["clustering"]   = nx.clustering(G_undir)

    # Structural holes (Burt's constraint) — use networkx-addon or igraph
    # results["constraint"]   = burt_constraint(G)

    return pd.DataFrame(results)

centrality_df = compute_centrality(G)
```

---

## Community Detection

```python
import community as community_louvain

# Louvain (fast, good for large networks)
G_undir = G.to_undirected()
partition = community_louvain.best_partition(G_undir, random_state=42)
modularity = community_louvain.modularity(partition, G_undir)
print(f"Louvain: {len(set(partition.values()))} communities, Q = {modularity:.3f}")

# Leiden (improved resolution; recommended for research papers)
# pip install leidenalg python-igraph
import leidenalg as la
import igraph as ig
ig_g = ig.Graph.from_networkx(G_undir)
leiden_part = la.find_partition(ig_g, la.ModularityVertexPartition, seed=42)
print(f"Leiden: {len(leiden_part)} communities")
```

```r
library(igraph)
# Leiden via leidenr or built-in community detection
cl_louvain <- cluster_louvain(g, resolution = 1.0)
cl_leiden  <- cluster_leiden(g, objective_function = "modularity")
modularity(g, cl_louvain)
```

---

## Statistical Network Models

### Exponential Random Graph Models (ERGMs)

ERGMs test whether observed network statistics exceed what random chance would produce. Fit in R:

```r
library(ergm)
library(network)

# Convert igraph to network object
net <- asNetwork(g)

# Null model (only density)
m0 <- ergm(net ~ edges)

# Hypothesis: tie formation depends on homophily (same race)
m1 <- ergm(net ~ edges + nodematch("race"))

# Full model: edges + homophily + reciprocity + transitivity (GWESP)
m2 <- ergm(net ~ edges
               + nodematch("race")
               + nodematch("education")
               + mutual                         # reciprocity
               + gwesp(0.5, fixed = TRUE),      # transitivity
           control = control.ergm(MCMC.samplesize = 2000,
                                  seed = 42))
summary(m2)

# Goodness of fit
gof_m2 <- gof(m2)
plot(gof_m2)  # Should match observed degree distribution, etc.
```

**ERGM reporting template**:
> "We estimate exponential random graph models (ERGMs; Robins et al. 2007) to test whether the probability of a tie between two nodes is conditioned on node attributes and network structure. We include terms for [density (edges)], [homophily on race (nodematch)], [reciprocity (mutual)], and [transitivity (GWESP)]. Table [X] reports log-odds coefficients. A positive coefficient on nodematch(race) indicates that ties are significantly more likely within racial groups than between groups, consistent with H[X]."

---

### Stochastic Actor-Oriented Models (SAOMs / RSiena)

For co-evolution of networks and behavior over time:

```r
library(RSiena)

# Data: two waves of friendship network + behavior variable
friend_w1 <- sienaDependent(array(c(net_w1, net_w2), dim=c(N,N,2)))
behavior   <- sienaDependent(cbind(beh_w1, beh_w2), type="behavior")
sex        <- coCovar(sex)  # time-constant covariate

data <- sienaDataCreate(friend_w1, behavior, sex)

# Specify model
effects <- getEffects(data)
effects <- includeEffects(effects, transTrip, recip)         # network dynamics
effects <- includeEffects(effects, egoX, altX, name="friend_w1",
                           interaction1 = "sex")              # homophily on sex
effects <- includeEffects(effects, name="behavior",
                           totSim)                            # social influence

# Estimate
algo   <- sienaAlgorithmCreate(projname = "siena_model", seed = 42)
result <- siena07(algo, data = data, effects = effects)
summary(result)
```

---

## Network Visualization

```python
import matplotlib.pyplot as plt
import networkx as nx

fig, ax = plt.subplots(figsize=(12, 10))

# Layout
pos = nx.spring_layout(G, seed=42, k=0.5)

# Color nodes by community
colors = [partition[node] for node in G.nodes()]

# Size nodes by degree
sizes = [G.degree(n) * 50 + 100 for n in G.nodes()]

nx.draw_networkx_nodes(G, pos, node_color=colors,
                        node_size=sizes, alpha=0.8,
                        cmap=plt.cm.tab20, ax=ax)
nx.draw_networkx_edges(G, pos, alpha=0.2,
                        arrows=True, arrowsize=10, ax=ax)
nx.draw_networkx_labels(G, pos, font_size=6, ax=ax)

ax.set_title("Network colored by community (Louvain)")
plt.axis("off")
plt.tight_layout()
plt.savefig("network_visualization.pdf", dpi=300, bbox_inches="tight")
```

---

## Network Analysis Reporting Standards

**Minimum descriptives to report**:
- N nodes, N edges, density
- Directed or undirected; weighted or binary
- Whether isolated nodes included or excluded
- Period / data source

**Table format for node-level analysis**:
| Node group | N | Mean degree | Mean betweenness | Mean clustering |
|-----------|---|------------|-----------------|----------------|

**For ERGM results**: Report log-odds with SE; note MCMC diagnostics (trace plots converged); GOF statistics

**Reporting template for network paper**:
> "We construct a directed social network where nodes represent [units] and edges represent [relationship type]. The network contains [N] nodes and [E] edges (density = [D]). [X]% of dyads show reciprocal ties. We identify [K] communities using the Leiden algorithm (modularity Q = [M]). To test our hypotheses, we estimate ERGMs with [list terms], using the `ergm` package in R (Hunter et al. 2008). MCMC chains converged based on visual inspection of trace plots; goodness-of-fit statistics indicate the model reproduces the observed degree distribution, triad census, and geodesic distances (Figure A[X])."

---

## Relational Event Analysis — Full Reference

### When to Use REMs vs. ERGMs vs. SAOMs

| Method | Data format | Time model | Key question |
|--------|-------------|------------|--------------|
| **ERGM** | Static network (one snapshot) | None | What predicts tie existence? |
| **SAOM / RSiena** | Panel network (2–4 waves) | Discrete waves | How do ties change between waves? |
| **REM** | Event sequence (time-stamped i→j events) | Continuous / ordinal time | What predicts the *rate* and *order* of interactions? |

Use REMs when: you have a time-stamped log of interactions (emails, messages, citations, conversation turns, social media replies) and want to model the sequence, rate, and direction of events as a function of network history and actor attributes.

### Key Endogenous Statistics

| Statistic | Definition | Interpretation |
|-----------|-----------|----------------|
| **Inertia** | i→j recently → i→j again | Repetition / persistence |
| **Reciprocity** | j→i recently → i→j | Reciprocal exchange |
| **Transitivity (OTP)** | i→k→j → i→j | Closure through intermediaries |
| **Popularity shift (in)** | j received many recent events → attract more | Matthew effect |
| **Activity shift (out)** | i sent many recent events → send more | Momentum |
| **Recency / time decay** | Events further in past matter less | Temporal decay |
| **Shared partners** | i and j have common alters | Structural balance |

### Option A — goldfish (Recommended for New Papers)

`goldfish` (Stadtfeld, Hollway & Block, 2017; ETH Zurich) is the modern, actively maintained REM implementation. It separates the *rate model* (when does anyone act?) from the *choice model* (given an event occurs, who sends to whom?).

```r
# install.packages("goldfish")
library(goldfish)

# ── 1. Define actors ─────────────────────────────────────────────────
# node_data: data.frame with columns: label (actor ID), + any attributes
actors <- defineActors(node_data)

# ── 2. Define initial network state ──────────────────────────────────
# Start with empty network (or observed baseline network)
init_net <- matrix(0, nrow=nrow(node_data), ncol=nrow(node_data))
network  <- defineNetwork(init_net, nodes=actors, directed=TRUE)

# ── 3. Register events that update the network ───────────────────────
# events_df: data.frame with columns: time (numeric), sender (label), receiver (label)
#            Optional: increment (default 1), replace (default FALSE)
events_df <- events_df[order(events_df$time), ]   # MUST be sorted by time
network   <- linkEvents(x=network, changeEvents=events_df, nodes=actors)

# ── 4. Define dependent event sequence ───────────────────────────────
dv <- defineDependentEvents(events=events_df, nodes=actors,
                             defaultNetwork=network)

# ── 5. Specify model effects ─────────────────────────────────────────
# Core endogenous effects:
#   inertia(network):  prior i→j events predict i→j
#   recip(network):    prior j→i events predict i→j
#   trans(network):    shared outgoing partners (i→k, k→j → i→j)
#   indeg(network):    j's current in-degree (popularity)
#   outdeg(network):   i's current out-degree (activity)

# Exogenous (node attribute) effects:
#   ego(actors$attribute):   sender attribute effect
#   alter(actors$attribute): receiver attribute effect
#   same(actors$group):      same-group homophily
#   diff(actors$attr):       absolute attribute difference

model_formula <- dv ~ inertia(network) + recip(network) +
                       trans(network)  + indeg(network) + outdeg(network) +
                       ego(actors$seniority) + alter(actors$seniority) +
                       same(actors$department)

# ── 6. Estimate (REM with Cox partial likelihood) ────────────────────
result <- estimate(model_formula, model="REM",
                   estimationInit=list(
                     engine="default",
                     startingParameters=NULL,
                     returnEventProbabilities=FALSE
                   ))
summary(result)
# Coefficients are log-rates; exp(coef) = rate ratio
# Positive inertia: dyads that recently interacted are more likely to interact again

# ── 7. Model comparison ──────────────────────────────────────────────
# Compare nested models via log-likelihood ratio test (LRT)
result_null <- estimate(dv ~ 1, model="REM")
lr_stat <- -2 * (logLik(result_null) - logLik(result))
p_val   <- pchisq(lr_stat, df=length(coef(result))-1, lower.tail=FALSE)
cat("LRT χ²=", round(lr_stat,2), " df=", length(coef(result))-1, " p=", round(p_val,4), "\n")

# ── 8. Export ─────────────────────────────────────────────────────────
saveRDS(result, "${OUTPUT_ROOT}/models/rem-goldfish.rds")

# Table via texreg
library(texreg)
screenreg(result)
texreg(result, file="${OUTPUT_ROOT}/tables/table-rem.tex",
       caption="Relational Event Model: Predictors of Interaction Rate")
```

### Option B — relevent (Butts 2008; Classic Implementation)

```r
# install.packages("relevent")
library(relevent)

# events_mat: N_events × 3 numeric matrix, columns = [time, sender, receiver]
# Actors indexed 1:N; time must be strictly increasing
events_mat <- as.matrix(events_df[order(events_df$time), c("time","sender","receiver")])

# Available effects (see ?rem.dyad for full list):
# "PSAB-BA" = inertia (i→j predicts i→j)
# "PSAB-AB" = reciprocity (j→i predicts i→j)
# "PSAB-AY" = popularity (j received many → j receives more)
# "PSAB-BY" = activity (i sent many → i sends more)
# "PSAB-XAB" = shared partners / transitivity
# "NTDSnd"   = recency decay for sender
# "NTDRec"   = recency decay for receiver

result_rem <- rem.dyad(
  edgelist = events_mat,
  n        = N_actors,
  effects  = c("PSAB-BA", "PSAB-AB", "PSAB-AY", "PSAB-BY", "NTDSnd", "NTDRec"),
  covar    = list(
    node = node_attr_matrix    # N_actors × K matrix of actor attributes
  ),
  acl    = NULL,   # optional: actor composition at each event (if actors enter/leave)
  timing = "interval"   # "ordinal" if only event order is known, not exact timestamps
)
summary(result_rem)

# Goodness of fit: compare predicted vs. observed event counts per dyad
# Use rem.dyad(... , predict=TRUE) to get predicted probabilities
```

### Visualization: Event Rate Over Time

```r
library(ggplot2)

# Plot cumulative event count by sender group
events_df |>
  mutate(cum_events = row_number()) |>
  ggplot(aes(x=time, y=cum_events, color=sender_group)) +
  geom_step() +
  scale_color_manual(values=c("#0072B2","#E69F00","#009E73")) +
  labs(x="Time", y="Cumulative Events", color="Group") +
  theme_Publication()
ggsave("${OUTPUT_ROOT}/figures/fig-rem-event-rate.pdf", device=cairo_pdf, width=6, height=4)

# Sender × receiver heat map of event frequency
event_mat <- table(events_df$sender, events_df$receiver)
library(ggcorrplot)
ggcorrplot(event_mat/max(event_mat), lab=FALSE, type="full") +
  labs(title="Dyadic Event Frequency", x="Receiver", y="Sender") +
  theme_Publication()
ggsave("${OUTPUT_ROOT}/figures/fig-rem-dyad-heatmap.pdf", device=cairo_pdf, width=7, height=6)
```

### Reporting Standards

**Minimum descriptives to report**:
- N events, N actors, time range, event rate per dyad
- Whether timing is continuous (timestamps) or ordinal (event order only)
- Definition of an "event" (what counts as an interaction)

**Required model information**:
- Software and version (`goldfish` version X or `relevent` version X)
- Effects included and justification for each
- Null model comparison (LRT χ², df, p)
- How ties with very high frequency are handled (weight cap?)

**Reporting template (goldfish):**
> "We model the sequence of [N] directed interaction events among [N_actors] actors using a Relational Event Model (REM; Butts 2008), estimated with the `goldfish` R package (Stadtfeld, Hollway & Block 2017). An event occurs when actor *i* directs a [message/citation/interaction] to actor *j*. The model specifies the instantaneous rate of a new i→j event as a function of: (1) inertia — whether i recently sent to j; (2) reciprocity — whether j recently sent to i; (3) transitivity — whether i and j share recent interaction partners; (4) indegree — j's recent receipt volume (popularity); and (5) actor-level covariates [list]. Table [X] reports log-rate coefficients with standard errors. A positive and significant inertia coefficient (b = [X], SE = [X]) indicates that dyads with recent prior interactions are [X] times more likely to interact again. The full model improves significantly over a null (intercept-only) model (LRT: χ² = [X], df = [X], p = [p])."

**Reporting template (relevent):**
> "We model the interaction sequence using `rem.dyad` from the `relevent` R package (Butts 2008). We include effects for inertia (PSAB-BA), reciprocity (PSAB-AB), popularity (PSAB-AY), activity (PSAB-BY), and temporal recency decay (NTDSnd, NTDRec), along with [actor-level covariates]. Coefficients are on the log-rate scale (Table [X])."
