#!/usr/bin/env bash
# PostToolUse hook — Strict-tier Bash STDOUT redactor (accident-mitigation).
#
# Claude Code calls this AFTER a Bash tool runs, passing the tool result on
# stdin. We inspect the command's stdout/stderr and, when the project is at
# safety level >= strict AND has restricted data, REPLACE row-level / PII
# output with a redaction notice before it reaches the model's context.
#
# SCOPE / HONESTY: this is ACCIDENT-MITIGATION, not a containment wall. It
# guards the output channel for ANY verb (so it catches dumps the PreToolUse
# denylist misses — ruby/node/custom scripts), but it is EVADABLE by encoding
# the output (base64/gzip/hex) and is blind to pattern-less restricted
# microdata below the volume threshold. The real boundary is the OS sandbox
# (Lockdown level). PostToolUse cannot block (the tool already ran); it can
# only redact what the model SEES.
#
# Activation: only acts when resolve_safety_level (project _safety_level >
# env SCHOLAR_SAFETY_LEVEL > "standard") is strict|lockdown AND the project's
# .claude/safety-status.json has >=1 LOCAL_MODE/HALTED/NEEDS_REVIEW entry.
# Otherwise it is a fast no-op. FAILS OPEN on any error/ambiguity (a redactor
# must never break a command's output by crashing).
#
# Verified payload contract (Claude Code 2.1.153): input stdout/stderr live
# under .tool_response (object); the replacement value of updatedToolOutput
# MUST be an OBJECT mirroring tool_response (a bare string is ignored).
#
# Exit code: always 0. JSON on stdout (when redacting) is the only signal.

set -uo pipefail

# Never let a crash alter output: trap → emit nothing, exit 0 (pass-through).
trap 'exit 0' ERR

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAFETY_SCAN="${HOOK_DIR}/safety-scan.sh"
[ -f "${HOOK_DIR}/sidecar-schema.sh" ] && . "${HOOK_DIR}/sidecar-schema.sh"

command -v jq >/dev/null 2>&1 || exit 0          # no jq → cannot parse → pass

INPUT="$(cat)"; [ -n "$INPUT" ] || exit 0

TOOL_NAME="$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)"
[ "$TOOL_NAME" = "Bash" ] || exit 0
CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)"
OUT="$(printf '%s' "$INPUT" | jq -r '.tool_response.stdout // empty' 2>/dev/null)"
ERR="$(printf '%s' "$INPUT" | jq -r '.tool_response.stderr // empty' 2>/dev/null)"
[ -n "$OUT$ERR" ] || exit 0

# ─── Resolve project root (walk up from cwd for .claude/safety-status.json) ─
find_root() {
  local d="$1"
  [ -n "$d" ] || return 0
  while [ -n "$d" ] && [ "$d" != "/" ]; do
    [ -f "${d}/.claude/safety-status.json" ] && { printf '%s\n' "$d"; return 0; }
    d="$(dirname "$d")"
  done
  [ -f "/.claude/safety-status.json" ] && printf '%s\n' "/"
  return 0
}
ROOT="$(find_root "$CWD")"
SIDECAR=""
[ -n "$ROOT" ] && SIDECAR="${ROOT}/.claude/safety-status.json"

# ─── Activation gate: level >= strict AND project has restricted data ──────
LEVEL="standard"
if declare -F resolve_safety_level >/dev/null 2>&1; then
  LEVEL="$(resolve_safety_level "$SIDECAR")"
else
  case "${SCHOLAR_SAFETY_LEVEL:-}" in strict|lockdown) LEVEL="$SCHOLAR_SAFETY_LEVEL" ;; esac
fi
case "$LEVEL" in strict|lockdown) : ;; *) exit 0 ;; esac

# Project must actually hold restricted data, else nothing to protect.
[ -n "$SIDECAR" ] && [ -f "$SIDECAR" ] || exit 0
jq -e 'to_entries | any(.value | type=="string" and test("^(LOCAL_MODE|HALTED|NEEDS_REVIEW)"))' \
   "$SIDECAR" >/dev/null 2>&1 || exit 0

# ─── Detectors ─────────────────────────────────────────────────────────────
# (a) PII via the canonical safety-scan.sh patterns, run on a temp text file.
# PII_ENTITIES is set as a side effect: the entity TYPES safety-scan matched
# (e.g. "PERSON", "US_SSN"). Types only — safety-scan prints the matched value
# as "[REDACTED len=N]" and never the value itself, so surfacing the type
# carries no data (C-01 holds). This exists because a guard that knows why it
# acted and does not say so forces the reader to guess: the previous notice
# said output matched "PII patterns OR a bulk row dump", and on 2026-08-27 two
# independent investigators each picked the wrong disjunct and spent multiple
# rounds chasing a threshold that does not exist. The real trigger was a
# statistical eponym ("Holm") scoring as PERSON.
PII_ENTITIES=""
scan_pii() {
  local text="$1" tmp rc out
  PII_ENTITIES=""
  [ -n "$text" ] || return 1
  [ -f "$SAFETY_SCAN" ] || return 1
  tmp="$(mktemp -t pt-scan.XXXXXX)" || return 1
  printf '%s' "$text" > "$tmp"
  out="$(bash "$SAFETY_SCAN" "$tmp" 2>/dev/null)"; rc=$?
  rm -f "$tmp"
  [ "$rc" = 1 ] || return 1        # 1 = RED (PII detected)
  # Detail lines read "  RED: PERSON (confidence: 0.85)". The summary line
  # "RED: 1 critical issue(s) found" must NOT match, so require >=1 letter.
  PII_ENTITIES="$(printf '%s\n' "$out" \
    | sed -n 's/^[[:space:]]*RED:[[:space:]]*\([A-Z_][A-Z_]*\).*/\1/p' \
    | sort -u | tr '\n' ',' | sed 's/,$//')"
  [ -n "$PII_ENTITIES" ] || PII_ENTITIES="unspecified"
  return 0
}
# (b) Bulk row dump: many delimited lines (>200 lines with >=2 commas OR tabs).
# Use awk (exits 0, prints a clean integer) rather than `grep -c ... || echo 0`
# which yields "0\n0" on zero matches and breaks the integer test below
# (the grep-count-capture bug class — see test-grep-count-capture-lint.sh).
is_bulk_rows() {
  local text="$1" n
  n="$(printf '%s\n' "$text" | awk '{c=gsub(/,/,","); t=gsub(/\t/,"\t"); if(c>=2||t>=2) n++} END{print n+0}')"
  [ "${n:-0}" -gt 200 ]
}

# Record WHICH detector fired, not merely THAT one did.
REDACT_OUT=0; REDACT_ERR=0
WHY_OUT=""; WHY_ERR=""
if [ -n "$OUT" ]; then
  if scan_pii "$OUT"; then
    REDACT_OUT=1; WHY_OUT="PII scan matched entity type(s): ${PII_ENTITIES}"
  elif is_bulk_rows "$OUT"; then
    REDACT_OUT=1
    WHY_OUT="bulk row dump ($(printf '%s\n' "$OUT" | awk '{c=gsub(/,/,","); t=gsub(/\t/,"\t"); if(c>=2||t>=2) n++} END{print n+0}') delimited lines, threshold 200)"
  fi
fi
if [ -n "$ERR" ]; then
  if scan_pii "$ERR"; then
    REDACT_ERR=1; WHY_ERR="PII scan matched entity type(s): ${PII_ENTITIES}"
  fi
fi

[ "$REDACT_OUT" = 1 ] || [ "$REDACT_ERR" = 1 ] || exit 0   # nothing to redact

NOTICE="[SAFETY GUARD — Strict level] This Bash command's output was redacted
for the reason named in REDACTION_TRIGGER above — do not infer a different one.
Project is at safety level '${LEVEL}' with restricted data. Row-level data must
not enter context. Re-run as an aggregate-only Rscript -e / python3 -c summary
(see _shared/data-handling-policy.md §3a/§3b), or 'wc -l' / 'grep -c' for counts.
This redactor is accident-mitigation, not a wall — for a kernel-enforced
boundary use the Lockdown level."

NEW_OUT="$OUT"; NEW_ERR="$ERR"
# Prepend the specific trigger. The generic NOTICE explains the policy; this
# line explains THIS redaction, so the reader never has to guess which detector
# fired or infer a mechanism that does not exist.
[ "$REDACT_OUT" = 1 ] && NEW_OUT="[SAFETY GUARD] REDACTION_TRIGGER: ${WHY_OUT}
$NOTICE"
[ "$REDACT_ERR" = 1 ] && NEW_ERR="[SAFETY GUARD] stderr redacted. REDACTION_TRIGGER: ${WHY_ERR}"

jq -n --arg out "$NEW_OUT" --arg err "$NEW_ERR" \
  '{hookSpecificOutput:{hookEventName:"PostToolUse",
     updatedToolOutput:{stdout:$out,stderr:$err,interrupted:false,isImage:false,noOutputExpected:false}}}'
exit 0
