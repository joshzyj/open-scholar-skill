#!/usr/bin/env bash
# independent-check-requests.sh — surface every INDEPENDENT-CHECK REQUESTED block a
# Bash-less review-code-* agent has filed, so a request cannot be silently overlooked.
#
# CONTRACT (user decision, 2026-08-16 — "Bash by request and authorization"):
#   review-code-* agents that hold no `Bash` may REQUEST an independent check (a digest,
#   a pin verification, a re-derived value) but may never take one. Only a recorded user
#   authorization turns a request into an action, and the action runs under a Bash-capable
#   agent, never the requester. This gate is the mechanical half of that contract: it makes
#   the pending requests visible. Without it the protocol is prose, and prose is exactly the
#   thing that failed one layer out today (a refusal that reaches nobody is not a guard —
#   see the suite defect-class registry, DC-11 corollary).
#
# WHAT IT READS
#   ${PROJ}/reviews/phase-5.5-iter*-*.md       (per-dimension review reports)
#   ${PROJ}/reports/code-review-*-iter*.md     (same reports under the reports/ convention —
#                                               the ses-polarization-gss run filed ALL its
#                                               per-dimension reports there, 2026-08-21;
#                                               scanning reviews/ alone read nothing)
#   Each request is a block whose first line is exactly `INDEPENDENT-CHECK REQUESTED` and
#   whose subsequent `  key: value` lines carry claim / why / command / scope / status.
#
# WHAT IT ENFORCES (RED — fail closed)
#   R1  scope names a data path        -> RED. A request to touch data/, materials/, or a
#                                          .csv/.dta/.sav/.parquet/.rds/.xlsx is not
#                                          authorizable under LOCAL_MODE; refusing here
#                                          means the user is never even asked.
#   R2  status is a value not in the    -> RED. The vocabulary is closed:
#       closed vocabulary                  PENDING-USER-AUTHORIZATION | AUTHORIZED-AND-RUN |
#                                          DECLINED. An unknown status is unreadable, and an
#                                          unreadable status must not pass (DC-11).
#   R3  block missing command: or scope: -> RED. Nothing can be authorized that is not stated
#                                          exactly; drift between filed and executed voids the
#                                          authorization, so the filed form must exist.
#
# WHAT IT REPORTS (YELLOW — advisory, needs a human)
#   Y1  >=1 request PENDING-USER-AUTHORIZATION -> YELLOW, and each is printed verbatim so
#       the orchestrator can surface it. The orchestrator MUST NOT resolve it.
#
# GREEN   no requests, or every request is AUTHORIZED-AND-RUN / DECLINED.
# INERT   no phase-5.5 review reports found (nothing to read).
#
# Exit: 0 GREEN | 1 RED | 2 YELLOW | 3 INERT
# Usage: independent-check-requests.sh <project_dir> [--emit-json]
#
# --emit-json (run visualizer, 2026-08-23). The parser builds ONE RECORD PER
# REQUEST as it goes (id_tag, source, line, status, form, valid, red_reasons);
# the default mode then renders the legacy prose from those records exactly as
# before (byte-identical — pinned by this gate's smoke suite), and --emit-json
# renders pure JSON instead, with ALL legacy stdout suppressed. A consumer must
# never re-derive request validity by parsing prose, and an invalid request must
# never reach a consumer as an ordinary pending one, so `valid:false` +
# `red_reasons[]` travel with the record.
#
# The default scan is UNBOUNDED by design (three globs, every file read in
# full). --emit-json is called by a renderer, so it adds explicit bounds and
# REPORTS THEM: newest-N file cap, per-file byte cap, wall-clock budget. A
# truncated scan says so in `bounds` rather than presenting a partial count as
# complete.
#
# --emit-json shape (independent-check-requests/v1):
#   {"gate":..,"verdict":"GREEN|YELLOW|RED|INERT","rc":N,"reason":..,
#    "reports_scanned":N,"safety_registry":..|null,
#    "counts":{"total":N,"pending":N,"run":N,"declined":N,"withdrawn":N,
#              "red":N,"closed_violations":N,"unparseable_headings":N},
#    "bounds":{..},"requests":[{..}],"unparseable_heading_lines":[..]}
set -uo pipefail

PROJ="${1:-}"

# ---- structured mode plumbing (must precede any output) --------------------
ICR_JSON=0
for _a in ${@+"$@"}; do
  case "$_a" in --emit-json) ICR_JSON=1 ;; esac
done
ICR_FILE_CAP="${SCHOLAR_ICR_FILE_CAP:-200}"
ICR_BYTE_CAP="${SCHOLAR_ICR_BYTE_CAP:-1048576}"
ICR_BUDGET_S="${SCHOLAR_ICR_BUDGET_S:-20}"
case "$ICR_FILE_CAP" in ''|*[!0-9]*) ICR_FILE_CAP=200 ;; esac
case "$ICR_BYTE_CAP" in ''|*[!0-9]*) ICR_BYTE_CAP=1048576 ;; esac
case "$ICR_BUDGET_S" in ''|*[!0-9]*) ICR_BUDGET_S=20 ;; esac
_icr_files_considered=0; _icr_files_truncated=false
_icr_files_oversize=0; _icr_files_unscanned=0; _icr_budget_exhausted=false
_icr_files_unreadable=0; _icr_scanned=0
_ICR_COUNTED=0; _ICR_SCANNED_CORPUS=0; _ICR_STORE_BROKEN=0; _ICR_EMIT_RC=""
_icr_start_epoch="$(date -u +%s 2>/dev/null || echo 0)"
_ICR_REASON=""
if [ "$ICR_JSON" = "1" ]; then
  exec 3>&1 1>/dev/null
  ICR_TMP="${TMPDIR:-/tmp}/icr-json.$$"
  : > "$ICR_TMP.records"
  : > "$ICR_TMP.headings"
  trap 'rm -f "$ICR_TMP.records" "$ICR_TMP.headings"' EXIT
fi
_icr_str() { if [ -z "${1:-}" ]; then printf 'null'; else printf '"%s"' "$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\000-\037')"; fi; }
# The record store is tab-delimited, so a TAB (or CR/LF) inside a captured field
# would shift every later field left and land a fragment where a JSON literal is
# expected — the reviewer annotation `status: PENDING…<TAB>(re-filed)` did
# exactly that, emitting `"valid":block`. Control characters are folded to a
# space at WRITE time, matching what _icr_str already strips at emit time.
_icr_flat() { printf '%s' "${1:-}" | tr '\000-\037' ' '; }
_icr_num() { case "${1:-}" in ''|*[!0-9]*) printf 'null' ;; *) printf '%s' "$1" ;; esac; }
# One record per parsed request. Empty fields travel as "-" placeholders:
# IFS=<tab> read collapses runs of tab, so a genuinely empty field would shift
# every later field left.
_icr_record() {
  [ "$ICR_JSON" = "1" ] || return 0
  if ! printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$(_icr_flat "${1:--}")" "$(_icr_flat "${2:--}")" "$(_icr_flat "${3:--}")" \
    "$(_icr_flat "${4:--}")" "$(_icr_flat "${5:--}")" "$(_icr_flat "${6:--}")" \
    "$(_icr_flat "${7:--}")" >> "$ICR_TMP.records"; then
    # A record store we cannot write to would silently produce `requests: []`
    # beside non-zero counts. Fail loudly instead of shipping a contradiction.
    _ICR_STORE_BROKEN=1
  fi
}
_icr_emit() {
  # $1 verdict, $2 rc
  [ "$ICR_JSON" = "1" ] || return 0
  # A BOUNDED SCAN MUST NOT REPORT A CLEAN VERDICT. The caps exist so a renderer
  # cannot hang, but a run that skipped files has not established that nothing is
  # wrong in them: emitting GREEN (or INERT — "nothing to read") with a reason
  # like "no requests filed across N reports" states a fact the scan never
  # checked. Truncation therefore floors the verdict at YELLOW and says why, and
  # `complete` records whether the scan covered its whole corpus.
  #
  # This is the ONE place --emit-json deliberately departs from prose rc parity:
  # prose has no caps, so it always scans everything. Parity holds whenever
  # complete=true.
  _icr_complete=true
  _icr_trunc=""
  [ "$_icr_files_truncated" = "true" ] && { _icr_complete=false; _icr_trunc="${_icr_trunc}file cap reached; "; }
  [ "$_icr_budget_exhausted" = "true" ] && { _icr_complete=false; _icr_trunc="${_icr_trunc}wall-clock budget exhausted; "; }
  [ "${_icr_files_oversize:-0}" -gt 0 ] && { _icr_complete=false; _icr_trunc="${_icr_trunc}${_icr_files_oversize} file(s) over the byte cap; "; }
  [ "${_icr_files_unreadable:-0}" -gt 0 ] && { _icr_complete=false; _icr_trunc="${_icr_trunc}${_icr_files_unreadable} file(s) unreadable; "; }
  [ "${_ICR_STORE_BROKEN:-0}" = "1" ] && { _icr_complete=false; _icr_trunc="${_icr_trunc}record store unwritable; "; }
  local _v="$1" _rc="$2"
  if [ "$_icr_complete" = "false" ]; then
    case "$_v" in
      GREEN|INERT)
        _v="YELLOW"; _rc=2
        _ICR_REASON="scan INCOMPLETE (${_icr_trunc%; }) — the requests in the unread file(s) were never examined, so no clean verdict can be given for this project"
        ;;
      *)
        _ICR_REASON="$_ICR_REASON [scan INCOMPLETE: ${_icr_trunc%; }]"
        ;;
    esac
  fi
  {
    printf '{"gate":"independent-check-requests","verdict":"%s","rc":%s,' "$_v" "$_rc"
    printf '"complete":%s,' "$_icr_complete"
    printf '"reason":%s,' "$(_icr_str "$_ICR_REASON")"
    # Files actually READ. ${#REPORTS[@]} is the post-bounds SELECTION, which
    # under budget exhaustion can be 12 while zero files were opened.
    printf '"reports_scanned":%s,' "$(_icr_num "${_icr_scanned:-0}")"
    printf '"reports_selected":%s,' "$(_icr_num "${#REPORTS[@]}")"
    printf '"safety_registry":%s,' "$(_icr_str "${SAFETY_REGISTRY:-}")"
    # Counters are NULL until the parse has actually run: on the INERT and
    # usage-error paths nothing was counted, and a 0 there would assert a
    # computation that never happened (the rule surface-lease.sh already keeps).
    if [ "${_ICR_COUNTED:-0}" = "1" ]; then
      printf '"counts":{"total":%s,"pending":%s,"run":%s,"declined":%s,"withdrawn":%s,"red":%s,"closed_violations":%s,"unparseable_headings":%s},' \
        "$(_icr_num "${n_total:-0}")" "$(_icr_num "${n_pending:-0}")" "$(_icr_num "${n_run:-0}")" \
        "$(_icr_num "${n_declined:-0}")" "$(_icr_num "${n_withdrawn:-0}")" \
        "$(_icr_num "${#RED_LINES[@]}")" "$(_icr_num "${#CLOSED_LINES[@]}")" \
        "$(_icr_num "${#HEADING_REQS[@]}")"
    else
      printf '"counts":{"total":null,"pending":null,"run":null,"declined":null,"withdrawn":null,"red":null,"closed_violations":null,"unparseable_headings":null},'
    fi
    # `bounds` describes a scan. On the usage-error path no scan was attempted,
    # so an all-zero bounds block would describe one that never happened.
    if [ "${_ICR_SCANNED_CORPUS:-0}" = "1" ]; then
      printf '"bounds":{"file_cap":%s,"files_considered":%s,"files_scanned":%s,"files_truncated":%s,"byte_cap":%s,"files_skipped_oversize":%s,"files_unreadable":%s,"wall_clock_budget_s":%s,"budget_exhausted":%s,"files_unscanned":%s},' \
        "$ICR_FILE_CAP" "$_icr_files_considered" "$(_icr_num "${_icr_scanned:-0}")" "$_icr_files_truncated" "$ICR_BYTE_CAP" \
        "$_icr_files_oversize" "${_icr_files_unreadable:-0}" "$ICR_BUDGET_S" "$_icr_budget_exhausted" "$_icr_files_unscanned"
    else
      printf '"bounds":null,'
    fi
    printf '"requests":['
    _rf=1
    while IFS="$(printf '\t')" read -r _tag _src _line _st _form _valid _reasons; do
      [ -n "$_tag" ] || continue
      [ "$_rf" = "1" ] || printf ','
      _rf=0
      [ "$_st" = "-" ] && _st=""
      case "$_valid" in
        true|false) : ;;
        *) _valid=false ;;   # never interpolate an unvalidated field as a JSON literal
      esac
      printf '{"id_tag":%s,"source":%s,"line":%s,"status":%s,"form":%s,"valid":%s,"red_reasons":[' \
        "$(_icr_str "$_tag")" "$(_icr_str "$_src")" "$(_icr_num "$_line")" \
        "$(_icr_str "$_st")" "$(_icr_str "$_form")" "$_valid"
      if [ "$_reasons" != "-" ]; then
        _cf=1; _rest="$_reasons"
        while [ -n "$_rest" ]; do
          case "$_rest" in
            (*'|||'*) _one="${_rest%%|||*}"; _rest="${_rest#*|||}" ;;
            (*)       _one="$_rest"; _rest="" ;;
          esac
          [ -n "$_one" ] || continue
          [ "$_cf" = "1" ] || printf ','
          _cf=0
          printf '%s' "$(_icr_str "$_one")"
        done
      fi
      printf ']}'
    done < "$ICR_TMP.records"
    printf '],"unparseable_heading_lines":['
    _hf=1
    while IFS= read -r _hline; do
      [ -n "$_hline" ] || continue
      [ "$_hf" = "1" ] || printf ','
      _hf=0
      printf '%s' "$(_icr_str "$_hline")"
    done < "$ICR_TMP.headings"
    printf ']}\n'
  } >&3
  _ICR_EMIT_RC="$_rc"
}

if [ -z "$PROJ" ] || [ ! -d "$PROJ" ]; then
  echo "GATE=independent-check-requests"
  echo "STATUS=RED"
  _ICR_REASON="usage: independent-check-requests.sh <project_dir> (got '${PROJ}')"
  echo "REASON=$_ICR_REASON"
  declare -a REPORTS=(); declare -a RED_LINES=(); declare -a CLOSED_LINES=(); declare -a HEADING_REQS=()
  [ "$ICR_JSON" = "1" ] && { : > "$ICR_TMP.records"; : > "$ICR_TMP.headings"; }
  _icr_emit RED 1
  exit "${_ICR_EMIT_RC:-1}"
fi

echo "GATE=independent-check-requests"
echo "PROJECT=$PROJ"

# Every array initialised with =(): under set -u, bash >= 4.4 treats a bare-declared array
# as unbound for ${#ARR[@]} too; initialize every array explicitly.
declare -a REPORTS=()
declare -a PENDING=()
declare -a RED_LINES=()
# CLOSED_LINES / HEADING_REQS are populated much further down, but --emit-json
# can exit before then (INERT); declared here so the record emitter can always
# report a count instead of tripping set -u.
declare -a CLOSED_LINES=()
declare -a HEADING_REQS=()

# peer-review/agents/*.md added 2026-08-22 (real-project eval, ses): the 3.5
# iter-4 reviewer filed ICR-Q4-* requests there and the gate never scanned the
# directory — requests invisible to the one gate built to surface them.
# phase-5A.5-iter* added 2026-08-25 (handoff P1-B): seven live PENDING
# requests filed from pre-execution reviews were invisible to the one gate
# built to surface them (REPORTS_SCANNED=0 against a project with three
# completed rounds).
for f in "$PROJ"/reviews/phase-5.5-iter*-*.md "$PROJ"/reviews/phase-5A.5-iter*-*.md "$PROJ"/reports/code-review-*-iter*.md "$PROJ"/peer-review/agents/*.md; do
  [ -f "$f" ] || continue
  case "$f" in *.trace.ndjson) continue ;; esac
  REPORTS+=("$f")
done

# --emit-json is called by a RENDERER, so the scan is bounded there (and only
# there — the gate's own phase-verify path must keep reading everything). The
# bounds are reported, never silent: a truncated scan that printed a plain
# count would read as a complete one.
_ICR_SCANNED_CORPUS=1
if [ "$ICR_JSON" = "1" ] && [ "${#REPORTS[@]}" -gt 0 ]; then
  _icr_files_considered=${#REPORTS[@]}
  declare -a _BOUNDED=()
  while IFS= read -r _bf; do
    [ -n "$_bf" ] || continue
    _sz=$(wc -c < "$_bf" 2>/dev/null | tr -d ' ')
    case "$_sz" in ''|*[!0-9]*) _sz=0 ;; esac
    if [ "$_sz" -gt "$ICR_BYTE_CAP" ]; then
      _icr_files_oversize=$((_icr_files_oversize + 1)); continue
    fi
    if [ "${#_BOUNDED[@]}" -ge "$ICR_FILE_CAP" ]; then
      _icr_files_truncated=true; continue
    fi
    _BOUNDED+=("$_bf")
  done <<EOF_ICR_BOUND
$(for _x in "${REPORTS[@]}"; do
    printf '%s\t%s\n' "$(stat -f %m "$_x" 2>/dev/null || stat -c %Y "$_x" 2>/dev/null || echo 0)" "$_x"
  done | sort -rn | cut -f2-)
EOF_ICR_BOUND
  REPORTS=(${_BOUNDED[@]+"${_BOUNDED[@]}"})
fi

if [ "${#REPORTS[@]}" -eq 0 ]; then
  echo "REPORTS_SCANNED=0"
  echo "STATUS=INERT"
  _ICR_REASON="no review reports under $PROJ/reviews/, $PROJ/reports/, or $PROJ/peer-review/agents/ — nothing to read"
  echo "REASON=$_ICR_REASON"
  _icr_emit INERT 3
  exit "${_ICR_EMIT_RC:-3}"
fi
echo "REPORTS_SCANNED=${#REPORTS[@]}"

## The registry may live at the project OR at a workshop root above it. The live project that surfaced F-74
## has no `.claude/` directory of its own and is governed entirely by an ancestor's registry, so a
## project-only lookup would find nothing and then refuse everything for "no registry" on a fully registered
## project. Walk upward; the nearest one wins.
SAFETY_REGISTRY=""
_d="$PROJ"
for _ in 1 2 3 4 5 6 7 8; do
  [ -f "$_d/.claude/safety-status.json" ] && { SAFETY_REGISTRY="$_d/.claude/safety-status.json"; break; }
  _p="$(dirname "$_d")"; [ "$_p" = "$_d" ] && break; _d="$_p"
done
echo "SAFETY_REGISTRY=${SAFETY_REGISTRY:-<none found>}"

## R1 IS NOW REGISTRY-AWARE (2026-08-19, F-74). The single pattern below used to flag ANY `.csv` anywhere,
## with no reference to directory, provenance, or the safety registry the LOCAL_MODE policy is actually built
## on. Measured on a live project: 20 of 20 request blocks RED, and six of the seven artifacts refused in the
## first one were registered **CLEARED** in `.claude/safety-status.json`. A rule that refuses ~100% of
## legitimate requests does not protect data — it disables the mechanism that lets a reviewer WITHOUT a Bash
## tool ask for a check instead of asserting something unverified, which pushes reviewers toward exactly the
## unverified claims this contract exists to prevent.
##
## The split: HARD tokens are refused unconditionally and are not negotiable by any registry. SOFT tokens
## (tabular interchange formats, which are equally the extension of an aggregate results table) are refused
## UNLESS every one of them resolves to a CLEARED entry. Unregistered is NOT cleared, and an unreadable or
## missing registry refuses everything — absence of evidence never becomes permission.
DATA_HARD_RE='(^|[^A-Za-z0-9_])(data|materials)(/|$)|\.(dta|sav|parquet|feather|rds|rdata|h5|pkl)\b'
DATA_SOFT_RE='\.(csv|tsv|xlsx|xls)\b'

## Emits: CLEARED  |  NOT-CLEARED <detail>  |  NO-REGISTRY <detail>
soft_tokens_cleared() {
  SAFETY_REGISTRY="$SAFETY_REGISTRY" PROJ="$PROJ" python3 - "$1" <<'PY_ICR'
import json, os, re, sys
text = sys.argv[1]
reg = os.environ.get("SAFETY_REGISTRY", "")
# A token immediately followed by "(" is a FUNCTION CALL (read.csv(...),
# write.csv(...)), not a file path — flagging the function name refused the
# very command whose real argument paths are checked anyway (2026-08-22
# verification round: `read.csv` alone REDed a compliant request).
toks = [m.group(0) for m in re.finditer(r'[A-Za-z0-9_./\\-]+\.(?:csv|tsv|xlsx|xls)\b', text)
        if not (m.end() < len(text) and text[m.end()] == '(')]
if not toks:
    print("CLEARED"); sys.exit(0)
if not reg or not os.path.isfile(reg):
    print("NO-REGISTRY no safety-status.json found from the project upward; "
          "cannot establish clearance for: " + ", ".join(sorted(set(toks)))); sys.exit(0)
try:
    with open(reg, "r", encoding="utf-8") as fh:
        d = json.load(fh)
except (IOError, OSError, ValueError) as e:
    print("NO-REGISTRY safety-status.json unreadable (%s); refusing rather than assuming" % e.__class__.__name__)
    sys.exit(0)
def status_of(v):
    if isinstance(v, dict):
        return v.get("status") or v.get("safety_status")
    return v if isinstance(v, str) else None
bad = []
for t in sorted(set(toks)):
    t_norm = re.sub(r'^(<PROJ>|\$\{PROJ\}|\$PROJ|PROJ)/+', '', t).lstrip("./")
    hit = None
    for k, v in d.items():
        if not isinstance(k, str):
            continue
        if k == t or k.endswith("/" + t_norm):
            hit = status_of(v); break
    if hit != "CLEARED":
        bad.append("%s=%s" % (t, hit or "unregistered"))
print("CLEARED" if not bad else "NOT-CLEARED " + "; ".join(bad))
PY_ICR
}
## R1 SCOPE DISCLAIMERS (2026-08-19, F-74). Reviewers write scopes like
##     "scripts/, logs/ ONLY. NEVER data/, NEVER materials/, NEVER any .csv/.rds/.dta/.sav."
## — an explicit statement of the boundary they are promising to respect. The classifier flagged exactly
## that sentence, so **the more carefully a reviewer declared what they would not touch, the more certainly
## the request was refused.** That is an incentive pointed the wrong way: it rewards vague scopes.
## Everything from the first NEVER onward is dropped before classifying the SCOPE field. The COMMAND field
## is deliberately NOT passed through this — a disclaimer in prose is not a request, but the command is what
## would actually run, and it stays checked in full, hard rules and registry alike.
## 2026-08-22 (verification round): reviewers phrase the same promise without the
## literal NEVER — "NOT under data/", "Touches no file under data/", "no
## filesystem access". Same F-74 inversion, same cure: cut from the first
## negative-scope head onward before classifying.
strip_disclaimer() { printf '%s' "$1" | sed -E 's/[[:space:]]*(—[[:space:]]*)?(NEVER|NOT under|[Tt]ouches no|[Tt]ouch no|[Nn]o filesystem access).*$//I'; }

## The vocabulary stays CLOSED; only trailing annotation is tolerated (2026-08-20).
## A reviewer wrote `PENDING-USER-AUTHORIZATION  (re-filed; iteration-1 request unanswered)` — the correct
## token, followed by the reason it was being re-filed. The anchored-both-ends match rejected it as "an
## unreadable status", which it plainly is not: the token is unambiguous and first. The rule as written
## punished a reviewer for explaining themselves and would have been satisfied by deleting the explanation,
## so it selected against exactly the context a human authorizer needs when deciding whether to grant a
## request. The token must still be one of the three and must still lead; anything after it is commentary.
## R3 2026-08-22: heading-style prose writes the token as a sentence —
## `PENDING-USER-AUTHORIZATION. I did not run it; …` — so punctuation
## directly after the token is annotation too, same principle: the token is
## one of the three and it LEADS; everything after a space or . , ; is
## commentary for the human authorizer.
## WITHDRAWN (R3 eval, 2026-08-22, second sighting): a request overtaken by
## a fix — the ses "CLOSED — MOOTED BY HARDENING" class — is neither
## declined nor run; forcing it into DECLINED misrecords the disposition
## and leaving it off-vocabulary REDs forever. WITHDRAWN (the findings-
## ledger's own terminal for this) closes the request: the record stays,
## nothing runs, nothing is pending. Legacy off-vocabulary statuses are
## remediated by setting status: WITHDRAWN — status lines are the one
## sanctioned in-place mutation of a filed request (same as DECLINED).
STATUS_RE='^(PENDING-USER-AUTHORIZATION|AUTHORIZED-AND-RUN|DECLINED|WITHDRAWN)([[:space:].,;].*)?$'

n_total=0; n_pending=0; n_run=0; n_declined=0; n_withdrawn=0
# Every RED reason is attached to the REQUEST it came from as well as to the
# global prose list: a consumer must be able to tell WHICH request is
# unauthorizable, which a flat list of formatted strings cannot say.
_rec_reds=""
_icr_red() { RED_LINES+=("$1"); _rec_reds="${_rec_reds:+$_rec_reds|||}$1"; }

# Parse blocks: from a line that is exactly `INDEPENDENT-CHECK REQUESTED` until the next
# non-indented line (or EOF). Keys are the first token before ':' on indented lines.
_icr_scanned=0
for f in "${REPORTS[@]}"; do
  if [ "$ICR_JSON" = "1" ] && [ "$_icr_start_epoch" -gt 0 ]; then
    _icr_now=$(date -u +%s 2>/dev/null || echo 0)
    if [ "$_icr_now" -gt 0 ] && [ $((_icr_now - _icr_start_epoch)) -ge "$ICR_BUDGET_S" ]; then
      _icr_budget_exhausted=true
      _icr_files_unscanned=$(( ${#REPORTS[@]} - _icr_scanned ))
      break
    fi
  fi
  # A file we cannot open has NOT been checked. Swallowing it into the loop
  # produced a confident GREEN over a report the gate never read.
  if [ ! -r "$f" ]; then
    _icr_files_unreadable=$((_icr_files_unreadable + 1))
    echo "  UNREADABLE: $f (permission denied) — its requests were NOT examined"
    continue
  fi
  _icr_scanned=$((_icr_scanned + 1))
  base="$(basename "$f")"
  in_block=0; blk=""; k_claim=""; k_why=""; k_command=""; k_scope=""; k_status=""; blk_start=0; ln=0
  flush() {
    [ "$in_block" -eq 1 ] || return 0
    n_total=$((n_total+1))
    _rec_reds=""
    local tag="$base:$blk_start"
    ## A DECLINED REQUEST IS CLOSED, NOT AN OPEN VIOLATION (2026-08-20).
    ## R1 exists to stop an inadmissible request from reaching a human for authorization. A request already
    ## marked DECLINED has been refused: nobody will run it, and no authorization is pending. Grading it RED
    ## forever means that once ANY reviewer has ever asked for something inadmissible, the gate can never be
    ## cleared except by DELETING the request — destroying the record of what was asked and refused, which is
    ## exactly the audit trail this contract exists to create. The safety property is untouched: PENDING and
    ## AUTHORIZED-AND-RUN are still graded in full, and AUTHORIZED-AND-RUN naming a restricted path stays RED
    ## because that is the genuinely dangerous state — a request that both names data and claims to have run.
    local _closed=0
    # Glob agrees with STATUS_RE: token exact, or followed by whitespace or
    # . , ; — `DECLINED-superseded` is NOT closed (and R2 will reject it),
    # so the two readings of the field can no longer disagree (R3 F7).
    case "$k_status" in
      (DECLINED | DECLINED[[:space:].,\;]* | WITHDRAWN | WITHDRAWN[[:space:].,\;]*) _closed=1 ;;
    esac
    # R3 — required fields
    if [ -z "$k_command" ] || [ -z "$k_scope" ]; then
      [ "$_closed" -eq 1 ] && CLOSED_LINES+=("R3 $tag (DECLINED — recorded, not open)") || _icr_red "R3 $tag — request block missing 'command:' or 'scope:'; nothing can be authorized that is not stated exactly"
    fi
    # R1 — scope must never name a data path
    k_scope_chk="$(strip_disclaimer "$k_scope")"
    if printf '%s' "$k_scope_chk" | grep -qiE "$DATA_HARD_RE"; then
      [ "$_closed" -eq 1 ] && CLOSED_LINES+=("R1 $tag — scope named a restricted path; request DECLINED, never authorized") || _icr_red "R1 $tag — scope names a restricted path ('$k_scope'); not authorizable under LOCAL_MODE"
    elif printf '%s' "$k_scope_chk" | grep -qiE "$DATA_SOFT_RE"; then
      _v="$(soft_tokens_cleared "$k_scope_chk")"
      case "$_v" in
        CLEARED) : ;;   # every tabular token is registered CLEARED — a check on an aggregate is authorizable
        NO-REGISTRY*) [ "$_closed" -eq 1 ] && CLOSED_LINES+=("R1 $tag — scope named a tabular path with no registry to clear it; request DECLINED") || _icr_red "R1 $tag — scope names a tabular path and NO safety registry exists to establish clearance ($_v). The file was NOT judged unsafe — it could not be judged at all; run scholar-init (or register the file) and re-run" ;;
        *) [ "$_closed" -eq 1 ] && CLOSED_LINES+=("R1 $tag — scope named an uncleared tabular path; request DECLINED") || _icr_red "R1 $tag — scope names a tabular path that is not registry-CLEARED ($_v)" ;;
      esac
    fi
    if printf '%s' "$k_command" | grep -qiE "$DATA_HARD_RE"; then
      [ "$_closed" -eq 1 ] && CLOSED_LINES+=("R1 $tag — command named a restricted path; request DECLINED, never authorized") || _icr_red "R1 $tag — command names a restricted path ('$k_command'); not authorizable under LOCAL_MODE"
    elif printf '%s' "$k_command" | grep -qiE "$DATA_SOFT_RE"; then
      _v="$(soft_tokens_cleared "$k_command")"
      case "$_v" in
        CLEARED) : ;;   # every tabular token is registered CLEARED — a check on an aggregate is authorizable
        NO-REGISTRY*) [ "$_closed" -eq 1 ] && CLOSED_LINES+=("R1 $tag — command named a tabular path with no registry to clear it; request DECLINED") || _icr_red "R1 $tag — command names a tabular path and NO safety registry exists to establish clearance ($_v). The file was NOT judged unsafe — it could not be judged at all; run scholar-init (or register the file) and re-run" ;;
        *) [ "$_closed" -eq 1 ] && CLOSED_LINES+=("R1 $tag — command named an uncleared tabular path; request DECLINED") || _icr_red "R1 $tag — command names a tabular path that is not registry-CLEARED ($_v)" ;;
      esac
    fi
    # R2 — closed status vocabulary
    if ! printf '%s' "$k_status" | grep -qE "$STATUS_RE"; then
      _icr_red "R2 $tag — status '${k_status:-<absent>}' is not in the closed vocabulary (PENDING-USER-AUTHORIZATION|AUTHORIZED-AND-RUN|DECLINED|WITHDRAWN); an unreadable status must not pass — a request overtaken by a fix is remediated with status: WITHDRAWN"
    else
      ## Glob-suffixed to match STATUS_RE, which allows a trailing annotation after the token. Without the
      ## `*` these counters silently under-count every annotated status: a run showed REQUESTS_DECLINED=0
      ## beside CLOSED_VIOLATIONS=9, i.e. nine blocks recognised as declined by one code path and by none of
      ## the tallies. Two readings of the same field in one gate must not disagree.
      case "$k_status" in
        (PENDING-USER-AUTHORIZATION | PENDING-USER-AUTHORIZATION[[:space:].,\;]*) n_pending=$((n_pending+1)); PENDING+=("$tag"$'\n'"$blk") ;;
        (AUTHORIZED-AND-RUN | AUTHORIZED-AND-RUN[[:space:].,\;]*)                 n_run=$((n_run+1)) ;;
        (DECLINED | DECLINED[[:space:].,\;]*)                                     n_declined=$((n_declined+1)) ;;
        (WITHDRAWN | WITHDRAWN[[:space:].,\;]*)                                   n_withdrawn=$((n_withdrawn+1)) ;;
      esac
    fi
    # One record per request, emitted from the SAME pass that produced the
    # prose. valid=false carries its own reasons, so an unauthorizable request
    # can never reach a consumer as an ordinary pending one.
    if [ "$ICR_JSON" = "1" ]; then
      _rec_valid=true
      [ -n "$_rec_reds" ] && _rec_valid=false
      _icr_record "$tag" "$base" "$blk_start" "${k_status:-}" "${_form:-block}" \
        "$_rec_valid" "${_rec_reds:-}"
    fi
    in_block=0; blk=""; k_claim=""; k_why=""; k_command=""; k_scope=""; k_status=""
  }
  while IFS= read -r line || [ -n "$line" ]; do
    ln=$((ln+1))
    # A CRLF report made every request in it invisible: the block token compares
    # exactly, so `INDEPENDENT-CHECK REQUESTED\r` matched nothing and the file
    # graded GREEN with zero requests. Strip the carriage return, not the text.
    line="${line%$'\r'}"
    ## The block token, like the status token (2026-08-20 note above), leads and
    ## may carry a trailing BRACKETED or DASHED annotation: `INDEPENDENT-CHECK
    ## REQUESTED  [filed iteration 2, §B2]` is a reviewer explaining themselves,
    ## not an unreadable block. Prose that merely STARTS with the token — "See the
    ## INDEPENDENT-CHECK REQUESTED block at the end." wraps to a line beginning
    ## with it — must NOT parse: annotation heads are (, [, or a dash only
    ## (real-project eval 2026-08-22; both shapes observed on ses).
    _tok=0
    case "$line" in
      ("INDEPENDENT-CHECK REQUESTED") _tok=1 ;;
      ("INDEPENDENT-CHECK REQUESTED "*)
        _rest="$(printf '%s' "${line#INDEPENDENT-CHECK REQUESTED}" | sed -E 's/^[[:space:]]+//')"
        case "$_rest" in
          ("("* | "["* | "—"* | "–"* | "-"*) _tok=1 ;;
        esac ;;
    esac
    if [ "$_tok" -eq 1 ]; then
      flush; in_block=1; blk_start=$ln; blk="$line"; _cur_key=""; _form="block"; continue
    fi
    if [ "$in_block" -eq 1 ]; then
      case "$line" in
        [[:space:]]*)
          blk="$blk"$'\n'"$line"
          key="$(printf '%s' "$line" | sed -E 's/^[[:space:]]*([a-z]+):.*/\1/')"
          val="$(printf '%s' "$line" | sed -E 's/^[[:space:]]*[a-z]+:[[:space:]]*//')"
          ## F1 (R3 eval, 2026-08-22): a line that names NO key is a
          ## CONTINUATION of the current key's value. Capturing only the
          ## first physical line let a data/ path on the wrapped line of a
          ## command: bypass R1 entirely — live on ses, printed in the
          ## pending list inviting authorization of a LOCAL_MODE read.
          if [ "$key" = "$line" ]; then
            case "$_cur_key" in
              (claim)   k_claim="$k_claim $val" ;;
              (why)     k_why="$k_why $val" ;;
              (command) k_command="$k_command $val" ;;
              (scope)   k_scope="$k_scope $val" ;;
              (status)  : ;;   # status stays single-token-led; prose after it is annotation
            esac
            continue
          fi
          _cur_key="$key"
          case "$key" in
            claim)   k_claim="$val" ;;
            why)     k_why="$val" ;;
            command) k_command="$val" ;;
            scope)   k_scope="$val" ;;
            status)  k_status="$val" ;;
          esac ;;
        *) flush ;;
      esac
    fi
  done < "$f"
  flush
done

# Heading-style requests (real-project eval, ses 2026-08-22): reviewers filed
# `### ICR-N` sections instead of the exact block format, and the gate read
# nothing — the exact silent-overlook this gate exists to prevent. They are
# surfaced and counted (no R-rules — the fields are not machine-readable), and
# their presence blocks GREEN below.
# R3 (2026-08-22, eval deferral discharged): heading-style sections are now
# PARSED, not just counted. A `### ICR-N` section whose body carries any of
# the contract keys (status/command/scope — bullet, bold, or bare forms all
# tolerated) is fed through the SAME rule machinery as a block-format
# request (R1 data-path refusal, R2 closed status vocabulary, R3 required
# fields, pending surfacing). Only a section with NO recognizable key
# remains an unparseable-heading advisory.
_hdr_key() {
  # $1 section text, $2 key name -> value: the matching key line PLUS its
  # continuation lines (until the next bulleted **key:** line or a blank).
  # F1 (R3 eval, 2026-08-22): first-line-only capture let wrapped values
  # hide data/ paths from R1, and annotated key names — the live ses form
  # `**Command (aggregate-only, emits no rows):**` — were not recognized
  # at all, so the .dta inside never reached the refusal.
  printf '%s\n' "$1" | awk -v key="$2" '
    BEGIN { IGNORECASE = 1; on = 0 }
    {
      line = $0
      is_key = 0
      probe = line
      sub(/^[[:space:]]*[-*]*[[:space:]]*\**/, "", probe)
      if (match(probe, /^[A-Za-z][A-Za-z ]*(\([^)]*\))?[[:space:]]*\**[[:space:]]*:/)) is_key = 1
      if (on) {
        if (is_key || line ~ /^[[:space:]]*$/ || line ~ /^#/) exit
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
        printf " %s", line
        next
      }
      if (is_key) {
        head = tolower(probe)
        if (index(head, tolower(key)) == 1) {
          val = probe
          sub(/^[A-Za-z][A-Za-z ]*(\([^)]*\))?[[:space:]]*\**[[:space:]]*:[[:space:]]*/, "", val)
          sub(/^\*+[[:space:]]*/, "", val)
          gsub(/\*+[[:space:]]*$/, "", val)
          gsub(/^[[:space:]]+|[[:space:]]+$/, "", val)
          printf "%s", val
          on = 1
        }
      }
    }
    END { printf "\n" }'
}
_icr_h_scanned=0
for f in "${REPORTS[@]}"; do
  # The heading scan honours the SAME budget as the block scan. Without this a
  # budget-truncated run would still parse headings out of files whose blocks
  # were never read, leaving one file half-parsed and the reported
  # files_unscanned understating what was skipped.
  if [ "$ICR_JSON" = "1" ]; then
    if [ "$_icr_budget_exhausted" = "true" ]; then
      # The block loop already stopped. Heading coverage for the WHOLE corpus is
      # incomplete from here, including files whose blocks were read.
      _icr_unread=$(( ${#REPORTS[@]} - _icr_h_scanned ))
      [ "$_icr_unread" -gt "$_icr_files_unscanned" ] && _icr_files_unscanned=$_icr_unread
      break
    fi
    if [ "$_icr_start_epoch" -gt 0 ]; then
      _icr_now=$(date -u +%s 2>/dev/null || echo 0)
      if [ "$_icr_now" -gt 0 ] && [ $((_icr_now - _icr_start_epoch)) -ge "$ICR_BUDGET_S" ]; then
        _icr_budget_exhausted=true
        _icr_unread=$(( ${#REPORTS[@]} - _icr_h_scanned ))
        [ "$_icr_unread" -gt "$_icr_files_unscanned" ] && _icr_files_unscanned=$_icr_unread
        break
      fi
    fi
    _icr_h_scanned=$((_icr_h_scanned + 1))
  fi
  base="$(basename "$f")"
  # Uppercase/digit only after ICR- : `### ICR-review notes` is prose, not
  # a request id (R3 verification round F4); observed ids are ICR-1/ICR-Q4-2.
  _hlines=$(grep -nE '^#{2,}[[:space:]]*\[?ICR-[A-Z0-9]' "$f" 2>/dev/null | cut -d: -f1 || true)
  [ -n "$_hlines" ] || continue
  # awk END{NR}, not wc -l: wc counts NEWLINES, so a file whose last line
  # is unterminated lost that line from the final section — a legitimate
  # trailing `status: DECLINED.` graded as <absent> → false RED (R3
  # verification round F1).
  _total_lines=$(awk 'END { print NR }' "$f")
  while IFS= read -r _hl; do
    [ -n "$_hl" ] || continue
    # section body: from the heading to the line before the next heading
    _next=$(awk -v s="$_hl" 'NR > s && /^#{2,}[[:space:]]/ { print NR; exit }' "$f")
    _end=$(( ${_next:-$((_total_lines + 1))} - 1 ))
    _section=$(sed -n "${_hl},${_end}p" "$f")
    # A heading whose body carries a literal block-format request is already
    # parsed by the block loop — grading it again double-counted the same
    # request (R3 verification round F5).
    if printf '%s\n' "$_section" | grep -q '^INDEPENDENT-CHECK REQUESTED'; then
      continue
    fi
    _htitle=$(printf '%s\n' "$_section" | head -1)
    k_status=$(_hdr_key "$_section" "status")
    k_command=$(_hdr_key "$_section" "command")
    k_scope=$(_hdr_key "$_section" "scope")
    k_claim=$(_hdr_key "$_section" "claim")
    if [ -n "$k_status" ] || [ -n "$k_command" ] || [ -n "$k_scope" ]; then
      # feed through the block machinery: same counters, same R-rules
      in_block=1; blk_start=$_hl; blk="$_section"; k_why=""; _form="heading"
      flush
      _form="block"
    else
      HEADING_REQS+=("$base:$_hl — ${_htitle} (no status/command/scope keys — not machine-readable)")
      [ "$ICR_JSON" = "1" ] && printf '%s\n' "$base:$_hl — ${_htitle}" >> "$ICR_TMP.headings"
    fi
  done <<EOF_ICR_H
$_hlines
EOF_ICR_H
done
echo "HEADING_STYLE_REQUESTS=${#HEADING_REQS[@]}"
for _h in ${HEADING_REQS[@]+"${HEADING_REQS[@]}"}; do echo "  HEADING: $_h"; done

_ICR_COUNTED=1
echo "REQUESTS_TOTAL=$n_total"
echo "REQUESTS_PENDING=$n_pending"
echo "REQUESTS_RUN=$n_run"
echo "REQUESTS_DECLINED=$n_declined"
echo "REQUESTS_WITHDRAWN=$n_withdrawn"
echo "CLOSED_VIOLATIONS=${#CLOSED_LINES[@]}"
for _c in ${CLOSED_LINES[@]+"${CLOSED_LINES[@]}"}; do echo "  CLOSED: $_c"; done
echo "RED_COUNT=${#RED_LINES[@]}"

if [ "${#RED_LINES[@]}" -gt 0 ]; then
  echo "STATUS=RED"
  _ICR_REASON="${#RED_LINES[@]} request block(s) violate the request contract"
  echo "REASON=$_ICR_REASON"
  for r in ${RED_LINES[@]+"${RED_LINES[@]}"}; do echo "  RED: $r"; done
  ## One bad block must not hide the good ones (real-project eval, cohab
  ## 2026-08-22: 1 RED suppressed 20 pending requests from the output — the
  ## user was never shown what was waiting on them). Print them here too;
  ## authorization still runs through the YELLOW-path instructions.
  if [ "$n_pending" -gt 0 ]; then
    echo ""
    echo "NOTE: $n_pending request(s) remain PENDING-USER-AUTHORIZATION and still need a"
    echo "      human decision INDEPENDENT of the violation(s) above:"
    for p in ${PENDING[@]+"${PENDING[@]}"}; do
      _ptag="${p%%$'\n'*}"
      # F5 (R3 eval): a RED-flagged request must not read as awaiting
      # authorization — mark it so one block never says both things.
      _pflag=""
      for r in ${RED_LINES[@]+"${RED_LINES[@]}"}; do
        case "$r" in (*"$_ptag"*) _pflag=" — NOT AUTHORIZABLE AS FILED (see RED above; refile per contract)" ; break ;; esac
      done
      echo "── request at ${_ptag}${_pflag} ──"
      printf '%s\n' "${p#*$'\n'}"
      echo ""
    done
    echo "To authorize a clean one: dispatch a Bash-capable agent with the 'command:' and"
    echo "'scope:' quoted EXACTLY as filed, append VERIFICATION: INDEPENDENT to the report,"
    echo "and set status: AUTHORIZED-AND-RUN. To decline: status: DECLINED. Overtaken by a"
    echo "fix: status: WITHDRAWN. RED-flagged blocks must be REFILED to contract first."
  fi
  _icr_emit RED 1
  exit "${_ICR_EMIT_RC:-1}"
fi

if [ "$n_pending" -gt 0 ]; then
  echo "STATUS=YELLOW"
  _ICR_REASON="$n_pending independent-check request(s) PENDING-USER-AUTHORIZATION — surface verbatim to the user; the orchestrator MUST NOT grant, run, or dismiss them"
  echo "REASON=$n_pending independent-check request(s) PENDING-USER-AUTHORIZATION — surface verbatim to the user; the orchestrator MUST NOT grant, run, or dismiss them"
  echo ""
  for p in ${PENDING[@]+"${PENDING[@]}"}; do
    echo "── request at ${p%%$'\n'*} ──"
    printf '%s\n' "${p#*$'\n'}"
    echo ""
  done
  echo "To authorize one: dispatch a Bash-capable agent (review-code-statistics) with the"
  echo "'command:' and 'scope:' quoted EXACTLY as filed, append its result to the requesting"
  echo "report as VERIFICATION: INDEPENDENT (user-authorized <date>; run by <agent>; <command>),"
  echo "and set that block's status: to AUTHORIZED-AND-RUN. To decline: set status: DECLINED."
  _icr_emit YELLOW 2
  exit "${_ICR_EMIT_RC:-2}"
fi

if [ "${#HEADING_REQS[@]}" -gt 0 ]; then
  echo "STATUS=YELLOW"
  _ICR_REASON="${#HEADING_REQS[@]} heading-style ICR section(s) carry NO status/command/scope keys and cannot be parsed"
  echo "REASON=${#HEADING_REQS[@]} heading-style ICR section(s) carry NO status/command/scope keys and cannot be parsed — refile each as an INDEPENDENT-CHECK REQUESTED block (claim/why/command/scope/status) or add those keys to the section; an unreadable request must not be silently overlooked"
  _icr_emit YELLOW 2
  exit "${_ICR_EMIT_RC:-2}"
fi

echo "STATUS=GREEN"
if [ "$n_total" -eq 0 ]; then
  _ICR_REASON="no independent-check requests filed across ${#REPORTS[@]} report(s)"
else
  _ICR_REASON="all $n_total request(s) resolved ($n_run run, $n_declined declined, $n_withdrawn withdrawn); none pending"
fi
echo "REASON=$_ICR_REASON"
_icr_emit GREEN 0
exit "${_ICR_EMIT_RC:-0}"
