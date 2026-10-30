/// 入口地址的解析与拼装（纯函数，好单测）。
///
/// dsh-pocket 的二维码里就是一个普通 URL：
///   - 插件版：http://192.168.1.5:3081  或  https://xxx.trycloudflare.com
///   - CLI 版：http://192.168.1.5:3081/?token=<访问密码>（密码直接内嵌）
/// 本项目两种都认：URL 上带 token 时直接当密码用，省掉手输。
library;

import '../models/connection.dart';

/// 从入口 URL 解析出来的东西。
class ParsedEntry {
  const ParsedEntry({
    required this.baseUrl,
    required this.host,
    required this.isLan,
    this.pin,
  });

  /// 去掉路径 / 查询 / 密码后的入口地址，例如 http://192.168.1.5:3081
  final String baseUrl;
  final String host;

  /// 判断依据只有 host：私网地址 / 单标签机器名 / .local 视为局域网。
  final bool isLan;

  /// URL 里带的 ?token= 或 ?pin=，没有就是 null。
  final String? pin;
}

/// 一次扫码 / 一次粘贴得到的结果：最多两条线路 + 可能仍存在的密码。
class ScannedEntry {
  const ScannedEntry({this.lanUrl, this.publicUrl, this.pin, this.name});

  final String? lanUrl;
  final String? publicUrl;
  final String? pin;
  final String? name;

  bool get isEmpty => lanUrl == null && publicUrl == null;
}

final RegExp _privateV4 = RegExp(
  r'^(?:10\.|192\.168\.|172\.(?:1[6-9]|2\d|3[01])\.|100\.(?:6[4-9]|[7-9]\d|1(?:0\d|1\d|2[0-7]))\.)',
);

/// 是不是「局域网里才通的地址」。
bool isLanHost(String host) {
  final h = host.toLowerCase().replaceAll('[', '').replaceAll(']', '');
  if (h.isEmpty) return false;
  if (h == 'localhost' || h == '::1' || h == '0.0.0.0') return true;
  if (h.endsWith('.local') || h.endsWith('.lan') || h.endsWith('.home.arpa')) {
    return true;
  }
  if (_privateV4.hasMatch(h)) return true;
  if (h.startsWith('169.254.')) return true; // IPv4 link-local
  if (h.startsWith('fe80:') || h.startsWith('fc') || h.startsWith('fd')) return true;
  // 单标签机器名（Windows 的 NetBIOS 名、macOS 的 .local 简写）
  if (!h.contains('.') && !h.contains(':')) return true;
  return false;
}

/// 解析一个入口 URL。认不出（空串、非 http/https、没有 host）就返回 null。
ParsedEntry? parseEntryUrl(String raw) {
  var text = raw.trim();
  if (text.isEmpty) return null;
  // 地址里不该有空白：有就说明是手滑粘了别的东西
  if (RegExp(r'\s').hasMatch(text)) return null;
  if (!text.contains('://')) text = 'http://$text';
  final uri = Uri.tryParse(text);
  if (uri == null) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  if (uri.host.isEmpty) return null;

  final pin = _firstNonEmpty([
    uri.queryParameters['token'],
    uri.queryParameters['pin'],
  ]);

  // 只留 scheme + host + port：路径、查询、fragment 全部丢掉（dsh 的入口就是根路径）
  final base = Uri(
    scheme: uri.scheme,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
  ).toString();

  return ParsedEntry(
    baseUrl: _stripTrailingSlash(base),
    host: uri.host,
    isLan: isLanHost(uri.host),
    pin: pin,
  );
}

/// 扫码结果 → 连接配置。同时支持自定义 scheme：
///   dshpocket://connect?lan=http://192.168.1.5:3081&public=https://x.trycloudflare.com&pin=12345678&name=宿舍电脑
ScannedEntry parseScanned(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return const ScannedEntry();

  final uri = Uri.tryParse(text);
  final scheme = uri?.scheme.toLowerCase();
  if (uri != null && (scheme == 'dshpocket' || scheme == 'dsh-pocket')) {
    final q = uri.queryParameters;
    final pin = _firstNonEmpty([q['pin'], q['token']]);
    final name = _firstNonEmpty([q['name']]);
    final lan = _parseOne(_firstNonEmpty([q['lan'], q['url']]));
    final pub = _parseOne(_firstNonEmpty([q['public'], q['tunnel'], q['wan']]));
    return ScannedEntry(
      lanUrl: lan?.isLan == true ? lan!.baseUrl : null,
      publicUrl: pub == null ? null : (pub.isLan ? null : pub.baseUrl),
      pin: pin ?? lan?.pin ?? pub?.pin,
      name: name,
    );
  }

  final entry = parseEntryUrl(text);
  if (entry == null) return const ScannedEntry();
  return ScannedEntry(
    lanUrl: entry.isLan ? entry.baseUrl : null,
    publicUrl: entry.isLan ? null : entry.baseUrl,
    pin: entry.pin,
  );
}

ParsedEntry? _parseOne(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  return parseEntryUrl(raw);
}

String? _firstNonEmpty(List<String?> values) {
  for (final v in values) {
    if (v != null && v.trim().isNotEmpty) return v.trim();
  }
  return null;
}

String _stripTrailingSlash(String s) =>
    s.endsWith('/') ? s.substring(0, s.length - 1) : s;

/// 拼出真正要打开的地址：根路径 + 可选 ?token= 与 ?dsh-layout=。
///
/// token 交给 dsh-pocket 的代理：它一看到能对上的 token 就种 HttpOnly cookie，
/// 于是手机上「永远不用再输密码」（除非电脑那边重启了 dsh web）。
Uri buildEntryUri(String baseUrl, {String? pin, LayoutPref? layout}) {
  final uri = Uri.parse(baseUrl);
  final query = <String, String>{};
  if (pin != null && pin.trim().isNotEmpty) query['token'] = pin.trim();
  if (layout != null && layout != LayoutPref.auto) {
    query['dsh-layout'] = layout == LayoutPref.mobile ? 'mobile' : 'desktop';
  }
  return uri.replace(path: '/', queryParameters: query.isEmpty ? null : query);
}

