# Final Assembly Contract

Phase 19 produces the canonical final manuscript set:

- `final/manuscript-final.md`
- `final/manuscript-final.docx`
- `final/manuscript-final.tex`
- `final/manuscript-final.pdf`
- `final/final-manifest.json`
- `final/LATEST.txt`
- immutable copies under `final/versions/<version_id>/`

## Source Rule

`final/manuscript-final.md` is the only source for the other three formats. It must derive from `manuscript/manuscript-draft.md` after Phase 18 has passed. Do not assemble from stale drafts, live output directories, reviewer memos, or a previously rendered final file.

`final/manuscript-final.md` is the reader-facing archival product, not the trace-rich verification draft. It should preserve substantive manuscript sections and any appendices allowed by the blueprint's `appendix_policy.final`, while excluding draft-only trace anchors and workflow scaffolding.
It must also be a rendered reader-facing manuscript: raw markdown citekeys, fake reference-key summaries, and figure captions without visible figure content are Phase 19 blockers.
It must also satisfy the Phase 12 blueprint's `journal_structure` and `display_architecture` so that journal-specific section order and table/figure policy survive into the reader-facing final manuscript.
It must not expose internal workflow language such as results locks, registries, manifests, phase numbers, route-back language, or provenance mechanics except inside hidden trace comments or appendices explicitly marked as audit material.
It must not expose registry/model-ladder tables as the main empirical Results table. Quantitative empirical final manuscripts must preserve the canonical regression table approved in Phase 13/18; provenance registries and row-per-spec extracts stay out of reader-facing final prose and tables. The main regression table block must continue to derive from the locked artifact named in `results-locked/manifest.json`; Phase 19 must NOT rebuild Table 1 from `tables/model-estimates.csv` or any other CSV. The gate `scripts/gates/locked-artifact-transclusion-check.sh` re-runs at Phase 19 — a hash mismatch routes back with reason `rebuild-from-locked-artifact`.
It must declare a manuscript title before the first `##` section heading, via either YAML frontmatter `title:` or a `# <Title>` H1 line. A final manuscript whose first non-comment line is `## Abstract` fails `scripts/gates/manuscript-title-check.sh`.
It must normalize the visible front matter to journal-native order: title, `## Abstract`, abstract text, `Keywords: ...`, then `## Introduction`. A visible `Keywords:` line before `## Abstract`, after `## Introduction`, missing entirely, or immediately after the Abstract heading before abstract prose is a Phase 19 blocker.
It must preserve reader-facing model labels. Visible final prose and tables should use `Model 1`, `Model 2`, `M1`, `M2`, and similar journal-native labels, not internal specification IDs such as `S1` or `S2`.
When the approved journal display architecture requires editable text tables, visible reader-facing tables must be Markdown/plain editable tables rather than raw HTML `<table>` blocks such as `tinytable` output. Raw HTML tables in `final/manuscript-final.md` are a Phase 19 blocker under `editable_text_*` table policies.
It must preserve visible declarations for data availability, ethics/human-subjects status, AI/tool use, and conflict of interest / competing interests unless Phase 16 marks a declaration as not applicable.

Good practice borrowed from `scholar-full-paper`: one canonical Markdown source rendered to `docx`, `tex`, and `pdf` with the same stem.

Do not borrow the fragile parts: warning-only conversion, missing PDFs treated as acceptable, or output files saved outside the canonical final directory.

`assembly_engine` must declare `name: pandoc`, `mode: same-source-final-assembly`, and `fallback_used: false`. Each `format_generation` command must explicitly render from `final/manuscript-final.md` to the matching canonical output path. Manual export, placeholder binary generation, or fallback conversion is a Phase 19 blocker.

## Versioning Rule

Keep stable canonical outputs for downstream automation:

- `final/manuscript-final.md`
- `final/manuscript-final.docx`
- `final/manuscript-final.tex`
- `final/manuscript-final.pdf`

Also save immutable timestamped copies:

- `final/versions/<version_id>/manuscript-final-<version_id>.md`
- `final/versions/<version_id>/manuscript-final-<version_id>.docx`
- `final/versions/<version_id>/manuscript-final-<version_id>.tex`
- `final/versions/<version_id>/manuscript-final-<version_id>.pdf`
- `final/versions/<version_id>/final-manifest-<version_id>.json`

`version_id` must match `YYYY-MM-DDTHHMMSSZ-vNNN`, where the timestamp is UTC. `final/LATEST.txt` must contain exactly the active `version_id` plus a trailing newline. Canonical hashes must equal versioned-copy hashes.

## Required Manifest Fields

`final/final-manifest.json` must include:

- `verdict`
- `degraded`
- `source_phase`
- `assembly_engine`
- `journal_profile_resolution`
- `version_id`
- `created_at_utc`
- `source_hashes`
- `source_manuscript_path`
- `source_manuscript_hash`
- `output_paths`
- `versioned_output_paths`
- `output_hashes`
- `versioned_output_hashes`
- `same_source`
- `format_generation`
- `content_checks`
- `reader_facing_language`
- `citation_checks`
- `declaration_checks`
- `declaration_visibility`
- `findings`
- `fix_checklist`
- `route_back_phase`
- `ready_for_phase_20`

## Pass Rules

- Phase 18 must pass first.
- `verdict` is `PASS`, `degraded` is false, and `source_phase` is `19`.
- `source_hashes` match the current manuscript, draft manifest, quality report, references, citation audit, claim map, ethics report, and replication report.
- all output paths equal `final/manuscript-final.{md,docx,tex,pdf}`;
- `final/LATEST.txt` points to `version_id`;
- all versioned output paths live under `final/versions/<version_id>/`;
- all output hashes match the files on disk;
- versioned output hashes match both the files on disk and the canonical output hashes;
- all four formats share the same stem and are generated from the same `final/manuscript-final.md` hash;
- `assembly_engine` declares Pandoc same-source rendering with no fallback;
- `journal_profile_resolution` must exactly match the approved Phase 12 blueprint and remain explicit about whether the paper is using a built-in profile, an imported custom profile, or an explicit `ASR` fallback;
- each format-generation command uses `final/manuscript-final.md` and writes the matching `final/manuscript-final.{docx,tex,pdf}` output;
- `docx` is a valid Word zip with `word/document.xml`;
- `tex` contains a LaTeX document body;
- `pdf` begins with `%PDF` and ends with an EOF marker;
- no placeholder manuscript text remains;
- no raw citation syntax such as `[@key]` or bare citekeys remains in the reader-facing manuscript body;
- the References section is a real formatted reference section rather than a citekey dump or bibliography-key summary;
- visible front matter follows `Title -> Abstract -> Keywords -> Introduction`;
- the final manuscript honors the blueprint's journal-specific section order and does not flatten venue-specific architecture into a generic article shell;
- the final manuscript honors the blueprint's journal-specific table/figure policy, including display caps and any required end-matter or supplement-facing treatment recorded in the blueprint;
- if the blueprint requires editable text tables, the final Markdown contains no raw HTML `<table>` blocks;
- `content_checks` must explicitly record that the journal structure and display architecture were applied, including section-order compliance, table and figure placement policy, rendering mode, descriptive-table requirement, and display-cap compliance;
- every non-`journal_exempt` reader-facing figure from the Phase 13 draft manifest remains visibly represented in the final manuscript;
- every non-`journal_exempt` reader-facing canonical regression table from the Phase 13 draft manifest remains visibly represented in the final manuscript for quantitative empirical papers;
- no visible final table is a row-per-spec registry/model-ladder display standing in for the main empirical table;
- all required manuscript sections and declarations are present or explicitly marked not applicable by upstream ethics/open-science artifacts.

## Route-Back Rules

- stale quality approval: Phase 18;
- unsupported references, missing bibliography, or citation contradiction: Phase 15;
- ethics/declaration contradiction: Phase 16;
- replication/package contradiction: Phase 17;
- conversion, manifest, format, or same-source defect: Phase 19;
- manuscript prose defects discovered during assembly: Phase 13, followed by downstream re-verification.
