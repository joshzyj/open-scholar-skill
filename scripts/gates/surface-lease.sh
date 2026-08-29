#!/usr/bin/env bash
# surface-lease.sh — one-writer leases per file, verified by CONTENT (RCA
# Round 1 #5, 2026-08-22).
#
# WHY: eight cohab-divorce-e2e findings trace to moving surfaces and nothing
# else — the orchestrator edited a file on its own do-not-touch list mid-round
# and the agent's incident report blamed a phantom concurrent agent (F-95); the
# measuring instrument changed while a round was being scored by it, so the
# headline number spanned two definitions of the measurement (F-85); two fix
# agents ran concurrently on the same files because a queued message revived a
# stopped one (F-65). Prose do-not-touch lists are advisory, and so is chmod:
# a pin must be verified by content at start, never trusted by permission
# (DC-07). The lease ledger is that content verification, and it binds the
# ORCHESTRATOR exactly as it binds agents.
#
# LEDGER: ${PROJ}/logs/surface-leases.ndjson — append-only events:
#   {"event":"acquire","path":...,"holder":...,"round":...,"ts":...,"sha256":...}
#   {"event":"write",  "path":...,"holder":...,"ts":...,"sha256":...,"violation":true?}
#   {"event":"release","path":...,"holder":...,"ts":...,"sha256":...}
#   {"event":"snapshot","round":...,"ts":...,"files":{path:sha,...}}
# Every write to a leased path by ANYONE lands here — a returning agent reads
# the ledger to learn what moved under it, instead of inventing phantoms.
#
# COMMANDS (all: surface-lease.sh <project_dir> <cmd> ...):
#   acquire <path> <holder> [round]   refuse if another holder has it (exit 1)
#   verify  <path> <holder>           content-check: current sha must equal the
#                                     lease's expected sha (acquire, updated by
#                                     authorized writes). Run at agent START and
#                                     at RETURN. Mismatch -> exit 1.
#   write   <path> <holder>           record an authorized write (holder only).
#                                     A non-holder write — the orchestrator
#                                     included — is recorded WITH violation:true
#                                     and exits 1: logged loudly, never quietly.
#   release <path> <holder>           end the lease (records final sha).
#   snapshot <round> <file>...        freeze instrument SHAs (gate scripts) for
#                                     a round.
#   verify-snapshot <round>           exit 1 if any snapshotted instrument
#                                     changed — the round's numbers then span
#                                     two definitions of the measurement and
#                                     MUST be decomposed under both (F-85).
#   check [--emit-json]               audit: unresolved violations, silent
#                                     mutations of active leases. For
#                                     phase-verify. INERT (3) if no ledger.
#                                     --emit-json prints the SAME computations
#                                     as pure JSON on stdout (prose suppressed)
#                                     for the run visualizer; rc is unchanged.
#                                     Read-only in both modes.
#
# --emit-json shape (surface-lease-check/v1):
#   {"gate":"surface-lease-check","verdict":"GREEN|YELLOW|RED|INERT","rc":N,
#    "stale_hours_threshold":N,"violations":N|null,"silent_mutations":N|null,
#    "snapshot_drift":N|null,"zombie_leases":N|null,
#    "paths":[{"path":..,"holder":..,"last_activity_ts":..|null,
#              "age_hours":N|null,"classifications":[..],"basis":".."}]}
#   classifications is an ARRAY (empty = active): silent mutation and staleness
#   are evaluated INDEPENDENTLY, so one path can carry both. basis records how
#   age was established: last-activity | unparseable-ts | no-activity-ts.
#
# Exit: 0 ok | 1 refusal/violation/mismatch | 2 usage | 3 INERT (check only)
set -uo pipefail

PROJ="${1:-}"; CMD="${2:-}"
# --emit-json is parsed BEFORE the usage guard: a caller that asked for JSON must
# get JSON on every exit, including this one. Emitting nothing left a renderer
# with an empty stdout and rc 2, which also collides with the YELLOW verdict.
_LJ_EARLY=0
for _a in ${@+"$@"}; do
  case "$_a" in --emit-json) _LJ_EARLY=1 ;; esac
done
if [ -z "$PROJ" ] || [ ! -d "$PROJ" ] || [ -z "$CMD" ]; then
  if [ "$_LJ_EARLY" = "1" ]; then
    printf '{"gate":"surface-lease-check","verdict":"USAGE","rc":2,"complete":false,'
    printf '"reason":"usage: surface-lease.sh <project_dir> acquire|verify|write|release|snapshot|verify-snapshot|check [--emit-json] ...",'
    printf '"stale_hours_threshold":null,"violations":null,"silent_mutations":null,'
    printf '"snapshot_drift":null,"zombie_leases":null,"paths":[]}\n'
  fi
  echo "usage: surface-lease.sh <project_dir> acquire|verify|write|release|snapshot|verify-snapshot|check [--emit-json] ..." >&2
  exit 2
fi
shift 2
LEDGER="$PROJ/logs/surface-leases.ndjson"
# logs/ is created only by MUTATING commands — `check` is read-only and must
# not touch the project (2026-08-22 verification round).
case "$CMD" in
  acquire|write|release|snapshot) mkdir -p "$PROJ/logs" ;;
esac

_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }
_sha() {
  # shasum prefixes the digest with a backslash for filenames containing
  # backslashes/newlines (escape convention); strip it or the recorded JSON
  # value is invalid and never matches (2026-08-22 verification round).
  if [ -f "$1" ]; then
    if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}' | sed 's/^\\//'
    else sha256sum "$1" | awk '{print $1}' | sed 's/^\\//'; fi
  else echo "absent"; fi
}
_emit() { printf '%s\n' "$1" >> "$LEDGER"; }
_json_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

# A path carrying a control character cannot round-trip through a line-based
# ledger: the row stops being NDJSON, and every reader that walks it line by line
# silently loses the lease. Refuse at the WRITE side rather than record something
# no reader can honour — a dropped lease is a fail-OPEN in the one gate whose job
# is to catch unrecorded writes.
_reject_ctrl_path() {
  case "$1" in
    (*[![:print:]]*)
      echo "LEASE-REFUSED: path contains a control character (tab/newline/etc)." >&2
      echo "  A lease ledger is line-based; such a path cannot be recorded or re-read" >&2
      echo "  reliably, and a lease that cannot be re-read is not a lease. Rename the" >&2
      echo "  file, or lease its directory instead." >&2
      exit 2 ;;
  esac
}

# Every acquired path, UNESCAPED, one per line.
#
# The scan used to feed _active_lease from `sed 's/.*"path":"//; s/".*//'`,
# which truncates any JSON-escaped path: `he said \"hi\".md` became `he said \`
# and `back\\slash.md` kept its doubled backslash, so _active_lease (which
# escapes what it is given) could never match the row it came from. The lease was
# then skipped by BOTH the silent-mutation scan and the zombie scan, and `check`
# reported GREEN on a surface `verify` correctly REDs. _active_lease itself was
# hardened for this in an earlier round; its INPUT was not.
_ledger_paths() {
  awk '
    /"event":"acquire"/ {
      i = index($0, "\"path\":\"")
      if (i == 0) next
      s = substr($0, i + 8)
      out = ""
      n = length(s)
      for (j = 1; j <= n; j++) {
        c = substr(s, j, 1)
        if (c == "\\") {            # escape: take the next character literally
          j++
          out = out substr(s, j, 1)
        } else if (c == "\"") {     # unescaped quote ends the token
          break
        } else {
          out = out c
        }
      }
      if (out != "") print out
    }
  ' "$LEDGER" | LC_ALL=C sort -u
}

# Current lease state for a path: prints "holder<TAB>expected_sha" of the
# active lease, empty if none. Later events win (append-only replay). The
# needle is built from the JSON-ESCAPED path and passed via ENVIRON — `-v`
# reinterprets backslash escapes, so a path containing `"` or `\` would
# otherwise never match its own ledger rows and the one-writer invariant
# silently vanished for it (2026-08-22 verification round).
_active_lease() {
  local path="$1"
  [ -f "$LEDGER" ] || return 0
  SL_NEEDLE="$(_json_escape "$path")" awk '
    BEGIN { holder = ""; sha = ""; p = ENVIRON["SL_NEEDLE"] }
    index($0, "\"path\":\"" p "\"") == 0 { next }
    /"event":"acquire"/ {
      holder = $0; sub(/.*"holder":"/, "", holder); sub(/".*/, "", holder)
      sha = $0; sub(/.*"sha256":"/, "", sha); sub(/".*/, "", sha)
      next
    }
    /"event":"write"/ && !/"violation":true/ {
      if (holder != "") { sha = $0; sub(/.*"sha256":"/, "", sha); sub(/".*/, "", sha) }
      next
    }
    /"event":"release"/ { holder = ""; sha = ""; next }
    { next }
    END { if (holder != "") printf "%s\t%s\n", holder, sha }
  ' "$LEDGER"
}

# ---- structured mirror of `check` (--emit-json) -------------------------
# The prose path is untouched: in JSON mode stdout is redirected to /dev/null
# and the real stdout is kept on fd 3, so every existing echo runs unchanged
# and only the record set reaches the caller. No gate logic is duplicated —
# the records are written by the same loops that print the prose.
_LJ=0
_LJ_STORE_BROKEN=0
_lj_num() { case "${1:-}" in ''|*[!0-9]*) printf 'null' ;; *) printf '%s' "$1" ;; esac; }
# A raw control character (a TAB in a leased path, say) both breaks the JSON —
# control characters are illegal inside a JSON string — and shifts every field of
# the tab-delimited record store. Fold them to a space at the boundary, the same
# rule independent-check-requests.sh applies.
_lj_flat() { printf '%s' "${1:-}" | tr '\000-\037' ' '; }
_lj_str() { if [ -z "${1:-}" ]; then printf 'null'; else printf '"%s"' "$(_json_escape "$(_lj_flat "$1")")"; fi; }
_lj_record() {
  # path, holder, last_activity_ts, age_hours ("?" -> null), classifications
  # (comma-separated, may be empty), basis.
  # Empty fields are written as "-" placeholders: IFS=<tab> read collapses
  # RUNS of tab (tab is IFS whitespace), so a genuinely empty field would
  # shift every later field left — the same trap the seam cards hit on real
  # ses. The reader maps "-" back to empty for the two fields that may be.
  [ "$_LJ" = "1" ] || return 0
  local _r_ts="${3:--}" _r_cls="${5:--}"
  [ -n "$_r_ts" ] || _r_ts="-"
  [ -n "$_r_cls" ] || _r_cls="-"
  if ! printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$(_lj_flat "$1")" "$(_lj_flat "$2")" "$(_lj_flat "$_r_ts")" \
      "$(_lj_flat "$4")" "$(_lj_flat "$_r_cls")" "$(_lj_flat "$6")" >> "$_LJ_TMP.paths"; then
    # An unwritable record store would emit GREEN with `paths: []` beside a real
    # active lease. Refuse to ship that contradiction.
    _LJ_STORE_BROKEN=1
  fi
}
_lj_emit() {
  # $1 verdict, $2 rc — emitted to the saved stdout, then the caller exits
  [ "$_LJ" = "1" ] || return 0
  {
    _lj_complete=true
    [ "${_LJ_STORE_BROKEN:-0}" = "1" ] && _lj_complete=false
    printf '{"gate":"surface-lease-check","verdict":"%s","rc":%s,"complete":%s,' "$1" "$2" "$_lj_complete"
    printf '"stale_hours_threshold":%s,' "$(_lj_num "${_stale_h:-${SCHOLAR_LEASE_STALE_HOURS:-24}}")"
    printf '"violations":%s,' "$(_lj_num "${VIOLATIONS:-}")"
    printf '"silent_mutations":%s,' "$(_lj_num "${SILENT:-}")"
    printf '"snapshot_drift":%s,' "$(_lj_num "${SNAP_DRIFT:-}")"
    printf '"zombie_leases":%s,' "$(_lj_num "${ZOMBIES:-}")"
    # The record set covers ACTIVE leases only — the scan that produces it walks
    # currently-held leases. A consumer must not read a released path's absence
    # from `paths` as "the gate looked and found nothing".
    printf '"paths_cover":"active leases only (released leases are not assessed)",'
    printf '"paths":['
    _lj_first=1
    while IFS="$(printf '\t')" read -r _p _h _ts _age _cls _basis; do
      [ -n "$_p" ] || continue
      [ "$_ts" = "-" ] && _ts=""
      [ "$_cls" = "-" ] && _cls=""
      [ "$_lj_first" = "1" ] || printf ','
      _lj_first=0
      printf '{"path":%s,"holder":%s,"last_activity_ts":%s,"age_hours":%s,"classifications":[' \
        "$(_lj_str "$_p")" "$(_lj_str "$_h")" "$(_lj_str "$_ts")" "$(_lj_num "$_age")"
      _lj_cf=1
      _lj_rest="$_cls"
      while [ -n "$_lj_rest" ]; do
        _lj_one="${_lj_rest%%,*}"
        if [ "$_lj_one" = "$_lj_rest" ]; then _lj_rest=""; else _lj_rest="${_lj_rest#*,}"; fi
        [ -n "$_lj_one" ] || continue
        [ "$_lj_cf" = "1" ] || printf ','
        _lj_cf=0
        printf '%s' "$(_lj_str "$_lj_one")"
      done
      printf '],"basis":%s}' "$(_lj_str "$_basis")"
    done < "$_LJ_TMP.paths"
    printf ']}\n'
  } >&3
}

case "$CMD" in
  acquire)
    P="${1:-}"; H="${2:-}"; R="${3:-}"
    [ -n "$P" ] && [ -n "$H" ] || { echo "usage: acquire <path> <holder> [round]" >&2; exit 2; }
    _reject_ctrl_path "$P"
    CUR=$(_active_lease "$P")
    if [ -n "$CUR" ]; then
      CH=$(printf '%s' "$CUR" | cut -f1)
      if [ "$CH" != "$H" ]; then
        echo "LEASE-REFUSED: '$P' is held by '$CH' — one writer per surface. Wait for release or escalate."
        exit 1
      fi
      echo "LEASE-HELD: '$P' already held by '$H' (idempotent)"
      exit 0
    fi
    S=$(_sha "$PROJ/$P")
    _emit "{\"event\":\"acquire\",\"path\":\"$(_json_escape "$P")\",\"holder\":\"$(_json_escape "$H")\",\"round\":\"$(_json_escape "$R")\",\"ts\":\"$(_now)\",\"sha256\":\"$S\"}"
    echo "LEASE-ACQUIRED: $P -> $H (sha=$S)"
    ;;
  verify)
    P="${1:-}"; H="${2:-}"
    [ -n "$P" ] && [ -n "$H" ] || { echo "usage: verify <path> <holder>" >&2; exit 2; }
    _reject_ctrl_path "$P"
    CUR=$(_active_lease "$P")
    [ -n "$CUR" ] || { echo "VERIFY-FAIL: no active lease on '$P' — acquire before writing"; exit 1; }
    CH=$(printf '%s' "$CUR" | cut -f1); ES=$(printf '%s' "$CUR" | cut -f2)
    [ "$CH" = "$H" ] || { echo "VERIFY-FAIL: '$P' is held by '$CH', not '$H'"; exit 1; }
    AS=$(_sha "$PROJ/$P")
    if [ "$AS" != "$ES" ]; then
      echo "VERIFY-FAIL: '$P' moved under the lease (expected $ES, found $AS)."
      echo "  Someone wrote this surface without a ledger event. Read the ledger tail and"
      echo "  the file diff before trusting ANY conclusion drawn from the old content (DC-07)."
      exit 1
    fi
    echo "VERIFY-OK: $P (sha=$AS)"
    ;;
  write)
    P="${1:-}"; H="${2:-}"
    [ -n "$P" ] && [ -n "$H" ] || { echo "usage: write <path> <holder>" >&2; exit 2; }
    _reject_ctrl_path "$P"
    S=$(_sha "$PROJ/$P")
    CUR=$(_active_lease "$P")
    if [ -n "$CUR" ]; then
      CH=$(printf '%s' "$CUR" | cut -f1)
      if [ "$CH" != "$H" ]; then
        _emit "{\"event\":\"write\",\"path\":\"$(_json_escape "$P")\",\"holder\":\"$(_json_escape "$H")\",\"ts\":\"$(_now)\",\"sha256\":\"$S\",\"violation\":true,\"lease_holder\":\"$(_json_escape "$CH")\"}"
        echo "LEASE-VIOLATION: '$H' wrote '$P' while '$CH' holds the lease."
        echo "  The event is on the ledger; '$CH' MUST read it at return (F-95: an undisclosed"
        echo "  orchestrator write made a careful agent blame a phantom concurrent agent)."
        exit 1
      fi
    fi
    _emit "{\"event\":\"write\",\"path\":\"$(_json_escape "$P")\",\"holder\":\"$(_json_escape "$H")\",\"ts\":\"$(_now)\",\"sha256\":\"$S\"}"
    echo "WRITE-RECORDED: $P by $H (sha=$S)"
    ;;
  release)
    P="${1:-}"; H="${2:-}"
    [ -n "$P" ] && [ -n "$H" ] || { echo "usage: release <path> <holder>" >&2; exit 2; }
    _reject_ctrl_path "$P"
    CUR=$(_active_lease "$P")
    [ -n "$CUR" ] || { echo "RELEASE-NOOP: no active lease on '$P'"; exit 0; }
    CH=$(printf '%s' "$CUR" | cut -f1)
    [ "$CH" = "$H" ] || { echo "RELEASE-REFUSED: '$P' is held by '$CH', not '$H'"; exit 1; }
    _emit "{\"event\":\"release\",\"path\":\"$(_json_escape "$P")\",\"holder\":\"$(_json_escape "$H")\",\"ts\":\"$(_now)\",\"sha256\":\"$(_sha "$PROJ/$P")\"}"
    echo "LEASE-RELEASED: $P by $H"
    ;;
  snapshot)
    R="${1:-}"; shift || true
    [ -n "$R" ] && [ $# -ge 1 ] || { echo "usage: snapshot <round> <file>..." >&2; exit 2; }
    FILES=""
    for f in "$@"; do
      S=$(_sha "$f")   # instruments are usually plugin paths — absolute allowed
      FILES="${FILES}${FILES:+,}\"$(_json_escape "$f")\":\"$S\""
    done
    _emit "{\"event\":\"snapshot\",\"round\":\"$(_json_escape "$R")\",\"ts\":\"$(_now)\",\"files\":{$FILES}}"
    echo "SNAPSHOT-RECORDED: round=$R files=$#"
    ;;
  verify-snapshot)
    R="${1:-}"
    [ -n "$R" ] || { echo "usage: verify-snapshot <round>" >&2; exit 2; }
    [ -f "$LEDGER" ] || { echo "VERIFY-SNAPSHOT-FAIL: no ledger"; exit 1; }
    SNAP=$(grep '"event":"snapshot"' "$LEDGER" | grep "\"round\":\"$R\"" | tail -1 || true)
    [ -n "$SNAP" ] || { echo "VERIFY-SNAPSHOT-FAIL: no snapshot for round '$R'"; exit 1; }
    CHANGED=0
    while IFS=$'\t' read -r f s; do
      [ -n "$f" ] || continue
      NOW_S=$(_sha "$f")
      if [ "$NOW_S" != "$s" ]; then
        echo "INSTRUMENT-CHANGED: $f ($s -> $NOW_S)"
        CHANGED=$((CHANGED + 1))
      fi
    done <<EOF_SNAP
$(printf '%s\n' "$SNAP" | python3 -c 'import json,sys
rec = json.loads(sys.stdin.read())
for k, v in rec.get("files", {}).items(): print("%s\t%s" % (k, v))')
EOF_SNAP
    if [ "$CHANGED" -gt 0 ]; then
      echo "VERIFY-SNAPSHOT-FAIL: $CHANGED instrument(s) changed mid-round."
      echo "  The round's numbers span two definitions of the measurement. Report them"
      echo "  DECOMPOSED under both instruments (old-gate delta and new-gate delta),"
      echo "  never as one headline number (F-85: '77 -> 0 is not one instrument's reading')."
      exit 1
    fi
    echo "VERIFY-SNAPSHOT-OK: round=$R"
    ;;
  check)
    for _a in "$@"; do
      case "$_a" in
        --emit-json) _LJ=1 ;;
      esac
    done
    if [ "$_LJ" = "1" ]; then
      exec 3>&1 1>/dev/null
      _LJ_TMP="${TMPDIR:-/tmp}/surface-lease-json.$$"
      : > "$_LJ_TMP.paths"
      : > "$_LJ_TMP.silent"
      trap 'rm -f "$_LJ_TMP.paths" "$_LJ_TMP.silent"' EXIT
    fi
    echo "GATE=surface-lease-check"
    echo "PROJECT=$PROJ"
    if [ ! -f "$LEDGER" ]; then
      echo "STATUS=INERT"
      echo "REASON=no logs/surface-leases.ndjson — leases not adopted in this project"
      _lj_emit INERT 3
      exit 3
    fi
    VIOLATIONS=$(grep -c '"violation":true' "$LEDGER" || true)
    echo "VIOLATIONS=$VIOLATIONS"
    # Silent mutation scan: every ACTIVE lease whose file sha no longer matches
    # its expected sha (no authorized write recorded).
    SILENT=0
    while IFS= read -r p; do
      [ -n "$p" ] || continue
      CUR=$(_active_lease "$p")
      [ -n "$CUR" ] || continue
      ES=$(printf '%s' "$CUR" | cut -f2)
      AS=$(_sha "$PROJ/$p")
      if [ "$AS" != "$ES" ]; then
        echo "  RED: active lease on '$p' but content moved with no ledger event ($ES -> $AS)"
        SILENT=$((SILENT + 1))
        [ "$_LJ" = "1" ] && printf '%s\n' "$p" >> "$_LJ_TMP.silent"
      fi
    done <<EOF_PATHS
$(_ledger_paths)
EOF_PATHS
    # Newest-snapshot re-verify (real-project eval, ses 2026-08-22): the
    # F-85 moving-instrument catch used to depend entirely on the
    # orchestrator remembering to run `verify-snapshot <round>` at round end
    # — the very actor F-85 indicts. `check` (the verb phase-verify wires)
    # now re-verifies the NEWEST snapshot round itself, so instrument drift
    # is caught by the gate even when the orchestrator forgets.
    SNAP_DRIFT=0
    NEWEST_SNAP=$(grep '"event":"snapshot"' "$LEDGER" | tail -1 || true)
    if [ -n "$NEWEST_SNAP" ]; then
      NEWEST_ROUND=$(printf '%s' "$NEWEST_SNAP" | sed 's/.*"round":"//; s/".*//')
      echo "SNAPSHOT_ROUND_CHECKED=$NEWEST_ROUND"
      while IFS=$'\t' read -r f s; do
        [ -n "$f" ] || continue
        NOW_S=$(_sha "$f")
        if [ "$NOW_S" != "$s" ]; then
          echo "  RED: instrument '$f' changed since the $NEWEST_ROUND snapshot ($s -> $NOW_S) — F-85 moving instrument"
          SNAP_DRIFT=$((SNAP_DRIFT + 1))
        fi
      done <<EOF_CKSNAP
$(printf '%s\n' "$NEWEST_SNAP" | python3 -c 'import json,sys
rec = json.loads(sys.stdin.read())
for k, v in rec.get("files", {}).items(): print("%s\t%s" % (k, v))' 2>/dev/null || true)
EOF_CKSNAP
    fi
    # Zombie-lease attribution (R3, 2026-08-22; eval deferral). A lease
    # acquired and never released past a staleness window is the F-65/67/89
    # signature: an agent that stopped (or was stopped) still owns the
    # surface, so no successor can write it and a forgotten holder's name
    # keeps authorizing writes. The gate cannot see process liveness, so
    # this is YELLOW with the attribution the operator needs (holder, path,
    # age) — release explicitly (`release <path> <holder>`) after checking
    # the process table, per SKILL.md's stopped-agent protocol.
    ZOMBIES=0
    _now_epoch=$(date -u +%s 2>/dev/null || echo 0)
    _stale_h="${SCHOLAR_LEASE_STALE_HOURS:-24}"
    case "$_stale_h" in ''|*[!0-9]*) _stale_h=24 ;; esac
    while IFS= read -r p; do
      [ -n "$p" ] || continue
      CUR=$(_active_lease "$p")
      [ -n "$CUR" ] || continue
      _holder=$(printf '%s' "$CUR" | cut -f1)
      # ts of the LAST acquire event for this path (ISO-8601 UTC)
      # ts of the last ACTIVITY on this lease — acquire OR authorized write
      # (R3 verification round F16: age-from-acquire-only flagged an
      # actively-writing holder on a long round; a zombie is a lease with
      # no RECENT activity, not merely an old acquisition).
      # Only extract a ts from a row that actually HAS one: `sed 's/.*"ts":"//'`
      # on a ts-less row leaves the rest of the line (a bare `{`), which was then
      # reported as a real timestamp with basis "unparseable-ts".
      # The needle must be the JSON-ESCAPED path: `$p` is now the real path, and
      # the ledger stores it escaped. Grepping the raw form found nothing for any
      # path containing a quote or backslash, so its activity ts came back empty
      # and a fresh lease was reported ZOMBIE-AGE-UNKNOWN. (_active_lease already
      # escapes its needle for exactly this reason.)
      _pesc="$(_json_escape "$p")"
      _arow=$(grep -E '"event":"(acquire|write)"' "$LEDGER" | grep -F "\"path\":\"$_pesc\"" \
        | grep -v '"violation":true' | tail -1 || true)
      case "$_arow" in
        (*'"ts":"'*) _ats=$(printf '%s' "$_arow" | sed 's/.*"ts":"//; s/".*//') ;;
        (*)          _ats="" ;;
      esac
      _age_h="?"
      _aep=0
      if [ -n "$_ats" ] && [ "$_now_epoch" -gt 0 ]; then
        _aep=$(date -ju -f "%Y-%m-%dT%H:%M:%SZ" "$_ats" +%s 2>/dev/null \
          || date -u -d "$_ats" +%s 2>/dev/null || echo 0)
      fi
      _zcls=""
      _zbasis="last-activity"
      if [ "${_aep:-0}" -gt 0 ]; then
        _age_h=$(( (_now_epoch - _aep) / 3600 ))
        if [ "$_age_h" -ge "$_stale_h" ]; then
          echo "  ZOMBIE: '$p' held by '$_holder' for ${_age_h}h since last activity (>= ${_stale_h}h) with no release"
          ZOMBIES=$((ZOMBIES + 1))
          _zcls="zombie"
        fi
      else
        # F17: an unparseable ts must not silently EXEMPT a lease — that
        # fail-open would sit inside the gate built to catch fail-open
        # agents. Unknown age counts toward the YELLOW.
        echo "  ZOMBIE-AGE-UNKNOWN: '$p' held by '$_holder' — activity ts '$_ats' unparseable; treat as stale until released or re-verified"
        ZOMBIES=$((ZOMBIES + 1))
        _zcls="zombie-age-unknown"
        if [ -n "$_ats" ]; then _zbasis="unparseable-ts"; else _zbasis="no-activity-ts"; fi
      fi
      if [ "$_LJ" = "1" ]; then
        # silent mutation and staleness are INDEPENDENT verdicts on the same
        # path — both can hold, so the record carries a list, not one label.
        if grep -Fxq "$p" "$_LJ_TMP.silent" 2>/dev/null; then
          if [ -n "$_zcls" ]; then _zcls="silent-mutation,$_zcls"; else _zcls="silent-mutation"; fi
        fi
        _lj_record "$p" "$_holder" "$_ats" "$_age_h" "$_zcls" "$_zbasis"
      fi
    done <<EOF_ZPATHS
$(_ledger_paths)
EOF_ZPATHS
    echo "ZOMBIE_LEASES=$ZOMBIES"
    if [ "${VIOLATIONS:-0}" -gt 0 ] || [ "$SILENT" -gt 0 ] || [ "$SNAP_DRIFT" -gt 0 ]; then
      echo "STATUS=RED"
      echo "REASON=$VIOLATIONS recorded violation(s), $SILENT silent mutation(s) of leased surfaces, $SNAP_DRIFT drifted instrument(s) vs the newest snapshot (report numbers DECOMPOSED under both instruments, never one headline — F-85)"
      _lj_emit RED 1
      exit 1
    fi
    if [ "$ZOMBIES" -gt 0 ]; then
      echo "STATUS=YELLOW"
      echo "REASON=$ZOMBIES lease(s) held past ${_stale_h}h with no release — likely zombie holder(s) (F-65/67/89: a stopped agent still owns the surface). Check the process table, cancel queued SendMessages to the holder, then release each explicitly; never write through a zombie's lease"
      _lj_emit YELLOW 2
      exit 2
    fi
    echo "STATUS=GREEN"
    _lj_emit GREEN 0
    ;;
  *)
    if [ "$_LJ_EARLY" = "1" ]; then
      printf '{"gate":"surface-lease-check","verdict":"USAGE","rc":2,"complete":false,'
      printf '"reason":"unknown command",'
      printf '"stale_hours_threshold":null,"violations":null,"silent_mutations":null,'
      printf '"snapshot_drift":null,"zombie_leases":null,"paths":[]}\n'
    fi
    echo "unknown command: $CMD" >&2
    exit 2
    ;;
esac
