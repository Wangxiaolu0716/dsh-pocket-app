# 发版手册

三件事分清楚：

| 想干什么 | 用哪个 | 会不会连服务器 |
| --- | --- | --- |
| 给用户装「发布版」（公告 + 检查更新 + 赞赏） | `tools\publish_server.ps1` | 会（上传 APK 和两个 JSON） |
| 从源码自己出一个包 / 验证代码 | `tools\release.ps1` 或 `flutter build apk --release` | 不会 |
| 出 iOS 的未签名 IPA | `tools\trigger_ios_build.ps1`（Codemagic 云端） | 不会 |

## 服务器上到底放了什么

`https://xuhuohua.xyz/dsh-pocket/` → `/var/www/dsh-pocket/`（nginx 静态目录，**没有任何源码**）

```
/var/www/dsh-pocket/
├── update.json          # 更新清单（版本号、下载地址、sha256、更新说明）
├── announcement.json    # 公告（首页横幅 + 公告列表）
└── dsh-pocket-1.1.0.apk # 安装包
```

对应的 nginx 配置（已经在 `/etc/nginx/conf.d/xuhuohua.conf` 里）：

```nginx
location /dsh-pocket/ {
    alias /var/www/dsh-pocket/;
    autoindex off;
    add_header Cache-Control "no-cache" always;
    types { application/vnd.android.package-archive apk; }
    default_type application/octet-stream;
}
```

## 改公告（不用重新打包）

1. 改 `server\announcement.json`（格式和课表那个一样：`{"announcements":[{id,title,content,createdAt}]}`）
2. `.`tools\publish_server.ps1 -AnnouncementOnly`
3. App 下次启动就能看到；看过的公告按 `id` 记在本地，不会反复弹

**id 换了才算新公告**：想重发同一条，改 id。

## 改更新清单

一般不用手动改——`publish_server.ps1` 每次发版都会重新生成。
只想调文案/备用链接，直接改服务器上的 `update.json` 即可（客户端每次启动读一次，`no-cache`）。

字段：

```json
{
  "versionCode": 2,              // 必须大于已装的 versionCode 才提示
  "versionName": "1.1.0",
  "force": false,                // true = 弹窗没有「稍后」，不给更新不让继续用
  "releaseDate": "2026-10-30",
  "notes": "1. ... \n2. ...",
  "apkUrl": "https://xuhuohua.xyz/dsh-pocket/dsh-pocket-1.1.0.apk",
  "sizeBytes": 35976451,
  "sha256": "…",                 // 下载后校验，防止下到半截或被替换
  "mirrors": ["https://github.com/.../releases/download/v1.1.0/dsh-pocket-1.1.0.apk"]
}
```

下载地址三选一（写进 `apkUrl`）：自己的服务器（你现在用的）、GitHub Release 直链、Gitee 附件直链。
服务器带宽小就把 `mirrors` 填上，App 的更新弹窗在下载失败时会给出备用链接。

## 发布版 vs 源码版只差一个编译开关

```powershell
# 发布版（带公告/更新/赞赏 + 收款码）
flutter build apk --release --target-platform android-arm64 --dart-define=OFFICIAL=true

# 源码版（什么都没多，连服务器的代码被 tree-shaking 掉）
flutter build apk --release
```

收款码不进仓库：仓库里只有 `docs/reward_qr.png`（README 用），
`assets/reward_qr.png` 是 `.gitignore` 的，`publish_server.ps1` 在构建前临时拷进去、构建后删掉。

## iOS

```powershell
.\tools\trigger_ios_build.ps1 -WaitMinutes 60   # 触发 + 等 + 下载 IPA 到 build\ios-ipa
```

Codemagic appId `6ae4229f80353414f5a033d8`，workflow `ios-unsigned`。
push 不会自动触发（用 API 建的 App 没装 webhook），要么用脚本，要么网页点 Start new build。

## 这台机器上踩过的坑（换机器可跳过）

- Gradle 守护进程 OOM：`android/gradle.properties` 里堆别超过 2G、`org.gradle.workers.max=2`
- Kotlin 增量缓存报 `Could not close incremental caches`：`kotlin.incremental=false`
- PowerShell 里 `flutter` 会解析成 `C:\flutter\bin\flutter`（bash 脚本，跑不动还不报错）：脚本里一律用 `flutter.bat`
- 资产换了以后构建报 `Cannot copy file ... already exists`：删掉 `build/app/intermediates/flutter/release/flutter_assets` 再编（两个发版脚本现在会自己先清这一层）
- 传服务器走 `pscp`，密码从 `.env` 的 `NBCC_SSH_PASSWORD` 读，写进临时文件用 `-pwfile` 传（不出现在命令行里）
- git push 需要走代理：`git -c http.proxy=http://127.0.0.1:7890 push origin main`
