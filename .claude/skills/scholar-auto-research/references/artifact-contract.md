# Artifact Contract

Artifact rules:

- Every phase writes to a canonical directory named by function, not by agent.
- Required outputs are relative to the project directory.
- A phase cannot pass from a prose heading or log note.
- Late phases must include structured verdict JSON, not only markdown.
- Final assembly must produce same-source `md`, `docx`, `tex`, and `pdf` plus `final/final-manifest.json`.

Known canonical directories:

- `safety/`
- `idea/`
- `literature/`
- `design/`
- `data/`
- `analysis/`
- `tables/`
- `figures/`
- `review/`
- `verify/`
- `results-locked/`
- `manuscript/`
- `citation/`
- `ethics/`
- `replication-package/`
- `quality/`
- `final/`
- `submission/`
