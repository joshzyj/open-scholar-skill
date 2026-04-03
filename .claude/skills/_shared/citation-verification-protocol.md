# Citation Verification Protocol (Shared)

All skills that produce or modify citations MUST follow this protocol.

## Verification Tiers

| Tier | Source | Limit | Required? |
|------|--------|-------|-----------|
| 0 | Knowledge Graph (~/.claude/scholar-knowledge/) | unlimited | If available |
| 1 | Local library (Zotero/Mendeley/BibTeX/EndNote) | 100 | YES — always search first |
| 2a | CrossRef API | 50 | YES |
| 2b | Semantic Scholar API | 50 | If S2_API_KEY set |
| 2c | OpenAlex API | 50 | YES (no key needed) |
| 2d | Google Scholar via WebSearch | 20 | Fallback only |

## Verification Levels

Skills operate at different verification levels depending on their role:

| Level | Description | Used by |
|-------|-------------|---------|
| FULL | All tiers searched; each ref verified against ≥1 database | scholar-citation (all modes) |
| STANDARD | Tiers 0-2a searched; unverified flagged as [CITATION NEEDED] | scholar-write, scholar-lit-review, scholar-hypothesis |
| LIGHT | Tier 1 only (local library); unverified flagged | scholar-respond |

## ABSOLUTE RULE

NEVER fabricate citations. If a reference cannot be verified at ANY tier, mark it as:
`[CITATION NEEDED: describe required evidence]`

## Invoking the Gate

After any skill produces citation-containing output, run:
```bash
bash "${SCHOLAR_SKILL_DIR:-.}/scripts/gates/verify-citations.sh" "$DRAFT_PATH"
```

## Integration

Skills that produce citations should state their verification level in their process log:
```
Citation verification level: [FULL/STANDARD/LIGHT]
References verified: [N] | Unverified: [N] | [CITATION NEEDED] markers: [N]
```
