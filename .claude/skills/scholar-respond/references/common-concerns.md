# Common Reviewer Concerns and Recommended Responses

## Sensitivity Analysis Response Templates

Use these when a reviewer requests formal sensitivity or bounding analyses.

### Oster (2019) Delta — Coefficient Stability Under Unobserved Confounding

**When**: Reviewer says "How sensitive are your OLS estimates to unobserved confounders?"

**Template response**:
> "Reviewer [N] raises an important concern about omitted variable bias. Following Oster (2019), we computed the degree of selection on unobservables relative to observables (δ) that would be required to reduce our main estimate to zero, assuming equal explanatory power of observed and unobserved controls (Rmax = 1.3 × R²_full). We find δ = [X], meaning unobservables would need to be [X] times as influential as our full set of controls to explain away the estimated effect. This exceeds conventional benchmarks (δ > 1.0 is considered robust). Results are reported in Appendix Table A[X] using the `sensemakr` package (Cinelli and Hazlett 2020)."

---

### E-Values — Unmeasured Confounding for Causal Claims

**When**: Reviewer says "What is the minimum confounding association needed to explain away your result?"

**Template response**:
> "To assess robustness to unmeasured confounding, we computed E-values (VanderWeele and Ding 2017) for our main estimate. The E-value for the point estimate is [X], meaning a confounder would need to have a risk ratio of at least [X]-fold with both the exposure and outcome — above and beyond all measured covariates — to fully explain away the observed association. The E-value for the confidence interval bound is [X]. We report these values in the Discussion (p. X) following the recommendation of VanderWeele (2020)."

---

### Rosenbaum Bounds — Sensitivity for Matched Designs

**When**: Reviewer questions whether unmeasured confounding could explain results in a matching or observational study.

**Template response**:
> "We conducted Rosenbaum (2002) bounds analysis to assess sensitivity of our matched estimates to hidden bias. We find that an unobserved confounder would need to increase the odds of treatment by a factor of Γ = [X] to render our result non-significant (p > .05). Given that our matched groups are balanced on [list covariates], we consider Γ = [X] to be an implausibly large effect of a single unmeasured variable. Sensitivity analysis was conducted using the `rbounds` package in R."

---

### Placebo Tests

**When**: Reviewer requests a falsification check.

**Template response**:
> "We conducted two placebo tests to assess the validity of our design. First, we [applied our treatment/instrument to a pre-treatment outcome / used a fake treatment date / tested against an unrelated outcome]. Under the null, we expect no effect; we find [b = X, SE = X, p = X], consistent with a valid design. Second, [describe second placebo if applicable]. Results are reported in Appendix Table A[X]."

---

## Empirical / Methods Concerns

### "You make causal claims but your design is observational."
**Priority**: MAJOR — must address
**What reviewers mean**: You say "X affects Y" or "X increases Y" but your data is cross-sectional OLS or panel without a clear identification strategy.
**Response strategies**:
1. **Weaken language** if the design doesn't support causal claims: change "affects" → "is associated with," "causes" → "predicts"
2. **Add identification strategy** if feasible: add FE model, IV analysis, DiD, or matching
3. **Defend OLS** if selection on observables is genuinely plausible: add controls, Oster delta bounding, and discuss why confounding is limited
4. **Explain counterfactual**: "Our interpretation is that... [mechanism]. While we cannot rule out all alternative explanations, we note that [controls, robustness, theory]."

**Template response**:
> "Reviewer [N] raises an important point about causal inference. We have revised the text throughout to use associational language ('associated with' rather than 'affects'), consistent with the observational nature of our design (p. X, and throughout). We have also added a paragraph to the Methods section discussing the main threats to causal inference in our setting and the steps we have taken to address them (p. X). [If you ran an additional analysis]: We have also added a [fixed effects / propensity score weighted] specification in Table A[X], which yields similar results."

---

### "You need more robustness checks."
**Priority**: MAJOR (if zero checks) / MINOR (if some already)
**What they want**: Alternative operationalizations, alternative samples, alternative model specs, placebo tests
**Response strategies**:
1. Run the specific checks requested
2. If already in the appendix, point to them explicitly
3. Add a dedicated robustness paragraph in the Results section

**Template response**:
> "We appreciate Reviewer [N]'s call for additional robustness checks. We have added [N] analyses to the Online Appendix: (1) [description, Table A.X]; (2) [description, Table A.X]; (3) [description, Table A.X]. Results are consistent with our main findings across all specifications, as we now note in the Results section (p. X)."

---

### "The sample is not representative / Your N is too small."
**Priority**: Depends on severity
**Response strategies**:
- If N is genuinely small: acknowledge explicitly; frame as "first-wave evidence" or "proof of concept"; discuss power
- If N is adequate but reviewer is worried: report power analysis or minimum detectable effect
- If representativeness is a concern: clarify the target population and defend that sample is appropriate for the research question

**Template response**:
> "Reviewer [N] raises a concern about sample size and representativeness. Our analytic sample (N = [X]) is [drawn from / limited to] [description]. While we acknowledge that [limitation], we note that [defense: the research question concerns this specific population / other studies of X use similar N / power analysis shows our sample is adequately powered to detect effects of size β]. We have added a sentence to the Data section clarifying the sampling strategy and its implications for generalizability (p. X)."

---

### "You should report AME / marginal effects, not odds ratios."
**Priority**: MAJOR for ASR; MODERATE for AJS/Demography
**Response strategies**:
- Compute AMEs and add to tables or replace odds ratios
- For ASR: this is essentially required; add AME column to main tables
- Note in text: "We report average marginal effects following [ASR convention / Mood 2010]"

**Template response**:
> "We thank Reviewer [N] for this suggestion. Following the convention of [ASR / the journal], we have replaced odds ratios with average marginal effects (AMEs) calculated using the margins package in R [or margins in Stata]. Tables [X] and [Y] now present AMEs with robust standard errors. This change does not alter the substantive interpretation of our findings."

---

### "The parallel trends assumption is not tested / The IV's exclusion restriction is not justified."
**Priority**: MAJOR — fatal if not addressed
**Response strategies**:
- **DiD/parallel trends**: Plot event study; add pre-trend test; discuss plausibility of the assumption
- **IV exclusion restriction**: Discuss explicitly why the instrument affects Y only through X; cite supportive evidence or prior work
- If assumption is truly untenable: acknowledge as a limitation and consider alternative design

**Template response (DiD)**:
> "Reviewer [N] correctly identifies the parallel trends assumption as critical to our difference-in-differences design. We have conducted two tests: (1) a formal pre-trend test [F-test / event study], which shows no differential pre-treatment trend between treatment and control groups (p = [X], Table A[X]); and (2) an event study plot (Figure A[X]) showing coefficients near zero in all pre-treatment periods. We have added a paragraph to the Methods section discussing the plausibility of the parallel trends assumption and these tests (p. X)."

---

### "Missing data / How did you handle missing values?"
**Priority**: MODERATE
**Response strategies**:
- Describe missing data handling in Methods: listwise deletion (most common), multiple imputation, or inverse probability weighting
- Report % missing on key variables
- If listwise deletion: check if dropped cases differ systematically (attrition analysis)
- Add to footnote or appendix

**Template response**:
> "Reviewer [N] asks about our missing data strategy. [N]% of observations are missing on [key variable]. We use [listwise deletion / multiple imputation via MICE / inverse probability weighting] in our main analysis. We report the missing data pattern in Appendix Table A[X]. [If listwise deletion]: We compared the analytic sample to excluded cases on key covariates and found no statistically significant differences (Appendix Table A[X]), suggesting attrition is unlikely to bias our estimates. [If MI]: We generated [M] imputed datasets using predictive mean matching and combined estimates using Rubin's rules."

---

### "Endogeneity / Selection bias is not addressed."
**Priority**: MAJOR
**Response strategies**:
1. Add a selection model (Heckman two-stage) if selection into treatment/sample is the concern
2. Add instrumental variable analysis if a plausible instrument exists
3. Add matching or reweighting (PSM, CEM, entropy balancing)
4. Bound the bias using Oster delta or E-values
5. Discuss the direction and magnitude of likely bias

**Template response**:
> "Reviewer [N] raises a valid concern about potential selection bias. To address this, we have [added a Heckman selection model / implemented coarsened exact matching / added an instrumental variable specification using Z as instrument]. The results, presented in Appendix Table A[X], are [consistent with / slightly attenuated relative to] our main estimates. We have added a paragraph to the Methods section (p. X) discussing the nature of the selection concern and the steps we have taken to address it."

---

## Theory / Conceptual Concerns

### "The theoretical mechanism is not clearly specified."
**Priority**: MAJOR for ASR/AJS
**What they mean**: You invoke a theory but don't explain WHY X causes Y through what process
**Response strategies**:
- Add an explicit "the mechanism is..." sentence in the Theory section
- Draw a simple causal diagram (can be text-based: X → M → Y)
- Make sure the mechanism connects your specific IV to your specific DV, not just general theory

**Template response**:
> "Reviewer [N] rightly calls for a more explicit statement of the theoretical mechanism. We have revised the Theory section (p. X) to specify that [specific mechanism: 'The mechanism operates through [M], whereby X leads to M, which in turn produces Y']. We have also added a diagram (Figure 1) showing the theoretical model. This revision clarifies how our hypotheses derive from the theoretical framework."

---

### "The paper doesn't engage with [specific work / debate]."
**Priority**: MAJOR if it's a directly relevant seminal paper; MINOR if peripheral
**Response strategies**:
- If the work is directly relevant: engage it seriously; does it support, contradict, or qualify your argument?
- If it supports your argument: cite it and note the alignment
- If it contradicts: explain why your findings might differ (different population, time period, measure)
- If it's genuinely not relevant: explain briefly why

**Template response**:
> "We thank Reviewer [N] for pointing us to [Author Year]. We have now engaged with this work in the [Literature Review / Theory / Discussion] section (p. X). [Author Year]'s argument that [their claim] is [consistent with / qualified by / in tension with] our findings because [explanation]. We have added [1–2 sentences] connecting our work to this literature."

---

### "Your hypotheses don't follow from your theory."
**Priority**: MAJOR — structural problem
**Response strategies**:
- Revise the theory section to make the logical derivation explicit
- Or revise the hypotheses to match what the theory actually predicts
- Use the "because" test: "H1: X is positively associated with Y BECAUSE [mechanism M]"

**Template response**:
> "Reviewer [N] identifies a disconnect between our theoretical framework and our stated hypotheses. We have substantially revised the Theory section (p. X–Y) to more explicitly derive our hypotheses from the theoretical mechanism. Specifically, we now show how [mechanism] leads to the prediction that [H1], and how the moderation argument in [H2] follows from [scope condition or boundary condition in the theory]. We believe the revised theory section makes the logical structure of our argument clearer."

---

### "The contribution is incremental / This is already well-established."
**Priority**: MAJOR — threatens the paper's rationale
**Response strategies**:
- Articulate what is genuinely new: new population, new mechanism, new data, resolved debate, boundary condition identified
- Distinguish your findings from the cited prior work more sharply
- If the reviewer is right, consider whether there is a stronger framing or a way to heighten the novelty

**Template response**:
> "We appreciate this important challenge and have substantially revised the framing of our contribution. Our paper advances the literature in [N specific ways]: (1) We examine [X population] which has not been studied in this context... (2) We provide the first test of [mechanism] using [this design/data]... (3) Our findings qualify the established view by showing that [boundary condition]. We have revised the Introduction (p. X) and Discussion (p. X) to more clearly articulate these distinctions."

---

## Writing and Framing Concerns

### "The introduction is too long / too slow to get to the point."
**Response**: Cut the literature review material from the introduction; move it to the Background section. Introduction should be ≤1,000 words for most sociology journals.

**Template response**:
> "Reviewer [N] is correct that our introduction was overlong. We have revised it substantially, reducing it from [N] to [N] words. We moved the extended literature discussion to the Background section, where it belongs. The revised introduction moves more quickly to the research question and contribution."

---

### "The discussion repeats the results rather than interpreting them."
**Response**: Rewrite the Discussion to open with theoretical interpretation, not restatement. Every paragraph should begin with "what this means for theory/literature," not "we found that..."

**Template response**:
> "Reviewer [N] correctly identifies that our Discussion largely restated results without sufficient interpretation. We have substantially rewritten the Discussion section (p. X–Y). Each paragraph now begins with a theoretical claim and then explains what our findings mean for that claim. We have also added [N] paragraphs connecting our findings to [specific debates in the literature]."

---

### "The abstract does not accurately represent the paper." / "The abstract overclaims."
**Response**: Rewrite the abstract to match the actual findings and scope. For observational studies, use associational language. For Nature journals, reformat to the 3-sentence structured abstract.

**Template response**:
> "We have rewritten the abstract to more accurately represent our findings and their scope. Specifically, we have [replaced causal language with associational language / removed the claim about X / added the key qualification about Y]. The revised abstract is [N] words, within the journal's limit."

---

### "The paper is too long." (Word count exceeds limit)
**Response**:
- Cut background material in the literature review
- Move robustness checks to the appendix
- Trim the Discussion
- Remove footnotes that aren't essential
- Report: "We have cut [N] words. The revised manuscript is [N] words, within the journal's [N]-word limit."

---

## Journal-Specific Common Concerns

### ASR Common Concerns
1. Causal claims without causal design (very common)
2. Odds ratios instead of AME
3. Insufficient theoretical contribution / too descriptive
4. Contribution not stated clearly enough
5. No robustness checks
6. Too long (>12,000 words)

### AJS Common Concerns
1. Theory section too thin or derivative
2. Not enough engagement with classical theory (Weber, Durkheim, Marx, Simmel)
3. Paper is interesting but doesn't advance sociological theory
4. Comparative or historical scope missing

### Demography Common Concerns
1. Methods section not detailed enough
2. Missing sensitivity analyses / robustness
3. Missing decomposition analysis
4. No online supplementary appendix
5. Data not available for replication

### Social Forces Common Concerns
1. Framing too narrow for generalist readership
2. Theory adequate but not innovative enough for ASR/AJS
3. Contribution unclear — what does this add to Social Forces readership?
4. Methods solid but not cutting-edge enough for methods journals

### Science Advances Common Concerns
1. Not sufficiently interdisciplinary in framing
2. Sociological jargon not defined for broader audience
3. Missing code/data availability statement
4. Methods not detailed enough for replication
5. Author contributions (CRediT) not included

### Nature Human Behaviour / NCS Common Concerns
1. Missing Reporting Summary (required form)
2. Missing pre-registration statement
3. Sample size not justified (no power analysis)
4. Statistical tests not fully reported (missing test statistic, df)
5. Over 50 references in main text
6. Figure error bars not labeled (SEM vs. SD vs. 95% CI)
7. Individual data points not shown for small-N comparisons
8. Code not deposited (NCS: mandatory)
9. Paper exceeds word limit (strict at Nature journals)

### Language in Society Common Concerns
1. Insufficient ethnographic context for the speech community
2. Speaker metadata incomplete (age, gender, education, language background)
3. Transcription conventions not specified (Jefferson? IPA?)
4. Language ideology framework not adequately developed
5. Over-reliance on quantitative results without qualitative interpretation
6. Not enough engagement with LiS's core readership debates

### APSR Common Concerns
1. Causal identification insufficient for political science standards
2. Pre-registration not mentioned for experimental studies
3. External validity / generalizability concerns
4. Policy implications not adequately discussed
5. Not enough engagement with formal/rational choice theory (if applicable)

---

## Qualitative Methods Concerns

### "The sampling strategy is not justified."
**Priority**: MAJOR
**What they mean**: Why these cases/participants? Why this number? How were they selected?

**Template response**:
> "Reviewer [N] raises an important question about our sampling strategy. We employed [purposive / snowball / theoretical / maximum variation] sampling to ensure [justification]. We recruited [N] participants who [criteria]. Sampling continued until we reached [theoretical saturation / data sufficiency], operationalized as [the point at which no new themes or codes emerged across 3 consecutive interviews / the point at which additional cases produced diminishing analytical returns]. We have added a paragraph to the Methods section (p. X) explaining the sampling rationale and saturation criteria."

---

### "The coding procedure is not transparent."
**Priority**: MAJOR for ASR/AJS; MODERATE for specialist journals
**Response strategies**:
- Describe the coding process step by step: open coding → axial coding → selective coding (or whatever procedure was used)
- Report inter-coder reliability if multiple coders were involved (κ ≥ 0.70 for systematic coding)
- Provide the codebook (or a summary) in the appendix
- If a single coder: acknowledge and discuss reflexivity

**Template response**:
> "We have expanded the Methods section (p. X) to describe our coding procedure in detail. We conducted [N] rounds of coding: (1) open coding to identify emergent themes, (2) focused coding to consolidate and refine themes, and (3) theoretical coding to connect themes to our analytical framework. [If multiple coders]: Two trained research assistants independently coded a random subsample of [N] transcripts, achieving inter-coder reliability of κ = [X]. Discrepancies were resolved through discussion. The final codebook ([N] codes in [N] categories) is provided in Appendix [X]."

---

### "Where is the reflexivity / positionality statement?"
**Priority**: MODERATE — increasingly expected, especially for ethnographic and interview work
**Response strategies**:
- Add a brief reflexivity statement to the Methods section
- Discuss how your social position may have affected data collection and interpretation
- Do NOT over-disclose; focus on methodologically relevant aspects

**Template response**:
> "We appreciate Reviewer [N]'s attention to researcher positionality. We have added a reflexivity statement to the Methods section (p. X) discussing how our [specific relevant aspects of social position — e.g., racial identity, class background, insider/outsider status relative to the community] may have influenced data collection and interpretation. We note that [specific consideration — e.g., our status as outsiders may have limited access to certain narratives, which we addressed through prolonged engagement and member checking]."

---

### "The claims exceed what the qualitative evidence supports."
**Priority**: MAJOR
**What they mean**: You generalize from a small sample to a population, or you claim causation from qualitative data.

**Template response**:
> "Reviewer [N] correctly flags that our claims exceeded the warrant of our evidence. We have revised the Discussion (p. X) to frame our findings as [analytical generalizations / transferable patterns / theoretical propositions] rather than [population-level claims / causal effects]. We have replaced language such as '[overclaiming phrase]' with '[appropriately scoped phrase].' We acknowledge the limitations of generalizability from our [N]-case [interview / ethnographic] study in the Discussion (p. X)."

---

### "You need more triangulation / more evidence."
**Priority**: MODERATE
**Response strategies**:
- If additional data sources exist (documents, field notes, secondary data): describe how they corroborate your findings
- If a single data source: acknowledge and explain why it is sufficient for the research question
- Add rich quotations that illustrate key themes from multiple participants

**Template response**:
> "We have strengthened the evidentiary base in two ways. First, we have added [N] additional illustrative quotations from [different participants / field notes / archival documents] that corroborate the [theme/pattern] (p. X–Y). Second, we triangulated our interview data with [data source], which confirms [specific finding]. We now discuss our triangulation strategy explicitly in the Methods section (p. X)."

---

## Mixed Methods Concerns

### "The integration between qualitative and quantitative components is weak."
**Priority**: MAJOR — this is the most common mixed-methods critique
**What they mean**: The qual and quant parts feel like two separate papers stapled together.

**Template response**:
> "Reviewer [N] correctly identifies that the integration between our quantitative and qualitative analyses needed strengthening. We have revised the paper in three ways: (1) We have added a 'Mixed Methods Integration' paragraph to the Methods section (p. X) that explains how the qualitative component was designed to [illuminate mechanisms identified in the quantitative analysis / generate hypotheses tested quantitatively / provide context for statistical patterns]. (2) In the Results section, we now present quantitative and qualitative findings together by theme rather than sequentially (p. X–Y). (3) In the Discussion, we have added a paragraph explaining how the two strands converge and where they offer complementary insights (p. X)."

---

### "Why mixed methods? The quantitative analysis alone would suffice."
**Priority**: MAJOR for generalist journals; MODERATE for methods journals

**Template response**:
> "We appreciate Reviewer [N]'s question about the necessity of our mixed methods design. The qualitative component serves [a specific function that the quantitative analysis cannot fulfill — e.g., 'to identify the mechanism through which X leads to Y, which is not observable in the survey data' / 'to provide contextual understanding of why respondents who experience X report Y' / 'to validate the construct validity of our key measure']. Without the qualitative data, our quantitative findings would remain [descriptive / mechanistically underspecified / potentially misinterpreted]. We have added a justification for the mixed methods design in the Methods section (p. X)."

---

## Network Analysis Concerns

### "The network boundary is not justified."
**Priority**: MAJOR
**What they mean**: Why these nodes and not others? How was the population of actors defined?

**Template response**:
> "Reviewer [N] raises a critical question about network boundary specification. We define the network boundary based on [criterion — e.g., organizational membership / geographic proximity / participation in event X]. This approach follows [Laumann et al. 1989 / other justification]. We acknowledge that boundary specification affects network statistics (Kossinets 2006) and have added a sensitivity analysis in the Appendix (Table A[X]) that [expands the boundary to include X / restricts to Y] to assess robustness. We discuss boundary specification in the Methods section (p. X)."

---

### "ERGM / SAOM convergence is not reported."
**Priority**: MAJOR for technical reviewers
**What they mean**: Did the model converge? Are the MCMC diagnostics acceptable?

**Template response**:
> "We have added convergence diagnostics to the Methods section and Appendix. For our [ERGM / SAOM] model: (1) all t-statistics for convergence are below [0.1 / the conventional threshold]; (2) MCMC trace plots show adequate mixing (Appendix Figure A[X]); (3) goodness-of-fit plots indicate the model adequately reproduces observed [degree distribution / edgewise shared partners / geodesic distances] (Appendix Figure A[X]). We used [N] iterations with a burn-in of [N]."

---

### "What about network endogeneity?"
**Priority**: MAJOR
**What they mean**: Network ties may be endogenous to the outcome (selection vs. influence).

**Template response**:
> "Reviewer [N] correctly identifies the challenge of disentangling selection from influence in network studies. We address this in [N] ways: (1) Our SAOM model jointly estimates selection (tie formation) and influence (behavior change) processes, allowing us to separate the two (Snijders et al. 2010). (2) We include [structural effects — reciprocity, transitivity, degree] to control for endogenous network dynamics. (3) We report [rate, evaluation, and creation functions separately]. We have expanded the Methods section (p. X) to discuss the endogeneity concern and our approach to addressing it."

---

## Agent-Based Modeling (ABM) Concerns

### "The model is not validated against empirical data."
**Priority**: MAJOR

**Template response**:
> "Reviewer [N] correctly asks about empirical validation. We validate our ABM in [N] ways: (1) pattern-oriented modeling (Grimm et al. 2005): we compare [N] emergent patterns from the model against empirical targets [list targets with citations]; (2) sensitivity analysis: we conducted [Sobol / Morris / Latin Hypercube] sensitivity analysis to identify which parameters most influence outcomes (Appendix Table A[X]); (3) calibration: we calibrated key parameters using [empirical data source]. We have expanded the Methods section (p. X) to document the validation protocol."

---

### "The ODD protocol is incomplete / not provided."
**Priority**: MAJOR for journals requiring it; MODERATE otherwise

**Template response**:
> "We have added a complete ODD (Overview, Design concepts, Details) protocol following Grimm et al. (2020) as Supplementary Text S[X]. The protocol describes: (1) Purpose and patterns; (2) Entities, state variables, and scales; (3) Process overview and scheduling; (4) Design concepts (emergence, adaptation, learning, prediction, sensing, interaction, stochasticity, collectives, observation); (5) Initialization; (6) Input data; (7) Submodels with pseudo-code for each behavioral rule."

---

## Computational and Reproducibility Concerns

These arise most often at Science Advances, NHB, NCS, and Demography.

### "Code and/or data are not available."

**Priority**: MAJOR at NCS (code mandatory); HIGH at Science Advances and NHB

**Response strategies**:
1. Deposit code to GitHub (public repository) and data to Harvard Dataverse, ICPSR, or OSF
2. For proprietary or restricted data: provide synthetic data, codebook, and full analysis code; explain the restriction
3. For restricted administrative data: deposit code; provide data access instructions in Methods

**Template response**:
> "Reviewer [N] correctly identifies the absence of a code and data availability statement. We have deposited all analysis code at [GitHub URL] and the data at [Dataverse/OSF DOI]. The repository includes [list contents: replication scripts, cleaned dataset, codebook, README]. We have added a Data and Code Availability statement to the Methods section (p. X). For [restricted variable], we provide [synthetic data / the analysis code with instructions for accessing the restricted data through [source]]."

---

### "The methods are not reproducible — insufficient detail."

**Priority**: HIGH at all journals for computational methods (LLM annotation, ML, NLP)

**Response strategies**:
- For LLM annotation: report exact model name + version, annotation date, temperature, full prompts verbatim in supplementary materials
- For ML: report all hyperparameters, train/test split, random seed, and validation procedure
- For network analysis: report all model parameters (ERGM terms, SAOM effects, convergence statistics)
- For topic models: report number of topics, coherence scores, topic selection rationale

**Template response**:
> "We agree that the [LLM annotation / ML / network] methods section needed more detail for reproducibility. We have added the following to the Methods section and Supplementary Materials: (1) exact model ID and annotation date ([model], [YYYY-MM-DD]); (2) full prompts verbatim (Supplementary Text S1); (3) temperature and decoding parameters ([values]); (4) all hyperparameters and the random seed used ([seed = X]). All analysis code has been deposited at [URL]."

---

### "The LLM/AI annotation lacks validation against human coders."

**Priority**: MAJOR if the annotation is a key variable

**Response strategies**:
- Report Cohen's κ or Krippendorff's α against a human-coded benchmark (minimum n = 200 documents)
- If κ < 0.70: flag as a limitation; use LLM labels as supplementary check rather than primary coding
- Report inter-rater agreement between human coders as a separate benchmark
- Report run-to-run reliability (same prompt, same data, different API calls)

**Template response**:
> "Reviewer [N] correctly flags the need for human validation of our LLM-based annotation. We conducted a validation study in which two trained research assistants independently coded a random sample of [N = 200] documents on [variable]. Cohen's κ between the two human coders was [X], indicating [fair/moderate/substantial/near-perfect] agreement. The LLM annotation agreed with the majority human label in [X]% of cases (κ = [X] vs. human gold standard). We also assessed run-to-run reliability by repeating the annotation on a subsample of [N = 100] documents, finding [X]% exact agreement across runs. We report this validation in the Methods section (p. X) and discuss its implications for the reliability of our annotation in Appendix S[X]. Following Lin and Zhang (2025), we treat the LLM annotation as [primary / supplementary] and note the reliability limitation explicitly."

---

### "The topic model has too many / too few topics."

**Priority**: MODERATE

**Template response**:
> "Reviewer [N] questions our choice of K = [N] topics. We selected K using [held-out likelihood / semantic coherence + exclusivity plot / domain knowledge]. We present the model selection diagnostics in Appendix Figure A[X], which shows [coherence peaks at K = X / the exclusivity-coherence frontier favors K = X]. We have also added Appendix Table A[X] showing results with K = [N-5] and K = [N+5] topics; our key findings are robust to this choice. We discuss topic selection in the Methods section (p. X)."

---

### "The text classification model is not properly evaluated."

**Priority**: MAJOR for NCS; HIGH for computational papers at any journal

**Template response**:
> "We have expanded the evaluation section (p. X and Appendix Table A[X]) to include: (1) precision, recall, and F1 for each class; (2) macro and weighted averages; (3) confusion matrix (Appendix Figure A[X]); (4) [5-fold / 10-fold] cross-validation results showing [mean F1 = X, SD = X]; (5) comparison against a [majority class baseline / simpler model] to demonstrate the value of our approach. We report these metrics following the standards recommended for computational social science (Grimmer et al. 2022)."

---

### "Missing Reporting Summary" (Nature journals only)

**Priority**: MANDATORY — cannot be accepted without it

**Response**:
> "We have completed the Nature [Human Behaviour / Computational Science] Reporting Summary, which is now included as a supplementary file. The Reporting Summary addresses study design, sample size justification, replication, randomization, blinding, and statistical reporting as required by the journal."

---

### "Figure error bars are not labeled / Individual data points not shown."

**Priority**: HIGH at NHB/NCS

**Template response**:
> "Reviewer [N] correctly identifies that our figure error bars were not labeled. We have added error bar labels to all figures specifying [95% confidence intervals / standard errors / standard deviations] as appropriate. For Figure [X], where n < [30] per group, we have added individual data points overlaid on the summary statistics, following NHB figure standards."

---

### "Pre-registration is not mentioned / not done."

**Priority**: HIGH at NHB/NCS; MODERATE at Science Advances; expected at ASR for experimental studies

**Template response**:
> "Reviewer [N] asks about pre-registration. [Option A — if pre-registered:] This study was pre-registered at [OSF/AsPredicted] on [date], prior to data collection. The pre-registration is publicly available at [URL]. We have added the pre-registration statement to the Methods section (p. X). [Option B — if not pre-registered:] This study was not pre-registered, as [data were already collected / the analysis was exploratory]. We have added a transparency statement to the Methods section acknowledging this and noting which analyses were pre-planned vs. exploratory (p. X)."

---

## Navigating Conflicting Reviewer Demands

When two reviewers give contradictory instructions, the response letter must acknowledge the conflict directly and explain your adjudication.

### Types of Reviewer Conflict

| Conflict type | Example | Resolution approach |
|--------------|---------|-------------------|
| Theoretical framing | R1: "Add Bourdieu." R2: "Drop the theory section; focus on empirics." | Integrate briefly; defend the framing you keep |
| Analytical approach | R1: "Run fixed effects." R2: "Fixed effects are inappropriate here." | Run both; discuss tradeoff in text |
| Word count | R1: "Too brief on methods." R2: "Paper is too long; cut." | Cut weak content; expand the specific area R1 requested |
| Literature coverage | R1: "Missing X literature." R2: "Too much background; not enough analysis." | Add X concisely; cut weaker background |
| Causal language | R1: "Causal claims are too strong." R2: "You understate the causal implications." | Use hedged-but-clear language; defend in text |
| Scope | R1: "Broaden to include Y." R2: "Narrow the focus to Z." | Narrow as requested by R2; acknowledge R1's point as future work |
| Model choice | R1: "Use OLS for interpretability." R2: "Use ML for prediction." | Report both; explain the role of each |

---

### How to Identify True vs. Apparent Conflicts

**Apparent conflict** (reviewers want the same thing but phrased differently):
- R1: "The paper lacks a clear contribution."
- R2: "The paper doesn't explain why this matters."
→ Both want a sharper framing of significance. Address once; note both reviewers raised it.

**True conflict** (mutually exclusive demands):
- R1: "The controls are over-specified and are blocking the mechanism."
- R2: "You need more control variables to rule out confounding."
→ Requires a judgment call; explain your reasoning.

---

### Response Template for Conflicting Reviewers

**Option A: Favor one reviewer with transparent justification**

> "Reviewers 1 and 2 offer different recommendations regarding [X]. Reviewer 1 suggests [R1 recommendation], while Reviewer 2 recommends [R2 recommendation]. After careful consideration, we have followed Reviewer [N]'s approach because [reason: e.g., it is more consistent with our identification strategy / it better fits the journal's audience / it is more standard in this subfield]. We note this choice in the [Methods / Discussion] section (p. X) so that readers can assess the implications."

**Option B: Find a synthesis**

> "Reviewers 1 and 2 have raised complementary concerns about [topic]. Reviewer 1 emphasizes [concern A], while Reviewer 2 emphasizes [concern B]. We have revised [section] to address both: [Describe synthesis — e.g., we present the fixed effects model as our preferred specification (addressing R2's concerns about confounding) while adding a paragraph discussing the within-person interpretation limitation that R1 identified]."

**Option C: Partial concession to both**

> "Both reviewers raise important points about [issue]. We have made changes in response to each: for Reviewer 1, we have [change A] (p. X); for Reviewer 2, we have [change B] (p. X). We acknowledge these are in some tension, and we explain our adjudication in the new footnote [N] on p. X."

---

### When the Editor Is the Tiebreaker

If reviewers conflict sharply and neither option is clearly correct:
- **Do not choose silently.** Always name the conflict and explain your resolution.
- **Favor the concern that the editor's decision letter emphasizes.** If the editor's letter says "the reviewers are particularly concerned about causal identification," treat that as the priority.
- **Write the justification for the non-favored reviewer**: "We respectfully maintain that [approach X] is appropriate here because [reason]. We have added a sentence noting this choice so that readers can evaluate the trade-off."

---

## Reviewer Personality Types — How to Calibrate Your Response

Different reviewers require different response strategies. Recognizing the reviewer type helps calibrate tone and depth.

### The Methodological Perfectionist
**Signs**: Extremely detailed comments on model specification, standard errors, robustness; demands specific alternative analyses by name; references recent methods papers.
**Strategy**: Match their level of detail. Run the exact analyses they request. Show your work. Reference the methods papers they cite. This reviewer respects thoroughness.
**Tone**: Technical, precise, evidence-heavy.

### The Theoretical Gatekeeper
**Signs**: Asks about contribution, mechanism, "so what?"; names specific theorists you should engage; questions the theoretical novelty.
**Strategy**: Take the theoretical challenge seriously. Don't just add a citation — engage the theory substantively. Show how your work extends, challenges, or qualifies the cited theory. For ASR/AJS, this reviewer is often the one who determines the decision.
**Tone**: Intellectually engaged, demonstrating command of the theoretical landscape.

### The Supportive-but-Thorough Reviewer
**Signs**: Opens with genuine praise; gives many minor comments; suggests improvements rather than demanding changes; recommends Minor Revision or Major Revision (not Reject).
**Strategy**: Address every minor point — this reviewer gave you detailed help because they want the paper to succeed. Show gratitude and diligence. Don't skip any comment just because it seems small.
**Tone**: Warm, appreciative, thorough.

### The Hostile Reviewer
**Signs**: Recommends Reject; questions the paper's basic premise; may misrepresent what the paper says; tone is dismissive or condescending.
**Strategy**: Stay calm. Do not match the tone. Correct factual misrepresentations politely with evidence. For the substance, address what can be addressed and acknowledge legitimate points. For illegitimate demands, disagree respectfully with reasons. The editor usually knows when a reviewer is being unfair.
**Tone**: Unfailingly polite, factual, evidence-based. Never defensive.

### The Lazy/Cursory Reviewer
**Signs**: Very short review (1–2 paragraphs); vague comments ("the methods need work"); no specific suggestions; recommends Major Revision or Reject without detail.
**Strategy**: Interpret the vague comment charitably and address the most likely underlying concern. Show that you took the comment seriously even if it was imprecise. This positions you well with the editor.
**Tone**: Professional, interpreting the comment generously.

---

## Response Calibration by R&R Round

### R1 (First Revision)
- **Length**: Full response; 1–2 pages per reviewer is normal; 3+ pages for major revisions
- **Detail**: Every comment gets a thorough response with specific revision text
- **New analyses**: Adding new robustness checks, tables, figures is appropriate and expected
- **Tone**: Grateful, thorough, demonstrating substantial engagement
- **Common mistake**: Under-responding to minor comments (editors notice)

### R2 (Second Revision)
- **Length**: Shorter; typically 0.5–1 page per reviewer
- **Detail**: Focused on remaining concerns only; do not re-explain R1 changes
- **New analyses**: Only if specifically requested; do NOT volunteer new analyses
- **Tone**: More direct; less deferential; confident but respectful
- **Common mistake**: Introducing new material not requested (this triggers R3)
- **Rule**: If a reviewer raises a new concern not in R1, address it but note it is new

### R3 (Third Revision — rare)
- **Length**: Brief; half a page to one page total
- **Detail**: Only the specific remaining items; no padding
- **New analyses**: Absolutely none unless explicitly demanded
- **Tone**: Surgical, efficient, final
- **Common mistake**: Over-explaining or appearing defensive
- **Rule**: The editor wants to accept. Make it easy. Any new issue you create = potential rejection

---

## Resubmission Strategy After Rejection

### Step 1: Triage the Decision

| Decision type | What it means | Your response |
|--------------|--------------|--------------|
| **Desk reject** (no external review) | Editor says out of scope or below threshold without sending to reviewers | Reframe for a different journal; do not resubmit to same journal without major restructuring |
| **Reject after review** (no R&R) | Reviewed externally; editor says fatal flaws | Diagnose root cause; major revision before next submission |
| **Reject with invitation to resubmit** (rare) | Editor rejects but signals openness if you address specific concerns | Treat as conditional R&R; respond to each concern; resubmit as new submission with a cover letter summarizing changes |
| **Revise and resubmit (R&R)** | Standard conditional acceptance — not a rejection | Accept; revise fully; do not send to another journal while under R&R |

---

### Step 2: Diagnose the Root Cause

Before resubmitting anywhere, diagnose why it was rejected:

**Scope mismatch** (most desk rejects):
- The journal's audience and your paper's audience don't overlap
- Fix: Change framing, not the paper. Rewrite the introduction to foreground what is interesting to the target journal's readers.

**Contribution threshold** (most common post-review rejection):
- The paper makes a real contribution but doesn't clear the bar for that specific journal
- Fix: Assess whether you can genuinely raise the contribution (new analysis, broader scope) or whether the paper belongs at a different tier

**Fatal methodological flaw**:
- A core identification assumption is untestable, violated, or not addressed
- Fix: Address before resubmitting ANYWHERE. Reviewers at other journals will raise it too.

**Framing problem** (common for interdisciplinary papers):
- Sociology paper rejected by Nature journal: too discipline-specific, not framed for broad audiences
- Nature paper rejected by sociology journal: not enough theoretical depth
- Fix: Substantive reframing, not just word choice

---

### Step 3: Use Reviewer Comments Proactively in the Next Submission

When resubmitting to a new journal, you are NOT required to disclose the previous rejection. However, if reviewer comments were detailed and useful, address them anyway — new reviewers will often raise the same concerns.

**Cover letter strategy for resubmission**:

> "This manuscript has been revised substantially since an earlier version was reviewed elsewhere. We have [summary of major revisions: e.g., added event study plot, reframed the theoretical contribution, extended the sample]. The current version represents a significant improvement over the previous draft."

- Do not name the previous journal unless you are resubmitting to the same journal
- Do not include your previous response letter unless asked
- Do not claim it is a new paper if it is substantially the same

**Pre-emptive addressing of predictable concerns** (optional but effective):
If prior reviewers raised a methodological concern that you could not fully address, state your position in the paper itself rather than waiting for the new reviewer to raise it:

> "While our panel design addresses time-invariant confounding, we acknowledge that time-varying unobservables remain a concern. We conduct sensitivity analyses in Appendix B using [alternative approach] and show that [key findings are robust / effect magnitude is bounded]."

---

### Step 4: Journal Ladder Strategy

Match the revised paper's realistic contribution to the right journal. Do not resubmit to a higher-tier journal without substantive improvements.

**Key decision rule**: Move down the ladder only if the paper's contribution doesn't clear the next tier's bar. Do not "shotgun" submissions — you should only have one submission active at a time (unless journals explicitly allow simultaneous submission).

---

### Step 5: Writing the Revised Introduction After Rejection

A rejected paper often needs a rewritten introduction for the new journal, even if the analysis is identical:

| What to change | Why |
|---------------|-----|
| Opening hook | Different journals value different entry points (ASR: theoretical puzzle; AJS: historical/theoretical question; Science Advances: societal significance; Demography: demographic trend; NCS: computational advance) |
| Contribution claim | Restate what is new relative to what the target journal's readers know |
| Literature framing | Cite the target journal's own recent articles; show you know the conversation |
| Theory emphasis | ASR: mechanism; AJS: theoretical innovation; Science Advances: interdisciplinary significance |
| Word count | Adjust to fit journal requirements |

**Template for reframed contribution paragraph**:
> "[Journal]'s readership will recognize [the puzzle or debate that motivates the paper]. Despite [what is known], [what remains unknown or contested]. We address this gap by [what we do]. Our contribution is [specific advance: new method / new population / resolved debate / boundary condition identified]. This matters because [why the target audience should care, in their own terms]."
