# Submission Hygiene Contract

Phase 20 produces the reviewer-facing submission package and closes the default auto-research route.

## Required Outputs

Stable canonical outputs:

- `submission/manuscript-submission.md`
- `submission/manuscript-submission.docx`
- `submission/manuscript-submission.tex`
- `submission/manuscript-submission.pdf`
- `submission/semantic-body-prose-read.md`
- `submission/submission-hygiene.json`
- `submission/submission-package-manifest.json`
- `submission/LATEST.txt`

Immutable versioned outputs:

- `submission/versions/<submission_version_id>/manuscript-submission-<submission_version_id>.md`
- `submission/versions/<submission_version_id>/manuscript-submission-<submission_version_id>.docx`
- `submission/versions/<submission_version_id>/manuscript-submission-<submission_version_id>.tex`
- `submission/versions/<submission_version_id>/manuscript-submission-<submission_version_id>.pdf`
- `submission/versions/<submission_version_id>/semantic-body-prose-read-<submission_version_id>.md`
- `submission/versions/<submission_version_id>/submission-hygiene-<submission_version_id>.json`
- `submission/versions/<submission_version_id>/submission-package-manifest-<submission_version_id>.json`

## Source Rule

Use `final/manuscript-final.md` as the source of substantive content for `submission/manuscript-submission.md`, but do not rely on scrub-only transformation. Assemble the submission manuscript as a reviewer-facing derivative with an explicit section allowlist: title, abstract, keywords, introduction, literature/theory, methods, results, discussion, and references. Exclude draft-only workflow appendices, trace anchors, lock metadata, and pipeline scaffolding by construction. Then render `submission/manuscript-submission.docx`, `submission/manuscript-submission.tex`, and `submission/manuscript-submission.pdf` from that reviewer-facing Markdown.

The submission manuscript MUST declare a title before the first `##` section heading. The title is required structurally (gate `scripts/gates/manuscript-title-check.sh`), not merely as an allowlisted section. A submission whose first non-comment line is `## Abstract` fails Phase 20.

The submission manuscript MUST normalize visible front matter to `Title -> Abstract -> Keywords -> Introduction`: `Keywords:` belongs after the abstract text and before `## Introduction`, not in the title prefix before `## Abstract`. A visible `Keywords:` line before Abstract, after Introduction, missing entirely, duplicated, or placed before abstract prose fails Phase 20.

Good practice borrowed from `scholar-full-paper`: separate the pandoc-ready final assembly file from the reviewer-facing submission file, because final assembly may need local figure paths or archival appendices while reviewers must not see them. Submission hygiene should be structural first and regex/path scrubbing second.

Each `format_generation` command must invoke Pandoc, read `submission/manuscript-submission.md`, and write the matching canonical output path. The package inventory must provide a unique record for every canonical and versioned output, a nonempty role, and a truthful hash value for the file on disk. Self-referential JSON files must use `SELF_REFERENTIAL`; all other package files must use their actual SHA-256.

## Two-Stage Hygiene

Phase 20 has two mandatory stages:

1. **Stage A: deterministic machinery scan.** `auto-research-verify.sh 20` independently scans the current `submission/manuscript-submission.md` for known submission-killing machinery prose. This includes `[VERIFIED-*]` citation markers, pipeline-jargon headers such as `Robustness Ladder`, `Multiple-Comparison Correction`, `BH Correction Summary`, `Limitations Acknowledged at Estimation Time`, "we carry N accepted limitations" / "pre-registered families" enumeration prose, 3+ consecutive bulleted spec-ID lines such as `- **M1.**`, `- **M2.**`, `- **M3.**`, and proposal-style hypothesis display blocks such as `- **H1.** ...`, `1. Hypothesis 1: ...`, `H1: ...`, or a separate `## Hypotheses` section.
2. **Stage B: semantic body-prose read.** After Stage A is GREEN, dispatch an independent body-prose-reader subagent to read `submission/manuscript-submission.md` top-to-bottom for novel structural prose markers that regex rules do not yet know how to catch. The reader must ignore argument substance and numeric accuracy and focus only on prose that reads like orchestration output rather than journal prose, including `H1/H2` hypothesis lists that read like a proposal or PAP instead of a journal article.

Save the Stage B report to `submission/semantic-body-prose-read.md` with these literal audit fields:

```text
STATUS: GREEN
REVIEWED_ARTIFACT: submission/manuscript-submission.md
MANUSCRIPT_SHA256: <current sha256 of submission/manuscript-submission.md>
BLOCKING_ISSUES: 0
STRUCTURAL_PATTERN_COUNT: 0
```

`YELLOW` and `RED` reports do not complete Phase 20. A YELLOW report means the suggestions must be resolved and the semantic reader rerun until it returns GREEN. A RED report should also be converted into a deterministic regression rule if it identifies a class-new machinery pattern.

## Required Hygiene Checks

Hard-fail on:

- local absolute paths: `/Users/`, `/home/`, `/tmp/`, `/private/var/`, `/var/folders/`, Windows drive paths, UNC paths, `~`, `$HOME`;
- internal pipeline paths or metadata: `results-locked/`, `manifest SHA`, `SHA-256 of manifest`, `.auto-research/`, `verify/`, `logs/`, `replication-package/`;
- internal workflow language in reader-facing prose: result locks, active locks, registries, manifests, phase numbers, route-back language, provenance records, or "registered before execution" phrasing when it refers to the pipeline rather than a formal preregistration;
- visible Results tables that are row-per-spec registries, model ladders, focal-coefficient extracts, results registries, or verification tables standing in for the original regression table;
- raw HTML `<table>` blocks in reviewer-facing Markdown when the journal profile requires editable text tables, including `tinytable` HTML output that should have been converted to Markdown/plain editable tables;
- internal specification IDs used as visible model labels in prose or tables, such as `S1`, `S2`, or `S3`; submission manuscripts should use `Model 1`, `Model 2`, `M1`, `M2`, and similar journal-native labels;
- citation-verification markers such as `[VERIFIED-WEB: ...]`, `[VERIFIED-LOCAL: ...]`, `[VERIFIED-TBV: ...]`, `[VERIFIED-EXTERNAL: ...]`, or `[VERIFIED-MANUAL: ...]`;
- pipeline-jargon section headers such as `Robustness Ladder`, `Multiple-Comparison Correction`, `BH Correction Summary`, `Hypothesis status update`, `Robustness battery`, `Pre-mortem memo`, or `Resolution tracker`;
- formulaic machinery enumeration prose such as "we carry ten accepted limitations" or "two pre-registered families";
- 3+ consecutive bulleted spec-ID lines such as `- **M1.**`, `- **M2.**`, `- **M3.**`;
- proposal-style hypothesis display blocks, including `H1/H2` bullet lists, numbered `Hypothesis 1:` lists, standalone `H1:` lines, or a separate `## Hypotheses` section, unless the journal profile explicitly allows displayed hypotheses;
- post-results theory leakage: the reviewer-facing Theory/Hypotheses block must preserve canonical Phase 2 hypotheses and must not contain result interpretation such as evidence revising expectations, positive/negative estimates, null-compatible findings, model/table/figure references, or drafting-derived result accommodations;
- draft tracker markers: `[REVISED: ...]`, `[T12]`, `[T13]`, reviewer-objection scaffolding, foreshadowing headings;
- unresolved citation markers: `SOURCE NEEDED`, `UNVERIFIED`, `[citation needed]`, missing citekeys;
- raw citekey syntax such as `[@key]` or bibliography-key placeholders surviving into the reviewer-facing manuscript;
- placeholder manuscript text: `TBD`, `TODO`, bracketed title/journal/author placeholders;
- invalid front-matter order: missing visible `Keywords:`, keywords before `## Abstract`, keywords after `## Introduction`, duplicate visible keyword lines, or keywords placed before the abstract prose;
- fake References sections that only list citekeys, bibliography keys, or workflow summaries instead of formatted references;
- missing visible reader-facing figure blocks when the approved final manuscript contained required non-`journal_exempt` figures;
- referenced local figure files that do not exist next to the submission manuscript or are absent from the package inventory;
- missing visible declarations for data availability, ethics/IRB or human-subjects status, AI/tool use, and conflict of interest / competing interests unless the Phase 16 report explicitly marks a declaration as not applicable;
- malformed or missing submission package manifest;
- missing versioned copies or canonical/versioned hash mismatch.
- journal-profile provenance that no longer matches the approved final assembly state.
- missing `docx`, `tex`, or `pdf` submission formats, or formats not generated from `submission/manuscript-submission.md`.
- package-inventory records that omit roles, duplicate paths, or report hashes that do not match the files on disk.
- missing, stale, YELLOW, RED, or unresolved `submission/semantic-body-prose-read.md`.

Advisory style warnings may be recorded, but they do not pass if any hard failure remains.

## Required JSON Fields

`submission/submission-hygiene.json` must include:

- `verdict`
- `degraded`
- `source_phase`
- `submission_engine`
- `journal_profile_resolution`
- `final_version_id`
- `submission_version_id`
- `created_at_utc`
- `source_hashes`
- `hygiene_checks`
- `citation_rendering`
- `path_scrub`
- `placeholder_scan`
- `internal_metadata_scan`
- `reader_facing_language`
- `semantic_body_prose_read`
- `declaration_visibility`
- `figure_packaging`
- `format_generation`
- `findings`
- `fix_checklist`
- `route_back_phase`
- `pipeline_complete`

`submission/submission-package-manifest.json` must include:

- `verdict`
- `source_phase`
- `journal_profile_resolution`
- `final_version_id`
- `submission_version_id`
- `canonical_outputs`
- `versioned_outputs`
- `output_hashes`
- `versioned_output_hashes`
- `package_inventory`
- `ready_for_done`

## Versioning Rule

`submission_version_id` must match `YYYY-MM-DDTHHMMSSZ-vNNN` and `created_at_utc` must match that timestamp. `submission/LATEST.txt` must contain exactly the active `submission_version_id` plus a trailing newline. Canonical hashes must equal versioned-copy hashes.

## Route-Back Rules

- final assembly source defect, stale final manifest, or final-version mismatch: Phase 19;
- citation rendering, missing bibliography, or citekey defect: Phase 15;
- missing/contradictory ethics, AI, COI, or data availability declaration: Phase 16;
- replication disclosure contradiction: Phase 17;
- submission scrub, placeholder, manifest, versioning, or package-inventory defect: Phase 20.
- body-prose machinery introduced during drafting: Phase 13.
- proposal-style hypothesis display introduced during drafting: Phase 13.
- post-results theory leakage or canonical-hypothesis drift introduced during drafting: Phase 13.
