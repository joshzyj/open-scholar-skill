---
name: scholar-rag
description: "Build and query a local vector database + GraphRAG over your entire reference library (Zotero or a PDF folder) for literature review. Downloads/locates full-text PDFs, extracts text (pdftotext/PyMuPDF/vision-OCR), chunks and embeds with bge-m3 into LanceDB, and layers a local-LLM GraphRAG (entity/relation extraction + Leiden communities + community summaries) seeded from the scholar-knowledge graph. Adds a bibliographic layer from OpenAlex (direct citations + bibliographic coupling + co-citation + paper-level communities). Exposes semantic retrieval to Claude Code and Codex via an MCP server (rag_search / rag_get_document / rag_neighbors / rag_stats). Local by default (bge-m3 + ollama + LanceDB); the only network use is the optional OA PDF fetch and the optional OpenAlex citation fetch. Use to build a searchable literature corpus, ground lit-review claims in cited passages, or find related papers."
tools: Read, Bash, Write
argument-hint: "[setup|ingest|query|mcp|graph|citations|keywords|semantic|status] [args], e.g. 'ingest' or 'query how does segregation affect mobility' or 'graph run'"
user-invocable: true
---

# Scholar RAG — Local Vector DB + GraphRAG for Your Literature

You turn a scholar's whole reference library into a **searchable, cited knowledge base**. This skill ships a **real, self-contained execution engine** in `assets/` (a Python package + a venv provisioner + a resumable build wrapper + an MCP server) — not in-context snippets. All *analysis* runs **locally**: `bge-m3` embeddings, an `ollama` LLM for GraphRAG, `LanceDB` for vectors, and a stdio MCP server. No passage text, PDF, or note ever leaves the machine. Two **opt-in** stages do make network calls, both metadata-only: the open-access PDF fetch (MODE 1) and the OpenAlex citation/topic fetch (MODE 6), which sends DOIs and your polite-pool email.

It is the **dense-retrieval complement** to `scholar-knowledge` (which stores *symbolic* extracted findings, keyword-searched). `scholar-knowledge` answers "what does the field claim"; `scholar-rag` answers "show me the exact passages, cited, and the papers near them." The two share paper identity by DOI/title and `scholar-rag`'s GraphRAG **seeds its entity graph from `scholar-knowledge`**.

> **SELF-CONTAINED.** The engine has no hard dependency on the rest of the plugin. It provisions its own venv, reads Zotero directly, and bundles its own logging. It *optionally* seeds from `scholar-knowledge` if present, degrading gracefully if not.

> **DATA SAFETY.** The corpus is *published papers* — normally `CLEARED`. But in `folder` mode a directory may contain unpublished drafts or sensitive PDFs. If a project safety sidecar (`.claude/safety-status.json`) marks any input `NEEDS_REVIEW`/`HALTED`, do not ingest it; route through `/scholar-safety` or `/scholar-init` first. Local embeddings + local LLM mean no external transfer by default.

---

## Arguments and Mode Routing

The user has provided: `$ARGUMENTS`

| Keyword(s) | Mode | What it does |
|---|---|---|
| `setup`, `install`, `venv` | **0 SETUP** | Provision the self-contained Python venv (one-time) |
| `ingest`, `build`, `index`, `add` | **1 INGEST** | Source → extract text → chunk → embed → LanceDB (resumable) |
| `query`, `search`, `find`, `ask` | **2 QUERY** | Semantic retrieval (dense + hybrid BM25 + optional rerank) |
| `mcp`, `register`, `serve`, `connect` | **3 MCP** | Register the MCP server with Claude Code / Codex |
| `graph`, `graphrag`, `neighbors`, `communities`, `global` | **4 GRAPH** | GraphRAG: seed → extract → build → summarize; local/global search |
| `status`, `stats`, `coverage` | **5 STATUS** | Corpus + index + graph coverage |
| `citations`, `cite`, `bibliography`, `coupling` | **6 CITATIONS** | OpenAlex citation layer: direct cites + coupling + co-citation + paper communities |
| `keywords`, `tags`, `topics` | **7 KEYWORDS** | Fold Zotero tags + OpenAlex topics + in-text keyword lines into the entity graph |
| `semantic`, `similarity`, `synonyms` | **8 SEMANTIC** | Embedding-derived edges: paper↔paper kNN and entity synonym linking |

If the mode is ambiguous, ask. `full` runs 0→1→3 (setup, build, register MCP); GraphRAG (mode 4) is run explicitly because it is the long, LLM-bound stage.

---

## Setup block (run once per Bash session, all modes)

Resolve this skill's `assets/` dir (self-contained — tries the dev tree, the
marketplace install, then a find) and the venv interpreter:

```bash
# locate assets/ without depending on plugin bootstrap vars. CLAUDE_PLUGIN_ROOT
# is set by Claude Code for plugin skills; the rest are install-layout fallbacks.
RAG_ASSETS=""
for c in \
  "${CLAUDE_PLUGIN_ROOT:-}/skills/scholar-rag/assets" \
  "${SCHOLAR_SKILL_DIR:-}/.claude/skills/scholar-rag/assets" \
  "${SCHOLAR_SKILL_DIR:-}/skills/scholar-rag/assets" \
  "$HOME/.claude/skills/scholar-rag/assets"; do
  [ -n "$c" ] && [ -f "$c/ingest.py" ] && { RAG_ASSETS="$c"; break; }
done
[ -z "$RAG_ASSETS" ] && RAG_ASSETS="$(dirname "$(find "$HOME/.claude" -name mcp_server.py -path '*scholar-rag*' 2>/dev/null | head -1)")"
. "$RAG_ASSETS/_lib.sh"     # sets SCHOLAR_RAG_DIR, RAG_VENV, RAG_PY, rag_trace()
echo "assets=$RAG_ASSETS  store=$SCHOLAR_RAG_DIR  py=$RAG_PY"
```

Then `rag_py <script.py> ...` runs an engine module with the resolved interpreter.

### Process logging (RAO trace)

At each meaningful step (a build stage, MCP registration, a graph stage), append one Reasoning·Action·Observation record. Prefer the plugin's shared tracer when present; the engine also writes a **bundled** trace via `rag_trace()` in `_lib.sh`, so logging works even in a standalone deploy:

```bash
# shared emit-trace.sh if available, else the self-contained bundled fallback
TRACE() { bash "${CLAUDE_PLUGIN_ROOT:-${SCHOLAR_SKILL_DIR:-$RAG_ASSETS/../../..}}/scripts/gates/emit-trace.sh" --skill scholar-rag "$@" 2>/dev/null \
  || rag_trace "$(echo "$*" | sed -n 's/.*--step \([^ ]*\).*/\1/p')" ok "$*"; }
TRACE --step "ingest" --reasoning "build the vector DB from Zotero" \
      --action "run-ingest.sh --batch 64" --observation "<N> docs embedded" --status ok
```

Privacy: traces carry counts / verdicts / file refs only — never verbatim passage text or PII.

---

## MODE 0 — SETUP (one-time)

Provision the venv (CPython 3.12 via `uv`; installs PyMuPDF, LanceDB,
sentence-transformers/bge-m3, mcp, and the GraphRAG deps) and prefetch bge-m3:

```bash
bash "$RAG_ASSETS/setup-venv.sh" --prefetch-models   # add --no-graph to skip Leiden deps
```

Verify: the script prints `ok` for `fitz, lancedb, sentence_transformers, mcp, torch (MPS=…)`. Report the torch/MPS line — MPS-accelerated embedding is much faster.

---

## MODE 1 — INGEST (build the vector DB)

The resumable, three-stage build (source → extract → embed). Safe to re-run; each stage skips finished work. This is the main deliverable.

```bash
# whole Zotero library (auto-detected); use --limit to trial a subset first
bash "$RAG_ASSETS/run-ingest.sh" --batch 64            # foreground (watch it)
bash "$RAG_ASSETS/run-ingest.sh" --batch 64 --background   # detach; tail the printed log
# a folder of PDFs instead of Zotero:
bash "$RAG_ASSETS/run-ingest.sh" --source folder --folder /path/to/pdfs
# enable vision-OCR for scanned PDFs (slower; llama3.2-vision via ollama):
bash "$RAG_ASSETS/run-ingest.sh" --ocr
```

Scale note: a full library is embedding-bound (~thousands of PDFs → hours on MPS). It is resumable — a killed run continues. Individual stages: `rag_py ingest.py zotero --with-pdf-only`, `rag_py extract.py run`, `rag_py chunk_embed.py run`.

---

## MODE 2 — QUERY (semantic retrieval)

```bash
rag_py query.py "how does residential segregation affect intergenerational mobility?" -k 8 --hybrid
# filters + reranking:
rag_py query.py "identification strategy" -k 6 --section methods,results --year-min 2010 --rerank --json
```

Returns passages with an author-year citation, section, page range, DOI, and similarity. Use `--json` for machine-readable output. This is exactly what the MCP `rag_search` tool wraps.

---

## MODE 3 — MCP (expose to Claude Code / Codex)

```bash
bash "$RAG_ASSETS/mcp-setup.sh"              # register with every detected host
bash "$RAG_ASSETS/mcp-setup.sh" --print-only # just show the .mcp.json / config.toml snippets
```

Registers a stdio MCP server exposing **`rag_search`**, **`rag_get_document`**, **`rag_neighbors`**, **`rag_stats`**. Restart the Claude Code / Codex session to pick up the tools. In a lit-review session, call `rag_search` to ground every claim in cited passages from your own library.

**Tool errors are outages, not counts.** If any `rag_*` call errors — `Connection closed`, tool not found, timeout — that is `TOOL_UNAVAILABLE`: the check did not run, and it says nothing about the library. Never report an MCP error as "0 documents" or "no local library". `rag_stats` returns an explicit `status` (`ok | ok-empty | corpus-missing | corpus-corrupt | server-error`) plus `corpus_path` and `on_disk_bytes`, so a zero is checkable against the file on disk. The no-venv, no-MCP fallback the operator can always run: `python3 "$SKILL_DIR/assets/store.py"` — a genuine "no local library" claim requires `corpus-missing` from that fallback, not an optimistic reading of a transport error.

---

## MODE 4 — GRAPH (GraphRAG)

The LLM-bound long pole; run **after** the vector build. Fully local via `ollama`.

```bash
rag_py graphrag.py seed                 # import scholar-knowledge concepts + citation edges (fast, no LLM)
rag_py graphrag.py extract              # LLM entity/relation extraction per paper (resumable; the long stage)
rag_py graphrag.py build                # merge entities → Leiden communities
rag_py graphrag.py summarize            # LLM community summaries (global-search corpus)
# or the whole chain (bounded by --limit while trialing):
rag_py graphrag.py run --limit 50
# query:
rag_py graphrag.py local  "mechanisms linking neighborhood to health"   # entity-grounded passages
rag_py graphrag.py global "what are the major theoretical camps in this literature?"  # map-reduce over communities
rag_py graphrag.py neighbors <doc_id>   # papers sharing entities / citations
```

**Entity identity.** `ent_id` hashes the **normalized name only** — type is a
majority-vote attribute, not part of the key. Making type part of the identity
(the pre-2026-08 behaviour) fragmented exactly the hubs that matter: `machine
learning` was three nodes (method/concept/population) instead of one node seen
in 98 papers. `norm_name()` also folds unicode dashes, punctuation and plurals,
which is what merges `COVID-19` with `COVID‑19` (U+2011). `author` is **not** an
entity type: `corpus.sqlite` already stores authoritative `authors_json`, and
LLM-scraped author names were ~14% of the graph and almost all singletons.

**Coverage knobs that decide graph quality.**

| Env / flag | Default | Why it matters |
|---|---|---|
| `RAG_GRAPH_WINDOWS` / `--windows` | 4 | Text windows sampled per paper (see *Which sections get read* below). At 1 you only ever see the first `RAG_GRAPH_MAX_CHARS` (~16% of a median paper), so discussion, conclusion and findings never enter the graph. Progress is tracked per **window signature**, so raising this only costs the newly-reachable regions. |
| `RAG_GRAPH_MIN_DOCS` / `--min-docs` | 2 | Drops entities seen in fewer than N papers. A single-paper entity cannot link papers; it only forms an isolated clique that inflates the community count. Typically prunes most of the entity set. |
| `RAG_GRAPH_COOC_MIN` | 2 | Co-occurrence edge threshold. Needed because pruning kills ~80% of LLM relations (most are paper-local with a singleton endpoint). Measured on a 5.5k-paper corpus: `1` collapses the graph into ~40 blobs, `3` starves it, `2` is the sweet spot. |
| `RAG_GRAPH_CITE_WEIGHT` | 1.0 | Weight of citation-derived entity edges (see MODE 6). `0` disables, restoring wording-only clustering. |
| `RAG_GRAPH_CITE_MIN_SUPPORT` | 8 | Independent citations required behind an entity pair before it becomes an edge. Projection is quadratic in entities-per-paper: one citation between two 15-entity papers mints ~225 pairs, so 17k citations produced **1.5M** pairs — 16× the co-occurrence layer — and collapsed the graph to 34 blobs. |
| `RAG_GRAPH_SEM_WEIGHT` | 3.0 | Weight of `entity_semantic.ndjson` synonym edges. Higher than a co-occurrence unit because a synonym pair is stronger evidence than one shared paper. Kept as an edge, never a hard merge, so a bad pairing distorts clustering instead of destroying a node. |
| `RAG_GRAPH_RESOLUTION` | 6.0 | Leiden resolution for the **entity** graph. At the 1.0 default this graph yields a few giant blobs — broad keyword nodes (OpenAlex topics like "Political science" tag hundreds of papers) act as hubs bridging unrelated areas. Measured: res 3 → 113 communities/largest 1416; **res 6 → 167/490**; res 12 → 319/204. |

**Which sections get read.** Extraction samples windows in this priority order,
always excluding `references` (a bibliography yields author and journal names,
which are noise in a concept graph):

1. **head** — abstract + introduction
2. **theory / literature / related work**
3. **discussion + conclusion**
4. **results + methods**

Two strategies. *Section-aware* uses `chunk_embed.detect_sections` on the full
text and succeeds for ~84% of papers. *Positional fallback* handles the rest:
head window, then windows spread across the body with the **last one anchored at
the tail**. Anchoring matters — an evenly-spaced scheme with one extra window
places it at ~16–32% of the paper, so discussion and conclusion (at ~70–95%)
stayed invisible even with multiple windows.

Measured signature frequency over 300 papers at `--windows 4`: `head` 300,
`sec:conclusion` 131, `sec:results` 99, `sec:discussion` 95, `sec:methods` 25,
`sec:literature` 20, remainder positional.

> **On theory/literature specifically:** only ~5% of papers in a typical
> social-science corpus carry an explicit *Literature Review* / *Related Work* /
> *Theoretical Framework* heading — theory is usually woven into the
> introduction, which the **head** window already covers. Do not read a low
> `sec:literature` count as a failure; check whether the heading exists at all
> before tuning for it.

**Model note.** Extraction auto-selects the first available of `gpt-oss:20b` →
`qwen2.5:7b-instruct` → … → `deepseek-r1:32b`; override with
`RAG_GRAPH_MODEL`. Older ollama builds fail to load `gpt-oss:20b` with an MoE
"size overflow" — `brew upgrade ollama` fixes it. Extraction over a full library
is hours of local inference — run it detached and let it resume across sessions.

> **Always `export SCHOLAR_RAG_DIR` before backgrounding a stage.** `nohup … python graphrag.py summarize &` without it silently resolves the store to the default path and dies instantly with `{"error": "run build first"}`. Use `nohup env SCHOLAR_RAG_DIR="$STORE" …`.

---

## MODE 5 — STATUS

```bash
rag_py ingest.py status        # documents by stage, chunk counts, no-PDF coverage
rag_py graphrag.py status      # entities / relations / communities / summaries
rag_py citations.py status     # OpenAlex cache, citation edges, paper communities
```

---

## MODE 6 — CITATIONS (bibliographic layer)

Entity co-mention answers "which papers use the same words." Citations answer
"which papers actually build on each other." Without this layer `build()` has
**zero** bibliographic input — the `seed()` edges alone covered ~12% of a 5.5k
corpus and were read only by `neighbors`.

```bash
rag_py citations.py fetch          # one OpenAlex call per DOI (resumable, cached)
rag_py citations.py build          # direct cites + coupling + co-citation + paper communities
rag_py citations.py neighbors <doc_id> -k 10   # related papers, with the reason why
```

Three relations, in increasing coverage — all derived from **outbound**
reference lists, so one call per DOI suffices (no inbound-citation crawl):

- **direct citation** — A cites B, both in the library. Highest precision, but needs both ends present.
- **bibliographic coupling** — A and B cite the same work. The shared reference need *not* be in the library, so this reaches far more pairs and stays useful for recent papers with few citations yet.
- **co-citation** — A and B are both cited by some in-corpus paper. The classic complement; reflects how the field itself groups work.

These are unioned into a weighted paper graph (direct is weighted higher, being
an author's explicit claim rather than a statistic) and clustered with Leiden
into **paper-level communities** — the research lineages/schools in the library,
a genuinely different view from the entity communities. The same edges are
projected back into the entity graph via `RAG_GRAPH_CITE_WEIGHT`, so concepts
joined by citing papers cluster together.

**Granularity is set by resolution, not by thresholds.** Coupling makes this
graph genuinely dense — a 4.2k-paper corpus produced ~107k coupling pairs — and
at Leiden's default resolution 1.0 you get ~15 giant blobs. Raising
`--min-coupling` barely helps (at 6 you have discarded most of the evidence and
still get ~40 communities); raising `RAG_CITE_RESOLUTION` keeps every edge and
actually resolves subfields. Measured on that corpus:

| resolution | communities | largest |
|---|---|---|
| 1 | 15 | 857 |
| 4 | 43 | 359 |
| **8** (default) | **98** | **203** |
| 15 | 232 | 150 |

At 8, ~98 communities of ~40 papers each land at "research area" granularity —
sociolinguistics, computational NLP, misinformation, deep-learning
architectures. Push higher for narrower topics, lower for broad traditions.

**Projection guard.** Citation→entity projection is quadratic in entities per
paper, so each citation's contribution is normalized by `1/sqrt(|E_src|·|E_dst|)`.
Without that, 703 seed citations alone generated 12k entity edges and OpenAlex's
16.5k would swamp every other signal.

> **Network use.** This is the one stage that sends library data outward: one
> request per DOI to `api.openalex.org`, carrying the DOI and your polite-pool
> `SCHOLAR_CROSSREF_EMAIL`. No text, no PDFs. Papers without a DOI are skipped
> deliberately — OpenAlex title-matching is unreliable enough that it would
> inject false citation edges, which is worse than a missing one.

---

## MODE 7 — KEYWORDS (curated vocabulary)

Three keyword sources exist in a normal setup and all three were historically
ignored. They matter disproportionately because they are **inherently
multi-document** — one tag covers dozens of papers — which is exactly what the
entity graph is short of, and they carry no hallucination risk.

```bash
rag_py keywords.py load                       # all three sources
rag_py keywords.py load --sources zotero,intext   # skip OpenAlex
rag_py keywords.py status
```

| Source | Coverage (typical) | Notes |
|---|---|---|
| `zotero` | ~69% of items | `itemTags`. Publisher/author keywords land here on import. Read live from `zotero.sqlite` by `zotero_key` — **no `tags` column exists in `corpus.sqlite`**, so nothing needs re-ingesting. |
| `openalex` | ~95% of DOI'd papers | `topics` / `keywords` / `concepts`, a curated scored taxonomy, cached by MODE 6's fetch — free, same request. Filtered by `--min-score` (default 0.3). |
| `intext` | ~39% of papers | The "Keywords: a; b; c" line under the abstract. Parsing stops at the first prose-looking token, since PDF extraction runs the line into body text. |

Keywords merge into the graph under the **same normalized identity** as
LLM-extracted entities, so a keyword matching an existing node reinforces it
rather than duplicating it. Provenance is kept in `source` as `kw:zotero` /
`kw:openalex` / `kw:intext`. Bookkeeping tags (`unread`, `migrated-*`, `_*`) are
excluded — see `_STOP_TAGS`.

---

## MODE 8 — SEMANTIC (embedding-derived structure)

The LanceDB index already holds a bge-m3 vector per chunk, but it was used only
for retrieval and contributed nothing to the graph. Both uses below are cheap
because the chunk vectors already exist.

```bash
rag_py semantic.py docs        --k 10 --min-sim 0.90   # paper↔paper kNN
rag_py semantic.py entities    --k 8  --min-sim 0.80   # entity synonym linking
rag_py semantic.py duplicates  --min-sim 0.995         # same work ingested twice
rag_py semantic.py status
```

- **`docs`** mean-pools each paper's chunks into a paper vector and kNNs it. This complements MODE 6 in a way that matters: a paper with **no DOI never enters the OpenAlex cache at all**, so it is invisible to the entire bibliographic layer. On a 5.5k-paper social-science reference corpus, adding semantic edges lifted paper-graph coverage from 72% to 95% of papers (3,923 → 5,189). It also links papers that are plainly about the same thing but share no references — concurrent work, adjacent subfields, different literatures.
- **`entities`** embeds entity *names* and links near-neighbours. This does what normalization provably cannot: `residential segregation` / `neighborhood segregation` / `spatial segregation` normalize to three distinct keys but are one concept. Real merges observed: `experienced isolation index` ≈ `experienced isolation` (0.90), `activity space segregation index` ≈ `activity-space segregation` (0.89).

**Thresholds are not interchangeable between the two.** Document similarity is
compressed far higher than phrase similarity — measured on a 5.5k-paper
social-science corpus, the
median top-10 *paper* neighbour scored **0.886**, so a 0.55 floor kept
essentially everything (7.9 edges/paper) including a historical-sociology
monograph sitting next to an LLM benchmark paper. Check the distribution before
trusting a cutoff:

| paper `min-sim` | edges | per paper |
|---|---|---|
| 0.55 | 43,293 | 7.9 |
| 0.85 | 34,661 | 6.3 |
| **0.90** (default) | **11,935** | **2.2** |
| 0.95 | 1,127 | 0.2 |

For *entity names* the picture is different — unrelated short phrases sit around
0.3–0.6 and genuine synonyms above ~0.85, so 0.80 is a reasonable floor there.
Edges keep both names in `graph/entity_semantic.ndjson` so pairings are
auditable before anything is merged.

**`duplicates`** exploits the same vectors to find the same work ingested twice.
`doc_id` is `sha256(normalized DOI or title)`, so same-DOI duplicates are already
collapsed; what survives is items where one side lacks a DOI and the titles hash
apart (filename-derived titles, truncation, case). These are worth pruning: they
inflate co-occurrence and citation weight and return twice in retrieval. Pairs at
`sim ≥ 0.995` are excluded from the paper graph, since linking a work to itself
asserts nothing.

> A `diff-doi` pair at `sim` ≈ 1.0 means something else: two items with
> *different* metadata resolving to *identical text*, i.e. **the wrong PDF is
> attached** to one of them. Worth fixing in Zotero — every downstream layer
> inherits the mis-attribution.

---

## Integration

- **Lit review / writing:** once the MCP server is registered, `scholar-lit-review`, `scholar-write`, and `scholar-citation` can call `rag_search` as a full-text semantic tier (complements Tier-0 KG metadata and Tier-1 Zotero).
- **Idea stage:** `scholar-idea` Step 3 and `scholar-brainstorm` Step 5 call it as **Tier 1b** before rating novelty. Novelty is a NEGATIVE claim ("nobody has asked this"), and a metadata-only scan cannot see a finding buried in a results section of a paper the user already owns — so an index materially changes what an `UNEXPLORED` rating is worth. Both are CONDITIONAL on the index existing and both must state coverage: an absent or timed-out Tier 1b is `TIER1B_UNAVAILABLE`, never evidence of novelty.
- **Feedback to `scholar-knowledge`:** extracted full text can upgrade abstract-only nodes — run `/scholar-knowledge re-extract` after a build.
- **Shared identity:** `doc_id` = sha256(normalized DOI or title), so a passage hit cross-links to the same paper's symbolic findings.

## Configuration (`.env` or environment)

`SCHOLAR_RAG_DIR` (store, default `~/.claude/scholar-rag`) · `SCHOLAR_ZOTERO_DIR` · `EMBED_MODEL` (default `BAAI/bge-m3`) · `RAG_CHUNK_CHARS` / `RAG_CHUNK_OVERLAP` · `RAG_GRAPH_MODEL` / `RAG_SUMMARY_MODEL` · `RAG_OCR_MODEL` (default `llama3.2-vision:90b`) · `OLLAMA_HOST` · `RAG_GRAPH_WINDOWS` · `RAG_GRAPH_MIN_DOCS` · `RAG_GRAPH_COOC_MIN` · `RAG_GRAPH_CITE_WEIGHT` · `SCHOLAR_CROSSREF_EMAIL` (OpenAlex polite pool).

These are read from `$SCHOLAR_SKILL_DIR/.env` and `~/.claude/.env` by `_lib.sh`.

> **Set `SCHOLAR_ZOTERO_DIR` explicitly; do not trust auto-detection.**
> `detect_zotero_dir()` only probes `~/Zotero`, `~/Documents/Zotero`, a snap
> path, and `~/Library/CloudStorage/*`. A data directory anywhere else — a
> Dropbox folder, an external volume — is invisible to it, and the failure is
> **silent and wrong**: it falls through to a stale `~/Zotero` copy and ingests
> that instead. Verify before any long build:
>
> ```bash
> rag_py zotero_reader.py stats      # must print the dir you expect + a sane total_items
> ```
>
> The authoritative answer is Zotero's own preference, not a guess:
> ```bash
> grep dataDir ~/Library/Application\ Support/Zotero/Profiles/*/prefs.js
> ```

## Quality checklist

- [ ] `setup-venv.sh` reports all imports `ok` and torch MPS status.
- [ ] `zotero_reader.py stats` names the **intended** library dir and a plausible `total_items` — before any long build, not after.
- [ ] `ingest.py status` shows `embedded > 0` and a sane `no_pdf` count before querying.
- [ ] A known-topic `query.py` returns the expected paper with correct author-year + page.
- [ ] MCP handshake lists all four tools (`rag_search`/`rag_get_document`/`rag_neighbors`/`rag_stats`), and `claude mcp list` shows it **Connected** at a path that still exists.
- [ ] GraphRAG `status` shows entities and communities before using `global`.
- [ ] Keyword layer loaded (`keywords.py status` shows `kw:*` sources) — it is the cheapest source of multi-doc nodes and needs no LLM.
- [ ] Graph health, not just totals: a large majority of entities should be **multi-doc**. If most appear in one paper only, the graph cannot link anything — raise `RAG_GRAPH_WINDOWS`, and check that `norm_name` is actually merging your top hubs.
- [ ] `community_summaries.json` was regenerated **after** the most recent `build`. Community ids are reassigned every build, so summaries from a previous run silently mis-key `global` search.

## Store layout

```
$SCHOLAR_RAG_DIR/
  corpus.sqlite       documents + chunks (text_path/pdf_path are ABSOLUTE —
                      moving the store requires rewriting them, see below)
  index/chunks.lance  vectors; run tbl.optimize(cleanup_older_than=0) after big
                      writes or thousands of version fragments accumulate
  raw/text|meta|pdfs  extraction caches — keep these, they make rebuilds cheap
  raw/openalex/       cached OpenAlex records: refs + topics (MODE 6/7)
  graph/              entities.ndjson  relations.ndjson  communities.json
                      community_summaries.json  extracted_docs.json
                      doc_edges.ndjson        scholar-knowledge seed edges
                      citations.ndjson        direct intra-corpus citations
                      paper_edges.ndjson      weighted paper graph (MODE 6)
                      paper_communities.json  paper-level Leiden clusters
                      doc_semantic.ndjson     paper kNN      (MODE 8)
                      entity_semantic.ndjson  entity synonyms (MODE 8)
  engine/             runtime copy of assets/ (refresh with sync-engine.sh)
```

**What actually feeds what.** A layer that is computed but read by nothing is
the recurring failure mode here — check this table before assuming a signal is
live (`grep -l <file> engine/*.py` settles it):

| Artifact | Produced by | Consumed by |
|---|---|---|
| `entities.ndjson` | graph extract, **keywords load** | graph build, semantic entities |
| `relations.ndjson` | graph extract | graph build |
| `doc_edges.ndjson` | graph seed (scholar-knowledge) | graph build (entity projection) |
| `citations.ndjson` | citations build | citations build, **graph build** (entity projection) |
| `doc_semantic.ndjson` | semantic docs | **citations build** (paper graph) |
| `entity_semantic.ndjson` | semantic entities | **graph build** (synonym edges) |
| `paper_edges.ndjson` | citations build | citations neighbors |
| `paper_communities.json` | citations build | citations status |
| `communities.json` | graph build | graph summarize, global search |
| `community_summaries.json` | graph summarize | global search |

Keywords have no file of their own by design — they merge straight into
`entities.ndjson` under the same normalized identity, so a keyword matching an
extracted entity reinforces that node instead of duplicating it.

**Recommended full order.** Later stages consume earlier ones, so ordering is
not arbitrary: keywords need the OpenAlex cache, and every graph stage must
precede `build`, which must precede `summarize`.

```
setup → ingest → mcp → citations fetch → citations build
      → graph seed → graph extract → keywords load → semantic entities
      → graph build → graph summarize
```

> **Moving the store breaks absolute paths.** `documents.text_path` and
> `pdf_path` are absolute. After relocating `$SCHOLAR_RAG_DIR`, rewrite them or
> every downstream stage silently no-ops (`extract` will report success having
> read nothing, and will mark the docs done):
> ```sql
> UPDATE documents SET text_path = replace(text_path, '<old>', '<new>')
>   WHERE text_path LIKE '<old>%';   -- same for pdf_path
> ```
