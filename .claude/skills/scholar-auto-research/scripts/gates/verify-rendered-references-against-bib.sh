#!/usr/bin/env bash
# verify-rendered-references-against-bib.sh — Phase 11+ structural gate.
#
# RATIONALE: even after a .bib metadata pass removes pure-fabrication
# entries and corrects misattributions, the manuscript's rendered
# `## References` section can be silently repopulated with additional
# citations that have no corresponding `@` entry in the .bib file —
# typically when the LLM hand-writes the References list from parametric
# memory during a late regeneration pass. These phantom references look
# plausible (real-sounding authors, journals, and years) but never came
# from the verified bibliography.
#
# `verify-citation-metadata.sh` iterates the .bib only; it never reverse-
# maps the manuscript's rendered References section. `verify-citation-
# existence.sh` checks body `(Author Year)` → bib but treats the rendered
# References list as the OUTPUT, not as a candidate fabrication site.
# `phase8-citation-bypass-check.sh` explicitly excludes the References
# section from its scan (see that script's header). All three gates miss
# the failure shape where the LLM hand-writes the References list from
# parametric memory during Phase 11b regeneration.
#
# THIS GATE closes that gap. It enforces: every paragraph in the rendered
# `## References` section MUST have a corresponding @entry in the .bib
# file, matched by (first-author-surname, year).
#
# Exit codes:
#   0 — GREEN (every reference matches a bib entry)
#   1 — RED (one or more phantom references)
#   2 — YELLOW (manuscript or bib not found, References section empty,
#               or python3 unavailable)
#
# Usage:
#   verify-rendered-references-against-bib.sh <project_dir|manuscript_path>
#
# Optional second arg: explicit bib path. If absent, the script auto-
# discovers the newest .bib under <proj>/citations/, drafts/, manuscript/.
#
# Environment:
#   SCHOLAR_RR_DEBUG=1 — print extracted signatures for both sides.

set -uo pipefail
export LC_ALL=C

if [ $# -lt 1 ]; then
  echo "Usage: $(basename "$0") <project_dir|manuscript_path> [bib_path]" >&2
  exit 64
fi

INPUT="$1"
EXPLICIT_BIB="${2:-}"

# ── Resolve manuscript ─────────────────────────────────────────────
MS=""
PROJ=""
if [ -f "$INPUT" ]; then
  MS="$INPUT"
  # PROJ = grandparent if file lives under drafts/ or submission/
  PROJ="$(dirname "$(dirname "$MS")")"
elif [ -d "$INPUT" ]; then
  PROJ="$INPUT"
  # Discovery order mirrors submission-hygiene.sh + Phase 11.5 convention.
  # Use null-delimited find to handle paths with spaces (e.g., "My Drive").
  while IFS= read -r -d '' f; do
    MS="$f"
    break
  done < <(
    {
      [ -f "$PROJ/submission/manuscript.md" ] && printf '%s\0' "$PROJ/submission/manuscript.md"
      find "$PROJ/drafts" -maxdepth 1 -name "manuscript-submission-*.md" -print0 2>/dev/null | sort -rz
      find "$PROJ/drafts" -maxdepth 1 -name "manuscript-final-*.md" -print0 2>/dev/null | sort -rz
      find "$PROJ/manuscript" -maxdepth 1 -name "manuscript-submission-*.md" -print0 2>/dev/null | sort -rz
      find "$PROJ/manuscript" -maxdepth 1 -name "manuscript-final-*.md" -print0 2>/dev/null | sort -rz
      [ -f "$PROJ/manuscript/manuscript-draft.md" ] && printf '%s\0' "$PROJ/manuscript/manuscript-draft.md"
    } 2>/dev/null
  )
else
  echo "STATUS=YELLOW"
  echo "REASON=input_path_not_found:$INPUT"
  exit 2
fi

if [ -z "$MS" ] || [ ! -f "$MS" ]; then
  echo "STATUS=YELLOW"
  echo "REASON=manuscript_not_found_under:$PROJ"
  exit 2
fi

# ── Resolve bib ────────────────────────────────────────────────────
BIB=""
if [ -n "$EXPLICIT_BIB" ]; then
  if [ ! -f "$EXPLICIT_BIB" ]; then
    echo "STATUS=YELLOW"
    echo "REASON=explicit_bib_not_found:$EXPLICIT_BIB"
    exit 2
  fi
  BIB="$EXPLICIT_BIB"
else
  for d in "$PROJ/citations" "$PROJ/drafts" "$PROJ/manuscript" "$PROJ/citation"; do
    [ -d "$d" ] || continue
    cand=$(ls -t "$d"/*.bib 2>/dev/null | head -1)
    if [ -n "$cand" ] && [ -f "$cand" ]; then
      BIB="$cand"
      break
    fi
  done
fi

if [ -z "$BIB" ] || [ ! -f "$BIB" ]; then
  echo "STATUS=YELLOW"
  echo "REASON=bib_not_found_under:$PROJ"
  exit 2
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "STATUS=YELLOW"
  echo "REASON=python3_missing"
  exit 2
fi

# ── Cross-check ────────────────────────────────────────────────────
python3 - "$MS" "$BIB" <<'PYEOF'
import os
import re
import sys
import unicodedata

ms_path, bib_path = sys.argv[1], sys.argv[2]
debug = os.environ.get("SCHOLAR_RR_DEBUG") == "1"


def normalize(s):
    s = unicodedata.normalize("NFD", s)
    s = "".join(c for c in s if not unicodedata.combining(c))
    return re.sub(r"[^a-z0-9]", "", s.lower())


_STOPWORDS = {
    "a", "an", "the", "of", "in", "on", "for", "and", "or", "with",
    "to", "from", "as", "by", "at", "is", "are", "be",
}


def title_tokens(s):
    s = unicodedata.normalize("NFD", s)
    s = "".join(c for c in s if not unicodedata.combining(c))
    # Normalize all hyphen/dash variants to a single ASCII space so that
    # "1964--2000" (LaTeX), "1964–2000" (en-dash), and "1964-2000" yield
    # identical tokens. Bib often uses `--` (LaTeX en-dash); prose often
    # uses Unicode `–`. Without normalization, "1964--2000" ≠ "1964 2000".
    s = re.sub(r"[\-–—‐‑‒]+", " ", s)
    s = re.sub(r"[^A-Za-z0-9\s]", " ", s)
    toks = [t.lower() for t in s.split() if t]
    return [t for t in toks if t not in _STOPWORDS and len(t) > 1]


def title_similarity(a, b):
    """Jaccard token-set similarity, stopwords removed. 0.0 .. 1.0

    Fallback: when either side has zero content tokens (e.g., the value is a
    single short word like "J" or contains only stopwords), token-set
    Jaccard is undefined. Use direct lowercase-equality as a backoff so that
    identical-but-short fields don't false-flag as drift.
    """
    sa = set(title_tokens(a))
    sb = set(title_tokens(b))
    if not sa or not sb:
        if a and b and a.strip().lower() == b.strip().lower():
            return 1.0
        return 0.0
    return len(sa & sb) / len(sa | sb)


def extract_braced_value(body, m_start):
    """Walk braces from position m_start (just past `{`); return inner value."""
    depth = 1
    k = m_start
    while k < len(body) and depth > 0:
        ch = body[k]
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
        k += 1
    return body[m_start:k - 1].strip()


def get_field(body, field):
    """Pull a top-level field value from a bib entry body, brace-tolerant."""
    m = re.search(r"\b" + re.escape(field) + r"\s*=\s*[{\"]", body, re.IGNORECASE)
    if not m:
        return None
    val = extract_braced_value(body, m.end())
    # Strip protective braces and TeX accent markers; keep inner text readable.
    val = re.sub(r"\\['\"`^~=\.bcdHkruv]\{?([A-Za-z])\}?", r"\1", val)
    val = val.replace("{", "").replace("}", "").strip()
    return val if val else None


def normalize_pages(s):
    """Normalize a page-range string to 'N-N' or 'N' for comparison."""
    if not s:
        return None
    s = s.replace("–", "-").replace("—", "-").replace("--", "-")
    m = re.search(r"(\d+)\s*-\s*(\d+)", s)
    if m:
        return f"{m.group(1)}-{m.group(2)}"
    m = re.search(r"(\d+)", s)
    return m.group(1) if m else s


def extract_bib_author_surnames(author_val, institutional):
    """Extract a list of normalized surnames from a bib author= field value.

    Examples:
      "Smith, Jane A."                                  → ["smith"]
      "Smith, Jane A. and Jones, Mary K."               → ["smith", "jones"]
      "Smith, Jane and Lee, Mei and Brown, Bob"         → ["smith", "lee", "brown"]
      "Das Gupta, Prithwis"                             → ["das"]
      "{United Nations}"                                → ["united"]
    """
    if not author_val:
        return []
    if institutional:
        inner = author_val.strip()
        if inner.startswith("{") and inner.endswith("}"):
            inner = inner[1:-1]
        tok = inner.strip().split()
        return [normalize(tok[0])] if tok else []
    parts = re.split(r"\s+and\s+", author_val)
    surnames = []
    for p in parts:
        p = p.strip().replace("{", "").replace("}", "").strip()
        if not p:
            continue
        # BibTeX "Last, First" form → take everything before the first comma,
        # then first whitespace-token (so "Das Gupta, Prithwis" → "Das").
        if "," in p:
            seg = p.split(",", 1)[0].strip()
            toks = seg.split()
            if toks:
                surnames.append(normalize(toks[0]))
        else:
            # "First Last" form (no comma) → last token is the surname.
            toks = p.split()
            if toks:
                surnames.append(normalize(toks[-1]))
    return surnames


def extract_prose_author_surnames(paragraph):
    """Extract a list of normalized surnames from the author-list portion of a
    rendered reference paragraph. Handles both ASA author-date and APA forms.

    ASA:  "Smith, Jane A., and James A. Sweet. 1989."
    APA:  "Smith, J. A., & Sweet, J. A. (1989)."
    Three+ ASA: "Smith, Jane A., John K. Jones, and Mary L. Brown. 2010."
    """
    # Find the year marker, which terminates the author list.
    # APA wraps year in parens: "Author (YYYY)."
    # ASA puts a bare year after a period: "Author. YYYY."
    # NOTE: titles often contain "(YYYY)" — e.g., "A Comment on Smith (2014)"
    # — so we must pick the EARLIEST year marker rather than preferring APA
    # unconditionally. The genuine publication-year marker always appears
    # immediately after the author list, before any title text.
    m_yr_apa = re.search(r"\(\d{4}[a-z]?\)", paragraph)
    m_yr_asa = re.search(r"\.\s+(?:1[6789]\d{2}|20\d{2})[\.,]", paragraph)
    apa_pos = m_yr_apa.start() if m_yr_apa else float("inf")
    asa_pos = m_yr_asa.start() if m_yr_asa else float("inf")
    if asa_pos == float("inf") and apa_pos == float("inf"):
        return []
    if asa_pos <= apa_pos:
        author_text = paragraph[:asa_pos].rstrip()
        style = "asa"
    else:
        author_text = paragraph[:apa_pos].rstrip()
        style = "apa"

    # Normalize "&" to "and" for uniform handling.
    norm = re.sub(r"\s*&\s*", " and ", author_text)

    # Split into [PRE, LAST] at the final " and " (which always precedes the
    # last author in both ASA and APA-with-and forms). If no " and " present,
    # it's a single-author reference.
    m_last_and = None
    for m in re.finditer(r"\s+and\s+", norm):
        m_last_and = m
    if m_last_and is None:
        pre = norm
        last = None
    else:
        pre = norm[:m_last_and.start()]
        last = norm[m_last_and.end():]

    def parse_author_token(tok):
        """Given an author chunk, return its normalized surname or None."""
        tok = tok.strip().rstrip(".,;")
        if not tok:
            return None
        if "," in tok:
            # "Last, First..." form — surname is first token before comma.
            seg = tok.split(",", 1)[0].strip()
            t = seg.split()
            return normalize(t[0]) if t else None
        else:
            # "First M. Last" form — surname is the last whitespace token.
            t = tok.split()
            return normalize(t[-1]) if t else None

    surnames = []

    # The first author always appears at the start of PRE in "Last, First..."
    # form (the canonical convention in both ASA and APA author-date). Take
    # the first comma-delimited segment as the first author's surname.
    first_seg = pre.strip().rstrip(",")
    if "," in first_seg:
        first_last = first_seg.split(",", 1)[0].strip().split()
        if first_last:
            surnames.append(normalize(first_last[0]))
        # Remainder of PRE after the first-author's "Last, First[, M.]" block:
        # this is harder because ASA writes "Smith, Jane A., John K. Jones,"
        # while APA writes "Smith, J. A., Jones, J. K.,". Heuristic: split
        # the remainder on `,\s+` and emit pairs.
        remainder = first_seg.split(",", 1)[1].strip()
        # Drop the first-author's firstname segment (one comma-delimited chunk).
        sub_chunks = [c.strip() for c in remainder.split(",") if c.strip()]
        if sub_chunks:
            # sub_chunks[0] is the first author's firstname/initials → drop.
            sub_chunks = sub_chunks[1:]
        # Now we may have either:
        #   - APA-style alternating pairs: ["Jones", "J. K.", "Brown", "M. L."]
        #   - ASA-style "First M. Last" chunks: ["John K. Jones"]
        i = 0
        while i < len(sub_chunks):
            chunk = sub_chunks[i]
            # If next chunk looks like initials only ("J. K.", "A.", etc.),
            # treat (chunk, next) as APA pair: chunk is surname.
            if i + 1 < len(sub_chunks) and re.match(
                r"^[A-Z]\.?(\s*[A-Z]\.?)*\s*$", sub_chunks[i + 1]
            ):
                surnames.append(normalize(chunk.split()[0]))
                i += 2
            else:
                # ASA "First M. Last" — surname is the last token.
                toks = chunk.split()
                if toks:
                    surnames.append(normalize(toks[-1]))
                i += 1
    else:
        # PRE has no comma → single-author "First Last" form (rare in refs).
        toks = first_seg.split()
        if toks:
            surnames.append(normalize(toks[-1]))

    if last is not None:
        s = parse_author_token(last)
        if s:
            surnames.append(s)

    # Deduplicate while preserving order.
    seen = set()
    out = []
    for s in surnames:
        if s and s not in seen:
            seen.add(s)
            out.append(s)
    return out


# ── Parse bib → set of (surname_norm, year) ────────────────────────
with open(bib_path, encoding="utf-8", errors="replace") as f:
    bib_text = f.read()

# Walk entries by @TYPE{KEY,
entries = []
i = 0
while True:
    m = re.search(r"@(\w+)\s*\{", bib_text[i:])
    if not m:
        break
    start = i + m.end()
    # Find matching close brace at depth 0
    depth = 1
    j = start
    while j < len(bib_text) and depth > 0:
        c = bib_text[j]
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
        j += 1
    entries.append((m.group(1).lower(), bib_text[start:j - 1]))
    i = j

bib_sigs = set()
bib_surnames_by_year = {}
bib_entries_by_sig = {}  # (surname_norm, year) -> [ {kind, title, journal, volume, issue, pages, doi} ]
for kind, body in entries:
    if kind.startswith("comment") or kind.startswith("string") or kind.startswith("preamble"):
        continue
    m_auth = re.search(r"\bauthor\s*=\s*[{\"]", body, re.IGNORECASE)
    m_year = re.search(r"\byear\s*=\s*\{?\s*(\d{4})\s*\}?", body, re.IGNORECASE)
    if not m_auth or not m_year:
        # Books/dataset entries with editor= only — treat editor as author.
        m_auth = re.search(r"\beditor\s*=\s*[{\"]", body, re.IGNORECASE)
        if not m_auth or not m_year:
            continue
    year = m_year.group(1)

    # Pull author value as braced block.
    author_val = extract_braced_value(body, m_auth.end())
    # Split on " and "
    first_author = re.split(r"\s+and\s+", author_val)[0].strip()
    # Detect brace-protected institutional name: BibTeX `{{United Nations}}`
    # arrives here as `{United Nations}` (outer braces stripped by the brace-
    # walking loop). Treat as a single name unit; surname = first token.
    institutional = False
    if first_author.startswith("{") and first_author.endswith("}"):
        institutional = True
        first_author = first_author[1:-1].strip()
    # BibTeX "Last, First" form → surname before comma; else "First Last" → last token
    if "," in first_author:
        surname_segment = first_author.split(",", 1)[0]
    elif institutional:
        # {{Institution Name}} → take FIRST token of the institutional name
        # so it matches manuscript-side extraction of "United Nations, ..."
        surname_segment = first_author
    else:
        toks = first_author.split()
        surname_segment = toks[-1] if toks else ""
    # Take FIRST whitespace-separated token of the surname segment so that
    # compound surnames parse consistently with manuscript-side extraction
    # (which also takes the leading capitalised word). Example:
    #   "Das Gupta, Prithwis"     → "Das"      (matches manuscript "Das")
    #   "Van de Kaa, Dirk J."     → "Van"      (matches manuscript "Van")
    #   "{United Nations}"        → "United"   (institutional path above)
    surname_segment = surname_segment.replace("{", "").replace("}", "").strip()
    surname = surname_segment.split()[0] if surname_segment.split() else ""
    if not surname:
        continue
    nsur = normalize(surname)
    bib_sigs.add((nsur, year))
    bib_surnames_by_year.setdefault(year, set()).add(nsur)
    # Capture detail fields for field-level comparison.
    bib_entries_by_sig.setdefault((nsur, year), []).append({
        "kind": kind,
        "title": get_field(body, "title"),
        "journal": get_field(body, "journal") or get_field(body, "booktitle"),
        "volume": get_field(body, "volume"),
        "issue": get_field(body, "number") or get_field(body, "issue"),
        "pages": get_field(body, "pages"),
        "doi": get_field(body, "doi"),
        "authors": extract_bib_author_surnames(author_val, institutional),
    })

if debug:
    print("DEBUG bib_sigs=" + repr(sorted(bib_sigs)), file=sys.stderr)

# ── Parse manuscript References section ────────────────────────────
with open(ms_path, encoding="utf-8", errors="replace") as f:
    ms_text = f.read()

# Find ## References (or Bibliography / Works Cited)
ref_header = re.search(
    r"^##\s+(References|Bibliography|Works\s+Cited)\s*$",
    ms_text, re.IGNORECASE | re.MULTILINE,
)
if not ref_header:
    print("STATUS=YELLOW")
    print("REASON=no_references_section_in_manuscript")
    sys.exit(2)

after = ms_text[ref_header.end():]
# Cut at next heading at same or higher level
next_head = re.search(r"^#{1,2}\s+\S", after, re.MULTILINE)
refs_text = after[:next_head.start()] if next_head else after

# Group into paragraphs (blank-line separated)
paragraphs = []
current = []
in_code = False
in_html_comment = False
for ln in refs_text.split("\n"):
    s = ln.rstrip()
    if s.startswith("```"):
        in_code = not in_code
        continue
    if in_code:
        continue
    if "<!--" in s and "-->" not in s:
        in_html_comment = True
    if in_html_comment:
        if "-->" in s:
            in_html_comment = False
        continue
    if not s.strip():
        if current:
            paragraphs.append(" ".join(current))
            current = []
    else:
        current.append(s.strip())
if current:
    paragraphs.append(" ".join(current))

# Strip leftover HTML comments inside paragraphs
clean_paragraphs = []
for p in paragraphs:
    p = re.sub(r"<!--.*?-->", "", p)
    p = p.strip()
    if not p:
        continue
    # Skip lines that look like raw bibkeys or markup-only
    if re.match(r"^\[.*\]$", p):  # e.g., "[note]"
        continue
    clean_paragraphs.append(p)

if not clean_paragraphs:
    print("STATUS=YELLOW")
    print("REASON=references_section_empty")
    print(f"  manuscript: {ms_path}")
    sys.exit(2)


def extract_signature(paragraph):
    # First surname: leading capitalised word(s). Allow hyphens, apostrophes,
    # accented letters. For "Van de Kaa, Dirk" we take "Van" as primary token
    # (the bib's surname extraction does the same).
    m_name = re.match(
        r"^\s*([A-ZÀ-ſ][A-Za-zÀ-ſ\-\']+)",
        paragraph,
    )
    if not m_name:
        return None
    surname = m_name.group(1)
    m_year = re.search(r"\b(1[6789]\d{2}|20\d{2})\b", paragraph)
    if not m_year:
        return None
    return (normalize(surname), m_year.group(1), surname, m_year.group(1))


def extract_prose_fields(paragraph):
    """Parse title / journal / volume / issue / pages from a rendered
    ASA-style reference paragraph. Returns dict with None for absent fields.

    Shapes handled:
      Smith, J. 2020. "Title." *Journal* 26(4): 615-625.        (article)
      Smith, J. 2014. *Book Title*. Pub: City.                  (book)
      Smith, J. 2010. "Chapter." In *Book Title*, ed. ..., 9-24. (chapter)
    """
    fields = {"title": None, "journal": None, "volume": None,
              "issue": None, "pages": None}

    # Title extraction — three style channels (try in order):
    #   1. ASA author-date: title in straight or curly quotes.
    #      → Author. YYYY. "Title." *Journal* Vol(N): Pages.
    #   2. APA: year in parens, title between "(YYYY)." and " *Journal*"/period.
    #      → Author (YYYY). Title in sentence case. *Journal*, Vol(N), Pages.
    #   3. Book / no-article: first *italic* IS the title.
    #      → Author. YYYY. *Book Title*. Publisher.
    after_title_pos = 0
    m_title = re.search(
        r'[\"“]([^\"“”]+?)[\"”]\.?',
        paragraph,
    )
    if m_title:
        fields["title"] = m_title.group(1).strip().rstrip(".")
        after_title_pos = m_title.end()
        # Journal/booktitle is the *italic* that follows the title.
        after_title = paragraph[after_title_pos:]
        m_italic = re.search(r"\*([^*]+?)\*", after_title)
        if m_italic:
            fields["journal"] = m_italic.group(1).strip().rstrip(".,")
    else:
        # APA-style: "(YYYY)[a-z]?. Title. *Journal*, ..."
        # Stop at "In " (chapter→book separator) OR at the journal italic,
        # whichever comes first. Handles book-chapter refs:
        #   "Author (YYYY). Chapter title. In Editor (Ed.), *Book*, pp. X-Y."
        # — title is "Chapter title", not "Book".
        m_apa = re.search(
            r"\(\d{4}[a-z]?\)\.?\s+(.+?)\.\s+(?:In\s+\S|(?=\*))",
            paragraph,
        )
        if m_apa:
            fields["title"] = m_apa.group(1).strip()
            after_title_pos = m_apa.end()
            m_italic = re.search(r"\*([^*]+?)\*", paragraph[after_title_pos:])
            if m_italic:
                fields["journal"] = m_italic.group(1).strip().rstrip(".,")
        else:
            # No quoted title and no APA shape — likely a book entry where
            # the *italic* IS the title (e.g., "Smith, J. 2014. *Book*. Pub.").
            m_italic = re.search(r"\*([^*]+?)\*", paragraph)
            if m_italic:
                fields["title"] = m_italic.group(1).strip().rstrip(".,")
                after_title_pos = m_italic.end()

    # Volume(Issue): handle both ASA ("*J* 26(4):") and APA ("*J*, 26(4),").
    # Allow comma OR whitespace between the journal italic and the volume,
    # and accept colon, comma, or whitespace after the issue parenthesis.
    post_title = paragraph[after_title_pos:]
    m_vol = re.search(
        r"\*[^*]+\*[,\s]+([A-Z]?\d+)(?:\((\d+(?:[\-–/]\d+)?)\))?[,:\s]",
        post_title,
    )
    if m_vol:
        fields["volume"] = m_vol.group(1)
        if m_vol.group(2):
            fields["issue"] = m_vol.group(2)

    # Pages: anchored AFTER the title's close quote (so titles containing
    # colon+year-range like "...: 1985-2009" can't leak into the page slot).
    # If volume(issue) marker exists, anchor further: after that marker.
    page_search_region = post_title
    if m_vol:
        page_search_region = post_title[m_vol.end():]
    # Strip DOI / URL suffixes before page extraction. A bare DOI like
    # `10.1017/S0007123424000419` would otherwise match as a 2-digit page
    # number "10" because of the leading `[:,]\s*10` pattern.
    page_search_region = re.sub(r"https?://\S+", "", page_search_region)
    page_search_region = re.sub(r"\bdoi\s*:?\s*\S+", "",
                                page_search_region, flags=re.IGNORECASE)
    page_search_region = re.sub(r"\b10\.\d{4,9}/\S+", "", page_search_region)
    m_pages = re.search(
        r"(?:^|[:,])\s*(\d+\s*[-––]\s*\d+|\d{2,})(?!\.\d)\s*\.?",
        page_search_region,
    )
    if m_pages:
        fields["pages"] = m_pages.group(1)

    return fields


def field_mismatches(prose, bib_entry):
    """Compare prose-parsed fields vs bib entry. Return list of
    (field_name, prose_value, bib_value) for disagreements that exceed
    tolerance. Skip fields when either side is missing."""
    issues = []
    bk = bib_entry.get("kind", "")

    # Authors — set-equality on normalized surnames.
    # Skip when either side has zero parseable authors (defensive — single-
    # author APA like "Smith, J. (2020)." can have ambiguous chunks).
    # Also skip when the bib has exactly 1 author: institutional bibs like
    # `{{United Nations}}` produce 1-surname bib lists, but the prose rendering
    # ("United Nations, Department of ...") looks like a multi-author string
    # to a generic parser. The first-author signature match (covered upstream
    # by extract_signature) already validates the single-author case.
    bib_authors = bib_entry.get("authors") or []
    prose_authors = prose.get("authors") or []
    if len(bib_authors) >= 2 and prose_authors:
        bib_set = set(bib_authors)
        prose_set = set(prose_authors)
        if bib_set != prose_set:
            missing = bib_set - prose_set
            extra = prose_set - bib_set
            issues.append((
                "authors",
                f"prose={prose_authors}",
                f"bib={bib_authors}"
                + (f" | missing_from_prose={sorted(missing)}" if missing else "")
                + (f" | extra_in_prose={sorted(extra)}" if extra else ""),
            ))

    # Title — Jaccard token-set similarity; threshold 0.55 (tolerant for
    # punctuation/casing variation; restrictive enough to catch fabrications).
    if prose["title"] and bib_entry.get("title"):
        sim = title_similarity(prose["title"], bib_entry["title"])
        if sim < 0.55:
            issues.append(("title", prose["title"][:80], bib_entry["title"][:80]))

    # Journal — only for @article (book entries have booktitle for the
    # containing volume, which doesn't appear identically in prose).
    if bk == "article" and prose["journal"] and bib_entry.get("journal"):
        sim = title_similarity(prose["journal"], bib_entry["journal"])
        if sim < 0.55:
            issues.append(("journal", prose["journal"][:60], bib_entry["journal"][:60]))

    # Volume — exact match when both present (article-only).
    if bk == "article" and prose["volume"] and bib_entry.get("volume"):
        if normalize(prose["volume"]) != normalize(bib_entry["volume"]):
            issues.append(("volume", prose["volume"], bib_entry["volume"]))

    # Issue — exact match when both present.
    if bk == "article" and prose["issue"] and bib_entry.get("issue"):
        if normalize(prose["issue"]) != normalize(bib_entry["issue"]):
            issues.append(("issue", prose["issue"], bib_entry["issue"]))

    # Pages — exact after normalization, when both present.
    if prose["pages"] and bib_entry.get("pages"):
        p_norm = normalize_pages(prose["pages"])
        b_norm = normalize_pages(bib_entry["pages"])
        if p_norm and b_norm and p_norm != b_norm:
            issues.append(("pages", prose["pages"], bib_entry["pages"]))

    return issues


phantoms = []
matched = []
field_drifts = []  # list of (raw_sur, raw_year, paragraph_excerpt, issues_list)
unparseable = []
for p in clean_paragraphs:
    sig = extract_signature(p)
    if sig is None:
        unparseable.append(p[:120])
        continue
    nsur, year, raw_sur, raw_year = sig
    # Resolve the matching bib-entry list (exact or soft-prefix match).
    match_key = None
    if (nsur, year) in bib_sigs:
        match_key = (nsur, year)
    else:
        for bib_nsur in bib_surnames_by_year.get(year, set()):
            if bib_nsur.startswith(nsur) or nsur.startswith(bib_nsur):
                if min(len(bib_nsur), len(nsur)) >= 4:
                    match_key = (bib_nsur, year)
                    break
    if match_key is None:
        phantoms.append((raw_sur, raw_year, p[:160]))
        continue

    matched.append((raw_sur, raw_year))
    # Field-level comparison: if ANY candidate entry under this signature
    # is consistent with the prose, we accept. Only flag drift if NO
    # candidate matches.
    prose = extract_prose_fields(p)
    prose["authors"] = extract_prose_author_surnames(p)
    candidates = bib_entries_by_sig.get(match_key, [])
    best_issues = None
    for cand in candidates:
        issues = field_mismatches(prose, cand)
        if not issues:
            best_issues = []
            break
        if best_issues is None or len(issues) < len(best_issues):
            best_issues = issues
    if best_issues:
        field_drifts.append((raw_sur, raw_year, p[:200], best_issues))

if debug:
    print(f"DEBUG matched={len(matched)} phantom={len(phantoms)} field_drift={len(field_drifts)}",
          file=sys.stderr)

# ── Verdict ────────────────────────────────────────────────────────
total = len(clean_paragraphs)
if phantoms or field_drifts:
    reasons = []
    if phantoms:
        reasons.append(f"phantom_references:{len(phantoms)}")
    if field_drifts:
        reasons.append(f"field_drifts:{len(field_drifts)}")
    print("STATUS=RED")
    print(f"REASON={','.join(reasons)}:{total}_total")
    print(f"  manuscript: {ms_path}")
    print(f"  bib:        {bib_path}")
    print(f"  matched (sig+fields): {len(matched) - len(field_drifts)}/{total}")
    print(f"  unparseable: {len(unparseable)}")

    if phantoms:
        print(f"  phantom references — {len(phantoms)} (surname/year not in bib):")
        for raw_sur, raw_year, excerpt in phantoms[:20]:
            print(f"    - {raw_sur} {raw_year} — {excerpt}")
        if len(phantoms) > 20:
            print(f"    … ({len(phantoms) - 20} more)")

    if field_drifts:
        print(f"  field drifts — {len(field_drifts)} (signature matched but"
              " prose details disagree with bib):")
        for raw_sur, raw_year, excerpt, issues in field_drifts[:20]:
            print(f"    - {raw_sur} {raw_year} —")
            print(f"        prose: {excerpt[:140]}")
            for field, prose_v, bib_v in issues:
                print(f"        DRIFT {field}: prose={prose_v!r} | bib={bib_v!r}")
        if len(field_drifts) > 20:
            print(f"    … ({len(field_drifts) - 20} more)")

    print()
    print("  FIX:")
    if phantoms:
        print("    - phantom: either (a) add @entry via /scholar-citation"
              " materialize, or (b) remove paragraph if not cited in body.")
    if field_drifts:
        print("    - field drift: prose paragraph disagrees with bib entry."
              " Re-render via pandoc citeproc from the bib (canonical), or")
        print("      correct the bib entry if it itself is wrong"
              " (run verify-citation-metadata.sh to check against CrossRef).")
    sys.exit(1)
else:
    print("STATUS=GREEN")
    print(f"  manuscript: {ms_path}")
    print(f"  bib:        {bib_path}")
    print(f"  references: {total} paragraphs, all matched to bib entries"
          " (signature + field-level)")
    if unparseable:
        print(f"  unparseable: {len(unparseable)} (likely non-reference lines)")
    sys.exit(0)
PYEOF
