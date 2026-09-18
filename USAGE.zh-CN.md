# Open Scholar Skill — 用户指南

[English](USAGE.md) | **简体中文**

一个面向社会科学研究者、以顶级期刊为目标的 Claude Code 项目。
33 个 scholar 技能 + 1 个实用工具（共 34 个），覆盖从想法探索到协作管理的完整研究流程。

本项目为 **Claude Code** 构建；这些技能同样适用于 **OpenAI Codex** 以及其他能够加载 markdown 技能文件夹的编码代理——把 `.claude/skills/*` 链接到 `~/.codex/skills`，即可在自然语言中按名称调用技能（例如："用 scholar-lit-review 梳理居住隔离与健康的文献"）。数据安全防护自带 Codex 适配器钩子，由 `/scholar-init` 安装（见[数据安全](#15-数据安全--scholar-safety)一节）。

---

## 目录结构

技能与代理（agents）位于 `.claude/` 目录中：

```
open-scholar-skill/
├── .claude/
│   ├── skills/           ← 33 skills (scholar-*) + 1 utility (sync-docs)
│   ├── agents/           ← 9 reviewer agents (peer-reviewer-*) + 4 verification agents (verify-*) + 6 code-review agents (review-code-*)
│   └── settings.local.json
├── README.md
└── USAGE.md
```

在本项目目录下工作时，全部 33 个技能都可以在任意 Claude Code 会话中通过 `/技能名` 调用。

---

## 如何调用技能

输入斜杠命令，后接你的参数：

```
/scholar-idea why do low-income neighborhoods have lower preventive care uptake
/scholar-lit-review residential segregation and health outcomes
/scholar-write introduction on racial disparities in school discipline for ASR
/scholar-citation insert ASA citations and build reference list for my draft
/scholar-journal prepare manuscript for Nature Human Behaviour
```

技能名后面的文本会直接作为上下文传入。参数越具体，输出质量越好。

---

## 技能速查表

| 技能 | 适用场景 | 示例参数 |
|-------|-------------|-----------------|
| `/scholar-brainstorm` | 从数据文件或码本生成研究问题（5 代理评审团） | `data/nlsy97.csv` 或 `codebook.pdf` |
| `/scholar-idea` | 将宽泛主题转化为正式研究问题 | `why does AI exposure affect worker precarity` |
| `/scholar-lit-review-hypothesis` | 文献综述 + 理论 + 假设一步完成 | `redlining and activity space segregation for AJS` |
| `/scholar-lit-review` | 仅做文献综述（只需检索/综合、不需要理论时使用） | `residential segregation and health` |
| `/scholar-hypothesis` | 仅做理论 + 假设（文献综述已完成时使用） | `why does segregation affect health` |
| `/scholar-conceptual` | 构建原创理论框架与概念图 | `theorize a framework for digital labor precarity` |
| `/scholar-design` | 假设确定之后 | `causal ID for segregation-health panel` |
| `/scholar-causal` | 分析之前 | `segregation → health; DiD or FE; SES confounder` |
| `/scholar-data` | 查找数据集（100+ 来源）、收集新数据、自动抓取 | `find dataset for immigration and earnings` |
| `/scholar-eda` | 建模之前 | `pre-analysis for panel dataset` |
| `/scholar-analyze` | 运行分析、生成表格/图形、撰写结果（18 种模型，gt + Stata 输出） | `data.csv, OLS of earnings on education by race for Demography` |
| `/scholar-compute` | NLP / 机器学习 / 网络 / life2vec（11 个模块） | `STM topic model on news corpus` 或 `life2vec on PSID panel` 或 `dml effect of X on Y` |
| `/scholar-simulate` | LLM 社会模拟（硅基抽样、生成式 ABM、实验）— **任何可发表的结论都必须先与真实人类数据验证** | `silicon survey of partisan affect, then validate against ANES` |
| `/scholar-write` | 起草章节 | `introduction on segregation and health for ASR` |
| `/scholar-citation` | 引文与参考文献 | `insert ASA citations and build reference list` |
| `/scholar-knowledge` | 8 模式知识图谱：ingest / search / relate / status / export / compile（Obsidian wiki）/ ask（问答）/ re-extract | `compile` 构建 wiki，然后 `ask what are the main theories of segregation?` |
| `/scholar-rag` | 面向整个参考文献库的全本地向量数据库 + GraphRAG，用于文献综述：提取 → bge-m3 嵌入 → LanceDB，本地 LLM 的 GraphRAG（实体/社区），通过 MCP 服务器（`rag_search`）向 Claude/Codex 暴露。自包含；数据不出本机。6 种模式：setup、ingest、query、mcp、graph、status | `ingest`，然后 `query how does residential segregation affect mobility` |
| `/scholar-monitor` | 前沿文献订阅：基于增量的顶刊（Crossref/ISSN）+ arXiv 抓取，自动写入知识图谱，经 ntfy.sh 推送摘要到手机。专为 `/loop` 定时调度设计。 | `arxiv-llm` 或 `preview` 或 `/loop 24h /scholar-monitor` |
| `/scholar-journal` | 投稿准备 | `prepare manuscript for Demography` |
| `/scholar-open` | 预注册 / 数据共享 | `preregistration for FE panel study` |
| `/scholar-replication` | 构建并测试复现包 | `full for Demography` |
| `/scholar-respond` | 评审模拟 / 返修（R&R） | `simulate paper.pdf for Demography` |
| `/scholar-qual` | 质性编码与分析 | `open-coding transcripts/*.txt grounded theory` |
| `/scholar-collaborate` | 多作者协作管理 | `credit 4-author paper on immigrant integration` |
| `/scholar-ling` | 社会语言学研究 | `variationist analysis of t-deletion` |
| `/scholar-ethics` | 研究伦理合规 | `pre-submission ethics check for Demography` |
| `/scholar-init` | **v5.9.0** 搭建项目目录、扫描原始文件、写入 `.claude/safety-status.json`，让 PreToolUse 钩子知道 Claude 可以 Read 哪些文件 | `nhanes-bmi ~/Downloads/nhanes.csv` 或 `review` |
| `/scholar-safety` | 实时数据隐私保护 | `scan data.csv before analysis` |
| `/scholar-verify` | 验证分析结果与稿件的一致性 | `full output/drafts/full-paper-2026-03-10.md` |
| `/scholar-polish` | 最终文字润色（清晰、简洁、流畅、期刊语感） | `output/drafts/draft-v2.md for ASR` |
| `/scholar-code-review` | 分析脚本的多代理代码审查（6 个代理） | `full output/scripts/` |
| `/scholar-openai` | 通过 OpenAI Codex CLI 代理进行外部审查 | `full output/drafts/full-paper-2026-03-10.md` |
| `/scholar-auto-improve` | 技能输出的事后质量审计 | `observe output/drafts/` |
| `/sync-docs` | 同步幻灯片、讲稿与论文 | `slides.tex script.tex manuscript.tex` |

---

## 完整研究工作流（模块化）

当你只想运行某一个研究阶段、反复打磨某一节，或从流程中的特定环节继续推进时，
可单独使用下列技能。

---

### 0. 想法探索 — `/scholar-idea`

```
/scholar-idea why does remote work change neighborhood ties and political participation
/scholar-idea AI automation and occupational mobility in low-wage service work
/scholar-idea intersectionality of immigration status and gender on wage penalties
```

当你有一个宽泛的主题、但需要一个达到可发表水准的研究问题时使用。
它会生成 3–5 个研究切入角度，以明确的"总体/情境/机制"结构将其形式化为 RQ1–RQ3，
为每个问题推导 H1–H2，进行可行性与新颖性筛查（High/Medium/Low），
并推荐唯一最优问题及后续技能调用命令。

**输出格式：**
1. `IDEA DIAGNOSIS` — 哪些方面有前景、哪些方面尚欠明确
2. `CANDIDATE RESEARCH ANGLES` — 3–5 个角度，含机制与竞争性解释
3. `FORMAL RESEARCH QUESTIONS` — RQ1–RQ3
4. `HYPOTHESES` — 每个 RQ 对应 H1–H2
5. `FEASIBILITY + NOVELTY MATRIX`
6. `RECOMMENDED QUESTION` + 推荐理由
7. `NEXT COMMANDS` — 后续技能的确切调用命令

---

### 0b. 数据驱动的头脑风暴 — `/scholar-brainstorm`

```
/scholar-brainstorm path/to/gss-codebook.pdf sociology, inequality
/scholar-brainstorm path/to/survey-data.csv health disparities for Demography
/scholar-brainstorm path/to/questionnaire.pdf immigration, labor market
```

当你手头已有材料——码本、调查问卷或数据集——并想发现这些数据能支撑哪些可发表的
研究问题时使用。有两种模式：

- **DATA 模式**（根据 `.csv`、`.dta`、`.rds`、`.parquet` 等自动识别）：先运行安全扫描
  （经由 `scholar-safety`），再探索变量分布、交叉表和经验信号检验，
  在提出问题之前先找出有潜力的模式。
- **MATERIALS 模式**（根据 `.pdf`、`.docx`、`.md` 自动识别）：阅读码本或问卷，
  基于可用测量提出理论驱动的问题，完全不接触实际数据。

**输出格式：**
1. `DATA LANDSCAPE` — 变量、测量与覆盖范围盘点
2. `EMPIRICAL SIGNALS`（仅 DATA 模式）— 值得深究的交叉表、相关和模式
3. `TOP 10 RESEARCH QUESTIONS` — 按可发表性排序，含机制、总体、可行性
4. `5-AGENT EVALUATION PANEL` — 理论家、方法学家、领域专家、期刊编辑、"魔鬼代言人"分别为每个 RQ 打分
5. `CONSENSUS RANKING` — 最终排序清单及推荐的后续技能

**何时用它、何时用 `/scholar-idea`：**
- `/scholar-idea` — 你有宽泛主题或困惑，但没有具体数据
- `/scholar-brainstorm` — 你有数据或材料，想发现它们能回答什么问题

---

### 1. 文献综述 — `/scholar-lit-review`

```
/scholar-lit-review residential segregation and cardiovascular health
/scholar-lit-review AI labor displacement and occupational mobility
```

先查询你的 **Zotero 文献库**（见 [Zotero 集成](#zotero-集成)），
再通过网络检索补齐缺口。产出：
- 理论图景（2–4 段，梳理主导框架）
- 经验知识现状（3–6 段）
- 研究缺口（条目列表 + 叙述）
- 可直接粘贴的文献综述初稿（ASR/AJS：1,500–2,500 词；Demography：1,000–2,000 词）

---

### 2. 理论与假设 — `/scholar-hypothesis`

```
/scholar-hypothesis why does residential segregation affect cardiovascular health
/scholar-hypothesis intersectionality of race and gender in political donations
```

选定理论框架（压力过程、累积劣势、社会资本、交叉性等），指明 X → M → Y 机制，
并推导编号假设（H1、H2、H3），格式可直接用于论文。

交叉性研究：采用乘积项设定（β₃ 交互项），并为加性效应与交叉性效应分别生成明确的
假设表述。

---

### 2b. 理论构建与概念图 — `/scholar-conceptual`

```
/scholar-conceptual theorize a framework for digital labor precarity
/scholar-conceptual diagram mechanism model for segregation and health
/scholar-conceptual full framework with figure for immigrant incorporation for ASR
```

构建原创理论框架并产出可发表质量的概念图。两种模式：

**MODE 1 — THEORIZE** — 从经验困惑构建新理论：
- 7 种理论构建策略：类型学构造（属性空间分析）、过程理论化（时间序列）、机制说明（Coleman 之舟、Hedström DBO）、适用范围条件划定、多层次模型、由异常现象出发的溯因推理、以及整合竞争视角的综合框架
- 产出：正式框架陈述、机制链条、适用范围条件、可证伪推论、相对既有理论的定位

**MODE 2 — DIAGRAM** — 生成概念图：
- 图形类型：机制图、多层次理论模型、类型学矩阵、过程/时间模型、概念地图、反馈回路、适用范围边界
- 输出格式：TikZ/PDF（用于 LaTeX 稿件）或 Mermaid/SVG
- 期刊定制排版（Nature、ASR/AJS、Science Advances）

**与其他技能的区别：**
- `/scholar-hypothesis` 从既有理论中挑选，以推导可检验假设
- `/scholar-causal` 为因果识别策略构建 DAG
- `/scholar-conceptual` 构建理论本身及其可视化表达

---
### 3. 研究设计 — `/scholar-design`

```
/scholar-design causal identification for segregation-health link using panel data
/scholar-design conjoint experiment on racial bias in hiring decisions
```

推荐识别策略（FE、DiD、IV、RD、实验），运行统计功效分析（附 R `pwr` 包语法），
设定分析模型，并标出必需的稳健性检验。

---

### 4. 因果推断 — `/scholar-causal`

```
/scholar-causal segregation → health; DiD design; SES confounder
/scholar-causal education → earnings; IV using distance to college; ability confounder
/scholar-causal minimum wage → employment; staggered DiD; Callaway-Sant'Anna
/scholar-causal policy adoption → outcomes; synthetic control; single treated state
/scholar-causal income → health; causal mediation via stress; ACME decomposition
```

在一个技能里提供完整的因果推断工具箱：
1. **DAG** — 绘制文本化 DAG，识别后门路径，给出最小调整集
2. **策略选择** — 8 策略决策树（OLS、DiD、RD、IV、FE、匹配、合成控制、中介分析）
3. **深度解析** — 针对所选策略：假设、标准流程、诊断、R 代码、Stata 代码、写作模板、常见陷阱
4. **敏感性分析** — Oster delta、E 值、Rosenbaum 界、安慰剂检验、中介分析的 ρ*
5. **识别论证** — 可直接粘贴的 Methods 段落

---

### 5. 数据收集与开放数据目录 — `/scholar-data`

```
/scholar-data find dataset for immigration and labor market outcomes
/scholar-data dataset for cross-national attitudes toward democracy
/scholar-data design a survey on neighborhood stress and health for NHANES sample
/scholar-data interview protocol for undocumented immigrants and labor market experiences
```

**开放数据目录**收录 14 大类 100+ 数据集：社会学/分层、人口学/健康、教育、
政治行为、移民/族群、社区/空间、文本/数字/计算、犯罪/司法、跨国调查
（ESS、WVS、Afrobarometer、Eurobarometer、DHS、PISA）、经济/劳动/宏观
（FRED、OECD、Eurostat、Penn World Table）、全球健康/环境（WHO、GBD、FAOSTAT）、
科学计量学（OpenAlex、Semantic Scholar、Crossref），以及 14 个通用存储库
（Harvard Dataverse、ICPSR、Zenodo、OSF、Figshare、Data.gov、Kaggle、
Google Dataset Search）。

**自动抓取**：针对 25+ 个无需 API 密钥的数据源，技能可直接把数据下载到 `data/raw/`，
使用 R 包（`gssr`、`tidycensus`、`WDI`、`eurostat`、`openalexR`、`essurvey`、`dataverse`）
或 Python（OpenAlex、WHO GHO、Eurostat、Zenodo、Harvard Dataverse 的 REST API）。

还可生成调查问卷、访谈提纲、码本模板、IRB 检查清单
（豁免/加急/全面审查判定）、数据管理计划、网络爬虫流水线，
以及 R 或 Stata 的清洗代码。

---

### 6. 探索性数据分析 — `/scholar-eda`

```
/scholar-eda run pre-analysis on panel dataset before modeling
/scholar-eda missing data diagnosis for NLSY97 with 20% attrition
```

指导缺失数据诊断（MCAR/MAR/MNAR 检验；MAR 情形推荐 `mice`）、
分布检查、离群值检测、共线性筛查，并产出预分析计划备忘录，
在运行主模型前锁定各项分析决策。

---

### 7. 数据分析 — `/scholar-analyze`

```
# With dataset path + model specification
/scholar-analyze data.csv, OLS of earnings on education by race for Demography
/scholar-analyze nhanes_panel.dta, fixed effects model of activity space on BMI for ASR
/scholar-analyze survey.csv, logit of political participation on neighborhood SES by gender for AJS
/scholar-analyze nlsy.rds, Oaxaca-Blinder decomposition of racial wage gap for Demography
```

**三种输入方式：**
- **文件路径**：`data.csv`、`panel.dta`、`clean.rds`
- **内联/粘贴数据**：直接粘贴 CSV 行或变量摘要——技能会写入临时文件并加载
- **在线数据源**：说出公开数据集名称，技能自动抓取（NHANES、ACS/Census、GSS、World Bank、FRED、IPUMS extract、原始 GitHub/OSF URL）

**因果设计闸门**：如果参数中包含因果设计（DiD、FE、RD、IV、匹配、中介分析），
技能会**先暂停并调用 `/scholar-causal`**，确认 DAG 与识别策略后才运行任何模型。

**产出（保存到磁盘）：**
- `output/tables/table1-descriptives.html/.tex/.docx` — gtsummary 描述统计表
- `output/tables/table2-regression.html/.tex/.docx` — modelsummary 回归表
- `output/tables/table2-ame.html/.tex/.docx` — 平均边际效应（logit 模型）
- `output/tables/tableA1-robustness.html/.tex/.docx` — 稳健性检验
- `output/figures/fig-dist-outcome.pdf/.png` — 结果变量分布
- `output/figures/fig-coef-plot.pdf/.png` — 系数森林图
- `output/figures/fig-ame-[x].pdf/.png` — 边际效应图（logit 模型）
- `scholar-analyze-[topic]-[date].md` — 分析摘要 + 结果初稿

**能力范围：**
- **Component A — 分析**：OLS（HC3 标准误）、面板 FE（`fixest`）、logit/probit + AME（`marginaleffects`）、有序 logit、多层模型（`lme4`）、生存分析（Cox PH）、负二项回归；完整诊断；Oster (2019) 敏感性分析；Oaxaca-Blinder 分解
- **Component B — 可视化**：分布图、小提琴+箱线图、系数/森林图、边际效应图、预测概率图、事件研究（DiD）、RD 图、love plot（匹配）、Kaplan-Meier 曲线；全部以 300 DPI 保存为 PDF + PNG，使用 `theme_Publication()`
- **Component C — 结果写作**：按期刊校准的行文模板（ASR/AJS 用 AME 表述，NHB 用 95% CI，Demography 用分解表述）；期刊特定的篇幅规范

---

### 8. 计算方法 — `/scholar-compute`

```
/scholar-compute run STM topic model on news corpus about neighborhood conditions
/scholar-compute Double ML for heterogeneous treatment effects in mobility study
/scholar-compute ERGM for friendship network in high school panel
```

10 个模块：NLP（STM、BERTopic、Wordfish/Wordscores、BERT、conText 嵌入回归、带 DSL 偏差校正的 LLM 标注）、机器学习（Double ML、因果森林、brms/Stan 贝叶斯）、网络（ERGM、SAOM、goldfish REM）、ABM（Mesa、NetLogo/nlrx、LLM 驱动的智能体）、可复现性（renv、Docker、Makefile）、计算机视觉（DINOv2、CLIP、ConvNeXt、多模态 LLM）、LLM 驱动分析（Pydantic 结构化抽取、CoT 编码、RAG）、合成数据（硅基抽样、人格模拟）、地理空间/空间分析（sf、tidycensus、spdep、Moran's I、LISA、空间模型）、音频数据（Whisper、pyannote、Essentia、音频 LLM）。

---

### 9. 写作 — `/scholar-write`

```
/scholar-write introduction on segregation and health for ASR
/scholar-write theory section linking stress process to cardiovascular outcomes
/scholar-write methods section for fixed effects panel design
/scholar-write discussion for Demography paper on mobility-based segregation
/scholar-write abstract for Science Advances structured format
```

起草之前会自动：
1. 阅读 `assets/index.md`，选出与任务最匹配的你已发表论文作为**语感参照**
   （例如：空间 + 健康类论文选用你自己的 *Demography* 论文）
2. 阅读一篇顶刊文章作为**结构深度参照**
   （例如：隔离研究选用一篇近期 *AJS* 论文）
3. 查询 **Zotero** 获取初稿可用的相关引文

可写章节：Introduction、Literature Review、Theory、Data & Methods、Results、
Discussion/Conclusion、Abstract。每一节交付时均为可发表水准的成稿，
附字数统计和期刊特定的格式说明。

**引文诚信：** scholar-write 对引文伪造执行零容忍规则。插入的每条引文都必须经
Zotero/CrossRef 验证，或承接自流程中先前阶段。无法核实的引文一律标记为
`[CITATION NEEDED]`，交由 `/scholar-citation` 后续处理。

---

### 9B. 验证 — `/scholar-verify`

```
/scholar-verify full output/drafts/full-paper-2026-03-10.md
/scholar-verify stage1
/scholar-verify numerics
/scholar-verify logic
```

对原始分析输出与稿件之间进行两阶段一致性检查，动用 4 个专职代理：

**Stage 1 — 原始输出 → 稿件表格/图形：**
- **verify-numerics**：逐单元格比对原始 CSV/HTML 表与稿件表格（转录错误、四舍五入、丢行）
- **verify-figures**：原始图形文件 vs. 稿件图题与描述（过期图、图题错配）

**Stage 2 — 稿件表格/图形 → 正文文字：**
- **verify-logic**：正文中每条统计陈述都回溯到某个表/图（数字误引、显著性错误、因果语言越界）
- **verify-completeness**：完整的产出物链条校验（孤立/缺失条目、编号、交叉引用）

**模式：** `full`（全部 4 个代理）、`stage1`、`stage2`、`numerics`、`figures`、`logic`、`completeness`

**输出：**
- 按严重度分级（CRITICAL / WARNING / INFO）的整合验证报告
- 修复清单，含确切位置与更正指引
- ★★ 标记：由 2 个以上代理同时标出的问题（置信度最高）
- 结论：READY FOR SUBMISSION / REVISIONS NEEDED / MAJOR ISSUES — DO NOT SUBMIT

**与其他技能的集成：**
- 作为 `/scholar-write` 的 Step 5b 自动运行（stage2，以存在原始输出为条件）
- 作为 `/scholar-respond` REVISE 模式的 Step 3b 运行（full，R&R 修改之后）
- 作为 `/scholar-journal` Step 6b 第 6 项运行（full，投稿前闸门）
- 建议在 `/scholar-analyze` 之后运行（stage1，尽早发现输出问题）
- 由 `/scholar-replication` 消费（验证清单条目）

---

### 9C. 代码审查 — `/scholar-code-review`

```
/scholar-code-review full output/scripts/
/scholar-code-review correctness output/scripts/02-analysis.R
/scholar-code-review data-handling output/scripts/01-clean.R
```

对项目中产生的全部分析脚本进行系统化多代理代码审查。6 个专职代理并行、从不同角度审阅每个脚本：

1. **正确性与逻辑**：bug、差一错误、错误连接（join）、筛选失误、逻辑流错误
2. **稳健性与防御式编程**：脆弱模式、硬编码值、缺失的错误处理、边界情形
3. **统计实现**：模型设定与设计文档一致、标准误正确、权重/聚类/分层处理得当、假设检验到位
4. **可复现性与可复制性**：随机种子、绝对路径、环境记录、输出确定性
5. **代码风格与 AI 反模式**：AI 生成代码的坏味道（幻觉包名、复制粘贴残留、未用变量、命名不一致）
6. **数据处理与变量构造**：类别编码错误、错误重编码、缺失值处理不当、样本限制与码本不符

**模式：** `full`（全部 6 个代理）、`correctness`、`robustness`、`statistics`、`reproducibility`、`style`、`data-handling`

**输出：**
- 按严重度分级（CRITICAL / WARNING / INFO）的整合审查报告
- 每脚本记分卡（PASS / NEEDS-REVIEW / FAIL）
- 修复清单，含确切文件路径、行号和代码片段
- 只读——只诊断，不修改任何脚本

**运行时机：** 在 `/scholar-analyze`、`/scholar-compute` 或 `/scholar-eda` 之后运行，在起草稿件之前捕获编码错误。

---

### 9D. 通过 OpenAI Codex 进行外部审查 — `/scholar-openai`

```
/scholar-openai full output/drafts/full-paper-2026-03-10.md
/scholar-openai code output/scripts/
/scholar-openai stats output/drafts/results-section.md
```

启动多个并行的 OpenAI Codex CLI 代理（`codex exec`）独立审查你的项目。每个代理都在沙箱中运行，读取项目文件，并将结构化审查报告写入磁盘。随后 Claude 将所有报告综合为一份整合审查。

**5 个代理：**
- **A1 — 代码正确性**：逻辑错误、错误连接、筛选失误
- **A2 — 代码稳健性**：脆弱模式、硬编码值、边界情形
- **A3 — 代码风格**：AI 反模式、未用变量、命名一致性
- **A4 — 统计一致性**：稿件数字与原始输出吻合、表格转录
- **A5 — 逻辑与解读**：正文断言有表/图支撑、因果语言

**模式：** `full`（全部 5 个代理）、`code`（A1–A3）、`stats`（A4）、`logic`（A5）、`custom`（用户自定义提示）

**输出：**
- 各代理报告存于 `output/reviews/`
- 整合审查，含严重度分级的问题清单与修复清单
- 只读——只诊断，不修改任何项目文件

**前置条件：** 需已安装 OpenAI Codex CLI（`npm install -g @openai/codex` 或 `brew install codex`）并设置 `OPENAI_API_KEY`。

---

### 10. 引文管理 — `/scholar-citation`

```
/scholar-citation insert ASA citations and build reference list for my draft
/scholar-citation audit manuscript for orphan citations and missing references
/scholar-citation convert reference list from APA to ASA author-date style
```

#### 绝对规则：绝不伪造引文

每条参考文献都必须经 7 层验证体系（Zotero → CrossRef → Semantic Scholar → OpenAlex → Google Scholar → WebSearch）确认真实存在后方可纳入。无法核实的来源一律标记为 `[SOURCE NEEDED]`——绝不冒充真实文献插入。该规则适用于全部六种模式。

#### 六种模式

**`insert`** — 用于有论断但尚无引文的稿件：
1. 在 Zotero 文献库中检索与每条论断匹配的、经核实的书目元数据
2. 库中没有的条目回退到 CrossRef API
3. 在全文中插入样式正确的文内引用
4. 构建完整参考文献表（每条文内引用 → 一条文献条目；不留孤引）
5. 找不到可核实来源的论断标记为 `[SOURCE NEEDED: describe evidence type]`

**`audit`** — 用于已有引文、需要一致性检查的稿件：
1. 核对每条文内引用都出现在参考文献表中
2. 核对参考文献表中每个条目都在正文中被引用
3. 检查作者姓名拼写在正文与文献表间的一致性
4. 标记同作者同年份、需要 `2020a`/`2020b` 消歧的情形
5. 交叉核对括注引用中的出版年份与参考文献表
6. 返回记录所有不匹配之处的引文审计日志

**`convert-style`** — 用于需要重排引文格式的稿件：
1. 检测当前引文样式
2. 将全部文内引用和整个参考文献表转换为目标样式
3. 支持 ASA ↔ APA ↔ Chicago author-date ↔ 编号制（Science/Nature 系期刊）

**`full-rebuild`** — 端到端引文流水线（顺序运行所有模式）：
1. 审计现有引文 → 盘点论断 → 检索 Zotero + CrossRef → 插入引文 → 组装参考文献表 → **核实全部文献** → 运行最终审计
2. 保存两个文件：引文齐备的定稿 + 附验证结果的审计日志

**`verify`** — 将每条参考文献逐一对照数据库进行系统核实：
1. 把全部参考文献提取为结构化清单
2. **Tier 1 — 本地文献库：** 逐条核对你本地的 Zotero、Mendeley、BibTeX 或 EndNote
3. **Tier 2a — CrossRef：** 未匹配条目经 CrossRef API 核对（按 DOI 或标题+作者）
4. **Tier 2b — Semantic Scholar：** 剩余条目经 Semantic Scholar API 核对（预印本、工作论文、引用图谱）
5. **Tier 2c — OpenAlex：** 剩余条目经 OpenAlex API 核对（开放元数据，2.5 亿+ 文献）
6. **Tier 3 — WebSearch：** 剩余条目经网络检索核对（书籍、报告、预印本）
7. 为每条指派状态：`VERIFIED-LOCAL` / `VERIFIED-CROSSREF` / `VERIFIED-S2` / `VERIFIED-OPENALEX` / `VERIFIED-WEB` / `CORRECTED` / `UNVERIFIED`
8. 发现出入时依据权威来源更正元数据（年份、卷、页码、DOI）
9. **删除或标记 UNVERIFIED 文献**——绝不悄悄纳入
10. 产出验证报告，含每条状态和全部查询记录
11. 可选 `verify-claims` 标志：检查 PDF 内容，确认被引来源确实支持具体论断

**`export`** — 从参考文献表生成 BibTeX `.bib` 文件：
1. 将参考文献表解析为结构化字段
2. 将每条文献映射到 BibTeX 条目类型（`@article`、`@book`、`@incollection` 等）
3. 生成引用键（AuthorYear 格式，带消歧后缀）
4. 从 Zotero/CrossRef 补全元数据（DOI、摘要、关键词）
5. 将 `.bib` 文件保存到 `output/citations/`

#### 支持的引文样式

| 期刊系 | 样式 |
|---------------|-------|
| ASR, AJS, Demography, Social Forces | ASA author-date |
| Sociological Quarterly, SSR | ASA author-date |
| APSR, AJPS | APSA（author-date；章节用 "ed."；DOI 写完整 URL） |
| Language in Society, J. Sociolinguistics | Unified Linguistics（标题小写；不要求 DOI） |
| PNAS | Author-date（NAS 样式） |
| Science Advances | 编号上标 |
| Nature Human Behaviour, Nature Comp. Science | 编号上标 |
| American Journal of Public Health | Vancouver 编号制 |

#### 输出文件

保存 2–3 个文件到 `output/citations/`（EXPORT 模式另加 `.bib`）：
- `scholar-citation-[slug]-[date]-draft.md` — 引文齐备的文本 + 完整参考文献表
- `scholar-citation-[slug]-[date]-log.md` — 审计日志，含 Zotero/CrossRef 查询、验证结果、SOURCE NEEDED 条目
- `scholar-citation-[slug]-[date]-verification.md` —（MODE 5 独立运行时）每条验证状态 + 元数据更正

---
### 10B. 知识图谱 — `/scholar-knowledge`

```
/scholar-knowledge ingest from zotero collection segregation
/scholar-knowledge ingest doi 10.1093/sf/soaa123
/scholar-knowledge ingest from url https://arxiv.org/abs/2402.12345
/scholar-knowledge ingest from output output/lit-review-2026-04.md
/scholar-knowledge search theories of spatial assimilation
/scholar-knowledge search methods difference-in-differences
/scholar-knowledge relate Massey 1993 contradicts Clark 1986
/scholar-knowledge status
/scholar-knowledge export for mobility-health project as markdown
/scholar-knowledge compile                                    # build Obsidian-compatible wiki
/scholar-knowledge compile full                                # force full rebuild (default: incremental)
/scholar-knowledge ask what are the main theories of segregation?
/scholar-knowledge ask compare mechanisms in Massey 1993 vs Clark 1986
/scholar-knowledge re-extract all abstract_only                # upgrade papers when PDFs become available
/scholar-knowledge re-extract doi 10.1093/sf/soaa123           # re-run extraction on one paper
```

一个**用户级、跨项目的知识图谱**，将提取出的学术内容——发现、机制、理论、方法与论文间关系——跨项目、跨会话持久保存。存储于 `~/.claude/scholar-knowledge/`（可经 `SCHOLAR_KNOWLEDGE_DIR` 配置）。它叠加在 Zotero 之上：Zotero 存书目元数据；知识图谱存你从每篇论文中提取和学到的东西。

**数据模型：** 三个 NDJSON 文件外加一个原始来源档案库：
- `papers.ndjson` — 论文元数据 + 提取的发现/理论/方法（现含 `raw_path`、`extraction_tier`、`limitations`、`future_directions` 字段）
- `concepts.ndjson` — 理论、方法、机制节点
- `edges.ndjson` — 论文间及论文-概念关系
- `raw/` — 只增档案库：`pdfs/`（Zotero 符号链接）、`abstracts/`、`api-responses/`、`web/`（URL 摄入）、`images/`（PDF 图形提取）
- `wiki/` — 编译出的 Obsidian 兼容 markdown wiki（MODE 6 输出）

#### 八种模式

**`ingest`** — 添加论文并提取学术内容：
- 来源：Zotero（收藏夹/标签/检索）、PDF 文件、DOI 查询、**URL（`from url [URL]`）**、**lit-review 或 analyze 输出文件（`from output [path]`）**、手动录入
- 提取：关键发现、理论框架、方法、机制、适用范围条件、局限、未来方向
- 将原始来源归档到 `raw/` 并记录 `extraction_tier`（`abstract_only` / `full_pdf`）
- 与图谱中已有条目去重
- 每次摄入后自动增量更新已编译的 wiki（Karpathy 原则：wiki 由 LLM 维护，用户几乎不直接动它）

**`search`** — 查询知识图谱：
- 按主题、作者、理论、方法、发现、局限或未来方向
- 特殊查询：`contradictions`、`gaps`、`methods for [topic]`、`limitations of [topic]`、`opportunities in [topic]`
- 返回结构化结果，含论文元数据 + 提取内容

**`relate`** — 添加或查看论文间关系：
- 关系类型：`cites`、`contradicts`、`extends`、`replicates`、`uses-method`、`uses-theory`
- 查看某篇论文的关系，或两篇论文之间的关系
- 构建引用链与理论谱系

**`status`** — 图谱统计与覆盖面板：
- 论文、概念、边的总数；wiki 页面数；上次编译时间戳
- 按主题、理论、方法的覆盖情况；近期新增；缺口分析

**`export`** — 导出项目专属子集：
- 格式：markdown 摘要、NDJSON、BibTeX
- 可按主题、日期范围、理论或方法过滤

**`compile`**（MODE 6）— **从 NDJSON 图谱生成可浏览的 Obsidian 兼容 markdown wiki**：
- **论文页**（`wiki/papers/[slug].md`）— 每篇论文一页，含提取的发现、理论、方法，以及指向概念和相关论文的 `[[wikilinks]]`
- **概念页**（`wiki/concepts/`）— 理论、方法、机制，附回链到使用它们的每篇论文
- **主题聚类**（`wiki/topics/`）— 基于论文相似度自动聚类的主题页
- **`wiki/index.md`** — 总控面板（总数、最新论文、热点主题）
- **`wiki/contradictions.md`** — 发现相互矛盾的论文汇总表
- **`wiki/gaps.md`** — 研究缺口与未来方向汇总
- **知识地图**（`wiki/knowledge-map.png`）— networkx/matplotlib 可视化
- 自动判断**增量编译**（仅上次编译以来的新论文）还是**全量重建**；传 `full` 可强制全量重建
- 用 **Obsidian** 打开生成的 `wiki/` 文件夹，即可使用图谱视图和回链导航

**`ask`**（MODE 7）— **基于已编译 wiki 回答复杂研究问题**：
- 读取综合后的 wiki（而非原始 NDJSON），因此答案会引用论文页和概念页
- 支持比较型、机制型、综合型问题（"compare X vs Y"、"why does Z happen?"、"summarize evidence on …"）
- 依据图谱覆盖度（支撑答案的论文与概念数量）给出置信水平
- 答案保存到 `wiki/answers/[slug].md`，成为 wiki 的一部分——问答反哺知识库的反馈回路

**`re-extract`**（MODE 8）— **对归档的原始来源重新运行提取**：
- 当 PDF 可用时（例如 Zotero 导入后）将论文从 `abstract_only → full_pdf` 升级
- 对既有论文应用新的模式字段（例如提取模板新增了 `limitations` 或 `future_directions`）
- 直接在原始档案上操作，无需重新下载任何内容

#### 与其他技能的集成

知识图谱存在时会被下游技能自动查询并**回写**（所有挂钩都有保护——没有图谱时技能照常工作）：

**查询挂钩：**
- **scholar-lit-review**（Step 1a-pre）：网络检索之前先查图谱
- **scholar-lit-review-hypothesis**（Step 0b-pre）：网络检索之前先查图谱
- **scholar-write**（Step 0 Tier 0）：起草时调取相关发现/理论作为上下文
- **scholar-hypothesis**（检索前）：调取理论框架与机制
- **scholar-citation**（Tier 0.5）：统一的 `scholar_search()` 先查图谱再查 Zotero

**跨技能回写挂钩**（v5.8.0 新增）：
- **scholar-analyze** — 发现随生成自动写入图谱
- **scholar-lit-review** — 综述过的论文与综合发现回流图谱
- **scholar-compute** — 计算结果与方法元数据写入图谱
- **scholar-respond** — 依据评审意见的修改更新既有论文节点

#### Obsidian 设置

推荐的 Obsidian 库配置见 `.claude/skills/scholar-knowledge/references/obsidian-setup.md`。将 Obsidian 指向 `~/.claude/scholar-knowledge/wiki/`（或你的 `$SCHOLAR_KNOWLEDGE_DIR/wiki/`），即可浏览论文页、概念页和回链图谱。

#### 配置

在 `.env` 中设置 `SCHOLAR_KNOWLEDGE_DIR` 可覆盖默认位置 `~/.claude/scholar-knowledge/`。知识图谱默认是用户级的（所有项目共享）。

---

### 11. 期刊格式化 — `/scholar-journal`

```
/scholar-journal prepare manuscript for Demography
/scholar-journal which journal for computational paper on mobility and segregation
```

五种模式：
- **FULL-PACKAGE**：完整投稿准备——结构审查 + 合规清单 + 投稿信 + 开放科学材料包
- **FORMAT-CHECK**：对照期刊要求审查现有稿件
- **COVER-LETTER**：起草按期刊校准的投稿信
- **SELECT-JOURNAL**：用 8 维评分量表推荐目标期刊（支持 15 种期刊：ASR、AJS、Demography、Science Advances、NHB、NCS、Social Forces、Language in Society、Gender & Society、APSR、JMF、PDR、SMR、Poetics、PNAS）
- **RESUBMIT-PACKAGE**：被拒后改投新期刊的材料准备

---

### 12. 开放科学 — `/scholar-open`

```
/scholar-open preregistration for fixed effects panel study
/scholar-open data sharing plan for survey with restricted interview data
/scholar-open replication package for computational paper with Twitter data
```

五种模式：PREREGISTER（OSF/AsPredicted/EGAP/Registered Reports + 二手数据预注册）、DATA-SHARE（FAIR 原则、sdcMicro 去标识化、存储库选择、各社交平台数据政策、经 HuggingFace Hub 的计算数据归档）、CODE-SHARE（renv+conda+Docker+Makefile 复现包、CITATION.cff、Zenodo DOI；消费 scholar-analyze/scholar-compute 产出的 `output/scripts/` 直接构建脚本归档）、FULL-PACKAGE（NSF/NIH DMP + CRediT + COI + IRB + OA 策略 + APC 减免）、REPLICATION-PACKAGE（审计：结构 + 洁净运行测试 + 数据合规）。

---

### 12B. 复现包 — `/scholar-replication`

```
/scholar-replication full for Demography
/scholar-replication build existing scripts in output/scripts/
/scholar-replication test clean-run validation of replication package
/scholar-replication verify paper-to-code correspondence audit
/scholar-replication archive prepare Zenodo deposit
```

**与 `/scholar-open` 的关键区别：**
- `/scholar-open` = 开放科学的*声明类事项*（预注册、数据共享政策、模板、审计清单）
- `/scholar-replication` = 复现包的*构建与验证*（组装、撰写文档、测试、核验、归档）

六种模式：

**`build`** — 组装复现包目录：
- 将 `output/scripts/` 中的脚本复制并重新编号到 `replication-package/code/`
- 生成 `00_master.R` 主控脚本
- 从主流水线（`output/tables/`、`output/figures/`）和 EDA 流水线（`output/eda/tables/`、`output/eda/figures/`）复制表格/图形
- 以 `scholar-write` 的产出物登记表作为表/图编号的权威对照
- 核验表格格式覆盖（HTML/TeX/docx 至少其一）与图形格式（PDF/PNG/SVG/EPS）
- 处理数据（公开 → 复制；受限 → 获取说明 + 经 `fabricatr`/`synthpop` 生成模拟数据；社交媒体 → 按平台条款仅存 ID）
- 记录运行环境（`renv::snapshot()` / `conda env export`）
- 生成 LICENSE（MIT + CC-BY-4.0）、CITATION.cff、Makefile、Dockerfile（NCS/计算类论文）

**`document`** — 生成完整文档：
- 遵循 AEA Social Science Data Editors 模板的 README（9 节：概览、数据来源、数据集清单、计算要求、程序说明、复现者操作指南、输出对应表、已知局限、参考文献）
- 数据码本及变量字典（有 `skimr` + `labelled` 时自动从数据生成）
- 计算要求文档（软件、硬件、运行时长、随机种子）
- 脚本依赖图

**`test`** — 洁净运行验证：
- 预检：文件存在性、语法校验、无绝对路径、随机种子、README 完整性
- 环境隔离：在全新目录中还原 `renv.lock` / `environment.yml`（或 Docker 构建）
- 执行主控脚本，为每个子脚本计时并记录日志
- 将复现输出与原始输出比对——同时覆盖主流水线（`output/tables/`、`output/figures/`）与 EDA（`output/eda/tables/`、`output/eda/figures/`）目录
- 生成 `TEST-REPORT.md`，含每脚本 PASS/FAIL 状态与总体结论

**`verify`** — 论文-代码对应审计：
- 有产出物登记表（来自 `scholar-write`）时以其为权威依据
- 从稿件中提取全部表格、图形、占位标记（`[Table N about here]`）和文内统计量
- 将每条内容映射到生成它的脚本 + 输出文件（含 EDA/附录输出）
- 标记 MAPPED / PARTIAL / UNMAPPED 条目；与登记表交叉核对 ORPHAN（有输出、未被引用）和 MISSING（被引用、无输出）条目
- 生成 `VERIFICATION-REPORT.md`，含完整度得分与未映射条目的补救方案

**`archive`** — 存储库存缴准备：
- 存缴前清理（删除测试产物、`.DS_Store`、`__pycache__`）
- 期刊定制的存储库推荐（NCS→Zenodo+CodeOcean；APSR→Harvard Dataverse；AJS→AJS Dataverse；一般→Zenodo）
- GitHub release + Zenodo DOI 集成操作说明
- 存缴元数据模板（标题、含 ORCID 的作者、摘要、关键词、许可证）
- 存缴后清单（DOI 写入 CITATION.cff + README + 稿件）

**`full`**（默认）— 顺序运行所有模式：BUILD → DOCUMENT → TEST → VERIFY → ARCHIVE。

**输出文件：**
- `replication-package/README.md` — 完整的 AEA 模板 README
- `replication-package/TEST-REPORT.md` — 洁净运行测试结果
- `replication-package/VERIFICATION-REPORT.md` — 论文-代码对应审计
- `output/replication/replication-report-[slug]-[YYYY-MM-DD].md` — 内部日志

---

### 13. 同行评审 — `/scholar-respond`

五种模式：

**投稿前——模拟同行评审：**
```
/scholar-respond simulate paper.pdf for Demography
```
启动 3–4 个按目标期刊校准的并行评审代理（方法、理论、资深编辑，计算类论文另加计算评审）。返回严重度×置信度矩阵、修改路线图和模拟编辑决定。

**收到评审意见后——起草回复信：**
```
/scholar-respond respond reviews.txt paper.pdf
```
将每条意见分类（MAJOR-FEASIBLE、MINOR、DISAGREE、INFEASIBLE），起草逐条回复，
并针对评审人之间相互冲突的要求提供各情形的模板措辞。

**收到 R&R 决定后——修改稿件：**
```
/scholar-respond revise paper.pdf reviews.txt response.txt
```

**收到 R&R 决定后——单独的投稿信：**
```
/scholar-respond cover-letter paper.pdf for R1 to Demography
```

另涵盖：被拒后的改投策略（判定决定类型 → 诊断根本原因 → 按子领域的期刊阶梯 → 为新期刊重写导言）。

---

### 14. 质性研究方法 — `/scholar-qual`

```
/scholar-qual open-coding transcripts/*.txt grounded theory
/scholar-qual thematic-analysis interviews/*.txt for ASR
/scholar-qual content-analysis media-articles/*.txt systematic
/scholar-qual llm-coding transcripts/*.txt using existing codebook codebook.md
/scholar-qual mixed-methods qual-data/*.txt with survey-results.csv joint-display
```

7 个工作流：码本开发、扎根理论（开放 → 主轴 → 选择性编码）、反身性主题分析（Braun & Clarke 六阶段）、系统内容分析（Krippendorff）、LLM 辅助质性编码（含人工验证与评分者间信度）、评分者间信度（Krippendorff's alpha、Fleiss' kappa、Gwet's AC1）、混合方法整合（案例选择、联合展示、质性到定量转换）。

---
### 14b. 项目初始化 — `/scholar-init`（v5.9.0）

```
# Create a fresh project (copies raw files into data/raw/ by default)
/scholar-init nhanes-bmi ~/Downloads/nhanes-2017.csv materials/codebook.pdf

# Same, but symlink raw files instead of copying
bash scripts/init-project.sh --dest ~/research --link nhanes-bmi ~/Downloads/nhanes-2017.csv

# Resolve NEEDS_REVIEW entries interactively
/scholar-init review

# Ingest new files into an existing project
/scholar-init add ~/Downloads/new-wave.csv

# Check current state
/scholar-init status
```

**它做什么。** 搭建标准项目布局，摄入原始文件，用 `scripts/gates/safety-scan.sh` 逐一扫描（装有 Presidio 时用 Presidio 后端，否则用正则），并写入 `.claude/safety-status.json` —— 一个按文件记录 `SAFETY_STATUS` 的边车文件（sidecar），PreToolUse 钩子在每次 `Read` / `NotebookRead` / `Grep` / `Glob` 调用时都会查询它。

```
<dest>/<slug>/
├── README.md                 ← teaches the researcher how the project works
├── .claude/
│   └── safety-status.json    ← per-file SAFETY_STATUS (CLEARED / LOCAL_MODE / ANONYMIZED / OVERRIDE / HALTED / NEEDS_REVIEW:*)
├── data/
│   ├── raw/                  ← copies (or symlinks with --link) of ingested files
│   ├── interim/              ← scripts write here
│   └── processed/            ← analytic datasets
├── materials/                ← codebooks, questionnaires, protocols
├── output/                   ← scripts write results here
└── logs/
    └── init-report.md        ← permanent ingest record
```

**它为何存在。** v5.9.0 之前，涉数据技能通过 `Read` 工具加载文件，而这会把文件内容发送到 Anthropic API。对于受 IRB 保护的访谈、受限的 NHANES/PSID 数据、受 HIPAA 约束的健康记录以及任何含 PII 的文件，这是一个随时可能发生的数据使用协议违规。`/scholar-init` 是这一修复的摄入端：每个进入 `data/raw/` 的文件都先经扫描分诊，然后下游技能才可能接触它。交互式 `review` 模式带你逐条处理每个 `NEEDS_REVIEW` 条目——这正是 README 伦理使用章节所说的"慢下来、由你决定"的环节，让你始终留在决策环内。

**五种 `SAFETY_STATUS` 处置取值，外加过渡态 `NEEDS_REVIEW`（定义于 `.claude/skills/_shared/data-handling-policy.md`）：**

| 状态 | 含义 | 下游技能可以做什么 |
|---|---|---|
| `CLEARED` | 安全、开放数据 | 正常读取（允许 Read 工具） |
| `LOCAL_MODE` | 敏感，必须留在本地 | 仅限 Bash 的 `Rscript -e` / `python3 -c` heredoc，只输出汇总结果；禁用动词：`head(df)`、`print(df)`、`View(df)`、`df.head()`、`df.sample()` |
| `ANONYMIZED` | 存在去标识化衍生文件 | 只读 ANONYMIZED 衍生文件；绝不读原始文件 |
| `OVERRIDE` | 研究者明确豁免扫描结论 | 在明确知情确认下读取。音频/视频/转写格式（`wav mp3 flac mp4 mov eaf textgrid cha ...`）**不可** `OVERRIDE`——即使边车文件写了 OVERRIDE，钩子也会拒绝 |
| `HALTED` | 禁止接触 | PreToolUse 钩子拒绝任何指向该文件的 `Read` / `Grep` / `Glob` 调用 |
| `NEEDS_REVIEW:<level>` | 待分诊（RED / YELLOW / BINARY / UNKNOWN） | PreToolUse 钩子一律拒绝，直到经 `/scholar-init review` 解决 |

**查询边车文件的 11 个涉数据技能：**
- **Tier A**（LOCAL_MODE 分派）：`scholar-analyze`、`scholar-eda`、`scholar-compute`、`scholar-ling`、`scholar-qual`、`scholar-brainstorm`
- **Tier B**（边车检查 + 快速失败拒绝）：`scholar-data`、`scholar-verify`、`scholar-replication`、`scholar-code-review`、`scholar-write`

**关于刻意排除的说明。** 本仓库不捆绑 `scholar-full-paper`（见 README 的 "Note on the Full-Paper Orchestrator"）。`scripts/gates/init-handshake.sh` 辅助脚本作为独立脚本随附，但仓库内没有调用方——这里没有任何编排器依据它分派。边车 + 钩子对上述 11 个模块化技能完全生效。

**快速上手：**

```
bash scripts/init-project.sh --dest ~/research nhanes-bmi ~/Downloads/nhanes.csv
cd ~/research/nhanes-bmi
/scholar-init review                      # resolve each NEEDS_REVIEW entry
/scholar-eda data/raw/nhanes.csv          # proceeds under the sidecar-recorded status
/scholar-analyze ...                      # inherits the same decisions
```

---

### 15. 数据安全 — `/scholar-safety`

```
# Scan a data file before analysis (local scan — no file content read by Claude)
/scholar-safety scan data/interviews.csv

# Safety gate before loading data for scholar-eda or scholar-analyze
/scholar-safety gate about to load nhanes_restricted.dta for regression analysis

# Generate a full project data safety protocol
/scholar-safety protocol segregation-health project, NHANES restricted, IRB expedited

# Check what has been logged
/scholar-safety status
```

**它解决的核心问题：** 当 Claude Code 对数据文件使用 `Read` 工具或 `Bash cat` 命令时，整个文件内容都会被传输到 Anthropic 的 API 服务器。对受限数据集（NHANES、PSID、NLSY、Census RDC）、受 HIPAA 约束的健康数据、访谈转写文本或受 IRB 保护的参与者数据而言，这种传输可能违反数据使用协议、IRB 方案或隐私法规（GDPR、HIPAA）。

**工作原理：**
1. 在本地对数据文件运行 `Bash grep -c` 模式扫描——只返回匹配*计数*；扫描过程中敏感值本身绝不进入 Claude 的上下文
2. 用综合评分矩阵将每个文件分级为 LOW / MEDIUM / HIGH 风险
3. HIGH 风险：显示完整警告及具体命中标志，暂停，给出四个选项
4. MEDIUM 风险：显示注意事项并要求确认
5. LOW 风险：记录绿灯并继续

**检测到风险时的三种应对选项：**
- **[B] ANONYMIZE** — 生成可直接运行的 R 匿名化脚本（去除全部 18 项 HIPAA 标识符、将参与者 ID 替换为顺序标签、粗化地理与日期）
- **[C] LOCAL MODE** — 生成只输出汇总结果（均值、标准差、回归系数、表格）的 Bash/R 脚本——原始数据绝不进入 Claude 上下文；研究者只粘贴打印出的结果
- **[A] HALT** — 停止全部操作；提供 IRB 修正模板与数据处理指引

**输出文件：**
- `output/logs/scholar-safety-log.md` — 每次扫描、风险级别与许可决定的持续日志
- `output/protocols/scholar-safety-protocol-[slug]-[YYYY-MM-DD].md` — 完整的项目安全协议（MODE：`protocol`）

**它能检测什么（本地进行，文件内容不进入 AI 上下文）：**
- SSN 模式、电子邮箱、电话号码、街道地址
- HIPAA/PHI：诊断代码、病历、用药、临床术语
- 心理健康：抑郁、自杀、精神科、物质使用
- 法律/移民身份：无证件、犯罪记录、驱逐出境
- 受限数据标志：NHANES、PSID、NLSY、IPUMS、DUA、restricted-use
- 细粒度地理数据：GPS 坐标、普查区、地理编码
- IRB 参与者标志：参与者 ID、知情同意、访谈、转写

**机械化执行。** `scripts/gates/pretooluse-data-guard.sh` 由 `setup.sh` 注册为 PreToolUse 钩子——Claude Code 下写入 `~/.claude/settings.json`，ZCode 下写入 `~/.zcode/cli/config.json`（`.hooks.events.PreToolUse`）；Codex 下则由 `/scholar-init` 按项目安装（`<project>/.codex/config.toml`）。用 `setup.sh --harness claude|codex|zcode|all` 指定目标，默认自动检测。PostToolUse 输出脱敏器仅限 Claude Code：Codex 与 ZCode 无法改写 Bash 输出，在这两种宿主上处理受限数据应使用 Lockdown 级别。凡目标文件的边车状态为 `NEEDS_REVIEW:*` 或 `HALTED`，一律拒绝——即使某个子技能忘了检查，钩子也会在不安全访问抵达 API 之前将其拦下。它现已覆盖两个过去敞开的通道：

- **Bash** — 一个*面向配合型代理的减速带*：拦截对敏感路径的明显内容倾倒命令（`cat`/`head`/`tail`/`sed`/`awk`/行级 `grep`/`sqlite3`/python·R 行倾倒），同时放行获准的 LOCAL_MODE `Rscript -e`/`python3 -c` 汇总加载器。它**不是一堵墙**——其他解释器、编码手法和变量拼接路径都能绕过。在 **strict** 级别，PostToolUse 钩子（`posttooluse-output-guard.sh`）会额外对 Bash *输出*中的 PII/批量行做脱敏。
- **Edit/Write** — 拦截对 `.claude/safety-status.json` 的篡改（在没有 `/scholar-init review` 溯源记录的情况下把受限文件改成 `CLEARED`/`OVERRIDE`）。

**安全级别**（`/scholar-safety level <standard|strict|lockdown>`，以 `_safety_level` 存入边车文件）：**standard** = Bash 减速带 + 边车防篡改；**strict** = 另加 PostToolUse 输出脱敏器；**lockdown** = 另加 OS 沙箱（内核级强制的墙，由 `generate-lockdown-config.sh` 按项目自动生成）。standard 和 strict 是防意外/配合型泄漏的护栏，**不是**墙。

**Codex 主机下的执行。** 上述钩子是 Claude Code 专属；Codex 主机不读 `~/.claude/settings.json`。当 `/scholar-init` 检测到 Codex（或未知）主机时，会把同一守卫安装为 Codex PreToolUse 钩子（`<project>/.codex/config.toml` 中的 `[hooks.PreToolUse]` → `scripts/gates/codex-pretooluse-hook.sh`，委托给守卫脚本）。在 Codex 中**信任该项目**后生效；项目的 `AGENTS.md` 承载过渡期的自我约束契约。

**Lockdown——OS 之墙。** `/scholar-safety level lockdown` 运行 `scripts/gates/generate-lockdown-config.sh`，为检测到的主机写入对数据目录的 OS 沙箱读取拒绝：Claude Code → `<proj>/.claude/settings.json` 中的 `sandbox.filesystem.denyRead`（Seatbelt/Landlock；**重启**后生效）；Codex → `<proj>/.codex/config.toml` 中的 `[permissions]` `"data"="deny"` 配置（**信任**项目后生效）。已验证：沙箱内 `cat data/raw/*.csv` 返回 `Operation not permitted`，零泄漏。默认（`allowUnsandboxedCommands:false`）连获准的 LOCAL_MODE `Rscript` 读取也一并阻断——请先完成分析再上锁，或用 `--allow-escalation` 保留一个需人工批准的逃生口。

> **两个激活时的注意点。**（1）钩子配置在会话启动时快照——修改 `settings.json` 后必须**重启** Claude Code 才生效。（2）Claude Code 以 shell 命令行方式运行钩子 `command`，若仓库路径含空格（如 Google Drive 安装位置），命令必须加引号包裹（`"command": "bash '<path>'"`）；裸的含空格路径会静默执行失败，守卫对*所有*工具形同虚设。`setup.sh` 会自动写入带包裹的形式。

---

### 16. 研究伦理 — `/scholar-ethics`

```
# Pre-submission comprehensive ethics check
/scholar-ethics full paper.pdf for Nature Human Behaviour

# AI tool data privacy audit
/scholar-ethics ai-audit used Claude Code and ChatGPT for analysis and writing

# Plagiarism and originality check
/scholar-ethics plagiarism paper.pdf for ASR; prior conference paper exists

# Research authenticity audit (p-hacking, HARKing, data integrity)
/scholar-ethics integrity results suggest p-hacking concern; multiple DVs tested

# General ethics compliance (IRB, authorship, COI, data sharing)
/scholar-ethics general for Demography; survey data; 3 authors; NSF funded
```

四种模式，可单独运行也可组合运行：

**MODE 1 — AI 工具数据隐私审计：**
记录各研究阶段使用了哪些 AI 工具（Claude Code、ChatGPT、GitHub Copilot 等），评估每类共享数据的隐私风险，检查 GDPR / HIPAA / 数据使用协议合规性，并起草期刊要求的 AI 使用披露声明。涉及敏感数据时推荐本地 LLM 替代方案（Ollama）。

**MODE 2 — 抄袭与原创性检查：**
逐节原创性审读；自我抄袭与文字复用评估（对照期刊具体政策）；AI 生成文本评估与披露要求；相似度分数（iThenticate / Turnitin）解读指南；可直接粘贴进投稿信的原创性声明。

**MODE 3 — 研究真实性审计：**
对数据收集、分析、报告全程运行 QRP（可疑研究实践）筛查。检测 p-hacking 迹象；生成多重宇宙分析与设定曲线的 R 代码。检查 HARKing 并给出补救措辞。数据造假交叉核验方案（Benford 定律、GRIM 检验、溯源核对）。结果误读审计：观察性研究中的因果语言、统计显著性 vs. 实质显著性、多重比较、过度概括。产出研究诚信自我声明。

**MODE 4 — 一般伦理标准：**
IRB 判定清单（豁免/加急/全面审查）；知情同意要素核对；CRediT 作者贡献声明；利益冲突披露；针对目标期刊的数据可用性声明；AI 使用声明。Nature、Science Advances、ASR、AJS、Demography 的期刊伦理合规清单。

**输出文件：**
- `scholar-ethics-log-[slug]-[YYYY-MM-DD].md` — 内部清单，逐项 PASS/FLAG
- `scholar-ethics-report-[slug]-[YYYY-MM-DD].md` — 按目标期刊排版、可直接粘贴的全部声明文本

---

### 17. 社会语言学 — `/scholar-ling`

```
/scholar-ling variationist analysis of t-deletion in NYC corpus
/scholar-ling conversation analysis of patient-doctor interactions
/scholar-ling discourse analysis of immigration policy debates
/scholar-ling matched guise experiment for accent attitudes study
```

6 个模块：变异研究（Rbrul/VARBRUL/混合效应模型）、声学语音学（Praat/Parselmouth/librosa + 功效分析）、语料库语言学（quanteda、keyness G²、带流行度效应的 STM）、会话分析/话语分析（Jefferson 转写体系、CADS 工作流的计算 CDA + STM 框架分析 + LLM 修辞语式编码）、叙事/扎根理论/配对变语实验、计算社会语言学（conText 嵌入回归、语言学编码的 LLM 标注、BERT 分类、语义演变检测）。按期刊类型提供方法模板。

---

### 18. 协作管理 — `/scholar-collaborate`

```
/scholar-collaborate credit 4-author paper on immigrant integration
/scholar-collaborate tasks assign analysis and writing for 3-author team
/scholar-collaborate mentor guide PhD student through first solo publication
```

多作者协作管理：CRediT 角色分配（含学生主导、同等贡献、大型团队等特殊情形）、任务分派与追踪、合作者沟通模板、贡献记录、版本管理、冲突化解，以及面向学生合作者的指导框架。

---

### 19. 质量审计 — `/scholar-auto-improve`

```
/scholar-auto-improve observe output/drafts/
/scholar-auto-improve audit
/scholar-auto-improve improve
/scholar-auto-improve evolve
```

持续质量引擎，四种模式：

**`observe`** — 技能输出的事后审计。启动 3 个并行诊断代理（结构审计员、学术质量评审员、跨技能一致性检查员）评估最近一次技能输出。产出健康分（0–100：GREEN/YELLOW/RED）与改进建议。

**`audit`** — 技能套件结构健康检查。对所有技能的 SKILL.md 运行 10 项检查（A1–A10）：frontmatter 完整性、工具声明准确性、步骤编号、质量清单存在性、保存输出章节、参考文件、跨技能引用、绝对规则一致性、输出目录模式、多格式输出。启动 3 个审计代理（架构、标准合规、可用性）。

**`improve`** — 依据 audit/observe 发现生成修复。按严重度排序，经用户确认后生成修复，并做修复后验证。

**`evolve`** — 跨会话模式分析。回顾多个会话的改进日志，识别系统性问题并提出结构性改进。

也可作为单个技能的轻量级执行后钩子使用。

**输出文件：**
- `output/auto-improve/diagnostic-report-[date].md` — 健康分 + 问题清单
- `output/auto-improve/improvement-log.md` — 跨会话持续日志

### 20. 文档同步 — `/sync-docs`

```
/sync-docs slides.tex script.tex manuscript.tex
/sync-docs
```

在演示幻灯片、讲稿和论文之间同步内容。未提供路径时自动检测文档。

**它做什么：**
1. 识别所有相关文档（LaTeX/Beamer 幻灯片、讲稿、论文）
2. 审查过期引用、数字不一致、陈旧引文和版本不一致
3. 并行更新所有文件以保证一致
4. 将更新后的文档编译为 PDF

在修改了其中一个文档后使用（例如更新了幻灯片中的图），把变化传播到讲稿和论文。对求职报告和会议报告尤其有用——幻灯片、演讲备注与论文必须保持同步。

### 21. 文献监测 — `/scholar-monitor`

```
/scholar-monitor init                      # bootstrap ~/.claude/scholar-monitor/ with 22 starter sources
/scholar-monitor list                      # show configured sources + last-seen state + next-due dates
/scholar-monitor preview                   # dry-run — show what would fetch, no network calls, no state change
/scholar-monitor arxiv-llm                 # targeted fetch: one specific source, overrides cadence
/scholar-monitor all                       # force-fetch every enabled source, ignore cadence
/scholar-monitor                           # default: fetch all enabled sources where cadence has elapsed
/scholar-monitor configure delivery        # prompts for ntfy topic / Telegram chat_id / SMTP creds
/scholar-monitor add                       # add a new journal (by ISSN) or arXiv query interactively
/scholar-monitor remove arxiv-llm          # remove a source by id
/scholar-monitor status                    # dashboard: enabled sources, archive size, delivery channels, overdue sources
/scholar-monitor digest last-7             # regenerate markdown digest from archive (no re-fetch)
```

**它做什么：**

一个面向前沿的*现刊通报*信息流——与 `/scholar-lit-review` 的回溯式文献图景互为补充。每次调用：

1. 从每个 `cadence_days` 已到期的来源抓取新文献（或抓取你指定的某个来源）。
2. 与每来源最近 200 条 DOI/arXiv ID 以及整个知识图谱去重。
3. 为每篇论文生成摘要（基于标题 + 摘要的 2–3 句话）并按类别分组。
4. 将摘要写入 `output/monitor/feed-YYYY-MM-DD.md`。
5. 经 ntfy.sh 或 Telegram 推送通知到手机（可选），或经 SMTP 发邮件（可选）。
6. 将新论文自动写入 `scholar-knowledge`（`~/.claude/scholar-knowledge/papers.ndjson`），标记 `source: "scholar-monitor"` 与 `extraction_tier: "abstract_only"`——之后的 `/scholar-lit-review` 会在 Tier 0 直接读到它们。
7. 原子化更新状态，下一次调度从新水位线开始。

**起始源注册表（22 个来源，默认启用 3 个）：**

- **社会学顶刊：** ASR（开）、AJS、Social Forces、Social Problems、Annual Review of Sociology
- **人口学：** Demography、Population and Development Review
- **子领域：** Gender & Society、Sociology of Education、JMF、Ethnic & Racial Studies、Du Bois Review、Social Science Research、Sociological Methods & Research
- **跨学科：** Nature Human Behaviour（开）、Science Advances、Nature Computational Science、APSR、PNAS
- **预印本：** arXiv cs.CL + LLM 过滤（开）、arXiv cs.CY、arXiv econ.GN

在 `~/.claude/scholar-monitor/sources.json` 中把任意来源的 `enabled: true` 打开，或用 `/scholar-monitor add` 注册新来源。完整 ISSN 对照表与 arXiv 类别列表见 `references/registry-guide.md`。

**`/loop` 集成：**

```
/loop 24h /scholar-monitor arxiv-llm       # daily LLM preprint digest
/loop 7d /scholar-monitor                  # weekly sweep across all due sources
/loop 1h /scholar-monitor                  # harmless — cadence filter drops redundant ticks
```

每次运行都是幂等的。`cadence_days` 过滤意味着对周更来源跑 `/loop 1h` 每周只产出一份真实摘要，而不是 168 份。单个来源的失败（网络错误）不会推进该来源的游标——下一次调度会干净地重试。

**投递通道（可叠加）：**

| 通道 | 设置 | 适用场景 |
|---|---|---|
| **file**（始终开启） | 无需设置 | 审计留痕：`output/monitor/feed-YYYY-MM-DD.md` |
| **ntfy.sh** | `openssl rand -hex 8` → 粘贴到 app + `configure delivery` | 零鉴权手机推送，`/loop` 无人值守可用 |
| **Telegram** | 需要 Telegram MCP 插件 + 白名单设置 | 双向推送，支持文件附件 |
| **SMTP 邮件** | Gmail 应用专用密码 + `configure delivery` | 最通用但设置最多；凭据放环境变量，绝不进 config.json |

配置位于 `~/.claude/scholar-monitor/config.json`（`chmod 0600`）。状态位于 `~/.claude/scholar-monitor/state.json`。只增归档位于 `~/.claude/scholar-monitor/archive.ndjson`（超过 50 MB 时手动轮转——见 `references/registry-guide.md`）。

**与 `/scholar-lit-review` 并用，而非取而代之。** scholar-lit-review 为你正在写的论文构建系统性文献图景；scholar-monitor 则持续累积新文献流——随时间推移不断充实知识图谱，供*未来的*文献综述在 Tier 0 查询。

---

## Zotero 集成

`/scholar-lit-review`、`/scholar-write`、`/scholar-citation` 和 `/scholar-knowledge`
都会自动查询你的 Zotero 文献库——无需 API 密钥，也无需运行 Zotero。

**文献库位置：**
由 `setup.sh` 自动检测，或在 `.env` 文件中设置 `SCHOLAR_ZOTERO_DIR`。
常见位置：`~/Zotero`、`~/Library/CloudStorage/*/zotero`

**查询内容：**
- `zotero.sqlite.bak` — 你的期刊论文和书籍
- `storage/[KEY]/[filename].pdf` — 可经 `pdftotext` 读取的附件 PDF

**各技能的用法：**
- `/scholar-lit-review` Step 0：任何网络检索之前先做标题 + 摘要关键词检索；也支持按作者检索、按收藏夹/文件夹检索，以及对靠前结果读取 PDF
- `/scholar-write` Step 0：起草章节时按主题关键词调取相关引文
- `/scholar-citation` Step 1：为所有被引来源获取完整书目元数据（作者、年份、标题、期刊、卷、期、页码、DOI）；MODE 5（VERIFY）将 Zotero 作为 Tier 1 验证，先于 CrossRef 和 WebSearch

**手动检索**（想自己查询 Zotero 时）：
```bash
ZOTERO_DIR="$SCHOLAR_ZOTERO_DIR"  # Set in .env via setup.sh, or auto-detected
DB="$ZOTERO_DIR/zotero.sqlite.bak"
Q="%segregation%"

sqlite3 "$DB" "
SELECT c.lastName || ' (' || SUBSTR(year.value,1,4) || '). ' || title.value || '. ' || COALESCE(pub.value,'')
FROM items parent
JOIN itemTypes it ON parent.itemTypeID = it.itemTypeID
LEFT JOIN itemData title_d ON parent.itemID = title_d.itemID
  AND title_d.fieldID = (SELECT fieldID FROM fields WHERE fieldName='title')
LEFT JOIN itemDataValues title ON title_d.valueID = title.valueID
LEFT JOIN itemData year_d ON parent.itemID = year_d.itemID
  AND year_d.fieldID = (SELECT fieldID FROM fields WHERE fieldName='date')
LEFT JOIN itemDataValues year ON year_d.valueID = year.valueID
LEFT JOIN itemData pub_d ON parent.itemID = pub_d.itemID
  AND pub_d.fieldID = (SELECT fieldID FROM fields WHERE fieldName='publicationTitle')
LEFT JOIN itemDataValues pub ON pub_d.valueID = pub.valueID
LEFT JOIN itemCreators ic ON parent.itemID = ic.itemID AND ic.orderIndex=0
LEFT JOIN creators c ON ic.creatorID = c.creatorID
WHERE it.typeName IN ('journalArticle','book','bookSection','conferencePaper','preprint','thesis')
  AND (LOWER(title.value) LIKE '$Q' OR LOWER(abstract.value) LIKE '$Q')
GROUP BY parent.itemID
ORDER BY SUBSTR(year.value,1,4) DESC LIMIT 20;
" 2>/dev/null
```

---

## 示例文章资产

`/scholar-write` 起草时把你已发表的论文用作**文风与语感参照**。
目录索引位于 `.claude/skills/scholar-write/assets/index.md`。

**工作机制（三层知识库，v3.0.0）：**
1. **Tier 1** — 读取 `assets/article-knowledge-base.md`：约 119 篇论文的预提取注记（开篇原句、缺口句、贡献表述、语体风格、引用密度、段落长度规范）。多数选择无需 pdftotext。
2. **Tier 2** — 读取 `assets/section-snippets.md`：按 9 种修辞功能整理的原文引句库（开篇钩子、缺口陈述、贡献声明、理论/机制描述、方法起句、结果起句、讨论开篇、限定语、量化句式）——每条附有解析句型结构的架构注记。
3. **Tier 3** — 需要更多上下文时，可选用 `pdftotext` 深读某篇论文。
4. 初稿会模仿你既有的行文风格，并对标所选期刊范文的结构深度。

**快速选择指南** — 填充你的文章库之后（见 README 的设置说明），技能会自动将你的论文与写作任务匹配。示例表结构：

| 论文类型 | 你的文章（语感） | 顶刊参照（结构/深度） |
|-----------|-----------------------|-----------------------------------------|
| 你的专长领域 | 你已发表的论文 | 目标期刊的近期范文 |
| 第二主题领域 | 你的另一篇论文 | 另一篇顶刊范文 |
| ... | ... | ... |

完整目录位于 `assets/index.md`。把你自己的 PDF 放入 `assets/example-articles/`，顶刊范文放入 `assets/top-journal-articles/`，然后让 Claude Code 构建索引（一句话设置见 README）。

---

## 使用技巧

**章节参数要具体** — 给 `/scholar-write` 的上下文越多，输出越好：
```
# Less useful
/scholar-write introduction

# More useful
/scholar-write introduction on activity space segregation and health for Demography,
fixed effects panel design, computational + demographic audience, ~800 words
```

**起草之后、排版之前运行 `/scholar-citation`** — 在运行 `/scholar-journal` 之前先对完整初稿插入引文。投稿前用 `verify` 模式确认所有参考文献真实存在。这样合规检查看到的是含全部文内引用的最终字数，而且不留任何伪造文献。

**尽早使用 `/scholar-journal`** — 动笔之前先运行它，了解目标期刊的字数限制、摘要格式和引文样式。事后返工排版很慢。

**按顺序串联模块化技能** — 每个技能的输出都是下一个的输入。运行 `/scholar-design` 时，把 `/scholar-hypothesis` 给出的 H1–H3 作为上下文粘贴进去。

**交叉性论证** — `/scholar-hypothesis` 内置正式的乘积项设定（交互项 beta-3）、假设表述模板，以及非西方理论传统（殖民性、Ubuntu、关系/guanxi）。调用时给出具体维度：
```
/scholar-hypothesis intersectionality of race and gender in campaign donations
```

**分析之后运行 `/scholar-code-review`** — 在编码错误、统计实现失误和 AI 生成反模式渗入稿件之前将其捕获：
```
/scholar-code-review full output/scripts/
```

---

## 版本信息

当前版本：**5.17.0**（历史见 `CHANGELOG.md`）
项目位置：本仓库根目录
技能：33 + 1 个实用工具（位于 `.claude/skills/`）| 代理：20 个（9 个 peer-reviewer + 5 个 verification + 6 个 code-review，位于 `.claude/agents/`）
