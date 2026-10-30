import 'dart:async';

import 'package:http/http.dart' as http;

import '../models/connection.dart';

/// 一次连通性探测的结果。
class ProbeResult {
  const ProbeResult({
    required this.reachable,
    this.needsPin = false,
    this.upstreamDown = false,
    this.statusCode,
    this.elapsed = Duration.zero,
    this.error,
  });

  final bool reachable;

  /// 探测到的是「请输入访问密码」页 —— 说明代理活着，只差密码。
  final bool needsPin;

  /// 代理活着，但它连不上 dsh web（电脑上没跑 dsh web）。
  final bool upstreamDown;

  final int? statusCode;
  final Duration elapsed;
  final String? error;

  static const offline = ProbeResult(reachable: false);
}

typedef Prober = Future<ProbeResult> Function(String baseUrl);

/// 真连一下。只要拿到任何 HTTP 响应就算「通」——认证失败、握手页、上游挂了
/// 都说明隧道/局域网这条路是活着的，值得让用户去解决后续问题。
Future<ProbeResult> httpProbe(
  String baseUrl, {
  Duration timeout = const Duration(seconds: 4),
}) async {
  final stopwatch = Stopwatch()..start();
  final client = http.Client();
  try {
    final uri = Uri.parse(baseUrl).replace(path: '/');
    final response = await client
        .get(uri, headers: {'accept': 'text/html,*/*'})
        .timeout(timeout);
    final body = response.body;
    stopwatch.stop();
    return ProbeResult(
      reachable: true,
      needsPin: response.statusCode == 401 || body.contains('/pocket-login'),
      upstreamDown: body.contains('无法连接上游') ||
          body.contains('pocket: 无法连接上游'),
      statusCode: response.statusCode,
      elapsed: stopwatch.elapsed,
    );
  } on TimeoutException {
    stopwatch.stop();
    return ProbeResult(
      reachable: false,
      elapsed: stopwatch.elapsed,
      error: '超时（${timeout.inSeconds} 秒）',
    );
  } catch (error) {
    stopwatch.stop();
    return ProbeResult(
      reachable: false,
      elapsed: stopwatch.elapsed,
      error: _shortError(error),
    );
  } finally {
    client.close();
  }
}

String _shortError(Object error) {
  final text = error.toString();
  if (text.contains('SocketException')) {
    if (text.contains('refused') || text.contains('拒绝')) return '连接被拒绝';
    if (text.contains('Failed host lookup')) return '域名解析失败';
    return '网络不可达';
  }
  if (text.contains('HandshakeException')) return 'TLS 握手失败';
  return text.length > 80 ? '${text.substring(0, 80)}…' : text;
}

/// 选定一条线路：按偏好顺序试，谁先通就用谁。
class LineChoice {
  const LineChoice({
    required this.kind,
    required this.baseUrl,
    required this.probe,
  });

  final LinePolicy kind;
  final String baseUrl;
  final ProbeResult probe;

  String get label => kind == LinePolicy.lan ? '局域网' : '公网';
}

/// 逐条试线路；都不通返回 null。顺序由 Connection.policy 决定。
Future<LineChoice?> pickLine(
  Connection connection, {
  Prober prober = httpProbe,
}) async {
  for (final line in connection.orderedLines()) {
    final result = await prober(line.baseUrl);
    if (result.reachable) {
      return LineChoice(kind: line.kind, baseUrl: line.baseUrl, probe: result);
    }
  }
  return null;
}
