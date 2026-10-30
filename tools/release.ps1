#Requires -Version 5.1
<#
.SYNOPSIS
    源码版打包：改版本号 → 静态检查 + 测试 → 出 APK（可选发 GitHub Release）。

.NOTES
    「发布版」（带服务器公告 / 检查更新 / 赞赏）请用 tools\publish_server.ps1，
    那个才是给用户装的包；这个脚本出的是源码版，功能一样但完全不连服务器。

.DESCRIPTION
    和课表 App 那套 release.ps1 一个思路，但只保留这个项目用得上的部分：
    没有更新服务器、没有飞鸡盘，产物就是 GitHub Release 里的那个 APK。

    iOS 那条线单独走：push 之后 Codemagic 自己按 codemagic.yaml 构建，
    要取包用 tools\fetch_ios_ipa.ps1。

.EXAMPLE
    .\tools\release.ps1 -Version 1.0.1 -Notes "支持多台电脑"

.EXAMPLE
    # 只出包，不发 GitHub
    # 只出包不发 GitHub（默认就是这样）
    .\tools\release.ps1 -Version 1.0.1
#>
param(
    [string]$Version = '',
    [string]$Notes = '',
    [switch]$SkipTest,
    [switch]$GitHub,
    [switch]$Yes
)

$ErrorActionPreference = 'Stop'

# 控制台按 UTF-8 输出，否则中文在 GBK 码页里会变成乱码
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }

function Write-Step($text) { Write-Host "`n>>> $text" -ForegroundColor Cyan }
function Write-Ok($text) { Write-Host "    OK   $text" -ForegroundColor Green }
function Write-Fail($text) { Write-Host "    !!   $text" -ForegroundColor Red }

# 跑外部命令：输出全进日志，成败只看退出码（flutter 会把正常信息写进 stderr）
function Invoke-Logged {
    param([string]$Exe, [string[]]$Arguments, [string]$LogPath)
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & $Exe @Arguments *> $LogPath
        return $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previous
    }
}

function Show-Tail {
    param([string]$Path, [int]$Lines = 25)
    if (Test-Path $Path) {
        Write-Host "    ---- $Path 尾部 $Lines 行 ----" -ForegroundColor Yellow
        Get-Content $Path -Tail $Lines | ForEach-Object { Write-Host "    $_" }
    }
}

$projectRoot = Split-Path -Parent $PSScriptRoot
$pubspec = Join-Path $projectRoot 'pubspec.yaml'

# 注意：PowerShell 里 `flutter` 会解析成 C:\flutter\bin\flutter（bash 脚本），
# 在 Windows 上跑不起来且不报错、LASTEXITCODE 还是空的。必须显式用 flutter.bat。
$flutter = (Get-Command flutter.bat -ErrorAction SilentlyContinue).Source
if (-not $flutter) {
    foreach ($candidate in @('C:\flutter\bin\flutter.bat', "$env:LOCALAPPDATA\flutter\bin\flutter.bat")) {
        if (Test-Path $candidate) { $flutter = $candidate; break }
    }
}
if (-not $flutter) { throw '找不到 flutter.bat，请确认 Flutter SDK 已安装并加入 PATH' }
$apk = Join-Path $projectRoot 'build\app\outputs\flutter-apk\app-release.apk'

# ---------------------------------------------------------------- 构建环境
# 这些原本是用户环境变量里的；脚本自己兜住一份，换台机器也能跑
$sdk = "$env:LOCALAPPDATA\Android\Sdk"
if (-not $env:ANDROID_HOME -and (Test-Path $sdk)) { $env:ANDROID_HOME = $sdk }
if (-not $env:ANDROID_SDK_ROOT -and $env:ANDROID_HOME) { $env:ANDROID_SDK_ROOT = $env:ANDROID_HOME }
if (-not $env:JAVA_HOME) {
    foreach ($candidate in @('D:\androidstudio\jbr', 'C:\Program Files\Android\Android Studio\jbr')) {
        if (Test-Path $candidate) { $env:JAVA_HOME = $candidate; break }
    }
}
if (-not $env:PUB_HOSTED_URL) { $env:PUB_HOSTED_URL = 'https://pub.flutter-io.cn' }
if (-not $env:FLUTTER_STORAGE_BASE_URL) { $env:FLUTTER_STORAGE_BASE_URL = 'https://storage.flutter-io.cn' }

$logDir = Join-Path $projectRoot 'build\release-logs'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'

# ---------------------------------------------------------------- 版本号
Write-Step '版本号'
$line = Select-String -Path $pubspec -Pattern '^version:\s*([0-9][0-9.]*)\+([0-9]+)' | Select-Object -First 1
if (-not $line) { throw 'pubspec.yaml 的 version 行格式不对，应为 1.0.0+1' }
$currentName = $line.Matches[0].Groups[1].Value
$currentCode = [int]$line.Matches[0].Groups[2].Value

if ($Version) {
    if ($Version -notmatch '^[0-9][0-9.]*$') { throw "版本号格式不对：$Version" }
    if ($Version -ne $currentName) {
        $newCode = $currentCode + 1
        $text = [IO.File]::ReadAllText($pubspec)
        $text = $text -replace '(?m)^version:\s*[0-9][0-9.]*\+[0-9]+', "version: $Version+$newCode"
        [IO.File]::WriteAllText($pubspec, $text, (New-Object Text.UTF8Encoding($false)))
        Write-Ok "pubspec.yaml：$currentName+$currentCode → $Version+$newCode"
        $currentName = $Version
        $currentCode = $newCode
    } else {
        Write-Ok "已是 $Version"
    }
} else {
    Write-Ok "沿用当前版本 $currentName+$currentCode"
}

if (-not $Notes) { $Notes = '问题修复与体验优化' }

Write-Step '发版计划'
Write-Host "    版本      : $currentName ($currentCode)"
Write-Host "    说明      : $Notes"
Write-Host "    Java      : $env:JAVA_HOME"
Write-Host "    Android SDK: $env:ANDROID_HOME"
Write-Host "    发 GitHub : $(if ($GitHub) { '是' } else { '跳过（发布版请用 publish_server.ps1）' })"
Write-Host "    日志目录  : $logDir"

if (-not $Yes) {
    $answer = Read-Host '确认开始？(y/N)'
    if ($answer -ne 'y' -and $answer -ne 'Y') { Write-Host '已取消'; return }
}

# ---------------------------------------------------------------- 检查与测试
if (-not $SkipTest) {
    Write-Step 'flutter analyze + test'
    $logAnalyze = Join-Path $logDir "analyze-$stamp.log"
    if ((Invoke-Logged $flutter @('analyze') $logAnalyze) -ne 0) {
        Write-Fail 'flutter analyze 没通过'
        Show-Tail $logAnalyze
        throw '静态检查失败'
    }
    Write-Ok 'analyze 零问题'

    $logTest = Join-Path $logDir "test-$stamp.log"
    if ((Invoke-Logged $flutter @('test') $logTest) -ne 0) {
        Write-Fail 'flutter test 没通过'
        Show-Tail $logTest
        throw '测试失败'
    }
    Write-Ok 'test 全过'
}

# ---------------------------------------------------------------- 出包
Write-Step '构建 APK'
$logBuild = Join-Path $logDir "build-$stamp.log"
if ((Invoke-Logged $flutter @('build', 'apk', '--release') $logBuild) -ne 0) {
    Write-Fail 'flutter build apk 失败'
    Show-Tail $logBuild 40
    throw '构建失败（Kotlin 报 could not close incremental caches 的话，检查 gradle.properties 里 kotlin.incremental=false）'
}
if (-not (Test-Path $apk)) { throw "构建成功但没找到 APK：$apk" }
$size = [math]::Round((Get-Item $apk).Length / 1MB, 1)
Write-Ok "APK $apk（$size MB）"

# ---------------------------------------------------------------- 发 GitHub
if ($GitHub) {
    Write-Step "发 GitHub Release v$currentName"
    $gh = (Get-Command gh -ErrorAction SilentlyContinue)
    if (-not $gh) { throw '找不到 gh 命令（GitHub CLI），先装一个，或者干脆不加 -GitHub' }
    & gh release view "v$currentName" 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        $previous = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        & gh release upload "v$currentName" $apk --clobber
        $ErrorActionPreference = $previous
        Write-Ok "已覆盖上传到 v$currentName"
    } else {
        & gh release create "v$currentName" $apk --title "v$currentName" --notes $Notes
        if ($LASTEXITCODE -ne 0) { throw 'gh release create 失败' }
        Write-Ok "已创建 Release v$currentName"
    }
}

Write-Host ''
Write-Host "发版完成：$currentName" -ForegroundColor Green
Write-Host "  APK: $apk"
if ($GitHub) { Write-Host "  Release: https://github.com/Wangxiaolu0716/dsh-pocket-app/releases/tag/v$currentName" }
