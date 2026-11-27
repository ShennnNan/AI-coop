# AI-Coop v2：四模型象限分工与按任务动态路由框架

一套专为本机 **Antigravity（Claude Opus 5.5 High + Gemini 4 Carbon + Gemini 4 Neon）× OpenAI Codex（Astra / Sol / Terra / Luna）** 打造的异构多智能体协同系统。

---

## 一、核心设计：告别“单模型一刀切”，按任务指派最擅长模型

v1 双智能体流程有两个天然瓶颈：一是无论大小任务都跑同一高耗时配置；二是“实现”与“复核”同属单一模型家族，容易共享同类盲区。

**AI-Coop v2** 将你电脑上四大模型家族的长板组合成流水线与并行矩阵：

| 模型 | 角色定位 | 调用方式 | 最擅长的事 |
| --- | --- | --- | --- |
| **Claude Opus 5.5 (High)** | **总策划 & 内容主笔 & 裁决官** | Antigravity 主对话 | 复杂需求推演、产品交互品味、高质感文案/Prompt 定稿、汇总多方复核做最终裁决 |
| **Gemini 4 Neon** (`flash`) | **高速侦察兵 & 浏览器 QA & L1 快审** | `invoke_subagent(Model="flash")` / `browser` | 秒级并行检索多目录代码、驱动内置浏览器真机点击/截图验收、小改动秒级初审 |
| **Gemini 4 Carbon (High)** (`pro`) | **全仓架构参谋 & 异构主审** | `invoke_subagent(Model="pro")` / 主对话切换 | 百万级上下文全仓依赖评估、对 Codex 代码执行**跨厂商异构复核**（抓架构偏离与跨文件契约破坏） |
| **Codex `gpt-6.2-astra`** | **重装攻坚 & L3 深度逻辑审计** | `-Profile deep-core` | 复杂算法、并发状态机、底层疑难 Bug、安全敏感逻辑实现与微观边界审计 |
| **Codex `gpt-6.2-sol`** | **高速主力工程机** | `-Profile standard` / `quick` | 日常 80% 业务代码与单测闭环主力（默认省流通道，按需可开 `priority` 2 倍速） |
| **Codex `gpt-6.1-terra` / `gpt-6-luna`** | **视觉前端专科 / 批量机械工兵** | `-Profile ui-fullstack` / `batch-mech` | 结合 `-Images` 还原设计稿，或低成本高吞吐完成机械替换与单测补全 |

---

## 二、五档任务路由表（自动识别 `task-XX.md` 中的 `Profile`）

配置文件位于 [model-profiles.json](./.agents/skills/coop/resources/model-profiles.json)，每个子任务在 `task-XX.md` 中声明 `Profile` 即可自动路由：

| Profile | 典型任务 | 前置侦察 | 实现模型 (Codex 主力 / Antigravity 自动接力) | 分级异构复核策略 |
| --- | --- | --- | --- | --- |
| `quick` | 小修小补、配置同步、样板代码 | 直读文件 | `gpt-6.2-sol` (`low`) · *满额接力: Neon (`flash`)* | **L1**：**Gemini 4 Neon** (`flash`) 秒级单审 |
| `standard` | 常规功能开发、接口与模块重构 | **Neon** (`flash`) 并行摸底 | `gpt-6.2-sol` (`high`) · *满额接力: Carbon (`pro`)* | **L2**：**Gemini 4 Carbon** (`pro`) 跨厂商异构主审 |
| `deep-core` | 核心算法、并发/状态机、高危重构 | **Neon** + **Carbon** 联合摸底 | **`gpt-6.2-astra`** (`high`/`xhigh`) · *满额接力: Carbon (`pro`)* | **L3**：**Codex Astra + Gemini 4 Carbon 同轮并行双盲复核** |
| `ui-fullstack` | 前端界面、设计稿还原、交互开发 | **Neon** (`flash`) 摸底组件 | `gpt-6.1-terra`（`-Images`）· *满额接力: Carbon (`pro`)* | **L2+UI**：**Neon Browser** 真机交互验收 + **Carbon** 审代码 |
| `batch-mech` | 批量重命名、格式化、机械补单测 | `flash_lite` 扫描清单 | `gpt-6-luna` (`medium`) · *满额接力: Neon (`flash`)* | **L1**：测试门禁 + **Neon** (`flash`) 快速抽检 |

> **内置配额保护与断流自动接力（Quota Protection & Failover）**：
> 1. **立省 50%+ Codex 配额**：侦察与 L1/L2 复核默认走 Antigravity 的 **Gemini 4 Neon / Carbon**，且默认使用 `service_tier = "default"`（避免 `priority` 双倍扣费；赶时间可手动加 `-ServiceTier priority`）。
> 2. **零中断故障转移**：当 Codex 触发窗口配额上限时，脚本自动识别并输出 `CODEX_QUOTA_EXHAUSTED=true`（退出码 `42`），总策划自动切换 **Gemini 4 Carbon (`pro`) / Neon (`flash`)** 子智能体按同一份 `task-XX.md` 接力完成开发与交叉复核。

---

## 三、常用命令与日常用法

### 1. 日常对话（最省心）
保持 Antigravity 主对话为 **Claude Opus 5.5 (High)**，直接提需求即可（例如：*“帮我重构这个核心调度模块，走 `deep-core` 档让 Astra 实现并用 Carbon + Codex 双盲复核”*，或交由总策划自动为每个子任务挑选 `Profile`）。

### 2. 安装与脚本命令速查
```powershell
# 克隆仓库并安装全局 Antigravity 技能 + 终端 codex 命令垫片
git clone https://github.com/ShennnNan/AI-coop.git
cd AI-coop
powershell -NoProfile -ExecutionPolicy Bypass -File .\install-coop.ps1 -Global -AddCodexShimToPath

# （可选）为指定项目注入常驻免点名协作规则（GEMINI.md + AGENTS.md + 项目级 coop 技能）
powershell -NoProfile -ExecutionPolicy Bypass -File .\install-coop.ps1 -TargetProject "D:\path\to\your-project"

# 查看所有模型路由档位详情
powershell -NoProfile -ExecutionPolicy Bypass -File .\.agents\skills\coop\scripts\coop-status.ps1 -ListProfiles

# 新建指定档位的任务（默认 standard）
powershell -NoProfile -ExecutionPolicy Bypass -File .\.agents\skills\coop\scripts\new-job.ps1 -Slug "core-engine" -Title "核心引擎改造" -Profile "deep-core"

# 启动实现（自动从 task-01.md 读取 Profile，也可传 -Profile / -Model / -ReasoningEffort / -Images 覆盖）
powershell -NoProfile -ExecutionPolicy Bypass -File .\.agents\skills\coop\scripts\codex-implement.ps1 -JobId "<JobId>" -Brief "task-01.md"

# 启动独立只读 Codex 复核
powershell -NoProfile -ExecutionPolicy Bypass -File .\.agents\skills\coop\scripts\codex-review.ps1 -JobId "<JobId>" -Brief "task-01.md"
```

### 3. 超大型项目进阶组合技
- **`/grill-me` 或 `/plan`**：开局让 Opus 与你把架构和产品文案打磨到零歧义。
- **`/goal`**：让总策划自动推进多个不同 `Profile` 子任务的全闭环交付。
- **`/teamwork`**：开启 Antigravity 原生多智能体面板，为常驻角色分别绑定具名的 `Claude Opus 5.5 (High)`、`Gemini 4 Carbon (High)`、`Gemini 4 Neon` 并配合 `share` 独立工作区并行推进。
