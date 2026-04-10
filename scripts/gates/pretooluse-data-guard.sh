#!/usr/bin/env bash
# PreToolUse hook — data-file safety guard.
#
# Claude Code calls this script before every tool invocation. It reads the
# hook payload from stdin (JSON with tool_name, tool_input, cwd, ...) and
# decides whether to allow or block the call.
#
# Behavior:
#   - Inspects tool_name ∈ {Read, NotebookRead, NotebookEdit, Grep, Glob}.
#     All other tools pass through.
#   - For Read / NotebookRead / NotebookEdit:
#     * Extracts the file_path (or notebook_path) argument.
#     * Canonicalizes it via realpath (resolves symlinks + relative segments).
#     * Checks if the extension is a data-file type. Non-data files pass.
#     * Checks the sidecar <cwd>/.claude/safety-status.json — honors
#       CLEARED/ANONYMIZED/OVERRIDE as allow; LOCAL_MODE/HALTED/
#       NEEDS_REVIEW:* as block.
#     * For image files, applies path-based classification (raw-data
#       directories → block; output/screenshot paths → allow).
#     * For other data files, delegates to safety-scan.sh.
#   - For Grep / Glob:
#     * Extracts the path/pattern argument.
#     * If it targets a raw-data directory segment, blocks the call
#       (Grep would return matching lines from sensitive files into
#       Claude's context, which is exactly what the guard must prevent).
#
# Exit codes (Claude Code hook semantics):
#   0 → allow the tool call
#   2 → block; stderr is surfaced to Claude as the refusal reason
#
# Bypass: there is no env-var bypass. To override a single file, write
# {"path": "OVERRIDE"} into <cwd>/.claude/safety-status.json. To disable
# globally, remove the hook from ~/.claude/settings.json.

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE_SCRIPT="${HOOK_DIR}/safety-scan.sh"

# ─── Helper: canonicalize a path (follow symlinks, resolve `..`) ────────
#
# Returns the resolved absolute path on stdout.
# Exit codes:
#   0 = resolved successfully (stdout has the canonical path)
#   1 = could not resolve, and the target is (or might be) a symlink.
#       Callers MUST fail closed on exit 1.
#
# Resolution order: python3 → realpath → readlink -f → bash fallback.
# The bash fallback does NOT resolve symlinks. If none of python3,
# realpath, or readlink -f is available AND the target is a symlink,
# return 1 to force callers into fail-closed behavior — otherwise a
# symlink pointing to /etc/passwd could evade the I4 system-dir check.
canonicalize() {
  local target="$1"
  [ -z "$target" ] && return 1
  local result

  if command -v python3 >/dev/null 2>&1; then
    result=$(python3 -c 'import os,sys; p=sys.argv[1]; print(os.path.realpath(p) if os.path.exists(p) else os.path.abspath(p))' "$target" 2>/dev/null)
    if [ -n "$result" ]; then
      printf '%s\n' "$result"
      return 0
    fi
  fi

  # GNU coreutils realpath (sometimes installed on macOS via brew)
  if command -v realpath >/dev/null 2>&1; then
    result=$(realpath "$target" 2>/dev/null)
    if [ -n "$result" ]; then
      printf '%s\n' "$result"
      return 0
    fi
  fi

  # Linux GNU readlink -f
  if result=$(readlink -f "$target" 2>/dev/null) && [ -n "$result" ]; then
    printf '%s\n' "$result"
    return 0
  fi

  # No symlink-resolving tool available. If the target IS a symlink (or
  # contains a symlink in its path), we cannot safely canonicalize it —
  # refuse. The I4 system-directory check depends on symlink resolution.
  if [ -L "$target" ]; then
    return 1
  fi
  # Walk parent directories looking for any symlink component.
  local parent="$target"
  while [ "$parent" != "/" ] && [ -n "$parent" ]; do
    parent=$(dirname "$parent")
    if [ -L "$parent" ]; then
      return 1
    fi
  done

  # Target is a plain file / directory with no symlinks in its path.
  # The bash fallback is safe here.
  if [ -e "$target" ]; then
    local dir base
    dir="$(cd "$(dirname "$target")" 2>/dev/null && pwd)"
    base="$(basename "$target")"
    if [ -n "$dir" ]; then
      printf '%s\n' "${dir}/${base}"
      return 0
    fi
  fi
  printf '%s\n' "$target"
  return 0
}

# ─── Data extension list (shared between Read and Grep/Glob checks) ─────
# Extensions here are ALWAYS inspected. Document formats (.txt, .rtf, .docx)
# are NOT in this list — they're conditionally inspected only when inside a
# data-ish directory (see the CONDITIONAL_TEXT_EXTS check below), because a
# README.txt at the project root is overwhelmingly non-sensitive and should
# not require OVERRIDE every time Claude reads it.
DATA_EXTS=(
  # Tabular / structured
  csv tsv dta sav rds rdata xlsx xls parquet feather arrow db sqlite
  # Semi-structured
  jsonl ndjson
  # Audio (inherent biometric identifier)
  wav mp3 flac m4a ogg aac aiff
  # Video
  mp4 mov avi mkv webm
  # Images (often PII — faces, documents)
  jpg jpeg png tiff tif heic heif bmp webp gif
  # Linguistics-specific
  eaf textgrid trs cha praat
  # Geospatial
  shp geojson kml gpx
)

# Text/document extensions that are inspected ONLY when in data-ish paths.
# Policy §0 says these count as data when they contain interview transcripts,
# field notes, open-ended survey responses, consent forms, etc. — typically
# files in data/raw/, materials/, corpus/, subjects/, etc.
CONDITIONAL_TEXT_EXTS=(txt rtf docx doc odt md)

is_data_ext() {
  local ext="$1"
  for E in "${DATA_EXTS[@]}"; do
    [ "$ext" = "$E" ] && return 0
  done
  return 1
}

is_image_ext() {
  case "$1" in
    jpg|jpeg|png|tiff|tif|heic|heif|bmp|webp|gif) return 0 ;;
  esac
  return 1
}

# Path segments that indicate raw/sensitive data directories
is_rawdata_path() {
  case "$1" in
    */data/raw/*|*/data/raw|\
    */data/interim/*|*/data/interim|\
    */data/processed/*|*/data/processed|\
    */data/*|*/raw/*|*/input/*|*/inputs/*|\
    */datasets/*|*/dataset/*|*/corpus/*|*/corpora/*|\
    */photos/*|*/subjects/*|*/participants/*|*/respondents/*|\
    */media/*|*/imagery/*|*/scans/*|*/originals/*|*/source_images/*)
      return 0 ;;
  esac
  return 1
}

# ─── 1. Read payload ────────────────────────────────────────────────────
INPUT="$(cat)"
if [ -z "$INPUT" ]; then
  exit 0    # nothing to inspect
fi

# ─── 2. Parse tool_name + target paths ──────────────────────────────────
# Prefer jq; fall back to a crude sed parser that handles the minimum we
# need to make a safe decision.
if command -v jq >/dev/null 2>&1; then
  TOOL_NAME="$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)"
  FILE_PATH="$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' 2>/dev/null)"
  CWD="$(printf '%s'      "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)"
  # For Grep/Glob the targetable path is `.tool_input.path` (Grep) or the
  # pattern itself (Glob). We extract whichever the tool uses.
  GREP_PATH="$(printf '%s' "$INPUT" | jq -r '.tool_input.path // empty' 2>/dev/null)"
  GLOB_PATTERN="$(printf '%s' "$INPUT" | jq -r '.tool_input.pattern // empty' 2>/dev/null)"
  JQ_OK=1
else
  # Pure-bash fallback. We extract only the fields we need to make a
  # fail-closed decision on data-file reads.
  TOOL_NAME="$(printf '%s' "$INPUT" | sed -n 's/.*"tool_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
  FILE_PATH="$(printf '%s' "$INPUT" | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
  if [ -z "$FILE_PATH" ]; then
    FILE_PATH="$(printf '%s' "$INPUT" | sed -n 's/.*"notebook_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
  fi
  CWD="$(printf '%s' "$INPUT" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
  GREP_PATH="$(printf '%s' "$INPUT" | sed -n 's/.*"path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
  GLOB_PATTERN="$(printf '%s' "$INPUT" | sed -n 's/.*"pattern"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
  JQ_OK=0
fi

# ─── 2b. Fail-closed check when sed fallback couldn't extract FILE_PATH
# If jq is missing AND the tool name matches a gated tool AND we failed
# to extract a file path via sed (empty FILE_PATH / empty GREP_PATH /
# empty GLOB_PATTERN), fail closed. The sed regex can't handle escaped
# quotes or malformed JSON, so an empty result may be a parse failure
# rather than a legitimately absent field. Never silently allow a gated
# tool call that we couldn't parse.
if [ "$JQ_OK" = 0 ]; then
  case "$TOOL_NAME" in
    Read|NotebookRead|NotebookEdit)
      if [ -z "$FILE_PATH" ]; then
        cat >&2 <<EOF
SAFETY GUARD: $TOOL_NAME blocked.

jq is not installed, and the pure-bash fallback parser could not extract
tool_input.file_path from the hook payload. This may be a parse failure
(escaped quotes, unicode, or malformed JSON), not a legitimately absent
field — failing closed as a precaution.

Install jq so the guard can parse payloads reliably:
  macOS:  brew install jq
  Linux:  apt-get install jq  (or dnf / pacman)
EOF
        exit 2
      fi
      ;;
    Grep|Glob)
      if [ -z "$GREP_PATH" ] && [ -z "$GLOB_PATTERN" ]; then
        cat >&2 <<EOF
SAFETY GUARD: $TOOL_NAME blocked.

jq is not installed, and the pure-bash fallback parser could not extract
tool_input.path / tool_input.pattern from the hook payload. Failing
closed as a precaution.

Install jq to restore parse reliability: brew install jq
EOF
        exit 2
      fi
      ;;
  esac
fi

# ─── 3. Dispatch by tool name ───────────────────────────────────────────
case "$TOOL_NAME" in
  Read|NotebookRead|NotebookEdit)
    # Continue to the file-path checks below.
    ;;
  Grep)
    # Grep returns matching lines from the target path directly into
    # Claude's context. Its tool_input has TWO fields:
    #   - `pattern`  (the regex to match — NEVER a path)
    #   - `path`     (the file or directory to search; defaults to cwd
    #                 when absent per the Grep tool contract)
    #
    # IMPORTANT: an earlier version did `TARGET="${GREP_PATH:-${GLOB_PATTERN:-}}"`
    # which substituted the GREP PATTERN as the search path when `path`
    # was absent — a bypass. We must use only `path` here, and treat
    # "absent path" as "Grep will search cwd".
    TARGET=""
    if [ -n "$GREP_PATH" ]; then
      TARGET="$GREP_PATH"
    elif [ -n "$CWD" ]; then
      TARGET="$CWD"
    else
      # No path arg AND no cwd in payload — fail closed.
      cat >&2 <<EOF
SAFETY GUARD: Grep blocked.
The payload has no tool_input.path and no cwd, so we cannot determine
what Grep would actually search. Failing closed.
EOF
      exit 2
    fi

    CANON_TARGET="$(canonicalize "$TARGET")"
    if [ -z "$CANON_TARGET" ]; then
      cat >&2 <<EOF
SAFETY GUARD: Grep blocked on '$TARGET'.
Cannot safely canonicalize this target (no symlink resolver and the
path contains a symlink). Failing closed.
EOF
      exit 2
    fi
    LOWER_TARGET="$(printf '%s' "$CANON_TARGET" | tr '[:upper:]' '[:lower:]')"

    # (a) Target is/under a raw-data directory
    if is_rawdata_path "$LOWER_TARGET"; then
      cat >&2 <<EOF
SAFETY GUARD: Grep blocked on '$TARGET'.

Grep returns matching lines from the target path into Claude's context.
This target points into a raw-data directory ($CANON_TARGET), which may
contain PII, HIPAA-covered, or restricted-use content.

If you need aggregate statistics, run a Bash call with summary-only
output (e.g., 'wc -l', 'grep -c PATTERN' — count only, no row output).
See _shared/data-handling-policy.md §3 for the Bash-only pattern.
EOF
      exit 2
    fi

    # (b) Target is a scholar-init project root (contains data/raw/).
    # This is the case where Grep has no `path` argument and defaults
    # to cwd, but cwd IS the project root. Grep would then search the
    # entire project including data/raw/.
    if [ -d "$CANON_TARGET/data/raw" ] && [ -f "$CANON_TARGET/.claude/safety-status.json" ]; then
      cat >&2 <<EOF
SAFETY GUARD: Grep blocked on '$TARGET'.

This target is a scholar-init project root that contains data/raw/.
Grep with no explicit path argument (or path=<project-root>) would
search the entire project, including sensitive files in data/raw/,
and return matching lines into Claude's context.

If you need to search only non-data subdirectories (e.g., scripts/ or
drafts/), call Grep with an explicit path that excludes data/raw/:
    Grep(pattern="...", path="scripts/")
    Grep(pattern="...", path="drafts/")

Or run the search in Bash with summary-only output:
    grep -rcI --include='*.py' PATTERN scripts/ | head
EOF
      exit 2
    fi

    # (c) Direct file target with data extension
    TARGET_EXT="${LOWER_TARGET##*.}"
    if [ "$TARGET_EXT" != "$LOWER_TARGET" ] && is_data_ext "$TARGET_EXT"; then
      if [ ! -d "$CANON_TARGET" ]; then
        cat >&2 <<EOF
SAFETY GUARD: Grep blocked on '$TARGET'.

This target is a direct file with a data-file extension (.$TARGET_EXT).
Grep on a data file returns matching rows into Claude's context, which
defeats the guard. Use 'grep -c PATTERN' in a Bash call for counts, or
Read the file (which routes through the sidecar gate).

Policy: _shared/data-handling-policy.md §3
EOF
        exit 2
      fi
    fi

    exit 0
    ;;

  Glob)
    # Glob returns matching file paths into Claude's context. The tool
    # uses `pattern` as its primary input (a glob expression). Block if
    # (a) the literal prefix of the pattern is in a raw-data directory,
    # or (b) the pattern's extension is a data extension.
    if [ -z "$GLOB_PATTERN" ]; then
      # No pattern — treat as cwd classification (same as Grep no-path).
      if [ -n "$CWD" ]; then
        CANON_TARGET="$(canonicalize "$CWD")"
        if [ -n "$CANON_TARGET" ] && [ -d "$CANON_TARGET/data/raw" ] && [ -f "$CANON_TARGET/.claude/safety-status.json" ]; then
          cat >&2 <<EOF
SAFETY GUARD: Glob blocked.
No pattern provided; cwd is a scholar-init project root with data/raw/.
Glob would enumerate files across the project, including sensitive ones.
Call Glob with an explicit pattern that excludes data/raw/.
EOF
          exit 2
        fi
      fi
      exit 0
    fi

    # Extract literal prefix (chars before first glob metachar * ? [ {).
    LITERAL_PREFIX="${GLOB_PATTERN%%[*?\[\{]*}"
    if [ -n "$LITERAL_PREFIX" ]; then
      CANON_PREFIX="$(canonicalize "$LITERAL_PREFIX")"
      if [ -n "$CANON_PREFIX" ]; then
        LOWER_PREFIX="$(printf '%s' "$CANON_PREFIX" | tr '[:upper:]' '[:lower:]')"
        if is_rawdata_path "$LOWER_PREFIX"; then
          cat >&2 <<EOF
SAFETY GUARD: Glob blocked on '$GLOB_PATTERN'.

The literal prefix of this pattern points into a raw-data directory
($CANON_PREFIX). Glob would return matching file paths, giving Claude
visibility into sensitive file names and locations.

Use a Bash call with summary-only output instead:
    find data/raw -name '*.csv' | wc -l
EOF
          exit 2
        fi
      fi
    fi

    # (b) The pattern's extension is a data extension
    LOWER_PATTERN="$(printf '%s' "$GLOB_PATTERN" | tr '[:upper:]' '[:lower:]')"
    PAT_EXT="${LOWER_PATTERN##*.}"
    # Strip glob metachars from the extension to handle patterns like `*.csv*`
    PAT_EXT="${PAT_EXT%%[*?\[\{]*}"
    if [ -n "$PAT_EXT" ] && [ "$PAT_EXT" != "$LOWER_PATTERN" ] && is_data_ext "$PAT_EXT"; then
      cat >&2 <<EOF
SAFETY GUARD: Glob blocked on '$GLOB_PATTERN'.

This glob pattern matches a data-file extension (.$PAT_EXT). Enumerating
data files and returning their paths into Claude's context reveals the
structure and locations of sensitive data. Use 'find ... | wc -l' for a
count-only Bash call instead.
EOF
      exit 2
    fi

    exit 0
    ;;
  *)
    # Not a file-reading tool — pass through.
    exit 0
    ;;
esac

# ─── 4. Read / NotebookRead / NotebookEdit path checks ──────────────────
[ -n "$FILE_PATH" ] || exit 0

# Non-existent files pass through — Claude gets its own "not found" error.
[ -e "$FILE_PATH" ] || exit 0

# Keep the original (raw) path so we can try it as a sidecar key fallback
# when the canonical form doesn't match (e.g., macOS /var → /private/var).
RAW_FILE_PATH="$FILE_PATH"

# Canonicalize for scanning and path-rule checks. Fail closed if the
# canonicalizer refused (no resolver available AND target is a symlink).
CANON_PATH="$(canonicalize "$FILE_PATH")"
if [ -z "$CANON_PATH" ]; then
  cat >&2 <<EOF
SAFETY GUARD: $TOOL_NAME blocked on '$RAW_FILE_PATH'.

Cannot safely canonicalize this path — no symlink-resolving tool is
available on this system (python3, realpath, readlink -f are all
missing), and the target is a symlink whose target cannot be verified.

The I4 system-directory check depends on symlink resolution, so we
refuse rather than allow a potentially escaped symlink.

Install one of:
  python3 (recommended — already required by safety-scan.sh)
  coreutils realpath  (brew install coreutils on macOS)
  GNU coreutils readlink (Linux default)
EOF
  exit 2
fi
FILE_PATH="$CANON_PATH"

# ─── 4a. Refuse canonical paths that escape into system directories ────
# A symlink inside a scholar-init project could point to /etc/passwd,
# /dev/mem, /proc/self/environ, etc. Canonicalization above resolves
# symlinks, so we can check the REAL target. Block if it lies under any
# of these sensitive roots. This is a weak TOCTOU mitigation — it does
# not close the race between scan-time and Read-time, but it closes the
# obvious symlink-escape attack.
case "$FILE_PATH" in
  /etc|/etc/*|\
  /dev|/dev/*|\
  /proc|/proc/*|\
  /sys|/sys/*|\
  /System|/System/*|\
  /var/db|/var/db/*|\
  /var/log|/var/log/*|\
  /private/etc|/private/etc/*|\
  /private/var/db|/private/var/db/*|\
  /private/var/log|/private/var/log/*)
    cat >&2 <<EOF
SAFETY GUARD: Read blocked on '$RAW_FILE_PATH'.

The canonicalized path resolves into a system directory:
    $FILE_PATH

The guard refuses reads into /etc, /dev, /proc, /sys, /System, /var/db,
/var/log, or their /private/ aliases. If this is a symlink inside a
scholar-init project that points out of the project tree, remove or
replace the symlink — the guard does not permit the Read tool to follow
symlinks into OS-owned directories even when the file is nominally
inside the project.
EOF
    exit 2
    ;;
esac

LOWER_PATH="$(printf '%s' "$FILE_PATH" | tr '[:upper:]' '[:lower:]')"
EXT="${LOWER_PATH##*.}"
# Strip trailing whitespace that might sneak in
EXT="${EXT%%[[:space:]]*}"

# ─── 5. Extension gate: only act on data-file extensions ────────────────
IS_DATA=0
if is_data_ext "$EXT"; then
  IS_DATA=1
fi

# .json is data only in data-ish directories
if [ "$IS_DATA" = 0 ] && [ "$EXT" = "json" ]; then
  case "$LOWER_PATH" in
    */data/*|*/raw/*|*/datasets/*|*/dataset/*|*/corpus/*|*/corpora/*)
      IS_DATA=1 ;;
  esac
fi

# Text document extensions (.txt, .rtf, .docx, .doc, .odt, .md) are data
# only when they live in a data-ish directory. Policy §0 says these count
# as data when they contain interview transcripts, field notes, etc. A
# README.md at the project root is NOT data; an interview.txt in
# data/raw/ IS data.
if [ "$IS_DATA" = 0 ]; then
  for E in "${CONDITIONAL_TEXT_EXTS[@]}"; do
    if [ "$EXT" = "$E" ]; then
      case "$LOWER_PATH" in
        */data/*|*/raw/*|*/datasets/*|*/dataset/*|\
        */corpus/*|*/corpora/*|*/materials/*|\
        */interviews/*|*/transcripts/*|*/field-notes/*|*/fieldnotes/*|\
        */subjects/*|*/participants/*|*/respondents/*)
          IS_DATA=1
          ;;
      esac
      break
    fi
  done
fi

# Files with no extension in a raw-data directory are still inspected —
# attackers could save `secrets` or `dump` to bypass the extension check.
if [ "$IS_DATA" = 0 ] && is_rawdata_path "$LOWER_PATH"; then
  IS_DATA=1
fi

[ "$IS_DATA" = 1 ] || exit 0

# ─── 5b. jq availability — fail CLOSED on data files if jq is missing ──
# The sidecar check and the scan both need jq-parsed payloads and JSON
# inspection. Without jq we cannot verify either reliably, and the
# policy is "fail closed on data files" — so we refuse the Read.
if [ "$JQ_OK" = 0 ]; then
  cat >&2 <<EOF
SAFETY GUARD: Read blocked on '$FILE_PATH'.

This file appears to be a data file (extension '$EXT') but 'jq' is not
installed on this system. The data-safety guard requires jq to parse the
hook payload and consult .claude/safety-status.json reliably. Failing
closed on data files as a precaution.

Install jq and re-try:
  macOS:   brew install jq
  Linux:   apt-get install jq   (or dnf / pacman / etc.)

Non-data tool calls (code files, docs, scripts) are unaffected.
EOF
  exit 2
fi

IS_IMAGE=0
if is_image_ext "$EXT"; then
  IS_IMAGE=1
fi

# ─── 6. Honor sidecar safety-status.json ────────────────────────────────
STATUS_FILE=""
if [ -n "$CWD" ] && [ -f "${CWD}/.claude/safety-status.json" ]; then
  STATUS_FILE="${CWD}/.claude/safety-status.json"
elif [ -f ".claude/safety-status.json" ]; then
  STATUS_FILE=".claude/safety-status.json"
fi

if [ -n "$STATUS_FILE" ]; then
  # Try TWO key forms in order: the canonical (realpath-resolved) form,
  # and the raw form that came in on the tool_input. Both are full
  # absolute paths, so they're project-scoped — no cross-project collision.
  #
  # On macOS, `cd ... && pwd` in init-project.sh returns /var/folders/...
  # while the guard's python3 realpath returns /private/var/folders/...
  # The raw-path fallback handles that. Beyond those two, we do NOT fall
  # back to basename — an OVERRIDE for `foo.csv` in project A must not
  # match a different `foo.csv` in project B.
  STATUS=""
  for KEY in "$FILE_PATH" "$RAW_FILE_PATH"; do
    [ -z "$KEY" ] && continue
    LOOKUP="$(jq -r --arg fp "$KEY" '(.[$fp] // empty) | tostring' "$STATUS_FILE" 2>/dev/null || echo "")"
    if [ -n "$LOOKUP" ]; then
      STATUS="$LOOKUP"
      break
    fi
  done
  # Qualitative-OVERRIDE refusal: the policy (§4, §6) forbids OVERRIDE on
  # audio/video/transcript extensions because voiceprints are biometric
  # PII and transcripts quote participants verbatim. scholar-init
  # interactively refuses to offer OVERRIDE for these, but we also
  # enforce it HERE so the guard cannot be bypassed by a hand-edited
  # sidecar or a buggy upstream skill.
  if [ "$STATUS" = "OVERRIDE" ]; then
    case "$EXT" in
      wav|mp3|flac|m4a|ogg|aac|aiff|\
      mp4|mov|avi|mkv|webm|\
      eaf|textgrid|trs|cha|praat)
        cat >&2 <<EOF
SAFETY GUARD: Read blocked on '$FILE_PATH'.

The sidecar marks this file SAFETY_STATUS=OVERRIDE, but its extension
'.$EXT' is an audio / video / interview-transcript format. Policy §4
forbids OVERRIDE on qualitative data:

  - Audio files contain voiceprints (biometric PII)
  - Video files contain identifying faces and voices
  - Interview transcripts quote participants verbatim

There is no rationale under which this file is "safe to transmit." Only
three resolutions are valid for qualitative data:

  LOCAL_MODE  — Claude analyzes via Rscript/python3 without reading
                the file; only aggregated output enters context.
  ANONYMIZED  — run scholar-qual's presidio anonymizer first, then
                treat the ANON_ output as CLEARED.
  HALTED      — do not process this file at all.

Fix: edit ${STATUS_FILE} and change the entry for this file from
"OVERRIDE" to one of the three statuses above.
EOF
        exit 2
        ;;
    esac
  fi

  case "$STATUS" in
    CLEARED|ANONYMIZED|OVERRIDE)
      exit 0
      ;;
    LOCAL_MODE)
      cat >&2 <<EOF
SAFETY GUARD: Read blocked on '$FILE_PATH'.

This file is marked SAFETY_STATUS=LOCAL_MODE in ${STATUS_FILE}.
LOCAL_MODE forbids the Read tool on this file. Load it via a single
Rscript -e / python3 -c Bash call and emit summary-only output.

See: _shared/data-handling-policy.md §3 (LOCAL_MODE execution contract)
     _shared/data-handling-policy.md §3a/§3b (R / Python loader templates)

Do NOT retry this Read. Switch to Bash.
EOF
      exit 2
      ;;
    HALTED)
      cat >&2 <<EOF
SAFETY GUARD: Read blocked on '$FILE_PATH'.

This file is marked SAFETY_STATUS=HALTED in ${STATUS_FILE}. The user
previously declined to process it. Do not retry.
EOF
      exit 2
      ;;
    NEEDS_REVIEW*)
      LVL="${STATUS#NEEDS_REVIEW:}"
      cat >&2 <<EOF
SAFETY GUARD: Read blocked on '$FILE_PATH'.

This file was ingested by scholar-init and marked SAFETY_STATUS=${STATUS}
in ${STATUS_FILE}. The user has NOT yet reviewed the safety-scan result
(initial scan level: ${LVL}).

Before Claude is allowed to Read this file, the user must run:

  /scholar-init review

…which walks through each NEEDS_REVIEW entry interactively and replaces
it with CLEARED, LOCAL_MODE, ANONYMIZED, OVERRIDE, or HALTED.

Policy: .claude/skills/_shared/data-handling-policy.md §2 (state machine)
EOF
      exit 2
      ;;
  esac
fi

# ─── 7. Image files: path-based classification ──────────────────────────
if [ "$IS_IMAGE" = 1 ]; then
  if is_rawdata_path "$LOWER_PATH"; then
    cat >&2 <<EOF
SAFETY GUARD: Read blocked on '$FILE_PATH'.

This is an image file in a raw-data directory. safety-scan.sh cannot
inspect pixel content for faces, license plates, street signs, medical
imagery, or other identifying visuals, so image Reads from raw-data
directories are blocked by default.

If this image is a public / fully-aggregated output, add an OVERRIDE
entry to .claude/safety-status.json:
  jq --arg fp "$FILE_PATH" '. + {(\$fp): "OVERRIDE"}' \\
     .claude/safety-status.json > .claude/safety-status.json.new \\
     && mv .claude/safety-status.json.new .claude/safety-status.json

If this image contains people, documents, or private locations, DO NOT
override. Process it via a Python script that emits only aggregates:
  - Face detection → emit counts / bounding-box sizes / de-identified embeddings
  - OCR → redact detected PII, save a redacted copy, then Read the copy
  - CLIP/DINOv2/ConvNeXt → emit label counts or pooled features

Policy: .claude/skills/_shared/data-handling-policy.md §3
        scholar-compute MODULE 6 (computer vision under LOCAL_MODE)
EOF
    exit 2
  fi
  # Image outside raw-data paths (output figures, screenshots, icons) — allow.
  exit 0
fi

# ─── 8. Non-image data file: run safety-scan.sh ─────────────────────────
if [ ! -f "$GATE_SCRIPT" ]; then
  cat >&2 <<EOF
SAFETY GUARD: Read blocked on '$FILE_PATH'.

Could not locate safety-scan.sh at: $GATE_SCRIPT
The data-safety gate cannot run, so Read is failing CLOSED on data files.
EOF
  exit 2
fi

SCAN_LOG="$(mktemp -t safety-guard.XXXXXX)"
trap 'rm -f "$SCAN_LOG"' EXIT

bash "$GATE_SCRIPT" "$FILE_PATH" >"$SCAN_LOG" 2>&1
LEVEL=$?

case "$LEVEL" in
  0)
    exit 0
    ;;
  2)
    DETAIL="$(cat "$SCAN_LOG")"
    cat >&2 <<EOF
SAFETY GUARD: Read blocked on '$FILE_PATH'.

safety-scan.sh returned YELLOW (review needed).

Scanner output:
$DETAIL

Before reading this file via Read you must:
  1. Present the YELLOW finding to the user.
  2. Get an explicit choice: [Y] PROCEED / [C] LOCAL_MODE / [B] ANONYMIZE / [A] HALT.
  3. Record the decision in .claude/safety-status.json.

Policy: .claude/skills/_shared/data-handling-policy.md
EOF
    exit 2
    ;;
  *)
    DETAIL="$(cat "$SCAN_LOG")"
    cat >&2 <<EOF
SAFETY GUARD: Read blocked on '$FILE_PATH'.

safety-scan.sh returned RED (sensitive patterns detected).

Scanner output:
$DETAIL

This file appears to contain PII, HIPAA-covered, restricted-use, or other
sensitive content. Reading it via the Read tool would transmit row-level
data to the Anthropic API.

DO NOT retry this Read. Instead:

  1. Switch to LOCAL_MODE. Load the file inside a single Rscript -e
     (or python3 -c) Bash call and print only aggregated output:
     see _shared/data-handling-policy.md §3a / §3b.

  2. If this is a false positive, add an OVERRIDE entry to
     .claude/safety-status.json with a typed rationale logged verbatim
     to logs/init-report.md.

  3. To anonymize first, use scripts/gates/anonymize-presidio.py.

Policy: .claude/skills/_shared/data-handling-policy.md §0 "The core rule"
EOF
    exit 2
    ;;
esac
