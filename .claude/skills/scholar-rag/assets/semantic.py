#!/usr/bin/env python3
"""
semantic.py — build graph structure out of the embeddings we already have.

The LanceDB index holds a bge-m3 vector per chunk, but it was used only for
retrieval; it contributed nothing to the graph. Two uses, both cheap because the
chunk vectors are already computed:

  docs      Mean-pool a paper's chunk vectors into one paper vector, then kNN.
            Complements the citation layer: it links papers that are about the
            same thing but do not cite each other (different subfields,
            concurrent work, language barriers) — precisely the pairs
            bibliographic coupling misses.

  entities  Embed the entity NAMES and link near-neighbours. This does what
            string normalization provably cannot: `residential segregation`,
            `neighborhood segregation` and `spatial segregation` normalize to
            three different keys but are one concept. Emitted as weighted
            `synonym` edges (and optionally hard-merged above a high cutoff),
            which directly attacks the graph's core weakness — too many
            single-paper nodes that link nothing.

Cosine similarity on normalized vectors == dot product; kNN is done in numpy
blocks so it stays memory-bounded on a ~40k x 1024 matrix.

Outputs (under $SCHOLAR_RAG_DIR/graph/):
  doc_semantic.ndjson     {a, b, sim}   paper-paper kNN edges
  entity_semantic.ndjson  {a, b, sim}   entity-entity synonym/related edges

Usage:
  python3 semantic.py docs      [--k 10] [--min-sim 0.90]
  python3 semantic.py duplicates [--min-sim 0.995]
  python3 semantic.py entities  [--k 8]  [--min-sim 0.80] [--min-docs 2]
  python3 semantic.py status
"""
import os, sys, json, argparse
import store


def gdir():
    d = os.path.join(store.rag_dir(), "graph")
    os.makedirs(d, exist_ok=True)
    return d


def _knn_blocks(M, k, min_sim, block=2048):
    """Top-k neighbours per row of a row-normalized matrix, as (i, j, sim).

    Each unordered pair is yielded ONCE. kNN is not symmetric, but it is often
    mutual: when i is in j's top-k and j is in i's top-k, a naive scan emits the
    same pair from both rows. That inflated the reported edge counts ~2x and,
    because citations.build() *sums* semantic weight into the paper graph
    (graphrag.build() takes a max, so it was unaffected), silently gave mutual
    pairs double weight there.
    """
    import numpy as np
    seen = set()
    n = M.shape[0]
    for s in range(0, n, block):
        e = min(n, s + block)
        sims = M[s:e] @ M.T                       # (block, n) cosine
        for r in range(e - s):
            i = s + r
            sims[r, i] = -1.0                     # drop self
            kk = min(k, sims.shape[1] - 1)
            if kk <= 0:
                continue
            idx = np.argpartition(-sims[r], kk)[:kk]
            for j in idx:
                v = float(sims[r, j])
                if v < min_sim:
                    continue
                a, b = (i, int(j)) if i < int(j) else (int(j), i)
                if (a, b) in seen:
                    continue
                seen.add((a, b))
                yield a, b, v


def doc_vectors(batch_rows=20000):
    """doc_id -> mean-pooled, re-normalized chunk vector.

    Reads via pyarrow batches rather than .to_pandas(): pandas is not a
    dependency of this venv, and materializing ~275k x 1024 floats as a
    DataFrame of Python lists is far heavier than accumulating in numpy.
    """
    import numpy as np
    import lancedb
    db = lancedb.connect(os.path.join(store.rag_dir(), "index"))
    tbl = db.open_table("chunks")
    ds = tbl.to_lance()
    sums, counts = {}, {}
    for rb in ds.to_batches(columns=["doc_id", "vector"],
                            batch_size=batch_rows):
        docs_col = rb.column("doc_id").to_pylist()
        vec_col = rb.column("vector")
        # FixedSizeListArray -> flat values -> (n, dim)
        dim = vec_col.type.list_size
        flat = np.asarray(vec_col.values, dtype="float32")
        V = flat.reshape(-1, dim)
        for i, did in enumerate(docs_col):
            if did in sums:
                sums[did] += V[i]
                counts[did] += 1
            else:
                sums[did] = V[i].astype("float32").copy()
                counts[did] = 1
    if not sums:
        return [], np.zeros((0, 1), dtype="float32")
    ids = sorted(sums)
    M = np.vstack([sums[d] / counts[d] for d in ids]).astype("float32")
    M /= (np.linalg.norm(M, axis=1, keepdims=True) + 1e-9)
    return ids, M


def docs(k=10, min_sim=0.90):
    """Paper-paper kNN over mean-pooled chunk vectors.

    On the default threshold: bge-m3 document similarity is compressed high —
    on this corpus the median top-10 neighbour scores 0.886, so a 0.55 floor
    keeps essentially everything (10.0 edges/paper) including nonsense pairings
    like a historical-sociology monograph next to an LLM benchmark paper. 0.90
    keeps ~3.5 edges/paper, which is a real relatedness signal. Pairs at >=0.995
    are usually the SAME work stored twice — see `semantic.py duplicates`.
    """
    ids, M = doc_vectors()
    sys.stderr.write("[semantic.docs] %d papers, dim=%d\n" % (len(ids), M.shape[1]))
    out = []
    for i, j, v in _knn_blocks(M, k, min_sim):
        out.append({"a": ids[i], "b": ids[j], "sim": round(v, 4)})
    with open(os.path.join(gdir(), "doc_semantic.ndjson"), "w") as f:
        for e in out:
            f.write(json.dumps(e) + "\n")
    return {"papers": len(ids), "edges": len(out), "k": k, "min_sim": min_sim}


def entities(k=8, min_sim=0.80, min_docs=2, batch=256):
    """Embed entity names; emit near-synonym edges between graph-eligible nodes."""
    import numpy as np
    import graphrag as G
    import chunk_embed as CE
    ents = G.load_entities()
    cand = [e for e in ents.values()
            if e.get("source") == "kg" or len(e.get("doc_ids", [])) >= min_docs]
    if not cand:
        return {"error": "no entities above min_docs"}
    names = [e["name"] for e in cand]
    sys.stderr.write("[semantic.entities] embedding %d entity names\n" % len(names))
    M = CE.embed_texts(names, batch=batch).astype("float32")
    M /= (np.linalg.norm(M, axis=1, keepdims=True) + 1e-9)
    out = []
    for i, j, v in _knn_blocks(M, k, min_sim):
        out.append({"a": cand[i]["ent_id"], "b": cand[j]["ent_id"],
                    "sim": round(v, 4),
                    "a_name": cand[i]["name"], "b_name": cand[j]["name"]})
    with open(os.path.join(gdir(), "entity_semantic.ndjson"), "w") as f:
        for e in out:
            f.write(json.dumps(e, ensure_ascii=False) + "\n")
    return {"entities_considered": len(cand), "edges": len(out),
            "k": k, "min_sim": min_sim,
            "sample": [(e["a_name"], e["b_name"], e["sim"]) for e in out[:12]]}


def duplicates(min_sim=0.995, limit=40):
    """Near-identical paper pairs — the same work ingested twice.

    doc_id is sha256(normalized DOI or title), so same-DOI duplicates are
    already collapsed. What survives is items where at least one side has no
    DOI and the titles differ enough to hash apart (filename-derived titles,
    truncation, punctuation). These inflate co-occurrence and citation weights
    and return twice in retrieval, so they are worth pruning in Zotero.
    """
    import sqlite3
    con = store.connect()
    meta = {r["doc_id"]: r for r in
            con.execute("SELECT doc_id, title, doi, n_chars FROM documents")}
    out = []
    for line in open(os.path.join(gdir(), "doc_semantic.ndjson")):
        e = json.loads(line)
        if e["sim"] < min_sim:
            continue
        a, b = meta.get(e["a"]), meta.get(e["b"])
        if not a or not b:
            continue
        da = (a["doi"] or "").strip().lower()
        db_ = (b["doi"] or "").strip().lower()
        kind = ("same-doi" if da and db_ and da == db_
                else "diff-doi" if da and db_ else "missing-doi")
        out.append({"sim": e["sim"], "kind": kind,
                    "a": {"doc_id": e["a"], "title": a["title"], "doi": a["doi"]},
                    "b": {"doc_id": e["b"], "title": b["title"], "doi": b["doi"]}})
    out.sort(key=lambda r: -r["sim"])
    from collections import Counter
    return {"pairs": len(out), "by_kind": dict(Counter(r["kind"] for r in out)),
            "min_sim": min_sim, "sample": out[:limit]}


def status():
    def _n(p):
        p = os.path.join(gdir(), p)
        return sum(1 for _ in open(p)) if os.path.isfile(p) else 0
    return {"doc_semantic_edges": _n("doc_semantic.ndjson"),
            "entity_semantic_edges": _n("entity_semantic.ndjson")}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("command", choices=["docs", "entities", "duplicates", "status"])
    ap.add_argument("--k", type=int, default=None)
    ap.add_argument("--min-sim", type=float, default=None)
    ap.add_argument("--min-docs", type=int, default=2)
    a = ap.parse_args()
    if a.command == "docs":
        print(json.dumps(docs(k=a.k or 10,
                              min_sim=a.min_sim if a.min_sim is not None else 0.90),
                         indent=2))
    elif a.command == "entities":
        print(json.dumps(entities(k=a.k or 8,
                                  min_sim=a.min_sim if a.min_sim is not None else 0.80,
                                  min_docs=a.min_docs),
                         ensure_ascii=False, indent=2))
    elif a.command == "duplicates":
        print(json.dumps(duplicates(
            min_sim=a.min_sim if a.min_sim is not None else 0.995),
            ensure_ascii=False, indent=2))
    else:
        print(json.dumps(status(), indent=2))


if __name__ == "__main__":
    main()
