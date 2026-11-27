param(
    [string]$TargetProject = "",
    [switch]$Global,
    [switch]$AddCodexShimToPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$SourceRoot = $PSScriptRoot
. (Join-Path $SourceRoot ".agents\skills\coop\scripts\coop-common.ps1")

function Merge-CoopRuleBlock {
    param(
        [Parameter(Mandatory = $true)][string]$SourceRuleFile,
        [Parameter(Mandatory = $true)][string]$DestRuleFile
    )
    $srcText = Read-Utf8File -Path $SourceRuleFile
    if (-not (Test-Path -LiteralPath $DestRuleFile)) {
        Write-Utf8File -Path $DestRuleFile -Content $srcText
        return "created"
    }

    # Extract managed block <!-- ai-coop:begin --> ... <!-- ai-coop:end -->
    $pattern = '(?s)<!-- ai-coop:begin -->.*?<!-- ai-coop:end -->'
    $srcMatch = [regex]::Match($srcText, $pattern)
    $managedBlock = if ($srcMatch.Success) { $srcMatch.Value } else { $srcText.Trim() }

    $destText = Read-Utf8File -Path $DestRuleFile
    if ([regex]::IsMatch($destText, $pattern)) {
        $updated = [regex]::Replace($destText, $pattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $managedBlock })
        Write-Utf8File -Path $DestRuleFile -Content $updated
        return "updated-block"
    } else {
        $merged = $managedBlock + "`r`n`r`n" + $destText.TrimStart()
        Write-Utf8File -Path $DestRuleFile -Content $merged
        return "prepended-block"
    }
}

function Copy-CoopSkill {
    param([Parameter(Mandatory = $true)][string]$DestSkillDir)
    $srcSkillDir = Join-Path $SourceRoot ".agents\skills\coop"
    if (Test-Path -LiteralPath $DestSkillDir) {
        Remove-Item -LiteralPath $DestSkillDir -Recurse -Force
    }
    New-Item -ItemType Directory -Path (Split-Path -Parent $DestSkillDir) -Force | Out-Null
    Copy-Item -LiteralPath $srcSkillDir -Destination $DestSkillDir -Recurse -Force
}

if (-not $TargetProject -and -not $Global -and -not $AddCodexShimToPath) {
    Write-Output @"
用法示例:
  1) 安装全局 coop 技能（推荐先执行一次，所有项目均可随时调用 coop 技能）:
     powershell -ExecutionPolicy Bypass -File .\install-coop.ps1 -Global -AddCodexShimToPath

  2) 为某个具体代码项目启用 AI-Coop v2 多模型协同规则（注入 GEMINI.md + AGENTS.md + 项目级 coop 技能）:
     powershell -ExecutionPolicy Bypass -File .\install-coop.ps1 -TargetProject "D:\AI\my-project"
"@
    exit 0
}

if ($Global) {
    $globalSkillDir = Join-Path $env:USERPROFILE ".gemini\config\skills\coop"
    Copy-CoopSkill -DestSkillDir $globalSkillDir
    Write-Output "[OK] 已安装全局 Antigravity 技能: $globalSkillDir"
}

if ($AddCodexShimToPath) {
    $codexExe = Resolve-CodexExecutable
    $shimDir = Join-Path $env:USERPROFILE ".local\bin"
    New-Item -ItemType Directory -Path $shimDir -Force | Out-Null
    $shimCmd = Join-Path $shimDir "codex.cmd"

    # Dynamic shim: resolves latest OpenAI.Codex InstallLocation at runtime, falling back to current resolved path
    $shimTemplate = @'
@echo off
setlocal
set "CODEX_EXE="
for /f "usebackq delims=" %%I in (`powershell -NoProfile -Command "(Get-AppxPackage -Name 'OpenAI.Codex' -ErrorAction SilentlyContinue | Sort-Object Version -Descending | Select-Object -First 1).InstallLocation"`) do (
    if exist "%%I\app\resources\codex.exe" set "CODEX_EXE=%%I\app\resources\codex.exe"
)
if not defined CODEX_EXE set "CODEX_EXE={{FALLBACK_EXE}}"
"%CODEX_EXE%" %*
'@
    $shimContent = $shimTemplate.Replace("{{FALLBACK_EXE}}", $codexExe)
    Write-Utf8File -Path $shimCmd -Content $shimContent
    Write-Output "[OK] 已生成终端 codex 命令垫片: $shimCmd"

    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $parts = ($userPath -split ";") | Where-Object { $_ }
    if ($parts -notcontains $shimDir) {
        $newUserPath = if ($userPath) { "$userPath;$shimDir" } else { $shimDir }
        [Environment]::SetEnvironmentVariable("Path", $newUserPath, "User")
        Write-Output "[OK] 已将 $shimDir 加入当前用户 PATH（新开终端即可直接运行 codex）"
    } else {
        Write-Output "[OK] $shimDir 已在用户 PATH 中"
    }
}

if ($TargetProject) {
    if (-not (Test-Path -LiteralPath $TargetProject)) {
        New-Item -ItemType Directory -Path $TargetProject -Force | Out-Null
    }
    $projRoot = (Resolve-Path -LiteralPath $TargetProject).Path

    $geminiStatus = Merge-CoopRuleBlock `
        -SourceRuleFile (Join-Path $SourceRoot "GEMINI.md") `
        -DestRuleFile (Join-Path $projRoot "GEMINI.md")

    $agentsStatus = Merge-CoopRuleBlock `
        -SourceRuleFile (Join-Path $SourceRoot "AGENTS.md") `
        -DestRuleFile (Join-Path $projRoot "AGENTS.md")

    $projSkillDir = Join-Path $projRoot ".agents\skills\coop"
    Copy-CoopSkill -DestSkillDir $projSkillDir

    $gitignorePath = Join-Path $projRoot ".gitignore"
    $ignoreLine = "coop/jobs/*/logs/"
    if (Test-Path -LiteralPath $gitignorePath) {
        $gi = Read-Utf8File -Path $gitignorePath
        if ($gi -notmatch [regex]::Escape($ignoreLine)) {
            $suffix = if ($gi.EndsWith("`n")) { "" } else { "`r`n" }
            Write-Utf8File -Path $gitignorePath -Content ($gi + $suffix + "`r`n# AI-Coop runtime logs`r`n$ignoreLine`r`n")
        }
    } else {
        Write-Utf8File -Path $gitignorePath -Content "# AI-Coop runtime logs`r`n$ignoreLine`r`n"
    }

    Write-Output "[OK] 已完成项目安装: $projRoot"
    Write-Output "     GEMINI.md : $geminiStatus"
    Write-Output "     AGENTS.md : $agentsStatus"
    Write-Output "     Skill     : $projSkillDir"
}
