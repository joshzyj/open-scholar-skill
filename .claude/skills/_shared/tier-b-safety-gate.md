# Tier B Safety Gate — Lightweight Sidecar Check

Skills that occasionally touch user data but do not implement the full LOCAL_MODE contract (scholar-data, scholar-verify, scholar-replication, scholar-code-review, scholar-write) MUST run the Tier B sidecar check before any `Read` call that targets a user data file.

This is the *lightweight* half of the v5.8.0 data-safety stack. Unlike scholar-eda / scholar-analyze / scholar-compute / scholar-ling (Tier A, which dispatch to LOCAL_MODE `Rscript -e` heredocs), Tier B skills simply consult the sidecar written by `/scholar-init` and fail fast with a clear message if the file is not safe to Read. The PreToolUse hook (`scripts/gates/pretooluse-data-guard.sh`) still provides the mechanical backstop — this gate just makes the failure happen earlier and with a more actionable error.

## Contract

The gate MUST run before the first `Read` / `NotebookRead` / `Grep` / `Glob` call that targets a user data file (CSV, .dta, .rds, .parquet, .xlsx, .sav, etc.). It does NOT need to run before reading manuscripts, scripts, logs, or reference documents.

Allowed statuses (proceed):
- `CLEARED` — safe, open data
- `ANONYMIZED` — de-identified derivative exists; the skill should Read the derivative, never the raw file
- `OVERRIDE` — user explicitly waived the scan; qualitative audio/video formats are refused at the hook level regardless

Refused statuses (halt with a clear message):
- `NEEDS_REVIEW:*` — user has not triaged this file; direct them to `/scholar-init review`
- `HALTED` — the file is off-limits; do not proceed
- `LOCAL_MODE` — this file must be loaded via a Bash-only heredoc. Tier B skills do not implement that path. Direct the user to `/scholar-analyze` or `/scholar-eda`.

Missing from sidecar or no sidecar at all → proceed; the PreToolUse hook remains the only line of defense.

## Canonical bash snippet

```bash
# ── Tier B safety gate: sidecar check ──
# Consult .claude/safety-status.json for every file argument that looks
# like a user data file. Halts the skill with a clear message when the
# sidecar says the file is not safe to Read.
#
# FILE_ARGS should be the list of candidate data-file paths parsed from
# $ARGUMENTS. The gate is a no-op when .claude/safety-status.json does
# not exist (project was not initialized via /scholar-init).

SIDECAR=".claude/safety-status.json"
if [ -f "$SIDECAR" ] && command -v jq >/dev/null 2>&1; then
  UNSAFE=""
  for F in $FILE_ARGS; do
    [ -f "$F" ] || continue
    # Canonicalize: python3 → realpath → readlink -f → raw path
    ABS=$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$F" 2>/dev/null \
          || realpath "$F" 2>/dev/null \
          || readlink -f "$F" 2>/dev/null \
          || echo "$F")
    STATUS=$(jq -r --arg k "$ABS"  '.[$k] // empty' "$SIDECAR")
    if [ -z "$STATUS" ]; then
      STATUS=$(jq -r --arg k "$F" '.[$k] // empty' "$SIDECAR")
    fi
    case "$STATUS" in
      CLEARED|ANONYMIZED|OVERRIDE|"") ;;  # safe or unregistered — proceed
      NEEDS_REVIEW:*)
        UNSAFE="${UNSAFE}
  - $F → $STATUS  (run: /scholar-init review)" ;;
      HALTED)
        UNSAFE="${UNSAFE}
  - $F → HALTED  (off-limits)" ;;
      LOCAL_MODE)
        UNSAFE="${UNSAFE}
  - $F → LOCAL_MODE  (use /scholar-analyze or /scholar-eda — Tier B skills do not implement LOCAL_MODE)" ;;
      *)
        UNSAFE="${UNSAFE}
  - $F → $STATUS  (unrecognized; resolve via /scholar-init review)" ;;
    esac
  done
  if [ -n "$UNSAFE" ]; then
    cat >&2 <<HALTMSG
⛔ HALT — Tier B safety gate refused the following file(s):
$UNSAFE

See _shared/data-handling-policy.md for the full SAFETY_STATUS state machine.
HALTMSG
    exit 1
  fi
  echo "✓ Tier B safety gate: all files CLEARED / ANONYMIZED / OVERRIDE / unregistered"
fi
```

## Integration notes

- **Where to run it**: At the top of the skill, after argument parsing but before any Read-tool call targeting a data file. Exact step number depends on the skill.
- **Missing jq**: Fail closed by writing a visible warning; the PreToolUse hook will then catch any subsequent unsafe Read.
- **Not applicable to**: Skills that never touch data files (scholar-idea, scholar-hypothesis, scholar-lit-review, scholar-citation, scholar-respond, scholar-journal, scholar-conceptual, scholar-polish, scholar-ethics, scholar-collaborate, scholar-open, scholar-auto-improve, scholar-design, scholar-causal, scholar-knowledge, sync-docs). The PreToolUse hook provides the backstop for these.
- **Tier A alternative**: If the skill DOES implement LOCAL_MODE dispatch (scholar-eda / scholar-analyze / scholar-compute / scholar-ling), use the Tier A Step 0 gate documented in `_shared/data-handling-policy.md` §1 instead. Tier A dispatches to `Rscript -e` heredocs on `LOCAL_MODE`; Tier B refuses.
