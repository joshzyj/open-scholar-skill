# Reference Manager Backends — Unified Search Layer

This file provides a unified reference search interface across multiple reference managers.
Load via `cat` in any skill's setup block that needs citation lookup.

All backends produce **pipe-delimited records** with identical columns:
```
AUTHORS|YEAR|TITLE|JOURNAL|DOI|VOLUME|ISSUE|PAGES|TYPE|PDF_PATH|SOURCE
```

`AUTHORS` contains semicolon-separated `"Last, First"` pairs (e.g., `Smith, John; Jones, Mary`).

---

## 1. Reference Source Auto-Detection

Run this block once at skill startup to detect which reference managers are available.

```bash
# ── Reference Source Auto-Detection ──────────────────────────────
REF_SOURCES=""
REF_PRIMARY=""

# ── 1. Zotero ────────────────────────────────────────────────────
# Load from .env if present (SCHOLAR_SKILL_DIR points to the scholar-skill installation)
[ -f "${SCHOLAR_SKILL_DIR:-.}/.env" ] && . "${SCHOLAR_SKILL_DIR:-.}/.env" 2>/dev/null || true
# Also check global Claude .env
[ -f "$HOME/.claude/.env" ] && . "$HOME/.claude/.env" 2>/dev/null || true

ZOTERO_DIR="${SCHOLAR_ZOTERO_DIR:-}"
if [ -z "$ZOTERO_DIR" ]; then
  # Auto-detect: check common locations
  for _zcandidate in \
    "$HOME/Zotero" \
    "$HOME/Documents/Zotero" \
    "$HOME/snap/zotero-snap/common/Zotero" \
    "$HOME/Library/CloudStorage/"*/zotero \
    "$HOME/Library/CloudStorage/"*/Zotero \
    "$HOME/Library/CloudStorage/"*/"My Drive"/zotero \
    "$HOME/Library/CloudStorage/"*/"My Drive"/Zotero \
    "$HOME/Google Drive/zotero"; do
    if [ -f "$_zcandidate/zotero.sqlite" ] 2>/dev/null || [ -f "$_zcandidate/zotero.sqlite.bak" ] 2>/dev/null; then
      ZOTERO_DIR="$_zcandidate"
      break
    fi
  done
fi
ZOTERO_BAK="$ZOTERO_DIR/zotero.sqlite.bak"
ZOTERO_LIVE="$ZOTERO_DIR/zotero.sqlite"
ZOTERO_STORAGE="$ZOTERO_DIR/storage"

if [ -f "$ZOTERO_BAK" ] || [ -f "$ZOTERO_LIVE" ]; then
  # Copy live DB to /tmp to avoid lock; fall back to .bak
  cp "$ZOTERO_LIVE" /tmp/zotero_search.sqlite 2>/dev/null \
    && ZOTERO_DB="/tmp/zotero_search.sqlite" \
    || ZOTERO_DB="$ZOTERO_BAK"
  REF_SOURCES="${REF_SOURCES}zotero "
  [ -z "$REF_PRIMARY" ] && REF_PRIMARY="zotero"
  echo "[refmanager] Zotero detected: $ZOTERO_DB"
fi

# ── 2. Mendeley Desktop ─────────────────────────────────────────
MENDELEY_DIR="$HOME/.local/share/data/Mendeley Ltd./Mendeley Desktop"
[ ! -d "$MENDELEY_DIR" ] && MENDELEY_DIR="$HOME/Library/Application Support/Mendeley Desktop"
MENDELEY_DB=""
if [ -d "$MENDELEY_DIR" ]; then
  MENDELEY_DB=$(find "$MENDELEY_DIR" -maxdepth 1 -name '*@www.mendeley.com.sqlite' 2>/dev/null | head -1)
  if [ -n "$MENDELEY_DB" ]; then
    REF_SOURCES="${REF_SOURCES}mendeley "
    [ -z "$REF_PRIMARY" ] && REF_PRIMARY="mendeley"
    echo "[refmanager] Mendeley detected: $MENDELEY_DB"
  fi
fi

# ── 3. BibTeX (.bib files) ──────────────────────────────────────
BIB_PATH="${SCHOLAR_BIB_PATH:-}"
if [ -z "$BIB_PATH" ]; then
  # Auto-search common locations
  for candidate in \
    "$HOME/references.bib" \
    "$HOME/bibliography.bib" \
    "$HOME/library.bib" \
    "$HOME/Documents/references.bib" \
    "$HOME/Documents/bibliography.bib" \
    "$(pwd)/references.bib" \
    "$(pwd)/bibliography.bib"; do
    if [ -f "$candidate" ]; then
      BIB_PATH="$candidate"
      break
    fi
  done
fi
if [ -n "$BIB_PATH" ] && [ -f "$BIB_PATH" ]; then
  REF_SOURCES="${REF_SOURCES}bibtex "
  [ -z "$REF_PRIMARY" ] && REF_PRIMARY="bibtex"
  echo "[refmanager] BibTeX detected: $BIB_PATH"
fi

# ── 4. EndNote XML ───────────────────────────────────────────────
ENDNOTE_XML="${SCHOLAR_ENDNOTE_XML:-}"
if [ -z "$ENDNOTE_XML" ]; then
  for candidate in \
    "$HOME/Documents/My EndNote Library.xml" \
    "$HOME/Documents/EndNote/My EndNote Library.xml" \
    "$(pwd)/endnote-library.xml"; do
    if [ -f "$candidate" ]; then
      ENDNOTE_XML="$candidate"
      break
    fi
  done
fi
if [ -n "$ENDNOTE_XML" ] && [ -f "$ENDNOTE_XML" ]; then
  REF_SOURCES="${REF_SOURCES}endnote-xml "
  [ -z "$REF_PRIMARY" ] && REF_PRIMARY="endnote-xml"
  echo "[refmanager] EndNote XML detected: $ENDNOTE_XML"
fi

# ── Summary ──────────────────────────────────────────────────────
if [ -z "$REF_SOURCES" ]; then
  echo "[refmanager] WARNING: No local reference library detected."
  echo "  Set SCHOLAR_BIB_PATH or SCHOLAR_ENDNOTE_XML, or ensure Zotero/Mendeley is installed."
  REF_SOURCES="none"
  REF_PRIMARY="none"
else
  echo "[refmanager] Sources: $REF_SOURCES | Primary: $REF_PRIMARY"
fi
```

---

## 2. Zotero Backend

### Keyword search (title + abstract)

```bash
scholar_search_zotero_keyword() {
  local KEYWORD="$1" LIMIT="${2:-100}"
  # Split multi-word query into individual words for AND matching + relevance scoring
  # "activity space segregation" → each word checked independently
  local TITLE_CONDS="" ABS_CONDS="" RELEVANCE_EXPR=""
  local WORD_COUNT=0
  for word in $(echo "$KEYWORD" | tr ' ' '\n'); do
    [ -z "$word" ] && continue
    WORD_COUNT=$((WORD_COUNT + 1))
    TITLE_CONDS="${TITLE_CONDS}${TITLE_CONDS:+ AND }LOWER(title.value) LIKE LOWER('%${word}%')"
    ABS_CONDS="${ABS_CONDS}${ABS_CONDS:+ AND }LOWER(COALESCE(abstract.value,'')) LIKE LOWER('%${word}%')"
    # Relevance score: +3 per word in title, +1 per word in abstract
    RELEVANCE_EXPR="${RELEVANCE_EXPR}${RELEVANCE_EXPR:+ + }(CASE WHEN LOWER(title.value) LIKE LOWER('%${word}%') THEN 3 ELSE 0 END)"
    RELEVANCE_EXPR="${RELEVANCE_EXPR} + (CASE WHEN LOWER(COALESCE(abstract.value,'')) LIKE LOWER('%${word}%') THEN 1 ELSE 0 END)"
  done
  # Bonus: +5 if exact phrase appears in title, +2 if in abstract
  local EXACT_BONUS=""
  if [ "$WORD_COUNT" -gt 1 ]; then
    local KEYWORD_LOWER=$(echo "$KEYWORD" | tr '[:upper:]' '[:lower:]')
    EXACT_BONUS=" + (CASE WHEN LOWER(title.value) LIKE '%${KEYWORD_LOWER}%' THEN 5 ELSE 0 END) + (CASE WHEN LOWER(COALESCE(abstract.value,'')) LIKE '%${KEYWORD_LOWER}%' THEN 2 ELSE 0 END)"
  fi
  sqlite3 "$ZOTERO_DB" "
  SELECT
    COALESCE((
      SELECT GROUP_CONCAT(cr.lastName || ', ' || cr.firstName, '; ')
      FROM itemCreators icr
      JOIN creators cr ON icr.creatorID = cr.creatorID
      WHERE icr.itemID = i.itemID
      ORDER BY icr.orderIndex
    ), '') AS authors,
    SUBSTR(year.value,1,4) AS year,
    title.value AS title,
    COALESCE(pub.value,'') AS journal,
    COALESCE(doi.value,'') AS doi,
    COALESCE(vol.value,'') AS volume,
    COALESCE(issue.value,'') AS issue,
    COALESCE(pages.value,'') AS pages,
    it.typeName AS type,
    COALESCE(REPLACE(att.path,'storage:',''),'') AS pdf_file,
    'zotero' AS source
  FROM items i
  JOIN itemTypes it ON i.itemTypeID = it.itemTypeID
  JOIN itemData td ON i.itemID = td.itemID
    AND td.fieldID = (SELECT fieldID FROM fields WHERE fieldName = 'title')
  JOIN itemDataValues title ON td.valueID = title.valueID
  LEFT JOIN itemData yd ON i.itemID = yd.itemID
    AND yd.fieldID = (SELECT fieldID FROM fields WHERE fieldName = 'date')
  LEFT JOIN itemDataValues year ON yd.valueID = year.valueID
  LEFT JOIN itemData pd ON i.itemID = pd.itemID
    AND pd.fieldID = (SELECT fieldID FROM fields WHERE fieldName = 'publicationTitle')
  LEFT JOIN itemDataValues pub ON pd.valueID = pub.valueID
  LEFT JOIN itemData dd ON i.itemID = dd.itemID
    AND dd.fieldID = (SELECT fieldID FROM fields WHERE fieldName = 'DOI')
  LEFT JOIN itemDataValues doi ON dd.valueID = doi.valueID
  LEFT JOIN itemData vd ON i.itemID = vd.itemID
    AND vd.fieldID = (SELECT fieldID FROM fields WHERE fieldName = 'volume')
  LEFT JOIN itemDataValues vol ON vd.valueID = vol.valueID
  LEFT JOIN itemData id ON i.itemID = id.itemID
    AND id.fieldID = (SELECT fieldID FROM fields WHERE fieldName = 'issue')
  LEFT JOIN itemDataValues issue ON id.valueID = issue.valueID
  LEFT JOIN itemData pgd ON i.itemID = pgd.itemID
    AND pgd.fieldID = (SELECT fieldID FROM fields WHERE fieldName = 'pages')
  LEFT JOIN itemDataValues pages ON pgd.valueID = pages.valueID
  LEFT JOIN itemData absd ON i.itemID = absd.itemID
    AND absd.fieldID = (SELECT fieldID FROM fields WHERE fieldName = 'abstractNote')
  LEFT JOIN itemDataValues abstract ON absd.valueID = abstract.valueID
  LEFT JOIN itemAttachments att ON att.parentItemID = i.itemID
    AND att.contentType = 'application/pdf'
  WHERE it.typeName NOT IN ('attachment', 'note')
    AND (($TITLE_CONDS)
      OR ($ABS_CONDS))
  GROUP BY i.itemID
  ORDER BY ($RELEVANCE_EXPR${EXACT_BONUS}) DESC, SUBSTR(year.value,1,4) DESC
  LIMIT $LIMIT;
  " 2>/dev/null
}
```

### Author search

```bash
scholar_search_zotero_author() {
  local AUTHOR="$1" LIMIT="${2:-100}"
  sqlite3 "$ZOTERO_DB" "
  SELECT
    COALESCE((
      SELECT GROUP_CONCAT(cr.lastName || ', ' || cr.firstName, '; ')
      FROM itemCreators icr
      JOIN creators cr ON icr.creatorID = cr.creatorID
      WHERE icr.itemID = i.itemID
      ORDER BY icr.orderIndex
    ), '') AS authors,
    SUBSTR(year.value,1,4) AS year,
    title.value AS title,
    COALESCE(pub.value,'') AS journal,
    COALESCE(doi.value,'') AS doi,
    COALESCE(vol.value,'') AS volume,
    COALESCE(issue.value,'') AS issue,
    COALESCE(pages.value,'') AS pages,
    it.typeName AS type,
    '' AS pdf_file,
    'zotero' AS source
  FROM items i
  JOIN itemTypes it ON i.itemTypeID = it.itemTypeID
  JOIN itemData td ON i.itemID = td.itemID
    AND td.fieldID = (SELECT fieldID FROM fields WHERE fieldName = 'title')
  JOIN itemDataValues title ON td.valueID = title.valueID
  JOIN itemCreators ic ON i.itemID = ic.itemID
  JOIN creators c ON ic.creatorID = c.creatorID
  LEFT JOIN itemData yd ON i.itemID = yd.itemID
    AND yd.fieldID = (SELECT fieldID FROM fields WHERE fieldName = 'date')
  LEFT JOIN itemDataValues year ON yd.valueID = year.valueID
  LEFT JOIN itemData pd ON i.itemID = pd.itemID
    AND pd.fieldID = (SELECT fieldID FROM fields WHERE fieldName = 'publicationTitle')
  LEFT JOIN itemDataValues pub ON pd.valueID = pub.valueID
  LEFT JOIN itemData dd ON i.itemID = dd.itemID
    AND dd.fieldID = (SELECT fieldID FROM fields WHERE fieldName = 'DOI')
  LEFT JOIN itemDataValues doi ON dd.valueID = doi.valueID
  LEFT JOIN itemData vd ON i.itemID = vd.itemID
    AND vd.fieldID = (SELECT fieldID FROM fields WHERE fieldName = 'volume')
  LEFT JOIN itemDataValues vol ON vd.valueID = vol.valueID
  LEFT JOIN itemData isd ON i.itemID = isd.itemID
    AND isd.fieldID = (SELECT fieldID FROM fields WHERE fieldName = 'issue')
  LEFT JOIN itemDataValues issue ON isd.valueID = issue.valueID
  LEFT JOIN itemData pgd ON i.itemID = pgd.itemID
    AND pgd.fieldID = (SELECT fieldID FROM fields WHERE fieldName = 'pages')
  LEFT JOIN itemDataValues pages ON pgd.valueID = pages.valueID
  WHERE it.typeName NOT IN ('attachment', 'note')
    AND LOWER(c.lastName) LIKE LOWER('%${AUTHOR}%')
  GROUP BY i.itemID
  ORDER BY SUBSTR(year.value,1,4) DESC
  LIMIT $LIMIT;
  " 2>/dev/null
}
```

### Collection search (Zotero only)

```bash
scholar_search_zotero_collection() {
  local COLLECTION="$1" LIMIT="${2:-100}"
  [ -z "$ZOTERO_DB" ] && return
  sqlite3 "$ZOTERO_DB" "
  SELECT
    COALESCE((
      SELECT GROUP_CONCAT(cr.lastName || ', ' || cr.firstName, '; ')
      FROM itemCreators icr
      JOIN creators cr ON icr.creatorID = cr.creatorID
      WHERE icr.itemID = parent.itemID
      ORDER BY icr.orderIndex
    ), '') AS authors,
    SUBSTR(year.value,1,4) AS year,
    title.value AS title,
    COALESCE(pub.value,'') AS journal,
    COALESCE(doi.value,'') AS doi,
    COALESCE(vol.value,'') AS volume,
    COALESCE(issue.value,'') AS issue,
    COALESCE(pages.value,'') AS pages,
    it.typeName AS type,
    '' AS pdf_file,
    'zotero' AS source
  FROM collections col
  JOIN collectionItems ci ON col.collectionID = ci.collectionID
  JOIN items parent ON ci.itemID = parent.itemID
  JOIN itemTypes it ON parent.itemTypeID = it.itemTypeID
  LEFT JOIN itemData title_d ON parent.itemID = title_d.itemID
    AND title_d.fieldID = (SELECT fieldID FROM fields WHERE fieldName='title')
  LEFT JOIN itemDataValues title ON title_d.valueID = title.valueID
  LEFT JOIN itemData year_d ON parent.itemID = year_d.itemID
    AND year_d.fieldID = (SELECT fieldID FROM fields WHERE fieldName='date')
  LEFT JOIN itemDataValues year ON year_d.valueID = year.valueID
  LEFT JOIN itemData pd ON parent.itemID = pd.itemID
    AND pd.fieldID = (SELECT fieldID FROM fields WHERE fieldName='publicationTitle')
  LEFT JOIN itemDataValues pub ON pd.valueID = pub.valueID
  LEFT JOIN itemData dd ON parent.itemID = dd.itemID
    AND dd.fieldID = (SELECT fieldID FROM fields WHERE fieldName='DOI')
  LEFT JOIN itemDataValues doi ON dd.valueID = doi.valueID
  LEFT JOIN itemData vd ON parent.itemID = vd.itemID
    AND vd.fieldID = (SELECT fieldID FROM fields WHERE fieldName='volume')
  LEFT JOIN itemDataValues vol ON vd.valueID = vol.valueID
  LEFT JOIN itemData isd ON parent.itemID = isd.itemID
    AND isd.fieldID = (SELECT fieldID FROM fields WHERE fieldName='issue')
  LEFT JOIN itemDataValues issue ON isd.valueID = issue.valueID
  LEFT JOIN itemData pgd ON parent.itemID = pgd.itemID
    AND pgd.fieldID = (SELECT fieldID FROM fields WHERE fieldName='pages')
  LEFT JOIN itemDataValues pages ON pgd.valueID = pages.valueID
  WHERE it.typeName IN ('journalArticle','book','bookSection','conferencePaper','preprint','thesis')
    AND LOWER(col.collectionName) LIKE LOWER('%${COLLECTION}%')
  GROUP BY parent.itemID
  ORDER BY SUBSTR(year.value,1,4) DESC
  LIMIT $LIMIT;
  " 2>/dev/null
}
```

### Tag search (Zotero only)

```bash
scholar_search_zotero_tag() {
  local TAG="$1" LIMIT="${2:-100}"
  [ -z "$ZOTERO_DB" ] && return
  sqlite3 "$ZOTERO_DB" "
  SELECT
    COALESCE((
      SELECT GROUP_CONCAT(cr.lastName || ', ' || cr.firstName, '; ')
      FROM itemCreators icr
      JOIN creators cr ON icr.creatorID = cr.creatorID
      WHERE icr.itemID = parent.itemID
      ORDER BY icr.orderIndex
    ), '') AS authors,
    SUBSTR(year.value,1,4) AS year,
    title.value AS title,
    COALESCE(pub.value,'') AS journal,
    COALESCE(doi.value,'') AS doi,
    COALESCE(vol.value,'') AS volume,
    COALESCE(issue.value,'') AS issue,
    COALESCE(pages.value,'') AS pages,
    itype.typeName AS type,
    '' AS pdf_file,
    'zotero' AS source
  FROM itemTags it_tag
  JOIN tags t ON it_tag.tagID = t.tagID
  JOIN items parent ON it_tag.itemID = parent.itemID
  JOIN itemTypes itype ON parent.itemTypeID = itype.itemTypeID
  LEFT JOIN itemData title_d ON parent.itemID = title_d.itemID
    AND title_d.fieldID = (SELECT fieldID FROM fields WHERE fieldName='title')
  LEFT JOIN itemDataValues title ON title_d.valueID = title.valueID
  LEFT JOIN itemData year_d ON parent.itemID = year_d.itemID
    AND year_d.fieldID = (SELECT fieldID FROM fields WHERE fieldName='date')
  LEFT JOIN itemDataValues year ON year_d.valueID = year.valueID
  LEFT JOIN itemData pd ON parent.itemID = pd.itemID
    AND pd.fieldID = (SELECT fieldID FROM fields WHERE fieldName='publicationTitle')
  LEFT JOIN itemDataValues pub ON pd.valueID = pub.valueID
  LEFT JOIN itemData dd ON parent.itemID = dd.itemID
    AND dd.fieldID = (SELECT fieldID FROM fields WHERE fieldName='DOI')
  LEFT JOIN itemDataValues doi ON dd.valueID = doi.valueID
  LEFT JOIN itemData vd ON parent.itemID = vd.itemID
    AND vd.fieldID = (SELECT fieldID FROM fields WHERE fieldName='volume')
  LEFT JOIN itemDataValues vol ON vd.valueID = vol.valueID
  LEFT JOIN itemData isd ON parent.itemID = isd.itemID
    AND isd.fieldID = (SELECT fieldID FROM fields WHERE fieldName='issue')
  LEFT JOIN itemDataValues issue ON isd.valueID = issue.valueID
  LEFT JOIN itemData pgd ON parent.itemID = pgd.itemID
    AND pgd.fieldID = (SELECT fieldID FROM fields WHERE fieldName='pages')
  LEFT JOIN itemDataValues pages ON pgd.valueID = pages.valueID
  WHERE itype.typeName IN ('journalArticle','book','bookSection','conferencePaper','preprint','thesis')
    AND LOWER(t.name) LIKE LOWER('%${TAG}%')
  GROUP BY parent.itemID
  ORDER BY SUBSTR(year.value,1,4) DESC
  LIMIT $LIMIT;
  " 2>/dev/null
}
```

### List all collections (Zotero only)

```bash
scholar_list_zotero_collections() {
  [ -z "$ZOTERO_DB" ] && return
  sqlite3 "$ZOTERO_DB" "
  SELECT col.collectionName, COUNT(ci.itemID) AS item_count
  FROM collections col
  LEFT JOIN collectionItems ci ON col.collectionID = ci.collectionID
  GROUP BY col.collectionID
  ORDER BY col.collectionName;
  " 2>/dev/null
}
```

---

## 3. Mendeley Backend

Mendeley Desktop stores references in a SQLite database. Note: Mendeley may encrypt the database in newer versions; if queries fail, the user should export to BibTeX instead.

### Keyword search

```bash
scholar_search_mendeley_keyword() {
  local KEYWORD="$1" LIMIT="${2:-100}"
  sqlite3 "$MENDELEY_DB" "
  SELECT
    COALESCE((
      SELECT GROUP_CONCAT(dc2.lastName || ', ' || dc2.firstNames, '; ')
      FROM DocumentContributors dc2
      WHERE dc2.documentId = d.id AND dc2.contribution = 'DocumentAuthor'
    ), '') AS authors,
    COALESCE(d.year,'') AS year,
    COALESCE(d.title,'') AS title,
    COALESCE(d.publication,'') AS journal,
    COALESCE(d.doi,'') AS doi,
    COALESCE(d.volume,'') AS volume,
    COALESCE(d.issue,'') AS issue,
    COALESCE(d.pages,'') AS pages,
    COALESCE(d.type,'') AS type,
    COALESCE(df.localUrl,'') AS pdf_file,
    'mendeley' AS source
  FROM Documents d
  LEFT JOIN DocumentFiles df ON d.id = df.documentId
  WHERE d.deletionPending = 'false'
    AND (LOWER(d.title) LIKE LOWER('%${KEYWORD}%')
      OR LOWER(COALESCE(d.abstract,'')) LIKE LOWER('%${KEYWORD}%'))
  GROUP BY d.id
  ORDER BY d.year DESC
  LIMIT $LIMIT;
  " 2>/dev/null
}
```

### Author search

```bash
scholar_search_mendeley_author() {
  local AUTHOR="$1" LIMIT="${2:-100}"
  sqlite3 "$MENDELEY_DB" "
  SELECT
    COALESCE((
      SELECT GROUP_CONCAT(dc2.lastName || ', ' || dc2.firstNames, '; ')
      FROM DocumentContributors dc2
      WHERE dc2.documentId = d.id AND dc2.contribution = 'DocumentAuthor'
    ), '') AS authors,
    COALESCE(d.year,'') AS year,
    COALESCE(d.title,'') AS title,
    COALESCE(d.publication,'') AS journal,
    COALESCE(d.doi,'') AS doi,
    COALESCE(d.volume,'') AS volume,
    COALESCE(d.issue,'') AS issue,
    COALESCE(d.pages,'') AS pages,
    COALESCE(d.type,'') AS type,
    COALESCE(df.localUrl,'') AS pdf_file,
    'mendeley' AS source
  FROM Documents d
  JOIN DocumentContributors dc ON d.id = dc.documentId
    AND dc.contribution = 'DocumentAuthor'
  LEFT JOIN DocumentFiles df ON d.id = df.documentId
  WHERE d.deletionPending = 'false'
    AND LOWER(dc.lastName) LIKE LOWER('%${AUTHOR}%')
  GROUP BY d.id
  ORDER BY d.year DESC
  LIMIT $LIMIT;
  " 2>/dev/null
}
```

---

## 4. BibTeX Backend

Parses `.bib` files using Python regex. No dependencies beyond Python 3 standard library.

### Keyword search

```bash
scholar_search_bibtex_keyword() {
  local KEYWORD="$1" LIMIT="${2:-100}"
  python3 << PYEOF
import re, sys

keyword = "${KEYWORD}".lower()
limit = int("${LIMIT}")

with open("${BIB_PATH}", "r", encoding="utf-8", errors="replace") as f:
    content = f.read()

entries = re.findall(r'@(\w+)\{([^,]*),([^@]*)', content, re.DOTALL)
count = 0
for entry_type, cite_key, body in entries:
    if entry_type.lower() in ('comment', 'string', 'preamble'):
        continue
    fields = {}
    for m in re.finditer(r'(\w+)\s*=\s*[\{"]([^}"]*?)[\}"]', body):
        fields[m.group(1).lower()] = m.group(2).strip()

    title = fields.get('title', '')
    abstract = fields.get('abstract', '')
    if keyword not in title.lower() and keyword not in abstract.lower():
        continue

    author_raw = fields.get('author', '')
    authors = [a.strip() for a in re.split(r'\s+and\s+', author_raw)]
    first_author = authors[0] if authors else ''
    if ',' in first_author:
        parts = first_author.split(',', 1)
        last_name = parts[0].strip()
        first_name = parts[1].strip() if len(parts) > 1 else ''
    else:
        name_parts = first_author.split()
        last_name = name_parts[-1] if name_parts else ''
        first_name = ' '.join(name_parts[:-1]) if len(name_parts) > 1 else ''

    year = fields.get('year', '')
    journal = fields.get('journal', fields.get('booktitle', ''))
    doi = fields.get('doi', '')
    volume = fields.get('volume', '')
    issue = fields.get('number', '')
    pages = fields.get('pages', '')

    all_authors = '; '.join(
        f"{a.split(',')[0].strip()}, {a.split(',')[1].strip()}" if ',' in a
        else f"{a.split()[-1]}, {' '.join(a.split()[:-1])}" if a.strip()
        else ''
        for a in authors if a.strip()
    )
    print(f"{all_authors}|{year}|{title}|{journal}|{doi}|{volume}|{issue}|{pages}|{entry_type}||bibtex")
    count += 1
    if count >= limit:
        break
PYEOF
}
```

### Author search

```bash
scholar_search_bibtex_author() {
  local AUTHOR="$1" LIMIT="${2:-100}"
  python3 << PYEOF
import re

author_q = "${AUTHOR}".lower()
limit = int("${LIMIT}")

with open("${BIB_PATH}", "r", encoding="utf-8", errors="replace") as f:
    content = f.read()

entries = re.findall(r'@(\w+)\{([^,]*),([^@]*)', content, re.DOTALL)
count = 0
for entry_type, cite_key, body in entries:
    if entry_type.lower() in ('comment', 'string', 'preamble'):
        continue
    fields = {}
    for m in re.finditer(r'(\w+)\s*=\s*[\{"]([^}"]*?)[\}"]', body):
        fields[m.group(1).lower()] = m.group(2).strip()

    author_raw = fields.get('author', '')
    if author_q not in author_raw.lower():
        continue

    authors = [a.strip() for a in re.split(r'\s+and\s+', author_raw)]

    title = fields.get('title', '')
    year = fields.get('year', '')
    journal = fields.get('journal', fields.get('booktitle', ''))
    doi = fields.get('doi', '')
    volume = fields.get('volume', '')
    issue = fields.get('number', '')
    pages = fields.get('pages', '')

    all_authors = '; '.join(
        f"{a.split(',')[0].strip()}, {a.split(',')[1].strip()}" if ',' in a
        else f"{a.split()[-1]}, {' '.join(a.split()[:-1])}" if a.strip()
        else ''
        for a in authors if a.strip()
    )
    print(f"{all_authors}|{year}|{title}|{journal}|{doi}|{volume}|{issue}|{pages}|{entry_type}||bibtex")
    count += 1
    if count >= limit:
        break
PYEOF
}
```

---

## 5. EndNote XML Backend

Parses EndNote XML export files using Python `xml.etree.ElementTree`. No dependencies.

### Keyword search

```bash
scholar_search_endnote_keyword() {
  local KEYWORD="$1" LIMIT="${2:-100}"
  python3 << PYEOF
import xml.etree.ElementTree as ET

keyword = "${KEYWORD}".lower()
limit = int("${LIMIT}")

tree = ET.parse("${ENDNOTE_XML}")
root = tree.getroot()
count = 0

for rec in root.iter('record'):
    title_el = rec.find('.//title/style')
    title = title_el.text if title_el is not None and title_el.text else ''
    abstract_el = rec.find('.//abstract/style')
    abstract = abstract_el.text if abstract_el is not None and abstract_el.text else ''

    if keyword not in title.lower() and keyword not in abstract.lower():
        continue

    authors = rec.findall('.//contributors/authors/author/style')
    first_author = authors[0].text if authors and authors[0].text else ''
    if ',' in first_author:
        parts = first_author.split(',', 1)
        last_name = parts[0].strip()
        first_name = parts[1].strip() if len(parts) > 1 else ''
    else:
        name_parts = first_author.split()
        last_name = name_parts[-1] if name_parts else ''
        first_name = ' '.join(name_parts[:-1]) if len(name_parts) > 1 else ''

    year_el = rec.find('.//dates/year/style')
    year = year_el.text if year_el is not None and year_el.text else ''
    journal_el = rec.find('.//periodical/full-title/style')
    if journal_el is None:
        journal_el = rec.find('.//secondary-title/style')
    journal = journal_el.text if journal_el is not None and journal_el.text else ''
    doi_el = rec.find('.//electronic-resource-num/style')
    doi = doi_el.text if doi_el is not None and doi_el.text else ''
    vol_el = rec.find('.//volume/style')
    volume = vol_el.text if vol_el is not None and vol_el.text else ''
    issue_el = rec.find('.//number/style')
    issue = issue_el.text if issue_el is not None and issue_el.text else ''
    pages_el = rec.find('.//pages/style')
    pages = pages_el.text if pages_el is not None and pages_el.text else ''
    type_el = rec.find('.//ref-type')
    ref_type = type_el.get('name', '') if type_el is not None else ''

    all_authors = '; '.join(
        f"{name.split(',')[0].strip()}, {name.split(',')[1].strip()}" if ',' in name
        else f"{name.split()[-1]}, {' '.join(name.split()[:-1])}" if name.strip()
        else ''
        for name in author_names if name.strip()
    )
    print(f"{all_authors}|{year}|{title}|{journal}|{doi}|{volume}|{issue}|{pages}|{ref_type}||endnote-xml")
    count += 1
    if count >= limit:
        break
PYEOF
}
```

### Author search

```bash
scholar_search_endnote_author() {
  local AUTHOR="$1" LIMIT="${2:-100}"
  python3 << PYEOF
import xml.etree.ElementTree as ET

author_q = "${AUTHOR}".lower()
limit = int("${LIMIT}")

tree = ET.parse("${ENDNOTE_XML}")
root = tree.getroot()
count = 0

for rec in root.iter('record'):
    authors = rec.findall('.//contributors/authors/author/style')
    author_names = [a.text for a in authors if a.text]
    if not any(author_q in name.lower() for name in author_names):
        continue

    title_el = rec.find('.//title/style')
    title = title_el.text if title_el is not None and title_el.text else ''
    year_el = rec.find('.//dates/year/style')
    year = year_el.text if year_el is not None and year_el.text else ''
    journal_el = rec.find('.//periodical/full-title/style')
    if journal_el is None:
        journal_el = rec.find('.//secondary-title/style')
    journal = journal_el.text if journal_el is not None and journal_el.text else ''
    doi_el = rec.find('.//electronic-resource-num/style')
    doi = doi_el.text if doi_el is not None and doi_el.text else ''
    vol_el = rec.find('.//volume/style')
    volume = vol_el.text if vol_el is not None and vol_el.text else ''
    issue_el = rec.find('.//number/style')
    issue = issue_el.text if issue_el is not None and issue_el.text else ''
    pages_el = rec.find('.//pages/style')
    pages = pages_el.text if pages_el is not None and pages_el.text else ''
    type_el = rec.find('.//ref-type')
    ref_type = type_el.get('name', '') if type_el is not None else ''

    all_authors = '; '.join(
        f"{name.split(',')[0].strip()}, {name.split(',')[1].strip()}" if ',' in name
        else f"{name.split()[-1]}, {' '.join(name.split()[:-1])}" if name.strip()
        else ''
        for name in author_names if name.strip()
    )
    print(f"{all_authors}|{year}|{title}|{journal}|{doi}|{volume}|{issue}|{pages}|{ref_type}||endnote-xml")
    count += 1
    if count >= limit:
        break
PYEOF
}
```

---

## 6. Unified Dispatcher

The `scholar_search` function queries **all detected backends** and merges results.

```bash
# Usage: scholar_search "KEYWORD" [LIMIT] [keyword|author|collection|tag]
scholar_search() {
  local QUERY="$1"
  local LIMIT="${2:-50}"
  local MODE="${3:-keyword}"   # keyword or author

  local RESULTS=""

  # --- Tier 0.5: Knowledge Graph (pre-extracted intellectual content) ---
  local SKILL_DIR="${SCHOLAR_SKILL_DIR:-.}/.claude/skills"
  local KG_REF="$SKILL_DIR/scholar-knowledge/references/knowledge-graph-search.md"
  if [ -f "$KG_REF" ]; then
    # Load KG functions (safe to re-eval)
    eval "$(cat "$KG_REF" | sed -n '/^```bash/,/^```/p' | sed '1d;$d')" 2>/dev/null
    if kg_available 2>/dev/null; then
      local KG_RESULTS=""
      if [ "$MODE" = "author" ]; then
        KG_RESULTS="$(kg_search_papers_author "$QUERY" "$LIMIT" 2>/dev/null)"
      else
        KG_RESULTS="$(kg_search_papers "$QUERY" "$LIMIT" 2>/dev/null)"
      fi
      if [ -n "$KG_RESULTS" ]; then
        RESULTS="${RESULTS}${KG_RESULTS}"$'\n'
      fi
    fi
  fi

  # --- Tier 1: Local reference managers ---
  for src in $(echo $REF_SOURCES); do
    case "$src" in
      zotero)
        if [ "$MODE" = "author" ]; then
          RESULTS="${RESULTS}$(scholar_search_zotero_author "$QUERY" "$LIMIT" 2>/dev/null)"$'\n'
        elif [ "$MODE" = "collection" ]; then
          RESULTS="${RESULTS}$(scholar_search_zotero_collection "$QUERY" "$LIMIT" 2>/dev/null)"$'\n'
        elif [ "$MODE" = "tag" ]; then
          RESULTS="${RESULTS}$(scholar_search_zotero_tag "$QUERY" "$LIMIT" 2>/dev/null)"$'\n'
        else
          RESULTS="${RESULTS}$(scholar_search_zotero_keyword "$QUERY" "$LIMIT" 2>/dev/null)"$'\n'
        fi
        ;;
      mendeley)
        if [ "$MODE" = "author" ]; then
          RESULTS="${RESULTS}$(scholar_search_mendeley_author "$QUERY" "$LIMIT" 2>/dev/null)"$'\n'
        else
          RESULTS="${RESULTS}$(scholar_search_mendeley_keyword "$QUERY" "$LIMIT" 2>/dev/null)"$'\n'
        fi
        ;;
      bibtex)
        if [ "$MODE" = "author" ]; then
          RESULTS="${RESULTS}$(scholar_search_bibtex_author "$QUERY" "$LIMIT" 2>/dev/null)"$'\n'
        else
          RESULTS="${RESULTS}$(scholar_search_bibtex_keyword "$QUERY" "$LIMIT" 2>/dev/null)"$'\n'
        fi
        ;;
      endnote-xml)
        if [ "$MODE" = "author" ]; then
          RESULTS="${RESULTS}$(scholar_search_endnote_author "$QUERY" "$LIMIT" 2>/dev/null)"$'\n'
        else
          RESULTS="${RESULTS}$(scholar_search_endnote_keyword "$QUERY" "$LIMIT" 2>/dev/null)"$'\n'
        fi
        ;;
    esac
  done

  # --- External API tiers (keyword and author modes only) ---
  # Tier 2a: CrossRef
  if [ "$MODE" = "author" ]; then
    RESULTS="${RESULTS}$(scholar_search_crossref_author "$QUERY" "$LIMIT" 2>/dev/null)"$'\n'
  elif [ "$MODE" = "keyword" ]; then
    RESULTS="${RESULTS}$(scholar_search_crossref_keyword "$QUERY" "$LIMIT" 2>/dev/null)"$'\n'
  fi

  # Tier 2b: Semantic Scholar
  if [ "$MODE" = "author" ]; then
    RESULTS="${RESULTS}$(scholar_search_semanticscholar_author "$QUERY" "$LIMIT" 2>/dev/null)"$'\n'
  elif [ "$MODE" = "keyword" ]; then
    RESULTS="${RESULTS}$(scholar_search_semanticscholar_keyword "$QUERY" "$LIMIT" 2>/dev/null)"$'\n'
  fi

  # Tier 2c: OpenAlex
  if [ "$MODE" = "author" ]; then
    RESULTS="${RESULTS}$(scholar_search_openalex_author "$QUERY" "$LIMIT" 2>/dev/null)"$'\n'
  elif [ "$MODE" = "keyword" ]; then
    RESULTS="${RESULTS}$(scholar_search_openalex_keyword "$QUERY" "$LIMIT" 2>/dev/null)"$'\n'
  fi

  # Tier 2d: Google Scholar
  if [ "$MODE" = "keyword" ] || [ "$MODE" = "author" ]; then
    RESULTS="${RESULTS}$(scholar_search_google_scholar "$QUERY" "$LIMIT" 2>/dev/null)"$'\n'
  fi

  # Output all results (each tier already caps at LIMIT; deduplication left to caller)
  echo "$RESULTS" | grep -v '^$'
}
```

---

## 7. Citation Format Helper

Converts pipe-delimited output rows to compact citation display format.

```bash
scholar_format_citations() {
  # Reads pipe-delimited rows from stdin; outputs compact citation lines
  # New format: AUTHORS|YEAR|TITLE|JOURNAL|DOI|VOLUME|ISSUE|PAGES|TYPE|PDF_PATH|SOURCE
  while IFS='|' read -r authors year title journal doi vol issue pages type pdf source; do
    [ -z "$authors" ] && continue
    # Extract first author last name for compact display
    first_author=$(echo "$authors" | cut -d';' -f1 | cut -d',' -f1)
    # Count authors
    num_authors=$(echo "$authors" | tr ';' '\n' | grep -c '.')
    if [ "$num_authors" -gt 2 ]; then
      display="$first_author et al."
    elif [ "$num_authors" -eq 2 ]; then
      second_author=$(echo "$authors" | cut -d';' -f2 | cut -d',' -f1 | tr -d ' ')
      display="$first_author and $second_author"
    else
      display="$first_author"
    fi
    echo "$display ($year). $title. $journal. [source: $source]"
  done
}
```

**Usage:**
```
scholar_search "segregation" 10 keyword | scholar_format_citations
```

---

## 7b. CrossRef API (External — Tier 2a)

CrossRef provides metadata for 150M+ DOI-registered works. No API key needed. Set `SCHOLAR_CROSSREF_EMAIL` for polite pool access (faster rates).

### Keyword search

```bash
scholar_search_crossref_keyword() {
  local KEYWORD="$1" LIMIT="${2:-50}"
  local QUERY=$(echo "$KEYWORD" | sed 's/ /+/g')
  local MAILTO="${SCHOLAR_CROSSREF_EMAIL:-}"
  local MAILTO_PARAM=""
  [ -n "$MAILTO" ] && MAILTO_PARAM="&mailto=$MAILTO"
  curl -sL "https://api.crossref.org/works?query=$QUERY&rows=$LIMIT&select=DOI,title,author,container-title,issued,type${MAILTO_PARAM}" \
    | python3 -c "
import json, sys
data = json.load(sys.stdin)
for item in data.get('message',{}).get('items',[]):
    authors_list = item.get('author',[]) or []
    authors = '; '.join(
        (a.get('family','') + ', ' + a.get('given',''))
        for a in authors_list
    ) if authors_list else ''
    title = item.get('title',[''])[0] if item.get('title') else ''
    journal = item.get('container-title',[''])[0] if item.get('container-title') else ''
    doi = item.get('DOI','')
    parts = item.get('issued',{}).get('date-parts',[['']])
    year = str(parts[0][0]) if parts and parts[0] and parts[0][0] else ''
    work_type = item.get('type','')
    print(f'{authors}|{year}|{title}|{journal}|{doi}||||{work_type}||crossref')
" 2>/dev/null
}
```

### Author search

```bash
scholar_search_crossref_author() {
  local AUTHOR="$1" LIMIT="${2:-50}"
  local QUERY=$(echo "$AUTHOR" | sed 's/ /+/g')
  local MAILTO="${SCHOLAR_CROSSREF_EMAIL:-}"
  local MAILTO_PARAM=""
  [ -n "$MAILTO" ] && MAILTO_PARAM="&mailto=$MAILTO"
  curl -sL "https://api.crossref.org/works?query.author=$QUERY&rows=$LIMIT&select=DOI,title,author,container-title,issued,type&sort=published&order=desc${MAILTO_PARAM}" \
    | python3 -c "
import json, sys
data = json.load(sys.stdin)
for item in data.get('message',{}).get('items',[]):
    authors_list = item.get('author',[]) or []
    authors = '; '.join(
        (a.get('family','') + ', ' + a.get('given',''))
        for a in authors_list
    ) if authors_list else ''
    title = item.get('title',[''])[0] if item.get('title') else ''
    journal = item.get('container-title',[''])[0] if item.get('container-title') else ''
    doi = item.get('DOI','')
    parts = item.get('issued',{}).get('date-parts',[['']])
    year = str(parts[0][0]) if parts and parts[0] and parts[0][0] else ''
    work_type = item.get('type','')
    print(f'{authors}|{year}|{title}|{journal}|{doi}||||{work_type}||crossref')
" 2>/dev/null
}
```

---

## 8. Semantic Scholar API (External — Tier 2b)

Semantic Scholar provides free access to 200M+ papers with citation graphs and full-text search. Rate limit: 100 requests/5 minutes without API key.

### Keyword search

```bash
scholar_search_semanticscholar_keyword() {
  local KEYWORD="$1" LIMIT="${2:-50}"
  local QUERY=$(echo "$KEYWORD" | sed 's/ /+/g')
  curl -s "https://api.semanticscholar.org/graph/v1/paper/search?query=$QUERY&fields=title,year,authors,externalIds,venue,publicationTypes&limit=$LIMIT" \
    | python3 -c "
import json, sys
data = json.load(sys.stdin)
for paper in data.get('data', []):
    authors_list = paper.get('authors', [])
    authors = '; '.join(
        a.get('name','').rsplit(' ',1)[-1] + ', ' + a.get('name','').rsplit(' ',1)[0]
        if ' ' in a.get('name','') else a.get('name','')
        for a in authors_list
    )
    year = str(paper.get('year','') or '')
    title = paper.get('title','')
    venue = paper.get('venue','')
    ext_ids = paper.get('externalIds', {}) or {}
    doi = ext_ids.get('DOI','')
    pub_types = ','.join(paper.get('publicationTypes',[]) or [])
    print(f'{authors}|{year}|{title}|{venue}|{doi}||||{pub_types}||semanticscholar')
" 2>/dev/null
}
```

### Author search

```bash
scholar_search_semanticscholar_author() {
  local AUTHOR="$1" LIMIT="${2:-50}"
  local QUERY=$(echo "$AUTHOR" | sed 's/ /+/g')
  curl -s "https://api.semanticscholar.org/graph/v1/paper/search?query=$QUERY&fields=title,year,authors,externalIds,venue&limit=$LIMIT" \
    | python3 -c "
import json, sys
author_q = '${AUTHOR}'.lower()
data = json.load(sys.stdin)
for paper in data.get('data', []):
    authors_list = paper.get('authors', [])
    if not any(author_q in a.get('name','').lower() for a in authors_list):
        continue
    authors = '; '.join(
        a.get('name','').rsplit(' ',1)[-1] + ', ' + a.get('name','').rsplit(' ',1)[0]
        if ' ' in a.get('name','') else a.get('name','')
        for a in authors_list
    )
    year = str(paper.get('year','') or '')
    title = paper.get('title','')
    venue = paper.get('venue','')
    ext_ids = paper.get('externalIds', {}) or {}
    doi = ext_ids.get('DOI','')
    print(f'{authors}|{year}|{title}|{venue}|{doi}|||||semanticscholar')
" 2>/dev/null
}
```

### DOI verification

```bash
scholar_verify_semanticscholar_doi() {
  local DOI="$1"
  curl -s "https://api.semanticscholar.org/graph/v1/paper/DOI:$DOI?fields=title,year,authors,externalIds,venue,citationCount" \
    | python3 -c "
import json, sys
paper = json.load(sys.stdin)
if 'title' in paper:
    authors_list = paper.get('authors', [])
    authors = '; '.join(
        a.get('name','').rsplit(' ',1)[-1] + ', ' + a.get('name','').rsplit(' ',1)[0]
        if ' ' in a.get('name','') else a.get('name','')
        for a in authors_list
    )
    year = str(paper.get('year','') or '')
    print(f'Title: {paper[\"title\"]}')
    print(f'Authors: {authors}')
    print(f'Year: {year}')
    print(f'Venue: {paper.get(\"venue\",\"\")}')
    print(f'DOI: {(paper.get(\"externalIds\",{}) or {}).get(\"DOI\",\"\")}')
    print(f'Citations: {paper.get(\"citationCount\", 0)}')
else:
    print('NOT FOUND')
" 2>/dev/null
}
```

> **Rate limit:** 100 requests/5 minutes without API key. Set `S2_API_KEY` header for higher limits.

---

## 9. OpenAlex API (External — Tier 2c)

OpenAlex provides free, open access to 250M+ works. No API key needed. Uses `mailto` for polite pool (faster rates).

### Keyword search

```bash
scholar_search_openalex_keyword() {
  local KEYWORD="$1" LIMIT="${2:-50}"
  local QUERY=$(echo "$KEYWORD" | sed 's/ /%20/g')
  local MAILTO="${SCHOLAR_CROSSREF_EMAIL:-}"
  local MAILTO_PARAM=""
  [ -n "$MAILTO" ] && MAILTO_PARAM="&mailto=$MAILTO"
  curl -sL "https://api.openalex.org/works?search=$QUERY&per_page=$LIMIT${MAILTO_PARAM}" \
    | python3 -c "
import json, sys
data = json.load(sys.stdin)
for work in data.get('results', []):
    authorships = work.get('authorships', [])
    authors = '; '.join(
        a.get('author',{}).get('display_name','').rsplit(' ',1)[-1] + ', ' + a.get('author',{}).get('display_name','').rsplit(' ',1)[0]
        if ' ' in a.get('author',{}).get('display_name','') else a.get('author',{}).get('display_name','')
        for a in authorships
    )
    year = str(work.get('publication_year','') or '')
    title = work.get('title','')
    source = work.get('primary_location',{}) or {}
    journal = (source.get('source',{}) or {}).get('display_name','')
    doi = (work.get('doi','') or '').replace('https://doi.org/','')
    vol = str(work.get('biblio',{}).get('volume','') or '')
    issue = str(work.get('biblio',{}).get('issue','') or '')
    pages = work.get('biblio',{}).get('first_page','') or ''
    last_page = work.get('biblio',{}).get('last_page','') or ''
    if pages and last_page:
        pages = f'{pages}-{last_page}'
    work_type = work.get('type','')
    print(f'{authors}|{year}|{title}|{journal}|{doi}|{vol}|{issue}|{pages}|{work_type}||openalex')
" 2>/dev/null
}
```

### Author search

```bash
scholar_search_openalex_author() {
  local AUTHOR="$1" LIMIT="${2:-50}"
  local QUERY=$(echo "$AUTHOR" | sed 's/ /%20/g')
  local MAILTO="${SCHOLAR_CROSSREF_EMAIL:-}"
  local MAILTO_PARAM=""
  [ -n "$MAILTO" ] && MAILTO_PARAM="&mailto=$MAILTO"
  curl -sL "https://api.openalex.org/works?filter=raw_author_name.search:$QUERY&per_page=$LIMIT&sort=publication_year:desc${MAILTO_PARAM}" \
    | python3 -c "
import json, sys
data = json.load(sys.stdin)
for work in data.get('results', []):
    authorships = work.get('authorships', [])
    authors = '; '.join(
        a.get('author',{}).get('display_name','').rsplit(' ',1)[-1] + ', ' + a.get('author',{}).get('display_name','').rsplit(' ',1)[0]
        if ' ' in a.get('author',{}).get('display_name','') else a.get('author',{}).get('display_name','')
        for a in authorships
    )
    year = str(work.get('publication_year','') or '')
    title = work.get('title','')
    source = work.get('primary_location',{}) or {}
    journal = (source.get('source',{}) or {}).get('display_name','')
    doi = (work.get('doi','') or '').replace('https://doi.org/','')
    vol = str(work.get('biblio',{}).get('volume','') or '')
    issue = str(work.get('biblio',{}).get('issue','') or '')
    pages = work.get('biblio',{}).get('first_page','') or ''
    last_page = work.get('biblio',{}).get('last_page','') or ''
    if pages and last_page:
        pages = f'{pages}-{last_page}'
    work_type = work.get('type','')
    print(f'{authors}|{year}|{title}|{journal}|{doi}|{vol}|{issue}|{pages}|{work_type}||openalex')
" 2>/dev/null
}
```

### DOI verification

```bash
scholar_verify_openalex_doi() {
  local DOI="$1"
  local MAILTO="${SCHOLAR_CROSSREF_EMAIL:-}"
  local MAILTO_PARAM=""
  [ -n "$MAILTO" ] && MAILTO_PARAM="?mailto=$MAILTO"
  curl -sL "https://api.openalex.org/works/doi:$DOI${MAILTO_PARAM}" \
    | python3 -c "
import json, sys
work = json.load(sys.stdin)
if 'title' in work:
    authorships = work.get('authorships', [])
    authors = '; '.join(
        a.get('author',{}).get('display_name','')
        for a in authorships
    )
    year = str(work.get('publication_year','') or '')
    source = work.get('primary_location',{}) or {}
    journal = (source.get('source',{}) or {}).get('display_name','')
    doi = (work.get('doi','') or '').replace('https://doi.org/','')
    cited = work.get('cited_by_count', 0)
    print(f'Title: {work[\"title\"]}')
    print(f'Authors: {authors}')
    print(f'Year: {year}')
    print(f'Journal: {journal}')
    print(f'DOI: {doi}')
    print(f'Cited by: {cited}')
    print(f'Open Access: {work.get(\"open_access\",{}).get(\"is_oa\",False)}')
else:
    print('NOT FOUND')
" 2>/dev/null
}
```

> **No API key needed.** Set `SCHOLAR_CROSSREF_EMAIL` for polite pool access (faster rate limits).

---

## 10. Google Scholar (External — Tier 2d)

Google Scholar provides access to scholarly articles, citation counts, and broad academic coverage. No API key needed. Uses HTML scraping via `curl`.

> **Terms of Service Notice:** Google's ToS prohibit automated access to Google Scholar. This scraping function is provided for limited, low-volume academic verification only (e.g., confirming a single reference exists). For bulk discovery, use CrossRef, Semantic Scholar, or OpenAlex APIs instead. Use at your own discretion and risk.

> **Rate limit:** Google Scholar may return CAPTCHA for high-frequency requests. Use sparingly — best for targeted verification searches, not bulk discovery. Insert a 2-second delay between consecutive calls.

### Keyword search

```bash
scholar_search_google_scholar() {
  local KEYWORD="$1" LIMIT="${2:-50}"
  local QUERY=$(echo "$KEYWORD" | sed 's/ /+/g')
  curl -sL -A "open-scholar-skill/5.4.0 (academic citation verification; +https://github.com/joshzyj/open-scholar-skill)" \
    "https://scholar.google.com/scholar?q=$QUERY&hl=en&num=$LIMIT" 2>/dev/null \
    | python3 -c "
import sys, re, html

content = sys.stdin.read()
if 'unusual traffic' in content.lower() or len(content) < 1000:
    print('RATE_LIMITED', file=sys.stderr)
    sys.exit(1)

blocks = re.split(r'<div class=\"gs_ri\">', content)[1:]
count = 0
for block in blocks:
    if count >= int('$LIMIT'):
        break
    t_match = re.search(r'gs_rt[^>]*>(.*?)</h3>', block, re.DOTALL)
    title = re.sub(r'<[^>]+>', '', t_match.group(1)).strip() if t_match else ''
    if not title:
        continue
    a_match = re.search(r'class=\"gs_a\">(.*?)</div>', block, re.DOTALL)
    meta = re.sub(r'<[^>]+>', '', a_match.group(1)).strip() if a_match else ''
    parts = meta.split(' - ')
    authors = parts[0].strip() if len(parts) > 0 else ''
    venue_year = parts[1].strip() if len(parts) > 1 else ''
    # Extract year from venue_year (e.g., 'Social forces, 1988')
    year_match = re.search(r'(\d{4})', venue_year)
    year = year_match.group(1) if year_match else ''
    journal = re.sub(r',?\s*\d{4}$', '', venue_year).strip()
    c_match = re.search(r'Cited by (\d+)', block)
    cited = c_match.group(1) if c_match else '0'
    l_match = re.search(r'href=\"(https?://[^\"]+)\"', block)
    url = l_match.group(1) if l_match else ''
    # Extract DOI from URL if present
    doi_match = re.search(r'10\.\d{4,}/[^\s\"&]+', url)
    doi = doi_match.group(0) if doi_match else ''
    print(f'{html.unescape(authors)}|{year}|{html.unescape(title)}|{html.unescape(journal)}|{doi}|||{cited}|article||google-scholar')
    count += 1
" 2>/dev/null
}
```

### Verification by title + author

```bash
scholar_verify_google_scholar() {
  local TITLE="$1" AUTHOR="${2:-}"
  local QUERY=$(echo "$AUTHOR $TITLE" | sed 's/ /+/g')
  local RESULT=$(scholar_search_google_scholar "$AUTHOR $TITLE" 1 2>/dev/null)
  if [ -n "$RESULT" ]; then
    echo "$RESULT"
  fi
}
```

> **Usage notes:** Google Scholar is best used as a verification fallback (Tier 2d) rather than primary discovery. It excels at: (1) confirming a paper exists with citation count, (2) finding papers not indexed by CrossRef/OpenAlex (books, theses, working papers, non-English publications), (3) checking "cited by" counts. Always prefer structured APIs (CrossRef, OpenAlex) for metadata extraction.

---

## 11. Verification Tier Update

When using the unified dispatcher, verification status labels use the detected source name:

| Old label | New label | When to use |
|-----------|-----------|-------------|
| `VERIFIED-ZOTERO` | `VERIFIED-LOCAL(zotero)` | Found in Zotero SQLite |
| — | `VERIFIED-LOCAL(mendeley)` | Found in Mendeley SQLite |
| — | `VERIFIED-LOCAL(bibtex)` | Found in .bib file |
| — | `VERIFIED-LOCAL(endnote-xml)` | Found in EndNote XML |
| `VERIFIED-CROSSREF` | `VERIFIED-CROSSREF` | Unchanged |
| — | `VERIFIED-S2` | Found in Semantic Scholar API |
| — | `VERIFIED-OPENALEX` | Found in OpenAlex API |
| — | `VERIFIED-GSCHOLAR` | Found in Google Scholar |
| `VERIFIED-WEB` | `VERIFIED-WEB` | Unchanged |

The 6-tier verification hierarchy:
1. **Local reference library** (Zotero/Mendeley/BibTeX/EndNote) — highest trust
2. **CrossRef API** — DOI-based confirmation (Tier 2a)
3. **Semantic Scholar API** — preprints, working papers, citation graphs (Tier 2b)
4. **OpenAlex API** — open metadata, 250M+ works (Tier 2c)
5. **Google Scholar** — broad academic coverage, citation counts, books/theses (Tier 2d)
6. **WebSearch** — last resort (Tier 3)

---

## 11. Configuration

### Environment Variables

| Variable | Purpose | Example |
|----------|---------|---------|
| `SCHOLAR_BIB_PATH` | Path to a `.bib` file | `export SCHOLAR_BIB_PATH="$HOME/refs/library.bib"` |
| `SCHOLAR_ENDNOTE_XML` | Path to an EndNote XML export | `export SCHOLAR_ENDNOTE_XML="$HOME/Documents/library.xml"` |
| `SCHOLAR_CROSSREF_EMAIL` | Email for CrossRef/OpenAlex polite pool | `export SCHOLAR_CROSSREF_EMAIL="user@institution.edu"` |

### Auto-Detection Paths

| Backend | Checked locations |
|---------|------------------|
| **Zotero** | `$SCHOLAR_ZOTERO_DIR` (env var), `~/Zotero`, `~/Documents/Zotero`, `~/Library/CloudStorage/*/zotero` |
| **Mendeley** | `~/.local/share/data/Mendeley Ltd./Mendeley Desktop/*@www.mendeley.com.sqlite`, `~/Library/Application Support/Mendeley Desktop/*@www.mendeley.com.sqlite` |
| **BibTeX** | `~/references.bib`, `~/bibliography.bib`, `~/library.bib`, `~/Documents/references.bib`, `./references.bib`, `./bibliography.bib` |
| **EndNote XML** | `~/Documents/My EndNote Library.xml`, `~/Documents/EndNote/My EndNote Library.xml`, `./endnote-library.xml` |
| **Semantic Scholar** | No local detection — external API only. Rate: 100 req/5 min (anonymous) |
| **OpenAlex** | No local detection — external API only. Uses `mailto` for polite pool |

### PDF Access

| Backend | PDF access |
|---------|-----------|
| **Zotero** | `pdftotext "$ZOTERO_STORAGE/$PDF_KEY/$PDF_FILE" - \| head -300` |
| **Mendeley** | `pdftotext "$localUrl" - \| head -300` (if `localUrl` is set) |
| **BibTeX** | No PDF path available; use `file` field if present in .bib entry |
| **EndNote XML** | No standard PDF path; check `<urls><pdf-urls>` element if present |
