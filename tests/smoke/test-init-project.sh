#!/usr/bin/env bash
# Smoke tests for scripts/init-project.sh
#
# Covers:
#   - Slug validation (accept/reject)
#   - Directory tree creation
#   - Copy mode (default)
#   - Symlink mode (--link)
#   - --materials routing
#   - Safety scan integration: GREEN→CLEARED, YELLOW/RED→NEEDS_REVIEW
#   - README, .gitignore, logs/init-report.md content
#   - --force overwrite behavior
#   - Integration with the PreToolUse guard (NEEDS_REVIEW blocks, CLEARED allows)

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
INIT_SCRIPT="${REPO_ROOT}/scripts/init-project.sh"
GUARD="${REPO_ROOT}/scripts/gates/pretooluse-data-guard.sh"

if [ ! -f "$INIT_SCRIPT" ]; then
  echo "FATAL: init-project.sh not found at $INIT_SCRIPT"
  exit 1
fi
if [ ! -f "$GUARD" ]; then
  echo "FATAL: pretooluse-data-guard.sh not found at $GUARD"
  exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not installed — init tests require jq"
  exit 0
fi

TMPDIR_BASE="$(mktemp -d -t init-smoke.XXXXXX)"
cleanup() { rm -rf "$TMPDIR_BASE" 2>/dev/null || true; }
trap cleanup EXIT

PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

# Helper: make a known-RED file (contains SSN)
make_red_csv() {
  cat > "$1" <<'CSV'
patient_id,first_name,ssn,diagnosis
1,Alice,111-22-3333,hypertension
CSV
}

# Helper: make a known-GREEN file (public aggregated data)
make_green_csv() {
  cat > "$1" <<'CSV'
year,country,gdp
2020,USA,21000000
2020,CHN,14700000
CSV
}

# Helper: make a known-YELLOW file. An email address reliably triggers
# safety-scan.sh's YELLOW threshold (line 91 of safety-scan.sh) without
# hitting any RED conditions.
make_yellow_md() {
  cat > "$1" <<'MD'
# Codebook

Contact: researcher@example.edu for dataset access.

- var1: first variable
- var2: second variable
MD
}

# Helper: simulate a PreToolUse Read payload
payload() {
  local tool="$1" fp="$2" cwd="$3"
  jq -n --arg tn "$tool" --arg fp "$fp" --arg cwd "$cwd" \
    '{session_id:"t", transcript_path:"", cwd:$cwd, hook_event_name:"PreToolUse", tool_name:$tn, tool_input:{file_path:$fp}}'
}

echo "=== init-project.sh Smoke Tests ==="
echo "Script: $INIT_SCRIPT"
echo ""

# ─── Test 1: Reject bad slug ────────────────────────────────────────────
echo "Test 1: Bad slugs are rejected, good slugs accepted"
# ── Rejections ──
reject_slug() {
  local slug="$1"; local reason="$2"
  if bash "$INIT_SCRIPT" --dest "$TMPDIR_BASE/t1" "$slug" 2>/dev/null; then
    fail "Accepted slug '$slug' ($reason)"
  else
    pass "Rejected '$slug' — $reason"
  fi
}
reject_slug "Bad Slug With Spaces" "has spaces"
reject_slug "1-starts-with-digit"  "starts with digit"
reject_slug "UPPERCASE"            "uppercase"
reject_slug "a-"                   "trailing hyphen"
reject_slug "my--project"          "double hyphen"
reject_slug "-bad"                 "leading hyphen"
reject_slug "a---"                 "multiple trailing hyphens"
reject_slug "a"                    "length < 2"
reject_slug "$(printf 'a%.0s' $(seq 1 65))" "length > 64"
reject_slug "has_underscore"       "contains underscore"
reject_slug "has.dot"              "contains dot"

# ── Accepted good slugs (the old regex accepted these too, verify we didn't over-tighten) ──
accept_slug() {
  local slug="$1"
  local destdir="$TMPDIR_BASE/t1/accept-$$-${RANDOM}"
  mkdir -p "$destdir"
  echo "a" > "$destdir/ok.csv"
  if bash "$INIT_SCRIPT" --dest "$destdir" "$slug" "$destdir/ok.csv" >/dev/null 2>&1; then
    pass "Accepted '$slug'"
  else
    fail "Rejected valid slug '$slug'"
  fi
}
accept_slug "ab"
accept_slug "a-b"
accept_slug "nhanes-2017-bmi"
accept_slug "immigrant-wage-penalty"
accept_slug "t-deletion"

# ─── Test 2: Accept good slug, create tree ──────────────────────────────
echo ""
echo "Test 2: Valid slug creates the standard tree"
T2="$TMPDIR_BASE/t2"
mkdir -p "$T2"
make_green_csv "$T2/public.csv"

bash "$INIT_SCRIPT" --dest "$T2" my-project "$T2/public.csv" >"$TMPDIR_BASE/t2.log" 2>&1
if [ $? -ne 0 ]; then
  fail "init script exited non-zero"
  sed 's/^/    /' "$TMPDIR_BASE/t2.log"
else
  pass "init script exited cleanly"
fi

PROJ="$T2/my-project"
for dir in data/raw data/interim data/processed materials output .claude logs; do
  if [ -d "$PROJ/$dir" ]; then
    pass "created $dir"
  else
    fail "missing $dir"
  fi
done

for f in README.md .gitignore .claude/safety-status.json logs/init-report.md; do
  if [ -f "$PROJ/$f" ]; then
    pass "created $f"
  else
    fail "missing $f"
  fi
done

# ─── Test 3: GREEN file → CLEARED in safety-status.json ────────────────
echo ""
echo "Test 3: GREEN file is written as CLEARED"
PROJ="$T2/my-project"
STATUS=$(jq -r --arg fp "$PROJ/data/raw/public.csv" '.[$fp]' "$PROJ/.claude/safety-status.json")
if [ "$STATUS" = "CLEARED" ]; then
  pass "GREEN → CLEARED"
else
  fail "expected CLEARED, got: $STATUS"
fi

# ─── Test 4: RED file → NEEDS_REVIEW:RED ────────────────────────────────
echo ""
echo "Test 4: RED file is written as NEEDS_REVIEW:RED"
T4="$TMPDIR_BASE/t4"
mkdir -p "$T4"
make_red_csv "$T4/patients.csv"
bash "$INIT_SCRIPT" --dest "$T4" red-project "$T4/patients.csv" >"$TMPDIR_BASE/t4.log" 2>&1
STATUS=$(jq -r --arg fp "$T4/red-project/data/raw/patients.csv" '.[$fp]' "$T4/red-project/.claude/safety-status.json")
if [ "$STATUS" = "NEEDS_REVIEW:RED" ]; then
  pass "RED → NEEDS_REVIEW:RED"
else
  fail "expected NEEDS_REVIEW:RED, got: $STATUS"
fi

# ─── Test 5: YELLOW file → NEEDS_REVIEW:YELLOW ──────────────────────────
echo ""
echo "Test 5: YELLOW file is written as NEEDS_REVIEW:YELLOW"
T5="$TMPDIR_BASE/t5"
mkdir -p "$T5"
make_yellow_md "$T5/codebook.md"
bash "$INIT_SCRIPT" --dest "$T5" yellow-project --materials "$T5/codebook.md" >"$TMPDIR_BASE/t5.log" 2>&1
STATUS=$(jq -r --arg fp "$T5/yellow-project/materials/codebook.md" '.[$fp]' "$T5/yellow-project/.claude/safety-status.json" 2>/dev/null || echo "")
if [ "$STATUS" = "NEEDS_REVIEW:YELLOW" ]; then
  pass "YELLOW → NEEDS_REVIEW:YELLOW"
else
  fail "expected NEEDS_REVIEW:YELLOW, got: $STATUS"
  echo "    log:"; sed 's/^/      /' "$TMPDIR_BASE/t5.log"
fi

# ─── Test 6: --materials routes to materials/ not data/raw/ ────────────
echo ""
echo "Test 6: --materials flag routes to materials/"
if [ -f "$T5/yellow-project/materials/codebook.md" ]; then
  pass "file landed in materials/"
else
  fail "file NOT in materials/"
fi
if [ ! -f "$T5/yellow-project/data/raw/codebook.md" ]; then
  pass "file NOT in data/raw/"
else
  fail "file wrongly in data/raw/"
fi

# ─── Test 7: Copy mode duplicates bytes ─────────────────────────────────
echo ""
echo "Test 7: Default mode copies (not symlinks)"
T7="$TMPDIR_BASE/t7"
mkdir -p "$T7"
make_green_csv "$T7/data.csv"
bash "$INIT_SCRIPT" --dest "$T7" copy-project "$T7/data.csv" >/dev/null 2>&1
INGESTED="$T7/copy-project/data/raw/data.csv"
if [ -L "$INGESTED" ]; then
  fail "default mode created a symlink (should have copied)"
elif [ -f "$INGESTED" ]; then
  pass "default mode copied the file"
else
  fail "file missing after copy"
fi

# Modifying the copy should NOT affect the original
echo "extra" >> "$INGESTED"
if grep -q "extra" "$T7/data.csv"; then
  fail "copy is linked to original (data leaked back)"
else
  pass "copy is independent of original"
fi

# ─── Test 8: --link creates a symlink ──────────────────────────────────
echo ""
echo "Test 8: --link creates symlinks"
T8="$TMPDIR_BASE/t8"
mkdir -p "$T8"
make_green_csv "$T8/data.csv"
bash "$INIT_SCRIPT" --dest "$T8" link-project --link "$T8/data.csv" >/dev/null 2>&1
INGESTED="$T8/link-project/data/raw/data.csv"
if [ -L "$INGESTED" ]; then
  pass "--link created a symlink"
else
  fail "--link did not create a symlink"
fi

# ─── Test 9: --force overwrites existing project ───────────────────────
echo ""
echo "Test 9: --force overwrites existing project"
T9="$TMPDIR_BASE/t9"
mkdir -p "$T9"
make_green_csv "$T9/d1.csv"
make_green_csv "$T9/d2.csv"

bash "$INIT_SCRIPT" --dest "$T9" force-project "$T9/d1.csv" >/dev/null 2>&1
# Second run without --force should fail
if bash "$INIT_SCRIPT" --dest "$T9" force-project "$T9/d2.csv" >/dev/null 2>&1; then
  fail "second run without --force succeeded — should have refused"
else
  pass "second run without --force refused"
fi
# With --force, should succeed
if bash "$INIT_SCRIPT" --dest "$T9" --force force-project "$T9/d2.csv" >/dev/null 2>&1; then
  pass "--force allowed overwrite"
else
  fail "--force did not allow overwrite"
fi
# After force overwrite, d1.csv is gone and d2.csv is present
if [ ! -f "$T9/force-project/data/raw/d1.csv" ] && [ -f "$T9/force-project/data/raw/d2.csv" ]; then
  pass "--force replaced contents"
else
  fail "--force did not replace contents cleanly"
fi

# ─── Test 10: README contains project slug and key sections ────────────
echo ""
echo "Test 10: README contains slug + operating manual sections"
README="$T2/my-project/README.md"
if grep -q "my-project" "$README" && \
   grep -q "How this project works" "$README" && \
   grep -q "Directory layout" "$README" && \
   grep -q "safety-status.json" "$README" && \
   grep -q "NEEDS_REVIEW" "$README"; then
  pass "README has slug, layout, safety model sections"
else
  fail "README missing required sections"
fi

# ─── Test 11: .gitignore excludes data/ and safety-status.json ─────────
echo ""
echo "Test 11: .gitignore protects data and safety sidecar"
GI="$T2/my-project/.gitignore"
if grep -q "data/raw/" "$GI" && grep -q "safety-status.json" "$GI"; then
  pass ".gitignore excludes data/raw/ and safety-status.json"
else
  fail ".gitignore missing critical excludes"
fi

# ─── Test 12: init-report.md records scan results ──────────────────────
echo ""
echo "Test 12: init-report.md records scan summary"
REPORT="$T4/red-project/logs/init-report.md"
if grep -q "NEEDS_REVIEW:RED" "$REPORT" && grep -q "patients.csv" "$REPORT"; then
  pass "init-report.md records the RED file"
else
  fail "init-report.md missing scan record"
fi

# ─── Test 13: PreToolUse guard honors NEEDS_REVIEW ─────────────────────
echo ""
echo "Test 13: Hook blocks Read on NEEDS_REVIEW entries"
PROJ="$T4/red-project"
RED_FILE="$PROJ/data/raw/patients.csv"
P="$(payload Read "$RED_FILE" "$PROJ")"
echo "$P" | bash "$GUARD" 2>"$TMPDIR_BASE/guard-stderr" >/dev/null
RC=$?
if [ "$RC" = "2" ]; then
  pass "guard blocked Read on NEEDS_REVIEW:RED file"
  if grep -q "NEEDS_REVIEW" "$TMPDIR_BASE/guard-stderr" || grep -q "scholar-init review" "$TMPDIR_BASE/guard-stderr"; then
    pass "stderr mentions NEEDS_REVIEW or review command"
  else
    fail "stderr missing review instructions"
    echo "    stderr:"; sed 's/^/      /' "$TMPDIR_BASE/guard-stderr"
  fi
else
  fail "guard did not block NEEDS_REVIEW:RED (exit $RC)"
  echo "    stderr:"; sed 's/^/      /' "$TMPDIR_BASE/guard-stderr"
fi

# ─── Test 14: PreToolUse guard allows CLEARED ──────────────────────────
echo ""
echo "Test 14: Hook allows Read on CLEARED entries"
PROJ="$T2/my-project"
GREEN_FILE="$PROJ/data/raw/public.csv"
P="$(payload Read "$GREEN_FILE" "$PROJ")"
echo "$P" | bash "$GUARD" 2>/dev/null >/dev/null
RC=$?
if [ "$RC" = "0" ]; then
  pass "guard allowed Read on CLEARED file"
else
  fail "guard blocked CLEARED file (exit $RC)"
fi

# ─── Test 15: Directory ingest recurses ────────────────────────────────
echo ""
echo "Test 15: Directory argument ingests all files inside"
T15="$TMPDIR_BASE/t15"
mkdir -p "$T15/my-data"
make_green_csv "$T15/my-data/a.csv"
make_green_csv "$T15/my-data/b.csv"
make_red_csv "$T15/my-data/c.csv"
bash "$INIT_SCRIPT" --dest "$T15" dir-project "$T15/my-data" >/dev/null 2>&1
COUNT=$(jq 'length' "$T15/dir-project/.claude/safety-status.json")
if [ "$COUNT" = "3" ]; then
  pass "directory ingest recorded 3 files"
else
  fail "expected 3 entries, got $COUNT"
fi

# ─── Test 16: Missing input file is rejected ───────────────────────────
echo ""
echo "Test 16: Missing input file produces error"
if bash "$INIT_SCRIPT" --dest "$TMPDIR_BASE/t16" missing-project /does/not/exist.csv 2>/dev/null; then
  fail "accepted missing input"
else
  pass "rejected missing input"
fi

# ─── Test 17: Flag arity checks ────────────────────────────────────────
echo ""
echo "Test 17: Valued flags fail cleanly when argument missing"
OUT=$(bash "$INIT_SCRIPT" --dest 2>&1 || true)
if echo "$OUT" | grep -q "requires a directory argument"; then
  pass "--dest with no arg prints clean usage error"
else
  fail "--dest with no arg did not print clean error"
  echo "    stderr:"; echo "$OUT" | sed 's/^/      /'
fi

OUT=$(bash "$INIT_SCRIPT" --materials 2>&1 || true)
if echo "$OUT" | grep -q "requires a file or directory argument"; then
  pass "--materials with no arg prints clean usage error"
else
  fail "--materials with no arg did not print clean error"
fi

# Make sure `--dest SOMEDIR` without a slug/files still errors cleanly
# (not with an arity crash)
OUT=$(bash "$INIT_SCRIPT" --dest /tmp 2>&1 || true)
if echo "$OUT" | grep -q "project slug is required"; then
  pass "--dest VALUE without slug still reaches the slug check"
else
  fail "--dest VALUE without slug crashed or gave wrong error"
  echo "    stderr:"; echo "$OUT" | sed 's/^/      /'
fi

# ─── Summary ────────────────────────────────────────────────────────────
echo ""
echo "════════════════════"
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  echo ">>> FAILED"
  exit 1
else
  echo ">>> PASSED"
  exit 0
fi
