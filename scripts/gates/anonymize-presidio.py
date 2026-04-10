#!/usr/bin/env python3
"""
Presidio-based anonymizer for qualitative research data.
Detects PII via NER + patterns and replaces with typed pseudonyms.
Called by scholar-qual and scholar-safety when presidio-analyzer is installed.

Usage:
  python3 anonymize-presidio.py scan <file>              # Detect PII, print report
  python3 anonymize-presidio.py anonymize <file> [--out DIR]  # Anonymize and save ANON_ copy
  python3 anonymize-presidio.py keygen <file> [--out DIR]     # Generate pseudonym-key CSV from detections
  python3 anonymize-presidio.py verify <file>             # Verify anonymized file is clean

Exit codes: 0 = clean/success, 1 = PII found (scan/verify), 2 = error
"""

import sys
import os
import re
import csv
import json
from collections import Counter, defaultdict

def check_presidio():
    try:
        from presidio_analyzer import AnalyzerEngine
        from presidio_anonymizer import AnonymizerEngine
        return True
    except ImportError:
        return False


def build_analyzer():
    from presidio_analyzer import AnalyzerEngine, PatternRecognizer, Pattern

    analyzer = AnalyzerEngine()

    # Research-specific recognizers (same as safety-scan-presidio.py)
    custom_recognizers = [
        PatternRecognizer(
            supported_entity="INSTITUTION",
            name="institution_recognizer",
            patterns=[
                Pattern("institution", r"\b(University|College|Hospital|Clinic|School|Church|Academy|Institute|Center|Centre)\s+(?:of\s+)?[A-Z][a-z]+(?:\s+[A-Z][a-z]+)*\b", 0.6),
                Pattern("org_suffix", r"\b[A-Z][a-z]+(?:\s+[A-Z][a-z]+)*\s+(University|College|Hospital|Clinic|School|Church|Academy|Institute)\b", 0.6),
            ],
            supported_language="en",
        ),
        PatternRecognizer(
            supported_entity="HIPAA_IDENTIFIER",
            name="hipaa_recognizer",
            patterns=[
                Pattern("medical", r"\b(medical[\s_]?record|patient[\s_]?id|mrn|health[\s_]?plan|beneficiary)\b", 0.7),
            ],
            supported_language="en",
        ),
        PatternRecognizer(
            supported_entity="DATE_OF_BIRTH",
            name="dob_recognizer",
            patterns=[
                Pattern("dob", r"\b(date[\s_.]?of[\s_.]?birth|dob|birth[\s_.]?date)\b", 0.85),
            ],
            supported_language="en",
        ),
    ]

    for r in custom_recognizers:
        analyzer.registry.add_recognizer(r)

    return analyzer


# ── Entity type → pseudonym prefix mapping ──
ENTITY_PSEUDONYM_PREFIX = {
    "PERSON": "P",
    "LOCATION": "LOC",
    "INSTITUTION": "ORG",
    "EMAIL_ADDRESS": "[EMAIL REMOVED]",
    "PHONE_NUMBER": "[PHONE REMOVED]",
    "US_SSN": "[SSN REMOVED]",
    "CREDIT_CARD": "[CARD REMOVED]",
    "IP_ADDRESS": "[IP REMOVED]",
    "DATE_OF_BIRTH": "[DOB REMOVED]",
    "HIPAA_IDENTIFIER": "[HIPAA REMOVED]",
    "DATE_TIME": None,  # skip — too noisy for qualitative data
    "NRP": None,  # nationality/religion — skip
    "URL": None,  # skip
}

# Entities where we generate numbered pseudonyms (not fixed replacements)
NUMBERED_ENTITIES = {"PERSON", "LOCATION", "INSTITUTION"}

# Minimum confidence for each entity type
ENTITY_THRESHOLDS = {
    "PERSON": 0.6,
    "LOCATION": 0.5,
    "INSTITUTION": 0.5,
    "EMAIL_ADDRESS": 0.4,
    "PHONE_NUMBER": 0.4,
    "US_SSN": 0.4,
    "CREDIT_CARD": 0.4,
    "IP_ADDRESS": 0.4,
    "DATE_OF_BIRTH": 0.7,
    "HIPAA_IDENTIFIER": 0.6,
}


def analyze_file(file_path):
    """Run Presidio analysis on a file and return deduplicated results."""
    analyzer = build_analyzer()

    with open(file_path, "r", errors="replace") as f:
        text = f.read()

    results = analyzer.analyze(
        text=text,
        language="en",
        score_threshold=0.35,
    )

    # Deduplicate and filter
    seen = set()
    filtered = []
    for r in sorted(results, key=lambda x: -x.score):
        span_key = (r.start, r.end)
        if span_key in seen:
            continue
        seen.add(span_key)

        prefix = ENTITY_PSEUDONYM_PREFIX.get(r.entity_type)
        if prefix is None:
            continue

        threshold = ENTITY_THRESHOLDS.get(r.entity_type, 0.5)
        if r.score < threshold:
            continue

        snippet = text[r.start:r.end].strip()
        if not snippet:
            continue

        filtered.append({
            "entity_type": r.entity_type,
            "score": round(r.score, 2),
            "start": r.start,
            "end": r.end,
            "text": snippet,
        })

    return text, filtered


def cmd_scan(file_path):
    """Scan a file for PII and print a report."""
    text, detections = analyze_file(file_path)

    if not detections:
        print("GREEN: No PII detected in file.")
        return 0

    # Group by entity type
    by_type = defaultdict(list)
    for d in detections:
        by_type[d["entity_type"]].append(d)

    total = len(detections)
    print(f"PII SCAN: {total} detection(s) in {os.path.basename(file_path)}")
    print()

    for etype, items in sorted(by_type.items()):
        print(f"  {etype} ({len(items)} found):")
        # Show unique values
        unique_vals = sorted(set(d["text"] for d in items))
        for val in unique_vals[:20]:
            best_score = max(d["score"] for d in items if d["text"] == val)
            print(f"    - \"{val}\" (confidence: {best_score})")
        if len(unique_vals) > 20:
            print(f"    ... and {len(unique_vals) - 20} more")
        print()

    return 1


def cmd_keygen(file_path, out_dir):
    """Generate a pseudonym-key CSV from detections."""
    text, detections = analyze_file(file_path)

    if not detections:
        print("No PII detected — no key to generate.")
        return 0

    # Build pseudonym map: unique text → pseudonym
    counters = Counter()
    pseudonym_map = {}

    for d in detections:
        val = d["text"]
        etype = d["entity_type"]
        if val in pseudonym_map:
            continue

        prefix = ENTITY_PSEUDONYM_PREFIX.get(etype, "UNK")
        if etype in NUMBERED_ENTITIES:
            counters[etype] += 1
            pseudonym = f"{prefix}{counters[etype]:02d}"
        else:
            pseudonym = prefix  # fixed replacement like [EMAIL REMOVED]

        pseudonym_map[val] = {
            "original": val,
            "pseudonym": pseudonym,
            "type": etype.lower().replace("_", " "),
            "confidence": max(dd["score"] for dd in detections if dd["text"] == val),
            "notes": "",
        }

    os.makedirs(out_dir, exist_ok=True)
    key_path = os.path.join(out_dir, "pseudonym-key-DO-NOT-SHARE.csv")

    with open(key_path, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=["original", "pseudonym", "type", "confidence", "notes"])
        writer.writeheader()
        for entry in sorted(pseudonym_map.values(), key=lambda x: x["type"]):
            writer.writerow(entry)

    print(f"Pseudonym key written: {key_path}")
    print(f"  {len(pseudonym_map)} unique entities mapped")
    print()
    print("WARNING: This key links real identities to pseudonyms.")
    print("  - Store securely, NEVER commit to git or share via AI tools")
    print("  - Add to .gitignore: echo 'pseudonym-key-DO-NOT-SHARE.csv' >> .gitignore")
    print()
    print("REVIEW the key before anonymizing — edit pseudonyms, remove false positives,")
    print("and add any entities the NER model missed.")

    return 0


def cmd_anonymize(file_path, out_dir):
    """Anonymize a file using Presidio and save an ANON_ copy."""
    # Check for existing pseudonym key (user-edited takes priority)
    key_path = os.path.join(out_dir, "pseudonym-key-DO-NOT-SHARE.csv")
    user_key = {}

    if os.path.isfile(key_path):
        print(f"Using existing pseudonym key: {key_path}")
        with open(key_path, "r") as f:
            reader = csv.DictReader(f)
            for row in reader:
                orig = row.get("original", "").strip()
                pseudo = row.get("pseudonym", "").strip()
                if orig and pseudo:
                    user_key[orig] = pseudo

    text, detections = analyze_file(file_path)

    if not detections and not user_key:
        print("No PII detected — file appears clean. No anonymization needed.")
        return 0

    # Build replacement map: combine user key + auto-detected
    replacements = dict(user_key)  # user key takes priority
    counters = Counter()

    # Count existing numbered pseudonyms to avoid collisions
    for pseudo in replacements.values():
        for prefix in ("P", "LOC", "ORG"):
            if pseudo.startswith(prefix) and pseudo[len(prefix):].isdigit():
                counters[{"P": "PERSON", "LOC": "LOCATION", "ORG": "INSTITUTION"}[prefix]] = max(
                    counters.get({"P": "PERSON", "LOC": "LOCATION", "ORG": "INSTITUTION"}[prefix], 0),
                    int(pseudo[len(prefix):])
                )

    for d in detections:
        val = d["text"]
        if val in replacements:
            continue

        etype = d["entity_type"]
        prefix = ENTITY_PSEUDONYM_PREFIX.get(etype, "UNK")
        if etype in NUMBERED_ENTITIES:
            counters[etype] += 1
            replacements[val] = f"{prefix}{counters[etype]:02d}"
        else:
            replacements[val] = prefix

    # Sort by length (longest first) to avoid partial replacements
    sorted_replacements = sorted(replacements.items(), key=lambda x: len(x[0]), reverse=True)

    # Apply replacements
    anon_text = text
    for original, pseudonym in sorted_replacements:
        anon_text = re.sub(re.escape(original), pseudonym, anon_text, flags=re.IGNORECASE)

    # Residual scrubbing (catch anything the key/NER missed)
    anon_text = re.sub(r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}', '[EMAIL REMOVED]', anon_text)
    anon_text = re.sub(r'(\+?1[-.\s]?)?(\(?\d{3}\)?[-.\s]?)?\d{3}[-.\s]?\d{4}', '[PHONE REMOVED]', anon_text)
    anon_text = re.sub(r'\b\d{3}-\d{2}-\d{4}\b', '[SSN REMOVED]', anon_text)

    # Save
    os.makedirs(out_dir, exist_ok=True)
    out_path = os.path.join(out_dir, "ANON_" + os.path.basename(file_path))
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(anon_text)

    # Update/create key if new entities were auto-detected
    if len(replacements) > len(user_key):
        with open(key_path, "w", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=["original", "pseudonym", "type", "confidence", "notes"])
            writer.writeheader()
            for d in detections:
                if d["text"] in replacements:
                    writer.writerow({
                        "original": d["text"],
                        "pseudonym": replacements[d["text"]],
                        "type": d["entity_type"].lower().replace("_", " "),
                        "confidence": d["score"],
                        "notes": "auto" if d["text"] not in user_key else "user",
                    })
            # Add user-only entries not in detections
            detected_texts = {d["text"] for d in detections}
            for orig, pseudo in user_key.items():
                if orig not in detected_texts:
                    writer.writerow({
                        "original": orig,
                        "pseudonym": pseudo,
                        "type": "user-defined",
                        "confidence": 1.0,
                        "notes": "user",
                    })

    n_replacements = sum(1 for orig, pseudo in sorted_replacements if orig.lower() in anon_text.lower() or pseudo in anon_text)
    print(f"Anonymized: {file_path} -> {out_path}")
    print(f"  {len(replacements)} unique entities replaced")
    if not user_key:
        print(f"  Pseudonym key saved: {key_path}")
    print()
    print("NEXT: Run 'verify' to confirm no PII remains in the anonymized file.")

    return 0


def cmd_verify(file_path):
    """Re-scan an anonymized file to verify it's clean."""
    text, detections = analyze_file(file_path)

    # Filter out our own replacement markers
    real_detections = []
    for d in detections:
        snippet = d["text"]
        if snippet.startswith("[") and snippet.endswith("]"):
            continue  # skip [EMAIL REMOVED] etc.
        if re.match(r'^(P|LOC|ORG)\d{2,}$', snippet):
            continue  # skip our pseudonyms
        real_detections.append(d)

    if not real_detections:
        print(f"VERIFIED: No residual PII detected in {os.path.basename(file_path)}")
        print("  File is safe for AI processing.")
        return 0

    print(f"WARNING: {len(real_detections)} potential PII detection(s) remain in anonymized file:")
    for d in real_detections:
        print(f"  {d['entity_type']}: \"{d['text']}\" (confidence: {d['score']})")

    print()
    print("Update the pseudonym key and re-run anonymization, or confirm these are false positives.")
    return 1


def main():
    if len(sys.argv) < 3:
        print(__doc__, file=sys.stderr)
        sys.exit(2)

    command = sys.argv[1]
    file_path = sys.argv[2]

    if not os.path.isfile(file_path):
        print(f"ERROR: File not found: {file_path}", file=sys.stderr)
        sys.exit(2)

    # Parse --out DIR
    out_dir = os.path.join(os.environ.get("OUTPUT_ROOT", "output"), "qual", "anonymized")
    if "--out" in sys.argv:
        idx = sys.argv.index("--out")
        if idx + 1 < len(sys.argv):
            out_dir = sys.argv[idx + 1]

    if command == "scan":
        sys.exit(cmd_scan(file_path))
    elif command == "keygen":
        sys.exit(cmd_keygen(file_path, out_dir))
    elif command == "anonymize":
        sys.exit(cmd_anonymize(file_path, out_dir))
    elif command == "verify":
        sys.exit(cmd_verify(file_path))
    else:
        print(f"Unknown command: {command}", file=sys.stderr)
        print(__doc__, file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main()
