#!/usr/bin/env bash
# Phase 18 quality-gate probe (audit 2026-05-02 + 2026-05-03).
#
# Five static-pattern checks on auto-research-verify.sh's Phase 18
# reviewer_reports validation block:
#
#   F1  (2026-08-26) Reviewer entries require a nonempty host-neutral
#       agent_name; role identity is enforced by the registered review-evidence
#       policy. Provider-specific peer-reviewer-* prefixes are prohibited.
#
#   F2  (2026-05-02) Per-reviewer task_invocation_id must be checked
#       against placeholder_values.  Mirrors validate_engine_provenance
#       (line 254) and Phase 7 line 2520.
#
#   F3  (2026-05-03 — Improvement A) Each reviewer must carry a
#       contribution_locator with sentences[] (≥1 entry, ≥10 words each)
#       and clarity/specificity scores ≥7.  Catches buried/vacuous
#       contribution claims that pass mechanical coverage gates.
#
#   F4  (2026-05-03 — Improvement A) Phase 18 must compute
#       cross-reviewer consensus on contribution_locator sentences using
#       Jaccard token overlap ≥0.7 across at least one pair of
#       reviewers.  Catches manuscripts where independent reviewers
#       can't agree on what the contribution IS.
#
#   F5  (2026-05-03 — Improvement B) Each reviewer must carry a
#       rival_adjudication with rivals_in_lit_review[] and
#       missing_adjudications[].  Phase 18 must aggregate and block
#       when ≥2 reviewers flag the same rival as un-adjudicated in the
#       discussion.
#
# This probe is a static pattern check on verify.sh's Phase 18
# reviewer-validation block.  It does NOT execute the verifier
# (which would require an 8-phase upstream cascade fixture).
#
# Pre-fix: F3/F4/F5 patterns absent → exits 1 (RED).
# Post-fix: all five patterns present → exits 0 (GREEN).

set -uo pipefail

SKILL_DIR="${SCHOLAR_AUTO_RESEARCH_TEST_SKILL_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
VERIFY_SH="${SKILL_DIR}/scripts/auto-research-verify.sh"

[ -f "$VERIFY_SH" ] || { echo "FATAL: missing $VERIFY_SH"; exit 1; }

PASS=0; FAIL=0
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; [ -n "${2:-}" ] && echo "    detail: $2"; }

# Do not implement these predicates as `printf ... | grep -q` while pipefail is
# active.  On a large block grep exits as soon as it finds an early match;
# printf then receives SIGPIPE and makes the successful predicate return 141.
block_matches() {
  local block="$1"
  local pattern="$2"
  grep -qE "$pattern" <<< "$block"
}

# ── Locate the Phase 18 reviewer_reports validation block ────────────
# F1/F2/F3/F5 are per-entry checks, F4 is a cross-reviewer aggregation
# check.  Both live under `if phase_id == "18":` and span from the
# per-reviewer loop opener to the first `if reviewer_issues:` / fail()
# call after the loop.
#
# We extract two views:
#   PHASE18_PER_REVIEWER  — the per-entry loop body (for F1/F2/F3/F5)
#   PHASE18_AGGREGATE     — everything from "if phase_id == 18" through
#                           the first dimension_scores reference
#                           (for F4 — consensus check is post-loop)
# Audit 2026-05-29: read the gate source ONCE and derive both block views
# from the in-memory copy. Previously each view ran a SEPARATE
# `awk "$VERIFY_SH"` over this large (~300KB) file; on a cloud-synced mount
# under concurrent full-suite I/O the two reads occasionally returned
# divergent content, so F4 (which reads PHASE18_AGGREGATE) alone false-FAILed
# while F1–F3/F5 (which read PHASE18_PER_REVIEWER) passed. A single shared
# read guarantees every check sees the same bytes; the retry absorbs a
# transient empty read, and a persistently-empty result is reported as an
# infra error rather than a misleading Phase 18 content failure.
# Audit 2026-08-20: the single-read fix above reduced the false-FAIL rate but
# did not close it — F4 false-FAILed again under a full-suite run while F1–F3/F5
# passed, the same asymmetric signature. Cause: the guard only asserted the read
# was NON-EMPTY. On this 683KB file on a Dropbox mount a read can come back
# SHORT — long enough to contain the per-reviewer block (so F1–F3/F5 pass) but
# truncated before the post-loop aggregate block (so F4 alone fails). A partial
# read passes a `-n` test perfectly. The guard now demands COMPLETENESS: the
# captured byte count must match the file's own size, and the aggregate block's
# sentinel must actually be present, before any assertion runs.
_vc_size="$(wc -c < "$VERIFY_SH" 2>/dev/null | tr -d ' ')"
_vc_size="${_vc_size:-0}"
VERIFY_CONTENT=""
_vc_got=0
for _vc_try in 1 2 3 4 5; do
  VERIFY_CONTENT="$(cat "$VERIFY_SH" 2>/dev/null)"
  _vc_got="$(printf '%s' "$VERIFY_CONTENT" | wc -c | tr -d ' ')"
  _vc_got="${_vc_got:-0}"
  # Command substitution strips trailing newlines, so allow a few bytes of slack.
  if [ "$_vc_got" -gt 0 ] && [ "$_vc_size" -gt 0 ] \
     && [ "$_vc_got" -ge "$((_vc_size - 8))" ]; then
    break
  fi
  sleep 1
done
unset _vc_try
if [ -n "$VERIFY_CONTENT" ] && [ "$_vc_size" -gt 0 ] \
   && [ "$_vc_got" -lt "$((_vc_size - 8))" ]; then
  fail "infra: short read of $VERIFY_SH ($_vc_got of $_vc_size bytes after 5 attempts)" \
       "a truncated cloud-mount read drops the Phase 18 aggregate block and would surface as a bogus F4 content failure"
  echo ""
  echo "=== quality-gate probe summary ==="
  echo "PASS: $PASS"
  echo "FAIL: $FAIL"
  exit 1
fi
if [ -z "$VERIFY_CONTENT" ]; then
  fail "infra: could not read $VERIFY_SH after 5 attempts (empty content)" \
       "cloud-mount read returned empty — this is an I/O issue, not a Phase 18 content failure"
  echo ""
  echo "=== quality-gate probe summary ==="
  echo "PASS: $PASS"
  echo "FAIL: $FAIL"
  exit 1
fi

# Harness regression: VERIFY_CONTENT is deliberately large and its shebang is
# an early match, the exact shape that made the former pipeline nondeterministic.
if block_matches "$VERIFY_CONTENT" '^#!/usr/bin/env bash'; then
  pass "harness: large-block early matches are stable under pipefail"
else
  fail "harness: large-block early match returned false under pipefail"
fi
if block_matches "$VERIFY_CONTENT" '__AUTO_RESEARCH_QUALITY_GATE_MISSING_SENTINEL__'; then
  fail "harness: matcher accepted a controlled missing token"
else
  pass "harness: controlled missing tokens remain negative"
fi

PHASE18_PER_REVIEWER="$(printf '%s\n' "$VERIFY_CONTENT" | awk '
  /^if phase_id == "18":/         { in18=1 }
  in18 && /for idx, reviewer in enumerate\(reviewers\):/ { capture=1 }
  capture                          { print }
  capture && /if reviewer_issues:/ { exit }
')"

PHASE18_AGGREGATE="$(printf '%s\n' "$VERIFY_CONTENT" | awk '
  /^if phase_id == "18":/         { in18=1 }
  in18                              { print }
  in18 && /required_dimensions = \[/ { exit }
')"

if [ -z "$PHASE18_PER_REVIEWER" ]; then
  fail "could not locate Phase 18 per-reviewer block in $VERIFY_SH" \
       "static-pattern probe requires the block to live under 'if phase_id == \"18\":'"
  echo ""
  echo "=== quality-gate probe summary ==="
  echo "PASS: $PASS"
  echo "FAIL: $FAIL"
  exit 1
fi

# ── F1: agent_name is required without a provider-specific prefix ─────
F1_HIT=0
if block_matches "$PHASE18_PER_REVIEWER" 'agent_name[[:space:]]*=[[:space:]]*str\(reviewer\.get\("agent_name"' \
   && block_matches "$PHASE18_PER_REVIEWER" 'if not agent_name:' \
   && ! block_matches "$PHASE18_PER_REVIEWER" 'peer-reviewer-'; then
  F1_HIT=1
fi

if [ "$F1_HIT" -eq 1 ]; then
  pass "F1: Phase 18 requires host-neutral agent_name metadata without provider prefixes"
else
  fail "F1: Phase 18 agent_name validation is not host-neutral" \
       "expected a nonempty agent_name check and no peer-reviewer-* prefix requirement"
fi

# ── F2: task_invocation_id must be checked against placeholder_values ─
F2_HIT=0
if block_matches "$PHASE18_PER_REVIEWER" 'task_id'; then
  if block_matches "$PHASE18_PER_REVIEWER" 'placeholder_values|"tbd"|"todo"|"placeholder"'; then
    F2_HIT=1
  fi
fi

if [ "$F2_HIT" -eq 1 ]; then
  pass "F2: Phase 18 reviewer block rejects placeholder task_invocation_id"
else
  fail "F2: Phase 18 reviewer block does not reject placeholder task_invocation_id" \
       "expected 'task_id' check against placeholder_values OR 'tbd'/'todo'/'placeholder' literal inside the per-reviewer loop"
fi

# ── F3: contribution_locator schema enforcement ─────────────────────
# Per-reviewer block must extract contribution_locator and validate:
#   - sentences[] non-empty
#   - each sentence has minimum word count (≥10 words)
#   - clarity_score / specificity_score ≥ threshold
F3_HIT=0
if block_matches "$PHASE18_PER_REVIEWER" 'contribution_locator'; then
  # Look for sentences[] and clarity/specificity score validation
  if block_matches "$PHASE18_PER_REVIEWER" 'sentences|clarity_score|specificity_score'; then
    F3_HIT=1
  fi
fi

if [ "$F3_HIT" -eq 1 ]; then
  pass "F3: Phase 18 reviewer block validates contribution_locator (sentences + clarity/specificity scores)"
else
  fail "F3: Phase 18 reviewer block does not validate contribution_locator schema" \
       "expected 'contribution_locator' AND ('sentences' OR 'clarity_score' OR 'specificity_score') tokens inside the per-reviewer loop"
fi

# ── F4: cross-reviewer Jaccard consensus on contribution sentences ──
# Aggregate block (post per-reviewer loop) must compute Jaccard overlap
# across pairs of reviewer contribution_locator sentences and require
# ≥1 pair above threshold.
F4_HIT=0
if block_matches "$PHASE18_AGGREGATE" 'jaccard|consensus_pairs|contribution_locator_consensus'; then
  if block_matches "$PHASE18_AGGREGATE" '0\.7|threshold'; then
    F4_HIT=1
  fi
fi

if [ "$F4_HIT" -eq 1 ]; then
  pass "F4: Phase 18 computes cross-reviewer Jaccard consensus on contribution sentences"
else
  fail "F4: Phase 18 does not compute cross-reviewer consensus on contribution_locator" \
       "expected 'jaccard'/'consensus_pairs'/'contribution_locator_consensus' AND a threshold token (0.7) in the post-loop aggregate block"
fi

# ── F5: rival_adjudication aggregation ──────────────────────────────
# Per-reviewer block must extract rival_adjudication; aggregate block
# must count how many reviewers flag each rival as un-adjudicated and
# block when ≥2 reviewers flag the same rival.
F5_HIT=0
if block_matches "$PHASE18_PER_REVIEWER" 'rival_adjudication'; then
  if block_matches "$PHASE18_AGGREGATE" 'missing_adjudications|rivals_missing|rival_consensus'; then
    F5_HIT=1
  fi
fi

if [ "$F5_HIT" -eq 1 ]; then
  pass "F5: Phase 18 validates rival_adjudication and aggregates missing-rival flags across reviewers"
else
  fail "F5: Phase 18 does not aggregate rival_adjudication across reviewers" \
       "expected 'rival_adjudication' inside per-reviewer loop AND 'missing_adjudications'/'rivals_missing'/'rival_consensus' in the post-loop aggregate"
fi

# ── Sanity: confirm the closing fail() still emits an issue ──────────
if block_matches "$PHASE18_PER_REVIEWER" 'reviewer_issues\.append'; then
  pass "sanity: per-reviewer loop continues to accumulate reviewer_issues"
else
  fail "sanity: per-reviewer loop no longer accumulates reviewer_issues" \
       "fix may have stripped the issue-collection structure"
fi

echo ""
echo "=== quality-gate probe summary ==="
echo "PASS: $PASS"
echo "FAIL: $FAIL"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
