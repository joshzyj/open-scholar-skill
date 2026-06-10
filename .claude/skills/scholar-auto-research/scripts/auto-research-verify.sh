#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "usage: auto-research-verify.sh <phase_id> <project_dir>" >&2
  exit 2
fi

PHASE="$1"
PROJ="$2"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTRACT="$(cd "$SCRIPT_DIR/.." && pwd)/references/phase-contract.json"

verify_prereq() {
  local prereq_phase="$1"
  local output=""
  local rc=0
  set +e
  output="$(bash "$SCRIPT_DIR/auto-research-verify.sh" "$prereq_phase" "$PROJ" 2>&1)"
  rc=$?
  set -e
  if [ "$rc" -ne 0 ]; then
    echo "FAIL: Phase ${PHASE} prerequisite Phase ${prereq_phase} failed" >&2
    if [ -n "$output" ]; then
      echo "$output" >&2
    else
      echo "FAIL: prerequisite verifier exited with status ${rc} but produced no output" >&2
    fi
    exit "$rc"
  fi
}

if [ "$PHASE" = "11" ]; then
  verify_prereq 10
fi
if [ "$PHASE" = "12" ]; then
  verify_prereq 11
fi
if [ "$PHASE" = "13" ]; then
  verify_prereq 12
fi
if [ "$PHASE" = "14" ]; then
  verify_prereq 13
fi
if [ "$PHASE" = "15" ]; then
  verify_prereq 14
fi
if [ "$PHASE" = "16" ]; then
  verify_prereq 15
fi
if [ "$PHASE" = "17" ]; then
  verify_prereq 16
fi
if [ "$PHASE" = "18" ]; then
  verify_prereq 17
fi
if [ "$PHASE" = "19" ]; then
  verify_prereq 18
fi
if [ "$PHASE" = "20" ]; then
  verify_prereq 19
fi

python3 - "$CONTRACT" "$PHASE" "$PROJ" "$SCRIPT_DIR" <<'PY'
import glob
import hashlib
import json
import math
import os
import re
import shlex
import subprocess
import sys
import csv
import zipfile
from pathlib import Path

contract_path = Path(sys.argv[1])
phase_id = sys.argv[2]
proj = Path(sys.argv[3])
# auto-research is self-contained: verifier gates are vendored under this
# skill's scripts/gates/. Missing bundled gates are hard failures. A repo-level
# fallback can be enabled only for legacy debugging with
# AUTO_RESEARCH_ALLOW_ROOT_GATE_FALLBACK=1.
SCRIPT_DIR = Path(sys.argv[4]) if len(sys.argv) > 4 else Path(__file__).resolve().parent

def _resolve_gate_dir(start):
    candidates = [
        start / "gates",
        start.resolve() / "gates",
    ]
    if os.environ.get("AUTO_RESEARCH_ALLOW_ROOT_GATE_FALLBACK") == "1":
        candidates.extend([
            start / ".." / ".." / ".." / "scripts" / "gates",
            start / ".." / ".." / ".." / ".." / "scripts" / "gates",
            start.resolve() / ".." / ".." / ".." / "scripts" / "gates",
            start.resolve() / ".." / ".." / ".." / ".." / "scripts" / "gates",
        ])
    for cand in candidates:
        if cand.exists():
            return cand.resolve()
    return None

GATE_DIR = _resolve_gate_dir(SCRIPT_DIR)

JOURNAL_PROFILE_TEMPLATE_PATH = (SCRIPT_DIR / ".." / "references" / "journal-profile-resolution-templates.json").resolve()
_JOURNAL_PROFILE_TEMPLATE_CACHE = None



def run_external_gate(gate_name, project, label):
    """Run a bundled scripts/gates/<name>.sh helper.

    External manuscript gates are required once listed by the verifier. A
    missing gate must fail loudly; otherwise packaging mistakes silently weaken
    Phase 13/18/20 quality checks.
    """
    if GATE_DIR is None:
        return ("RED", "missing_gate_directory", "expected scholar-auto-research/scripts/gates")
    gate_path = GATE_DIR / gate_name
    if not gate_path.exists():
        return ("RED", f"missing_external_gate:{gate_name}", str(gate_path))
    if not os.access(gate_path, os.X_OK):
        return ("RED", f"external_gate_not_executable:{gate_name}", str(gate_path))
    try:
        env = dict(os.environ)
        env["AUTO_RESEARCH_VERIFY_PHASE"] = str(phase_id)
        result = subprocess.run(
            ["bash", str(gate_path), str(project)],
            capture_output=True, text=True, timeout=120, env=env,
        )
    except Exception as exc:
        return ("YELLOW", f"gate_invocation_error:{exc}", "")
    text = (result.stdout or "") + "\n" + (result.stderr or "")
    status = ""
    reason = ""
    detail = ""
    for line in (result.stdout or "").splitlines():
        if line.startswith("STATUS="):
            status = line.split("=", 1)[1].strip()
        elif line.startswith("REASON="):
            reason = line.split("=", 1)[1].strip()
        elif line.startswith("DETAIL:"):
            detail = line.split(":", 1)[1].strip()
    return (status or "YELLOW", reason, detail)

contract = json.loads(contract_path.read_text())
phase = next((p for p in contract["phases"] if str(p["id"]) == phase_id), None)
if phase is None:
    print(f"FAIL: unknown phase {phase_id}")
    sys.exit(2)
if not proj.exists():
    print(f"FAIL: project directory does not exist: {proj}")
    sys.exit(1)

def sha256(path):
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()

def canonical_sha256_without_field(obj, field):
    clone = dict(obj)
    clone.pop(field, None)
    payload = json.dumps(clone, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()

def read_csv_dicts(path):
    with path.open(newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))

def word_count(text):
    return len(re.findall(r"\b[\w'-]+\b", text))

def prose_only_text(text):
    visible = strip_comments(text)
    visible = re.sub(r"(?is)<table\b.*?</table>", " ", visible)
    visible = re.sub(r"!\[[^\]]*\]\([^)]+\)", " ", visible)
    visible = re.sub(r"\[[^\]]+\]\([^)]+\)", " ", visible)
    kept = []
    in_fenced = False
    for line in visible.splitlines():
        stripped = line.strip()
        if stripped.startswith("```"):
            in_fenced = not in_fenced
            continue
        if in_fenced:
            continue
        if not stripped:
            kept.append("")
            continue
        if stripped.startswith("|"):
            continue
        if re.match(r"^\|?(?:\s*:?-{3,}:?\s*\|)+\s*$", stripped):
            continue
        if re.match(r"^(?:#{1,6}\s+)?(?:\*\*)?(?:Table|Figure)\s+\d+[.:]", stripped, flags=re.IGNORECASE):
            continue
        if re.match(r"^Notes?:", stripped, flags=re.IGNORECASE):
            continue
        if re.match(r"^<!--\s*(?:DISPLAY|LOCKED|CLAIM)_", stripped, flags=re.IGNORECASE):
            continue
        kept.append(line)
    return "\n".join(kept)

def prose_word_count(text):
    return word_count(prose_only_text(text))

def command_invokes_pandoc(command):
    try:
        tokens = shlex.split(command)
    except ValueError:
        tokens = command.split()
    return any(Path(token).name == "pandoc" for token in tokens)

def markdown_sections(text):
    sections = {}
    current = None
    buffer = []
    for line in text.splitlines():
        match = re.match(r"^##\s+(.+?)\s*$", line)
        if match:
            if current is not None:
                sections[current] = "\n".join(buffer)
            current = re.sub(r"[^a-z0-9]+", " ", match.group(1).lower()).strip()
            buffer = []
        elif current is not None:
            buffer.append(line)
    if current is not None:
        sections[current] = "\n".join(buffer)
    return sections

def strip_comments(text):
    return re.sub(r"<!--.*?-->", " ", text, flags=re.DOTALL)

def claim_strength_rank(value):
    text = str(value or "").strip().lower()
    if not text:
        return None
    if "causal" in text and "noncausal" not in text and "non-causal" not in text:
        return 3
    if "associat" in text:
        return 2
    if "descript" in text:
        return 1
    if "explor" in text:
        return 0
    return None

def method_orientation_components(value):
    text = str(value or "").strip().lower()
    if not text:
        return set()
    components = set()
    quantitative_keywords = (
        "quantitative", "observational", "survey", "panel", "regression",
        "demograph", "experimental", "experiment", "causal", "quasi-causal",
        "quasi causal", "event study", "fixed effects", "did",
    )
    computational_keywords = (
        "computational", "text-as-data", "text as data", "machine learning",
        "ml ", " ml", "network", "nlp", "agent-based", "agent based",
        "geospatial", "computer vision", "llm", "sequence", "audio",
    )
    qualitative_keywords = (
        "qualitative", "interview", "ethnograph", "focus group", "grounded theory",
        "thematic", "content analysis", "fieldwork", "participant observation",
        "oral history", "case study", "discourse",
    )
    linguistic_keywords = (
        "linguistic", "sociolingu", "phonetic", "phonology", "variationist",
        "varbrul", "rbrul", "conversation analysis", "discourse analysis",
        "language contact", "acoustic",
    )
    if "mixed-method" in text or "mixed method" in text or "mixedmethods" in text:
        components.add("mixed_methods")
    if any(keyword in text for keyword in quantitative_keywords):
        components.add("quantitative")
    if any(keyword in text for keyword in computational_keywords):
        components.add("computational")
    if any(keyword in text for keyword in qualitative_keywords):
        components.add("qualitative")
    if any(keyword in text for keyword in linguistic_keywords):
        components.add("linguistic")
    return components

def normalized_method_family(value):
    components = method_orientation_components(value)
    non_mixed = components - {"mixed_methods"}
    if not components:
        return None
    if "mixed_methods" in components or len(non_mixed) > 1:
        return "mixed_methods"
    if "computational" in non_mixed:
        return "computational"
    if "qualitative" in non_mixed:
        return "qualitative"
    if "linguistic" in non_mixed:
        return "linguistic"
    if "quantitative" in non_mixed:
        return "quantitative"
    return None

def expected_skill_for_method_family(family):
    return {
        "quantitative": "scholar-analyze",
        "computational": "scholar-compute",
        "qualitative": "scholar-qual",
        "linguistic": "scholar-ling",
    }.get(family)

def allowed_skills_for_method_orientation(value):
    components = method_orientation_components(value)
    allowed = set()
    if "quantitative" in components:
        allowed.add("scholar-analyze")
    if "computational" in components:
        allowed.add("scholar-compute")
    if "qualitative" in components:
        allowed.add("scholar-qual")
    if "linguistic" in components:
        allowed.add("scholar-ling")
    return allowed

def validate_method_specialist_routing(routing, method_orientation, context):
    issues = []
    family = normalized_method_family(method_orientation)
    components = method_orientation_components(method_orientation)
    if family is None:
        return None, None, components, [f"{context}: method_orientation is not specific enough to route"]
    if not isinstance(routing, dict):
        return family, None, components, [f"{context}: method_specialist_routing must be an object"]
    routed_orientation = str(routing.get("method_orientation", "")).strip()
    routed_family = normalized_method_family(routed_orientation)
    if routed_family is None:
        issues.append(f"{context}: method_specialist_routing.method_orientation is not parseable")
    elif routed_family != family:
        issues.append(f"{context}: method_specialist_routing.method_orientation does not match Phase 1 method family")
    primary = str(routing.get("primary_execution_skill", "")).strip()
    premortem = str(routing.get("premortem_skill", "")).strip()
    supporting = routing.get("supporting_skills")
    if word_count(str(routing.get("rationale", ""))) < 8:
        issues.append(f"{context}: method_specialist_routing.rationale is too thin")
    if not isinstance(supporting, list):
        issues.append(f"{context}: method_specialist_routing.supporting_skills must be a list")
        supporting = []
    allowed = allowed_skills_for_method_orientation(method_orientation)
    if family == "mixed_methods":
        if primary not in allowed:
            issues.append(f"{context}: primary_execution_skill must be one of {sorted(allowed)} for mixed-methods")
        if premortem != primary:
            issues.append(f"{context}: premortem_skill must match primary_execution_skill for mixed-methods")
        support_set = {str(item).strip() for item in supporting if str(item).strip()}
        if not support_set:
            issues.append(f"{context}: mixed-methods routing requires non-empty supporting_skills")
        missing = sorted((allowed - {primary}) - support_set)
        if missing:
            issues.append(f"{context}: supporting_skills missing {missing}")
        extra = sorted(support_set - allowed)
        if extra:
            issues.append(f"{context}: supporting_skills include invalid entries {extra}")
        return family, primary, components, issues
    expected = expected_skill_for_method_family(family)
    if primary != expected:
        issues.append(f"{context}: primary_execution_skill must be {expected} for {family}")
    if premortem != expected:
        issues.append(f"{context}: premortem_skill must be {expected} for {family}")
    return family, expected, components, issues

def validate_engine_provenance(engine, context):
    issues = []
    placeholder_values = {"", "tbd", "todo", "unknown", "n/a", "na", "placeholder"}
    if not isinstance(engine, dict):
        return [f"{context}: engine object missing"]
    task_id = str(engine.get("task_invocation_id", "")).strip()
    if task_id.lower() in placeholder_values:
        issues.append(f"{context}: task_invocation_id missing")
    invoked_at = str(engine.get("invoked_at_utc", "")).strip()
    if not re.match(r"^\d{4}-\d{2}-\d{2}T", invoked_at):
        issues.append(f"{context}: invoked_at_utc must be ISO-like UTC timestamp")
    for field in ("input_artifacts", "output_artifacts"):
        value = engine.get(field)
        if not isinstance(value, list) or not value:
            issues.append(f"{context}: {field} must be a non-empty list")
            continue
        for idx, item in enumerate(value):
            rel = str(item).strip()
            if not rel or Path(rel).is_absolute():
                issues.append(f"{context}: {field}[{idx}] must be a non-empty relative path")
    return issues

def section_mentions_artifact(section_text, artifact_path):
    artifact_path = str(artifact_path).strip()
    if not artifact_path:
        return False
    basename = Path(artifact_path).name
    return artifact_path in section_text or basename in section_text

def content_keywords(text):
    stop = {
        "the", "and", "for", "with", "from", "that", "this", "into", "than", "then",
        "have", "has", "had", "were", "was", "are", "is", "be", "been", "being",
        "under", "over", "after", "before", "while", "where", "when", "their", "there",
        "which", "what", "about", "through", "because", "would", "could", "should",
        "does", "did", "done", "them", "they", "those", "these", "only", "more",
        "less", "very", "must", "will", "also", "just", "into", "onto", "across",
        "paper", "study", "result", "results", "finding", "findings", "manuscript",
    }
    tokens = re.findall(r"\b[a-z][a-z0-9_-]{2,}\b", str(text).lower())
    return [token for token in tokens if token not in stop]

def keyword_overlap_count(seed_text, target_text):
    seed = set(content_keywords(seed_text))
    target = set(content_keywords(target_text))
    return len(seed & target)

def display_window(text, anchor, span=4000):
    start = text.find(anchor)
    if start < 0:
        return ""
    return text[start:start + span]

def parse_search_log_rows(path):
    rows = []
    try:
        lines = path.read_text(errors="ignore").splitlines()
    except Exception:
        return rows
    for line in lines:
        stripped = line.strip()
        if not stripped.startswith("|"):
            continue
        parts = [part.strip() for part in stripped.strip("|").split("|")]
        if len(parts) < 6:
            continue
        if parts[0] in {"#", "---"} or parts[0].lower() == "source":
            continue
        rows.append(parts)
    return rows

def normalize_search_source(value):
    text = str(value).strip().lower()
    if text in {"reflib", "zotero", "mendeley", "bibtex", "endnote xml", "endnote"}:
        return "reflib"
    if text in {"websearch", "crossref", "annrev", "annual reviews", "annualreviews", "web"}:
        return "web"
    if text in {"knowledge-graph", "knowledge graph", "kg"}:
        return "kg"
    return text

def has_markdown_or_html_table(text):
    visible = strip_comments(text)
    if re.search(r"(?is)<table\b.*?</table>", visible):
        return True
    return bool(
        re.search(
            r"(?m)^\|.+\|\s*$\n^\|(?:\s*:?-{3,}:?\s*\|)+\s*$",
            visible,
        )
    )

def raw_html_table_hits(text):
    visible = strip_comments(text)
    hits = []
    for match in re.finditer(r"(?is)<table\b[\s\S]{0,200000}?</table>", visible):
        excerpt = re.sub(r"\s+", " ", match.group(0)).strip()
        hits.append(excerpt[:240])
    return hits

def editable_text_policy_forbids_raw_html_tables(display_architecture):
    if not isinstance(display_architecture, dict):
        return False
    mode = str(display_architecture.get("table_rendering_mode", "")).strip().lower()
    editable_flag = display_architecture.get("editable_text_tables")
    return editable_flag is True or mode.startswith("editable_text")

def has_visible_figure_block(text):
    visible = strip_comments(text)
    if re.search(r"!\[[^\]]*\]\([^)]+\)", visible):
        return True
    has_caption = bool(re.search(r"(?im)^\*\*Figure\s+\d+[.:]", visible) or re.search(r"(?im)^Figure\s+\d+[.:]", visible))
    has_link = bool(re.search(r"\[[^\]]+\]\([^)]+\)", visible))
    return has_caption and has_link

def prose_paragraphs(text, min_words=40):
    visible = strip_comments(text)
    paragraphs = []
    for block in re.split(r"\n\s*\n", visible):
        chunk = block.strip()
        if not chunk:
            continue
        if has_markdown_or_html_table(chunk):
            continue
        if re.search(r"(?m)^\|", chunk):
            continue
        if re.search(r"(?m)^!\[[^\]]*\]\([^)]+\)\s*$", chunk):
            continue
        if re.search(r"(?im)^\*\*Figure\s+\d+[.:]\*\*\s*$", chunk) or re.search(r"(?im)^Figure\s+\d+[.:]\s*$", chunk):
            continue
        if word_count(chunk) >= min_words:
            paragraphs.append(chunk)
    return paragraphs

def section_citekeys(text):
    return set(re.findall(r"@([A-Za-z0-9_:\-]+)", text))

def validate_numeric_reporting_policy(policy, context):
    issues = []
    if not isinstance(policy, dict):
        return [f"{context}: numeric_reporting_policy must be an object"]
    policy_source = str(policy.get("policy_source", "")).strip()
    if not policy_source:
        issues.append(f"{context}: policy_source missing")
    try:
        inferential_digits = int(policy.get("inferential_digits", -1))
        descriptive_digits = int(policy.get("descriptive_digits", -1))
    except Exception:
        inferential_digits = descriptive_digits = -1
        issues.append(f"{context}: inferential_digits and descriptive_digits must be integers")
    if inferential_digits < 2 or inferential_digits > 4:
        issues.append(f"{context}: inferential_digits must be between 2 and 4")
    if descriptive_digits < 1 or descriptive_digits > 3:
        issues.append(f"{context}: descriptive_digits must be between 1 and 3")
    if not str(policy.get("p_value_rule", "")).strip():
        issues.append(f"{context}: p_value_rule missing")
    if not isinstance(policy.get("allow_scientific_notation"), bool):
        issues.append(f"{context}: allow_scientific_notation must be boolean")
    return issues

def visible_markdown_text(text):
    visible = strip_comments(text)
    visible = re.sub(r"!\[[^\]]*\]\([^)]+\)", " ", visible)
    visible = re.sub(r"\[[^\]]+\]\([^)]+\)", " ", visible)
    return visible

def strip_yaml_frontmatter_preserve_lines(text):
    lines = str(text or "").splitlines()
    if not lines or lines[0].strip() != "---":
        return str(text or "")
    for idx in range(1, len(lines)):
        if lines[idx].strip() in {"---", "..."}:
            return "\n" * (idx + 1) + "\n".join(lines[idx + 1:])
    return str(text or "")

def keyword_placement_issues(text):
    visible = strip_yaml_frontmatter_preserve_lines(strip_comments(text))
    lines = visible.splitlines()
    title_line = None
    abstract_line = None
    introduction_line = None
    keyword_lines = []
    for line_no, line in enumerate(lines, start=1):
        stripped = line.strip()
        if not stripped:
            continue
        if title_line is None and (stripped.startswith("# ") or re.match(r"(?i)^title\s*:", stripped)):
            title_line = line_no
        if abstract_line is None and re.match(r"(?i)^#{1,6}\s+abstract\s*$", stripped):
            abstract_line = line_no
        if introduction_line is None and re.match(r"(?i)^#{1,6}\s+introduction\s*$", stripped):
            introduction_line = line_no
        if re.match(r"(?i)^(?:\*\*)?\s*keywords?\s*(?:\*\*)?\s*[:：]", stripped):
            keyword_lines.append(line_no)
    issues = []
    if title_line is None:
        issues.append("missing manuscript title before Abstract")
    if abstract_line is None:
        issues.append("missing Abstract heading")
        return issues
    if title_line is not None and title_line > abstract_line:
        issues.append(f"title line {title_line} appears after Abstract line {abstract_line}")
    if introduction_line is None:
        issues.append("missing Introduction heading")
    if not keyword_lines:
        issues.append("missing visible Keywords line")
        return issues
    if len(keyword_lines) > 1:
        issues.append(f"multiple visible Keywords lines: {keyword_lines}")
    for keyword_line in keyword_lines:
        if keyword_line < abstract_line:
            issues.append(f"Keywords line {keyword_line} appears before Abstract line {abstract_line}; expected Title -> Abstract -> Keywords -> Introduction")
        if introduction_line is not None and keyword_line > introduction_line:
            issues.append(f"Keywords line {keyword_line} appears after Introduction line {introduction_line}; expected keywords before Introduction")
    first_keyword = keyword_lines[0]
    if first_keyword > abstract_line:
        abstract_body_lines = [
            line.strip()
            for line in lines[abstract_line:first_keyword - 1]
            if line.strip() and not re.match(r"(?i)^(?:\*\*)?\s*keywords?\s*(?:\*\*)?\s*[:：]", line.strip())
        ]
        if not abstract_body_lines:
            issues.append("Keywords line must follow the abstract text, not just the Abstract heading")
        if any(line.startswith("#") for line in abstract_body_lines):
            issues.append("Keywords line is not inside the Abstract section")
    return issues

def displayed_hypotheses_allowed(*objects):
    for obj in objects:
        if not isinstance(obj, dict):
            continue
        candidates = [obj]
        for key in (
            "hypothesis_display_policy",
            "journal_profile_resolution",
            "journal_spec",
            "journal_structure",
            "display_architecture",
        ):
            value = obj.get(key)
            if isinstance(value, dict):
                candidates.append(value)
        for candidate in candidates:
            if candidate.get("allow_displayed_hypotheses") is True:
                return True
            if candidate.get("displayed_hypotheses_allowed") is True:
                return True
            policy = candidate.get("hypothesis_display_policy")
            if isinstance(policy, dict) and policy.get("allow_displayed_hypotheses") is True:
                return True
            presentation = norm_text(candidate.get("hypothesis_presentation", ""))
            if presentation in {"displayed allowed", "displayed hypotheses allowed", "standalone hypotheses allowed"}:
                return True
            placement = norm_text(candidate.get("hypothesis_placement", ""))
            if placement in {"blended", "theory", "theory section", "standalone", "displayed", "hypotheses section"}:
                return True
            sections = candidate.get("sections")
            if isinstance(sections, dict):
                for section in sections.values():
                    if not isinstance(section, dict):
                        continue
                    label = norm_text(section.get("label", ""))
                    moves = " ".join(str(item) for item in section.get("structural_moves", []) if item)
                    if "hypothes" in label or re.search(r"\bderive each h[_ ]?id\b|\bhypotheses?_all\b", moves, re.IGNORECASE):
                        return True
            section_order = candidate.get("section_order")
            if isinstance(section_order, list) and any("hypoth" in norm_text(item) for item in section_order):
                return True
    return False

def hypothesis_display_hits(text):
    visible = visible_markdown_text(text)
    hits = []
    heading_pat = re.compile(r"^\s*#{1,6}\s+(?:[0-9.]+\s+)?(?:formal\s+)?hypoth(?:esis|eses)\s*$", re.IGNORECASE)
    list_pat = re.compile(
        r"^\s*(?:[-*+]|\d+[.)]|[A-Za-z][.)])\s+"
        r"(?:\*\*)?\s*(?:H\d+[A-Za-z]?|Hypothesis\s+\d+[A-Za-z]?|Hypothesis)"
        r"(?:\*\*)?\s*(?:[:.)\-]|\b)",
        re.IGNORECASE,
    )
    standalone_pat = re.compile(
        r"^\s*(?:\*\*)?\s*(?:H\d+[A-Za-z]?|Hypothesis\s+\d+[A-Za-z]?)"
        r"(?:\*\*)?\s*[:.)\-]\s+\S",
        re.IGNORECASE,
    )
    for line_no, line in enumerate(visible.splitlines(), start=1):
        stripped = line.strip()
        if not stripped or "[ALLOW-DISPLAYED-HYPOTHESIS:" in stripped:
            continue
        if stripped.startswith("|"):
            continue
        if heading_pat.search(line):
            hits.append(f"standalone hypothesis heading line {line_no}: {stripped[:160]}")
            continue
        if list_pat.search(line):
            hits.append(f"hypothesis bullet/list line {line_no}: {stripped[:160]}")
            continue
        if standalone_pat.search(line) and word_count(stripped) < 90:
            hits.append(f"standalone hypothesis line {line_no}: {stripped[:160]}")
    return hits

def bare_hypothesis_display_hits(text):
    visible = visible_markdown_text(text)
    lines = visible.splitlines()
    hits = []
    theory_signal = re.compile(
        r"\b(theor|mechanism|perspective|because|therefore|thus|prior|literature|argu|expect|predict|suggest|scope|condition)\b",
        re.IGNORECASE,
    )
    hyp_line = re.compile(
        r"^\s*(?:[-*+]\s+)?(?:\*\*)?\s*(?:H\d+[A-Za-z]?|Hypothesis\s+\d+[A-Za-z]?)(?:\*\*)?\s*[:.)\-]\s+\S",
        re.IGNORECASE,
    )
    hyp_heading = re.compile(r"^\s*#{1,6}\s+(?:[0-9.]+\s+)?(?:formal\s+)?hypoth(?:esis|eses)\s*$", re.IGNORECASE)
    for idx, line in enumerate(lines):
        stripped = line.strip()
        if not stripped or stripped.startswith("|"):
            continue
        if not (hyp_line.search(stripped) or hyp_heading.search(stripped)):
            continue
        prior = "\n".join(lines[max(0, idx - 14):idx])
        if word_count(prior) < 35 or not theory_signal.search(prior):
            hits.append(f"displayed hypothesis lacks nearby theoretical motivation line {idx + 1}: {stripped[:160]}")
    return hits

def norm_text(value):
    return re.sub(r"[^a-z0-9]+", " ", str(value).lower()).strip()

def looks_machine_like_label(value):
    text = str(value or "").strip()
    lower = text.lower()
    if not text:
        return False
    if "_" in text or "/" in text:
        return True
    if re.search(r"[a-z][A-Z]", text):
        return True
    if re.fullmatch(r"[A-Za-z]{1,3}\d{1,4}", text):
        return True
    if re.match(r"^(?:q|item|var|v|x|y)\d", lower):
        return True
    if re.search(r"(?:_var|_code|_id|_num|_cat|_flag|_ind|_item|_score)\b", lower):
        return True
    if lower in {"x", "y"}:
        return True
    return False

def contains_literal_token(text, token):
    token = str(token or "").strip()
    if not token:
        return False
    return bool(re.search(rf"(?<![A-Za-z0-9]){re.escape(token)}(?![A-Za-z0-9])", str(text)))

def find_scientific_notation_tokens(text):
    visible = visible_markdown_text(text)
    return sorted(set(
        match.group(0)
        for match in re.finditer(r"(?<![\w/])[-+]?(?:\d+(?:\.\d+)?|\.\d+)[eE][+-]?\d+(?![\w/])", visible)
    ))

def find_overprecise_decimal_tokens(text, max_decimals):
    visible = visible_markdown_text(text)
    tokens = []
    for match in re.finditer(r"(?<![\w/])[-+]?\d+\.(\d+)(?![\w/])", visible):
        token = match.group(0)
        decimals = len(match.group(1))
        if decimals > max_decimals:
            tokens.append((token, decimals))
    seen = set()
    unique = []
    for token, decimals in tokens:
        if token in seen:
            continue
        seen.add(token)
        unique.append((token, decimals))
    return unique

def has_results_callout(section_text, display_label):
    label = str(display_label or "").strip().lower()
    if not label:
        return False
    visible = visible_markdown_text(section_text)
    for sentence in re.split(r"(?<=[.!?])\s+", visible):
        lowered = sentence.lower()
        if label in lowered and re.search(
            r"\b(show(?:s|n)?|present(?:s|ed)?|report(?:s|ed)?|plot(?:s|ted)?|display(?:s|ed)?|illustrat(?:e|es|ed)|document(?:s|ed)?|summari(?:ze|zes|zed)|describ(?:e|es|ed))\b",
            lowered,
        ):
            return True
    return False

def has_raw_citekeys(text):
    visible = strip_comments(text)
    return bool(re.search(r"\[@[^\]]+\]|\b@[A-Za-z0-9_:\-]+\b", visible))

def references_looks_like_key_dump(text):
    visible = strip_comments(text).strip()
    lower = visible.lower()
    if not visible:
        return True
    if "cited bibliography keys:" in lower or "bibliography keys:" in lower:
        return True
    keyish = re.findall(r"\b[a-z][a-z0-9_:-]*\d{4}[a-z0-9_:-]*\b", lower)
    if ";" in visible and len(keyish) >= 5:
        return True
    if not re.search(r"\b(19|20)\d{2}\b", visible):
        return True
    return False

def count_visible_figure_blocks(text):
    visible = strip_comments(text)
    image_blocks = len(re.findall(r"!\[[^\]]*\]\([^)]+\)", visible))
    caption_link_blocks = _count_figure_caption_link_blocks(visible)
    return max(image_blocks, caption_link_blocks)


def _count_figure_caption_link_blocks(text):
    """Line-based O(N) scan for **Figure N.** caption-followed-by-link blocks.

    Replaces a catastrophically-backtracking (?ims) regex. For each line
    starting with `**Figure N.` or `Figure N.` / `Figure N:`, look at up
    to 4 subsequent non-blank lines (skipping blanks within the budget)
    for a markdown link `[text](url)`. Each Figure label that has a link
    in its same line or 4-non-blank-line window counts as one block.

    Blank lines skip (not terminate) within the 4-line budget; this also
    corrects an under-counting bug where a blank line between caption and
    image link caused the original (?im) form to return zero matches.

    Patch P6.1, verified by review-code-correctness agent against fixtures
    A-F + 100KB pathological input (runtime 0.43ms vs original hang >2min).
    """
    lines = text.split("\n")
    label_re = re.compile(r"^(?:\*\*)?Figure\s+\d+[.:]", re.IGNORECASE)
    link_re = re.compile(r"\[[^\]]+\]\([^)]+\)")
    n = len(lines)
    count = 0
    for i, line in enumerate(lines):
        if not label_re.match(line):
            continue
        if link_re.search(line):
            count += 1
            continue
        non_blank_seen = 0
        j = i + 1
        while j < n and non_blank_seen < 4:
            if not lines[j].strip():
                j += 1
                continue
            if link_re.search(lines[j]):
                count += 1
                break
            non_blank_seen += 1
            j += 1
    return count

def count_visible_table_blocks(text):
    visible = strip_comments(text)
    markdown_tables = len(
        re.findall(
            r"(?m)^\|.+\|\s*$\n^\|(?:\s*:?-{3,}:?\s*\|)+\s*$",
            visible,
        )
    )
    html_tables = len(re.findall(r"(?is)<table\b[\s\S]{0,200000}?</table>", visible))
    labeled_tables = len(re.findall(r"(?im)^(?:\*\*)?Table\s+\d+[.:]", visible))
    return max(markdown_tables, html_tables, labeled_tables)

def visible_heading_sequence(text):
    headings = []
    for line in text.splitlines():
        match = re.match(r"^##\s+(.+?)\s*$", line)
        if match:
            headings.append(norm_text(match.group(1)))
    return headings

def sequence_contains_in_order(sequence, expected):
    if not expected:
        return True
    idx = 0
    for item in sequence:
        if item == expected[idx]:
            idx += 1
            if idx == len(expected):
                return True
    return False

def count_label_positions(text, label):
    visible = strip_comments(text)
    return [match.start() for match in re.finditer(rf"(?im)^(?:\*\*)?{re.escape(label)}\s+\d+[.:]", visible)]

def json_blob(*values):
    parts = []
    for value in values:
        if value is None:
            continue
        if isinstance(value, (dict, list)):
            try:
                parts.append(json.dumps(value, sort_keys=True, ensure_ascii=False))
            except Exception:
                parts.append(str(value))
        else:
            parts.append(str(value))
    return "\n".join(parts).lower()

def structured_secondary_data_indicated(*values):
    text = json_blob(*values)
    return bool(re.search(
        r"\b(survey|sampling|sample weight|weight(?:ed|ing)?|cluster(?:ed|ing)?|strat(?:a|ified)|"
        r"multistage|panel|longitudinal|wave|psu|primary sampling|complex sample|"
        r"administrative|register data|claims data|census|person file|household file)\b",
        text,
    ))

def complex_outcome_family_indicated(var_rows=None, model_specs=None, measurement_text=""):
    outcome_bits = []
    if isinstance(var_rows, list):
        for row in var_rows:
            if not isinstance(row, dict):
                continue
            role = str(row.get("role", "")).lower()
            if any(token in role for token in ("y", "outcome", "dependent")):
                outcome_bits.append(" ".join(str(row.get(field, "")) for field in row))
    if isinstance(model_specs, dict):
        for model in model_specs.get("models", []) or []:
            if isinstance(model, dict):
                outcome_bits.append(str(model.get("outcome", "")))
                outcome_bits.append(str(model.get("outcome_family", "")))
                outcome_bits.append(str(model.get("estimator", "")))
    outcome_bits.append(str(measurement_text))
    text = " ".join(outcome_bits).lower()
    return bool(re.search(
        r"\b(hour|hours|minute|minutes|duration|time use|time-use|bounded|skew|zero[- ]inflated|"
        r"count|counts|rate|proportion|fraction|binary|ordinal|top[- ]code|ceiling|floor)\b",
        text,
    ))

def truthy_review_field(obj, *names):
    if not isinstance(obj, dict):
        return False
    for name in names:
        value = obj.get(name)
        if value is True:
            return True
        if isinstance(value, str) and value.strip().lower() in {"true", "yes", "reviewed", "pass", "not_applicable", "not-applicable"}:
            return True
    return False

def reader_workflow_jargon_hits(text):
    visible = visible_markdown_text(text)
    patterns = {
        "result lock language": r"\b(?:active\s+)?results?\s+lock(?:ed|s)?\b|\b(?:locked|lock)\s+(?:estimate|estimates|model|models|result|results|headline|claim|claims|table|figure|artifact|artifacts)\b|\blocked[- ]output\b",
        "registry language": r"\bresults?\s+registr(?:y|ies)\b|\b(?:registry|registered)\s+(?:coefficient|coefficients|estimate|estimates|row|rows|table|tables|model|models|specification|specifications)\b|\b(?:coefficient|estimate|model|specification)\s+registr(?:y|ies)\b|\bregistered\s+before\s+execution\b",
        "manifest language": r"\bmanifest\b|\bSHA-?256\b|\bsource\s+hash(?:es)?\b",
        "phase language": r"\bphase[- ]?\d+\b|\bphase\s+\d+\b|\broute[- ]back\b",
        "pipeline language": r"\b(?:pipeline|workflow orchestration|workflow scaffold(?:ing)?|internal workflow|workflow language)\b",
        "verification mechanics": r"\b(?:verification|audit|trace|pipeline|workflow|locked|source)\s+artifact(?:s)?\b|\bverification\s+(?:table|report|workflow|gate|scan|artifact(?:s)?)\b|\bquality\s+gate\b|\bclaim[- ]source\s+map\b|\bclaim\s+map\b",
        "provenance mechanics": r"\bprovenance\s+(?:record|mechanic|metadata|artifact(?:s)?)\b|\baudit artifact\b|\btrace anchor\b",
        "process note language": r"\bfirst\s+draft\b|\bverified\s+chain\b|\blater\s+checking\b|\bsource\s+note\b|\bworking\s+(?:file|files|folder|folders)\b|\bexecution\s+report\b|\bpost[- ]execution\b|\bplanned\s+model\s+calls\b|\boutput\s+records\b|\breviewed\s+outputs\b|\blocked\s+discipline\b",
    }
    hits = []
    for label, pattern in patterns.items():
        for match in re.finditer(pattern, visible, flags=re.IGNORECASE):
            hits.append(f"{label}: {match.group(0)}")
    hits.extend(reader_internal_spec_index_hits(text))
    return hits

def disclosure_semantic_label(disclosure):
    text = str(disclosure or "").strip().lower()
    if "observational" in text or "causal" in text:
        return "claim-boundary"
    if "weight" in text or "hc1" in text or "unweighted" in text:
        return "weights-and-inference"
    if "complete-case" in text or "denominator" in text:
        return "complete-case-denominators"
    if "2016" in text or "2020" in text or "comparable-wave" in text or "harmonized" in text:
        return "harmonized-wave-scope"
    if "privacy" in text or "governance" in text or "public-file" in text or "public-use" in text:
        return "construct-availability"
    return re.sub(r"[^a-z0-9]+", "-", text).strip("-")[:80] or "disclosure"

def disclosure_semantically_covered(disclosure, lower_manuscript):
    item = str(disclosure or "").strip().lower()
    label = disclosure_semantic_label(item)
    if item and item in lower_manuscript:
        return True
    if label == "claim-boundary":
        return (
            "not a complete adjustment set for causal identification" in lower_manuscript
            or "cannot determine whether" in lower_manuscript
            or "primary models do not provide exogenous assignment" in lower_manuscript
            or "not used as a panel identification design" in lower_manuscript
        )
    if label == "weights-and-inference":
        return (
            "unweighted" in lower_manuscript
            and ("survey-weight" in lower_manuscript or "survey weight" in lower_manuscript or "weights" in lower_manuscript)
            and ("hc1" in lower_manuscript or "robust standard errors" in lower_manuscript)
        )
    if label == "complete-case-denominators":
        return (
            ("complete-case" in lower_manuscript or "complete cases" in lower_manuscript)
            and ("denominator" in lower_manuscript or "denominators" in lower_manuscript)
            and ("vary" in lower_manuscript or "differ" in lower_manuscript or "reports the denominator" in lower_manuscript)
        )
    if label == "harmonized-wave-scope":
        return (
            "2016" in lower_manuscript
            and "2018" in lower_manuscript
            and "2020" in lower_manuscript
            and "harmonized" in lower_manuscript
            and ("robustness check" in lower_manuscript or "comparable-wave" in lower_manuscript)
        )
    if label == "construct-availability":
        return (
            ("public-use files do not include every construct" in lower_manuscript)
            or ("privacy-governance constructs" in lower_manuscript and "excluded" in lower_manuscript)
            or ("platform governance" in lower_manuscript and "public-use files do not include" in lower_manuscript)
        )
    return bool(item and item in lower_manuscript)

def submission_machinery_prose_hits(text):
    visible = visible_markdown_text(text)
    hits = []
    for line_no, line in enumerate(visible.splitlines(), start=1):
        if "[ALLOW-PIPELINE-META:" in line:
            continue
        if re.search(r"\[VERIFIED-(?:WEB|LOCAL|TBV|EXTERNAL|MANUAL|CROSSREF|S2|OPENALEX)\b[^\]]*\]", line, flags=re.IGNORECASE):
            hits.append(f"verified citation marker line {line_no}: {line.strip()[:160]}")
        if re.search(
            r"^\s*#{1,6}\s+(?:[0-9.]+\s+)?(?:Robustness Ladder|Multiple[- ]Comparison Correction|Limitations Acknowledged at Estimation Time|BH Correction Summary|Hypothesis status update|Robustness battery|Iter \d+ spot-fixes|Fix-loop iter|Codex arms?|Pre-mortem memo|Resolution tracker)\s*$",
            line,
            flags=re.IGNORECASE,
        ):
            hits.append(f"pipeline-jargon heading line {line_no}: {line.strip()[:160]}")
        if re.search(
            r"\b(?:we carry (?:\d+|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve) (?:accepted )?limitations|(?:two|three|four|five|\d+) pre-registered (?:famil(?:y|ies)|groups?)|(?:\d+|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve) accepted limitations|pre-registered famil(?:y|ies))\b",
            line,
            flags=re.IGNORECASE,
        ):
            hits.append(f"pipeline-limitation enumeration line {line_no}: {line.strip()[:160]}")
    run = []
    bullet_pat = re.compile(r"^\s*[-*+]\s+\*\*(?:M\d+[A-Za-z]?|R\d+[A-Za-z]?|S\d+[A-Za-z]?)(?:[.)\s:-]|\b)", re.IGNORECASE)
    for line_no, line in enumerate(visible.splitlines(), start=1):
        if "[ALLOW-PIPELINE-META:" in line:
            if len(run) >= 3:
                hits.append("bulleted spec-ID list lines " + ",".join(str(n) for n, _ in run[:8]))
            run = []
            continue
        if bullet_pat.search(line):
            run.append((line_no, line.strip()))
            continue
        if len(run) >= 3:
            hits.append("bulleted spec-ID list lines " + ",".join(str(n) for n, _ in run[:8]))
        run = []
    if len(run) >= 3:
        hits.append("bulleted spec-ID list lines " + ",".join(str(n) for n, _ in run[:8]))
    return hits

def report_field(text, field):
    match = re.search(rf"(?im)^\s*{re.escape(field)}\s*:\s*(.+?)\s*$", text)
    return match.group(1).strip() if match else ""

def validate_semantic_body_prose_report(section, report_path, current_hash):
    issues = []
    if not isinstance(section, dict):
        return ["semantic_body_prose_read must be an object"]
    expected_rel = "submission/semantic-body-prose-read.md"
    if str(section.get("report_path", "")).strip() != expected_rel:
        issues.append("semantic_body_prose_read.report_path must be submission/semantic-body-prose-read.md")
    if str(section.get("reviewed_artifact", "")).strip() != "submission/manuscript-submission.md":
        issues.append("semantic_body_prose_read.reviewed_artifact must be submission/manuscript-submission.md")
    if str(section.get("manuscript_sha256", "")).strip() != current_hash:
        issues.append("semantic_body_prose_read.manuscript_sha256 must match current submission manuscript")
    if str(section.get("status", "")).strip() != "GREEN":
        issues.append("semantic_body_prose_read.status must be GREEN for Phase 20 PASS")
    for key in ("blocking_issue_count", "structural_pattern_count", "unresolved_suggestion_count"):
        try:
            value = int(section.get(key))
        except Exception:
            issues.append(f"semantic_body_prose_read.{key} must be numeric")
            continue
        if value != 0:
            issues.append(f"semantic_body_prose_read.{key} must be 0 for Phase 20 PASS")
    if not str(section.get("subagent_type", "")).strip():
        issues.append("semantic_body_prose_read.subagent_type must identify the semantic reader")
    if not report_path.exists():
        issues.append("semantic body-prose report file is missing")
        return issues
    report = report_path.read_text(errors="ignore")
    status = report_field(report, "STATUS")
    reviewed = report_field(report, "REVIEWED_ARTIFACT")
    report_hash = report_field(report, "MANUSCRIPT_SHA256")
    blocking = report_field(report, "BLOCKING_ISSUES")
    structural = report_field(report, "STRUCTURAL_PATTERN_COUNT")
    if status != "GREEN":
        issues.append("semantic body-prose report STATUS must be GREEN")
    if reviewed != "submission/manuscript-submission.md":
        issues.append("semantic body-prose report REVIEWED_ARTIFACT must be submission/manuscript-submission.md")
    if report_hash != current_hash:
        issues.append("semantic body-prose report MANUSCRIPT_SHA256 is stale")
    if blocking != "0":
        issues.append("semantic body-prose report BLOCKING_ISSUES must be 0")
    if structural != "0":
        issues.append("semantic body-prose report STRUCTURAL_PATTERN_COUNT must be 0")
    return issues

TABLE_ARTIFACT_ROLES = {
    "result_table",
    "model_output",
    "main_regression_table",
    "sensitivity_regression_table",
    "regression_table",
    "descriptive_table",
    "reader_facing_descriptive_table",
}

REGRESSION_TABLE_ROLES = {
    "main_regression_table",
    "sensitivity_regression_table",
    "regression_table",
}

REGRESSION_TABLE_DISPLAY_TYPES = {
    "regression_table_markdown",
    "regression_table_html",
    "regression_table_tex",
    "regression_table_docx",
}

DESCRIPTIVE_TABLE_REQUIREMENTS = {
    "table_1_mandatory",
    "table_1_required_for_quantitative",
}

def source_is_registry_like(path):
    name = Path(str(path or "")).name.lower()
    stem = name.rsplit(".", 1)[0]
    return bool(
        name == "results-registry.csv"
        or "results-registry" in stem
        or "result-registry" in stem
        or "model-ladder" in stem
        or "model_ladder" in stem
        or "focal-coef" in stem
        or "focal_coef" in stem
        or "focal-coefficient" in stem
        or "focal_coefficient" in stem
        or "registry-coef" in stem
        or "registry_coef" in stem
    )

def markdown_table_headers(text):
    lines = strip_comments(text).splitlines()
    headers = []
    for idx, line in enumerate(lines[:-1]):
        if not line.strip().startswith("|"):
            continue
        next_line = lines[idx + 1]
        if not re.match(r"^\|(?:\s*:?-{3,}:?\s*\|)+\s*$", next_line.strip()):
            continue
        parts = [norm_text(part) for part in line.strip().strip("|").split("|")]
        parts = [part for part in parts if part]
        if parts:
            headers.append(parts)
    return headers

def reader_internal_spec_index_hits(text):
    visible = visible_markdown_text(text)
    visible = re.sub(r"<[^>]+>", " ", visible)
    hits = []
    for match in re.finditer(r"\bS\d+[A-Za-z]?\b", visible):
        start = match.start()
        end = match.end()
        prefix = visible[max(0, start - 40):start]
        suffix = visible[end:end + 40]
        if re.search(r"\b(?:Table|Figure|Appendix|Supplementary)\s+$", prefix, flags=re.IGNORECASE):
            continue
        if re.match(r"^\s+(?:Appendix|Table|Figure)\b", suffix, flags=re.IGNORECASE):
            continue
        context = re.sub(r"\s+", " ", (prefix + match.group(0) + suffix).strip())
        hits.append(f"internal specification index: {context[:180]}")
    return hits

def registry_like_table_display_hits(text):
    visible = visible_markdown_text(text)
    hits = []
    title_patterns = [
        (r"(?im)^(?:\*\*)?Table\s+\d+[.:].*\b(?:model ladder|results? registry|registry coefficients?|focal coefficients?|verification table)\b", "table title"),
        (r"(?im)^#{1,6}\s+.*\b(?:model ladder|results? registry|registry coefficients?|focal coefficients?|verification table)\b", "heading"),
    ]
    for pattern, label in title_patterns:
        for match in re.finditer(pattern, visible):
            hits.append(f"{label}: {match.group(0).strip()[:160]}")
    registry_header_tokens = {
        "spec id",
        "model id",
        "hypothesis",
        "model role",
        "reader facing contrast",
        "output file",
        "locked path",
        "source path",
        "interpretation",
    }
    coefficient_extract_tokens = {"estimate", "std error", "p value", "n"}
    regression_shape_tokens = {"predictor", "covariate", "term", "variable"}
    # Focal-summary extract pattern:
    # row-per-statistic tables with first-column header "Statistic" or a focal-
    # coefficient label collapse all model evidence to one focal coefficient,
    # one SE, one p-value, and one N — disqualifies as a main regression table.
    focal_summary_tokens = {
        "statistic",
        "focal adjusted association",
        "focal coefficient",
        "headline estimate",
        "point estimate",
        "headline statistic",
    }
    for headers in markdown_table_headers(visible):
        header_set = set(headers)
        if "spec id" in header_set or "model id" in header_set or "output file" in header_set:
            hits.append(f"registry-like table headers: {', '.join(headers[:8])}")
            continue
        if len(header_set & registry_header_tokens) >= 3 and len(header_set & coefficient_extract_tokens) >= 2:
            hits.append(f"model-ladder table headers: {', '.join(headers[:8])}")
            continue
        if len(header_set & coefficient_extract_tokens) >= 3 and not (header_set & regression_shape_tokens):
            hits.append(f"focal-coefficient extract headers: {', '.join(headers[:8])}")
            continue
        if (header_set & focal_summary_tokens) and not (header_set & regression_shape_tokens) \
                and len(header_set & coefficient_extract_tokens) >= 1:
            hits.append(f"focal-summary extract headers: {', '.join(headers[:8])}")
    return hits

def displayed_registry_sources_from_coverage(coverage):
    hits = []
    if not isinstance(coverage, list):
        return hits
    for item in coverage:
        if not isinstance(item, dict):
            continue
        source_path = str(item.get("source_path", "")).strip()
        role = str(item.get("artifact_role", "")).strip()
        display_status = str(item.get("display_status", "")).strip()
        used = item.get("used_in_manuscript") is True
        if used and role == "results_registry":
            hits.append(f"{source_path}: results_registry marked reader-facing")
        if display_status and display_status != "journal_exempt" and source_is_registry_like(source_path):
            hits.append(f"{source_path}: registry-like source has display_status={display_status}")
    return hits

def has_canonical_regression_display(coverage):
    if not isinstance(coverage, list):
        return False
    for item in coverage:
        if not isinstance(item, dict):
            continue
        source_path = str(item.get("source_path", "")).strip()
        role = str(item.get("artifact_role", "")).strip()
        display_status = str(item.get("display_status", "")).strip()
        display_type = str(item.get("display_type", "")).strip().lower()
        if item.get("used_in_manuscript") is not True:
            continue
        if display_status == "journal_exempt":
            continue
        if source_is_registry_like(source_path):
            continue
        if role in REGRESSION_TABLE_ROLES or display_type in REGRESSION_TABLE_DISPLAY_TYPES or display_type.startswith("regression_table"):
            return True
    return False

def quantitative_empirical_regression_table_required(*values):
    text = json_blob(*values)
    if not structured_secondary_data_indicated(*values):
        return False
    return bool(re.search(
        r"\b(regression|regress|logit|logistic|probit|ols|glm|linear probability|"
        r"coefficient|estimate|estimator|model specification|fixed effects|random effects|"
        r"survey[- ]weighted|clustered standard|robust standard|marginal effect|hazard|cox)\b",
        text,
    ))

def concrete_review_locator_present(text):
    visible = strip_comments(text)
    return bool(re.search(
        r"(\b(?:p\.|page|line|lines)\s*\d+\b|:\d+\b|\bTable\s+\d+\b|\bFigure\s+\d+\b|"
        r"\bClaim\s+[A-Za-z0-9_.:-]+\b|claim_id|manuscript/manuscript-draft\.md|"
        r"citation/claim-source-map\.json|verify/manuscript-verification\.json)",
        visible,
        flags=re.IGNORECASE,
    ))

def adversarial_review_terms_present(text):
    visible = strip_comments(text).lower()
    return bool(re.search(
        r"\b(risk|weakness|limitation|concern|falsification|robustness|sensitivity|"
        r"rival|alternative explanation|desk[- ]reject|threat|missing|unsupported|overclaim)\b",
        visible,
    ))

def token_set_similarity(a, b):
    ta = set(content_keywords(a))
    tb = set(content_keywords(b))
    if not ta or not tb:
        return 0.0
    return len(ta & tb) / len(ta | tb)

def markdown_link_targets(text, image_only=False):
    pattern = r"!\[[^\]]*\]\(([^)]+)\)" if image_only else r"!?\[[^\]]*\]\(([^)]+)\)"
    return [match.group(1).strip() for match in re.finditer(pattern, strip_comments(text))]

def journal_profile_templates():
    global _JOURNAL_PROFILE_TEMPLATE_CACHE
    if _JOURNAL_PROFILE_TEMPLATE_CACHE is None:
        try:
            _JOURNAL_PROFILE_TEMPLATE_CACHE = json.loads(JOURNAL_PROFILE_TEMPLATE_PATH.read_text())
        except Exception as exc:
            raise SystemExit(f"journal profile template file is unreadable: {JOURNAL_PROFILE_TEMPLATE_PATH}: {exc}")
    return _JOURNAL_PROFILE_TEMPLATE_CACHE

def normalize_journal_name(value):
    text = norm_text(value)
    aliases = journal_profile_templates().get("aliases", {})
    return aliases.get(text, text)

def builtin_journal_profiles():
    profiles = journal_profile_templates().get("profiles", {})
    if not isinstance(profiles, dict) or not profiles:
        raise SystemExit(f"journal profile template file has no profiles: {JOURNAL_PROFILE_TEMPLATE_PATH}")
    return profiles

def expected_journal_profile(target_journal):
    journal = normalize_journal_name(target_journal)
    return builtin_journal_profiles().get(journal)

def validate_journal_structure(structure, target_journal, context, expected_profile=None):
    issues = []
    if not isinstance(structure, dict):
        return [f"{context}: journal_structure must be an object"]
    required = (
        "profile_source",
        "section_sequence",
        "results_before_methods",
        "theory_presentation",
        "methods_section_label",
        "discussion_conclusion_policy",
        "supplement_policy",
    )
    missing = [field for field in required if field not in structure]
    if missing:
        issues.append(f"{context}: missing fields {missing}")
        return issues
    if not str(structure.get("profile_source", "")).strip():
        issues.append(f"{context}: profile_source missing")
    section_sequence = structure.get("section_sequence")
    if not isinstance(section_sequence, list) or len(section_sequence) < 4:
        issues.append(f"{context}: section_sequence must be a list with at least 4 entries")
        section_sequence = []
    normalized_sequence = [norm_text(item) for item in section_sequence if norm_text(item)]
    if len(normalized_sequence) != len(section_sequence):
        issues.append(f"{context}: section_sequence contains blank headings")
    if not isinstance(structure.get("results_before_methods"), bool):
        issues.append(f"{context}: results_before_methods must be boolean")
    valid_theory_modes = {"standalone_literature_theory", "theory_section", "background_section", "embedded_in_introduction"}
    if str(structure.get("theory_presentation", "")).strip() not in valid_theory_modes:
        issues.append(f"{context}: theory_presentation must be one of {sorted(valid_theory_modes)}")
    if not str(structure.get("methods_section_label", "")).strip():
        issues.append(f"{context}: methods_section_label missing")
    valid_close_modes = {"combined_only", "split_required", "split_allowed"}
    if str(structure.get("discussion_conclusion_policy", "")).strip() not in valid_close_modes:
        issues.append(f"{context}: discussion_conclusion_policy must be one of {sorted(valid_close_modes)}")
    if not str(structure.get("supplement_policy", "")).strip():
        issues.append(f"{context}: supplement_policy missing")
    methods_label = norm_text(structure.get("methods_section_label", ""))
    if methods_label and methods_label not in normalized_sequence:
        issues.append(f"{context}: section_sequence must include methods_section_label")
    if "results" not in normalized_sequence:
        issues.append(f"{context}: section_sequence must include Results")
    if methods_label and "results" in normalized_sequence:
        results_idx = normalized_sequence.index("results")
        methods_idx = normalized_sequence.index(methods_label)
        if structure.get("results_before_methods") is True and results_idx > methods_idx:
            issues.append(f"{context}: results_before_methods=true but Results does not precede {methods_label}")
        if structure.get("results_before_methods") is False and methods_idx > results_idx:
            issues.append(f"{context}: results_before_methods=false but {methods_label} does not precede Results")
    profile = expected_profile if expected_profile is not None else expected_journal_profile(target_journal)
    if profile:
        if str(structure.get("theory_presentation", "")).strip() != profile["theory_presentation"]:
            issues.append(f"{context}: theory_presentation must be {profile['theory_presentation']} for {target_journal}")
        if norm_text(structure.get("methods_section_label", "")) != norm_text(profile["methods_section_label"]):
            issues.append(f"{context}: methods_section_label must be {profile['methods_section_label']} for {target_journal}")
        if structure.get("results_before_methods") != profile["results_before_methods"]:
            issues.append(f"{context}: results_before_methods must be {profile['results_before_methods']} for {target_journal}")
        if str(structure.get("discussion_conclusion_policy", "")).strip() != profile["discussion_conclusion_policy"]:
            issues.append(f"{context}: discussion_conclusion_policy must be {profile['discussion_conclusion_policy']} for {target_journal}")
        if str(structure.get("supplement_policy", "")).strip() != profile["supplement_policy"]:
            issues.append(f"{context}: supplement_policy must be {profile['supplement_policy']} for {target_journal}")
        if not sequence_contains_in_order(normalized_sequence, profile["section_sequence"]):
            issues.append(f"{context}: section_sequence must preserve the journal-calibrated order for {target_journal}")
    return issues

def validate_display_architecture(architecture, target_journal, context, expected_profile=None):
    issues = []
    if not isinstance(architecture, dict):
        return [f"{context}: display_architecture must be an object"]
    required = (
        "table_placement_policy",
        "figure_placement_policy",
        "descriptive_table_requirement",
        "editable_text_tables",
        "image_tables_forbidden",
        "main_text_display_cap",
        "main_text_table_cap",
        "main_text_figure_cap",
        "supplement_label_prefix",
        "panel_label_style",
        "table_rendering_mode",
        "figure_rendering_mode",
        "table_title_position",
        "table_notes_policy",
        "display_callout_style",
    )
    missing = [field for field in required if field not in architecture]
    if missing:
        issues.append(f"{context}: missing fields {missing}")
        return issues
    for field in ("table_placement_policy", "figure_placement_policy", "descriptive_table_requirement", "supplement_label_prefix", "panel_label_style", "table_rendering_mode", "figure_rendering_mode", "table_title_position", "table_notes_policy", "display_callout_style"):
        if not str(architecture.get(field, "")).strip():
            issues.append(f"{context}: {field} missing")
    for field in ("editable_text_tables", "image_tables_forbidden"):
        if not isinstance(architecture.get(field), bool):
            issues.append(f"{context}: {field} must be boolean")
    for field in ("main_text_display_cap", "main_text_table_cap", "main_text_figure_cap"):
        value = architecture.get(field)
        if value in (None, ""):
            continue
        try:
            if int(value) < 0:
                issues.append(f"{context}: {field} must be non-negative or null")
        except Exception:
            issues.append(f"{context}: {field} must be integer or null")
    cap = architecture.get("main_text_display_cap")
    table_cap = architecture.get("main_text_table_cap")
    figure_cap = architecture.get("main_text_figure_cap")
    if cap not in (None, "") and table_cap not in (None, "") and figure_cap not in (None, ""):
        if int(table_cap) + int(figure_cap) < 0:
            issues.append(f"{context}: table and figure caps are invalid")
        if int(cap) < max(int(table_cap), int(figure_cap)):
            issues.append(f"{context}: main_text_display_cap cannot be smaller than a component cap")
    profile = expected_profile if expected_profile is not None else expected_journal_profile(target_journal)
    if profile:
        expected = profile["display_architecture"]
        for field, expected_value in expected.items():
            actual_value = architecture.get(field)
            if actual_value != expected_value:
                issues.append(f"{context}: {field} must be {expected_value!r} for {target_journal}")
        if "main_text_display_cap" in expected:
            actual_cap = architecture.get("main_text_display_cap")
            if actual_cap != expected["main_text_display_cap"]:
                issues.append(f"{context}: main_text_display_cap must be {expected['main_text_display_cap']} for {target_journal}")
        elif architecture.get("main_text_display_cap") not in (None, ""):
            try:
                if int(architecture.get("main_text_display_cap")) < 1:
                    issues.append(f"{context}: main_text_display_cap must be null or positive")
            except Exception:
                issues.append(f"{context}: main_text_display_cap must be null or positive integer")
    return issues

def build_profile_from_resolution(resolution):
    if not isinstance(resolution, dict):
        return None
    origin = str(resolution.get("profile_origin", "")).strip()
    if origin == "built_in":
        return expected_journal_profile(resolution.get("resolved_profile_name") or resolution.get("requested_journal"))
    if origin == "fallback_asr":
        return expected_journal_profile("american sociological review")
    if origin == "imported_custom":
        structure = resolution.get("journal_structure")
        display = resolution.get("display_architecture")
        if not isinstance(structure, dict) or not isinstance(display, dict):
            return None
        return {
            "section_sequence": [norm_text(item) for item in structure.get("section_sequence", []) if norm_text(item)],
            "results_before_methods": structure.get("results_before_methods"),
            "theory_presentation": structure.get("theory_presentation"),
            "methods_section_label": structure.get("methods_section_label"),
            "discussion_conclusion_policy": structure.get("discussion_conclusion_policy"),
            "supplement_policy": structure.get("supplement_policy"),
            "display_architecture": display,
        }
    return None

def validate_journal_profile_resolution(resolution, target_journal, context):
    issues = []
    if not isinstance(resolution, dict):
        return [f"{context}: journal_profile_resolution must be an object"]
    required = (
        "requested_journal",
        "resolved_profile_name",
        "profile_origin",
        "profile_source_engine",
        "source_strategy",
        "web_lookup_attempted",
        "fallback_used",
        "fallback_reason",
        "journal_structure",
        "display_architecture",
    )
    missing = [field for field in required if field not in resolution]
    if missing:
        return [f"{context}: journal_profile_resolution missing fields {missing}"]
    origin = str(resolution.get("profile_origin", "")).strip()
    if origin not in {"built_in", "imported_custom", "fallback_asr"}:
        issues.append(f"{context}: profile_origin must be built_in, imported_custom, or fallback_asr")
    if resolution.get("profile_source_engine") != "scholar-journal":
        issues.append(f"{context}: profile_source_engine must be scholar-journal")
    strategy = str(resolution.get("source_strategy", "")).strip()
    if strategy not in {"built_in_catalog", "web_fetched_profile", "asr_fallback"}:
        issues.append(f"{context}: source_strategy must be built_in_catalog, web_fetched_profile, or asr_fallback")
    requested = str(resolution.get("requested_journal", "")).strip()
    resolved = str(resolution.get("resolved_profile_name", "")).strip()
    if not requested:
        issues.append(f"{context}: requested_journal missing")
    if not resolved:
        issues.append(f"{context}: resolved_profile_name missing")
    if not isinstance(resolution.get("web_lookup_attempted"), bool):
        issues.append(f"{context}: web_lookup_attempted must be boolean")
    if not isinstance(resolution.get("fallback_used"), bool):
        issues.append(f"{context}: fallback_used must be boolean")
    target_norm = normalize_journal_name(target_journal)
    requested_norm = normalize_journal_name(requested)
    resolved_norm = normalize_journal_name(resolved)
    if origin == "built_in":
        if strategy != "built_in_catalog":
            issues.append(f"{context}: built_in profiles must use source_strategy=built_in_catalog")
        if resolution.get("fallback_used") is not False:
            issues.append(f"{context}: built_in profiles must have fallback_used=false")
        if str(resolution.get("fallback_reason", "")).strip():
            issues.append(f"{context}: built_in profiles must not include fallback_reason text")
        profile = expected_journal_profile(resolved or target_journal)
        if profile is None:
            issues.append(f"{context}: resolved built_in profile is not in the built-in journal map")
        if target_norm and target_norm != resolved_norm:
            issues.append(f"{context}: built_in resolution must match the active target journal")
    elif origin == "imported_custom":
        if strategy != "web_fetched_profile":
            issues.append(f"{context}: imported_custom profiles must use source_strategy=web_fetched_profile")
        if resolution.get("web_lookup_attempted") is not True:
            issues.append(f"{context}: imported_custom profiles must record web_lookup_attempted=true")
        if resolution.get("fallback_used") is not False:
            issues.append(f"{context}: imported_custom profiles must have fallback_used=false")
        if str(resolution.get("fallback_reason", "")).strip():
            issues.append(f"{context}: imported_custom profiles must not include fallback_reason text")
        if target_norm and target_norm != requested_norm:
            issues.append(f"{context}: imported_custom requested_journal must match the active target journal")
        if requested_norm in builtin_journal_profiles() or resolved_norm in builtin_journal_profiles():
            issues.append(f"{context}: imported_custom may not be used for a journal already covered by the built-in catalog")
    elif origin == "fallback_asr":
        if strategy != "asr_fallback":
            issues.append(f"{context}: fallback_asr profiles must use source_strategy=asr_fallback")
        if resolution.get("web_lookup_attempted") is not True:
            issues.append(f"{context}: fallback_asr profiles must record a failed lookup attempt before fallback")
        if resolution.get("fallback_used") is not True:
            issues.append(f"{context}: fallback_asr profiles must have fallback_used=true")
        if word_count(str(resolution.get("fallback_reason", ""))) < 4:
            issues.append(f"{context}: fallback_asr profiles require a substantive fallback_reason")
        if resolved_norm != "american sociological review":
            issues.append(f"{context}: fallback_asr resolved_profile_name must be American Sociological Review")
        if target_norm and target_norm != "american sociological review":
            issues.append(f"{context}: fallback_asr requires the active target journal to be American Sociological Review")
    expected_profile = build_profile_from_resolution(resolution)
    structure_issues = validate_journal_structure(
        resolution.get("journal_structure"),
        resolved or target_journal,
        f"{context} journal_structure",
        expected_profile=expected_profile if origin in {"built_in", "fallback_asr"} else None,
    )
    display_issues = validate_display_architecture(
        resolution.get("display_architecture"),
        resolved or target_journal,
        f"{context} display_architecture",
        expected_profile=expected_profile if origin in {"built_in", "fallback_asr"} else None,
    )
    issues.extend(structure_issues)
    issues.extend(display_issues)
    return issues

def resolve_profile_for_target(target_journal, resolution, context):
    if resolution is None:
        profile = expected_journal_profile(target_journal)
        if profile is None:
            return None, [f"{context}: target journal is outside the built-in journal map and journal_profile_resolution is missing"]
        return profile, []
    issues = validate_journal_profile_resolution(resolution, target_journal, context)
    if issues:
        return None, issues
    profile = build_profile_from_resolution(resolution)
    if profile is None:
        return None, [f"{context}: journal_profile_resolution could not be converted into a usable journal profile"]
    return profile, []

def fail(message, items=None):
    print(message)
    for item in items or []:
        print(f"  - {item}")
    sys.exit(1)

missing = []
for rel in phase["required_outputs"]:
    matches = glob.glob(str(proj / rel))
    if not matches:
        missing.append(rel)

if missing:
    fail(f"FAIL: Phase {phase_id} {phase['name']} missing required outputs", missing)

if phase_id == "0":
    safety_path = proj / "safety" / "safety-status.json"
    try:
        safety = json.loads(safety_path.read_text())
    except Exception as exc:
        fail(f"FAIL: Phase 0 safety artifact is not valid JSON: {exc}")
    required = ("safety_status", "files_scanned", "no_data_declared", "high_risk_unresolved", "status_by_file")
    absent = [field for field in required if field not in safety]
    if absent:
        fail("FAIL: Phase 0 safety artifact missing required fields", absent)
    try:
        files_scanned = int(safety.get("files_scanned", -1))
        unresolved_count = int(safety.get("high_risk_unresolved", -1))
    except Exception:
        fail("FAIL: Phase 0 files_scanned and high_risk_unresolved must be integers")
    if files_scanned < 0:
        fail("FAIL: Phase 0 files_scanned must be >= 0")
    if unresolved_count < 0:
        fail("FAIL: Phase 0 high_risk_unresolved must be >= 0")
    if files_scanned == 0 and safety.get("no_data_declared") is not True:
        fail("FAIL: Phase 0 files_scanned is 0 but no_data_declared is not true")
    if int(safety.get("high_risk_unresolved", 0)) != 0:
        fail("FAIL: Phase 0 has unresolved high-risk safety entries", safety.get("unresolved_files", []))
    if str(safety.get("safety_status")) not in ("PASS", "PASS_LOCAL_MODE"):
        fail(f"FAIL: Phase 0 safety_status must be PASS or PASS_LOCAL_MODE, got {safety.get('safety_status')}")
    status_by_file = safety.get("status_by_file")
    if not isinstance(status_by_file, dict):
        fail("FAIL: Phase 0 status_by_file must be an object")
    if len(status_by_file) != files_scanned:
        fail("FAIL: Phase 0 files_scanned must match status_by_file count")
    if safety.get("source") == "scholar-init":
        counts = safety.get("counts")
        if not isinstance(counts, dict):
            fail("FAIL: Phase 0 scholar-init import must preserve counts")
        if sum(int(v) for v in counts.values()) != files_scanned:
            fail("FAIL: Phase 0 counts do not sum to files_scanned")
        missing_rationale = []
        for path, entry in status_by_file.items():
            source_status = str(entry.get("source_status", ""))
            if source_status.split(":", 1)[0].strip().upper() == "OVERRIDE":
                rationale = source_status.split(":", 1)[1].strip() if ":" in source_status else ""
                if not rationale:
                    missing_rationale.append(path)
        if missing_rationale:
            fail("FAIL: Phase 0 OVERRIDE entries require scholar-init rationale", missing_rationale)

    # 2026-05-29: setup-project-claudemd.sh is host-aware and may write
    # CLAUDE.md (Claude Code), AGENTS.md (Codex), or both (unknown host).
    # Verify whichever project-memory file exists, while failing malformed
    # marker blocks so a stale partial contract cannot pass Phase 0.
    project_memory_paths = [proj / "CLAUDE.md", proj / "AGENTS.md"]
    present_memory_paths = [path for path in project_memory_paths if path.exists()]
    if not present_memory_paths:
        fail(
            "FAIL: Phase 0 missing project workflow contract file "
            "(CLAUDE.md or AGENTS.md). Run "
            "`bash scripts/setup-project-claudemd.sh \"$PROJ\"` to create it "
            "with the auto-research workflow contract (principles + rules)."
        )
    memory_issues = []
    for memory_path in present_memory_paths:
        try:
            memory_text = memory_path.read_text(errors="ignore")
        except Exception as exc:
            fail(f"FAIL: Phase 0 {memory_path.name} is not readable: {exc}")
        has_begin = "<!-- scholar-auto-research:BEGIN auto-rules" in memory_text
        has_end = "<!-- scholar-auto-research:END auto-rules -->" in memory_text
        if not has_begin:
            memory_issues.append(f"{memory_path.name}: missing BEGIN marker")
        if has_begin and not has_end:
            memory_issues.append(f"{memory_path.name}: BEGIN marker without END marker")
    if memory_issues:
        fail(
            "FAIL: Phase 0 project workflow contract marker block is missing "
            "or malformed. Run `bash scripts/setup-project-claudemd.sh "
            "\"$PROJ\"` to refresh CLAUDE.md/AGENTS.md. User content outside "
            "the markers is preserved.",
            memory_issues,
        )

if phase_id == "1":
    rq_path = proj / "idea" / "research-question.json"
    candidates_path = proj / "idea" / "candidate-rqs.json"
    panel_path = proj / "idea" / "rq-evaluation-panel.json"
    journal_fit_path = proj / "idea" / "journal-fit.json"
    rationale_path = proj / "idea" / "rq-selection-rationale.md"
    rq_md_path = proj / "idea" / "research-question.md"
    try:
        rq = json.loads(rq_path.read_text())
        candidates_doc = json.loads(candidates_path.read_text())
        panel = json.loads(panel_path.read_text())
        journal_fit = json.loads(journal_fit_path.read_text())
    except Exception as exc:
        fail(f"FAIL: Phase 1 research question artifacts are not valid JSON: {exc}")
    required = (
        "verdict",
        "engine",
        "input_mode",
        "selected_rq_id",
        "selected_rq",
        "x",
        "y",
        "directional_relation",
        "mechanism",
        "confounders",
        "scope",
        "target_journal",
        "paper_type",
        "method_orientation",
        "recommended_dataset",
        "claim_strength",
        "rationale",
        "selection_evidence",
        "ready_for_phase_2",
    )
    absent = [field for field in required if field not in rq]
    if absent:
        fail("FAIL: Phase 1 research-question.json missing required fields", absent)
    placeholder_values = {"", "tbd", "todo", "unknown", "n/a", "na", "to be determined"}
    def weak_text(value):
        return not isinstance(value, str) or value.strip().lower() in placeholder_values or bool(re.search(r"\[(insert|add|topic|journal|dataset|tbd)[^\]]*\]", str(value), re.IGNORECASE))
    weak = []
    for field in ("selected_rq", "x", "y", "directional_relation", "mechanism", "paper_type", "method_orientation", "recommended_dataset", "claim_strength", "rationale"):
        value = rq.get(field)
        if weak_text(value):
            weak.append(field)
    if weak:
        fail("FAIL: Phase 1 required fields must be non-placeholder strings", weak)
    if normalized_method_family(rq.get("method_orientation")) is None:
        fail("FAIL: Phase 1 method_orientation must identify a recognized method family")
    if rq.get("verdict") != "PASS" or rq.get("ready_for_phase_2") is not True:
        fail("FAIL: Phase 1 research question verdict must be PASS and ready_for_phase_2 must be true")
    if rq.get("engine") not in {"scholar-idea", "scholar-brainstorm"}:
        fail("FAIL: Phase 1 engine must be scholar-idea or scholar-brainstorm")
    engine_provenance = rq.get("engine_provenance")
    engine_provenance_issues = validate_engine_provenance(engine_provenance, "Phase 1 engine_provenance")
    if engine_provenance_issues:
        fail("FAIL: Phase 1 engine provenance is incomplete", engine_provenance_issues)
    if rq.get("input_mode") not in {"idea", "data", "materials", "paper"}:
        fail("FAIL: Phase 1 input_mode must be idea, data, materials, or paper")
    if rq.get("claim_strength") not in {"causal", "associational", "descriptive", "exploratory"}:
        fail("FAIL: Phase 1 claim_strength is invalid")
    selected = rq["selected_rq"].strip()
    if len(selected.split()) < 8:
        fail("FAIL: Phase 1 selected_rq is too short to guide a full paper")
    x = rq["x"].strip().lower()
    y = rq["y"].strip().lower()
    selected_lower = selected.lower()
    if x not in selected_lower or y not in selected_lower:
        fail("FAIL: Phase 1 selected_rq must mention both x and y")
    if rq["claim_strength"] != "causal" and re.search(r"\b(causal|causes?|effect of|impact of|leads? to|influences?)\b", selected_lower):
        fail("FAIL: Phase 1 selected_rq uses causal language but claim_strength is not causal")
    if rq["directional_relation"].strip().lower() == "exploratory" and len(rq["rationale"].split()) < 12:
        fail("FAIL: Phase 1 exploratory directional_relation requires a substantive rationale")
    confounders = rq.get("confounders")
    if not isinstance(confounders, list) or len(confounders) < 2 or any(weak_text(item) for item in confounders):
        fail("FAIL: Phase 1 confounders must list at least two non-placeholder concepts")
    scope = rq.get("scope")
    if not isinstance(scope, dict):
        fail("FAIL: Phase 1 scope must be an object")
    weak_scope = [field for field in ("population", "place", "time", "unit") if weak_text(scope.get(field))]
    if weak_scope:
        fail("FAIL: Phase 1 scope must define population, place, time, and unit", weak_scope)
    target = rq.get("target_journal")
    if not isinstance(target, dict):
        fail("FAIL: Phase 1 target_journal must be an object")
    weak_target = [
        field
        for field in ("primary", "journal_family", "fit_rationale", "method_bar", "theory_bar")
        if weak_text(target.get(field))
    ]
    if weak_target:
        fail("FAIL: Phase 1 target_journal is incomplete", weak_target)
    if "desk_reject_risks" not in target or not isinstance(target.get("desk_reject_risks"), list):
        fail("FAIL: Phase 1 target_journal.desk_reject_risks must be a list")
    selection = rq.get("selection_evidence")
    if not isinstance(selection, dict):
        fail("FAIL: Phase 1 selection_evidence must be an object")
    selection_issues = []
    if int(selection.get("candidate_count", -1)) < 3:
        selection_issues.append("candidate_count must be at least 3")
    if str(selection.get("panel_consensus", "")).lower() not in {"strong", "mixed"}:
        selection_issues.append("panel_consensus must be strong or mixed")
    if selection.get("fatal_flaw") not in (False, 0):
        selection_issues.append("fatal_flaw must be false")
    if selection.get("data_feasible") is not True:
        selection_issues.append("data_feasible must be true")
    if str(selection.get("journal_fit", "")).lower() not in {"strong", "adequate"}:
        selection_issues.append("journal_fit must be strong or adequate")
    if selection_issues:
        fail("FAIL: Phase 1 selection_evidence is insufficient", selection_issues)

    candidates = candidates_doc.get("candidates")
    if candidates_doc.get("verdict") != "PASS" or candidates_doc.get("engine") != rq.get("engine") or candidates_doc.get("input_mode") != rq.get("input_mode"):
        fail("FAIL: Phase 1 candidate-rqs metadata must pass and match research-question engine/input_mode")
    if not isinstance(candidates, list) or len(candidates) < 3:
        fail("FAIL: Phase 1 candidate-rqs.json must contain at least three candidates")
    selected_id = str(rq.get("selected_rq_id", "")).strip()
    candidate_ids = set()
    selected_candidate = None
    candidate_issues = []
    candidate_required = ("rq_id", "question", "x", "y", "mechanism", "confounders", "scope", "claim_strength", "recommended_dataset", "novelty_risk", "data_feasible", "fatal_flaw")
    for idx, candidate in enumerate(candidates):
        if not isinstance(candidate, dict):
            candidate_issues.append(f"candidates[{idx}] is not an object")
            continue
        cid = str(candidate.get("rq_id", "")).strip()
        if not cid or cid in candidate_ids:
            candidate_issues.append(f"candidates[{idx}].rq_id missing or duplicate")
        candidate_ids.add(cid)
        for field in candidate_required:
            if field not in candidate:
                candidate_issues.append(f"{cid or idx}: {field} missing")
        if cid == selected_id:
            selected_candidate = candidate
    if candidate_issues:
        fail("FAIL: Phase 1 candidates are incomplete", candidate_issues)
    if selected_candidate is None:
        fail("FAIL: Phase 1 selected_rq_id is not present in candidate-rqs.json")
    if selected_candidate.get("fatal_flaw") not in (False, 0):
        fail("FAIL: Phase 1 selected candidate has a fatal flaw")
    if selected_candidate.get("data_feasible") is not True:
        fail("FAIL: Phase 1 selected candidate is not data feasible")
    if str(selected_candidate.get("question", "")).strip() != selected:
        fail("FAIL: Phase 1 selected candidate question must match selected_rq")

    if panel.get("verdict") != "PASS" or panel.get("selected_rq_id") != selected_id or panel.get("fatal_flaw_selected") not in (False, 0) or panel.get("ready_for_selection") is not True:
        fail("FAIL: Phase 1 rq-evaluation-panel must pass for the selected RQ")
    reviewers = panel.get("reviewers")
    if not isinstance(reviewers, list) or len(reviewers) < 5:
        fail("FAIL: Phase 1 rq-evaluation-panel requires at least five reviewers")
    required_roles = {"theorist", "methodologist", "domain_expert", "journal_editor", "devils_advocate"}
    roles = {str(item.get("role", "")).strip() for item in reviewers if isinstance(item, dict)}
    missing_roles = sorted(required_roles - roles)
    if missing_roles:
        fail("FAIL: Phase 1 evaluation panel is missing required roles", missing_roles)

    if journal_fit.get("verdict") != "PASS" or journal_fit.get("selected_rq_id") != selected_id or journal_fit.get("ready_for_phase_2") is not True:
        fail("FAIL: Phase 1 journal-fit report must pass for the selected RQ")
    if journal_fit.get("target_source") not in {"user_provided", "inferred"}:
        fail("FAIL: Phase 1 journal-fit target_source must be user_provided or inferred")
    if journal_fit.get("primary_target") != target.get("primary") or journal_fit.get("journal_family") != target.get("journal_family") or journal_fit.get("paper_type") != rq.get("paper_type"):
        fail("FAIL: Phase 1 journal-fit target metadata must match research-question.json")
    journal_resolution = journal_fit.get("journal_profile_resolution")
    resolution_issues = validate_journal_profile_resolution(journal_resolution, journal_fit.get("primary_target"), "Phase 1")
    if resolution_issues:
        fail("FAIL: Phase 1 journal_profile_resolution is invalid", resolution_issues)
    journal_candidates = journal_fit.get("candidates")
    if not isinstance(journal_candidates, list) or len(journal_candidates) < len(candidates):
        fail("FAIL: Phase 1 journal-fit must score every candidate")
    selected_journal = [item for item in journal_candidates if isinstance(item, dict) and item.get("rq_id") == selected_id]
    if not selected_journal:
        fail("FAIL: Phase 1 journal-fit missing selected candidate")
    selected_fit = selected_journal[0]
    if int(selected_fit.get("fit_score", -1)) < 7 or selected_fit.get("recommended") is not True:
        fail("FAIL: Phase 1 selected candidate journal fit must be recommended with score >= 7")
    if rq.get("engine") == "scholar-brainstorm":
        brainstorm_mode_path = proj / "idea" / "brainstorm-mode.json"
        brainstorm_report_path = proj / "idea" / "brainstorm-report.md"
        brainstorm_summary_path = proj / "idea" / "brainstorm-summary.md"
        for required_path in (brainstorm_mode_path, brainstorm_report_path, brainstorm_summary_path):
            if not required_path.exists():
                fail(f"FAIL: Phase 1 scholar-brainstorm missing required artifact {required_path.relative_to(proj)}")
        try:
            brainstorm_mode = json.loads(brainstorm_mode_path.read_text())
        except Exception as exc:
            fail(f"FAIL: Phase 1 brainstorm-mode.json is not valid JSON: {exc}")
        if brainstorm_mode.get("verdict") != "PASS":
            fail("FAIL: Phase 1 brainstorm-mode verdict must be PASS")
        if brainstorm_mode.get("engine") != "scholar-brainstorm":
            fail("FAIL: Phase 1 brainstorm-mode engine must be scholar-brainstorm")
        expected_mode = str(rq.get("input_mode", "")).upper()
        if brainstorm_mode.get("operating_mode") != expected_mode:
            fail("FAIL: Phase 1 brainstorm operating_mode must match research-question input_mode")
        if int(brainstorm_mode.get("candidate_count", -1)) < 15:
            fail("FAIL: Phase 1 scholar-brainstorm must generate at least 15 candidates before shortlist")
        if int(brainstorm_mode.get("shortlist_count", -1)) < 10:
            fail("FAIL: Phase 1 scholar-brainstorm must produce a Top 10 shortlist")
        if word_count(brainstorm_report_path.read_text(errors="ignore")) < 120:
            fail("FAIL: Phase 1 brainstorm-report.md is too thin")
        if word_count(brainstorm_summary_path.read_text(errors="ignore")) < 50:
            fail("FAIL: Phase 1 brainstorm-summary.md is too thin")

        signal_tests = brainstorm_mode.get("empirical_signal_tests")
        if expected_mode == "DATA":
            variable_inventory_path = proj / "idea" / "variable-inventory.json"
            signal_table_path = proj / "idea" / "empirical-signal-table.csv"
            signal_script_path = proj / "scripts" / "brainstorm-signal-tests.R"
            signal_log_path = proj / "scripts" / "brainstorm-signal-tests.log"
            for required_path in (variable_inventory_path, signal_table_path, signal_script_path, signal_log_path):
                if not required_path.exists():
                    fail(f"FAIL: Phase 1 scholar-brainstorm DATA mode missing required artifact {required_path.relative_to(proj)}")
            try:
                variable_inventory = json.loads(variable_inventory_path.read_text())
            except Exception as exc:
                fail(f"FAIL: Phase 1 variable-inventory.json is not valid JSON: {exc}")
            if not isinstance(variable_inventory.get("variables"), list) or len(variable_inventory.get("variables", [])) < 2:
                fail("FAIL: Phase 1 DATA mode variable inventory must include at least two variables")
            roles_seen = {str(item.get("role", "")).lower() for item in variable_inventory.get("variables", []) if isinstance(item, dict)}
            if "x" not in roles_seen or "y" not in roles_seen:
                fail("FAIL: Phase 1 DATA mode variable inventory must identify x and y variables")
            if not isinstance(signal_tests, dict) or signal_tests.get("required") is not True or signal_tests.get("status") != "PASS":
                fail("FAIL: Phase 1 DATA mode empirical_signal_tests must be required and PASS")
            expected_paths = {
                "script_path": "scripts/brainstorm-signal-tests.R",
                "log_path": "scripts/brainstorm-signal-tests.log",
                "signal_table_path": "idea/empirical-signal-table.csv",
            }
            bad_signal_paths = [
                f"{key}: expected {expected}, got {signal_tests.get(key)!r}"
                for key, expected in expected_paths.items()
                if signal_tests.get(key) != expected
            ]
            if bad_signal_paths:
                fail("FAIL: Phase 1 DATA mode empirical_signal_tests paths are invalid", bad_signal_paths)
            if float(signal_tests.get("score_weight", -1)) <= 0:
                fail("FAIL: Phase 1 DATA mode scoring must include a positive empirical signal weight")
            script_text = signal_script_path.read_text(errors="ignore")
            script_requirements = {
                "effectsize::": "effectsize package calls",
                "tryCatch": "tryCatch wrappers",
                "signal_results": "signal_results object",
                "case_when": "case_when signal thresholds",
            }
            missing_script_terms = [label for term, label in script_requirements.items() if term not in script_text]
            if missing_script_terms:
                fail("FAIL: Phase 1 signal-test script is not protocol-compliant", missing_script_terms)
            log_text = signal_log_path.read_text(errors="ignore")
            if "signal" not in log_text.lower() or word_count(log_text) < 20:
                fail("FAIL: Phase 1 signal-test log is missing aggregated signal output")
            rows = read_csv_dicts(signal_table_path)
            required_signal_cols = {"rq", "x_var", "y_var", "test_type", "estimate", "effect_size", "effect_value", "p_value", "n_obs", "signal"}
            if not rows:
                fail("FAIL: Phase 1 empirical-signal-table.csv must contain signal rows")
            missing_cols = sorted(required_signal_cols - set(rows[0].keys()))
            if missing_cols:
                fail("FAIL: Phase 1 empirical-signal-table.csv missing required columns", missing_cols)
            signal_by_rq = {str(row.get("rq", "")).strip(): row for row in rows}
            if selected_id not in signal_by_rq:
                fail("FAIL: Phase 1 empirical-signal-table.csv missing selected RQ")
            allowed_signals = {"STRONG", "MODERATE", "WEAK", "NULL", "UNTESTABLE", "MECHANISM PLAUSIBLE", "MODERATION DETECTED", "ERROR"}
            eligible_signals = {"STRONG", "MODERATE", "MECHANISM PLAUSIBLE", "MODERATION DETECTED"}
            selected_signal = selected_candidate.get("empirical_signal")
            if not isinstance(selected_signal, dict):
                fail("FAIL: Phase 1 DATA mode selected candidate must include empirical_signal")
            status = str(selected_signal.get("status", "")).strip().upper()
            if status not in allowed_signals:
                fail("FAIL: Phase 1 selected empirical_signal.status is invalid")
            if str(signal_by_rq[selected_id].get("signal", "")).strip().upper() != status:
                fail("FAIL: Phase 1 selected empirical_signal.status must match empirical-signal-table.csv")
            for field in ("effect_size", "effect_value", "p_value", "n_obs", "interpretation"):
                if field not in selected_signal or str(selected_signal.get(field, "")).strip() == "":
                    fail(f"FAIL: Phase 1 selected empirical_signal.{field} is required")
            if status == "WEAK" and not str(selected_signal.get("theory_journal_justification", "")).strip():
                fail("FAIL: Phase 1 WEAK empirical signal requires theory_journal_justification")
            user_override = rq.get("user_override")
            has_override = (
                isinstance(user_override, dict)
                and user_override.get("confirmed") is True
                and user_override.get("pursue_despite_signal") is True
                and word_count(str(user_override.get("reason", ""))) >= 12
            )
            if status not in eligible_signals and status != "WEAK" and not has_override:
                fail("FAIL: Phase 1 cannot select NULL/UNTESTABLE/ERROR empirical signal without explicit user override")
            if selected_signal.get("selection_allowed") is not True and not has_override:
                fail("FAIL: Phase 1 selected empirical signal is not selection_allowed and has no user override")
            rq_signal = selection.get("empirical_signal")
            if not isinstance(rq_signal, dict) or str(rq_signal.get("status", "")).strip().upper() != status:
                fail("FAIL: Phase 1 selection_evidence.empirical_signal must record selected signal status")
            if rq_signal.get("bivariate_only") is not True:
                fail("FAIL: Phase 1 selection_evidence.empirical_signal must mark signal as bivariate_only")
        elif isinstance(signal_tests, dict):
            if signal_tests.get("status") != "SKIPPED":
                fail("FAIL: Phase 1 non-DATA brainstorm modes must mark empirical signal tests as SKIPPED")
    if word_count(rq_md_path.read_text(errors="ignore")) < 30:
        fail("FAIL: Phase 1 research-question.md is too thin")
    if word_count(rationale_path.read_text(errors="ignore")) < 80:
        fail("FAIL: Phase 1 rq-selection-rationale.md is too thin")

if phase_id == "2":
    matrix_path = proj / "literature" / "literature-coverage-matrix.json"
    lit_path = proj / "literature" / "lit-theory.md"
    bib_path = proj / "literature" / "references.bib"
    manifest_path = proj / "literature" / "lit-theory-manifest.json"
    rq_path = proj / "idea" / "research-question.json"
    journal_fit_path = proj / "idea" / "journal-fit.json"
    try:
        matrix = json.loads(matrix_path.read_text())
        manifest = json.loads(manifest_path.read_text())
        rq = json.loads(rq_path.read_text())
        journal_fit = json.loads(journal_fit_path.read_text())
    except Exception as exc:
        fail(f"FAIL: Phase 2 literature or journal-fit artifact is not valid JSON: {exc}")
    if matrix.get("verdict") != "PASS":
        fail("FAIL: Phase 2 literature-coverage-matrix verdict must be PASS")
    if matrix.get("ready_for_phase_3") is not True:
        fail("FAIL: Phase 2 literature-coverage-matrix ready_for_phase_3 must be true")
    engine_handoff = matrix.get("engine_handoff")
    if not isinstance(engine_handoff, dict):
        fail("FAIL: Phase 2 engine_handoff must be an object")
    lit_engine = engine_handoff.get("lit_review_engine")
    write_engine = engine_handoff.get("writing_engine")
    engine_issues = []
    if not isinstance(lit_engine, dict) or lit_engine.get("skill") != "scholar-lit-review-hypothesis" or lit_engine.get("mode") != "integrated_literature_theory_hypotheses":
        engine_issues.append("lit_review_engine must be scholar-lit-review-hypothesis integrated_literature_theory_hypotheses")
    if not isinstance(write_engine, dict) or write_engine.get("skill") != "scholar-write" or write_engine.get("mode") not in {"draft", "revise"} or write_engine.get("section") != "Literature Review and Theory":
        engine_issues.append("writing_engine must be scholar-write draft/revise Literature Review and Theory")
    if engine_handoff.get("target_journal") != journal_fit.get("primary_target"):
        engine_issues.append("engine_handoff target_journal must match Phase 1 journal fit")
    engine_issues.extend(validate_engine_provenance(lit_engine, "Phase 2 lit_review_engine"))
    engine_issues.extend(validate_engine_provenance(write_engine, "Phase 2 writing_engine"))
    if engine_issues:
        fail("FAIL: Phase 2 engine handoff is invalid", engine_issues)
    review_protocol_ref = matrix.get("review_protocol")
    if review_protocol_ref != "literature/review-protocol.json":
        fail("FAIL: Phase 2 literature-coverage-matrix review_protocol must equal literature/review-protocol.json")
    coverage = matrix.get("coverage_matrix")
    if not isinstance(coverage, dict):
        fail("FAIL: Phase 2 coverage_matrix must be an object")
    required_categories = ("constructs", "theories", "methods", "datasets_populations", "competing_findings")
    empty_categories = []
    for category in required_categories:
        value = coverage.get(category)
        if not isinstance(value, list) or not value:
            empty_categories.append(category)
    if empty_categories:
        fail("FAIL: Phase 2 coverage_matrix categories must be non-empty lists", empty_categories)
    must_cite = matrix.get("must_cite_coverage")
    if not isinstance(must_cite, list) or len(must_cite) <= 30:
        fail("FAIL: Phase 2 must_cite_coverage must list more than 30 works")
    uncovered = []
    for idx, item in enumerate(must_cite):
        if not isinstance(item, dict):
            uncovered.append(f"must_cite_coverage[{idx}] is not an object")
        elif item.get("covered") is not True:
            label = item.get("key") or item.get("title") or idx
            uncovered.append(str(label))
    if uncovered:
        fail("FAIL: Phase 2 must-cite works are not fully covered", uncovered)
    source_role_matrix = matrix.get("source_role_matrix")
    if not isinstance(source_role_matrix, list) or len(source_role_matrix) < 12:
        fail("FAIL: Phase 2 source_role_matrix must include at least 12 argument-role source entries")
    allowed_source_roles = {
        "theory",
        "mechanism",
        "rival",
        "competing_explanation",
        "method",
        "design",
        "context",
        "population",
        "domain",
        "data",
        "empirical_prior",
        "journal_canon",
    }
    source_role_issues = []
    source_roles_seen = set()
    for idx, item in enumerate(source_role_matrix or []):
        if not isinstance(item, dict):
            source_role_issues.append(f"source_role_matrix[{idx}] is not an object")
            continue
        key_or_title = str(item.get("key", "") or item.get("title", "")).strip()
        role = str(item.get("argument_role", "")).strip()
        source_roles_seen.add(role)
        if not key_or_title:
            source_role_issues.append(f"source_role_matrix[{idx}] missing key or title")
        if role not in allowed_source_roles:
            source_role_issues.append(f"{key_or_title or idx}: invalid argument_role {role or '<missing>'}")
        for field in ("claim_supported", "target_section", "why_it_matters"):
            if word_count(str(item.get(field, ""))) < 4:
                source_role_issues.append(f"{key_or_title or idx}: {field} too thin")
    required_source_role_groups = [
        {"theory"},
        {"mechanism"},
        {"rival", "competing_explanation"},
        {"method", "design"},
    ]
    for group in required_source_role_groups:
        if not source_roles_seen.intersection(group):
            source_role_issues.append(f"missing source role group {sorted(group)}")
    if source_role_issues:
        fail("FAIL: Phase 2 source_role_matrix does not assign sources to argument roles", source_role_issues[:30])
    mechanism = matrix.get("mechanism_chain")
    if not isinstance(mechanism, list) or len(mechanism) < 2:
        fail("FAIL: Phase 2 mechanism_chain must include at least 2 linked steps")
    weak_mechanism = [str(i) for i, step in enumerate(mechanism) if not isinstance(step, dict) or not step.get("link")]
    if weak_mechanism:
        fail("FAIL: Phase 2 mechanism_chain steps must include link text", weak_mechanism)
    hypotheses = matrix.get("hypotheses")
    if not isinstance(hypotheses, list) or not hypotheses:
        fail("FAIL: Phase 2 hypotheses must include at least one hypothesis")
    non_directional = []
    for idx, hyp in enumerate(hypotheses):
        if not isinstance(hyp, dict) or not hyp.get("text") or not hyp.get("direction"):
            non_directional.append(str(idx))
    if non_directional:
        fail("FAIL: Phase 2 hypotheses must include text and direction", non_directional)
    journal_calibration = matrix.get("journal_calibration")
    if not isinstance(journal_calibration, dict):
        fail("FAIL: Phase 2 journal_calibration must be an object")
    calibration_issues = []
    if journal_calibration.get("target_journal") != journal_fit.get("primary_target"):
        calibration_issues.append("target_journal must match Phase 1 journal-fit primary_target")
    if journal_calibration.get("paper_type") != journal_fit.get("paper_type"):
        calibration_issues.append("paper_type must match Phase 1 journal-fit paper_type")
    for field in ("theory_depth", "citation_density", "must_cite_strategy"):
        value = journal_calibration.get(field)
        if not isinstance(value, str) or not value.strip():
            calibration_issues.append(f"{field} missing")
    if calibration_issues:
        fail("FAIL: Phase 2 journal_calibration is incomplete", calibration_issues)
    review_protocol_path = proj / "literature" / "review-protocol.json"
    search_log_path = proj / "literature" / "search-log.md"
    try:
        review_protocol = json.loads(review_protocol_path.read_text())
    except Exception as exc:
        fail(f"FAIL: Phase 2 review-protocol artifact is not valid JSON: {exc}")
    protocol_issues = []
    if review_protocol.get("verdict") != "PASS":
        protocol_issues.append("review-protocol verdict must be PASS")
    if str(review_protocol.get("source_phase")) != "2":
        protocol_issues.append("review-protocol source_phase must be 2")
    if review_protocol.get("primary_skill") != "scholar-lit-review-hypothesis":
        protocol_issues.append("review-protocol primary_skill must be scholar-lit-review-hypothesis")
    if review_protocol.get("local_library_first") is not True:
        protocol_issues.append("review-protocol local_library_first must be true")
    backends = review_protocol.get("reference_backend_detected")
    if not isinstance(backends, list) or not backends:
        protocol_issues.append("reference_backend_detected must be a non-empty list")
    else:
        allowed_backends = {"zotero", "mendeley", "bibtex", "endnote xml", "endnote"}
        if not any(str(item).strip().lower() in allowed_backends for item in backends):
            protocol_issues.append("reference_backend_detected must include Zotero, Mendeley, BibTeX, or EndNote XML")
    for field, minimum in (("ref_queries", 3), ("author_queries", 1)):
        try:
            value = int(review_protocol.get(field, -1))
        except Exception:
            value = -1
        if value < minimum:
            protocol_issues.append(f"{field} must be >= {minimum}")
    for field in ("knowledge_graph_checked", "source_integrity_completed", "verification_panel_completed", "ready_for_phase_3"):
        if review_protocol.get(field) not in {True, False}:
            protocol_issues.append(f"{field} must be boolean")
    if review_protocol.get("source_integrity_completed") is not True:
        protocol_issues.append("source_integrity_completed must be true")
    if review_protocol.get("verification_panel_completed") is not True:
        protocol_issues.append("verification_panel_completed must be true")
    if str(review_protocol.get("search_log_path", "")).strip() != "literature/search-log.md":
        protocol_issues.append("search_log_path must equal literature/search-log.md")
    prior_bibs = review_protocol.get("prior_project_bibliographies_used")
    if not isinstance(prior_bibs, list):
        protocol_issues.append("prior_project_bibliographies_used must be a list")
    if lit_engine.get("protocol_followed") is not True:
        protocol_issues.append("lit_review_engine.protocol_followed must be true")
    lit_protocol_artifacts = lit_engine.get("protocol_artifacts")
    expected_protocol_artifacts = {"literature/review-protocol.json", "literature/search-log.md"}
    if not isinstance(lit_protocol_artifacts, list) or set(map(str, lit_protocol_artifacts)) != expected_protocol_artifacts:
        protocol_issues.append("lit_review_engine.protocol_artifacts must list literature/review-protocol.json and literature/search-log.md")
    if protocol_issues:
        fail("FAIL: Phase 2 review protocol is incomplete", protocol_issues)
    rows = parse_search_log_rows(search_log_path)
    if not rows:
        fail("FAIL: Phase 2 search-log.md must contain searchable query rows")
    ref_rows = [idx for idx, row in enumerate(rows) if normalize_search_source(row[1]) == "reflib"]
    web_rows = [idx for idx, row in enumerate(rows) if normalize_search_source(row[1]) == "web"]
    author_rows = [row for row in rows if normalize_search_source(row[1]) == "reflib" and "author" in row[2].lower()]
    if len(ref_rows) < 3:
        fail("FAIL: Phase 2 search-log.md must include at least 3 local-library RefLib rows")
    if not author_rows:
        fail("FAIL: Phase 2 search-log.md must include at least 1 local-library author query")
    if web_rows and min(web_rows) < min(ref_rows):
        fail("FAIL: Phase 2 search-log.md must show local-library searches before web searches")
    bib_text = bib_path.read_text(errors="ignore")
    bib_entries = re.findall(r"@\w+\s*\{", bib_text)
    if len(bib_entries) <= 30:
        fail(f"FAIL: Phase 2 references.bib must contain more than 30 BibTeX entries, found {len(bib_entries)}")
    lit_words = re.findall(r"\b\w+\b", lit_path.read_text(errors="ignore"))
    if len(lit_words) < 500:
        fail(f"FAIL: Phase 2 lit-theory.md is too short for a theory/literature handoff, found {len(lit_words)} words")
    if manifest.get("verdict") != "PASS" or manifest.get("source_phase") != "2" or manifest.get("ready_for_phase_3") is not True:
        fail("FAIL: Phase 2 lit-theory manifest must PASS with source_phase 2 and ready_for_phase_3 true")
    if manifest.get("engine_handoff") != engine_handoff:
        fail("FAIL: Phase 2 lit-theory manifest engine_handoff must match coverage matrix")
    protocol_artifacts = manifest.get("protocol_artifacts")
    if protocol_artifacts != {"search_log": "literature/search-log.md", "review_protocol": "literature/review-protocol.json"}:
        fail("FAIL: Phase 2 lit-theory manifest must record canonical protocol artifacts")
    expected_manifest_hashes = {
        "selected_rq_hash": sha256(rq_path),
        "journal_fit_hash": sha256(journal_fit_path),
        "coverage_matrix_hash": sha256(matrix_path),
        "lit_theory_hash": sha256(lit_path),
        "references_bib_hash": sha256(bib_path),
    }
    stale_manifest = [
        f"{key} mismatch"
        for key, expected in expected_manifest_hashes.items()
        if manifest.get(key) != expected
    ]
    if stale_manifest:
        fail("FAIL: Phase 2 lit-theory manifest hashes are stale", stale_manifest)
    source_hashes = manifest.get("source_hashes")
    if not isinstance(source_hashes, dict):
        fail("FAIL: Phase 2 lit-theory manifest source_hashes must be an object")
    for key, expected in {
        "research_question": sha256(rq_path),
        "journal_fit": sha256(journal_fit_path),
    }.items():
        if source_hashes.get(key) != expected:
            fail("FAIL: Phase 2 lit-theory manifest source_hashes are stale", [f"{key} mismatch"])

if phase_id == "3":
    blueprint_path = proj / "design" / "design-blueprint.md"
    specs_path = proj / "design" / "model-specs.json"
    id_path = proj / "design" / "identification-strategy.json"
    manifest_path = proj / "design" / "design-manifest.json"
    evaluation_path = proj / "design" / "design-evaluation.json"
    revision_path = proj / "design" / "design-revision-log.json"
    rq_path = proj / "idea" / "research-question.json"
    journal_fit_path = proj / "idea" / "journal-fit.json"
    lit_path = proj / "literature" / "lit-theory.md"
    lit_manifest_path = proj / "literature" / "lit-theory-manifest.json"
    lit_matrix_path = proj / "literature" / "literature-coverage-matrix.json"
    placeholder_values = {"", "tbd", "todo", "unknown", "n/a", "na", "to be determined"}
    try:
        ident = json.loads(id_path.read_text())
        rq = json.loads(rq_path.read_text())
        journal_fit = json.loads(journal_fit_path.read_text())
        lit_manifest = json.loads(lit_manifest_path.read_text())
        lit_matrix = json.loads(lit_matrix_path.read_text())
    except Exception as exc:
        fail(f"FAIL: Phase 3 design input or identification artifact is not valid JSON: {exc}")
    if lit_manifest.get("ready_for_phase_3") is not True or lit_matrix.get("ready_for_phase_3") is not True:
        fail("FAIL: Phase 3 literature inputs are not ready_for_phase_3")
    required = (
        "design_type",
        "claim_strength",
        "estimand",
        "identification_strategy",
        "outcome_mechanism_alignment",
        "journal_method_bar",
        "hypothesis_model_coverage",
        "power_or_feasibility_assessment",
        "causal_gate",
        "assumptions",
        "measures",
        "threats",
        "robustness_plan",
    )
    absent = [field for field in required if field not in ident]
    if absent:
        fail("FAIL: Phase 3 identification-strategy.json missing required fields", absent)
    weak_strings = []
    for field in ("design_type", "claim_strength", "estimand", "identification_strategy", "journal_method_bar"):
        value = ident.get(field)
        if not isinstance(value, str) or value.strip().lower() in placeholder_values:
            weak_strings.append(field)
    if weak_strings:
        fail("FAIL: Phase 3 core design fields must be non-placeholder strings", weak_strings)
    rq_claim_strength = str(rq.get("claim_strength", "")).strip().lower()
    ident_claim_strength = str(ident.get("claim_strength", "")).strip().lower()
    if rq_claim_strength and ident_claim_strength != rq_claim_strength:
        revision_note = str(ident.get("claim_strength_revision_rationale", "")).strip()
        if word_count(revision_note) < 12:
            fail("FAIL: Phase 3 claim_strength must match Phase 1 or include a substantive revision rationale")
    target_journal = journal_fit.get("primary_target")
    rq_target = rq.get("target_journal")
    if isinstance(rq_target, dict) and rq_target.get("primary") and target_journal and rq_target.get("primary") != target_journal:
        fail("FAIL: Phase 3 journal-fit target does not match research-question target")
    align_allowed = {"entry-process", "prevalence-stock", "dissolution", "multi-state"}
    alignment = str(ident.get("outcome_mechanism_alignment", "")).strip()
    if alignment not in align_allowed:
        fail("FAIL: Phase 3 outcome_mechanism_alignment is invalid", [alignment or "<missing>"])
    list_minimums = {"assumptions": 2, "threats": 2, "robustness_plan": 2}
    weak_lists = []
    for field, minimum in list_minimums.items():
        value = ident.get(field)
        if not isinstance(value, list) or len(value) < minimum:
            weak_lists.append(f"{field} requires at least {minimum} items")
    if weak_lists:
        fail("FAIL: Phase 3 assumptions, threats, and robustness_plan are too thin", weak_lists)
    measures = ident.get("measures")
    if not isinstance(measures, dict):
        fail("FAIL: Phase 3 measures must be an object")
    weak_measures = []
    for key in ("x", "y"):
        measure = measures.get(key)
        if not isinstance(measure, dict):
            weak_measures.append(f"{key} missing")
            continue
        for field in ("name", "operationalization"):
            value = measure.get(field)
            if not isinstance(value, str) or value.strip().lower() in placeholder_values:
                weak_measures.append(f"{key}.{field}")
    if weak_measures:
        fail("FAIL: Phase 3 measures must define x/y names and operationalizations", weak_measures)
    power = ident.get("power_or_feasibility_assessment")
    if not isinstance(power, dict):
        fail("FAIL: Phase 3 power_or_feasibility_assessment must be an object")
    if power.get("status") not in {"powered", "feasible_existing_data", "feasibility_limited", "not_applicable"}:
        fail("FAIL: Phase 3 power_or_feasibility_assessment.status is invalid")
    if word_count(str(power.get("rationale", ""))) < 8:
        fail("FAIL: Phase 3 power_or_feasibility_assessment needs a substantive rationale")
    method_family, expected_execution_skill, method_components, routing_issues = validate_method_specialist_routing(
        ident.get("method_specialist_routing"),
        rq.get("method_orientation"),
        "Phase 3",
    )
    if routing_issues:
        fail("FAIL: Phase 3 method-specialist routing is incomplete", routing_issues)
    causal_gate = ident.get("causal_gate")
    if not isinstance(causal_gate, dict):
        fail("FAIL: Phase 3 causal_gate must be an object")
    design_blob = " ".join(
        str(part)
        for part in (
            ident.get("claim_strength"),
            ident.get("design_type"),
            ident.get("identification_strategy"),
            ident.get("estimand"),
        )
    ).lower()
    causal_method_keywords = (
        "difference-in-differences",
        "difference in differences",
        "did",
        "fixed effects",
        "fixed-effects",
        "event-study",
        "event study",
        "regression discontinuity",
        "instrumental variable",
        "matching",
        "mediation",
        "synthetic control",
        "dml",
        "causal forest",
    )
    negated_causal_pattern = re.compile(
        r"\b(no|not|non|without)\s+(credible\s+|formal\s+)?(causal|quasi[- ]causal)\s+"
        r"(effect|effects|estimand|identification|inference|design|claim|claims|strategy)\b"
    )
    causal_phrase_pattern = re.compile(
        r"\b(causal|quasi[- ]causal)\s+"
        r"(effect|effects|estimand|identification|inference|design|claim|claims|strategy)\b"
    )
    unnegated_causal_blob = negated_causal_pattern.sub("", design_blob)
    causal_required_by_content = (
        ident_claim_strength == "causal"
        or any(keyword in design_blob for keyword in causal_method_keywords)
        or bool(causal_phrase_pattern.search(unnegated_causal_blob))
    )
    if causal_required_by_content and causal_gate.get("required") is not True:
        fail("FAIL: Phase 3 causal_gate.required must be true for causal/quasi-causal designs")
    if causal_gate.get("required") is True:
        if causal_gate.get("invoked") is not True:
            fail("FAIL: Phase 3 causal_gate requires scholar-causal invocation")
        if causal_gate.get("skill") != "scholar-causal":
            fail("FAIL: Phase 3 causal_gate skill must be scholar-causal when invoked")
    try:
        specs = json.loads(specs_path.read_text())
    except Exception as exc:
        fail(f"FAIL: Phase 3 model-specs.json is not valid JSON: {exc}")
    models = specs.get("models")
    if not isinstance(models, list) or not models:
        fail("FAIL: Phase 3 model-specs.json must include a non-empty models list")
    bad_models = []
    model_required = ("id", "outcome", "predictors", "estimator", "covariates", "purpose")
    for idx, model in enumerate(models):
        if not isinstance(model, dict):
            bad_models.append(f"models[{idx}] is not an object")
            continue
        for field in model_required:
            if field not in model:
                bad_models.append(f"models[{idx}].{field} missing")
        if "predictors" in model and (not isinstance(model["predictors"], list) or not model["predictors"]):
            bad_models.append(f"models[{idx}].predictors must be non-empty list")
        if "covariates" in model and not isinstance(model["covariates"], list):
            bad_models.append(f"models[{idx}].covariates must be list")
        if "hypothesis_ids" in model and not isinstance(model["hypothesis_ids"], list):
            bad_models.append(f"models[{idx}].hypothesis_ids must be list")
    if bad_models:
        fail("FAIL: Phase 3 model specifications are incomplete", bad_models)
    hypothesis_ids = []
    for idx, hyp in enumerate(lit_matrix.get("hypotheses", [])):
        if not isinstance(hyp, dict) or not str(hyp.get("id", "")).strip():
            fail("FAIL: Phase 3 requires every Phase 2 hypothesis to have an id", [f"hypotheses[{idx}]"])
        hypothesis_ids.append(str(hyp.get("id")).strip())
    model_ids = {str(model.get("id", "")).strip() for model in models if isinstance(model, dict)}
    model_hypothesis_ids = set()
    for model in models:
        if isinstance(model, dict):
            model_hypothesis_ids.update(str(h).strip() for h in model.get("hypothesis_ids", []) if str(h).strip())
    coverage = ident.get("hypothesis_model_coverage")
    if not isinstance(coverage, list) or not coverage:
        fail("FAIL: Phase 3 hypothesis_model_coverage must be a non-empty list")
    covered_hypotheses = set()
    coverage_issues = []
    for idx, item in enumerate(coverage):
        if not isinstance(item, dict):
            coverage_issues.append(f"hypothesis_model_coverage[{idx}] is not an object")
            continue
        hid = str(item.get("hypothesis_id", "")).strip()
        if hid not in hypothesis_ids:
            coverage_issues.append(f"hypothesis_model_coverage[{idx}] unknown hypothesis_id {hid or '<missing>'}")
            continue
        if item.get("accepted_unmodeled_limitation") is True:
            if word_count(str(item.get("rationale", ""))) < 8:
                coverage_issues.append(f"{hid} accepted limitation needs rationale")
            covered_hypotheses.add(hid)
            continue
        ids = item.get("model_ids")
        if not isinstance(ids, list) or not ids:
            coverage_issues.append(f"{hid} missing model_ids")
            continue
        unknown_models = [mid for mid in ids if str(mid) not in model_ids]
        if unknown_models:
            coverage_issues.append(f"{hid} references unknown models {unknown_models}")
        if hid not in model_hypothesis_ids:
            coverage_issues.append(f"{hid} not listed in any model hypothesis_ids")
        covered_hypotheses.add(hid)
    missing_hypotheses = sorted(set(hypothesis_ids) - covered_hypotheses)
    coverage_issues.extend(f"missing hypothesis coverage {hid}" for hid in missing_hypotheses)
    if coverage_issues:
        fail("FAIL: Phase 3 hypothesis-model coverage is incomplete", coverage_issues)
    blueprint_text = blueprint_path.read_text(errors="ignore")
    blueprint_words = re.findall(r"\b\w+\b", blueprint_text)
    if len(blueprint_words) < 300:
        fail(f"FAIL: Phase 3 design-blueprint.md is too short, found {len(blueprint_words)} words")
    if not re.search(rf"^outcome_mechanism_alignment:\s*{re.escape(alignment)}\s*$", blueprint_text, flags=re.MULTILINE):
        fail("FAIL: Phase 3 design-blueprint.md must include matching outcome_mechanism_alignment line")
    try:
        manifest = json.loads(manifest_path.read_text())
    except Exception as exc:
        fail(f"FAIL: Phase 3 design-manifest.json is not valid JSON: {exc}")
    if manifest.get("verdict") != "PASS" or manifest.get("source_phase") != "3" or manifest.get("ready_for_phase_4") is not True:
        fail("FAIL: Phase 3 design manifest must PASS with source_phase 3 and ready_for_phase_4 true")
    design_engine = manifest.get("design_engine")
    if not isinstance(design_engine, dict) or design_engine.get("skill") != "scholar-design":
        fail("FAIL: Phase 3 design manifest must record scholar-design as design_engine")
    design_engine_issues = validate_engine_provenance(design_engine, "Phase 3 design_engine")
    if design_engine_issues:
        fail("FAIL: Phase 3 design_engine provenance is incomplete", design_engine_issues)
    causal_engine = manifest.get("causal_engine")
    if not isinstance(causal_engine, dict):
        fail("FAIL: Phase 3 design manifest must include causal_engine object")
    if causal_gate.get("required") is True and (causal_engine.get("invoked") is not True or causal_engine.get("skill") != "scholar-causal"):
        fail("FAIL: Phase 3 design manifest must record scholar-causal when causal_gate requires it")
    if causal_gate.get("required") is True:
        causal_engine_issues = validate_engine_provenance(causal_engine, "Phase 3 causal_engine")
        if causal_engine_issues:
            fail("FAIL: Phase 3 causal_engine provenance is incomplete", causal_engine_issues)
    method_specialist_engines = manifest.get("method_specialist_engines")
    if not isinstance(method_specialist_engines, list):
        fail("FAIL: Phase 3 design manifest must include method_specialist_engines list")
    engine_lookup = {
        str(item.get("skill", "")).strip(): item
        for item in method_specialist_engines
        if isinstance(item, dict) and str(item.get("skill", "")).strip()
    }
    required_method_skills = set()
    if method_family == "computational":
        required_method_skills.add("scholar-compute")
    elif method_family == "qualitative":
        required_method_skills.add("scholar-qual")
    elif method_family == "linguistic":
        required_method_skills.add("scholar-ling")
    elif method_family == "mixed_methods":
        required_method_skills = allowed_skills_for_method_orientation(rq.get("method_orientation")) - {"scholar-analyze"}
    missing_method_skills = []
    for skill in sorted(required_method_skills):
        item = engine_lookup.get(skill)
        if not isinstance(item, dict) or item.get("invoked") is not True:
            missing_method_skills.append(skill)
        elif validate_engine_provenance(item, f"Phase 3 method_specialist_engine {skill}"):
            missing_method_skills.append(f"{skill} provenance incomplete")
    if missing_method_skills:
        fail("FAIL: Phase 3 design manifest must record required specialist method engines", missing_method_skills)
    if manifest.get("target_journal") != target_journal:
        fail("FAIL: Phase 3 design manifest target_journal must match Phase 1 journal-fit")
    if str(manifest.get("claim_strength", "")).strip().lower() != ident_claim_strength:
        fail("FAIL: Phase 3 design manifest claim_strength must match identification-strategy.json")
    claim_continuity = manifest.get("claim_continuity")
    continuity_issues = []
    if not isinstance(claim_continuity, dict):
        continuity_issues.append("claim_continuity must be an object")
    else:
        if str(claim_continuity.get("claim_strength", "")).strip().lower() != ident_claim_strength:
            continuity_issues.append("claim_continuity.claim_strength must match identification-strategy.json")
        for field in ("mechanisms_carried_forward", "hypotheses_carried_forward", "robustness_carried_forward", "limitations_carried_forward"):
            if claim_continuity.get(field) is not True:
                continuity_issues.append(f"{field} must be true")
        if word_count(str(claim_continuity.get("manuscript_claim_boundary", ""))) < 8:
            continuity_issues.append("manuscript_claim_boundary too thin")
    mechanism_result_matrix = manifest.get("mechanism_result_matrix")
    if not isinstance(mechanism_result_matrix, list) or not mechanism_result_matrix:
        continuity_issues.append("mechanism_result_matrix must be a nonempty list")
    else:
        for idx, item in enumerate(mechanism_result_matrix):
            if not isinstance(item, dict):
                continuity_issues.append(f"mechanism_result_matrix[{idx}] is not an object")
                continue
            for field in ("mechanism", "model_or_spec", "expected_pattern", "manuscript_implication"):
                if word_count(str(item.get(field, ""))) < 3:
                    continuity_issues.append(f"mechanism_result_matrix[{idx}].{field} too thin")
    robustness_claim_matrix = manifest.get("robustness_claim_matrix")
    if not isinstance(robustness_claim_matrix, list) or len(robustness_claim_matrix) < len(ident.get("robustness_plan", [])):
        continuity_issues.append("robustness_claim_matrix must cover the robustness plan")
    else:
        for idx, item in enumerate(robustness_claim_matrix):
            if not isinstance(item, dict):
                continuity_issues.append(f"robustness_claim_matrix[{idx}] is not an object")
                continue
            for field in ("robustness_check", "claim_implication", "weaken_or_bound_rule"):
                if word_count(str(item.get(field, ""))) < 3:
                    continuity_issues.append(f"robustness_claim_matrix[{idx}].{field} too thin")
    limitation_scope_matrix = manifest.get("limitation_scope_matrix")
    if not isinstance(limitation_scope_matrix, list) or not limitation_scope_matrix:
        continuity_issues.append("limitation_scope_matrix must be a nonempty list")
    else:
        for idx, item in enumerate(limitation_scope_matrix):
            if not isinstance(item, dict):
                continuity_issues.append(f"limitation_scope_matrix[{idx}] is not an object")
                continue
            for field in ("limitation", "scope_language", "affected_claim"):
                if word_count(str(item.get(field, ""))) < 3:
                    continuity_issues.append(f"limitation_scope_matrix[{idx}].{field} too thin")
    if continuity_issues:
        fail("FAIL: Phase 3 design-to-writing continuity is incomplete", continuity_issues[:30])
    expected_source_hashes = {
        "research_question": sha256(rq_path),
        "journal_fit": sha256(journal_fit_path),
        "lit_theory": sha256(lit_path),
        "lit_theory_manifest": sha256(lit_manifest_path),
        "literature_coverage_matrix": sha256(lit_matrix_path),
    }
    source_hashes = manifest.get("source_hashes")
    if not isinstance(source_hashes, dict):
        fail("FAIL: Phase 3 design manifest source_hashes must be an object")
    stale_sources = [
        f"{key} mismatch"
        for key, expected in expected_source_hashes.items()
        if source_hashes.get(key) != expected
    ]
    if stale_sources:
        fail("FAIL: Phase 3 design manifest source_hashes are stale", stale_sources)
    expected_output_hashes = {
        "design_blueprint": sha256(blueprint_path),
        "identification_strategy": sha256(id_path),
        "model_specs": sha256(specs_path),
    }
    output_hashes = manifest.get("output_hashes")
    if not isinstance(output_hashes, dict):
        fail("FAIL: Phase 3 design manifest output_hashes must be an object")
    stale_outputs = [
        f"{key} mismatch"
        for key, expected in expected_output_hashes.items()
        if output_hashes.get(key) != expected
    ]
    if stale_outputs:
        fail("FAIL: Phase 3 design manifest output_hashes are stale", stale_outputs)
    try:
        evaluation = json.loads(evaluation_path.read_text())
    except Exception as exc:
        fail(f"FAIL: Phase 3 design-evaluation.json is not valid JSON: {exc}")
    if evaluation.get("overall_verdict") != "PASS":
        fail(f"FAIL: Phase 3 design evaluation overall_verdict must be PASS, got {evaluation.get('overall_verdict')}")
    if int(evaluation.get("unresolved_critical_count", -1)) != 0:
        fail("FAIL: Phase 3 design evaluation has unresolved critical issues")
    reviewers = evaluation.get("reviewers")
    if not isinstance(reviewers, list) or len(reviewers) < 5:
        fail("FAIL: Phase 3 design evaluation requires at least 5 reviewers")
    required_roles = {"identification", "measurement", "theory_mechanism", "feasibility_data", "journal_skeptic"}
    roles = set()
    bad_reviewers = []
    for idx, reviewer in enumerate(reviewers):
        if not isinstance(reviewer, dict):
            bad_reviewers.append(f"reviewers[{idx}] is not an object")
            continue
        role = str(reviewer.get("role", ""))
        roles.add(role)
        if reviewer.get("verdict") not in ("PASS", "ACCEPTED_LIMITATION"):
            bad_reviewers.append(f"reviewers[{idx}].verdict={reviewer.get('verdict')}")
        if int(reviewer.get("critical_issues_count", 0)) != 0:
            bad_reviewers.append(f"reviewers[{idx}] has unresolved critical issues")
    missing_roles = sorted(required_roles - roles)
    if missing_roles:
        bad_reviewers.extend(f"missing role {role}" for role in missing_roles)
    if bad_reviewers:
        fail("FAIL: Phase 3 design evaluation reviewer panel is incomplete or unresolved", bad_reviewers)
    try:
        revision = json.loads(revision_path.read_text())
    except Exception as exc:
        fail(f"FAIL: Phase 3 design-revision-log.json is not valid JSON: {exc}")
    if revision.get("required_revisions_completed") is not True:
        fail("FAIL: Phase 3 required design revisions are not completed")
    if int(revision.get("unresolved_critical_count", -1)) != 0:
        fail("FAIL: Phase 3 revision log has unresolved critical issues")
    if revision.get("final_verdict") != "PASS":
        fail(f"FAIL: Phase 3 revision log final_verdict must be PASS, got {revision.get('final_verdict')}")
    rounds = revision.get("revision_rounds")
    if not isinstance(rounds, list) or not rounds:
        fail("FAIL: Phase 3 revision log must include at least one revision round")
    bad_rounds = []
    for idx, round_item in enumerate(rounds):
        if not isinstance(round_item, dict):
            bad_rounds.append(f"revision_rounds[{idx}] is not an object")
            continue
        if "status" in round_item and round_item.get("status") not in ("resolved", "no_critical_revisions_required", "accepted_limitation"):
            bad_rounds.append(f"revision_rounds[{idx}].status={round_item.get('status')}")
        if not round_item.get("affected_files"):
            bad_rounds.append(f"revision_rounds[{idx}].affected_files missing")
    if bad_rounds:
        fail("FAIL: Phase 3 revision rounds are incomplete", bad_rounds)
    design_mtime = max(blueprint_path.stat().st_mtime, specs_path.stat().st_mtime, id_path.stat().st_mtime)
    if manifest_path.stat().st_mtime < design_mtime:
        fail("FAIL: Phase 3 design manifest is older than revised design artifacts")
    if evaluation_path.stat().st_mtime < design_mtime:
        fail("FAIL: Phase 3 design evaluation is older than revised design artifacts")
    if revision_path.stat().st_mtime < evaluation_path.stat().st_mtime:
        fail("FAIL: Phase 3 revision log is older than design evaluation")

if phase_id == "4":
    data_status_path = proj / "data" / "data-status.json"
    var_dict_path = proj / "data" / "variable-dictionary.csv"
    measurement_path = proj / "data" / "measurement-plan.md"
    data_manifest_path = proj / "data" / "data-measurement-manifest.json"
    safety_path = proj / "safety" / "safety-status.json"
    blueprint_path = proj / "design" / "design-blueprint.md"
    design_manifest_path = proj / "design" / "design-manifest.json"
    id_path = proj / "design" / "identification-strategy.json"
    specs_path = proj / "design" / "model-specs.json"
    placeholder_values = {"", "tbd", "todo", "unknown", "n/a", "na", "to be determined"}
    def norm_var(value):
        return re.sub(r"[^a-z0-9]+", " ", str(value).lower()).strip()
    try:
        data_status = json.loads(data_status_path.read_text())
        data_manifest = json.loads(data_manifest_path.read_text())
        safety = json.loads(safety_path.read_text())
        design_manifest = json.loads(design_manifest_path.read_text())
        ident = json.loads(id_path.read_text())
        specs = json.loads(specs_path.read_text())
    except Exception as exc:
        fail(f"FAIL: Phase 4 JSON input or output artifact is invalid: {exc}")
    if design_manifest.get("ready_for_phase_4") is not True:
        fail("FAIL: Phase 4 design manifest is not ready_for_phase_4")
    if int(safety.get("high_risk_unresolved", -1)) != 0:
        fail("FAIL: Phase 4 safety status has unresolved high-risk entries")
    required = ("data_status", "access_status", "irb_status", "source_type", "files", "dataset_fit")
    absent = [field for field in required if field not in data_status]
    if absent:
        fail("FAIL: Phase 4 data-status.json missing required fields", absent)
    allowed = {
        "data_status": {"existing-data", "collecting-new-data", "no-data"},
        "access_status": {"available", "restricted", "pending", "not-applicable"},
        "irb_status": {"exempt", "approved", "pending", "not-human-subjects", "not-applicable"},
    }
    bad_status = []
    for field, values in allowed.items():
        if data_status.get(field) not in values:
            bad_status.append(f"{field}={data_status.get(field)}")
    if bad_status:
        fail("FAIL: Phase 4 data-status values are invalid", bad_status)
    if not isinstance(data_status.get("files"), list):
        fail("FAIL: Phase 4 data-status files must be a list")
    if data_status["data_status"] == "existing-data" and not data_status["files"]:
        fail("FAIL: Phase 4 existing-data requires at least one file entry")
    if data_status["data_status"] != "no-data" and data_status["access_status"] == "not-applicable":
        fail("FAIL: Phase 4 access_status cannot be not-applicable for data projects")
    files = data_status.get("files")
    vague_files = []
    if data_status["data_status"] == "existing-data":
        if int(safety.get("files_scanned", 0)) <= 0:
            fail("FAIL: Phase 4 existing-data requires Phase 0 safety scan with files_scanned > 0")
        for idx, file_entry in enumerate(files):
            if not isinstance(file_entry, dict):
                vague_files.append(f"files[{idx}] must be object with path/source/provenance/safety_status")
                continue
            for field in ("path", "source", "provenance", "safety_status"):
                value = str(file_entry.get(field, "")).strip()
                if not value or value.lower() in placeholder_values:
                    vague_files.append(f"files[{idx}].{field}")
            if str(file_entry.get("safety_status", "")).strip() not in {"PASS", "PASS_LOCAL_MODE", "SAFE", "APPROVED", "OVERRIDE"}:
                vague_files.append(f"files[{idx}].safety_status invalid")
        if vague_files:
            fail("FAIL: Phase 4 existing-data files need concrete provenance and safety status", vague_files)
    dataset_fit = data_status.get("dataset_fit")
    if not isinstance(dataset_fit, dict):
        fail("FAIL: Phase 4 dataset_fit must be an object")
    fit_required = ("verdict", "unit_of_analysis", "population", "time_period", "key_variables_available", "sample_size_feasibility", "access_timeline")
    fit_issues = []
    for field in fit_required:
        if field not in dataset_fit:
            fit_issues.append(f"{field} missing")
    if dataset_fit.get("verdict") != "PASS":
        fit_issues.append(f"verdict={dataset_fit.get('verdict')}")
    if dataset_fit.get("key_variables_available") is not True:
        fit_issues.append("key_variables_available must be true")
    for field in ("unit_of_analysis", "population", "time_period", "sample_size_feasibility", "access_timeline"):
        value = str(dataset_fit.get(field, "")).strip().lower()
        if not value or value in placeholder_values:
            fit_issues.append(f"{field} placeholder")
    if fit_issues:
        fail("FAIL: Phase 4 dataset_fit is incomplete", fit_issues)
    try:
        with var_dict_path.open(newline="", encoding="utf-8") as f:
            rows = list(csv.DictReader(f))
    except Exception as exc:
        fail(f"FAIL: Phase 4 variable-dictionary.csv cannot be read: {exc}")
    required_columns = {
        "variable",
        "role",
        "construct",
        "display_label",
        "table_stub_label",
        "manuscript_term",
        "levels_display",
        "operationalization",
        "source",
        "missing_values",
        "design_source",
        "post_treatment",
        "measurement_quality",
    }
    fieldnames = set(rows[0].keys()) if rows else set()
    missing_columns = sorted(required_columns - fieldnames)
    if missing_columns:
        fail("FAIL: Phase 4 variable dictionary missing required columns", missing_columns)
    if not rows:
        fail("FAIL: Phase 4 variable dictionary has no rows")
    roles = {str(row.get("role", "")).strip().lower() for row in rows}
    missing_roles = [role for role in ("x", "y") if role not in roles]
    if missing_roles:
        fail("FAIL: Phase 4 variable dictionary must include x and y roles", missing_roles)
    bad_rows = []
    post_treatment_issues = []
    display_semantic_issues = []
    row_terms = set()
    for idx, row in enumerate(rows, start=2):
        for column in required_columns:
            value = str(row.get(column, "")).strip()
            if not value or value.lower() in placeholder_values:
                bad_rows.append(f"row {idx} {column}")
        variable_name = str(row.get("variable", "")).strip()
        display_label = str(row.get("display_label", "")).strip()
        table_stub_label = str(row.get("table_stub_label", "")).strip()
        manuscript_term = str(row.get("manuscript_term", "")).strip()
        post = str(row.get("post_treatment", "")).strip().lower()
        if post not in {"yes", "no"}:
            post_treatment_issues.append(f"row {idx} post_treatment must be yes/no")
        row_blob = " ".join(str(row.get(c, "")) for c in ("variable", "role", "construct", "operationalization", "design_source")).lower()
        if "post-treatment" in row_blob and post != "yes":
            post_treatment_issues.append(f"row {idx} mentions post-treatment but is not flagged yes")
        if looks_machine_like_label(variable_name):
            if norm_text(display_label) == norm_text(variable_name):
                display_semantic_issues.append(f"row {idx} display_label must translate machine-like variable {variable_name}")
            if norm_text(table_stub_label) == norm_text(variable_name):
                display_semantic_issues.append(f"row {idx} table_stub_label must translate machine-like variable {variable_name}")
            if norm_text(manuscript_term) == norm_text(variable_name):
                display_semantic_issues.append(f"row {idx} manuscript_term must translate machine-like variable {variable_name}")
        if word_count(str(row.get("levels_display", ""))) < 2:
            display_semantic_issues.append(f"row {idx} levels_display too thin")
        row_terms.add(norm_var(row.get("variable", "")))
        row_terms.add(norm_var(row.get("construct", "")))
    if bad_rows:
        fail("FAIL: Phase 4 variable dictionary contains blank or placeholder cells", bad_rows[:20])
    if post_treatment_issues:
        fail("FAIL: Phase 4 post-treatment flags are incomplete", post_treatment_issues[:20])
    if display_semantic_issues:
        fail("FAIL: Phase 4 variable dictionary display semantics are incomplete", display_semantic_issues[:20])
    required_design_measures = []
    measures = ident.get("measures")
    if not isinstance(measures, dict):
        fail("FAIL: Phase 4 identification-strategy measures must be an object")
    for key in ("x", "y"):
        measure = measures.get(key)
        if not isinstance(measure, dict):
            fail("FAIL: Phase 4 identification-strategy measures must include x and y")
        required_design_measures.append(str(measure.get("name", "")).strip())
    models = specs.get("models")
    if not isinstance(models, list) or not models:
        fail("FAIL: Phase 4 model-specs.json must include models")
    required_model_vars = set()
    for model in models:
        if not isinstance(model, dict):
            continue
        required_model_vars.add(str(model.get("outcome", "")).strip())
        for field in ("predictors", "covariates"):
            value = model.get(field)
            if isinstance(value, list):
                required_model_vars.update(str(item).strip() for item in value if str(item).strip())
    coverage = data_manifest.get("variable_coverage")
    if not isinstance(coverage, dict):
        fail("FAIL: Phase 4 data manifest variable_coverage must be an object")
    accepted_limitations = coverage.get("accepted_limitations", [])
    if accepted_limitations is None:
        accepted_limitations = []
    if not isinstance(accepted_limitations, list):
        fail("FAIL: Phase 4 variable_coverage accepted_limitations must be a list")
    accepted_missing = set()
    limitation_issues = []
    for idx, item in enumerate(accepted_limitations):
        if not isinstance(item, dict):
            limitation_issues.append(f"accepted_limitations[{idx}] is not an object")
            continue
        variable = norm_var(item.get("variable", ""))
        if not variable:
            limitation_issues.append(f"accepted_limitations[{idx}].variable missing")
        if word_count(str(item.get("rationale", ""))) < 8:
            limitation_issues.append(f"accepted_limitations[{idx}].rationale too thin")
        accepted_missing.add(variable)
    if limitation_issues:
        fail("FAIL: Phase 4 accepted variable limitations are incomplete", limitation_issues)
    missing_design = [
        name for name in required_design_measures
        if norm_var(name) not in row_terms and norm_var(name) not in accepted_missing
    ]
    if missing_design:
        fail("FAIL: Phase 4 variable dictionary missing Phase 3 design measures", missing_design)
    missing_model = [
        name for name in sorted(required_model_vars)
        if norm_var(name) not in row_terms and norm_var(name) not in accepted_missing
    ]
    if missing_model:
        fail("FAIL: Phase 4 variable dictionary missing model-spec variables", missing_model)
    manifest_design_coverage = {norm_var(item.get("name", "")): item for item in coverage.get("design_measures", []) if isinstance(item, dict)}
    manifest_model_coverage = {norm_var(item.get("name", "")): item for item in coverage.get("model_variables", []) if isinstance(item, dict)}
    manifest_coverage_issues = []
    for name in required_design_measures:
        item = manifest_design_coverage.get(norm_var(name))
        if not item or item.get("covered") is not True:
            manifest_coverage_issues.append(f"design measure {name}")
    for name in required_model_vars:
        item = manifest_model_coverage.get(norm_var(name))
        if not item or item.get("covered") is not True:
            manifest_coverage_issues.append(f"model variable {name}")
    if manifest_coverage_issues:
        fail("FAIL: Phase 4 data manifest variable coverage is incomplete", manifest_coverage_issues[:20])
    measurement_text = measurement_path.read_text(errors="ignore").lower()
    required_terms = {
        "validity": "measurement validity",
        "missing": "missing data handling",
        "sample": "sample restrictions",
        "access": "access implications",
        "irb": "IRB implications",
        "provenance": "data provenance",
        "security": "data security",
        "sharing": "data sharing constraints",
        "dataset": "dataset fit",
        "variable": "variable coverage",
        "post-treatment": "post-treatment review",
    }
    missing_terms = [label for term, label in required_terms.items() if term not in measurement_text]
    if missing_terms:
        fail("FAIL: Phase 4 measurement-plan.md missing required discussion", missing_terms)
    measurement_words = re.findall(r"\b\w+\b", measurement_path.read_text(errors="ignore"))
    if len(measurement_words) < 300:
        fail(f"FAIL: Phase 4 measurement-plan.md is too short, found {len(measurement_words)} words")
    if data_status["data_status"] == "existing-data":
        codebook_validation = data_manifest.get("codebook_validation")
        codebook_issues = []
        if not isinstance(codebook_validation, dict):
            codebook_issues.append("codebook_validation missing")
        else:
            if codebook_validation.get("reviewed") is not True:
                codebook_issues.append("reviewed must be true")
            for field in (
                "value_labels_checked",
                "valid_ranges_checked",
                "missing_codes_checked",
                "skip_logic_checked",
                "measurement_units_checked",
            ):
                rationale = str(codebook_validation.get(f"{field}_unavailable_rationale", "") or codebook_validation.get("unavailable_rationale", "")).strip()
                if codebook_validation.get(field) is not True and word_count(rationale) < 8:
                    codebook_issues.append(f"{field} must be true or have unavailable rationale")
        if codebook_issues:
            fail("FAIL: Phase 4 codebook validation is incomplete", codebook_issues)
    structured_data_needed = structured_secondary_data_indicated(data_status, ident, specs, measurement_text)
    if structured_data_needed:
        design_review = data_status.get("dataset_design_review")
        design_review_issues = []
        if not isinstance(design_review, dict):
            design_review_issues.append("data-status.dataset_design_review missing")
        else:
            if design_review.get("reviewed") is not True:
                design_review_issues.append("reviewed must be true")
            if word_count(str(design_review.get("analytic_decision", ""))) < 6:
                design_review_issues.append("analytic_decision must explain the modeling decision")
            if not any(truthy_review_field(design_review, field) for field in (
                "weights_reviewed",
                "design_variables_reviewed",
                "clustering_reviewed",
                "strata_reviewed",
                "sampling_frame_reviewed",
                "panel_structure_reviewed",
                "denominator_rules_reviewed",
            )):
                design_review_issues.append("at least one dataset-design component must be explicitly reviewed")
            decision = str(design_review.get("analytic_decision", "")).lower()
            if re.search(r"\b(unweighted|ignore|ignored|simplified|not use|not used|flat file)\b", decision):
                limitations = design_review.get("accepted_limitations")
                rationale = str(design_review.get("limitation_rationale", "")).strip()
                if not isinstance(limitations, list) or not limitations:
                    if word_count(rationale) < 10:
                        design_review_issues.append("simplified/unweighted decisions require accepted_limitations or substantive limitation_rationale")
            if not re.search(r"\b(weight|cluster|strata|sampling|sample design|panel|denominator|survey design)\b", measurement_text):
                design_review_issues.append("measurement-plan.md must discuss the dataset-design decision")
        if data_manifest.get("dataset_design_review") != design_review:
            design_review_issues.append("data-measurement-manifest.dataset_design_review must match data-status.json")
        if design_review_issues:
            fail("FAIL: Phase 4 dataset-design review is incomplete", design_review_issues)
    if complex_outcome_family_indicated(rows, specs, measurement_text):
        outcome_screen = data_manifest.get("outcome_family_screen")
        outcome_screen_issues = []
        if not isinstance(outcome_screen, dict):
            outcome_screen_issues.append("outcome_family_screen missing")
        else:
            if outcome_screen.get("screened") is not True:
                outcome_screen_issues.append("screened must be true")
            families = outcome_screen.get("outcome_families")
            if not isinstance(families, list) or not families:
                outcome_screen_issues.append("outcome_families must be a nonempty list")
            if word_count(str(outcome_screen.get("phase5_implication", ""))) < 8:
                outcome_screen_issues.append("phase5_implication must explain modeling implications")
        if not re.search(r"\b(hour|time use|duration|bounded|skew|zero|count|top[- ]code|outcome family)\b", measurement_text):
            outcome_screen_issues.append("measurement-plan.md must discuss the outcome family")
        if outcome_screen_issues:
            fail("FAIL: Phase 4 outcome-family screen is incomplete", outcome_screen_issues)
    if data_manifest.get("verdict") != "PASS" or data_manifest.get("source_phase") != "4" or data_manifest.get("ready_for_phase_5") is not True:
        fail("FAIL: Phase 4 data manifest must PASS with source_phase 4 and ready_for_phase_5 true")
    data_engine = data_manifest.get("data_engine")
    if not isinstance(data_engine, dict) or data_engine.get("skill") != "scholar-data":
        fail("FAIL: Phase 4 data manifest must record scholar-data as data_engine")
    data_engine_issues = validate_engine_provenance(data_engine, "Phase 4 data_engine")
    if data_engine_issues:
        fail("FAIL: Phase 4 data_engine provenance is incomplete", data_engine_issues)
    if data_manifest.get("dataset_fit") != dataset_fit:
        fail("FAIL: Phase 4 data manifest dataset_fit must match data-status.json")
    display_semantics = data_manifest.get("display_semantics")
    if not isinstance(display_semantics, dict):
        fail("FAIL: Phase 4 data manifest display_semantics must be an object")
    if display_semantics.get("reader_facing_labels_complete") is not True:
        fail("FAIL: Phase 4 display_semantics must confirm reader_facing_labels_complete")
    if display_semantics.get("machine_labels_eliminated") is not True:
        fail("FAIL: Phase 4 display_semantics must confirm machine_labels_eliminated")
    if display_semantics.get("ready_for_tables") is not True:
        fail("FAIL: Phase 4 display_semantics must confirm ready_for_tables")
    try:
        machine_like_count = int(display_semantics.get("machine_like_variable_count", -1))
    except Exception:
        fail("FAIL: Phase 4 display_semantics.machine_like_variable_count must be numeric")
    actual_machine_like_count = sum(1 for row in rows if looks_machine_like_label(row.get("variable", "")))
    if machine_like_count != actual_machine_like_count:
        fail("FAIL: Phase 4 display_semantics.machine_like_variable_count mismatch")
    if str(display_semantics.get("label_source", "")).strip() != "data/variable-dictionary.csv":
        fail("FAIL: Phase 4 display_semantics.label_source must be data/variable-dictionary.csv")
    safety_provenance = data_manifest.get("safety_provenance")
    if not isinstance(safety_provenance, dict):
        fail("FAIL: Phase 4 data manifest safety_provenance must be an object")
    if int(safety_provenance.get("files_scanned", -1)) != int(safety.get("files_scanned", -2)):
        fail("FAIL: Phase 4 safety_provenance files_scanned must match safety status")
    if int(safety_provenance.get("high_risk_unresolved", -1)) != int(safety.get("high_risk_unresolved", -2)):
        fail("FAIL: Phase 4 safety_provenance high_risk_unresolved must match safety status")
    post_review = data_manifest.get("post_treatment_review")
    if not isinstance(post_review, dict) or post_review.get("reviewed") is not True or int(post_review.get("unresolved_count", -1)) != 0:
        fail("FAIL: Phase 4 post_treatment_review must be reviewed with unresolved_count 0")
    expected_source_hashes = {
        "safety_status": sha256(safety_path),
        "design_blueprint": sha256(blueprint_path),
        "design_manifest": sha256(design_manifest_path),
        "identification_strategy": sha256(id_path),
        "model_specs": sha256(specs_path),
    }
    source_hashes = data_manifest.get("source_hashes")
    if not isinstance(source_hashes, dict):
        fail("FAIL: Phase 4 data manifest source_hashes must be an object")
    stale_sources = [
        f"{key} mismatch"
        for key, expected in expected_source_hashes.items()
        if source_hashes.get(key) != expected
    ]
    if stale_sources:
        fail("FAIL: Phase 4 data manifest source_hashes are stale", stale_sources)
    expected_output_hashes = {
        "data_status": sha256(data_status_path),
        "variable_dictionary": sha256(var_dict_path),
        "measurement_plan": sha256(measurement_path),
    }
    output_hashes = data_manifest.get("output_hashes")
    if not isinstance(output_hashes, dict):
        fail("FAIL: Phase 4 data manifest output_hashes must be an object")
    stale_outputs = [
        f"{key} mismatch"
        for key, expected in expected_output_hashes.items()
        if output_hashes.get(key) != expected
    ]
    if stale_outputs:
        fail("FAIL: Phase 4 data manifest output_hashes are stale", stale_outputs)

if phase_id == "5":
    plan_path = proj / "analysis" / "analysis-plan.md"
    spec_path = proj / "analysis" / "spec-registry.csv"
    inventory_path = proj / "analysis" / "scripts-inventory.json"
    plan_manifest_path = proj / "analysis" / "analysis-plan-manifest.json"
    design_manifest_path = proj / "design" / "design-manifest.json"
    id_path = proj / "design" / "identification-strategy.json"
    model_specs_path = proj / "design" / "model-specs.json"
    data_status_path = proj / "data" / "data-status.json"
    var_dict_path = proj / "data" / "variable-dictionary.csv"
    data_manifest_path = proj / "data" / "data-measurement-manifest.json"
    measurement_path = proj / "data" / "measurement-plan.md"
    placeholder_values = {"", "tbd", "todo", "unknown", "n/a", "na", "to be determined"}
    # Design-aware Layer 1 (added 2026-05-11): resolve primary_execution_skill via
    # shared helper at scripts/gates/_phase5-skill-resolver.sh. Helper emits
    # COVARIATES_OPTIONAL=true|false. For non-regression method families
    # (scholar-compute / scholar-qual / scholar-ling), the `covariates` column
    # may be legitimately empty. All other required columns stay universal.
    # Safe default: any failure path → covariates_optional=False (strict).
    covariates_optional = False
    _resolver = SCRIPT_DIR / "gates" / "_phase5-skill-resolver.sh"
    if _resolver.exists():
        try:
            _r = subprocess.run(
                ["bash", str(_resolver), str(proj)],
                capture_output=True, text=True, timeout=10,
            )
            for _line in (_r.stdout or "").splitlines():
                if _line.startswith("COVARIATES_OPTIONAL="):
                    covariates_optional = (_line.split("=", 1)[1].strip() == "true")
                    break
        except Exception:
            covariates_optional = False
    def norm_var(value):
        return re.sub(r"[^a-z0-9]+", " ", str(value).lower()).strip()
    def split_values(value):
        if isinstance(value, list):
            return [str(v).strip() for v in value if str(v).strip()]
        text = str(value or "").strip()
        if not text:
            return []
        if text.startswith("["):
            try:
                parsed = json.loads(text)
                if isinstance(parsed, list):
                    return [str(v).strip() for v in parsed if str(v).strip()]
            except Exception:
                pass
        return [part.strip() for part in re.split(r"\s*[;|]\s*", text) if part.strip()]
    forbidden_outputs = [
        "analysis/execution-report.json",
        "tables/results-registry.csv",
        "figures/figure-registry.csv",
    ]
    present_forbidden = [rel for rel in forbidden_outputs if (proj / rel).exists()]
    if present_forbidden:
        fail("FAIL: Phase 5 must not contain execution/result artifacts before Phase 8", present_forbidden)
    try:
        plan_manifest = json.loads(plan_manifest_path.read_text())
        design_manifest = json.loads(design_manifest_path.read_text())
        ident = json.loads(id_path.read_text())
        model_specs = json.loads(model_specs_path.read_text())
        data_status = json.loads(data_status_path.read_text())
        data_manifest = json.loads(data_manifest_path.read_text())
    except Exception as exc:
        fail(f"FAIL: Phase 5 JSON input or manifest artifact is invalid: {exc}")
    if design_manifest.get("ready_for_phase_4") is not True:
        fail("FAIL: Phase 5 design manifest is not ready_for_phase_4")
    if data_manifest.get("ready_for_phase_5") is not True:
        fail("FAIL: Phase 5 data-measurement manifest is not ready_for_phase_5")
    try:
        with spec_path.open(newline="", encoding="utf-8") as f:
            specs = list(csv.DictReader(f))
    except Exception as exc:
        fail(f"FAIL: Phase 5 spec-registry.csv cannot be read: {exc}")
    required_columns = {
        "spec_id",
        "model_id",
        "hypothesis_ids",
        "outcome",
        "predictors",
        "covariates",
        "estimator",
        "purpose",
        "robustness_type",
        "missing_data_strategy",
        "status",
    }
    fieldnames = set(specs[0].keys()) if specs else set()
    missing_columns = sorted(required_columns - fieldnames)
    if missing_columns:
        fail("FAIL: Phase 5 spec registry missing required columns", missing_columns)
    if not specs:
        fail("FAIL: Phase 5 spec registry has no planned specs")
    try:
        with var_dict_path.open(newline="", encoding="utf-8") as f:
            var_rows = list(csv.DictReader(f))
    except Exception as exc:
        fail(f"FAIL: Phase 5 variable-dictionary.csv cannot be read: {exc}")
    var_terms = set()
    for row in var_rows:
        var_terms.add(norm_var(row.get("variable", "")))
        var_terms.add(norm_var(row.get("construct", "")))
    models = model_specs.get("models")
    if not isinstance(models, list) or not models:
        fail("FAIL: Phase 5 model-specs.json must include models")
    model_ids = {str(model.get("id", "")).strip() for model in models if isinstance(model, dict) and str(model.get("id", "")).strip()}
    model_hypotheses = set()
    for model in models:
        if isinstance(model, dict):
            model_hypotheses.update(str(h).strip() for h in model.get("hypothesis_ids", []) if str(h).strip())
    bad_specs = []
    spec_ids = set()
    spec_model_ids = set()
    spec_hypothesis_ids = set()
    spec_variables = set()
    for idx, row in enumerate(specs, start=2):
        for column in required_columns:
            # Design-aware: covariates may be legitimately empty for
            # scholar-compute / scholar-qual / scholar-ling families
            # (resolved at the top of this block). Layer 2 (control-
            # variables-check.sh) enforces design-specific contracts.
            if column == "covariates" and covariates_optional:
                continue
            value = str(row.get(column, "")).strip()
            if not value or value.lower() in placeholder_values:
                bad_specs.append(f"row {idx} {column}")
        if str(row.get("status", "")).strip().lower() != "planned":
            bad_specs.append(f"row {idx} status must be planned")
        spec_id = str(row.get("spec_id", "")).strip()
        model_id = str(row.get("model_id", "")).strip()
        if spec_id in spec_ids:
            bad_specs.append(f"row {idx} duplicate spec_id {spec_id}")
        spec_ids.add(spec_id)
        if model_id not in model_ids:
            bad_specs.append(f"row {idx} model_id not found in design/model-specs.json: {model_id}")
        spec_model_ids.add(model_id)
        hids = split_values(row.get("hypothesis_ids"))
        if not hids:
            bad_specs.append(f"row {idx} hypothesis_ids must be non-empty")
        for hid in hids:
            if hid not in model_hypotheses:
                bad_specs.append(f"row {idx} unknown hypothesis_id {hid}")
            spec_hypothesis_ids.add(hid)
        variables = [row.get("outcome", "")]
        variables.extend(split_values(row.get("predictors")))
        variables.extend(split_values(row.get("covariates")))
        for var in variables:
            nvar = norm_var(var)
            if nvar and nvar not in var_terms:
                bad_specs.append(f"row {idx} variable not in Phase 4 dictionary: {var}")
            if nvar:
                spec_variables.add(nvar)
    if bad_specs:
        fail("FAIL: Phase 5 spec registry contains incomplete or non-planned specs", bad_specs[:20])
    missing_model_specs = sorted(model_ids - spec_model_ids)
    if missing_model_specs:
        fail("FAIL: Phase 5 spec registry does not cover every Phase 3 model", missing_model_specs)
    missing_hypotheses = sorted(model_hypotheses - spec_hypothesis_ids)
    if missing_hypotheses:
        fail("FAIL: Phase 5 spec registry does not cover every Phase 3 hypothesis", missing_hypotheses)
    try:
        inventory = json.loads(inventory_path.read_text())
    except Exception as exc:
        fail(f"FAIL: Phase 5 scripts-inventory.json is not valid JSON: {exc}")
    if inventory.get("no_execution_yet") is not True:
        fail("FAIL: Phase 5 scripts-inventory.json must set no_execution_yet=true")
    scripts = inventory.get("scripts")
    if not isinstance(scripts, list) or not scripts:
        fail("FAIL: Phase 5 scripts-inventory.json must include non-empty scripts list")
    bad_scripts = []
    script_paths = []
    for idx, script in enumerate(scripts):
        if not isinstance(script, dict):
            bad_scripts.append(f"scripts[{idx}] is not an object")
            continue
        for field in ("path", "purpose", "uses", "produces", "status"):
            value = script.get(field)
            if not value:
                bad_scripts.append(f"scripts[{idx}].{field} missing")
        if script.get("status") != "planned":
            bad_scripts.append(f"scripts[{idx}].status must be planned")
        if script.get("executed") is True:
            bad_scripts.append(f"scripts[{idx}].executed must not be true in Phase 5")
        if "uses" in script and not isinstance(script.get("uses"), list):
            bad_scripts.append(f"scripts[{idx}].uses must be list")
        if "produces" in script and not isinstance(script.get("produces"), list):
            bad_scripts.append(f"scripts[{idx}].produces must be list")
        path_value = str(script.get("path", "")).strip()
        if path_value:
            script_paths.append(path_value)
    if bad_scripts:
        fail("FAIL: Phase 5 script inventory is incomplete", bad_scripts)
    if len(script_paths) != len(set(script_paths)):
        fail("FAIL: Phase 5 script inventory has duplicate script paths")
    script_order = inventory.get("script_order")
    dependency_graph = inventory.get("dependency_graph")
    if not isinstance(script_order, list) or not script_order:
        fail("FAIL: Phase 5 scripts-inventory.json must include non-empty script_order")
    if set(script_order) != set(script_paths):
        fail("FAIL: Phase 5 script_order must list exactly the planned scripts")
    if not isinstance(dependency_graph, dict):
        fail("FAIL: Phase 5 scripts-inventory.json must include dependency_graph object")
    order_index = {path: idx for idx, path in enumerate(script_order)}
    dag_issues = []
    for path in script_paths:
        deps = dependency_graph.get(path)
        if deps is None:
            dag_issues.append(f"{path} missing from dependency_graph")
            continue
        if not isinstance(deps, list):
            dag_issues.append(f"{path} dependencies must be list")
            continue
        for dep in deps:
            if dep not in order_index:
                dag_issues.append(f"{path} depends on unknown script {dep}")
            elif order_index[dep] >= order_index[path]:
                dag_issues.append(f"{path} depends on later script {dep}")
    if dag_issues:
        fail("FAIL: Phase 5 script dependency graph is invalid", dag_issues)
    tests = inventory.get("test_inventory")
    if not isinstance(tests, list) or not tests:
        fail("FAIL: Phase 5 scripts-inventory.json must include non-empty test_inventory")
    bad_tests = []
    required_test_categories = {"data_loading", "analytic_sample", "variable_construction", "missingness", "model_spec", "output_registry"}
    test_categories = set()
    spec_test_coverage = set()
    for idx, test in enumerate(tests):
        if not isinstance(test, dict):
            bad_tests.append(f"test_inventory[{idx}] is not an object")
            continue
        for field in ("id", "target", "assertion", "category"):
            if not test.get(field):
                bad_tests.append(f"test_inventory[{idx}].{field} missing")
        category = str(test.get("category", "")).strip()
        test_categories.add(category)
        target = str(test.get("target", "")).strip()
        if target and target not in set(script_paths) and target != "all":
            bad_tests.append(f"test_inventory[{idx}].target unknown script {target}")
        if category == "model_spec":
            spec_ids_for_test = test.get("spec_ids")
            if not isinstance(spec_ids_for_test, list) or not spec_ids_for_test:
                bad_tests.append(f"test_inventory[{idx}].spec_ids missing for model_spec test")
            else:
                for spec_id in spec_ids_for_test:
                    if str(spec_id) not in spec_ids:
                        bad_tests.append(f"test_inventory[{idx}] unknown spec_id {spec_id}")
                    spec_test_coverage.add(str(spec_id))
        if test.get("status") and test.get("status") != "planned":
            bad_tests.append(f"test_inventory[{idx}].status must be planned")
    missing_test_categories = sorted(required_test_categories - test_categories)
    if missing_test_categories:
        bad_tests.extend(f"missing test category {category}" for category in missing_test_categories)
    missing_spec_tests = sorted(spec_ids - spec_test_coverage)
    if missing_spec_tests:
        bad_tests.extend(f"missing model_spec test for {spec_id}" for spec_id in missing_spec_tests)
    if bad_tests:
        fail("FAIL: Phase 5 test inventory is incomplete", bad_tests)
    plan_text = plan_path.read_text(errors="ignore").lower()
    required_terms = {
        "model": "model plan",
        "hypothesis": "hypothesis/spec mapping",
        "robustness": "robustness plan",
        "missing": "missing data plan",
        "variable": "variable-construction plan",
        "script": "script inventory",
        "test": "test plan",
        "no execution": "no-execution boundary",
        "pre-execution": "pre-execution review handoff",
    }
    missing_terms = [label for term, label in required_terms.items() if term not in plan_text]
    if missing_terms:
        fail("FAIL: Phase 5 analysis-plan.md missing required discussion", missing_terms)
    plan_words = re.findall(r"\b\w+\b", plan_path.read_text(errors="ignore"))
    if len(plan_words) < 350:
        fail(f"FAIL: Phase 5 analysis-plan.md is too short, found {len(plan_words)} words")
    if plan_manifest.get("verdict") != "PASS" or plan_manifest.get("source_phase") != "5" or plan_manifest.get("ready_for_phase_6") is not True:
        fail("FAIL: Phase 5 analysis-plan manifest must PASS with source_phase 5 and ready_for_phase_6 true")
    engine = plan_manifest.get("analysis_planning_engine")
    if (
        not isinstance(engine, dict)
        or engine.get("skill") != "scholar-auto-research"
        or engine.get("mode") != "analysis_plan_compiler"
    ):
        fail("FAIL: Phase 5 analysis-plan manifest must record scholar-auto-research analysis_plan_compiler as analysis_planning_engine")
    expected_source_hashes = {
        "design_manifest": sha256(design_manifest_path),
        "identification_strategy": sha256(id_path),
        "model_specs": sha256(model_specs_path),
        "data_status": sha256(data_status_path),
        "variable_dictionary": sha256(var_dict_path),
        "data_measurement_manifest": sha256(data_manifest_path),
        "measurement_plan": sha256(measurement_path),
    }
    source_hashes = plan_manifest.get("source_hashes")
    if not isinstance(source_hashes, dict):
        fail("FAIL: Phase 5 analysis-plan manifest source_hashes must be an object")
    stale_sources = [
        f"{key} mismatch"
        for key, expected in expected_source_hashes.items()
        if source_hashes.get(key) != expected
    ]
    if stale_sources:
        fail("FAIL: Phase 5 analysis-plan manifest source_hashes are stale", stale_sources)
    expected_output_hashes = {
        "analysis_plan": sha256(plan_path),
        "spec_registry": sha256(spec_path),
        "scripts_inventory": sha256(inventory_path),
    }
    output_hashes = plan_manifest.get("output_hashes")
    if not isinstance(output_hashes, dict):
        fail("FAIL: Phase 5 analysis-plan manifest output_hashes must be an object")
    stale_outputs = [
        f"{key} mismatch"
        for key, expected in expected_output_hashes.items()
        if output_hashes.get(key) != expected
    ]
    if stale_outputs:
        fail("FAIL: Phase 5 analysis-plan manifest output_hashes are stale", stale_outputs)
    model_coverage = plan_manifest.get("model_spec_coverage")
    if not isinstance(model_coverage, list):
        fail("FAIL: Phase 5 model_spec_coverage must be a list")
    coverage_issues = []
    manifest_model_ids = set()
    for idx, item in enumerate(model_coverage):
        if not isinstance(item, dict):
            coverage_issues.append(f"model_spec_coverage[{idx}] is not object")
            continue
        mid = str(item.get("model_id", "")).strip()
        manifest_model_ids.add(mid)
        ids = item.get("spec_ids")
        if mid not in model_ids:
            coverage_issues.append(f"unknown model_id {mid}")
        if item.get("covered") is not True:
            coverage_issues.append(f"{mid} not marked covered")
        if not isinstance(ids, list) or not ids or any(str(spec_id) not in spec_ids for spec_id in ids):
            coverage_issues.append(f"{mid} has invalid spec_ids")
    coverage_issues.extend(f"missing model coverage {mid}" for mid in sorted(model_ids - manifest_model_ids))
    hypothesis_coverage = plan_manifest.get("hypothesis_spec_coverage")
    if not isinstance(hypothesis_coverage, list):
        fail("FAIL: Phase 5 hypothesis_spec_coverage must be a list")
    manifest_hypotheses = set()
    for idx, item in enumerate(hypothesis_coverage):
        if not isinstance(item, dict):
            coverage_issues.append(f"hypothesis_spec_coverage[{idx}] is not object")
            continue
        hid = str(item.get("hypothesis_id", "")).strip()
        manifest_hypotheses.add(hid)
        ids = item.get("spec_ids")
        if hid not in model_hypotheses:
            coverage_issues.append(f"unknown hypothesis_id {hid}")
        if item.get("covered") is not True:
            coverage_issues.append(f"{hid} not marked covered")
        if not isinstance(ids, list) or not ids or any(str(spec_id) not in spec_ids for spec_id in ids):
            coverage_issues.append(f"{hid} has invalid spec_ids")
    coverage_issues.extend(f"missing hypothesis coverage {hid}" for hid in sorted(model_hypotheses - manifest_hypotheses))
    variable_coverage = plan_manifest.get("variable_coverage")
    if not isinstance(variable_coverage, list):
        fail("FAIL: Phase 5 variable_coverage must be a list")
    manifest_variables = set()
    for idx, item in enumerate(variable_coverage):
        if not isinstance(item, dict):
            coverage_issues.append(f"variable_coverage[{idx}] is not object")
            continue
        variable = norm_var(item.get("name", ""))
        manifest_variables.add(variable)
        if item.get("covered") is not True:
            coverage_issues.append(f"variable {item.get('name')} not marked covered")
        if variable not in var_terms:
            coverage_issues.append(f"variable {item.get('name')} not found in Phase 4 dictionary")
    coverage_issues.extend(f"missing variable coverage {var}" for var in sorted(spec_variables - manifest_variables))
    if coverage_issues:
        fail("FAIL: Phase 5 manifest coverage is incomplete", coverage_issues[:30])
    robustness_plan = [str(item).strip() for item in ident.get("robustness_plan", []) if str(item).strip()]
    robustness_coverage = plan_manifest.get("robustness_coverage")
    if not isinstance(robustness_coverage, list):
        fail("FAIL: Phase 5 robustness_coverage must be a list")
    robustness_seen = set()
    robustness_issues = []
    for idx, item in enumerate(robustness_coverage):
        if not isinstance(item, dict):
            robustness_issues.append(f"robustness_coverage[{idx}] is not object")
            continue
        design_item = str(item.get("design_item", "")).strip()
        robustness_seen.add(design_item)
        if design_item not in robustness_plan:
            robustness_issues.append(f"unknown robustness item {design_item}")
        if item.get("accepted_limitation") is True:
            if word_count(str(item.get("rationale", ""))) < 8:
                robustness_issues.append(f"{design_item} accepted limitation rationale too thin")
            continue
        ids = item.get("spec_ids")
        if item.get("covered") is not True:
            robustness_issues.append(f"{design_item} not marked covered")
        if not isinstance(ids, list) or not ids or any(str(spec_id) not in spec_ids for spec_id in ids):
            robustness_issues.append(f"{design_item} has invalid spec_ids")
    robustness_issues.extend(f"missing robustness coverage {item}" for item in robustness_plan if item not in robustness_seen)
    if robustness_issues:
        fail("FAIL: Phase 5 robustness coverage is incomplete", robustness_issues)
    missing_alignment = plan_manifest.get("missing_data_alignment")
    if not isinstance(missing_alignment, dict) or missing_alignment.get("strategy_matches_phase4") is not True:
        fail("FAIL: Phase 5 missing_data_alignment must state strategy_matches_phase4 true")
    if missing_alignment.get("variable_dictionary_hash") != sha256(var_dict_path):
        fail("FAIL: Phase 5 missing_data_alignment variable_dictionary_hash is stale")
    measurement_text = measurement_path.read_text(errors="ignore").lower()
    structured_data_needed = structured_secondary_data_indicated(data_status, data_manifest, ident, model_specs, measurement_text, plan_text)
    if structured_data_needed:
        design_plan = plan_manifest.get("dataset_design_plan")
        design_plan_issues = []
        if not isinstance(design_plan, dict):
            design_plan_issues.append("dataset_design_plan missing")
        else:
            if design_plan.get("reviewed") is not True:
                design_plan_issues.append("reviewed must be true")
            if word_count(str(design_plan.get("analytic_decision", ""))) < 6:
                design_plan_issues.append("analytic_decision must explain weights/design/clustering/panel choice")
            if word_count(str(design_plan.get("decision_rationale", ""))) < 8:
                design_plan_issues.append("decision_rationale too thin")
            if not any(truthy_review_field(design_plan, field) for field in (
                "weights_considered",
                "design_variables_considered",
                "clustering_considered",
                "strata_considered",
                "panel_structure_considered",
                "denominator_rules_considered",
            )):
                design_plan_issues.append("at least one dataset-design component must be considered")
            decision = str(design_plan.get("analytic_decision", "")).lower()
            if re.search(r"\b(unweighted|ignore|ignored|simplified|not use|not used|flat file)\b", decision):
                limitations = design_plan.get("accepted_limitations")
                if not isinstance(limitations, list) or not limitations:
                    design_plan_issues.append("simplified/unweighted plans require accepted_limitations")
            phase4_review = data_manifest.get("dataset_design_review")
            if isinstance(phase4_review, dict):
                phase4_decision = norm_text(phase4_review.get("analytic_decision", ""))
                if phase4_decision and keyword_overlap_count(phase4_decision, design_plan.get("analytic_decision", "")) < 2:
                    design_plan_issues.append("dataset_design_plan analytic_decision does not inherit Phase 4 design review")
        if not re.search(r"\b(weight|cluster|strata|sampling|sample design|panel|denominator|survey design)\b", plan_text):
            design_plan_issues.append("analysis-plan.md must discuss the dataset-design modeling decision")
        if design_plan_issues:
            fail("FAIL: Phase 5 dataset-design plan is incomplete", design_plan_issues)
    if complex_outcome_family_indicated(var_rows, model_specs, measurement_text):
        ladder = plan_manifest.get("outcome_model_ladder")
        ladder_issues = []
        if not isinstance(ladder, dict):
            ladder_issues.append("outcome_model_ladder missing")
        else:
            if not str(ladder.get("outcome_family", "")).strip():
                ladder_issues.append("outcome_family missing")
            if not str(ladder.get("headline_estimator", "")).strip():
                ladder_issues.append("headline_estimator missing")
            sensitivity_specs = ladder.get("sensitivity_specs")
            if not isinstance(sensitivity_specs, list) or not sensitivity_specs:
                ladder_issues.append("sensitivity_specs must be a nonempty list")
            else:
                known_spec_ids = {str(row.get("spec_id", "")).strip() for row in specs}
                for item in sensitivity_specs:
                    if isinstance(item, dict):
                        sid = str(item.get("spec_id", "")).strip()
                        rationale = str(item.get("rationale", "")).strip()
                    else:
                        sid = str(item).strip()
                        rationale = ""
                    if sid and sid not in known_spec_ids:
                        ladder_issues.append(f"sensitivity spec {sid} not found in spec-registry.csv")
                    if isinstance(item, dict) and word_count(rationale) < 6:
                        ladder_issues.append(f"sensitivity spec {sid or '<blank>'} rationale too thin")
            if not any(truthy_review_field(ladder, field) for field in (
                "distributional_diagnostics_planned",
                "skewness_checked",
                "zero_mass_checked",
                "top_code_checked",
                "bounded_scale_checked",
            )):
                ladder_issues.append("outcome diagnostics must be planned")
        robustness_blob = " ".join(str(row.get("robustness_type", "")) + " " + str(row.get("estimator", "")) for row in specs)
        if not re.search(r"\b(log|two[-_ ]part|positive|glm|gamma|poisson|negative binomial|quantile|top[-_ ]code|bounded|fractional|robustness)\b", robustness_blob, re.IGNORECASE):
            ladder_issues.append("spec-registry.csv needs at least one outcome-family sensitivity specification")
        if ladder_issues:
            fail("FAIL: Phase 5 outcome model ladder is incomplete", ladder_issues)
    missingness_needed = bool(re.search(
        r"\b(missing|complete[- ]case|listwise|casewise|skip|inapplicable|denominator|nonresponse|special code)\b",
        json_blob(measurement_text, plan_text, specs, missing_alignment),
    ))
    if missingness_needed:
        missing_plan = plan_manifest.get("missingness_sensitivity_plan")
        missing_plan_issues = []
        if not isinstance(missing_plan, dict):
            missing_plan_issues.append("missingness_sensitivity_plan missing")
        else:
            for field in ("post_restriction_diagnostics", "denominator_checks", "skip_vs_missing_reviewed"):
                if missing_plan.get(field) is not True:
                    missing_plan_issues.append(f"{field} must be true")
            sensitivity_specs = missing_plan.get("sensitivity_specs")
            accepted_limitations = missing_plan.get("accepted_limitations")
            if not isinstance(sensitivity_specs, list) or not sensitivity_specs:
                if not isinstance(accepted_limitations, list) or not accepted_limitations:
                    missing_plan_issues.append("requires sensitivity_specs or accepted_limitations")
            if word_count(str(missing_plan.get("rationale", ""))) < 8:
                missing_plan_issues.append("rationale too thin")
        if not re.search(r"\b(post[- ]restriction|denominator|skip|complete[- ]case|sensitivity|missingness)\b", plan_text):
            missing_plan_issues.append("analysis-plan.md must discuss post-restriction missingness and sensitivity")
        if missing_plan_issues:
            fail("FAIL: Phase 5 missingness sensitivity plan is incomplete", missing_plan_issues)
    script_dag = plan_manifest.get("script_dag")
    if not isinstance(script_dag, dict) or script_dag.get("valid") is not True or script_dag.get("script_order") != script_order:
        fail("FAIL: Phase 5 script_dag manifest entry is invalid")
    test_coverage = plan_manifest.get("test_coverage")
    if not isinstance(test_coverage, dict):
        fail("FAIL: Phase 5 test_coverage must be an object")
    manifest_categories = set(test_coverage.get("categories", [])) if isinstance(test_coverage.get("categories"), list) else set()
    if not required_test_categories.issubset(manifest_categories):
        fail("FAIL: Phase 5 test_coverage categories are incomplete")
    manifest_tested_specs = set(str(spec_id) for spec_id in test_coverage.get("spec_ids", [])) if isinstance(test_coverage.get("spec_ids"), list) else set()
    if spec_ids - manifest_tested_specs:
        fail("FAIL: Phase 5 test_coverage missing spec_ids", sorted(spec_ids - manifest_tested_specs))
    # Control-variable enforcement gate (added 2026-05-11):
    # For regression/observational designs, at least one planned spec must
    # have non-empty `covariates`. ML / qualitative / decomposition designs
    # are N/A. RCT designs require BOTH unadjusted + covariate-adjusted rungs.
    # observational-causal-with-DAG requires controls drawn from the DAG
    # adjustment_set. Opt out per-phase with [EXCUSED:control-variables: <reason>]
    # in analysis/analysis-plan.md.
    cv_external_gate_failures = []
    cv_gate_result = run_external_gate(
        "control-variables-check.sh", proj, "Phase 5 control-variables gate"
    )
    if cv_gate_result is not None:
        cv_status, cv_reason, cv_detail = cv_gate_result
        if cv_status == "RED":
            cv_external_gate_failures.append(
                f"Phase 5 control-variables gate: reason={cv_reason} detail={cv_detail}"
            )
    if cv_external_gate_failures:
        fail("FAIL: Phase 5 control-variables enforcement", cv_external_gate_failures)

if phase_id == "6":
    analysis_plan_path = proj / "analysis" / "analysis-plan.md"
    analysis_manifest_path = proj / "analysis" / "analysis-plan-manifest.json"
    inventory_path = proj / "analysis" / "scripts-inventory.json"
    spec_path = proj / "analysis" / "spec-registry.csv"
    identification_path = proj / "design" / "identification-strategy.json"
    model_specs_path = proj / "design" / "model-specs.json"
    variable_dictionary_path = proj / "data" / "variable-dictionary.csv"
    data_manifest_path = proj / "data" / "data-measurement-manifest.json"
    review_path = proj / "review" / "pre-execution-review.json"
    fix_log_path = proj / "review" / "pre-execution-fix-log.json"
    rereview_path = proj / "review" / "pre-execution-rereview.json"
    review_md_path = proj / "review" / "pre-execution-review.md"
    fix_log_md_path = proj / "review" / "pre-execution-fix-log.md"
    forbidden_outputs = [
        "analysis/execution-report.json",
        "tables/results-registry.csv",
        "figures/figure-registry.csv",
    ]
    present_forbidden = [rel for rel in forbidden_outputs if (proj / rel).exists()]
    if present_forbidden:
        fail("FAIL: Phase 6 must not contain execution/result artifacts before Phase 8", present_forbidden)
    try:
        inventory = json.loads(inventory_path.read_text())
        analysis_manifest = json.loads(analysis_manifest_path.read_text())
    except Exception as exc:
        fail(f"FAIL: Phase 6 cannot read Phase 5 analysis artifacts: {exc}")
    if analysis_manifest.get("ready_for_phase_6") is not True:
        fail("FAIL: Phase 6 analysis-plan-manifest is not ready_for_phase_6")
    required_upstream_artifacts = {
        "analysis/analysis-plan.md",
        "analysis/analysis-plan-manifest.json",
        "analysis/scripts-inventory.json",
        "analysis/spec-registry.csv",
        "design/identification-strategy.json",
        "design/model-specs.json",
        "data/variable-dictionary.csv",
        "data/data-measurement-manifest.json",
    }
    planned_scripts = inventory.get("scripts")
    if not isinstance(planned_scripts, list) or not planned_scripts:
        fail("FAIL: Phase 6 requires non-empty planned scripts from scripts-inventory.json")
    planned_script_paths = {
        str(script.get("path", "")).strip()
        for script in planned_scripts
        if isinstance(script, dict) and script.get("path")
    }
    if not planned_script_paths:
        fail("FAIL: Phase 6 planned scripts have no paths")
    planned_tests = inventory.get("test_inventory")
    if not isinstance(planned_tests, list) or not planned_tests:
        fail("FAIL: Phase 6 requires non-empty test_inventory from scripts-inventory.json")
    planned_test_ids = {
        str(test.get("id", "")).strip()
        for test in planned_tests
        if isinstance(test, dict) and test.get("id")
    }
    if not planned_test_ids:
        fail("FAIL: Phase 6 planned tests have no ids")
    planned_spec_ids = set()
    if spec_path.exists():
        try:
            with spec_path.open(newline="", encoding="utf-8") as f:
                planned_spec_ids = {
                    str(row.get("spec_id", "")).strip()
                    for row in csv.DictReader(f)
                    if row.get("spec_id")
                }
        except Exception as exc:
            fail(f"FAIL: Phase 6 cannot read analysis/spec-registry.csv: {exc}")
    try:
        review = json.loads(review_path.read_text())
    except Exception as exc:
        fail(f"FAIL: Phase 6 pre-execution-review.json is not valid JSON: {exc}")
    if review.get("verdict") != "PASS":
        fail(f"FAIL: Phase 6 verdict must be PASS, got {review.get('verdict')}")
    if review.get("degraded") is not False:
        fail("FAIL: Phase 6 degraded must be false")
    review_engine = review.get("review_engine")
    if (
        not isinstance(review_engine, dict)
        or review_engine.get("skill") != "scholar-code-review"
        or review_engine.get("mode") != "pre_execution_planned"
    ):
        fail("FAIL: Phase 6 review_engine must be scholar-code-review pre_execution_planned")
    review_engine_issues = validate_engine_provenance(review_engine, "Phase 6 review_engine")
    if review_engine_issues:
        fail("FAIL: Phase 6 review_engine provenance is incomplete", review_engine_issues)
    expected_source_hashes = {
        "analysis_plan": sha256(analysis_plan_path),
        "analysis_plan_manifest": sha256(analysis_manifest_path),
        "scripts_inventory": sha256(inventory_path),
        "spec_registry": sha256(spec_path),
        "identification_strategy": sha256(identification_path),
        "model_specs": sha256(model_specs_path),
        "variable_dictionary": sha256(variable_dictionary_path),
        "data_measurement_manifest": sha256(data_manifest_path),
    }
    source_hashes = review.get("source_hashes")
    if not isinstance(source_hashes, dict):
        fail("FAIL: Phase 6 source_hashes must be an object")
    stale_sources = [
        f"{key} mismatch"
        for key, expected in expected_source_hashes.items()
        if source_hashes.get(key) != expected
    ]
    if stale_sources:
        fail("FAIL: Phase 6 source_hashes are stale", stale_sources)
    if review.get("inventory_hash") != sha256(inventory_path):
        fail("FAIL: Phase 6 inventory_hash does not match analysis/scripts-inventory.json")
    if int(review.get("unresolved_critical_count", -1)) != 0:
        fail("FAIL: Phase 6 unresolved_critical_count must be 0")
    if review.get("ready_for_phase_7") is not True:
        fail("FAIL: Phase 6 ready_for_phase_7 must be true")
    required_roles = {"correctness", "robustness", "statistical", "reproducibility", "style_ai_patterns", "data_handling"}
    reviewers = review.get("reviewers")
    if not isinstance(reviewers, list) or len(reviewers) < len(required_roles):
        fail("FAIL: Phase 6 requires at least six independent reviewers")
    roles = set()
    reviewer_ids = set()
    task_ids = set()
    bad_reviewers = []
    placeholder_values = {"", "tbd", "todo", "unknown", "n/a", "na", "placeholder"}
    for idx, reviewer in enumerate(reviewers):
        if not isinstance(reviewer, dict):
            bad_reviewers.append(f"reviewers[{idx}] is not an object")
            continue
        role = str(reviewer.get("role", "")).strip()
        reviewer_id = str(reviewer.get("reviewer_id", "")).strip()
        task_id = str(reviewer.get("task_invocation_id", "")).strip()
        agent_type = str(reviewer.get("agent_type", "")).strip()
        report_path = str(reviewer.get("report_path", "")).strip()
        roles.add(role)
        if reviewer_id.lower() in placeholder_values:
            bad_reviewers.append(f"reviewers[{idx}].reviewer_id missing")
        elif reviewer_id in reviewer_ids:
            bad_reviewers.append(f"reviewers[{idx}].reviewer_id duplicate")
        reviewer_ids.add(reviewer_id)
        if task_id.lower() in placeholder_values:
            bad_reviewers.append(f"reviewers[{idx}].task_invocation_id missing")
        elif task_id in task_ids:
            bad_reviewers.append(f"reviewers[{idx}].task_invocation_id duplicate")
        task_ids.add(task_id)
        if agent_type.lower() in placeholder_values:
            bad_reviewers.append(f"reviewers[{idx}].agent_type missing")
        if not report_path:
            bad_reviewers.append(f"reviewers[{idx}].report_path missing")
        elif Path(report_path).is_absolute() or not (proj / report_path).exists():
            bad_reviewers.append(f"reviewers[{idx}].report_path not found in project")
        if reviewer.get("verdict") not in ("PASS", "PASS_WITH_NONBLOCKING_NOTES"):
            bad_reviewers.append(f"reviewers[{idx}].verdict={reviewer.get('verdict')}")
        reviewer_scripts = reviewer.get("reviewed_scripts")
        if not isinstance(reviewer_scripts, list):
            bad_reviewers.append(f"reviewers[{idx}].reviewed_scripts must be list")
        else:
            reviewer_script_paths = {str(item).strip() for item in reviewer_scripts}
            if reviewer_script_paths != planned_script_paths:
                bad_reviewers.append(f"reviewers[{idx}].reviewed_scripts does not cover all planned scripts")
        reviewer_specs = reviewer.get("reviewed_specs")
        if not isinstance(reviewer_specs, list) or {str(item).strip() for item in reviewer_specs} != planned_spec_ids:
            bad_reviewers.append(f"reviewers[{idx}].reviewed_specs does not cover all planned specs")
        reviewer_tests = reviewer.get("reviewed_tests")
        if not isinstance(reviewer_tests, list) or {str(item).strip() for item in reviewer_tests} != planned_test_ids:
            bad_reviewers.append(f"reviewers[{idx}].reviewed_tests does not cover all planned tests")
        upstream = reviewer.get("reviewed_upstream_artifacts")
        if not isinstance(upstream, list) or {str(item).strip() for item in upstream} != required_upstream_artifacts:
            bad_reviewers.append(f"reviewers[{idx}].reviewed_upstream_artifacts incomplete")
        if not isinstance(reviewer.get("findings"), list):
            bad_reviewers.append(f"reviewers[{idx}].findings must be list")
    missing_roles = sorted(required_roles - roles)
    if missing_roles:
        bad_reviewers.extend(f"missing role {role}" for role in missing_roles)
    if bad_reviewers:
        fail("FAIL: Phase 6 reviewer panel is incomplete or not independent", bad_reviewers)
    reviewed_scripts = review.get("reviewed_scripts")
    if not isinstance(reviewed_scripts, list):
        fail("FAIL: Phase 6 reviewed_scripts must be a list")
    reviewed_script_paths = set()
    bad_reviewed_scripts = []
    for idx, item in enumerate(reviewed_scripts):
        if not isinstance(item, dict):
            bad_reviewed_scripts.append(f"reviewed_scripts[{idx}] is not an object")
            continue
        path = str(item.get("path", "")).strip()
        reviewed_script_paths.add(path)
        if item.get("status_in_inventory") != "planned":
            bad_reviewed_scripts.append(f"reviewed_scripts[{idx}].status_in_inventory must be planned")
        if item.get("exists_or_stub_declared") is not True:
            bad_reviewed_scripts.append(f"reviewed_scripts[{idx}].exists_or_stub_declared must be true")
        reviewed_by = item.get("reviewed_by")
        if not isinstance(reviewed_by, list) or set(str(role).strip() for role in reviewed_by) != required_roles:
            bad_reviewed_scripts.append(f"reviewed_scripts[{idx}].reviewed_by must include every required role")
    if bad_reviewed_scripts:
        fail("FAIL: Phase 6 reviewed_scripts entries are incomplete", bad_reviewed_scripts)
    missing_script_reviews = sorted(planned_script_paths - reviewed_script_paths)
    extra_script_reviews = sorted(reviewed_script_paths - planned_script_paths)
    if missing_script_reviews:
        fail("FAIL: Phase 6 did not review every planned script", missing_script_reviews)
    if extra_script_reviews:
        fail("FAIL: Phase 6 reviewed scripts not present in inventory", extra_script_reviews)
    reviewed_tests = review.get("reviewed_tests")
    if not isinstance(reviewed_tests, list):
        fail("FAIL: Phase 6 reviewed_tests must be a list")
    reviewed_test_ids = {
        str(item.get("id", "") if isinstance(item, dict) else item).strip()
        for item in reviewed_tests
    }
    missing_test_reviews = sorted(planned_test_ids - reviewed_test_ids)
    extra_test_reviews = sorted(reviewed_test_ids - planned_test_ids)
    if missing_test_reviews:
        fail("FAIL: Phase 6 did not review every planned test", missing_test_reviews)
    if extra_test_reviews:
        fail("FAIL: Phase 6 reviewed tests not present in inventory", extra_test_reviews)
    reviewed_specs = review.get("reviewed_specs", [])
    if planned_spec_ids:
        if not isinstance(reviewed_specs, list):
            fail("FAIL: Phase 6 reviewed_specs must be a list")
        reviewed_spec_ids = {str(spec).strip() for spec in reviewed_specs}
        missing_spec_reviews = sorted(planned_spec_ids - reviewed_spec_ids)
        extra_spec_reviews = sorted(reviewed_spec_ids - planned_spec_ids)
        if missing_spec_reviews:
            fail("FAIL: Phase 6 did not review every planned spec", missing_spec_reviews)
        if extra_spec_reviews:
            fail("FAIL: Phase 6 reviewed specs not present in registry", extra_spec_reviews)
    review_gate_checks = {
        "reviewed_script_dag": "script DAG",
        "reviewed_spec_coverage": "spec coverage",
        "reviewed_robustness_coverage": "robustness coverage",
        "reviewed_missing_data_alignment": "missing-data alignment",
        "reviewed_no_execution_boundary": "no-execution boundary",
    }
    gate_issues = []
    for field, label in review_gate_checks.items():
        value = review.get(field)
        if not isinstance(value, dict):
            gate_issues.append(f"{field} must be object")
            continue
        if value.get("reviewed") is not True:
            gate_issues.append(f"{label} not reviewed")
        if value.get("status") not in ("PASS", "PASS_WITH_NONBLOCKING_NOTES"):
            gate_issues.append(f"{label} status={value.get('status')}")
        reviewed_by = value.get("reviewed_by")
        if not isinstance(reviewed_by, list) or {str(role).strip() for role in reviewed_by} != required_roles:
            gate_issues.append(f"{label} reviewed_by must include every required role")
    if gate_issues:
        fail("FAIL: Phase 6 review gate coverage is incomplete", gate_issues)
    blocking_findings = review.get("blocking_findings")
    if not isinstance(blocking_findings, list):
        fail("FAIL: Phase 6 blocking_findings must be a list")
    if blocking_findings:
        fail("FAIL: Phase 6 final blocking_findings must be empty after fixes and re-review")
    fix_status = review.get("fix_status")
    if not isinstance(fix_status, dict):
        fail("FAIL: Phase 6 fix_status must be an object")
    if fix_status.get("all_blocking_fixed") is not True:
        fail("FAIL: Phase 6 fix_status.all_blocking_fixed must be true")
    if fix_status.get("fix_log") != "review/pre-execution-fix-log.json":
        fail("FAIL: Phase 6 fix_status.fix_log must point to review/pre-execution-fix-log.json")
    if fix_status.get("rereview") != "review/pre-execution-rereview.json":
        fail("FAIL: Phase 6 fix_status.rereview must point to review/pre-execution-rereview.json")
    try:
        fix_log = json.loads(fix_log_path.read_text())
    except Exception as exc:
        fail(f"FAIL: Phase 6 pre-execution-fix-log.json is not valid JSON: {exc}")
    if fix_log.get("required_fixes_completed") is not True:
        fail("FAIL: Phase 6 fix log required_fixes_completed must be true")
    if int(fix_log.get("unfixed_blocking_count", -1)) != 0:
        fail("FAIL: Phase 6 fix log has unfixed blocking findings")
    if fix_log.get("final_verdict") != "PASS":
        fail(f"FAIL: Phase 6 fix log final_verdict must be PASS, got {fix_log.get('final_verdict')}")
    fixed_findings = fix_log.get("fixed_findings")
    if not isinstance(fixed_findings, list):
        fail("FAIL: Phase 6 fix log fixed_findings must be a list")
    if fix_status.get("required") is True and not fixed_findings:
        fail("FAIL: Phase 6 fix_status.required is true but fixed_findings is empty")
    bad_fixes = []
    fixed_ids = set()
    for idx, finding in enumerate(fixed_findings):
        if not isinstance(finding, dict):
            bad_fixes.append(f"fixed_findings[{idx}] is not an object")
            continue
        finding_id = str(finding.get("finding_id", "")).strip()
        if finding_id.lower() in placeholder_values:
            bad_fixes.append(f"fixed_findings[{idx}].finding_id missing")
        elif finding_id in fixed_ids:
            bad_fixes.append(f"fixed_findings[{idx}].finding_id duplicate")
        fixed_ids.add(finding_id)
        if finding.get("status") not in ("fixed", "resolved"):
            bad_fixes.append(f"fixed_findings[{idx}].status={finding.get('status')} not allowed")
        if not finding.get("action_taken"):
            bad_fixes.append(f"fixed_findings[{idx}].action_taken missing")
        if not finding.get("affected_files"):
            bad_fixes.append(f"fixed_findings[{idx}].affected_files missing")
        if str(finding.get("blocker_type", "")).strip() == "executable" and finding.get("status") == "accepted_limitation":
            bad_fixes.append(f"fixed_findings[{idx}] accepts an executable blocker")
    if bad_fixes:
        fail("FAIL: Phase 6 fix log entries are incomplete", bad_fixes)
    try:
        rereview = json.loads(rereview_path.read_text())
    except Exception as exc:
        fail(f"FAIL: Phase 6 pre-execution-rereview.json is not valid JSON: {exc}")
    if rereview.get("verdict") != "PASS":
        fail(f"FAIL: Phase 6 rereview verdict must be PASS, got {rereview.get('verdict')}")
    if rereview.get("degraded") is not False:
        fail("FAIL: Phase 6 rereview degraded must be false")
    if int(rereview.get("unresolved_blocking_count", -1)) != 0:
        fail("FAIL: Phase 6 rereview has unresolved blocking findings")
    if rereview.get("ready_for_phase_7") is not True:
        fail("FAIL: Phase 6 rereview ready_for_phase_7 must be true")
    rereviewed_findings = rereview.get("rereviewed_findings")
    if not isinstance(rereviewed_findings, list):
        fail("FAIL: Phase 6 rereviewed_findings must be a list")
    rereviewed_ids = set()
    bad_rereviews = []
    for idx, item in enumerate(rereviewed_findings):
        if not isinstance(item, dict):
            bad_rereviews.append(f"rereviewed_findings[{idx}] is not an object")
            continue
        finding_id = str(item.get("finding_id", "")).strip()
        rereviewed_ids.add(finding_id)
        if item.get("resolution_verdict") != "RESOLVED":
            bad_rereviews.append(f"rereviewed_findings[{idx}].resolution_verdict={item.get('resolution_verdict')}")
    if fixed_ids and fixed_ids - rereviewed_ids:
        bad_rereviews.extend(f"missing rereview for {finding_id}" for finding_id in sorted(fixed_ids - rereviewed_ids))
    if bad_rereviews:
        fail("FAIL: Phase 6 rereview does not resolve fixed findings", bad_rereviews)
    if review_path.stat().st_mtime < inventory_path.stat().st_mtime:
        fail("FAIL: Phase 6 review is older than scripts inventory")
    if fix_log_path.stat().st_mtime < review_path.stat().st_mtime:
        fail("FAIL: Phase 6 fix log is older than review")
    if rereview_path.stat().st_mtime < fix_log_path.stat().st_mtime:
        fail("FAIL: Phase 6 rereview is older than fix log")
    conflict_pattern = re.compile(r"(unresolved|remains|open).{0,50}(block|blocking|critical|major)|(block|blocking|critical|major).{0,50}(unresolved|remains|open)")
    review_md_text = review_md_path.read_text(errors="ignore").lower()
    fix_log_md_text = fix_log_md_path.read_text(errors="ignore").lower()
    if conflict_pattern.search(review_md_text) or conflict_pattern.search(fix_log_md_text):
        fail("FAIL: Phase 6 markdown summary contradicts JSON PASS status with unresolved blocker language")
    review_words = re.findall(r"\b\w+\b", review_md_path.read_text(errors="ignore"))
    if len(review_words) < 50:
        fail(f"FAIL: Phase 6 pre-execution-review.md is too short, found {len(review_words)} words")
    fix_words = re.findall(r"\b\w+\b", fix_log_md_path.read_text(errors="ignore"))
    if len(fix_words) < 30:
        fail(f"FAIL: Phase 6 pre-execution-fix-log.md is too short, found {len(fix_words)} words")
    # Codex cross-model review gate (added 2026-05-10):
    # SCHOLAR_CODEX_DEFAULT defaults to true, so when the codex CLI is on PATH
    # the gate REQUIRES either codex code-mode artifacts under reviews/codex/
    # OR an [EXCUSED:codex-review: <reason>] annotation in
    # review/pre-execution-review.{md,json}. Opt out at the shell level with
    # SCHOLAR_CODEX_DEFAULT=false.
    codex_external_gate_failures = []
    codex_gate_result = run_external_gate(
        "codex-trigger-phase6.sh", proj, "Phase 6 codex cross-model review"
    )
    if codex_gate_result is not None:
        codex_status, codex_reason, codex_detail = codex_gate_result
        if codex_status == "RED":
            codex_external_gate_failures.append(
                f"Phase 6 codex cross-model review: reason={codex_reason} detail={codex_detail}"
            )
    if codex_external_gate_failures:
        fail("FAIL: Phase 6 codex cross-model review gate", codex_external_gate_failures)

if phase_id == "7":
    identification_path = proj / "design" / "identification-strategy.json"
    model_specs_path = proj / "design" / "model-specs.json"
    measurement_plan_path = proj / "data" / "measurement-plan.md"
    variable_dictionary_path = proj / "data" / "variable-dictionary.csv"
    analysis_plan_path = proj / "analysis" / "analysis-plan.md"
    spec_path = proj / "analysis" / "spec-registry.csv"
    inventory_path = proj / "analysis" / "scripts-inventory.json"
    preexec_review_path = proj / "review" / "pre-execution-review.json"
    preexec_fix_log_path = proj / "review" / "pre-execution-fix-log.json"
    preexec_rereview_path = proj / "review" / "pre-execution-rereview.json"
    premortem_path = proj / "review" / "analysis-premortem.json"
    premortem_md_path = proj / "review" / "analysis-premortem.md"
    fix_log_path = proj / "review" / "analysis-premortem-fix-log.json"
    forbidden_outputs = [
        "analysis/execution-report.json",
        "tables/results-registry.csv",
        "figures/figure-registry.csv",
    ]
    present_forbidden = [rel for rel in forbidden_outputs if (proj / rel).exists()]
    if present_forbidden:
        fail("FAIL: Phase 7 must not contain execution/result artifacts before Phase 8", present_forbidden)
    required_phase7_paths = (
        identification_path,
        model_specs_path,
        measurement_plan_path,
        variable_dictionary_path,
        analysis_plan_path,
        spec_path,
        inventory_path,
        preexec_review_path,
        preexec_fix_log_path,
        preexec_rereview_path,
    )
    for required_path in required_phase7_paths:
        if not required_path.exists():
            fail(f"FAIL: Phase 7 missing required input {required_path.relative_to(proj)}")
    try:
        preexec_review = json.loads(preexec_review_path.read_text())
        preexec_fix_log = json.loads(preexec_fix_log_path.read_text())
        preexec_rereview = json.loads(preexec_rereview_path.read_text())
    except Exception as exc:
        fail(f"FAIL: Phase 7 cannot read Phase 6 review artifacts: {exc}")
    if preexec_review.get("verdict") != "PASS" or preexec_review.get("degraded") is not False:
        fail("FAIL: Phase 7 requires passing non-degraded Phase 6 pre-execution review")
    if preexec_review.get("ready_for_phase_7") is not True:
        fail("FAIL: Phase 7 requires Phase 6 ready_for_phase_7 true")
    if preexec_review.get("blocking_findings"):
        fail("FAIL: Phase 7 cannot start with Phase 6 blocking findings")
    if preexec_fix_log.get("final_verdict") != "PASS" or int(preexec_fix_log.get("unfixed_blocking_count", -1)) != 0:
        fail("FAIL: Phase 7 requires passing Phase 6 fix log")
    if preexec_rereview.get("verdict") != "PASS" or preexec_rereview.get("ready_for_phase_7") is not True:
        fail("FAIL: Phase 7 requires passing Phase 6 re-review")
    try:
        identification = json.loads(identification_path.read_text())
        model_specs = json.loads(model_specs_path.read_text())
        inventory = json.loads(inventory_path.read_text())
    except Exception as exc:
        fail(f"FAIL: Phase 7 cannot read design/model or script inventory artifacts: {exc}")
    planned_scripts = inventory.get("scripts")
    if not isinstance(planned_scripts, list) or not planned_scripts:
        fail("FAIL: Phase 7 requires non-empty planned scripts from scripts-inventory.json")
    planned_script_paths = {
        str(script.get("path", "")).strip()
        for script in planned_scripts
        if isinstance(script, dict) and script.get("path")
    }
    planned_outputs = set()
    for script in planned_scripts:
        if isinstance(script, dict) and isinstance(script.get("produces"), list):
            planned_outputs.update(str(item).strip() for item in script["produces"] if str(item).strip())
    planned_tests = inventory.get("test_inventory")
    if not isinstance(planned_tests, list) or not planned_tests:
        fail("FAIL: Phase 7 requires non-empty test_inventory from scripts-inventory.json")
    planned_test_ids = {
        str(test.get("id", "")).strip()
        for test in planned_tests
        if isinstance(test, dict) and test.get("id")
    }
    planned_spec_ids = set()
    try:
        with spec_path.open(newline="", encoding="utf-8") as f:
            spec_rows = list(csv.DictReader(f))
    except Exception as exc:
        fail(f"FAIL: Phase 7 cannot read analysis/spec-registry.csv: {exc}")
    for row in spec_rows:
        if row.get("spec_id"):
            planned_spec_ids.add(str(row["spec_id"]).strip())
    if not planned_spec_ids:
        fail("FAIL: Phase 7 requires non-empty spec IDs from spec-registry.csv")
    planned_hypothesis_ids = set()
    for row in spec_rows:
        raw_hypotheses = str(row.get("hypothesis_id") or row.get("hypothesis_ids") or "").strip()
        for hypothesis_id in re.split(r"[;,]", raw_hypotheses):
            hypothesis_id = hypothesis_id.strip()
            if hypothesis_id:
                planned_hypothesis_ids.add(hypothesis_id)
    if not planned_hypothesis_ids:
        fail("FAIL: Phase 7 requires hypothesis_id coverage in spec-registry.csv for null-falsification review")
    design_model_ids = {
        str(model.get("id", "")).strip()
        for model in model_specs.get("models", [])
        if isinstance(model, dict) and model.get("id")
    }
    bad_specs = []
    for idx, row in enumerate(spec_rows):
        model_id = str(row.get("model_id", "")).strip()
        if model_id and design_model_ids and model_id not in design_model_ids:
            bad_specs.append(f"spec row {idx} model_id {model_id} not found in design/model-specs.json")
    if bad_specs:
        fail("FAIL: Phase 7 spec registry does not align with design model specs", bad_specs)
    try:
        premortem = json.loads(premortem_path.read_text())
    except Exception as exc:
        fail(f"FAIL: Phase 7 analysis-premortem.json is not valid JSON: {exc}")
    if premortem.get("verdict") != "PASS":
        fail(f"FAIL: Phase 7 verdict must be PASS, got {premortem.get('verdict')}")
    if premortem.get("degraded") is not False:
        fail("FAIL: Phase 7 degraded must be false")
    if premortem.get("ready_for_phase_8") is not True:
        fail("FAIL: Phase 7 ready_for_phase_8 must be true")
    method_family, expected_execution_skill, _method_components, routing_issues = validate_method_specialist_routing(
        identification.get("method_specialist_routing"),
        identification.get("method_specialist_routing", {}).get("method_orientation"),
        "Phase 7",
    )
    if routing_issues:
        fail("FAIL: Phase 7 cannot resolve routed specialist skill from Phase 3", routing_issues)
    premortem_engine = premortem.get("premortem_engine")
    if not isinstance(premortem_engine, dict):
        fail("FAIL: Phase 7 premortem_engine must be an object")
    if premortem_engine.get("skill") != expected_execution_skill or premortem_engine.get("mode") != "premortem":
        fail(f"FAIL: Phase 7 must invoke {expected_execution_skill} in premortem mode")
    premortem_engine_issues = validate_engine_provenance(premortem_engine, "Phase 7 premortem_engine")
    if premortem_engine_issues:
        fail("FAIL: Phase 7 premortem_engine provenance is incomplete", premortem_engine_issues)
    if premortem_engine.get("auto_research_contract") != "phase_7":
        fail("FAIL: Phase 7 premortem_engine.auto_research_contract must be phase_7")
    if premortem_engine.get("skip_premortem_ignored") is not True:
        fail("FAIL: Phase 7 must record skip_premortem_ignored true")
    try:
        iteration = int(premortem.get("iteration"))
    except Exception:
        fail("FAIL: Phase 7 iteration must be an integer from 1 to 3")
    if iteration < 1 or iteration > 3:
        fail("FAIL: Phase 7 iteration must be between 1 and 3")
    source_hashes = premortem.get("source_hashes")
    if not isinstance(source_hashes, dict):
        fail("FAIL: Phase 7 source_hashes must be an object")
    expected_hashes = {
        "identification_strategy": sha256(identification_path),
        "model_specs": sha256(model_specs_path),
        "measurement_plan": sha256(measurement_plan_path),
        "variable_dictionary": sha256(variable_dictionary_path),
        "analysis_plan": sha256(analysis_plan_path),
        "spec_registry": sha256(spec_path),
        "scripts_inventory": sha256(inventory_path),
        "pre_execution_review": sha256(preexec_review_path),
        "pre_execution_fix_log": sha256(preexec_fix_log_path),
        "pre_execution_rereview": sha256(preexec_rereview_path),
    }
    hash_errors = [
        f"{key} mismatch"
        for key, expected in expected_hashes.items()
        if source_hashes.get(key) != expected
    ]
    if hash_errors:
        fail("FAIL: Phase 7 source hashes are stale or incomplete", hash_errors)
    required_roles = {"identification", "measurement_missingness", "model_robustness", "interpretation_claims"}
    required_inputs = {
        "design/identification-strategy.json",
        "design/model-specs.json",
        "data/measurement-plan.md",
        "data/variable-dictionary.csv",
        "analysis/analysis-plan.md",
        "analysis/spec-registry.csv",
        "analysis/scripts-inventory.json",
        "review/pre-execution-review.json",
        "review/pre-execution-fix-log.json",
        "review/pre-execution-rereview.json",
    }
    reviewers = premortem.get("reviewers")
    if not isinstance(reviewers, list) or len(reviewers) < len(required_roles):
        fail("FAIL: Phase 7 requires at least four independent premortem reviewers")
    reviewer_provenance = premortem.get("reviewer_provenance")
    if not isinstance(reviewer_provenance, list) or len(reviewer_provenance) < len(required_roles):
        fail("FAIL: Phase 7 reviewer_provenance must cover all premortem reviewers")
    provenance_roles = set()
    provenance_ids = set()
    bad_provenance = []
    for idx, item in enumerate(reviewer_provenance):
        if not isinstance(item, dict):
            bad_provenance.append(f"reviewer_provenance[{idx}] is not an object")
            continue
        role = str(item.get("role", "")).strip()
        reviewer_id = str(item.get("reviewer_id", "")).strip()
        agent_name = str(item.get("agent_name", "")).strip()
        task_id = str(item.get("task_invocation_id", "")).strip()
        dispatched_at = str(item.get("dispatched_at_utc", "")).strip()
        model_id = str(item.get("model_id", "")).strip()
        report_path = str(item.get("report_path", "")).strip()
        provenance_roles.add(role)
        provenance_ids.add(reviewer_id)
        if role not in required_roles:
            bad_provenance.append(f"reviewer_provenance[{idx}].role={role}")
        if reviewer_id.lower() in {"", "tbd", "todo", "unknown", "n/a", "na", "placeholder"}:
            bad_provenance.append(f"reviewer_provenance[{idx}].reviewer_id missing")
        if not agent_name.startswith("peer-reviewer-"):
            bad_provenance.append(f"reviewer_provenance[{idx}].agent_name must start with peer-reviewer-")
        if task_id.lower() in {"", "tbd", "todo", "unknown", "n/a", "na", "placeholder"}:
            bad_provenance.append(f"reviewer_provenance[{idx}].task_invocation_id missing")
        if not re.match(r"^\d{4}-\d{2}-\d{2}T", dispatched_at):
            bad_provenance.append(f"reviewer_provenance[{idx}].dispatched_at_utc must be ISO-like UTC timestamp")
        if model_id.lower() in {"", "tbd", "todo", "unknown", "n/a", "na", "placeholder"}:
            bad_provenance.append(f"reviewer_provenance[{idx}].model_id missing")
        if not report_path:
            bad_provenance.append(f"reviewer_provenance[{idx}].report_path missing")
        elif Path(report_path).is_absolute() or not (proj / report_path).exists():
            bad_provenance.append(f"reviewer_provenance[{idx}].report_path not found in project")
    if required_roles - provenance_roles:
        bad_provenance.extend(f"missing provenance role {role}" for role in sorted(required_roles - provenance_roles))
    if bad_provenance:
        fail("FAIL: Phase 7 reviewer provenance is incomplete", bad_provenance)
    roles = set()
    reviewer_ids = set()
    task_ids = set()
    bad_reviewers = []
    placeholder_values = {"", "tbd", "todo", "unknown", "n/a", "na", "placeholder"}
    for idx, reviewer in enumerate(reviewers):
        if not isinstance(reviewer, dict):
            bad_reviewers.append(f"reviewers[{idx}] is not an object")
            continue
        role = str(reviewer.get("role", "")).strip()
        reviewer_id = str(reviewer.get("reviewer_id", "")).strip()
        task_id = str(reviewer.get("task_invocation_id", "")).strip()
        agent_type = str(reviewer.get("agent_type", "")).strip()
        report_path = str(reviewer.get("report_path", "")).strip()
        roles.add(role)
        if reviewer_id.lower() in placeholder_values:
            bad_reviewers.append(f"reviewers[{idx}].reviewer_id missing")
        elif reviewer_id in reviewer_ids:
            bad_reviewers.append(f"reviewers[{idx}].reviewer_id duplicate")
        reviewer_ids.add(reviewer_id)
        if task_id.lower() in placeholder_values:
            bad_reviewers.append(f"reviewers[{idx}].task_invocation_id missing")
        elif task_id in task_ids:
            bad_reviewers.append(f"reviewers[{idx}].task_invocation_id duplicate")
        task_ids.add(task_id)
        if agent_type.lower() in placeholder_values:
            bad_reviewers.append(f"reviewers[{idx}].agent_type missing")
        if not report_path:
            bad_reviewers.append(f"reviewers[{idx}].report_path missing")
        elif Path(report_path).is_absolute() or not (proj / report_path).exists():
            bad_reviewers.append(f"reviewers[{idx}].report_path not found in project")
        if reviewer.get("verdict") not in ("PASS", "PASS_WITH_NONBLOCKING_NOTES"):
            bad_reviewers.append(f"reviewers[{idx}].verdict={reviewer.get('verdict')}")
        reviewed_inputs = reviewer.get("reviewed_inputs")
        if not isinstance(reviewed_inputs, list):
            bad_reviewers.append(f"reviewers[{idx}].reviewed_inputs must be list")
        elif set(str(item).strip() for item in reviewed_inputs) != required_inputs:
            bad_reviewers.append(f"reviewers[{idx}].reviewed_inputs must cover all required inputs")
        if not isinstance(reviewer.get("risks"), list):
            bad_reviewers.append(f"reviewers[{idx}].risks must be list")
    missing_roles = sorted(required_roles - roles)
    if missing_roles:
        bad_reviewers.extend(f"missing role {role}" for role in missing_roles)
    if reviewer_ids != provenance_ids:
        bad_reviewers.append("reviewer ids must match reviewer_provenance ids")
    if bad_reviewers:
        fail("FAIL: Phase 7 reviewer panel is incomplete or not independent", bad_reviewers)
    traffic = premortem.get("traffic_light_summary")
    required_traffic = {
        "identification",
        "variable_construction",
        "sample_restrictions",
        "model_specification",
        "standard_errors",
        "missing_data",
        "robustness",
        "power_effect_size",
        "heterogeneity_multi_comparison",
        "mechanism_evidence",
        "table_figure_plan",
        "preregistration_deviation",
        "interpretive_reach",
    }
    if not isinstance(traffic, list) or len(traffic) < len(required_traffic):
        fail("FAIL: Phase 7 traffic_light_summary must cover all analysis premortem dimensions")
    traffic_dims = set()
    unresolved_red_dims = []
    bad_traffic = []
    for idx, item in enumerate(traffic):
        if not isinstance(item, dict):
            bad_traffic.append(f"traffic_light_summary[{idx}] is not an object")
            continue
        dim = str(item.get("dimension", "")).strip()
        verdict = str(item.get("verdict", "")).strip().upper()
        traffic_dims.add(dim)
        if verdict not in {"GREEN", "YELLOW", "RED"}:
            bad_traffic.append(f"traffic_light_summary[{idx}].verdict={item.get('verdict')}")
        if not item.get("lead_reviewer") or not item.get("evidence"):
            bad_traffic.append(f"traffic_light_summary[{idx}] missing lead_reviewer or evidence")
        if verdict == "RED" and item.get("resolution_status") != "resolved":
            unresolved_red_dims.append(dim or f"traffic_light_summary[{idx}]")
    missing_traffic = sorted(required_traffic - traffic_dims)
    if missing_traffic:
        bad_traffic.extend(f"missing traffic-light dimension {dim}" for dim in missing_traffic)
    if unresolved_red_dims:
        bad_traffic.extend(f"unresolved RED dimension {dim}" for dim in unresolved_red_dims)
    if bad_traffic:
        fail("FAIL: Phase 7 traffic-light summary is incomplete", bad_traffic)
    null_table = premortem.get("null_falsification_table")
    if not isinstance(null_table, list):
        fail("FAIL: Phase 7 null_falsification_table must be a list")
    null_by_hypothesis = {
        str(item.get("hypothesis_id", "")).strip(): item
        for item in null_table
        if isinstance(item, dict)
    }
    bad_null = []
    for hid in sorted(planned_hypothesis_ids):
        item = null_by_hypothesis.get(hid)
        if not item:
            bad_null.append(f"missing hypothesis {hid}")
            continue
        if word_count(str(item.get("null_pattern", ""))) < 8:
            bad_null.append(f"{hid} null_pattern too thin")
        if item.get("precommitted") is not True:
            bad_null.append(f"{hid} precommitted must be true")
        if item.get("discussion_concedes_null") is not True:
            bad_null.append(f"{hid} discussion_concedes_null must be true")
        if item.get("status") not in {"PASS", "GREEN"}:
            bad_null.append(f"{hid} status={item.get('status')}")
    extra_null = sorted(set(null_by_hypothesis) - planned_hypothesis_ids)
    if extra_null:
        bad_null.extend(f"unexpected hypothesis {hid}" for hid in extra_null)
    if bad_null:
        fail("FAIL: Phase 7 null-falsification table is incomplete", bad_null)
    reviewed_scripts = premortem.get("reviewed_scripts")
    if not isinstance(reviewed_scripts, list):
        fail("FAIL: Phase 7 reviewed_scripts must be a list")
    reviewed_script_paths = {
        str(item.get("path", "") if isinstance(item, dict) else item).strip()
        for item in reviewed_scripts
    }
    if reviewed_script_paths != planned_script_paths:
        missing = sorted(planned_script_paths - reviewed_script_paths)
        extra = sorted(reviewed_script_paths - planned_script_paths)
        fail("FAIL: Phase 7 reviewed_scripts must exactly cover planned scripts", missing + extra)
    reviewed_specs = premortem.get("reviewed_specs")
    if not isinstance(reviewed_specs, list):
        fail("FAIL: Phase 7 reviewed_specs must be a list")
    reviewed_spec_ids = {
        str(item.get("spec_id", "") if isinstance(item, dict) else item).strip()
        for item in reviewed_specs
    }
    if reviewed_spec_ids != planned_spec_ids:
        missing = sorted(planned_spec_ids - reviewed_spec_ids)
        extra = sorted(reviewed_spec_ids - planned_spec_ids)
        fail("FAIL: Phase 7 reviewed_specs must exactly cover planned specs", missing + extra)
    reviewed_tests = premortem.get("reviewed_tests")
    if not isinstance(reviewed_tests, list):
        fail("FAIL: Phase 7 reviewed_tests must be a list")
    reviewed_test_ids = {
        str(item.get("id", "") if isinstance(item, dict) else item).strip()
        for item in reviewed_tests
    }
    if reviewed_test_ids != planned_test_ids:
        missing = sorted(planned_test_ids - reviewed_test_ids)
        extra = sorted(reviewed_test_ids - planned_test_ids)
        fail("FAIL: Phase 7 reviewed_tests must exactly cover planned tests", missing + extra)
    risk_register = premortem.get("risk_register")
    required_risk_domains = {
        "design_plan_alignment",
        "identification",
        "measurement",
        "missing_data",
        "model_fragility",
        "robustness",
        "null_or_conflicting_results",
        "claim_support",
        "execution_readiness",
    }
    if not isinstance(risk_register, list) or len(risk_register) < len(required_risk_domains):
        fail("FAIL: Phase 7 risk_register must include all mandatory premortem domains")
    blocking_severities = {"red", "critical", "blocker", "major", "high"}
    allowed_risk_status = {"mitigated", "resolved", "nonblocking", "accepted_limitation"}
    risk_ids = set()
    fixed_required_ids = set()
    risk_domains = set()
    bad_risks = []
    for idx, risk in enumerate(risk_register):
        if not isinstance(risk, dict):
            bad_risks.append(f"risk_register[{idx}] is not an object")
            continue
        risk_id = str(risk.get("risk_id", "")).strip()
        severity = str(risk.get("severity", "")).strip().lower()
        status = str(risk.get("status", "")).strip().lower()
        domain = str(risk.get("domain", "")).strip()
        risk_domains.add(domain)
        if risk_id.lower() in placeholder_values:
            bad_risks.append(f"risk_register[{idx}].risk_id missing")
        elif risk_id in risk_ids:
            bad_risks.append(f"risk_register[{idx}].risk_id duplicate")
        risk_ids.add(risk_id)
        for field in ("domain", "severity", "description", "evidence", "affected_specs", "affected_scripts", "mitigation", "status", "owner_phase"):
            if not risk.get(field):
                bad_risks.append(f"risk_register[{idx}].{field} missing")
        if "route_back_phase" not in risk:
            bad_risks.append(f"risk_register[{idx}].route_back_phase missing")
        if not isinstance(risk.get("affected_specs", []), list):
            bad_risks.append(f"risk_register[{idx}].affected_specs must be list")
        if not isinstance(risk.get("affected_scripts", []), list):
            bad_risks.append(f"risk_register[{idx}].affected_scripts must be list")
        if status not in allowed_risk_status:
            bad_risks.append(f"risk_register[{idx}].status={risk.get('status')}")
        if severity in blocking_severities:
            if status not in ("mitigated", "resolved"):
                bad_risks.append(f"risk_register[{idx}] blocking severity is not mitigated/resolved")
            fixed_required_ids.add(risk_id)
        if risk.get("owner_phase") not in ("3", "4", "5", "6", "7"):
            bad_risks.append(f"risk_register[{idx}].owner_phase must be 3, 4, 5, 6, or 7")
        if risk.get("route_back_phase") not in (None, ""):
            bad_risks.append(f"risk_register[{idx}] cannot pass with route_back_phase set")
    missing_domains = sorted(required_risk_domains - risk_domains)
    if missing_domains:
        bad_risks.extend(f"missing risk domain {domain}" for domain in missing_domains)
    if bad_risks:
        fail("FAIL: Phase 7 risk register is incomplete", bad_risks)
    reporting_depth = premortem.get("reporting_depth_checklist")
    if not isinstance(reporting_depth, list):
        fail("FAIL: Phase 7 reporting_depth_checklist must be a list")
    reporting_by_risk = {
        str(item.get("risk_id", "")).strip(): item
        for item in reporting_depth
        if isinstance(item, dict)
    }
    reporting_triggers = (
        "report",
        "diagnostic",
        "estimator",
        "specification",
        "sensitivity",
        "robustness",
        "table",
        "figure",
        "appendix",
        "compare",
        "pretrend",
    )
    required_reporting_risks = set()
    for risk in risk_register:
        if not isinstance(risk, dict):
            continue
        mitigation_text = str(risk.get("mitigation", "")).lower()
        if any(token in mitigation_text for token in reporting_triggers):
            required_reporting_risks.add(str(risk.get("risk_id", "")).strip())
    bad_reporting = []
    for rid in sorted(required_reporting_risks):
        item = reporting_by_risk.get(rid)
        if not item:
            bad_reporting.append(f"missing reporting-depth checklist for {rid}")
            continue
        for field in ("diagnostic_outputs", "sensitivity_range", "failure_mode_disclosure", "reporting_location"):
            value = item.get(field)
            if isinstance(value, list):
                if not value:
                    bad_reporting.append(f"{rid}.{field} empty")
            elif not str(value or "").strip():
                bad_reporting.append(f"{rid}.{field} missing")
    if bad_reporting:
        fail("FAIL: Phase 7 reporting-depth checklist is incomplete", bad_reporting)
    if premortem.get("blocking_items_resolved") is not True:
        fail("FAIL: Phase 7 blocking_items_resolved must be true")
    if int(premortem.get("unresolved_blocking_count", -1)) != 0:
        fail("FAIL: Phase 7 unresolved_blocking_count must be 0")
    accepted = premortem.get("accepted_limitations")
    if not isinstance(accepted, list):
        fail("FAIL: Phase 7 accepted_limitations must be a list")
    bad_limitations = []
    for idx, limitation in enumerate(accepted):
        if not isinstance(limitation, dict):
            bad_limitations.append(f"accepted_limitations[{idx}] is not an object")
            continue
        severity = str(limitation.get("severity", "")).strip().lower()
        if severity in blocking_severities:
            bad_limitations.append(f"accepted_limitations[{idx}] cannot accept {severity} risk")
        for field in ("limitation_id", "severity", "rationale", "monitoring_plan"):
            if not limitation.get(field):
                bad_limitations.append(f"accepted_limitations[{idx}].{field} missing")
    if bad_limitations:
        fail("FAIL: Phase 7 accepted limitations are invalid", bad_limitations)
    decision_rules = premortem.get("decision_rules")
    if not isinstance(decision_rules, list) or len(decision_rules) < 3:
        fail("FAIL: Phase 7 decision_rules must include at least three execution decision rules")
    bad_rules = []
    for idx, rule in enumerate(decision_rules):
        if not isinstance(rule, dict):
            bad_rules.append(f"decision_rules[{idx}] is not an object")
            continue
        for field in ("rule_id", "condition", "action"):
            if not rule.get(field):
                bad_rules.append(f"decision_rules[{idx}].{field} missing")
    if bad_rules:
        fail("FAIL: Phase 7 decision rules are incomplete", bad_rules)
    phase8_handoff = premortem.get("phase8_handoff")
    if not isinstance(phase8_handoff, dict):
        fail("FAIL: Phase 7 phase8_handoff must be an object")
    handoff_scripts = [str(item).strip() for item in phase8_handoff.get("script_order", [])]
    if set(handoff_scripts) != planned_script_paths:
        fail("FAIL: Phase 7 phase8_handoff.script_order must cover every planned script exactly once")
    expected_outputs = {str(item).strip() for item in phase8_handoff.get("expected_outputs", [])}
    if planned_outputs and not planned_outputs.issubset(expected_outputs):
        fail("FAIL: Phase 7 phase8_handoff.expected_outputs must include every planned script output", sorted(planned_outputs - expected_outputs))
    if phase8_handoff.get("expected_result_registry") != "tables/results-registry.csv":
        fail("FAIL: Phase 7 phase8_handoff.expected_result_registry must be tables/results-registry.csv")
    if phase8_handoff.get("expected_figure_registry") != "figures/figure-registry.csv":
        fail("FAIL: Phase 7 phase8_handoff.expected_figure_registry must be figures/figure-registry.csv")
    halt_checks = phase8_handoff.get("halt_checks")
    if not isinstance(halt_checks, list) or len(halt_checks) < 3:
        fail("FAIL: Phase 7 phase8_handoff.halt_checks must include at least three halt checks")
    go_no_go = premortem.get("go_no_go")
    if not isinstance(go_no_go, dict):
        fail("FAIL: Phase 7 go_no_go must be an object")
    if go_no_go.get("decision") != "GO":
        fail(f"FAIL: Phase 7 go_no_go.decision must be GO, got {go_no_go.get('decision')}")
    if go_no_go.get("route_back_phase") not in (None, ""):
        fail("FAIL: Phase 7 cannot pass while route_back_phase is set")
    if go_no_go.get("ready_for_phase_8") is not True:
        fail("FAIL: Phase 7 go_no_go.ready_for_phase_8 must be true")
    try:
        fix_log = json.loads(fix_log_path.read_text())
    except Exception as exc:
        fail(f"FAIL: Phase 7 analysis-premortem-fix-log.json is not valid JSON: {exc}")
    if fix_log.get("required_fixes_completed") is not True:
        fail("FAIL: Phase 7 fix log required_fixes_completed must be true")
    if int(fix_log.get("unresolved_blocking_count", -1)) != 0:
        fail("FAIL: Phase 7 fix log unresolved_blocking_count must be 0")
    if fix_log.get("final_verdict") != "PASS":
        fail(f"FAIL: Phase 7 fix log final_verdict must be PASS, got {fix_log.get('final_verdict')}")
    fixed_risks = fix_log.get("fixed_risks")
    if not isinstance(fixed_risks, list):
        fail("FAIL: Phase 7 fix log fixed_risks must be a list")
    fixed_ids = set()
    bad_fixes = []
    for idx, fixed in enumerate(fixed_risks):
        if not isinstance(fixed, dict):
            bad_fixes.append(f"fixed_risks[{idx}] is not an object")
            continue
        risk_id = str(fixed.get("risk_id", "")).strip()
        fixed_ids.add(risk_id)
        if risk_id.lower() in placeholder_values:
            bad_fixes.append(f"fixed_risks[{idx}].risk_id missing")
        if fixed.get("status") not in ("fixed", "mitigated", "resolved"):
            bad_fixes.append(f"fixed_risks[{idx}].status={fixed.get('status')}")
        for field in ("action_taken", "affected_files"):
            if not fixed.get(field):
                bad_fixes.append(f"fixed_risks[{idx}].{field} missing")
    missing_fixes = sorted(fixed_required_ids - fixed_ids)
    if missing_fixes:
        bad_fixes.extend(f"missing fix log entry for {risk_id}" for risk_id in missing_fixes)
    if bad_fixes:
        fail("FAIL: Phase 7 fix log entries are incomplete", bad_fixes)
    if premortem_path.stat().st_mtime < preexec_review_path.stat().st_mtime:
        fail("FAIL: Phase 7 premortem is older than Phase 6 review")
    premortem_md_text = premortem_md_path.read_text(errors="ignore").lower()
    conflict_pattern = re.compile(r"(unresolved|remains|open).{0,50}(red|block|blocking|critical|major)|(red|block|blocking|critical|major).{0,50}(unresolved|remains|open)")
    if conflict_pattern.search(premortem_md_text):
        fail("FAIL: Phase 7 markdown summary contradicts JSON PASS status with unresolved red/blocker language")
    premortem_words = re.findall(r"\b\w+\b", premortem_md_path.read_text(errors="ignore"))
    if len(premortem_words) < 80:
        fail(f"FAIL: Phase 7 analysis-premortem.md is too short, found {len(premortem_words)} words")

if phase_id == "8":
    analysis_plan_path = proj / "analysis" / "analysis-plan.md"
    spec_path = proj / "analysis" / "spec-registry.csv"
    inventory_path = proj / "analysis" / "scripts-inventory.json"
    premortem_path = proj / "review" / "analysis-premortem.json"
    premortem_fix_log_path = proj / "review" / "analysis-premortem-fix-log.json"
    execution_path = proj / "analysis" / "execution-report.json"
    results_path = proj / "tables" / "results-registry.csv"
    figures_path = proj / "figures" / "figure-registry.csv"
    for required_path in (analysis_plan_path, spec_path, inventory_path, premortem_path, premortem_fix_log_path):
        if not required_path.exists():
            fail(f"FAIL: Phase 8 missing required input {required_path.relative_to(proj)}")
    try:
        ident = json.loads((proj / "design" / "identification-strategy.json").read_text())
        inventory = json.loads(inventory_path.read_text())
        premortem = json.loads(premortem_path.read_text())
        premortem_fix_log = json.loads(premortem_fix_log_path.read_text())
        execution = json.loads(execution_path.read_text())
    except Exception as exc:
        fail(f"FAIL: Phase 8 cannot read required JSON artifacts: {exc}")
    if premortem.get("verdict") != "PASS" or premortem.get("degraded") is not False:
        fail("FAIL: Phase 8 requires passing non-degraded Phase 7 premortem")
    if premortem.get("ready_for_phase_8") is not True:
        fail("FAIL: Phase 8 requires Phase 7 ready_for_phase_8 true")
    go = premortem.get("go_no_go")
    if not isinstance(go, dict) or go.get("decision") != "GO" or go.get("ready_for_phase_8") is not True:
        fail("FAIL: Phase 8 requires Phase 7 go_no_go decision GO")
    if premortem_fix_log.get("final_verdict") != "PASS" or int(premortem_fix_log.get("unresolved_blocking_count", -1)) != 0:
        fail("FAIL: Phase 8 requires passing Phase 7 fix log")
    handoff = premortem.get("phase8_handoff")
    if not isinstance(handoff, dict):
        fail("FAIL: Phase 8 requires phase8_handoff from Phase 7 premortem")
    handoff_scripts = [str(item).strip() for item in handoff.get("script_order", [])]
    expected_outputs = {str(item).strip() for item in handoff.get("expected_outputs", [])}
    expected_halt_checks = {str(item).strip() for item in handoff.get("halt_checks", [])}
    if not handoff_scripts:
        fail("FAIL: Phase 8 handoff script_order is empty")
    planned_scripts = inventory.get("scripts")
    if not isinstance(planned_scripts, list) or not planned_scripts:
        fail("FAIL: Phase 8 requires non-empty planned scripts from scripts-inventory.json")
    planned_script_paths = {
        str(script.get("path", "")).strip()
        for script in planned_scripts
        if isinstance(script, dict) and script.get("path")
    }
    planned_outputs = set()
    for script in planned_scripts:
        if isinstance(script, dict) and isinstance(script.get("produces"), list):
            planned_outputs.update(str(item).strip() for item in script["produces"] if str(item).strip())
    if set(handoff_scripts) != planned_script_paths:
        fail("FAIL: Phase 8 handoff scripts do not match scripts inventory")
    missing_script_files = [path for path in handoff_scripts if not (proj / path).exists()]
    if missing_script_files:
        fail("FAIL: Phase 8 planned scripts must exist before execution", missing_script_files)
    planned_tests = inventory.get("test_inventory")
    if not isinstance(planned_tests, list) or not planned_tests:
        fail("FAIL: Phase 8 requires non-empty test_inventory from scripts-inventory.json")
    planned_test_ids = {
        str(test.get("id", "")).strip()
        for test in planned_tests
        if isinstance(test, dict) and test.get("id")
    }
    try:
        with spec_path.open(newline="", encoding="utf-8") as f:
            spec_rows = list(csv.DictReader(f))
    except Exception as exc:
        fail(f"FAIL: Phase 8 cannot read analysis/spec-registry.csv: {exc}")
    planned_spec_ids = {str(row.get("spec_id", "")).strip() for row in spec_rows if row.get("spec_id")}
    if not planned_spec_ids:
        fail("FAIL: Phase 8 requires non-empty planned specs")
    if execution.get("verdict") != "PASS":
        fail(f"FAIL: Phase 8 execution verdict must be PASS, got {execution.get('verdict')}")
    if execution.get("degraded") is not False:
        fail("FAIL: Phase 8 degraded must be false")
    if execution.get("ready_for_phase_9") is not True:
        fail("FAIL: Phase 8 ready_for_phase_9 must be true")
    if execution.get("errors") != []:
        fail("FAIL: Phase 8 execution errors must be empty")
    method_family, expected_execution_skill, _method_components, routing_issues = validate_method_specialist_routing(
        ident.get("method_specialist_routing"),
        ident.get("method_specialist_routing", {}).get("method_orientation"),
        "Phase 8",
    )
    if routing_issues:
        fail("FAIL: Phase 8 cannot resolve routed specialist skill from Phase 3", routing_issues)
    execution_engine = execution.get("execution_engine")
    if not isinstance(execution_engine, dict):
        fail("FAIL: Phase 8 execution_engine must be an object")
    if execution_engine.get("skill") != expected_execution_skill or execution_engine.get("mode") != "execute_analysis":
        fail(f"FAIL: Phase 8 must record {expected_execution_skill} execute_analysis as execution_engine")
    execution_engine_issues = validate_engine_provenance(execution_engine, "Phase 8 execution_engine")
    if execution_engine_issues:
        fail("FAIL: Phase 8 execution_engine provenance is incomplete", execution_engine_issues)
    if execution_engine.get("auto_research_contract") != "phase_8":
        fail("FAIL: Phase 8 execution_engine.auto_research_contract must be phase_8")
    if execution_engine.get("phase7_handoff_only") is not True:
        fail("FAIL: Phase 8 execution_engine.phase7_handoff_only must be true")
    analysis_stack = execution.get("analysis_stack")
    if not isinstance(analysis_stack, dict):
        fail("FAIL: Phase 8 analysis_stack must be an object")
    stack_required_fields = {
        "primary_language",
        "table_engine",
        "figure_engine",
        "packages_used",
        "nonlinear_probability_models",
        "marginal_effects_engine",
        "viz_style_source",
        "viz_style_reference",
        "viz_style_sha256",
        "ggplot2_style_consistency",
        "reader_facing_label_source",
        "table_label_translation_applied",
        "figure_label_translation_applied",
        "deviation_justification",
    }
    missing_stack_fields = sorted(field for field in stack_required_fields if field not in analysis_stack)
    if missing_stack_fields:
        fail("FAIL: Phase 8 analysis_stack is missing required fields", missing_stack_fields)
    if method_family == "quantitative" and expected_execution_skill == "scholar-analyze":
        stack_issues = []
        primary_language = str(analysis_stack.get("primary_language", "")).strip()
        table_engine = str(analysis_stack.get("table_engine", "")).strip()
        figure_engine = str(analysis_stack.get("figure_engine", "")).strip()
        packages_used = analysis_stack.get("packages_used")
        nonlinear_probability_models = analysis_stack.get("nonlinear_probability_models")
        marginal_effects_engine = analysis_stack.get("marginal_effects_engine")
        viz_style_source = str(analysis_stack.get("viz_style_source", "")).strip()
        viz_style_reference = str(analysis_stack.get("viz_style_reference", "")).strip()
        viz_style_sha256 = str(analysis_stack.get("viz_style_sha256", "")).strip()
        reader_facing_label_source = str(analysis_stack.get("reader_facing_label_source", "")).strip()
        deviation_justification = str(analysis_stack.get("deviation_justification", "")).strip()
        if not isinstance(packages_used, list) or not packages_used:
            stack_issues.append("analysis_stack.packages_used must be a non-empty list")
            packages_lower = set()
        else:
            packages_lower = {str(item).strip().lower() for item in packages_used if str(item).strip()}
        if not isinstance(nonlinear_probability_models, bool):
            stack_issues.append("analysis_stack.nonlinear_probability_models must be boolean")
            nonlinear_probability_models = False
        executed_r_scripts = [path for path in handoff_scripts if path.endswith(".R")]
        if not executed_r_scripts:
            stack_issues.append("quantitative scholar-analyze route must execute at least one .R script")
        default_deviations = []
        if primary_language != "R":
            default_deviations.append("primary_language must default to R")
        if table_engine != "modelsummary":
            default_deviations.append("table_engine must default to modelsummary")
        if figure_engine != "ggplot2":
            default_deviations.append("figure_engine must default to ggplot2")
        if primary_language == "R" and table_engine == "modelsummary" and "modelsummary" not in packages_lower:
            stack_issues.append("analysis_stack.packages_used must include modelsummary")
        if primary_language == "R" and figure_engine == "ggplot2" and "ggplot2" not in packages_lower:
            stack_issues.append("analysis_stack.packages_used must include ggplot2")
        if reader_facing_label_source != "data/variable-dictionary.csv":
            stack_issues.append("analysis_stack.reader_facing_label_source must be data/variable-dictionary.csv")
        if analysis_stack.get("table_label_translation_applied") is not True:
            stack_issues.append("analysis_stack.table_label_translation_applied must be true")
        if analysis_stack.get("figure_label_translation_applied") is not True:
            stack_issues.append("analysis_stack.figure_label_translation_applied must be true")
        if nonlinear_probability_models:
            if marginal_effects_engine != "marginaleffects":
                default_deviations.append("nonlinear probability models must default to marginaleffects")
            if marginal_effects_engine == "marginaleffects" and "marginaleffects" not in packages_lower:
                stack_issues.append("analysis_stack.packages_used must include marginaleffects when nonlinear_probability_models is true")
        if figure_engine == "ggplot2":
            if viz_style_source != "analysis/scripts/viz_setting.R":
                stack_issues.append("analysis_stack.viz_style_source must be analysis/scripts/viz_setting.R when ggplot2 is the figure engine")
            if viz_style_reference != "references/viz_setting.R":
                stack_issues.append("analysis_stack.viz_style_reference must be references/viz_setting.R when ggplot2 is the figure engine")
            if analysis_stack.get("ggplot2_style_consistency") is not True:
                stack_issues.append("analysis_stack.ggplot2_style_consistency must be true when ggplot2 is the figure engine")
            viz_path = proj / "analysis" / "scripts" / "viz_setting.R"
            if not viz_path.exists():
                stack_issues.append("analysis/scripts/viz_setting.R must exist when ggplot2 is the figure engine")
            canonical_viz_path = (SCRIPT_DIR / ".." / "references" / "viz_setting.R").resolve()
            if not canonical_viz_path.exists():
                stack_issues.append("bundled references/viz_setting.R is missing from scholar-auto-research")
            elif viz_path.exists():
                canonical_viz_hash = sha256(canonical_viz_path)
                if sha256(viz_path) != canonical_viz_hash:
                    stack_issues.append("analysis/scripts/viz_setting.R must be copied from scholar-auto-research/references/viz_setting.R, not locally rewritten")
                if viz_style_sha256 != canonical_viz_hash:
                    stack_issues.append("analysis_stack.viz_style_sha256 must match bundled references/viz_setting.R")
        if default_deviations and word_count(deviation_justification) < 8:
            stack_issues.append("analysis_stack.deviation_justification must explain any departure from R/modelsummary/ggplot2/marginaleffects defaults")
        # Audit 2026-05-03: artifact-level enforcement of the table-engine
        # contract. The declaration above checks `table_engine == "modelsummary"`
        # and that "modelsummary" is in `packages_used`, but it does NOT verify
        # the analysis script CALLED the engine or that any rich-format file
        # landed in `tables/`. Real projects shipped tables/ with only CSVs.
        # The fallback list (stargazer, texreg, huxreg, gtsummary, gt,
        # fixest::etable, kableExtra) is accepted because modelsummary cannot
        # tidy every model class.
        tables_root = proj / "tables"
        if tables_root.is_dir():
            rich_files = []
            for ext in ("*.html", "*.tex", "*.docx"):
                rich_files.extend(p.name for p in tables_root.glob(ext) if p.is_file())
            if not rich_files:
                engine_call_pattern = re.compile(
                    r"(^|[^a-zA-Z._])("
                    r"modelsummary[a-zA-Z_]*|stargazer|texreg|htmlreg|screenreg|"
                    r"huxreg|hux_to_(html|latex|docx)|quick_html|quick_pdf|quick_docx|"
                    r"tbl_regression|tbl_summary|gt|gtsave|etable|kable|kbl"
                    r")\s*\(",
                    re.MULTILINE,
                )
                engine_called = False
                engine_names_called = set()
                script_dirs = [proj / "analysis" / "scripts", proj / "scripts"]
                for sdir in script_dirs:
                    if not sdir.is_dir():
                        continue
                    for script_path in sdir.rglob("*.R"):
                        try:
                            text = script_path.read_text(errors="ignore")
                        except OSError:
                            continue
                        for m in engine_call_pattern.finditer(text):
                            engine_called = True
                            engine_names_called.add(m.group(2))
                if engine_called:
                    stack_issues.append(
                        "tables/ contains no .html/.tex/.docx artifact even though export engine(s) "
                        f"[{', '.join(sorted(engine_names_called))}] were called — engine likely failed silently"
                    )
                else:
                    stack_issues.append(
                        "tables/ contains no .html/.tex/.docx artifact AND no supported export engine "
                        "(modelsummary, stargazer, texreg, huxreg, gtsummary, gt, fixest::etable, kableExtra) "
                        "is called by any analysis R script — regression tables must be exported as "
                        "publication-quality HTML/TeX/docx, not just CSV"
                    )
        if stack_issues:
            fail("FAIL: Phase 8 quantitative analysis stack is incomplete", stack_issues + default_deviations)
    run_context = execution.get("run_context")
    if not isinstance(run_context, dict):
        fail("FAIL: Phase 8 run_context must be an object")
    run_context_issues = []
    for field in ("started_at_utc", "completed_at_utc", "working_directory", "seed", "environment", "session_info"):
        if not run_context.get(field):
            run_context_issues.append(f"run_context.{field} missing")
    for field in ("started_at_utc", "completed_at_utc"):
        if run_context.get(field) and not re.match(r"^\d{4}-\d{2}-\d{2}T", str(run_context.get(field))):
            run_context_issues.append(f"run_context.{field} must be ISO-like UTC timestamp")
    working_dir = str(run_context.get("working_directory", "")).strip()
    if working_dir and Path(working_dir).is_absolute() and Path(working_dir) != proj:
        run_context_issues.append("run_context.working_directory must be project root or relative")
    if run_context_issues:
        fail("FAIL: Phase 8 run_context is incomplete", run_context_issues)
    source_hashes = execution.get("source_hashes")
    if not isinstance(source_hashes, dict):
        fail("FAIL: Phase 8 source_hashes must be an object")
    expected_hashes = {
        "analysis_plan": sha256(analysis_plan_path),
        "spec_registry": sha256(spec_path),
        "scripts_inventory": sha256(inventory_path),
        "analysis_premortem": sha256(premortem_path),
        "analysis_premortem_fix_log": sha256(premortem_fix_log_path),
    }
    hash_errors = [
        f"{key} mismatch"
        for key, expected in expected_hashes.items()
        if source_hashes.get(key) != expected
    ]
    if hash_errors:
        fail("FAIL: Phase 8 source hashes are stale or incomplete", hash_errors)
    phase7_source_hashes = premortem.get("source_hashes")
    if not isinstance(phase7_source_hashes, dict):
        fail("FAIL: Phase 8 requires Phase 7 premortem source_hashes")
    phase7_expected_hashes = {
        "analysis_plan": sha256(analysis_plan_path),
        "spec_registry": sha256(spec_path),
        "scripts_inventory": sha256(inventory_path),
        "pre_execution_review": sha256(proj / "review" / "pre-execution-review.json") if (proj / "review" / "pre-execution-review.json").exists() else None,
        "pre_execution_fix_log": sha256(proj / "review" / "pre-execution-fix-log.json") if (proj / "review" / "pre-execution-fix-log.json").exists() else None,
        "pre_execution_rereview": sha256(proj / "review" / "pre-execution-rereview.json") if (proj / "review" / "pre-execution-rereview.json").exists() else None,
    }
    phase7_hash_errors = [
        f"{key} mismatch"
        for key, expected in phase7_expected_hashes.items()
        if expected is not None and phase7_source_hashes.get(key) != expected
    ]
    if phase7_hash_errors:
        fail("FAIL: Phase 8 cannot execute because Phase 7 source hashes are stale", phase7_hash_errors)
    phase7_source_hash_check = execution.get("phase7_source_hash_check")
    if not isinstance(phase7_source_hash_check, dict):
        fail("FAIL: Phase 8 phase7_source_hash_check must be an object")
    if phase7_source_hash_check.get("status") != "PASS" or phase7_source_hash_check.get("checked") is not True:
        fail("FAIL: Phase 8 phase7_source_hash_check must PASS")
    checked_sources = set(phase7_source_hash_check.get("checked_sources", []) if isinstance(phase7_source_hash_check.get("checked_sources"), list) else [])
    required_phase7_sources = {key for key, expected in phase7_expected_hashes.items() if expected is not None}
    if checked_sources != required_phase7_sources:
        fail("FAIL: Phase 8 phase7_source_hash_check checked_sources must match Phase 7 hash sources")
    if phase7_source_hash_check.get("mismatches") not in ([], None):
        fail("FAIL: Phase 8 phase7_source_hash_check mismatches must be empty")
    phase7_go = execution.get("phase7_go")
    if not isinstance(phase7_go, dict) or phase7_go.get("decision") != "GO" or phase7_go.get("ready_for_phase_8") is not True:
        fail("FAIL: Phase 8 execution report must preserve Phase 7 GO decision")
    if phase7_go.get("route_back_phase") not in (None, ""):
        fail("FAIL: Phase 8 execution report cannot pass with route_back_phase set")
    executed_scripts = execution.get("executed_scripts")
    if not isinstance(executed_scripts, list):
        fail("FAIL: Phase 8 executed_scripts must be a list")
    executed_paths = [str(item.get("path", "")).strip() for item in executed_scripts if isinstance(item, dict)]
    if executed_paths != handoff_scripts:
        fail("FAIL: Phase 8 executed scripts must match Phase 7 handoff order exactly")
    command_trace = execution.get("command_trace")
    if not isinstance(command_trace, list):
        fail("FAIL: Phase 8 command_trace must be a list")
    trace_paths = [str(item.get("path", "")).strip() for item in command_trace if isinstance(item, dict)]
    if trace_paths != handoff_scripts:
        fail("FAIL: Phase 8 command_trace must match Phase 7 handoff order exactly")
    bad_trace = []
    for idx, item in enumerate(command_trace):
        if not isinstance(item, dict):
            bad_trace.append(f"command_trace[{idx}] is not an object")
            continue
        path = str(item.get("path", "")).strip()
        if Path(path).is_absolute() or path not in planned_script_paths:
            bad_trace.append(f"command_trace[{idx}].path invalid")
        for field in ("path", "command", "cwd", "started_at", "ended_at", "exit_code", "stdout_log", "stderr_log"):
            if field not in item or item.get(field) in (None, ""):
                bad_trace.append(f"command_trace[{idx}].{field} missing")
        if item.get("exit_code") != 0:
            bad_trace.append(f"command_trace[{idx}].exit_code={item.get('exit_code')}")
        for field in ("stdout_log", "stderr_log"):
            log_path = str(item.get(field, "")).strip()
            if Path(log_path).is_absolute() or not log_path or not (proj / log_path).exists():
                bad_trace.append(f"command_trace[{idx}].{field} must point to existing relative log")
    if bad_trace:
        fail("FAIL: Phase 8 command_trace is invalid", bad_trace)
    bad_exec = []
    for idx, item in enumerate(executed_scripts):
        if not isinstance(item, dict):
            bad_exec.append(f"executed_scripts[{idx}] is not an object")
            continue
        path = str(item.get("path", "")).strip()
        script_path = proj / path
        if Path(path).is_absolute():
            bad_exec.append(f"executed_scripts[{idx}].path must be relative")
        for field in ("path", "command", "script_hash", "exit_code", "status", "started_at", "ended_at", "outputs", "output_hashes"):
            if field not in item or item.get(field) in (None, ""):
                bad_exec.append(f"executed_scripts[{idx}].{field} missing")
        if item.get("exit_code") != 0:
            bad_exec.append(f"executed_scripts[{idx}].exit_code={item.get('exit_code')}")
        if item.get("status") != "success":
            bad_exec.append(f"executed_scripts[{idx}].status={item.get('status')}")
        if script_path.exists() and item.get("script_hash") != sha256(script_path):
            bad_exec.append(f"executed_scripts[{idx}].script_hash mismatch")
        outputs = item.get("outputs")
        if not isinstance(outputs, list):
            bad_exec.append(f"executed_scripts[{idx}].outputs must be list")
        else:
            missing_outputs = [rel for rel in outputs if rel and not (proj / str(rel)).exists()]
            bad_exec.extend(f"executed_scripts[{idx}] missing output {rel}" for rel in missing_outputs)
            output_hashes = item.get("output_hashes")
            if not isinstance(output_hashes, dict):
                bad_exec.append(f"executed_scripts[{idx}].output_hashes must be object")
            else:
                for rel in outputs:
                    rel = str(rel).strip()
                    if rel and (proj / rel).exists() and output_hashes.get(rel) != sha256(proj / rel):
                        bad_exec.append(f"executed_scripts[{idx}].output_hashes mismatch for {rel}")
    if bad_exec:
        fail("FAIL: Phase 8 executed script records are invalid", bad_exec)
    exit_codes = execution.get("exit_codes")
    if not isinstance(exit_codes, dict):
        fail("FAIL: Phase 8 exit_codes must be an object")
    expected_exit_codes = {path: 0 for path in handoff_scripts}
    normalized_exit_codes = {str(key).strip(): value for key, value in exit_codes.items()}
    if normalized_exit_codes != expected_exit_codes:
        fail("FAIL: Phase 8 exit_codes must map every executed script to 0")
    tests_run = execution.get("tests_run")
    if not isinstance(tests_run, list):
        fail("FAIL: Phase 8 tests_run must be a list")
    test_ids = {str(item.get("id", "") if isinstance(item, dict) else "").strip() for item in tests_run}
    if test_ids != planned_test_ids:
        missing = sorted(planned_test_ids - test_ids)
        extra = sorted(test_ids - planned_test_ids)
        fail("FAIL: Phase 8 tests_run must exactly cover planned tests", missing + extra)
    failed_tests = [
        str(item.get("id", idx))
        for idx, item in enumerate(tests_run)
        if not isinstance(item, dict) or item.get("status") != "pass"
    ]
    if failed_tests:
        fail("FAIL: Phase 8 tests did not all pass", failed_tests)
    halt_checks = execution.get("halt_checks")
    if not isinstance(halt_checks, list):
        fail("FAIL: Phase 8 halt_checks must be a list")
    halt_names = {str(item.get("check", "") if isinstance(item, dict) else "").strip() for item in halt_checks}
    if expected_halt_checks and halt_names != expected_halt_checks:
        missing = sorted(expected_halt_checks - halt_names)
        extra = sorted(halt_names - expected_halt_checks)
        fail("FAIL: Phase 8 halt_checks must exactly cover Phase 7 handoff checks", missing + extra)
    failed_halts = [
        str(item.get("check", idx))
        for idx, item in enumerate(halt_checks)
        if not isinstance(item, dict) or item.get("status") != "pass"
    ]
    if failed_halts:
        fail("FAIL: Phase 8 halt checks did not all pass", failed_halts)
    expected_output_items = execution.get("expected_outputs")
    if not isinstance(expected_output_items, list):
        fail("FAIL: Phase 8 expected_outputs must be a list")
    reported_expected_outputs = {
        str(item.get("path", "") if isinstance(item, dict) else item).strip()
        for item in expected_output_items
    }
    required_expected_outputs = expected_outputs | planned_outputs
    if required_expected_outputs and reported_expected_outputs != required_expected_outputs:
        missing = sorted(required_expected_outputs - reported_expected_outputs)
        extra = sorted(reported_expected_outputs - required_expected_outputs)
        fail("FAIL: Phase 8 expected_outputs must exactly cover Phase 7 handoff outputs", missing + extra)
    missing_expected_files = [rel for rel in required_expected_outputs if not (proj / rel).exists()]
    if missing_expected_files:
        fail("FAIL: Phase 8 expected output files are missing", sorted(missing_expected_files))
    try:
        with results_path.open(newline="", encoding="utf-8") as f:
            result_rows = list(csv.DictReader(f))
    except Exception as exc:
        fail(f"FAIL: Phase 8 cannot read tables/results-registry.csv: {exc}")
    result_required = {"spec_id", "model_id", "outcome", "predictor", "estimate", "std_error", "p_value", "n", "status", "output_file"}
    if not result_rows:
        fail("FAIL: Phase 8 results-registry.csv must contain rows")
    missing_result_columns = sorted(result_required - set(result_rows[0].keys()))
    if missing_result_columns:
        fail("FAIL: Phase 8 results-registry.csv missing required columns", missing_result_columns)
    result_spec_ids = {str(row.get("spec_id", "")).strip() for row in result_rows}
    if result_spec_ids != planned_spec_ids:
        missing = sorted(planned_spec_ids - result_spec_ids)
        extra = sorted(result_spec_ids - planned_spec_ids)
        fail("FAIL: Phase 8 results registry must exactly cover planned specs", missing + extra)
    bad_results = []
    for idx, row in enumerate(result_rows):
        status = str(row.get("status", "")).strip()
        spec_id = str(row.get("spec_id", "")).strip()
        if spec_id in planned_spec_ids and status not in ("completed", "success"):
            bad_results.append(f"row {idx} status={status}")
        if status in ("completed", "success"):
            try:
                float(row.get("estimate", ""))
                std_error = float(row.get("std_error", ""))
                p_value = float(row.get("p_value", ""))
                n = int(float(row.get("n", "")))
            except Exception:
                bad_results.append(f"row {idx} completed numeric fields invalid")
                continue
            if std_error < 0:
                bad_results.append(f"row {idx} std_error must be nonnegative")
            if not (0 <= p_value <= 1):
                bad_results.append(f"row {idx} p_value must be between 0 and 1")
            if n <= 0:
                bad_results.append(f"row {idx} n must be positive")
            output_file = str(row.get("output_file", "")).strip()
            if Path(output_file).is_absolute() or not output_file or not (proj / output_file).exists():
                bad_results.append(f"row {idx} output_file missing")
    if bad_results:
        fail("FAIL: Phase 8 results registry rows are invalid", bad_results)
    report_results = execution.get("results_registry")
    if not isinstance(report_results, dict) or report_results.get("path") != "tables/results-registry.csv":
        fail("FAIL: Phase 8 execution report results_registry path must be tables/results-registry.csv")
    if set(str(item).strip() for item in report_results.get("covered_spec_ids", [])) != planned_spec_ids:
        fail("FAIL: Phase 8 execution report results_registry must cover all planned specs")
    try:
        with figures_path.open(newline="", encoding="utf-8") as f:
            figure_rows = list(csv.DictReader(f))
    except Exception as exc:
        fail(f"FAIL: Phase 8 cannot read figures/figure-registry.csv: {exc}")
    figure_required = {"figure_id", "path", "source_script", "status", "description"}
    if not figure_rows:
        fail("FAIL: Phase 8 figure-registry.csv must contain at least one row")
    missing_figure_columns = sorted(figure_required - set(figure_rows[0].keys()))
    if missing_figure_columns:
        fail("FAIL: Phase 8 figure-registry.csv missing required columns", missing_figure_columns)
    bad_figures = []
    figure_ids = set()
    for idx, row in enumerate(figure_rows):
        figure_id = str(row.get("figure_id", "")).strip()
        status = str(row.get("status", "")).strip()
        figure_ids.add(figure_id)
        if not figure_id:
            bad_figures.append(f"row {idx} figure_id missing")
        if status not in ("completed", "no_figures_planned"):
            bad_figures.append(f"row {idx} status={status}")
        if status == "completed":
            fig_path = str(row.get("path", "")).strip()
            if Path(fig_path).is_absolute() or not fig_path or not (proj / fig_path).exists():
                bad_figures.append(f"row {idx} completed figure path missing")
            if str(row.get("source_script", "")).strip() not in planned_script_paths:
                bad_figures.append(f"row {idx} source_script not in planned scripts")
        if not row.get("description"):
            bad_figures.append(f"row {idx} description missing")
    if bad_figures:
        fail("FAIL: Phase 8 figure registry rows are invalid", bad_figures)
    if method_family == "quantitative" and expected_execution_skill == "scholar-analyze" and str(analysis_stack.get("figure_engine", "")).strip() == "ggplot2":
        ggplot_issues = []
        for row in figure_rows:
            if str(row.get("status", "")).strip() != "completed":
                continue
            source_script = str(row.get("source_script", "")).strip()
            if not source_script.endswith(".R"):
                continue
            script_text = (proj / source_script).read_text(errors="ignore")
            if "theme_Publication" not in script_text:
                ggplot_issues.append(f"{source_script}: missing theme_Publication usage")
            if "viz_setting.R" not in script_text or "source(" not in script_text:
                ggplot_issues.append(f"{source_script}: missing viz_setting.R source call")
        if ggplot_issues:
            fail("FAIL: Phase 8 ggplot2 figure scripts are not using the shared viz_setting.R style block", ggplot_issues)
    registered_figure_paths = {
        str(row.get("path", "")).strip()
        for row in figure_rows
        if str(row.get("status", "")).strip() == "completed"
    }
    unregistered_figures = []
    for path in (proj / "figures").iterdir():
        if path.is_file() and path.name != "figure-registry.csv":
            rel = str(path.relative_to(proj))
            if rel not in registered_figure_paths:
                unregistered_figures.append(rel)
    if unregistered_figures:
        fail("FAIL: Phase 8 found unregistered figure files", sorted(unregistered_figures))
    report_figures = execution.get("figure_registry")
    if not isinstance(report_figures, dict) or report_figures.get("path") != "figures/figure-registry.csv":
        fail("FAIL: Phase 8 execution report figure_registry path must be figures/figure-registry.csv")
    if set(str(item).strip() for item in report_figures.get("covered_figure_ids", [])) != figure_ids:
        fail("FAIL: Phase 8 execution report figure_registry must match figure registry IDs")
    artifact_manifest = execution.get("artifact_manifest")
    if not isinstance(artifact_manifest, list) or not artifact_manifest:
        fail("FAIL: Phase 8 artifact_manifest must be a non-empty list")
    manifest_by_path = {
        str(item.get("path", "")).strip(): item
        for item in artifact_manifest
        if isinstance(item, dict)
    }
    required_artifacts = {
        "tables/results-registry.csv",
        "figures/figure-registry.csv",
    } | required_expected_outputs
    for row in result_rows:
        output_file = str(row.get("output_file", "")).strip()
        if output_file:
            required_artifacts.add(output_file)
    for row in figure_rows:
        if str(row.get("status", "")).strip() == "completed":
            fig_path = str(row.get("path", "")).strip()
            if fig_path:
                required_artifacts.add(fig_path)
    for folder in ("tables", "figures"):
        base = proj / folder
        if base.exists():
            for path in base.rglob("*"):
                if path.is_file():
                    required_artifacts.add(str(path.relative_to(proj)))
    missing_artifacts = sorted(path for path in required_artifacts if path not in manifest_by_path)
    if missing_artifacts:
        fail("FAIL: Phase 8 artifact_manifest missing produced artifacts", missing_artifacts)
    allowed_roles = {
        "execution_report",
        "results_registry",
        "figure_registry",
        "result_table",
        "model_output",
        "main_regression_table",
        "sensitivity_regression_table",
        "regression_table",
        "descriptive_table",
        "reader_facing_descriptive_table",
        "figure_file",
        "diagnostic",
        "intermediate_data",
        "planned_model_calls",
    }
    bad_artifacts = []
    for idx, item in enumerate(artifact_manifest):
        if not isinstance(item, dict):
            bad_artifacts.append(f"artifact_manifest[{idx}] is not an object")
            continue
        path = str(item.get("path", "")).strip()
        if Path(path).is_absolute() or not path or not (proj / path).exists():
            bad_artifacts.append(f"artifact_manifest[{idx}].path invalid")
            continue
        if item.get("sha256") != sha256(proj / path):
            bad_artifacts.append(f"artifact_manifest[{idx}].sha256 mismatch")
        if item.get("artifact_role") not in allowed_roles:
            bad_artifacts.append(f"artifact_manifest[{idx}].artifact_role={item.get('artifact_role')}")
        if not item.get("produced_by"):
            bad_artifacts.append(f"artifact_manifest[{idx}].produced_by missing")
        if item.get("registered") is not True:
            bad_artifacts.append(f"artifact_manifest[{idx}].registered must be true")
    if bad_artifacts:
        fail("FAIL: Phase 8 artifact_manifest rows are invalid", bad_artifacts)
    if (
        method_family == "quantitative"
        and expected_execution_skill == "scholar-analyze"
        and quantitative_empirical_regression_table_required(
            analysis_plan_path.read_text(errors="ignore"),
            analysis_stack,
            spec_rows,
            execution,
        )
    ):
        publication_tables = execution.get("publication_regression_tables")
        table_issues = []
        if not isinstance(publication_tables, list) or not publication_tables:
            table_issues.append("execution-report.publication_regression_tables must list canonical regression table artifacts")
        else:
            main_table_seen = False
            for idx, table in enumerate(publication_tables):
                if not isinstance(table, dict):
                    table_issues.append(f"publication_regression_tables[{idx}] is not an object")
                    continue
                path = str(table.get("path", "")).strip()
                role = str(table.get("role", "")).strip()
                if role in {"main_regression_table", "regression_table"}:
                    main_table_seen = True
                if role not in REGRESSION_TABLE_ROLES:
                    table_issues.append(f"{path or idx}: role must be a regression table role")
                if not path or Path(path).is_absolute() or not path.startswith("tables/") or not (proj / path).exists():
                    table_issues.append(f"{path or idx}: path must exist under tables/")
                    continue
                if source_is_registry_like(path) or Path(path).suffix.lower() == ".csv":
                    table_issues.append(f"{path}: registry/CSV extracts cannot satisfy publication_regression_tables")
                table_text = (proj / path).read_text(errors="ignore")
                label_hits = reader_internal_spec_index_hits(table_text)
                if label_hits:
                    table_issues.append(f"{path}: reader-facing regression table exposes internal spec IDs; use Model 1/Model 2 or M1/M2 labels ({'; '.join(label_hits[:3])})")
                manifest_item = manifest_by_path.get(path)
                if not manifest_item:
                    table_issues.append(f"{path}: missing from artifact_manifest")
                elif str(manifest_item.get("artifact_role", "")).strip() not in REGRESSION_TABLE_ROLES:
                    table_issues.append(f"{path}: artifact_manifest role must be a regression table role")
                for field in ("table_engine", "source_script", "model_columns", "statistic_rows"):
                    if not table.get(field):
                        table_issues.append(f"{path}: publication_regression_tables.{field} missing")
                model_columns = table.get("model_columns")
                if isinstance(model_columns, list):
                    bad_model_columns = [
                        str(col).strip()
                        for col in model_columns
                        if re.fullmatch(r"S\d+[A-Za-z]?", str(col).strip(), flags=re.IGNORECASE)
                    ]
                    if bad_model_columns:
                        table_issues.append(f"{path}: model_columns use internal spec IDs {bad_model_columns}; use Model 1/Model 2 or M1/M2")
            if not main_table_seen:
                table_issues.append("publication_regression_tables must include a main_regression_table or regression_table")
        if table_issues:
            fail("FAIL: Phase 8 quantitative outputs lack a canonical publication regression table", table_issues)

if phase_id == "9":
    spec_path = proj / "analysis" / "spec-registry.csv"
    premortem_path = proj / "review" / "analysis-premortem.json"
    execution_path = proj / "analysis" / "execution-report.json"
    results_path = proj / "tables" / "results-registry.csv"
    figures_path = proj / "figures" / "figure-registry.csv"
    review_path = proj / "review" / "post-execution-review.json"
    review_md_path = proj / "review" / "post-execution-review.md"
    fix_log_path = proj / "review" / "post-execution-fix-log.json"
    for required_path in (spec_path, premortem_path, execution_path, results_path, figures_path):
        if not required_path.exists():
            fail(f"FAIL: Phase 9 missing required input {required_path.relative_to(proj)}")
    try:
        premortem = json.loads(premortem_path.read_text())
        execution = json.loads(execution_path.read_text())
        review = json.loads(review_path.read_text())
    except Exception as exc:
        fail(f"FAIL: Phase 9 cannot read required JSON artifacts: {exc}")
    if execution.get("verdict") != "PASS" or execution.get("degraded") is not False:
        fail("FAIL: Phase 9 requires passing non-degraded Phase 8 execution")
    if execution.get("ready_for_phase_9") is not True:
        fail("FAIL: Phase 9 requires Phase 8 ready_for_phase_9 true")
    if execution.get("errors") != []:
        fail("FAIL: Phase 9 cannot start with Phase 8 execution errors")
    if premortem.get("verdict") != "PASS" or premortem.get("ready_for_phase_8") is not True:
        fail("FAIL: Phase 9 requires passing Phase 7 premortem")
    try:
        with spec_path.open(newline="", encoding="utf-8") as f:
            spec_rows = list(csv.DictReader(f))
        with results_path.open(newline="", encoding="utf-8") as f:
            result_rows = list(csv.DictReader(f))
        with figures_path.open(newline="", encoding="utf-8") as f:
            figure_rows = list(csv.DictReader(f))
    except Exception as exc:
        fail(f"FAIL: Phase 9 cannot read registries: {exc}")
    planned_spec_ids = {str(row.get("spec_id", "")).strip() for row in spec_rows if row.get("spec_id")}
    result_spec_ids = {str(row.get("spec_id", "")).strip() for row in result_rows if row.get("spec_id")}
    figure_ids = {str(row.get("figure_id", "")).strip() for row in figure_rows if row.get("figure_id")}
    planned_hypothesis_ids = set()
    for row in spec_rows:
        raw_hypotheses = str(row.get("hypothesis_id") or row.get("hypothesis_ids") or "").strip()
        for hypothesis_id in re.split(r"[;,]", raw_hypotheses):
            hypothesis_id = hypothesis_id.strip()
            if hypothesis_id:
                planned_hypothesis_ids.add(hypothesis_id)
    if not planned_spec_ids:
        fail("FAIL: Phase 9 requires planned spec IDs")
    if result_spec_ids != planned_spec_ids:
        missing = sorted(planned_spec_ids - result_spec_ids)
        extra = sorted(result_spec_ids - planned_spec_ids)
        fail("FAIL: Phase 9 results registry must exactly cover planned specs", missing + extra)
    if review.get("verdict") != "PASS":
        fail(f"FAIL: Phase 9 verdict must be PASS, got {review.get('verdict')}")
    if review.get("degraded") is not False:
        fail("FAIL: Phase 9 degraded must be false")
    if review.get("decision") != "PROCEED_TO_RUNTIME_SANITY":
        fail(f"FAIL: Phase 9 decision must be PROCEED_TO_RUNTIME_SANITY, got {review.get('decision')}")
    if review.get("ready_for_phase_10") is not True:
        fail("FAIL: Phase 9 ready_for_phase_10 must be true")
    review_engine = review.get("review_engine")
    if not isinstance(review_engine, dict):
        fail("FAIL: Phase 9 review_engine must be an object")
    if review_engine.get("skill") != "scholar-verify" or review_engine.get("mode") != "stage1_no_manuscript":
        fail("FAIL: Phase 9 must invoke scholar-verify stage1_no_manuscript as review_engine")
    review_engine_issues = validate_engine_provenance(review_engine, "Phase 9 review_engine")
    if review_engine_issues:
        fail("FAIL: Phase 9 review_engine provenance is incomplete", review_engine_issues)
    if review_engine.get("auto_research_contract") != "phase_9":
        fail("FAIL: Phase 9 review_engine.auto_research_contract must be phase_9")
    if review_engine.get("read_live_outputs_pre_lock") is not True:
        fail("FAIL: Phase 9 review_engine.read_live_outputs_pre_lock must be true")
    source_hashes = review.get("source_hashes")
    if not isinstance(source_hashes, dict):
        fail("FAIL: Phase 9 source_hashes must be an object")
    expected_hashes = {
        "spec_registry": sha256(spec_path),
        "analysis_premortem": sha256(premortem_path),
        "execution_report": sha256(execution_path),
        "results_registry": sha256(results_path),
        "figure_registry": sha256(figures_path),
    }
    hash_errors = [
        f"{key} mismatch"
        for key, expected in expected_hashes.items()
        if source_hashes.get(key) != expected
    ]
    if hash_errors:
        fail("FAIL: Phase 9 source hashes are stale or incomplete", hash_errors)
    phase7_carryforward = review.get("phase7_constraint_carryforward")
    if not isinstance(phase7_carryforward, dict):
        fail("FAIL: Phase 9 phase7_constraint_carryforward must be an object")
    premortem_null = premortem.get("null_falsification_table")
    if not isinstance(premortem_null, list):
        fail("FAIL: Phase 9 requires Phase 7 null_falsification_table")
    premortem_hypotheses = {
        str(item.get("hypothesis_id", "")).strip()
        for item in premortem_null
        if isinstance(item, dict) and str(item.get("hypothesis_id", "")).strip()
    }
    if planned_hypothesis_ids and not planned_hypothesis_ids.issubset(premortem_hypotheses):
        fail("FAIL: Phase 9 Phase 7 null-falsification table does not cover planned hypotheses", sorted(planned_hypothesis_ids - premortem_hypotheses))
    carry_hypotheses = set(phase7_carryforward.get("checked_hypothesis_ids", []) if isinstance(phase7_carryforward.get("checked_hypothesis_ids"), list) else [])
    carry_issues = []
    if planned_hypothesis_ids and carry_hypotheses != planned_hypothesis_ids:
        carry_issues.append("checked_hypothesis_ids must match planned hypotheses")
    for field in ("null_falsification_checked", "reporting_depth_checked", "claim_constraints_reflect_phase7"):
        if phase7_carryforward.get(field) is not True:
            carry_issues.append(f"{field} must be true")
    if not phase7_carryforward.get("evidence"):
        carry_issues.append("evidence missing")
    if carry_issues:
        fail("FAIL: Phase 9 phase7_constraint_carryforward is incomplete", carry_issues)
    raw_verify = review.get("raw_output_verification")
    if not isinstance(raw_verify, dict):
        fail("FAIL: Phase 9 raw_output_verification must be an object")
    raw_issues = []
    if raw_verify.get("verdict") not in ("PASS", "CLEAN"):
        raw_issues.append(f"verdict={raw_verify.get('verdict')}")
    if raw_verify.get("stage") != "stage1_no_manuscript":
        raw_issues.append("stage must be stage1_no_manuscript")
    checked_tables = set(raw_verify.get("checked_raw_tables", []) if isinstance(raw_verify.get("checked_raw_tables"), list) else [])
    required_tables = {"tables/results-registry.csv"}
    for row in result_rows:
        output_file = str(row.get("output_file", "")).strip()
        if output_file:
            required_tables.add(output_file)
    if not required_tables.issubset(checked_tables):
        raw_issues.append(f"checked_raw_tables missing {sorted(required_tables - checked_tables)}")
    checked_figures = set(raw_verify.get("checked_figures", []) if isinstance(raw_verify.get("checked_figures"), list) else [])
    required_figures = {
        str(row.get("path", "")).strip()
        for row in figure_rows
        if str(row.get("status", "")).strip() == "completed" and str(row.get("path", "")).strip()
    }
    if required_figures and not required_figures.issubset(checked_figures):
        raw_issues.append(f"checked_figures missing {sorted(required_figures - checked_figures)}")
    if raw_verify.get("registry_consistency") is not True:
        raw_issues.append("registry_consistency must be true")
    if required_figures and raw_verify.get("visual_figure_inspection") is not True:
        raw_issues.append("visual_figure_inspection must be true when figures exist")
    if int(raw_verify.get("critical_count", -1)) != 0:
        raw_issues.append("critical_count must be 0")
    report_path = str(raw_verify.get("report_path", "")).strip()
    if Path(report_path).is_absolute() or not report_path or not (proj / report_path).exists():
        raw_issues.append("report_path must point to an existing relative file")
    if raw_issues:
        fail("FAIL: Phase 9 raw_output_verification is incomplete", raw_issues)
    phase8_status = review.get("phase8_status")
    if not isinstance(phase8_status, dict):
        fail("FAIL: Phase 9 phase8_status must be an object")
    if phase8_status.get("verdict") != "PASS" or phase8_status.get("ready_for_phase_9") is not True:
        fail("FAIL: Phase 9 phase8_status must confirm Phase 8 PASS and readiness")
    if phase8_status.get("errors_empty") is not True:
        fail("FAIL: Phase 9 phase8_status.errors_empty must be true")
    required_roles = {"statistical_results", "robustness_consistency", "sample_data_integrity", "interpretation_claims"}
    reviewers = review.get("reviewers")
    if not isinstance(reviewers, list) or len(reviewers) < len(required_roles):
        fail("FAIL: Phase 9 requires at least four independent post-execution reviewers")
    reviewer_provenance = review.get("reviewer_provenance")
    if not isinstance(reviewer_provenance, list) or len(reviewer_provenance) < len(required_roles):
        fail("FAIL: Phase 9 reviewer_provenance must cover all post-execution reviewers")
    provenance_roles = set()
    provenance_ids = set()
    bad_provenance = []
    for idx, item in enumerate(reviewer_provenance):
        if not isinstance(item, dict):
            bad_provenance.append(f"reviewer_provenance[{idx}] is not an object")
            continue
        role = str(item.get("role", "")).strip()
        reviewer_id = str(item.get("reviewer_id", "")).strip()
        agent_name = str(item.get("agent_name", "")).strip()
        task_id = str(item.get("task_invocation_id", "")).strip()
        dispatched_at = str(item.get("dispatched_at_utc", "")).strip()
        model_id = str(item.get("model_id", "")).strip()
        report_path = str(item.get("report_path", "")).strip()
        provenance_roles.add(role)
        provenance_ids.add(reviewer_id)
        if role not in required_roles:
            bad_provenance.append(f"reviewer_provenance[{idx}].role={role}")
        if reviewer_id.lower() in {"", "tbd", "todo", "unknown", "n/a", "na", "placeholder"}:
            bad_provenance.append(f"reviewer_provenance[{idx}].reviewer_id missing")
        if agent_name.lower() in {"", "tbd", "todo", "unknown", "n/a", "na", "placeholder"}:
            bad_provenance.append(f"reviewer_provenance[{idx}].agent_name missing")
        if task_id.lower() in {"", "tbd", "todo", "unknown", "n/a", "na", "placeholder"}:
            bad_provenance.append(f"reviewer_provenance[{idx}].task_invocation_id missing")
        if not re.match(r"^\d{4}-\d{2}-\d{2}T", dispatched_at):
            bad_provenance.append(f"reviewer_provenance[{idx}].dispatched_at_utc must be ISO-like UTC timestamp")
        if model_id.lower() in {"", "tbd", "todo", "unknown", "n/a", "na", "placeholder"}:
            bad_provenance.append(f"reviewer_provenance[{idx}].model_id missing")
        if not report_path:
            bad_provenance.append(f"reviewer_provenance[{idx}].report_path missing")
        elif Path(report_path).is_absolute() or not (proj / report_path).exists():
            bad_provenance.append(f"reviewer_provenance[{idx}].report_path not found in project")
    if required_roles - provenance_roles:
        bad_provenance.extend(f"missing provenance role {role}" for role in sorted(required_roles - provenance_roles))
    if bad_provenance:
        fail("FAIL: Phase 9 reviewer provenance is incomplete", bad_provenance)
    roles = set()
    reviewer_ids = set()
    task_ids = set()
    bad_reviewers = []
    placeholder_values = {"", "tbd", "todo", "unknown", "n/a", "na", "placeholder"}
    for idx, reviewer in enumerate(reviewers):
        if not isinstance(reviewer, dict):
            bad_reviewers.append(f"reviewers[{idx}] is not an object")
            continue
        role = str(reviewer.get("role", "")).strip()
        reviewer_id = str(reviewer.get("reviewer_id", "")).strip()
        task_id = str(reviewer.get("task_invocation_id", "")).strip()
        agent_type = str(reviewer.get("agent_type", "")).strip()
        report_path = str(reviewer.get("report_path", "")).strip()
        roles.add(role)
        if reviewer_id.lower() in placeholder_values:
            bad_reviewers.append(f"reviewers[{idx}].reviewer_id missing")
        elif reviewer_id in reviewer_ids:
            bad_reviewers.append(f"reviewers[{idx}].reviewer_id duplicate")
        reviewer_ids.add(reviewer_id)
        if task_id.lower() in placeholder_values:
            bad_reviewers.append(f"reviewers[{idx}].task_invocation_id missing")
        elif task_id in task_ids:
            bad_reviewers.append(f"reviewers[{idx}].task_invocation_id duplicate")
        task_ids.add(task_id)
        if agent_type.lower() in placeholder_values:
            bad_reviewers.append(f"reviewers[{idx}].agent_type missing")
        if not report_path:
            bad_reviewers.append(f"reviewers[{idx}].report_path missing")
        elif Path(report_path).is_absolute() or not (proj / report_path).exists():
            bad_reviewers.append(f"reviewers[{idx}].report_path not found in project")
        if reviewer.get("verdict") not in ("PASS", "PASS_WITH_NONBLOCKING_NOTES"):
            bad_reviewers.append(f"reviewers[{idx}].verdict={reviewer.get('verdict')}")
        reviewed_specs = reviewer.get("reviewed_specs")
        if not isinstance(reviewed_specs, list) or {str(item).strip() for item in reviewed_specs} != planned_spec_ids:
            bad_reviewers.append(f"reviewers[{idx}].reviewed_specs must cover every planned spec")
        reviewed_figures = reviewer.get("reviewed_figures")
        if not isinstance(reviewed_figures, list) or {str(item).strip() for item in reviewed_figures} != figure_ids:
            bad_reviewers.append(f"reviewers[{idx}].reviewed_figures must cover every figure registry row")
        if not isinstance(reviewer.get("findings"), list):
            bad_reviewers.append(f"reviewers[{idx}].findings must be list")
    missing_roles = sorted(required_roles - roles)
    if missing_roles:
        bad_reviewers.extend(f"missing role {role}" for role in missing_roles)
    if reviewer_ids != provenance_ids:
        bad_reviewers.append("reviewer ids must match reviewer_provenance ids")
    if bad_reviewers:
        fail("FAIL: Phase 9 reviewer panel is incomplete or not independent", bad_reviewers)
    reviewed_specs = review.get("reviewed_specs")
    if not isinstance(reviewed_specs, list):
        fail("FAIL: Phase 9 reviewed_specs must be a list")
    reviewed_spec_ids = {
        str(item.get("spec_id", "") if isinstance(item, dict) else item).strip()
        for item in reviewed_specs
    }
    if reviewed_spec_ids != planned_spec_ids:
        missing = sorted(planned_spec_ids - reviewed_spec_ids)
        extra = sorted(reviewed_spec_ids - planned_spec_ids)
        fail("FAIL: Phase 9 reviewed_specs must exactly cover planned specs", missing + extra)
    result_by_spec = {
        str(row.get("spec_id", "")).strip(): row
        for row in result_rows
        if str(row.get("spec_id", "")).strip()
    }
    bad_spec_reviews = []
    for idx, item in enumerate(reviewed_specs):
        if not isinstance(item, dict):
            bad_spec_reviews.append(f"reviewed_specs[{idx}] is not an object")
            continue
        for field in ("spec_id", "planned_direction", "observed_direction", "estimate", "std_error", "p_value", "ci_low", "ci_high", "n", "sample_id", "technical_validity", "substantive_classification", "interpretation_constraint", "allowed_claim_verbs"):
            if not item.get(field):
                bad_spec_reviews.append(f"reviewed_specs[{idx}].{field} missing")
        if item.get("review_verdict") not in ("PASS", "PASS_WITH_INTERPRETATION_CONSTRAINT"):
            bad_spec_reviews.append(f"reviewed_specs[{idx}].review_verdict={item.get('review_verdict')}")
        if item.get("technical_validity") is not True:
            bad_spec_reviews.append(f"reviewed_specs[{idx}].technical_validity must be true")
        if not isinstance(item.get("allowed_claim_verbs"), list) or not item.get("allowed_claim_verbs"):
            bad_spec_reviews.append(f"reviewed_specs[{idx}].allowed_claim_verbs must be non-empty list")
        result_row = result_by_spec.get(str(item.get("spec_id", "")).strip())
        if result_row:
            for field, result_field in (("estimate", "estimate"), ("std_error", "std_error"), ("p_value", "p_value"), ("n", "n")):
                try:
                    reviewed_value = float(item.get(field))
                    result_value = float(result_row.get(result_field))
                except Exception:
                    bad_spec_reviews.append(f"reviewed_specs[{idx}].{field} cannot compare to results registry")
                    continue
                if abs(reviewed_value - result_value) > 1e-9:
                    bad_spec_reviews.append(f"reviewed_specs[{idx}].{field} differs from results registry")
            try:
                estimate = float(result_row.get("estimate", ""))
                observed_direction = str(item.get("observed_direction", "")).strip().lower()
                expected_direction = "positive" if estimate > 0 else "negative" if estimate < 0 else "zero"
                if observed_direction != expected_direction:
                    bad_spec_reviews.append(f"reviewed_specs[{idx}].observed_direction={observed_direction} but estimate is {expected_direction}")
            except Exception:
                pass
    if bad_spec_reviews:
        fail("FAIL: Phase 9 reviewed_specs entries are incomplete", bad_spec_reviews)
    reviewed_figures = review.get("reviewed_figures")
    if not isinstance(reviewed_figures, list):
        fail("FAIL: Phase 9 reviewed_figures must be a list")
    reviewed_figure_ids = {
        str(item.get("figure_id", "") if isinstance(item, dict) else item).strip()
        for item in reviewed_figures
    }
    if reviewed_figure_ids != figure_ids:
        missing = sorted(figure_ids - reviewed_figure_ids)
        extra = sorted(reviewed_figure_ids - figure_ids)
        fail("FAIL: Phase 9 reviewed_figures must exactly cover figure registry", missing + extra)
    figure_by_id = {
        str(row.get("figure_id", "")).strip(): row
        for row in figure_rows
        if str(row.get("figure_id", "")).strip()
    }
    bad_figure_reviews = []
    for idx, item in enumerate(reviewed_figures):
        if not isinstance(item, dict):
            bad_figure_reviews.append(f"reviewed_figures[{idx}] is not an object")
            continue
        fig_id = str(item.get("figure_id", "")).strip()
        row = figure_by_id.get(fig_id)
        if row and str(row.get("status", "")).strip() == "completed":
            source_path = str(item.get("source_path", "")).strip()
            expected_path = str(row.get("path", "")).strip()
            if source_path != expected_path:
                bad_figure_reviews.append(f"reviewed_figures[{idx}].source_path must match figure registry path")
            if source_path and (proj / source_path).exists() and item.get("sha256") != sha256(proj / source_path):
                bad_figure_reviews.append(f"reviewed_figures[{idx}].sha256 mismatch")
            if item.get("visual_inspection") is not True:
                bad_figure_reviews.append(f"reviewed_figures[{idx}].visual_inspection must be true")
            if word_count(str(item.get("caption_or_registry_match", ""))) < 5:
                bad_figure_reviews.append(f"reviewed_figures[{idx}].caption_or_registry_match too thin")
        if item.get("review_verdict") not in ("PASS", "PASS_WITH_INTERPRETATION_CONSTRAINT"):
            bad_figure_reviews.append(f"reviewed_figures[{idx}].review_verdict={item.get('review_verdict')}")
    if bad_figure_reviews:
        fail("FAIL: Phase 9 reviewed_figures entries are incomplete", bad_figure_reviews)
    sample_integrity = review.get("sample_integrity")
    if not isinstance(sample_integrity, dict):
        fail("FAIL: Phase 9 sample_integrity must be an object")
    for field in ("verdict", "initial_n", "analytic_n", "exclusion_count", "missingness_checked", "cluster_or_group_count", "weights_status", "minimum_cell_count"):
        if field not in sample_integrity:
            fail(f"FAIL: Phase 9 sample_integrity.{field} missing")
    if sample_integrity.get("verdict") != "PASS":
        fail(f"FAIL: Phase 9 sample_integrity verdict must be PASS, got {sample_integrity.get('verdict')}")
    try:
        initial_n = int(float(sample_integrity.get("initial_n")))
        analytic_n = int(float(sample_integrity.get("analytic_n")))
        minimum_cell_count = int(float(sample_integrity.get("minimum_cell_count")))
    except Exception:
        fail("FAIL: Phase 9 sample_integrity counts must be numeric")
    if analytic_n <= 0 or initial_n < analytic_n or minimum_cell_count <= 0:
        fail("FAIL: Phase 9 sample_integrity counts are invalid")
    if sample_integrity.get("missingness_checked") is not True:
        fail("FAIL: Phase 9 sample_integrity.missingness_checked must be true")
    interpretation = review.get("result_interpretation")
    if not isinstance(interpretation, dict):
        fail("FAIL: Phase 9 result_interpretation must be an object")
    for field in ("direction_summary", "strength_summary", "uncertainty_summary", "technically_valid", "claim_constraints"):
        if field not in interpretation:
            fail(f"FAIL: Phase 9 result_interpretation.{field} missing")
    if interpretation.get("technically_valid") is not True:
        fail("FAIL: Phase 9 technically_valid must be true to proceed")
    if not isinstance(interpretation.get("claim_constraints"), list) or not interpretation.get("claim_constraints"):
        fail("FAIL: Phase 9 result_interpretation.claim_constraints must be non-empty list")
    robustness = review.get("robustness_assessment")
    if not isinstance(robustness, dict):
        fail("FAIL: Phase 9 robustness_assessment must be an object")
    if robustness.get("verdict") not in ("PASS", "PASS_WITH_CONFLICTS_DISCLOSED"):
        fail(f"FAIL: Phase 9 robustness_assessment verdict invalid: {robustness.get('verdict')}")
    for field in ("conflicts", "interpretation_implications"):
        if field not in robustness:
            fail(f"FAIL: Phase 9 robustness_assessment.{field} missing")
    robustness_matrix = review.get("robustness_matrix")
    if not isinstance(robustness_matrix, list):
        fail("FAIL: Phase 9 robustness_matrix must be a list")
    bad_robustness = []
    for idx, item in enumerate(robustness_matrix):
        if not isinstance(item, dict):
            bad_robustness.append(f"robustness_matrix[{idx}] is not an object")
            continue
        for field in ("primary_spec_id", "comparison_spec_id", "conflict_type", "severity", "adjudication", "manuscript_instruction"):
            if not item.get(field):
                bad_robustness.append(f"robustness_matrix[{idx}].{field} missing")
        if item.get("primary_spec_id") not in planned_spec_ids or item.get("comparison_spec_id") not in planned_spec_ids:
            bad_robustness.append(f"robustness_matrix[{idx}] references unknown spec")
        if item.get("severity") in ("major", "critical", "blocker", "high") and not item.get("manuscript_instruction"):
            bad_robustness.append(f"robustness_matrix[{idx}] blocking conflict lacks manuscript instruction")
    if bad_robustness:
        fail("FAIL: Phase 9 robustness matrix is incomplete", bad_robustness)
    unexpected = review.get("unexpected_results")
    if not isinstance(unexpected, list):
        fail("FAIL: Phase 9 unexpected_results must be a list")
    bad_unexpected = []
    for idx, item in enumerate(unexpected):
        if not isinstance(item, dict):
            bad_unexpected.append(f"unexpected_results[{idx}] is not an object")
            continue
        for field in ("spec_id", "classification", "action", "manuscript_instruction"):
            if not item.get(field):
                bad_unexpected.append(f"unexpected_results[{idx}].{field} missing")
        if item.get("action") not in ("carry_forward_with_constraints", "route_back"):
            bad_unexpected.append(f"unexpected_results[{idx}].action={item.get('action')}")
        if item.get("action") in ("rerun_to_match_hypothesis", "rewrite_to_match_hypothesis"):
            bad_unexpected.append(f"unexpected_results[{idx}] cannot rerun/rewrite to match hypothesis")
        if item.get("action") == "route_back" and review.get("route_back_phase") in (None, ""):
            bad_unexpected.append(f"unexpected_results[{idx}] routes back but route_back_phase is empty")
    if bad_unexpected:
        fail("FAIL: Phase 9 unexpected result records are incomplete", bad_unexpected)
    unexpected_classes = {"null", "opposite_sign", "weak", "conflicting", "inconclusive"}
    spec_classes = {
        str(item.get("spec_id", "")).strip(): str(item.get("substantive_classification", "")).strip()
        for item in reviewed_specs
        if isinstance(item, dict)
    }
    expected_unexpected_specs = {spec for spec, cls in spec_classes.items() if cls in unexpected_classes}
    actual_unexpected_specs = {
        str(item.get("spec_id", "")).strip()
        for item in unexpected
        if isinstance(item, dict)
    }
    if expected_unexpected_specs - actual_unexpected_specs:
        fail("FAIL: Phase 9 unexpected/null/weak/conflicting specs must be listed in unexpected_results", sorted(expected_unexpected_specs - actual_unexpected_specs))
    claim_constraints = review.get("claim_constraints")
    if not isinstance(claim_constraints, dict):
        fail("FAIL: Phase 9 claim_constraints must be an object")
    for field in ("allowed_claim_verbs", "forbidden_claim_verbs", "required_disclosures"):
        if not isinstance(claim_constraints.get(field), list) or not claim_constraints.get(field):
            fail(f"FAIL: Phase 9 claim_constraints.{field} must be a non-empty list")
    forbidden = {str(item).lower() for item in claim_constraints.get("forbidden_claim_verbs", [])}
    if "prove" not in forbidden and "causes" not in forbidden:
        fail("FAIL: Phase 9 claim_constraints must forbid overstrong causal verbs")
    if int(review.get("critical_count", -1)) != 0:
        fail("FAIL: Phase 9 critical_count must be 0")
    if int(review.get("unresolved_blocking_count", -1)) != 0:
        fail("FAIL: Phase 9 unresolved_blocking_count must be 0")
    if review.get("route_back_phase") not in (None, ""):
        fail("FAIL: Phase 9 cannot pass while route_back_phase is set")
    fix_status = review.get("fix_status")
    if not isinstance(fix_status, dict):
        fail("FAIL: Phase 9 fix_status must be an object")
    if fix_status.get("all_blocking_fixed") is not True:
        fail("FAIL: Phase 9 fix_status.all_blocking_fixed must be true")
    if fix_status.get("fix_log") != "review/post-execution-fix-log.json":
        fail("FAIL: Phase 9 fix_status.fix_log must point to review/post-execution-fix-log.json")
    try:
        fix_log = json.loads(fix_log_path.read_text())
    except Exception as exc:
        fail(f"FAIL: Phase 9 post-execution-fix-log.json is not valid JSON: {exc}")
    if fix_log.get("required_fixes_completed") is not True:
        fail("FAIL: Phase 9 fix log required_fixes_completed must be true")
    if int(fix_log.get("unresolved_blocking_count", -1)) != 0:
        fail("FAIL: Phase 9 fix log unresolved_blocking_count must be 0")
    if fix_log.get("final_verdict") != "PASS":
        fail(f"FAIL: Phase 9 fix log final_verdict must be PASS, got {fix_log.get('final_verdict')}")
    fixed_findings = fix_log.get("fixed_findings")
    if not isinstance(fixed_findings, list):
        fail("FAIL: Phase 9 fix log fixed_findings must be a list")
    if fix_status.get("required") is True and not fixed_findings:
        fail("FAIL: Phase 9 fix_status.required is true but fixed_findings is empty")
    bad_fixes = []
    for idx, item in enumerate(fixed_findings):
        if not isinstance(item, dict):
            bad_fixes.append(f"fixed_findings[{idx}] is not an object")
            continue
        for field in ("finding_id", "status", "action_taken", "affected_files", "owner_phase"):
            if not item.get(field):
                bad_fixes.append(f"fixed_findings[{idx}].{field} missing")
        if item.get("status") not in ("fixed", "resolved", "mitigated"):
            bad_fixes.append(f"fixed_findings[{idx}].status={item.get('status')}")
    if bad_fixes:
        fail("FAIL: Phase 9 fix log entries are incomplete", bad_fixes)
    review_md_text = review_md_path.read_text(errors="ignore").lower()
    conflict_pattern = re.compile(r"(unresolved|remains|open).{0,60}(invalid|block|blocking|critical)|(invalid|block|blocking|critical).{0,60}(unresolved|remains|open)")
    if conflict_pattern.search(review_md_text):
        fail("FAIL: Phase 9 markdown summary contradicts JSON PASS status with unresolved blocker language")
    review_words = re.findall(r"\b\w+\b", review_md_path.read_text(errors="ignore"))
    if len(review_words) < 80:
        fail(f"FAIL: Phase 9 post-execution-review.md is too short, found {len(review_words)} words")

if phase_id == "10":
    spec_path = proj / "analysis" / "spec-registry.csv"
    execution_path = proj / "analysis" / "execution-report.json"
    results_path = proj / "tables" / "results-registry.csv"
    figures_path = proj / "figures" / "figure-registry.csv"
    post_review_path = proj / "review" / "post-execution-review.json"
    post_fix_log_path = proj / "review" / "post-execution-fix-log.json"
    sanity_path = proj / "verify" / "runtime-sanity.json"
    sanity_md_path = proj / "verify" / "runtime-sanity.md"
    for required_path in (spec_path, execution_path, results_path, figures_path, post_review_path, post_fix_log_path):
        if not required_path.exists():
            fail(f"FAIL: Phase 10 missing required input {required_path.relative_to(proj)}")
    try:
        execution = json.loads(execution_path.read_text())
        post_review = json.loads(post_review_path.read_text())
        post_fix_log = json.loads(post_fix_log_path.read_text())
        sanity = json.loads(sanity_path.read_text())
    except Exception as exc:
        fail(f"FAIL: Phase 10 cannot read required JSON artifacts: {exc}")
    if execution.get("verdict") != "PASS" or execution.get("ready_for_phase_9") is not True or execution.get("errors") != []:
        fail("FAIL: Phase 10 requires passing Phase 8 execution")
    if post_review.get("verdict") != "PASS" or post_review.get("decision") != "PROCEED_TO_RUNTIME_SANITY":
        fail("FAIL: Phase 10 requires Phase 9 decision PROCEED_TO_RUNTIME_SANITY")
    if post_review.get("ready_for_phase_10") is not True:
        fail("FAIL: Phase 10 requires Phase 9 ready_for_phase_10 true")
    if int(post_review.get("unresolved_blocking_count", -1)) != 0 or int(post_review.get("critical_count", -1)) != 0:
        fail("FAIL: Phase 10 cannot start with unresolved Phase 9 blockers")
    if post_fix_log.get("final_verdict") != "PASS" or int(post_fix_log.get("unresolved_blocking_count", -1)) != 0:
        fail("FAIL: Phase 10 requires passing Phase 9 fix log")
    post_source_hashes = post_review.get("source_hashes")
    if not isinstance(post_source_hashes, dict):
        fail("FAIL: Phase 10 requires Phase 9 source_hashes")
    post_expected_hashes = {
        "spec_registry": sha256(spec_path),
        "execution_report": sha256(execution_path),
        "results_registry": sha256(results_path),
        "figure_registry": sha256(figures_path),
    }
    premortem_path = proj / "review" / "analysis-premortem.json"
    if premortem_path.exists():
        post_expected_hashes["analysis_premortem"] = sha256(premortem_path)
    stale_post = [
        f"{key} mismatch"
        for key, expected in post_expected_hashes.items()
        if post_source_hashes.get(key) != expected
    ]
    if stale_post:
        fail("FAIL: Phase 10 Phase 9 review source hashes are stale", stale_post)
    try:
        with spec_path.open(newline="", encoding="utf-8") as f:
            spec_rows = list(csv.DictReader(f))
        with results_path.open(newline="", encoding="utf-8") as f:
            result_rows = list(csv.DictReader(f))
        with figures_path.open(newline="", encoding="utf-8") as f:
            figure_rows = list(csv.DictReader(f))
    except Exception as exc:
        fail(f"FAIL: Phase 10 cannot read registries: {exc}")
    planned_spec_ids = {str(row.get("spec_id", "")).strip() for row in spec_rows if row.get("spec_id")}
    result_spec_ids = {str(row.get("spec_id", "")).strip() for row in result_rows if row.get("spec_id")}
    figure_ids = {str(row.get("figure_id", "")).strip() for row in figure_rows if row.get("figure_id")}
    if planned_spec_ids != result_spec_ids:
        fail("FAIL: Phase 10 planned specs and result specs must match")
    spec_fingerprints = {}
    for row in spec_rows:
        spec_id = str(row.get("spec_id", "")).strip()
        if spec_id:
            normalized = json.dumps({k: str(v).strip() for k, v in sorted(row.items())}, sort_keys=True)
            spec_fingerprints[spec_id] = hashlib.sha256(normalized.encode("utf-8")).hexdigest()
    reviewed_specs = post_review.get("reviewed_specs")
    if not isinstance(reviewed_specs, list):
        fail("FAIL: Phase 10 requires Phase 9 reviewed_specs")
    reviewed_by_spec = {
        str(item.get("spec_id", "")).strip(): item
        for item in reviewed_specs
        if isinstance(item, dict)
    }
    bad_review_value_checks = []
    for idx, row in enumerate(result_rows):
        spec_id = str(row.get("spec_id", "")).strip()
        reviewed = reviewed_by_spec.get(spec_id)
        if not reviewed:
            bad_review_value_checks.append(f"result row {idx} missing Phase 9 reviewed spec")
            continue
        for field in ("estimate", "std_error", "p_value", "n"):
            try:
                row_value = float(row.get(field, ""))
                reviewed_value = float(reviewed.get(field, ""))
            except Exception:
                bad_review_value_checks.append(f"result row {idx} {field} cannot compare to Phase 9 review")
                continue
            if abs(row_value - reviewed_value) > 1e-9:
                bad_review_value_checks.append(f"result row {idx} {field} differs from Phase 9 review")
    if bad_review_value_checks:
        fail("FAIL: Phase 10 result values differ from Phase 9 reviewed specs", bad_review_value_checks)
    if sanity.get("verdict") != "PASS":
        fail(f"FAIL: Phase 10 verdict must be PASS, got {sanity.get('verdict')}")
    if sanity.get("degraded") is not False:
        fail("FAIL: Phase 10 degraded must be false")
    if sanity.get("decision") != "PROCEED_TO_RESULTS_LOCK":
        fail(f"FAIL: Phase 10 decision must be PROCEED_TO_RESULTS_LOCK, got {sanity.get('decision')}")
    if sanity.get("ready_for_phase_11") is not True:
        fail("FAIL: Phase 10 ready_for_phase_11 must be true")
    runtime_engine = sanity.get("runtime_engine")
    if not isinstance(runtime_engine, dict):
        fail("FAIL: Phase 10 runtime_engine must be an object")
    if runtime_engine.get("skill") != "scholar-auto-research":
        fail("FAIL: Phase 10 runtime_engine.skill must be scholar-auto-research")
    if runtime_engine.get("mode") != "runtime_sanity":
        fail("FAIL: Phase 10 runtime_engine.mode must be runtime_sanity")
    if runtime_engine.get("auto_research_contract") != "phase_10":
        fail("FAIL: Phase 10 runtime_engine.auto_research_contract must be phase_10")
    if runtime_engine.get("deterministic_gate") is not True:
        fail("FAIL: Phase 10 runtime_engine.deterministic_gate must be true")
    source_hashes = sanity.get("source_hashes")
    if not isinstance(source_hashes, dict):
        fail("FAIL: Phase 10 source_hashes must be an object")
    expected_hashes = {
        "spec_registry": sha256(spec_path),
        "execution_report": sha256(execution_path),
        "results_registry": sha256(results_path),
        "figure_registry": sha256(figures_path),
        "post_execution_review": sha256(post_review_path),
        "post_execution_fix_log": sha256(post_fix_log_path),
    }
    hash_errors = [
        f"{key} mismatch"
        for key, expected in expected_hashes.items()
        if source_hashes.get(key) != expected
    ]
    if hash_errors:
        fail("FAIL: Phase 10 source hashes are stale or incomplete", hash_errors)
    phase9_status = sanity.get("phase9_status")
    if not isinstance(phase9_status, dict):
        fail("FAIL: Phase 10 phase9_status must be an object")
    if phase9_status.get("verdict") != "PASS" or phase9_status.get("decision") != "PROCEED_TO_RUNTIME_SANITY":
        fail("FAIL: Phase 10 phase9_status must confirm Phase 9 PASS")
    if phase9_status.get("ready_for_phase_10") is not True:
        fail("FAIL: Phase 10 phase9_status.ready_for_phase_10 must be true")
    if int(phase9_status.get("critical_count", -1)) != 0:
        fail("FAIL: Phase 10 phase9_status critical_count must be 0")
    if int(phase9_status.get("unresolved_blocking_count", -1)) != 0:
        fail("FAIL: Phase 10 phase9_status unresolved_blocking_count must be 0")
    if phase9_status.get("route_back_phase") not in (None, ""):
        fail("FAIL: Phase 10 phase9_status route_back_phase must be null")
    carryforward = sanity.get("phase9_constraint_carryforward")
    if not isinstance(carryforward, dict):
        fail("FAIL: Phase 10 phase9_constraint_carryforward must be an object")
    if carryforward.get("unexpected_results_checked") is not True:
        fail("FAIL: Phase 10 must confirm Phase 9 unexpected_results were checked")
    if carryforward.get("claim_constraints_checked") is not True:
        fail("FAIL: Phase 10 must confirm Phase 9 claim_constraints were checked")
    phase9_unexpected_ids = {
        str(item.get("spec_id", "")).strip()
        for item in post_review.get("unexpected_results", [])
        if isinstance(item, dict) and str(item.get("spec_id", "")).strip()
    }
    carry_unexpected_ids = {
        str(item).strip()
        for item in carryforward.get("unexpected_result_spec_ids", [])
        if str(item).strip()
    }
    if carry_unexpected_ids != phase9_unexpected_ids:
        fail("FAIL: Phase 10 phase9_constraint_carryforward unexpected_result_spec_ids must match Phase 9")
    claim_constraints = post_review.get("claim_constraints")
    if not isinstance(claim_constraints, dict):
        fail("FAIL: Phase 10 requires Phase 9 claim_constraints")
    phase9_forbidden = {
        str(item).strip()
        for item in claim_constraints.get("forbidden_claim_verbs", [])
        if str(item).strip()
    }
    carry_forbidden = {
        str(item).strip()
        for item in carryforward.get("forbidden_claim_verbs", [])
        if str(item).strip()
    }
    if not phase9_forbidden or not phase9_forbidden.issubset(carry_forbidden):
        fail("FAIL: Phase 10 phase9_constraint_carryforward must preserve Phase 9 forbidden claim verbs")
    phase9_disclosures = {
        str(item).strip()
        for item in claim_constraints.get("required_disclosures", [])
        if str(item).strip()
    }
    carry_disclosures = {
        str(item).strip()
        for item in carryforward.get("required_disclosures", [])
        if str(item).strip()
    }
    if not phase9_disclosures or not phase9_disclosures.issubset(carry_disclosures):
        fail("FAIL: Phase 10 phase9_constraint_carryforward must preserve Phase 9 required disclosures")
    bad_runtime_numbers = []
    for idx, row in enumerate(result_rows):
        try:
            estimate = float(row.get("estimate", ""))
            std_error = float(row.get("std_error", ""))
            p_value = float(row.get("p_value", ""))
            n = int(float(row.get("n", "")))
        except Exception:
            bad_runtime_numbers.append(f"result row {idx} has nonnumeric runtime values")
            continue
        if not math.isfinite(estimate) or not math.isfinite(std_error) or not math.isfinite(p_value):
            bad_runtime_numbers.append(f"result row {idx} has non-finite runtime values")
        if std_error < 0:
            bad_runtime_numbers.append(f"result row {idx} has negative standard error")
        if not (0 <= p_value <= 1):
            bad_runtime_numbers.append(f"result row {idx} has p-value outside [0,1]")
        if n <= 0:
            bad_runtime_numbers.append(f"result row {idx} has nonpositive n")
    if bad_runtime_numbers:
        fail("FAIL: Phase 10 runtime numeric sanity failed", bad_runtime_numbers)
    sample_integrity = post_review.get("sample_integrity", {})
    try:
        analytic_n = int(float(sample_integrity.get("analytic_n", 0)))
        min_cell_n = int(float(sample_integrity.get("minimum_cell_count", 0)))
    except Exception:
        fail("FAIL: Phase 10 cannot read Phase 9 sample integrity counts")
    bad_sample_counts = []
    for idx, row in enumerate(result_rows):
        try:
            n = int(float(row.get("n", "")))
        except Exception:
            continue
        if analytic_n > 0 and n > analytic_n:
            bad_sample_counts.append(f"result row {idx} n exceeds analytic_n")
        if min_cell_n > 0 and n < min_cell_n:
            bad_sample_counts.append(f"result row {idx} n below minimum_cell_count")
    if bad_sample_counts:
        fail("FAIL: Phase 10 result sample counts violate Phase 9 sample integrity", bad_sample_counts)
    plausibility = sanity.get("plausibility")
    if not isinstance(plausibility, dict) or plausibility.get("verdict") != "PASS":
        fail("FAIL: Phase 10 plausibility verdict must be PASS")
    plausibility_checks = plausibility.get("checks")
    required_plausibility = {"numeric_finite", "sample_size", "p_value_range", "effect_magnitude", "interpretation_constraints"}
    if not isinstance(plausibility_checks, list):
        fail("FAIL: Phase 10 plausibility.checks must be a list")
    plausibility_domains = {str(item.get("domain", "")).strip() for item in plausibility_checks if isinstance(item, dict)}
    if not required_plausibility.issubset(plausibility_domains):
        fail("FAIL: Phase 10 plausibility checks missing required domains", sorted(required_plausibility - plausibility_domains))
    bad_plausibility = [
        str(item.get("domain", idx))
        for idx, item in enumerate(plausibility_checks)
        if not isinstance(item, dict) or item.get("status") != "PASS" or not item.get("evidence")
    ]
    if bad_plausibility:
        fail("FAIL: Phase 10 plausibility checks did not all pass", bad_plausibility)
    clean_room = sanity.get("clean_room")
    if not isinstance(clean_room, dict) or clean_room.get("verdict") != "PASS":
        fail("FAIL: Phase 10 clean_room verdict must be PASS")
    if clean_room.get("reviewed_artifacts_match") is not True:
        fail("FAIL: Phase 10 clean_room.reviewed_artifacts_match must be true")
    artifact_hashes = clean_room.get("artifact_hashes")
    if not isinstance(artifact_hashes, dict):
        fail("FAIL: Phase 10 clean_room.artifact_hashes must be an object")
    for key, expected in expected_hashes.items():
        if artifact_hashes.get(key) != expected:
            fail("FAIL: Phase 10 clean_room artifact hash mismatch", [key])
    clean_run = clean_room.get("run")
    if not isinstance(clean_run, dict) or clean_run.get("verdict") != "PASS":
        fail("FAIL: Phase 10 clean_room.run verdict must be PASS")
    for field in ("mode", "commands", "exit_codes", "input_hashes", "output_hashes", "numeric_tolerance", "seed", "session_info"):
        if field not in clean_run:
            fail(f"FAIL: Phase 10 clean_room.run.{field} missing")
    if not isinstance(clean_run.get("commands"), list) or not clean_run.get("commands"):
        fail("FAIL: Phase 10 clean_room.run.commands must be non-empty list")
    if any(code != 0 for code in clean_run.get("exit_codes", {}).values()):
        fail("FAIL: Phase 10 clean_room.run exit_codes must all be 0")
    if not isinstance(clean_run.get("output_hashes"), dict) or not clean_run.get("output_hashes"):
        fail("FAIL: Phase 10 clean_room.run.output_hashes must be non-empty object")
    execution_output_hashes = {}
    for item in execution.get("executed_scripts", []):
        if isinstance(item, dict) and isinstance(item.get("output_hashes"), dict):
            execution_output_hashes.update(item["output_hashes"])
    for rel, expected in execution_output_hashes.items():
        if (proj / rel).exists() and sha256(proj / rel) != expected:
            fail("FAIL: Phase 10 output hash differs from Phase 8 execution report", [rel])
        if clean_run["output_hashes"].get(rel) != expected:
            fail("FAIL: Phase 10 clean-room output hash differs from Phase 8 execution report", [rel])
    phase8_manifest = execution.get("artifact_manifest")
    if not isinstance(phase8_manifest, list) or not phase8_manifest:
        fail("FAIL: Phase 10 requires Phase 8 artifact_manifest")
    phase8_manifest_paths = set()
    bad_phase8_manifest = []
    for idx, item in enumerate(phase8_manifest):
        if not isinstance(item, dict):
            bad_phase8_manifest.append(f"artifact_manifest[{idx}] is not an object")
            continue
        rel = str(item.get("path", "")).strip()
        if Path(rel).is_absolute() or not rel or not (proj / rel).exists():
            bad_phase8_manifest.append(f"artifact_manifest[{idx}].path invalid")
            continue
        phase8_manifest_paths.add(rel)
        if not item.get("sha256") or item.get("sha256") != sha256(proj / rel):
            bad_phase8_manifest.append(f"{rel} sha256 mismatch")
        if item.get("registered") is not True:
            bad_phase8_manifest.append(f"{rel} registered must be true")
    if bad_phase8_manifest:
        fail("FAIL: Phase 10 Phase 8 artifact_manifest is stale or invalid", bad_phase8_manifest)
    invariants = sanity.get("invariants")
    if not isinstance(invariants, dict) or invariants.get("verdict") != "PASS":
        fail("FAIL: Phase 10 invariants verdict must be PASS")
    invariant_checks = invariants.get("checks")
    required_invariants = {
        "planned_specs_equal_results",
        "execution_report_matches_registries",
        "expected_outputs_exist",
        "figure_registry_complete",
        "post_execution_review_current",
        "phase8_artifact_manifest_current",
        "phase9_constraints_current",
    }
    if not isinstance(invariant_checks, list):
        fail("FAIL: Phase 10 invariants.checks must be a list")
    invariant_domains = {str(item.get("name", "")).strip() for item in invariant_checks if isinstance(item, dict)}
    if not required_invariants.issubset(invariant_domains):
        fail("FAIL: Phase 10 invariant checks missing required names", sorted(required_invariants - invariant_domains))
    bad_invariants = [
        str(item.get("name", idx))
        for idx, item in enumerate(invariant_checks)
        if not isinstance(item, dict) or item.get("status") != "PASS" or not item.get("evidence")
    ]
    if bad_invariants:
        fail("FAIL: Phase 10 invariant checks did not all pass", bad_invariants)
    pap_drift = sanity.get("pap_drift")
    if not isinstance(pap_drift, dict) or pap_drift.get("verdict") != "PASS":
        fail("FAIL: Phase 10 pap_drift verdict must be PASS")
    planned_from_pap = {str(item).strip() for item in pap_drift.get("planned_spec_ids", [])}
    executed_from_pap = {str(item).strip() for item in pap_drift.get("executed_spec_ids", [])}
    if planned_from_pap != planned_spec_ids or executed_from_pap != result_spec_ids:
        fail("FAIL: Phase 10 pap_drift spec IDs must match planned and executed specs")
    pap_fingerprints = pap_drift.get("spec_fingerprints")
    if not isinstance(pap_fingerprints, dict) or pap_fingerprints != spec_fingerprints:
        fail("FAIL: Phase 10 pap_drift spec_fingerprints must match current spec registry")
    if int(pap_drift.get("unresolved_drift_count", -1)) != 0:
        fail("FAIL: Phase 10 pap_drift unresolved_drift_count must be 0")
    drift_items = pap_drift.get("drift_items")
    if not isinstance(drift_items, list):
        fail("FAIL: Phase 10 pap_drift.drift_items must be a list")
    unresolved_drift = [
        str(item.get("drift_id", idx))
        for idx, item in enumerate(drift_items)
        if not isinstance(item, dict) or item.get("status") not in ("none", "resolved", "nonblocking_documented")
    ]
    if unresolved_drift:
        fail("FAIL: Phase 10 unresolved PAP/plan drift remains", unresolved_drift)
    artifact_inventory = sanity.get("artifact_inventory")
    if not isinstance(artifact_inventory, list) or not artifact_inventory:
        fail("FAIL: Phase 10 artifact_inventory must be a non-empty list")
    inventory_paths = {str(item.get("path", "")).strip() for item in artifact_inventory if isinstance(item, dict)}
    required_inventory_paths = {
        "analysis/execution-report.json",
        "tables/results-registry.csv",
        "figures/figure-registry.csv",
        "review/post-execution-review.json",
    }
    for row in result_rows:
        output_file = str(row.get("output_file", "")).strip()
        if output_file:
            required_inventory_paths.add(output_file)
    for row in figure_rows:
        if str(row.get("status", "")).strip() == "completed":
            fig_path = str(row.get("path", "")).strip()
            if fig_path:
                required_inventory_paths.add(fig_path)
    for folder in ("tables", "figures"):
        base = proj / folder
        if base.exists():
            for path in base.rglob("*"):
                if path.is_file():
                    required_inventory_paths.add(str(path.relative_to(proj)))
    if not required_inventory_paths.issubset(inventory_paths):
        fail("FAIL: Phase 10 artifact_inventory missing lock candidates", sorted(required_inventory_paths - inventory_paths))
    bad_inventory = []
    for idx, item in enumerate(artifact_inventory):
        if not isinstance(item, dict):
            bad_inventory.append(f"artifact_inventory[{idx}] is not an object")
            continue
        path = str(item.get("path", "")).strip()
        if Path(path).is_absolute() or not path or not (proj / path).exists():
            bad_inventory.append(f"artifact_inventory[{idx}].path invalid")
        if not item.get("sha256") or item.get("sha256") != sha256(proj / path):
            bad_inventory.append(f"artifact_inventory[{idx}].sha256 mismatch")
        if item.get("lock_candidate") is not True:
            bad_inventory.append(f"artifact_inventory[{idx}].lock_candidate must be true")
    if bad_inventory:
        fail("FAIL: Phase 10 artifact inventory is invalid", bad_inventory)
    reconciliation = sanity.get("lock_candidate_reconciliation")
    if not isinstance(reconciliation, dict):
        fail("FAIL: Phase 10 lock_candidate_reconciliation must be an object")
    if reconciliation.get("status") != "PASS":
        fail("FAIL: Phase 10 lock_candidate_reconciliation.status must be PASS")
    if reconciliation.get("missing_paths") != [] or reconciliation.get("extra_paths") != []:
        fail("FAIL: Phase 10 lock_candidate_reconciliation must have no missing or extra paths")
    recon_required = {
        str(item).strip()
        for item in reconciliation.get("required_paths", [])
        if str(item).strip()
    }
    recon_inventory = {
        str(item).strip()
        for item in reconciliation.get("inventory_paths", [])
        if str(item).strip()
    }
    recon_phase8 = {
        str(item).strip()
        for item in reconciliation.get("phase8_manifest_paths_checked", [])
        if str(item).strip()
    }
    if recon_required != required_inventory_paths:
        fail("FAIL: Phase 10 lock_candidate_reconciliation.required_paths do not match computed lock candidates")
    if recon_inventory != inventory_paths:
        fail("FAIL: Phase 10 lock_candidate_reconciliation.inventory_paths do not match artifact_inventory")
    if recon_phase8 != phase8_manifest_paths:
        fail("FAIL: Phase 10 lock_candidate_reconciliation.phase8_manifest_paths_checked must match Phase 8 artifact_manifest")
    if int(sanity.get("critical_count", -1)) != 0:
        fail("FAIL: Phase 10 critical_count must be 0")
    if int(sanity.get("unresolved_blocking_count", -1)) != 0:
        fail("FAIL: Phase 10 unresolved_blocking_count must be 0")
    if sanity.get("route_back_phase") not in (None, ""):
        fail("FAIL: Phase 10 cannot pass while route_back_phase is set")
    sanity_md_text = sanity_md_path.read_text(errors="ignore").lower()
    conflict_pattern = re.compile(r"(unresolved|remains|open|stale).{0,60}(drift|block|blocking|critical|invalid)|(drift|block|blocking|critical|invalid).{0,60}(unresolved|remains|open|stale)")
    if conflict_pattern.search(sanity_md_text):
        fail("FAIL: Phase 10 markdown summary contradicts JSON PASS status")
    sanity_words = re.findall(r"\b\w+\b", sanity_md_path.read_text(errors="ignore"))
    if len(sanity_words) < 80:
        fail(f"FAIL: Phase 10 runtime-sanity.md is too short, found {len(sanity_words)} words")

if phase_id == "11":
    sanity_path = proj / "verify" / "runtime-sanity.json"
    sanity_md_path = proj / "verify" / "runtime-sanity.md"
    execution_path = proj / "analysis" / "execution-report.json"
    results_path = proj / "tables" / "results-registry.csv"
    figures_path = proj / "figures" / "figure-registry.csv"
    post_review_path = proj / "review" / "post-execution-review.json"
    latest_path = proj / "results-locked" / "LATEST.txt"
    manifest_path = proj / "results-locked" / "manifest.json"
    stage1_path = proj / "verify" / "stage1-verify.json"
    for required_path in (sanity_path, sanity_md_path, execution_path, results_path, figures_path, post_review_path):
        if not required_path.exists():
            fail(f"FAIL: Phase 11 missing required input {required_path.relative_to(proj)}")
    try:
        sanity = json.loads(sanity_path.read_text())
        execution = json.loads(execution_path.read_text())
        manifest = json.loads(manifest_path.read_text())
        stage1 = json.loads(stage1_path.read_text())
    except Exception as exc:
        fail(f"FAIL: Phase 11 cannot read required JSON artifacts: {exc}")
    result_rows = read_csv_dicts(results_path)
    figure_rows = read_csv_dicts(figures_path)
    if sanity.get("verdict") != "PASS" or sanity.get("decision") != "PROCEED_TO_RESULTS_LOCK":
        fail("FAIL: Phase 11 requires Phase 10 decision PROCEED_TO_RESULTS_LOCK")
    if sanity.get("ready_for_phase_11") is not True:
        fail("FAIL: Phase 11 requires Phase 10 ready_for_phase_11 true")
    if int(sanity.get("critical_count", -1)) != 0 or int(sanity.get("unresolved_blocking_count", -1)) != 0:
        fail("FAIL: Phase 11 cannot lock with unresolved Phase 10 blockers")
    if sanity.get("route_back_phase") not in (None, ""):
        fail("FAIL: Phase 11 cannot lock while Phase 10 route_back_phase is set")
    if manifest.get("verdict") != "PASS":
        fail(f"FAIL: Phase 11 manifest verdict must be PASS, got {manifest.get('verdict')}")
    if manifest.get("degraded") is not False:
        fail("FAIL: Phase 11 manifest degraded must be false")
    lock_engine = manifest.get("lock_engine")
    if not isinstance(lock_engine, dict):
        fail("FAIL: Phase 11 manifest lock_engine must be an object")
    if lock_engine.get("skill") != "scholar-auto-research":
        fail("FAIL: Phase 11 lock_engine.skill must be scholar-auto-research")
    if lock_engine.get("mode") != "results_lock":
        fail("FAIL: Phase 11 lock_engine.mode must be results_lock")
    if lock_engine.get("auto_research_contract") != "phase_11":
        fail("FAIL: Phase 11 lock_engine.auto_research_contract must be phase_11")
    if lock_engine.get("deterministic_lock") is not True:
        fail("FAIL: Phase 11 lock_engine.deterministic_lock must be true")
    if manifest.get("ready_for_phase_12") is not True:
        fail("FAIL: Phase 11 manifest ready_for_phase_12 must be true")
    lock_id = str(manifest.get("lock_id", "")).strip()
    if lock_id.lower() in {"", "tbd", "todo", "unknown", "placeholder"}:
        fail("FAIL: Phase 11 lock_id must be non-placeholder")
    active_lock_dir = proj / "results-locked" / lock_id
    if not active_lock_dir.exists() or not active_lock_dir.is_dir():
        fail("FAIL: Phase 11 active lock directory results-locked/<lock_id>/ must exist")
    latest = latest_path.read_text(errors="ignore")
    if latest != f"{lock_id}\n":
        fail("FAIL: Phase 11 LATEST.txt must contain exactly lock_id plus trailing newline")
    if manifest.get("latest_matches") is not True:
        fail("FAIL: Phase 11 manifest latest_matches must be true")
    source_hashes = manifest.get("source_hashes")
    if not isinstance(source_hashes, dict):
        fail("FAIL: Phase 11 manifest source_hashes must be an object")
    expected_sources = {
        "runtime_sanity": sha256(sanity_path),
        "runtime_sanity_md": sha256(sanity_md_path),
        "execution_report": sha256(execution_path),
        "results_registry": sha256(results_path),
        "figure_registry": sha256(figures_path),
        "post_execution_review": sha256(post_review_path),
    }
    stale_sources = [
        f"{key} mismatch"
        for key, expected in expected_sources.items()
        if source_hashes.get(key) != expected
    ]
    if stale_sources:
        fail("FAIL: Phase 11 manifest source_hashes are stale", stale_sources)
    manifest_hash = canonical_sha256_without_field(manifest, "manifest_sha256")
    if manifest.get("manifest_sha256") != manifest_hash:
        fail("FAIL: Phase 11 manifest_sha256 does not match manifest content excluding manifest_sha256")
    sanity_inventory = sanity.get("artifact_inventory")
    if not isinstance(sanity_inventory, list) or not sanity_inventory:
        fail("FAIL: Phase 11 requires Phase 10 artifact_inventory")
    expected_artifacts = {
        str(item.get("path", "")).strip(): item
        for item in sanity_inventory
        if isinstance(item, dict) and item.get("lock_candidate") is True
    }
    rebuilt_candidates = {
        "analysis/execution-report.json",
        "tables/results-registry.csv",
        "figures/figure-registry.csv",
        "review/post-execution-review.json",
    }
    for row in result_rows:
        output_file = str(row.get("output_file", "")).strip()
        if output_file:
            rebuilt_candidates.add(output_file)
    for row in figure_rows:
        if str(row.get("status", "")).strip() == "completed":
            fig_path = str(row.get("path", "")).strip()
            if fig_path:
                rebuilt_candidates.add(fig_path)
    for key in ("expected_outputs", "outputs"):
        values = execution.get(key)
        if isinstance(values, list):
            for value in values:
                rel = str(value).strip()
                if rel.startswith(("tables/", "figures/")):
                    rebuilt_candidates.add(rel)
    for script in execution.get("executed_scripts", []):
        if not isinstance(script, dict):
            continue
        outputs = script.get("outputs")
        if isinstance(outputs, list):
            for value in outputs:
                rel = str(value).strip()
                if rel.startswith(("tables/", "figures/")):
                    rebuilt_candidates.add(rel)
        output_hashes = script.get("output_hashes")
        if isinstance(output_hashes, dict):
            for value in output_hashes:
                rel = str(value).strip()
                if rel.startswith(("tables/", "figures/")):
                    rebuilt_candidates.add(rel)
    for folder in ("tables", "figures"):
        base = proj / folder
        if base.exists():
            for path in base.rglob("*"):
                if path.is_file():
                    rebuilt_candidates.add(str(path.relative_to(proj)))
    rebuilt_candidates = {path for path in rebuilt_candidates if path and not Path(path).is_absolute()}
    if set(expected_artifacts) != rebuilt_candidates:
        missing = sorted(rebuilt_candidates - set(expected_artifacts))
        extra = sorted(set(expected_artifacts) - rebuilt_candidates)
        fail("FAIL: Phase 11 Phase 10 inventory must match independently rebuilt lock candidates", missing + extra)
    locked_artifacts = manifest.get("locked_artifacts")
    if not isinstance(locked_artifacts, list) or not locked_artifacts:
        fail("FAIL: Phase 11 manifest locked_artifacts must be non-empty list")
    locked_by_source = {
        str(item.get("source_path", "")).strip(): item
        for item in locked_artifacts
        if isinstance(item, dict)
    }
    if set(locked_by_source) != set(expected_artifacts):
        missing = sorted(set(expected_artifacts) - set(locked_by_source))
        extra = sorted(set(locked_by_source) - set(expected_artifacts))
        fail("FAIL: Phase 11 locked artifacts must exactly cover Phase 10 lock candidates", missing + extra)
    allowed_roles = {
        "runtime_sanity",
        "execution_report",
        "results_registry",
        "result_table",
        "model_output",
        "main_regression_table",
        "sensitivity_regression_table",
        "regression_table",
        "descriptive_table",
        "reader_facing_descriptive_table",
        "figure_registry",
        "figure_file",
        "post_execution_review",
        "diagnostic",
    }
    bad_locks = []
    manifest_locked_paths = set()
    for source_path, expected_item in expected_artifacts.items():
        item = locked_by_source[source_path]
        locked_path = str(item.get("locked_path", "")).strip()
        source_file = proj / source_path
        locked_file = proj / locked_path
        if Path(source_path).is_absolute() or not source_file.exists():
            bad_locks.append(f"{source_path}: source_path invalid")
            continue
        if Path(locked_path).is_absolute() or not locked_path or not locked_file.exists():
            bad_locks.append(f"{source_path}: locked_path invalid")
            continue
        if not locked_path.startswith(f"results-locked/{lock_id}/"):
            bad_locks.append(f"{source_path}: locked_path must be under results-locked/{lock_id}/")
        manifest_locked_paths.add(locked_path)
        expected_hash = str(expected_item.get("sha256", "")).strip()
        if not expected_hash or expected_hash != sha256(source_file):
            bad_locks.append(f"{source_path}: Phase 10 artifact hash stale")
        if item.get("sha256") != expected_hash:
            bad_locks.append(f"{source_path}: manifest sha256 differs from Phase 10 artifact hash")
        if sha256(locked_file) != expected_hash:
            bad_locks.append(f"{source_path}: locked copy hash differs from source")
        if item.get("lock_status") != "copied":
            bad_locks.append(f"{source_path}: lock_status must be copied")
        if item.get("artifact_role") not in allowed_roles:
            bad_locks.append(f"{source_path}: artifact_role invalid or missing")
    if bad_locks:
        fail("FAIL: Phase 11 locked artifact entries are invalid", bad_locks)
    actual_lock_files = {
        str(path.relative_to(proj))
        for path in active_lock_dir.rglob("*")
        if path.is_file()
    }
    if actual_lock_files != manifest_locked_paths:
        missing = sorted(manifest_locked_paths - actual_lock_files)
        extra = sorted(actual_lock_files - manifest_locked_paths)
        fail("FAIL: Phase 11 active lock directory must contain only manifest-listed artifacts", missing + extra)
    if stage1.get("verdict") != "PASS":
        fail(f"FAIL: Phase 11 stage1 verdict must be PASS, got {stage1.get('verdict')}")
    if manifest.get("stage1_verdict") != stage1.get("verdict"):
        fail("FAIL: Phase 11 manifest stage1_verdict must match Stage 1 verdict")
    if stage1.get("degraded") is not False:
        fail("FAIL: Phase 11 stage1 degraded must be false")
    if stage1.get("lock_id") != lock_id:
        fail("FAIL: Phase 11 stage1 lock_id must match manifest lock_id")
    if stage1.get("manifest_sha256") != manifest_hash:
        fail("FAIL: Phase 11 stage1 manifest_sha256 must match manifest")
    if stage1.get("input_manifest_sha256") != manifest_hash:
        fail("FAIL: Phase 11 stage1 input_manifest_sha256 must match manifest")
    if stage1.get("ready_for_phase_12") is not True:
        fail("FAIL: Phase 11 stage1 ready_for_phase_12 must be true")
    for field in ("missing_count", "mismatch_count", "extra_locked_count"):
        if int(stage1.get(field, -1)) != 0:
            fail(f"FAIL: Phase 11 stage1 {field} must be 0")
    for field in ("missing_paths", "mismatch_paths", "extra_locked_paths"):
        if stage1.get(field) != []:
            fail(f"FAIL: Phase 11 stage1 {field} must be an empty list")
    provenance = stage1.get("scanner_provenance")
    if not isinstance(provenance, dict) or not provenance.get("scanner") or not provenance.get("verified_at"):
        fail("FAIL: Phase 11 stage1 scanner_provenance must identify scanner and verified_at")
    if provenance.get("scanner") != "auto-research-verify":
        fail("FAIL: Phase 11 stage1 scanner_provenance.scanner must be auto-research-verify")
    if provenance.get("mode") != "results_lock_stage1":
        fail("FAIL: Phase 11 stage1 scanner_provenance.mode must be results_lock_stage1")
    if provenance.get("auto_research_contract") != "phase_11":
        fail("FAIL: Phase 11 stage1 scanner_provenance.auto_research_contract must be phase_11")
    checked = stage1.get("checked_artifacts")
    if not isinstance(checked, list):
        fail("FAIL: Phase 11 stage1 checked_artifacts must be a list")
    if int(stage1.get("checked_count", -1)) != len(checked):
        fail("FAIL: Phase 11 stage1 checked_count must equal checked_artifacts length")
    checked_sources = {
        str(item.get("source_path", "")).strip(): item
        for item in checked
        if isinstance(item, dict)
    }
    if set(checked_sources) != set(expected_artifacts):
        missing = sorted(set(expected_artifacts) - set(checked_sources))
        extra = sorted(set(checked_sources) - set(expected_artifacts))
        fail("FAIL: Phase 11 stage1 checked_artifacts must cover every locked artifact", missing + extra)
    bad_checks = []
    for source_path, lock_item in locked_by_source.items():
        check = checked_sources[source_path]
        locked_path = str(lock_item.get("locked_path", "")).strip()
        expected_hash = str(lock_item.get("sha256", "")).strip()
        if check.get("locked_path") != locked_path:
            bad_checks.append(f"{source_path}: checked locked_path mismatch")
        if check.get("source_hash") != expected_hash or check.get("locked_hash") != expected_hash:
            bad_checks.append(f"{source_path}: checked hashes mismatch")
        if check.get("verdict") != "PASS":
            bad_checks.append(f"{source_path}: checked verdict={check.get('verdict')}")
    if bad_checks:
        fail("FAIL: Phase 11 stage1 artifact checks are invalid", bad_checks)

if phase_id == "12":
    blueprint_path = proj / "manuscript" / "manuscript-blueprint.json"
    blueprint_md_path = proj / "manuscript" / "manuscript-blueprint.md"
    lock_manifest_path = proj / "results-locked" / "manifest.json"
    latest_path = proj / "results-locked" / "LATEST.txt"
    stage1_path = proj / "verify" / "stage1-verify.json"
    rq_path = proj / "idea" / "research-question.json"
    journal_fit_path = proj / "idea" / "journal-fit.json"
    lit_path = proj / "literature" / "lit-theory.md"
    design_path = proj / "design" / "design-blueprint.md"
    identification_path = proj / "design" / "identification-strategy.json"
    analysis_plan_path = proj / "analysis" / "analysis-plan.md"
    post_review_path = proj / "review" / "post-execution-review.json"
    results_registry_path = proj / "tables" / "results-registry.csv"
    figure_registry_path = proj / "figures" / "figure-registry.csv"
    for required_path in (
        blueprint_path,
        blueprint_md_path,
        lock_manifest_path,
        latest_path,
        stage1_path,
        rq_path,
        journal_fit_path,
        lit_path,
        design_path,
        identification_path,
        analysis_plan_path,
        post_review_path,
        results_registry_path,
        figure_registry_path,
    ):
        if not required_path.exists():
            fail(f"FAIL: Phase 12 missing required input {required_path.relative_to(proj)}")
    try:
        blueprint = json.loads(blueprint_path.read_text())
        lock_manifest = json.loads(lock_manifest_path.read_text())
        stage1 = json.loads(stage1_path.read_text())
        research_question = json.loads(rq_path.read_text())
        journal_fit = json.loads(journal_fit_path.read_text())
        identification = json.loads(identification_path.read_text())
        post_review = json.loads(post_review_path.read_text())
        results_registry = read_csv_dicts(results_registry_path)
        figure_registry = read_csv_dicts(figure_registry_path)
    except Exception as exc:
        fail(f"FAIL: Phase 12 blueprint artifacts are not valid: {exc}")
    required = (
        "verdict",
        "degraded",
        "blueprint_engine",
        "lock_id",
        "lock_manifest_sha256",
        "source_hashes",
        "paper_type",
        "target_journal",
        "journal_profile_resolution",
        "paper_claim",
        "claim_strength",
        "publication_readiness",
        "contribution_stack",
        "result_hierarchy",
        "hypothesis_resolution",
        "mechanism_integration_plan",
        "journal_structure",
        "display_architecture",
        "discussion_mode",
        "appendix_policy",
        "section_obligations",
        "required_disclosures",
        "forbidden_moves",
        "table_figure_narrative_map",
        "abstract_alignment",
        "discussion_alignment",
        "null_result_framing",
        "route_back_phase",
        "ready_for_phase_13",
    )
    absent = [field for field in required if field not in blueprint]
    if absent:
        fail("FAIL: Phase 12 blueprint missing required fields", absent)
    if blueprint.get("verdict") != "PASS":
        fail(f"FAIL: Phase 12 blueprint verdict must be PASS, got {blueprint.get('verdict')}")
    if blueprint.get("degraded") is not False:
        fail("FAIL: Phase 12 blueprint degraded must be false")
    engine = blueprint.get("blueprint_engine")
    if not isinstance(engine, dict):
        fail("FAIL: Phase 12 blueprint_engine must be an object")
    expected_engine = {
        "skill": "scholar-auto-research",
        "mode": "manuscript_blueprint",
        "lock_enforced": True,
        "live_output_reads_forbidden": True,
    }
    engine_mismatches = [
        f"{key}: expected {expected!r}, got {engine.get(key)!r}"
        for key, expected in expected_engine.items()
        if engine.get(key) != expected
    ]
    if engine_mismatches:
        fail("FAIL: Phase 12 blueprint_engine must declare the manuscript blueprint compiler", engine_mismatches)
    if stage1.get("verdict") != "PASS" or stage1.get("ready_for_phase_12") is not True:
        fail("FAIL: Phase 12 requires a passing Phase 11 Stage 1 verification")
    lock_id = str(lock_manifest.get("lock_id", "")).strip()
    if not lock_id or latest_path.read_text(errors="ignore") != f"{lock_id}\n":
        fail("FAIL: Phase 12 results-locked/LATEST.txt must point to the active lock")
    if blueprint.get("lock_id") != lock_id:
        fail("FAIL: Phase 12 blueprint lock_id must match the active lock")
    if blueprint.get("lock_manifest_sha256") != lock_manifest.get("manifest_sha256"):
        fail("FAIL: Phase 12 blueprint lock_manifest_sha256 must match Phase 11 manifest_sha256")
    source_hashes = blueprint.get("source_hashes")
    if not isinstance(source_hashes, dict):
        fail("FAIL: Phase 12 source_hashes must be an object")
    expected_hashes = {
        "lock_manifest": sha256(lock_manifest_path),
        "stage1_verify": sha256(stage1_path),
        "research_question": sha256(rq_path),
        "journal_fit": sha256(journal_fit_path),
        "lit_theory": sha256(lit_path),
        "design_blueprint": sha256(design_path),
        "identification_strategy": sha256(identification_path),
        "analysis_plan": sha256(analysis_plan_path),
        "post_execution_review": sha256(post_review_path),
        "results_registry": sha256(results_registry_path),
        "figure_registry": sha256(figure_registry_path),
    }
    stale_sources = [
        f"{key} mismatch"
        for key, expected in expected_hashes.items()
        if source_hashes.get(key) != expected
    ]
    if stale_sources:
        fail("FAIL: Phase 12 blueprint source_hashes are stale", stale_sources)
    if blueprint.get("paper_type") != research_question.get("paper_type") or blueprint.get("paper_type") != journal_fit.get("paper_type"):
        fail("FAIL: Phase 12 blueprint paper_type must match Phase 1 artifacts")
    if blueprint.get("target_journal") != research_question.get("target_journal", {}).get("primary"):
        fail("FAIL: Phase 12 blueprint target_journal must match Phase 1 research question")
    if blueprint.get("target_journal") != journal_fit.get("primary_target"):
        fail("FAIL: Phase 12 blueprint target_journal must match Phase 1 journal-fit")
    journal_resolution = blueprint.get("journal_profile_resolution")
    if journal_resolution != journal_fit.get("journal_profile_resolution"):
        fail("FAIL: Phase 12 journal_profile_resolution must match the approved Phase 1 journal-fit resolution")
    resolved_profile, resolution_issues = resolve_profile_for_target(blueprint.get("target_journal"), journal_resolution, "Phase 12")
    if resolution_issues:
        fail("FAIL: Phase 12 journal_profile_resolution is invalid", resolution_issues)
    journal_structure = blueprint.get("journal_structure")
    if journal_structure != journal_resolution.get("journal_structure"):
        fail("FAIL: Phase 12 journal_structure must match journal_profile_resolution.journal_structure")
    journal_structure_issues = validate_journal_structure(journal_structure, blueprint.get("target_journal"), "Phase 12", expected_profile=resolved_profile)
    if journal_structure_issues:
        fail("FAIL: Phase 12 journal_structure is invalid", journal_structure_issues)
    display_architecture = blueprint.get("display_architecture")
    if display_architecture != journal_resolution.get("display_architecture"):
        fail("FAIL: Phase 12 display_architecture must match journal_profile_resolution.display_architecture")
    display_architecture_issues = validate_display_architecture(display_architecture, blueprint.get("target_journal"), "Phase 12", expected_profile=resolved_profile)
    if display_architecture_issues:
        fail("FAIL: Phase 12 display_architecture is invalid", display_architecture_issues)
    profile = resolved_profile
    if profile and profile["discussion_conclusion_policy"] == "split_required" and blueprint.get("discussion_mode") != "split":
        fail("FAIL: Phase 12 discussion_mode must be split for the target journal profile")
    if profile and profile["discussion_conclusion_policy"] == "combined_only" and blueprint.get("discussion_mode") != "combined":
        fail("FAIL: Phase 12 discussion_mode must be combined for the target journal profile")
    display_expected_count = sum(
        1
        for item in blueprint.get("table_figure_narrative_map", [])
        if isinstance(item, dict) and item.get("display_expected") is True
    )
    display_cap = display_architecture.get("main_text_display_cap")
    if display_cap not in (None, "") and display_expected_count > int(display_cap):
        fail(
            "FAIL: Phase 12 display_architecture main_text_display_cap is exceeded by display-expected artifacts",
            [f"display_expected={display_expected_count}", f"cap={display_cap}"],
        )
    descriptive_requirement = str(display_architecture.get("descriptive_table_requirement", "")).strip()
    if descriptive_requirement in DESCRIPTIVE_TABLE_REQUIREMENTS:
        has_display_table = any(
            isinstance(item, dict)
            and item.get("display_expected") is True
            and str(item.get("artifact_path", "")).strip().startswith("tables/")
            and (
                "descript" in json_blob(item)
                or "summary statistic" in json_blob(item)
                or str(item.get("artifact_role", "")).strip() in {"descriptive_table", "reader_facing_descriptive_table"}
            )
            for item in blueprint.get("table_figure_narrative_map", [])
        )
        if not has_display_table:
            fail("FAIL: Phase 12 blueprint must reserve a display-expected descriptive table for this journal profile")
    paper_claim = str(blueprint.get("paper_claim", "")).strip()
    if word_count(paper_claim) < 6:
        fail("FAIL: Phase 12 paper_claim must be a substantive one-sentence claim")
    claim_strength = str(blueprint.get("claim_strength", "")).strip()
    if not claim_strength:
        fail("FAIL: Phase 12 claim_strength must be nonempty")
    ident_claim_strength = str(identification.get("claim_strength", "")).strip()
    blueprint_rank = claim_strength_rank(claim_strength)
    ident_rank = claim_strength_rank(ident_claim_strength)
    if blueprint_rank is None:
        fail("FAIL: Phase 12 claim_strength must map to exploratory/descriptive/associational/causal semantics")
    if ident_rank is not None and blueprint_rank > ident_rank:
        fail(
            "FAIL: Phase 12 claim_strength may match or narrow Phase 3 claim strength, but may not exceed it",
            [f"phase3={ident_claim_strength}", f"phase12={claim_strength}"],
        )
    readiness = blueprint.get("publication_readiness")
    readiness_issues = []
    if not isinstance(readiness, dict):
        readiness_issues.append("publication_readiness must be an object")
    else:
        if readiness.get("status") != "PASS":
            readiness_issues.append("status must be PASS")
        if readiness.get("ready_for_drafting") is not True:
            readiness_issues.append("ready_for_drafting must be true")
        if readiness.get("route_back_if_not_ready") not in (False, 0):
            readiness_issues.append("route_back_if_not_ready must be false for PASS")
        contribution_sentence = str(readiness.get("contribution_sentence", "")).strip()
        novelty_claim = str(readiness.get("target_journal_novelty_claim", "") or readiness.get("novelty_claim", "")).strip()
        journal_fit_claim = str(readiness.get("target_journal_fit", "") or readiness.get("journal_fit_claim", "")).strip()
        if word_count(contribution_sentence) < 10:
            readiness_issues.append("contribution_sentence must be a concrete sentence of at least 10 words")
        if word_count(novelty_claim) < 10:
            readiness_issues.append("target_journal_novelty_claim must explain novelty for the target journal")
        if word_count(journal_fit_claim) < 8:
            readiness_issues.append("target_journal_fit must explain why this is a venue-ready paper")
        mechanism_rival_matrix = readiness.get("mechanism_rival_matrix")
        if not isinstance(mechanism_rival_matrix, list) or len(mechanism_rival_matrix) < 2:
            readiness_issues.append("mechanism_rival_matrix must include at least two entries")
        else:
            roles_seen = set()
            for idx, item in enumerate(mechanism_rival_matrix):
                if not isinstance(item, dict):
                    readiness_issues.append(f"mechanism_rival_matrix[{idx}] is not an object")
                    continue
                role = str(item.get("role", "")).strip()
                roles_seen.add(role)
                if role not in {"mechanism", "rival", "alternative", "scope_condition", "boundary_condition"}:
                    readiness_issues.append(f"mechanism_rival_matrix[{idx}].role invalid")
                for field in ("label", "evidence_link", "claim_implication"):
                    if word_count(str(item.get(field, ""))) < 3:
                        readiness_issues.append(f"mechanism_rival_matrix[{idx}].{field} too thin")
            if "mechanism" not in roles_seen:
                readiness_issues.append("mechanism_rival_matrix must include at least one mechanism")
            if not roles_seen.intersection({"rival", "alternative"}):
                readiness_issues.append("mechanism_rival_matrix must include at least one rival or alternative explanation")
        reviewer_risk_register = readiness.get("reviewer_risk_register")
        if not isinstance(reviewer_risk_register, list) or len(reviewer_risk_register) < 3:
            readiness_issues.append("reviewer_risk_register must include at least three anticipated objections")
        else:
            has_rejection_reason = False
            allowed_route_phases = {str(i) for i in range(2, 19)}
            for idx, item in enumerate(reviewer_risk_register):
                if not isinstance(item, dict):
                    readiness_issues.append(f"reviewer_risk_register[{idx}] is not an object")
                    continue
                risk_type = str(item.get("risk_type", "") or item.get("type", "")).lower()
                if "rejection" in risk_type or item.get("strongest_rejection_reason") is True:
                    has_rejection_reason = True
                for field in ("objection", "required_response"):
                    if word_count(str(item.get(field, ""))) < 5:
                        readiness_issues.append(f"reviewer_risk_register[{idx}].{field} too thin")
                route = str(item.get("route_back_phase", "")).strip()
                if route and route not in allowed_route_phases:
                    readiness_issues.append(f"reviewer_risk_register[{idx}].route_back_phase invalid")
            if not has_rejection_reason:
                readiness_issues.append("reviewer_risk_register must identify the strongest plausible rejection reason")
        evidence_claim_map = readiness.get("evidence_claim_map")
        if not isinstance(evidence_claim_map, list) or not evidence_claim_map:
            readiness_issues.append("evidence_claim_map must be a nonempty list")
        else:
            for idx, item in enumerate(evidence_claim_map):
                if not isinstance(item, dict):
                    readiness_issues.append(f"evidence_claim_map[{idx}] is not an object")
                    continue
                for field in ("claim", "evidence_type", "claim_strength"):
                    if word_count(str(item.get(field, ""))) < 2:
                        readiness_issues.append(f"evidence_claim_map[{idx}].{field} too thin")
                if not (str(item.get("artifact_path", "")).strip() or str(item.get("hypothesis_id", "")).strip() or str(item.get("limitation", "")).strip()):
                    readiness_issues.append(f"evidence_claim_map[{idx}] must cite artifact_path, hypothesis_id, or limitation")
    if readiness_issues:
        fail("FAIL: Phase 12 publication_readiness gate is incomplete", readiness_issues[:40])
    contribution_stack = blueprint.get("contribution_stack")
    if not isinstance(contribution_stack, list) or len(contribution_stack) < 2 or len(contribution_stack) > 4:
        fail("FAIL: Phase 12 contribution_stack must contain 2 to 4 ranked contributions")
    contribution_issues = []
    seen_ranks = set()
    for idx, item in enumerate(contribution_stack or []):
        if not isinstance(item, dict):
            contribution_issues.append(f"contribution_stack[{idx}] is not an object")
            continue
        rank = int(item.get("rank", -1)) if str(item.get("rank", "")).strip() else -1
        if rank < 1 or rank in seen_ranks:
            contribution_issues.append(f"contribution_stack[{idx}].rank missing or duplicate")
        seen_ranks.add(rank)
        if not str(item.get("contribution_type", "")).strip():
            contribution_issues.append(f"contribution_stack[{idx}].contribution_type missing")
        if word_count(str(item.get("claim_text", "")).strip()) < 6:
            contribution_issues.append(f"contribution_stack[{idx}].claim_text too short")
        if item.get("depends_on_results") not in (True, False):
            contribution_issues.append(f"contribution_stack[{idx}].depends_on_results must be boolean")
        if not str(item.get("scope_note", "")).strip():
            contribution_issues.append(f"contribution_stack[{idx}].scope_note missing")
    if contribution_issues:
        fail("FAIL: Phase 12 contribution_stack is invalid", contribution_issues)
    hierarchy = blueprint.get("result_hierarchy")
    if not isinstance(hierarchy, list) or not hierarchy:
        fail("FAIL: Phase 12 result_hierarchy must be a non-empty list")
    known_table_paths = {"tables/results-registry.csv"} | {
        str(row.get("output_file", "")).strip()
        for row in results_registry
        if str(row.get("output_file", "")).strip()
    }
    tables_base = proj / "tables"
    if tables_base.exists():
        known_table_paths |= {
            str(path.relative_to(proj))
            for path in tables_base.rglob("*")
            if path.is_file()
        }
    known_figure_paths = {
        str(row.get("path", "")).strip()
        for row in figure_registry
        if str(row.get("path", "")).strip()
    }
    hierarchy_issues = []
    hierarchy_paths = set()
    headline_paths = set()
    for idx, item in enumerate(hierarchy):
        if not isinstance(item, dict):
            hierarchy_issues.append(f"result_hierarchy[{idx}] is not an object")
            continue
        artifact_path = str(item.get("artifact_path", "")).strip()
        artifact_role = str(item.get("artifact_role", "")).strip()
        headline_status = str(item.get("headline_status", "")).strip()
        if not artifact_path or Path(artifact_path).is_absolute():
            hierarchy_issues.append(f"result_hierarchy[{idx}].artifact_path invalid")
        elif not (proj / artifact_path).exists():
            hierarchy_issues.append(f"{artifact_path}: artifact_path missing from project")
        hierarchy_paths.add(artifact_path)
        if artifact_role not in {"results_registry", "result_table", "model_output", "main_regression_table", "sensitivity_regression_table", "regression_table", "descriptive_table", "reader_facing_descriptive_table", "figure_file"}:
            hierarchy_issues.append(f"{artifact_path or idx}: artifact_role invalid")
        if headline_status not in {"headline", "supporting", "sensitivity", "diagnostic", "appendix_only"}:
            hierarchy_issues.append(f"{artifact_path or idx}: headline_status invalid")
        if artifact_role == "figure_file":
            if artifact_path not in known_figure_paths:
                hierarchy_issues.append(f"{artifact_path}: figure_file must appear in figure-registry.csv")
            if not str(item.get("figure_id", "")).strip():
                hierarchy_issues.append(f"{artifact_path}: figure_id missing")
        else:
            if artifact_path not in known_table_paths:
                hierarchy_issues.append(f"{artifact_path}: table/model artifact must appear in results registries")
            if artifact_role not in {"results_registry", "descriptive_table", "reader_facing_descriptive_table"} and not str(item.get("spec_id", "")).strip():
                hierarchy_issues.append(f"{artifact_path}: spec_id missing")
        if not str(item.get("narrative_role", "")).strip():
            hierarchy_issues.append(f"{artifact_path or idx}: narrative_role missing")
        if headline_status == "headline":
            headline_paths.add(artifact_path)
            if artifact_role not in {"result_table", "model_output", "main_regression_table", "sensitivity_regression_table", "regression_table", "figure_file"}:
                hierarchy_issues.append(f"{artifact_path}: headline artifacts may not use role {artifact_role}")
    if hierarchy_issues:
        fail("FAIL: Phase 12 result_hierarchy is invalid", hierarchy_issues)
    candidate_headline_paths = sorted(
        path for path in hierarchy_paths
        if path != "tables/results-registry.csv"
    )
    if candidate_headline_paths and not headline_paths:
        fail("FAIL: Phase 12 result_hierarchy must declare at least one headline artifact when locked evidence exists", candidate_headline_paths)
    if quantitative_empirical_regression_table_required(
        analysis_plan_path.read_text(errors="ignore"),
        blueprint,
        results_registry,
        identification,
        post_review,
    ):
        hierarchy_regression_tables = [
            str(item.get("artifact_path", "")).strip()
            for item in hierarchy
            if isinstance(item, dict)
            and str(item.get("artifact_role", "")).strip() in {"main_regression_table", "regression_table"}
            and not source_is_registry_like(str(item.get("artifact_path", "")).strip())
        ]
        if not hierarchy_regression_tables:
            fail(
                "FAIL: Phase 12 quantitative result_hierarchy must include a canonical main regression table",
                ["Use artifact_role main_regression_table or regression_table; do not use results-registry/model-ladder artifacts as the main evidence display"],
            )
    readiness_evidence_issues = []
    for idx, item in enumerate((blueprint.get("publication_readiness") or {}).get("evidence_claim_map", []) if isinstance(blueprint.get("publication_readiness"), dict) else []):
        if not isinstance(item, dict):
            continue
        artifact_path = str(item.get("artifact_path", "")).strip()
        if artifact_path and artifact_path not in hierarchy_paths:
            readiness_evidence_issues.append(f"evidence_claim_map[{idx}].artifact_path not in result_hierarchy: {artifact_path}")
        claim_status = str(item.get("claim_status", "") or item.get("headline_status", "")).strip()
        if claim_status and claim_status not in {"headline", "supporting", "sensitivity", "diagnostic", "limitation", "null_compatible", "scope"}:
            readiness_evidence_issues.append(f"evidence_claim_map[{idx}].claim_status invalid: {claim_status}")
    if readiness_evidence_issues:
        fail("FAIL: Phase 12 publication_readiness evidence-to-claim map is inconsistent with result_hierarchy", readiness_evidence_issues)
    hypothesis_resolution = blueprint.get("hypothesis_resolution")
    if not isinstance(hypothesis_resolution, list) or not hypothesis_resolution:
        fail("FAIL: Phase 12 hypothesis_resolution must be a non-empty list")
    hypothesis_issues = []
    seen_hypotheses = set()
    for idx, item in enumerate(hypothesis_resolution):
        if not isinstance(item, dict):
            hypothesis_issues.append(f"hypothesis_resolution[{idx}] is not an object")
            continue
        hypothesis_id = str(item.get("hypothesis_id", "")).strip()
        if not hypothesis_id or hypothesis_id in seen_hypotheses:
            hypothesis_issues.append(f"hypothesis_resolution[{idx}].hypothesis_id missing or duplicate")
        seen_hypotheses.add(hypothesis_id)
        if str(item.get("resolution_status", "")).strip() not in {"supported", "null_compatible", "mixed", "not_tested", "reframed"}:
            hypothesis_issues.append(f"{hypothesis_id or idx}: resolution_status invalid")
        evidence_specs = item.get("evidence_specs")
        if not isinstance(evidence_specs, list):
            hypothesis_issues.append(f"{hypothesis_id or idx}: evidence_specs must be a list")
        if not str(item.get("manuscript_implication", "")).strip():
            hypothesis_issues.append(f"{hypothesis_id or idx}: manuscript_implication missing")
    if hypothesis_issues:
        fail("FAIL: Phase 12 hypothesis_resolution is invalid", hypothesis_issues)
    mechanism_plan = blueprint.get("mechanism_integration_plan")
    if not isinstance(mechanism_plan, list) or not mechanism_plan:
        fail("FAIL: Phase 12 mechanism_integration_plan must be a non-empty list")
    mechanism_issues = []
    for idx, item in enumerate(mechanism_plan):
        if not isinstance(item, dict):
            mechanism_issues.append(f"mechanism_integration_plan[{idx}] is not an object")
            continue
        if not str(item.get("mechanism_id", item.get("mechanism_label", ""))).strip():
            mechanism_issues.append(f"mechanism_integration_plan[{idx}] mechanism label missing")
        if not str(item.get("theory_role", "")).strip():
            mechanism_issues.append(f"mechanism_integration_plan[{idx}].theory_role missing")
        if not str(item.get("evidence_role", "")).strip():
            mechanism_issues.append(f"mechanism_integration_plan[{idx}].evidence_role missing")
        if str(item.get("integration_status", "")).strip() not in {"tested_directly", "tested_indirectly", "discussion_only", "drop_from_claim"}:
            mechanism_issues.append(f"mechanism_integration_plan[{idx}].integration_status invalid")
    if mechanism_issues:
        fail("FAIL: Phase 12 mechanism_integration_plan is invalid", mechanism_issues)
    discussion_mode = str(blueprint.get("discussion_mode", "")).strip()
    if discussion_mode not in {"combined", "split"}:
        fail("FAIL: Phase 12 discussion_mode must be combined or split")
    appendix_policy = blueprint.get("appendix_policy")
    if not isinstance(appendix_policy, dict):
        fail("FAIL: Phase 12 appendix_policy must be an object")
    appendix_issues = []
    for product in ("draft", "final", "submission"):
        entries = appendix_policy.get(product)
        if not isinstance(entries, list):
            appendix_issues.append(f"appendix_policy.{product} must be a list")
        elif any(not str(item).strip() for item in entries):
            appendix_issues.append(f"appendix_policy.{product} contains blank entries")
    if appendix_issues:
        fail("FAIL: Phase 12 appendix_policy is invalid", appendix_issues)
    section_obligations = blueprint.get("section_obligations")
    if not isinstance(section_obligations, dict):
        fail("FAIL: Phase 12 section_obligations must be an object")
    required_sections = {
        "abstract",
        "introduction",
        "literature_review_and_theory",
        "data_and_methods",
        "results",
        "discussion",
    }
    if not required_sections.issubset(section_obligations):
        fail("FAIL: Phase 12 section_obligations missing required sections", sorted(required_sections - set(section_obligations)))
    if discussion_mode == "split" and "conclusion" not in section_obligations:
        fail("FAIL: Phase 12 discussion_mode=split requires section_obligations.conclusion")
    obligation_issues = []
    for section_name in sorted(required_sections | ({"conclusion"} if discussion_mode == "split" else set())):
        item = section_obligations.get(section_name)
        if not isinstance(item, dict):
            obligation_issues.append(f"{section_name}: obligation must be an object")
            continue
        for field in ("required_moves", "required_artifacts", "required_disclosures", "forbidden_moves"):
            if not isinstance(item.get(field), list):
                obligation_issues.append(f"{section_name}.{field} must be a list")
        if isinstance(item.get("required_moves"), list) and not item.get("required_moves"):
            obligation_issues.append(f"{section_name}.required_moves must be non-empty")
        if isinstance(item.get("forbidden_moves"), list) and not item.get("forbidden_moves"):
            obligation_issues.append(f"{section_name}.forbidden_moves must be non-empty")
    if obligation_issues:
        fail("FAIL: Phase 12 section_obligations are invalid", obligation_issues)
    results_required = {
        str(item).strip()
        for item in section_obligations.get("results", {}).get("required_artifacts", [])
        if str(item).strip()
    }
    missing_results_headlines = sorted(headline_paths - results_required)
    if missing_results_headlines:
        fail(
            "FAIL: Phase 12 headline results must appear in results obligations",
            [f"results missing: {path}" for path in missing_results_headlines]
        )
    required_disclosures = blueprint.get("required_disclosures")
    if not isinstance(required_disclosures, list) or not required_disclosures or any(not str(item).strip() for item in required_disclosures):
        fail("FAIL: Phase 12 required_disclosures must be a non-empty list")
    post_constraints = post_review.get("claim_constraints", {})
    phase9_disclosures = {
        str(item).strip()
        for item in post_constraints.get("required_disclosures", [])
        if str(item).strip()
    } if isinstance(post_constraints, dict) else set()
    if not phase9_disclosures.issubset({str(item).strip() for item in required_disclosures}):
        fail("FAIL: Phase 12 required_disclosures must carry forward all Phase 9 disclosures", sorted(phase9_disclosures - {str(item).strip() for item in required_disclosures}))
    forbidden_moves = blueprint.get("forbidden_moves")
    if not isinstance(forbidden_moves, list) or not forbidden_moves or any(not str(item).strip() for item in forbidden_moves):
        fail("FAIL: Phase 12 forbidden_moves must be a non-empty list")
    narrative_map = blueprint.get("table_figure_narrative_map")
    if not isinstance(narrative_map, list) or not narrative_map:
        fail("FAIL: Phase 12 table_figure_narrative_map must be a non-empty list")
    map_issues = []
    mapped_paths = set()
    for idx, item in enumerate(narrative_map):
        if not isinstance(item, dict):
            map_issues.append(f"table_figure_narrative_map[{idx}] is not an object")
            continue
        artifact_path = str(item.get("artifact_path", "")).strip()
        if not artifact_path or artifact_path not in hierarchy_paths:
            map_issues.append(f"table_figure_narrative_map[{idx}].artifact_path missing from result_hierarchy")
        mapped_paths.add(artifact_path)
        if item.get("display_expected") not in (True, False):
            map_issues.append(f"{artifact_path or idx}: display_expected must be boolean")
        for field in ("section", "paragraph_role", "claim_role"):
            if not str(item.get(field, "")).strip():
                map_issues.append(f"{artifact_path or idx}: {field} missing")
    if map_issues:
        fail("FAIL: Phase 12 table_figure_narrative_map is invalid", map_issues)
    if not headline_paths.issubset(mapped_paths):
        fail("FAIL: Phase 12 narrative map must cover every headline artifact", sorted(headline_paths - mapped_paths))
    missing_candidate_map = sorted(set(candidate_headline_paths) - mapped_paths)
    if missing_candidate_map:
        fail("FAIL: Phase 12 narrative map must cover every interpreted non-registry artifact", missing_candidate_map)
    for alignment_name in ("abstract_alignment", "discussion_alignment", "null_result_framing"):
        alignment = blueprint.get(alignment_name)
        if not isinstance(alignment, dict) or not alignment:
            fail(f"FAIL: Phase 12 {alignment_name} must be a non-empty object")
    if blueprint.get("route_back_phase") not in (None, ""):
        fail("FAIL: Phase 12 route_back_phase must be empty for PASS")
    if blueprint.get("ready_for_phase_13") is not True:
        fail("FAIL: Phase 12 ready_for_phase_13 must be true")
    blueprint_md = blueprint_md_path.read_text(errors="ignore")
    if word_count(blueprint_md) < 150:
        fail("FAIL: Phase 12 manuscript-blueprint.md is too short")

if phase_id == "13":
    manuscript_path = proj / "manuscript" / "manuscript-draft.md"
    draft_manifest_path = proj / "manuscript" / "draft-manifest.json"
    drafting_plan_path = proj / "manuscript" / "drafting-plan.json"
    self_critique_path = proj / "manuscript" / "draft-self-critique.json"
    polish_report_path = proj / "manuscript" / "polish-report.json"
    journal_spec_path = proj / "manuscript" / "journal-spec.json"
    blueprint_path = proj / "manuscript" / "manuscript-blueprint.json"
    lock_manifest_path = proj / "results-locked" / "manifest.json"
    latest_path = proj / "results-locked" / "LATEST.txt"
    bib_path = proj / "literature" / "references.bib"
    lit_path = proj / "literature" / "lit-theory.md"
    rq_path = proj / "idea" / "research-question.json"
    journal_fit_path = proj / "idea" / "journal-fit.json"
    design_path = proj / "design" / "design-blueprint.md"
    var_dict_path = proj / "data" / "variable-dictionary.csv"
    analysis_plan_path = proj / "analysis" / "analysis-plan.md"
    post_review_path = proj / "review" / "post-execution-review.json"
    stage1_path = proj / "verify" / "stage1-verify.json"
    for required_path in (lock_manifest_path, latest_path, bib_path, lit_path, rq_path, journal_fit_path, design_path, var_dict_path, analysis_plan_path, post_review_path, stage1_path, blueprint_path):
        if not required_path.exists():
            fail(f"FAIL: Phase 13 missing required input {required_path.relative_to(proj)}")
    try:
        lock_manifest = json.loads(lock_manifest_path.read_text())
        stage1 = json.loads(stage1_path.read_text())
        draft_manifest = json.loads(draft_manifest_path.read_text())
        drafting_plan = json.loads(drafting_plan_path.read_text())
        self_critique = json.loads(self_critique_path.read_text())
        polish_report = json.loads(polish_report_path.read_text())
        journal_spec = json.loads(journal_spec_path.read_text())
        blueprint = json.loads(blueprint_path.read_text())
        research_question = json.loads(rq_path.read_text())
        journal_fit = json.loads(journal_fit_path.read_text())
        post_review = json.loads(post_review_path.read_text())
        var_rows = read_csv_dicts(var_dict_path)
    except Exception as exc:
        fail(f"FAIL: Phase 13 cannot read required JSON artifacts: {exc}")
    manuscript_text = manuscript_path.read_text(errors="ignore")
    if draft_manifest.get("verdict") != "PASS":
        fail(f"FAIL: Phase 13 draft manifest verdict must be PASS, got {draft_manifest.get('verdict')}")
    if draft_manifest.get("degraded") is not False:
        fail("FAIL: Phase 13 draft manifest degraded must be false")
    drafting_engine = draft_manifest.get("drafting_engine")
    if not isinstance(drafting_engine, dict):
        fail("FAIL: Phase 13 draft manifest must declare drafting_engine")
    expected_engine = {
        "skill": "scholar-write",
        "mode": "draft",
        "section": "full paper",
        "auto_research_contract": "phase_13",
        "lock_enforced": True,
        "live_output_reads_forbidden": True,
    }
    engine_mismatches = [
        f"{key}: expected {expected!r}, got {drafting_engine.get(key)!r}"
        for key, expected in expected_engine.items()
        if drafting_engine.get(key) != expected
    ]
    if engine_mismatches:
        fail("FAIL: Phase 13 drafting_engine must use scholar-write under the Phase 13 lock contract", engine_mismatches)
    drafting_engine_issues = validate_engine_provenance(drafting_engine, "Phase 13 drafting_engine")
    if drafting_engine_issues:
        fail("FAIL: Phase 13 drafting_engine provenance is incomplete", drafting_engine_issues)
    if draft_manifest.get("ready_for_phase_14") is not True:
        fail("FAIL: Phase 13 draft manifest ready_for_phase_14 must be true")
    blueprint_decl = draft_manifest.get("blueprint")
    if not isinstance(blueprint_decl, dict):
        fail("FAIL: Phase 13 draft manifest must include blueprint metadata")
    if blueprint_decl.get("path") != "manuscript/manuscript-blueprint.json":
        fail("FAIL: Phase 13 blueprint.path must be manuscript/manuscript-blueprint.json")
    if blueprint_decl.get("sha256") != sha256(blueprint_path):
        fail("FAIL: Phase 13 blueprint sha256 mismatch")
    if blueprint.get("verdict") != "PASS" or blueprint.get("ready_for_phase_13") is not True:
        fail("FAIL: Phase 13 requires a passing Phase 12 manuscript blueprint")
    drafting_plan_decl = draft_manifest.get("drafting_plan")
    if not isinstance(drafting_plan_decl, dict):
        fail("FAIL: Phase 13 draft manifest must include drafting_plan metadata")
    if drafting_plan_decl.get("path") != "manuscript/drafting-plan.json":
        fail("FAIL: Phase 13 drafting_plan.path must be manuscript/drafting-plan.json")
    if drafting_plan_decl.get("sha256") != sha256(drafting_plan_path):
        fail("FAIL: Phase 13 drafting_plan sha256 mismatch")
    self_critique_decl = draft_manifest.get("self_critique")
    if not isinstance(self_critique_decl, dict):
        fail("FAIL: Phase 13 draft manifest must include self_critique metadata")
    if self_critique_decl.get("path") != "manuscript/draft-self-critique.json":
        fail("FAIL: Phase 13 self_critique.path must be manuscript/draft-self-critique.json")
    if self_critique_decl.get("sha256") != sha256(self_critique_path):
        fail("FAIL: Phase 13 self_critique sha256 mismatch")
    if self_critique_decl.get("ready_for_verification") is not True:
        fail("FAIL: Phase 13 self_critique metadata must set ready_for_verification true")
    blueprint_execution = draft_manifest.get("blueprint_execution")
    if not isinstance(blueprint_execution, dict):
        fail("FAIL: Phase 13 blueprint_execution must be an object")
    for field in ("headline_claim_rendered", "contribution_stack_rendered", "headline_results_covered", "null_result_framing_applied"):
        if blueprint_execution.get(field) is not True:
            fail(f"FAIL: Phase 13 blueprint_execution.{field} must be true")
    polish_decl = draft_manifest.get("polish_report")
    if not isinstance(polish_decl, dict):
        fail("FAIL: Phase 13 draft manifest must include polish_report metadata")
    if polish_decl.get("path") != "manuscript/polish-report.json":
        fail("FAIL: Phase 13 polish_report.path must be manuscript/polish-report.json")
    if polish_decl.get("skill") != "scholar-polish" or polish_decl.get("mode") != "full":
        fail("FAIL: Phase 13 polish_report must declare scholar-polish full mode")
    if polish_decl.get("sha256") != sha256(polish_report_path):
        fail("FAIL: Phase 13 polish_report sha256 mismatch")
    if polish_report.get("verdict") != "PASS":
        fail("FAIL: Phase 13 polish report verdict must be PASS")
    engine = polish_report.get("polish_engine")
    if not isinstance(engine, dict) or engine.get("skill") != "scholar-polish" or engine.get("mode") != "full":
        fail("FAIL: Phase 13 polish_engine must be scholar-polish full mode")
    polish_engine_issues = validate_engine_provenance(engine, "Phase 13 polish_engine")
    if polish_engine_issues:
        fail("FAIL: Phase 13 polish_engine provenance is incomplete", polish_engine_issues)
    if polish_report.get("polished_manuscript_hash") != sha256(manuscript_path):
        fail("FAIL: Phase 13 polish report polished_manuscript_hash must match manuscript")
    if polish_report.get("ready_for_verification") is not True:
        fail("FAIL: Phase 13 polish report ready_for_verification must be true")
    if polish_report.get("citation_or_numeric_changes") not in (False, 0):
        fail("FAIL: Phase 13 scholar-polish must not alter citations or numeric anchors")
    if polish_report.get("argument_structure_changed") not in (False, 0):
        fail("FAIL: Phase 13 scholar-polish must not change argument structure")
    remaining_markers = polish_report.get("generic_markers_remaining")
    if not isinstance(remaining_markers, dict):
        fail("FAIL: Phase 13 polish report generic_markers_remaining must be an object")
    if int(remaining_markers.get("high", -1)) != 0:
        fail("FAIL: Phase 13 polish report must leave zero high-severity generic prose markers")
    spec_decl = draft_manifest.get("journal_spec")
    if not isinstance(spec_decl, dict):
        fail("FAIL: Phase 13 draft manifest must include journal_spec metadata")
    if spec_decl.get("path") != "manuscript/journal-spec.json":
        fail("FAIL: Phase 13 journal_spec.path must be manuscript/journal-spec.json")
    if spec_decl.get("skill") != "scholar-journal" or spec_decl.get("mode") != "prepare":
        fail("FAIL: Phase 13 journal_spec must declare scholar-journal prepare mode")
    if spec_decl.get("sha256") != sha256(journal_spec_path):
        fail("FAIL: Phase 13 journal_spec sha256 mismatch")
    required_journal_spec = (
        "verdict",
        "source_engine",
        "target_journal",
        "paper_type",
        "journal_profile_resolution",
        "total_word_range",
        "abstract_word_cap",
        "section_word_budget",
        "numeric_reporting_policy",
        "journal_structure",
        "display_architecture",
        "ready_for_drafting",
    )
    missing_journal_spec = [field for field in required_journal_spec if field not in journal_spec]
    if missing_journal_spec:
        fail("FAIL: Phase 13 journal-spec missing required fields", missing_journal_spec)
    if journal_spec.get("verdict") != "PASS" or journal_spec.get("ready_for_drafting") is not True:
        fail("FAIL: Phase 13 journal-spec verdict must be PASS and ready_for_drafting true")
    if journal_spec.get("source_engine") != "scholar-journal":
        fail("FAIL: Phase 13 journal-spec must be generated by scholar-journal")
    journal_engine = journal_spec.get("engine_provenance")
    journal_engine_issues = validate_engine_provenance(journal_engine, "Phase 13 journal_spec engine_provenance")
    if journal_engine_issues:
        fail("FAIL: Phase 13 journal-spec engine provenance is incomplete", journal_engine_issues)
    if journal_spec.get("target_journal") != research_question.get("target_journal", {}).get("primary") or journal_spec.get("paper_type") != research_question.get("paper_type"):
        fail("FAIL: Phase 13 journal-spec target must match Phase 1 research question")
    if journal_fit.get("primary_target") != journal_spec.get("target_journal") or journal_fit.get("paper_type") != journal_spec.get("paper_type"):
        fail("FAIL: Phase 13 journal-spec target must match Phase 1 journal-fit report")
    journal_resolution = journal_spec.get("journal_profile_resolution")
    if journal_resolution != journal_fit.get("journal_profile_resolution"):
        fail("FAIL: Phase 13 journal_spec journal_profile_resolution must match the approved Phase 1 journal-fit resolution")
    if journal_resolution != blueprint.get("journal_profile_resolution"):
        fail("FAIL: Phase 13 journal_spec journal_profile_resolution must match the approved Phase 12 blueprint")
    resolved_profile, resolution_issues = resolve_profile_for_target(journal_spec.get("target_journal"), journal_resolution, "Phase 13 journal_spec")
    if resolution_issues:
        fail("FAIL: Phase 13 journal_spec journal_profile_resolution is invalid", resolution_issues)
    blueprint_journal_structure = blueprint.get("journal_structure")
    blueprint_display_architecture = blueprint.get("display_architecture")
    journal_spec_structure = journal_spec.get("journal_structure")
    journal_spec_display = journal_spec.get("display_architecture")
    if journal_spec_structure != journal_resolution.get("journal_structure"):
        fail("FAIL: Phase 13 journal_spec journal_structure must match journal_profile_resolution.journal_structure")
    journal_structure_issues = validate_journal_structure(journal_spec_structure, journal_spec.get("target_journal"), "Phase 13 journal_spec", expected_profile=resolved_profile)
    if journal_structure_issues:
        fail("FAIL: Phase 13 journal_spec journal_structure is invalid", journal_structure_issues)
    if journal_spec_display != journal_resolution.get("display_architecture"):
        fail("FAIL: Phase 13 journal_spec display_architecture must match journal_profile_resolution.display_architecture")
    display_architecture_issues = validate_display_architecture(journal_spec_display, journal_spec.get("target_journal"), "Phase 13 journal_spec", expected_profile=resolved_profile)
    if display_architecture_issues:
        fail("FAIL: Phase 13 journal_spec display_architecture is invalid", display_architecture_issues)
    if journal_spec_structure != blueprint_journal_structure:
        fail("FAIL: Phase 13 journal_spec journal_structure must match the approved Phase 12 blueprint")
    if journal_spec_display != blueprint_display_architecture:
        fail("FAIL: Phase 13 journal_spec display_architecture must match the approved Phase 12 blueprint")
    lock_id = str(lock_manifest.get("lock_id", "")).strip()
    if latest_path.read_text(errors="ignore") != f"{lock_id}\n":
        fail("FAIL: Phase 13 LATEST.txt must still point to the lock used for drafting")
    if draft_manifest.get("lock_id") != lock_id:
        fail("FAIL: Phase 13 draft manifest lock_id must match active results lock")
    if draft_manifest.get("selected_manuscript_hash") != sha256(manuscript_path):
        fail("FAIL: Phase 13 selected_manuscript_hash does not match manuscript/manuscript-draft.md")
    source_hashes = draft_manifest.get("source_hashes")
    if not isinstance(source_hashes, dict):
        fail("FAIL: Phase 13 source_hashes must be an object")
    expected_sources = {
        "lock_manifest": sha256(lock_manifest_path),
        "stage1_verify": sha256(stage1_path),
        "manuscript_blueprint": sha256(blueprint_path),
        "references_bib": sha256(bib_path),
        "lit_theory": sha256(lit_path),
        "research_question": sha256(rq_path),
        "journal_fit": sha256(journal_fit_path),
        "design_blueprint": sha256(design_path),
        "variable_dictionary": sha256(var_dict_path),
        "analysis_plan": sha256(analysis_plan_path),
        "post_execution_review": sha256(post_review_path),
    }
    stale_sources = [
        f"{key} mismatch"
        for key, expected in expected_sources.items()
        if source_hashes.get(key) != expected
    ]
    if stale_sources:
        fail("FAIL: Phase 13 draft source_hashes are stale", stale_sources)
    if draft_manifest.get("lock_manifest_sha256") != lock_manifest.get("manifest_sha256"):
        fail("FAIL: Phase 13 lock_manifest_sha256 must match Phase 11 manifest_sha256")
    if stage1.get("ready_for_phase_12") is not True:
        fail("FAIL: Phase 13 requires Stage 1 ready_for_phase_12 true")
    total_words = word_count(manuscript_text)
    draft_prose_words = prose_word_count(manuscript_text)
    if total_words < 1300:
        fail(f"FAIL: Phase 13 manuscript is too short, found {total_words} words")
    short_format_pattern = re.compile(r"\b(research note|brief|short report|commentary|registered report|stage|replication note|letter)\b", re.IGNORECASE)
    paper_type_text = " ".join(str(journal_spec.get(field, "")) for field in ("paper_type", "article_type", "format"))
    if not short_format_pattern.search(paper_type_text):
        total_range = journal_spec.get("total_word_range") if isinstance(journal_spec.get("total_word_range"), dict) else {}
        try:
            declared_min_words = int(total_range.get("min", -1))
        except Exception:
            declared_min_words = -1
        if declared_min_words < 4000:
            fail("FAIL: Phase 13 full empirical journal articles require journal-spec total_word_range.min >= 4000 unless short-format exception is explicit")
        if draft_prose_words < 4000:
            fail(f"FAIL: Phase 13 full empirical journal manuscript has too little visible prose for submission-quality drafting, found {draft_prose_words} prose words")
    jargon_hits = reader_workflow_jargon_hits(manuscript_text)
    if jargon_hits:
        fail("FAIL: Phase 13 reader-facing manuscript prose exposes internal workflow language", jargon_hits[:20])
    reader_language = draft_manifest.get("reader_facing_language")
    if not isinstance(reader_language, dict):
        fail("FAIL: Phase 13 draft manifest reader_facing_language must be an object")
    if reader_language.get("workflow_jargon_hits") not in (0, "0") or reader_language.get("status") != "PASS":
        fail("FAIL: Phase 13 reader_facing_language must report zero workflow jargon hits and PASS status")
    placeholder_pattern = re.compile(r"\b(TBD|TODO|FIXME|XXX|lorem ipsum|placeholder|\[citation needed\])\b", re.IGNORECASE)
    placeholders = sorted(set(match.group(0) for match in placeholder_pattern.finditer(manuscript_text)))
    if placeholders:
        fail("FAIL: Phase 13 manuscript contains placeholder text", placeholders)
    sections = markdown_sections(manuscript_text)
    visible_headings = visible_heading_sequence(manuscript_text)
    discussion_mode = str(blueprint.get("discussion_mode", "")).strip() or "combined"
    theory_mode = str(blueprint_journal_structure.get("theory_presentation", "")).strip()
    methods_heading = norm_text(blueprint_journal_structure.get("methods_section_label", "")) or "data and methods"
    required_sections = {
        "abstract": (80, 300),
        "introduction": (250, None),
        methods_heading: (250, None),
        "results": (250, None),
        "discussion": (200, None),
    }
    theory_heading = None
    if theory_mode == "standalone_literature_theory":
        theory_heading = "literature review and theory"
        required_sections[theory_heading] = (300, None)
    elif theory_mode == "theory_section":
        theory_heading = "theory"
        required_sections[theory_heading] = (300, None)
    elif theory_mode == "background_section":
        theory_heading = "background"
        required_sections[theory_heading] = (300, None)
    if discussion_mode == "split":
        required_sections["conclusion"] = (120, None)
    expected_heading_order = ["abstract", "introduction"]
    if theory_heading:
        expected_heading_order.append(theory_heading)
    expected_heading_order.extend([methods_heading, "results", "discussion"])
    if discussion_mode == "split":
        expected_heading_order.append("conclusion")
    if not sequence_contains_in_order(visible_headings, expected_heading_order):
        fail(
            "FAIL: Phase 13 manuscript section order does not match the approved journal-specific blueprint",
            [f"expected_order={expected_heading_order}", f"actual_headings={visible_headings}"],
        )
    section_counts = {}
    section_prose_counts = {}
    section_issues = []
    for section, (minimum, maximum) in required_sections.items():
        if section not in sections:
            section_issues.append(f"{section}: missing ## heading")
            continue
        count = word_count(sections[section])
        prose_count = prose_word_count(sections[section])
        section_counts[section] = count
        section_prose_counts[section] = prose_count
        if prose_count < minimum:
            section_issues.append(f"{section}: {prose_count} prose words, minimum {minimum}")
        if maximum is not None and count > maximum:
            section_issues.append(f"{section}: {count} words, maximum {maximum}")
    if section_issues:
        fail("FAIL: Phase 13 manuscript sections are incomplete or underdeveloped", section_issues)
    main_text_word_count = sum(section_prose_counts.values())
    plan_issues = []
    if drafting_plan.get("verdict") != "PASS":
        plan_issues.append("drafting-plan verdict must be PASS")
    if drafting_plan.get("source_phase") not in ("13", 13):
        plan_issues.append("drafting-plan source_phase must be 13")
    section_briefs = drafting_plan.get("section_briefs")
    if not isinstance(section_briefs, dict):
        plan_issues.append("section_briefs must be an object")
    else:
        for section_name in required_sections:
            brief = section_briefs.get(section_name)
            if not isinstance(brief, dict):
                plan_issues.append(f"section_briefs.{section_name} missing")
                continue
            for field in ("section_purpose", "key_claim", "required_evidence", "source_roles", "forbidden_moves"):
                value = brief.get(field)
                if isinstance(value, list):
                    if not value:
                        plan_issues.append(f"section_briefs.{section_name}.{field} must be nonempty")
                elif word_count(str(value)) < 4:
                    plan_issues.append(f"section_briefs.{section_name}.{field} too thin")
    paragraph_map = drafting_plan.get("paragraph_purpose_map")
    if not isinstance(paragraph_map, list) or len(paragraph_map) < max(6, len(required_sections)):
        plan_issues.append("paragraph_purpose_map must include planned paragraphs across required sections")
    else:
        paragraph_sections = set()
        for idx, item in enumerate(paragraph_map):
            if not isinstance(item, dict):
                plan_issues.append(f"paragraph_purpose_map[{idx}] is not an object")
                continue
            section_name = norm_text(item.get("section", ""))
            paragraph_sections.add(section_name)
            for field in ("paragraph_id", "purpose", "claim"):
                if word_count(str(item.get(field, ""))) < 2:
                    plan_issues.append(f"paragraph_purpose_map[{idx}].{field} too thin")
            if not (item.get("source_roles") or item.get("evidence_artifacts") or item.get("mechanism_link")):
                plan_issues.append(f"paragraph_purpose_map[{idx}] must include source_roles, evidence_artifacts, or mechanism_link")
        missing_plan_sections = sorted(set(required_sections) - paragraph_sections - {"abstract", "references"})
        if missing_plan_sections:
            plan_issues.append(f"paragraph_purpose_map missing required sections {missing_plan_sections}")
    source_use_plan = drafting_plan.get("source_use_plan")
    if not isinstance(source_use_plan, list) or len(source_use_plan) < 10:
        plan_issues.append("source_use_plan must include at least 10 source-use entries")
    else:
        source_roles_seen = set()
        for idx, item in enumerate(source_use_plan):
            if not isinstance(item, dict):
                plan_issues.append(f"source_use_plan[{idx}] is not an object")
                continue
            role = str(item.get("argument_role", "")).strip()
            source_roles_seen.add(role)
            if not str(item.get("citation_key", "") or item.get("title", "")).strip():
                plan_issues.append(f"source_use_plan[{idx}] missing citation_key or title")
            for field in ("target_section", "claim_supported", "why_necessary"):
                if word_count(str(item.get(field, ""))) < 3:
                    plan_issues.append(f"source_use_plan[{idx}].{field} too thin")
        if not source_roles_seen.intersection({"rival", "competing_explanation", "alternative"}):
            plan_issues.append("source_use_plan must include rival or alternative explanation sources")
        if not source_roles_seen.intersection({"theory", "mechanism"}):
            plan_issues.append("source_use_plan must include theory or mechanism sources")
    results_plan = drafting_plan.get("results_interpretation_plan")
    expected_interpreted = [
        item.get("artifact_path")
        for item in blueprint.get("result_hierarchy", [])
        if isinstance(item, dict) and item.get("headline_status") in {"headline", "supporting"}
    ]
    if expected_interpreted and (not isinstance(results_plan, list) or len(results_plan) < len(set(expected_interpreted))):
        plan_issues.append("results_interpretation_plan must cover headline/supporting result artifacts")
    elif isinstance(results_plan, list):
        result_paths_seen = set()
        for idx, item in enumerate(results_plan):
            if not isinstance(item, dict):
                plan_issues.append(f"results_interpretation_plan[{idx}] is not an object")
                continue
            artifact_path = str(item.get("artifact_path", "")).strip()
            result_paths_seen.add(artifact_path)
            for field in ("interpretive_claim", "uncertainty_language", "mechanism_link", "limitation_language"):
                if word_count(str(item.get(field, ""))) < 4:
                    plan_issues.append(f"results_interpretation_plan[{idx}].{field} too thin")
        missing_result_plan = sorted(set(expected_interpreted) - result_paths_seen)
        if missing_result_plan:
            plan_issues.append(f"results_interpretation_plan missing {missing_result_plan}")
    revision_workflow = drafting_plan.get("revision_workflow")
    if not isinstance(revision_workflow, dict):
        plan_issues.append("revision_workflow must be an object")
    else:
        for field in ("outline_completed", "draft_after_plan", "self_critique_required"):
            if revision_workflow.get(field) is not True:
                plan_issues.append(f"revision_workflow.{field} must be true")
    if plan_issues:
        fail("FAIL: Phase 13 drafting-plan is incomplete", plan_issues[:40])
    critique_issues = []
    if self_critique.get("verdict") != "PASS" or self_critique.get("ready_for_verification") is not True:
        critique_issues.append("draft-self-critique must PASS with ready_for_verification true")
    if word_count(str(self_critique.get("strongest_rejection_reason", ""))) < 8:
        critique_issues.append("strongest_rejection_reason too thin")
    for field in ("unsupported_leap_scan", "missing_rival_scan", "claim_strength_scan", "workflow_language_scan"):
        value = self_critique.get(field)
        if not isinstance(value, dict):
            critique_issues.append(f"{field} must be an object")
            continue
        if value.get("status") not in {"PASS", "NOT_APPLICABLE", "REVISED"}:
            critique_issues.append(f"{field}.status invalid")
        if word_count(str(value.get("summary", ""))) < 6:
            critique_issues.append(f"{field}.summary too thin")
    revision_actions = self_critique.get("revision_actions")
    if not isinstance(revision_actions, list) or not revision_actions:
        critique_issues.append("revision_actions must be a nonempty list")
    else:
        for idx, item in enumerate(revision_actions):
            if not isinstance(item, dict):
                critique_issues.append(f"revision_actions[{idx}] is not an object")
                continue
            if word_count(str(item.get("action", ""))) < 4:
                critique_issues.append(f"revision_actions[{idx}].action too thin")
    if critique_issues:
        fail("FAIL: Phase 13 draft-self-critique is incomplete", critique_issues[:30])
    declared_counts = draft_manifest.get("section_word_counts")
    if not isinstance(declared_counts, dict):
        fail("FAIL: Phase 13 section_word_counts must be an object")
    count_mismatches = [
        f"{section}: declared {declared_counts.get(section)} actual {count}"
        for section, count in section_counts.items()
        if int(declared_counts.get(section, -1)) != count
    ]
    if count_mismatches:
        fail("FAIL: Phase 13 section_word_counts do not match manuscript", count_mismatches)
    declared_prose_counts = draft_manifest.get("section_prose_word_counts")
    if not isinstance(declared_prose_counts, dict):
        fail("FAIL: Phase 13 section_prose_word_counts must be an object")
    prose_count_mismatches = [
        f"{section}: declared {declared_prose_counts.get(section)} actual {count}"
        for section, count in section_prose_counts.items()
        if int(declared_prose_counts.get(section, -1)) != count
    ]
    if prose_count_mismatches:
        fail("FAIL: Phase 13 section_prose_word_counts do not match manuscript", prose_count_mismatches)
    section_budget = journal_spec.get("section_word_budget")
    if not isinstance(section_budget, dict):
        fail("FAIL: Phase 13 journal-spec section_word_budget must be an object")
    manifest_budget = draft_manifest.get("section_word_budget")
    if manifest_budget != section_budget:
        fail("FAIL: Phase 13 draft manifest section_word_budget must match journal-spec")
    numeric_reporting_policy = journal_spec.get("numeric_reporting_policy")
    numeric_policy_issues = validate_numeric_reporting_policy(numeric_reporting_policy, "Phase 13 journal_spec")
    if numeric_policy_issues:
        fail("FAIL: Phase 13 journal numeric reporting policy is invalid", numeric_policy_issues)
    manifest_numeric_policy = draft_manifest.get("numeric_reporting_policy")
    if manifest_numeric_policy != numeric_reporting_policy:
        fail("FAIL: Phase 13 draft manifest numeric_reporting_policy must match journal-spec")
    total_range = journal_spec.get("total_word_range")
    if not isinstance(total_range, dict):
        fail("FAIL: Phase 12 journal-spec total_word_range must be an object")
    total_min = int(total_range.get("min", -1))
    total_max = int(total_range.get("max", -1))
    if total_min < 1 or total_max < total_min:
        fail("FAIL: Phase 13 journal-spec total_word_range is invalid")
    # Audit 2026-05-03: profile→spec equality gate.
    # The spec's total_word_range MUST match the journal profile's
    # total_word_budget. Fixture-leak bug ships JMF specs with min=1300
    # while the JMF profile demands min=7000; downstream gates then anchor
    # to a hollowed-out floor and the manuscript ships at 2,500-3,500
    # words. Skip for short-format papers (paper_type already short-circuits
    # the > 4000 check above).
    if not short_format_pattern.search(paper_type_text):
        profile_budget = resolved_profile.get("total_word_budget") if isinstance(resolved_profile, dict) else None
        if isinstance(profile_budget, dict):
            try:
                profile_min = int(profile_budget.get("min", -1))
                profile_max = int(profile_budget.get("max", -1))
            except Exception:
                profile_min = profile_max = -1
            if profile_min >= 1 and profile_max >= profile_min:
                profile_spec_issues = []
                if total_min != profile_min:
                    profile_spec_issues.append(
                        f"spec.total_word_range.min={total_min} but profile "
                        f"total_word_budget.min={profile_min} for journal "
                        f"{resolved_profile.get('name','?')} — spec floor has been "
                        f"hollowed out below the journal's calibrated minimum"
                    )
                if total_max != profile_max:
                    profile_spec_issues.append(
                        f"spec.total_word_range.max={total_max} but profile "
                        f"total_word_budget.max={profile_max} for journal "
                        f"{resolved_profile.get('name','?')}"
                    )
                # Soft check: sum of section target_words must reach 85% of profile floor.
                section_budget_for_sum = journal_spec.get("section_word_budget") if isinstance(journal_spec.get("section_word_budget"), dict) else {}
                sum_targets = 0
                sum_targets_seen = 0
                for sec_name, sec_obj in section_budget_for_sum.items():
                    if not isinstance(sec_obj, dict):
                        continue
                    try:
                        tw = int(sec_obj.get("target_words", -1))
                    except Exception:
                        tw = -1
                    if tw > 0:
                        sum_targets += tw
                        sum_targets_seen += 1
                if sum_targets_seen >= 4 and sum_targets < int(profile_min * 0.85):
                    profile_spec_issues.append(
                        f"sum of section_word_budget.target_words={sum_targets} is below "
                        f"85% of profile.total_word_budget.min={profile_min} "
                        f"(journal {resolved_profile.get('name','?')}); section targets "
                        f"do not realize the journal's calibrated total floor"
                    )
                if profile_spec_issues:
                    fail(
                        "FAIL: Phase 13 journal-spec disagrees with the resolved journal profile",
                        profile_spec_issues,
                    )
    if main_text_word_count < total_min or main_text_word_count > total_max:
        fail(
            f"FAIL: Phase 13 main-text prose word count {main_text_word_count} is outside "
            f"journal range {total_min}-{total_max}; references, tables, figures, "
            f"declarations, trace anchors, and captions do not count toward manuscript substance"
        )
    abstract_cap = int(journal_spec.get("abstract_word_cap", -1))
    if abstract_cap < 50:
        fail("FAIL: Phase 13 journal-spec abstract_word_cap is invalid")
    if section_counts.get("abstract", 0) > abstract_cap:
        fail(f"FAIL: Phase 13 abstract exceeds journal cap {abstract_cap}")
    budget_issues = []
    circular_budget_sections = []
    exact_target_sections = []
    for section, count in section_prose_counts.items():
        budget = section_budget.get(section)
        if not isinstance(budget, dict):
            budget_issues.append(f"{section}: missing journal budget")
            continue
        target_words = int(budget.get("target_words", -1))
        min_words = int(budget.get("min_words", max(0, round(target_words * 0.8))))
        max_words = budget.get("max_words")
        max_words_int = None if max_words in (None, "") else int(max_words)
        if target_words < 1 or min_words < 1:
            budget_issues.append(f"{section}: invalid target/min budget")
            continue
        if section != "abstract" and target_words == count:
            exact_target_sections.append(section)
        if (
            section != "abstract"
            and target_words == count
            and min_words == max(50, count - 50)
            and max_words_int is None
        ):
            circular_budget_sections.append(section)
        if count < min_words:
            budget_issues.append(f"{section}: {count} words below journal minimum {min_words}")
        if max_words_int is not None and section_counts.get(section, 0) > max_words_int:
            budget_issues.append(f"{section}: {section_counts.get(section, 0)} words above journal maximum {max_words_int}")
        # Audit 2026-05-03: anchor-to-floor anti-pattern fix.
        # For full empirical articles, target_words is the binding floor (the
        # journal-calibrated section size). min_words is a short-format safety
        # net, NOT a target. A draft that hits min_words but is far below
        # target_words is a hollowed-out section, not a successful section.
        if (
            not short_format_pattern.search(paper_type_text)
            and section != "abstract"
            and target_words >= 1
            and count < int(target_words * 0.85)
        ):
            budget_issues.append(
                f"{section}: {count} words is below 85% of journal target_words {target_words} "
                f"(for full empirical articles target_words is the binding floor; "
                f"min_words is a short-format safety net only)"
            )
    if circular_budget_sections:
        fail(
            "FAIL: Phase 13 journal section budgets appear to be reverse-engineered from the written draft",
            circular_budget_sections,
        )
    if len(exact_target_sections) >= max(4, len(section_counts) - 1):
        fail(
            "FAIL: Phase 13 journal section target_words appear to be copied from realized draft lengths instead of journal calibration",
            exact_target_sections,
        )
    if budget_issues:
        fail("FAIL: Phase 13 manuscript does not meet journal section word budgets", budget_issues)
    budget_compliance = draft_manifest.get("budget_compliance")
    if not isinstance(budget_compliance, dict):
        fail("FAIL: Phase 13 budget_compliance must be an object")
    if budget_compliance.get("status") != "PASS" or budget_compliance.get("target_journal") != journal_spec.get("target_journal"):
        fail("FAIL: Phase 13 budget_compliance must PASS for the target journal")
    if int(budget_compliance.get("total_word_count", -1)) != total_words:
        fail("FAIL: Phase 13 budget_compliance total_word_count mismatch")
    if int(budget_compliance.get("main_text_word_count", -1)) != main_text_word_count:
        fail("FAIL: Phase 13 budget_compliance main_text_word_count mismatch")
    if budget_compliance.get("abstract_within_cap") is not True:
        fail("FAIL: Phase 13 budget_compliance must confirm abstract_within_cap")
    quality_gate = draft_manifest.get("draft_quality_gate")
    if not isinstance(quality_gate, dict):
        fail("FAIL: Phase 13 draft_quality_gate must be an object")
    if quality_gate.get("status") != "PASS":
        fail("FAIL: Phase 13 draft_quality_gate status must be PASS")
    for field in ("anti_stub_checked", "repetition_checked", "section_substance_checked", "locked_evidence_integrated", "journal_fit_checked", "polish_applied"):
        if quality_gate.get(field) is not True:
            fail(f"FAIL: Phase 13 draft_quality_gate.{field} must be true")
    for field in ("reader_facing_translation_checked", "theory_synthesis_checked", "results_comparison_checked", "results_theory_link_checked"):
        if quality_gate.get(field) is not True:
            fail(f"FAIL: Phase 13 draft_quality_gate.{field} must be true")
    try:
        raw_variable_name_count = int(quality_gate.get("raw_variable_name_count", -1))
    except Exception:
        fail("FAIL: Phase 13 draft_quality_gate.raw_variable_name_count must be numeric")
    try:
        repeated_sentence_limit = int(quality_gate.get("repeated_sentence_limit", 2))
        declared_max_repeat = int(quality_gate.get("max_repeated_sentence_count", -1))
    except Exception:
        fail("FAIL: Phase 13 draft_quality_gate repetition counts must be numeric")
    if repeated_sentence_limit < 1 or repeated_sentence_limit > 2:
        fail("FAIL: Phase 13 repeated_sentence_limit must be 1 or 2")
    sentence_source = re.sub(r"<!--.*?-->", " ", manuscript_text, flags=re.DOTALL)
    sentence_source = re.sub(r"\[[^\]]+\]", " ", sentence_source)
    sentence_counts = {}
    for sentence in re.split(r"(?<=[.!?])\s+", sentence_source):
        normalized = re.sub(r"[^a-z0-9]+", " ", sentence.lower()).strip()
        if word_count(normalized) < 8:
            continue
        sentence_counts[normalized] = sentence_counts.get(normalized, 0) + 1
    actual_max_repeat = max(sentence_counts.values(), default=0)
    if declared_max_repeat != actual_max_repeat:
        fail("FAIL: Phase 13 draft_quality_gate max_repeated_sentence_count does not match manuscript")
    if actual_max_repeat > repeated_sentence_limit:
        repeated_examples = sorted(
            f"{count}x: {sentence[:90]}"
            for sentence, count in sentence_counts.items()
            if count > repeated_sentence_limit
        )
        fail("FAIL: Phase 13 manuscript repeats substantive sentences too often", repeated_examples[:10])
    section_quality = quality_gate.get("section_quality")
    if not isinstance(section_quality, dict):
        fail("FAIL: Phase 13 draft_quality_gate.section_quality must be an object")
    section_quality_issues = []
    section_evidence_text = {}
    for section in required_sections:
        item = section_quality.get(section)
        if not isinstance(item, dict):
            section_quality_issues.append(f"{section}: missing quality entry")
            continue
        if item.get("status") != "PASS":
            section_quality_issues.append(f"{section}: status must be PASS")
        if item.get("not_stub") is not True:
            section_quality_issues.append(f"{section}: not_stub must be true")
        if item.get("section_specific_evidence") is not True:
            section_quality_issues.append(f"{section}: section_specific_evidence must be true")
        evidence_str = str(item.get("evidence", "")).strip()
        if not evidence_str:
            section_quality_issues.append(f"{section}: evidence missing")
            continue
        # Audit 2026-05-03: stub-PASS detection.
        # Empty-string check is trivially gamed by writing any non-empty
        # text. Require evidence to be substantive (>= 25 words) and
        # section-specific (low pairwise Jaccard similarity). Prevents the
        # "write the same boilerplate across all sections" fixture pattern.
        if word_count(evidence_str) < 25:
            section_quality_issues.append(
                f"{section}: evidence is too thin (got {word_count(evidence_str)} words, "
                f"need >= 25); section_quality.evidence must demonstrate "
                f"section-specific substance, not boilerplate"
            )
            continue
        section_evidence_text[section] = evidence_str
    if len(section_evidence_text) >= 2:
        def _evidence_token_set(text):
            return set(re.findall(r"[a-z0-9]{3,}", text.lower()))
        evidence_tokens = {sec: _evidence_token_set(t) for sec, t in section_evidence_text.items()}
        sections_listed = sorted(evidence_tokens.keys())
        for i in range(len(sections_listed)):
            for j in range(i + 1, len(sections_listed)):
                a_sec, b_sec = sections_listed[i], sections_listed[j]
                a_toks, b_toks = evidence_tokens[a_sec], evidence_tokens[b_sec]
                if not a_toks or not b_toks:
                    continue
                intersection = len(a_toks & b_toks)
                union = len(a_toks | b_toks)
                if union == 0:
                    continue
                jaccard = intersection / union
                if jaccard > 0.7:
                    section_quality_issues.append(
                        f"{a_sec} vs {b_sec}: section_quality.evidence are nearly "
                        f"identical (Jaccard={jaccard:.2f}); evidence text appears "
                        f"copy-pasted across sections rather than describing "
                        f"section-specific substance"
                    )
    if section_quality_issues:
        fail("FAIL: Phase 13 section quality gate is incomplete", section_quality_issues)
    substantive_counts = quality_gate.get("substantive_paragraph_counts")
    if not isinstance(substantive_counts, dict):
        fail("FAIL: Phase 13 draft_quality_gate.substantive_paragraph_counts must be an object")
    paragraph_rules = {
        "introduction": 2,
        methods_heading: 2,
        "results": 3,
        "discussion": 2,
    }
    if theory_heading:
        paragraph_rules[theory_heading] = 3
    paragraph_issues = []
    for section, minimum in paragraph_rules.items():
        actual_paragraphs = len(prose_paragraphs(sections.get(section, ""), min_words=40))
        if int(substantive_counts.get(section, -1)) != actual_paragraphs:
            paragraph_issues.append(f"{section}: substantive paragraph count mismatch")
        if actual_paragraphs < minimum:
            paragraph_issues.append(f"{section}: {actual_paragraphs} substantive paragraphs, minimum {minimum}")
    if discussion_mode == "split":
        actual_conclusion_paragraphs = len(prose_paragraphs(sections.get("conclusion", ""), min_words=40))
        if int(substantive_counts.get("conclusion", -1)) != actual_conclusion_paragraphs:
            paragraph_issues.append("conclusion: substantive paragraph count mismatch")
        if actual_conclusion_paragraphs < 1:
            paragraph_issues.append("conclusion: must contain at least 1 substantive paragraph")
    results_prose_paragraph_count = quality_gate.get("results_prose_paragraph_count")
    actual_results_paragraphs = len(prose_paragraphs(sections.get("results", ""), min_words=35))
    if int(results_prose_paragraph_count if results_prose_paragraph_count is not None else -1) != actual_results_paragraphs:
        paragraph_issues.append("results: results_prose_paragraph_count mismatch")
    if actual_results_paragraphs < 2:
        paragraph_issues.append("results: must contain at least 2 substantive prose paragraphs in addition to displayed evidence")
    theory_text_lower = (sections.get(theory_heading, "") if theory_heading else sections.get("introduction", "")).lower()
    theory_section_label = theory_heading or "introduction"
    theory_cites = section_citekeys(sections.get(theory_heading, "") if theory_heading else sections.get("introduction", ""))
    if len(theory_cites) < 20:
        paragraph_issues.append(f"{theory_section_label}: cites only {len(theory_cites)} unique keys, minimum 20")
    if not any(token in theory_text_lower for token in ("mechanism", "pathway", "process")):
        paragraph_issues.append(f"{theory_section_label}: must name at least one mechanism or pathway")
    if not any(token in theory_text_lower for token in ("rival", "alternative", "competing", "by contrast", "compensation", "resilience")):
        paragraph_issues.append(f"{theory_section_label}: must name at least one rival or alternative explanation")
    if not any(token in theory_text_lower for token in ("scope", "boundary", "condition", "heterogeneity", "under what", "not all")):
        paragraph_issues.append(f"{theory_section_label}: must name at least one scope or boundary condition")
    if not any(token in theory_text_lower for token in ("hypoth", "expect", "predict")):
        paragraph_issues.append(f"{theory_section_label}: must bridge theory to at least one hypothesis or expectation")
    hypothesis_list_hits = hypothesis_display_hits(manuscript_text)
    if hypothesis_list_hits:
        if not displayed_hypotheses_allowed(journal_spec, draft_manifest, blueprint, journal_fit):
            paragraph_issues.extend(
                "hypotheses must be integrated into theory prose rather than displayed as proposal-style bullets/lists: " + hit
                for hit in hypothesis_list_hits[:12]
            )
        else:
            bare_hypothesis_hits = bare_hypothesis_display_hits(manuscript_text)
            if bare_hypothesis_hits:
                paragraph_issues.extend(
                    "displayed hypotheses must be preceded by theoretical motivation: " + hit
                    for hit in bare_hypothesis_hits[:12]
                )
    results_text_lower = sections.get("results", "").lower()
    if not any(token in results_text_lower for token in ("by contrast", "compared", "relative to", "while", "whereas", "robustness")):
        paragraph_issues.append("results: must compare the headline evidence with at least one secondary specification or diagnostic")
    if not any(token in results_text_lower for token in ("mechanism", "theory", "hypoth", "expect", "consistent with", "in line with")):
        paragraph_issues.append("results: must return the empirical pattern to theory or mechanism language")
    if not any(token in results_text_lower for token in ("uncertainty", "precision", "weak", "null", "bounded", "cautious", "limit")):
        paragraph_issues.append("results: must interpret uncertainty, weakness, or boundary of the evidence")
    discussion_text_lower = sections.get("discussion", "").lower()
    if not any(token in discussion_text_lower for token in ("limitation", "limits", "scope", "observational", "cannot", "does not")):
        paragraph_issues.append("discussion: must include explicit limitations or scope language")
    if paragraph_issues:
        fail("FAIL: Phase 13 manuscript lacks substantive section development", paragraph_issues)
    visible_reader_text = visible_markdown_text(manuscript_text)
    raw_variable_hits = []
    for row in var_rows:
        variable_name = str(row.get("variable", "")).strip()
        if not looks_machine_like_label(variable_name):
            continue
        if contains_literal_token(visible_reader_text, variable_name):
            raw_variable_hits.append(variable_name)
    unique_raw_hits = sorted(set(raw_variable_hits))
    if raw_variable_name_count != len(unique_raw_hits):
        fail("FAIL: Phase 13 draft_quality_gate.raw_variable_name_count does not match visible manuscript content")
    if unique_raw_hits:
        fail("FAIL: Phase 13 visible manuscript content exposes raw dataset variable names", unique_raw_hits[:20])
    max_visible_decimals = max(
        int(numeric_reporting_policy.get("inferential_digits", 3)),
        int(numeric_reporting_policy.get("descriptive_digits", 2)),
    )
    numeric_visible_sections = "\n\n".join(
        sections.get(name, "")
        for name in ("abstract", "data and methods", "results", "discussion")
        if sections.get(name, "")
    )
    numeric_style_issues = []
    if numeric_reporting_policy.get("allow_scientific_notation") is not True:
        scientific_tokens = find_scientific_notation_tokens(numeric_visible_sections)
        if scientific_tokens:
            numeric_style_issues.append(
                "scientific notation in reader-facing prose: " + ", ".join(scientific_tokens[:10])
            )
    overprecise_tokens = find_overprecise_decimal_tokens(numeric_visible_sections, max_visible_decimals)
    if overprecise_tokens:
        numeric_style_issues.append(
            "overprecise decimals in reader-facing prose: " +
            ", ".join(f"{token} ({decimals} dp)" for token, decimals in overprecise_tokens[:10])
        )
    if numeric_style_issues:
        fail("FAIL: Phase 13 manuscript violates journal numeric reporting policy", numeric_style_issues)
    bib_text = bib_path.read_text(errors="ignore")
    bib_keys = set(re.findall(r"@\w+\s*\{\s*([^,\s]+)", bib_text))
    if len(bib_keys) < 30:
        fail(f"FAIL: Phase 13 references.bib must retain at least 30 entries, found {len(bib_keys)}")
    cited_keys = set(re.findall(r"@([A-Za-z0-9_:\-]+)", manuscript_text))
    unresolved_cites = sorted(cited_keys - bib_keys)
    if len(cited_keys) < 30:
        fail(f"FAIL: Phase 13 manuscript must cite at least 30 unique BibTeX keys, found {len(cited_keys)}")
    if unresolved_cites:
        fail("FAIL: Phase 13 manuscript cites keys absent from references.bib", unresolved_cites)
    citation_plan = draft_manifest.get("citation_plan")
    if not isinstance(citation_plan, dict):
        fail("FAIL: Phase 13 citation_plan must be an object")
    if int(citation_plan.get("bib_entry_count", -1)) != len(bib_keys):
        fail("FAIL: Phase 13 citation_plan bib_entry_count does not match references.bib")
    if int(citation_plan.get("unique_citations_in_draft", -1)) != len(cited_keys):
        fail("FAIL: Phase 13 citation_plan unique_citations_in_draft does not match manuscript")
    if int(citation_plan.get("unique_citations_in_draft", -1)) < 30:
        fail("FAIL: Phase 13 citation_plan must record at least 30 unique citations")
    if int(citation_plan.get("unique_citations_in_draft", -1)) != len(cited_keys):
        fail("FAIL: Phase 13 citation_plan unique_citations_in_draft does not match manuscript")
    if citation_plan.get("all_citations_in_bib") is not True or int(citation_plan.get("unresolved_citation_count", -1)) != 0:
        fail("FAIL: Phase 13 citation_plan must report all citations resolved")
    post_constraints = post_review.get("claim_constraints")
    if not isinstance(post_constraints, dict):
        fail("FAIL: Phase 13 requires Phase 9 claim_constraints")
    forbidden_terms = set(str(term).strip().lower() for term in post_constraints.get("forbidden_claim_verbs", []) if str(term).strip())
    forbidden_terms.update(["prove", "proves", "proved", "guarantee", "guarantees", "guaranteed"])
    forbidden_claims = []
    lower_manuscript = manuscript_text.lower()
    for term in sorted(forbidden_terms):
        if re.search(rf"\b{re.escape(term)}\b", lower_manuscript):
            forbidden_claims.append(term)
    claim_discipline = draft_manifest.get("claim_discipline")
    if not isinstance(claim_discipline, dict):
        fail("FAIL: Phase 13 claim_discipline must be an object")
    if forbidden_claims:
        fail("FAIL: Phase 13 manuscript contains overclaiming language", sorted(set(forbidden_claims)))
    if claim_discipline.get("overclaim_count") != 0 or claim_discipline.get("phase9_constraints_used") is not True:
        fail("FAIL: Phase 13 claim_discipline must report zero overclaims and Phase 9 constraint use")
    required_disclosures = [str(item).strip().lower() for item in post_constraints.get("required_disclosures", []) if str(item).strip()]
    missing_disclosures = [
        item for item in required_disclosures
        if not disclosure_semantically_covered(item, lower_manuscript)
    ]
    if missing_disclosures:
        fail("FAIL: Phase 13 manuscript is missing Phase 9 required disclosures", missing_disclosures)
    declared_disclosures = claim_discipline.get("required_disclosures_present")
    declared_set = set(str(item).strip().lower() for item in (declared_disclosures or []) if str(item).strip())
    required_set = set(required_disclosures)
    required_label_set = set(disclosure_semantic_label(item) for item in required_disclosures)
    if not (
        required_set.issubset(declared_set)
        or required_label_set.issubset(declared_set)
    ):
        fail("FAIL: Phase 13 claim_discipline must list Phase 9 required disclosures present as exact strings or semantic disclosure labels")
    alignment = draft_manifest.get("content_alignment")
    if not isinstance(alignment, dict):
        fail("FAIL: Phase 13 content_alignment must be an object")
    rq_terms = {
        "x": str(research_question.get("x", "")).strip().lower(),
        "y": str(research_question.get("y", "")).strip().lower(),
    }
    missing_rq_terms = [key for key, value in rq_terms.items() if value and value not in lower_manuscript]
    if missing_rq_terms:
        fail("FAIL: Phase 13 manuscript does not include core research-question terms", missing_rq_terms)
    if alignment.get("research_question_answered") is not True or alignment.get("mechanism_integrated") is not True or alignment.get("limitations_discussed") is not True:
        fail("FAIL: Phase 13 content_alignment must confirm RQ answer, mechanism integration, and limitations")
    locked_artifacts = lock_manifest.get("locked_artifacts")
    if not isinstance(locked_artifacts, list) or not locked_artifacts:
        fail("FAIL: Phase 13 requires non-empty locked_artifacts from Phase 11")
    locked_by_source = {
        str(item.get("source_path", "")).strip(): item
        for item in locked_artifacts
        if isinstance(item, dict)
    }
    coverage = draft_manifest.get("locked_result_coverage")
    if not isinstance(coverage, list) or not coverage:
        fail("FAIL: Phase 13 locked_result_coverage must be a non-empty list")
    coverage_by_source = {
        str(item.get("source_path", "")).strip(): item
        for item in coverage
        if isinstance(item, dict)
    }
    if set(coverage_by_source) != set(locked_by_source):
        missing = sorted(set(locked_by_source) - set(coverage_by_source))
        extra = sorted(set(coverage_by_source) - set(locked_by_source))
        fail("FAIL: Phase 13 locked_result_coverage must cover every locked artifact exactly", missing + extra)
    reader_facing_roles = TABLE_ARTIFACT_ROLES | {"figure_file"}
    results_text = sections.get("results", "")
    coverage_issues = []
    display_required_roles = TABLE_ARTIFACT_ROLES | {"figure_file"}
    displayed_sources = []
    results_table_callouts = []
    results_figure_callouts = []
    for source_path, lock_item in locked_by_source.items():
        item = coverage_by_source[source_path]
        locked_path = str(lock_item.get("locked_path", "")).strip()
        role = str(lock_item.get("artifact_role", "")).strip()
        anchor = str(item.get("manuscript_anchor", "")).strip()
        if item.get("locked_path") != locked_path:
            coverage_issues.append(f"{source_path}: locked_path mismatch")
        if item.get("artifact_role") != lock_item.get("artifact_role"):
            coverage_issues.append(f"{source_path}: artifact_role mismatch")
        if role in reader_facing_roles:
            if item.get("used_in_manuscript") is not True:
                coverage_issues.append(f"{source_path}: reader-facing artifact used_in_manuscript must be true")
            if not anchor or anchor not in manuscript_text:
                coverage_issues.append(f"{source_path}: manuscript_anchor missing from draft")
            if source_path not in manuscript_text or locked_path not in manuscript_text:
                coverage_issues.append(f"{source_path}: draft must name both source_path and locked_path in trace anchor")
            if role in display_required_roles:
                display_anchor = str(item.get("display_anchor", "")).strip()
                display_status = str(item.get("display_status", "")).strip()
                display_type = str(item.get("display_type", "")).strip()
                caption_text = str(item.get("caption_text", "")).strip()
                display_label = str(item.get("display_label", "")).strip()
                results_callout = str(item.get("results_callout", "")).strip()
                if display_status not in {"rendered_inline", "rendered_appendix", "preview_link", "journal_exempt"}:
                    coverage_issues.append(f"{source_path}: display_status invalid")
                if not display_anchor or display_anchor not in manuscript_text:
                    coverage_issues.append(f"{source_path}: display_anchor missing from draft")
                if not display_type:
                    coverage_issues.append(f"{source_path}: display_type missing")
                if not caption_text:
                    coverage_issues.append(f"{source_path}: caption_text missing")
                if not display_label:
                    coverage_issues.append(f"{source_path}: display_label missing")
                elif role in TABLE_ARTIFACT_ROLES and not re.match(r"^Table\s+\d+$", display_label):
                    coverage_issues.append(f"{source_path}: display_label must look like Table N")
                elif role == "figure_file" and not re.match(r"^Figure\s+\d+$", display_label):
                    coverage_issues.append(f"{source_path}: display_label must look like Figure N")
                if not results_callout:
                    coverage_issues.append(f"{source_path}: results_callout missing")
                if display_status != "journal_exempt":
                    displayed_sources.append(source_path)
                    window = display_window(manuscript_text, display_anchor)
                    if role in TABLE_ARTIFACT_ROLES:
                        allowed_table_display_types = {"markdown_table", "html_table"} | REGRESSION_TABLE_DISPLAY_TYPES
                        if display_type not in allowed_table_display_types:
                            coverage_issues.append(f"{source_path}: table display_type must be markdown/html or regression_table_*")
                        if role in REGRESSION_TABLE_ROLES and not display_type.startswith("regression_table"):
                            coverage_issues.append(f"{source_path}: regression table artifacts must use regression_table_* display_type")
                        if not has_markdown_or_html_table(window):
                            coverage_issues.append(f"{source_path}: visible table block missing near display_anchor")
                        if display_label and display_label not in manuscript_text:
                            coverage_issues.append(f"{source_path}: display_label missing from manuscript text")
                        if display_label and not has_results_callout(results_text, display_label):
                            coverage_issues.append(f"{source_path}: Results section must explicitly call out {display_label} with a reporting verb")
                        elif display_label:
                            results_table_callouts.append(display_label)
                    elif role == "figure_file":
                        if display_type not in {"markdown_image", "html_image", "figure_link_block"}:
                            coverage_issues.append(f"{source_path}: figure display_type invalid")
                        if not has_visible_figure_block(window):
                            coverage_issues.append(f"{source_path}: visible figure block missing near display_anchor")
                        if display_label and display_label not in manuscript_text:
                            coverage_issues.append(f"{source_path}: display_label missing from manuscript text")
                        if display_label and not has_results_callout(results_text, display_label):
                            coverage_issues.append(f"{source_path}: Results section must explicitly call out {display_label} with a reporting verb")
                        elif display_label:
                            results_figure_callouts.append(display_label)
                elif "journal" not in caption_text.lower():
                    coverage_issues.append(f"{source_path}: journal_exempt requires journal-calibrated rationale in caption_text")
        else:
            if item.get("used_in_manuscript") is not False:
                coverage_issues.append(f"{source_path}: provenance artifact used_in_manuscript must be false")
    if coverage_issues:
        fail("FAIL: Phase 13 locked result coverage is incomplete", coverage_issues)
    registry_display_issues = displayed_registry_sources_from_coverage(coverage) + registry_like_table_display_hits(manuscript_text)
    if registry_display_issues:
        fail("FAIL: Phase 13 manuscript uses registry/model-ladder evidence as reader-facing empirical tables", registry_display_issues[:25])
    if quantitative_empirical_regression_table_required(
        manuscript_text,
        draft_manifest,
        blueprint,
        analysis_plan_path.read_text(errors="ignore"),
        lock_manifest,
    ) and not has_canonical_regression_display(coverage):
        fail(
            "FAIL: Phase 13 quantitative manuscript lacks a canonical reader-facing regression table",
            [
                "Display at least one locked main_regression_table or regression_table artifact with regression_table_* display_type",
                "Do not use results-registry.csv, model-ladder tables, or focal-coefficient extracts as the main empirical table",
            ],
        )
    display_evidence = draft_manifest.get("display_evidence")
    if not isinstance(display_evidence, dict):
        fail("FAIL: Phase 13 display_evidence must be an object")
    if display_evidence.get("status") != "PASS":
        fail("FAIL: Phase 13 display_evidence status must be PASS")
    expected_table_sources = sorted(
        source_path
        for source_path, item in coverage_by_source.items()
        if str(item.get("artifact_role", "")).strip() in TABLE_ARTIFACT_ROLES
        and str(item.get("display_status", "")).strip() != "journal_exempt"
    )
    expected_figure_sources = sorted(
        source_path
        for source_path, item in coverage_by_source.items()
        if str(item.get("artifact_role", "")).strip() == "figure_file"
        and str(item.get("display_status", "")).strip() != "journal_exempt"
    )
    actual_displayed_sources = sorted(displayed_sources)
    declared_displayed_sources = sorted(
        str(item).strip()
        for item in display_evidence.get("displayed_sources", [])
        if str(item).strip()
    ) if isinstance(display_evidence.get("displayed_sources"), list) else []
    if declared_displayed_sources != actual_displayed_sources:
        fail("FAIL: Phase 13 display_evidence.displayed_sources mismatch", actual_displayed_sources + declared_displayed_sources)
    if int(display_evidence.get("required_table_display_min", -1)) != (1 if expected_table_sources else 0):
        fail("FAIL: Phase 13 required_table_display_min is invalid")
    if int(display_evidence.get("required_figure_display_min", -1)) != (1 if expected_figure_sources else 0):
        fail("FAIL: Phase 13 required_figure_display_min is invalid")
    if int(display_evidence.get("table_display_count", -1)) != len(expected_table_sources):
        fail("FAIL: Phase 13 table_display_count must match displayed table artifacts")
    if int(display_evidence.get("figure_display_count", -1)) != len(expected_figure_sources):
        fail("FAIL: Phase 13 figure_display_count must match displayed figure artifacts")
    declared_table_callouts = sorted(
        str(item).strip()
        for item in display_evidence.get("results_table_callouts", [])
        if str(item).strip()
    ) if isinstance(display_evidence.get("results_table_callouts"), list) else []
    declared_figure_callouts = sorted(
        str(item).strip()
        for item in display_evidence.get("results_figure_callouts", [])
        if str(item).strip()
    ) if isinstance(display_evidence.get("results_figure_callouts"), list) else []
    if declared_table_callouts != sorted(results_table_callouts):
        fail("FAIL: Phase 13 display_evidence.results_table_callouts mismatch")
    if declared_figure_callouts != sorted(results_figure_callouts):
        fail("FAIL: Phase 13 display_evidence.results_figure_callouts mismatch")
    if display_evidence.get("all_display_items_called_out_in_results") is not True:
        fail("FAIL: Phase 13 display_evidence must confirm all display items are called out in Results prose")
    display_cap = blueprint_display_architecture.get("main_text_display_cap")
    if display_cap not in (None, "") and (len(expected_table_sources) + len(expected_figure_sources)) > int(display_cap):
        fail(
            "FAIL: Phase 13 displayed evidence exceeds the journal-specific main-text display cap",
            [f"tables={len(expected_table_sources)}", f"figures={len(expected_figure_sources)}", f"cap={display_cap}"],
        )
    table_cap = blueprint_display_architecture.get("main_text_table_cap")
    if table_cap not in (None, "") and len(expected_table_sources) > int(table_cap):
        fail("FAIL: Phase 13 displayed tables exceed the journal-specific table cap")
    figure_cap = blueprint_display_architecture.get("main_text_figure_cap")
    if figure_cap not in (None, "") and len(expected_figure_sources) > int(figure_cap):
        fail("FAIL: Phase 13 displayed figures exceed the journal-specific figure cap")
    descriptive_requirement = str(blueprint_display_architecture.get("descriptive_table_requirement", "")).strip()
    if descriptive_requirement in DESCRIPTIVE_TABLE_REQUIREMENTS:
        descriptive_display_sources = [
            source_path
            for source_path, item in coverage_by_source.items()
            if (
                str(item.get("artifact_role", "")).strip() in {"descriptive_table", "reader_facing_descriptive_table"}
                or "descript" in json_blob(item)
                or "summary statistic" in json_blob(item)
                or "sample characteristic" in json_blob(item)
            )
            and item.get("used_in_manuscript") is True
            and str(item.get("display_status", "")).strip() != "journal_exempt"
        ]
        if not descriptive_display_sources:
            fail("FAIL: Phase 13 journal profile requires a reader-facing descriptive table for quantitative manuscripts")
        if "Table 1" not in results_text:
            fail("FAIL: Phase 13 journal profile requires the descriptive Table 1 to be called out in Results flow")
    if expected_table_sources and not has_markdown_or_html_table(results_text):
        fail("FAIL: Phase 13 Results section must include a visible rendered table block")
    if expected_figure_sources and not has_visible_figure_block(results_text):
        fail("FAIL: Phase 13 Results section must include a visible figure block")
    external_gate_failures = []
    for gate_name, label in [
        ("front-matter-check.sh", "Phase 13 front matter"),
        ("abstract-boilerplate-check.sh", "Phase 13 abstract boilerplate"),
        ("journal-section-architecture-check.sh", "Phase 13 journal section architecture"),
        ("introduction-argument-architecture-check.sh", "Phase 13 introduction argument architecture"),
        ("theory-hypothesis-continuity-check.sh", "Phase 13 theory/hypothesis continuity"),
        ("theory-structure-depth-check.sh", "Phase 13 theory structure depth"),
        ("methods-role-subsections-check.sh", "Phase 13 methods role subsections"),
        ("data-sample-flow-check.sh", "Phase 13 data/sample flow"),
        ("analytic-strategy-quality-check.sh", "Phase 13 analytic strategy quality"),
        ("analytic-formula-specificity-check.sh", "Phase 13 method-specific analytic detail"),
        ("discussion-adjudication-check.sh", "Phase 13 discussion adjudication"),
        ("conclusion-contribution-support-check.sh", "Phase 13 conclusion contribution support"),
        ("cross-section-continuity-check.sh", "Phase 13 cross-section continuity"),
        ("manuscript-artifact-leakage-check.sh", "Phase 13 manuscript artifact leakage"),
        ("citation-cluster-quality-check.sh", "Phase 13 citation cluster quality"),
        ("figure-style-source-check.sh", "Phase 13 figure style source"),
        ("descriptives-coverage-check.sh", "Phase 13 descriptive variable coverage"),
        ("descriptive-table-display-check.sh", "Phase 13 descriptive table display"),
        ("concept-to-measure-check.sh", "Phase 13 concept-to-measure bridge"),
        ("regression-table-family-shape-check.sh", "Phase 13 regression table family shape"),
        ("regression-table-export-check.sh", "Phase 13 regression-engine purity"),
        ("regression-table-display-check.sh", "Phase 13 full regression table reader-facing"),
    ]:
        gate_result = run_external_gate(gate_name, proj, label)
        if gate_result is None:
            continue
        status, reason, detail = gate_result
        if status == "RED":
            external_gate_failures.append(f"{label}: reason={reason} detail={detail}")
    if external_gate_failures:
        fail("FAIL: Phase 13 external manuscript gates failed", external_gate_failures)
    claims = draft_manifest.get("locked_result_claims")
    if not isinstance(claims, list):
        fail("FAIL: Phase 13 locked_result_claims must be a list")
    claims_by_source = {
        str(item.get("source_path", "")).strip(): item
        for item in claims
        if isinstance(item, dict)
    }
    expected_claim_sources = []
    for source_path, lock_item in locked_by_source.items():
        role = str(lock_item.get("artifact_role", "")).strip()
        locked_path = str(lock_item.get("locked_path", "")).strip()
        if role in TABLE_ARTIFACT_ROLES and locked_path.endswith(".csv"):
            locked_file = proj / locked_path
            try:
                rows = read_csv_dicts(locked_file)
            except Exception:
                rows = []
            if rows and any("spec_id" in row for row in rows):
                expected_claim_sources.append((source_path, locked_path, rows))
    if set(claims_by_source) != {source for source, _, _ in expected_claim_sources}:
        missing = sorted({source for source, _, _ in expected_claim_sources} - set(claims_by_source))
        extra = sorted(set(claims_by_source) - {source for source, _, _ in expected_claim_sources})
        fail("FAIL: Phase 13 locked_result_claims must cover every reader-facing CSV result source", missing + extra)
    claim_issues = []
    for source_path, locked_path, rows in expected_claim_sources:
        claim = claims_by_source[source_path]
        if claim.get("locked_path") != locked_path:
            claim_issues.append(f"{source_path}: locked_path mismatch")
        if int(claim.get("row_count", -1)) != len(rows):
            claim_issues.append(f"{source_path}: row_count mismatch")
        row_claims = claim.get("rows")
        if not isinstance(row_claims, list) or len(row_claims) != len(rows):
            claim_issues.append(f"{source_path}: rows must match locked CSV rows")
            continue
        by_spec_index = {
            (str(item.get("spec_id", "")).strip(), int(item.get("row_index", -1))): item
            for item in row_claims
            if isinstance(item, dict)
        }
        for row_index, row in enumerate(rows):
            spec_id = str(row.get("spec_id", "")).strip()
            if not spec_id or (spec_id, row_index) not in by_spec_index:
                claim_issues.append(f"{source_path}: missing claim for spec {spec_id or '<blank>'}")
                continue
            row_claim = by_spec_index[(spec_id, row_index)]
            expected_claim_id = f"{source_path}#{row_index}:{spec_id}"
            if int(row_claim.get("row_index", -1)) != row_index:
                claim_issues.append(f"{source_path}:{spec_id}: row_index mismatch")
            if row_claim.get("claim_id") != expected_claim_id:
                claim_issues.append(f"{source_path}:{spec_id}: claim_id mismatch")
            for field in ("estimate", "std_error", "p_value", "n"):
                if field in row and str(row.get(field, "")).strip():
                    expected = str(row.get(field, "")).strip()
                    if str(row_claim.get(field, "")).strip() != expected:
                        claim_issues.append(f"{source_path}:{spec_id}: {field} claim mismatch")
                    if expected not in manuscript_text:
                        claim_issues.append(f"{source_path}:{spec_id}: {field} value absent from manuscript")
            anchor = str(row_claim.get("manuscript_anchor", "")).strip()
            if not anchor or anchor not in manuscript_text:
                claim_issues.append(f"{source_path}:{spec_id}: row manuscript_anchor missing")
    if claim_issues:
        fail("FAIL: Phase 13 locked result claims do not match locked CSV values", claim_issues)

if phase_id == "14":
    report_path = proj / "verify" / "manuscript-verification.json"
    manuscript_path = proj / "manuscript" / "manuscript-draft.md"
    blueprint_path = proj / "manuscript" / "manuscript-blueprint.json"
    verification_md_path = proj / "verify" / "manuscript-verification.md"
    lock_manifest_path = proj / "results-locked" / "manifest.json"
    latest_path = proj / "results-locked" / "LATEST.txt"
    draft_manifest_path = proj / "manuscript" / "draft-manifest.json"
    try:
        report = json.loads(report_path.read_text())
        blueprint = json.loads(blueprint_path.read_text())
        lock_manifest = json.loads(lock_manifest_path.read_text())
        draft_manifest = json.loads(draft_manifest_path.read_text())
    except Exception as exc:
        fail(f"FAIL: Phase 14 verification report is not valid JSON: {exc}")
    manuscript_text = manuscript_path.read_text(errors="ignore")
    lower_manuscript = manuscript_text.lower()
    sections = markdown_sections(manuscript_text)
    required = (
        "verdict",
        "degraded",
        "verification_engine",
        "lock_id",
        "source_hashes",
        "blueprint_hashes",
        "scanned",
        "critical_count",
        "selected_manuscript_hash",
        "agent_reports",
        "agents",
        "input_artifacts_read",
        "stage_1_outputs_to_manuscript",
        "stage_2_manuscript_to_prose",
        "lock_coverage",
        "findings",
        "fix_checklist",
        "route_back_phase",
        "ready_for_phase_15",
    )
    absent = [field for field in required if field not in report]
    if absent:
        fail("FAIL: Phase 14 verification report missing required fields", absent)
    findings = report.get("findings")
    if not isinstance(findings, list):
        fail("FAIL: Phase 14 findings must be a list")
    if report.get("verdict") != "PASS":
        if report.get("verdict") != "FAIL":
            fail(f"FAIL: Phase 14 top-level verdict must be PASS or FAIL, got {report.get('verdict')}")
        allowed_categories = {
            "blueprint_drift": "12",
            "draft_prose": "13",
            "manuscript_trace": "13",
            "citation_placeholder": "13",
            "unsupported_manuscript_display": "13",
            "locked_artifact_mismatch": "11",
            "lock_stale": "11",
            "analysis_output_error": "8",
            "post_execution_interpretation": "9",
            "design_issue": "3",
            "measurement_issue": "4",
            "analysis_plan_issue": "5",
            "verification_process": "14",
        }
        allowed_roles = {"verify-numerics", "verify-figures", "verify-logic", "verify-completeness"}
        if not findings:
            fail("FAIL: Phase 14 FAIL report must include nonempty findings")
        finding_issues = []
        route_phases = set()
        critical_or_major = 0
        seen_findings = set()
        for idx, finding in enumerate(findings):
            if not isinstance(finding, dict):
                finding_issues.append(f"findings[{idx}] is not an object")
                continue
            finding_id = str(finding.get("finding_id", "")).strip()
            if not finding_id or finding_id in seen_findings:
                finding_issues.append(f"findings[{idx}].finding_id missing or duplicate")
            seen_findings.add(finding_id)
            severity = str(finding.get("severity", "")).strip()
            if severity not in {"CRITICAL", "MAJOR", "WARNING"}:
                finding_issues.append(f"{finding_id}: severity invalid")
            if severity in {"CRITICAL", "MAJOR"}:
                critical_or_major += 1
            category = str(finding.get("category", "")).strip()
            expected_phase = allowed_categories.get(category)
            if expected_phase is None:
                finding_issues.append(f"{finding_id}: category invalid")
            owner_phase = str(finding.get("owner_phase", "")).strip()
            route_back_phase = str(finding.get("route_back_phase", "")).strip()
            if expected_phase and owner_phase != expected_phase:
                finding_issues.append(f"{finding_id}: owner_phase must be {expected_phase} for {category}")
            if expected_phase and route_back_phase != expected_phase:
                finding_issues.append(f"{finding_id}: route_back_phase must be {expected_phase} for {category}")
            if route_back_phase:
                route_phases.add(route_back_phase)
            if finding.get("detected_by") not in allowed_roles:
                finding_issues.append(f"{finding_id}: detected_by must be one of the Phase 14 verifier roles")
            affected = finding.get("affected_artifacts")
            if not isinstance(affected, list) or not affected or any(not str(item).strip() for item in affected):
                finding_issues.append(f"{finding_id}: affected_artifacts must be a nonempty list")
            if not str(finding.get("required_fix", "")).strip():
                finding_issues.append(f"{finding_id}: required_fix missing")
            if finding.get("status") != "open":
                finding_issues.append(f"{finding_id}: status must be open")
        fix_checklist = report.get("fix_checklist")
        if not isinstance(fix_checklist, dict):
            finding_issues.append("fix_checklist must be an object")
        else:
            if critical_or_major and not fix_checklist.get("critical_fixes"):
                finding_issues.append("fix_checklist.critical_fixes must be nonempty for CRITICAL/MAJOR findings")
            route_back = fix_checklist.get("route_back")
            if not isinstance(route_back, list) or not route_back:
                finding_issues.append("fix_checklist.route_back must be nonempty for FAIL")
        top_route = str(report.get("route_back_phase", "")).strip()
        if not top_route:
            finding_issues.append("route_back_phase must be set for FAIL")
        elif route_phases and top_route != str(min(int(phase) for phase in route_phases)):
            finding_issues.append("route_back_phase must be the earliest finding route_back_phase")
        if report.get("ready_for_phase_15") is not False:
            finding_issues.append("ready_for_phase_15 must be false for FAIL")
        if int(report.get("critical_count", 0)) <= 0 and critical_or_major:
            finding_issues.append("critical_count must be positive when CRITICAL/MAJOR findings exist")
        if finding_issues:
            fail("FAIL: Phase 14 FAIL report is malformed", finding_issues)
        fail("FAIL: Phase 14 verification found unresolved issues; route back before Phase 15", [f"route_back_phase={top_route}"] + [f"{f.get('finding_id')}: {f.get('required_fix')}" for f in findings if isinstance(f, dict)])
    if report.get("degraded") is not False:
        fail("FAIL: Phase 14 degraded must be false")
    if findings:
        fail("FAIL: Phase 14 PASS report must have empty findings")
    engine = report.get("verification_engine")
    if not isinstance(engine, dict):
        fail("FAIL: Phase 14 verification_engine must be an object")
    expected_engine = {
        "skill": "scholar-verify",
        "mode": "full",
        "stage_1": True,
        "stage_2": True,
        "lock_enforced": True,
        "live_output_reads_forbidden": True,
        "agent_count": 4,
    }
    engine_mismatches = [
        f"{key}: expected {expected!r}, got {engine.get(key)!r}"
        for key, expected in expected_engine.items()
        if engine.get(key) != expected
    ]
    if engine_mismatches:
        fail("FAIL: Phase 14 must use scholar-verify full mode under the active lock", engine_mismatches)
    verification_engine_issues = validate_engine_provenance(engine, "Phase 14 verification_engine")
    if verification_engine_issues:
        fail("FAIL: Phase 14 verification_engine provenance is incomplete", verification_engine_issues)
    lock_id = str(lock_manifest.get("lock_id", "")).strip()
    if latest_path.read_text(errors="ignore") != f"{lock_id}\n":
        fail("FAIL: Phase 14 LATEST.txt must still point to the verified lock")
    if report.get("lock_id") != lock_id:
        fail("FAIL: Phase 14 report lock_id must match active results lock")
    if report.get("lock_manifest_sha256") != lock_manifest.get("manifest_sha256"):
        fail("FAIL: Phase 14 report lock_manifest_sha256 must match active lock manifest")
    if int(report.get("scanned", 0)) <= 0:
        fail("FAIL: Phase 14 scanned must be positive")
    if int(report.get("critical_count", 0)) != 0:
        fail("FAIL: Phase 14 critical_count must be 0")
    actual_hash = sha256(manuscript_path)
    if report.get("selected_manuscript_hash") != actual_hash:
        fail("FAIL: Phase 14 selected_manuscript_hash does not match manuscript/manuscript-draft.md")
    source_hashes = report.get("source_hashes")
    if not isinstance(source_hashes, dict):
        fail("FAIL: Phase 14 source_hashes must be an object")
    expected_hashes = {
        "manuscript": sha256(manuscript_path),
        "draft_manifest": sha256(draft_manifest_path),
        "lock_manifest": sha256(lock_manifest_path),
    }
    stale_sources = [
        f"{key} mismatch"
        for key, expected in expected_hashes.items()
        if source_hashes.get(key) != expected
    ]
    if stale_sources:
        fail("FAIL: Phase 14 source_hashes are stale", stale_sources)
    blueprint_hashes = report.get("blueprint_hashes")
    if not isinstance(blueprint_hashes, dict):
        fail("FAIL: Phase 14 blueprint_hashes must be an object")
    if blueprint_hashes.get("manuscript_blueprint") != sha256(blueprint_path):
        fail("FAIL: Phase 14 blueprint_hashes.manuscript_blueprint must match manuscript/manuscript-blueprint.json")
    if blueprint.get("verdict") != "PASS" or blueprint.get("ready_for_phase_13") is not True:
        fail("FAIL: Phase 14 requires a passing Phase 12 manuscript blueprint")
    agents = report.get("agents")
    if not isinstance(agents, list):
        fail("FAIL: Phase 14 agents must be a list")
    required_roles = {"verify-numerics", "verify-figures", "verify-logic", "verify-completeness"}
    agent_roles = {str(agent.get("role", "")).strip() for agent in agents if isinstance(agent, dict)}
    if agent_roles != required_roles:
        fail("FAIL: Phase 14 must include all four scholar-verify agents", sorted(required_roles - agent_roles) + sorted(agent_roles - required_roles))
    agent_issues = []
    seen_agent_ids = set()
    seen_task_invocations = set()
    seen_report_paths = set()
    required_agent_scopes = {
        "verify-numerics": {"stage_1_numeric_values", "stage_2_numeric_claims"},
        "verify-figures": {"stage_1_visual_inspection", "caption_claims"},
        "verify-logic": {"stage_2_claim_scope", "phase9_constraints"},
        "verify-completeness": {"coverage", "live_read_audit"},
    }
    for agent in agents:
        if not isinstance(agent, dict):
            agent_issues.append("agent entry is not an object")
            continue
        role = str(agent.get("role", "")).strip()
        agent_id = str(agent.get("agent_id", "")).strip()
        if not agent_id or agent_id in seen_agent_ids:
            agent_issues.append(f"{role}: missing or duplicate agent_id")
        seen_agent_ids.add(agent_id)
        task_invocation_id = str(agent.get("task_invocation_id", "")).strip()
        if not task_invocation_id or task_invocation_id in seen_task_invocations:
            agent_issues.append(f"{role}: missing or duplicate task_invocation_id")
        seen_task_invocations.add(task_invocation_id)
        declared_scope = {
            str(item).strip()
            for item in agent.get("verification_scope", [])
            if str(item).strip()
        } if isinstance(agent.get("verification_scope"), list) else set()
        required_scope = required_agent_scopes.get(role, set())
        if not required_scope.issubset(declared_scope):
            agent_issues.append(f"{role}: verification_scope missing {sorted(required_scope - declared_scope)}")
        if agent.get("independent") is not True:
            agent_issues.append(f"{role}: independent must be true")
        if agent.get("verdict") != "PASS":
            agent_issues.append(f"{role}: verdict must be PASS")
        if agent.get("agent_type") not in ("independent_scholar_verify_agent", "independent_codex_agent"):
            agent_issues.append(f"{role}: agent_type invalid")
        input_hashes = agent.get("input_hashes")
        if not isinstance(input_hashes, dict):
            agent_issues.append(f"{role}: input_hashes missing")
        else:
            for key, expected in expected_hashes.items():
                if input_hashes.get(key) != expected:
                    agent_issues.append(f"{role}: input_hashes.{key} mismatch")
        report_rel = str(agent.get("report_path", "")).strip()
        if report_rel in seen_report_paths:
            agent_issues.append(f"{role}: duplicate report_path")
        seen_report_paths.add(report_rel)
        if Path(report_rel).is_absolute() or not report_rel or not (proj / report_rel).exists():
            agent_issues.append(f"{role}: report_path invalid")
        else:
            report_text = (proj / report_rel).read_text(errors="ignore")
            if word_count(report_text) < 30:
                agent_issues.append(f"{role}: report_path is too short")
            if f"SCANNED: {role}" not in report_text:
                agent_issues.append(f"{role}: report missing role-specific SCANNED token")
    if agent_issues:
        fail("FAIL: Phase 14 agent reports are invalid", agent_issues)
    agent_reports = report.get("agent_reports")
    if not isinstance(agent_reports, list) or set(agent_reports) != {str(agent.get("report_path", "")).strip() for agent in agents if isinstance(agent, dict)}:
        fail("FAIL: Phase 14 agent_reports must exactly match agent report paths")
    input_reads = report.get("input_artifacts_read")
    if not isinstance(input_reads, list):
        fail("FAIL: Phase 14 input_artifacts_read must be a list")
    input_read_sources = set()
    bad_input_reads = []
    for item in input_reads:
        if not isinstance(item, dict):
            bad_input_reads.append("input_artifacts_read entry is not an object")
            continue
        rel = str(item.get("path", "")).strip()
        source = str(item.get("source_artifact", "")).strip()
        if Path(rel).is_absolute() or not rel.startswith(f"results-locked/{lock_id}/") or not (proj / rel).exists():
            bad_input_reads.append(f"{rel}: must be an existing active-lock path")
            continue
        if rel.startswith(("tables/", "figures/")):
            bad_input_reads.append(f"{rel}: live output read detected")
        if item.get("sha256") != sha256(proj / rel):
            bad_input_reads.append(f"{rel}: sha256 mismatch")
        if source:
            input_read_sources.add(source)
    if bad_input_reads:
        fail("FAIL: Phase 14 input_artifacts_read contains invalid or live-read paths", bad_input_reads)
    lock_coverage = report.get("lock_coverage")
    if not isinstance(lock_coverage, dict):
        fail("FAIL: Phase 14 lock_coverage must be an object")
    if lock_coverage.get("all_locked_artifacts_accounted") is not True or lock_coverage.get("live_output_reads_detected") not in (False, 0):
        fail("FAIL: Phase 14 lock_coverage must account for all locked artifacts and forbid live reads")
    if lock_coverage.get("lock_id") != lock_id:
        fail("FAIL: Phase 14 lock_coverage lock_id must match active lock")
    reader_facing_roles = TABLE_ARTIFACT_ROLES | {"figure_file"}
    coverage = draft_manifest.get("locked_result_coverage")
    if not isinstance(coverage, list):
        fail("FAIL: Phase 14 requires Phase 13 locked_result_coverage")
    registry_display_issues = displayed_registry_sources_from_coverage(coverage) + registry_like_table_display_hits(manuscript_text)
    if registry_display_issues:
        fail("FAIL: Phase 14 manuscript verification cannot proceed with registry/model-ladder reader-facing tables", registry_display_issues[:25])
    model_label_issues = reader_internal_spec_index_hits(manuscript_text)
    if model_label_issues:
        fail("FAIL: Phase 14 manuscript verification cannot proceed with internal S1/S2-style model labels in reader-facing text", model_label_issues[:25])
    if quantitative_empirical_regression_table_required(manuscript_text, draft_manifest, blueprint, lock_manifest) and not has_canonical_regression_display(coverage):
        fail("FAIL: Phase 14 quantitative manuscript lacks a verified canonical regression table display")
    expected_reader_sources = {
        str(item.get("source_path", "")).strip()
        for item in coverage
        if isinstance(item, dict)
        and item.get("used_in_manuscript") is True
        and str(item.get("artifact_role", "")).strip() in reader_facing_roles
    }
    all_coverage_sources = {str(item.get("source_path", "")).strip() for item in coverage if isinstance(item, dict)}
    if set(lock_coverage.get("covered_sources", [])) != all_coverage_sources:
        fail("FAIL: Phase 14 lock_coverage covered_sources must match Phase 13 locked_result_coverage")
    locked_by_source = {
        str(item.get("source_path", "")).strip(): item
        for item in lock_manifest.get("locked_artifacts", [])
        if isinstance(item, dict)
    }
    expected_read_sources = {
        source
        for source in expected_reader_sources
        if source in locked_by_source
    }
    if input_read_sources != expected_read_sources:
        missing = sorted(expected_read_sources - input_read_sources)
        extra = sorted(input_read_sources - expected_read_sources)
        fail("FAIL: Phase 14 input_artifacts_read must cover every reader-facing locked artifact", missing + extra)
    draft_claims = draft_manifest.get("locked_result_claims")
    if not isinstance(draft_claims, list):
        fail("FAIL: Phase 14 requires Phase 13 locked_result_claims")
    expected_claim_keys = set()
    for source_claim in draft_claims:
        if not isinstance(source_claim, dict):
            continue
        source = str(source_claim.get("source_path", "")).strip()
        for row in source_claim.get("rows", []):
            if isinstance(row, dict):
                spec_id = str(row.get("spec_id", "")).strip()
                claim_id = str(row.get("claim_id", "")).strip()
                if source and spec_id and claim_id:
                    expected_claim_keys.add((source, spec_id, claim_id))
    stage_specs = (
        ("stage_1_outputs_to_manuscript", "items_scanned"),
        ("stage_2_manuscript_to_prose", "claims_scanned"),
    )
    for stage_name, scan_field in stage_specs:
        stage = report.get(stage_name)
        if not isinstance(stage, dict):
            fail(f"FAIL: Phase 14 {stage_name} must be an object")
        if stage.get("verdict") != "PASS":
            fail(f"FAIL: Phase 14 {stage_name}.verdict must be PASS, got {stage.get('verdict')}")
        if stage.get("degraded") is not False:
            fail(f"FAIL: Phase 14 {stage_name}.degraded must be false")
        if int(stage.get("critical_count", 0)) != 0:
            fail(f"FAIL: Phase 14 {stage_name}.critical_count must be 0")
        checked = stage.get("checked")
        if stage_name == "stage_2_manuscript_to_prose" and not expected_claim_keys:
            if int(stage.get(scan_field, -1)) != 0:
                fail(f"FAIL: Phase 14 {stage_name}.{scan_field} must be 0 when Phase 13 has no reader-facing CSV row claims")
            if checked != []:
                fail(f"FAIL: Phase 14 {stage_name}.checked must be empty when Phase 13 has no reader-facing CSV row claims")
            continue
        if int(stage.get(scan_field, 0)) <= 0:
            fail(f"FAIL: Phase 14 {stage_name}.{scan_field} must be positive")
        if not isinstance(checked, list) or not checked:
            fail(f"FAIL: Phase 14 {stage_name}.checked must be a non-empty list")
        if int(stage.get(scan_field, -1)) != len(checked):
            fail(f"FAIL: Phase 14 {stage_name}.{scan_field} must equal checked length")
        bad_checks = []
        for idx, check in enumerate(checked):
            if not isinstance(check, dict):
                bad_checks.append(f"{stage_name}.checked[{idx}] is not an object")
            elif check.get("verdict") != "PASS":
                bad_checks.append(f"{stage_name}.checked[{idx}].verdict={check.get('verdict')}")
        if bad_checks:
            fail(f"FAIL: Phase 14 {stage_name} contains non-passing checks", bad_checks)
    stage1 = report.get("stage_1_outputs_to_manuscript")
    stage1_sources = {str(item.get("source_artifact", "")).strip() for item in stage1.get("checked", []) if isinstance(item, dict)}
    if stage1_sources != expected_reader_sources:
        missing = sorted(expected_reader_sources - stage1_sources)
        extra = sorted(stage1_sources - expected_reader_sources)
        fail("FAIL: Phase 14 Stage 1 checks must exactly cover reader-facing locked artifacts", missing + extra)
    stage1_issues = []
    coverage_by_source = {str(item.get("source_path", "")).strip(): item for item in coverage if isinstance(item, dict)}
    def reader_facing_artifact_terms(artifact_path):
        artifact_text = str(artifact_path).strip()
        terms = []
        coverage_item = coverage_by_source.get(artifact_text)
        if not coverage_item:
            for candidate in coverage_by_source.values():
                if artifact_text and artifact_text == str(candidate.get("locked_path", "")).strip():
                    coverage_item = candidate
                    break
        if isinstance(coverage_item, dict):
            for field in ("display_label", "caption_text", "results_callout"):
                value = str(coverage_item.get(field, "")).strip()
                if value:
                    terms.append(value)
            label = str(coverage_item.get("display_label", "")).strip()
            if label:
                terms.append(label)
        elif artifact_text:
            terms.extend([artifact_text, Path(artifact_text).name])
        seen = set()
        unique_terms = []
        for term in terms:
            key = term.lower()
            if key and key not in seen:
                unique_terms.append(term)
                seen.add(key)
        return unique_terms
    def section_mentions_reader_artifact(section_text, artifact_path):
        section_lower = str(section_text).lower()
        return any(str(term).strip().lower() in section_lower for term in reader_facing_artifact_terms(artifact_path))
    for item in stage1.get("checked", []):
        source = str(item.get("source_artifact", "")).strip()
        expected = coverage_by_source.get(source, {})
        if item.get("locked_path") != expected.get("locked_path"):
            stage1_issues.append(f"{source}: locked_path mismatch")
        if item.get("manuscript_anchor") != expected.get("manuscript_anchor"):
            stage1_issues.append(f"{source}: manuscript_anchor mismatch")
        if expected.get("artifact_role") == "figure_file":
            visual = item.get("visual_inspection")
            if not isinstance(visual, dict) or visual.get("rendered") is not True or visual.get("caption_matches") is not True:
                stage1_issues.append(f"{source}: figure visual inspection must render and match caption")
            if visual and (not visual.get("read_confirmed") or visual.get("figure_sha256") != sha256(proj / item.get("locked_path")) or not visual.get("rendered_dimensions") or not visual.get("caption_claims_checked")):
                stage1_issues.append(f"{source}: figure visual inspection lacks read proof, hash, dimensions, or caption claims")
    if stage1_issues:
        fail("FAIL: Phase 14 Stage 1 locked artifact checks are incomplete", stage1_issues)
    stage2 = report.get("stage_2_manuscript_to_prose")
    stage2_keys = {
        (str(item.get("source_artifact", "")).strip(), str(item.get("spec_id", "")).strip(), str(item.get("claim_id", "")).strip())
        for item in stage2.get("checked", [])
        if isinstance(item, dict) and item.get("spec_id") and item.get("claim_id")
    }
    if stage2_keys != expected_claim_keys:
        missing = sorted(f"{source}:{spec}:{claim}" for source, spec, claim in expected_claim_keys - stage2_keys)
        extra = sorted(f"{source}:{spec}:{claim}" for source, spec, claim in stage2_keys - expected_claim_keys)
        fail("FAIL: Phase 14 Stage 2 checks must exactly cover Phase 13 locked result claims", missing + extra)
    claim_lookup = {}
    for source_claim in draft_claims:
        if not isinstance(source_claim, dict):
            continue
        source = str(source_claim.get("source_path", "")).strip()
        for row in source_claim.get("rows", []):
            if isinstance(row, dict):
                claim_lookup[(source, str(row.get("spec_id", "")).strip(), str(row.get("claim_id", "")).strip())] = row
    stage2_issues = []
    seen_stage2_keys = set()
    for item in stage2.get("checked", []):
        key = (str(item.get("source_artifact", "")).strip(), str(item.get("spec_id", "")).strip(), str(item.get("claim_id", "")).strip())
        if key in seen_stage2_keys:
            stage2_issues.append(f"{key}: duplicate Stage 2 check")
        seen_stage2_keys.add(key)
        expected = claim_lookup.get(key, {})
        if item.get("locked_path") != next((claim.get("locked_path") for claim in draft_claims if isinstance(claim, dict) and claim.get("source_path") == key[0]), None):
            stage2_issues.append(f"{key}: locked_path mismatch")
        if item.get("manuscript_anchor") != expected.get("manuscript_anchor"):
            stage2_issues.append(f"{key}: manuscript_anchor mismatch")
        for field in ("estimate", "std_error", "p_value", "n"):
            if str(item.get(field, "")).strip() != str(expected.get(field, "")).strip():
                stage2_issues.append(f"{key}: {field} mismatch")
        for verdict_field in ("direction_verdict", "uncertainty_verdict", "causal_language_verdict", "phase9_constraint_verdict"):
            if item.get(verdict_field) != "PASS":
                stage2_issues.append(f"{key}: {verdict_field} must be PASS")
    if stage2_issues:
        fail("FAIL: Phase 14 Stage 2 locked claim checks are incomplete", stage2_issues)
    blueprint_to_manuscript = report.get("blueprint_to_manuscript")
    if not isinstance(blueprint_to_manuscript, dict):
        fail("FAIL: Phase 14 blueprint_to_manuscript must be an object")
    for field in ("headline_claim_aligned", "contribution_stack_aligned", "section_obligations_aligned", "headline_results_preserved", "forbidden_moves_absent"):
        if blueprint_to_manuscript.get(field) is not True:
            fail(f"FAIL: Phase 14 blueprint_to_manuscript.{field} must be true")
    blueprint_semantic_issues = []
    abstract_intro_discussion = " ".join(
        sections.get(name, "")
        for name in ("abstract", "introduction", "discussion", "conclusion")
        if sections.get(name, "")
    )
    if keyword_overlap_count(str(blueprint.get("paper_claim", "")), abstract_intro_discussion) < 2:
        blueprint_semantic_issues.append("paper_claim: overlap with abstract/introduction/discussion is too weak")
    for idx, contribution in enumerate(blueprint.get("contribution_stack", [])):
        claim_text = str(contribution.get("claim_text", "")).strip()
        if claim_text and keyword_overlap_count(claim_text, manuscript_text) < 2:
            blueprint_semantic_issues.append(f"contribution_stack[{idx}]: manuscript overlap too weak")
    headline_paths = [
        str(item.get("artifact_path", "")).strip()
        for item in blueprint.get("result_hierarchy", [])
        if isinstance(item, dict) and str(item.get("headline_status", "")).strip() == "headline"
    ]
    results_text = sections.get("results", "")
    for artifact_path in headline_paths:
        if not section_mentions_reader_artifact(results_text, artifact_path):
            blueprint_semantic_issues.append(f"headline artifact missing from Results section: {artifact_path}")
    phase14_structure = blueprint.get("journal_structure", {}) if isinstance(blueprint.get("journal_structure"), dict) else {}
    phase14_theory_mode = str(phase14_structure.get("theory_presentation", "")).strip()
    phase14_methods_heading = norm_text(phase14_structure.get("methods_section_label", "")) or "data and methods"
    if phase14_theory_mode == "background_section":
        phase14_theory_heading = "background"
    elif phase14_theory_mode == "theory_section":
        phase14_theory_heading = "theory"
    else:
        phase14_theory_heading = "literature review and theory"
    section_name_map = {
        "abstract": "abstract",
        "introduction": "introduction",
        "literature_review_and_theory": phase14_theory_heading if phase14_theory_mode != "embedded_in_introduction" else "introduction",
        "data_and_methods": phase14_methods_heading,
        "results": "results",
        "discussion": "discussion",
        "conclusion": "conclusion",
    }
    for section_key, section_name in section_name_map.items():
        obligations = blueprint.get("section_obligations", {}).get(section_key)
        if not isinstance(obligations, dict):
            continue
        section_text = sections.get(section_name, "")
        for artifact_path in obligations.get("required_artifacts", []):
            artifact_text = str(artifact_path).strip()
            if artifact_text and section_text and not section_mentions_reader_artifact(section_text, artifact_text):
                blueprint_semantic_issues.append(f"{section_key}: required artifact absent from section text: {artifact_text}")
        for disclosure in obligations.get("required_disclosures", []):
            disclosure_text = str(disclosure).strip().lower()
            if (
                disclosure_text
                and section_text
                and not disclosure_semantically_covered(disclosure_text, section_text.lower())
                and not disclosure_semantically_covered(disclosure_text, lower_manuscript)
            ):
                blueprint_semantic_issues.append(f"{section_key}: required disclosure not reflected in section text: {disclosure[:80]}")
    for disclosure in blueprint.get("required_disclosures", []):
        disclosure_text = str(disclosure).strip().lower()
        if disclosure_text and not disclosure_semantically_covered(disclosure_text, lower_manuscript):
            blueprint_semantic_issues.append(f"required disclosure missing from manuscript: {disclosure[:80]}")
    if blueprint_semantic_issues:
        fail("FAIL: Phase 14 blueprint/manuscript semantic alignment is insufficient", blueprint_semantic_issues[:25])
    if int(report.get("scanned", -1)) != int(stage1.get("items_scanned", -1)) + int(stage2.get("claims_scanned", -1)):
        fail("FAIL: Phase 14 scanned must equal Stage 1 items plus Stage 2 claims")
    for checklist_name in ("critical_fixes", "route_back"):
        if report.get("fix_checklist", {}).get(checklist_name) not in ([], None):
            fail(f"FAIL: Phase 14 fix_checklist.{checklist_name} must be empty for PASS")
    if report.get("route_back_phase") not in (None, ""):
        fail("FAIL: Phase 14 route_back_phase must be empty for PASS")
    if report.get("ready_for_phase_15") is not True:
        fail("FAIL: Phase 14 ready_for_phase_15 must be true")
    verification_md = verification_md_path.read_text(errors="ignore")
    if word_count(verification_md) < 80:
        fail("FAIL: Phase 14 manuscript-verification.md is too short")
    conflict_pattern = re.compile(r"(critical|unverified|mismatch|unresolved|live read|stale).{0,60}(remains|open|found|detected|unresolved)", re.IGNORECASE)
    if conflict_pattern.search(verification_md):
        fail("FAIL: Phase 14 markdown summary contradicts JSON PASS status")
    # Codex cross-model review gate (added 2026-05-10):
    # SCHOLAR_CODEX_DEFAULT defaults to true, so when the codex CLI is on PATH
    # the gate REQUIRES either codex full-mode artifacts under reviews/codex/
    # OR an [EXCUSED:codex-review: <reason>] annotation in
    # verify/manuscript-verification.{md,json}. Opt out at the shell level
    # with SCHOLAR_CODEX_DEFAULT=false.
    codex_external_gate_failures = []
    codex_gate_result = run_external_gate(
        "codex-trigger-phase14.sh", proj, "Phase 14 codex cross-model review"
    )
    if codex_gate_result is not None:
        codex_status, codex_reason, codex_detail = codex_gate_result
        if codex_status == "RED":
            codex_external_gate_failures.append(
                f"Phase 14 codex cross-model review: reason={codex_reason} detail={codex_detail}"
            )
    if codex_external_gate_failures:
        fail("FAIL: Phase 14 codex cross-model review gate", codex_external_gate_failures)

if phase_id == "15":
    manuscript_path = proj / "manuscript" / "manuscript-draft.md"
    draft_manifest_path = proj / "manuscript" / "draft-manifest.json"
    source_bib_path = proj / "literature" / "references.bib"
    phase13_path = proj / "verify" / "manuscript-verification.json"
    audit_path = proj / "citation" / "citation-audit.json"
    claim_map_path = proj / "citation" / "claim-source-map.json"
    exported_bib_path = proj / "citation" / "references.bib"
    for required_path in (manuscript_path, draft_manifest_path, source_bib_path, phase13_path):
        if not required_path.exists():
            fail(f"FAIL: Phase 15 missing required input {required_path.relative_to(proj)}")
    try:
        audit = json.loads(audit_path.read_text())
        claim_map = json.loads(claim_map_path.read_text())
        phase13 = json.loads(phase13_path.read_text())
        draft_manifest = json.loads(draft_manifest_path.read_text())
    except Exception as exc:
        fail(f"FAIL: Phase 15 citation artifacts are not valid JSON: {exc}")

    def bib_keys(path):
        text = path.read_text(errors="ignore")
        return set(match.strip() for match in re.findall(r"@\w+\s*\{\s*([^,\s]+)", text) if match.strip())

    manuscript_text = manuscript_path.read_text(errors="ignore")
    cited_keys = set(match.strip() for match in re.findall(r"@([A-Za-z0-9_:\-]+)", manuscript_text) if match.strip())
    source_keys = bib_keys(source_bib_path)
    exported_keys = bib_keys(exported_bib_path)
    if phase13.get("verdict") != "PASS" or phase13.get("ready_for_phase_15") is not True:
        fail("FAIL: Phase 15 requires a passing Phase 14 manuscript verification")
    if phase13.get("selected_manuscript_hash") != sha256(manuscript_path):
        fail("FAIL: Phase 15 manuscript hash does not match the draft verified by Phase 14")
    if not cited_keys:
        fail("FAIL: Phase 15 manuscript contains no citation keys")
    if not source_keys:
        fail("FAIL: Phase 15 source references.bib contains no BibTeX keys")

    required = (
        "verdict",
        "degraded",
        "citation_engine",
        "source_hashes",
        "selected_manuscript_hash",
        "citation_inventory",
        "bibliography_provenance",
        "verified_references",
        "unresolved_citation_count",
        "fabricated_reference_count",
        "unsupported_claims",
        "contradicted_claims",
        "locator_missing",
        "retraction_check",
        "claim_source_map",
        "claim_specificity",
        "findings",
        "fix_checklist",
        "route_back_phase",
        "ready_for_phase_16",
    )
    absent = [field for field in required if field not in audit]
    if absent:
        fail("FAIL: Phase 15 citation audit missing required fields", absent)
    findings = audit.get("findings")
    if not isinstance(findings, list):
        fail("FAIL: Phase 15 findings must be a list")
    if audit.get("verdict") != "PASS":
        if audit.get("verdict") != "FAIL":
            fail(f"FAIL: Phase 15 top-level verdict must be PASS or FAIL, got {audit.get('verdict')}")
        allowed_categories = {
            "unsupported_claim": "13",
            "contradicted_claim": "13",
            "locator_missing": "13",
            "draft_citation_problem": "13",
            "phase14_conflict": "14",
            "unverified_reference": "15",
            "missing_reference": "15",
            "fabricated_reference": "15",
            "retraction_flag": "15",
            "citation_pool_gap": "2",
            "citation_process": "15",
            "citation_specificity": "15",
            "claim_map_specificity": "15",
        }
        if not findings:
            fail("FAIL: Phase 15 FAIL report must include nonempty findings")
        finding_issues = []
        route_phases = set()
        critical_or_major = 0
        seen_findings = set()
        for idx, finding in enumerate(findings):
            if not isinstance(finding, dict):
                finding_issues.append(f"findings[{idx}] is not an object")
                continue
            finding_id = str(finding.get("finding_id", "")).strip()
            if not finding_id or finding_id in seen_findings:
                finding_issues.append(f"findings[{idx}].finding_id missing or duplicate")
            seen_findings.add(finding_id)
            severity = str(finding.get("severity", "")).strip()
            if severity not in {"CRITICAL", "MAJOR", "WARNING"}:
                finding_issues.append(f"{finding_id}: severity invalid")
            if severity in {"CRITICAL", "MAJOR"}:
                critical_or_major += 1
            category = str(finding.get("category", "")).strip()
            expected_phase = allowed_categories.get(category)
            if expected_phase is None:
                finding_issues.append(f"{finding_id}: category invalid")
            owner_phase = str(finding.get("owner_phase", "")).strip()
            route_back_phase = str(finding.get("route_back_phase", "")).strip()
            if expected_phase and owner_phase != expected_phase:
                finding_issues.append(f"{finding_id}: owner_phase must be {expected_phase} for {category}")
            if expected_phase and route_back_phase != expected_phase:
                finding_issues.append(f"{finding_id}: route_back_phase must be {expected_phase} for {category}")
            if route_back_phase:
                route_phases.add(route_back_phase)
            if finding.get("detected_by") not in {"scholar-citation", "citation-inventory", "claim-source-map", "retraction-check"}:
                finding_issues.append(f"{finding_id}: detected_by must be a Phase 15 citation checker")
            affected = finding.get("affected_artifacts")
            if not isinstance(affected, list) or not affected or any(not str(item).strip() for item in affected):
                finding_issues.append(f"{finding_id}: affected_artifacts must be a nonempty list")
            if not str(finding.get("required_fix", "")).strip():
                finding_issues.append(f"{finding_id}: required_fix missing")
            if finding.get("status") != "open":
                finding_issues.append(f"{finding_id}: status must be open")
        fix_checklist = audit.get("fix_checklist")
        if not isinstance(fix_checklist, dict):
            finding_issues.append("fix_checklist must be an object")
        else:
            if critical_or_major and not fix_checklist.get("critical_fixes"):
                finding_issues.append("fix_checklist.critical_fixes must be nonempty for CRITICAL/MAJOR findings")
            route_back = fix_checklist.get("route_back")
            if not isinstance(route_back, list) or not route_back:
                finding_issues.append("fix_checklist.route_back must be nonempty for FAIL")
        top_route = str(audit.get("route_back_phase", "")).strip()
        if not top_route:
            finding_issues.append("route_back_phase must be set for FAIL")
        elif route_phases and top_route != str(min(int(phase) for phase in route_phases)):
            finding_issues.append("route_back_phase must be the earliest finding route_back_phase")
        if audit.get("ready_for_phase_16") is not False:
            finding_issues.append("ready_for_phase_16 must be false for FAIL")
        if finding_issues:
            fail("FAIL: Phase 15 FAIL report is malformed", finding_issues)
        fail("FAIL: Phase 15 citation audit found unresolved issues; route back before Phase 16", [f"route_back_phase={top_route}"] + [f"{f.get('finding_id')}: {f.get('required_fix')}" for f in findings if isinstance(f, dict)])

    if audit.get("degraded") is not False:
        fail("FAIL: Phase 15 degraded must be false")
    if findings:
        fail("FAIL: Phase 15 PASS report must have empty findings")
    engine = audit.get("citation_engine")
    if not isinstance(engine, dict):
        fail("FAIL: Phase 15 citation_engine must be an object")
    expected_engine = {
        "skill": "scholar-citation",
        "mode": "verify",
        "source_verification": True,
        "claim_support": True,
        "retraction_check": True,
        "fabrication_guard": True,
    }
    engine_mismatches = [
        f"{key}: expected {expected!r}, got {engine.get(key)!r}"
        for key, expected in expected_engine.items()
        if engine.get(key) != expected
    ]
    if engine_mismatches:
        fail("FAIL: Phase 15 must use scholar-citation verify mode with all citation guards", engine_mismatches)
    citation_engine_issues = validate_engine_provenance(engine, "Phase 15 citation_engine")
    if citation_engine_issues:
        fail("FAIL: Phase 15 citation_engine provenance is incomplete", citation_engine_issues)
    if audit.get("selected_manuscript_hash") != sha256(manuscript_path):
        fail("FAIL: Phase 15 selected_manuscript_hash does not match manuscript/manuscript-draft.md")
    source_hashes = audit.get("source_hashes")
    if not isinstance(source_hashes, dict):
        fail("FAIL: Phase 15 source_hashes must be an object")
    expected_hashes = {
        "manuscript": sha256(manuscript_path),
        "draft_manifest": sha256(draft_manifest_path),
        "source_bib": sha256(source_bib_path),
        "phase13_verification": sha256(phase13_path),
        "claim_source_map": sha256(claim_map_path),
        "exported_references": sha256(exported_bib_path),
    }
    stale_sources = [
        f"{key} mismatch"
        for key, expected in expected_hashes.items()
        if source_hashes.get(key) != expected
    ]
    if stale_sources:
        fail("FAIL: Phase 15 source_hashes are stale", stale_sources)
    exported_bib_text = exported_bib_path.read_text(errors="ignore").strip()
    if not re.search(r"@\w+\s*\{", exported_bib_text):
        fail("FAIL: Phase 15 exported citation/references.bib must be valid BibTeX")
    provenance = audit.get("bibliography_provenance")
    if not isinstance(provenance, dict):
        fail("FAIL: Phase 15 bibliography_provenance must be an object")
    if provenance.get("source_bib_path") != "literature/references.bib":
        fail("FAIL: Phase 15 bibliography_provenance.source_bib_path must be literature/references.bib")
    if provenance.get("exported_bib_path") != "citation/references.bib":
        fail("FAIL: Phase 15 bibliography_provenance.exported_bib_path must be citation/references.bib")
    if provenance.get("project_native_primary") is not True:
        fail("FAIL: Phase 15 bibliography_provenance.project_native_primary must be true")
    if not isinstance(provenance.get("cross_project_imports_declared"), bool):
        fail("FAIL: Phase 15 bibliography_provenance.cross_project_imports_declared must be boolean")
    try:
        cross_project_import_count = int(provenance.get("cross_project_import_count", -1))
    except Exception:
        fail("FAIL: Phase 15 bibliography_provenance.cross_project_import_count must be numeric")
    if cross_project_import_count < 0:
        fail("FAIL: Phase 15 bibliography_provenance.cross_project_import_count must be nonnegative")
    import_notes = str(provenance.get("cross_project_import_notes", "")).strip()
    if cross_project_import_count == 0:
        if provenance.get("cross_project_imports_declared") is not False:
            fail("FAIL: Phase 15 bibliography_provenance.cross_project_imports_declared must be false when import count is zero")
        if import_notes:
            fail("FAIL: Phase 15 bibliography_provenance.cross_project_import_notes must be empty when import count is zero")
    else:
        if provenance.get("cross_project_imports_declared") is not True:
            fail("FAIL: Phase 15 bibliography_provenance.cross_project_imports_declared must be true when imports are declared")
        if not import_notes:
            fail("FAIL: Phase 15 bibliography_provenance.cross_project_import_notes must explain cross-project imports")
    if not cited_keys <= source_keys:
        fail("FAIL: Phase 15 manuscript cites keys missing from source references.bib", sorted(cited_keys - source_keys))
    if exported_keys != cited_keys:
        missing = sorted(cited_keys - exported_keys)
        extra = sorted(exported_keys - cited_keys)
        fail("FAIL: Phase 15 exported citation/references.bib must exactly match cited manuscript keys", missing + extra)
    inventory = audit.get("citation_inventory")
    if not isinstance(inventory, dict):
        fail("FAIL: Phase 15 citation_inventory must be an object")
    inventory_errors = []
    if set(str(item).strip() for item in inventory.get("unique_cited_keys", [])) != cited_keys:
        inventory_errors.append("unique_cited_keys mismatch")
    if int(inventory.get("unique_cited_count", -1)) != len(cited_keys):
        inventory_errors.append("unique_cited_count mismatch")
    if set(str(item).strip() for item in inventory.get("source_bib_keys", [])) != source_keys:
        inventory_errors.append("source_bib_keys mismatch")
    if int(inventory.get("source_bib_count", -1)) != len(source_keys):
        inventory_errors.append("source_bib_count mismatch")
    if set(str(item).strip() for item in inventory.get("exported_bib_keys", [])) != exported_keys:
        inventory_errors.append("exported_bib_keys mismatch")
    if int(inventory.get("exported_bib_count", -1)) != len(exported_keys):
        inventory_errors.append("exported_bib_count mismatch")
    if int(inventory.get("unresolved_citation_count", -1)) != 0:
        inventory_errors.append("unresolved_citation_count must be 0")
    if inventory_errors:
        fail("FAIL: Phase 15 citation inventory is inconsistent", inventory_errors)
    verified = audit.get("verified_references")
    if not isinstance(verified, list):
        fail("FAIL: Phase 15 verified_references must be a list")
    verified_keys = {str(item.get("key", "")).strip() for item in verified if isinstance(item, dict)}
    if verified_keys != cited_keys:
        missing = sorted(cited_keys - verified_keys)
        extra = sorted(verified_keys - cited_keys)
        fail("FAIL: Phase 15 verified_references must exactly cover cited keys", missing + extra)
    reference_issues = []
    for item in verified:
        if not isinstance(item, dict):
            reference_issues.append("verified_references entry is not an object")
            continue
        key = str(item.get("key", "")).strip()
        if item.get("verification_status") != "VERIFIED":
            reference_issues.append(f"{key}: verification_status must be VERIFIED")
        sources = item.get("verification_sources")
        if not isinstance(sources, list) or "project_bib" not in {str(source).strip() for source in sources}:
            reference_issues.append(f"{key}: verification_sources must include project_bib")
        else:
            source_set = {str(source).strip().lower() for source in sources}
            external_unavailable = item.get("external_verification_unavailable") is True
            unavailable_rationale = str(item.get("external_verification_unavailable_rationale", "")).strip()
            if source_set <= {"project_bib"} and not (external_unavailable and word_count(unavailable_rationale) >= 8):
                reference_issues.append(f"{key}: verification_sources need a non-project_bib source or documented external_verification_unavailable rationale")
        if item.get("metadata_match") is not True:
            reference_issues.append(f"{key}: metadata_match must be true")
        if item.get("fabricated") is not False:
            reference_issues.append(f"{key}: fabricated must be false")
        if str(item.get("retraction_status", "")).strip() != "not_retracted":
            reference_issues.append(f"{key}: retraction_status must be not_retracted")
    if reference_issues:
        fail("FAIL: Phase 15 verified reference records are invalid", reference_issues)
    for field in ("unresolved_citation_count", "fabricated_reference_count", "unsupported_claims", "contradicted_claims", "locator_missing"):
        if int(audit.get(field, -1)) != 0:
            fail(f"FAIL: Phase 15 {field} must be 0 for PASS")
    retraction = audit.get("retraction_check")
    if not isinstance(retraction, dict):
        fail("FAIL: Phase 15 retraction_check must be an object")
    if int(retraction.get("checked_count", -1)) != len(cited_keys):
        fail("FAIL: Phase 15 retraction_check.checked_count must equal cited key count")
    if int(retraction.get("retracted_count", -1)) != 0:
        fail("FAIL: Phase 15 retraction_check.retracted_count must be 0")
    records = retraction.get("records")
    if not isinstance(records, list):
        fail("FAIL: Phase 15 retraction_check.records must be a list")
    record_keys = {str(item.get("key", "")).strip() for item in records if isinstance(item, dict)}
    if record_keys != cited_keys:
        fail("FAIL: Phase 15 retraction_check.records must cover every cited key", sorted(cited_keys - record_keys) + sorted(record_keys - cited_keys))
    bad_retractions = [
        str(item.get("key", idx))
        for idx, item in enumerate(records)
        if not isinstance(item, dict) or item.get("status") != "not_retracted" or item.get("retracted") not in (False, 0)
    ]
    if bad_retractions:
        fail("FAIL: Phase 15 retraction records contain retracted or unchecked works", bad_retractions)
    map_summary = audit.get("claim_source_map")
    if not isinstance(map_summary, dict):
        fail("FAIL: Phase 15 claim_source_map summary must be an object")
    if map_summary.get("path") != "citation/claim-source-map.json":
        fail("FAIL: Phase 15 claim_source_map.path must be citation/claim-source-map.json")
    if claim_map.get("verdict") != "PASS" or claim_map.get("degraded") is not False:
        fail("FAIL: Phase 15 claim-source map must pass without degradation")
    if claim_map.get("selected_manuscript_hash") != sha256(manuscript_path):
        fail("FAIL: Phase 15 claim-source map manuscript hash is stale")
    claims = claim_map.get("claims")
    if not isinstance(claims, list) or not claims:
        fail("FAIL: Phase 15 claim-source map must include non-empty claims")
    claim_issues = []
    seen_claim_ids = set()
    claim_cited_keys = set()
    locator_required_types = {"causal", "novelty", "prevalence", "policy", "empirical", "background", "result_interpretation"}
    for idx, claim in enumerate(claims):
        if not isinstance(claim, dict):
            claim_issues.append(f"claims[{idx}] is not an object")
            continue
        claim_id = str(claim.get("claim_id", "")).strip()
        if not claim_id or claim_id in seen_claim_ids:
            claim_issues.append(f"claims[{idx}].claim_id missing or duplicate")
        seen_claim_ids.add(claim_id)
        for field in ("manuscript_location", "claim_type", "claim_text", "manuscript_anchor"):
            if not str(claim.get(field, "")).strip():
                claim_issues.append(f"{claim_id}: {field} missing")
        if not str(claim.get("evidence_span_summary", "")).strip():
            claim_issues.append(f"{claim_id}: evidence_span_summary missing")
        keys = {str(item).strip() for item in claim.get("citation_keys", []) if str(item).strip()} if isinstance(claim.get("citation_keys"), list) else set()
        if not keys:
            claim_issues.append(f"{claim_id}: citation_keys must be nonempty")
        elif not keys <= cited_keys:
            claim_issues.append(f"{claim_id}: citation_keys include uncited or unknown keys {sorted(keys - cited_keys)}")
        if len(keys) > 8 and claim.get("bulk_citation_exception") is not True:
            claim_issues.append(f"{claim_id}: more than 8 citation_keys requires bulk_citation_exception with rationale")
        if claim.get("bulk_citation_exception") is True and word_count(str(claim.get("bulk_citation_rationale", ""))) < 10:
            claim_issues.append(f"{claim_id}: bulk_citation_exception rationale too thin")
        if cited_keys and len(keys) >= max(9, math.ceil(len(cited_keys) * 0.6)):
            generic_blob = " ".join(str(claim.get(field, "")) for field in ("claim_id", "claim_type", "claim_text", "source_locator")).lower()
            if re.search(r"\b(all|background|literature|context|theory paragraph|citation cluster|source inventory|bibliography)\b", generic_blob):
                claim_issues.append(f"{claim_id}: omnibus citation cluster treats bibliography as undifferentiated claim support")
        anchor = str(claim.get("manuscript_anchor", "")).strip()
        if anchor and anchor not in manuscript_text:
            claim_issues.append(f"{claim_id}: manuscript_anchor not found in manuscript")
        if anchor and keys:
            missing_anchor_keys = sorted(key for key in keys if f"@{key}" not in anchor)
            if missing_anchor_keys:
                claim_issues.append(f"{claim_id}: manuscript_anchor missing cited keys {missing_anchor_keys}")
        claim_cited_keys.update(keys)
        claim_type = str(claim.get("claim_type", "")).strip()
        locator = str(claim.get("source_locator", "")).strip()
        if claim_type in locator_required_types and not locator:
            claim_issues.append(f"{claim_id}: source_locator missing")
        if locator and re.search(r"\b(citation cluster|background theory paragraph|generic literature|all sources|source inventory)\b", locator, flags=re.IGNORECASE):
            claim_issues.append(f"{claim_id}: source_locator is too generic")
        if claim.get("support_verdict") != "SUPPORTED":
            claim_issues.append(f"{claim_id}: support_verdict must be SUPPORTED")
        if claim.get("contradiction") not in (False, 0):
            claim_issues.append(f"{claim_id}: contradiction must be false")
    if claim_issues:
        fail("FAIL: Phase 15 claim-source map entries are invalid", claim_issues)
    if claim_cited_keys != cited_keys:
        missing = sorted(cited_keys - claim_cited_keys)
        extra = sorted(claim_cited_keys - cited_keys)
        fail("FAIL: Phase 15 claim-source map must cover every cited key at least once", missing + extra)
    claim_specificity = audit.get("claim_specificity") or claim_map.get("claim_specificity")
    if not isinstance(claim_specificity, dict):
        fail("FAIL: Phase 15 claim_specificity must be an object")
    if claim_specificity.get("status") != "PASS":
        fail("FAIL: Phase 15 claim_specificity must report PASS status")
    if int(claim_specificity.get("omnibus_claim_count", -1)) != 0:
        fail("FAIL: Phase 15 claim_specificity must report zero omnibus claims")
    if int(claim_specificity.get("max_citation_keys_per_claim", 99)) > 8 and claim_specificity.get("bulk_citation_exceptions_documented") is not True:
        fail("FAIL: Phase 15 claim_specificity must document any claim with more than 8 citation keys")
    locked_result_claims = draft_manifest.get("locked_result_claims")
    if not isinstance(locked_result_claims, list):
        fail("FAIL: Phase 15 requires Phase 13 locked_result_claims to be a list")
    mapped_claim_ids = {str(claim.get("claim_id", "")).strip() for claim in claims if isinstance(claim, dict)}
    empirical_row_claim_ids = []
    for source_claim in locked_result_claims:
        if not isinstance(source_claim, dict):
            continue
        for row in source_claim.get("rows", []):
            if isinstance(row, dict):
                claim_id = str(row.get("claim_id", "")).strip()
                if claim_id:
                    empirical_row_claim_ids.append(claim_id)
    missing_empirical_claims = sorted(claim_id for claim_id in empirical_row_claim_ids if claim_id not in mapped_claim_ids)
    if missing_empirical_claims:
        fail("FAIL: Phase 15 claim-source map must cover every Phase 13 empirical row claim", missing_empirical_claims[:50])
    manuscript_locations = {str(claim.get("manuscript_location", "")).strip().lower() for claim in claims if isinstance(claim, dict)}
    manuscript_sections_for_claims = markdown_sections(manuscript_text)
    required_claim_sections = {
        section_name
        for section_name in ("abstract", "results", "discussion")
        if re.findall(r"@([A-Za-z0-9_:\-]+)", manuscript_sections_for_claims.get(section_name, ""))
    }
    if not required_claim_sections.issubset(manuscript_locations):
        fail("FAIL: Phase 15 claim-source map must include abstract, results, and discussion coverage", sorted(required_claim_sections - manuscript_locations))
    expected_claim_counts = {
        "total_claims": len(claims),
        "supported_count": len(claims),
        "unsupported_count": 0,
        "contradicted_count": 0,
        "locator_missing_count": 0,
    }
    count_errors = [
        f"{key}: expected {expected}, got {claim_map.get(key)}"
        for key, expected in expected_claim_counts.items()
        if int(claim_map.get(key, -1)) != expected
    ]
    for key in ("total_claims", "supported_count", "unsupported_count", "contradicted_count", "locator_missing_count"):
        if int(map_summary.get(key, -1)) != expected_claim_counts[key]:
            count_errors.append(f"claim_source_map.{key}: expected {expected_claim_counts[key]}, got {map_summary.get(key)}")
    if count_errors:
        fail("FAIL: Phase 15 claim-source map counts are inconsistent", count_errors)
    placeholder_pattern = re.compile(r"\b(SOURCE NEEDED|UNVERIFIED|CLAIM-[A-Z-]+|citation needed)\b|\{\{[^}]+\}\}", re.IGNORECASE)
    if placeholder_pattern.search(manuscript_text):
        fail("FAIL: Phase 15 manuscript contains unresolved citation or claim-support placeholder text")
    for checklist_name in ("critical_fixes", "route_back"):
        if audit.get("fix_checklist", {}).get(checklist_name) not in ([], None):
            fail(f"FAIL: Phase 15 fix_checklist.{checklist_name} must be empty for PASS")
    if audit.get("route_back_phase") not in (None, ""):
        fail("FAIL: Phase 15 route_back_phase must be empty for PASS")
    if audit.get("ready_for_phase_16") is not True:
        fail("FAIL: Phase 15 ready_for_phase_16 must be true")

    # ── Gate cross-check (2026-05-25): close the trust-based loophole ──
    # The validations above check that citation/citation-audit.json declares
    # the right shape (engine=scholar-citation, fabrication_guard=true, all
    # counts=0 for PASS). Those declarations could in principle be fabricated
    # by an agent who skipped or partially ran scholar-citation. To close
    # that gap, independently run the three vendored citation gates and
    # require their actual outputs match the audit's declared PASS verdict.
    #
    # Bundled gates (vendored from scholar-skill/scripts/gates/):
    #   - verify-citation-metadata.sh             bib ↔ CrossRef DOI registry
    #   - verify-rendered-references-against-bib  rendered `## References` ↔ bib
    #   - verify-citation-local-library.sh        bib ↔ user's local Zotero
    #
    # Semantics: any RED contradicts the JSON's PASS verdict → fail.
    # YELLOW (network down, library unavailable) does NOT contradict — it
    # only means the gate could not run. Missing vendored gate → hard fail
    # via run_external_gate() (vendoring policy).
    #
    # Skip-flag: SCHOLAR_AUTO_RESEARCH_SKIP_GATE_RECHECK=1 (intended for
    # fixture tests that exercise the JSON-shape contract in isolation).
    if os.environ.get("SCHOLAR_AUTO_RESEARCH_SKIP_GATE_RECHECK") != "1":
        gate_contradictions = []
        gate_unavailable = []
        for gate_name, label in (
            ("verify-citation-metadata.sh",
             "verify-citation-metadata (bib ↔ CrossRef)"),
            ("verify-rendered-references-against-bib.sh",
             "verify-rendered-references-against-bib (manuscript ↔ bib)"),
            ("verify-citation-local-library.sh",
             "verify-citation-local-library (bib ↔ local Zotero)"),
        ):
            status, reason, detail = run_external_gate(gate_name, str(proj), label)
            if status == "RED":
                # missing_external_gate or external_gate_not_executable are
                # bundling defects — these MUST be treated as RED contradictions
                # (vendoring contract violated).
                gate_contradictions.append(
                    f"{label}: STATUS=RED reason={reason or '<unspecified>'}"
                    + (f" detail={detail}" if detail else "")
                )
            elif status == "YELLOW":
                # YELLOW = gate could not run (network, library missing).
                # Record but don't contradict the JSON verdict.
                gate_unavailable.append(f"{label}: YELLOW ({reason or 'unavailable'})")
            # status == "GREEN" → cross-check confirms the JSON's PASS verdict
        if gate_contradictions:
            fail(
                "FAIL: Phase 15 citation-audit JSON declares verdict=PASS but "
                "the vendored gate cross-check returned RED. The declared "
                "fabrication_guard/source_verification flags are inconsistent "
                "with the actual citation state — the audit cannot be trusted.",
                gate_contradictions
                + (["  (also: " + u + ")" for u in gate_unavailable]
                   if gate_unavailable else []),
            )

if phase_id == "16":
    safety_path = proj / "safety" / "safety-status.json"
    data_status_path = proj / "data" / "data-status.json"
    manuscript_path = proj / "manuscript" / "manuscript-draft.md"
    draft_manifest_path = proj / "manuscript" / "draft-manifest.json"
    citation_audit_path = proj / "citation" / "citation-audit.json"
    ethics_path = proj / "ethics" / "ethics-open-science.json"
    ethics_md_path = proj / "ethics" / "ethics-open-science.md"
    for required_path in (safety_path, data_status_path, manuscript_path, draft_manifest_path, citation_audit_path):
        if not required_path.exists():
            fail(f"FAIL: Phase 15 missing required input {required_path.relative_to(proj)}")
    try:
        safety = json.loads(safety_path.read_text())
        data_status = json.loads(data_status_path.read_text())
        citation_audit = json.loads(citation_audit_path.read_text())
        ethics = json.loads(ethics_path.read_text())
    except Exception as exc:
        fail(f"FAIL: Phase 15 ethics/open-science artifacts are not valid JSON: {exc}")
    if citation_audit.get("verdict") != "PASS" or citation_audit.get("ready_for_phase_16") is not True:
        fail("FAIL: Phase 16 requires a passing Phase 15 citation audit")
    if citation_audit.get("selected_manuscript_hash") != sha256(manuscript_path):
        fail("FAIL: Phase 16 manuscript hash does not match the draft audited by Phase 15")
    required = (
        "verdict",
        "degraded",
        "ethics_engine",
        "open_science_engine",
        "source_hashes",
        "selected_manuscript_hash",
        "critical_flags",
        "ai_disclosure",
        "privacy_review",
        "irb_status",
        "consent_status",
        "coi_status",
        "data_availability",
        "open_science",
        "authorship_credit",
        "integrity_review",
        "findings",
        "fix_checklist",
        "route_back_phase",
        "ready_for_phase_17",
    )
    absent = [field for field in required if field not in ethics]
    if absent:
        fail("FAIL: Phase 15 ethics/open-science report missing required fields", absent)
    findings = ethics.get("findings")
    if not isinstance(findings, list):
        fail("FAIL: Phase 15 findings must be a list")
    if ethics.get("verdict") != "PASS":
        if ethics.get("verdict") != "FAIL":
            fail(f"FAIL: Phase 15 top-level verdict must be PASS or FAIL, got {ethics.get('verdict')}")
        allowed_categories = {
            "ai_privacy": "0",
            "safety_status": "0",
            "data_status": "4",
            "irb_consent": "4",
            "data_availability_mismatch": "4",
            "manuscript_ethics_text": "13",
            "citation_ethics": "15",
            "ethics_disclosure": "16",
            "coi_disclosure": "16",
            "authorship_credit": "16",
            "open_science_plan": "16",
            "integrity_review": "16",
        }
        if not findings:
            fail("FAIL: Phase 15 FAIL report must include nonempty findings")
        finding_issues = []
        route_phases = set()
        critical_or_major = 0
        seen_findings = set()
        for idx, finding in enumerate(findings):
            if not isinstance(finding, dict):
                finding_issues.append(f"findings[{idx}] is not an object")
                continue
            finding_id = str(finding.get("finding_id", "")).strip()
            if not finding_id or finding_id in seen_findings:
                finding_issues.append(f"findings[{idx}].finding_id missing or duplicate")
            seen_findings.add(finding_id)
            severity = str(finding.get("severity", "")).strip()
            if severity not in {"CRITICAL", "MAJOR", "WARNING"}:
                finding_issues.append(f"{finding_id}: severity invalid")
            if severity in {"CRITICAL", "MAJOR"}:
                critical_or_major += 1
            category = str(finding.get("category", "")).strip()
            expected_phase = allowed_categories.get(category)
            if expected_phase is None:
                finding_issues.append(f"{finding_id}: category invalid")
            owner_phase = str(finding.get("owner_phase", "")).strip()
            route_back_phase = str(finding.get("route_back_phase", "")).strip()
            if expected_phase and owner_phase != expected_phase:
                finding_issues.append(f"{finding_id}: owner_phase must be {expected_phase} for {category}")
            if expected_phase and route_back_phase != expected_phase:
                finding_issues.append(f"{finding_id}: route_back_phase must be {expected_phase} for {category}")
            if route_back_phase:
                route_phases.add(route_back_phase)
            if finding.get("detected_by") not in {"scholar-ethics", "scholar-open", "ethics-open-science", "privacy-review", "data-availability"}:
                finding_issues.append(f"{finding_id}: detected_by must be a Phase 15 checker")
            affected = finding.get("affected_artifacts")
            if not isinstance(affected, list) or not affected or any(not str(item).strip() for item in affected):
                finding_issues.append(f"{finding_id}: affected_artifacts must be a nonempty list")
            if not str(finding.get("required_fix", "")).strip():
                finding_issues.append(f"{finding_id}: required_fix missing")
            if finding.get("status") != "open":
                finding_issues.append(f"{finding_id}: status must be open")
        fix_checklist = ethics.get("fix_checklist")
        if not isinstance(fix_checklist, dict):
            finding_issues.append("fix_checklist must be an object")
        else:
            if critical_or_major and not fix_checklist.get("critical_fixes"):
                finding_issues.append("fix_checklist.critical_fixes must be nonempty for CRITICAL/MAJOR findings")
            route_back = fix_checklist.get("route_back")
            if not isinstance(route_back, list) or not route_back:
                finding_issues.append("fix_checklist.route_back must be nonempty for FAIL")
        top_route = str(ethics.get("route_back_phase", "")).strip()
        if not top_route:
            finding_issues.append("route_back_phase must be set for FAIL")
        elif route_phases and top_route != str(min(int(phase) for phase in route_phases)):
            finding_issues.append("route_back_phase must be the earliest finding route_back_phase")
        if ethics.get("ready_for_phase_17") is not False:
            finding_issues.append("ready_for_phase_17 must be false for FAIL")
        if finding_issues:
            fail("FAIL: Phase 15 FAIL report is malformed", finding_issues)
        fail("FAIL: Phase 16 ethics/open-science audit found unresolved issues; route back before Phase 17", [f"route_back_phase={top_route}"] + [f"{f.get('finding_id')}: {f.get('required_fix')}" for f in findings if isinstance(f, dict)])

    if ethics.get("degraded") is not False:
        fail("FAIL: Phase 15 degraded must be false")
    if str(ethics.get("source_phase", "")).strip() != "16":
        fail("FAIL: Phase 16 source_phase must be 16")
    if findings:
        fail("FAIL: Phase 15 PASS report must have empty findings")
    critical_flags = ethics.get("critical_flags")
    if not isinstance(critical_flags, list) or critical_flags:
        fail("FAIL: Phase 15 critical_flags must be an empty list for PASS")
    ethics_engine = ethics.get("ethics_engine")
    open_engine = ethics.get("open_science_engine")
    if not isinstance(ethics_engine, dict) or ethics_engine.get("skill") != "scholar-ethics" or ethics_engine.get("mode") != "full":
        fail("FAIL: Phase 15 ethics_engine must be scholar-ethics full mode")
    if not isinstance(open_engine, dict) or open_engine.get("skill") != "scholar-open" or open_engine.get("mode") != "full-package":
        fail("FAIL: Phase 15 open_science_engine must be scholar-open full-package mode")
    ethics_engine_provenance = validate_engine_provenance(ethics_engine, "Phase 16 ethics_engine")
    if ethics_engine_provenance:
        fail("FAIL: Phase 16 ethics_engine provenance is incomplete", ethics_engine_provenance)
    open_engine_provenance = validate_engine_provenance(open_engine, "Phase 16 open_science_engine")
    if open_engine_provenance:
        fail("FAIL: Phase 16 open_science_engine provenance is incomplete", open_engine_provenance)
    ethics_engine_issues = [
        field
        for field in ("ai_privacy", "originality", "integrity", "general_ethics")
        if ethics_engine.get(field) is not True
    ]
    if ethics_engine_issues:
        fail("FAIL: Phase 15 ethics_engine missing required scholar-ethics capability flags", ethics_engine_issues)
    open_engine_issues = [
        field
        for field in ("data_management", "code_sharing", "credit_coi", "replication_planning")
        if open_engine.get(field) is not True
    ]
    if open_engine_issues:
        fail("FAIL: Phase 15 open_science_engine missing required scholar-open capability flags", open_engine_issues)
    if ethics.get("selected_manuscript_hash") != sha256(manuscript_path):
        fail("FAIL: Phase 15 selected_manuscript_hash does not match manuscript/manuscript-draft.md")
    source_hashes = ethics.get("source_hashes")
    if not isinstance(source_hashes, dict):
        fail("FAIL: Phase 15 source_hashes must be an object")
    expected_hashes = {
        "safety_status": sha256(safety_path),
        "data_status": sha256(data_status_path),
        "manuscript": sha256(manuscript_path),
        "draft_manifest": sha256(draft_manifest_path),
        "citation_audit": sha256(citation_audit_path),
    }
    stale_sources = [
        f"{key} mismatch"
        for key, expected in expected_hashes.items()
        if source_hashes.get(key) != expected
    ]
    if stale_sources:
        fail("FAIL: Phase 15 source_hashes are stale", stale_sources)
    placeholder_values = {"", "tbd", "todo", "unknown", "n/a", "na", "to be determined", "[protocol number]", "[repository url]", "[tool name]"}
    placeholder_pattern = re.compile(
        r"\[[^\]]+\]|\b(TBD|TODO|XXXX+|to be determined|Author\s+[0-9X])\b",
        re.IGNORECASE,
    )
    def collect_bad_placeholders(value, path="ethics"):
        bad = []
        if isinstance(value, dict):
            for key, subvalue in value.items():
                bad.extend(collect_bad_placeholders(subvalue, f"{path}.{key}"))
        elif isinstance(value, list):
            for idx, subvalue in enumerate(value):
                bad.extend(collect_bad_placeholders(subvalue, f"{path}[{idx}]"))
        elif isinstance(value, str) and placeholder_pattern.search(value):
            bad.append(path)
        return bad
    placeholder_hits = collect_bad_placeholders(ethics)
    if placeholder_hits:
        fail("FAIL: Phase 15 JSON contains placeholder text", placeholder_hits[:20])
    def required_text(obj, field, label, min_words=5):
        value = obj.get(field) if isinstance(obj, dict) else None
        if not isinstance(value, str) or value.strip().lower() in placeholder_values or placeholder_pattern.search(value) or word_count(value) < min_words:
            return f"{label}.{field} missing or placeholder"
        return None
    ai = ethics.get("ai_disclosure")
    if not isinstance(ai, dict):
        fail("FAIL: Phase 15 ai_disclosure must be an object")
    ai_issues = []
    tools = ai.get("tools")
    if not isinstance(tools, list) or not tools:
        ai_issues.append("ai_disclosure.tools must be nonempty")
    else:
        required_tool_fields = ("tool", "provider", "model_or_version", "stage_used", "task_performed", "data_type_shared", "sensitivity", "date_used", "cloud_or_local")
        for idx, tool in enumerate(tools):
            if not isinstance(tool, dict):
                ai_issues.append(f"ai_disclosure.tools[{idx}] is not an object")
                continue
            for field in required_tool_fields:
                value = str(tool.get(field, "")).strip()
                if not value or value.lower() in placeholder_values or placeholder_pattern.search(value):
                    ai_issues.append(f"ai_disclosure.tools[{idx}].{field} missing or placeholder")
            if str(tool.get("sensitivity", "")).strip() not in {"Low", "Medium"}:
                ai_issues.append(f"ai_disclosure.tools[{idx}].sensitivity must be Low or Medium for PASS")
            if str(tool.get("cloud_or_local", "")).strip() not in {"cloud", "local", "institutional"}:
                ai_issues.append(f"ai_disclosure.tools[{idx}].cloud_or_local invalid")
    ai_issues.extend(issue for issue in [required_text(ai, "statement", "ai_disclosure", 20)] if issue)
    statement_lower = str(ai.get("statement", "")).lower()
    if "ai" not in statement_lower and "codex" not in statement_lower and "claude" not in statement_lower:
        ai_issues.append("ai_disclosure.statement must mention AI tool use")
    if re.search(r"\b(did not|didn't|no)\s+(use\s+)?(generative\s+)?ai\s+(tools?|used)\b", statement_lower):
        ai_issues.append("auto-research Phase 15 cannot claim no AI tools were used")
    if ai.get("human_reviewed") is not True:
        ai_issues.append("ai_disclosure.human_reviewed must be true")
    if ai.get("sensitive_data_shared") not in (False, 0):
        ai_issues.append("ai_disclosure.sensitive_data_shared must be false for PASS")
    if ai_issues:
        fail("FAIL: Phase 15 AI disclosure is incomplete", ai_issues)
    privacy = ethics.get("privacy_review")
    if not isinstance(privacy, dict):
        fail("FAIL: Phase 15 privacy_review must be an object")
    privacy_issues = []
    if privacy.get("risk_level") not in ("Low", "Medium"):
        privacy_issues.append(f"risk_level={privacy.get('risk_level')}")
    if int(privacy.get("high_risk_unresolved", -1)) != 0:
        privacy_issues.append("high_risk_unresolved must be 0")
    if privacy.get("safety_status") != safety.get("safety_status"):
        privacy_issues.append("safety_status mismatch")
    for field in ("irb_consent_scope_checked", "dua_checked", "institutional_policy_checked"):
        if privacy.get(field) is not True:
            privacy_issues.append(f"{field} must be true")
    if privacy_issues:
        fail("FAIL: Phase 15 privacy review is incomplete or high risk", privacy_issues)
    irb = ethics.get("irb_status")
    if not isinstance(irb, dict):
        fail("FAIL: Phase 15 irb_status must be an object")
    data_irb = str(data_status.get("irb_status", "")).strip()
    allowed_irb = {"exempt", "approved", "not-human-subjects", "not-applicable"}
    irb_issues = []
    if irb.get("status") not in allowed_irb:
        irb_issues.append(f"status={irb.get('status')}")
    if data_irb == "pending" or irb.get("status") == "pending":
        irb_issues.append("pending IRB cannot pass Phase 15")
    if data_irb and data_irb not in {"pending"} and irb.get("status") != data_irb:
        irb_issues.append("status must match data/data-status.json irb_status")
    irb_issues.extend(issue for issue in [required_text(irb, "statement", "irb_status", 12), required_text(irb, "determination", "irb_status", 2)] if issue)
    if irb_issues:
        fail("FAIL: Phase 15 IRB status is incomplete", irb_issues)
    consent = ethics.get("consent_status")
    if not isinstance(consent, dict):
        fail("FAIL: Phase 15 consent_status must be an object")
    consent_issues = []
    if consent.get("status") not in ("obtained", "waived", "not-applicable"):
        consent_issues.append(f"status={consent.get('status')}")
    data_kind = str(data_status.get("data_status", "")).strip()
    access_status = str(data_status.get("access_status", "")).strip()
    source_type = str(data_status.get("source_type", "")).strip().lower()
    human_or_restricted = (
        data_kind == "collecting-new-data"
        or access_status == "restricted"
        or any(term in source_type for term in ("restricted", "confidential", "human", "participant", "survey", "interview", "health", "administrative"))
    )
    if human_or_restricted and irb.get("status") not in ("not-human-subjects", "not-applicable") and consent.get("status") == "not-applicable":
        consent_issues.append("human or restricted data require obtained or waived consent status")
    consent_issues.extend(issue for issue in [required_text(consent, "statement", "consent_status", 8)] if issue)
    if consent_issues:
        fail("FAIL: Phase 15 consent status is incomplete", consent_issues)
    coi = ethics.get("coi_status")
    if not isinstance(coi, dict):
        fail("FAIL: Phase 15 coi_status must be an object")
    coi_issues = []
    if coi.get("status") not in ("no_competing_interests", "disclosed"):
        coi_issues.append(f"status={coi.get('status')}")
    if coi.get("unresolved_conflicts") not in (False, 0):
        coi_issues.append("unresolved_conflicts must be false")
    coi_issues.extend(issue for issue in [required_text(coi, "statement", "coi_status", 5)] if issue)
    if coi_issues:
        fail("FAIL: Phase 15 COI status is incomplete", coi_issues)
    data_avail = ethics.get("data_availability")
    if not isinstance(data_avail, dict):
        fail("FAIL: Phase 15 data_availability must be an object")
    sharing_mode = str(data_avail.get("sharing_mode", "")).strip()
    allowed_modes = {"public-data-full", "restricted-data-code-only", "synthetic-demo", "no-data-conceptual"}
    data_issues = []
    if sharing_mode not in allowed_modes:
        data_issues.append(f"sharing_mode={sharing_mode}")
    if data_kind == "no-data" and sharing_mode != "no-data-conceptual":
        data_issues.append("no-data projects require no-data-conceptual sharing_mode")
    if data_kind in {"existing-data", "collecting-new-data"} and sharing_mode == "no-data-conceptual":
        data_issues.append("data projects cannot use no-data-conceptual sharing_mode")
    if access_status == "pending":
        data_issues.append("pending data access cannot pass Phase 15")
    if access_status == "restricted" and sharing_mode == "public-data-full":
        data_issues.append("restricted data cannot use public-data-full sharing_mode")
    if "restricted" in source_type and sharing_mode == "public-data-full":
        data_issues.append("restricted source_type cannot use public-data-full sharing_mode")
    if data_avail.get("matches_data_status") is not True:
        data_issues.append("matches_data_status must be true")
    data_issues.extend(issue for issue in [required_text(data_avail, "statement", "data_availability", 15), required_text(data_avail, "repository_or_access_plan", "data_availability", 3)] if issue)
    if sharing_mode == "restricted-data-code-only" and not str(data_avail.get("restriction_rationale", "")).strip():
        data_issues.append("restricted-data-code-only requires restriction_rationale")
    if data_issues:
        fail("FAIL: Phase 15 data availability is incomplete or mismatched", data_issues)
    open_science = ethics.get("open_science")
    if not isinstance(open_science, dict):
        fail("FAIL: Phase 15 open_science must be an object")
    open_issues = []
    for field in ("preregistration_status", "code_sharing_plan", "license_plan", "preprint_open_access_plan"):
        issue = required_text(open_science, field, "open_science", 3)
        if issue:
            open_issues.append(issue)
    if open_science.get("replication_ready") is not True:
        open_issues.append("replication_ready must be true")
    if open_science.get("phase16_handoff") != "replication-package":
        open_issues.append("phase16_handoff must be replication-package")
    if open_issues:
        fail("FAIL: Phase 15 open science plan is incomplete", open_issues)
    credit = ethics.get("authorship_credit")
    if not isinstance(credit, dict):
        fail("FAIL: Phase 15 authorship_credit must be an object")
    credit_issues = []
    if not isinstance(credit.get("credit_roles"), list) or not credit.get("credit_roles"):
        credit_issues.append("credit_roles must be nonempty")
    else:
        valid_credit_roles = {
            "Conceptualization",
            "Data curation",
            "Formal analysis",
            "Funding acquisition",
            "Investigation",
            "Methodology",
            "Project administration",
            "Resources",
            "Software",
            "Supervision",
            "Validation",
            "Visualization",
            "Writing - original draft",
            "Writing - review and editing",
        }
        roles = {str(role).strip() for role in credit.get("credit_roles", [])}
        invalid_roles = sorted(role for role in roles if role not in valid_credit_roles)
        if invalid_roles:
            credit_issues.extend(f"invalid CRediT role {role}" for role in invalid_roles)
    credit_issues.extend(issue for issue in [required_text(credit, "statement", "authorship_credit", 8)] if issue)
    if credit_issues:
        fail("FAIL: Phase 15 authorship/CRediT statement is incomplete", credit_issues)
    integrity = ethics.get("integrity_review")
    if not isinstance(integrity, dict):
        fail("FAIL: Phase 15 integrity_review must be an object")
    integrity_issues = []
    for field in ("originality_check", "p_hacking_review", "selective_reporting_review", "misinterpretation_review"):
        if integrity.get(field) != "PASS":
            integrity_issues.append(f"{field} must be PASS")
    if integrity.get("citation_audit_used") is not True:
        integrity_issues.append("citation_audit_used must be true")
    if integrity.get("result_constraints_used") is not True:
        integrity_issues.append("result_constraints_used must be true")
    checked_artifacts = integrity.get("checked_artifacts")
    if not isinstance(checked_artifacts, list) or not checked_artifacts:
        integrity_issues.append("checked_artifacts must be nonempty")
    else:
        checked_by_path = {
            str(item.get("path", "")).strip(): item
            for item in checked_artifacts
            if isinstance(item, dict)
        }
        expected_integrity_artifacts = {
            "citation/citation-audit.json": sha256(citation_audit_path),
            "manuscript/draft-manifest.json": sha256(draft_manifest_path),
        }
        for rel, expected_hash in expected_integrity_artifacts.items():
            item = checked_by_path.get(rel)
            if not item:
                integrity_issues.append(f"checked_artifacts missing {rel}")
            elif item.get("sha256") != expected_hash:
                integrity_issues.append(f"checked_artifacts hash mismatch for {rel}")
    if integrity_issues:
        fail("FAIL: Phase 15 integrity review is incomplete", integrity_issues)
    for checklist_name in ("critical_fixes", "route_back"):
        if ethics.get("fix_checklist", {}).get(checklist_name) not in ([], None):
            fail(f"FAIL: Phase 15 fix_checklist.{checklist_name} must be empty for PASS")
    if ethics.get("route_back_phase") not in (None, ""):
        fail("FAIL: Phase 15 route_back_phase must be empty for PASS")
    if ethics.get("ready_for_phase_17") is not True:
        fail("FAIL: Phase 16 ready_for_phase_17 must be true")
    ethics_md = ethics_md_path.read_text(errors="ignore")
    if placeholder_pattern.search(ethics_md):
        fail("FAIL: Phase 15 markdown summary contains placeholder text")
    if word_count(ethics_md) < 120:
        fail("FAIL: Phase 15 ethics-open-science.md is too short")
    required_terms = {
        "ai": "AI use disclosure",
        "irb": "IRB statement",
        "consent": "consent statement",
        "conflict": "conflict-of-interest statement",
        "data availability": "data availability statement",
        "open science": "open science plan",
    }
    lower_md = ethics_md.lower()
    missing_terms = [label for term, label in required_terms.items() if term not in lower_md]
    if missing_terms:
        fail("FAIL: Phase 15 markdown summary is missing required declarations", missing_terms)
    sync_issues = []
    if "The authors declare no competing interests" in str(coi.get("statement", "")) and "the authors declare no competing interests" not in lower_md:
        sync_issues.append("COI statement missing from markdown")
    if sharing_mode and sharing_mode.lower() not in lower_md:
        sync_issues.append("data availability sharing_mode missing from markdown")
    if str(irb.get("status", "")).lower() not in lower_md:
        sync_issues.append("IRB status missing from markdown")
    consent_status_text = str(consent.get("status", "")).lower()
    if consent_status_text and consent_status_text not in lower_md and consent_status_text.replace("-", " ") not in lower_md:
        sync_issues.append("consent status missing from markdown")
    if "codex" in statement_lower and "codex" not in lower_md:
        sync_issues.append("AI tool disclosure missing from markdown")
    if sync_issues:
        fail("FAIL: Phase 15 markdown summary does not match JSON declarations", sync_issues)
    contradiction_pattern = re.compile(r"(critical|unresolved|pending|high risk).{0,80}(remains|open|unresolved|not resolved)", re.IGNORECASE)
    if contradiction_pattern.search(ethics_md):
        fail("FAIL: Phase 15 markdown summary contradicts JSON PASS status")

if phase_id == "17":
    lock_manifest_path = proj / "results-locked" / "manifest.json"
    latest_path = proj / "results-locked" / "LATEST.txt"
    stage1_path = proj / "verify" / "stage1-verify.json"
    execution_path = proj / "analysis" / "execution-report.json"
    ethics_path = proj / "ethics" / "ethics-open-science.json"
    data_status_path = proj / "data" / "data-status.json"
    report_path = proj / "replication-package" / "replication-report.json"
    package_manifest_path = proj / "replication-package" / "MANIFEST.json"
    readme_path = proj / "replication-package" / "README.md"
    test_report_path = proj / "replication-package" / "TEST-REPORT.md"
    verification_report_path = proj / "replication-package" / "VERIFICATION-REPORT.md"
    for required_path in (lock_manifest_path, latest_path, stage1_path, execution_path, ethics_path, data_status_path):
        if not required_path.exists():
            fail(f"FAIL: Phase 16 missing required input {required_path.relative_to(proj)}")
    try:
        lock_manifest = json.loads(lock_manifest_path.read_text())
        stage1_verify = json.loads(stage1_path.read_text())
        execution = json.loads(execution_path.read_text())
        ethics = json.loads(ethics_path.read_text())
        data_status = json.loads(data_status_path.read_text())
        report = json.loads(report_path.read_text())
        package_manifest = json.loads(package_manifest_path.read_text())
    except Exception as exc:
        fail(f"FAIL: Phase 16 replication artifacts are not valid JSON: {exc}")
    if ethics.get("verdict") != "PASS" or ethics.get("ready_for_phase_17") is not True:
        fail("FAIL: Phase 17 requires a passing Phase 16 ethics/open-science report")
    if execution.get("verdict") != "PASS":
        fail("FAIL: Phase 16 requires a passing Phase 8 execution report")
    lock_id = str(lock_manifest.get("lock_id", "")).strip()
    if not lock_id or latest_path.read_text(errors="ignore") != f"{lock_id}\n":
        fail("FAIL: Phase 16 results-locked/LATEST.txt must point to the active lock manifest")
    if stage1_verify.get("verdict") != "PASS":
        fail("FAIL: Phase 16 requires passing Phase 11 stage1 verification")
    required = (
        "verdict",
        "degraded",
        "replication_engine",
        "source_hashes",
        "replication_mode",
        "clean_room_verdict",
        "reproduction_match",
        "restricted_data_rationale",
        "package_inventory",
        "locked_artifact_coverage",
        "script_coverage",
        "data_handling",
        "path_safety",
        "environment",
        "test_report",
        "verification_report",
        "findings",
        "fix_checklist",
        "route_back_phase",
        "ready_for_phase_18",
    )
    absent = [field for field in required if field not in report]
    if absent:
        fail("FAIL: Phase 16 replication report missing required fields", absent)
    findings = report.get("findings")
    if not isinstance(findings, list):
        fail("FAIL: Phase 16 findings must be a list")
    if report.get("verdict") != "PASS":
        if report.get("verdict") != "FAIL":
            fail(f"FAIL: Phase 16 top-level verdict must be PASS or FAIL, got {report.get('verdict')}")
        allowed_categories = {
            "data_status": "4",
            "data_availability_mismatch": "16",
            "execution_output": "8",
            "results_lock": "11",
            "package_manifest": "17",
            "readme": "17",
            "path_safety": "17",
            "clean_room": "17",
            "reproduction_mismatch": "17",
            "paper_code_verification": "17",
            "restricted_data_packaging": "17",
            "environment": "17",
        }
        if not findings:
            fail("FAIL: Phase 16 FAIL report must include nonempty findings")
        finding_issues = []
        route_phases = set()
        critical_or_major = 0
        seen_findings = set()
        for idx, finding in enumerate(findings):
            if not isinstance(finding, dict):
                finding_issues.append(f"findings[{idx}] is not an object")
                continue
            finding_id = str(finding.get("finding_id", "")).strip()
            if not finding_id or finding_id in seen_findings:
                finding_issues.append(f"findings[{idx}].finding_id missing or duplicate")
            seen_findings.add(finding_id)
            severity = str(finding.get("severity", "")).strip()
            if severity not in {"CRITICAL", "MAJOR", "WARNING"}:
                finding_issues.append(f"{finding_id}: severity invalid")
            if severity in {"CRITICAL", "MAJOR"}:
                critical_or_major += 1
            category = str(finding.get("category", "")).strip()
            expected_phase = allowed_categories.get(category)
            if expected_phase is None:
                finding_issues.append(f"{finding_id}: category invalid")
            owner_phase = str(finding.get("owner_phase", "")).strip()
            route_back_phase = str(finding.get("route_back_phase", "")).strip()
            if expected_phase and owner_phase != expected_phase:
                finding_issues.append(f"{finding_id}: owner_phase must be {expected_phase} for {category}")
            if expected_phase and route_back_phase != expected_phase:
                finding_issues.append(f"{finding_id}: route_back_phase must be {expected_phase} for {category}")
            if route_back_phase:
                route_phases.add(route_back_phase)
            if finding.get("detected_by") not in {"scholar-replication", "replication-manifest", "clean-room-test", "paper-code-verification", "path-safety"}:
                finding_issues.append(f"{finding_id}: detected_by must be a Phase 16 checker")
            affected = finding.get("affected_artifacts")
            if not isinstance(affected, list) or not affected or any(not str(item).strip() for item in affected):
                finding_issues.append(f"{finding_id}: affected_artifacts must be a nonempty list")
            if not str(finding.get("required_fix", "")).strip():
                finding_issues.append(f"{finding_id}: required_fix missing")
            if finding.get("status") != "open":
                finding_issues.append(f"{finding_id}: status must be open")
        fix_checklist = report.get("fix_checklist")
        if not isinstance(fix_checklist, dict):
            finding_issues.append("fix_checklist must be an object")
        else:
            if critical_or_major and not fix_checklist.get("critical_fixes"):
                finding_issues.append("fix_checklist.critical_fixes must be nonempty for CRITICAL/MAJOR findings")
            route_back = fix_checklist.get("route_back")
            if not isinstance(route_back, list) or not route_back:
                finding_issues.append("fix_checklist.route_back must be nonempty for FAIL")
        top_route = str(report.get("route_back_phase", "")).strip()
        if not top_route:
            finding_issues.append("route_back_phase must be set for FAIL")
        elif route_phases and top_route != str(min(int(phase) for phase in route_phases)):
            finding_issues.append("route_back_phase must be the earliest finding route_back_phase")
        if report.get("ready_for_phase_18") is not False:
            finding_issues.append("ready_for_phase_18 must be false for FAIL")
        if finding_issues:
            fail("FAIL: Phase 16 FAIL report is malformed", finding_issues)
        fail("FAIL: Phase 17 replication package found unresolved issues; route back before Phase 18", [f"route_back_phase={top_route}"] + [f"{f.get('finding_id')}: {f.get('required_fix')}" for f in findings if isinstance(f, dict)])

    if report.get("degraded") is not False:
        fail("FAIL: Phase 16 degraded must be false")
    if str(report.get("source_phase", "")).strip() != "17":
        fail("FAIL: Phase 17 source_phase must be 17")
    if findings:
        fail("FAIL: Phase 16 PASS report must have empty findings")
    engine = report.get("replication_engine")
    if not isinstance(engine, dict) or engine.get("skill") != "scholar-replication" or engine.get("mode") != "FULL":
        fail("FAIL: Phase 16 replication_engine must be scholar-replication FULL mode")
    replication_engine_issues = validate_engine_provenance(engine, "Phase 17 replication_engine")
    if replication_engine_issues:
        fail("FAIL: Phase 17 replication_engine provenance is incomplete", replication_engine_issues)
    source_hashes = report.get("source_hashes")
    if not isinstance(source_hashes, dict):
        fail("FAIL: Phase 16 source_hashes must be an object")
    expected_hashes = {
        "lock_manifest": sha256(lock_manifest_path),
        "latest": sha256(latest_path),
        "stage1_verify": sha256(stage1_path),
        "execution_report": sha256(execution_path),
        "ethics_open_science": sha256(ethics_path),
        "data_status": sha256(data_status_path),
    }
    stale_sources = [
        f"{key} mismatch"
        for key, expected in expected_hashes.items()
        if source_hashes.get(key) != expected
    ]
    if stale_sources:
        fail("FAIL: Phase 16 source_hashes are stale", stale_sources)
    allowed_modes = {"public-data-full", "restricted-data-code-only", "synthetic-demo", "no-data-conceptual"}
    mode = str(report.get("replication_mode", "")).strip()
    expected_mode = str(ethics.get("data_availability", {}).get("sharing_mode", "")).strip()
    if mode not in allowed_modes:
        fail(f"FAIL: Phase 16 replication_mode invalid: {mode}")
    if expected_mode and mode != expected_mode:
        fail("FAIL: Phase 16 replication_mode must match Phase 15 data_availability.sharing_mode")
    data_access = str(data_status.get("access_status", "")).strip()
    if data_access == "restricted" and mode == "public-data-full":
        fail("FAIL: Phase 16 restricted data cannot use public-data-full replication mode")
    if mode == "public-data-full":
        if report.get("clean_room_verdict") != "PASS":
            fail("FAIL: Phase 16 public-data-full requires clean_room_verdict PASS")
        if report.get("reproduction_match") is not True:
            fail("FAIL: Phase 16 public-data-full requires reproduction_match true")
        if str(report.get("restricted_data_rationale", "")).strip():
            fail("FAIL: Phase 16 public-data-full must not set restricted_data_rationale")
    elif mode == "restricted-data-code-only":
        if report.get("clean_room_verdict") not in ("SKIPPED_RESTRICTED_DATA", "SCHEMA_TEST_PASS"):
            fail("FAIL: Phase 16 restricted-data-code-only requires restricted clean-room/schema verdict")
        if not str(report.get("restricted_data_rationale", "")).strip():
            fail("FAIL: Phase 16 restricted-data-code-only requires restricted_data_rationale")
    elif mode == "synthetic-demo":
        if report.get("clean_room_verdict") not in ("SYNTHETIC_TEST_PASS", "PASS"):
            fail("FAIL: Phase 16 synthetic-demo requires synthetic test verdict")
        if report.get("reproduction_match") not in (False, 0):
            fail("FAIL: Phase 16 synthetic-demo must not claim real output reproduction_match")
    elif mode == "no-data-conceptual":
        if report.get("clean_room_verdict") != "NOT_APPLICABLE":
            fail("FAIL: Phase 16 no-data-conceptual requires clean_room_verdict NOT_APPLICABLE")
    inventory = report.get("package_inventory")
    if not isinstance(inventory, dict):
        fail("FAIL: Phase 16 package_inventory must be an object")
    files = inventory.get("files")
    if not isinstance(files, list) or not files:
        fail("FAIL: Phase 16 package_inventory.files must be nonempty")
    manifest_files = package_manifest.get("files")
    if not isinstance(manifest_files, list) or not manifest_files:
        fail("FAIL: Phase 16 MANIFEST.json files must be nonempty")
    def file_map(file_list):
        return {
            str(item.get("path", "")).strip(): item
            for item in file_list
            if isinstance(item, dict) and str(item.get("path", "")).strip()
        }
    inv_by_path = file_map(files)
    manifest_by_path = file_map(manifest_files)
    required_package_paths = {
        "replication-package/README.md",
        "replication-package/replication-report.json",
        "replication-package/MANIFEST.json",
        "replication-package/TEST-REPORT.md",
        "replication-package/VERIFICATION-REPORT.md",
    }
    if set(inv_by_path) != set(manifest_by_path):
        fail("FAIL: Phase 16 package_inventory and MANIFEST.json must list the same files", sorted(set(inv_by_path) ^ set(manifest_by_path))[:20])
    actual_package_files = {
        str(path.relative_to(proj))
        for path in (proj / "replication-package").rglob("*")
        if path.is_file()
    }
    if set(manifest_by_path) != actual_package_files:
        missing = sorted(actual_package_files - set(manifest_by_path))
        extra = sorted(set(manifest_by_path) - actual_package_files)
        fail("FAIL: Phase 16 MANIFEST.json must exactly match files under replication-package", (missing + extra)[:30])
    missing_required_package = sorted(path for path in required_package_paths if path not in inv_by_path or not (proj / path).exists())
    if missing_required_package:
        fail("FAIL: Phase 16 package inventory missing required package files", missing_required_package)
    file_issues = []
    for rel, item in inv_by_path.items():
        path = Path(rel)
        if path.is_absolute() or ".." in path.parts or not rel.startswith("replication-package/"):
            file_issues.append(f"{rel}: path must be relative under replication-package/")
            continue
        actual = proj / rel
        if not actual.exists() or not actual.is_file():
            file_issues.append(f"{rel}: file missing")
            continue
        if rel in {"replication-package/replication-report.json", "replication-package/MANIFEST.json"}:
            if item.get("sha256") != "SELF_REFERENTIAL":
                file_issues.append(f"{rel}: self-referential package files must use sha256=SELF_REFERENTIAL")
        elif item.get("sha256") != sha256(actual):
            file_issues.append(f"{rel}: sha256 mismatch")
        if not str(item.get("role", "")).strip():
            file_issues.append(f"{rel}: role missing")
        manifest_item = manifest_by_path.get(rel, {})
        if manifest_item.get("sha256") != item.get("sha256"):
            file_issues.append(f"{rel}: manifest sha256 mismatch")
    if file_issues:
        fail("FAIL: Phase 16 package file inventory is invalid", file_issues[:30])
    readme_text = readme_path.read_text(errors="ignore")
    readme_lower = readme_text.lower()
    required_sections = ["overview", "data availability", "dataset list", "computational requirements", "description of programs", "instructions to replicators", "output correspondence", "known limitations", "references"]
    missing_sections = [section for section in required_sections if section not in readme_lower]
    if missing_sections:
        fail("FAIL: Phase 16 README missing required sections", missing_sections)
    package_texts = [readme_text, test_report_path.read_text(errors="ignore"), verification_report_path.read_text(errors="ignore"), json.dumps(report), json.dumps(package_manifest)]
    local_path_pattern = re.compile(r"(/Users/|/tmp/|/private/var/|/var/folders/|/home/|~[/\\]|\\$HOME|[A-Za-z]:\\\\|\\\\\\\\)")
    if any(local_path_pattern.search(text) for text in package_texts):
        fail("FAIL: Phase 16 replication package contains local absolute paths")
    placeholder_pattern = re.compile(
        r"\[(paper title|title|repository url|repository|doi|date|author|institution|protocol|protocol number|insert [^\]]+|add [^\]]+)\]"
        r"|\b(TBD|TODO|XXXX+|to be determined|Author\s+[0-9X])\b",
        re.IGNORECASE
    )
    if any(placeholder_pattern.search(text) for text in package_texts):
        fail("FAIL: Phase 16 replication package contains placeholder text")
    locked_artifacts = lock_manifest.get("locked_artifacts")
    if not isinstance(locked_artifacts, list) or not locked_artifacts:
        fail("FAIL: Phase 16 requires nonempty results-locked manifest")
    coverage = report.get("locked_artifact_coverage")
    if not isinstance(coverage, dict):
        fail("FAIL: Phase 16 locked_artifact_coverage must be an object")
    covered = coverage.get("covered_artifacts")
    if not isinstance(covered, list):
        fail("FAIL: Phase 16 locked_artifact_coverage.covered_artifacts must be a list")
    expected_locked_sources = {
        str(item.get("source_path", "")).strip()
        for item in locked_artifacts
        if isinstance(item, dict) and str(item.get("source_path", "")).strip()
    }
    covered_sources = {
        str(item.get("source_path", "")).strip()
        for item in covered
        if isinstance(item, dict) and str(item.get("source_path", "")).strip()
    }
    if covered_sources != expected_locked_sources:
        fail("FAIL: Phase 16 locked_artifact_coverage must cover every active locked artifact", sorted(expected_locked_sources - covered_sources) + sorted(covered_sources - expected_locked_sources))
    coverage_issues = []
    for item in covered:
        if not isinstance(item, dict):
            coverage_issues.append("covered artifact entry is not an object")
            continue
        source = str(item.get("source_path", "")).strip()
        package_path = str(item.get("package_path", "")).strip()
        status = str(item.get("status", "")).strip()
        if status not in {"copied", "documented_restricted", "documented_not_applicable"}:
            coverage_issues.append(f"{source}: invalid status {status}")
        if mode == "public-data-full":
            if status != "copied":
                coverage_issues.append(f"{source}: public-data-full requires copied locked artifact")
            elif package_path not in inv_by_path or not (proj / package_path).exists():
                coverage_issues.append(f"{source}: package_path missing from inventory")
        elif not package_path and status == "copied":
            coverage_issues.append(f"{source}: copied status requires package_path")
    if coverage_issues:
        fail("FAIL: Phase 16 locked artifact coverage is incomplete", coverage_issues)
    script_coverage = report.get("script_coverage")
    if not isinstance(script_coverage, dict):
        fail("FAIL: Phase 16 script_coverage must be an object")
    script_records = script_coverage.get("scripts")
    if not isinstance(script_records, list):
        fail("FAIL: Phase 16 script_coverage.scripts must be a list")
    if mode in {"public-data-full", "restricted-data-code-only", "synthetic-demo"} and not script_records:
        fail("FAIL: Phase 16 empirical replication modes require nonempty script coverage")
    execution_scripts = {
        str(item.get("path", "")).strip(): item
        for item in execution.get("executed_scripts", [])
        if isinstance(item, dict) and str(item.get("path", "")).strip()
    }
    script_sources = {
        str(item.get("source_path", "")).strip()
        for item in script_records
        if isinstance(item, dict) and str(item.get("source_path", "")).strip()
    }
    if mode in {"public-data-full", "restricted-data-code-only", "synthetic-demo"}:
        if script_sources != set(execution_scripts):
            missing = sorted(set(execution_scripts) - script_sources)
            extra = sorted(script_sources - set(execution_scripts))
            fail("FAIL: Phase 16 script_coverage must exactly cover Phase 8 executed_scripts", missing + extra)
        if int(script_coverage.get("executed_script_count", -1)) != len(execution_scripts):
            fail("FAIL: Phase 16 script_coverage.executed_script_count must match Phase 8 execution report")
        if int(script_coverage.get("packaged_script_count", -1)) != len(script_records):
            fail("FAIL: Phase 16 script_coverage.packaged_script_count must match script records")
    if mode in {"public-data-full", "restricted-data-code-only", "synthetic-demo"} and "replication-package/scripts/run-all.sh" not in inv_by_path:
        fail("FAIL: Phase 16 empirical replication modes require replication-package/scripts/run-all.sh")
    script_issues = []
    for idx, script in enumerate(script_records):
        if not isinstance(script, dict):
            script_issues.append(f"scripts[{idx}] is not an object")
            continue
        rel = str(script.get("package_path", "")).strip()
        if not rel or rel not in inv_by_path or not (proj / rel).exists():
            script_issues.append(f"scripts[{idx}].package_path missing from inventory")
        source_path = str(script.get("source_path", "")).strip()
        expected_exec = execution_scripts.get(source_path)
        if expected_exec:
            if script.get("source_hash") != expected_exec.get("script_hash"):
                script_issues.append(f"{source_path}: source_hash must match Phase 8 script_hash")
        elif mode in {"public-data-full", "restricted-data-code-only", "synthetic-demo"}:
            script_issues.append(f"{source_path}: not found in Phase 8 executed_scripts")
        if script.get("syntax_check") not in ("PASS", "NOT_APPLICABLE"):
            script_issues.append(f"scripts[{idx}].syntax_check={script.get('syntax_check')}")
        outputs = script.get("produces")
        if not isinstance(outputs, list):
            script_issues.append(f"scripts[{idx}].produces must be list")
    if script_issues:
        fail("FAIL: Phase 16 script coverage is incomplete", script_issues)
    data_handling = report.get("data_handling")
    if not isinstance(data_handling, dict):
        fail("FAIL: Phase 16 data_handling must be an object")
    data_issues = []
    if data_handling.get("mode") != mode:
        data_issues.append("data_handling.mode must match replication_mode")
    if mode == "public-data-full" and data_handling.get("restricted_data_included") not in (False, 0):
        data_issues.append("public-data-full cannot include restricted_data_included true")
    if mode == "restricted-data-code-only":
        if data_handling.get("restricted_data_included") not in (False, 0):
            data_issues.append("restricted raw data must not be bundled")
        if not str(data_handling.get("access_instructions", "")).strip():
            data_issues.append("restricted mode requires access_instructions")
        if data_handling.get("schema_or_synthetic_validation") is not True:
            data_issues.append("restricted mode requires schema_or_synthetic_validation true")
    if mode == "synthetic-demo":
        if data_handling.get("synthetic_data_included") is not True:
            data_issues.append("synthetic-demo requires synthetic_data_included true")
        if data_handling.get("non_equivalence_statement") is not True:
            data_issues.append("synthetic-demo requires non_equivalence_statement true")
    if data_issues:
        fail("FAIL: Phase 16 data handling is inconsistent", data_issues)
    path_safety = report.get("path_safety")
    if not isinstance(path_safety, dict):
        fail("FAIL: Phase 16 path_safety must be an object")
    if path_safety.get("absolute_paths_found") not in (False, 0) or path_safety.get("local_path_leaks_found") not in (False, 0):
        fail("FAIL: Phase 16 path safety found absolute or local path leaks")
    environment = report.get("environment")
    if not isinstance(environment, dict):
        fail("FAIL: Phase 16 environment must be an object")
    if environment.get("lockfile_present") is not True and not str(environment.get("session_info", "")).strip():
        fail("FAIL: Phase 16 environment must include a lockfile or session_info")
    if mode in {"public-data-full", "restricted-data-code-only", "synthetic-demo"}:
        env_files = set(environment.get("files", []) if isinstance(environment.get("files"), list) else [])
        if not (env_files & set(inv_by_path) or str(environment.get("session_info", "")).strip()):
            fail("FAIL: Phase 16 empirical replication modes require environment files in package inventory or session_info")
    for section_name, path, verdict_key in (
        ("test_report", test_report_path, "verdict"),
        ("verification_report", verification_report_path, "verdict"),
    ):
        section = report.get(section_name)
        if not isinstance(section, dict):
            fail(f"FAIL: Phase 16 {section_name} must be an object")
        if section.get("path") != str(path.relative_to(proj)):
            fail(f"FAIL: Phase 16 {section_name}.path must be {path.relative_to(proj)}")
        allowed_verdicts = {"PASS", "NOT_APPLICABLE"}
        if mode == "restricted-data-code-only" and section_name == "test_report":
            allowed_verdicts.add("SCHEMA_TEST_PASS")
        if mode == "synthetic-demo" and section_name == "test_report":
            allowed_verdicts.add("SYNTHETIC_TEST_PASS")
        if section.get(verdict_key) not in allowed_verdicts:
            fail(f"FAIL: Phase 16 {section_name}.{verdict_key} invalid: {section.get(verdict_key)}")
        if section.get("sha256") != sha256(path):
            fail(f"FAIL: Phase 16 {section_name}.sha256 mismatch")
        if word_count(path.read_text(errors="ignore")) < 40:
            fail(f"FAIL: Phase 16 {path.relative_to(proj)} is too short")
    if report.get("fix_checklist", {}).get("critical_fixes") not in ([], None):
        fail("FAIL: Phase 16 fix_checklist.critical_fixes must be empty for PASS")
    if report.get("fix_checklist", {}).get("route_back") not in ([], None):
        fail("FAIL: Phase 16 fix_checklist.route_back must be empty for PASS")
    if report.get("route_back_phase") not in (None, ""):
        fail("FAIL: Phase 16 route_back_phase must be empty for PASS")
    if report.get("ready_for_phase_18") is not True:
        fail("FAIL: Phase 17 ready_for_phase_18 must be true")

if phase_id == "18":
    manuscript_path = proj / "manuscript" / "manuscript-draft.md"
    draft_manifest_path = proj / "manuscript" / "draft-manifest.json"
    polish_report_path = proj / "manuscript" / "polish-report.json"
    journal_spec_path = proj / "manuscript" / "journal-spec.json"
    phase13_path = proj / "verify" / "manuscript-verification.json"
    citation_audit_path = proj / "citation" / "citation-audit.json"
    claim_map_path = proj / "citation" / "claim-source-map.json"
    ethics_path = proj / "ethics" / "ethics-open-science.json"
    replication_path = proj / "replication-package" / "replication-report.json"
    quality_path = proj / "quality" / "manuscript-quality.json"
    quality_md_path = proj / "quality" / "manuscript-quality.md"
    required_inputs = (
        manuscript_path,
        draft_manifest_path,
        polish_report_path,
        phase13_path,
        citation_audit_path,
        claim_map_path,
        ethics_path,
        replication_path,
    )
    for required_path in required_inputs:
        if not required_path.exists():
            fail(f"FAIL: Phase 17 missing required input {required_path.relative_to(proj)}")
    try:
        draft_manifest = json.loads(draft_manifest_path.read_text())
        polish_report = json.loads(polish_report_path.read_text())
        phase13 = json.loads(phase13_path.read_text())
        citation_audit = json.loads(citation_audit_path.read_text())
        claim_map = json.loads(claim_map_path.read_text())
        ethics = json.loads(ethics_path.read_text())
        replication = json.loads(replication_path.read_text())
        quality = json.loads(quality_path.read_text())
        journal_spec = json.loads(journal_spec_path.read_text()) if journal_spec_path.exists() else {}
    except Exception as exc:
        fail(f"FAIL: Phase 17 quality artifacts or inputs are not valid JSON: {exc}")
    if draft_manifest.get("ready_for_phase_14") is not True:
        fail("FAIL: Phase 18 requires a passing Phase 13 draft manifest")
    if phase13.get("verdict") != "PASS" or phase13.get("ready_for_phase_15") is not True:
        fail("FAIL: Phase 18 requires a passing Phase 14 manuscript verification report")
    if citation_audit.get("verdict") != "PASS" or citation_audit.get("ready_for_phase_16") is not True:
        fail("FAIL: Phase 18 requires a passing Phase 15 citation audit")
    if ethics.get("verdict") != "PASS" or ethics.get("ready_for_phase_17") is not True:
        fail("FAIL: Phase 18 requires a passing Phase 16 ethics/open-science report")
    if replication.get("verdict") != "PASS" or replication.get("ready_for_phase_18") is not True:
        fail("FAIL: Phase 18 requires a passing Phase 17 replication report")
    manuscript_text = manuscript_path.read_text(errors="ignore")
    manuscript_sections = markdown_sections(manuscript_text)
    section_budget_for_quality = draft_manifest.get("section_word_budget")
    budget_compliance_for_quality = draft_manifest.get("budget_compliance")
    declared_prose_counts = draft_manifest.get("section_prose_word_counts")
    if not isinstance(section_budget_for_quality, dict):
        fail("FAIL: Phase 18 requires Phase 13 section_word_budget for independent substance audit")
    if not isinstance(budget_compliance_for_quality, dict):
        fail("FAIL: Phase 18 requires Phase 13 budget_compliance for independent substance audit")
    if not isinstance(declared_prose_counts, dict):
        fail("FAIL: Phase 18 requires Phase 13 section_prose_word_counts for independent substance audit")
    quality_section_prose_counts = {}
    quality_budget_issues = []
    for section, budget in section_budget_for_quality.items():
        section_key = norm_text(section)
        if section_key not in manuscript_sections:
            continue
        quality_section_prose_counts[section_key] = prose_word_count(manuscript_sections.get(section_key, ""))
        if int(declared_prose_counts.get(section_key, -1)) != quality_section_prose_counts[section_key]:
            quality_budget_issues.append(
                f"{section_key}: declared prose count {declared_prose_counts.get(section_key)} "
                f"actual {quality_section_prose_counts[section_key]}"
            )
    quality_main_text_words = sum(quality_section_prose_counts.values())
    if int(budget_compliance_for_quality.get("main_text_word_count", -1)) != quality_main_text_words:
        quality_budget_issues.append(
            f"budget_compliance.main_text_word_count={budget_compliance_for_quality.get('main_text_word_count')} "
            f"actual={quality_main_text_words}"
        )
    short_format_pattern = re.compile(r"\b(research note|brief|short report|commentary|registered report|stage|replication note|letter)\b", re.IGNORECASE)
    journal_decl = draft_manifest.get("journal_spec") if isinstance(draft_manifest.get("journal_spec"), dict) else {}
    paper_type_text = " ".join(str(journal_decl.get(field, "")) for field in ("paper_type", "article_type", "format"))
    total_range = budget_compliance_for_quality.get("total_word_range")
    if not isinstance(total_range, dict):
        total_range = {}
    try:
        total_min = int(total_range.get("min", -1))
        total_max = int(total_range.get("max", -1))
    except Exception:
        total_min = total_max = -1
    if not short_format_pattern.search(paper_type_text):
        if total_min < 4000 or total_max < total_min:
            quality_budget_issues.append("full empirical article has missing or invalid total_word_range in Phase 13 budget_compliance")
        elif quality_main_text_words < total_min:
            quality_budget_issues.append(
                f"main-text prose word count {quality_main_text_words} is below journal minimum {total_min}; "
                f"references, tables, figures, declarations, captions, and trace metadata do not count as article substance"
            )
        for section, budget in section_budget_for_quality.items():
            section_key = norm_text(section)
            if section_key == "abstract" or section_key not in quality_section_prose_counts or not isinstance(budget, dict):
                continue
            try:
                target_words = int(budget.get("target_words", -1))
            except Exception:
                target_words = -1
            if target_words > 0 and quality_section_prose_counts[section_key] < int(target_words * 0.85):
                quality_budget_issues.append(
                    f"{section_key}: {quality_section_prose_counts[section_key]} prose words is below "
                    f"85% of journal target_words {target_words}"
                )
    if quality_budget_issues:
        fail("FAIL: Phase 18 independent manuscript substance audit failed", quality_budget_issues[:30])
    required = (
        "verdict",
        "degraded",
        "source_phase",
        "quality_engine",
        "selected_manuscript_hash",
        "source_hashes",
        "reviewer_reports",
        "reviewer_independence",
        "adversarial_review_coverage",
        "method_specialist_review",
        "polish_audit",
        "dimension_scores",
        "threshold_policy",
        "severity_confidence_matrix",
        "decision",
        "findings",
        "fix_checklist",
        "route_back_phase",
        "ready_for_phase_19",
    )
    absent = [field for field in required if field not in quality]
    if absent:
        fail("FAIL: Phase 17 quality report missing required fields", absent)
    findings = quality.get("findings")
    if not isinstance(findings, list):
        fail("FAIL: Phase 17 findings must be a list")
    allowed_categories = {
        "research_question_answer": "13",
        "manuscript_structure": "13",
        "argument_coherence": "12",
        "prose_quality": "13",
        "theory_contribution": "2",
        "design_logic": "3",
        "data_measurement": "4",
        "dataset_design": "4",
        "analysis_plan": "5",
        "missingness_sensitivity": "5",
        "outcome_model_ladder": "5",
        "regression_table_architecture": "13",
        "hypothesis_display": "13",
        "analysis_execution": "8",
        "verification_traceability": "14",
        "citation_claim_support": "15",
        "ethics_open_science": "16",
        "replication_reproducibility": "17",
        "review_process": "18",
        "journal_fit": "13",
    }
    if quality.get("verdict") != "PASS":
        if quality.get("verdict") != "FAIL":
            fail(f"FAIL: Phase 17 top-level verdict must be PASS or FAIL, got {quality.get('verdict')}")
        if not findings:
            fail("FAIL: Phase 17 FAIL report must include nonempty findings")
        finding_issues = []
        route_phases = set()
        critical_or_major = 0
        seen_findings = set()
        for idx, finding in enumerate(findings):
            if not isinstance(finding, dict):
                finding_issues.append(f"findings[{idx}] is not an object")
                continue
            finding_id = str(finding.get("finding_id", "")).strip()
            if not finding_id or finding_id in seen_findings:
                finding_issues.append(f"findings[{idx}].finding_id missing or duplicate")
            seen_findings.add(finding_id)
            severity = str(finding.get("severity", "")).strip()
            if severity not in {"CRITICAL", "MAJOR", "MINOR", "WARNING"}:
                finding_issues.append(f"{finding_id}: severity invalid")
            if severity in {"CRITICAL", "MAJOR"}:
                critical_or_major += 1
            category = str(finding.get("category", "")).strip()
            expected_phase = allowed_categories.get(category)
            if expected_phase is None:
                finding_issues.append(f"{finding_id}: category invalid")
            owner_phase = str(finding.get("owner_phase", "")).strip()
            route_back_phase = str(finding.get("route_back_phase", "")).strip()
            if expected_phase and owner_phase != expected_phase:
                finding_issues.append(f"{finding_id}: owner_phase must be {expected_phase} for {category}")
            if expected_phase and route_back_phase != expected_phase:
                finding_issues.append(f"{finding_id}: route_back_phase must be {expected_phase} for {category}")
            if route_back_phase:
                route_phases.add(route_back_phase)
            if finding.get("detected_by") not in {"scholar-respond", "scholar-polish", "quality-panel", "senior-editor", "interpretive-skeptic", "quality-verifier"}:
                finding_issues.append(f"{finding_id}: detected_by must be a Phase 17 checker")
            affected = finding.get("affected_artifacts")
            if not isinstance(affected, list) or not affected or any(not str(item).strip() for item in affected):
                finding_issues.append(f"{finding_id}: affected_artifacts must be a nonempty list")
            if not str(finding.get("required_fix", "")).strip():
                finding_issues.append(f"{finding_id}: required_fix missing")
            if finding.get("status") != "open":
                finding_issues.append(f"{finding_id}: status must be open")
        fix_checklist = quality.get("fix_checklist")
        if not isinstance(fix_checklist, dict):
            finding_issues.append("fix_checklist must be an object")
        else:
            if critical_or_major and not fix_checklist.get("critical_fixes"):
                finding_issues.append("fix_checklist.critical_fixes must be nonempty for CRITICAL/MAJOR findings")
            route_back = fix_checklist.get("route_back")
            if not isinstance(route_back, list) or not route_back:
                finding_issues.append("fix_checklist.route_back must be nonempty for FAIL")
        top_route = str(quality.get("route_back_phase", "")).strip()
        if not top_route:
            finding_issues.append("route_back_phase must be set for FAIL")
        elif route_phases and top_route != str(min(int(phase) for phase in route_phases)):
            finding_issues.append("route_back_phase must be the earliest finding route_back_phase")
        if quality.get("source_phase") != "18":
            finding_issues.append("source_phase must be 18")
        if quality.get("ready_for_phase_19") is not False:
            finding_issues.append("ready_for_phase_19 must be false for FAIL")
        if finding_issues:
            fail("FAIL: Phase 17 FAIL report is malformed", finding_issues)
        fail("FAIL: Phase 18 quality gate found unresolved manuscript issues; route back before Phase 19", [f"route_back_phase={top_route}"] + [f"{f.get('finding_id')}: {f.get('required_fix')}" for f in findings if isinstance(f, dict)])

    if quality.get("degraded") is not False:
        fail("FAIL: Phase 18 degraded must be false")
    if quality.get("source_phase") != "18":
        fail("FAIL: Phase 18 source_phase must be 18")
    if findings:
        fail("FAIL: Phase 17 PASS report must have empty findings")
    engine = quality.get("quality_engine")
    if not isinstance(engine, dict) or engine.get("skill") != "scholar-respond" or engine.get("mode") != "simulate":
        fail("FAIL: Phase 17 quality_engine must be scholar-respond simulate mode")
    quality_engine_issues = validate_engine_provenance(engine, "Phase 18 quality_engine")
    if quality_engine_issues:
        fail("FAIL: Phase 18 quality_engine provenance is incomplete", quality_engine_issues)
    if quality.get("selected_manuscript_hash") != sha256(manuscript_path):
        fail("FAIL: Phase 17 selected_manuscript_hash is stale")
    source_hashes = quality.get("source_hashes")
    if not isinstance(source_hashes, dict):
        fail("FAIL: Phase 17 source_hashes must be an object")
    expected_hashes = {
        "manuscript": sha256(manuscript_path),
        "draft_manifest": sha256(draft_manifest_path),
        "polish_report": sha256(polish_report_path),
        "manuscript_verification": sha256(phase13_path),
        "citation_audit": sha256(citation_audit_path),
        "claim_source_map": sha256(claim_map_path),
        "ethics_open_science": sha256(ethics_path),
        "replication_report": sha256(replication_path),
    }
    stale_sources = [
        f"{key} mismatch"
        for key, expected in expected_hashes.items()
        if source_hashes.get(key) != expected
    ]
    if stale_sources:
        fail("FAIL: Phase 17 source_hashes are stale", stale_sources)
    if claim_map.get("unsupported_count", 0) not in (0, "0") or claim_map.get("locator_missing_count", 0) not in (0, "0"):
        fail("FAIL: Phase 17 cannot pass with unsupported claims or missing source locators")
    if polish_report.get("verdict") != "PASS" or polish_report.get("ready_for_verification") is not True:
        fail("FAIL: Phase 17 requires passing Phase 12 scholar-polish report")
    polish_audit = quality.get("polish_audit")
    if not isinstance(polish_audit, dict):
        fail("FAIL: Phase 17 polish_audit must be an object")
    if polish_audit.get("skill") != "scholar-polish" or polish_audit.get("mode") != "scan":
        fail("FAIL: Phase 17 polish_audit must declare scholar-polish scan mode")
    polish_audit_issues = validate_engine_provenance(polish_audit, "Phase 18 polish_audit")
    if polish_audit_issues:
        fail("FAIL: Phase 18 polish_audit provenance is incomplete", polish_audit_issues)
    if polish_audit.get("manuscript_hash") != sha256(manuscript_path):
        fail("FAIL: Phase 17 polish_audit manuscript_hash is stale")
    if polish_audit.get("rewrite_applied") not in (False, 0):
        fail("FAIL: Phase 17 polish_audit must not rewrite the verified manuscript")
    if polish_audit.get("high_severity_markers") not in (0, "0"):
        fail("FAIL: Phase 17 polish_audit must report zero high-severity AI writing markers")
    if polish_audit.get("route_back_required") not in (False, 0):
        fail("FAIL: Phase 17 polish_audit route_back_required must be false for PASS")
    reviewers = quality.get("reviewer_reports")
    if not isinstance(reviewers, list) or len(reviewers) < 4:
        fail("FAIL: Phase 17 requires at least four independent reviewer reports")
    required_roles = {"methods-evidence", "theory-contribution", "senior-editor", "interpretive-skeptic"}
    roles = {str(reviewer.get("role", "")).strip() for reviewer in reviewers if isinstance(reviewer, dict)}
    missing_roles = sorted(required_roles - roles)
    if missing_roles:
        fail("FAIL: Phase 17 missing required reviewer roles", missing_roles)
    if not any(isinstance(reviewer, dict) and reviewer.get("role") == "senior-editor" and reviewer.get("primed") in (False, 0) for reviewer in reviewers):
        fail("FAIL: Phase 17 requires an unprimed senior-editor reviewer")
    structured_quality_review_needed = structured_secondary_data_indicated(manuscript_text, draft_manifest, claim_map)
    if structured_quality_review_needed:
        specialist_roles = {
            "survey-methods",
            "demographic-family-methods",
            "quantitative-family-methods",
            "domain-methods",
            "methods-specialist",
        }
        if not roles.intersection(specialist_roles):
            fail("FAIL: Phase 18 structured secondary-data manuscripts require a method-specialized reviewer", sorted(specialist_roles))
    reviewer_independence = quality.get("reviewer_independence")
    if not isinstance(reviewer_independence, dict):
        fail("FAIL: Phase 18 reviewer_independence must be an object")
    if reviewer_independence.get("status") != "PASS" or reviewer_independence.get("duplicate_report_count") not in (0, "0"):
        fail("FAIL: Phase 18 reviewer_independence must report PASS status and zero duplicate reports")
    adversarial_coverage = quality.get("adversarial_review_coverage")
    if not isinstance(adversarial_coverage, dict):
        fail("FAIL: Phase 18 adversarial_review_coverage must be an object")
    if adversarial_coverage.get("status") != "PASS" or adversarial_coverage.get("all_reports_have_concrete_locator") is not True or adversarial_coverage.get("all_reports_have_risk_or_robustness_issue") is not True:
        fail("FAIL: Phase 18 adversarial_review_coverage must confirm concrete locators and risk/robustness coverage")
    method_specialist_review = quality.get("method_specialist_review")
    if not isinstance(method_specialist_review, dict):
        fail("FAIL: Phase 18 method_specialist_review must be an object")
    if method_specialist_review.get("status") not in {"PASS", "NOT_APPLICABLE"}:
        fail("FAIL: Phase 18 method_specialist_review status must be PASS or NOT_APPLICABLE")
    if structured_quality_review_needed and method_specialist_review.get("status") != "PASS":
        fail("FAIL: Phase 18 method_specialist_review must PASS when structured secondary-data review is needed")

    # External-gate dispatch:
    # Phase 18 must compute shape evidence from artifacts, not trust the
    # self-reported regression_table_audit. Run each gate; RED status fails
    # the phase regardless of metadata. See quality-gate.md for contract.
    external_gate_failures = []
    for gate_name, label in [
        # 5.18.0 structural gates (front matter, table fidelity, descriptives, methods bridge)
        ("front-matter-check.sh", "Phase 18 front matter"),
        ("abstract-boilerplate-check.sh", "Phase 18 abstract boilerplate"),
        ("regression-table-export-check.sh", "Phase 18 regression-engine purity"),
        ("regression-table-family-shape-check.sh", "Phase 18 regression table family shape"),
        ("regression-table-display-check.sh", "Phase 18 full regression table reader-facing"),
        ("locked-artifact-transclusion-check.sh", "Phase 18 locked-artifact transclusion"),
        ("manuscript-title-check.sh", "Phase 18 manuscript title"),
        ("journal-section-architecture-check.sh", "Phase 18 journal section architecture"),
        ("introduction-argument-architecture-check.sh", "Phase 18 introduction argument architecture"),
        ("theory-hypothesis-continuity-check.sh", "Phase 18 theory/hypothesis continuity"),
        ("theory-structure-depth-check.sh", "Phase 18 theory structure depth"),
        ("methods-role-subsections-check.sh", "Phase 18 methods role subsections"),
        ("data-sample-flow-check.sh", "Phase 18 data/sample flow"),
        ("analytic-strategy-quality-check.sh", "Phase 18 analytic strategy quality"),
        ("analytic-formula-specificity-check.sh", "Phase 18 method-specific analytic detail"),
        ("discussion-adjudication-check.sh", "Phase 18 discussion adjudication"),
        ("conclusion-contribution-support-check.sh", "Phase 18 conclusion contribution support"),
        ("cross-section-continuity-check.sh", "Phase 18 cross-section continuity"),
        ("manuscript-artifact-leakage-check.sh", "Phase 18 manuscript artifact leakage"),
        ("citation-cluster-quality-check.sh", "Phase 18 citation cluster quality"),
        ("figure-style-source-check.sh", "Phase 18 figure style source"),
        ("descriptives-coverage-check.sh", "Phase 18 descriptive-table coverage"),
        ("descriptive-table-display-check.sh", "Phase 18 descriptive table display"),
        ("concept-to-measure-check.sh", "Phase 18 concept-to-measure bridge"),
        # 5.19.0 substantive-quality gates
        ("survey-weights-check.sh", "Phase 18 survey weights"),
        ("composite-measure-validation-check.sh", "Phase 18 composite-measure validation"),
        ("interaction-joint-test-check.sh", "Phase 18 interaction joint test"),
    ]:
        gate_result = run_external_gate(gate_name, proj, label)
        if gate_result is None:
            continue
        status, reason, detail = gate_result
        if status == "RED":
            external_gate_failures.append(f"{label}: reason={reason} detail={detail}")
    # G5 effect-size-narrative-check is phase-aware (RED at 11.5/18/19/20, YELLOW at 13).
    # Run it explicitly with phase tag "18" so it RED-fails when small R² is unacknowledged.
    if GATE_DIR is not None:
        es_gate = GATE_DIR / "effect-size-narrative-check.sh"
        if es_gate.exists():
            try:
                es_result = subprocess.run(
                    ["bash", str(es_gate), str(proj), "18"],
                    capture_output=True, text=True, timeout=120,
                )
                es_status = ""
                es_reason = ""
                es_detail = ""
                for line in (es_result.stdout or "").splitlines():
                    if line.startswith("STATUS="):
                        es_status = line.split("=", 1)[1].strip()
                    elif line.startswith("REASON="):
                        es_reason = line.split("=", 1)[1].strip()
                    elif line.startswith("DETAIL:"):
                        es_detail = line.split(":", 1)[1].strip()
                if es_status == "RED":
                    external_gate_failures.append(
                        f"Phase 18 effect-size narrative: reason={es_reason} detail={es_detail}"
                    )
            except Exception as exc:
                external_gate_failures.append(
                    f"Phase 18 effect-size narrative: gate_invocation_error={exc}"
                )
    if external_gate_failures:
        fail("FAIL: Phase 18 external-gate panel reported RED", external_gate_failures)

    regression_table_needed = quantitative_empirical_regression_table_required(
        manuscript_text,
        draft_manifest,
        claim_map,
        quality,
    )
    registry_display_issues = (
        displayed_registry_sources_from_coverage(draft_manifest.get("locked_result_coverage"))
        + registry_like_table_display_hits(manuscript_text)
    )
    if registry_display_issues:
        fail("FAIL: Phase 18 quality gate cannot pass registry/model-ladder reader-facing Results tables", registry_display_issues[:25])
    model_label_issues = reader_internal_spec_index_hits(manuscript_text)
    if model_label_issues:
        fail("FAIL: Phase 18 quality gate cannot pass internal S1/S2-style model labels in reader-facing text", model_label_issues[:25])
    hypothesis_list_hits = hypothesis_display_hits(manuscript_text)
    if hypothesis_list_hits:
        if not displayed_hypotheses_allowed(journal_spec, draft_manifest, quality):
            fail("FAIL: Phase 18 quality gate cannot pass proposal-style hypothesis bullet/list blocks", hypothesis_list_hits[:25])
        bare_hypothesis_hits = bare_hypothesis_display_hits(manuscript_text)
        if bare_hypothesis_hits:
            fail("FAIL: Phase 18 quality gate cannot pass displayed hypotheses without nearby theoretical motivation", bare_hypothesis_hits[:25])
    if regression_table_needed:
        if not has_canonical_regression_display(draft_manifest.get("locked_result_coverage")):
            fail("FAIL: Phase 18 quantitative manuscript lacks a canonical regression table display")
        regression_audit = quality.get("regression_table_audit")
        if not isinstance(regression_audit, dict):
            fail("FAIL: Phase 18 quantitative manuscripts require regression_table_audit")
        required_true = [
            "canonical_main_regression_table_present",
            "model_columns_as_columns",
            "predictor_rows_as_rows",
            "standard_errors_or_intervals_present",
            "sample_size_present",
            "reader_facing_labels_used",
            "notes_cover_design_features",
        ]
        audit_issues = []
        if regression_audit.get("status") != "PASS":
            audit_issues.append("regression_table_audit.status must be PASS")
        for field in required_true:
            if regression_audit.get(field) is not True:
                audit_issues.append(f"regression_table_audit.{field} must be true")
        if regression_audit.get("registry_table_used_as_main_display") not in (False, 0):
            audit_issues.append("regression_table_audit.registry_table_used_as_main_display must be false")
        if audit_issues:
            fail("FAIL: Phase 18 regression table audit failed", audit_issues)
    reviewer_issues = []
    seen_reviewers = set()
    seen_reviewer_tasks = set()
    seen_reviewer_paths = set()
    reviewer_texts = []
    placeholder_values = {"", "tbd", "todo", "unknown", "n/a", "na", "placeholder"}
    for idx, reviewer in enumerate(reviewers):
        if not isinstance(reviewer, dict):
            reviewer_issues.append(f"reviewer_reports[{idx}] is not an object")
            continue
        reviewer_id = str(reviewer.get("reviewer_id", "")).strip()
        role = str(reviewer.get("role", "")).strip()
        if not reviewer_id or reviewer_id in seen_reviewers:
            reviewer_issues.append(f"reviewer_reports[{idx}].reviewer_id missing or duplicate")
        seen_reviewers.add(reviewer_id)
        agent_name = str(reviewer.get("agent_name", "")).strip()
        if not agent_name.startswith("peer-reviewer-"):
            reviewer_issues.append(f"{reviewer_id}: agent_name must start with peer-reviewer-")
        task_id = str(reviewer.get("task_invocation_id", "")).strip()
        if not task_id or task_id in seen_reviewer_tasks or task_id.lower() in placeholder_values:
            reviewer_issues.append(f"{reviewer_id}: task_invocation_id missing")
        seen_reviewer_tasks.add(task_id)
        report_path = str(reviewer.get("report_path", "")).strip()
        if report_path in seen_reviewer_paths:
            reviewer_issues.append(f"{reviewer_id}: duplicate report_path")
        seen_reviewer_paths.add(report_path)
        if not report_path.startswith("quality/agents/") or not (proj / report_path).exists():
            reviewer_issues.append(f"{reviewer_id}: report_path missing under quality/agents/")
        else:
            report_text = (proj / report_path).read_text(errors="ignore")
            reviewer_texts.append((reviewer_id, role, report_text))
            if word_count(report_text) < 50:
                reviewer_issues.append(f"{reviewer_id}: report file is too short")
            if f"REVIEWER_ROLE: {role}" not in report_text:
                reviewer_issues.append(f"{reviewer_id}: report file missing reviewer role token")
            if f"TASK_ID: {task_id}" not in report_text:
                reviewer_issues.append(f"{reviewer_id}: report file missing task id token")
            if not concrete_review_locator_present(report_text):
                reviewer_issues.append(f"{reviewer_id}: report must cite a concrete section, line, table, figure, claim, or artifact")
            if not adversarial_review_terms_present(report_text):
                reviewer_issues.append(f"{reviewer_id}: report must include a risk, limitation, rival, robustness, falsification, or desk-reject concern")
        reviewed_inputs = reviewer.get("reviewed_inputs")
        if not isinstance(reviewed_inputs, list) or not {"manuscript/manuscript-draft.md", "verify/manuscript-verification.json", "citation/claim-source-map.json"}.issubset(set(reviewed_inputs)):
            reviewer_issues.append(f"{reviewer_id}: reviewed_inputs must include manuscript, verification, and claim map")
        score_vector = reviewer.get("score_vector")
        if not isinstance(score_vector, dict) or not score_vector:
            reviewer_issues.append(f"{reviewer_id}: score_vector missing")
        decision = str(reviewer.get("decision", "")).strip()
        if decision not in {"ACCEPT", "MINOR_REVISION", "PROCEED_TO_FINAL_ASSEMBLY"}:
            reviewer_issues.append(f"{reviewer_id}: blocking decision {decision}")
        if not isinstance(reviewer.get("findings"), list):
            reviewer_issues.append(f"{reviewer_id}: findings must be a list")
        # Improvement A (2026-05-03) — per-reviewer contribution_locator.
        # Each reviewer must quote 1+ verbatim sentences from the manuscript
        # that constitute the contribution, with clarity/specificity scores.
        # Catches manuscripts where the contribution is buried, vacuous, or
        # decorative — a class of failure mechanical coverage gates miss.
        locator = reviewer.get("contribution_locator")
        if not isinstance(locator, dict):
            reviewer_issues.append(f"{reviewer_id}: contribution_locator missing or not an object")
        else:
            sentences = locator.get("sentences")
            if not isinstance(sentences, list) or not sentences:
                reviewer_issues.append(f"{reviewer_id}: contribution_locator.sentences must be a nonempty list")
            else:
                for si, sent in enumerate(sentences):
                    if not isinstance(sent, str) or len(sent.split()) < 10:
                        reviewer_issues.append(f"{reviewer_id}: contribution_locator.sentences[{si}] must be a string with at least 10 words")
                        break
            for sf in ("clarity_score", "specificity_score"):
                sval = locator.get(sf)
                try:
                    snum = float(sval)
                    if snum < 7 or snum > 10:
                        reviewer_issues.append(f"{reviewer_id}: contribution_locator.{sf} must be a number in [7,10]")
                except Exception:
                    reviewer_issues.append(f"{reviewer_id}: contribution_locator.{sf} missing or nonnumeric")
        # Improvement B (2026-05-03) — per-reviewer rival_adjudication.
        # Each reviewer reports rivals named in the lit review and which
        # the discussion fails to adjudicate. Cross-reviewer aggregate
        # below blocks when >=2 reviewers agree on a missing adjudication.
        rival = reviewer.get("rival_adjudication")
        if not isinstance(rival, dict):
            reviewer_issues.append(f"{reviewer_id}: rival_adjudication missing or not an object")
        else:
            for rf in ("rivals_in_lit_review", "missing_adjudications"):
                rv = rival.get(rf)
                if not isinstance(rv, list):
                    reviewer_issues.append(f"{reviewer_id}: rival_adjudication.{rf} must be a list")
            aqs = rival.get("adjudication_quality_score")
            try:
                aqs_num = float(aqs)
                if aqs_num < 7 or aqs_num > 10:
                    reviewer_issues.append(f"{reviewer_id}: rival_adjudication.adjudication_quality_score must be a number in [7,10]")
            except Exception:
                reviewer_issues.append(f"{reviewer_id}: rival_adjudication.adjudication_quality_score missing or nonnumeric")
    for i in range(len(reviewer_texts)):
        id_a, role_a, text_a = reviewer_texts[i]
        for j in range(i + 1, len(reviewer_texts)):
            id_b, role_b, text_b = reviewer_texts[j]
            similarity = token_set_similarity(text_a, text_b)
            if similarity >= 0.78:
                reviewer_issues.append(
                    f"{id_a}/{id_b}: reviewer reports are too similar for independent role-specific review "
                    f"(token-set similarity={similarity:.2f}; roles={role_a},{role_b})"
                )
    # Improvement A (2026-05-03) — cross-reviewer Jaccard consensus.
    # Load-bearing check: at least one pair of reviewers must
    # independently quote contribution sentences with Jaccard token
    # overlap >= threshold. If no pair agrees, the contribution is
    # not independently locatable and the manuscript fails Phase 18.
    contribution_locator_threshold = 0.7
    def _locator_tokens(s):
        return set(re.sub(r"[^\w\s]", " ", s.lower()).split())
    def _jaccard(a, b):
        ta = _locator_tokens(a)
        tb = _locator_tokens(b)
        if not ta or not tb:
            return 0.0
        return len(ta & tb) / len(ta | tb)
    all_sentences = []
    for r in reviewers:
        if not isinstance(r, dict):
            continue
        rid = str(r.get("reviewer_id", "")).strip()
        loc = r.get("contribution_locator", {})
        if not isinstance(loc, dict):
            continue
        sents = loc.get("sentences", [])
        if not isinstance(sents, list):
            continue
        for s in sents:
            if isinstance(s, str) and s.strip():
                all_sentences.append((rid, s))
    consensus_pairs = []
    for i in range(len(all_sentences)):
        r1, s1 = all_sentences[i]
        for j in range(i + 1, len(all_sentences)):
            r2, s2 = all_sentences[j]
            if r1 == r2:
                continue
            if _jaccard(s1, s2) >= contribution_locator_threshold:
                pair = tuple(sorted([r1, r2]))
                if pair not in consensus_pairs:
                    consensus_pairs.append(pair)
    if not consensus_pairs and any(isinstance(r, dict) for r in reviewers):
        reviewer_issues.append(
            f"contribution_locator_consensus: no reviewer pair shares a contribution sentence "
            f"(jaccard threshold=0.7); manuscript contribution is not independently locatable across the panel"
        )
    # Improvement B (2026-05-03) — rival_adjudication aggregate.
    # Block when >=2 reviewers name the same rival in the lit review AND
    # >=2 reviewers flag it as un-adjudicated in the discussion.
    def _norm_rival(s):
        return re.sub(r"\s+", " ", s.lower().strip())
    rivals_named_count = {}
    rivals_missing_count = {}
    for r in reviewers:
        if not isinstance(r, dict):
            continue
        rival_obj = r.get("rival_adjudication", {})
        if not isinstance(rival_obj, dict):
            continue
        for rname in (rival_obj.get("rivals_in_lit_review") or []):
            if isinstance(rname, str) and rname.strip():
                key = _norm_rival(rname)
                rivals_named_count[key] = rivals_named_count.get(key, 0) + 1
        for rname in (rival_obj.get("missing_adjudications") or []):
            if isinstance(rname, str) and rname.strip():
                key = _norm_rival(rname)
                rivals_missing_count[key] = rivals_missing_count.get(key, 0) + 1
    unaddressed_rivals = sorted([
        rname for rname, named in rivals_named_count.items()
        if named >= 2 and rivals_missing_count.get(rname, 0) >= 2
    ])
    if unaddressed_rivals:
        reviewer_issues.append(
            f"rival_consensus: {len(unaddressed_rivals)} rival(s) named by >=2 reviewers and "
            f"flagged un-adjudicated by >=2 reviewers: " + ", ".join(unaddressed_rivals[:5])
        )
    if reviewer_issues:
        fail("FAIL: Phase 18 reviewer report coverage is invalid", reviewer_issues[:30])
    required_dimensions = [
        "contribution",
        "rq_answer",
        "argument_coherence",
        "theory_results_integration",
        "limitation_candor",
        "journal_fit",
        "abstract_intro_discussion_consistency",
        "substantive_conclusion_support",
        "prose_quality",
        "reviewer_consensus",
    ]
    scores = quality.get("dimension_scores")
    if not isinstance(scores, dict):
        fail("FAIL: Phase 17 dimension_scores must be an object")
    score_values = []
    score_issues = []
    for dimension in required_dimensions:
        value = scores.get(dimension)
        if isinstance(value, dict):
            value = value.get("score")
        try:
            numeric = float(value)
        except Exception:
            score_issues.append(f"{dimension}: score missing or nonnumeric")
            continue
        score_values.append(numeric)
        if numeric < 7:
            score_issues.append(f"{dimension}: score below 7")
        if numeric > 10 or numeric < 0:
            score_issues.append(f"{dimension}: score outside 0-10")
    if score_issues:
        fail("FAIL: Phase 17 quality dimension scores do not meet threshold", score_issues)
    mean_score = sum(score_values) / len(score_values)
    policy = quality.get("threshold_policy")
    if not isinstance(policy, dict):
        fail("FAIL: Phase 17 threshold_policy must be an object")
    if float(policy.get("min_dimension_score", 7)) < 7 or float(policy.get("mean_score_min", 8)) < 8:
        fail("FAIL: Phase 17 threshold_policy is weaker than the required gate")
    if mean_score < 8:
        fail("FAIL: Phase 17 mean quality score must be at least 8", [f"mean_score={mean_score:.2f}"])
    blockers = policy.get("non_overridable_blockers")
    if blockers not in ([], None):
        fail("FAIL: Phase 17 non_overridable_blockers must be empty for PASS")
    matrix = quality.get("severity_confidence_matrix")
    if not isinstance(matrix, list):
        fail("FAIL: Phase 17 severity_confidence_matrix must be a list")
    blocking_matrix = []
    for idx, item in enumerate(matrix):
        if not isinstance(item, dict):
            blocking_matrix.append(f"matrix[{idx}] is not an object")
            continue
        severity = str(item.get("severity", "")).strip()
        status = str(item.get("status", "")).strip().lower()
        if severity in {"CRITICAL", "MAJOR"} and status not in {"resolved", "not_applicable"}:
            blocking_matrix.append(f"{item.get('issue_id', idx)}: unresolved {severity}")
    if blocking_matrix:
        fail("FAIL: Phase 17 severity-confidence matrix has unresolved major or critical items", blocking_matrix)
    decision = quality.get("decision")
    if not isinstance(decision, dict):
        fail("FAIL: Phase 17 decision must be an object")
    if decision.get("editorial_recommendation") != "PROCEED_TO_FINAL_ASSEMBLY":
        fail("FAIL: Phase 17 decision must be PROCEED_TO_FINAL_ASSEMBLY for PASS")
    if quality.get("fix_checklist", {}).get("critical_fixes") not in ([], None):
        fail("FAIL: Phase 17 fix_checklist.critical_fixes must be empty for PASS")
    if quality.get("fix_checklist", {}).get("route_back") not in ([], None):
        fail("FAIL: Phase 17 fix_checklist.route_back must be empty for PASS")
    if quality.get("route_back_phase") not in (None, ""):
        fail("FAIL: Phase 17 route_back_phase must be empty for PASS")
    if quality.get("ready_for_phase_19") is not True:
        fail("FAIL: Phase 18 ready_for_phase_19 must be true")
    quality_md = quality_md_path.read_text(errors="ignore")
    md_lower = quality_md.lower()
    required_terms = ["overall verdict", "dimension scores", "reviewer consensus", "severity confidence", "route back", "proceed to final assembly"]
    missing_terms = [term for term in required_terms if term not in md_lower]
    if missing_terms:
        fail("FAIL: Phase 17 markdown summary is missing required quality-gate sections", missing_terms)
    placeholder_pattern = re.compile(
        r"\[(paper title|title|journal|insert [^\]]+|add [^\]]+)\]"
        r"|\b(TBD|TODO|XXXX+|to be determined|Author\s+[0-9X])\b",
        re.IGNORECASE
    )
    if placeholder_pattern.search(quality_md) or placeholder_pattern.search(json.dumps(quality)):
        fail("FAIL: Phase 17 quality report contains placeholder text")
    if word_count(quality_md) < 100:
        fail("FAIL: Phase 17 markdown summary is too short")
    if "proceed_to_final_assembly" not in md_lower and "proceed to final assembly" not in md_lower:
        fail("FAIL: Phase 17 markdown summary does not match JSON PASS decision")

if phase_id == "19":
    manuscript_path = proj / "manuscript" / "manuscript-draft.md"
    draft_manifest_path = proj / "manuscript" / "draft-manifest.json"
    quality_path = proj / "quality" / "manuscript-quality.json"
    quality_md_path = proj / "quality" / "manuscript-quality.md"
    references_path = proj / "citation" / "references.bib"
    citation_audit_path = proj / "citation" / "citation-audit.json"
    claim_map_path = proj / "citation" / "claim-source-map.json"
    ethics_path = proj / "ethics" / "ethics-open-science.json"
    replication_path = proj / "replication-package" / "replication-report.json"
    final_md_path = proj / "final" / "manuscript-final.md"
    final_docx_path = proj / "final" / "manuscript-final.docx"
    final_tex_path = proj / "final" / "manuscript-final.tex"
    final_pdf_path = proj / "final" / "manuscript-final.pdf"
    final_manifest_path = proj / "final" / "final-manifest.json"
    latest_final_path = proj / "final" / "LATEST.txt"
    required_inputs = (
        manuscript_path,
        draft_manifest_path,
        quality_path,
        quality_md_path,
        references_path,
        citation_audit_path,
        claim_map_path,
        ethics_path,
        replication_path,
    )
    for required_path in required_inputs:
        if not required_path.exists():
            fail(f"FAIL: Phase 18 missing required input {required_path.relative_to(proj)}")
    try:
        draft_manifest = json.loads(draft_manifest_path.read_text())
        quality = json.loads(quality_path.read_text())
        citation_audit = json.loads(citation_audit_path.read_text())
        claim_map = json.loads(claim_map_path.read_text())
        ethics = json.loads(ethics_path.read_text())
        replication = json.loads(replication_path.read_text())
        manifest = json.loads(final_manifest_path.read_text())
        blueprint = json.loads((proj / "manuscript" / "manuscript-blueprint.json").read_text())
    except Exception as exc:
        fail(f"FAIL: Phase 18 final manifest or inputs are not valid JSON: {exc}")
    if draft_manifest.get("ready_for_phase_14") is not True:
        fail("FAIL: Phase 19 requires a passing Phase 13 draft manifest")
    if quality.get("verdict") != "PASS" or quality.get("ready_for_phase_19") is not True:
        fail("FAIL: Phase 19 requires a passing Phase 18 quality report")
    if citation_audit.get("verdict") != "PASS" or citation_audit.get("ready_for_phase_16") is not True:
        fail("FAIL: Phase 19 requires a passing Phase 15 citation audit")
    if ethics.get("verdict") != "PASS" or ethics.get("ready_for_phase_17") is not True:
        fail("FAIL: Phase 19 requires a passing Phase 16 ethics/open-science report")
    if replication.get("verdict") != "PASS" or replication.get("ready_for_phase_18") is not True:
        fail("FAIL: Phase 19 requires a passing Phase 17 replication report")
    required = (
        "verdict",
        "degraded",
        "source_phase",
        "assembly_engine",
        "journal_profile_resolution",
        "version_id",
        "created_at_utc",
        "source_hashes",
        "source_manuscript_path",
        "source_manuscript_hash",
        "output_paths",
        "versioned_output_paths",
        "output_hashes",
        "versioned_output_hashes",
        "same_source",
        "format_generation",
        "content_checks",
        "reader_facing_language",
        "citation_checks",
        "declaration_checks",
        "declaration_visibility",
        "findings",
        "fix_checklist",
        "route_back_phase",
        "ready_for_phase_20",
    )
    absent = [field for field in required if field not in manifest]
    if absent:
        fail("FAIL: Phase 18 final manifest missing required fields", absent)
    findings = manifest.get("findings")
    if not isinstance(findings, list):
        fail("FAIL: Phase 18 findings must be a list")
    allowed_categories = {
        "manuscript_source": "13",
        "citation_bibliography": "15",
        "quality_stale": "18",
        "ethics_declarations": "16",
        "replication_package": "17",
        "format_generation": "19",
        "same_source": "19",
        "manifest": "19",
        "content_placeholder": "19",
        "reader_facing_language": "19",
        "declaration_visibility": "16",
    }
    if manifest.get("verdict") != "PASS":
        if manifest.get("verdict") != "FAIL":
            fail(f"FAIL: Phase 18 top-level verdict must be PASS or FAIL, got {manifest.get('verdict')}")
        if not findings:
            fail("FAIL: Phase 18 FAIL report must include nonempty findings")
        finding_issues = []
        route_phases = set()
        critical_or_major = 0
        seen_findings = set()
        for idx, finding in enumerate(findings):
            if not isinstance(finding, dict):
                finding_issues.append(f"findings[{idx}] is not an object")
                continue
            finding_id = str(finding.get("finding_id", "")).strip()
            if not finding_id or finding_id in seen_findings:
                finding_issues.append(f"findings[{idx}].finding_id missing or duplicate")
            seen_findings.add(finding_id)
            severity = str(finding.get("severity", "")).strip()
            if severity not in {"CRITICAL", "MAJOR", "MINOR", "WARNING"}:
                finding_issues.append(f"{finding_id}: severity invalid")
            if severity in {"CRITICAL", "MAJOR"}:
                critical_or_major += 1
            category = str(finding.get("category", "")).strip()
            expected_phase = allowed_categories.get(category)
            if expected_phase is None:
                finding_issues.append(f"{finding_id}: category invalid")
            owner_phase = str(finding.get("owner_phase", "")).strip()
            route_back_phase = str(finding.get("route_back_phase", "")).strip()
            if expected_phase and owner_phase != expected_phase:
                finding_issues.append(f"{finding_id}: owner_phase must be {expected_phase} for {category}")
            if expected_phase and route_back_phase != expected_phase:
                finding_issues.append(f"{finding_id}: route_back_phase must be {expected_phase} for {category}")
            if route_back_phase:
                route_phases.add(route_back_phase)
            if finding.get("detected_by") not in {"final-assembly", "pandoc", "format-check", "manifest-check", "citation-check", "reader-language-check", "declaration-check"}:
                finding_issues.append(f"{finding_id}: detected_by must be a Phase 18 checker")
            affected = finding.get("affected_artifacts")
            if not isinstance(affected, list) or not affected or any(not str(item).strip() for item in affected):
                finding_issues.append(f"{finding_id}: affected_artifacts must be a nonempty list")
            if not str(finding.get("required_fix", "")).strip():
                finding_issues.append(f"{finding_id}: required_fix missing")
            if finding.get("status") != "open":
                finding_issues.append(f"{finding_id}: status must be open")
        fix_checklist = manifest.get("fix_checklist")
        if not isinstance(fix_checklist, dict):
            finding_issues.append("fix_checklist must be an object")
        else:
            if critical_or_major and not fix_checklist.get("critical_fixes"):
                finding_issues.append("fix_checklist.critical_fixes must be nonempty for CRITICAL/MAJOR findings")
            route_back = fix_checklist.get("route_back")
            if not isinstance(route_back, list) or not route_back:
                finding_issues.append("fix_checklist.route_back must be nonempty for FAIL")
        top_route = str(manifest.get("route_back_phase", "")).strip()
        if not top_route:
            finding_issues.append("route_back_phase must be set for FAIL")
        elif route_phases and top_route != str(min(int(phase) for phase in route_phases)):
            finding_issues.append("route_back_phase must be the earliest finding route_back_phase")
        if manifest.get("source_phase") != "19":
            finding_issues.append("source_phase must be 19")
        if manifest.get("ready_for_phase_20") is not False:
            finding_issues.append("ready_for_phase_20 must be false for FAIL")
        if finding_issues:
            fail("FAIL: Phase 18 FAIL report is malformed", finding_issues)
        fail("FAIL: Phase 19 final assembly found unresolved issues; route back before Phase 20", [f"route_back_phase={top_route}"] + [f"{f.get('finding_id')}: {f.get('required_fix')}" for f in findings if isinstance(f, dict)])

    if manifest.get("degraded") is not False:
        fail("FAIL: Phase 19 degraded must be false")
    if manifest.get("source_phase") != "19":
        fail("FAIL: Phase 19 source_phase must be 19")
    final_journal_resolution = manifest.get("journal_profile_resolution")
    if final_journal_resolution != blueprint.get("journal_profile_resolution"):
        fail("FAIL: Phase 19 final manifest journal_profile_resolution must match the approved blueprint")
    resolution_issues = validate_journal_profile_resolution(final_journal_resolution, blueprint.get("target_journal"), "Phase 19")
    if resolution_issues:
        fail("FAIL: Phase 19 final manifest journal_profile_resolution is invalid", resolution_issues)
    if findings:
        fail("FAIL: Phase 18 PASS manifest must have empty findings")
    engine = manifest.get("assembly_engine")
    if not isinstance(engine, dict) or not str(engine.get("name", "")).strip():
        fail("FAIL: Phase 18 assembly_engine must identify the renderer")
    if engine.get("name") != "pandoc":
        fail("FAIL: Phase 18 assembly_engine.name must be pandoc")
    if engine.get("mode") != "same-source-final-assembly":
        fail("FAIL: Phase 18 assembly_engine.mode must be same-source-final-assembly")
    if engine.get("fallback_used") is not False:
        fail("FAIL: Phase 18 assembly_engine.fallback_used must be false")
    version_id = str(manifest.get("version_id", "")).strip()
    if not re.match(r"^\d{4}-\d{2}-\d{2}T\d{6}Z-v\d{3}$", version_id):
        fail("FAIL: Phase 18 version_id must match YYYY-MM-DDTHHMMSSZ-vNNN")
    created_at = str(manifest.get("created_at_utc", "")).strip()
    if not re.match(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$", created_at):
        fail("FAIL: Phase 18 created_at_utc must match YYYY-MM-DDTHH:MM:SSZ")
    expected_created = f"{version_id[:13]}:{version_id[13:15]}:{version_id[15:17]}Z"
    if created_at != expected_created:
        fail("FAIL: Phase 18 created_at_utc must match version_id timestamp")
    if not latest_final_path.exists() or latest_final_path.read_text(errors="ignore") != f"{version_id}\n":
        fail("FAIL: Phase 18 final/LATEST.txt must point to the active version_id")
    source_hashes = manifest.get("source_hashes")
    if not isinstance(source_hashes, dict):
        fail("FAIL: Phase 18 source_hashes must be an object")
    expected_hashes = {
        "manuscript": sha256(manuscript_path),
        "draft_manifest": sha256(draft_manifest_path),
        "quality_report": sha256(quality_path),
        "quality_markdown": sha256(quality_md_path),
        "references_bib": sha256(references_path),
        "citation_audit": sha256(citation_audit_path),
        "claim_source_map": sha256(claim_map_path),
        "ethics_open_science": sha256(ethics_path),
        "replication_report": sha256(replication_path),
    }
    stale_sources = [
        f"{key} mismatch"
        for key, expected in expected_hashes.items()
        if source_hashes.get(key) != expected
    ]
    if stale_sources:
        fail("FAIL: Phase 18 source_hashes are stale", stale_sources)
    if manifest.get("source_manuscript_path") != "manuscript/manuscript-draft.md":
        fail("FAIL: Phase 18 source_manuscript_path must be manuscript/manuscript-draft.md")
    if manifest.get("source_manuscript_hash") != sha256(manuscript_path):
        fail("FAIL: Phase 18 source_manuscript_hash is stale")
    output_paths = manifest.get("output_paths")
    expected_outputs = {
        "md": "final/manuscript-final.md",
        "docx": "final/manuscript-final.docx",
        "tex": "final/manuscript-final.tex",
        "pdf": "final/manuscript-final.pdf",
    }
    if output_paths != expected_outputs:
        fail("FAIL: Phase 18 output_paths must use canonical final/manuscript-final stem")
    output_hashes = manifest.get("output_hashes")
    if not isinstance(output_hashes, dict):
        fail("FAIL: Phase 18 output_hashes must be an object")
    versioned_output_paths = manifest.get("versioned_output_paths")
    expected_versioned_outputs = {
        "md": f"final/versions/{version_id}/manuscript-final-{version_id}.md",
        "docx": f"final/versions/{version_id}/manuscript-final-{version_id}.docx",
        "tex": f"final/versions/{version_id}/manuscript-final-{version_id}.tex",
        "pdf": f"final/versions/{version_id}/manuscript-final-{version_id}.pdf",
        "manifest": f"final/versions/{version_id}/final-manifest-{version_id}.json",
    }
    if versioned_output_paths != expected_versioned_outputs:
        fail("FAIL: Phase 18 versioned_output_paths must use final/versions/<version_id>/ with versioned filenames")
    versioned_output_hashes = manifest.get("versioned_output_hashes")
    if not isinstance(versioned_output_hashes, dict):
        fail("FAIL: Phase 18 versioned_output_hashes must be an object")
    output_file_map = {
        "md": final_md_path,
        "docx": final_docx_path,
        "tex": final_tex_path,
        "pdf": final_pdf_path,
    }
    file_issues = []
    for ext, path in output_file_map.items():
        if not path.exists() or not path.is_file():
            file_issues.append(f"{ext}: missing")
            continue
        if path.stat().st_size < (20 if ext == "md" else 10):
            file_issues.append(f"{ext}: file too small")
            continue
        if output_hashes.get(ext) != sha256(path):
            file_issues.append(f"{ext}: sha256 mismatch")
    if file_issues:
        fail("FAIL: Phase 18 output files or hashes are invalid", file_issues)
    version_issues = []
    for ext in ("md", "docx", "tex", "pdf"):
        rel = versioned_output_paths.get(ext)
        path = proj / rel
        if not path.exists() or not path.is_file():
            version_issues.append(f"{ext}: versioned copy missing")
            continue
        version_hash = sha256(path)
        if versioned_output_hashes.get(ext) != version_hash:
            version_issues.append(f"{ext}: versioned sha256 mismatch")
        if version_hash != output_hashes.get(ext):
            version_issues.append(f"{ext}: versioned hash differs from canonical hash")
    version_manifest_rel = versioned_output_paths.get("manifest")
    version_manifest_path = proj / version_manifest_rel
    if not version_manifest_path.exists() or not version_manifest_path.is_file():
        version_issues.append("manifest: versioned manifest copy missing")
    elif versioned_output_hashes.get("manifest") != "SELF_REFERENTIAL":
        version_issues.append("manifest: versioned manifest hash must be SELF_REFERENTIAL")
    if version_issues:
        fail("FAIL: Phase 18 versioned final outputs are invalid", version_issues)
    same_source = manifest.get("same_source")
    if not isinstance(same_source, dict):
        fail("FAIL: Phase 18 same_source must be an object")
    final_md_hash = sha256(final_md_path)
    if same_source.get("source_md_path") != "final/manuscript-final.md":
        fail("FAIL: Phase 18 same_source.source_md_path must be final/manuscript-final.md")
    if same_source.get("source_md_sha256") != final_md_hash:
        fail("FAIL: Phase 18 same_source.source_md_sha256 mismatch")
    if same_source.get("shared_stem") != "final/manuscript-final":
        fail("FAIL: Phase 18 same_source.shared_stem must be final/manuscript-final")
    if same_source.get("all_formats_from_source_md") is not True:
        fail("FAIL: Phase 18 same_source must prove all formats came from final Markdown")
    generation = manifest.get("format_generation")
    if not isinstance(generation, dict):
        fail("FAIL: Phase 18 format_generation must be an object")
    generation_issues = []
    for ext in ("docx", "tex", "pdf"):
        record = generation.get(ext)
        if not isinstance(record, dict):
            generation_issues.append(f"{ext}: generation record missing")
            continue
        if record.get("status") != "PASS":
            generation_issues.append(f"{ext}: status must be PASS")
        if record.get("source_md_sha256") != final_md_hash:
            generation_issues.append(f"{ext}: source_md_sha256 mismatch")
        command = str(record.get("command", "")).strip()
        if not command:
            generation_issues.append(f"{ext}: command missing")
        else:
            expected_output = f"final/manuscript-final.{ext}"
            if not command_invokes_pandoc(command):
                generation_issues.append(f"{ext}: command must invoke pandoc")
            if "final/manuscript-final.md" not in command:
                generation_issues.append(f"{ext}: command must use final/manuscript-final.md as source")
            if expected_output not in command:
                generation_issues.append(f"{ext}: command must write {expected_output}")
    if generation_issues:
        fail("FAIL: Phase 18 format_generation is incomplete", generation_issues)
    try:
        with zipfile.ZipFile(final_docx_path) as zf:
            names = set(zf.namelist())
            if "word/document.xml" not in names:
                fail("FAIL: Phase 18 DOCX is missing word/document.xml")
    except Exception as exc:
        fail(f"FAIL: Phase 18 DOCX is not a valid docx zip: {exc}")
    tex_text = final_tex_path.read_text(errors="ignore")
    if "\\documentclass" not in tex_text or "\\begin{document}" not in tex_text:
        fail("FAIL: Phase 18 TeX output does not look like a standalone LaTeX document")
    pdf_bytes = final_pdf_path.read_bytes()
    if not pdf_bytes.startswith(b"%PDF") or b"%%EOF" not in pdf_bytes[-2048:]:
        fail("FAIL: Phase 18 PDF output does not look like a valid PDF")
    final_md = final_md_path.read_text(errors="ignore")
    md_lower = final_md.lower()
    final_sections = markdown_sections(final_md)
    final_keyword_issues = keyword_placement_issues(final_md)
    if final_keyword_issues:
        fail("FAIL: Phase 19 final markdown has invalid front-matter keyword placement", final_keyword_issues)
    placeholder_pattern = re.compile(
        r"\[(paper title|title|journal|insert [^\]]+|add [^\]]+|citation needed)\]"
        r"|\b(TBD|TODO|XXXX+|to be determined|SOURCE NEEDED|UNVERIFIED)\b",
        re.IGNORECASE
    )
    if placeholder_pattern.search(final_md) or placeholder_pattern.search(json.dumps(manifest)):
        fail("FAIL: Phase 18 final outputs contain placeholder text")
    if "the locked artifact snapshot" in final_md.lower():
        fail("FAIL: Phase 19 final markdown contains placeholder artifact targets")
    if has_raw_citekeys(final_md):
        fail("FAIL: Phase 19 final markdown contains raw citation syntax")
    final_jargon_hits = reader_workflow_jargon_hits(final_md)
    if final_jargon_hits:
        fail("FAIL: Phase 19 final markdown exposes internal workflow language", final_jargon_hits[:25])
    final_registry_table_hits = registry_like_table_display_hits(final_md)
    if final_registry_table_hits:
        fail("FAIL: Phase 19 final markdown exposes registry/model-ladder tables as reader-facing evidence", final_registry_table_hits[:25])
    final_coverage = draft_manifest.get("locked_result_coverage")
    if quantitative_empirical_regression_table_required(final_md, draft_manifest, blueprint, claim_map):
        expected_regression_labels = [
            str(item.get("display_label", "")).strip()
            for item in final_coverage
            if isinstance(item, dict)
            and item.get("used_in_manuscript") is True
            and str(item.get("artifact_role", "")).strip() in REGRESSION_TABLE_ROLES
            and str(item.get("display_status", "")).strip() != "journal_exempt"
            and str(item.get("display_label", "")).strip()
        ] if isinstance(final_coverage, list) else []
        if not expected_regression_labels:
            fail("FAIL: Phase 19 quantitative final manuscript has no canonical regression table recorded in Phase 13 coverage")
        missing_regression_labels = [label for label in expected_regression_labels if label not in final_md]
        if missing_regression_labels:
            fail("FAIL: Phase 19 final markdown dropped canonical regression table labels", missing_regression_labels)
    visible_final = visible_markdown_text(final_md).lower()
    final_declaration_patterns = {
        "data availability": r"\b(data availability|availability of data|data and code availability)\b",
        "ethics or human-subjects status": r"\b(ethics|irb|human subjects|human-subjects|institutional review)\b",
        "ai/tool use": r"\b(ai use|artificial intelligence|large language model|language model|tool use disclosure|ai disclosure)\b",
        "conflict of interest": r"\b(conflict of interest|conflicts of interest|competing interests|coi)\b",
    }
    missing_final_declarations = [
        label
        for label, pattern in final_declaration_patterns.items()
        if not re.search(pattern, visible_final)
    ]
    if missing_final_declarations:
        fail("FAIL: Phase 19 final markdown is missing visible declaration sections or statements", missing_final_declarations)
    content_checks = manifest.get("content_checks")
    if not isinstance(content_checks, dict):
        fail("FAIL: Phase 18 content_checks must be an object")
    final_structure = blueprint.get("journal_structure", {}) if isinstance(blueprint.get("journal_structure"), dict) else {}
    final_display_architecture = blueprint.get("display_architecture", {}) if isinstance(blueprint.get("display_architecture"), dict) else {}
    if editable_text_policy_forbids_raw_html_tables(final_display_architecture):
        final_html_table_hits = raw_html_table_hits(final_md)
        if final_html_table_hits:
            fail(
                "FAIL: Phase 19 final markdown contains raw HTML tables despite editable-text table policy",
                final_html_table_hits[:10],
            )
    final_theory_mode = str(final_structure.get("theory_presentation", "")).strip()
    final_methods_heading = norm_text(final_structure.get("methods_section_label", "")) or "data and methods"
    required_sections = ["abstract", "introduction", final_methods_heading, "results", "discussion", "references"]
    if final_theory_mode == "standalone_literature_theory":
        required_sections.insert(2, "literature review and theory")
    elif final_theory_mode == "theory_section":
        required_sections.insert(2, "theory")
    elif final_theory_mode == "background_section":
        required_sections.insert(2, "background")
    if str(blueprint.get("discussion_mode", "")).strip() == "split":
        required_sections.append("conclusion")
    final_heading_order = visible_heading_sequence(final_md)
    missing_sections = [section for section in required_sections if section not in final_heading_order]
    if missing_sections:
        fail("FAIL: Phase 18 final markdown missing required manuscript sections", missing_sections)
    expected_sequence = [section for section in required_sections if section != "references"]
    if not sequence_contains_in_order(final_heading_order, expected_sequence):
        fail("FAIL: Phase 19 final markdown section order does not match the approved journal structure", [f"expected_order={expected_sequence}", f"actual_headings={final_heading_order}"])
    refs_match = re.search(r"(?ims)^#{1,3}\s+references\s*$([\s\S]*)", final_md)
    if not refs_match:
        fail("FAIL: Phase 19 final markdown must include a rendered References section")
    refs_body = refs_match.group(1)
    if references_looks_like_key_dump(refs_body):
        fail("FAIL: Phase 19 final markdown References section looks like a citekey dump rather than formatted references")
    if content_checks.get("required_sections_present") is not True or content_checks.get("placeholder_free") is not True:
        fail("FAIL: Phase 18 content_checks must confirm sections and placeholder-free text")
    required_content_fields = (
        "journal_structure_applied",
        "journal_display_architecture_applied",
        "section_sequence_matches_blueprint",
        "table_placement_policy_applied",
        "figure_placement_policy_applied",
        "table_rendering_mode_applied",
        "figure_rendering_mode_applied",
        "descriptive_table_requirement_satisfied",
        "display_cap_respected",
        "main_text_table_count",
        "main_text_figure_count",
        "main_text_display_count",
    )
    missing_content_fields = [field for field in required_content_fields if field not in content_checks]
    if missing_content_fields:
        fail("FAIL: Phase 18 content_checks missing journal-specific display fields", missing_content_fields)
    if content_checks.get("journal_structure_applied") is not True:
        fail("FAIL: Phase 18 content_checks must confirm journal_structure_applied")
    if content_checks.get("journal_display_architecture_applied") is not True:
        fail("FAIL: Phase 18 content_checks must confirm journal_display_architecture_applied")
    if content_checks.get("section_sequence_matches_blueprint") is not True:
        fail("FAIL: Phase 18 content_checks must confirm section_sequence_matches_blueprint")
    if content_checks.get("table_placement_policy_applied") != final_display_architecture.get("table_placement_policy"):
        fail("FAIL: Phase 18 content_checks.table_placement_policy_applied must match blueprint display_architecture")
    if content_checks.get("figure_placement_policy_applied") != final_display_architecture.get("figure_placement_policy"):
        fail("FAIL: Phase 18 content_checks.figure_placement_policy_applied must match blueprint display_architecture")
    if content_checks.get("table_rendering_mode_applied") != final_display_architecture.get("table_rendering_mode"):
        fail("FAIL: Phase 18 content_checks.table_rendering_mode_applied must match blueprint display_architecture")
    if content_checks.get("figure_rendering_mode_applied") != final_display_architecture.get("figure_rendering_mode"):
        fail("FAIL: Phase 18 content_checks.figure_rendering_mode_applied must match blueprint display_architecture")
    citation_checks = manifest.get("citation_checks")
    if not isinstance(citation_checks, dict):
        fail("FAIL: Phase 18 citation_checks must be an object")
    if citation_checks.get("references_bib_used") is not True or citation_checks.get("unresolved_citations") not in (0, "0"):
        fail("FAIL: Phase 18 citation_checks must confirm bibliography use and zero unresolved citations")
    if claim_map.get("unsupported_count", 0) not in (0, "0"):
        fail("FAIL: Phase 18 cannot assemble with unsupported claims")
    declaration_checks = manifest.get("declaration_checks")
    if not isinstance(declaration_checks, dict):
        fail("FAIL: Phase 18 declaration_checks must be an object")
    required_declarations = ["ethics_statement", "data_availability", "ai_use_disclosure", "coi_statement"]
    missing_declarations = [key for key in required_declarations if declaration_checks.get(key) not in (True, "not_applicable")]
    if missing_declarations:
        fail("FAIL: Phase 18 declaration_checks missing required declarations", missing_declarations)
    reader_language = manifest.get("reader_facing_language")
    if not isinstance(reader_language, dict):
        fail("FAIL: Phase 19 reader_facing_language must be an object")
    if reader_language.get("workflow_jargon_hits") not in (0, "0") or reader_language.get("status") != "PASS":
        fail("FAIL: Phase 19 reader_facing_language must report zero workflow jargon hits and PASS status")
    declaration_visibility = manifest.get("declaration_visibility")
    if not isinstance(declaration_visibility, dict):
        fail("FAIL: Phase 19 declaration_visibility must be an object")
    if declaration_visibility.get("missing_required_declarations") not in ([], None) or declaration_visibility.get("status") != "PASS":
        fail("FAIL: Phase 19 declaration_visibility must report all required declarations visible")
    final_output_root = final_md_path.parent
    broken_targets = []
    for match in re.finditer(r"\[[^\]]+\]\(([^)]+)\)", final_md):
        target = match.group(1).strip()
        if not target or target.startswith(("http://", "https://", "mailto:", "#")):
            continue
        resolved = (final_output_root / target).resolve()
        try:
            resolved.relative_to(proj.resolve())
        except Exception:
            broken_targets.append(target)
            continue
        if not resolved.exists():
            broken_targets.append(target)
    if broken_targets:
        fail("FAIL: Phase 19 final markdown contains broken relative targets", broken_targets[:25])
    required_disclosures = [
        str(item).strip().lower()
        for item in blueprint.get("required_disclosures", [])
        if str(item).strip()
    ]
    missing_disclosures = [item for item in required_disclosures if not disclosure_semantically_covered(item, md_lower)]
    if missing_disclosures:
        fail("FAIL: Phase 19 final markdown dropped required blueprint disclosures", missing_disclosures[:20])
    expected_reader_figures = [
        item.get("source_path")
        for item in draft_manifest.get("locked_result_coverage", [])
        if isinstance(item, dict)
        and item.get("artifact_role") == "figure_file"
        and item.get("used_in_manuscript") is True
        and item.get("display_status") != "journal_exempt"
    ]
    visible_final_figures = count_visible_figure_blocks(final_md)
    if visible_final_figures < len(expected_reader_figures):
        fail(
            "FAIL: Phase 19 final markdown dropped reader-facing figures required by the locked draft",
            expected_reader_figures,
        )
    visible_final_tables = count_visible_table_blocks(final_md)
    total_displays = visible_final_tables + visible_final_figures
    if int(content_checks.get("main_text_table_count", -1)) != visible_final_tables:
        fail("FAIL: Phase 18 content_checks.main_text_table_count mismatch")
    if int(content_checks.get("main_text_figure_count", -1)) != visible_final_figures:
        fail("FAIL: Phase 18 content_checks.main_text_figure_count mismatch")
    if int(content_checks.get("main_text_display_count", -1)) != total_displays:
        fail("FAIL: Phase 18 content_checks.main_text_display_count mismatch")
    display_cap = final_display_architecture.get("main_text_display_cap")
    if display_cap not in (None, "") and total_displays > int(display_cap):
        fail("FAIL: Phase 19 final markdown exceeds journal-specific main-text display cap")
    table_cap = final_display_architecture.get("main_text_table_cap")
    if table_cap not in (None, "") and visible_final_tables > int(table_cap):
        fail("FAIL: Phase 19 final markdown exceeds journal-specific table cap")
    figure_cap = final_display_architecture.get("main_text_figure_cap")
    if figure_cap not in (None, "") and visible_final_figures > int(figure_cap):
        fail("FAIL: Phase 19 final markdown exceeds journal-specific figure cap")
    if content_checks.get("display_cap_respected") is not True:
        fail("FAIL: Phase 18 content_checks must confirm display_cap_respected")
    if str(final_display_architecture.get("descriptive_table_requirement", "")).strip() in DESCRIPTIVE_TABLE_REQUIREMENTS:
        if "Table 1" not in final_md or content_checks.get("descriptive_table_requirement_satisfied") is not True:
            fail("FAIL: Phase 19 final markdown must satisfy the journal's descriptive Table 1 requirement")
    table_positions = count_label_positions(final_md, "Table")
    figure_positions = count_label_positions(final_md, "Figure")
    refs_heading = re.search(r"(?im)^##\s+references\s*$", strip_comments(final_md))
    refs_pos = refs_heading.start() if refs_heading else -1
    table_policy = str(final_display_architecture.get("table_placement_policy", "")).strip()
    figure_policy = str(final_display_architecture.get("figure_placement_policy", "")).strip()
    if refs_pos >= 0 and table_positions:
        if table_policy in {"end_matter_after_references", "end_matter_with_online_supplement"} and any(pos < refs_pos for pos in table_positions):
            fail("FAIL: Phase 19 table placement does not honor the journal end-matter policy")
        if table_policy == "embedded_main_text" and min(table_positions) > refs_pos:
            fail("FAIL: Phase 19 table placement does not honor the journal embedded-display policy")
    if refs_pos >= 0 and figure_positions:
        if figure_policy in {"separate_files_after_tables", "manuscript_or_supplement_figures"} and any(pos < refs_pos for pos in figure_positions):
            fail("FAIL: Phase 19 figure placement does not honor the journal end-matter/separate-file policy")
        if figure_policy == "embedded_main_text" and min(figure_positions) > refs_pos:
            fail("FAIL: Phase 19 figure placement does not honor the journal embedded-display policy")
        if figure_policy == "separate_files_after_tables" and table_positions and min(figure_positions) < max(table_positions):
            fail("FAIL: Phase 19 figures must follow tables under the journal separate-file policy")
    if manifest.get("fix_checklist", {}).get("critical_fixes") not in ([], None):
        fail("FAIL: Phase 18 fix_checklist.critical_fixes must be empty for PASS")
    if manifest.get("fix_checklist", {}).get("route_back") not in ([], None):
        fail("FAIL: Phase 18 fix_checklist.route_back must be empty for PASS")
    if manifest.get("route_back_phase") not in (None, ""):
        fail("FAIL: Phase 18 route_back_phase must be empty for PASS")
    if manifest.get("ready_for_phase_20") is not True:
        fail("FAIL: Phase 19 ready_for_phase_20 must be true")

if phase_id == "20":
    final_md_path = proj / "final" / "manuscript-final.md"
    final_docx_path = proj / "final" / "manuscript-final.docx"
    final_tex_path = proj / "final" / "manuscript-final.tex"
    final_pdf_path = proj / "final" / "manuscript-final.pdf"
    final_manifest_path = proj / "final" / "final-manifest.json"
    final_latest_path = proj / "final" / "LATEST.txt"
    references_path = proj / "citation" / "references.bib"
    ethics_path = proj / "ethics" / "ethics-open-science.json"
    replication_path = proj / "replication-package" / "replication-report.json"
    submission_md_path = proj / "submission" / "manuscript-submission.md"
    submission_docx_path = proj / "submission" / "manuscript-submission.docx"
    submission_tex_path = proj / "submission" / "manuscript-submission.tex"
    submission_pdf_path = proj / "submission" / "manuscript-submission.pdf"
    semantic_body_path = proj / "submission" / "semantic-body-prose-read.md"
    hygiene_path = proj / "submission" / "submission-hygiene.json"
    package_manifest_path = proj / "submission" / "submission-package-manifest.json"
    submission_latest_path = proj / "submission" / "LATEST.txt"
    for required_path in (
        final_md_path,
        final_docx_path,
        final_tex_path,
        final_pdf_path,
        final_manifest_path,
        final_latest_path,
        references_path,
        ethics_path,
        replication_path,
    ):
        if not required_path.exists():
            fail(f"FAIL: Phase 20 missing required input {required_path.relative_to(proj)}")
    try:
        final_manifest = json.loads(final_manifest_path.read_text())
        ethics = json.loads(ethics_path.read_text())
        replication = json.loads(replication_path.read_text())
        hygiene = json.loads(hygiene_path.read_text())
        package_manifest = json.loads(package_manifest_path.read_text())
    except Exception as exc:
        fail(f"FAIL: Phase 20 submission artifacts or inputs are not valid JSON: {exc}")
    if final_manifest.get("verdict") != "PASS" or final_manifest.get("ready_for_phase_20") is not True:
        fail("FAIL: Phase 20 requires a passing Phase 19 final manifest")
    if ethics.get("verdict") != "PASS" or ethics.get("ready_for_phase_17") is not True:
        fail("FAIL: Phase 20 requires a passing Phase 16 ethics/open-science report")
    if replication.get("verdict") != "PASS" or replication.get("ready_for_phase_18") is not True:
        fail("FAIL: Phase 20 requires a passing Phase 17 replication report")
    required = (
        "verdict",
        "degraded",
        "source_phase",
        "submission_engine",
        "journal_profile_resolution",
        "final_version_id",
        "submission_version_id",
        "created_at_utc",
        "source_hashes",
        "hygiene_checks",
        "citation_rendering",
        "path_scrub",
        "placeholder_scan",
        "internal_metadata_scan",
        "reader_facing_language",
        "semantic_body_prose_read",
        "declaration_visibility",
        "figure_packaging",
        "format_generation",
        "findings",
        "fix_checklist",
        "route_back_phase",
        "pipeline_complete",
    )
    absent = [field for field in required if field not in hygiene]
    if absent:
        fail("FAIL: Phase 20 hygiene report missing required fields", absent)
    manifest_required = (
        "verdict",
        "source_phase",
        "journal_profile_resolution",
        "final_version_id",
        "submission_version_id",
        "canonical_outputs",
        "versioned_outputs",
        "output_hashes",
        "versioned_output_hashes",
        "package_inventory",
        "ready_for_done",
    )
    manifest_absent = [field for field in manifest_required if field not in package_manifest]
    if manifest_absent:
        fail("FAIL: Phase 20 submission package manifest missing required fields", manifest_absent)
    findings = hygiene.get("findings")
    if not isinstance(findings, list):
        fail("FAIL: Phase 20 findings must be a list")
    allowed_categories = {
        "final_assembly": "19",
        "citation_rendering": "15",
        "ethics_declaration": "16",
        "replication_disclosure": "17",
        "path_scrub": "20",
        "placeholder": "20",
        "internal_metadata": "20",
        "reader_facing_language": "20",
        "figure_packaging": "20",
        "declaration_visibility": "16",
        "submission_manifest": "20",
        "versioning": "20",
        "semantic_body_prose": "13",
        "draft_machinery_prose": "13",
        "hypothesis_display": "13",
        "citation_marker": "15",
    }
    if hygiene.get("verdict") != "PASS":
        if hygiene.get("verdict") != "FAIL":
            fail(f"FAIL: Phase 20 top-level verdict must be PASS or FAIL, got {hygiene.get('verdict')}")
        if not findings:
            fail("FAIL: Phase 20 FAIL report must include nonempty findings")
        finding_issues = []
        route_phases = set()
        critical_or_major = 0
        seen_findings = set()
        for idx, finding in enumerate(findings):
            if not isinstance(finding, dict):
                finding_issues.append(f"findings[{idx}] is not an object")
                continue
            finding_id = str(finding.get("finding_id", "")).strip()
            if not finding_id or finding_id in seen_findings:
                finding_issues.append(f"findings[{idx}].finding_id missing or duplicate")
            seen_findings.add(finding_id)
            severity = str(finding.get("severity", "")).strip()
            if severity not in {"CRITICAL", "MAJOR", "MINOR", "WARNING"}:
                finding_issues.append(f"{finding_id}: severity invalid")
            if severity in {"CRITICAL", "MAJOR"}:
                critical_or_major += 1
            category = str(finding.get("category", "")).strip()
            expected_phase = allowed_categories.get(category)
            if expected_phase is None:
                finding_issues.append(f"{finding_id}: category invalid")
            owner_phase = str(finding.get("owner_phase", "")).strip()
            route_back_phase = str(finding.get("route_back_phase", "")).strip()
            if expected_phase and owner_phase != expected_phase:
                finding_issues.append(f"{finding_id}: owner_phase must be {expected_phase} for {category}")
            if expected_phase and route_back_phase != expected_phase:
                finding_issues.append(f"{finding_id}: route_back_phase must be {expected_phase} for {category}")
            if route_back_phase:
                route_phases.add(route_back_phase)
            if finding.get("detected_by") not in {"submission-hygiene", "submission-manifest", "citation-rendering", "path-scrub", "metadata-scrub", "reader-language-check", "declaration-check", "figure-packaging", "semantic-body-prose-read", "machinery-prose-scan", "hypothesis-display-scan"}:
                finding_issues.append(f"{finding_id}: detected_by must be a Phase 20 checker")
            affected = finding.get("affected_artifacts")
            if not isinstance(affected, list) or not affected or any(not str(item).strip() for item in affected):
                finding_issues.append(f"{finding_id}: affected_artifacts must be a nonempty list")
            if not str(finding.get("required_fix", "")).strip():
                finding_issues.append(f"{finding_id}: required_fix missing")
            if finding.get("status") != "open":
                finding_issues.append(f"{finding_id}: status must be open")
        fix_checklist = hygiene.get("fix_checklist")
        if not isinstance(fix_checklist, dict):
            finding_issues.append("fix_checklist must be an object")
        else:
            if critical_or_major and not fix_checklist.get("critical_fixes"):
                finding_issues.append("fix_checklist.critical_fixes must be nonempty for CRITICAL/MAJOR findings")
            route_back = fix_checklist.get("route_back")
            if not isinstance(route_back, list) or not route_back:
                finding_issues.append("fix_checklist.route_back must be nonempty for FAIL")
        top_route = str(hygiene.get("route_back_phase", "")).strip()
        if not top_route:
            finding_issues.append("route_back_phase must be set for FAIL")
        elif route_phases and top_route != str(min(int(phase) for phase in route_phases)):
            finding_issues.append("route_back_phase must be the earliest finding route_back_phase")
        if hygiene.get("source_phase") != "20":
            finding_issues.append("source_phase must be 20")
        if hygiene.get("pipeline_complete") is not False:
            finding_issues.append("pipeline_complete must be false for FAIL")
        if finding_issues:
            fail("FAIL: Phase 20 FAIL report is malformed", finding_issues)
        fail("FAIL: Phase 20 submission hygiene found unresolved issues", [f"route_back_phase={top_route}"] + [f"{f.get('finding_id')}: {f.get('required_fix')}" for f in findings if isinstance(f, dict)])

    if hygiene.get("degraded") is not False:
        fail("FAIL: Phase 20 degraded must be false")
    if hygiene.get("source_phase") != "20" or package_manifest.get("source_phase") != "20":
        fail("FAIL: Phase 20 source_phase must be 20")
    submission_journal_resolution = hygiene.get("journal_profile_resolution")
    if submission_journal_resolution != final_manifest.get("journal_profile_resolution"):
        fail("FAIL: Phase 20 submission-hygiene journal_profile_resolution must match the final manifest")
    resolution_target = final_manifest.get("journal_profile_resolution", {}).get("resolved_profile_name") or final_manifest.get("journal_profile_resolution", {}).get("requested_journal") or "American Sociological Review"
    resolution_issues = validate_journal_profile_resolution(submission_journal_resolution, resolution_target, "Phase 20 hygiene")
    if resolution_issues:
        fail("FAIL: Phase 20 submission-hygiene journal_profile_resolution is invalid", resolution_issues)
    if package_manifest.get("journal_profile_resolution") != final_manifest.get("journal_profile_resolution"):
        fail("FAIL: Phase 20 submission-package-manifest journal_profile_resolution must match the final manifest")
    if findings:
        fail("FAIL: Phase 20 PASS report must have empty findings")
    if hygiene.get("pipeline_complete") is not True:
        fail("FAIL: Phase 20 pipeline_complete must be true")
    if package_manifest.get("ready_for_done") is not True:
        fail("FAIL: Phase 20 submission package manifest ready_for_done must be true")
    engine = hygiene.get("submission_engine")
    if not isinstance(engine, dict) or not str(engine.get("name", "")).strip():
        fail("FAIL: Phase 20 submission_engine must identify the hygiene process")
    final_version_id = str(hygiene.get("final_version_id", "")).strip()
    if final_version_id != str(final_manifest.get("version_id", "")).strip():
        fail("FAIL: Phase 20 final_version_id must match Phase 19 final manifest")
    if final_latest_path.read_text(errors="ignore") != f"{final_version_id}\n":
        fail("FAIL: Phase 20 final_version_id must match final/LATEST.txt")
    submission_version_id = str(hygiene.get("submission_version_id", "")).strip()
    if not re.match(r"^\d{4}-\d{2}-\d{2}T\d{6}Z-v\d{3}$", submission_version_id):
        fail("FAIL: Phase 20 submission_version_id must match YYYY-MM-DDTHHMMSSZ-vNNN")
    created_at = str(hygiene.get("created_at_utc", "")).strip()
    expected_created = f"{submission_version_id[:13]}:{submission_version_id[13:15]}:{submission_version_id[15:17]}Z"
    if created_at != expected_created:
        fail("FAIL: Phase 20 created_at_utc must match submission_version_id timestamp")
    if not submission_latest_path.exists() or submission_latest_path.read_text(errors="ignore") != f"{submission_version_id}\n":
        fail("FAIL: Phase 20 submission/LATEST.txt must point to active submission_version_id")
    if package_manifest.get("final_version_id") != final_version_id or package_manifest.get("submission_version_id") != submission_version_id:
        fail("FAIL: Phase 20 package manifest version ids must match hygiene report")
    source_hashes = hygiene.get("source_hashes")
    if not isinstance(source_hashes, dict):
        fail("FAIL: Phase 20 source_hashes must be an object")
    expected_hashes = {
        "final_manifest": sha256(final_manifest_path),
        "final_latest": sha256(final_latest_path),
        "final_md": sha256(final_md_path),
        "final_docx": sha256(final_docx_path),
        "final_tex": sha256(final_tex_path),
        "final_pdf": sha256(final_pdf_path),
        "references_bib": sha256(references_path),
        "ethics_open_science": sha256(ethics_path),
        "replication_report": sha256(replication_path),
    }
    stale_sources = [
        f"{key} mismatch"
        for key, expected in expected_hashes.items()
        if source_hashes.get(key) != expected
    ]
    if stale_sources:
        fail("FAIL: Phase 20 source_hashes are stale", stale_sources)
    expected_canonical = {
        "submission_md": "submission/manuscript-submission.md",
        "submission_docx": "submission/manuscript-submission.docx",
        "submission_tex": "submission/manuscript-submission.tex",
        "submission_pdf": "submission/manuscript-submission.pdf",
        "semantic_body_prose_read": "submission/semantic-body-prose-read.md",
        "hygiene_json": "submission/submission-hygiene.json",
        "package_manifest": "submission/submission-package-manifest.json",
    }
    if package_manifest.get("canonical_outputs") != expected_canonical:
        fail("FAIL: Phase 20 canonical_outputs must use submission/ stable paths")
    expected_versioned = {
        "submission_md": f"submission/versions/{submission_version_id}/manuscript-submission-{submission_version_id}.md",
        "submission_docx": f"submission/versions/{submission_version_id}/manuscript-submission-{submission_version_id}.docx",
        "submission_tex": f"submission/versions/{submission_version_id}/manuscript-submission-{submission_version_id}.tex",
        "submission_pdf": f"submission/versions/{submission_version_id}/manuscript-submission-{submission_version_id}.pdf",
        "semantic_body_prose_read": f"submission/versions/{submission_version_id}/semantic-body-prose-read-{submission_version_id}.md",
        "hygiene_json": f"submission/versions/{submission_version_id}/submission-hygiene-{submission_version_id}.json",
        "package_manifest": f"submission/versions/{submission_version_id}/submission-package-manifest-{submission_version_id}.json",
    }
    if package_manifest.get("versioned_outputs") != expected_versioned:
        fail("FAIL: Phase 20 versioned_outputs must use submission/versions/<submission_version_id>/")
    output_hashes = package_manifest.get("output_hashes")
    versioned_hashes = package_manifest.get("versioned_output_hashes")
    if not isinstance(output_hashes, dict) or not isinstance(versioned_hashes, dict):
        fail("FAIL: Phase 20 output hashes must be objects")
    canonical_files = {
        "submission_md": submission_md_path,
        "submission_docx": submission_docx_path,
        "submission_tex": submission_tex_path,
        "submission_pdf": submission_pdf_path,
        "semantic_body_prose_read": semantic_body_path,
        "hygiene_json": hygiene_path,
        "package_manifest": package_manifest_path,
    }
    output_issues = []
    for key, path in canonical_files.items():
        if not path.exists() or not path.is_file():
            output_issues.append(f"{key}: missing")
            continue
        if path.stat().st_size < 20:
            output_issues.append(f"{key}: file too small")
            continue
        if key == "hygiene_json" or key == "package_manifest":
            expected_hash = "SELF_REFERENTIAL"
        else:
            expected_hash = sha256(path)
        if output_hashes.get(key) != expected_hash:
            output_issues.append(f"{key}: output_hash mismatch")
    for key, rel in expected_versioned.items():
        path = proj / rel
        if not path.exists() or not path.is_file():
            output_issues.append(f"{key}: versioned copy missing")
            continue
        if key in {"submission_md", "submission_docx", "submission_tex", "submission_pdf", "semantic_body_prose_read"}:
            vh = sha256(path)
            if versioned_hashes.get(key) != vh:
                output_issues.append(f"{key}: versioned hash mismatch")
            if vh != output_hashes.get(key):
                output_issues.append(f"{key}: versioned hash differs from canonical")
        elif versioned_hashes.get(key) != "SELF_REFERENTIAL":
            output_issues.append(f"{key}: versioned self-referential hash must be SELF_REFERENTIAL")
    if output_issues:
        fail("FAIL: Phase 20 submission package outputs are invalid", output_issues)
    format_issues = []
    try:
        with zipfile.ZipFile(submission_docx_path) as zf:
            if "word/document.xml" not in zf.namelist():
                format_issues.append("submission_docx: missing word/document.xml")
    except zipfile.BadZipFile:
        format_issues.append("submission_docx: not a valid docx zip")
    tex_text = submission_tex_path.read_text(errors="ignore")
    if "\\documentclass" not in tex_text or "\\begin{document}" not in tex_text:
        format_issues.append("submission_tex: missing documentclass or document body")
    with submission_pdf_path.open("rb") as f:
        pdf_head = f.read(8)
        f.seek(max(0, submission_pdf_path.stat().st_size - 2048))
        pdf_tail = f.read()
    if not pdf_head.startswith(b"%PDF") or b"%%EOF" not in pdf_tail:
        format_issues.append("submission_pdf: missing PDF header or EOF marker")
    if format_issues:
        fail("FAIL: Phase 20 submission formats are invalid", format_issues)
    submission_text = submission_md_path.read_text(errors="ignore")
    submission_keyword_issues = keyword_placement_issues(submission_text)
    if submission_keyword_issues:
        fail("FAIL: Phase 20 submission manuscript has invalid front-matter keyword placement", submission_keyword_issues)
    local_path_pattern = re.compile(r"(/Users/|/tmp/|/private/var/|/var/folders/|/home/|~[/\\]|\\$HOME|[A-Za-z]:\\\\|\\\\\\\\)")
    if local_path_pattern.search(submission_text):
        fail("FAIL: Phase 20 submission manuscript contains local absolute paths")
    internal_pattern = re.compile(r"(results-locked/|manifest SHA|SHA-256 of manifest|\.auto-research/|verify/|logs/|replication-package/|final/versions/)", re.IGNORECASE)
    if internal_pattern.search(submission_text):
        fail("FAIL: Phase 20 submission manuscript contains internal pipeline metadata")
    submission_display_architecture = (
        final_manifest.get("journal_profile_resolution", {}).get("display_architecture", {})
        if isinstance(final_manifest.get("journal_profile_resolution"), dict)
        else {}
    )
    if editable_text_policy_forbids_raw_html_tables(submission_display_architecture):
        submission_html_table_hits = raw_html_table_hits(submission_text)
        if submission_html_table_hits:
            fail(
                "FAIL: Phase 20 submission markdown contains raw HTML tables despite editable-text table policy",
                submission_html_table_hits[:10],
            )
    jargon_hits = reader_workflow_jargon_hits(submission_text)
    if jargon_hits:
        fail("FAIL: Phase 20 submission manuscript exposes internal workflow language", jargon_hits[:25])
    machinery_hits = submission_machinery_prose_hits(submission_text)
    if machinery_hits:
        fail("FAIL: Phase 20 Stage A submission manuscript exposes machinery prose", machinery_hits[:25])
    hypothesis_list_hits = hypothesis_display_hits(submission_text)
    if hypothesis_list_hits:
        if not displayed_hypotheses_allowed(hygiene, package_manifest, final_manifest):
            fail("FAIL: Phase 20 Stage A submission manuscript exposes proposal-style hypothesis bullet/list blocks", hypothesis_list_hits[:25])
        bare_hypothesis_hits = bare_hypothesis_display_hits(submission_text)
        if bare_hypothesis_hits:
            fail("FAIL: Phase 20 Stage A submission manuscript exposes displayed hypotheses without nearby theoretical motivation", bare_hypothesis_hits[:25])
    submission_registry_table_hits = registry_like_table_display_hits(submission_text)
    if submission_registry_table_hits:
        fail("FAIL: Phase 20 submission manuscript exposes registry/model-ladder tables as reader-facing evidence", submission_registry_table_hits[:25])
    phase20_external_gate_failures = []
    for gate_name, label in [
        ("abstract-boilerplate-check.sh", "Phase 20 abstract boilerplate"),
        ("manuscript-artifact-leakage-check.sh", "Phase 20 manuscript artifact leakage"),
        ("concept-to-measure-check.sh", "Phase 20 concept-to-measure bridge"),
        ("data-sample-flow-check.sh", "Phase 20 data/sample flow"),
        ("analytic-formula-specificity-check.sh", "Phase 20 method-specific analytic detail"),
        ("theory-hypothesis-continuity-check.sh", "Phase 20 theory/hypothesis continuity"),
        ("introduction-argument-architecture-check.sh", "Phase 20 introduction argument architecture"),
        ("theory-structure-depth-check.sh", "Phase 20 theory structure depth"),
        ("discussion-adjudication-check.sh", "Phase 20 discussion adjudication"),
        ("conclusion-contribution-support-check.sh", "Phase 20 conclusion contribution support"),
        ("cross-section-continuity-check.sh", "Phase 20 cross-section continuity"),
        ("citation-cluster-quality-check.sh", "Phase 20 citation cluster quality"),
        ("figure-style-source-check.sh", "Phase 20 figure style source"),
    ]:
        gate_result = run_external_gate(gate_name, proj, label)
        if gate_result is None:
            continue
        status, reason, detail = gate_result
        if status == "RED":
            phase20_external_gate_failures.append(f"{label}: reason={reason} detail={detail}")
    if phase20_external_gate_failures:
        fail("FAIL: Phase 20 external methods gates failed", phase20_external_gate_failures)
    placeholder_pattern = re.compile(
        r"\[(paper title|title|journal|author|insert [^\]]+|add [^\]]+|citation needed)\]"
        r"|\b(TBD|TODO|XXXX+|to be determined|SOURCE NEEDED|UNVERIFIED)\b"
        r"|\[REVISED:[^\]]+\]|\[T\d+\]",
        re.IGNORECASE
    )
    if placeholder_pattern.search(submission_text):
        fail("FAIL: Phase 20 submission manuscript contains placeholders or tracker markers")
    if re.search(r"^#+\s*(Reviewer objections we anticipate|Foreshadow)", submission_text, re.IGNORECASE | re.MULTILINE):
        fail("FAIL: Phase 20 submission manuscript contains reviewer-scaffolding headings")
    if "references" not in submission_text.lower():
        fail("FAIL: Phase 20 submission manuscript must include a References section")
    if has_raw_citekeys(submission_text):
        fail("FAIL: Phase 20 submission manuscript contains raw citation syntax")
    refs_match = re.search(r"(?ims)^#{1,3}\s+references\s*$([\s\S]*)", submission_text)
    if refs_match:
        refs_body = refs_match.group(1)
        if re.search(r"(?m)^\s*[-*+]\s+\S", refs_body):
            fail("FAIL: Phase 20 References section must not be a Markdown bullet list")
        if references_looks_like_key_dump(refs_body):
            fail("FAIL: Phase 20 submission References section looks like a citekey dump rather than formatted references")
    final_figure_blocks = count_visible_figure_blocks(final_md_path.read_text(errors="ignore"))
    submission_figure_blocks = count_visible_figure_blocks(submission_text)
    if final_figure_blocks > 0 and submission_figure_blocks < final_figure_blocks:
        fail("FAIL: Phase 20 submission manuscript dropped reader-facing figures present in the final manuscript")
    visible_submission = visible_markdown_text(submission_text).lower()
    declaration_patterns = {
        "data availability": r"\b(data availability|availability of data|data and code availability)\b",
        "ethics or human-subjects status": r"\b(ethics|irb|human subjects|human-subjects|institutional review)\b",
        "ai/tool use": r"\b(ai use|artificial intelligence|large language model|language model|tool use disclosure|ai disclosure)\b",
        "conflict of interest": r"\b(conflict of interest|conflicts of interest|competing interests|coi)\b",
    }
    missing_declarations = [
        label
        for label, pattern in declaration_patterns.items()
        if not re.search(pattern, visible_submission)
    ]
    if missing_declarations:
        fail("FAIL: Phase 20 submission manuscript is missing visible declaration sections or statements", missing_declarations)
    hygiene_checks = hygiene.get("hygiene_checks")
    path_scrub = hygiene.get("path_scrub")
    placeholder_scan = hygiene.get("placeholder_scan")
    internal_scan = hygiene.get("internal_metadata_scan")
    reader_language = hygiene.get("reader_facing_language")
    semantic_body = hygiene.get("semantic_body_prose_read")
    declaration_visibility = hygiene.get("declaration_visibility")
    figure_packaging = hygiene.get("figure_packaging")
    format_generation = hygiene.get("format_generation")
    citation_rendering = hygiene.get("citation_rendering")
    for label, section in {
        "hygiene_checks": hygiene_checks,
        "path_scrub": path_scrub,
        "placeholder_scan": placeholder_scan,
        "internal_metadata_scan": internal_scan,
        "reader_facing_language": reader_language,
        "semantic_body_prose_read": semantic_body,
        "declaration_visibility": declaration_visibility,
        "figure_packaging": figure_packaging,
        "format_generation": format_generation,
        "citation_rendering": citation_rendering,
    }.items():
        if not isinstance(section, dict):
            fail(f"FAIL: Phase 20 {label} must be an object")
    if hygiene_checks.get("red_hits") not in (0, "0") or hygiene_checks.get("status") not in {"GREEN", "YELLOW"}:
        fail("FAIL: Phase 20 hygiene_checks must have zero red hits and GREEN/YELLOW status")
    stage_a = hygiene_checks.get("stage_a")
    if not isinstance(stage_a, dict):
        fail("FAIL: Phase 20 hygiene_checks.stage_a must document deterministic machinery scan")
    if stage_a.get("status") != "GREEN" or stage_a.get("red_hits") not in (0, "0") or stage_a.get("machinery_prose_hits") not in (0, "0"):
        fail("FAIL: Phase 20 hygiene_checks.stage_a must be GREEN with zero red/machinery hits")
    if path_scrub.get("absolute_paths") not in (0, "0") or path_scrub.get("internal_paths") not in (0, "0"):
        fail("FAIL: Phase 20 path_scrub must report zero absolute/internal paths")
    if placeholder_scan.get("unresolved_placeholders") not in (0, "0"):
        fail("FAIL: Phase 20 placeholder_scan must report zero unresolved placeholders")
    if internal_scan.get("pipeline_metadata_hits") not in (0, "0"):
        fail("FAIL: Phase 20 internal_metadata_scan must report zero pipeline metadata hits")
    if reader_language.get("workflow_jargon_hits") not in (0, "0") or reader_language.get("status") != "PASS":
        fail("FAIL: Phase 20 reader_facing_language must report zero workflow jargon hits and PASS status")
    semantic_report_issues = validate_semantic_body_prose_report(semantic_body, semantic_body_path, sha256(submission_md_path))
    if semantic_report_issues:
        fail("FAIL: Phase 20 semantic body-prose read is missing, stale, or unresolved", semantic_report_issues)
    if declaration_visibility.get("missing_required_declarations") not in ([], None) or declaration_visibility.get("status") != "PASS":
        fail("FAIL: Phase 20 declaration_visibility must report all required declarations visible")
    if figure_packaging.get("missing_or_uninventoried_figures") not in ([], None) or figure_packaging.get("status") != "PASS":
        fail("FAIL: Phase 20 figure_packaging must report no missing or uninventoried referenced figures")
    if citation_rendering.get("unresolved_citations") not in (0, "0") or citation_rendering.get("references_bullet_list") not in (False, 0):
        fail("FAIL: Phase 20 citation_rendering must report zero unresolved citations and no bullet-list references")
    if citation_rendering.get("bibliography_present") is not True:
        fail("FAIL: Phase 20 citation_rendering must confirm a rendered bibliography is present")
    generation_issues = []
    source_md_hash = sha256(submission_md_path)
    for fmt in ("docx", "tex", "pdf"):
        section = format_generation.get(fmt)
        if not isinstance(section, dict):
            generation_issues.append(f"{fmt}: missing section")
            continue
        if section.get("status") != "PASS":
            generation_issues.append(f"{fmt}: status must be PASS")
        if section.get("source_md_sha256") != source_md_hash:
            generation_issues.append(f"{fmt}: source_md_sha256 mismatch")
        command = str(section.get("command", "")).strip()
        if not command:
            generation_issues.append(f"{fmt}: command missing")
        else:
            expected_output = f"submission/manuscript-submission.{fmt}"
            if not command_invokes_pandoc(command):
                generation_issues.append(f"{fmt}: command must invoke pandoc")
            if "submission/manuscript-submission.md" not in command:
                generation_issues.append(f"{fmt}: command must use submission/manuscript-submission.md as source")
            if expected_output not in command:
                generation_issues.append(f"{fmt}: command must write {expected_output}")
    if generation_issues:
        fail("FAIL: Phase 20 format_generation is incomplete", generation_issues)
    package_inventory = package_manifest.get("package_inventory")
    if not isinstance(package_inventory, dict) or not isinstance(package_inventory.get("files"), list):
        fail("FAIL: Phase 20 package_inventory.files must be a list")
    inventory_records = {}
    inventory_issues = []
    for idx, item in enumerate(package_inventory.get("files", [])):
        if not isinstance(item, dict):
            inventory_issues.append(f"files[{idx}]: not an object")
            continue
        rel = str(item.get("path", "")).strip()
        if not rel:
            inventory_issues.append(f"files[{idx}]: path missing")
            continue
        if rel in inventory_records:
            inventory_issues.append(f"{rel}: duplicate inventory record")
        inventory_records[rel] = item
        if not str(item.get("role", "")).strip():
            inventory_issues.append(f"{rel}: role missing")
    submission_image_targets = []
    for target in markdown_link_targets(submission_text, image_only=True):
        clean_target = target.split("#", 1)[0].split("?", 1)[0].strip()
        if not clean_target or clean_target.startswith(("http://", "https://", "mailto:", "#")):
            continue
        submission_image_targets.append(clean_target)
    for target in submission_image_targets:
        resolved = (submission_md_path.parent / target).resolve()
        try:
            rel_target = str(resolved.relative_to(proj.resolve()))
        except Exception:
            inventory_issues.append(f"{target}: referenced figure resolves outside project")
            continue
        if not resolved.exists():
            inventory_issues.append(f"{target}: referenced figure file is missing")
        elif rel_target not in inventory_records:
            inventory_issues.append(f"{rel_target}: referenced figure missing package inventory record")
    expected_inventory = set(expected_canonical.values()) | set(expected_versioned.values()) | {"submission/LATEST.txt"}
    inventory_paths = set(inventory_records)
    missing_inventory = expected_inventory - inventory_paths
    if missing_inventory:
        inventory_issues.extend(sorted(f"{rel}: missing inventory record" for rel in missing_inventory))
    for rel in sorted(expected_inventory & inventory_paths):
        expected_hash = "SELF_REFERENTIAL" if rel.endswith(".json") else sha256(proj / rel)
        if inventory_records[rel].get("sha256") != expected_hash:
            inventory_issues.append(f"{rel}: inventory sha256 mismatch")
    if inventory_issues:
        fail("FAIL: Phase 20 package inventory is invalid", inventory_issues)
    if hygiene.get("fix_checklist", {}).get("critical_fixes") not in ([], None):
        fail("FAIL: Phase 20 fix_checklist.critical_fixes must be empty for PASS")
    if hygiene.get("fix_checklist", {}).get("route_back") not in ([], None):
        fail("FAIL: Phase 20 fix_checklist.route_back must be empty for PASS")
    if hygiene.get("route_back_phase") not in (None, ""):
        fail("FAIL: Phase 20 route_back_phase must be empty for PASS")
    if package_manifest.get("verdict") != "PASS":
        fail("FAIL: Phase 20 submission package manifest verdict must be PASS")

print(f"PASS: Phase {phase_id} {phase['name']} required outputs exist")
print("Required verdict fields:")
for field in phase["pass_schema"]:
    print(f"  - {field}")
PY
