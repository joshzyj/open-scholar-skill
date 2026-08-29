#!/usr/bin/env bash
set -euo pipefail

SKILL_DIR="${SCHOLAR_AUTO_RESEARCH_TEST_SKILL_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/scholar-auto-research-review-contract.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

for mutation in unknown_assurance duplicate_roles unmapped_role empty_inputs invalid_root unknown_host_claim missing_binding invalid_binding_field; do
  copy="$TMP_ROOT/$mutation"
  cp -R "$SKILL_DIR" "$copy"
  python3 - "$copy/references/phase-contract.json" "$mutation" <<'PY'
import json, sys
path, mutation = sys.argv[1:]
doc = json.load(open(path, encoding="utf-8"))
phase = next(item for item in doc["phases"] if str(item["id"]) == "6")
policy = phase["review_evidence_policy"]
round_policy = policy["rounds"]["initial_panel"]
if mutation == "unknown_assurance":
    policy["minimum_assurance"] = "magic_attestation"
elif mutation == "duplicate_roles":
    round_policy["roles"].append(round_policy["roles"][0])
elif mutation == "unmapped_role":
    round_policy["roles"][0] = "unmapped_plausible_role"
elif mutation == "empty_inputs":
    round_policy["input_patterns"] = []
elif mutation == "invalid_root":
    policy["evidence_root"] = "../outside"
elif mutation == "unknown_host_claim":
    policy["strict_required_host_claims"].append("magic_claim")
elif mutation == "missing_binding":
    round_policy.pop("binding_collection")
elif mutation == "invalid_binding_field":
    round_policy["task_id_field"] = "../task"
with open(path, "w", encoding="utf-8") as out:
    json.dump(doc, out, indent=2, sort_keys=True)
    out.write("\n")
PY
  set +e
  bash "$copy/scripts/auto-research-contract-lint.sh" >"$TMP_ROOT/$mutation.out" 2>&1
  rc=$?
  set -e
  [ "$rc" -ne 0 ] || fail "contract lint accepted $mutation"
  case "$mutation" in
    unknown_assurance) diagnostic="minimum assurance must be process_recorded" ;;
    duplicate_roles) diagnostic="roles are missing/duplicate" ;;
    unmapped_role) diagnostic="roles do not map to verifier-owned semantic outputs" ;;
    empty_inputs) diagnostic="input_patterns are missing" ;;
    invalid_root) diagnostic="evidence_root must be review-evidence/phase-06" ;;
    unknown_host_claim) diagnostic="strict host claims are incomplete" ;;
    missing_binding) diagnostic="must declare exactly one semantic binding" ;;
    invalid_binding_field) diagnostic="has invalid task_id_field" ;;
  esac
  grep -F "$diagnostic" "$TMP_ROOT/$mutation.out" >/dev/null \
    || fail "contract lint rejected $mutation without its exact diagnostic"
done

echo "PASS: review-evidence contract lint rejects assurance, claim, role, input, root, and binding defects"
