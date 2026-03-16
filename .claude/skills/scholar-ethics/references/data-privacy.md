# Data Privacy & AI Tool Use in Research

Reference guide for `scholar-ethics` MODE 1.

---

## 1. AI Tool Privacy Risk by Provider

| Tool | Provider | Data retention policy | GDPR DPA available | BAA available | Recommended for sensitive data? |
|------|----------|----------------------|-------------------|---------------|-------------------------------|
| Claude (API) | Anthropic | No training on API data by default; 30-day retention | Contact enterprise | Contact enterprise | Low-sensitivity OK; not HIPAA by default |
| Claude Code | Anthropic | Same as Claude API | Same | Same | Code + variable names OK; not full datasets |
| ChatGPT (web) | OpenAI | May use for training (unless opted out) | Available (EU) | Available (Healthcare plan) | Avoid research data |
| ChatGPT (API) | OpenAI | No training on API data | Available | BAA available | Low-sensitivity OK with enterprise |
| GitHub Copilot | Microsoft | Code snippets retained; training opt-out available | Available | Available (enterprise) | Code only; do not include data values in code |
| Gemini (web) | Google | Activity stored; training uses content | Available | Google Workspace BAA | Avoid research data in web version |
| Gemini API | Google | No training on API data by default | Available | Available (workspace) | Low-sensitivity OK |
| Llama (local) | Meta / self-hosted | No external transmission | N/A — fully local | N/A | Suitable for all sensitivity levels |
| Ollama (local) | Community / self-hosted | No external transmission | N/A | N/A | Best option for sensitive data |

**Key rule:** When in doubt, use a local model (Ollama + Llama/Mistral) for any data containing personal identifiers, restricted variables, or IRB-protected information.

---

## 2. Data Categories and AI Tool Compatibility

| Data type | AI tool use | Notes |
|-----------|------------|-------|
| Code structure only (function names, logic) | ✓ Safe | No data values transmitted |
| Variable names and column headers | ✓ Safe | Does not constitute personal data |
| Aggregate statistics (means, SDs, counts) | ✓ Safe | Not re-identifiable |
| De-identified survey responses (sample rows) | ⚠ Review | Verify IRB consent covers third-party processing |
| Qualitative excerpts from published sources | ✓ Safe | Already public |
| Manuscript text (theory, methods, discussion) | ✓ Generally safe | Disclose AI writing assistance |
| Interview transcripts with pseudonyms | ⚠ Medium risk | Pseudonyms may still be re-identifiable; use local LLM |
| Full dataset with de-identified IDs | ⚠ Medium risk | Check DUA; prefer local tools |
| Datasets with PII (names, SSN, DOB, address) | ✗ Do not share | GDPR / HIPAA violation risk |
| Restricted licensed data (NHANES linked, PSID geocode) | ✗ Prohibited | DUA explicitly forbids third-party sharing |
| Health / clinical records | ✗ Prohibited | HIPAA: no BAA = violation |
| Immigration status, legal status variables | ✗ Do not share | Severe participant harm risk |

---

## 3. Regulatory Frameworks

### GDPR (General Data Protection Regulation — EU/EEA)
- **Applies when**: any EU/EEA resident participant, even if researcher is US-based
- **Key principles**: purpose limitation, data minimization, storage limitation, security
- **AI tool use**: cloud AI API = **data processor** → requires Data Processing Agreement (DPA)
- **Lawful basis for research**: Article 89(1) allows research processing with appropriate safeguards
- **Pseudonymization** is required where possible; anonymization removes GDPR applicability
- **Action**: If sharing any EU participant data with cloud AI, sign DPA with provider first

### HIPAA (Health Insurance Portability and Accountability Act — US)
- **Applies when**: health information linked to individuals, collected/held by covered entities or their business associates
- **18 HIPAA identifiers**: name, address, dates (except year), phone, fax, email, SSN, medical record #, health plan #, account #, certificate #, vehicle ID, device ID, web URL, IP address, biometric identifiers, photos, other unique identifiers
- **Safe Harbor de-identification**: remove all 18 identifiers → no longer PHI
- **AI tools**: commercial cloud AI is NOT a covered entity → Business Associate Agreement (BAA) required to share PHI
- **Action**: Never paste HIPAA-covered data into any cloud AI without a BAA

### FERPA (Family Educational Rights and Privacy Act — US)
- **Applies when**: student education records at institutions receiving federal funds
- **Key rule**: do not share individually identifiable education records with third-party AI without consent
- **De-identified data** (no direct or indirect identifiers) is OK

### Data Use Agreements (DUAs)
Common restricted datasets and their AI sharing restrictions:

| Dataset | Key DUA restriction |
|---------|-------------------|
| NHANES (CDC) | "Not to transfer data to any other person" — cloud AI likely prohibited |
| PSID | "Restricted use" files: cannot share outside approved project team |
| NLSY (BLS) | Geocode/restricted supplement: explicit prohibition on third-party access |
| IPUMS restricted extracts | Cannot distribute or share with unauthorized parties |
| ANES / GSS | Public-use files: generally OK; restricted geocode files: DUA applies |
| Census restricted (RDC) | Strict: no external transmission of any analysis inputs |
| Administrative records (Medicaid, tax, court) | Specific DUA terms vary; typically prohibit any third-party sharing |

---

## 4. IRB Consent Language for AI Tool Use

If your study involves collecting data that may later be processed by AI tools, ensure your consent form covers this.

**Consent language to add for AI-assisted analysis:**

> Your de-identified responses may be processed using secure computational tools, including AI-assisted analysis software, to assist with data interpretation. No personally identifying information will be shared with third-party AI services. All data shared with computational tools will be de-identified and used solely for research purposes.

**If using cloud AI for text analysis of participant data:**

> Text data you provide may be processed through [tool name] for automated analysis. [Provider name] processes data under [applicable privacy framework, e.g., GDPR DPA / institutional agreement]. No data will be used to train AI systems without separate consent.

---

## 5. Local vs. Cloud AI: Decision Guide

| Use case | Recommended tool type | Rationale |
|----------|----------------------|-----------|
| Code generation (no data in prompts) | Cloud or local | Safe; no data transmitted |
| Writing assistance (manuscript text) | Cloud or local | Manuscript text generally OK; disclose usage |
| Analyzing de-identified survey rows | Local (Ollama) preferred | Avoids DPA/consent questions |
| LLM annotation of interview transcripts | Local mandatory | Transcripts are sensitive |
| Analysis of restricted licensed data | Local mandatory | DUA prohibits third-party sharing |
| Semantic search over de-identified corpus | Cloud OK with audit | Verify DUA; use batch API not web UI |

**Setting up Ollama for local AI use:**
```bash
# Install Ollama
curl https://ollama.ai/install.sh | sh

# Pull a model (runs fully locally — no internet after download)
ollama pull llama3.2
ollama pull mistral

# Run model — stays entirely on your machine
ollama run llama3.2
```

**Python API call (local, no data leaves your machine):**
```python
import ollama
response = ollama.chat(
    model="llama3.2",
    messages=[{"role": "user", "content": "Analyze this text: " + your_text}]
)
print(response["message"]["content"])
```

---

## 6. AI Use Logging Template

Keep a log during the project:

```
AI TOOL USE LOG — [Project Name]
PI: [Name]
IRB Protocol: [Number]

Date       | Tool       | Task                          | Data type shared          | Risk level
-----------|------------|-------------------------------|---------------------------|-----------
2025-01-15 | Claude Code| Generate cleaning script       | Variable names only       | Low
2025-02-10 | ChatGPT    | Edit discussion paragraph      | Manuscript text (no data) | Low
2025-03-01 | Ollama     | Annotate interview transcripts | De-identified transcripts | Local — safe
```

This log supports journal disclosure requirements and IRB documentation.
