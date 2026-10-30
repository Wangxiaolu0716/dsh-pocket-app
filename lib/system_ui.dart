import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 系统栏配色：让状态栏 / 底部导航栏都透明，界面背景一直铺到屏幕边缘。
///
/// 为什么这么做：
///   - Android 15 起系统强制 edge-to-edge，躺着不改反而会出现一条突兀的
///     系统栏色带（特别是底部手势条那块）
///   - 透明之后，页面背景（深色 #0B0D12）就是那块区域的颜色，
///     视觉上「满屏」，不会有一条比上面浅或深的横条
///   - 图标明暗跟着主题走，浅色主题下用深色图标，避免白底白图标
void applySystemUi(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final iconBrightness = isDark ? Brightness.light : Brightness.dark;

  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: iconBrightness, // Android
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light, // iOS
      systemStatusBarContrastEnforced: false,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarIconBrightness: iconBrightness,
      systemNavigationBarContrastEnforced: false,
    ),
  );
}
