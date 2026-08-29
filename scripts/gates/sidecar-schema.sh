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
#   - TWO reserved meta keys are allowed:
#       "_safety_level" — the per-project safety tier; value MUST be one of
#           standard | strict | lockdown.
#       "_meta" — the no-data declaration; value MUST be exactly
#           "no-data-project". This is the form phase-early-hardstops.sh has
#           always PRINTED as the way to assert a no-data project; until
#           2026-08-23 (system-fix P0.1) the schema rejected it, so following
#           the printed advice produced a RED. The hardstop verifies the
#           declaration against disk — it is not honor-system (see
#           phase-early-hardstops.sh no-data branch).
#     Any other underscore-prefixed key is a schema violation (so a typoed
#     meta key cannot silently pass).
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
    # NEEDS_REVIEW, or NEEDS_REVIEW:LEVEL with a NON-EMPTY level. `?*` requires
    # at least one char after the colon, so a malformed `NEEDS_REVIEW:` (empty
    # level) is rejected — matching validate_sidecar_schema's `NEEDS_REVIEW(:.+)?`.
    NEEDS_REVIEW|NEEDS_REVIEW:?*) return 0 ;;
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
            if (.key | startswith("_")) then
              # Reserved meta keys: "_safety_level" and "_meta" (P0.1).
              if .key == "_safety_level" then
                if (.value | type) != "string" then
                  "  - \(.key): non-string value (\(.value | type))"
                elif (.value | test("^(standard|strict|lockdown)$")) | not then
                  "  - \(.key): unknown safety level \"\(.value)\" (want standard|strict|lockdown)"
                else empty end
              elif .key == "_meta" then
                if (.value | type) != "string" then
                  "  - \(.key): non-string value (\(.value | type))"
                elif .value != "no-data-project" then
                  "  - \(.key): unknown value \"\(.value)\" (only \"no-data-project\" is recognized)"
                else empty end
              else
                "  - \(.key): unknown meta key (only _safety_level and _meta are allowed)"
              end
            elif (.value | type) != "string" then
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

# ─── resolve_safety_level ───────────────────────────────────────────────
# Resolve the active safety tier for a project: the per-project
# "_safety_level" sidecar key wins; else the global SCHOLAR_SAFETY_LEVEL env
# var; else "standard". Always prints one of standard|strict|lockdown.
#   $1 = path to the project's .claude/safety-status.json (may be empty/absent)
resolve_safety_level() {
  local sidecar="$1" lvl=""
  if [ -n "$sidecar" ] && [ -f "$sidecar" ] && command -v jq >/dev/null 2>&1; then
    lvl="$(jq -r '(._safety_level // empty) | if type=="string" then . else empty end' "$sidecar" 2>/dev/null || true)"
  fi
  case "$lvl" in standard|strict|lockdown) printf '%s' "$lvl"; return 0 ;; esac
  case "${SCHOLAR_SAFETY_LEVEL:-}" in standard|strict|lockdown) printf '%s' "${SCHOLAR_SAFETY_LEVEL}"; return 0 ;; esac
  printf 'standard'
}
