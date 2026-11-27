param(
    [string]$JobId = "",
    [string]$Workspace = "",
    [switch]$ListProfiles
)

. (Join-Path $PSScriptRoot "coop-common.ps1")

if ($ListProfiles) {
    $cfg = Get-CoopProfilesConfig
    $defaultProfile = [string](Get-ObjectPropertyValue -Object $cfg -Name "default_profile" -Default "standard")
    Write-Output "AI-Coop v2 模型路由档位配置 (默认档位: $defaultProfile)"
    Write-Output "=================================================================="
    foreach ($prop in @($cfg.profiles.PSObject.Properties)) {
        $pName = $prop.Name
        $pObj = $prop.Value
        $desc = [string](Get-ObjectPropertyValue -Object $pObj -Name "description" -Default "")
        $agObj = Get-ObjectPropertyValue -Object $pObj -Name "antigravity"
        $implObj = Get-ObjectPropertyValue -Object $pObj -Name "codex_implement"
        $revObj = Get-ObjectPropertyValue -Object $pObj -Name "codex_review"

        $implModel = [string](Get-ObjectPropertyValue -Object $implObj -Name "model" -Default "")
        $implEffort = [string](Get-ObjectPropertyValue -Object $implObj -Name "reasoning_effort" -Default "")
        $implTier = [string](Get-ObjectPropertyValue -Object $implObj -Name "service_tier" -Default "default")

        $reviewTier = [string](Get-ObjectPropertyValue -Object $agObj -Name "review_tier" -Default "")
        $agReviewer = [string](Get-ObjectPropertyValue -Object $agObj -Name "review_subagent_model" -Default "")
        $failoverModel = [string](Get-ObjectPropertyValue -Object $agObj -Name "failover_implement_model" -Default "")
        $reconModel = Get-ObjectPropertyValue -Object $agObj -Name "recon_model"
        $reconDisplay = if ([string]::IsNullOrWhiteSpace([string]$reconModel)) { "none" } else { [string]$reconModel }

        $revEnabled = [bool](Get-ObjectPropertyValue -Object $revObj -Name "enabled_by_default" -Default $false)
        $revModel = [string](Get-ObjectPropertyValue -Object $revObj -Name "model" -Default "")
        $revEffort = [string](Get-ObjectPropertyValue -Object $revObj -Name "reasoning_effort" -Default "")
        $revTier = [string](Get-ObjectPropertyValue -Object $revObj -Name "service_tier" -Default "default")

        $defaultTag = if ($pName -eq $defaultProfile) { " [默认]" } else { "" }
        Write-Output "[$pName]$defaultTag - $desc"
        Write-Output "  Codex 实现 : model=$implModel | effort=$implEffort | tier=$implTier | failover=$failoverModel | recon=$reconDisplay"
        Write-Output "  复核策略   : $reviewTier | Antigravity=$agReviewer | Codex=$revModel ($revEffort, tier=$revTier, default_enabled=$revEnabled)"
    }
    exit 0
}

$ws = Resolve-WorkspaceRoot -Workspace $Workspace
$jobsRoot = Join-Path $ws "coop\jobs"

if (-not (Test-Path -LiteralPath $jobsRoot)) {
    Write-Output "当前项目尚无 coop/jobs 记录。"
    exit 0
}

$jobDirs = @(
    if ($JobId) {
        $target = Join-Path $jobsRoot $JobId
        if (-not (Test-Path -LiteralPath $target)) {
            throw "找不到指定 Job: $target"
        }
        Get-Item -LiteralPath $target
    } else {
        Get-ChildItem -LiteralPath $jobsRoot -Directory | Sort-Object Name -Descending
    }
)

if ($jobDirs.Count -eq 0) {
    Write-Output "当前项目尚无协作任务。"
    exit 0
}

foreach ($dir in $jobDirs) {
    $tasks = @(Get-ChildItem -LiteralPath $dir.FullName -Filter "task-*.md" -File -ErrorAction SilentlyContinue)
    $fixes = @(Get-ChildItem -LiteralPath $dir.FullName -Filter "fix-*.md" -File -ErrorAction SilentlyContinue)
    $builds = @(Get-ChildItem -LiteralPath $dir.FullName -Filter "build-*.md" -File -ErrorAction SilentlyContinue)
    $reviews = @(Get-ChildItem -LiteralPath $dir.FullName -Filter "review-*.json" -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)

    $latestVerdict = "pending"
    if ($reviews.Count -gt 0) {
        try {
            $rObj = (Read-Utf8File -Path $reviews[0].FullName) | ConvertFrom-Json
            $fCount = @($rObj.findings).Count
            $latestVerdict = "$($rObj.verdict) ($($reviews[0].Name), findings=$fCount)"
        } catch {
            $latestVerdict = "parse-error ($($reviews[0].Name))"
        }
    }

    $profileLabel = ""
    $jobJsonPath = Join-Path $dir.FullName "job.json"
    if (Test-Path -LiteralPath $jobJsonPath) {
        try {
            $jObj = (Read-Utf8File -Path $jobJsonPath) | ConvertFrom-Json
            $profVal = [string](Get-ObjectPropertyValue -Object $jObj -Name "profile" -Default "")
            if (-not [string]::IsNullOrWhiteSpace($profVal)) {
                $profileLabel = " | Profile: $($profVal.Trim())"
            }
        } catch {
            $profileLabel = " | Profile: (parse-error)"
        }
    }

    Write-Output "Job: $($dir.Name)$profileLabel"
    Write-Output "  Tasks: $($tasks.Count) | Fixes: $($fixes.Count) | Builds: $($builds.Count) | Latest Review: $latestVerdict"
}
