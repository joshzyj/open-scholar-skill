#!/usr/bin/env bash
# test-session-transcript-html.sh — smoke tests for the HTML transcript stack:
#   scripts/gates/emit-trace.sh              (session_id stamping)
#   scripts/gates/render-trace-html.sh       (curated RAO -> HTML pipeline view)
#   scripts/gates/render-session-transcript.sh (raw session -> HTML, safety-gated)
#
# DETERMINISM
#   Every assertion below runs offline. The raw renderer's SAFETY GATE and arg
#   handling are exercised through --dry-run, which returns before the external
#   `claude-code-transcripts` binary is ever needed — so this test never
#   depends on uvx, PyPI, or the network. One final ADVISORY block does a real
#   render when the tool happens to be available; it reports but never fails
#   the suite, so an offline CI run stays green.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/../.." && pwd)"
EMIT="$REPO/scripts/gates/emit-trace.sh"
RTH="$REPO/scripts/gates/render-trace-html.sh"
RST="$REPO/scripts/gates/render-session-transcript.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); echo "  PASS: $1"; }
bad()  { FAIL=$((FAIL+1)); echo "  FAIL: $1"; }
check(){ if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$3', got '$2')"; fi; }

echo "=== T1: emit-trace.sh stamps session_id ==="
P1="$TMP/p1"; mkdir -p "$P1"
CLAUDE_CODE_SESSION_ID="sess-from-env" bash "$EMIT" --output-root "$P1" \
  --skill scholar-test --step "s1" --action "a" >/dev/null 2>&1
bash "$EMIT" --output-root "$P1" --skill scholar-test --step "s2" --action "a" \
  --session-id "sess-explicit" >/dev/null 2>&1
env -u CLAUDE_CODE_SESSION_ID -u CLAUDE_SESSION_ID bash "$EMIT" --output-root "$P1" \
  --skill scholar-test --step "s3" --action "a" >/dev/null 2>&1
T1OUT="$(python3 - "$P1" <<'PY'
import glob, json, os, sys
f = glob.glob(os.path.join(sys.argv[1], "logs", "trace-*.ndjson"))[0]
vals = [json.loads(l).get("session_id") for l in open(f)]
print("|".join("NULL" if v is None else str(v) for v in vals))
PY
)"
check "env-derived / explicit / null session_id" "$T1OUT" "sess-from-env|sess-explicit|NULL"

echo "=== T2: session_id does not break trace-coverage-check.sh ==="
TCC="$REPO/scripts/gates/trace-coverage-check.sh"
V="$(bash "$TCC" "$P1" --skill scholar-test 2>/dev/null | grep -o 'STATUS=[A-Z]*' | head -1)"
check "extra field is forward-compatible (REQ is a subset check)" "$V" "STATUS=GREEN"

echo "=== T3: render-trace.sh markdown path still renders (gate contract intact) ==="
bash "$REPO/scripts/gates/render-trace.sh" "$(ls "$P1"/logs/trace-*.ndjson | head -1)" >/dev/null 2>&1
[ -f "$P1/logs/process-log-scholar-test-$(date +%Y-%m-%d).md" ] \
  && ok "markdown view unaffected by the schema addition" \
  || bad "markdown view missing after schema addition"

echo "=== T4: render-trace-html.sh renders a pipeline view ==="
P2="$TMP/p2"; mkdir -p "$P2/tables"; : > "$P2/tables/reg.csv"
bash "$EMIT" --output-root "$P2" --skill scholar-analyze --phase "5B" --step "M1" \
  --reasoning "why" --action "feols(y ~ x)" --observation "beta=0.4, N=100" \
  --refs "tables/reg.csv" --session-id "sess-A" --status ok >/dev/null 2>&1
bash "$EMIT" --output-root "$P2" --skill scholar-analyze --phase "5C" --step "cleanroom" \
  --action "cleanroom-rerun.sh" --observation "registry diff on 2 rows" \
  --session-id "sess-A" --status fail >/dev/null 2>&1
bash "$EMIT" --output-root "$P2" --skill scholar-write --phase "7" --step "draft" \
  --agent peer-reviewer-quant --agentId "task_abc" --action "Task(...)" \
  --observation "3 findings" --session-id "sess-A" --status skipped >/dev/null 2>&1
OUT2="$(bash "$RTH" --proj "$P2" 2>/dev/null | grep -o 'STEPS=[0-9]*')"
check "merges every logs/trace-*.ndjson into one timeline" "$OUT2" "STEPS=3"
H="$P2/logs/trace-html/index.html"
[ -f "$H" ] && ok "index.html written to logs/trace-html/" || bad "index.html not written"
grep -q "cleanroom" "$H" && ok "step names rendered" || bad "step names missing"
grep -q "class='badge fail'" "$H" && ok "fail status badged" || bad "fail badge missing"
grep -q "class='badge skip'" "$H" && ok "skipped status badged" || bad "skip badge missing"
grep -q "task_abc" "$H" && ok "agentId surfaced" || bad "agentId missing"
grep -q "tables/reg.csv" "$H" && ok "artifact refs linked" || bad "artifact refs missing"

echo "=== T5: HTML view is self-contained (no network fetch) ==="
NET="$(grep -cE "(src|href)=['\"]https?://" "$H" 2>/dev/null || true)"
check "zero external src/href (offline-safe)" "${NET:-0}" "0"

echo "=== T6: HTML escaping (a trace value cannot inject markup) ==="
P3="$TMP/p3"; mkdir -p "$P3"
bash "$EMIT" --output-root "$P3" --skill scholar-test --step "xss" \
  --observation '<script>alert(1)</script> & "quoted" <b>' --status ok >/dev/null 2>&1
bash "$RTH" --proj "$P3" >/dev/null 2>&1
H3="$P3/logs/trace-html/index.html"
grep -q "&lt;script&gt;alert(1)&lt;/script&gt;" "$H3" \
  && ok "angle brackets escaped" || bad "angle brackets NOT escaped"
grep -q "<script>alert(1)</script>" "$H3" \
  && bad "raw <script> present in output" || ok "no raw script tag injected"

echo "=== T7: cross-link appears only when the transcript is actually rendered ==="
grep -q "not rendered" "$H" && ok "unrendered session shown as inert text" \
  || bad "unrendered session should not be a live link"
grep -q "class='tx' href=" "$H" && bad "live link present with no transcript on disk" \
  || ok "no live link without a rendered transcript"
mkdir -p "$P2/logs/transcript-html/sess-A"; : > "$P2/logs/transcript-html/sess-A/index.html"
bash "$RTH" --proj "$P2" >/dev/null 2>&1
grep -q "href='../transcript-html/sess-A/index.html'" "$H" \
  && ok "live deep-link appears once the transcript exists" || bad "deep-link not generated"
LINK="$(python3 - "$P2" <<'PY'
import os, re, sys
base = os.path.join(sys.argv[1], "logs", "trace-html")
h = open(os.path.join(base, "index.html")).read()
ls = set(re.findall(r"<a class='tx' href='([^']+)'", h))
print("RESOLVES" if ls and all(os.path.isfile(os.path.normpath(os.path.join(base, l))) for l in ls) else "BROKEN")
PY
)"
check "deep-link resolves on disk" "$LINK" "RESOLVES"

echo "=== T8: render-trace-html.sh error handling ==="
bash "$RTH" >/dev/null 2>&1; check "no args -> exit 1" "$?" "1"
bash "$RTH" "$TMP/nope.ndjson" >/dev/null 2>&1; check "missing trace file -> exit 1" "$?" "1"
bash "$RTH" --proj "$TMP/nodir" >/dev/null 2>&1; check "bad --proj -> exit 1" "$?" "1"
mkdir -p "$TMP/notrace/logs"; bash "$RTH" --proj "$TMP/notrace" >/dev/null 2>&1
check "--proj with no traces -> exit 1" "$?" "1"

echo "=== T9: SAFETY GATE — --gist fails closed on anything but all-CLEARED ==="
mk_proj() { local d="$1" json="$2"; mkdir -p "$d/.claude"; printf '%s' "$json" > "$d/.claude/safety-status.json"; }
FAKE="$TMP/projects"; mkdir -p "$FAKE"
# A fixture session store so target resolution succeeds without a real session.
SDIR="$FAKE/$(printf '%s' "$TMP/gp" | tr '/. ' '---')"; mkdir -p "$SDIR"
printf '{"type":"user","cwd":"%s"}\n' "$TMP/gp" > "$SDIR/sess-fix.jsonl"
export CLAUDE_PROJECTS_DIR="$FAKE"

mk_proj "$TMP/gp" '{"_meta":"CLEARED","data/raw/cfps.dta":"LOCAL_MODE"}'
bash "$RST" "$TMP/gp" --cwd "$TMP/gp" --session sess-fix --gist --dry-run >/dev/null 2>&1
check "LOCAL_MODE entry + --gist -> exit 3" "$?" "3"

mk_proj "$TMP/gp" '{"_meta":"CLEARED","x.csv":"NEEDS_REVIEW:RED"}'
bash "$RST" "$TMP/gp" --cwd "$TMP/gp" --session sess-fix --gist --dry-run >/dev/null 2>&1
check "NEEDS_REVIEW entry + --gist -> exit 3" "$?" "3"

mk_proj "$TMP/gp" 'this is not json'
bash "$RST" "$TMP/gp" --cwd "$TMP/gp" --session sess-fix --gist --dry-run >/dev/null 2>&1
check "unparseable sidecar + --gist -> exit 3 (fail closed)" "$?" "3"

NOSIDE="$TMP/nosidecar"; mkdir -p "$NOSIDE"
bash "$RST" "$NOSIDE" --cwd "$NOSIDE" --session sess-fix --gist --dry-run >/dev/null 2>&1
check "absent sidecar + --gist -> exit 3 (unknown is not CLEARED)" "$?" "3"

mk_proj "$TMP/gp" '{"_meta":"CLEARED","materials/synthetic.csv":"CLEARED"}'
G="$(bash "$RST" "$TMP/gp" --cwd "$TMP/gp" --session sess-fix --gist --dry-run 2>/dev/null | grep -o 'GIST=allowed')"
check "all-CLEARED + --gist -> allowed" "$G" "GIST=allowed"

echo "=== T10: SAFETY GATE — a local render is never blocked, only warned ==="
mk_proj "$TMP/gp" '{"_meta":"CLEARED","data/raw/cfps.dta":"LOCAL_MODE"}'
OUT10="$(bash "$RST" "$TMP/gp" --cwd "$TMP/gp" --session sess-fix --dry-run 2>/dev/null)"
RC10=$?
check "non-CLEARED local render proceeds (exit 0)" "$RC10" "0"
echo "$OUT10" | grep -q 'SAFETY_VERDICT=NON_CLEARED' && ok "verdict reported as NON_CLEARED" \
  || bad "verdict not reported"
W="$(bash "$RST" "$TMP/gp" --cwd "$TMP/gp" --session sess-fix --dry-run 2>&1 >/dev/null | grep -c 'cfps.dta')"
[ "${W:-0}" -ge 1 ] && ok "warning names the restricted entries on stderr" \
  || bad "warning did not name the restricted entries"

echo "=== T11: session discovery + arg handling ==="
L="$(bash "$RST" "$TMP/gp" --cwd "$TMP/gp" --list 2>/dev/null | grep -o 'SESSIONS_FOUND=[0-9]*')"
check "--list finds the fixture session" "$L" "SESSIONS_FOUND=1"
env -u CLAUDE_CODE_SESSION_ID -u CLAUDE_SESSION_ID bash "$RST" "$TMP/gp" --cwd "$TMP/gp" --dry-run >/dev/null 2>&1
check "no session id and no env -> exit 1" "$?" "1"
bash "$RST" "$TMP/gp" --session does-not-exist --dry-run >/dev/null 2>&1
check "unknown session id -> exit 1" "$?" "1"
bash "$RST" --bogus-flag >/dev/null 2>&1
check "unknown flag -> exit 1" "$?" "1"
LT="$(bash "$RST" "$TMP/gp" --cwd "$TMP/gp" --latest --dry-run 2>/dev/null | grep -c 'WOULD_RENDER=')"
check "--latest resolves one target" "$LT" "1"
unset CLAUDE_PROJECTS_DIR

echo "=== T12: end-to-end render loop (PATH stub — deterministic, offline) ==="
# A stub `claude-code-transcripts` lets us exercise the real render loop, the
# output layout, and the failure branches without the network or PyPI.
STUB="$TMP/bin"; mkdir -p "$STUB"
cat > "$STUB/claude-code-transcripts" <<'STUBEOF'
#!/usr/bin/env bash
# stub: mimic `claude-code-transcripts json <file> -o <dest>`
dest=""; prev=""
for a in "$@"; do [ "$prev" = "-o" ] && dest="$a"; prev="$a"; done
[ -n "$dest" ] || exit 1
mkdir -p "$dest"
[ "${STUB_NO_OUTPUT:-0}" = "1" ] && exit 0          # success but no index.html
[ "${STUB_FAIL:-0}" = "1" ] && exit 7               # renderer error
printf '<html><body>stub transcript</body></html>' > "$dest/index.html"
exit 0
STUBEOF
chmod +x "$STUB/claude-code-transcripts"
export CLAUDE_PROJECTS_DIR="$FAKE"
P12="$TMP/p12"; mkdir -p "$P12"
OUT12="$(PATH="$STUB:$PATH" bash "$RST" "$P12" --cwd "$TMP/gp" --session sess-fix 2>/dev/null)"
RC12=$?
check "render loop exits 0" "$RC12" "0"
echo "$OUT12" | grep -q "TRANSCRIPT_HTML=$P12/logs/transcript-html/sess-fix/index.html" \
  && ok "output lands at logs/transcript-html/<session-id>/index.html" \
  || bad "output path wrong: $OUT12"
[ -f "$P12/logs/transcript-html/sess-fix/index.html" ] \
  && ok "index.html exists on disk" || bad "index.html missing on disk"

echo "=== T12b: the output dir is self-ignoring ==="
GI="$P12/logs/transcript-html/.gitignore"
[ -f "$GI" ] && ok ".gitignore written into the output dir" || bad ".gitignore not written"
grep -qx '\*' "$GI" && ok ".gitignore ignores everything" || bad ".gitignore missing '*'"
grep -qx '!.gitignore' "$GI" && ok ".gitignore exempts itself" || bad ".gitignore missing '!.gitignore'"
if command -v git >/dev/null 2>&1; then
  ( cd "$P12" && git init -q . 2>/dev/null && git add -A 2>/dev/null
    if git status --porcelain 2>/dev/null | grep -q 'transcript-html/sess-fix/index.html'; then
      echo "  FAIL: rendered transcript would be staged by git add -A"
    else
      echo "  PASS: git add -A does not stage the rendered transcript"
    fi ) | tee "$TMP/git.out"
  grep -q '^  FAIL' "$TMP/git.out" && FAIL=$((FAIL+1)) || PASS=$((PASS+1))
else
  echo "  ADVISORY: git unavailable — staging check skipped"
fi

echo "=== T13: renderer failure branches ==="
P13="$TMP/p13"; mkdir -p "$P13"
STUB_FAIL=1 PATH="$STUB:$PATH" bash "$RST" "$P13" --cwd "$TMP/gp" --session sess-fix >/dev/null 2>&1
check "renderer non-zero exit -> exit 4" "$?" "4"
P14="$TMP/p14"; mkdir -p "$P14"
STUB_NO_OUTPUT=1 PATH="$STUB:$PATH" bash "$RST" "$P14" --cwd "$TMP/gp" --session sess-fix >/dev/null 2>&1
check "renderer succeeds but writes no index.html -> exit 4 (no false success)" "$?" "4"
PATH="$(printf '%s' "$PATH" | tr ':' '\n' | grep -v "^${STUB}$" | paste -sd: -)" \
  bash -c 'command -v uvx >/dev/null 2>&1' || true
unset CLAUDE_PROJECTS_DIR

echo "=== T14: missing renderer -> exit 2 (not a silent pass) ==="
export CLAUDE_PROJECTS_DIR="$FAKE"
P15="$TMP/p15"; mkdir -p "$P15"
env PATH="/usr/bin:/bin" bash "$RST" "$P15" --cwd "$TMP/gp" --session sess-fix >/dev/null 2>&1
check "no claude-code-transcripts and no uvx -> exit 2" "$?" "2"
unset CLAUDE_PROJECTS_DIR

echo ""
echo "----------------------------------------"
echo "PASSED: $PASS   FAILED: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
echo "test-session-transcript-html.sh: all assertions passed."
