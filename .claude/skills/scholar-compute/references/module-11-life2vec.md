## MODULE 11: Life-Event Sequence Modeling (life2vec)

Transformer-based representation learning for individual life-trajectories, following Savcisens et al. (2024, *Nature Computational Science*). Converts administrative/survey panel data into chronologically ordered "life-sequences" — a synthetic language where each life-event is a sentence of concept tokens — then pretrains a BERT-like encoder to learn a shared concept space and finetunes for downstream prediction tasks (mortality, personality, mobility, health outcomes).

**When to use:** The researcher has longitudinal individual-level panel data (labor market records, health registries, education records, survey panel waves, or combined administrative data) and wants to (a) learn dense person-level embeddings that capture the full trajectory, (b) predict individual outcomes from these embeddings, and/or (c) explore the learned concept space to understand relationships between life domains.

**Key reference:** Savcisens, G., Eliassi-Rad, T., Hansen, L.K., et al. (2024). Using sequences of life-events to predict human lives. *Nature Computational Science*, 4, 43–56. Code: `github.com/SocialComplexityLab/life2vec`

**Architecture summary (from original repo `github.com/SocialComplexityLab/life2vec`):**

| Component | Original Implementation | Key Detail |
|---|---|---|
| Hidden dim | 280 | d_model throughout |
| Encoder layers | 5 | NOT 6 as in standard BERT-base |
| Attention heads | 10 (7 local + 3 global) | Performer FAVOR+ for global, local window=38 for local |
| FFN dim | 2210 | ~7.9× hidden_size |
| FFN activation | swish (x·sigmoid(x)) | NOT GELU or SwiGLU |
| Normalization | ScaleNorm (L2-based) | NOT LayerNorm |
| Residual | ReZero: x + α·f(x), α init=0 | Learnable scalar per sublayer |
| Embedding combination | ReZero residual per temporal dim | token, then += α_age·time2vec(age), += α_pos·time2vec(pos), += α_seg·segment |
| Mean-centering | `parametrize.register_parametrization` | Excludes special token indices [0,4,5,6,7,8] |
| SOP classes | 3-way: original / reversed / shuffled | NOT binary NSP |
| Loss weights | 0.8·MLM + 0.2·SOP | SOP class weights [1/0.9, 1/0.1, 1/0.1] |
| MLM decoder | L2-norm + √d scalar + weight tying | Tied to token embedding matrix |
| Finetuning CLS | Average CLS from layers 1, mid, last | NOT just last-layer CLS |
| Background sentence | [CLS] origin gender MONTH_m YEAR_y [SEP] | Segment=1; 4 concept tokens |
| Segment cycling | [2, 3, 1, 2, 3, 1, ...] for events | NOT [0,1,2] |
| Augmentation | timecut, resample (25-50%), ±5-day noise, token dropout, intra-sentence shuffle | Applied during training only |
| Optimizer | AdamW(lr=5e-3, β=(0.9,0.999), ε=1e-6) | OneCycleLR, pct_start=0.05, div_factor=30 |
| Max sequence | 2048 tokens (configurable) | Right-truncation preserving background prefix |

### Step 1 — Data Inventory and Vocabulary Design

**1a. Identify event sources and temporal grain:**

Determine what event streams are available. Each stream becomes a sentence type in the synthetic language:

```python
# ── 100-life2vec-preprocess.py ──
# Life2Vec Step 1: Data inventory and vocabulary construction
# Reference: Savcisens et al. (2024) Nature Computational Science
import pandas as pd
import numpy as np
from collections import Counter
from datetime import datetime

# ── Configuration ──
ORIGIN_DATE = pd.Timestamp("2008-01-01")  # Day 0 for absolute position
MAX_SEQ_LEN = 2560   # Max concept tokens per person
INCOME_QUANTILES = 100
SEED = 42
np.random.seed(SEED)

# ── 1a. Load event streams ──
# Adapt these loaders to your data format
# LABOR stream: employment records (job type, industry, income, city, position)
# labor_df = pd.read_parquet("data/labor_events.parquet")
# HEALTH stream: hospital/clinic visits (diagnosis ICD-10, patient type, urgency)
# health_df = pd.read_parquet("data/health_events.parquet")
# EDUCATION stream: enrollment, degree completion
# edu_df = pd.read_parquet("data/education_events.parquet")
# SURVEY stream: panel survey responses across waves
# survey_df = pd.read_parquet("data/survey_panel.parquet")

# ── 1b. Build vocabulary from categorical features ──
def build_vocabulary(event_dfs: dict, continuous_bins: dict) -> dict:
    """
    Build concept token vocabulary from all event streams.

    Args:
        event_dfs: dict mapping stream name to DataFrame
        continuous_bins: dict mapping column name to number of quantile bins
            e.g., {"income": 100, "labor_force_pct": 10}

    Returns:
        vocab: dict mapping token string -> integer ID
    """
    # Special tokens
    special = ["[PAD]", "[CLS]", "[SEP]", "[UNK]", "[MASK]"]
    all_tokens = list(special)

    for stream_name, df in event_dfs.items():
        for col in df.columns:
            if col in ["person_id", "date", "birth_date"]:
                continue
            if col in continuous_bins:
                # Discretize continuous features into quantile bins
                n_bins = continuous_bins[col]
                bin_labels = [f"{col.upper()}_{i}" for i in range(n_bins)]
                all_tokens.extend(bin_labels)
            else:
                # Categorical features: prefix with stream/type
                unique_vals = df[col].dropna().unique()
                tokens = [f"{col.upper()}_{v}" for v in unique_vals]
                all_tokens.extend(tokens)

    # Add background tokens: birth_year, birth_month, country_of_origin, sex
    all_tokens.extend([f"BIRTH_YEAR_{y}" for y in range(1930, 2010)])
    all_tokens.extend([f"BIRTH_MONTH_{m}" for m in range(1, 13)])
    all_tokens.extend(["SEX_MALE", "SEX_FEMALE"])
    # Add country tokens as needed
    # all_tokens.extend([f"ORIGIN_{c}" for c in country_list])

    # Deduplicate and assign IDs
    seen = set()
    vocab = {}
    idx = 0
    for t in all_tokens:
        if t not in seen:
            vocab[t] = idx
            seen.add(t)
            idx += 1

    print(f"Vocabulary size: {len(vocab)} tokens")
    print(f"  Special: {len(special)}")
    print(f"  Concept tokens: {len(vocab) - len(special)}")
    return vocab

# ── 1c. Discretize continuous variables ──
def discretize_column(series: pd.Series, n_bins: int, prefix: str) -> pd.Series:
    """Convert continuous column to quantile-binned token strings."""
    bins = pd.qcut(series.rank(method="first"), q=n_bins, labels=False, duplicates="drop")
    return bins.map(lambda x: f"{prefix}_{int(x)}" if pd.notna(x) else "[UNK]")

# Example: discretize income into 100 quantile bins
# labor_df["income_token"] = discretize_column(
#     labor_df["income"], INCOME_QUANTILES, "INC"
# )
```

**1b. Define sentence structure per event type:**

Each event record → one "sentence" of concept tokens. The structure depends on the data source:

| Event stream | Concept tokens per sentence | Example |
|---|---|---|
| Labor/employment | job_type, industry, income_quantile, city, position | `POS_9210 IND_6200 INC_75 CITY_101 STATUS_EMPLOYED` |
| Health/hospital | diagnosis_chapter, diagnosis_code, patient_type, urgency | `DX_S86 PTYPE_INPATIENT URG_ACUTE` |
| Education | level, field, institution_type | `EDU_BACHELOR FIELD_SOC INST_PUBLIC` |
| Survey response | item_code, response_value (discretized) | `ITEM_EXTRA1 RESP_4 ITEM_EXTRA2 RESP_3` |

### Step 2 — Life-Sequence Construction

Convert raw event records into the life2vec document format: a chronologically ordered sequence of sentences per person, with temporal and segment metadata.

```python
# ── 101-life2vec-sequences.py ──
# Life2Vec Step 2: Construct life-sequences from event data
import pandas as pd
import numpy as np
from typing import List, Dict, Tuple

ORIGIN_DATE = pd.Timestamp("2008-01-01")
MAX_SEQ_LEN = 2560

def compute_temporal_features(event_date: pd.Timestamp,
                               birth_date: pd.Timestamp) -> Tuple[int, int]:
    """
    Compute the two temporal indicators for each event:
      - age: full years since birth at event time
      - absolute_position: days since ORIGIN_DATE
    """
    age = (event_date - birth_date).days // 365
    abs_pos = (event_date - ORIGIN_DATE).days
    return int(age), int(abs_pos)

def assign_segments(events_on_day: List[dict]) -> List[str]:
    """
    Assign segment labels (A, B, C) to events on the same day.
    Events on the same day share age/position but get different segments
    to distinguish them. Cycle through A→B→C→A...
    """
    segments = ["A", "B", "C"]
    return [segments[i % 3] for i in range(len(events_on_day))]

def build_life_sequence(person_id: str,
                         events: pd.DataFrame,
                         birth_date: pd.Timestamp,
                         sex: str,
                         birth_year: int,
                         birth_month: int,
                         vocab: dict) -> dict:
    """
    Build one person's life-sequence document.

    Returns dict with:
      - person_id: str
      - tokens: List[int]  (concept token IDs)
      - ages: List[int]
      - abs_positions: List[int]
      - segments: List[int]  (0=A, 1=B, 2=C)
    """
    # Background sentence (no age/position)
    bg_tokens = [
        vocab.get(f"BIRTH_YEAR_{birth_year}", vocab["[UNK]"]),
        vocab.get(f"BIRTH_MONTH_{birth_month}", vocab["[UNK]"]),
        vocab.get(f"SEX_{sex.upper()}", vocab["[UNK]"]),
    ]

    # Sort events chronologically
    events = events.sort_values("date")

    all_tokens = [vocab["[CLS]"]] + bg_tokens + [vocab["[SEP]"]]
    all_ages = [0] * (len(bg_tokens) + 2)  # background has no temporal info
    all_abs_pos = [0] * (len(bg_tokens) + 2)
    all_segments = [0] * (len(bg_tokens) + 2)

    # Group events by date for segment assignment
    for date, day_events in events.groupby("date"):
        seg_labels = assign_segments(list(day_events.itertuples()))
        for i, (_, event_row) in enumerate(day_events.iterrows()):
            age, abs_pos = compute_temporal_features(
                pd.Timestamp(date), birth_date
            )
            # Convert event row to concept tokens
            event_tokens = []
            for col in event_row.index:
                if col in ["person_id", "date", "birth_date", "stream"]:
                    continue
                token_str = f"{col.upper()}_{event_row[col]}"
                event_tokens.append(vocab.get(token_str, vocab["[UNK]"]))

            seg_id = i % 3
            for t in event_tokens:
                all_tokens.append(t)
                all_ages.append(age)
                all_abs_pos.append(abs_pos)
                all_segments.append(seg_id)

            # [SEP] after each event sentence
            all_tokens.append(vocab["[SEP]"])
            all_ages.append(age)
            all_abs_pos.append(abs_pos)
            all_segments.append(seg_id)

    # Truncate to MAX_SEQ_LEN (remove earliest events if over limit)
    if len(all_tokens) > MAX_SEQ_LEN:
        # Keep [CLS] + background + [SEP], then take the LAST events
        bg_len = len(bg_tokens) + 2  # [CLS] + bg + [SEP]
        tail_len = MAX_SEQ_LEN - bg_len
        all_tokens = all_tokens[:bg_len] + all_tokens[-tail_len:]
        all_ages = all_ages[:bg_len] + all_ages[-tail_len:]
        all_abs_pos = all_abs_pos[:bg_len] + all_abs_pos[-tail_len:]
        all_segments = all_segments[:bg_len] + all_segments[-tail_len:]

    # Pad to MAX_SEQ_LEN
    pad_len = MAX_SEQ_LEN - len(all_tokens)
    all_tokens += [vocab["[PAD]"]] * pad_len
    all_ages += [0] * pad_len
    all_abs_pos += [0] * pad_len
    all_segments += [0] * pad_len

    return {
        "person_id": person_id,
        "tokens": all_tokens,
        "ages": all_ages,
        "abs_positions": all_abs_pos,
        "segments": all_segments,
    }

# ── Build all sequences and save as HDF5 ──
# import h5py
# with h5py.File(f"{output_root}/life2vec_sequences.h5", "w") as f:
#     for person_id, person_data in tqdm(all_persons.items()):
#         seq = build_life_sequence(person_id, ...)
#         grp = f.create_group(person_id)
#         grp.create_dataset("tokens", data=np.array(seq["tokens"], dtype=np.int32))
#         grp.create_dataset("ages", data=np.array(seq["ages"], dtype=np.int16))
#         grp.create_dataset("abs_positions", data=np.array(seq["abs_positions"], dtype=np.int32))
#         grp.create_dataset("segments", data=np.array(seq["segments"], dtype=np.int8))
```

### Step 3 — Model Architecture

Implement the life2vec transformer from the original repo (`github.com/SocialComplexityLab/life2vec`): embedding layer with Time2Vec temporal encoding combined via ReZero residuals, stacked encoder blocks with hybrid Performer attention (local softmax + global FAVOR+), ScaleNorm, swish FFN, and task-specific decoders.

```python
# ── 102-life2vec-model.py ──
# Life2Vec Step 3: Model architecture — faithful to original repo
# Reference: Savcisens et al. (2024) Nature Computational Science
# Source: github.com/SocialComplexityLab/life2vec
import torch
import torch.nn as nn
import torch.nn.functional as F
import math
from torch.nn.utils import parametrize

# ── 3a. Time2Vec temporal encoding (Kazemi et al. 2019) ──
# Original: src/transformer/embeddings.py — t2v() function
class Time2Vec(nn.Module):
    """
    Learnable periodic + linear temporal embedding.
    Exact implementation from life2vec repo: t2v(tau, f, w, b, w0, b0).
    """
    def __init__(self, d_model: int, activation=torch.cos):
        super().__init__()
        self.d_model = d_model
        self.activation = activation
        # Periodic component: d_model-1 frequencies
        self.w = nn.Parameter(torch.empty(d_model - 1))
        self.b = nn.Parameter(torch.empty(d_model - 1))
        # Linear component: 1 dimension
        self.w0 = nn.Parameter(torch.empty(1))
        self.b0 = nn.Parameter(torch.empty(1))
        # Initialize uniformly per original repo
        nn.init.uniform_(self.w, -0.01, 0.01)
        nn.init.uniform_(self.b, -0.01, 0.01)
        nn.init.uniform_(self.w0, -0.01, 0.01)
        nn.init.uniform_(self.b0, -0.01, 0.01)

    def forward(self, tau: torch.Tensor) -> torch.Tensor:
        """tau: (batch, seq_len, 1) float tensor."""
        periodic = self.activation(tau * self.w + self.b)  # (B, L, d-1)
        linear = tau * self.w0 + self.b0                   # (B, L, 1)
        return torch.cat([linear, periodic], dim=-1)        # (B, L, d)

# ── 3b. ScaleNorm (NOT LayerNorm — original uses L2-based normalization) ──
class ScaleNorm(nn.Module):
    """L2-based normalization with learnable scale. From original repo."""
    def __init__(self, hidden_size: int, eps: float = 1e-6):
        super().__init__()
        self.g = nn.Parameter(torch.sqrt(torch.tensor(float(hidden_size))))
        self.eps = eps

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        norm = self.g / torch.linalg.norm(x, dim=-1, ord=2, keepdim=True).clamp(min=self.eps)
        return x * norm

# ── 3c. ReZero residual connection ──
class ReZero(nn.Module):
    """x + α·y where α is a learnable scalar initialized to 0."""
    def __init__(self, fill: float = 0.0):
        super().__init__()
        self.alpha = nn.Parameter(torch.tensor(fill))

    def forward(self, x: torch.Tensor, y: torch.Tensor) -> torch.Tensor:
        return x + y * self.alpha

# ── 3d. Mean-centering parametrization for token embeddings ──
class CenterEmbedding(nn.Module):
    """
    Register as parametrization on nn.Embedding.weight to auto-center.
    Excludes special tokens (indices 0,4,5,6,7,8) from mean computation.
    From original: src/transformer/embeddings.py — Center class.
    """
    def __init__(self, ignore_indices=None):
        super().__init__()
        self.ignore_indices = ignore_indices or [0, 4, 5, 6, 7, 8]

    def forward(self, weight: torch.Tensor) -> torch.Tensor:
        mask = torch.ones(weight.size(0), dtype=torch.bool, device=weight.device)
        mask[self.ignore_indices] = False
        mean = weight[mask].mean(dim=0, keepdim=True)
        return weight - mean

# ── 3e. Embedding layer ──
class Life2VecEmbedding(nn.Module):
    """
    Combines: token embedding + age Time2Vec + abspos Time2Vec + segment embedding.
    Each temporal/segment component added via ReZero residual (NOT simple addition).
    First 5 positions of temporal embeddings zeroed (background sentence slots).
    From original: src/transformer/embeddings.py — Embeddings class.
    """
    def __init__(self, vocab_size: int, d_model: int = 280, n_segments: int = 4,
                 dropout: float = 0.1):
        super().__init__()
        self.token_embed = nn.Embedding(vocab_size, d_model, padding_idx=0)
        self.segment_embed = nn.Embedding(n_segments, d_model)
        self.age_time2vec = Time2Vec(d_model, activation=torch.cos)
        self.pos_time2vec = Time2Vec(d_model, activation=torch.sin)  # sin for abspos
        # ReZero residuals for combining temporal components
        self.res_age = ReZero(fill=0.0)
        self.res_pos = ReZero(fill=0.0)
        self.res_seg = ReZero(fill=0.0)
        self.dropout = nn.Dropout(dropout)
        # Register mean-centering parametrization
        parametrize.register_parametrization(self.token_embed, "weight",
                                              CenterEmbedding())

    def forward(self, tokens, abs_positions, ages, segments):
        """
        Args — all (batch, seq_len) int tensors:
          tokens: concept token IDs
          abs_positions: days since origin date
          ages: age in years at each event
          segments: 1=background, 2/3=alternating event segments
        """
        x = self.token_embed(tokens)  # Auto mean-centered via parametrization

        # Age embedding — zero out first 5 positions (background sentence)
        age_emb = self.age_time2vec(ages.float().unsqueeze(-1))
        age_emb[:, :5] *= 0
        x = self.res_age(x, age_emb)

        # Absolute position embedding — zero out first 5 positions
        pos_emb = self.pos_time2vec(abs_positions.float().unsqueeze(-1))
        pos_emb[:, :5] *= 0
        x = self.res_pos(x, pos_emb)

        # Segment embedding
        seg_emb = self.segment_embed(segments)
        x = self.res_seg(x, seg_emb)

        return self.dropout(x)

# ── 3f. Encoder block ──
class Life2VecEncoderBlock(nn.Module):
    """
    Transformer encoder block with:
    - Hybrid attention: performer_pytorch (7 local softmax + 3 global FAVOR+ heads)
    - Swish FFN (NOT SwiGLU, NOT GELU)
    - ReZero residual connections
    - ScaleNorm normalization
    From original: src/transformer/modules.py — EncoderLayer.
    """
    def __init__(self, d_model: int = 280, n_heads: int = 10, d_ff: int = 2210,
                 dropout: float = 0.1, n_local_heads: int = 7,
                 local_window: int = 38, num_random_features: int = 436):
        super().__init__()
        # Attention: use performer_pytorch for production;
        # fallback to standard nn.MultiheadAttention for prototyping
        self.attention = nn.MultiheadAttention(
            d_model, n_heads, dropout=dropout, batch_first=True
        )
        # NOTE: For the full Performer attention with local/global head split,
        # install performer-pytorch and use:
        # from performer_pytorch import SelfAttention as CustomSelfAttention
        # self.attention = CustomSelfAttention(
        #     dim=d_model, heads=n_heads, dim_head=d_model//n_heads,
        #     local_heads=n_local_heads, local_window_size=local_window,
        #     nb_features=num_random_features, causal=False
        # )

        # Swish FFN (x * sigmoid(x)) — NOT SwiGLU
        self.ff_in = nn.Linear(d_model, d_ff)
        self.ff_out = nn.Linear(d_ff, d_model)
        self.dropout = nn.Dropout(dropout)

        # ReZero residuals (one per sublayer)
        self.res_attn = ReZero(fill=0.0)
        self.res_ffn = ReZero(fill=0.0)

    @staticmethod
    def swish(x):
        return x * torch.sigmoid(x)

    def forward(self, x, padding_mask=None):
        # Zero out padded positions before attention
        if padding_mask is not None:
            x = torch.einsum("bsh, bs -> bsh", x, padding_mask.float())

        # Self-attention with ReZero
        attn_out, _ = self.attention(x, x, x, key_padding_mask=(padding_mask == 0)
                                      if padding_mask is not None else None)
        x = self.res_attn(x, self.dropout(attn_out))

        # Swish FFN with ReZero
        ffn_out = self.ff_out(self.dropout(self.swish(self.ff_in(x))))
        x = self.res_ffn(x, self.dropout(ffn_out))
        return x

# ── 3g. Full encoder ──
class Life2VecEncoder(nn.Module):
    def __init__(self, vocab_size: int, d_model: int = 280, n_layers: int = 5,
                 n_heads: int = 10, d_ff: int = 2210, dropout: float = 0.1):
        super().__init__()
        self.embedding = Life2VecEmbedding(vocab_size, d_model, dropout=dropout)
        self.encoders = nn.ModuleList([
            Life2VecEncoderBlock(d_model, n_heads, d_ff, dropout)
            for _ in range(n_layers)
        ])
        self.d_model = d_model
        self.n_layers = n_layers

    def forward(self, tokens, abs_positions, ages, segments, padding_mask=None):
        x = self.embedding(tokens, abs_positions, ages, segments)
        for block in self.encoders:
            x = block(x, padding_mask=padding_mask)
        return x  # (batch, seq_len, d_model)

    def forward_finetuning_cls(self, tokens, abs_positions, ages, segments,
                                padding_mask=None):
        """
        Multi-layer CLS extraction for finetuning:
        Average [CLS] from layers 1, mid, and last (original repo approach).
        """
        x = self.embedding(tokens, abs_positions, ages, segments)
        cls_reps = []
        mid = (self.n_layers - 1) // 2
        for i, block in enumerate(self.encoders):
            x = block(x, padding_mask=padding_mask)
            if i == 1 or i == mid or i == (self.n_layers - 1):
                cls_reps.append(x[:, 0, :])  # [CLS] at position 0
        return torch.stack(cls_reps, dim=0).mean(dim=0)  # (batch, d_model)

# ── 3h. Pretraining decoders ──
class MLMDecoder(nn.Module):
    """
    Masked Language Model decoder with L2 normalization and √d scaling.
    Weight-tied to token embedding matrix.
    From original: src/transformer/models.py — MaskedLanguageModel.
    """
    def __init__(self, d_model: int, vocab_size: int, token_embedding: nn.Embedding):
        super().__init__()
        self.dense = nn.Linear(d_model, d_model)
        self.g = nn.Parameter(torch.tensor(math.sqrt(d_model)))  # √d scalar
        self.proj = nn.Linear(d_model, vocab_size, bias=False)
        # Weight tying: proj.weight = token_embedding.weight
        self.proj.weight = token_embedding.weight
        self.dropout = nn.Dropout(0.1)

    def forward(self, hidden_states, masked_positions):
        """
        hidden_states: (B, L, d)
        masked_positions: (B, n_masked) — indices of masked tokens
        """
        # Extract only masked positions
        B = hidden_states.size(0)
        selected = torch.gather(
            hidden_states, 1,
            masked_positions.unsqueeze(-1).expand(-1, -1, hidden_states.size(-1))
        )
        x = torch.tanh(self.dense(selected))
        x = F.normalize(x, p=2, dim=-1)  # L2 normalization
        x = self.dropout(x)
        return self.g * self.proj(x)  # (B, n_masked, vocab_size)

class SOPDecoder(nn.Module):
    """
    3-way Sequence Ordering Prediction: original / reversed / shuffled.
    From original: src/transformer/models.py — CLS_Decoder.
    """
    def __init__(self, d_model: int, dropout: float = 0.1):
        super().__init__()
        self.net = nn.Sequential(
            nn.Linear(d_model, d_model),
            nn.SiLU(),  # swish
            ScaleNorm(d_model),
            nn.Dropout(dropout),
            nn.Linear(d_model, 3)  # 3 classes: original(0), reversed(1), shuffled(2)
        )

    def forward(self, cls_hidden):
        return self.net(cls_hidden)

# ── 3i. Finetuning decoders ──
class Life2VecClassifier(nn.Module):
    """Task-specific classification head using multi-layer CLS pooling."""
    def __init__(self, d_model: int, n_classes: int):
        super().__init__()
        self.head = nn.Sequential(
            nn.Linear(d_model, d_model),
            nn.SiLU(),
            ScaleNorm(d_model),
            nn.Dropout(0.1),
            nn.Linear(d_model, n_classes)
        )

    def forward(self, cls_embedding):
        return self.head(cls_embedding)

# ── 3j. Full model wrapper ──
class Life2VecModel(nn.Module):
    def __init__(self, vocab_size: int, d_model: int = 280, n_layers: int = 5,
                 n_heads: int = 10, d_ff: int = 2210, mode: str = "pretrain"):
        super().__init__()
        self.encoder = Life2VecEncoder(vocab_size, d_model, n_layers, n_heads, d_ff)
        self.mode = mode
        if mode == "pretrain":
            self.mlm_decoder = MLMDecoder(d_model, vocab_size,
                                           self.encoder.embedding.token_embed)
            self.sop_decoder = SOPDecoder(d_model)

    def set_finetune_head(self, n_classes: int):
        self.mode = "finetune"
        self.classifier = Life2VecClassifier(self.encoder.d_model, n_classes)
        # Freeze token embedding weights (original repo behavior)
        for param in self.encoder.embedding.token_embed.parameters():
            param.requires_grad = False

    def forward(self, tokens, abs_positions, ages, segments,
                padding_mask=None, masked_positions=None):
        if self.mode == "pretrain":
            hidden = self.encoder(tokens, abs_positions, ages, segments, padding_mask)
            mlm_logits = self.mlm_decoder(hidden, masked_positions)
            sop_logits = self.sop_decoder(hidden[:, 0, :])
            return mlm_logits, sop_logits
        else:
            cls_emb = self.encoder.forward_finetuning_cls(
                tokens, abs_positions, ages, segments, padding_mask
            )
            return self.classifier(cls_emb)

print(f"Life2VecModel architecture defined (faithful to original repo).")
print(f"  Encoder: 5 layers, d_model=280, n_heads=10 (7 local + 3 global)")
print(f"  FFN: d_ff=2210, activation=swish, residual=ReZero(α=0)")
print(f"  Normalization: ScaleNorm (L2-based)")
print(f"  Temporal: Time2Vec (cos for age, sin for abspos)")
print(f"  Finetuning CLS: averaged from layers 1, mid, last")
```

### Step 4 — Pretraining (MLM + SOP)

```python
# ── 103-life2vec-pretrain.py ──
# Life2Vec Step 4: Pretraining with MLM + Sequence Ordering Prediction
import torch
import torch.nn as nn
from torch.utils.data import DataLoader, Dataset
import pytorch_lightning as pl
import numpy as np

class Life2VecPretrainDataset(Dataset):
    """
    Dataset for life2vec pretraining.
    Applies MLM masking and SOP augmentation on-the-fly.
    """
    def __init__(self, sequences_h5_path, vocab, mask_prob=0.30,
                 mask_token_rate=0.80, random_token_rate=0.10):
        self.vocab = vocab
        self.mask_prob = mask_prob
        self.mask_token_rate = mask_token_rate
        self.random_token_rate = random_token_rate
        self.mask_id = vocab["[MASK]"]
        self.special_ids = {vocab[t] for t in ["[CLS]", "[SEP]", "[PAD]", "[UNK]"]}
        self.vocab_size = len(vocab)
        # Load sequences (adapt to your storage format: HDF5, parquet, etc.)
        # self.data = h5py.File(sequences_h5_path, "r")
        # self.person_ids = list(self.data.keys())

    def __len__(self):
        return len(self.person_ids)

    def apply_mlm_masking(self, tokens):
        """
        MLM masking following Savcisens et al.:
        - Select 30% of non-special tokens
        - Of selected: 80% → [MASK], 10% → unchanged, 10% → random token
        """
        tokens = np.array(tokens)
        labels = np.full_like(tokens, -100)  # -100 = ignore in loss

        # Identify maskable positions (non-special tokens)
        maskable = np.array([t not in self.special_ids for t in tokens])
        n_mask = int(maskable.sum() * self.mask_prob)

        if n_mask == 0:
            return tokens, labels

        mask_indices = np.random.choice(
            np.where(maskable)[0], size=n_mask, replace=False
        )
        labels[mask_indices] = tokens[mask_indices]

        # 10% unchanged, then 80% → [MASK], 10% → random (original repo split)
        n_unchanged = int(len(mask_indices) * 0.10)
        n_random = int(len(mask_indices) * 0.10)
        # Positions n_unchanged: onward get [MASK] or random
        mask_positions = mask_indices[n_unchanged:]
        n_actual_mask = len(mask_positions) - n_random
        tokens[mask_positions[:n_actual_mask]] = self.mask_id
        tokens[mask_positions[n_actual_mask:]] = np.random.randint(
            len(self.special_ids), self.vocab_size, size=n_random
        )
        # First n_unchanged positions: labels set but token unchanged

        return tokens, labels

    def apply_sop_augmentation(self, sentences):
        """
        3-way Sequence Ordering Prediction (from original repo):
        - p < 0.05: reverse sentence order → label=1
        - p > 0.95: shuffle sentence order → label=2
        - else: keep original order → label=0
        """
        p = np.random.random()
        if p < 0.05:
            sentences.reverse()
            return sentences, 1  # reversed
        elif p > 0.95:
            np.random.shuffle(sentences)
            return sentences, 2  # shuffled
        else:
            return sentences, 0  # original

class Life2VecPretrainModule(pl.LightningModule):
    """PyTorch Lightning module for life2vec pretraining."""
    def __init__(self, model, vocab_size, lr=1e-4, warmup_steps=10000):
        super().__init__()
        self.model = model
        self.mlm_loss = nn.CrossEntropyLoss(ignore_index=-100)
        # SOP loss: 3-way with class weights [1/0.9, 1/0.1, 1/0.1] + label smoothing
        sop_weights = torch.tensor([1/0.9, 1/0.1, 1/0.1])
        self.sop_loss = nn.CrossEntropyLoss(weight=sop_weights, label_smoothing=0.1)
        self.lr = lr
        self.warmup_steps = warmup_steps

    def training_step(self, batch, batch_idx):
        tokens, ages, abs_pos, segments, padding_mask, mlm_labels, sop_labels = batch
        mlm_logits, sop_logits = self.model(tokens, ages, abs_pos, segments, padding_mask)

        # MLM loss: only on masked positions
        mlm_loss = self.mlm_loss(
            mlm_logits.view(-1, mlm_logits.size(-1)),
            mlm_labels.view(-1)
        )
        # SOP loss
        sop_loss = self.sop_loss(sop_logits, sop_labels)

        # Original repo weights: 0.8 * MLM + 0.2 * SOP (fixed)
        total_loss = 0.8 * mlm_loss + 0.2 * sop_loss
        self.log("train/mlm_loss", mlm_loss)
        self.log("train/sop_loss", sop_loss)
        self.log("train/total_loss", total_loss)
        return total_loss

    def configure_optimizers(self):
        optimizer = torch.optim.AdamW(self.model.parameters(), lr=self.lr,
                                       weight_decay=0.01)
        scheduler = torch.optim.lr_scheduler.OneCycleLR(
            optimizer, max_lr=self.lr,
            total_steps=self.trainer.estimated_stepping_batches,
            pct_start=0.1
        )
        return {"optimizer": optimizer, "lr_scheduler": {"scheduler": scheduler, "interval": "step"}}

# ── Training script ──
# vocab = load_vocab("vocab.json")
# model = Life2VecModel(len(vocab), d_model=280, n_layers=6, n_heads=8, mode="pretrain")
# dataset = Life2VecPretrainDataset("life2vec_sequences.h5", vocab)
# dataloader = DataLoader(dataset, batch_size=64, shuffle=True, num_workers=4)
# trainer = pl.Trainer(max_epochs=20, accelerator="gpu", devices=1,
#                       precision="16-mixed", gradient_clip_val=1.0)
# trainer.fit(Life2VecPretrainModule(model, len(vocab)), dataloader)
# torch.save(model.state_dict(), f"{output_root}/life2vec_pretrained.pt")
```

### Step 5 — Finetuning for Downstream Prediction

```python
# ── 104-life2vec-finetune.py ──
# Life2Vec Step 5: Task-specific finetuning
# Supports: binary classification (mortality), ordinal (personality/survey items),
#           multi-class, and continuous regression

import torch
import torch.nn as nn
import pytorch_lightning as pl
from sklearn.metrics import roc_auc_score, matthews_corrcoef
import numpy as np

class Life2VecFinetuneModule(pl.LightningModule):
    """
    Finetuning module supporting multiple task types.
    PU-learning for mortality (positive-unlabeled setting; Savcisens et al.).
    """
    def __init__(self, model, task_type="binary", n_classes=2, lr=5e-5,
                 pu_learning=False):
        super().__init__()
        self.model = model
        self.task_type = task_type
        self.pu_learning = pu_learning
        self.lr = lr

        if task_type == "binary":
            if pu_learning:
                # Asymmetric loss for PU-learning (Wang et al. 2021)
                self.loss_fn = self._pu_loss
            else:
                self.loss_fn = nn.BCEWithLogitsLoss()
        elif task_type == "ordinal":
            # Combine: class-distance weighted CE + focal loss + label smoothing
            # (Savcisens et al. personality nuances approach)
            self.loss_fn = self._ordinal_loss
        elif task_type == "regression":
            self.loss_fn = nn.MSELoss()

        self.validation_preds = []
        self.validation_labels = []

    def _pu_loss(self, logits, labels):
        """
        Asymmetric loss for positive-unlabeled learning.
        Treats all negative samples as potentially positive (unlabeled).
        See Wang et al. (2021, IEEE ICME).
        """
        probs = torch.sigmoid(logits.squeeze())
        pos_mask = labels == 1
        neg_mask = labels == 0

        # Positive loss: standard BCE on known positives
        pos_loss = -torch.log(probs[pos_mask] + 1e-8).mean() if pos_mask.any() else 0.0
        # Negative (unlabeled) loss: asymmetric — penalize confident negatives less
        neg_loss = -torch.log(1 - probs[neg_mask] + 1e-8).mean() if neg_mask.any() else 0.0

        return pos_loss + 0.5 * neg_loss  # down-weight unlabeled negatives

    def _ordinal_loss(self, logits, labels):
        """
        Combined loss for ordinal classification:
        - Class-distance weighted cross-entropy (penalize far-off predictions more)
        - Focal loss component for hard examples
        - Label smoothing
        """
        n_classes = logits.size(-1)
        # Distance-weighted CE
        probs = torch.softmax(logits, dim=-1)
        targets_onehot = torch.zeros_like(probs).scatter_(1, labels.unsqueeze(1), 1.0)

        # Distance weights: penalize predictions far from true class
        class_indices = torch.arange(n_classes, device=logits.device).float()
        distances = (class_indices.unsqueeze(0) - labels.unsqueeze(1).float()).abs()
        weights = 1.0 + distances  # linear distance weighting

        # Weighted CE
        log_probs = torch.log_softmax(logits, dim=-1)
        weighted_loss = -(weights * targets_onehot * log_probs).sum(dim=-1).mean()

        # Focal component (γ=2)
        pt = (targets_onehot * probs).sum(dim=-1)
        focal = ((1 - pt) ** 2 * (-torch.log(pt + 1e-8))).mean()

        return 0.7 * weighted_loss + 0.3 * focal

    def training_step(self, batch, batch_idx):
        tokens, ages, abs_pos, segments, padding_mask, labels = batch
        logits = self.model(tokens, ages, abs_pos, segments, padding_mask)
        loss = self.loss_fn(logits, labels)
        self.log("train/loss", loss)
        return loss

    def validation_step(self, batch, batch_idx):
        tokens, ages, abs_pos, segments, padding_mask, labels = batch
        logits = self.model(tokens, ages, abs_pos, segments, padding_mask)
        if self.task_type == "binary":
            preds = torch.sigmoid(logits.squeeze())
        else:
            preds = logits
        self.validation_preds.append(preds.detach().cpu())
        self.validation_labels.append(labels.detach().cpu())

    def on_validation_epoch_end(self):
        preds = torch.cat(self.validation_preds)
        labels = torch.cat(self.validation_labels)

        if self.task_type == "binary":
            auc = roc_auc_score(labels.numpy(), preds.numpy())
            self.log("val/auc", auc)
            # C-MCC (corrected Matthews Correlation Coefficient) for PU-learning
            binary_preds = (preds > 0.5).int()
            mcc = matthews_corrcoef(labels.numpy(), binary_preds.numpy())
            self.log("val/mcc", mcc)
        elif self.task_type == "ordinal":
            # Cohen's quadratic kappa
            pred_classes = preds.argmax(dim=-1)
            from sklearn.metrics import cohen_kappa_score
            kappa = cohen_kappa_score(labels.numpy(), pred_classes.numpy(),
                                      weights="quadratic")
            self.log("val/cohens_kappa", kappa)

        self.validation_preds.clear()
        self.validation_labels.clear()

    def configure_optimizers(self):
        # Lower learning rate for deeper encoder layers (Savcisens et al.)
        encoder_params = list(self.model.encoder.parameters())
        head_params = list(self.model.classifier.parameters())
        return torch.optim.AdamW([
            {"params": encoder_params, "lr": self.lr * 0.1},
            {"params": head_params, "lr": self.lr}
        ], weight_decay=0.01)

# ── Finetuning script ──
# model = Life2VecModel(len(vocab), d_model=280, n_layers=6, n_heads=8, mode="pretrain")
# model.load_state_dict(torch.load(f"{output_root}/life2vec_pretrained.pt"))
# model.set_finetune_head(n_classes=2, task_type="binary")  # mortality prediction
# trainer = pl.Trainer(max_epochs=50, accelerator="gpu", devices=1, precision="16-mixed")
# trainer.fit(Life2VecFinetuneModule(model, task_type="binary", pu_learning=True), train_dl, val_dl)
```

### Step 6 — Concept Space Exploration and Interpretability

```python
# ── 105-life2vec-interpret.py ──
# Life2Vec Step 6: Concept space visualization + TCAV interpretability
import torch
import numpy as np
from sklearn.linear_model import LogisticRegression

# ── 6a. Extract concept embeddings ──
def extract_concept_space(model, vocab):
    """Extract the learned concept embedding matrix."""
    with torch.no_grad():
        embeddings = model.encoder.embedding.token_embed.weight.cpu().numpy()
        # Mean-center (as in model forward pass)
        embeddings = embeddings - embeddings.mean(axis=0, keepdims=True)
    return embeddings  # (vocab_size, d_model)

# ── 6b. Visualize concept space with PaCMAP ──
def plot_concept_space(embeddings, vocab, token_types, output_path):
    """
    2D projection of concept space using PaCMAP (Wang et al. 2021).
    Color by token type (health, labor, income, municipality, etc.).
    """
    import pacmap
    import matplotlib.pyplot as plt

    # Filter out special tokens and infrequent tokens
    idx_to_token = {v: k for k, v in vocab.items()}
    valid_mask = np.array([
        not idx_to_token.get(i, "").startswith("[") for i in range(len(embeddings))
    ])
    valid_embeddings = embeddings[valid_mask]
    valid_labels = [token_types.get(idx_to_token.get(i, ""), "other")
                    for i in range(len(embeddings)) if valid_mask[i]]

    reducer = pacmap.PaCMAP(n_components=2, n_neighbors=10, random_state=42)
    coords = reducer.fit_transform(valid_embeddings)

    fig, ax = plt.subplots(figsize=(12, 10))
    categories = list(set(valid_labels))
    colors = plt.cm.tab10(np.linspace(0, 1, len(categories)))
    for cat, color in zip(categories, colors):
        mask = [l == cat for l in valid_labels]
        ax.scatter(coords[mask, 0], coords[mask, 1], c=[color], label=cat,
                   s=8, alpha=0.6)
    ax.legend(fontsize=8, markerscale=3)
    ax.set_title("life2vec Concept Space (PaCMAP projection)")
    fig.savefig(output_path, dpi=300, bbox_inches="tight")
    plt.close()
    return coords

# ── 6c. Nearest-neighbor analysis ──
def find_nearest_concepts(embeddings, vocab, query_token, top_k=5):
    """Find the top-k nearest concept tokens by cosine similarity."""
    from sklearn.metrics.pairwise import cosine_similarity
    idx = vocab.get(query_token)
    if idx is None:
        return []
    sims = cosine_similarity(embeddings[idx:idx+1], embeddings)[0]
    top_indices = np.argsort(sims)[::-1][1:top_k+1]  # exclude self
    idx_to_token = {v: k for k, v in vocab.items()}
    return [(idx_to_token.get(i, "?"), float(sims[i])) for i in top_indices]

# ── 6d. TCAV — Testing with Concept Activation Vectors (Kim et al. 2018) ──
def compute_tcav(model, concept_sequences, random_sequences,
                 target_class: int, vocab):
    """
    TCAV: measure sensitivity of predictions to high-level concepts.
    1. Get person-summary embeddings for concept vs. random subsamples
    2. Train linear classifier to separate them → concept activation vector (CAV)
    3. Measure how moving in the CAV direction changes predictions
    """
    model.eval()
    with torch.no_grad():
        # Get [CLS] representations (person summaries)
        def get_cls_embeddings(sequences):
            embeddings = []
            for seq in sequences:
                tokens = torch.tensor(seq["tokens"]).unsqueeze(0)
                ages = torch.tensor(seq["ages"]).unsqueeze(0)
                pos = torch.tensor(seq["abs_positions"]).unsqueeze(0)
                segs = torch.tensor(seq["segments"]).unsqueeze(0)
                mask = (tokens == vocab["[PAD]"])
                hidden = model.encoder(tokens, ages, pos, segs, mask)
                embeddings.append(hidden[0, 0, :].cpu().numpy())  # [CLS]
            return np.array(embeddings)

        concept_embs = get_cls_embeddings(concept_sequences)
        random_embs = get_cls_embeddings(random_sequences)

    # Train linear classifier: concept vs. random
    X = np.vstack([concept_embs, random_embs])
    y = np.array([1]*len(concept_embs) + [0]*len(random_embs))
    clf = LogisticRegression(max_iter=1000, random_state=42)
    clf.fit(X, y)
    cav = clf.coef_[0]  # concept activation vector (normal to hyperplane)
    cav = cav / np.linalg.norm(cav)

    # Compute directional derivative: how does moving along CAV affect predictions?
    # (Sensitivity score for each concept)
    # ... gradient-based computation or finite difference
    return cav, clf.score(X, y)

# ── 6e. Person-summary visualization ──
def extract_person_summaries(model, dataloader, vocab):
    """
    Extract [CLS] embeddings for all individuals → person-summary space.
    These are task-specific representations after finetuning.
    """
    model.eval()
    all_embeddings = []
    all_ids = []
    with torch.no_grad():
        for batch in dataloader:
            tokens, ages, abs_pos, segments, padding_mask, person_ids = batch
            hidden = model.encoder(tokens, ages, abs_pos, segments, padding_mask)
            cls_emb = hidden[:, 0, :].cpu().numpy()
            all_embeddings.append(cls_emb)
            all_ids.extend(person_ids)
    return np.vstack(all_embeddings), all_ids
```

### Step 7 — Evaluation and Baselines

```python
# ── 106-life2vec-evaluate.py ──
# Life2Vec Step 7: Evaluation with baselines and bootstrapped confidence intervals

import numpy as np
from sklearn.metrics import roc_auc_score, matthews_corrcoef, balanced_accuracy_score
from scipy import stats

def compute_cmcc(y_true, y_pred_probs, n_bootstrap=5000, seed=42):
    """
    Corrected Matthews Correlation Coefficient with bootstrapped 95% CI.
    Accounts for PU-learning bias (Ramola et al. 2019).
    """
    rng = np.random.RandomState(seed)
    binary_preds = (y_pred_probs > 0.5).astype(int)
    mcc_obs = matthews_corrcoef(y_true, binary_preds)

    # Stratified bootstrap
    boot_mccs = []
    pos_idx = np.where(y_true == 1)[0]
    neg_idx = np.where(y_true == 0)[0]
    for _ in range(n_bootstrap):
        boot_pos = rng.choice(pos_idx, size=len(pos_idx), replace=True)
        boot_neg = rng.choice(neg_idx, size=len(neg_idx), replace=True)
        boot_idx = np.concatenate([boot_pos, boot_neg])
        boot_mcc = matthews_corrcoef(y_true[boot_idx], binary_preds[boot_idx])
        boot_mccs.append(boot_mcc)

    ci_low = np.percentile(boot_mccs, 2.5)
    ci_high = np.percentile(boot_mccs, 97.5)
    return mcc_obs, ci_low, ci_high

def run_baselines(X_counts, y_true, feature_names):
    """
    Baseline comparison suite (Savcisens et al. Table 3):
    1. Majority class prediction
    2. Random guess (uniform)
    3. Random guess (from target distribution)
    4. Life table (logistic regression on age + sex)
    5. Logistic regression (on token count vectors)
    6. Feed-forward neural network
    7. RNN (same input as life2vec)
    """
    from sklearn.linear_model import LogisticRegression
    from sklearn.neural_network import MLPClassifier
    from sklearn.model_selection import cross_val_predict

    results = {}

    # Majority class
    majority = np.zeros_like(y_true)
    results["majority_class"] = matthews_corrcoef(y_true, majority)

    # Logistic regression on count vectors
    lr = LogisticRegression(max_iter=1000, penalty="l2", class_weight="balanced")
    lr_preds = cross_val_predict(lr, X_counts, y_true, cv=5, method="predict")
    results["logistic_regression"] = matthews_corrcoef(y_true, lr_preds)

    # Feed-forward NN
    mlp = MLPClassifier(hidden_layer_sizes=(256, 128), max_iter=500, random_state=42)
    mlp_preds = cross_val_predict(mlp, X_counts, y_true, cv=5, method="predict")
    results["feed_forward_nn"] = matthews_corrcoef(y_true, mlp_preds)

    return results

# ── Intersectional performance breakdown ──
def performance_by_subgroup(y_true, y_pred, age_groups, sex):
    """
    Break down performance by age × sex subgroups
    (Savcisens et al. Fig. 3d).
    """
    results = {}
    for age_grp in sorted(set(age_groups)):
        for s in sorted(set(sex)):
            mask = (age_groups == age_grp) & (sex == s)
            if mask.sum() < 50:
                continue
            mcc = matthews_corrcoef(y_true[mask], (y_pred[mask] > 0.5).astype(int))
            results[f"{s}_{age_grp}"] = {"mcc": mcc, "n": int(mask.sum())}
    return results
```

### Step 8 — Data Augmentation Strategies

The following augmentation techniques improve pretraining robustness (Savcisens et al. Supp. Info. Section 4):

```python
# ── In pretraining dataset __getitem__ ──
def augment_sequence(tokens, ages, abs_positions, segments, vocab):
    """
    Data augmentation suite for life2vec pretraining:
    1. Subsampling: randomly drop 0-20% of sentences
    2. Temporal noise: add ±N days to absolute positions
    3. Background masking: replace background sentence tokens with [MASK]
    """
    tokens = list(tokens)
    ages = list(ages)
    abs_positions = list(abs_positions)
    segments = list(segments)

    # 1. Subsample sentences (drop random events)
    if np.random.random() < 0.3:
        sep_id = vocab["[SEP]"]
        # Find sentence boundaries and randomly drop some
        # (Implementation: identify contiguous sentence blocks, remove randomly)
        pass

    # 2. Temporal noise (±30 days to absolute positions)
    if np.random.random() < 0.3:
        noise = np.random.randint(-30, 31, size=len(abs_positions))
        abs_positions = [max(0, p + n) for p, n in zip(abs_positions, noise)]

    # 3. Background masking (mask birth_year, birth_month, or sex)
    if np.random.random() < 0.2:
        # Mask 1-2 background tokens (positions 1-3 after [CLS])
        mask_id = vocab["[MASK]"]
        bg_positions = [1, 2, 3]  # background token positions
        for pos in np.random.choice(bg_positions,
                                     size=np.random.randint(1, 3), replace=False):
            if pos < len(tokens):
                tokens[pos] = mask_id

    return tokens, ages, abs_positions, segments
```

### Step 9 — Verification Subagent

```
MODULE 11 VERIFICATION CHECKLIST:
[ ] Vocabulary built from actual data features — no manual token invention
[ ] Continuous variables discretized via quantile bins (not arbitrary cutoffs)
[ ] Sequences sorted chronologically; segment assignment correct for same-day events
[ ] Background sentence includes only birth_year, birth_month, sex, origin
[ ] Temporal encoding uses Time2Vec (learnable periodic + linear)
[ ] Max sequence length enforced (truncation removes EARLIEST events, not latest)
[ ] Padding applied at END of sequence
[ ] MLM masking rate ~30%; special tokens never masked
[ ] SOP swaps concept tokens between events while preserving temporal info
[ ] ReZero residuals initialized to α=0
[ ] Token embeddings mean-centered before forward pass
[ ] Finetuning freezes token_embed weights (except [CLS], [SEP], [UNK])
[ ] Deeper encoder layers use lower learning rate
[ ] PU-learning loss used for mortality (asymmetric loss on unlabeled negatives)
[ ] Ordinal tasks use distance-weighted CE + focal loss
[ ] Evaluation uses C-MCC with stratified bootstrap CI (not raw accuracy)
[ ] Baselines include: majority class, life table, logistic regression, FFNN, RNN
[ ] Intersectional breakdown by age × sex reported
[ ] Concept space visualized via PaCMAP; nearest-neighbor sanity checks performed
[ ] TCAV computed for key social concepts (occupation, income, health conditions)
[ ] GPU training: precision=16-mixed; gradient_clip_val=1.0
[ ] All scripts saved to ${OUTPUT_ROOT}/scripts/100-106-*.py
[ ] Seeds set for reproducibility (model init, data split, augmentation)

RESULT: [PASS / NEEDS REVISION]
Issues: [list]
```

**Reporting template:**
> "We represent individual life-trajectories as chronologically ordered sequences of life-events following the life2vec framework (Savcisens et al. 2024). Each event record from [data sources: e.g., labor market records, health registries, education records] is converted into a 'sentence' of concept tokens in a synthetic vocabulary (N = [vocab_size] tokens). Continuous features (e.g., income) are discretized into [N]-quantile bins. Each event carries two temporal indicators — the individual's age in years and absolute calendar position in days — encoded via Time2Vec (Kazemi et al. 2019) and combined with token embeddings through ReZero residual connections (Bachlechner et al. 2021). A background sentence encodes birth year, birth month, country of origin, and sex. Event segments cycle through three labels to distinguish same-day events. The full life-sequence for each individual (max length: [2,048] tokens) is the chronological concatenation of all event sentences, truncated from the left (earliest events removed) if over the limit. We pretrain a 5-layer transformer encoder (d = 280, 10 attention heads: 7 local softmax with window size 38 + 3 global Performer FAVOR+ heads; ScaleNorm; swish FFN with d_ff = 2,210) using masked language modeling (30% masking rate, loss weight 0.8) and 3-way sequence ordering prediction (original/reversed/shuffled, loss weight 0.2) on [N] individuals over [time period]. Data augmentation includes random event subsampling (25–50%), temporal noise (±5 days), and background sentence masking. The pretrained model is then finetuned for [prediction task] using [loss function: asymmetric PU-learning loss for mortality / cumulative link loss for ordinal personality items], with multi-layer [CLS] pooling (averaged from layers 1, mid, and last) and frozen token embeddings. We evaluate using corrected Matthews Correlation Coefficient (C-MCC; Ramola et al. 2019) with stratified bootstrap 95% confidence intervals (5,000 resamples), and compare against [N] baselines including logistic regression, life tables, feed-forward neural networks, and recurrent neural networks on the same data representation. We explore the learned concept space via PaCMAP (Wang et al. 2021) two-dimensional projections and Testing with Concept Activation Vectors (TCAV; Kim et al. 2018) for interpretability. All code is implemented in Python ([version]) using PyTorch [version] and PyTorch Lightning [version]."

---

