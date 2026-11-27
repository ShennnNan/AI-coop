---
name: coop
description: >-
  Orchestrates the AI-Coop v2 multi-model workflow combining Claude Opus 5.5 High (Chief Planner & Content Architect), Gemini 4 Neon (Fast Recon & Browser QA), Gemini 4 Carbon (Architecture Consult, Cross-Family Reviewer & Failover Builder), and Codex CLI (Task-Routed Code Implementer & Deep Logic Auditor across gpt-6.2-astra, gpt-6.2-sol, gpt-6.1-terra, gpt-6-luna). Activate whenever creating, modifying, refactoring, debugging, or reviewing code under AI-Coop rules, or when assigning models per task.
---

# AI-Coop v2 多模型分级路由与异构协同手册

本工作流打通 **Antigravity 原生多模型子智能体（Claude Opus 5.5 High + Gemini 4 Carbon + Gemini 4 Neon）** 与 **Codex CLI 多模型沙箱**，实现**按任务难度精准派单 + 跨厂商异构交叉复核 + 配额耗尽无缝接力**。

所有脚本位于本技能目录 `scripts/` 下，路由配置位于 `resources/model-profiles.json`。

---

## 一、五档任务路由表（Per-Task Model Routing）

在每个 `task-XX.md` 顶部标记 `- **Profile**: <档位>`（或脚本传 `-Profile`），系统自动匹配最佳模型组合与推理强度：

| Profile 档位 | 适用场景 | 前置侦察 (Antigravity) | 编码实现 (主力 Codex / 满额接力) | 复核策略 (Review Gate) |
| --- | --- | --- | --- | --- |
| **`quick`** | 小修小补、配置同步、简单样板代码 | 无需或主对话直读 | `gpt-6.2-sol` (`low`, `default`) · *接力: Neon (`flash`)* | **L1 极速单审**：派 `research` 子智能体（`Model="flash"` **Gemini 4 Neon**）秒级核查 diff |
| **`standard`**（默认） | 常规业务功能、API 开发、中型重构 | `research` 子智能体（`Model="flash"` **Neon** 并行摸底） | `gpt-6.2-sol` (`high`, `default`) · *接力: Carbon (`pro`)* | **L2 异构主审**：派 `research` 子智能体（`Model="pro"` **Gemini 4 Carbon**）跨厂商审查（省去二次 Codex 消耗） |
| **`deep-core`** | 核心算法、状态机/并发、底层架构改造、高危安全逻辑 | **Neon** (`flash`) 搜调用链 + **Carbon** (`pro`) 评全仓影响 | **`gpt-6.2-astra`** (`high` / `xhigh`) · *接力: Carbon (`pro`)* | **L3 双盲并行交叉复核**：**同时**启动 `codex-review.ps1 -Profile deep-core` **+** **Gemini 4 Carbon** (`Model="pro"`) |
| **`ui-fullstack`** | 前端页面、视觉稿还原、交互组件 | **Neon** (`flash`) 摸底现有组件 | `gpt-6.1-terra`（支持 `-Images`）· *接力: Carbon (`pro`)* | **L2 视觉+代码双验**：`browser` 子智能体（`Model="flash"` **Neon**）真机操作截图 + **Carbon** (`pro`) 审代码 |
| **`batch-mech`** | 批量机械替换、补简单单测、格式化迁移 | `flash_lite` / `flash` 扫描清单 | `gpt-6-luna` (`medium`, `default`) · *接力: Neon (`flash`)* | **L1 测试门禁** + **Neon** (`flash`) 快速抽检 |

> **配额保护与手动覆盖**：
> - Codex 的 `service_tier = "priority"` 会产生双倍配额消耗，因此五档默认均为 `"default"`；仅在赶时间时显式传 `-ServiceTier priority` 开启 2 倍速。
> - 任何时候可传 `-Model <slug> -ReasoningEffort <low|medium|high|xhigh|max>` 覆盖档位默认模型；运行 `coop-status.ps1 -ListProfiles` 查看完整配置。
> - **自动配额熔断接力（Quota Failover）**：若脚本返回退出码 `42` 且输出 `CODEX_QUOTA_EXHAUSTED=true`，切勿重试 Codex，立即改调 `invoke_subagent(TypeName="self", Model="pro" 或 "flash")`（在 Prompt 中明确指示其作为接力 IMPLEMENTER 直接编码，不再次调 Codex）读取同一份 `plan.md` + `task-XX.md` 完成实现并写入 `build-XX.md`。

---

## 二、标准 6 步高效闭环

### 第 1 步：高速侦察与需求对齐（Neon 探路 + Opus 拍板）
- **小范围任务**：直接 `read_file` 阅读目标文件。
- **跨目录/大仓库任务**：在同一轮并行调用 1～3 个 `invoke_subagent(TypeName="research", Model="flash", ...)`（**Gemini 4 Neon**），秒级收回模块摘要，保持主对话上下文精简。

### 第 2 步：立项、内容定稿与任务派单（Opus 主笔）
1. 创建协作任务（指定默认 `-Profile`）：
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File "<SkillDir>\scripts\new-job.ps1" -Slug "<slug>" -Title "<标题>" -Profile "standard"
   ```
2. 编写 `coop/jobs/<JobId>/plan.md` 与 `task-01.md`：
   - 在每个 `task-XX.md` 中声明 `- **Profile**: \`<quick|standard|deep-core|ui-fullstack|batch-mech>\``。
   - 所有产品文案、Prompt、接口签名、错误提示、文件白名单、验证命令与验收标准（AC-1, AC-2...）由总策划写实。

### 第 3 步：按档位派发编码实现
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<SkillDir>\scripts\codex-implement.ps1" -JobId "<JobId>" -Brief "task-01.md"
```
- `run_command` 设 `WaitMsBeforeAsync: 10000`、`NotificationTimeoutSeconds: 600`；后台运行期间**立即结束本轮等待通知，严禁轮询**。
- 若遇到 `CODEX_QUOTA_EXHAUSTED=true`（退出码 `42`），立即按档位派发 `Model="pro"`（Gemini 4 Carbon）或 `Model="flash"`（Gemini 4 Neon）子智能体直接完成实现并写入 `build-01.md`。

### 第 4 步：分级异构复核（同轮并行，零额外挂钟等待）
- **L1（`quick` / `batch-mech`）**：调用 `invoke_subagent(TypeName="research", Model="flash", Role="Neon L1 Quick Reviewer", ...)`。
- **L2（`standard` / `ui-fullstack`）**：调用 `invoke_subagent(TypeName="research", Model="pro", Role="Carbon Cross-Family Reviewer", ...)`；前端任务同轮并行调用 `browser` 子智能体（`Model="flash"`）。
- **L3（`deep-core`）**：同轮并行调用 `codex-review.ps1 -JobId "<JobId>" -Brief "task-01.md"` **+** `invoke_subagent(TypeName="research", Model="pro", Role="Carbon Architecture & Security Reviewer", ...)`（若 Codex 配额耗尽，则并行调用 `Model="pro"` 与 `Model="flash"` 两个独立只读子智能体从架构与细节双视角交叉审查）。

### 第 5 步：总策划去重裁决与闭环（最多 3 轮）
- 汇总各方复核意见独立裁决（采纳真问题派发 `fix-01.md`；驳回误报或过度设计 P3）。最多 3 轮未收敛则交用户拍板。

### 第 6 步：总策划终验与交付
- 亲自运行核心验证命令与 `git status --short`，向用户汇报模型路由、裁决结论与改动文件链接。

---

## 三、进阶：`/teamwork` 原生常驻多智能体群组

遇到超大型跨多子系统工程时，可推荐用户输入 `/teamwork`（或 `/swarm`），为各常驻 Worker 分别绑定具名模型（`Claude Opus 5.5 (High)`、`Gemini 4 Carbon (High)`、`Gemini 4 Neon`）并开启 `workspace:"share"` 并行开发。
