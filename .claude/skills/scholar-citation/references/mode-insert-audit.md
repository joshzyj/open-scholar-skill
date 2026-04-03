# MODE 1: INSERT — Add Citations to Uncited Draft

**Input:** Draft section text (may contain `[citation needed]` markers or none at all)

## Step I-1: Claim Inventory

Read the draft carefully. Identify every empirical claim, statistical fact, theoretical assertion, or methodological claim that requires citation. Create an inventory:

```
CLAIM INVENTORY:
1. "[exact claim text]" — type: empirical fact | theory | method | statistic
2. "[exact claim text]" — ...
...
```

Distinguish:
- **Must cite:** empirical findings, statistics, original theories, methodological choices
- **May cite:** well-established background facts (Marx said X), logical deductions
- **Skip:** purely logical transitions, author's own framing

## Steps I-2 through I-4: Iterative Search-Insert Loop

**Design**: Instead of a single pass, citation insertion runs as an iterative loop. Each round searches for citations for remaining uncited claims, inserts what it finds, and re-scans for gaps. This catches claims that only become apparent as context from inserted citations clarifies the text.

**Maximum rounds**: 3 (most drafts converge in 1-2 rounds).

**Cache file**: `${OUTPUT_ROOT}/citations/citation-cache-$(date +%Y-%m-%d).json` — stores resolved claim-to-citation mappings so that interrupted runs can resume without re-querying APIs.

### I-2.0: Initialize or Load Cache

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
CACHE_FILE="${OUTPUT_ROOT}/citations/citation-cache-$(date +%Y-%m-%d).json"
mkdir -p "${OUTPUT_ROOT}/citations"
if [ -f "$CACHE_FILE" ]; then
  echo "Resuming from cache: $CACHE_FILE ($(python3 -c "import json; print(len(json.load(open('$CACHE_FILE'))))" 2>/dev/null || echo 0) entries)"
else
  echo '{}' > "$CACHE_FILE"
  echo "Initialized empty citation cache: $CACHE_FILE"
fi
```

Before searching for any claim, check the cache first. If a claim's exact text (or a normalized form) already has a resolved citation in the cache, skip the search and use the cached result.

---

### Round Structure (repeat up to 3 times)

**For each round N (1, 2, 3):**

#### I-2: Local Reference Library Search

For each **unresolved claim** (not yet cited and not in cache), search all detected local reference backends (Zotero, Mendeley, BibTeX, EndNote) using the unified dispatcher:

```bash
# Re-load reference manager (shell state lost between Bash calls)
SKILL_DIR="${SCHOLAR_SKILL_DIR:-.}/.claude/skills"
eval "$(cat "$SKILL_DIR/scholar-citation/references/refmanager-backends.md" | sed -n '/^```bash/,/^```/p' | sed '1d;$d')" 2>/dev/null

# Keyword search across all detected backends
scholar_search "KEYWORD" 15 keyword | scholar_format_citations
```

Run multiple searches per claim varying keywords. For author-specific queries:

```bash
# Re-load reference manager (shell state lost between Bash calls)
SKILL_DIR="${SCHOLAR_SKILL_DIR:-.}/.claude/skills"
eval "$(cat "$SKILL_DIR/scholar-citation/references/refmanager-backends.md" | sed -n '/^```bash/,/^```/p' | sed '1d;$d')" 2>/dev/null

# Author last name search across all detected backends
scholar_search "LASTNAME" 20 author | scholar_format_citations
```

#### I-3: External API Fallback (for items not in local library)

If local library search yields no match, query external APIs in order: CrossRef (2a) → Semantic Scholar (2b) → OpenAlex (2c).

**Tier 2a — CrossRef API:**

```bash
# CrossRef lookup by title keywords (URL-encode spaces as +)
curl -s "https://api.crossref.org/works?query=TITLE+KEYWORDS&filter=type:journal-article&rows=5&mailto=$CROSSREF_EMAIL" \
  | python3 -c "
import json, sys
data = json.load(sys.stdin)
for item in data.get('message', {}).get('items', []):
    print('---')
    print('Title:', item.get('title', [''])[0])
    authors = item.get('author', [])
    names = [f\"{a.get('family','')}, {a.get('given','')[:1]}.\" for a in authors]
    print('Authors:', '; '.join(names))
    pub = item.get('published-print', {}).get('date-parts', [['']])[0]
    print('Year:', pub[0] if pub else '')
    print('Journal:', item.get('container-title', [''])[0])
    print('Volume:', item.get('volume',''))
    print('Issue:', item.get('issue',''))
    print('Pages:', item.get('page',''))
    print('DOI:', item.get('DOI',''))
"
```

For author + year lookup:

```bash
curl -s "https://api.crossref.org/works?query.author=AUTHOR_LAST&query=KEYWORDS&filter=from-pub-date:YEAR,until-pub-date:YEAR&rows=5&mailto=$CROSSREF_EMAIL" \
  | python3 -c "import json,sys; [print(i.get('title',[''])[0], i.get('DOI','')) for i in json.load(sys.stdin)['message']['items']]"
```

**Tier 2b — Semantic Scholar API** (for preprints, working papers, conference papers not in CrossRef):

```bash
# Search Semantic Scholar by title keywords
QUERY="TITLE+KEYWORDS"
curl -s "https://api.semanticscholar.org/graph/v1/paper/search?query=$QUERY&fields=title,year,authors,externalIds,venue&limit=5" \
  | python3 -c "
import json, sys
data = json.load(sys.stdin)
for p in data.get('data', []):
    authors = '; '.join(a.get('name','') for a in p.get('authors', [])[:5])
    doi = p.get('externalIds', {}).get('DOI', '')
    print(f\"{authors} ({p.get('year','')}). {p.get('title','')}. {p.get('venue','')}. DOI: {doi}\")
"
```

**Tier 2c — OpenAlex API** (broadest coverage, 250M+ works):

```bash
# Search OpenAlex by title keywords
QUERY="TITLE+KEYWORDS"
curl -s "https://api.openalex.org/works?search=$QUERY&per_page=5&mailto=$CROSSREF_EMAIL" \
  | python3 -c "
import json, sys
data = json.load(sys.stdin)
for w in data.get('results', []):
    authors = '; '.join(a.get('author',{}).get('display_name','') for a in w.get('authorships', [])[:5])
    print(f\"{authors} ({w.get('publication_year','')}). {w.get('title','')}. {w.get('primary_location',{}).get('source',{}).get('display_name','')}. DOI: {w.get('doi','')}\")
"
```

**IMPORTANT:** Only insert a citation if at least one API returns a match. If no API confirms the reference exists, use `[SOURCE NEEDED]` instead of guessing.

#### I-4: Citation Matching and Insertion

For each claim, select the best-matching source(s):
- **Quality hierarchy:** Published peer-reviewed > Accepted preprint > Working paper > Report
- **Recency:** Prefer seminal + recent (within 5 years) over only-old citations
- **Fit:** Source must actually support the specific claim
- **Parsimony:** One strong citation > three weak ones for undisputed facts

Insert citations using target style format. For numbered styles, assign numbers in order of first appearance and track a running list.

**Citation stacking rules:**
- ≤ 2 sources: sufficient for most empirical claims
- 3–5 sources: appropriate for broad theoretical claims or contested empirics
- > 5: only for comprehensive reviews or meta-analyses

**SOURCE NEEDED protocol:**
```
**[SOURCE NEEDED: requires empirical evidence for claim that X → Y; search: "mechanism X Y sociology"]**
```

#### I-4b: Update Cache and Check Convergence

After inserting citations for this round, update the cache file:

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
CACHE_FILE="${OUTPUT_ROOT}/citations/citation-cache-$(date +%Y-%m-%d).json"
# Write resolved mappings (claim text → citation key) to the cache
# Use python3 to merge new entries into existing cache
python3 -c "
import json, sys
cache_path = '$CACHE_FILE'
try:
    with open(cache_path) as f:
        cache = json.load(f)
except:
    cache = {}
# New entries passed via heredoc (claim_text -> citation_key pairs)
new_entries = dict(line.split(' ||| ') for line in sys.stdin.read().strip().split('\n') if ' ||| ' in line)
cache.update(new_entries)
with open(cache_path, 'w') as f:
    json.dump(cache, f, indent=2)
print(f'Cache updated: {len(cache)} total entries ({len(new_entries)} new this round)')
" << 'CACHE_INPUT'
[claim text 1] ||| (Author Year)
[claim text 2] ||| (Author Year)
CACHE_INPUT
```

**Convergence check**: Re-scan the updated draft for remaining uncited claims (claims without citations and without `[SOURCE NEEDED]` markers). Count them.

```
ROUND [N] SUMMARY:
- Claims resolved this round: [N]
- Claims still unresolved: [N]
- SOURCE NEEDED markers added: [N]
- Cache entries total: [N]
```

**Exit conditions** (stop iterating if ANY is true):
1. **All claims resolved**: 0 unresolved claims remain
2. **No progress**: 0 new citations inserted this round (all remaining claims are genuinely hard to find)
3. **Max rounds reached**: Round 3 completed

If exiting due to condition 2, convert all remaining unresolved claims to `[SOURCE NEEDED]` markers.

---

## Step I-5: Output with Citations

Return the full revised text with:
- In-text citations added at appropriate locations (end of sentence before period, or mid-sentence at natural pause)
- `SOURCE NEEDED` markers for unresolved claims
- A numbered source list used (for tracking)
- **Iteration summary**: how many rounds were needed, how many claims resolved per round

```
ITERATIVE INSERTION SUMMARY:
- Total rounds: [N] / 3 max
- Round 1: [N] claims resolved
- Round 2: [N] claims resolved (or "not needed — converged")
- Round 3: [N] claims resolved (or "not needed — converged")
- Final: [N] cited, [N] SOURCE NEEDED
- Cache file: [path]
```

---

# MODE 2: AUDIT — Citation Consistency Check

**Input:** Draft with existing citations

## Step A-1: Extract All In-Text Citations

```bash
# For author-date style — extract (Author Year) patterns
grep -oE '\([A-Z][a-z]+ (and [A-Z][a-z]+ |et al\. )?[0-9]{4}[a-b]?\)' draft.txt | sort | uniq

# For numbered style — extract [N] or superscript patterns
grep -oE '\[[0-9,– ]+\]' draft.txt | sort
```

Build an IN-TEXT CITATION LIST from the extracted items.

## Step A-2: Extract All Reference List Entries

Parse the References section to extract each cited item's:
- Author(s) last name(s)
- Year
- Title (first few words)

Build a REFERENCE LIST.

## Step A-3: Cross-Check

Run four checks:

**Check 1 — Orphan citations** (in-text but not in references):
```
IN-TEXT but MISSING from reference list:
- Smith (2020) → Not found in references
```

**Check 2 — Ghost references** (in references but not cited in text):
```
IN REFERENCES but NEVER CITED:
- Jones et al. (2019) → Listed in references but no matching in-text citation found
```

**Check 3 — Year/author mismatches:**
```
MISMATCH DETECTED:
- In-text: "Williams (2018)" → Reference list has Williams 2019
```

**Check 4 — Disambiguation needed:**
```
DISAMBIGUATION NEEDED:
- Smith 2020 appears twice in references (two different Smith 2020 works)
  → Label as Smith 2020a and Smith 2020b in both text and references
```

## Step A-4: Style Errors

Scan for common style violations:
- Incorrect in-text format (e.g., `(Smith, 2020)` in ASA instead of `(Smith 2020)`)
- Missing page numbers for direct quotes
- "et al." used in references (ASA: spell out all authors)
- DOI missing from reference entries
- Capitalization errors in article titles
- Page range formatting (ASA: spell out vs. abbreviated)

## Step A-4b: Semantic Duplicate Detection

**Semantic duplicate detection**:
Beyond exact-match deduplication, check for:
- Same work cited under different titles (e.g., translated titles, abbreviated vs. full titles)
- Same work as preprint AND published version (keep published; drop preprint unless citing preprint-specific content)
- Same first author + similar year + similar title → flag for manual review
- Conference paper later published as journal article → keep journal version

Detection heuristic: If two references share first author AND year differs by ≤1 AND title Jaccard similarity > 0.6, flag as potential duplicate.

## Step A-5: Audit Report

```
CITATION AUDIT REPORT
─────────────────────────────────────────────────
Style: [ASA/APA/Chicago/Numbered]
Total in-text citations: [N]
Total reference entries: [N]

ORPHAN IN-TEXT CITATIONS (N):
  • [List]

GHOST REFERENCES (N):
  • [List]

YEAR/AUTHOR MISMATCHES (N):
  • [List]

DISAMBIGUATION NEEDED (N):
  • [List]

STYLE ERRORS (N):
  • [List]

SOURCE NEEDED — Uncited Claims (N):
  • [List]

RECOMMENDED ACTIONS:
  1. [Specific fix]
  2. ...
─────────────────────────────────────────────────
```
