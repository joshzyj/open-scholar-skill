## MODULE 3: Network Analysis

### Step 1 — Build Network

```python
import networkx as nx, pandas as pd

# From edge list
edges = pd.read_csv("edges.csv")   # source, target, [weight, time, type]
G = nx.from_pandas_edgelist(edges, "sender", "receiver",
                             edge_attr=["weight"],
                             create_using=nx.DiGraph())
# Attach node attributes
nodes = pd.read_csv("nodes.csv")   # id, [age, sex, education, ...]
nx.set_node_attributes(G, nodes.set_index("id").to_dict("index"))
print(f"N={G.number_of_nodes()}, E={G.number_of_edges()}, density={nx.density(G):.4f}")
```

```r
library(igraph)
g <- graph_from_data_frame(edges_df, directed=TRUE, vertices=nodes_df)
```

### Step 2 — Descriptive Network Measures

```python
def compute_centrality(G):
    G_u = G.to_undirected()
    return pd.DataFrame({
        "degree":      nx.degree_centrality(G),
        "indegree":    nx.in_degree_centrality(G),
        "outdegree":   nx.out_degree_centrality(G),
        "betweenness": nx.betweenness_centrality(G, normalized=True),
        "closeness":   nx.closeness_centrality(G),
        "pagerank":    nx.pagerank(G),
        "clustering":  nx.clustering(G_u),
    })

centrality_df = compute_centrality(G)
centrality_df.to_csv("${OUTPUT_ROOT}/tables/network-centrality.csv")
```

**Report**: N nodes, N edges, density, directed/undirected, weighted/binary, whether isolates included, data period.

### Step 2b — GNN / Node Embedding for Social Network Analysis

**When to use**: When you need low-dimensional node representations that capture structural position *and* node attributes for downstream tasks (link prediction, node classification, community detection). GNNs learn embeddings that outperform hand-crafted centrality measures when the network is large (N > 1,000 nodes), attributed, and the task is predictive rather than inferential.

| Goal | Recommended approach | Package |
|------|---------------------|---------|
| Unsupervised node embeddings (no labels) | **node2vec** | `node2vec`, `torch_geometric` |
| Node classification (labeled nodes) | **GraphSAGE** or **GCN** | `torch_geometric` (PyG) |
| Link prediction (predict missing/future ties) | **GCN + link decoder** | `torch_geometric` |
| Community detection via learned embeddings | node2vec + k-means / HDBSCAN | `node2vec`, `sklearn` |
| Heterogeneous graphs (multiple node/edge types) | **R-GCN** | `torch_geometric` |

**Installation:**

```bash
# PyTorch Geometric (PyG) — check https://pytorch-geometric.readthedocs.io for CUDA-specific install
pip install torch-geometric node2vec
# Alternative: DGL (Deep Graph Library)
# pip install dgl
```

**Option A — node2vec (unsupervised, scalable):**

```python
# pip install node2vec
import networkx as nx, numpy as np, pandas as pd
from node2vec import Node2Vec

# G: networkx graph (from Step 1)
node2vec = Node2Vec(
    G, dimensions=128, walk_length=30, num_walks=200,
    p=1.0,  # return parameter (1.0 = balanced BFS/DFS)
    q=1.0,  # in-out parameter (< 1 = BFS-like; > 1 = DFS-like)
    workers=4, seed=42
)
model_n2v = node2vec.fit(window=10, min_count=1, batch_words=4)

# Extract embeddings as DataFrame
embeddings = pd.DataFrame(
    [model_n2v.wv[str(n)] for n in G.nodes()],
    index=list(G.nodes())
)
embeddings.to_csv("${OUTPUT_ROOT}/models/node2vec-embeddings.csv")

# Downstream: cluster embeddings for community detection
from sklearn.cluster import KMeans
kmeans = KMeans(n_clusters=5, random_state=42)
communities = kmeans.fit_predict(embeddings.values)
```

**Option B — GCN for node classification (PyTorch Geometric):**

```python
import torch
import torch.nn.functional as F
from torch_geometric.nn import GCNConv
from torch_geometric.utils import from_networkx
from sklearn.model_selection import train_test_split

SEED = 42
torch.manual_seed(SEED)

# Convert networkx graph to PyG Data object
# Requires node features: set as node attributes in G before conversion
# Example: nx.set_node_attributes(G, features_dict)  where features_dict = {node: {"x": [f1, f2, ...]}}
data = from_networkx(G, group_node_attrs=["x"])   # "x" = feature attribute name
data.y = torch.tensor(labels, dtype=torch.long)   # node labels

# Train/val/test masks (60/20/20)
nodes = list(range(data.num_nodes))
train_idx, test_idx = train_test_split(nodes, test_size=0.4, random_state=SEED,
                                        stratify=labels)
val_idx, test_idx   = train_test_split(test_idx, test_size=0.5, random_state=SEED,
                                        stratify=[labels[i] for i in test_idx])
data.train_mask = torch.zeros(data.num_nodes, dtype=torch.bool)
data.val_mask   = torch.zeros(data.num_nodes, dtype=torch.bool)
data.test_mask  = torch.zeros(data.num_nodes, dtype=torch.bool)
data.train_mask[train_idx] = True
data.val_mask[val_idx]     = True
data.test_mask[test_idx]   = True

class GCN(torch.nn.Module):
    def __init__(self, in_channels, hidden_channels, out_channels, dropout=0.5):
        super().__init__()
        self.conv1   = GCNConv(in_channels, hidden_channels)
        self.conv2   = GCNConv(hidden_channels, out_channels)
        self.dropout = dropout

    def forward(self, x, edge_index):
        x = self.conv1(x, edge_index)
        x = F.relu(x)
        x = F.dropout(x, p=self.dropout, training=self.training)
        x = self.conv2(x, edge_index)
        return x

device = "cuda" if torch.cuda.is_available() else "cpu"
model  = GCN(data.num_node_features, 64, len(torch.unique(data.y))).to(device)
data   = data.to(device)
optimizer = torch.optim.Adam(model.parameters(), lr=0.01, weight_decay=5e-4)

# Training loop
model.train()
for epoch in range(200):
    optimizer.zero_grad()
    out  = model(data.x, data.edge_index)
    loss = F.cross_entropy(out[data.train_mask], data.y[data.train_mask])
    loss.backward()
    optimizer.step()

# Evaluation
model.eval()
with torch.no_grad():
    pred = model(data.x, data.edge_index).argmax(dim=1)
    test_acc = (pred[data.test_mask] == data.y[data.test_mask]).float().mean().item()
    print(f"Test accuracy: {test_acc:.3f}")

# Save embeddings (penultimate layer)
model.eval()
with torch.no_grad():
    x = model.conv1(data.x, data.edge_index)
    x = F.relu(x)
    node_embeddings = x.cpu().numpy()
np.save("${OUTPUT_ROOT}/models/gcn-node-embeddings.npy", node_embeddings)

torch.save(model.state_dict(), "${OUTPUT_ROOT}/models/gcn-model.pt")
```

**Option C — GraphSAGE for inductive node classification** (generalizes to unseen nodes):

```python
from torch_geometric.nn import SAGEConv

class GraphSAGE(torch.nn.Module):
    def __init__(self, in_channels, hidden_channels, out_channels, dropout=0.5):
        super().__init__()
        self.conv1   = SAGEConv(in_channels, hidden_channels)
        self.conv2   = SAGEConv(hidden_channels, out_channels)
        self.dropout = dropout

    def forward(self, x, edge_index):
        x = self.conv1(x, edge_index)
        x = F.relu(x)
        x = F.dropout(x, p=self.dropout, training=self.training)
        x = self.conv2(x, edge_index)
        return x

# Training follows the same pattern as GCN above
# GraphSAGE is preferred for large graphs (>50K nodes) with mini-batch training:
from torch_geometric.loader import NeighborLoader
train_loader = NeighborLoader(
    data, num_neighbors=[10, 10], batch_size=256,
    input_nodes=data.train_mask, shuffle=True
)
```

**Option D — Link prediction** (predict missing/future ties):

```python
from torch_geometric.nn import GCNConv
from torch_geometric.utils import negative_sampling
from sklearn.metrics import roc_auc_score

class LinkPredictor(torch.nn.Module):
    def __init__(self, in_channels, hidden_channels):
        super().__init__()
        self.conv1 = GCNConv(in_channels, hidden_channels)
        self.conv2 = GCNConv(hidden_channels, hidden_channels)

    def encode(self, x, edge_index):
        x = F.relu(self.conv1(x, edge_index))
        return self.conv2(x, edge_index)

    def decode(self, z, edge_label_index):
        return (z[edge_label_index[0]] * z[edge_label_index[1]]).sum(dim=-1)

# Split edges into train/val/test using RandomLinkSplit
from torch_geometric.transforms import RandomLinkSplit
transform = RandomLinkSplit(num_val=0.1, num_test=0.1, is_undirected=True,
                             add_negative_train_samples=True, neg_sampling_ratio=1.0)
train_data, val_data, test_data = transform(data)

# Training: BCE loss on positive + negative edges
# Evaluation: AUC-ROC on held-out test edges
```

**Validation approach:**
- Node classification: F1 (macro) and accuracy on held-out test nodes (60/20/20 split)
- Link prediction: AUC-ROC on held-out test edges; compare vs. common-neighbors / Adamic-Adar baselines
- Community detection: compare GNN-derived communities vs. Leiden; report NMI and modularity
- Embedding quality: visualize with UMAP; check that known groups cluster

**Reporting template:**
> "We learn 128-dimensional node embeddings using [node2vec (Grover & Leskovec 2016) / a two-layer GCN (Kipf & Welling 2017) / GraphSAGE (Hamilton et al. 2017)] implemented in PyTorch Geometric (Fey & Lenssen 2019). The model takes as input the adjacency structure and [X] node-level features [list features]. For [node classification], we train on 60% of labeled nodes, validate on 20%, and evaluate on the held-out 20%, achieving test F1 (macro) = [X] and accuracy = [X]. [For link prediction], we hold out 10% of edges for testing and achieve AUC-ROC = [X], compared to [X] for a common-neighbors baseline. [For community detection], we cluster the learned embeddings via k-means (K = [X]), obtaining modularity Q = [X], compared to Q = [X] from Leiden on the raw adjacency. All models use seed = 42."

---

### Step 3 — Community Detection

```python
import leidenalg as la, igraph as ig   # Leiden preferred for research

G_u    = G.to_undirected()
ig_g   = ig.Graph.from_networkx(G_u)
leiden = la.find_partition(ig_g, la.ModularityVertexPartition, seed=42)
print(f"Leiden: {len(leiden)} communities, Q={leiden.modularity:.3f}")
```

```r
library(igraph)
cl_leiden  <- cluster_leiden(g, objective_function="modularity", resolution=1.0)
modularity(g, cl_leiden)
```

### Step 4 — ERGMs

```r
library(ergm); library(network)

net <- asNetwork(g)    # convert igraph to network

# Progressive model ladder
m0 <- ergm(net ~ edges)
m1 <- ergm(net ~ edges + nodematch("race"))
m2 <- ergm(net ~ edges
               + nodematch("race")
               + nodematch("education")
               + mutual
               + gwesp(0.5, fixed=TRUE),
           control=control.ergm(MCMC.samplesize=2000, seed=42))
summary(m2)

# Goodness-of-fit (REQUIRED — must match degree dist., triad census, geodesics)
gof_m2 <- gof(m2); plot(gof_m2)

# Export table
texreg::texreg(list(m0,m1,m2),
               file="${OUTPUT_ROOT}/tables/table-ergm.tex",
               caption="ERGM Results")
```

**Reporting template:**
> "We estimate ERGMs (Robins et al. 2007) to test whether tie formation is conditioned on node attributes and endogenous network structure. We include terms for density (edges), racial homophily (nodematch), reciprocity (mutual), and transitivity (GWESP). MCMC chains converged based on visual inspection of trace plots. GOF statistics indicate the model reproduces the observed degree distribution, triad census, and geodesic distances (Figure A[X])."

### Step 4b — Temporal ERGMs (tERGMs)

```r
library(btergm)
# Fit TERGM to panel of networks
tergm_mod <- btergm(networks ~ edges + mutual + gwesp(0.5, fixed = TRUE)
                    + nodematch("gender") + memory(type = "stability"),
                    R = 100, verbose = TRUE)
summary(tergm_mod)
# Interpretation: coefficients represent tendency controlling for prior network state
```

### Step 4c — Stochastic Block Models (SBM)

```python
import graph_tool.all as gt
# Fit SBM to detect latent community structure (allows overlapping membership)
g = gt.Graph(directed=False)
# ... add edges ...
state = gt.minimize_blockmodel_dl(g)
state.draw(output="sbm_communities.pdf")
b = state.get_blocks()  # Block assignments
```

### Step 4d — Ego-Network Analysis

```r
library(egor)
# Load ego-network data (alter attributes + ties between alters)
ego_data <- read_egor(egos = ego_df, alters = alter_df, aaties = tie_df)
# Constraint (Burt 1992)
ego_data <- ego_constraint(ego_data)
# Effective size
ego_data <- ego_effsize(ego_data)
summary(ego_data$ego$constraint)
```

### Step 5 — SAOMs / RSiena (Longitudinal Network Dynamics)

```r
library(RSiena)

friend_net <- sienaDependent(array(c(net_w1, net_w2), dim=c(N,N,2)))
behavior   <- sienaDependent(cbind(beh_w1, beh_w2), type="behavior")
sex        <- coCovar(sex_vec)

data    <- sienaDataCreate(friend_net, behavior, sex)
effects <- getEffects(data) |>
           includeEffects(transTrip, recip) |>
           includeEffects(egoX, altX, name="friend_net", interaction1="sex") |>
           includeEffects(name="behavior", totSim)

algo   <- sienaAlgorithmCreate(projname="siena_run", seed=42)
result <- siena07(algo, data=data, effects=effects)
summary(result)
```

### Step 6 — Relational Event Analysis

**When to use**: Your data is a *time-ordered sequence of dyadic interactions* (e.g., emails, messages, citations, observed conversations) rather than a static or panel network snapshot. Relational Event Models (Butts 2008) model the *rate* at which each sender-receiver pair interacts as a function of endogenous history statistics and exogenous covariates.

**Key endogenous statistics:**

| Statistic | Meaning |
|-----------|---------|
| Inertia | i→j recently sent to j; predicts repetition |
| Reciprocity | j recently sent to i; predicts reciprocation |
| Transitivity | shared partners predict new ties |
| Popularity shift | nodes receiving many recent events attract more |
| Activity shift | nodes sending many events continue sending |
| Recency | decay function — recent events matter more |

**Option A — `goldfish` (ETH Zurich; recommended for new papers):**

```r
# install.packages("goldfish")
library(goldfish)

# Define actors and network
actors  <- defineActors(node_data)                       # node_data: data.frame with id col
network <- defineNetwork(matrix(0, nrow=N, ncol=N),      # initial empty network
                         nodes=actors, directed=TRUE)

# Register dynamic updates: each event updates the network state
network <- linkEvents(x=network, changeEvents=events_df, nodes=actors)
# events_df must have columns: time, sender, receiver (and optionally weight, replace)

# Define dependent event sequence
dv <- defineDependentEvents(events=events_df, nodes=actors,
                             defaultNetwork=network)

# Specify model effects
# inertia: repetition of i→j
# recip:   reciprocity j→i predicts i→j
# trans:   transitivity via shared partners
# ego.attribute / alter.attribute: node-level covariates
model_formula <- dv ~ inertia(network) + recip(network) +
                       trans(network)  +
                       ego(actors$attribute) +
                       alter(actors$attribute) +
                       same(actors$group)

# Estimate (REM with Cox partial likelihood)
result <- estimate(model_formula, model="REM",
                   estimationInit=list(engine="default",
                                       startingParameters=NULL,
                                       returnEventProbabilities=FALSE))
summary(result)

# Model fit: compare log-likelihood across nested models
# Export
saveRDS(result, "${OUTPUT_ROOT}/models/rem-goldfish.rds")
```

**Option B — `relevent` (Butts 2008; classic implementation):**

```r
# install.packages("relevent")
library(relevent)

# events_mat: N_events × 3 matrix with columns [time, sender, receiver]
# n: number of actors
result_rem <- rem.dyad(
  edgelist = events_mat,
  n        = N_actors,
  effects  = c("PSAB-BA",   # inertia: prior i→j predicts i→j
               "PSAB-BY",   # activity: i sent to anyone recently
               "PSAB-AY",   # popularity: j received from anyone recently
               "PSAB-AB",   # reciprocity: j→i predicts i→j
               "NTDSnd",    # recency decay (sender)
               "NTDRec"),   # recency decay (receiver)
  covar    = list(node=node_attr_matrix),  # exogenous node attributes
  timing   = "interval"   # or "ordinal" if only order of events is known
)
summary(result_rem)

# Goodness of fit
# Compare predicted vs. observed event rates per dyad
```

**Reporting template:**
> "We model the sequence of [N] interaction events among [N_actors] actors using a Relational Event Model (REM; Butts 2008), estimated via the `goldfish` package (Stadtfeld et al. 2017). The model captures how the rate of a directed event from actor *i* to actor *j* depends on endogenous network history — including inertia (prior i→j interactions), reciprocity (prior j→i interactions), and transitivity (shared partners) — as well as actor-level covariates [list]. Table [X] reports log-likelihood coefficients. A positive coefficient on inertia indicates that dyads with recent prior interactions are more likely to interact again, consistent with H[X]."

**Required diagnostics:**
- Compare null model (intercept only) vs. full model via log-likelihood ratio test
- Plot predicted vs. observed event rate per sender/receiver
- Check temporal stability: does the model hold across sub-periods?

### Step 7 — Network Visualization

```python
import matplotlib.pyplot as plt, networkx as nx

fig, ax = plt.subplots(figsize=(12,10))
pos     = nx.spring_layout(G, seed=42, k=0.5)
colors  = [leiden.membership[list(G.nodes()).index(n)] for n in G.nodes()]
sizes   = [G.degree(n)*50+100 for n in G.nodes()]

nx.draw_networkx_nodes(G, pos, node_color=colors, node_size=sizes,
                       alpha=0.8, cmap=plt.cm.tab20, ax=ax)
nx.draw_networkx_edges(G, pos, alpha=0.15, arrows=True, arrowsize=10, ax=ax)
ax.set_title("Network colored by community (Leiden)")
plt.axis("off"); plt.tight_layout()
plt.savefig("${OUTPUT_ROOT}/figures/fig-network.pdf", dpi=300, bbox_inches="tight")
plt.savefig("${OUTPUT_ROOT}/figures/fig-network.png", dpi=300, bbox_inches="tight")
```

For interactive network figures, see `viz-standards.md` T17 (visNetwork + networkD3).

### Step 8 — Network Verification (Subagent)

```
NETWORK VERIFICATION REPORT
=============================

DESCRIPTIVES
[ ] N nodes, N edges, density reported
[ ] Directed/undirected and weighted/binary specified
[ ] Isolates inclusion/exclusion documented

COMMUNITY DETECTION
[ ] Leiden or Louvain used (not Girvan-Newman for large graphs)
[ ] random_state / seed=42 set
[ ] Modularity Q reported

ERGM (if used)
[ ] Progressive model ladder (m0 → m1 → m2)
[ ] MCMC trace plots inspected for convergence
[ ] GOF run and plot saved (degree dist., triad census, geodesics)
[ ] Coefficients are log-odds (NOT exp(β) unless reported as odds ratios)
[ ] Table exported to output/[slug]/tables/

SAOM (if used)
[ ] seed=42 in sienaAlgorithmCreate
[ ] Convergence ratio < 0.25 for all parameters
[ ] GOF run

RELATIONAL EVENT MODEL (if used)
[ ] Event sequence sorted by time
[ ] N events, N actors, time range reported
[ ] Model includes at minimum inertia + reciprocity terms
[ ] Null model comparison (log-likelihood ratio test)
[ ] goldfish or relevent used (not manual)

GNN / NODE EMBEDDING (if used)
[ ] Method specified (node2vec / GCN / GraphSAGE)
[ ] Node features documented (what attributes used as input)
[ ] Train/val/test split documented (60/20/20 for node classification)
[ ] Test F1 (macro) and accuracy reported (not train-set metrics)
[ ] Link prediction: AUC-ROC on held-out test edges reported
[ ] Baseline comparison (common neighbors / Adamic-Adar / Leiden) included
[ ] Embedding dimensionality documented
[ ] Embeddings saved to output/[slug]/models/
[ ] UMAP visualization of embeddings saved
[ ] torch.manual_seed(42) set

VISUALIZATION
[ ] Network figure saved as .pdf + .png
[ ] Colorblind-safe palette used (not default matplotlib tab10 if >8 communities)

RESULT: [PASS / NEEDS REVISION]
Issues: [list]
```

---

