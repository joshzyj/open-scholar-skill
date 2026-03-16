# Verification Standards & Common Error Catalog

## Journal-Specific Verification Requirements

### ASR / AJS
- AME preferred over odds ratios for logistic models — verify conversion accuracy
- All significance claims must use conventional thresholds (p < 0.05)
- Descriptive statistics table required — verify N, means, SDs match analysis output
- Robustness checks in appendix — verify all are referenced in text

### Demography
- Most technically demanding — every number will be scrutinized by reviewers
- Decomposition results (Kitagawa, Oaxaca-Blinder) must sum correctly
- Life table values must be internally consistent
- Replication file required — verify script-to-output traceability

### Science Advances
- Reporting Summary required — verify consistency with manuscript claims
- Data/code availability statement — verify URLs and DOIs resolve
- Effect sizes and confidence intervals required — verify CI bounds

### Nature Human Behaviour / NCS
- Extended Data tables/figures — verify numbering (ED Fig. 1, ED Table 1)
- Reporting Summary — every field must match manuscript
- Pre-registration statement — verify claims match registered protocol
- Code availability — verify repository link exists and is complete

## Common Transcription Error Taxonomy

### Category 1: Digit Errors
| Type | Example | Frequency |
|------|---------|-----------|
| Transposition | 0.23 → 0.32 | Very common |
| Dropped digit | 0.234 → 0.23 (may be rounding) or 0.234 → 0.24 | Common |
| Added digit | 0.23 → 0.234 | Uncommon |
| Wrong sign | -0.14 → 0.14 | Common, often catastrophic |

### Category 2: Wrong Source
| Type | Example | Frequency |
|------|---------|-----------|
| Wrong column | Model 3 value reported as Model 2 | Very common |
| Wrong row | Education value reported for Income | Common |
| Wrong table | Table 2 value cited as Table 3 | Common |
| Old version | Value from previous analysis run | Very common with iterative revisions |

### Category 3: Conversion Errors
| Type | Example | Frequency |
|------|---------|-----------|
| Log-odds vs. probability | b=0.5 reported as "50% increase" instead of ~12pp | Common |
| Odds ratio vs. coefficient | OR=1.5 reported as "0.5 increase" | Common |
| AME computation error | AME computed at wrong values | Occasional |
| Percentage vs. proportion | 0.05 reported as "5%" when it should be "0.05 units" | Common |
| Standard deviation scaling | "1 SD increase" computed with wrong SD | Occasional |

### Category 4: Significance Errors
| Type | Example | Frequency |
|------|---------|-----------|
| Star threshold mismatch | Note says * p<0.05 but stars applied at p<0.10 | Occasional |
| Marginal significance | p=0.06 described as "significant" | Common |
| Multiple comparison oversight | Individual p<0.05 but Bonferroni-adjusted p>0.05 | Common |
| One-tailed vs. two-tailed | p=0.08 two-tailed described as "significant" (one-tailed) | Occasional |

### Category 5: Figure-Specific Errors
| Type | Example | Frequency |
|------|---------|-----------|
| Stale figure | Figure generated from old data/model | Very common |
| Wrong CI level | 90% CI plotted but "95% CI" in caption | Occasional |
| Axis scale mismatch | Log scale in figure, linear in text | Occasional |
| Panel label swap | Panel A and B switched in text description | Common |
| Legend error | Groups mislabeled or colors swapped | Occasional |

## Verification Heuristics

### Red Flags That Warrant Extra Scrutiny
1. **Round numbers in regression output** (0.100, 0.200) — suspicious precision
2. **Identical coefficients across models** — possible copy-paste error
3. **N changes between tables without explanation** — different sample constructions
4. **R² decreases when adding predictors** — possible error (or mis-specified model)
5. **All results significant** — possible selective reporting
6. **Confidence intervals that exactly touch zero** — possible manipulation
7. **Standard errors smaller than expected** — possible clustering error

### Acceptable Rounding Differences
- ±1 in last reported decimal place: WARNING (not CRITICAL)
- ±2 or more: CRITICAL
- Inconsistent decimal places across a table: WARNING
- Inconsistent decimal places across text and table: WARNING
