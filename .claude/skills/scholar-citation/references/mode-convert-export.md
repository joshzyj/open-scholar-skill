# MODE 3: CONVERT-STYLE — Reference List Style Conversion

**Input:** Existing reference list in style A + target style B

## Step C-1: Parse Input References

For each entry, extract structured fields:
- Authors (list of full names)
- Year
- Title (article/chapter)
- Container (journal/book)
- Volume, Issue, Pages
- Publisher, Location (for books)
- DOI / URL

## Step C-2: Verify with Zotero or CrossRef

For entries missing fields required by target style (e.g., DOI for Nature, full first names for ASA), look up via:
1. Zotero first (title + author Bash query)
2. CrossRef API fallback

## Step C-2.5: Convert In-Text Markers (if manuscript text provided)

If the user provides full manuscript text (not just reference list), also convert in-text citation markers:

**Numbered -> Author-date:**
1. Build mapping: `[1] -> (Smith 2020)`, `[2] -> (Jones and Lee 2019)`, etc. from parsed reference list
2. Scan manuscript text for `[N]` or superscript patterns
3. Replace each marker with the correct author-date citation
4. Handle multiple citations: `[1,3]` -> `(Jones 2019; Smith 2020)` (re-sort alphabetically)

**Author-date -> Numbered:**
1. Scan manuscript for `(Author Year)` patterns in order of appearance
2. Assign sequential numbers: first occurrence = [1], second = [2], etc.
3. Replace in-text markers: `(Smith 2020)` -> `[1]`
4. Reorder reference list by appearance number

**Between author-date styles (ASA <-> APA <-> Chicago <-> APSA <-> Unified Linguistics):**
- ASA -> APA: Add commas `(Smith 2020)` -> `(Smith, 2020)`, change "and" -> "&"
- APA -> ASA: Remove commas, change "&" -> "and"
- ASA/APA -> Chicago: `(Smith 2020:45)` page format
- Any -> APSA: Same as ASA format
- Any -> Unified Linguistics: Same as APA format

```bash
# Example: Extract numbered citations for building mapping
grep -oE '\[[0-9,– ]+\]' manuscript.md | sort -u
# Example: Extract author-date citations
grep -oE '\([A-Z][a-z]+ (and [A-Z][a-z]+ |et al\. )?(, )?[0-9]{4}[a-b]?\)' manuscript.md | sort -u
```

## Step C-3: Reformat

Apply the target style templates (see Citation Style Reference in SKILL.md). Common conversions:

**ASA → APA:**
- Add commas after author initials
- Change `(2020)` placement (after authors)
- Add "doi:" prefix
- Italicize journal name and volume

**Numbered → ASA author-date:**
- Reorder to alphabetical by first author
- Expand all author names (no "et al." in list)
- Reformat in-text markers from [1] to (Author Year)

**APA → Nature numbered:**
- Reorder to text-appearance order
- Abbreviate journal names (standard NLM abbreviations)
- Remove article title (Nature style omits article title in some formats — check target journal's instructions)
- Use Nature author format: Smith, J. A., Jones, M. B. & Lee, C. D.

## Step C-4: Output

Deliver:
1. Converted reference list in target style
2. Notes on fields that could not be verified (flagged for author confirmation)

---

# MODE 6: EXPORT — Generate BibTeX .bib File

**Input:** Draft manuscript with citations and reference list (or standalone reference list)

**Purpose:** Generate a `.bib` file from the manuscript's reference list for LaTeX workflows. Each reference is converted to a BibTeX entry with appropriate entry type, cite key, and all available metadata.

## Step E-1: Parse Reference List

Extract structured fields from each reference entry (same as Step C-1): authors, year, title, journal/publisher, volume, issue, pages, DOI, URL.

## Step E-2: Determine BibTeX Entry Types

Map reference types to BibTeX entry types:

| Source Type | BibTeX Entry |
|-------------|-------------|
| Journal article | `@article` |
| Book | `@book` |
| Book chapter | `@incollection` |
| Conference paper | `@inproceedings` |
| Working paper / Report | `@techreport` |
| Preprint | `@unpublished` |
| Thesis / Dissertation | `@phdthesis` or `@mastersthesis` |
| Dataset | `@misc` with `howpublished` |
| Government document | `@techreport` with `institution` |
| Software / R package | `@manual` |

## Step E-3: Generate Cite Keys

Format: `AuthorYear` (first author last name + year). Disambiguate with letter suffix:

```
Smith and Jones 2020 → Smith2020
Smith et al. 2020 → Smith2020
Two different Smith 2020 → Smith2020a, Smith2020b
```

## Step E-4: Verify and Enrich Metadata

For each reference, check Zotero/CrossRef/OpenAlex for missing fields:
- DOI (if not in original reference)
- Abstract (from Zotero)
- Keywords (from Zotero tags)
- ISSN (from CrossRef)
- Open access status (from OpenAlex)

## Step E-5: Generate .bib Entries

```bibtex
@article{Smith2020,
  author    = {Smith, John A. and Jones, Mary B.},
  title     = {Title of Article in Sentence Case},
  journal   = {American Sociological Review},
  year      = {2020},
  volume    = {85},
  number    = {3},
  pages     = {412--435},
  doi       = {10.xxxx/xxxx},
}
```

**Field mapping rules:**
- `author`: BibTeX format with `and` between authors (e.g., `Smith, John A. and Jones, Mary B.`)
- `title`: Wrap proper nouns in `{Braces}` to preserve capitalization in BibTeX
- `pages`: Use `--` for en dash (e.g., `412--435`)
- `doi`: Without `doi:` or URL prefix
- `abstract`: Include if available from Zotero
- `keywords`: Include if available from Zotero tags

## Step E-6: Save .bib File

Path: `output/[slug]/citations/scholar-citation-[slug]-[date].bib`

Also save an audit log noting:
- Total entries exported
- Entries enriched with Zotero/CrossRef/OpenAlex metadata
- Missing fields flagged
- Cite key disambiguation applied
