#!/usr/bin/env bash
set -euo pipefail

SKILL_DIR="${SCHOLAR_AUTO_RESEARCH_TEST_SKILL_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
VERIFY="$SKILL_DIR/scripts/auto-research-verify.sh"

for tool in pandoc xelatex pdfinfo pdftotext pdftoppm; do
  command -v "$tool" >/dev/null 2>&1 || { echo "FAIL: required format test tool missing: $tool" >&2; exit 1; }
done

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/scholar-format-authenticity.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

python3 - "$VERIFY" "$TMP_ROOT" <<'PY'
import ast, pathlib, re, shutil, subprocess, sys, tempfile, unicodedata, zipfile
import xml.etree.ElementTree as ET
from collections import Counter

verify_path = pathlib.Path(sys.argv[1])
root = pathlib.Path(sys.argv[2])
shell = verify_path.read_text()
python_source = shell.split("<<'PY'", 1)[1].rsplit("\nPY", 1)[0]
tree = ast.parse(python_source)
wanted = {
    "strip_comments", "visible_markdown_text", "normalize_locator_sentence",
    "_semantic_tokens", "_content_correspondence_issues", "validate_format_trio",
}
module = ast.Module(body=[n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name in wanted], type_ignores=[])
ns = dict(re=re, shutil=shutil, subprocess=subprocess, tempfile=tempfile,
          unicodedata=unicodedata, zipfile=zipfile, ET=ET, Counter=Counter, Path=pathlib.Path)
exec(compile(module, str(verify_path), "exec"), ns)
validate = ns["validate_format_trio"]

paragraph = " ".join(
    "This section presents substantive evidence and interpretation for a reproducible social science manuscript."
    for _ in range(12)
)
markdown = "# Test Paper\n\n" + "\n\n".join(
    f"## {heading}\n\n{paragraph}" for heading in
    ("Abstract", "Introduction", "Data and Methods", "Results", "Discussion", "Conclusion")
) + "\n"
md = root / "paper.md"; docx = root / "paper.docx"; tex = root / "paper.tex"; pdf = root / "paper.pdf"
md.write_text(markdown)
subprocess.run(["pandoc", str(md), "-o", str(docx)], check=True)
subprocess.run(["pandoc", "-s", str(md), "-o", str(tex)], check=True)
subprocess.run(["pandoc", str(md), "-o", str(pdf), "--pdf-engine=xelatex"], check=True)
positive_issues = validate(markdown, docx, tex, pdf, "positive")
assert positive_issues == [], positive_issues

good_docx = docx.read_bytes(); good_tex = tex.read_bytes(); good_pdf = pdf.read_bytes()
title = root / "title.md"; title.write_text("# Test Paper\n")
subprocess.run(["pandoc", str(title), "-o", str(docx)], check=True)
issues = validate(markdown, docx, tex, pdf, "negative")
assert any("DOCX: extracted substantive text is too short" in issue for issue in issues), issues
docx.write_bytes(good_docx)

with zipfile.ZipFile(docx, "w") as zf:
    zf.writestr("[Content_Types].xml", "not xml")
    zf.writestr("_rels/.rels", "not xml")
    zf.writestr("word/document.xml", markdown)
issues = validate(markdown, docx, tex, pdf, "negative")
assert any("DOCX: invalid OPC package" in issue for issue in issues), issues
docx.write_bytes(good_docx)

tex.write_text("\\documentclass{article}\n\\begin{document}\nTitle only.\n\\end{document}\n")
issues = validate(markdown, docx, tex, pdf, "negative")
assert any("TeX: extracted substantive text is too short" in issue for issue in issues), issues
tex.write_bytes(good_tex)

pdf.write_bytes(b"%PDF-1.4\n%%EOF\n")
issues = validate(markdown, docx, tex, pdf, "negative")
assert any("PDF: pdfinfo/pdftotext parse failed" in issue for issue in issues), issues
pdf.write_bytes(good_pdf)

tex.write_text("\\documentclass{article}\n\\begin{document}x\\includegraphics*[width=1pt]{/tmp/outside.png}\\end{document}\n")
issues = validate(markdown, docx, tex, pdf, "negative")
assert any("TeX: input escapes isolated source tree" in issue for issue in issues), issues

missing_results = re.sub(r"(?ms)^## Results\n.*?(?=^## Discussion)", "", markdown)
missing_md = root / "missing.md"; missing_docx = root / "missing.docx"
missing_tex = root / "missing.tex"; missing_pdf = root / "missing.pdf"
missing_md.write_text(missing_results)
subprocess.run(["pandoc", str(missing_md), "-o", str(missing_docx)], check=True)
subprocess.run(["pandoc", "-s", str(missing_md), "-o", str(missing_tex)], check=True)
subprocess.run(["pandoc", str(missing_md), "-o", str(missing_pdf), "--pdf-engine=xelatex"], check=True)
issues = validate(markdown, missing_docx, missing_tex, missing_pdf, "negative")
assert any("expected section labels missing: Results" in issue for issue in issues), issues

print("PASS: production-built DOCX, TeX, and PDF materially correspond to canonical Markdown")
print("PASS: invalid OPC, title-only/missing-section formats, malformed PDF, and TeX escapes fail distinctly")
PY
