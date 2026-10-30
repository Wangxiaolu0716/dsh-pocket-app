# 这个 App 是怎么贴着 dsh-pocket 做的

读 [dsh-pocket](https://github.com/shaobeichen/dsh-pocket) 源码（1.x 版）得出的结论，
以及每一条结论对应的 App 实现。改 dsh-pocket 或排查问题时对着看。

## 1. 入口与端口

- `dsh web` 跑在 `127.0.0.1:3080`
- dsh-pocket 起一个反向代理（默认 `3081`，可在 `$DSH_HOME/dsh-pocket/settings.json` 改 `proxyPort`），
  把请求改头（`Host`/`Origin` → loopback）后转发给上游，HTTP 与 WebSocket 全透传。
- 手机拿到的就是代理地址：局域网 `http://<电脑IP>:3081`，公网 `https://<随机>.trycloudflare.com`。
- **App 侧**：`--` 只认「scheme + host + port」，路径/查询/fragment 全丢掉
  （`lib/data/entry_url.dart` 的 `parseEntryUrl`），因为入口永远是根路径。

## 2. 认证（这是最容易做错的地方）

源码：`lib/proxy.mjs`

- 密码（PIN）默认 8 位随机；公网每次开启换新，可自定义 8–64 位固定；局域网独立一份，可整体关闭。
- 受保护 Host 上：
  - **HTML 导航**没 cookie → 返回登录页（`GET` 显示表单，`form action="/pocket-login"`），
    `POST /pocket-login` + `token` 字段校验通过后种 cookie。
  - **API/WS** 没 cookie → `401 {"error":"unauthorized"}`。
  - 带 `?token=<明文 PIN>` 进根路径 → 校验通过就在响应里种 HttpOnly cookie
    （`dsh_pocket_token`，30 天），并让后续子资源也走 cookie（修 issue #35 的白屏）。
- cookie 值 = `sha256(PIN:sessionKey)`，`sessionKey` 是 **dsh web 进程级随机值**：
  - dsh web 不重启 → 手机长期免输；
  - dsh web 重启/更新 → 旧 cookie 全失效 → 必须重新握手一次。
- 限速：同 IP 连续输错 5 次锁 60 秒；全局失败过多时短暂全锁。
- fail closed（issue #66）：除本机 loopback 和私网地址外，**一切陌生域名都按公网强制要密码**。

**App 侧对应实现**（`lib/ui/connection_page.dart`）：

1. 有密码就用 `buildEntryUri(base, pin: pin)` 打开 `/?token=<pin>` —— 一条请求完成「登录 + 进页面」，
   不碰表单、不碰 POST，也不受「登录页 POST 后再跳转」的时序影响。
2. 页面 `onPageFinished` 时跑一段 JS 自检（`_inspectJs`）：
   - 找到 `form[action="/pocket-login"]` → 说明密码不对/被换了 → 弹原生密码框；
   - body 里出现 `Browser did not keep the session cookie` → 上游的握手兜底页（issue #91）；
   - 出现 `无法连接上游` → 代理活着但 dsh web 没跑；
   - 否则认为已经进 DSH。
3. 密码进系统安全存储，下次（含 dsh web 重启后）自动带 `?token=` 重新握手。
4. 自动重试有上限：连续 3 次仍被弹回登录页就停下来提示，避免把电脑那边的限速锁触发。

## 3. 移动端布局

源码：`client/mobile/layout-mode.mjs`、`client/mobile/mobile-apply.tsx`

- 优先级：URL 参数 `?dsh-layout=desktop|mobile|auto` > `localStorage['dsh-pocket.layout']` > 屏幕宽度。
- 窄屏时会自己把 `meta viewport` 改成 `viewport-fit=cover`，并用 `env(safe-area-inset-*)`
  把界面压到安全区下面，还同步 `theme-color`。
- 也就是说：**缩放、安全区、抽屉布局这些脏活 dsh-pocket 的 CSS 已经干了**，
  App 不要自作聪明再套一层 `SafeArea`，否则会双倍留白。本项目的做法是
  WebView 端只留一个原生 AppBar（返回/刷新/菜单），内容区交给页面自己排。
- App 的「界面布局」菜单就是往 URL 上加 `dsh-layout`，并顺手记住选择。

## 4. 页面注入（为什么 App 里不用管 polyfill）

源码：`lib/proxy.mjs` 的 `DEFAULT_INJECT`

- 非安全上下文（`http://192.168.x.x`）里浏览器缺 `crypto.randomUUID` 和 `AbortSignal.any`，
  代理会往 HTML 里注入 polyfill，DSH 的连接层才能发消息。
- 所以 **App 用 WebView 打开 http 局域网地址也不会「消息发不出去」**——不用自己再注入一遍。

## 5. 探活为什么这么便宜

- 受保护 Host 上，根路径随便 `GET` 一下就能拿到 200（登录页）或 401，**不需要密码**，
  这正好当连通性探测用：拿到任何 HTTP 响应就算「这条线路活着」。
- `lib/data/probe.dart`：`GET /` + 4 秒超时，同时从 body 里认出「要密码」和「上游没跑」两种状态。
- 首页两条线路并行探活；连接页两条线路并行探活后按偏好挑第一条通的。

## 6. 实测：四种「页面」分别长什么样

用本机 dsh-pocket 源码起了个代理（上游指向本机 dsh web，密码 `12345678`），
从局域网 IP 访问，把 App 要认的四种状态都打了一遍：

| 请求 | 状态码 | 页面 | App 的判断 |
| --- | --- | --- | --- |
| `GET /`（无 cookie） | 200 | 登录页，`<form method="post" action="/pocket-login">` | `login` → 弹密码框 |
| `GET /?token=12345678` | 200/401 | 种下 `dsh_pocket_token` cookie 后放行 | 看上游：进 DSH 或者 `dshauth` |
| `GET /?token=00000000` | 200 | 还是登录页 | `login` → 「密码不对」 |
| 上游 dsh web 没跑 | 502 | 纯文本 `dsh-pocket: 无法连接上游 dsh web（…）` | `upstream` → 「dsh web 没有在运行」 |
| dsh web 的启动 token 没接上 | 401 | 纯文本 `dsh web authentication required; reopen the URL printed by dsh web.` | `dshauth` → 先自动重载一次（代理每次 `GET /` 都会补 token） |

两个**反直觉但要紧**的点：

1. `?token=` 带对时，代理会在**同一个响应**里种 cookie 并把请求转发给上游，所以
   App 不需要「先 POST 登录、再跳转」这种两步走；一条 `loadRequest` 就够了，
   也不会出现「主页 200、子资源 401」的白屏（那是 issue #35 修掉的）。
2. 登录页的 `<form>` 是 `method="post" action="/pocket-login"`——属性顺序别写死成
   `form action=...method=...`。App 侧用的是 CSS 属性选择器
   `document.querySelector('form[action="/pocket-login"]')`，与顺序无关；
   兜底再扫一遍 body 里的 `pocket-login` 字样。

## 7. 顺着代理去问 dsh-pocket 自己的状态（地址自动跟进）

dsh-pocket 的设置页通过一条 **loopback-only RPC** 跟主机通信：

- 通道：`POST /dsh-pocket/<endpoint>`，endpoint 见 `client/api.js` 的 `POCKET_ENDPOINTS`
  （`pocket.status` / `tunnel.start` / `pocket.restart` …）
- 信封：`{"rpcId":"…","method":"pocket.status","payload":{}}`
- 返回：`{"type":"server-response","rpcId":"…","result":{"ok":true,"data":{…}}}`
- 放行的前提是「Host 是 loopback」+ 不是 cross-site（`lib/web-rpc.js` 的 `isTrustedLoopbackRequest`）

**关键点：手机也能走这条路。** 代理会把 `Host`/`Origin`/`Referer` 全部改写成
`127.0.0.1:3080` 再转给上游，所以从手机发来的请求到了 dsh web 那儿，看起来就是本机请求；
再加上代理那层访问密码，等于「只有拿着密码的人能问」。

那么 App 拿到 `data` 里的这些就够用了：

| 字段 | 用途 |
| --- | --- |
| `tunnelUrl` | 当前公网地址（快速隧道每次重开都变）→ 自动写回本地配置 |
| `lanUrl` | 当前局域网地址（电脑换网/换 IP）→ 同上 |
| `proxyPort` | 代理端口，换过端口也能自己修 |
| `tunnelRunning` | 公网此刻开着没有，用来决定要不要提示「隧道没开」 |

**实现上的坑**：这个 RPC 认 dsh web 自己的会话 cookie，而 App 的原生 HTTP 客户端没有那套
cookie。所以查询**必须在页面上下文里发**（`lib/data/pocket_status.dart` 的 `pocketStatusJs`），
再用 `addJavaScriptChannel` 把结果 `postMessage` 回 Dart。

**能自动跟到什么程度：**

- 在家（局域网连得上）：一定能同步到最新公网地址，所以「电脑重启 dsh web → 出门」这条链路是通的
- 人在外面、公网地址已经变了：这时候没有任何本地信息可查，唯一办法是**命名隧道固定域名**
  （dsh-pocket 设置页里填 Cloudflare Tunnel Token + 自己的域名），或者让电脑主动往服务器上报地址
