#!/usr/bin/env bash
# detect-host-agent.sh — Returns the host AI coding tool currently driving
# this session, used to choose the project-memory filename written by
# setup-project-claudemd.sh (CLAUDE.md for Claude Code, AGENTS.md for Codex).
#
# OUTPUT (single line on stdout, exit code 0):
#   claude-code  — Claude Code session detected
#   codex        — OpenAI Codex CLI session detected
#   unknown      — no recognised signal (e.g., CI, manual invocation)
#
# DETECTION SIGNALS (verified 2026-05-28)
#
#   Claude Code (verified live in this session)
#     CLAUDECODE=1                          — canonical "I'm Claude Code"
#     CLAUDE_CODE_ENTRYPOINT=cli            — set by the CLI wrapper
#     CLAUDE_CODE_SESSION_ID=<uuid>         — session identifier
#     AI_AGENT=claude-code_<version>_agent  — cross-tool AI_AGENT convention
#
#   Codex (per OpenAI docs + GitHub issue #13416)
#     CODEX_CI=1                            — currently shipped
#     AGENT=codex                           — emerging cross-tool convention
#                                              (Goose uses AGENT=goose, Amp
#                                              uses AGENT=amp; tracked in
#                                              openai/codex#13416)
#
# OVERRIDE (highest precedence)
#   SCHOLAR_HOST_AGENT_OVERRIDE=<value>
#     Used by smoke tests and by users who want to force a particular file
#     layout. Accepted values: claude-code | codex | unknown (or any other
#     string echoed verbatim — caller decides validity).
#
# Precedence: override > claude-code > codex > unknown.
#
# Usage:
#   agent=$(bash scripts/detect-host-agent.sh)
#   case "$agent" in
#     claude-code) ... ;;
#     codex)       ... ;;
#     unknown)     ... ;;
#   esac
#
# Sourceable form (avoids subshell):
#   source scripts/detect-host-agent.sh
#   agent=$(detect_host_agent)

set -uo pipefail

detect_host_agent() {
  # Explicit override always wins (test hook + user opt-out)
  if [ -n "${SCHOLAR_HOST_AGENT_OVERRIDE:-}" ]; then
    printf '%s\n' "$SCHOLAR_HOST_AGENT_OVERRIDE"
    return 0
  fi

  # Claude Code signals (any one is sufficient; CLAUDECODE is canonical)
  if [ "${CLAUDECODE:-}" = "1" ]; then
    printf 'claude-code\n'
    return 0
  fi
  case "${AI_AGENT:-}" in
    claude-code*) printf 'claude-code\n'; return 0 ;;
  esac

  # Codex signals (CODEX_CI is current; AGENT=codex is emerging convention)
  if [ "${CODEX_CI:-}" = "1" ]; then
    printf 'codex\n'
    return 0
  fi
  if [ "${AGENT:-}" = "codex" ]; then
    printf 'codex\n'
    return 0
  fi

  printf 'unknown\n'
  return 0
}

# When executed directly (not sourced), run the function and exit.
# When sourced, expose the function and do nothing else.
# BASH_SOURCE[0] != $0 → sourced; equal → executed.
if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
  detect_host_agent
fi
