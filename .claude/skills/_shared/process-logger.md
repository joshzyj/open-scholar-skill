# Process Logging Protocol

Every `/scholar-*` skill run MUST produce a process log that captures all steps, decisions, and outputs as a reviewable audit trail.

---

## START — Initialize Process Log

At the **very beginning** of the skill run (after parsing arguments), execute:

```
Set SKILL_NAME to the current skill name (e.g., "scholar-eda")
Set LOG_DATE to today's date as YYYY-MM-DD
Set LOG_FILE to "${OUTPUT_ROOT}/logs/process-log-${SKILL_NAME}-${LOG_DATE}.md"
```

Create the logs directory if it does not exist:
```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
mkdir -p "${OUTPUT_ROOT}/logs"
```

Write the log header:

```markdown
# Process Log: /[SKILL_NAME]
- **Date**: [LOG_DATE]
- **Time started**: [HH:MM:SS]
- **Arguments**: [raw arguments passed to the skill]
- **Working Directory**: [pwd]
- **Git Branch**: [current branch, if in a git repo]

## Steps

| # | Timestamp | Step | Action | Output | Status |
|---|-----------|------|--------|--------|--------|
```

---

## STEP — Append After Every Numbered Step

**IMPORTANT:** Shell variables do NOT persist across separate Bash tool calls in Claude Code. You MUST re-derive `LOG_FILE` before every append.

After completing **each numbered step** in the skill workflow, append one row to the Steps table in the log file:

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
SKILL_NAME="scholar-XXXX"
LOG_DATE=$(date +%Y-%m-%d)
LOG_FILE="${OUTPUT_ROOT}/logs/process-log-${SKILL_NAME}-${LOG_DATE}.md"
# If a counter was used during init, find the latest log file for today:
if [ ! -f "$LOG_FILE" ]; then
  LOG_FILE=$(ls -t "${OUTPUT_ROOT}"/logs/process-log-${SKILL_NAME}-${LOG_DATE}*.md 2>/dev/null | head -1)
fi
echo "| [step#] | $(date +%H:%M:%S) | [Step Name] | [1-line action summary] | [output files or —] | ✓ |" >> "$LOG_FILE"
```

Guidelines:
- **Step ID**: Use the skill's own step identifiers (e.g., "A0 — Parse Arguments", "Step 3 — Run Models")
- **Action**: Keep to one concise line describing what happened (e.g., "Loaded data.csv (N=5,234, 42 vars)", "OLS M1-M3 with HC3 SEs")
- **Output**: List any files saved in this step; use `—` if none
- **Status**: `✓` for success, `✗` for failure/error (with brief note)

If a step fails or is skipped, still log it with status `✗` or `SKIPPED` and a brief reason.

---

## END — Close Process Log

At the **very end** of the skill run (in the Save Output section), re-derive `LOG_FILE` and append the closing blocks:

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
SKILL_NAME="scholar-XXXX"
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

## Notes

- If the skill is run multiple times on the same day, append a counter: `process-log-scholar-eda-2026-03-05-2.md`
- The log file itself should NOT appear in the "Output Files" list
- For orchestrator skills that call sub-skills, log each phase as a step; sub-skills produce their own logs
- **Shell variables do NOT persist** across separate Bash tool calls in Claude Code. Every append block MUST re-derive `SKILL_NAME`, `LOG_DATE`, and `LOG_FILE`.
