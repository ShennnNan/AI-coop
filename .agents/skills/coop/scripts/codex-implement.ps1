param(
    [Parameter(Mandatory = $true)]
    [string]$JobId,
    [string]$Brief = "task-01.md",
    [string]$Round = "",
    [ValidateSet("workspace-write", "danger-full-access")]
    [string]$Sandbox = "workspace-write",
    [string]$Model = "",
    [string]$ReasoningEffort = "",
    [switch]$EnableMcp,
    [switch]$PersistSession,
    [string]$Workspace = "",
    [int]$TimeoutSeconds = 1200,
    [string]$Profile = "",
    [string]$ServiceTier = "",
    [string[]]$Images = @()
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

$outputFile = Join-Path $jobDir "build-$Round.md"
$logPrefix = Join-Path $jobDir "logs\implement-$Round"

$planText = Read-Utf8File -Path $planPath
$briefText = Read-Utf8File -Path $briefPath
$gitSnapshot = Get-GitSnapshot -WorkspaceRoot $ws

$promptTemplate = @'
你现在的角色是 **IMPLEMENTER（工程实现者）**。
请严格遵守项目根目录 `AGENTS.md` 中的 AI-Coop 协作协议。

## 协作上下文路径（只读，切勿修改 `coop/` 下任何文件）
- 整体计划：`coop/jobs/{{JOB_ID}}/plan.md`
- 本轮简报：`coop/jobs/{{JOB_ID}}/{{BRIEF_NAME}}`

## 硬性约束提醒
1. 只实现【本轮简报】明确要求范围内的代码与测试改动，不顺手重构无关文件。
2. 严禁修改 `coop/` 目录下的任何文件；严禁执行 `git commit`、`reset`、`checkout`、`switch`、`stash`、`rebase`、`push`、`clean`。
3. 必须运行本轮简报中的“验证命令”，并在最终报告中如实给出命令和关键输出（失败也必须如实报告）。
4. 最终回复必须使用中文，严格遵循 `AGENTS.md` 中的 `build-XX.md` 六段式 Markdown 结构（`## 结果`、`## 改动文件`、`## 实现要点`、`## 验证`、`## 偏离与假设`、`## 遗留问题`）。

---
## 附：当前仓库状态快照
{{GIT_SNAPSHOT}}

---
## 附：整体计划（`coop/jobs/{{JOB_ID}}/plan.md`）
{{PLAN_TEXT}}

---
## 附：本轮执行简报（`coop/jobs/{{JOB_ID}}/{{BRIEF_NAME}}`）
{{BRIEF_TEXT}}
'@

$prompt = $promptTemplate.
    Replace("{{JOB_ID}}", $JobId).
    Replace("{{BRIEF_NAME}}", $briefName).
    Replace("{{GIT_SNAPSHOT}}", $gitSnapshot).
    Replace("{{PLAN_TEXT}}", $planText).
    Replace("{{BRIEF_TEXT}}", $briefText)

$resolvedProfile = Resolve-TaskProfile -ExplicitProfile $Profile -BriefPath $briefPath -JobDir $jobDir
$stageCfg = Resolve-CodexStageConfig `
    -ProfileName $resolvedProfile `
    -Stage "implement" `
    -Model $Model `
    -ReasoningEffort $ReasoningEffort `
    -ServiceTier $ServiceTier

$validImages = @($Images | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

Write-Output "[AI-Coop] 启动 Codex IMPLEMENTER | Job=$JobId | Brief=$briefName | Profile=$($stageCfg.Profile) | Model=$($stageCfg.Model) | Effort=$($stageCfg.ReasoningEffort) | Tier=$($stageCfg.ServiceTier) | Sandbox=$Sandbox"
$res = Invoke-CodexExec `
    -WorkspaceRoot $ws `
    -Prompt $prompt `
    -OutputFile $outputFile `
    -LogPrefix $logPrefix `
    -Sandbox $Sandbox `
    -Model $stageCfg.Model `
    -ReasoningEffort $stageCfg.ReasoningEffort `
    -ServiceTier $stageCfg.ServiceTier `
    -Images $validImages `
    -EnableMcp:$EnableMcp `
    -PersistSession:$PersistSession `
    -TimeoutSeconds $TimeoutSeconds

Write-CoopStageMeta `
    -Path "$logPrefix.meta.json" `
    -JobId $JobId `
    -Stage "implement" `
    -Round $Round `
    -Brief $briefName `
    -StageConfig $stageCfg `
    -Sandbox $Sandbox `
    -ExecResult $res `
    -ImagesCount $validImages.Count

if ($res.QuotaExhausted) {
    Write-Output "CODEX_QUOTA_EXHAUSTED=true"
    Write-Output "FAILOVER_SUBAGENT_MODEL=$($stageCfg.FailoverModel)"
    Write-Warning "Codex IMPLEMENTER 触发配额限制 (ExitCode=$($res.ExitCode), 耗时=$($res.DurationSeconds)s)。请切换 Antigravity 子智能体 (Model=$($stageCfg.FailoverModel)) 接力执行。"
    exit 42
}

if ($res.ExitCode -ne 0) {
    Write-Error "Codex IMPLEMENTER 非零退出 (ExitCode=$($res.ExitCode), 耗时=$($res.DurationSeconds)s)`nStderr 摘要:`n$($res.StderrPreview)" -ErrorAction Continue
    exit $res.ExitCode
}

if (-not (Test-Path -LiteralPath $outputFile)) {
    throw "Codex 已退出但未生成报告文件: $outputFile。请检查日志: $($res.StderrLog)"
}

$reportText = Read-Utf8File -Path $outputFile
Write-Output "[AI-Coop] Codex IMPLEMENTER 完成 | 耗时=$($res.DurationSeconds)s | 报告=$outputFile"
Write-Output "===== BUILD REPORT ($Round) ====="
Write-Output $reportText
