import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/connection_store.dart';
import 'models/connection.dart';

/// 全局状态：设备列表 + 一点用户偏好。够用就好，没上状态管理框架。
class AppController extends ChangeNotifier {
  AppController({
    required this.store,
    required this.themeMode,
    required this.defaultLayout,
  });

  static const _themeKey = 'pref.themeMode';
  static const _layoutKey = 'pref.defaultLayout';

  final ConnectionStore store;

  ThemeMode themeMode;
  LayoutPref defaultLayout;

  static Future<AppController> load() async {
    final store = await ConnectionStore.open();
    final prefs = await SharedPreferences.getInstance();
    return AppController(
      store: store,
      themeMode: _themeFromName(prefs.getString(_themeKey)),
      defaultLayout: _layoutFromName(prefs.getString(_layoutKey)),
    );
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeKey, mode.name);
  }

  Future<void> setDefaultLayout(LayoutPref layout) async {
    defaultLayout = layout;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_layoutKey, layout.name);
  }

  static ThemeMode _themeFromName(String? name) {
    for (final mode in ThemeMode.values) {
      if (mode.name == name) return mode;
    }
    return ThemeMode.system;
  }

  static LayoutPref _layoutFromName(String? name) {
    for (final layout in LayoutPref.values) {
      if (layout.name == name) return layout;
    }
    return LayoutPref.auto;
  }
}
