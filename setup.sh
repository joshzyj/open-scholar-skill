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

echo "═══════════════════════════════════════════════════"
echo "  Scholar-Skill Setup"
echo "═══════════════════════════════════════════════════"
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

# ── 5. Install as personal skills (global access) ────────────────
echo "▸ Installing as personal Claude Code skills..."

PERSONAL_SKILLS="$HOME/.claude/skills"
PERSONAL_AGENTS="$HOME/.claude/agents"
SKILLS_SRC="$SCRIPT_DIR/.claude/skills"
AGENTS_SRC="$SCRIPT_DIR/.claude/agents"

# Per-entry install: we create one symlink per skill (and per agent)
# INSIDE the user's existing ~/.claude/skills/ and ~/.claude/agents/
# directories, rather than replacing the whole directory with a single
# symlink to this repo. That way:
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

mkdir -p "$HOME/.claude"

install_per_entry "$SKILLS_SRC" "$PERSONAL_SKILLS" "skills/" "*"
install_per_entry "$AGENTS_SRC" "$PERSONAL_AGENTS" "agents/" "*.md"

# Count for the summary line — only count entries that actually got
# linked (the source-of-truth install count, not raw directory contents).
skill_count=0
if [ -d "$SKILLS_SRC" ]; then
  for d in "$SKILLS_SRC"/*/; do
    name="$(basename "$d")"
    [ "$name" = "_shared" ] && continue
    [ -e "$PERSONAL_SKILLS/$name" ] && skill_count=$((skill_count + 1))
  done
fi
agent_count=0
if [ -d "$AGENTS_SRC" ]; then
  for f in "$AGENTS_SRC"/*.md; do
    [ -e "$f" ] || continue
    name="$(basename "$f")"
    [ -e "$PERSONAL_AGENTS/$name" ] && agent_count=$((agent_count + 1))
  done
fi

echo "  → $skill_count skills, $agent_count agents available via ~/.claude/"
echo "  → Pre-existing user skills in ~/.claude/skills/ are preserved."
echo ""

# ── 5b. Install the PreToolUse data-safety hook ──────────────────
# Docs have always promised that setup.sh registers the data-safety hook
# in ~/.claude/settings.json. Earlier versions of setup.sh silently
# skipped this step, so fresh installs shipped without the guard.
#
# We now actually write the hook config. The approach is additive and
# idempotent:
#   1. If ~/.claude/settings.json does not exist, create it with a
#      minimal hook-only config.
#   2. If it exists, merge via jq — preserving every other key the user
#      has configured. Replace any existing PreToolUse/scholar-skill
#      entry rather than duplicating it.
#   3. If jq is unavailable, print explicit manual instructions and
#      return non-zero so the summary reflects the partial install.
echo "▸ Registering PreToolUse data-safety hook in ~/.claude/settings.json..."

HOOK_SCRIPT="$SCRIPT_DIR/scripts/gates/pretooluse-data-guard.sh"
SETTINGS_FILE="$HOME/.claude/settings.json"

if [ ! -x "$HOOK_SCRIPT" ] && [ -f "$HOOK_SCRIPT" ]; then
  chmod +x "$HOOK_SCRIPT" 2>/dev/null || true
fi

if [ ! -f "$HOOK_SCRIPT" ]; then
  echo "  ⚠ Hook script not found at $HOOK_SCRIPT — cannot register"
elif ! command -v jq >/dev/null 2>&1; then
  cat <<HOOK_MANUAL
  ⚠ jq is not installed — cannot safely merge hook into $SETTINGS_FILE.
    Add this entry manually (or install jq and re-run setup.sh):

    {
      "hooks": {
        "PreToolUse": [
          {
            "matcher": "Read|NotebookRead|NotebookEdit|Grep|Glob",
            "hooks": [
              { "type": "command", "command": "$HOOK_SCRIPT" }
            ]
          }
        ]
      }
    }

HOOK_MANUAL
else
  mkdir -p "$HOME/.claude"
  if [ ! -f "$SETTINGS_FILE" ]; then
    cat > "$SETTINGS_FILE" <<HOOKJSON
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Read|NotebookRead|NotebookEdit|Grep|Glob",
        "hooks": [
          { "type": "command", "command": "$HOOK_SCRIPT" }
        ]
      }
    ]
  }
}
HOOKJSON
    echo "  ✓ Created $SETTINGS_FILE with PreToolUse hook"
  else
    # Merge: drop any existing hook whose command matches this hook
    # script (so re-runs don't duplicate), then append a fresh entry.
    TMP_SETTINGS="$(mktemp -t scholar-settings.XXXXXX)"
    if jq \
        --arg cmd "$HOOK_SCRIPT" \
        --arg matcher "Read|NotebookRead|NotebookEdit|Grep|Glob" \
        '
          . as $orig
          | (.hooks // {}) as $hooks
          | ($hooks.PreToolUse // []) as $pretool
          | ($pretool | map(
              .hooks |= ((. // []) | map(select(.command != $cmd)))
            ) | map(select((.hooks // []) | length > 0))) as $cleaned
          | .hooks.PreToolUse = ($cleaned + [{
              "matcher": $matcher,
              "hooks": [{"type": "command", "command": $cmd}]
            }])
        ' "$SETTINGS_FILE" > "$TMP_SETTINGS" 2>/dev/null; then
      mv "$TMP_SETTINGS" "$SETTINGS_FILE"
      echo "  ✓ Merged PreToolUse hook into $SETTINGS_FILE"
    else
      rm -f "$TMP_SETTINGS"
      echo "  ⚠ jq merge failed — $SETTINGS_FILE left unchanged."
      echo "    Inspect the file and add the hook manually."
    fi
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
echo "  Setup Complete"
echo "═══════════════════════════════════════════════════"
echo ""
echo "  SCHOLAR_SKILL_DIR=$SCRIPT_DIR"
[ -n "$ZOTERO_DIR" ] && echo "  Zotero:     $ZOTERO_DIR"
[ -n "$BIB_PATH" ]   && echo "  BibTeX:     $BIB_PATH"
[ -n "$ENDNOTE_XML" ] && echo "  EndNote:    $ENDNOTE_XML"
echo ""
echo "  Next steps:"
echo "  1. Source your shell profile or open a new terminal"
echo "  2. Try from any project: /scholar-idea \"your research question\""
echo ""
