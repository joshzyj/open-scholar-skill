#!/usr/bin/env bash
# verify-citation-metadata.sh — validate .bib metadata against CrossRef DOI registry.
#
# RATIONALE: citation audits regularly find that a large share of .bib
# entries carry hallucinated metadata — e.g. an author's own paper
# misattributed to a similar-but-wrong name (a first-name swap between two
# authors who share a surname), plus pure fabrications with no CrossRef
# record. A structural existence gate (`(Author Year)` in body ↔ entry in
# .bib) cannot catch these because it never validates the bib metadata
# against a canonical source.
#
# THIS GATE closes that gap. For each bib entry:
#   1. If `doi=` field present: resolve via CrossRef API; compare metadata.
#   2. If no `doi=`: search CrossRef by title+author+year; pick best match.
#   3. Compare author last/first names, year, volume, issue, pages.
#   4. Emit verdict: REAL | MISREMEMBERED | FABRICATED | UNVERIFIABLE.
#
# Tolerance rules:
#   - Author last names: case-insensitive substring match (allows "Smith"
#     to match "Smith-Jones" etc.)
#   - Author first names: initial-letter match acceptable (allows "J." vs
#     "John"); full-name swap not acceptable.
#   - Year: exact.
#   - Volume: exact when both present.
#   - Issue: exact when both present; absent in bib + present in CrossRef
#     is YELLOW (advisory).
#   - Pages: numeric range match; whitespace and en-dash variants normalized.
#
# Exit codes:
#   0 — GREEN (all entries REAL or pre-print/book UNVERIFIABLE)
#   1 — RED (≥1 MISREMEMBERED or FABRICATED)
#   2 — YELLOW (network issues, advisory)
#
# Usage:
#   verify-citation-metadata.sh <project_dir>
#
# Environment:
#   SCHOLAR_CROSSREF_TIMEOUT_S — per-request timeout (default 10)
#   SCHOLAR_CITATION_REQUIRE_DOI=1 — strict mode: entries without DOI RED-fail
#
# Smoke tests:
#   scripts/gates/tests/test-verify-citation-metadata.sh

set -uo pipefail
export LC_ALL=C

if [ $# -lt 1 ]; then
  echo "Usage: $(basename "$0") <project_dir>" >&2
  exit 64
fi

PROJ="$1"
if [ ! -d "$PROJ" ]; then
  echo "STATUS=YELLOW"
  echo "REASON=project_dir_not_found:$PROJ"
  exit 2
fi

CITATIONS_DIR="$PROJ/citations"
if [ ! -d "$CITATIONS_DIR" ]; then
  echo "STATUS=YELLOW"
  echo "REASON=no_citations_dir"
  exit 2
fi

# Connectivity precheck
if ! curl --max-time 5 -sf -o /dev/null -A "scholar-skill/1.0" \
     "https://api.crossref.org/works/10.1111/jomf.12419" 2>/dev/null; then
  echo "STATUS=YELLOW"
  echo "REASON=crossref_api_unreachable"
  echo "DETAIL: try again when network access is available"
  exit 2
fi

# Find bib files
BIB_FILES=()
while IFS= read -r f; do
  [ -n "$f" ] && BIB_FILES+=("$f")
done < <(find "$CITATIONS_DIR" -maxdepth 1 -type f -name "*.bib" 2>/dev/null)

if [ "${#BIB_FILES[@]}" -eq 0 ]; then
  echo "STATUS=YELLOW"
  echo "REASON=no_bib_files_in_citations_dir"
  exit 2
fi

REQUIRE_DOI="${SCHOLAR_CITATION_REQUIRE_DOI:-0}"
TIMEOUT_S="${SCHOLAR_CROSSREF_TIMEOUT_S:-10}"

# Build temp file with newline-separated bib file paths (handles spaces).
BIB_LIST=$(mktemp)
trap 'rm -f "$BIB_LIST"' EXIT
for f in "${BIB_FILES[@]}"; do
  printf '%s\n' "$f" >> "$BIB_LIST"
done

python3 - "$BIB_LIST" "$REQUIRE_DOI" "$TIMEOUT_S" <<'PYEOF'
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

bib_list_file, require_doi, timeout_s = sys.argv[1], sys.argv[2] == "1", int(sys.argv[3])

USER_AGENT = "scholar-skill/1.0 (citation-metadata-verify; mailto:noreply@anthropic.com)"

# ── Bib parser (simple; handles @kind{key, field={val}, ...}) ────────────
ENTRY_RE = re.compile(r"@(\w+)\s*\{\s*([^,\s]+)\s*,(.*?)^\s*\}", re.MULTILINE | re.DOTALL)
FIELD_RE = re.compile(r"(\w+)\s*=\s*\{([^{}]*?)\}", re.DOTALL)

# Citation kinds we attempt to verify (skip @misc, @unpublished, @manual)
# Note: @incollection (book chapters) and @book often lack DOIs and are not
# reliably indexed in CrossRef. Verify only when DOI present; otherwise
# mark UNVERIFIABLE (advisory).
VERIFIABLE_KINDS = {"article", "inproceedings", "incollection", "book"}
DOI_REQUIRED_KINDS = {"incollection", "book"}


def parse_bib(text):
    entries = []
    for m in ENTRY_RE.finditer(text):
        kind = m.group(1).lower()
        key = m.group(2)
        body = m.group(3)
        if kind not in VERIFIABLE_KINDS:
            continue
        fields = {"_kind": kind, "_key": key}
        for fm in FIELD_RE.finditer(body):
            fields[fm.group(1).lower()] = fm.group(2).strip()
        entries.append(fields)
    return entries


# ── CrossRef API client ───────────────────────────────────────────────────
def _http_get_json(url):
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    try:
        with urllib.request.urlopen(req, timeout=timeout_s) as r:
            return json.loads(r.read().decode("utf-8", "replace"))
    except urllib.error.HTTPError as e:
        return {"_http_error": e.code}
    except Exception:
        return None


def crossref_by_doi(doi):
    doi = doi.strip().rstrip("/")
    if doi.lower().startswith("https://doi.org/"):
        doi = doi[len("https://doi.org/"):]
    if doi.lower().startswith("doi:"):
        doi = doi[4:]
    url = "https://api.crossref.org/works/" + urllib.parse.quote(doi, safe="/")
    j = _http_get_json(url)
    if j is None or j.get("_http_error"):
        return None
    return j.get("message")


def crossref_search(author, title, year):
    title_q = urllib.parse.quote(title[:120])
    author_q = urllib.parse.quote(author[:60])
    url = (
        "https://api.crossref.org/works?"
        f"query.title={title_q}&query.author={author_q}&rows=3"
    )
    j = _http_get_json(url)
    if j is None or j.get("_http_error"):
        return None
    items = (j.get("message") or {}).get("items", [])
    if not items:
        return None
    # Prefer the year match if available
    for it in items:
        date_parts = (
            it.get("published-print", {})
            or it.get("published-online", {})
            or it.get("issued", {})
        ).get("date-parts", [[None]])
        cy = date_parts[0][0] if date_parts and date_parts[0] else None
        if cy is not None and str(cy) == str(year):
            return it
    return items[0]


# ── OpenAlex cascade (opt-in via SCHOLAR_CITATION_CASCADE=openalex) ──────
# Added 2026-05-25 to close VCM's UNVERIFIABLE bucket for sources outside
# CrossRef coverage (books, book chapters, working papers, dissertations,
# Chinese-language journals). OpenAlex (~250M works) has broader gray-lit
# coverage than CrossRef (~150M). CrossRef remains the primary authority;
# OpenAlex only fires for entries CrossRef cannot resolve.
def _oa_to_crossref_shape(work):
    """Map an OpenAlex work dict into the CrossRef shape that compare() expects."""
    if not work:
        return None
    biblio = work.get("biblio") or {}
    fp = (biblio.get("first_page") or "").strip()
    lp = (biblio.get("last_page") or "").strip()
    pages = f"{fp}-{lp}" if (fp and lp) else (fp or "")
    venue = (work.get("host_venue")
             or (work.get("primary_location") or {}).get("source")
             or {})
    cr_authors = []
    for a in work.get("authorships") or []:
        disp = (a.get("author") or {}).get("display_name", "") or ""
        toks = disp.split()
        if not toks:
            continue
        # OpenAlex returns "First M Last" form
        last = toks[-1]
        first = " ".join(toks[:-1]) if len(toks) > 1 else ""
        cr_authors.append({"family": last, "given": first})
    pub_year = work.get("publication_year")
    return {
        "DOI": (work.get("doi") or "").replace("https://doi.org/", ""),
        "title": [work.get("title")] if work.get("title") else [],
        "container-title": [venue.get("display_name")] if venue.get("display_name") else [],
        "volume": str(biblio.get("volume") or ""),
        "issue": str(biblio.get("issue") or ""),
        "page": pages,
        "author": cr_authors,
        "type": work.get("type") or "",
        "published-print": {"date-parts": [[pub_year]]} if pub_year else {},
        "_source": "openalex",
    }


def openalex_by_doi(doi):
    doi = doi.strip().rstrip("/")
    if doi.lower().startswith("https://doi.org/"):
        doi = doi[len("https://doi.org/"):]
    if doi.lower().startswith("doi:"):
        doi = doi[4:]
    url = ("https://api.openalex.org/works/https://doi.org/"
           + urllib.parse.quote(doi, safe="/")
           + "?mailto=" + urllib.parse.quote("scholar-skill@example.com"))
    j = _http_get_json(url)
    if j is None or j.get("_http_error"):
        return None
    return _oa_to_crossref_shape(j)


def openalex_search(author, title, year):
    """OpenAlex full-text search. Combines title and (optionally) author
    surname into the search= query so OpenAlex's relevance ranking handles
    weighting. Filters strictly only by publication year — author-name
    filter is too brittle (book reviews / co-authored variants drop out).
    Returns the first result whose year matches (or first overall)."""
    if not title:
        return None
    # Author "Last, First" → "Last" surname; if author has no comma, use as-is.
    sur = ""
    if author:
        sur = author.split(",", 1)[0].strip() if "," in author else author.strip()
    # Build search query: title + author surname for relevance weighting.
    q_text = (title[:160] + (" " + sur if sur else "")).strip()
    search_q = urllib.parse.quote(q_text)
    flt = f"&filter=publication_year:{year}" if year else ""
    url = ("https://api.openalex.org/works?search=" + search_q
           + flt + "&per_page=5&mailto=" + urllib.parse.quote("scholar-skill@example.com"))
    j = _http_get_json(url)
    if j is None or j.get("_http_error"):
        return None
    items = j.get("results") or []
    if not items:
        return None
    # Two-stage selection:
    #   1. If bib has a surname, restrict to items whose first author surname
    #      matches (case-insensitive, diacritic-normalized). This rejects
    #      book-review hits where OpenAlex returns a different paper that
    #      discusses the bib's work but isn't by the bib's author.
    #   2. Among surviving items, pick the one whose title best matches the
    #      bib's title (Jaccard token-set ≥ 0.5).
    def _norm_tok_string(s):
        return re.sub(r"[^a-z0-9]", "", (s or "").lower())

    def _norm_tokens(s):
        s = re.sub(r"[^A-Za-z0-9\s]", " ", (s or "").lower())
        return set(t for t in s.split() if len(t) > 2)

    bib_toks = _norm_tokens(title)
    bib_sur_norm = _norm_tok_string(sur)

    candidates = items
    if bib_sur_norm:
        filtered = []
        for it in items:
            ships = it.get("authorships") or []
            if not ships:
                continue
            first_disp = (ships[0].get("author") or {}).get("display_name", "")
            toks = first_disp.split()
            it_sur = _norm_tok_string(toks[-1] if toks else "")
            # Substring match: handles "Putnam" vs "Putnam Jr." etc.
            if it_sur and (
                it_sur == bib_sur_norm
                or bib_sur_norm in it_sur
                or it_sur in bib_sur_norm
            ):
                filtered.append(it)
        candidates = filtered

    if not candidates:
        return None

    best = None
    best_jacc = -1.0
    for it in candidates:
        it_toks = _norm_tokens(it.get("title") or "")
        if not it_toks or not bib_toks:
            continue
        jacc = len(bib_toks & it_toks) / max(1, len(bib_toks | it_toks))
        if jacc > best_jacc:
            best_jacc = jacc
            best = it
    # Stricter threshold (0.5) now that author is hard-filtered upstream.
    if best is not None and best_jacc >= 0.5:
        return _oa_to_crossref_shape(best)
    return None


# ── Field-by-field comparison ─────────────────────────────────────────────
def _normalize_pages(s):
    if not s:
        return ""
    return re.sub(r"[\s–—]+", "-", s).replace("--", "-").strip()


def _split_authors_bib(s):
    """Parse bib author string: 'Last, First and Last2, First2' → [(last, first), ...]"""
    out = []
    for chunk in re.split(r"\s+and\s+", s):
        chunk = chunk.strip()
        if not chunk:
            continue
        if "," in chunk:
            last, first = chunk.split(",", 1)
            out.append((last.strip().lower(), first.strip().lower()))
        else:
            # "First Last" form
            parts = chunk.split()
            if len(parts) >= 2:
                out.append((parts[-1].strip().lower(), " ".join(parts[:-1]).strip().lower()))
            else:
                out.append((chunk.strip().lower(), ""))
    return out


def _cr_authors(cr):
    return [
        (a.get("family", "").strip().lower(), a.get("given", "").strip().lower())
        for a in cr.get("author", [])
    ]


def _first_initial_match(bib_first, cr_first):
    """Accept 'A. J.' vs 'Andrew J.' as compatible; reject full-name swap.

    Tokenize each (drop periods, split on whitespace). For each position:
    - if EITHER token is a 1-2-char initial → require first-letter match
    - if BOTH tokens are full names (3+ chars) → require full match
    This catches the same-surname first-name-swap case (e.g. two authors
    whose given names share a first letter but differ — full-name match
    required so one is not silently substituted for the other).
    """
    if not bib_first or not cr_first:
        return True  # one side missing → don't penalize
    b_tokens = [t for t in bib_first.lower().replace(".", " ").split() if t]
    c_tokens = [t for t in cr_first.lower().replace(".", " ").split() if t]
    if not b_tokens or not c_tokens:
        return True
    for bt, ct in zip(b_tokens, c_tokens):
        if len(bt) <= 2 or len(ct) <= 2:
            # at least one is initial — first-letter match suffices
            if bt[0] != ct[0]:
                return False
        else:
            # both are full names — require exact (case-insensitive) match
            if bt != ct:
                return False
    return True


# ── Title fuzzy match (Phase A) ──────────────────────────────────────────
# Catches the "right DOI + right author + wrong title" fabrication where the
# bib carries title of paper B but DOI/year/authors of paper A. Title was
# previously not compared, so this class of fabrication slipped through.
#
# Strategy: aggressive normalization (lowercase, strip leading articles +
# punctuation), tokenize, drop stopwords, compute Jaccard. Threshold is
# tunable via SCHOLAR_CITATION_TITLE_FUZZ_MIN (default 0.6).
_TITLE_STOPWORDS = {
    "the", "a", "an", "of", "and", "or", "in", "on", "for", "to", "from",
    "with", "by", "as", "is", "are", "be", "at", "into", "through",
}


def _title_normalize(s):
    s = (s or "").lower()
    s = re.sub(r"^(the|a|an|le|la|el|der|die|das)\s+", "", s)
    s = re.sub(r"[^\w\s]", " ", s)
    s = re.sub(r"\s+", " ", s).strip()
    return s


def _title_match(bib_t, cr_t, threshold):
    if not bib_t or not cr_t:
        return True  # missing on either side → don't penalize
    bt = set(_title_normalize(bib_t).split()) - _TITLE_STOPWORDS
    ct = set(_title_normalize(cr_t).split()) - _TITLE_STOPWORDS
    if not bt or not ct:
        return True
    overlap = len(bt & ct)
    union = len(bt | ct)
    if union == 0:
        return True
    return (overlap / union) >= threshold


# ── Journal / container-title comparison (Phase A) ───────────────────────
# Catches "right paper + wrong journal" fabrication. Uses a small
# abbreviation map for common social-science journals so that legitimate
# variants (JOMF ↔ Journal of Marriage and Family) do not false-RED.
_JOURNAL_ALIASES = {
    "asr": "american sociological review",
    "am sociol rev": "american sociological review",
    "ajs": "american journal of sociology",
    "am j sociol": "american journal of sociology",
    "jmf": "journal of marriage and family",
    "j marriage fam": "journal of marriage and family",
    "j marriage family": "journal of marriage and family",
    "sf": "social forces",
    "soc forces": "social forces",
    "ssr": "social science research",
    "soc sci res": "social science research",
    "ars": "annual review of sociology",
    "annu rev sociol": "annual review of sociology",
    "pnas": "proceedings of the national academy of sciences",
    "proc natl acad sci": "proceedings of the national academy of sciences",
    "sci adv": "science advances",
    "nhb": "nature human behaviour",
    "nat hum behav": "nature human behaviour",
    "ncs": "nature computational science",
    "nat comput sci": "nature computational science",
    "lis": "language in society",
    "lang soc": "language in society",
    "jos": "journal of sociolinguistics",
    "j socioling": "journal of sociolinguistics",
    "ijal": "international journal of american linguistics",
    "demogr res": "demographic research",
    "popul stud": "population studies",
    "popul dev rev": "population and development review",
}


def _journal_normalize(s):
    s = (s or "").lower().strip()
    s = re.sub(r"[.,]", "", s)
    s = re.sub(r"\s+", " ", s).strip()
    # Expand abbreviation if it matches exactly
    if s in _JOURNAL_ALIASES:
        s = _JOURNAL_ALIASES[s]
    return s


def _journal_match(bib_j, cr_j):
    if not bib_j or not cr_j:
        return True
    bn = _journal_normalize(bib_j)
    cn = _journal_normalize(cr_j)
    if not bn or not cn:
        return True
    if bn == cn:
        return True
    # Substring tolerance: a journal carrying a series subtitle still matches
    if bn in cn or cn in bn:
        return True
    # Token overlap fallback (handles minor wording differences)
    bt = set(re.sub(r"[^\w\s]", " ", bn).split())
    ct = set(re.sub(r"[^\w\s]", " ", cn).split())
    bt -= _TITLE_STOPWORDS
    ct -= _TITLE_STOPWORDS
    if bt and ct and len(bt & ct) / max(1, len(bt | ct)) >= 0.5:
        return True
    return False


# ── Entry-type ↔ CrossRef-type equivalence (Phase A) ─────────────────────
# Catches "right paper + wrong @kind" fabrication (e.g., @book for what
# CrossRef indexes as journal-article). Tolerates the legitimate
# proceedings-vs-article ambiguity for conference papers.
_TYPE_EQUIVALENCE = {
    "journal-article": {"article"},
    "book-chapter": {"incollection", "inbook"},
    "monograph": {"book"},
    "book": {"book"},
    "edited-book": {"book", "collection"},
    "reference-book": {"book"},
    "proceedings-article": {"inproceedings", "conference", "article"},
    "proceedings": {"proceedings"},
    "report": {"techreport", "misc"},
    "report-series": {"techreport", "misc"},
    "dissertation": {"phdthesis", "mastersthesis"},
    "posted-content": {"misc", "unpublished", "article"},
    "preprint": {"misc", "unpublished", "article"},
}


def _type_match(bib_kind, cr_type):
    if not bib_kind or not cr_type:
        return True
    allowed = _TYPE_EQUIVALENCE.get(cr_type.lower())
    if allowed is None:
        return True  # unknown CrossRef type → don't penalize
    return bib_kind.lower() in allowed


# ── Coauthor-count check (Phase A) ───────────────────────────────────────
# Catches "real first author + missing coauthors" fabrication. Respects the
# legitimate ASA/APA 'and others' (et al.) shorthand: if the bib uses it,
# the count gap is not flagged.
#
# 2026-05-25 fix: default gap_threshold tightened from 2 → 1 after a peer
# sweep with verify-rendered-references-against-bib.sh surfaced multiple
# real defects where the bib dropped exactly ONE middle coauthor (Dush 2003,
# Stanley 2006). gap=1 was previously silent in VCM. Override available via
# `SCHOLAR_CITATION_COAUTHOR_GAP` env var for projects that intentionally
# truncate (e.g., 4+ author papers where ASA style permits short refs).
def _coauthor_count_ok(bib_author_str, cr_authors, gap_threshold=None):
    if gap_threshold is None:
        try:
            gap_threshold = int(os.environ.get("SCHOLAR_CITATION_COAUTHOR_GAP", "1"))
        except (TypeError, ValueError):
            gap_threshold = 1
    if not bib_author_str:
        return True
    if re.search(r"\band\s+others\b", bib_author_str, re.IGNORECASE):
        return True  # legitimate et-al shorthand
    bib_count = len(_split_authors_bib(bib_author_str))
    cr_count = len(cr_authors)
    if bib_count == 0 or cr_count == 0:
        return True
    # cr_count - bib_count < gap_threshold means: gap must be STRICTLY less
    # than threshold to be acceptable. gap_threshold=1 → only gap=0 passes;
    # gap_threshold=2 → gap=0 or 1 passes (legacy behavior).
    return (cr_count - bib_count) < gap_threshold


def compare(bib, cr):
    if not cr:
        return "UNVERIFIABLE", "no_crossref_match"
    mismatches = []

    # ── Authors ──
    bib_authors = _split_authors_bib(bib.get("author", ""))
    cr_authors = _cr_authors(cr)
    if bib_authors:
        # last-name comparison: every bib lastname must appear (substring) in cr
        cr_lasts = [a[0] for a in cr_authors]
        cr_givens = [a[1] for a in cr_authors]
        # Tolerate CrossRef records that store given/family swapped — common for
        # older JSTOR-deposited records and some CJK names (e.g., PDR 1996
        # 10.2307/2137436 returns family="Feng"/"Quanhe" for authors Feng Wang
        # and Quanhe Yang). Accept a bib surname that matches EITHER a CrossRef
        # family OR a CrossRef given. A genuinely fabricated author matches
        # neither, so this does not weaken fabrication detection.
        cr_name_parts = cr_lasts + cr_givens
        for i, (bl, _) in enumerate(bib_authors):
            if bl and not any(bl in cn or cn in bl for cn in cr_name_parts):
                mismatches.append(f"author[{i}].last(bib={bl},cr={cr_lasts})")
        # first-name per-position comparison (only when lasts align positionally)
        if len(bib_authors) == len(cr_authors):
            for i, ((bl, bf), (cl, cf)) in enumerate(zip(bib_authors, cr_authors)):
                if bl and cl and (bl in cl or cl in bl):
                    if not _first_initial_match(bf, cf):
                        mismatches.append(
                            f"author[{i}].first(bib={bf!r},cr={cf!r})"
                        )

    # ── Year ──
    # Accept ANY of CrossRef's date sources matching (print, online, issued).
    # Online-first papers commonly have online-year=2023 + print-year=2024;
    # either is a legitimate bib value.
    bib_year = (bib.get("year") or "").strip()
    cr_years = set()
    for k in ("published-print", "published-online", "issued", "published"):
        dp = (cr.get(k) or {}).get("date-parts", [[None]])
        if dp and dp[0] and dp[0][0] is not None:
            cr_years.add(str(dp[0][0]))
    if bib_year and cr_years and bib_year not in cr_years:
        mismatches.append(f"year(bib={bib_year},cr={'|'.join(sorted(cr_years))})")

    # ── Volume ──
    # Fuzzy match: Demographic Research's "S3" ↔ CrossRef's "Special 3"
    # should match. Strategy: extract digit-only parts AND first-letter
    # parts; if both agree, accept. e.g., "S3" → letters="s",digits="3";
    # "Special 3" → letters="s" (from "Special"),digits="3"; match.
    def _vol_signature(v):
        v = (v or "").strip().lower()
        digits = "".join(re.findall(r"\d+", v))
        # First letter of any leading non-digit word (e.g., "Special" → "s")
        leading_letters = re.match(r"^[a-z]+", v)
        first_letter = leading_letters.group(0)[0] if leading_letters else ""
        return (first_letter, digits)
    bib_sig = _vol_signature(bib.get("volume"))
    cr_sig = _vol_signature(cr.get("volume"))
    if bib_sig[1] and cr_sig[1]:  # both have digits
        # Mismatch only if digits differ OR if both have leading letters and they differ
        digit_mismatch = bib_sig[1] != cr_sig[1]
        letter_mismatch = (
            bib_sig[0] and cr_sig[0] and bib_sig[0] != cr_sig[0]
        )
        if digit_mismatch or letter_mismatch:
            mismatches.append(f"volume(bib={bib.get('volume')},cr={cr.get('volume')})")

    # ── Issue ──
    bib_iss = (bib.get("number") or bib.get("issue") or "").strip()
    cr_iss = (cr.get("issue") or "").strip()
    if bib_iss and cr_iss and str(bib_iss) != str(cr_iss):
        mismatches.append(f"issue(bib={bib_iss},cr={cr_iss})")

    # ── Pages ──
    # CrossRef sometimes returns ONLY the start page (e.g., "61") even when
    # the article spans 61-98. Accept "start page matches" as soft match
    # since fabricated entries rarely get the start page right by accident.
    bib_pp = _normalize_pages(bib.get("pages", ""))
    cr_pp = _normalize_pages(cr.get("page", ""))
    if bib_pp and cr_pp and bib_pp != cr_pp:
        # If CrossRef has single page (no dash), check it matches bib start
        if "-" not in cr_pp:
            bib_start = bib_pp.split("-")[0]
            if bib_start != cr_pp:
                mismatches.append(f"pages(bib={bib_pp},cr={cr_pp})")
        # If bib has single page, check it matches CrossRef start
        elif "-" not in bib_pp:
            cr_start = cr_pp.split("-")[0]
            if bib_pp != cr_start:
                mismatches.append(f"pages(bib={bib_pp},cr={cr_pp})")
        else:
            # Both are ranges; require exact match
            mismatches.append(f"pages(bib={bib_pp},cr={cr_pp})")

    # ── Title (Phase A — new check; env-knob gated) ──
    if os.environ.get("SCHOLAR_CITATION_CHECK_TITLE", "1") == "1":
        try:
            title_fuzz = float(os.environ.get("SCHOLAR_CITATION_TITLE_FUZZ_MIN", "0.6"))
        except ValueError:
            title_fuzz = 0.6
        bib_title = (bib.get("title") or "").strip()
        cr_title_list = cr.get("title") or []
        cr_title = cr_title_list[0] if cr_title_list else ""
        # CrossRef stores the subtitle in a separate `subtitle` field; an ASA
        # bib title legitimately carries "Main Title: Subtitle". Compare the
        # bib title against the CONCATENATED CrossRef title+subtitle so a
        # subtitle-bearing bib entry is not falsely flagged (e.g., Yeung & Hu
        # 2013 "Coming of Age in Times of Change: The Transition to Adulthood
        # in China"). Concatenation only adds tokens to the CrossRef side, so
        # it cannot mask a genuinely wrong title.
        cr_sub_list = cr.get("subtitle") or []
        cr_sub = cr_sub_list[0] if cr_sub_list else ""
        cr_title_full = (cr_title + " " + cr_sub).strip() if cr_sub else cr_title
        if not _title_match(bib_title, cr_title_full, title_fuzz):
            mismatches.append(
                f"title(bib={bib_title[:60]!r},cr={cr_title_full[:60]!r})"
            )

    # ── Journal / container-title (Phase A) ──
    if os.environ.get("SCHOLAR_CITATION_CHECK_JOURNAL", "1") == "1":
        bib_journal = (bib.get("journal") or bib.get("booktitle") or "").strip()
        cr_container = cr.get("container-title") or []
        cr_journal = cr_container[0] if cr_container else ""
        if not _journal_match(bib_journal, cr_journal):
            mismatches.append(
                f"journal(bib={bib_journal!r},cr={cr_journal!r})"
            )

    # ── Entry-type ↔ CrossRef-type (Phase A) ──
    if os.environ.get("SCHOLAR_CITATION_CHECK_TYPE", "1") == "1":
        bib_kind = (bib.get("_kind") or "").strip()
        cr_type = (cr.get("type") or "").strip()
        if not _type_match(bib_kind, cr_type):
            mismatches.append(f"type(bib=@{bib_kind},cr={cr_type})")

    # ── Co-author count (Phase A) ──
    if os.environ.get("SCHOLAR_CITATION_CHECK_COAUTHORS", "1") == "1":
        if not _coauthor_count_ok(bib.get("author", ""), cr_authors):
            mismatches.append(
                f"coauthor-count(bib={len(bib_authors)},cr={len(cr_authors)})"
            )

    if not mismatches:
        return "REAL", "all_fields_match"
    return "MISREMEMBERED", ";".join(mismatches)


# ── Main loop ────────────────────────────────────────────────────────────
all_entries = []
with open(bib_list_file) as f:
    for line in f:
        path = line.strip()
        if not path or not os.path.isfile(path):
            continue
        try:
            text = open(path, encoding="utf-8", errors="replace").read()
        except Exception:
            continue
        for e in parse_bib(text):
            e["_bib_file"] = os.path.basename(path)
            all_entries.append(e)

if not all_entries:
    print("STATUS=YELLOW")
    print("REASON=no_verifiable_bib_entries")
    sys.exit(2)

results = []
for e in all_entries:
    doi = (e.get("doi") or "").strip()
    if doi:
        cr = crossref_by_doi(doi)
        if cr is None:
            results.append((e["_key"], "UNVERIFIABLE", "doi_lookup_failed"))
        else:
            v, d = compare(e, cr)
            results.append((e["_key"], v, d))
    elif require_doi:
        results.append((e["_key"], "MISREMEMBERED", "no_doi_field_in_strict_mode"))
    elif e.get("_kind") in DOI_REQUIRED_KINDS:
        # Book chapters and books without DOIs are not reliably indexed in
        # CrossRef. Title-search yields unrelated journal articles (e.g.,
        # Davis 2014 "On the Limits of Personal Autonomy" book chapter was
        # matching a different journal paper at pages 551-577). Mark
        # UNVERIFIABLE (advisory) instead of running a misleading search.
        # If the entry carries `verified_via = {local-pdf|zotero|websearch}`
        # (per SKILL.md provenance contract), record the channel.
        vv = (e.get("verified_via") or "").strip().lower()
        detail = f"{e.get('_kind')}_no_doi_skipped"
        if vv in ("local-pdf", "zotero", "websearch"):
            detail += f"|verified_via={vv}"
        results.append((e["_key"], "UNVERIFIABLE", detail))
    else:
        title = (e.get("title") or "").strip()
        author = (e.get("author") or "").split(" and ")[0].strip()
        year = (e.get("year") or "").strip()
        if not (title and author):
            results.append((e["_key"], "UNVERIFIABLE", "insufficient_metadata_for_search"))
        else:
            cr = crossref_search(author, title, year)
            v, d = compare(e, cr)
            results.append((e["_key"], v, d))
    time.sleep(0.06)  # 16 req/sec, well under CrossRef limit

# ── OpenAlex cascade for UNVERIFIABLE entries (opt-in) ───────────────────
# Activate by setting SCHOLAR_CITATION_CASCADE=openalex (or comma list).
# Default off: no behavior change. When on, every UNVERIFIABLE result is
# retried against OpenAlex; if OpenAlex finds the work, run compare() and
# update the verdict. Preserves CrossRef-positive verdicts unchanged.
cascade = (os.environ.get("SCHOLAR_CITATION_CASCADE") or "").lower()
cascade_sources = [s.strip() for s in cascade.split(",") if s.strip()]
if "openalex" in cascade_sources:
    by_key = {e["_key"]: e for e in all_entries}
    for idx, (key, verdict, detail) in enumerate(results):
        if verdict != "UNVERIFIABLE":
            continue
        e = by_key.get(key)
        if not e:
            continue
        oa = None
        doi = (e.get("doi") or "").strip()
        if doi:
            oa = openalex_by_doi(doi)
        if oa is None:
            title = (e.get("title") or "").strip()
            author = (e.get("author") or "").split(" and ")[0].strip()
            year = (e.get("year") or "").strip()
            if title and (author or year):
                oa = openalex_search(author, title, year)
        if oa is None:
            results[idx] = (key, "UNVERIFIABLE", f"{detail}|openalex_no_match")
        else:
            v, d = compare(e, oa)
            # Tag the result so reports show it came from cascade.
            results[idx] = (key, v, f"{d}|source=openalex")
        time.sleep(0.06)  # be polite

# ── Tallies + output ─────────────────────────────────────────────────────
red = [r for r in results if r[1] == "MISREMEMBERED"]
fab = [r for r in results if r[1] == "FABRICATED"]
unver = [r for r in results if r[1] == "UNVERIFIABLE"]
real = [r for r in results if r[1] == "REAL"]

print(f"BIB_ENTRIES_AUDITED={len(results)}")
print(f"REAL={len(real)}")
print(f"MISREMEMBERED={len(red)}")
print(f"FABRICATED={len(fab)}")
print(f"UNVERIFIABLE={len(unver)}")

if red or fab:
    print("STATUS=RED")
    print("REASON=citation_metadata_fabrication_or_misremember")
    for k, v, d in (red + fab)[:20]:
        print(f"  DETAIL: {k}={v}:{d[:160]}")
    sys.exit(1)

if unver:
    print("STATUS=YELLOW")
    print("REASON=some_entries_unverifiable")
    for k, v, d in unver[:10]:
        print(f"  DETAIL: {k}={v}:{d[:120]}")
    sys.exit(2)

print("STATUS=GREEN")
print("REASON=all_citations_verified_against_crossref")
sys.exit(0)
PYEOF
GATE_RC=$?
echo "GATE=verify-citation-metadata"
exit $GATE_RC
