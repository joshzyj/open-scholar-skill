#!/usr/bin/env bash
# test-run-external-gate.sh — F4/F6 regression (audit 2026-07-07).
#
# Exercises the REAL run_external_gate (+ _gate_timeout_s + NETWORK_GATES),
# extracted verbatim from auto-research-verify.sh via AST, against scratch
# gates covering every synthesized/emitted branch. Before F4 the function
# returned `status or "YELLOW"`, so a crashed gate (nonzero exit, no STATUS
# line) became a non-fatal YELLOW that the RED-only panels dropped — a silent
# pass. These assertions lock the fix: deterministic crash/timeout -> RED;
# NETWORK_GATES crash/timeout -> YELLOW; STATUS=GREEN contradicted by nonzero
# exit -> RED; emitted GREEN/RED/INERT respected.
set -u
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VERIFIER="$SKILL_DIR/scripts/auto-research-verify.sh"
python3 - "$VERIFIER" <<'PY'
import ast, os, subprocess, sys, tempfile, shutil
from pathlib import Path

verifier = Path(sys.argv[1])
src = verifier.read_text()
m = "<<'PY'\n"
s = src.index(m) + len(m)
e = src.index("\nPY\n", s)
pysrc = src[s:e]
tree = ast.parse(pysrc)
wanted = {"NETWORK_GATES", "_gate_timeout_s", "run_external_gate"}
seg = {}
for n in tree.body:
    nm = None
    if isinstance(n, ast.FunctionDef):
        nm = n.name
    elif isinstance(n, ast.Assign):
        for t in n.targets:
            if isinstance(t, ast.Name) and t.id in wanted:
                nm = t.id
    if nm in wanted:
        seg[nm] = ast.get_source_segment(pysrc, n)
assert wanted <= set(seg), f"cannot extract {wanted - set(seg)} from verifier"

tmp = Path(tempfile.mkdtemp())
gdir = tmp / "gates"; gdir.mkdir()
proj = tmp / "proj"; proj.mkdir()


def mk(name, body):
    p = gdir / name
    p.write_text("#!/usr/bin/env bash\n" + body + "\n")
    p.chmod(0o755)


mk("broken.sh", "exit 3")
mk("greenx1.sh", "echo STATUS=GREEN\nexit 1")
mk("green.sh", "echo STATUS=GREEN")
mk("red.sh", "echo STATUS=RED\nexit 1")
mk("inert.sh", "echo STATUS=INERT\nexit 3")
mk("verify-citation-metadata.sh", "exit 3")
mk("slow.sh", "sleep 5")
mk("verify-citation-local-library.sh", "sleep 5")

GATE_DIR = gdir.resolve()  # noqa: N806
phase_id = "18"            # noqa: N816
ns = {"os": os, "subprocess": subprocess, "GATE_DIR": GATE_DIR,
      "phase_id": phase_id, "Path": Path}
for k in ("NETWORK_GATES", "_gate_timeout_s", "run_external_gate"):
    exec(seg[k], ns)  # noqa: S102 — verbatim verifier source
rex = ns["run_external_gate"]

fails = []


def chk(desc, gate, want_status, want_reason_sub, extra=()):
    st, rs, _ = rex(gate, proj, desc, extra)
    ok = st == want_status and (want_reason_sub in (rs or ""))
    print(("  OK  " if ok else "  XX  ") + f"{desc}: got ({st}, {rs})")
    if not ok:
        fails.append(desc)


chk("crash no-STATUS -> RED", "broken.sh", "RED", "gate_crash:exit3")
chk("STATUS=GREEN + exit1 -> RED", "greenx1.sh", "RED", "status_green_but_exit1")
chk("emitted GREEN -> GREEN", "green.sh", "GREEN", "")
chk("emitted RED -> RED", "red.sh", "RED", "")
chk("emitted INERT respected", "inert.sh", "INERT", "")
chk("missing gate -> RED", "missing.sh", "RED", "missing_external_gate")
chk("network crash -> YELLOW", "verify-citation-metadata.sh", "YELLOW", "gate_unavailable:exit3")
os.environ["AUTO_RESEARCH_GATE_TIMEOUT_S"] = "1"
os.environ["AUTO_RESEARCH_NETWORK_GATE_TIMEOUT_S"] = "1"
chk("deterministic timeout -> RED", "slow.sh", "RED", "gate_crash:timeout_1s")
chk("network timeout -> YELLOW", "verify-citation-local-library.sh", "YELLOW", "gate_unavailable:timeout_1s")

shutil.rmtree(tmp, ignore_errors=True)
print(f"Results: {9 - len(fails)} passed, {len(fails)} failed")
sys.exit(1 if fails else 0)
PY
