# 与 dsh-pocket 的对接说明

读 [dsh-pocket](https://github.com/shaobeichen/dsh-pocket) 源码（1.x）整理出来的约定，以及 App 里对应的实现位置，排查问题时对着看。

## 1. 入口与端口

- `dsh web` 跑在 `127.0.0.1:3080`
- dsh-pocket 起一个反向代理，默认 `3081`，端口在 `$DSH_HOME/dsh-pocket/settings.json` 的 `proxyPort` 里改。代理会把 `Host`/`Origin` 改写成 loopback 再转发，HTTP 和 WebSocket 都透传。
- 手机拿到的是代理地址：局域网 `http://<电脑IP>:3081`，公网 `https://<随机名>.trycloudflare.com`。
- App 侧只取 scheme + host + port，路径、查询、fragment 全部丢掉（`lib/data/entry_url.dart` 的 `parseEntryUrl`）。入口永远是根路径。

## 2. 认证

源码：`lib/proxy.mjs`

- 密码默认 8 位随机。公网每次开启换新，也可以设成 8–64 位固定；局域网是独立的一份，能整个关掉。
- 受保护的 Host 上，三种情况：
  - HTML 导航没有 cookie：返回登录页，表单是 `<form method="post" action="/pocket-login">`，POST 带 `token` 字段校验通过后种 cookie。
  - API / WebSocket 没有 cookie：`401 {"error":"unauthorized"}`。
  - 带 `?token=<明文密码>` 请求根路径：校验通过，在同一个响应里种 HttpOnly cookie（`dsh_pocket_token`，30 天），后续子资源也走 cookie（issue #35 的白屏问题）。
- cookie 值 = `sha256(PIN:sessionKey)`，`sessionKey` 是 dsh web 的进程级随机值。dsh web 不重启就一直有效，重启或更新后全部失效，要重新握手一次。
- 限速：同一 IP 连错 5 次锁 60 秒，全局失败过多时短暂全锁。
- fail closed（issue #66）：除 loopback 和私网地址外，陌生域名一律按公网强制要密码。

App 的做法（`lib/ui/connection_page.dart`）：

1. 有密码就用 `buildEntryUri(base, pin: pin)` 打开 `/?token=<pin>`，一条请求完成登录和进页面，不走表单 POST，也没有「登录后跳转」的时序问题。
2. `onPageFinished` 里跑一段 JS 自检（`_inspectJs`），按页面内容判断状态：
   - 有 `form[action="/pocket-login"]`：密码不对或已更换，弹原生密码框
   - 出现 `Browser did not keep the session cookie`：上游的握手兜底页（issue #91）
   - 出现 `无法连接上游`：代理活着但 dsh web 没跑
   - 出现 `dsh web authentication required`：dsh web 自己的会话没接上，先自动重载一次
   - 都不匹配：认为已经进 DSH
3. 密码存系统安全存储，下次（包括 dsh web 重启之后）自动带上 `?token=` 重新握手。
4. 自动重试有上限，连续 3 次仍被弹回登录页就停下来提示，避免触发电脑端的限速。

## 3. 移动端布局

源码：`client/mobile/layout-mode.mjs`、`client/mobile/mobile-apply.tsx`

- 优先级：URL 参数 `?dsh-layout=desktop|mobile|auto` > `localStorage['dsh-pocket.layout']` > 屏幕宽度。
- 窄屏时 dsh-pocket 自己把 `meta viewport` 改成 `viewport-fit=cover`，用 `env(safe-area-inset-*)` 把界面压到安全区下面，并同步 `theme-color`。
- 缩放、安全区、抽屉布局都是页面自己处理的，所以 WebView 外面不要再套一层 `SafeArea`，会双倍留白。App 只留一个原生 AppBar（返回 / 刷新 / 菜单），内容区交给页面。
- 「界面布局」菜单就是往 URL 上加 `dsh-layout`，并把选择存下来。

## 4. 页面注入

源码：`lib/proxy.mjs` 的 `DEFAULT_INJECT`

非安全上下文（`http://192.168.x.x`）里浏览器没有 `crypto.randomUUID` 和 `AbortSignal.any`，DSH 的连接层发不出消息。代理会把这两个 polyfill 注入 HTML，所以 App 打开局域网 http 地址不需要额外处理。

## 5. 探活

受保护的 Host 上，根路径 `GET /` 不登录也会返回 200（登录页）或 401，正好当连通性探测：拿到任何 HTTP 响应就算这条线路通。

`lib/data/probe.dart`：`GET /`，4 秒超时，同时从 body 里识别「要密码」和「上游没跑」。首页两条线路并行探活；连接页并行探活后按偏好取第一条通的。

## 6. 实测过的状态

用本机 dsh-pocket 源码起了个代理，上游指向本机 dsh web，密码 `12345678`，从局域网 IP 访问，把 App 要识别的几种情况都打了一遍：

| 请求 | 状态码 | 页面 | App 的判断 |
| --- | --- | --- | --- |
| `GET /`（无 cookie） | 200 | 登录页，`<form method="post" action="/pocket-login">` | `login`，弹密码框 |
| `GET /?token=12345678` | 200 / 401 | 种下 `dsh_pocket_token` 后放行 | 看上游结果，进 DSH 或 `dshauth` |
| `GET /?token=00000000` | 200 | 还是登录页 | `login`，提示密码不对 |
| 上游 dsh web 没跑 | 502 | 纯文本 `dsh-pocket: 无法连接上游 dsh web（…）` | `upstream` |
| dsh web 启动 token 没接上 | 401 | 纯文本 `dsh web authentication required; reopen the URL printed by dsh web.` | `dshauth`，自动重载一次 |

两点容易写错的细节：

1. `?token=` 正确时，代理在同一个响应里种 cookie 并转发给上游。所以一条 `loadRequest` 就够了，不需要先 POST 登录再跳转。
2. 登录页表单的属性顺序是 `method="post" action="/pocket-login"`，不要写成 `form action=...` 去匹配字符串。App 用的是 CSS 属性选择器 `document.querySelector('form[action="/pocket-login"]')`，顺序无关；另外再扫一遍 body 里的 `pocket-login` 兜底。

## 7. 查询 dsh-pocket 状态（地址自动跟进的原理）

dsh-pocket 的设置页通过一条 loopback-only RPC 和主机通信：

- 通道：`POST /dsh-pocket/<endpoint>`，endpoint 见 `client/api.js` 的 `POCKET_ENDPOINTS`（`pocket.status`、`tunnel.start`、`pocket.restart` 等）
- 请求体：`{"rpcId":"…","method":"pocket.status","payload":{}}`
- 响应：`{"type":"server-response","rpcId":"…","result":{"ok":true,"data":{…}}}`
- 放行条件是 Host 为 loopback 且不是 cross-site（`lib/web-rpc.js` 的 `isTrustedLoopbackRequest`）

手机也能走这条路：代理把 `Host`/`Origin`/`Referer` 全改写成 `127.0.0.1:3080` 再转给上游，请求到了 dsh web 那里看起来就是本机的。加上代理那层访问密码，能问的只有拿到密码的人。

App 用到的字段：

| 字段 | 用途 |
| --- | --- |
| `tunnelUrl` | 当前公网地址，快速隧道每次重开都变，写回本地配置 |
| `lanUrl` | 当前局域网地址，电脑换网或换 IP 时跟着改 |
| `proxyPort` | 代理端口 |
| `tunnelRunning` | 公网此刻开没开 |

这个 RPC 认 dsh web 自己的会话 cookie，App 的原生 HTTP 客户端没有那套 cookie，所以查询放在页面上下文里发（`lib/data/pocket_status.dart` 的 `pocketStatusJs`），结果用 `addJavaScriptChannel` 传回 Dart。

覆盖范围：

- 局域网连得上时，一定能同步到最新公网地址。电脑重启 dsh web 之后再出门，用的是新地址。
- 人在外面且公网地址已经变了时，手机没有任何本地信息可查。这种情况要么用命名隧道固定域名（dsh-pocket 设置页里填 Cloudflare Tunnel Token 和域名），要么让电脑主动把地址上报到服务器。
