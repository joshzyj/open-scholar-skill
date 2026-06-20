#!/usr/bin/env bash
# build-codex-mirror.sh — E1 hard control B: data-free mirror for codex review.
#
# Problem
# -------
# `codex exec` reviews a project with `-C <dir>` as its cwd. `-s read-only`
# restricts WRITES, not read scope — codex can `cat` any absolute path the OS
# user can read (validated). So pointing `-C` at the live project on
# a LOCAL_MODE run lets a codex agent open restricted microdata a script names.
#
# Control
# -------
# Build a DATA-FREE MIRROR of the project and point codex's `-C` at it. Scripts
# read data by RELATIVE path, so from cwd=mirror a relative read resolves to
# <mirror>/data/... which does not exist → codex gets "No such file" and reports
# the data UNVERIFIABLE, while still reviewing the scripts. Validated end-to-end.
#
# Three exclusion layers (defense in depth):
#   (1) AUTHORITATIVE — every path the safety sidecar marks LOCAL_MODE / HALTED /
#       NEEDS_REVIEW is excluded by basename. This catches restricted data
#       regardless of extension or directory name (e.g. loose .csv/.txt
#       microdata under a non-`data/` dir).
#   (2) STRUCTURAL — exclude data/, raw/, materials/, .git/, node_modules/.
#   (3) EXTENSION — exclude every microdata file extension.
# Plus `--safe-links` so a symlink pointing OUTSIDE the tree (e.g. into a real
# data dir) is dropped, not copied. Post-build assertions (superset of the
# exclude set) fail RED if anything leaked.
#
# Residual hole (the GREP GUARD): a script that hard-codes an ABSOLUTE data path
# (or `setwd("/abs/data"); read_dta("x")`) can still be `cat`'d by codex because
# it is outside the mirror. The guard REDs (and HALTs the dispatch) on those.
# It cannot see a path built at runtime (paste0/sprintf/var) — documented
# residual.
#
# Usage
# -----
#   build-codex-mirror.sh <source_dir> [<proj_dir>]
#     <source_dir>  the directory codex's -C currently points at (e.g. "$(pwd)").
#     <proj_dir>    optional project root used to locate the safety sidecar for
#                   layer (1); if omitted, sidecars found under <source_dir> are
#                   used. The sidecar is also searched in <proj_dir>'s ancestors
#                   (some projects keep the sidecar at a parent/example root,
#                   not the project directory itself).
#
# Output: the mirror path on the LAST stdout line as `MIRROR=<abs-path>`.
# Exit: 0 built · 1 RED (absolute data path, or post-build leak) · 2 cannot run.
set -uo pipefail
export LC_ALL=C

SRC="${1:-}"
PROJ_IN="${2:-}"
MIRROR=""
if [ -z "$SRC" ] || [ ! -d "$SRC" ]; then
  echo "WARN: usage: build-codex-mirror.sh <source_dir> [<proj_dir>]" >&2
  exit 2
fi
SRC="$(cd "$SRC" && pwd)"

MICRO='dta|sav|por|zsav|rds|rdata|rda|RData|parquet|feather|sas7bdat|xpt|dbf'

# ── (0) Locate safety sidecars (for layer-1 authoritative excludes) ───────
# Search PROJ_IN (or SRC) subtree AND walk up its ancestors to the filesystem
# root, collecting every safety-status.json (bounded). Ancestors matter: the
# real sidecar can live at a grandparent root, not the project dir.
_SIDECARS=()
_seed="${PROJ_IN:-$SRC}"
[ -d "$_seed" ] && _seed="$(cd "$_seed" && pwd)" || _seed="$SRC"
while IFS= read -r _sc; do
  [ -n "$_sc" ] && _SIDECARS+=("$_sc")
done < <(find "$_seed" -name 'safety-status.json' -type f 2>/dev/null)
_d="$_seed"
for _i in 1 2 3 4 5 6; do
  [ -f "$_d/.claude/safety-status.json" ] && _SIDECARS+=("$_d/.claude/safety-status.json")
  _nd="$(dirname "$_d")"; [ "$_nd" = "$_d" ] && break; _d="$_nd"
done
unset _d _nd _i _seed _sc

# Collect basenames of restricted entries (LOCAL_MODE / HALTED / NEEDS_REVIEW).
_RESTRICTED_BN=()
if [ "${#_SIDECARS[@]}" -gt 0 ]; then
  while IFS= read -r _path; do
    [ -n "$_path" ] || continue
    _RESTRICTED_BN+=("$(basename "$_path")")
  done < <(
    for _s in "${_SIDECARS[@]}"; do
      [ -f "$_s" ] || continue
      grep -oE '"[^"]+"[[:space:]]*:[[:space:]]*"(LOCAL_MODE|HALTED|NEEDS_REVIEW)"' "$_s" 2>/dev/null \
        | sed -E 's/^"([^"]+)"[[:space:]]*:.*/\1/'
    done | sort -u
  )
fi

# ── (1) GREP GUARD — absolute data paths / setwd into an absolute data dir ──
HITS=""
while IFS= read -r _scr; do
  [ -n "$_scr" ] || continue
  _h=$(grep -nE \
    "[\"']/[^\"' ]*\.(${MICRO})[\"']?|[\"']/[^\"' ]*/(data|raw)/[^\"' ]*[\"']?|setwd\([\"']/[^\"' ]*/(data|raw)[^\"' ]*[\"']\)" \
    "$_scr" 2>/dev/null || true)
  if [ -n "$_h" ]; then
    while IFS= read -r _line; do
      [ -n "$_line" ] && HITS="${HITS}${HITS:+$'\n'}${_scr#"$SRC"/}:${_line}"
    done <<EOF
$_h
EOF
  fi
done <<EOF
$(find "$SRC" -type f \( -name '*.R' -o -name '*.r' -o -name '*.py' -o -name '*.do' -o -name '*.jl' \) \
    -not -path '*/.git/*' 2>/dev/null)
EOF
if [ -n "$HITS" ]; then
  echo "STATUS=RED" >&2
  echo "REASON=absolute_data_path_in_script" >&2
  echo "A script hard-codes an ABSOLUTE path into a data dir (or setwd's into one)." >&2
  echo "The data-free mirror cannot contain it, but codex can still 'cat' an absolute" >&2
  echo "path — so restricted data could reach the cloud reviewer. Rewrite as RELATIVE" >&2
  echo "(file.path(DATA,\"x.dta\") with DATA <- \"data/raw\"), then re-dispatch." >&2
  echo "Offending line(s):" >&2
  printf '  %s\n' "$HITS" | head -20 >&2
  exit 1
fi

# ── (2) BUILD THE DATA-FREE MIRROR ────────────────────────────────────────
if ! command -v rsync >/dev/null 2>&1; then
  echo "WARN: rsync not found — cannot build a data-free mirror; caller should" >&2
  echo "      fall back to the prompt-prohibition control." >&2
  exit 2
fi
MIRROR="$(mktemp -d "${TMPDIR:-/tmp}/codex-mirror.XXXXXX")"

# Build rsync exclude args: layer-1 (sidecar basenames) + layers 2/3 (dir/ext).
_EXC=( --safe-links
  --exclude='.git/' --exclude='node_modules/'
  --exclude='data/' --exclude='raw/' --exclude='materials/'
  --exclude='*.dta' --exclude='*.sav' --exclude='*.por' --exclude='*.zsav'
  --exclude='*.rds' --exclude='*.RData' --exclude='*.rda' --exclude='*.rdata'
  --exclude='*.parquet' --exclude='*.feather' --exclude='*.sas7bdat'
  --exclude='*.xpt' --exclude='*.dbf' )
for _bn in "${_RESTRICTED_BN[@]:-}"; do
  [ -n "$_bn" ] && _EXC+=( --exclude="$_bn" )
done

rsync -a "${_EXC[@]}" "$SRC"/ "$MIRROR"/ 2>/dev/null \
  || { echo "WARN: rsync failed building mirror at $MIRROR" >&2; exit 2; }

# ── (3) POST-BUILD LEAK ASSERTIONS (RED on any survivor) ──────────────────
# (a) no microdata file extension survived (superset of the rsync exclude set).
_leak=$(find "$MIRROR" -type f \( \
        -iname '*.dta' -o -iname '*.sav' -o -iname '*.por' -o -iname '*.zsav' \
     -o -iname '*.rds' -o -iname '*.rdata' -o -iname '*.rda' \
     -o -iname '*.parquet' -o -iname '*.feather' -o -iname '*.sas7bdat' \
     -o -iname '*.xpt' -o -iname '*.dbf' \) 2>/dev/null | head -3)
# (b) no sidecar-marked restricted basename survived (catches odd-extension data).
if [ -z "$_leak" ] && [ "${#_RESTRICTED_BN[@]}" -gt 0 ]; then
  for _bn in "${_RESTRICTED_BN[@]}"; do
    [ -n "$_bn" ] || continue
    _f=$(find "$MIRROR" -type f -name "$_bn" 2>/dev/null | head -1)
    [ -n "$_f" ] && { _leak="$_f"; break; }
  done
fi
# (c) no data/ directory survived.
_leakdir=$(find "$MIRROR" -type d -name data 2>/dev/null | head -1)
# (d) no symlink survived that resolves outside the mirror (or is dangling).
_leaklink=""
while IFS= read -r _ln; do
  [ -n "$_ln" ] || continue
  _tgt=$(cd "$(dirname "$_ln")" 2>/dev/null && readlink "$_ln" 2>/dev/null || true)
  _real=$(readlink -f "$_ln" 2>/dev/null || true)
  case "$_real" in "$MIRROR"/*) : ;; *) _leaklink="$_ln"; break ;; esac
done < <(find "$MIRROR" -type l 2>/dev/null)

if [ -n "$_leak" ] || [ -n "$_leakdir" ] || [ -n "$_leaklink" ]; then
  echo "STATUS=RED" >&2
  echo "REASON=restricted_artifact_leaked_into_mirror" >&2
  [ -n "$_leak" ]     && echo "  microdata file: $_leak" >&2
  [ -n "$_leakdir" ]  && echo "  data/ dir:      $_leakdir" >&2
  [ -n "$_leaklink" ] && echo "  unsafe symlink: $_leaklink" >&2
  exit 1
fi

echo "OK: data-free mirror built (scripts present; data/ + microdata + ${#_RESTRICTED_BN[@]} sidecar-marked file(s) excluded)" >&2
echo "MIRROR=${MIRROR}"
exit 0
