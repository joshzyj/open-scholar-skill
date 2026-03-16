# Safe-Mode Protocols for AI-Assisted Research

Reference for `scholar-safety` — concrete protocols for each risk level and data type combination.

---

## 1. The Core Problem: What Gets Transmitted to AI Servers

When you use Claude Code (or any cloud AI tool), the following are transmitted to the provider's servers:

| Claude Code Action | Data transmitted |
|-------------------|-----------------|
| `Read` tool on a file | **Complete file contents** |
| `Bash cat file.csv` | **Complete file contents** |
| `Bash head -20 file.csv` | First 20 rows |
| `Bash grep -c pattern file.csv` | **Only the integer count** — safe ✓ |
| `Bash Rscript -e "summary(read.csv('file.csv'))"` | Only the summary output |
| `Bash awk '{print NR}' file.csv` | Only line count — safe ✓ |
| Pasting data inline in chat | All pasted content |

**Key insight:** Run local operations that return AGGREGATED outputs (counts, summaries, model coefficients) rather than raw file contents. The raw data stays local; only results go to Claude.

---

## 2. Protocol by Risk Level

### 🔴 HIGH RISK — Protocol H

**Trigger:** SSN, PHI, health data, immigration status, criminal records, restricted licensed data detected.

**Required steps before any Claude Code operation:**

1. **Do not Read the file into context.** Stop immediately.
2. **Determine the necessary operation:** What does the research actually need from this file?
3. **Choose one of four paths:**

| Path | When to use | What to do |
|------|------------|-----------|
| **H-1: Anonymize first** | PII present but data is your own | Run anonymization script; re-scan anonymized file before proceeding |
| **H-2: Extract-only (local Bash)** | Restricted licensed data (NHANES restricted, PSID, Census RDC) | Write Bash/R scripts that output only aggregated results; paste only those results |
| **H-3: Local LLM** | Interview transcripts; qualitative data with PII | Use Ollama/llama3 locally; no data leaves your machine |
| **H-4: Halt and remediate** | Consent/DUA prohibits ANY AI processing | Stop; resolve compliance first; contact IRB/data source |

**H-2 Extract-only protocol (detailed):**

The researcher runs R/Python/Stata locally and shares ONLY the output:

```r
# Step 1: Load data locally — does NOT go to Claude
data <- haven::read_dta("restricted_data.dta")

# Step 2: Produce ONLY the outputs Claude needs
# 2a. Descriptive statistics (no individual rows)
table1 <- data |>
  group_by(race, gender) |>
  summarise(
    n = n(),
    mean_income = mean(income, na.rm = TRUE),
    sd_income   = sd(income, na.rm = TRUE),
    .groups = "drop"
  )
print(table1)   # ← share THIS with Claude

# 2b. Regression coefficients (no individual predictions)
fit <- feols(outcome ~ treatment + age + education | state + year,
             data = data, cluster = ~state)
modelsummary::msummary(fit)   # ← share THIS with Claude

# 2c. Frequency distributions (aggregated)
prop.table(table(data$education_level))  # ← share THIS with Claude
```

The researcher pastes the PRINTED OUTPUT into the Claude conversation — not the file. Claude never sees individual records.

---

### 🟡 MEDIUM RISK — Protocol M

**Trigger:** IRB participant markers, de-identified data with quasi-identifiers, email addresses (low count), fine-grained geography.

**Required steps:**

1. **Verify IRB consent covers cloud AI processing.** Check your consent form or IRB protocol.
2. **Verify DUA (if any) permits third-party processing.**
3. **If both are OK → proceed with note in AI use log.**
4. **If unclear → use H-2 extract-only or anonymize.**

**M-1: De-identification check before proceeding**

```r
# Quick de-identification verification
data <- read_csv("data.csv")

# Check for remaining direct identifiers
id_cols <- names(data)[grepl(
  "name|email|phone|address|ssn|dob|birth|id_number",
  names(data), ignore.case = TRUE
)]
cat("Potential identifier columns:", paste(id_cols, collapse = ", "), "\n")
cat("Total rows:", nrow(data), "\n")
cat("Minimum quasi-identifier combo size (k-anonymity check):\n")

# k-anonymity check: smallest group when cross-tabbing quasi-identifiers
if (length(id_cols) == 0) {
  quasi_ids <- c("age", "race", "zip", "education")  # adjust as needed
  quasi_present <- intersect(quasi_ids, names(data))
  if (length(quasi_present) > 0) {
    k <- data |>
      group_by(across(all_of(quasi_present))) |>
      summarise(n = n()) |>
      pull(n) |>
      min()
    cat("Minimum group size (k-anonymity):", k, "\n")
    cat("Threshold: k >= 5 is generally safe\n")
  }
}
```

**M-2: Geographic generalization before proceeding**

```r
# Generalize fine-grained geography before sharing with Claude
data <- data |>
  mutate(
    # Census tract → county FIPS (drop last 6 digits)
    county_fips = substr(census_tract, 1, 5),
    # Exact coordinates → region (rough)
    lat_approx = round(latitude, 1),
    lon_approx = round(longitude, 1)
  ) |>
  select(-census_tract, -latitude, -longitude)
```

---

### 🟢 LOW RISK — Protocol L

**Trigger:** No sensitive patterns; public datasets; code files only; manuscript text.

**Action:** Log green light. Proceed normally. No special protocol required.

**L-1: Suggested log entry**

```
[GREEN] File: [name] | Operation: [describe] | Risk: LOW | [timestamp]
No sensitive patterns detected. Proceeding with standard Claude Code workflow.
```

---

## 3. Data Type-Specific Protocols

### Protocol for Survey Data

| Survey type | Risk level | Protocol |
|-------------|-----------|---------|
| Fully anonymous (no ID, no identifiers) | LOW | Standard proceed |
| Pseudonymous (P001, P002...) | MEDIUM | Verify anonymization is complete |
| Named respondents | HIGH | Anonymize before Claude sees any data |
| Sensitive topics (health, immigration, criminal) | HIGH | Extract-only (H-2) or local LLM |
| Linked to administrative records | HIGH | Extract-only (H-2) always |

**Recommended survey sharing approach:**
Share only `summary(data)` or `skimr::skim(data)` output — never raw rows.

```r
library(skimr)
skim_result <- skim(data)
print(skim_result)  # Share this output — no individual records
```

### Protocol for Interview / Qualitative Data

Interview transcripts are among the highest-risk data types. Participants may discuss sensitive topics in their own words; direct quotes are identifiable even without names.

**Protocol Q-1: Never share raw transcripts with cloud AI**

Instead, use one of:

1. **Local LLM annotation** (Ollama + llama3):
```bash
# Install and run locally — no internet connection needed
ollama serve &
ollama run llama3.2 "Code this transcript excerpt for themes of X: [paste excerpt]"
```

2. **Pre-coded excerpts only**: human-code the transcripts first; share only the codes (not the text) with Claude.

3. **Aggregated themes**: share theme frequency tables, not quotes.

4. **Redacted excerpts**: manually remove all identifying information from specific short excerpts before sharing.

**Protocol Q-2: If AI text analysis is required**
- Use Anthropic API with a DPA in place (for EU data) or verify institutional data use agreement
- Verify IRB consent covers AI text processing
- Use `temperature=0` for reproducibility
- Archive the exact prompt, model version, and date
- Do not request analysis that could re-identify (e.g., "who said X" queries)

### Protocol for Restricted Licensed Data (NHANES restricted, PSID, Census RDC, NLSY)

These datasets are subject to DUAs that explicitly prohibit sharing with third parties. Cloud AI APIs are third parties. **No raw data from these files may be transmitted to any cloud AI service.**

**Protocol R-1: Script-in, results-out**

```r
# ALL data operations run locally via R/Python/Stata
# Share ONLY final outputs with Claude

# Pattern 1: Share regression table
fit <- feols(health_outcome ~ residential_stability + i(year) | state,
             data = nhanes_restricted, cluster = ~psu)
etable(fit)  # ← paste this output to Claude

# Pattern 2: Share descriptive table
gtsummary::tbl_summary(
  data |> select(outcome, key_vars),
  by = race
) |> as_gt() |> as.character()  # ← paste output to Claude

# Pattern 3: Share figure (saved as PNG; no raw data in the image)
ggplot(data, aes(x = year, y = mean_outcome, color = race)) +
  geom_line() +
  ggsave("output/[slug]/fig_trend.png", width = 8, height = 5)
# Tell Claude: "I've generated fig_trend.png. Describe it to me as [description]."
# Or: open the PNG yourself and describe what you see, then ask Claude for prose
```

**Protocol R-2: What to tell Claude about restricted data**

```
"I have a restricted-use dataset [name the dataset]. I cannot share raw data
with cloud AI services per my data use agreement. I will share only
aggregated outputs. Please work with what I provide."
```

Then share: N by group, means/SDs, regression coefficients with SEs, figures.

### Protocol for Health Data (HIPAA)

If your data contains PHI (protected health information):

1. **No cloud AI processing without a BAA.** Check whether your institution has a BAA with Anthropic or OpenAI. Most do not as of 2025.
2. **Obtain a BAA** before any cloud AI work with PHI.
3. **Use de-identification** (Safe Harbor or Expert Determination) before cloud AI processing.
4. **Local LLM** (Ollama) for any text analysis of clinical notes.

**Safe Harbor de-identification checklist (45 CFR §164.514):**
Remove all 18 identifiers:
- [ ] Names
- [ ] Geographic data (smaller than state, except age/year)
- [ ] Dates (except year) — including admission/discharge dates, DOB, date of death
- [ ] Phone numbers
- [ ] Fax numbers
- [ ] Email addresses
- [ ] SSNs
- [ ] Medical record numbers
- [ ] Health plan beneficiary numbers
- [ ] Account numbers
- [ ] Certificate/license numbers
- [ ] Vehicle identifiers / serial numbers
- [ ] Device identifiers
- [ ] Web URLs
- [ ] IP addresses
- [ ] Biometric identifiers
- [ ] Full-face photos
- [ ] Any other unique identifying number or code

---

## 4. Emergency Response: Unintentional Data Exposure

If you realize that sensitive data was transmitted to a cloud AI service unintentionally:

### Immediate steps (within 24 hours):

1. **Document the incident:**
   - What file(s) were shared?
   - Estimated volume of sensitive data
   - Which tool / API (Claude Code, ChatGPT, etc.)
   - Approximate timestamp
   - What operation triggered it (Read, Bash cat, paste)

2. **Request data deletion:**
   - Anthropic API: Contact support and request deletion of session data
   - OpenAI API: Submit a deletion request via privacy request form
   - GitHub Copilot: Contact GitHub support

3. **Notify required parties:**
   - Your IRB (as a protocol deviation / unanticipated problem)
   - Your data source / DUA grantor (NHANES, PSID, etc.) as required by agreement
   - Your institution's Research Integrity Officer
   - Affected participants (if required by IRB; usually required if breach creates risk of harm)

4. **GDPR notification (if EU data):** 72-hour notification to supervisory authority if risk to data subjects is likely (GDPR Article 33).

5. **Document the response** in writing with timestamps.

### Incident report template:

```
DATA EXPOSURE INCIDENT REPORT
Date of discovery: [date]
Date of incident (approx): [date]
PI: [name]
Project: [name]
IRB Protocol: [number]

File(s) exposed: [list]
Estimated records: [N]
Data types involved: [PII / PHI / restricted / etc.]
AI service: [Claude / ChatGPT / GitHub Copilot / other]
Operation that caused exposure: [describe]

Immediate actions taken:
  [list]

Parties notified:
  [ ] IRB — date: [date]
  [ ] DUA grantor — date: [date]
  [ ] Institution RIO — date: [date]
  [ ] Participants — date: [date] / N/A (no risk of harm)

Deletion request submitted:
  Service: [name], Request #: [number], Date: [date]

Preventive measures implemented:
  [list changes to workflow]
```

---

## 5. Local LLM Setup for Sensitive Data Analysis

When cloud AI is prohibited, use a fully local LLM (Ollama). No data leaves your machine.

### Setup (one-time):

```bash
# Install Ollama
curl -fsSL https://ollama.com/install.sh | sh

# Pull models (downloads once; runs offline thereafter)
ollama pull llama3.2          # General purpose, good for text
ollama pull mistral           # Strong at code and analysis
ollama pull llama3.2:3b       # Smaller/faster if RAM is limited

# Verify it runs locally
ollama list
```

### Use in Python (for LLM annotation of sensitive data):

```python
import ollama

def annotate_text(text: str, codebook: str, model: str = "llama3.2") -> str:
    """Annotate text using local LLM — no data leaves the machine."""
    prompt = f"""
You are a research coder. Apply the following codebook to the text:

CODEBOOK:
{codebook}

TEXT:
{text}

Return only the code label and a one-sentence rationale.
"""
    response = ollama.chat(
        model=model,
        messages=[{"role": "user", "content": prompt}],
        options={"temperature": 0}   # Set to 0 for reproducibility
    )
    return response["message"]["content"]

# Usage: sensitive transcript data stays local
code = annotate_text(
    text=transcript_excerpt,
    codebook="1=positive sentiment; 2=negative sentiment; 3=neutral"
)
```

### Use in R (via `ollamar`):

```r
install.packages("ollamar")
library(ollamar)

# Annotate sensitive text locally
annotate_local <- function(text, codebook, model = "llama3.2") {
  prompt <- paste0(
    "Code this text using the codebook:\n",
    codebook, "\n\nText: ", text,
    "\n\nReturn only the numeric code and a brief rationale."
  )
  resp <- generate(model, prompt, output = "text")
  return(resp)
}

# Run on a sensitive transcript (data stays local)
result <- annotate_local(
  text = interview_excerpt,
  codebook = "1=economic hardship; 2=social support; 3=legal concern; 4=other"
)
```

---

## 6. Data Minimization Principles

Even for low-risk operations, practice data minimization:

1. **Share only the columns you need.** Before sharing any data with Claude, `select()` to the minimum set of variables needed for the question.

2. **Aggregate before sharing.** Group-level statistics are always safer than individual rows.

3. **Share code, not data.** Describe the data structure (variable names, types, N) to Claude; let Claude write the code; run the code locally; share only the output.

4. **Use synthetic data for debugging.** Generate a synthetic dataset with the same structure to test code, then run on real data locally.

```r
# Generate synthetic data for code testing
library(fabricatr)
synth <- fabricate(
  N = 500,
  age     = round(runif(N, 18, 80)),
  income  = rnorm(N, 50000, 15000),
  race    = sample(c("White", "Black", "Hispanic", "Asian"), N, replace = TRUE),
  outcome = rbinom(N, 1, 0.3)
)
# Share synth with Claude for code development; run final code on real data locally
```
