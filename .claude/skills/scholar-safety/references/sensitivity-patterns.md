# Sensitivity Pattern Library

Reference for `scholar-safety` MODE 1 — local grep/awk patterns for detecting sensitive data without reading file content into AI context.

**Usage rule:** All patterns below are run via `Bash grep -c` (count only). The actual matching values are NEVER returned — only the integer count. This keeps sensitive data local.

---

## 1. Direct Personal Identifiers (HIPAA Tier 1)

These patterns flag the most dangerous identifiers. Any match → 🔴 HIGH risk.

```bash
# Social Security Numbers
grep -cEi '\b[0-9]{3}-[0-9]{2}-[0-9]{4}\b' "$FILE"
grep -cEi '\b(SSN|social.?security.?number)\b' "$FILE"

# Full names (column headers or embedded)
grep -cEi '\b(first.?name|last.?name|full.?name|given.?name|family.?name|surname)\b' "$FILE"
grep -cEi '\b(respondent.?name|participant.?name|subject.?name|interviewee.?name)\b' "$FILE"

# Email addresses
grep -cEi '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,6}' "$FILE"

# Phone numbers (US and international)
grep -cEi '\b(\+?1[-.\s]?)?(\([0-9]{3}\)|[0-9]{3})[-.\s][0-9]{3}[-.\s][0-9]{4}\b' "$FILE"
grep -cEi '\b\+[1-9][0-9]{6,14}\b' "$FILE"    # International format

# Street addresses
grep -cEi '\b[0-9]{1,5}\s[A-Za-z]+(St\.?|Street|Ave\.?|Avenue|Blvd\.?|Boulevard|Dr\.?|Drive|Rd\.?|Road|Ln\.?|Lane|Way|Ct\.?|Court|Pl\.?|Place)\b' "$FILE"

# US ZIP codes (standalone, not part of a larger number)
grep -cPi '(?<!\d)\d{5}(?:-\d{4})?(?!\d)' "$FILE" 2>/dev/null || \
  grep -cEi '\bzip.?code\b|\bpostal.?code\b' "$FILE"

# Dates of birth
grep -cEi '\b(date.?of.?birth|dob|birth.?date|birthdate)\b' "$FILE"
grep -cEi '\b(born.?on|birth.?year)\b' "$FILE"

# Medical record / patient numbers
grep -cEi '\b(medical.?record.?number|MRN|patient.?ID|patient.?number|health.?plan.?number)\b' "$FILE"

# Device / biometric identifiers
grep -cEi '\b(device.?ID|MAC.?address|IMEI|fingerprint|biometric|facial.?recognition)\b' "$FILE"

# IP addresses
grep -cEi '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b' "$FILE"

# URLs with potential user identifiers
grep -cEi '\b(user.?ID|account.?ID|profile.?ID|user.?token|session.?ID)\b' "$FILE"
```

---

## 2. Health and Clinical Data (HIPAA PHI)

Any match → 🔴 HIGH risk.

```bash
# HIPAA keywords
grep -cEi '\b(HIPAA|PHI|protected.?health.?information|covered.?entity|business.?associate)\b' "$FILE"

# Clinical and medical terms
grep -cEi '\b(diagnosis|diagnos[ei]s|ICD.?[0-9]|CPT.?code|SNOMED|LOINC)\b' "$FILE"
grep -cEi '\b(medical.?record|clinical.?note|lab.?result|test.?result|biopsy|pathology)\b' "$FILE"
grep -cEi '\b(hospital|clinic|physician|doctor|nurse|patient|inpatient|outpatient|ER|ICU)\b' "$FILE"
grep -cEi '\b(medication|prescription|drug.?name|dosage|treatment|therapy|procedure)\b' "$FILE"
grep -cEi '\b(HIV|AIDS|cancer|diabetes|hypertension|heart.?disease|kidney.?disease)\b' "$FILE"
grep -cEi '\b(disability|chronic.?illness|terminal|palliative|hospice)\b' "$FILE"

# Mental health
grep -cEi '\b(depression|anxiety|bipolar|schizophrenia|PTSD|OCD|ADHD|autism)\b' "$FILE"
grep -cEi '\b(mental.?health|psychiatric|psycholog|therapy|therapist|counseling|counselor)\b' "$FILE"
grep -cEi '\b(suicid|self.?harm|self.?injur|eating.?disorder|anorexia|bulimia)\b' "$FILE"
grep -cEi '\b(substance.?use|drug.?use|alcohol.?use|addiction|overdose|rehab)\b' "$FILE"

# Reproductive health
grep -cEi '\b(pregnancy|pregnant|abortion|miscarriage|fertility|reproductive|contracepti)\b' "$FILE"

# Genetic information
grep -cEi '\b(genetic|DNA|RNA|genome|genomic|BRCA|hereditary|mutation)\b' "$FILE"
```

---

## 3. Legal and Immigration Status

Any match → 🔴 HIGH risk (severe participant harm potential).

```bash
# Immigration status
grep -cEi '\b(undocumented|illegal.?alien|unauthorized.?immigrant|immigration.?status)\b' "$FILE"
grep -cEi '\b(visa.?status|visa.?type|visa.?holder|H1B|F1.?visa|OPT|DACA|asylum|refugee)\b' "$FILE"
grep -cEi '\b(deportation|removal.?order|ICE|immigration.?enforcement|detained)\b' "$FILE"
grep -cEi '\b(naturalized|citizenship.?status|green.?card|permanent.?resident|LPR)\b' "$FILE"

# Criminal/legal history
grep -cEi '\b(criminal.?record|arrest|conviction|felony|misdemeanor|probation|parole)\b' "$FILE"
grep -cEi '\b(incarcerated|imprisoned|prison|jail|correctional|offender|inmate)\b' "$FILE"
grep -cEi '\b(sex.?offender|restraining.?order|domestic.?violence.?victim)\b' "$FILE"
```

---

## 4. Restricted / Licensed Dataset Markers

Any match → 🔴 HIGH risk (DUA violation potential).

```bash
# Common restricted datasets
grep -cEi '\b(NHANES|NHIS|MEPS|National.?Health.?Interview|Behavioral.?Risk.?Factor)\b' "$FILE"
grep -cEi '\b(PSID|Panel.?Study.?Income.?Dynamics)\b' "$FILE"
grep -cEi '\b(NLSY|National.?Longitudinal.?Survey)\b' "$FILE"
grep -cEi '\b(IPUMS|Minnesota.?Population.?Center)\b' "$FILE"
grep -cEi '\b(Census.?RDC|Federal.?Statistical.?Research.?Data.?Center|Restricted.?Use.?File)\b' "$FILE"
grep -cEi '\b(Add.?Health|National.?Longitudinal.?Study.?Adolescent)\b' "$FILE"
grep -cEi '\b(SIPP|Survey.?Income.?Program.?Participation)\b' "$FILE"
grep -cEi '\b(ACS.?PUMS|Current.?Population.?Survey|American.?Community.?Survey)\b' "$FILE"
grep -cEi '\b(Medicare|Medicaid|CMS.?data|claims.?data|administrative.?records)\b' "$FILE"
grep -cEi '\b(tax.?records|IRS.?data|W-?2|1040|earnings.?record|Social.?Security.?earnings)\b' "$FILE"

# DUA markers
grep -cEi '\b(data.?use.?agreement|DUA|restricted.?use|confidential.?data|not.?for.?distribution)\b' "$FILE"
grep -cEi '\b(do.?not.?share|proprietary|licensed.?data|access.?restricted)\b' "$FILE"
```

---

## 5. IRB / Research Participant Markers

Multiple matches combined with other flags → 🔴 HIGH; alone → 🟡 MEDIUM.

```bash
# Participant/subject identifiers
grep -cEi '\b(participant|respondent|subject|interviewee|informant)\b' "$FILE"
grep -cEi '\b(participant.?ID|respondent.?ID|subject.?ID|case.?ID|record.?ID|survey.?ID)\b' "$FILE"
grep -cEi '\b(consent|IRB|institutional.?review|human.?subjects|ethics.?approval)\b' "$FILE"
grep -cEi '\b(anonymized|de.?identified|pseudonym|masked|blinded)\b' "$FILE"  # → suggests WERE identifiable

# Interview data markers
grep -cEi '\b(transcript|verbatim|field.?note|fieldnote|ethnograph|observation)\b' "$FILE"
grep -cEi '\b(quote|quotation|said.?that|told.?us|mentioned.?that|expressed.?that)\b' "$FILE"
```

---

## 6. Financial Data

Match → 🟡 MEDIUM (higher risk if combined with identifiers → 🔴).

```bash
# Financial identifiers
grep -cEi '\b(account.?number|routing.?number|bank.?account|credit.?card|debit.?card)\b' "$FILE"
grep -cEi '\b(IBAN|SWIFT|ABA.?routing|financial.?account)\b' "$FILE"

# Income/earnings (sensitive but common in social science)
grep -cEi '\b(income|earnings|salary|wage|compensation|annual.?pay)\b' "$FILE"
grep -cEi '\b(net.?worth|assets|wealth|poverty|below.?poverty)\b' "$FILE"
```

---

## 7. Fine-Grained Geographic Data

High precision geography can enable re-identification → 🟡 MEDIUM (with other flags → 🔴).

```bash
# GPS coordinates
grep -cEi '\b(latitude|longitude|lat|lon|gps|coordinate|geolocation|geocode)\b' "$FILE"
grep -cEi '[-+]?[0-9]{1,3}\.[0-9]{4,}' "$FILE"   # decimal degrees (4+ decimal places)

# Small-area geography
grep -cEi '\b(census.?tract|block.?group|census.?block|FIPS.?code)\b' "$FILE"
grep -cEi '\b(neighborhood|address|exact.?location|home.?address|residence)\b' "$FILE"
```

---

## 8. Sexual Orientation and Gender Identity

Any match (especially linked to individuals) → 🔴 HIGH (heightened sensitivity; discrimination risk).

```bash
grep -cEi '\b(sexual.?orientation|LGBTQ|LGBT|gay|lesbian|bisexual|queer|transgender)\b' "$FILE"
grep -cEi '\b(gender.?identity|non.?binary|gender.?nonconforming|gender.?dysphoria)\b' "$FILE"
grep -cEi '\b(coming.?out|closeted|same.?sex|same-sex.?partner)\b' "$FILE"
```

---

## 9. Religious and Political Beliefs

Match → 🟡 MEDIUM (may enable discrimination in some contexts).

```bash
grep -cEi '\b(religion|religious|church|mosque|synagogue|temple|faith|denomination)\b' "$FILE"
grep -cEi '\b(political.?party|party.?affiliation|republican|democrat|libertarian|communist)\b' "$FILE"
grep -cEi '\b(political.?belief|ideology|radical|extremist|activist)\b' "$FILE"
```

---

## 10. Pattern Aggregation: Risk Scoring Function

```bash
#!/bin/bash
# Run this full scan and compute composite risk score
FILE="$1"

score=0
flags=""

SSN=$(grep -cEi '\b[0-9]{3}-[0-9]{2}-[0-9]{4}\b|\bSSN\b' "$FILE" 2>/dev/null); [ "$SSN" -gt 0 ] && score=$((score+100)) && flags="$flags SSN($SSN)"
EMAIL=$(grep -cEi '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' "$FILE" 2>/dev/null); [ "$EMAIL" -gt 5 ] && score=$((score+80)) && flags="$flags email($EMAIL)"
HEALTH=$(grep -cEi '\b(diagnosis|ICD|patient|PHI|HIPAA|clinical)\b' "$FILE" 2>/dev/null); [ "$HEALTH" -gt 0 ] && score=$((score+90)) && flags="$flags health($HEALTH)"
MENTAL=$(grep -cEi '\b(suicid|self.?harm|psychiatric|mental.?health)\b' "$FILE" 2>/dev/null); [ "$MENTAL" -gt 0 ] && score=$((score+90)) && flags="$flags mental($MENTAL)"
LEGAL=$(grep -cEi '\b(undocumented|immigration.?status|criminal.?record|incarcerated)\b' "$FILE" 2>/dev/null); [ "$LEGAL" -gt 0 ] && score=$((score+95)) && flags="$flags legal($LEGAL)"
DUA=$(grep -cEi '\b(NHANES|PSID|NLSY|IPUMS|restricted.?use|DUA)\b' "$FILE" 2>/dev/null); [ "$DUA" -gt 0 ] && score=$((score+85)) && flags="$flags restricted($DUA)"
IRB=$(grep -cEi '\b(participant|respondent|consent)\b' "$FILE" 2>/dev/null); [ "$IRB" -gt 20 ] && score=$((score+30)) && flags="$flags irb-markers($IRB)"
GEO=$(grep -cEi '\b(latitude|longitude|census.?tract|geocode)\b' "$FILE" 2>/dev/null); [ "$GEO" -gt 0 ] && score=$((score+40)) && flags="$flags geo($GEO)"
FINANCIAL=$(grep -cEi '\b(account.?number|routing.?number|credit.?card)\b' "$FILE" 2>/dev/null); [ "$FINANCIAL" -gt 0 ] && score=$((score+60)) && flags="$flags financial($FINANCIAL)"
PHONE=$(grep -cEi '\b[0-9]{3}[-.\s][0-9]{3}[-.\s][0-9]{4}\b' "$FILE" 2>/dev/null); [ "$PHONE" -gt 5 ] && score=$((score+70)) && flags="$flags phone($PHONE)"
LGBTQ=$(grep -cEi '\b(sexual.?orientation|LGBTQ|transgender|gender.?identity)\b' "$FILE" 2>/dev/null); [ "$LGBTQ" -gt 0 ] && score=$((score+50)) && flags="$flags lgbtq($LGBTQ)"

if [ "$score" -ge 80 ]; then
  RISK="🔴 HIGH"
elif [ "$score" -ge 30 ]; then
  RISK="🟡 MEDIUM"
else
  RISK="🟢 LOW"
fi

echo "RISK: $RISK (score=$score)"
echo "FLAGS: $flags"
```

---

## 11. False Positive Management

Common false positives to handle:

| Pattern | Common false positive | How to distinguish |
|---------|----------------------|-------------------|
| Email regex | Equations like `a@b` in code | Require `.com/.edu/.org` TLD; count > 5 |
| Phone regex | Version numbers `3.14.159` | Require separator pattern `xxx-xxx-xxxx` |
| ZIP code | Any 5-digit number | Check if in address context; use zip column name |
| Latitude | Any decimal like `0.4567` | Require 4+ decimal places AND lat/lon column header |
| NHANES | Citation of NHANES | Usually OK if in manuscript text only; check if it's a data file |
| "Patient" | Academic writing about patients | If in .csv/.dta file, likely real data |
| SSN-like | ID codes `123-45-6789` | Flag all; user confirms |

**When NOT to flag:**
- Manuscript text files (`.txt`, `.docx`, `.md`) containing no tabular data: reduce false positive rate by 80%
- Files named `code.R`, `analysis.R`, `clean.py` etc.: code files; flag only if data values are embedded
- Bibliography files (`.bib`): skip entirely
