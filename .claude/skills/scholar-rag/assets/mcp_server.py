#!/usr/bin/env python3
"""
mcp_server.py — expose the scholar-rag index to Claude Code / Codex over MCP.

A stdio Model Context Protocol server (FastMCP). Read-only: it retrieves from
the local LanceDB index built by the ingest pipeline; it never mutates the
store. Run it via the venv interpreter so torch/lancedb/bge-m3 are importable.

Tools
  rag_search(query, k, section, year_min, year_max, hybrid, rerank)
        -> semantically retrieved passages with citations + page numbers
  rag_get_document(doc_id, include_text)
        -> full bibliographic record for a hit (and optionally its full text)
  rag_neighbors(doc_id, k)                      [GraphRAG; M4]
        -> papers linked in the literature graph (falls back to embedding-kNN)
  rag_stats()
        -> corpus coverage + index manifest

Register (Claude Code, .mcp.json):
  {"mcpServers":{"scholar-rag":{"command":"<venv>/bin/python",
     "args":["<assets>/mcp_server.py"]}}}
Register (Codex, ~/.codex/config.toml):
  [mcp_servers.scholar-rag]
  command = "<venv>/bin/python"
  args = ["<assets>/mcp_server.py"]
"""
import os, sys, json
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import store
import query as Q

# MCP Python SDK: modern SDKs expose MCPServer (the FastMCP successor:
# same .tool() decorator + .run() stdio default); older ones ship FastMCP.
try:
    from mcp.server import MCPServer as _Server
except Exception:  # pragma: no cover - legacy SDK fallback
    from mcp.server.fastmcp import FastMCP as _Server

mcp = _Server("scholar-rag")


@mcp.tool()
def rag_search(query: str, k: int = 8, section: str = "", year_min: int = 0,
               year_max: int = 0, hybrid: bool = True, rerank: bool = False) -> str:
    """Semantic search over the user's full-text literature library.

    Returns the k passages most relevant to `query`, each with an author-year
    citation, section, page range, DOI, and the passage text. Use this to
    ground literature-review claims in specific cited passages.

    Args:
        query: natural-language question or topic.
        k: number of passages to return (default 8).
        section: optional comma-separated filter, e.g. "methods,results".
        year_min / year_max: optional publication-year bounds (0 = unbounded).
        hybrid: fuse dense + BM25 (default True); set False for dense-only.
        rerank: apply a cross-encoder reranker (slower, higher precision).
    """
    res = Q.search(query, k=k, section=section or None,
                   year_min=year_min or None, year_max=year_max or None,
                   hybrid=hybrid, rerank=rerank)
    return json.dumps({"query": query, "n": len(res), "results": res},
                      ensure_ascii=False, indent=1)


@mcp.tool()
def rag_get_document(doc_id: str, include_text: bool = False) -> str:
    """Fetch the full bibliographic record for a doc_id returned by rag_search.

    Args:
        doc_id: the doc_id field from a rag_search result.
        include_text: if True, include the extracted full text (can be large).
    """
    con = store.connect()
    row = con.execute("SELECT * FROM documents WHERE doc_id=?", (doc_id,)).fetchone()
    if not row:
        return json.dumps({"error": "no such doc_id", "doc_id": doc_id})
    d = dict(row)
    d["authors"] = json.loads(d.get("authors_json") or "[]")
    d.pop("authors_json", None)
    if include_text and d.get("text_path") and os.path.isfile(d["text_path"]):
        pages = json.load(open(d["text_path"])).get("pages", [])
        d["full_text"] = "\n\n".join(p["text"] for p in pages)
    return json.dumps(d, ensure_ascii=False, indent=1)


@mcp.tool()
def rag_neighbors(doc_id: str, k: int = 8) -> str:
    """Papers related to `doc_id` in the literature graph.

    Uses the GraphRAG entity/citation graph when built (M4); otherwise falls
    back to embedding k-NN over the paper's own chunks.
    """
    try:
        import graphrag
        nb = graphrag.neighbors(doc_id, k=k)
        if nb:
            return json.dumps({"doc_id": doc_id, "source": "graph",
                               "neighbors": nb}, ensure_ascii=False, indent=1)
    except Exception:
        pass
    # fallback: nearest chunks from other documents
    con = store.connect()
    row = con.execute("SELECT title FROM documents WHERE doc_id=?",
                      (doc_id,)).fetchone()
    seed = row["title"] if row else doc_id
    res = [r for r in Q.search(seed or "", k=k * 3, hybrid=False)
           if r["doc_id"] != doc_id]
    seen, out = set(), []
    for r in res:
        if r["doc_id"] in seen:
            continue
        seen.add(r["doc_id"]); out.append({"doc_id": r["doc_id"],
                 "cite": r["cite"], "title": r["title"], "score": r["score"]})
        if len(out) >= k:
            break
    return json.dumps({"doc_id": doc_id, "source": "embedding-knn",
                       "neighbors": out}, ensure_ascii=False, indent=1)


@mcp.tool()
def rag_stats() -> str:
    """Corpus coverage counts with corpus path, on-disk size, and an explicit
    status — never a bare zero.

    status: ok | ok-empty | corpus-missing | corpus-corrupt | server-error.
    A zero count is only meaningful beside the corpus_path / on_disk_bytes it
    was measured from. If this CALL errors (connection closed, tool not
    found), that is a tool outage, not a count — never read a tool error as
    evidence the library is empty. Fallback that needs no MCP and no venv:
    `python3 <assets>/store.py`.
    """
    return json.dumps(store.stats_payload(), ensure_ascii=False, indent=1)


if __name__ == "__main__":
    mcp.run()   # stdio transport
