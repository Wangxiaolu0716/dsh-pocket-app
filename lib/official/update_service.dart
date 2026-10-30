import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'official.dart';

/// 查更新、下载安装包、交给系统安装器。
///
/// 只在发布版里用（`kOfficialBuild`）；源码版直接 git pull 重编，不需要这套。
class UpdateService {
  const UpdateService();

  static bool get canInstallInApp => Platform.isAndroid;

  /// 已安装的 versionCode（= pubspec 的 build number）
  Future<int> installedVersionCode() async {
    final info = await PackageInfo.fromPlatform();
    return int.tryParse(info.buildNumber) ?? 0;
  }

  Future<String> installedVersionName() async {
    final info = await PackageInfo.fromPlatform();
    return info.version;
  }

  /// 有更新的版本就返回它，否则 null。
  Future<UpdateInfo?> check() async {
    final latest = await const OfficialApi().fetchUpdateManifest();
    if (latest == null) return null;
    final installed = await installedVersionCode();
    if (!latest.isNewerThan(installed)) return null;
    return latest;
  }

  /// 下载到缓存目录（open_filex 的 FileProvider 覆盖这里，系统安装器才拿得到）。
  Future<File> download(
    UpdateInfo update, {
    void Function(double progress)? onProgress,
  }) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/dsh-pocket-${update.versionName}.apk');
    if (await file.exists()) await file.delete();

    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(update.apkUrl));
      final response = await client.send(request).timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw HttpException('下载失败：HTTP ${response.statusCode}');
      }
      final total = response.contentLength ?? update.sizeBytes ?? 0;
      final sink = file.openWrite();
      var received = 0;
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress?.call(received / total);
      }
      await sink.flush();
      await sink.close();

      if (update.hasChecksum) {
        final digest = sha256.convert(await file.readAsBytes()).toString();
        if (digest.toLowerCase() != update.sha256!.trim().toLowerCase()) {
          await file.delete();
          throw const HttpException('安装包校验失败，请重新下载');
        }
      }
      onProgress?.call(1);
      return file;
    } catch (error) {
      if (await file.exists()) await file.delete();
      debugPrint('下载更新失败：$error');
      rethrow;
    } finally {
      client.close();
    }
  }

  /// 交给系统安装器。第一次会跳「允许安装未知应用」，属正常流程。
  Future<void> install(File apk) async {
    final result = await OpenFilex.open(apk.path);
    if (result.type != ResultType.done) {
      throw Exception(result.message.isEmpty ? '打不开安装器' : result.message);
    }
  }
}
