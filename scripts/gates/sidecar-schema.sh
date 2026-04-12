#!/usr/bin/env bash
# sidecar-schema.sh — shared schema validator for .claude/safety-status.json.
#
# Sourced by both scripts/gates/pretooluse-data-guard.sh and
# scripts/gates/init-handshake.sh so the two cannot diverge on what
# constitutes a valid sidecar entry.
#
# Contract:
#   - The sidecar is a JSON object mapping absolute file paths to
#     status strings.
#   - Every value MUST be a string.
#   - Every value MUST match one of:
#         CLEARED | ANONYMIZED | OVERRIDE | LOCAL_MODE | HALTED |
#         NEEDS_REVIEW | NEEDS_REVIEW:LEVEL
#     where LEVEL is any non-empty token (e.g., GREEN / YELLOW / RED).
#
# Anything else — object-valued entries, arrays, typoed statuses — is a
# schema violation. Both callers fail closed on schema violations.
#
# Provides:
#   is_valid_status <string>         — returns 0 iff the status is allowed
#   validate_sidecar_schema <file>   — prints a diagnostic list on stderr
#                                      and returns 1 if any entry is
#                                      invalid; returns 0 for a missing
#                                      or fully-valid file.
#
# Both functions require jq for parsing JSON.

# ─── is_valid_status ────────────────────────────────────────────────────
is_valid_status() {
  case "$1" in
    CLEARED|ANONYMIZED|OVERRIDE|LOCAL_MODE|HALTED) return 0 ;;
    NEEDS_REVIEW|NEEDS_REVIEW:*) return 0 ;;
  esac
  return 1
}

# ─── validate_sidecar_schema ────────────────────────────────────────────
# Writes a violation list to stdout (one "  - key: reason" line per bad
# entry) and returns 1 if any violations are found; returns 0 for a
# fully-valid file (including one that does not exist).
validate_sidecar_schema() {
  local file="$1"
  [ -f "$file" ] || return 0
  if ! command -v jq >/dev/null 2>&1; then
    # Caller is responsible for handling the no-jq case. We can't
    # validate without jq, so return 1 to force fail-closed.
    printf '  - (cannot validate: jq not installed)\n'
    return 1
  fi
  local invalid
  invalid="$(jq -r '
      if type != "object" then
        "  - <root>: not a JSON object"
      else
        to_entries
        | map(
            if (.value | type) != "string" then
              "  - \(.key): non-string value (\(.value | type))"
            elif (.value | test("^(CLEARED|ANONYMIZED|OVERRIDE|LOCAL_MODE|HALTED|NEEDS_REVIEW(:.+)?)$")) | not then
              "  - \(.key): unknown status \"\(.value)\""
            else empty
            end
          )
        | .[]
      end
    ' "$file" 2>/dev/null)"
  if [ -n "$invalid" ]; then
    printf '%s\n' "$invalid"
    return 1
  fi
  return 0
}
