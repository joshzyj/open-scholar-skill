# Permission Request Templates and User Interaction Scripts

Reference for `scholar-safety` — verbatim templates for safety alerts, permission requests, and logging.

---

## 1. Full Alert Templates

### HIGH RISK Alert (Full)

```
╔══════════════════════════════════════════════════════════════════╗
║  ⛔  SCHOLAR SAFETY — HIGH SENSITIVITY ALERT                      ║
╚══════════════════════════════════════════════════════════════════╝

📁 File:      [filename]
📏 Size:      [size / line count]
🔬 Scan:      Local pattern scan (no file content was read by Claude)

Sensitive patterns detected:
  [• SSN patterns: XX matches]
  [• Health/HIPAA keywords: XX matches]
  [• Immigration/legal status: XX matches]
  [• Restricted dataset markers (NHANES/PSID/DUA): XX matches]
  [• Email addresses: XX matches]
  [• (add any others found)]

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
⚠  TRANSMISSION RISK

If Claude Code reads this file, ALL its contents will be
transmitted to Anthropic's API servers.

This may violate one or more of the following:
  ☐  HIPAA — no Business Associate Agreement (BAA) between your
     institution and Anthropic for this data
  ☐  IRB Protocol — your consent form may not cover cloud AI
     processing of participant data
  ☐  Data Use Agreement — NHANES / PSID / NLSY / IPUMS / Census
     data use agreements prohibit third-party data sharing
  ☐  GDPR — transfer of EU personal data to US servers without
     adequate safeguards (Article 46)
  ☐  Institutional Data Policy — your university IT policy may
     restrict sensitive data on cloud AI services

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
OPTIONS — Please choose one:

[A]  HALT
     Stop all operations on this file now. I will resolve
     the data handling issue (IRB amendment, DUA clarification,
     anonymization) before continuing.

[B]  ANONYMIZE
     Generate an anonymization R script I can run locally to
     produce a de-identified copy. I will re-scan the clean
     file before proceeding with analysis.

[C]  LOCAL MODE
     Proceed using Bash/R/Python scripts that output ONLY
     aggregated results (means, SDs, coefficients, tables).
     Raw data rows will never enter Claude's context.
     I accept that Claude will work from summary outputs only.

[D]  OVERRIDE (use only if this is a false positive)
     I have verified this data is NOT sensitive (e.g., the
     pattern matches are false positives). Log my decision
     and proceed. I accept full responsibility for compliance.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Your selection (A / B / C / D):
```

---

### MEDIUM RISK Advisory (Full)

```
╔══════════════════════════════════════════════════════════════════╗
║  ⚠   SCHOLAR SAFETY — CAUTION ADVISORY                           ║
╚══════════════════════════════════════════════════════════════════╝

📁 File:      [filename]
🔬 Scan:      Local pattern scan (no file content was read by Claude)

Potentially sensitive patterns found:
  [• IRB/participant markers: XX matches]
  [• De-identified data indicators: XX matches]
  [• Fine-grained geographic data: XX matches]
  [• Financial data keywords: XX matches]

⚠  Reading this file will transmit its contents to Anthropic's API.

Before proceeding, please confirm:
  ☐  Your IRB consent form covers cloud AI processing of this data
  ☐  No applicable data use agreement prohibits third-party sharing
  ☐  Data is de-identified (no direct or indirect identifiers remain)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
OPTIONS:

[Y]  PROCEED
     I confirm the above conditions are met. Continue with
     the analysis. Log this decision.

[B]  ANONYMIZE FIRST
     Generate a local anonymization script before proceeding.

[C]  LOCAL MODE
     Use Bash/R output-only scripts. No raw data in Claude's context.

[A]  HALT
     I need to verify compliance first. Stop all operations.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Your selection (Y / B / C / A):
```

---

### LOW RISK Clearance (Compact)

```
✅  SCHOLAR SAFETY GATE — CLEARED

File: [filename]
Scan: Local pattern scan — no sensitive data detected
Risk: 🟢 LOW — safe for standard Claude Code analysis

[Proceeding with operation...]
```

---

## 2. Inline Operation Gate Templates

### Before reading a data file (compact version)

```
🔐 Safety check before reading [filename]...
[Running local scan — no content transmitted during scan]

Result: [🔴 HIGH / 🟡 MEDIUM / 🟢 LOW]
[If not LOW: show full alert template above]
[If LOW: "✅ Cleared — proceeding."]
```

### Before a Bash operation with data

```
🔐 Safety check: About to run [describe bash command] on [filename]

Does this command read raw data into Claude's context?
  • grep -c (count only) → SAFE ✓
  • Rscript summary() → SAFE ✓
  • cat / head / tail → READS FILE ⚠
  • awk '{print}' → READS FILE ⚠
  • Rscript with print(data[1:5,]) → READS ROWS ⚠

[If READS FILE: run sensitivity scan first, then apply appropriate protocol]
[If SAFE: proceed]
```

---

## 3. Post-Selection Response Templates

### After user selects [A] HALT

```
⛔  HALT confirmed.

All operations on [filename] are suspended.

Recommended next steps:
1. Review your IRB protocol — does the consent form cover
   cloud AI processing? If not, submit an amendment.
2. Review your data use agreement — check section on
   "third-party sharing" and "computational services."
3. Contact your IRB coordinator: [your institution's contact]
4. Consider anonymization or the local-mode workflow.

When you are ready to proceed, re-invoke:
  /scholar-safety scan [filename]      ← re-check the file
  /scholar-safety protocol [project]  ← build a full safety plan
```

### After user selects [B] ANONYMIZE

```
📋  Generating anonymization script for [filename]...

[Generate and output the R anonymization script from SKILL.md]

Steps for you to follow:
1. Save the script above to: scripts/anonymize_[filename].R
2. Run it locally: Rscript scripts/anonymize_[filename].R
3. Verify the output file: data/anonymized/[filename]_anon.csv
4. Re-scan the anonymized file:
   /scholar-safety scan data/anonymized/[filename]_anon.csv
5. If cleared, re-invoke the original skill on the clean file.

⚠  Important: Never overwrite your raw data file.
   Keep the original in a secure, restricted-access location.
```

### After user selects [C] LOCAL MODE

```
🔒  Local Mode activated for [filename].

In Local Mode:
  • Claude Code will NOT read [filename] directly
  • All data operations run locally via Bash/R/Python
  • Only aggregated outputs (statistics, model results) enter Claude's context
  • You will paste model output, summary tables, and figure descriptions

Here are the local-mode scripts for your analysis:

[Generate appropriate R/Python/Stata scripts based on what the
 user was trying to do — e.g., if running EDA, generate:
 summary stats, distribution checks, Table 1 via gtsummary;
 all with print() output that can be pasted back]

Paste the output of these scripts back here and I will
proceed with the analysis, writing, and visualization.
```

### After user selects [D] OVERRIDE / [Y] PROCEED

```
📝  User override logged.

[Log entry written to output/[slug]/logs/scholar-safety-log.md]

Entry:
  File: [filename]
  Risk detected: [level]
  Patterns found: [list]
  User decision: OVERRIDE / PROCEED
  Timestamp: [timestamp]
  Reason stated: [if user provided a reason]
  Responsibility: User has accepted full compliance responsibility.

[Proceeding with original operation...]
```

---

## 4. Safety Log Format

```markdown
# Scholar Safety Log
Project: [name]
Started: [date]

---

## Entry [N] — [YYYY-MM-DD HH:MM]

| Field | Value |
|-------|-------|
| File | [path] |
| Operation | [describe: Read / Bash analysis / scholar-eda / etc.] |
| Scan method | Local grep/awk (no content in Claude context) |
| Risk level | 🔴 HIGH / 🟡 MEDIUM / 🟢 LOW |
| Patterns found | [list with counts] |
| User decision | [A: HALT / B: ANONYMIZE / C: LOCAL / D: OVERRIDE / Y: PROCEED] |
| Reason (if override) | [user's stated reason] |
| Follow-up action | [anonymization script generated / local scripts provided / halted] |

---

## Entry [N+1] — [YYYY-MM-DD HH:MM]
...
```

---

Proceeding to Phase 0 (Idea Exploration)...

Safety gate log written to: output/[slug]/logs/scholar-safety-log.md
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## 6. Journal-Specific Safety Disclosure Prompts

After completing the safety gate, remind the user of the disclosure they'll need to make:

```
📋  DISCLOSURE REMINDER for [journal]:

Based on your safety decisions, you will need to include the
following in your manuscript submission:

[If any AI tool was used for code generation:]
  → Methods note: "Code for data analysis was generated with
    assistance from Claude Code (Anthropic). No participant data
    was transmitted to AI servers; only anonymized outputs were used."

[If local LLM was used for text analysis:]
  → Methods note: "Interview data were coded using a locally-deployed
    large language model (Llama 3.2 via Ollama) to prevent transmission
    of sensitive participant data to external servers."

[If extract-only mode was used for restricted data:]
  → Methods note: "Data analysis was conducted on restricted-use
    files per the data use agreement. AI-assisted code generation
    used only variable names and code structure, not participant data."

[If AI tools were not used on any sensitive data:]
  → "The authors used [tool] for [task]. No participant data were
    processed by AI services."

Save this disclosure to your scholar-ethics report:
  /scholar-ethics ai-audit for [journal]
```

---

## 7. IRB Amendment Template (if needed after safety scan)

If the safety gate determines that IRB consent language does not cover AI processing, use this to request an amendment:

```
SUBJECT: IRB Amendment Request — Addition of AI-Assisted Analysis
TO: IRB Coordinator / IRB Chair
Protocol #: [number]

We are requesting a minor amendment to include AI-assisted
data analysis in our approved protocol.

PROPOSED CHANGE:
We propose to use Claude Code (Anthropic, Inc.) to generate
data analysis scripts. Only [describe what data: de-identified
variable names / aggregate statistics / model code] will be
processed by the AI service. No individual participant data
or personally identifiable information will be transmitted.

JUSTIFICATION:
This change involves minimal additional risk to participants
as no personal data is shared with the AI service. The use
is limited to [code generation / grammar editing / literature
summarization] and does not alter the study design, recruitment,
or data collection procedures.

CONSENT LANGUAGE TO ADD (if any participant data is shared):
"Your de-identified responses may be analyzed using AI-assisted
computational tools. These tools process aggregated, de-identified
data only. No personally identifying information is shared with
AI services."
```
