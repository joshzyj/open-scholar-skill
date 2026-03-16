# Source Integrity Protocol

**MANDATORY** for all skills that summarize, cite, or draft text based on published literature: `scholar-lit-review`, `scholar-lit-review-hypothesis`, `scholar-hypothesis`, `scholar-write`.

This protocol has two parts: **Anti-Plagiarism** (during drafting) and **Claim Accuracy** (post-draft verification).

---

## Part A: Anti-Plagiarism Rules (Apply DURING Drafting)

### A1 — Absolute Rules

1. **Every sentence summarizing a source must be in your own words.** Do NOT reproduce phrases from papers — not from memory, not from PDFs, not from the knowledge base. Rephrase the idea using different sentence structure and vocabulary.

2. **Direct quotes require quotation marks + page number.** If an exact phrase is essential (e.g., a coined term like "strength of weak ties"), use `"quoted phrase" (Author Year, p. N)`. Limit direct quotes to ≤2 per 1,000 words.

3. **No patchwork paraphrasing.** Changing 1–2 words in a sentence while keeping the same structure is still plagiarism. You must change BOTH the words AND the sentence structure.

4. **Coined terms and frameworks are not plagiarism.** Using established terms like "cultural capital," "intersectionality," or "ecological fallacy" without quotes is fine — these are shared disciplinary vocabulary. But the sentence around them must be original.

5. **Section snippets are structural templates only.** When using `section-snippets.md` or `article-knowledge-base.md`, adopt the *rhetorical move* (e.g., "open with a puzzle," "pivot to the gap"), never the actual words.

### A2 — Self-Check Before Saving Any Draft

Before saving any literature-based output (lit review, theory section, hypothesis rationale, introduction), perform this check:

**For each paragraph that summarizes published work:**
1. Read each sentence aloud — does it sound like something YOU wrote, or something you read?
2. Check for distinctive phrases (≥5 consecutive content words) that may come from a source. If uncertain, rephrase.
3. Verify that no two consecutive sentences follow the same structure as the source being cited.

**Flag format:** If a sentence cannot be confidently declared original, mark it:
```
[REPHRASE NEEDED: may echo SOURCE_AUTHOR YEAR — rewrite before submission]
```

### A3 — Hedging and Precision

When summarizing findings from literature:
- Use hedging language appropriate to the original study's claims: "found an association" not "proved" or "showed that X causes Y" (unless the study is causal)
- Attribute clearly: "According to Author (Year)..." or "Author (Year) argued that..." — not just a parenthetical at the end of a claim
- Distinguish between what the author *argued* vs. what they *found* vs. what others *interpreted*

---

## Part B: Claim Accuracy Rules (Post-Draft Verification)

### B1 — Mandatory Claim Check

After drafting any text that attributes specific findings to published sources, verify each factual claim before saving output. This is NOT optional.

**For every cited empirical claim, verify:**

| Check | What to verify | Example |
|-------|---------------|---------|
| **Direction** | Is the effect positive/negative as stated? | "Zhang (2020) found a negative association" — is it really negative? |
| **Population** | Is the population/sample correctly described? | "using NLSY data" — did the paper actually use NLSY? |
| **Method** | Is the method correctly attributed? | "using fixed effects" — did they actually use FE? |
| **Magnitude** | If effect sizes are mentioned, are they approximately correct? | "a 15% reduction" — is it really ~15%? |
| **Conclusion** | Does the author actually draw the conclusion you attribute to them? | "concluded that X causes Y" — did they actually make a causal claim? |

### B2 — Verification Procedure

For each cited claim, attempt verification in this order:

**Tier 1 — Zotero PDF (highest confidence):**
```bash
# Re-derive Zotero path (shell vars don't persist across calls)
ZOTERO_DIR="${SCHOLAR_ZOTERO_DIR:-}"
if [ -z "$ZOTERO_DIR" ]; then
  for d in "$HOME/Zotero" "$HOME/Library/CloudStorage/"*/zotero "$HOME/Library/CloudStorage/"*/Zotero; do
    [ -f "$d/zotero.sqlite" ] && ZOTERO_DIR="$d" && break
  done
fi
# Search for the paper
DB="/tmp/zotero_verify.sqlite"
cp "$ZOTERO_DIR/zotero.sqlite" "$DB" 2>/dev/null
STORAGE="$ZOTERO_DIR/storage"
# Find PDF key for author+year
sqlite3 "$DB" "SELECT key FROM items WHERE itemID IN (
  SELECT itemID FROM itemData JOIN itemDataValues USING(valueID)
  WHERE LOWER(value) LIKE '%AUTHOR_KEYWORD%'
) AND itemTypeID=14 LIMIT 1;"
# Extract text from PDF
pdftotext "$STORAGE/[KEY]/[FILENAME].pdf" - | head -500
```
Read the abstract and results section. Confirm the claim matches.

**Tier 2 — Semantic Scholar / OpenAlex API:**
If no local PDF, query the API for the paper's abstract and verify the claim against it.

**Tier 3 — Flag as unverified:**
If the claim cannot be verified against any source:
```
[CLAIM UNVERIFIED: "Author (Year) found X" — could not confirm from source; verify before submission]
```

### B3 — Claim Verification Report

After verification, append a claim check summary to the output file:

```markdown
## Source Integrity Check
- **Claims checked**: [N]
- **Verified against PDF**: [N]
- **Verified against API**: [N]
- **Unverified (flagged)**: [N]
- **Corrected**: [N] (list corrections made)
- **Direct quotes used**: [N] (all with page numbers: YES/NO)
```

### B4 — Common Hallucination Patterns to Watch For

Claude is especially prone to these errors when summarizing literature:
1. **Inverted effect direction** — stating a positive association when the paper found negative (or vice versa)
2. **Wrong dataset** — attributing PSID findings to NLSY, or Census findings to ACS
3. **Conflated authors** — mixing up findings from Author A's paper with Author B's
4. **Fabricated statistics** — citing specific percentages, coefficients, or sample sizes that aren't in the paper
5. **Overclaiming causality** — saying "showed that X causes Y" when the paper only found a correlation
6. **Wrong year** — citing Author 2019 when the paper was published in 2021
7. **Ghost papers** — citing papers that don't exist at all (caught by citation verification, but claim check catches misattributed *real* papers)

**Rule:** When in doubt about any specific number, effect direction, or sample detail — do NOT include it. Use general language ("found a significant association") rather than risk a fabricated specific ("found a 23% increase").

---

## Part C: Multi-Agent Verification Panel (Post-Draft)

After drafting is complete and Parts A–B have been applied inline, run a **3-agent independent verification panel** using the Task tool. Each agent works in a fresh context with no knowledge of the others' findings. Results are then cross-validated.

### C1 — Agent Definitions

| Agent | Role | Focus |
|-------|------|-------|
| **Originality Auditor** | Plagiarism detection | Scans every paragraph that summarizes published work. Flags: (1) distinctive phrases ≥5 consecutive content words that likely come from a source, (2) patchwork paraphrasing (same sentence structure with minor word swaps), (3) unquoted direct lifts, (4) suspiciously uniform prose register that doesn't match the author's voice elsewhere in the draft |
| **Claim Verifier** | Factual accuracy | For every cited empirical claim, verifies direction, population, method, magnitude, and conclusion against the source (Zotero PDF → Semantic Scholar/OpenAlex abstract → flag). Checks the 7 common hallucination patterns (B4). Produces per-claim SUPPORTED / AMBIGUOUS / UNSUPPORTED / UNVERIFIED verdict |
| **Attribution Analyst** | Citation–claim alignment | Checks whether each citation actually supports the specific claim it's attached to. Detects: (1) citations that exist but don't support the stated claim, (2) claims attributed to the wrong author, (3) overclaimed causality vs. correlation, (4) mismatched dates/datasets, (5) orphaned claims with no citation |

### C2 — Dispatch Protocol

Spawn all 3 agents **in parallel** using the Task tool. Each agent receives:
1. The full draft text being verified
2. The list of all cited references (with Zotero keys if available)
3. Access to `$SCHOLAR_ZOTERO_DIR` for PDF verification
4. Instructions to work independently and produce a structured report

**Task prompt template for each agent:**

```
You are the [AGENT_ROLE] agent in a Source Integrity verification panel.

Your task: Read the draft at [DRAFT_PATH] and independently audit it for [FOCUS_AREA].

Instructions:
- Work through the draft paragraph by paragraph
- For each issue found, record: paragraph number, the problematic text, the issue type, severity (HIGH/MEDIUM/LOW), and your recommended fix
- Do NOT assume the draft is correct — verify independently
- If Zotero is available at [ZOTERO_DIR], use pdftotext to cross-check against source PDFs
- Produce your findings as a structured markdown table

Save your report to: ${OUTPUT_ROOT}/logs/source-integrity-[AGENT_ID]-[DATE].md
```

### C3 — Cross-Validation Protocol

After all 3 agents complete, **cross-validate** their findings:

**Step C3.1 — Collect reports:**
Read all 3 agent reports from `${OUTPUT_ROOT}/logs/source-integrity-{originality,claims,attribution}-[DATE].md`.

**Step C3.2 — Build agreement matrix:**

For each flagged issue, check how many agents independently flagged it:

| Agreement Level | Meaning | Action |
|----------------|---------|--------|
| **3/3 agents agree** | High-confidence issue | **MUST FIX** before saving output — auto-correct or flag as `[INTEGRITY ISSUE — 3/3 agents]` |
| **2/3 agents agree** | Likely issue | **SHOULD FIX** — review and fix if confirmed; flag as `[INTEGRITY WARNING — 2/3 agents]` if uncertain |
| **1/3 agents flag** | Possible false positive | **REVIEW** — include in report but do not auto-flag in draft unless the single agent's evidence is compelling |

**Step C3.3 — Produce consolidated report:**

```markdown
## Source Integrity Panel Report

### Panel Summary
- **Agents dispatched**: 3 (Originality Auditor, Claim Verifier, Attribution Analyst)
- **Total issues found**: [N]
- **3/3 consensus (MUST FIX)**: [N]
- **2/3 consensus (SHOULD FIX)**: [N]
- **1/3 only (REVIEW)**: [N]

### Consensus Issues (3/3)
| # | Paragraph | Issue | Type | Agents | Fix Applied |
|---|-----------|-------|------|--------|-------------|
| 1 | ¶4 | "social capital facilitates..." echoes Putnam (2000) verbatim | Plagiarism | OA+CV+AA | Rephrased |

### Majority Issues (2/3)
| # | Paragraph | Issue | Type | Agents | Action |
|---|-----------|-------|------|--------|--------|
| 1 | ¶12 | Zhang (2019) cited as finding negative effect; PDF shows positive | Claim accuracy | CV+AA | Corrected direction |

### Single-Agent Flags (1/3)
| # | Paragraph | Issue | Type | Agent | Disposition |
|---|-----------|-------|------|-------|-------------|
| 1 | ¶7 | Sentence structure similar to Smith (2021) | Possible patchwork | OA | Reviewed — acceptable paraphrase |

### Corrections Applied
- [List each correction: what was changed, from what, to what, which agents flagged it]

### Remaining Flags
- [List any `[REPHRASE NEEDED]`, `[CLAIM UNVERIFIED]`, or `[INTEGRITY WARNING]` markers still in the draft]
```

Save to: `${OUTPUT_ROOT}/logs/source-integrity-panel-[SLUG]-[DATE].md`

### C4 — When to Run the Panel

| Context | Panel Required? | Notes |
|---------|----------------|-------|
| `scholar-lit-review` | **YES** — after Step 7 (synthesis drafting) | Run before saving final landscape map |
| `scholar-hypothesis` | **YES** — after theory section draft | Run before saving theory output |
| `scholar-lit-review-hypothesis` | **YES** — after integrated draft | Run before saving combined output |
| `scholar-write` (Introduction, Theory, Discussion) | **YES** — after section draft | Run before Step 5 internal review panel |
| `scholar-write` (Methods, Results) | NO — these sections report original analysis | Skip unless heavily citing methods literature |

---

## Integration Points

### During Drafting (scholar-lit-review, scholar-hypothesis, scholar-write)
- Apply Part A rules to every paragraph as you write
- Flag uncertain phrasings with `[REPHRASE NEEDED]`
- Flag unverifiable claims with `[CLAIM UNVERIFIED]`

### Post-Draft (before saving output)
1. Run Part B claim check on all empirical claims
2. **Run Part C multi-agent verification panel** (3 parallel Task agents: Originality Auditor, Claim Verifier, Attribution Analyst)
3. Cross-validate agent findings using the agreement matrix (C3.2)
4. Apply all 3/3 consensus fixes; review and apply 2/3 majority fixes
5. Append Source Integrity Check summary (B3) + Panel Report (C3.3) to output
6. Count of `[REPHRASE NEEDED]`, `[CLAIM UNVERIFIED]`, and `[INTEGRITY WARNING]` markers must be reported to user

---

## Notes

- This protocol complements (does not replace) `scholar-citation`'s 7-tier citation verification, which checks whether references *exist*. This protocol checks whether the *claims attributed to them* are accurate.
- This protocol complements (does not replace) `scholar-ethics` MODE 2 plagiarism check, which is a post-submission audit. This protocol prevents plagiarism *during* drafting.
- When Zotero PDFs are not available, verification confidence is lower. Always note the verification tier in the report.
