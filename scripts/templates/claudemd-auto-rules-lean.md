# Open Scholar Skill — Cross-Skill Rules

This block is **auto-managed** by `/scholar-init` Step 1.2.5 via `scripts/phases/setup-project-claudemd.sh`. Edits between the BEGIN/END markers are overwritten on the next `/scholar-init` run. Put project-specific content OUTSIDE the markers.

These are the rules that apply across every scholar-* skill in this fork. Because Open Scholar Skill is a modular, researcher-in-the-loop suite (no full-paper orchestrator), this block is the complete cross-skill contract — there is no separate "full" profile to upgrade to. Run each skill individually; this block is what each standalone invocation (`/scholar-eda`, `/scholar-analyze`, `/scholar-write`, `/scholar-respond`, …) auto-loads so the rules below bind every session in this project directory.

Path key throughout: `<plugin>` resolves to `${SCHOLAR_SKILL_DIR}` — your Open Scholar Skill install (the directory containing `scripts/` and `.claude/skills/`).

---

## §A. No destructive regex on manuscript files

`sed -i`, `re.sub`, and one-line bash regex passes silently break `[CITATION NEEDED]` markers, citation provenance, anchor-verify tags, and structural anchors. Use the `Edit` tool with explicit `old_string`/`new_string`, or invoke the dedicated skill (`/scholar-polish`, `/scholar-citation`, `/scholar-write revise`).

---

## §B. Objectivity Mandate — no sycophancy

Do not validate ideas, hypotheses, results, or drafts to please the user. Do not open with praise ("Great question," "Excellent point"). Do not inflate novelty / significance / evidentiary strength. Do not soften negative findings.

Report what the data, code, literature, or text actually shows — null results as null, weak effects as weak, contradictory citations as contradictory, methodological flaws with the specific location, prose that overreaches as overreaching. When the user proposes something wrong or weak, say so plainly with the specific reason. Disagreement with the user is required when the evidence demands it. Hedging language must reflect genuine uncertainty, not social cushioning.

**Factual honesty about your own state.** Do not fabricate file paths, function names, line numbers, citations, or claims that something exists, runs, or is done. Before claiming X works / exists / is done, run the check — do not infer from naming. When you haven't verified, say "I haven't checked — verifying now" and verify. When the answer is unknown, say "I don't know" and either look it up or stop. Reporting a task complete requires the artifact present and the test passing.

Applies to every skill, every reviewer / verify agent, every user-facing response. Source: `<plugin>/.claude/skills/_shared/objectivity-mandate.md` (rules 1–8).

---

## §C. Data safety stack — LOCAL_MODE scope

Three layers (full text in `<plugin>/.claude/skills/_shared/data-handling-policy.md`):

1. **Policy** — `_shared/data-handling-policy.md`. Five `SAFETY_STATUS` values: `CLEARED`, `LOCAL_MODE`, `ANONYMIZED`, `OVERRIDE`, `HALTED`. LOCAL_MODE execution contract uses `Rscript -e` / `python3 -c` heredocs; forbidden verbs: `head(df)`, `print(df)`, `df.head()`, `df.sample()`.
2. **Ingestion** — `/scholar-init` writes `.claude/safety-status.json`.
{{ENFORCEMENT_BLOCK}}

**LOCAL_MODE scope clarification.** LOCAL_MODE applies to *data values and rows* — `.dta` / `.csv` / `.sav` files and any row-level derivatives. It does NOT prohibit cross-model code review of `scripts/*.R` or `scripts/*.py` files — those contain variable construction logic and estimator setup, not respondent-level values. Excusing a cloud reviewer under a LOCAL_MODE-data-prohibition rationale when the artifact is code (not data) is a category error.

---

## §D. Citation rules

- **Zero tolerance for fabrication.** Run `bash <plugin>/scripts/gates/verify-citations.sh <draft>` before finalizing.
- 7-tier verification order: Knowledge Graph → Local Library (Zotero/Mendeley/BibTeX/EndNote) → CrossRef → Semantic Scholar → OpenAlex → Google Scholar → WebSearch.
- Unverified claims flagged as `[CITATION NEEDED]` — never erased without verification.
- **Inherited citations from a prior project do NOT substitute** for a fresh `scholar_search` query on the current topic's keywords. Cross-project lit reuse is convenience, not provenance.

---

## §E. Cross-skill workflow rules

- **File versioning.** Run `bash <plugin>/scripts/gates/version-check.sh <output_dir> <filename_stem>` before every Write call; use the printed `SAVE_PATH`. Never overwrite existing drafts.
- **LaTeX.** Use `xelatex` (not `pdflatex`) for Unicode. Verify the compiled PDF exists and spot-check content.
- **Figures.** Source `viz_setting.R` (custom theme) — never default ggplot2 themes. Never define `theme_Publication()` inline.
- **Code comments.** Every line of R / Python / Stata / Julia code must have an inline comment explaining what + why.
- **Verification protocol.** After edits: (1) confirm file exists; (2) extract text to confirm changes; (3) report what you see, not what you expect.

{{CONDITIONAL_RULES}}

---

*Auto-generated by `/scholar-init` Step 1.2.5. This is the complete cross-skill rule set for Open Scholar Skill — a modular, researcher-in-the-loop suite with no full-paper orchestrator. Subsequent `/scholar-init` runs refresh this block idempotently; project-specific content outside the markers is preserved.*
