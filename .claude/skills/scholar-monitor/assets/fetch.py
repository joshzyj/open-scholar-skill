#!/usr/bin/env python3
"""Literature feed fetcher for scholar-monitor.

Reads a single source spec (JSON on --source-json or --source-file) and a
since-date cutoff; emits normalized paper records as JSONL on stdout.

Backends: crossref | arxiv | openalex | rss
Stdlib only — no pip deps.

Normalized record schema (one JSON object per stdout line):
  source_id, category, doi, arxiv_id, title, authors (list[str]),
  year, published_date (YYYY-MM-DD), journal, abstract, url
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import time
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from datetime import date, datetime, timedelta
from html import unescape
from typing import Any, Iterator

USER_AGENT = "scholar-monitor/1.0 (open-scholar-skills)"
TIMEOUT = 30
ARXIV_VERSION_RE = re.compile(r"v\d+$")


def _arxiv_base_id(arxiv_id: str) -> str:
    """Strip trailing v1/v2/... version suffix — dedup key must be version-agnostic."""
    return ARXIV_VERSION_RE.sub("", arxiv_id) if arxiv_id else ""


# ─────────────────────── utilities ───────────────────────

def _log(msg: str) -> None:
    print(f"[fetch] {msg}", file=sys.stderr)


def _http_get(url: str, *, accept: str = "application/json") -> bytes:
    req = urllib.request.Request(
        url,
        headers={"User-Agent": USER_AGENT, "Accept": accept},
    )
    with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
        return resp.read()


def _clean_html(text: str | None) -> str:
    if not text:
        return ""
    text = unescape(text)
    for tag in ("<jats:p>", "</jats:p>", "<p>", "</p>", "<i>", "</i>",
                "<b>", "</b>", "<em>", "</em>"):
        text = text.replace(tag, "")
    return " ".join(text.split())


def _parse_date(s: str | None) -> str:
    """Return YYYY-MM-DD from a variety of input formats. Empty string if unparseable."""
    if not s:
        return ""
    s = s.strip()
    for fmt in ("%Y-%m-%d", "%Y-%m-%dT%H:%M:%SZ", "%Y-%m-%dT%H:%M:%S",
                "%Y/%m/%d", "%a, %d %b %Y %H:%M:%S %Z",
                "%a, %d %b %Y %H:%M:%S %z"):
        try:
            return datetime.strptime(s, fmt).strftime("%Y-%m-%d")
        except ValueError:
            continue
    if len(s) >= 10 and s[4] == "-" and s[7] == "-":
        return s[:10]
    return ""


def _crossref_date_parts(dp: Any) -> str:
    """Crossref `date-parts` is [[YYYY, M, D]] or [[YYYY, M]] or [[YYYY]]."""
    try:
        parts = dp["date-parts"][0]
        y = parts[0]
        m = parts[1] if len(parts) > 1 else 1
        d = parts[2] if len(parts) > 2 else 1
        return f"{y:04d}-{m:02d}-{d:02d}"
    except (KeyError, IndexError, TypeError):
        return ""


# ─────────────────────── Crossref ───────────────────────

def fetch_crossref(source: dict, since: str, max_n: int,
                   email: str = "") -> Iterator[dict]:
    issn = source.get("issn", "").strip()
    query_cont = source.get("query", "").strip()
    if not issn and not query_cont:
        raise ValueError("crossref source needs either 'issn' or 'query'")

    filters = [f"from-pub-date:{since}"]
    if issn:
        filters.append(f"issn:{issn}")
    params = {
        "filter": ",".join(filters),
        "rows": str(max_n),
        "sort": "published",
        "order": "desc",
    }
    if query_cont:
        params["query.container-title"] = query_cont
    if email:
        params["mailto"] = email

    url = "https://api.crossref.org/works?" + urllib.parse.urlencode(params)
    _log(f"crossref: {url}")
    raw = _http_get(url)
    data = json.loads(raw)
    items = data.get("message", {}).get("items", [])

    for item in items:
        doi = item.get("DOI", "").lower()
        title = " ".join(item.get("title", [""]))
        authors = [
            f"{a.get('family', '')}, {a.get('given', '')}".strip(", ")
            for a in item.get("author", [])
            if a.get("family") or a.get("given")
        ]
        issued = _crossref_date_parts(
            item.get("issued") or item.get("published-online")
            or item.get("published-print") or {"date-parts": [[]]}
        )
        year = int(issued[:4]) if issued else 0
        journal = " ".join(item.get("container-title", [""]))
        abstract = _clean_html(item.get("abstract"))
        url_out = item.get("URL", f"https://doi.org/{doi}" if doi else "")

        yield {
            "source_id": source.get("id", ""),
            "category": source.get("category", ""),
            "doi": doi,
            "arxiv_id": "",
            "title": title.strip(),
            "authors": authors,
            "year": year,
            "published_date": issued,
            "journal": journal.strip(),
            "abstract": abstract,
            "url": url_out,
        }


# ─────────────────────── arXiv ───────────────────────

_ARXIV_NS = {"atom": "http://www.w3.org/2005/Atom",
             "arxiv": "http://arxiv.org/schemas/atom"}


def fetch_arxiv(source: dict, since: str, max_n: int) -> Iterator[dict]:
    query = source.get("query", "").strip()
    if not query:
        raise ValueError("arxiv source needs 'query'")

    params = {
        "search_query": query,
        "sortBy": "submittedDate",
        "sortOrder": "descending",
        "max_results": str(max_n),
        "start": "0",
    }
    url = "http://export.arxiv.org/api/query?" + urllib.parse.urlencode(params)
    _log(f"arxiv: {url}")
    raw = _http_get(url, accept="application/atom+xml")
    root = ET.fromstring(raw)

    since_dt = None
    try:
        since_dt = datetime.strptime(since, "%Y-%m-%d").date()
    except ValueError:
        pass

    for entry in root.findall("atom:entry", _ARXIV_NS):
        arxiv_url = entry.findtext("atom:id", "", _ARXIV_NS)
        full_id = arxiv_url.rsplit("/abs/", 1)[-1] if "/abs/" in arxiv_url else ""
        arxiv_id = _arxiv_base_id(full_id)  # strip v1/v2 — dedup must be version-agnostic
        title = (entry.findtext("atom:title", "", _ARXIV_NS) or "").strip()
        title = " ".join(title.split())
        abstract = (entry.findtext("atom:summary", "", _ARXIV_NS) or "").strip()
        abstract = " ".join(abstract.split())
        published_raw = entry.findtext("atom:published", "", _ARXIV_NS)
        published = _parse_date(published_raw)
        if since_dt and published:
            try:
                pub_dt = datetime.strptime(published, "%Y-%m-%d").date()
                if pub_dt < since_dt:
                    continue
            except ValueError:
                pass
        year = int(published[:4]) if published else 0
        authors = [
            (a.findtext("atom:name", "", _ARXIV_NS) or "").strip()
            for a in entry.findall("atom:author", _ARXIV_NS)
        ]
        doi = entry.findtext("arxiv:doi", "", _ARXIV_NS) or ""

        yield {
            "source_id": source.get("id", ""),
            "category": source.get("category", ""),
            "doi": doi.lower(),
            "arxiv_id": arxiv_id,
            "title": title,
            "authors": [a for a in authors if a],
            "year": year,
            "published_date": published,
            "journal": "arXiv",
            "abstract": abstract,
            "url": arxiv_url,
        }


# ─────────────────────── OpenAlex ───────────────────────

def fetch_openalex(source: dict, since: str, max_n: int,
                   email: str = "") -> Iterator[dict]:
    issn = source.get("issn", "").strip()
    if not issn:
        raise ValueError("openalex source needs 'issn'")
    filters = [
        f"primary_location.source.issn:{issn}",
        f"from_publication_date:{since}",
    ]
    params = {
        "filter": ",".join(filters),
        "per-page": str(min(max_n, 200)),
        "sort": "publication_date:desc",
    }
    if email:
        params["mailto"] = email
    url = "https://api.openalex.org/works?" + urllib.parse.urlencode(params)
    _log(f"openalex: {url}")
    raw = _http_get(url)
    data = json.loads(raw)
    for w in data.get("results", []):
        doi = (w.get("doi") or "").replace("https://doi.org/", "").lower()
        title = w.get("title") or w.get("display_name") or ""
        pub_date = w.get("publication_date", "")
        year = w.get("publication_year") or (int(pub_date[:4]) if pub_date else 0)
        authors = [
            (a.get("author", {}).get("display_name") or "")
            for a in w.get("authorships", [])
        ]
        journal = ""
        loc = w.get("primary_location") or {}
        src_info = loc.get("source") or {}
        journal = src_info.get("display_name", "") or ""
        inv = w.get("abstract_inverted_index") or {}
        abstract = _reconstruct_inverted_index(inv) if inv else ""

        yield {
            "source_id": source.get("id", ""),
            "category": source.get("category", ""),
            "doi": doi,
            "arxiv_id": "",
            "title": title.strip(),
            "authors": [a for a in authors if a],
            "year": year,
            "published_date": pub_date,
            "journal": journal,
            "abstract": abstract,
            "url": f"https://doi.org/{doi}" if doi else w.get("id", ""),
        }


def _reconstruct_inverted_index(inv: dict) -> str:
    pos: list[tuple[int, str]] = []
    for word, positions in inv.items():
        for p in positions:
            pos.append((p, word))
    pos.sort()
    return " ".join(w for _, w in pos)


# ─────────────────────── RSS (generic Atom/RSS) ───────────────────────

def fetch_rss(source: dict, since: str, max_n: int) -> Iterator[dict]:
    url = source.get("url", "").strip()
    if not url:
        raise ValueError("rss source needs 'url'")
    _log(f"rss: {url}")
    raw = _http_get(url, accept="application/atom+xml, application/rss+xml, application/xml")
    root = ET.fromstring(raw)

    # Normalize: strip all namespaces for simpler XPath
    for el in root.iter():
        if "}" in el.tag:
            el.tag = el.tag.split("}", 1)[1]

    items = root.findall(".//item") or root.findall(".//entry")
    emitted = 0
    since_dt = None
    try:
        since_dt = datetime.strptime(since, "%Y-%m-%d").date()
    except ValueError:
        pass

    for it in items:
        if emitted >= max_n:
            break
        title = (it.findtext("title") or "").strip()
        link_el = it.find("link")
        link = (link_el.get("href") if link_el is not None and link_el.get("href")
                else (it.findtext("link") or "")).strip()
        pub = (it.findtext("pubDate") or it.findtext("updated")
               or it.findtext("published") or "")
        published = _parse_date(pub)
        if since_dt and published:
            try:
                pub_dt = datetime.strptime(published, "%Y-%m-%d").date()
                if pub_dt < since_dt:
                    continue
            except ValueError:
                pass
        desc = (it.findtext("description") or it.findtext("summary") or "").strip()
        desc = _clean_html(desc)
        year = int(published[:4]) if published else 0
        authors_el = it.findall("author") + it.findall("creator")
        authors = [(a.text or "").strip() for a in authors_el if a is not None]

        yield {
            "source_id": source.get("id", ""),
            "category": source.get("category", ""),
            "doi": "",
            "arxiv_id": "",
            "title": title,
            "authors": [a for a in authors if a],
            "year": year,
            "published_date": published,
            "journal": source.get("note", ""),
            "abstract": desc[:2000],
            "url": link,
        }
        emitted += 1


# ─────────────────────── main ───────────────────────

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--source-json", help="source spec as JSON string")
    ap.add_argument("--source-file", help="source spec as JSON file path")
    ap.add_argument("--since", required=True,
                    help="YYYY-MM-DD — earliest publication date to include")
    ap.add_argument("--max", type=int, default=20, dest="max_n")
    ap.add_argument("--email", default="",
                    help="contact email for polite-pool Crossref/OpenAlex")
    args = ap.parse_args()

    if args.source_json:
        source = json.loads(args.source_json)
    elif args.source_file:
        with open(args.source_file, "r", encoding="utf-8") as fh:
            source = json.load(fh)
    else:
        ap.error("one of --source-json or --source-file required")
        return 2

    backend = source.get("type", "").lower()
    try:
        if backend == "crossref":
            it = fetch_crossref(source, args.since, args.max_n, email=args.email)
        elif backend == "arxiv":
            it = fetch_arxiv(source, args.since, args.max_n)
        elif backend == "openalex":
            it = fetch_openalex(source, args.since, args.max_n, email=args.email)
        elif backend == "rss":
            it = fetch_rss(source, args.since, args.max_n)
        else:
            _log(f"ERROR: unknown backend '{backend}'")
            return 3
    except Exception as exc:
        _log(f"ERROR: {backend} fetch failed: {exc}")
        return 4

    count = 0
    for rec in it:
        sys.stdout.write(json.dumps(rec, ensure_ascii=False) + "\n")
        count += 1
    _log(f"emitted {count} records")

    # Per-backend courtesy sleeps — avoid hammering when called in batch under /loop
    if backend == "arxiv":
        time.sleep(3)
    elif backend in ("crossref", "openalex"):
        time.sleep(1)

    return 0


if __name__ == "__main__":
    sys.exit(main())
