import 'package:dsh_pocket/data/pocket_status.dart';
import 'package:dsh_pocket/official/official.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UpdateInfo', () {
    test('正常清单能解析', () {
      final info = UpdateInfo.tryParse(r'''
{
  "versionCode": 3,
  "versionName": "1.1.1",
  "force": false,
  "notes": "1. 修修复\n2. 优化",
  "apkUrl": "https://xuhuohua.xyz/dsh-pocket/dsh-pocket-1.1.1.apk",
  "sizeBytes": 31457280,
  "sha256": "abc",
  "mirrors": ["https://github.com/x/y.apk"]
}
''');
      expect(info, isNotNull);
      expect(info!.versionCode, 3);
      expect(info.versionName, '1.1.1');
      expect(info.force, isFalse);
      expect(info.sizeText, '30.0 MB');
      expect(info.mirrors.single, contains('github.com'));
      expect(info.isNewerThan(2), isTrue);
      expect(info.isNewerThan(3), isFalse);
    });

    test('缺字段/写错返回 null，不崩', () {
      expect(UpdateInfo.tryParse('{}'), isNull);
      expect(UpdateInfo.tryParse('not json'), isNull);
      expect(UpdateInfo.tryParse('{"versionCode":"3","versionName":"1","apkUrl":"x"}'), isNull);
      expect(UpdateInfo.tryParse('{"versionCode":3,"versionName":"","apkUrl":"x"}'), isNull);
    });
  });

  group('Announcement', () {
    test('按服务器的 announcements 数组解析', () {
      final items = Announcement.parseList('''
{"updatedAt":"2026-10-20T19:28:00","announcements":[
  {"id":"38e08a58","title":"标题一","content":"内容一","createdAt":"2026-10-14T19:38:52"},
  {"id":"b7c1e2a4","title":"标题二","content":"内容二","url":"https://example.com"}
]}
''');
      expect(items.length, 2);
      expect(items.first.id, '38e08a58');
      expect(items.first.url, isNull);
      expect(items.last.url, 'https://example.com');
    });

    test('脏数据跳过', () {
      final items = Announcement.parseList(
        '{"announcements":[{"id":1,"title":"x","content":"y"},{"id":"ok","title":"t","content":"c"}]}',
      );
      expect(items.length, 1);
      expect(items.single.id, 'ok');
    });
  });

  group('PocketStatus', () {
    test('解析 server-response 信封', () {
      final status = PocketStatus.tryParse(
        '{"type":"server-response","rpcId":"dsh-pocket-app","result":{"ok":true,"data":'
        '{"tunnelUrl":"https://fox-abc.trycloudflare.com/","lanUrl":"http://192.168.1.5:3081",'
        '"proxyPort":3081,"tunnelRunning":true}}}',
      );
      expect(status, isNotNull);
      expect(status!.tunnelUrl, 'https://fox-abc.trycloudflare.com');
      expect(status.lanUrl, 'http://192.168.1.5:3081');
      expect(status.proxyPort, 3081);
      expect(status.tunnelRunning, isTrue);
    });

    test('隧道没开时 tunnelUrl 是 null，不算脏数据', () {
      final status = PocketStatus.tryParse(
        '{"result":{"ok":true,"data":{"tunnelUrl":null,"lanUrl":"http://10.0.0.2:3081"}}}',
      );
      expect(status!.tunnelUrl, isNull);
      expect(status.isEmpty, isFalse);
    });

    test('失败信封 / 乱码返回 null', () {
      expect(PocketStatus.tryParse('{"result":{"ok":false}}'), isNull);
      expect(PocketStatus.tryParse('<html>login</html>'), isNull);
      expect(PocketStatus.tryParse(''), isNull);
    });
  });
}
