#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

bash -n "$SCRIPT_DIR/auto-research-verify.sh"
python3 -m json.tool "$SKILL_DIR/references/phase-contract.json" >/dev/null
bash "$SCRIPT_DIR/auto-research-contract-lint.sh" >/dev/null
bash "$SCRIPT_DIR/auto-research-system-gate-smoke.sh" >/dev/null

python3 - "$SKILL_DIR" <<'PY'
import copy
import json
import re
import sys
from pathlib import Path

skill_dir = Path(sys.argv[1])


def word_count(value):
    return len(re.findall(r"\b\w+\b", str(value or "")))


def norm(value):
    return re.sub(r"\s+", " ", str(value or "").strip().lower())


def validate_source_role_matrix(matrix):
    issues = []
    entries = matrix.get("source_role_matrix")
    if not isinstance(entries, list) or len(entries) < 12:
        issues.append("source_role_matrix must include at least 12 entries")
        return issues
    allowed = {
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
    roles = set()
    for idx, item in enumerate(entries):
        if not isinstance(item, dict):
            issues.append(f"source_role_matrix[{idx}] is not an object")
            continue
        role = str(item.get("argument_role", "")).strip()
        roles.add(role)
        if not str(item.get("key", "") or item.get("title", "")).strip():
            issues.append(f"source_role_matrix[{idx}] missing source key/title")
        if role not in allowed:
            issues.append(f"source_role_matrix[{idx}] invalid role")
        for field in ("claim_supported", "target_section", "why_it_matters"):
            if word_count(item.get(field)) < 4:
                issues.append(f"source_role_matrix[{idx}].{field} too thin")
    required_groups = [
        {"theory"},
        {"mechanism"},
        {"rival", "competing_explanation"},
        {"method", "design"},
    ]
    for group in required_groups:
        if not roles.intersection(group):
            issues.append(f"missing source role group {sorted(group)}")
    return issues


def validate_design_continuity(manifest):
    issues = []
    expected_claim_strength = norm(manifest.get("identification_claim_strength", "associational"))
    continuity = manifest.get("claim_continuity")
    if not isinstance(continuity, dict):
        issues.append("claim_continuity must be an object")
    else:
        if norm(continuity.get("claim_strength")) != expected_claim_strength:
            issues.append("claim_continuity claim_strength mismatch")
        for field in (
            "mechanisms_carried_forward",
            "hypotheses_carried_forward",
            "robustness_carried_forward",
            "limitations_carried_forward",
        ):
            if continuity.get(field) is not True:
                issues.append(f"{field} must be true")
        if word_count(continuity.get("manuscript_claim_boundary")) < 8:
            issues.append("manuscript_claim_boundary too thin")
    mechanism_rows = manifest.get("mechanism_result_matrix")
    if not isinstance(mechanism_rows, list) or not mechanism_rows:
        issues.append("mechanism_result_matrix must be nonempty")
    else:
        for idx, item in enumerate(mechanism_rows):
            for field in ("mechanism", "model_or_spec", "expected_pattern", "manuscript_implication"):
                if not isinstance(item, dict) or word_count(item.get(field)) < 3:
                    issues.append(f"mechanism_result_matrix[{idx}].{field} too thin")
    robustness_rows = manifest.get("robustness_claim_matrix")
    expected_robustness = int(manifest.get("robustness_plan_count", 1))
    if not isinstance(robustness_rows, list) or len(robustness_rows) < expected_robustness:
        issues.append("robustness_claim_matrix must cover robustness plan")
    else:
        for idx, item in enumerate(robustness_rows):
            for field in ("robustness_check", "claim_implication", "weaken_or_bound_rule"):
                if not isinstance(item, dict) or word_count(item.get(field)) < 3:
                    issues.append(f"robustness_claim_matrix[{idx}].{field} too thin")
    limitation_rows = manifest.get("limitation_scope_matrix")
    if not isinstance(limitation_rows, list) or not limitation_rows:
        issues.append("limitation_scope_matrix must be nonempty")
    else:
        for idx, item in enumerate(limitation_rows):
            for field in ("limitation", "scope_language", "affected_claim"):
                if not isinstance(item, dict) or word_count(item.get(field)) < 3:
                    issues.append(f"limitation_scope_matrix[{idx}].{field} too thin")
    return issues


def validate_publication_readiness(blueprint):
    issues = []
    readiness = blueprint.get("publication_readiness")
    if not isinstance(readiness, dict):
        return ["publication_readiness must be an object"]
    if readiness.get("status") != "PASS":
        issues.append("status must be PASS")
    if readiness.get("ready_for_drafting") is not True:
        issues.append("ready_for_drafting must be true")
    if readiness.get("route_back_if_not_ready") not in (False, 0):
        issues.append("route_back_if_not_ready must be false")
    if word_count(readiness.get("contribution_sentence")) < 10:
        issues.append("contribution_sentence too thin")
    if word_count(readiness.get("target_journal_novelty_claim") or readiness.get("novelty_claim")) < 10:
        issues.append("target_journal_novelty_claim too thin")
    if word_count(readiness.get("target_journal_fit") or readiness.get("journal_fit_claim")) < 8:
        issues.append("target_journal_fit too thin")

    mechanism_rows = readiness.get("mechanism_rival_matrix")
    roles = set()
    if not isinstance(mechanism_rows, list) or len(mechanism_rows) < 2:
        issues.append("mechanism_rival_matrix must include mechanism and rival entries")
    else:
        for idx, item in enumerate(mechanism_rows):
            role = str(item.get("role", "")).strip() if isinstance(item, dict) else ""
            roles.add(role)
            if role not in {"mechanism", "rival", "alternative", "scope_condition", "boundary_condition"}:
                issues.append(f"mechanism_rival_matrix[{idx}].role invalid")
            for field in ("label", "evidence_link", "claim_implication"):
                if not isinstance(item, dict) or word_count(item.get(field)) < 3:
                    issues.append(f"mechanism_rival_matrix[{idx}].{field} too thin")
        if "mechanism" not in roles:
            issues.append("mechanism_rival_matrix must include a mechanism")
        if not roles.intersection({"rival", "alternative"}):
            issues.append("mechanism_rival_matrix must include a rival")

    risks = readiness.get("reviewer_risk_register")
    if not isinstance(risks, list) or len(risks) < 3:
        issues.append("reviewer_risk_register must include three objections")
    else:
        has_rejection_reason = False
        for idx, item in enumerate(risks):
            if not isinstance(item, dict):
                issues.append(f"reviewer_risk_register[{idx}] is not an object")
                continue
            risk_type = str(item.get("risk_type", "") or item.get("type", "")).lower()
            has_rejection_reason = has_rejection_reason or "rejection" in risk_type or item.get("strongest_rejection_reason") is True
            for field in ("objection", "required_response"):
                if word_count(item.get(field)) < 5:
                    issues.append(f"reviewer_risk_register[{idx}].{field} too thin")
        if not has_rejection_reason:
            issues.append("reviewer_risk_register must identify the strongest rejection reason")

    hierarchy_paths = {
        str(item.get("artifact_path", "")).strip()
        for item in blueprint.get("result_hierarchy", [])
        if isinstance(item, dict)
    }
    evidence = readiness.get("evidence_claim_map")
    if not isinstance(evidence, list) or not evidence:
        issues.append("evidence_claim_map must be nonempty")
    else:
        for idx, item in enumerate(evidence):
            if not isinstance(item, dict):
                issues.append(f"evidence_claim_map[{idx}] is not an object")
                continue
            for field in ("claim", "evidence_type", "claim_strength"):
                if word_count(item.get(field)) < 2:
                    issues.append(f"evidence_claim_map[{idx}].{field} too thin")
            path = str(item.get("artifact_path", "")).strip()
            if not (path or str(item.get("hypothesis_id", "")).strip() or str(item.get("limitation", "")).strip()):
                issues.append(f"evidence_claim_map[{idx}] lacks evidence locator")
            if path and path not in hierarchy_paths:
                issues.append(f"evidence_claim_map[{idx}].artifact_path not in result_hierarchy")
    return issues


def validate_drafting_plan(plan, blueprint):
    issues = []
    required_sections = {"abstract", "introduction", "background", "data and methods", "results", "discussion"}
    if plan.get("verdict") != "PASS":
        issues.append("drafting-plan verdict must be PASS")
    if plan.get("source_phase") not in ("13", 13):
        issues.append("source_phase must be 13")
    section_briefs = plan.get("section_briefs")
    if not isinstance(section_briefs, dict):
        issues.append("section_briefs must be an object")
    else:
        for section in required_sections:
            brief = section_briefs.get(section)
            if not isinstance(brief, dict):
                issues.append(f"section_briefs.{section} missing")
                continue
            for field in ("section_purpose", "key_claim", "required_evidence", "source_roles", "forbidden_moves"):
                value = brief.get(field)
                if isinstance(value, list):
                    if not value:
                        issues.append(f"section_briefs.{section}.{field} empty")
                elif word_count(value) < 4:
                    issues.append(f"section_briefs.{section}.{field} too thin")

    paragraph_map = plan.get("paragraph_purpose_map")
    if not isinstance(paragraph_map, list) or len(paragraph_map) < max(6, len(required_sections)):
        issues.append("paragraph_purpose_map must cover required sections")
    else:
        covered = set()
        for idx, item in enumerate(paragraph_map):
            if not isinstance(item, dict):
                issues.append(f"paragraph_purpose_map[{idx}] is not an object")
                continue
            covered.add(norm(item.get("section")))
            for field in ("paragraph_id", "purpose", "claim"):
                if word_count(item.get(field)) < 2:
                    issues.append(f"paragraph_purpose_map[{idx}].{field} too thin")
            if not (item.get("source_roles") or item.get("evidence_artifacts") or item.get("mechanism_link")):
                issues.append(f"paragraph_purpose_map[{idx}] lacks source/evidence/mechanism link")
        missing = sorted(required_sections - covered - {"abstract"})
        if missing:
            issues.append(f"paragraph_purpose_map missing sections {missing}")

    source_plan = plan.get("source_use_plan")
    if not isinstance(source_plan, list) or len(source_plan) < 10:
        issues.append("source_use_plan must include at least 10 entries")
    else:
        roles = set()
        for idx, item in enumerate(source_plan):
            role = str(item.get("argument_role", "")).strip() if isinstance(item, dict) else ""
            roles.add(role)
            if not isinstance(item, dict) or not str(item.get("citation_key", "") or item.get("title", "")).strip():
                issues.append(f"source_use_plan[{idx}] missing citation key/title")
                continue
            for field in ("target_section", "claim_supported", "why_necessary"):
                if word_count(item.get(field)) < 3:
                    issues.append(f"source_use_plan[{idx}].{field} too thin")
        if not roles.intersection({"rival", "competing_explanation", "alternative"}):
            issues.append("source_use_plan must include rival sources")
        if not roles.intersection({"theory", "mechanism"}):
            issues.append("source_use_plan must include theory or mechanism sources")

    expected_artifacts = {
        str(item.get("artifact_path", "")).strip()
        for item in blueprint.get("result_hierarchy", [])
        if isinstance(item, dict) and item.get("headline_status") in {"headline", "supporting"}
    }
    results_plan = plan.get("results_interpretation_plan")
    if not isinstance(results_plan, list):
        issues.append("results_interpretation_plan must be a list")
    else:
        covered = set()
        for idx, item in enumerate(results_plan):
            if not isinstance(item, dict):
                issues.append(f"results_interpretation_plan[{idx}] is not an object")
                continue
            covered.add(str(item.get("artifact_path", "")).strip())
            for field in ("interpretive_claim", "uncertainty_language", "mechanism_link", "limitation_language"):
                if word_count(item.get(field)) < 4:
                    issues.append(f"results_interpretation_plan[{idx}].{field} too thin")
        missing = sorted(expected_artifacts - covered)
        if missing:
            issues.append(f"results_interpretation_plan missing {missing}")

    workflow = plan.get("revision_workflow")
    if not isinstance(workflow, dict):
        issues.append("revision_workflow must be an object")
    else:
        for field in ("outline_completed", "draft_after_plan", "self_critique_required"):
            if workflow.get(field) is not True:
                issues.append(f"revision_workflow.{field} must be true")
    return issues


def validate_self_critique(critique):
    issues = []
    if critique.get("verdict") != "PASS" or critique.get("ready_for_verification") is not True:
        issues.append("draft-self-critique must PASS and be ready")
    if word_count(critique.get("strongest_rejection_reason")) < 8:
        issues.append("strongest_rejection_reason too thin")
    for field in ("unsupported_leap_scan", "missing_rival_scan", "claim_strength_scan", "workflow_language_scan"):
        value = critique.get(field)
        if not isinstance(value, dict):
            issues.append(f"{field} must be an object")
            continue
        if value.get("status") not in {"PASS", "NOT_APPLICABLE", "REVISED"}:
            issues.append(f"{field}.status invalid")
        if word_count(value.get("summary")) < 6:
            issues.append(f"{field}.summary too thin")
    actions = critique.get("revision_actions")
    if not isinstance(actions, list) or not actions:
        issues.append("revision_actions must be nonempty")
    else:
        for idx, item in enumerate(actions):
            if not isinstance(item, dict) or word_count(item.get("action")) < 4:
                issues.append(f"revision_actions[{idx}].action too thin")
    return issues


def expect_pass(name, issues):
    if issues:
        raise AssertionError(f"{name} should pass, got: {issues[:8]}")


def expect_fail(name, issues, token):
    if not issues:
        raise AssertionError(f"{name} should fail")
    if token and not any(token in issue for issue in issues):
        raise AssertionError(f"{name} failed for wrong reason; expected token {token!r}, got {issues[:8]}")


contract = json.loads((skill_dir / "references" / "phase-contract.json").read_text())
phase_by_id = {str(item["id"]): item for item in contract["phases"]}
for phase_id, fields in {
    "2": {"source_role_matrix"},
    "3": {"claim_continuity", "mechanism_result_matrix", "robustness_claim_matrix", "limitation_scope_matrix"},
    "12": {"publication_readiness"},
    "13": {"drafting_plan", "self_critique"},
}.items():
    missing = sorted(fields - set(phase_by_id[phase_id].get("pass_schema", [])))
    if missing:
        raise AssertionError(f"phase {phase_id} missing pass_schema fields {missing}")

verify_text = (skill_dir / "scripts" / "auto-research-verify.sh").read_text()
for token in (
    "Phase 2 source_role_matrix",
    "Phase 3 design-to-writing continuity",
    "Phase 12 publication_readiness gate",
    "Phase 13 drafting-plan is incomplete",
    "Phase 13 draft-self-critique is incomplete",
):
    if token not in verify_text:
        raise AssertionError(f"verifier missing expected publication-quality token: {token}")

roles = [
    "theory",
    "mechanism",
    "rival",
    "method",
    "design",
    "context",
    "population",
    "domain",
    "data",
    "empirical_prior",
    "journal_canon",
    "mechanism",
]
good_source_matrix = {
    "source_role_matrix": [
        {
            "key": f"GenericSource{idx:02d}",
            "argument_role": role,
            "claim_supported": "supports a specific manuscript claim",
            "target_section": "Literature Review and Theory",
            "why_it_matters": "prevents generic citation padding",
        }
        for idx, role in enumerate(roles, start=1)
    ]
}
bad_source_matrix = {"source_role_matrix": [{"key": f"Source{idx}", "argument_role": "background"} for idx in range(12)]}
expect_pass("good source role matrix", validate_source_role_matrix(good_source_matrix))
expect_fail("bad source role matrix", validate_source_role_matrix(bad_source_matrix), "missing source role group")

good_design = {
    "identification_claim_strength": "associational",
    "robustness_plan_count": 2,
    "claim_continuity": {
        "claim_strength": "associational",
        "mechanisms_carried_forward": True,
        "hypotheses_carried_forward": True,
        "robustness_carried_forward": True,
        "limitations_carried_forward": True,
        "manuscript_claim_boundary": "The manuscript will state bounded associational claims with no causal overreach.",
    },
    "mechanism_result_matrix": [
        {
            "mechanism": "resource strain mechanism",
            "model_or_spec": "primary adjusted model",
            "expected_pattern": "larger coefficient among constrained households",
            "manuscript_implication": "supports bounded mechanism discussion",
        }
    ],
    "robustness_claim_matrix": [
        {
            "robustness_check": "alternative outcome scale",
            "claim_implication": "main association remains substantively similar",
            "weaken_or_bound_rule": "downgrade claim if sign changes",
        },
        {
            "robustness_check": "additional baseline controls",
            "claim_implication": "supports cautious descriptive interpretation",
            "weaken_or_bound_rule": "bound conclusion if interval widens",
        },
    ],
    "limitation_scope_matrix": [
        {
            "limitation": "unobserved household shocks",
            "scope_language": "claims remain associational within observed survey scope",
            "affected_claim": "headline association claim",
        }
    ],
}
bad_design = copy.deepcopy(good_design)
bad_design.pop("mechanism_result_matrix")
bad_design["claim_continuity"]["mechanisms_carried_forward"] = False
expect_pass("good design continuity", validate_design_continuity(good_design))
expect_fail("bad design continuity", validate_design_continuity(bad_design), "mechanism")

generic_blueprint = {
    "result_hierarchy": [
        {"artifact_path": "tables/model-1.csv", "headline_status": "headline"},
        {"artifact_path": "figures/diagnostic-1.png", "headline_status": "supporting"},
    ],
    "publication_readiness": {
        "status": "PASS",
        "ready_for_drafting": True,
        "route_back_if_not_ready": False,
        "contribution_sentence": "The paper clarifies a bounded family-process mechanism using transparent observational evidence.",
        "target_journal_novelty_claim": "The manuscript contributes to the target journal by linking mechanism, measurement, and scope more explicitly than prior work.",
        "target_journal_fit": "The study addresses the journal audience with family mechanisms and careful empirical boundaries.",
        "mechanism_rival_matrix": [
            {
                "role": "mechanism",
                "label": "resource strain mechanism",
                "evidence_link": "primary model and mechanism-aligned heterogeneity",
                "claim_implication": "supports cautious process interpretation",
            },
            {
                "role": "rival",
                "label": "selection into exposure",
                "evidence_link": "baseline covariates and sensitivity checks",
                "claim_implication": "bounds rather than eliminates alternative explanations",
            },
        ],
        "evidence_claim_map": [
            {
                "claim": "headline association is negative",
                "evidence_type": "model output",
                "claim_strength": "associational bounded",
                "claim_status": "headline",
                "artifact_path": "tables/model-1.csv",
            },
            {
                "claim": "unobserved shocks remain a limitation",
                "evidence_type": "design limitation",
                "claim_strength": "scope condition",
                "claim_status": "limitation",
                "limitation": "unobserved household shocks",
            },
        ],
        "reviewer_risk_register": [
            {
                "risk_type": "strongest rejection reason",
                "strongest_rejection_reason": True,
                "objection": "The design may not justify the implied causal language.",
                "required_response": "Use bounded associational language and route claims through robustness evidence.",
                "route_back_phase": "3",
            },
            {
                "risk_type": "measurement objection",
                "objection": "The outcome may not capture the intended construct.",
                "required_response": "Explain construct validity and report alternative measurement checks.",
                "route_back_phase": "4",
            },
            {
                "risk_type": "novelty objection",
                "objection": "The contribution may read like a routine replication.",
                "required_response": "Tie novelty to mechanism, scope, and journal-specific debate.",
                "route_back_phase": "2",
            },
        ],
    },
}
bad_blueprint = copy.deepcopy(generic_blueprint)
bad_blueprint["publication_readiness"]["mechanism_rival_matrix"] = [bad_blueprint["publication_readiness"]["mechanism_rival_matrix"][0]]
expect_pass("good publication readiness", validate_publication_readiness(generic_blueprint))
expect_fail("bad publication readiness", validate_publication_readiness(bad_blueprint), "rival")

sections = {"abstract", "introduction", "background", "data and methods", "results", "discussion"}
good_drafting_plan = {
    "verdict": "PASS",
    "source_phase": "13",
    "section_briefs": {
        section: {
            "section_purpose": "state the specific contribution for readers",
            "key_claim": "make a bounded and evidence-linked claim",
            "required_evidence": ["publication readiness evidence map"],
            "source_roles": ["theory", "mechanism"],
            "forbidden_moves": ["workflow narration", "unsupported causal upgrade"],
        }
        for section in sections
    },
    "paragraph_purpose_map": [
        {
            "paragraph_id": f"paragraph {idx}",
            "section": section,
            "purpose": "develop section claim",
            "claim": "bounded evidence-linked claim",
            "source_roles": ["theory" if idx % 2 else "mechanism"],
        }
        for idx, section in enumerate(sections, start=1)
    ],
    "source_use_plan": [
        {
            "citation_key": f"GenericSource{idx:02d}",
            "argument_role": role,
            "target_section": "Background and theory section",
            "claim_supported": "supports a specific argument",
            "why_necessary": "anchors evidence in literature",
        }
        for idx, role in enumerate(["theory", "mechanism", "rival", "method", "design", "context", "population", "domain", "data", "empirical_prior"], start=1)
    ],
    "results_interpretation_plan": [
        {
            "artifact_path": "tables/model-1.csv",
            "interpretive_claim": "the headline estimate supports a bounded association",
            "uncertainty_language": "confidence intervals require cautious interpretation",
            "mechanism_link": "pattern is consistent with resource strain",
            "limitation_language": "unobserved shocks still limit inference",
        },
        {
            "artifact_path": "figures/diagnostic-1.png",
            "interpretive_claim": "diagnostic evidence supports model transparency",
            "uncertainty_language": "visual diagnostics do not prove identification",
            "mechanism_link": "diagnostic pattern contextualizes mechanism evidence",
            "limitation_language": "diagnostics cannot resolve all selection concerns",
        },
    ],
    "revision_workflow": {
        "outline_completed": True,
        "draft_after_plan": True,
        "self_critique_required": True,
    },
}
bad_drafting_plan = {
    "verdict": "PASS",
    "source_phase": "13",
    "source_use_plan": [{"citation_key": f"Source{idx}"} for idx in range(10)],
}
expect_pass("good drafting plan", validate_drafting_plan(good_drafting_plan, generic_blueprint))
expect_fail("bad drafting plan", validate_drafting_plan(bad_drafting_plan, generic_blueprint), "section_briefs")

good_critique = {
    "verdict": "PASS",
    "ready_for_verification": True,
    "strongest_rejection_reason": "Reviewers may reject the paper if claims exceed the observational design.",
    "unsupported_leap_scan": {"status": "REVISED", "summary": "Revised claims that moved beyond available evidence."},
    "missing_rival_scan": {"status": "PASS", "summary": "Rival selection explanations are named and bounded."},
    "claim_strength_scan": {"status": "PASS", "summary": "All claims use associational language consistently."},
    "workflow_language_scan": {"status": "PASS", "summary": "No internal workflow terms remain visible."},
    "revision_actions": [{"action": "tightened causal language in contribution paragraph"}],
}
bad_critique = {
    "verdict": "PASS",
    "ready_for_verification": True,
    "strongest_rejection_reason": "Looks fine.",
}
expect_pass("good draft self critique", validate_self_critique(good_critique))
expect_fail("bad draft self critique", validate_self_critique(bad_critique), "strongest_rejection_reason")

print("auto-research publication-quality fixture test: PASS")
print("  synthetic gates: source roles, design continuity, publication readiness, drafting plan, self-critique")
print("  project data used: none")
PY
