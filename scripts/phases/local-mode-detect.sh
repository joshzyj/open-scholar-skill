#!/usr/bin/env bash
# local-mode-detect.sh — is this project operating in LOCAL_MODE?
#
# Used by scholar-openai to decide whether to route codex through a data-free
# mirror (E1 control "B"). A FALSE NEGATIVE here silently lets codex read
# restricted data, so detection searches thoroughly:
#   - every safety-status.json under <proj> (any depth), AND
#   - safety-status.json in <proj>'s ancestors up to the filesystem root
#     (the real sidecar can live at a grandparent root, not the project dir), AND
#   - project-state.md under <proj> and <cwd> (records `**DATA MODE**: LOCAL_MODE`).
# A bare `LOCAL_MODE` match is used (not a structured regex) so markdown bold and
# the sidecar's per-path JSON entries are both caught. Each file is grep'd
# SEPARATELY (a missing file passed to one grep would exit non-zero and mask a
# real match elsewhere).
#
# Usage:  local-mode-detect.sh [<proj_dir>] [<cwd>]
#   defaults: proj_dir=".", cwd="$(pwd)".
# Exit:   0 = LOCAL_MODE detected · 1 = no LOCAL_MODE marker found.
set -uo pipefail
export LC_ALL=C

PROJ="${1:-.}"
CWD_IN="${2:-$(pwd)}"
[ -d "$PROJ" ] && PROJ="$(cd "$PROJ" && pwd)" || PROJ="."
[ -d "$CWD_IN" ] && CWD_IN="$(cd "$CWD_IN" && pwd)" || CWD_IN="$(pwd)"

_hit() { grep -qi 'LOCAL_MODE' "$1" 2>/dev/null; }

# (a) project-state.md at the obvious spots
for _f in "$PROJ/logs/project-state.md" "$CWD_IN/logs/project-state.md"; do
  [ -f "$_f" ] && _hit "$_f" && exit 0
done

# (b) any safety-status.json under PROJ (subtree)
while IFS= read -r _f; do
  [ -f "$_f" ] && _hit "$_f" && exit 0
done < <(find "$PROJ" -name 'safety-status.json' -type f 2>/dev/null)

# (c) safety-status.json in ancestors of PROJ and CWD (up to root, bounded)
for _start in "$PROJ" "$CWD_IN"; do
  _d="$_start"
  for _i in 1 2 3 4 5 6 7 8; do
    [ -f "$_d/.claude/safety-status.json" ] && _hit "$_d/.claude/safety-status.json" && exit 0
    _nd="$(dirname "$_d")"; [ "$_nd" = "$_d" ] && break; _d="$_nd"
  done
done

exit 1
