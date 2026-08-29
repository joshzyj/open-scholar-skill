#!/usr/bin/env bash
# Shared assertion/result/lifecycle harness for scholar-auto-research tests.
# Source this file.  Semantic expectations come only from coverage-manifest.json.

if [ "${_SCHOLAR_AUTO_RESEARCH_HARNESS_SOURCED:-0}" = "1" ]; then
  return 0 2>/dev/null || exit 0
fi
_SCHOLAR_AUTO_RESEARCH_HARNESS_SOURCED=1

# Python bytecode is runtime cache state, not authored test source.  Suppress it
# before any helper invocation so the harness cannot invalidate its own frozen
# source-generation binding.
export PYTHONDONTWRITEBYTECODE=1

_HARNESS_HELPER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_HARNESS_CASE_TOOL="$_HARNESS_HELPER_DIR/case_result.py"
_HARNESS_INITIALIZED=0
_HARNESS_TEMP_INITIALIZED=0
_HARNESS_OWNED_ROOT=""
_HARNESS_OWNED_NONCE=""
_HARNESS_OWNED_PARENT=""
_HARNESS_CAPABILITY=""

_harness_error() {
  echo "$*" >&2
  return 1
}

_harness_require_env() {
  local name="$1"
  [ -n "${!name:-}" ] || _harness_error "HARNESS_ENV_REQUIRED: $name"
}

harness_init() {
  # harness_init <absolute-test-path> <runner-label>
  [ "$#" -eq 2 ] || { _harness_error "HARNESS_USAGE: harness_init <test-path> <runner-label>"; return 1; }
  [ "$_HARNESS_INITIALIZED" -eq 0 ] || { _harness_error "HARNESS_ALREADY_INITIALIZED"; return 1; }
  [ -f "$_HARNESS_CASE_TOOL" ] || { _harness_error "HARNESS_HELPER_MISSING: $_HARNESS_CASE_TOOL"; return 1; }

  local name
  for name in \
    SCHOLAR_HARNESS_SOURCE_ROOT SCHOLAR_HARNESS_MANIFEST \
    SCHOLAR_HARNESS_RESULTS_DIR SCHOLAR_HARNESS_RUN_ID \
    SCHOLAR_HARNESS_RUN_NONCE SCHOLAR_HARNESS_SUITE_MODE \
    SCHOLAR_HARNESS_SUITE_ORDER SCHOLAR_HARNESS_MANIFEST_SHA256 \
    SCHOLAR_HARNESS_SOURCE_GENERATION_SHA256; do
    _harness_require_env "$name" || return 1
  done

  _HARNESS_TEST_PATH="$1"
  _HARNESS_RUNNER_LABEL="$2"

  local capability="${SCHOLAR_HARNESS_CAPABILITY:-}"
  unset SCHOLAR_HARNESS_CAPABILITY
  if [ -f "$SCHOLAR_HARNESS_RESULTS_DIR/.run-context.json" ]; then
    [ -n "$capability" ] || { _harness_error "HARNESS_ENV_REQUIRED: SCHOLAR_HARNESS_CAPABILITY"; return 1; }
    python3 "$_HARNESS_CASE_TOOL" check-run \
      --result-dir "$SCHOLAR_HARNESS_RESULTS_DIR" \
      --capability "$capability" \
      --run-id "$SCHOLAR_HARNESS_RUN_ID" \
      --run-nonce "$SCHOLAR_HARNESS_RUN_NONCE" \
      --suite-mode "$SCHOLAR_HARNESS_SUITE_MODE" \
      --suite-order "$SCHOLAR_HARNESS_SUITE_ORDER" \
      --manifest-sha256 "$SCHOLAR_HARNESS_MANIFEST_SHA256" \
      --source-generation-sha256 "$SCHOLAR_HARNESS_SOURCE_GENERATION_SHA256" \
      >/dev/null || return 1
  else
    [ ! -e "$SCHOLAR_HARNESS_RESULTS_DIR" ] || {
      _harness_error "HARNESS_RESULTS_NOT_FRESH: $SCHOLAR_HARNESS_RESULTS_DIR"
      return 1
    }
    capability="$(python3 "$_HARNESS_CASE_TOOL" init-run \
      --result-dir "$SCHOLAR_HARNESS_RESULTS_DIR" \
      --source-root "$SCHOLAR_HARNESS_SOURCE_ROOT" \
      --manifest "$SCHOLAR_HARNESS_MANIFEST" \
      --run-id "$SCHOLAR_HARNESS_RUN_ID" \
      --run-nonce "$SCHOLAR_HARNESS_RUN_NONCE" \
      --suite-mode "$SCHOLAR_HARNESS_SUITE_MODE" \
      --suite-order "$SCHOLAR_HARNESS_SUITE_ORDER" \
      --manifest-sha256 "$SCHOLAR_HARNESS_MANIFEST_SHA256" \
      --source-generation-sha256 "$SCHOLAR_HARNESS_SOURCE_GENERATION_SHA256")" || return 1
  fi
  _HARNESS_CAPABILITY="$capability"
  _HARNESS_INITIALIZED=1
}

_harness_cleanup_owned_root() {
  [ "$_HARNESS_TEMP_INITIALIZED" -eq 1 ] || return 0
  if [ "${SCHOLAR_KEEP_FIXTURE:-0}" = "1" ]; then
    echo "HARNESS_FIXTURE_PRESERVED=$_HARNESS_OWNED_ROOT" >&2
    return 0
  fi
  [ -e "$_HARNESS_OWNED_ROOT" ] || return 0
  python3 "$_HARNESS_CASE_TOOL" cleanup-owned-root \
    --root "$_HARNESS_OWNED_ROOT" --nonce "$_HARNESS_OWNED_NONCE" \
    --tmp-parent "$_HARNESS_OWNED_PARENT"
}

_harness_on_exit() {
  local rc=$?
  trap - EXIT
  if ! _harness_cleanup_owned_root; then
    rc=1
  fi
  exit "$rc"
}

_harness_on_signal() {
  local rc="$1"
  trap - HUP INT TERM
  exit "$rc"
}

harness_make_temp_root() {
  # harness_make_temp_root <caller-variable-name> [prefix]
  [ "$#" -ge 1 ] && [ "$#" -le 2 ] || {
    _harness_error "HARNESS_USAGE: harness_make_temp_root <variable> [prefix]"
    return 1
  }
  [ "$_HARNESS_TEMP_INITIALIZED" -eq 0 ] || { _harness_error "HARNESS_TEMP_ROOT_ALREADY_CREATED"; return 1; }
  case "$1" in
    ''|*[!A-Za-z0-9_]*) _harness_error "HARNESS_VARIABLE_INVALID: $1"; return 1 ;;
  esac
  if [ "${SCHOLAR_HARNESS_SUITE_MODE:-}" = "release" ] && [ "${SCHOLAR_KEEP_FIXTURE:-0}" = "1" ]; then
    _harness_error "HARNESS_KEEP_FORBIDDEN_IN_RELEASE"
    return 1
  fi
  if [ -n "$(trap -p EXIT)" ]; then
    _harness_error "HARNESS_EXIT_TRAP_ALREADY_SET"
    return 1
  fi

  local prefix="${2:-scholar-auto-research-test}"
  local base="${TMPDIR:-/tmp}" proposal
  proposal="$(python3 "$_HARNESS_CASE_TOOL" prepare-owned-root --tmpdir "$base" --prefix "$prefix")" || return 1
  IFS=$'\t' read -r _HARNESS_OWNED_ROOT _HARNESS_OWNED_NONCE _HARNESS_OWNED_PARENT <<< "$proposal"
  [ -n "$_HARNESS_OWNED_ROOT" ] && [ -n "$_HARNESS_OWNED_NONCE" ] && [ -n "$_HARNESS_OWNED_PARENT" ] \
    || { _harness_error "HARNESS_TEMP_PROPOSAL_INVALID"; return 1; }
  _HARNESS_TEMP_INITIALIZED=1
  trap '_harness_on_exit' EXIT
  trap '_harness_on_signal 129' HUP
  trap '_harness_on_signal 130' INT
  trap '_harness_on_signal 143' TERM
  python3 "$_HARNESS_CASE_TOOL" create-owned-root \
    --root "$_HARNESS_OWNED_ROOT" --nonce "$_HARNESS_OWNED_NONCE" \
    --tmp-parent "$_HARNESS_OWNED_PARENT" || return 1
  printf -v "$1" '%s' "$_HARNESS_OWNED_ROOT"
}

harness_cleanup() {
  _harness_cleanup_owned_root || return 1
  _HARNESS_TEMP_INITIALIZED=0
  _HARNESS_OWNED_ROOT=""
  _HARNESS_OWNED_NONCE=""
  _HARNESS_OWNED_PARENT=""
  trap - EXIT HUP INT TERM
}

_harness_count_exact_lines() {
  local expected="$1" path="$2" count=0 line
  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$line" = "$expected" ]; then
      count=$((count + 1))
    fi
  done < "$path"
  printf '%s\n' "$count"
}

_harness_show_capture() {
  local stdout_file="$1" stderr_file="$2"
  echo "--- captured stdout ---" >&2
  if [ -s "$stdout_file" ]; then cat "$stdout_file" >&2; else echo "<empty>" >&2; fi
  echo "--- captured stderr ---" >&2
  if [ -s "$stderr_file" ]; then cat "$stderr_file" >&2; else echo "<empty>" >&2; fi
}

_harness_run_production() (
  # Keep shell functions callable while creating a subprocess boundary whose
  # environment contains neither capability name nor any exported alias of
  # the capability value.  Disable allexport before creating local scratch.
  set +a
  local capability_value="$_HARNESS_CAPABILITY" exported_name
  while IFS= read -r exported_name; do
    if [ "$exported_name" = "SCHOLAR_HARNESS_CAPABILITY" ] \
        || [ "$exported_name" = "_HARNESS_CAPABILITY" ] \
        || [ "${!exported_name-}" = "$capability_value" ]; then
      unset "$exported_name" || {
        echo "HARNESS_CAPABILITY_ENV_UNSAFE: $exported_name" >&2
        return 125
      }
    fi
  done < <(compgen -e)
  unset SCHOLAR_HARNESS_CAPABILITY _HARNESS_CAPABILITY capability_value exported_name
  "$@"
)

_harness_expect() {
  local invoked="$1" case_id="$2" project_root="$3"
  shift 3
  [ "$_HARNESS_INITIALIZED" -eq 1 ] || { _harness_error "HARNESS_NOT_INITIALIZED"; return 1; }
  [ "$_HARNESS_TEMP_INITIALIZED" -eq 1 ] || { _harness_error "HARNESS_TEMP_ROOT_REQUIRED"; return 1; }
  [ "$#" -ge 2 ] && [ "$1" = "--" ] || {
    _harness_error "HARNESS_USAGE: expect_$invoked <case-id> <project-root> -- <command> [args...]"
    return 1
  }
  shift

  local manifest_polarity expected_rc diagnostic_kind expected_diagnostic
  manifest_polarity="$(python3 "$_HARNESS_CASE_TOOL" case-field --manifest "$SCHOLAR_HARNESS_MANIFEST" --case-id "$case_id" --field polarity)" || return 1
  if [ "$invoked" = "reject" ]; then
    [ "$manifest_polarity" = "negative" ] || {
      _harness_error "HARNESS_POLARITY_BINDING: $case_id must be negative"
      return 1
    }
  elif [ "$manifest_polarity" = "negative" ]; then
    _harness_error "HARNESS_POLARITY_BINDING: $case_id negative case invoked with expect_pass"
    return 1
  fi
  python3 "$_HARNESS_CASE_TOOL" check-case \
    --manifest "$SCHOLAR_HARNESS_MANIFEST" \
    --source-root "$SCHOLAR_HARNESS_SOURCE_ROOT" \
    --case-id "$case_id" \
    --test-path "$_HARNESS_TEST_PATH" \
    --runner-label "$_HARNESS_RUNNER_LABEL" \
    --polarity "$manifest_polarity" >/dev/null || return 1
  expected_rc="$(python3 "$_HARNESS_CASE_TOOL" case-field --manifest "$SCHOLAR_HARNESS_MANIFEST" --case-id "$case_id" --field expected_exit.value)" || return 1
  diagnostic_kind="$(python3 "$_HARNESS_CASE_TOOL" case-field --manifest "$SCHOLAR_HARNESS_MANIFEST" --case-id "$case_id" --field diagnostic_match.kind)" || return 1
  expected_diagnostic="$(python3 "$_HARNESS_CASE_TOOL" case-field --manifest "$SCHOLAR_HARNESS_MANIFEST" --case-id "$case_id" --field diagnostic_match.value)" || return 1
  if [ "$invoked" = "reject" ]; then
    [ "$expected_rc" -ne 0 ] || { _harness_error "HARNESS_REJECT_EXIT_INVALID: $case_id"; return 1; }
    [ "$diagnostic_kind" = "exact" ] && [ -n "$expected_diagnostic" ] || {
      _harness_error "HARNESS_REJECT_DIAGNOSTIC_INVALID: $case_id"
      return 1
    }
  fi

  local assertion_dir before after delta stdout_file stderr_file
  assertion_dir="$(mktemp -d "$_HARNESS_OWNED_ROOT/assertion.$case_id.XXXXXX")" || return 1
  before="$assertion_dir/before.json"
  after="$assertion_dir/after.json"
  delta="$assertion_dir/delta.json"
  stdout_file="$assertion_dir/stdout"
  stderr_file="$assertion_dir/stderr"
  python3 "$_HARNESS_CASE_TOOL" snapshot --manifest "$SCHOLAR_HARNESS_MANIFEST" \
    --case-id "$case_id" --project-root "$project_root" --output "$before" || return 1

  local observed_rc
  if _harness_run_production "$@" >"$stdout_file" 2>"$stderr_file"; then
    observed_rc=0
  else
    observed_rc=$?
  fi
  python3 "$_HARNESS_CASE_TOOL" snapshot --manifest "$SCHOLAR_HARNESS_MANIFEST" \
    --case-id "$case_id" --project-root "$project_root" --output "$after" || return 1

  local delta_verdict="PASS" delta_output=""
  if delta_output="$(python3 "$_HARNESS_CASE_TOOL" compare --manifest "$SCHOLAR_HARNESS_MANIFEST" \
      --case-id "$case_id" --before "$before" --after "$after" --output "$delta" 2>&1)"; then
    delta_verdict="PASS"
  else
    delta_verdict="FAIL"
  fi

  local status="PASS" observed_diagnostic="" diagnostic_count=0 reasons=""
  if [ "$observed_rc" -ne "$expected_rc" ]; then
    status="FAIL"
    reasons="${reasons}wrong exit expected=$expected_rc observed=$observed_rc; "
  fi
  if [ "$diagnostic_kind" = "exact" ]; then
    local stdout_count stderr_count
    stdout_count="$(_harness_count_exact_lines "$expected_diagnostic" "$stdout_file")"
    stderr_count="$(_harness_count_exact_lines "$expected_diagnostic" "$stderr_file")"
    diagnostic_count=$((stdout_count + stderr_count))
    if [ "$diagnostic_count" -eq 1 ]; then
      observed_diagnostic="$expected_diagnostic"
    else
      status="FAIL"
      reasons="${reasons}exact diagnostic count expected=1 observed=$diagnostic_count; "
    fi
  elif [ "$diagnostic_kind" != "none" ]; then
    status="FAIL"
    reasons="${reasons}unsupported diagnostic kind=$diagnostic_kind; "
  fi
  if [ "$delta_verdict" != "PASS" ]; then
    status="FAIL"
    reasons="${reasons}authoritative state delta failed; "
  fi

  local transcript_verdict="not_applicable" transcript_output=""
  if transcript_output="$(python3 "$_HARNESS_CASE_TOOL" validate-transcript \
      --manifest "$SCHOLAR_HARNESS_MANIFEST" --case-id "$case_id" \
      --source-root "$SCHOLAR_HARNESS_SOURCE_ROOT" --project-root "$project_root" \
      --after "$after" \
      --stdout-file "$stdout_file" --stderr-file "$stderr_file" 2>&1)"; then
    case "$transcript_output" in
      *HARNESS_TRANSCRIPT_VERDICT=PASS*) transcript_verdict="PASS" ;;
      *) transcript_verdict="not_applicable" ;;
    esac
  else
    transcript_verdict="FAIL"
    status="FAIL"
    reasons="${reasons}transcript policy failed; "
  fi

  local postcondition_verdict="not_applicable" postcondition_output=""
  if postcondition_output="$(python3 "$_HARNESS_CASE_TOOL" validate-postconditions \
      --manifest "$SCHOLAR_HARNESS_MANIFEST" --case-id "$case_id" \
      --project-root "$project_root" --after "$after" 2>&1)"; then
    case "$postcondition_output" in
      *HARNESS_POSTCONDITION_VERDICT=PASS*) postcondition_verdict="PASS" ;;
      *) postcondition_verdict="not_applicable" ;;
    esac
  else
    postcondition_verdict="FAIL"
    status="FAIL"
    reasons="${reasons}postcondition policy failed; "
  fi

  local stdout_sha stderr_sha recorder_output recorder_rc=0
  stdout_sha="$(python3 "$_HARNESS_CASE_TOOL" digest-file "$stdout_file")" || return 1
  stderr_sha="$(python3 "$_HARNESS_CASE_TOOL" digest-file "$stderr_file")" || return 1
  if recorder_output="$(SCHOLAR_HARNESS_INTERNAL_CALL=1 python3 "$_HARNESS_CASE_TOOL" record \
      --result-dir "$SCHOLAR_HARNESS_RESULTS_DIR" \
      --capability "$_HARNESS_CAPABILITY" \
      --case-id "$case_id" \
      --test-path "$_HARNESS_TEST_PATH" \
      --runner-label "$_HARNESS_RUNNER_LABEL" \
      --project-root "$project_root" \
      --after "$after" \
      --observed-exit "$observed_rc" \
      --observed-exact-diagnostic "$observed_diagnostic" \
      --diagnostic-count "$diagnostic_count" \
      --stdout-file "$stdout_file" \
      --stderr-file "$stderr_file" \
      --stdout-sha256 "$stdout_sha" \
      --stderr-sha256 "$stderr_sha" \
      --mutation-verdict "${SCHOLAR_HARNESS_MUTATION_VERDICT:-not_applicable}" \
      --state-delta-verdict "$delta_verdict" \
      --terminal-status "$status" 2>&1)"; then
    recorder_rc=0
  else
    recorder_rc=$?
    status="FAIL"
    reasons="${reasons}case recorder refused; "
  fi

  if [ "$status" != "PASS" ]; then
    echo "HARNESS_ASSERTION_FAILED: case=$case_id ${reasons% }" >&2
    [ -z "$delta_output" ] || echo "$delta_output" >&2
    [ "$transcript_verdict" != "FAIL" ] || echo "$transcript_output" >&2
    [ "$postcondition_verdict" != "FAIL" ] || echo "$postcondition_output" >&2
    [ "$recorder_rc" -eq 0 ] || echo "$recorder_output" >&2
    _harness_show_capture "$stdout_file" "$stderr_file"
    return 1
  fi
  echo "HARNESS_CASE_PASS=$case_id"
}

expect_pass() {
  [ "$#" -ge 4 ] || { _harness_error "HARNESS_USAGE: expect_pass <case-id> <project-root> -- <command>"; return 1; }
  _harness_expect pass "$@"
}

expect_reject() {
  [ "$#" -ge 4 ] || { _harness_error "HARNESS_USAGE: expect_reject <case-id> <project-root> -- <command>"; return 1; }
  _harness_expect reject "$@"
}

harness_validate_results() {
  [ "$_HARNESS_INITIALIZED" -eq 1 ] || { _harness_error "HARNESS_NOT_INITIALIZED"; return 1; }
  if [ "$#" -eq 2 ] && [ "$1" = "--phase-through" ]; then
    python3 "$_HARNESS_CASE_TOOL" validate-results \
      --result-dir "$SCHOLAR_HARNESS_RESULTS_DIR" \
      --capability "$_HARNESS_CAPABILITY" \
      --test-path "$_HARNESS_TEST_PATH" \
      --runner-label "$_HARNESS_RUNNER_LABEL" \
      --phase-through "$2"
  elif [ "$#" -eq 2 ] && [ "$1" = "--checkpoint" ]; then
    python3 "$_HARNESS_CASE_TOOL" validate-results \
      --result-dir "$SCHOLAR_HARNESS_RESULTS_DIR" \
      --capability "$_HARNESS_CAPABILITY" \
      --test-path "$_HARNESS_TEST_PATH" \
      --runner-label "$_HARNESS_RUNNER_LABEL" \
      --checkpoint "$2"
  elif [ "$#" -ne 0 ]; then
    _harness_error "HARNESS_USAGE: harness_validate_results [--phase-through N|--checkpoint NAME]"
    return 1
  else
    python3 "$_HARNESS_CASE_TOOL" validate-results \
      --result-dir "$SCHOLAR_HARNESS_RESULTS_DIR" \
      --capability "$_HARNESS_CAPABILITY" \
      --test-path "$_HARNESS_TEST_PATH" \
      --runner-label "$_HARNESS_RUNNER_LABEL"
  fi
}

harness_lint() {
  [ "$#" -ge 1 ] || { _harness_error "HARNESS_USAGE: harness_lint <path> [path...]"; return 1; }
  python3 "$_HARNESS_CASE_TOOL" lint \
    --manifest "$SCHOLAR_HARNESS_MANIFEST" \
    --source-root "$SCHOLAR_HARNESS_SOURCE_ROOT" "$@"
}
