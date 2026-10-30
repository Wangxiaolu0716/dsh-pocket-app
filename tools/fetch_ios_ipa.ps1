#Requires -Version 5.1
<#
.SYNOPSIS
    等 Codemagic 的 iOS 构建跑完，把未签名 IPA 下载到 build/ios-ipa/。

.DESCRIPTION
    默认等「本地 HEAD 那次提交」对应的构建（刚 push 完要等的必然是它）；
    也可以显式传 -BuildId。

    产物地址要带 x-auth-token 头才能下，不带会 401。

.EXAMPLE
    .\tools\fetch_ios_ipa.ps1 -AppId 1234abcd -WaitMinutes 60
#>
param(
    [Parameter(Mandatory)][string]$AppId,
    [string]$BuildId = '',
    [string]$OutDir = '',
    [string]$Token = '',
    [int]$WaitMinutes = 30,
    [int]$PollSeconds = 20
)

$ErrorActionPreference = 'Stop'
function Write-Ok($text) { Write-Host "    $text" -ForegroundColor Green }

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
if (-not $Token) { throw '没有 Codemagic token：在 .env 里写 CODEMAGIC_TOKEN=...' }
if (-not $OutDir) { $OutDir = Join-Path $projectRoot 'build\ios-ipa' }

$head = ''
if (-not $BuildId) {
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $head = (& git -C $projectRoot rev-parse HEAD).Trim() } finally { $ErrorActionPreference = $previous }
    if (-not $head) { throw '读不到 git HEAD，请显式传 -BuildId' }
}

function Get-TargetBuild {
    param([switch]$FinishedOnly)
    $builds = @(Invoke-RestMethod -Uri "https://api.codemagic.io/builds?appId=$AppId" `
            -Headers @{ 'x-auth-token' = $Token } -TimeoutSec 60).builds
    if ($BuildId) { $builds = $builds | Where-Object { $_._id -eq $BuildId } }
    else { $builds = $builds | Where-Object { $_.commit.hash -eq $head } }
    if ($FinishedOnly) { $builds = $builds | Where-Object { $_.status -eq 'finished' } }
    return $builds | Sort-Object index -Descending | Select-Object -First 1
}

Write-Host "`n>>> 等 iOS 构建（$(if ($BuildId) { "buildId $BuildId" } else { "commit " + $head.Substring(0,7) })）" -ForegroundColor Cyan
$failedStates = @('failed', 'canceled', 'cancelled', 'timeout', 'skipped')
$deadline = (Get-Date).AddMinutes($WaitMinutes)
$lastShown = ''
while ($true) {
    $match = Get-TargetBuild
    if ($match) {
        if ($match.status -eq 'finished') { Write-Ok "构建 #$($match.index) 完成"; break }
        if ($failedStates -contains $match.status) {
            throw "构建 #$($match.index) 没成功（$($match.status)）：https://codemagic.io/builds?app_id=$AppId"
        }
        $now = "构建 #$($match.index) 进行中（$($match.status)）"
    } else {
        $now = '还没看到这次构建，等它出现'
    }
    if ($now -ne $lastShown) { Write-Host "    $now"; $lastShown = $now }
    if ((Get-Date) -gt $deadline) {
        throw "等了 $WaitMinutes 分钟还没跑完，去 https://codemagic.io/builds?app_id=$AppId 看一眼"
    }
    Start-Sleep -Seconds $PollSeconds
}

$build = Get-TargetBuild -FinishedOnly
$art = $build.artefacts | Where-Object { $_.type -eq 'ipa' } | Select-Object -First 1
if (-not $art) { throw "构建 #$($build.index) 完成了但没有 ipa 产物（看日志有没有编译错误）" }

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$dest = Join-Path $OutDir $art.name
if ((Test-Path $dest) -and (Get-Item $dest).Length -eq $art.size) {
    Write-Ok '本地已有同大小文件，跳过下载'
} else {
    Write-Host '    下载中…'
    Invoke-WebRequest -Uri $art.url -Headers @{ 'x-auth-token' = $Token } -OutFile $dest `
        -TimeoutSec 600 -UseBasicParsing -MaximumRedirection 5
    Write-Ok "已下载 $dest（$([math]::Round((Get-Item $dest).Length/1MB,1)) MB）"
}
Write-Host ''
Write-Host '未签名 IPA 装不上手机，用 Sideloadly / AltStore 重签后再装。' -ForegroundColor Yellow
