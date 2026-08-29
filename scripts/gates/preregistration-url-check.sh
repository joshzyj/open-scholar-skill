#!/usr/bin/env bash
# preregistration-url-check.sh — gate that ensures pre-registration
# claims in the manuscript are backed by a real third-party deposit
# URL (or an explicit no-deposit disclosure).
#
# Background (audit 2026-04-26 PR4.4): the round-04-26 cover letter
# repeatedly said "deposited blueprint and addendum" and cited only an
# internal `design/scholar-design-…md` path. JMF's credibility-reform
# framing requires a verifiable third-party deposit. Pipeline accepted
# internal paths as if they were public deposits.
#
# Behavior:
#   1. Reads `${PROJ}/logs/project-state.md` for `PREREG_URL` and
#      `PREREG_TYPE` fields. PREREG_TYPE ∈ {osf, aspredicted,
#      clinicaltrials, internal-only, none, unset}.
#   2. Scans cover letter, ethics statement, and final manuscript for
#      the words "pre-registered" / "preregistered" / "pre-registration".
#   3. Validation rules:
#      R1   Manuscript/cover/ethics claim pre-reg AND PREREG_TYPE=unset
#           → RED.
#      R2   PREREG_TYPE ∈ {osf, aspredicted, clinicaltrials} AND
#           PREREG_URL does not match the corresponding allowlist
#           pattern → RED.
#      R3   PREREG_TYPE=internal-only AND cover letter does not contain
#           an explicit "no public deposit" disclosure sentence → RED.
#      R4   Manuscript claims pre-reg but PREREG_TYPE=none → RED
#           (cannot claim pre-reg without a deposit).
#      R5   No pre-reg claim AND PREREG_TYPE=unset → GREEN (legitimate
#           non-pre-registered study).
#
# Exit codes: 0=GREEN, 1=RED. Diagnostics on stdout, machine-readable
# format `STATUS=<color>` and `REASON=<short>` on the last two lines.
#
# Usage: bash preregistration-url-check.sh <proj_dir>

set -uo pipefail

if [ $# -lt 1 ]; then
  echo "usage: $0 <proj_dir>" >&2
  exit 64
fi

PROJ="$1"
[ -d "$PROJ" ] || { echo "ERROR: project directory not found: $PROJ" >&2; exit 66; }

# Audit 2026-05-02: canonical PROJECT STATE path is $PROJ/logs/project-state.md
# (per pipeline-state.sh:168). Original `find "$PROJ" \( -name "project-state*.md" \)`
# was unscoped and admitted stale archive/project-state-old.md (BSD find depth-first
# returns subdir hits first, so a recently-touched archive copy could win head -1
# over the canonical file). Apply Gap CC-B pattern: canonical-first probe list,
# then maxdepth-1 fallback.
STATE_FILE=""
for _sf_cand in \
  "$PROJ/logs/project-state.md" \
  "$PROJ/project-state.md"; do
  if [ -f "$_sf_cand" ]; then
    STATE_FILE="$_sf_cand"
    break
  fi
done
if [ -z "$STATE_FILE" ]; then
  STATE_FILE=$(find "$PROJ/logs" -maxdepth 1 -type f \
    \( -name "project-state*.md" -o -name "PROJECT-STATE*" \) \
    2>/dev/null | head -1 || true)
fi
if [ -z "$STATE_FILE" ]; then
  STATE_FILE=$(find "$PROJ" -maxdepth 1 -type f \
    \( -name "project-state*.md" -o -name "PROJECT-STATE*" \) \
    2>/dev/null | head -1 || true)
fi
unset _sf_cand

# ── Step 1: read PREREG_TYPE and PREREG_URL from state ──────────────
# Extract a single PREREG field. Strips leading bullet/bold markup and
# splits at the FIRST ":" or "=" only (URLs contain colons).
_extract_field() {
  local file="$1" key="$2"
  awk -v key="$key" '
    BEGIN { IGNORECASE = 1 }
    {
      line = $0
      # strip leading "- ", "* ", "** **" bold markup, whitespace
      sub(/^[[:space:]]*[-*][[:space:]]+/, "", line)
      gsub(/\*\*/, "", line)
      sub(/^[[:space:]]+/, "", line)
      # find the FIRST `:` or `=`
      colon = index(line, ":")
      eq = index(line, "=")
      sep = 0
      if (colon > 0 && (eq == 0 || colon < eq)) { sep = colon }
      else if (eq > 0)                          { sep = eq }
      if (sep == 0) next
      this_key = substr(line, 1, sep - 1)
      sub(/[[:space:]]+$/, "", this_key)
      if (tolower(this_key) != tolower(key)) next
      val = substr(line, sep + 1)
      sub(/^[[:space:]]+/, "", val)
      sub(/[[:space:]]+$/, "", val)
      gsub(/^"|"$/, "", val)
      print val
      exit
    }
  ' "$file"
}

PREREG_TYPE="unset"
PREREG_URL=""
if [ -n "$STATE_FILE" ] && [ -f "$STATE_FILE" ]; then
  _t=$(_extract_field "$STATE_FILE" "PREREG_TYPE" | tr '[:upper:]' '[:lower:]')
  [ -n "$_t" ] && PREREG_TYPE="$_t"
  PREREG_URL=$(_extract_field "$STATE_FILE" "PREREG_URL")
fi

# ── Step 2: assemble list of files where pre-reg claims may live ─────
# Audit 2026-05-02 (Gap CC-B): canonical paths live at depth ≤ 2 —
# cover letter at ${PROJ}/drafts/cover-letter-*.md or
# ${PROJ}/submission/scholar-journal-cover-letter-*.md; ethics at
# ${PROJ}/ethics/ethics-open-science.md. Original maxdepth 3 admitted stale
# archive/old-runs/cover-letter-*.md and lit-review/old-runs/ethics-*.md whose
# pre-reg claims could spuriously trigger the gate. Tighten to maxdepth 2.
SCAN_FILES=()
# Cover letter
while IFS= read -r f; do [ -n "$f" ] && SCAN_FILES+=("$f"); done < <(
  find "$PROJ" -maxdepth 2 \( -iname "*cover-letter*" -o -iname "*cover_letter*" \) -type f 2>/dev/null
)
# Ethics statement
while IFS= read -r f; do [ -n "$f" ] && SCAN_FILES+=("$f"); done < <(
  find "$PROJ" -maxdepth 2 -iname "*ethics*" -type f 2>/dev/null | grep -v "/logs/" || true
)
# Final manuscript (md, tex, docx-source if present)
while IFS= read -r f; do [ -n "$f" ] && SCAN_FILES+=("$f"); done < <(
  find "$PROJ/drafts" -maxdepth 2 \( -iname "manuscript-final*.md" -o -iname "manuscript-final*.tex" \) -type f 2>/dev/null
)

# ── Step 3: detect pre-reg claims ────────────────────────────────────
# A KEYWORD IS NOT A CLAIM. The previous test was
#   grep -qiE 'pre-?registered|pre-?registration'
# which reads an honest denial ("we make no pre-registration claim") as an
# assertion of pre-registration, REDs the phase, and — per the remedy text
# this gate used to print — instructs the author to delete a true disclosure.
# Measured 2026-08-27 (P18-A): the denial fixture RED-failed under BOTH
# PREREG_TYPE unset and PREREG_TYPE=none.
#
# Classification is per OCCURRENCE, not per file or per sentence: one sentence
# can carry both ("not a pre-registered replication of Smith, but an
# independent study that was pre-registered at OSF"), and per-sentence logic
# gets that backwards. An occurrence is a DENIAL when a negation cue precedes
# it within CLAIM_WINDOW characters *of the same sentence* — the window is
# clipped at sentence boundaries because an unclipped window reads
# "This is not true. We pre-registered at OSF." as a denial, which is the
# DANGEROUS direction (a real claim silently unverified).
PREREG_CLAIM=0
PREREG_CLAIM_FILES=()
PREREG_DENIAL_ONLY_FILES=()
PREREG_URL_WITH_DENIAL=()
CLAIM_WINDOW="${SCHOLAR_PREREG_CLAIM_WINDOW:-40}"

_prereg_classify() {  # <file> -> "CLAIMS=<n> DENIALS=<n> URL=<0|1>"
  python3 - "$1" "$CLAIM_WINDOW" <<'PY' 2>/dev/null
import re, sys
try:
    text = open(sys.argv[1], encoding="utf-8", errors="replace").read()
except Exception:
    print("CLAIMS=-1 DENIALS=0 URL=0"); raise SystemExit(0)
window = int(sys.argv[2])

KW = re.compile(r"pre-?regist(?:ered|ration|er)", re.I)
# "not only/just/merely pre-registered" is an ASSERTION, not a denial.
NEG = re.compile(r"\b(?:no|not|never|without|neither|nor|absent|lack(?:ing|s|ed)?|"
                 r"absence|didn't|did\s+not|was\s+not|were\s+not|is\s+not|are\s+not|"
                 r"has\s+not|have\s+not|non-?)\b(?!\s+(?:only|just|merely))", re.I)
# "Pre-registration: none" / "Pre-registration — N/A"
FWD_NONE = re.compile(r"^\s*[:—\-]?\s*(?:none|n/?a|not\s+applicable|no\b)", re.I)
# A possessive/definite determiner immediately before the keyword PRESUPPOSES
# that a pre-registration exists, so the sentence asserts one even when a
# negation sits earlier in the window: "We did not deviate from OUR
# pre-registration" negates *deviate*, not the pre-registration. Without this,
# that sentence reads as a denial — a genuine claim silently unverified, which
# is the dangerous direction. (Codex adversarial review, 2026-08-27.)
# "no"/"any" are deliberately NOT in this list: "no pre-registration" is a denial.
PRESUPPOSING = re.compile(r"\b(?:our|the|its|their|his|her|this|that|a\s+prior|"
                          r"the\s+original|our\s+own)\s*$", re.I)
URL = re.compile(r"(?:osf\.io/|aspredicted\.org|clinicaltrials\.gov|isrctn|drks\.de|"
                 r"researchregistry|egap\.org|socialscienceregistry\.org|"
                 r"crd\.york\.ac\.uk/PROSPERO|prospero|anzctr\.org|apps\.who\.int/trialsearch|"
                 r"trialsearch\.who\.int|chictr\.org)", re.I)
# A single newline is NOT a sentence boundary: manuscript prose is hard-wrapped,
# so "we make no\npre-registration claim" would otherwise have its window
# truncated at the wrap and read as a claim. Only real terminators and
# paragraph breaks end a sentence. (Caught by the end-to-end fixture after the
# single-line shape tests passed — wrapped text is the shape they could not see.)
SENT_END = re.compile(r"[.!?;]|\n[ \t]*\n")

claims = denials = 0
for m in KW.finditer(text):
    start = m.start()
    bound = 0
    for s in SENT_END.finditer(text, 0, start):
        bound = s.end()
    back = text[max(bound, start - window):start]
    fwd = text[m.end():m.end() + 24]
    # A presupposing determiner directly before the keyword wins over an
    # earlier negation in the window; an explicit "none" AFTER the keyword
    # ("Pre-registration: none") still wins over the determiner.
    if FWD_NONE.match(fwd):
        denials += 1
    elif PRESUPPOSING.search(back):
        claims += 1
    elif NEG.search(back):
        denials += 1
    else:
        claims += 1
print(f"CLAIMS={claims} DENIALS={denials} URL={1 if URL.search(text) else 0}")
PY
}

if [ "${#SCAN_FILES[@]}" -gt 0 ]; then
  for f in "${SCAN_FILES[@]}"; do
    grep -qiE 'pre-?registered|pre-?registration' "$f" 2>/dev/null || continue
    RES="$(_prereg_classify "$f")"
    case "$RES" in
      CLAIMS=*) : ;;
      *)  # python3 unavailable / classifier failed: fall back to the old
          # keyword test. Fail CLOSED (treat as a claim) — an unverified
          # pre-registration claim is the worse outcome — and say so.
          echo "WARN: pre-reg claim classifier unavailable for $f; falling back to keyword match (may misread an honest denial)." >&2
          PREREG_CLAIM=1; PREREG_CLAIM_FILES+=("$f"); continue ;;
    esac
    C="${RES#CLAIMS=}"; C="${C%% *}"
    Dn="${RES#*DENIALS=}"; Dn="${Dn%% *}"
    U="${RES##*URL=}"
    if [ "${C:-0}" -gt 0 ]; then
      PREREG_CLAIM=1
      PREREG_CLAIM_FILES+=("$f")
    elif [ "${Dn:-0}" -gt 0 ]; then
      PREREG_DENIAL_ONLY_FILES+=("$f")
      # A registry URL alongside nothing but denials is not decidable here:
      # osf.io also hosts data and materials, so the URL is not proof of a
      # pre-registration claim — but silently passing it would hide the one
      # combination most likely to be a real claim the window misread.
      [ "${U:-0}" = "1" ] && PREREG_URL_WITH_DENIAL+=("$f")
    fi
  done
fi

# ── Step 4: apply rules ──────────────────────────────────────────────
RED=0
DIAG=""

# R1 / R4 — claim without a real deposit type
if [ "$PREREG_CLAIM" -eq 1 ]; then
  case "$PREREG_TYPE" in
    osf|aspredicted|clinicaltrials)
      # R2 — type valid, URL must match allowlist
      case "$PREREG_TYPE" in
        osf)            allow_re='https?://osf\.io/' ;;
        aspredicted)    allow_re='https?://aspredicted\.org/' ;;
        clinicaltrials) allow_re='https?://clinicaltrials\.gov/' ;;
      esac
      if ! printf '%s\n' "$PREREG_URL" | grep -qE "$allow_re"; then
        RED=1
        DIAG="${DIAG}- PREREG_TYPE=$PREREG_TYPE in project-state but PREREG_URL='$PREREG_URL' does not match allowlist pattern '$allow_re'. Update PREREG_URL or correct PREREG_TYPE.\n"
      fi
      ;;
    internal-only)
      # R3 — must have disclosure sentence in cover letter
      DISCLOSURE=0
      if [ "${#SCAN_FILES[@]}" -gt 0 ]; then
        for f in "${SCAN_FILES[@]}"; do
          if grep -qiE 'no (public|external|third[- ]party) deposit|not (yet|publicly) deposited|registry deposit (is )?not|internal[- ]only' "$f" 2>/dev/null; then
            DISCLOSURE=1
            break
          fi
        done
      fi
      if [ "$DISCLOSURE" -eq 0 ]; then
        RED=1
        DIAG="${DIAG}- PREREG_TYPE=internal-only requires the cover letter (or ethics statement) to contain an explicit 'no public deposit' disclosure sentence — none found in scanned files.\n"
      fi
      ;;
    none)
      # Reached only when an AFFIRMATIVE claim was found (Step 3 classifies
      # denials separately), so this remains RED: prose asserting
      # pre-registration while project-state says none is a real contradiction.
      # What changed is that a denial no longer arrives here at all.
      RED=1
      DIAG="${DIAG}- Manuscript/cover letter AFFIRMATIVELY claims pre-registration but PREREG_TYPE=none in project-state. Correct PREREG_TYPE/PREREG_URL, or reword the affirmative claim. An honest denial ('this study was not pre-registered') is NOT a violation and does not need to be removed.\n"
      ;;
    unset|"")
      RED=1
      DIAG="${DIAG}- Manuscript/cover letter claims pre-registration but PREREG_TYPE/PREREG_URL are unset in project-state.md. Phase 0 should set these fields.\n"
      DIAG="${DIAG}    Choose one of the five PREREG_TYPE values and add the matching pair to the Phase 0 block of project-state.md:\n"
      DIAG="${DIAG}      • osf            — public deposit on OSF.\n"
      DIAG="${DIAG}        PREREG_TYPE: osf\n"
      DIAG="${DIAG}        PREREG_URL: https://osf.io/<token>\n"
      DIAG="${DIAG}      • aspredicted    — public deposit on AsPredicted.\n"
      DIAG="${DIAG}        PREREG_TYPE: aspredicted\n"
      DIAG="${DIAG}        PREREG_URL: https://aspredicted.org/<token>\n"
      DIAG="${DIAG}      • clinicaltrials — public deposit on ClinicalTrials.gov.\n"
      DIAG="${DIAG}        PREREG_TYPE: clinicaltrials\n"
      DIAG="${DIAG}        PREREG_URL: https://clinicaltrials.gov/<NCT-id>\n"
      DIAG="${DIAG}      • internal-only  — design artifact only, no public deposit. Cover letter (or ethics statement) MUST contain an explicit 'no public deposit' disclosure sentence.\n"
      DIAG="${DIAG}        PREREG_TYPE: internal-only\n"
      DIAG="${DIAG}        PREREG_URL: design/<design-doc>.md (internal-only — public deposit deferred)\n"
      DIAG="${DIAG}      • none           — study is NOT pre-registered. Stating that plainly ('this study was not pre-registered') is a DISCLOSURE and passes this gate; do not delete an honest denial to satisfy it. Only an affirmative claim of pre-registration must be removed or corrected.\n"
      DIAG="${DIAG}        PREREG_TYPE: none\n"
      DIAG="${DIAG}        PREREG_URL: (leave blank)\n"
      ;;
  esac
fi

# ── Step 5: emit report ──────────────────────────────────────────────
echo "=== PRE-REGISTRATION URL GATE ==="
echo "Project: $PROJ"
echo "PREREG_TYPE: $PREREG_TYPE"
echo "PREREG_URL: ${PREREG_URL:-<unset>}"
echo "Pre-reg claim detected: $([ "$PREREG_CLAIM" -eq 1 ] && echo yes || echo no)"
if [ "${#PREREG_CLAIM_FILES[@]}" -gt 0 ]; then
  echo "Files with an AFFIRMATIVE pre-reg claim:"
  for f in "${PREREG_CLAIM_FILES[@]}"; do echo "  - $f"; done
fi
# Both classifications are printed, not just the one that gates. A reader must
# be able to audit the split rather than trust a boolean.
if [ "${#PREREG_DENIAL_ONLY_FILES[@]}" -gt 0 ]; then
  echo "Files whose pre-reg language is a DENIAL/disclosure only (not a claim):"
  for f in "${PREREG_DENIAL_ONLY_FILES[@]}"; do echo "  - $f"; done
fi
if [ "${#PREREG_URL_WITH_DENIAL[@]}" -gt 0 ]; then
  echo "ADVISORY: a registry URL appears in a file whose pre-registration language reads as a denial."
  echo "          osf.io also hosts data and materials, so this is NOT treated as a claim — but it is"
  echo "          the combination most likely to be an affirmative claim this gate misread. Confirm by hand:"
  for f in "${PREREG_URL_WITH_DENIAL[@]}"; do echo "  - $f"; done
fi
# Declared registered while the prose denies it is a contradiction in the other
# direction, and was previously invisible because denials were read as claims.
if [ "$PREREG_CLAIM" -eq 0 ] && [ "${#PREREG_DENIAL_ONLY_FILES[@]}" -gt 0 ]; then
  case "$PREREG_TYPE" in
    osf|aspredicted|clinicaltrials)
      echo "ADVISORY: PREREG_TYPE=$PREREG_TYPE (declared pre-registered) but the scanned prose contains only"
      echo "          denials of pre-registration. One of the two is wrong — reconcile before submission." ;;
  esac
fi
echo ""
if [ "$RED" -eq 1 ]; then
  echo "FAIL — pre-registration gate violations:"
  printf '%b' "$DIAG"
  echo ""
  echo "STATUS=RED"
  echo "REASON=prereg-url-mismatch"
  exit 1
else
  echo "PASS — pre-registration gate clean."
  echo "STATUS=GREEN"
  echo "REASON=ok"
  exit 0
fi
