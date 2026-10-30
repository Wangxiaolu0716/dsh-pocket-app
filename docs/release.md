# 发版

## 两条命令

| 目的 | 命令 |
| --- | --- |
| Android 发布包（公告、检查更新、赞赏）+ 传服务器 + GitHub Release | `tools\publish_server.ps1` |
| iOS 未签名 IPA（Codemagic 云端） | `tools\trigger_ios_build.ps1` |
| 只打一个本地包看看 | `flutter build apk --release` |

`publish_server.ps1` 需要 `.env` 里的 `NBCC_SSH_PASSWORD`（服务器 SSH）和本机装好的 PuTTY（plink / pscp）。

## 服务器目录

`https://xuhuohua.xyz/dsh-pocket/` → `/var/www/dsh-pocket/`

```
/var/www/dsh-pocket/
├── update.json          # 版本号、下载地址、sha256、更新说明
├── announcement.json    # 公告
└── dsh-pocket-1.1.0.apk
```

nginx 配置在 `/etc/nginx/conf.d/xuhuohua.conf`：

```nginx
location /dsh-pocket/ {
    alias /var/www/dsh-pocket/;
    autoindex off;
    add_header Cache-Control "no-cache" always;
    types { application/vnd.android.package-archive apk; }
    default_type application/octet-stream;
}
```

## 改公告

改 `server\announcement.json`，然后：

```powershell
.\tools\publish_server.ps1 -AnnouncementOnly
```

格式和课表那个一样：

```json
{
  "updatedAt": "2026-10-30T21:40:00",
  "announcements": [
    { "id": "dshp-20261030-01", "title": "标题", "content": "正文，\\n 换行", "createdAt": "2026-10-30T21:40:00" }
  ]
}
```

App 按 `id` 记住看过的公告，同一条不会反复弹。想重新推一次就换 id。可选字段 `url`，填了会在弹窗里多个「打开链接」。

## 更新清单

正常发版不用手写，脚本会生成。只想改文案或备用链接时，直接改服务器上的 `update.json` 就行（客户端每次启动读一次，响应头是 no-cache）。

```json
{
  "versionCode": 2,              // 大于已装的 versionCode 才会提示
  "versionName": "1.1.0",
  "force": false,                // true 时没有「稍后」，必须更新
  "releaseDate": "2026-10-30",
  "notes": "1. ... \\n2. ...",
  "apkUrl": "https://xuhuohua.xyz/dsh-pocket/dsh-pocket-1.1.0.apk",
  "sizeBytes": 35976451,
  "sha256": "...",               // 下载后校验
  "mirrors": ["https://github.com/.../releases/download/v1.1.0/dsh-pocket-1.1.0.apk"]
}
```

`apkUrl` 可以指向自己的服务器、GitHub Release 直链或 Gitee 附件。下载失败时弹窗会列出 `mirrors` 里的地址。

## 赞赏码

图片放在 `docs/reward_qr.png`，README 用它。构建发布包时 `publish_server.ps1` 会把它拷到 `assets/reward_qr.png`，编完再删掉——`assets/reward_qr.png` 在 `.gitignore` 里。

## iOS

```powershell
.\tools\trigger_ios_build.ps1 -WaitMinutes 60
```

Codemagic appId `6ae4229f80353414f5a033d8`，workflow `ios-unsigned`。push 不会自动触发构建，用脚本或在网页上点 Start new build。

## 这台机器上的坑

- Gradle 守护进程 OOM：`android/gradle.properties` 里堆别超过 2G，`org.gradle.workers.max=2`
- Kotlin 增量缓存报 `Could not close incremental caches`：`kotlin.incremental=false`
- PowerShell 里 `flutter` 会解析成 `C:\flutter\bin\flutter`（bash 脚本），跑不起来也不报错，脚本里一律用 `flutter.bat`
- 换过 asset 之后构建报 `Cannot copy file ... already exists`：删掉 `build/app/intermediates/flutter/release/flutter_assets`，两个发版脚本现在会自己先清
- 传服务器用 pscp，密码写进临时文件用 `-pwfile` 传，不走命令行
- push 到 GitHub 走代理：`git -c http.proxy=http://127.0.0.1:7890 push origin main`
- 代理不通时 GitHub 直连可能反而能用，两种情况都试一下
