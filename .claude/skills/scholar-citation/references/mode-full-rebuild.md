# MODE 4: FULL-REBUILD — End-to-End Citation Pipeline

**Input:** Draft manuscript section (text with or without existing citations)

Run all modes in sequence:
1. **AUDIT existing citations** (if any) → identify issues
2. **CLAIM INVENTORY** → identify uncited claims
3. **ZOTERO SEARCH** → locate sources for all claims
4. **CROSSREF FALLBACK** → for items not in Zotero
5. **INSERT citations** → revised draft with all in-text citations
6. **ASSEMBLE reference list** → complete, deduplicated, style-formatted
7. **VERIFY all references** → run MODE 5 VERIFY on the assembled reference list (every entry must pass Zotero, CrossRef, Google Scholar, or WebSearch verification; remove or flag any entry that cannot be confirmed)
8. **FINAL AUDIT** → cross-check all in-text vs. references
9. **SAVE OUTPUT** → two files (draft + audit log with verification results)

**Implementation notes:**

For steps 1-2, load `references/mode-insert-audit.md` and follow the INSERT and AUDIT procedures.

For step 7, load `references/mode-verify-retraction.md` and follow the VERIFY procedure (MODE 5 only — skip RETRACTION-CHECK unless explicitly requested).

For steps 8-9, follow the Save Output and Quality Checklist sections in the main SKILL.md.
