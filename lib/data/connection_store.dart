import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/connection.dart';
import 'secret_store.dart';

/// 设备（电脑）列表的持久化。列表本身是明文 JSON，访问密码单独进安全存储。
class ConnectionStore extends ChangeNotifier {
  ConnectionStore._(this._prefs, this._secrets, this._items);

  static const _listKey = 'connections.v1';

  final SharedPreferences _prefs;
  final SecretStore _secrets;
  final List<Connection> _items;

  static Future<ConnectionStore> open() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_listKey);
    final items = <Connection>[];
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map) {
              items.add(Connection.fromJson(Map<String, Object?>.from(item)));
            }
          }
        }
      } catch (error) {
        debugPrint('连接列表损坏，已忽略：$error');
      }
    }
    return ConnectionStore._(prefs, SecretStore(prefs), items);
  }

  List<Connection> get connections => List.unmodifiable(_items);

  Connection? byId(String id) {
    for (final item in _items) {
      if (item.id == id) return item;
    }
    return null;
  }

  Future<void> upsert(Connection connection) async {
    final index = _items.indexWhere((item) => item.id == connection.id);
    if (index >= 0) {
      _items[index] = connection;
    } else {
      _items.insert(0, connection);
    }
    await _flush();
  }

  Future<void> remove(String id) async {
    _items.removeWhere((item) => item.id == id);
    await _secrets.delete(_pinKey(id));
    await _flush();
  }

  /// 最近用过的排前面。
  Future<void> touch(String id, {LinePolicy? line}) async {
    final index = _items.indexWhere((item) => item.id == id);
    if (index < 0) return;
    _items[index] = _items[index].copyWith(
      lastUsedAt: DateTime.now(),
      lastLine: line,
    );
    await _flush();
  }

  Future<String?> pin(String id) => _secrets.read(_pinKey(id));

  Future<void> setPin(String id, String? pin) async {
    if (pin == null || pin.trim().isEmpty) {
      await _secrets.delete(_pinKey(id));
      return;
    }
    await _secrets.write(_pinKey(id), pin.trim());
  }

  Future<void> clearAll() async {
    for (final item in _items) {
      await _secrets.delete(_pinKey(item.id));
    }
    _items.clear();
    await _flush();
  }

  String _pinKey(String id) => 'pin.$id';

  Future<void> _flush() async {
    await _prefs.setString(
      _listKey,
      jsonEncode(_items.map((item) => item.toJson()).toList()),
    );
    notifyListeners();
  }
}
