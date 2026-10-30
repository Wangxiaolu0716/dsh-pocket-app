/// 只在**发布版**（`--dart-define=OFFICIAL=true`）里生效的东西：
/// 更新检查、服务器公告、赞赏入口。
///
/// 从源码自己构建的版本（GitHub 上直接 clone 出来的）不会带这些：
/// 公告内容和收款码都不进仓库、不进源码版 APK，服务器上也只放
/// 两个 JSON 和一个 APK，没有任何源码。
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

const bool kOfficialBuild = bool.fromEnvironment('OFFICIAL', defaultValue: false);

/// 服务器上的静态目录（nginx 直出，没有后端、没有源码）
const String kServerBase = 'https://xuhuohua.xyz/dsh-pocket';
const String kUpdateManifestUrl = '$kServerBase/update.json';
const String kAnnouncementUrl = '$kServerBase/announcement.json';

/// 服务器上的更新清单。
class UpdateInfo {
  const UpdateInfo({
    required this.versionCode,
    required this.versionName,
    required this.apkUrl,
    this.force = false,
    this.notes = '',
    this.sizeBytes,
    this.sha256,
    this.mirrors = const [],
  });

  final int versionCode;
  final String versionName;
  final String apkUrl;
  final bool force;
  final String notes;
  final int? sizeBytes;
  final String? sha256;

  /// 备用下载地址（GitHub Release / 网盘）。服务器带宽小时用户能换条路。
  final List<String> mirrors;

  bool isNewerThan(int installedCode) => versionCode > installedCode;
  bool get hasChecksum => (sha256 ?? '').trim().isNotEmpty;

  String get sizeText {
    final bytes = sizeBytes;
    if (bytes == null || bytes <= 0) return '';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  /// 清单写错不该让 App 崩，一律当成「没有更新」。
  static UpdateInfo? tryParse(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) return null;
      final versionCode = decoded['versionCode'];
      final versionName = decoded['versionName'];
      final apkUrl = decoded['apkUrl'];
      if (versionCode is! int || versionName is! String || apkUrl is! String) {
        return null;
      }
      if (versionName.trim().isEmpty || apkUrl.trim().isEmpty) return null;
      final mirrors = <String>[];
      final rawMirrors = decoded['mirrors'];
      if (rawMirrors is List) {
        for (final item in rawMirrors) {
          if (item is String && item.trim().isNotEmpty) mirrors.add(item.trim());
        }
      }
      return UpdateInfo(
        versionCode: versionCode,
        versionName: versionName.trim(),
        apkUrl: apkUrl.trim(),
        force: decoded['force'] == true,
        notes: decoded['notes'] is String ? decoded['notes'] as String : '',
        sizeBytes: decoded['sizeBytes'] is int ? decoded['sizeBytes'] as int : null,
        sha256: decoded['sha256'] is String ? decoded['sha256'] as String : null,
        mirrors: mirrors,
      );
    } catch (_) {
      return null;
    }
  }
}

/// 一条服务器公告。
class Announcement {
  const Announcement({
    required this.id,
    required this.title,
    required this.content,
    this.createdAt,
    this.url,
  });

  final String id;
  final String title;
  final String content;
  final String? createdAt;

  /// 可选的外链（比如更新日志页面）
  final String? url;

  /// 服务器格式：{"announcements":[{id,title,content,createdAt,updatedAt,url}]}
  static List<Announcement> parseList(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) return const [];
      final items = decoded['announcements'];
      if (items is! List) return const [];
      final out = <Announcement>[];
      for (final item in items) {
        if (item is! Map) continue;
        final id = item['id'];
        final title = item['title'];
        final content = item['content'];
        if (id is! String || title is! String || content is! String) continue;
        if (title.trim().isEmpty) continue;
        out.add(
          Announcement(
            id: id,
            title: title.trim(),
            content: content,
            createdAt: item['createdAt'] is String ? item['createdAt'] as String : null,
            url: item['url'] is String && (item['url'] as String).trim().isNotEmpty
                ? (item['url'] as String).trim()
                : null,
          ),
        );
      }
      return out;
    } catch (_) {
      return const [];
    }
  }
}

/// 服务器交互：只读两个静态 JSON，失败一律静默（网络问题不该影响连电脑）。
class OfficialApi {
  const OfficialApi();

  static const Duration _timeout = Duration(seconds: 12);

  Future<UpdateInfo?> fetchUpdateManifest() async {
    final body = await _get(kUpdateManifestUrl);
    return body == null ? null : UpdateInfo.tryParse(body);
  }

  Future<List<Announcement>> fetchAnnouncements() async {
    final body = await _get(kAnnouncementUrl);
    return body == null ? const [] : Announcement.parseList(body);
  }

  Future<String?> _get(String url) async {
    try {
      final response = await http.get(Uri.parse(url)).timeout(_timeout);
      if (response.statusCode != 200) return null;
      // 中文内容必须按 UTF-8 解码，不能依赖响应头
      return utf8.decode(response.bodyBytes);
    } catch (_) {
      return null;
    }
  }
}
