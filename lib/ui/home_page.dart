import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_controller.dart';
import '../data/entry_url.dart' as entry;
import '../data/probe.dart';
import '../models/connection.dart';
import 'add_connection_page.dart';
import 'connection_page.dart';
import 'scan_page.dart';
import 'settings_page.dart';
import 'widgets.dart';

/// 首页：设备列表 + 每条线路的实时连通状态。
class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.controller});

  final AppController controller;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  /// connectionId -> (线路 -> 探测结果)
  final Map<String, Map<LinePolicy, ProbeResult>> _probes = {};
  bool _probing = false;

  AppController get _app => widget.controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _app.store.addListener(_onStoreChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _probeAll());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _app.store.removeListener(_onStoreChanged);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _probeAll();
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _probeAll() async {
    if (_probing) return;
    _probing = true;
    try {
      final connections = _app.store.connections;
      final results = await Future.wait(
        connections.map((connection) async {
          final lines = <LinePolicy, ProbeResult>{};
          await Future.wait(connection.orderedLines().map((line) async {
            lines[line.kind] = await httpProbe(line.baseUrl);
          }));
          return MapEntry(connection.id, lines);
        }),
      );
      if (!mounted) return;
      setState(() {
        _probes
          ..clear()
          ..addEntries(results);
      });
    } finally {
      _probing = false;
    }
  }

  ProbeDotState _dotFor(Connection connection, LinePolicy kind) {
    final result = _probes[connection.id]?[kind];
    if (result == null) return ProbeDotState.unknown;
    return result.reachable ? ProbeDotState.online : ProbeDotState.offline;
  }

  Future<void> _openAdd() async {
    final mode = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.qr_code_scanner),
              title: const Text('扫码添加'),
              subtitle: const Text('电脑端：设置 → 手机访问 → 扫二维码'),
              onTap: () => Navigator.pop(context, 'scan'),
            ),
            ListTile(
              leading: const Icon(Icons.keyboard_alt_outlined),
              title: const Text('手动输入地址'),
              subtitle: const Text('http://192.168.1.5:3081 或公网域名'),
              onTap: () => Navigator.pop(context, 'manual'),
            ),
            ListTile(
              leading: const Icon(Icons.content_paste_go),
              title: const Text('粘贴剪贴板里的链接'),
              onTap: () => Navigator.pop(context, 'paste'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || mode == null) return;

    if (mode == 'scan') {
      final raw = await Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (_) => const ScanPage()),
      );
      if (!mounted || raw == null) return;
      await _openAddPage(entry.parseScanned(raw));
      return;
    }

    if (mode == 'paste') {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim() ?? '';
      if (!mounted) return;
      if (text.isEmpty) {
        _toast('剪贴板是空的');
        return;
      }
      final scanned = entry.parseScanned(text);
      if (scanned.isEmpty) {
        _toast('剪贴板里没有可用的地址');
        return;
      }
      await _openAddPage(scanned);
      return;
    }

    await _openAddPage(null);
  }

  Future<void> _openAddPage(entry.ScannedEntry? prefill, {Connection? editing}) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AddConnectionPage(
          controller: _app,
          prefill: prefill,
          editing: editing,
        ),
      ),
    );
    if (saved == true) _probeAll();
  }

  Future<void> _connect(Connection connection) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ConnectionPage(controller: _app, connection: connection),
      ),
    );
    if (mounted) _probeAll();
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final connections = _app.store.connections;

    return Scaffold(
      appBar: AppBar(
        title: const Text('DSH Pocket'),
        actions: [
          IconButton(
            tooltip: '刷新状态',
            onPressed: _probing ? null : _probeAll,
            icon: _probing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: '设置',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => SettingsPage(controller: _app),
              ),
            ),
            icon: const Icon(Icons.settings_outlined),
          ),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: connections.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _openAdd,
              icon: const Icon(Icons.add),
              label: const Text('添加电脑'),
            ),
      body: SafeArea(
        top: false,
        child: connections.isEmpty
            ? _EmptyState(onAdd: _openAdd)
            : RefreshIndicator(
                onRefresh: _probeAll,
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  itemCount: connections.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final connection = connections[index];
                    return _ConnectionCard(
                      connection: connection,
                      dotFor: (kind) => _dotFor(connection, kind),
                      onTap: () => _connect(connection),
                      onEdit: () => _openAddPage(null, editing: connection),
                      onDelete: () => _confirmDelete(connection),
                    );
                  },
                ),
              ),
      ),
    );
  }

  Future<void> _confirmDelete(Connection connection) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除「${connection.name}」？'),
        content: const Text('只删除手机里的这条配置，电脑上的 dsh-pocket 不受影响。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _app.store.remove(connection.id);
    _probes.remove(connection.id);
    if (mounted) setState(() {});
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.qr_code_scanner,
                size: 56, color: theme.colorScheme.primary),
            const SizedBox(height: 18),
            Text('把电脑上的 DSH 装进口袋',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Text(
              '电脑上装好 dsh-pocket 并重启 dsh web 后，打开 设置 → 手机访问，'
              '扫一下二维码就能在手机上用同一套界面。',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('扫码添加'),
            ),
            const SizedBox(height: 10),
            Text(
              '同一个 WiFi 走局域网；人在外面就走公网隧道（公网地址每次重开都会变，'
              '想固定地址用命名隧道）。',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({
    required this.connection,
    required this.dotFor,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  final Connection connection;
  final ProbeDotState Function(LinePolicy) dotFor;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.computer, size: 20, color: theme.colorScheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      connection.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: '更多',
                    icon: const Icon(Icons.more_horiz, size: 20),
                    onSelected: (value) {
                      if (value == 'edit') onEdit();
                      if (value == 'delete') onDelete();
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 'edit', child: Text('编辑')),
                      PopupMenuItem(value: 'delete', child: Text('删除')),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (connection.hasLan)
                      LineChip(
                        label: '局域网',
                        address: _addressOf(connection.lanUrl!),
                        state: dotFor(LinePolicy.lan),
                      ),
                    if (connection.hasPublic)
                      LineChip(
                        label: '公网',
                        address: _addressOf(connection.publicUrl!),
                        state: dotFor(LinePolicy.public),
                      ),
                  ],
                ),
              ),
              if (connection.lastUsedAt != null) ...[
                const SizedBox(height: 8),
                Text(
                  '上次连接：${_relativeTime(connection.lastUsedAt!)}'
                  '${connection.lastLine == null ? '' : ' · ${connection.lastLine == LinePolicy.lan ? '局域网' : '公网'}'}',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: theme.colorScheme.outline),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 只显示 host:port，完整地址在连接页/编辑页里看
  static String _addressOf(String url) {
    final parsed = Uri.tryParse(url);
    if (parsed == null) return url;
    return parsed.hasPort ? '${parsed.host}:${parsed.port}' : parsed.host;
  }

  static String _relativeTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
    if (diff.inHours < 24) return '${diff.inHours} 小时前';
    return '${diff.inDays} 天前';
  }
}
