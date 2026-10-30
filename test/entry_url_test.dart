import 'package:dsh_pocket/data/entry_url.dart';
import 'package:dsh_pocket/models/connection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseEntryUrl', () {
    test('局域网地址带端口', () {
      final parsed = parseEntryUrl('http://192.168.1.5:3081');
      expect(parsed, isNotNull);
      expect(parsed!.baseUrl, 'http://192.168.1.5:3081');
      expect(parsed.isLan, isTrue);
      expect(parsed.pin, isNull);
    });

    test('没写协议也能认', () {
      final parsed = parseEntryUrl('192.168.1.5:3081');
      expect(parsed!.baseUrl, 'http://192.168.1.5:3081');
    });

    test('CLI 版二维码里带 token', () {
      final parsed = parseEntryUrl('http://192.168.1.5:3081/?token=12345678');
      expect(parsed!.pin, '12345678');
      expect(parsed.baseUrl, 'http://192.168.1.5:3081');
    });

    test('公网隧道地址判成公网', () {
      final parsed = parseEntryUrl('https://sweet-fox-abc.trycloudflare.com');
      expect(parsed!.isLan, isFalse);
      expect(parsed.baseUrl, 'https://sweet-fox-abc.trycloudflare.com');
    });

    test('路径和查询都丢掉，只留入口', () {
      final parsed = parseEntryUrl('https://pocket.example.com/some/path?a=1#x');
      expect(parsed!.baseUrl, 'https://pocket.example.com');
    });

    test('乱写的不认', () {
      expect(parseEntryUrl(''), isNull);
      expect(parseEntryUrl('hello world'), isNull);
    });
  });

  group('isLanHost', () {
    test('私网网段', () {
      expect(isLanHost('10.0.0.2'), isTrue);
      expect(isLanHost('172.20.3.4'), isTrue);
      expect(isLanHost('192.168.31.7'), isTrue);
      expect(isLanHost('100.101.102.103'), isTrue); // Tailscale
      expect(isLanHost('8.8.8.8'), isFalse);
    });

    test('机器名', () {
      expect(isLanHost('DESKTOP-ABC'), isTrue);
      expect(isLanHost('macbook.local'), isTrue);
      expect(isLanHost('pocket.example.com'), isFalse);
    });
  });

  group('parseScanned', () {
    test('自定义 scheme 一次给两条线路', () {
      final scanned = parseScanned(
        'dshpocket://connect?lan=http://192.168.1.5:3081'
        '&public=https://abc.trycloudflare.com&pin=87654321&name=宿舍电脑',
      );
      expect(scanned.lanUrl, 'http://192.168.1.5:3081');
      expect(scanned.publicUrl, 'https://abc.trycloudflare.com');
      expect(scanned.pin, '87654321');
      expect(scanned.name, '宿舍电脑');
    });

    test('普通 URL 扫码', () {
      final scanned = parseScanned('http://192.168.1.5:3081');
      expect(scanned.lanUrl, 'http://192.168.1.5:3081');
      expect(scanned.publicUrl, isNull);
    });
  });

  group('buildEntryUri', () {
    test('带密码与布局', () {
      final uri = buildEntryUri(
        'http://192.168.1.5:3081',
        pin: '12345678',
        layout: LayoutPref.mobile,
      );
      expect(uri.toString(),
          'http://192.168.1.5:3081/?token=12345678&dsh-layout=mobile');
    });

    test('没密码就不带 token', () {
      final uri = buildEntryUri('https://abc.trycloudflare.com');
      expect(uri.toString(), 'https://abc.trycloudflare.com/');
      expect(uri.query, isEmpty);
    });
  });

  group('Connection', () {
    test('自动线路先局域网后公网', () {
      const connection = Connection(
        id: '1',
        name: '电脑',
        lanUrl: 'http://192.168.1.5:3081',
        publicUrl: 'https://abc.trycloudflare.com',
      );
      final lines = connection.orderedLines();
      expect(lines.map((line) => line.kind).toList(),
          [LinePolicy.lan, LinePolicy.public]);
    });

    test('偏公网时公网排前面', () {
      const connection = Connection(
        id: '1',
        name: '电脑',
        lanUrl: 'http://192.168.1.5:3081',
        publicUrl: 'https://abc.trycloudflare.com',
        policy: LinePolicy.public,
      );
      expect(connection.orderedLines().first.kind, LinePolicy.public);
    });

    test('JSON 往返', () {
      final connection = Connection(
        id: 'x',
        name: '宿舍电脑',
        lanUrl: 'http://192.168.1.5:3081',
        policy: LinePolicy.lan,
        layout: LayoutPref.desktop,
        lastUsedAt: DateTime.parse('2026-10-30T10:00:00Z'),
        lastLine: LinePolicy.lan,
      );
      final restored = Connection.fromJson(connection.toJson());
      expect(restored.name, connection.name);
      expect(restored.lanUrl, connection.lanUrl);
      expect(restored.policy, LinePolicy.lan);
      expect(restored.layout, LayoutPref.desktop);
      expect(restored.lastLine, LinePolicy.lan);
    });
  });
}
