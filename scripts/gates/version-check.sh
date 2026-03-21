#!/usr/bin/env bash
# Version Collision Avoidance Gate
# Usage: bash scripts/gates/version-check.sh <output_dir> <filename_stem>
# Example: bash scripts/gates/version-check.sh output/drafts draft-intro-redlining-2026-03-21
# Output: prints SAVE_PATH=<path>.md and BASE=<path> to stdout
# Exit 0 on success, exit 1 on bad arguments.
set -euo pipefail

if [ $# -lt 2 ]; then
  echo "Usage: version-check.sh <output_dir> <filename_stem>" >&2
  echo "Example: version-check.sh output/drafts draft-intro-slug-2026-03-21" >&2
  exit 1
fi

OUTPUT_DIR="$1"
STEM="$2"
mkdir -p "$OUTPUT_DIR"

BASE="${OUTPUT_DIR}/${STEM}"

if [ -f "${BASE}.md" ]; then
  V=2
  while [ -f "${BASE}-v${V}.md" ]; do
    V=$((V + 1))
  done
  BASE="${BASE}-v${V}"
fi

echo "SAVE_PATH=${BASE}.md"
echo "BASE=${BASE}"
