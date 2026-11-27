Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Ensure UTF-8 console output so Chinese characters never garble in PowerShell 5.1 / 7
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = $Utf8NoBom
$OutputEncoding = $Utf8NoBom
$script:CoopScriptsRoot = $PSScriptRoot

function Read-Utf8File {
    param([Parameter(Mandatory = $true)][string]$Path)
    return [System.IO.File]::ReadAllText($Path, $Utf8NoBom)
}

function Write-Utf8File {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Content
    )
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    [System.IO.File]::WriteAllText($Path, $Content, $Utf8NoBom)
}

function Resolve-CodexExecutable {
    param([string]$ExplicitPath = "")

    if ($ExplicitPath -and (Test-Path -LiteralPath $ExplicitPath)) {
        return (Resolve-Path -LiteralPath $ExplicitPath).Path
    }
    if ($env:CODEX_BIN -and (Test-Path -LiteralPath $env:CODEX_BIN)) {
        return (Resolve-Path -LiteralPath $env:CODEX_BIN).Path
    }

    $cmd = Get-Command codex -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source -and (Test-Path -LiteralPath $cmd.Source)) {
        return $cmd.Source
    }

    # Windows Store / Codex Desktop App dynamic resolution (auto-tracks version updates)
    try {
        $appx = Get-AppxPackage -Name "OpenAI.Codex" -ErrorAction SilentlyContinue |
            Sort-Object Version -Descending |
            Select-Object -First 1
        if ($appx -and $appx.InstallLocation) {
            $candidate = Join-Path $appx.InstallLocation "app\resources\codex.exe"
            if (Test-Path -LiteralPath $candidate) {
                return $candidate
            }
        }
    } catch {
        # Ignore Appx lookup errors and continue fallbacks
    }

    $winApps = "C:\Program Files\WindowsApps"
    if (Test-Path -LiteralPath $winApps) {
        $dirs = Get-ChildItem -LiteralPath $winApps -Directory -Filter "OpenAI.Codex_*" -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending
        foreach ($d in $dirs) {
            $candidate = Join-Path $d.FullName "app\resources\codex.exe"
            if (Test-Path -LiteralPath $candidate) {
                return $candidate
            }
        }
    }

    $codexConfig = Join-Path $env:USERPROFILE ".codex\config.toml"
    if (Test-Path -LiteralPath $codexConfig) {
        $match = Select-String -LiteralPath $codexConfig -Pattern "CODEX_CLI_PATH\s*=\s*['`"]([^'`"]+)['`"]" |
            Select-Object -First 1
        if ($match) {
            $cfgPath = $match.Matches[0].Groups[1].Value
            if (Test-Path -LiteralPath $cfgPath) {
                return $cfgPath
            }
        }
    }

    $sandboxBin = Join-Path $env:USERPROFILE ".codex\.sandbox-bin\codex.exe"
    if (Test-Path -LiteralPath $sandboxBin) {
        return $sandboxBin
    }

    throw "未找到 codex.exe。请确认已安装 Codex Desktop 或 npm 包 @openai/codex，或设置环境变量 CODEX_BIN。"
}

function Resolve-WorkspaceRoot {
    param([string]$Workspace = "")
    if ($Workspace) {
        return (Resolve-Path -LiteralPath $Workspace).Path
    }
    return (Get-Location).Path
}

function Format-WinProcessArg {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Arg)
    if ($Arg.Length -eq 0) {
        return '""'
    }
    if ($Arg -notmatch '[\s"]') {
        return $Arg
    }
    # Escape backslashes preceding quotes or trailing backslashes for Windows CommandLineToArgvW
    $escaped = [regex]::Replace($Arg, '(\\*)"', '$1$1\"')
    $escaped = [regex]::Replace($escaped, '(\\+)$', '$1$1')
    return '"' + $escaped + '"'
}

function Get-GitSnapshot {
    param([Parameter(Mandatory = $true)][string]$WorkspaceRoot)

    $gitCmd = Get-Command git -ErrorAction SilentlyContinue
    if (-not $gitCmd) {
        return "（当前环境未安装 git）"
    }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $gitCmd.Source
    $psi.Arguments = "rev-parse --is-inside-work-tree"
    $psi.WorkingDirectory = $WorkspaceRoot
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    $out = $p.StandardOutput.ReadToEnd().Trim()
    $p.WaitForExit()
    if ($p.ExitCode -ne 0 -or $out -ne "true") {
        return "（当前目录尚未初始化 Git 仓库）"
    }

    $statusOut = (& git -C $WorkspaceRoot status --short 2>&1 | Out-String).Trim()
    $diffStatOut = (& git -C $WorkspaceRoot diff --stat 2>&1 | Out-String).Trim()

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("### git status --short")
    if ($statusOut) {
        [void]$sb.AppendLine('```text')
        [void]$sb.AppendLine($statusOut)
        [void]$sb.AppendLine('```')
    } else {
        [void]$sb.AppendLine("（工作区干净，无未提交变更）")
    }

    if ($diffStatOut) {
        [void]$sb.AppendLine()
        [void]$sb.AppendLine("### git diff --stat")
        [void]$sb.AppendLine('```text')
        [void]$sb.AppendLine($diffStatOut)
        [void]$sb.AppendLine('```')
    }
    return $sb.ToString().Trim()
}

function Get-ObjectPropertyValue {
    param(
        [AllowNull()][object]$Object,
        [Parameter(Mandatory = $true)][string]$Name,
        [AllowNull()][object]$Default = $null
    )
    if ($null -eq $Object) {
        return $Default
    }
    $prop = $Object.PSObject.Properties[$Name]
    if ($null -eq $prop -or $null -eq $prop.Value) {
        return $Default
    }
    return $prop.Value
}

function Get-CoopProfilesConfig {
    $scriptsDir = if ($PSScriptRoot) { $PSScriptRoot } else { $script:CoopScriptsRoot }
    $configPath = Join-Path (Split-Path -Parent $scriptsDir) "resources\model-profiles.json"
    if (-not (Test-Path -LiteralPath $configPath)) {
        throw "找不到模型路由配置文件: $configPath"
    }
    $raw = Read-Utf8File -Path $configPath
    $cfg = $raw | ConvertFrom-Json
    if ($null -eq $cfg -or $null -eq $cfg.PSObject.Properties["profiles"] -or $cfg.profiles -isnot [PSCustomObject]) {
        throw "模型路由配置文件格式无效（缺少有效的 profiles 对象节点）: $configPath"
    }
    return $cfg
}

function Resolve-TaskProfile {
    param(
        [string]$ExplicitProfile = "",
        [string]$BriefPath = "",
        [string]$JobDir = ""
    )

    $cfg = Get-CoopProfilesConfig
    $candidate = ""

    if (-not [string]::IsNullOrWhiteSpace($ExplicitProfile)) {
        $candidate = $ExplicitProfile.Trim()
    }

    if (-not $candidate -and -not [string]::IsNullOrWhiteSpace($BriefPath) -and (Test-Path -LiteralPath $BriefPath -PathType Leaf)) {
        $briefText = Read-Utf8File -Path $BriefPath
        $h2Match = [regex]::Match($briefText, '(?m)^##\s+')
        $headerText = if ($h2Match.Success) { $briefText.Substring(0, $h2Match.Index) } else { $briefText }
        $pattern = '(?im)^\s*(?:[-*]\s+)?(?:\*\*)?(?:(?:默认)?路由档位\s*\(\s*Profile\s*\)|Profile)\s*(?:[:：]\s*\*\*|\*\*\s*[:：]|[:：])\s*(?:`([a-z0-9\-_]+)`|([a-z0-9\-_]+))(?=\s|$|[（(,，;；])'
        $match = [regex]::Match($headerText, $pattern)
        if ($match.Success) {
            $rawVal = if ($match.Groups[1].Success) { $match.Groups[1].Value } else { $match.Groups[2].Value }
            $candidate = $rawVal.Trim()
        }
    }

    if (-not $candidate -and -not [string]::IsNullOrWhiteSpace($JobDir)) {
        $jobJsonPath = Join-Path $JobDir "job.json"
        if (Test-Path -LiteralPath $jobJsonPath) {
            $jobObj = (Read-Utf8File -Path $jobJsonPath) | ConvertFrom-Json
            if ($null -ne $jobObj) {
                $profProp = $jobObj.PSObject.Properties["profile"]
                if ($null -ne $profProp -and -not [string]::IsNullOrWhiteSpace([string]$profProp.Value)) {
                    $candidate = ([string]$profProp.Value).Trim()
                }
            }
        }
    }

    if (-not $candidate) {
        $defaultProfile = [string](Get-ObjectPropertyValue -Object $cfg -Name "default_profile" -Default "standard")
        $candidate = if (-not [string]::IsNullOrWhiteSpace($defaultProfile)) { $defaultProfile.Trim() } else { "standard" }
    }

    $validNames = @($cfg.profiles.PSObject.Properties | ForEach-Object { $_.Name })
    $matchedProp = $cfg.profiles.PSObject.Properties[$candidate]
    if ($null -eq $matchedProp) {
        $validList = $validNames -join ", "
        throw "无效的路由档位 (Profile): '$candidate'。合法档位包括: $validList"
    }

    return $matchedProp.Name
}

function Resolve-CodexStageConfig {
    param(
        [Parameter(Mandatory = $true)][string]$ProfileName,
        [Parameter(Mandatory = $true)][ValidateSet("implement", "review")][string]$Stage,
        [string]$Model = "",
        [string]$ReasoningEffort = "",
        [string]$ServiceTier = ""
    )

    $cfg = Get-CoopProfilesConfig
    $validNames = @($cfg.profiles.PSObject.Properties | ForEach-Object { $_.Name })
    $profProp = $cfg.profiles.PSObject.Properties[$ProfileName]
    if ($null -eq $profProp) {
        $validList = $validNames -join ", "
        throw "无效的路由档位 (Profile): '$ProfileName'。合法档位包括: $validList"
    }

    $resolvedName = $profProp.Name
    $profObj = $profProp.Value
    $stageKey = if ($Stage -eq "implement") { "codex_implement" } else { "codex_review" }
    $stageObj = Get-ObjectPropertyValue -Object $profObj -Name $stageKey
    if ($null -eq $stageObj) {
        throw "路由档位 '$resolvedName' 缺少 '$stageKey' 配置节点。"
    }

    $agObj = Get-ObjectPropertyValue -Object $profObj -Name "antigravity"
    $reviewCfgObj = Get-ObjectPropertyValue -Object $profObj -Name "codex_review"

    $effModel = if (-not [string]::IsNullOrWhiteSpace($Model)) {
        $Model.Trim()
    } else {
        [string](Get-ObjectPropertyValue -Object $stageObj -Name "model" -Default "")
    }
    $effEffort = if (-not [string]::IsNullOrWhiteSpace($ReasoningEffort)) {
        $ReasoningEffort.Trim()
    } else {
        [string](Get-ObjectPropertyValue -Object $stageObj -Name "reasoning_effort" -Default "")
    }
    $effTier = if (-not [string]::IsNullOrWhiteSpace($ServiceTier)) {
        $ServiceTier.Trim()
    } else {
        [string](Get-ObjectPropertyValue -Object $stageObj -Name "service_tier" -Default "default")
    }

    return [PSCustomObject]@{
        Profile                     = $resolvedName
        Stage                       = $Stage
        Model                       = $effModel
        ReasoningEffort             = $effEffort
        ServiceTier                 = $effTier
        FailoverModel               = [string](Get-ObjectPropertyValue -Object $agObj -Name "failover_implement_model" -Default "pro")
        ReviewTier                  = [string](Get-ObjectPropertyValue -Object $agObj -Name "review_tier" -Default "L2")
        AntigravityReviewer         = [string](Get-ObjectPropertyValue -Object $agObj -Name "review_subagent_model" -Default "pro")
        CodexReviewEnabledByDefault = [bool](Get-ObjectPropertyValue -Object $reviewCfgObj -Name "enabled_by_default" -Default $false)
    }
}

function Test-CodexQuotaExhausted {
    param(
        [Parameter(Mandatory = $true)][int]$ExitCode,
        [AllowEmptyString()][string]$CombinedOutput = ""
    )
    if ($ExitCode -eq 0 -or [string]::IsNullOrEmpty($CombinedOutput)) {
        return $false
    }
    $errLinePattern = '(?i)^\s*(?:\d{4}-\d{2}-\d{2}T\S+\s+)?(?:ERROR|FATAL)\b[:\s].*(?:hit your usage limit|usage limit|rate limit exceeded|insufficient_quota)'
    $jsonLinePattern = '(?i)^\s*\{.*"error".*(?:hit your usage limit|usage[_ ]limit|insufficient_quota|rate[_ ]limit)'
    foreach ($line in ($CombinedOutput -split '\r?\n')) {
        if ([regex]::IsMatch($line, $errLinePattern) -or [regex]::IsMatch($line, $jsonLinePattern)) {
            return $true
        }
    }
    return $false
}

function Write-CoopStageMeta {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$JobId,
        [Parameter(Mandatory = $true)][ValidateSet("implement", "review")][string]$Stage,
        [Parameter(Mandatory = $true)][string]$Round,
        [Parameter(Mandatory = $true)][string]$Brief,
        [Parameter(Mandatory = $true)][object]$StageConfig,
        [Parameter(Mandatory = $true)][string]$Sandbox,
        [Parameter(Mandatory = $true)][object]$ExecResult,
        [int]$ImagesCount = -1
    )
    $meta = [ordered]@{
        job_id           = $JobId
        stage            = $Stage
        round            = $Round
        brief            = $Brief
        profile          = $StageConfig.Profile
        model            = $StageConfig.Model
        reasoning_effort = $StageConfig.ReasoningEffort
        service_tier     = $StageConfig.ServiceTier
        sandbox          = $Sandbox
    }
    if ($ImagesCount -ge 0) {
        $meta["images_count"] = $ImagesCount
    }
    $meta["duration_seconds"] = $ExecResult.DurationSeconds
    $meta["exit_code"] = $ExecResult.ExitCode
    $meta["quota_exhausted"] = [bool]$ExecResult.QuotaExhausted
    $meta["recorded_at"] = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")

    Write-Utf8File -Path $Path -Content ($meta | ConvertTo-Json -Depth 4)
}

function Invoke-CodexExec {
    param(
        [Parameter(Mandatory = $true)][string]$WorkspaceRoot,
        [Parameter(Mandatory = $true)][string]$Prompt,
        [Parameter(Mandatory = $true)][string]$OutputFile,
        [Parameter(Mandatory = $true)][string]$LogPrefix,
        [ValidateSet("read-only", "workspace-write", "danger-full-access")]
        [string]$Sandbox = "workspace-write",
        [string]$OutputSchema = "",
        [string]$Model = "",
        [string]$ReasoningEffort = "",
        [string]$ServiceTier = "",
        [string[]]$Images = @(),
        [switch]$EnableMcp,
        [switch]$PersistSession,
        [string]$CodexPath = "",
        [int]$TimeoutSeconds = 1200
    )

    $resolvedImages = New-Object System.Collections.Generic.List[string]
    if ($null -ne $Images) {
        foreach ($img in @($Images)) {
            if ([string]::IsNullOrWhiteSpace($img)) {
                continue
            }
            $trimmedImg = $img.Trim()
            if (-not (Test-Path -LiteralPath $trimmedImg -PathType Leaf)) {
                throw "找不到参考图片文件: $trimmedImg"
            }
            $resolvedImages.Add((Resolve-Path -LiteralPath $trimmedImg).Path)
        }
    }

    $codexExe = Resolve-CodexExecutable -ExplicitPath $CodexPath
    $argList = New-Object System.Collections.Generic.List[string]
    $argList.Add("exec")
    $argList.Add("-C")
    $argList.Add($WorkspaceRoot)
    $argList.Add("-s")
    $argList.Add($Sandbox)
    $argList.Add("-c")
    $argList.Add('approval_policy="never"')

    if (-not $EnableMcp) {
        # Disable Desktop-GUI-bound MCP servers by default so CLI runs never block on named pipes
        $argList.Add("-c")
        $argList.Add("mcp_servers={}")
    }
    if ($Model) {
        $argList.Add("-m")
        $argList.Add($Model)
    }
    if ($ReasoningEffort) {
        $argList.Add("-c")
        $argList.Add("model_reasoning_effort=`"$ReasoningEffort`"")
    }
    if (-not [string]::IsNullOrWhiteSpace($ServiceTier)) {
        $trimmedTier = $ServiceTier.Trim()
        $argList.Add("-c")
        $argList.Add("service_tier=`"$trimmedTier`"")
    }

    $argList.Add("--skip-git-repo-check")
    $argList.Add("--trust")
    if (-not $PersistSession) {
        $argList.Add("--ephemeral")
    }
    $argList.Add("--color")
    $argList.Add("never")

    if ($OutputSchema) {
        $argList.Add("--output-schema")
        $argList.Add($OutputSchema)
    }

    foreach ($imgPath in $resolvedImages) {
        $argList.Add("-i")
        $argList.Add($imgPath)
    }

    $outParent = Split-Path -Parent $OutputFile
    if ($outParent -and -not (Test-Path -LiteralPath $outParent)) {
        New-Item -ItemType Directory -Path $outParent -Force | Out-Null
    }
    $argList.Add("-o")
    $argList.Add($OutputFile)
    $argList.Add("-")

    $formattedArgs = ($argList | ForEach-Object { Format-WinProcessArg $_ }) -join " "

    $logDir = Split-Path -Parent $LogPrefix
    if ($logDir -and -not (Test-Path -LiteralPath $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    $promptLog = "$LogPrefix.prompt.md"
    $stdoutLog = "$LogPrefix.stdout.log"
    $stderrLog = "$LogPrefix.stderr.log"
    Write-Utf8File -Path $promptLog -Content $Prompt

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $codexExe
    $psi.Arguments = $formattedArgs
    $psi.WorkingDirectory = $WorkspaceRoot
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = $Utf8NoBom
    $psi.StandardErrorEncoding = $Utf8NoBom
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi

    if (-not $proc.Start()) {
        throw "无法启动 Codex 进程: $codexExe"
    }

    # Read stdout & stderr asynchronously BEFORE waiting, avoiding pipe buffer deadlocks
    $stdoutTask = $proc.StandardOutput.ReadToEndAsync()
    $stderrTask = $proc.StandardError.ReadToEndAsync()

    $promptBytes = $Utf8NoBom.GetBytes($Prompt)
    $proc.StandardInput.BaseStream.Write($promptBytes, 0, $promptBytes.Length)
    $proc.StandardInput.BaseStream.Flush()
    $proc.StandardInput.Close()

    $exited = $proc.WaitForExit($TimeoutSeconds * 1000)
    if (-not $exited) {
        try { $proc.Kill() } catch {}
        throw "Codex 执行超时（超过 ${TimeoutSeconds} 秒），进程已终止。请检查日志: $stderrLog"
    }
    # Ensure async stream readers flush after process exit
    $proc.WaitForExit()
    $sw.Stop()

    $stdoutText = $stdoutTask.GetAwaiter().GetResult()
    $stderrText = $stderrTask.GetAwaiter().GetResult()

    Write-Utf8File -Path $stdoutLog -Content $stdoutText
    Write-Utf8File -Path $stderrLog -Content $stderrText

    $combinedOutput = $stderrText + "`n" + $stdoutText
    $quotaExhausted = Test-CodexQuotaExhausted -ExitCode $proc.ExitCode -CombinedOutput $combinedOutput

    return [PSCustomObject]@{
        ExitCode        = $proc.ExitCode
        DurationSeconds = [Math]::Round($sw.Elapsed.TotalSeconds, 1)
        CodexExecutable = $codexExe
        OutputFile      = $OutputFile
        PromptLog       = $promptLog
        StdoutLog       = $stdoutLog
        StderrLog       = $stderrLog
        QuotaExhausted  = $quotaExhausted
        StderrPreview   = if ($stderrText.Length -gt 1200) { $stderrText.Substring($stderrText.Length - 1200) } else { $stderrText }
    }
}
