#!/usr/bin/env bash
# Citation Existence Verifier — Phase 8 hard gate
# Usage: bash scripts/gates/verify-citation-existence.sh <manuscript> <bibfile>
#
# Catches LLM citation hallucinations: in-text "(Author Year)" or
# "(Author1 & Author2 Year)" or "(Author1 et al. Year)" references that
# have NO matching @entry in the bibliography. citation-bib-completeness.sh
# only catches LaTeX/pandoc-citeproc keys ([@key], \cite{key}); this gate
# catches the ASA/APA author-date pattern that sociology journals use.
#
# Match logic:
#   1. Parse every (Author Year) / (Author et al. Year) / (Author1 & Author2 Year)
#      pattern from the manuscript body, exclude fenced code blocks and
#      block quotes.
#   2. Parse every @entry{KEY,...} from the bib: extract first-author surname
#      + year from `author = {...}` and `year = {...}` fields.
#   3. For each in-text citation, check whether any bib entry matches
#      (first-author-surname-lowercased, year). Allow 4-letter prefix
#      tolerance for variant spellings.
#   4. Emit per-citation status: VERIFIED / UNRESOLVED.
#
# Exit codes:
#   0 — GREEN  (every in-text citation resolves to a bib entry)
#   1 — RED    (>=1 in-text citation has no matching bib entry)
#   2 — YELLOW (manuscript has no parseable in-text citations — advisory)

set -euo pipefail

if [ $# -lt 2 ]; then
  echo "Usage: verify-citation-existence.sh <manuscript> <bibfile>" >&2
  exit 1
fi

MS="$1"
BIB="$2"

if [ ! -f "$MS" ]; then
  echo "STATUS=RED"
  echo "FAIL: manuscript not found: $MS"
  exit 1
fi
if [ ! -f "$BIB" ]; then
  echo "STATUS=RED"
  echo "FAIL: bibfile not found: $BIB"
  exit 1
fi

CIT_TMP=$(mktemp)
BIB_INDEX=$(mktemp)
UNRESOLVED=$(mktemp)
PY_SCRIPT=$(mktemp --suffix=.py 2>/dev/null || mktemp -t verify-cit-XXXXXX.py)
trap 'rm -f "$CIT_TMP" "$BIB_INDEX" "$UNRESOLVED" "$PY_SCRIPT"' EXIT

# 1. Write the citation+bib parser as a separate Python script (avoids
#    the bash quoting hazards of an inline `python3 -c`).
cat > "$PY_SCRIPT" <<'PYEOF'
import re, sys

ms_path  = sys.argv[1]
bib_path = sys.argv[2]
mode     = sys.argv[3]   # "cites" or "bib"

if mode == "cites":
    with open(ms_path, encoding="utf-8") as f:
        text = f.read()
    # Strip fenced code blocks and block-quoted lines.
    out = []
    in_fence = False
    for line in text.splitlines():
        if line.startswith("```"):
            in_fence = not in_fence
            continue
        if in_fence: continue
        if line.startswith(">"): continue
        out.append(line)
    text = "\n".join(out)

    SURNAME = r"[A-Z][A-Za-z\u00C0-\u017F\u2019\-]+"
    YEAR    = r"(?:19|20)\d{2}[a-z]?"
    pat = re.compile(
        r"\("                           # opening paren
        + r"(" + SURNAME + r")"         # 1st author surname (group 1)
        + r"(?:[,\s]+(?:and|&|et\s+al\.?)\s*[,\s]*" + SURNAME + r"?)*"
        + r"(?:[,\s]+(?:and|&)\s+" + SURNAME + r")?"
        + r"[,;\s]+"
        + r"(" + YEAR + r")"            # year (group 2)
        + r"(?:[,;:][^)]*)?"            # optional page/note tail
        + r"\)"
    )
    seen = set()
    for m in pat.finditer(text):
        surname = re.sub(r"[^A-Za-z]", "", m.group(1)).lower()
        year    = m.group(2)[:4]
        key = f"{surname}|{year}"
        if key in seen: continue
        seen.add(key)
        sample = m.group(0).replace("\t", " ").replace("\n", " ")
        print(f"{surname}\t{year}\t{sample}")

elif mode == "bib":
    with open(bib_path, encoding="utf-8") as f:
        txt = f.read()
    entries = re.findall(r"@\w+\{[^@]+", txt)
    seen = set()

    def get_field(body, field):
        # Brace-DEPTH walk, not a character class. The previous extractor was
        # r"author\s*=\s*[\{\"]([^\}\"]+)" — that class excludes `}` and `"` but
        # NOT `{`, so `author = {Bj{\"o}rn Nilsson}` captured `Bj{\` and yielded
        # surname "bj". A correctly-cited reference was then reported as "likely
        # LLM-fabricated or mis-attributed" (reproduced end-to-end 2026-08-27).
        # Brace-protected capitalization (`title = {... {China}}`) and any LaTeX
        # accent hit the same edge. Ported verbatim from the walker already
        # shipping in verify-citation-local-library.sh:196-211 rather than
        # written fresh — that one is proven and this must not diverge from it.
        m = re.search(r"\b" + re.escape(field) + r"\s*=\s*([{\"])", body, re.IGNORECASE)
        if not m:
            return None
        # The delimiter that OPENED the value decides what closes it. Brace-depth
        # walking a quote-delimited field (`author = "Jane Smith",`) never finds a
        # `}` and runs past the closing quote into the following fields — which is
        # what the first version of this port did, regressing quoted-style .bib
        # files that the old regex handled correctly. (Caught by Codex review
        # 2026-08-27; the same defect is present in the walker this was ported
        # from, verify-citation-local-library.sh:196-211 — reported separately.)
        opener = m.group(1)
        k = m.end()
        if opener == '"':
            while k < len(body):
                if body[k] == '"' and body[k - 1] != "\\":
                    break
                k += 1
            val = body[m.end():k].strip()
        else:
            depth = 1
            while k < len(body) and depth > 0:
                ch = body[k]
                if ch == "{":
                    depth += 1
                elif ch == "}":
                    depth -= 1
                k += 1
            val = body[m.end():k - 1].strip()
        # Fold LaTeX accents to their base letter so `Bj{\"o}rn` matches `Bjorn`.
        val = re.sub(r"\\['\"`^~=.bcdHkruv]\{?([A-Za-z])\}?", r"\1", val)
        return val.replace("{", "").replace("}", "").strip() or None

    for e in entries:
        authors = get_field(e, "author")
        ym = re.search(r"year\s*=\s*[\{\"]?(\d{4})", e, re.IGNORECASE)
        if not authors or not ym: continue
        year = ym.group(1)
        first = re.split(r"\s+and\s+", authors, maxsplit=1)[0].strip()
        if "," in first:
            last = first.split(",", 1)[0].strip()
        else:
            tokens = first.split()
            last = tokens[-1] if tokens else ""
        last = re.sub(r"[^A-Za-z]", "", last).lower()
        if last and year:
            key = f"{last}\t{year}"
            if key not in seen:
                seen.add(key)
                print(key)
PYEOF

# 2. Extract in-text citations.
python3 "$PY_SCRIPT" "$MS" "$BIB" cites > "$CIT_TMP" || true
N_CITES=$(wc -l < "$CIT_TMP" | tr -d ' ')

# Count numbered/citeproc citations too (so callers can decide which verifier
# to dispatch). Detects [N], [N,N], [N-N], [@key], \cite{key}, \citep{key}.
# Audit 2026-05-02 (F6): the gate previously YELLOWed with a generic advisory
# when no author-year cites were found, which let Nature/PNAS manuscripts
# pass uncheck​ed. Reporting N_NUMBERED_CITES makes the silent gap loud.
N_NUMBERED_CITES=$( { grep -oE '\[[0-9]+(,\s*[0-9]+|\s*-\s*[0-9]+)*\]|\[@[A-Za-z][A-Za-z0-9_:.-]*\]|\\cite[pt]?\{[^}]+\}' "$MS" 2>/dev/null || true; } | wc -l | tr -d ' ')
N_NUMBERED_CITES=${N_NUMBERED_CITES:-0}

if [ "$N_CITES" -eq 0 ]; then
  if [ "$N_NUMBERED_CITES" -gt 0 ]; then
    echo "STATUS=RED"
    echo "MANUSCRIPT=$MS"
    echo "BIBFILE=$BIB"
    echo "INTEXT_CITATIONS=0"
    echo "N_NUMBERED_CITES=$N_NUMBERED_CITES"
    echo "FAIL: 0 (Author Year) citations parsed, BUT $N_NUMBERED_CITES numbered/citeproc citations detected."
    echo "  This gate targets ASA/APA author-date style. The manuscript uses a numbered citation style"
    echo "  (Nature/PNAS/Science) — verify-citation-existence.sh cannot validate them."
    echo "  REQUIRED: run \`bash scripts/gates/citation-bib-completeness.sh ${MS} ${BIB}\` instead."
    echo "  The author-year gate is not authoritative for this manuscript and silently passing"
    echo "  it would leave numbered cites unverified — a known false-negative vector."
    exit 1
  fi
  echo "STATUS=YELLOW"
  echo "MANUSCRIPT=$MS"
  echo "INTEXT_CITATIONS=0"
  echo "N_NUMBERED_CITES=0"
  echo "ADVISORY: no parseable in-text citations of any kind found in manuscript prose."
  echo "  If the manuscript is fully cited but uses an unrecognized format, contact maintainers"
  echo "  to extend the regex. Otherwise, ensure the draft has been through Phase 8 (citation harmonization)."
  exit 2
fi

# 3. Build bib index.
python3 "$PY_SCRIPT" "$MS" "$BIB" bib | sort -u > "$BIB_INDEX"
N_BIB_ENTRIES=$(wc -l < "$BIB_INDEX" | tr -d ' ')

# 4. Cross-check each in-text citation against the bib index.
RESOLVED_COUNT=0
UNRESOLVED_COUNT=0
: > "$UNRESOLVED"

while IFS=$'\t' read -r surname year sample; do
  [ -z "$surname" ] && continue
  matched=0
  while IFS=$'\t' read -r bib_last bib_year; do
    [ "$bib_year" = "$year" ] || continue
    if [ "$bib_last" = "$surname" ]; then
      matched=1; break
    fi
    # 4-letter prefix tolerance only when both exceed 4 chars to avoid
    # false positives on short surnames (Wu, Hu, Yu).
    if [ "${#surname}" -ge 4 ] && [ "${#bib_last}" -ge 4 ]; then
      case "$bib_last" in "$surname"*) matched=1; break ;; esac
      case "$surname" in "$bib_last"*) matched=1; break ;; esac
    fi
  done < "$BIB_INDEX"

  if [ "$matched" -eq 1 ]; then
    RESOLVED_COUNT=$((RESOLVED_COUNT + 1))
  else
    UNRESOLVED_COUNT=$((UNRESOLVED_COUNT + 1))
    printf '%s\t%s\t%s\n' "$surname" "$year" "$sample" >> "$UNRESOLVED"
  fi
done < "$CIT_TMP"

echo "MANUSCRIPT=$MS"
echo "BIBFILE=$BIB"
echo "BIB_ENTRIES=$N_BIB_ENTRIES"
echo "INTEXT_CITATIONS=$N_CITES"
echo "RESOLVED=$RESOLVED_COUNT"
echo "UNRESOLVED=$UNRESOLVED_COUNT"

if [ "$UNRESOLVED_COUNT" -gt 0 ]; then
  echo "STATUS=RED"
  echo ""
  echo "FAIL: $UNRESOLVED_COUNT in-text citation(s) have no matching @entry in $BIB."
  echo "These are likely LLM-fabricated or mis-attributed citations."
  echo ""
  echo "Unresolved (first 20):"
  head -20 "$UNRESOLVED" | awk -F'\t' '{printf "  - %s %s   [%s]\n", $1, $2, $3}'
  if [ "$UNRESOLVED_COUNT" -gt 20 ]; then
    echo "  ... ($((UNRESOLVED_COUNT - 20)) more)"
  fi
  echo ""
  echo "Remediation (Phase 8 contract):"
  echo "  1. Verify each citation via CrossRef / Semantic Scholar / OpenAlex."
  echo "  2. If verified: add the @entry to $BIB."
  echo "  3. If unverifiable: replace with a verified substitute OR mark with"
  echo "     [SOURCE NEEDED] inline (preserved per feedback_preserve_ai_failure_cases.md)."
  echo "  4. Re-run this gate. Do NOT advance to Phase 9 with unresolved citations."
  exit 1
fi

echo "STATUS=GREEN"
echo "PASS: every in-text (Author Year) citation resolves to a bib entry."
exit 0
