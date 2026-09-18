<p align="center">
  <img src="assets/logo.svg" alt="Open Scholar Skill" width="560">
</p>

[English](README.md) | **简体中文**

# Open Scholar Skill — 面向 Claude Code 与 Codex 的学术研究技能套件

> **Copyright (c) 2025-2026 Open Scholar Skill Contributors**
> 依据 [Open Scholar Skill License (Academic Use)（学术用途许可）](LICENSE)，本项目可免费用于学术、教育及非商业研究用途。
> 商业使用须另行获得作者的书面许可。

这是一个面向社会科学研究者、以顶级期刊投稿为目标的 Claude Code 项目，覆盖从文献综合到可投稿稿件的完整研究流程。

本套件为 **Claude Code** 而构建，但并不与之绑定：这些技能就是纯 markdown 的指令文件夹，**OpenAI Codex** 及其他编码智能体同样可以加载。把它们链接到 `~/.codex/skills`，即可用自然语言调用（例如 "Use scholar-idea to sharpen this research question"，即"用 scholar-idea 打磨这个研究问题"）。数据安全层会随宿主一同迁移——`/scholar-init` 会把同一个 PreToolUse 守卫作为 Codex 钩子安装到 `<project>/.codex/config.toml`（见[数据安全](#数据安全-v590)）。

> **如果你使用了 open-scholar-skill，请引用 [Zhang (2026), *Chinese Sociological Review*](https://doi.org/10.1080/21620555.2026.2707167)。** 完整参考文献与 BibTeX 见下方[引用](#引用)一节（arXiv 上亦有预印本）。

## 学术研究中 AI 的伦理使用

Open-scholar-skill 的定位是**辅助**研究者，而不是取代研究者。如果你在研究中使用本工具，我们强烈建议遵循以下实践：

1. **披露 AI 使用情况。** 许多期刊现已要求或建议提交 AI 使用声明。请如实说明你在研究过程中如何使用了 AI 工具——无论是文献综述、初稿撰写、数据分析还是引文管理。`/scholar-ethics` 技能可以为你生成符合特定期刊要求的 AI 披露声明。

2. **核验所有输出。** AI 生成的内容可能包含错误、幻觉和捏造的引文。提交前务必独立核验统计结果、确认所引文献真实存在，并以批判的眼光审读任何由 AI 起草的文字。`/scholar-verify` 和 `/scholar-citation verify` 技能提供自动化检查，但人的判断始终不可或缺。

3. **保持智识上的所有权。** 你才是研究者。用这些工具加速你的工作流程，而不是把思考外包出去。研究问题、理论论证和结果解释都应体现你自己的专业素养与学术判断。

4. **以机制化手段保护受访者隐私。** 通过 Claude Code 读取数据文件会将其内容传输至 Anthropic API。对于受限数据集、受 HIPAA 保护的记录、受 IRB 保护的访谈，或任何包含个人身份信息的文件，未经声明的静默传输是不可接受的。v5.9.0 引入了三层数据安全栈（政策 → 摄入时扫描 → PreToolUse 钩子），要求研究者对每一个数据文件做出明确决定，任何技能才能对其执行 Read。请从 `/scholar-init` 开始搭建项目；完整说明见下方[数据安全](#数据安全-v590)一节。

### 关于全流程论文编排器的说明

本开源版本有意**不包含** `scholar-full-paper`（将全部技能串联为单条命令的端到端编排器）、`scholar-grant`、`scholar-teach`、`scholar-book` 和 `scholar-presentation`。前四者被移除，是为了避免助长缺乏研究者实质参与的全自动论文生成；`scholar-presentation` 被移除，则是出于咨询公司幻灯片美学的版权顾虑。

本版本**包含** `scholar-auto-research`——一条稳定、确定性的流水线，将各模块化技能从想法或数据一路串联到经过验证的稿件。但**这不是自主研究，我们也不认可将其当作自主研究来使用。** 它与上述编排器的差异体现在三个专为让你保持掌控而设计的方面：（1）强制的**人在回路模式**，在各阶段之间停下来等待你的明确批准（`set-mode human-in-loop`）；（2）每个阶段都有确定性、可审计的关卡——结果锁定、引文元数据核验、四智能体稿件验证，以及按目标期刊校准的质量评审——这些关卡是把需要检查的内容摆到你面前，而不是藏起来；（3）一条硬性规则：实质性的学术工作由专业技能（`scholar-write`、`scholar-citation`、`scholar-respond` 等）完成，任何辅助脚本都不会悄悄成为你的论证、文献综合或引文的作者。**研究问题、论证和每一处解释的作者始终是你。** 只有当你会独立核验它产出的每一项结果时，才可在自主模式下运行——这与上文[伦理使用](#学术研究中-ai-的伦理使用)第 2 条是同一标准。拿不准时，就逐个运行各技能，在每一步都保持人在回路。

这里提供的 35 个模块化技能就是同一套积木。我们鼓励你按照适合自己研究流程的顺序串联技能、搭建自己的工作流。典型流水线如下：

```
/scholar-init (set up project + data safety)
    →  /scholar-idea  →  /scholar-brainstorm (or /scholar-conceptual)
    →  /scholar-lit-review (or /scholar-lit-review-hypothesis)
    →  /scholar-hypothesis  →  /scholar-design
    →  /scholar-causal  →  /scholar-data  →  /scholar-safety
    →  /scholar-eda  →  /scholar-analyze  →  /scholar-compute (if needed)
    →  /scholar-qual (if qualitative)  →  /scholar-ling (if sociolinguistic)
    →  /scholar-write  →  /scholar-citation  →  /scholar-verify
    →  /scholar-journal  →  /scholar-open  →  /scholar-replication
    →  /scholar-ethics  →  /scholar-code-review
    →  /scholar-respond (simulate review)  →  revise and submit
```

并非每个项目都需要用到所有技能。用不上的就跳过，需要的就反复使用（`/scholar-write` → `/scholar-verify` → 修改 → 再来一轮）。逐个运行技能能让你在每个环节都保持在回路之中——审阅输出、做出决定、把握研究方向。我们相信，这才是 AI 工具在学术研究中应有的使用方式。

## 支持本项目

Open Scholar Skill 面向学术与非商业研究免费使用，由开发者利用业余时间维护。如果你觉得它对你有帮助，欢迎通过小额个人捐赠支持本项目的持续维护与开发。捐赠完全自愿——无论是否捐赠，本套件的每一部分都始终免费使用。

<p align="center">
  <img src="assets/wechat.jpg" alt="微信支付捐赠二维码" width="280">
  <br>
  <em>微信支付 —— 扫码支持开发者</em>
</p>

感谢你帮助本项目持续发展。🙏

## 数据安全 (v5.9.0)

"让研究者留在回路中"这一理念，同样适用于数据访问，正如它适用于论文起草。通过 Claude Code 读取数据文件会将其内容传输至 Anthropic API——对公开的 CSV 而言无关紧要，但对 NHANES、PSID、NLSY、Census RDC、受 HIPAA 保护的记录或受 IRB 保护的访谈而言，这可能构成对数据使用协议的违反。v5.9.0 以三层防御应对这一问题，要求研究者对每个数据文件做出明确决定。

**第 1 层——政策。** `.claude/skills/_shared/data-handling-policy.md` 定义了五种 `SAFETY_STATUS` 取值（`CLEARED`、`LOCAL_MODE`、`ANONYMIZED`、`OVERRIDE`、`HALTED`）以及 LOCAL_MODE 执行契约：只允许 bash 通道的 `Rscript -e` / `python3 -c` heredoc，绝不使用 `Read`，并附有禁用动词清单（`head(df)`、`print(df)`、`df.head()`、`df.sample()` 等）。

**第 2 层——摄入时扫描。** `/scholar-init` 是一个新的交互式技能：创建标准化项目布局，将原始文件复制到 `data/raw/`，对每个文件做本地 PII/HIPAA 扫描，并写入 `.claude/safety-status.json`。其 `review` 模式带着研究者逐条处理每个 `NEEDS_REVIEW` 条目，将其解决为一个明确状态。这是整个安全栈中"慢下来、做决定"的那一半——最大程度的人在回路，正是本版本的精神所在。

**第 3 层——机制化强制执行。** `scripts/gates/pretooluse-data-guard.sh` 旨在作为 PreToolUse 钩子全局注册到 `~/.claude/settings.json`。它拦截每一次 `Read`、`NotebookRead`、`NotebookEdit`、`Grep` 和 `Glob` 调用，在最近的 `.claude/safety-status.json` 中查找目标路径，当状态为 `NEEDS_REVIEW:*` 或 `HALTED` 时拒绝该调用。定性研究的音频/视频/转录文本格式即使手工改写边车文件也无法被 `OVERRIDE`。规范化后落入系统目录（`/etc`、`/dev`、`/proc`、`/sys`、`/System`、`/var/db`、`/var/log`、`/private/*`）的路径一律直接拒绝。该钩子还覆盖了以往敞开的两条通道：**Bash** 倾倒动词关卡（拦截对敏感路径的 `cat`/`head`/`sed`/`awk`/行级 `grep`/`sqlite3`/python·R 行倾倒，同时放行政策许可的 LOCAL_MODE 聚合加载器），以及防止篡改 `.claude/safety-status.json` 的 **Edit/Write** 守卫。可选的 **strict** 级别额外增加一个 PostToolUse 钩子，在 Bash *输出*进入模型上下文之前对 PII / 批量行数据进行涂抹——用 `/scholar-safety level <standard|strict|lockdown>` 设置级别。

**Codex 宿主下的第 3 层。** 上述钩子是 Claude Code 的机制；**Codex** 宿主从不读取 `~/.claude/settings.json`。因此当 `/scholar-init` 检测到 Codex（或未知）宿主时，它会*同时*将同一守卫安装为 Codex 的 PreToolUse 钩子——在 `<project>/.codex/config.toml` 中写入一个 `[hooks.PreToolUse]` 块，运行 `scripts/gates/codex-pretooluse-hook.sh`，后者委托给同一个守卫脚本，并在读取被拦截时返回 Codex 的拒绝协议（已针对 `codex` 完成端到端验证）。它在你于 Codex 中**信任该项目**后激活；在此之前，项目的 `AGENTS.md` 块会指示智能体依照边车文件自我约束。

**第 3 层 lockdown——操作系统之墙（两种宿主均适用）。** 上面的钩子与文字约定都属于*合作式*护栏。若要一道内核级强制边界、连蓄意行动或遭提示注入的智能体也能挡住，`/scholar-safety level lockdown` 会运行 `scripts/gates/generate-lockdown-config.sh`，为检测到的宿主在数据目录上写入操作系统沙箱级的读取拒绝：Claude Code 得到 `.claude/settings.json` 中的 `sandbox.filesystem.denyRead`（Seatbelt/Landlock）；Codex 得到 `.codex/config.toml` 中的 `[permissions]` `"data"="deny"` 配置。已完成端到端验证——沙箱内执行 `cat data/raw/*.csv` 返回 `Operation not permitted`，零泄漏，两种宿主皆然。lockdown 默认是一道硬墙（`allowUnsandboxedCommands:false`），因此也会挡住政策许可的 LOCAL_MODE 分析——请在锁定之前完成分析，或传入 `--allow-escalation` 以启用需人工批准的逃生通道。

**典型快速上手：**

```
bash scripts/init-project.sh --dest ~/research nhanes-bmi ~/Downloads/nhanes.csv
cd ~/research/nhanes-bmi
/scholar-init review                      # resolve each NEEDS_REVIEW entry
/scholar-eda data/raw/nhanes.csv          # proceeds under the sidecar-recorded status
/scholar-analyze ...                      # inherits the same decisions
```

**受本安全栈约束的十一个数据接触型技能**：`scholar-analyze`、`scholar-eda`、`scholar-compute`、`scholar-ling`、`scholar-qual`、`scholar-brainstorm`（A 级——LOCAL_MODE 分派）；`scholar-data`、`scholar-verify`、`scholar-replication`、`scholar-code-review`、`scholar-write`（B 级——边车检查 + 快速失败拒绝）。

**启用机制化强制执行。** 在 Claude Code 下，`setup.sh` 会自动将 `scripts/gates/pretooluse-data-guard.sh`（以及在 strict 级别下的 `posttooluse-output-guard.sh`）注册为 `~/.claude/settings.json` 中的钩子（ZCode 与 Codex 的接入方式不同——见[安装设置](#安装设置)一节的宿主对照表），匹配器覆盖 `Read`、`NotebookRead`、`NotebookEdit`、`Grep`、`Glob`、`Bash`、`Edit` 和 `Write`。宿主机上必须安装 `jq` 和 `python3`；二者缺一，读取通道的守卫即失效关闭（Bash/Edit/Write 减速带则失效放行，以免 shell 被彻底卡死）。两个激活时的注意事项：（1）Claude Code 在会话**启动**时对钩子配置做快照，因此安装后必须**重启** Claude Code 钩子才会生效；（2）Claude Code 将钩子的 `command` 作为一行 shell 命令执行，所以当安装路径含有空格（例如 Google Drive）时，命令必须包装为 `bash '<path>'`——`setup.sh` 会替你处理，但手工编辑的 settings 文件也必须如此，否则守卫会对*所有*工具静默失效放行。

### ⚠️ 诚实的局限性 — 这是风险缓解，而非绝对保证

**请注意：当前的数据安全栈并非理想或最安全的设计。** 它是一道*研究者在回路中的护栏*，让意外和随意的数据泄漏变得困难——它**不是能抵御蓄意行动或遭提示注入的智能体的封闭边界。** 具体而言：

- **Bash** 关卡是一份尽力而为的黑名单。任意 shell 命令无法被完全审查：其他解释器（`ruby`、`node`、`perl`）、输出编码（`base64`/`gzip`/`hex`）、由变量拼装的路径，或先把敏感文件复制到无害路径再读取副本，都仍可能把数据带入上下文。PostToolUse 的 **strict** 涂抹器收窄了输出通道，但同样可被编码手段绕过。
- 该钩子是工具名白名单，不是操作系统沙箱。它拦不住直接打开文件的子进程，也不约束你在自己脚本中调用的第三方工具。
- 对于真正的受限数据（DUA/IRB/HIPAA），请把这些守卫当作机构管控之上的纵深防御——绝不能替代机构管控。

**操作系统级沙箱（`lockdown`）才是真正的边界。** 如上所述，`/scholar-safety level lockdown` 会在数据目录上写入内核强制的 `denyRead`（`allowUnsandboxedCommands:false`），使智能体在物理上无法读取原始数据，除非经过明确的、由用户批准的逃生通道（`--allow-escalation`）。这是唯一能挡住蓄意智能体的配置；`standard` 和 `strict` 级别做不到。

**当前最强的缓解手段：在合成数据上工作。** 与其把真实敏感数据暴露给任何 AI 工具，不如生成一份**具备完整变量集的合成数据集**——与真实数据相同的列名、类型、取值范围，以及（可选的）联合分布，但不含任何真实记录——然后把各技能指向它。智能体可以在合成文件上构建并调试整条分析流水线；之后你在 AI 工具之外、**本地**对真实数据运行已完成并经审阅的脚本，让真实记录永不进入任何模型的上下文。这从根本上绕开了守卫的局限，是处理 DUA/IRB 受限数据集的推荐工作流——它是 `lockdown` 的补充而非替代：即便启用了操作系统沙箱，让真实记录远离任何模型的上下文仍是最稳妥的姿态。

## 在 aiXiv 上分享你的成果

如果你在用 open-scholar-skill 生成论文，欢迎把不打算在其他地方发表的论文分享到 [aiXiv.me](https://aixiv.me)——一个面向 AI 生成研究的开放平台。LLM 请阅读 [https://aixiv.me/llms.txt](https://aixiv.me/llms.txt) 了解投稿与评审说明。

## 目标期刊

| 期刊 | 领域 | 影响力 |
|---------|-------|--------|
| American Sociological Review (ASR) | 社会学 | 顶级（第 1） |
| American Journal of Sociology (AJS) | 社会学 | 顶级（第 2） |
| Demography | 人口科学 | 顶级（第 1） |
| Science Advances | 综合学科 | 高 |
| Nature Human Behaviour | 行为/社会科学 | 高 |
| Nature Computational Science | 计算方法 | 高 |

> **商标声明：** 上文及本项目各处列出的期刊名称均为其各自出版方的商标，此处仅用于标识与格式化目的。本项目与任何期刊或出版方均无隶属或背书关系。

## 技能总览 (35 个技能 + 1 个实用工具 = 共 36 个)

### 研究流程（编排器）

| 技能 | 调用方式 | 用途 |
|-------|--------|---------|
| `scholar-auto-research` | `/scholar-auto-research` | 稳定、确定性的 21 阶段流水线，从想法或数据直达经过验证的稿件、引文、复现包及 md/docx/tex/pdf 输出。**不是自主研究**——内置强制的人在回路模式，在各阶段之间暂停等待你的批准，并以确定性检查为每个阶段设卡（结果锁定、引文元数据核验、四智能体稿件验证、按期刊校准的质量评审）。实质工作由专业技能完成；辅助脚本只负责打包与验证。自包含：关卡脚本捆绑在技能目录之下。 |

### 核心流程技能

| 技能 | 调用方式 | 用途 |
|-------|--------|---------|
| `scholar-brainstorm` | `/scholar-brainstorm` | 从数据文件、码本或已发表论文出发，经 5 智能体评审小组生成研究问题（DATA 模式：经验信号检验；MATERIALS 模式：理论驱动排序；PAPER 模式：种子论文拓展） |
| `scholar-idea` | `/scholar-idea` | 将宽泛的想法转化为规范、可研究的社会科学问题 |
| `scholar-lit-review` | `/scholar-lit-review` | 系统性文献综述与综合 |
| `scholar-lit-review-hypothesis` | `/scholar-lit-review-hypothesis` | 文献综述 + 理论 + 假设发展一体化完成 |
| `scholar-hypothesis` | `/scholar-hypothesis` | 理论发展、假设构建、交叉性视角 |
| `scholar-design` | `/scholar-design` | 研究设计、方法论、统计功效分析、实验设计 |
| `scholar-analyze` | `/scholar-analyze` | 数据分析（OLS、logit、贝叶斯 brms、LCA、SEM、序列分析、分位数回归、GAMLSS、DML 桥接、增长曲线、MSEM、FMR、设定曲线、BART）+ 出版级表格/图形（modelsummary + gt + Stata .do） |
| `scholar-write` | `/scholar-write` | 逐节指导的完整论文起草 |
| `scholar-citation` | `/scholar-citation` | 8 模式引文管理：INSERT、AUDIT、CONVERT-STYLE、FULL-REBUILD、VERIFY、EXPORT (.bib)、RETRACTION-CHECK、REPORTING-SUMMARY |
| `scholar-code-review` | `/scholar-code-review` | 6 智能体系统化代码审查：正确性、稳健性、统计忠实度、可复现性、代码风格、数据处理 |
| `scholar-knowledge` | `/scholar-knowledge` | 用户级、跨项目知识图谱（8 模式：INGEST、SEARCH、RELATE、STATUS、EXPORT、COMPILE wiki、ASK、RE-EXTRACT）——兼容 Obsidian 的 markdown wiki，附原始来源存档 |
| `scholar-rag` | `/scholar-rag` | 面向整个参考文献库（Zotero 或 PDF 文件夹）的**全本地向量数据库 + GraphRAG**，用于文献综述。定位/开放获取抓取全文 PDF，提取文本（pdftotext/PyMuPDF/视觉 OCR），用 **bge-m3** 切块嵌入到 **LanceDB**，并叠加一层本地 LLM 的 **GraphRAG**（实体/关系抽取 + Leiden 社区 + 社区摘要，从 `scholar-knowledge` 播种）。通过 **MCP 服务器**（`rag_search`、`rag_get_document`、`rag_neighbors`、`rag_stats`）向 Claude Code + Codex 暴露语义检索。自包含（自带 venv）；数据不出本机。6 种模式：setup、ingest、query、mcp、graph、status |
| `scholar-journal` | `/scholar-journal` | 面向特定期刊的格式化与投稿准备（22 种期刊，Nature Reporting Summary） |
| `scholar-respond` | `/scholar-respond` | 5 种模式：simulate（3-4 位评审）、respond（逐条回应）、revise（字数预算）、resubmit（被拒后改投）、cover-letter |
| `scholar-verify` | `/scholar-verify` | 两阶段"分析到稿件"一致性验证（4 智能体小组：数值、图形、逻辑、完整性） |
| `scholar-polish` | `/scholar-polish` | 稿件最终润色：面向清晰、精炼、流畅与期刊语感的文字级编辑（保留内容，只改文风） |
| `scholar-openai` | `/scholar-openai` | 借助 OpenAI Codex CLI 的外部评审：5 个并行智能体（代码正确性、稳健性、可复现性、统计一致性、逻辑）提供独立的第二意见验证 |

### 扩展技能

| 技能 | 调用方式 | 用途 |
|-------|--------|---------|
| `scholar-data` | `/scholar-data` | 开放数据目录（100+ 数据集）、自动获取、问卷设计、访谈提纲、IRB、网络爬取 |
| `scholar-eda` | `/scholar-eda` | 探索性数据分析、缺失数据、数据清洗、预分析计划 |
| `scholar-causal` | `/scholar-causal` | 因果推断工具箱：DAG、13 种识别策略（OLS、DiD、交错 DiD、RD、IV、FE、匹配、合成控制、中介分析、DML、因果森林、bunching、Bartik IV）+ 分布性方法、敏感性分析 |
| `scholar-compute` | `/scholar-compute` | 11 个模块化模块：NLP/文本即数据、机器学习、网络/GNN、ABM、计算机视觉、LLM 工作流、合成数据、地理空间、音频、life2vec |
| `scholar-annotate` | `/scholar-annotate` | 规模化的 LLM 标注：编码簿设计、开发集/黄金集、DSPy 提示优化、κ ≥ 0.70 硬性信度门槛、Batch/本地/HPC 扩展，以及蒸馏为轻量分类器 |
| `scholar-simulate` | `/scholar-simulate` | 规模化的 LLM 社会模拟：硅基抽样、生成式 ABM、问卷/情境/联合实验、观点动力学。自带真实执行引擎（多提供商 Batch API + 本地异步并发），而非上下文内代码片段；多提供商支持（Anthropic/OpenAI/开源/本地）。**任何可发表结论之前必须完成与人类数据的保真度验证**——模拟受访者不能替代人类数据。 |
| `scholar-open` | `/scholar-open` | 预注册、数据共享、代码打包、开放获取 |
| `scholar-replication` | `/scholar-replication` | 构建、记录、测试、核验并归档符合期刊要求的复现包（EDA 输出、工件登记、格式核验） |
| `scholar-qual` | `/scholar-qual` | 定性方法：开放/主轴/选择性编码、主题分析、内容分析、附人工校验的 LLM 辅助编码、混合方法整合、编码者间信度 |
| `scholar-ling` | `/scholar-ling` | 9 个模块化模块：变异研究、定量、定性、语言态度/配对变语、语料库、计算社会语言学、实验、Biber 多维分析、TTS-MGT |
| `scholar-collaborate` | `/scholar-collaborate` | 多作者协作：CRediT 角色、任务管理、师徒指导、冲突解决 |
| `scholar-conceptual` | `/scholar-conceptual` | 理论建构（8 种策略：类型学、过程、机制、适用范围、多层次、溯因、综合、概念澄清）+ 出版级概念图（TikZ/Mermaid） |
| `scholar-monitor` | `/scholar-monitor` | 文献动态追踪：基于增量从顶级期刊（Crossref/ISSN）与 arXiv 类目抓取；总结新论文；经 ntfy.sh 或 Telegram 推送摘要到手机；自动摄入 `scholar-knowledge`。为 `/loop` 定时调度而设计。按源节律过滤保证幂等：`/loop 1h` 搭配每周一次的源只产出一份摘要/周。9 种模式：默认/定向抓取、`all`、`preview`（试运行）、`init`、`list`、`status`、`add`、`remove`、`configure delivery`、`digest`。状态存于 `~/.claude/scholar-monitor/`（可经 `SCHOLAR_MONITOR_DIR` 配置） |

### 伦理与安全技能

| 技能 | 调用方式 | 用途 |
|-------|--------|---------|
| `scholar-init` | `/scholar-init` | **v5.9.0** 项目初始化器与数据安全决策回路。创建标准布局（`data/raw`、`data/interim`、`data/processed`、`materials`、`output`、`.claude`、`logs`），复制或符号链接原始文件到位，对每个摄入文件执行安全扫描，写入 `.claude/safety-status.json`，并以交互方式带研究者逐条处理 `NEEDS_REVIEW` 决定（将每条解决为 CLEARED / LOCAL_MODE / ANONYMIZED / OVERRIDE / HALTED）。与 PreToolUse 数据安全钩子协同，确保任何敏感文件在没有明确决定之前不会到达 API。 |
| `scholar-ethics` | `/scholar-ethics` | AI 工具数据隐私审计、抄袭检查、研究诚信审计、IRB/署名/利益冲突合规 |
| `scholar-safety` | `/scholar-safety` | 实时数据隐私保护：在 AI 处理之前扫描文件中的 PII/HIPAA/受限数据 |
| `scholar-auto-improve` | `/scholar-auto-improve` | 持续质量引擎：技能输出事后审计、技能套件健康检查、修复生成、跨会话模式分析 |

### 实用工具技能

| 技能 | 调用方式 | 用途 |
|-------|--------|---------|
| `sync-docs` | `/sync-docs` | 在演示幻灯片、讲稿与论文稿件之间同步内容——审查过时的引用、数字、引文与版本不一致 |

## 智能体（共 20 个：9 个同行评审 + 5 个验证 + 6 个代码审查）

| 智能体 | 角色 |
|-------|------|
| `peer-reviewer-quant` | 方法论专家：评估研究设计、识别策略、稳健性 |
| `peer-reviewer-theory` | 理论专家：评估理论框架、假设、文献 |
| `peer-reviewer-computational` | 计算方法专家：评估 NLP、机器学习、网络与 ABM 方法 |
| `peer-reviewer-qual` | 定性方法专家：评估民族志、访谈、扎根理论 |
| `peer-reviewer-ling` | 语言学专家：评估社会语言学方法、语音学、话语分析 |
| `peer-reviewer-demographics` | 人口代表性、APC 分析、交叉性、人口学分解 |
| `peer-reviewer-mixed-methods` | 整合策略、联合展示、案例选择、收敛/分歧分析 |
| `peer-reviewer-ethics` | IRB 合规、知情同意、弱势群体、AI 透明度、GDPR |
| `peer-reviewer-senior` | 资深编辑：整体重要性、框架立意、期刊契合度 |

### 验证智能体（由 `scholar-verify` 调用）

| 智能体 | 角色 |
|-------|------|
| `verify-numerics` | 将原始分析输出（CSV、HTML 表格）与稿件表格逐格比对 |
| `verify-figures` | 原始图形文件 vs. 稿件中的图形描述与图注 |
| `verify-logic` | 将正文中的统计论断回溯到表格/图形——捕捉错引数字、显著性错误 |
| `verify-completeness` | 完整工件链完整性——孤立/缺失项、编号、交叉引用 |
| `verify-claim-faithfulness` | 句子级检查每条被引文献是否真正支持归于它的论断——捕捉张冠李戴、方向颠倒、效应量夸大、适用范围过度推广 |

### 代码审查智能体（由 `scholar-code-review` 调用）

| 智能体 | 角色 |
|-------|------|
| `review-code-correctness` | 逻辑错误、差一错误、错误的合并键、静默的 NaN 传播 |
| `review-code-robustness` | 边界情况、输入校验、防御式编程 |
| `review-code-statistics` | 统计实现忠实度——方法正确、设定正确 |
| `review-code-reproducibility` | 随机种子设置、路径可移植性、依赖管理 |
| `review-code-style` | AI 生成代码的反模式、幻觉函数、过度设计 |
| `review-code-data-handling` | 类别编码错误、错误的重编码、缺失值处理不当、样本限制 |

## 安装设置

```bash
git clone <this-repo> && cd open-scholar-skill
bash setup.sh                          # 自动检测你使用的宿主工具
bash setup.sh --harness claude,zcode   # 或显式指定：claude | codex | zcode | all
```

`setup.sh` 将会：
1. 选定目标宿主工具（harness）。默认的 `auto` 会为所有已存在配置目录（`~/.claude`、`~/.codex`、`~/.zcode`）的宿主以及当前驱动会话的宿主安装；全新机器上回退为 Claude Code。可用 `--harness <列表>` 或 `SCHOLAR_SETUP_HARNESS` 覆盖。
2. 创建符号链接（`skills/` → `.claude/skills/`，`agents/` → `.claude/agents/`）
3. 自动检测你的 Zotero 库（或提示输入路径）
4. 按需配置 BibTeX、EndNote 与 CrossRef 邮箱
5. 将全部 36 个技能（35 个研究技能 + `sync-docs` 实用工具）+ 20 个智能体作为**个人技能**安装——逐条安装，与已有个人技能并存，位置取决于各宿主读取的目录（见下表）
6. 在各宿主自己的配置文件中、按其自己的格式注册该宿主真正能执行的数据安全钩子（幂等；保留现有设置；文件内容发生变化时，旧版本保留为 `<file>.bak-<时间戳>`）
7. 检查 `jq` 与 `python3`（数据安全钩子的必要依赖）
8. 写入包含你的配置的 `.env` 文件

安装过程是**按宿主区分**的——三种宿主把技能与钩子放在不同位置、采用不同格式，且互不读取对方的文件：

| 宿主 | 技能 / 智能体 | PreToolUse 数据守卫 | PostToolUse 输出脱敏器 |
|---|---|---|---|
| **Claude Code** | `~/.claude/skills/`、`~/.claude/agents/` | `~/.claude/settings.json` → `.hooks.PreToolUse` | 有 → `.hooks.PostToolUse`（strict 级别下生效） |
| **Codex** | `~/.codex/skills/`（Codex 不加载智能体文件） | **按项目安装**——由 `/scholar-init` 写入 `<project>/.codex/config.toml`；在 Codex 中信任该项目后生效 | 不可用 |
| **ZCode** | `~/.zcode/skills/`、`~/.zcode/agents/` | `~/.zcode/cli/config.json` → `.hooks.events.PreToolUse`（并设 `hooks.enabled: true`） | 不可用 |

脱敏器仅限 Claude Code，是因为它只能通过返回 Claude Code 的 `updatedToolOutput` 钩子协议来脱敏。Codex 与 ZCode 虽有 PostToolUse 事件，却无法替换 Bash 输出；在那里注册它只会装上一个什么也不脱敏的“控制”，所以 `setup.sh` 不这么做。在这两种宿主上处理受限数据，请使用内核级强制的 Lockdown 级别（`/scholar-safety level lockdown`）。安装后请重启各宿主——钩子配置在会话启动时读取。

**环境要求：** `bash`、`python3`、`jq`。缺少 `jq` 或 `python3` 时数据安全钩子会失效关闭，因此请先安装二者（`brew install jq` / `apt-get install jq`）。Presidio（可选，用于基于 NER 的 PII 检测）通过 `python3 -m pip install presidio-analyzer presidio-anonymizer` 安装。

安装完成后，所有 `/scholar-*` 命令可在任意目录使用。

## 配置文章库（供 `scholar-write` 使用）

`scholar-write` 技能使用示例文章来校准写作语感与风格。资产目录出厂为空——由你用自己的论文和目标期刊的范文来填充。

### 第 1 步：加入你自己的论文

将你已发表论文的 PDF 复制到：
```
.claude/skills/scholar-write/assets/example-articles/
```
这些论文教会该技能你的个人写作语感——你如何提出困惑、陈述贡献、组织论证。

### 第 2 步：加入顶刊范文（可选但推荐）

创建目录并加入目标期刊的范文：
```bash
mkdir -p .claude/skills/scholar-write/assets/top-journal-articles/
```
复制 5–20 篇你目标期刊（如 ASR、AJS、Demography、Science Advances）的近期论文。这些范文教会该技能各期刊所期待的结构深度、引文密度与严谨程度。

### 第 3 步：构建索引与知识库

加入 PDF 之后，让 Claude Code 为你建立索引：

```
Scan all PDFs in .claude/skills/scholar-write/assets/example-articles/ and
.claude/skills/scholar-write/assets/top-journal-articles/. For each paper,
use pdftotext to extract the first 300 lines, then populate:
1. assets/index.md — add a row per paper (filename, citation, journal, method, topics, best-for)
2. assets/article-knowledge-base.md — add a structured entry per paper (opening line, gap sentence, contribution claim, voice register, sentence architecture, paragraph rhythm)
3. assets/section-snippets.md — extract verbatim quotes into the 9 rhetorical categories (opening hooks, gap statements, contribution claims, mechanism statements, data description openings, results lead-ins, discussion openers, limitation acknowledgments, closing sentences)
```

只需这一条提示，就能从你的 PDF 自动建成整个知识库。

> **注意：** `scholar-write` 在没有任何文章的情况下也能工作——它会依靠内置的期刊惯例知识起草各节。文章库的作用是通过校准你的语感和目标期刊的规范，让输出更好。

## 配置 `scholar-monitor`（通过 ntfy 或 Telegram 推送手机摘要）

`scholar-monitor` 盯守你选定的期刊和 arXiv 类目，把新论文摘要推送到你的手机。本节完整走一遍配置流程：初始化 → 选择来源 → 测试抓取 → 接通手机推送 → 用 `/loop` 定时调度。

所有状态持久化在 `~/.claude/scholar-monitor/` 之下——用户级、跨项目共享，不依赖任何单个仓库。

### 第 1 步：初始化状态目录

```
/scholar-monitor init
```

这会创建 `~/.claude/scholar-monitor/`，内含：
- `sources.json` — 22 个预置来源（ASR、AJS、Demography、arXiv cs.CL 等），默认启用三个（ASR、arxiv-llm、NHB），让首次摘要保持精简
- `state.json` — 空游标文件（每个来源的最近可见水位）
- `config.json` — 推送通道设置（`chmod 0600`）
- `archive.ndjson` — 只追加的摘要历史

至此配置完成；该技能会立即将抓取结果写入文件通道。手机推送还需要下面几步。

### 第 2 步：选择你关注的期刊与预印本查询

```
/scholar-monitor list
```

显示全部 22 个来源及其启用/停用状态、节律（多久检查一次）和下次到期日。要启用更多期刊或调整节律，直接编辑 `~/.claude/scholar-monitor/sources.json`——它就是一份普通的 JSON 注册表。ISSN 对照表（覆盖 28 种社会学/人口学/交叉学科期刊）与 arXiv 类目清单见本仓库的 `references/registry-guide.md`。

想不动手编辑 JSON 就添加自定义期刊或 arXiv 查询：

```
/scholar-monitor add
```

它会提示你输入后端类型、标识符（期刊用 ISSN，预印本用 arXiv 查询串）、类目标签和节律。

### 第 3 步：测试抓取流水线（暂不推送手机）

```
/scholar-monitor preview          # dry-run: show what would fetch, no network, no state change
/scholar-monitor arxiv-llm         # real fetch from one source, writes output/monitor/feed-YYYY-MM-DD.md
```

打开生成的 feed 文件。如果其中有论文条目，包含标题、作者、日期和 2–3 句摘要，说明抓取器工作正常。接下来接通推送通道。

### 第 4a 步：通过 **ntfy.sh** 推送手机（推荐 — 无需注册，5 分钟搞定）

ntfy 是一个免注册的免费推送服务。你选定一个保密的主题字符串，在手机上订阅它，`scholar-monitor` 就向该主题 POST 通知。

**在手机上：**

1. 安装 **ntfy** 应用（iOS App Store / Google Play——发布者为 Philipp Heckel）。
2. 打开应用 → 点 **+** → 粘贴一个随机主题字符串（见下一步）→ **Subscribe**。

**在电脑上：**

```bash
# Generate an unguessable topic. Anyone who knows this string can push to your
# phone, so save it somewhere like a password manager, and treat it as a secret.
openssl rand -hex 8
# → e.g., b4ab8afe7e06d2ef
```

在手机上订阅同一个字符串（即上面的 **+** 步骤），然后：

```
/scholar-monitor configure delivery
```

在提示时粘贴主题字符串。Telegram 和邮件的提示可以跳过。就这样——下次 `/scholar-monitor` 抓到论文时，几秒内你就会收到推送通知。

**测试推送：**

```
/scholar-monitor arxiv-llm
```

你的手机应当收到一条标题为 "scholar-monitor — N new papers" 的通知。若没有收到，请检查：（1）ntfy 应用订阅的主题字符串完全一致；（2）iOS/Android 已为 ntfy 应用开启通知权限；（3）`~/.claude/scholar-monitor/config.json` 中的主题与之完全匹配。

**ntfy 免费额度：** 每 IP 每天 250 条消息——对每日摘要绰绰有余。如需更高频率或自定义域名，见 [ntfy.sh 自托管文档](https://docs.ntfy.sh/install/)。

### 第 4b 步：通过 **Telegram** 推送手机（备选 — 配置较多，支持双向交互）

Telegram 推送配置更繁琐，但提供双向聊天通道（你可以回复摘要；若你还装了其他 Claude Code Telegram 插件，还能远程与 Claude 交互）。

**前置条件：**

1. 一个 Telegram 账号 + 手机端 Telegram 应用。
2. 你的 Claude Code 环境中已安装 Claude Code Telegram MCP 插件（这与 scholar-monitor 是两回事）。

**配置：**

1. **创建机器人。** 在 Telegram 中私信 `@BotFather`，运行 `/newbot`，给机器人取名，保存令牌（`123456:ABC-DEF...`）。
2. **配置插件。** 在 Claude Code 会话中运行你的 Telegram 插件的配置命令（通常是 `/telegram:configure`），在提示时粘贴机器人令牌。
3. **找到你的 chat ID。** 用手机给你的机器人发一条消息。插件的白名单管理命令（通常是 `/telegram:access`）会显示待批准的配对及你的 `chat_id`。批准它。
4. **接入 scholar-monitor。**
   ```
   /scholar-monitor configure delivery
   ```
   在提示时粘贴第 3 步得到的 `chat_id`。

**测试：**

```
/scholar-monitor arxiv-llm
```

你会收到机器人发来的 Telegram 消息：正文是摘要概览，完整的 `feed-YYYY-MM-DD.md` 以文档形式附上。

**提醒：** Telegram MCP 插件是一个活动部件——若它在会话中途断开，scholar-monitor 会记录失败并继续运行（文件通道和知识图谱摄入照常执行）。对于不依赖运行中 MCP 插件的无人值守 `/loop` 调度，ntfy 更可靠。

### 第 4c 步（可选）：通过 SMTP 发送邮件

三种方式中配置最重的一种。需要 SMTP 凭据（推荐 Gmail 应用专用密码；见 [Google 官方指南](https://support.google.com/accounts/answer/185833)）。

```
/scholar-monitor configure delivery
```

在提示时提供 SMTP 主机（`smtp.gmail.com`）、端口（`587`）、发件/收件地址，以及存放密码的环境变量名（默认 `SMTP_PASS`）。然后在你的 shell 或 `.env` 中：

```bash
export SMTP_PASS="your-16-char-app-password"
```

密码只存在于环境变量中，绝不会写入 `config.json`。

### 第 5 步：用 `/loop` 定时调度

推送通道就绪后，就可以自动化：

```
/loop 24h /scholar-monitor arxiv-llm     # daily arXiv LLM digest
/loop 7d  /scholar-monitor                # weekly sweep of every enabled source
/loop 1h  /scholar-monitor                # harmless — per-source cadence_days drops redundant ticks
```

每个来源的 `cadence_days` 过滤器保证幂等：对一个周节律的来源运行 `/loop 1h`，一周只会产出**一份**摘要，而不是 168 份。单个来源的失败（网络错误）不会推进该来源的游标，下一轮会干净地重试。

### 验证配置

```
/scholar-monitor status
```

打印一份仪表盘：启用的来源数量、归档大小、已配置的推送通道，以及任何逾期的来源。健康的配置应当显示至少一个 `file` 之外的通道、零错误，且各来源的下次到期日都在近期。

如有异常，`~/.claude/scholar-monitor/logs/deliver-YYYY-MM-DD.log` 记录了每个通道的投递尝试——ntfy 的 HTTP 错误或 SMTP 认证失败都会落在那里。



## 使用示例

```
# Core pipeline
/scholar-idea why do low-income neighborhoods have lower preventive care uptake
/scholar-brainstorm path/to/gss-codebook.pdf sociology, inequality
/scholar-brainstorm path/to/my-survey-data.csv health disparities for Demography
/scholar-lit-review social capital and labor market outcomes
/scholar-lit-review-hypothesis redlining and activity space segregation for AJS
/scholar-hypothesis mobility and linguistic assimilation
/scholar-design causal identification for education returns
/scholar-analyze interpret regression coefficients for ASR
/scholar-write introduction section on stratification
/scholar-citation insert ASA citations and build reference list
/scholar-journal prepare manuscript for Nature Human Behaviour
/scholar-conceptual theorize typology of immigrant civic engagement
/scholar-openai full output/scripts/

# Knowledge graph (8 modes)
/scholar-knowledge ingest from zotero collection segregation
/scholar-knowledge ingest from url https://arxiv.org/abs/2402.12345
/scholar-knowledge ingest from output output/lit-review-2026-04.md
/scholar-knowledge search theories of spatial assimilation
/scholar-knowledge relate Massey 1993 contradicts Clark 1986
/scholar-knowledge status
/scholar-knowledge compile                                 # build Obsidian wiki
/scholar-knowledge ask what are the main mechanisms linking segregation and health?
/scholar-knowledge re-extract all abstract_only            # upgrade when PDFs arrive
/scholar-knowledge export for mobility-health project

# Extended pipeline
/scholar-data find dataset for immigration and labor market outcomes
/scholar-data design a survey on immigrant identity
/scholar-eda run EDA on panel dataset before modeling
/scholar-causal draw DAG for education → earnings; IV using distance to college
/scholar-compute run STM topic model on newspaper corpus
/scholar-open preregistration template for survey experiment
/scholar-replication full for Demography
/scholar-ling analyze discourse of immigration restrictionism
# Ethics and safety
/scholar-init nhanes-bmi ~/Downloads/nhanes.csv    # stand up a project + scan raw files (v5.9.0)
/scholar-init review                                # resolve NEEDS_REVIEW entries interactively
/scholar-init status                                # print sidecar and init-report state
/scholar-ethics pre-submission ethics check for Demography
/scholar-safety scan data.csv before analysis

# Qualitative methods
/scholar-qual codebook develop codebook for interview study on immigrant identity
/scholar-qual open-coding transcripts/*.txt grounded theory
/scholar-qual thematic 20 parent interviews on school choice
/scholar-qual llm-coding code 500 open-ended survey responses using codebook.csv
/scholar-qual reliability assess inter-coder reliability for 3 coders

# Collaboration
/scholar-collaborate credit 4-author paper on immigrant integration
/scholar-collaborate tasks multi-site ethnography project

# Verification and synchronization
/scholar-verify full output/drafts/full-paper-2026-03-10.md
/scholar-verify stage1
/sync-docs slides.tex script.tex manuscript.tex

# Peer review cycle
/scholar-respond simulate paper.pdf for ASR
/scholar-respond respond reviews.txt paper.pdf
/scholar-respond revise paper.pdf reviews.txt response.txt
```

## 完整研究工作流

```
Research Question
       │
       ├─► /scholar-idea              ← Explore broad idea and formalize RQs
       │
       ├─► /scholar-brainstorm        ← Generate RQs from codebooks, questionnaires, or datasets
       │
       └─► (or run modular skills below)
       │
       ├─► /scholar-init              ← (v5.9.0) Create project layout, copy raw files, scan +
       │                                  populate .claude/safety-status.json (PreToolUse hook enforces)
       │
       ├─► /scholar-data              ← Find open datasets (100+ sources), auto-fetch, design collection
       │
       ├─► /scholar-safety            ← Scan data files for PII/sensitive data before AI processing
       │
       ├─► /scholar-lit-review        ← Systematic literature synthesis
       │
       ├─► /scholar-lit-review-hypothesis ← Integrated lit review + theory + hypotheses
       │
       ├─► /scholar-hypothesis        ← Theory + hypotheses (incl. intersectionality,
       │                                  non-Western frameworks)
       │
       ├─► /scholar-conceptual        ← Theory building + conceptual diagrams (TikZ/Mermaid)
       │
       ├─► /scholar-design            ← Research design, power analysis, experiments
       │
       ├─► /scholar-causal            ← Causal inference toolkit (DAG + 13 strategies + sensitivity)
       │
       ├─► /scholar-eda               ← EDA, missing data, cleaning, pre-analysis plan
       │
       ├─► /scholar-analyze           ← Regression interpretation, robustness
       │
       ├─► /scholar-compute           ← NLP / ML / networks (if computational)
       │
       ├─► /scholar-write             ← Draft all sections
       │
       ├─► /scholar-verify            ← 4-agent analysis-to-manuscript consistency check
       │
       ├─► /scholar-openai            ← External second-opinion review (5 Codex agents)
       │
       ├─► /scholar-citation          ← Insert citations, build reference list, audit
       │
       ├─► /scholar-knowledge         ← Persist extracted findings, theories, relationships
       │                                  across projects (layers on Zotero)
       │
       ├─► /sync-docs                 ← Synchronize slides, script, and manuscript
       │
       ├─► /scholar-journal           ← Format for target journal
       │
       ├─► /scholar-open              ← Preregistration, data/code sharing, open access
       │
       ├─► /scholar-replication       ← Build, test, and archive replication packages
       │
       ├─► /scholar-ethics            ← AI audit, plagiarism check, integrity audit, compliance
       │
       ├─► /scholar-respond           ← Simulate review → respond → revise
       │                                  (handles conflicting reviewers +
       │                                   resubmission strategy if rejected)
       │
       ├─► /scholar-qual              ← Qualitative coding, grounded theory, thematic analysis, LLM-assisted coding
       │
       ├─► /scholar-ling              ← Sociolinguistics, discourse analysis, variationist methods
       │
       └─► /scholar-collaborate       ← Multi-author collaboration (CRediT, tasks, mentoring)
```

## 引用

如果你在研究、教学或任何衍生作品中使用了 **open-scholar-skill**，请引用介绍它的已发表论文：

> Zhang, Yongjun. 2026. "Vibe Researching: Can AI Agents with Skills Replace or Augment Social Scientists?" *Chinese Sociological Review*. https://doi.org/10.1080/21620555.2026.2707167

BibTeX:

```bibtex
@article{zhang2026vibe,
  title   = {Vibe Researching: Can AI Agents with Skills Replace or Augment Social Scientists?},
  author  = {Zhang, Yongjun},
  journal = {Chinese Sociological Review},
  year    = {2026},
  pages   = {1--36},
  doi     = {10.1080/21620555.2026.2707167},
  url     = {https://doi.org/10.1080/21620555.2026.2707167}
}
```

arXiv 上也提供开放获取的预印本——但**请引用上面的已发表版本**，而非预印本：

> Zhang, Yongjun. 2026. "Vibe Researching as Wolf Coming: Can AI Agents with Skills Replace or Augment Social Scientists?" *arXiv preprint* [arXiv:2602.22401](https://arxiv.org/abs/2602.22401).

你的引用有助于本技能套件的持续开发，也向期刊和评审人表明：此处使用的 AI 辅助工作流具有可查证的方法论依据。
