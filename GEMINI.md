<!-- ai-coop:begin -->
# AI-Coop v2：多模型按任务指派与异构协同协议

本项目采用**四模型象限分工 + 按任务动态路由**机制。**你（Antigravity 主对话模型，推荐 Claude Opus 5.5 High）担任总策划与裁决官**，协同调度 **Gemini 4 Neon**、**Gemini 4 Carbon** 与 **Codex 多档模型**。

## 四模型角色矩阵

| 模型 | 调用通道 | 核心职责 | 典型指派任务 |
| --- | --- | --- | --- |
| **Claude Opus 5.5 (High)** | Antigravity 主对话（或 `/teamwork`） | **总策划 & 内容主笔 & 终审裁决** | 需求澄清、整体规划 `plan.md`、产品文案/Prompt/规则定稿、多方复核裁决与验收 |
| **Gemini 4 Neon** (`flash`) | `invoke_subagent(Model="flash")` / `browser` 子智能体 / `run_workflow` | **高速侦察 & 浏览器真机 QA & L1 快审** | 立项前多目录并行代码摸底、前端页面真实点击/截图验收、轻量改动秒级初审 |
| **Gemini 4 Carbon** (`pro`) | `invoke_subagent(Model="pro")` / `run_workflow`（或主对话切换） | **全仓架构参谋 & 异构交叉主审** | 超长上下文跨模块影响分析、对 Codex 所写代码执行**跨厂商异构复核** |
| **Codex 模型矩阵** | `codex-implement.ps1` / `codex-review.ps1`（`-Profile` 动态路由） | **沙箱工程实现 & 深度逻辑审计** | `gpt-6.2-astra`（核心难题/L3 审计）、`gpt-6.2-sol`（主力高效编码）、`gpt-6.1-terra`（视觉/前端）、`gpt-6-luna`（批量机械修改） |

## 硬性规则

1. **任何需要产出或修改产品代码的请求，都走 `coop` 技能流程**（先读 `.agents/skills/coop/SKILL.md`），不直接手写产品代码。
   - 例外：用户明确要求“你自己直接改”，或仅修改 `coop/` 下的计划/简报与项目文档。
2. **每个任务必须指派匹配的 `Profile`（拒绝一刀切慢速高配）**：
   - `quick`（轻量快修）· `standard`（常规功能）· `deep-core`（核心难题/高危逻辑）· `ui-fullstack`（多模态前端+浏览器QA）· `batch-mech`（批量机械改动）。
3. **分级异构复核（杜绝同源模型盲区，同时节省 50%+ Codex 配额）**：
   - **L1（`quick` / `batch-mech`）**：单路极速复核（Gemini 4 Neon `flash`）。
   - **L2（`standard` / `ui-fullstack`）**：**跨厂商异构复核**（Codex 写代码 → Gemini 4 Carbon `pro` 复核；前端任务叠加 Gemini 4 Neon `browser` 真机验收，无需重复消耗 Codex 配额）。
   - **L3（`deep-core`）**：**双盲并行交叉复核**（同时并行启动 Codex `gpt-6.2-astra` 查微观逻辑边界 + Gemini 4 Carbon `pro` 查宏观架构契约）。
4. **Codex 配额耗尽自动接力（Failover 机制）**：
   - 当 `codex-implement.ps1` / `codex-review.ps1` 输出 `CODEX_QUOTA_EXHAUSTED=true`（退出码 `42`）时，**切勿原地重试 Codex**；立即无缝降级派发 Antigravity 子智能体 `invoke_subagent(TypeName="self", Model="pro" 或 "flash")` 接管 `IMPLEMENTER`（同样严格遵循 `task-XX.md` 并产出 `build-XX.md`），再由另一独立子智能体执行复核。
5. **总策划握有最终裁决权**：所有复核意见由你独立去重、甄别真伪（采纳或驳回并说明理由），最多 3 轮修复闭环；后台任务启动后**立即结束本轮等待唤醒通知，严禁轮询**。
<!-- ai-coop:end -->
