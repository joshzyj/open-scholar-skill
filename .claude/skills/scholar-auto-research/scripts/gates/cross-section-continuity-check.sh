#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${1:-.}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
python3 "$SCRIPT_DIR/_section-role-helper.py" continuity "$PROJECT_DIR"
