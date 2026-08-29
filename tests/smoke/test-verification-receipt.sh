#!/usr/bin/env bash
# test-verification-receipt.sh — locks the pre-dispatch verification chain
# (system-fix plan v2 P0.3 + S1.1, 2026-08-23): emit-agent-brief.sh mints a
# dispatch nonce, emit-verification-receipt.sh runs verify-brief.sh
# ORCHESTRATOR-side and writes briefs/receipts/<nonce>.json,
# emit-task-dispatch.sh --receipt binds it into the manifest row, and
# receipt-binding-check.sh audits the chain. Includes the P0.3 negative
# matrix: absent receipt, RED verification, stale brief, renamed receipt,
# reused nonce, receipt overwrite.
set -uo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
EAB="$REPO_ROOT/scripts/gates/emit-agent-brief.sh"
EVR="$REPO_ROOT/scripts/gates/emit-verification-receipt.sh"
ETD="$REPO_ROOT/scripts/gates/emit-task-dispatch.sh"
RBC="$REPO_ROOT/scripts/gates/receipt-binding-check.sh"
PASS=0; FAIL=0
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }
TMP="$(mktemp -d -t receipt.XXXXXX)"; trap 'rm -rf "$TMP"' EXIT
P="$TMP/p"; mkdir -p "$P/design" "$P/logs"
printf 'blueprint v1\n' > "$P/design/blueprint.md"

echo ""
echo "T1: GREEN chain — brief → receipt → dispatch row → binding check"
B_OUT=$(bash "$EAB" "$P" 3.5 theory --report-to "reviews/3.5-theory.md" \
  --inputs "design/blueprint.md:the design" --return findings-ndjson --purpose "t1" 2>&1)
BRIEF=$(printf '%s\n' "$B_OUT" | grep '^BRIEF=' | cut -d= -f2)
NONCE=$(printf '%s\n' "$B_OUT" | grep '^NONCE=' | cut -d= -f2)
set +e; R_OUT=$(bash "$EVR" "$P" "$BRIEF" 2>&1); R_RC=$?; set -u
RECEIPT="$P/briefs/receipts/$NONCE.json"
if [ "$R_RC" = 0 ] && [ -f "$RECEIPT" ] && grep -q "STATUS=GREEN" <<<"$R_OUT"; then
  pass "T1a receipt written GREEN at receipts/<nonce>.json"
else fail "T1a (rc=$R_RC): $R_OUT"; fi
python3 - "$RECEIPT" "$NONCE" <<'PY' && pass "T1b receipt binds nonce, brief sha, verifier sha, per-input results" || fail "T1b receipt content wrong"
import json, sys
r = json.load(open(sys.argv[1]))
assert r["schema"] == "verification-receipt/v1"
assert r["nonce"] == sys.argv[2]
assert len(r["brief_sha256"]) == 64 and len(r["verifier_sha256"]) == 64
assert r["status"] == "GREEN"
assert r["inputs"] and r["inputs"][0]["result"] == "OK"
assert len(r["inputs"][0]["sha256"]) == 64
PY
set +e; D_OUT=$(bash "$ETD" --proj "$P" --subagent peer-reviewer-theory --purpose "t1" \
  --phase 3.5 --agentId a1b2c3d4e5f6a7b8c --brief "$BRIEF" --receipt "$RECEIPT" 2>&1); D_RC=$?; set -u
ROW=$(tail -1 "$P/logs/dispatch-manifest.jsonl")
python3 - "$NONCE" <<PY && pass "T1c manifest row carries receipt + dispatch_nonce" || fail "T1c (rc=$D_RC): $ROW"
import json, sys
r = json.loads('''$ROW''')
assert r["dispatch_nonce"] == sys.argv[1]
assert r["receipt"].endswith(sys.argv[1] + ".json")
PY
set +e; C_OUT=$(bash "$RBC" "$P" --phase 3.5 2>&1); C_RC=$?; set -u
if [ "$C_RC" = 0 ] && grep -q "STATUS=GREEN" <<<"$C_OUT" && grep -q "RECEIPTED_ROWS=1" <<<"$C_OUT"; then
  pass "T1d receipt-binding-check GREEN on the intact chain"
else fail "T1d (rc=$C_RC): $C_OUT"; fi

echo ""
echo "T2: briefed row WITHOUT receipt → YELLOW default, RED under enforcement"
bash "$EAB" "$P" 5.5 fixer --report-to "reviews/5.5-fixer.md" \
  --inputs "design/blueprint.md" --purpose "t2" >/dev/null 2>&1
bash "$ETD" --proj "$P" --subagent review-code-style --purpose "t2" --phase 5.5 \
  --agentId b2c3d4e5f6a7b8c9d --brief "briefs/5.5-fixer.json" >/dev/null 2>&1
set +e; C_OUT=$(bash "$RBC" "$P" --phase 5.5 2>&1); C_RC=$?; set -u
[ "$C_RC" = 2 ] && grep -q "legacy-unreceipted" <<<"$C_OUT" && pass "T2a unreceipted → YELLOW (advisory rollout)" || fail "T2a (rc=$C_RC): $C_OUT"
set +e; C_OUT=$(SCHOLAR_RECEIPTS_ENFORCE=1 bash "$RBC" "$P" --phase 5.5 2>&1); C_RC=$?; set -u
[ "$C_RC" = 1 ] && grep -q "STATUS=RED" <<<"$C_OUT" && pass "T2b unreceipted → RED under SCHOLAR_RECEIPTS_ENFORCE=1" || fail "T2b (rc=$C_RC): $C_OUT"

echo ""
echo "T3: RED verification still writes the receipt but refuses dispatch"
P3="$TMP/p3"; mkdir -p "$P3/design" "$P3/logs"
printf 'v1\n' > "$P3/design/doc.md"
B_OUT=$(bash "$EAB" "$P3" 10 senior --report-to "reviews/10-senior.md" \
  --inputs "design/doc.md:the doc" --purpose "t3" 2>&1)
BRIEF3=$(printf '%s\n' "$B_OUT" | grep '^BRIEF=' | cut -d= -f2)
NONCE3=$(printf '%s\n' "$B_OUT" | grep '^NONCE=' | cut -d= -f2)
printf 'v2 — moved after brief\n' > "$P3/design/doc.md"
set +e; R_OUT=$(bash "$EVR" "$P3" "$BRIEF3" 2>&1); R_RC=$?; set -u
if [ "$R_RC" = 1 ] && [ -f "$P3/briefs/receipts/$NONCE3.json" ] && grep -q "STATUS=RED" <<<"$R_OUT"; then
  pass "T3a mutated input → exit 1, RED receipt kept as audit evidence"
else fail "T3a (rc=$R_RC): $R_OUT"; fi
set +e; D_OUT=$(bash "$ETD" --proj "$P3" --subagent peer-reviewer-senior --purpose "t3" \
  --phase 10 --agentId c3d4e5f6a7b8c9d0e --brief "$BRIEF3" --receipt "$P3/briefs/receipts/$NONCE3.json" 2>&1); D_RC=$?; set -u
[ "$D_RC" = 1 ] && grep -q "non-GREEN" <<<"$D_OUT" && pass "T3b --receipt refuses a RED receipt at record time" || fail "T3b (rc=$D_RC): $D_OUT"

echo ""
echo "T4: brief mutated AFTER a GREEN receipt → stale receipt refused"
P4="$TMP/p4"; mkdir -p "$P4/design" "$P4/logs"
printf 'stable\n' > "$P4/design/doc.md"
B_OUT=$(bash "$EAB" "$P4" 7b verify-logic --report-to "reviews/7b-logic.md" \
  --inputs "design/doc.md:the doc" --purpose "t4" 2>&1)
BRIEF4=$(printf '%s\n' "$B_OUT" | grep '^BRIEF=' | cut -d= -f2)
NONCE4=$(printf '%s\n' "$B_OUT" | grep '^NONCE=' | cut -d= -f2)
bash "$EVR" "$P4" "$BRIEF4" >/dev/null 2>&1
python3 - "$BRIEF4" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); d["purpose"] = "tampered after verification"
json.dump(d, open(sys.argv[1], "w"), indent=1)
PY
set +e; D_OUT=$(bash "$ETD" --proj "$P4" --subagent verify-logic --purpose "t4" \
  --phase 7b --agentId d4e5f6a7b8c9d0e1f --brief "$BRIEF4" --receipt "$P4/briefs/receipts/$NONCE4.json" 2>&1); D_RC=$?; set -u
[ "$D_RC" = 1 ] && grep -q "changed AFTER verification" <<<"$D_OUT" && pass "T4 stale receipt (brief re-hashed) refused at record time" || fail "T4 (rc=$D_RC): $D_OUT"

echo ""
echo "T5: renamed receipt file → binding check RED"
P5="$TMP/p5"; mkdir -p "$P5/design" "$P5/logs"
printf 'stable\n' > "$P5/design/doc.md"
B_OUT=$(bash "$EAB" "$P5" 3.5 quant --report-to "reviews/3.5-quant.md" \
  --inputs "design/doc.md:the doc" --purpose "t5" 2>&1)
BRIEF5=$(printf '%s\n' "$B_OUT" | grep '^BRIEF=' | cut -d= -f2)
NONCE5=$(printf '%s\n' "$B_OUT" | grep '^NONCE=' | cut -d= -f2)
bash "$EVR" "$P5" "$BRIEF5" >/dev/null 2>&1
bash "$ETD" --proj "$P5" --subagent peer-reviewer-quant --purpose "t5" --phase 3.5 \
  --agentId e5f6a7b8c9d0e1f2a --brief "$BRIEF5" --receipt "$P5/briefs/receipts/$NONCE5.json" >/dev/null 2>&1
FAKE="badc0ffee0ddf00dbadc0ffe"
mv "$P5/briefs/receipts/$NONCE5.json" "$P5/briefs/receipts/$FAKE.json"
python3 - "$P5/logs/dispatch-manifest.jsonl" "$NONCE5" "$FAKE" <<'PY'
import json, sys
lines = [json.loads(l) for l in open(sys.argv[1])]
for r in lines:
    if r.get("dispatch_nonce") == sys.argv[2]:
        r["receipt"] = r["receipt"].replace(sys.argv[2], sys.argv[3])
open(sys.argv[1], "w").write("\n".join(json.dumps(r) for r in lines) + "\n")
PY
set +e; C_OUT=$(bash "$RBC" "$P5" 2>&1); C_RC=$?; set -u
[ "$C_RC" = 1 ] && grep -q "nonce mismatch" <<<"$C_OUT" && pass "T5 renamed receipt → RED nonce mismatch" || fail "T5 (rc=$C_RC): $C_OUT"

echo ""
echo "T6: one nonce on two manifest rows → RED reuse"
P6="$TMP/p6"; mkdir -p "$P6/design" "$P6/logs"
printf 'stable\n' > "$P6/design/doc.md"
B_OUT=$(bash "$EAB" "$P6" 10 theory --report-to "reviews/10-theory.md" \
  --inputs "design/doc.md:the doc" --purpose "t6" 2>&1)
BRIEF6=$(printf '%s\n' "$B_OUT" | grep '^BRIEF=' | cut -d= -f2)
NONCE6=$(printf '%s\n' "$B_OUT" | grep '^NONCE=' | cut -d= -f2)
bash "$EVR" "$P6" "$BRIEF6" >/dev/null 2>&1
for AID in f6a7b8c9d0e1f2a3b a7b8c9d0e1f2a3b4c; do
  bash "$ETD" --proj "$P6" --subagent peer-reviewer-theory --purpose "t6" --phase 10 \
    --agentId "$AID" --brief "$BRIEF6" --receipt "$P6/briefs/receipts/$NONCE6.json" >/dev/null 2>&1
done
set +e; C_OUT=$(bash "$RBC" "$P6" 2>&1); C_RC=$?; set -u
[ "$C_RC" = 1 ] && grep -q "REUSED" <<<"$C_OUT" && pass "T6 reused nonce across rows → RED" || fail "T6 (rc=$C_RC): $C_OUT"

echo ""
echo "T7: second receipt for the same nonce → refused (no overwrite)"
set +e; R_OUT=$(bash "$EVR" "$P6" "$BRIEF6" 2>&1); R_RC=$?; set -u
[ "$R_RC" = 1 ] && grep -q "already exists" <<<"$R_OUT" && pass "T7 receipt overwrite refused — one nonce, one verification" || fail "T7 (rc=$R_RC): $R_OUT"

echo ""
echo "T9 (review C1): receipt file modified after recording → RED hash mismatch"
P9="$TMP/p9"; mkdir -p "$P9/design" "$P9/logs"
printf 'stable\n' > "$P9/design/doc.md"
B_OUT=$(bash "$EAB" "$P9" 3.5 senior --report-to "reviews/3.5-senior.md" \
  --inputs "design/doc.md:the doc" --purpose "t9" 2>&1)
BRIEF9=$(printf '%s\n' "$B_OUT" | grep '^BRIEF=' | cut -d= -f2)
NONCE9=$(printf '%s\n' "$B_OUT" | grep '^NONCE=' | cut -d= -f2)
bash "$EVR" "$P9" "$BRIEF9" >/dev/null 2>&1
bash "$ETD" --proj "$P9" --subagent peer-reviewer-senior --purpose "t9" --phase 3.5 \
  --agentId f9a7b8c9d0e1f2a3b --brief "$BRIEF9" --receipt "$P9/briefs/receipts/$NONCE9.json" >/dev/null 2>&1
python3 - "$P9/briefs/receipts/$NONCE9.json" <<'PY'
import json, sys
r = json.load(open(sys.argv[1])); r["verified_at"] = "2020-01-01T00:00:00Z"
json.dump(r, open(sys.argv[1], "w"), indent=1)
PY
set +e; C_OUT=$(bash "$RBC" "$P9" 2>&1); C_RC=$?; set -u
[ "$C_RC" = 1 ] && grep -q "hashes differently" <<<"$C_OUT" \
  && pass "T9 post-record receipt edit → RED (content re-hashed, not trusted)" || fail "T9 (rc=$C_RC): $C_OUT"

echo ""
echo "T10 (review C3): row naming an out-of-project receipt → RED containment"
P10="$TMP/p10"; mkdir -p "$P10/design" "$P10/logs" "$TMP/elsewhere"
printf 'stable\n' > "$P10/design/doc.md"
B_OUT=$(bash "$EAB" "$P10" 3.5 quant --report-to "reviews/3.5-quant.md" \
  --inputs "design/doc.md:the doc" --purpose "t10" 2>&1)
BRIEF10=$(printf '%s\n' "$B_OUT" | grep '^BRIEF=' | cut -d= -f2)
NONCE10=$(printf '%s\n' "$B_OUT" | grep '^NONCE=' | cut -d= -f2)
bash "$EVR" "$P10" "$BRIEF10" >/dev/null 2>&1
bash "$ETD" --proj "$P10" --subagent peer-reviewer-quant --purpose "t10" --phase 3.5 \
  --agentId a0b7b8c9d0e1f2a3b --brief "$BRIEF10" --receipt "$P10/briefs/receipts/$NONCE10.json" >/dev/null 2>&1
cp "$P10/briefs/receipts/$NONCE10.json" "$TMP/elsewhere/$NONCE10.json"
python3 - "$P10/logs/dispatch-manifest.jsonl" "$TMP/elsewhere/$NONCE10.json" <<'PY'
import json, sys
lines = [json.loads(l) for l in open(sys.argv[1])]
lines[-1]["receipt"] = sys.argv[2]
open(sys.argv[1], "w").write("\n".join(json.dumps(r) for r in lines) + "\n")
PY
set +e; C_OUT=$(bash "$RBC" "$P10" 2>&1); C_RC=$?; set -u
[ "$C_RC" = 1 ] && grep -q "outside" <<<"$C_OUT" \
  && pass "T10 out-of-project receipt path → RED" || fail "T10 (rc=$C_RC): $C_OUT"
# T10b: ETD itself refuses recording an out-of-project receipt.
set +e; D_OUT=$(bash "$ETD" --proj "$P10" --subagent peer-reviewer-quant --purpose "t10b" --phase 3.5 \
  --agentId a1c7b8c9d0e1f2a3b --brief "$BRIEF10" --receipt "$TMP/elsewhere/$NONCE10.json" 2>&1); D_RC=$?; set -u
[ "$D_RC" = 1 ] && grep -q "briefs/receipts" <<<"$D_OUT" \
  && pass "T10b --receipt outside <proj>/briefs/receipts refused at record time" || fail "T10b (rc=$D_RC): $D_OUT"

echo ""
echo "T11 (review C2): one nonce riding rows in TWO phases → RED under either filter"
P11="$TMP/p11"; mkdir -p "$P11/design" "$P11/logs"
printf 'stable\n' > "$P11/design/doc.md"
B_OUT=$(bash "$EAB" "$P11" 3.5 theory --report-to "reviews/3.5-theory.md" \
  --inputs "design/doc.md:the doc" --purpose "t11" 2>&1)
BRIEF11=$(printf '%s\n' "$B_OUT" | grep '^BRIEF=' | cut -d= -f2)
NONCE11=$(printf '%s\n' "$B_OUT" | grep '^NONCE=' | cut -d= -f2)
bash "$EVR" "$P11" "$BRIEF11" >/dev/null 2>&1
bash "$ETD" --proj "$P11" --subagent peer-reviewer-theory --purpose "t11" --phase 3.5 \
  --agentId b2c7b8c9d0e1f2a3b --brief "$BRIEF11" --receipt "$P11/briefs/receipts/$NONCE11.json" >/dev/null 2>&1
bash "$ETD" --proj "$P11" --subagent peer-reviewer-theory --purpose "t11" --phase 5.5 \
  --agentId c3d7b8c9d0e1f2a3b --brief "$BRIEF11" --receipt "$P11/briefs/receipts/$NONCE11.json" >/dev/null 2>&1
set +e; C_OUT=$(bash "$RBC" "$P11" --phase 3.5 2>&1); C_RC=$?; set -u
[ "$C_RC" = 1 ] && grep -q "REUSED" <<<"$C_OUT" \
  && pass "T11 cross-phase nonce reuse visible under a --phase filter" || fail "T11 (rc=$C_RC): $C_OUT"

echo ""
echo "T12 (review M2): input path containing ' (' records exactly in the receipt"
P12="$TMP/p12"; mkdir -p "$P12/design" "$P12/logs"
printf 'x\n' > "$P12/design/notes (final).md"
B_OUT=$(bash "$EAB" "$P12" 3.5 reader --report-to "reviews/3.5-reader.md" \
  --input "design/notes (final).md" --why "paren-bearing name" --purpose "t12" 2>&1)
BRIEF12=$(printf '%s\n' "$B_OUT" | grep '^BRIEF=' | cut -d= -f2)
NONCE12=$(printf '%s\n' "$B_OUT" | grep '^NONCE=' | cut -d= -f2)
set +e; bash "$EVR" "$P12" "$BRIEF12" >/dev/null 2>&1; R_RC=$?; set -u
python3 - "$P12/briefs/receipts/$NONCE12.json" <<'PY' && pass "T12 paren path intact, result OK (no truncation)" || fail "T12 receipt content wrong"
import json, sys
r = json.load(open(sys.argv[1]))
assert r["inputs"][0]["path"] == "design/notes (final).md", r["inputs"][0]
assert r["inputs"][0]["result"] == "OK"
PY

echo ""
echo "T8: legacy v1 brief (no nonce) → receipt refused with re-emit guidance"
P8="$TMP/p8"; mkdir -p "$P8/briefs" "$P8/design" "$P8/logs"
printf '{"schema":"agent-brief/v1","phase":"3.5","role":"x","inputs":[]}\n' > "$P8/briefs/3.5-x.json"
set +e; R_OUT=$(bash "$EVR" "$P8" "briefs/3.5-x.json" 2>&1); R_RC=$?; set -u
[ "$R_RC" = 2 ] && grep -q "no dispatch_nonce" <<<"$R_OUT" && pass "T8 v1 brief → exit 2, re-emit guidance" || fail "T8 (rc=$R_RC): $R_OUT"

echo ""
echo "T13: relative PROJ (the canonical derive-proj.sh form) — handoff 2026-08-25 P1-A"
# Every earlier fixture uses an absolute mktemp PROJ, which is exactly why the
# double-prefix shipped unseen: derive-proj.sh emits output/<slug> RELATIVE.
mkdir -p "$TMP/rel/output/p13/design" "$TMP/rel/output/p13/logs"
printf 'blueprint\n' > "$TMP/rel/output/p13/design/blueprint.md"
T13_OUT=$(cd "$TMP/rel" && {
  B_OUT=$(bash "$EAB" "output/p13" 3.5 theory --report-to "reviews/3.5-theory.md" \
    --inputs "design/blueprint.md:the design" --return findings-ndjson --purpose "t13" 2>&1)
  BRIEF=$(printf '%s\n' "$B_OUT" | grep '^BRIEF=' | cut -d= -f2)
  # (a) the EXACT printed BRIEF= value (already PROJ-prefixed, relative)
  R1=$(bash "$EVR" "output/p13" "$BRIEF" 2>&1); RC1=$?
  # (b) the bare PROJ-relative form, on a second brief (one nonce, one receipt)
  bash "$EAB" "output/p13" 3.5 methods --report-to "reviews/3.5-methods.md" \
    --inputs "design/blueprint.md:the design" --return findings-ndjson --purpose "t13b" >/dev/null 2>&1
  R2=$(bash "$EVR" "output/p13" "briefs/3.5-methods.json" 2>&1); RC2=$?
  # (c) missing brief names BOTH candidate paths
  R3=$(bash "$EVR" "output/p13" "briefs/nope.json" 2>&1); RC3=$?
  echo "RC1=$RC1 RC2=$RC2 RC3=$RC3"
  printf '%s\n' "$R1" | grep -c "STATUS=GREEN" | sed 's/^/G1=/'
  printf '%s\n' "$R2" | grep -c "STATUS=GREEN" | sed 's/^/G2=/'
  printf '%s\n' "$R3" | grep -c "output/p13/briefs/nope.json or briefs/nope.json" | sed 's/^/C3=/'
})
grep -q "RC1=0" <<<"$T13_OUT" && grep -q "G1=1" <<<"$T13_OUT" \
  && pass "T13a printed BRIEF= form verifies GREEN under relative PROJ" \
  || fail "T13a: $T13_OUT"
grep -q "RC2=0" <<<"$T13_OUT" && grep -q "G2=1" <<<"$T13_OUT" \
  && pass "T13b bare briefs/ form verifies GREEN under relative PROJ" \
  || fail "T13b: $T13_OUT"
grep -q "RC3=2" <<<"$T13_OUT" && grep -q "C3=1" <<<"$T13_OUT" \
  && pass "T13c missing brief fails closed naming both candidates" \
  || fail "T13c: $T13_OUT"

echo ""
echo "════════════════════"
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
