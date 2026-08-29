#!/usr/bin/env bash
# Verify scholar-auto-research can execute its helper boundary from an isolated
# copy with an empty HOME and no parent plugin tree.
set -euo pipefail

SKILL_DIR="${SCHOLAR_AUTO_RESEARCH_TEST_SKILL_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/scholar-auto-research-self-contained.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

ISOLATED="$TMP_ROOT/standalone/scholar-auto-research"
EMPTY_HOME="$TMP_ROOT/home"
PROJ="$TMP_ROOT/project with spaces"
mkdir -p "$ISOLATED" "$EMPTY_HOME" "$PROJ"
ISOLATED="$(cd "$ISOLATED" && pwd -P)"
cp -R "$SKILL_DIR/." "$ISOLATED/"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

required=(
  scripts/runtime-preflight.py
  scripts/detect-host-agent.sh
  scripts/setup-project-claudemd.sh
  scripts/templates/claudemd-auto-rules.md
  scripts/auto-research-state.sh
  scripts/auto-research-verify.sh
  scripts/review_evidence.py
  scripts/setup-codex-hooks.sh
  scripts/safety_inventory.py
  scripts/gates/codex-pretooluse-hook.sh
  scripts/gates/pretooluse-data-guard.sh
  scripts/gates/safety-scan.sh
  scripts/gates/safety-scan-presidio.py
  scripts/gates/dua-fingerprints.json
  scripts/gates/sidecar-schema.sh
  scripts/gates/emit-trace.sh
  scripts/gates/render-trace.sh
  scripts/gates/trace-coverage-check.sh
  scripts/gates/ingest-agent-trace.sh
  scripts/gates/refresh-run-html.sh
  scripts/gates/build-run-model.py
  scripts/gates/render-run-html.py
  scripts/gates/surface-lease.sh
  scripts/gates/seam-summary-check.sh
  scripts/gates/independent-check-requests.sh
  references/process-logger.md
  references/agent-trace-contract.md
  references/review-evidence-contract.md
  references/phase-contract.json
  references/contract-migrations.json
  references/runtime-dependencies.json
)
for rel in "${required[@]}"; do
  [ -f "$ISOLATED/$rel" ] || fail "missing vendored runtime dependency: $rel"
done

# Existing bundled gates must also resolve their references from the isolated
# skill rather than reconstructing the parent plugin layout.
WEIGHT_PROJ="$TMP_ROOT/weighted-project"
mkdir -p "$WEIGHT_PROJ/data" "$WEIGHT_PROJ/design" "$WEIGHT_PROJ/analysis/scripts"
printf '{"dataset_id":"gss","files":[]}\n' > "$WEIGHT_PROJ/data/data-status.json"
printf '{"measurement_strategy":{"weights_policy":"apply_published_weights"}}\n' \
  > "$WEIGHT_PROJ/design/design-blueprint.json"
printf 'fit <- survey::svydesign(ids=~1, weights=~wt, data=d)\n' \
  > "$WEIGHT_PROJ/analysis/scripts/weighted.R"
HOME="$EMPTY_HOME" env -u SCHOLAR_SKILL_DIR \
  bash "$ISOLATED/scripts/gates/survey-weights-check.sh" "$WEIGHT_PROJ" \
  >"$TMP_ROOT/weights.out"
grep -F 'STATUS=GREEN' "$TMP_ROOT/weights.out" >/dev/null \
  || fail "survey-weights gate did not resolve its vendored registry"

# Runtime instructions and state code must not bootstrap or walk into the
# parent plugin. Documentation may name upstream source files, so target only
# executable command patterns that would be followed at runtime.
if grep -nE 'scholar-skill-bootstrap|\$\{SCHOLAR_SKILL_DIR:-\.\}/scripts/(gates|phases)' "$ISOLATED/SKILL.md"; then
  fail "SKILL.md still contains parent-plugin runtime commands"
fi
if grep -nE 'SCRIPT_DIR/\.\./\.\./\.\./\.\.|SCHOLAR_SKILL_DIR.*refresh-run-html' "$ISOLATED/scripts/auto-research-state.sh"; then
  fail "state runtime still reaches outside the isolated skill"
fi
if grep -n 'AUTO_RESEARCH_ALLOW_ROOT_GATE_FALLBACK' "$ISOLATED/scripts/auto-research-verify.sh"; then
  fail "verifier still exposes a parent gate fallback"
fi
if grep -nE 'Google Drive|scholar-marketplace/plugins/scholar-skill/(skills|\.claude)' \
    "$ISOLATED/scripts/templates/claudemd-auto-rules.md"; then
  fail "generated memory still pins a user-specific parent plugin path"
fi
if grep -nF '$HOME/Google Drive' "$ISOLATED/scripts/gates/verify-citation-local-library.sh"; then
  fail "citation provider discovery still executes a Google Drive lookup"
fi
if grep -nE 'SCHOLAR_SKILL_DIR|scholar-skill-bootstrap|_shared/agent-trace-contract|render-trace-html|render-session-transcript|render-run-html\.sh' \
    "$ISOLATED/references/process-logger.md" "$ISOLATED/references/agent-trace-contract.md"; then
  fail "local protocol references still require non-vendored runtime files"
fi
if grep -nF '_AR_SKILL=".claude/skills/scholar-auto-research"' "$ISOLATED/SKILL.md"; then
  fail "SKILL.md still assumes the caller's cwd contains the loaded skill"
fi
if grep -nE '`bash scripts/|`bash \.claude/skills/' "$ISOLATED/scripts/templates/claudemd-auto-rules.md"; then
  fail "generated memory still contains a cwd-relative executable instruction"
fi

# The local installer must write a hook pointing back into this isolated copy.
HOME="$EMPTY_HOME" env -u SCHOLAR_SKILL_DIR \
  bash "$ISOLATED/scripts/setup-codex-hooks.sh" "$PROJ" >/dev/null
CONFIG="$PROJ/.codex/config.toml"
[ -s "$CONFIG" ] || fail "local Codex hook installer did not create config"
grep -F "$ISOLATED/scripts/gates/codex-pretooluse-hook.sh" "$CONFIG" >/dev/null \
  || fail "Codex hook does not point into isolated skill"

# The installer is the runtime preflight for the mandatory safety closure. It
# must name each missing dependency and refuse to install a partial hook.
mkdir -p "$TMP_ROOT/broken-project"
for rel in \
  scripts/runtime-preflight.py \
  scripts/detect-host-agent.sh \
  scripts/setup-project-claudemd.sh \
  scripts/templates/claudemd-auto-rules.md \
  scripts/auto-research-state.sh \
  scripts/auto-research-verify.sh \
  scripts/review_evidence.py \
  scripts/safety_inventory.py \
  scripts/gates/codex-pretooluse-hook.sh \
  scripts/gates/pretooluse-data-guard.sh \
  scripts/gates/safety-scan.sh \
  scripts/gates/safety-scan-presidio.py \
  scripts/gates/dua-fingerprints.json \
  scripts/gates/sidecar-schema.sh \
  scripts/gates/emit-trace.sh \
  scripts/gates/render-trace.sh \
  scripts/gates/trace-coverage-check.sh \
  scripts/gates/ingest-agent-trace.sh \
  references/phase-contract.json \
  references/contract-migrations.json \
  references/review-evidence-contract.md \
  references/process-logger.md \
  references/agent-trace-contract.md; do
  BROKEN="$TMP_ROOT/broken-$(basename "$rel")"
  cp -R "$ISOLATED/." "$BROKEN/"
  rm "$BROKEN/$rel"
  set +e
  HOME="$EMPTY_HOME" bash "$BROKEN/scripts/setup-codex-hooks.sh" "$TMP_ROOT/broken-project" \
    >"$TMP_ROOT/broken.out" 2>"$TMP_ROOT/broken.err"
  BROKEN_RC=$?
  set -e
  [ "$BROKEN_RC" -eq 1 ] \
    || fail "hook installer accepted missing closure member: $rel (rc=$BROKEN_RC)"
  grep -F "required runtime dependency missing/unreadable: $rel" "$TMP_ROOT/broken.err" >/dev/null \
    || fail "hook installer did not name missing closure member: $rel"
done

# A manifest from an incompatible runtime contract must be rejected before a
# hook is installed.
BROKEN_VERSION="$TMP_ROOT/broken-manifest-version"
cp -R "$ISOLATED/." "$BROKEN_VERSION/"
python3 - "$BROKEN_VERSION/references/runtime-dependencies.json" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p, encoding="utf-8"))
d["schema_version"] = "scholar-auto-research-runtime/v999"
with open(p, "w", encoding="utf-8") as f:
    json.dump(d, f)
PY
set +e
HOME="$EMPTY_HOME" bash "$BROKEN_VERSION/scripts/setup-codex-hooks.sh" "$TMP_ROOT/broken-project" \
  >"$TMP_ROOT/version.out" 2>"$TMP_ROOT/version.err"
VERSION_RC=$?
set -e
[ "$VERSION_RC" -eq 1 ] || fail "hook installer accepted a runtime manifest version mismatch"
grep -F 'runtime dependency manifest schema mismatch' "$TMP_ROOT/version.err" >/dev/null \
  || fail "manifest version mismatch did not produce the named failure"

BROKEN_LIST="$TMP_ROOT/broken-manifest-list"
cp -R "$ISOLATED/." "$BROKEN_LIST/"
python3 - "$BROKEN_LIST/references/runtime-dependencies.json" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p, encoding="utf-8"))
d["required_packaged_files"].append("scripts/gates/not-shipped-required-helper.sh")
with open(p, "w", encoding="utf-8") as f:
    json.dump(d, f)
PY
set +e
HOME="$EMPTY_HOME" bash "$BROKEN_LIST/scripts/setup-codex-hooks.sh" "$TMP_ROOT/broken-project" \
  >"$TMP_ROOT/list.out" 2>"$TMP_ROOT/list.err"
LIST_RC=$?
set -e
[ "$LIST_RC" -eq 1 ] || fail "hook installer ignored a required manifest entry"
grep -F 'required runtime dependency missing/unreadable: scripts/gates/not-shipped-required-helper.sh' \
  "$TMP_ROOT/list.err" >/dev/null || fail "manifest/list drift did not name the missing entry"

# Generated project memory must bind commands to the absolute loaded-skill
# directory, not assume the project cwd contains a .claude/skills copy.
HOME="$EMPTY_HOME" SCHOLAR_HOST_AGENT_OVERRIDE=codex \
  bash "$ISOLATED/scripts/setup-project-claudemd.sh" "$PROJ" >/dev/null
grep -F "$ISOLATED/scripts/setup-project-claudemd.sh" "$PROJ/AGENTS.md" >/dev/null \
  || fail "generated project memory did not bind the isolated skill path"
grep -F "bash \"$ISOLATED/scripts/auto-research-verify.sh\" 0" "$PROJ/AGENTS.md" >/dev/null \
  || fail "generated project memory left Phase 0 verification cwd-relative"
if grep -nE '`bash scripts/|`bash \.claude/skills/|`scripts/[^`]+\.sh`|`auto-research-verify\.sh' "$PROJ/AGENTS.md"; then
  fail "rendered project memory contains a cwd-relative executable instruction"
fi

# Restricted-dataset fingerprinting is mandatory: deleting its registry must
# be a named RED, never a clean regex-only GREEN.
BROKEN_DUA="$TMP_ROOT/broken-dua-scan"
cp -R "$ISOLATED/." "$BROKEN_DUA/"
rm "$BROKEN_DUA/scripts/gates/dua-fingerprints.json"
printf 'SEQN,RIDAGEYR\n1,40\n' > "$TMP_ROOT/nhanes-like.csv"
set +e
bash "$BROKEN_DUA/scripts/gates/safety-scan.sh" "$TMP_ROOT/nhanes-like.csv" \
  >"$TMP_ROOT/dua.out" 2>"$TMP_ROOT/dua.err"
DUA_RC=$?
set -e
[ "$DUA_RC" -eq 1 ] || fail "safety scanner accepted a missing DUA registry (rc=$DUA_RC)"
grep -F 'required DUA fingerprint registry missing/unreadable' "$TMP_ROOT/dua.out" >/dev/null \
  || fail "missing DUA registry did not produce the named RED"
EMPTY_DUA="$TMP_ROOT/empty-dua-scan"
cp -R "$ISOLATED/." "$EMPTY_DUA/"
printf '{"datasets":[]}\n' > "$EMPTY_DUA/scripts/gates/dua-fingerprints.json"
set +e
bash "$EMPTY_DUA/scripts/gates/safety-scan.sh" "$TMP_ROOT/nhanes-like.csv" \
  >"$TMP_ROOT/empty-dua.out" 2>"$TMP_ROOT/empty-dua.err"
EMPTY_DUA_RC=$?
set -e
[ "$EMPTY_DUA_RC" -eq 1 ] || fail "safety scanner accepted an empty DUA registry"
grep -F 'required DUA fingerprint registry is malformed or empty' "$TMP_ROOT/empty-dua.out" >/dev/null \
  || fail "empty DUA registry did not produce the named RED"

# A LOCAL_MODE data read must be denied by the fully vendored hook chain.
mkdir -p "$PROJ/.claude" "$PROJ/data/raw"
DATA_FILE="$PROJ/data/raw/respondents.csv"
printf 'id,value\n1,restricted\n' > "$DATA_FILE"
python3 - "$PROJ/.claude/safety-status.json" "$DATA_FILE" <<'PY'
import json, sys
with open(sys.argv[1], "w", encoding="utf-8") as out:
    json.dump({sys.argv[2]: "LOCAL_MODE"}, out)
PY
set +e
printf '{"tool_name":"Read","tool_input":{"file_path":"%s"},"cwd":"%s"}\n' "$DATA_FILE" "$PROJ" \
  | HOME="$EMPTY_HOME" env -u SCHOLAR_SKILL_DIR bash "$ISOLATED/scripts/gates/codex-pretooluse-hook.sh" \
      >"$TMP_ROOT/hook.out" 2>"$TMP_ROOT/hook.err"
HOOK_RC=$?
set -e
[ "$HOOK_RC" -eq 2 ] || fail "vendored Codex hook failed to deny LOCAL_MODE read (rc=$HOOK_RC)"
grep -E 'deny|block' "$TMP_ROOT/hook.out" >/dev/null \
  || fail "vendored Codex hook emitted no deny decision"

# Process logging must work without the parent bootstrap or root gate tree.
TRACE_ROOT="$TMP_ROOT/trace-output"
HOME="$EMPTY_HOME" env -u SCHOLAR_SKILL_DIR bash "$ISOLATED/scripts/gates/emit-trace.sh" \
  --skill scholar-auto-research --step isolated-runtime \
  --reasoning 'exercise local trace writer' --action 'emit one record' \
  --observation 'isolated trace created' --status ok --output-root "$TRACE_ROOT" >/dev/null
TRACE="$TRACE_ROOT/logs/trace-scholar-auto-research-$(date +%Y-%m-%d).ndjson"
HOME="$EMPTY_HOME" env -u SCHOLAR_SKILL_DIR bash "$ISOLATED/scripts/gates/render-trace.sh" "$TRACE" >/dev/null
HOME="$EMPTY_HOME" env -u SCHOLAR_SKILL_DIR bash "$ISOLATED/scripts/gates/trace-coverage-check.sh" \
  "$TRACE_ROOT" --skill scholar-auto-research >"$TMP_ROOT/coverage.out"
grep -F 'STATUS=GREEN' "$TMP_ROOT/coverage.out" >/dev/null \
  || fail "isolated trace coverage did not turn GREEN"

# Agent sidecars are part of the trace protocol, not inventory-only files.
SIDECAR="$TMP_ROOT/agent.trace.ndjson"
printf '%s\n' '{"step":"isolated-agent","reasoning":"exercise local ingester","action":"fold sidecar","observation":"one record","status":"ok"}' > "$SIDECAR"
HOME="$EMPTY_HOME" env -u SCHOLAR_SKILL_DIR bash "$ISOLATED/scripts/gates/ingest-agent-trace.sh" \
  --sidecar "$SIDECAR" --skill scholar-auto-research --agent reviewer \
  --agentId isolated-1 --output-root "$TRACE_ROOT" >"$TMP_ROOT/ingest.out"
grep -F 'INGESTED=1' "$TMP_ROOT/ingest.out" >/dev/null \
  || fail "isolated agent trace ingester did not fold one record"

# Core state and optional run-view refresh must also remain inside the copy.
STATE_PROJ="$TMP_ROOT/state-project"
HOME="$EMPTY_HOME" env -u SCHOLAR_SKILL_DIR \
  bash "$ISOLATED/scripts/auto-research-state.sh" init "$STATE_PROJ" >/dev/null
HOME="$EMPTY_HOME" env -u SCHOLAR_SKILL_DIR \
  bash "$ISOLATED/scripts/auto-research-state.sh" set-mode "$STATE_PROJ" autonomous fixture >/dev/null
HOME="$EMPTY_HOME" env -u SCHOLAR_SKILL_DIR SCHOLAR_RUN_HTML_AUTO=1 \
  bash "$ISOLATED/scripts/auto-research-state.sh" next "$STATE_PROJ" >"$TMP_ROOT/next.out"
grep -F 'NEXT_PHASE=0' "$TMP_ROOT/next.out" >/dev/null \
  || fail "isolated state machine did not return Phase 0"
[ -s "$STATE_PROJ/logs/run-html/index.html" ] \
  || fail "vendored run-view refresh did not produce isolated HTML"
python3 - "$STATE_PROJ/logs/run-model.json" <<'PY' || fail "isolated run model is materially degraded"
import json, sys
m = json.load(open(sys.argv[1], encoding="utf-8"))
coverage = m.get("coverage") or {}
assert coverage.get("has_backbone") is True
assert coverage.get("n_declared_phases") == 21
assert sum(int(p.get("n_gates_declared") or 0) for p in m.get("phases") or []) >= 21
assert not any("gate roster not found" in str(x) for x in coverage.get("degraded_reasons") or [])
PY

# Run-view rendering is optional. Removing it must preserve the state result
# while producing a visible advisory rather than disappearing into `|| true`.
NO_VIEW="$TMP_ROOT/no-view"
cp -R "$ISOLATED/." "$NO_VIEW/"
rm "$NO_VIEW/scripts/gates/refresh-run-html.sh"
NO_VIEW_PROJ="$TMP_ROOT/no-view-project"
HOME="$EMPTY_HOME" bash "$NO_VIEW/scripts/auto-research-state.sh" init "$NO_VIEW_PROJ" >/dev/null
HOME="$EMPTY_HOME" bash "$NO_VIEW/scripts/auto-research-state.sh" \
  set-mode "$NO_VIEW_PROJ" autonomous fixture >/dev/null
HOME="$EMPTY_HOME" SCHOLAR_RUN_HTML_AUTO=1 \
  bash "$NO_VIEW/scripts/auto-research-state.sh" next "$NO_VIEW_PROJ" \
  >"$TMP_ROOT/no-view.out" 2>"$TMP_ROOT/no-view.err"
grep -F 'NEXT_PHASE=0' "$TMP_ROOT/no-view.out" >/dev/null \
  || fail "missing optional run view changed the state-machine result"
grep -F 'ADVISORY: optional run-view refresh unavailable' "$TMP_ROOT/no-view.err" >/dev/null \
  || fail "missing optional run view was silently suppressed"

NO_BUILDER="$TMP_ROOT/no-builder"
cp -R "$ISOLATED/." "$NO_BUILDER/"
rm "$NO_BUILDER/scripts/gates/build-run-model.py"
NO_BUILDER_PROJ="$TMP_ROOT/no-builder-project"
HOME="$EMPTY_HOME" bash "$NO_BUILDER/scripts/auto-research-state.sh" init "$NO_BUILDER_PROJ" >/dev/null
HOME="$EMPTY_HOME" bash "$NO_BUILDER/scripts/auto-research-state.sh" \
  set-mode "$NO_BUILDER_PROJ" autonomous fixture >/dev/null
HOME="$EMPTY_HOME" SCHOLAR_RUN_HTML_AUTO=1 \
  bash "$NO_BUILDER/scripts/auto-research-state.sh" next "$NO_BUILDER_PROJ" \
  >"$TMP_ROOT/no-builder.out" 2>"$TMP_ROOT/no-builder.err"
grep -F 'NEXT_PHASE=0' "$TMP_ROOT/no-builder.out" >/dev/null \
  || fail "missing optional run-view companion changed the state result"
grep -F 'ADVISORY: optional run-view:' "$TMP_ROOT/no-builder.err" >/dev/null \
  || fail "missing optional run-view companion was silently suppressed"

# The portable review path must run with no repository parent and a PATH made
# only from commands declared by the copied skill's runtime manifest.
CONTROLLED_BIN="$TMP_ROOT/declared-bin"
mkdir -p "$CONTROLLED_BIN"
while IFS= read -r runtime_command; do
  runtime_source="$(command -v "$runtime_command" || true)"
  [ -n "$runtime_source" ] || fail "declared runtime command is unavailable: $runtime_command"
  ln -s "$runtime_source" "$CONTROLLED_BIN/$runtime_command"
done < <(python3 - "$ISOLATED/references/runtime-dependencies.json" <<'PY'
import json, sys
for item in json.load(open(sys.argv[1], encoding="utf-8"))["required_commands"]:
    print(item)
PY
)

PATH="$CONTROLLED_BIN" HOME="$EMPTY_HOME" \
  python3 "$ISOLATED/scripts/runtime-preflight.py" --skill-dir "$ISOLATED" \
  >"$TMP_ROOT/preflight.out"
grep -F 'RUNTIME_PREFLIGHT=PASS' "$TMP_ROOT/preflight.out" >/dev/null \
  || fail "host-neutral runtime preflight did not pass in the declared PATH"

NO_JQ_BIN="$TMP_ROOT/declared-bin-no-jq"
mkdir -p "$NO_JQ_BIN"
for runtime_path in "$CONTROLLED_BIN"/*; do
  [ "$(basename "$runtime_path")" = "jq" ] || ln -s "$(readlink "$runtime_path")" "$NO_JQ_BIN/$(basename "$runtime_path")"
done
set +e
PATH="$NO_JQ_BIN" HOME="$EMPTY_HOME" \
  "$CONTROLLED_BIN/python3" "$ISOLATED/scripts/runtime-preflight.py" --skill-dir "$ISOLATED" \
  >"$TMP_ROOT/preflight-missing.out" 2>"$TMP_ROOT/preflight-missing.err"
PREFLIGHT_MISSING_RC=$?
set -e
[ "$PREFLIGHT_MISSING_RC" -eq 1 ] || fail "runtime preflight accepted a missing declared command"
grep -F 'required runtime command unavailable: jq' "$TMP_ROOT/preflight-missing.err" >/dev/null \
  || fail "runtime preflight did not name the missing declared command"

REVIEW_PROJ="$TMP_ROOT/portable-review-project"
cp -pR "$ISOLATED/tests/fixtures/phase5-seed" "$REVIEW_PROJ"
PATH="$CONTROLLED_BIN" HOME="$EMPTY_HOME" SCHOLAR_RUN_HTML_AUTO=0 \
  bash "$ISOLATED/scripts/auto-research-state.sh" init "$REVIEW_PROJ" >/dev/null
PATH="$CONTROLLED_BIN" HOME="$EMPTY_HOME" SCHOLAR_RUN_HTML_AUTO=0 \
  bash "$ISOLATED/scripts/auto-research-state.sh" set-mode "$REVIEW_PROJ" autonomous isolated >/dev/null
PATH="$CONTROLLED_BIN" HOME="$EMPTY_HOME" python3 - "$REVIEW_PROJ" "$ISOLATED/references/phase-contract.json" <<'PY'
import hashlib, json, pathlib, sys
project = pathlib.Path(sys.argv[1])
contract = pathlib.Path(sys.argv[2])
path = project / ".auto-research/state.json"
state = json.loads(path.read_text())
state["contract_sha256"] = hashlib.sha256(contract.read_bytes()).hexdigest()
state["phases_completed"] = [str(i) for i in range(6)]
state["phase_records"] = {
    str(i): {"phase_id": str(i), "phase_name": "isolated prerequisite", "artifacts": [], "dependencies": []}
    for i in range(6)
}
state["stale_phases"] = []
path.write_text(json.dumps(state, indent=2, sort_keys=True) + "\n")
PY

PATH="$CONTROLLED_BIN" HOME="$EMPTY_HOME" SCHOLAR_RUN_HTML_AUTO=0 \
  bash "$ISOLATED/scripts/auto-research-state.sh" review-begin \
    "$REVIEW_PROJ" 6 initial_panel generic-isolated-host >"$TMP_ROOT/review-begin.out"
REVIEW_SESSION_ID="$(sed -n 's/^REVIEW_SESSION_ID=//p' "$TMP_ROOT/review-begin.out")"
[ -n "$REVIEW_SESSION_ID" ] || fail "isolated review-begin returned no session ID"

PATH="$CONTROLLED_BIN" HOME="$EMPTY_HOME" SCHOLAR_RUN_HTML_AUTO=0 \
  python3 - "$REVIEW_PROJ" "$REVIEW_SESSION_ID" "$ISOLATED/scripts/auto-research-state.sh" <<'PY'
import json, os, pathlib, shutil, subprocess, sys, time
project = pathlib.Path(sys.argv[1])
session_id = sys.argv[2]
state_tool = sys.argv[3]
session = json.loads((project / "review-evidence/phase-06" / session_id / "session.json").read_text())
by_role = {}
for index, reservation in enumerate(session["reservations"], 1):
    role = reservation["role"]
    report = project / reservation["report_path"]
    trace = project / reservation["trace_path"]
    report.parent.mkdir(parents=True, exist_ok=True)
    trace.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(project / "review/agents" / f"{role}.md", report)
    trace.write_text(json.dumps({
        "step": f"isolated-{role}",
        "reasoning": "review the reserved role over the registered inputs",
        "action": "persist the generic-host review and RAO sidecar",
        "observation": f"isolated role {index} completed",
        "status": "ok",
    }) + "\n")
    subprocess.run([
        "bash", state_tool, "review-complete", str(project), "6", session_id, role,
        "--driver-status", "succeeded",
        "--host-task-unavailable", "generic host exposes no stable task identity",
        "--model-unavailable", "generic host exposes no model identity",
    ], check=True, stdout=subprocess.DEVNULL)
    by_role[role] = reservation

summary_path = project / "review/pre-execution-review.json"
summary = json.loads(summary_path.read_text())
for reviewer in summary["reviewers"]:
    reservation = by_role[reviewer["role"]]
    reviewer["report_path"] = reservation["report_path"]
    reviewer["task_invocation_id"] = reservation["dispatch_id"]
summary["review_evidence"] = {
    "profile": "normal",
    "attempt_epoch": 0,
    "rounds": {
        "initial_panel": {"session_id": session_id, "achieved_assurance": "process_recorded"},
        "fix_rereview": {"status": "not_applicable"},
    },
}
summary_path.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")
stamp = time.time()
os.utime(summary_path, (stamp, stamp))
os.utime(project / "review/pre-execution-fix-log.json", (stamp + 1, stamp + 1))
os.utime(project / "review/pre-execution-rereview.json", (stamp + 2, stamp + 2))
PY

PATH="$CONTROLLED_BIN" python3 - "$REVIEW_PROJ" "$REVIEW_SESSION_ID" >"$TMP_ROOT/review-launches.tsv" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1]) / "review-evidence/phase-06" / sys.argv[2] / "session.json"
for reservation in json.loads(p.read_text())["reservations"]:
    print("\t".join((
        reservation["role"],
        reservation["dispatch_id"],
        str(pathlib.Path(sys.argv[1]) / reservation["trace_path"]),
    )))
PY
while IFS=$'\t' read -r REVIEW_ROLE REVIEW_DISPATCH_ID REVIEW_TRACE; do
  PATH="$CONTROLLED_BIN" HOME="$EMPTY_HOME" \
    bash "$ISOLATED/scripts/gates/ingest-agent-trace.sh" \
      --sidecar "$REVIEW_TRACE" --skill scholar-auto-research --agent "$REVIEW_ROLE" \
      --agentId "$REVIEW_DISPATCH_ID" --phase 6 --proj "$REVIEW_PROJ" \
      --output-root "$REVIEW_PROJ" >"$TMP_ROOT/review-ingest.out"
  grep -F 'AGENTID_BOUND=yes' "$TMP_ROOT/review-ingest.out" >/dev/null \
    || fail "isolated trace ingest did not bind registered dispatch $REVIEW_DISPATCH_ID"
done < "$TMP_ROOT/review-launches.tsv"

PATH="$CONTROLLED_BIN" HOME="$EMPTY_HOME" SCHOLAR_RUN_HTML_AUTO=0 \
  bash "$ISOLATED/scripts/auto-research-verify.sh" 6 "$REVIEW_PROJ" \
  >"$TMP_ROOT/review-verify.out" \
  || fail "isolated process-recorded Phase 6 verification failed"
PATH="$CONTROLLED_BIN" HOME="$EMPTY_HOME" SCHOLAR_RUN_HTML_AUTO=0 \
  bash "$ISOLATED/scripts/auto-research-state.sh" complete "$REVIEW_PROJ" 6 \
  >"$TMP_ROOT/review-complete.out" \
  || fail "isolated process-recorded Phase 6 state completion failed"
grep -F 'COMPLETED_PHASE=6' "$TMP_ROOT/review-complete.out" >/dev/null \
  || fail "isolated state completion did not publish Phase 6"

echo "self-contained runtime smoke: PASS"
