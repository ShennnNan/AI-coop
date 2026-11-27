param(
    [Parameter(Mandatory = $true)]
    [string]$JobId,
    [string]$Brief = "task-01.md",
    [string]$BuildReport = "",
    [string]$Round = "",
    [string]$Model = "",
    [string]$ReasoningEffort = "",
    [switch]$EnableMcp,
    [switch]$PersistSession,
    [string]$Workspace = "",
    [int]$TimeoutSeconds = 900,
    [string]$Profile = "",
    [string]$ServiceTier = ""
)

. (Join-Path $PSScriptRoot "coop-common.ps1")

$ws = Resolve-WorkspaceRoot -Workspace $Workspace
$jobDir = Join-Path $ws "coop\jobs\$JobId"
if (-not (Test-Path -LiteralPath $jobDir)) {
    throw "找不到 Job 目录: $jobDir"
}

$planPath = Join-Path $jobDir "plan.md"
if (-not (Test-Path -LiteralPath $planPath)) {
    throw "找不到整体计划文件: $planPath"
}

$briefName = if ($Brief.EndsWith(".md", [System.StringComparison]::OrdinalIgnoreCase)) { $Brief } else { "$Brief.md" }
$briefPath = Join-Path $jobDir $briefName
if (-not (Test-Path -LiteralPath $briefPath)) {
    throw "找不到任务简报文件: $briefPath"
}

if (-not $Round) {
    if ($briefName -match '^(task|fix)-(.+)\.md$') {
        $prefix = $Matches[1]
        $num = $Matches[2]
        $Round = if ($prefix -eq "fix") { "fix-$num" } else { $num }
    } else {
        $Round = [System.IO.Path]::GetFileNameWithoutExtension($briefName)
    }
}

if (-not $BuildReport) {
    $BuildReport = "build-$Round.md"
}
$buildPath = Join-Path $jobDir $BuildReport
$buildSection = if (Test-Path -LiteralPath $buildPath) {
    Read-Utf8File -Path $buildPath
} else {
    "（未找到 $BuildReport，请直接根据仓库实际文件与 diff 进行复核）"
}

$schemaPath = Join-Path (Split-Path -Parent $PSScriptRoot) "resources\review.schema.json"
if (-not (Test-Path -LiteralPath $schemaPath)) {
    throw "找不到复核 JSON Schema: $schemaPath"
}

$reviewJsonFile = Join-Path $jobDir "review-$Round.json"
$reviewMdFile = Join-Path $jobDir "review-$Round.md"
$logPrefix = Join-Path $jobDir "logs\review-$Round"

$planText = Read-Utf8File -Path $planPath
$briefText = Read-Utf8File -Path $briefPath
$gitSnapshot = Get-GitSnapshot -WorkspaceRoot $ws

# If task-01.md also exists when reviewing a fix-XX.md round, include original acceptance criteria context
$origTaskContext = ""
if ($briefName -like "fix-*" -and (Test-Path -LiteralPath (Join-Path $jobDir "task-01.md"))) {
    $origTaskHeader = "`n---`n## 附：原始任务简报（``coop/jobs/$JobId/task-01.md``，供对照完整验收标准）`n"
    $origTaskContext = $origTaskHeader + (Read-Utf8File -Path (Join-Path $jobDir "task-01.md"))
}

$promptTemplate = @'
你现在的角色是 **REVIEWER（独立代码复核者）**，运行在全新的独立会话与只读沙箱中。
请严格遵守项目根目录 `AGENTS.md` 中的 AI-Coop 复核协议，带着审视眼光独立核查代码实现，切勿盲信实现者报告。

## 复核任务要求
1. **只读核查**：不修改任何文件。请直接阅读被改动源码与测试文件，并在可用时执行 `git diff`、`git status` 或只读检查命令核实真实代码状态。
2. **逐条对照验收标准**：结合 `plan.md` 与简报中的“验收标准”逐项核实，给出 `met` / `partial` / `missing` 及具体证据（文件名 + 行号 + 逻辑或测试依据）。
3. **深度代码审查**：重点检查逻辑正确性、边界条件、异常/错误处理、编码与路径兼容（尤其 Windows 环境）、安全隐患、测试真实覆盖度、以及是否越界修改了无关文件。
4. **严格判定规则**：
   - 存在任意 `P0` 或 `P1` 问题，或任一验收标准为 `missing` / `partial` → `verdict` 必须为 `"request_changes"`
   - 因缺少关键文件或环境导致无法评审 → `"blocked"`
   - 其余情况 → `"approve"`
5. **输出要求**：严格输出符合 JSON Schema 的 JSON，所有说明文字使用中文，只报告有事实与代码行号依据的问题，不为凑数挑刺。

---
## 附：当前仓库状态快照
{{GIT_SNAPSHOT}}

---
## 附：整体计划（`coop/jobs/{{JOB_ID}}/plan.md`）
{{PLAN_TEXT}}
{{ORIG_TASK_CONTEXT}}
---
## 附：本轮任务/修复简报（`coop/jobs/{{JOB_ID}}/{{BRIEF_NAME}}`）
{{BRIEF_TEXT}}

---
## 附：实现者自述报告（`coop/jobs/{{JOB_ID}}/{{BUILD_REPORT}}`，仅供参考，须核对源码验证）
{{BUILD_SECTION}}
'@

$prompt = $promptTemplate.
    Replace("{{JOB_ID}}", $JobId).
    Replace("{{BRIEF_NAME}}", $briefName).
    Replace("{{BUILD_REPORT}}", $BuildReport).
    Replace("{{GIT_SNAPSHOT}}", $gitSnapshot).
    Replace("{{PLAN_TEXT}}", $planText).
    Replace("{{ORIG_TASK_CONTEXT}}", $origTaskContext).
    Replace("{{BRIEF_TEXT}}", $briefText).
    Replace("{{BUILD_SECTION}}", $buildSection)

$resolvedProfile = Resolve-TaskProfile -ExplicitProfile $Profile -BriefPath $briefPath -JobDir $jobDir
$stageCfg = Resolve-CodexStageConfig `
    -ProfileName $resolvedProfile `
    -Stage "review" `
    -Model $Model `
    -ReasoningEffort $ReasoningEffort `
    -ServiceTier $ServiceTier

Write-Output "[AI-Coop] 启动 Codex REVIEWER（独立只读会话） | Job=$JobId | Round=$Round | Profile=$($stageCfg.Profile) | Model=$($stageCfg.Model) | Effort=$($stageCfg.ReasoningEffort) | Tier=$($stageCfg.ServiceTier)"
$res = Invoke-CodexExec `
    -WorkspaceRoot $ws `
    -Prompt $prompt `
    -OutputFile $reviewJsonFile `
    -LogPrefix $logPrefix `
    -Sandbox "read-only" `
    -OutputSchema $schemaPath `
    -Model $stageCfg.Model `
    -ReasoningEffort $stageCfg.ReasoningEffort `
    -ServiceTier $stageCfg.ServiceTier `
    -EnableMcp:$EnableMcp `
    -PersistSession:$PersistSession `
    -TimeoutSeconds $TimeoutSeconds

Write-CoopStageMeta `
    -Path "$logPrefix.meta.json" `
    -JobId $JobId `
    -Stage "review" `
    -Round $Round `
    -Brief $briefName `
    -StageConfig $stageCfg `
    -Sandbox "read-only" `
    -ExecResult $res

if ($res.QuotaExhausted) {
    Write-Output "CODEX_QUOTA_EXHAUSTED=true"
    Write-Output "FAILOVER_SUBAGENT_MODEL=$($stageCfg.AntigravityReviewer)"
    Write-Warning "Codex REVIEWER 触发配额限制 (ExitCode=$($res.ExitCode), 耗时=$($res.DurationSeconds)s)。请切换 Antigravity 复核子智能体 (Model=$($stageCfg.AntigravityReviewer)) 接力复核。"
    exit 42
}

if ($res.ExitCode -ne 0) {
    Write-Error "Codex REVIEWER 非零退出 (ExitCode=$($res.ExitCode), 耗时=$($res.DurationSeconds)s)`nStderr 摘要:`n$($res.StderrPreview)" -ErrorAction Continue
    exit $res.ExitCode
}

if (-not (Test-Path -LiteralPath $reviewJsonFile)) {
    throw "Codex REVIEWER 未生成 JSON 结果: $reviewJsonFile。请检查日志: $($res.StderrLog)"
}

$rawJson = Read-Utf8File -Path $reviewJsonFile
$review = $rawJson | ConvertFrom-Json

# Render human-readable Markdown companion report for Antigravity planner & user inspection
$md = New-Object System.Text.StringBuilder
[void]$md.AppendLine("# 代码复核报告（Round: $Round）")
[void]$md.AppendLine()
[void]$md.AppendLine("- **Job ID**: ``$JobId``")
[void]$md.AppendLine("- **路由档位 / 复核模型**: ``$($stageCfg.Profile)`` / ``$($stageCfg.Model) ($($stageCfg.ReasoningEffort), tier=$($stageCfg.ServiceTier))``")
[void]$md.AppendLine("- **复核结论 (Verdict)**: **$($review.verdict)**")
[void]$md.AppendLine("- **耗时**: $($res.DurationSeconds)s")
[void]$md.AppendLine("- **范围合规**: $($review.scope_check.within_scope) — $($review.scope_check.notes)")
[void]$md.AppendLine()
[void]$md.AppendLine("## 总体评价")
[void]$md.AppendLine($review.summary)
[void]$md.AppendLine()
[void]$md.AppendLine("## 验收标准核查")
[void]$md.AppendLine("| 状态 | 验收标准 | 证据与说明 |")
[void]$md.AppendLine("| --- | --- | --- |")
$criteriaList = @($review.acceptance_criteria)
$findingsList = @($review.findings)

foreach ($ac in $criteriaList) {
    $crit = ($ac.criterion -replace '\|', '\|' -replace '\r?\n', ' ')
    $evid = ($ac.evidence -replace '\|', '\|' -replace '\r?\n', ' ')
    [void]$md.AppendLine("| **$($ac.status)** | $crit | $evid |")
}
[void]$md.AppendLine()
[void]$md.AppendLine("## 发现问题列表（共 $($findingsList.Count) 项）")
if ($findingsList.Count -eq 0) {
    [void]$md.AppendLine("- 无问题。")
} else {
    foreach ($f in $findingsList) {
        $loc = if ($null -ne $f.line) { "$($f.file):$($f.line)" } else { "$($f.file)" }
        [void]$md.AppendLine("### [$($f.severity)] $($f.id): $($f.title)")
        [void]$md.AppendLine("- **位置**: ``$loc``")
        [void]$md.AppendLine("- **详情**: $($f.detail)")
        [void]$md.AppendLine("- **建议**: $($f.suggestion)")
        [void]$md.AppendLine()
    }
}
[void]$md.AppendLine("## 测试评估")
[void]$md.AppendLine($review.test_assessment)

Write-Utf8File -Path $reviewMdFile -Content $md.ToString()

Write-Output "[AI-Coop] Codex REVIEWER 完成 | Verdict=$($review.verdict) | Findings=$($findingsList.Count) | 耗时=$($res.DurationSeconds)s"
Write-Output "REVIEW_JSON=$reviewJsonFile"
Write-Output "REVIEW_MD=$reviewMdFile"
Write-Output "===== REVIEW SUMMARY ($Round) ====="
Write-Output $md.ToString()
