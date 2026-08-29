#!/usr/bin/env bash
# Regression test for trace-coverage-check.sh — the hard RAO-trace gate.
# Hand-built fixtures cover every verdict shape (CLAUDE.md rule 10: no single-
# project validation for a regex/parse gate).
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$REPO_ROOT/scripts/gates/trace-coverage-check.sh"
EMIT="$REPO_ROOT/scripts/gates/emit-trace.sh"
for f in "$GATE" "$EMIT"; do [ -f "$f" ] || { echo "FATAL: missing $f"; exit 1; }; done
command -v python3 >/dev/null 2>&1 || { echo "SKIP: python3 needed"; exit 0; }

FAILS=0
ok()  { echo "  ok: $1"; }
bad() { echo "  FAIL: $1"; FAILS=$((FAILS + 1)); }
TMP=$(mktemp -d "${TMPDIR:-/tmp}/tracecov.XXXXXX"); trap 'rm -rf "$TMP"' EXIT
D=$(date +%Y-%m-%d)
# Each fixture gets a UNIQUE root. (Do not use a mutated counter here: `R=$(mkroot)`
# runs in a command-substitution subshell, so a counter increment would not
# persist and every fixture would collide on the same dir.)
mkroot() { local r; r=$(mktemp -d "$TMP/rXXXXXX"); mkdir -p "$r/logs"; echo "$r"; }
# assert STATUS + exit code
expect() { # $1 label $2 want_status $3 want_rc ; rest = gate args
  local label="$1" ws="$2" wrc="$3"; shift 3
  local out rc st
  out=$(bash "$GATE" "$@" 2>&1); rc=$?
  st=$(printf '%s\n' "$out" | grep '^STATUS=' | head -1 | sed 's/STATUS=//')
  if [ "$st" = "$ws" ] && [ "$rc" = "$wrc" ]; then ok "$label -> $st (rc $rc)"
  else bad "$label -> STATUS=$st rc=$rc (want $ws / $wrc)"; fi
}

bash -n "$GATE" && ok "trace-coverage-check.sh parses" || bad "syntax error"

# valid -> GREEN / 0
R=$(mkroot); OUTPUT_ROOT="$R" bash "$EMIT" --skill scholar-eda --phase EDA --step s1 --reasoning w --action d --observation o >/dev/null
expect "valid trace" GREEN 0 "$R" --skill scholar-eda

# empty file -> RED / 1
R=$(mkroot); : > "$R/logs/trace-scholar-eda-$D.ndjson"
expect "empty trace" RED 1 "$R" --skill scholar-eda

# malformed line -> RED / 1
R=$(mkroot); printf '{bad}\n' > "$R/logs/trace-scholar-eda-$D.ndjson"
expect "malformed line" RED 1 "$R" --skill scholar-eda

# missing required fields -> RED / 1
R=$(mkroot); printf '{"ts":"x","seq":1,"skill":"scholar-eda","step":"s","reasoning":"r"}\n' > "$R/logs/trace-scholar-eda-$D.ndjson"
expect "missing fields" RED 1 "$R" --skill scholar-eda

# all-empty RAO triad -> RED / 1
R=$(mkroot); printf '{"ts":"x","seq":1,"run_id":"r","skill":"scholar-eda","phase":null,"agent":"self","agentId":null,"step":"s","reasoning":"","action":"","observation":"","refs":[],"status":"ok"}\n' > "$R/logs/trace-scholar-eda-$D.ndjson"
expect "all-empty triad" RED 1 "$R" --skill scholar-eda

# no trace (migration-safe) -> YELLOW / 2, even with a manifest present
R=$(mkroot); printf '{"agentId":"aaaaaaaaaaaaa","phase":"5.5"}\n' > "$R/logs/dispatch-manifest.jsonl"
expect "missing trace + manifest (migration)" YELLOW 2 "$R" --skill scholar-code-review

# no trace, no infra (legacy) -> YELLOW / 2
R=$(mkroot)
expect "no infra (legacy)" YELLOW 2 "$R" --skill scholar-eda

# dispatched agentId not in trace -> RED / 1
R=$(mkroot)
OUTPUT_ROOT="$R" bash "$EMIT" --skill scholar-code-review --phase 5.5 --step s --action a >/dev/null
printf '{"agentId":"missingaidxxxx","phase":"5.5","skill":"scholar-code-review","run_id":"cr-1","trace_mirror_status":"failed:emit-error"}\n' > "$R/logs/dispatch-manifest.jsonl"
expect "dispatched aid missing from trace" RED 1 "$R" --skill scholar-code-review --phase 5.5

# cross-link satisfied: trace event carries the dispatched agentId -> GREEN / 0
R=$(mkroot)
OUTPUT_ROOT="$R" bash "$EMIT" --skill scholar-code-review --phase 5.5 --agent review-code-correctness --agentId "boundaidxxxxxx" --step verdict --observation "1 crit" >/dev/null
printf '{"agentId":"boundaidxxxxxx","phase":"5.5","skill":"scholar-code-review","run_id":"cr-1","trace_mirror_status":"ok"}\n' > "$R/logs/dispatch-manifest.jsonl"
expect "cross-link satisfied" GREEN 0 "$R" --skill scholar-code-review --phase 5.5

echo ""
if [ "$FAILS" -eq 0 ]; then echo "ALL trace-coverage-check checks passed"; exit 0
else echo "$FAILS trace-coverage-check check(s) FAILED"; exit 1; fi
