import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../app_controller.dart';
import '../app_info.dart';
import '../data/entry_url.dart';
import '../data/pocket_status.dart';
import '../data/probe.dart';
import '../models/connection.dart';
import 'add_connection_page.dart';
import 'widgets.dart';

/// 连接页：一条真实的 dsh-pocket 会话。
///
/// 干的事：
///   1. 按偏好挑一条通得上的线路（局域网优先，其次公网）
///   2. 用 ?token=<密码> 打开入口 —— dsh-pocket 见到 token 就种 HttpOnly cookie，
///      于是手机上「不用再输密码」，除非电脑那边重启过 dsh web
///   3. 页面加载完检查一眼：是不是被弹回了登录页 / 是不是电脑上 dsh web 没跑
///   4. 里面就是电脑上的 DSH 本身：流式输出、审批、终端全在 WebView 里跑
class ConnectionPage extends StatefulWidget {
  const ConnectionPage({
    super.key,
    required this.controller,
    required this.connection,
  });

  final AppController controller;
  final Connection connection;

  @override
  State<ConnectionPage> createState() => _ConnectionPageState();
}

enum _Phase { connecting, live, offline, failed }

class _ConnectionPageState extends State<ConnectionPage>
    with WidgetsBindingObserver {
  late final WebViewController _web;
  late Connection _conn;
  String? _pin;

  _Phase _phase = _Phase.connecting;
  String? _error;
  String? _detail;
  int _progress = 0;
  LinePolicy? _line;
  String _base = '';

  bool _webviewPrepared = false;
  bool _inspecting = false;
  bool _pinDialogOpen = false;
  bool _authRetried = false;
  bool _statusSynced = false;
  int _pinAttempts = 0;
  Map<LinePolicy, ProbeResult> _probeResults = const {};

  AppController get _app => widget.controller;

  @override
  void initState() {
    super.initState();
    _conn = widget.connection;
    WidgetsBinding.instance.addObserver(this);
    _web = WebViewController()
      // 页面里问完 dsh-pocket 的状态后会 postMessage 回来（拿当前公网/局域网地址）
      ..addJavaScriptChannel(
        'DshPocketBridge',
        onMessageReceived: (message) => _onBridgeMessage(message.message),
      )
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF0B0D12))
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (value) {
            if (!mounted) return;
            setState(() => _progress = value);
          },
          onPageFinished: (_) => _inspect(),
          onWebResourceError: _onResourceError,
          onNavigationRequest: _onNavigationRequest,
        ),
      );
    _boot();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    switch (_phase) {
      case _Phase.offline:
      case _Phase.failed:
        _boot();
      case _Phase.live:
        // 电脑那边可能重启过 dsh web（会掉登录态），回来先看一眼
        _inspect();
      case _Phase.connecting:
        break;
    }
  }

  // ---------------------------------------------------------------- 连接

  Future<void> _boot() async {
    setState(() {
      _phase = _Phase.connecting;
      _error = null;
      _detail = null;
      _progress = 0;
    });
    _pin = await _app.store.pin(_conn.id);
    if (!mounted) return;

    final probes = await _probeBothLines();
    final choice = _choose(probes);
    if (!mounted) return;
    _probeResults = probes;
    if (choice == null) {
      setState(() {
        _phase = _Phase.offline;
        _error = '两条线路都连不上';
      });
      return;
    }
    _base = choice.baseUrl;
    _line = choice.kind;
    await _openEntry();
    await _app.store.touch(_conn.id, line: choice.kind);
  }

  /// 两条线路并测，界面能把「局域网不通、公网通」这类情况讲清楚。
  Future<Map<LinePolicy, ProbeResult>> _probeBothLines() async {
    final lines = _conn.orderedLines();
    final results = <LinePolicy, ProbeResult>{};
    await Future.wait(lines.map((line) async {
      results[line.kind] = await httpProbe(line.baseUrl);
    }));
    return results;
  }

  LineChoice? _choose(Map<LinePolicy, ProbeResult> probes) {
    for (final line in _conn.orderedLines()) {
      final probe = probes[line.kind];
      if (probe != null && probe.reachable) {
        return LineChoice(kind: line.kind, baseUrl: line.baseUrl, probe: probe);
      }
    }
    return null;
  }

  /// 用户点「仍然打开」时用：不探测，直接照偏好第一条线路开。
  Future<void> _forceOpen() async {
    final lines = _conn.orderedLines();
    if (lines.isEmpty) return;
    _base = lines.first.baseUrl;
    _line = lines.first.kind;
    _pin ??= await _app.store.pin(_conn.id);
    await _openEntry();
  }

  Future<void> _openEntry() async {
    if (!_webviewPrepared) {
      try {
        final defaultUa = await _web.getUserAgent();
        await _web.setUserAgent('$defaultUa $kUserAgentSuffix');
      } catch (_) {
        // 拿不到默认 UA 就不加尾巴，不影响主流程
      }
      _webviewPrepared = true;
    }
    _progress = 0;
    _authRetried = false;
    _statusSynced = false;
    final uri = buildEntryUri(_base, pin: _pin, layout: _conn.layout);
    setState(() {
      _phase = _Phase.live;
      _error = null;
      _detail = null;
    });
    await _web.loadRequest(uri);
  }

  // ---------------------------------------------------------------- 页面自检

  /// 在页面里跑一段 JS，判断现在是「已经进了 DSH」还是被拦在门外。
  static const String _inspectJs = r'''
(function () {
  try {
    if (document.querySelector('form[action="/pocket-login"]')) return 'login';
    var text = document.body ? (document.body.innerText || '') : '';
    if (text.indexOf('pocket-login') >= 0) return 'login';
    if (text.indexOf('Browser did not keep the session cookie') >= 0) return 'blocked';
    if (text.indexOf('无法连接上游') >= 0) return 'upstream';
    if (text.indexOf('dsh web 没有运行') >= 0) return 'upstream';
    if (text.indexOf('dsh web authentication required') >= 0) return 'dshauth';
    return 'app';
  } catch (e) {
    return 'unknown';
  }
})()
''';

  Future<void> _inspect() async {
    if (_inspecting || _phase == _Phase.connecting) return;
    if (_base.isEmpty) return;
    _inspecting = true;
    try {
      final raw = await _web.runJavaScriptReturningResult(_inspectJs);
      if (!mounted) return;
      final state = _normalizeJs(raw);
      switch (state) {
        case 'login':
          await _handleLoginPage();
        case 'blocked':
          setState(() {
            _phase = _Phase.failed;
            _error = '浏览器没保住登录 cookie';
            _detail = '这是 dsh-pocket 已知的握手问题（http:// + IP 的老 Safari 场景）。'
                '点「重新加载」再试一次，或者改用公网 HTTPS 地址进入。';
          });
        case 'dshauth':
          // dsh web 给浏览器会话的启动 token 没接上（多见于电脑那边刚重启 dsh web）。
          // 代理每次 GET / 都会补一次，所以先默默重载一遍。
          if (!_authRetried) {
            _authRetried = true;
            await _web.reload();
          } else {
            setState(() {
              _phase = _Phase.failed;
              _error = 'dsh web 的浏览器会话没接上';
              _detail = '电脑上的 dsh web 刚重启过，或者它的启动链接变了。'
                  '点「重新加载」再试一次；还不行就在电脑上重新打开一次 dsh web 给的地址。';
            });
          }
        case 'upstream':
          setState(() {
            _phase = _Phase.failed;
            _error = '电脑上的 dsh web 没有在运行';
            _detail = 'dsh-pocket 的代理活着，但它连不上 3080 端口。'
                '去电脑上重启一下 dsh web，再点「重新加载」。';
          });
        case 'app':
          setState(() {
            _phase = _Phase.live;
            _error = null;
            _detail = null;
          });
          _syncStatusFromPage();
        default:
          setState(() => _phase = _Phase.live);
      }
    } catch (_) {
      // 页面还在跳（或者还是 about:blank），下一次 onPageFinished 再说
    } finally {
      _inspecting = false;
    }
  }

  /// 让页面替我们问一次 dsh-pocket 的状态，把最新的公网/局域网地址记下来。
  ///
  /// 为什么要绕这么一圈：那个 RPC 是 loopback-only 且要 dsh web 自己的 cookie，
  /// 只有页面上下文里才有；原生 HTTP 客户端问了也是 401。
  /// 拿到之后：
  ///   - 电脑重启 dsh web → 快速隧道换了新地址 → 下次连公网自动用新的
  ///   - 电脑换了 IP / 换了 WiFi → 局域网地址也能自己改过来
  Future<void> _syncStatusFromPage() async {
    if (_statusSynced) return;
    _statusSynced = true;
    try {
      await _web.runJavaScript(pocketStatusJs);
    } catch (_) {
      // 页面不让跑 JS 就算了，纯锦上添花
    }
  }

  Future<void> _onBridgeMessage(String raw) async {
    final status = PocketStatus.tryParse(raw);
    if (status == null || status.isEmpty || !mounted) return;

    var conn = _conn;
    final changes = <String>[];
    if (status.tunnelUrl != null && status.tunnelUrl != conn.publicUrl) {
      conn = conn.copyWith(publicUrl: status.tunnelUrl);
      changes.add('公网');
    }
    if (status.lanUrl != null && status.lanUrl != conn.lanUrl) {
      conn = conn.copyWith(lanUrl: status.lanUrl);
      changes.add('局域网');
    }
    if (changes.isEmpty) return;

    _conn = conn;
    await _app.store.upsert(conn);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已同步电脑上的新${changes.join(' / ')}地址')),
    );
  }

  static String _normalizeJs(Object? raw) {
    var text = (raw ?? '').toString().trim();
    if (text.length >= 2 && text.startsWith('"') && text.endsWith('"')) {
      text = text.substring(1, text.length - 1);
    }
    return text;
  }

  Future<void> _handleLoginPage() async {
    final hadPin = _pin != null && _pin!.trim().isNotEmpty;
    if (!mounted || _pinDialogOpen) return;
    await _askPin(wrongPin: hadPin);
  }

  /// 要密码：输一次就存进安全存储，下次（以及 dsh web 重启后）自动带上。
  Future<void> _askPin({required bool wrongPin}) async {
    if (_pinAttempts >= 3) {
      setState(() {
        _phase = _Phase.failed;
        _error = '密码一直不对';
        _detail = '连续输错 5 次会被电脑那边锁 60 秒。'
            '去电脑端「设置 → 手机访问」复制一下当前密码，再回来点「重新输入密码」。';
      });
      return;
    }
    _pinDialogOpen = true;
    final textController = TextEditingController();
    var obscure = true;
    final pin = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(wrongPin ? '密码不对，再输一次' : '输入访问密码'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                wrongPin
                    ? '电脑上的密码换过了，或者这条不是当前那个密码。'
                    : '电脑端「设置 → 手机访问」里有这串密码（8 位数字，或你自己设的）。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 14),
              TextField(
                controller: textController,
                autofocus: true,
                obscureText: obscure,
                autocorrect: false,
                enableSuggestions: false,
                keyboardType: TextInputType.visiblePassword,
                textInputAction: TextInputAction.done,
                onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
                decoration: InputDecoration(
                  labelText: '访问密码',
                  suffixIcon: IconButton(
                    onPressed: () => setDialogState(() => obscure = !obscure),
                    icon: Icon(
                      obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('返回'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(textController.text.trim()),
              child: const Text('连接'),
            ),
          ],
        ),
      ),
    );
    _pinDialogOpen = false;
    textController.dispose();
    if (!mounted) return;

    if (pin == null || pin.isEmpty) {
      // 没有密码就进不去，回到设备列表让用户自己决定
      Navigator.of(context).pop();
      return;
    }
    _pinAttempts += 1;
    _pin = pin;
    await _app.store.setPin(_conn.id, pin);
    if (!mounted) return;
    await _openEntry();
  }

  // ---------------------------------------------------------------- 回调

  void _onResourceError(WebResourceError error) {
    if (error.isForMainFrame == false) return;
    if (!mounted) return;
    setState(() {
      _phase = _Phase.failed;
      _error = '打不开 $_base';
      _detail = error.description;
    });
  }

  NavigationDecision _onNavigationRequest(NavigationRequest request) {
    final uri = Uri.tryParse(request.url);
    if (uri == null) return NavigationDecision.navigate;
    // about: / data: / blob: 是页面自己在折腾，交给 WebView
    if (uri.scheme == 'about' || uri.scheme == 'data' || uri.scheme == 'blob') {
      return NavigationDecision.navigate;
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      // mailto: / tel: 之类交给系统
      launchUrl(uri, mode: LaunchMode.externalApplication);
      return NavigationDecision.prevent;
    }
    if (!request.isMainFrame) return NavigationDecision.navigate;
    final baseHost = Uri.tryParse(_base)?.host;
    if (baseHost != null && uri.host != baseHost) {
      // 页面里的外链（文档、GitHub 等）丢给系统浏览器，别在 App 里迷路
      launchUrl(uri, mode: LaunchMode.externalApplication);
      return NavigationDecision.prevent;
    }
    return NavigationDecision.navigate;
  }

  // ---------------------------------------------------------------- 菜单动作

  Future<void> _switchLine() async {
    final picked = await showModalBottomSheet<LinePolicy>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final policy in LinePolicy.values)
              ListTile(
                title: Text(switch (policy) {
                  LinePolicy.auto => '自动（局域网优先）',
                  LinePolicy.lan => '局域网',
                  LinePolicy.public => '公网',
                }),
                subtitle: Text(switch (policy) {
                  LinePolicy.auto => '在家/公司走局域网，不通自动转公网',
                  LinePolicy.lan => _conn.lanUrl ?? '没填局域网地址',
                  LinePolicy.public => _conn.publicUrl ?? '没填公网地址',
                }),
                enabled: switch (policy) {
                  LinePolicy.auto => true,
                  LinePolicy.lan => _conn.hasLan,
                  LinePolicy.public => _conn.hasPublic,
                },
                trailing: _conn.policy == policy
                    ? const Icon(Icons.check, size: 18)
                    : null,
                onTap: () => Navigator.of(context).pop(policy),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    _conn = _conn.copyWith(policy: picked);
    await _app.store.upsert(_conn);
    if (mounted) await _boot();
  }

  Future<void> _switchLayout() async {
    final picked = await showModalBottomSheet<LayoutPref>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final layout in LayoutPref.values)
              ListTile(
                title: Text(switch (layout) {
                  LayoutPref.auto => '自动（按屏幕宽度）',
                  LayoutPref.mobile => '手机布局',
                  LayoutPref.desktop => '电脑布局',
                }),
                subtitle: layout == LayoutPref.desktop
                    ? const Text('Pad / 折叠屏展开时更像电脑；手机屏幕会很挤')
                    : null,
                trailing: _conn.layout == layout
                    ? const Icon(Icons.check, size: 18)
                    : null,
                onTap: () => Navigator.of(context).pop(layout),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    _conn = _conn.copyWith(layout: picked);
    await _app.store.upsert(_conn);
    if (!mounted) return;
    await _openEntry();
  }

  Future<void> _copyLink() async {
    final uri = buildEntryUri(_base, pin: _pin, layout: _conn.layout);
    await Clipboard.setData(ClipboardData(text: uri.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('链接里带着密码，别发给别人')),
    );
  }

  Future<void> _openInBrowser() async {
    final uri = buildEntryUri(_base, pin: _pin, layout: _conn.layout);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('没找到能打开的浏览器')));
    }
  }

  Future<void> _clearSession() async {
    try {
      await WebViewCookieManager().clearCookies();
      await _web.clearCache();
      await _web.clearLocalStorage();
    } catch (_) {
      // 清不掉也不至于用不了
    }
    if (!mounted) return;
    await _openEntry();
  }

  Future<void> _editConnection() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AddConnectionPage(controller: _app, editing: _conn),
      ),
    );
    final refreshed = _app.store.byId(_conn.id);
    if (!mounted) return;
    if (refreshed == null) {
      Navigator.of(context).pop();
      return;
    }
    _conn = refreshed;
    _pin = await _app.store.pin(_conn.id);
    if (mounted) await _boot();
  }

  // ---------------------------------------------------------------- 界面

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        if (_phase == _Phase.live && await _web.canGoBack()) {
          await _web.goBack();
          return;
        }
        if (mounted) navigator.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_conn.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(
                _subtitle(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: '刷新',
              onPressed: _phase == _Phase.live ? () => _web.reload() : _boot,
              icon: const Icon(Icons.refresh),
            ),
            PopupMenuButton<String>(
              tooltip: '更多',
              onSelected: (value) async {
                switch (value) {
                  case 'line':
                    await _switchLine();
                  case 'layout':
                    await _switchLayout();
                  case 'pin':
                    _pinAttempts = 0;
                    await _askPin(wrongPin: false);
                  case 'copy':
                    await _copyLink();
                  case 'browser':
                    await _openInBrowser();
                  case 'clear':
                    await _clearSession();
                  case 'edit':
                    await _editConnection();
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'line', child: Text('切换线路')),
                PopupMenuItem(value: 'layout', child: Text('界面布局')),
                PopupMenuItem(value: 'pin', child: Text('重新输入密码')),
                PopupMenuDivider(),
                PopupMenuItem(value: 'copy', child: Text('复制入口链接')),
                PopupMenuItem(value: 'browser', child: Text('用系统浏览器打开')),
                PopupMenuItem(value: 'clear', child: Text('清除本站登录状态')),
                PopupMenuDivider(),
                PopupMenuItem(value: 'edit', child: Text('编辑这台电脑')),
              ],
            ),
          ],
        ),
        body: Padding(
          // 安卓：edge-to-edge 之后内容会铺到手势条底下，补一层等效留白；
          // iOS：dsh-pocket 的移动端 CSS 自己处理 env(safe-area-inset-bottom)，别重复加
          padding: EdgeInsets.only(
            bottom: Platform.isAndroid ? MediaQuery.viewPaddingOf(context).bottom : 0,
          ),
          child: Stack(
          children: [
            // WebView 一直在，别因为切状态被重建（重建 = 丢页面状态）
            Positioned.fill(child: WebViewWidget(controller: _web)),
            if (_phase == _Phase.connecting) _buildConnecting(theme),
            if (_phase == _Phase.offline) _buildOffline(theme),
            if (_phase == _Phase.failed) _buildFailed(theme),
            if (_phase == _Phase.live && _progress < 100)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: LinearProgressIndicator(
                  value: _progress <= 0 ? null : _progress / 100,
                  minHeight: 2,
                ),
              ),
          ],
          ),
        ),
      ),
    );
  }

  String _subtitle() {
    if (_phase == _Phase.connecting) return '正在连接…';
    if (_base.isEmpty) return '未连接';
    final lineLabel = switch (_line) {
      LinePolicy.lan => '局域网',
      LinePolicy.public => '公网',
      _ => '',
    };
    final host = Uri.tryParse(_base)?.authority ?? _base;
    return lineLabel.isEmpty ? host : '$lineLabel · $host';
  }

  Widget _buildConnecting(ThemeData theme) {
    return _Overlay(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 18),
          Text('正在连接电脑…', style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          Text(
            '先试局域网，不通再走公网',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildOffline(ThemeData theme) {
    return _Overlay(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.wifi_off, size: 44, color: theme.colorScheme.error),
            const SizedBox(height: 14),
            Text(
              '连不上这台电脑',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            for (final line in _conn.orderedLines())
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    StatusDot(
                      state: _probeResults[line.kind]?.reachable == true
                          ? ProbeDotState.online
                          : ProbeDotState.offline,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _probeLineText(line),
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 10),
            Text(
              '常见原因：',
              style: theme.textTheme.labelLarge
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              '· 手机和电脑不在同一个 WiFi（走局域网要同一个网络）\n'
              '· 电脑端「公网访问」没开，或隧道刚重启换了新地址\n'
              '· 电脑上的 dsh web 没在跑\n'
              '· 手机上开着 VPN，把局域网流量劫走了',
              style: theme.textTheme.bodySmall?.copyWith(height: 1.6),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: _boot,
                  icon: const Icon(Icons.refresh),
                  label: const Text('重试'),
                ),
                OutlinedButton(
                  onPressed: _forceOpen,
                  child: const Text('仍然打开'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: _editConnection,
              child: const Text('改地址 / 换密码'),
            ),
          ],
        ),
      ),
    );
  }

  String _probeLineText(ConnectionLine line) {
    final probe = _probeResults[line.kind];
    final suffix = probe?.error == null ? '' : '（${probe!.error}）';
    return '${line.label}  ${line.baseUrl}$suffix';
  }

  Widget _buildFailed(ThemeData theme) {
    return _Overlay(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, size: 44, color: theme.colorScheme.error),
            const SizedBox(height: 14),
            Text(
              _error ?? '出错了',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            if (_detail != null) ...[
              const SizedBox(height: 10),
              Text(
                _detail!,
                style: theme.textTheme.bodySmall?.copyWith(height: 1.6),
              ),
            ],
            const SizedBox(height: 20),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: _boot,
                  icon: const Icon(Icons.refresh),
                  label: const Text('重新加载'),
                ),
                OutlinedButton(
                  onPressed: () {
                    _pinAttempts = 0;
                    _askPin(wrongPin: false);
                  },
                  child: const Text('重新输入密码'),
                ),
                OutlinedButton(
                  onPressed: _editConnection,
                  child: const Text('改地址'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 盖在 WebView 上的状态层。
class _Overlay extends StatelessWidget {
  const _Overlay({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ColoredBox(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: Center(child: child),
      ),
    );
  }
}
