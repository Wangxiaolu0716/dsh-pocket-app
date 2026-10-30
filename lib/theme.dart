import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 和 DeepSeek Harness 界面同一套观感：近黑底色 + 蓝色主色。
const Color dshSeed = Color(0xFF4D6BFE);
const Color dshDarkBg = Color(0xFF0B0D12);
const Color dshDarkSurface = Color(0xFF14171F);
const Color dshOnline = Color(0xFF3DD68C);
const Color dshOffline = Color(0xFFEB5757);

ThemeData buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: dshSeed,
    brightness: brightness,
  );
  final isDark = brightness == Brightness.dark;
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme.copyWith(
      surface: isDark ? dshDarkSurface : scheme.surface,
    ),
    scaffoldBackgroundColor: isDark ? dshDarkBg : scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: isDark ? dshDarkBg : scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      // 默认的 AppBar 会把系统导航栏刷成不透明黑，底部就会多一条色带；
      // 统一成透明，配合 edge-to-edge 界面才能真正铺满
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
        systemStatusBarContrastEnforced: false,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        systemNavigationBarContrastEnforced: false,
      ),
      titleTextStyle: TextStyle(
        color: scheme.onSurface,
        fontSize: 17,
        fontWeight: FontWeight.w600,
      ),
    ),
    cardTheme: CardThemeData(
      color: isDark ? dshDarkSurface : scheme.surfaceContainerLow,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isDark ? const Color(0xFF232733) : scheme.outlineVariant,
        ),
      ),
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 16),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: isDark ? const Color(0xFF191D26) : scheme.surfaceContainerHighest,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      isDense: true,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: isDark ? const Color(0xFF232733) : null,
    ),
  );
}
