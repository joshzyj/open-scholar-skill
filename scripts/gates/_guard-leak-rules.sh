#!/usr/bin/env bash
# _guard-leak-rules.sh — Bash-channel leak rules for pretooluse-data-guard.sh (S310, S311).
#
# Sourced by every copy of the data guard (top-level and the scholar-auto-research
# bundle), so the rules cannot drift between copies. It defines functions only and
# relies on the guard's own helpers: bash_first_sensitive_target, bash_sidecar_status,
# bash_primary_verb, bash_command_is_dump, lexical_abspath, is_rawdata_path,
# is_qual_path, find_project_root, and $CWD. It carries its own script-path
# extractor, because older guard copies (the auto-research bundle) lack one.
#
# WHY. The guard blocked a direct dump of a restricted file but let the same content
# out by side doors (verified 2026-10-19 against the real guard):
#   S310  a two-step copy: `cp data/raw/x.csv output/c.txt` (or pandas
#         read_csv(x).to_csv("output/c.txt")), then `cat output/c.txt`. The copy has
#         no sidecar entry, so step 2 reads it freely, even from a HALTED file.
#   S311  row printing the dump regex did not know (`print(df[:5])`), and any script
#         run from disk (`python3 scripts/peek.py`), whose body the guard never read.
#
# WHAT. lr_bash_verdict <cmd> prints one reason line and returns 0 when the command
# should be BLOCKED; returns 1 otherwise. Rules:
#   R1 copy or convert (cp/mv/rsync/dd/..., pdftotext/pandoc/soffice/unzip/...) with a
#      restricted source and a destination that is not itself protected (path shape or
#      sidecar status); a converter writing to stdout counts as a dump, and `> out` on a
#      converter or compressor (gzip -c, base64) names the destination.
#   R2 HALTED or NEEDS_REVIEW: an interpreter, or a script it runs, that names a file the
#      user refused or nobody has reviewed yet; R1 likewise refuses copying such a file
#      anywhere (S313).
#   R3 tainted write: code that loads a restricted file and writes that frame (or
#      copies the file) to a path that is not itself protected.
#   R4 row printing: in inline code (-c / heredoc) slices, .to_markdown, .iterrows,
#      ...; in a saved script, printing or head()-ing the frame loaded from the file.
#   R5 R2-R4 (and R1 / the dump verbs for .sh) applied to the body of a project
#      script the command runs, one level deep.
#
# LIMITS (stated, not hidden). Taint is direct only: `x = read_csv(f); y = x[...];
# y.to_csv(p)` is not traced through y. A write target that cannot be resolved (a
# path computed at run time, an argument, an environment variable) is allowed as
# unknown; literal variables, f-strings and file.path/os.path.join/paste0 of them are
# resolved. An input path built the same way is resolved; one read from config or the
# environment is not. Scripts outside the project, scripts over 256 KB, and files
# reached through source()/import inside a script are not read. Encodings done inside
# code (base64 in Python) are not modelled. This remains a cooperative speed-bump; the
# OS sandbox (Lockdown) is the containment boundary.

_LR_MAX_SCRIPT_BYTES=262144

# The code scanner. argv: mode (inline|script-py|script-r), restricted path, cwd; code on
# stdin. Comments are stripped first: a script that says "# no print(df)" is not a dump.
# Exit 0 + one line on stdout = leak found.
read -r -d '' _LR_PY <<'PY' || true
import os, re, sys
mode, sens, cwd = sys.argv[1], sys.argv[2], sys.argv[3]
code = sys.stdin.read()

def strip_comments(src):
    # drop "# ..." to end of line when the # is outside a string literal (R and Python)
    out = []
    for line in src.split("\n"):
        q, cut = None, len(line)
        for i, ch in enumerate(line):
            if q:
                if ch == "\\":
                    continue
                if ch == q:
                    q = None
            elif ch in "\"'":
                q = ch
            elif ch == "#":
                cut = i
                break
        out.append(line[:cut])
    return "\n".join(out)
code = strip_comments(code)
base = os.path.basename(sens)
if not base or base not in code:
    sys.exit(1)
b = re.escape(base)
ID = r'[A-Za-z_.][\w.]*'

def hit(kind, text):
    print(kind + ': ' + ' '.join(text.split())[:60])
    sys.exit(0)

READ = (r'(?:read_(?:csv|table|stata|spss|sas|parquet|feather|excel|json|fwf|dta|sav|rds|xlsx|delim|tsv)'
        r'|read\.(?:csv2?|table|delim|dta|xlsx)|fread|readRDS|read_dta|read_sav|open|load|import)')

# Variables holding the restricted path, then frames loaded from it.
# A path variable's right-hand side is the literal itself, or a path-building call.
PATHCALL = r'(?:(?:file\.path|os\.path\.join|here::here|here|Path|paste0?|normalizePath)\s*\([^)\n]*)?'
pathvars = {m.group(1) for m in re.finditer(r'(' + ID + r')\s*(?:=|<-)\s*' + PATHCALL + r'["\'][^"\'\n]*' + b, code)}
src = '(?:[^)\\n]*' + b + ('|\\s*(?:' + '|'.join(map(re.escape, pathvars)) + ')\\b' if pathvars else '') + ')'
taint = {m.group(1) for m in re.finditer(r'(' + ID + r')\s*(?:=|<-)\s*[^\n;]*?' + READ + r'\s*\(' + src, code)}
taint -= pathvars

# R4 row printing.
if mode == 'inline':
    for rx in (r'print\s*\(\s*' + ID + r'\s*\[',
               r'\.(?:to_markdown|to_html|to_latex|to_records|to_numpy|itertuples|iterrows|show)\s*\(',
               r'\.to_json\s*\(\s*\)',
               r'(?:^|[^\w.])display\s*\(\s*[A-Za-z_]',
               r'(?:^|[^\w.])(?:glimpse|kable)\s*\(\s*[A-Za-z_.]'):
        m = re.search(rx, code)
        if m:
            hit('rows', m.group(0))
ROWISH = r'(?:head|tail|sample|iloc|loc|values|to_dict|to_string|to_markdown|query|nlargest|nsmallest)'
for v in taint:
    ve = re.escape(v)
    rxs = [r'print\s*\(\s*' + ve + r'\s*(?:\)|\[|\.\s*' + ROWISH + r'\b)',     # print(df) / print(df[..]) / print(df.head())
           r'(?<![\w.])' + ve + r'\s*\.\s*(?:to_string|to_markdown)\s*\(',          # rendered for output
           r'(?:^|[^\w.])(?:display|kable)\s*\(\s*' + ve + r'\b']
    if mode != 'script-py':                                                  # R (and inline code)
        rxs += [r'(?:^|[^\w.])(?:head|tail|View|str|glimpse)\s*\(\s*' + ve + r'\s*[,)\[]',
                r'(?m)^\s*' + ve + r'\s*(?:\[[^\]\n]*\])?\s*$']            # bare top-level autoprint in R
    for rx in rxs:
        m = re.search(rx, code)
        if m:
            hit('rows', m.group(0))
m = re.search(r'(?:open\s*\([^)\n]*' + b + r'[^)\n]*\)\s*\.\s*read|readLines\s*\([^)\n]*' + b + r')', code)
if m and mode != 'inline':
    hit('rows', m.group(0))

# R3 writes.
PROTECTED = re.compile(r'(^|/)(data|raw|input|inputs|datasets?|corpus|corpora|materials|transcripts|'
                       r'interviews|field-?notes|field_notes|participants|subjects|respondents)(/|$)', re.I)

def args_of(i):
    depth, j = 0, i
    while j < len(code):
        if code[j] == '(':
            depth += 1
        elif code[j] == ')':
            depth -= 1
            if depth == 0:
                return code[i + 1:j]
        j += 1
    return code[i + 1:]

# Simple string variables (OUT = "data/processed"; RAW <- file.path("data", "raw")) so a
# write target spelled through a variable, an f-string or file.path() resolves.
svar = {}

def split_args(a):
    parts, depth, cur, q = [], 0, "", None
    for ch in a:
        if q:
            cur += ch
            if ch == q:
                q = None
            continue
        if ch in "\"'":
            q = ch
        elif ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
        elif ch == "," and depth == 0:
            parts.append(cur.strip()); cur = ""; continue
        cur += ch
    if cur.strip():
        parts.append(cur.strip())
    return parts

def resolve(expr):
    """A path expression -> string, or None when any part is unknown."""
    expr = expr.strip()
    m = re.fullmatch(r"([fr]?)[\"']([^\"'\n]*)[\"']", expr)
    if m:
        s = m.group(2)
        def sub(x):
            k = x.group(1)
            return svar.get(k, "\0")
        s = re.sub(r"\{([A-Za-z_][\w.]*)\}", sub, s)
        return None if "\0" in s or "{" in s or "$" in s else s
    if expr in svar:
        return svar[expr]
    m = re.fullmatch(r"(file\.path|os\.path\.join|paste0|Path)\s*\((.*)\)", expr)
    if m:
        vals = [resolve(x) for x in split_args(m.group(2))]
        if not vals or any(v is None for v in vals):
            return None
        return "".join(vals) if m.group(1) == "paste0" else "/".join(v.strip("/") for v in vals)
    return None

def target(a, pos):
    """The output path argument: a file=/path=/con=/path_or_buf= keyword, else positional pos."""
    args = split_args(a)
    for x in args:
        km = re.match(r"(?:file|path|con|path_or_buf|filename|fname)\s*=\s*(.+)$", x)
        if km:
            return resolve(km.group(1))
    pos_args = [x for x in args if not re.match(r"[A-Za-z_.][\w.]*\s*=[^=]", x)]
    return resolve(pos_args[pos]) if len(pos_args) > pos else None

for _ in range(3):
    for m in re.finditer(r"(?m)^\s*([A-Za-z_.][\w.]*)\s*(?:<-|=)\s*(.+)$", code):
        n, rhs = m.group(1), m.group(2).strip().rstrip(";")
        if n not in svar:
            v = resolve(rhs)
            if v is not None:
                svar[n] = v

DATA_EXT = re.compile(r"\.(csv|tsv|dta|sav|rds|rdata|xlsx|xls|parquet|feather|arrow|db|sqlite|jsonl|ndjson)$", re.I)

def unprotected(t):
    if t is None:
        return False                      # unknown target: allowed (stated limit)
    p = t if os.path.isabs(t) else os.path.join(cwd, t)
    # S313: protected only under a protected dir AND with a data extension (the Read gate's scope)
    return not (PROTECTED.search(os.path.normpath(p)) and DATA_EXT.search(p))

for m in re.finditer(READ + r'\s*\(' + src + r'[^)\n]*\)\s*\.\s*to_\w+\s*\(', code):
    a = args_of(m.end() - 1)
    if a.strip() and unprotected(target(a, 0)):
        hit('write', m.group(0))
for v in taint:
    for m in re.finditer(r'(?<![\w.])' + re.escape(v) + r'\s*\.\s*to_\w+\s*\(', code):
        a = args_of(m.end() - 1)
        if a.strip() and unprotected(target(a, 0)):
            hit('write', m.group(0))
    for m in re.finditer(r'(?:write\.(?:csv2?|table|dta)|write_(?:csv|tsv|delim|dta|sav|parquet|feather|xlsx|rds)'
                         r'|fwrite|saveRDS|save|arrow::write_\w+)\s*\(\s*' + re.escape(v) + r'\b', code):
        if unprotected(target(args_of(code.index('(', m.start())), 1)):
            hit('write', m.group(0))
for m in re.finditer(r'(?:shutil\.(?:copy\w*|move)|copyfile|os\.(?:rename|replace|link|symlink)|file\.(?:copy|rename)'
                     r'|fs::file_(?:copy|move))\s*\(', code):
    a = args_of(m.end() - 1)
    if base in a or any(re.search(r'\b' + re.escape(p) + r'\b', a) for p in pathvars):
        args = split_args(a)
        dest = resolve(args[-1]) if len(args) >= 2 else None
        if len(args) >= 2 and (dest is None or unprotected(dest)):
            hit('copy', m.group(0))
sys.exit(1)
PY

# Is a destination path protected in its own right? 0 = protected.
# S313: a protected directory protects a copy only if the copy keeps a data extension
# (DATA_EXTS) — the Read gate checks only those, so data/processed/cb.txt made from a
# restricted PDF was readable by Read. $2 = the source, used when $1 is a directory.
_lr_dest_protected() {
  local p="$1" src="${2:-}" abs low st name ext
  [ -n "$p" ] || return 1
  abs="$(lexical_abspath "$p" 2>/dev/null)"
  [ -n "$abs" ] || abs="$p"
  if [ -d "$abs" ] || [ "${p%/}" != "$p" ]; then name="${src##*/}"; else name="${abs##*/}"; fi
  case "$name" in *.*) ext="$(printf '%s' "${name##*.}" | tr 'A-Z' 'a-z')" ;; *) ext="" ;; esac
  is_data_ext "$ext" || return 1
  low="$(printf '%s' "$abs" | tr 'A-Z' 'a-z')"
  # `cp f data/raw` (a directory) and `cp f data/raw/` both land inside it.
  is_rawdata_path "$low" && return 0
  is_rawdata_path "${low%/}/" && return 0
  is_qual_path "$low" && return 0
  st="$(bash_sidecar_status "$abs")"
  case "$st" in LOCAL_MODE|HALTED|NEEDS_REVIEW|NEEDS_REVIEW:*) return 0 ;; esac
  return 1
}

# Shell words of one segment (quote-aware when python3 exists).
_lr_words() {
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import shlex,sys
for w in shlex.split(sys.argv[1], posix=True): print(w)' "$1" 2>/dev/null && return 0
  fi
  local w
  for w in $1; do printf '%s\n' "$w"; done
}

# R1. Prints "source -> dest" for the first offending copy; 0 = block.
# Copiers take the last operand as the destination. Converters (pdftotext, pandoc,
# soffice, ...) also make a readable copy — the CUHK runsheet's two-step leak was
# `pdftotext materials/x.pdf output/x.txt` — so they count too: the destination is
# an output option's value, else the last operand, else stdout (a dump) or, for the
# tools that write beside their input / into the cwd, that location.
_LR_COPIERS='cp|mv|rsync|install|ln|scp|ditto|dd'
_LR_CONVERTERS='pdftotext|pdftohtml|pdftoppm|mutool|qpdf|gs|pandoc|textutil|soffice|libreoffice|iconv|in2csv|xlsx2csv|csvformat|docx2txt|antiword|catdoc|unzip|tar|7z|zip|ffmpeg|sox|convert|magick|gzip|bzip2|xz|zstd|lz4|base64|openssl'
lr_copy_violation() {
  local cmd="$1" segs seg verb w src dest sens seen want kind
  local -a ops=()
  segs="$(printf '%s' "$cmd" | tr '|;&()`' '\n\n\n\n\n\n')"
  while IFS= read -r seg; do
    [ -n "$seg" ] || continue
    verb="$(bash_primary_verb "$seg")"
    if [[ "$verb" =~ ^($_LR_COPIERS)$ ]]; then kind=copy
    elif [[ "$verb" =~ ^($_LR_CONVERTERS)$ ]]; then kind=convert
    else continue
    fi
    ops=(); seen=0; src=""; dest=""; want=0
    while IFS= read -r w; do
      if [ "$seen" -eq 0 ]; then
        [ "$(printf '%s' "${w##*/}" | tr 'A-Z' 'a-z')" = "$verb" ] && seen=1
        continue
      fi
      if [ "$want" -eq 1 ]; then dest="$w"; want=0; continue; fi
      # `> out` / `>> out` on a converter: the redirect target is where the copy lands.
      if [ "$kind" = convert ]; then
        case "$w" in
          '>'|'>>'|'1>') want=1; continue ;;
          '>'?*|'>>'?*) dest="${w#>}"; dest="${dest#>}"; continue ;;
        esac
      fi
      case "$verb:$w" in
        dd:if=*) src="${w#if=}"; continue ;;
        dd:of=*) dest="${w#of=}"; continue ;;
      esac
      if [ "$kind" = convert ]; then
        case "$w" in
          -o|--output|-output|--outdir|--output-dir|-d|-C|-O|--directory) want=1; continue ;;
          --output=*|--outdir=*|--output-dir=*|--directory=*|-output=*) dest="${w#*=}"; continue ;;
        esac
      fi
      case "$w" in -*|'') continue ;; esac
      ops+=("$w")
    done < <(_lr_words "$seg")
    if [ "$verb" = dd ]; then
      [ -n "$src" ] || continue
      ops=("$src"); dest="${dest:-stdout}"
    elif [ -z "$dest" ]; then
      if [ "$kind" = copy ]; then
        [ "${#ops[@]}" -ge 2 ] || continue
        dest="${ops[$((${#ops[@]} - 1))]}"
        unset 'ops[${#ops[@]}-1]'
      else
        case "$verb" in
          textutil|soffice|libreoffice) dest="" ;;                    # writes beside the input
          unzip|tar|7z) dest="${CWD:-$PWD}" ;;                         # extracts into the cwd
          gzip|bzip2|xz|zstd|lz4)                                      # in place unless -c (stdout)
            case " $seg " in *' -c '*|*' --stdout '*|*' -dc '*|*' -cd '*) dest=stdout ;; *) dest="" ;; esac ;;
          zip)                                                         # zip OUT.zip INPUT...
            [ "${#ops[@]}" -ge 2 ] || continue
            dest="${ops[0]}"; ops=("${ops[@]:1}") ;;
          pdftotext|pdftohtml|pdftoppm|ffmpeg|sox|convert|magick|mutool|qpdf)
            if [ "${#ops[@]}" -ge 2 ] && [ "${ops[$((${#ops[@]} - 1))]}" != - ]; then
              dest="${ops[$((${#ops[@]} - 1))]}"; unset 'ops[${#ops[@]}-1]'
            elif [ "${#ops[@]}" -ge 2 ]; then
              dest=stdout
            else
              dest=""                                                  # x.pdf -> x.txt beside it
            fi ;;
          *) dest=stdout ;;                                            # pandoc/iconv/in2csv/...: stdout
        esac
      fi
    fi
    [ "${#ops[@]}" -ge 1 ] || continue
    if [ -z "$dest" ]; then
      continue                                                         # stays beside its source
    fi
    for src in "${ops[@]}"; do
      sens="$(bash_first_sensitive_target "$(printf '%q' "$src")")"
      [ -n "$sens" ] || continue
      # S313: a file nobody has cleared (NEEDS_REVIEW / RED) or the user refused (HALTED)
      # may not be copied at all — the copy would carry no status into data/processed/.
      case "$(bash_sidecar_status "$sens")" in
        NEEDS_REVIEW|NEEDS_REVIEW:*|HALTED)
          printf '%s -> %s (%s; source is %s)\n' "$sens" "$dest" "$verb" "$(bash_sidecar_status "$sens")"; return 0 ;;
      esac
      if [ "$dest" != stdout ] && _lr_dest_protected "$dest" "$src"; then continue; fi
      printf '%s -> %s (%s)\n' "$sens" "$dest" "$verb"; return 0
    done
  done <<EOF
$segs
EOF
  return 1
}

# R2-R4 over code text. $1 = code, $2 = restricted path, $3 = inline|script-py|script-r.
_lr_code_violation() {
  local code="$1" sens="$2" mode="$3" st out
  st="$(bash_sidecar_status "$sens")"
  if [ "$st" = HALTED ]; then
    printf 'halted: the user declined processing of %s\n' "$sens"; return 0
  fi
  # S313: an unreviewed INPUT (NEEDS_REVIEW / RED under a raw-data or qualitative path,
  # e.g. a codebook in materials/) is not processed by code either — review it first
  # (/scholar-init), then work under the status it is given. Pipeline artifacts that
  # carry NEEDS_REVIEW (analysis/*.json, design/*.json) are read by the pipeline's own
  # scripts; checked on a real project (9 such reads), so they are left to the other rules.
  case "$st" in NEEDS_REVIEW|NEEDS_REVIEW:*)
    local low; low="$(printf '%s' "$sens" | tr 'A-Z' 'a-z')"
    if is_rawdata_path "$low" || is_qual_path "$low"; then
      printf 'unreviewed: %s is %s; review it before code reads it\n' "$sens" "$st"; return 0
    fi ;;
  esac
  command -v python3 >/dev/null 2>&1 || return 1
  out="$(printf '%s' "$code" | python3 -c "$_LR_PY" "$mode" "$sens" "${CWD:-$PWD}" 2>/dev/null)" || return 1
  [ -n "$out" ] || return 1
  printf '%s in %s\n' "$out" "$sens"
}

# Script paths a command runs (Rscript/python/bash/source()/./x.sh), one per line.
# Same patterns as the guard's phase_order_bash_paths (S268), kept here so the helper
# works with guard copies that predate it.
_lr_run_paths() {
  local rest n ext='(R|r|py|sh|Rmd|qmd)' run re g
  run='(Rscript|python3?|bash|sh|zsh|R[[:space:]]+CMD[[:space:]]+BATCH|quarto[[:space:]]+render)([[:space:]]+-[-A-Za-z]+)*[[:space:]]+'
  local re_q="${run}[\"']([^\"']+\.${ext})[\"']"
  local re_b="${run}([^[:space:];&|()\"']+\.${ext})([[:space:];&|)]|$)"
  local re_f="(source|sys\.source|rmarkdown::render|runpy\.run_path|exec\(open)\([[:space:]]*[\"']([^\"']+\.${ext})[\"']"
  local re_d="(^|[;&|(\`][[:space:]]*)(\./)?([^[:space:];&|()\"'/=]*/[^[:space:];&|()\"'=]+\.${ext})([[:space:];&|)]|$)"
  for re in re_q re_b re_f re_d; do
    rest="${1:-}"; n=0
    case "$re" in re_q|re_b|re_d) g=3 ;; re_f) g=2 ;; esac
    while [ "$n" -lt 20 ] && [[ $rest =~ ${!re} ]]; do
      printf '%s\n' "${BASH_REMATCH[$g]}"
      rest="${rest#*"${BASH_REMATCH[0]}"}"; n=$((n + 1))
    done
  done
}

# Path-like strings in a script body (quoted literals and bare a/b tokens with a slash
# or a data extension) that exist and sit in a protected directory or carry a restricted
# sidecar status, shell-quoted on one line. One python pass narrows ~100 candidates to
# the few the guard's classifier must confirm, keeping R5 near the guard's normal cost.
read -r -d '' _LR_PATHS_PY <<'PY' || true
import json, os, re, shlex, sys
cwd = sys.argv[1]
body = sys.stdin.read()
ext = re.compile(r"\.(csv|tsv|dta|sav|rds|rdata|xlsx?|parquet|feather|arrow|sqlite|db|jsonl|ndjson|json|txt|pdf|docx?|wav|mp3|mp4|zip|gz)$", re.I)
protected = re.compile(r"/(data|raw|input|inputs|datasets?|corpus|corpora|photos|subjects|participants|respondents|media|imagery|"
                       r"scans|originals|source_images|materials|transcripts|interviews|field-?notes|field_notes)(/|$)")
# sidecar keys of the nearest project root (restricted statuses only)
keys, d = set(), os.path.realpath(cwd)
while True:
    sf = os.path.join(d, ".claude", "safety-status.json")
    if os.path.isfile(sf):
        try:
            keys = {k for k, v in json.load(open(sf)).items() if isinstance(v, str) and not v.startswith(("CLEARED", "ANONYMIZED", "OVERRIDE"))}
        except Exception:
            pass
        break
    if os.path.dirname(d) == d:
        break
    d = os.path.dirname(d)
quoted = re.findall(r"[\"']([^\"'\n]{1,300})[\"']", body)
bare = re.findall(r"(?:^|[\s(=,])([^\s\"'`;|&()<>=,]+/[^\s\"'`;|&()<>=,]+)", body)
# Paths built from variables — RAW <- "data/raw"; file.path(RAW, "x.dta"); paste0(RAW, "/x.dta");
# os.path.join(RAW, "x.dta"); RAW / "x.dta" — are how pipeline scripts name their inputs
# (31 of 32 reads in a real CFPS project). Expand the simple cases: every part a string
# literal or a variable assigned one.
var = {}
for _ in range(3):
    for m in re.finditer(r"(?m)^\s*([A-Za-z_.][\w.]*)\s*(?:<-|=)\s*(.+)$", body):
        name, rhs = m.group(1), m.group(2).strip().rstrip(";")
        lit = re.fullmatch(r"[\"']([^\"'\n]+)[\"']", rhs)
        if lit:
            var.setdefault(name, lit.group(1)); continue
        call = re.fullmatch(r"(file\.path|os\.path\.join|paste0|Path)\s*\((.*)\)", rhs)
        parts = [x.strip() for x in call.group(2).split(",")] if call else None
        if call and parts and all(re.fullmatch(r"[\"'][^\"']*[\"']", x) or x in var for x in parts):
            vals = [x[1:-1] if x[:1] in "\"'" else var[x] for x in parts]
            var.setdefault(name, "".join(vals) if call.group(1) == "paste0" else "/".join(v.strip("/") for v in vals))
built = []
for m in re.finditer(r"(file\.path|os\.path\.join|paste0)\s*\(([^()\n]*)\)", body):
    parts = [x.strip() for x in m.group(2).split(",")]
    if parts and all(re.fullmatch(r"[\"'][^\"']*[\"']", x) or x in var for x in parts):
        vals = [x[1:-1] if x[:1] in "\"'" else var[x] for x in parts]
        built.append("".join(vals) if m.group(1) == "paste0" else "/".join(v.strip("/") for v in vals))
for m in re.finditer(r"([A-Za-z_.][\w.]*)\s*/\s*[\"']([^\"'\n]+)[\"']", body):
    if m.group(1) in var:
        built.append(var[m.group(1)].rstrip("/") + "/" + m.group(2))
seen, out = set(), []
for s in quoted + bare + built + list(var.values()):
    if s in seen or not ("/" in s or ext.search(s)):
        continue
    seen.add(s)
    if os.environ.get("LR_LIST_ALL"):
        out.append(shlex.quote(s)); continue
    p = s if os.path.isabs(s) else os.path.join(cwd, s)
    if not os.path.isfile(p):
        continue                                   # files only: absent paths and dirs are not inputs
    real, lex = os.path.realpath(p), os.path.normpath(p)
    if protected.search(real.lower()) or protected.search(lex.lower()) or real in keys or lex in keys:
        out.append(shlex.quote(s))
print(" ".join(out[:100]))
PY
_lr_body_paths() {
  python3 -c "$_LR_PATHS_PY" "${CWD:-$PWD}" 2>/dev/null
}

# R5. Scripts the command runs: existing files inside the project, outside the
# skill's own scripts/ and .claude/ trees, at most 256 KB. One path per line.
_lr_project_scripts() {
  local cmd="$1" tok abs root rootp skill
  root="$(find_project_root "${CWD:-$PWD}" 2>/dev/null || true)"
  [ -n "$root" ] || root="${CWD:-$PWD}"
  rootp="$(cd "$root" 2>/dev/null && pwd -P)"
  skill="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/../.." 2>/dev/null && pwd -P)"
  while IFS= read -r tok; do
    [ -n "$tok" ] || continue
    case "$tok" in /*) abs="$tok" ;; *) abs="${CWD:-$PWD}/$tok" ;; esac
    [ -f "$abs" ] || continue
    abs="$(cd "$(dirname "$abs")" 2>/dev/null && pwd -P)/$(basename "$abs")"
    case "$abs" in "$skill"/scripts/*|"$skill"/.claude/*) continue ;; esac
    case "$abs" in "$rootp"/*|"$root"/*) : ;; *) continue ;; esac
    [ "$(wc -c < "$abs" 2>/dev/null | tr -d ' ')" -le "$_LR_MAX_SCRIPT_BYTES" ] 2>/dev/null || continue
    printf '%s\n' "$abs"
  done < <(_lr_run_paths "$cmd")
}

# Does the command run a script that lives in the skill's own scripts/ tree?
# Trusted roots: this helper's skill, the repo that bundles it (…/.claude/skills/<name>
# → the repo root), and $SCHOLAR_SKILL_DIR.
_lr_runs_skill_tool() {
  local tok abs skill repo sd
  skill="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/../.." 2>/dev/null && pwd -P)"
  case "$skill" in */.claude/skills/*) repo="${skill%/.claude/skills/*}" ;; *) repo="$skill" ;; esac
  sd="$(cd "${SCHOLAR_SKILL_DIR:-/nonexistent}" 2>/dev/null && pwd -P)"
  while IFS= read -r tok; do
    [ -n "$tok" ] || continue
    case "$tok" in /*) abs="$tok" ;; *) abs="${CWD:-$PWD}/$tok" ;; esac
    [ -f "$abs" ] || continue
    abs="$(cd "$(dirname "$abs")" 2>/dev/null && pwd -P)/$(basename "$abs")"
    case "$abs" in "$skill"/scripts/*|"$repo"/scripts/*) return 0 ;; esac
    if [ -n "$sd" ]; then case "$abs" in "$sd"/scripts/*) return 0 ;; esac; fi
  done < <(_lr_run_paths "$1")
  return 1
}

# Entry point. 0 = block (reason on stdout), 1 = allow.
lr_bash_verdict() {
  local cmd="$1" sens hit script body cands _m
  hit="$(lr_copy_violation "$cmd")" && { printf 'R1 copy out of protection: %s\n' "$hit"; return 0; }
  sens="$(bash_first_sensitive_target "$cmd")"
  # The skill's own tools (safety-scan, anonymize-presidio under scripts/gates/) are how
  # an unreviewed file GETS reviewed; their runs are not inline analysis code.
  if [ -n "$sens" ] && _lr_runs_skill_tool "$cmd"; then sens=""; fi
  if [ -n "$sens" ]; then
    case "$(bash_primary_verb "$cmd")" in
      python|python2|python3|rscript|r|ruby|node|nodejs|php|lua|perl)
        hit="$(_lr_code_violation "$cmd" "$sens" inline)" && { printf 'R2-R4 %s\n' "$hit"; return 0; } ;;
    esac
  fi
  while IFS= read -r script; do
    [ -n "$script" ] || continue
    body="$(cat "$script" 2>/dev/null)" || continue
    cands="$(printf '%s' "$body" | _lr_body_paths)"
    [ -n "$cands" ] || continue
    sens="$(bash_first_sensitive_target "$cands")"
    [ -n "$sens" ] || continue
    case "$script" in
      *.sh)
        hit="$(lr_copy_violation "$body")" && { printf 'R5 %s copies %s\n' "$script" "$hit"; return 0; }
        if bash_command_is_dump "$body" "$sens"; then
          printf 'R5 %s dumps %s\n' "$script" "$sens"; return 0
        fi ;;
      *)
        case "$script" in *.py) _m=script-py ;; *) _m=script-r ;; esac
        hit="$(_lr_code_violation "$body" "$sens" "$_m")" && { printf 'R5 %s: %s\n' "$script" "$hit"; return 0; } ;;
    esac
  done < <(_lr_project_scripts "$cmd")
  return 1
}
