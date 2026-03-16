# Web Scraping and Digital Data Collection Reference

## 1. Ethical and Legal Checklist

Before any scraping project, document each item:

| Item | How to check | Pass condition |
|------|-------------|----------------|
| `robots.txt` | `GET https://site.com/robots.txt` | No `Disallow` for target paths |
| Terms of Service | Site footer → Terms / Legal | No explicit prohibition on automated access |
| Rate limit policy | ToS, API docs, or `Retry-After` headers | Delays conform to stated limits |
| Authentication required | Does the page load without login? | Publicly accessible without credentials |
| CFAA exposure | Is data accessible to anonymous users? | Yes → generally safe (*hiQ v. LinkedIn*, 9th Cir. 2022) |
| GDPR / CCPA | Does site serve EU/CA users? Are scraped fields personal data? | Anonymize PII; document legal basis |
| IRB determination | Does collection involve human subjects data? | Exempt Cat. 4 (public data, no identifiers) or approved protocol |

**Reporting in Methods:** "We collected [N] records from [site] between [dates]. The site's `robots.txt` permits crawling of these pages. Data were publicly accessible without authentication. IRB determined the collection exempt under 45 CFR 46.104(d)(4). Scraping was performed with randomized delays of 1–3 seconds per request."

---

## 2. Polite Scraping Setup

### R — `polite` package (wraps `rvest`)

```r
library(polite)
library(rvest)
library(httr)

# Check what robots.txt allows
robotstxt::robotstxt("https://example.com")$permissions

# Establish polite session
session <- bow(
  url        = "https://example.com",
  user_agent = "Academic research — [Your Name], [Institution] ([email])",
  delay      = 2,   # min seconds between requests (polite respects Crawl-delay)
  times      = 3    # retry on failure
)

# Scrape — respects delay automatically
page <- scrape(session)

# Navigate to sub-page (keeps polite context)
page2 <- nod(session, "https://example.com/page/2") %>% scrape()
```

### Python — `requests` with retry and backoff

```python
import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry
import time, random
from urllib.robotparser import RobotFileParser

# Check robots.txt
def can_fetch(base_url: str, path: str, user_agent: str = "*") -> bool:
    rp = RobotFileParser()
    rp.set_url(f"{base_url}/robots.txt")
    rp.read()
    return rp.can_fetch(user_agent, f"{base_url}{path}")

# Session with automatic retries (backoff on 429 / 503)
retry = Retry(total=5, backoff_factor=1,
              status_forcelist=[429, 500, 502, 503, 504])
adapter = HTTPAdapter(max_retries=retry)
session = requests.Session()
session.mount("https://", adapter)
session.headers.update({
    "User-Agent": "Academic research — [Your Name], [Institution] ([email])"
})

def polite_get(url: str, min_delay=1.0, max_delay=3.0) -> requests.Response:
    time.sleep(random.uniform(min_delay, max_delay))
    resp = session.get(url, timeout=15)
    resp.raise_for_status()
    return resp
```

---

## 3. CSS Selector Quick Reference

| Target | CSS selector | rvest call | BeautifulSoup call |
|--------|-------------|------------|-------------------|
| All `<h2>` in `<article>` | `article h2` | `html_nodes("article h2")` | `soup.select("article h2")` |
| Element with class | `div.article-body` | `html_nodes("div.article-body")` | `soup.select("div.article-body")` |
| Element with ID | `#main-content` | `html_nodes("#main-content")` | `soup.select_one("#main-content")` |
| `href` attribute of `<a>` | `a.result-link` | `html_attr("href")` | `tag["href"]` |
| All `<li>` in a `<ul>` | `ul.item-list li` | `html_nodes("ul.item-list li")` | `soup.select("ul.item-list li")` |
| nth child | `table tr:nth-child(2)` | `html_nodes("table tr:nth-child(2)")` | `soup.select("table tr:nth-child(2)")` |
| Contains text (XPath) | `//p[contains(.,'keyword')]` | `html_nodes(xpath = "//p[contains(.,'keyword')]")` | `soup.find_all(string=re.compile("keyword"))` |

**Finding selectors:** Chrome DevTools → right-click element → Inspect → right-click tag → Copy → Copy selector. Use SelectorGadget Chrome extension for point-and-click selection.

---

## 4. Handling Pagination

### R — `rvest` pagination loop

```r
library(rvest); library(tidyverse)

# Pattern 1: numeric pagination (?page=N)
scrape_page <- function(n, session) {
  nod(session, glue::glue("https://example.com/articles?page={n}")) %>%
    scrape() %>%
    html_nodes("div.article-card") %>%
    map_dfr(~tibble(
      title = html_node(.x, "h2")       %>% html_text(trim = TRUE),
      url   = html_node(.x, "a")        %>% html_attr("href"),
      date  = html_node(.x, "span.date") %>% html_text(trim = TRUE)
    ))
}

results <- map_dfr(1:50, scrape_page, session = session, .progress = TRUE)

# Pattern 2: "Next" button pagination
results <- list()
url <- "https://example.com/articles"
while (!is.null(url)) {
  page  <- nod(session, url) %>% scrape()
  results[[length(results) + 1]] <- page %>% html_nodes("div.card") %>%
    map_dfr(~tibble(title = html_text(html_node(.x, "h2"), trim = TRUE)))
  next_btn <- page %>% html_node("a.next-page")
  url <- if (!is.null(next_btn)) html_attr(next_btn, "href") else NULL
}
results <- bind_rows(results)
```

### Python — cursor / offset pagination

```python
records = []

# Offset pagination
offset = 0
page_size = 100
while True:
    resp = polite_get(f"https://api.example.com/articles?limit={page_size}&offset={offset}")
    data = resp.json()
    if not data.get("results"):
        break
    records.extend(data["results"])
    offset += page_size
    if offset >= data.get("total_count", float("inf")):
        break

# Cursor pagination (common in REST APIs)
cursor = None
while True:
    params = {"limit": 100, **({"cursor": cursor} if cursor else {})}
    data = polite_get("https://api.example.com/posts", params=params).json()
    records.extend(data["items"])
    cursor = data.get("next_cursor")
    if not cursor:
        break
```

---

## 5. API Authentication Patterns

### Bearer token (Twitter, GitHub, many REST APIs)

```r
# Store in .Renviron — NEVER hardcode in scripts
# .Renviron: TWITTER_BEARER=xxxxxxx
Sys.setenv(TWITTER_BEARER = Sys.getenv("TWITTER_BEARER"))  # already set

# Use in headers
httr::GET("https://api.twitter.com/2/tweets/search/all",
          httr::add_headers(Authorization = paste("Bearer", Sys.getenv("TWITTER_BEARER"))),
          query = list(query = "redlining", max_results = 100))
```

```python
import os
headers = {"Authorization": f"Bearer {os.environ['TWITTER_BEARER']}"}
resp = session.get("https://api.twitter.com/2/tweets/search/all",
                   headers=headers, params={"query": "redlining"})
```

### OAuth 2.0 (Reddit, YouTube)

```python
import praw, os

reddit = praw.Reddit(
    client_id     = os.environ["REDDIT_CLIENT_ID"],
    client_secret = os.environ["REDDIT_CLIENT_SECRET"],
    user_agent    = "Academic research — [Name], [Institution]"
)
# Credentials stored in .env:
# REDDIT_CLIENT_ID=xxx
# REDDIT_CLIENT_SECRET=yyy
```

### API key in query string (NewsAPI, FRED, Census)

```r
# .Renviron: CENSUS_API_KEY=xxx
library(tidycensus)
census_api_key(Sys.getenv("CENSUS_API_KEY"), install = TRUE)

library(fredr)
fredr_set_key(Sys.getenv("FRED_API_KEY"))
```

**Credential security rules:**
- Store all keys in `.Renviron` (R) or `.env` (Python); add both to `.gitignore`
- Use `keyring` (R) or `python-dotenv` / `keyring` (Python) for team projects
- Never paste API keys into SKILL prompts or paper appendices

---

## 6. Rate Limiting and Error Recovery

### R — handle 429 (Too Many Requests)

```r
library(httr)

safe_get <- function(url, max_tries = 5) {
  for (i in seq_len(max_tries)) {
    resp <- GET(url, add_headers("User-Agent" = "Academic research"))
    if (status_code(resp) == 429) {
      wait <- as.integer(headers(resp)$`retry-after`) %||% (2^i * 5)
      message("Rate limited; waiting ", wait, "s")
      Sys.sleep(wait)
    } else if (status_code(resp) == 200) {
      return(content(resp, as = "parsed"))
    } else {
      warning("HTTP ", status_code(resp), " for ", url)
      return(NULL)
    }
  }
  stop("Max retries exceeded for: ", url)
}
```

### Python — exponential backoff

```python
import time

def fetch_with_backoff(url: str, max_retries: int = 5, **kwargs) -> dict | None:
    for attempt in range(max_retries):
        try:
            resp = session.get(url, timeout=15, **kwargs)
            if resp.status_code == 429:
                wait = int(resp.headers.get("Retry-After", 2 ** attempt * 5))
                print(f"Rate limited; waiting {wait}s")
                time.sleep(wait)
                continue
            resp.raise_for_status()
            return resp.json()
        except requests.RequestException as e:
            wait = 2 ** attempt * 2
            print(f"Attempt {attempt+1} failed: {e}; retrying in {wait}s")
            time.sleep(wait)
    print(f"All retries failed for {url}")
    return None
```

---

## 7. HTML Caching (avoid re-requesting)

```r
library(digest)

cache_dir <- "data/raw/html_cache"
dir.create(cache_dir, showWarnings = FALSE)

cached_get <- function(url, session) {
  hash     <- digest::digest(url)
  cache_file <- file.path(cache_dir, paste0(hash, ".html"))
  if (file.exists(cache_file)) {
    return(xml2::read_html(cache_file))
  }
  page <- nod(session, url) %>% scrape()
  xml2::write_html(page, cache_file)
  page
}
```

```python
import hashlib, os
from pathlib import Path

CACHE_DIR = Path("data/raw/html_cache")
CACHE_DIR.mkdir(parents=True, exist_ok=True)

def cached_get(url: str) -> BeautifulSoup:
    key  = hashlib.md5(url.encode()).hexdigest()
    path = CACHE_DIR / f"{key}.html"
    if path.exists():
        return BeautifulSoup(path.read_text(encoding="utf-8"), "html.parser")
    resp = polite_get(url)
    path.write_text(resp.text, encoding="utf-8")
    return BeautifulSoup(resp.text, "html.parser")
```

---

## 8. Structured Storage for Large Collections

### DuckDB (recommended for > 100K records)

```python
import duckdb, pandas as pd

con = duckdb.connect("data/raw/corpus.duckdb")

# Create table
con.execute("""
    CREATE TABLE IF NOT EXISTS documents (
        id          VARCHAR PRIMARY KEY,
        url         VARCHAR,
        title       VARCHAR,
        date        DATE,
        body        TEXT,
        author      VARCHAR,
        scraped_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        source      VARCHAR,
        lang        VARCHAR DEFAULT 'en'
    )
""")

# Bulk insert from DataFrame
con.register("df_view", df)
con.execute("INSERT OR IGNORE INTO documents SELECT * FROM df_view")
con.unregister("df_view")

# Query example: count by month
con.execute("""
    SELECT DATE_TRUNC('month', date) AS month, COUNT(*) AS n
    FROM documents GROUP BY 1 ORDER BY 1
""").df()

con.close()
```

### SQLite (smaller collections, R-native)

```r
library(DBI); library(RSQLite)

con <- dbConnect(RSQLite::SQLite(), "data/raw/corpus.sqlite")
dbWriteTable(con, "documents", df, append = TRUE, overwrite = FALSE)

# Query
dbGetQuery(con, "SELECT COUNT(*) FROM documents WHERE date >= '2022-01-01'")
dbDisconnect(con)
```

### Parquet (columnar; best for text + metadata)

```python
# Write partitioned by year
df["year"] = pd.to_datetime(df["date"]).dt.year
df.to_parquet("data/raw/news-corpus/", partition_cols=["year"], index=False)

# Read with predicate pushdown (fast subsetting)
import pyarrow.dataset as ds
dataset = ds.dataset("data/raw/news-corpus/", format="parquet")
df_22 = dataset.to_table(filter=ds.field("year") == 2022).to_pandas()
```

---

## 9. IRB Considerations for Web Data

### Decision table

| Data type | Publicly accessible | Sensitive topic | Identifiable | Likely IRB level |
|-----------|--------------------|-----------------|-----------|--------------------|
| News articles | Yes | No | No | Exempt Cat. 4 |
| Public tweets (no DMs) | Yes | No | Pseudonym | Exempt Cat. 4 |
| Public tweets on health / politics | Yes | Yes | Pseudonym | Expedited or Exempt with documentation |
| Reddit posts (public subreddits) | Yes | No | Username | Exempt Cat. 4 |
| Forum posts (mental health, sexuality) | Yes | Yes | Username | Expedited review; consider aggregation only |
| Private Facebook groups | No | Yes | Yes | Full board review |
| Scraped profiles (names + addresses) | Varies | Yes | Yes | Full board review + DUA |

**Key principle (AoIR 2019 ethics guidelines):** Legal accessibility ≠ ethical appropriateness. Apply higher scrutiny when content involves vulnerable populations, sensitive disclosures, or reasonable expectation of limited audience even on nominally public platforms.

### Reporting checklist for Methods section

- [ ] State that data were publicly accessible without authentication
- [ ] Note IRB determination and category
- [ ] State whether usernames / identifiers were retained or anonymized
- [ ] Describe scraping period and any rate limiting
- [ ] Note how data are stored and who has access
- [ ] For Twitter/Reddit: state that platform ToS permits academic research use

---

## 10. Downstream Text Analysis Pipeline

After collecting and cleaning web/social media data, hand off to `/scholar-compute` MODULE 1:

```
Raw HTML → Parse → Clean text → De-duplicate → scholar-compute MODULE 1
                                                  ├── STM topic modeling
                                                  ├── BERT/RoBERTa classification
                                                  ├── conText embedding regression
                                                  └── LLM annotation (Claude API)
```

**Cleaning checklist before NLP:**
- Remove HTML tags (`rvest::html_text()` / `BeautifulSoup.get_text()`)
- Remove boilerplate (nav menus, footers) — use `trafilatura` Python package for article extraction
- Detect and filter near-duplicates: `text_reuse` (R) or `datasketch` MinHash (Python)
- Language detection: `cld3` (R) / `langdetect` (Python)
- Normalize encoding: UTF-8 throughout
- Remove personally identifiable information before sharing or publishing

```python
# Article extraction from raw HTML (removes boilerplate)
import trafilatura

def extract_text(html: str) -> str | None:
    return trafilatura.extract(html, include_comments=False,
                               include_tables=False, no_fallback=False)

df["text_clean"] = df["html_raw"].apply(extract_text)
df = df.dropna(subset=["text_clean"])
df = df[df["text_clean"].str.len() > 100]  # remove very short extractions
```
