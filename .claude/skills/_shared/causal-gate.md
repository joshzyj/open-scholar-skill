# Causal Design Detection Gate (Shared)

When a skill encounters research questions or analysis plans that involve causal claims, this gate determines whether to invoke scholar-causal.

## Detection Keywords

```bash
CAUSAL_KEYWORDS="causal|DiD|difference.in.difference|regression.discontinuity|instrumental.variable|IV\b|propensity.score|matching|synthetic.control|fixed.effect|treatment.effect|RCT|experiment|quasi.experiment|endogeneity|selection.bias|counterfactual|identification.strategy"
```

## Gate Levels

| Level | Action | Used by |
|-------|--------|---------|
| HARD | Block advancement until scholar-causal runs | scholar-design |
| SOFT | Warn user; recommend scholar-causal; proceed if declined | scholar-eda, scholar-analyze, scholar-compute |
| INFO | Log detection; no blocking | scholar-brainstorm, scholar-idea |

## Invocation Pattern

```bash
# Check if causal design is detected in the research question or design doc
RQ_FILE="[path to research question or design document]"
CAUSAL_HIT=$(grep -cEi "$CAUSAL_KEYWORDS" "$RQ_FILE" 2>/dev/null || echo 0)

if [ "$CAUSAL_HIT" -gt 0 ]; then
  echo "CAUSAL DESIGN DETECTED ($CAUSAL_HIT keyword matches)"
  echo "Recommended: Run /scholar-causal before proceeding to analysis"
  # HARD gate: halt here
  # SOFT gate: prompt user
  # INFO gate: log and continue
fi
```

## What scholar-causal Provides

1. DAG construction (text-based or visual)
2. Identification strategy selection (13 strategies)
3. Assumption documentation
4. Diagnostic checklist
5. Methods section draft language
