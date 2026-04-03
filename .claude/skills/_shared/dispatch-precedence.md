# NLP / Text-as-Data Dispatch Precedence

When a user's request matches keywords in both `scholar-compute` (MODULE 1) and `scholar-ling` (MODULEs 5-6), use this decision table to route correctly.

## Decision Rule

| User's Goal | Route to | Rationale |
|-------------|----------|-----------|
| **Predict outcomes** from text (classification, ML, supervised learning) | `scholar-compute` MODULE 1/2 | Prediction-focused; computational social science |
| **Estimate causal/associational effects** using text features (embedding regression, text controls) | `scholar-compute` MODULE 1 (conText, DSL) | Causal inference focus |
| **Discover latent topics** in political/social corpus (STM, BERTopic) | `scholar-compute` MODULE 1 | General topic modeling for social science |
| **Annotate text** with LLM for downstream quantitative analysis | `scholar-compute` MODULE 1 (Step 5) | Annotation is a measurement step for quant analysis |
| **Analyze linguistic variation** (phonological, morphosyntactic, lexical) | `scholar-ling` MODULE 2 | Core sociolinguistics |
| **Study language attitudes or ideologies** | `scholar-ling` MODULE 4 | Matched guise, language evaluation |
| **Analyze conversation/interaction** (CA, IS, turn-taking, repair) | `scholar-ling` MODULE 3 | Qualitative/interactional linguistics |
| **Study language change or contact** (code-switching, heritage languages) | `scholar-ling` MODULE 1 + 2 | Sociolinguistic theory-driven |
| **Corpus linguistics** with focus on **linguistic features** (keyness, collocations, CDA, narrative) | `scholar-ling` MODULE 5 | Linguistics-focused discourse/corpus |
| **Computational sociolinguistics** (embedding regression for *linguistic* variables, LLM annotation for *linguistic* coding, semantic change of *linguistic* forms) | `scholar-ling` MODULE 6 | Same tools as compute MODULE 1 but framed through sociolinguistic theory |
| **Biber MDA** (multi-dimensional analysis, register comparison) | `scholar-ling` MODULE 8 | Specialized linguistics method |
| **Network analysis** of any kind | `scholar-compute` MODULE 3 | Always compute |
| **Agent-based modeling** | `scholar-compute` MODULE 4 | Always compute |
| **Computer vision** | `scholar-compute` MODULE 6 | Always compute |
| **Geospatial analysis** | `scholar-compute` MODULE 9 | Always compute |
| **Audio/speech as data** (acoustic features, transcription, classification) | `scholar-compute` MODULE 10 | Always compute (even for speech data) |

## Shared Keywords — Disambiguation

| Keyword | Default Route | Override Condition |
|---------|---------------|-------------------|
| `corpus` | `scholar-ling` MODULE 5 | Unless user says "topic model" or "classify" → `scholar-compute` MODULE 1 |
| `STM` / `topic` | `scholar-compute` MODULE 1 | Unless user says "discourse" or "register" → `scholar-ling` MODULE 5 |
| `embedding` / `conText` | `scholar-compute` MODULE 1 | Unless user specifies a *linguistic variable* (e.g., "embedding regression on /t/-deletion") → `scholar-ling` MODULE 6 |
| `BERT` / `transformer` | `scholar-compute` MODULE 1 | Unless user says "linguistic coding" or "sociolinguistic classification" → `scholar-ling` MODULE 6 |
| `LLM annotation` | `scholar-compute` MODULE 1 | Unless user says "linguistic coding" or "phonological annotation" → `scholar-ling` MODULE 6 |
| `semantic change` | `scholar-compute` MODULE 1 | Unless user says "diachronic sociolinguistics" or "language change" → `scholar-ling` MODULE 6 |

## Shortcut

If the user's target journal is **Language in Society**, **J. Sociolinguistics**, **Language**, or **Applied Linguistics** → prefer `scholar-ling`.

If the user's target journal is **NCS**, **Science Advances**, **PNAS**, **Sociological Methods & Research**, or **Poetics** → prefer `scholar-compute`.

If still ambiguous, ask the user: "Your request could use either computational social science tools (scholar-compute) or sociolinguistic tools (scholar-ling). Which framing fits your paper better?"
