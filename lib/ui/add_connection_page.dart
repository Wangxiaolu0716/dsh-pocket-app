import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../data/entry_url.dart';
import '../models/connection.dart';

/// 添加 / 编辑一台电脑。
class AddConnectionPage extends StatefulWidget {
  const AddConnectionPage({
    super.key,
    required this.controller,
    this.prefill,
    this.editing,
  });

  final AppController controller;
  final ScannedEntry? prefill;
  final Connection? editing;

  @override
  State<AddConnectionPage> createState() => _AddConnectionPageState();
}

class _AddConnectionPageState extends State<AddConnectionPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _lan;
  late final TextEditingController _public;
  late final TextEditingController _pin;

  LinePolicy _policy = LinePolicy.auto;
  LayoutPref _layout = LayoutPref.auto;
  bool _obscurePin = true;
  bool _saving = false;

  bool get _isEditing => widget.editing != null;

  @override
  void initState() {
    super.initState();
    final editing = widget.editing;
    final prefill = widget.prefill;
    final lan = editing?.lanUrl ?? prefill?.lanUrl ?? '';
    final pub = editing?.publicUrl ?? prefill?.publicUrl ?? '';
    _name = TextEditingController(
      text: editing?.name ??
          prefill?.name ??
          _suggestName(lan.isNotEmpty ? lan : pub),
    );
    _lan = TextEditingController(text: lan);
    _public = TextEditingController(text: pub);
    _pin = TextEditingController(text: prefill?.pin ?? '');
    _policy = editing?.policy ?? LinePolicy.auto;
    _layout = editing?.layout ?? widget.controller.defaultLayout;
  }

  @override
  void dispose() {
    _name.dispose();
    _lan.dispose();
    _public.dispose();
    _pin.dispose();
    super.dispose();
  }

  static String _suggestName(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return '我的电脑';
    return uri.host;
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      final lanUrl = _normalize(_lan.text);
      final publicUrl = _normalize(_public.text);
      final pin = _pin.text.trim();
      final id = widget.editing?.id ??
          DateTime.now().microsecondsSinceEpoch.toString();
      final connection = Connection(
        id: id,
        name: _name.text.trim().isEmpty ? _suggestName(lanUrl ?? publicUrl ?? '') : _name.text.trim(),
        lanUrl: lanUrl,
        publicUrl: publicUrl,
        policy: _policy,
        layout: _layout,
      );
      await widget.controller.store.upsert(connection);
      if (pin.isNotEmpty) {
        await widget.controller.store.setPin(id, pin);
      } else if (!_isEditing) {
        await widget.controller.store.setPin(id, null);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// 用户可能粘贴整条含 ?token= 的链接：拆出密码、只留干净的入口地址。
  String? _normalize(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    final parsed = parseEntryUrl(text);
    if (parsed == null) return text;
    if (parsed.pin != null && _pin.text.trim().isEmpty) {
      _pin.text = parsed.pin!;
    }
    return parsed.baseUrl;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? '编辑电脑' : '添加电脑'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? '保存中…' : '保存'),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            TextFormField(
              controller: _name,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: '名称',
                hintText: '宿舍电脑 / 公司台式机',
              ),
            ),
            const SizedBox(height: 20),
            _sectionTitle(context, '入口地址', '两个都填最好：在家自动走局域网，出门自动走公网。'),
            const SizedBox(height: 10),
            TextFormField(
              controller: _lan,
              keyboardType: TextInputType.url,
              autocorrect: false,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: '局域网地址（可选）',
                hintText: 'http://192.168.1.5:3081',
                helperText: '手机电脑连同一个 WiFi 时用这条，快且不费流量',
              ),
              validator: (value) => _validateUrl(value, other: _public.text),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _public,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: '公网地址（可选）',
                hintText: 'https://xxx.trycloudflare.com',
                helperText: '电脑端「开启公网访问」后才有；快速隧道每次重开都会变',
              ),
              validator: (value) => _validateUrl(value, other: _lan.text),
            ),
            const SizedBox(height: 20),
            _sectionTitle(context, '访问密码', '电脑端「设置 → 手机访问」里能看到，也可以自己设固定密码。'),
            const SizedBox(height: 10),
            TextFormField(
              controller: _pin,
              obscureText: _obscurePin,
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: TextInputType.visiblePassword,
              decoration: InputDecoration(
                labelText: '密码',
                hintText: '8 位数字或自定义密码',
                helperText: '存在系统安全存储里；留空的话进页面时再输',
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _obscurePin = !_obscurePin),
                  icon: Icon(_obscurePin
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined),
                ),
              ),
              validator: (value) {
                final text = value?.trim() ?? '';
                if (text.isEmpty) return null;
                if (text.length < 6) return '密码至少 6 位';
                return null;
              },
            ),
            const SizedBox(height: 20),
            _sectionTitle(context, '默认线路', '自动 = 先试局域网，不通再走公网。'),
            const SizedBox(height: 6),
            SegmentedButton<LinePolicy>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: LinePolicy.auto, label: Text('自动')),
                ButtonSegment(value: LinePolicy.lan, label: Text('局域网')),
                ButtonSegment(value: LinePolicy.public, label: Text('公网')),
              ],
              selected: {_policy},
              onSelectionChanged: (value) =>
                  setState(() => _policy = value.first),
            ),
            const SizedBox(height: 20),
            _sectionTitle(context, '界面布局', '窄屏默认就是手机布局；Pad / 折叠屏想用电脑布局可以这里改。'),
            const SizedBox(height: 6),
            SegmentedButton<LayoutPref>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: LayoutPref.auto, label: Text('自动')),
                ButtonSegment(value: LayoutPref.mobile, label: Text('手机')),
                ButtonSegment(value: LayoutPref.desktop, label: Text('电脑')),
              ],
              selected: {_layout},
              onSelectionChanged: (value) =>
                  setState(() => _layout = value.first),
            ),
            const SizedBox(height: 24),
            Text(
              '提示：手机端也能自己在页面里改布局，改完会记住。',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
          ],
        ),
        ),
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String title, String subtitle) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(subtitle,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ],
    );
  }

  String? _validateUrl(String? value, {String? other}) {
    final text = value?.trim() ?? '';
    final otherText = other?.trim() ?? '';
    if (text.isEmpty) {
      if (otherText.isEmpty) return '局域网和公网至少填一个';
      return null;
    }
    if (parseEntryUrl(text) == null) return '看不出这是个地址，示例：http://192.168.1.5:3081';
    return null;
  }
}
