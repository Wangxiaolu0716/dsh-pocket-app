import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_controller.dart';
import 'system_ui.dart';
import 'theme.dart';
import 'ui/home_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = await AppController.load();
  runApp(DshPocketApp(controller: controller));
}

class DshPocketApp extends StatefulWidget {
  const DshPocketApp({super.key, required this.controller});

  final AppController controller;

  @override
  State<DshPocketApp> createState() => _DshPocketAppState();
}

class _DshPocketAppState extends State<DshPocketApp> with WidgetsBindingObserver {
  Brightness? _applied;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    _syncSystemUi(force: true);
  }

  /// 系统栏配色跟着主题走（透明 → 背景一直铺到屏幕边缘）。
  void _syncSystemUi({bool force = false}) {
    final brightness = switch (widget.controller.themeMode) {
      ThemeMode.dark => Brightness.dark,
      ThemeMode.light => Brightness.light,
      ThemeMode.system =>
        WidgetsBinding.instance.platformDispatcher.platformBrightness,
    };
    if (!force && _applied == brightness) return;
    _applied = brightness;
    applySystemUi(brightness);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        _syncSystemUi();
        return MaterialApp(
          title: 'DSH Pocket',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(Brightness.light),
          darkTheme: buildTheme(Brightness.dark),
          themeMode: widget.controller.themeMode,
          locale: const Locale('zh', 'CN'),
          supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: HomePage(controller: widget.controller),
        );
      },
    );
  }
}
