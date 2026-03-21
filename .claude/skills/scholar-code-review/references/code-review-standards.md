# Code Review Standards Reference

## Common Error Catalogs

### Statistical Implementation Errors
- Off-by-one in lag/lead construction
- Wrong reference category in factor variables
- Missing cluster/robust SE specification
- Incorrect degrees of freedom for small-sample corrections
- Applying log() to variables with zeros without adding 1 or using asinh()

### AI-Generated Code Anti-Patterns
- Hallucinated function names (packages that don't export the function)
- Deprecated API usage (e.g., `aes_string()` instead of `aes()` with `.data[[]]`)
- Overly verbose variable assignments instead of piped operations
- Unnecessary `as.data.frame()` calls on tibbles
- Redundant `library()` calls or conflicting package loads
- Comments that restate the code rather than explain intent

### Data Handling Errors
- Miscoded categorical variables (numeric codes treated as continuous)
- Wrong handling of missing values (listwise deletion when MI appropriate)
- Sample restriction errors (filtering before vs. after merge)
- Incorrect variable recoding (inverted scales, wrong cutpoints)
- Unintended NA introduction from joins

## Journal-Specific Computational Reproducibility Requirements

| Journal | Requirements |
|---------|-------------|
| Nature Computational Science | Docker/Singularity container; all code on GitHub/Zenodo with DOI; random seeds documented |
| Science Advances | Code availability statement; data deposition; computational methods fully described |
| ASR / AJS | Replication package encouraged; code sharing increasingly expected |
| Demography | Replication materials required; AEA-style README |
