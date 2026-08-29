#!/usr/bin/env bash
# Run all smoke tests
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
OVERALL=0

# ── Resource-locator env from .env (added 2026-08-20) ────────────────────────
# Gates that auto-detect heavy local resources fall back to filesystem scans when
# their locator var is unset. On a cloud-mounted home that fallback is not slow,
# it is effectively a hang: verify-citation-local-library.sh runs
# `find ~/Library/CloudStorage -maxdepth 4 -name zotero.sqlite`, which stalled a
# full suite run for 20+ minutes because DriveFS materializes every directory it
# walks. The repo's .env already records the right paths; the runner just never
# read it.
#
# ALLOWLIST, NOT `set -a; . .env`: .env also holds secrets (HF_TOKEN). Exporting
# those into ~270 test subprocesses is exposure this suite has no use for, so we
# lift only the path-locator keys. Existing env wins — an explicit override on
# the command line must not be clobbered by the file.
if [ -f "$REPO_ROOT/.env" ]; then
  for _k in SCHOLAR_SKILL_DIR SCHOLAR_ZOTERO_DIR SCHOLAR_BIB_PATH \
            SCHOLAR_ENDNOTE_XML SCHOLAR_KNOWLEDGE_DIR; do
    eval "_cur=\${$_k:-}"
    [ -n "$_cur" ] && continue                       # already set: leave it alone
    _v=$(grep -m1 "^${_k}=" "$REPO_ROOT/.env" 2>/dev/null | sed "s/^${_k}=//") || true
    _v=${_v%\"}; _v=${_v#\"}; _v=${_v%\'}; _v=${_v#\'}   # strip surrounding quotes
    [ -n "$_v" ] && export "$_k=$_v"
  done
  unset _k _v _cur
fi


for test_script in "$SCRIPT_DIR"/test-*.sh; do
  [ -f "$test_script" ] || continue
  echo ""
  echo "========================================"
  echo "Running: $(basename "$test_script")"
  echo "========================================"
  if bash "$test_script"; then
    echo ">>> PASSED"
  else
    echo ">>> FAILED"
    OVERALL=1
  fi
  echo ""
done

if [ "$OVERALL" -eq 0 ]; then
  echo "All smoke tests passed."
else
  echo "Some smoke tests FAILED."
  exit 1
fi
