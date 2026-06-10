#!/usr/bin/env bash
# verify-citation-local-library.sh — Phase 8/11/11.5 structural gate.
#
# AUDIT TRAIL (2026-05-25): The first two citation-authority gates are
#   (1) verify-citation-metadata.sh — bib ↔ CrossRef DOI registry
#   (2) verify-rendered-references-against-bib.sh — manuscript prose ↔ bib
# Neither catches the class "bib has an @entry the user has never engaged
# with in their own curated library" — a strong LLM-fabrication signal,
# because an LLM can hallucinate plausible-but-unread papers, but it cannot
# hallucinate items into the operator's local Zotero. This gate adds that
# third axis.
#
# Authority direction: bib → user's local library (Zotero detected first;
# other backends planned).
#
# Per-entry verdicts:
#   MATCHED_LOCAL       — found in library AND all comparable fields agree
#   MISMATCHED_LOCAL    — found in library BUT ≥1 field disagrees (RED — drift
#                         between project bib and master library)
#   NOT_IN_LOCAL        — no library counterpart (YELLOW — informational; the
#                         operator may have just-discovered or colleague-shared
#                         papers; not all real citations are in personal Zotero)
#   EXEMPT_VERIFIED_VIA — bib entry has `verified_via = {websearch|...}`
#                         (documented escape hatch from mode-convert-export.md D-4)
#   LOCAL_UNAVAILABLE   — Zotero install not detected, or DB unreadable (YELLOW)
#
# Exit codes:
#   0 GREEN  — no MISMATCHED_LOCAL entries
#   1 RED    — ≥1 MISMATCHED_LOCAL
#   2 YELLOW — library unavailable, manuscript/bib missing, or all entries
#              fell into NOT_IN_LOCAL (no signal)
#
# Usage:
#   verify-citation-local-library.sh <project_dir> [bib_path]
#
# Environment:
#   SCHOLAR_ZOTERO_DIR — explicit Zotero install path (skips auto-detection)
#   SCHOLAR_LOCAL_LIB_DEBUG=1 — print per-entry detail to stderr

set -uo pipefail
export LC_ALL=C

if [ $# -lt 1 ]; then
  echo "Usage: $(basename "$0") <project_dir> [bib_path]" >&2
  exit 64
fi

PROJ="$1"
EXPLICIT_BIB="${2:-}"

if [ ! -d "$PROJ" ]; then
  echo "STATUS=YELLOW"
  echo "REASON=project_dir_not_found:$PROJ"
  exit 2
fi

# ── Resolve bib (same pattern as verify-rendered-references-against-bib) ──
BIB=""
if [ -n "$EXPLICIT_BIB" ]; then
  [ -f "$EXPLICIT_BIB" ] && BIB="$EXPLICIT_BIB"
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

# ── Auto-detect Zotero install ────────────────────────────────────────
ZOTERO_DB=""
ZOTERO_CANDIDATES=()
if [ -n "${SCHOLAR_ZOTERO_DIR:-}" ] && [ -f "${SCHOLAR_ZOTERO_DIR}/zotero.sqlite" ]; then
  ZOTERO_DB="${SCHOLAR_ZOTERO_DIR}/zotero.sqlite"
else
  # Match the path patterns documented in refmanager-backends.md.
  while IFS= read -r -d '' f; do
    ZOTERO_CANDIDATES+=("$f")
  done < <(
    {
      [ -f "$HOME/Zotero/zotero.sqlite" ] && printf '%s\0' "$HOME/Zotero/zotero.sqlite"
      [ -f "$HOME/Documents/Zotero/zotero.sqlite" ] && printf '%s\0' "$HOME/Documents/Zotero/zotero.sqlite"
      [ -f "$HOME/snap/zotero-snap/common/Zotero/zotero.sqlite" ] && printf '%s\0' "$HOME/snap/zotero-snap/common/Zotero/zotero.sqlite"
      find "$HOME/Library/CloudStorage" -maxdepth 4 -name "zotero.sqlite" -print0 2>/dev/null
      find "$HOME/Google Drive" -maxdepth 3 -name "zotero.sqlite" -print0 2>/dev/null
    } 2>/dev/null
  )
  if [ "${#ZOTERO_CANDIDATES[@]}" -gt 0 ]; then
    ZOTERO_DB="${ZOTERO_CANDIDATES[0]}"
  fi
fi

if [ -z "$ZOTERO_DB" ]; then
  echo "STATUS=YELLOW"
  echo "REASON=zotero_not_detected"
  echo "  Set SCHOLAR_ZOTERO_DIR to your Zotero data directory, or install Zotero."
  exit 2
fi

# ── Run the verification in Python ────────────────────────────────────
python3 - "$BIB" "$ZOTERO_DB" <<'PYEOF'
import os
import re
import sqlite3
import shutil
import sys
import tempfile
import unicodedata

bib_path, zotero_src = sys.argv[1], sys.argv[2]
debug = os.environ.get("SCHOLAR_LOCAL_LIB_DEBUG") == "1"


def normalize(s):
    s = unicodedata.normalize("NFD", s or "")
    s = "".join(c for c in s if not unicodedata.combining(c))
    return re.sub(r"[^a-z0-9]", "", s.lower())


_STOPWORDS = {
    "a", "an", "the", "of", "in", "on", "for", "and", "or", "with",
    "to", "from", "as", "by", "at", "is", "are", "be",
}


def title_tokens(s):
    s = unicodedata.normalize("NFD", s or "")
    s = "".join(c for c in s if not unicodedata.combining(c))
    s = re.sub(r"[\-–—‐‑‒]+", " ", s)
    s = re.sub(r"[^A-Za-z0-9\s]", " ", s)
    toks = [t.lower() for t in s.split() if t]
    return [t for t in toks if t not in _STOPWORDS and len(t) > 1]


def title_similarity(a, b):
    sa = set(title_tokens(a))
    sb = set(title_tokens(b))
    if not sa or not sb:
        if a and b and a.strip().lower() == b.strip().lower():
            return 1.0
        return 0.0
    return len(sa & sb) / len(sa | sb)


def normalize_pages(s):
    if not s:
        return None
    s = s.replace("–", "-").replace("—", "-").replace("--", "-")
    m = re.search(r"(\d+)\s*-\s*(\d+)", s)
    if m:
        return f"{m.group(1)}-{m.group(2)}"
    m = re.search(r"(\d+)", s)
    return m.group(1) if m else s


# ── Parse bib ────────────────────────────────────────────────────────
with open(bib_path, encoding="utf-8", errors="replace") as f:
    bib_text = f.read()

entries = []
i = 0
while True:
    m = re.search(r"@(\w+)\s*\{([^,]+),", bib_text[i:])
    if not m:
        break
    kind = m.group(1).lower()
    key = m.group(2).strip()
    start = i + m.end()
    depth = 1
    j = start
    while j < len(bib_text) and depth > 0:
        c = bib_text[j]
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
        j += 1
    entries.append((kind, key, bib_text[start:j - 1]))
    i = j


def get_field(body, field):
    m = re.search(r"\b" + re.escape(field) + r"\s*=\s*[{\"]", body, re.IGNORECASE)
    if not m:
        return None
    depth = 1
    k = m.end()
    while k < len(body) and depth > 0:
        ch = body[k]
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
        k += 1
    val = body[m.end():k - 1].strip()
    val = re.sub(r"\\['\"`^~=.bcdHkruv]\{?([A-Za-z])\}?", r"\1", val)
    return val.replace("{", "").replace("}", "").strip() or None


def extract_first_surname(author_val):
    if not author_val:
        return ""
    first_author = re.split(r"\s+and\s+", author_val)[0].strip()
    if first_author.startswith("{") and first_author.endswith("}"):
        first_author = first_author[1:-1].strip()
    if "," in first_author:
        seg = first_author.split(",", 1)[0]
    else:
        toks = first_author.split()
        seg = toks[-1] if toks else ""
    seg = seg.replace("{", "").replace("}", "").strip()
    toks = seg.split()
    return toks[0] if toks else ""


def extract_all_surnames(author_val):
    if not author_val:
        return []
    parts = re.split(r"\s+and\s+", author_val)
    out = []
    for p in parts:
        p = p.strip().replace("{", "").replace("}", "").strip()
        if not p:
            continue
        if "," in p:
            seg = p.split(",", 1)[0].strip()
            toks = seg.split()
            if toks:
                out.append(normalize(toks[0]))
        else:
            toks = p.split()
            if toks:
                out.append(normalize(toks[-1]))
    return out


# ── Snapshot Zotero DB to /tmp for read-only safety ──────────────────
with tempfile.NamedTemporaryFile(suffix=".sqlite", delete=False) as tf:
    tmp_db = tf.name
try:
    shutil.copy(zotero_src, tmp_db)
except Exception as e:
    print("STATUS=YELLOW")
    print(f"REASON=zotero_db_copy_failed:{e}")
    sys.exit(2)

try:
    conn = sqlite3.connect(f"file:{tmp_db}?mode=ro", uri=True, timeout=5)
    conn.row_factory = sqlite3.Row
    cur = conn.cursor()
except Exception as e:
    os.unlink(tmp_db)
    print("STATUS=YELLOW")
    print(f"REASON=zotero_db_open_failed:{e}")
    sys.exit(2)

# Build a single query — one row per Zotero item — that returns everything we need.
ITEM_SQL = """
SELECT
  i.itemID AS item_id,
  title.value AS title,
  SUBSTR(COALESCE(yr.value, ''), 1, 4) AS year,
  COALESCE(pub.value, '') AS journal,
  COALESCE(doi.value, '') AS doi,
  COALESCE(vol.value, '') AS volume,
  COALESCE(iss.value, '') AS issue,
  COALESCE(pg.value, '') AS pages,
  it.typeName AS itype,
  (SELECT GROUP_CONCAT(cr.lastName, '|')
   FROM itemCreators ic
   JOIN creators cr ON ic.creatorID = cr.creatorID
   WHERE ic.itemID = i.itemID
   ORDER BY ic.orderIndex) AS surnames_pipe
FROM items i
JOIN itemTypes it ON i.itemTypeID = it.itemTypeID
JOIN itemData td ON i.itemID = td.itemID
JOIN fields ft ON td.fieldID = ft.fieldID AND ft.fieldName = 'title'
JOIN itemDataValues title ON td.valueID = title.valueID
LEFT JOIN itemData yd ON i.itemID = yd.itemID
  AND yd.fieldID = (SELECT fieldID FROM fields WHERE fieldName = 'date')
LEFT JOIN itemDataValues yr ON yd.valueID = yr.valueID
LEFT JOIN itemData pd ON i.itemID = pd.itemID
  AND pd.fieldID = (SELECT fieldID FROM fields WHERE fieldName = 'publicationTitle')
LEFT JOIN itemDataValues pub ON pd.valueID = pub.valueID
LEFT JOIN itemData dd ON i.itemID = dd.itemID
  AND dd.fieldID = (SELECT fieldID FROM fields WHERE fieldName = 'DOI')
LEFT JOIN itemDataValues doi ON dd.valueID = doi.valueID
LEFT JOIN itemData vd ON i.itemID = vd.itemID
  AND vd.fieldID = (SELECT fieldID FROM fields WHERE fieldName = 'volume')
LEFT JOIN itemDataValues vol ON vd.valueID = vol.valueID
LEFT JOIN itemData id_ ON i.itemID = id_.itemID
  AND id_.fieldID = (SELECT fieldID FROM fields WHERE fieldName = 'issue')
LEFT JOIN itemDataValues iss ON id_.valueID = iss.valueID
LEFT JOIN itemData pgd ON i.itemID = pgd.itemID
  AND pgd.fieldID = (SELECT fieldID FROM fields WHERE fieldName = 'pages')
LEFT JOIN itemDataValues pg ON pgd.valueID = pg.valueID
WHERE i.itemID NOT IN (SELECT itemID FROM deletedItems)
"""

try:
    rows = list(cur.execute(ITEM_SQL))
except Exception as e:
    conn.close()
    os.unlink(tmp_db)
    print("STATUS=YELLOW")
    print(f"REASON=zotero_query_failed:{e}")
    sys.exit(2)

# Index by (first_surname_norm, year) → list of candidate row dicts
by_sig = {}
by_doi = {}
for r in rows:
    title = (r["title"] or "").strip()
    year = (r["year"] or "").strip()[:4]
    surnames = (r["surnames_pipe"] or "").split("|") if r["surnames_pipe"] else []
    surnames_norm = [normalize(s) for s in surnames if s.strip()]
    first_sur = surnames_norm[0] if surnames_norm else ""
    doi_norm = (r["doi"] or "").strip().lower()
    rec = {
        "title": title,
        "year": year,
        "journal": (r["journal"] or "").strip(),
        "doi": doi_norm,
        "volume": (r["volume"] or "").strip(),
        "issue": (r["issue"] or "").strip(),
        "pages": (r["pages"] or "").strip(),
        "itype": r["itype"],
        "surnames": surnames_norm,
    }
    if doi_norm:
        by_doi[doi_norm] = rec
    if first_sur and year:
        by_sig.setdefault((first_sur, year), []).append(rec)

conn.close()
os.unlink(tmp_db)

if debug:
    print(f"DEBUG zotero_items={len(rows)} by_doi={len(by_doi)} by_sig={len(by_sig)}",
          file=sys.stderr)


# ── Compare each bib entry against Zotero ─────────────────────────────
_PLACEHOLDERS = {"", "n/a", "na", "none", "null", "tbd", "forthcoming", "in press"}


def is_present(v):
    """A field value counts as present only if it's not a placeholder.
    Zotero entries often carry 'n/a' / 'N/A' as a placeholder rather than NULL,
    which would generate false-positive drifts against a populated bib value."""
    if v is None:
        return False
    return v.strip().lower() not in _PLACEHOLDERS


def field_mismatches(bib_entry, zot_entry):
    issues = []
    bk = bib_entry.get("kind", "")
    bib_t = bib_entry.get("title")
    zot_t = zot_entry.get("title")
    if is_present(bib_t) and is_present(zot_t):
        if title_similarity(bib_t, zot_t) < 0.55:
            if zot_t.strip().lower() not in {"untitled", "forthcoming", "no title"} \
               and len(zot_t.strip()) >= 5:
                issues.append(("title", bib_t[:80], zot_t[:80]))

    if bk == "article":
        bib_j = bib_entry.get("journal")
        zot_j = zot_entry.get("journal")
        if is_present(bib_j) and is_present(zot_j) and title_similarity(bib_j, zot_j) < 0.55:
            issues.append(("journal", bib_j[:60], zot_j[:60]))
        bib_v = bib_entry.get("volume")
        zot_v = zot_entry.get("volume")
        if is_present(bib_v) and is_present(zot_v) and normalize(bib_v) != normalize(zot_v):
            issues.append(("volume", bib_v, zot_v))
        bib_i = bib_entry.get("issue")
        zot_i = zot_entry.get("issue")
        if is_present(bib_i) and is_present(zot_i) and normalize(bib_i) != normalize(zot_i):
            issues.append(("issue", bib_i, zot_i))

    bib_p = bib_entry.get("pages")
    zot_p = zot_entry.get("pages")
    if is_present(bib_p) and is_present(zot_p):
        bn = normalize_pages(bib_p)
        zn = normalize_pages(zot_p)
        if bn and zn and bn != zn:
            issues.append(("pages", bib_p, zot_p))

    # Coauthor set — only when bib has ≥2 authors and Zotero has ≥2.
    # ASA/APA "and others" (et-al) shorthand: if the bib author list ends
    # with "others", we trust that bib intentionally truncated the list.
    # Match if the prefix (sans "others") is a prefix of the local list.
    bib_authors = bib_entry.get("surnames") or []
    zot_authors = zot_entry.get("surnames") or []
    bib_has_etal = bool(bib_authors) and bib_authors[-1] == "others"
    bib_eff = bib_authors[:-1] if bib_has_etal else bib_authors
    if len(bib_eff) >= 2 and len(zot_authors) >= 2:
        if bib_has_etal:
            # Prefix match: every author in bib_eff must appear (in order)
            # among the first N entries of zot_authors, where N = len(bib_eff).
            ok = (len(zot_authors) >= len(bib_eff)
                  and zot_authors[:len(bib_eff)] == bib_eff)
            if not ok:
                # Soft check: at least all bib_eff appear somewhere in local.
                if not set(bib_eff).issubset(set(zot_authors)):
                    missing = set(bib_eff) - set(zot_authors)
                    issues.append((
                        "authors_etal",
                        f"bib={bib_authors}",
                        f"local={zot_authors[:10]}{'...' if len(zot_authors) > 10 else ''}"
                        + f" | bib_prefix_not_subset | only_in_bib={sorted(missing)}",
                    ))
        else:
            if set(bib_authors) != set(zot_authors):
                missing = set(bib_authors) - set(zot_authors)
                extra = set(zot_authors) - set(bib_authors)
                issues.append((
                    "authors",
                    f"bib={bib_authors}",
                    f"local={zot_authors}"
                    + (f" | only_in_bib={sorted(missing)}" if missing else "")
                    + (f" | only_in_local={sorted(extra)}" if extra else ""),
                ))

    return issues


matched_count = 0
mismatched = []
not_in_local = []
exempt_count = 0
parse_skip = 0

for kind, key, body in entries:
    if kind.startswith("comment") or kind.startswith("string") or kind.startswith("preamble"):
        continue
    # Exemption: verified_via field explicitly documents a non-local provenance
    if get_field(body, "verified_via"):
        exempt_count += 1
        continue

    title = get_field(body, "title")
    year_v = get_field(body, "year") or ""
    year_v = year_v.strip()[:4]
    m_yr = re.search(r"(\d{4})", year_v)
    year = m_yr.group(1) if m_yr else ""
    if not year:
        parse_skip += 1
        continue

    bib_authors_val = get_field(body, "author") or get_field(body, "editor") or ""
    first_sur = extract_first_surname(bib_authors_val)
    bib_doi = (get_field(body, "doi") or "").strip().lower()
    bib_entry = {
        "kind": kind,
        "key": key,
        "title": title,
        "journal": get_field(body, "journal") or get_field(body, "booktitle"),
        "volume": get_field(body, "volume"),
        "issue": get_field(body, "number") or get_field(body, "issue"),
        "pages": get_field(body, "pages"),
        "doi": bib_doi,
        "surnames": extract_all_surnames(bib_authors_val),
    }

    # Match: prefer DOI exact; else (surname, year) with title fuzz.
    cand = None
    if bib_doi and bib_doi in by_doi:
        cand = by_doi[bib_doi]
    elif first_sur and year:
        cands = by_sig.get((normalize(first_sur), year), [])
        if cands and title:
            # Pick best title-similarity match
            best = max(cands, key=lambda r: title_similarity(title, r["title"]))
            if title_similarity(title, best["title"]) >= 0.4:
                cand = best
        elif cands and len(cands) == 1:
            cand = cands[0]

    if cand is None:
        not_in_local.append((key, kind, first_sur, year, (title or "")[:80]))
        continue

    issues = field_mismatches(bib_entry, cand)
    if issues:
        mismatched.append((key, kind, issues, (title or "")[:80]))
    else:
        matched_count += 1


total = matched_count + len(mismatched) + len(not_in_local) + exempt_count

# ── Verdict ──────────────────────────────────────────────────────────
if total == 0:
    print("STATUS=YELLOW")
    print("REASON=no_parseable_bib_entries")
    print(f"  bib:    {bib_path}")
    print(f"  zotero: {zotero_src}")
    sys.exit(2)

if mismatched:
    print("STATUS=RED")
    print(f"REASON=mismatched_local:{len(mismatched)}/{total}")
    print(f"  bib:    {bib_path}")
    print(f"  zotero: {zotero_src}")
    print(f"  matched_local:    {matched_count}/{total}")
    print(f"  mismatched_local: {len(mismatched)}/{total}")
    print(f"  not_in_local:     {len(not_in_local)}/{total} (YELLOW informational)")
    print(f"  exempt_via_field: {exempt_count}/{total}")
    print("  mismatched entries (bib drift vs local library):")
    for key, kind, issues, title in mismatched[:15]:
        print(f"    - {key} (@{kind}) — {title}")
        for field, bib_v, loc_v in issues:
            print(f"        DRIFT {field}: bib={bib_v!r} | local={loc_v!r}")
    if len(mismatched) > 15:
        print(f"    … ({len(mismatched) - 15} more)")
    print()
    print("  FIX: each mismatched entry — either update the .bib to match")
    print("  the Zotero record (preferred — Zotero is curated), OR if the bib")
    print("  is correct and Zotero has stale metadata, fix the Zotero entry.")
    print("  Use scholar-citation MODE 6b MATERIALIZE to rebuild from canonical.")
    sys.exit(1)
else:
    # GREEN if at least one MATCHED_LOCAL and no MISMATCHED. NOT_IN_LOCAL
    # alone is informational, not blocking — many real citations are
    # legitimately not in the operator's Zotero.
    if matched_count == 0 and not_in_local:
        # Library exists but nothing from bib was found — possibly the wrong
        # Zotero installation, possibly the project uses sources the operator
        # has never curated. YELLOW with a note.
        print("STATUS=YELLOW")
        print(f"REASON=zero_matched_local:{matched_count}/{total}")
        print(f"  bib:    {bib_path}")
        print(f"  zotero: {zotero_src}")
        print(f"  not_in_local: {len(not_in_local)}/{total}")
        print(f"  exempt_via_field: {exempt_count}/{total}")
        print("  No bib entry matched any Zotero record. Either (a) the Zotero")
        print("  install detected doesn't contain this project's sources, or")
        print("  (b) the bib was assembled from CrossRef/web rather than the")
        print("  operator's curated library.")
        sys.exit(2)
    print("STATUS=GREEN")
    print(f"  bib:    {bib_path}")
    print(f"  zotero: {zotero_src}")
    print(f"  matched_local:    {matched_count}/{total}")
    print(f"  not_in_local:     {len(not_in_local)}/{total} (YELLOW informational)")
    print(f"  exempt_via_field: {exempt_count}/{total}")
    if debug and not_in_local:
        print("  (debug) not_in_local sample:", file=sys.stderr)
        for key, kind, sur, yr, title in not_in_local[:5]:
            print(f"    - {key} (@{kind}) — {sur} {yr} — {title}", file=sys.stderr)
    sys.exit(0)
PYEOF
