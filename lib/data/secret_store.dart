import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 访问密码的存放处。
///
/// 优先走系统安全存储（Android Keystore / iOS Keychain）；某些机器上 Keystore
/// 会抽风（root 过、刷过机、或厂商 ROM 有 bug），这时静默退回
/// SharedPreferences——它是 App 私有目录，没 root 的机器上别人也读不到。
/// 宁可降级也不要把密码丢了：丢了就得回电脑前重看一次。
class SecretStore {
  SecretStore(this._prefs);

  final SharedPreferences _prefs;
  static const _storage = FlutterSecureStorage();

  String _fallbackKey(String key) => 'secret.$key';

  Future<String?> read(String key) async {
    try {
      final value = await _storage.read(key: key);
      if (value != null && value.isNotEmpty) return value;
    } catch (_) {
      // 安全存储不可用，走下面的兜底
    }
    return _prefs.getString(_fallbackKey(key));
  }

  Future<void> write(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
      await _prefs.remove(_fallbackKey(key));
      return;
    } catch (_) {
      // 写不进安全存储，落兜底
    }
    await _prefs.setString(_fallbackKey(key), value);
  }

  Future<void> delete(String key) async {
    try {
      await _storage.delete(key: key);
    } catch (_) {
      // 忽略：兜底那份下面会删
    }
    await _prefs.remove(_fallbackKey(key));
  }
}
