## MODULE 5: Computational Reproducibility

For preregistration, data sharing, and Zenodo DOI archiving, invoke `/scholar-open`.

This module covers compute-specific reproducibility only.

### Project Directory Structure

```
project/
├── README.md              ← How to reproduce; hardware specs; estimated runtime
├── environment.yml        ← Conda environment (Python)
├── renv.lock              ← renv lockfile (R)
├── Makefile               ← Pipeline automation (optional; see below)
├── data/
│   ├── raw/               ← Never modified; README with source + access date
│   ├── clean/
│   └── analysis/
├── code/
│   ├── 01_clean.py / .R
│   ├── 02_eda.py / .R
│   ├── 03_model.py / .R
│   └── 04_figures.py / .R
├── output/
│   ├── figures/
│   ├── tables/
│   └── models/
└── paper/
    └── manuscript.tex
```

### Environment Files

```yaml
# environment.yml (Python)
name: scholar-project
channels: [conda-forge, defaults]
dependencies:
  - python=3.11
  - numpy=1.26
  - pandas=2.1
  - scikit-learn=1.3
  - transformers=4.35
  - gensim=4.3
  - networkx=3.2
  - econml=0.15
  - shap=0.43
  - mesa=2.1
  - SALib=1.5
  - optuna=3.5
  - anthropic
  - matplotlib=3.8
  - seaborn=0.13
```

```r
# R reproducibility — use renv
renv::init()
# install packages...
renv::snapshot()   # writes renv.lock
# Restore on another machine:
# renv::restore()
```

### Makefile Pipeline

```makefile
all: clean model figures

clean:
	Rscript code/01_clean.R

model:
	python code/03_model.py

figures:
	Rscript code/04_figures.R

.PHONY: all clean model figures
```

### Seed Discipline

```python
# Python: set at top of every script
import random, numpy as np, torch
SEED = 42
random.seed(SEED); np.random.seed(SEED); torch.manual_seed(SEED)
```

```r
# R: set at top of every script
set.seed(42)
```

Report in the Methods section: *"All stochastic analyses used random seed 42."*

### Computational Reproducibility: Containerization

**Docker** (recommended for NCS, Science Advances):
```dockerfile
# Dockerfile for reproducible analysis
FROM rocker/verse:4.3.2
# Install system dependencies
RUN apt-get update && apt-get install -y libxml2-dev libcurl4-openssl-dev
# Install R packages from renv.lock
COPY renv.lock renv.lock
RUN R -e "install.packages('renv'); renv::restore()"
# Copy analysis code
COPY . /project
WORKDIR /project
CMD ["Rscript", "run_all.R"]
```

```dockerfile
# Python Dockerfile
FROM python:3.11-slim
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . /project
WORKDIR /project
CMD ["python", "run_all.py"]
```

**Build & run**:
```bash
docker build -t my-analysis .
docker run --rm -v $(pwd)/output:/project/output my-analysis
```

**Code Ocean**: For NCS submissions, create a Code Ocean capsule (https://codeocean.com) with the same Dockerfile. Include `postInstall` script for dependencies.

**Singularity** (for HPC clusters):
```bash
singularity build analysis.sif docker://my-analysis:latest
singularity run analysis.sif
```

---

