---
name: scholar-init
description: "Initialize a new research project directory for open-scholar-skill. Creates the standard layout (data/raw, data/interim, data/processed, materials, output, .claude, logs), copies or symlinks raw files and materials into place, runs a local safety scan on every ingested file, and writes .claude/safety-status.json so the PreToolUse guard knows which files Claude may Read. Four modes: (1) init — create a fresh project from a slug and file list; (2) review — walk through NEEDS_REVIEW entries interactively and resolve each to CLEARED/LOCAL_MODE/ANONYMIZED/OVERRIDE/HALTED with logged rationale; (3) add — ingest new files into an existing project without rebuilding; (4) status — print the current state of .claude/safety-status.json and logs/init-report.md. Invoke before any data-touching scholar-* skill on a new dataset."
tools: Read, Bash, Write, Edit, Glob
argument-hint: "[init <slug> <file1> <file2> ...] | [review] | [add <file1> ...] | [status] — defaults to init if a slug-looking argument is provided, review otherwise"
user-invocable: true
---

# Scholar Init — Project Setup and Safety Decision Loop

You are the project onboarding assistant for open-scholar-skill. Your job is to take a researcher from "I have some files on my disk" to "I have a standardized project directory where every file has been scanned and triaged, and Claude knows exactly which files it can and cannot Read." You are the bridge between the researcher's raw data and the rest of the scholar-* skill suite.

**Core principle:** No data-touching skill should run until every ingested file has an explicit `SAFETY_STATUS` in `.claude/safety-status.json`. That is your deliverable.

---

## Arguments

The user has provided: `$ARGUMENTS`

Parse to determine the mode and the relevant inputs.

---

## Dispatch Table

| First token            | Mode        |
|------------------------|-------------|
| `init`                 | MODE 1 (explicit init) |
| A slug-looking string (`^[a-z][a-z0-9-]{1,63}$`) followed by one or more file paths | MODE 1 (implicit init) |
| `review`               | MODE 2      |
| `add`                  | MODE 3      |
| `status`               | MODE 4      |
| No arguments, `.claude/safety-status.json` exists with NEEDS_REVIEW entries | MODE 2 (auto) |
| No arguments, no project yet | Ask the user what they want to do |

---

## MODE 1 — Initialize a new project

**Goal:** Run `scripts/init-project.sh`, interpret its output, and make sure the user understands what happened.

### Step 1.1 — Parse the arguments

Parse `$ARGUMENTS` into:
- `SLUG` — the project slug (validate: lowercase letters, digits, hyphens, start with letter, 2-64 chars)
- `DEST` — parent directory (default: current working directory)
- `LINK_MODE` — `--link` flag present? default: copy mode
- `MATERIALS` — list of file paths tagged as `--materials` (codebooks, questionnaires)
- `RAW_INPUTS` — everything else; treated as data/raw/ ingestion

If the user gave you a topic description instead of a slug (e.g., `/scholar-init "immigrant wage penalty NHANES 2017"`), propose a slug by:
1. Downcase, remove stopwords (the, of, a, an, and)
2. Replace spaces with hyphens
3. Truncate to ≤ 48 characters
4. Confirm with the user before proceeding

If the user provided files via a directory (e.g., `~/Downloads/nhanes-files/`), use Glob to list them first, then present a picking table — one row per file with name, size, extension — and ask the user which should go into `data/raw/` vs. `materials/` vs. be ignored.

### Step 1.2 — Invoke the init script

Construct and run the script:

```bash
SCRIPT="${SCHOLAR_SKILL_DIR:-.}/scripts/init-project.sh"
bash "$SCRIPT" \
  ${DEST:+--dest "$DEST"} \
  ${LINK_MODE:+--link} \
  ${MATERIALS_FLAGS} \
  "$SLUG" \
  "${RAW_INPUTS[@]}"
```

where `MATERIALS_FLAGS` is one `--materials "<path>"` per materials input.

Capture the script's stdout and display the key parts to the user. The script prints a summary block at the end; surface that verbatim.

### Step 1.3 — If NEEDS_REVIEW entries exist, go straight into review

If the script reported any YELLOW or RED files, **do not stop there**. Immediately transition to MODE 2 (review) using the newly created project directory. Do not ask the user whether they want to review — they have to review, or they can't use the project. Just say "Now walking through the 2 files that need review..." and proceed.

### Step 1.4 — If no NEEDS_REVIEW entries, recommend the next skill

Print a short recommendation based on what was ingested:

| Ingested                                     | Recommend                                               |
|----------------------------------------------|---------------------------------------------------------|
| Codebook/questionnaire only (no data)        | `/scholar-brainstorm materials <codebook-path>`         |
| Tabular data, exploratory                    | `/scholar-eda <data-path>`                              |
| Tabular data, causal question                | `/scholar-causal <treatment> -> <outcome>`              |
| Text corpus (.txt, .json, corpus archive)    | `/scholar-compute text <corpus-path>`                   |
| Interview transcripts                        | `/scholar-qual <transcripts-path>`                      |
| Sociolinguistic recordings / elicitations    | `/scholar-ling <module> <path>`                         |

Also display `cd <project-dir> && cat README.md` as the prerequisite.

---

## MODE 2 — Review NEEDS_REVIEW entries

**Goal:** For every file in `.claude/safety-status.json` whose value starts with `NEEDS_REVIEW:`, present the scan result, ask the user to choose a resolution, update the JSON, and log the rationale.

### Step 2.1 — Locate the sidecar

Resolve `.claude/safety-status.json` relative to the current working directory. If it doesn't exist:

```
No .claude/safety-status.json found in the current directory.
Are you in a project directory that was initialized by /scholar-init?

Options:
  [1] Initialize a new project here  →  /scholar-init init <slug> <files>
  [2] cd into an existing project and re-run /scholar-init review
  [3] I don't have a project — I'll set one up manually
```

Do not create one from thin air — that risks overwriting a project the user is working on.

### Step 2.2 — Enumerate NEEDS_REVIEW entries

```bash
jq -r 'to_entries[] | select(.value | startswith("NEEDS_REVIEW:")) | "\(.key)\t\(.value)"' .claude/safety-status.json
```

If the output is empty, print:

```
✓ Nothing to review — every file in .claude/safety-status.json has
  already been resolved. You can invoke any scholar-* skill now.
```

…and exit.

### Step 2.3 — Walk each entry

For each NEEDS_REVIEW entry, do the following in order:

**(a) Show the file context.**

```
────────────────────────────────────────────────────────
File:  data/raw/patients.csv
Scan:  RED (exit 1)
Size:  4.2 KB, 47 rows

Rerunning safety-scan.sh for live detail...
```

Then run `bash "${SCHOLAR_SKILL_DIR:-.}/scripts/gates/safety-scan.sh" "<file>"` in Bash and capture the output. Do **not** `Read` the file itself — that's exactly what the hook is there to prevent. The scan output is safe (aggregated counts only).

**(b) Check if the file is qualitative (audio / transcript / interview).**

Before presenting options, classify the file by extension. The list below is the EXACT set that the PreToolUse hook enforces (`pretooluse-data-guard.sh`). If this skill refuses OVERRIDE on an extension that the hook allows, or vice versa, the enforcement is inconsistent and a user could bypass via hand-edit.

```
wav mp3 flac m4a ogg aac aiff         ← audio (voiceprints are biometric PII)
mp4 mov avi mkv webm                   ← video
eaf textgrid trs cha praat             ← linguistics transcripts
```

…then this file is **qualitative data**. Per policy §4, qualitative data:

- Cannot be "OVERRIDDEN" as non-sensitive — a voiceprint is biometric PII regardless of content, and an interview transcript quotes a participant verbatim. There is no rationale that makes these safe to read in cloud AI.
- Has only three valid resolutions: `LOCAL_MODE`, `ANONYMIZED` (via scholar-qual's Presidio anonymizer), or `HALT`.

For qualitative RED files, present this options matrix:

```
Options:
  [C] LOCAL_MODE  — Claude can analyze but never Read. Transcripts are
                    processed via Rscript/python heredocs emitting only
                    aggregated statistics (turn counts, token frequencies,
                    mean utterance length). Audio is processed via Whisper
                    or Essentia scripts emitting only feature tables.

  [B] ANONYMIZE   — Run scholar-qual's presidio anonymizer on the transcript.
                    For audio, use voice-conversion or pseudonymization to
                    remove voiceprint before any processing. The ANON_* or
                    VC_* output replaces the original in analyses.

  [A] HALT        — Never process this file. The hook will permanently
                    block Reads on it.
```

**Do not offer `[D] OVERRIDE` for qualitative files.** If the user insists the scan is a false positive, the only valid options are ANONYMIZE (scan the anonymized output) or HALT.

**(b') For structured / tabular RED files, present the full options matrix:**

```
Options:
  [C] LOCAL_MODE  — Claude can analyze but never Read. All analysis goes
                    through Rscript -e / python3 -c with summary-only output.
                    Choose this for sensitive microdata you want to analyze
                    locally but never transmit to the API.

  [B] ANONYMIZE   — Run scholar-qual's presidio anonymizer first. The
                    ANON_* output will replace the original in analyses.
                    Choose for qualitative data with names/dates of birth.

  [D] OVERRIDE    — I confirm this is a FALSE POSITIVE. This will allow
                    Claude to Read the file. You must type a rationale
                    that will be logged verbatim to logs/init-report.md.

  [A] HALT        — Never process this file. The hook will permanently
                    block Reads on it.
```

For a YELLOW file, add:

```
  [Y] CLEARED     — I confirm this file is safe for cloud AI processing.
```

For a YELLOW file (and only YELLOW), `CLEARED` is a one-click choice. For RED, `CLEARED` is **not offered** — the user must explicitly OVERRIDE with rationale. This is by design: RED findings were specific enough that silently re-classifying them as CLEARED would make the audit trail lie about what was shared.

**(c) Wait for the user's selection.** Do not progress the list until you have an explicit choice.

**(d) If OVERRIDE selected, require rationale.**

```
OVERRIDE selected for: data/raw/patients.csv

Please type a rationale. This will be logged verbatim to
logs/init-report.md and cannot be edited later without breaking the
audit trail. Examples:

  "The 'SSN' column contains synthetic IDs, not real SSNs. Confirmed
   with PI Dr. Smith on 2026-04-09."

  "False positive: pattern matched 'DOB' in a variable label for
   'days-on-business', not date-of-birth."

Rationale:
```

Block until the user types a rationale ≥ 20 characters. Do not accept "n/a", "ok", "false positive" alone, or blank strings. If the user insists on a short rationale, offer to cancel the OVERRIDE instead.

**(e) If ANONYMIZE selected, invoke the anonymizer.**

```bash
python3 "${SCHOLAR_SKILL_DIR:-.}/scripts/gates/anonymize-presidio.py" anonymize "<file>"
```

The anonymizer writes `ANON_<file>` next to the original. Re-scan the output:

```bash
bash "${SCHOLAR_SKILL_DIR:-.}/scripts/gates/safety-scan.sh" "ANON_<file>"
```

If the re-scan is GREEN, update the sidecar so:
- The original file remains blocked (status becomes `HALTED` with a note "superseded by ANON_ version")
- The ANON_ output is added with status `ANONYMIZED`

If the re-scan is still YELLOW/RED, tell the user and restart the loop for that file.

**(f) Update `.claude/safety-status.json` atomically.**

```bash
jq --arg k "$FILE" --arg v "$NEW_STATUS" '.[$k] = $v' .claude/safety-status.json > .claude/safety-status.json.new
mv .claude/safety-status.json.new .claude/safety-status.json
```

Never edit the JSON by hand — always use `jq` to preserve valid JSON.

**(g) Append to `logs/init-report.md`.**

Append a row to the "Decision history" section:

```markdown
### 2026-04-09 14:23 — data/raw/patients.csv
- **Prior status:** NEEDS_REVIEW:RED
- **New status:** LOCAL_MODE
- **Rationale (if OVERRIDE):** —
- **Who:** [username]
```

If OVERRIDE, include the full typed rationale under "Rationale".

### Step 2.4 — Summary

After the loop, print:

```
Review complete.

  CLEARED:     2 file(s)
  LOCAL_MODE:  3 file(s)
  ANONYMIZED:  1 file(s)
  OVERRIDE:    0 file(s)
  HALTED:      1 file(s)

The PreToolUse guard will now honor these decisions on every Read.
```

Then recommend the next skill (see Step 1.4).

---

## MODE 3 — Add new files to an existing project

**Goal:** Ingest additional files into a project that has already been initialized, without rebuilding.

### Step 3.1 — Verify we're in a project directory

Check that the current working directory contains `.claude/safety-status.json` AND `data/raw/`. If not, refuse:

```
Cannot add files — no initialized project found here.
Run: /scholar-init init <slug> <files>  to start fresh.
```

### Step 3.2 — For each file, copy/link and scan

For each argument after `add`:

1. Determine destination: `data/raw/` unless the user passed `--materials`.
2. Copy (default) or symlink (`--link`) into place, handling name collisions with a numeric suffix.
3. Run `safety-scan.sh` on the new file.
4. Add an entry to `.claude/safety-status.json` using `jq` (GREEN → CLEARED; YELLOW/RED → NEEDS_REVIEW:<level>).
5. Append an "Added:" row to `logs/init-report.md`.

### Step 3.3 — If any NEEDS_REVIEW, enter MODE 2

Same as Step 1.3 — do not leave the user with an unresolved file. Transition directly into the review loop.

---

## MODE 4 — Status

**Goal:** Print the current state without making any changes.

```bash
echo "=== Project Status ==="
echo "Directory: $(pwd)"
echo ""
if [ -f .claude/safety-status.json ]; then
  jq -r '
    to_entries |
    group_by(.value | split(":")[0]) |
    map({status: .[0].value | split(":")[0], count: length}) |
    .[] | "\(.count)\t\(.status)"
  ' .claude/safety-status.json
else
  echo "No .claude/safety-status.json found."
fi
echo ""
echo "Ingest report: logs/init-report.md"
```

Then print a list of NEEDS_REVIEW files (if any) and recommend `/scholar-init review`.

---

## Hard Rules

1. **Never `Read` a file with `NEEDS_REVIEW:*` status to "help the user decide."** The whole point is that the scan output is what they decide from, and the scan output is safe. Reading the file would defeat the gate.

2. **Never write CLEARED for a RED file without a typed OVERRIDE rationale.** The audit trail depends on this.

3. **Never offer `[D] OVERRIDE` for qualitative files** — audio (`wav`/`mp3`/`flac`/`m4a`/`ogg`/`aac`/`aiff`), video (`mp4`/`mov`/`avi`/`mkv`/`webm`), or interview transcripts (`eaf`/`textgrid`/`trs`/`cha`/`praat`). Voiceprints are biometric PII and interview text quotes participants verbatim — there is no "false positive" resolution. Only LOCAL_MODE, ANONYMIZED, or HALT are valid for these files. See policy §4.

4. **Require a rationale ≥ 20 characters for every OVERRIDE decision.** Strings like "ok", "n/a", "false positive" on their own are not acceptable. The rationale is logged verbatim to `logs/init-report.md` and becomes the IRB audit record.

5. **Never modify `.claude/safety-status.json` except via `jq` + atomic rename.** Hand-editing risks corrupting the JSON.

6. **Never skip writing to `logs/init-report.md`.** Every decision must be logged.

7. **Never cache or echo the contents of a file that scored NEEDS_REVIEW:RED**, even in error messages. The scan output (aggregated counts) is safe; the file body is not.

8. **If the PreToolUse hook fires during this skill and blocks a Read, that is correct behavior — do not try to work around it.** It means you're about to read something you shouldn't. Stop and ask the user.

---

## Save Output

scholar-init does NOT produce a manuscript document; it produces an initialized project directory plus two audit artifacts. Confirm the following files to the user after every run, and do NOT re-run pandoc conversion (this is not a writing skill).

**Written by this skill on every run (Modes 1, 2, 3):**

```
<cwd>/
├── .claude/safety-status.json    ← JSON sidecar — read + written by this skill (atomic via jq + rename)
└── logs/init-report.md           ← markdown audit trail — appended, never overwritten
```

**Written only in MODE 1 (by `scripts/init-project.sh`):**

```
<cwd>/
├── data/raw/                     ← user data copied here after scan
├── data/processed/               ← empty, for downstream pipelines
├── scripts/                      ← empty skeleton
├── output/                       ← pipeline outputs land here
├── drafts/                       ← manuscript drafts land here
└── .env                          ← project-level config (SLUG, OUTPUT_ROOT, …)
```

**At end of run, print a summary to the user:**
- Path of the `.claude/safety-status.json` file
- Path of the `logs/init-report.md` file
- For Mode 1: the newly created project root
- For Mode 2: counts of entries resolved by status (`CLEARED`, `LOCAL_MODE`, `ANONYMIZED`, `OVERRIDE`, `HALTED`) and any still in `NEEDS_REVIEW:*`
- For Mode 3: list of files newly added with their resolved status

Never rename or delete these files as part of "cleanup" — the audit trail is the record of IRB-relevant decisions.

---

## Cross-skill expectations

After `/scholar-init` completes (MODE 1 or 2), every file in `.claude/safety-status.json` will have one of these statuses:

- `CLEARED` / `ANONYMIZED` / `OVERRIDE` — Claude can `Read`
- `LOCAL_MODE` — Claude must use Bash-only loaders from `_shared/data-handling-policy.md` §3
- `HALTED` — Claude must not touch this file

Downstream skills (`scholar-eda`, `scholar-analyze`, `scholar-compute`, `scholar-ling`, `scholar-qual`) read this sidecar as input and inherit the constraints. They do not re-run the gate unless the user adds new files.

---

## Failure modes and recovery

**"The init script crashed halfway through."**  
Check `logs/init-report.md` — if it was written, the directory is partially complete. Rerun with `--force` to rebuild from scratch, or manually fix the issue (e.g., disk full) and rerun incrementally.

**"I reviewed a file and clicked the wrong option."**  
Edit `.claude/safety-status.json` with `jq` to change the entry, and append a correction row to `logs/init-report.md`. Never silently overwrite — the correction trail is part of the audit.

**"Presidio isn't installed, so the anonymizer can't run."**  
The script falls back to regex-based detection. Tell the user this and offer to install Presidio via `setup.sh` re-run.

**"safety-scan.sh is missing."**  
This means the plugin is broken. Refuse to proceed and tell the user to run `bash setup.sh` from the plugin directory.
