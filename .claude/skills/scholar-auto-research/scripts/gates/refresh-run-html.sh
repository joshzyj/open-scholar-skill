#!/usr/bin/env bash
# refresh-run-html.sh — fail-safe re-render of a project's run view.
#
# Called at phase boundaries so <proj>/logs/run-html/index.html tracks a run as
# it happens. This is INSTRUMENTATION hanging off gate-critical code paths, so
# it is built to be invisible:
#
#   1. ALWAYS exits 0. A broken or missing visualizer must never turn a passing
#      phase into a failing one. Every internal failure is swallowed.
#   2. Writes NOTHING to stdout. pipeline-state.sh's stdout is parsed by the
#      orchestrators; one stray line here would corrupt a state read. Diagnostics
#      go to stderr, and only when something actually went wrong.
#   3. Debounced. Phase transitions can fire several state writes in a row;
#      re-rendering on each is wasted work. Skips if the page was rendered
#      within SCHOLAR_RUN_HTML_DEBOUNCE seconds (default 3).
#   4. Opt-out via SCHOLAR_RUN_HTML_AUTO=0.
#
# A full render of the largest project on hand (30 phases, 83 artifacts) takes
# ~80 ms, so this runs synchronously — backgrounding would buy nothing and would
# introduce races between concurrent renders.
#
# USAGE
#   bash refresh-run-html.sh <project_dir> [--force] [--verbose]
#
# ENVIRONMENT
#   SCHOLAR_RUN_HTML_AUTO=0        disable entirely (default: enabled)
#   SCHOLAR_RUN_HTML_DEBOUNCE=<s>  min seconds between renders (default 3)
#   SCHOLAR_RUN_HTML_REFRESH=<s>   embed a <meta refresh> of N seconds so an
#                                  open browser tab updates itself (default 0/off)
#
# EXIT CODE
#   0, unconditionally. By design.

PROJ="" FORCE=0 VERBOSE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --force)   FORCE=1; shift ;;
    --verbose) VERBOSE=1; shift ;;
    -h|--help) grep -E '^#' "$0" | sed 's/^# *//;s/^#$//'; exit 0 ;;
    *)         [ -z "$PROJ" ] && PROJ="$1"; shift ;;
  esac
done

_note() { [ "$VERBOSE" -eq 1 ] && printf 'refresh-run-html: %s\n' "$1" >&2; return 0; }
_warn() { printf 'refresh-run-html: WARN %s\n' "$1" >&2; return 0; }

# Everything below is best-effort. The trailing `exit 0` is load-bearing.
{
  [ "${SCHOLAR_RUN_HTML_AUTO:-1}" = "0" ] && { _note "disabled via SCHOLAR_RUN_HTML_AUTO=0"; exit 0; }
  [ -n "$PROJ" ] && [ -d "$PROJ" ] || { _note "no project dir"; exit 0; }
  command -v python3 >/dev/null 2>&1 || { _warn "python3 unavailable"; exit 0; }

  HERE="$(cd "$(dirname "$0")" 2>/dev/null && pwd)" || { _warn "cannot resolve helper directory"; exit 0; }
  BUILD="$HERE/build-run-model.py"
  RENDER="$HERE/render-run-html.py"
  [ -f "$BUILD" ] && [ -f "$RENDER" ] || { _warn "companion scripts missing"; exit 0; }

  OUT="$PROJ/logs/run-html/index.html"

  # Debounce: skip when the page is newer than the window.
  if [ "$FORCE" -eq 0 ] && [ -f "$OUT" ]; then
    WIN="${SCHOLAR_RUN_HTML_DEBOUNCE:-3}"
    NOW=$(date +%s 2>/dev/null || echo 0)
    MT=$(stat -f %m "$OUT" 2>/dev/null || stat -c %Y "$OUT" 2>/dev/null || echo 0)
    if [ "$NOW" -gt 0 ] && [ "$MT" -gt 0 ] && [ "$((NOW - MT))" -lt "$WIN" ]; then
      _note "debounced (rendered $((NOW - MT))s ago)"
      exit 0
    fi
  fi

  MODEL="$PROJ/logs/run-model.json"
  if ! python3 "$BUILD" "$PROJ" -o "$MODEL" >/dev/null 2>&1; then
    # exit 2 = no recognizable run state; that is normal for a non-scholar dir
    # and is not worth a warning on every call.
    _warn "no run state to model (or model build failed)"
    exit 0
  fi

  RARGS=("$MODEL" -o "$OUT")
  # Sticky auto-refresh (2026-08-25, user report "the visualizer cannot
  # auto refresh"): SCHOLAR_RUN_HTML_REFRESH lives only in the shell block
  # that exported it, and pipeline-state events re-render from FRESH blocks
  # (shell state does not persist — CLAUDE.md rule 2) — so every event
  # render silently STRIPPED the meta-refresh from a live-following tab, at
  # exactly the moment the tab should follow. Reproduced: env-set render
  # embeds the tag, the next env-less render removes it. When the env is
  # unset, inherit the interval already embedded in the page; an explicit
  # SCHOLAR_RUN_HTML_REFRESH=0 still disables (and, once rendered without
  # the tag, later env-less renders stay off — 0 is not inherited because
  # the tag it would inherit from is gone).
  # Project-scoped persistence (handoff 2026-08-25 P11-A): "a live-run view
  # whose live mode can only be switched on by an environment variable that
  # the caller never sets is not a live-run view by default." Any env-set
  # render PERSISTS the choice to <proj>/.claude/run-html.json (0 persists
  # the OFF choice); env-less renders read it back. Priority: explicit env >
  # project config > interval already embedded in the page (the sticky
  # fallback for pre-config pages).
  _REFRESH="${SCHOLAR_RUN_HTML_REFRESH:-}"
  _CFG="$PROJ/.claude/run-html.json"
  case "$_REFRESH" in
    ''|*[!0-9]*) _REFRESH="" ;;   # non-numeric env is ignored, never persisted
    *)
      mkdir -p "$PROJ/.claude" 2>/dev/null || true
      printf '{"refresh": %s}\n' "$_REFRESH" > "$_CFG" 2>/dev/null || true ;;
  esac
  if [ -z "$_REFRESH" ] && [ -f "$_CFG" ]; then
    _REFRESH="$(grep -m1 -oE '"refresh"[[:space:]]*:[[:space:]]*[0-9]+' "$_CFG" 2>/dev/null | grep -oE '[0-9]+$' || true)"
  fi
  if [ -z "$_REFRESH" ] && [ -f "$OUT" ]; then
    _REFRESH="$(grep -m1 -oE "http-equiv=['\"]refresh['\"] content=['\"][0-9]+" "$OUT" 2>/dev/null | grep -oE '[0-9]+$' || true)"
  fi
  [ -n "$_REFRESH" ] && [ "$_REFRESH" != "0" ] \
    && RARGS+=(--auto-refresh "$_REFRESH")
  if python3 "$RENDER" "${RARGS[@]}" >/dev/null 2>&1; then
    _note "rendered $OUT"
  else
    printf 'refresh-run-html: WARN render failed for %s (run view may be stale)\n' "$PROJ" >&2
  fi
} || true

exit 0
