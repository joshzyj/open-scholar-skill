# Survey Design Reference

## Established Scale Batteries by Construct

### Trust and Social Capital
**Rosenberg Trust Scale** (generalized social trust):
- "Generally speaking, would you say that most people can be trusted, or that you can't be too careful in dealing with people?" (GSS single item)
- Three-item version: above + "Most people would try to take advantage of you if they got the chance" + "Most people try to be helpful"

**Institutional Trust** (GSS):
- "How much confidence do you have in [Congress / Banks / Church / Education]?" (Great deal / Some / Hardly any)

### Socioeconomic Status
**Subjective SES — MacArthur Scale**:
- "Think of this ladder as representing where people stand in society. People at the top have the most money, education, and most respected jobs. People at the bottom have the least. Where would you place yourself on this ladder?" (1–10)

**Perceived class position**: "Which of these do you think best describes you?" (Lower / Working / Middle / Upper Middle / Upper class)

### Discrimination
**Everyday Discrimination Scale** (Williams et al. 1997):
"In your day-to-day life, how often do any of the following things happen to you?" (Never → Almost every day)
1. You are treated with less courtesy than other people
2. You receive poorer service than other people at restaurants or stores
3. People act as if they think you are not smart
4. People act as if they are afraid of you
5. You are called names or insulted
6. You are threatened or harassed

Attribution item: "What do you think is the main reason for these experiences?"

### Mental Health
**PHQ-9** (Depression Screening — Kroenke et al. 2001):
"Over the last 2 weeks, how often have you been bothered by any of the following problems?" (0=Not at all, 1=Several days, 2=More than half the days, 3=Nearly every day)
1. Little interest or pleasure in doing things
2. Feeling down, depressed, or hopeless
3–9. [standard items]

Scoring: 0–4 minimal; 5–9 mild; 10–14 moderate; 15–19 mod. severe; 20–27 severe

**GAD-7** (Anxiety):
Similar format, 7 items measuring anxiety symptoms (Spitzer et al. 2006)

### Immigrant Identity and Assimilation
**MEIM-R** (Multiethnic Identity Measure — Revised, Phinney & Ong 2007):
"I have a clear sense of my ethnic background and what it means for me" — 6 items on exploration and commitment

**Language-based assimilation** (self-report, 4-point):
"How well do you speak [English / heritage language]?" (Not at all / Not well / Well / Very well)
"How often do you speak [language] at home / with friends / at work?" (Never → Always)

**Ethnic identity strength**: "I am proud to be [ethnicity]" / "My ethnicity is important to who I am" (4-item, 4-point Likert)

### Social Network Instrument (Burt 1984 name generator)
**Name generator**: "From time to time, most people discuss important matters with other people. Looking back over the last six months, who are the people with whom you discussed matters important to you? Just tell me their first names or initials."
(Record up to 5 names)

**Name interpreter** (for each name cited):
- How often do you have contact? (daily / weekly / monthly / less)
- What is the nature of your relationship? (family / friend / coworker / neighbor / other)
- What is their educational level? (less than HS / HS / college / graduate)
- What race/ethnicity are they?
- Did they help you find your current job? (yes/no)

---

## Survey Platform Comparison

| Feature | Qualtrics | REDCap | Google Forms | Prolific |
|---------|----------|--------|-------------|---------|
| Complex routing/branching | Excellent | Good | Limited | N/A |
| Randomization | Yes | Yes | No | Via Qualtrics |
| IRB compliance tools | Yes | Yes (HIPAA) | No | Yes |
| Response quality checks | Yes | Limited | No | Yes |
| Panel recruitment | Lucid/Dynata | No | No | Yes |
| Cost | Institutional license | Free (non-profit) | Free | Per response |
| Best for | Academic surveys | Health/clinical | Pilot only | Online panels |

---

## Response Scale Guidelines

**Likert scale construction**:
- 4 points: no midpoint; forces direction (useful when neutral is theoretically meaningless)
- 5 points: with neutral midpoint (standard)
- 7 points: for fine-grained attitudes; more statistical variance
- Labels: always label both endpoints AND midpoint at minimum; ideally all points

**Common ordinal scales**:
- Agreement: Strongly disagree / Disagree / Neither / Agree / Strongly agree
- Frequency: Never / Rarely / Sometimes / Often / Always
- Quality: Very poor / Poor / Fair / Good / Very good
- Likelihood: Very unlikely / Unlikely / Neither / Likely / Very likely

**Numeric entry format**: Use validated ranges; show unit ("years," "dollars," "$1,000s")

---

## Attention Check and Data Quality Items

**Instructed response item** (direct attention check):
"For this question, please select 'Strongly agree' regardless of your opinion. We include this item to verify you are reading the questions carefully."

**Consistency check** (indirect):
Include the same question twice with different wording; flag respondents whose answers differ by > 2 scale points.

**Logic check**:
- Age inconsistency: "Year graduated college" < "Year born + 15"
- Employment inconsistency: Full-time employed + student + retired all checked simultaneously

**Completion time filter**:
Flag responses completed in < [median time × 0.33] as likely inattentive. Most platforms record completion time automatically.

---

## Cognitive Interview Protocol Template

For each question, ask these cognitive probes verbally:

```
1. Comprehension probe:
   "What does that question mean to you in your own words?"

2. Retrieval probe:
   "How did you come up with that answer? What came to mind?"

3. Judgment probe:
   "How did you decide on [the answer they gave]?"

4. Response mapping probe:
   "Why did you choose [response category] rather than [adjacent category]?"

5. Sensitivity probe (for sensitive items):
   "Were you comfortable answering that question, or did you feel uncomfortable?"
```

Record verbatim answers. After 5–10 interviews, revise questions that were frequently misunderstood or caused confusion.

---

## Conjoint Analysis Reference

### Design Checklist
- Number of attributes: 4–7 (more reduces attribute salience)
- Levels per attribute: 2–5 (avoid too many; increases cognitive load)
- Tasks per respondent: 3–8 (balance precision vs. fatigue)
- Profile format: forced-choice (pick one of two) or rating (1–7 scale); forced-choice preferred for discrimination studies
- Randomization: full profile randomization per respondent in Qualtrics

### Power and Sample Size
For detecting AMCE of δ = 0.05 (5 pp) with 80% power: N ≥ 500 respondents × 5 tasks = 2,500 observations.
Rule of thumb: 1,000 respondents with 5 tasks gives ±3% precision for each AMCE.

### Analysis (R — cregg package)
```r
library(cregg)

# Estimate AMCEs (average marginal component effects)
amce <- cj(data = df,
           formula = chosen ~ race + education + criminal_record + experience,
           id = ~respondent_id,
           estimate = "amce")
plot(amce, vline = 0) + theme_Publication()
ggsave(file.path(output_root, "figures", "fig-amce.pdf"), device = cairo_pdf, width = 7, height = 5)

# Heterogeneous AMCEs by respondent subgroup
amce_het <- cj(df, chosen ~ race + education, id = ~respondent_id,
               by = ~respondent_race, estimate = "amce")
plot(amce_het) + facet_wrap(~BY) + theme_Publication()

# MM (marginal means) — alternative estimand; preferred when baseline matters
mm <- cj(df, chosen ~ race + education, id = ~respondent_id, estimate = "mm")
```

### Reporting Template
> "We used a conjoint experiment in which respondents evaluated [N] profiles varying [K] attributes ([list attributes with levels]). Each respondent completed [T] choice tasks. We estimate average marginal component effects (AMCEs) using OLS with standard errors clustered by respondent (Hainmueller, Hopkins & Yamamoto 2014). [N respondents, platform]."
