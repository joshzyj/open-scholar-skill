#!/bin/bash
# mcp-setup.sh — register the scholar-rag MCP server with Claude Code and/or Codex.
#
# Idempotent: removes any existing `scholar-rag` entry, then re-adds it pointing
# at the venv interpreter + mcp_server.py. Also writes reference snippets to the
# store so registration can be reproduced by hand.
#
# Usage:
#   bash mcp-setup.sh                 # register with every detected host
#   bash mcp-setup.sh --claude        # Claude Code only
#   bash mcp-setup.sh --codex         # Codex only
#   bash mcp-setup.sh --print-only    # print snippets, change nothing
#   bash mcp-setup.sh --scope user    # Claude scope: local|user|project (default user)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; . "$HERE/_lib.sh"

DO_CLAUDE=0; DO_CODEX=0; PRINT_ONLY=0; SCOPE="user"; EXPLICIT=0
while [ $# -gt 0 ]; do
  case "$1" in
    --claude) DO_CLAUDE=1; EXPLICIT=1; shift;;
    --codex)  DO_CODEX=1; EXPLICIT=1; shift;;
    --print-only) PRINT_ONLY=1; shift;;
    --scope)  SCOPE="$2"; shift 2;;
    *) echo "unknown arg: $1" >&2; exit 2;;
  esac
done
if [ "$EXPLICIT" = "0" ]; then DO_CLAUDE=1; DO_CODEX=1; fi

PY="$RAG_VENV/bin/python"
SERVER="$HERE/mcp_server.py"
if [ ! -x "$PY" ]; then
  echo "ERROR: venv python not found at $PY — run setup-venv.sh first" >&2; exit 3
fi

# reference snippets ----------------------------------------------------------
mkdir -p "$SCHOLAR_RAG_DIR"
# "timeout": 120000 (ms) — P15-A (2026-08-25): without it, a hung rag call
# burns the 1800s global MCP default before the caller learns anything; a
# local vector search that has not answered in 2 minutes is not going to.
# (The server ALSO self-bounds each search at SCHOLAR_RAG_SEARCH_TIMEOUT=90s
# and returns an explicit server-timeout payload — the client timeout is the
# backstop for hangs outside the search path.)
cat > "$SCHOLAR_RAG_DIR/mcp.claude.json" <<JSON
{
  "mcpServers": {
    "scholar-rag": { "command": "$PY", "args": ["$SERVER"], "timeout": 120000 }
  }
}
JSON
cat > "$SCHOLAR_RAG_DIR/mcp.codex.toml" <<TOML
[mcp_servers.scholar-rag]
command = "$PY"
args = ["$SERVER"]
TOML

echo "== scholar-rag MCP =="
echo "  interpreter : $PY"
echo "  server      : $SERVER"
echo "  snippets    : $SCHOLAR_RAG_DIR/mcp.claude.json , mcp.codex.toml"
echo ""

if [ "$PRINT_ONLY" = "1" ]; then
  echo "--- Claude Code (.mcp.json / ~/.claude.json) ---"; cat "$SCHOLAR_RAG_DIR/mcp.claude.json"
  echo "--- Codex (~/.codex/config.toml) ---"; cat "$SCHOLAR_RAG_DIR/mcp.codex.toml"
  exit 0
fi

# Claude Code -----------------------------------------------------------------
if [ "$DO_CLAUDE" = "1" ]; then
  if command -v claude >/dev/null 2>&1; then
    claude mcp remove -s "$SCOPE" scholar-rag >/dev/null 2>&1 || true
    claude mcp add -s "$SCOPE" scholar-rag -- "$PY" "$SERVER" \
      && echo "[claude] registered (scope=$SCOPE)"
  else
    echo "[claude] CLI not found — add manually from mcp.claude.json"
  fi
fi

# Codex -----------------------------------------------------------------------
if [ "$DO_CODEX" = "1" ]; then
  if command -v codex >/dev/null 2>&1; then
    codex mcp remove scholar-rag >/dev/null 2>&1 || true
    codex mcp add scholar-rag -- "$PY" "$SERVER" \
      && echo "[codex] registered"
  else
    echo "[codex] CLI not found — add the mcp.codex.toml block to ~/.codex/config.toml"
  fi
fi

rag_trace "mcp-setup" "ok" "claude=$DO_CLAUDE codex=$DO_CODEX scope=$SCOPE"
echo ""
echo "Done. In a new Claude Code / Codex session, the tools rag_search,"
echo "rag_get_document, rag_neighbors, rag_stats will be available."
