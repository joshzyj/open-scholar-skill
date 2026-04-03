---
name: scholar-journal
description: "Format, select, and prepare a manuscript for journal submission. 5 modes: FULL-PACKAGE (complete submission prep: structure audit + compliance checklist + cover letter + open science package + Save Output), FORMAT-CHECK (audit existing manuscript against journal requirements), COVER-LETTER (draft journal-calibrated cover letter), SELECT-JOURNAL (score paper against 18 journals and produce ranked target list with journal ladder), RESUBMIT-PACKAGE (post-rejection or R&R resubmission prep). Covers 18 journals: ASR, AJS, Demography, Du Bois Review, Science Advances, NHB, NCS, Social Forces, Language in Society, Journal of Sociolinguistics, Linguistic Inquiry, Gender & Society, APSR, Journal of Marriage and Family, Population and Development Review, Sociological Methods & Research, Poetics, PNAS. Per-journal: word limits, section structure, abstract format, citation style, figure/table limits, open science requirements (CRediT, COI, data/code availability, preregistration, Reporting Summary), blind review type, APC, submission system URL, acceptance rate, turnaround. Journal-specific cover letter templates with sociological/behavioral/computational framing. Journal selection scoring rubric with 8 dimensions. Open science package builder (data availability statement + code availability + preregistration + CRediT table + COI). Write tool saves submission readiness report + cover letter draft + open science declarations."
tools: Write, Bash, WebSearch, Read
argument-hint: "[journal name] [paper type: article/research-note/letter/brief-report] — optionally: mode [FULL-PACKAGE/FORMAT-CHECK/COVER-LETTER/SELECT-JOURNAL/RESUBMIT-PACKAGE]"
user-invocable: true
---

# Scholar Journal Formatting and Submission

You are an expert in academic publishing, familiar with submission requirements, editorial emphases, and open science standards of top sociology, demography, linguistics, political science, and multidisciplinary journals.

## Arguments

The user has provided: `$ARGUMENTS`

Parse:
- **Target journal**: ASR / AJS / Demography / Du Bois Review / Science Advances / NHB / NCS / Social Forces / Language in Society / J. Sociolinguistics / Linguistic Inquiry / Gender & Society / APSR / JMF / PDR / SMR / Poetics / PNAS / other
- **Paper type**: research article / research note / letter / brief report / methods article
- **Mode**: FULL-PACKAGE / FORMAT-CHECK / COVER-LETTER / SELECT-JOURNAL / RESUBMIT-PACKAGE
- **Paper description** (for SELECT-JOURNAL and COVER-LETTER): topic, methods, main finding

If no mode specified: run **FULL-PACKAGE** when a journal is named; run **SELECT-JOURNAL** when no journal is named.

---

## Setup

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
mkdir -p "${OUTPUT_ROOT}/submission" "${OUTPUT_ROOT}/logs"
```

**Process Logging (REQUIRED):**

Initialize the process log NOW by running:

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
mkdir -p "${OUTPUT_ROOT}/logs"
SKILL_NAME="scholar-journal"
LOG_DATE=$(date +%Y-%m-%d)
LOG_FILE="${OUTPUT_ROOT}/logs/process-log-${SKILL_NAME}-${LOG_DATE}.md"
if [ -f "$LOG_FILE" ]; then
  CTR=2; while [ -f "${OUTPUT_ROOT}/logs/process-log-${SKILL_NAME}-${LOG_DATE}-${CTR}.md" ]; do CTR=$((CTR+1)); done
  LOG_FILE="${OUTPUT_ROOT}/logs/process-log-${SKILL_NAME}-${LOG_DATE}-${CTR}.md"
fi
cat > "$LOG_FILE" << LOGHEADER
# Process Log: /${SKILL_NAME}
- **Date**: ${LOG_DATE}
- **Time started**: $(date +%H:%M:%S)
- **Arguments**: [raw arguments]
- **Working Directory**: $(pwd)

## Steps

| # | Timestamp | Step | Action | Output | Status |
|---|-----------|------|--------|--------|--------|
LOGHEADER
echo "Process log initialized: $LOG_FILE"
```

**After EVERY numbered step**, append a row by running:

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
SKILL_NAME="scholar-journal"
LOG_DATE=$(date +%Y-%m-%d)
LOG_FILE="${OUTPUT_ROOT}/logs/process-log-${SKILL_NAME}-${LOG_DATE}.md"
if [ ! -f "$LOG_FILE" ]; then
  LOG_FILE=$(ls -t "${OUTPUT_ROOT}"/logs/process-log-${SKILL_NAME}-${LOG_DATE}*.md 2>/dev/null | head -1)
fi
echo "| [step#] | $(date +%H:%M:%S) | [Step Name] | [1-line action summary] | [output files or —] | ✓ |" >> "$LOG_FILE"
```

**IMPORTANT:** Shell variables do NOT persist across Bash tool calls. Every step MUST re-derive LOG_FILE before appending.

---

## Step 0: Dispatch

| Mode keyword | Action |
|--------------|--------|
| `full`, `prepare`, `submission`, no mode given + journal named | FULL-PACKAGE → Steps 1–8 |
| `format`, `check`, `audit` | FORMAT-CHECK → Steps 2–3 + Step 7 checklist |
| `cover letter`, `cover` | COVER-LETTER → Steps 1 + 5 |
| `select`, `which journal`, `target`, no journal named | SELECT-JOURNAL → Step 1 only |
| `resubmit`, `R&R`, `rejection`, `revise and resubmit` | RESUBMIT-PACKAGE → Steps 1 + 3 + 5 + 6 + 8 |

---

## Step 1: Journal Selection and Scoring

**If mode = SELECT-JOURNAL**, score the paper against all target journals. If a journal is already named, skip to Step 2.

### Journal Selection Scoring Rubric (8 dimensions)

Score each candidate journal 1–5 on each dimension, then sum for a ranked list.

| Dimension | Score 1 | Score 5 |
|-----------|---------|---------|
| **Scope fit** | Paper outside journal scope | Perfect scope match |
| **Methods fit** | Methods below current journal standard | Methods are exactly what journal publishes |
| **Theory fit** | Atheoretical or theory mismatch | Theory is at center of argument |
| **Word count fit** | Paper is 2,000+ words over limit | Paper fits within limit |
| **Prestige target** | Paper not competitive at that tier | Paper is competitive |
| **Open science readiness** | Missing data/code; not preregistered | Data + code + preregistration all present |
| **Turnaround priority** | Fastest turnaround less important | Fastest turnaround critical |
| **Audience breadth** | Narrow disciplinary audience | Cross-disciplinary appeal |

### Quick Selection Guide

| Paper type | Primary target | Secondary | Tertiary |
|------------|---------------|-----------|---------|
| Causal ID + broad sociological significance | ASR | AJS | Social Forces |
| Theoretical innovation + deep argument | AJS | ASR | Sociological Theory |
| Population process + rigorous demography | Demography | PDR | JMF |
| Computational social science + large-scale data | Science Advances | NHB | NCS |
| New computational method | NCS | Science Advances | PNAS |
| Human behavior + cross-disciplinary methods | NHB | Science Advances | PNAS |
| Gender, race, family inequality | Gender & Society | ASR | AJS |
| Race/ethnicity + interdisciplinary | Du Bois Review | ASR | Social Forces |
| Language variation + society | Language in Society | J. Sociolinguistics | AJS |
| Variationist sociolinguistics | J. Sociolinguistics | Language in Society | AJS |
| Formal/generative linguistics | Linguistic Inquiry | Language | Natural Language & Linguistic Theory |
| Political behavior + institutions | APSR | AJPS | NHB |
| Family formation + demography | JMF | Demography | PDR |
| Culture + tastes + stratification | Poetics | AJS | ASR |
| Methods development + quantitative sociology | SMR | Sociological Methods | NCS |
| Social movements + collective action | Mobilization | ASR | AJS |
| Cross-national comparative | ASR | AJS | International Sociology |

### Journal Ladder (Rejection Routing)

```
SOCIOLOGY LADDER:
  ASR → AJS → Social Forces → Sociological Quarterly / Social Problems

DEMOGRAPHY LADDER:
  Demography → PDR → JMF → Demographic Research

COMPUTATIONAL LADDER:
  NCS → Science Advances → NHB → PNAS → AJS/ASR

LANGUAGE/LINGUISTICS LADDER:
  Language in Society → J. Sociolinguistics → Applied Linguistics

FORMAL LINGUISTICS LADDER:
  Linguistic Inquiry → Language → Natural Language & Linguistic Theory

GENDER/RACE LADDER:
  Gender & Society → ASR → Social Problems → Du Bois Review

RACE/ETHNICITY LADDER:
  Du Bois Review → ASR → Social Forces → Ethnic and Racial Studies
```

---

## Step 2: Manuscript Audit

Audit the manuscript against the target journal's requirements. Ask the user for (or infer from $ARGUMENTS):
- Current word count (total + by section if available)
- Current citation style
- Number of tables and figures
- Whether preregistered / data available / code available

**Word Count Audit** (approximate section allocation):

| Section | ASR/AJS (~12k) | Demography (~10k) | Science Advances (~5k) | NHB (~4k) |
|---------|---------------|------------------|----------------------|---------|
| Introduction | 600–900 | 500–700 | 400–600 | 400–600 |
| Theory/Background | 1,500–2,500 | 1,000–1,500 | embedded in intro | embedded |
| Data & Methods | 1,500–2,500 | 2,000–3,000 | 700–1,200 | 800–1,200 |
| Results | 2,500–4,000 | 2,500–4,000 | 1,200–2,000 | 800–1,500 |
| Discussion/Conclusion | 1,000–1,500 | 800–1,200 | 600–1,000 | 600–900 |

---

## Step 3: Journal-Specific Requirements

Apply the appropriate spec block for the target journal. Full specs in `references/top-journals.md`.

---

### ASR — American Sociological Review

**Word limit**: ~12,000 (text + notes; not references, tables, figures)
**Abstract**: 150–200 words, unstructured
**Research Notes**: ~5,000 words
**Format**: 12pt, double-spaced, 1-inch margins, line numbers required
**Blind review**: Double-blind (remove all identifying information including acknowledgments)
**Citation style**: ASA author-date
**Submission system**: Editorial Manager — https://www.editorialmanager.com/asr
**Acceptance rate**: ~5–6% | **Turnaround**: 3–6 months
**APC**: ~$2,600 (optional open access)

**Section order**: Introduction → Literature Review/Theory → Data & Methods → Results → Discussion → Conclusion → Notes → References → Tables → Figures

**Abstract template**:
> "[2–3 sentences on background/gap] [1–2 sentences on data/methods] [1–2 sentences on main findings] [1 sentence on contribution]"

**Key requirements**:
- [ ] Line numbers on every page (required for review)
- [ ] Tables as editable Word text, end of document; no images
- [ ] Figures as separate files (EPS, TIFF, PDF); 300+ DPI
- [ ] Endnotes only (footnotes not accepted); use sparingly
- [ ] Explicit contribution statement in introduction ("This paper contributes...")
- [ ] Hypotheses clearly numbered and labeled
- [ ] AMEs (average marginal effects) for logit/probit; OR are discouraged
- [ ] Replication data deposit strongly encouraged (ASA guidelines)

**What ASR desk-rejects**: No theoretical contribution; below-standard identification strategy; paper already >15,000 words; not "broadly sociological"

---

### AJS — American Journal of Sociology

**Word limit**: No strict limit; 8,000–15,000 typical
**Abstract**: 150 words, unstructured
**Format**: Double-spaced, 12pt, anonymous
**Blind review**: Double-blind
**Citation style**: Chicago author-date (close to ASA; note minor punctuation differences)
**Submission system**: ScholarOne — https://mc.manuscriptcentral.com/ajs
**Acceptance rate**: ~5–8% | **Turnaround**: 3–6 months

**Section order**: Introduction → Theory → Data & Methods → Results → Discussion → References

**Key AJS distinctions**:
- Theory is more central than in ASR; longer theory sections are acceptable (2,000–3,000 words)
- Historical, comparative, and macro-structural arguments are especially welcome
- Review essays (invited or proposed) accepted
- AJS tolerates more variation in methods than ASR

**What AJS desk-rejects**: Thin theory; pure methods paper without sociological argument; topic too narrow for broad sociological audience

---

### Demography

**Word limit**: ~10,000 (text + notes) | Research Notes: ~4,000
**Abstract**: ~150 words, unstructured; keywords: 4–6
**Format**: Double-spaced, 12pt
**Blind review**: Double-blind
**Citation style**: ASA format
**Submission system**: Editorial Manager — https://www.editorialmanager.com/demography
**Acceptance rate**: ~10–15% | **Turnaround**: 3–5 months
**APC**: optional open access

**Section order**: Introduction → Background (theory + literature) → Data and Methods → Results → Discussion → References → Appendices (online supplement)

**Key requirements**:
- [ ] Data replication deposit required (ICPSR, Zenodo, or OSF — no exceptions)
- [ ] Descriptive statistics table mandatory (Table 1)
- [ ] Online Supplementary Appendix for all sensitivity analyses and additional tables
- [ ] Demographic decomposition expected for population-level claims (Kitagawa, Blinder-Oaxaca, etc.)
- [ ] Survey weights and sample design documented
- [ ] If using restricted-use data: note access restrictions and how replication is handled
- [ ] Keywords required (4–6)

**What Demography desk-rejects**: No demographic contribution; thin methods section; missing data availability; not centered on a population process

---

### Du Bois Review — Social Science Research on Race

**Word limit**: 8,000–12,000 words (text + notes; not references, tables, figures)
**Abstract**: 150 words, unstructured; keywords: 4–6
**Format**: 12pt, double-spaced, 1-inch margins
**Blind review**: Double-blind
**Citation style**: ASA author-date
**Submission system**: Cambridge Core — https://www.cambridge.org/core/journals/du-bois-review-social-science-research-on-race
**Acceptance rate**: ~15–20% | **Turnaround**: 3–6 months
**Publisher**: Cambridge University Press

**Scope**: Race and ethnicity; racial inequality; immigration and ethnoracial boundaries; intersections of race with class, gender, and citizenship; interdisciplinary approaches to racial stratification; critical race scholarship; comparative racial formations

**Section order**: Introduction → Literature Review/Theory → Data & Methods → Results → Discussion → Conclusion → References → Tables → Figures

**Key requirements**:
- [ ] Structured sections required (Introduction, Literature/Theory, Data & Methods, Results, Discussion, Conclusion)
- [ ] ASA author-date citation style
- [ ] Abstract 150 words maximum
- [ ] Keywords required (4–6)
- [ ] Tables as editable text at end of document
- [ ] Figures as separate files; 300+ DPI
- [ ] Double-blind: remove all identifying information

**Key notes**:
- Interdisciplinary journal: welcomes sociology, political science, economics, history, public health, legal studies
- Both qualitative and quantitative work published; mixed methods welcome
- Explicitly centers race as a core analytic category (not merely a control variable)
- Publishes research articles, review essays, and state-of-the-discipline pieces
- Strong engagement with W.E.B. Du Bois's intellectual legacy and critical race theory expected

**What Du Bois Review desk-rejects**: Race as secondary variable without substantive racial analysis; no engagement with race scholarship; narrow disciplinary framing without interdisciplinary relevance

---

### Science Advances

**Word limit**: 4,000–6,000 (main text); Methods can go in supplement
**Abstract**: ~250 words + one-sentence teaser (≤250 characters) for TOC
**Format**: AAAS style; figures and tables embedded or at end
**Blind review**: Single-blind; ~50% desk-reject rate
**Citation style**: Numbered references in appearance order
**Submission system**: https://www.science.org/journal/sciadv
**Acceptance rate**: ~30% of externally reviewed (~15% of submitted) | **Turnaround**: 6–10 weeks
**APC**: ~$4,950 (mandatory open access)

**Section order**: Title → One-sentence abstract → Full abstract → Introduction → Results → Discussion → Materials and Methods → Supplementary Materials → References and Notes → Acknowledgments → Author Contributions (CRediT) → Competing Interests → Data Availability

**Key requirements**:
- [ ] One-sentence teaser abstract (≤250 characters) required — write this separately
- [ ] Max display items: 7 (figures + tables combined; main text)
- [ ] All figures: 300 DPI minimum; TIFF or EPS; panels labeled A, B, C...
- [ ] Data and code availability statement required
- [ ] CRediT author contributions taxonomy required
- [ ] Competing interests statement required (even if none)
- [ ] Supplementary Materials: Separate PDF; text + figures + tables labeled S1, S2...
- [ ] Methods can be moved to Supplementary if needed to meet word limit

**Abstract template (one-sentence teaser)**:
> "[Paper's advance in one sentence, accessible to non-sociologists, ≤250 characters]"

**What Science Advances desk-rejects**: Not interdisciplinarily significant; no "advance" beyond sociology; missing data/code; narrow disciplinary framing

---

### Nature Human Behaviour (NHB)

**Word limit**: Articles 3,000–5,000; Letters ~1,500
**Abstract**: ≤150 words; 3 structured sentences: [Background / Findings / Implications]
**Title**: ≤90 characters (including spaces)
**Max references**: 50 for articles; 30 for letters
**Max display items**: 6 figures/tables (main text); +10 Extended Data items
**Blind review**: Double-blind (since 2019)
**Citation style**: Numbered superscripts
**Submission system**: https://mts.nature.com (select NHB)
**Acceptance rate**: ~5% | **Turnaround**: 6–12 weeks
**APC**: ~€9,500 (optional open access)

**Section order**: Title → Abstract (3 sentences) → Introduction → Results → Discussion → Methods → References → Acknowledgments → Author Contributions (CRediT) → Competing Interests → Additional Information (data/code) → Extended Data → Supplementary Information

**Key requirements**:
- [ ] Abstract: Exactly 3 sentences — Background (problem + gap), Findings (methods + key results), Implications (broader significance)
- [ ] Title: ≤90 characters — must be accessible and not jargon-heavy
- [ ] Methods AFTER Discussion (not before results)
- [ ] Nature Research Reporting Summary (PDF form) — REQUIRED — download from Nature website
- [ ] Preregistration statement required (note if not preregistered and why)
- [ ] Data availability statement required (must specify repository + accession code OR state why data cannot be shared)
- [ ] Code availability statement required
- [ ] CRediT author contributions required
- [ ] Extended Data (up to 10 items): label as "Extended Data Fig. 1" etc.; cited in main text

**Abstract template**:
> "**Background**: [One sentence on the phenomenon and the knowledge gap.] **Findings**: [One sentence on what you did and what you found.] **Implications**: [One sentence on what this means for the field and/or for policy/practice.]"

**What NHB desk-rejects**: Missing Reporting Summary; missing preregistration statement; main text >5,000 words; sample is exclusively Western with no generalizability discussion; methods not at current standards; no broader-than-sociology significance

---

### Nature Computational Science (NCS)

**Word limit**: Articles 3,000–5,000; Methods articles up to 6,000
**Abstract**: ≤150 words, structured (Background / Methods summary / Results summary / Conclusions)
**Title**: ≤90 characters
**Blind review**: Double-blind
**Citation style**: Numbered superscripts (same as NHB)
**Submission system**: https://mts.nature.com (select NCS)
**Acceptance rate**: <10% | **Turnaround**: 8–12 weeks

**Key NCS requirements** (non-negotiable):
- [ ] Computational method is itself the primary contribution — NOT just applying existing methods
- [ ] Open-source code REQUIRED (GitHub repository + Zenodo DOI for long-term archiving)
- [ ] Benchmarking against existing methods with quantitative comparison
- [ ] Reproducibility environment (Docker / conda environment.yml / renv.lock)
- [ ] Nature Reporting Summary required
- [ ] NCS Results-before-Methods section order (same as NHB)
- [ ] Software availability statement: GitHub URL + Zenodo DOI + version + language

**Section order**: Same as NHB (Introduction → Results → Discussion → Methods)

**What NCS desk-rejects**: Code not available; no methodological advance (just applying BERT/GPT to social data); benchmarking absent; not reproducible

---

### Social Forces

**Word limit**: 10,000–12,000 words (text + notes; not references, tables, figures)
**Abstract**: 150 words, unstructured; keywords: 4–6
**Format**: 12pt, double-spaced, 1-inch margins
**Blind review**: Double-blind
**Citation style**: ASA author-date
**Submission system**: ScholarOne — https://mc.manuscriptcentral.com/sf
**Acceptance rate**: ~10–12% | **Turnaround**: 3–5 months
**Publisher**: Oxford University Press

**Scope**: Broad sociology; strong on race, gender, immigration, stratification, social inequality, organizations; more tolerant of exploratory and heterodox work than ASR

**Section order**: Introduction → Literature Review/Theory → Data & Methods → Results → Discussion → Conclusion → References → Tables → Figures

**Key requirements**:
- [ ] Tables as editable text at end of document
- [ ] Figures as separate files (EPS, TIFF, PDF); 300+ DPI
- [ ] Endnotes preferred; use sparingly
- [ ] Replication packet required at acceptance
- [ ] Keywords required (4–6)
- [ ] Line numbers on every page

**Key notes**:
- Social Forces accepts papers that don't quite fit ASR/AJS (more heterodox methods, regional samples)
- Good for causal work without extreme identification strategies
- Also publishes research notes (~4,000 words)

**What Social Forces desk-rejects**: Pure methods paper; no sociological argument; paper already over 15,000 words

---

### Language in Society

**Word limit**: 8,000–10,000 words | **Abstract**: 150 words; 6–10 keywords
**Blind review**: Double-blind | **Citation style**: APA 7th
**Submission system**: Cambridge Core (https://mc.manuscriptcentral.com/lis)
**Acceptance rate**: ~15–20% | **Turnaround**: 3–6 months
**Publisher**: Cambridge University Press

**Scope**: Sociolinguistics, language variation and change, language attitudes, language ideologies, conversation analysis, multilingualism, language policy

**Section order**: Introduction → Background/Literature → Methods → Results → Discussion → References

**Key notes**:
- Rich qualitative/discourse analysis work welcomed alongside quantitative variationist studies
- Transcripts and extended examples expected for CA, interactional, and ethnographic work
- Jefferson notation standard for CA work
- APA reference format (not ASA)
- Keywords: 6–10 required (including linguistic features and populations studied)

**What LiS desk-rejects**: Pure sociology without linguistic analysis; no language data; computational work without qualitative grounding

---

### Journal of Sociolinguistics

**Word limit**: 8,000–10,000 words (text + notes; not references, tables, figures)
**Abstract**: 200 words, unstructured; keywords: 5–8
**Format**: 12pt, double-spaced, 1-inch margins
**Blind review**: Double-blind
**Citation style**: Unified Style Sheet for Linguistics (author-date)
**Submission system**: Wiley Online — https://onlinelibrary.wiley.com/journal/14679841
**Acceptance rate**: ~15–25% | **Turnaround**: 3–6 months
**Publisher**: Wiley

**Scope**: Sociolinguistics; language variation and change; language and identity; language and gender; multilingualism and code-switching; language policy and planning; language ideologies; linguistic landscapes; language and social media; variationist sociolinguistics

**Section order**: Introduction → Background/Literature → Methods → Results/Analysis → Discussion → Conclusion → References → Appendices → Tables → Figures

**Key requirements**:
- [ ] Unified Style Sheet for Linguistics citation format (not APA or ASA)
- [ ] Abstract 200 words maximum
- [ ] Keywords required (5–8)
- [ ] Tables as editable text; figures at 300+ DPI
- [ ] Double-blind: remove all identifying information
- [ ] IPA transcriptions should use Unicode (not images)
- [ ] Linguistic examples numbered sequentially and glossed per Leipzig Glossing Rules where applicable

**Key notes**:
- Core venue for variationist sociolinguistics and language-and-society research
- Both quantitative (mixed-effects regression, Rbrul) and qualitative (ethnographic, discourse-analytic) work published
- Engagement with social theory (Bourdieu, Goffman, intersectionality) valued
- Special issues on emerging topics (digital sociolinguistics, raciolinguistics) are common
- Companion journal to Language in Society; more variation-focused and empirically driven

**What J. Sociolinguistics desk-rejects**: Pure formal linguistics without social dimension; no language data; computational methods without sociolinguistic framing; pure sociology without linguistic analysis

---

### Linguistic Inquiry

**Word limit**: ~30 pages double-spaced (approximately 10,000–12,000 words including references)
**Abstract**: Not required (no structured abstract); brief introductory paragraph serves as abstract
**Format**: 12pt, double-spaced, 1-inch margins
**Blind review**: Double-blind
**Citation style**: Unified Style Sheet for Linguistics (author-date)
**Submission system**: MIT Press — https://direct.mit.edu/ling
**Acceptance rate**: ~10–15% | **Turnaround**: 3–6 months
**Publisher**: MIT Press

**Scope**: Formal linguistics; generative grammar; syntax; semantics; phonology; morphology; theoretical linguistics; linguistic universals; formal pragmatics

**Section order**: Introduction → Background → Analysis/Proposal → Predictions/Evidence → Alternative Analyses → Conclusion → References → Appendices

**Key requirements**:
- [ ] Unified Style Sheet for Linguistics citation format
- [ ] No structured abstract required; paper should open with a clear statement of the problem
- [ ] ~30 pages double-spaced maximum (including references and appendices)
- [ ] Linguistic examples numbered sequentially: (1a), (1b), (2), etc.
- [ ] Glossing per Leipzig Glossing Rules for non-English data
- [ ] Tree diagrams and formal representations should be high-resolution (300+ DPI)
- [ ] Formal notation (feature matrices, Optimality Theory tableaux, lambda calculus) typeset correctly
- [ ] Double-blind: remove all identifying information

**Key notes**:
- Premier venue for formal/generative linguistics — theoretical argumentation is central
- Empirical data must support formal analysis; typological breadth valued
- "Squibs and Discussion" section for shorter contributions (~10 pages) addressing specific puzzles
- "Remarks and Replies" section for responses to previously published articles
- Not a sociolinguistics journal — social dimensions of language are not the focus
- Strong engagement with current syntactic/semantic/phonological theory expected

**What LI desk-rejects**: Sociolinguistic or applied linguistics work; purely descriptive without formal analysis; no theoretical contribution to generative grammar; insufficient engagement with current formal literature

---

### Gender & Society

**Word limit**: ~9,000 words (text) | **Abstract**: 200 words
**Blind review**: Double-blind | **Citation style**: ASA
**Submission system**: https://mc.manuscriptcentral.com/gs
**Acceptance rate**: ~8–10% | **Turnaround**: 3–6 months
**Publisher**: SAGE / Sociologists for Women in Society

**Scope**: Gender relations, feminism, intersectionality, sexualities, masculinities, feminist theory and methods

**Key notes**:
- Explicitly intersectional framework expected
- Both qualitative and quantitative work published; mixed methods welcome
- Feminist standpoint epistemology valued but not required
- Strong engagement with feminist theory expected in all papers
- Race and class alongside gender is standard

**What G&S desk-rejects**: Gender as secondary variable without feminist theorization; no engagement with feminist scholarship

---

### APSR — American Political Science Review

**Word limit**: ~12,000 words | **Abstract**: 150 words, unstructured
**Blind review**: Double-blind | **Citation style**: APSA author-date (similar to APA)
**Submission system**: Cambridge Core (https://mc.manuscriptcentral.com/apsr)
**Acceptance rate**: ~7–8% | **Turnaround**: 3–6 months

**Scope**: Formal theory, empirical political science, comparative politics, international relations, political behavior, political economy

**Key notes**:
- Pre-analysis plans strongly encouraged for experimental work
- Methods must be at frontier (causal ID, formal models, large-scale text)
- APSA citation format: (Author Year) with full first names in reference list
- Computational/text-as-data papers increasingly welcome
- Data replication required at acceptance (Dataverse)

**For sociologists submitting to APSR**: Frame the political dimension explicitly; social structure as politically constituted; policy implications emphasized

---

### Journal of Marriage and Family (JMF)

**Word limit**: 8,000 words (text + notes; not references, tables, figures)
**Abstract**: 200 words, unstructured; keywords: 3–5
**Format**: 12pt, double-spaced, 1-inch margins
**Blind review**: Double-blind
**Citation style**: APA 7th edition
**Submission system**: ScholarOne — https://mc.manuscriptcentral.com/jmf
**Acceptance rate**: ~15–20% | **Turnaround**: 3–6 months
**Publisher**: Wiley / National Council on Family Relations (NCFR)

**Scope**: Family dynamics, marriage, cohabitation, divorce, parenting, family structure and inequality, life course transitions, family demography, intergenerational relationships

**Section order**: Introduction → Background/Literature → Data & Methods → Results → Discussion → Conclusion → References → Tables → Figures

**Key requirements**:
- [ ] APA reference format (not ASA)
- [ ] Abstract 200 words maximum
- [ ] Keywords required (3–5)
- [ ] Theoretical contribution required (not just "we use new data")
- [ ] Replication data deposit expected at acceptance
- [ ] Tables as editable text at end of document
- [ ] Figures at 300+ DPI

**Key notes**:
- Life course perspective and demographic approaches standard
- Family inequality and child well-being papers are core
- Both qualitative and quantitative work published
- Research briefs accepted (~3,000 words)

**What JMF desk-rejects**: No family-relevant contribution; pure demographic trend without family mechanism; missing theoretical grounding

---

### Population and Development Review (PDR)

**Word limit**: 8,000–10,000 words (text + notes; not references, tables, figures)
**Abstract**: 200 words, unstructured; keywords: 4–6
**Format**: 12pt, double-spaced
**Blind review**: Double-blind
**Citation style**: Chicago author-date
**Submission system**: Wiley Online — https://onlinelibrary.wiley.com/journal/17284457
**Acceptance rate**: ~10–15% | **Turnaround**: 3–5 months
**Publisher**: Wiley / Population Council

**Scope**: Population change and its interactions with economic development, policy, and social institutions; cross-national comparative demography; fertility, mortality, migration at population level

**Section order**: Introduction → Background → Data & Methods → Results → Discussion → Conclusion → References → Tables → Figures

**Key requirements**:
- [ ] Chicago author-date citation style
- [ ] Abstract 200 words maximum
- [ ] Keywords required (4–6)
- [ ] Strong policy relevance expected
- [ ] Tables as editable text; figures at 300+ DPI

**Key notes**:
- Cross-national and Global South data highly valued
- Less quantitative-methods-heavy than Demography; narrative/theoretical pieces also published
- PDR publishes "Research Reports" (shorter pieces ~3,000 words)
- Essay-style and review articles also welcome

**What PDR desk-rejects**: No population-level contribution; purely methodological without substantive application; narrow single-country focus without comparative implication

---

### Sociological Methods & Research (SMR)

**Word limit**: 10,000–15,000 words (text + notes; not references, tables, figures)
**Abstract**: 200 words, unstructured; keywords: 5–7
**Format**: 12pt, double-spaced, 1-inch margins
**Blind review**: Double-blind
**Citation style**: ASA author-date
**Submission system**: SAGE — https://mc.manuscriptcentral.com/smr
**Acceptance rate**: ~15–20% | **Turnaround**: 3–6 months
**Publisher**: SAGE Publications

**Scope**: Quantitative and computational methods; causal inference; measurement; social science methodology; statistical modeling; survey methodology; simulation

**Section order**: Introduction → Background/Literature → Proposed Method/Framework → Simulation/Monte Carlo Evidence → Empirical Application → Discussion → Conclusion → References → Appendices → Tables → Figures

**Key requirements**:
- [ ] ASA author-date citation style
- [ ] Abstract 200 words maximum
- [ ] Keywords required (5–7)
- [ ] Methods contribution IS the paper — application alone insufficient
- [ ] Simulation studies expected for new estimators
- [ ] Code and data for all analyses required
- [ ] Empirical application demonstrating method on real data expected
- [ ] Tables as editable text; figures at 300+ DPI
- [ ] Emphasis on methodology: derivations, proofs, or simulation evidence must be central

**Key notes**:
- Longer manuscripts (up to 15,000 words) acceptable given methodological detail
- Online appendix for extended proofs, additional simulations encouraged
- Both frequentist and Bayesian methods published
- Computational social science methods increasingly welcome

**What SMR desk-rejects**: Pure application of existing methods; no methodological contribution; missing simulation evidence for new estimator; no code/data availability

---

### PNAS — Proceedings of the National Academy of Sciences

**Word limit**: 6 pages (~3,500 words) for Research Articles; significance statement (125 words)
**Abstract**: ≤250 words, unstructured
**Blind review**: Single-blind; member-contributed or direct submission
**Citation style**: Numbered, superscript
**Submission system**: https://www.pnas.org/author-center
**Acceptance rate**: ~10–15% of direct submissions | **Turnaround**: 4–8 weeks
**APC**: ~$3,780–$5,400 (open access optional; mandatory for NIH-funded)

**Key requirements**:
- [ ] Significance Statement (125 words, layperson-accessible) — REQUIRED
- [ ] 6-page limit (figures embedded; use SI for all extended content)
- [ ] 2 classification tags required (e.g., "Social Sciences/Sociology"; "Social Sciences/Psychological and Cognitive Sciences")
- [ ] All data and code publicly available
- [ ] Direct submission track available (no NAS member required since 2021 for social science track)

---

### Poetics

**Word limit**: 8,000–10,000 words | **Abstract**: 150 words; keywords: 4–6
**Blind review**: Double-blind | **Citation style**: APA 7th
**Submission system**: Elsevier Editorial System
**Turnaround**: 3–6 months

**Scope**: Sociology of culture, cultural consumption, taste, aesthetic fields, literature, media, arts institutions; quantitative and computational cultural sociology

**Key notes**: Bourdieu's field theory and cultural capital are central reference points; increasingly computational (text analysis of cultural products, field analysis)

---

## Step 4: Open Science Package

Build the complete open science declarations required for the target journal.

### Data Availability Statement Templates

**When data is publicly available (direct download)**:
> "All data used in this study are publicly available from [source name] at [URL]. The analysis dataset and replication code are deposited at [Zenodo/OSF/ICPSR]: [DOI/URL]."

**When data is restricted-use (licensed / secure enclave)**:
> "Data were obtained under a restricted-use data agreement with [source]. Due to the terms of this agreement, we are unable to share the analysis dataset. Researchers can apply for access at [URL]. Analysis code is available at [GitHub/Zenodo URL]. Variable names, codebooks, and model specifications sufficient for replication of our procedures are available from the authors upon request."

**When data is from original primary collection**:
> "The survey data collected for this study will be deposited at [OSF/Zenodo/ICPSR] upon acceptance and are available from the corresponding author during review. The survey instrument and analysis code are available at [URL/DOI]."

**When data includes sensitive/identifying information**:
> "The [interview/administrative] data cannot be shared publicly due to [IRB restrictions / participant confidentiality / HIPAA compliance]. Anonymized codebooks and analysis code are available at [URL]. Researchers interested in access should contact [author]."

---

### Code Availability Statement Templates

**When code is on GitHub + Zenodo**:
> "All analysis code is available at [GitHub URL] and archived at Zenodo [DOI]. The repository includes [R scripts / Python scripts / Stata do-files] for all analyses reported in the main text and supplementary materials. The computing environment is documented in [renv.lock / requirements.txt / environment.yml]."

**When code is in supplement only**:
> "Analysis code is provided in the Supplementary Materials. Requests for additional code or data should be directed to the corresponding author."

---

### Preregistration Statement Templates

**When preregistered**:
> "This study was pre-registered at OSF prior to data collection: [OSF DOI]. The pre-analysis plan specifies [the primary outcomes, the analytic sample, and the main model specifications]. Deviations from the pre-analysis plan are noted in the Supplementary Materials."

**When NOT preregistered (NHB/NCS requirement)**:
> "This study was not pre-registered. The analyses reported here were exploratory in nature / were conducted on existing secondary data, precluding pre-registration. All analysis decisions are documented in the Supplementary Materials."

---

### CRediT Author Contributions Table

Use the CRediT (Contributor Roles Taxonomy) 14-role system. Fill in for all authors:

| CRediT Role | Author 1 | Author 2 | Author 3 |
|-------------|----------|----------|----------|
| Conceptualization | | | |
| Data curation | | | |
| Formal analysis | | | |
| Funding acquisition | | | |
| Investigation | | | |
| Methodology | | | |
| Project administration | | | |
| Resources | | | |
| Software | | | |
| Supervision | | | |
| Validation | | | |
| Visualization | | | |
| Writing – original draft | | | |
| Writing – review & editing | | | |

**Roles**: Lead = primary contributor; Support = contributing but not primary

---

### Competing Interests / COI Statement Templates

**When no competing interests**:
> "The authors declare no competing interests."

**When interests exist**:
> "[Author X] has received [funding / consulting fees / speaking honoraria] from [Organization Y], which [may / does not] have an interest in the findings reported here. [Author Z] holds [advisory board position / financial interest] in [Organization]. All other authors declare no competing interests."

---

### IRB / Ethics Statement Template

> "This study was approved by the [Institution] Institutional Review Board (IRB Protocol #[number], approved [date]). All participants provided [written / oral] informed consent. [If no IRB required:] This study used [de-identified secondary data / publicly available data] and was determined to be exempt from IRB review by [institution]."

---

## Step 5: Write Cover Letter

Use the journal-specific template below. Calibrate tone and emphasis to the target journal.

---

### ASR / AJS Cover Letter Template

```
Dear Editors,

We submit [PAPER TITLE] for consideration as a [Research Article / Research Note]
in [ASR / the American Journal of Sociology].

[¶1 — Research question, approach, and main finding — 3 sentences]:
[Paper's RQ]. Using [data and method], we find that [key finding]. [One sentence
on effect size or scope of finding].

[¶2 — Theoretical contribution and fit with journal — 3 sentences]:
This paper advances [theoretical debate X] by [specific contribution: establishing /
challenging / specifying the boundary conditions of / Y]. The findings speak directly
to the sociology of [subfield] and to the growing literature on [theme]. [One
sentence explicitly naming 2–3 prior ASR/AJS papers this builds on or responds to].

[¶3 — Methods and compliance — 2 sentences]:
The paper uses [design / data] to [identification strategy], addressing longstanding
concerns about [confounding / selection]. The manuscript has not been submitted
elsewhere and meets the journal's submission requirements ([word count] words).

[¶4 — Data, code, and IRB (optional)]:
[Data source] [are/will be] deposited at [repository]. Analysis code is available
at [URL]. This research was [approved by / exempt from] IRB review.

[¶5 — Suggested reviewers (optional)]:
We suggest the following reviewers who have relevant expertise: [Name (Affiliation,
email)]; [Name (Affiliation, email)]; [Name (Affiliation, email)].

We appreciate your consideration.

[Corresponding author name, title, institution, email]
```

---

### Demography Cover Letter Template

```
Dear Editors,

We submit [PAPER TITLE] as a [Research Article / Research Note] to Demography.

[¶1 — Demographic contribution — 2–3 sentences]:
[State the demographic process or trend being studied]. [State the specific
population, time period, and data used]. [State the main finding using
demographic framing: rates, trends, differentials, decomposition results].

[¶2 — Methodological contribution — 2 sentences]:
[Describe the identification strategy or methodological advance]. This approach
addresses [endogeneity concern / selection bias / data limitation] that has limited
prior work on [topic].

[¶3 — Compliance and data availability — 2 sentences]:
The analysis dataset and replication code have been [deposited at / will be
deposited at] [ICPSR / Zenodo] upon acceptance (DOI: [placeholder]). The
manuscript meets Demography's requirements ([word count] words; double-blind).

Thank you for your consideration.

[Corresponding author contact]
```

---

### Science Advances Cover Letter Template

```
Dear Editors,

We submit [PAPER TITLE] for consideration as a Research Article in Science Advances.

[¶1 — Broad scientific significance — 2–3 sentences]:
[State the phenomenon and its broader significance beyond sociology]. Using
[data description: N, scope, method], we demonstrate [main finding in one
accessible sentence]. [One sentence on why non-sociologists should care].

[¶2 — Advance and interdisciplinary relevance — 2 sentences]:
This study advances our understanding of [broad theme: social inequality /
collective behavior / human decision-making] by [specific advance]. Our findings
are relevant to researchers in [psychology / economics / public health / political
science] as well as to [policy audience].

[¶3 — Methods rigor and open science — 2 sentences]:
Our analysis uses [method] with [N] observations from [data source]. All data
[are publicly available at / have been deposited at] [repository]; analysis code
is available at [GitHub URL]; and the manuscript meets Science Advances submission
requirements ([word count] words; [number] figures/tables ≤ 7 total).

[¶4 — Scope]:
The manuscript has not been submitted or published elsewhere.

[Corresponding author contact]
```

---

### NHB Cover Letter Template

```
Dear Editors,

We submit [PAPER TITLE] for consideration as an Article in Nature Human Behaviour.

[¶1 — Finding and significance — 3 sentences]:
[State the research question and its relevance to understanding human behavior].
Using [data and method], we find [main finding — accessible to non-specialists].
[State the magnitude or scope of the finding and its translational implications].

[¶2 — Cross-disciplinary appeal — 2 sentences]:
This work will interest researchers across [psychology, economics, sociology,
public health] because [mechanism / implication applies broadly]. It speaks
to the NHB priority areas of [name 1–2: inequality / social influence /
decision-making / digital behavior].

[¶3 — Open science and compliance — 2 sentences]:
The study [was preregistered at OSF: DOI / was not preregistered; this is
noted in the manuscript]. Data [are/will be] deposited at [repository]; code
is available at [GitHub/Zenodo URL]. The Reporting Summary and all required
supplementary files are included with this submission.

[¶4 — Fit and format]:
The main text is [word count] words ([number] display items; [number] Extended
Data items). It has not been submitted elsewhere.

[Corresponding author contact]
```

---

### NCS Cover Letter Template

```
Dear Editors,

We submit [PAPER TITLE] for consideration as a [Research Article / Methods Article]
in Nature Computational Science.

[¶1 — Computational contribution — 3 sentences]:
We introduce / substantially advance [METHOD NAME], a [brief description of
what the method does]. Existing approaches [limitation of prior methods].
[Method name] addresses this by [key technical advance], enabling [new capability].

[¶2 — Application and validation — 2 sentences]:
We demonstrate [method name] on [domain + dataset], finding [key empirical
finding]. Benchmarking against [prior method 1] and [prior method 2] shows
[quantitative improvement: e.g., "a 15% improvement in F1 / 30% faster runtime"].

[¶3 — Open science and reproducibility — 2 sentences]:
All code is available at [GitHub URL] and archived at Zenodo ([DOI]); a
reproducible [Docker / conda / renv] environment is provided. The Reporting
Summary is included with this submission.

[Corresponding author contact]
```

---

## Step 6: Supplementary Materials Organization

### Standard Supplement Structure

```
SUPPLEMENTARY MATERIALS / ONLINE APPENDIX

Section A — Extended Methods
  A.1  [Variable construction and operationalization detail]
  A.2  [Sample construction and exclusions: full flowchart + N at each step]
  A.3  [Missing data strategy and sensitivity to imputation]
  A.4  [Survey weighting procedures (if applicable)]

Section B — Robustness and Sensitivity Analyses
  Table B1.  [Main model with alternative sample / exclusion criteria]
  Table B2.  [Alternative operationalization of [key variable]]
  Table B3.  [Oster delta / E-value / Rosenbaum bounds for main effect]
  Table B4.  [Staggered DiD / alternative specification (if applicable)]
  [Add as many as needed; label sequentially B1, B2...]

Section C — Heterogeneity / Subgroup Analyses
  Table C1.  [Subgroup analysis by race / gender / cohort / etc.]
  Figure C1. [CATE or interaction plot]

Section D — Descriptive Statistics and Data Quality
  Table D1.  [Full descriptive statistics table with all variables]
  Table D2.  [Correlation matrix or VIF table]
  Figure D1. [Missingness plot / attrition analysis]

Section E — Survey Instruments / Interview Protocols (if applicable)
  [Full question wording; coding rules; interviewer instructions]

Section F — Computational Methods (if applicable)
  F.1  [Full prompt text (LLM annotation)]
  F.2  [Model architecture details / hyperparameters]
  F.3  [Human coding instructions and IRR results]
```

**Journal-specific supplement labels**:
- NHB / NCS: "Extended Data Fig. 1" (up to 10 items cited in main text) + "Supplementary Information" (additional)
- Science Advances: Figs. S1–SN; Tables S1–SN (numbered within supplement)
- ASR / AJS / Demography: Appendix Tables A1–AN; Appendix Figures A1–AN

---

## Step 6b: Pre-Submission Cross-Skill Integration Checks

**Pre-submission integration checks**:
1. Invoke `scholar-citation` MODE 2 (AUDIT) — verify all citations are consistent
2. Invoke `scholar-citation` MODE 3 (CONVERT-STYLE) — ensure citation style matches target journal
3. Check: Does manuscript include Data/Code Availability statement? If not, flag.
4. Check: Does manuscript include Author Contributions (CRediT)? If targeting Nature family, flag if missing.
5. Check: Does manuscript include Competing Interests declaration? Flag if missing for Nature family.
6. **Invoke `scholar-verify` (full mode)** — run the 4-agent verification panel as a pre-submission gate:

   ```bash
   cat .claude/skills/scholar-verify/SKILL.md
   ```

   Run `scholar-verify full` on the manuscript being submitted. This catches:
   - **Stage 1**: Raw analysis outputs that don't match manuscript tables/figures (transcription errors introduced during formatting)
   - **Stage 2**: Statistical claims in prose that don't match manuscript tables/figures (misquoted numbers, wrong references, significance errors)

   **Gate rule**: If the verification verdict is **MAJOR ISSUES — DO NOT SUBMIT**, halt submission prep and report the fix checklist. The user must resolve all CRITICAL issues before proceeding to Step 7 (compliance checklist). If verdict is REVISIONS NEEDED or READY, proceed with any CRITICAL fixes applied and WARNINGS noted in the submission readiness report (Step 8).

---

## Step 7: Pre-Submission Compliance Checklist

Generate a journal-specific checklist. Mark each item PASS / FAIL / N/A.

### Universal Items (all journals)

- [ ] **Anonymous manuscript** — no author names in text, notes, or acknowledgments (for double-blind)
- [ ] **Word count** within journal limit (check against Step 3 specs)
- [ ] **Line numbers** on every page (required by most sociology journals)
- [ ] **Double-spaced** throughout (including references)
- [ ] **12pt font** (Times New Roman or similar)
- [ ] **Abstract** within word limit and correctly formatted (structured vs. unstructured)
- [ ] **Keywords** present if required
- [ ] **In-text citations** consistent with journal's style throughout
- [ ] **Reference list** — all in-text citations appear; no orphans; no entries missing from text
- [ ] **Tables** as editable text (not screenshots or images)
- [ ] **Figures** at correct resolution (≥300 DPI; TIFF or EPS preferred)
- [ ] **Figure and table count** within journal limit
- [ ] **Author contributions statement** (CRediT) — required by Nature/AAAS journals
- [ ] **Data availability statement** — required by all journals
- [ ] **Competing interests statement** — required; include even if "none"
- [ ] **Funding / acknowledgments** — listed; not in blinded version
- [ ] **IRB statement** — included if human subjects research

### Journal-Specific Additional Items

**ASR/AJS/Demography**:
- [ ] Line numbers present
- [ ] Tables placed after references (end of document)
- [ ] Figures as separate files (not embedded in Word)
- [ ] Endnotes only (no footnotes) — ASR
- [ ] Replication data deposited or in progress — Demography (required), ASR/AJS (strongly encouraged)

**Science Advances**:
- [ ] One-sentence teaser abstract (≤250 characters) present as separate field
- [ ] Display items ≤7 total (figures + tables combined)
- [ ] Methods section placed after Discussion
- [ ] Supplement labeled S1, S2... throughout

**NHB / NCS**:
- [ ] Abstract is exactly 3 structured sentences (Background / Findings / Implications)
- [ ] Title ≤90 characters
- [ ] Main text ≤5,000 words
- [ ] References ≤50
- [ ] Reporting Summary (Nature PDF form) completed and attached
- [ ] Preregistration statement present (even if not preregistered)
- [ ] Extended Data labeled "Extended Data Fig. N" and cited in text
- [ ] Code available on GitHub + Zenodo (NCS: non-negotiable)

### Nature Reporting Summary Template (NHB / NCS / Nature)

Required for ALL Nature-family submissions. Auto-generate from manuscript:

**Study Design**:
- Study type: [Observational / Experimental / Computational / Meta-analysis]
- Sample size: [N = X] with justification: [power analysis / census / full population]
- Data exclusions: [criteria, N excluded, percentage]
- Replication: [independent replication attempted? Results consistent?]
- Randomization: [method used, or "N/A — observational"]
- Blinding: [analyst blinded to treatment? Or "N/A"]

**Statistical Parameters**:
- Test(s) used: [OLS, logistic regression, etc.]
- Exact p-values reported: [YES — all p-values exact, not thresholded]
- Confidence intervals: [95% CIs reported for all key estimates]
- Effect sizes: [Cohen's d / OR / RR / AME with CIs]
- Multiple comparisons: [correction method used, or "single primary outcome"]

**Data & Code Availability**:
- Data: [Public repository URL] or [Available upon request — justification]
- Code: [GitHub/Zenodo URL with DOI]
- Materials: [Survey instruments / interview protocols available at URL]

**Ethics**:
- IRB approval: [Institution, protocol number]
- Informed consent: [obtained / waived — justification]
- AI tools used: [Claude Code for data analysis — see AI Use Disclosure]

**Computational Methodology** (NCS only):
- Hardware: [GPU type, CPU, RAM]
- Software versions: [R 4.3.2, Python 3.11, etc.]
- Random seeds: [set and reported]
- Runtime: [approximate total computation time]

**PNAS**:
- [ ] Significance statement (125 words, layperson-accessible) present
- [ ] Within 6-page limit (with figures embedded)
- [ ] Two classification fields selected

---

## Step 8: Save Output

Use the **Write tool** to save the submission package files.

### Version Collision Avoidance (MANDATORY)

**Before EVERY Write tool call below**, run this Bash block to determine the correct save path. Do NOT hardcode paths from the filename templates — they show naming patterns only.

```bash
# MANDATORY: Replace [values] with actuals before running
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
# BASE pattern: ${OUTPUT_ROOT}/[slug]/submission/scholar-journal-report-[journal]-[topic-slug]-[YYYY-MM-DD]
# Split into directory and stem for the gate script:
OUTDIR="$(dirname "${OUTPUT_ROOT}/[slug]/submission/scholar-journal-report-[journal]-[topic-slug]-[YYYY-MM-DD]")"
STEM="$(basename "${OUTPUT_ROOT}/[slug]/submission/scholar-journal-report-[journal]-[topic-slug]-[YYYY-MM-DD]")"
mkdir -p "$OUTDIR"
bash "${SCHOLAR_SKILL_DIR:-.}/scripts/gates/version-check.sh" "$OUTDIR" "$STEM"
```

**Use the printed `SAVE_PATH` as `file_path` in the Write tool call.** Re-run this block (with the appropriate BASE) for each additional file (cover letter, open science declarations). The same version suffix must be used for all related output files (.md, .docx, .tex, .pdf).

---

### File 1 — Submission Readiness Report

**Filename**: `output/[slug]/submission/scholar-journal-report-[journal]-[topic-slug]-[YYYY-MM-DD].md`

```markdown
# Submission Readiness Report
## Journal: [journal] | Paper: [title / slug] | Date: [YYYY-MM-DD]

### Journal Selected
- Target journal: [name]
- Paper type: [article / note / letter]
- Mode: [FULL-PACKAGE / FORMAT-CHECK / RESUBMIT]

### Word Count Audit
| Section | Current | Allowed | Status |
|---------|---------|---------|--------|
| Total text | [N] | [limit] | [PASS/FAIL] |
| Abstract | [N] | [limit] | [PASS/FAIL] |
| Introduction | [N] | ~[range] | [OK/LONG/SHORT] |
| Theory/Background | [N] | ~[range] | [OK/LONG/SHORT] |
| Methods | [N] | ~[range] | [OK/LONG/SHORT] |
| Results | [N] | ~[range] | [OK/LONG/SHORT] |
| Discussion | [N] | ~[range] | [OK/LONG/SHORT] |

### Compliance Checklist Summary
- PASS: [N] items
- FAIL: [list failing items]
- N/A: [N] items

### Top Issues to Resolve Before Submission
1. [Critical issue 1]
2. [Critical issue 2]
3. [Issue 3]

### Open Science Declarations
- Data availability: [statement drafted / not yet / N/A]
- Code availability: [statement drafted / not yet / N/A]
- Preregistration: [yes: DOI / not preregistered: stated]
- CRediT: [completed / not yet]
- COI: [drafted / none declared]
- IRB: [statement present / not applicable]

### Reporting Summary
- Required: [yes/no for this journal]
- Status: [completed / pending]

### Submission System
- URL: [submission system URL]
- Estimated review time: [range from Step 3]
- APC: [amount / none / N/A]
```

---

### File 2 — Cover Letter Draft

**Filename**: `output/[slug]/submission/scholar-journal-cover-letter-[journal]-[topic-slug]-[YYYY-MM-DD].md`

[Full cover letter draft from Step 5]

---

### File 3 — Open Science Declarations

**Filename**: `output/[slug]/submission/scholar-journal-open-science-[topic-slug]-[YYYY-MM-DD].md`

```markdown
# Open Science Declarations: [Paper Title]
## [YYYY-MM-DD]

### Data Availability Statement
[From Step 4]

### Code Availability Statement
[From Step 4]

### Preregistration Statement
[From Step 4]

### Author Contributions (CRediT)
[Completed CRediT table from Step 4]

### Competing Interests
[From Step 4]

### IRB / Ethics Statement
[From Step 4]
```

Confirm all three file paths to user at end.

**Close Process Log:**

Run the following to finalize the process log:

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
SKILL_NAME="scholar-journal"
LOG_DATE=$(date +%Y-%m-%d)
LOG_FILE="${OUTPUT_ROOT}/logs/process-log-${SKILL_NAME}-${LOG_DATE}.md"
if [ ! -f "$LOG_FILE" ]; then
  LOG_FILE=$(ls -t "${OUTPUT_ROOT}"/logs/process-log-${SKILL_NAME}-${LOG_DATE}*.md 2>/dev/null | head -1)
fi
cat >> "$LOG_FILE" << LOGFOOTER

## Output Files
[list each output file path as a bullet]

## Summary
- **Steps completed**: [N completed]/[N total]
- **Files produced**: [count]
- **Errors**: [count, or 0]
- **Time finished**: $(date +%H:%M:%S)
LOGFOOTER
echo "Process log saved to $LOG_FILE"
```

---

## Quality Checklist

- [ ] **Journal correctly identified** and mode dispatched accordingly
- [ ] **Journal selection** (if SELECT-JOURNAL mode): scoring rubric applied; ranked list produced
- [ ] **Word count** within limit — section-by-section audit completed
- [ ] **Section order** matches journal's required structure
- [ ] **Abstract** correct format (structured vs. unstructured; word limit met)
- [ ] **Title** within character limit (NHB/NCS: ≤90 chars)
- [ ] **Citation style** correct throughout (ASA / Chicago / APA / numbered)
- [ ] **Reference list** complete and consistent with in-text citations
- [ ] **Figure/table count** within limit; figures at correct resolution
- [ ] **Blind review compliance**: no identifying information in blinded submission
- [ ] **Causal language consistency**: cover letter and submission materials use the same language as the manuscript — if manuscript uses "is associated with," cover letter must too (not "our study shows X causes Y"). See scholar-write SKILL.md for the full causal language rule
- [ ] **Data availability statement** drafted for target journal
- [ ] **Code availability statement** drafted (mandatory: NHB, NCS, Science Advances, PNAS)
- [ ] **Preregistration statement** present (mandatory for NHB/NCS)
- [ ] **Reporting Summary** identified as required / not required for this journal
- [ ] **CRediT** author contributions completed (mandatory: Nature journals, AAAS)
- [ ] **COI statement** drafted
- [ ] **IRB statement** present if human subjects
- [ ] **Cover letter** drafted with journal-specific framing and contribution language
- [ ] **Supplement** organized according to journal's labeling conventions
- [ ] **Submission readiness report saved** to `output/[slug]/submission/`
- [ ] **Cover letter saved** to `output/[slug]/submission/`
- [ ] **Open science declarations saved** to `output/[slug]/submission/`

---

See [references/top-journals.md](references/top-journals.md) for quick-reference specs, acceptance rates, impact factors, submission system URLs, and journal ladder routing for all 22 covered journals.
