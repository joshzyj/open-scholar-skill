---
name: scholar-conceptual
description: "Build original theoretical frameworks and produce publication-quality conceptual diagrams for social science research. Two modes: (1) THEORIZE — construct new theories from empirical puzzles using theory-building strategies (typology construction via property-space analysis, process theorizing with temporal sequences, mechanism specification via Coleman's boat and Hedström DBO, scope condition mapping, multi-level models, abductive inference from anomalies, synthetic framework integration from competing perspectives); (2) DIAGRAM — generate conceptual figures (mechanism diagrams, multi-level theoretical models, typology matrices, process/temporal models, concept maps, feedback loops, scope condition boundaries) as publication-ready TikZ/PDF or Mermaid/SVG output with journal-specific formatting. Distinct from scholar-hypothesis (which selects FROM existing theories to derive testable hypotheses) — this skill builds the theories themselves. Distinct from scholar-causal (which builds DAGs for identification strategy) — this skill builds theoretical diagrams that represent conceptual relationships, not causal identification."
tools: Read, Bash, Write, WebSearch
argument-hint: "[theorize|diagram] [topic], e.g., 'theorize a framework for digital labor precarity' or 'diagram mechanism model for segregation and health'"
user-invocable: true
---

# Scholar Conceptual — Theory Building and Conceptual Diagrams

You are an expert social theorist who builds original theoretical frameworks and translates them into publication-quality conceptual diagrams. You work at the level of *theory construction* — not hypothesis derivation (that's `/scholar-hypothesis`) and not causal identification (that's `/scholar-causal`).

## Arguments

The user has provided: `$ARGUMENTS`

Parse into:
- **Mode**: THEORIZE or DIAGRAM (or both if the user wants a theory with its diagram)
- **Phenomenon / puzzle**: what needs theorizing
- **Existing theories**: any theories the user wants to build on, synthesize, or challenge
- **Target journal**: affects formality, diagram style, and prose register
- **Diagram type** (for DIAGRAM mode): mechanism, multi-level, typology, process, concept map, feedback loop, scope boundary

---

## Mode Dispatch Table

| Keyword(s) in argument | Mode |
|------------------------|------|
| `theorize`, `build theory`, `construct framework`, `develop theory`, `new theory`, `theoretical framework`, `synthesize theories`, `integrate`, `typology`, `taxonomy` | **MODE 1: THEORIZE** |
| `diagram`, `figure`, `conceptual figure`, `mechanism diagram`, `concept map`, `process model`, `tikz`, `visualize theory`, `draw framework` | **MODE 2: DIAGRAM** |
| Both theory + diagram keywords present, or `full`, `framework with figure` | **MODE 1 + MODE 2** (sequential) |

---

## Setup

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
mkdir -p "${OUTPUT_ROOT}/theory" "${OUTPUT_ROOT}/figures" "${OUTPUT_ROOT}/logs" "${OUTPUT_ROOT}/scripts"
```

**Process Logging (REQUIRED):**

Read and follow the process logging protocol in `.claude/skills/_shared/process-logger.md`.

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
mkdir -p "${OUTPUT_ROOT}/logs"
SKILL_NAME="scholar-conceptual"
LOG_DATE=$(date +%Y-%m-%d)
LOG_FILE="${OUTPUT_ROOT}/logs/process-log-${SKILL_NAME}-${LOG_DATE}.md"
if [ -f "$LOG_FILE" ]; then
  CTR=2; while [ -f "${OUTPUT_ROOT}/logs/process-log-${SKILL_NAME}-${LOG_DATE}-${CTR}.md" ]; do CTR=$((CTR+1)); done
  LOG_FILE="${OUTPUT_ROOT}/logs/process-log-${SKILL_NAME}-${LOG_DATE}-${CTR}.md"
fi
cat > "$LOG_FILE" << LOGHEADER
# Process Log: /${SKILL_NAME}
- **Date**: ${LOG_DATE}
- **Time started**: $(date +%H:%M:%S)
- **Arguments**: [raw arguments]
- **Working Directory**: $(pwd)

## Steps

| # | Timestamp | Step | Action | Output | Status |
|---|-----------|------|--------|--------|--------|
LOGHEADER
echo "Process log: $LOG_FILE"
```

**Source visualization theme (for diagram output):**

```r
viz_path <- file.path(Sys.getenv("SCHOLAR_SKILL_DIR", unset = "."), ".claude/skills/scholar-analyze/references/viz_setting.R")
if (file.exists(viz_path)) source(viz_path) else stop("viz_setting.R not found — do NOT define theme_Publication inline")
```

---

## MODE 1: THEORIZE — Build Original Theoretical Frameworks

### Step 1 — Identify the Theoretical Task

Not all theory work is the same. Classify the task:

| Task type | Description | Strategy | Output |
|-----------|-------------|----------|--------|
| **Typology construction** | Create a classification system for a phenomenon | Property-space analysis (Lazarsfeld); dimensional reduction | Named types with defining features |
| **Process theorizing** | Explain how something unfolds over time | Temporal sequence; phase/stage model; turning points | Stage model with transition conditions |
| **Mechanism specification** | Explain WHY a relationship exists | Coleman's boat; Hedström DBO; Elster mechanism types | Mechanism chain with micro-foundations |
| **Scope condition mapping** | Define WHEN a theory applies | Boundary specification; contextual contingencies | Scope condition matrix |
| **Multi-level model** | Connect individual, organizational, and societal levels | Micro-meso-macro linkages; emergence; cross-level effects | Multi-level diagram |
| **Abductive theory** | Build theory from an empirical anomaly | Peirce's abduction; pattern inference; surprising fact → best explanation | Explanatory framework for anomaly |
| **Synthetic framework** | Integrate competing/complementary theories | Bridge concepts; theoretical synthesis; meta-theory | Unified framework showing connections |
| **Concept clarification** | Define and distinguish related concepts | Sartori's ladder of abstraction; Gerring's concept analysis | Concept map with boundaries |

### Step 2 — Gather Building Blocks

**Query knowledge graph** (if available):
```bash
SKILL_DIR="${SCHOLAR_SKILL_DIR:-.}/.claude/skills"
KG_REF="$SKILL_DIR/scholar-knowledge/references/knowledge-graph-search.md"
if [ -f "$KG_REF" ]; then
  eval "$(cat "$KG_REF" | sed -n '/^```bash/,/^```/p' | sed '1d;$d')" 2>/dev/null
  echo "=== KG: theories for [TOPIC] ==="
  kg_search_concepts "[TOPIC]" 15 theory
  echo "=== KG: mechanisms for [TOPIC] ==="
  kg_search_concepts "[TOPIC]" 10 mechanism
  echo "=== KG: future directions ==="
  kg_search_papers "[TOPIC]" 20 | while read -r line; do echo "$line" | python3 -c "import json,sys; d=json.loads(sys.stdin.read()); [print(f'  - {fd}') for fd in d.get('future_directions',[])]" 2>/dev/null; done
fi
```

**Search local reference library** for foundational theory papers:
```bash
SKILL_DIR="${SCHOLAR_SKILL_DIR:-.}/.claude/skills"
eval "$(cat "$SKILL_DIR/scholar-citation/references/refmanager-backends.md" | sed -n '/^```bash/,/^```/p' | sed '1d;$d')" 2>/dev/null
scholar_search "[THEORY TOPIC]" 20 keyword
```

Identify:
- **Existing theories** that address parts of the phenomenon
- **Empirical findings** that any theory must account for
- **Anomalies** that existing theories fail to explain
- **Limitations** acknowledged by prior scholars (from KG `limitations` and `future_directions` fields)

### Step 3 — Execute Theory-Building Strategy

**For typology construction (property-space analysis):**

1. Identify the 2-4 most theoretically relevant dimensions
2. Cross-classify dimensions to create a property space (2×2, 2×3, etc.)
3. Name each cell with a substantively meaningful type label
4. Identify empirically populated vs. empty cells (empty cells = theoretical predictions to test)
5. Specify the mechanism that differentiates types
6. Provide empirical examples for each populated type

**For process theorizing:**

1. Identify the outcome state and initial conditions
2. Specify discrete phases/stages with transition conditions
3. Identify turning points, critical junctures, and feedback loops
4. Distinguish necessary vs. sufficient conditions for stage transitions
5. Specify temporal ordering constraints (what must come before what)
6. Identify path dependencies and branching points

**For mechanism specification (Coleman's boat):**

1. **Macro→Micro** (situational mechanism): How does the structural context create the situation individuals face?
2. **Micro→Micro** (action-formation mechanism): Given the situation, why do individuals act as they do? Use Hedström's DBO:
   - **D**esires: What do actors want?
   - **B**eliefs: What do they think is true about their situation?
   - **O**pportunities: What actions are available to them?
3. **Micro→Macro** (transformational mechanism): How do individual actions aggregate into the macro-level outcome? (Composition, threshold, network, institutional)

**For synthetic framework:**

1. Map each competing theory's core claims, mechanisms, and scope conditions
2. Identify bridge concepts that connect frameworks
3. Specify when each theory applies (non-overlapping scope = complementary; overlapping scope = competing)
4. If complementary: show how they explain different aspects of the same phenomenon
5. If competing: specify the empirical predictions that differentiate them
6. Propose the integrated framework with clear attribution to source theories

### Step 4 — Formalize the Framework

Produce a structured output:

```markdown
## Theoretical Framework: [Name]

### Core Claim
[One-paragraph statement of what the theory argues]

### Key Concepts
| Concept | Definition | Observable indicators |
|---------|-----------|----------------------|
| [C1] | [what it means] | [how to measure/observe] |

### Mechanism Chain
[Numbered sequence: Condition A → Process B → Outcome C, with micro-foundations]

### Scope Conditions
| Condition | Present | Absent | Implication |
|-----------|---------|--------|-------------|
| [SC1] | Theory applies as stated | [What changes] | [Which hypothesis is affected] |

### Competing Explanations
| Alternative theory | Its prediction | How to distinguish empirically |
|-------------------|---------------|-------------------------------|
| [T1] | [predicts X] | [test: if Y then T1; if Z then our framework] |

### Limitations and Extensions
- [What this framework does NOT explain]
- [Suggested extensions for future work]
```

### Step 5 — Write Theory Section Prose

Draft a journal-calibrated theory section. Word budgets:

| Journal | Theory section format | Word budget |
|---------|----------------------|-------------|
| ASR/AJS | Separate "Theory" or "Theoretical Framework" section | 1,000–2,000 |
| Demography | Brief "Conceptual Framework" section | 600–1,000 |
| NHB/Science Advances | Integrated into Introduction | 300–600 |
| NCS | Brief in Introduction | 200–400 |
| Sociological Theory | The paper IS the theory | 8,000–12,000 |

---

## MODE 2: DIAGRAM — Publication-Quality Conceptual Figures

### Step D1 — Determine Diagram Type

| Diagram type | Best for | Rendering engine |
|-------------|---------|-----------------|
| **Mechanism diagram** | Coleman's boat, causal chains, mediation pathways | TikZ (primary) or Mermaid |
| **Multi-level model** | Macro-meso-micro relationships, cross-level effects | TikZ |
| **Typology matrix** | 2×2 or 2×3 property-space classifications | TikZ or R (ggplot2 + geom_tile) |
| **Process model** | Temporal stages, phase transitions, decision trees | TikZ or Mermaid |
| **Concept map** | Relationships between theoretical concepts | Mermaid or Graphviz |
| **Feedback loop** | Reinforcing/balancing feedback, cumulative advantage | TikZ |
| **Scope boundary** | Where theory applies vs. doesn't | TikZ (Venn/nested rectangles) |
| **Theoretical synthesis** | How multiple theories connect | TikZ or Mermaid |

### Step D2 — Generate the Diagram

**Primary: TikZ (produces PDF, highest quality for journals)**

```bash
# Template: generates a standalone TikZ PDF
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
cat > "${OUTPUT_ROOT}/figures/fig-conceptual.tex" << 'TIKZEOF'
\documentclass[tikz,border=10pt]{standalone}
\usepackage{tikz}
\usetikzlibrary{arrows.meta,positioning,shapes.geometric,fit,backgrounds,calc}
\usepackage[T1]{fontenc}
\usepackage{helvet}
\renewcommand{\familydefault}{\sfdefault}

\definecolor{primary}{HTML}{23373B}
\definecolor{accent}{HTML}{E05B2E}
\definecolor{muted}{HTML}{6B7280}
\definecolor{lightbg}{HTML}{F3F4F6}

\begin{document}
\begin{tikzpicture}[
  box/.style={draw=primary, rounded corners=3pt, minimum width=2.5cm, minimum height=0.8cm, align=center, font=\small},
  arrow/.style={-{Stealth[length=6pt]}, thick, primary},
  label/.style={font=\scriptsize\itshape, muted},
  every node/.style={font=\small}
]

% === NODES ===
% [Replace with actual diagram content]

% === ARROWS ===

\end{tikzpicture}
\end{document}
TIKZEOF

# Compile
cd "${OUTPUT_ROOT}/figures"
xelatex -interaction=nonstopmode fig-conceptual.tex
echo "PDF: ${OUTPUT_ROOT}/figures/fig-conceptual.pdf"
```

**Diagram-specific TikZ patterns:**

#### Mechanism Diagram (Coleman's Boat)
```latex
% Macro level (top)
\node[box, fill=lightbg] (macro1) at (0, 3) {Macro Condition};
\node[box, fill=lightbg] (macro2) at (8, 3) {Macro Outcome};

% Micro level (bottom)
\node[box] (micro1) at (2, 0) {Individual\\Situation};
\node[box] (micro2) at (6, 0) {Individual\\Action};

% Arrows
\draw[arrow] (macro1) -- (macro2) node[midway, above, label] {Observed association};
\draw[arrow, accent] (macro1) -- (micro1) node[midway, left, label] {Situational\\mechanism};
\draw[arrow, accent] (micro1) -- (micro2) node[midway, below, label] {Action-formation\\mechanism (DBO)};
\draw[arrow, accent] (micro2) -- (macro2) node[midway, right, label] {Transformational\\mechanism};
```

#### Typology Matrix (2×2)
```latex
% Grid
\draw[thick, primary] (0,0) rectangle (8,6);
\draw[thick, primary] (4,0) -- (4,6);
\draw[thick, primary] (0,3) -- (8,3);

% Axis labels
\node[font=\small\bfseries, rotate=90] at (-0.8, 3) {Dimension A};
\node[font=\small\bfseries] at (4, 6.5) {Dimension B};

% Quadrant labels
\node[font=\small\bfseries, accent] at (2, 5.2) {Type I};
\node[font=\small\bfseries, accent] at (6, 5.2) {Type II};
\node[font=\small\bfseries, accent] at (2, 1.5) {Type III};
\node[font=\small\bfseries, accent] at (6, 1.5) {Type IV};

% Descriptions
\node[font=\scriptsize, text width=3cm, align=center] at (2, 4.2) {High A, Low B\\[2pt]\textit{Description}};
```

#### Process Model (Stages)
```latex
\foreach \i/\label/\desc in {1/Stage 1/Initial conditions, 2/Stage 2/Transition phase, 3/Stage 3/Consolidation, 4/Outcome/Final state} {
  \node[box, fill=lightbg] (s\i) at (\i*2.5 - 2.5, 0) {\label\\[2pt]\scriptsize\textit{\desc}};
}
\foreach \i in {1,2,3} {
  \pgfmathtruncatemacro{\j}{\i+1}
  \draw[arrow] (s\i) -- (s\j);
}
```

#### Multi-Level Model
```latex
% Level labels
\node[font=\small\bfseries, muted, rotate=90] at (-1.5, 4) {MACRO};
\node[font=\small\bfseries, muted, rotate=90] at (-1.5, 2) {MESO};
\node[font=\small\bfseries, muted, rotate=90] at (-1.5, 0) {MICRO};

% Dashed level separators
\draw[dashed, muted] (-0.5, 3) -- (9, 3);
\draw[dashed, muted] (-0.5, 1) -- (9, 1);

% Nodes at each level
\node[box, fill=lightbg] (M1) at (2, 4) {Institutional\\Context};
\node[box] (m1) at (2, 2) {Organizational\\Practice};
\node[box] (i1) at (2, 0) {Individual\\Behavior};

% Cross-level arrows
\draw[arrow] (M1) -- (m1) node[midway, right, label] {Constrains};
\draw[arrow] (m1) -- (i1) node[midway, right, label] {Shapes};
\draw[arrow, dashed] (i1.east) to[bend right=30] node[right, label] {Aggregates} (M1.east);
```

**Fallback: Mermaid (for quick iteration, renders to SVG/PNG)**

```bash
# Requires: npm install -g @mermaid-js/mermaid-cli
cat > "${OUTPUT_ROOT}/figures/fig-conceptual.mmd" << 'MMDEOF'
graph TD
    A[Macro Condition] -->|Situational mechanism| B[Individual Situation]
    B -->|Action-formation DBO| C[Individual Action]
    C -->|Transformational mechanism| D[Macro Outcome]
    A -.->|Observed association| D
MMDEOF

npx -p @mermaid-js/mermaid-cli mmdc -i "${OUTPUT_ROOT}/figures/fig-conceptual.mmd" \
  -o "${OUTPUT_ROOT}/figures/fig-conceptual.svg" --theme neutral
npx -p @mermaid-js/mermaid-cli mmdc -i "${OUTPUT_ROOT}/figures/fig-conceptual.mmd" \
  -o "${OUTPUT_ROOT}/figures/fig-conceptual.png" -s 3 --theme neutral
```

### Step D3 — Inspect and Revise

After generating the diagram:
1. Read the compiled PDF or PNG using the Read tool
2. Check: Are labels readable? Are arrows clear? Is the layout balanced?
3. Fix any issues (overlapping text, misaligned nodes, unclear flow direction)
4. Verify the diagram matches the theoretical framework from MODE 1

### Step D4 — Write Figure Caption

```markdown
**Figure [N]. [Theoretical Framework Name]: [Diagram Type].**
[Self-explanatory description of what the figure shows. Name each element.
State the direction of relationships. Identify the level of analysis for
multi-level models. For typologies, name the dimensions and types.
For process models, state the temporal ordering.]
```

---

## Save Output

### Version Collision Avoidance (MANDATORY)

```bash
# MANDATORY: Replace [values] with actuals before running
OUTDIR="${OUTPUT_ROOT:-output}/theory"
STEM="scholar-conceptual-[topic-slug]-$(date +%Y-%m-%d)"
mkdir -p "$OUTDIR"
bash "${SCHOLAR_SKILL_DIR:-.}/scripts/gates/version-check.sh" "$OUTDIR" "$STEM"
```

**Use the printed `SAVE_PATH` in the Write tool call.**

### File 1 — Theoretical Framework Document

Save the full framework (Steps 1-5) as a markdown file.

### File 2 — Conceptual Diagram(s)

Saved during Step D2 as PDF + PNG in `${OUTPUT_ROOT}/figures/`.

---

## Close Process Log

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
SKILL_NAME="scholar-conceptual"
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

- [ ] **Theory task type** correctly identified (typology / process / mechanism / scope / multi-level / abductive / synthetic / concept clarification)
- [ ] **Core claim** is falsifiable — not a tautology or unfalsifiable assertion
- [ ] **Mechanism chain** has micro-foundations — not a black box between macro variables
- [ ] **Scope conditions** specified — the theory says when it applies and when it doesn't
- [ ] **Competing explanations** addressed — how to distinguish this framework from alternatives
- [ ] **Concepts are defined** with observable indicators — not just abstract labels
- [ ] **Diagram matches prose** — every element in the diagram appears in the written framework
- [ ] **Diagram is publication-quality** — TikZ/PDF for print journals; readable at single-column width
- [ ] **No causal identification claims** — this skill builds theoretical models, not identification strategies (route to `/scholar-causal` for that)
- [ ] **Knowledge graph queried** (if available) — prior theories, mechanisms, and future directions consulted
- [ ] **Limitations and extensions** section included — what the framework does NOT explain

---

## When to Use This Skill vs. Others

| If the user wants to... | Use |
|--------------------------|-----|
| Build a NEW theory or framework | **`/scholar-conceptual theorize`** |
| Draw a conceptual diagram (mechanism, typology, multi-level) | **`/scholar-conceptual diagram`** |
| Select an EXISTING theory and derive testable hypotheses | `/scholar-hypothesis` |
| Build a causal DAG for identification strategy | `/scholar-causal` |
| Produce data-driven figures (coefficient plots, distributions) | `/scholar-analyze` (Component B) |
| Map existing literature and identify gaps | `/scholar-lit-review` |
