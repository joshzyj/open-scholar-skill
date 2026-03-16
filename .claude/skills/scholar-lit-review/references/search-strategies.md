# Literature Search Strategies for Social Sciences

## Systematic Search Protocol (PRISMA-Style)

Follow this flow for all literature reviews. Track counts at each stage.

```
IDENTIFICATION
  Zotero library search        → N₁ records
  WebSearch waves               → N₂ records
  Annual Reviews / Handbooks    → N₃ records
  Citation chain expansion      → N₄ records
  Total identified              → N₁ + N₂ + N₃ + N₄

SCREENING
  Remove duplicates             → N₅ removed
  Screen titles/abstracts       → N₆ excluded (with reasons)
  Records after screening       → N₇

ELIGIBILITY
  Full-text review (pdftotext)  → N₈ excluded (with reasons)
  Records after eligibility     → N₉

INCLUDED
  Papers in final inventory     → N₁₀
  Of which: foundational        → count
  Of which: recent (≤5 years)   → count
  Of which: review articles     → count
```

Record these counts in the search log file. For published systematic reviews, convert this to a PRISMA flow diagram.

---

## Discipline-Specific Search Tips

### Sociology

**Core sociology journals to search**:
- American Sociological Review (ASR)
- American Journal of Sociology (AJS)
- Social Forces
- Sociological Theory
- Sociological Methods & Research
- Annual Review of Sociology (for comprehensive reviews)
- Theory and Society
- Sociological Inquiry
- Sociology of Education, Work and Occupations, etc. (specialty journals)

**Search strategy for sociological topics**:
1. Start with Annual Review of Sociology articles — they map entire subfields
2. Use Google Scholar "Cited by" to find forward citations from seminal papers
3. Search ASA journal cluster at asanet.org
4. Use JSTOR for pre-2000 classics
5. Check "Related articles" on Google Scholar

**Key theoretical lineages to trace** (by subfield):

*Stratification*: Blau & Duncan (1967) → Sewell et al. (1969) → Jencks et al. (1972) → DiPrete & Eirich (2006)
*Networks*: Granovetter (1973) → Burt (1992) → Lin (2001) → Centola (2010)
*Culture*: Bourdieu (1984) → Lamont (1992) → DiMaggio (1982) → Vaisey (2009)
*Immigration*: Gordon (1964) → Alba & Nee (2003) → Massey et al. (1987) → Waters (1990)
*Race/ethnicity*: Du Bois (1899) → Wilson (1978) → Bonilla-Silva (1997) → Ray (2019)
*Organizations*: Weber (1922) → DiMaggio & Powell (1983) → Dobbin (2009) → Tomaskovic-Devey & Avent-Holt (2019)

### Demography

**Core demography journals**:
- Demography (PAA flagship)
- Population and Development Review
- Demographic Research (open access)
- Population Studies
- Journal of Marriage and Family
- Journal of Population Economics

**Demographic databases**:
- HMD (Human Mortality Database): mortality data
- HFD (Human Fertility Database): fertility data
- IPUMS: harmonized census microdata
- DHS (Demographic Health Surveys): developing world

**Search tips**:
- Use POPLINE database for population studies
- Check PAA annual meeting abstracts for working papers
- Search by demographic process: fertility, mortality, migration, marriage, household

### Linguistics and Language Studies

**Core linguistics journals** (relevant to sociolinguistics):
- Language in Society
- Journal of Sociolinguistics
- Language
- Journal of Language and Social Psychology
- Annual Review of Linguistics
- Applied Linguistics
- Language Learning

**Key search terms for linguistic studies**:
- Language ideologies + [group/context]
- Code-switching + [population]
- Linguistic assimilation / language shift
- Heritage language maintenance
- Language socialization
- Sociolinguistic variation

**Computational linguistics** (relevant to NCS/Science Advances):
- Proceedings of ACL, EMNLP, NAACL (NLP papers)
- Computational Communication Research
- PNAS for language evolution studies

### Computational Social Science

**Core journals**:
- Nature Human Behaviour
- Nature Computational Science
- PNAS (Proceedings of the National Academy of Sciences)
- Science Advances
- Journal of Computational Social Science
- Social Networks (for network analysis)
- EPJ Data Science

**Search tips**:
- Search arXiv (cs.SI, cs.CL, stat.AP sections) for preprints
- Check papers citing foundational CSS papers: Lazer et al. (2009) Science; Watts (2007) Nature
- ICWSM proceedings for social media research
- IC2S2 conference proceedings

### Political Science

**Core journals**:
- American Political Science Review (APSR)
- American Journal of Political Science (AJPS)
- Journal of Politics
- Annual Review of Political Science
- Political Analysis (methods)
- Comparative Political Studies

**Search tips**:
- SSRN for working papers
- NBER working paper series (overlaps with economics)
- Search by subfield: American politics, comparative, IR, political economy, political behavior

---

## Boolean Search Strategies

**Basic structure**:
```
[Main concept] AND [theoretical lens OR mechanism] AND [population OR context]
```

**Example constructions**:
```
"social capital" AND "labor market" AND (immigrants OR minorities)
"income inequality" AND (education OR "skill premium") AND "United States"
("linguistic assimilation" OR "language shift") AND immigrants AND "second generation"
"computational" AND ("social mobility" OR stratification) AND ("machine learning" OR "natural language processing")
```

**Expand with synonyms**:
- inequality = stratification = disparity = gap = difference
- social capital = social networks = ties = connections
- assimilation = integration = acculturation = incorporation
- segregation = isolation = hypersegregation = dissimilarity
- mechanism = pathway = channel = mediator = process

**Temporal filtering**:
- Recent frontier: add `2022 OR 2023 OR 2024 OR 2025 OR 2026`
- Classic works: search in JSTOR, filter pre-2000
- Use `after:YYYY` syntax in Google Scholar searches

---

## Citation Mapping

### Forward citation search (who cited X):
1. Find the key paper on Google Scholar
2. Click "Cited by N"
3. Filter by year, sort by relevance
4. Look for high-citation papers in the list

### Backward citation search (who X cited):
1. Read reference list of key paper
2. Identify foundational works
3. Find those papers and repeat

### Co-citation analysis:
- Papers that frequently cite the same sources share intellectual lineage
- Use VOSviewer or CiteSpace for bibliometric mapping
- Identify dense citation clusters = theoretical schools

### Semantic Scholar API (citation graph traversal)

For programmatic citation expansion, use the Semantic Scholar API:

```bash
# Get paper details + citations by DOI
PAPER_DOI="10.1177/00031224211024294"
curl -s "https://api.semanticscholar.org/graph/v1/paper/DOI:$PAPER_DOI?fields=title,year,authors,citationCount,citations.title,citations.year,citations.authors,references.title,references.year" | python3 -m json.tool | head -100

# Search by keyword
QUERY="residential+segregation+health"
curl -s "https://api.semanticscholar.org/graph/v1/paper/search?query=$QUERY&fields=title,year,authors,citationCount&limit=20&fieldsOfStudy=Sociology" | python3 -m json.tool
```

Note: Semantic Scholar API is rate-limited (100 requests/5 minutes without API key). Use sparingly for targeted expansion, not bulk search.

### CrossRef API (DOI metadata and cited-by counts)

```bash
# Search CrossRef for papers by keyword
QUERY="residential+segregation+health+disparities"
curl -s "https://api.crossref.org/works?query=$QUERY&rows=10&filter=type:journal-article&sort=relevance" | python3 -m json.tool | head -100

# Get metadata for a specific DOI
DOI="10.1177/00031224211024294"
curl -s "https://api.crossref.org/works/$DOI" | python3 -m json.tool
```

CrossRef is useful for: confirming publication details, getting DOIs for Zotero import, checking citation counts.

---

## Managing Literature

### Reference management tools:
- **Zotero** (free, open source) — recommended for ASA citation style
- **Mendeley** (free) — good for PDFs
- **EndNote** (paid) — institutional standard

### Organization strategies:
- Create folders by: theoretical tradition, empirical finding, method, population
- Tag papers: "foundational," "recent," "methodological," "review"
- Write 2–3 sentence summaries for each paper as you read

### Paper inventory table template

Use this table structure throughout the review to track all papers found:

| # | Author(s) | Year | Title | Journal | Method | Population / Data | Key finding | Source (Zotero/Web/AnnRev/Citation chain) | Relevance (H/M/L) | Gap addressed |
|---|-----------|------|-------|---------|--------|-------------------|-------------|-------------------------------------------|-------------------|--------------|

Fill this table incrementally after each search wave. At the end, it becomes part of the search log output file.

### Literature matrix (for deeper analysis):

Build a spreadsheet with columns:
| Author | Year | Journal | Theory | Outcome | Data | Method | Finding | Limitation | Mechanism tested | Notes |
