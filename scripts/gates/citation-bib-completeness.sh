#!/usr/bin/env bash
# Citation ↔ Bibliography Completeness — Phase 8 + Phase 11.5 cross-check
# Usage: bash scripts/gates/citation-bib-completeness.sh <manuscript> <bibfile>
#
# Checks that every citation key used in the manuscript has a matching
# entry in the bibliography file. Without this gate, pandoc --citeproc
# silently renders unresolved citekeys as literal "@foo" tokens in the
# output DOCX/PDF, producing broken references that reviewers notice.
#
# Supports two citation conventions:
#   1. Pandoc-citeproc:  [@key], [@key1; @key2], [-@key, p. 3]
#   2. LaTeX:            \cite{key}, \citep{key}, \citet{key},
#                         \cite{key1,key2}, \citeauthor{key}, \citeyear{key}
#
# The ASA/APA "(Author Year)" convention is NOT parsed — that is the
# domain of scholar-citation's audit mode (which resolves author strings
# to bib entries). This gate operates on mechanical keys only.
#
# Exits:
#   0 — GREEN  (every citekey resolves to a bib entry)
#   1 — RED    (≥1 citekey has no matching @entry{KEY,} in bibfile)
#   2 — YELLOW (unused bib entries; advisory only)

set -euo pipefail

if [ $# -lt 2 ]; then
  echo "Usage: citation-bib-completeness.sh <manuscript> <bibfile>" >&2
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

# 1. Extract citation keys from manuscript.
#    Pandoc-citeproc: [@key] or [-@key]. Keys may contain letters, digits,
#    underscore, hyphen, colon, dot (but not space, brace, bracket, comma,
#    semicolon). Strip the leading [- or [@ sigil.
#    LaTeX \cite{key,key2}: split on comma inside braces.
#
#    Pandoc pattern: -?@[A-Za-z][A-Za-z0-9_.:-]*
#
# Register a single consolidated trap up front. All three temp files are
# created below; the trap remains valid for unset variables thanks to the
# ${VAR:-} defaults.
MS_TMP="$(mktemp)"
MS_SORTED=""
BIB_SORTED=""
trap 'rm -f "$MS_TMP" "${MS_SORTED:-}" "${BIB_SORTED:-}"' EXIT

# Pandoc-style — strip the leading - or @ to get bare keys.
# Any step may return exit 1 (no matches) — guard every pipeline under set -e.
{ grep -oE '(\[-?@|; -?@|[^@a-zA-Z]-?@)[A-Za-z][A-Za-z0-9_.:-]*' "$MS" 2>/dev/null \
  | sed -E 's/^.*@//' \
  > "$MS_TMP"; } || true

# LaTeX-style — pull out the inside of \cite{...}, \citep{...}, etc.,
# then split on commas. Use multi-pass to be portable with BSD sed.
{ grep -oE '\\(cite|citep|citet|citeauthor|citeyear|citealt|citealp|parencite|textcite|autocite)\{[^}]*\}' "$MS" 2>/dev/null \
  | sed -E 's/\\[a-z]+\{//' \
  | sed -E 's/\}$//' \
  | tr ',' '\n' \
  | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' \
  | grep -E '^[A-Za-z][A-Za-z0-9_.:-]*$' \
  >> "$MS_TMP"; } || true

# Dedupe. grep -v may return 1 when the sorted output is entirely empty
# lines; guard with || true so set -e doesn't kill the script.
MS_KEYS=$(sort -u "$MS_TMP" | grep -v '^$' || true)
N_MS_KEYS=$(printf '%s\n' "$MS_KEYS" | grep -c . 2>/dev/null || true)
N_MS_KEYS=${N_MS_KEYS:-0}

if [ "$N_MS_KEYS" -eq 0 ]; then
  echo "STATUS=GREEN"
  echo "PASS: manuscript contains no machine-parseable citation keys (pandoc-citeproc or LaTeX)."
  echo "  Note: ASA/APA '(Author Year)' citations are checked by scholar-citation audit, not this gate."
  exit 0
fi

# 2. Extract bib entry keys. BibTeX entries start with @type{KEY, where
#    type is word chars and KEY is followed by a comma.
BIB_KEYS=$({ grep -oE '^[[:space:]]*@[A-Za-z]+\{[^,]+,' "$BIB" 2>/dev/null \
  | sed -E 's/^[[:space:]]*@[A-Za-z]+\{//' \
  | sed -E 's/,$//' \
  | sed -E 's/[[:space:]]//g' \
  | sort -u; } || true)

N_BIB_KEYS=$(printf '%s\n' "$BIB_KEYS" | grep -c . 2>/dev/null || true)
N_BIB_KEYS=${N_BIB_KEYS:-0}

echo "MANUSCRIPT=$MS"
echo "BIBFILE=$BIB"
echo "MANUSCRIPT_CITEKEYS=$N_MS_KEYS"
echo "BIB_ENTRIES=$N_BIB_KEYS"

# 3. Cross-check: every MS key must have a BIB entry.
#    Use comm on sorted lists.
MS_SORTED="$(mktemp)"
BIB_SORTED="$(mktemp)"
printf '%s\n' "$MS_KEYS" > "$MS_SORTED"
printf '%s\n' "$BIB_KEYS" > "$BIB_SORTED"

# Keys in MS but not in BIB — these are the broken citations.
# comm requires sorted inputs. Guard with || true because comm may exit
# non-zero on certain edge cases and set -e would otherwise terminate.
MISSING=$(comm -23 "$MS_SORTED" "$BIB_SORTED" || true)
N_MISSING=$(printf '%s\n' "$MISSING" | grep -c . 2>/dev/null || true)
N_MISSING=${N_MISSING:-0}

# Keys in BIB but not in MS — unused entries, YELLOW only.
UNUSED=$(comm -13 "$MS_SORTED" "$BIB_SORTED" || true)
N_UNUSED=$(printf '%s\n' "$UNUSED" | grep -c . 2>/dev/null || true)
N_UNUSED=${N_UNUSED:-0}

if [ "$N_MISSING" -gt 0 ]; then
  echo "STATUS=RED"
  echo "FAIL: $N_MISSING citekey(s) cited in manuscript have NO matching @entry{...} in bibfile."
  echo ""
  echo "Missing keys (first 20):"
  printf '%s\n' "$MISSING" | head -20 | sed 's/^/  - /'
  if [ "$N_MISSING" -gt 20 ]; then
    echo "  … ($((N_MISSING - 20)) more)"
  fi
  echo ""
  echo "  Remediation:"
  echo "    - If the citation is legitimate: add a corresponding @article{KEY,...} to $BIB"
  echo "    - If the citekey is a typo: fix the \\cite{} or [@key] in the manuscript"
  echo "    - Run scholar-citation audit to auto-resolve missing entries from the reference library"
  exit 1
fi

if [ "$N_UNUSED" -gt 0 ]; then
  echo "STATUS=YELLOW"
  echo "WARN: $N_UNUSED bib entr(ies) defined but never cited in manuscript."
  echo ""
  echo "Unused keys (first 10):"
  printf '%s\n' "$UNUSED" | head -10 | sed 's/^/  - /'
  if [ "$N_UNUSED" -gt 10 ]; then
    echo "  … ($((N_UNUSED - 10)) more)"
  fi
  echo ""
  echo "  Advisory: consider removing unused entries from $BIB for a clean final bibliography."
  exit 2
fi

echo "STATUS=GREEN"
echo "PASS: all $N_MS_KEYS manuscript citekey(s) resolve to bib entries."
exit 0
