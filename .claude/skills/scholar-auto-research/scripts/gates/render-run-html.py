#!/usr/bin/env python3
"""render-run-html.py — render run-model.json to one self-contained HTML page.

A pure function of the model: this script never walks the project. Everything
it shows was normalized by build-run-model.py. Output is offline/self-contained
(inline CSS+JS, no CDN, no fetch) so it opens anywhere, including from a
cloud-synced folder.

LAYOUT ON DISK
    <proj>/logs/run-html/index.html          <- this page
    <proj>/logs/transcript-html/<sid>/       <- raw transcripts (deep-linked)
    <proj>/<artifact paths>                  <- linked as ../../<relpath>

PRIVACY
    Renders only what the model carries. Artifacts whose safety status is not
    CLEARED arrive with previewable=false and are shown as a name plus a status
    chip — never a link that would inline restricted values.

USAGE
    python3 render-run-html.py <run-model.json> [-o out.html]
"""

import argparse
import html
import json
import os
import sys

STATUS_ORDER = ["completed", "current", "halted", "stale", "excused",
                "undeclared", "pending"]


def e(v):
    return html.escape("" if v is None else str(v), quote=True)


def hhmm(ts):
    if isinstance(ts, str) and "T" in ts:
        return ts.split("T", 1)[1].rstrip("Z")[:8]
    return ts or ""


CSS = """
/* Theme: yongjunzhang.com/vibe-researching. Chrome and type are lifted from
   that site's stylesheet (assets/css/main.css) so a published run view sits
   beside the rest of the site without looking foreign:
     brand/links #a84a22 · body ink #504942 · surface tint #f3f2f1
     note wash #f7ece2 · hairlines #e2e2e2 / #c2bdb7
     UI font -apple-system stack · Georgia for prose · Monaco for code
   The site ships light-only; the dark values below are derived warm-neutrals
   on the same hue family, not a cold inversion. */
:root{--bg:#fff;--tint:#f3f2f1;--fg:#504942;--fg-strong:#2f2a25;--mut:#857a6e;
--mut-2:#a49b92;--line:#e2e2e2;--line-2:#c2bdb7;--card:#fafafa;--code:#f3f2f1;
--brand:#a84a22;--brand-2:#8a5a34;--wash:#f7ece2;
--ok:#0f7a34;--okbg:#eaf4ec;--fail:#a3231f;--failbg:#fbeae6;
--skip:#8a5a34;--skipbg:#f7ece2;--cur:#1e6f8c;--curbg:#e8f1f5;--mutbg:#f3f2f1;
--acc:#a84a22;--purple:#6b3fa0;--purplebg:#f0e9f8;
--ui:-apple-system,".SFNSText-Regular","San Francisco","Roboto","Segoe UI","Helvetica Neue","Lucida Grande",Arial,sans-serif;
--mono:Monaco,Consolas,"Lucida Console",monospace;
--serif:Georgia,Times,serif;}
@media (prefers-color-scheme:dark){:root:where(:not([data-theme="light"])){
--bg:#141210;--tint:#1c1a18;--fg:#ede7e0;--fg-strong:#fff;--mut:#a49b92;--mut-2:#857a6e;
--line:#332e28;--line-2:#443c34;--card:#1c1a18;--code:#232019;--brand:#e08b5f;--brand-2:#c8956a;
--wash:#2a211a;--ok:#5fc27e;--okbg:#16301f;--fail:#f08b7f;--failbg:#33191a;
--skip:#d0a06a;--skipbg:#2a211a;--cur:#6fb6d4;--curbg:#15262e;--mutbg:#232019;--acc:#e08b5f;
--purple:#c4a2f0;--purplebg:#2a1f3d;}}
:root[data-theme="dark"]{--bg:#141210;--tint:#1c1a18;--fg:#ede7e0;--fg-strong:#fff;--mut:#a49b92;
--mut-2:#857a6e;--line:#332e28;--line-2:#443c34;--card:#1c1a18;--code:#232019;--brand:#e08b5f;
--brand-2:#c8956a;--wash:#2a211a;--ok:#5fc27e;--okbg:#16301f;--fail:#f08b7f;--failbg:#33191a;
--skip:#d0a06a;--skipbg:#2a211a;--cur:#6fb6d4;--curbg:#15262e;--mutbg:#232019;--acc:#e08b5f;
--purple:#c4a2f0;--purplebg:#2a1f3d;}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--fg);font:16px/1.5 var(--ui)}
.wrap{max-width:1240px;margin:0 auto;padding:26px 20px 90px}
h1{font-size:1.563em;margin:0 0 3px;color:var(--fg-strong);font-weight:650}
h2{font-size:12px;letter-spacing:.08em;text-transform:uppercase;color:var(--brand);
margin:34px 0 12px;padding-bottom:7px;border-bottom:1px solid var(--line);font-weight:700}
.sub{color:var(--mut);font-size:13.5px;margin-bottom:14px}
.chips{display:flex;flex-wrap:wrap;gap:7px;margin:12px 0}
.chip{font-size:12px;padding:4px 10px;border-radius:20px;background:var(--card);
border:1px solid var(--line);color:var(--mut);white-space:nowrap}
.chip b{color:var(--fg-strong);font-weight:650}
.chip.ok{background:var(--okbg);border-color:transparent;color:var(--ok)}
.chip.fail{background:var(--failbg);border-color:transparent;color:var(--fail)}
.chip.warn{background:var(--skipbg);border-color:transparent;color:var(--skip)}
.chip.cur{background:var(--curbg);border-color:transparent;color:var(--cur)}
.chip.pur{background:var(--purplebg);border-color:transparent;color:var(--purple)}
.banner{border:1px solid var(--line);border-left:3px solid var(--brand);background:var(--wash);
border-radius:0 6px 6px 0;padding:.7em 1em;margin:14px 0;font-size:13.5px}
.banner h3{margin:0 0 6px;font-size:.72em;letter-spacing:.08em;text-transform:uppercase;
color:var(--brand);font-weight:700}
.banner ul{margin:0;padding-left:18px} .banner li{margin:2px 0}
nav.tabs{display:flex;gap:2px;flex-wrap:wrap;border-bottom:1px solid var(--line);
margin:20px 0 0;position:sticky;top:0;background:var(--bg);z-index:20;padding-top:6px}
nav.tabs button{font:inherit;font-size:13.5px;padding:9px 15px;border:0;background:none;
color:var(--mut);cursor:pointer;border-bottom:2px solid transparent;margin-bottom:-1px}
nav.tabs button[aria-selected=true]{color:var(--brand);border-bottom-color:var(--brand);font-weight:700}
nav.tabs button .n{font-size:11px;opacity:.65;margin-left:5px}
section.panel{display:none;padding-top:18px} section.panel.on{display:block}
.toolbar{display:flex;gap:9px;flex-wrap:wrap;margin-bottom:14px;align-items:center}
.toolbar input,.toolbar select{font:inherit;font-size:13px;padding:6px 9px;border:1px solid var(--line-2);
border-radius:7px;background:var(--bg);color:var(--fg)} .toolbar input{flex:1;min-width:200px}
.qf{font:inherit;font-size:12px;padding:5px 11px;border:1px solid var(--line-2);border-radius:20px;
background:var(--bg);color:var(--mut);cursor:pointer}
.qf[aria-pressed=true]{background:var(--wash);border-color:var(--brand);color:var(--brand);font-weight:650}
.spine{position:relative;padding-left:74px}
.spine svg.arcs{position:absolute;left:0;top:0;width:74px;height:100%;overflow:visible;pointer-events:none}
.ph{background:var(--card);border:1px solid var(--line);border-left:3px solid var(--line-2);
border-radius:10px;margin-bottom:7px;position:relative;transition:opacity .12s}
.ph.completed{border-left-color:var(--ok)} .ph.current{border-left-color:var(--cur)}
.ph.halted,.ph.undeclared{border-left-color:var(--fail)}
.ph.excused,.ph.stale{border-left-color:var(--skip)} .ph.pending{opacity:.62}
.dim{opacity:.15}
.ph>summary{cursor:pointer;list-style:none;padding:11px 14px;display:flex;gap:10px;
align-items:baseline;flex-wrap:wrap}
.ph>summary::-webkit-details-marker{display:none}
.ph>summary:hover{background:var(--tint);border-radius:9px}
.pid{font:700 12.5px var(--mono);min-width:44px;color:var(--mut)}
.plab{font-weight:650;flex:1;min-width:150px;color:var(--fg-strong)}
.badge{font-size:11px;padding:2px 8px;border-radius:5px;font-weight:650;white-space:nowrap}
.b-completed{background:var(--okbg);color:var(--ok)} .b-current{background:var(--curbg);color:var(--cur)}
.b-halted,.b-undeclared{background:var(--failbg);color:var(--fail)}
.b-excused,.b-stale{background:var(--skipbg);color:var(--skip)}
.b-pending{background:var(--mutbg);color:var(--mut)}
.meta{font-size:12px;color:var(--mut)}
.body{padding:2px 14px 14px 14px;border-top:1px solid var(--line);margin-top:2px}
.kv{display:grid;grid-template-columns:132px 1fr;gap:3px 12px;font-size:13.5px;margin:9px 0}
.kv dt{color:var(--mut);font-size:11px;text-transform:uppercase;letter-spacing:.06em;padding-top:3px}
.kv dd{margin:0;overflow-wrap:anywhere}
h4{font-size:11px;text-transform:uppercase;letter-spacing:.06em;color:var(--mut);
margin:15px 0 7px;border-bottom:1px solid var(--line);padding-bottom:4px;font-weight:700}
.step{background:var(--tint);border-radius:8px;padding:9px 11px;margin-bottom:6px;font-size:13.5px}
.step.fail{background:var(--failbg)} .step.skipped{background:var(--skipbg)}
.step .hd{display:flex;gap:8px;align-items:baseline;flex-wrap:wrap;margin-bottom:4px}
.step .sname{font-weight:650;color:var(--fg-strong)}
.rao{display:grid;grid-template-columns:82px 1fr;gap:2px 10px;font-size:13px}
.rao dt{color:var(--mut);font-size:10px;text-transform:uppercase;letter-spacing:.06em;padding-top:2px}
.rao dd{margin:0;overflow-wrap:anywhere}
.mono{font-family:var(--mono);font-size:12px;background:var(--code);padding:2px 6px;
border-radius:4px;display:inline-block;max-width:100%}
table{width:100%;border-collapse:collapse;font-size:13.5px}
th{text-align:left;font-size:11px;text-transform:uppercase;letter-spacing:.06em;color:var(--mut);
border-bottom:1px solid var(--line-2);padding:7px 9px;font-weight:700}
td{padding:7px 9px;border-bottom:1px solid var(--line);vertical-align:top;overflow-wrap:anywhere}
tr:hover td{background:var(--tint)}
.scroll{overflow-x:auto;-webkit-overflow-scrolling:touch}
a{color:var(--brand)} a.art{text-decoration:none;font-family:var(--mono);font-size:12.5px}
a.art:hover{text-decoration:underline}
.locked{color:var(--mut);font-family:var(--mono);font-size:12.5px}
a.tx{font-size:11.5px;color:var(--brand);text-decoration:none;border-bottom:1px dotted var(--brand)}
.tx-none{font-size:11.5px;color:var(--mut)}
pre{background:var(--code);padding:10px 12px;border-radius:7px;overflow-x:auto;
font-size:12px;line-height:1.45;margin:6px 0;font-family:var(--mono)}
.empty{color:var(--mut);font-style:italic;padding:26px;text-align:center}
footer{margin-top:44px;padding-top:14px;border-top:1px solid var(--line);color:var(--mut);font-size:12px}
code{font-family:var(--mono);background:var(--code);padding:1px 5px;border-radius:4px;font-size:12.5px}
.grp{font-size:11px;padding:1px 7px;border-radius:4px;background:var(--mutbg);color:var(--mut)}
.prose{max-width:74ch;font-family:var(--serif);font-size:16px;line-height:1.62;color:var(--fg)}
.prose h3,.prose h4,.prose h5,.prose h6{margin:20px 0 7px;font-size:1em;color:var(--fg-strong);
font-family:var(--ui);text-transform:none;letter-spacing:0;border:0;padding:0;font-weight:650}
.prose p{margin:0 0 11px} .prose ul{margin:0 0 11px;padding-left:20px} .prose li{margin:3px 0}
.prose pre{white-space:pre-wrap;font-size:12.5px}
.prose code{font-size:.85em}
"""

JS = r"""
(function(){
  // ── tabs ──
  var tabs=[].slice.call(document.querySelectorAll('nav.tabs button'));
  function show(id){
    tabs.forEach(function(t){var on=t.dataset.tab===id;t.setAttribute('aria-selected',on?'true':'false');});
    [].forEach.call(document.querySelectorAll('section.panel'),function(p){p.classList.toggle('on',p.id===id);});
    if(id==='spine') requestAnimationFrame(drawArcs);
  }
  tabs.forEach(function(t){t.addEventListener('click',function(){show(t.dataset.tab);});});

  // ── filters ──
  // Text search DIMS rather than hides (as dsh-trace-compare does): a
  // non-matching phase still shows you where the match sits in the run.
  // Status and quick filters DO hide — those are deliberate narrowing.
  var TROUBLE={halted:1,undeclared:1}, WAIVED={excused:1,stale:1};
  var NEVER={never:1};
  [].forEach.call(document.querySelectorAll('[data-filters]'),function(tb){
    var panel=tb.closest('section.panel');
    var q=tb.querySelector('input'), sel=tb.querySelector('select');
    var qfs=[].slice.call(tb.querySelectorAll('.qf'));
    function apply(){
      var t=(q&&q.value||'').toLowerCase(), s=sel?sel.value:'all', n=0, on={};
      qfs.forEach(function(b){if(b.getAttribute('aria-pressed')==='true')on[b.dataset.qf]=1;});
      [].forEach.call(panel.querySelectorAll('[data-row]'),function(r){
        var st=r.dataset.status||'';
        var vis=(s==='all'||st===s);
        if(vis&&on.trouble) vis=!!TROUBLE[st]||r.querySelector('.step.fail')!==null;
        if(vis&&on.waived)  vis=!!WAIVED[st];
        if(vis&&on.never)   vis=!!NEVER[st];
        r.style.display=vis?'':'none';
        var match=(!t||r.textContent.toLowerCase().indexOf(t)>-1);
        r.classList.toggle('dim', vis&&!match);
        if(vis&&match)n++;
      });
      var c=tb.querySelector('.count'); if(c)c.textContent=n;
      if(panel.id==='spine') requestAnimationFrame(drawArcs);
    }
    if(q)q.addEventListener('input',apply); if(sel)sel.addEventListener('change',apply);
    qfs.forEach(function(b){b.addEventListener('click',function(){
      b.setAttribute('aria-pressed',b.getAttribute('aria-pressed')==='true'?'false':'true');
      apply();
    });});
    apply();
  });

  // ── route-back arcs ──
  // Drawn after layout because phase rows have variable height; the badges in
  // each row are the accessible fallback and are always present.
  function drawArcs(){
    var svg=document.getElementById('arcs'); if(!svg)return;
    var spine=document.getElementById('spineList'); if(!spine)return;
    while(svg.firstChild)svg.removeChild(svg.firstChild);
    var arcs=[];try{arcs=JSON.parse(svg.dataset.arcs||'[]');}catch(err){return;}
    if(!arcs.length)return;
    var base=spine.getBoundingClientRect();
    svg.setAttribute('height',spine.offsetHeight);
    var NS='http://www.w3.org/2000/svg';
    function y(pid){
      var el=spine.querySelector('[data-pid="'+CSS.escape(pid)+'"]');
      if(!el||el.style.display==='none')return null;
      var r=el.getBoundingClientRect();
      return r.top-base.top+Math.min(22,r.height/2);
    }
    arcs.forEach(function(a,i){
      var y1=y(a.from), y2=y(a.to); if(y1===null||y2===null)return;
      var lane=62-(i%4)*13;
      var p=document.createElementNS(NS,'path');
      p.setAttribute('d','M '+lane+' '+y1+' C '+(lane-26)+' '+y1+', '+(lane-26)+' '+y2+', '+lane+' '+y2);
      p.setAttribute('fill','none'); p.setAttribute('stroke','var(--fail)');
      p.setAttribute('stroke-width','1.6'); p.setAttribute('opacity','.75');
      svg.appendChild(p);
      var head=document.createElementNS(NS,'path');
      head.setAttribute('d','M '+lane+' '+y2+' l -5 -4 l 0 8 z');
      head.setAttribute('fill','var(--fail)'); head.setAttribute('opacity','.85');
      svg.appendChild(head);
    });
  }
  [].forEach.call(document.querySelectorAll('details.ph'),function(d){
    d.addEventListener('toggle',function(){requestAnimationFrame(drawArcs);});
  });
  window.addEventListener('resize',function(){requestAnimationFrame(drawArcs);});

  // ── shared tooltip for every chart mark (interaction is not optional) ──
  var tip=document.getElementById('tip');
  document.addEventListener('mouseover',function(ev){
    var t=ev.target.closest('[data-tip]'); if(!t||!tip)return;
    tip.textContent=t.getAttribute('data-tip'); tip.style.opacity='1';
  });
  document.addEventListener('mousemove',function(ev){
    if(!tip||tip.style.opacity!=='1')return;
    var x=ev.clientX+14,y=ev.clientY+14;
    var r=tip.getBoundingClientRect();
    if(x+r.width>innerWidth-8)x=ev.clientX-r.width-14;
    if(y+r.height>innerHeight-8)y=ev.clientY-r.height-14;
    tip.style.left=x+'px'; tip.style.top=y+'px';
  });
  document.addEventListener('mouseout',function(ev){
    if(ev.target.closest('[data-tip]')&&tip)tip.style.opacity='0';
  });
  // Export a chart as standalone SVG, for a slide or a paper figure. CSS vars
  // are resolved to literal colours first — outside this page they do not exist.
  [].forEach.call(document.querySelectorAll('.card .exp'),function(btn){
    btn.addEventListener('click',function(){
      var card=btn.closest('.card'), svg=card.querySelector('svg');
      if(!svg)return;
      var cs=getComputedStyle(svg), clone=svg.cloneNode(true);
      [].forEach.call(clone.querySelectorAll('*'),function(el){
        ['fill','stroke'].forEach(function(prop){
          var v=el.getAttribute(prop);
          if(v&&v.indexOf('var(')===0){
            var lit=cs.getPropertyValue(v.slice(4,-1).trim());
            if(lit)el.setAttribute(prop,lit.trim());
          }
        });
        if(el.tagName==='text'&&!el.getAttribute('fill'))
          el.setAttribute('fill',(cs.getPropertyValue('--ink-mut')||'#857a6e').trim());
      });
      clone.setAttribute('xmlns','http://www.w3.org/2000/svg');
      var nm=((card.querySelector('h3')||{}).textContent||'chart')
               .replace(/[^a-z0-9]+/gi,'-').toLowerCase();
      var blob=new Blob(['<?xml version="1.0" encoding="UTF-8"?>\n'+clone.outerHTML],
                        {type:'image/svg+xml'});
      var a=document.createElement('a');
      a.href=URL.createObjectURL(blob); a.download=nm+'.svg'; a.click();
      setTimeout(function(){URL.revokeObjectURL(a.href);},1500);
    });
  });

  show('overview');
})();
"""


def chip(label, value, cls=""):
    return f"<span class='chip {cls}'><b>{e(value)}</b> {e(label)}</span>"


def render_steps(steps, rel_tx):
    if not steps:
        return ""
    out = ["<h4>RAO steps</h4>"]
    for s in steps:
        st = str(s.get("status") or "")
        out.append(f"<div class='step {e(st)}'><div class='hd'>")
        out.append(f"<span class='mono'>#{e(s.get('seq'))}</span>")
        out.append(f"<span class='sname'>{e(s.get('step'))}</span>")
        if st:
            out.append(f"<span class='badge b-{'completed' if st=='ok' else 'halted' if st=='fail' else 'excused'}'>{e(st)}</span>")
        bits = [f"/{s.get('skill')}"]
        if s.get("ts"):
            bits.append(hhmm(s.get("ts")))
        ag = s.get("agent")
        if ag and ag != "self":
            bits.append(f"agent: {ag}" + (f" ({s.get('agentId')})" if s.get("agentId") else ""))
        out.append(f"<span class='meta'>{e(' · '.join(str(b) for b in bits))}</span>")
        sid = s.get("session_id")
        if sid and rel_tx.get(sid):
            out.append(f"<a href='{e(rel_tx[sid])}' title='raw session transcript'>raw ↗</a>")
        out.append("</div><dl class='rao'>")
        for lab, key, mono in (("Reasoning", "reasoning", False), ("Action", "action", True),
                               ("Observation", "observation", False)):
            v = s.get(key)
            if v:
                dd = f"<dd><span class='mono'>{e(v)}</span></dd>" if mono else f"<dd>{e(v)}</dd>"
                out.append(f"<dt>{lab}</dt>{dd}")
        out.append("</dl>")
        refs = s.get("refs") or []
        if refs:
            out.append("<div style='margin-top:6px'>" + " ".join(
                f"<a class='art' href='{e(os.path.join('..','..',str(r)))}'>{e(r)}</a>" for r in refs) + "</div>")
        out.append("</div>")
    return "".join(out)




# ═══════════════════════════════════════════════════════════════════════════
# Charts — hand-built inline SVG. No chart library, because the page must be
# self-contained under a strict CSP (Artifact hosting, air-gapped viewing) and
# a CDN <script> would break it.
#
# PALETTE PROVENANCE. The chart scales are derived from the site brand
# (#a84a22, yongjunzhang.com) and were run through the dataviz validator
# (scripts/validate_palette.js) in BOTH modes before being written down:
#
#   severity ordinal ramp  light #fd9a73,#e27e57,#c5643d,#a84a22,#8c3000
#                          dark  #ffb79c,#f3936d,#d67854,#b95e3a,#9d4520
#                          -> ALL CHECKS PASS both modes (monotone L, gaps
#                             >= 0.06, light end 2.09:1 / 2.73:1, hue spread
#                             1 deg). Step 4 IS the brand hex.
#   ok/failed pair         light #10938b teal / #b0522a rust
#                          dark  #2fa59b teal / #c86740 rust
#                          -> ALL CHECKS PASS both modes (CVD dE 12.4 / 11.9,
#                             normal-vision 23.1 / 22.9, both >= 3:1)
#
# Two rejected attempts, both instructive:
#   1. The four STATUS colours fail as adjacent stacked segments — serious
#      #ec835a vs warning #fab219 is normal-vision dE 13.6, under the 15
#      floor. Phase status is therefore KPI tiles + a meter, and severity uses
#      an ordered one-hue ramp, the right form for an ordered scale anyway.
#   2. A first brand ramp clipped the sRGB gamut at its light end, squeezing
#      two dark-mode steps to dL 0.05. Fixed by fitting chroma per step rather
#      than holding it constant.
#
# Re-colouring these means re-running the validator; the smoke test pins these
# hexes and asserts no status hue is ever used as a chart fill.

VIZ_CSS = """
.viz{--surface-1:#fff;--page:#f3f2f1;--ink:#2f2a25;--ink-2:#504942;--ink-mut:#857a6e;
--grid:#ececea;--axis:#c2bdb7;--ring:rgba(80,73,66,.10);
--s1:#fd9a73;--s2:#e27e57;--s3:#c5643d;--s4:#a84a22;--s5:#8c3000;
--ok:#10938b;--bad:#b0522a;--good:#0f7a34;--warn:#c8873a;--serious:#b5643c;--crit:#a3231f;}
@media (prefers-color-scheme:dark){:root:where(:not([data-theme="light"])) .viz{
--surface-1:#1c1a18;--page:#141210;--ink:#fff;--ink-2:#ede7e0;--ink-mut:#a49b92;
--grid:#2a2622;--axis:#443c34;--ring:rgba(255,255,255,.10);
--s1:#ffb79c;--s2:#f3936d;--s3:#d67854;--s4:#b95e3a;--s5:#9d4520;
--ok:#2fa59b;--bad:#c86740;--good:#5fc27e;--crit:#f08b7f;}}
:root[data-theme="dark"] .viz{--surface-1:#1c1a18;--page:#141210;--ink:#fff;--ink-2:#ede7e0;
--ink-mut:#a49b92;--grid:#2a2622;--axis:#443c34;--ring:rgba(255,255,255,.10);
--s1:#ffb79c;--s2:#f3936d;--s3:#d67854;--s4:#b95e3a;--s5:#9d4520;
--ok:#2fa59b;--bad:#c86740;--good:#5fc27e;--crit:#f08b7f;}
.kpis{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:10px;margin:16px 0}
.kpi{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:13px 15px}
.kpi .lab{font-size:.72em;color:var(--mut);letter-spacing:.08em;text-transform:uppercase;font-weight:700}
.kpi .val{font-size:27px;font-weight:650;line-height:1.15;margin-top:5px;color:var(--fg-strong)}
.kpi .sub{font-size:11.5px;color:var(--mut);margin-top:2px;display:flex;align-items:center;gap:5px}
.kpi .dot{width:9px;height:9px;border-radius:50%;flex:none}
.meter{height:9px;border-radius:5px;background:var(--mutbg);overflow:hidden;margin-top:9px}
.meter>i{display:block;height:100%;border-radius:5px;background:var(--brand)}
.cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(340px,1fr));gap:14px}
.card{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:15px 16px;
transition:box-shadow .15s ease,border-color .15s ease}
.card:hover{box-shadow:0 4px 14px rgba(0,0,0,.10);border-color:var(--brand)}
.card h3{margin:0;font-size:1.05em;font-weight:650;color:var(--fg-strong)}
.card .cap{font-size:.85em;color:var(--mut);margin:2px 0 12px;line-height:1.45}
.card .exp{float:right;font-size:11px;color:var(--mut);background:none;border:1px solid var(--line-2);
border-radius:5px;padding:2px 7px;cursor:pointer;font-family:var(--ui)}
.card .exp:hover{border-color:var(--brand);color:var(--brand)}
.lg{display:flex;flex-wrap:wrap;gap:11px;margin-top:10px;font-size:11.5px;color:var(--mut)}
.lg span{display:flex;align-items:center;gap:5px}
.lg i{width:10px;height:10px;border-radius:2px;display:block}
.viz svg{display:block;width:100%;height:auto;overflow:visible}
.viz .gl{stroke:var(--grid);stroke-width:1}
.viz .ax{stroke:var(--axis);stroke-width:1}
.viz text{fill:var(--mut);font:11px var(--ui)}
.viz text.v{fill:var(--fg-strong);font-weight:650}
.viz .mk{cursor:pointer}
.viz .mk:hover{opacity:.82}
#tip{position:fixed;z-index:99;pointer-events:none;background:var(--fg-strong);color:var(--bg);
padding:6px 9px;border-radius:6px;font:12px var(--ui);opacity:0;transition:opacity .1s;
white-space:pre;box-shadow:0 2px 10px rgba(0,0,0,.25);max-width:300px}
"""

SEV_ORDER = ["CRITICAL", "MAJOR", "MODERATE", "MINOR", "ADVISORY"]
SEV_VAR = {"CRITICAL": "--s5", "MAJOR": "--s4", "MODERATE": "--s3",
           "MINOR": "--s2", "ADVISORY": "--s1"}


def _tip(text):
    """data-tip drives the single shared tooltip; every mark carries one."""
    return " class='mk' data-tip=\"%s\"" % e(text).replace("\n", "&#10;")


def chart_severity(rows):
    """Findings by review dimension, split by severity.

    Ordered scale -> ordinal one-hue ramp (NOT status colours: see the module
    note). Horizontal stacked bar because dimension names are long.
    """
    if not rows:
        return ""
    rows = sorted(rows, key=lambda r: -sum(r.get(k, 0) for k in SEV_ORDER))[:10]
    mx = max(sum(r.get(k, 0) for k in SEV_ORDER) for r in rows) or 1
    LBL, BAR, GAP, PAD = 132, 20, 13, 46
    H = len(rows) * (BAR + GAP) + 26
    W, PLOT = 560, 560 - LBL - PAD
    o = [f"<svg viewBox='0 0 {W} {H}' role='img' aria-label='Findings by dimension and severity'>"]
    for gi in range(5):                                    # recessive hairline grid
        gx = LBL + PLOT * gi / 4
        o.append(f"<line class='gl' x1='{gx:.1f}' y1='0' x2='{gx:.1f}' y2='{H-22}'/>")
        o.append(f"<text x='{gx:.1f}' y='{H-8}' text-anchor='middle'>{round(mx*gi/4)}</text>")
    for i, r in enumerate(rows):
        y = i * (BAR + GAP)
        name = r["dimension"]
        o.append(f"<text x='{LBL-9}' y='{y+BAR*0.72:.1f}' text-anchor='end'>"
                 f"{e(name[:20])}</text>")
        x = LBL
        tot = sum(r.get(k, 0) for k in SEV_ORDER)
        for k in SEV_ORDER:
            v = r.get(k, 0)
            if not v:
                continue
            w = PLOT * v / mx
            # 2px surface gap between touching segments; the gap does the
            # separating, not a stroke.
            tooltip = _tip(f"{name}\n{k}: {v}")
            o.append(f"<rect x='{x:.1f}' y='{y}' width='{max(w-2,1):.1f}' height='{BAR}' "
                     f"rx='2' fill='var({SEV_VAR[k]})'{tooltip}/>")
            x += w
        if tot:
            o.append(f"<text class='v' x='{x+7:.1f}' y='{y+BAR*0.72:.1f}'>{tot}</text>")
    o.append("</svg>")
    lg = "".join(f"<span><i style='background:var({SEV_VAR[k]})'></i>{k.title()}</span>"
                 for k in SEV_ORDER)
    return "".join(o) + f"<div class='lg'>{lg}</div>"


def chart_steps(rows):
    """Trace steps per phase, failures emphasised.

    Emphasis form: the failing portion is the story, so it takes the critical
    hue and everything else recedes to one blue. Two series -> legend present.
    """
    if not rows:
        return ""
    rows = rows[:16]
    mx = max(r["total"] for r in rows) or 1
    BAR, GAP, TOP = 22, 11, 8
    LBL, PAD, W = 62, 40, 560
    PLOT = W - LBL - PAD
    H = len(rows) * (BAR + GAP) + TOP + 20
    o = [f"<svg viewBox='0 0 {W} {H}' role='img' aria-label='Trace steps per phase'>"]
    for gi in range(5):
        gx = LBL + PLOT * gi / 4
        o.append(f"<line class='gl' x1='{gx:.1f}' y1='0' x2='{gx:.1f}' y2='{H-18}'/>")
        o.append(f"<text x='{gx:.1f}' y='{H-4}' text-anchor='middle'>{round(mx*gi/4)}</text>")
    for i, r in enumerate(rows):
        y = TOP + i * (BAR + GAP)
        o.append(f"<text x='{LBL-9}' y='{y+BAR*0.72:.1f}' text-anchor='end'>{e(r['phase'])}</text>")
        x = LBL
        for key, var, lab in (("ok", "--ok", "ok"), ("skipped", "--s1", "skipped"),
                              ("fail", "--bad", "failed")):
            v = r.get(key, 0)
            if not v:
                continue
            w = PLOT * v / mx
            tip = _tip("Phase %s\n%s: %d" % (r["phase"], lab, v))
            o.append(f"<rect x='{x:.1f}' y='{y}' width='{max(w-2,1):.1f}' height='{BAR}' "
                     f"rx='2' fill='var({var})'{tip}/>")
            x += w
        o.append(f"<text class='v' x='{x+7:.1f}' y='{y+BAR*0.72:.1f}'>{r['total']}</text>")
    o.append("</svg>")
    return "".join(o) + ("<div class='lg'>"
        "<span><i style='background:var(--ok)'></i>ok</span>"
        "<span><i style='background:var(--s1)'></i>skipped</span>"
        "<span><i style='background:var(--bad)'></i>failed</span></div>")


def chart_locks(rows):
    """Lock generations over time: how much churned at each relock.

    Single series -> sequential hue, and NO legend box (the title names it).
    """
    if not rows:
        return ""
    rows = rows[-14:]
    mx = max(max(r["diff_lines"], r["n_files"]) for r in rows) or 1
    W, H, PAD_L, PAD_B, TOP = 560, 190, 34, 40, 10
    n = len(rows)
    slot = (W - PAD_L - 12) / n
    bw = min(24, slot * 0.55)                              # cap bar thickness at 24px
    base = H - PAD_B
    o = [f"<svg viewBox='0 0 {W} {H}' role='img' aria-label='Lock generation churn'>"]
    for gi in range(5):
        gy = TOP + (base - TOP) * gi / 4
        val = round(mx * (4 - gi) / 4)
        o.append(f"<line class='gl' x1='{PAD_L}' y1='{gy:.1f}' x2='{W-6}' y2='{gy:.1f}'/>")
        o.append(f"<text x='{PAD_L-7}' y='{gy+3.5:.1f}' text-anchor='end'>{val}</text>")
    o.append(f"<line class='ax' x1='{PAD_L}' y1='{base}' x2='{W-6}' y2='{base}'/>")
    for i, r in enumerate(rows):
        cx = PAD_L + slot * (i + 0.5)
        h = (base - TOP) * r["diff_lines"] / mx
        # 4px rounded data-end, square at the baseline: draw a rounded rect and
        # square off the bottom with an overlay.
        if h > 0:
            tip = _tip("%s\n%d diff lines\n%d files locked"
                       % (r["ts"], r["diff_lines"], r["n_files"]))
            o.append(f"<rect x='{cx-bw/2:.1f}' y='{base-h:.1f}' width='{bw:.1f}' "
                     f"height='{h:.1f}' rx='4' fill='var(--s3)'{tip}/>")
            o.append(f"<rect x='{cx-bw/2:.1f}' y='{base-min(h,4):.1f}' width='{bw:.1f}' "
                     f"height='{min(h,4):.1f}' fill='var(--s3)'/>")
        lab = r["ts"][-4:] if len(r["ts"]) > 4 else r["ts"]
        o.append(f"<text x='{cx:.1f}' y='{base+15:.1f}' text-anchor='middle'>{e(lab)}</text>")
    o.append(f"<text x='{PAD_L}' y='{H-6}' fill='var(--ink-mut)'>lock generation</text>")
    o.append("</svg>")
    return "".join(o)


# Verdict presentation. INERT is the point of this panel: "a gate that skips
# and a gate that checks and finds nothing clean were the same output" — so it
# gets its own token, never folded into GREEN. Status colour always rides an
# icon AND a label (the four status hues fail as adjacent chart fills, see the
# palette note above), which is why these are chips and tiles, not a stack.
VERDICT_META = {
    "GREEN":  ("--good", "\u2713", "passed"),
    "YELLOW": ("--warn", "\u26a0", "warned"),
    "RED":    ("--crit", "\u2717", "failed"),
    "INERT":  ("--ink-mut", "\u25cb", "graded nothing"),
    "UNKNOWN": ("--ink-mut", "?", "unknown"),
    "ERROR":  ("--crit", "!", "error rc"),
}


def chart_gate_runs(index, limit=14):
    """Gates by invocation count — magnitude, so one hue, no legend."""
    rows = [r for r in index if r["runs"]][:limit]
    if not rows:
        return ""
    mx = max(r["runs"] for r in rows) or 1
    LBL, PAD, W, BAR, GAP = 210, 44, 620, 18, 10
    PLOT = W - LBL - PAD
    H = len(rows) * (BAR + GAP) + 24
    o = [f"<svg viewBox='0 0 {W} {H}' role='img' aria-label='Gate invocations'>"]
    for gi in range(5):
        gx = LBL + PLOT * gi / 4
        o.append(f"<line class='gl' x1='{gx:.1f}' y1='0' x2='{gx:.1f}' y2='{H-20}'/>")
        o.append(f"<text x='{gx:.1f}' y='{H-6}' text-anchor='middle'>{round(mx*gi/4)}</text>")
    for i, row in enumerate(rows):
        y = i * (BAR + GAP)
        o.append(f"<text x='{LBL-9}' y='{y+BAR*0.72:.1f}' text-anchor='end'>"
                 f"{e(row['gate'][:30])}</text>")
        w = PLOT * row["runs"] / mx
        tip = _tip("%s\n%d run(s)\n%s" % (row["gate"], row["runs"],
                   ", ".join(f"{k} {v}" for k, v in row["verdicts"].items()) or "no verdicts"))
        o.append(f"<rect x='{LBL}' y='{y}' width='{max(w-2,1):.1f}' height='{BAR}' "
                 f"rx='2' fill='var(--s3)'{tip}/>")
        o.append(f"<text class='v' x='{LBL+w+7:.1f}' y='{y+BAR*0.72:.1f}'>{row['runs']}</text>")
    o.append("</svg>")
    return "".join(o)


def kpi(label, value, sub="", dot=""):
    d = f"<span class='dot' style='background:var({dot})'></span>" if dot else ""
    sb = f"<div class='sub'>{d}{e(sub)}</div>" if sub else ""
    return (f"<div class='kpi'><div class='lab'>{e(label)}</div>"
            f"<div class='val'>{e(value)}</div>{sb}</div>")




def md_to_html(text):
    """Very small Markdown -> HTML. Everything is HTML-escaped FIRST, so no
    document content can inject markup; only our own tags are added after."""
    import re as _re
    out, in_ul, in_code = [], False, False
    for raw in text.splitlines():
        line = e(raw)
        if raw.strip().startswith("```"):
            out.append("</code></pre>" if in_code else "<pre><code>")
            in_code = not in_code
            continue
        if in_code:
            out.append(line)
            continue
        if not line.strip():
            if in_ul:
                out.append("</ul>"); in_ul = False
            continue
        h = _re.match(r"^(#{1,6})\s+(.*)$", line)
        if h:
            if in_ul:
                out.append("</ul>"); in_ul = False
            lv = min(len(h.group(1)) + 2, 6)
            out.append(f"<h{lv}>{h.group(2)}</h{lv}>")
            continue
        li = _re.match(r"^\s*[-*+]\s+(.*)$", line)
        if li:
            if not in_ul:
                out.append("<ul>"); in_ul = True
            out.append(f"<li>{li.group(1)}</li>")
            continue
        if in_ul:
            out.append("</ul>"); in_ul = False
        out.append(f"<p>{line}</p>")
    if in_ul:
        out.append("</ul>")
    if in_code:
        out.append("</code></pre>")
    html_ = "\n".join(out)
    html_ = _re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", html_)
    html_ = _re.sub(r"(?<!\*)\*([^*\n]+)\*(?!\*)", r"<em>\1</em>", html_)
    html_ = _re.sub(r"`([^`\n]+)`", r"<code>\1</code>", html_)
    return html_


# ── governance rendering (model >= 1.3.0) ────────────────────────────────────
#
# DISPLAY LABELS LIVE HERE, NOT IN THE MODEL. The model stores what the sink
# recorded (`basis: "no-ledger"`, `count: null`); turning that into the reader-
# facing "UNKNOWN (no-ledger)" is a rendering decision, so a later consumer of
# the model is never handed a label it did not compute.
#
# Every fill below comes from a scale that was ALREADY validated in both modes
# (the --s1..--s5 ordinal ramp and the --ok/--bad pair; see the palette
# provenance note). No new scale is introduced, and no status hue is ever used
# as a chart fill.

# Latest-state -> ordinal ramp step. A finding's lifecycle IS an ordered scale
# (how far it has travelled from OPEN), which is exactly what a one-hue ramp is
# for. The ramp has FIVE validated steps and the vocabulary has six states, so
# the two TERMINAL non-open states share the last bucket rather than two states
# silently sharing a fill mid-scale. The bucket says what it contains, and the
# exact per-state totals are printed as text beside the bar — the chart
# summarises, the text is authoritative.
FIND_BUCKETS = [
    ("OPEN", ("OPEN",), "--s5"),
    ("ESCALATED", ("ESCALATED",), "--s4"),
    ("FIXED", ("FIXED",), "--s3"),
    ("VERIFIED", ("VERIFIED",), "--s2"),
    ("ACCEPTED / WITHDRAWN", ("ACCEPTED", "WITHDRAWN"), "--s1"),
]
FIND_STATE_ORDER = ["OPEN", "ESCALATED", "FIXED", "VERIFIED", "ACCEPTED", "WITHDRAWN"]


def _count_label(block):
    """{count, ids, basis} -> reader-facing text. A null count is UNKNOWN with
    its basis, NEVER a zero: 'no ledger to read' and 'a ledger that says zero'
    are different facts and must not print the same."""
    if isinstance(block, (int, float)) and not isinstance(block, bool):
        # A legacy card wrote a bare integer. Printing "—" for it discarded a
        # number the card actually states.
        return "%s (bare count, no basis recorded)" % block
    if not isinstance(block, dict):
        return "—"
    n, basis = block.get("count"), block.get("basis") or ""
    if n is None:
        return "UNKNOWN (%s)" % (basis or "no basis recorded")
    return "%d%s" % (n, " (%s)" % basis if basis else "")


def _integrity_badge(card):
    """verified | not-verified | unassessed — the only three the checker
    supports. A not-verified card carries the checker's REASON verbatim."""
    st = card.get("integrity") or "unassessed"
    cls = {"verified": "b-completed", "not-verified": "b-halted"}.get(st, "b-pending")
    reason = card.get("integrity_reason") or ""
    tail = f" <span class='meta'>{e(reason)}</span>" if reason else ""
    return f"<span class='badge {cls}'>{e(st)}</span>{tail}"


def chart_finding_states(totals):
    """Latest state of every finding, one stacked bar over five ordered buckets."""
    buckets = []
    for label, states, var in FIND_BUCKETS:
        v = sum(totals.get(st, 0) for st in states)
        if v:
            buckets.append((label, states, var, v))
    known = {st for _, states, _ in FIND_BUCKETS for st in states}
    other = sum(v for k, v in totals.items() if k not in known)
    if other:
        # A status outside the closed vocabulary still occupies the bar. Leaving
        # it undrawn made a 6-finding ledger render as one small segment on an
        # otherwise blank 560px bar with no explanation.
        buckets.append(("outside the vocabulary", (), "--s3", other))
    tot = sum(b[3] for b in buckets)
    if not tot:
        return ""
    W, H, BAR = 560, 54, 22
    o = [f"<svg viewBox='0 0 {W} {H}' role='img' aria-label='Findings by latest state'>"]
    x = 0.0
    for label, states, var, v in buckets:
        w = W * v / tot
        detail = (", ".join("%s %d" % (st, totals.get(st, 0)) for st in states if totals.get(st))
                  or "%s: %d" % (label, v))
        o.append(f"<rect x='{x:.1f}' y='0' width='{max(w - 2, 1):.1f}' height='{BAR}' rx='2' "
                 f"fill='var({var})'{_tip(detail)}/>")
        x += w
    # Exact per-state totals in text: the bar buckets, the text does not.
    exact = " · ".join("%s %d" % (k, totals[k]) for k in FIND_STATE_ORDER if totals.get(k))
    if other:
        exact += " · outside the vocabulary %d" % other
    o.append(f"<text class='v' x='0' y='{BAR + 17}'>{tot} finding(s) tracked</text>")
    o.append("</svg>")
    lg = "".join(f"<span><i style='background:var({var})'></i>{e(label)} {v}</span>"
                 for label, _s, var, v in buckets)
    return ("".join(o) + f"<div class='lg'>{lg}</div>"
            + f"<div class='meta'>latest state, exact: {e(exact)}</div>")


def chart_episodes(episodes):
    """One strip per back-route episode; one mark per hop, ESCALATE marks in the
    failed rust. Episodes are the writer's own segmentation (CLEAR markers), not
    a window this page invented."""
    EP_CAP = 8
    all_eps = [ep for ep in episodes if ep.get("hops")]
    eps = all_eps[:EP_CAP]
    eps_dropped = len(all_eps) - len(eps)
    if not eps:
        return ""
    # A long episode would squeeze every mark below a pixel, which reads as one
    # smear rather than as hops. Show the MOST RECENT window and say so.
    HOP_CAP = 40
    dropped = sum(max(0, len(ep["hops"]) - HOP_CAP) for ep in eps)
    ROW, BAR, LBL = 30, 18, 74
    W, H = 560, len(eps) * ROW + 8
    o = [f"<svg viewBox='0 0 {W} {H}' role='img' aria-label='Back-route episodes'>"]
    widest = max(min(len(ep["hops"]), HOP_CAP) for ep in eps) or 1
    for i, ep in enumerate(eps):
        y = i * ROW
        state = ep.get("state") or "open"
        o.append(f"<text x='{LBL - 9}' y='{y + BAR * 0.75:.1f}' text-anchor='end'>"
                 f"ep {e(ep.get('index'))} {e('·' + state)}</text>")
        cell = (W - LBL - 30) / max(widest, 1)
        for j, hop in enumerate(ep["hops"][-HOP_CAP:]):
            esc = hop.get("escalation")
            var = "--bad" if esc else "--s3"
            tip = "%s\n%s" % (hop.get("directive") or "", hop.get("ts") or "")
            o.append(f"<rect x='{LBL + j * cell:.1f}' y='{y}' width='{max(cell - 3, 2):.1f}' "
                     f"height='{BAR}' rx='2' fill='var({var})'{_tip(tip)}/>")
        o.append(f"<text class='v' x='{W - 24}' y='{y + BAR * 0.75:.1f}' text-anchor='end'>"
                 f"{len(ep['hops'])}</text>")
    o.append("</svg>")
    bits = []
    if dropped:
        bits.append(f"showing the most recent {HOP_CAP} hop(s) per episode; {dropped} "
                    f"earlier hop(s) not drawn (the counts at right are complete)")
    if eps_dropped:
        bits.append(f"{eps_dropped} older episode(s) not drawn")
    note = f"<div class='meta'>{'; '.join(bits)}</div>" if bits else ""
    return "".join(o) + ("<div class='lg'><span><i style='background:var(--s3)'></i>hop</span>"
                         "<span><i style='background:var(--bad)'></i>escalation</span></div>"
                         + note)


def chart_lease_spans(paths):
    """One bar per leased surface: open leases in teal, anything the GATE
    classified (zombie / silent mutation) or any recorded violation in rust.
    The classification is the gate's, never this renderer's."""
    LEASE_CAP = 10
    all_rows = [p for p in paths if p.get("n_acquires")]
    rows = all_rows[:LEASE_CAP]
    rows_dropped = len(all_rows) - len(rows)
    if not rows:
        return ""
    ROW, BAR, LBL = 26, 16, 190
    W, H = 560, len(rows) * ROW + 6
    o = [f"<svg viewBox='0 0 {W} {H}' role='img' aria-label='Leased surfaces'>"]
    for i, p in enumerate(rows):
        y = i * ROW
        # `classifications` is the gate's word. When the gate was not consulted
        # the model leaves the list empty, but a recorded violation is a literal
        # ledger event and stands on its own.
        flagged = bool(p.get("classifications")) or bool(p.get("n_violations"))
        var = "--bad" if flagged else ("--ok" if p.get("open") else "--s2")
        name = p["path"]
        o.append(f"<text x='{LBL - 9}' y='{y + BAR * 0.78:.1f}' text-anchor='end'>"
                 f"{e(name[-26:])}</text>")
        cls = ", ".join(p.get("classifications") or []) or ("open" if p.get("open") else "released")
        tip = "%s\n%s\nwrites %s · violations %s" % (name, cls, p.get("n_writes", 0),
                                                     p.get("n_violations", 0))
        o.append(f"<rect x='{LBL}' y='{y}' width='{W - LBL - 30}' height='{BAR}' rx='2' "
                 f"fill='var({var})'{_tip(tip)}/>")
    o.append("</svg>")
    lease_note = (f"<div class='meta'>{rows_dropped} further leased surface(s) not "
                  f"charted; the table below lists them all</div>" if rows_dropped else "")
    return "".join(o) + ("<div class='lg'><span><i style='background:var(--ok)'></i>held</span>"
                         "<span><i style='background:var(--s2)'></i>released</span>"
                         "<span><i style='background:var(--bad)'></i>flagged by the gate</span></div>"
                         + lease_note)


def render_governance(m):
    """The Governance panel: findings ledger, leases, seam cards, §7b
    acceptances, dispatch briefs, fix receipts, governors, ICR.

    Sections appear only when the model carries them. A source that was never
    adopted is NOT an empty section here — it is a line in the coverage banner,
    so 'not adopted' can never read as 'adopted and clean'.
    """
    g = m.get("governance")
    if not isinstance(g, dict):
        g = {}
    # Each section is rendered only when it is the shape this panel expects. The
    # governance layer is OPTIONAL and feature-detected, so an unexpected shape
    # must cost its own section, never the whole page.
    g = {k: v for k, v in g.items() if isinstance(v, dict) or k == "phase_pointers"}
    # NOTE: `panel`, not `panel viz` — the .viz scope redefines --ok from the
    # status green to the chart teal, which drops .badge.b-completed text
    # contrast below WCAG AA. Charts opt INTO .viz individually below.
    o = ["<section class='panel' id='governance'>"]
    if not g:
        o.append("<div class='empty'>No governance sinks found for this run — no findings "
                 "ledger, leases, seam cards, acceptances, receipts, back-route history or "
                 "independent-check requests. The coverage banner above lists each one.</div>")
        o.append("</section>")
        return "".join(o)
    o.append("<div class='sub'>What the run's governance layer RECORDED, and what its own "
             "checkers computed. This panel is a derived view: it never re-decides a gate's "
             "verdict, and anything a checker could not assess is labelled unassessed rather "
             "than shown as clean.</div>")
    # Adoption is stated beside the data, not in the coverage banner: the layer
    # is opt-in per run, so "no findings ledger" is a fact about this project,
    # not a gap in the page. Naming it here is what stops an unadopted sink from
    # being read as an adopted, clean one.
    if (m.get("coverage") or {}).get("governance_redacted"):
        o.append("<div class='banner'><h3>Bundle mode — content withheld</h3><ul><li>"
                 + e("This is a portable bundle. Governance sections carry counts and "
                     "verdicts only: holder names, authorizers, headlines, loci, digests "
                     "and requested commands are withheld from the page.")
                 + "</li></ul></div>")
    adopted = (m.get("coverage") or {}).get("governance_adoption") or []
    if adopted:
        o.append("<div class='banner'><h3>Sinks this run did not adopt</h3><ul>")
        for line in adopted:
            o.append(f"<li>{e(line)}</li>")
        o.append("</ul></div>")

    # ── findings ledger ─────────────────────────────────────────────────────
    f = g.get("findings")
    if f:
        o.append("<h4>Findings ledger <span class='meta'>%s</span></h4>" % e(f.get("path") or ""))
        if not (f.get("findings") or []):
            if f.get("usable_unknown"):
                # Every line was unparseable or gate-invalid. "Zero findings
                # filed" would be the exact null-as-zero claim this panel exists
                # to prevent.
                o.append("<div class='empty'>Ledger adopted, but NONE of its %s line(s) "
                         "are usable — the open-finding count is UNKNOWN, not zero. See "
                         "the coverage banner.</div>" % e(f.get("n_lines_total")))
            else:
                o.append("<div class='empty'>Ledger adopted, zero findings filed. "
                         "(A zero here is a real count, not an absent source.)</div>")
        else:
            o.append("<div class='viz'>" + chart_finding_states(f.get("totals_by_state") or {}) + "</div>")
            o.append("<div class='meta'>%s</div>" % e(f.get("iter_note") or ""))
            o.append("<div class='scroll'><table><tr><th>id</th><th>latest</th>"
                     "<th>lifecycle</th><th>locus</th><th>class</th><th>iter</th></tr>")
            _f_shown = (f.get("findings") or [])[:400]
            _f_dropped = len(f.get("findings") or []) - len(_f_shown)
            for rec in _f_shown:
                chain = " → ".join(t["status"] for t in rec["transitions"])
                flags = []
                if rec.get("reopens"):
                    flags.append("re-OPENed %dx" % rec["reopens"])
                if rec.get("invariant"):
                    flags.append("invariant")
                fl = (" <span class='badge b-excused'>%s</span>" % e(", ".join(flags))) if flags else ""
                it = rec.get("iter")
                o.append(f"<tr data-row><td><span class='mono'>{e(rec['id'])}</span></td>"
                         f"<td><span class='badge b-{'halted' if rec['latest'] == 'OPEN' else 'completed'}'>"
                         f"{e(rec['latest'] or '—')}</span>{fl}</td>"
                         f"<td class='meta'>{e(chain)}</td>"
                         f"<td><span class='mono'>{e(rec.get('locus') or '—')}</span></td>"
                         f"<td>{e(rec.get('cls') or '—')}</td>"
                         f"<td>{e(it if it is not None else '—')}</td></tr>")
            o.append("</table></div>")
            if _f_dropped:
                o.append("<div class='meta'>%d further finding(s) not listed (display "
                         "cap); the totals above cover all of them.</div>" % _f_dropped)

    # ── surface leases ──────────────────────────────────────────────────────
    l = g.get("leases")
    if l:
        chk = l.get("checker") or {}
        o.append("<h4>Surface leases <span class='meta'>%s</span></h4>" % e(l.get("path") or ""))
        if chk.get("state") == "assessed":
            o.append("<div class='meta'>surface-lease.sh check: <b>%s</b> · stale threshold "
                     "%sh · violations %s · silent mutations %s · zombies %s</div>"
                     % (e(chk.get("verdict")), e(chk.get("stale_hours_threshold")),
                        e(chk.get("violations")), e(chk.get("silent_mutations")),
                        e(chk.get("zombie_leases"))))
        else:
            o.append("<div class='meta'>Lease classifications <b>unassessed</b> (%s) — spans "
                     "below show recorded activity only; no zombie or silent-mutation label "
                     "is implied.</div>" % e(chk.get("reason") or "checker not consulted"))
        o.append("<div class='viz'>" + chart_lease_spans(l.get("paths") or []) + "</div>")
        if l.get("paths"):
            o.append("<div class='scroll'><table><tr><th>surface</th><th>holder</th>"
                     "<th>state</th><th>classification</th><th>last activity</th>"
                     "<th>writes</th><th>violations</th></tr>")
            _l_shown = (l.get("paths") or [])[:300]
            _l_dropped = len(l.get("paths") or []) - len(_l_shown)
            for p in _l_shown:
                cls = ", ".join(p.get("classifications") or [])
                _assessed = chk.get("state") == "assessed"
                if cls and _assessed:
                    cls_html = f"<span class='badge b-halted'>{e(cls)}</span>"
                elif cls:
                    # The model should never produce this, but the page must not
                    # assert a gate judgement the gate did not make.
                    cls_html = ("<span class='meta'>%s (not from the gate — ignored)</span>"
                                % e(cls))
                else:
                    # "the gate looked and found nothing" and "the gate's record
                    # set does not cover this path" are different facts.
                    _basis = str(p.get("classification_basis") or "")
                    cls_html = ("<span class='meta'>%s</span>"
                                % e("—" if _assessed and not _basis.startswith("not-assessed")
                                    else (_basis or "not assessed")))
                o.append(f"<tr data-row><td><span class='mono'>{e(p['path'])}</span></td>"
                         f"<td>{e(p.get('holder') or '—')}</td>"
                         f"<td>{'held' if p.get('open') else 'released'}</td>"
                         f"<td>{cls_html}</td><td class='meta'>{e(p.get('last_activity_ts') or '—')}</td>"
                         f"<td>{e(p.get('n_writes'))}</td><td>{e(p.get('n_violations'))}</td></tr>")
            o.append("</table></div>")
            if _l_dropped:
                o.append("<div class='meta'>%d further leased surface(s) not listed "
                         "(display cap).</div>" % _l_dropped)
        if l.get("snapshots"):
            o.append("<div class='meta'>%d instrument snapshot round(s) recorded.</div>"
                     % len(l["snapshots"]))

    # ── seam cards ──────────────────────────────────────────────────────────
    s = g.get("seams")
    if s:
        o.append("<h4>Seam cards <span class='meta'>seams/</span></h4>")
        if not (s.get("cards") or []):
            o.append("<div class='empty'>seams/ exists but carries no summary card.</div>")
        else:
            o.append("<div class='scroll'><table><tr><th>phase</th><th>integrity</th>"
                     "<th>verdict</th><th>gates (run/red/yellow/inert/unassessed)</th>"
                     "<th>open findings</th><th>fixed, unverified</th><th>accepted</th>"
                     "<th>next</th></tr>")
            for c in (s.get("cards") or []):
                _g = [c.get(k) for k in ("gates_run", "gates_red", "gates_yellow",
                                         "gates_inert", "gates_unassessed")]
                # A card the checker could not read has NO gate counts. Rendering
                # Python's None as data invented five values.
                gates = ("—" if all(v is None for v in _g)
                         else " / ".join("—" if v is None else str(v) for v in _g))
                _accb = c.get("accepted_findings")
                acc = _count_label(_accb) if isinstance(_accb, dict) else None
                stale_cls = " class='meta'" if c.get("integrity") != "verified" else ""
                o.append(f"<tr data-row{stale_cls}><td>{e(c.get('phase') or '—')}</td>"
                         f"<td>{_integrity_badge(c)}</td><td>{e(c.get('verdict') or '—')}</td>"
                         f"<td class='meta'>{e(gates)}</td>"
                         f"<td>{e(_count_label(c.get('open_findings')))}</td>"
                         f"<td>{e(_count_label(c.get('fixed_unverified')))}</td>"
                         f"<td>{e(acc if acc is not None else '—')}</td>"
                         f"<td>{e(c.get('next_phase') or '—')}</td></tr>")
            o.append("</table></div>")
            if s.get("n_truncated"):
                o.append("<div class='meta'>%d older card(s) not read (cap).</div>"
                         % s["n_truncated"])

    # ── §7b acceptances ─────────────────────────────────────────────────────
    a = g.get("acceptances")
    if a:
        o.append("<h4>Gate acceptances <span class='meta'>%s</span></h4>" % e(a.get("path") or ""))
        o.append("<div class='meta'>%s</div>" % e(a.get("rule") or ""))
        if not (a.get("records") or []):
            o.append("<div class='empty'>No acceptance entries filed.</div>")
        else:
            o.append("<div class='scroll'><table><tr><th>token</th><th>phase</th>"
                     "<th>headline (binds to the gate's FAIL)</th><th>NUMBER_EFFECT</th>"
                     "<th>authorized by</th><th>reason</th><th>disclosure</th>"
                     "<th>complete</th></tr>")
            for r in (a.get("records") or []):
                tok = r["token"]
                badge = {"accepted": "b-completed", "proposed": "b-excused"}.get(tok, "b-halted")
                # An empty Authorized-by is what the matcher itself reports as
                # <unnamed>; it is displayed, never treated as invalidating.
                by = r.get("authorized_by") or "<unnamed>"
                note = (" <span class='meta'>%s</span>" % e(r["parse_note"])) if r.get("parse_note") else ""
                o.append(f"<tr data-row><td><span class='badge {badge}'>{e(tok)}</span></td>"
                         f"<td>{e(r.get('phase') or '—')}</td>"
                         f"<td>{e((r.get('headline') or '')[:120])}{note}</td>"
                         f"<td>{e(r.get('number_effect') or '—')}</td>"
                         f"<td>{e(by)}</td><td>{e(r.get('reason_len'))} ch</td>"
                         f"<td>{e(r.get('disclosure_len'))} ch</td>"
                         f"<td>{'yes' if r.get('complete') else 'no'}</td></tr>")
            o.append("</table></div>")

    # ── fix receipts ────────────────────────────────────────────────────────
    rc = g.get("receipts")
    if rc:
        o.append("<h4>Fix receipts <span class='meta'>code-review/reviewed-scripts-*.json</span></h4>")
        o.append("<div class='meta'>Manifest fields as filed. Hash binding, out-of-scope "
                 "movement and the blocking-count cross-check belong to "
                 "pre-exec-review-check.sh — nothing here is re-verified.</div>")
        if not (rc.get("receipts") or []):
            o.append("<div class='empty'>code-review/ exists but holds no receipt.</div>")
        else:
            o.append("<div class='scroll'><table><tr><th>review_id</th><th>ts</th>"
                     "<th>supersedes</th><th>chain</th><th>fixed findings</th>"
                     "<th>remaining blocking</th><th>scripts</th><th>out of scope</th>"
                     "<th>validation</th></tr>")
            for r in (rc.get("receipts") or []):
                if r.get("malformed"):
                    o.append(f"<tr data-row><td colspan='9' class='meta'>{e(r['file'])} — "
                             f"not readable JSON</td></tr>")
                    continue
                chain = r.get("chain")
                ccls = "b-halted" if chain == "broken" else "b-completed" if chain == "linked" else "b-pending"
                o.append(f"<tr data-row><td><span class='mono'>{e(r.get('review_id'))}</span></td>"
                         f"<td class='meta'>{e(r.get('ts'))}</td>"
                         f"<td><span class='mono'>{e(r.get('supersedes_review_id') or '—')}</span></td>"
                         f"<td><span class='badge {ccls}'>{e(chain)}</span></td>"
                         f"<td>{e(len(r.get('fixed_finding_ids') or []))}</td>"
                         f"<td>{e(r.get('remaining_blocking_count'))}</td>"
                         f"<td>{e(r.get('n_scripts'))}</td><td>{e(r.get('n_out_of_scope'))}</td>"
                         f"<td class='meta'>{e(r.get('validation'))}</td></tr>")
            o.append("</table></div>")

    # ── governors ───────────────────────────────────────────────────────────
    gv = g.get("governors")
    if gv:
        o.append("<h4>Governors <span class='meta'>back-route episodes · 10.5 loop state</span></h4>")
        o.append("<div class='meta'>%d hop(s) across %d episode(s)%s. Episodes are segmented on "
                 "the writer's own CLEAR markers.</div>"
                 % (gv.get("n_hops", 0), gv.get("n_episodes", 0),
                    "; the final episode is still open" if gv.get("open_episode") else ""))
        o.append("<div class='viz'>" + chart_episodes(gv.get("episodes") or []) + "</div>")
        if gv.get("escalations"):
            o.append("<div class='scroll'><table><tr><th>ts</th><th>class</th><th>target</th>"
                     "<th>directive (verbatim)</th></tr>")
            for esc in gv["escalations"]:
                o.append(f"<tr data-row><td class='meta'>{e(esc.get('ts'))}</td>"
                         f"<td><span class='badge b-halted'>{e(esc.get('class'))}</span></td>"
                         f"<td>{e(esc.get('target') or 'target unknown (legacy bare ESCALATE)')}</td>"
                         f"<td><span class='mono'>{e(esc.get('directive'))}</span></td></tr>")
            o.append("</table></div>")
        ls = gv.get("loop_state")
        if isinstance(ls, dict):
            blk = ls.get("10.5") if isinstance(ls.get("10.5"), dict) else None
            if blk:
                o.append("<dl class='kv'><dt>10.5 loop</dt><dd>iter A/B/C "
                         f"{e(blk.get('iter_a'))}/{e(blk.get('iter_b'))}/{e(blk.get('iter_c'))} · "
                         f"last verdict {e(blk.get('last_verdict') or '—')} · "
                         f"last route-back {e(blk.get('last_route_back') or '—')}</dd></dl>")
        elif gv.get("loop_state_note"):
            o.append("<div class='meta'>%s</div>" % e(gv["loop_state_note"]))

    # ── independent-check requests ──────────────────────────────────────────
    icr = g.get("icr")
    if icr:
        c = icr.get("counts") or {}
        o.append("<h4>Independent-check requests <span class='meta'>gate verdict: %s</span></h4>"
                 % e(icr.get("verdict")))
        o.append("<div class='meta'>%s</div>" % e(icr.get("reason") or ""))
        bad_ = icr.get("not_authorizable_as_filed") or []
        pend = icr.get("pending_authorizable") or []
        if bad_:
            o.append("<h5>Not authorizable as filed <span class='meta'>the gate refused these; "
                     "they must be refiled to contract, never authorized as they stand</span></h5>")
            o.append("<div class='scroll'><table><tr><th>request</th><th>status</th>"
                     "<th>form</th><th>why the gate refused it</th></tr>")
            for r in bad_:
                o.append(f"<tr data-row><td><span class='mono'>{e(r.get('id_tag'))}</span></td>"
                         f"<td>{e(r.get('status') or '—')}</td><td>{e(r.get('form'))}</td>"
                         f"<td class='meta'>{e('; '.join(r.get('red_reasons') or []))}</td></tr>")
            o.append("</table></div>")
        if pend:
            o.append("<h5>Pending user authorization <span class='meta'>a human decides these; "
                     "the orchestrator must not grant, run or dismiss them</span></h5>")
            o.append("<div class='scroll'><table><tr><th>request</th><th>status</th>"
                     "<th>form</th></tr>")
            for r in pend:
                o.append(f"<tr data-row><td><span class='mono'>{e(r.get('id_tag'))}</span></td>"
                         f"<td><span class='badge b-excused'>{e(r.get('status'))}</span></td>"
                         f"<td>{e(r.get('form'))}</td></tr>")
            o.append("</table></div>")
        if icr.get("complete") is False:
            o.append("<div class='banner'><h3>This scan was incomplete</h3><ul><li>"
                     + e("The gate did not read every review report for this project "
                         "(see bounds below), so the counts here are a FLOOR, not a "
                         "total. No clean verdict can be given from a bounded scan.")
                     + "</li></ul></div>")
            _b = icr.get("bounds") or {}
            o.append("<div class='meta'>bounds: %s</div>"
                     % e(", ".join("%s=%s" % (k, v) for k, v in sorted(_b.items()))))
        if not bad_ and not pend:
            if icr.get("complete") is False:
                o.append("<div class='empty'>No requests were found in the part of the "
                         "corpus that was read. This is NOT a statement that none "
                         "exist.</div>")
            else:
                o.append("<div class='empty'>No requests pending and none refused "
                         "(%s filed in total).</div>" % e(c.get("total", 0)))
        for line in icr.get("unparseable_heading_lines") or []:
            o.append(f"<div class='meta'>unparseable heading section: {e(line)}</div>")

    # ── dispatch provenance ─────────────────────────────────────────────────
    dp = g.get("dispatch_provenance")
    if dp:
        o.append("<h4>Legacy dispatch metadata <span class='meta'>%s</span></h4>" % e(dp["path"]))
        _accounted = (dp.get("n_verified", 0) + dp.get("n_mismatch", 0)
                      + dp.get("n_missing", 0))
        _resid = max(0, dp.get("n_briefed", 0) - _accounted)
        _residtxt = (", %d not re-hashed (cap or no recorded sha)" % _resid) if _resid else ""
        o.append("<div class='meta'>%s row(s): %s briefed (%s re-hash verified, %s mismatch, "
                 "%s missing%s), %s legacy unbriefed. `verified` is a byte identity check "
                 "against the sha the manifest row recorded — display metadata only, "
                 "not review-evidence authority.</div>"
                 % (e(dp.get("n_rows")), e(dp.get("n_briefed")), e(dp.get("n_verified")),
                    e(dp.get("n_mismatch")), e(dp.get("n_missing")), _residtxt,
                    e(dp.get("n_unbriefed"))))
    o.append("</section>")
    return "".join(o)


def build_html(m, outdir, auto_refresh=0):
    P, C, S = m["project"], m["coverage"], m["state"]
    phases, arts = m["phases"], m["artifacts"]

    # Deep links to raw transcripts, only where one actually exists on disk.
    rel_tx = {}
    for sid in m.get("sessions", []):
        p = os.path.normpath(os.path.join(outdir, "..", "transcript-html", sid, "index.html"))
        if os.path.isfile(p):
            rel_tx[sid] = os.path.relpath(p, outdir)

    gov = m.get("governance") or {}
    # Seam cards keyed by phase, so the spine can carry an integrity chip. The
    # chip states the CHECKER's verdict on that phase's card; it never asserts
    # anything the checker did not say.
    seam_by_phase = {}
    for _c in (gov.get("seams") or {}).get("cards", []):
        if _c.get("phase"):
            seam_by_phase[str(_c["phase"])] = _c
    counts = {}
    for ph in phases:
        counts[ph["status"]] = counts.get(ph["status"], 0) + 1
    n_steps = C.get("n_trace_steps", 0)
    n_fail = sum(ph["n_failed_steps"] for ph in phases)
    n_disp = C.get("n_dispatches", 0)
    suspects = [ph for ph in phases if ph.get("dispatch_suspect")]

    o = []
    o.append("<!doctype html><html lang='en'><head><meta charset='utf-8'>")
    o.append("<meta name='viewport' content='width=device-width,initial-scale=1'>")
    if auto_refresh:
        # Lets an open tab follow a running pipeline without the reader doing
        # anything. Off unless asked for: a page that reloads under you is
        # hostile when you are reading a finished run.
        o.append(f"<meta http-equiv='refresh' content='{int(auto_refresh)}'>")
    title = f"Run — {P['slug']} ({P['orchestrator']})"
    o.append(f"<title>{e(title)}</title><style>{CSS}{VIZ_CSS}</style></head><body><div class='wrap'>")
    o.append(f"<h1>{e(P['slug'])}</h1>")
    o.append(f"<div class='sub'>{e(P['orchestrator'])} · model v{e(m['model_version'])} · "
             f"generated {e(m['generated_at'])} · last run activity {e(S.get('last_updated') or '—')}</div>")

    o.append("<div class='chips'>")
    o.append(chip("phases", len(phases)))
    for k in STATUS_ORDER:
        if counts.get(k):
            cls = {"completed": "ok", "current": "cur", "halted": "fail", "undeclared": "fail",
                   "excused": "warn", "stale": "warn"}.get(k, "")
            o.append(chip(k, counts[k], cls))
    if n_steps:
        o.append(chip("RAO steps", n_steps))
    if n_fail:
        o.append(chip("failed steps", n_fail, "fail"))
    if n_disp:
        o.append(chip("dispatches", n_disp))
    if m["locks"]:
        o.append(chip("lock generations", len(m["locks"])))
    if m["anomalies"]:
        o.append(chip("anomalies", len(m["anomalies"]), "warn"))
    o.append(chip("artifacts", len(arts)))
    if S.get("current_phase"):
        o.append(chip("current phase", S["current_phase"], "cur"))
    o.append("</div>")

    if C.get("degraded_reasons"):
        o.append("<div class='banner'><h3>Coverage — what this page could NOT show</h3><ul>")
        for d in C["degraded_reasons"]:
            o.append(f"<li>{e(d)}</li>")
        o.append("</ul></div>")

    rep = m.get("report") or {}
    ch = m.get("charts") or {}
    n_results = len(rep.get("tables", [])) + len(rep.get("figures", [])) + len(rep.get("documents", []))
    tabs = [("overview", "Overview", ""), ("spine", "Pipeline", len(phases)),
            ("results", "Results", n_results),
            ("gates", "Gates", (m.get("gates") or {}).get("n_distinct_declared", 0)),
            ("agents", "Agents", n_disp + len(m["reviews"])),
            ("anomalies", "Anomalies", len(m["anomalies"]))]
    # Feature-detect by key presence: a 1.2 model carries no governance section
    # and simply renders without the tab (an old renderer on a 1.3+ model is the
    # unsupported direction — it drops the layer silently).
    _gov = {k: v for k, v in gov.items() if k != "phase_pointers"}
    if _gov:
        # Every other tab counts ITEMS; counting sections here made "Governance 8"
        # point at a panel with eight headings and no rows.
        _gn = 0
        for _k, _sec in _gov.items():
            if not isinstance(_sec, dict):
                continue
            for _lk in ("findings", "paths", "cards", "records", "receipts",
                        "episodes", "requests", "rows"):
                _lv = _sec.get(_lk)
                if isinstance(_lv, list):
                    _gn += len(_lv)
        tabs.append(("governance", "Governance", _gn))
    tabs += [("locks", "Locks", len(m["locks"])),
            ("artifacts", "Artifacts", len(arts)), ("trace", "Trace", n_steps)]
    o.append("<nav class='tabs' role='tablist'>")
    for tid, label, n in tabs:
        o.append(f"<button role='tab' data-tab='{tid}' aria-selected='false'>{e(label)}"
                 f"<span class='n'>{n}</span></button>")
    o.append("</nav>")

    # ── OVERVIEW: KPI row + charts ──────────────────────────────────────────
    # Headline numbers are stat tiles, not a one-bar bar chart. Status colour
    # rides an accompanying dot AND the label, never colour alone.
    o.append("<section class='panel viz' id='overview'>")
    prog = ch.get("progress") or {"done": 0, "total": 0, "pct": 0}
    o.append("<div class='kpis'>")
    o.append("<div class='kpi'><div class='lab'>Pipeline progress</div>"
             f"<div class='val'>{prog['done']}<span style='font-size:16px;color:var(--mut)'>"
             f"/{prog['total']}</span></div>"
             f"<div class='meter'><i style='width:{max(prog['pct'],1.5):.1f}%'></i></div>"
             f"<div class='sub'>{prog['pct']}% of declared phases done or excused</div></div>")
    o.append(kpi("Failed steps", n_fail if n_steps else "—",
                 "across the RAO trace" if n_steps else "no trace recorded",
                 "--crit" if n_fail else ("--good" if n_steps else "")))
    findings = sum(sum(r["severities"].values()) for r in m["reviews"]) if m["reviews"] else 0
    crit = sum(r["severities"].get("CRITICAL", 0) for r in m["reviews"])
    o.append(kpi("Review findings", findings,
                 f"{crit} critical" if crit else "none critical",
                 "--crit" if crit else "--good"))
    o.append(kpi("Anomalies", len(m["anomalies"]),
                 "excuses, halts, bypasses", "--warn" if m["anomalies"] else "--good"))
    o.append(kpi("Lock generations", len(m["locks"]),
                 f"relock_count {S.get('relock_count') or '—'}"))
    o.append(kpi("Artifacts", len(arts),
                 f"{len(rep.get('withheld', []))} withheld" if rep.get("withheld") else "all embeddable",
                 "--warn" if rep.get("withheld") else ""))
    # ── governance KPIs ─────────────────────────────────────────────────────
    # Each one states its BASIS. "no ledger" and "a ledger reading zero" are
    # different facts, and a tile that printed 0 for both would be the exact
    # false confidence the seam three-state work removed.
    # Every tile states its BASIS, and a tile whose section is present but could
    # not be read shows UNKNOWN rather than a green zero. `is not None` alone
    # trusted a key that may be an empty or partial dict.
    _f = gov.get("findings")
    if isinstance(_f, dict) and _f.get("present"):
        _open = _f.get("n_open")
        if _open is None:
            o.append(kpi("Open findings", "UNKNOWN",
                         _f.get("n_open_basis") or "ledger unreadable", "--warn"))
        else:
            o.append(kpi("Open findings", _open,
                         "basis: findings ledger", "--crit" if _open else "--good"))
    _a = gov.get("acceptances")
    if isinstance(_a, dict) and _a.get("present"):
        _risk = _a.get("n_gate_merge_risk") or 0
        _sub = f"{_a.get('n_proposed', 0)} proposed · {_a.get('n_complete', 0)} complete"
        if _risk:
            _sub += f" · {_risk} the gate would misread"
        o.append(kpi("Gate acceptances", _a.get("n_accepted", 0), _sub,
                     "--crit" if _risk else ("--warn" if _a.get("n_proposed") else "")))
    _gv = gov.get("governors")
    if isinstance(_gv, dict) and _gv.get("present"):
        # `halted` is the PIPELINE's status, not a governor fact — say which.
        _halted = str(S.get("current_phase_status") or "").startswith("halted")
        _openep = _gv.get("open_episode")
        if not _gv.get("segmentation_reliable", True):
            _state, _dot = "UNRELIABLE", "--warn"
        elif _openep:
            _state, _dot = "episode open", "--warn"
        else:
            _state, _dot = "no open episode", "--good"
        if _gv.get("escalations"):
            _dot = "--crit"
        _sub = (f"{_gv.get('n_hops', 0)} hop(s) · "
                f"{len(_gv.get('escalations') or [])} escalation(s)")
        if _halted:
            _sub += " · pipeline halted"
        o.append(kpi("Governor state", _state, _sub, _dot))
    _icr = gov.get("icr")
    if isinstance(_icr, dict) and _icr.get("present"):
        _np = len(_icr.get("pending_authorizable") or [])
        _nb = len(_icr.get("not_authorizable_as_filed") or [])
        if _icr.get("complete") is False:
            # A bounded scan did not read every report: the queue length is a
            # floor, not a count.
            o.append(kpi("Check requests", "UNKNOWN",
                         f"scan incomplete · at least {_np} pending, {_nb} refused",
                         "--warn"))
        else:
            _tot = (_icr.get("counts") or {}).get("pending")
            _sub = f"pending a human · {_nb} not authorizable as filed"
            if isinstance(_tot, int) and _tot != _np:
                _sub += f" (of {_tot} filed as pending)"
            o.append(kpi("Check requests", _np, _sub,
                         "--crit" if _nb else ("--warn" if _np else "--good")))
    o.append("</div>")

    o.append("<div class='cards'>")
    sev = chart_severity(ch.get("severity_by_dimension") or [])
    if sev:
        o.append("<div class='card'><button class='exp'>SVG</button>"
                 "<h3>Findings by dimension</h3>"
                 "<div class='cap'>Severity is an ordered scale, so it uses one hue "
                 "light&rarr;dark — not the reserved status colours.</div>" + sev + "</div>")
    stp = chart_steps(ch.get("steps_by_phase") or [])
    if stp:
        o.append("<div class='card'><button class='exp'>SVG</button>"
                 "<h3>Trace steps per phase</h3>"
                 "<div class='cap'>Failures carry the critical hue; everything else "
                 "recedes.</div>" + stp + "</div>")
    lk = chart_locks(ch.get("lock_churn") or [])
    if lk:
        o.append("<div class='card'><button class='exp'>SVG</button>"
                 "<h3>Results-lock churn</h3>"
                 "<div class='cap'>Diff lines per lock generation — how much moved "
                 "at each relock.</div>" + lk + "</div>")
    o.append("</div>")
    if not (sev or stp or lk):
        o.append("<div class='empty'>No chartable metrics yet. Findings need "
                 "<code>reviews/</code>, step charts need an RAO trace, and churn "
                 "needs more than one lock generation.</div>")
    o.append("</section>")

    # ── PIPELINE ────────────────────────────────────────────────────────────
    o.append("<section class='panel' id='spine'>")
    # Quick filters, borrowed from dsh-trace-compare's failures-only toggle:
    # the two questions actually asked of a run are "what broke" and "what got
    # waived", so make each one click instead of a dropdown hunt.
    o.append("<div class='toolbar' data-filters><input type='search' placeholder='Filter phases, steps, gates…'>"
             "<select><option value='all'>All statuses</option>" +
             "".join(f"<option value='{k}'>{k}</option>" for k in STATUS_ORDER if counts.get(k)) +
             "</select>"
             "<button class='qf' data-qf='trouble' aria-pressed='false'>Trouble only</button>"
             "<button class='qf' data-qf='waived' aria-pressed='false'>Waived only</button>"
             "<span class='meta'><span class='count'>0</span> shown</span></div>")
    if suspects:
        o.append("<div class='banner'><h3>Review-evidence check</h3><ul><li>" +
                 e(f"{len(suspects)} completed review-evidence phase(s) recorded no "
                   f"digest-verified successful role completion in state: "
                   f"{', '.join(p['id'] for p in suspects)}. Legacy dispatch-manifest rows "
                   f"cannot satisfy this check.") +
                 "</li></ul></div>")
    arcs = [{"from": rb["from"], "to": rb["to"]} for rb in m.get("route_backs", [])
            if rb.get("from") and rb.get("to")]
    o.append("<div class='spine'>")
    o.append(f"<svg class='arcs' id='arcs' data-arcs='{e(json.dumps(arcs))}'></svg>")
    o.append("<div id='spineList'>")
    for ph in phases:
        st = ph["status"]
        o.append(f"<details class='ph {e(st)}' data-row data-status='{e(st)}' data-pid='{e(ph['id'])}'>")
        o.append("<summary>")
        o.append(f"<span class='pid'>{e(ph['id'])}</span>")
        o.append(f"<span class='plab'>{e(ph['label'] or '—')}</span>")
        o.append(f"<span class='badge b-{e(st)}'>{e(st)}</span>")
        bits = []
        if ph["n_steps"]:
            bits.append(f"{ph['n_steps']} steps")
        if ph["n_failed_steps"]:
            bits.append(f"{ph['n_failed_steps']} failed")
        if ph["dispatches"]:
            bits.append(f"{len(ph['dispatches'])} agents")
        if ph["reviews"]:
            bits.append(f"{len(ph['reviews'])} reviews")
        if ph.get("retry_count"):
            bits.append(f"retried ×{ph['retry_count']}")
        _sc = seam_by_phase.get(str(ph["id"]))
        if _sc:
            bits.append("seam card " + str(_sc.get("integrity") or "unassessed"))
        _pp = (gov.get("phase_pointers") or {}).get(str(ph["id"])) or {}
        if _pp:
            # LATEST only. Digest reports and rotated phase notes append
            # forever; inventorying every generation would bloat the model for
            # no reader benefit, so the row links the newest of each.
            bits.append("latest " + " + ".join(sorted(k.replace("_", " ") for k in _pp)))
        if ph["route_backs_in"]:
            bits.append(f"↩ {len(ph['route_backs_in'])} in")
        if ph["route_backs_out"]:
            bits.append(f"↪ {len(ph['route_backs_out'])} out")
        if not ph["declared"]:
            bits.append("NOT in declared sequence")
        if bits:
            o.append(f"<span class='meta'>{e(' · '.join(bits))}</span>")
        o.append("</summary><div class='body'>")

        o.append("<dl class='kv'>")
        if ph.get("completed_at"):
            o.append(f"<dt>Completed</dt><dd>{e(ph['completed_at'])}</dd>")
        if ph.get("declared_gate"):
            o.append(f"<dt>Declared gate</dt><dd><span class='mono'>{e(ph['declared_gate'])}</span></dd>")
        if ph.get("excuse"):
            o.append(f"<dt>Excuse</dt><dd>{e(ph['excuse'])}</dd>")
        if not ph["declared"]:
            o.append("<dt>Drift</dt><dd>This phase completed but is absent from the "
                     "orchestrator's declared phase sequence.</dd>")
        if ph.get("required_outputs"):
            o.append("<dt>Required outputs</dt><dd>" + " ".join(
                f"<a class='art' href='{e(os.path.join('..','..',r))}'>{e(r)}</a>"
                for r in ph["required_outputs"]) + "</dd>")
        if ph.get("artifacts"):
            o.append("<dt>Recorded artifacts</dt><dd>" + " ".join(
                f"<a class='art' href='{e(os.path.join('..','..',r))}'>{e(r)}</a>"
                for r in ph["artifacts"]) + "</dd>")
        o.append("</dl>")

        gts = ph.get("gates") or []
        if gts:
            n_obs = sum(1 for g in gts if g["runs"])
            o.append(f"<h4>Gates declared at this phase — {len(gts)} "
                     f"({n_obs} with a run record)</h4><div class='scroll'><table>"
                     "<tr><th>gate</th><th>verdict</th><th>runs</th></tr>")
            for g in gts:
                v = g.get("verdict")
                if v:
                    var, ico, blurb = VERDICT_META.get(v, ("--ink-mut", "?", ""))
                    cell = (f"<span class='badge' style='background:var(--mutbg);"
                            f"color:var({var})'>{ico} {e(v)}</span> "
                            f"<span class='meta'>{e(blurb)}</span>")
                else:
                    cell = "<span class='meta'>no record — not evidence of a pass</span>"
                extra = "" if g.get("declared") else " <span class='meta'>(not on this phase's roster)</span>"
                o.append(f"<tr><td><code>{e(g['name'])}</code>{extra}</td>"
                         f"<td>{cell}</td><td>{g['runs']}</td></tr>")
            o.append("</table></div>")
        for rb in ph["route_backs_out"]:
            o.append(f"<div class='step fail'><b>Route-back → phase {e(rb['to'])}</b>"
                     f"<div class='meta'>{e(rb.get('reason') or '')}"
                     f"{' · findings: ' + e(', '.join(map(str, rb.get('finding_ids') or []))) if rb.get('finding_ids') else ''}</div></div>")
        if ph["dispatches"]:
            o.append("<h4>Registered review completions</h4><div class='scroll'><table>"
                     "<tr><th>dispatch ID</th><th>role</th><th>round / session</th>"
                     "<th>report</th></tr>")
            for d in ph["dispatches"]:
                o.append(f"<tr><td><span class='mono'>{e(d.get('agentId'))}</span></td>"
                         f"<td>{e(d.get('agent') or d.get('seat') or d.get('subagent_type'))}</td>"
                         f"<td>{e(d.get('round') or '—')} · "
                         f"<span class='mono'>{e(d.get('session_id') or '—')}</span></td>"
                         f"<td>{e(d.get('report') or d.get('output') or '')}</td></tr>")
            o.append("</table></div>")
        if ph["reviews"]:
            o.append("<h4>Reviews</h4><div class='scroll'><table><tr><th>dimension</th><th>iter</th>"
                     "<th>severities</th><th>resolved</th><th>file</th></tr>")
            for r in ph["reviews"]:
                sev = ", ".join(f"{k} {v}" for k, v in r["severities"].items() if v) or "—"
                o.append(f"<tr><td>{e(r['dimension'])}</td><td>{e(r['iteration'])}</td>"
                         f"<td>{e(sev)}</td><td>{e(r['resolved'])}</td>"
                         f"<td><a class='art' href='{e(os.path.join('..','..',r['file']))}'>{e(r['file'])}</a></td></tr>")
            o.append("</table></div>")
        o.append(render_steps(ph["steps"], rel_tx))
        o.append("</div></details>")
    o.append("</div></div></section>")

    # ── GATES ───────────────────────────────────────────────────────────────
    G = m.get("gates") or {}
    gidx = G.get("index") or []
    gruns = G.get("runs") or []
    o.append("<section class='panel viz' id='gates'>")
    src = G.get("source", "none")
    o.append("<div class='sub'>Every gate the pipeline declares, and what is known "
             "about whether it actually ran. Declared roster comes from "
             "<code>references/gates-invoked-per-phase.md</code> (generated from "
             "<code>phase-verify.sh</code>).</div>")
    if src == "none":
        o.append("<div class='banner'><h3>No gate-run record</h3><p style='margin:0'>"
                 "Nothing on disk says which gates fired or what they returned. The "
                 "roster below is what each phase <em>declares</em> — not evidence that "
                 "any of it ran. <code>logs/gate-runs.ndjson</code> carries every "
                 "invocation once the phase-verify wrapper is in place.</p></div>")
    elif src.startswith("trace"):
        o.append("<div class='banner'><h3>Partial gate record</h3><p style='margin:0'>"
                 "Verdicts below come from the RAO trace, which records a gate call only "
                 "when a skill logged one as a step — so passing gates are largely "
                 "invisible and run counts are floors, not totals.</p></div>")
    vc = {}
    for r in gruns:
        vc[r["verdict"]] = vc.get(r["verdict"], 0) + 1
    o.append("<div class='kpis'>")
    o.append(kpi("Declared gates", G.get("n_distinct_declared", 0),
                 f"{G.get('n_declared_total', 0)} phase-assignments"))
    o.append(kpi("Observed runs", len(gruns), f"source: {src}"))
    for v in ("GREEN", "YELLOW", "RED", "INERT"):
        if vc.get(v):
            var, ico, blurb = VERDICT_META[v]
            o.append(kpi(v.title(), vc[v], f"{ico} {blurb}", var))
    never = [g for g in gidx if g.get("declared") and not g["runs"]]
    o.append(kpi("Never observed", len(never),
                 "declared but no record", "--warn" if never else ""))
    o.append("</div>")
    ch_runs = chart_gate_runs(gidx)
    if ch_runs:
        o.append("<div class='cards'><div class='card'><button class='exp'>SVG</button>"
                 "<h3>Gates by invocation count</h3>"
                 "<div class='cap'>Which gates carry the load. A gate that never appears "
                 "here is either not reached or not recorded.</div>" + ch_runs + "</div></div>")
    o.append("<div class='toolbar' data-filters><input type='search' "
             "placeholder='Filter gates by name or phase…'>"
             "<button class='qf' data-qf='never' aria-pressed='false'>Never observed</button>"
             "<span class='meta'><span class='count'>0</span> shown</span></div>")
    if not gidx:
        o.append("<div class='empty'>No gate roster found — is "
                 "<code>gates-invoked-per-phase.md</code> present in the plugin tree?</div>")
    else:
        o.append("<div class='scroll'><table><tr><th>gate</th><th>declared at phases</th>"
                 "<th>runs</th><th>verdicts</th></tr>")
        for gi in gidx:
            never_flag = "never" if (gi.get("declared") and not gi["runs"]) else "seen"
            ph = " ".join(f"<span class='grp'>{html.escape(x)}</span>" for x in gi["phases"][:8]) \
                 or ("<span class='meta'>wired, not on a phase roster</span>"
                     if gi.get("wired_only") else "<span class='meta'>—</span>")
            vd = " ".join(
                f"<span class='badge' style='background:var(--mutbg);color:var({VERDICT_META.get(k,('--ink-mut','','' ))[0]})'>"
                f"{VERDICT_META.get(k, ('', '?', ''))[1]} {html.escape(k)} {v}</span>"
                for k, v in sorted(gi["verdicts"].items())) or "<span class='meta'>no record</span>"
            o.append(f"<tr data-row data-status='{never_flag}'>"
                     f"<td><code>{html.escape(gi['gate'])}</code></td>"
                     f"<td>{ph}</td><td>{gi['runs']}</td><td>{vd}</td></tr>")
        o.append("</table></div>")
    o.append("</section>")

    # ── AGENTS ──────────────────────────────────────────────────────────────
    o.append("<section class='panel' id='agents'>")
    o.append("<div class='toolbar' data-filters><input type='search' placeholder='Filter agents and reviews…'>"
             "<span class='meta'><span class='count'>0</span> shown</span></div>")
    if not n_disp and not m["reviews"]:
        o.append("<div class='empty'>No agent dispatches or review reports found for this run.</div>")
    else:
        if n_disp:
            o.append("<h4>Review completions (digest-verified state ledger)</h4>"
                     "<div class='scroll'><table><tr><th>phase</th><th>dispatch ID</th>"
                     "<th>role</th><th>round</th><th>session</th><th>report</th></tr>")
            for ph in phases:
                for d in ph["dispatches"]:
                    o.append(f"<tr data-row><td>{e(ph['id'])}</td>"
                             f"<td><span class='mono'>{e(d.get('agentId'))}</span></td>"
                             f"<td>{e(d.get('agent') or d.get('seat') or d.get('subagent_type'))}</td>"
                             f"<td>{e(d.get('round') or '—')}</td>"
                             f"<td><span class='mono'>{e(d.get('session_id') or '—')}</span></td>"
                             f"<td>{e(d.get('report') or '')}</td></tr>")
            o.append("</table></div>")
        if m["reviews"]:
            o.append("<h4>Review reports (reviews/)</h4><div class='scroll'><table><tr><th>phase</th>"
                     "<th>iter</th><th>dimension</th><th>severities</th><th>NUMBER_EFFECT</th>"
                     "<th>resolved</th><th>file</th></tr>")
            for r in m["reviews"]:
                sev = ", ".join(f"{k} {v}" for k, v in r["severities"].items() if v) or "—"
                o.append(f"<tr data-row><td>{e(r['phase'])}</td><td>{e(r['iteration'])}</td>"
                         f"<td>{e(r['dimension'])}</td><td>{e(sev)}</td>"
                         f"<td>{e(r['number_effect'])}</td><td>{e(r['resolved'])}</td>"
                         f"<td><a class='art' href='{e(os.path.join('..','..',r['file']))}'>{e(r['file'])}</a></td></tr>")
            o.append("</table></div>")
    o.append("</section>")

    # ── RESULTS (the report / showcase half) ────────────────────────────────
    o.append("<section class='panel' id='results'>")
    wh = rep.get("withheld") or []
    if wh:
        o.append("<div class='banner'><h3>Withheld from this page</h3>"
                 f"<p style='margin:0 0 6px'>{len(wh)} artifact(s) are explicitly "
                 "restricted in <code>.claude/safety-status.json</code> and are named "
                 "but never rendered or embedded:</p><ul>")
        for w in wh[:25]:
            o.append(f"<li><code>{e(w['path'])}</code> — {e(w['safety'])}</li>")
        if len(wh) > 25:
            o.append(f"<li>… and {len(wh)-25} more</li>")
        o.append("</ul></div>")
    if not n_results:
        o.append("<div class='empty'>No renderable research outputs found under "
                 "<code>tables/ figures/ drafts/</code>.</div>")
    else:
        o.append("<div class='toolbar' data-filters><input type='search' "
                 "placeholder='Filter tables, figures and documents…'>"
                 "<span class='meta'><span class='count'>0</span> shown</span></div>")
        figs = rep.get("figures") or []
        if figs:
            o.append("<h4>Figures</h4><div class='cards'>")
            for f in figs:
                o.append("<div class='card' data-row>")
                o.append(f"<h3>{e(os.path.basename(f['path']))}</h3>"
                         f"<div class='cap'>{e(f['path'])}</div>")
                if f.get("data_uri"):
                    o.append(f"<img src='{f['data_uri']}' alt='{e(f['path'])}' "
                             "style='max-width:100%;height:auto;border-radius:6px'/>")
                elif f["ext"] == ".pdf":
                    o.append(f"<a class='art' href='{e(os.path.join('..','..',f['path']))}'>"
                             "open PDF ↗</a>"
                             "<div class='meta'>PDFs are linked, not inlined — a bundled "
                             "copy would multiply the page size.</div>")
                else:
                    o.append(f"<a class='art' href='{e(os.path.join('..','..',f['path']))}'>"
                             "open ↗</a>")
                o.append("</div>")
            o.append("</div>")
        tbls = rep.get("tables") or []
        if tbls:
            o.append("<h4>Tables</h4>")
            for t in tbls:
                o.append(f"<details class='ph completed' data-row><summary>"
                         f"<span class='pid'>tbl</span>"
                         f"<span class='plab'>{e(os.path.basename(t['path']))}</span>"
                         f"<span class='meta'>{len(t['columns'])} cols · {len(t['rows'])} rows"
                         f"{' · truncated' if t.get('truncated') else ''}</span>"
                         "</summary><div class='body'><div class='scroll'><table><tr>")
                for c in t["columns"]:
                    o.append(f"<th>{e(c)}</th>")
                o.append("</tr>")
                for row in t["rows"]:
                    o.append("<tr>" + "".join(f"<td>{e(c)}</td>" for c in row) + "</tr>")
                o.append("</table></div>"
                         f"<div class='meta' style='margin-top:8px'>{e(t['path'])}</div>"
                         "</div></details>")
        docs = rep.get("documents") or []
        if docs:
            o.append("<h4>Documents</h4>")
            for d in docs:
                o.append(f"<details class='ph completed' data-row><summary>"
                         f"<span class='pid'>doc</span>"
                         f"<span class='plab'>{e(os.path.basename(d['path']))}</span>"
                         f"<span class='meta'>{d['words']} words · {e(d['group'])}"
                         f"{' · truncated' if d.get('truncated') else ''}</span>"
                         "</summary><div class='body prose'>")
                o.append(md_to_html(d["text"]))
                o.append("</div></details>")
    o.append("</section>")

    # ── ANOMALIES ───────────────────────────────────────────────────────────
    o.append("<section class='panel' id='anomalies'>")
    o.append("<div class='sub'>Every excuse, force-complete, halt, bypass and stale marker, "
             "collected from the five audit logs and the run state. These are what the "
             "pacing-discipline rules exist to catch; they normally sit in separate files.</div>")
    o.append("<div class='toolbar' data-filters><input type='search' placeholder='Filter anomalies…'>"
             "<span class='meta'><span class='count'>0</span> shown</span></div>")
    if not m["anomalies"]:
        o.append("<div class='empty'>No excuses, force-completes, halts, or bypasses recorded. "
                 "(Absence of audit files is itself reported in the coverage banner above.)</div>")
    else:
        o.append("<div class='scroll'><table><tr><th>kind</th><th>phase</th><th>detail</th><th>source</th></tr>")
        for a in m["anomalies"]:
            o.append(f"<tr data-row><td><span class='badge b-excused'>{e(a['kind'])}</span></td>"
                     f"<td>{e(a['phase'])}</td><td>{e(a['detail'])}</td>"
                     f"<td><span class='mono'>{e(a['source'])}</span></td></tr>")
        o.append("</table></div>")
    o.append("</section>")

    # ── GOVERNANCE (RCA Rounds 1-3 machinery) ───────────────────────────────
    if _gov:
        o.append(render_governance(m))

    # ── LOCKS ───────────────────────────────────────────────────────────────
    o.append("<section class='panel' id='locks'>")
    if not m["locks"]:
        o.append("<div class='empty'>No results-lock generations found.</div>")
    else:
        o.append(f"<div class='sub'>{len(m['locks'])} lock generation(s). "
                 f"relock_count in state: {e(S.get('relock_count') or '—')}.</div>")
        for lk in m["locks"]:
            o.append(f"<details class='ph completed'><summary><span class='pid'>lock</span>"
                     f"<span class='plab'>{e(lk['ts'])}</span>"
                     f"<span class='meta'>{e(lk['n_files'])} files · {e(lk['diff_lines'])} diff lines</span>"
                     f"</summary><div class='body'>")
            o.append(f"<dl class='kv'><dt>Directory</dt><dd><a class='art' "
                     f"href='{e(os.path.join('..','..',lk['dir']))}'>{e(lk['dir'])}</a></dd></dl>")
            if lk["diff_preview"].strip():
                o.append(f"<h4>relock-diff.txt (first 40 lines)</h4><pre>{e(lk['diff_preview'])}</pre>")
            else:
                o.append("<div class='meta'>No relock diff recorded for this generation.</div>")
            o.append("</div></details>")
    o.append("</section>")

    # ── ARTIFACTS ───────────────────────────────────────────────────────────
    o.append("<section class='panel' id='artifacts'>")
    n_restricted = sum(1 for a in arts if a["safety"] not in ("CLEARED", "unknown"))
    o.append(f"<div class='sub'>{len(arts)} file(s). Links open the file on disk — they resolve "
             f"only when this page is opened in place. {n_restricted} file(s) carry a non-CLEARED "
             f"safety status and are listed without a link, by design.</div>")
    o.append("<div class='toolbar' data-filters><input type='search' placeholder='Filter artifacts by path…'>"
             "<span class='meta'><span class='count'>0</span> shown</span></div>")
    if not arts:
        o.append("<div class='empty'>No artifacts found in the standard output directories.</div>")
    else:
        o.append("<div class='scroll'><table><tr><th>path</th><th>group</th><th>size</th><th>safety</th></tr>")
        for a in arts:
            restricted = a["safety"] not in ("CLEARED", "unknown")
            cell = (f"<span class='locked'>{e(a['path'])}</span>" if restricted
                    else f"<a class='art' href='{e(os.path.join('..','..',a['path']))}'>{e(a['path'])}</a>")
            sev = "b-halted" if restricted else "b-completed" if a["safety"] == "CLEARED" else "b-pending"
            kb = f"{a['size']/1024:.0f} KB" if a["size"] >= 1024 else f"{a['size']} B"
            o.append(f"<tr data-row><td>{cell}</td><td><span class='grp'>{e(a['group'])}</span></td>"
                     f"<td class='meta'>{e(kb)}</td>"
                     f"<td><span class='badge {sev}'>{e(a['safety'])}</span></td></tr>")
        o.append("</table></div>")
    o.append("</section>")

    # ── TRACE ───────────────────────────────────────────────────────────────
    o.append("<section class='panel' id='trace'>")
    allsteps = [s for ph in phases for s in ph["steps"]] + m.get("unphased_steps", [])
    if not allsteps:
        o.append("<div class='empty'>No RAO trace for this run. Skills emit one via "
                 "<code>emit-trace.sh</code>; projects predating trace adoption have none.</div>")
    else:
        o.append("<div class='toolbar' data-filters><input type='search' placeholder='Filter steps…'>"
                 "<select><option value='all'>All statuses</option><option value='ok'>ok</option>"
                 "<option value='fail'>fail</option><option value='skipped'>skipped</option></select>"
                 "<span class='meta'><span class='count'>0</span> shown</span></div>")
        for ph in phases:
            if not ph["steps"]:
                continue
            o.append(f"<h4>Phase {e(ph['id'])} — {e(ph['label'] or '')}</h4>")
            for s in ph["steps"]:
                o.append(f"<div data-row data-status='{e(s.get('status') or '')}'>"
                         + render_steps([s], rel_tx).replace("<h4>RAO steps</h4>", "") + "</div>")
        if m.get("unphased_steps"):
            o.append("<h4>Unphased</h4>")
            for s in m["unphased_steps"]:
                o.append(f"<div data-row data-status='{e(s.get('status') or '')}'>"
                         + render_steps([s], rel_tx).replace("<h4>RAO steps</h4>", "") + "</div>")
    o.append("</section>")

    o.append("<footer>Generated by <code>render-run-html.py</code> from "
             "<code>run-model.json</code> (<code>build-run-model.py</code>). This page is a "
             "generated view — edit the run, not the page. Curated artifacts only; the raw "
             "session transcript is linked per step where rendered and carries its own safety "
             "gate in <code>render-session-transcript.sh</code>.</footer>")
    o.append("<div id='tip' role='status'></div>")
    o.append(f"</div><script>{JS}</script></body></html>")
    return "\n".join(o)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("model")
    ap.add_argument("-o", "--output")
    ap.add_argument("--auto-refresh", type=int, default=0, metavar="SECONDS",
                    help="embed a meta-refresh so an open tab follows a live run "
                         "(0 = off, the default)")
    a = ap.parse_args()
    if not os.path.isfile(a.model):
        print(f"ERROR: model not found: {a.model}", file=sys.stderr)
        return 1
    try:
        with open(a.model) as fh:
            m = json.load(fh)
    except Exception as ex:
        print(f"ERROR: cannot parse model: {ex}", file=sys.stderr)
        return 1
    major = str(m.get("model_version", "0")).split(".")[0]
    if major != "1":
        print(f"ERROR: unsupported model_version {m.get('model_version')} "
              f"(this renderer speaks 1.x). Refusing to render a wrong picture.", file=sys.stderr)
        return 2
    out = a.output or os.path.join(m["project"]["path"], "logs", "run-html", "index.html")
    outdir = os.path.dirname(os.path.abspath(out))
    os.makedirs(outdir, exist_ok=True)
    with open(out, "w") as fh:
        fh.write(build_html(m, outdir, a.auto_refresh))
    print(f"RUN_HTML={out}")
    print(f"PHASES={len(m['phases'])}")
    if a.auto_refresh:
        print(f"AUTO_REFRESH={a.auto_refresh}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
