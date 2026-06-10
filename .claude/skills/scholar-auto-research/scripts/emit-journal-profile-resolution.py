#!/usr/bin/env python3
"""Emit canonical journal_profile_resolution JSON for scholar-auto-research.

This script is intentionally small and deterministic. It reads
references/journal-profile-resolution-templates.json, the same template file
used by auto-research-verify.sh, so ASR fallback profiles cannot drift into a
generic article shell.
"""

import argparse
import json
import re
import sys
from pathlib import Path


def norm(value):
    return re.sub(r"\s+", " ", re.sub(r"[^a-z0-9]+", " ", str(value).lower())).strip()


def load_templates():
    script_dir = Path(__file__).resolve().parent
    path = script_dir.parent / "references" / "journal-profile-resolution-templates.json"
    try:
        return json.loads(path.read_text())
    except Exception as exc:
        raise SystemExit(f"failed to read journal profile templates at {path}: {exc}")


def resolve_profile_key(templates, journal):
    aliases = templates.get("aliases", {})
    token = norm(journal)
    return aliases.get(token, token)


def profile_for(templates, journal):
    key = resolve_profile_key(templates, journal)
    profile = templates.get("profiles", {}).get(key)
    if not isinstance(profile, dict):
        known = ", ".join(sorted(templates.get("profiles", {})))
        raise SystemExit(f"unknown built-in journal profile: {journal!r}. Known: {known}")
    return key, profile


def build_structure(profile):
    return {
        "profile_source": profile.get("profile_source", "journal-profile-resolution-templates.json"),
        "section_sequence": profile.get("resolution_section_sequence") or profile.get("section_sequence", []),
        "results_before_methods": profile.get("results_before_methods"),
        "theory_presentation": profile.get("theory_presentation"),
        "methods_section_label": profile.get("resolution_methods_section_label") or profile.get("methods_section_label"),
        "discussion_conclusion_policy": profile.get("discussion_conclusion_policy"),
        "supplement_policy": profile.get("supplement_policy"),
    }


def build_display(profile):
    display = profile.get("resolution_display_architecture") or profile.get("display_architecture")
    if not isinstance(display, dict):
        raise SystemExit(f"profile {profile.get('name')} is missing display architecture")
    required_defaults = {
        "main_text_display_cap": None,
        "main_text_table_cap": None,
        "main_text_figure_cap": None,
        "supplement_label_prefix": "Appendix",
        "panel_label_style": "A_B_C",
        "display_callout_style": "numbered_tables_and_figures",
    }
    out = dict(display)
    for key, value in required_defaults.items():
        out.setdefault(key, value)
    return out


def build_resolution(args):
    templates = load_templates()
    origin = args.origin
    requested = args.requested.strip()
    if not requested:
        raise SystemExit("--requested is required")

    if origin == "fallback_asr":
        fallback_key = templates.get("fallback_profile_key", "american sociological review")
        profile = templates.get("profiles", {}).get(fallback_key)
        if not isinstance(profile, dict):
            raise SystemExit("fallback_profile_key is missing from templates")
        if not args.fallback_reason or len(args.fallback_reason.split()) < 4:
            raise SystemExit("fallback_asr requires --fallback-reason with at least four words")
        return {
            "requested_journal": requested,
            "resolved_profile_name": profile["name"],
            "profile_origin": "fallback_asr",
            "profile_source_engine": "scholar-journal",
            "source_strategy": "asr_fallback",
            "web_lookup_attempted": True,
            "fallback_used": True,
            "fallback_reason": args.fallback_reason,
            "journal_structure": build_structure(profile),
            "display_architecture": build_display(profile),
        }

    if origin == "built_in":
        resolved_name = args.resolved or requested
        _, profile = profile_for(templates, resolved_name)
        return {
            "requested_journal": requested,
            "resolved_profile_name": profile["name"],
            "profile_origin": "built_in",
            "profile_source_engine": "scholar-journal",
            "source_strategy": "built_in_catalog",
            "web_lookup_attempted": bool(args.web_lookup_attempted),
            "fallback_used": False,
            "fallback_reason": "",
            "journal_structure": build_structure(profile),
            "display_architecture": build_display(profile),
        }

    if origin == "imported_custom":
        if not args.custom_profile_json:
            raise SystemExit("imported_custom requires --custom-profile-json")
        try:
            custom = json.loads(Path(args.custom_profile_json).read_text())
        except Exception as exc:
            raise SystemExit(f"failed to read custom profile JSON: {exc}")
        for key in ("journal_structure", "display_architecture"):
            if key not in custom:
                raise SystemExit(f"custom profile JSON missing {key}")
        return {
            "requested_journal": requested,
            "resolved_profile_name": args.resolved or requested,
            "profile_origin": "imported_custom",
            "profile_source_engine": "scholar-journal",
            "source_strategy": "web_fetched_profile",
            "web_lookup_attempted": True,
            "fallback_used": False,
            "fallback_reason": "",
            "journal_structure": custom["journal_structure"],
            "display_architecture": custom["display_architecture"],
        }

    raise SystemExit(f"unsupported origin: {origin}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--requested", required=True)
    parser.add_argument("--resolved", default="")
    parser.add_argument("--origin", choices=["built_in", "imported_custom", "fallback_asr"], required=True)
    parser.add_argument("--fallback-reason", default="")
    parser.add_argument("--custom-profile-json", default="")
    parser.add_argument("--web-lookup-attempted", action="store_true")
    args = parser.parse_args()
    print(json.dumps(build_resolution(args), sort_keys=True))


if __name__ == "__main__":
    main()
