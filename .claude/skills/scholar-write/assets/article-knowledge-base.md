# Article Knowledge Base for Scholar-Write

Pre-extracted structured annotations for all articles in the asset library. Built to eliminate per-session pdftotext calls — use this file to find the right exemplars instantly, then read only the PDFs you actually need.

**Last updated**: [DATE]
**Coverage**: Your articles + top-journal exemplars
**Assets base path**: `.claude/skills/scholar-write/assets/`

---

## How to Use

1. Identify target journal + section + paper type
2. Search this file (Ctrl-F) by journal name, method keyword, or topic
3. Select 1–2 of your articles (voice) + 1–2 top-journal entries (structure)
4. Note the `**Opening line**`, `**Gap sentence**`, and `**Contribution claim**` fields — these are verbatim quotes
5. For deeper reading: `pdftotext "[path]/[file]" - | head -300`
6. For verbatim section quotes by rhetorical function: see `section-snippets.md`

---

## Empirical Section Word Counts by Journal

Use these as calibration targets when drafting — they reflect what journals actually publish, not theoretical guidelines.

### Summary Table (averages from published papers)

| Journal | Introduction | Theory/Lit Review | Data & Methods | Results | Discussion/Conclusion | Total body |
|---------|-------------|-------------------|----------------|---------|----------------------|------------|
| ASR | 2,500–4,000 | 1,000–1,500 (often integrated into Intro) | 1,500–2,500 | 2,000–4,000 | 1,500–2,500 | 10,000–14,000 |
| AJS | 2,500–5,000 | 1,000–1,500 (often integrated into Intro) | 1,500–2,500 | 2,000–4,000 | 1,500–2,500 | 10,000–16,000 |
| Demography | 1,500–2,500 | 600–1,000 | 1,500–2,500 | 2,000–3,500 | 1,000–2,000 | 8,000–12,000 |
| Social Forces | 2,000–3,500 | 800–1,200 | 1,200–2,000 | 1,800–3,000 | 1,200–2,000 | 8,000–12,000 |
| Science Advances | 800–1,500 | 300–600 (integrated) | 800–1,500 | 1,000–2,000 | 500–1,000 | 3,500–6,500 |
| NHB | 600–1,200 | 200–400 (integrated) | 600–1,200 | 800–1,500 | 400–800 | 3,000–5,000 |
| NCS | 400–800 | 200–400 (integrated) | 600–1,000 | 600–1,200 | 300–600 | 2,500–4,000 |

**Important structural note:** Many ASR/AJS papers (~50%) have NO separate Theory section — they integrate literature review and theory into a long Introduction (often 5,000–16,000 words). When this pattern is used, the Introduction budget should be 4,000–8,000 and the Theory row is absorbed. The budgets above assume a SEPARATE Theory section exists. When drafting, decide the structure first, then allocate accordingly.

---

## Your Articles (`example-articles/`)

To populate this section, add entries following this template for each of your papers:

### Author (Year) — Journal
**File**: `filename.pdf`
**Journal**: Journal Name | **Year**: YYYY
**Method**: Methods used
**Topics**: Key topics, research areas
**Hook type**: [empirical-puzzle | conceptual-gap | policy-hook | counter-intuitive | methodological-advance]
**Opening line**: "Verbatim first sentence..."
**Gap sentence**: "Verbatim gap/puzzle statement..."
**Contribution claim**: "Verbatim contribution statement..."
**Voice register**: [e.g., Formal-analytical with accessible framing; precise but not jargon-heavy]
**Sentence architecture**: [e.g., Complex-compound with enumeration; topic sentences anchor each paragraph]
**Paragraph rhythm**: [e.g., 4–6 sentences; alternates evidence and interpretation]

---

## Top Journal Examples (`top-journal-articles/`)

To populate this section, add entries following the same template above for each exemplar paper you add.
