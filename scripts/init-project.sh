#!/usr/bin/env bash
# scholar-init — stand up a new research project directory and scan its
# raw data for sensitivity.
#
# Creates:
#   <dest>/<slug>/
#   ├── README.md                 ← teaches the user how the project works
#   ├── .gitignore                ← keeps raw data and safety decisions out of git
#   ├── .claude/
#   │   └── safety-status.json    ← per-file SAFETY_STATUS for the PreToolUse hook
#   ├── data/
#   │   ├── raw/                  ← copies/symlinks of ingested files
#   │   ├── interim/              ← empty, scripts write here
#   │   └── processed/            ← empty, analytic datasets
#   ├── materials/                ← codebooks, questionnaires, protocols
#   ├── output/                   ← scholar-full-paper Phase 0 populates this
#   └── logs/
#       └── init-report.md        ← permanent ingest record
#
# Usage:
#   scholar-init [options] <slug> [raw_file_or_dir ...]
#
# Options:
#   --dest <dir>        Parent directory (default: current directory)
#   --link              Symlink raw files instead of copying (default: copy)
#   --materials <path>  Treat this file/dir as materials/ not data/raw/.
#                       May be given multiple times.
#   --force             Overwrite an existing <dest>/<slug> directory
#   -h, --help          Show this help
#
# Exit codes:
#   0  success
#   1  usage error (bad slug, missing file, etc.)
#   2  project directory already exists and --force not given
#   3  safety-scan.sh could not be located

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAFETY_SCAN="${SCRIPT_DIR}/gates/safety-scan.sh"

# ─── Argument parsing ───────────────────────────────────────────────────
usage() {
  sed -n '2,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

DEST="."
LINK_MODE=0
FORCE=0
SLUG=""
MATERIALS_INPUTS=()
RAW_INPUTS=()

# Helper: validate that a valued flag has a following argument before
# dereferencing $2 (otherwise `set -u` makes the script crash with
# "unbound variable" instead of printing a clean usage error).
require_arg() {
  local flag="$1"
  if [ "$#" -lt 3 ]; then
    # $1=flag, $2=count-of-remaining-args, $3=missing → caller error
    echo "error: $flag requires an argument" >&2
    exit 1
  fi
}

while [ $# -gt 0 ]; do
  case "$1" in
    --dest)
      if [ $# -lt 2 ]; then
        echo "error: --dest requires a directory argument" >&2
        exit 1
      fi
      DEST="$2"; shift 2 ;;
    --link)       LINK_MODE=1; shift ;;
    --materials)
      if [ $# -lt 2 ]; then
        echo "error: --materials requires a file or directory argument" >&2
        exit 1
      fi
      MATERIALS_INPUTS+=("$2"); shift 2 ;;
    --force)      FORCE=1; shift ;;
    -h|--help)    usage 0 ;;
    --)           shift; break ;;
    -*)           echo "error: unknown option: $1" >&2; usage 1 ;;
    *)
      if [ -z "$SLUG" ]; then
        SLUG="$1"
      else
        RAW_INPUTS+=("$1")
      fi
      shift
      ;;
  esac
done
# Any remaining args after -- are raw inputs too
while [ $# -gt 0 ]; do RAW_INPUTS+=("$1"); shift; done

if [ -z "$SLUG" ]; then
  echo "error: project slug is required" >&2
  usage 1
fi

# ─── Validate slug ──────────────────────────────────────────────────────
# Length check first (2-64 chars), so we can give a specific error.
SLUG_LEN=${#SLUG}
if [ "$SLUG_LEN" -lt 2 ] || [ "$SLUG_LEN" -gt 64 ]; then
  echo "error: slug length must be 2-64 characters (got ${SLUG_LEN})" >&2
  exit 1
fi
# Shape check: starts with lowercase letter, alphanumeric groups joined by
# single hyphens. Rejects trailing hyphen, leading hyphen (after letter),
# double hyphens, and any non-[a-z0-9-] character.
if ! printf '%s' "$SLUG" | grep -qE '^[a-z][a-z0-9]*(-[a-z0-9]+)*$'; then
  cat >&2 <<EOF
error: invalid slug '$SLUG'

A project slug must:
  - start with a lowercase letter
  - contain only lowercase letters, digits, and hyphens
  - use hyphens only between non-empty alphanumeric groups
    (no trailing hyphen, no double hyphens, no leading hyphen)
  - be 2-64 characters long

Good:  immigrant-wage-penalty, nhanes-2017-bmi, t-deletion
Bad:   a- , my--project , -foo , UPPER
EOF
  exit 1
fi

# ─── Validate inputs ────────────────────────────────────────────────────
# Note: bash 3.2 (macOS default) throws "unbound variable" under `set -u`
# for an empty array expansion, so we use the `${arr[@]:+...}` guard.
ALL_INPUTS=()
[ ${#RAW_INPUTS[@]} -gt 0 ]       && ALL_INPUTS+=("${RAW_INPUTS[@]}")
[ ${#MATERIALS_INPUTS[@]} -gt 0 ] && ALL_INPUTS+=("${MATERIALS_INPUTS[@]}")
if [ ${#ALL_INPUTS[@]} -eq 0 ]; then
  echo "error: at least one input file or directory is required" >&2
  usage 1
fi
for f in "${ALL_INPUTS[@]}"; do
  if [ ! -e "$f" ]; then
    echo "error: input not found: $f" >&2
    exit 1
  fi
done

# ─── Locate safety-scan.sh ──────────────────────────────────────────────
if [ ! -f "$SAFETY_SCAN" ]; then
  echo "error: safety-scan.sh not found at $SAFETY_SCAN" >&2
  exit 3
fi

# ─── Resolve project directory ──────────────────────────────────────────
# Use `cd ... && pwd` to get an absolute path without requiring GNU realpath
mkdir -p "$DEST"
DEST_ABS="$(cd "$DEST" && pwd)"
PROJ_DIR="${DEST_ABS}/${SLUG}"

if [ -e "$PROJ_DIR" ]; then
  if [ "$FORCE" = 1 ]; then
    echo "▸ --force: removing existing $PROJ_DIR"
    rm -rf "$PROJ_DIR"
  else
    echo "error: $PROJ_DIR already exists. Use --force to overwrite." >&2
    exit 2
  fi
fi

# ─── Create directory tree ──────────────────────────────────────────────
echo "▸ Creating project directory: $PROJ_DIR"
mkdir -p \
  "$PROJ_DIR/data/raw" \
  "$PROJ_DIR/data/interim" \
  "$PROJ_DIR/data/processed" \
  "$PROJ_DIR/materials" \
  "$PROJ_DIR/output" \
  "$PROJ_DIR/logs" \
  "$PROJ_DIR/.claude"

# ─── Ingest files ───────────────────────────────────────────────────────
# Returns the destination basename; handles name collisions by appending
# a numeric suffix.
unique_dest() {
  local base="$1"
  local name="$(basename "$base")"
  local target_dir="$2"
  local candidate="${target_dir}/${name}"
  if [ ! -e "$candidate" ]; then
    echo "$candidate"
    return
  fi
  local stem="${name%.*}"
  local ext=""
  if [ "$stem" != "$name" ]; then
    ext=".${name##*.}"
  fi
  local n=2
  while [ -e "${target_dir}/${stem}-${n}${ext}" ]; do
    n=$((n + 1))
  done
  echo "${target_dir}/${stem}-${n}${ext}"
}

ingest_one() {
  local src="$1"
  local dest_dir="$2"
  # Strip trailing slash so `data/` doesn't become `data/.` via dirname.
  src="${src%/}"
  local src_abs
  # Canonicalize via python3 when available (handles symlinks); otherwise
  # fall back to `cd ... && pwd` (absolute but does not resolve symlinks).
  if command -v python3 >/dev/null 2>&1; then
    src_abs="$(python3 -c 'import os,sys;print(os.path.realpath(sys.argv[1]))' "$src" 2>/dev/null)"
  fi
  if [ -z "${src_abs:-}" ]; then
    src_abs="$(cd "$(dirname "$src")" && pwd)/$(basename "$src")"
  fi

  if [ -d "$src" ]; then
    # Directory → copy or symlink the whole tree
    local name="$(basename "$src")"
    local target="${dest_dir}/${name}"
    if [ -e "$target" ]; then
      target="$(unique_dest "$src" "$dest_dir")"
    fi
    if [ "$LINK_MODE" = 1 ]; then
      ln -s "$src_abs" "$target"
      # When `$target` is a symlinked directory, `find $target -type f`
      # does NOT traverse it by default (on macOS it prints the symlink
      # once without descending). Enumerate from `$src_abs` (the real
      # directory) instead. The guard canonicalizes paths on Read, so
      # user-facing `data/raw/<name>/foo.csv` resolves to the same
      # canonical path we record here.
      find "$src_abs" -type f \
        ! -name '.DS_Store' \
        ! -name 'Thumbs.db' \
        ! -path '*/.git/*' \
        ! -path '*/.Rproj.user/*' \
        ! -path '*/__pycache__/*' \
        -print0
    else
      cp -R "$src_abs" "$target"
      # Copy mode: enumerate from the in-project target since that's
      # where the files now live (independent of the source).
      find "$target" -type f \
        ! -name '.DS_Store' \
        ! -name 'Thumbs.db' \
        ! -path '*/.git/*' \
        ! -path '*/.Rproj.user/*' \
        ! -path '*/__pycache__/*' \
        -print0
    fi
    return
  fi

  # Single file
  local target
  target="$(unique_dest "$src" "$dest_dir")"
  if [ "$LINK_MODE" = 1 ]; then
    ln -s "$src_abs" "$target"
  else
    cp "$src_abs" "$target"
  fi
  printf '%s\0' "$target"
}

INGESTED_RAW=()
if [ ${#RAW_INPUTS[@]} -gt 0 ]; then
  for src in "${RAW_INPUTS[@]}"; do
    # Null-delimited so filenames with newlines don't get split.
    while IFS= read -r -d '' f; do
      INGESTED_RAW+=("$f")
    done < <(ingest_one "$src" "$PROJ_DIR/data/raw")
  done
fi

INGESTED_MATERIALS=()
if [ ${#MATERIALS_INPUTS[@]} -gt 0 ]; then
  for src in "${MATERIALS_INPUTS[@]}"; do
    while IFS= read -r -d '' f; do
      INGESTED_MATERIALS+=("$f")
    done < <(ingest_one "$src" "$PROJ_DIR/materials")
  done
fi

RAW_COUNT=${#INGESTED_RAW[@]}
MAT_COUNT=${#INGESTED_MATERIALS[@]}

# ─── Scan each ingested file ────────────────────────────────────────────
echo "▸ Running safety scan on $RAW_COUNT raw file(s) and $MAT_COUNT material(s)..."

SCAN_RESULTS=()      # one line per file: "<level>|<path>"
GREEN_COUNT=0
YELLOW_COUNT=0
RED_COUNT=0
UNKNOWN_COUNT=0      # safety-scan.sh returned an unexpected exit code (crash, SIGSEGV, missing binary)

scan_one() {
  local f="$1"
  # safety-scan returns 0=GREEN, 1=RED, 2=YELLOW. Under `set -e` we must
  # not let a non-zero exit propagate — capture it via `if` instead.
  local rc=0
  if bash "$SAFETY_SCAN" "$f" >/dev/null 2>&1; then
    rc=0
  else
    rc=$?
  fi
  local level="UNKNOWN"
  case "$rc" in
    0) level="GREEN"  ; GREEN_COUNT=$((GREEN_COUNT + 1)) ;;
    1) level="RED"    ; RED_COUNT=$((RED_COUNT + 1)) ;;
    2) level="YELLOW" ; YELLOW_COUNT=$((YELLOW_COUNT + 1)) ;;
    *) level="UNKNOWN"; UNKNOWN_COUNT=$((UNKNOWN_COUNT + 1)) ;;
  esac
  SCAN_RESULTS+=("${level}|${f}")
  # Quote the substring-removal pattern so glob chars in PROJ_DIR don't match wrong prefixes.
  echo "  [$level] ${f#"$PROJ_DIR"/}"
}

if [ ${#INGESTED_RAW[@]} -gt 0 ]; then
  for f in "${INGESTED_RAW[@]}"; do scan_one "$f"; done
fi
if [ ${#INGESTED_MATERIALS[@]} -gt 0 ]; then
  for f in "${INGESTED_MATERIALS[@]}"; do scan_one "$f"; done
fi

# ─── Build .claude/safety-status.json ───────────────────────────────────
# GREEN files → CLEARED (no user review needed — scanner says no patterns)
# YELLOW/RED  → NEEDS_REVIEW:<level> (PreToolUse hook will block until user decides)
echo "▸ Writing .claude/safety-status.json"
STATUS_JSON="$PROJ_DIR/.claude/safety-status.json"

if command -v jq >/dev/null 2>&1; then
  # Build the JSON via jq --args so paths with any control characters
  # (tabs, newlines, quotes, backslashes, unicode) are safely encoded.
  JQ_ARGS=()
  if [ ${#SCAN_RESULTS[@]} -gt 0 ]; then
    for row in "${SCAN_RESULTS[@]}"; do
      level="${row%%|*}"
      path="${row#*|}"
      case "$level" in
        GREEN)  status="CLEARED" ;;
        YELLOW) status="NEEDS_REVIEW:YELLOW" ;;
        RED)    status="NEEDS_REVIEW:RED" ;;
        *)      status="NEEDS_REVIEW:UNKNOWN" ;;
      esac
      JQ_ARGS+=("$path" "$status")
    done
  fi
  # IMPORTANT: under bash 3.2 with set -u, `"${JQ_ARGS[@]:-}"` on an empty
  # array expands to a SINGLE empty argument, which makes jq receive "" as
  # a positional arg and write `{"":null}` instead of `{}`. Guard the call
  # itself, not the expansion.
  if [ ${#JQ_ARGS[@]} -gt 0 ]; then
    jq -n --args '
      [range(0; $ARGS.positional | length; 2) as $i
        | {key: $ARGS.positional[$i], value: $ARGS.positional[$i+1]}]
      | from_entries
    ' "${JQ_ARGS[@]}" > "$STATUS_JSON"
  else
    jq -n '{}' > "$STATUS_JSON"
  fi
else
  # Fallback: prefer python3 for JSON encoding if available. Python's
  # json module handles all control chars, unicode, quotes, backslashes
  # correctly. If python3 is also missing, bail out with a clear error —
  # the hand-written fallback below cannot safely handle arbitrary paths.
  if command -v python3 >/dev/null 2>&1; then
    # Same array-safety rule as the jq branch: under bash 3.2 with set -u,
    # `"${arr[@]:-}"` on an empty array becomes a single empty string arg.
    # Pass SCAN_RESULTS only when non-empty; otherwise call python3 with no
    # data rows (it emits `{}`).
    if [ ${#SCAN_RESULTS[@]} -gt 0 ]; then
      python3 - "$STATUS_JSON" "${SCAN_RESULTS[@]}" <<'PYEOF'
import json, sys
out_path = sys.argv[1]
entries = sys.argv[2:]
status_map = {"GREEN": "CLEARED", "YELLOW": "NEEDS_REVIEW:YELLOW",
              "RED": "NEEDS_REVIEW:RED"}
result = {}
for row in entries:
    level, sep, path = row.partition("|")
    if not sep:
        continue
    result[path] = status_map.get(level, "NEEDS_REVIEW:UNKNOWN")
with open(out_path, "w", encoding="utf-8") as f:
    json.dump(result, f, indent=2, ensure_ascii=False)
    f.write("\n")
PYEOF
    else
      python3 - "$STATUS_JSON" <<'PYEOF'
import json, sys
with open(sys.argv[1], "w", encoding="utf-8") as f:
    json.dump({}, f, indent=2)
    f.write("\n")
PYEOF
    fi
  else
    echo "error: neither jq nor python3 is available — cannot write valid JSON" >&2
    exit 3
  fi
fi

# ─── Write .gitignore ───────────────────────────────────────────────────
echo "▸ Writing .gitignore"
cat > "$PROJ_DIR/.gitignore" <<'GITIGNORE'
# scholar-init default .gitignore
# -----------------------------------------------------------------------
# Keep sensitive material and per-user state out of version control.
# If you need to share raw data, do it through a proper data repository
# (ICPSR, Dataverse, OSF) with access controls — not git.

# Raw, interim, and processed data never go in git.
data/raw/
data/interim/
data/processed/

# Per-user safety decisions include OVERRIDE rationales that reference
# sensitive content by path. Do not commit them.
.claude/safety-status.json

# Output artifacts — commit these manually if you want; they are often
# large and regenerable, so git-ignored by default.
output/

# Logs are per-user and include timestamps + decisions.
logs/

# Common OS/editor noise
.DS_Store
*.swp
*~
.Rhistory
.Rproj.user/
__pycache__/
.ipynb_checkpoints/
GITIGNORE

# ─── Write logs/init-report.md ──────────────────────────────────────────
echo "▸ Writing logs/init-report.md"
INIT_REPORT="$PROJ_DIR/logs/init-report.md"
{
  echo "# Init Report — $SLUG"
  echo
  echo "- **Generated:** $(date '+%Y-%m-%d %H:%M:%S %Z')"
  echo "- **Host:** $(hostname)"
  echo "- **User:** ${USER:-unknown}"
  echo "- **Project directory:** $PROJ_DIR"
  echo "- **Ingest mode:** $([ "$LINK_MODE" = 1 ] && echo 'symlink (--link)' || echo 'copy')"
  echo
  echo "## Scan summary"
  echo
  echo "| Level    | Count |"
  echo "|----------|-------|"
  echo "| GREEN    | $GREEN_COUNT |"
  echo "| YELLOW   | $YELLOW_COUNT |"
  echo "| RED      | $RED_COUNT |"
  if [ "$UNKNOWN_COUNT" -gt 0 ]; then
    echo "| UNKNOWN* | $UNKNOWN_COUNT |"
  fi
  echo
  echo "Total: $((GREEN_COUNT + YELLOW_COUNT + RED_COUNT + UNKNOWN_COUNT)) file(s)"
  if [ "$UNKNOWN_COUNT" -gt 0 ]; then
    echo
    echo "> \*UNKNOWN = safety-scan.sh returned an unexpected exit code (crash,"
    echo "> missing binary, or signal). These files are marked NEEDS_REVIEW:UNKNOWN"
    echo "> in .claude/safety-status.json until manually investigated."
  fi
  echo
  echo "## Ingested files"
  echo
  # Column header is "Mode" (not "Source") — we emit the ingest mode
  # (copied / linked), not the source path. The destination column is
  # the path as it appears inside the project (relative to $PROJ_DIR).
  echo "| Destination | Mode | Scan level | Initial status |"
  echo "|-------------|------|------------|----------------|"
  if [ ${#SCAN_RESULTS[@]} -gt 0 ]; then
    for row in "${SCAN_RESULTS[@]}"; do
      level="${row%%|*}"
      path="${row#*|}"
      mode_word="copied"
      [ "$LINK_MODE" = 1 ] && mode_word="linked"
      # Quote the LHS of the substring removal to disable glob expansion;
      # otherwise $PROJ_DIR containing *, ?, or [ would match unintended
      # prefixes and strip wrongly.
      rel="${path#"$PROJ_DIR"/}"
      # Strip control characters (newline, tab, etc.) and escape pipes.
      # A filename with these characters would otherwise corrupt the
      # markdown table. The JSON sidecar still stores the full original
      # path unchanged, so enforcement is unaffected — only the human-
      # facing display gets sanitized.
      display_rel=$(printf '%s' "$rel" | tr -d '\000-\037' | sed 's/|/\\|/g')
      case "$level" in
        GREEN)  status="CLEARED" ;;
        YELLOW) status="NEEDS_REVIEW:YELLOW" ;;
        RED)    status="NEEDS_REVIEW:RED" ;;
        *)      status="NEEDS_REVIEW:UNKNOWN" ;;
      esac
      echo "| \`$display_rel\` | $mode_word | $level | $status |"
    done
  fi
  echo
  echo "## Source invocations"
  echo
  echo "\`\`\`"
  echo "Raw inputs: ${#RAW_INPUTS[@]}"
  if [ ${#RAW_INPUTS[@]} -gt 0 ]; then
    for s in "${RAW_INPUTS[@]}"; do echo "  - $s"; done
  fi
  echo "Materials inputs: ${#MATERIALS_INPUTS[@]}"
  if [ ${#MATERIALS_INPUTS[@]} -gt 0 ]; then
    for s in "${MATERIALS_INPUTS[@]}"; do echo "  - $s"; done
  fi
  echo "\`\`\`"
  echo
  echo "## Decision history"
  echo
  echo "_This section is appended to by \`/scholar-init review\` as the user"
  echo "upgrades NEEDS_REVIEW entries. Every OVERRIDE decision must include a"
  echo "typed rationale logged here verbatim — this is the audit record for IRB"
  echo "protocols or data use agreement review._"
  echo
} > "$INIT_REPORT"

# ─── Write README.md ────────────────────────────────────────────────────
echo "▸ Writing README.md"
cat > "$PROJ_DIR/README.md" <<'README_EOF'
# __SLUG__

Research project managed with [open-scholar-skill](https://github.com/joshzyj/open-scholar-skill).
Initialized by `scholar-init` on __DATE__.

This README was auto-generated. Feel free to edit the top (project-specific
content), but **keep the "How this project works" section intact** — it is
the operating manual for anyone (including future-you and co-authors) who
opens this directory and wonders what the conventions are.

---

## What this project is about

_Write 2–3 sentences here about your research question, the data, and the
target journal. This is the place future-you will look when you come back
to this project in three months._

- **Research question:** _fill in_
- **Data source(s):** _fill in_
- **Target journal:** _fill in_
- **Unit of analysis:** _fill in_
- **Analytic strategy:** _fill in_

---

## How this project works

### Directory layout

```
__SLUG__/
├── README.md                ← this file
├── .gitignore               ← excludes data/, output/, .claude/safety-status.json
├── .claude/
│   └── safety-status.json   ← per-file SAFETY_STATUS decisions (see below)
├── data/
│   ├── raw/                 ← original files, IMMUTABLE after init
│   ├── interim/             ← cleaned/subsetted (scripts write here)
│   └── processed/           ← analytic datasets used by models
├── materials/               ← codebooks, questionnaires, protocols
├── output/
│   └── __SLUG__/            ← scholar-full-paper Phase 0 populates this
│       ├── tables/          ← regression tables (HTML / TeX / docx)
│       ├── figures/         ← plots (PDF / PNG)
│       ├── eda/             ← scholar-eda outputs
│       ├── drafts/          ← manuscript drafts per section
│       ├── scripts/         ← numbered analysis scripts + coding log
│       ├── replication/     ← replication package build log
│       └── logs/            ← process logs per skill
└── logs/
    └── init-report.md       ← permanent ingest record + OVERRIDE rationales
```

**Golden rule:** `data/raw/` is append-only. Never edit a file in `data/raw/`
after init. Cleaned / subsetted versions go in `data/interim/`; the final
analytic dataset goes in `data/processed/`. This keeps provenance traceable.

### The data safety model (important — please read)

Open-scholar-skills ships with a **PreToolUse hook** registered globally in
`~/.claude/settings.json`. Every time Claude tries to `Read` a file in this
project (or any project), the hook runs `scripts/gates/safety-scan.sh` and
checks `.claude/safety-status.json` before the file is allowed to enter
Claude's context.

The decision flow:

```
Claude calls Read("data/raw/foo.csv")
    │
    ▼
PreToolUse hook fires
    │
    ├─ Is the extension a data extension? ──── no ──► allow
    │
    ├─ Is there an entry in .claude/safety-status.json for this file?
    │     │
    │     ├─ CLEARED / ANONYMIZED / OVERRIDE ──► allow
    │     ├─ LOCAL_MODE / HALTED           ──► block with Bash-loader hint
    │     ├─ NEEDS_REVIEW:*                ──► block, ask you to review
    │     └─ no entry                      ──► run safety-scan.sh now
    │                                            │
    │                                            ├─ GREEN  ──► allow
    │                                            ├─ YELLOW ──► block + ask
    │                                            └─ RED    ──► block hard
    │
    └─ (Image files are routed to path-based classification instead
        of content scanning — see _shared/data-handling-policy.md §3)
```

When `scholar-init` created this project, it scanned every file you ingested
and populated `.claude/safety-status.json`:

- **GREEN** files (no PII patterns detected) were auto-marked **CLEARED**.
- **YELLOW** and **RED** files were marked **NEEDS_REVIEW:** until you
  explicitly decide how to handle each one.

**Any file with NEEDS_REVIEW status cannot be read by Claude yet.** The hook
will block the Read call and tell you to review it. Run:

```
/scholar-init review
```

to walk through each unresolved file interactively. For each one you
choose:

| Choice        | Effect                                                                                                   |
|---------------|----------------------------------------------------------------------------------------------------------|
| `CLEARED`     | Read is allowed. Use for GREEN files (auto-applied by scholar-init) or YELLOW files you have confirmed are safe (e.g., a codebook with one author email). **Never use CLEARED for RED files** — they must use OVERRIDE with a typed rationale per policy §2 / §6. |
| `LOCAL_MODE`  | Read is **forbidden**. All analysis must go through `Rscript -e` / `python3 -c` Bash calls with summary-only output. Use for sensitive microdata you want to analyze locally but never transmit. |
| `ANONYMIZED`  | Run `scholar-qual`'s Presidio anonymizer first, then treat the ANON_ output as CLEARED.                  |
| `OVERRIDE`    | Read is allowed, BUT you must log a typed rationale to `logs/init-report.md`. Use when you are certain the scan is a false positive and want an audit record. |
| `HALTED`      | Block this file permanently. Use when you decide the analysis cannot proceed on this data.              |

### Adding new files after init

Option A — use the script directly:

```bash
bash /path/to/open-scholar-skill/scripts/init-project.sh \
    --dest $(dirname $(pwd)) --force __SLUG__ \
    data/raw/* path/to/new_file.csv
```

(`--force` is safe here because the script copies the existing `data/raw/`
contents back in along with the new files, then rewrites
`.claude/safety-status.json` — but you lose your prior OVERRIDE decisions.
Not recommended.)

Option B — incrementally:

```bash
cp path/to/new_file.csv data/raw/
bash /path/to/open-scholar-skill/scripts/gates/safety-scan.sh data/raw/new_file.csv
# Then edit .claude/safety-status.json and add an entry for the new file.
```

Option C — interactive:

```
/scholar-init add data/raw/new_file.csv
```

(walks through the same scan + decision flow for just the new file.)

### What to invoke next

Depending on what you ingested:

| You have              | Try                                                          |
|-----------------------|--------------------------------------------------------------|
| A codebook / questionnaire (no data yet) | `/scholar-brainstorm materials <path to codebook>` |
| A dataset you want to explore | `/scholar-eda <path to data>`                       |
| A causal research question | `/scholar-causal <treatment> -> <outcome>`         |
| A research idea to develop | `/scholar-idea <topic description>`             |
| Interview transcripts | `/scholar-qual <path to transcripts>`               |
| A text corpus / NLP task | `/scholar-compute text <corpus path>`            |
| Sociolinguistic variation / acoustic data | `/scholar-ling <module> <path>`          |

All of these will honor the `SAFETY_STATUS` for each file — LOCAL_MODE files
will be analyzed via Bash-only scripts; NEEDS_REVIEW files will be blocked
until you run `/scholar-init review`.

### Git hygiene

The auto-generated `.gitignore` excludes:

- `data/raw/`, `data/interim/`, `data/processed/` — never commit raw data
- `.claude/safety-status.json` — contains your OVERRIDE rationales, which
  reference sensitive files by path
- `output/` — large, regenerable artifacts (commit manually if you want)
- `logs/` — timestamps + decisions, per-user state

If you want to share this project with a co-author, send them:
- Everything NOT in `.gitignore` (scripts, drafts, README)
- A separate pointer to where the raw data lives (ICPSR study ID, Dataverse
  handle, OSF project, etc.) — never the data itself.

### If the safety guard is getting in your way

The guard is a hard block. If it's blocking a file you know is safe, the
two intended escape hatches are:

1. Edit `.claude/safety-status.json` directly and set the entry to
   `"CLEARED"` or `"OVERRIDE"`. Record your rationale in
   `logs/init-report.md`.
2. Run `/scholar-init review` to make the decision interactively — it will
   update the JSON and the log for you.

If you need to disable the guard temporarily (e.g., debugging), remove the
`PreToolUse` entry from `~/.claude/settings.json`. Re-add it after you're
done. Do not leave it off.

---

## Project log

_Running notes on decisions, dead ends, and surprising findings. Append to
this section as the project evolves — it's where future-you will look when
you come back and wonder "why did I drop the 2008 wave?"_

- __DATE__: Project initialized by scholar-init. See `logs/init-report.md`
  for ingest details.
README_EOF

# Now substitute __SLUG__ and __DATE__ in README.md
TODAY="$(date +%Y-%m-%d)"
# Use a different delimiter in sed to avoid slug or date interacting with /
sed -i.bak \
    -e "s|__SLUG__|${SLUG}|g" \
    -e "s|__DATE__|${TODAY}|g" \
    "$PROJ_DIR/README.md"
rm -f "$PROJ_DIR/README.md.bak"

# ─── Print summary ──────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════"
echo "  Project initialized: $SLUG"
echo "═══════════════════════════════════════════════════"
echo "  Location:  $PROJ_DIR"
echo "  Files:     $RAW_COUNT raw, $MAT_COUNT materials"
SCAN_SUMMARY="$GREEN_COUNT GREEN, $YELLOW_COUNT YELLOW, $RED_COUNT RED"
if [ "$UNKNOWN_COUNT" -gt 0 ]; then
  SCAN_SUMMARY="$SCAN_SUMMARY, $UNKNOWN_COUNT UNKNOWN"
fi
echo "  Scan:      $SCAN_SUMMARY"
echo ""
NEEDS_REVIEW_COUNT=$((YELLOW_COUNT + RED_COUNT + UNKNOWN_COUNT))
if [ "$NEEDS_REVIEW_COUNT" -gt 0 ]; then
  echo "  ⚠  $NEEDS_REVIEW_COUNT file(s) need review before Claude can Read them."
  echo "     Run:  /scholar-init review"
  echo ""
fi
echo "  Next steps:"
echo "    cd \"$PROJ_DIR\""
echo "    cat README.md          # read the operating manual"
if [ "$NEEDS_REVIEW_COUNT" -gt 0 ]; then
  echo "    /scholar-init review   # resolve NEEDS_REVIEW entries"
fi
echo "    /scholar-idea          # start with an idea, or invoke any scholar-* skill"
echo ""
