# General Research Ethics Standards

Reference guide for `scholar-ethics` MODE 4.

---

## 1. Foundational Ethics Documents

| Document | Scope | Key principles |
|----------|-------|----------------|
| **Belmont Report (1979)** | US human subjects research | Respect for persons, Beneficence, Justice |
| **Common Rule (45 CFR 46)** | US federally funded research with humans | IRB review, informed consent requirements |
| **Declaration of Helsinki (WMA)** | Medical and biomedical research | Participant welfare > science; independent ethics committee |
| **GDPR (2018)** | EU data protection | Lawfulness, purpose limitation, data minimization, accuracy, storage limitation, security |
| **ICMJE Recommendations** | Biomedical journal authorship | 4 authorship criteria; disclosure of conflicts |
| **COPE Guidelines** | Publication ethics | Plagiarism, authorship, peer review, corrections, retractions |
| **ASA Code of Ethics (2018)** | Sociological research | Professional integrity, conflict of interest, data sharing, authorship |
| **APA Ethics Code** | Psychology research | Honesty, fidelity, justice, respect for rights |

---

## 2. IRB Review Types (US — Common Rule)

### Exempt Research (45 CFR 46.104)
Does not require continuing IRB review. Categories relevant to social science:

| Category | Description |
|----------|-------------|
| Cat. 1 | Normal educational practices in established institutions |
| Cat. 2 | Anonymous surveys, public observation (no sensitive topics, no identifiers) |
| Cat. 3 | Benign behavioral interventions (no deception, minimal risk) |
| Cat. 4 | Secondary research using identifiable data, if publicly available or DUA with protections |
| Cat. 5 | Research by federal agencies on public benefit programs |
| Cat. 6 | Taste/food quality evaluations |

**Cat. 4 exemption criteria** (commonly used for administrative data / secondary analysis):
- Data originally collected for non-research purposes, OR
- Data previously collected under IRB oversight where consent authorized this use, AND
- Data is publicly available OR protected by a confidentiality agreement that prohibits re-identification

### Expedited Review
Single IRB reviewer; appropriate for minimal risk research:
- Cat. (6): Voice, video, digital recordings
- Cat. (7): Research on individual or group characteristics or behavior (surveys, interviews, focus groups, program evaluation, human factors evaluation, quality assurance) **without sensitive topics**

### Full Board Review
Entire IRB committee reviews. Required when:
- Greater than minimal risk
- Vulnerable populations (prisoners, children, pregnant women, cognitively impaired)
- Sensitive topics (illegal behavior, sexual behavior, psychologically sensitive)
- Possibility of coercion in recruitment
- Deception that could cause significant distress

---

## 3. Informed Consent: Required Elements

**Basic elements (45 CFR 46.116(b)):**
1. Statement that the study involves research; explanation of the purpose; expected duration; description of procedures
2. Description of any reasonably foreseeable risks or discomforts
3. Description of any reasonably expected benefits to the subject or others
4. Disclosure of appropriate alternative procedures or courses of treatment
5. Statement describing confidentiality of records, any limits of confidentiality
6. Explanation of compensation or treatment if injury occurs (if applicable)
7. Contact information (researcher + IRB)
8. Statement that participation is voluntary; right to withdraw without penalty

**Additional elements when applicable:**
- Whether unforeseeable risks may exist
- Circumstances under which participation may be terminated without consent
- Any additional costs to participant
- Consequences of withdrawal
- Statement that significant new findings will be shared
- Approximate number of subjects involved

### Online Consent Best Practices
- Use a clear, readable consent preamble (not just a legal boilerplate)
- Include checkbox: "I have read the above and agree to participate"
- Prevent survey access if consent not given
- Store consent records (timestamp, IP hash where permitted)
- For anonymous surveys: "By completing this survey you are indicating your consent to participate"

---

## 4. Authorship Standards

### ICMJE Criteria (4 conditions — ALL must be met for authorship credit)
1. **Substantial contribution** to conception/design OR data collection OR analysis/interpretation
2. **Drafting** or critically **revising** the manuscript for important intellectual content
3. **Final approval** of the version to be submitted/published
4. **Accountability**: agreement to be accountable for all aspects of the work (can investigate and resolve accuracy/integrity questions)

### Common authorship violations
| Issue | Description | Resolution |
|-------|-------------|-----------|
| **Ghost authorship** | Individual who made substantial contribution is not listed | Include all contributors meeting ICMJE criteria |
| **Gift / honorary authorship** | Author listed for prestige / reciprocity, not contribution | Remove; use Acknowledgments for non-author contributions |
| **Coercive authorship** | PI demands authorship without meeting criteria | Follow ICMJE; report to RIO if coercion is serious |
| **Author order disputes** | Disagreement on first/last author | Agree in writing at project start; first = primary contribution; last = senior supervisor |

### Non-author contributions: Acknowledgments
Individuals who contributed but do not meet all four ICMJE criteria should be acknowledged (not listed as authors):
- Research assistants (data collection, coding)
- Statistical consultants
- Lab technicians
- Participants
- Funders (separate conflict-of-interest disclosure)

### CRediT Taxonomy (14 roles)
See SKILL.md Step 4.3 for full role descriptions.

**Template for Nature submission:**
> Author contributions: [A.B.]: Conceptualization, Funding acquisition, Writing — original draft. [C.D.]: Formal analysis, Software, Visualization. [E.F.]: Data curation, Investigation. [A.B. and C.D.]: Writing — review & editing.

---

## 5. Conflict of Interest Policies

### What constitutes a conflict of interest (COI)?

**Financial COI:**
- Employment, consulting, or advisory role with an organization that has a stake in the research
- Stocks, equity, or ownership interest in relevant organizations (except mutual funds)
- Honoraria, speaking fees, or travel reimbursement from interested parties
- Patents, royalties, or licensing fees related to the research topic
- Research grants or contracts from industry sponsors with potential bias

**Intellectual/Professional COI:**
- Strong prior public advocacy for a specific outcome (blog posts, op-eds, testimony)
- Personal relationship with journal editor or editorial board
- Prior review of the same manuscript for another journal
- Competitor relationship with authors being cited

### ASA Code of Ethics on COI (Section 16)
Sociologists must disclose all sources of financial support in reports of research and, when possible, any personal or professional relationship with organizations sponsoring the research.

### Handling COI as author
1. Disclose at submission (most journals have a COI declaration form)
2. Describe the nature of the relationship specifically
3. State explicitly that the funder/interested party had no role in study design, data collection, analysis, interpretation, or submission decision
4. If COI is substantial (e.g., employee of the company whose product is studied), consider whether independent replication is needed

### Handling COI as reviewer
- Decline to review if you have a personal or financial relationship with any author
- Decline to review if you are at the same institution as any author
- Decline to review a competitor's paper if you are working on a directly competing project
- Disclose any potential COI to the editor and let the editor decide

---

## 6. Data Sharing Ethics

### Ethical obligations vs. practical constraints

| Situation | Obligation | Mechanism |
|-----------|-----------|-----------|
| Publicly funded research (NSF, NIH) | Strong expectation/requirement | Repository deposit (Zenodo, OSF, ICPSR) |
| Proprietary / licensed data (PSID, NLSY, ACS restricted) | Share code + metadata; access memo | Code repository + instructions for data access |
| IRB-restricted (identifiable interviews) | Share de-identified or aggregate version | Anonymized extracts + full code |
| Commercially sensitive data | Share what the contract allows; code only | Code repository with data description |
| Fully proprietary (cannot share at all) | Explain in data availability statement | Statement noting confidentiality constraints |

### FAIR Data Principles
- **F**indable: persistent identifier, rich metadata
- **A**ccessible: open protocol, authenticated access where needed
- **I**nteroperable: standard format, uses standard vocabulary
- **R**eusable: license, provenance, detailed documentation

### Data repositories for social science

| Repository | Best for | License options |
|------------|----------|----------------|
| **Harvard Dataverse** | Sociology, political science; institutional hosting | CC0, CC-BY |
| **ICPSR** (icpsr.umich.edu) | Large social science datasets; restricted access tiers | Various |
| **OSF** (osf.io) | Code + data + preprints; pre-registration | CC0, CC-BY |
| **Zenodo** (zenodo.org) | Code + data; DOI issued; GitHub integration | CC0, CC-BY, MIT, GPL |
| **Qualitative Data Repository** (qdr.syr.edu) | Qualitative data (interviews, fieldnotes) with consent management | Tiered access |
| **UK Data Service** | UK and European social science data | Restricted/open |

### Anonymization vs. de-identification

| Level | What is removed | Re-identification risk |
|-------|----------------|----------------------|
| **Direct identifiers removed** (de-identified) | Name, SSN, DOB, address | Low but possible via rare attribute combination |
| **Cell suppression** | Small-N cells with < 5 observations | Low with proper k-anonymization |
| **Synthetic data** | All real values replaced by statistically similar synthetic values | Very low; no real individual's data |
| **Aggregate only** | Only group-level statistics released | Very low; original microdata not released |

---

## 7. Ethics in Computational and AI-Assisted Research

### Lin & Zhang (2025) Four-Risk Framework for LLM Annotation

When using LLMs to code/annotate data (relevant to `scholar-compute` and `scholar-ling`):

| Risk type | Description | Mitigation |
|-----------|-------------|-----------|
| **Validity** | LLM labels may not capture intended theoretical construct | Human validation sample (200+ items, κ > .70 vs. LLM) |
| **Reliability** | LLM output varies run-to-run | Set temperature = 0; run twice; report run-to-run κ |
| **Replicability** | Prompt and model version not archived | Archive exact prompt, model version, date; include in appendix |
| **Transparency** | Black-box annotations cannot be audited | Publish all prompts; provide sample of LLM annotations |

### Ethical use of LLMs in social science

| Use | Ethical status | Required disclosure |
|-----|---------------|-------------------|
| Code generation (cleaning, analysis) | ✓ Acceptable | Brief note in Methods |
| Grammar/style editing of manuscript | ✓ Acceptable | Disclose per journal policy |
| Literature summarization (non-primary) | ✓ Acceptable with verification | Verify all claims |
| Data annotation / coding at scale | ✓ Acceptable with validation | Full validation protocol in Methods |
| Generating synthetic survey responses | ✓ Acceptable as supplement | Must not present as real participant data |
| Drafting primary argument without author revision | ✗ Not acceptable | — |
| Generating fabricated citations | ✗ Not acceptable (research misconduct) | — |

### Algorithm and AI Fairness

If the research uses ML models for prediction or classification of social outcomes:
- [ ] Assess differential performance by demographic group (race, gender, age)
- [ ] Report precision, recall, and F1 by subgroup
- [ ] Discuss potential for disparate impact if model is deployed
- [ ] Cite relevant fairness literature (Barocas, Hardt & Narayanan 2023 "Fairness and Machine Learning")

---

## 8. Social Science Professional Codes of Ethics

### American Sociological Association (ASA) Code of Ethics 2018 — Key Sections

**Section 10 — Research and Publication:**
- Report research findings honestly and without fabrication
- Disclose all relevant aspects of research, including procedures that might affect interpretations
- Report findings irrespective of results (do not selectively report)
- Acknowledge all persons who contributed to research
- Do not list authors who did not contribute; do not omit authors who did

**Section 13 — Confidentiality:**
- Protect confidential information given in professional relationships
- Store data with participant identifiers under secure conditions
- Destroy identifiers when they are no longer required

**Section 14 — Publication and Authorship:**
- Publish findings only once (no duplicate publication)
- Credit all contributors appropriately
- Acknowledge data sources
- Correct the record if errors are discovered post-publication

### Association of Internet Researchers (AoIR) Ethics Guidelines (2019)

For online and social media research:

| Principle | Application |
|-----------|------------|
| **Context matters** | Apply contextual integrity: was data shared in a context where reuse is expected? |
| **Vulnerability** | Even "public" data can harm vulnerable groups when aggregated |
| **Minimal harm** | Avoid collecting more data than needed; anonymize where possible |
| **Transparency** | Disclose research purpose when feasible |
| **Ongoing consent** | For longitudinal online data, reassess consent at each wave |

### Key question: Is internet data "public"?

| Platform / Data type | Typically "public" | Notes |
|---------------------|-------------------|-------|
| Twitter/X public posts (non-DMs) | Yes | But aggregation can harm; re-ID risk; check ToS |
| Reddit public posts in public subreddits | Yes | r/depression, r/SuicideWatch = sensitive; use aggregate only |
| Facebook public posts | Context-dependent | Most users expect limited audience even if technically public |
| LinkedIn public profiles | Yes | Professional context; professional use expected |
| Private group posts | No | Do not scrape; not intended as public |
| Direct messages | No | Never research DMs without explicit consent |
| User-generated content with clear audience expectation | Assess contextually | Apply contextual integrity principle |
