# Scholar-Write Article Assets Index

This index catalogs all example articles in `assets/`. The `scholar-write` skill reads this file at write-time to select relevant examples, then uses `pdftotext` to extract text from selected PDFs for style calibration.

**Assets directory**: `.claude/skills/scholar-write/assets/` (relative to project root)

## How to Use This Index

1. Identify the paper's **research domain**, **method**, and **target journal**
2. Select 1–2 **example-articles/** entries that match the domain/method — read for voice, framing, and contribution style
3. Select 1–2 **top-journal-articles/** entries that match the journal standard — read for structural depth and rigor level
4. Extract text: `pdftotext "[ASSETS_DIR]/[subfolder]/[filename]" - | head -250`

---

## Your Articles (`example-articles/`)

Add your own published papers here. These serve as **personal style and voice reference** — how you frame puzzles, state contributions, integrate methods, and write for different journals.

To populate this section:
1. Copy your published PDFs into `assets/example-articles/`
2. Add entries to the table below following this format:

| Filename | Citation | Journal | Method | Topics | Best for |
|----------|---------|---------|--------|--------|---------|
| `your-paper.pdf` | Author (Year) | **Journal** | Methods used | Key topics | What writing style this exemplifies |

---

## Top Journal Examples (`top-journal-articles/`)

Add published work from top journals in your field here. Use as **structural and rigor reference** — the depth of theory, density of literature, precision of methods, and level of contribution expected.

To populate this section:
1. Copy exemplar PDFs into `assets/top-journal-articles/`
2. Add entries to the table below

| Filename | Citation | Journal | Method | Topics | Best for |
|----------|---------|---------|--------|--------|---------|
| `example-paper.pdf` | Author (Year) | **Journal** | Methods used | Key topics | What writing style this exemplifies |

---

## Quick Selection Guide

**Total assets**: Your articles (voice + framing) + top-journal exemplars (structure + rigor)

| Paper type | Use your article | Use top-journal article |
|-----------|-----------------|------------------------|
| Quantitative sociology | Pick closest match by method | ASR/AJS/Demography exemplars |
| Computational / NLP | Pick closest match by method | NHB/NCS/Science Advances exemplars |
| Qualitative / mixed-methods | Pick closest match by approach | Target journal exemplars |
| Applied linguistics | Pick closest match by subfield | Target journal exemplars |
