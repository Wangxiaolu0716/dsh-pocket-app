/// dsh-pocket 的状态查询（借 WebView 里的页面去问）。
///
/// 为什么要走页面：`/dsh-pocket/pocket.status` 是 loopback-only 的 RPC，
/// dsh web 自己也认 cookie；App 的原生 HTTP 客户端没有那套会话，只有页面里有。
/// 所以在页面上下文里 fetch，再让它把结果 postMessage 回来。
///
/// 拿到的东西里，App 只关心这几个：
///   - tunnelUrl：当前公网地址（快速隧道每次重开都会变，靠这个自动跟进）
///   - lanUrl：当前局域网地址（电脑换了 IP / 换了网也能自己改过来）
///   - proxyPort：代理端口
library;

import 'dart:convert';

class PocketStatus {
  const PocketStatus({this.tunnelUrl, this.lanUrl, this.proxyPort, this.tunnelRunning});

  final String? tunnelUrl;
  final String? lanUrl;
  final int? proxyPort;
  final bool? tunnelRunning;

  bool get isEmpty => tunnelUrl == null && lanUrl == null;

  /// 解析 server-response 信封 → result.data。
  ///
  /// 形状：{"type":"server-response","rpcId":"..","result":{"ok":true,"data":{...}}}
  static PocketStatus? tryParse(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final result = decoded['result'];
      if (result is! Map) return null;
      if (result['ok'] != true) return null;
      final data = result['data'];
      if (data is! Map) return null;
      return PocketStatus(
        tunnelUrl: _cleanUrl(data['tunnelUrl']),
        lanUrl: _cleanUrl(data['lanUrl']),
        proxyPort: data['proxyPort'] is int ? data['proxyPort'] as int : null,
        tunnelRunning: data['tunnelRunning'] is bool ? data['tunnelRunning'] as bool : null,
      );
    } catch (_) {
      return null;
    }
  }

  static String? _cleanUrl(Object? value) {
    if (value is! String) return null;
    final text = value.trim();
    if (text.isEmpty) return null;
    final uri = Uri.tryParse(text);
    if (uri == null || uri.host.isEmpty) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    return text.endsWith('/') ? text.substring(0, text.length - 1) : text;
  }
}

/// 在页面里执行的 JS：问一次状态，把响应原文 postMessage 回来。
const String pocketStatusJs = r'''
(function () {
  try {
    if (window.__dshPocketStatusDone) return 'skip';
    window.__dshPocketStatusDone = true;
    fetch('/dsh-pocket/pocket.status', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ rpcId: 'dsh-pocket-app', method: 'pocket.status' })
    })
      .then(function (r) { return r.text(); })
      .then(function (t) { window.DshPocketBridge.postMessage(t); })
      .catch(function (e) { window.DshPocketBridge.postMessage('{"error":"' + e + '"}'); });
    return 'sent';
  } catch (e) {
    return 'error';
  }
})()
''';
