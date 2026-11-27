param(
    [Parameter(Mandatory = $true)]
    [string]$Slug,
    [string]$Title = "",
    [string]$Profile = "standard",
    [string]$Workspace = ""
)

. (Join-Path $PSScriptRoot "coop-common.ps1")

$resolvedProfile = Resolve-TaskProfile -ExplicitProfile $Profile
$ws = Resolve-WorkspaceRoot -Workspace $Workspace
$cleanSlug = ($Slug.ToLowerInvariant() -replace '[^a-z0-9\-_]+', '-').Trim('-')
if (-not $cleanSlug) {
    throw "Slug 不能为空，请使用英文短横线命名，如 auth-refactor 或 video-pipeline。"
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$jobId = "$timestamp-$cleanSlug"
$jobDir = Join-Path $ws "coop\jobs\$jobId"
$logsDir = Join-Path $jobDir "logs"

New-Item -ItemType Directory -Path $logsDir -Force | Out-Null

$templatesDir = Join-Path (Split-Path -Parent $PSScriptRoot) "resources\templates"
$planTplPath = Join-Path $templatesDir "plan.template.md"
$taskTplPath = Join-Path $templatesDir "task.template.md"

$displayTitle = if ($Title) { $Title } else { $cleanSlug }
$createdAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

if (Test-Path -LiteralPath $planTplPath) {
    $planContent = (Read-Utf8File -Path $planTplPath).
        Replace("{{JOB_ID}}", $jobId).
        Replace("{{TITLE}}", $displayTitle).
        Replace("{{PROFILE}}", $resolvedProfile).
        Replace("{{CREATED_AT}}", $createdAt)
} else {
    $planContent = "# 整体计划：$displayTitle`n`n- Job ID: ``$jobId```n- **Profile**: ``$resolvedProfile```n- 创建时间: $createdAt`n"
}

if (Test-Path -LiteralPath $taskTplPath) {
    $taskContent = (Read-Utf8File -Path $taskTplPath).
        Replace("{{JOB_ID}}", $jobId).
        Replace("{{TASK_ID}}", "task-01").
        Replace("{{TITLE}}", $displayTitle).
        Replace("{{PROFILE}}", $resolvedProfile)
} else {
    $taskContent = "# 任务简报：task-01`n`n- Job ID: ``$jobId```n- **Profile**: ``$resolvedProfile```n"
}

$planFile = Join-Path $jobDir "plan.md"
$taskFile = Join-Path $jobDir "task-01.md"

Write-Utf8File -Path $planFile -Content $planContent
Write-Utf8File -Path $taskFile -Content $taskContent

$meta = [ordered]@{
    job_id     = $jobId
    title      = $displayTitle
    profile    = $resolvedProfile
    created_at = $createdAt
    status     = "planning"
    workspace  = $ws
} | ConvertTo-Json -Depth 4
Write-Utf8File -Path (Join-Path $jobDir "job.json") -Content $meta

Write-Output "JOB_CREATED=$jobId"
Write-Output "PROFILE=$resolvedProfile"
Write-Output "JOB_DIR=$jobDir"
Write-Output "PLAN_FILE=$planFile"
Write-Output "TASK_FILE=$taskFile"
