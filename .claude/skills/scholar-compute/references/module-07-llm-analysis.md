## MODULE 7: LLM-Powered Analysis Workflows

### Step 1 — Goal and Risk Assessment

Before designing the LLM pipeline, classify the workflow type and apply corresponding safeguards:

| Workflow type | Goal | Key risk | Safeguard |
|--------------|------|----------|-----------|
| **Structured extraction** | Pull named entities, dates, amounts from documents | Hallucination of non-existent values | Schema validation + spot-check 10% |
| **Multi-step coding** | Assign substantive codes to text (theory-driven) | Validity drift; confidential leakage | κ ≥ 0.70 vs. humans; few-shot anchors |
| **Computational grounded theory** | Inductive category discovery | Premature closure; category proliferation | 3-iteration loop; researcher review each cycle |
| **Document QA / RAG** | Answer questions about a document corpus | Retrieval failures; fabricated citations | Always cite retrieved passage; human audit |

Apply all four Lin & Zhang (2025) epistemic risk checks (from MODULE 1 Step 7) before full deployment: validity, reliability, replicability, transparency.

---

### Step 2 — Structured Extraction (Pydantic + Claude)

```python
from anthropic import Anthropic
from pydantic import BaseModel, Field
from typing import Optional
import json

client = Anthropic()

class PolicyEvent(BaseModel):
    date:            Optional[str]   = Field(description="Date of policy event (YYYY-MM-DD)")
    jurisdiction:    Optional[str]   = Field(description="Jurisdiction (state, city, country)")
    policy_type:     Optional[str]   = Field(description="Type of policy (housing, immigration, labor, etc.)")
    direction:       Optional[str]   = Field(description="'restrictive' or 'permissive'")
    affected_group:  Optional[str]   = Field(description="Primary affected group if mentioned")
    confidence:      str             = Field(description="'high', 'medium', or 'low'")

EXTRACT_SYSTEM = f"""Extract structured information about policy events from news articles.
If a field cannot be determined from the text, return null for that field.
Return ONLY a JSON object matching this schema:
{PolicyEvent.schema_json(indent=2)}"""

def extract_event(text: str) -> PolicyEvent:
    msg = client.messages.create(
        model="claude-sonnet-4-6",
        max_tokens=300,
        temperature=0,
        system=EXTRACT_SYSTEM,
        messages=[{"role": "user",
                   "content": f"Article:\n{text[:3000]}"}]
    )
    raw  = json.loads(msg.content[0].text)
    return PolicyEvent(**raw)

# Batch extraction with schema validation
records = []
errors  = []
for _, row in df.iterrows():
    try:
        event = extract_event(row["text"])
        records.append({"doc_id": row["id"], **event.dict()})
    except Exception as e:
        errors.append({"doc_id": row["id"], "error": str(e)})

import pandas as pd
pd.DataFrame(records).to_csv("${OUTPUT_ROOT}/tables/policy-events-extracted.csv", index=False)
print(f"Extracted: {len(records)} / Errors: {len(errors)}")
```

---

### Step 3 — Chain-of-Thought Multi-Step Coding

For theoretically nuanced coding tasks, use step-by-step reasoning before assigning the final code. This improves validity (Lin & Zhang 2025) by making the inference process auditable.

```python
COT_SYSTEM = """You are a sociologist coding newspaper articles about immigration using schema theory.
Follow these steps before assigning a frame code:
STEP 1: Identify the main subject of the article.
STEP 2: Note the most prominent metaphors or analogies used.
STEP 3: Identify the primary causal attribution (who/what is responsible?).
STEP 4: Based on steps 1-3, assign a frame code:
  - ECONOMIC: immigration framed primarily in terms of labor, economy, costs/benefits
  - SECURITY: immigration framed primarily in terms of crime, border security, national safety
  - HUMANITARIAN: immigration framed primarily in terms of human rights, family, asylum
  - CULTURAL: immigration framed primarily in terms of identity, values, national character
  - OTHER: does not fit cleanly into above categories
Respond with JSON: {"step1":"...", "step2":"...", "step3":"...", "frame":"ECONOMIC|SECURITY|HUMANITARIAN|CULTURAL|OTHER", "confidence":"high|medium|low"}"""

def code_frame_cot(text: str) -> dict:
    msg = client.messages.create(
        model="claude-sonnet-4-6",
        max_tokens=400,
        temperature=0,
        system=COT_SYSTEM,
        messages=[{"role": "user", "content": f"Article:\n{text[:3000]}"}]
    )
    return json.loads(msg.content[0].text)
```

---

### Step 4 — Computational Grounded Theory Loop

Nelson (2020, *Sociological Methods & Research*) proposes an iterative cycle: unsupervised induction → manual interpretation → supervised deduction.

```python
# CYCLE 1: Inductive discovery via STM or k-means on embeddings
# (Run Step 3 or Step 6 from MODULE 1 to get initial topics/clusters)

# CYCLE 2: Researcher reviews top documents per cluster;
#           defines theoretically-grounded categories

categories_cycle2 = {
    "displacement_threat": "Articles framing immigrants as displacing native workers",
    "cultural_dilution":   "Articles framing immigration as threatening cultural values",
    "humanitarian_appeal": "Articles emphasizing suffering, rights, and asylum needs",
    "economic_benefit":    "Articles emphasizing immigrants' economic contributions"
}

# CYCLE 3: LLM assigns documents to researcher-defined categories (deductive)
DEDUCTIVE_SYSTEM = (
    "You are coding news articles into one of these categories defined by a sociologist:\n"
    + "\n".join(f"- {k}: {v}" for k, v in categories_cycle2.items())
    + "\nRespond ONLY with JSON: {\"category\": \"category_name\", \"confidence\": \"high|medium|low\"}"
)

def classify_grounded(text: str) -> dict:
    msg = client.messages.create(
        model="claude-sonnet-4-6",
        max_tokens=100,
        temperature=0,
        system=DEDUCTIVE_SYSTEM,
        messages=[{"role": "user", "content": f"Article:\n{text[:2000]}"}]
    )
    return json.loads(msg.content[0].text)

# Validate Cycle 3 against human codes (κ ≥ 0.70 required)
```

**Reporting template:**
> "Following Nelson's (2020) computational grounded theory approach, we proceeded in three cycles. In Cycle 1, we applied Structural Topic Modeling (K = [X]) to inductively identify latent themes in the corpus. In Cycle 2, two authors reviewed the top [N] documents per topic and developed a [K]-category coding scheme. In Cycle 3, we used [Claude Sonnet 4.6] to classify all [N] documents into this scheme (agreement with human codes on 200-document sample: κ = [X]). All prompts and a random sample of LLM reasoning chains are reproduced in the Online Appendix."

---

### Step 5 — RAG / Document QA with FAISS

For large document collections where you need to answer specific questions or retrieve relevant passages:

```python
from sentence_transformers import SentenceTransformer
import faiss, numpy as np

# Build vector index
embedder = SentenceTransformer("all-mpnet-base-v2")   # 768-dim embeddings

def build_index(texts: list[str], chunk_size: int = 500) -> tuple:
    """Chunk documents and build FAISS index."""
    chunks, chunk_ids = [], []
    for doc_id, text in enumerate(texts):
        words  = text.split()
        for i in range(0, len(words), chunk_size):
            chunks.append(" ".join(words[i:i+chunk_size]))
            chunk_ids.append(doc_id)

    embeddings = embedder.encode(chunks, show_progress_bar=True,
                                 batch_size=64, normalize_embeddings=True)
    index = faiss.IndexFlatIP(embeddings.shape[1])   # inner product = cosine for L2-normalized
    index.add(embeddings.astype("float32"))
    return index, chunks, chunk_ids

def query(question: str, index, chunks, top_k=5) -> list[str]:
    q_emb = embedder.encode([question], normalize_embeddings=True).astype("float32")
    _, ids = index.search(q_emb, top_k)
    return [chunks[i] for i in ids[0]]

def answer_with_rag(question: str, context_chunks: list[str]) -> str:
    context = "\n\n---\n\n".join(context_chunks)
    msg = client.messages.create(
        model="claude-sonnet-4-6",
        max_tokens=500,
        temperature=0,
        system="You are a research assistant. Answer the question based ONLY on the provided passages. If the answer is not in the passages, say 'Not found in corpus.'",
        messages=[{"role": "user",
                   "content": f"Passages:\n{context}\n\nQuestion: {question}"}]
    )
    return msg.content[0].text

# Example usage
index, chunks, chunk_ids = build_index(df["text"].tolist())
context   = query("What are the main arguments for restrictive immigration policy?", index, chunks)
answer    = answer_with_rag("What are the main arguments for restrictive immigration policy?", context)
print(answer)
```

---

### Step 6 — LLM Analysis Reproducibility

```python
import hashlib, json, datetime

def reproducible_prompt_call(system: str, user_msg: str,
                              model="claude-sonnet-4-6") -> dict:
    """Wrapper that records prompt hash, model, date for replicability."""
    prompt_hash = hashlib.sha256(
        (system + user_msg).encode()).hexdigest()[:12]
    result = client.messages.create(
        model=model,
        max_tokens=500,
        temperature=0,   # REQUIRED for replicability
        system=system,
        messages=[{"role": "user", "content": user_msg}]
    )
    return {
        "response":     result.content[0].text,
        "model":        model,
        "date":         datetime.date.today().isoformat(),
        "prompt_hash":  prompt_hash,
        "input_tokens": result.usage.input_tokens,
        "output_tokens":result.usage.output_tokens
    }
```

**Reproducibility checklist for LLM analysis:**
- temperature = 0 for all production annotation calls
- Exact model ID (including version suffix) archived
- Annotation date recorded (model behavior can change across releases)
- Full system + user prompts archived verbatim
- Raw LLM outputs saved alongside derived codes

---

### Step 7 — LLM Analysis Verification (Subagent)

```
LLM ANALYSIS VERIFICATION REPORT
==================================

RISK ASSESSMENT (Lin & Zhang 2025)
[ ] Validity: LLM coding of intended construct confirmed via pilot + rationale review
[ ] Reliability: run-to-run κ on 50-doc subsample reported; temperature=0 used
[ ] Replicability: model name + version + date + prompts archived
[ ] Transparency: prompts reproduced in supplementary; limitations discussed

STRUCTURED EXTRACTION (if used)
[ ] Pydantic schema documented and reproduced
[ ] Error rate (extraction failures / schema violations) reported
[ ] 10% spot-check against source documents conducted

CHAIN-OF-THOUGHT CODING (if used)
[ ] Reasoning steps documented in prompt
[ ] Sample CoT chains included in supplementary

GROUNDED THEORY (if used)
[ ] All 3 cycles documented (inductive → interpretive → deductive)
[ ] Category definitions reproduced verbatim
[ ] κ from Cycle 3 deductive coding ≥ 0.70

RAG / DOCUMENT QA (if used)
[ ] Chunk size and embedding model documented
[ ] Retrieval quality assessed (sample queries spot-checked)
[ ] Answers grounded in retrieved passages (no hallucinated citations)

COST
[ ] Total token usage and estimated cost reported
[ ] Cost included in Methods or budget note

RESULT: [PASS / NEEDS REVISION]
Issues: [list]
```

---

