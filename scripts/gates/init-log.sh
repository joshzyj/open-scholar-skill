#!/usr/bin/env bash
# Process Log Initializer — shared gate script
# Usage: bash scripts/gates/init-log.sh <skill_name> [output_root]
# Output: prints LOG_FILE=<path> to stdout (capture with eval)
# Creates the log file with header; subsequent appends use the printed path.
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: init-log.sh <skill_name> [output_root]" >&2
  echo "Example: eval \$(bash scripts/gates/init-log.sh scholar-eda)" >&2
  exit 1
fi

SKILL_NAME="$1"
OUTPUT_ROOT="${2:-${OUTPUT_ROOT:-output}}"
LOG_DATE=$(date +%Y-%m-%d)

mkdir -p "${OUTPUT_ROOT}/logs"

LOG_FILE="${OUTPUT_ROOT}/logs/process-log-${SKILL_NAME}-${LOG_DATE}.md"
if [ -f "$LOG_FILE" ]; then
  CTR=2
  while [ -f "${OUTPUT_ROOT}/logs/process-log-${SKILL_NAME}-${LOG_DATE}-${CTR}.md" ]; do
    CTR=$((CTR + 1))
  done
  LOG_FILE="${OUTPUT_ROOT}/logs/process-log-${SKILL_NAME}-${LOG_DATE}-${CTR}.md"
fi

cat > "$LOG_FILE" << LOGHEADER
# Process Log: /${SKILL_NAME}
- **Date**: ${LOG_DATE}
- **Time started**: $(date +%H:%M:%S)
- **Arguments**: (see skill invocation)
- **Working Directory**: $(pwd)

## Steps

| # | Timestamp | Step | Action | Output | Status |
|---|-----------|------|--------|--------|--------|
LOGHEADER

# Print assignment for eval capture
echo "LOG_FILE=\"${LOG_FILE}\""
