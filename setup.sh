#!/usr/bin/env bash
# Scholar-Skill Setup Script
# Run once after cloning: bash setup.sh
set -uo pipefail
# NOTE: we intentionally do NOT enable `set -e`. Interactive `read -rp`
# prompts below return non-zero on EOF (non-interactive stdin, e.g.
# CI or smoke tests that pipe /dev/null). Under `set -e`, that would
# abort setup in mid-install. Instead, each step checks its own exit
# status and continues best-effort on benign failures.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

usage() {
  cat <<'USAGE'
Usage: bash setup.sh [--harness <list>]

  --harness <list>   Which AI coding harness(es) to install for: a comma-
                     separated list of  claude, codex, zcode  — or `all`, or
                     `auto` (default). `auto` installs for every harness whose
                     config dir exists (~/.claude, ~/.codex, ~/.zcode) plus the
                     one driving this session; if none is found it falls back
                     to claude. Also settable as SCHOLAR_SETUP_HARNESS.
  -h, --help         Show this help.

What gets installed is harness-specific:
  claude  skills + agents -> ~/.claude/
          PreToolUse data guard + PostToolUse redactor -> ~/.claude/settings.json
  codex   skills -> ~/.codex/skills/
          data guard: installed PER PROJECT by /scholar-init
          (<project>/.codex/config.toml), not by this script
  zcode   skills + agents -> ~/.zcode/
          PreToolUse data guard -> ~/.zcode/cli/config.json
USAGE
}

HARNESS_ARG="${SCHOLAR_SETUP_HARNESS:-auto}"
while [ $# -gt 0 ]; do
  case "$1" in
    --harness)
      if [ $# -lt 2 ]; then
        echo "setup.sh: --harness needs a value" >&2; usage >&2; exit 2
      fi
      HARNESS_ARG="$2"; shift 2 ;;
    --harness=*) HARNESS_ARG="${1#--harness=}"; shift ;;
    -h|--help)   usage; exit 0 ;;
    *) echo "setup.sh: unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

# ── Harness model ─────────────────────────────────────────────────
# Setup is HARNESS-SPECIFIC. Claude Code, Codex and ZCode each keep skills,
# agents and hook config in a different place and a different format, and none
# of them reads another's files — a Codex or ZCode host never reads
# ~/.claude/settings.json, so a Claude-only install leaves the data guard inert
# there. Every install step below dispatches on $HARNESSES.
VALID_HARNESSES="claude codex zcode"

harness_home() {
  case "$1" in
    claude) printf '%s\n' "$HOME/.claude" ;;
    codex)  printf '%s\n' "$HOME/.codex" ;;
    zcode)  printf '%s\n' "$HOME/.zcode" ;;
  esac
}

# Normalize a list ("claude, zcode" / "all") to a de-duplicated, space-
# separated list in canonical order. Returns 1 (printing nothing) on an
# unknown name or an empty result.
normalize_harnesses() {
  local spec want="" out="" tok h
  spec="$(printf '%s' "$1" | tr ',' ' ' | tr '[:upper:]' '[:lower:]')"
  for tok in $spec; do
    case "$tok" in
      all)                want="$VALID_HARNESSES" ;;
      claude|claude-code) want="$want claude" ;;
      codex)              want="$want codex" ;;
      zcode)              want="$want zcode" ;;
      *) return 1 ;;
    esac
  done
  for h in $VALID_HARNESSES; do
    case " $want " in *" $h "*) out="${out:+$out }$h" ;; esac
  done
  [ -n "$out" ] || return 1
  printf '%s\n' "$out"
}

detect_harnesses() {
  local found="" h host="unknown"
  for h in $VALID_HARNESSES; do
    [ -d "$(harness_home "$h")" ] && found="$found $h"
  done
  # The harness driving THIS session counts even before its dir exists.
  if [ -f "$SCRIPT_DIR/scripts/detect-host-agent.sh" ]; then
    host="$(bash "$SCRIPT_DIR/scripts/detect-host-agent.sh")" || host="unknown"
  fi
  case "$host" in
    claude-code) found="$found claude" ;;
    codex)       found="$found codex" ;;
  esac
  # ZCode exports ZCODE_SESSION_ID into its tool shell (seen in ZCode 3.10.2).
  # Checked here rather than in detect-host-agent.sh on purpose: that helper's
  # project-level callers (scholar-init, setup-project-claudemd.sh,
  # generate-lockdown-config.sh) only know claude-code|codex|unknown.
  [ -n "${ZCODE_SESSION_ID:-}" ] && found="$found zcode"
  # Fresh machine, nothing found: Claude Code is the historical default.
  [ -n "$found" ] || found="claude"
  normalize_harnesses "$found"
}

has_harness() {
  case " $HARNESSES " in *" $1 "*) return 0 ;; esac
  return 1
}

if [ "$HARNESS_ARG" != "auto" ]; then
  if ! HARNESSES="$(normalize_harnesses "$HARNESS_ARG")"; then
    echo "setup.sh: unrecognized --harness value: '$HARNESS_ARG'" >&2
    echo "          expected a list of: $VALID_HARNESSES (or all | auto)" >&2
    exit 2
  fi
fi

echo "═══════════════════════════════════════════════════"
echo "  Scholar-Skill Setup"
echo "═══════════════════════════════════════════════════"
echo ""

# ── 0. Select target harness(es) ──────────────────────────────────
echo "▸ Selecting target AI harness(es)..."
if [ "$HARNESS_ARG" = "auto" ]; then
  HARNESSES="$(detect_harnesses)"
  echo "  Detected: $HARNESSES"
  read -rp "  Press Enter to accept, or type a list (claude,codex,zcode | all): " user_harness
  case "${user_harness:-}" in
    ""|y|Y|yes|Yes) ;;
    *)
      if picked="$(normalize_harnesses "$user_harness")"; then
        HARNESSES="$picked"
      else
        echo "  ⚠ Unrecognized '$user_harness' — keeping the detected list"
      fi
      ;;
  esac
fi
echo "  ✓ Installing for: $HARNESSES"
echo ""

# ── 1. Create symlinks if needed ──────────────────────────────────
echo "▸ Checking symlinks..."

# Helper: repair or create a repo-local convenience symlink
# ($SCRIPT_DIR/$name → .claude/$name). Error-checks each destructive op
# so silent rm/ln failures don't leave dangling or half-created state.
repo_convenience_link() {
  local name="$1"
  local link="$SCRIPT_DIR/$name"
  local src_rel=".claude/$name"
  local src_abs="$SCRIPT_DIR/.claude/$name"
  if [ -L "$link" ]; then
    local existing
    existing="$(readlink "$link")"
    if [ "$existing" = "$src_rel" ] || [ "$existing" = "$src_abs" ]; then
      echo "  ✓ $name/ symlink exists"
      return 0
    fi
    echo "  ⚠ $name/ symlink points to $existing (expected $src_rel)"
    if ! rm "$link" 2>/dev/null; then
      echo "    ✗ Could not rm stale $name/ symlink — leaving as-is"
      return 1
    fi
    if ln -sf "$src_rel" "$link" 2>/dev/null; then
      echo "  ✓ Repaired $name/ → $src_rel"
    else
      echo "    ✗ ln -sf failed after rm — $name/ is now missing"
      return 1
    fi
  elif [ -d "$src_abs" ]; then
    if [ -e "$link" ]; then
      echo "  ✗ $name/ exists as a real directory — refusing to delete."
      echo "    Please remove or rename it manually, then re-run setup.sh."
      return 1
    fi
    if ln -sf "$src_rel" "$link" 2>/dev/null; then
      echo "  ✓ Created $name/ → $src_rel"
    else
      echo "    ✗ ln -sf failed — could not create $name/ symlink"
      return 1
    fi
  else
    echo "  ⚠ .claude/$name/ not found — skipping symlink"
  fi
}

repo_convenience_link skills
repo_convenience_link agents

echo ""

# ── 2. Auto-detect Zotero ─────────────────────────────────────────
echo "▸ Looking for Zotero library..."

ZOTERO_DIR=""
for candidate in \
  "$HOME/Zotero" \
  "$HOME/Documents/Zotero" \
  "$HOME/snap/zotero-snap/common/Zotero" \
  "$HOME/Library/CloudStorage/"*/zotero \
  "$HOME/Library/CloudStorage/"*/Zotero \
  "$HOME/Google Drive/zotero" \
  "$HOME/Google Drive/Zotero"; do
  if [ -f "$candidate/zotero.sqlite" ] 2>/dev/null || [ -f "$candidate/zotero.sqlite.bak" ] 2>/dev/null; then
    ZOTERO_DIR="$candidate"
    break
  fi
done

if [ -n "$ZOTERO_DIR" ]; then
  echo "  Auto-detected Zotero at: $ZOTERO_DIR"
  read -rp "  Use this path? [Y/n] or enter a different path: " user_zotero
  if [ -z "$user_zotero" ] || [[ "$user_zotero" =~ ^[Yy]$ ]]; then
    echo "  ✓ Using: $ZOTERO_DIR"
  elif [[ "$user_zotero" =~ ^[Nn]$ ]]; then
    ZOTERO_DIR=""
    echo "  → Skipping Zotero setup. You can set SCHOLAR_ZOTERO_DIR in .env later."
  elif [ -d "$user_zotero" ]; then
    ZOTERO_DIR="$user_zotero"
    echo "  ✓ Using: $ZOTERO_DIR"
  else
    echo "  ⚠ Directory not found: $user_zotero — keeping auto-detected path"
  fi
else
  echo "  ⚠ Zotero not auto-detected."
  read -rp "  Enter Zotero library path (or press Enter to skip): " user_zotero
  if [ -n "$user_zotero" ] && [ -d "$user_zotero" ]; then
    ZOTERO_DIR="$user_zotero"
    echo "  ✓ Using: $ZOTERO_DIR"
  else
    echo "  → Skipping Zotero setup. You can set SCHOLAR_ZOTERO_DIR in .env later."
  fi
fi

echo ""

# ── 3. Optional: BibTeX / EndNote ─────────────────────────────────
echo "▸ Optional reference managers..."

BIB_PATH=""
read -rp "  Path to a .bib file (or press Enter to skip): " user_bib
if [ -n "$user_bib" ] && [ -f "$user_bib" ]; then
  BIB_PATH="$user_bib"
  echo "  ✓ BibTeX: $BIB_PATH"
elif [ -n "$user_bib" ]; then
  echo "  ⚠ File not found: $user_bib — skipping"
fi

ENDNOTE_XML=""
read -rp "  Path to an EndNote XML export (or press Enter to skip): " user_endnote
if [ -n "$user_endnote" ] && [ -f "$user_endnote" ]; then
  ENDNOTE_XML="$user_endnote"
  echo "  ✓ EndNote XML: $ENDNOTE_XML"
elif [ -n "$user_endnote" ]; then
  echo "  ⚠ File not found: $user_endnote — skipping"
fi

CROSSREF_EMAIL=""
read -rp "  CrossRef/OpenAlex polite pool email (or press Enter to skip): " user_email
if [ -n "$user_email" ]; then
  CROSSREF_EMAIL="$user_email"
  echo "  ✓ CrossRef email: $CROSSREF_EMAIL"
fi

HF_TOKEN=""
read -rp "  HuggingFace access token (or press Enter to skip): " user_hf
if [ -n "$user_hf" ]; then
  HF_TOKEN="$user_hf"
  echo "  ✓ HuggingFace token: set"
fi

echo ""

# ── 3b. Knowledge graph directory ────────────────────────────────
echo "▸ Knowledge graph setup..."

KNOWLEDGE_DIR="${HOME}/.claude/scholar-knowledge"
read -rp "  Knowledge graph directory [$KNOWLEDGE_DIR]: " user_kg_dir
if [ -n "$user_kg_dir" ]; then
  KNOWLEDGE_DIR="$user_kg_dir"
fi
if mkdir -p "$KNOWLEDGE_DIR" 2>/dev/null; then
  echo "  ✓ Knowledge graph: $KNOWLEDGE_DIR"
else
  echo "  ⚠ Could not create $KNOWLEDGE_DIR — skipping (check permissions)"
  KNOWLEDGE_DIR=""
fi

echo ""

# ── 3c. Presidio PII detection (optional) ───────────────────────
echo "▸ Checking jq (required for PreToolUse data guard)..."
if command -v jq >/dev/null 2>&1; then
  echo "  ✓ jq found at $(command -v jq)"
else
  cat <<'JQ_MISSING'
  ⚠ jq is NOT installed.

    The PreToolUse data guard (scripts/gates/pretooluse-data-guard.sh)
    requires jq to parse Claude Code hook payloads reliably. Without it,
    the guard falls back to a minimal sed-based parser and fails CLOSED
    on data files — every Read of a .csv/.dta/.xlsx will be blocked
    with "install jq" until jq is available.

    Install jq before using this plugin:
      macOS:  brew install jq
      Linux:  apt-get install jq   (or dnf / pacman / etc.)

JQ_MISSING
fi
echo ""

echo "▸ PII detection setup..."

PRESIDIO_INSTALLED=false
if python3 -c "import presidio_analyzer" 2>/dev/null; then
  echo "  ✓ Presidio already installed"
  PRESIDIO_INSTALLED=true
else
  echo "  Presidio enables NER-based PII detection (names, addresses, entities)"
  echo "  in addition to the built-in regex patterns. Requires ~500MB disk."
  read -rp "  Install Presidio? [y/N] " install_presidio
  if [[ "${install_presidio:-N}" =~ ^[Yy] ]]; then
    echo "  Installing presidio-analyzer and spaCy model..."
    # Use `python3 -m pip` so we target the same interpreter safety-scan
    # will use at runtime. Bare `pip` on mixed systems (multiple pythons,
    # pyenv, Homebrew) can install into the wrong site-packages.
    # Install BOTH presidio-analyzer AND presidio-anonymizer. The
    # anonymization workflow (scripts/gates/anonymize-presidio.py and
    # scholar-qual's anonymizer) imports presidio_anonymizer; without it
    # `import presidio_anonymizer` fails at runtime even though a
    # `presidio_analyzer` import succeeded — the docs' promise of
    # "Presidio support" was only half-installed.
    if python3 -m pip install presidio-analyzer presidio-anonymizer spacy 2>/dev/null && \
       python3 -m spacy download en_core_web_lg 2>/dev/null; then
      echo "  ✓ Presidio installed (analyzer + anonymizer)"
      PRESIDIO_INSTALLED=true
      # Smoke-test the anonymizer import — a successful pip install is
      # not proof that the package actually imports on this interpreter.
      if python3 -c "import presidio_anonymizer" 2>/dev/null; then
        echo "  ✓ presidio_anonymizer import check passed"
      else
        echo "  ⚠ presidio_anonymizer installed but failed to import"
        echo "    Anonymization workflows may not work until this is resolved."
      fi
    else
      echo "  ⚠ Presidio installation failed — regex fallback will be used"
      echo "    To install manually: python3 -m pip install presidio-analyzer presidio-anonymizer spacy && python3 -m spacy download en_core_web_lg"
    fi
  else
    echo "  → Skipping. Regex-based detection will be used."
    echo "    To install later: python3 -m pip install presidio-analyzer presidio-anonymizer spacy && python3 -m spacy download en_core_web_lg"
  fi
fi

echo ""

# ── 4. Write .env file ───────────────────────────────────────────
echo "▸ Writing .env file..."

cat > "$ENV_FILE" << ENVEOF
# Scholar-Skill Configuration
# Generated by setup.sh on $(date +%Y-%m-%d)
# Edit paths below to match your system.

# Scholar-skill installation directory (REQUIRED for cross-project use)
SCHOLAR_SKILL_DIR="${SCRIPT_DIR}"

# Zotero library directory (containing zotero.sqlite)
SCHOLAR_ZOTERO_DIR="${ZOTERO_DIR}"

# BibTeX .bib file path (optional)
SCHOLAR_BIB_PATH="${BIB_PATH}"

# EndNote XML export path (optional)
SCHOLAR_ENDNOTE_XML="${ENDNOTE_XML}"

# CrossRef / OpenAlex polite pool email (optional but recommended)
SCHOLAR_CROSSREF_EMAIL="${CROSSREF_EMAIL}"

# HuggingFace access token (for SciThinker, gated models, etc.)
HF_TOKEN="${HF_TOKEN}"

# Knowledge graph directory (user-scoped, cross-project)
# Default: ~/.claude/scholar-knowledge
SCHOLAR_KNOWLEDGE_DIR="${KNOWLEDGE_DIR}"
ENVEOF

echo "  ✓ Wrote $ENV_FILE"
echo ""

# ── 5. Install as personal skills (global access, per harness) ───
echo "▸ Installing personal skills for: $HARNESSES"

SKILLS_SRC="$SCRIPT_DIR/.claude/skills"
AGENTS_SRC="$SCRIPT_DIR/.claude/agents"

# Per-entry install: we create one symlink per skill (and per agent)
# INSIDE the harness's existing skills/ and agents/ directories
# (~/.claude/, ~/.codex/, ~/.zcode/), rather than replacing the whole
# directory with a single symlink to this repo. That way:
#
#   1. A user who already has ~/.claude/skills/my-custom-skill/ keeps
#      that skill. scholar-* entries are installed alongside it.
#   2. setup.sh is idempotent: re-running only repairs existing links.
#   3. Uninstalling is simple — delete the scholar-* symlinks.
#
# Earlier versions aborted if ~/.claude/skills/ or ~/.claude/agents/
# existed as a real directory, which was a normal user state, and made
# fresh installs on existing users painful. This function handles all
# three target states (symlink, real dir, missing) correctly.

# Install a single symlink: $target → $src, where $src is a path inside
# this repo. Does NOT delete any existing file at $target unless it is
# already a symlink to a different location (in which case we repair).
#
# Each destructive op (rm, ln -s) is error-checked explicitly because
# setup.sh runs with `set -uo pipefail` (not `set -e`). Silent failures
# here would leave dangling symlinks or missing entries.
link_entry() {
  local target="$1" src="$2" label="$3"
  if [ -L "$target" ]; then
    local existing
    existing="$(readlink "$target")"
    if [ "$existing" = "$src" ]; then
      return 0   # already correct — silent
    else
      if ! rm "$target" 2>/dev/null; then
        echo "    ✗ $label — could not rm existing symlink at $target"
        return 1
      fi
      if ! ln -s "$src" "$target" 2>/dev/null; then
        echo "    ✗ $label — removed old symlink but could not create new one"
        return 1
      fi
      echo "    ↻ $label (repaired — was → $existing)"
    fi
  elif [ -e "$target" ]; then
    # Real file / directory at $target — do NOT delete user content.
    echo "    ⚠ $label — skipping: $target exists and is NOT a symlink"
    echo "      (the user has their own entry by that name — leaving it alone)"
    return 1
  else
    if ! ln -s "$src" "$target" 2>/dev/null; then
      echo "    ✗ $label — ln -s failed (permission or parent missing)"
      return 1
    fi
    echo "    + $label"
  fi
}

# Install every entry inside $src_dir as an individual symlink inside
# $target_dir. $target_dir is created if missing but is NEVER replaced
# wholesale — if it already exists, we add our entries alongside
# whatever is already there.
install_per_entry() {
  local src_dir="$1" target_dir="$2" label="$3" pattern="$4"
  if [ ! -d "$src_dir" ]; then
    echo "  ⚠ $src_dir not found — skipping $label install"
    return 0
  fi
  mkdir -p "$target_dir"
  if [ -L "$target_dir" ]; then
    # target_dir is a symlink — probably from an older setup.sh that
    # wholesale-linked the directory. Leave it alone; it already points
    # somewhere.
    echo "  ✓ $label (already installed as directory symlink: $target_dir)"
    return 0
  fi
  local installed=0
  local skipped=0
  # Save and restore nullglob so we don't stomp on the caller's shopt
  # state. `shopt -p nullglob` prints the exact command needed to put
  # the option back where we found it (set or unset), which we eval at
  # the end of the function.
  local prev_nullglob
  prev_nullglob="$(shopt -p nullglob)"
  shopt -s nullglob
  for entry in "$src_dir"/$pattern; do
    [ -e "$entry" ] || continue
    local name
    name="$(basename "$entry")"
    # Skip dotfiles and the _shared helper directory (it's loaded via
    # relative paths by skills, not installed as a skill itself).
    case "$name" in
      .*|_shared) continue ;;
    esac
    if link_entry "$target_dir/$name" "$entry" "$name"; then
      installed=$((installed + 1))
    else
      skipped=$((skipped + 1))
    fi
  done
  eval "$prev_nullglob"
  echo "  ✓ $label: $installed entries installed ($skipped skipped)"
}

# Count entries of $src_dir (matching $pattern) that are actually present in
# $target_dir — the source-of-truth install count, not raw directory contents.
count_available() {
  local src_dir="$1" target_dir="$2" pattern="$3" n=0 e name
  if [ -d "$src_dir" ]; then
    for e in "$src_dir"/$pattern; do
      [ -e "$e" ] || continue
      name="$(basename "$e")"
      case "$name" in .*|_shared) continue ;; esac
      [ -e "$target_dir/$name" ] && n=$((n + 1))
    done
  fi
  printf '%s\n' "$n"
}

for h in $HARNESSES; do
  h_home="$(harness_home "$h")"
  echo "  [$h] → $h_home/"
  mkdir -p "$h_home"
  install_per_entry "$SKILLS_SRC" "$h_home/skills" "skills/" "*"
  skill_count="$(count_available "$SKILLS_SRC" "$h_home/skills" "*")"
  case "$h" in
    codex)
      # Codex loads skills from ~/.codex/skills/ but has no equivalent of the
      # Claude/ZCode agents/ directory, so the agent .md files have nowhere to go.
      echo "  → agents/: skipped — Codex does not load agent files from ~/.codex/"
      echo "  → $skill_count skills available via $h_home/"
      ;;
    *)
      install_per_entry "$AGENTS_SRC" "$h_home/agents" "agents/" "*.md"
      agent_count="$(count_available "$AGENTS_SRC" "$h_home/agents" "*.md")"
      echo "  → $skill_count skills, $agent_count agents available via $h_home/"
      ;;
  esac
done
unset h h_home
echo "  → Pre-existing user skills in each skills/ directory are preserved."
echo ""

# ── 5a.7. Ensure runtime helper scripts are executable ───────────
# Gate dispatch sites guard their helpers with `[ -x "$HELPER" ]`, and
# scholar-auto-research's run_external_gate() refuses to run a gate that is not
# executable. If a mode-stripping copy (some cloud-sync mounts, download-zip
# installs) drops the +x bit, those checks silently skip or hard-RED at pipeline
# runtime. git records mode 100755 so fresh *clones* are fine, but non-git
# copies are not. Restore +x defensively here (idempotent). Globs (not `find`)
# so paths containing spaces — e.g. "My Drive" — are handled correctly.
echo "▸ Ensuring gate/phase helper scripts are executable..."
# Only scripts with a `#!` shebang are meant to be EXECUTED; sourced helpers
# (e.g. scholar-skill-bootstrap.sh, whose first line is a comment) are
# intentionally non-executable (git mode 100644) and `. sourced` — chmod-ing
# them +x would create a spurious mode change. Shebang presence is the
# git-independent signal (this runs on non-git copies too).
_chmod_fixed=0
for _s in \
  "$SCRIPT_DIR"/scripts/*.sh \
  "$SCRIPT_DIR"/scripts/gates/*.sh \
  "$SCRIPT_DIR"/scripts/gates/tests/*.sh \
  "$SCRIPT_DIR"/scripts/phases/*.sh \
  "$SCRIPT_DIR"/.claude/skills/*/scripts/*.sh \
  "$SCRIPT_DIR"/.claude/skills/*/scripts/gates/*.sh ; do
  [ -f "$_s" ] || continue          # literal (unmatched) glob -> skip
  IFS= read -r _l < "$_s" || _l=""  # first line
  case "$_l" in '#!'*) ;; *) continue ;; esac   # sourced helper (no shebang) — leave as-is
  if [ ! -x "$_s" ]; then
    chmod +x "$_s" 2>/dev/null && _chmod_fixed=$((_chmod_fixed + 1)) || true
  fi
done
unset _s _l
if [ "$_chmod_fixed" -gt 0 ]; then
  echo "  → restored +x on $_chmod_fixed executable helper script(s) that had lost it"
else
  echo "  → all executable helper scripts already +x"
fi
unset _chmod_fixed

# ── 5b. Install the data-safety hooks (harness-specific) ─────────
# Docs have always promised that setup.sh registers the data-safety hook.
# Earlier versions silently skipped this step, and later ones registered it
# for Claude Code ONLY — so a Codex or ZCode user got the skills with no guard
# behind them. Each harness now gets the hooks it can actually honor, written
# to ITS OWN config file in ITS OWN schema.
#
# Capability table. This is what each harness can enforce, not a preference:
# registering a hook the host cannot honor is a FAKE control — it shows up as
# "installed" while protecting nothing.
#
#            PreToolUse data guard             PostToolUse output redactor
#   claude   ~/.claude/settings.json           yes  (.hooks.PostToolUse)
#            .hooks.PreToolUse
#   codex    PER PROJECT, by /scholar-init →   no
#            <project>/.codex/config.toml
#   zcode    ~/.zcode/cli/config.json          no
#            .hooks.events.PreToolUse
#
# Why the redactor is Claude-only: posttooluse-output-guard.sh can only REDACT
# by returning hookSpecificOutput.updatedToolOutput, a Claude Code wire
# (verified end-to-end on Claude Code 2.1.153). Both other hosts have a
# PostToolUse event but no way to replace Bash output: the codex-cli 0.154.0
# binary carries `updatedMCPToolOutput` (MCP tools only) and no
# `updatedToolOutput`; the ZCode 3.10.2 bundle carries neither. (Checked by
# string search of the shipped binary/bundle on 2026-09-18 — not an end-to-end
# run.) There the redactor would fire, emit JSON the host ignores, and redact
# nothing. So the strict tier's output redaction does not exist on codex/zcode;
# the kernel-enforced Lockdown tier (/scholar-safety level lockdown) is the
# substitute. SCHOLAR_SETUP_POSTTOOLUSE=force registers it anyway, for testing
# a newer host build that has gained an output-rewrite wire.
#
# The merge is additive and idempotent:
#   1. Missing config file → created with a minimal hook-only config.
#   2. Existing → merged via jq, preserving every other key. Any prior entry
#      for THIS checkout's script is replaced rather than duplicated.
#   3. The file is only rewritten when the content changes, and the previous
#      version is kept as <file>.bak-<timestamp>.
#   4. No jq → explicit manual instructions, and the summary reflects it.
echo "▸ Registering data-safety hooks for: $HARNESSES"

HOOK_SCRIPT="$SCRIPT_DIR/scripts/gates/pretooluse-data-guard.sh"

# Hosts run a hook `command` as a shell line, so a bare path that contains
# SPACES (e.g. a Google Drive install: ".../My Drive/...") is split on
# whitespace and fails to execute → the hook silently FAILS OPEN and the data
# guard never runs. Wrap the (single-quoted) path in `bash '...'` so the spaces
# survive. Same footgun on Claude Code and Codex (both live-verified); ZCode's
# own config uses the same form. (Paths containing a literal single quote are
# unsupported — vanishingly rare.)
HOOK_CMD="bash '$HOOK_SCRIPT'"

# Strict-tier PostToolUse redactor (self-gates on safety level — a no-op below
# the 'strict' level, so it is safe to register unconditionally where the host
# can honor it).
PT_SCRIPT="$SCRIPT_DIR/scripts/gates/posttooluse-output-guard.sh"
PT_CMD="bash '$PT_SCRIPT'"

# Tool names differ per host. ZCode has no Notebook*/MultiEdit tools and edits
# through ApplyPatch. NOTE: the guard has no ApplyPatch branch yet, so that
# name is matched for forward-compatibility and currently passes through — the
# READ channel (Read/Grep/Glob/Bash), which is what protects data, is covered.
CLAUDE_MATCHER="Read|NotebookRead|NotebookEdit|Grep|Glob|Bash|Edit|Write|MultiEdit"
ZCODE_MATCHER="Read|Grep|Glob|Bash|Edit|Write|ApplyPatch"

if [ ! -x "$HOOK_SCRIPT" ] && [ -f "$HOOK_SCRIPT" ]; then
  chmod +x "$HOOK_SCRIPT" 2>/dev/null || true
fi
if [ -f "$PT_SCRIPT" ] && [ ! -x "$PT_SCRIPT" ]; then
  chmod +x "$PT_SCRIPT" 2>/dev/null || true
fi

# Track what actually landed, per harness: the safety hook is the single most
# important automated control this setup installs, and a summary that prints
# "Setup Complete" (exit 0) when it silently failed to register would leave the
# user unprotected while telling them they are protected.
GUARD_OK=""        # harnesses whose guard is registered by this run
GUARD_MISSING=""   # harnesses that should have one and do not
REDACTOR_OK=""     # harnesses with a working PostToolUse redactor

# merge_json_hooks <file> <flavor> <pre_matcher> <with_post:0|1>
#   flavor=claude → events at .hooks.<Event>
#   flavor=zcode  → events at .hooks.events.<Event>, plus .hooks.enabled=true
#                   and a per-hook `timeout` (seconds)
# With with_post=0 a stale redactor entry from THIS checkout is removed, so a
# re-run after an upgrade does not leave the fake control behind.
# Sets MERGE_NOTE. Returns 0 if the file is now correct, 1 otherwise.
merge_json_hooks() {
  local file="$1" flavor="$2" matcher="$3" with_post="$4"
  local tmp bak
  MERGE_NOTE=""
  if ! mkdir -p "$(dirname "$file")"; then
    MERGE_NOTE="could not create $(dirname "$file")"; return 1
  fi
  if ! tmp="$(mktemp -t scholar-hooks.XXXXXX)"; then
    MERGE_NOTE="mktemp failed"; return 1
  fi
  # A missing or zero-byte config is an empty object, not a jq error.
  if ! { if [ -s "$file" ]; then cat "$file"; else printf '{}\n'; fi; } | jq \
      --arg cmd "$HOOK_CMD" \
      --arg script "$HOOK_SCRIPT" \
      --arg ptcmd "$PT_CMD" \
      --arg ptscript "$PT_SCRIPT" \
      --arg matcher "$matcher" \
      --arg flavor "$flavor" \
      --arg withpost "$with_post" \
      '
        # Drop ANY prior entry that references this script — both the wrapped
        # form ("bash <path>") and a legacy bare-path command — so a re-run
        # leaves neither a duplicate nor a broken bare entry behind.
        def strip($s):
          map(.hooks |= ((. // []) | map(select((.command // "") | contains($s) | not))))
          | map(select((.hooks // []) | length > 0));
        def hook($c):
          {type: "command", command: $c}
          + (if $flavor == "zcode" then {timeout: 30} else {} end);
        (if $flavor == "zcode" then ["hooks", "events"] else ["hooks"] end) as $base
        | ((getpath($base + ["PreToolUse"])  // []) | strip($script))   as $pre
        | ((getpath($base + ["PostToolUse"]) // []) | strip($ptscript)) as $post
        | setpath($base + ["PreToolUse"]; $pre + [{matcher: $matcher, hooks: [hook($cmd)]}])
        | if $withpost == "1" then
            setpath($base + ["PostToolUse"]; $post + [{matcher: "Bash", hooks: [hook($ptcmd)]}])
          elif ($post | length) > 0 then
            setpath($base + ["PostToolUse"]; $post)
          else
            delpaths([$base + ["PostToolUse"]])
          end
        | if $flavor == "zcode" then .hooks.enabled = true else . end
      ' > "$tmp"; then
    rm -f "$tmp"
    MERGE_NOTE="jq merge failed — is $file valid JSON?"; return 1
  fi
  if [ ! -s "$tmp" ]; then
    rm -f "$tmp"; MERGE_NOTE="jq produced no output"; return 1
  fi
  if [ -f "$file" ] && cmp -s "$tmp" "$file"; then
    rm -f "$tmp"; MERGE_NOTE="already up to date"; return 0
  fi
  if [ -f "$file" ]; then
    bak="${file}.bak-$(date +%Y%m%d-%H%M%S)"
    if ! cp -p "$file" "$bak"; then
      rm -f "$tmp"; MERGE_NOTE="could not back up $file"; return 1
    fi
    MERGE_NOTE="merged; previous version kept as $(basename "$bak")"
  else
    MERGE_NOTE="created"
  fi
  # `cat >` rather than `mv`: keeps the file's mode, and keeps a settings file
  # that is a SYMLINK (dotfiles repo) a symlink instead of replacing it.
  if ! cat "$tmp" > "$file"; then
    rm -f "$tmp"; MERGE_NOTE="could not write $file"; return 1
  fi
  rm -f "$tmp"
  return 0
}

# A second checkout of this repo (a dev copy, a moved clone) may have its own
# guard registered. We never remove another checkout's entry — but two guards
# both run on every tool call, so say so.
warn_other_checkouts() {
  local file="$1" flavor="$2" line
  jq -r --arg s "$HOOK_SCRIPT" --arg flavor "$flavor" '
      (if $flavor == "zcode" then ["hooks", "events"] else ["hooks"] end) as $base
      | [ (getpath($base + ["PreToolUse"]) // [])[] | (.hooks // [])[] | (.command // "")
          | select(contains("/scripts/gates/pretooluse-data-guard.sh") and (contains($s) | not)) ]
      | unique | .[]
    ' "$file" | while IFS= read -r line; do
      echo "    ⚠ another checkout's data guard is also registered here:"
      echo "        $line"
      echo "      Both run on every tool call — remove the one you do not use."
    done
}

print_manual_hooks_claude() {
  cat <<HOOK_MANUAL
    Add this to $1 manually (or install jq and re-run setup.sh):

    {
      "hooks": {
        "PreToolUse": [
          {
            "matcher": "$CLAUDE_MATCHER",
            "hooks": [
              { "type": "command", "command": "$HOOK_CMD" }
            ]
          }
        ],
        "PostToolUse": [
          {
            "matcher": "Bash",
            "hooks": [
              { "type": "command", "command": "$PT_CMD" }
            ]
          }
        ]
      }
    }

HOOK_MANUAL
}

print_manual_hooks_zcode() {
  cat <<HOOK_MANUAL
    Add this to $1 manually (or install jq and re-run setup.sh):

    {
      "hooks": {
        "enabled": true,
        "events": {
          "PreToolUse": [
            {
              "matcher": "$ZCODE_MATCHER",
              "hooks": [
                { "type": "command", "command": "$HOOK_CMD", "timeout": 30 }
              ]
            }
          ]
        }
      }
    }

HOOK_MANUAL
}

# install_json_hooks <harness> <file> <flavor> <matcher> <with_post>
install_json_hooks() {
  local h="$1" file="$2" flavor="$3" matcher="$4" with_post="$5"
  if [ ! -f "$HOOK_SCRIPT" ]; then
    echo "  [$h] ⚠ Hook script not found at $HOOK_SCRIPT — cannot register"
    GUARD_MISSING="$GUARD_MISSING $h"
    return 1
  fi
  if ! command -v jq >/dev/null 2>&1; then
    echo "  [$h] ⚠ jq is not installed — cannot safely merge hooks into $file."
    "print_manual_hooks_$flavor" "$file"
    GUARD_MISSING="$GUARD_MISSING $h"
    return 1
  fi
  if ! merge_json_hooks "$file" "$flavor" "$matcher" "$with_post"; then
    echo "  [$h] ⚠ $MERGE_NOTE — $file left unchanged."
    echo "       Inspect the file and add the hook manually."
    GUARD_MISSING="$GUARD_MISSING $h"
    return 1
  fi
  GUARD_OK="$GUARD_OK $h"
  if [ "$with_post" = "1" ]; then
    echo "  [$h] ✓ PreToolUse guard + PostToolUse redactor → $file ($MERGE_NOTE)"
  else
    echo "  [$h] ✓ PreToolUse guard → $file ($MERGE_NOTE)"
  fi
  warn_other_checkouts "$file" "$flavor"
  return 0
}

FORCE_POST=0
[ "${SCHOLAR_SETUP_POSTTOOLUSE:-}" = "force" ] && FORCE_POST=1

if has_harness claude; then
  if install_json_hooks claude "$HOME/.claude/settings.json" claude "$CLAUDE_MATCHER" 1; then
    REDACTOR_OK="$REDACTOR_OK claude"
  fi
fi

if has_harness codex; then
  # Nothing is written globally for Codex, and that is deliberate: the
  # live-verified path is a PROJECT-level .codex/config.toml, which Codex
  # honors once the project is trusted. /scholar-init installs it (adapter:
  # scripts/gates/codex-pretooluse-hook.sh) whenever it initializes a project
  # under a Codex host. ~/.codex/config.toml is the user's own TOML (MCP
  # servers, profiles) and there is no safe TOML merge available here.
  echo "  [codex] → data guard is installed PER PROJECT, not by setup.sh:"
  echo "       /scholar-init writes <project>/.codex/config.toml via"
  echo "       scripts/phases/setup-codex-hooks.sh, and the hook activates once"
  echo "       you TRUST that project in Codex. Until a project is initialized"
  echo "       and trusted, nothing mechanically guards data reads under Codex."
  echo "  [codex] → PostToolUse redactor: not available (Codex cannot rewrite"
  echo "       Bash output). For restricted data use: /scholar-safety level lockdown"
fi

if has_harness zcode; then
  install_json_hooks zcode "$HOME/.zcode/cli/config.json" zcode "$ZCODE_MATCHER" "$FORCE_POST"
  if [ "$FORCE_POST" = "1" ]; then
    echo "  [zcode] ⚠ PostToolUse redactor registered because SCHOLAR_SETUP_POSTTOOLUSE=force."
    echo "       ZCode 3.10.2 has no output-rewrite wire, so treat it as INERT until"
    echo "       you have seen it redact a real command's output."
  else
    echo "  [zcode] → PostToolUse redactor: not available (ZCode cannot rewrite"
    echo "       Bash output). For restricted data use: /scholar-safety level lockdown"
  fi
fi
echo ""

# ── 6. Add SCHOLAR_SKILL_DIR to shell profile ────────────────────
echo "▸ Setting up shell environment..."

EXPORT_LINE="export SCHOLAR_SKILL_DIR=\"$SCRIPT_DIR\""
SHELL_RC=""

if [ -n "${ZSH_VERSION:-}" ] || [ "$(basename "${SHELL:-}")" = "zsh" ]; then
  SHELL_RC="$HOME/.zshrc"
elif [ -n "${BASH_VERSION:-}" ] || [ "$(basename "${SHELL:-}")" = "bash" ]; then
  SHELL_RC="$HOME/.bashrc"
  [ -f "$HOME/.bash_profile" ] && SHELL_RC="$HOME/.bash_profile"
fi

if [ -n "$SHELL_RC" ]; then
  if grep -qF "SCHOLAR_SKILL_DIR" "$SHELL_RC" 2>/dev/null; then
    echo "  ✓ SCHOLAR_SKILL_DIR already in $SHELL_RC"
  else
    read -rp "  Add SCHOLAR_SKILL_DIR to $SHELL_RC? [Y/n] " add_to_rc
    add_to_rc="${add_to_rc:-Y}"
    if [[ "$add_to_rc" =~ ^[Yy] ]]; then
      echo "" >> "$SHELL_RC"
      echo "# Scholar-Skill plugin directory" >> "$SHELL_RC"
      echo "$EXPORT_LINE" >> "$SHELL_RC"
      echo "  ✓ Added to $SHELL_RC"
      echo "  → Run: source $SHELL_RC   (or open a new terminal)"
    else
      echo "  → Skipped. Add manually if needed:"
      echo "    $EXPORT_LINE"
    fi
  fi
else
  echo "  ⚠ Could not detect shell profile. Add manually:"
  echo "    $EXPORT_LINE"
fi

echo ""

# ── 7. Summary ────────────────────────────────────────────────────
echo "═══════════════════════════════════════════════════"
if [ -z "$GUARD_MISSING" ]; then
  echo "  Setup Complete"
else
  echo "  Setup Complete (WARNING: safety hook NOT installed for:$GUARD_MISSING)"
fi
echo "═══════════════════════════════════════════════════"
echo ""
echo "  SCHOLAR_SKILL_DIR=$SCRIPT_DIR"
[ -n "$ZOTERO_DIR" ] && echo "  Zotero:     $ZOTERO_DIR"
[ -n "$BIB_PATH" ]   && echo "  BibTeX:     $BIB_PATH"
[ -n "$ENDNOTE_XML" ] && echo "  EndNote:    $ENDNOTE_XML"
echo ""
# Per-harness protection status — stated as what IS enforced, so nobody reads
# "Setup Complete" as "every harness is guarded the same way".
echo "  Data-safety status by harness:"
for h in $HARNESSES; do
  case "$h" in
    codex)
      echo "    codex   guard: per project (run /scholar-init, then trust the project) · redactor: n/a"
      ;;
    *)
      case " $GUARD_OK " in
        *" $h "*) g="installed" ;;
        *)        g="NOT INSTALLED" ;;
      esac
      case " $REDACTOR_OK " in
        *" $h "*) r="installed (active at the strict level)" ;;
        *)        r="n/a" ;;
      esac
      printf '    %-7s guard: %s · redactor: %s\n' "$h" "$g" "$r"
      ;;
  esac
done
unset h g r
echo ""
echo "  Next steps:"
echo "  1. Source your shell profile or open a new terminal"
echo "  2. RESTART each harness — hook config is read at session start"
echo "  3. Try from any project: /scholar-idea \"your research question\""
echo ""
if [ -n "$GUARD_MISSING" ]; then
  echo "  ⚠ The PreToolUse data-safety hook did NOT register for:$GUARD_MISSING"
  echo "    (see the hook section above for the reason — usually missing jq, or"
  echo "    a failed merge). Until it is installed, NOTHING mechanically prevents"
  echo "    raw data files from being read into the AI context under that"
  echo "    harness. Install jq and re-run setup.sh, or add the printed hook JSON"
  echo "    to the config file named above manually."
  exit 1
fi
