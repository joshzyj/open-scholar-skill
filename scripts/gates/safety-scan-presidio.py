#!/usr/bin/env python3
"""
Presidio-based PII/sensitive data scanner for research files.
Called by safety-scan.sh when presidio-analyzer is installed.

Usage: python3 safety-scan-presidio.py <file_path> [--json]
Exit codes: 0 = GREEN, 1 = RED, 2 = YELLOW
"""

import sys
import json
import os

# Opaque binary formats: compressed/encoded data where reading raw bytes
# as text produces garbage that wastes Presidio cycles and never finds
# anything useful. Mirror the binary list in safety-scan.sh so we exit
# fast. Note: PDF/DOCX/XLSX are intentionally OMITTED — those formats
# often contain extractable plaintext fragments (PDF content streams,
# OOXML XML) that Presidio CAN usefully scan, so we let them through.
OPAQUE_BINARY_EXTENSIONS = frozenset({
    "dta", "sav", "rds", "rdata", "parquet", "feather", "arrow",
    "h5", "hdf5", "mat", "pkl", "npy", "npz", "pickle",
    "sqlite", "db",
    "wav", "mp3", "flac", "m4a", "ogg", "aac", "aiff",
    "mp4", "mov", "avi", "mkv", "webm",
    "jpg", "jpeg", "png", "tiff", "tif", "heic", "heif", "bmp", "webp", "gif",
})

# spaCy's default nlp.max_length is 1,000,000 chars. Research files
# (CSV codebooks, multi-MB PDFs) routinely exceed this and crash the
# default pipeline with ValueError [E088]. Bump the limit on the
# analyzer's NLP backbone, and truncate text as a last-ditch backstop
# in case the API differs across Presidio versions.
SPACY_MAX_LENGTH = 10_000_000        # 10M chars ≈ 10 MB of text
TEXT_TRUNCATION_LIMIT = 9_500_000    # leave headroom under SPACY_MAX_LENGTH


def check_presidio_available():
    try:
        from presidio_analyzer import AnalyzerEngine
        return True
    except ImportError:
        return False

def build_analyzer():
    from presidio_analyzer import AnalyzerEngine, PatternRecognizer, Pattern

    analyzer = AnalyzerEngine()

    # ── Custom recognizers for research-sensitive data ──

    # HIPAA identifiers
    hipaa_recognizer = PatternRecognizer(
        supported_entity="HIPAA_IDENTIFIER",
        name="hipaa_recognizer",
        patterns=[
            Pattern("medical_record", r"\b(medical[\s_]?record|patient[\s_]?id|mrn|health[\s_]?plan|beneficiary)\b", 0.7),
            Pattern("clinical_data", r"\b(diagnosis|icd[\s_]?[0-9]|prescription|medication|treatment[\s_]?plan|discharge[\s_]?summary)\b", 0.5),
        ],
        supported_language="en",
    )

    # Mental health (high-sensitivity)
    mental_health_recognizer = PatternRecognizer(
        supported_entity="MENTAL_HEALTH_DATA",
        name="mental_health_recognizer",
        patterns=[
            Pattern("high_sensitivity", r"\b(suicid(?:e|al|ality)|self[\s_]?harm|bipolar|schizophren(?:ia|ic)|psychosis|eating[\s_]?disorder)\b", 0.7),
            Pattern("with_data_markers", r"\b(?:patient|subject|respondent|participant|score|scale|diagnosis|_id|_code)\b.*\b(?:depression|ptsd|anxiety[\s_]?disorder|psychiatric|mental[\s_]?health[\s_]?diagnosis)\b", 0.85),
        ],
        supported_language="en",
    )

    # Immigration / legal status
    immigration_recognizer = PatternRecognizer(
        supported_entity="IMMIGRATION_STATUS",
        name="immigration_recognizer",
        patterns=[
            Pattern("immigration", r"\b(undocumented|immigration[\s_]?status|deportat|asylum[\s_]?seek|visa[\s_]?status|DACA|refugee[\s_]?status|legal[\s_]?status|citizenship[\s_]?status)\b", 0.8),
            Pattern("criminal", r"\b(arrest[\s_]?record|criminal[\s_]?record|conviction|incarcerat|parole|probation|mugshot|booking)\b", 0.8),
        ],
        supported_language="en",
    )

    # Financial data
    financial_recognizer = PatternRecognizer(
        supported_entity="FINANCIAL_DATA",
        name="financial_recognizer",
        patterns=[
            Pattern("accounts", r"\b(credit[\s_]?card|account[\s_]?number|bank[\s_]?account|routing[\s_]?number|tax[\s_]?id|ein)\b", 0.8),
            Pattern("individual_finance", r"\b(income[\s_]?amount|salary|wage[\s_]?rate|net[\s_]?worth)\b", 0.5),
        ],
        supported_language="en",
    )

    # Biometric / genetic
    biometric_recognizer = PatternRecognizer(
        supported_entity="BIOMETRIC_DATA",
        name="biometric_recognizer",
        patterns=[
            Pattern("biometric", r"\b(biometric|fingerprint|retina|facial[\s_]?recognition|dna[\s_]?sample|genetic[\s_]?data|genome)\b", 0.8),
        ],
        supported_language="en",
    )

    # Personal name fields in structured data (column headers)
    name_field_recognizer = PatternRecognizer(
        supported_entity="NAME_FIELD",
        name="name_field_recognizer",
        patterns=[
            Pattern("name_column", r"\b(first_?name|last_?name|full_?name|respondent_?name|participant_?name)\b", 0.85),
        ],
        supported_language="en",
    )

    # Date of birth
    dob_recognizer = PatternRecognizer(
        supported_entity="DATE_OF_BIRTH",
        name="dob_recognizer",
        patterns=[
            Pattern("dob", r"\b(date[\s_.]?of[\s_.]?birth|dob|birth[\s_.]?date)\b", 0.85),
        ],
        supported_language="en",
    )

    # Sexual orientation / gender identity
    sogi_recognizer = PatternRecognizer(
        supported_entity="SOGI_DATA",
        name="sogi_recognizer",
        patterns=[
            Pattern("sogi", r"\b(sexual[\s_]?orientation|gender[\s_]?identity|transgender|lgbtq|non[\s_]?binary|sexual[\s_]?preference|coming[\s_]?out)\b", 0.5),
        ],
        supported_language="en",
    )

    # Religious / political affiliation
    belief_recognizer = PatternRecognizer(
        supported_entity="BELIEF_DATA",
        name="belief_recognizer",
        patterns=[
            Pattern("belief", r"\b(religious[\s_]?affiliation|political[\s_]?affiliation|party[\s_]?registration|church[\s_]?membership|mosque|synagogue|temple[\s_]?membership)\b", 0.5),
        ],
        supported_language="en",
    )

    # Restricted data markers
    restricted_recognizer = PatternRecognizer(
        supported_entity="RESTRICTED_MARKER",
        name="restricted_recognizer",
        patterns=[
            Pattern("restricted", r"\b(restricted[\s_]?use|confidential|under[\s_]?embargo|data[\s_]?use[\s_]?agreement|DUA)\b", 0.5),
        ],
        supported_language="en",
    )

    # Sub-state geographic identifiers
    geo_recognizer = PatternRecognizer(
        supported_entity="GEO_IDENTIFIER",
        name="geo_recognizer",
        patterns=[
            Pattern("geo", r"\b(census[\s_]?tract|block[\s_]?group|zip[\s_]?code|street[\s_]?address|latitude|longitude|geocode)\b", 0.5),
        ],
        supported_language="en",
    )

    # SSN broad pattern (Presidio's built-in US_SSN excludes known test SSNs like 123-45-6789;
    # for research data scanning we want to flag ANY XXX-XX-XXXX pattern)
    ssn_broad_recognizer = PatternRecognizer(
        supported_entity="US_SSN",
        name="ssn_broad_recognizer",
        patterns=[
            Pattern("ssn_broad", r"\b[0-9]{3}-[0-9]{2}-[0-9]{4}\b", 0.8),
        ],
        supported_language="en",
    )

    for r in [hipaa_recognizer, mental_health_recognizer, immigration_recognizer,
              financial_recognizer, biometric_recognizer, name_field_recognizer,
              dob_recognizer, sogi_recognizer, belief_recognizer,
              restricted_recognizer, geo_recognizer, ssn_broad_recognizer]:
        analyzer.registry.add_recognizer(r)

    return analyzer


# ── Severity classification ──

RED_ENTITIES = {
    "US_SSN", "CREDIT_CARD", "US_BANK_NUMBER", "IBAN_CODE",
    "PERSON",  # Presidio's NER-based person detector
    "HIPAA_IDENTIFIER", "IMMIGRATION_STATUS",
    "BIOMETRIC_DATA", "NAME_FIELD", "DATE_OF_BIRTH",
}

YELLOW_ENTITIES = {
    "EMAIL_ADDRESS", "PHONE_NUMBER", "IP_ADDRESS", "LOCATION",
    "FINANCIAL_DATA", "SOGI_DATA", "BELIEF_DATA",
    "RESTRICTED_MARKER", "GEO_IDENTIFIER",
}

# Entities to skip (too noisy for research text)
SKIP_ENTITIES = {"DATE_TIME", "NRP", "URL", "US_DRIVER_LICENSE"}

# ── Severity overrides by score ──
# High-confidence PERSON detections (NER, score >= 0.85) are RED.
# Lower-confidence ones (pattern-only) downgrade to YELLOW to reduce noise.
PERSON_RED_THRESHOLD = 0.85

# HIPAA clinical terms at low confidence (0.5) are YELLOW, not RED.
HIPAA_YELLOW_THRESHOLD = 0.6


def classify(entity_type, score):
    """Return 'RED', 'YELLOW', or None (skip)."""
    if entity_type in SKIP_ENTITIES:
        return None
    if entity_type == "PERSON":
        return "RED" if score >= PERSON_RED_THRESHOLD else "YELLOW"
    if entity_type == "HIPAA_IDENTIFIER":
        return "RED" if score >= HIPAA_YELLOW_THRESHOLD else "YELLOW"
    if entity_type == "MENTAL_HEALTH_DATA":
        # High-sensitivity terms alone (0.7) = YELLOW (could be prose/literature review)
        # Data + identifier combos (0.85) = RED (actual participant data)
        return "RED" if score >= 0.85 else "YELLOW"
    if entity_type == "FINANCIAL_DATA":
        return "RED" if score >= 0.7 else "YELLOW"
    if entity_type in RED_ENTITIES:
        return "RED"
    if entity_type in YELLOW_ENTITIES:
        return "YELLOW"
    # Unknown entity types default to YELLOW
    return "YELLOW"


def scan_file(file_path, output_json=False):
    # ── Opaque binary short-circuit ──
    # Stata, SPSS, parquet, hdf5, pickle, audio, video, raster images
    # store data zlib-compressed or in proprietary encodings. Reading
    # them as text gives garbage that wastes spaCy/Presidio cycles and
    # never matches anything useful. Exit fast with a YELLOW the bash
    # wrapper recognizes — the user will be prompted to choose
    # LOCAL_MODE or HALT for these files.
    ext = os.path.splitext(file_path)[1].lstrip(".").lower()
    if ext in OPAQUE_BINARY_EXTENSIONS:
        if output_json:
            print(json.dumps({
                "file": file_path,
                "red_count": 0,
                "yellow_count": 1,
                "issues": [{
                    "severity": "YELLOW",
                    "entity_type": "BINARY_FORMAT",
                    "score": 1.0,
                    "snippet": f".{ext}",
                }],
            }, indent=2))
        else:
            print(f"YELLOW: Binary format (.{ext}) — Presidio cannot inspect compressed/encoded content")
            print(f"  YELLOW: File extension '.{ext}' is opaque to text-based PII analyzers")
            print(f"  YELLOW: Recommend LOCAL_MODE: analyze via Rscript -e / python3 -c")
            print(f"  YELLOW: without transmitting row-level data to the API.")
        return 2

    # Wrap analyzer construction AND execution in a fallback guard.
    # Presidio depends on spaCy models, tldextract cache files, and
    # transient network fetches for its NER backbone; any of these can
    # fail on restricted / offline / read-only environments (e.g.,
    # sandboxed CI, airgapped servers, locked-down laptops). If the
    # scanner crashes, we want to degrade cleanly so `safety-scan.sh`
    # falls through to its regex backend rather than surface a Python
    # traceback to the user.
    #
    # The calling shell script interprets any exit code outside {0,1,2}
    # as "Presidio failed, use regex fallback" — we return 99 here.
    try:
        analyzer = build_analyzer()
    except Exception as exc:
        print(
            f"WARNING: Presidio analyzer construction failed: {type(exc).__name__}: {exc}",
            file=sys.stderr,
        )
        return 99

    # Bump spaCy's per-pipeline max_length so larger codebooks/PDFs
    # don't crash with ValueError [E088]. The default 1M-char ceiling is
    # far below what modern hardware can comfortably handle. We reach
    # into the analyzer's NLP backbone via Presidio's nlp_engine API,
    # but that API has changed across versions — wrap defensively and
    # let the truncation safety net (below) catch any version where
    # this bump silently fails.
    try:
        nlp_dict = analyzer.nlp_engine.nlp
        for engine in nlp_dict.values():
            engine.max_length = SPACY_MAX_LENGTH
    except (AttributeError, KeyError, TypeError):
        pass

    try:
        with open(file_path, "r", errors="replace") as f:
            text = f.read()
    except OSError as exc:
        print(f"ERROR: Could not read {file_path}: {exc}", file=sys.stderr)
        return 1

    # Truncation safety net: even with the max_length bump above,
    # extremely large text inputs would exhaust memory or take minutes
    # to NER. Cap at TEXT_TRUNCATION_LIMIT and warn so the user knows
    # the scan was partial. (Headers/variable names sit at the top of
    # most research files, so the front of the file is the highest-
    # information region anyway.)
    if len(text) > TEXT_TRUNCATION_LIMIT:
        print(
            f"WARNING: Truncating {file_path} from {len(text):,} to "
            f"{TEXT_TRUNCATION_LIMIT:,} chars for Presidio analysis",
            file=sys.stderr,
        )
        text = text[:TEXT_TRUNCATION_LIMIT]

    try:
        results = analyzer.analyze(
            text=text,
            language="en",
            score_threshold=0.4,
        )
    except Exception as exc:
        # tldextract cache permission errors, HTTP fetch failures, spaCy
        # model load errors all end up here. Exit 99 → regex fallback.
        print(
            f"WARNING: Presidio analyze() failed: {type(exc).__name__}: {exc}",
            file=sys.stderr,
        )
        return 99

    red_issues = []
    yellow_issues = []

    seen = set()
    for r in sorted(results, key=lambda x: -x.score):
        # Deduplicate by span
        span_key = (r.start, r.end, r.entity_type)
        if span_key in seen:
            continue
        seen.add(span_key)

        severity = classify(r.entity_type, r.score)
        if severity is None:
            continue

        snippet = text[r.start:r.end]
        # Truncate long snippets
        if len(snippet) > 60:
            snippet = snippet[:57] + "..."

        issue = {
            "severity": severity,
            "entity_type": r.entity_type,
            "score": round(r.score, 2),
            "start": r.start,
            "end": r.end,
            "snippet": snippet,
        }

        if severity == "RED":
            red_issues.append(issue)
        else:
            yellow_issues.append(issue)

    if output_json:
        result = {
            "file": file_path,
            "red_count": len(red_issues),
            "yellow_count": len(yellow_issues),
            "issues": red_issues + yellow_issues,
        }
        print(json.dumps(result, indent=2))
    else:
        if red_issues:
            print(f"RED: {len(red_issues)} critical issue(s) found — DO NOT transmit to AI without review")
        if yellow_issues:
            print(f"YELLOW: {len(yellow_issues)} issue(s) found — review before transmitting")

        for issue in red_issues + yellow_issues:
            label = issue["severity"]
            etype = issue["entity_type"]
            score = issue["score"]
            snippet = issue["snippet"]
            print(f"  {label}: {etype} (confidence: {score}) — \"{snippet}\"")

        if not red_issues and not yellow_issues:
            print("GREEN: No sensitive data patterns detected")

    # Exit code
    if red_issues:
        return 1
    elif yellow_issues:
        return 2
    else:
        return 0


def main():
    if len(sys.argv) < 2:
        print("Usage: safety-scan-presidio.py <file_path> [--json]", file=sys.stderr)
        sys.exit(1)

    file_path = sys.argv[1]
    output_json = "--json" in sys.argv

    if not os.path.isfile(file_path):
        print(f"ERROR: File not found: {file_path}", file=sys.stderr)
        sys.exit(1)

    exit_code = scan_file(file_path, output_json)
    sys.exit(exit_code)


if __name__ == "__main__":
    main()
