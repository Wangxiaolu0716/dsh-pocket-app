import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'official.dart';
import 'update_service.dart';

/// 发布版专属界面：检查更新、服务器公告、赞赏入口。

const String _ignoredVersionKey = 'official.ignoredUpdateVersion';
const String _seenAnnouncementKey = 'official.seenAnnouncements';

Future<void> _openExternal(String url) async {
  await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
}

// ---------------------------------------------------------------- 检查更新

/// 查一次更新。[silent] = 用户主动点了「检查更新」，没有更新时也给个反馈。
Future<void> checkForUpdate(BuildContext context, {bool silent = false}) async {
  if (!kOfficialBuild) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('源码版不走服务器更新：git pull 后重新构建即可')),
    );
    return;
  }

  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context, rootNavigator: true);

  UpdateInfo? info;
  try {
    info = await const UpdateService().check();
  } catch (_) {
    info = null;
  }
  if (!context.mounted) return;

  if (info == null) {
    if (silent) {
      messenger.showSnackBar(const SnackBar(content: Text('已经是最新版本')));
    }
    return;
  }

  final prefs = await SharedPreferences.getInstance();
  final ignored = prefs.getInt(_ignoredVersionKey) ?? 0;
  if (!info.force && info.versionCode <= ignored) return;
  if (!context.mounted) return;

  await showDialog<void>(
    context: context,
    barrierDismissible: !info.force,
    builder: (context) => _UpdateDialog(
      info: info!,
      onIgnore: () async {
        await prefs.setInt(_ignoredVersionKey, info!.versionCode);
        if (navigator.canPop()) navigator.pop();
      },
    ),
  );
}

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({required this.info, required this.onIgnore});

  final UpdateInfo info;
  final Future<void> Function() onIgnore;

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  double _progress = 0;
  bool _downloading = false;
  String? _error;

  Future<void> _start() async {
    final info = widget.info;
    if (!UpdateService.canInstallInApp) {
      // iOS 装不了 APK：把下载页丢给浏览器，让人自己走 TestFlight / 重签
      await _openExternal(info.mirrors.isNotEmpty ? info.mirrors.first : info.apkUrl);
      return;
    }
    setState(() {
      _downloading = true;
      _error = null;
      _progress = 0;
    });
    try {
      final file = await const UpdateService().download(
        info,
        onProgress: (value) {
          if (mounted) setState(() => _progress = value);
        },
      );
      await const UpdateService().install(file);
      if (mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _error = '下载或安装失败：$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final info = widget.info;
    final canInstall = UpdateService.canInstallInApp;

    return AlertDialog(
      title: Text('发现新版本 v${info.versionName}'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              [
                if (info.sizeText.isNotEmpty) info.sizeText,
                if (info.force) '必须更新后才能继续使用',
              ].join(' · '),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            if (info.notes.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(info.notes.trim(), style: theme.textTheme.bodyMedium),
            ],
            if (_downloading) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(value: _progress > 0 ? _progress : null),
              const SizedBox(height: 6),
              Text('正在下载 ${(_progress * 100).toStringAsFixed(0)}%',
                  style: theme.textTheme.labelSmall),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final url in [info.apkUrl, ...info.mirrors])
                    TextButton(
                      onPressed: () => _openExternal(url),
                      child: Text(Uri.tryParse(url)?.host ?? '打开下载页'),
                    ),
                ],
              ),
            ],
            if (!canInstall) ...[
              const SizedBox(height: 12),
              Text(
                'iOS 版没法在 App 内装包：点下面按钮去下载页，用 TestFlight / 重签包更新。',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (!info.force)
          TextButton(
            onPressed: _downloading ? null : () => widget.onIgnore(),
            child: const Text('稍后'),
          ),
        FilledButton(
          onPressed: _downloading ? null : _start,
          child: Text(canInstall ? '下载并安装' : '打开下载页'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- 公告

/// 从服务器拉公告（发布版才有；失败静默返回空）。
Future<List<Announcement>> loadAnnouncements() async {
  if (!kOfficialBuild) return const [];
  return const OfficialApi().fetchAnnouncements();
}

/// 横幅：首页顶部一条，看过就记下 id 不再打扰。
class AnnouncementBanner extends StatefulWidget {
  const AnnouncementBanner({super.key, required this.announcement});

  final Announcement announcement;

  @override
  State<AnnouncementBanner> createState() => _AnnouncementBannerState();
}

class _AnnouncementBannerState extends State<AnnouncementBanner> {
  bool _closed = false;

  Future<void> _markSeen() async {
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getStringList(_seenAnnouncementKey) ?? <String>[];
    if (!seen.contains(widget.announcement.id)) {
      seen.add(widget.announcement.id);
      // 只留最近 20 条，别让偏好文件无限长
      final trimmed = seen.length > 20 ? seen.sublist(seen.length - 20) : seen;
      await prefs.setStringList(_seenAnnouncementKey, trimmed);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_closed) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => showAnnouncementDialog(context, widget.announcement),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.campaign_outlined,
                    size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.announcement.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        widget.announcement.content.replaceAll('\n', ' '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '不再提示',
                  iconSize: 18,
                  onPressed: () async {
                    await _markSeen();
                    if (mounted) setState(() => _closed = true);
                  },
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> showAnnouncementDialog(
  BuildContext context,
  Announcement announcement,
) async {
  final prefs = await SharedPreferences.getInstance();
  final seen = prefs.getStringList(_seenAnnouncementKey) ?? <String>[];
  if (!seen.contains(announcement.id)) {
    seen.add(announcement.id);
    final trimmed = seen.length > 20 ? seen.sublist(seen.length - 20) : seen;
    await prefs.setStringList(_seenAnnouncementKey, trimmed);
  }
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(announcement.title),
      content: SingleChildScrollView(
        child: Text(announcement.content, style: const TextStyle(height: 1.6)),
      ),
      actions: [
        if (announcement.url != null)
          TextButton(
            onPressed: () => _openExternal(announcement.url!),
            child: const Text('打开链接'),
          ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('知道了'),
        ),
      ],
    ),
  );
}

/// 最近一条还没看过的公告；没有就返回 null。
Future<Announcement?> unreadAnnouncement(List<Announcement> items) async {
  if (items.isEmpty) return null;
  final prefs = await SharedPreferences.getInstance();
  final seen = prefs.getStringList(_seenAnnouncementKey) ?? <String>[];
  for (final item in items) {
    if (!seen.contains(item.id)) return item;
  }
  return null;
}

// ---------------------------------------------------------------- 赞赏

/// 赞赏码。图片只在发布版里（tools/publish_server.ps1 打包时才把收款码放进 assets/），
/// 源码仓库里它只出现在 README，不进 APK。
Future<void> showRewardSheet(BuildContext context) async {
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) {
      final theme = Theme.of(context);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('请作者喝杯奶茶',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(
                '微信扫码赞赏，金额随意。用着顺手就支持一下，谢谢！',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              // 收款码原始比例 1118x1524（≈0.734），必须按比例显示，别拉伸
              Flexible(
                child: AspectRatio(
                  aspectRatio: 1118 / 1524,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.asset(
                      'assets/reward_qr.png',
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stack) => ColoredBox(
                        color: theme.colorScheme.surfaceContainerHighest,
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              '这个版本没带收款码\n（源码版请见 README 里的赞赏章节）',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('关闭'),
              ),
            ],
          ),
        ),
      );
    },
  );
}
