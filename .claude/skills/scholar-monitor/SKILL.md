---
name: scholar-monitor
description: "Current-awareness literature monitoring for social sciences. Tracks new publications from top journals (ASR, AJS, Demography, Social Forces, NHB, NCS, Science Advances, APSR, PNAS), preprint servers (arXiv cs.CL for LLM research, cs.CY for computational social science, econ.GN), and custom author/keyword watchlists. Delta-based and /loop-safe: each invocation fetches only papers published since the last tick, groups them by user-defined category, generates 2–3 sentence LLM summaries of title+abstract, and auto-ingests into the scholar-knowledge graph. Delivers digests to the user's phone via Telegram (using the existing MCP channel) or ntfy.sh push, optionally email over SMTP — with a file-based audit trail always written to output/monitor/. Modes: default fetch (all due enabled sources), targeted fetch (source_id argument), all (force-fetch all enabled), preview (dry-run — show what would fetch without network calls), init, list, status, add, remove, configure delivery, digest. Designed for /loop (e.g., '/loop 24h /scholar-monitor arxiv-llm' or '/loop 7d /scholar-monitor'). Fully idempotent: cadence_days filter drops redundant ticks. State persisted in ~/.claude/scholar-monitor/ (configurable via SCHOLAR_MONITOR_DIR). Works alongside scholar-lit-review (retrospective reviews) and scholar-knowledge (knowledge graph accumulation)."
tools: Bash, WebFetch, Read, Write, Agent
argument-hint: "[source_id | all | preview | init | list | status | add | remove | configure delivery | digest [date-range]]"
user-invocable: true
---

# Scholar Monitor — Current-Awareness Literature Feed

You are running a **delta-based literature monitoring** pass. Unlike `scholar-lit-review` (which builds a retrospective landscape map), this skill pulls *new* publications since the last run, summarizes them, pushes them to the user's phone, and files them into the scholar-knowledge graph. Every run must be **idempotent** — a /loop invocation tomorrow must not re-deliver today's papers.

## Arguments

The user has provided: `$ARGUMENTS`

**Critical** — before running any Bash block below, parse `$ARGUMENTS`:

- First token → the mode keyword. Store as `MODE_ARG_VALUE` (or empty string if `$ARGUMENTS` is blank).
- Second token (where applicable, e.g., in `remove <id>` or `digest <range>`) → `SECOND_ARG_VALUE`.
- Every `[mode_arg]` / `[target_id]` / `[date_range]` / `[telegram_chat_id]` / `[ntfy_topic]` / `[smtp_*]` marker below is a **placeholder**. Substitute the actual value into the Bash block *before* executing it. A Bash block with literal `[mode_arg]` will fail.

Shell state does **not** persist between Bash tool calls. Every phase below re-derives its paths and re-loads helpers — deliberately, not redundantly.

---

## ABSOLUTE RULE — No Fabricated Papers

> **ZERO TOLERANCE**: never synthesize fake DOIs, fake arXiv IDs, fake titles, or fake authors. Every paper in every digest MUST originate from the `fetch.py` JSONL output. If `fetch.py` returns zero records, the digest reports zero new papers — never pad. Summary prose must stay faithful to the abstract text; if the abstract is empty, say "no abstract available" rather than inferring content.

---

## Shared Context Block

Every Bash block in this skill — every phase, every mode — begins with the following boilerplate. Re-evaluate it in place; do not assume variables from a prior block are still set.

```bash
# ── scholar-monitor shared context ──
set -euo pipefail
[ -f "${SCHOLAR_SKILL_DIR}/.env" ] && . "${SCHOLAR_SKILL_DIR}/.env" 2>/dev/null || true
[ -f "$HOME/.claude/.env" ] && . "$HOME/.claude/.env" 2>/dev/null || true

SCHOLAR_MONITOR_DIR="${SCHOLAR_MONITOR_DIR:-$HOME/.claude/scholar-monitor}"
SM_SOURCES="$SCHOLAR_MONITOR_DIR/sources.json"
SM_STATE="$SCHOLAR_MONITOR_DIR/state.json"
SM_CONFIG="$SCHOLAR_MONITOR_DIR/config.json"
SM_ARCHIVE="$SCHOLAR_MONITOR_DIR/archive.ndjson"
SM_LOGS="$SCHOLAR_MONITOR_DIR/logs"
SKILL_ASSETS="${SCHOLAR_SKILL_DIR}/.claude/skills/scholar-monitor/assets"
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"

# Run-dir is the stable cross-block scratch location (fixes PID-changes-between-blocks bug)
if [ -f "$SCHOLAR_MONITOR_DIR/.current-run" ]; then
    RUN_DIR=$(cat "$SCHOLAR_MONITOR_DIR/.current-run")
fi
```

Optionally reload KG helpers when needed (functions, not vars — functions also don't persist):

```bash
# ── reload KG helpers (use when the block calls kg_* functions) ──
SHARED_KG="${SCHOLAR_SKILL_DIR}/.claude/skills/_shared/knowledge-graph-search.md"
if [ -f "$SHARED_KG" ]; then
    eval "$(sed -n '/^```bash/,/^```/p' "$SHARED_KG" | sed '1d;$d')" 2>/dev/null || true
fi
```

---

## Phase 0: Setup (every mode)

### 0a. Initialize run context

```bash
# ── shared context (see "Shared Context Block" above) ──
set -euo pipefail
# Load .env files so SCHOLAR_SKILL_DIR + SCHOLAR_CROSSREF_EMAIL etc. are available.
# SCHOLAR_SKILL_DIR falls back to "." via the param-expansion default below; cwd is
# expected to be the repo root (or set SCHOLAR_SKILL_DIR in $HOME/.claude/.env).
[ -f "$HOME/.claude/.env" ] && . "$HOME/.claude/.env" 2>/dev/null || true
[ -f "${SCHOLAR_SKILL_DIR:-.}/.env" ] && . "${SCHOLAR_SKILL_DIR:-.}/.env" 2>/dev/null || true
SCHOLAR_SKILL_DIR="${SCHOLAR_SKILL_DIR:-.}"
SCHOLAR_MONITOR_DIR="${SCHOLAR_MONITOR_DIR:-$HOME/.claude/scholar-monitor}"
SM_SOURCES="$SCHOLAR_MONITOR_DIR/sources.json"
SM_STATE="$SCHOLAR_MONITOR_DIR/state.json"
SM_CONFIG="$SCHOLAR_MONITOR_DIR/config.json"
SM_ARCHIVE="$SCHOLAR_MONITOR_DIR/archive.ndjson"
SM_LOGS="$SCHOLAR_MONITOR_DIR/logs"
SKILL_ASSETS="${SCHOLAR_SKILL_DIR}/.claude/skills/scholar-monitor/assets"
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
mkdir -p "${OUTPUT_ROOT}/logs" "${OUTPUT_ROOT}/monitor" "$SCHOLAR_MONITOR_DIR" "$SM_LOGS" "$SCHOLAR_MONITOR_DIR/tmp"

# Establish a stable RUN_DIR (timestamped, persists across Bash calls via .current-run pointer)
RUN_DIR="$SCHOLAR_MONITOR_DIR/tmp/run-$(date -u +%Y%m%dT%H%M%SZ)-$$"
mkdir -p "$RUN_DIR"
echo "$RUN_DIR" > "$SCHOLAR_MONITOR_DIR/.current-run"

# Persist the mode argument — every subsequent block reads it from $RUN_DIR/mode.txt.
# Claude substitutes the actual first-token value into [mode_arg] before executing this block.
echo "[mode_arg]" > "$RUN_DIR/mode.txt"

echo "RUN_DIR=$RUN_DIR"
echo "MODE_ARG=[mode_arg]"
```

### 0b. Process log init

```bash
set -euo pipefail
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
mkdir -p "${OUTPUT_ROOT}/logs"

SKILL_NAME="scholar-monitor"
LOG_DATE=$(date +%Y-%m-%d)
LOG_FILE="${OUTPUT_ROOT}/logs/process-log-${SKILL_NAME}-${LOG_DATE}.md"
# Version-collision: if today's log exists, create -2, -3, … suffix
if [ -f "$LOG_FILE" ]; then
    CTR=2
    while [ -f "${OUTPUT_ROOT}/logs/process-log-${SKILL_NAME}-${LOG_DATE}-${CTR}.md" ]; do
        CTR=$((CTR + 1))
    done
    LOG_FILE="${OUTPUT_ROOT}/logs/process-log-${SKILL_NAME}-${LOG_DATE}-${CTR}.md"
fi
cat > "$LOG_FILE" <<LOGHEADER
# Process Log: /scholar-monitor
- **Date**: ${LOG_DATE}
- **Time started**: $(date +%H:%M:%S)
- **Arguments**: (see skill invocation)
- **Working Directory**: $(pwd)

## Steps

| # | Timestamp | Step | Action | Output | Status |
|---|-----------|------|--------|--------|--------|
LOGHEADER
echo "LOG_FILE=${LOG_FILE}"
```

### 0c. Auto-bootstrap on first run

```bash
# ── shared context ──
set -euo pipefail
SCHOLAR_MONITOR_DIR="${SCHOLAR_MONITOR_DIR:-$HOME/.claude/scholar-monitor}"
SM_SOURCES="$SCHOLAR_MONITOR_DIR/sources.json"
SM_STATE="$SCHOLAR_MONITOR_DIR/state.json"
SM_CONFIG="$SCHOLAR_MONITOR_DIR/config.json"
SM_ARCHIVE="$SCHOLAR_MONITOR_DIR/archive.ndjson"
SKILL_ASSETS="${SCHOLAR_SKILL_DIR}/.claude/skills/scholar-monitor/assets"

if [ ! -f "$SM_SOURCES" ]; then
    echo "[setup] First run — bootstrapping $SCHOLAR_MONITOR_DIR"
    cp "$SKILL_ASSETS/default-sources.json" "$SM_SOURCES"
    echo '{"version":"1.0","sources":{}}' > "$SM_STATE"
    cat > "$SM_CONFIG" <<'CFG'
{
  "version": "1.0",
  "channels": ["file"],
  "telegram": { "chat_id": "" },
  "ntfy":     { "topic": "" },
  "email": {
    "smtp_host": "", "smtp_port": 587,
    "from": "", "to": "", "pass_env": "SMTP_PASS"
  }
}
CFG
    chmod 0600 "$SM_CONFIG"
    touch "$SM_ARCHIVE"
    echo "[setup] Wrote: sources.json, state.json, config.json (chmod 0600), archive.ndjson"
    echo "[setup] /scholar-monitor configure delivery — add Telegram/ntfy push"
fi
```

### 0d. Validate sources.json (fail loud)

```bash
# ── shared context ──
SCHOLAR_MONITOR_DIR="${SCHOLAR_MONITOR_DIR:-$HOME/.claude/scholar-monitor}"
SM_SOURCES="$SCHOLAR_MONITOR_DIR/sources.json"

if ! python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$SM_SOURCES" 2>/dev/null; then
    echo "HALT: $SM_SOURCES is not valid JSON. Fix it before proceeding."
    echo "      Validate with:  python3 -m json.tool < $SM_SOURCES"
    exit 1
fi
echo "[validate] sources.json OK"
```

---

## Mode Dispatch

Match the first token of `$ARGUMENTS`. Dispatch to the matching section.

| First token | Mode |
|---|---|
| `init` | **MODE 1**: Bootstrap (already done in 0c; just confirm + print next steps) |
| `list`, `ls`, `sources` | **MODE 2**: List sources + last-seen |
| `status`, `stats`, `dashboard` | **MODE 3**: Dashboard |
| `add` | **MODE 4**: Add a source interactively |
| `remove`, `rm`, `disable` | **MODE 5**: Remove / disable a source |
| `configure` (with second token `delivery`) | **MODE 6**: Configure delivery channels |
| `digest` | **MODE 7**: Regenerate digest from archive |
| `preview`, `dry-run` | **MODE 8**: Show what would fetch, no network calls |
| `all` | **MODE 0 — force-fetch** every enabled source |
| (empty) | **MODE 0 — default fetch** every *due* enabled source |
| anything else | **MODE 0 — targeted fetch** treating token as a `source_id` (override cadence) |

---

## MODE 0: Default / Targeted Fetch

Follow Phases 1–9 in order. Each phase is a separate Bash tool call; every block re-derives variables and (where noted) re-loads KG helpers.

### Phase 1 — Source Selection

```bash
# ── shared context ──
set -euo pipefail
SCHOLAR_MONITOR_DIR="${SCHOLAR_MONITOR_DIR:-$HOME/.claude/scholar-monitor}"
SM_SOURCES="$SCHOLAR_MONITOR_DIR/sources.json"
SM_STATE="$SCHOLAR_MONITOR_DIR/state.json"
RUN_DIR=$(cat "$SCHOLAR_MONITOR_DIR/.current-run")
MODE_ARG=$(cat "$RUN_DIR/mode.txt")

python3 - "$SM_SOURCES" "$SM_STATE" "$MODE_ARG" > "$RUN_DIR/selected.jsonl" <<'PYEOF'
import json, sys
from datetime import datetime, timezone, timedelta

sources_path, state_path, mode_arg = sys.argv[1], sys.argv[2], sys.argv[3]
with open(sources_path) as fh: reg = json.load(fh)
try:
    with open(state_path) as fh: state = json.load(fh)
except (FileNotFoundError, json.JSONDecodeError):
    state = {"version": "1.0", "sources": {}}
now = datetime.now(timezone.utc)

explicit = mode_arg and mode_arg not in ("", "all")
force_all = mode_arg == "all"
lookback = reg.get("defaults", {}).get("first_run_lookback_days", 14)

known_ids = {s["id"] for s in reg.get("sources", [])}
if explicit and mode_arg not in known_ids:
    print(f"ERROR: unknown source_id '{mode_arg}'. Run /scholar-monitor list.", file=sys.stderr)
    sys.exit(2)

for src in reg.get("sources", []):
    if not src.get("enabled", False) and not explicit:
        continue
    if explicit and src["id"] != mode_arg:
        continue
    st = state.get("sources", {}).get(src["id"], {})
    last_run_s = st.get("last_run", "")
    due = True
    reason = "never run"
    if last_run_s and not explicit and not force_all:
        try:
            last_run = datetime.fromisoformat(last_run_s.replace("Z", "+00:00"))
            cadence = src.get("cadence_days", 7)
            next_due = last_run + timedelta(days=cadence)
            if now < next_due:
                due = False
                reason = f"next due {next_due.date()}"
            else:
                reason = f"elapsed >{cadence}d"
        except ValueError:
            pass
    if not due:
        continue
    since = st.get("last_seen_date", "")
    if not since:
        since = (now - timedelta(days=lookback)).strftime("%Y-%m-%d")
    src_out = dict(src)
    src_out["_since"] = since
    src_out["_reason"] = reason
    src_out["_last_seen_ids"] = st.get("last_seen_ids", [])
    src_out["_total_seen"] = st.get("total_seen", 0)
    print(json.dumps(src_out, ensure_ascii=False))
PYEOF

SEL_COUNT=$(wc -l < "$RUN_DIR/selected.jsonl" | tr -d ' ')
echo "[selection] $SEL_COUNT source(s) selected"
if [ "$SEL_COUNT" = "0" ]; then
    echo "[selection] Nothing due. Run /scholar-monitor list to see next-due dates."
    echo "done" > "$RUN_DIR/early-exit.flag"
    exit 0
fi
while IFS= read -r src_line; do
    id=$(echo "$src_line" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['id'])")
    since=$(echo "$src_line" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['_since'])")
    reason=$(echo "$src_line" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['_reason'])")
    echo "  - $id (since $since, $reason)"
done < "$RUN_DIR/selected.jsonl"
```

If `$RUN_DIR/early-exit.flag` exists after this block, skip all remaining phases.

### Phase 2 — Fetch Loop (per-source, failure-isolating)

```bash
# ── shared context ──
set -euo pipefail
SCHOLAR_MONITOR_DIR="${SCHOLAR_MONITOR_DIR:-$HOME/.claude/scholar-monitor}"
SM_SOURCES="$SCHOLAR_MONITOR_DIR/sources.json"
SKILL_ASSETS="${SCHOLAR_SKILL_DIR}/.claude/skills/scholar-monitor/assets"
RUN_DIR=$(cat "$SCHOLAR_MONITOR_DIR/.current-run")

EMAIL="${SCHOLAR_CROSSREF_EMAIL:-$(python3 -c "import json; print(json.load(open('$SM_SOURCES')).get('defaults',{}).get('crossref_email',''))")}"

> "$RUN_DIR/new-papers.jsonl"
> "$RUN_DIR/errors.log"
> "$RUN_DIR/failed-sources.txt"
> "$RUN_DIR/ok-sources.txt"

while IFS= read -r src_line; do
    SRC_ID=$(echo "$src_line" | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")
    SINCE=$(echo "$src_line" | python3 -c "import json,sys; print(json.load(sys.stdin)['_since'])")
    MAX=$(echo "$src_line" | python3 -c "import json,sys; print(json.load(sys.stdin).get('max_per_tick',20))")
    SRC_CLEAN=$(echo "$src_line" | python3 -c "import json,sys; d=json.load(sys.stdin); print(json.dumps({k:v for k,v in d.items() if not k.startswith('_')}))")

    echo "[fetch] $SRC_ID: since=$SINCE max=$MAX"
    TMP_OUT="$RUN_DIR/fetch-${SRC_ID}.jsonl"
    if python3 "$SKILL_ASSETS/fetch.py" \
        --source-json "$SRC_CLEAN" \
        --since "$SINCE" --max "$MAX" --email "$EMAIL" \
        > "$TMP_OUT" 2>> "$RUN_DIR/errors.log"
    then
        cat "$TMP_OUT" >> "$RUN_DIR/new-papers.jsonl"
        echo "$SRC_ID" >> "$RUN_DIR/ok-sources.txt"
        N=$(wc -l < "$TMP_OUT" | tr -d ' ')
        echo "[fetch] $SRC_ID: OK ($N records)"
    else
        rc=$?
        echo "[fetch] $SRC_ID: FAILED (rc=$rc)"
        echo "$SRC_ID" >> "$RUN_DIR/failed-sources.txt"
        # Deliberately do NOT append partial output — treat source as fully failed
        rm -f "$TMP_OUT"
    fi
done < "$RUN_DIR/selected.jsonl"

RAW_COUNT=$(wc -l < "$RUN_DIR/new-papers.jsonl" | tr -d ' ')
FAIL_COUNT=$(wc -l < "$RUN_DIR/failed-sources.txt" | tr -d ' ')
echo "[fetch] $RAW_COUNT raw records; $FAIL_COUNT source(s) failed"
```

### Phase 3 — Dedup (re-loads KG helpers)

```bash
# ── shared context + KG helpers ──
set -euo pipefail
SCHOLAR_MONITOR_DIR="${SCHOLAR_MONITOR_DIR:-$HOME/.claude/scholar-monitor}"
SM_STATE="$SCHOLAR_MONITOR_DIR/state.json"
RUN_DIR=$(cat "$SCHOLAR_MONITOR_DIR/.current-run")

# Re-load KG helpers — shell functions don't persist across Bash calls
SHARED_KG="${SCHOLAR_SKILL_DIR}/.claude/skills/_shared/knowledge-graph-search.md"
if [ -f "$SHARED_KG" ]; then
    eval "$(sed -n '/^```bash/,/^```/p' "$SHARED_KG" | sed '1d;$d')" 2>/dev/null || true
fi
KG_PAPERS_PATH="${KG_PAPERS:-}"   # set by the eval'd init block; empty if KG not installed

python3 - "$SM_STATE" "$KG_PAPERS_PATH" "$RUN_DIR/new-papers.jsonl" "$RUN_DIR/dedup.jsonl" <<'PYEOF'
import json, sys, os, re

state_path, kg_path, new_path, out_path = sys.argv[1:5]
ARXIV_VER = re.compile(r"v\d+$")

def _key(rec):
    """Dedup key — same normalization as fetch.py arxiv_id handling."""
    doi = (rec.get("doi") or "").lower()
    if doi:
        return doi
    ax = ARXIV_VER.sub("", (rec.get("arxiv_id") or "").lower())
    if ax:
        return ax
    return (rec.get("title", "")[:80] or "").lower()

seen = set()
try:
    with open(state_path) as fh: state = json.load(fh)
    for sid, st in state.get("sources", {}).items():
        for x in st.get("last_seen_ids", []):
            seen.add(ARXIV_VER.sub("", x.lower()))
except Exception:
    pass

kg_dois = set()
if kg_path and os.path.exists(kg_path):
    with open(kg_path) as fh:
        for ln in fh:
            if '"doi":"' in ln:
                i = ln.index('"doi":"') + 7
                j = ln.index('"', i)
                if j > i:
                    kg_dois.add(ln[i:j].lower())

kept = 0
dropped = 0
with open(new_path) as fin, open(out_path, "w") as fout:
    for ln in fin:
        try:
            rec = json.loads(ln)
        except json.JSONDecodeError:
            continue
        key = _key(rec)
        if not key:
            continue
        if key in seen or (rec.get("doi") and rec["doi"].lower() in kg_dois):
            dropped += 1
            continue
        seen.add(key)
        fout.write(json.dumps(rec, ensure_ascii=False) + "\n")
        kept += 1

print(f"[dedup] kept={kept} dropped_duplicates={dropped}", file=sys.stderr)
PYEOF

NEW_COUNT=$(wc -l < "$RUN_DIR/dedup.jsonl" | tr -d ' ')
echo "[dedup] $NEW_COUNT new papers after dedup"
echo "$NEW_COUNT" > "$RUN_DIR/new-count.txt"

if [ "$NEW_COUNT" = "0" ]; then
    echo "[result] Nothing new since last run. Updating last_run timestamp only."
    NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    python3 - "$SM_STATE" "$RUN_DIR/selected.jsonl" "$RUN_DIR/failed-sources.txt" "$NOW" <<'PYEOF'
import json, sys, os
state_path, sel_path, failed_path, now = sys.argv[1:5]
try:
    with open(state_path) as fh: state = json.load(fh)
except Exception:
    state = {"version": "1.0", "sources": {}}
state.setdefault("sources", {})
failed = set()
if os.path.exists(failed_path):
    with open(failed_path) as fh:
        failed = {ln.strip() for ln in fh if ln.strip()}
with open(sel_path) as fh:
    for ln in fh:
        sid = json.loads(ln)["id"]
        st = state["sources"].setdefault(sid, {})
        st["last_run"] = now
        if sid in failed:
            st["last_error"] = "fetch failed — see run logs"
        else:
            st["last_error"] = None
tmp = state_path + ".tmp"
with open(tmp, "w") as fh: json.dump(state, fh, indent=2)
os.replace(tmp, state_path)
PYEOF
    echo "done" > "$RUN_DIR/early-exit.flag"
fi
```

If `$RUN_DIR/early-exit.flag` exists after this block, skip to Phase 9 cleanup.

### Phase 4 — Summarize + Write Digest File

**This phase is executed by you (Claude), not by a script.**

1. Read context: `RUN_DIR=$(cat ~/.claude/scholar-monitor/.current-run)` and then Read `$RUN_DIR/dedup.jsonl` (one paper per line).
2. For each paper, write a **2–3 sentence plain-language summary** from title + abstract. Stick to what the abstract says — no speculation. If the abstract is empty, write: *"No abstract available. Title: <title>."*
3. Group papers by `category`.
4. Ordering — apply as a stable composite sort:
   - **Category order**: desc by total-new-count in that category; ties broken by category name asc.
   - **Paper order within category**: primary key `published_date` desc; secondary key `title` asc; papers with empty `published_date` sort last.
5. Use the Write tool to write `output/monitor/feed-YYYY-MM-DD.md`. If the file already exists for today, append a timestamped sub-header (`## Run at HH:MM:SS`) rather than overwriting.

Digest format:

```markdown
# Scholar Monitor — YYYY-MM-DD

Run at HH:MM:SS — N new papers across K categories.

## <Category 1>

### <Title 1>
**<Authors>** · *<Journal>* · <YYYY-MM-DD> · [<DOI or URL>]

<Your 2–3 sentence summary.>

### <Title 2>
…

## <Category 2>
…
```

### Phase 5 — Delivery (stacked channels)

```bash
# ── shared context ──
set -euo pipefail
SCHOLAR_MONITOR_DIR="${SCHOLAR_MONITOR_DIR:-$HOME/.claude/scholar-monitor}"
SM_CONFIG="$SCHOLAR_MONITOR_DIR/config.json"
SM_LOGS="$SCHOLAR_MONITOR_DIR/logs"
SKILL_ASSETS="${SCHOLAR_SKILL_DIR}/.claude/skills/scholar-monitor/assets"
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
RUN_DIR=$(cat "$SCHOLAR_MONITOR_DIR/.current-run")

# Re-derive NEW_COUNT (doesn't persist across Bash calls)
NEW_COUNT=$(cat "$RUN_DIR/new-count.txt" 2>/dev/null || echo 0)
FEED="${OUTPUT_ROOT}/monitor/feed-$(date +%Y-%m-%d).md"
CHANNELS=$(python3 -c "import json; print(' '.join(json.load(open('$SM_CONFIG'))['channels']))")

echo "[deliver] new=$NEW_COUNT  channels: $CHANNELS"

# ── ntfy (push via POST)
if echo "$CHANNELS" | grep -qw ntfy; then
    TOPIC=$(python3 -c "import json; print(json.load(open('$SM_CONFIG')).get('ntfy',{}).get('topic',''))")
    if [ -n "$TOPIC" ] && [ -f "$FEED" ]; then
        python3 "$SKILL_ASSETS/deliver.py" ntfy \
            --topic "$TOPIC" \
            --title "scholar-monitor — $NEW_COUNT new papers" \
            --body-file "$FEED" \
            --priority default \
            2>> "$SM_LOGS/deliver-$(date +%Y-%m-%d).log" \
            && echo "[deliver] ntfy: OK" \
            || echo "[deliver] ntfy: FAILED (see $SM_LOGS/deliver-...log)"
    fi
fi

# ── email (SMTP)
if echo "$CHANNELS" | grep -qw email; then
    SMTP_HOST=$(python3 -c "import json; print(json.load(open('$SM_CONFIG'))['email'].get('smtp_host',''))")
    if [ -n "$SMTP_HOST" ] && [ -f "$FEED" ]; then
        EMAIL_TO=$(python3 -c "import json; print(json.load(open('$SM_CONFIG'))['email'].get('to',''))")
        EMAIL_FROM=$(python3 -c "import json; print(json.load(open('$SM_CONFIG'))['email'].get('from',''))")
        SMTP_PORT=$(python3 -c "import json; print(json.load(open('$SM_CONFIG'))['email'].get('smtp_port',587))")
        PASS_ENV=$(python3 -c "import json; print(json.load(open('$SM_CONFIG'))['email'].get('pass_env','SMTP_PASS'))")
        python3 "$SKILL_ASSETS/deliver.py" email \
            --to "$EMAIL_TO" \
            --subject "scholar-monitor digest — $(date +%Y-%m-%d) ($NEW_COUNT new)" \
            --body-file "$FEED" \
            --smtp-host "$SMTP_HOST" --smtp-port "$SMTP_PORT" \
            --from "$EMAIL_FROM" --pass-env "$PASS_ENV" \
            2>> "$SM_LOGS/deliver-$(date +%Y-%m-%d).log" \
            && echo "[deliver] email: OK" \
            || echo "[deliver] email: FAILED"
    fi
fi
```

**Telegram delivery** (if `telegram` is in `$CHANNELS`): call the MCP tool directly in a *separate tool call*, not in the Bash block above.

1. Read `chat_id` from `~/.claude/scholar-monitor/config.json` via a quick Bash read.
2. Derive `NEW_COUNT` and the feed path (same as above).
3. Build a short message body (≤4000 chars): header line with count, then the top 3 titles as bullets, then a note that the full markdown is attached.
4. Call `mcp__plugin_telegram_telegram__reply` with: `chat_id`, `text` (that short body), `files: ["<absolute path to feed file>"]`. Omit `reply_to`.
5. If the MCP call errors, log it and continue — do not abort the run.

### Phase 6 — Knowledge-Graph Ingest (re-loads KG helpers)

```bash
# ── shared context + KG helpers (re-loaded; functions don't persist) ──
set -euo pipefail
SCHOLAR_MONITOR_DIR="${SCHOLAR_MONITOR_DIR:-$HOME/.claude/scholar-monitor}"
SM_ARCHIVE="$SCHOLAR_MONITOR_DIR/archive.ndjson"
RUN_DIR=$(cat "$SCHOLAR_MONITOR_DIR/.current-run")
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)

SHARED_KG="${SCHOLAR_SKILL_DIR}/.claude/skills/_shared/knowledge-graph-search.md"
if [ -f "$SHARED_KG" ]; then
    eval "$(sed -n '/^```bash/,/^```/p' "$SHARED_KG" | sed '1d;$d')" 2>/dev/null || true
fi

INGESTED=0
SKIPPED_KG=0

if ! command -v kg_append_paper >/dev/null 2>&1; then
    echo "[kg] helpers unavailable — skipping knowledge-graph ingest"
else
    mkdir -p "$KNOWLEDGE_DIR"
    while IFS= read -r paper_line; do
        [ -z "$paper_line" ] && continue
        DOI=$(echo "$paper_line" | python3 -c "import json,sys; print(json.load(sys.stdin).get('doi',''))")
        TITLE=$(echo "$paper_line" | python3 -c "import json,sys; print(json.load(sys.stdin).get('title',''))")
        EXISTS=$(kg_has_paper "$DOI" "$TITLE")
        if [ "$EXISTS" != "no" ]; then
            SKIPPED_KG=$((SKIPPED_KG+1))
            continue
        fi
        KG_LINE=$(echo "$paper_line" | python3 <<'PYEOF'
import json, sys, hashlib, datetime, re
r = json.loads(sys.stdin.read())
ARXIV_VER = re.compile(r"v\d+$")
ax = ARXIV_VER.sub("", r.get("arxiv_id") or "")
key = (r.get("doi") or ax or r.get("title","")[:80]).lower()
pid = "paper_" + hashlib.sha256(key.encode()).hexdigest()[:12]
now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
node = {
    "id": pid, "type": "paper",
    "doi": r.get("doi",""), "title": r.get("title",""),
    "authors": r.get("authors",[]), "year": r.get("year",0),
    "journal": r.get("journal",""), "volume": "", "issue": "", "pages": "",
    "abstract": r.get("abstract",""), "zotero_key": "", "pdf_path": "",
    "findings": [], "mechanisms": [], "theories": [], "methods": [],
    "populations": [], "data_sources": [],
    "key_quotes": [], "gap_claims": [], "limitations": [], "future_directions": [],
    "ingested_at": now, "updated_at": now,
    "source": "scholar-monitor",
    "projects": [],
    "raw_path": "",
    "extraction_tier": "abstract_only",
    "monitor_source_id": r.get("source_id",""),
    "monitor_category": r.get("category",""),
    "monitor_url": r.get("url",""),
}
print(json.dumps(node, ensure_ascii=False))
PYEOF
)
        kg_append_paper "$KG_LINE"
        INGESTED=$((INGESTED+1))
    done < "$RUN_DIR/dedup.jsonl"
    kg_update_meta 2>/dev/null || true
fi
echo "[kg] ingested=$INGESTED skipped_title_dup=$SKIPPED_KG"

# Append to monitor's own archive (always, even if KG is unavailable)
python3 - "$RUN_DIR/dedup.jsonl" "$SM_ARCHIVE" "$NOW" <<'PYEOF'
import json, sys
new_path, archive_path, now = sys.argv[1], sys.argv[2], sys.argv[3]
with open(new_path) as fin, open(archive_path, "a") as fout:
    for ln in fin:
        try: rec = json.loads(ln)
        except json.JSONDecodeError: continue
        rec["delivered_at"] = now
        fout.write(json.dumps(rec, ensure_ascii=False) + "\n")
PYEOF
```

### Phase 7 — Update State (respects per-source failures)

```bash
# ── shared context ──
set -euo pipefail
SCHOLAR_MONITOR_DIR="${SCHOLAR_MONITOR_DIR:-$HOME/.claude/scholar-monitor}"
SM_STATE="$SCHOLAR_MONITOR_DIR/state.json"
RUN_DIR=$(cat "$SCHOLAR_MONITOR_DIR/.current-run")
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)

python3 - "$SM_STATE" "$RUN_DIR/selected.jsonl" "$RUN_DIR/dedup.jsonl" "$RUN_DIR/failed-sources.txt" "$NOW" <<'PYEOF'
import json, sys, os, collections, re

state_path, sel_path, new_path, failed_path, now = sys.argv[1:6]
ARXIV_VER = re.compile(r"v\d+$")

try:
    with open(state_path) as fh: state = json.load(fh)
except Exception:
    state = {"version": "1.0", "sources": {}}
state.setdefault("sources", {})

failed = set()
if os.path.exists(failed_path):
    with open(failed_path) as fh:
        failed = {ln.strip() for ln in fh if ln.strip()}

def _key(r):
    if r.get("doi"): return r["doi"].lower()
    ax = ARXIV_VER.sub("", (r.get("arxiv_id") or "").lower())
    if ax: return ax
    return (r.get("title","")[:80] or "").lower()

per_source = collections.defaultdict(list)
with open(new_path) as fh:
    for ln in fh:
        try: r = json.loads(ln)
        except json.JSONDecodeError: continue
        sid = r.get("source_id","")
        per_source[sid].append((r.get("published_date","") or "", _key(r)))

with open(sel_path) as fh:
    for ln in fh:
        s = json.loads(ln)
        sid = s["id"]
        st = state["sources"].setdefault(sid, {})
        st["last_run"] = now
        if sid in failed:
            # CRITICAL: don't advance last_seen_date on failed fetches — next tick must retry
            st["last_error"] = "fetch failed — see run logs"
            continue
        st["last_error"] = None
        new_for_source = per_source.get(sid, [])
        if new_for_source:
            # Only advance if we saw dated papers — empty dates don't update the cursor
            dated = [d for d, _ in new_for_source if d]
            if dated:
                st["last_seen_date"] = max(dated)
            old_ids = st.get("last_seen_ids", [])
            new_ids = [k for _, k in new_for_source]
            combined = new_ids + [x for x in old_ids if x not in new_ids]
            st["last_seen_ids"] = combined[:200]
            st["total_seen"] = st.get("total_seen", 0) + len(new_for_source)

tmp = state_path + ".tmp"
with open(tmp, "w") as fh: json.dump(state, fh, indent=2)
os.replace(tmp, state_path)
print("[state] updated (failed sources not advanced)", file=sys.stderr)
PYEOF
```

### Phase 8 — Summary Report

Print a concise summary to the conversation:

```
scholar-monitor — run complete
  Selected:        N sources
  OK:              [list of source_ids from $RUN_DIR/ok-sources.txt]
  Failed:          [list from $RUN_DIR/failed-sources.txt, or "none"]
  New papers:      M
  Delivered via:   [channels from config + whether each OK]
  KG ingested:     K (skipped D title-dupes)
  Feed file:       output/monitor/feed-YYYY-MM-DD.md
  Error log:       $SM_LOGS/deliver-YYYY-MM-DD.log (if any channel failed)
```

### Phase 9 — Cleanup

```bash
# ── shared context ──
set -euo pipefail
SCHOLAR_MONITOR_DIR="${SCHOLAR_MONITOR_DIR:-$HOME/.claude/scholar-monitor}"
RUN_DIR=$(cat "$SCHOLAR_MONITOR_DIR/.current-run" 2>/dev/null)

# Keep the latest 5 run-dirs for postmortem; delete older
if [ -d "$SCHOLAR_MONITOR_DIR/tmp" ]; then
    ls -1td "$SCHOLAR_MONITOR_DIR/tmp/"run-* 2>/dev/null | tail -n +6 | xargs -I{} rm -rf "{}" 2>/dev/null || true
fi
echo "[cleanup] kept last 5 run-dirs under $SCHOLAR_MONITOR_DIR/tmp/"
```

---

## MODE 1: `init`

Bootstrapping already happens in Phase 0c. Additionally print:

```
scholar-monitor is initialized.
  Config dir:  $SCHOLAR_MONITOR_DIR
  Sources:     $SM_SOURCES

Enabled by default: asr, arxiv-llm, nhb

Next steps:
  1. Edit sources.json to enable more journals or add arXiv queries
     (see registry-guide.md for ISSN lookup + schema)
  2. /scholar-monitor configure delivery    — add Telegram or ntfy push
  3. /scholar-monitor arxiv-llm             — test-fetch one source
  4. /loop 24h /scholar-monitor             — schedule daily digest
```

---

## MODE 2: `list`

```bash
# ── shared context ──
set -euo pipefail
SCHOLAR_MONITOR_DIR="${SCHOLAR_MONITOR_DIR:-$HOME/.claude/scholar-monitor}"
SM_SOURCES="$SCHOLAR_MONITOR_DIR/sources.json"
SM_STATE="$SCHOLAR_MONITOR_DIR/state.json"

python3 - "$SM_SOURCES" "$SM_STATE" <<'PYEOF'
import json, sys
from datetime import datetime, timezone, timedelta
reg = json.load(open(sys.argv[1]))
try: st = json.load(open(sys.argv[2]))
except: st = {"sources": {}}
now = datetime.now(timezone.utc)
print(f"{'ID':<22} {'EN':<3} {'TYPE':<10} {'CAD':<5} {'LAST SEEN':<12} {'NEXT DUE':<14} CATEGORY")
print("-" * 112)
for s in reg.get("sources", []):
    sst = st.get("sources", {}).get(s["id"], {})
    cad = s.get("cadence_days", 7)
    last_run = sst.get("last_run", "")
    last_seen = sst.get("last_seen_date", "-")
    next_due = "-"
    if last_run:
        try:
            lr = datetime.fromisoformat(last_run.replace("Z","+00:00"))
            nd = lr + timedelta(days=cad)
            next_due = nd.date().isoformat()
            if nd <= now: next_due += " *"
        except: pass
    en = "Y" if s.get("enabled") else " "
    err = " [err]" if sst.get("last_error") else ""
    print(f"{s['id']:<22} {en:<3} {s.get('type',''):<10} {cad:<5} {last_seen:<12} {next_due:<14} {s.get('category','')}{err}")
PYEOF
```

---

## MODE 3: `status`

```bash
# ── shared context ──
set -euo pipefail
SCHOLAR_MONITOR_DIR="${SCHOLAR_MONITOR_DIR:-$HOME/.claude/scholar-monitor}"
SM_SOURCES="$SCHOLAR_MONITOR_DIR/sources.json"
SM_STATE="$SCHOLAR_MONITOR_DIR/state.json"
SM_ARCHIVE="$SCHOLAR_MONITOR_DIR/archive.ndjson"
SM_CONFIG="$SCHOLAR_MONITOR_DIR/config.json"

python3 - "$SM_SOURCES" "$SM_STATE" "$SM_ARCHIVE" "$SM_CONFIG" <<'PYEOF'
import json, sys, os
from datetime import datetime, timezone, timedelta

reg = json.load(open(sys.argv[1]))
try: st = json.load(open(sys.argv[2]))
except: st = {"sources": {}}
arch = sys.argv[3]
cfg = json.load(open(sys.argv[4]))

print("\n=== scholar-monitor — status ===\n")
enabled = [s for s in reg.get("sources",[]) if s.get("enabled")]
print(f"Sources:   {len(enabled)} enabled / {len(reg.get('sources',[]))} total")

total_archive = 0
last_7d = 0
now = datetime.now(timezone.utc)
week_ago = now - timedelta(days=7)
if os.path.exists(arch):
    with open(arch) as fh:
        for ln in fh:
            total_archive += 1
            try:
                d = json.loads(ln).get("delivered_at","")
                if d and datetime.fromisoformat(d.replace("Z","+00:00")) > week_ago:
                    last_7d += 1
            except: pass
arch_size_kb = os.path.getsize(arch) // 1024 if os.path.exists(arch) else 0
print(f"Archive:   {total_archive} papers total ({arch_size_kb} KB), {last_7d} in last 7 days")
print(f"Delivery:  {', '.join(cfg.get('channels',['file']))}")
tg = cfg.get("telegram",{}).get("chat_id","")
nt = cfg.get("ntfy",{}).get("topic","")
em = cfg.get("email",{}).get("smtp_host","")
print(f"           telegram chat_id: {'set' if tg else 'unset'}")
print(f"           ntfy topic:       {'set' if nt else 'unset'}")
print(f"           email smtp_host:  {'set' if em else 'unset'}")

overdue = []
errored = []
for s in enabled:
    sst = st.get("sources",{}).get(s["id"], {})
    if sst.get("last_error"):
        errored.append((s["id"], sst["last_error"]))
    lr = sst.get("last_run","")
    if not lr:
        overdue.append((s["id"], "never run"))
        continue
    try:
        lrd = datetime.fromisoformat(lr.replace("Z","+00:00"))
        nd = lrd + timedelta(days=s.get("cadence_days",7))
        if nd <= now:
            overdue.append((s["id"], f"{(now-nd).days}d overdue"))
    except: pass

if overdue:
    print(f"\nOverdue:   {len(overdue)} source(s)")
    for sid, why in overdue: print(f"  - {sid}: {why}")
else:
    print("\nOverdue:   none")

if errored:
    print(f"\nErrors:    {len(errored)} source(s)")
    for sid, e in errored: print(f"  - {sid}: {e}")

print()
PYEOF
```

---

## MODE 4: `add`

Use `AskUserQuestion` to collect: backend type, identifier (issn/query/url), id, category, cadence_days, max_per_tick, enabled. Then substitute the collected values into this block:

```bash
# ── shared context ──
set -euo pipefail
SCHOLAR_MONITOR_DIR="${SCHOLAR_MONITOR_DIR:-$HOME/.claude/scholar-monitor}"
SM_SOURCES="$SCHOLAR_MONITOR_DIR/sources.json"

# Claude substitutes the values below from AskUserQuestion responses.
NEW_SRC_JSON='[new_source_json]'

python3 - "$SM_SOURCES" "$NEW_SRC_JSON" <<'PYEOF'
import json, sys, os
path, new_json = sys.argv[1], sys.argv[2]
reg = json.load(open(path))
new = json.loads(new_json)
# Prevent duplicate id
if any(s["id"] == new["id"] for s in reg["sources"]):
    print(f"ERROR: source id '{new['id']}' already exists"); sys.exit(1)
reg["sources"].append(new)
with open(path + ".tmp","w") as fh: json.dump(reg, fh, indent=2)
os.replace(path + ".tmp", path)
print(f"[add] appended {new['id']}")
PYEOF
```

Then call `/scholar-monitor list` to confirm.

---

## MODE 5: `remove`

Claude substitutes `[target_id]` from the second token of `$ARGUMENTS`:

```bash
# ── shared context ──
set -euo pipefail
SCHOLAR_MONITOR_DIR="${SCHOLAR_MONITOR_DIR:-$HOME/.claude/scholar-monitor}"
SM_SOURCES="$SCHOLAR_MONITOR_DIR/sources.json"

TARGET_ID="[target_id]"   # ← Claude substitutes from 2nd token of $ARGUMENTS
if [ -z "$TARGET_ID" ] || [ "$TARGET_ID" = "[target_id]" ]; then
    echo "Usage: /scholar-monitor remove <source_id>"
    exit 1
fi

python3 - "$SM_SOURCES" "$TARGET_ID" <<'PYEOF'
import json, sys, os
path, tid = sys.argv[1], sys.argv[2]
reg = json.load(open(path))
before = len(reg["sources"])
reg["sources"] = [s for s in reg["sources"] if s["id"] != tid]
if len(reg["sources"]) == before:
    print(f"[remove] no source with id '{tid}'"); sys.exit(1)
with open(path + ".tmp","w") as fh: json.dump(reg, fh, indent=2)
os.replace(path + ".tmp", path)
print(f"[remove] removed {tid}")
PYEOF
```

---

## MODE 6: `configure delivery`

Collect values via `AskUserQuestion`. Propose these questions in sequence (skip any the user declines):

1. **Enable Telegram push?** → if yes, look up `chat_id` from `~/.claude/telegram/access.json` or ask the user to paste it.
2. **Enable ntfy.sh push?** → if yes, recommend `openssl rand -hex 8` for the topic. Tell the user to install the ntfy app (iOS/Android) and subscribe to that topic.
3. **Enable email push (SMTP)?** → if yes, collect:
   - `smtp_host` (e.g., `smtp.gmail.com`)
   - `smtp_port` (default `587`)
   - `from` (sender email)
   - `to` (recipient — usually same as `from`)
   - `pass_env` (env var name holding the password; default `SMTP_PASS`)
   - Gmail-specific note: use an **App Password** (requires 2FA on the account), not the main password. Remind the user to `export SMTP_PASS="xxxx xxxx xxxx xxxx"` in their shell or `.env`.

Then substitute the values into this block. Pass empty strings for channels the user declined:

```bash
# ── shared context ──
set -euo pipefail
SCHOLAR_MONITOR_DIR="${SCHOLAR_MONITOR_DIR:-$HOME/.claude/scholar-monitor}"
SM_CONFIG="$SCHOLAR_MONITOR_DIR/config.json"

# Claude substitutes the 7 values below (empty strings if user declined).
TG_CHAT='[telegram_chat_id]'
NTFY_TOPIC='[ntfy_topic]'
SMTP_HOST='[smtp_host]'
SMTP_PORT='[smtp_port]'
EMAIL_FROM='[smtp_from]'
EMAIL_TO='[smtp_to]'
PASS_ENV='[smtp_pass_env]'

python3 - "$SM_CONFIG" "$TG_CHAT" "$NTFY_TOPIC" "$SMTP_HOST" "$SMTP_PORT" "$EMAIL_FROM" "$EMAIL_TO" "$PASS_ENV" <<'PYEOF'
import json, sys, os
path = sys.argv[1]
tg, ntfy, smtp, port, efrom, eto, passenv = sys.argv[2:9]
try: cfg = json.load(open(path))
except Exception: cfg = {"version":"1.0"}
channels = ["file"]
if tg: channels.append("telegram")
if ntfy: channels.append("ntfy")
if smtp and eto: channels.append("email")
cfg["channels"] = channels
cfg["telegram"] = {"chat_id": tg}
cfg["ntfy"]     = {"topic":    ntfy}
cfg["email"]    = {
    "smtp_host": smtp,
    "smtp_port": int(port) if port else 587,
    "from": efrom, "to": eto,
    "pass_env": passenv or "SMTP_PASS",
}
with open(path + ".tmp","w") as fh: json.dump(cfg, fh, indent=2)
os.replace(path + ".tmp", path)
os.chmod(path, 0o600)
print(f"[config] channels={channels}")
if "email" in channels and not os.environ.get(passenv or "SMTP_PASS"):
    print(f"[config] WARNING: ${passenv or 'SMTP_PASS'} is not set in your environment. Email delivery will fail until you export it.")
PYEOF
```

---

## MODE 7: `digest`

Regenerate a markdown digest from `archive.ndjson` for a given date range — no network calls.

```bash
# ── shared context ──
set -euo pipefail
SCHOLAR_MONITOR_DIR="${SCHOLAR_MONITOR_DIR:-$HOME/.claude/scholar-monitor}"
SM_ARCHIVE="$SCHOLAR_MONITOR_DIR/archive.ndjson"
RUN_DIR=$(cat "$SCHOLAR_MONITOR_DIR/.current-run")

# Claude substitutes from the second token of $ARGUMENTS; default "last-30".
RANGE='[date_range]'
if [ -z "$RANGE" ] || [ "$RANGE" = "[date_range]" ]; then
    RANGE="last-30"
fi

python3 - "$SM_ARCHIVE" "$RANGE" > "$RUN_DIR/digest.jsonl" <<'PYEOF'
import json, sys, re
from datetime import datetime, timezone, timedelta
arch, rng = sys.argv[1], sys.argv[2]
now = datetime.now(timezone.utc)
start, end = None, None
if rng == "last-30":
    start = now - timedelta(days=30); end = now
elif rng == "last-7":
    start = now - timedelta(days=7); end = now
elif re.match(r"\d{4}-\d{2}-\d{2}\.\.\d{4}-\d{2}-\d{2}", rng):
    s, e = rng.split("..")
    start = datetime.fromisoformat(s + "T00:00:00+00:00")
    end = datetime.fromisoformat(e + "T23:59:59+00:00")
else:
    print(f"ERROR: bad range '{rng}'. Try 'last-7', 'last-30', or 'YYYY-MM-DD..YYYY-MM-DD'", file=sys.stderr)
    sys.exit(2)
with open(arch) as fh:
    for ln in fh:
        try: r = json.loads(ln)
        except: continue
        d = r.get("delivered_at","")
        if not d: continue
        try: dt = datetime.fromisoformat(d.replace("Z","+00:00"))
        except: continue
        if start <= dt <= end:
            print(json.dumps(r, ensure_ascii=False))
PYEOF
DIGEST_COUNT=$(wc -l < "$RUN_DIR/digest.jsonl" | tr -d ' ')
echo "[digest] $DIGEST_COUNT papers in range $RANGE"
echo "Range: $RANGE" > "$RUN_DIR/digest-meta.txt"
```

Then Claude reads `$RUN_DIR/digest.jsonl` and writes the same Phase-4 markdown structure to `output/monitor/digest-<range>.md`. Do **not** re-ingest to KG (already done originally). Do **not** re-deliver via push channels unless the user explicitly asks.

---

## MODE 8: `preview` (dry-run)

Runs Phase 1 selection only — shows which sources *would* fetch on a real invocation, what their `since_date` would be, and their `max_per_tick` — without making any network calls or updating state.

```bash
# ── shared context ──
set -euo pipefail
SCHOLAR_MONITOR_DIR="${SCHOLAR_MONITOR_DIR:-$HOME/.claude/scholar-monitor}"
SM_SOURCES="$SCHOLAR_MONITOR_DIR/sources.json"
SM_STATE="$SCHOLAR_MONITOR_DIR/state.json"

python3 - "$SM_SOURCES" "$SM_STATE" <<'PYEOF'
import json, sys
from datetime import datetime, timezone, timedelta
reg = json.load(open(sys.argv[1]))
try: state = json.load(open(sys.argv[2]))
except: state = {"sources": {}}
now = datetime.now(timezone.utc)
lookback = reg.get("defaults", {}).get("first_run_lookback_days", 14)

due, not_due = [], []
for src in reg.get("sources", []):
    if not src.get("enabled"): continue
    sst = state.get("sources", {}).get(src["id"], {})
    lr = sst.get("last_run", "")
    cad = src.get("cadence_days", 7)
    if lr:
        try:
            lrd = datetime.fromisoformat(lr.replace("Z","+00:00"))
            nd = lrd + timedelta(days=cad)
            if now < nd:
                not_due.append((src["id"], nd.date().isoformat())); continue
        except: pass
    since = sst.get("last_seen_date","") or (now - timedelta(days=lookback)).strftime("%Y-%m-%d")
    due.append((src["id"], since, src.get("max_per_tick", 20), src.get("category","")))

print("\n=== scholar-monitor — preview (no network calls) ===\n")
print(f"Would fetch {len(due)} source(s):")
for sid, since, mx, cat in sorted(due):
    print(f"  - {sid:<22} since {since}  max {mx:>3}   [{cat}]")
print(f"\nSkipped (cadence not elapsed): {len(not_due)}")
for sid, nd in sorted(not_due):
    print(f"  - {sid:<22} next due {nd}")
print()
PYEOF
```

No state changes, no network calls. Use this before enabling a new source or before scheduling via `/loop`.

---

## `/loop` Integration Recipes

```
# Daily arXiv LLM digest
/loop 24h /scholar-monitor arxiv-llm

# Weekly full sweep across all due sources
/loop 7d /scholar-monitor

# Hourly check — harmless; cadence_days filter drops redundant ticks
/loop 1h /scholar-monitor

# Target a specific source on a custom cadence
/loop 12h /scholar-monitor nhb

# Dry-run: see what /loop 24h /scholar-monitor would do at the next tick
/scholar-monitor preview
```

**Why these are safe under /loop:**
- Phase 1 selection drops sources whose `last_run + cadence_days > now` — `/loop 1h` with a weekly source = one real digest per week.
- Phase 3 dedup drops DOIs/arxiv_ids already in `state.last_seen_ids` (last 200) or in `papers.ndjson`.
- Phase 7 skips `last_seen_date` advance for any source whose fetch failed — retries cleanly on the next tick.
- Atomic state writes (`os.replace`) prevent partial updates on interruption.
- Stable `$RUN_DIR` per invocation (not PID-based) survives cross-Bash-call state handoff.

For background scheduling when the terminal isn't open, use `/schedule` (remote-agent cron-style triggers) — same skill call, different scheduler.

---

## Quality Checklist

Before reporting the run complete, verify:

- [ ] `output/monitor/feed-<today>.md` exists and is non-empty when `NEW_COUNT > 0`
- [ ] `state.json` shows updated `last_run` for every selected source (even on zero-new, even on failure)
- [ ] `state.json` does **not** show updated `last_seen_date` for sources in `failed-sources.txt`
- [ ] `state.json` shows `last_error: "..."` for failed sources, `null` for successful ones
- [ ] Every entry in the feed has a real DOI, arXiv ID, or URL — no fabricated identifiers
- [ ] Summary prose for each paper sticks to the abstract — no speculation
- [ ] Papers grouped correctly by `category`; no paper appears in two categories
- [ ] Ordering follows: category (count desc, name asc); paper (date desc, title asc; empty dates last)
- [ ] Knowledge-graph ingest count matches new papers minus title-similarity duplicates (unless KG helpers unavailable, in which case the run explicitly says "helpers unavailable")
- [ ] Archive file (`archive.ndjson`) grew by exactly `NEW_COUNT` lines
- [ ] `$RUN_DIR/` was created under `$SCHOLAR_MONITOR_DIR/tmp/` (not `/tmp/`)

---

## Reference Loading

When working on a specific sub-task, load just the relevant reference:

- **[references/fetcher-protocols.md](references/fetcher-protocols.md)** — Crossref / arXiv / OpenAlex / RSS call patterns, normalized paper record schema, how to add a new backend
- **[references/registry-guide.md](references/registry-guide.md)** — `sources.json` schema, ISSN lookup table, arXiv categories, cadence rules of thumb, archive-rotation policy
- **[references/delivery-protocol.md](references/delivery-protocol.md)** — Telegram / ntfy / email / file channel specs, long-message chunking, config.json schema, security notes

Assets:

- **[assets/default-sources.json](assets/default-sources.json)** — starter registry (3 enabled + 19 disabled)
- **[assets/fetch.py](assets/fetch.py)** — Python fetcher (stdlib only; arxiv_id version-stripped; 1s Crossref sleep)
- **[assets/deliver.py](assets/deliver.py)** — ntfy + SMTP delivery helper
