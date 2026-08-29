#!/usr/bin/env bash
# render-trace-html.sh — render RAO NDJSON trace(s) to a single self-contained
# HTML pipeline view: phases, gate verdicts, agent dispatches, artifact links,
# and a deep link per step into the raw session transcript.
#
# WHY THIS EXISTS, AND WHY IT IS A SEPARATE SCRIPT FROM render-trace.sh
#   render-trace.sh renders the trace to markdown. That markdown is not just a
#   convenience: verify-task-dispatch-provenance.sh GREPS it, so its exact
#   shape is a gate contract. Adding an HTML mode inside that script would put
#   a cosmetic renderer on the same code path as a gate-consumed artifact.
#   This script therefore reads the SAME documented NDJSON schema
#   (_shared/process-logger.md) and writes a different view. The schema is the
#   shared source of truth; neither renderer is upstream of the other.
#
# RELATIONSHIP TO render-session-transcript.sh
#   emit-trace.sh stamps each record with `session_id`. When a rendered raw
#   transcript exists at <proj>/logs/transcript-html/<session_id>/index.html,
#   every step from that session becomes a live link into it. So: scan the
#   phase timeline here, spot the RED gate, click through to the actual tool
#   call that produced it. Steps whose session has not been rendered show the
#   id as inert text plus the command that would render it.
#
# PRIVACY
#   Renders only fields the trace already carries, which C-01 binds to
#   aggregate metrics, verdicts, counts, and file refs. This view therefore
#   inherits the trace's privacy posture and adds no new exposure — unlike the
#   raw transcript, which has its own gate. Output is offline/self-contained
#   (inline CSS+JS, no CDN, no network) so it is safe to open anywhere.
#
# USAGE
#   bash scripts/gates/render-trace-html.sh <trace.ndjson> [more.ndjson ...] [-o out.html]
#   bash scripts/gates/render-trace-html.sh --proj <project_dir> [-o out.html]
#     --proj  discovers every logs/trace-*.ndjson under the project and merges
#             them into one cross-skill timeline (the usual orchestrator case:
#             a paper pipeline leaves one trace per skill per day).
#     -o      default: <proj>/logs/trace-html/index.html, or, for explicit
#             file args, alongside the first trace as trace-view.html.
#
# EXIT CODES
#   0  rendered (prints TRACE_HTML=<path>, STEPS=<n>)
#   1  usage / no trace files found
#   2  python3 unavailable
#
# FIXTURES: tests/smoke/test-session-transcript-html.sh

set -uo pipefail

PROJ="" OUT="" TRACES=()
while [ $# -gt 0 ]; do
  case "$1" in
    --proj)     PROJ="${2:-}"; shift 2 ;;
    -o|--output) OUT="${2:-}"; shift 2 ;;
    -h|--help)  grep -E '^#' "$0" | sed 's/^# *//;s/^#$//'; exit 0 ;;
    -*)         echo "ERROR: unknown flag $1" >&2; exit 1 ;;
    *)          TRACES+=("$1"); shift ;;
  esac
done

if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 required to parse the NDJSON trace" >&2
  exit 2
fi

if [ -n "$PROJ" ]; then
  [ -d "$PROJ" ] || { echo "ERROR: --proj not a directory: $PROJ" >&2; exit 1; }
  for f in "$PROJ"/logs/trace-*.ndjson; do [ -f "$f" ] && TRACES+=("$f"); done
  [ "${#TRACES[@]}" -gt 0 ] || { echo "ERROR: no logs/trace-*.ndjson under $PROJ" >&2; exit 1; }
  OUT="${OUT:-${PROJ}/logs/trace-html/index.html}"
fi

if [ "${#TRACES[@]}" -eq 0 ]; then
  echo "Usage: render-trace-html.sh <trace.ndjson> [...] [-o out.html]" >&2
  echo "       render-trace-html.sh --proj <project_dir> [-o out.html]" >&2
  exit 1
fi
for f in "${TRACES[@]}"; do
  [ -f "$f" ] || { echo "ERROR: trace file not found: $f" >&2; exit 1; }
done

OUT="${OUT:-$(dirname "${TRACES[0]}")/trace-view.html}"
mkdir -p "$(dirname "$OUT")" 2>/dev/null || { echo "ERROR: cannot mkdir $(dirname "$OUT")" >&2; exit 1; }

python3 - "$OUT" "${TRACES[@]}" <<'PY'
import html, json, os, sys
from collections import OrderedDict

out, trace_files = sys.argv[1], sys.argv[2:]
outdir = os.path.dirname(os.path.abspath(out))

rows, bad = [], 0
for tf in trace_files:
    with open(tf) as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                rows.append(json.loads(line))
            except Exception:
                bad += 1

# Order by (date-of-ts, skill, seq). `seq` is per-skill-per-day, so sorting on
# seq alone would interleave two skills' step 1..n incorrectly in a merged view.
rows.sort(key=lambda r: (str(r.get("ts") or ""), str(r.get("skill") or ""), r.get("seq") or 0))

def e(v):
    return html.escape("" if v is None else str(v), quote=True)

def hhmm(ts):
    if isinstance(ts, str) and "T" in ts:
        return ts.split("T", 1)[1].rstrip("Z")[:8]
    return ts or ""

def daypart(ts):
    if isinstance(ts, str) and "T" in ts:
        return ts.split("T", 1)[0]
    return ""

# ── Which sessions have a rendered raw transcript beside us? ────────────────
# outdir is <proj>/logs/trace-html; transcripts land at <proj>/logs/transcript-html.
tx_root = os.path.normpath(os.path.join(outdir, "..", "transcript-html"))
def tx_link(sid):
    if not sid:
        return None
    p = os.path.join(tx_root, sid, "index.html")
    if os.path.isfile(p):
        return os.path.relpath(p, outdir)
    return None

STATUS_CLASS = {"ok": "ok", "fail": "fail", "skipped": "skip"}

# ── Aggregate counters ──────────────────────────────────────────────────────
n_ok = sum(1 for r in rows if r.get("status") == "ok")
n_fail = sum(1 for r in rows if r.get("status") == "fail")
n_skip = sum(1 for r in rows if r.get("status") == "skipped")
skills = sorted({str(r.get("skill") or "?") for r in rows})
phases = list(OrderedDict.fromkeys(str(r.get("phase")) for r in rows if r.get("phase")))
agents = sorted({str(r.get("agent")) for r in rows if r.get("agent") and r.get("agent") != "self"})
sessions = sorted({str(r.get("session_id")) for r in rows if r.get("session_id")})
rendered_sessions = [s for s in sessions if tx_link(s)]

# ── Group into phase sections, preserving first-appearance order ─────────────
groups = OrderedDict()
for r in rows:
    key = str(r.get("phase")) if r.get("phase") else "(unphased)"
    groups.setdefault(key, []).append(r)

CSS = """
:root{--bg:#fbfbfa;--fg:#1a1a19;--mut:#6b6b66;--line:#e3e3df;--card:#fff;
--ok:#1a7f4b;--okbg:#e8f5ee;--fail:#b3261e;--failbg:#fdecea;--skip:#8a6d0b;--skipbg:#fdf6e3;
--acc:#2b5cb8;--code:#f4f4f2;}
@media (prefers-color-scheme:dark){:root{--bg:#16161a;--fg:#e8e8e6;--mut:#9a9a95;--line:#2e2e34;
--card:#1e1e23;--ok:#5fd39a;--okbg:#123023;--fail:#ff8a80;--failbg:#3a1c1a;--skip:#e3c05c;
--skipbg:#332b12;--acc:#7fa8f0;--code:#26262c;}}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--fg);
font:15px/1.55 -apple-system,BlinkMacSystemFont,"Segoe UI",Inter,Roboto,sans-serif;}
.wrap{max-width:1180px;margin:0 auto;padding:28px 20px 80px}
h1{font-size:22px;margin:0 0 4px} h2{font-size:15px;letter-spacing:.04em;text-transform:uppercase;
color:var(--mut);margin:34px 0 12px;padding-bottom:7px;border-bottom:1px solid var(--line)}
.sub{color:var(--mut);font-size:13px;margin-bottom:20px}
.chips{display:flex;flex-wrap:wrap;gap:8px;margin:16px 0 6px}
.chip{font-size:12px;padding:4px 10px;border-radius:20px;background:var(--card);
border:1px solid var(--line);color:var(--mut)}
.chip b{color:var(--fg);font-weight:600}
.chip.ok{background:var(--okbg);border-color:transparent;color:var(--ok)}
.chip.fail{background:var(--failbg);border-color:transparent;color:var(--fail)}
.chip.skip{background:var(--skipbg);border-color:transparent;color:var(--skip)}
.controls{display:flex;flex-wrap:wrap;gap:10px;align-items:center;margin:18px 0 4px;
position:sticky;top:0;background:var(--bg);padding:10px 0;z-index:5;border-bottom:1px solid var(--line)}
.controls input,.controls select{font:inherit;font-size:13px;padding:6px 9px;border:1px solid var(--line);
border-radius:7px;background:var(--card);color:var(--fg)}
.controls input{flex:1;min-width:190px}
.step{background:var(--card);border:1px solid var(--line);border-left:3px solid var(--line);
border-radius:9px;padding:12px 14px;margin-bottom:9px}
.step.ok{border-left-color:var(--ok)} .step.fail{border-left-color:var(--fail)}
.step.skip{border-left-color:var(--skip)}
.hd{display:flex;flex-wrap:wrap;gap:9px;align-items:baseline;margin-bottom:7px}
.seq{font:600 12px ui-monospace,SFMono-Regular,Menlo,monospace;color:var(--mut);min-width:2.2em}
.name{font-weight:650}
.meta{font-size:12px;color:var(--mut)}
.badge{font-size:11px;padding:2px 8px;border-radius:5px;font-weight:600;letter-spacing:.02em}
.badge.ok{background:var(--okbg);color:var(--ok)} .badge.fail{background:var(--failbg);color:var(--fail)}
.badge.skip{background:var(--skipbg);color:var(--skip)}
.rao{display:grid;grid-template-columns:88px 1fr;gap:3px 12px;font-size:13.5px;margin-top:8px}
.rao dt{color:var(--mut);font-size:11px;text-transform:uppercase;letter-spacing:.05em;padding-top:2px}
.rao dd{margin:0;overflow-wrap:anywhere}
.rao dd.mono{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:12.5px;
background:var(--code);padding:3px 7px;border-radius:5px;display:inline-block;max-width:100%}
.refs{margin-top:9px;display:flex;flex-wrap:wrap;gap:6px}
.ref{font:12px ui-monospace,SFMono-Regular,Menlo,monospace;background:var(--code);
padding:2px 8px;border-radius:5px;color:var(--acc);text-decoration:none;border:1px solid transparent}
.ref:hover{border-color:var(--acc)}
a.tx{font-size:11.5px;color:var(--acc);text-decoration:none;border-bottom:1px dotted var(--acc)}
.tx-none{font-size:11.5px;color:var(--mut)}
.empty{color:var(--mut);font-style:italic;padding:22px;text-align:center}
footer{margin-top:44px;padding-top:14px;border-top:1px solid var(--line);color:var(--mut);font-size:12px}
code{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;background:var(--code);
padding:1px 5px;border-radius:4px;font-size:12.5px}
"""

JS = """
(function(){
 var q=document.getElementById('q'),st=document.getElementById('st'),sk=document.getElementById('sk');
 function apply(){
  var t=(q.value||'').toLowerCase(),s=st.value,k=sk.value,shown=0;
  document.querySelectorAll('.step').forEach(function(el){
   var okS=(s==='all'||el.dataset.status===s),
       okK=(k==='all'||el.dataset.skill===k),
       okT=(!t||el.textContent.toLowerCase().indexOf(t)>-1);
   var v=okS&&okK&&okT; el.style.display=v?'':'none'; if(v)shown++;
  });
  document.querySelectorAll('section.phase').forEach(function(sec){
   var any=sec.querySelectorAll('.step:not([style*="none"])').length;
   sec.style.display=any?'':'none';
  });
  document.getElementById('shown').textContent=shown;
 }
 [q,st,sk].forEach(function(el){el.addEventListener('input',apply)});
 apply();
})();
"""

parts = []
parts.append("<!doctype html><html lang='en'><head><meta charset='utf-8'>")
parts.append("<meta name='viewport' content='width=device-width,initial-scale=1'>")
title = "RAO Trace — " + (", ".join(f"/{s}" for s in skills) if skills else "no records")
parts.append(f"<title>{e(title)}</title><style>{CSS}</style></head><body><div class='wrap'>")
parts.append(f"<h1>{e(title)}</h1>")
days = sorted({daypart(r.get("ts")) for r in rows if daypart(r.get("ts"))})
parts.append("<div class='sub'>Rendered from {} trace file(s){}. Source of truth: the NDJSON trace — this page is a generated view, do not hand-edit.</div>".format(
    len(trace_files), (" · " + " → ".join(days)) if days else ""))

parts.append("<div class='chips'>")
parts.append(f"<span class='chip'><b>{len(rows)}</b> steps</span>")
parts.append(f"<span class='chip ok'><b>{n_ok}</b> ok</span>")
if n_fail:
    parts.append(f"<span class='chip fail'><b>{n_fail}</b> fail</span>")
if n_skip:
    parts.append(f"<span class='chip skip'><b>{n_skip}</b> skipped</span>")
if phases:
    parts.append(f"<span class='chip'><b>{len(phases)}</b> phases</span>")
if agents:
    parts.append(f"<span class='chip'><b>{len(agents)}</b> agents</span>")
if sessions:
    parts.append("<span class='chip'><b>{}</b>/{} sessions rendered</span>".format(
        len(rendered_sessions), len(sessions)))
if bad:
    parts.append(f"<span class='chip fail'><b>{bad}</b> malformed line(s) skipped</span>")
parts.append("</div>")

parts.append("<div class='controls'>")
parts.append("<input id='q' type='search' placeholder='Filter steps, reasoning, actions, observations…'>")
parts.append("<select id='st'><option value='all'>All statuses</option><option value='ok'>ok</option>"
             "<option value='fail'>fail</option><option value='skipped'>skipped</option></select>")
opts = "".join(f"<option value='{e(s)}'>{e(s)}</option>" for s in skills)
parts.append(f"<select id='sk'><option value='all'>All skills</option>{opts}</select>")
parts.append("<span class='meta'><span id='shown'>0</span> shown</span>")
parts.append("</div>")

if not rows:
    parts.append("<div class='empty'>No trace records found.</div>")

for phase, items in groups.items():
    pf = sum(1 for r in items if r.get("status") == "fail")
    hdr = f"{e(phase)} <span class='meta'>· {len(items)} step(s)"
    hdr += f" · <span style='color:var(--fail)'>{pf} failed</span>" if pf else ""
    hdr += "</span>"
    parts.append(f"<section class='phase'><h2>{hdr}</h2>")
    for r in items:
        st = str(r.get("status") or "")
        cls = STATUS_CLASS.get(st, "")
        sid = str(r.get("session_id") or "")
        parts.append("<div class='step {c}' data-status='{s}' data-skill='{k}'>".format(
            c=cls, s=e(st), k=e(r.get("skill") or "?")))
        parts.append("<div class='hd'>")
        parts.append(f"<span class='seq'>#{e(r.get('seq'))}</span>")
        parts.append(f"<span class='name'>{e(r.get('step'))}</span>")
        if st:
            parts.append(f"<span class='badge {cls}'>{e(st)}</span>")
        bits = [f"/{r.get('skill')}"]
        if r.get("ts"):
            bits.append(hhmm(r.get("ts")))
        ag = r.get("agent")
        if ag and ag != "self":
            bits.append(f"agent: {ag}" + (f" ({r.get('agentId')})" if r.get("agentId") else ""))
        parts.append(f"<span class='meta'>{e(' · '.join(str(b) for b in bits))}</span>")
        link = tx_link(sid)
        if link:
            parts.append(f"<a class='tx' href='{e(link)}' title='Open the raw session transcript for this step'>raw transcript ↗</a>")
        elif sid:
            parts.append(f"<span class='tx-none' title='Render it with: render-session-transcript.sh --session {e(sid)}'>session {e(sid[:8])} (not rendered)</span>")
        parts.append("</div>")

        parts.append("<dl class='rao'>")
        for label, key, mono in (("Reasoning", "reasoning", False),
                                 ("Action", "action", True),
                                 ("Observation", "observation", False)):
            v = r.get(key)
            if v:
                dd = f"<dd class='mono'>{e(v)}</dd>" if mono else f"<dd>{e(v)}</dd>"
                parts.append(f"<dt>{label}</dt>{dd}")
        parts.append("</dl>")

        refs = r.get("refs") or []
        if isinstance(refs, list) and refs:
            parts.append("<div class='refs'>")
            for ref in refs:
                # Link relative to the project root (two levels up from logs/trace-html/).
                parts.append("<a class='ref' href='{h}'>{t}</a>".format(
                    h=e(os.path.join("..", "..", str(ref))), t=e(ref)))
            parts.append("</div>")
        parts.append("</div>")
    parts.append("</section>")

parts.append("<footer>Generated by <code>render-trace-html.sh</code> from the RAO trace "
             "(<code>_shared/process-logger.md</code>). Steps carry aggregate metrics, verdicts and "
             "file refs only (C-01) — the raw session transcript, linked per step where rendered, "
             "does not, and has its own safety gate in <code>render-session-transcript.sh</code>.</footer>")
parts.append(f"</div><script>{JS}</script></body></html>")

with open(out, "w") as w:
    w.write("\n".join(parts))

print(f"TRACE_HTML={out}")
print(f"STEPS={len(rows)}")
if bad:
    print(f"MALFORMED_LINES={bad}", file=sys.stderr)
PY
