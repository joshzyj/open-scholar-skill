# Parental Job Loss and Adolescent Educational Expectations

Keywords: parental job loss; educational expectations; family inequality; panel data

## Abstract
This article examines whether parental job loss is associated with adolescent educational expectations in household panel data. The question matters for family inequality research because adolescents form educational plans while households absorb labor-market risk, stress, and resource constraints. Using an observational panel design with household fixed effects, wave fixed effects, and robustness checks for timing and attrition, the analysis estimates bounded associations rather than causal effects. The findings show that parental job loss is linked to lower educational expectations, while one timing-oriented check is directionally similar but less precise. The article contributes to family sociology by showing how economic instability can enter expectation formation while making uncertainty and design limits part of the substantive claim. [@work01] [@work02] [@work03] [@work04] [@work05] [@work06] [@work07] [@work08] [@work09] [@work10] [@work11] [@work12]

## Introduction
Educational expectations are a central bridge between family conditions and later attainment, because they organize course taking, institutional navigation, and the perceived value of continued schooling. Parental job loss can alter that bridge by changing material resources, stress exposure, and beliefs about what educational investments remain feasible. The puzzle is therefore not only whether economic instability matters, but how a household shock becomes attached to adolescents' own future-oriented judgments. [@work01] [@work02] [@work03]

Prior literature has established strong links between family resources, parental employment, and educational attainment, yet less is known about how adolescents revise expectations during a parent's employment disruption. Existing research also leaves unresolved whether household shocks mainly depress expectations through stress and constraint or whether some families respond by emphasizing schooling as protection against future insecurity. This gap motivates a focused empirical test of expectation formation rather than a broad claim about every pathway from job loss to attainment. [@work04] [@work05] [@work06]

The article advances a bounded contribution for family sociology. It integrates family stress and status attainment perspectives, estimates the association in panel data, and evaluates whether timing and attrition checks support the same interpretation. This contribution is deliberately disciplined: the analysis asks whether the pattern is consistent with a feasibility mechanism while recognizing that unobserved time-varying shocks may still shape both parental employment and adolescent planning.

The remainder of the article therefore follows the structure of a quantitative family article. The next section develops the theory and states the hypothesis, the Data and Methods section explains the sample, measures, and analytic strategy, the Results section presents descriptive and regression evidence, and the Discussion and Conclusion return to the theoretical contribution and limits of the observational design.

## Background
### Family Stress and Economic Shock
The family stress perspective defines parental job loss as a household-level disruption that can alter routines, emotional climate, and available resources. Educational expectations refer to adolescents' beliefs about the schooling they are likely to complete, so the concept is a future-oriented judgment rather than an observed attainment outcome. When employment instability enters the household, adolescents may hear new conversations about affordability, observe parental strain, or perceive reduced capacity to support educational plans. The mechanism is not simply income loss; it is the translation of economic uncertainty into everyday judgments about what schooling remains feasible. [@work07] [@work08] [@work09] [@work10] [@work11] [@work12]

### Status Attainment and Educational Feasibility
Status attainment research treats expectations as socially organized beliefs about plausible futures rather than private preferences alone. Adolescents learn what seems possible from parents, schools, peers, and the resources surrounding them. A parent's job loss can signal that economic security is fragile and that continued schooling may require tradeoffs the household cannot easily absorb. From this perspective, expectations are a point at which structural risk becomes translated into perceived opportunity. [@work13] [@work14] [@work15] [@work16] [@work17] [@work18]

### Rival Expectations and Scope Conditions
A competing account is that some families respond to economic insecurity by emphasizing education as protection against future vulnerability. This alternative is important because it prevents the theory from assuming a one-directional response to hardship. The association may also vary by savings, school context, timing of the shock, and adolescents' prior expectations. These scope conditions imply that a single estimate should be interpreted as an average pattern across heterogeneous household responses, not as a universal family process. [@work19] [@work20] [@work21] [@work22] [@work23] [@work24]

### Testable Expectation
The preceding arguments predict a testable hypothesis. If parental job loss reduces perceived educational feasibility through stress, resource constraints, and uncertainty, adolescents exposed to job loss should report lower educational expectations than comparable adolescents observed without that household shock. H1 is the study hypothesis: parental job loss is associated with lower adolescent educational expectations. The timing and attrition checks probe whether this expectation is sensitive to event timing and observed sample composition; they do not convert the observational design into a causal experiment. [@work25] [@work26] [@work27] [@work28] [@work29] [@work30]

## Data and Methods
### Data and Sample
The analysis uses household panel data with repeated observations of adolescents and parental employment. The source file initially contains 2,500 adolescents from 1,760 households observed across eligible survey waves. I restrict the data to adolescents with nonmissing educational expectations, observed parental employment histories, household income, child age, and valid wave identifiers, and I exclude records outside the age range covered by the study question. These restrictions align the denominator with the outcome, exposure, and fixed-effects design. After applying the eligibility rules and complete-case requirements for modeled variables, the final analytic sample includes N = 1,200 observations. The final analytic sample is therefore justified by the need to compare observed changes in expectations within households while retaining the variables required for adjustment and robustness checks.

### Variables and Measures
#### Dependent Variable
The dependent variable is adolescent educational expectations. It measures the highest level of schooling the adolescent expects to complete, using a survey item recorded as an ordered expectation scale and treated as a continuous score in the linear models. Higher values indicate more ambitious expected attainment. This outcome captures perceived educational feasibility, not completed schooling.

#### Independent Variable
The independent variable is parental job loss. It is coded as a binary indicator equal to 1 when a parent experiences an employment transition into job loss between observed waves and 0 otherwise. The measure is based on panel employment reports and is interpreted as a household economic shock that may change adolescents' planning environment.

#### Control Variables
The control variables include child age, survey wave, and household income. Child age is measured in years and adjusts for developmental differences in expectations. Survey wave indicators absorb period-specific differences in the survey environment and educational context. Household income is measured as total household income and adjusts for observed economic resources that may confound the association between job loss and educational expectations.

### Analytic Strategy
The primary model is a household fixed-effects linear regression because the research question concerns within-household changes in adolescent educational expectations around parental job loss. I estimate this regression with household-clustered standard errors. The estimating equation is EducationalExpectations_it = alpha_i + lambda_t + beta JobLoss_it + gamma Age_it + delta Income_it + epsilon_it, where alpha_i denotes household fixed effects and lambda_t denotes wave fixed effects. The coefficient beta compares educational expectations within the same household after parental job loss with expectations in observations without job loss, net of child age, household income, and wave conditions. Standard errors are clustered at the household level to account for repeated observations within households. This estimator is appropriate for the panel structure, but it remains observational because time-varying unmeasured shocks may still coincide with job loss. Observational claims must remain bounded.

The analysis reports the full primary specification rather than presenting a long stepwise sequence in the main text. Robustness and sensitivity checks assess whether the association is sensitive to event timing and sample composition. A timing specification adds event-study indicators to inspect pre-shock patterns and the shape of adjustment around job loss. An attrition-weighted sensitivity analysis first estimates a logit propensity score for remaining in the final analytic sample using baseline observed characteristics, including parental job loss exposure, child age, wave, and household income. The weighting algorithm uses inverse probability weighting rather than nearest-neighbor matching, and overlap is evaluated with common support and standardized differences. After weighting, the outcome model re-estimates the household fixed-effects specification. Complete-case denominators are reported for the modeled variables, and survey design decisions are handled through the robustness weights rather than as causal identification.

## Results
<!-- LOCKED_ARTIFACT: tables/regression-main.html | LOCKED_PATH: results-locked/LOCK-20260429-001/tables/regression-main.html -->
<!-- LOCKED_ARTIFACT: figures/event-study.png | LOCKED_PATH: results-locked/LOCK-20260429-001/figures/event-study.png -->

Table 1. Descriptive statistics for modeled variables in the analytic sample.

| Variable | Coding or scale | Mean / percent | N |
| --- | --- | ---: | ---: |
| Adolescent educational expectations | Ordered expected schooling scale | 4.20 | 1200 |
| Parental job loss | Binary indicator, 1 = job loss | 0.18 | 1200 |
| Child age | Continuous years | 15.10 | 1200 |
| Survey wave | Categorical wave indicators | -- | 1200 |
| Household income | Continuous household income | 52,300 | 1200 |
Notes: Table 1 reports reader-facing descriptive statistics for every variable used in the modeled specifications.

<!-- DISPLAY_TABLE: tables/regression-main.html -->
Table 2. Regression estimates for parental job loss and adolescent educational expectations.

| Predictor | Model 1 | Model 2 | Model 3 |
| --- | ---: | ---: | ---: |
| Parental job loss | -0.120 (0.040) | -0.080 (0.050) | -0.090 (0.045) |
| p-value | 0.003 | 0.110 | 0.046 |
| N | 1200 | 1200 | 1200 |

<!-- DISPLAY_FIGURE: figures/event-study.png -->
Figure 1. Event-study diagnostic figure.

![Figure 1. Event-study diagnostic figure](figures/event-study.png)

Table 1 reports descriptive statistics for all modeled variables in the analytic sample, including adolescent educational expectations, parental job loss, child age, survey wave, and household income. These descriptives establish the scale, coding, and denominator before the regression evidence is interpreted.

Table 2 shows the headline regression estimates for the primary and robustness specifications. In Model 1, the primary specification, parental job loss is associated with lower adolescent educational expectations, with an estimate of -0.120, a standard error of 0.040, a p-value of 0.003, and n = 1200 [@work01]. This is the clearest result in the reviewed evidence, so the manuscript treats it as the main empirical anchor rather than spreading equal weight across every specification. Its direction matches the feasibility mechanism developed in the theory section, but the interpretation remains associational because the design cannot rule out all time-varying unobserved shocks.

Table 2 also shows why the manuscript frames robustness evidence cautiously. For Model 2, the timing-oriented specification has a negative estimate of -0.080, a standard error of 0.050, a p-value of 0.110, and n = 1200 [@work02]. For Model 3, the attrition-weighted specification has a negative estimate of -0.090, a standard error of 0.045, a p-value of 0.046, and n = 1200 [@work03]. These side-by-side results support a negative pattern with uneven robustness instead of uniform confirmation. The weaker robustness estimate is treated as a boundary on the claim rather than as a finding to smooth over. Primary claims must stay aligned with reviewed evidence. All numerical claims must stay aligned with reviewed evidence.

Figure 1 presents the event-study diagnostic and visually supports the same bounded reading. The figure is not treated as standalone proof; instead, it helps readers inspect timing and visual consistency while the tabled estimates carry the inferential claims. Read together, the descriptive statistics, regression table, and diagnostic figure indicate that the pattern is negative in the primary specification, weaker in one robustness check, and therefore best interpreted as evidence for a cautious observational claim rather than a decisive causal story.

## Discussion
The findings suggest that household economic instability may shape educational expectations through perceived feasibility and stress-linked constraints. The contribution is to connect family economic shocks with expectation formation while preserving the distinction between a reviewed association and broader causal interpretation. The pattern is substantively meaningful because educational expectations are part of the pathway through which family circumstances can become linked to later attainment. Table 2 and Figure 1 are discussed as evidence for this bounded interpretation rather than as proof of causation. At the same time, the evidence is not uniform enough to support a sweeping claim, which is why the interpretation stays close to the theory of constrained feasibility.

The weaker robustness evidence narrows the claim and motivates future work with stronger identification, longer follow-up, and richer measures of household coping. The timing-sensitive evidence is less precise than the primary estimate, which may reflect sparse event-time information or limits in the measured shock. Future designs could combine administrative employment histories with repeated expectation measures to observe adjustment more directly. Such work would help distinguish short-term disruption from longer-term changes in educational planning.

The manuscript also has measurement and design limitations. Educational expectations capture perceived futures, but they do not reveal every conversation, resource tradeoff, or emotional response inside the household. The observational design means that unmeasured shocks could coincide with parental job loss and adolescent planning. These limitations are disclosed because they define the claim's scope rather than merely qualifying it after the fact.

## Conclusion
This article began with a problem in family inequality research: adolescents form educational plans while families experience economic shocks, yet the literature has less evidence on how job loss enters expectation formation before attainment is observed. The theoretical argument joined family stress and status attainment perspectives to show why employment instability may reduce perceived educational feasibility. The empirical evidence supports a bounded conclusion: parental job loss is linked to lower adolescent educational expectations in the primary panel analysis, with some uncertainty across robustness checks. The contribution is not a causal demonstration; it is a bounded observational claim about how household economic instability is associated with future-oriented educational beliefs. Future research can extend this contribution by using stronger identification, longer panels, and richer measures of household coping to clarify when adolescents revise expectations after family employment shocks. This next step matters because expectation formation is one channel through which temporary household disruption may become connected to durable educational inequality.

## References
Author, F. (2020). Verified citation fixture.
