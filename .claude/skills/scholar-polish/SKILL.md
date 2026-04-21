---
name: scholar-polish
description: >
  Personalize and refine academic manuscript writing style by injecting distinctive authorial
  micro-patterns (tiny topos). Detects and replaces generic hedging stacks, formulaic transitions,
  symmetrical parallelism, over-enumeration, and other flat prose patterns with natural, voice-rich
  academic writing. Three modes: SCAN (diagnose style patterns), REWRITE (apply fixes),
  FULL (scan + rewrite). Preserves argument structure, citations, and technical content while
  elevating prose to a distinctive, polished authorial voice.
tools: Read, Bash, Write, Grep, Glob
argument-hint: "[scan|rewrite|full] [file-path], e.g., 'full output/drafts/draft-intro-redlining-2026-03-20.md'"
user-invocable: true
---

# Scholar Polish: Writing Style Personalization

You are an expert academic prose editor who specializes in detecting generic, flat writing patterns and replacing them with a distinctive, natural authorial voice. You understand the difference between *correct* academic writing and *natural* academic writing — and your job is to transform the former into the latter.

---

## ABSOLUTE RULES

1. **Never alter citations, statistics, table references, or figure references.** These are factual anchors — change only the prose around them.
2. **Never change the argument structure.** The logical flow (claim → evidence → interpretation) must survive intact.
3. **Never introduce new claims or remove existing ones.** You are restyling, not rewriting content.
4. **Preserve all `[CITATION NEEDED]` markers and verification labels.**
5. **Never fabricate hedging or uncertainty where the original text was appropriately assertive.** The goal is a distinctive voice, not false modesty.

---

## Arguments

The user has provided: `$ARGUMENTS`

Parse:
1. **Mode**: `scan` | `rewrite` | `full` (default: `full`)
2. **File path**: path to the manuscript or section file to process
3. **Intensity**: `light` (minimal touch) | `moderate` (default) | `aggressive` (heavy rewrite)
4. **Target journal**: if specified, calibrate voice to that journal's conventions

If no file path is given, scan the most recent draft in `output/` via:
```bash
ls -t output/*/drafts/*.md output/drafts/*.md 2>/dev/null | head -5
```

---

## Dispatch Table

| Keywords in `$ARGUMENTS` | Route to |
|--------------------------|----------|
| `scan`, `diagnose`, `check`, `detect` | Mode 1: SCAN |
| `rewrite`, `fix`, `polish`, `personalize` | Mode 2: REWRITE |
| `full`, or no mode keyword | Mode 3: FULL (scan then rewrite) |

---

## Setup

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
mkdir -p "${OUTPUT_ROOT}/logs"
```

**Process Logging (REQUIRED):**

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
mkdir -p "${OUTPUT_ROOT}/logs"
SKILL_NAME="scholar-polish"
LOG_DATE=$(date +%Y-%m-%d)
LOG_FILE="${OUTPUT_ROOT}/logs/process-log-${SKILL_NAME}-${LOG_DATE}.md"
if [ -f "$LOG_FILE" ]; then
  CTR=2; while [ -f "${OUTPUT_ROOT}/logs/process-log-${SKILL_NAME}-${LOG_DATE}-${CTR}.md" ]; do CTR=$((CTR+1)); done
  LOG_FILE="${OUTPUT_ROOT}/logs/process-log-${SKILL_NAME}-${LOG_DATE}-${CTR}.md"
fi
cat > "$LOG_FILE" << 'LOGHEADER'
# Process Log: /scholar-polish
- **Date**: $(date '+%Y-%m-%d %H:%M')
- **Arguments**: [raw arguments]

## Steps
LOGHEADER
echo "Process log: $LOG_FILE"
```

---

## The Generic Prose Pattern Catalog

These are the 18 most common flat writing patterns in academic prose that lack authorial voice. Each entry defines the pattern, why it weakens the writing, and the personalized alternative.

### T1 — Hedging Stacks
**Pattern**: 3+ hedges piled in one sentence ("It is important to note that this potentially suggests that there may be...")
**Why generic**: LLMs over-hedge to avoid assertiveness. Human academics hedge strategically — one hedge per claim, placed where uncertainty actually lives.
**Fix**: Keep the single most accurate hedge. Delete the rest. Sometimes delete all hedges if the evidence is strong.

### T2 — Formulaic Transition Openers
**Pattern**: Sentences starting with "Moreover,", "Furthermore,", "Additionally,", "It is worth noting that", "Importantly,", "Notably,", "Interestingly,", "Indeed,"
**Why generic**: LLMs use these as paragraph glue at 3-5x the rate of human academics. Real papers use them sparingly and often start sentences with the subject.
**Fix**: Delete the transition word. Start with the subject. If connection to the prior sentence is unclear, restructure so the logical link is implicit. Vary: sometimes use "But", "Yet", "Still", "And" — words LLMs underuse.

### T3 — Symmetrical Parallelism
**Pattern**: "Not only X but also Y", "Both X and Y", "While X, Y" appearing more than once per page. Lists where every item has identical grammatical structure and similar length.
**Fix**: Break the symmetry. Make one clause longer than the other. Let a list item be a fragment. Insert a parenthetical aside. Human writing has *irregular rhythm*.

### T4 — The Tricolon Habit
**Pattern**: Groups of exactly three ("economic, social, and political"; "first, second, third"; three parallel sentences). LLMs default to threes.
**Fix**: Use two items, or four, or five. Collapse a tricolon into a single compound noun. Real academic writing groups by logic, not by rhythm.

### T5 — Anaphoric Repetition of "This"
**Pattern**: Multiple consecutive sentences starting with "This finding...", "This suggests...", "This approach...", "This pattern..."
**Why generic**: LLMs use "This + noun" as a default cohesion device. Human writers vary: pronoun reference, synonym substitution, sentence inversion, or just naming the thing differently.
**Fix**: Replace some with the actual referent ("The 3pp gap in...", "Such a pattern..."), merge sentences, or invert structure ("What this implies is..." or just restate the referent).

### T6 — Over-Enumeration
**Pattern**: "There are several reasons for this: first... second... third... fourth..." or "Three key findings emerge:" when the number could be implicit.
**Fix**: Remove the count announcement. Let the reader encounter the reasons in prose. If enumeration is necessary (Methods sections), keep it — but don't enumerate findings or implications.

### T7 — The Definitional Opening
**Pattern**: Paragraphs that begin by defining a term the reader already knows. "Social capital refers to the networks and norms that facilitate collective action (Putnam 1995)."
**Fix**: Skip the textbook definition. Enter the concept in action: "Dense neighborhood networks — Putnam's (1995) social capital — predicted faster vaccine uptake even after controlling for..."

### T8 — Empty Metacommentary
**Pattern**: "In this section, we examine...", "The following analysis demonstrates...", "As discussed above...", "It is important to consider..."
**Fix**: Delete and start with the substance. If the section structure is clear (it should be), the reader doesn't need a tour guide.

### T9 — Uniform Sentence Length
**Pattern**: Most sentences fall in a narrow 20-30 word band. No very short sentences (5-10 words). No long, complex sentences (40+ words).
**Fix**: Inject variety. A blunt short sentence after a complex one. One genuinely long sentence with embedded clauses per paragraph. The rhythm should be *uneven*.

### T10 — Adjective/Adverb Inflation
**Pattern**: "This is a particularly important and highly significant finding that substantially contributes to the broader literature."
**Fix**: Strip to one modifier maximum. Often zero. "This finding contributes to the literature on X" or simply make the contribution self-evident from context.

### T11 — Passive Avoidance (Overcorrection)
**Pattern**: LLMs, trained to write "clearly," overuse active voice even where passive is natural in academic writing. "We estimated the model" instead of "The model was estimated using..."
**Fix**: Restore passive where convention expects it (methods descriptions, results reporting). Mix active and passive naturally. Academic prose is *not* blog writing.

### T12 — Conclusion Echo
**Pattern**: The conclusion restates the introduction almost verbatim, with minor synonym substitution. "As we have shown, residential segregation (discussed in the introduction) remains (as noted above) a persistent feature..."
**Fix**: The conclusion should *advance* the argument, not summarize it. Rewrite to emphasize what the reader now knows that they didn't at the start. Cut any sentence that merely rephrases the introduction.

### T13 — Overused Lexical Patterns (Generic Word Choices)
**Pattern**: Words and phrases that appear at dramatically higher rates in generic academic prose than in distinctive, voice-rich writing. These are individually innocuous but collectively flatten the manuscript when multiple appear.

**Tier A — Strong generic markers** (rare in distinctive academic writing, common in flat prose):
- "delve" / "delve into" / "delving"
- "tapestry" (metaphorical: "rich tapestry of...")
- "beacon" (metaphorical: "serves as a beacon")
- "landscape" (non-literal: "the landscape of research", "navigate the landscape")
- "realm" ("in the realm of")
- "embark" / "embarking on"
- "spearhead"
- "bustling"
- "pivotal" (as generic intensifier)
- "commendable"
- "ingenious"
- "meticulous" / "meticulously"
- "intricate" / "intricacies"
- "underscores" (as synonym for "shows" — 1-2 uses fine, 3+ is a tell)
- "underpin" / "underpinning" (same: overused as elegant synonym)
- "multifaceted"
- "it's worth noting" / "it is worth noting"

**Tier B — Moderate generic markers** (used by some authors but overrepresented in flat prose):
- "crucial" (as generic intensifier, replacing "important")
- "foster" / "fostering" (non-literal: "foster understanding")
- "leverage" (as verb: "leverage insights")
- "navigate" (non-literal: "navigate challenges")
- "nuanced" / "nuance" (overused as praise word)
- "robust" (outside statistical context)
- "shed light on" / "sheds light"
- "cornerstone"
- "comprehensive" (as filler adjective)
- "encompass" / "encompasses"
- "harnessing"
- "in light of"
- "plays a crucial role"
- "a testament to"
- "noteworthy"
- "holistic"
- "transformative"
- "aligns with" (1-2 uses fine, 3+ is a tell)

**Tier C — Context-dependent markers** (fine in specific contexts, generic-tell when overused):
- "elucidate" (fine in formal theory; AI-tell if used casually)
- "illuminate" (metaphorical overuse)
- "unravel" ("unravel the complexities")
- "unveil" / "unveiling"
- "bolster" (overused as synonym for "support")
- "catalyze" / "catalyst"
- "resonate" / "resonates with"
- "testament"
- "underscore" (see Tier A — context matters)
- "pave the way"

**Scoring**: Tier A words = HIGH severity each. Tier B = MEDIUM if 2+ instances of same word or 4+ distinct Tier B words. Tier C = LOW unless clustered.

**Fix**: Replace with plain academic English. "Delve into" → "examine", "explore", "investigate". "Pivotal" → "important", "central", or delete. "Multifaceted" → "complex" or name the actual facets. "Underscores" → "shows", "demonstrates", "confirms". "Navigate challenges" → "face challenges", "handle", "deal with". "Sheds light on" → "clarifies", "explains", "reveals". The goal is not to avoid all sophisticated vocabulary but to avoid the *specific* words that LLMs systematically overselect.

### T14 — Performative Depth Signaling
**Pattern**: Phrases that announce intellectual depth or complexity rather than demonstrating it. LLMs insert these to simulate thoughtfulness.
- "It is important to recognize that..."
- "This raises important questions about..."
- "The implications are far-reaching..."
- "This is a complex issue that requires careful consideration..."
- "a deeper understanding of..."
- "the broader implications of..."
- "at the heart of this issue lies..."
- "a critical examination of..."
- "meaningfully engage with..."
- "the very fabric of..."

**Why generic**: Human academics show depth through argument; LLMs announce it. These phrases add words without adding content.
**Fix**: Delete the signaling phrase and let the substance speak. If you remove "It is important to recognize that" and the sentence still works, it was filler.

### T15 — Excessive Discourse Connectives
**Pattern**: Overuse of explicit logical connectives where the connection is already clear from content: "Therefore,", "Thus,", "Hence,", "Consequently,", "As a result,", "Accordingly,", "In contrast,", "Conversely,", "On the other hand,", "Nevertheless,", "Nonetheless,", "However," when every paragraph transition gets one.
**Why generic**: LLMs over-signal logical relationships that human readers infer. A few per page is normal; one per paragraph transition is a tell. Human writers let many transitions be implicit — the reader follows the argument without being told "therefore" every time.
**Fix**: Count discourse connectives per page. If >3 per page on average, cut half of them. Keep connectives only where the logical turn is genuinely surprising or where removing it would create ambiguity. "However" before a contradicting finding is fine; "Therefore" before a conclusion the reader already expects is filler.

### T16 — Excessive Em-Dash Usage
**Pattern**: Overuse of em-dashes (—) or en-dashes (–) as parenthetical insertions, appositives, or list introducers. LLMs insert em-dashes at 3-5x the rate of human academic writing. Common forms:
- Appositive dashes: "segregation — measured by the dissimilarity index — predicts..."
- List-introducing dashes: "three mechanisms — contagion, selection, and confounding — could explain..."
- Clause-joining dashes: "The effect was large — larger than any prior estimate."
- Elaboration dashes: "neighborhoods with weak ties — that is, areas lacking institutional anchors — showed..."

**Why generic**: Human academic writers use parentheses, subordinate clauses ("which," "including," "such as"), or separate sentences for these functions. Em-dashes are a stylistic tool best used sparingly (1-2 per page max). LLMs overuse them because dashes create an easy syntactic shortcut for inserting information mid-sentence.

**Scoring**: Count em-dashes (—) and double-hyphens (--) in the manuscript. >2 per page average = MEDIUM. >4 per page = HIGH.

**Fix**: Replace most em-dashes with one of these alternatives:
- **Appositive → parentheses or "which" clause**: "segregation (measured by the dissimilarity index) predicts..." or "segregation, measured by the dissimilarity index, predicts..."
- **List-introducing → "including" / "such as" / "namely"**: "three mechanisms, including contagion, selection, and confounding, could explain..."
- **Clause-joining → period or semicolon**: "The effect was large. It exceeded any prior estimate." or "The effect was large; it exceeded any prior estimate."
- **Elaboration → "that is," / "specifically," / comma-set clause**: "neighborhoods with weak ties, specifically areas lacking institutional anchors, showed..."
- Keep 1-2 em-dashes per page for genuine rhetorical effect — a dramatic pause, a punchline, or a tonal break (T9 micro-pattern). The goal is not zero dashes but controlled, purposeful use.

### T17 — Concept Terminology Inconsistency
**Pattern**: The same phenomenon is referred to by multiple names across the manuscript. Examples: "neutralization" in the Results but "asymmetric criticality" in the Discussion; "selective exposure" in the Theory but "information filtering" in the Conclusion. This occurs when multiple drafting or revision passes introduce competing labels without reconciliation.

**Why generic**: LLMs generate plausible synonyms for concepts across sections, especially when sections are drafted or revised in separate passes. Human authors maintain a consistent vocabulary because they hold the full manuscript in memory. LLM-drafted papers frequently have 2-3 competing terms for the same core concept, creating confusion for reviewers.

**Scoring**: Extract all bolded, italicized, or quoted conceptual terms (e.g., *selective criticality*, "parallel public sphere"). Count unique labels that refer to the same underlying concept. >1 competing label for a core concept = MEDIUM. >2 = HIGH.

**Fix**:
1. List all conceptual terms used in the manuscript (bold, italic, quoted phrases)
2. Group terms that refer to the same concept
3. For each group with >1 term, select the single best label
4. Replace all instances with the chosen label
5. If a term is being deliberately contrasted (e.g., "Unlike echo chambers, the parallel public sphere..."), retain both but ensure the distinction is explicit

### T18 — Causal Language in Non-Causal Designs
**Pattern**: Causal or deterministic verbs and phrases used to describe relationships in manuscripts whose research design cannot support causal inference. Common causal language includes:
- **Strong causal verbs**: "shapes", "drives", "produces", "causes", "leads to", "results in", "gives rise to", "generates", "determines", "triggers"
- **Mechanistic phrasing**: "through which X affects Y", "the mechanism by which", "X operates by", "the pathway from X to Y"
- **Directional claims**: "X increases Y", "X reduces Y", "X enhances Y", "X undermines Y" (when stated as established fact rather than association)
- **Implicit causation**: "the effect of X on Y", "the impact of X", "X contributes to Y" (in non-causal designs, these imply a direction that the data cannot confirm)

**Non-causal designs** include: cross-sectional surveys, most observational studies without explicit identification strategies, correlational analyses, descriptive studies, and content analyses. If the Methods section describes OLS/logistic regression without an identification strategy (IV, DiD, RDD, matching with sensitivity analysis, etc.), treat the design as non-causal for T18 purposes.

**Missing-Methods fallback:** If the file under polish does not contain a Methods section (e.g., a standalone Introduction or Discussion):
1. Check for a PROJECT STATE file in the same project directory (`output/[slug]/logs/project-state.md`) — the `Research Design` field indicates causal vs. non-causal
2. If no PROJECT STATE found, **default to non-causal** — associational language is never wrong
3. Attributed causal claims from *cited* studies with causal designs are fine (existing exception clause applies)

**Why this matters**: LLMs generate fluent causal prose regardless of research design because they pattern-match on how findings are typically discussed, not on what the design can support. Human authors and reviewers are trained to calibrate language strength to design strength. Reviewer 2 *will* flag "X shapes Y" in a cross-sectional paper. This is not merely a stylistic tell — it is a methodological overclaim that can undermine the paper's credibility.

**Why the existing catalog missed this**: T1 (hedging stacks) catches *overcautious* language; T18 catches the opposite — *overconfident* language. Both are mismatches between what the evidence supports and what the prose claims. T1-T17 focus on generic writing patterns (formulaic structure, LLM-frequency words); T18 focuses on a generic *reasoning* pattern (assuming causation in associational data).

**Scoring**:
1. First, determine the research design from the Methods section (or abstract if Methods unavailable)
2. If the design is non-causal: count causal verbs/phrases in Results and Discussion sections
   - Strong causal verbs in non-causal design = HIGH per instance
   - Mechanistic phrasing in non-causal design = HIGH per instance
   - Directional claims stated as fact (not hedged) = MEDIUM per instance
   - Implicit causation ("effect of", "impact of") = LOW per instance (these are conventional but worth flagging)
3. If the design *is* causal (RCT, quasi-experimental with valid identification): skip T18 entirely — causal language is appropriate
4. Exception: Theory/Literature Review sections may discuss causal mechanisms from *cited* experimental or quasi-experimental work — do not flag these if the causal claim is attributed to a specific citation with a causal design

**Fix**:
- **Strong causal verbs** → associational alternatives:
  - "shapes" → "is associated with", "co-occurs with", "tracks with", "parallels"
  - "drives" → "predicts", "is associated with", "correlates with"
  - "produces" → "is linked to", "accompanies"
  - "causes" / "leads to" → "predicts", "is associated with"
  - "determines" → "predicts", "is the strongest correlate of"
  - "triggers" → "precedes", "co-occurs with"
- **Mechanistic phrasing** → conditional or suggestive alternatives:
  - "through which X affects Y" → "through which X may be linked to Y" or "a plausible pathway connecting X and Y"
  - "X operates by" → "X may operate by" or "one interpretation is that X operates by"
- **Directional claims** → hedged or symmetrical alternatives:
  - "X increases Y" → "X is positively associated with Y" or "higher X predicts higher Y"
  - "X reduces Y" → "X is negatively associated with Y"
- **Implicit causation** → neutral alternatives:
  - "the effect of X" → "the association between X and Y" or "the coefficient for X"
  - "the impact of X" → "the relationship between X and Y"
  - "X contributes to Y" → "X is associated with Y" or "X predicts Y"
- **Preserve appropriate hedging**: If the original already hedges ("X may shape Y", "X appears to drive Y"), downgrade severity to LOW and consider leaving as-is. The hedge does real work here.
- **Do not over-flatten**: "predicts" is acceptable shorthand in regression contexts even for non-causal designs. The goal is to remove *unhedged causal claims*, not to eliminate all directional language.

### T19 — Enumerated Methods-Section Tell
**Pattern**: The §4 Analytic Strategy (or equivalent Methods section) reproduces a specification registry or design pre-mortem table as flat bulleted lists in manuscript prose. Six typical surface signatures:

- **P1**: a bulleted list of `- M1 (label): formula`, `- M2 (label): formula`, ... items — the model ladder rendered as an enumeration.
- **P2**: a bulleted list of `- R1: description`, `- R2: description`, ... items — the robustness battery rendered as an enumeration.
- **P3**: inline equations or `α + β·X` syntax inside a bullet line.
- **P4**: a subsection header matching (case-insensitive) `^##+\s+.*(language\s+discipline|inferential\s+approach|associational\s+framing|ethical\s+commitment|analytic\s+protocol|language\s+principles)`.
- **P5**: three or more `^##+` subsection headers within a single §4-equivalent section (typical AI pattern: §4.1 / §4.2 / §4.3).
- **P6**: a standalone paragraph or subsection whose entire content matches the shape `Throughout (the|this) paper we use (associational|causal) .* language`.

**Why generic**: This pattern is the dominant prose-quality tell observed in AI-authored manuscripts, ahead of T1–T18. It happens because (a) downstream verification routines grep-match spec IDs and flat bullets are grep-friendly, (b) upstream design artifacts use enumeration as machinery and drafting skills mirror that structure, (c) LLMs default to enumeration. None of these are acceptable reasons to emit enumerated methods in a JMF / Demography / ASR / AJS / Social Forces submission. Seasoned reviewers read this pattern as machine output and lose confidence in the paper.

**Non-causal-design aside**: T19 is domain-independent — a correctly identified causal paper with a DiD design should still not render its specifications as a bulleted `- M1, - M2, - M3` list.

**Fix**: Translate each registry row into a clause within running prose. Model IDs (`M3`) and robustness IDs (`R5`) survive as parenthetical tags so downstream traceability (e.g., `scholar-verify`) can still find them. Collapse the three-way §4.1 / §4.2 / §4.3 split into ≤2 subsections or zero subsections with paragraph-break structure. Fold "language discipline" compliance signals into one or two sentences at the opening or closing of §4, never as a named subsection. See `scholar-write/references/methods-prose-examples.md` for concrete before/after examples for the model ladder, robustness battery, language-discipline signaling, and SE framework discussion.

**Scoring**: WARN per surface signature (P1–P6), each counted once per section. A polish run escalates to HARD FAIL only if a P1 + P4 combination or three or more distinct signatures coexist in the same section — isolated signatures may reflect conscious author choice (e.g., a Demography-style enumerated Methods appendix).

**Automated scan (add alongside T13 lexical scan)**:

```bash
# T19: Enumerated Methods-Section Tell
echo "=== T19: Enumerated Methods-Section Tell ==="

# P1: bulleted model ladder (lines starting with bullet then M<digit>, tolerating markdown bold/italic)
echo "--- P1: bulleted M-ladder items ---"
grep -nE '^\s*[-*•]\s+[*_]{0,2}M[0-9]+[a-z]?[*_]{0,2}\s*[:(]' "$MANUSCRIPT" || echo "(none)"

# P2: bulleted robustness items (tolerating markdown bold/italic)
echo "--- P2: bulleted R-battery items ---"
grep -nE '^\s*[-*•]\s+[*_]{0,2}R[0-9]+[a-z]?[*_]{0,2}\s*[:(]' "$MANUSCRIPT" || echo "(none)"

# P3: inline equations in bullets (greek letters or · inside a bullet)
echo "--- P3: inline equations in bullets ---"
grep -nE '^\s*[-*•].*(α|β|γ|δ|ε|·|=\s*α|=\s*β)' "$MANUSCRIPT" || echo "(none)"

# P4: compliance-signaling subsection headers (case-insensitive — catches "Language discipline" and variants)
echo "--- P4: compliance-signaling subsection headers ---"
grep -niE '^##+\s+.*(language\s+discipline|inferential\s+approach|associational\s+framing|ethical\s+commitment|analytic\s+protocol|language\s+principles)' "$MANUSCRIPT" || echo "(none)"

# P5: 3+ subsections under a Methods-like section (scoped to Methods/Analytic/Strategy/Specification headers only,
# because §2 Background / §5 Results etc. legitimately use 3+ subsections in ASR/AJS/Demography/JMF)
echo "--- P5: over-subsectioned Methods section ---"
awk '
  /^## [0-9].*(Method|Methods|Analy[st]ic|Identification|Strategy|Specification)/ {in_sec=1; sec=$0; n=0; line=NR; next}
  /^## [0-9]/ {in_sec=0}
  in_sec && /^### / {n++; if (n==3) print "line " line ": " sec " has 3+ subsections through line " NR}
' "$MANUSCRIPT"

# P6: standalone language-discipline paragraph
echo "--- P6: language-discipline boilerplate paragraph ---"
grep -nE 'Throughout (the|this) paper we use (associational|causal).*language' "$MANUSCRIPT" || echo "(none)"
```

---

## Automated Lexical Scan (for T13)

Before the manual paragraph-by-paragraph scan, run this automated check to flag T13 words:

```bash
# T13 Automated Lexical Scan — run on the manuscript text file
echo "=== T13: Overused Lexical Patterns ==="
echo "--- Tier A (strong generic markers) ---"
grep -n -i -c -w 'delve\|delving\|tapestry\|beacon\|landscape\|realm\|embark\|embarking\|spearhead\|bustling\|pivotal\|commendable\|ingenious\|meticulous\|meticulously\|intricate\|intricacies\|underscores\|underpinning\|multifaceted' "$MANUSCRIPT" && \
grep -n -i -w 'delve\|delving\|tapestry\|beacon\|landscape\|realm\|embark\|embarking\|spearhead\|bustling\|pivotal\|commendable\|ingenious\|meticulous\|meticulously\|intricate\|intricacies\|underscores\|underpinning\|multifaceted' "$MANUSCRIPT"
echo ""
echo "--- Tier B (moderate generic markers) ---"
grep -n -i -c -w 'crucial\|foster\|fostering\|leverage\|navigate\|nuanced\|nuance\|robust\|cornerstone\|comprehensive\|encompasses\|harnessing\|noteworthy\|holistic\|transformative' "$MANUSCRIPT" && \
grep -n -i -w 'crucial\|foster\|fostering\|leverage\|navigate\|nuanced\|nuance\|robust\|cornerstone\|comprehensive\|encompasses\|harnessing\|noteworthy\|holistic\|transformative' "$MANUSCRIPT"
echo ""
echo "--- Tier C (context-dependent) ---"
grep -n -i -c -w 'elucidate\|illuminate\|unravel\|unveil\|unveiling\|bolster\|catalyze\|catalyst\|resonate\|resonates\|testament\|pave' "$MANUSCRIPT" && \
grep -n -i -w 'elucidate\|illuminate\|unravel\|unveil\|unveiling\|bolster\|catalyze\|catalyst\|resonate\|resonates\|testament\|pave' "$MANUSCRIPT"
echo ""
echo "--- Frequency markers (count-based) ---"
echo -n "underscores: "; grep -i -c -w 'underscores' "$MANUSCRIPT"
echo -n "aligns with: "; grep -i -c 'aligns with' "$MANUSCRIPT"
echo -n "sheds light: "; grep -i -c 'sheds\? light' "$MANUSCRIPT"
echo -n "plays a.*role: "; grep -i -c 'plays a.*role' "$MANUSCRIPT"
echo ""
echo "=== T16: Em-Dash Overuse ==="
echo -n "em-dashes (—): "; grep -o '—' "$MANUSCRIPT" | wc -l | tr -d ' '
echo -n "double-hyphens (--): "; grep -o '\-\-' "$MANUSCRIPT" | wc -l | tr -d ' '
TOTAL_LINES=$(wc -l < "$MANUSCRIPT")
APPROX_PAGES=$(( (TOTAL_LINES + 49) / 50 ))
echo "approx pages: $APPROX_PAGES"
echo "(>2 per page avg = MEDIUM, >4 per page avg = HIGH)"
```

```bash
# T18 Automated Causal Language Scan — run on the manuscript text file
echo "=== T18: Causal Language in Non-Causal Designs ==="
echo "--- Strong causal verbs ---"
grep -n -i -w 'shapes\|drives\|produces\|causes\|leads to\|results in\|gives rise to\|generates\|determines\|triggers' "$MANUSCRIPT" | head -30
echo ""
echo "--- Mechanistic phrasing ---"
grep -n -i 'through which.*affects\|mechanism by which\|operates by\|pathway from.*to' "$MANUSCRIPT" | head -20
echo ""
echo "--- Directional claims ---"
grep -n -i -w 'increases\|reduces\|enhances\|undermines\|diminishes\|amplifies\|exacerbates\|attenuates' "$MANUSCRIPT" | head -30
echo ""
echo "--- Implicit causation ---"
grep -n -i 'the effect of\|the impact of\|contributes to' "$MANUSCRIPT" | head -20
echo ""
echo "--- Counts ---"
echo -n "strong causal verbs: "; grep -i -c -w 'shapes\|drives\|produces\|causes\|determines\|triggers' "$MANUSCRIPT"
echo -n "mechanistic phrases: "; grep -i -c 'through which.*affects\|mechanism by which\|operates by\|pathway from.*to' "$MANUSCRIPT"
echo -n "'effect of'/'impact of': "; grep -i -c 'the effect of\|the impact of' "$MANUSCRIPT"
echo "(Severity depends on research design — check Methods section first)"
```

Include T13, T16, and T18 results in the scan report table alongside the structural tells (T1-T18).

---

## Mode 1: SCAN

Read the target file and produce a diagnostic report.

### Step 1.1 — Read and Segment
Read the entire manuscript/section file. Segment into paragraphs. Count total paragraphs, sentences, and words.

### Step 1.2 — Pattern Detection
For each of the 18 tells (T1-T18), scan every paragraph. **For T18**: before scanning paragraphs, first read the Methods section (or abstract) to determine the research design. If the design is causal (RCT, quasi-experimental with valid identification strategy), skip T18 entirely. Record:
- **Location**: paragraph number and opening words
- **Tell ID**: T1-T18
- **Severity**: LOW (subtle, could pass) | MEDIUM (noticeable to trained reader) | HIGH (obvious generic pattern)
- **Excerpt**: the offending phrase (max 15 words, with `...` truncation)

### Step 1.3 — Frequency Analysis
Count occurrences of each tell. Compute:
- **Style Score**: 0-100 scale (0 = distinctive voice, 100 = fully generic). Formula:
  - Each HIGH = 5 points, MEDIUM = 2 points, LOW = 1 point
  - Cap at 100
- **Top 3 tells**: the most frequent patterns
- **Worst paragraphs**: the 5 paragraphs with the highest tell density

### Step 1.4 — Produce Scan Report

```markdown
# Style Polish Scan Report: [filename]
**Date**: [YYYY-MM-DD]
**Style Score**: [N]/100
**Total tells detected**: [N] (HIGH: [n], MEDIUM: [n], LOW: [n])

## Tell Frequency
| Tell | Count | HIGH | MED | LOW | Description |
|------|-------|------|-----|-----|-------------|
| T2   | 14    | 3    | 8   | 3   | Formulaic transitions |
| T5   | 9     | 2    | 5   | 2   | "This..." anaphora |
| ...  | ...   | ...  | ... | ... | ... |

## Worst Paragraphs
| Para # | Opening Words | Tells | Score |
|--------|--------------|-------|-------|
| 3      | "Moreover, it is important..." | T2, T1, T8 | 12 |
| ...    | ... | ... | ... |

## Detailed Findings
### T2 — Formulaic Transitions (14 instances)
1. Para 3: "**Moreover**, it is important to note..." → HIGH
2. Para 7: "**Furthermore**, recent scholarship..." → MEDIUM
...

## Recommendation
[LIGHT / MODERATE / AGGRESSIVE rewrite recommended based on Style Score]
- Score 0-15: No action needed
- Score 16-35: LIGHT pass (fix HIGH tells only)
- Score 36-60: MODERATE pass (fix HIGH + MEDIUM)
- Score 61-100: AGGRESSIVE pass (comprehensive rewrite)
```

If mode is SCAN only, save the report and stop.

---

## Mode 2: REWRITE

Apply human writing micro-patterns to the manuscript. Requires a scan report (run SCAN first, or auto-run in FULL mode).

### Step 2.1 — Set Intensity Threshold
Based on intensity setting:
- **LIGHT**: Fix only HIGH-severity tells
- **MODERATE**: Fix HIGH + MEDIUM tells
- **AGGRESSIVE**: Fix all tells (HIGH + MEDIUM + LOW)

### Step 2.2 — Apply Fixes by Tell Type

Process the manuscript paragraph by paragraph. For each flagged tell:

**T1 (Hedging Stacks)**: Identify all hedges in the sentence. Keep only the one closest to the actual uncertainty. Example:
- Before: "It is important to note that this finding potentially suggests that income may play a role"
- After: "This finding suggests that income plays a role"

**T2 (Formulaic Transitions)**: Delete the transition word. Restructure if needed. Occasionally replace with a short conjunction ("But", "Yet", "And", "Still") — these are underrepresented in generic prose.
- Before: "Moreover, residential segregation has been linked to health disparities."
- After: "Residential segregation has been linked to health disparities." OR "And residential segregation compounds the effect..."

**T3 (Symmetrical Parallelism)**: Break one parallel. Make one clause longer or shorter. Add a parenthetical.
- Before: "Not only does poverty affect health, but it also shapes educational outcomes."
- After: "Poverty affects health — and, less obviously, shapes educational outcomes too."

**T4 (Tricolon Habit)**: Collapse, expand, or restructure.
- Before: "economic, social, and political factors"
- After: "economic and social factors" or "economic, social, political, and demographic factors"

**T5 (Anaphoric "This")**: Vary the referent.
- Before: "This finding aligns with prior work. This suggests that..."
- After: "The 3-percentage-point gap aligns with prior work, suggesting that..."

**T6 (Over-Enumeration)**: Remove count announcements. Let ideas flow.
- Before: "Three key findings emerge from our analysis. First,... Second,... Third,..."
- After: "The clearest result is [finding 1]... [Finding 2] complicates this picture... [Finding 3], by contrast,..."

**T7 (Definitional Opening)**: Enter concepts in action.
- Before: "Social disorganization theory posits that..."
- After: "Neighborhoods with weak institutional ties — the core of social disorganization theory — showed..."

**T8 (Empty Metacommentary)**: Delete and start with substance.
- Before: "In this section, we examine the relationship between X and Y."
- After: [Delete. The section heading already says this.]

**T9 (Uniform Sentence Length)**: Inject a short punchy sentence (5-10 words) after a complex one. Allow one genuinely long sentence (40+ words) per paragraph.
- Insert: "The effect was large." after a methodological detail sentence.
- Extend: Combine two mid-length sentences into one longer one with embedded clauses.

**T10 (Adjective/Adverb Inflation)**: Strip to one modifier max.
- Before: "This is a particularly noteworthy and highly significant contribution"
- After: "This contribution matters because..."

**T11 (Passive Avoidance)**: Restore passive in methods/results where conventional.
- Before: "We estimated a multilevel model with random intercepts."
- After: "A multilevel model with random intercepts was estimated." (in Methods)

**T12 (Conclusion Echo)**: Rewrite conclusion sentences that merely paraphrase the introduction. Advance the argument.

**T13 (LLM Lexical Fingerprint)**: Replace flagged AI-frequency words with plain academic English. Use the automated scan results from the "Automated Lexical Scan" section above.
- "delve into" → "examine", "explore", "investigate"
- "pivotal" → "important", "central", or delete
- "multifaceted" → "complex", or name the actual facets
- "underscores" → "shows", "demonstrates", "confirms" (keep 1 instance max)
- "navigate challenges" → "face challenges", "handle"
- "sheds light on" → "clarifies", "explains", "reveals"
- "foster understanding" → "build understanding", "promote"
- "nuanced" → "detailed", "specific", "careful", or delete
- "landscape" (non-literal) → "field", "area", "body of work"
- "robust" (non-statistical) → "strong", "solid", "reliable"
- "aligns with" → "matches", "is consistent with", "fits" (keep 1-2 instances max)
- "holistic" → "comprehensive", "full", "integrated"

**T14 (Performative Depth Signaling)**: Delete the signaling phrase. If the sentence still works without it, it was filler.
- "It is important to recognize that..." → delete, start with substance
- "This raises important questions about..." → state the questions directly
- "The implications are far-reaching..." → state the specific implications

**T15 (Excessive Discourse Connectives)**: Count connectives per page. If >3 per page average, cut half. Keep only where the logical turn is surprising.
- "Therefore" before an expected conclusion → delete
- "However" before a genuine contradiction → keep
- "In contrast" where the contrast is already obvious from content → delete

**T16 (Excessive Em-Dashes)**: Replace most em-dashes with conventional academic alternatives. Target: max 1-2 per page.
- Appositive dashes → parentheses or comma-set "which" clause: "segregation — measured by D — predicts" → "segregation (measured by D) predicts" or "segregation, measured by D, predicts"
- List-introducing dashes → "including", "such as", "namely": "three factors — X, Y, Z — drive" → "three factors, including X, Y, and Z, drive"
- Clause-joining dashes → period or semicolon: "The effect was large — larger than expected." → "The effect was large. It exceeded expectations."
- Elaboration dashes → "that is," / "specifically,": "weak ties — areas lacking anchors — showed" → "weak ties, specifically areas lacking anchors, showed"

**T18 (Causal Language in Non-Causal Designs)**: If the scan flagged T18 instances (i.e., the research design is non-causal), replace causal verbs with associational language. This is a **methodological** fix, not merely stylistic — Reviewer 2 will flag it.
- "X shapes Y" → "X is associated with Y" or "X tracks with Y"
- "X drives Y" → "X predicts Y" or "X is associated with Y"
- "X leads to Y" → "X predicts Y" or "X is linked to Y"
- "the effect of X on Y" → "the association between X and Y" or "the coefficient for X"
- "the impact of X" → "the relationship between X and Y"
- "X increases/reduces Y" → "X is positively/negatively associated with Y" or "higher X predicts higher/lower Y"
- Keep "predicts" — it is standard in regression contexts even for non-causal designs
- If the original already hedges ("X may shape Y"), downgrade to LOW and consider leaving as-is
- In Theory/Lit Review sections: do NOT flag causal language attributed to cited experimental or quasi-experimental work
- **Important**: This fix changes claim *strength*, not claim *content*. The argument structure (which variables relate to which) survives intact. Absolute Rule #2 is not violated because the logical flow is preserved — only the epistemic confidence is calibrated to match the design.

### Step 2.3 — Human Micro-Pattern Injection (Tiny Topos)

Beyond fixing tells, inject these *positive* human writing markers that LLMs rarely produce:

1. **The mid-sentence qualification**: "Segregation — at least as measured by dissimilarity indices — predicts..."
2. **The concessive start**: "Granted, our sample overrepresents..." or "To be sure, cross-sectional data cannot..."
3. **The self-aware limitation**: "We are aware that this operationalization is imperfect, but..."
4. **The fieldwork/data aside**: "The survey, fielded during a particularly contentious election season, may capture..."
5. **The specific-over-generic**: Replace "recent scholarship" with "work since the 2015 replication crisis" or "post-Chetty mobility studies"
6. **The rhetorical question** (once per paper, max): "But does neighborhood context operate the same way for renters?"
7. **The tonal break**: One sentence per section that is noticeably more casual than its neighbors. "The effect size was, frankly, smaller than we expected."
8. **The imperfect enumeration**: A list where items aren't grammatically parallel. "We control for age, household income, whether the respondent owns their home, and years in the neighborhood."
9. **The embedded citation aside**: "Coleman's (1988) much-cited — if occasionally misread — argument about social capital..."
10. **The late-arriving caveat**: Place a qualification at the end of the paragraph rather than hedging up front. State the finding boldly, *then* note the limitation.

Apply 2-4 of these per page, distributed naturally. Never cluster them.

### Step 2.4 — Consistency Check
After all edits:
- Verify no citations were altered or removed
- Verify no statistics were changed
- Verify argument structure is intact (same claims, same order, same evidence)
- Verify all `[CITATION NEEDED]` markers survive
- Count words: the rewrite should be within +/- 5% of the original word count

### Step 2.5 — Produce Diff Summary

```markdown
## Style Polish Edit Summary
- **Paragraphs modified**: [N] of [total]
- **Tells fixed**: [N] (T1: [n], T2: [n], ...)
- **Micro-patterns injected**: [N]
- **Word count**: [original] → [new] ([+/- N]%)
- **Estimated new Style Score**: [N]/100 (was [original])
```

---

## Mode 3: FULL

Execute Mode 1 (SCAN) then Mode 2 (REWRITE) sequentially. This is the default.

---

## Save Output

### Version Collision Avoidance (MANDATORY)

**Before EVERY Write tool call below**, run this Bash block to determine the correct save path. Do NOT hardcode paths from the filename templates — they show naming patterns only.

```bash
# MANDATORY: Replace [slug] and [YYYY-MM-DD] with actuals before running
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
# BASE pattern: ${OUTPUT_ROOT}/[slug]/polish/scholar-polish-[slug]-[YYYY-MM-DD]
OUTDIR="$(dirname "${OUTPUT_ROOT}/[slug]/polish/scholar-polish-[slug]-[YYYY-MM-DD]")"
STEM="$(basename "${OUTPUT_ROOT}/[slug]/polish/scholar-polish-[slug]-[YYYY-MM-DD]")"
mkdir -p "$OUTDIR"
bash "${SCHOLAR_SKILL_DIR:-.}/scripts/gates/version-check.sh" "$OUTDIR" "$STEM"


```

**Use the printed `SAVE_PATH` as `file_path` in the Write tool call.** Re-run this block (with the appropriate BASE) for each additional file. The same version suffix must be used for all related output files.

---

### File 1 — Style Polish Scan Report (SCAN and FULL modes)

**Filename**: `output/[slug]/polish/scholar-polish-scan-[slug]-[YYYY-MM-DD].md`

Contains the full scan report from Step 1.4.

### File 2 — Rewritten Manuscript (REWRITE and FULL modes)

**Filename**: `output/[slug]/polish/scholar-polish-rewrite-[slug]-[YYYY-MM-DD].md`

The full rewritten text with all fixes applied. This is the primary deliverable — a drop-in replacement for the original file.

### File 3 — Edit Log (REWRITE and FULL modes)

**Filename**: `output/[slug]/polish/scholar-polish-log-[slug]-[YYYY-MM-DD].md`

Contains:
- Diff summary from Step 2.5
- Every individual edit: original text → replacement text, with tell ID and rationale
- List of micro-patterns injected with locations

### Pandoc Conversions

For File 2 (the rewritten manuscript), generate multi-format output:

```bash
# CRITICAL: Replace [saved-md-path] with the EXACT path you used in the Write tool call above.
MD_FILE="[saved-md-path]"
BASE="${MD_FILE%.md}"
OUTDIR="$(dirname "$MD_FILE")"
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"

# Detect .bib file for citation processing
BIB_FILE=""
CITEPROC_FLAGS=""
for bib_candidate in "${OUTDIR}/references.bib" "${OUTPUT_ROOT}/citations/"*.bib "${OUTPUT_ROOT}/"*/citations/*.bib; do
  if [ -f "$bib_candidate" ]; then
    BIB_FILE="$(cd "$(dirname "$bib_candidate")" && pwd)/$(basename "$bib_candidate")"
    CITEPROC_FLAGS="--citeproc --bibliography=\"$BIB_FILE\" --metadata reference-section-title=\"References\""
    echo "Found .bib for citation processing: $BIB_FILE"
    break
  fi
done

eval pandoc "${BASE}.md" -o "${BASE}.docx" \
  $CITEPROC_FLAGS \
  --reference-doc="$HOME/.pandoc/reference.docx" 2>/dev/null \
  || eval pandoc "${BASE}.md" -o "${BASE}.docx" $CITEPROC_FLAGS

eval pandoc "${BASE}.md" -o "${BASE}.tex" --standalone \
  $CITEPROC_FLAGS \
  -V geometry:margin=1in -V fontsize=12pt

eval pandoc "${BASE}.md" -o "${BASE}.pdf" \
  --pdf-engine=xelatex \
  $CITEPROC_FLAGS \
  -V geometry:margin=1in -V fontsize=12pt 2>/dev/null \
  || echo "PDF generation requires a LaTeX engine"

echo "Converted: ${BASE}.md -> .docx, .tex, .pdf"
if [ -n "$BIB_FILE" ]; then echo "Citations resolved via: $BIB_FILE"; fi
```

---

**Close Process Log:**

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
SKILL_NAME="scholar-polish"
LOG_DATE=$(date +%Y-%m-%d)
LOG_FILE="${OUTPUT_ROOT}/logs/process-log-${SKILL_NAME}-${LOG_DATE}.md"
if [ ! -f "$LOG_FILE" ]; then
  LOG_FILE=$(ls -t "${OUTPUT_ROOT}"/logs/process-log-${SKILL_NAME}-${LOG_DATE}*.md 2>/dev/null | head -1)
fi
cat >> "$LOG_FILE" << LOGFOOTER

## Output Files
[list each output file path as a bullet]

## Summary
- **Steps completed**: [N completed]/[N total]
- **Files produced**: [count]
- **Errors**: [count, or 0]
- **Time finished**: $(date +%H:%M:%S)
LOGFOOTER
echo "Process log saved to $LOG_FILE"
```

---

## Quality Checklist

- [ ] Target file identified and fully read
- [ ] All 18 tell types (T1-T18) scanned (T18 design-gated: checked Methods first)
- [ ] Style Score computed with severity weighting
- [ ] Scan report saved to disk (SCAN/FULL modes)
- [ ] Edits applied only to flagged tells at the correct intensity threshold
- [ ] 2-4 human micro-patterns injected per page
- [ ] No citations altered, removed, or fabricated
- [ ] No statistics changed
- [ ] No argument structure modified
- [ ] All `[CITATION NEEDED]` markers preserved
- [ ] Word count within +/- 5% of original
- [ ] Consistency check passed (Step 2.4)
- [ ] Rewritten manuscript saved to disk with multi-format conversion
- [ ] Edit log saved to disk with per-edit rationale
- [ ] Process log opened and closed
