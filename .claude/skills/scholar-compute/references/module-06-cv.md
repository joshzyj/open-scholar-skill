## MODULE 6: Computer Vision — Image and Video as Data

### Step 1 — Method Selection

| Goal | Recommended model | Package |
|------|------------------|---------|
| General visual features (unsupervised) | **DINOv2-Large** | `transformers` (Hugging Face) |
| Zero-shot classification / similarity | **CLIP ViT-L/14** | `transformers` |
| Fine-tuned classification (N > 500 labeled) | **ConvNeXt-Base** or **EfficientNet-B4** | `timm`, `torchvision` |
| Large-scale zero-shot with rich reasoning | **ViT-B/16** via HF | `transformers` |
| Multimodal annotation (VQA, description) | **GPT-4o** / **Claude** / **LLaVA** | `openai`, `anthropic` |
| Video temporal dynamics | **VideoMAE-Base** | `transformers` |
| Street view / satellite coding | DINOv2 + CLIP zero-shot | `transformers` |

**Social science use cases**: protest / event imagery coding; facial expression / crowd density; historical photograph analysis; housing condition from street view; land use from satellite; social media video content analysis.

---

### Step 2 — Data Preparation

```python
import os, PIL.Image, torch
from torchvision import transforms
from torch.utils.data import Dataset, DataLoader

# Standard preprocessing for pretrained ViT-family models
TRANSFORM = transforms.Compose([
    transforms.Resize(256),
    transforms.CenterCrop(224),
    transforms.ToTensor(),
    transforms.Normalize(mean=[0.485, 0.456, 0.406],
                         std =[0.229, 0.224, 0.225])
])

class ImageDataset(Dataset):
    def __init__(self, img_dir, label_df, transform=TRANSFORM):
        self.img_dir   = img_dir
        self.label_df  = label_df.reset_index(drop=True)
        self.transform = transform

    def __len__(self):
        return len(self.label_df)

    def __getitem__(self, idx):
        row    = self.label_df.iloc[idx]
        img    = PIL.Image.open(os.path.join(self.img_dir, row["filename"])).convert("RGB")
        label  = int(row["label"]) if "label" in row else -1
        return self.transform(img), label, row["filename"]

loader = DataLoader(ImageDataset("data/images/", label_df),
                    batch_size=32, shuffle=False, num_workers=4)
```

---

### Step 3 — Feature Extraction with DINOv2 (Best for Unsupervised / Clustering)

DINOv2 (Oquab et al. 2023, Meta) produces the strongest general-purpose visual features. Ideal for clustering images without labels.

```python
from transformers import AutoImageProcessor, AutoModel
import torch, numpy as np

device     = "cuda" if torch.cuda.is_available() else "cpu"
processor  = AutoImageProcessor.from_pretrained("facebook/dinov2-large")
dino_model = AutoModel.from_pretrained("facebook/dinov2-large").to(device).eval()

def extract_features(img_paths, batch_size=32):
    all_feats = []
    for i in range(0, len(img_paths), batch_size):
        imgs   = [PIL.Image.open(p).convert("RGB") for p in img_paths[i:i+batch_size]]
        inputs = processor(images=imgs, return_tensors="pt").to(device)
        with torch.no_grad():
            out = dino_model(**inputs)
        # CLS token = 1024-dim feature vector per image
        feats = out.last_hidden_state[:, 0, :].cpu().numpy()
        all_feats.append(feats)
    return np.vstack(all_feats)

features = extract_features(img_paths)   # shape: (N_images, 1024)
np.save("${OUTPUT_ROOT}/models/dinov2-features.npy", features)

# Downstream: cluster with k-means or UMAP + HDBSCAN
from sklearn.cluster import KMeans
kmeans = KMeans(n_clusters=10, random_state=42)
labels = kmeans.fit_predict(features)
```

---

### Step 4 — Zero-Shot Classification with CLIP

CLIP (Radford et al. 2021, OpenAI) enables zero-shot image classification using natural language labels — no training data required.

```python
from transformers import CLIPProcessor, CLIPModel
import torch

device     = "cuda" if torch.cuda.is_available() else "cpu"
clip_model = CLIPModel.from_pretrained("openai/clip-vit-large-patch14").to(device).eval()
clip_proc  = CLIPProcessor.from_pretrained("openai/clip-vit-large-patch14")

# Define category descriptions (natural language)
categories = [
    "a photograph of a protest or demonstration",
    "a photograph of a peaceful public gathering",
    "a photograph of police presence or riot control",
    "a photograph of a celebration or festival"
]

def zero_shot_classify(img_paths, categories, batch_size=32):
    text_inputs = clip_proc(text=categories, return_tensors="pt",
                             padding=True).to(device)
    with torch.no_grad():
        text_feats = clip_model.get_text_features(**text_inputs)
        text_feats = text_feats / text_feats.norm(dim=-1, keepdim=True)

    all_probs = []
    for i in range(0, len(img_paths), batch_size):
        imgs   = [PIL.Image.open(p).convert("RGB") for p in img_paths[i:i+batch_size]]
        inputs = clip_proc(images=imgs, return_tensors="pt").to(device)
        with torch.no_grad():
            img_feats = clip_model.get_image_features(**inputs)
            img_feats = img_feats / img_feats.norm(dim=-1, keepdim=True)
        logits = (100.0 * img_feats @ text_feats.T).softmax(dim=-1)
        all_probs.append(logits.cpu().numpy())

    return np.vstack(all_probs)   # shape: (N_images, N_categories)

probs = zero_shot_classify(img_paths, categories)
predicted = [categories[p] for p in probs.argmax(axis=1)]
```

**Required**: Validate on 200-image human-labeled sample; report Cohen's κ before using at scale.

---

### Step 5 — Fine-Tuning ConvNeXt / ViT (When You Have Labeled Data)

Use when N_labeled ≥ 500 images. ConvNeXt-Base is preferred for most social science tasks.

```python
import timm, torch, torch.nn as nn
from torch.optim import AdamW
from torch.optim.lr_scheduler import CosineAnnealingLR
from sklearn.metrics import classification_report

device = "cuda" if torch.cuda.is_available() else "cpu"

# Load pretrained ConvNeXt-Base
model = timm.create_model("convnext_base.fb_in22k_ft_in1k",
                           pretrained=True, num_classes=N_CLASSES)
model = model.to(device)

# Replace classification head (transfer learning)
# For ViT-B/16: model = timm.create_model("vit_base_patch16_224", pretrained=True, num_classes=N_CLASSES)

optimizer = AdamW(model.parameters(), lr=2e-5, weight_decay=0.01)
scheduler = CosineAnnealingLR(optimizer, T_max=NUM_EPOCHS)
criterion = nn.CrossEntropyLoss()

torch.manual_seed(42)
for epoch in range(NUM_EPOCHS):
    model.train()
    for imgs, labels, _ in train_loader:
        imgs, labels = imgs.to(device), labels.to(device)
        loss = criterion(model(imgs), labels)
        optimizer.zero_grad(); loss.backward(); optimizer.step()
    scheduler.step()

# Evaluate on test set
model.eval()
all_preds, all_labels = [], []
with torch.no_grad():
    for imgs, labels, _ in test_loader:
        preds = model(imgs.to(device)).argmax(dim=-1).cpu()
        all_preds.extend(preds.tolist())
        all_labels.extend(labels.tolist())

print(classification_report(all_labels, all_preds))
torch.save(model.state_dict(), "${OUTPUT_ROOT}/models/convnext-finetuned.pt")
```

---

### Step 6 — Multimodal LLM Annotation

When fine-tuning is impractical or semantic nuance requires reasoning. GPT-4o and Claude are preferred for complex social science coding tasks.

```python
import anthropic, base64, json

client = anthropic.Anthropic()

def encode_image_b64(path: str) -> str:
    with open(path, "rb") as f:
        return base64.standard_b64encode(f.read()).decode("utf-8")

VISION_SYSTEM = """You are a social science research assistant coding protest photographs.
For each image, code:
  - presence: 1 = protest/demonstration visible; 0 = not
  - crowd_size: "small" (<50), "medium" (50-500), "large" (>500)
  - police: 1 = police/security forces visible; 0 = not
  - violence: 1 = signs of violence or property destruction; 0 = not
Respond ONLY with JSON: {"presence":_, "crowd_size":"_", "police":_, "violence":_, "confidence":"high|medium|low"}"""

def annotate_image(img_path: str, model="claude-sonnet-4-6") -> dict:
    img_b64     = encode_image_b64(img_path)
    ext         = img_path.rsplit(".", 1)[-1].lower()
    media_types = {"jpg": "image/jpeg", "jpeg": "image/jpeg",
                   "png": "image/png", "gif": "image/gif", "webp": "image/webp"}
    msg = client.messages.create(
        model=model,
        max_tokens=200,
        temperature=0,
        system=VISION_SYSTEM,
        messages=[{
            "role": "user",
            "content": [{
                "type": "image",
                "source": {"type": "base64",
                           "media_type": media_types.get(ext, "image/jpeg"),
                           "data": img_b64}
            }, {"type": "text", "text": "Code this image:"}]
        }]
    )
    return json.loads(msg.content[0].text)

# Batch annotation
results = []
for path in img_paths:
    try:
        res = annotate_image(path)
        results.append({"path": path, **res})
    except Exception as e:
        results.append({"path": path, "error": str(e)})

import pandas as pd
pd.DataFrame(results).to_csv("${OUTPUT_ROOT}/tables/vision-annotations.csv", index=False)
```

**Required validation**: Human-code 200-image sample; compute κ per dimension ≥ 0.70.

---

### Step 7 — Video Analysis

**Frame sampling** (extract representative frames before running image models):

```python
import cv2, os

def extract_frames_uniform(video_path, n_frames=16, out_dir="${OUTPUT_ROOT}/frames"):
    os.makedirs(out_dir, exist_ok=True)
    cap     = cv2.VideoCapture(video_path)
    total   = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    indices = [int(i * total / n_frames) for i in range(n_frames)]
    paths   = []
    for idx in indices:
        cap.set(cv2.CAP_PROP_POS_FRAMES, idx)
        ret, frame = cap.read()
        if ret:
            path = os.path.join(out_dir, f"frame_{idx:06d}.jpg")
            cv2.imwrite(path, frame)
            paths.append(path)
    cap.release()
    return paths

def extract_frames_scene_change(video_path, threshold=30.0, out_dir="${OUTPUT_ROOT}/frames"):
    """Extract frames at scene boundaries using frame-diff heuristic."""
    os.makedirs(out_dir, exist_ok=True)
    cap  = cv2.VideoCapture(video_path)
    prev = None
    paths, idx = [], 0
    while True:
        ret, frame = cap.read()
        if not ret: break
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        if prev is not None:
            diff = cv2.absdiff(prev, gray).mean()
            if diff > threshold:
                path = os.path.join(out_dir, f"scene_{idx:06d}.jpg")
                cv2.imwrite(path, frame)
                paths.append(path)
        prev = gray; idx += 1
    cap.release()
    return paths
```

**VideoMAE for temporal features** (video understanding):

```python
from transformers import VideoMAEFeatureExtractor, VideoMAEModel
import torch, numpy as np

vmae_processor = VideoMAEFeatureExtractor.from_pretrained(
    "MCG-NJU/videomae-base")
vmae_model     = VideoMAEModel.from_pretrained(
    "MCG-NJU/videomae-base").to(device).eval()

def extract_video_features(frame_paths, n_frames=16):
    """Load N uniformly spaced frames; extract VideoMAE CLS token."""
    frames = [PIL.Image.open(p).convert("RGB") for p in frame_paths[:n_frames]]
    inputs = vmae_processor(frames, return_tensors="pt").to(device)
    with torch.no_grad():
        out = vmae_model(**inputs)
    return out.last_hidden_state[:, 0, :].cpu().numpy()  # (1, 768)
```

---

### Step 7b — Multimodal Fusion: Combining Text + Image Data

**When to use**: When your data has paired text and image modalities (e.g., social media posts with photos, news articles with images, product listings, dating profiles, protest documentation, housing ads with photos) and you want to leverage both for classification, clustering, or retrieval. Multimodal fusion captures information that neither modality alone provides.

| Fusion strategy | Description | When to use |
|----------------|-------------|-------------|
| **Late fusion** | Train separate unimodal models, combine predictions | Simple baseline; modalities are independently informative |
| **Early fusion** | Concatenate raw features before model | Features are low-dimensional; interaction effects expected |
| **Hybrid / joint embedding** | Map both modalities to shared space (CLIP) | Need cross-modal similarity; zero-shot capability |
| **Attention-based fusion** | Cross-attention between modality representations | Complex interaction patterns; sufficient labeled data |

**Installation:**

```bash
pip install transformers sentence-transformers open_clip_torch
```

**Option A — CLIP joint embeddings (zero-shot, no training required):**

```python
import torch, numpy as np, pandas as pd
from transformers import CLIPProcessor, CLIPModel
from PIL import Image

device     = "cuda" if torch.cuda.is_available() else "cpu"
clip_model = CLIPModel.from_pretrained("openai/clip-vit-large-patch14").to(device).eval()
clip_proc  = CLIPProcessor.from_pretrained("openai/clip-vit-large-patch14")

def extract_multimodal_features(texts, image_paths, batch_size=32):
    """Extract aligned text and image embeddings from CLIP."""
    text_embs, img_embs = [], []
    for i in range(0, len(texts), batch_size):
        batch_texts = texts[i:i+batch_size]
        batch_imgs  = [Image.open(p).convert("RGB") for p in image_paths[i:i+batch_size]]

        inputs = clip_proc(text=batch_texts, images=batch_imgs,
                           return_tensors="pt", padding=True,
                           truncation=True, max_length=77).to(device)
        with torch.no_grad():
            outputs = clip_model(**inputs)
            text_embs.append(outputs.text_embeds.cpu().numpy())
            img_embs.append(outputs.image_embeds.cpu().numpy())

    text_embs = np.vstack(text_embs)  # (N, 768)
    img_embs  = np.vstack(img_embs)   # (N, 768)
    return text_embs, img_embs

text_embs, img_embs = extract_multimodal_features(
    df["text"].tolist(), df["image_path"].tolist()
)

# Late fusion: concatenate normalized embeddings
from sklearn.preprocessing import normalize
text_norm = normalize(text_embs)
img_norm  = normalize(img_embs)
fused     = np.hstack([text_norm, img_norm])  # (N, 1536)

np.save("${OUTPUT_ROOT}/models/clip-text-embeddings.npy", text_embs)
np.save("${OUTPUT_ROOT}/models/clip-image-embeddings.npy", img_embs)
np.save("${OUTPUT_ROOT}/models/clip-fused-embeddings.npy", fused)
```

**Option B — Late fusion classifier (text model + image model + meta-learner):**

```python
from sklearn.linear_model import LogisticRegression
from sklearn.ensemble import GradientBoostingClassifier
from sklearn.model_selection import StratifiedKFold, cross_val_score
from sklearn.metrics import f1_score, classification_report
import joblib

# Assume: text_embs (N, d_text), img_embs (N, d_img), labels (N,)
# Option 1: Concatenate features, train single classifier
fused = np.hstack([text_embs, img_embs])  # early fusion on embeddings
clf_fused = GradientBoostingClassifier(n_estimators=200, max_depth=4,
                                        random_state=42)
cv = StratifiedKFold(n_splits=5, shuffle=True, random_state=42)
scores_fused = cross_val_score(clf_fused, fused, labels, cv=cv,
                                scoring="f1_macro")
print(f"Fused (text+image) F1: {scores_fused.mean():.3f} +/- {scores_fused.std():.3f}")

# Option 2: Late fusion — separate classifiers, combine probabilities
from sklearn.calibration import CalibratedClassifierCV
clf_text = CalibratedClassifierCV(
    GradientBoostingClassifier(n_estimators=200, random_state=42), cv=5)
clf_img  = CalibratedClassifierCV(
    GradientBoostingClassifier(n_estimators=200, random_state=42), cv=5)
clf_text.fit(text_embs[train_idx], labels[train_idx])
clf_img.fit(img_embs[train_idx], labels[train_idx])

# Average calibrated probabilities
prob_text = clf_text.predict_proba(text_embs[test_idx])
prob_img  = clf_img.predict_proba(img_embs[test_idx])
prob_late = 0.5 * prob_text + 0.5 * prob_img   # equal weighting; or tune weights
pred_late = prob_late.argmax(axis=1)
print(f"Late fusion F1: {f1_score(labels[test_idx], pred_late, average='macro'):.3f}")

# Compare: text-only, image-only, early fusion, late fusion
for name, X in [("Text only", text_embs), ("Image only", img_embs),
                ("Early fusion", fused)]:
    s = cross_val_score(GradientBoostingClassifier(n_estimators=200, random_state=42),
                        X, labels, cv=cv, scoring="f1_macro")
    print(f"{name} F1: {s.mean():.3f} +/- {s.std():.3f}")

joblib.dump(clf_fused, "${OUTPUT_ROOT}/models/multimodal-fused-clf.pkl")
```

**Option C — Cross-modal similarity for social media analysis:**

```python
# Use case: find text-image alignment / mismatch in social media posts
from sklearn.metrics.pairwise import cosine_similarity

# Per-post text-image alignment score
alignment_scores = np.array([
    cosine_similarity(text_embs[i:i+1], img_embs[i:i+1])[0, 0]
    for i in range(len(text_embs))
])
df["text_image_alignment"] = alignment_scores

# Low alignment = potential irony, sarcasm, misinformation, or mismatch
# Use as feature in downstream models or analyze directly
print(f"Mean alignment: {alignment_scores.mean():.3f}")
print(f"Low-alignment posts (< 0.2): {(alignment_scores < 0.2).sum()}")

df.to_csv("${OUTPUT_ROOT}/tables/multimodal-alignment.csv", index=False)
```

```r
# R alternative — use reticulate to call Python CLIP, then analyze in R
library(reticulate)
library(tidyverse)

# Load pre-computed embeddings from Python
text_embs <- as.matrix(read.csv("${OUTPUT_ROOT}/models/clip-text-embeddings.csv"))
img_embs  <- as.matrix(read.csv("${OUTPUT_ROOT}/models/clip-image-embeddings.csv"))

# Fuse and run classification in R
fused <- cbind(text_embs, img_embs)
library(caret)
set.seed(42)
ctrl <- trainControl(method="cv", number=5, classProbs=TRUE,
                     summaryFunction=multiClassSummary)
fit  <- train(x=fused, y=as.factor(labels),
              method="gbm", trControl=ctrl, metric="F1",
              verbose=FALSE)
print(fit$results)
```

**Validation approach:**
- Always compare multimodal vs. unimodal baselines (text-only, image-only)
- Report F1 (macro) for all modality combinations on the same held-out test set
- For late fusion, report calibration metrics (Brier score) to ensure probability combination is meaningful
- For cross-modal alignment, validate interpretation on a manual sample of high/low alignment posts

**Reporting template:**
> "We combine text and image modalities using [late / early / CLIP-based joint embedding] fusion. Text features are encoded with [CLIP text encoder / sentence-transformers / XLM-RoBERTa] ([d_text]-dimensional); image features with [CLIP image encoder / DINOv2] ([d_img]-dimensional). [For early fusion], we concatenate L2-normalized embeddings and train a gradient boosting classifier (5-fold CV). [For late fusion], we train separate calibrated classifiers per modality and average predicted probabilities. The multimodal model achieves F1 (macro) = [X], compared to text-only = [X] and image-only = [X] on the held-out test set (N = [X]). [For text-image alignment analysis], we compute per-post cosine similarity between CLIP text and image embeddings; posts with alignment < [threshold] are flagged as potential [irony / misinformation / mismatched] content. All models use seed = 42."

---

### Step 8 — CV Verification (Subagent)

```
CV VERIFICATION REPORT
=======================

DATA PREPARATION
[ ] Image preprocessing (resize, normalize) documented and matches pretrained model specs
[ ] Image resolution and format documented
[ ] Number of images, class distribution reported

METHOD ALIGNMENT
[ ] DINOv2 / CLIP / fine-tuned model choice justified vs. alternatives
[ ] Zero-shot: CLIP category descriptions validated on pilot set
[ ] Fine-tuning: N_labeled ≥ 500; train/val/test split documented

VALIDATION
[ ] Human-coded 200-image sample for benchmark
[ ] Cohen's κ ≥ 0.70 per coded dimension
[ ] Confusion matrix saved (for multi-class tasks)
[ ] LLM annotation: model name + date + temperature=0 documented

VIDEO (if used)
[ ] Frame sampling method documented (uniform or scene-change)
[ ] Number of frames per video reported
[ ] VideoMAE or image-level classification justified

MULTIMODAL FUSION (if used)
[ ] Fusion strategy documented (late / early / hybrid / CLIP joint embedding)
[ ] Both modality embeddings saved to output/[slug]/models/
[ ] Unimodal baselines reported (text-only F1, image-only F1)
[ ] Multimodal F1 reported and compared to unimodal baselines
[ ] For late fusion: calibrated classifiers used; probability weights documented
[ ] For text-image alignment: cosine similarity distribution analyzed
[ ] Ambiguous / mismatched cases manually inspected on sample

REPRODUCIBILITY
[ ] random seed reported (torch.manual_seed(42))
[ ] Model checkpoints saved to output/[slug]/models/
[ ] All annotation outputs saved as CSV

RESULT: [PASS / NEEDS REVISION]
Issues: [list]
```

---

