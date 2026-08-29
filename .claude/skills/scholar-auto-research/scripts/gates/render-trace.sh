#!/usr/bin/env bash
# render-trace.sh — render an RAO NDJSON trace to a human-readable markdown
# process log (the file skills used to hand-write). The markdown is now a
# GENERATED VIEW of the trace sink written by emit-trace.sh.
#
# USAGE
#   bash scripts/gates/render-trace.sh <trace.ndjson> [out.md]
#   Default out.md: same dir, `trace-<skill>-<date>.ndjson` -> `process-log-<skill>-<date>.md`.
#
# OUTPUT COLUMNS
#   # | Time | Phase | Agent | Step | Reasoning | Action | Observation | Refs | Status
#
# EXIT CODES
#   0  rendered (prints RENDERED=<path>)
#   1  usage / trace file missing
#   2  python3 unavailable (cannot parse JSON robustly)

set -uo pipefail

TRACE="${1:-}"
OUT="${2:-}"
if [ -z "$TRACE" ] || [ ! -f "$TRACE" ]; then
  echo "Usage: render-trace.sh <trace.ndjson> [out.md]" >&2
  echo "ERROR: trace file not found: ${TRACE:-<none>}" >&2
  exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 required to parse the NDJSON trace" >&2
  exit 2
fi

if [ -z "$OUT" ]; then
  _dir=$(dirname "$TRACE")
  _base=$(basename "$TRACE")
  _base=${_base#trace-}       # strip leading "trace-"
  _base=${_base%.ndjson}      # strip ".ndjson"
  OUT="${_dir}/process-log-${_base}.md"
fi

python3 - "$TRACE" "$OUT" <<'PY'
import json, sys, os
trace, out = sys.argv[1], sys.argv[2]

def cell(v):
    # Markdown-table-safe: escape pipes, drop any stray newlines, blank -> em dash.
    if v is None or v == "":
        return "—"
    s = str(v).replace("\n", " ").replace("|", "\\|").strip()
    return s or "—"

STATUS_SYM = {"ok": "✓", "fail": "✗", "skipped": "SKIPPED"}

rows = []
skill = date = run_id = None
bad = 0
with open(trace) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            r = json.loads(line)
        except Exception:
            bad += 1
            continue
        skill = skill or r.get("skill")
        run_id = run_id or r.get("run_id")
        rows.append(r)

# Sort by seq so the rendered order is deterministic even if lines interleave.
rows.sort(key=lambda r: r.get("seq", 0))

def hhmmss(ts):
    # ISO8601 "YYYY-MM-DDTHH:MM:SSZ" -> "HH:MM:SS"
    if isinstance(ts, str) and "T" in ts:
        return ts.split("T", 1)[1].rstrip("Z")[:8]
    return ts or "—"

with open(out, "w") as w:
    w.write(f"# Process Log: /{skill or '?'}\n")
    w.write(f"- **Run**: {run_id or '—'}\n")
    w.write(f"- **Steps**: {len(rows)}\n")
    w.write("- **Source**: rendered from the RAO trace by `render-trace.sh` (do not hand-edit)\n\n")
    w.write("## Steps\n\n")
    w.write("| # | Time | Phase | Agent | Step | Reasoning | Action | Observation | Refs | Status |\n")
    w.write("|---|------|-------|-------|------|-----------|--------|-------------|------|--------|\n")
    for r in rows:
        refs = r.get("refs") or []
        refs_str = "; ".join(refs) if isinstance(refs, list) else str(refs)
        st = r.get("status", "")
        w.write("| {seq} | {ts} | {phase} | {agent} | {step} | {reasoning} | {action} | {obs} | {refs} | {status} |\n".format(
            seq=r.get("seq", ""),
            ts=hhmmss(r.get("ts")),
            phase=cell(r.get("phase")),
            # RENDER THE agentId ALONGSIDE THE AGENT NAME (audit 2026-08-18).
            # emit-trace.sh writes `agentId` as a STRUCTURED field; render-trace.sh dropped it.
            # trace-coverage checks read the structured NDJSON and could see it, while older
            # rendered-log consumers could not — the same dispatch satisfied one view and
            # failed the other, and the only way a caller
            # could pass both was to duplicate the id into the free-text `action`. One fact, two
            # consumers, two channels, and the structured channel was the invisible one.
            agent=cell(("%s (agentId=%s)" % (r.get("agent"), r.get("agentId")))
                       if r.get("agentId") else r.get("agent")),
            step=cell(r.get("step")),
            reasoning=cell(r.get("reasoning")),
            action=cell(r.get("action")),
            obs=cell(r.get("observation")),
            refs=cell(refs_str),
            status=STATUS_SYM.get(st, cell(st)),
        ))
    if bad:
        w.write(f"\n> WARNING: {bad} malformed NDJSON line(s) were skipped during rendering.\n")

print(f"RENDERED={out}")
print(f"STEPS={len(rows)}")
if bad:
    print(f"MALFORMED_LINES={bad}", file=sys.stderr)
PY
