#!/usr/bin/env bash
# test-s310-guard-leaks.sh — S310–S312: side doors around the Bash data guard.
#
# Verified 2026-10-19 against the real guard: a two-step copy (cp or pandas to_csv
# into output/, then cat the copy) got a HALTED file out; print(df[:5]) and a saved
# script that prints rows got LOCAL_MODE rows out; with no jq on PATH the Bash
# branch failed open (a jq-less Codex host had no guard at all).
#   L*  leaks that must BLOCK on the shipped guard
#   P1  the same leak cases with the leak-rules helper removed ALLOW — proves the test bites
#   A*  legitimate work that must stay ALLOWED (aggregates, protected copies, model output)
#   J*  no jq on PATH (python3 present): the guard and the Codex adapter still BLOCK
# L/A/J run against the top-level guard AND the scholar-auto-research bundled copy;
# both source the one _guard-leak-rules.sh, which must stay byte-identical.
# Fixture paths contain a space (CLAUDE.md rule 12).
set -uo pipefail
export LC_ALL=C
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
G="$REPO_ROOT/scripts/gates"
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not installed (fixture builder needs it)"; exit 0; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: python3 not installed"; exit 0; }

TMPROOT="$(mktemp -d -t s310.XXXXXX)"
trap 'rm -rf "$TMPROOT"' EXIT
PASS=0; FAIL=0
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

FIX="$TMPROOT/proj one"
mkdir -p "$FIX/data/raw" "$FIX/data/derived" "$FIX/.claude" "$FIX/output" "$FIX/tables" "$FIX/scripts" "$FIX/materials"
printf 'id,income\n1,52000\n2,61000\n' > "$FIX/data/raw/secret.csv"
printf 'id,voice\n1,wav\n'             > "$FIX/data/raw/halted.csv"
S="$(cd "$FIX/data/raw" && pwd -P)/secret.csv"
H="$(cd "$FIX/data/raw" && pwd -P)/halted.csv"
printf '%%PDF-1.4 consent form\n' > "$FIX/materials/codebook.pdf"
R="$(cd "$FIX/materials" && pwd -P)/codebook.pdf"
jq -n --arg s "$S" --arg h "$H" --arg r "$R" '{($s):"LOCAL_MODE", ($h):"HALTED", ($r):"NEEDS_REVIEW:RED"}' > "$FIX/.claude/safety-status.json"
printf 'import pandas as pd\ndf = pd.read_csv("data/raw/secret.csv")\nprint(df.head())\n' > "$FIX/scripts/peek.py"
printf 'import pandas as pd\nsrc = "data/raw/secret.csv"\nd = pd.read_csv(src)\nd.to_csv("output/leak.csv")\n' > "$FIX/scripts/export.py"
printf 'library(readr)\nd <- read_csv("data/raw/secret.csv")\nm <- lm(income ~ id, data = d)\nprint(m)\nprint(summary(m))\nwrite.csv(d, "data/derived/clean.csv")\nwrite.csv(coef(summary(m)), "tables/coefs.csv")\n' > "$FIX/scripts/04-models.R"
printf 'import pandas as pd\nd = pd.read_csv("data/raw/halted.csv")\nprint(len(d))\n' > "$FIX/scripts/count-halted.py"
# variable-built paths, the way pipeline scripts name their inputs
printf 'RAW <- "data/raw"\nd <- read.csv(file.path(RAW, "secret.csv"))\nprint(head(d))\n' > "$FIX/scripts/varpath-peek.R"
printf 'RAW <- "data/raw"\nf <- file.path(RAW, "secret.csv")\nd <- read.csv(f)\nwrite.csv(d, "output/leak.csv")\n' > "$FIX/scripts/varpath-export.R"
printf 'RAW <- "data/raw"\nd <- read.csv(file.path(RAW, "secret.csv"))\nm <- glm(income ~ id, data = d)\nprint(summary(m))\nsaveRDS(m, "output/m.rds")\n' > "$FIX/scripts/varpath-model.R"

verdict() {  # <guard dir> <command> [env...] -> ALLOW|BLOCK
  local gd="$1" cmd="$2"; shift 2
  jq -nc --arg c "$FIX" --arg cmd "$cmd" '{tool_name:"Bash",tool_input:{command:$cmd},cwd:$c,hook_event_name:"PreToolUse"}' \
    | env "$@" bash "$gd/pretooluse-data-guard.sh" >/dev/null 2>&1
  [ $? -eq 2 ] && echo BLOCK || echo ALLOW
}

LEAKS=(
  "L1 cp HALTED into output/|cp data/raw/halted.csv output/halted-copy.txt"
  "L2 pandas read HALTED|python3 -c \"import pandas as pd; print(len(pd.read_csv('data/raw/halted.csv')))\""
  "L3 pandas copy LOCAL_MODE to output/|python3 -c \"import pandas as pd; pd.read_csv('data/raw/secret.csv').to_csv('output/c.txt')\""
  "L4 tainted var to_csv|python3 -c \"import pandas as pd; d=pd.read_csv('data/raw/secret.csv'); d.to_csv('output/c.txt')\""
  "L5 print(df[:5])|python3 -c \"import pandas as pd; df=pd.read_csv('data/raw/secret.csv'); print(df[:5])\""
  "L6 saved script prints rows|python3 scripts/peek.py"
  "L7 saved script writes frame to output/|python3 scripts/export.py"
  "L8 saved script reads HALTED|python3 scripts/count-halted.py"
  "L9 mv LOCAL_MODE out of data/|mv data/raw/secret.csv output/s.csv"
  "L10 shutil.copy to output/|python3 -c \"import shutil; shutil.copy('data/raw/secret.csv', 'output/s.csv')\""
  "L11 runsheet case: pdftotext RED file into output/|pdftotext materials/codebook.pdf output/codebook.txt"
  "L12 pandoc RED file to stdout|pandoc materials/codebook.pdf -t plain"
  "L13 pandoc RED file -o output/|pandoc materials/codebook.pdf -o output/codebook.md"
  "L14 script, file.path(RAW, ...) input, prints head|Rscript scripts/varpath-peek.R"
  "L15 script, path variable input, writes frame to output/|Rscript scripts/varpath-export.R"
  "L16 gzip -c LOCAL_MODE > output/|gzip -c data/raw/secret.csv > output/s.gz"
  "L17 base64 LOCAL_MODE > output/|base64 data/raw/secret.csv > output/s.b64"
)
ALLOWS=(
  "A1 aggregate to stdout|python3 -c \"import pandas as pd; d=pd.read_csv('data/raw/secret.csv'); print(d.shape, d.income.mean())\""
  "A2 cp within data/|cp data/raw/secret.csv data/derived/secret-work.csv"
  "A3 wc -l HALTED (count)|wc -l data/raw/halted.csv"
  "A4 pipeline script: model print + derived write under data/ + table|Rscript scripts/04-models.R"
  "A5 cp of unrestricted file|cp tables/x.csv output/x.csv"
  "A6 rsync between unrestricted dirs|rsync -a output/ tables/"
  "A7 pdftotext beside its source|pdftotext materials/codebook.pdf"
  "A8 pandoc of an unrestricted doc|pandoc tables/x.csv -o output/x.md"
  "A9 script, file.path input, model summary + saveRDS(model)|Rscript scripts/varpath-model.R"
  "A10 gzip in place under data/|gzip data/raw/secret.csv"
)
: > "$FIX/tables/x.csv"

echo "=== P1: without the leak rules, the guard lets them through ==="
# The pre-fix guard = the shipped guard with _guard-leak-rules.sh absent (it sources
# the helper only when present), so P1 needs no git history and runs in every repo.
PRE="$TMPROOT/pre gates"; mkdir -p "$PRE"
cp "$G"/*.sh "$G"/*.py "$G"/*.json "$PRE"/ 2>/dev/null
rm -f "$PRE/_guard-leak-rules.sh"
n=0
for row in "${LEAKS[@]}"; do
  [ "$(verdict "$PRE" "${row#*|}")" = ALLOW ] && n=$((n + 1))
done
[ "$n" -ge 10 ] && pass "P1 guard without the leak rules allowed $n of ${#LEAKS[@]} leak cases" \
               || fail "P1 guard without the leak rules allowed only $n of ${#LEAKS[@]} — the test does not bite"

BUNDLE="$REPO_ROOT/.claude/skills/scholar-auto-research/scripts/gates"
if [ -f "$BUNDLE/_guard-leak-rules.sh" ]; then
  cmp -s "$G/_guard-leak-rules.sh" "$BUNDLE/_guard-leak-rules.sh" && pass "B0 bundled _guard-leak-rules.sh is byte-identical" \
    || fail "B0 bundled _guard-leak-rules.sh differs from scripts/gates"
fi
NOJQ="$TMPROOT/no jq"; mkdir -p "$NOJQ"
for t in bash sh sed awk grep cat tr head tail env python3 realpath readlink dirname basename mktemp rm date wc cut sort uniq find stat ls printf; do
  p="$(command -v "$t" 2>/dev/null)"; [ -n "$p" ] && [ -x "$p" ] && ln -sf "$p" "$NOJQ/$t"
done
for GD in "$G" "$BUNDLE"; do
  [ -f "$GD/pretooluse-data-guard.sh" ] || continue
  echo "##### guard: ${GD#$REPO_ROOT/}"
  echo "=== S310/S311: leaks must BLOCK ==="
  for row in "${LEAKS[@]}"; do
    label="${row%%|*}"; cmd="${row#*|}"
    [ "$(verdict "$GD" "$cmd")" = BLOCK ] && pass "$label" || fail "$label (ALLOWED)"
  done

  echo "=== legitimate work must stay ALLOWED ==="
  for row in "${ALLOWS[@]}"; do
    label="${row%%|*}"; cmd="${row#*|}"
    [ "$(verdict "$GD" "$cmd")" = ALLOW ] && pass "$label" || fail "$label (BLOCKED)"
  done

  echo "=== S312: no jq on PATH ==="
  [ "$(verdict "$GD" 'cat data/raw/halted.csv' PATH="$NOJQ")" = BLOCK ] && pass "J1 guard blocks cat HALTED without jq" || fail "J1 guard ALLOWED cat HALTED without jq"
  [ "$(verdict "$GD" 'cat data/raw/secret.csv' PATH="$NOJQ")" = BLOCK ] && pass "J2 guard blocks cat LOCAL_MODE without jq" || fail "J2 guard ALLOWED cat LOCAL_MODE without jq"
  [ "$(verdict "$GD" 'cat tables/x.csv' PATH="$NOJQ")" = ALLOW ] && pass "J3 unrestricted cat still allowed without jq" || fail "J3 unrestricted cat BLOCKED without jq"
  OUT="$(jq -nc --arg c "$FIX" '{tool_name:"Bash",tool_input:{command:"cat data/raw/halted.csv"},cwd:$c,hook_event_name:"PreToolUse"}' \
    | env PATH="$NOJQ" bash "$GD/codex-pretooluse-hook.sh" 2>/dev/null)"; RC=$?
  if [ "$RC" -eq 2 ] && printf '%s' "$OUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["hookSpecificOutput"]["permissionDecision"]=="deny" and d["reason"].startswith("SAFETY GUARD")' 2>/dev/null; then
    pass "J4 Codex adapter denies without jq, with the guard's real reason"
  else
    fail "J4 Codex adapter without jq: rc=$RC out=${OUT:0:80}"
  fi

done

echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
