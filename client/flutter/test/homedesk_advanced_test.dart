import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/homedesk_advanced.dart';

void main() {
  const key = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=';

  test('纯内网只接受完整私网组', () {
    expect(
        validateHomeDeskNetworkDraft(
          mode: 'lan_only',
          server: '192.168.50.10:21116',
          relay: '',
          key: key,
          familyCidr: '192.168.50.0/24',
          sourceCidr: '',
        ),
        isEmpty);
    expect(
        validateHomeDeskNetworkDraft(
          mode: 'lan_only',
          server: 'remote.example.com:21116',
          relay: '',
          key: key,
          familyCidr: '192.168.50.0/24',
          sourceCidr: '',
        ),
        isNotEmpty);
  });

  test('自建公网拒绝数字域名、不完整公钥与过宽来源', () {
    String validate(
            {String server = 'remote.example.com:21116',
            String testKey = key,
            String source = '203.0.113.0/24'}) =>
        validateHomeDeskNetworkDraft(
            mode: 'self_hosted',
            server: server,
            relay: '',
            key: testKey,
            familyCidr: '192.168.50.0/24',
            sourceCidr: source);
    expect(validate(), isEmpty);
    for (final server in [
      '127.1:21116',
      '100.64.0.1:21116',
      '999.999.999.999:21116',
      'host.123:21116'
    ]) {
      expect(validate(server: server), isNotEmpty);
    }
    expect(validate(testKey: 'short'), isNotEmpty);
    expect(validate(source: '0.0.0.0/0'), isNotEmpty);
  });

  test('即使配置正确，中继地址仍被拒绝', () {
    expect(
        validateHomeDeskNetworkDraft(
            mode: 'self_hosted',
            server: 'remote.example.com:21116',
            relay: 'relay.example.com:21117',
            key: key,
            familyCidr: '192.168.50.0/24',
            sourceCidr: ''),
        isNotEmpty);
  });

  test('家庭 CIDR 不允许跨出 RFC1918 范围', () {
    expect(isHomeDeskPrivateWhitelistEntry('192.168.50.0/24'), isTrue);
    expect(isHomeDeskPrivateWhitelistEntry('192.168.0.0/8'), isFalse);
    expect(isHomeDeskPrivateWhitelistEntry('2001:db8::/64'), isFalse);
  });

  testWidgets('连接配置由登录服务提供，旧内网配置没有可用入口', (tester) async {
    var writes = 0;
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => TextButton(
                onPressed: () => showHomeDeskNetworkSettings(context,
                    readOption: (key) => key == 'custom-rendezvous-server'
                        ? 'signal.example.com:21116'
                        : 'lan_only',
                    saveProfile: (a, b, c, d, e, f) async {
                      writes++;
                      return '';
                    }),
                child: const Text('打开')))));
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.text('signal.example.com:21116'), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('远控仅限内网'), findsNothing);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(writes, 0);
    expect(tester.takeException(), isNull);
  });
}
