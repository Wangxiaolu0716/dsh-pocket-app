#Requires -Version 5.1
<#
.SYNOPSIS
    触发一次 Codemagic 的 iOS 构建（未签名 IPA），可选接着等它跑完并下载。

.DESCRIPTION
    两条路：
      - pubspec.yaml 有未提交的改动 → 提交并 push，由 push 自动触发（Codemagic 编的是远程代码）
      - 远程已经是最新代码 → 直接调 Codemagic API 起一次构建

    API token 从环境变量 CODEMAGIC_TOKEN 或项目根目录 .env 里取。

.EXAMPLE
    .\tools\trigger_ios_build.ps1 -AppId 1234abcd -WaitMinutes 60
#>
param(
    # 默认就是这个仓库在 Codemagic 上的 app id；换仓库/换账号时传新的
    [string]$AppId = '6ae4229f80353414f5a033d8',
    [string]$WorkflowId = 'ios-unsigned',
    [string]$Branch = 'main',
    [string]$Token = '',
    [int]$WaitMinutes = 0,
    [switch]$NoFetch
)

$ErrorActionPreference = 'Stop'
function Write-Step($text) { Write-Host "`n>>> $text" -ForegroundColor Cyan }
function Write-Ok($text) { Write-Host "    $text" -ForegroundColor Green }
function Write-Warn($text) { Write-Host "    $text" -ForegroundColor Yellow }

$projectRoot = Split-Path -Parent $PSScriptRoot
$envFile = Join-Path $projectRoot '.env'
if (Test-Path $envFile) {
    foreach ($envLine in [IO.File]::ReadAllLines($envFile)) {
        if ($envLine -match '^\s*#' -or $envLine -notmatch '=') { continue }
        $envKey, $envValue = $envLine -split '=', 2
        [Environment]::SetEnvironmentVariable($envKey.Trim(), $envValue.Trim())
    }
}
if (-not $Token) { $Token = $env:CODEMAGIC_TOKEN }

function Invoke-Git {
    param([string[]]$Arguments)
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $out = & git -C $projectRoot @Arguments 2>&1
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previous
    }
    if ($code -ne 0) { throw "git $($Arguments -join ' ') 失败：`n$($out -join "`n")" }
    return $out
}

$dirty = @(Invoke-Git @('status', '--porcelain', '--untracked-files=no')).Count -gt 0
if ($dirty) {
    Write-Step '有未提交改动：提交并 push，由 push 触发构建'
    Invoke-Git @('add', '-A') | Out-Null
    Invoke-Git @('commit', '-m', '触发 iOS 构建') | Out-Null
    Invoke-Git @('push', 'origin', $Branch) | ForEach-Object { Write-Host "    $_" }
    Write-Ok '已 push'
} else {
    if (-not $Token) { throw '没有 Codemagic token：在 .env 里写 CODEMAGIC_TOKEN=...' }
    Write-Step '直接调 API 起构建'
    $body = @{ appId = $AppId; workflowId = $WorkflowId; branch = $Branch } | ConvertTo-Json
    $resp = Invoke-RestMethod -Uri 'https://api.codemagic.io/builds' -Method Post `
        -Headers @{ 'x-auth-token' = $Token } `
        -ContentType 'application/json; charset=utf-8' `
        -Body ([Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 60
    if (-not $resp.buildId) { throw "触发失败：$($resp | ConvertTo-Json -Compress)" }
    Write-Ok "buildId=$($resp.buildId)"
}

if ($NoFetch) {
    Write-Host "进度：https://codemagic.io/builds?app_id=$AppId" -ForegroundColor Green
    return
}

& (Join-Path $PSScriptRoot 'fetch_ios_ipa.ps1') -AppId $AppId -WaitMinutes ([Math]::Max($WaitMinutes, 30)) -Token $Token
