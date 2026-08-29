#!/usr/bin/env bash
# Smoke tests for the Evidence Ledger layer (Slice A):
#   - schema/claim-anchor.schema.json + schema/claim-audit-record.schema.json exist
#     and are valid JSON
#   - _shared/evidence-ledger.md bash helpers: capture, dedup, null-quote records,
#     sidecar + ingest idempotence
#   - scripts/gates/evidence-anchor-check.sh: GREEN / YELLOW / RED / INERT paths,
#     including NEGATIVE fixtures (schema-invalid line, unresolvable inventory id)
#   - scripts/render-evidence-dossier.py: dossier (UNADJUDICATED stamp, action-
#     required view, unused anchors, source index) and brief (kind filter)
#
# Protocol: skills/_shared/evidence-ledger.md.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LEDGER_MD="$REPO_ROOT/.claude/skills/_shared/evidence-ledger.md"
GATE="$REPO_ROOT/scripts/gates/evidence-anchor-check.sh"
RENDER="$REPO_ROOT/scripts/render-evidence-dossier.py"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

PASS=0; FAIL=0
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

echo "=== Evidence Ledger Smoke Tests (Slice A) ==="
echo ""

# ── T1: files exist, schemas parse ───────────────────────────────
echo "Test 1: artifacts exist and schemas are valid JSON"
for f in "$LEDGER_MD" "$GATE" "$RENDER" \
         "$REPO_ROOT/schema/claim-anchor.schema.json" \
         "$REPO_ROOT/schema/claim-audit-record.schema.json"; do
  [ -f "$f" ] && pass "exists: ${f#"$REPO_ROOT"/}" || fail "missing: ${f#"$REPO_ROOT"/}"
done
jq -e '.title == "claim-anchor/v1"' "$REPO_ROOT/schema/claim-anchor.schema.json" >/dev/null 2>&1 \
  && pass "claim-anchor schema valid JSON with title" || fail "claim-anchor schema invalid"
jq -e '.title == "claim-audit-record/v1"' "$REPO_ROOT/schema/claim-audit-record.schema.json" >/dev/null 2>&1 \
  && pass "claim-audit-record schema valid JSON with title" || fail "claim-audit-record schema invalid"

# ── T2: helper block — capture, dedup, sidecar ───────────────────
echo ""
echo "Test 2: evidence-ledger.md bash helpers"
(
  cd "$WORK"
  eval "$(sed -n '/^```bash/,/^```/p' "$LEDGER_MD" | sed '1d;$d')"
  export PROJ="$WORK/hp"
  id1=$(EV_CITE_KEY="Autor2013" EV_CLAIM_KIND="magnitude" \
    EV_QUOTE="about 0.6 percentage points" EV_FORM="source_verbatim" \
    EV_TIER="T1_fulltext" EV_SOURCE_LOC="p.2125" \
    EV_PRODUCED_BY="scholar-lit-review" ev_capture)
  id2=$(EV_CITE_KEY="Autor2013" EV_CLAIM_KIND="prose_sentence" \
    EV_QUOTE="about 0.6 percentage points" EV_FORM="source_verbatim" \
    EV_TIER="T1_fulltext" EV_SOURCE_LOC="p.2125" \
    EV_PRODUCED_BY="scholar-write" ev_capture)
  [ "$id1" = "$id2" ] || { echo "DEDUP_FAIL"; exit 1; }
  [ "$(ev_count)" = "1" ] || { echo "COUNT_FAIL"; exit 1; }
  printf '%s' "$id1" | grep -qE '^[a-z0-9_-]+-[0-9a-f]{8}$' || { echo "ID_FAIL"; exit 1; }
  jq -e '.schema=="claim-anchor/v1" and .anchor_id and .cite_key' \
    "$PROJ/evidence/claim-anchors.ndjson" >/dev/null || { echo "JSON_FAIL"; exit 1; }
  # sidecar + idempotent ingest
  export EV_SIDECAR="$WORK/side.anchors.ndjson"
  eval "$(sed -n '/^```bash/,/^```/p' "$LEDGER_MD" | sed '1d;$d')"
  EV_CITE_KEY="zhang2019" EV_CLAIM_KIND="map_cell" EV_QUOTE="q" \
    EV_FORM="abstract_verbatim" EV_TIER="T3_abstract" \
    EV_PRODUCED_BY="scholar-lit-review" ev_capture >/dev/null
  unset EV_SIDECAR
  eval "$(sed -n '/^```bash/,/^```/p' "$LEDGER_MD" | sed '1d;$d')"
  ev_ingest_sidecar "$WORK/side.anchors.ndjson"
  ev_ingest_sidecar "$WORK/side.anchors.ndjson"
  [ "$(ev_count)" = "2" ] || { echo "INGEST_FAIL"; exit 1; }
  echo "HELPERS_OK"
) > "$WORK/helper.out" 2>&1
if grep -q "HELPERS_OK" "$WORK/helper.out"; then
  pass "capture + dedup + sidecar ingest (idempotent)"
else
  fail "helper block: $(tail -1 "$WORK/helper.out")"
fi

# ── T3: gate verdict paths, incl. negative fixtures ──────────────
echo ""
echo "Test 3: evidence-anchor-check.sh verdicts"
GOOD='{"schema":"claim-anchor/v1","anchor_id":"autor2013-3f9a1c2e","cite_key":"autor2013","claim_kind":"map_cell","stance":"supports","evidence_quote":"reduces employment","evidence_form":"source_verbatim","access_tier":"T1_fulltext","produced_by":"scholar-lit-review","ts":"2026-08-12T00:00:00Z"}'
BAD='{"schema":"claim-anchor/v1","anchor_id":"BADID","cite_key":"x","claim_kind":"nonsense","stance":"supports","evidence_form":"source_verbatim","access_tier":"T1_fulltext","produced_by":"s","ts":"t"}'

mkdir -p "$WORK/g1"                                   # empty → INERT
bash "$GATE" "$WORK/g1" --phase 2 >/dev/null 2>&1
[ $? -eq 3 ] && pass "INERT on empty project" || fail "INERT path"

mkdir -p "$WORK/g1b/drafts" "$WORK/g1b/logs"          # LEGACY: orchestrated + LRH but NO evidence/ dir → INERT
echo x > "$WORK/g1b/drafts/scholar-lrh-t-2026-08-12.md"; echo s > "$WORK/g1b/logs/project-state.md"
bash "$GATE" "$WORK/g1b" --phase 2 >/dev/null 2>&1
[ $? -eq 3 ] && pass "INERT: legacy project (no evidence/ dir) never failed retroactively" || fail "legacy INERT path"

mkdir -p "$WORK/g2/drafts" "$WORK/g2/logs" "$WORK/g2/evidence"  # post-feature scaffold, orchestrated, empty ledger → RED
echo x > "$WORK/g2/drafts/scholar-lrh-t-2026-08-12.md"; echo s > "$WORK/g2/logs/project-state.md"
bash "$GATE" "$WORK/g2" --phase 2 >/dev/null 2>&1
[ $? -eq 1 ] && pass "RED: orchestrated + scaffolded evidence/ but ledger missing" || fail "RED orchestrated path"

mkdir -p "$WORK/g3/drafts" "$WORK/g3/evidence"        # standalone, scaffolded, no ledger → YELLOW
echo x > "$WORK/g3/drafts/scholar-lrh-t-2026-08-12.md"
bash "$GATE" "$WORK/g3" --phase 2 >/dev/null 2>&1
[ $? -eq 2 ] && pass "YELLOW: standalone missing ledger" || fail "YELLOW standalone path"

mkdir -p "$WORK/g4/drafts" "$WORK/g4/evidence"        # valid + covered → GREEN
echo x > "$WORK/g4/drafts/scholar-lrh-t-2026-08-12.md"
printf '%s\n' "$GOOD" > "$WORK/g4/evidence/claim-anchors.ndjson"
printf '{"schema":"claim-inventory/v1","rows":[{"row_id":"r1","claim_kind":"map_cell","claim_text":"A","anchor_ids":["autor2013-3f9a1c2e"]}]}' > "$WORK/g4/evidence/claim-inventory.json"
bash "$GATE" "$WORK/g4" --phase 2 >/dev/null 2>&1
[ $? -eq 0 ] && pass "GREEN: valid ledger + covered inventory" || fail "GREEN path"

mkdir -p "$WORK/g5/drafts" "$WORK/g5/evidence"        # NEGATIVE: invalid line → RED
echo x > "$WORK/g5/drafts/scholar-lrh-t-2026-08-12.md"
printf '%s\n%s\n' "$GOOD" "$BAD" > "$WORK/g5/evidence/claim-anchors.ndjson"
bash "$GATE" "$WORK/g5" --phase 2 >/dev/null 2>&1
[ $? -eq 1 ] && pass "RED: schema-invalid ledger line detected" || fail "negative fixture: invalid line NOT detected"

mkdir -p "$WORK/g6/drafts" "$WORK/g6/evidence"        # NEGATIVE: ghost inventory id → RED
echo x > "$WORK/g6/drafts/scholar-lrh-t-2026-08-12.md"
printf '%s\n' "$GOOD" > "$WORK/g6/evidence/claim-anchors.ndjson"
printf '{"schema":"claim-inventory/v1","rows":[{"row_id":"r1","claim_kind":"map_cell","claim_text":"A","anchor_ids":["ghost9999-deadbeef"]}]}' > "$WORK/g6/evidence/claim-inventory.json"
bash "$GATE" "$WORK/g6" --phase 2 >/dev/null 2>&1
[ $? -eq 1 ] && pass "RED: unresolvable inventory anchor_id detected" || fail "negative fixture: ghost id NOT detected"


# ── Real-project eval fixes (2026-08-22, finding 17 + CRITICAL) ──
mkdir -p "$WORK/g7/drafts" "$WORK/g7/evidence"        # reader identity → GREEN
echo x > "$WORK/g7/drafts/scholar-lrh-t-2026-08-12.md"
printf '%s\n' '{"schema":"claim-anchor/v1","anchor_id":"autor2013-3f9a1c2e","cite_key":"autor2013","claim_kind":"map_cell","stance":"supports","evidence_quote":"reduces employment","evidence_form":"source_verbatim","access_tier":"T1_fulltext","produced_by":"reader-batch2","ts":"2026-08-22T00:00:00Z"}' > "$WORK/g7/evidence/claim-anchors.ndjson"
printf '{"schema":"claim-inventory/v1","rows":[{"row_id":"r1","claim_kind":"map_cell","claim_text":"A","anchor_ids":["autor2013-3f9a1c2e"]}]}' > "$WORK/g7/evidence/claim-inventory.json"
bash "$GATE" "$WORK/g7" --phase 2 >/dev/null 2>&1
[ $? -eq 0 ] && pass "GREEN: reader-batchN produced_by is schema-valid (delegated Phase 2)" || fail "reader-batch identity rejected"

mkdir -p "$WORK/g8/drafts" "$WORK/g8/evidence"        # live-line arbitrary produced_by → RED (alignment)
echo x > "$WORK/g8/drafts/scholar-lrh-t-2026-08-12.md"
printf '%s\n' '{"schema":"claim-anchor/v1","anchor_id":"autor2013-3f9a1c2e","cite_key":"autor2013","claim_kind":"map_cell","stance":"supports","evidence_quote":"q","evidence_form":"source_verbatim","access_tier":"T1_fulltext","produced_by":"some-rogue-writer","ts":"t"}' > "$WORK/g8/evidence/claim-anchors.ndjson"
printf '{"schema":"claim-inventory/v1","rows":[{"row_id":"r1","claim_kind":"map_cell","claim_text":"A","anchor_ids":["autor2013-3f9a1c2e"]}]}' > "$WORK/g8/evidence/claim-inventory.json"
bash "$GATE" "$WORK/g8" --phase 2 >/dev/null 2>&1
[ $? -eq 1 ] && pass "RED: off-enum produced_by now fails (gate == schema; was any-non-empty)" || fail "off-enum produced_by still passes"

mkdir -p "$WORK/g9/drafts" "$WORK/g9/evidence"        # superseded bad line + valid latest → YELLOW not RED
echo x > "$WORK/g9/drafts/scholar-lrh-t-2026-08-12.md"
printf '%s\n%s\n' \
  '{"schema":"claim-anchor/v1","anchor_id":"autor2013-3f9a1c2e","cite_key":"autor2013","claim_kind":"nonsense","stance":"supports","evidence_form":"source_verbatim","access_tier":"T1_fulltext","produced_by":"scholar-lit-review","ts":"t"}' \
  '{"schema":"claim-anchor/v1","anchor_id":"autor2013-3f9a1c2e","cite_key":"autor2013","claim_kind":"map_cell","stance":"supports","evidence_quote":"q","evidence_form":"source_verbatim","access_tier":"T1_fulltext","produced_by":"scholar-lit-review","ts":"t2"}' \
  > "$WORK/g9/evidence/claim-anchors.ndjson"
printf '{"schema":"claim-inventory/v1","rows":[{"row_id":"r1","claim_kind":"map_cell","claim_text":"A","anchor_ids":["autor2013-3f9a1c2e"]}]}' > "$WORK/g9/evidence/claim-inventory.json"
OUT_G9=$(bash "$GATE" "$WORK/g9" --phase 2 2>&1); RC_G9=$?
if [ "$RC_G9" -eq 2 ] && printf '%s' "$OUT_G9" | grep -q "superseded"; then
  pass "YELLOW: superseded invalid line is history, latest valid line governs"
else
  fail "superseded-line handling (rc=$RC_G9)"
fi

# ── T4: renderer ─────────────────────────────────────────────────
echo ""
echo "Test 4: render-evidence-dossier.py"
mkdir -p "$WORK/r/evidence" "$WORK/r/drafts"
printf '%s\n' "$GOOD" > "$WORK/r/evidence/claim-anchors.ndjson"
cat > "$WORK/r/drafts/d.md" <<'EOF'
## Section One
Claim sentence here (Autor 2013). <!--ev: autor2013-3f9a1c2e-->
EOF
python3 "$RENDER" --proj "$WORK/r" --out "$WORK/r/evidence/dossier.md" \
  --draft "$WORK/r/drafts/d.md" >/dev/null 2>&1
if [ -s "$WORK/r/evidence/dossier.md" ]; then
  pass "dossier rendered"
  grep -q "UNADJUDICATED" "$WORK/r/evidence/dossier.md" \
    && pass "UNADJUDICATED stamp without audit" || fail "missing UNADJUDICATED stamp"
  grep -q "reduces employment" "$WORK/r/evidence/dossier.md" \
    && pass "verbatim quote in dossier" || fail "quote missing from dossier"
  grep -q "Section One" "$WORK/r/evidence/dossier.md" \
    && pass "draft section ordering" || fail "section ordering missing"
else
  fail "dossier not rendered"
fi
python3 "$RENDER" --proj "$WORK/r" --out "$WORK/r/evidence/brief.md" \
  --brief --kinds map_cell >/dev/null 2>&1
grep -q "autor2013" "$WORK/r/evidence/brief.md" 2>/dev/null \
  && pass "brief rendered with kind filter" || fail "brief render failed"

# (T5 phase-verify integration omitted in this repo: phase-verify.sh ships
#  for parity but no in-repo orchestrator uses it — see CLAUDE.md.)

# ── T6: --phase 7 mode (Slice B: tag resolution, adjacency, coverage) ──
echo ""
echo "Test 6: evidence-anchor-check.sh --phase 7"
A7='{"schema":"claim-anchor/v1","anchor_id":"autor2013-3f9a1c2e","cite_key":"autor2013","claim_kind":"prose_sentence","stance":"supports","evidence_quote":"q","evidence_form":"source_verbatim","access_tier":"T1_fulltext","produced_by":"scholar-write","ts":"t"}'

mkdir -p "$WORK/s1/evidence" "$WORK/s1/drafts"        # GREEN
printf '%s\n' "$A7" > "$WORK/s1/evidence/claim-anchors.ndjson"
printf '## Theory\nTrade exposure reduced employment (Autor et al. 2013). <!--ev: autor2013-3f9a1c2e-->\n' > "$WORK/s1/drafts/draft-theory-t.md"
bash "$GATE" "$WORK/s1" --phase 7 >/dev/null 2>&1
[ $? -eq 0 ] && pass "P7 GREEN: resolved + adjacent + covered" || fail "P7 GREEN path"

mkdir -p "$WORK/s2/evidence" "$WORK/s2/drafts"        # RED: dangling tag
printf '%s\n' "$A7" > "$WORK/s2/evidence/claim-anchors.ndjson"
printf 'Claim (Autor et al. 2013). <!--ev: ghost0000-deadbeef-->\n' > "$WORK/s2/drafts/draft-theory-t.md"
bash "$GATE" "$WORK/s2" --phase 7 >/dev/null 2>&1
[ $? -eq 1 ] && pass "P7 RED: unresolved tag detected" || fail "P7 negative fixture: dangling tag NOT detected"

mkdir -p "$WORK/s3/evidence" "$WORK/s3/drafts"        # YELLOW: adjacency mismatch
printf '%s\n' "$A7" > "$WORK/s3/evidence/claim-anchors.ndjson"
printf 'A different claim (Card and Krueger 1994). <!--ev: autor2013-3f9a1c2e-->\n' > "$WORK/s3/drafts/draft-theory-t.md"
bash "$GATE" "$WORK/s3" --phase 7 >/dev/null 2>&1
[ $? -eq 2 ] && pass "P7 YELLOW: cite-key adjacency mismatch (presence != relevance)" || fail "P7 adjacency check"

mkdir -p "$WORK/s4/evidence" "$WORK/s4/drafts"        # YELLOW: low coverage
printf '%s\n' "$A7" > "$WORK/s4/evidence/claim-anchors.ndjson"
printf 'First (Autor et al. 2013). <!--ev: autor2013-3f9a1c2e-->\nSecond untagged (Smith 2020).\nThird untagged (Jones 2019).\n' > "$WORK/s4/drafts/draft-discussion-t.md"
bash "$GATE" "$WORK/s4" --phase 7 >/dev/null 2>&1
[ $? -eq 2 ] && pass "P7 YELLOW: tag coverage below threshold" || fail "P7 coverage check"
SCHOLAR_EVIDENCE_TAG_COVERAGE_MIN=30 bash "$GATE" "$WORK/s4" --phase 7 >/dev/null 2>&1
[ $? -eq 0 ] && pass "P7 threshold env var respected" || fail "P7 env threshold"

mkdir -p "$WORK/s5/drafts"                            # INERT: legacy
printf 'x (Smith 2020).\n' > "$WORK/s5/drafts/draft-intro-t.md"
bash "$GATE" "$WORK/s5" --phase 7 >/dev/null 2>&1
[ $? -eq 3 ] && pass "P7 INERT: legacy project" || fail "P7 legacy path"

# ── T7: check-claim-audit-consistency.sh (Slice C) ───────────────
echo ""
echo "Test 7: check-claim-audit-consistency.sh"
CONS="$REPO_ROOT/scripts/gates/check-claim-audit-consistency.sh"
AUDIT_OK='{"schema":"claim-audit-record/v1","claim_id":"c1","cite_key":"autor2013","manuscript_loc":"m.md:3","manuscript_quote":"q","claim_fingerprint":null,"citation_function":"empirical","anchor_refs":["autor2013-3f9a1c2e"],"sub_claims":[{"kind":"direction","verdict":"SUPPORTED","evidence_quote":"reduces employment","source_loc":"p.1","access_tier":"T1_fulltext"}],"sentence_verdict":"CLAIM-VERIFIED","severity":"OK","access_tier_max":"T1_fulltext","evidence_retrieved":true,"confidence":0.9}'
printf '%s\n' "$AUDIT_OK" > "$WORK/a-ok.ndjson"
bash "$CONS" "$WORK/a-ok.ndjson" >/dev/null 2>&1
[ $? -eq 0 ] && pass "consistency GREEN on canonical record" || fail "consistency GREEN path"
printf '%s\n' "$AUDIT_OK" | jq -c '.sentence_verdict="CLAIM-REVERSED" | .severity="MED" | .sub_claims[0].verdict="CONTRADICTED"' > "$WORK/a-r3.ndjson"
bash "$CONS" "$WORK/a-r3.ndjson" >/dev/null 2>&1
[ $? -eq 1 ] && pass "R3 RED: non-canonical severity" || fail "R3 severity map"
printf '%s\n' "$AUDIT_OK" | jq -c '.sentence_verdict="CLAIM-UNSUPPORTED" | .severity="HIGH" | .access_tier_max="T3_abstract" | .sub_claims[0].verdict="NOT_FOUND" | .sub_claims[0].evidence_quote=null' > "$WORK/a-r5.ndjson"
bash "$CONS" "$WORK/a-r5.ndjson" >/dev/null 2>&1
[ $? -eq 1 ] && pass "R5 RED: UNSUPPORTED without full text (precision rule)" || fail "R5 precision rule"
printf '%s\n' "$AUDIT_OK" | jq -c '.sub_claims[0].evidence_quote=null' > "$WORK/a-r4.ndjson"
bash "$CONS" "$WORK/a-r4.ndjson" >/dev/null 2>&1
[ $? -eq 1 ] && pass "R4 RED: SUPPORTED verdict without evidence_quote" || fail "R4 quote rule"

# ── T8: --phase 8 and --phase 11-entry (Slice C) ─────────────────
echo ""
echo "Test 8: evidence-anchor-check.sh --phase 8 / --phase 11-entry"
A8='{"schema":"claim-anchor/v1","anchor_id":"autor2013-3f9a1c2e","cite_key":"autor2013","claim_kind":"prose_sentence","stance":"supports","evidence_quote":"q","evidence_form":"source_verbatim","access_tier":"T1_fulltext","produced_by":"scholar-write","ts":"t"}'
S8='Trade exposure reduced employment (Autor et al. 2013). <!--ev: autor2013-3f9a1c2e-->'
FP8=$(python3 -c "
import hashlib,re
s='Trade exposure reduced employment (Autor et al. 2013).'
print(hashlib.sha256(re.sub(r'\s+',' ',s.lower()).strip().encode()).hexdigest())")
AUD8=$(printf '%s\n' "$AUDIT_OK" | jq -c --arg fp "$FP8" '.claim_fingerprint=$fp | .manuscript_quote="Trade exposure reduced employment (Autor et al. 2013)."')

mk8() { mkdir -p "$1/evidence" "$1/drafts" "$1/logs"
  printf '%s\n' "$A8" > "$1/evidence/claim-anchors.ndjson"
  printf '## Theory\n%s\n' "$S8" > "$1/drafts/manuscript-final-t-2026-08-12.md"
  echo s > "$1/logs/project-state.md"; }

mk8 "$WORK/h1"                                          # no audit, orchestrated → RED
bash "$GATE" "$WORK/h1" --phase 8 >/dev/null 2>&1
[ $? -eq 1 ] && pass "P8 RED: skipped audit is no longer invisible" || fail "P8 missing-audit path"

mk8 "$WORK/h2"; printf '%s\n' "$AUD8" > "$WORK/h2/evidence/claim-faithfulness-audit-2026-08-12.ndjson"
bash "$GATE" "$WORK/h2" --phase 8 >/dev/null 2>&1
[ $? -eq 0 ] && pass "P8 GREEN: consistent audit, covered, no HIGHs" || fail "P8 GREEN path"

mk8 "$WORK/h3"; printf '%s\n' "$AUD8" | jq -c '.sentence_verdict="CLAIM-REVERSED" | .severity="HIGH" | .sub_claims[0].verdict="CONTRADICTED"' > "$WORK/h3/evidence/claim-faithfulness-audit-2026-08-12.ndjson"
bash "$GATE" "$WORK/h3" --phase 8 >/dev/null 2>&1
[ $? -eq 1 ] && pass "P8 RED: HIGH-severity audit record blocks" || fail "P8 HIGH path"

# This repo ships without resolve-canonical-draft.sh (no in-repo Phase-11
# orchestrator — see CLAUDE.md), so the 11-entry reconciliation mode must
# degrade to INERT rather than resolve a draft by newest-glob.
mk8 "$WORK/h4"; printf '%s\n' "$AUD8" > "$WORK/h4/evidence/claim-faithfulness-audit-2026-08-12.ndjson"
bash "$GATE" "$WORK/h4" --phase 11-entry >/dev/null 2>&1
[ $? -eq 3 ] && pass "P11 INERT: degrades safely without the canonical-draft resolver" || fail "P11 resolver-absent degradation"

mkdir -p "$WORK/h6/evidence" "$WORK/h6/drafts"          # no audit → INERT
printf '%s\n' "$A8" > "$WORK/h6/evidence/claim-anchors.ndjson"
printf '%s\n' "$S8" > "$WORK/h6/drafts/manuscript-final-t-2026-08-12.md"
bash "$GATE" "$WORK/h6" --phase 11-entry >/dev/null 2>&1
[ $? -eq 3 ] && pass "P11 INERT: no audit (legacy)" || fail "P11 INERT path"

# ── T9: producer-skill integration pointers (Slices A/B/D1) ──────
echo ""
echo "Test 9: producer skills reference the shared protocol"
for sk in scholar-lit-review scholar-lit-review-hypothesis scholar-write \
          scholar-citation scholar-hypothesis scholar-conceptual \
          scholar-respond scholar-brainstorm scholar-idea \
          scholar-auto-research; do
  hits=$(grep -rl "evidence-ledger.md" "$REPO_ROOT/.claude/skills/$sk/" 2>/dev/null | wc -l | tr -d ' ')
  [ "$hits" -ge 1 ] && pass "$sk references _shared/evidence-ledger.md" \
                    || fail "$sk missing evidence-ledger.md pointer"
done
grep -q '`Evidence anchors: N created / M reused`' "$REPO_ROOT/.claude/skills/scholar-write/SKILL.md" 2>/dev/null \
  || grep -q 'Evidence anchors: \[N\] created' "$REPO_ROOT/.claude/skills/scholar-write/SKILL.md" 2>/dev/null \
  && pass "scholar-write writing-log carries the required anchors row" \
  || fail "scholar-write log row missing"
grep -q 'Preserve all inline HTML comments' "$REPO_ROOT/.claude/skills/scholar-polish/SKILL.md" 2>/dev/null \
  && pass "scholar-polish Absolute Rule 6 (preserve ev bindings) present" \
  || fail "scholar-polish preserve rule missing"

echo ""
# ── Phase-8 audit-existence is INDEPENDENT of ledger-emptiness (P17-A) ──────
# Until 2026-08-27 the empty-ledger branch exited YELLOW before $AUDIT — which
# had already been computed one line above — was ever consulted. So "was the
# faithfulness audit produced?" was gated on "is the ledger non-empty?". Since
# phase-verify maps exit 2 to WARNINGS++ and prints "PASS with N warning(s)",
# the only check in the suite that reads a cited source's actual text could be
# skipped end to end on a passing phase.
EVG="$GATE"
if [ ! -f "$EVG" ]; then
  fail "evidence-anchor-check.sh not found — cannot assert Phase 8 audit wiring"
else
  _ev_case() {  # <name> <ledger:empty|full> <orchestrated:0|1> <audit:0|1> -> dir
    local d="$WORK/ev-$1"; mkdir -p "$d/evidence" "$d/logs"
    if [ "$2" = "full" ]; then
      printf '%s\n' '{"schema":"claim-anchor/v1","anchor_id":"a1","cite_key":"k","doi":null,"source_title":"T","claim_kind":"theory_attribution","stance":"supports","claim_text":null,"claim_loc":null,"hypothesis_id":null,"evidence_quote":null,"evidence_context":null,"evidence_form":"metadata_only","quote_sha256":null,"source_loc":null,"locator_type":"none","access_tier":"T4_none","retrieval":{},"produced_by":"scholar-citation","phase":"8","ts":"2026-08-27T00:00:00Z","supersedes":null}' \
        > "$d/evidence/claim-anchors.ndjson"
    else
      : > "$d/evidence/claim-anchors.ndjson"
    fi
    [ "$3" = "1" ] && printf 'state\n' > "$d/logs/project-state.md"
    [ "$4" = "1" ] && printf '{"schema":"claim-audit-record/v1"}\n' > "$d/evidence/claim-faithfulness-audit-2026-08-27.ndjson"
    printf '%s' "$d"
  }
  _ev_rc() { bash "$EVG" "$1" --phase 8 >/dev/null 2>&1; echo $?; }

  # Pre-existing RED must be preserved exactly (the change is severity-additive).
  RC=$(_ev_rc "$(_ev_case red full 1 0)")
  [ "$RC" = "1" ] && pass "orchestrated + anchors + no audit still REDs (unchanged)" \
                  || fail "orchestrated + anchors + no audit should RED, got rc=$RC"

  # The newly-visible case: an empty ledger no longer HIDES the missing audit.
  D_EMPTY="$(_ev_case empty empty 1 0)"
  RC=$(_ev_rc "$D_EMPTY")
  [ "$RC" = "2" ] && pass "orchestrated + empty ledger + no audit is advisory by default" \
                  || fail "expected YELLOW(2) for empty-ledger missing audit, got rc=$RC"
  OUT=$(bash "$EVG" "$D_EMPTY" --phase 8 2>&1 || true)
  if printf '%s' "$OUT" | grep -q "no claim-faithfulness audit was produced on an orchestrated run"; then
    pass "the missing audit is NAMED, not hidden behind 'coverage cannot be assessed'"
  else
    fail "empty-ledger path does not report the missing faithfulness audit"
  fi
  if printf '%s' "$OUT" | grep -q "audit COVERAGE cannot be assessed"; then
    pass "coverage-unassessable is still reported as its own separate fact"
  else
    fail "coverage-unassessable fact was dropped"
  fi
  RC=$(SCHOLAR_FAITHFULNESS_ENFORCE=1 bash "$EVG" "$D_EMPTY" --phase 8 >/dev/null 2>&1; echo $?)
  [ "$RC" = "1" ] && pass "SCHOLAR_FAITHFULNESS_ENFORCE=1 promotes it to RED" \
                  || fail "enforce flag did not promote to RED, got rc=$RC"

  # A standalone (non-orchestrated) run must NOT be newly failed.
  RC=$(_ev_rc "$(_ev_case standalone empty 0 0)")
  [ "$RC" = "2" ] && pass "standalone run unaffected (no retroactive failure)" \
                  || fail "standalone run changed verdict, got rc=$RC"

  # An audit with no ledger must report what it could not assess, never clean.
  OUT=$(bash "$EVG" "$(_ev_case auditonly empty 1 1)" --phase 8 2>&1 || true)
  if printf '%s' "$OUT" | grep -q "audit coverage cannot be assessed"; then
    pass "audit-present + no ledger reports unassessed coverage rather than passing clean"
  else
    fail "audit-present + no ledger did not disclose unassessable coverage"
  fi
fi

echo "════════════════════"
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  echo ">>> FAILED"
  exit 1
fi
echo ">>> PASSED"
exit 0
