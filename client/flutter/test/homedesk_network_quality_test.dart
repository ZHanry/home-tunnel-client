// HOMEDESK: 合成网络地址与会话质量验证；不保存真实配置或发起远控。
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/homedesk_service_address.dart';
import 'package:flutter_hbb/homedesk_quality.dart';

Widget qualityHost(HomeDeskQuality value) =>
    MaterialApp(home: Scaffold(body: Center(child: value)));

void main() {
  testWidgets('家庭服务地址校验后显式保存，失败保持原批准地址，保存中禁止重复提交', (tester) async {
    var approved = 'https://old.example.com';
    var writes = 0;
    final gate = Completer<void>();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: HomeDeskServiceAddress(
                read: () => approved,
                save: (value) async {
                  writes++;
                  await gate.future;
                  approved = value;
                }))));
    final field = find.byKey(const ValueKey('network-service-address'));
    final save = find.byKey(const ValueKey('network-save-service-address'));
    for (final invalid in [
      'http://example.com',
      'https://example.com/path',
      'https://user:pass@example.com'
    ]) {
      await tester.enterText(field, invalid);
      await tester.tap(save);
      await tester.pump();
      expect(writes, 0);
      expect(approved, 'https://old.example.com');
    }
    await tester.enterText(field, 'https://new.example.com/');
    await tester.tap(save);
    await tester.pump();
    expect(writes, 1);
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    gate.complete();
    await tester.pumpAndSettle();
    expect(approved, 'https://new.example.com');
    expect(find.text('地址已保存，请重新登录家庭账号。'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('地址保存未获原生确认时不宣称成功', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: HomeDeskServiceAddress(
                read: () => 'https://old.example.com', save: (_) async {}))));
    await tester.enterText(
        find.byKey(const ValueKey('network-service-address')),
        'https://new.example.com');
    await tester
        .tap(find.byKey(const ValueKey('network-save-service-address')));
    await tester.pumpAndSettle();
    expect(find.text('地址未能保存，请检查后重试。'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('质量面板中文显示实际路径，未知信息不伪装成公网P2P', (tester) async {
    for (final entry in {
      'lan': '局域网直连',
      'p2p': '公网 P2P',
      'relay': '中继转发',
      'direct_unknown': '直连（路径未确认）'
    }.entries) {
      await tester.pumpWidget(qualityHost(HomeDeskQuality(
          path: entry.key,
          transport: 'TCP',
          secure: true,
          speed: '1.2 MB/s',
          fps: '30',
          delay: '23',
          bitrate: '2000',
          codec: 'H264',
          chroma: '4:2:0')));
      expect(find.text(entry.value), findsOneWidget);
      expect(find.text('接收速度'), findsOneWidget);
      expect(find.text('目标码率'), findsOneWidget);
      expect(find.text('23 毫秒'), findsOneWidget);
      expect(find.text('已加密'), findsOneWidget);
      expect(find.text('Speed'), findsNothing);
      expect(find.text('Target Bitrate'), findsNothing);
    }
    await tester.pumpWidget(qualityHost(const HomeDeskQuality(
        path: 'unknown', transport: 'Relay', delay: '25')));
    expect(find.text('正在连接'), findsOneWidget);
    expect(find.text('25 毫秒'), findsOneWidget);
    expect(find.text('未提供'), findsOneWidget);
    expect(find.text('确认中'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('中文质量面板在窄屏双倍字体下不会横向溢出', (tester) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(2)),
                child: const Center(
                    child: HomeDeskQuality(
                        path: 'direct_unknown',
                        transport: 'TCP',
                        secure: true,
                        speed: '12.34 MB/s',
                        fps: '30',
                        delay: '25',
                        bitrate: '5000',
                        codec: 'H264',
                        chroma: '4:2:0'))))));
    expect(tester.takeException(), isNull);
  });
}
