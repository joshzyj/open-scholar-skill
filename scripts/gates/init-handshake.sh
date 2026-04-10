#!/usr/bin/env bash
# init-handshake.sh — canonical implementation of the scholar-init →
# scholar-full-paper Phase -1 handshake.
#
# Detects whether the current working directory is a scholar-init project,
# validates that every file in .claude/safety-status.json has been resolved
# (no NEEDS_REVIEW entries), creates the output/<slug>/ tree directly
# (bypassing the legacy _staging step), writes an initial PROJECT STATE,
# and appends a handshake record to logs/init-report.md.
#
# This script is EXECUTED (not sourced). scholar-full-paper's Phase -1
# Step -1.0 dispatches on its exit code:
#
#   0 — handshake fired; caller should advance directly to Phase 0
#   1 — HALT: unresolved NEEDS_REVIEW entries, malformed safety-status.json,
#       or missing jq. Caller should exit the skill entirely.
#   2 — not a scholar-init project; caller should fall through to legacy
#       Phase -1 flow (creates output/_staging/...)
#
# The script is idempotent on priority 0 (reentry): if project-state.md
# already has phase entries, the handshake appends a "Re-Entry" note
# instead of clobbering accumulated state.

set -uo pipefail

# ─── 1. Detect scholar-init project context ────────────────────────────
# Requires all seven marker files/directories created by init-project.sh.
if ! { [ -f ".claude/safety-status.json" ] \
    && [ -d "data/raw" ] \
    && [ -d "data/interim" ] \
    && [ -d "data/processed" ] \
    && [ -d "materials" ] \
    && [ -d "logs" ] \
    && [ -f "logs/init-report.md" ]; }; then
  exit 2
fi

echo "✓ Detected scholar-init project context"

# ─── 2. Require jq ──────────────────────────────────────────────────────
# The safety-status check below needs jq. Fail CLOSED if it's missing.
if ! command -v jq >/dev/null 2>&1; then
  cat >&2 <<EOF
⛔ HALT — jq is required for the scholar-init handshake.

The scholar-full-paper Phase -1 handshake uses jq to verify that every
file in .claude/safety-status.json has been resolved before proceeding.
jq is not installed on this system.

Install jq:
  macOS:   brew install jq
  Linux:   apt-get install jq   (or dnf / pacman / etc.)

Then re-invoke /scholar-full-paper.
EOF
  exit 1
fi

# ─── 3. Check for unresolved NEEDS_REVIEW entries ───────────────────────
UNRESOLVED=$(jq -r '[.[] | select(type=="string" and startswith("NEEDS_REVIEW:"))] | length' .claude/safety-status.json 2>/dev/null)
if ! [[ "${UNRESOLVED:-}" =~ ^[0-9]+$ ]]; then
  cat >&2 <<EOF
⛔ HALT — could not parse .claude/safety-status.json.

jq returned a non-numeric result when counting NEEDS_REVIEW entries.
The file may be malformed or contain non-string values.

Inspect:
  jq . .claude/safety-status.json

Then re-run /scholar-init (or edit the file by hand to fix the syntax).
EOF
  exit 1
fi

if [ "$UNRESOLVED" -gt 0 ]; then
  cat >&2 <<EOF
⛔ HALT — $UNRESOLVED unresolved NEEDS_REVIEW entries.

The init-created .claude/safety-status.json contains $UNRESOLVED file(s)
that have not yet been reviewed. scholar-full-paper cannot proceed until
every ingested file has an explicit decision (CLEARED / LOCAL_MODE /
ANONYMIZED / OVERRIDE / HALTED).

Run:  /scholar-init review
…then re-invoke /scholar-full-paper.
EOF
  exit 1
fi

# ─── 4. Derive slug and create output tree ──────────────────────────────
PROJECT_SLUG="$(basename "$(pwd)")"
PROJ="output/${PROJECT_SLUG}"

mkdir -p "${PROJ}"/{drafts,logs,protocols,reports,tables,figures,scripts,citations,eda/{tables,figures},replication,presentation/figures,auto-improve}

# ─── 5. Write or append PROJECT STATE ──────────────────────────────────
STATE_FILE="${PROJ}/logs/project-state.md"

if [ -f "$STATE_FILE" ] && grep -q "^## Phase" "$STATE_FILE" 2>/dev/null; then
  # State already has phase entries — this is a re-entry. Append a note
  # instead of clobbering the accumulated phases.
  {
    printf '\n## Phase -1 — Safety Gate Re-Entry (%s)\n' "$(date '+%Y-%m-%d %H:%M')"
    printf -- '- Status: SKIPPED (already complete; scholar-init handshake previously detected)\n'
    printf -- '- Note: /scholar-full-paper re-invoked inside the same project directory; PROJECT STATE preserved.\n'
  } >> "$STATE_FILE"
  echo "✓ Phase -1 re-entry — PROJECT STATE preserved (no clobber)"
else
  # Fresh state file.
  STATUS_BREAKDOWN=$(jq -r 'to_entries | group_by(.value) | map("  - " + .[0].value + ": " + (length | tostring) + " file(s)") | .[]' .claude/safety-status.json 2>/dev/null || echo "  - (unable to parse .claude/safety-status.json)")
  cat > "$STATE_FILE" <<STATEEOF
# PROJECT STATE

- Project Slug: ${PROJECT_SLUG}
- Output Directory: ${PROJ}/
- Initialized via: scholar-init (detected at Phase -1)
- Safety status: inherited from .claude/safety-status.json

## Phase -1 — Safety Gate ($(date '+%Y-%m-%d %H:%M'))
- Status: COMPLETE (inherited)
- Method: scholar-init handshake — scan and user decisions were made during /scholar-init
- Unresolved NEEDS_REVIEW: 0
- File-level status breakdown:
${STATUS_BREAKDOWN}
- Next phase: 0
- **Lessons**: Inherited safety decisions from scholar-init. Every data file already has a CLEARED / LOCAL_MODE / ANONYMIZED / OVERRIDE / HALTED status. Sub-skills should read .claude/safety-status.json before touching any file and must not re-run the gate.
STATEEOF
fi

# ─── 6. Append handshake record to logs/init-report.md ─────────────────
cat >> logs/init-report.md <<INITEOF

## scholar-full-paper handshake — $(date '+%Y-%m-%d %H:%M')
- Pipeline invoked: scholar-full-paper
- PROJECT_SLUG: ${PROJECT_SLUG}
- Output tree: ${PROJ}/
- Phase -1 result: inherited (no re-scan)
INITEOF

# ─── 6b. Write scholar-safety-log.md inside output/<slug>/logs/ ─────────
# phase-verify.sh Phase -1 looks for any file matching *safety* in the
# project directory's logs/. Without this, a valid handshake project
# fails its own Phase -1 verifier. Write a summary that captures the
# inherited decisions — this is the phase-verify contract artifact.
#
# On re-entry, APPEND a new dated section rather than clobbering the
# prior log. The audit trail is valuable and should survive re-invocations.
SAFETY_LOG="${PROJ}/logs/scholar-safety-log.md"
if [ -f "$SAFETY_LOG" ]; then
  # Re-entry — append a new dated section, preserving prior entries.
  {
    printf '\n---\n\n'
    printf '## Re-Entry — %s\n\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')"
    printf 'scholar-full-paper re-invoked inside this project; the prior\n'
    printf 'safety log above is preserved. Current status breakdown:\n\n'
    printf '| Count | SAFETY_STATUS |\n'
    printf '|-------|---------------|\n'
    jq -r 'to_entries | group_by(.value) | map("| " + (length|tostring) + " | " + .[0].value + " |") | .[]' .claude/safety-status.json 2>/dev/null \
      || printf '| ? | (jq unavailable — see .claude/safety-status.json) |\n'
  } >> "$SAFETY_LOG"
else
  # First invocation — write the full log from scratch.
  {
    printf '# Safety Gate — Phase -1 (inherited from scholar-init)\n\n'
    printf -- '- Date: %s\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')"
    printf -- '- Pipeline: scholar-full-paper\n'
    printf -- '- Method: handshake — no re-scan performed\n'
    printf -- '- Source: .claude/safety-status.json (populated by scholar-init)\n\n'
    printf '## Files scanned and decisions\n\n'
    printf 'The following safety decisions were made by the user during\n'
    printf '`/scholar-init` and `/scholar-init review`. The PreToolUse hook\n'
    printf '(`scripts/gates/pretooluse-data-guard.sh`) enforces them on every\n'
    printf '`Read` / `NotebookRead` / `Grep` / `Glob` call.\n\n'
    printf '| Count | SAFETY_STATUS |\n'
    printf '|-------|---------------|\n'
    jq -r 'to_entries | group_by(.value) | map("| " + (length|tostring) + " | " + .[0].value + " |") | .[]' .claude/safety-status.json 2>/dev/null \
      || printf '| ? | (jq unavailable — see .claude/safety-status.json) |\n'
    printf '\n## Unresolved NEEDS_REVIEW entries\n\n'
    printf 'None (handshake verified above).\n\n'
    printf '## Full status sidecar (path-keyed)\n\n'
    printf '```json\n'
    cat .claude/safety-status.json 2>/dev/null || printf '{}\n'
    printf '\n```\n'
  } > "$SAFETY_LOG"
fi

# ─── 7. Success banner ──────────────────────────────────────────────────
echo "✓ Phase -1 complete (inherited from scholar-init)"
echo "✓ PROJECT_SLUG=${PROJECT_SLUG}"
echo "✓ Output tree: ${PROJ}/"
echo ""
echo "Proceeding directly to Phase 0. In Phase 0.POST, the rename step is a no-op."

exit 0
