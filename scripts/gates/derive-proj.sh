#!/usr/bin/env bash
# derive-proj.sh — single source of truth for the ${PROJ} path.
#
# Every phase of scholar-full-paper, scholar-book, scholar-grant, etc. needs
# to write to the project-scoped output directory (`output/<slug>/`). Shell
# variables do NOT persist across Bash tool calls (per the repo's CLAUDE.md
# rule), so every Bash block has to re-derive PROJ. This helper is the
# canonical derivation logic — sourcing it replaces the legacy
#     PROJ="${PROJ:-output/_staging}"
# one-liner that defaulted every phase to a staging directory and silently
# broke the scholar-init → scholar-full-paper handshake.
#
# Usage (inside any Bash block in a SKILL.md or reference file):
#     . "${SCHOLAR_SKILL_DIR:-.}/scripts/gates/derive-proj.sh"
#     # PROJ is now set; use ${PROJ}/tables, ${PROJ}/logs, etc.
#
# Priority order:
#   1. If PROJ is already exported in the environment → keep it.
#   2. Existing project-state.md under output/<slug>/logs/ → use that slug.
#   3. scholar-init handshake context (.claude/safety-status.json + data/raw/)
#      → use basename(pwd) as slug and return output/<slug>.
#   4. Legacy fallback → output/_staging.
#
# This file is `source`d, not executed. It MUST NOT `exit`.

if [ -z "${PROJ:-}" ]; then
  # ─── Priority 2a: cwd-basename matches an existing project ─────────
  # If cwd is a scholar-init project root (or any directory that has a
  # corresponding output/<basename-of-cwd>/logs/project-state.md), use
  # THAT project. This is the stable per-invocation choice and avoids
  # misrouting to whichever project happens to have the newest state
  # file in a parent directory that contains multiple prior projects.
  _cwd_slug="$(basename "$(pwd)")"
  if [ -f "output/${_cwd_slug}/logs/project-state.md" ] \
     && [ -d "output/${_cwd_slug}" ]; then
    PROJ="output/${_cwd_slug}"
  fi
  unset _cwd_slug
fi

if [ -z "${PROJ:-}" ]; then
  # ─── Priority 2b: newest PROJECT STATE (legacy fallback) ───────────
  # Used when the cwd-basename heuristic above didn't match (e.g., the
  # user ran the orchestrator from a parent directory, or the slug
  # doesn't match any basename). Pick the most recently modified
  # project-state.md, excluding _staging.
  _state_candidate=""
  if [ -d output ]; then
    _state_candidate=$(ls -t output/*/logs/project-state.md 2>/dev/null \
                       | grep -v '/_staging/' \
                       | head -1)
  fi
  if [ -n "${_state_candidate}" ] && [ -f "${_state_candidate}" ]; then
    _maybe_proj=$(dirname "$(dirname "${_state_candidate}")")
    if [ -d "${_maybe_proj}" ]; then
      PROJ="${_maybe_proj}"
    fi
  fi
  unset _state_candidate _maybe_proj
fi

if [ -z "${PROJ:-}" ]; then
  # ─── Priority 3: scholar-init handshake context ────────────────────
  # Current directory IS a scholar-init project: use basename(pwd) as slug.
  if [ -f ".claude/safety-status.json" ] && [ -d "data/raw" ]; then
    PROJ="output/$(basename "$(pwd)")"
  fi
fi

if [ -z "${PROJ:-}" ]; then
  # ─── Priority 4: legacy _staging fallback ──────────────────────────
  PROJ="output/_staging"
fi

export PROJ
