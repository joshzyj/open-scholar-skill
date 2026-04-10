---
name: scholar-data
description: Comprehensive open data directory (100+ datasets across 14 categories) with auto-fetch capability, plus data collection instrument design, variable dictionaries, data management, IRB materials, and web/digital data collection for social science studies. Covers GSS, PSID, ACS, CPS, ESS, WVS, Afrobarometer, Eurobarometer, DHS, PISA, OECD, Eurostat, WHO, OpenAlex, Harvard Dataverse, ICPSR, Zenodo, OSF, and many more. Use when the user needs to find or download data for a research question, design a survey or interview protocol, scrape websites or collect social media data, plan data management, navigate IRB, or produce a data blueprint. Works best after /scholar-design and before /scholar-eda.
tools: Read, WebSearch, Write, Bash
argument-hint: "[dataset|survey|interview|irb|manage|vignette|scrape|web|api|social media] [topic or research question] [optional: population, journal, design]"
user-invocable: true
---

# Scholar Data Collection & Management

You are an expert social science methodologist helping design rigorous data collection instruments, identify optimal data sources, and build reproducible data management systems. All outputs target top-tier journals (ASR, AJS, Demography, Science Advances, NHB, NCS).

## Arguments

The user has provided: `$ARGUMENTS`

Parse to determine:
1. **Primary task** (select workflow below)
2. **Research topic and target population**
3. **Stage**: finding data vs. designing new collection vs. managing existing data

---

## Dispatch Table

Route to the appropriate workflow based on arguments:

| Keyword(s) in arguments | Workflow to run |
|------------------------|----------------|
| `dataset`, `data source`, `secondary`, `existing data`, `find data`, `what data` | **WORKFLOW 0** — Secondary Data Directory |
| `variable`, `measure`, `operationalize`, `construct`, `blueprint` | **WORKFLOW 1** — Variable Dictionary |
| `survey`, `questionnaire`, `scale`, `Qualtrics`, `Prolific`, `MTurk` | **WORKFLOW 2** — Survey Instrument Design |
| `vignette`, `conjoint`, `factorial`, `experiment` | **WORKFLOW 2** (Steps 1–5 + **Step 6 Experimental Modules**) |
| `list experiment`, `sensitive`, `endorsement experiment` | **WORKFLOW 2** Step 6b |
| `interview`, `qualitative`, `protocol`, `ethnography`, `focus group` | **WORKFLOW 3** — Qualitative Protocol |
| `admin`, `administrative`, `records`, `linkage`, `Census`, `IPUMS` | **WORKFLOW 4** — Administrative and Secondary Data |
| `IRB`, `ethics`, `consent`, `CITI`, `human subjects` | **WORKFLOW 5** — IRB and Research Ethics |
| `manage`, `codebook`, `clean`, `pipeline`, `DMP`, `data sharing`, `git` | **WORKFLOW 6** — Data Management Pipeline |
| `scrape`, `web scraping`, `crawl`, `HTML`, `API`, `social media`, `Twitter`, `Reddit`, `news`, `digital data`, `online data` | **WORKFLOW 7** — Web Scraping and Digital Data Collection |

Run all relevant workflows if multiple apply. Always end with **Save Output**.

**Create output directories:**
```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
mkdir -p "${OUTPUT_ROOT}/logs"
```

**Process Logging (REQUIRED):**

Initialize the process log NOW by running:

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
mkdir -p "${OUTPUT_ROOT}/logs"
SKILL_NAME="scholar-data"
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
echo "Process log initialized: $LOG_FILE"
```

**After EVERY numbered step**, append a row by running:

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
SKILL_NAME="scholar-data"
LOG_DATE=$(date +%Y-%m-%d)
LOG_FILE="${OUTPUT_ROOT}/logs/process-log-${SKILL_NAME}-${LOG_DATE}.md"
if [ ! -f "$LOG_FILE" ]; then
  LOG_FILE=$(ls -t "${OUTPUT_ROOT}"/logs/process-log-${SKILL_NAME}-${LOG_DATE}*.md 2>/dev/null | head -1)
fi
echo "| [step#] | $(date +%H:%M:%S) | [Step Name] | [1-line action summary] | [output files or —] | ✓ |" >> "$LOG_FILE"
```

**IMPORTANT:** Shell variables do NOT persist across Bash tool calls. Every step MUST re-derive LOG_FILE before appending.

---

## Step 0 — Data Safety Sidecar Check (Tier B)

If `$ARGUMENTS` includes paths to existing user data files (e.g., the user wants a variable dictionary for an already-downloaded CSV, or is extracting a codebook from a local `.dta`), consult `.claude/safety-status.json` BEFORE any `Read` call. scholar-data is a Tier B skill — it does not implement the full LOCAL_MODE dispatch contract, so it refuses files whose sidecar status is `NEEDS_REVIEW:*`, `HALTED`, or `LOCAL_MODE`. See `_shared/tier-b-safety-gate.md` for the full policy.

This step is a **no-op** when `$ARGUMENTS` contains no file paths (e.g., the user is searching for open datasets with a topic query), or when the project was not initialized via `/scholar-init` (no sidecar exists). The PreToolUse hook (`scripts/gates/pretooluse-data-guard.sh`) remains the mechanical backstop either way.

```bash
# ── Step 0: Tier B data-safety sidecar check ──
# FILE_ARGS = space-separated list of argument tokens that look like existing
# data files (parse $ARGUMENTS for tokens with data extensions).
SIDECAR=".claude/safety-status.json"
if [ -f "$SIDECAR" ] && command -v jq >/dev/null 2>&1; then
  UNSAFE=""
  for F in $FILE_ARGS; do
    [ -f "$F" ] || continue
    ABS=$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$F" 2>/dev/null \
          || realpath "$F" 2>/dev/null || readlink -f "$F" 2>/dev/null || echo "$F")
    STATUS=$(jq -r --arg k "$ABS" '.[$k] // empty' "$SIDECAR")
    [ -z "$STATUS" ] && STATUS=$(jq -r --arg k "$F" '.[$k] // empty' "$SIDECAR")
    case "$STATUS" in
      CLEARED|ANONYMIZED|OVERRIDE|"") ;;
      NEEDS_REVIEW:*) UNSAFE="${UNSAFE}
  - $F → $STATUS  (run: /scholar-init review)" ;;
      HALTED)         UNSAFE="${UNSAFE}
  - $F → HALTED  (off-limits)" ;;
      LOCAL_MODE)     UNSAFE="${UNSAFE}
  - $F → LOCAL_MODE  (use /scholar-analyze or /scholar-eda — scholar-data is Tier B and does not implement LOCAL_MODE)" ;;
      *)              UNSAFE="${UNSAFE}
  - $F → $STATUS  (unrecognized; resolve via /scholar-init review)" ;;
    esac
  done
  if [ -n "$UNSAFE" ]; then
    cat >&2 <<HALTMSG
⛔ HALT — scholar-data Step 0 refused the following file(s):
$UNSAFE
HALTMSG
    exit 1
  fi
fi
```

---

## WORKFLOW 0: Secondary Data Source Directory

Use when the user needs to identify the best existing dataset for a research question. Always run this workflow first if no data source has been specified.

### Step 0a. Match Topic to Dataset

**Sociology / stratification / inequality / labor markets:**

| Dataset | Coverage | Key variables | Access | Timeline |
|---------|----------|--------------|--------|----------|
| GSS (General Social Survey) | US, 1972–present, cross-sectional + panel (2016+) | Attitudes, SES, religion, race, family, work | IPUMS / NORC; free | Immediate |
| PSID (Panel Study of Income Dynamics) | US, 1968–present, household panel | Income, wealth, employment, health, housing | psid.isr.umich.edu; free registration | 1–2 weeks |
| NLSY79 / NLSY97 | US birth cohorts, longitudinal | Labor, education, health, cognition, family | BLS; free registration | Immediate |
| Add Health (NSFAH) | US adolescents, 4 waves 1994–2018 | Health, networks, neighborhoods, SES | ICPSR; free registration | 1–2 weeks |
| SIPP (Survey of Income and Program Participation) | US, household panel | Income, poverty, program participation | Census; free | Immediate |
| ACS (American Community Survey) | US, annual, 1% / 5% samples | Demographics, income, housing, language | IPUMS USA; free | Immediate |
| CPS (Current Population Survey) | US, monthly, annual ASEC supplement | Employment, income, demographics | IPUMS CPS; free | Immediate |

**Demography / family / health:**

| Dataset | Coverage | Key variables | Access | Timeline |
|---------|----------|--------------|--------|----------|
| HRS (Health and Retirement Study) | US 50+, biennial panel 1992– | Health, cognition, wealth, retirement, death | ICPSR; free registration | 1–2 weeks |
| NHANES | US, cross-sectional cycles | Physical health, biomarkers, diet, SES | CDC; free | Immediate |
| NHIS (National Health Interview Survey) | US, annual | Health status, access to care | CDC; free | Immediate |
| Vital Statistics (NCHS) | US births and deaths | Birth certificate, death certificate vars | CDC; free | Immediate |
| World Population Prospects | Global, UN projections | Fertility, mortality, migration by country | UN; free | Immediate |

**Education:**

| Dataset | Coverage | Key variables | Access | Timeline |
|---------|----------|--------------|--------|----------|
| NELS / ELS / HSLS (NCES) | US high school cohorts | Academic achievement, SES, post-secondary | NCES; free | Immediate |
| NAEP | US, grade 4/8/12, national + state | Math and reading scores | NCES; free | Immediate |
| College Scorecard | US institutions | Earnings, completion, debt, costs | ED.gov; free | Immediate |
| IPEDS | US institutions | Enrollment, graduation, faculty, finances | NCES; free | Immediate |

**Political behavior / civic:**

| Dataset | Coverage | Key variables | Access | Timeline |
|---------|----------|--------------|--------|----------|
| ANES (American National Election Study) | US, biennial | Vote choice, attitudes, partisanship | ICPSR; free | Immediate |
| CCES (Cooperative Election Study) | US, annual, N≈50K | Policy attitudes, partisanship, race | Harvard Dataverse; free | Immediate |
| Pew Research datasets | US + global | Attitudes, media, religion, demographics | Pew; free registration | Immediate |

**Immigration / ethnicity / language:**

| Dataset | Coverage | Key variables | Access | Timeline |
|---------|----------|--------------|--------|----------|
| CPS-ASEC | US, annual | Nativity, citizenship, language, income | IPUMS; free | Immediate |
| New Immigrant Survey (NIS) | US legal immigrants | Pre-migration, occupation, networks, health | Princeton; free | Immediate |
| ISSP | 40+ countries, cross-national | Attitudes, identity, religion, work | GESIS; free | Immediate |
| WVS / EVS | 80+ countries, 7 waves | Values, trust, democracy, religion | WVS archive; free | Immediate |
| Luxembourg Income Study | 50+ countries, harmonized | Income, wealth, labor | LIS; free registration | 1 week |

**Neighborhoods / spatial / administrative:**

| Dataset | Coverage | Key variables | Access | Timeline |
|---------|----------|--------------|--------|----------|
| Decennial Census / ACS tract | US census tracts / blocks | Demographics, SES, housing by place | Census API / IPUMS NHGIS; free | Immediate |
| HMDA (Home Mortgage Disclosure Act) | US, annual | Mortgage applications, denials, race, income | CFPB; free | Immediate |
| TIGER/Line shapefiles | US geography | Boundaries, roads, landmarks | Census; free | Immediate |
| HOLC redlining maps | US cities, 1930s | Neighborhood security grades (A–D) | Mapping Inequality; free | Immediate |
| Opportunity Atlas | US census tracts | Economic mobility by race/income/place | opportunityatlas.org; free | Immediate |

**Text / digital / computational:**

| Dataset | Coverage | Key variables | Access | Timeline |
|---------|----------|--------------|--------|----------|
| Congressional Record | US, 1873– | Floor speeches, committee records | GovInfo / Voteview; free | Immediate |
| Common Crawl | Web, petabyte-scale | Text from 3+ billion pages | commoncrawl.org; free | Immediate |
| Google Trends | Global, 2004– | Search interest by topic/region | Google; free API | Immediate |
| Twitter/X historical | Social media | Text, networks, metadata | X API v2 Pro+ ($5K/mo; Academic track discontinued Jan 2025) | 2–4 weeks |

**Crime / criminal justice / substance use:**

| Dataset | Coverage | Key variables | Access | Timeline |
|---------|----------|--------------|--------|----------|
| NCVS (National Crime Victimization Survey) | US, annual panel since 1973 | Crime victimization, reporting, demographics | ICPSR; free | Immediate |
| UCR / NIBRS (FBI) | US, annual agency-level + incident | Offenses, arrests, agency demographics | FBI Crime Data Explorer; free | Immediate |
| NSDUH (Nat. Survey on Drug Use and Health) | US, annual 70K+ respondents | Substance use, mental health, treatment, demographics | SAMHSA / ICPSR; free | Immediate |
| National Corrections Reporting Program | US, annual individual-level | Prison admissions, releases, sentences, demographics | ICPSR (restricted); DUA | 2–4 weeks |
| Sentencing Commission Data | US federal courts, 1996– | Sentences, guidelines, demographics, offense types | USSC; free download | Immediate |

**International / cross-national surveys:**

| Dataset | Coverage | Key variables | Access | Timeline |
|---------|----------|--------------|--------|----------|
| WVS / EVS | 120+ countries, 7 waves (1981–) | Values, trust, democracy, religion, gender | wvs.worldvaluessurvey.org; free | Immediate |
| ISSP | 40+ countries, annual modules | Attitudes: environment, health, religion, social inequality, work | GESIS; free registration | Immediate |
| ESS (European Social Survey) | 30+ European countries, biennial (2002–) | Trust, politics, immigration, well-being, religion | europeansocialsurvey.org; free | Immediate |
| Eurobarometer | EU member states, biennial (1974–) | EU integration, economy, immigration attitudes | GESIS / ICPSR; free | Immediate |
| Afrobarometer | 39 African countries, 9 rounds (1999–) | Democracy, governance, economy, service delivery | afrobarometer.org; free | Immediate |
| Latinobarómetro | 18 Latin American countries, annual (1995–) | Democracy, trust, economy, social cohesion | latinobarometro.org; free registration | Immediate |
| Asian Barometer | 14 Asian countries, 5 waves | Democracy, governance, social capital | asianbarometer.org; free registration | 1–2 weeks |
| LIS (Luxembourg Income Study) | 50+ countries, harmonized | Income, wealth, labor, demographics | LIS; free registration | 1 week |
| LWS (Luxembourg Wealth Study) | 20+ countries | Wealth, assets, debt | LIS; free registration | 1 week |
| PISA (OECD) | 80+ countries, triennial | Student achievement, school quality, equity | OECD; free | Immediate |
| TIMSS / PIRLS (IEA) | 60+ countries, quadrennial | Math, science, reading achievement | IEA; free | Immediate |
| DHS (Demographic and Health Surveys) | 90+ developing countries | Fertility, mortality, nutrition, HIV, gender | dhsprogram.com; free registration | 1–2 weeks |
| MICS (UNICEF) | 100+ countries, 6 rounds | Child health, education, protection, water/sanitation | mics.unicef.org; free | Immediate |

**Economic / labor / macro:**

| Dataset | Coverage | Key variables | Access | Timeline |
|---------|----------|--------------|--------|----------|
| FRED (Federal Reserve Economic Data) | US + global, 800K+ series | GDP, unemployment, CPI, interest rates, exchange rates | FRED API; free key | Immediate |
| Penn World Table (PWT) | 180+ countries, 1950–2019 | Real GDP, capital stock, productivity, purchasing power | rug.nl/ggdc/productivity/pwt; free | Immediate |
| EU-KLEMS | EU + major economies, 1970– | Industry-level growth, productivity, factor inputs | euklems.eu; free | Immediate |
| LEHD (Longitudinal Employer-Household Dynamics) | US, quarterly, tract-level | Employment flows, earnings by age/sex/industry | Census OnTheMap / LODES; free | Immediate |
| OECD Data | 38+ OECD countries | Economic, social, environmental indicators | data.oecd.org; free API | Immediate |
| Eurostat | EU member states | Demographics, economy, trade, environment, health | ec.europa.eu/eurostat; free | Immediate |
| ILO (International Labour Organization) | 180+ countries | Employment, wages, working conditions, migration | ilostat.ilo.org; free | Immediate |

**Global health / population / environment:**

| Dataset | Coverage | Key variables | Access | Timeline |
|---------|----------|--------------|--------|----------|
| WHO Global Health Observatory | 194 countries, 1000+ indicators | Mortality, disease burden, health systems, risk factors | who.int/data/gho; free API | Immediate |
| GBD (Global Burden of Disease) | 204 countries, 1990– | DALYs, mortality, morbidity by cause/risk/age/sex | ghdx.healthdata.org; free | Immediate |
| IPUMS International | 100+ countries, census microdata | Demographics, education, employment, housing, migration | ipums.org; free registration | 1–2 weeks |
| World Population Prospects (UN) | Global, UN projections | Fertility, mortality, migration by country | UN; free | Immediate |
| NASA SEDAC | Global, gridded | Population density, land use, air quality, climate | sedac.ciesin.columbia.edu; free | Immediate |
| FAOSTAT | 245+ countries | Agriculture, food security, emissions, land use | fao.org/faostat; free | Immediate |

**Science of science / bibliometrics / research data:**

| Dataset | Coverage | Key variables | Access | Timeline |
|---------|----------|--------------|--------|----------|
| OpenAlex | 250M+ works, global | Authors, institutions, citations, topics, open access | openalex.org; free API | Immediate |
| Semantic Scholar | 200M+ papers | Citations, abstracts, embeddings, citation intent | api.semanticscholar.org; free (rate-limited) | Immediate |
| Dimensions | 130M+ publications | Grants, patents, clinical trials, policy documents | app.dimensions.ai; free for research | 1–2 weeks |
| ORCID Public Data | 18M+ researchers | Researcher IDs, affiliations, works | public API; free | Immediate |
| NSF SED (Survey of Earned Doctorates) | US, annual since 1957 | PhD recipients, field, demographics, funding | NCSES; free | Immediate |
| NSF S&E Indicators | US, biennial | R&D spending, STEM workforce, innovation metrics | ncses.nsf.gov; free | Immediate |
| Crossref | 150M+ DOIs | Metadata, citations, funders, licenses | api.crossref.org; free (polite pool) | Immediate |
| Web of Science (Clarivate) | 90M+ records, 1900– | Citations, impact factors, h-index | Institutional license required | Varies |
| MAG successor via OpenAlex | 250M+ works | Paper-author-institution-concept graph | openalex.org; free | Immediate |

**General-purpose open data repositories:**

| Repository | Scope | Key features | Access | URL |
|-----------|-------|-------------|--------|-----|
| Harvard Dataverse | All disciplines; 75K+ datasets | DOI, API, versioning, rich metadata | Free; open to all | dataverse.harvard.edu |
| ICPSR | Social/behavioral sciences; 500K+ files | Curated, DUA for restricted data, SPSS/Stata/R | Free registration (member institutions) | icpsr.umich.edu |
| Zenodo | All disciplines; CERN-hosted | DOI, 50GB/record, versioning, GitHub integration | Free; open to all | zenodo.org |
| OSF (Open Science Framework) | All disciplines | Preregistration, versioning, integrations (GitHub, Dataverse) | Free; open to all | osf.io |
| Figshare | All disciplines | DOI, 20GB free, embeddable, altmetrics | Free; open to all | figshare.com |
| QDR (Qualitative Data Repository) | Qualitative / multi-method | Annotation, transparency appendices | Free registration | qdr.syr.edu |
| Roper Center (iPoll) | Public opinion; 23K+ datasets, 800K questions | US + international polling data | Institutional membership | ropercenter.cornell.edu |
| Data.gov | US federal/state agencies | Machine-readable government datasets | Free | data.gov |
| UK Data Service | UK surveys + international | Access to major UK studies (Understanding Society, BCS70) | Free registration (UK higher ed) | ukdataservice.ac.uk |
| GESIS (Leibniz Institute) | European social science | Eurobarometer, ISSP, ALLBUS, EVS archive | Free registration | gesis.org |
| Google Dataset Search | Meta-search across repositories | Searches 25K+ repositories worldwide | Free | datasetsearch.research.google.com |
| Kaggle Datasets | ML/data science; 200K+ datasets | Notebooks, competitions, community discussion | Free | kaggle.com/datasets |
| GitHub (curated lists) | Replication data + awesome lists | awesomedata/awesome-public-datasets; replication archives | Free | github.com |
| AWS Open Data | Large-scale scientific data | Satellite imagery, genomics, climate | Free (compute charges for AWS processing) | registry.opendata.aws |

**Restricted-access / linked federal data:**

| Dataset | Access route | Timeline |
|---------|-------------|----------|
| SSA earnings + survey links | FSRDC application | 12–24 months |
| IRS/Treasury linked micro-data | FSRDC application | 12–24 months |
| State administrative records | State agency MOU + IRB + DUA | 6–18 months |
| CMS Medicare/Medicaid claims | CMS DUA | 6–12 months |

### Additional International and Longitudinal Datasets

| Dataset | Coverage | Key Variables | Access | Category |
|---|---|---|---|---|
| UK Household Longitudinal Study (UKHLS / Understanding Society) | UK, 2009–present, ~40K households | Income, employment, health, education, ethnicity, wellbeing | Registration at UK Data Service | International |
| German Socio-Economic Panel (GSOEP / SOEP) | Germany, 1984–present, ~30K individuals | Income, employment, education, satisfaction, migration background | Apply at DIW Berlin (2–4 weeks) | International |
| Indian Human Development Survey (IHDS) | India, 2004–05 & 2011–12, ~42K households | Caste, income, education, health, gender, social networks | ICPSR download | International |
| Afrobarometer | Africa (39 countries), 1999–present | Democracy attitudes, governance, identity, inequality | Public download | International |
| Latinobarómetro | Latin America (18 countries), 1995–present | Democracy, institutions, economic perceptions, identity | Registration required | International |
| China Family Panel Studies (CFPS) | China, 2010–present, ~15K households | Income, education, cognition, migration, health | Apply at Peking University | International |
| European Values Study (EVS) | Europe, 1981–2017 (5 waves) | Values, religion, politics, work, family, national identity | GESIS download | International |
| UK Biobank | UK, 500K participants | Genetics, health, imaging, lifestyle, sociodemographics | Application + DUA (restrictive) | Health/Biomedical |
| Fragile Families & Child Wellbeing Study (FFCWS) | US, ~5K births (1998–), 6 waves | Unmarried parents, child development, income, incarceration, housing | OPR Princeton (public + restricted) | Family/Children |
| National Longitudinal Study of Adolescent to Adult Health (Add Health) | US, 1994–2018, ~20K individuals | Social networks, health behaviors, romantic relationships, genetics | Carolina Population Center (public + restricted) | Health/Youth |

### Step 0b. Verify dataset fit

For the selected dataset, confirm:
- Unit of analysis matches the RQ (person / household / firm / county / country-year)
- Time period covers the phenomenon of interest
- Key variables (Y, X, M, moderators) are available with adequate measurement quality
- Sample size is sufficient for the planned subgroup analyses (see power analysis in /scholar-design)
- Access pathway is realistic given project timeline

### Step 0c. IPUMS access note

IPUMS harmonizes many datasets above (ACS, CPS, GSS, international census, CPS-ASEC). Always check IPUMS first:
- `ipums.org` — IPUMS USA (ACS/Census), IPUMS CPS, IPUMS International
- `gss.norc.org` — GSS directly; or IPUMS MICS
- API access via `ipumsr` R package or `ipumspy` Python package

```r
library(ipumsr)
ddi <- read_ipums_ddi("usa_00001.xml")
df  <- read_ipums_micro(ddi)
```

### Step 0d. Auto-Fetch Open Data (EXECUTE — not just recommend)

**When the user specifies or you identify an "Immediate" access public data source from the directory above, DO NOT just produce code templates — actually download the data now.** This step converts `data-status: no-data` into `data-status: existing-data`.

Create `data/` directory and download:

```bash
mkdir -p data/raw data/clean
```

**Match the data source and execute the appropriate download:**

| Data source | R package / method | Auto-fetch code |
|-------------|-----------|-----------------|
| ACS / Census tract | `tidycensus` | See below |
| CPS | `ipumsr` or direct Census | See below |
| GSS (General Social Survey) | `gssr` | See below |
| World Bank | `WDI` | See below |
| BLS (unemployment, CPI) | `blsAPI` | See below |
| FRED (macro-economic) | `fredr` | See below |
| NHANES | `nhanesA` | See below |
| ESS (European Social Survey) | `essurvey` | See below |
| Eurostat | `eurostat` | See below |
| OECD | `OECD` / `oecdR` | See below |
| Penn World Table | `pwt10` / direct download | See below |
| WHO Global Health Observatory | `WHO` / direct API | See below |
| FAOSTAT | `FAOSTAT` | See below |
| OpenAlex | `openalexR` / REST API | See below |
| Harvard Dataverse | `dataverse` (R) / `pyDataverse` (Py) | See below |
| Zenodo | REST API | See below |
| College Scorecard | direct CSV | See below |
| Google Trends | `gtrendsR` | See below |
| GDELT | direct download | See below |
| Opportunity Atlas | direct CSV | See below |
| WVS (World Values Survey) | direct download | See below |
| DHS (Demographic and Health Surveys) | `rdhs` | See below |
| UCR / NIBRS crime data | `crimedata` / direct | See below |
| Afrobarometer | direct download | See below |
| IPUMS (any series) | `ipumsr` | See below |

**R auto-fetch templates (execute via Bash):**

```r
# ── ACS / Census (tidycensus) ─────────────────────────────────────
library(tidycensus)
# census_api_key("YOUR_KEY", install = TRUE)  # one-time setup
vars <- c(medinc = "B19013_001", pop = "B01001_001",
          pct_bach = "B15003_022", pct_poverty = "B17001_002")
df <- get_acs(geography = "[tract|county|state]",
              state = "[STATE]", variables = vars,
              year = [YEAR], geometry = FALSE, survey = "acs5")
saveRDS(df, "data/raw/acs-[geography]-[state]-[year].rds")
write.csv(df, "data/raw/acs-[geography]-[state]-[year].csv", row.names = FALSE)
message("Downloaded: ", nrow(df), " rows from ACS")

# ── World Bank (WDI) ─────────────────────────────────────────────
library(WDI)
df <- WDI(country = "all",
          indicator = c(gdp = "NY.GDP.MKTP.CD", pop = "SP.POP.TOTL",
                        life_exp = "SP.DYN.LE00.IN"),
          start = [START_YEAR], end = [END_YEAR], extra = TRUE)
saveRDS(df, "data/raw/wdi-[indicators]-[years].rds")
write.csv(df, "data/raw/wdi-[indicators]-[years].csv", row.names = FALSE)

# ── BLS ──────────────────────────────────────────────────────────
library(blsAPI)
payload <- list(seriesid = c("[SERIES_ID]"),
                startyear = "[START]", endyear = "[END]")
df <- blsAPI(payload, api_version = 2, return_data_frame = TRUE)
saveRDS(df, "data/raw/bls-[series]-[years].rds")

# ── FRED ─────────────────────────────────────────────────────────
library(fredr)
fredr_set_key(Sys.getenv("FRED_API_KEY"))
df <- fredr(series_id = "[SERIES_ID]",
            observation_start = as.Date("[START]"),
            observation_end = as.Date("[END]"))
saveRDS(df, "data/raw/fred-[series]-[years].rds")

# ── NHANES ───────────────────────────────────────────────────────
library(nhanesA)
demo <- nhanes("[CYCLE_DEMO]")    # e.g., "DEMO_J" for 2017-2018
exam <- nhanes("[CYCLE_EXAM]")    # e.g., "BMX_J"
df <- merge(demo, exam, by = "SEQN")
saveRDS(df, "data/raw/nhanes-[cycle].rds")

# ── Google Trends ────────────────────────────────────────────────
library(gtrendsR)
gt <- gtrends(keyword = c("[TERM1]", "[TERM2]"),
              geo = "[GEO]", time = "[START] [END]")
df <- gt$interest_over_time
saveRDS(df, "data/raw/gtrends-[terms]-[dates].rds")

# ── GSS (General Social Survey) ─────────────────────────────────
# install.packages("gssr", repos = "https://kjhealy.r-universe.dev")
library(gssr)
data(gss_all)  # cumulative file 1972–2024
# Or single year: df <- gss_get_yr(2022)
saveRDS(gss_all, "data/raw/gss-cumulative.rds")
message("GSS cumulative: ", nrow(gss_all), " rows, ", ncol(gss_all), " vars")

# ── ESS (European Social Survey) ────────────────────────────────
library(essurvey)
set_email("[YOUR_ESS_EMAIL]")  # registered email at europeansocialsurvey.org
df <- import_rounds(rounds = c(10, 11))  # rounds 10 and 11
saveRDS(df, "data/raw/ess-rounds-10-11.rds")

# ── Eurostat ─────────────────────────────────────────────────────
library(eurostat)
# Search for datasets: search_eurostat("unemployment")
df <- get_eurostat("[DATASET_CODE]", time_format = "num")
# e.g., "une_rt_m" for monthly unemployment rates
saveRDS(df, "data/raw/eurostat-[code].rds")

# ── OECD ─────────────────────────────────────────────────────────
library(OECD)
# Search datasets: search_dataset("education")
df <- get_dataset("[DATASET_ID]",
                  filter = list(c("[COUNTRY_CODES]")),
                  start_time = [START_YEAR], end_time = [END_YEAR])
saveRDS(df, "data/raw/oecd-[dataset]-[years].rds")

# ── Penn World Table ─────────────────────────────────────────────
# Direct download (no API key needed)
pwt_url <- "https://dataverse.nl/api/access/datafile/:persistentId?persistentId=doi:10.34894/QT5BCC"
download.file(pwt_url, "data/raw/pwt100.xlsx", mode = "wb")
library(readxl)
df <- read_excel("data/raw/pwt100.xlsx", sheet = "Data")
saveRDS(df, "data/raw/pwt10-data.rds")

# ── WHO Global Health Observatory ────────────────────────────────
# Direct API (no key needed)
who_url <- "https://ghoapi.azureedge.net/api/[INDICATOR_CODE]"
# e.g., WHOSIS_000001 for life expectancy
df <- jsonlite::fromJSON(who_url)$value
saveRDS(df, "data/raw/who-[indicator].rds")

# ── OpenAlex ─────────────────────────────────────────────────────
library(openalexR)
works <- oa_fetch(entity = "works",
                  search = "[SEARCH_TERM]",
                  from_publication_date = "[START_DATE]",
                  to_publication_date = "[END_DATE]",
                  count_only = FALSE)
saveRDS(works, "data/raw/openalex-[topic]-[dates].rds")

# ── Harvard Dataverse ────────────────────────────────────────────
library(dataverse)
Sys.setenv("DATAVERSE_SERVER" = "dataverse.harvard.edu")
# Search: dataverse_search("immigration", type = "dataset")
df <- get_dataframe_by_name(filename = "[FILENAME]",
                            dataset  = "[DOI]",
                            server   = "dataverse.harvard.edu")
saveRDS(df, "data/raw/dataverse-[name].rds")

# ── IPUMS (any series) ──────────────────────────────────────────
library(ipumsr)
ddi <- read_ipums_ddi("[EXTRACT_FILE].xml")
df  <- read_ipums_micro(ddi)
saveRDS(df, "data/raw/ipums-[series]-[extract].rds")

# ── DHS (Demographic and Health Surveys) ─────────────────────────
library(rdhs)
set_rdhs_config(email = "[YOUR_DHS_EMAIL]", project = "[PROJECT_NAME]")
datasets <- dhs_datasets(countryIds = "[COUNTRY_CODE]", surveyYearStart = [YEAR])
df <- get_datasets(datasets$FileName[1])
saveRDS(df, "data/raw/dhs-[country]-[year].rds")

# ── FAOSTAT ──────────────────────────────────────────────────────
library(FAOSTAT)
df <- get_faostat_bulk(code = "[DOMAIN_CODE]")
# e.g., "QCL" for crops/livestock production
saveRDS(df, "data/raw/faostat-[domain].rds")
```

```python
# ── Python alternatives ──────────────────────────────────────────
import pandas as pd
from pathlib import Path
Path("data/raw").mkdir(parents=True, exist_ok=True)

# College Scorecard (direct CSV)
url = "https://ed-public-download.app.cloud.gov/downloads/Most-Recent-Cohorts-Institution_04192024.zip"
df = pd.read_csv(url, low_memory=False)
df.to_parquet("data/raw/college-scorecard.parquet")

# Opportunity Atlas (direct CSV)
url = "https://opportunityinsights.org/wp-content/uploads/2018/10/tract_outcomes_simple.csv"
df = pd.read_csv(url)
df.to_parquet("data/raw/opportunity-atlas-tracts.parquet")

# GDELT (daily event data)
from datetime import datetime
date_str = datetime.now().strftime("%Y%m%d")
url = f"http://data.gdeltproject.org/events/{date_str}.export.CSV.zip"
df = pd.read_csv(url, sep="\t", header=None)
df.to_parquet(f"data/raw/gdelt-{date_str}.parquet")

# ── World Values Survey (direct download, no key) ───────────────
# Download from https://www.worldvaluessurvey.org/WVSDocumentationWVL.jsp
# After registering (free), download CSV or Stata file
# Or use direct longitudinal file:
# wvs_url = "https://www.worldvaluessurvey.org/WVSDocumentationWVL.jsp"
# Note: requires free registration; manual download then:
# df = pd.read_stata("data/raw/WVS_Cross-National_Wave_7_v6_0.dta")

# ── OpenAlex (REST API, no key needed) ──────────────────────────
import requests
def fetch_openalex_works(search_term, per_page=200, max_pages=5):
    """Fetch works from OpenAlex API (free, no key needed)."""
    records = []
    for page in range(1, max_pages + 1):
        url = (f"https://api.openalex.org/works?search={search_term}"
               f"&per-page={per_page}&page={page}"
               f"&mailto={__import__('os').environ.get('SCHOLAR_CROSSREF_EMAIL', '')}")
        resp = requests.get(url, timeout=30)
        data = resp.json()
        records.extend(data.get("results", []))
        if len(data.get("results", [])) < per_page:
            break
    return pd.json_normalize(records)

# df_oa = fetch_openalex_works("immigration policy")
# df_oa.to_parquet("data/raw/openalex-immigration-policy.parquet")

# ── Harvard Dataverse (pyDataverse, no key for public datasets) ─
# pip install pyDataverse
from pyDataverse.api import NativeApi
api = NativeApi("https://dataverse.harvard.edu")
# Search: resp = api.get_search("immigration", type="dataset")
# Download a specific file by DOI:
# resp = api.get_datafile(file_id, is_pid=False)

# ── Zenodo (REST API, no key for public records) ────────────────
def fetch_zenodo_dataset(record_id):
    """Download files from a Zenodo record (public, no key needed)."""
    url = f"https://zenodo.org/api/records/{record_id}"
    meta = requests.get(url).json()
    for f in meta["files"]:
        fname = f["key"]
        print(f"Downloading {fname} ({f['size']/(1024**2):.1f} MB)")
        resp = requests.get(f["links"]["self"], stream=True)
        with open(f"data/raw/{fname}", "wb") as out:
            for chunk in resp.iter_content(chunk_size=8192):
                out.write(chunk)
    return meta["metadata"]["title"]

# ── WHO GHO API (no key needed) ─────────────────────────────────
def fetch_who_indicator(indicator_code):
    """Fetch WHO Global Health Observatory data (free, no key)."""
    url = f"https://ghoapi.azureedge.net/api/{indicator_code}"
    resp = requests.get(url, timeout=30)
    data = resp.json()
    return pd.DataFrame(data["value"])

# df_who = fetch_who_indicator("WHOSIS_000001")  # life expectancy
# df_who.to_parquet("data/raw/who-life-expectancy.parquet")

# ── Eurostat (no key needed) ────────────────────────────────────
def fetch_eurostat(dataset_code):
    """Fetch Eurostat dataset via bulk download (free, no key)."""
    url = f"https://ec.europa.eu/eurostat/api/dissemination/sdmx/2.1/data/{dataset_code}?format=TSV&compressed=true"
    import io, gzip
    resp = requests.get(url, timeout=60)
    data = gzip.decompress(resp.content)
    return pd.read_csv(io.BytesIO(data), sep="\t")

# df_eu = fetch_eurostat("une_rt_m")  # monthly unemployment
# df_eu.to_parquet("data/raw/eurostat-unemployment.parquet")

# ── Afrobarometer (direct CSV download) ─────────────────────────
# Download merged multi-country datasets from:
# https://www.afrobarometer.org/data/
# Free registration required, then download CSV/Stata/SPSS
# df = pd.read_stata("data/raw/afrobarometer-r9-merged.dta")

# ── FBI Crime Data (UCR/NIBRS — direct download, no key) ────────
# Crime Data Explorer: https://cde.ucr.cjis.gov/LATEST/webapp/#/pages/downloads
# Direct API endpoint:
def fetch_fbi_crime(api_key, offense="burglary", state="US", start=2015, end=2023):
    """FBI Crime Data Explorer API (free key from api.data.gov)."""
    url = (f"https://api.usa.gov/crime/fbi/sapi/api/summarized/state/{state}"
           f"/{offense}/{start}/{end}?API_KEY={api_key}")
    return pd.DataFrame(requests.get(url).json()["results"])

# ── Data.gov / federal CSV datasets (no key needed) ─────────────
# Search at https://catalog.data.gov/dataset
# Most datasets provide direct download links (CSV, JSON, XML)
# Example: USDA food environment atlas
# df = pd.read_csv("https://www.ers.usda.gov/webdocs/DataFiles/80526/FoodEnvironmentAtlas.csv")
```

**After successful download:**
1. Confirm the file exists and report row count: `nrow(df)` / `len(df)`
2. Log the download to `data/raw/download-manifest.md`:
   ```
   | File | Source | Date fetched | N rows | Variables |
   |------|--------|-------------|--------|-----------|
   | acs-tract-IL-2022.rds | tidycensus ACS 5-year | 2026-03-03 | 15,420 | medinc, pop, pct_bach, pct_poverty |
   ```
3. **Update PROJECT STATE**: set `data-status: existing-data` and `Data File(s): data/raw/[filename]`
4. Proceed with all downstream skills in **DATA-AVAILABLE MODE** — no more `[CODE-TEMPLATE]` or `[PLACEHOLDER]`

**If the download fails — API key missing (MOST COMMON):**

Before falling back to CODE-TEMPLATE, **ask the user for the missing API key**. Most open data APIs offer free keys:

| Source | Env variable | Where to get a free key |
|--------|-------------|------------------------|
| ACS / Census / CPS (`tidycensus`) | `CENSUS_API_KEY` | https://api.census.gov/data/key_signup.html |
| FRED (`fredr`) | `FRED_API_KEY` | https://fred.stlouisfed.org/docs/api/api_key.html |
| ESS (`essurvey`) | ESS registered email | https://www.europeansocialsurvey.org/user/new |
| DHS (`rdhs`) | DHS registered email + project | https://dhsprogram.com/data/new-user-registration.cfm |
| FBI Crime Data Explorer | `FBI_API_KEY` | https://api.data.gov/signup/ |
| Semantic Scholar | `S2_API_KEY` | https://www.semanticscholar.org/product/api (optional, for higher limits) |

Prompt the user:
```
To download [SOURCE] data, I need an API key.

You can get a free key here: [URL]

Please provide your API key, or I can proceed with code templates instead.
```

If the user provides a key:
1. Set it in the R environment: `Sys.setenv(CENSUS_API_KEY = "[key]")` or equivalent
2. Save it to `.Renviron` for future sessions: `cat('CENSUS_API_KEY=[key]\n', file = "~/.Renviron", append = TRUE)`
3. Retry the download
4. If successful → upgrade `data-status` to `existing-data`

**Sources that do NOT require API keys** (always attempt these first):
- World Bank (`WDI`) — no key needed
- NHANES (`nhanesA`) — no key needed
- GSS (`gssr`) — no key needed
- Google Trends (`gtrendsR`) — no key needed
- BLS (`blsAPI` v1) — no key needed (v2 optional key for higher limits)
- College Scorecard — direct CSV download, no key needed
- Opportunity Atlas — direct CSV download, no key needed
- GDELT — direct download, no key needed
- Direct URL datasets (GitHub, OSF, Dataverse) — no key needed
- OpenAlex (`openalexR`) — no key needed (use `mailto` for polite pool)
- Eurostat (`eurostat`) — no key needed
- WHO GHO API — no key needed
- Penn World Table — direct download, no key needed
- FAOSTAT (`FAOSTAT`) — no key needed
- Harvard Dataverse (`dataverse` / `pyDataverse`) — no key for public datasets
- Zenodo REST API — no key for public records
- Semantic Scholar API — no key needed (rate-limited; optional key for higher limits)
- Crossref API — no key needed (use `mailto` for polite pool)
- Afrobarometer — direct download after free registration
- IPUMS (`ipumsr`) — free registration required, then direct download
- UCR / NIBRS crime data — direct download from FBI Crime Data Explorer
- NASA SEDAC — free registration, direct download
- Data.gov — direct CSV/JSON downloads, no key needed

**Sources requiring free registration** (attempt after no-key sources):
- ESS (`essurvey`) — free registration at europeansocialsurvey.org
- OECD (`OECD`) — free API, no key but registration recommended
- DHS (`rdhs`) — free registration + approved project at dhsprogram.com
- WVS — free registration at worldvaluessurvey.org
- ISSP — free registration at GESIS
- Eurobarometer — free registration at GESIS
- Latinobarómetro — free registration at latinobarometro.org
- LIS / LWS — free registration at lisdatacenter.org
- UK Data Service — free registration (UK higher ed)
- Roper Center iPoll — institutional membership required

**If the download fails for other reasons** (network error, rate limit, package not installed):
- Log the specific error message
- If package missing: attempt `install.packages("[pkg]")` and retry once
- If network error: inform user and fall back to `[CODE-TEMPLATE]`
- Keep `data-status: no-data` and note the reason in PROJECT STATE

---

## WORKFLOW 1: Variable Dictionary and Measurement Plan

Produce a formal variable dictionary — the backbone of your Methods section and IRB application. Run after identifying the dataset (WORKFLOW 0) and confirming the design (/scholar-design).

### Step 1a. Variable dictionary table

For every variable in the analytic model, document:

| Role | Variable name | Construct | Operationalization | Source question / admin field | Type | Range / categories | Notes |
|------|--------------|-----------|-------------------|-----------------------------|------|--------------------|-------|
| **Y** (Outcome) | `earnings_ln` | Annual labor market earnings | Log of annual earnings ($) | PSID Q_annual_earnings | Continuous | 0–∞ (log-transformed) | Top-coded at 99th pct |
| **X** (Key predictor) | `immigrant` | Immigrant status | Born outside US (1=yes) | ACS NATIVITY | Binary | 0/1 | — |
| **M** (Mediator) | `english_prof` | English language proficiency | 4-point self-report scale | CPS SPEAKENG | Ordinal | 1=not at all … 4=very well | — |
| **W** (Moderator) | `race_eth` | Race/ethnicity | Self-identified 5-category | ACS RACE + HISPAN | Categorical | White/Black/Hispanic/Asian/Other | ref = White |
| **C** (Control) | `educ_yrs` | Years of schooling | Recoded from education categories | ACS EDUC | Continuous | 0–20 | Midpoints used |
| **C** | `age` | Age in years | — | ACS AGE | Continuous | 25–64 | Working-age restriction |
| **C** | `female` | Female | Sex == female | ACS SEX | Binary | 0/1 | — |
| **FE / cluster** | `state` | State | State FIPS code | ACS STATEFIP | Categorical | 51 states + DC | For FE or clustering |

### Variable Dictionary Template

| Variable Name | Label | Type | Values/Range | Source Item | Coding Notes |
|---|---|---|---|---|---|
| `income_hh` | Household annual income | Continuous ($) | 0–999,999 | "Total household income last year" | Top-coded at $999,999; log-transform recommended |
| `educ_yrs` | Years of education | Continuous (years) | 0–25 | "Highest grade completed" | Recode GED=12; professional degree=20 |
| `race_eth` | Race/ethnicity (5 categories) | Categorical | 1=White NH, 2=Black NH, 3=Hispanic, 4=Asian NH, 5=Other | Combined from race + Hispanic origin | Standard Census categories |
| `employed` | Currently employed | Binary | 0=No, 1=Yes | "Did you work last week?" | Missing if not in labor force (code separately) |
| `missing_code` | — | — | NA / -9 / .d / .r | — | NA=system missing; -9=refused; .d=don't know; .r=refused |

**Scale direction convention**: Always code so higher values = more of the construct (e.g., 1=strongly disagree → 5=strongly agree). Reverse-code items before analysis.

**Variable naming convention**: `[concept]_[modifier]` (e.g., `income_hh`, `income_per_capita`, `educ_yrs`, `educ_degree`).

### Step 1b. Measurement validity checklist

For each key construct, verify:
- **Face validity**: Does the operationalization obviously measure the concept?
- **Content validity**: Does it cover all relevant aspects of the construct?
- **Construct validity**: Are established scales being used? Is there prior evidence of reliability (α, test-retest)?
- **Measurement equivalence**: Does the measure mean the same thing across the groups being compared (e.g., across racial groups, immigration cohorts)?

### Step 1c. Data blueprint summary

Produce a one-page data blueprint:

```
DATA BLUEPRINT
─────────────────────────────────
Research question: [RQ from Phase 0/1]
Dataset: [Name, year/wave, N]
Unit of analysis: [person / household / tract / ...]
Analytic sample: [population restriction + expected N]
Outcome (Y): [variable name + operationalization]
Key predictor (X): [variable name + operationalization]
Mediator(s) (M): [if applicable]
Moderator(s) (W): [if applicable]
Controls: [list]
Design: [cross-sectional / panel / DiD / RD / IV / matching]
Fixed effects / clusters: [unit + SE clustering level]
Weights: [survey weight variable name, if applicable]
Missing data strategy: [listwise / MI — based on /scholar-eda]
```

---

## WORKFLOW 2: Survey Instrument Design

### Step 1: Define Measurement Goals

For each construct, specify:
- **Conceptual definition**: What is the construct theoretically?
- **Operational definition**: What observable behavior/attitude/characteristic measures it?
- **Measurement level**: Nominal, ordinal, interval, ratio
- **Reference period**: "In the past 12 months," "currently," "ever"

### Step 2: Question Construction

**Question types and when to use:**

| Type | Best For | Example |
|------|----------|---------|
| Single-item Likert | Attitudes with established scales | "Strongly agree → Strongly disagree" |
| Multi-item scale | Latent constructs (trust, identity) | Average of 5 items; report α |
| Open-ended | Unexpected responses, sensitive topics | "In your own words, describe…" |
| Numeric entry | Factual, bounded | "How many years have you lived in the US?" |
| Matrix / grid | Battery of related items | Multiple rows, shared response scale |
| Ranking | Relative preference | "Rank the following from most to least…" |
| Filtered / branching | Subpopulation follow-ups | "If yes → [follow-up]" |

**Question wording rules:**
- One concept per question (no double-barreled: "Do you trust neighbors *and* local government?")
- Avoid negations
- 8th-grade reading level
- Offer "Don't know" / "Prefer not to answer" where appropriate
- Consistent response direction (higher = more of the construct)
- Match scale length to construct precision needed (5-pt standard; 7-pt for fine-grained attitudes)

**Established scales to use** (cite if using):
- Social trust: Rosenberg Trust Scale; GSS trust items
- Subjective SES: MacArthur Ladder (1–10)
- Discrimination: Everyday Discrimination Scale (Williams et al. 1997)
- Mental health: PHQ-9 (depression), GAD-7 (anxiety)
- Political attitudes: ANES scales
- Immigrant identity: MEIM-R (Phinney & Ong 2007)
- Social network: Burt (1984) name generator + name interpreter

See [references/survey-design.md](references/survey-design.md) for full item batteries.

### Step 3: Survey Organization

**Recommended order:**
1. Introduction screen (purpose, consent, confidentiality)
2. Screener questions (eligibility)
3. Salient but non-threatening items first
4. Sensitive items (income, discrimination, illegal behavior) later
5. Sociodemographics last
6. Debriefing / thank-you screen

**Sample size for surveys:**

| Goal | Rule of thumb | Notes |
|------|--------------|-------|
| Descriptive estimates (proportions) | N ≥ 400 for ±5% margin (95% CI) | N ≥ 1,000 for subgroup comparisons |
| Regression with 10 predictors | N ≥ 500 for OLS (Cohen's rule: 50 + 8k) | N ≥ 1,000 for logistic |
| Experimental contrast (d = 0.3, 80% power) | N ≥ 352 per arm | Use `pwr::pwr.t.test()` |
| Conjoint / AMCE (1% precision) | N ≥ 1,000, 3–5 tasks | More profiles = better precision |
| Multilevel (ICC = 0.10, L2 effects) | N ≥ 30 groups × 30 within | Use `pwr2ppl` or `simr` |

**Online panel quality tiers:**

| Tier | Panel | Quality | Cost | Best for |
|------|-------|---------|------|---------|
| Probability-based | IPSOS KnowledgePanel, Amerispeak | Highest | $$$ | Top-tier publication; nationally representative |
| High-quality opt-in | Prolific Academic | High | $$ | Academic research; attention checks built-in |
| MTurk | MTurk (via CloudResearch) | Medium | $ | Pilot testing; not recommended for main analysis |
| Convenience | Qualtrics panel, Lucid | Variable | $–$$ | Pretest; not representative |

**Data quality checks:**
- Completion time < ⅓ median → flag inattentive
- Straight-lining on Likert batteries
- Instructed response item failures (attention checks)
- Open-ended gibberish / copy-paste
- IP duplicates

### Step 4: Pilot and Cognitive Testing

1. Expert review (2–3 colleagues; face validity)
2. Cognitive interviewing (5–10 respondents; 4-probe protocol — see survey-design.md)
3. Pilot survey (N = 20–50; check distributions, timing, drop-off)
4. Psychometric checks: CFA for multi-item scales; remove items loading < 0.4

### Step 5: Fielding and Documentation

- Platform: Qualtrics (complex routing) > Prolific (probability-based recruitment) > REDCap (clinical/HIPAA)
- AAPOR response rate documentation (RR1–RR6) required in Methods
- Non-response analysis: compare respondents to non-respondents or population benchmarks

### Step 6: Experimental Survey Modules

#### Step 6a: Vignette / Factorial Survey Experiment

A factorial survey presents randomized descriptions (vignettes) of hypothetical persons or situations and asks respondents to evaluate them. Used to measure preferences, discrimination, or decision-making while controlling for confounds.

**Design:**
- 2–5 dimensions varied; 2–4 levels per dimension → full or fractional factorial design
- Each respondent rates 3–8 vignettes (avoid fatigue)
- Analyze with OLS clustered by respondent (AMCE: Average Marginal Component Effect)

**Vignette template:**
```
[Respondent instructions]:
"Below is a description of a job applicant. Please read carefully and rate
how likely you would be to invite them for an interview."

Job applicant profile:
  Name:            [RANDOMIZED: Michael Johnson / DeShawn Jackson / José García]
  Education:       [RANDOMIZED: High school diploma / Bachelor's degree / Master's degree]
  Years of exp.:   [RANDOMIZED: 2 years / 5 years / 10 years]
  Criminal record: [RANDOMIZED: None / Misdemeanor / Felony]

"How likely would you be to invite this applicant for an interview?"
  (1) Very unlikely — (2) Unlikely — (3) Neutral — (4) Likely — (5) Very likely
```

**Analysis (R):**
```r
library(cregg)
# Estimate AMCEs
amce_results <- cj(data = df, formula = outcome ~ name + education + experience + criminal,
                   id = ~respondent_id)
plot(amce_results) + theme_Publication()

# Subgroup AMCEs
amce_sub <- cj(df, outcome ~ name + education, id = ~respondent_id,
               by = ~respondent_race)
```

**Report:** "We used a factorial survey experiment with [N] vignettes and [K] randomized dimensions. Average marginal component effects (AMCEs; Hainmueller, Hopkins & Yamamoto 2014) were estimated using OLS with standard errors clustered by respondent."

#### Step 6b: List Experiment (Sensitive Item Measurement)

List experiments allow respondents to reveal sensitive attitudes (racism, illegal behavior, stigmatized conditions) without directly endorsing them — protecting against social desirability bias.

**Design (split-half):**
- Control group: 3 innocuous items → "How many of the following have you done in the past year?"
- Treatment group: same 3 items + 1 sensitive item
- Difference in means = % endorsing sensitive item

**Template:**
```
[Control condition]:
"Below is a list of things some people have done. Please tell us
HOW MANY you have done in the past year — not which ones, just how many."
  1. Watched a movie at home
  2. Donated to a charity
  3. Attended a religious service
  [Answer: 0 / 1 / 2 / 3]

[Treatment condition — adds sensitive item]:
  1. Watched a movie at home
  2. Donated to a charity
  3. Attended a religious service
  4. [Sensitive: e.g., "Used marijuana" / "Supported restricting immigration"]
  [Answer: 0 / 1 / 2 / 3 / 4]
```

**Analysis (R):**
```r
library(list)
lexp <- ict.test(df$count, df$treatment, J = 3, gms = TRUE)
summary(lexp)
# Reports: estimated prevalence + SE + 95% CI for sensitive item
```

**Sample size:** N ≥ 500 per arm (N ≥ 1,000 total) for ±5% precision. List experiments are statistically inefficient — plan for larger samples than direct questions would require.

---

## WORKFLOW 3: Qualitative Interview Protocol

### Step 1: Protocol Architecture

A qualitative interview guide has three parts:
1. **Preamble**: introduce yourself, state purpose, obtain consent, explain recording
2. **Core guide**: 8–15 open-ended questions organized thematically (3–5 themes)
3. **Closing**: ask for what was missed; offer referrals if sensitive topics were discussed

**Sampling strategy:**

| Strategy | Purpose | Typical N |
|----------|---------|-----------|
| Maximum variation | Capture full range of relevant variation | 20–40 |
| Homogeneous | Depth within one type | 15–25 |
| Theoretical (grounded theory) | Continue until conceptual saturation | 15–30 |
| Critical case | Test theory on hardest case | 5–15 |
| Snowball | Hard-to-reach populations | Varies |

Saturation typically occurs at N = 15–25 for a single population; more for comparative multi-group designs.

### Step 2: Question Sequence

See [references/interview-protocols.md](references/interview-protocols.md) for full template. Core structure:

1. Rapport opener (biographical, low-stakes)
2. Grand tour question (typical day / typical encounter with X)
3. Thematic questions (2–4 per theme) with explicit probes
4. Contrast / comparison questions
5. Meaning / interpretation questions
6. Closing ("What haven't I asked?")

**Probing types:** elaboration / clarification / example / contrast / emotional (use sparingly)

### Step 3: Sensitive Topics Protocol

- State upfront which topics will be covered; allow opt-out before starting
- Use distancing language: "Some people I've talked with say… What's your experience?"
- Never press for more detail than offered
- Prepare referral resources (hotlines, social services) before fieldwork
- Debrief at close: "We covered some difficult topics — how are you feeling?"

### Step 4: Focus Groups (alternative format)

Use when group interaction is the phenomenon of interest (e.g., deliberation, norm formation, collective sense-making). **Not** a substitute for in-depth interviews when individual experience is the target.

- Group size: 5–8 participants (too small → insufficient interaction; too large → some dominated)
- Number of groups: 3–6 per subgroup; stop when theoretical saturation is reached
- Facilitator role: introduce topics, manage dominant voices, ensure quieter participants contribute
- Co-facilitator: takes notes on nonverbal dynamics while facilitator runs discussion
- Analyze turn-taking patterns alongside content

### Step 5: Online / Video Interviews

- Zoom / Teams: adequate for most semi-structured interviews; less rapport than in-person
- Provide tech support beforehand; confirm platform access and audio/video
- Record with consent (built-in recording; confirm jurisdiction-specific legality)
- Background and setting: note if participant is in private vs. semi-public space
- Transcription: Otter.ai / Whisper for automatic draft; always human-review for accuracy

### Step 6: Multilingual Fieldwork

- Translate instrument using forward-backward procedure (translate → back-translate → reconcile)
- Use bilingual interviewers; never rely solely on respondent to translate
- Conduct interviews in respondent's preferred language; document language used
- Analysis: code from transcript in original language; translate selected quotes for publication
- Report language of interview and translation procedure in Methods

---

## WORKFLOW 4: Administrative and Secondary Data

### Step 1: Data Access Strategy

| Access type | Route | Timeline |
|-------------|-------|----------|
| Public use micro-data (ACS, CPS, GSS) | IPUMS, Census, ICPSR — register and download | Immediate |
| Restricted federal data (NLSY restricted, HRS geocoded) | ICPSR DUA | 2–4 weeks |
| FSRDC-linked data (SSA + IRS + survey) | FSRDC application (PI must be Census employee or external researcher) | 12–24 months |
| State administrative records (Medicaid, court, school) | State agency MOU + institutional DUA + IRB | 6–18 months |
| Private / commercial data (credit, social media, employer) | Data sharing agreement; often requires fee or in-kind contribution | Varies |

### Step 2: Data Documentation Review

Before analysis, document for every source:
- Survey instrument or administrative codebook / data dictionary
- Variable names, labels, value codes (distinguish "don't know" / "refused" / "not applicable")
- Sampling design: stratification, clustering, probability weights
- Panel structure (if longitudinal): wave IDs, response rates, attrition rates by wave
- Geographic identifiers and level of geography available (state / PUMA / tract)
- Top-coding and suppression rules (especially in restricted-use files)

### Step 3: Data Linkage

When merging two or more data sources:
- Document matching variables (name, SSN, address, date of birth, geographic ID)
- Report match rate and characterize match vs. non-match cases (selective linkage is a validity threat)
- **Probabilistic record linkage** (when exact matching fails):

```r
library(fastLink)
matches <- fastLink(
  dfA = df1, dfB = df2,
  varnames = c("fname", "lname", "dob", "zip"),
  stringdist.match = c("fname", "lname"),
  numeric.match = "zip",
  threshold.match = 0.85
)
matched <- getMatches(dfA = df1, dfB = df2, fl.out = matches)
```

- Report concordance rates for key variables across sources

### Step 4: Geographic / Spatial Data

```r
library(tidycensus)
library(sf)

# Download Census tract-level ACS variables
tracts <- get_acs(
  geography = "tract", state = "IL", county = "Cook",
  variables = c(medinc = "B19013_001", pct_black = "B03002_004"),
  year = 2022, geometry = TRUE
)

# TIGER/Line shapefiles
library(tigris)
counties_sf <- counties(state = "IL", cb = TRUE, year = 2022)

# Join survey / administrative data to geographic units
df_spatial <- df %>% left_join(tracts, by = c("tract_fips" = "GEOID"))
```

For historical geographic data: IPUMS NHGIS provides Census tract boundaries and variables for every decade since 1790.

---

## WORKFLOW 5: IRB and Research Ethics

### Step 1: Determine IRB Level

**Exempt categories** (45 CFR 46.104 — post-2018 Common Rule):

| Category | Description | Example |
|----------|-------------|---------|
| 1 | Normal educational practices in established educational settings | Classroom curriculum study |
| 2 | Anonymous surveys / interviews / observations (no sensitive topics; no identifiers) | Online survey on public attitudes |
| 2 (sensitive) | Survey / interview on sensitive topics but subjects are 18+ and disclosure would not harm them | Discrimination survey with adult workers |
| 3 | Benign behavioral interventions with verbal consent | Random assignment to information treatments |
| 4 | Secondary analysis of existing identifiable data if investigator cannot identify subjects | Analysis of de-identified medical records |
| 5 | Federal research on public benefit programs | Survey of SNAP recipients |
| 6 | Taste / food quality evaluation studies | Food preference study |
| 7 | Storage / maintenance of identifiable data for future secondary use | Biospecimen repository |
| 8 | Broad consent research using identifiable biospecimens | Genetic research |

**Expedited review** (minimal risk + falls into expedited categories): most online surveys with adults, in-depth interviews without vulnerable populations, secondary analysis of identifiable data with DUA.

**Full board review**: vulnerable populations (minors, prisoners, pregnant women); deception studies; research in international settings with different norms; studies involving more than minimal risk.

### Step 2: Waiver of Consent

A waiver of written (or all) consent may be granted when:
- The research involves no more than minimal risk
- Waiver will not adversely affect subjects' rights and welfare
- Research could not practicably be carried out without the waiver
- When appropriate, subjects will be provided pertinent information afterward

Online surveys with anonymous responses typically qualify for waiver of documented consent (checkbox consent screen suffices).

### Step 3: IRB Application Components

- Research protocol: purpose, procedures, population, timeline
- Consent form / script: lay language; institutional template required
- Survey instrument or interview guide: submit with application
- Recruitment materials: scripts, flyers, emails, social media posts
- Data security plan: storage, encryption, access controls, destruction timeline
- CITI training certificates: Human Subjects Research (social-behavioral track)
- Conflict of interest disclosure

### Step 4: Data Security Standards

- Remove direct identifiers (name, address, SSN, email) → replace with study IDs
- Store PII separately from research data in encrypted folder
- Use institutional storage for identified data (not personal Google Drive / Dropbox)
- Encrypt files at rest (VeraCrypt, BitLocker) and in transit (SFTP, not FTP)
- Specify retention period in IRB protocol (standard: 3 years post-publication; NIH: 7 years)

---

## WORKFLOW 6: Data Management Pipeline

### Step 1: Directory Structure

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
mkdir -p data/{raw,clean,analysis,codebooks} \
         docs/{irb,instruments,protocols} \
         scripts \
         "${OUTPUT_ROOT}"/{tables,figures}

# Protect raw data from accidental modification
chmod -w data/raw/
```

Maintain strict separation:
```
project/
├── data/
│   ├── raw/          ← NEVER modify; treat as read-only
│   ├── clean/        ← after cleaning; reproducible from raw
│   ├── analysis/     ← analytic sample used in paper
│   └── codebooks/    ← variable documentation
├── scripts/
│   ├── 01_download.R     (or .do)
│   ├── 02_clean.R
│   ├── 03_eda.R
│   ├── 04_main_models.R
│   ├── 05_robustness.R
│   └── 06_figures.R
├── output/[slug]/
│   ├── tables/
│   └── figures/
└── docs/
    ├── codebook.md
    ├── data_cleaning_log.md
    └── pre_analysis_plan.md
```

### Step 2: Git Version Control for Code

```bash
git init
git add scripts/ docs/ output/[slug]/
git commit -m "Initial project setup"

# .gitignore — keep sensitive data out of git
cat > .gitignore << 'EOF'
# Raw and identified data — never commit
data/raw/
data/clean/*.rds
data/clean/*.dta
data/analysis/

# Credentials and keys
.Renviron
.env
*.key

# OS and editor clutter
.DS_Store
*.Rproj.user/
__pycache__/
*.pyc
EOF
```

**Best practice:** Commit scripts and outputs (tables, figures) to git; never commit raw data or identified data files. Use `.Renviron` or `.env` for API keys.

### Step 3: Codebook

Create a codebook with variable-level documentation:

| var_name | var_label | type | values | missing_codes | source | notes |
|----------|-----------|------|--------|--------------|--------|-------|
| id | Unique respondent ID | string | — | — | Generated | Never use for analysis |
| educ_yrs | Years of education | integer | 0–25 | NA | Q14; recoded | midpoints: HS=12, BA=16 |
| income_1k | Annual HH income ($1000s) | numeric | 0–250 | NA | Q22 | top-coded at $250K |

**R codebook tools:**
```r
library(codebook); library(labelled)
var_label(df$educ_yrs) <- "Years of formal education completed"
val_labels(df$educ_cat) <- c("Less than HS" = 1, "HS" = 2, "Some college" = 3, "BA" = 4, "Grad" = 5)
codebook(df)  # generates HTML codebook
```

See [references/data-management.md](references/data-management.md) for R and Stata cleaning pipeline templates.

### Step 4: Data Sharing Plan (DMP)

Required for NSF/NIH grants and increasingly expected at Nature journals and Demography.

**DMP template:**

```
DATA MANAGEMENT PLAN — [Project Title]
PI: [Name] | Institution: [Name] | Date: [Date]

1. DATA TYPES AND SOURCES
   [Describe: survey data / administrative records / observational / experimental;
    estimated file sizes; formats (RDS, CSV, DTA, shapefiles)]

2. DATA COLLECTION AND STORAGE
   Collection method: [Qualtrics / IPUMS download / administrative transfer]
   Storage: [Institutional server + encrypted external backup]
   Backup frequency: [Daily automated backup; monthly off-site]
   Retention period: [3 years post-publication / 7 years (NIH) / permanent (if public value)]

3. DATA SHARING AND ACCESS
   Sharing plan: [Full public release / Restricted access / Unable to share (reason)]
   Repository: [Harvard Dataverse / ICPSR / Zenodo / OSF]
   Timeline: [Upon publication / within 12 months of completion]
   Format: [CSV + codebook + README (non-proprietary preferred)]
   Access restrictions: [None / IRB-approved researchers only / licensed use]

4. PRIVACY AND CONFIDENTIALITY
   Identifiers: [Removed per IRB protocol; study IDs only in shared files]
   Disclosure risk: [Suppression rules applied; k-anonymity ≥ 5 for geographic vars]
   Consent: [Participants consented to data sharing / anonymous; no consent needed]

5. ROLES AND RESPONSIBILITIES
   PI: [responsible for compliance, repository deposit]
   Co-I/RA: [responsible for data preparation and documentation]
```

### Step 5: Naming Conventions and Version Control

**Variables:** lowercase, underscores, no special characters
- Suffixes: `_cat` (categorical), `_bin` (binary), `_ln` (log), `_std` (standardized), `_w` (winsorized)
- Wave prefixes: `w1_`, `w2_` for panel data

**Files:** lowercase with hyphens; include date for versioned files
- `gss-2022-clean.rds`, `analysis-data-2024-01-15.rds`

**Scripts:** numbered for execution order (see directory structure above)

---

## WORKFLOW 7: Web Scraping and Digital Data Collection

Use when primary data must be collected from websites, social media platforms, news archives, or public APIs. Always attempt API-first; fall back to HTML scraping only when no API exists.

### Step 1: Ethical and Legal Framework

Before any scraping, review:

| Check | Requirement | Action if violated |
|-------|-------------|-------------------|
| `robots.txt` | Check `https://site.com/robots.txt`; respect `Disallow` paths | Do not scrape disallowed paths |
| Terms of Service | Read ToS; many platforms explicitly prohibit scraping | Use official API or request data license |
| Rate limits | Impose delays ≥ 1–3 sec between requests | Use `polite` (R) or `time.sleep()` (Python) |
| CFAA | U.S. Computer Fraud and Abuse Act — public data generally protected (*hiQ v. LinkedIn* 2022) | Document that data was publicly accessible without authentication |
| GDPR / privacy | EU personal data requires legal basis for collection | Anonymize or aggregate; consult IRB |
| IRB | Public posts generally exempt (Category 4); semi-public or identifiable data may require expedited review | Document IRB determination before collection |

**Polite scraping principles:**
- Identify your bot with an academic user-agent: `"Research bot — [Name], [Institution] ([email])"`
- Randomize delays: `Sys.sleep(runif(1, 1, 3))` / `time.sleep(random.uniform(1, 3))`
- Cache responses to avoid re-requesting the same pages
- Scrape during off-peak hours to minimize server load

### Web Scraping: Legal and Ethical Checklist

Before scraping, verify:
- [ ] **Terms of Service**: Does the website/platform prohibit scraping? (Twitter/X: Academic API discontinued Jan 2025, Pro tier $5K/mo required for full-archive; Reddit: check API terms; LinkedIn: scraping prohibited)
- [ ] **robots.txt**: Check `[domain]/robots.txt` for crawl restrictions
- [ ] **IRB review**: Does your institution consider public social media data as human subjects research? (Many do — check with your IRB)
- [ ] **Rate limiting**: Implement polite crawling (≥1 second between requests; respect rate limits)
- [ ] **Data storage**: Comply with GDPR if collecting EU user data (right to be forgotten, data minimization)
- [ ] **Identifiability**: Can users be identified from scraped content? If yes, de-identify before analysis
- [ ] **Consent**: Is there a reasonable expectation of privacy? (public tweets: generally no; private Facebook groups: yes)

**Platform-specific guidance**:
| Platform | Access Method | Rate Limit | Key Restriction |
|---|---|---|---|
| Twitter/X | X API v2 (Basic/Pro/Enterprise tiers; Academic Research track discontinued Jan 2025) | Varies by tier (Basic: 10K reads/mo free; Pro: 1M reads/mo $5K/mo) | Must not share raw tweet text; share IDs only; historical full-archive requires Pro+ |
| Reddit | Reddit API (register app) | 60 req/min (OAuth) | Respect subreddit rules; user consent not required for public posts |
| News sites | Web scraping + newspaper3k | Varies (check robots.txt) | Fair use for research; do not republish full text |
| Congressional Record | congress.gov API | No strict limit | Public domain; no restrictions |

---

### Step 2: API-First Strategy

Always prefer an official API over HTML scraping. Prioritize by data type:

**Social media:**

| Platform | API / Access route | Package | Notes |
|----------|--------------------|---------|-------|
| Twitter / X | X API v2 (Basic: free 10K reads/mo; Pro: $5K/mo 1M reads; Enterprise: custom; Academic Research track discontinued Jan 2025) | `academictwitteR` (R, limited to existing tokens), `tweepy` (Py) | Pro+ required for full-archive search; Basic tier severely rate-limited; consider Bluesky AT Protocol as alternative |
| Reddit | Reddit API v2 + PRAW | `RedditExtractoR` (R), `praw` (Py) | Free; rate limits enforced; Pushshift archive restricted as of 2023 |
| Facebook / Instagram | Meta Content Library (replaces CrowdTangle) | `contentid` + Meta API | Application required; access for academic researchers |
| TikTok | TikTok Research API | REST + Python SDK | Application required; limited to public content |
| YouTube | YouTube Data API v3 | `tuber` (R), `google-api-python-client` (Py) | Free quota: 10,000 units/day |

**News and text:**

| Source | API / Access | Package | Notes |
|--------|-------------|---------|-------|
| GDELT | BigQuery or direct download | `Rgdelt` (R), pandas direct | Free; global news events + tone + location + URLs |
| MediaCloud | mediacloud.org | `mediacloud` (Py) | Story-level coverage and framing; requires registration |
| NewsAPI | newsapi.org | REST | Free tier: 1 month history; developer tier: $449/mo |
| Internet Archive | CDX API + Wayback Machine | `wayback` (R), requests CDX | Full historical web; excellent for longitudinal designs |

**Government and social science APIs:**

```r
# Census API via tidycensus (see WORKFLOW 4)
# BLS API
library(blsAPI)
bls_data <- blsAPI(list(seriesid = "LNS14000000", startyear = "2010", endyear = "2023"))

# World Bank via WDI
library(WDI)
wdi <- WDI(country = c("US", "MX", "CA"), indicator = "NY.GDP.MKTP.CD",
           start = 2000, end = 2022)

# FRED (Federal Reserve Economic Data)
library(fredr)
fredr_set_key(Sys.getenv("FRED_API_KEY"))
unemp <- fredr(series_id = "UNRATE", observation_start = as.Date("2000-01-01"))
```

---

### Step 3: Static HTML Scraping — R (`rvest` + `polite`)

Use for sites with HTML-rendered content (no JavaScript required):

```r
library(rvest)
library(polite)
library(tidyverse)

# Step 1: Establish a polite session (checks robots.txt + sets delays)
session <- bow(
  url        = "https://example.com/articles",
  user_agent = "Academic research bot (set your email in SCHOLAR_CROSSREF_EMAIL)",
  delay      = 2  # minimum seconds between requests
)

# Step 2: Scrape a single page
page <- scrape(session)

# Step 3: Extract elements via CSS selectors (use browser DevTools to find selectors)
titles <- page %>% html_nodes("h2.article-title") %>% html_text(trim = TRUE)
links  <- page %>% html_nodes("a.article-link")   %>% html_attr("href")
dates  <- page %>% html_nodes("span.pub-date")     %>% html_text(trim = TRUE)

df_page <- tibble(title = titles, url = links, date = dates)

# Step 4: Multi-page scraping (paginated)
base_url <- "https://example.com/articles?page="
results  <- map_dfr(1:20, function(p) {
  nod(session, paste0(base_url, p)) %>%  # update URL, keep polite session
    scrape() %>%
    {tibble(
      title = html_nodes(., "h2.article-title") %>% html_text(trim = TRUE),
      url   = html_nodes(., "a.article-link")   %>% html_attr("href"),
      date  = html_nodes(., "span.pub-date")     %>% html_text(trim = TRUE)
    )}
}, .progress = TRUE)

# Step 5: Save raw data immediately
saveRDS(results, "data/raw/scraped-articles-raw.rds")
write_csv(results, "data/raw/scraped-articles-raw.csv")
message("Scraped N = ", nrow(results), " articles")
```

**Selector identification:** In Chrome/Firefox, right-click an element → Inspect → right-click in DevTools → Copy → Copy selector. Prefer class-based selectors (`.article-title`) over position-based (`div > p:nth-child(3)`).

---

### Step 4: Static HTML Scraping — Python (`requests` + `BeautifulSoup`)

```python
import requests
from bs4 import BeautifulSoup
import pandas as pd
import time, random, json
from pathlib import Path

HEADERS = {
    "User-Agent": "Academic research bot (set your email in SCHOLAR_CROSSREF_EMAIL)"
}

session = requests.Session()
session.headers.update(HEADERS)

def scrape_page(url: str, delay: tuple = (1.0, 3.0)) -> BeautifulSoup:
    """Politely fetch and parse a single page."""
    time.sleep(random.uniform(*delay))
    resp = session.get(url, timeout=15)
    resp.raise_for_status()
    return BeautifulSoup(resp.text, "html.parser")

def parse_article(soup: BeautifulSoup) -> dict:
    return {
        "title": soup.select_one("h2.article-title").get_text(strip=True),
        "date":  soup.select_one("span.pub-date").get_text(strip=True),
        "body":  " ".join(p.get_text(strip=True)
                          for p in soup.select("div.article-body p"))
    }

# Multi-page collection
records = []
for page_num in range(1, 21):
    soup = scrape_page(f"https://example.com/articles?page={page_num}")
    for card in soup.select("div.article-card"):
        records.append({
            "title": card.select_one("h2").get_text(strip=True),
            "url":   card.select_one("a")["href"],
            "date":  card.select_one("span.date").get_text(strip=True)
        })
    print(f"Page {page_num}: {len(records)} articles so far")

df = pd.DataFrame(records)
Path("data/raw").mkdir(parents=True, exist_ok=True)
df.to_csv("data/raw/scraped-articles-raw.csv", index=False)
print(f"Saved {len(df)} articles")
```

---

### Step 5: Dynamic / JavaScript-Rendered Pages

For single-page applications (React, Vue) or pages that load content via XHR after initial HTML load:

**R — `chromote` (recommended; headless Chrome):**

```r
library(chromote)
library(rvest)

b <- ChromoteSession$new()

# Navigate and wait for content
b$Page$navigate("https://example.com/dynamic-page")
b$Page$loadEventFired()          # wait for full page load
Sys.sleep(2)                     # extra wait for JS rendering

# Extract rendered HTML
html <- b$Runtime$evaluate("document.documentElement.outerHTML")$result$value
page <- read_html(html)
b$close()

# Parse as usual with rvest
titles <- page %>% html_nodes("h2.article-title") %>% html_text(trim = TRUE)
```

**Python — `playwright` (recommended over selenium):**

```python
from playwright.sync_api import sync_playwright
import time

with sync_playwright() as p:
    browser = p.chromium.launch(headless=True)
    page    = browser.new_page()

    # Set academic user-agent
    page.set_extra_http_headers({
        "User-Agent": "Academic research bot — [Your Name], [Your University]"
    })

    page.goto("https://example.com/dynamic-page")
    page.wait_for_selector("div.article-list")   # wait for target element
    time.sleep(1)

    # Interact if needed (e.g., click "Load more")
    while page.locator("button.load-more").count() > 0:
        page.locator("button.load-more").click()
        page.wait_for_load_state("networkidle")
        time.sleep(random.uniform(1, 2))

    html = page.content()
    browser.close()

soup = BeautifulSoup(html, "html.parser")
```

**Install:** `pip install playwright && playwright install chromium` / `install.packages("chromote")`

---

### Step 6: Social Media Data Collection

#### Twitter / X (X API v2)

> **Note (updated 2026):** The Academic Research track was discontinued in January 2025. The code below still works with X API v2 Bearer tokens, but full-archive search now requires a Pro ($5K/mo) or Enterprise tier. The free Basic tier allows only 10K tweet reads/month. For new social media research projects, consider Bluesky (AT Protocol, free firehose access) or Meta Content Library as alternatives.

```r
library(academictwitteR)

# Authenticate (store bearer token in .Renviron as TWITTER_BEARER)
set_bearer()

# Full-archive search (Academic access required)
tweets <- get_all_tweets(
  query    = '"redlining" lang:en -is:retweet',
  start_tweets = "2020-01-01T00:00:00Z",
  end_tweets   = "2023-12-31T23:59:59Z",
  n        = 50000,
  data_path = "data/raw/tweets/"
)

# Bind collected data
df_tweets <- bind_tweets(data_path = "data/raw/tweets/", output_format = "tidy")
```

```python
# Python — tweepy v4
import tweepy, json, os

client = tweepy.Client(bearer_token=os.environ["TWITTER_BEARER"], wait_on_rate_limit=True)

paginator = tweepy.Paginator(
    client.search_all_tweets,
    query         = '"redlining" lang:en -is:retweet',
    tweet_fields  = ["created_at", "author_id", "text", "public_metrics", "geo"],
    start_time    = "2020-01-01T00:00:00Z",
    end_time      = "2023-12-31T23:59:59Z",
    max_results   = 500
)

tweets = [t for page in paginator for t in page.data or []]
with open("data/raw/tweets.jsonl", "w") as f:
    for t in tweets:
        f.write(json.dumps(t.data) + "\n")
print(f"Collected {len(tweets)} tweets")
```

#### Reddit (PRAW)

```python
import praw, pandas as pd, os

reddit = praw.Reddit(
    client_id     = os.environ["REDDIT_CLIENT_ID"],
    client_secret = os.environ["REDDIT_CLIENT_SECRET"],
    user_agent    = "Academic research — [Your Name], [Your University]"
)

# Collect posts from subreddits
subreddits = ["sociology", "urbanplanning", "firsttimehomebuyer"]
records = []
for sub_name in subreddits:
    sub = reddit.subreddit(sub_name)
    for post in sub.search("redlining", limit=500, time_filter="year"):
        records.append({
            "id": post.id, "subreddit": sub_name,
            "title": post.title, "selftext": post.selftext,
            "score": post.score, "num_comments": post.num_comments,
            "created_utc": post.created_utc, "url": post.url
        })

df = pd.DataFrame(records)
df.to_parquet("data/raw/reddit-posts.parquet", index=False)
```

---

### Step 7: Large-Scale Text and News Sources

**GDELT (global news events):**

```r
library(Rgdelt)
# Download event data for specific countries/actors
events <- gdelt_data(
  start_date = "2020-01-01", end_date = "2023-12-31",
  type = "events", country = "US"
)
# Or query via BigQuery for full dataset (free 1TB/month)
```

**Internet Archive Wayback Machine (longitudinal web):**

```python
import requests, pandas as pd

def wayback_cdx(url: str, from_date: str, to_date: str) -> pd.DataFrame:
    """Get all archived snapshots of a URL between two dates."""
    cdx_url = (
        f"http://web.archive.org/cdx/search/cdx?url={url}&output=json"
        f"&from={from_date}&to={to_date}&fl=timestamp,statuscode,original"
        f"&filter=statuscode:200&collapse=timestamp:6"  # one per month
    )
    resp = requests.get(cdx_url, timeout=30)
    rows = resp.json()[1:]  # skip header
    return pd.DataFrame(rows, columns=["timestamp", "statuscode", "url"])

snaps = wayback_cdx("example.com/policy-page", "20200101", "20231231")
# Retrieve archived HTML for each snapshot
for _, row in snaps.iterrows():
    archive_url = f"https://web.archive.org/web/{row.timestamp}/{row.url}"
    # ... scrape archive_url with requests + BeautifulSoup
```

---

### Step 8: Storage, Provenance, and Pipeline

**Always record metadata alongside scraped content:**

```r
# R: store with provenance metadata
df_raw <- df_raw %>%
  mutate(
    scraped_at = Sys.time(),
    source_url  = "https://example.com",
    scraper_version = "v1.0"
  )
saveRDS(df_raw, paste0("data/raw/scraped-", Sys.Date(), ".rds"))
```

```python
# Python: use DuckDB for large structured collections (faster than SQLite for analytics)
import duckdb, pandas as pd

con = duckdb.connect("data/raw/scraped.duckdb")
con.execute("""
    CREATE TABLE IF NOT EXISTS articles (
        id          VARCHAR PRIMARY KEY,
        url         VARCHAR,
        title       VARCHAR,
        date        DATE,
        body        TEXT,
        scraped_at  TIMESTAMP,
        source      VARCHAR
    )
""")
# Insert records in batch
con.executemany(
    "INSERT OR IGNORE INTO articles VALUES (?, ?, ?, ?, ?, ?, ?)",
    df[["id","url","title","date","body","scraped_at","source"]].values.tolist()
)
con.close()
```

**Parquet for large text corpora:**

```python
import pandas as pd
# Write in compressed Parquet partitioned by year
df.to_parquet("data/raw/news-corpus/", partition_cols=["year"], index=False)
# Read back a single year
df_2022 = pd.read_parquet("data/raw/news-corpus/year=2022/")
```

**Web scraping directory extension:**

```bash
mkdir -p data/raw/html_cache    # cached HTML pages
mkdir -p data/raw/api_responses # raw API JSON
mkdir -p scripts/scraping       # scraper scripts
echo "data/raw/html_cache/" >> .gitignore
echo "data/raw/api_responses/" >> .gitignore
```

**Scraping log template** (save as `docs/scraping-log.md`):

```
SCRAPING LOG
─────────────────────────────────────
Target site:       [URL]
Date range:        [start] to [end]
Script:            scripts/scraping/01_scrape.py
robots.txt status: Complied / No restrictions
ToS reviewed:      Yes / No — [notes]
IRB determination: [Exempt Cat. 4 / Expedited / Full]
Rate limiting:     [X] sec delay; randomized ± [Y] sec
Total records:     [N]
Raw files:         data/raw/[filename].parquet / .rds
Scrape timestamp:  [datetime]
Notes:             [any errors, blocks, or partial coverage]
─────────────────────────────────────
```

**For downstream text analysis:** hand off to `/scholar-compute` MODULE 1 (NLP: STM, BERT, LLM annotation) after cleaning.

See [references/web-scraping.md](references/web-scraping.md) for extended code examples, CSS selector guide, API authentication patterns, rate-limit handling, and error recovery.

---

## Save Output

After completing all relevant workflows, save a data plan document using the Write tool.

### Version Collision Avoidance (MANDATORY)

**Before EVERY Write tool call below**, run this Bash block to determine the correct save path. Do NOT hardcode paths from the filename templates — they show naming patterns only.

```bash
# MANDATORY: Replace [values] with actuals before running
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
# BASE pattern: ${OUTPUT_ROOT}/[slug]/data/scholar-data-[topic-slug]-[YYYY-MM-DD]
# Split into directory and stem for the gate script:
OUTDIR="$(dirname "${OUTPUT_ROOT}/[slug]/data/scholar-data-[topic-slug]-[YYYY-MM-DD]")"
STEM="$(basename "${OUTPUT_ROOT}/[slug]/data/scholar-data-[topic-slug]-[YYYY-MM-DD]")"
mkdir -p "$OUTDIR"
bash "${SCHOLAR_SKILL_DIR:-.}/scripts/gates/version-check.sh" "$OUTDIR" "$STEM"
```

**Use the printed `SAVE_PATH` as `file_path` in the Write tool call.** Re-run this block (with the appropriate BASE) for each additional file. The same version suffix must be used for all related output files (.md, .docx, .tex, .pdf).

**Filename:** `scholar-data-[topic-slug]-[YYYY-MM-DD].md`

**Contents:**

```markdown
# Data Plan: [topic]
*Generated by /scholar-data on [YYYY-MM-DD]*

## Data Blueprint
[Fill from WORKFLOW 1 Step 1c: dataset, unit, N, Y, X, M, W, controls, design]

## Variable Dictionary
[Full table from WORKFLOW 1 Step 1a]

## Data Access Plan
[Dataset name + access route + estimated timeline]

## Survey / Interview / Instrument Notes
[If new data collection: platform, panel, sample size rationale, cognitive testing plan]

## IRB Plan
[Determination: exempt / expedited / full; waiver of consent: yes/no; data security approach]

## Data Management Plan Summary
[Directory structure, git plan, codebook location, DMP repository]

## File Inventory
data/raw/           ← [source files]
data/clean/         ← [cleaned dataset: name.rds / .dta]
data/analysis/      ← [analytic sample: name.rds]
data/codebooks/     ← codebook.md
docs/               ← irb/, instruments/, protocols/
```

Confirm saved file path to user after Write completes.

**Close Process Log:**

Run the following to finalize the process log:

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
SKILL_NAME="scholar-data"
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

- [ ] Dataset selected with access timeline confirmed (WORKFLOW 0)
- [ ] Dataset fit verified: unit of analysis, time period, key variables available
- [ ] Variable dictionary complete: Y, X, M, W, all controls operationalized
- [ ] Data blueprint written with analytic sample definition
- [ ] Post-treatment variables identified and flagged
- [ ] Survey instrument: measurement goals defined; established scales cited; question wording rules followed
- [ ] If experimental: vignette design balanced; AMCE analysis planned; sample size adequate
- [ ] If list experiment: control/treatment split-half design; N ≥ 1,000 total
- [ ] If qualitative: sampling strategy specified; saturation criterion defined; sensitive topics protocol prepared
- [ ] IRB determination made; application components identified; CITI certificates current
- [ ] Data security plan documented (encryption, storage, retention)
- [ ] Data directory structure created (`data/raw/`, `clean/`, `analysis/`, `codebooks/`)
- [ ] `.gitignore` set to exclude raw/identified data from git
- [ ] Codebook shell drafted
- [ ] Data sharing / DMP plan drafted (required for NSF/NIH; increasingly required for journals)
- [ ] If web scraping: `robots.txt` and ToS reviewed; polite delays set; IRB determination documented
- [ ] If web scraping: scraping log created (`docs/scraping-log.md`) with site, date range, rate limits, N records
- [ ] If web scraping: raw HTML/JSON cached separately from parsed data; provenance fields added (scraped_at, source_url)
- [ ] Data plan saved to `scholar-data-[slug]-[date].md`

See [references/survey-design.md](references/survey-design.md) for scale batteries, platform comparison, and cognitive interview protocol.
See [references/interview-protocols.md](references/interview-protocols.md) for full protocol template, sampling strategies, and field notes template.
See [references/data-management.md](references/data-management.md) for codebook template, cleaning pipeline code (R + Stata), and decision log.
See [references/web-scraping.md](references/web-scraping.md) for extended scraping code, CSS selector guide, API authentication patterns, rate-limit handling, and error recovery.
