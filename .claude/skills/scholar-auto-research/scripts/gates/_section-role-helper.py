#!/usr/bin/env python3
"""Shared section-role gate logic for scholar-auto-research manuscripts."""

from __future__ import annotations

import json
import os
import re
import sys
from collections import Counter
from pathlib import Path


EMPIRICAL_MARKERS = re.compile(
    r"\b(data|survey|sample|respondent|corpus|records|interview|experiment|model|regression|"
    r"logit|ols|cox|survival|matching|propensity|fixed effects?|panel|did|estimate|analysis)\b",
    re.I,
)

STOPWORDS = {
    "about",
    "across",
    "after",
    "again",
    "against",
    "among",
    "analysis",
    "article",
    "because",
    "before",
    "being",
    "between",
    "could",
    "data",
    "different",
    "during",
    "evidence",
    "findings",
    "first",
    "from",
    "have",
    "however",
    "important",
    "information",
    "into",
    "methods",
    "model",
    "paper",
    "research",
    "results",
    "second",
    "section",
    "should",
    "social",
    "study",
    "their",
    "these",
    "this",
    "through",
    "using",
    "which",
    "while",
    "with",
    "would",
}


def emit(status: str, reason: str, details: list[str] | None = None) -> int:
    print(f"STATUS={status}")
    print(f"REASON={reason}")
    for detail in details or []:
        print(f"DETAIL: {detail}")
    return 1 if status == "RED" else 0


def read_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        return path.read_text(encoding="utf-8", errors="replace")


def strip_yaml(text: str) -> str:
    if text.startswith("---"):
        end = text.find("\n---", 3)
        if end != -1:
            return text[end + 4 :]
    return text


def sections(text: str) -> list[dict[str, object]]:
    body = strip_yaml(text)
    matches = list(re.finditer(r"(?m)^(#{1,6})\s+(.+?)\s*$", body))
    out: list[dict[str, object]] = []
    for i, match in enumerate(matches):
        start = match.end()
        end = matches[i + 1].start() if i + 1 < len(matches) else len(body)
        out.append(
            {
                "level": len(match.group(1)),
                "title": match.group(2).strip(),
                "start": match.start(),
                "body": body[start:end],
            }
        )
    return out


def find_section(text: str, title_re: str) -> tuple[str, dict[str, object] | None]:
    parsed = sections(text)
    pattern = re.compile(title_re, re.I)
    for i, sec in enumerate(parsed):
        if pattern.search(str(sec["title"])):
            level = int(sec["level"])
            end_index = len(parsed)
            for j in range(i + 1, len(parsed)):
                if int(parsed[j]["level"]) <= level:
                    end_index = j
                    break
            if end_index == i + 1:
                return str(sec["body"]), sec
            start = int(sec["start"])
            end = int(parsed[end_index]["start"]) if end_index < len(parsed) else len(strip_yaml(text))
            return strip_yaml(text)[start:end], sec
    return "", None


def find_theory_block(text: str) -> tuple[str, dict[str, object] | None]:
    parsed = sections(text)
    start_re = re.compile(
        r"\b(theor\w*|hypothes\w*|conceptual|literature|background|framework|perspective|argument)\b",
        re.I,
    )
    stop_re = re.compile(
        r"\b(data|sample|method|variable|measure|analytic|analysis|estimation|result|finding|"
        r"robustness|discussion|conclusion)\b",
        re.I,
    )
    for i, sec in enumerate(parsed):
        title = str(sec["title"])
        if start_re.search(title) and not stop_re.search(title):
            level = int(sec["level"])
            end_index = len(parsed)
            for j in range(i + 1, len(parsed)):
                next_title = str(parsed[j]["title"])
                if int(parsed[j]["level"]) <= level and stop_re.search(next_title):
                    end_index = j
                    break
            start = int(sec["start"])
            end = int(parsed[end_index]["start"]) if end_index < len(parsed) else len(strip_yaml(text))
            return strip_yaml(text)[start:end], sec
    return "", None


def child_heading_count(block: str) -> int:
    return len(re.findall(r"(?m)^#{3,6}\s+\S", block))


def word_count(text: str) -> int:
    return len(re.findall(r"[A-Za-z][A-Za-z'-]*", text))


def has_any(text: str, patterns: list[str]) -> bool:
    return any(re.search(pattern, text, re.I | re.M) for pattern in patterns)


def count_any(text: str, patterns: list[str]) -> int:
    return sum(1 for pattern in patterns if re.search(pattern, text, re.I | re.M))


def project_has_empirical_inputs(project: Path) -> bool:
    likely_files = [
        project / "config" / "research-question.json",
        project / "config" / "project-spec.json",
        project / "design" / "research-design.md",
        project / "analysis" / "analysis-plan.md",
        project / "analysis" / "spec-registry.csv",
        project / "logs" / "project-state.md",
    ]
    for path in likely_files:
        if path.exists() and EMPIRICAL_MARKERS.search(read_text(path)):
            return True
    return any((project / "data" / sub).exists() for sub in ("raw", "processed", "analysis", "interim"))


def phase_manuscripts(project: Path) -> list[Path]:
    """Return present manuscript files across BOTH pipeline layouts.

    Path-adapt (master-plan-v4 P1+Update 10): scholar-auto-research uses
    `manuscript/`, `final/`, `submission/` directories; scholar-full-paper
    uses `drafts/manuscript-final-*.md`, `drafts/manuscript-submission-*.md`,
    `drafts/draft-manuscript-*.md`. The helper searches both. For the
    auto-research-only Phase 13/18 mode (signaled by env var), only the
    canonical draft is returned.
    """
    phase = os.environ.get("AUTO_RESEARCH_VERIFY_PHASE", "")
    draft = project / "manuscript" / "manuscript-draft.md"
    if phase in {"13", "18"}:
        return [draft] if draft.exists() else []
    candidates = [
        draft,
        project / "final" / "manuscript-final.md",
        project / "submission" / "manuscript-submission.md",
    ]
    drafts_dir = project / "drafts"
    if drafts_dir.is_dir():
        # Pick newest match for each canonical full-paper pattern.
        for pat in ("manuscript-final-*.md", "manuscript-submission-*.md",
                    "draft-manuscript-*.md"):
            matches = sorted(drafts_dir.glob(pat),
                             key=lambda p: p.stat().st_mtime, reverse=True)
            if matches:
                candidates.append(matches[0])
    present = [p for p in candidates if p.exists()]
    # Generic fallback: hand-named experimental manuscripts under drafts/.
    # Only fires when no canonical match was found.
    if not present and drafts_dir.is_dir():
        skip_prefixes = ("scholar-lrh-", "scholar-write-log-",
                         "scholar-polish-",
                         "manuscript-tables-figures-captions-",
                         "manuscript-section-")
        fallback = [
            f for f in drafts_dir.glob("manuscript-*.md")
            if not any(f.name.startswith(s) for s in skip_prefixes)
        ]
        fallback.sort(key=lambda p: p.stat().st_mtime, reverse=True)
        if fallback:
            present = [fallback[0]]
    return present


def rel(project: Path, path: Path) -> str:
    try:
        return str(path.relative_to(project))
    except ValueError:
        return str(path)


def canonical_hypotheses(project: Path) -> list[str]:
    path = project / "citations" / "hypotheses-canonical.json"
    if not path.exists():
        return []
    try:
        payload = json.loads(read_text(path))
    except Exception:
        return []
    items = payload.get("hypotheses", payload if isinstance(payload, list) else [])
    ids: list[str] = []
    if isinstance(items, list):
        for i, item in enumerate(items, start=1):
            if isinstance(item, dict):
                ids.append(str(item.get("id") or item.get("label") or f"H{i}"))
            elif isinstance(item, str):
                match = re.match(r"\s*(H\d+[a-z]?)", item, re.I)
                ids.append(match.group(1).upper() if match else f"H{i}")
    return ids


def downstream_discussion_conclusion(text: str) -> tuple[str, bool]:
    discussion, discussion_sec = find_section(text, r"\bdiscussion\b")
    conclusion, conclusion_sec = find_section(text, r"\bconclusion\b")
    if conclusion_sec:
        return f"{discussion}\n{conclusion}", True
    return discussion, False


def conclusion_required(project: Path, text: str) -> bool:
    if find_section(text, r"\bconclusion\b")[1]:
        return True
    config_paths = [
        project / "config" / "journal-profile.json",
        project / "manuscript" / "journal-profile.json",
        project / "logs" / "project-state.md",
    ]
    pattern = re.compile(r"\b(split_required|separate conclusion|conclusion required|discussion_mode[^A-Za-z]+split)\b", re.I)
    return any(path.exists() and pattern.search(read_text(path)) for path in config_paths)


def content_terms(text: str, limit: int = 20) -> list[str]:
    words = [
        word.lower()
        for word in re.findall(r"[A-Za-z][A-Za-z'-]{4,}", text)
        if word.lower() not in STOPWORDS
    ]
    return [word for word, _ in Counter(words).most_common(limit)]


def check_introduction(project: Path, manuscripts: list[Path]) -> int:
    issues: list[str] = []
    for path in manuscripts:
        text = read_text(path)
        intro, sec = find_section(text, r"\bintroduction\b")
        if sec is None:
            issues.append(f"{rel(project, path)}: missing explicit Introduction section")
            continue
        moves = {
            "puzzle_or_importance": [r"\b(puzzle|question|dilemma|important|central|debate|problem|why)\b"],
            "literature_gap": [
                r"\b(literature|prior work|existing research|scholarship|gap|overlook|neglect|limited|unknown|unresolved)\b"
            ],
            "theory_or_contribution": [
                r"\b(theory|theoretical|framework|mechanism|perspective|account|contribution|advance|integrat|fuse)\b"
            ],
            "case_or_data_preview": [
                r"\b(data|survey|sample|corpus|records|cfps|gss|psid|respondent|employee|household|administrative|interview)\b"
            ],
            "method_preview": [
                r"\b(model|regression|cox|hazard|matching|propensity|fixed effect|logit|ols|estimate|analysis|computational|measure)\b"
            ],
            "findings_preview": [r"\b(find|show|result|evidence|suggest|reveal|demonstrate|support)\b"],
            "roadmap_or_article_scope": [
                r"\b(article|paper|study|analysis|remainder|first|then|finally|we test|i test)\b"
            ],
        }
        missing = [name for name, pats in moves.items() if not has_any(intro, pats)]
        if word_count(intro) < 250:
            issues.append(f"{rel(project, path)}: Introduction is too thin ({word_count(intro)} words)")
        if missing:
            issues.append(f"{rel(project, path)}: Introduction missing moves: {', '.join(missing)}")
    if issues:
        return emit("RED", "introduction_argument_architecture_incomplete", issues)
    return emit("GREEN", "introduction_argument_architecture_complete", [f"checked={len(manuscripts)}"])


def check_theory(project: Path, manuscripts: list[Path]) -> int:
    issues: list[str] = []
    for path in manuscripts:
        text = read_text(path)
        block, sec = find_theory_block(text)
        if sec is None:
            issues.append(f"{rel(project, path)}: missing theory/background/conceptual section")
            continue
        hypothesis_lines = len(re.findall(r"(?mi)^\s*(\*\*)?\s*H\d+[a-z]?\b|hypothesis\s+\d+", block))
        perspectives = len(re.findall(r"(?mi)^#{2,6}\s+.*\b(selection|causation|diffusion|mechanism|scope|rival|account|perspective|hypothes)", block))
        moves = {
            "concept_definition": [r"\b(define|definition|conceptualize|means|refers to|distinguish|concept|construct)\b"],
            "mechanism": [r"\b(mechanism|pathway|process|because|therefore|lead to|shapes?|links?|produces?)\b"],
            "rival_or_alternative": [r"\b(rival|alternative|competing|selection|causation|diffusion|by contrast|rather than)\b"],
            "scope_condition": [r"\b(scope|boundary|condition|context|heterogeneity|when|where|cohort|setting)\b"],
            "testable_expectations": [r"\b(hypothesis|hypotheses|expect|predict|anticipate|proposition)\b"],
        }
        missing = [name for name, pats in moves.items() if not has_any(block, pats)]
        memo_leakage_patterns = {
            "standalone_rival_scope_scaffold": [
                r"\bRival explanations are central\b",
                r"\bThere are also scope conditions\b",
                r"\bThese boundaries are not afterthoughts\b",
                r"\bThe theoretical task is to adjudicate among\b",
                r"\bThe broader literature supports this cautious stance\b",
            ],
            "methods_limitations_in_theory": [
                r"\bcomplete[- ]case analytic sample\b",
                r"\bunweighted complete[- ]case\b",
                r"\blocal extract\b",
                r"\bverified design weights\b",
                r"\bsingle survey year\b",
                r"\bdoes not include a clean\b",
                r"\bpartnered adults ages?\b",
            ],
            "post_results_theory_language": [
                r"\bempirical sections? (?:below|above)\b",
                r"\bthe data can support, weaken, or redirect\b",
                r"\bdiscussion treats that adjudication as the main result\b",
                r"\bthe evidence supports\b",
            ],
        }
        for label, pats in memo_leakage_patterns.items():
            hits = [pat for pat in pats if re.search(pat, block, re.I)]
            if hits:
                issues.append(f"{rel(project, path)}: theory contains {label}")
        citation_clusters = re.findall(r"\(([^()\n]{80,900})\)", block)
        for cluster in citation_clusters:
            semicolon_count = cluster.count(";")
            if semicolon_count >= 10:
                issues.append(f"{rel(project, path)}: theory contains oversized omnibus citation cluster")
                break
            if re.search(r"\b([A-Z][A-Za-z.\-]*(?:\s+et\s+al\.)?)\s+(\d{4}[a-z]?)\s*,\s*\2\b", cluster):
                issues.append(f"{rel(project, path)}: theory contains duplicated author-year citation")
                break
        if word_count(block) < 300:
            issues.append(f"{rel(project, path)}: theory block is too thin ({word_count(block)} words)")
        if child_heading_count(block) < 2 and hypothesis_lines < 2 and perspectives < 2:
            issues.append(
                f"{rel(project, path)}: theory is not organized by subheadings, perspectives, or explicit hypotheses"
            )
        if missing:
            issues.append(f"{rel(project, path)}: theory missing moves: {', '.join(missing)}")
    if issues:
        return emit("RED", "theory_structure_depth_incomplete", issues)
    return emit("GREEN", "theory_structure_depth_complete", [f"checked={len(manuscripts)}"])


def check_discussion(project: Path, manuscripts: list[Path]) -> int:
    issues: list[str] = []
    hids = canonical_hypotheses(project)
    for path in manuscripts:
        text = read_text(path)
        discussion, sec = find_section(text, r"\bdiscussion\b")
        if sec is None:
            issues.append(f"{rel(project, path)}: missing Discussion section")
            continue
        moves = {
            "answer_or_result_synthesis": [
                r"\b(this study|this article|the findings|the results|evidence|we find|i find|show|reveal|suggest)\b"
            ],
            "theory_or_hypothesis_adjudication": [
                r"\b(hypothesis|expectation|perspective|theory|account|support|consistent|contrary|revise|adjudicat)\b"
            ],
            "rival_or_selection_logic": [
                r"\b(rival|alternative|selection|endogeneity|unobserved|confound|reverse|scope|limitation|observational)\b"
            ],
            "mechanism_interpretation": [
                r"\b(mechanism|pathway|process|because|interpret|meaning|suggests that|indicates that)\b"
            ],
            "limitation_or_scope": [r"\b(limitation|limits|scope|cannot|does not|observational|generaliz|boundary)\b"],
            "contribution_or_implication": [
                r"\b(contribution|advance|literature|theory|understanding|implication)\b"
            ],
        }
        missing = [name for name, pats in moves.items() if not has_any(discussion, pats)]
        mentioned_hids = [hid for hid in hids if re.search(rf"\b{re.escape(hid)}\b", discussion, re.I)]
        if hids and not mentioned_hids and not has_any(discussion, [r"\b(hypothesis|expectation)\b"]):
            missing.append("canonical_hypothesis_adjudication")
        if word_count(discussion) < 200:
            issues.append(f"{rel(project, path)}: Discussion is too thin ({word_count(discussion)} words)")
        if missing:
            issues.append(f"{rel(project, path)}: Discussion missing moves: {', '.join(dict.fromkeys(missing))}")
        coefficient_terms = len(re.findall(r"\b(table|model|coefficient|odds ratio|hazard ratio|p\s*[<=>])\b", discussion, re.I))
        if coefficient_terms >= 8 and not has_any(discussion, moves["contribution_or_implication"]):
            issues.append(f"{rel(project, path)}: Discussion reads like coefficient reporting rather than interpretation")
    if issues:
        return emit("RED", "discussion_adjudication_incomplete", issues)
    return emit("GREEN", "discussion_adjudication_complete", [f"checked={len(manuscripts)}"])


def check_conclusion(project: Path, manuscripts: list[Path]) -> int:
    issues: list[str] = []
    checked = 0
    for path in manuscripts:
        text = read_text(path)
        conclusion, sec = find_section(text, r"\bconclusion\b")
        if sec is None:
            if conclusion_required(project, text):
                issues.append(f"{rel(project, path)}: missing separate Conclusion section required by journal profile")
            continue
        checked += 1
        moves = {
            "problem_synthesis": [r"\b(problem|question|puzzle|debate|what this study|this article)\b"],
            "theoretical_synthesis": [r"\b(theory|theoretical|conceptual|framework|account|argument)\b"],
            "empirical_grounding": [r"\b(findings|evidence|results|analysis|data)\b"],
            "contribution_or_implication": [
                r"\b(contribution|advance|implication|literature|understanding|sociology|field)\b"
            ],
            "scope_or_future": [r"\b(future|further|scope|boundary|limitation|generaliz|replication|research)\b"],
        }
        missing = [name for name, pats in moves.items() if not has_any(conclusion, pats)]
        if word_count(conclusion) < 150:
            issues.append(f"{rel(project, path)}: Conclusion is too thin ({word_count(conclusion)} words)")
        if missing:
            issues.append(f"{rel(project, path)}: Conclusion missing moves: {', '.join(missing)}")
        if re.search(r"\b(Table|Figure|Model)\s+\d|\bp\s*[<=>]|\bcoefficient\b|\bodds ratio\b|\bhazard ratio\b", conclusion, re.I):
            issues.append(f"{rel(project, path)}: Conclusion contains table/model/coefficient reporting")
        if (
            re.search(r"in conclusion, this (paper|study) has important implications|more research is needed", conclusion, re.I)
            and word_count(conclusion) < 250
        ):
            issues.append(f"{rel(project, path)}: Conclusion contains generic boilerplate without enough specific synthesis")
    if issues:
        return emit("RED", "conclusion_contribution_support_incomplete", issues)
    if checked == 0:
        return emit("INERT", "no_separate_conclusion_required_or_present", [f"checked={len(manuscripts)}"])
    return emit("GREEN", "conclusion_contribution_support_complete", [f"checked={checked}"])


def check_continuity(project: Path, manuscripts: list[Path]) -> int:
    issues: list[str] = []
    for path in manuscripts:
        text = read_text(path)
        intro, intro_sec = find_section(text, r"\bintroduction\b")
        downstream, has_conclusion = downstream_discussion_conclusion(text)
        if intro_sec is None:
            issues.append(f"{rel(project, path)}: cannot check continuity without Introduction")
            continue
        if not downstream.strip():
            issues.append(f"{rel(project, path)}: cannot check continuity without Discussion or Conclusion")
            continue
        terms = content_terms(intro, 25)
        overlap = [term for term in terms if re.search(rf"\b{re.escape(term)}\b", downstream, re.I)]
        required = 6 if word_count(intro) >= 500 else 4
        if len(overlap) < required:
            issues.append(
                f"{rel(project, path)}: weak intro-to-discussion/conclusion continuity "
                f"(shared_terms={len(overlap)}, required={required})"
            )
        if has_any(intro, [r"\b(hypothesis|expectation|theory|perspective|mechanism)\b"]) and not has_any(
            downstream, [r"\b(hypothesis|expectation|theory|perspective|account|mechanism)\b"]
        ):
            issues.append(f"{rel(project, path)}: theory/hypothesis promise in Introduction is not revisited later")
        if has_any(intro, [r"\b(contribution|advance|literature|gap)\b"]) and not has_any(
            downstream, [r"\b(contribution|advance|literature|understanding|implication)\b"]
        ):
            issues.append(f"{rel(project, path)}: contribution promise in Introduction is not closed later")
        if has_conclusion and has_any(downstream, [r"\b(Table|Figure|Model)\s+\d|\bp\s*[<=>]|\bcoefficient\b"]):
            discussion, _ = find_section(text, r"\bdiscussion\b")
            conclusion, _ = find_section(text, r"\bconclusion\b")
            if conclusion and re.search(r"\b(Table|Figure|Model)\s+\d|\bp\s*[<=>]|\bcoefficient\b", conclusion, re.I):
                issues.append(f"{rel(project, path)}: final closure reopens model/table reporting")
    if issues:
        return emit("RED", "cross_section_continuity_incomplete", issues)
    return emit("GREEN", "cross_section_continuity_complete", [f"checked={len(manuscripts)}"])


def main() -> int:
    if len(sys.argv) != 3:
        return emit("RED", "usage: _section-role-helper.py <mode> <project-dir>")
    mode = sys.argv[1]
    project = Path(sys.argv[2]).resolve()
    if not project.exists():
        return emit("RED", "project_dir_missing", [str(project)])
    if not project_has_empirical_inputs(project):
        return emit("INERT", "no_empirical_project_markers_detected")
    manuscripts = phase_manuscripts(project)
    if not manuscripts:
        return emit("INERT", "no_manuscript_files_found")
    if mode == "introduction":
        return check_introduction(project, manuscripts)
    if mode == "theory":
        return check_theory(project, manuscripts)
    if mode == "discussion":
        return check_discussion(project, manuscripts)
    if mode == "conclusion":
        return check_conclusion(project, manuscripts)
    if mode == "continuity":
        return check_continuity(project, manuscripts)
    return emit("RED", f"unknown_section_role_mode={mode}")


if __name__ == "__main__":
    raise SystemExit(main())
