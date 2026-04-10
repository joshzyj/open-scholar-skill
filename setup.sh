#!/usr/bin/env bash
# Scholar-Skill Setup Script
# Run once after cloning: bash setup.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

echo "═══════════════════════════════════════════════════"
echo "  Scholar-Skill Setup"
echo "═══════════════════════════════════════════════════"
echo ""

# ── 1. Create symlinks if needed ──────────────────────────────────
echo "▸ Checking symlinks..."

if [ -L "$SCRIPT_DIR/skills" ]; then
  # Verify symlink points to the right target
  link_target="$(readlink "$SCRIPT_DIR/skills")"
  if [ "$link_target" = ".claude/skills" ] || [ "$link_target" = "$SCRIPT_DIR/.claude/skills" ]; then
    echo "  ✓ skills/ symlink exists"
  else
    echo "  ⚠ skills/ symlink points to $link_target (expected .claude/skills)"
    echo "    Repairing..."
    rm "$SCRIPT_DIR/skills"
    ln -sf .claude/skills "$SCRIPT_DIR/skills"
    echo "  ✓ Repaired skills/ → .claude/skills/"
  fi
elif [ -d "$SCRIPT_DIR/.claude/skills" ]; then
  if [ -e "$SCRIPT_DIR/skills" ]; then
    echo "  ✗ skills/ exists as a real directory — refusing to delete."
    echo "    Please remove or rename it manually, then re-run setup.sh."
    exit 1
  fi
  ln -sf .claude/skills "$SCRIPT_DIR/skills"
  echo "  ✓ Created skills/ → .claude/skills/"
else
  echo "  ⚠ .claude/skills/ not found — skipping symlink"
fi

if [ -L "$SCRIPT_DIR/agents" ]; then
  # Verify symlink points to the right target
  link_target="$(readlink "$SCRIPT_DIR/agents")"
  if [ "$link_target" = ".claude/agents" ] || [ "$link_target" = "$SCRIPT_DIR/.claude/agents" ]; then
    echo "  ✓ agents/ symlink exists"
  else
    echo "  ⚠ agents/ symlink points to $link_target (expected .claude/agents)"
    echo "    Repairing..."
    rm "$SCRIPT_DIR/agents"
    ln -sf .claude/agents "$SCRIPT_DIR/agents"
    echo "  ✓ Repaired agents/ → .claude/agents/"
  fi
elif [ -d "$SCRIPT_DIR/.claude/agents" ]; then
  if [ -e "$SCRIPT_DIR/agents" ]; then
    echo "  ✗ agents/ exists as a real directory — refusing to delete."
    echo "    Please remove or rename it manually, then re-run setup.sh."
    exit 1
  fi
  ln -sf .claude/agents "$SCRIPT_DIR/agents"
  echo "  ✓ Created agents/ → .claude/agents/"
else
  echo "  ⚠ .claude/agents/ not found — skipping symlink"
fi

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
mkdir -p "$KNOWLEDGE_DIR"
echo "  ✓ Knowledge graph: $KNOWLEDGE_DIR"

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
    if python3 -m pip install presidio-analyzer spacy 2>/dev/null && \
       python3 -m spacy download en_core_web_lg 2>/dev/null; then
      echo "  ✓ Presidio installed"
      PRESIDIO_INSTALLED=true
    else
      echo "  ⚠ Presidio installation failed — regex fallback will be used"
      echo "    To install manually: python3 -m pip install presidio-analyzer spacy && python3 -m spacy download en_core_web_lg"
    fi
  else
    echo "  → Skipping. Regex-based detection will be used."
    echo "    To install later: python3 -m pip install presidio-analyzer spacy && python3 -m spacy download en_core_web_lg"
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

# Helper: ensure a directory-level symlink points to the right target.
#
# SAFETY: this function NEVER recursively deletes a real (non-symlink)
# directory. Earlier versions of this script did, which could wipe a
# user's pre-existing ~/.claude/skills/ or ~/.claude/agents/ — any
# personal skills the user had installed outside this project.
#
# If $target is a real directory, we refuse to touch it and print a
# clear migration message. The user can:
#   1. Move or rename $target, then re-run setup.sh, OR
#   2. Re-run with SCHOLAR_FORCE_MIGRATE=1 if they are certain the
#      directory is safe to replace.
link_dir() {
  local target="$1" src="$2" label="$3"
  if [ -L "$target" ]; then
    existing="$(readlink "$target")"
    if [ "$existing" = "$src" ]; then
      echo "  ✓ $label (already installed)"
    else
      rm "$target"
      ln -s "$src" "$target"
      echo "  ✓ $label (repaired — was pointing to $existing)"
    fi
  elif [ -d "$target" ]; then
    # Real directory at $target — do NOT delete.
    if [ "${SCHOLAR_FORCE_MIGRATE:-0}" = "1" ]; then
      echo "  ⚠ $label — SCHOLAR_FORCE_MIGRATE=1 set, replacing real directory"
      echo "    Backup: moving $target → ${target}.bak-$(date +%Y%m%d-%H%M%S)"
      mv "$target" "${target}.bak-$(date +%Y%m%d-%H%M%S)"
      ln -s "$src" "$target"
      echo "  ✓ $label (migrated — prior contents saved to .bak-*)"
    else
      cat <<MIGRATE_MSG

  ✗ $label — cannot install: $target exists and is a REAL directory.
    This script refuses to delete unrelated user content in ~/.claude/.

    If the directory contains your OWN skills/agents that you want to
    keep, move or rename it:
        mv "$target" "${target}.my-skills"
    then re-run: bash setup.sh

    If you are SURE the directory is safe to replace (e.g., it was
    created by a previous run of this setup that left stale state),
    re-run with:
        SCHOLAR_FORCE_MIGRATE=1 bash setup.sh
    The existing directory will be renamed to ${target}.bak-<timestamp>
    before the symlink is created — nothing is rm -rf'd.

MIGRATE_MSG
      return 1
    fi
  else
    ln -s "$src" "$target"
    echo "  ✓ $label (installed)"
  fi
}

mkdir -p "$HOME/.claude"

if [ -d "$SKILLS_SRC" ]; then
  link_dir "$PERSONAL_SKILLS" "$SKILLS_SRC" "skills/"
  skill_count=$(find "$SKILLS_SRC" -maxdepth 1 -type d | wc -l)
  skill_count=$((skill_count - 1))  # subtract the directory itself
else
  echo "  ⚠ .claude/skills/ not found — skipping"
  skill_count=0
fi

if [ -d "$AGENTS_SRC" ]; then
  link_dir "$PERSONAL_AGENTS" "$AGENTS_SRC" "agents/"
  agent_count=$(find "$AGENTS_SRC" -maxdepth 1 -name '*.md' | wc -l)
else
  echo "  ⚠ .claude/agents/ not found — skipping"
  agent_count=0
fi

echo "  → $skill_count skills, $agent_count agents available via ~/.claude/"
echo "  → New skills added to the repo are automatically available in all sessions"
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
