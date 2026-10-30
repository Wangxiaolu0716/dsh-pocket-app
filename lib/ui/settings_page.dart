import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_controller.dart';
import '../app_info.dart';
import '../models/connection.dart';
import '../official/official.dart';
import '../official/official_ui.dart';

/// 设置：主题、默认布局、出处、清空数据。
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  AppController get _app => widget.controller;

  Future<void> _open(String url) async {
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('打不开这个链接')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: SafeArea(
        top: false,
        child: ListView(
        children: [
          _header(context, '外观'),
          RadioGroup<ThemeMode>(
            groupValue: _app.themeMode,
            onChanged: (mode) {
              if (mode != null) _app.setThemeMode(mode);
            },
            child: const Column(
              children: [
                RadioListTile<ThemeMode>(
                  value: ThemeMode.system,
                  title: Text('跟随系统'),
                ),
                RadioListTile<ThemeMode>(
                  value: ThemeMode.dark,
                  title: Text('深色'),
                ),
                RadioListTile<ThemeMode>(
                  value: ThemeMode.light,
                  title: Text('浅色'),
                ),
              ],
            ),
          ),
          _header(context, '新设备默认界面布局'),
          RadioGroup<LayoutPref>(
            groupValue: _app.defaultLayout,
            onChanged: (layout) {
              if (layout != null) _app.setDefaultLayout(layout);
            },
            child: const Column(
              children: [
                RadioListTile<LayoutPref>(
                  value: LayoutPref.auto,
                  title: Text('自动'),
                  subtitle: Text('窄屏用手机布局，宽屏用电脑布局'),
                ),
                RadioListTile<LayoutPref>(
                  value: LayoutPref.mobile,
                  title: Text('手机布局'),
                ),
                RadioListTile<LayoutPref>(
                  value: LayoutPref.desktop,
                  title: Text('电脑布局'),
                ),
              ],
            ),
          ),
          _header(context, '关于'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('版本'),
            subtitle: const Text(kAppVersion),
          ),
          ListTile(
            leading: const Icon(Icons.phone_iphone),
            title: const Text('电脑端要装的东西'),
            subtitle: const Text('dsh-pocket 插件：npm 装完重启 dsh web'),
            trailing: const Icon(Icons.open_in_new, size: 16),
            onTap: () => _open(kUpstreamUrl),
          ),
          ListTile(
            leading: const Icon(Icons.code),
            title: const Text('这个 App 的源码'),
            subtitle: const Text('欢迎提 issue'),
            trailing: const Icon(Icons.open_in_new, size: 16),
            onTap: () => _open(kRepoUrl),
          ),
          if (kOfficialBuild) ...[
            _header(context, '发布版'),
            ListTile(
              leading: const Icon(Icons.system_update_alt),
              title: const Text('检查更新'),
              subtitle: const Text('从更新服务器拉最新版本'),
              onTap: () => checkForUpdate(context, silent: true),
            ),
            ListTile(
              leading: const Icon(Icons.favorite_border),
              title: const Text('请作者喝杯奶茶'),
              subtitle: const Text('微信扫码赞赏，金额随意'),
              onTap: () => showRewardSheet(context),
            ),
          ],
          _header(context, '安全提示'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              '手机上的访问密码存在系统安全存储里（Android Keystore / iOS 钥匙串）。'
              'DSH 能在电脑上执行代码，这串密码等同于电脑的钥匙：别把二维码、'
              '链接或密码发给别人，公网用完就关。',
              style: theme.textTheme.bodySmall?.copyWith(height: 1.6),
            ),
          ),
          _header(context, '危险操作'),
          ListTile(
            leading: Icon(Icons.delete_sweep_outlined,
                color: theme.colorScheme.error),
            title: Text('清空所有电脑和密码',
                style: TextStyle(color: theme.colorScheme.error)),
            onTap: _confirmClearAll,
          ),
          const SizedBox(height: 24),
        ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context, String text) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
      child: Text(
        text,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Future<void> _confirmClearAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空所有配置？'),
        content: const Text('手机里保存的地址和访问密码都会删掉（电脑上的 dsh-pocket 不受影响）。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _app.store.clearAll();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已清空')));
  }
}
