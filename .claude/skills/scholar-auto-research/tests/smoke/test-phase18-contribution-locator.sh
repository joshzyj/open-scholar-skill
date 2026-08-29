#!/usr/bin/env bash
set -euo pipefail

SKILL_DIR="${SCHOLAR_AUTO_RESEARCH_TEST_SKILL_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
VERIFY="$SKILL_DIR/scripts/auto-research-verify.sh"

python3 - "$VERIFY" <<'PY'
import ast
import re
import sys
import unicodedata

shell = open(sys.argv[1], encoding="utf-8").read()
python_source = shell.split("<<'PY'", 1)[1].rsplit("\nPY", 1)[0]
tree = ast.parse(python_source)
wanted = {
    "strip_comments",
    "strip_yaml_frontmatter_preserve_lines",
    "normalize_locator_sentence",
    "substantive_sentence_locations",
}
module = ast.Module(
    body=[node for node in tree.body if isinstance(node, ast.FunctionDef) and node.name in wanted],
    type_ignores=[],
)
namespace = {"re": re, "unicodedata": unicodedata}
exec(compile(module, sys.argv[1], "exec"), namespace)
locate = namespace["substantive_sentence_locations"]

sentence = "Our analysis identifies a bounded and theoretically specific contribution to family inequality research."
genuine = f"""---
title: Test
---
# Paper
## Introduction

{sentence}
"""
records = locate(genuine)
match = next(item for item in records if item["sentence"] == sentence)
assert match["section"] == "introduction"
assert match["line_start"] == 7

excluded = [
    f"## References and Notes\n\n{sentence}\n",
    f"## Introduction\n\nAuthor | Finding\nSmith | {sentence}\n",
    f"## Introduction\n\n<table><tr><td>{sentence}</td></tr></table>\n",
    f"## Introduction\n\n<!-- {sentence} -->\n",
    f"## Introduction\n\n_Figure 1. {sentence}_\n",
    f"## Introduction\n\n<div hidden>{sentence}</div>\n",
    f"## Introduction\n\n<span style=\"display:none\">{sentence}</span>\n",
    f"## Introduction\n\n<meta content=\"{sentence}\">\n",
]
for case in excluded:
    assert sentence not in {item["sentence"] for item in locate(case)}, case

typographic = "Our analysis identifies a bounded—and theoretically specific—contribution to family inequality research."
ascii_form = "Our analysis identifies a bounded-and theoretically specific-contribution to family inequality research."
record = locate(f"## Discussion\n\n{typographic}\n")[0]
assert namespace["normalize_locator_sentence"](ascii_form) == record["sentence"]
print("PASS: Phase 18 locators require exact visible-prose sentence, section, and line membership")
print("PASS: references, tables, HTML, comments, and captions cannot satisfy contribution membership")
PY
