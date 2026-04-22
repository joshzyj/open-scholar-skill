# Source Registry — Schema & Editing Guide

User-editable at `~/.claude/scholar-monitor/sources.json` (or `$SCHOLAR_MONITOR_DIR/sources.json`). Populated on first run from `assets/default-sources.json`.

## Top-Level Schema

```json
{
  "version": "1.0",
  "defaults": {
    "crossref_email": "",
    "max_per_tick": 20,
    "first_run_lookback_days": 14
  },
  "sources": [ { ... }, { ... } ]
}
```

- `version` — schema version. Do not change; used by future migrations.
- `defaults.crossref_email` — your email; improves Crossref/OpenAlex rate limits (the "polite pool"). Highly recommended.
- `defaults.max_per_tick` — fallback cap when a source does not specify its own.
- `defaults.first_run_lookback_days` — on a source's first fetch, how far back to look. Default 14. Increase for slower journals; decrease for firehose sources.

## Source Entry Schema

| Field | Required | Description |
|---|---|---|
| `id` | ✓ | Short unique identifier (kebab-case). Used in `/scholar-monitor <id>` and state keys. |
| `enabled` | ✓ | `true` to include in default runs; `false` to pause without deleting. |
| `type` | ✓ | One of `crossref`, `arxiv`, `openalex`, `rss`. See `fetcher-protocols.md`. |
| `issn` | crossref/openalex | Journal ISSN (print or electronic). |
| `query` | arxiv | arXiv search syntax (see fetcher-protocols.md). |
| `url` | rss | Feed URL. |
| `category` | ✓ | Free-text group label for digest section headings. |
| `cadence_days` | ✓ | Minimum days between fetches. Cadence filter drops too-frequent invocations. |
| `max_per_tick` | ✓ | Cap on papers emitted per run. Excess silently dropped (sorted newest-first, so you never miss new ones). |
| `note` | ✗ | Human-readable name or comment. Shown in `list` / `status` modes. |

## ISSN Quick-Reference (Sociology & Adjacent)

| Journal | ISSN |
|---|---|
| American Sociological Review | 0003-1224 |
| American Journal of Sociology | 0002-9602 |
| Social Forces | 0037-7732 |
| Social Problems | 0037-7791 |
| Annual Review of Sociology | 0360-0572 |
| Demography | 0070-3370 |
| Population and Development Review | 0098-7921 |
| Gender & Society | 0891-2432 |
| Sociology of Education | 0038-0407 |
| Journal of Marriage and Family | 0022-2445 |
| Ethnic and Racial Studies | 0141-9870 |
| Du Bois Review | 1742-058X |
| Social Science Research | 0049-089X |
| Sociological Methods & Research | 0049-1241 |
| Nature Human Behaviour | 2397-3374 |
| Science Advances | 2375-2548 |
| Nature Computational Science | 2662-8457 |
| American Political Science Review | 0003-0554 |
| PNAS | 0027-8424 |
| Poetics | 0304-422X |
| Sociological Science | 2330-6696 |
| City & Community | 1535-6841 |
| Socius | 2378-0231 |
| Sociological Theory | 0735-2751 |
| Social Networks | 0378-8733 |
| International Migration Review | 0197-9183 |
| Sociology of Race and Ethnicity | 2332-6492 |
| Language in Society | 0047-4045 |
| Journal of Sociolinguistics | 1360-6441 |

## arXiv Categories

| Category | Description |
|---|---|
| `cs.CL` | Computation and Language (NLP, LLMs) |
| `cs.AI` | Artificial Intelligence |
| `cs.LG` | Machine Learning |
| `cs.CY` | Computers and Society |
| `cs.SI` | Social and Information Networks |
| `stat.ML` | Statistics — Machine Learning |
| `stat.AP` | Statistics — Applications |
| `econ.GN` | Economics — General |
| `econ.EM` | Econometrics |
| `q-fin.EC` | Quantitative Finance — Economics |

## Adding a Source — Examples

**A new sociology journal (Socius)**:
```json
{
  "id": "socius",
  "enabled": true,
  "type": "crossref",
  "issn": "2378-0231",
  "category": "Sociology — Open Access",
  "cadence_days": 7,
  "max_per_tick": 10,
  "note": "Socius (ASA open-access flagship)"
}
```

**A filtered arXiv query**:
```json
{
  "id": "arxiv-fairness-ml",
  "enabled": true,
  "type": "arxiv",
  "query": "cat:cs.LG AND (abs:\"algorithmic fairness\" OR abs:\"algorithmic bias\")",
  "category": "Preprints — Fairness / Ethics in ML",
  "cadence_days": 2,
  "max_per_tick": 15
}
```

**An OpenAlex fallback for a Crossref source that returns empty abstracts**:
```json
{
  "id": "asr-openalex",
  "enabled": true,
  "type": "openalex",
  "issn": "0003-1224",
  "category": "Sociology — Top General",
  "cadence_days": 7,
  "max_per_tick": 10,
  "note": "OpenAlex mirror of ASR — fills in missing abstracts"
}
```
Dedup by DOI will collapse overlaps; unique abstracts from OpenAlex supplement Crossref's sparse metadata.

## Cadence Choice — Rules of Thumb

- **Daily (`cadence_days: 1`)**: arXiv categories you track actively; PNAS.
- **Bi-daily (`2`)**: arXiv CSS / econ; fast-moving Nature family.
- **Weekly (`7`)**: most top sociology journals (ASR, AJS, Social Forces); Nature Human Behaviour.
- **Bi-weekly (`14`)**: subfield journals, Demography, SMR.
- **Monthly (`30`)**: quarterly / low-volume (Annual Review of Sociology, Du Bois Review).

Set short cadence on small registries; long cadence on many sources. `/loop 1h /scholar-monitor` with 18 sources on weekly cadence = ~2.5 digests/day on average as sources come due in rotation.

## Archive Rotation

The `archive.ndjson` file at `$SCHOLAR_MONITOR_DIR/archive.ndjson` is append-only and never auto-rotated. At ~2 KB per paper record, expect ~7 MB/year for a moderate setup (10 papers/day × 365 days). Not a problem for years of use, but `/scholar-monitor digest last-30` does a full-file scan and gets linearly slower as the archive grows.

**When to rotate manually**:
- When `/scholar-monitor status` reports archive size > 50 MB
- When `digest` mode feels sluggish (seconds-to-minutes)

**How to rotate**:

```bash
SMD="${SCHOLAR_MONITOR_DIR:-$HOME/.claude/scholar-monitor}"
STAMP=$(date +%Y-%m)
mv "$SMD/archive.ndjson" "$SMD/archive-${STAMP}.ndjson.bak"
touch "$SMD/archive.ndjson"
```

Archived backups are still readable by `/scholar-monitor digest` if you move them back temporarily, or by `jq`/`python3 -c` directly. The knowledge-graph ingest was already done at fetch time; rotation doesn't lose any graph data.

---

## Editing Workflow

```bash
# Edit
$EDITOR "${SCHOLAR_MONITOR_DIR:-$HOME/.claude/scholar-monitor}/sources.json"

# Validate — must be valid JSON
python3 -c "import json,sys; json.load(open(sys.argv[1]))" \
    "${SCHOLAR_MONITOR_DIR:-$HOME/.claude/scholar-monitor}/sources.json"

# Preview what would fetch on next tick
/scholar-monitor list
```

If you break the JSON, the skill refuses to run until fixed — it does not silently fall back to defaults (that would cause silent data loss of your custom sources).
