#!/usr/bin/env bash
# test-refmanager-fn-names.sh — every scholar_search_* call in a skill must
# name a function _shared/refmanager-backends.md actually defines.
#
# WHY (2026-08-26): scholar-brainstorm called `scholar_search_crossref` and
# `scholar_search_s2`; the backends file ships only the `_keyword`/`_author`
# variants. A bare name is "command not found" — swallowed by the
# `2>/dev/null` on the eval that loads the block — so the external-API tier
# silently returned nothing and the RQ read as having no external coverage.
# The same class was found independently in the public fork's scholar-idea.
# A search tier that fails silently is the worst kind: it looks like
# evidence of absence.
#
# NOTE: the detection pass is python (a shell prepass with an apostrophe in
# its character class broke the heredoc — caught by this file's own first
# run). Keep it that way.
set -uo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BACKENDS="$REPO_ROOT/.claude/skills/_shared/refmanager-backends.md"
PASS=0; FAIL=0
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }
[ -f "$BACKENDS" ] || { echo "  FAIL: refmanager-backends.md missing"; exit 1; }

DEFINED="$(grep -oE '^scholar_search[a-z_]*\(\)' "$BACKENDS" | sed 's/()//' | sort -u)"
DEF_N=$(printf '%s\n' "$DEFINED" | grep -c . || true)
if [ "$DEF_N" -ge 10 ]; then
  pass "backends file defines $DEF_N scholar_search_* functions"
else
  fail "only $DEF_N definitions parsed — fix the extractor before trusting this test"
fi

UNDEF="$(DEFINED="$DEFINED" REPO_ROOT="$REPO_ROOT" python3 - <<'PY'
import os, re
root = os.path.join(os.environ["REPO_ROOT"], ".claude", "skills")
defined = set(os.environ["DEFINED"].split())
backends = os.path.abspath(os.path.join(root, "_shared", "refmanager-backends.md"))
# A CALL is the name followed by whitespace and an argument opener.
call_rx = re.compile(r"\b(scholar_search[a-z_]*)[ \t]+(?=[\"'$\[\w])")
bad = set()
for dirpath, _dirs, files in os.walk(root):
    for fn in files:
        if not fn.endswith(".md"):
            continue
        p = os.path.join(dirpath, fn)
        if os.path.abspath(p) == backends:
            continue
        try:
            txt = open(p, encoding="utf-8", errors="replace").read()
        except OSError:
            continue
        for m in call_rx.finditer(txt):
            if m.group(1) not in defined:
                bad.add("%s -> %s" % (os.path.relpath(p, root), m.group(1)))
for b in sorted(bad):
    print(b)
PY
)"
if [ -z "$UNDEF" ]; then
  pass "every scholar_search_* call in every skill names a defined function"
else
  fail "undefined refmanager function(s) called — these fail SILENTLY at runtime:"
  printf '%s\n' "$UNDEF" | sed 's/^/      /'
fi

# Self-check: the detector must actually catch a planted bad call.
TMPD="$(mktemp -d -t rfn.XXXXXX)"; trap 'rm -rf "$TMPD"' EXIT
mkdir -p "$TMPD/skills/_shared" "$TMPD/skills/fake"
cp "$BACKENDS" "$TMPD/skills/_shared/refmanager-backends.md"
printf 'run: scholar_search_nonexistent "kw" 10\n' > "$TMPD/skills/fake/SKILL.md"
PLANTED="$(DEFINED="$DEFINED" REPO_ROOT="$TMPD" python3 - <<'PY'
import os, re
root = os.path.join(os.environ["REPO_ROOT"], "skills")
defined = set(os.environ["DEFINED"].split())
backends = os.path.abspath(os.path.join(root, "_shared", "refmanager-backends.md"))
call_rx = re.compile(r"\b(scholar_search[a-z_]*)[ \t]+(?=[\"'$\[\w])")
bad = set()
for dirpath, _dirs, files in os.walk(root):
    for fn in files:
        if not fn.endswith(".md"):
            continue
        p = os.path.join(dirpath, fn)
        if os.path.abspath(p) == backends:
            continue
        txt = open(p, encoding="utf-8", errors="replace").read()
        for m in call_rx.finditer(txt):
            if m.group(1) not in defined:
                bad.add(m.group(1))
print(",".join(sorted(bad)))
PY
)"
if [ "$PLANTED" = "scholar_search_nonexistent" ]; then
  pass "detector catches a planted undefined call (not vacuously green)"
else
  fail "detector missed a planted undefined call (got '$PLANTED') — this test proves nothing"
fi

echo ""
echo "════════════════════"
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
