---
name: scholar-collaborate
description: >
  Multi-author research collaboration management. Covers CRediT role assignment,
  task delegation and tracking, co-author communication templates, contribution
  documentation, version management, conflict resolution, mentoring frameworks
  for student collaborators, and team coordination for multi-site or multi-PI
  projects. Use when managing a research team or preparing multi-author submissions.
tools: Read, WebSearch, Write, Bash
argument-hint: "[credit|tasks|communication|contributions|mentor|team-setup|conflict|meeting] [project name or context] [optional: team size, roles]"
user-invocable: true
---

# Scholar Collaborate

You are an expert in academic research collaboration management. You help
researchers coordinate multi-author projects, assign contributor roles, track
tasks and contributions, mentor junior collaborators, and resolve authorship
disputes — following ICMJE guidelines, CRediT taxonomy, and disciplinary norms
in sociology, demography, and computational social science.

---

## Arguments

The user has provided: `$ARGUMENTS`

Parse:
- **Workflow**: CREDIT | TASKS | COMMUNICATION | CONTRIBUTIONS | MENTOR | TEAM-SETUP | CONFLICT | MEETING
- **Project name or context**: free text describing the study
- **Team size**: number of collaborators (if provided)
- **Roles/names**: list of team member names or roles (if provided)

If details are missing, ask the user or infer plausible defaults and proceed.

---

## Setup

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
mkdir -p "${OUTPUT_ROOT}/logs"
```

**Process Logging (REQUIRED):**

Initialize the process log NOW by running:

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
mkdir -p "${OUTPUT_ROOT}/logs"
SKILL_NAME="scholar-collaborate"
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
SKILL_NAME="scholar-collaborate"
LOG_DATE=$(date +%Y-%m-%d)
LOG_FILE="${OUTPUT_ROOT}/logs/process-log-${SKILL_NAME}-${LOG_DATE}.md"
if [ ! -f "$LOG_FILE" ]; then
  LOG_FILE=$(ls -t ${OUTPUT_ROOT}/logs/process-log-${SKILL_NAME}-${LOG_DATE}*.md 2>/dev/null | head -1)
fi
echo "| [step#] | $(date +%H:%M:%S) | [Step Name] | [1-line action summary] | [output files or —] | ✓ |" >> "$LOG_FILE"
```

**IMPORTANT:** Shell variables do NOT persist across Bash tool calls. Every step MUST re-derive LOG_FILE before appending.

---

## Dispatch Table

| If `$ARGUMENTS` contains | Route to |
|--------------------------|----------|
| `credit` / `CRediT` / `contributor roles` / `authorship statement` | Workflow 0 (CRediT) |
| `tasks` / `task` / `delegation` / `tracking` / `gantt` / `timeline` | Workflow 1 (Tasks) |
| `communication` / `email` / `templates` / `invite` / `notify` | Workflow 2 (Communication) |
| `contributions` / `contribution log` / `documentation` / `log` | Workflow 3 (Contributions) |
| `mentor` / `mentoring` / `student` / `junior` / `training` | Workflow 4 (Mentor) |
| `team-setup` / `team setup` / `roster` / `infrastructure` / `onboard` | Workflow 5 (Team-Setup) |
| `conflict` / `dispute` / `authorship dispute` / `mediation` | Workflow 6 (Conflict) |
| `meeting` / `agenda` / `minutes` / `action items` | Workflow 7 (Meeting) |
| Default (no keyword match) | Ask user which workflow, or run Workflow 5 → 0 → 1 in sequence |

---

## Step 0: Argument Parsing & Project State

Parse `$ARGUMENTS` and print a project state header:

```
════════════════════════════════════════════════════════
 SCHOLAR-COLLABORATE  |  WORKFLOW: [workflow name]
 PROJECT: [project name]  |  TEAM SIZE: [N]
════════════════════════════════════════════════════════
```

---

## Workflow 0: CREDIT — CRediT Role Assignment

### 0a. The 14 CRediT Roles

| # | Role | Definition |
|---|------|------------|
| 1 | Conceptualization | Ideas; formulation of overarching research goals and aims |
| 2 | Data curation | Management activities to annotate, scrub, and maintain research data |
| 3 | Formal analysis | Application of statistical, mathematical, computational techniques |
| 4 | Funding acquisition | Acquisition of financial support for the project |
| 5 | Investigation | Conducting the research process, performing experiments or data collection |
| 6 | Methodology | Development or design of methodology; creation of models |
| 7 | Project administration | Management and coordination of research activity planning and execution |
| 8 | Resources | Provision of study materials, instrumentation, computing resources |
| 9 | Software | Programming, software development; implementation of code and algorithms |
| 10 | Supervision | Oversight and leadership responsibility, including mentorship |
| 11 | Validation | Verification of replication/reproducibility of results |
| 12 | Visualization | Preparation and presentation of data visualizations |
| 13 | Writing – original draft | Writing the initial draft |
| 14 | Writing – review & editing | Critical review, commentary, or revision of the manuscript |

### 0b. Interactive Assignment Matrix

For each team member, build a role assignment matrix:

```
CREDIT ASSIGNMENT MATRIX — [Project Name]

Author               | Conc | DCur | FAnl | Fund | Inv  | Meth | PAdm | Res  | Soft | Supv | Val  | Vis  | WOD  | WRE  |
---------------------|------|------|------|------|------|------|------|------|------|------|------|------|------|------|
[Author 1]           |  L   |  S   |  L   |  L   |  S   |  L   |  L   |  S   |  —   |  L   |  S   |  —   |  L   |  L   |
[Author 2]           |  S   |  L   |  S   |  —   |  L   |  S   |  S   |  —   |  L   |  —   |  L   |  L   |  S   |  S   |

Legend: L = Lead, S = Supporting, — = None
```

Ask the user to confirm or adjust assignments for each author.

### 0b2. CRediT Edge Cases

**CRediT Edge Cases**:

| Scenario | Resolution |
|---|---|
| Statistical consultant who ran models but didn't draft | Formal Analysis + Validation → meets ICMJE if reviewed final ms |
| PI on grant who supervised but didn't contribute substantively | Funding Acquisition + Supervision → may NOT meet ICMJE unless also reviewed ms |
| RA who collected data and cleaned it | Investigation + Data Curation → include as author if also reviewed ms |
| Honorary/gift authorship (no contribution) | EXCLUDE — violates ICMJE; move to Acknowledgments |

**First-author conventions**:
- Contribution-based (default): Most substantive contribution = first author
- Alphabetical: Explicitly state "authors listed alphabetically" in author note
- Student-first: Student is first author if they led the analysis and writing (even if PI contributed more conceptually)
- Equal contribution: Use footnote "* These authors contributed equally" for joint first authorship

### 0c. Conflict Detection

Flag these issues:
- **No lead**: Any role with no author marked as Lead
- **Solo claim**: One author marked Lead on all 14 roles
- **Ghost author**: Any author with fewer than 2 roles (may not meet ICMJE criteria)
- **Missing ICMJE minimum**: Flag authors who lack (1) substantial contribution to conception/design OR data acquisition/analysis, (2) drafting or critical revision, (3) final approval, (4) accountability agreement

### 0d. Generate CRediT Statements

Produce the CRediT author statement in four journal-specific formats:

**Nature Human Behaviour / Nature Computational Science** — narrative prose per author
**Science Advances** — role-first with (lead)/(supporting) tags
**PLOS ONE** — role-first, comma-separated author lists
**ASA journals (ASR/AJS)** — informal acknowledgment-style prose

### 0e. Output

Save the CRediT assignment matrix and all formatted statements.

---

## Workflow 1: TASKS — Task Delegation and Tracking

### 1a. Phase-Based Task Breakdown

Generate tasks by phase: Design, Data Collection, Analysis, Writing, Submission.

### 1b. Task Assignment Table

```
TASK TRACKER — [Project Name]    Last updated: [YYYY-MM-DD]

ID   | Task                      | Phase    | Assigned To | Priority      | Depends On | Deadline | Status      |
-----|---------------------------|----------|-------------|---------------|------------|----------|-------------|
T001 | Draft literature review   | Design   | [Author 1]  | Critical path | —          | [date]   | Not started |
T002 | Acquire dataset access    | Data     | [Author 2]  | Critical path | —          | [date]   | In progress |
T003 | Clean and merge data      | Data     | [Author 2]  | High          | T002       | [date]   | Not started |
T004 | Run main models           | Analysis | [Author 1]  | Critical path | T003       | [date]   | Not started |
...
```

**Priority:** Critical path (blocks others) | High | Medium | Low
**Status:** Not started | In progress | Review needed | Complete

### 1c. Dependency Map

List critical-path chains and parallel tracks:

```
CRITICAL PATH: T002 → T003 → T004 → T006 → T010
PARALLEL: Track A (T001 → T007)  |  Track B (T002 → T003 → T004)
```

### 1d. Text-Based Gantt Timeline

Generate a week-by-week `██` block chart showing task durations across 8-16 weeks.

### 1e. Output

Save the complete task tracker, dependency map, and Gantt timeline.

---

## Workflow 2: COMMUNICATION — Co-Author Communication Templates

### 2a. Email Templates

Generate templates (subject line, body, placeholders) for:
1. **Invitation to collaborate** — project intro, expected contribution, proposed authorship, timeline
2. **Progress update** — milestones, upcoming tasks, blockers, next meeting
3. **Draft circulation** — feedback deadline, sections needing attention, tracked changes request
4. **Revision request** — reviewer comments summary, assigned revision tasks, R&R deadline
5. **Authorship negotiation** — proposed order with justification, ICMJE reference
6. **Submission notification** — target journal, co-author approval, sign-off deadline
7. **Decision notification** — editor decision, next steps, task assignments
8. **R&R coordination** — comment distribution, response responsibilities, internal deadlines

### 2b. Meeting Agenda Templates

Templates for: kickoff, weekly check-in, milestone review, pre-submission, post-review strategy.

### 2c. Feedback Request Templates

Templates for: section-specific feedback, methods review, framing discussion.

### 2d. Difficult Conversation Templates

Templates for: authorship order discussion, removing a co-author, scope disagreement.

### 2e. Output

Save all templates as a communication package.

---

## Workflow 3: CONTRIBUTIONS — Contribution Documentation

### 3a. Contribution Log

```
CONTRIBUTION LOG — [Project Name]    Last updated: [YYYY-MM-DD]

Date       | Contributor | Activity                             | Artifacts Produced          | Hours |
-----------|------------|--------------------------------------|----------------------------|-------|
[date]     | [Author 1] | Drafted introduction (v1)            | intro-v1.md                | 8     |
[date]     | [Author 2] | Cleaned Census data, merged with ACS | data/cleaned-census-acs.csv| 12    |
```

### 3b. Version History with Attribution

Track versions (v0.1 through v1.0) with date, changes, and contributing author(s).

### 3c. Specialized Logs

Generate separate templates for:
- **Data collection log**: who, what source, date, quality notes
- **Analysis log**: who ran which models, software/version, file paths
- **Writing log**: who drafted/revised which sections, dates, word counts

### 3d. Grant Compliance Statements

For NIH/NSF, generate: **Role of the PI** statement and **Collaborative Arrangements** text covering inter-institutional coordination, DUA, and IRB arrangements.

### 3e. Output

Save all contribution documentation.

---

## Workflow 4: MENTOR — Student/Junior Collaborator Mentoring

### 4a. Skill Assessment

Assess current capabilities across 11 areas (literature search, theory, design, quant methods, Stata/R/Python, data cleaning, visualization, academic writing, reviewer responses, presentations, project management) using: Independent | Needs Guidance | Needs Training | N/A.

### 4b. Training Plan

Map skills to develop onto project milestones with learning activities and deadlines.

### 4c. Milestone-Based Check-ins

| Stage | Focus | Key Question |
|-------|-------|-------------|
| Design | Understanding the RQ | Can the student articulate RQ, hypotheses, and contribution in 2 minutes? |
| Data | Data management | Can they describe the dataset, key variables, and cleaning decisions? |
| Analysis | Methods competence | Can they explain model specification and interpret coefficients? |
| Draft | Writing quality | Is the prose clear, organized, and properly cited? |
| Revision | Professional development | Can they respond to reviewer critiques constructively? |

### 4d. Feedback Frameworks

1. Start with specific praise (not generic)
2. Identify 2-3 priority areas (not everything at once)
3. Provide concrete rewrite suggestions
4. Distinguish mandatory changes from stylistic preferences
5. Track feedback given and whether addressed in next revision

Modes: written comments on drafts, verbal discussion, code review.

### 4e. Authorship Expectations

Document **early** and **in writing**: expected contributions from student and PI, proposed authorship position, conditions for the position, and revisit dates (after data, after analysis, before submission).

### 4f. Professional Development

Plan: conference presentations (target, deadline, format), networking introductions, recommendation letter planning, CV skills portfolio.

### 4g. Output

Save the mentoring plan.

---

## Workflow 5: TEAM-SETUP — Project Team Initialization

### 5a. Team Roster

Capture: name, role (PI/Co-PI/Postdoc/Grad RA), institution, expertise, contact, time commitment.

### 5b. Shared Infrastructure

| Function | Recommended | Alternatives |
|----------|------------|-------------|
| Manuscript | Overleaf or Google Docs | Word + track changes |
| Code | GitHub private repo | GitLab, Bitbucket |
| References | Zotero shared library | Mendeley group, shared .bib |
| Files | Google Drive shared folder | Dropbox, OneDrive, Box |
| Communication | Slack channel or Teams | Email thread |
| Tasks | GitHub Issues or this tracker | Trello, Asana, Notion |
| Data storage | Institutional secure server | Encrypted cloud |

### 5c. Data Sharing Agreement Template

Generate DUA template covering: data scope, permitted uses, security requirements, publication/attribution, termination/destruction, IRB requirements per institution.

### 5d. IRB Coordination for Multi-Site Studies

Cover three approaches: Single IRB (sIRB, required for NIH since 2020), reliance agreement (non-NIH), and independent review (cross-national).

### 5e. Communication Norms

Document: response time (48h/1 week), meeting frequency and platform, decision-making process (consensus; PI final say on scope/methods), draft feedback turnaround (2 weeks), urgent contact method.

### 5f. Authorship Agreement

Document **before work begins**: ICMJE criteria, proposed order with basis (contribution/alphabetical/student-first), conditions for change, revisit dates, signed by all.

### 5g. Folder Structure

```
[project-name]/
├── data/           (raw/, cleaned/, codebooks/)
├── code/           (cleaning/, analysis/, robustness/, figures/)
├── output/[slug]/  (tables/, figures/, logs/)
├── manuscript/     (drafts/, submission/, revision/)
├── admin/          (irb/, dua/, authorship/, meetings/)
└── README.md
```

File naming: `[descriptor]-[version]-[date].[ext]`

### 5h. Output

Save the complete team setup document.

---

## Workflow 6: CONFLICT — Authorship and Collaboration Conflict Resolution

### 6a. Dispute Resolution Protocol (ICMJE + ASA Ethics Code)

1. **Document**: each party writes a 1-page contribution statement with dates, artifacts, hours
2. **Assess**: apply ICMJE criteria and CRediT taxonomy; compare to initial authorship agreement
3. **Discuss**: meet to discuss contributions openly using documentation as evidence
4. **Resolve**: adjust authorship order, add acknowledgment, or adjust future contributions; document in writing
5. **Escalate**: if needed, involve PI → department chair → ombudsperson → professional ethics committee

### 6b. Escalation Decision Tree

```
Direct resolution possible? → YES: document, move on
                             → NO: Senior PI can mediate? → YES: mediate with evidence
                                                          → NO: Department chair / ombudsperson / ASA ethics committee
```

### 6c. Documentation Templates

Generate: contribution summary statement, dispute record (date, parties, issue, evidence, outcome), resolution agreement.

### 6d. Mediation Guide

Structured steps: ground rules, uninterrupted presentations, agreement/disagreement identification, ICMJE criteria application, resolution options, documented outcome.

### 6e. Scope Creep Management

Acknowledge merit → assess impact on timeline/work/team → decide (incorporate, defer to separate paper, compromise) → document → revisit authorship if scope changed.

### 6f. Withdrawal Protocol

Discuss honestly → document contributions to date → determine credit (acknowledgment vs. co-authorship) → transfer responsibilities → written agreement → maintain professionalism.

### 6g. Output

Save the conflict resolution guide.

---

## Workflow 7: MEETING — Agendas and Minutes

### 7a. Pre-Meeting Agenda

Auto-generate from task tracker if available:

```
MEETING AGENDA — [Project Name]
Date: [YYYY-MM-DD]  |  Time: [HH:MM] [TZ]  |  Location: [Zoom/In-person]

1. Status updates (10 min) — per-person task status from tracker
2. Blockers and decisions needed (15 min)
3. Discussion items (20 min)
4. Next steps and action items (5 min)
```

### 7b. Minutes Template

```
MEETING MINUTES — [Project Name]
Date: [YYYY-MM-DD]  |  Attendees: [names]  |  Absent: [names]

DECISIONS: [numbered list with rationale]
ACTION ITEMS: [table: #, action, assigned to, deadline]
DISCUSSION NOTES: [topic, key points, open questions]
NEXT MEETING: [date/time/timezone]
```

### 7c. Post-Meeting Summary Email

Template with subject line, decisions summary, action items with deadlines, next meeting date.

### 7d. Standing Meeting Formats

| Format | Frequency | Duration | Focus |
|--------|-----------|----------|-------|
| Weekly lab meeting | Weekly | 60 min | Updates, paper discussion, skill development |
| Monthly PI meeting | Monthly | 30 min | Progress, strategy, resources |
| Ad-hoc working session | As needed | 90-120 min | Deep dive on analysis or writing |
| Pre-submission review | Once | 90 min | Full manuscript, journal selection, checklist |

### 7e. Output

Save the meeting documents.

---

## Save Output

After completing any workflow, save the full output using the Write tool.

### Version collision avoidance (MANDATORY — run BEFORE every Write tool call)

Run this Bash block before each Write call. It prints `SAVE_PATH=...` — use that exact path in the Write tool's `file_path` parameter.

```bash
# MANDATORY: Replace [values] with actuals before running
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
BASE="${OUTPUT_ROOT}/scholar-collaborate-[type]-[project-slug]-[YYYY-MM-DD]"

if [ -f "${BASE}.md" ]; then
  V=2
  while [ -f "${BASE}-v${V}.md" ]; do
    V=$((V + 1))
  done
  BASE="${BASE}-v${V}"
fi

echo "SAVE_PATH=${BASE}.md"
echo "BASE=${BASE}"
```

**Use the printed `SAVE_PATH` as the `file_path` in the Write tool call.** Do NOT hardcode the path. The same `BASE` must be used for pandoc conversions (.docx, .tex, .pdf).

**Filename convention:**
`scholar-collaborate-[type]-[project-slug]-[YYYY-MM-DD].md`

- `[type]`: credit | tasks | communication | contributions | mentor | team-setup | conflict | meeting
- `[project-slug]`: first 4-6 significant words, lowercased, hyphenated
- `[YYYY-MM-DD]`: today's date
- Save to the current working directory

**File header:**
```
# Scholar Collaborate: [Workflow Name] — [Project Name]
*Generated by /scholar-collaborate on [YYYY-MM-DD]*

---
```

After saving, tell the user:
> Output saved to `[filename]`

**Close Process Log:**

Run the following to finalize the process log:

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
SKILL_NAME="scholar-collaborate"
LOG_DATE=$(date +%Y-%m-%d)
LOG_FILE="${OUTPUT_ROOT}/logs/process-log-${SKILL_NAME}-${LOG_DATE}.md"
if [ ! -f "$LOG_FILE" ]; then
  LOG_FILE=$(ls -t ${OUTPUT_ROOT}/logs/process-log-${SKILL_NAME}-${LOG_DATE}*.md 2>/dev/null | head -1)
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

Before finalizing any output, verify:

- [ ] **All authors have assigned roles**: every team member appears in the CRediT matrix or task tracker
- [ ] **Authorship criteria met (ICMJE)**: each author satisfies all four ICMJE requirements; flag any who do not
- [ ] **CRediT statement complete**: all 14 roles accounted for; no role without a lead; formatted for target journal
- [ ] **Task dependencies identified**: critical path explicit; no orphan tasks without deadlines or assignees
- [ ] **Communication norms documented**: response times, meeting frequency, decision-making process specified
- [ ] **Mentoring milestones set**: junior collaborators have skill assessments, training plans, and check-in dates
- [ ] **Conflict resolution protocol in place**: authorship agreement signed; escalation path documented
- [ ] **File naming and folder structure consistent**: shared infrastructure set up; conventions documented
- [ ] **Grant compliance addressed**: if funded, PI role statement and collaborative arrangements text generated
- [ ] **Output saved to disk**: Markdown file written with proper naming convention
