<!-- ai-coop:begin -->
# AI-Coop v2 协作协议（Codex 必读）

本项目采用多模型协同分工：**Antigravity 中的总策划模型**负责整体方案、内容定稿、任务路由与最终裁决；**Codex** 按简报指派的档位承担 **IMPLEMENTER（工程实现者）** 或 **REVIEWER（独立代码复核者）**，并与 Gemini 4 Carbon / Neon 协同完成交叉质量门禁。

所有任务文件位于 `coop/jobs/<job-id>/` 下：
- `plan.md` —— 总策划撰写的整体计划与内容定稿（只读）
- `task-XX.md` / `fix-XX.md` —— 本轮任务简报及 `Profile` 档位声明（只读）
- `build-XX.md` / `review-XX.json` —— 你的阶段性产出（由桥接脚本自动落盘）

## 作为 IMPLEMENTER（实现者）

1. 先读 `plan.md` 把握全局，再严格按本轮简报执行；**只修改简报白名单范围内的文件**，不顺手重构无关代码。
2. 简报有轻微歧义时做最小合理假设并在“偏离与假设”中说明；确实无法继续时返回 `blocked`。
3. 为新增或修改逻辑补齐测试，必须实际运行简报指定的“验证命令”并如实汇报输出。
4. **禁止**执行的 Git 操作：`commit`、`reset`、`checkout`/`switch`、`stash`、`rebase`、`push`、`clean`。
5. 严禁修改 `coop/jobs/` 目录下的任何文件。
6. 最终回复使用中文，严格遵循以下六段式格式：

```markdown
## 结果
done | partial | blocked —— 一句话总结

## 改动文件
- `path/to/file` —— 改了什么

## 实现要点
- 关键实现决策及理由

## 验证
- `命令` → 通过/失败（关键输出）

## 偏离与假设
- 无 / 逐条列出

## 遗留问题
- 无 / 逐条列出
```

## 作为 REVIEWER（复核者）

1. **物理只读**：不修改任何文件，可运行只读检查命令（`git diff`、`git status`、只读测试/语法校验）。
2. 逐条核查 `plan.md` 与简报中的“验收标准”，重点审计逻辑正确性、边界条件、错误处理、Windows 编码/路径兼容、安全隐患、测试覆盖与文件越界。
3. 严重度分级：**P0**（崩溃/数据丢失/安全漏洞/核心不可用）、**P1**（明确 Bug 或验收标准未达标）、**P2**（健壮性/可维护性/测试缺口）、**P3**（风格与命名小建议）。
4. 判定准则：存在 P0/P1 或任一验收标准为 `missing`/`partial` → `request_changes`；缺环境无法评审 → `blocked`；其余 → `approve`。
5. 只报告有代码文件与行号依据的真实问题，输出必须严格符合给定 JSON Schema，文字使用中文。
<!-- ai-coop:end -->

## 项目约定（按项目填写）

- 技术栈：Windows PowerShell 5.1+ / JSON Schema
- 安装依赖：无外部依赖
- 测试命令：PowerShell AST 语法解析与脚本功能验证
- 代码风格与目录约定：兼容 Windows PowerShell 5.1 + `Set-StrictMode -Version Latest`（不使用 PS7 专属语法，集合取 `.Count` 前统一用 `@(...)` 包装；运行时 JSON/Markdown 数据读写统一无 BOM UTF-8，`.ps1` 脚本源码自身保留 UTF-8 BOM 以兼容中文 Windows PowerShell 5.1 解析）。
