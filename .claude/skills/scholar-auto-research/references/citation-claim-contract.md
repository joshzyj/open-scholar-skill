# Citation and Claim Contract

Phase 15 must verify both source existence and claim support.

Phase 15 uses `scholar-citation` as the citation and claim-support engine. Run it in verify/audit mode against the Phase 14-verified manuscript, the project BibTeX file, and the Phase 13/14 manifests.

Helper code may prepare inventories, manifests, or packaging sidecars, but it must not replace `scholar-citation` as the primary engine for source verification, bibliography judgment, claim checking, or contradiction detection. A local scanner that only counts keys or rewrites files is not a passing substitute for Phase 15.

Required inputs:

- `manuscript/manuscript-draft.md`
- `manuscript/draft-manifest.json`
- `literature/references.bib`
- `verify/manuscript-verification.json`

Required outputs:

- `citation/citation-audit.json`
- `citation/claim-source-map.json`
- `citation/references.bib`

`citation/citation-audit.json` must include:

- `verdict`: `PASS` or `FAIL`
- `degraded`: boolean
- `citation_engine`: object declaring `skill: scholar-citation`, `mode: verify`, source verification enabled, claim support enabled, retraction check enabled, and fabrication guard enabled
- `source_hashes`: hashes for manuscript, draft manifest, source BibTeX, Phase 14 verification report, claim-source map, and exported references
- `selected_manuscript_hash`: current manuscript hash
- `citation_inventory`: all unique citation keys in the manuscript and every key in both BibTeX files
- `bibliography_provenance`: source-bibliography lineage for the manuscript citation pool
- `verified_references`: one record per cited key
- `unresolved_citation_count`: `0` for PASS
- `fabricated_reference_count`: `0` for PASS
- `unsupported_claims`: `0` for PASS
- `contradicted_claims`: `0` for PASS
- `locator_missing`: `0` for PASS
- `retraction_check`: checked count, retracted count, and records
- `claim_source_map`: summary of claim-source map coverage
- `claim_specificity`: status, maximum citation keys per claim, omnibus claim count, and documentation of any bulk-citation exceptions
- `findings`: empty for PASS; nonempty structured findings for FAIL
- `fix_checklist`: empty critical fixes and route-back for PASS
- `route_back_phase`: `null` for PASS
- `ready_for_phase_16`: `true` for PASS

`citation/claim-source-map.json` must include claim-level records:

- claim ID
- manuscript location
- manuscript anchor copied from the draft
- claim type
- citation keys
- source locator or page/section
- evidence span summary
- support verdict
- contradiction flag

`bibliography_provenance` must include:

- `source_bib_path`: `literature/references.bib`
- `exported_bib_path`: `citation/references.bib`
- `project_native_primary`: boolean
- `cross_project_imports_declared`: boolean
- `cross_project_import_count`: integer
- `cross_project_import_notes`: empty string only when `cross_project_import_count` is zero

For PASS, the exported `citation/references.bib` must be a project-scoped bibliography subset or an explicitly documented curated extension. Silent reuse of another project's bibliography pool is not acceptable.

Every claim record must include `support_verdict: SUPPORTED`, `contradiction: false`, a `manuscript_anchor` that appears in `manuscript/manuscript-draft.md` and contains the cited keys, and a nonempty `source_locator` for causal, novelty, prevalence, and policy claims.

Claim-source maps must be specific rather than inventory-like:

- no single claim may carry more than eight citation keys unless `bulk_citation_exception` is true and a field-specific rationale explains why the sentence is a source catalogue rather than a substantive claim;
- no claim may attach most or all cited keys to one generic background, literature, context, or "all sources" claim;
- rendered manuscripts must not contain oversized citation clusters, duplicated author-year pairs in the same parenthetical citation, or generic "the broader literature supports..." clusters; `scripts/gates/citation-cluster-quality-check.sh` enforces this after rendering;
- every cited key must be tied to at least one claim whose `claim_text`, `manuscript_location`, and `source_locator` describe what that source supports;
- empirical result claims must cite result artifacts and relevant data documentation, not a generic theory citation cluster;
- verified reference records must include at least one verification source beyond `project_bib`, such as CrossRef, DOI metadata, local reference-manager metadata, publisher metadata, or an explicit `external_verification_unavailable` rationale.

Hard failures:

- fabricated or missing source
- unverified source
- unsupported empirical claim
- contradicted claim
- missing locator for causal, novelty, prevalence, or policy claims
- omnibus citation clusters or claim-source maps that treat the bibliography as one undifferentiated support block
- missing bibliography provenance
- fake exported bibliography that is only a key dump, placeholder list, or non-BibTeX text

If Phase 15 fails, it must emit structured findings. Route unsupported or contradicted prose/citation problems to Phase 13; missing/unverified references to Phase 15; citation pool problems to Phase 2; and result-claim citation conflicts that contradict Phase 14 to Phase 14.
