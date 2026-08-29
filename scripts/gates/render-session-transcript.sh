#!/usr/bin/env bash
# render-session-transcript.sh — render a RAW Claude Code session transcript to
# browsable HTML, behind the project's data-safety gate.
#
# WHY THIS EXISTS
#   The RAO trace (emit-trace.sh -> render-trace.sh) is the project's CURATED
#   audit record: stated reasoning, verdicts, counts, file refs — policy-bound
#   by C-01 to carry no raw data. It is deliberately lossy. When a phase goes
#   wrong you often need the FORENSIC record instead: the actual tool calls,
#   their arguments, and their raw results. That lives only in Claude Code's
#   session JSONL under ~/.claude/projects/<munged-cwd>/<session-id>.jsonl.
#
#   This wrapper renders that JSONL to paginated HTML via simonw's
#   `claude-code-transcripts` (PyPI; run through `uvx`, no install required),
#   and is the companion to render-trace-html.sh: a trace record now carries a
#   `session_id`, so the RAO HTML view can deep-link into the transcript built
#   here. Curated view for "what did the pipeline decide"; raw view for "what
#   actually happened".
#
# ── SAFETY CONTRACT (read this before widening anything) ────────────────────
#   The session JSONL is the single most sensitive artifact in the project. It
#   records tool RESULTS verbatim — every `cat`, every Read, every LOCAL_MODE
#   `Rscript -e` heredoc's stdout. pretooluse-data-guard.sh governs what may be
#   READ; it cannot un-record a value once that value is in the transcript.
#
#   Policy implemented here (chosen 2026-08-20; "warn and proceed, block
#   --gist only"):
#     * LOCAL render — always allowed. The JSONL is already on this disk, so
#       rendering it to HTML beside it adds no new exposure. If the sidecar
#       reports any non-CLEARED entry we print a loud WARN naming the statuses
#       so the operator knows what the HTML may contain.
#     * --gist — HARD REFUSED (exit 3) unless EVERY sidecar entry is CLEARED.
#       A gist is a public, indexed, third-party publication; that is a
#       one-way door and is not a warn-level action. Refused too when the
#       sidecar is missing or unparseable: unknown is not CLEARED (fail closed).
#     * The output directory gets a self-ignoring .gitignore so the HTML can
#       never be committed by an incautious `git add -A`, regardless of where
#       OUTPUT_ROOT lives. (`output/` is already ignored at this repo's root,
#       but a project rendered under an external OUTPUT_ROOT is not covered by
#       that rule — hence the belt-and-braces local .gitignore.)
#
#   NOTE FOR OPERATORS: a local render is still a file on disk. If the project
#   lives in a synced folder (Dropbox/Drive/iCloud), "local" means "synced to
#   your cloud provider". Excluded from replication packages by construction —
#   it lives under logs/, which replication does not ship.
#
# USAGE
#   bash scripts/gates/render-session-transcript.sh [<project_dir>] [options]
#
#   --session <id>   Session to render. Default: $CLAUDE_CODE_SESSION_ID
#                    (i.e. the session you are running in right now).
#   --latest         Render the most recently modified session for --cwd.
#   --all            Render every session for --cwd (each to its own subdir).
#   --list           List discoverable sessions for --cwd and exit.
#   --cwd <path>     Working dir whose session history to search. Default: $PWD.
#   -o, --output <d> Output dir. Default: <project_dir>/logs/transcript-html.
#   --gist           Publish to a GitHub Gist. Gated — see SAFETY CONTRACT.
#   --open           Open the rendered index.html in a browser.
#   --dry-run        Run arg resolution + the safety gate, report the decision
#                    (WOULD_RENDER / GIST=allowed|blocked) and exit WITHOUT
#                    rendering. Use it to ask "would --gist be permitted here?"
#                    without publishing anything, and to test the gate offline.
#   --force          Acknowledge the non-CLEARED warning without prompting.
#                    (Does NOT unlock --gist; nothing unlocks --gist but an
#                    all-CLEARED sidecar.)
#
# ENVIRONMENT
#   CLAUDE_CODE_SESSION_ID  the running session (fallback CLAUDE_SESSION_ID);
#                           supplies the default --session.
#   CLAUDE_PROJECTS_DIR     override the session store root
#                           (default ~/.claude/projects). Used by the smoke
#                           test to point at a fixture store.
#
# EXIT CODES
#   0  rendered      (prints TRANSCRIPT_HTML=<path> per session)
#   1  usage error / session or JSONL not found
#   2  uvx or claude-code-transcripts unavailable
#   3  --gist refused by the safety gate
#   4  the underlying renderer failed
#
# FIXTURES: tests/smoke/test-session-transcript-html.sh

set -uo pipefail

PROJ_ARG="" SESSION="" OUT_DIR="" SEARCH_CWD=""
DO_LATEST=0 DO_ALL=0 DO_LIST=0 DO_GIST=0 DO_OPEN=0 DO_FORCE=0 DO_DRY=0

while [ $# -gt 0 ]; do
  case "$1" in
    --session)    SESSION="${2:-}"; shift 2 ;;
    --latest)     DO_LATEST=1; shift ;;
    --all)        DO_ALL=1; shift ;;
    --list)       DO_LIST=1; shift ;;
    --cwd)        SEARCH_CWD="${2:-}"; shift 2 ;;
    -o|--output)  OUT_DIR="${2:-}"; shift 2 ;;
    --gist)       DO_GIST=1; shift ;;
    --open)       DO_OPEN=1; shift ;;
    --force)      DO_FORCE=1; shift ;;
    --dry-run)    DO_DRY=1; shift ;;
    -h|--help)    grep -E '^#' "$0" | sed 's/^# *//;s/^#$//'; exit 0 ;;
    -*)           echo "ERROR: unknown flag $1" >&2; exit 1 ;;
    *)            if [ -z "$PROJ_ARG" ]; then PROJ_ARG="$1"; shift
                  else echo "ERROR: unexpected arg $1" >&2; exit 1; fi ;;
  esac
done

SEARCH_CWD="${SEARCH_CWD:-$PWD}"
PROJ="${PROJ_ARG:-$SEARCH_CWD}"
SESSIONS_ROOT="${CLAUDE_PROJECTS_DIR:-$HOME/.claude/projects}"

# ── Locate the session directory for a cwd ──────────────────────────────────
# Claude Code munges the absolute cwd into a directory name by replacing every
# '/', '.' and ' ' with '-'. Verified against this host: "/Users/u/.claude" ->
# "-Users-u--claude" (the slash AND the dot each become a dash), and a path
# with spaces ("…/My Drive/Some Folder/…") dashes the spaces too.
# We use the munge as a FAST PATH only; if it misses we fall back to reading
# the `cwd` field out of each session file, which is authoritative and immune
# to any future change in the munging rule.
munge_cwd() { printf '%s' "$1" | tr '/. ' '---'; }

session_dir_for_cwd() {
  local cwd="$1" cand
  cand="${SESSIONS_ROOT}/$(munge_cwd "$cwd")"
  if [ -d "$cand" ]; then printf '%s\n' "$cand"; return 0; fi
  # Fallback: authoritative scan of the recorded cwd in each session's first records.
  command -v python3 >/dev/null 2>&1 || return 1
  python3 - "$SESSIONS_ROOT" "$cwd" <<'PY'
import json, os, sys
root, want = sys.argv[1], os.path.realpath(sys.argv[2])
if not os.path.isdir(root):
    sys.exit(1)
for d in sorted(os.listdir(root)):
    full = os.path.join(root, d)
    if not os.path.isdir(full):
        continue
    for fn in os.listdir(full):
        if not fn.endswith(".jsonl"):
            continue
        try:
            with open(os.path.join(full, fn)) as fh:
                for _ in range(40):          # cwd appears in the early records
                    line = fh.readline()
                    if not line:
                        break
                    try:
                        rec = json.loads(line)
                    except Exception:
                        continue
                    c = rec.get("cwd")
                    if c and os.path.realpath(c) == want:
                        print(full)
                        sys.exit(0)
        except Exception:
            continue
sys.exit(1)
PY
}

# ── Locate a specific session JSONL anywhere under the projects root ─────────
jsonl_for_session() {
  local sid="$1" f
  for f in "$SESSIONS_ROOT"/*/"${sid}.jsonl"; do
    [ -f "$f" ] && { printf '%s\n' "$f"; return 0; }
  done
  return 1
}

SESSION_DIR="$(session_dir_for_cwd "$SEARCH_CWD" 2>/dev/null || true)"

# ── --list ──────────────────────────────────────────────────────────────────
if [ "$DO_LIST" -eq 1 ]; then
  if [ -z "$SESSION_DIR" ] || [ ! -d "$SESSION_DIR" ]; then
    echo "SESSIONS_FOUND=0"
    echo "No session directory for cwd: $SEARCH_CWD" >&2
    echo "  (looked under $SESSIONS_ROOT)" >&2
    exit 1
  fi
  echo "SESSION_DIR=$SESSION_DIR"
  n=0
  for f in "$SESSION_DIR"/*.jsonl; do
    [ -f "$f" ] || continue
    n=$((n + 1))
    b="$(basename "$f" .jsonl)"
    mark=""
    [ "$b" = "${CLAUDE_CODE_SESSION_ID:-}" ] && mark="  <- current"
    printf 'SESSION=%s  size=%s  mtime=%s%s\n' \
      "$b" "$(du -h "$f" 2>/dev/null | cut -f1)" \
      "$(date -r "$f" '+%Y-%m-%d %H:%M' 2>/dev/null || echo '?')" "$mark"
  done
  echo "SESSIONS_FOUND=$n"
  exit 0
fi

# ── Resolve which session(s) to render ──────────────────────────────────────
TARGETS=()
if [ "$DO_ALL" -eq 1 ]; then
  [ -n "$SESSION_DIR" ] && [ -d "$SESSION_DIR" ] || {
    echo "ERROR: --all needs a session directory for cwd: $SEARCH_CWD" >&2; exit 1; }
  for f in "$SESSION_DIR"/*.jsonl; do [ -f "$f" ] && TARGETS+=("$f"); done
elif [ "$DO_LATEST" -eq 1 ]; then
  [ -n "$SESSION_DIR" ] && [ -d "$SESSION_DIR" ] || {
    echo "ERROR: --latest needs a session directory for cwd: $SEARCH_CWD" >&2; exit 1; }
  newest="" newest_t=0
  for f in "$SESSION_DIR"/*.jsonl; do
    [ -f "$f" ] || continue
    t=$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null || echo 0)
    [ "$t" -gt "$newest_t" ] && { newest_t="$t"; newest="$f"; }
  done
  [ -n "$newest" ] || { echo "ERROR: no session files under $SESSION_DIR" >&2; exit 1; }
  TARGETS+=("$newest")
else
  SESSION="${SESSION:-${CLAUDE_CODE_SESSION_ID:-${CLAUDE_SESSION_ID:-}}}"
  if [ -z "$SESSION" ]; then
    echo "ERROR: no session id. Pass --session <id>, or --latest / --all, or run" >&2
    echo "       inside Claude Code where \$CLAUDE_CODE_SESSION_ID is set." >&2
    echo "       Use --list to see what is available for this cwd." >&2
    exit 1
  fi
  f="$(jsonl_for_session "$SESSION" || true)"
  [ -n "$f" ] || { echo "ERROR: no session JSONL for id '$SESSION' under $SESSIONS_ROOT" >&2; exit 1; }
  TARGETS+=("$f")
fi

[ "${#TARGETS[@]}" -gt 0 ] || { echo "ERROR: no session files resolved" >&2; exit 1; }

# ── SAFETY GATE ─────────────────────────────────────────────────────────────
# Walk upward from the search cwd (and the project arg) for the sidecar, the
# same discovery rule pretooluse-data-guard.sh uses — a tool call issued from a
# subdirectory must not escape its project's sidecar.
find_sidecar() {
  local dir="$1" i=0
  dir="$(cd "$dir" 2>/dev/null && pwd || printf '%s' "$dir")"
  while [ -n "$dir" ] && [ "$dir" != "/" ] && [ "$i" -lt 12 ]; do
    [ -f "${dir}/.claude/safety-status.json" ] && { printf '%s\n' "${dir}/.claude/safety-status.json"; return 0; }
    dir="$(dirname "$dir")"; i=$((i + 1))
  done
  return 1
}

SIDECAR="$(find_sidecar "$PROJ" 2>/dev/null || find_sidecar "$SEARCH_CWD" 2>/dev/null || true)"

SAFETY_VERDICT="NO_SIDECAR"
NON_CLEARED=""
if [ -n "$SIDECAR" ] && [ -f "$SIDECAR" ] && command -v python3 >/dev/null 2>&1; then
  NON_CLEARED="$(python3 - "$SIDECAR" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    print("__UNPARSEABLE__")
    sys.exit(0)
if not isinstance(d, dict):
    print("__UNPARSEABLE__")
    sys.exit(0)
bad = []
for k, v in d.items():
    if k == "_meta":
        continue
    if str(v).strip().upper() != "CLEARED":
        bad.append(f"{k}={v}")
for b in bad:
    print(b)
PY
)"
  if [ "$NON_CLEARED" = "__UNPARSEABLE__" ]; then
    SAFETY_VERDICT="UNPARSEABLE"
  elif [ -z "$NON_CLEARED" ]; then
    SAFETY_VERDICT="ALL_CLEARED"
  else
    SAFETY_VERDICT="NON_CLEARED"
  fi
fi

echo "SAFETY_SIDECAR=${SIDECAR:-<none>}"
echo "SAFETY_VERDICT=$SAFETY_VERDICT"

# --gist: fail closed. Only an all-CLEARED sidecar unlocks publication.
if [ "$DO_GIST" -eq 1 ] && [ "$SAFETY_VERDICT" != "ALL_CLEARED" ]; then
  cat >&2 <<GISTBLOCK

REFUSED: --gist blocked by the data-safety gate.

  Sidecar : ${SIDECAR:-<none found>}
  Verdict : $SAFETY_VERDICT

A gist is a public, third-party, search-indexed publication, and a session
transcript records tool RESULTS verbatim — including the stdout of every
LOCAL_MODE analysis heredoc. Publishing it would route around
pretooluse-data-guard.sh entirely.

--gist requires EVERY entry in .claude/safety-status.json to read CLEARED.
"missing sidecar" and "unparseable sidecar" are NOT CLEARED (fail closed).
There is no override flag for this; --force does not unlock it. Render
locally instead (drop --gist), or resolve the sidecar via /scholar-init review.
GISTBLOCK
  exit 3
fi

# Non-CLEARED local render: warn loudly, then proceed (policy: warn-and-proceed).
if [ "$SAFETY_VERDICT" = "NON_CLEARED" ] || [ "$SAFETY_VERDICT" = "UNPARSEABLE" ]; then
  {
    echo ""
    echo "WARN: rendering a session transcript for a project with restricted data."
    echo "      The HTML may contain values from these entries verbatim:"
    if [ "$SAFETY_VERDICT" = "UNPARSEABLE" ]; then
      echo "        - <sidecar present but unparseable: treat as restricted>"
    else
      printf '%s\n' "$NON_CLEARED" | sed 's/^/        - /'
    fi
    echo "      Local render proceeds (the JSONL is already on this disk)."
    echo "      Do NOT share the output directory. --gist is blocked."
    [ "$DO_FORCE" -eq 1 ] && echo "      (--force: warning acknowledged)"
    echo ""
  } >&2
elif [ "$SAFETY_VERDICT" = "NO_SIDECAR" ]; then
  echo "NOTE: no .claude/safety-status.json found — treating as un-scanned. Local render proceeds; --gist blocked." >&2
fi

# ── --dry-run: the gate has ruled; report and stop before touching anything ──
if [ "$DO_DRY" -eq 1 ]; then
  echo "DRY_RUN=1"
  [ "$DO_GIST" -eq 1 ] && echo "GIST=allowed" || echo "GIST=not-requested"
  _dest_root="${OUT_DIR:-${PROJ}/logs/transcript-html}"
  for f in "${TARGETS[@]}"; do
    echo "WOULD_RENDER=${_dest_root}/$(basename "$f" .jsonl)/index.html"
  done
  echo "SESSIONS_RENDERED=0"
  exit 0
fi

# ── Renderer availability ───────────────────────────────────────────────────
RENDER_CMD=""
if command -v claude-code-transcripts >/dev/null 2>&1; then
  RENDER_CMD="claude-code-transcripts"
elif command -v uvx >/dev/null 2>&1; then
  RENDER_CMD="uvx claude-code-transcripts"
else
  cat >&2 <<'NOTOOL'
ERROR: neither `claude-code-transcripts` nor `uvx` is on PATH.

Install one of:
  uv tool install claude-code-transcripts     # persistent
  brew install uv                             # then `uvx` runs it on demand
NOTOOL
  exit 2
fi
echo "RENDERER=$RENDER_CMD"

# ── Output dir ──────────────────────────────────────────────────────────────
OUT_DIR="${OUT_DIR:-${PROJ}/logs/transcript-html}"
mkdir -p "$OUT_DIR" || { echo "ERROR: cannot mkdir $OUT_DIR" >&2; exit 4; }

# Self-ignoring: a rendered transcript must never be committed by `git add -A`,
# wherever OUTPUT_ROOT happens to live.
if [ ! -f "${OUT_DIR}/.gitignore" ]; then
  cat > "${OUT_DIR}/.gitignore" <<'GI'
# Rendered raw session transcripts — never commit.
# These reproduce tool RESULTS verbatim (see render-session-transcript.sh
# SAFETY CONTRACT). Self-ignoring so the rule holds under any OUTPUT_ROOT.
*
!.gitignore
GI
fi

# ── Render ──────────────────────────────────────────────────────────────────
RC=0
for f in "${TARGETS[@]}"; do
  sid="$(basename "$f" .jsonl)"
  dest="${OUT_DIR}/${sid}"
  mkdir -p "$dest" || { echo "ERROR: cannot mkdir $dest" >&2; RC=4; continue; }

  args=(json "$f" -o "$dest")
  [ "$DO_GIST" -eq 1 ] && args+=(--gist)
  [ "$DO_OPEN" -eq 1 ] && args+=(--open)

  if $RENDER_CMD "${args[@]}"; then
    if [ -f "${dest}/index.html" ]; then
      echo "TRANSCRIPT_HTML=${dest}/index.html"
      echo "SESSION_ID=${sid}"
    else
      echo "ERROR: renderer reported success but ${dest}/index.html is absent" >&2
      RC=4
    fi
  else
    echo "ERROR: renderer failed for $f" >&2
    RC=4
  fi
done

echo "SESSIONS_RENDERED=${#TARGETS[@]}"
exit $RC
