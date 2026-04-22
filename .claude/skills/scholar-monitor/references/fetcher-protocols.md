# Fetcher Protocols

All backend-specific HTTP logic lives in `assets/fetch.py`. This file documents **how to call it** from within the skill and what each backend accepts. The SKILL.md routing code treats `fetch.py` as a black box that emits normalized paper records as JSONL on stdout.

## Invocation Pattern (from SKILL.md Bash blocks)

```bash
# ── fetch.py call pattern ──────────────────────────────
SKILL_DIR="${SCHOLAR_SKILL_DIR:-.}/.claude/skills/scholar-monitor"
SOURCE_JSON='{"id":"asr","type":"crossref","issn":"0003-1224","category":"Sociology — Top General","max_per_tick":10,"note":"American Sociological Review"}'
SINCE="2026-04-14"          # YYYY-MM-DD — from state.json last_seen_date
MAX=10
EMAIL="${SCHOLAR_CROSSREF_EMAIL:-}"

python3 "$SKILL_DIR/assets/fetch.py" \
    --source-json "$SOURCE_JSON" \
    --since "$SINCE" \
    --max "$MAX" \
    --email "$EMAIL" \
    > /tmp/fetch-$$.jsonl 2> /tmp/fetch-$$.err

RC=$?
if [ $RC -ne 0 ]; then
    echo "WARN: fetch failed for source — see /tmp/fetch-$$.err"
    # Do NOT update state.last_seen_date; record last_error instead
fi
```

**Output format**: one JSON object per line. Schema:
```
source_id, category, doi, arxiv_id, title, authors (list),
year, published_date (YYYY-MM-DD), journal, abstract, url
```

**Error handling**: exit code `0` = success (even with zero records); nonzero = network or parse failure. The skill must preserve `state.json[source_id].last_seen_date` on failure so the next tick re-tries the same window.

---

## Backend: `crossref`

**Required fields**: `type: "crossref"`, and one of:
- `issn: "0003-1224"` — primary route, filters by ISSN
- `query: "American Sociological Review"` — container-title keyword (fallback)

**What it does**: hits `https://api.crossref.org/works` with `filter=issn:XXXX,from-pub-date:YYYY-MM-DD`, sorted by `published` descending. Honors the `mailto` polite-pool header if `--email` is set.

**Known quirks**:
- Crossref has ~1–2 week ingestion lag for some publishers (SAGE in particular). Don't expect ASR/AJS articles the same day they appear on the journal website.
- `abstract` field is not always present — many publishers withhold abstracts from Crossref's metadata feed. Set `category` to indicate abstract may be empty.
- `<jats:p>` and `<p>` tags in abstracts are stripped by `fetch.py` already.

**Recommended cadence**: 7 days for most journals; 14 days for bimonthly/quarterly.

---

## Backend: `arxiv`

**Required fields**: `type: "arxiv"`, `query` (arXiv search syntax).

**Query syntax examples**:
- `cat:cs.CL` — all cs.CL papers
- `cat:cs.CL AND abs:"large language model"` — cs.CL filtered by abstract
- `cat:cs.CY AND (abs:"algorithmic bias" OR abs:"fairness")`
- `au:Mikolov` — by author
- See https://info.arxiv.org/help/api/user-manual.html#query_details

**What it does**: hits `http://export.arxiv.org/api/query` with `search_query`, `sortBy=submittedDate`, `sortOrder=descending`. Parses Atom XML. Applies the `--since` filter client-side (arXiv doesn't expose a native date range in the query).

**Known quirks**:
- arXiv rate limit: roughly 1 request per 3 seconds. `fetch.py` sleeps 3s after every arxiv call.
- Papers can appear under multiple categories (cross-listing). If you subscribe to both `arxiv-llm` (cat:cs.CL) and `arxiv-css` (cat:cs.CY), you may see duplicates — the dedup pass against `state.last_seen_ids` + `kg_has_paper` catches this by arxiv_id / doi / title.
- Some arXiv papers later get a journal DOI; `fetch.py` records the DOI in the `doi` field when present.

**Recommended cadence**: 1 day for active categories (cs.CL), 2–3 days for slower ones (econ.GN).

---

## Backend: `openalex`

**Required fields**: `type: "openalex"`, `issn`.

**What it does**: hits `https://api.openalex.org/works` with `filter=primary_location.source.issn:ISSN,from_publication_date:YYYY-MM-DD`, sorted by `publication_date:desc`. Honors `--email` for polite pool.

**When to use over Crossref**: OpenAlex aggregates Crossref + PubMed + arXiv + others, and reconstructs abstracts via `abstract_inverted_index` when the publisher withholds them from Crossref. If a Crossref source keeps returning empty abstracts, mirror it with `openalex` as a fallback source (same `category`, same cadence).

**Known quirks**:
- Inverted-index reconstruction is lossy for punctuation and spacing; `fetch.py` does the reconstruction with best-effort word ordering.
- OpenAlex uses its own work IDs (e.g., `W2741809807`); the DOI field is still populated when available.

---

## Backend: `rss`

**Required fields**: `type: "rss"`, `url`.

**What it does**: generic Atom/RSS parser. Strips namespaces, walks `<item>` (RSS 2.0) or `<entry>` (Atom) elements, extracts `title`, `link`, `pubDate`/`updated`/`published`, `description`/`summary`, and authors.

**When to use**: journals or sources with no API but a working feed. Examples: some Annual Reviews feeds, institutional working-paper series (NBER, IZA).

**Known quirks**:
- No DOI in most RSS entries — dedup falls back to title hash. Set a long `last_seen_ids` window (200) to compensate.
- Date parsing is best-effort across RFC-822, ISO-8601, and local formats. Entries with unparseable dates are always emitted (no `--since` filtering).
- `abstract` is whatever the feed puts in `description`/`summary`, capped at 2000 chars.

---

## Paper Record Schema (emitted by all fetchers)

```json
{
  "source_id":       "asr",
  "category":        "Sociology — Top General",
  "doi":             "10.1177/...",
  "arxiv_id":        "",
  "title":           "...",
  "authors":         ["Family, Given", ...],
  "year":            2026,
  "published_date":  "2026-04-15",
  "journal":         "American Sociological Review",
  "abstract":        "...",
  "url":             "https://doi.org/..."
}
```

**Invariants**:
- `doi` is lowercased when present; empty string otherwise (never `null`).
- `published_date` is ISO YYYY-MM-DD when parseable, empty string otherwise.
- `authors` is a list of `"Family, Given"` strings; empty list if none.
- `abstract` may be empty (Crossref holds back some); downstream summary step must handle.
- `year` is int; `0` if unparseable.

---

## Adding a New Backend

If you want to add (e.g.) Semantic Scholar or bioRxiv:

1. Add a `fetch_<name>(source, since, max_n, ...)` function to `assets/fetch.py` that yields records matching the schema above.
2. Add a dispatch branch in `main()` keyed on `source["type"] == "<name>"`.
3. Document here: required fields, quirks, recommended cadence.
4. Update `registry-guide.md` with an example source entry.

No change to `SKILL.md` is needed — it calls `fetch.py` generically.
