#!/usr/bin/env python3
"""build-run-model.py — normalize a scholar project directory into run-model.json.

WHY THIS EXISTS
    A finished run scatters its story across ten artifact families: a state
    block, an NDJSON trace, review-evidence records, five audit logs, lock
    generations, review reports, an evidence ledger, and the outputs
    themselves. Reading that story means knowing all ten formats AND the
    auto-research state, trace, gate, and governance formats.

    This module does that once and emits ONE normalized document. Renderers
    (render-run-html.py, and anything later) are pure functions of it. The
    model is the contract; nothing downstream re-walks the project.

ORCHESTRATOR
    auto-research  <proj>/.auto-research/state.json  + the phase-contract.json
                   bundled beside this helper. Rich: per-phase artifact SHAs,
                   route_back_history, transition_decisions, stale_phases.

HONESTY RULES BAKED IN (CLAUDE.md rule 4 — silence is not success)
    * `coverage.degraded_reasons` names every absent source. A run with no
      trace must render as "no trace", never as an empty-but-confident timeline.
    * A phase found in phases_completed but ABSENT from the declared sequence is
      emitted with status "undeclared" rather than dropped. This is live today:
      6.8 and 9c appear in real full-paper runs and are not in _PSTATE_SEQUENCE.
    * Artifacts carry their safety status; a non-CLEARED artifact is listed but
      flagged `previewable: false` so no renderer can inline restricted values.

USAGE
    python3 build-run-model.py <project_dir> [-o out.json] [--orchestrator X]
    Prints RUN_MODEL=<path>, PHASES=<n>, ORCHESTRATOR=<name>.

EXIT CODES
    0 model written   1 usage / project not found   2 no recognizable run state
"""

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone

# 1.4.0 makes digest-verified review-evidence state completions the Agents and
# phase-dispatch source. Legacy dispatch-manifest rows remain optional
# governance/display metadata and can no longer suppress a missing-review flag.
MODEL_VERSION = "1.4.0"


# ── helpers ──────────────────────────────────────────────────────────────────

def read_text(path):
    try:
        with open(path, errors="replace") as fh:
            return fh.read()
    except Exception:
        return None


def read_json(path):
    t = read_text(path)
    if t is None:
        return None
    try:
        return json.loads(t)
    except Exception:
        return None


def read_ndjson(path):
    t = read_text(path)
    if t is None:
        return []
    out = []
    for line in t.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            out.append(json.loads(line))
        except Exception:
            continue
    return out


def find_skill_dir(proj):
    """Locate the plugin tree so we can read the declared phase backbones."""
    env = os.environ.get("SCHOLAR_SKILL_DIR")
    cands = [env] if env else []
    # Walk up from the project: output/<slug> usually sits inside the repo.
    d = os.path.abspath(proj)
    for _ in range(6):
        cands.append(d)
        d = os.path.dirname(d)
    for c in cands:
        if c and os.path.isfile(os.path.join(c, "scripts", "gates", "pipeline-state.sh")):
            return c
    return None


def local_auto_research_skill_dir():
    """Return this vendored skill root without consulting cwd or a parent tree."""
    return os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))


# ── safety sidecar ───────────────────────────────────────────────────────────

def load_safety(proj):
    """Return (sidecar_path, {relpath: STATUS}). Mirrors the guard's upward walk."""
    d = os.path.abspath(proj)
    for _ in range(12):
        p = os.path.join(d, ".claude", "safety-status.json")
        if os.path.isfile(p):
            data = read_json(p)
            if isinstance(data, dict):
                return p, {k: str(v) for k, v in data.items() if k != "_meta"}
            return p, {}
        nd = os.path.dirname(d)
        if nd == d:
            break
        d = nd
    return None, {}


def safety_for(path, proj, table):
    """CLEARED / restricted / unknown for one artifact path."""
    if not table:
        return "unknown"
    ap = os.path.abspath(path)
    rel = os.path.relpath(ap, os.path.abspath(proj))
    for key, status in table.items():
        k = key if os.path.isabs(key) else os.path.join(os.path.abspath(proj), key)
        if os.path.abspath(k) == ap or key == rel:
            return status
    return "unknown"


# ── phase backbones ──────────────────────────────────────────────────────────

def _bash_array(src, name):
    """Extract the quoted tokens of a bash array, comments stripped.

    Handles both the multi-line form (closing `)` alone on a line) and the
    single-line form `NAME=("a" "b")`. Comments are removed BEFORE token
    extraction because these arrays carry long rationale comments that contain
    both parentheses and phase tokens — parsing them naively pulls in tokens
    that were only being discussed, and stops early on a `)` inside prose.
    """
    m = re.search(rf"^{re.escape(name)}=\((.*)$", src, re.M)
    if not m:
        return []
    rest = src[m.start(1):]
    head = rest.split("\n", 1)[0]
    if ")" in head:                                  # single-line array
        body = head[:head.index(")")]
    else:                                            # multi-line, ends on a bare )
        end = re.search(r"^\s*\)\s*$", rest, re.M)
        body = rest[:end.start()] if end else ""
    body = "\n".join(re.sub(r"#.*$", "", ln) for ln in body.splitlines())
    return re.findall(r'"([^"]+)"', body)


def backbone_full_paper(skill_dir):
    """Parse the full-paper phase backbone + SKILL.md labels.

    A phase token is DECLARED if it appears in either of two arrays, and
    reading only the first is a bug this module shipped once already:

      _PSTATE_SEQUENCE  the linear walk pstate_next follows.
      _PSTATE_OPTIONAL  tokens that are legitimate but deliberately OUTSIDE
                        that walk — checkpoints (0.D, 6.2, 6.8), the relock
                        variant (6.5-relock), and 9c, whose work was relocated
                        to Phase 12 in the 2026-05-28 audit with the token kept
                        so pstate_migrate/rebuild does not drop legacy
                        headings.

    Reading only _PSTATE_SEQUENCE made 6.8 and 9c look like "completed phases
    absent from the declared sequence" and this module reported that as drift.
    It was not drift; both are declared, just in the other array. Treating an
    unread source as an absent declaration is the same class of error as
    treating silence as success.

    Ordering: _PSTATE_CHECKPOINTS / _PSTATE_CHECKPOINT_SUCCESSORS are parallel
    arrays giving each checkpoint the phase it must precede, so optional tokens
    land in their real position on the spine rather than being appended.
    """
    seq, labels = [], {}
    if not skill_dir:
        return seq, labels
    txt = read_text(os.path.join(skill_dir, "scripts", "gates", "pipeline-state.sh")) or ""
    seq = _bash_array(txt, "_PSTATE_SEQUENCE")
    optional = _bash_array(txt, "_PSTATE_OPTIONAL")
    ckpts = _bash_array(txt, "_PSTATE_CHECKPOINTS")
    succs = _bash_array(txt, "_PSTATE_CHECKPOINT_SUCCESSORS")
    before = dict(zip(ckpts, succs))

    # Fallback placement for optional tokens that are not checkpoints: put the
    # token after its longest declared prefix (6.5-relock -> after 6.5), and
    # 9c after 9b, its historical slot, so a legacy run reads in run order.
    def insert_at(tok):
        succ = before.get(tok)
        if succ and succ in seq:
            return seq.index(succ)
        base = tok.split("-")[0]                     # 6.5-relock -> after 6.5
        if base in seq:
            return seq.index(base) + 1
        # Same numeric stem: 9c belongs after 9b, not after 9. Insert past the
        # last same-stem sibling that sorts before it.
        stem = re.match(r"[0-9.]+", tok)
        if stem:
            sib = [i for i, q in enumerate(seq)
                   if re.match(r"[0-9.]+", q or "")
                   and re.match(r"[0-9.]+", q).group(0) == stem.group(0)
                   and q < tok]
            if sib:
                return max(sib) + 1
        cands = [i for i, q in enumerate(seq) if tok.startswith(q)]
        return (max(cands) + 1) if cands else len(seq)

    for tok in optional:
        if tok not in seq:
            seq.insert(insert_at(tok), tok)

    sk = read_text(os.path.join(skill_dir, ".claude", "skills",
                                "scholar-full-paper", "SKILL.md")) or ""
    for pid, label in re.findall(r"^#{2,4}\s*Phase\s+([0-9][0-9A-Za-z.\-]*)\s*[:—-]\s*(.+)$",
                                 sk, re.M):
        labels.setdefault(pid.strip(), label.strip().rstrip("#").strip()[:90])
    return seq, labels


def backbone_auto_research(skill_dir):
    """Read the JSON phase contract: ids, names, declared gate, and next-links."""
    local_contract = os.path.abspath(os.path.join(
        os.path.dirname(__file__), "..", "..", "references", "phase-contract.json"))
    c = read_json(local_contract)
    if not c and skill_dir:
        c = read_json(os.path.join(skill_dir, ".claude", "skills", "scholar-auto-research",
                                   "references", "phase-contract.json"))
    if not c:
        return [], {}, {}
    seq, labels, meta = [], {}, {}
    for ph in c.get("phases", []):
        pid = str(ph.get("id"))
        seq.append(pid)
        labels[pid] = str(ph.get("name") or "")
        meta[pid] = {
            "declared_gate": ph.get("gate"),
            "next": ph.get("next"),
            "trigger": ph.get("trigger"),
            "required_outputs": ph.get("required_outputs") or [],
            "review_evidence_policy": ph.get("review_evidence_policy"),
        }
    return seq, labels, meta


# ── state readers ────────────────────────────────────────────────────────────

def state_full_paper(proj):
    txt = read_text(os.path.join(proj, "logs", "project-state.md"))
    if not txt or "=== PIPELINE STATE ===" not in txt:
        return None
    block = txt.split("=== PIPELINE STATE ===", 1)[1]
    def field(name):
        m = re.search(rf"^{re.escape(name)}:\s*(.*)$", block, re.M)
        return m.group(1).strip() if m else ""
    def clist(name):
        return [x.strip() for x in field(name).split(",") if x.strip()]
    excused = {}
    for tok in clist("phases_excused"):
        pid, _, reason = tok.partition(":")
        excused[pid.strip()] = reason.strip()
    return {
        "orchestrator": "full-paper",
        "phases_completed": clist("phases_completed"),
        "current_phase": field("current_phase"),
        "current_phase_status": field("current_phase_status"),
        "relock_count": field("relock_count"),
        "excused": excused,
        "last_updated": field("last_updated"),
        "checksum": field("body_checksum"),
        "route_backs": [],
        "stale_phases": [],
        "phase_records": {},
    }


def state_auto_research(proj):
    s = read_json(os.path.join(proj, ".auto-research", "state.json"))
    if not s:
        return None
    rbs = []
    for rb in s.get("route_back_history") or []:
        rbs.append({
            "from": str(rb.get("from_phase") or rb.get("from") or ""),
            "to": str(rb.get("to_phase") or rb.get("to") or ""),
            "reason": rb.get("reason") or rb.get("note") or "",
            "finding_ids": rb.get("finding_ids") or [],
            "at": rb.get("recorded_at") or rb.get("at") or "",
        })
    pend = s.get("pending_transition") or {}
    return {
        "orchestrator": "auto-research",
        "phases_completed": [str(x) for x in (s.get("phases_completed") or [])],
        "current_phase": str((pend.get("to_phase") if isinstance(pend, dict) else "") or ""),
        "current_phase_status": (s.get("run_mode") or {}).get("mode", ""),
        "relock_count": "",
        "excused": {},
        "last_updated": s.get("updated_at", ""),
        "checksum": s.get("contract_sha256", ""),
        "route_backs": rbs,
        "retry_counts": s.get("route_back_retry_counts") or {},
        "stale_phases": [str(x) for x in (s.get("stale_phases") or [])],
        "phase_records": s.get("phase_records") or {},
        "transition_decisions": s.get("transition_decisions") or [],
        "run_nonce": s.get("run_nonce"),
        "review_attempt_epochs": s.get("review_attempt_epochs") or {},
        "review_evidence_history": s.get("review_evidence_history") or [],
    }


# ── enrichment sources ───────────────────────────────────────────────────────

def load_traces(proj):
    logs = os.path.join(proj, "logs")
    recs = []
    if os.path.isdir(logs):
        for fn in sorted(os.listdir(logs)):
            if fn.startswith("trace-") and fn.endswith(".ndjson"):
                recs.extend(read_ndjson(os.path.join(logs, fn)))
    recs.sort(key=lambda r: (str(r.get("ts") or ""), str(r.get("skill") or ""),
                             r.get("seq") or 0))
    return recs


def load_dispatches(proj):
    """Legacy display metadata; never review-evidence authority."""
    return read_ndjson(os.path.join(proj, "logs", "dispatch-manifest.jsonl"))


def load_registered_review_dispatches(proj, state):
    """Load digest-verified successful reviewer completions from locked state.

    Session files are mutable artifacts, so discovering a dispatch ID in one is
    insufficient.  A row is authoritative only when the current-attempt state
    ledger registers the session and completion and both recorded digests still
    match their files.  Invalid rows are omitted and surfaced as degradation.
    """
    history = state.get("review_evidence_history") or []
    if not isinstance(history, list):
        return [], ["review evidence: state review_evidence_history is not an array"]
    root = os.path.abspath(proj)
    epochs = state.get("review_attempt_epochs") or {}
    rows, degraded, seen = [], [], set()
    completions = [e for e in history if isinstance(e, dict)
                   and e.get("event") == "review_role_completed"]
    for event in completions:
        phase = str(event.get("phase_id") or "")
        role = str(event.get("role") or "")
        session_id = str(event.get("session_id") or "")
        dispatch_id = str(event.get("dispatch_id") or "")
        epoch = epochs.get(phase, 0)
        if event.get("attempt_epoch") != epoch:
            continue
        key = (phase, session_id, role)
        if not all(key) or not dispatch_id or key in seen:
            degraded.append("review evidence: malformed or duplicate current completion "
                            f"for phase {phase or '?'} role {role or '?'}")
            continue
        seen.add(key)
        aborted = any(
            isinstance(e, dict) and e.get("event") == "review_session_aborted"
            and str(e.get("phase_id")) == phase
            and str(e.get("session_id")) == session_id
            for e in history
        )
        if aborted:
            continue
        registrations = [
            e for e in history
            if isinstance(e, dict) and e.get("event") == "review_session_registered"
            and str(e.get("phase_id")) == phase
            and str(e.get("session_id")) == session_id
            and e.get("attempt_epoch") == epoch
        ]
        if len(registrations) != 1:
            degraded.append(f"review evidence: phase {phase}/{role} has no unique "
                            "current session registration")
            continue
        evidence_root = os.path.join(root, "review-evidence")
        candidates = []
        if os.path.isdir(evidence_root):
            for phase_dir in os.listdir(evidence_root):
                candidate = os.path.join(evidence_root, phase_dir, session_id, "session.json")
                if os.path.isfile(candidate):
                    candidates.append(candidate)
        if len(candidates) != 1:
            degraded.append(f"review evidence: phase {phase}/{role} session file is "
                            "missing or ambiguous")
            continue
        session_path = candidates[0]
        session = read_json(session_path)
        if (not isinstance(session, dict)
                or os.path.islink(session_path)
                or _sha256_file(session_path) != registrations[0].get("reservation_sha256")):
            degraded.append(f"review evidence: phase {phase}/{role} registered session "
                            "digest is invalid")
            continue
        reservations = [
            item for item in session.get("reservations", [])
            if isinstance(item, dict)
            and str(item.get("dispatch_id")) == dispatch_id
            and str(item.get("role")) == role
        ]
        if (str(session.get("phase_id")) != phase
                or str(session.get("session_id")) != session_id
                or session.get("attempt_epoch") != epoch
                or session.get("project_run_nonce") != state.get("run_nonce")
                or len(reservations) != 1):
            degraded.append(f"review evidence: phase {phase}/{role} registered session "
                            "identity is invalid")
            continue
        completion_path = os.path.join(os.path.dirname(session_path), "completions", f"{role}.json")
        completion = read_json(completion_path)
        if (not isinstance(completion, dict)
                or os.path.islink(completion_path)
                or _sha256_file(completion_path) != event.get("completion_sha256")):
            degraded.append(f"review evidence: phase {phase}/{role} registered completion "
                            "digest is invalid")
            continue
        reservation = reservations[0]
        if (str(completion.get("dispatch_id")) != dispatch_id
                or str(completion.get("role")) != role
                or completion.get("driver_completion", {}).get("status") != "succeeded"
                or completion.get("report_path") != reservation.get("report_path")
                or completion.get("trace_path") != reservation.get("trace_path")):
            degraded.append(f"review evidence: phase {phase}/{role} completion identity "
                            "is invalid")
            continue
        artifact_invalid = False
        for kind in ("report", "trace"):
            artifact_path = os.path.abspath(os.path.join(root, str(reservation.get(f"{kind}_path") or "")))
            relative_artifact = os.path.relpath(artifact_path, root)
            cursor = root
            symlink_component = False
            for component in relative_artifact.split(os.sep):
                cursor = os.path.join(cursor, component)
                if os.path.islink(cursor):
                    symlink_component = True
                    break
            root_real = os.path.realpath(root)
            artifact_real = os.path.realpath(artifact_path)
            if (not (artifact_real == root_real or artifact_real.startswith(root_real + os.sep))
                    or symlink_component
                    or not os.path.isfile(artifact_path)):
                artifact_invalid = True
                break
            artifact_sha = _sha256_file(artifact_path)
            if (completion.get(f"{kind}_sha256") != artifact_sha
                    or event.get(f"{kind}_sha256") != artifact_sha):
                artifact_invalid = True
                break
        if artifact_invalid:
            degraded.append(f"review evidence: phase {phase}/{role} report/trace binding is invalid")
            continue
        rows.append({
            "phase": phase,
            "agentId": dispatch_id,
            "agent": role,
            "role": role,
            "session_id": session_id,
            "round": str(event.get("round") or session.get("round") or ""),
            "report": str(completion.get("report_path") or reservation.get("report_path") or ""),
            "trace": str(completion.get("trace_path") or ""),
            "attempt_epoch": epoch,
            "registration": "state-digest-verified",
            "completed_at": str(event.get("recorded_at") or ""),
        })
    rows.sort(key=lambda row: (row["phase"], row["round"], row["role"], row["agentId"]))
    return rows, degraded


AUDIT_FILES = {
    "force-complete": "logs/force-complete-audit.md",
    "halt": "logs/halt-audit.md",
    "recheck-bypass": "logs/recheck-bypass-audit.md",
    "state-mutation": "logs/state-mutations.md",
    "hardblock-refusal": "logs/hardblock-refusal-audit.md",
}

# Structured sinks added by the 2026-08-21 gates work. These are NOT prose
# audit logs — they carry fields, so they are parsed rather than line-scraped.
BYPASS_NDJSON = "logs/bypass-audit.ndjson"
ACCEPTANCES_MD = "logs/gate-acceptances.md"
BACKROUTE_JSONL = "logs/back-route-history.jsonl"


def _anom(kind, ts, detail, source):
    """One anomaly row. Phase is recovered from the text when it names one."""
    detail = (detail or "").strip()[:400]
    m = re.search(r"(?:phase|Phase)[ :]*([0-9][0-9A-Za-z.\-]*)", detail)
    return {"kind": kind, "phase": m.group(1) if m else "",
            "detail": detail, "source": source, "ts": ts}


def load_anomalies(proj, state):
    """Every bypass, halt, forced completion and excuse, on one list.

    These live in five separate files today. Surfacing them together is the
    point: they are exactly what the CLAUDE.md discipline rules exist to catch.
    """
    out = []
    # These logs come in three shapes and a scraper that assumes one loses the
    # others. Learned the hard way, twice, on real data:
    #   TABLE     state-mutations.md — prose preamble + a markdown table. Taking
    #             every non-comment line counted the paragraphs as events (33
    #             mutations became 42 "anomalies").
    #   HEADING   halt-audit.md / force-complete-audit.md — pstate_halt writes
    #             `## <ts> — Phase X halted (RED)` and THEN `- **Reason**:`
    #             bullets. The event is the heading. Blanket-skipping `#` lines
    #             and requiring a date on the rest dropped real halts entirely.
    #   FREE-TEXT one dated line per event.
    DATE_RE = r"\d{4}-\d{2}-\d{2}"
    for kind, rel in AUDIT_FILES.items():
        txt = read_text(os.path.join(proj, rel))
        if not txt:
            continue
        pending = None                      # the open HEADING event, if any
        for line in txt.splitlines():
            line = line.strip()
            if not line or set(line) <= set("|- "):
                continue

            if line.startswith("|"):                                  # TABLE
                cells = [c.strip() for c in line.strip("|").split("|")]
                if len(cells) < 2 or not re.match(DATE_RE, cells[0]):
                    continue                                          # header/prose row
                out.append(_anom(kind, cells[0],
                                 " · ".join(c for c in cells[1:] if c), rel))
                continue

            heading = re.match(r"^#{2,6}\s+(.*)$", line)
            if heading:
                body = heading.group(1)
                if re.search(DATE_RE, body):                          # HEADING event
                    ts = (re.search(DATE_RE + r"T[\d:]+Z?", body) or
                          re.search(DATE_RE, body)).group(0)
                    pending = _anom(kind, ts, body, rel)
                    out.append(pending)
                else:
                    pending = None                                    # section title
                continue
            if line.startswith("#"):
                pending = None
                continue

            # A `- **Reason**: …` bullet belongs to the heading above it.
            if pending is not None and line.startswith("-"):
                extra = re.sub(r"^-\s*", "", line)
                if extra and len(pending["detail"]) < 360:
                    pending["detail"] = (pending["detail"] + " — " + extra)[:400]
                continue

            if re.search(DATE_RE, line):                              # FREE-TEXT
                pending = None
                out.append(_anom(kind, "", line, rel))

    # Excused phases: an excuse asserts NOT APPLICABLE, which is an ending the
    # reader must see beside halts and bypasses. (Restored 2026-08-21: an edit
    # to the audit-file scraper above sliced this loop out, and the excuse count
    # silently went to zero.)
    for pid, reason in (state.get("excused") or {}).items():
        out.append({"kind": "excuse", "phase": pid,
                    "detail": reason or "(no reason recorded)",
                    "source": "logs/project-state.md phases_excused", "ts": ""})
    # Bypasses: {ts, gate_id, env_var, reason, user, phase, manuscript_sha256}
    for r in read_ndjson(os.path.join(proj, BYPASS_NDJSON)):
        out.append({
            "kind": "bypass", "phase": str(r.get("phase") or ""),
            "detail": "%s via %s — %s" % (r.get("gate_id") or "?",
                                          r.get("env_var") or "?",
                                          r.get("reason") or "(no reason)"),
            "source": BYPASS_NDJSON, "ts": r.get("ts", ""),
        })
    # PI acceptances: a THIRD ending beside pass and halt. Never counted as
    # resolved — the finding stands, the researcher has accepted it on record.
    acc = read_text(os.path.join(proj, ACCEPTANCES_MD)) or ""
    for finding, numeff, text in re.findall(
            r"^\s*-\s*\[ACCEPTED:\s*([^|\]]+?)\s*\|\s*NUMBER_EFFECT=(YES|NO|UNKNOWN)\s*\]\s*(.+?)\s*$",
            acc, re.M):
        out.append({
            "kind": "accepted", "phase": "",
            "detail": "%s [NUMBER_EFFECT=%s] %s" % (finding.strip(), numeff, text.strip()[:260]),
            "source": ACCEPTANCES_MD, "number_effect": numeff, "ts": "",
        })
    for r in read_ndjson(os.path.join(proj, BACKROUTE_JSONL)):
        directive = str(r.get("directive") or "?")
        # A CLEAR row is not an anomaly — it is the marker that ENDS one. It is
        # carried informationally so the lane reads as episodes rather than as a
        # run of unexplained hops.
        kind = "episode-boundary" if directive.startswith("CLEAR:") else "back-route"
        out.append({
            "kind": kind, "phase": "",
            "detail": "%s (x%s) %s" % (directive, r.get("count") or 1,
                                       (r.get("digest") or "")[:120]),
            "source": BACKROUTE_JSONL, "ts": r.get("ts", ""),
        })
    # Idiom-override receipts (R3 #13): each one records a human deliberately
    # taking a flagged idiom anyway. That is exactly the class of decision this
    # lane exists to surface.
    for r in read_ndjson(os.path.join(proj, "logs", "idiom-override-receipts.ndjson")):
        out.append({
            "kind": "idiom-override", "phase": str(r.get("phase") or ""),
            "detail": "%s — %s" % (r.get("rule") or r.get("id") or "?",
                                   (r.get("reason") or r.get("why") or "(no reason)"))[:400],
            "source": "logs/idiom-override-receipts.ndjson", "ts": r.get("ts", ""),
        })
    # DIGEST_DEGRADED: phase-verify --digest could not write its report, so the
    # run's own observability degraded. Only the FIRST line of each report is
    # read — the reports themselves are large and are not inventoried.
    _rep_dir = os.path.join(proj, "logs", "phase-verify-reports")
    if os.path.isdir(_rep_dir):
        try:
            _reps = [os.path.join(_rep_dir, f) for f in os.listdir(_rep_dir)]
        except OSError:
            _reps = []
        for f in _newest_first(_reps)[:64]:
            try:
                with open(f, errors="replace") as fh:
                    first = fh.readline().strip()
            except OSError:
                continue
            if "DIGEST_DEGRADED" in first:
                out.append({"kind": "digest-degraded", "phase": "",
                            "detail": first[:400],
                            "source": _rel(proj, f), "ts": ""})
    for pid in state.get("stale_phases") or []:
        out.append({"kind": "stale", "phase": pid,
                    "detail": "marked stale — its inputs changed after completion",
                    "source": ".auto-research/state.json stale_phases", "ts": ""})
    return out


def load_locks(proj):
    root = os.path.join(proj, "results-locked")
    if not os.path.isdir(root):
        return []
    locks = []
    for ts in sorted(os.listdir(root)):
        d = os.path.join(root, ts)
        if not os.path.isdir(d):
            continue
        man = read_json(os.path.join(d, "manifest.json"))
        diff = read_text(os.path.join(d, "relock-diff.txt")) or ""
        n = 0
        if isinstance(man, dict):
            for key in ("files", "entries", "artifacts"):
                if isinstance(man.get(key), (list, dict)):
                    n = len(man[key]); break
        locks.append({
            "ts": ts, "dir": os.path.relpath(d, proj), "n_files": n,
            "diff_lines": len([l for l in diff.splitlines() if l.strip()]),
            "diff_preview": "\n".join(diff.splitlines()[:40]),
        })
    return locks


SEVERITY = ("CRITICAL", "MAJOR", "MODERATE", "MINOR", "ADVISORY")


def load_reviews(proj):
    d = os.path.join(proj, "reviews")
    if not os.path.isdir(d):
        return []
    out = []
    for fn in sorted(os.listdir(d)):
        if not fn.endswith(".md"):
            continue
        txt = read_text(os.path.join(d, fn)) or ""
        m = re.match(r"phase-([0-9][0-9A-Za-z.\-]*)-iter(\d+)-(.+)\.md$", fn)
        out.append({
            "file": os.path.join("reviews", fn),
            "phase": m.group(1) if m else "",
            "iteration": m.group(2) if m else "",
            # Fall back to the filename minus any trailing ISO date, so the
            # chart axis reads "peer-review-quant" not
            # "peer-review-quant-2026-04-29".
            "dimension": (m.group(3) if m
                          else re.sub(r"[-_]?\d{4}-\d{2}-\d{2}$", "", fn[:-3])),
            "severities": {s: len(re.findall(rf"\b{s}\b", txt)) for s in SEVERITY},
            "resolved": len(re.findall(r"\bRESOLVED\b", txt)),
            "number_effect": len(re.findall(r"\bNUMBER_EFFECT\b", txt)),
        })
    return out


ARTIFACT_DIRS = ("drafts", "tables", "figures", "scripts", "analysis", "design",
                 "verify", "reviews", "citations", "compute", "reports",
                 "replication-package", "evidence", "manuscript", "polish")
PREVIEWABLE_EXT = (".md", ".txt", ".csv", ".json", ".ndjson", ".jsonl", ".r", ".py",
                   ".sh", ".tex", ".bib", ".yaml", ".yml", ".log", ".do")
IMAGE_EXT = (".png", ".jpg", ".jpeg", ".gif", ".svg", ".webp")


def load_artifacts(proj, safety_table, limit=4000):
    out, truncated = [], False
    for d in ARTIFACT_DIRS:
        root = os.path.join(proj, d)
        if not os.path.isdir(root):
            continue
        for dirpath, dirnames, filenames in os.walk(root):
            dirnames[:] = [x for x in dirnames if not x.startswith(".")]
            for fn in sorted(filenames):
                if fn.startswith("."):
                    continue
                if len(out) >= limit:
                    truncated = True
                    break
                full = os.path.join(dirpath, fn)
                rel = os.path.relpath(full, proj)
                ext = os.path.splitext(fn)[1].lower()
                status = safety_for(full, proj, safety_table)
                try:
                    size = os.path.getsize(full)
                except OSError:
                    size = 0
                out.append({
                    "path": rel, "group": d, "ext": ext, "size": size,
                    "safety": status,
                    # A restricted artifact is LISTED but never previewable, so a
                    # renderer cannot inline values the data guard exists to contain.
                    "previewable": (status in ("CLEARED", "unknown")
                                    and ext in PREVIEWABLE_EXT and size <= 400_000),
                    "is_image": ext in IMAGE_EXT,
                })
            if truncated:
                break
    return out, truncated




# ── chart aggregates ─────────────────────────────────────────────────────────
# Computed here, not in the renderer: the model is the contract, and a second
# consumer (a TUI, a run-diff) should not have to re-derive these.

def build_gate_index(roster, runs, extra):
    """One row per gate: where it is declared, how often it ran, verdict mix.

    The interesting rows are the extremes — a gate declared on six phases that
    never ran, and a gate that runs constantly and is always INERT. Both look
    like "fine" in a per-phase view and only become visible when the gate is
    the unit of analysis.
    """
    idx = {}
    for pid, gates in roster.items():
        for g in gates:
            idx.setdefault(g, {"gate": g, "phases": [], "runs": 0,
                               "verdicts": {}, "declared": True})["phases"].append(pid)
    for g in extra:
        idx.setdefault(g, {"gate": g, "phases": [], "runs": 0,
                           "verdicts": {}, "declared": True, "wired_only": True})
    for r in runs:
        e = idx.setdefault(r["gate"], {"gate": r["gate"], "phases": [], "runs": 0,
                                       "verdicts": {}, "declared": False})
        e["runs"] += 1
        e["verdicts"][r["verdict"]] = e["verdicts"].get(r["verdict"], 0) + 1
    for e in idx.values():
        e["phases"] = sorted(set(e["phases"]))
    return sorted(idx.values(), key=lambda e: (-e["runs"], e["gate"]))


def build_charts(phases, reviews, locks, gate_runs=()):
    sev_by_dim = {}
    for r in reviews:
        d = r.get("dimension") or "unknown"
        row = sev_by_dim.setdefault(d, {k: 0 for k in SEVERITY})
        for k in SEVERITY:
            row[k] += r["severities"].get(k, 0)
    severity = [dict(dimension=d, **v) for d, v in sorted(sev_by_dim.items())
                if any(v.values())]

    steps = []
    for ph in phases:
        if not ph["steps"]:
            continue
        ok = sum(1 for s in ph["steps"] if s.get("status") == "ok")
        fail = sum(1 for s in ph["steps"] if s.get("status") == "fail")
        skip = sum(1 for s in ph["steps"] if s.get("status") == "skipped")
        steps.append({"phase": ph["id"], "ok": ok, "fail": fail, "skipped": skip,
                      "total": len(ph["steps"])})

    gv = {}
    for r in gate_runs:
        gv[r["verdict"]] = gv.get(r["verdict"], 0) + 1
    gate_verdicts = [{"verdict": k, "n": v} for k, v in
                     sorted(gv.items(), key=lambda kv: -kv[1])]

    counts = {}
    for ph in phases:
        counts[ph["status"]] = counts.get(ph["status"], 0) + 1
    done = counts.get("completed", 0) + counts.get("excused", 0)
    total = len(phases) or 1

    return {
        "severity_by_dimension": severity,
        "steps_by_phase": steps,
        "gate_verdicts": gate_verdicts,
        "lock_churn": [{"ts": l["ts"], "n_files": l["n_files"],
                        "diff_lines": l["diff_lines"]} for l in locks],
        "status_counts": counts,
        "progress": {"done": done, "total": len(phases),
                     "pct": round(100.0 * done / total, 1)},
    }


# ── report assets (the "showcase" half) ──────────────────────────────────────
# Only CLEARED artifacts are ever embedded. A restricted file is recorded in
# `withheld` with its status so the page can say what it is NOT showing —
# omission is safe, silent omission is not.

TABLE_EXT = (".csv", ".tsv")
DOC_EXT = (".md", ".markdown", ".txt")
EMBED_IMG_EXT = (".png", ".jpg", ".jpeg", ".gif", ".webp", ".svg")

MAX_TABLE_ROWS = 200
MAX_DOC_CHARS = 120_000
MAX_IMG_BYTES = 3_000_000


def _is_cleared(a):
    """May this artifact be embedded in a travelling bundle?

    The sidecar records INGESTED INPUTS (data/raw/*, materials/*) — the files
    scholar-init copied in. Pipeline PRODUCTS (tables/, figures/, drafts/, …)
    have no sidecar entry by design, because nothing ingested them; under the
    LOCAL_MODE execution contract they carry aggregates, not rows.

    So "no entry" must not be read as "unreviewed sensitive data". Treating it
    that way withheld all 58 artifacts of a real project and produced an empty
    report — safe, but useless, and useless enough that nobody would use the
    safe path.

    The scan scope already excludes data/ and materials/ (see ARTIFACT_DIRS), so
    everything reaching here is a derived product. The rule:
      * an EXPLICIT sidecar entry is obeyed exactly — only CLEARED embeds;
      * no entry -> derived product -> embeddable.
    An explicitly restricted file (e.g. an interim extract auto-registered as
    LOCAL_MODE) is therefore still withheld, which is the case that matters.
    """
    return a.get("safety") in ("CLEARED", "unknown")


def parse_table(path, limit=MAX_TABLE_ROWS):
    import csv as _csv
    try:
        with open(path, newline="", errors="replace") as fh:
            sniff = fh.read(8192); fh.seek(0)
            delim = "\t" if path.lower().endswith(".tsv") else ","
            try:
                delim = _csv.Sniffer().sniff(sniff, delimiters=",;\t").delimiter
            except Exception:
                pass
            rows = []
            for i, row in enumerate(_csv.reader(fh, delimiter=delim)):
                if i > limit:
                    break
                rows.append(row)
    except Exception:
        return None
    if not rows:
        return None
    head, body = rows[0], rows[1:limit + 1]
    ncol = max(len(r) for r in rows)
    head = (head + [""] * ncol)[:ncol]
    body = [(r + [""] * ncol)[:ncol] for r in body]
    return {"columns": head, "rows": body, "truncated": len(body) >= limit}


# Governance logs are pipeline METADATA, not pipeline products: they carry
# commands, reviewer prose and holder names. They are linked by path and never
# inlined, and in --bundle mode their bytes must not travel inside the page.
# This needs an ACTIVE exclusion, not an omission: `reports/` is already in
# ARTIFACT_DIRS and build_report inlines report Markdown into report.documents,
# and the ICR gate's own sources are reports/code-review-*-iter*.md.
# Anchored on the FAMILY, not on an incidental token. The first cut required an
# `-iter` segment in a code-review report name, so every real filename the
# pipeline actually writes escaped it — `code-review-fix-proposals-<date>.md`
# (phase-code-review.md), `code-review-pre-execution-*.md` (SKILL.md), legacy
# `code-review-<dim>.md`, and anything in a nested subdirectory. The smoke test
# happened to plant the one name that DID match, so the suite passed while the
# real ones leaked.
GOVERNANCE_SOURCE_RE = re.compile(
    r"^(?:"
    r"logs/(?:findings\.ndjson|surface-leases\.ndjson|back-route-history\.(?:ndjson|jsonl)"
    r"|gate-acceptances\.md|dispatch-manifest\.jsonl"
    r"|idiom-override-receipts\.ndjson|gate-runs\.ndjson)"
    r"|logs/phase-verify-reports/.*"
    r"|logs/phase-notes/.*"
    r"|seams/.*"
    r"|briefs/.*"
    r"|code-review/.*"
    r"|(?:.*/)?reports/(?:.*/)?code-review-.*"
    r"|(?:.*/)?reports/(?:.*/)?fix-brief-.*"
    r"|(?:.*/)?reviews/(?:.*/)?phase-[0-9][0-9A-Za-z.]*-iter.*"
    r"|peer-review/agents/.*"
    r")$")

# Matched separately: a leading dot must not be stripped, which is what
# lstrip("./") did — it removes every leading "." and "/" character, so
# ".loop-state.json" became "loop-state.json" and the branch was unreachable.
GOVERNANCE_SOURCE_EXACT = frozenset((".loop-state.json",))


def is_governance_source(rel):
    """True for a path that belongs to the governance layer (linked, never
    inlined, never bundled)."""
    rel = (rel or "").strip()
    while rel.startswith("./"):
        rel = rel[2:]
    return rel in GOVERNANCE_SOURCE_EXACT or bool(GOVERNANCE_SOURCE_RE.match(rel))


def build_report(artifacts, proj, embed):
    """Group CLEARED artifacts into tables / figures / documents for the report
    view. `embed` also inlines bytes as data: URIs so the page is portable."""
    import base64, mimetypes
    tables, figures, docs, withheld = [], [], [], []
    n_gov_excluded = 0
    for a in artifacts:
        ext, rel = a["ext"], a["path"]
        full = os.path.join(proj, rel)
        interesting = (ext in TABLE_EXT or ext in DOC_EXT or a["is_image"]
                       or ext == ".pdf")
        if not interesting:
            continue
        if is_governance_source(rel):
            # Excluded BEFORE clearance/embedding: a governance log is not a
            # derived pipeline product, so the derived-product embed rule must
            # never reach it.
            n_gov_excluded += 1
            continue
        if not _is_cleared(a):
            withheld.append({"path": rel, "safety": a["safety"],
                             "reason": "explicitly restricted in .claude/safety-status.json",
                             "kind": "table" if ext in TABLE_EXT else
                                     "figure" if a["is_image"] or ext == ".pdf" else "document"})
            continue
        if ext in TABLE_EXT and a["group"] in ("tables", "analysis", "results-locked"):
            t = parse_table(full)
            if t:
                tables.append({"path": rel, "group": a["group"], **t})
        elif a["is_image"] or ext == ".pdf":
            fig = {"path": rel, "group": a["group"], "ext": ext,
                   "size": a["size"], "data_uri": None}
            if embed and a["is_image"] and a["size"] <= MAX_IMG_BYTES:
                try:
                    mime = mimetypes.guess_type(full)[0] or "application/octet-stream"
                    with open(full, "rb") as fh:
                        fig["data_uri"] = "data:%s;base64,%s" % (
                            mime, base64.b64encode(fh.read()).decode("ascii"))
                except Exception:
                    pass
            figures.append(fig)
        elif ext in DOC_EXT and a["group"] in ("drafts", "manuscript", "analysis",
                                               "design", "reports", "polish"):
            txt = read_text(full)
            if txt:
                docs.append({"path": rel, "group": a["group"],
                             "text": txt[:MAX_DOC_CHARS],
                             "truncated": len(txt) > MAX_DOC_CHARS,
                             "words": len(txt.split())})
    return {"tables": tables, "figures": figures, "documents": docs,
            "withheld": withheld, "embedded": bool(embed),
            "governance_sources_excluded": n_gov_excluded}




# ── gates: declared roster, observed runs, verdict vocabulary ────────────────
# rc -> verdict is the suite's own convention, and INERT is load-bearing:
# "a gate that skips and a gate that checks and finds nothing clean were the
# same output" (gates commit 2026-08-21). Rendering both as a silent pass is
# exactly the confusion the INERT campaign removed, so the model keeps them
# distinct all the way to the page.
RC_VERDICT = {0: "GREEN", 1: "RED", 2: "YELLOW", 3: "INERT"}


def rc_to_verdict(rc):
    try:
        rc = int(rc)
    except (TypeError, ValueError):
        return "UNKNOWN"
    return RC_VERDICT.get(rc, "ERROR")


def load_gate_roster(skill_dir):
    """Declared gates per phase, from the auto-generated roster doc.

    `gates-invoked-per-phase.md` is generated from phase-verify.sh by
    scripts/audit/enumerate-gates-per-phase.py and is the authoritative list of
    what each phase's case-arm invokes. Parsing the doc rather than re-deriving
    it from phase-verify keeps one source of truth; if the doc is stale the fix
    is to regenerate it, not to grow a second parser here.

    Returns (per_phase, aliases, extra) where `extra` is the "Additional wired
    gates" set the case-arm walk structurally cannot capture.
    """
    if not skill_dir:
        return {}, {}, []
    path = os.path.join(skill_dir, ".claude", "skills", "scholar-full-paper",
                        "references", "gates-invoked-per-phase.md")
    txt = read_text(path)
    if not txt:
        return {}, {}, []
    # Split on the SECTION HEADING, not the phrase: the intro paragraph also
    # says "Additional wired gates", and partitioning on the first occurrence
    # put the entire table into the tail — 0 declared gates, which reads
    # identically to "no roster found".
    m = re.search(r"^#{1,4}\s*Additional wired gates", txt, re.M)
    body, tail = (txt[:m.start()], txt[m.start():]) if m else (txt, "")
    per_phase, aliases = {}, {}
    for pid, alias_cell, gate_cell in re.findall(
            r"^\|\s*`([^`]+)`\s*\|([^|]*)\|(.*?)\|\s*$", body, re.M):
        gates = re.findall(r"`([a-z0-9._-]+\.(?:sh|py))`", gate_cell)
        per_phase[pid.strip()] = sorted(set(gates))
        al = [a for a in re.findall(r"`([^`]+)`", alias_cell)
              if not a.endswith((".sh", ".py"))]
        if al:
            aliases[pid.strip()] = al
    extra = sorted(set(re.findall(r"`([a-z0-9._-]+\.sh)`", tail))) if tail else []
    return per_phase, aliases, extra


def load_auto_research_gate_roster(phase_meta):
    """Build the auto-research phase-gate roster from its local JSON contract."""
    per_phase = {}
    for pid, meta in (phase_meta or {}).items():
        declared = str((meta or {}).get("declared_gate") or "").strip()
        if declared:
            per_phase[str(pid)] = [declared.split()[0]]
    return per_phase, {}, []


def load_gate_runs(proj, traces):
    """Observed gate invocations.

    Two sources, best first:
      1. logs/gate-runs.ndjson — written by the phase-verify wrapper. Carries
         every invocation with its rc, so GREEN gates are visible too.
      2. the RAO trace — only the gate calls a skill happened to log as a step.
         Partial by construction: a gate that ran without being traced is
         invisible here, which is why source 1 exists.

    Returns (runs, source) so the page can state which it is looking at rather
    than implying the coverage of source 1 when it only has source 2.
    """
    runs = read_ndjson(os.path.join(proj, "logs", "gate-runs.ndjson"))
    if runs:
        out = []
        for r in runs:
            rc = r.get("rc")
            out.append({
                "gate": str(r.get("gate") or ""),
                "phase": str(r.get("phase") or ""),
                "rc": rc,
                "verdict": r.get("verdict") or rc_to_verdict(rc),
                "ts": r.get("ts", ""),
                "ms": r.get("ms"),
                "origin": "gate-runs",
            })
        return out, "gate-runs.ndjson"

    # Fallback: mine the trace for steps whose action names a gate script.
    out = []
    for rec in traces:
        act = str(rec.get("action") or "")
        m = re.search(r"([a-z0-9._-]+\.(?:sh|py))", act)
        if not m or "check" not in m.group(1) and not m.group(1).endswith(
                ("-lint.sh", "-verify.sh", "-gate.sh", "-route.sh")):
            continue
        obs = str(rec.get("observation") or "")
        v = next((k for k in ("CRITICAL", "RED", "YELLOW", "GREEN", "INERT") if k in obs), None)
        if v == "CRITICAL":
            v = "RED"
        if not v:
            v = {"ok": "GREEN", "fail": "RED", "skipped": "INERT"}.get(rec.get("status"), "UNKNOWN")
        out.append({"gate": m.group(1), "phase": str(rec.get("phase") or ""),
                    "rc": None, "verdict": v, "ts": rec.get("ts", ""),
                    "ms": None, "origin": "trace"})
    return out, ("trace (partial)" if out else "none")


# ── governance sinks (RCA Rounds 1–3 machinery) ──────────────────────────────
#
# DERIVED VIEW, NEVER AUTHORITY. These loaders display what the sinks RECORD and
# what the sinks' own checkers COMPUTE. The model never re-implements gate
# verdict logic: no model-side silent-mutation detection, no zombie aging, no
# seam re-hashing, no receipt chain validation. Where a classification exists
# only inside a checker, the model consumes that checker read-only (structured
# mode, timeout-bounded) or omits the classification and says so.
#
# ABSENCE IS A COVERAGE LINE, NEVER A ZERO. A loader returns (None, [reason])
# when its source does not exist, so the section key is simply absent and the
# banner explains why. An EMPTY source is a different thing: it is adopted, and
# its zeros are real.

GOV_CAP_BRIEFS = 100
GOV_CAP_RECEIPTS = 100
GOV_CAP_SEAMS = 64
GOV_BYTE_CAP = 1048576          # per-file read cap; larger files are skipped, loudly
GOV_FINDING_STATES = ("OPEN", "FIXED", "VERIFIED", "ACCEPTED", "ESCALATED", "WITHDRAWN")


def _gates_dir():
    """The gate scripts shipped BESIDE this builder (mirror-safe)."""
    return os.path.dirname(os.path.abspath(__file__))


def _gov_timeout():
    try:
        return max(1, int(os.environ.get("SCHOLAR_RUNVIZ_CHECKER_TIMEOUT", "20")))
    except (TypeError, ValueError):
        return 20


def _run_checker(script, args, cwd=None):
    """Read-only invocation of a gate. -> (state, rc, stdout).

    state is "ok" only when the gate ran to completion; "absent", "timeout" and
    "error" are the three ways it can fail to produce a verdict, and every one
    of them must reach the caller as unassessed rather than a fabricated pass.
    """
    path = os.path.join(_gates_dir(), script)
    if not os.path.isfile(path):
        return "absent", None, ""
    try:
        p = subprocess.run(["bash", path] + list(args),
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                           timeout=_gov_timeout(), cwd=cwd)
    except subprocess.TimeoutExpired:
        return "timeout", None, ""
    except Exception:
        return "error", None, ""
    return "ok", p.returncode, p.stdout.decode("utf-8", "replace")


def _too_big(path):
    try:
        return os.path.getsize(path) > GOV_BYTE_CAP
    except OSError:
        return False


def _sink_state(path, kind="file"):
    """(state, detail) for a governance source.

    "The run never adopted this" and "this is here but I could not read it" are
    different statements about a project, and only the first is a fact about the
    RUN. Gating on os.path.isfile alone collapsed them: a directory standing
    where a ledger belongs, or a chmod-000 file, was reported to the reader as
    "not adopted" — a false statement about what the run did.
    """
    if not os.path.exists(path):
        return "absent", ""
    if kind == "file":
        if os.path.isdir(path):
            return "wrong-type", "a directory stands where a file is expected"
        if not os.path.isfile(path):
            return "wrong-type", "not a regular file"
    else:
        if not os.path.isdir(path):
            return "wrong-type", "not a directory"
    if not os.access(path, os.R_OK):
        return "unreadable", "permission denied"
    return "ok", ""


def _newest_first(paths):
    def key(p):
        try:
            return os.path.getmtime(p)
        except OSError:
            return 0
    return sorted(paths, key=key, reverse=True)


def _rel(proj, path):
    try:
        return os.path.relpath(path, proj)
    except ValueError:
        return path


def _sha256_file(path):
    try:
        h = hashlib.sha256()
        with open(path, "rb") as fh:
            for chunk in iter(lambda: fh.read(65536), b""):
                h.update(chunk)
        return h.hexdigest()
    except OSError:
        return None


def _ndjson_with_malformed(path):
    """read_ndjson, but the dropped lines are COUNTED. A silently skipped bad
    line is the difference between 'zero findings' and 'a ledger we could not
    read', and those must never render the same."""
    txt = read_text(path)
    if txt is None:
        return None, 0
    rows, bad = [], 0
    for line in txt.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
        except Exception:
            bad += 1
            continue
        if isinstance(obj, dict):
            rows.append(obj)
        else:
            bad += 1
    return rows, bad


# ── findings ledger ──────────────────────────────────────────────────────────

def load_findings(proj):
    """logs/findings.ndjson as a CHRONOLOGICAL lifecycle.

    Deliberately NOT per-iteration bars: the ledger's required keys are only
    id/ts/status/locus/report; `iter` is optional and its namespace is
    loop-scoped (PM35- lines belong to the pre-mortem loop, not the code-review
    one). Iteration aggregation therefore happens ONLY over lines that actually
    carry an iter field, and says how many those were.
    """
    path = os.path.join(proj, "logs", "findings.ndjson")
    st, _d = _sink_state(path)
    if st != "ok":
        return None, [_sink_absent("findings ledger", path)]
    if _too_big(path):
        return None, [_degrade("findings ledger: present but larger than the %d-byte read "
                               "cap — NOT read, so nothing below is derived from it"
                               % GOV_BYTE_CAP)]
    rows, malformed = _ndjson_with_malformed(path)
    if rows is None:
        return None, [_degrade("findings ledger: logs/findings.ndjson unreadable")]
    n_lines_total = len(rows) + malformed

    order, by_id, rejected = [], {}, 0
    for r in rows:
        fid = str(r.get("id") or "").strip()
        # The LEDGER GATE's own line validity (findings-ledger-check.sh R2/R3):
        # required keys id/ts/status/locus/report, and a status inside the closed
        # vocabulary. A line the gate rejects never lands in its replay, so
        # counting it here produced a different lifecycle from the gate's — and
        # a smaller open count than the truth.
        _st = str(r.get("status") or "").strip().upper()
        if (not fid or not r.get("ts") or not _st or not r.get("locus")
                or not r.get("report") or _st not in GOV_FINDING_STATES):
            rejected += 1
            continue
        rec = by_id.get(fid)
        if rec is None:
            rec = {"id": fid, "transitions": [], "latest": None, "locus": "",
                   "cls": "", "invariant": False, "reopens": 0,
                   "iter": None, "iter_basis": None, "report": ""}
            by_id[fid] = rec
            order.append(fid)
        status = _st
        prev = rec["latest"]
        # Ledger (append) order is the authority here, exactly as
        # findings-ledger-check.sh replays it. ts is carried for display but is
        # never used to re-order: a malformed or absent ts must not silently
        # reshuffle a lifecycle.
        rec["transitions"].append({"ts": str(r.get("ts") or ""), "status": status})
        # A regression re-OPEN is an OPEN whose PRIOR latest state was already
        # closed-ish — the same rule fix-induced-check.sh documents.
        if status == "OPEN" and prev in ("FIXED", "VERIFIED"):
            rec["reopens"] += 1
        rec["latest"] = status
        for k, dst in (("locus", "locus"), ("class", "cls"), ("report", "report")):
            v = r.get(k)
            if v:
                rec[dst] = str(v)
        if r.get("invariant"):
            rec["invariant"] = True
        if r.get("iter") not in (None, ""):
            rec["iter"] = str(r.get("iter"))          # VERBATIM — never inferred
            rec["iter_basis"] = "ledger-iter-field"

    findings = [by_id[f] for f in order]
    totals = {}
    for rec in findings:
        totals[rec["latest"] or "UNKNOWN"] = totals.get(rec["latest"] or "UNKNOWN", 0) + 1
    with_iter = [rec for rec in findings if rec["iter"] is not None]
    # `iter` is LOOP-SCOPED: a PM35-* pre-mortem finding's iteration 1 and a
    # code-review finding's iteration 1 are different rounds of different loops.
    # Bucketing them together merged two namespaces into one bar.
    by_iter = {}
    for rec in with_iter:
        loop = "premortem" if rec["id"].startswith("PM35-") else "code-review"
        b = by_iter.setdefault(loop, {}).setdefault(rec["iter"], {})
        b[rec["latest"]] = b.get(rec["latest"], 0) + 1

    deg = []
    unusable = malformed + rejected
    if malformed:
        deg.append(_degrade("findings ledger: %d line(s) could not be parsed and are "
                            "excluded from every count below" % malformed))
    if rejected:
        deg.append(_degrade("findings ledger: %d line(s) are missing a required key "
                            "(id/ts/status/locus/report) or carry a status outside the "
                            "closed vocabulary — findings-ledger-check.sh rejects these, "
                            "so they are excluded here too" % rejected))
    # A ledger whose every line is unusable is NOT "zero findings filed". Saying
    # so — as the panel's own empty-state text did — is the exact null-as-zero
    # error the rest of this module exists to prevent.
    unreadable_ledger = bool(unusable) and not findings
    if unreadable_ledger:
        deg.append(_degrade("findings ledger: adopted, but NONE of its %d line(s) are "
                            "usable — the open-finding count is UNKNOWN, not zero"
                            % n_lines_total))
    sec = {
        "present": True,
        "path": _rel(proj, path),
        "n_lines_total": n_lines_total,
        "n_usable": len(rows) - rejected,
        "n_malformed": malformed,
        "n_rejected_by_gate_rules": rejected,
        "usable_unknown": unreadable_ledger,
        "findings": findings,
        "totals_by_state": totals,
        "n_open": None if unreadable_ledger else totals.get("OPEN", 0),
        "n_open_basis": "unknown (no usable ledger line)" if unreadable_ledger else "ledger",
        "n_with_iter": len(with_iter),
        "by_iter": by_iter,
        "iter_note": ("aggregated over %d of %d finding(s) that carry an iter field, "
                      "bucketed per loop (pre-mortem ids are a separate namespace)"
                      % (len(with_iter), len(findings))),
        "vocabulary": list(GOV_FINDING_STATES),
    }
    return sec, deg


# ── surface leases ───────────────────────────────────────────────────────────

def load_leases(proj):
    """logs/surface-leases.ndjson as LITERAL events, plus the gate's own
    classifications.

    The model records spans, holders, writes and recorded violations exactly as
    the ledger states them. It does NOT decide what a zombie is or whether a
    file moved silently: those judgements belong to surface-lease.sh, and they
    enter the model only through `check --emit-json`.
    """
    path = os.path.join(proj, "logs", "surface-leases.ndjson")
    st, _d = _sink_state(path)
    if st != "ok":
        return None, [_sink_absent("surface leases", path)]
    if _too_big(path):
        return None, [_degrade("surface leases: present but larger than the %d-byte read "
                               "cap — NOT read" % GOV_BYTE_CAP)]
    rows, malformed = _ndjson_with_malformed(path)
    if rows is None:
        return None, [_degrade("surface leases: logs/surface-leases.ndjson unreadable")]

    paths, order, snapshots = {}, [], []
    for r in rows:
        ev = str(r.get("event") or "")
        if ev == "snapshot":
            files = r.get("files") if isinstance(r.get("files"), dict) else {}
            snapshots.append({"round": str(r.get("round") or ""),
                              "ts": str(r.get("ts") or ""), "n_files": len(files)})
            continue
        p = str(r.get("path") or "")
        if not p:
            malformed += 1
            continue
        rec = paths.get(p)
        if rec is None:
            rec = {"path": p, "holder": "", "open": False, "n_acquires": 0,
                   "n_writes": 0, "n_violations": 0, "last_activity_ts": "",
                   "spans": [], "classifications": [], "classification_basis":
                   "not-assessed (gate not consulted)"}
            paths[p] = rec
            order.append(p)
        ts = str(r.get("ts") or "")
        violation = bool(r.get("violation"))
        if ev == "acquire":
            rec["n_acquires"] += 1
            rec["holder"] = str(r.get("holder") or "")
            rec["open"] = True
            rec["spans"].append({"holder": rec["holder"], "acquired": ts, "released": None})
            rec["last_activity_ts"] = ts
        elif ev == "write":
            rec["n_writes"] += 1
            if violation:
                rec["n_violations"] += 1
            else:
                rec["last_activity_ts"] = ts
        elif ev == "release":
            rec["open"] = False
            for span in reversed(rec["spans"]):
                if span["released"] is None:
                    span["released"] = ts
                    break

    # The ONLY source of zombie / silent-mutation labels.
    state, rc, out = _run_checker("surface-lease.sh", [proj, "check", "--emit-json"])
    checker = {"state": "unassessed", "reason": "", "verdict": None, "rc": rc}
    deg = []
    if state != "ok":
        checker["reason"] = "surface-lease.sh check --emit-json %s" % state
        deg.append("surface leases: lease classifications unassessed (%s) — spans are "
                   "shown with their recorded activity and no zombie/silent-mutation "
                   "labels" % state)
    elif rc not in (0, 1, 2, 3):
        checker["reason"] = "unexpected exit %s" % rc
        deg.append("surface leases: lease gate exited %s, outside its documented "
                   "0/1/2/3 contract — classifications unassessed" % rc)
    else:
        try:
            data = json.loads(out.strip() or "{}")
        except Exception:
            data = None
        if not isinstance(data, dict) or "paths" not in data:
            checker["reason"] = "output was not the documented JSON record set"
            deg.append("surface leases: lease gate produced no parseable record set — "
                       "classifications unassessed")
        else:
            checker.update({"state": "assessed", "verdict": data.get("verdict"),
                            "rc": data.get("rc", rc),
                            "stale_hours_threshold": data.get("stale_hours_threshold"),
                            "violations": data.get("violations"),
                            "silent_mutations": data.get("silent_mutations"),
                            "zombie_leases": data.get("zombie_leases")})
            for pr in data.get("paths") or []:
                if not isinstance(pr, dict):
                    continue
                rec = paths.get(str(pr.get("path") or ""))
                if rec is None:
                    continue
                rec["classifications"] = list(pr.get("classifications") or [])
                rec["classification_basis"] = str(pr.get("basis") or "")
                rec["age_hours"] = pr.get("age_hours")
                if pr.get("last_activity_ts"):
                    rec["last_activity_ts"] = str(pr.get("last_activity_ts"))

    if malformed:
        deg.append("surface leases: %d ledger line(s) could not be parsed and are "
                   "excluded from the spans below" % malformed)
    sec = {
        "present": True,
        "path": _rel(proj, path),
        "n_events": len(rows),
        "n_malformed": malformed,
        "paths": [paths[p] for p in order],
        "snapshots": snapshots,
        "checker": checker,
    }
    return sec, deg


# ── seam cards ───────────────────────────────────────────────────────────────

def load_seams(proj):
    """seams/*-summary.json, values preserved verbatim, integrity from the
    checker ONLY.

    The checker does not distinguish a stale hash from malformed JSON (both
    surface as REASON=STALE CARD), and an existing card can come back INERT when
    python3 is unavailable. The model therefore claims no discrimination the
    checker does not make: GREEN -> verified, RED -> not-verified carrying the
    REASON line verbatim, anything else -> unassessed.
    """
    sdir = os.path.join(proj, "seams")
    st, _d = _sink_state(sdir, "dir")
    if st != "ok":
        return None, [_sink_absent("seam cards", sdir, "dir")]
    try:
        files = [os.path.join(sdir, f) for f in os.listdir(sdir)
                 if f.endswith("-summary.json")]
    except OSError:
        return None, [_degrade("seam cards: seams/ unreadable")]
    if not files:
        return ({"present": True, "path": "seams", "cards": [], "n_truncated": 0},
                ["seam cards: seams/ exists but holds no *-summary.json card"])

    deg, truncated = [], 0
    files = _newest_first(files)
    if len(files) > GOV_CAP_SEAMS:
        truncated = len(files) - GOV_CAP_SEAMS
        files = files[:GOV_CAP_SEAMS]
        deg.append("seam cards: showing the newest %d of %d cards (%d not read)"
                   % (GOV_CAP_SEAMS, GOV_CAP_SEAMS + truncated, truncated))

    cards, n_bad, n_over = [], 0, 0
    for f in files:
        if _too_big(f):
            n_over += 1
            cards.append({"file": _rel(proj, f), "phase": "", "malformed": True,
                          "integrity": "unassessed",
                          "integrity_reason": "card larger than the read cap — not read"})
            continue
        data = read_json(f)
        if not isinstance(data, dict):
            n_bad += 1
            cards.append({"file": _rel(proj, f), "phase": "", "malformed": True,
                          "integrity": "unassessed",
                          "integrity_reason": "card is not readable JSON"})
            continue
        phase = str(data.get("phase") or "")
        card = {
            "file": _rel(proj, f),
            "phase": phase,
            "schema": data.get("schema"),
            "ts": data.get("ts"),
            "verdict": data.get("verdict"),
            "gates_run": data.get("gates_run"),
            "gates_red": data.get("gates_red"),
            "gates_yellow": data.get("gates_yellow"),
            "gates_inert": data.get("gates_inert"),
            "gates_unassessed": data.get("gates_unassessed"),
            "open_findings": data.get("open_findings"),
            "fixed_unverified": data.get("fixed_unverified"),
            "accepted_findings": data.get("accepted_findings"),
            "lock_id": data.get("lock_id"),
            "manuscript": data.get("manuscript"),
            "next_phase": data.get("next_phase"),
            "sources": data.get("sources") or [],
            "malformed": False,
        }
        # ONE card at a time: the no-phase form validates only the NEWEST
        # summary, so a per-project invocation cannot stamp every card — and a
        # card that records no phase cannot be aimed at at all. Calling the
        # no-phase form for it would stamp this card with a verdict about a
        # different one, which is worse than saying nothing.
        if not phase:
            card["integrity"] = "unassessed"
            card["integrity_reason"] = ("card records no phase; the checker cannot be "
                                        "aimed at this card")
            cards.append(card)
            continue
        state, rc, out = _run_checker("seam-summary-check.sh", [proj, phase])
        # THE CHECKER RESOLVES ITS OWN TARGET from the phase argument
        # (seams/<phase>-summary.json) and prints it on SUMMARY=. Any OTHER card
        # file whose `phase` field names that same phase — a relock copy, a
        # restored backup, a hand-edited card — would otherwise inherit a verdict
        # about a file it is not. Stamp a card only when the checker says it
        # validated THAT file.
        validated = ""
        for line in (out or "").splitlines():
            if line.startswith("SUMMARY="):
                validated = line[len("SUMMARY="):].strip()
                break
        card["checked_file"] = _rel(proj, validated) if validated else None
        if state == "ok" and validated and os.path.abspath(validated) != os.path.abspath(f):
            card["integrity"] = "unassessed"
            card["integrity_reason"] = (
                "the checker validated %s, not this card — a card is only assessed by a "
                "run aimed at its own file" % _rel(proj, validated))
            cards.append(card)
            continue
        reason = ""
        for line in (out or "").splitlines():
            if line.startswith("REASON="):
                reason = line[len("REASON="):].strip()
                break
        status = ""
        for line in (out or "").splitlines():
            if line.startswith("STATUS="):
                status = line[len("STATUS="):].strip()
                break
        if state != "ok":
            card["integrity"] = "unassessed"
            card["integrity_reason"] = "seam-summary-check.sh %s" % state
        elif status == "GREEN" and rc == 0:
            card["integrity"] = "verified"
            card["integrity_reason"] = ""
        elif status == "RED" and rc == 1:
            card["integrity"] = "not-verified"
            card["integrity_reason"] = reason
        else:
            # Do NOT reuse the checker's REASON here: a stub that printed
            # "REASON=all good" and then exited 7 would render that reassurance
            # beside a non-verdict. Name the contract violation instead.
            card["integrity"] = "unassessed"
            card["integrity_reason"] = ("checker returned %s / rc %s, outside its "
                                        "documented 0/1/3 contract"
                                        % (status or "no STATUS line", rc))
        cards.append(card)

    if n_bad:
        deg.append(_degrade("seam cards: %d card(s) are not readable JSON — shown as "
                            "unassessed, never as verified" % n_bad))
    if n_over:
        deg.append(_degrade("seam cards: %d card(s) exceed the read cap and were not "
                            "read" % n_over))
    if any(c.get("integrity") == "unassessed" and not c.get("malformed") for c in cards):
        deg.append(_degrade("seam cards: at least one card could not be checked (gate "
                            "absent, timed out, exited outside its contract, or the "
                            "checker validated a different file) — those cards are "
                            "labelled unassessed and must not be read as verified"))
    sec = {"present": True, "path": "seams", "cards": cards, "n_truncated": truncated}
    return sec, deg


# ── §7b gate acceptances ─────────────────────────────────────────────────────

_ACC_HEAD_RE = re.compile(
    r"^\s*-\s*\[(ACCEPTED|PROPOSED-ACCEPTANCE):\s*([^|\]]+?)\s*\|\s*"
    r"NUMBER_EFFECT=(YES|NO|UNKNOWN)\s*\]\s*(.+?)\s*$")
_ACC_LOOSE_RE = re.compile(r"^\s*-\s*\[(ACCEPTED|PROPOSED-ACCEPTANCE)\b")
_ACC_FIELD_RE = re.compile(r"^\s*\*\*(Authorized by|Reason|Disclosure):\*\*\s*(.*?)\s*$")


def load_acceptances(proj):
    """logs/gate-acceptances.md as records.

    `complete` mirrors the CONSUMING GATE's rules exactly (phase-verify §7b):
    Reason >= 120 chars, and when NUMBER_EFFECT=YES a Disclosure >= 80 chars.
    Authorized-by is NOT part of it — the matcher accepts an empty value and
    reports `<unnamed>` — so it is carried verbatim and displayed, never gating.
    """
    path = os.path.join(proj, "logs", "gate-acceptances.md")
    st, _d = _sink_state(path)
    if st != "ok":
        return None, [_sink_absent("gate acceptances", path)]
    if _too_big(path):
        return None, [_degrade("gate acceptances: present but larger than the %d-byte "
                               "read cap — NOT read" % GOV_BYTE_CAP)]
    txt = read_text(path)
    if txt is None:
        return None, [_degrade("gate acceptances: logs/gate-acceptances.md unreadable")]

    recs, cur, malformed = [], None, 0
    for line in txt.split("\n"):
        m = _ACC_HEAD_RE.match(line)
        if m:
            cur = {"token": "accepted" if m.group(1) == "ACCEPTED" else "proposed",
                   "phase": m.group(2).strip(), "number_effect": m.group(3),
                   "headline": m.group(4).strip(), "authorized_by": "",
                   "reason_len": 0, "disclosure_len": 0, "complete": False,
                   "parse_note": ""}
            recs.append(cur)
            continue
        if _ACC_LOOSE_RE.match(line):
            # A header that does not match the gate's own pattern is KEPT with a
            # note: dropping it would hide an acceptance the gate will also fail
            # to read.
            malformed += 1
            cur = {"token": "unparsed", "phase": "", "number_effect": "",
                   "headline": line.strip()[:200], "authorized_by": "",
                   "reason_len": 0, "disclosure_len": 0, "complete": False,
                   "parse_note": "header does not match the gate's ACCEPTED/"
                                 "PROPOSED-ACCEPTANCE pattern; phase-verify will not "
                                 "read it either"}
            recs.append(cur)
            continue
        if cur is not None:
            mm = _ACC_FIELD_RE.match(line)
            if mm:
                lab, val = mm.group(1), mm.group(2)
                if lab == "Authorized by":
                    cur["authorized_by"] = val
                elif lab == "Reason":
                    cur["reason_len"] = len(val)
                else:
                    cur["disclosure_len"] = len(val)
    # The §7b matcher resets its current record ONLY on an `- [ACCEPTED:` header.
    # A `- [PROPOSED-ACCEPTANCE:` header matches neither that nor a field line, so
    # the gate keeps writing the PROPOSED block's Reason/Disclosure/Authorized-by
    # into the ACCEPTED record above it. Where that layout occurs, this model's
    # per-record reading and the gate's merged reading DISAGREE, and the reader
    # must be told rather than shown a confident `complete`.
    prev_accepted = None
    for r in recs:
        if r["token"] == "accepted":
            prev_accepted = r
        elif r["token"] == "proposed" and prev_accepted is not None:
            note = ("this proposal follows an ACCEPTED entry: phase-verify's §7b parser "
                    "does not reset on a PROPOSED-ACCEPTANCE header, so it reads this "
                    "block's fields INTO that entry. The gate's verdict for the entry "
                    "above cannot be predicted from this file as laid out.")
            r["gate_merge_risk"] = True
            prev_accepted["gate_merge_risk"] = True
            prev_accepted["parse_note"] = (prev_accepted.get("parse_note") or "") + note
            r["parse_note"] = (r.get("parse_note") or "") + note
    for r in recs:
        r.setdefault("gate_merge_risk", False)
        if r["token"] != "accepted":
            continue      # PROPOSED is non-binding by definition; unparsed cannot bind
        ok = r["reason_len"] >= 120
        if ok and r["number_effect"] == "YES":
            ok = r["disclosure_len"] >= 80
        # `complete` reports the LENGTH-VALIDITY rules only. It is not a
        # prediction that the gate will accept the entry: §7b additionally
        # requires the record's phase to match the phase being verified AND its
        # headline to match a live FAIL line in that run's report.
        r["complete"] = ok and not r["gate_merge_risk"]
        r["complete_scope"] = "length rules only (phase + headline match not evaluated here)"
        if r["gate_merge_risk"]:
            pass
        elif not ok and not r["parse_note"]:
            r["parse_note"] = ("does not satisfy the §7b matcher: Reason >= 120 chars"
                               + (" and, with NUMBER_EFFECT=YES, Disclosure >= 80 chars"
                                  if r["number_effect"] == "YES" else ""))

    deg = []
    if malformed:
        deg.append("gate acceptances: %d entr(y/ies) do not match the gate's own "
                   "pattern and are shown unparsed — the gate will not read them either"
                   % malformed)
    sec = {
        "present": True,
        "path": _rel(proj, path),
        "records": recs,
        "n_accepted": sum(1 for r in recs if r["token"] == "accepted"),
        "n_proposed": sum(1 for r in recs if r["token"] == "proposed"),
        "n_complete": sum(1 for r in recs if r["complete"]),
        "n_unparsed": malformed,
        "n_gate_merge_risk": sum(1 for r in recs if r.get("gate_merge_risk")),
        "rule": ("complete = Reason >= 120 chars, plus Disclosure >= 80 when "
                 "NUMBER_EFFECT=YES (phase-verify section 7b). Authorized-by is "
                 "displayed, never required — the matcher accepts an empty value. This "
                 "is the LENGTH-VALIDITY test only: the gate additionally requires a "
                 "phase match and a live FAIL headline match, which this page does not "
                 "evaluate."),
    }
    return sec, deg


# ── dispatch provenance (manifest rows ↔ briefing packets) ───────────────────

def load_dispatch_provenance(proj, dispatches):
    """Each dispatch row's brief, re-hashed. A byte identity check, not a
    verdict: `verified` means the file on disk still hashes to the sha the row
    recorded, nothing more.

    Two legacy brief conventions may be displayed: briefs/<phase>-<role>*.json
    and briefs/fix-<round>.md. Rows with no brief key are
    LEGACY, stamped `unbriefed` and rendered neutrally: they predate the packet
    legacy display metadata and are not review-evidence authority.
    """
    _mf = os.path.join(proj, "logs", "dispatch-manifest.jsonl")
    if not dispatches:
        if os.path.exists(_mf):
            # The file is there; read_ndjson simply could not use any line of it.
            # Reporting "not adopted" states something false about the run, and
            # it silently disables the hand-authored-summary heuristic too.
            return None, [_degrade("dispatch provenance: logs/dispatch-manifest.jsonl "
                                   "exists but no line of it could be parsed — provenance "
                                   "is UNREADABLE, not absent, and the missing-dispatch "
                                   "heuristic cannot run for this project")]
        return None, [_adopt("dispatch provenance: not adopted (no "
                             "logs/dispatch-manifest.jsonl rows)")]
    rows, n_checked, deg = [], 0, []
    for d in dispatches:
        brief = d.get("brief")
        rec = {"ts": str(d.get("ts") or ""), "agentId": str(d.get("agentId") or ""),
               "subagent": str(d.get("subagent") or ""), "phase": str(d.get("phase") or ""),
               "purpose": str(d.get("purpose") or "")[:300],
               "brief": str(brief or ""), "brief_sha256": str(d.get("brief_sha256") or ""),
               "brief_link": "unbriefed", "brief_kind": ""}
        if brief:
            bp = str(brief)
            if not os.path.isabs(bp):
                bp = os.path.join(proj, bp)
            rec["brief_kind"] = ("agent-brief-json" if bp.endswith(".json")
                                 else "fix-brief-md" if bp.endswith(".md") else "other")
            _root = os.path.abspath(proj)
            _bp = os.path.abspath(bp)
            if not (_bp == _root or _bp.startswith(_root + os.sep)):
                # A byte match against a file outside the project proves nothing
                # about this run: the artifact is not part of it.
                rec["brief_link"] = "unverifiable (path escapes the project)"
            elif not os.path.isfile(bp):
                rec["brief_link"] = "missing"
            elif n_checked >= GOV_CAP_BRIEFS:
                rec["brief_link"] = "not-checked (brief cap reached)"
            else:
                n_checked += 1
                got = _sha256_file(bp)
                if not rec["brief_sha256"]:
                    rec["brief_link"] = "unverifiable (row records no sha)"
                elif got == rec["brief_sha256"]:
                    rec["brief_link"] = "verified"
                else:
                    rec["brief_link"] = "mismatch"
        rows.append(rec)
    n_briefed = sum(1 for r in rows if r["brief"])
    # Gate on what was actually hashed: n_briefed counts rows carrying a brief
    # KEY, so a corpus whose briefs are mostly missing on disk produced a
    # truncation warning while nothing had in fact been left unchecked.
    if n_checked >= GOV_CAP_BRIEFS and any(
            r["brief_link"] == "not-checked (brief cap reached)" for r in rows):
        deg.append(_degrade("dispatch provenance: re-hashed %d brief(s) and stopped at "
                            "the cap; the rest are listed unchecked" % GOV_CAP_BRIEFS))
    sec = {
        "present": True,
        "path": "logs/dispatch-manifest.jsonl",
        "rows": rows,
        "n_rows": len(rows),
        "n_briefed": n_briefed,
        "n_verified": sum(1 for r in rows if r["brief_link"] == "verified"),
        "n_mismatch": sum(1 for r in rows if r["brief_link"] == "mismatch"),
        "n_missing": sum(1 for r in rows if r["brief_link"] == "missing"),
        "n_unbriefed": sum(1 for r in rows if r["brief_link"] == "unbriefed"),
    }
    return sec, deg


# ── fix receipts ─────────────────────────────────────────────────────────────

def load_receipts(proj, gate_run_rows):
    """code-review/reviewed-scripts-*.json — parsed manifest fields only.

    Chain edges come from supersedes_review_id. A named predecessor with no
    matching manifest is recorded as `chain: broken` — a fact about the files,
    not a verdict. Hash binding, R2b and R6c belong to pre-exec-review-check.sh,
    so every receipt is stamped validation: not-re-verified-here.
    """
    cdir = os.path.join(proj, "code-review")
    st, _d = _sink_state(cdir, "dir")
    if st != "ok":
        return None, [_sink_absent("fix receipts", cdir, "dir")]
    try:
        files = [os.path.join(cdir, f) for f in os.listdir(cdir)
                 if f.startswith("reviewed-scripts-") and f.endswith(".json")
                 and not _too_big(os.path.join(cdir, f))]
    except OSError:
        return None, [_degrade("fix receipts: code-review/ unreadable")]
    if not files:
        return ({"present": True, "path": "code-review", "receipts": [], "n_truncated": 0},
                ["fix receipts: code-review/ exists but holds no reviewed-scripts-*.json"])

    deg, truncated = [], 0
    all_files = list(files)
    files = _newest_first(files)
    if len(files) > GOV_CAP_RECEIPTS:
        truncated = len(files) - GOV_CAP_RECEIPTS
        files = files[:GOV_CAP_RECEIPTS]
        deg.append("fix receipts: showing the newest %d receipts (%d not read)"
                   % (GOV_CAP_RECEIPTS, truncated))

    # Chain membership is computed over EVERY receipt filename, not just the ones
    # that survived truncation — otherwise the cap manufactures a `broken` chain
    # at the truncation boundary.
    all_ids = set()
    for f in _newest_first(all_files):
        d0 = read_json(f)
        if isinstance(d0, dict) and d0.get("review_id"):
            all_ids.add(str(d0["review_id"]))
    recs, ids, n_bad = [], set(), 0
    for f in files:
        d = read_json(f)
        if not isinstance(d, dict):
            n_bad += 1
            recs.append({"file": _rel(proj, f), "malformed": True,
                         "validation": "not-re-verified-here"})
            continue
        rid = str(d.get("review_id") or "")
        ids.add(rid)
        scripts = d.get("scripts")
        oos = d.get("out_of_scope")
        # pre-exec-review-check.sh treats a non-array `scripts` as an INVALID
        # manifest. Emitting 0 here made it indistinguishable from a genuine
        # empty list — a receipt that reviewed nothing.
        bad_shape = not isinstance(scripts, (list, dict)) or not isinstance(oos, (list, dict))
        recs.append({
            "file": _rel(proj, f),
            "malformed": False,
            "review_id": rid,
            "ts": str(d.get("ts") or ""),
            "supersedes_review_id": (None if d.get("supersedes_review_id") in (None, "", "null")
                                     else str(d.get("supersedes_review_id"))),
            "fixed_finding_ids": list(d.get("fixed_finding_ids") or []),
            "remaining_blocking_count": d.get("remaining_blocking_count"),
            "n_scripts": len(scripts) if isinstance(scripts, (list, dict)) else None,
            "n_out_of_scope": len(oos) if isinstance(oos, (list, dict)) else None,
            "shape_invalid": bad_shape,
            "chain": "head",
            "validation": "not-re-verified-here",
            "gate_run": None,
        })
    by_id = {r["review_id"]: r for r in recs
             if not r.get("malformed") and r.get("review_id")}
    for r in recs:
        if r.get("malformed"):
            continue
        sup = r.get("supersedes_review_id")
        if sup:
            if sup in all_ids:
                r["chain"] = "linked"
            elif sup in ids:
                r["chain"] = "linked"
            else:
                r["chain"] = "broken"
    # A supersedes CYCLE (A→B→A) is not a chain: presenting both ends as `linked`
    # implies an ordering that does not exist.
    for r in recs:
        if r.get("malformed") or not r.get("supersedes_review_id"):
            continue
        seen, cur_id, cyc = set(), r.get("review_id"), False
        while cur_id and cur_id not in seen:
            seen.add(cur_id)
            nxt = (by_id.get(cur_id) or {}).get("supersedes_review_id")
            if nxt and nxt in seen:
                cyc = True
                break
            cur_id = nxt
        if cyc:
            r["chain"] = "cycle"
    if any(r.get("chain") == "cycle" for r in recs):
        deg.append(_degrade("fix receipts: a supersedes CYCLE was recorded — those "
                            "receipts have no head and no ordering"))

    # R2-6: a gate-run link is attached ONLY when a recorded pre-exec row names
    # THIS review_id. gate-runs.ndjson records gate/phase/rc/ts and no output,
    # so in practice nothing links — and a project-newest link would imply a
    # validation that never covered this receipt.
    # A SUBSTRING TEST OVER A NORMALIZED ROW CANNOT PRODUCE A TRUE POSITIVE, only
    # false ones: load_gate_runs strips every field except gate/phase/rc/verdict/
    # ts/ms/origin, so `review_id in json.dumps(row)` only ever matched incidental
    # text (a phase literally named "R1-lane"). Worse, one such accident flipped
    # `linkable` and suppressed the honest coverage line for EVERY receipt.
    # Require an exact match on a dedicated field, from a pre-exec row.
    linkable = False
    for row in gate_run_rows or []:
        if "pre-exec" not in str(row.get("gate") or ""):
            continue
        rid_field = str(row.get("review_id") or "").strip()
        if not rid_field:
            continue
        for r in recs:
            if r.get("review_id") and r["review_id"] == rid_field:
                r["gate_run"] = {"gate": row.get("gate"), "ts": row.get("ts"),
                                 "verdict": row.get("verdict"),
                                 "basis": "gate-run row records this exact review_id"}
                linkable = True
    if not linkable:
        deg.append(_degrade("fix receipts: no pre-exec gate run records a review_id, so no "
                            "receipt is linked to a validation run — receipts are shown as "
                            "filed, not as verified"))
    if n_bad:
        deg.append(_degrade("fix receipts: %d receipt(s) are not readable JSON" % n_bad))
    n_shape = sum(1 for r in recs if r.get("shape_invalid"))
    if n_shape:
        deg.append(_degrade("fix receipts: %d receipt(s) carry a non-array scripts/"
                            "out_of_scope field — pre-exec-review-check.sh treats that as "
                            "an invalid manifest, so their counts are UNKNOWN, not zero"
                            % n_shape))
    sec = {"present": True, "path": "code-review", "receipts": recs,
           "n_truncated": truncated,
           "n_broken_chain": sum(1 for r in recs if r.get("chain") == "broken")}
    return sec, deg


# ── governors: back-route episodes + 10.5 loop state ─────────────────────────

_ESC_RE = re.compile(r"^ESCALATE:(same-signature|recurring-signature|cap-reached)-on-(.+)$")


def load_governors(proj):
    """logs/back-route-history.jsonl segmented into EPISODES, plus .loop-state.json.

    Episode rules, matching the writer's own reset reader: hops before the first
    CLEAR belong to episode 1; consecutive CLEARs produce empty episodes, which
    are skipped rather than rendered; malformed rows are excluded from
    segmentation and counted; a final episode with no trailing CLEAR is `open`.
    """
    hist = os.path.join(proj, "logs", "back-route-history.jsonl")
    lstate = os.path.join(proj, ".loop-state.json")
    if not os.path.exists(hist) and not os.path.exists(lstate):
        return None, [_adopt("governors: not adopted (no logs/back-route-history.jsonl, "
                             "no .loop-state.json)")]

    deg, episodes, malformed, escalations = [], [], 0, []
    hops_total = 0
    if _too_big(hist):
        deg.append(_degrade("governors: back-route history is larger than the %d-byte "
                            "read cap — episodes NOT derived" % GOV_BYTE_CAP))
    elif os.path.isfile(hist):
        rows, malformed = _ndjson_with_malformed(hist)
        rows = rows or []
        cur = {"index": 1, "hops": [], "closed_by": None, "state": "open"}
        for r in rows:
            directive = str(r.get("directive") or "")
            if directive.startswith("CLEAR:"):
                # Consecutive CLEARs yield empty episodes: close only a NON-empty
                # one, so an empty episode is never rendered.
                if cur["hops"]:
                    cur["closed_by"] = directive
                    cur["state"] = "closed"
                    episodes.append(cur)
                    cur = {"index": len(episodes) + 1, "hops": [], "closed_by": None,
                           "state": "open"}
                continue
            hops_total += 1
            esc = None
            if directive.startswith("ESCALATE"):
                m = _ESC_RE.match(directive)
                if m:
                    esc = {"class": m.group(1), "target": m.group(2)}
                else:
                    # The bare legacy form records no target.
                    esc = {"class": "cap", "target": None,
                           "note": "legacy bare ESCALATE — target unknown"}
                escalations.append({"ts": str(r.get("ts") or ""), "directive": directive,
                                    "class": esc["class"], "target": esc["target"]})
            cur["hops"].append({
                "ts": str(r.get("ts") or ""),
                "directive": directive,               # ALWAYS verbatim
                "count": r.get("count"),
                "digest": str(r.get("digest") or ""),
                "findings_count": r.get("findings_count"),
                "loop": str(r.get("loop") or ""),
                "escalation": esc,
            })
        if cur["hops"]:
            episodes.append(cur)          # no trailing CLEAR -> stays `open`
    if malformed:
        # A truncated CLEAR row is invisible to segmentation, so two episodes
        # merge into one and the survivor is reported "open". The counts stay
        # honest; the SHAPE does not, and the page must say so.
        deg.append(_degrade("governors: %d back-route row(s) could not be parsed. A "
                            "CLEAR marker among them would merge two episodes into one, "
                            "so the episode count and the open/closed state below are "
                            "UNRELIABLE for this run" % malformed))

    loop_state, loop_note = None, ""
    if _too_big(lstate):
        loop_note = ".loop-state.json exceeds the read cap and was not read"
        deg.append(_degrade("governors: .loop-state.json is larger than the %d-byte read "
                            "cap — 10.5 loop counters not shown" % GOV_BYTE_CAP))
    elif os.path.isfile(lstate):
        loop_state = read_json(lstate)
        if loop_state is None:
            loop_note = ".loop-state.json is not readable JSON"
            deg.append(_degrade("governors: .loop-state.json unreadable — 10.5 loop "
                                "counters not shown"))
    else:
        loop_note = "no .loop-state.json (10.5 loop not entered, or pre-R3 project)"

    sec = {
        "present": True,
        "history_path": _rel(proj, hist) if os.path.isfile(hist) else None,
        "episodes": episodes,
        "n_episodes": len(episodes),
        "n_hops": hops_total,
        "n_malformed": malformed,
        "escalations": escalations,
        "open_episode": (None if malformed
                         else bool(episodes and episodes[-1]["state"] == "open")),
        "segmentation_reliable": not malformed,
        "loop_state": loop_state,
        "loop_state_note": loop_note,
    }
    return sec, deg


# ── independent-check requests ───────────────────────────────────────────────

def load_icr(proj):
    """Consumed from the gate's own --emit-json records. The visualizer never
    parses ICR prose: a request's validity is the gate's judgement, and an
    invalid request must never reach the page as an ordinary pending one."""
    state, rc, out = _run_checker("independent-check-requests.sh", [proj, "--emit-json"])
    if state == "absent":
        return None, ["ICR: not parsed (independent-check-requests.sh not found beside "
                      "the model builder)"]
    if state != "ok":
        return None, ["ICR: not parsed (gate %s)" % state]
    try:
        data = json.loads((out or "").strip() or "{}")
    except Exception:
        data = None
    if not isinstance(data, dict) or "requests" not in data:
        return None, ["ICR: not parsed (gate produced no record set)"]
    if rc not in (0, 1, 2, 3):
        return None, ["ICR: not parsed (gate exited %s, outside its 0/1/2/3 contract)" % rc]

    reqs = [r for r in (data.get("requests") or []) if isinstance(r, dict)]
    pending_clean = [r for r in reqs
                     if r.get("valid") and str(r.get("status") or "").startswith("PENDING")]
    invalid = [r for r in reqs if not r.get("valid")]
    deg = []
    b = data.get("bounds") or {}
    if data.get("complete") is False:
        deg.append(_degrade("ICR: the gate's scan was INCOMPLETE — the request counts on "
                            "this page are a floor, not a total"))
    if b.get("files_truncated"):
        deg.append("ICR: scan truncated at the newest %s report files of %s"
                   % (b.get("file_cap"), b.get("files_considered")))
    if b.get("budget_exhausted"):
        deg.append("ICR: scan stopped at its %ss budget with %s file(s) unread"
                   % (b.get("wall_clock_budget_s"), b.get("files_unscanned")))
    if b.get("files_skipped_oversize"):
        deg.append("ICR: %s report file(s) skipped as larger than the byte cap"
                   % b.get("files_skipped_oversize"))
    if data.get("counts", {}).get("unparseable_headings"):
        deg.append("ICR: %s heading-style section(s) carry no machine-readable keys"
                   % data["counts"]["unparseable_headings"])
    sec = {
        "present": True,
        "verdict": data.get("verdict"),
        "rc": data.get("rc", rc),
        # The gate now reports whether its own scan covered the whole corpus. A
        # bounded scan's counts are a FLOOR, and the page must say so rather than
        # present them as totals.
        "complete": data.get("complete", True),
        "reason": data.get("reason"),
        "counts": data.get("counts") or {},
        "bounds": b,
        "requests": reqs,
        "pending_authorizable": pending_clean,
        "not_authorizable_as_filed": invalid,
        "unparseable_heading_lines": data.get("unparseable_heading_lines") or [],
        "safety_registry": data.get("safety_registry"),
    }
    return sec, deg


# ── per-phase pointers (digest reports, rotated phase notes) ─────────────────

def load_phase_pointers(proj):
    """LATEST pointer per phase for the two classes that are deliberately NOT
    inventoried.

    `phase-verify --digest` reports and rotated phase notes are large and
    append-forever: listing every generation would bloat the model to no
    purpose. What a reader needs is the newest one per phase, as a link. Nothing
    here reads the file bodies.
    """
    out, unmatched = {}, 0
    for sub, key, pat in (("phase-verify-reports", "digest_report", None),
                          ("phase-notes", "phase_note", "phase-")):
        d = os.path.join(proj, "logs", sub)
        if not os.path.isdir(d):
            continue
        try:
            names = os.listdir(d)
        except OSError:
            continue
        for name in names:
            full = os.path.join(d, name)
            if not os.path.isfile(full):
                continue
            stem = name[len(pat):] if pat and name.startswith(pat) else name
            # <phase>-<timestamp>.<ext>: the phase id is everything before the
            # first dash that starts a date-ish token.
            m = re.match(r"^([0-9][0-9A-Za-z.]*)-", stem)
            if not m:
                # e.g. pipeline-state.sh writes phase-${phase:-unphased}-<ts>.md,
                # and `unphased` has no numeric head. Dropping these silently made
                # the pointer map look complete when it was not.
                unmatched += 1
                continue
            ph = m.group(1)
            slot = out.setdefault(ph, {})
            prev = slot.get(key)
            try:
                mt = os.path.getmtime(full)
            except OSError:
                mt = 0
            if prev is None or mt > prev[1]:
                slot[key] = (_rel(proj, full), mt)
    deg = []
    if unmatched:
        deg.append(_degrade("phase pointers: %d file(s) under logs/phase-verify-reports/ "
                            "or logs/phase-notes/ do not carry a phase-id prefix and are "
                            "not pointed at" % unmatched))
    return ({ph: {k: v[0] for k, v in slot.items()} for ph, slot in out.items()}, deg)


# ── governance assembly ──────────────────────────────────────────────────────

def _adopt(msg):
    """A fact about the run: this sink was never adopted."""
    return ("adoption", msg)


def _degrade(msg):
    """A gap in this page: present but unreadable, malformed, truncated, or
    unassessed."""
    return ("degraded", msg)


def _sink_absent(label, path, kind="file"):
    """Classify a missing-or-unusable sink honestly. Returns a coverage tuple."""
    state, detail = _sink_state(path, kind)
    if state == "absent":
        return _adopt("%s: not adopted (no %s)" % (label, path.split("/")[-1]
                                                   if kind == "file" else path))
    word = "unreadable" if state == "unreadable" else "the wrong type"
    return _degrade("%s: %s is present but %s (%s) — this is NOT a run that skipped the "
                    "layer, it is a source this page could not read"
                    % (label, path, word, detail or state))


REDACTED = "[withheld from bundle]"

# Free-text fields that carry governance CONTENT — holder names, authorizers,
# headlines, loci, digests, and the commands a reviewer asked to have run. Path
# exclusion alone does NOT keep these out of a bundle: the loaders lift them out
# of the logs as FIELDS, and the renderer prints them. A bundle is a portable
# file meant to leave the machine, so it carries counts and verdicts only.
_REDACT_FIELDS = {
    "findings":            ("locus", "cls", "report"),
    "leases":              ("path", "holder"),
    "acceptances":         ("headline", "authorized_by", "parse_note"),
    "receipts":            ("review_id", "supersedes_review_id", "fixed_finding_ids", "file"),
    "governors":           ("digest", "directive", "closed_by", "target", "note"),
    "icr":                 ("id_tag", "source", "red_reasons", "reason"),
    "dispatch_provenance": ("purpose", "brief", "brief_sha256"),
    "seams":               ("manuscript", "lock_id", "integrity_reason"),
}


def _redact(obj, fields):
    """Recursively blank the named fields, preserving structure and counts."""
    if isinstance(obj, dict):
        out = {}
        for k, v in obj.items():
            if k in fields:
                if isinstance(v, list):
                    out[k] = [REDACTED] * len(v)     # length is a count, not content
                elif v is None:
                    out[k] = None
                else:
                    out[k] = REDACTED
            else:
                out[k] = _redact(v, fields)
        return out
    if isinstance(obj, list):
        return [_redact(v, fields) for v in obj]
    return obj


def redact_governance_for_bundle(sections):
    """Counts and verdicts survive; content does not."""
    out = {}
    for key, sec in sections.items():
        fields = _REDACT_FIELDS.get(key)
        out[key] = _redact(sec, set(fields)) if fields else sec
    return out


def build_governance(proj, dispatches, gate_run_rows):
    """All governance sections, split into two kinds of honesty.

    ADOPTION is a fact about the PROJECT: the governance layer is opt-in per
    run, so "no findings ledger" is not a gap in this page's coverage — it is
    what the run did. Those lines ride with the panel, beside the sinks that
    ARE adopted.

    DEGRADATION is a gap in what this page could show: unreadable, malformed,
    truncated, or a checker that could not be consulted. Those go to the
    coverage banner, which must stay a signal — a banner that fires on every
    run is decoration.

    Either way, absence is stated explicitly. What must never happen is an
    unadopted sink rendering as an adopted-and-clean one.
    """
    sections, degraded, adoption = {}, [], []

    def _route(entry):
        # Loaders may return a plain string (legacy) or a typed (kind, msg)
        # tuple. Keying adoption off the substring "not adopted" let a gate's own
        # free text — e.g. an ICR bounds string containing that phrase — route a
        # real degradation into the adoption list.
        if isinstance(entry, tuple) and len(entry) == 2:
            kind, msg = entry
        else:
            kind, msg = ("adoption" if "not adopted" in str(entry) else "degraded"), str(entry)
        (adoption if kind == "adoption" else degraded).append(msg)
    for key, fn in (("findings", lambda: load_findings(proj)),
                    ("leases", lambda: load_leases(proj)),
                    ("seams", lambda: load_seams(proj)),
                    ("acceptances", lambda: load_acceptances(proj)),
                    ("dispatch_provenance", lambda: load_dispatch_provenance(proj, dispatches)),
                    ("receipts", lambda: load_receipts(proj, gate_run_rows)),
                    ("governors", lambda: load_governors(proj)),
                    ("icr", lambda: load_icr(proj))):
        try:
            sec, deg = fn()
        except Exception as e:            # a broken sink must not kill the model
            sec, deg = None, ["%s: loader failed (%s) — section omitted"
                              % (key, e.__class__.__name__)]
        if sec is not None:
            sections[key] = sec
        for line in (deg or []):
            _route(line)
    try:
        ptr, ptr_deg = load_phase_pointers(proj)
    except Exception as e:
        ptr, ptr_deg = {}, [_degrade("phase pointers: loader failed (%s)"
                                     % e.__class__.__name__)]
    for line in (ptr_deg or []):
        _route(line)
    if ptr:
        sections["phase_pointers"] = ptr
    return sections, degraded, adoption


# ── assembly ─────────────────────────────────────────────────────────────────

def build(proj, orchestrator=None, embed=False):
    proj = os.path.abspath(proj)
    if orchestrator not in (None, "auto-research"):
        return None
    st = state_auto_research(proj)
    if st is None:
        return None

    ar = True
    skill_dir = local_auto_research_skill_dir()
    seq, labels, pmeta = backbone_auto_research(skill_dir)

    traces = load_traces(proj)
    legacy_dispatches = load_dispatches(proj)
    dispatches, review_dispatch_degraded = load_registered_review_dispatches(proj, st)
    reviews = load_reviews(proj)
    locks = load_locks(proj)
    roster, ph_aliases, extra_gates = load_auto_research_gate_roster(pmeta)
    gate_runs, gate_src = load_gate_runs(proj, traces)
    safety_path, safety_table = load_safety(proj)
    artifacts, art_truncated = load_artifacts(proj, safety_table)
    governance, gov_degraded, gov_adoption = build_governance(proj, legacy_dispatches, gate_runs)
    gov_degraded.extend(review_dispatch_degraded)
    if embed and governance:
        # --embed produces a page meant to be published. Governance logs are
        # pipeline metadata, not pipeline products (CLAUDE.md derived-product
        # rule), so the bundle carries their counts and verdicts only.
        governance = redact_governance_for_bundle(governance)
        gov_degraded.append("governance: this is a BUNDLE — governance sections carry "
                            "counts and verdicts only; holder names, authorizers, "
                            "headlines, loci, digests and requested commands are withheld")

    steps_by_phase, disp_by_phase, rev_by_phase = {}, {}, {}
    for r in traces:
        steps_by_phase.setdefault(str(r.get("phase") or "(unphased)"), []).append(r)
    for d in dispatches:
        disp_by_phase.setdefault(str(d.get("phase") or ""), []).append(d)
    for r in reviews:
        rev_by_phase.setdefault(r["phase"], []).append(r)

    completed = st["phases_completed"]
    declared = set(seq)
    # The drift lane: completed phases the declared sequence never mentions.
    undeclared = [p for p in completed if p not in declared]
    order = list(seq) + [p for p in undeclared if p not in seq]

    rb_in, rb_out = {}, {}
    for rb in st.get("route_backs", []):
        rb_out.setdefault(rb["from"], []).append(rb)
        rb_in.setdefault(rb["to"], []).append(rb)

    phases = []
    for pid in order:
        if pid in st.get("excused", {}):
            status = "excused"
        elif pid in undeclared:
            status = "undeclared"
        elif pid in completed:
            status = "completed"
        elif pid == st.get("current_phase"):
            status = ("halted" if str(st.get("current_phase_status", "")).startswith("halted")
                      else "current")
        else:
            status = "pending"
        if pid in (st.get("stale_phases") or []):
            status = "stale"

        rec = (st.get("phase_records") or {}).get(pid) or {}
        # Declared roster for this phase, joined to whatever was observed.
        # A declared gate with no observation is NOT a pass — it is "no record",
        # and the page must say so rather than leave the row blank.
        obs_by_gate = {}
        for r in gate_runs:
            if str(r.get("phase")) == pid or not r.get("phase"):
                obs_by_gate.setdefault(r["gate"], []).append(r)
        declared_gates = roster.get(pid, [])
        gate_rows = []
        for g in declared_gates:
            seen = obs_by_gate.get(g, [])
            gate_rows.append({
                "name": g, "declared": True,
                "runs": len(seen),
                "verdict": (seen[-1]["verdict"] if seen else None),
                "rc": (seen[-1]["rc"] if seen else None),
            })
        for g, seen in sorted(obs_by_gate.items()):
            if g not in declared_gates:            # ran but not on this phase's roster
                gate_rows.append({"name": g, "declared": False, "runs": len(seen),
                                  "verdict": seen[-1]["verdict"], "rc": seen[-1]["rc"]})
        steps = steps_by_phase.get(pid, [])
        disps = disp_by_phase.get(pid, [])
        label = labels.get(pid, "")

        # The phase contract, not label heuristics or a legacy manifest, says
        # which auto-research phases require portable review evidence.
        needs = bool((pmeta.get(pid) or {}).get("review_evidence_policy"))
        suspect = bool(needs and status == "completed" and not disps)

        phases.append({
            "id": pid, "label": label, "status": status,
            "declared": pid in declared,
            "completed_at": rec.get("completed_at", ""),
            "declared_gate": (pmeta.get(pid) or {}).get("declared_gate"),
            "required_outputs": (pmeta.get(pid) or {}).get("required_outputs", []),
            "excuse": st.get("excused", {}).get(pid, ""),
            "steps": steps,
            "n_steps": len(steps),
            "n_failed_steps": sum(1 for s in steps if s.get("status") == "fail"),
            "dispatches": disps,
            "reviews": rev_by_phase.get(pid, []),
            "artifacts": [a.get("path") for a in (rec.get("artifacts") or [])
                          if isinstance(a, dict)],
            "route_backs_out": rb_out.get(pid, []),
            "route_backs_in": rb_in.get(pid, []),
            "retry_count": (st.get("retry_counts") or {}).get(pid, 0),
            "dispatch_suspect": suspect,
            "gates": gate_rows,
            "n_gates_declared": len(declared_gates),
            "n_gates_observed": sum(1 for g in gate_rows if g["runs"]),
            "aliases": ph_aliases.get(pid, []),
        })

    sessions = sorted({str(r.get("session_id")) for r in traces if r.get("session_id")})

    degraded = []
    if not traces:
        degraded.append("no RAO trace (logs/trace-*.ndjson) — step detail unavailable; "
                        "this project predates trace adoption or the skill never emitted one")
    if not seq:
        degraded.append("declared phase sequence not found — could not locate the plugin "
                        "tree (set SCHOLAR_SKILL_DIR); spine order is from run state only")
    if not sessions:
        degraded.append("no session_id on any trace record — raw-transcript deep links "
                        "unavailable")
    if undeclared:
        degraded.append(f"{len(undeclared)} completed phase(s) absent from the declared "
                        f"sequence: {', '.join(undeclared)}")
    if not roster:
        degraded.append("gate roster not found (references/gates-invoked-per-phase.md) — "
                        "cannot show which gates each phase declares")
    if gate_src == "none":
        degraded.append("no gate-run record — neither logs/gate-runs.ndjson nor traced gate "
                        "calls. Declared gates are listed, but nothing shows which actually "
                        "fired or what they returned")
    elif gate_src.startswith("trace"):
        degraded.append("gate verdicts come from the RAO trace only, which records a gate "
                        "call ONLY when a skill logged one as a step — GREEN gates are "
                        "largely invisible. logs/gate-runs.ndjson carries every invocation")
    if art_truncated:
        degraded.append("artifact listing truncated at the 4000-file cap")
    if safety_path is None:
        degraded.append("no .claude/safety-status.json — artifact safety unknown; "
                        "previews restricted to text under the size cap")
    # Only real coverage gaps reach the banner: unreadable, malformed,
    # truncated, or a checker that could not be consulted. Sinks the run simply
    # never adopted are reported with the panel instead (see governance_adoption)
    # so this banner keeps meaning "what this page could NOT show".
    degraded.extend(gov_degraded)

    return {
        "model_version": MODEL_VERSION,
        "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "project": {
            "slug": os.path.basename(proj.rstrip("/")),
            "path": proj,
            "orchestrator": st["orchestrator"],
        },
        "state": {
            "current_phase": st.get("current_phase", ""),
            "current_phase_status": st.get("current_phase_status", ""),
            "relock_count": st.get("relock_count", ""),
            "last_updated": st.get("last_updated", ""),
            "checksum": st.get("checksum", ""),
            "n_completed": len(completed),
        },
        "phases": phases,
        "route_backs": st.get("route_backs", []),
        "transition_decisions": st.get("transition_decisions", []),
        "anomalies": ([a for a in load_anomalies(proj, st)
                       if a.get("kind") not in ("idiom-override", "digest-degraded")]
                      if embed else load_anomalies(proj, st)),
        "locks": locks,
        "reviews": reviews,
        "artifacts": artifacts,
        "gates": {
            "source": gate_src,
            "n_declared_total": sum(len(v) for v in roster.values()),
            "n_distinct_declared": len({g for v in roster.values() for g in v}),
            "additional_wired": extra_gates,
            "runs": gate_runs,
            "index": build_gate_index(roster, gate_runs, extra_gates),
        },
        "charts": build_charts(phases, reviews, locks, gate_runs),
        "report": build_report(artifacts, proj, embed),
        "unphased_steps": steps_by_phase.get("(unphased)", []),
        "sessions": sessions,
        "governance": governance,
        "coverage": {
            "has_trace": bool(traces), "n_trace_steps": len(traces),
            "has_review_evidence_ledger": bool(st.get("review_evidence_history")),
            "n_dispatches": len(dispatches),
            "has_manifest": bool(legacy_dispatches),
            "n_legacy_dispatches": len(legacy_dispatches),
            "has_backbone": bool(seq), "n_declared_phases": len(seq),
            "undeclared_phases": undeclared,
            "safety_sidecar": safety_path,
            # phase_pointers is a convenience map, not a sink, so it is not
            # part of the adoption roll-call.
            "governance_sources": {
                k: (k in governance) for k in
                ("findings", "leases", "seams", "acceptances", "dispatch_provenance",
                 "receipts", "governors", "icr")
            },
            "governance_adoption": gov_adoption,
            "governance_redacted": bool(embed and governance),
            "degraded_reasons": degraded,
        },
    }


def main():
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("project")
    ap.add_argument("-o", "--output")
    ap.add_argument("--orchestrator", choices=["auto-research"])
    ap.add_argument("--embed", action="store_true",
                    help="inline CLEARED figures as data: URIs so the page is "
                         "portable (cloud/bundle mode). Restricted files are "
                         "never embedded; they are recorded in report.withheld.")
    a = ap.parse_args()

    if not os.path.isdir(a.project):
        print(f"ERROR: not a directory: {a.project}", file=sys.stderr)
        return 1
    model = build(a.project, a.orchestrator, a.embed)
    if model is None:
        print("ERROR: no recognizable run state in this project.", file=sys.stderr)
        print("       Expected <proj>/.auto-research/state.json.", file=sys.stderr)
        return 2

    out = a.output or os.path.join(a.project, "logs", "run-model.json")
    os.makedirs(os.path.dirname(out) or ".", exist_ok=True)
    with open(out, "w") as fh:
        json.dump(model, fh, indent=1)
    print(f"RUN_MODEL={out}")
    print(f"ORCHESTRATOR={model['project']['orchestrator']}")
    print(f"PHASES={len(model['phases'])}")
    print(f"TRACE_STEPS={model['coverage']['n_trace_steps']}")
    print(f"DEGRADED={len(model['coverage']['degraded_reasons'])}")
    _r = model["report"]
    _g = model["gates"]
    print(f"GATES_DECLARED={_g['n_distinct_declared']} GATE_RUNS={len(_g['runs'])} "
          f"GATE_SOURCE={_g['source']}")
    print(f"TABLES={len(_r['tables'])} FIGURES={len(_r['figures'])} "
          f"DOCUMENTS={len(_r['documents'])} WITHHELD={len(_r['withheld'])}")
    _gov = model.get("governance") or {}
    print("GOVERNANCE=" + (",".join(sorted(_gov)) if _gov else "none"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
