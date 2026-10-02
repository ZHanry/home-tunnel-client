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
          relay: '192.168.50.10:21117',
          key: key,
          familyCidr: '192.168.50.0/24',
          sourceCidr: '',
        ),
        isEmpty);
    expect(
        validateHomeDeskNetworkDraft(
          mode: 'lan_only',
          server: 'remote.example.com:21116',
          relay: '192.168.50.10:21117',
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
            relay: 'relay.example.com:21117',
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

  test('家庭 CIDR 不允许跨出 RFC1918 范围', () {
    expect(isHomeDeskPrivateWhitelistEntry('192.168.50.0/24'), isTrue);
    expect(isHomeDeskPrivateWhitelistEntry('192.168.0.0/8'), isFalse);
    expect(isHomeDeskPrivateWhitelistEntry('2001:db8::/64'), isFalse);
  });

  testWidgets('切换模式加载独立组且保存ACK期间禁止重入', (tester) async {
    const profiles = <String, String>{
      'homedesk-net-mode': 'lan_only',
      'homedesk-profile-lan_only-server': '192.168.50.10:21116',
      'homedesk-profile-lan_only-relay': '192.168.50.10:21117',
      'homedesk-profile-lan_only-key': key,
      'homedesk-profile-lan_only-family-cidr': '192.168.50.0/24',
      'homedesk-profile-lan_only-source-cidr': '',
      'homedesk-profile-self_hosted-server': 'remote.example.com:21116',
      'homedesk-profile-self_hosted-relay': 'relay.example.com:21117',
      'homedesk-profile-self_hosted-key': key,
      'homedesk-profile-self_hosted-family-cidr': '192.168.50.0/24',
      'homedesk-profile-self_hosted-source-cidr': '203.0.113.0/24',
    };
    final ack = Completer<String>();
    var saves = 0;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
      return TextButton(
          onPressed: () => showHomeDeskNetworkSettings(context,
              readOption: (name) => profiles[name] ?? '',
              saveProfile: (mode, server, relay, savedKey, family, source) {
                saves++;
                expect(mode, 'self_hosted');
                expect(server, 'remote.example.com:21116');
                expect(relay, 'relay.example.com:21117');
                return ack.future;
              }),
          child: const Text('打开'));
    })));
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('纯内网').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('自建公网').last);
    await tester.pumpAndSettle();
    expect(find.text('remote.example.com:21116'), findsWidgets);
    expect(find.text('relay.example.com:21117'), findsWidgets);
    await tester.tap(find.text('保存并重启服务'));
    await tester.pump();
    expect(saves, 1);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    ack.complete('后台拒绝保存');
    await tester.pumpAndSettle();
    expect(find.text('后台拒绝保存'), findsOneWidget);
    expect(find.text('HomeDesk 网络模式'), findsOneWidget);
  });
}
