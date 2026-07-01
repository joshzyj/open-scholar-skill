#!/usr/bin/env bash
# generate-lockdown-config.sh — Stage 3 "lockdown": generate the OS-enforced
# read-deny sandbox config for the sensitive data dirs, for Claude Code and/or
# Codex. This is the ONLY tier that stops a determined / prompt-injected agent:
# the kernel sandbox physically blocks a subprocess (cat / python / base64 / …)
# from opening the file, not just the cooperative PreToolUse hook.
#
# VERIFIED 2026-07-01:
#   - Claude Code 2.1.197 (macOS Seatbelt): `sandbox.filesystem.denyRead` →
#     `cat data/raw/x.csv` returns "Operation not permitted", 0 leak.
#   - Codex 0.142.5: `[permissions.<id>.filesystem]` `"data"="deny"` →
#     "blocked by the active permission profile", 0 leak.
#
# WHAT IT DENIES
#   - The standard data dirs that exist: data/raw, data/interim, data/processed.
#   - (Claude only, v1) any sidecar file marked LOCAL_MODE / HALTED /
#     NEEDS_REVIEW that lives OUTSIDE those dirs (added as an absolute denyRead).
#
# THE LOCKDOWN TENSION (honest): denyRead blocks ALL reads of data/ at the OS
#   level — including a sanctioned LOCAL_MODE `Rscript` that must read the raw
#   file to emit summaries. There is no OS way to "deny cat but allow Rscript"
#   (both are subprocesses). So:
#     default            → allowUnsandboxedCommands=false : a true wall; run your
#                          analysis BEFORE locking, or drop to `strict`, analyze,
#                          then re-lock.
#     --allow-escalation → allowUnsandboxedCommands=true  : the agent's ad-hoc
#                          reads are still denied, but a HUMAN-APPROVED command
#                          may escalate out of the sandbox to read data. Usable,
#                          but a careless approval can let an injected read through.
#
# ACTIVATION: Claude Code snapshots settings at session start → RESTART required.
#   Codex loads the project `.codex/` layer only when the project is TRUSTED.
#
# Usage:
#   generate-lockdown-config.sh <project_dir> [--host claude-code|codex|both|auto]
#                                             [--allow-escalation]
# Exits: 0 ok | 1 error | 3 partial (a host skipped, e.g. foreign config)

set -uo pipefail
export LC_ALL=C

PROJ=""; HOST="auto"; ESCALATION="false"
while [ $# -gt 0 ]; do
  case "$1" in
    --host) HOST="${2:-auto}"; shift 2 ;;
    --host=*) HOST="${1#--host=}"; shift ;;
    --allow-escalation) ESCALATION="true"; shift ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "FAIL: unknown option '$1'" >&2; exit 1 ;;
    *) [ -z "$PROJ" ] && PROJ="$1" || { echo "FAIL: extra arg '$1'" >&2; exit 1; }; shift ;;
  esac
done
[ -n "$PROJ" ] || { echo "FAIL: usage: generate-lockdown-config.sh <project_dir> [--host ...] [--allow-escalation]" >&2; exit 1; }
[ -d "$PROJ" ] || { echo "FAIL: project dir not found: $PROJ" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "FAIL: jq required" >&2; exit 1; }

_b="$HOME/.claude/scholar-skill-bootstrap.sh"
[ -f "$_b" ] || _b="${SCHOLAR_SKILL_DIR:-.}/scripts/scholar-skill-bootstrap.sh"
[ -f "$_b" ] && . "$_b"; unset _b

# Resolve host
if [ "$HOST" = "auto" ]; then
  HELPER="${SCHOLAR_SKILL_DIR:-.}/scripts/detect-host-agent.sh"
  DETECTED="$( [ -f "$HELPER" ] && bash "$HELPER" 2>/dev/null || echo unknown )"
  case "$DETECTED" in claude-code) HOST="claude-code" ;; codex) HOST="codex" ;; *) HOST="both" ;; esac
fi

SIDE="$PROJ/.claude/safety-status.json"
# Canonical (pwd -P) so the prefix-match against sidecar keys — which
# scholar-init writes canonicalized — is not defeated by a symlinked ancestor
# (e.g. macOS /var -> /private/var, /tmp -> /private/tmp). Using plain `pwd`
# here misclassifies in-project files as "outside" and drops their Codex deny.
PROJ_ABS="$(cd "$PROJ" && pwd -P)"

# ── Compute deny targets ─────────────────────────────────────────────────
# Standard data dirs that exist (denied unconditionally — defense in depth:
# anything later dropped into data/raw is covered without a re-scan).
DATA_DIRS=()
for d in data/raw data/interim data/processed; do
  [ -d "$PROJ/$d" ] && DATA_DIRS+=("$d")
done
# Sidecar-restricted files OUTSIDE the data dirs (absolute paths).
EXTRA_ABS=()
if [ -f "$SIDE" ]; then
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    case "$p" in "$PROJ_ABS/data/raw/"*|"$PROJ_ABS/data/interim/"*|"$PROJ_ABS/data/processed/"*) continue ;; esac
    EXTRA_ABS+=("$p")
  done < <(jq -r 'to_entries[] | select(.key|type=="string") | select(.value|type=="string") | select(.value|test("LOCAL_MODE|HALTED|NEEDS_REVIEW")) | .key' "$SIDE" 2>/dev/null)
fi

if [ "${#DATA_DIRS[@]}" -eq 0 ] && [ "${#EXTRA_ABS[@]}" -eq 0 ]; then
  echo "generate-lockdown-config: no data dirs or restricted sidecar files found under $PROJ — nothing to deny." >&2
  echo "  (Create data/raw|interim|processed or run /scholar-init first.)" >&2
  exit 1
fi

RC=0

# ── Claude Code: merge sandbox block into <proj>/.claude/settings.json ────
gen_claude() {
  local settings="$PROJ/.claude/settings.json"
  mkdir -p "$PROJ/.claude"
  # Build the denyRead array: relative data-dir globs + absolute extra files.
  local deny_json; deny_json="$(
    { for d in "${DATA_DIRS[@]}"; do printf '%s\n' "./$d" "./$d/**"; done
      for a in "${EXTRA_ABS[@]}"; do printf '%s\n' "$a"; done
    } | jq -R . | jq -s .
  )"
  local unsandboxed; [ "$ESCALATION" = "true" ] && unsandboxed=true || unsandboxed=false
  # The sandbox object we want to ensure. Merge NON-DESTRUCTIVELY: preserve any
  # existing settings.json keys; deep-merge the sandbox block (our denyRead wins).
  local sandbox_obj; sandbox_obj="$(jq -n --argjson deny "$deny_json" --argjson uns "$unsandboxed" '
    {sandbox: {enabled:true, autoAllowBashIfSandboxed:true, allowUnsandboxedCommands:$uns,
               filesystem: {denyRead:$deny}}}')"
  local base="{}"; [ -f "$settings" ] && base="$(cat "$settings")"
  # Validate existing file is JSON; if not, refuse (don't clobber).
  if ! printf '%s' "$base" | jq -e . >/dev/null 2>&1; then
    echo "generate-lockdown-config: WARN $settings is not valid JSON — refusing to modify. Fix or remove it." >&2
    RC=3; return
  fi
  local tmp; tmp="$(mktemp)"
  printf '%s' "$base" | jq --argjson s "$sandbox_obj" '. * $s' > "$tmp" && mv "$tmp" "$settings"
  echo "generate-lockdown-config: wrote sandbox denyRead to $settings ($([ "$ESCALATION" = "true" ] && echo 'escalation ALLOWED' || echo 'HARD wall, no escalation'))"
  echo "  denied: ${DATA_DIRS[*]:-<none>}${EXTRA_ABS:+ + ${#EXTRA_ABS[@]} sidecar file(s)}"
  echo "  → RESTART Claude Code to activate (settings are snapshotted at session start)."
  [ "$ESCALATION" = "true" ] || echo "  → NOTE: this also blocks LOCAL_MODE Rscript reads. Run analysis before locking, or use --allow-escalation."
}

# ── Codex: [permissions] deny profile in <proj>/.codex/config.toml ────────
gen_codex() {
  local config="$PROJ/.codex/config.toml"
  mkdir -p "$PROJ/.codex"
  local MB="# scholar-lockdown:BEGIN v1" ME="# scholar-lockdown:END"
  # Codex denies the whole data/ tree (covers raw|interim|processed) PLUS each
  # restricted sidecar file that lives INSIDE the workspace but OUTSIDE data/
  # (e.g. materials/*), added as a workspace-relative "<rel>" = "deny" under
  # :workspace_roots — the same map form proven to block "data". Files that
  # resolve OUTSIDE the project entirely are still not covered (Codex
  # workspace-relative scoping does not reach them) and are reported below.
  local EXTRA_DENY_LINES="" _outside=0 _a _rel
  for _a in ${EXTRA_ABS[@]+"${EXTRA_ABS[@]}"}; do
    [ -n "$_a" ] || continue
    case "$_a" in
      "$PROJ_ABS/"*) _rel="${_a#"$PROJ_ABS"/}"; EXTRA_DENY_LINES="${EXTRA_DENY_LINES}\"${_rel}\" = \"deny\"
" ;;
      *) _outside=$((_outside + 1)) ;;
    esac
  done
  local block
  block="$(cat <<TOML
${MB}
# Auto-managed by /scholar-safety level lockdown. OS-enforced (Seatbelt/Landlock)
# read-deny on the data/ tree (+ restricted sidecar files) via a permissions
# profile. Activates once you TRUST this project in Codex. NOTE: [permissions]
# is mutually exclusive with sandbox_mode; if you set sandbox_mode, remove it.
default_permissions = "scholar-lockdown"

[permissions.scholar-lockdown.filesystem]
":minimal" = "read"

[permissions.scholar-lockdown.filesystem.":workspace_roots"]
"." = "read"
"data" = "deny"
${EXTRA_DENY_LINES}${ME}
TOML
)"
  if [ ! -f "$config" ]; then
    printf '%s\n' "$block" > "$config"
    echo "generate-lockdown-config: created $config (Codex [permissions] deny on data/)"
  elif grep -qF "$MB" "$config"; then
    local bf tf; bf="$(mktemp)"; tf="$(mktemp)"; printf '%s\n' "$block" > "$bf"
    awk -v b="$MB" -v e="$ME" -v bf="$bf" '
      $0==b {i=1; while((getline l<bf)>0) print l; close(bf); next}
      i && $0==e {i=0; next} i{next} {print}' "$config" > "$tf"
    mv "$tf" "$config"; rm -f "$bf"
    echo "generate-lockdown-config: refreshed lockdown block in $config"
  elif grep -qE '^[[:space:]]*(default_permissions|\[permissions)' "$config"; then
    echo "generate-lockdown-config: WARN $config already defines default_permissions/[permissions] (not scholar's)." >&2
    echo "  Refusing to clobber. Add filesystem \"data\"=\"deny\" to your profile manually." >&2
    RC=3; return
  else
    { printf '\n'; printf '%s\n' "$block"; } >> "$config"
    echo "generate-lockdown-config: appended lockdown block to $config"
  fi
  echo "  → TRUST this project in Codex to activate. [permissions] is mutually exclusive with sandbox_mode."
  [ "$_outside" -eq 0 ] || echo "  → NOTE: $_outside restricted sidecar file(s) resolve OUTSIDE this project and are NOT covered by the Codex workspace-relative profile; move them under the project or add a manual :root deny."
}

case "$HOST" in
  claude-code) gen_claude ;;
  codex)       gen_codex ;;
  both)        gen_claude; gen_codex ;;
  *) echo "FAIL: --host must be claude-code|codex|both|auto (got '$HOST')" >&2; exit 1 ;;
esac

exit "$RC"
