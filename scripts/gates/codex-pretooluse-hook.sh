#!/usr/bin/env bash
# codex-pretooluse-hook.sh — Codex CLI PreToolUse adapter for the data-safety guard.
#
# WHY THIS EXISTS
#   The data-safety guard `pretooluse-data-guard.sh` is registered as a *Claude
#   Code* PreToolUse hook in ~/.claude/settings.json. A **Codex** host never
#   reads that file, so under Codex the guard is inert. Codex has its OWN
#   PreToolUse hook mechanism (registered in a project's `.codex/config.toml`).
#   This script is the command a Codex PreToolUse hook runs: it hands Codex's
#   payload to the SAME guard (no second implementation) and translates the
#   guard's exit code into Codex's decision wire.
#
#   Payload compatibility was verified end-to-end against `codex exec`
#   v0.142.5 on 2026-07-01: Codex normalizes its shell tool to
#   tool_name="Bash" with tool_input={command:"<string>"} and includes `cwd`
#   — the exact fields pretooluse-data-guard.sh already parses. Returning the
#   deny wire below (or exit 2) BLOCKS the tool call ("hook: PreToolUse
#   Blocked") and surfaces the reason to the model.
#
# CONTRACT
#   stdin  : Codex PreToolUse payload JSON {tool_name, tool_input, cwd, ...}
#   stdout : on DENY, the Codex decision wire (permissionDecision:"deny");
#            on ALLOW, nothing.
#   exit   : 0 = allow, 2 = deny. On deny we emit BOTH the JSON wire and exit 2
#            (either alone blocks in Codex — belt-and-suspenders).
#
#   Delegation rule: guard exit 2 → DENY; guard exit 0 (or any other code) →
#   ALLOW. The guard's own EXIT trap already converts an abnormal crash on a
#   *data* path into exit 2, so "any other code = allow" cannot fail-open on a
#   real data read; a crash while evaluating a non-data path stays allow (and
#   must, so the Codex session is never bricked on unrelated failures).
#
# NOTE (scope): Codex reaches files primarily through the shell ("Bash") tool,
#   which this covers. It does NOT fire a distinct pre-*read* event, and — like
#   the Claude-side Bash speed-bump — this is a cooperative guardrail, not a
#   containment boundary (encodings / alternate interpreters / var-assembled
#   paths can evade it). The OS-enforced wall is the deferred Stage 3
#   `.codex` [permissions] `deny_read` profile. See _shared/data-handling-policy.md §9.

set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
GUARD="$SELF_DIR/pretooluse-data-guard.sh"

INPUT="$(cat)"   # slurp Codex's payload once

if [ ! -f "$GUARD" ]; then
  # Fail toward ALLOW-with-warning: a missing guard must not brick the Codex
  # session, but surface it loudly so the user knows the data guard is OFF.
  echo "codex-pretooluse-hook: WARN guard not found at $GUARD — data guard INACTIVE" >&2
  exit 0
fi

ERR="$(mktemp 2>/dev/null || echo "/tmp/cdxguard.$$")"
printf '%s' "$INPUT" | bash "$GUARD" >/dev/null 2>"$ERR"
RC=$?
REASON="$(cat "$ERR" 2>/dev/null)"; rm -f "$ERR" 2>/dev/null || true

if [ "$RC" -eq 2 ]; then
  [ -n "$REASON" ] || REASON="Blocked by scholar data-safety guard (restricted data file)."
  # JSON-escape the reason for the decision wire (jq -Rs slurps raw → JSON string).
  ESC="$(printf '%s' "$REASON" | jq -Rs . 2>/dev/null)"
  [ -n "$ESC" ] || ESC='"Blocked by scholar data-safety guard."'
  printf '{"decision":"block","reason":%s,"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}\n' "$ESC" "$ESC"
  # Also mirror a plain reason to stderr (some Codex surfaces show it).
  printf '%s\n' "$REASON" >&2
  exit 2
fi

# ALLOW: stay out of the way (no stdout, exit 0).
exit 0
