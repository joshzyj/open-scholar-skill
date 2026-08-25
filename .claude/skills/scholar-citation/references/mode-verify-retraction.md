# MODE 5: VERIFY — Citation Verification Against Databases

**Input:** Draft manuscript or reference list (with existing citations/references to verify)

**Purpose:** Systematically verify that EVERY reference in the manuscript actually exists by checking against the local reference library (Zotero/Mendeley/BibTeX/EndNote), CrossRef API, and WebSearch. Produces a verification report with per-entry status.

## Step V-0: Extract All References

Parse the reference list (or in-text citations if no reference list) to create a structured inventory:

```
REFERENCE INVENTORY:
| # | Author(s) | Year | Title (first 10 words) | Journal/Book | DOI | Status |
|---|-----------|------|------------------------|--------------|-----|--------|
| 1 | Smith, John A. | 2020 | "Title of article..." | ASR | doi:10.xxx | PENDING |
| 2 | Jones, Mary B. | 2019 | "Another title..." | AJS | — | PENDING |
...
```

## Step V-1: Local Reference Library Verification (Tier 1 — highest trust)

For each reference, search all detected local backends (Zotero, Mendeley, BibTeX, EndNote) using the unified dispatcher:

```bash
# Re-load reference manager (shell state lost between Bash calls)
SKILL_DIR="${SCHOLAR_SKILL_DIR:-.}/.claude/skills"
eval "$(cat "$SKILL_DIR/_shared/refmanager-backends.md" | sed -n '/^```bash/,/^```/p' | sed '1d;$d')" 2>/dev/null

# Title keyword match (use first 3-5 distinctive title words)
scholar_search "TITLE_KEYWORDS" 5 keyword

# Author match
scholar_search "AUTHOR_LASTNAME" 5 author
```

**Local library match criteria:**
- Author last name matches (exact or close)
- Year matches (exact or ±1 for publication lag)
- Title contains key distinctive words (≥3 word overlap)
- If ALL match → status = `VERIFIED-LOCAL(source)` where source = zotero|mendeley|bibtex|endnote-xml
- If author+year match but title differs → flag for manual review
- Also cross-check: volume, pages, DOI if available in the local library

## Step V-2: CrossRef Verification (Tier 2)

For references NOT verified via Zotero, query CrossRef:

```bash
# By DOI (fastest, most reliable if DOI is available)
curl -sL "https://api.crossref.org/works/DOI_HERE?mailto=$CROSSREF_EMAIL" \
  | python3 -c "
import json, sys
data = json.load(sys.stdin)
item = data.get('message', {})
print('Title:', item.get('title', [''])[0])
authors = item.get('author', [])
names = [f\"{a.get('family','')}, {a.get('given','')[:1]}.\" for a in authors]
print('Authors:', '; '.join(names))
pub = item.get('published-print', item.get('published-online', {}))
date_parts = pub.get('date-parts', [['']])[0]
print('Year:', date_parts[0] if date_parts else '')
print('Journal:', item.get('container-title', [''])[0])
print('Volume:', item.get('volume',''))
print('Issue:', item.get('issue',''))
print('Pages:', item.get('page',''))
print('DOI:', item.get('DOI',''))
print('Type:', item.get('type',''))
"
```

```bash
# By title + author (when DOI unavailable)
curl -s "https://api.crossref.org/works?query.bibliographic=TITLE+KEYWORDS&query.author=AUTHOR_LAST&rows=3&mailto=$CROSSREF_EMAIL" \
  | python3 -c "
import json, sys
data = json.load(sys.stdin)
for item in data.get('message', {}).get('items', []):
    print('---')
    print('Title:', item.get('title', [''])[0])
    authors = item.get('author', [])
    names = [f\"{a.get('family','')}, {a.get('given','')[:1]}.\" for a in authors]
    print('Authors:', '; '.join(names))
    pub = item.get('published-print', item.get('published-online', {}))
    date_parts = pub.get('date-parts', [['']])[0]
    print('Year:', date_parts[0] if date_parts else '')
    print('Journal:', item.get('container-title', [''])[0])
    print('Volume:', item.get('volume',''))
    print('Pages:', item.get('page',''))
    print('DOI:', item.get('DOI',''))
    score = item.get('score', 0)
    print('Match score:', score)
"
```

**CrossRef match criteria:**
- Author last name present in author list
- Year matches (exact)
- Title similarity ≥ 80% (check key distinctive words)
- If ALL match → status = `VERIFIED-CROSSREF`
- If match found but metadata differs → status = `CORRECTED-CROSSREF` (note discrepancy: e.g., year off by 1, volume number differs)
- Also capture: correct DOI, volume, pages for metadata correction

## Step V-2.5: Semantic Scholar + OpenAlex Verification (Tier 2b/2c)

For references NOT verified via local library or CrossRef, query Semantic Scholar and OpenAlex:

```bash
# Re-load reference manager (shell state lost between Bash calls)
SKILL_DIR="${SCHOLAR_SKILL_DIR:-.}/.claude/skills"
eval "$(cat "$SKILL_DIR/_shared/refmanager-backends.md" | sed -n '/^```bash/,/^```/p' | sed '1d;$d')" 2>/dev/null

# Semantic Scholar — by DOI (if available)
scholar_verify_semanticscholar_doi "DOI_HERE"

# Semantic Scholar — by title keywords
scholar_search_semanticscholar_keyword "TITLE KEYWORDS" 5

# OpenAlex — by DOI (if available)
scholar_verify_openalex_doi "DOI_HERE"

# OpenAlex — by title keywords
scholar_search_openalex_keyword "TITLE KEYWORDS" 5
```

**Semantic Scholar advantages:** Better coverage for preprints, working papers, CS/social science crossover papers, and citation graph data.

**OpenAlex advantages:** Open metadata for 250M+ works, open access status, institutional affiliations, broader coverage of non-English publications.

**Match criteria:** Same as CrossRef (author + year + title match). Status labels:
- `VERIFIED-S2` — confirmed via Semantic Scholar
- `VERIFIED-OPENALEX` — confirmed via OpenAlex

## Step V-2.7: Google Scholar Verification (Tier 2d)

For references NOT verified via local library, CrossRef, Semantic Scholar, or OpenAlex, query Google Scholar:

```bash
# Re-load reference manager (shell state lost between Bash calls)
SKILL_DIR="${SCHOLAR_SKILL_DIR:-.}/.claude/skills"
eval "$(cat "$SKILL_DIR/_shared/refmanager-backends.md" | sed -n '/^```bash/,/^```/p' | sed '1d;$d')" 2>/dev/null

# Google Scholar — by title + author keywords
scholar_search_google_scholar "AUTHOR TITLE KEYWORDS" 3

# Or verify a specific paper
scholar_verify_google_scholar "EXACT TITLE" "AUTHOR LAST NAME"
```

**Google Scholar advantages:** Broadest academic coverage — books, theses, dissertations, working papers, non-English publications, government reports, and conference proceedings often missing from CrossRef/OpenAlex. Also provides citation counts.

**Match criteria:** Same as CrossRef (author + year + title match). Status label:
- `VERIFIED-GSCHOLAR` — confirmed via Google Scholar

**Rate limit warning:** Google Scholar may return CAPTCHA for rapid consecutive requests. Insert 2-second delays between calls. Use sparingly — best for targeted verification, not bulk discovery.

## Step V-3: WebSearch Verification (Tier 3 — last resort)

For references NOT verified via Zotero, CrossRef, Semantic Scholar, OpenAlex, or Google Scholar (e.g., very recent publications, niche reports, datasets, policy briefs):

```
WebSearch query: "[Author Last Name] [Year] [First 5 Title Words] [Journal/Publisher if known]"
```

**Targeted search patterns for higher hit rates:**

```
WebSearch: "Author LastName" "Year" "First 5 Title Words" site:scholar.google.com
WebSearch: "Author LastName" "Book Title" site:books.google.com
WebSearch: "Author LastName" "Title" site:ssrn.com OR site:osf.io OR site:arxiv.org
WebSearch: "DOI" site:doi.org OR site:journals.sagepub.com OR site:academic.oup.com
WebSearch: "Report Title" "Year" site:gov OR site:census.gov OR site:bls.gov
```

Verify that WebSearch results confirm:
- The publication exists (found on publisher site, Google Scholar, library catalog, or repository)
- Author name matches
- Year matches
- Title matches (substantially)

**WebSearch match criteria:**
- Found on authoritative source (publisher website, Google Scholar, WorldCat, institutional repository, SSRN, SocArXiv, arXiv, government website)
- Author + year + title all confirmed
- If ALL match → status = `VERIFIED-WEB`
- If partially matched → status = `PARTIALLY-VERIFIED` (note what could/couldn't be confirmed)

## Step V-3.5: Claim Verification (MANDATORY — runs for all verified references)

After confirming that each reference exists (Tiers 1–3), verify that the manuscript's prose claims about each cited source are accurate — i.e., that when the manuscript says "Smith (2020) found X," Smith (2020) actually found X. This step catches mischaracterized findings, wrong directionality, overstated effects, unsupported causal language, and claims applied to the wrong population or context.

**This step is MANDATORY, not optional.** Citation fabrication and citation mischaracterization are equally damaging to scholarly integrity. A real paper cited for a claim it doesn't make is as misleading as a fabricated paper. It runs as Step V-3.5 in every VERIFY execution — not only when a flag is passed.

### Step V-3.5a: Extract prose claims

Parse the manuscript for every sentence or clause that attributes a specific finding, argument, or conclusion to a cited source. Extract structured claim records:

```
CLAIM INVENTORY:
| # | Manuscript text (verbatim) | Cited paper | Claim type | Claim content |
|---|---------------------------|-------------|------------|---------------|
| 1 | "Smith (2020) found that X increases Y" | Smith 2020 | empirical finding | X increases Y |
| 2 | "Following Jones's (2019) argument that..." | Jones 2019 | theoretical argument | [argument] |
| 3 | "Using the method developed by Lee (2018)..." | Lee 2018 | method attribution | [method] |
```

**Claim types to extract:**
- **Empirical finding**: "found that", "showed that", "demonstrated", "reported", "observed"
- **Theoretical argument**: "argues that", "contends", "theorizes", "proposes", "following X's framework"
- **Method attribution**: "using the method developed by", "following the approach of"
- **Directional claim**: "positive/negative association", "increases/decreases", "more/less likely"
- **Magnitude claim**: specific numbers, effect sizes, percentages attributed to a source
- **Population/scope claim**: "among [population]", "in [context]", claims about where a finding applies
- **Causal claim**: "causes", "leads to", "produces", "results in" — verify the cited paper actually makes a causal claim vs. showing correlation

### Step V-3.5a2: Resolve write-time Evidence Ledger anchors (fast path — before KG)

When the manuscript carries `<!--ev: anchor_id-->` tags (written by lit-review/scholar-write/INSERT per `_shared/evidence-ledger.md`), resolve each tagged claim's anchor_ids against `${PROJ}/evidence/claim-anchors.ndjson` FIRST. The anchor gives you the exact passage the author relied on (`evidence_quote` + `source_loc`), its access tier, and its honesty class (`evidence_form`):
- A `source_verbatim` T1/T2 anchor whose quote entails the claim → verify against that passage directly (record the anchor_id in the audit record's `anchor_refs[]`).
- A `kg_paraphrase` or `metadata_only`/`T3` anchor → the write-time evidence was weak: **escalate these claims to a KG/PDF read first** — they are the highest-risk pool.
- Anchors are leads, not verdicts: the verdict always comes from what the retrieved text actually says.

### Step V-3.5b: Look up cited papers in Knowledge Graph (Tier 0 — fastest)

Before reading PDFs, check the knowledge graph for pre-extracted findings, mechanisms, and theories:

```bash
SKILL_DIR="${SCHOLAR_SKILL_DIR:-.}/.claude/skills"
KG_REF="$SKILL_DIR/scholar-knowledge/references/knowledge-graph-search.md"
if [ -f "$KG_REF" ]; then
  eval "$(cat "$KG_REF" | sed -n '/^```bash/,/^```/p' | sed '1d;$d')" 2>/dev/null
fi

# Search by DOI or title
kg_get_paper "[DOI]"
# Or by author + title keyword
kg_search_papers "[AUTHOR TITLE_KEYWORDS]" 3
```

If the cited paper is in the knowledge graph with `extraction_tier: "full_pdf"` or `"abstract_only"`, compare the manuscript's claim against the paper's `findings[]`, `mechanisms[]`, `theories[]`, `methods[]`, and `populations[]` fields.

**KG-based claim check (fast path — no PDF read needed):**
1. Match the manuscript claim to the KG paper's extracted fields
2. Check: Does any finding[] entry support the specific claim?
3. Check: Does the directionality match? (positive vs. negative, increases vs. decreases)
4. Check: Does the population/context match the paper's populations[]?
5. Check: If the manuscript uses causal language, does the paper's methods[] support causal inference? (e.g., "causes" is only justified if the paper used RCT, IV, DiD, RD, or similar)
6. If KG data is sufficient to verify → assign status and move to next claim
7. If KG data is insufficient or ambiguous → fall through to PDF verification

### Step V-3.5c: PDF-based verification (Tier 1 — for claims not resolvable via KG)

For claims that cannot be verified from the knowledge graph (paper not in KG, or KG data insufficient), read the cited paper's PDF:

```bash
SKILL_DIR="${SCHOLAR_SKILL_DIR:-.}/.claude/skills"
eval "$(cat "$SKILL_DIR/_shared/refmanager-backends.md" | sed -n '/^```bash/,/^```/p' | sed '1d;$d')" 2>/dev/null

# Search for the paper to get Zotero storage key
scholar_search "AUTHOR_LASTNAME TITLE_KEYWORDS" 3 keyword
```

```bash
# Extract text from PDF — abstract + intro + results + discussion
ZOTERO_DIR="${SCHOLAR_ZOTERO_DIR:-$HOME/Zotero}"
PDF_PATH="$ZOTERO_DIR/storage/[KEY]/[FILENAME]"
if [ -f "$PDF_PATH" ]; then
  # First pass: abstract + intro (first 150 lines)
  pdftotext -q "$PDF_PATH" - | head -150
fi
```

```bash
# Second pass: results + discussion (where findings live)
if [ -f "$PDF_PATH" ]; then
  TOTAL_LINES=$(pdftotext -q "$PDF_PATH" - | wc -l | tr -d ' ')
  # Read the last 40% (typically Results through Conclusion)
  START=$((TOTAL_LINES * 60 / 100))
  pdftotext -q "$PDF_PATH" - | tail -n +${START} | head -300
fi
```

**Read strategically based on claim type:**
- Empirical finding → focus on Results and Discussion sections (last 40% of paper)
- Theoretical argument → focus on Introduction and Theory/Literature Review (first 30%)
- Method attribution → focus on Methods/Data section (middle 30%)
- Magnitude claim → search for specific numbers in Results tables and text

### Step V-3.5d: Verification logic and status assignment

For each claim, assign one of these statuses:

| Status | Meaning | Action |
|--------|---------|--------|
| `CLAIM-VERIFIED` | Paper content confirms the claim as stated in the manuscript | No action needed |
| `CLAIM-IMPRECISE` | Paper supports the general direction but manuscript overstates, understates, or simplifies | Flag for author revision with specific correction |
| `CLAIM-MISCHARACTERIZED` | Paper's finding is meaningfully different from what the manuscript claims | **Flag as error** — manuscript must be corrected |
| `CLAIM-UNSUPPORTED` | Paper does not address this specific claim at all | **Flag as error** — wrong citation or fabricated claim |
| `CLAIM-REVERSED` | Paper finds the opposite direction of what the manuscript claims | **Flag as critical error** — immediate correction required |
| `CLAIM-OVERCAUSAL` | Manuscript uses causal language but paper reports only correlation/association | Flag for language correction |
| `CLAIM-WRONG-POPULATION` | Paper studied a different population than what the manuscript attributes | Flag for scope correction |
| `CLAIM-NOT-A-CLAIM` | Sentence cites a source but attributes no checkable finding/argument/method to it (e.g., background mention) | No action — not a factual attribution |
| `CLAIM-NOT-CHECKABLE` | No PDF available and not in KG; claim cannot be verified | Log and note in report |

**IMPORTANT — Insert markers inline in the manuscript draft.** For all statuses except `CLAIM-VERIFIED` and `CLAIM-NOT-A-CLAIM`, insert a bracketed marker adjacent to the problematic claim in the manuscript text itself (not just in the report). Format: `[CLAIM-REVERSED: Author Year — paper finds opposite direction]`. These inline markers are what `scripts/gates/verify-claims.sh` scans for. Without inline markers, the gate cannot detect errors.

**IMPORTANT — Emit an audit record for EVERY adjudicated claim, including `CLAIM-VERIFIED`.** Markers persist only the defects; without positive records a verified claim is indistinguishable from an unchecked one and a skipped V-3.5 pass is indistinguishable from a passing one. Append one `claim-audit-record/v1` line per (sentence, citation) pair to `${PROJ}/evidence/claim-faithfulness-audit-[YYYY-MM-DD].ndjson` (schema: `schema/claim-audit-record.schema.json`; fields incl. verbatim sub-claim `evidence_quote`s, `access_tier`, `anchor_refs[]` from Step V-3.5a2, and `claim_fingerprint` = sha256 of the normalized comment-stripped sentence). After the pass: write the audit filename to `${PROJ}/evidence/LATEST-audit.txt`, validate with `bash scripts/gates/check-claim-audit-consistency.sh <audit-file>` (fix any violation), and re-render the Evidence Dossier (`python3 scripts/render-evidence-dossier.py --proj "$PROJ" --out <version-checked evidence/evidence-dossier-*.md path> --draft <manuscript>`) so verdicts appear beside the passages.

For a deeper sentence-level audit (or to offload this entire step), dispatch the `verify-claim-faithfulness` agent — it implements the same sub-claim decomposition and tier chain described in V-3.5a–d against the identical schema. When dispatched, consume its artifact instead of re-deriving these steps manually; do not double-write the audit file.

**Decision rules:**
1. **Directional match**: If the manuscript says "X increases Y" but the paper found "X decreases Y" → `CLAIM-REVERSED`
2. **Causal inflation**: If the paper uses "associated with" / "correlated with" but the manuscript says "causes" / "leads to" → `CLAIM-OVERCAUSAL`
3. **Population mismatch**: If the paper studied "US adults" but the manuscript says "across all Western democracies" → `CLAIM-WRONG-POPULATION`
4. **Magnitude mismatch**: If the manuscript cites a specific number (β = 0.45) that doesn't appear in the paper → `CLAIM-MISCHARACTERIZED`
5. **Finding attribution**: If the paper's main finding is about topic A but the manuscript cites it for topic B → `CLAIM-UNSUPPORTED`
6. **Theoretical misattribution**: If the manuscript says "following Smith's (2020) theory of X" but Smith proposes theory of Y → `CLAIM-MISCHARACTERIZED`
7. **Hedging mismatch**: If the paper says "suggestive evidence" but the manuscript says "strong evidence" → `CLAIM-IMPRECISE`

### Step V-3.5e: Claim verification report

Append to the main verification report:

```
CLAIM VERIFICATION REPORT
─────────────────────────────────────────────────
Total prose claims checked: [N]

CLAIM-VERIFIED:           [N] ([%])  — claim accurately represents cited source
CLAIM-IMPRECISE:          [N] ([%])  — mostly correct but overstated/simplified
CLAIM-MISCHARACTERIZED:   [N] ([%])  — meaningfully different from source
CLAIM-UNSUPPORTED:        [N] ([%])  — source doesn't address this claim
CLAIM-REVERSED:           [N] ([%])  — source contradicts the claim direction
CLAIM-OVERCAUSAL:         [N] ([%])  — causal language for correlational finding
CLAIM-WRONG-POPULATION:   [N] ([%])  — population/context mismatch
CLAIM-NOT-CHECKABLE:      [N] ([%])  — no PDF/KG data available

Verified via Knowledge Graph: [N]
Verified via PDF:             [N]
─────────────────────────────────────────────────

ERRORS REQUIRING CORRECTION:

  [#]. CLAIM-REVERSED: "[manuscript text]" — citing [Author Year]
       Manuscript says: [X increases Y]
       Paper actually found: [X decreases Y]
       Evidence (VERBATIM): "[exact source passage that contradicts the claim]"
       Source: [PDF p.N / KG findings[] — access tier T0/T1/T2/T3] | anchors: [anchor_ids or none]
       → CORRECTION NEEDED: [suggested fix]

  [#]. CLAIM-MISCHARACTERIZED: "[manuscript text]" — citing [Author Year]
       Manuscript says: [claim]
       Paper actually says: [what the paper says]
       Evidence (VERBATIM): "[exact source passage]"
       Source: [PDF p.N / KG — access tier] | anchors: [anchor_ids or none]
       → CORRECTION NEEDED: [suggested fix]

  [#]. CLAIM-OVERCAUSAL: "[manuscript text]" — citing [Author Year]
       Manuscript says: "[causes / leads to / produces]"
       Paper's method: [OLS / cross-sectional / correlational]
       → CORRECTION: Change to "[is associated with / correlates with]"

WARNINGS (author should review):

  [#]. CLAIM-IMPRECISE: "[manuscript text]" — citing [Author Year]
       Manuscript says: [overstated version]
       Paper actually says: [more nuanced version]
       → SUGGESTED REVISION: [more precise wording]

  [#]. CLAIM-WRONG-POPULATION: "[manuscript text]" — citing [Author Year]
       Manuscript implies: [broader population]
       Paper studied: [specific population]
       → SUGGESTED REVISION: [scope-qualified wording]

NOT CHECKABLE:

  [#]. [Author Year] — no PDF available, not in knowledge graph
       Claim: "[manuscript text]"
       → Author must manually verify this claim against the source
─────────────────────────────────────────────────
```

### Step V-3.5f: File corrections back to Knowledge Graph

If claim verification revealed that a paper's findings were different from what the KG had recorded (or the KG was missing key details), update the knowledge graph:

```bash
SKILL_DIR="${SCHOLAR_SKILL_DIR:-.}/.claude/skills"
KG_REF="$SKILL_DIR/scholar-knowledge/references/knowledge-graph-search.md"
if [ -f "$KG_REF" ]; then
  eval "$(cat "$KG_REF" | sed -n '/^```bash/,/^```/p' | sed '1d;$d')" 2>/dev/null
  # Update paper's findings if corrections found during PDF reading
  # This feeds the cross-skill loop: future claim checks benefit from richer KG data
fi
```

This feedback loop means each VERIFY run enriches the knowledge graph, making future claim checks faster and more accurate (more papers resolvable via KG fast path, fewer requiring slow PDF reads).

**Note:** This step does NOT replace metadata verification (Tiers 1–3). It supplements by checking content relevance.

## Step V-4: Unverified Reference Handling

For any reference that FAILS all three tiers:

1. **Flag as UNVERIFIED:** `**[UNVERIFIED: Author Year — not found in Zotero, CrossRef, Google Scholar, or WebSearch]**`
2. **Do NOT include in the final reference list** unless the user explicitly confirms
3. **Suggest alternatives:** If a similar-but-different source was found during verification, suggest it as a replacement
4. **Log the failure:** Record in audit log with all queries attempted

**Decision matrix:**
| Local Library | CrossRef | S2 | OpenAlex | WebSearch | Status | Action |
|---------------|----------|----|----------|-----------|--------|--------|
| Match | — | — | — | — | VERIFIED-LOCAL(source) | Include as-is |
| — | Match | — | — | — | VERIFIED-CROSSREF | Include; update metadata if corrections found |
| — | — | Match | — | — | VERIFIED-S2 | Include; note S2-only verification |
| — | — | — | Match | — | VERIFIED-OPENALEX | Include; note OpenAlex-only verification |
| — | — | — | — | Match | VERIFIED-WEB | Include; note web-only verification |
| — | Partial | Partial | — | — | PARTIALLY-VERIFIED | Include with warning; author must confirm |
| No | No | No | No | No | UNVERIFIED | REMOVE from list; flag as **[UNVERIFIED]** |
| Match | Mismatch | — | — | — | CORRECTED | Include local version; note discrepancy |

## Step V-5: Metadata Correction

During verification, if authoritative sources reveal metadata errors in the manuscript's references, correct them:

- **Wrong year:** Update to verified year (e.g., preprint year → publication year)
- **Wrong volume/pages:** Update from CrossRef/Zotero
- **Missing DOI:** Add DOI from CrossRef
- **Author name spelling:** Correct from CrossRef/Zotero
- **Preprint → published:** If a cited preprint has since been published, update to published version
- **Journal name:** Correct to official title (no abbreviation errors)

Log all corrections in the audit log.

## Step V-6: Verification Report

Produce a structured verification report:

```
CITATION VERIFICATION REPORT
─────────────────────────────────────────────────
Total references checked: [N]

VERIFIED-LOCAL:      [N] ([%])  — found in local reference library (Zotero/Mendeley/BibTeX/EndNote)
VERIFIED-CROSSREF:   [N] ([%])  — confirmed via CrossRef API
VERIFIED-S2:         [N] ([%])  — confirmed via Semantic Scholar API
VERIFIED-OPENALEX:   [N] ([%])  — confirmed via OpenAlex API
VERIFIED-WEB:        [N] ([%])  — confirmed via WebSearch
CORRECTED:           [N] ([%])  — verified but metadata corrected
PARTIALLY-VERIFIED:  [N] ([%])  — partial match; requires author confirmation
UNVERIFIED:          [N] ([%])  — NOT FOUND in any database

─────────────────────────────────────────────────
VERIFIED REFERENCES:
  1. Smith (2020) — VERIFIED-LOCAL — "Title..." ASR 85(3):412–35
  2. Jones (2019) — VERIFIED-CROSSREF — "Title..." AJS 124(4):1102–48
  ...

CORRECTED REFERENCES:
  3. Williams (2018) — CORRECTED-CROSSREF
     Original: Williams 2018, vol. 42
     Corrected: Williams 2019, vol. 43 (publication lag)
  ...

PARTIALLY-VERIFIED (require author confirmation):
  4. Lee (2021) — PARTIALLY-VERIFIED
     Found matching author+title on SSRN but year shows 2022
     Author must confirm correct year
  ...

UNVERIFIED (REMOVED from reference list):
  5. [Author] ([Year]) — UNVERIFIED
     Queries attempted: Zotero keyword="...", CrossRef title="...", WebSearch="..."
     No matching source found in any database
     Suggested alternative: [if any similar source was found]
  ...
─────────────────────────────────────────────────
```

## Step V-7: Save Verification Output

Save the verification report as part of the audit log (File 2). If running standalone:

Path: `output/[slug]/citations/scholar-citation-[slug]-[date]-verification.md`

Contents include the full verification report from Step V-6 plus:
- All Zotero queries run (with result counts)
- All CrossRef queries run (with DOIs found)
- All WebSearch queries run (with confirmation URLs)
- Metadata corrections applied
- Unverified references removed
- Suggested replacements for unverified items

---

# MODE 7: RETRACTION-CHECK — Cross-Reference Against Retraction Watch

**Input:** Draft manuscript with reference list (or standalone reference list)

**Purpose:** Check every cited work against the Retraction Watch database to identify retracted papers. Flag retracted citations, provide retraction details, and suggest replacement citations where possible.

## Step R-1: Extract Reference List

Parse all references from the manuscript (same parsing as MODE 2 AUDIT Step A-1). Extract: authors, year, title, journal, DOI.

## Step R-2: Query Retraction Watch Database

For each reference, query the Retraction Watch API (via CrossRef retraction metadata and the Retraction Watch database):

```bash
# Method 1: CrossRef — check if DOI has "update-to" with type "retraction"
check_retraction_crossref() {
  local DOI="$1"
  curl -sL "https://api.crossref.org/works/$DOI" | python3 -c "
import json, sys
data = json.load(sys.stdin)
item = data.get('message', {})
updates = item.get('update-to', [])
for u in updates:
    if u.get('type') == 'retraction':
        print(f'RETRACTED: {u.get(\"updated\",{}).get(\"date-parts\",[[\"unknown\"]])[0]}')
        print(f'Label: {u.get(\"label\",\"retraction\")}')
        sys.exit(0)
# Also check if the article itself is a retraction notice
if 'retraction' in item.get('type', '').lower():
    print('THIS IS A RETRACTION NOTICE')
    sys.exit(0)
print('CLEAR')
"
}

# Method 2: Retraction Watch API (http://retractiondatabase.org/RetractionSearch.aspx)
# Query by title keywords or DOI
check_retraction_rw() {
  local TITLE="$1"
  # URL-encode the title
  ENCODED=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$TITLE'))")
  curl -s "http://api.retractiondatabase.org/api/v1/search?query=$ENCODED" | python3 -c "
import json, sys
data = json.load(sys.stdin)
results = data.get('results', [])
if results:
    for r in results:
        print(f'RETRACTED: {r.get(\"RetractionDate\",\"unknown\")}')
        print(f'Reason: {r.get(\"Reason\",\"not specified\")}')
        print(f'Original DOI: {r.get(\"OriginalPaperDOI\",\"\")}')
else:
    print('CLEAR')
"
}
```

## Step R-3: CrossRef "Is Retracted" Field Check

```bash
# Bulk check using CrossRef filter for retracted works
check_retraction_bulk() {
  local DOIS="$1"  # comma-separated DOIs
  curl -s "https://api.crossref.org/works?filter=doi:$DOIS&mailto=$CROSSREF_EMAIL" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for item in data.get('message',{}).get('items',[]):
    doi = item.get('DOI','')
    # Check update-to field
    retracted = False
    for u in item.get('update-to', []):
        if 'retract' in u.get('type','').lower():
            retracted = True
    # Check if marked as retracted in CrossRef
    if item.get('is-retracted', False):
        retracted = True
    status = 'RETRACTED' if retracted else 'CLEAR'
    print(f'{doi}\t{status}')
"
}
```

## Step R-4: Generate Retraction Report

For each retracted citation found:

1. **Flag in manuscript**: Replace the citation with `**[RETRACTED — Author Year]**` marker
2. **Retraction details**: Record date of retraction, reason (if available), retraction notice DOI
3. **Suggest replacements**: Search Zotero + CrossRef + Semantic Scholar for:
   - The same finding replicated in a non-retracted paper
   - A systematic review or meta-analysis covering the same topic
   - The closest methodologically similar paper by different authors
4. **Assess impact**: Classify how the retracted citation was used:
   - **Critical** (supports a key claim or hypothesis) — must replace or remove claim
   - **Supporting** (one of several citations for the claim) — remove citation, others suffice
   - **Peripheral** (background/context only) — remove citation, no claim impact

## Step R-5: Save Retraction Report

Path: `output/[slug]/citations/scholar-citation-[slug]-[date]-retraction-report.md`

```markdown
# Retraction Check Report — [slug] — [date]

## Summary
- Total references checked: [N]
- References with DOIs checked via CrossRef: [N]
- References checked via Retraction Watch: [N]
- **Retracted papers found: [N]**
- Replacement citations suggested: [N]

## Retracted Citations

### [Author (Year)] — [Title]
- **DOI:** [doi]
- **Retraction date:** [date]
- **Reason:** [reason from Retraction Watch]
- **Retraction notice:** [DOI or URL of retraction notice]
- **Usage in manuscript:** [Critical / Supporting / Peripheral]
- **Claim affected:** "[quoted claim from manuscript]"
- **Suggested replacement(s):**
  1. [Author (Year)] — [Title] — [DOI] — [verification status]
  2. ...

## Clear References
- [N] references checked — no retraction flags found
```
