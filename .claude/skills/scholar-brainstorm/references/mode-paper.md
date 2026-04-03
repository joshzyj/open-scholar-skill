# Mode: PAPER — Step 0b

This file contains the PAPER mode workflow. After completing Step 0b, rejoin the main workflow at Step 5 (Literature Scan) in `shared-evaluation.md`.

---

### Step 0b: PAPER Mode Workflow (PAPER mode only — skip for DATA/MATERIALS)

If `OPERATING_MODE = PAPER`, execute this workflow instead of Steps 1-4. After Step 0b, rejoin the main workflow at Step 5 (Literature Scan).

**Step 0b-1 — Extract title and abstract:**

| Input type | Extraction method |
|-----------|-------------------|
| **PDF file** | `pdftotext "[PATH]" - | head -100` — extract title (first non-blank line) and abstract (text between "Abstract" and "Introduction") |
| **DOI** | Fetch via CrossRef: `curl -sL "https://api.crossref.org/works/[DOI]"` — extract title, abstract, authors, journal |
| **Pasted text** | Parse directly from `$ARGUMENTS` — identify title and abstract from formatting |

Store as `SEED_TITLE` and `SEED_ABSTRACT`.

**Step 0b-2 — Extract seed paper's key elements:**

Read the paper (or abstract) and extract:
1. **Core findings** — what did this paper discover?
2. **Methods used** — what analytical approach?
3. **Limitations acknowledged** — what did the authors say they couldn't do?
4. **Future directions stated** — what do the authors suggest as next steps?
5. **Theoretical framework** — what theory does it use or propose?
6. **Population/context** — who/where was studied?
7. **Data source** — what data was used?

**Step 0b-3 — SciThinker ideation (optional but recommended):**

Call `OpenMOSS-Team/SciThinker-30B` via the HuggingFace Inference API to generate follow-up research ideas:

```python
import os, json
from huggingface_hub import InferenceClient

HF_TOKEN = os.environ.get("HF_TOKEN", "")
client = InferenceClient("OpenMOSS-Team/SciThinker-30B", token=HF_TOKEN)

prompt = f"""You are a knowledgeable and insightful AI researcher. You have come across a new research paper with the following title and abstract:

Title: {SEED_TITLE}
Abstract: {SEED_ABSTRACT}

Based on the core ideas, methods, or findings of this work, engage in heuristic thinking and propose a follow-up research idea that is novel, specific, and actionable. Your proposed idea should:
1. Improve upon the original methods, OR
2. Apply the ideas to a new domain or population, OR
3. Address a limitation explicitly mentioned in the paper, OR
4. Propose an entirely new problem inspired by the findings.

Output format:
Title: <your proposed paper title>
Abstract: <your proposed abstract>"""

response = client.text_generation(
    prompt,
    max_new_tokens=4096,
    temperature=0.6,
    top_p=0.95,
    do_sample=True
)
print(response)
```

**If HF_TOKEN is not set or the API call fails:** Skip SciThinker and proceed with Claude-only ideation in Step 0b-4. Log: "SciThinker: SKIPPED — [reason]".

**If SciThinker succeeds:** Parse the response to extract proposed title(s) and abstract(s). These become **seed ideas** for Step 0b-4.

**Step 0b-4 — Claude expansion (generate 15-20 follow-up RQ candidates):**

Using the seed paper's elements (Step 0b-2) and SciThinker's proposals (Step 0b-3, if available), generate 15-20 candidate follow-up research questions across these dimensions:

| Dimension | Strategy | Example |
|-----------|----------|---------|
| **Methodological extension** | Apply a stronger/different method to the same question | "What if we used DiD instead of OLS?" |
| **Population transfer** | Same question, different population or context | "Does this hold in [country/group/era]?" |
| **Mechanism deepening** | Test the proposed mechanism directly | "Through what mechanism does X affect Y?" |
| **Limitation addressal** | Directly tackle an acknowledged limitation | "What if we had longitudinal data instead of cross-sectional?" |
| **Scope expansion** | Broaden the scope to a related phenomenon | "Does this theory also explain [adjacent phenomenon]?" |
| **Contradictory test** | Design a study that could falsify the finding | "Under what conditions would the opposite hold?" |
| **Computational upgrade** | Apply computational methods to the same domain | "Can NLP/ML reveal patterns the original method missed?" |
| **SciThinker proposals** | Refine and ground SciThinker's AI-generated ideas in social science theory | "SciThinker proposed X — how does this connect to [theory]?" |

For each candidate RQ, specify:
- The research question (1-2 sentences)
- The connection to the seed paper (which element it extends)
- A plausible theoretical framework
- A feasible data source
- The target journal

**After Step 0b-4, proceed directly to Step 5** (Literature Scan) with the 15-20 candidates, then Step 6 (Shortlist to Top 10), Step 7 (Multi-Agent Evaluation), and Step 8 (Final Ranking). The PAPER mode uses 5-criterion scoring (same as MATERIALS mode — no empirical signal tests).
