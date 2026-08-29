#!/usr/bin/env bash
set -euo pipefail

SKILL_DIR="${SCHOLAR_AUTO_RESEARCH_TEST_SKILL_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
METADATA="$SKILL_DIR/scripts/gates/verify-citation-metadata.sh"
VERIFY="$SKILL_DIR/scripts/auto-research-verify.sh"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/scholar-citation-authority.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

mkdir -p "$TMP_ROOT/project/citations"
printf '@article{legacy, title={Wrong}, author={Wrong Author}, year={2020}}\n' > "$TMP_ROOT/project/citations/references.bib"
set +e
OUT="$(bash "$METADATA" "$TMP_ROOT/project" 2>&1)"; RC=$?
set -e
[ "$RC" -eq 2 ] || { echo "FAIL: legacy-only metadata gate rc=$RC" >&2; exit 1; }
case "$OUT" in *"canonical_bib_not_found:"*"/citation/references.bib"*) ;; *) echo "FAIL: legacy citations/ path was consulted: $OUT" >&2; exit 1 ;; esac

mkdir -p "$TMP_ROOT/project/citation"
printf '@article{canonical, title={Right}, author={Right Author}, year={2020}}\n' > "$TMP_ROOT/project/citation/references.bib"
set +e
OUT="$(bash "$METADATA" "$TMP_ROOT/project" "$TMP_ROOT/project/citation/references.bib" 2>&1)"; RC=$?
set -e
case "$OUT" in *"canonical_bib_not_found"*|*"no_citations_dir"*) echo "FAIL: canonical bibliography was not resolved: $OUT" >&2; exit 1 ;; esac

python3 - "$VERIFY" <<'PY'
import sys
source = open(sys.argv[1], encoding="utf-8").read()
assert "SCHOLAR_AUTO_RESEARCH_SKIP_GATE_RECHECK" not in source
assert 'canonical_bib = proj / "citation" / "references.bib"' in source
assert 'canonical_manuscript = proj / "manuscript" / "manuscript-draft.md"' in source
assert "uncovered_keys = sorted(cited_keys - authority_covered_keys)" in source
assert source.index('if is_authority and detail.startswith("AUTHORITY_KEYS=")') < source.index('if status == "GREEN" and is_authority')
assert "rendered reconciliation requires GREEN" in source
assert "neither CrossRef metadata nor local library returned GREEN" in source
PY

echo "PASS: Phase 15 ignores legacy citations/ and resolves only canonical citation/references.bib"
echo "PASS: production policy has no skip flag and requires rendered GREEN plus per-key authority coverage"
