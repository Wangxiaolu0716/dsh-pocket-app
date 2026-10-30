#Requires -Version 5.1
<#
.SYNOPSIS
    发布版一键发版：打带公告/更新/赞赏的官方包 → 传自己的服务器 → 发 GitHub Release。

.DESCRIPTION
    和「源码版」的区别只有一件事：`--dart-define=OFFICIAL=true`。
    带上它才有更新检查、服务器公告、赞赏入口；不带就是源码版（什么都没多）。

    服务器上只放两个 JSON 和一个 APK，全部是静态文件，没有任何源码：
      /var/www/dsh-pocket/update.json        更新清单（改了立刻生效，不用发版）
      /var/www/dsh-pocket/announcement.json  公告（同上）
      /var/www/dsh-pocket/dsh-pocket-X.apk   安装包

    收款码的处理：仓库里只有 docs/reward_qr.png（README 用），
    assets/reward_qr.png 是 gitignore 的——打官方包时才在这里临时拷进来，
    构建完整删掉。所以源码版 APK 里根本没有收款码。

.EXAMPLE
    .\tools\publish_server.ps1 -Notes "1. 顶栏/底栏改为全屏\n2. 自动跟进公网地址"

.EXAMPLE
    # 只传公告，不重新打包
    .\tools\publish_server.ps1 -AnnouncementOnly

.EXAMPLE
    # 强制更新（弹窗没有「稍后」）
    .\tools\publish_server.ps1 -Force
#>
param(
    [string]$Notes = '',
    [switch]$Force,

    # 只把 server\announcement.json 传上去，不构建、不碰 APK
    [switch]$AnnouncementOnly,

    # 服务器
    [string]$SshTarget = 'root@121.43.151.118',
    [string]$HostKey = 'SHA256:gHgt11uYwkgeDxvSG9rgYhFzN2RTrEfyM4yQdTm4iUw',
    [string]$RemoteDir = '/var/www/dsh-pocket',
    [string]$PublicBase = 'https://xuhuohua.xyz/dsh-pocket',

    # 只打 arm64：体积小一半多，新手机全是 arm64
    [string]$TargetPlatform = 'android-arm64',

    # 顺手发 GitHub Release（同一个包，也当备用下载直链）
    [switch]$SkipGitHub,

    [switch]$Yes
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }

function Write-Step($text) { Write-Host "`n>>> $text" -ForegroundColor Cyan }
function Write-Ok($text) { Write-Host "    OK   $text" -ForegroundColor Green }
function Write-Fail($text) { Write-Host "    !!   $text" -ForegroundColor Red }

function Invoke-Native {
    param([string]$Exe, [string[]]$Arguments, [string]$What)
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & $Exe @Arguments 2>&1 | ForEach-Object { Write-Host "    $_" }
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previous
    }
    if ($code -ne 0) { throw "$What 失败（退出码 $code）" }
}

function Invoke-Remote {
    param([string]$Command)
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { return (& $Plink -batch -ssh -hostkey $HostKey -pwfile $pwFile $SshTarget $Command 2>&1) }
    finally { $ErrorActionPreference = $previous }
}

$projectRoot = Split-Path -Parent $PSScriptRoot
$pubspec = Join-Path $projectRoot 'pubspec.yaml'
$Plink = 'C:\Program Files\PuTTY\plink.exe'
$Pscp = 'C:\Program Files\PuTTY\pscp.exe'
foreach ($tool in @($Plink, $Pscp)) {
    if (-not (Test-Path $tool)) { throw "找不到 PuTTY 工具：$tool" }
}

# PowerShell 里 `flutter` 会解析成 C:\flutter\bin\flutter（bash 脚本），跑不起来还不报错
$flutter = (Get-Command flutter.bat -ErrorAction SilentlyContinue).Source
if (-not $flutter) { $flutter = 'C:\flutter\bin\flutter.bat' }
if (-not (Test-Path $flutter)) { throw '找不到 flutter.bat' }

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

# ---------------------------------------------------------------- 密码
$envFile = Join-Path $projectRoot '.env'
if (Test-Path $envFile) {
    foreach ($envLine in [IO.File]::ReadAllLines($envFile)) {
        if ($envLine -match '^\s*#' -or $envLine -notmatch '=') { continue }
        $envKey, $envValue = $envLine -split '=', 2
        [Environment]::SetEnvironmentVariable($envKey.Trim(), $envValue.Trim())
    }
}
$Password = $env:NBCC_SSH_PASSWORD
if (-not $Password) { throw '没有服务器密码：在 .env 里写 NBCC_SSH_PASSWORD=...' }
$pwFile = [IO.Path]::GetTempFileName()
[IO.File]::WriteAllText($pwFile, $Password, [Text.Encoding]::ASCII)

$rewardSrc = Join-Path $projectRoot 'docs\reward_qr.png'
$rewardStaged = Join-Path $projectRoot 'assets\reward_qr.png'

try {
    # ------------------------------------------------------------ 只传公告
    if ($AnnouncementOnly) {
        $announcement = Join-Path $projectRoot 'server\announcement.json'
        if (-not (Test-Path $announcement)) { throw "找不到 $announcement" }
        Write-Step '上传公告'
        Invoke-Native -What '上传 announcement.json' -Exe $Pscp -Arguments @(
            '-batch', '-hostkey', $HostKey, '-pwfile', $pwFile,
            $announcement, "${SshTarget}:${RemoteDir}/announcement.json"
        )
        Invoke-Remote "chmod 644 $RemoteDir/announcement.json" | Out-Null
        Write-Ok "$PublicBase/announcement.json"
        return
    }

    # ------------------------------------------------------------ 版本号
    Write-Step '读取版本号'
    $line = Select-String -Path $pubspec -Pattern '^version:\s*([0-9][0-9.]*)\+([0-9]+)' | Select-Object -First 1
    if (-not $line) { throw 'pubspec.yaml 的 version 行格式不对' }
    $versionName = $line.Matches[0].Groups[1].Value
    $versionCode = [int]$line.Matches[0].Groups[2].Value
    Write-Ok "versionName = $versionName   versionCode = $versionCode"

    if (-not $Notes) { $Notes = '问题修复与体验优化' }
    $Notes = $Notes -replace '\\n', "`n"

    Write-Step '发布计划'
    Write-Host "    版本    : $versionName ($versionCode)"
    Write-Host "    架构    : $TargetPlatform"
    Write-Host "    强制更新: $(if ($Force) { '是' } else { '否' })"
    Write-Host "    说明    : $(($Notes -split "`n") -join ' / ')"
    Write-Host "    目标    : $SshTarget`:$RemoteDir"
    Write-Host "    发布版  : 带公告 / 更新检查 / 赞赏入口（--dart-define=OFFICIAL=true）"

    if (-not $Yes) {
        $answer = Read-Host '确认发布？(y/N)'
        if ($answer -ne 'y' -and $answer -ne 'Y') { Write-Host '已取消'; return }
    }

    # ------------------------------------------------------------ 收款码
    if (Test-Path $rewardSrc) {
        # 先删再拷：上一次构建会把资产文件标成只读，直接覆盖会失败
        if (Test-Path $rewardStaged) { Remove-Item $rewardStaged -Force -ErrorAction SilentlyContinue }
        Copy-Item $rewardSrc $rewardStaged -Force
        Write-Ok '收款码已放进 assets/（构建完会删掉）'
    } else {
        Write-Host '    没有 docs/reward_qr.png，这次包里不带收款码' -ForegroundColor Yellow
    }

    # ------------------------------------------------------------ 构建
    Write-Step "构建发布版 APK（$TargetPlatform）"
    Push-Location $projectRoot
    try {
        Invoke-Native -What 'flutter build apk' -Exe $flutter -Arguments @(
            'build', 'apk', '--release',
            '--target-platform', $TargetPlatform,
            '--dart-define=OFFICIAL=true'
        )
    } finally {
        Pop-Location
        # 别把收款码留在工作区：源码版和下次构建都不该有它
        if (Test-Path $rewardStaged) { Remove-Item $rewardStaged -Force }
    }

    $apk = Join-Path $projectRoot 'build\app\outputs\flutter-apk\app-release.apk'
    if (-not (Test-Path $apk)) { throw "构建产物不存在：$apk" }
    $apkName = "dsh-pocket-$versionName.apk"
    $staged = Join-Path $projectRoot "build\$apkName"
    Copy-Item $apk $staged -Force

    $bytes = (Get-Item $staged).Length
    $sha = (Get-FileHash $staged -Algorithm SHA256).Hash.ToLower()
    Write-Ok ("体积 {0:N1} MB  SHA256 {1}" -f ($bytes / 1MB), $sha.Substring(0, 16))

    # ------------------------------------------------------------ 清单
    Write-Step '生成 update.json'
    $manifest = [ordered]@{
        versionCode = $versionCode
        versionName = $versionName
        force       = [bool]$Force
        releaseDate = (Get-Date -Format 'yyyy-MM-dd')
        notes       = $Notes
        apkUrl      = "$PublicBase/$apkName"
        sizeBytes   = $bytes
        sha256      = $sha
        # 备用直链：服务器带宽小的时候用户能换条路
        mirrors     = @("https://github.com/Wangxiaolu0716/dsh-pocket-app/releases/download/v$versionName/$apkName")
    } | ConvertTo-Json -Depth 4
    $manifestPath = Join-Path $projectRoot 'build\update.json'
    # 必须是无 BOM 的 UTF-8：App 侧严格按 UTF-8 解析
    [IO.File]::WriteAllText($manifestPath, $manifest, (New-Object Text.UTF8Encoding($false)))
    Write-Ok $manifestPath

    # ------------------------------------------------------------ 上传
    Write-Step '上传到服务器'
    Invoke-Native -What '上传 APK' -Exe $Pscp -Arguments @(
        '-batch', '-hostkey', $HostKey, '-pwfile', $pwFile,
        $staged, "${SshTarget}:${RemoteDir}/$apkName"
    )
    Invoke-Native -What '上传清单' -Exe $Pscp -Arguments @(
        '-batch', '-hostkey', $HostKey, '-pwfile', $pwFile,
        $manifestPath, "${SshTarget}:${RemoteDir}/update.json"
    )
    Invoke-Remote "chmod 644 $RemoteDir/*" | Out-Null
    Write-Ok '上传完成'

    # ------------------------------------------------------------ 校验
    Write-Step '校验线上状态'
    $remoteSha = ((Invoke-Remote "sha256sum $RemoteDir/$apkName") -join ' ') -split '\s+' | Select-Object -First 1
    if ($remoteSha -ne $sha) { throw "服务器文件哈希不一致：$remoteSha" }

    $online = Invoke-WebRequest "$PublicBase/update.json" -TimeoutSec 20 -UseBasicParsing
    $text = [Text.Encoding]::UTF8.GetString(
        $(if ($online.Content -is [byte[]]) { $online.Content } else { [Text.Encoding]::UTF8.GetBytes([string]$online.Content) })
    )
    # PowerShell 的双引号串里没有 \" 转义：拼出来再匹配
    $versionPattern = '"versionCode"\s*:\s*' + $versionCode
    if ($text -notmatch $versionPattern) { throw '线上 update.json 的 versionCode 不对' }
    Write-Ok "清单已生效：$PublicBase/update.json"

    # ------------------------------------------------------------ GitHub
    if (-not $SkipGitHub) {
        Write-Step "发 GitHub Release v$versionName"
        $gh = Get-Command gh -ErrorAction SilentlyContinue
        if (-not $gh) {
            Write-Host '    找不到 gh，跳过（文件已在服务器上）' -ForegroundColor Yellow
        } else {
            $previous = $ErrorActionPreference
            $ErrorActionPreference = 'Continue'
            & gh release view "v$versionName" *> $null
            $exists = ($LASTEXITCODE -eq 0)
            if ($exists) {
                & gh release upload "v$versionName" $staged --clobber
            } else {
                & gh release create "v$versionName" $staged --title "v$versionName" --notes $Notes
            }
            $ErrorActionPreference = $previous
            Write-Ok "https://github.com/Wangxiaolu0716/dsh-pocket-app/releases/tag/v$versionName"
        }
    }

    Write-Host ''
    Write-Host "发布完成：$versionName ($versionCode)" -ForegroundColor Green
    Write-Host "  安装包  $PublicBase/$apkName  ($([math]::Round($bytes / 1MB, 1)) MB)"
    Write-Host "  清单    $PublicBase/update.json"
    Write-Host '  公告：改 server\announcement.json 后跑 -AnnouncementOnly 即可，不用重打包'
} finally {
    if (Test-Path $rewardStaged) { Remove-Item $rewardStaged -Force -ErrorAction SilentlyContinue }
    Remove-Item $pwFile -Force -ErrorAction SilentlyContinue
}
