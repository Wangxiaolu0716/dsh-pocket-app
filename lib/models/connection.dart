/// 一台电脑（一个 DSH Pocket 入口）的配置。
///
/// 一条连接可以同时有「局域网」和「公网」两条线路：
///   - 局域网：http://<电脑IP>:3081（同一 WiFi 时才通）
///   - 公网：  https://xxx.trycloudflare.com（人不在家时用）
/// 访问密码（PIN）不入库，存在系统安全存储里，见 data/secret_store.dart。
library;

/// 线路偏好：自动 = 先试局域网、不通再走公网。
enum LinePolicy { auto, lan, public }

/// 布局偏好：auto 由 dsh-pocket 按屏幕宽度自己判断。
enum LayoutPref { auto, mobile, desktop }

class Connection {
  const Connection({
    required this.id,
    required this.name,
    this.lanUrl,
    this.publicUrl,
    this.policy = LinePolicy.auto,
    this.layout = LayoutPref.auto,
    this.lastUsedAt,
    this.lastLine,
  });

  final String id;
  final String name;

  /// 局域网入口，形如 http://192.168.1.5:3081（不带路径、不带密码）。
  final String? lanUrl;

  /// 公网入口，形如 https://xxx.trycloudflare.com。
  final String? publicUrl;

  final LinePolicy policy;
  final LayoutPref layout;
  final DateTime? lastUsedAt;

  /// 上次连通的线路，首页用来提示「上次走公网」。
  final LinePolicy? lastLine;

  bool get hasLan => lanUrl != null && lanUrl!.isNotEmpty;
  bool get hasPublic => publicUrl != null && publicUrl!.isNotEmpty;
  bool get isEmpty => !hasLan && !hasPublic;

  /// 按偏好排出的待试线路（最多两条）。
  List<ConnectionLine> orderedLines() {
    final lan = hasLan ? ConnectionLine(LinePolicy.lan, lanUrl!) : null;
    final pub = hasPublic ? ConnectionLine(LinePolicy.public, publicUrl!) : null;
    switch (policy) {
      case LinePolicy.lan:
        return [?lan, ?pub];
      case LinePolicy.public:
        return [?pub, ?lan];
      case LinePolicy.auto:
        return [?lan, ?pub];
    }
  }

  Connection copyWith({
    String? name,
    String? lanUrl,
    String? publicUrl,
    bool clearLan = false,
    bool clearPublic = false,
    LinePolicy? policy,
    LayoutPref? layout,
    DateTime? lastUsedAt,
    LinePolicy? lastLine,
  }) {
    return Connection(
      id: id,
      name: name ?? this.name,
      lanUrl: clearLan ? null : (lanUrl ?? this.lanUrl),
      publicUrl: clearPublic ? null : (publicUrl ?? this.publicUrl),
      policy: policy ?? this.policy,
      layout: layout ?? this.layout,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      lastLine: lastLine ?? this.lastLine,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'lanUrl': lanUrl,
        'publicUrl': publicUrl,
        'policy': policy.name,
        'layout': layout.name,
        'lastUsedAt': lastUsedAt?.toIso8601String(),
        'lastLine': lastLine?.name,
      };

  static Connection fromJson(Map<String, Object?> json) {
    return Connection(
      id: json['id'] as String,
      name: (json['name'] as String?)?.trim().isNotEmpty == true
          ? json['name'] as String
          : '未命名',
      lanUrl: _str(json['lanUrl']),
      publicUrl: _str(json['publicUrl']),
      policy: _enum(LinePolicy.values, json['policy'], LinePolicy.auto),
      layout: _enum(LayoutPref.values, json['layout'], LayoutPref.auto),
      lastUsedAt: DateTime.tryParse(_str(json['lastUsedAt']) ?? ''),
      lastLine: json['lastLine'] == null
          ? null
          : _enum(LinePolicy.values, json['lastLine'], LinePolicy.auto),
    );
  }

  static String? _str(Object? v) {
    if (v is! String) return null;
    final t = v.trim();
    return t.isEmpty ? null : t;
  }

  static T _enum<T extends Enum>(List<T> values, Object? raw, T fallback) {
    if (raw is String) {
      for (final v in values) {
        if (v.name == raw) return v;
      }
    }
    return fallback;
  }
}

/// 一条线路 = 偏好 + 入口地址。
class ConnectionLine {
  const ConnectionLine(this.kind, this.baseUrl);
  final LinePolicy kind;
  final String baseUrl;

  String get label => kind == LinePolicy.lan ? '局域网' : '公网';
}
