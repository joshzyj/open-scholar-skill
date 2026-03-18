# Computer Vision Reference for Social Science

## Model Selection Guide

| Model | Architecture | Parameters | Best for |
|-------|-------------|-----------|---------|
| **DINOv2-Large** | ViT-L/14 | 307M | General features; clustering; no labels needed |
| **CLIP ViT-L/14** | ViT-L/14 | 307M | Zero-shot classification; image-text similarity |
| **ConvNeXt-Base** | ConvNet | 89M | Fine-tuning with ≥500 labeled images; fast inference |
| **EfficientNet-B4** | ConvNet | 19M | Fine-tuning with limited compute; mobile deployment |
| **ViT-B/16** | ViT | 86M | Fine-tuning; standard benchmark model |
| **DINOv2-Base** | ViT-B/14 | 86M | Faster DINOv2 variant for smaller datasets |
| **VideoMAE-Base** | ViT-B | 87M | Video temporal understanding; action recognition |

**Rule of thumb**:
- N_labeled = 0 → CLIP zero-shot or DINOv2 + clustering
- N_labeled = 100–500 → CLIP zero-shot + few-shot fine-tuning; or logistic regression on DINOv2 features
- N_labeled > 500 → ConvNeXt-Base or ViT-B/16 fine-tuning
- Semantic reasoning needed → Multimodal LLM (Claude / GPT-4o)
- Video sequences → VideoMAE; or image-level model on sampled frames

---

## Full DINOv2 Feature Extraction Workflow

```python
from transformers import AutoImageProcessor, AutoModel
import torch, numpy as np, pandas as pd
from pathlib import Path
import PIL.Image
from torch.utils.data import DataLoader, Dataset

device    = "cuda" if torch.cuda.is_available() else "cpu"
processor = AutoImageProcessor.from_pretrained("facebook/dinov2-large")
model     = AutoModel.from_pretrained("facebook/dinov2-large").to(device).eval()

class SimpleImageDataset(Dataset):
    def __init__(self, paths, processor):
        self.paths     = paths
        self.processor = processor

    def __len__(self): return len(self.paths)

    def __getitem__(self, idx):
        img = PIL.Image.open(self.paths[idx]).convert("RGB")
        return self.processor(images=img, return_tensors="pt")["pixel_values"][0]

img_paths = sorted(Path("data/images/").glob("*.jpg"))
dataset   = SimpleImageDataset(img_paths, processor)
loader    = DataLoader(dataset, batch_size=32, num_workers=4)

all_features = []
with torch.no_grad():
    for batch in loader:
        out = model(batch.to(device))
        all_features.append(out.last_hidden_state[:, 0, :].cpu().numpy())

features = np.vstack(all_features)   # (N, 1024)
np.save("${OUTPUT_ROOT}/models/dinov2_large_features.npy", features)

# Save manifest
pd.DataFrame({"path": [str(p) for p in img_paths]}).to_csv(
    "${OUTPUT_ROOT}/models/dinov2_manifest.csv", index=False)
```

### Downstream: Logistic Regression on DINOv2 Features (Few-Shot)

```python
from sklearn.linear_model import LogisticRegressionCV
from sklearn.model_selection import StratifiedKFold
from sklearn.metrics import classification_report
import numpy as np

# features: (N, 1024) from DINOv2
# labels:   (N,) human-coded labels

X = features[labeled_idx]
y = labels_array

clf = LogisticRegressionCV(
    Cs=np.logspace(-4, 2, 10),
    cv=StratifiedKFold(5, shuffle=True, random_state=42),
    max_iter=5000, random_state=42
)
clf.fit(X_train, y_train)
print(classification_report(y_test, clf.predict(X_test)))

import joblib
joblib.dump(clf, "${OUTPUT_ROOT}/models/dinov2_logreg.pkl")
```

---

## Full CLIP Zero-Shot Workflow

```python
from transformers import CLIPProcessor, CLIPModel
import torch, numpy as np, pandas as pd
import PIL.Image

device     = "cuda" if torch.cuda.is_available() else "cpu"
clip_model = CLIPModel.from_pretrained("openai/clip-vit-large-patch14").to(device).eval()
clip_proc  = CLIPProcessor.from_pretrained("openai/clip-vit-large-patch14")

# ── Text encoding (do once) ──────────────────────────────────────────────
categories = [
    "a protest or political demonstration",
    "a peaceful gathering or celebration",
    "police or security forces in riot gear",
    "a formal press conference or political speech"
]
text_inputs = clip_proc(text=categories, return_tensors="pt",
                        padding=True, truncation=True).to(device)
with torch.no_grad():
    text_feats = clip_model.get_text_features(**text_inputs)
    text_feats = text_feats / text_feats.norm(dim=-1, keepdim=True)

# ── Image encoding (batch) ───────────────────────────────────────────────
def encode_images(paths, batch_size=32):
    all_feats = []
    for i in range(0, len(paths), batch_size):
        imgs   = [PIL.Image.open(p).convert("RGB") for p in paths[i:i+batch_size]]
        inputs = clip_proc(images=imgs, return_tensors="pt").to(device)
        with torch.no_grad():
            feats = clip_model.get_image_features(**inputs)
        feats = feats / feats.norm(dim=-1, keepdim=True)
        all_feats.append(feats.cpu().numpy())
    return np.vstack(all_feats)

img_feats = encode_images(img_paths)
logits    = (100.0 * img_feats @ text_feats.cpu().numpy().T)
probs     = np.exp(logits) / np.exp(logits).sum(axis=1, keepdims=True)

results = pd.DataFrame({
    "path":      img_paths,
    "predicted": [categories[i] for i in probs.argmax(axis=1)],
    "confidence": probs.max(axis=1)
})
results.to_csv("${OUTPUT_ROOT}/tables/clip-zero-shot.csv", index=False)
```

---

## ConvNeXt Fine-Tuning Workflow

```python
import timm, torch, torch.nn as nn
from torch.optim import AdamW
from torch.optim.lr_scheduler import CosineAnnealingLR
from sklearn.metrics import classification_report, confusion_matrix
import matplotlib.pyplot as plt, seaborn as sns

torch.manual_seed(42)
device = "cuda" if torch.cuda.is_available() else "cpu"

# ── Model ────────────────────────────────────────────────────────────────
model = timm.create_model("convnext_base.fb_in22k_ft_in1k",
                           pretrained=True, num_classes=N_CLASSES).to(device)

# Freeze backbone first (warm-up phase)
for param in list(model.parameters())[:-20]:
    param.requires_grad = False

optimizer = AdamW(filter(lambda p: p.requires_grad, model.parameters()),
                  lr=1e-4, weight_decay=0.01)
criterion = nn.CrossEntropyLoss(label_smoothing=0.1)

# Phase 1: train classification head only (3 epochs)
for epoch in range(3):
    model.train()
    for imgs, labels, _ in train_loader:
        loss = criterion(model(imgs.to(device)), labels.to(device))
        optimizer.zero_grad(); loss.backward(); optimizer.step()

# Phase 2: unfreeze all + lower LR (full fine-tuning)
for param in model.parameters():
    param.requires_grad = True
optimizer = AdamW(model.parameters(), lr=2e-5, weight_decay=0.01)
scheduler = CosineAnnealingLR(optimizer, T_max=10)

for epoch in range(10):
    model.train()
    for imgs, labels, _ in train_loader:
        loss = criterion(model(imgs.to(device)), labels.to(device))
        optimizer.zero_grad(); loss.backward(); optimizer.step()
    scheduler.step()

# ── Evaluation ────────────────────────────────────────────────────────────
model.eval()
preds_all, labels_all = [], []
with torch.no_grad():
    for imgs, labels, _ in test_loader:
        preds = model(imgs.to(device)).argmax(dim=-1).cpu()
        preds_all.extend(preds.tolist())
        labels_all.extend(labels.tolist())

print(classification_report(labels_all, preds_all, target_names=class_names))

# Confusion matrix
cm = confusion_matrix(labels_all, preds_all)
fig, ax = plt.subplots(figsize=(8,6))
sns.heatmap(cm, annot=True, fmt="d", xticklabels=class_names,
            yticklabels=class_names, ax=ax)
plt.savefig("${OUTPUT_ROOT}/figures/fig-cv-confusion-matrix.pdf", bbox_inches="tight", dpi=300)
torch.save(model.state_dict(), "${OUTPUT_ROOT}/models/convnext-finetuned.pt")
```

---

## Multimodal LLM Annotation — Full Workflow

### Claude (Anthropic)

```python
import anthropic, base64, json, time, pandas as pd

client = anthropic.Anthropic()

def load_image_b64(path: str) -> tuple[str, str]:
    """Returns (base64_data, media_type)."""
    ext_map = {"jpg": "image/jpeg", "jpeg": "image/jpeg",
               "png": "image/png", "webp": "image/webp"}
    ext = path.rsplit(".", 1)[-1].lower()
    with open(path, "rb") as f:
        return base64.standard_b64encode(f.read()).decode(), ext_map.get(ext, "image/jpeg")

SYSTEM = """You are a social science research assistant coding protest images.
For each image, provide:
  - protest_present: 1 if protest/demonstration clearly visible, 0 otherwise
  - crowd_size: "small" (<50), "medium" (50–500), "large" (>500), "unclear"
  - police_present: 1 if uniformed police/security visible, 0 otherwise
  - confrontation: 1 if direct confrontation between groups visible, 0 otherwise
  - setting: "outdoor_urban", "outdoor_rural", "indoor", "unclear"
  - confidence: "high", "medium", or "low"
Respond ONLY with valid JSON matching this schema."""

def annotate_image(img_path: str) -> dict:
    img_b64, media_type = load_image_b64(img_path)
    msg = client.messages.create(
        model="claude-sonnet-4-6",
        max_tokens=250,
        temperature=0,
        system=SYSTEM,
        messages=[{"role": "user", "content": [
            {"type": "image",
             "source": {"type": "base64", "media_type": media_type, "data": img_b64}},
            {"type": "text", "text": "Code this image:"}
        ]}]
    )
    result = json.loads(msg.content[0].text)
    result.update({"path": img_path, "model": "claude-sonnet-4-6",
                   "annot_date": "2026-02-23"})
    return result

# Batch with rate limiting + error handling
records = []
for i, path in enumerate(img_paths):
    try:
        records.append(annotate_image(str(path)))
        if i % 20 == 0 and i > 0:
            time.sleep(2)
    except Exception as e:
        records.append({"path": str(path), "error": str(e)})
        time.sleep(5)   # back off on error

df_out = pd.DataFrame(records)
df_out.to_csv("${OUTPUT_ROOT}/tables/vision-llm-annotations.csv", index=False)
print(f"Annotated: {df_out['protest_present'].notna().sum()} / {len(df_out)}")
```

### OpenAI Vision Alternative

```python
from openai import OpenAI
import base64, os

client_oai = OpenAI()

# Model selection: set OPENAI_MODEL env var or change default here
# Vision-capable models: "gpt-4.1", "gpt-4.1-mini", "gpt-5", "gpt-5-mini", "gpt-5-nano"
OPENAI_VISION_MODEL = os.getenv("OPENAI_MODEL", "gpt-4.1-mini")

def annotate_openai_vision(img_path: str, model: str = None) -> dict:
    model = model or OPENAI_VISION_MODEL
    with open(img_path, "rb") as f:
        b64 = base64.b64encode(f.read()).decode()
    response = client_oai.chat.completions.create(
        model=model,
        max_tokens=250,
        temperature=0,
        messages=[{
            "role": "user",
            "content": [
                {"type": "image_url",
                 "image_url": {"url": f"data:image/jpeg;base64,{b64}"}},
                {"type": "text",
                 "text": SYSTEM + "\n\nCode this image:"}
            ]
        }]
    )
    return json.loads(response.choices[0].message.content)
```

### LLaVA / InternVL2 (Open-Source, No API Required)

Use when you want to avoid API costs, have GPU capacity, and need full local reproducibility. **InternVL2** is generally more capable than LLaVA for structured annotation tasks.

```python
import torch
from transformers import AutoProcessor, AutoModelForCausalLM
from PIL import Image

device = "cuda" if torch.cuda.is_available() else "cpu"

# ── InternVL2-8B (recommended; stronger than LLaVA) ──────────────────
# pip install transformers accelerate
processor_ivl = AutoProcessor.from_pretrained(
    "OpenGVLab/InternVL2-8B", trust_remote_code=True)
model_ivl = AutoModelForCausalLM.from_pretrained(
    "OpenGVLab/InternVL2-8B",
    torch_dtype=torch.float16,
    device_map="auto",
    trust_remote_code=True
)

def annotate_internvl2(img_path: str, task_instruction: str) -> str:
    img    = Image.open(img_path).convert("RGB")
    prompt = f"<image>\nQuestion: {task_instruction}\nAnswer:"
    inputs = processor_ivl(images=img, text=prompt, return_tensors="pt")
    inputs = {k: v.to(device) if isinstance(v, torch.Tensor) else v
              for k, v in inputs.items()}
    with torch.no_grad():
        out = model_ivl.generate(**inputs, max_new_tokens=300, temperature=0)
    return processor_ivl.decode(out[0], skip_special_tokens=True).split("Answer:")[-1].strip()

# ── LLaVA-1.6-7B (alternative) ───────────────────────────────────────
processor_llava = AutoProcessor.from_pretrained("llava-hf/llava-1.6-7b-hf")
model_llava     = AutoModelForCausalLM.from_pretrained(
    "llava-hf/llava-1.6-7b-hf",
    torch_dtype=torch.float16,
    device_map="auto"
)

def annotate_llava(img_path: str, task_instruction: str) -> str:
    img    = Image.open(img_path).convert("RGB")
    prompt = f"USER: <image>\n{task_instruction}\nASSISTANT:"
    inputs = processor_llava(text=prompt, images=img, return_tensors="pt")
    inputs = {k: v.to(device) for k, v in inputs.items()}
    with torch.no_grad():
        out = model_llava.generate(**inputs, max_new_tokens=200,
                                    do_sample=False)  # greedy for reproducibility
    resp = processor_llava.decode(out[0], skip_special_tokens=True)
    return resp.split("ASSISTANT:")[-1].strip()
```

**Model selection guide:**
- API budget available + complex reasoning → Claude Sonnet / GPT-4o
- Local GPU + best open-source quality → InternVL2-8B or InternVL2-26B
- Local GPU + lightweight → LLaVA-1.6-7B or InternVL2-1B
- All open-source models: always validate κ ≥ 0.70 vs. human coders before full deployment

---

## Video Analysis — Full Workflow

### Uniform Frame Extraction

```python
import cv2, os, PIL.Image
from pathlib import Path

def extract_frames_uniform(video_path: str, n_frames: int = 16,
                            out_dir: str = "${OUTPUT_ROOT}/frames") -> list[str]:
    os.makedirs(out_dir, exist_ok=True)
    cap   = cv2.VideoCapture(video_path)
    total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    fps   = cap.get(cv2.CAP_PROP_FPS)
    print(f"Video: {total} frames, {fps:.1f} fps, "
          f"{total/fps:.1f}s duration")

    indices = [int(i * total / n_frames) for i in range(n_frames)]
    paths   = []
    for idx in indices:
        cap.set(cv2.CAP_PROP_POS_FRAMES, idx)
        ret, frame = cap.read()
        if ret:
            path = os.path.join(out_dir, f"{Path(video_path).stem}_{idx:06d}.jpg")
            cv2.imwrite(path, frame)
            paths.append(path)
    cap.release()
    return paths
```

### Scene-Change Frame Extraction

```python
def extract_frames_scene_change(video_path: str, threshold: float = 30.0,
                                 min_gap_frames: int = 10,
                                 out_dir: str = "${OUTPUT_ROOT}/frames") -> list[str]:
    """Extract keyframes at visual scene transitions."""
    os.makedirs(out_dir, exist_ok=True)
    cap   = cv2.VideoCapture(video_path)
    prev  = None
    paths = []
    idx   = 0
    last_saved = -min_gap_frames

    while True:
        ret, frame = cap.read()
        if not ret: break
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        if prev is not None and idx - last_saved >= min_gap_frames:
            diff = cv2.absdiff(prev, gray).mean()
            if diff > threshold:
                path = os.path.join(out_dir,
                    f"{Path(video_path).stem}_scene_{idx:06d}.jpg")
                cv2.imwrite(path, frame)
                paths.append(path)
                last_saved = idx
        prev = gray; idx += 1
    cap.release()
    print(f"Extracted {len(paths)} scene-change frames from {video_path}")
    return paths
```

### VideoMAE Feature Extraction

```python
from transformers import VideoMAEFeatureExtractor, VideoMAEModel
import torch, numpy as np

vmae_proc  = VideoMAEFeatureExtractor.from_pretrained("MCG-NJU/videomae-base")
vmae_model = VideoMAEModel.from_pretrained("MCG-NJU/videomae-base").to(device).eval()

def extract_video_features(frame_paths: list[str], n_frames: int = 16) -> np.ndarray:
    """Returns (1, 768) CLS token feature vector for a video clip."""
    selected = frame_paths[:n_frames]
    while len(selected) < n_frames:           # pad if too few frames
        selected.append(selected[-1])
    frames = [PIL.Image.open(p).convert("RGB") for p in selected]
    inputs = vmae_proc(frames, return_tensors="pt").to(device)
    with torch.no_grad():
        out = vmae_model(**inputs)
    return out.last_hidden_state[:, 0, :].cpu().numpy()

# Process all videos
video_features = {}
for vid_path in video_paths:
    frames = extract_frames_uniform(str(vid_path), n_frames=16)
    video_features[vid_path.name] = extract_video_features(frames)

np.save("${OUTPUT_ROOT}/models/videomae-features.npy",
        np.vstack(list(video_features.values())))
```

---

## Social Science Use Cases

### Protest Event Imagery (Sociological Research)

```python
# Zero-shot protest coding using CLIP
protest_categories = [
    "a political protest or demonstration with signs",
    "a peaceful community gathering or event",
    "a police response to a crowd with riot gear",
    "a violent confrontation between protesters and police",
    "a political rally or campaign event"
]

# Recommended workflow:
# 1. CLIP zero-shot → preliminary coding
# 2. Human-code 200 images from each CLIP category
# 3. Compute κ; if < 0.70, refine categories or switch to LLM annotation
# 4. DINOv2 fine-tuning on human codes if κ ≥ 0.70 with N_labeled ≥ 500
```

### Street View Housing Condition (Demography / Housing)

```python
# DINOv2 features + human labels for housing condition
housing_labels = {
    0: "well-maintained: neat facade, good upkeep",
    1: "moderate condition: minor visible disrepair",
    2: "poor condition: boarded windows, structural damage, vacancy signs"
}

# Recommended workflow:
# 1. Sample 1,000 addresses from administrative records
# 2. Fetch Street View images via Google Street View Static API
# 3. Human-code 500 → train DINOv2-logistic regression
# 4. Validate on 200-image holdout (report κ vs. human consensus)
# 5. Apply to full sample
```

### Satellite / Aerial Imagery (Urban Inequality)

```python
# NDVI (vegetation index) from satellite bands
import numpy as np

def compute_ndvi(nir_band: np.ndarray, red_band: np.ndarray) -> np.ndarray:
    """Normalized Difference Vegetation Index: (NIR - Red) / (NIR + Red)."""
    denominator = nir_band.astype(float) + red_band.astype(float)
    denominator[denominator == 0] = np.nan
    return (nir_band.astype(float) - red_band.astype(float)) / denominator

# For urban greenness inequality:
# 1. Load Landsat 8 Band 4 (red) and Band 5 (NIR) for metro area
# 2. Compute NDVI per 30m pixel
# 3. Aggregate to census tract → merge with socioeconomic data
# 4. rasterio + geopandas recommended for spatial aggregation
```

### Historical Photograph Analysis

```python
# Multimodal LLM for complex historical image annotation
HISTORICAL_SYSTEM = """You are a historical sociologist analyzing photographs from [YEAR].
For each photograph, note:
  - decade_estimate: estimated decade the photo was taken
  - location_type: "urban_street", "industrial", "domestic", "institutional", "rural", "unclear"
  - visible_race: list any racial/ethnic groups identifiable from context and clothing
  - class_indicators: visible indicators of social class (clothing, setting, objects)
  - notable_features: any historically significant elements (3–5 words each)
  - confidence: "high", "medium", or "low"
Return JSON only."""
```

---

## Evaluation Standards for CV Tasks

### Annotation Benchmark (Required Before Full Deployment)

```python
from sklearn.metrics import (cohen_kappa_score, classification_report,
                               confusion_matrix)
import pandas as pd

def evaluate_cv_annotation(human_labels: pd.DataFrame,
                             model_labels: pd.DataFrame,
                             label_col: str = "label",
                             id_col: str = "image_id") -> dict:
    merged = human_labels.merge(model_labels, on=id_col, suffixes=("_human","_model"))
    kappa  = cohen_kappa_score(merged[f"{label_col}_human"], merged[f"{label_col}_model"])
    report = classification_report(merged[f"{label_col}_human"],
                                    merged[f"{label_col}_model"],
                                    output_dict=True)
    return {
        "kappa":     kappa,
        "n_labeled": len(merged),
        "f1_macro":  report["macro avg"]["f1-score"],
        "f1_weighted": report["weighted avg"]["f1-score"]
    }

# Print and save
metrics = evaluate_cv_annotation(human_df, model_df)
print(f"κ = {metrics['kappa']:.3f}  |  F1 (macro) = {metrics['f1_macro']:.3f}")
# κ ≥ 0.70: proceed with automated coding
# 0.60 ≤ κ < 0.70: human review of low-confidence predictions
# κ < 0.60: revise annotation schema or prompt; do not proceed
```

### Class Imbalance Handling

```python
from sklearn.utils.class_weight import compute_class_weight
import numpy as np

# For imbalanced datasets (common in protest/event imagery):
class_weights = compute_class_weight("balanced",
    classes=np.unique(y_train), y=y_train)
weight_tensor = torch.FloatTensor(class_weights).to(device)
criterion = nn.CrossEntropyLoss(weight=weight_tensor)
# Report class distribution (N per class) alongside F1 metrics

# Alternative: SMOTE oversampling of minority class
# (use BEFORE extracting features; apply to flattened feature vectors)
from imblearn.over_sampling import SMOTE

smote = SMOTE(random_state=42)
X_train_bal, y_train_bal = smote.fit_resample(X_train_features, y_train)
print(f"After SMOTE: {pd.Series(y_train_bal).value_counts().to_dict()}")
# Note: SMOTE on image pixels is not recommended; use on extracted features instead
```

**Rule of thumb**: Use class weights (loss reweighting) when imbalance ratio < 10:1; use SMOTE on feature vectors when imbalance ratio > 10:1. Always report class distribution and use F1 (macro), not accuracy.

---

## Reporting Standards

### Minimum to Report

- Model name, architecture, parameter count, source (HuggingFace model ID)
- Preprocessing: image size, normalization parameters
- Whether model is zero-shot, few-shot, or fine-tuned; if fine-tuned: N_train, N_val, N_test per class
- Human benchmark: N images coded, κ per dimension, who coded (RA training, qualification)
- All performance metrics on held-out test set (not train/val)
- Random seed; hardware (GPU type); inference time estimate for large deployments

### Methods Reporting Template

> "We code [N] images using [DINOv2-Large / CLIP ViT-L/14 / Claude Sonnet 4.6], accessed via Hugging Face Transformers [version] / the Anthropic API (model version: [X], annotation date: [YYYY-MM-DD]). Images were preprocessed to 224×224 pixels and normalized to ImageNet statistics. To validate the automated coding, two trained research assistants independently coded a random sample of N = 200 images; inter-coder reliability was κ = [X] for [dimension A] and κ = [X] for [dimension B]. We applied the same schema to the automated model; agreement with human consensus was κ = [X], indicating [substantial/near-perfect] agreement. Test-set F1 (macro) = [X] on a stratified holdout of [N] images (Table [X]). We therefore treat automated codes as reliable for the full corpus."

### Table Format for CV Results

```
Table X. Computer Vision Annotation Performance

                    Human agreement     Test-set performance
Dimension           κ (N=200)          F1 (macro)   F1 (wtd)   N per class
──────────────────────────────────────────────────────────────────────────
protest_present     0.84               0.87         0.89       [N0, N1]
police_present      0.79               0.81         0.84       [N0, N1]
crowd_size          0.72               0.74         0.77       [Ns, Nm, Nl]

Note. Human benchmark: two RA coders, stratified random sample.
Model: Claude Sonnet 4.6 (annotation date: 2026-02-23), temperature=0.
Test set: stratified holdout (20%), N = [X] images.
```

---

## References

- Oquab, M., et al. (2023). DINOv2: Learning robust visual features without supervision. *arXiv:2304.07193*.
- Radford, A., et al. (2021). Learning transferable visual models from natural language supervision. *ICML*.
- Liu, Z., et al. (2022). A ConvNet for the 2020s. *CVPR*.
- Dosovitskiy, A., et al. (2021). An image is worth 16x16 words: Transformers for image recognition at scale. *ICLR*.
- Wang, C., et al. (2022). VideoMAE: Masked autoencoders are data-efficient learners for self-supervised video pre-training. *NeurIPS*.
- Lin, H., & Zhang, Y. (2025). Navigating the risks of using large language models for text annotation in social science research. *Social Science Computer Review*. DOI: 10.1177/08944393251366243.
