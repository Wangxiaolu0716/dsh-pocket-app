# DSH Pocket App

把 [dsh-pocket](https://github.com/shaobeichen/dsh-pocket) 的入口装进手机桌面：**扫码 → 连上你电脑上的 DeepSeek Harness → 就是电脑上那套界面，实时同步。**

Android / iOS 一套 Flutter 代码，界面中文。

<p align="center">
  <img src="assets_icon_1024.png" width="120">
</p>

---

## 它和 dsh-pocket 是什么关系

dsh-pocket 是一个 DSH 插件：它在电脑上起一个反向代理（默认 `3081`），把 `dsh web`（`3080`）包装成
「手机能看、能点、能实时同步」的页面，并且可选开 cloudflared 公网隧道。它给的入口就是一条普通 URL：

| 场景 | 入口 | 认证 |
| --- | --- | --- |
| 局域网（同一 WiFi） | `http://192.168.1.5:3081` | 默认 8 位密码（可在电脑端关掉） |
| 公网（人在外面） | `https://xxx.trycloudflare.com` | 永远要密码，每次开公网换新（也可自定义固定） |
| 命名隧道（固定域名） | `https://pocket.example.com` | 密码不自动轮换 |

所以这个 App **不重写 DSH 界面**，也不假装能脱离电脑跑：它是一个专门为 dsh-pocket 调过的
原生外壳。浏览器也能打开那个链接，但用浏览器会踩这些坑，App 把它们全处理掉了：

| 浏览器里的坑 | 这个 App 怎么处理 |
| --- | --- |
| 每次都要手输 8 位密码 | 密码存系统安全存储（Keystore / 钥匙串），进页面自动用 `?token=` 换好 cookie，**不用输** |
| 在家/在外面要换两个地址，还得记哪个通 | 一台电脑存两条线路，进去**先探活**：局域网通就用局域网，不通自动走公网 |
| 公网地址每次重开都变，旧书签打不开 | 地址随改随存；连不上时给的是「哪条线不通、为什么」而不是白屏 |
| 电脑重启 dsh web → 掉登录态，页面卡在登录页 | 认出登录页就弹原生密码框，输一次接着用（不用回设置页找链接） |
| 局域网 `http://` 在 iOS 被 ATS 拦死、Android 被明文策略拦死 | 两个平台都按需放开（只对 App 自身生效） |
| 电脑上 dsh web 没开，页面一片空白 | 直接说人话：「电脑上的 dsh web 没有在运行」 |
| 顺手点开外链，在 App 里回不去了 | 外链一律丢给系统浏览器，App 只留 DSH 本体 |
| 想在大屏/折叠屏用电脑布局 | 菜单里手机 / 电脑 / 自动三档，改完记住 |

## 功能

- 📷 **扫码添加**：对着电脑端「设置 → 手机访问」里的二维码扫一下。CLI 版二维码里自带
  `?token=` 的，密码也一并读走。
- 🧠 **两条线路自动选**：局域网优先，失败回落公网；两条都试过还不通，会列出每条线的探测结果。
- 🔄 **地址自动跟进**：连上电脑后顺手问一次 dsh-pocket 的状态，把当前的**公网域名**（快速隧道每次重开都会变）和**局域网 IP** 同步回本地配置。电脑重启 dsh web 之后，只要你在家用局域网连过一次，出门用的公网地址就已经是新地址了。
- 🖤 **真·满屏**：状态栏 / 底部导航栏透明，界面背景一直铺到屏幕边缘，不再有那条深浅不一的色带（Android 15 起系统强制 edge-to-edge，这里对齐了）。
- 🔑 **一次输入长期免输**：密码进系统安全存储；dsh web 重启后自动重新握手。
- 📱 **手机布局原生感**：用的是 dsh-pocket 自己的移动端适配（`?dsh-layout=` 可控），
  不是缩小版桌面网页。
- ⚙️ **每台电脑的独立配置**：名称、两条地址、默认线路、默认布局。
- 🌙 **深色 / 浅色 / 跟随系统**，跟 DSH 本体一个观感。
- 🔗 **复制入口链接**（带密码，方便临时在别人的浏览器里看，注意别外传）。

## 发布版 vs 源码版

只有一处开关：`--dart-define=OFFICIAL=true`。

| | 源码版（默认） | 发布版 |
| --- | --- | --- |
| 扫码 / 线路 / 自动登录 / 满屏 | ✅ | ✅ |
| 检查更新（服务器清单） | ❌ 自己 `git pull` 重编 | ✅ 带下载进度、sha256 校验、装完即用 |
| 服务器公告 | ❌ | ✅ 首页横幅 + 公告列表 |
| 赞赏入口 / 收款码 | ❌ 仓库里只有 README 那张图 | ✅ 内置入口（收款码构建时才塞进 APK） |

服务器上**只有两个 JSON 和一个 APK**（`https://xuhuohua.xyz/dsh-pocket/`），
没有任何源码、没有后端：公告和版本号都是纯静态文件，改完立刻生效，不用重新发版。

## 下载

[Releases](https://github.com/Wangxiaolu0716/dsh-pocket-app/releases) 里两个都有：

- `dsh-pocket-1.0.0.apk` —— Android，直接装（debug 证书签名）
- `dsh-pocket-1.0.0-unsigned.ipa` —— iOS，**未签名**，用 Sideloadly / AltStore 重签后装

## 安装

### Android

```powershell
flutter build apk --release
# 产物 build\app\outputs\flutter-apk\app-release.apk（debug 证书签名，可直接装）
```

或者用 `tools\release.ps1` 一键：改版本号 → analyze + test → 出包 → 发 GitHub Release。

### iOS

Windows 上编不了 iOS，走 Codemagic（和课表 App 同一套办法）：

1. Codemagic 上已经建好这个 App（appId `6ae4229f80353414f5a033d8`），配置用仓库里的
   `codemagic.yaml`（workflow：`ios-unsigned`）
2. push 一下就开跑，产物是 **未签名 IPA**（`build/ios/iphoneos/*.ipa`）
3. 装到手机：Sideloadly / AltStore 重签后安装

> 首次构建已跑通（Codemagic build #1–#3，3~4 分钟出包，min iOS 15.0）。
> 注意：用 API 新建的 Codemagic App 没有自动装 GitHub webhook，push 不会自己触发，
> 用 `tools\trigger_ios_build.ps1` 触发一次，或者去 Codemagic 网页里点 Start new build。

```powershell
# 触发一次构建 + 等它跑完 + 把 IPA 拉到 build\ios-ipa\（token 在 .env 的 CODEMAGIC_TOKEN）
.\tools\trigger_ios_build.ps1 -WaitMinutes 60

# 已经有构建在跑，只想取包
.\tools\fetch_ios_ipa.ps1 -WaitMinutes 60
```

## 开发

```powershell
flutter pub get
flutter analyze     # 零问题
flutter test        # 入口地址解析 / 线路排序 / JSON 往返
flutter run         # 插根数据线直接跑
```

代码不多，都在 `lib/`：

```
lib/
  main.dart              入口
  app_controller.dart    全局状态（设备列表 + 主题/默认布局）
  theme.dart             跟 DSH 一致的深色/浅色主题
  app_info.dart          版本号 / 仓库地址 / UA 尾巴
  models/connection.dart 一台电脑 = 名称 + 局域网地址 + 公网地址 + 偏好 + 布局
  data/entry_url.dart    入口 URL 解析与拼装（纯函数，有单测）
  data/probe.dart        探活 + 选线路
  data/connection_store.dart  设备列表持久化
  data/secret_store.dart      密码存放（安全存储，带降级）
  ui/home_page.dart      设备列表
  ui/scan_page.dart      扫码
  ui/add_connection_page.dart  手填 / 编辑
  ui/connection_page.dart      WebView 外壳（核心）
  ui/settings_page.dart  设置
```

## 已知边界

- **iOS 未签名包**：普通用户直接点开装不上，得重签。要正式分发需要 Apple 开发者账号
  （$99/年）+ App Store Connect 集成。
- **Android release 用 debug 证书**：能装能升级，但换签名要卸载重装。上架需要自己的 keystore。
- **不做后台常驻**：手机锁屏/切后台久了，WebSocket 可能被系统掐掉。回到 App 会自动重连
  （DSH 前端自己会重连，连不上时点右上角刷新）。想在后台收「任务跑完了」的推送，需要
  电脑侧出 webhook + 推送服务，这一版没做。
- **文件下载**：WebView 里点下载不会落地。要下载文件用菜单里的「用系统浏览器打开」。
- **DSH Desktop 的 advanced 模式**不支持手机访问（上游限制），请用 compatibility 模式。

## 赞赏

用着顺手，可以请作者喝杯奶茶 ☕（源码版没有这个入口，这里放图就够了）：

<img src="docs/reward_qr.png" width="260" alt="微信赞赏码">

## License

MIT
