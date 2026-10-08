// HOMEDESK: 验证真实设备墙的连接、唤醒、故障和放大字体布局。
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/homedesk_console_api.dart';
import 'package:flutter_hbb/homedesk_devices.dart';

class FakeConsole extends HomeDeskConsoleApi {
  bool fail = false, closed = false, online = false;
  String? woken;
  Completer<List<Map<String, dynamic>>>? pendingDevices;
  FakeConsole() : super('http://192.168.50.10:8080', 'test-only-token');
  @override
  Future<List<Map<String, dynamic>>> devices() async {
    final pending = pendingDevices;
    if (pending != null) return pending.future;
    if (fail) throw const FormatException('测试故障');
    return [
      {
        'id': '123456',
        'name': '书房电脑',
        'room': '书房',
        'online': online,
        'wol_configured': true
      }
    ];
  }

  @override
  Future<void> wake(String id) async {
    woken = id;
  }

  @override
  void close() {
    closed = true;
    super.close();
  }
}

class ConfigConsole extends HomeDeskConsoleApi {
  final String token;
  bool closed = false;
  ConfigConsole(String url, this.token, {bool Function()? isAllowed})
      : super(url, token, isAllowed: isAllowed);
  @override
  Future<List<Map<String, dynamic>>> devices() async => [
        {
          'id': '123456',
          'name': token,
          'room': '书房',
          'online': true,
        }
      ];
  @override
  void close() {
    closed = true;
    super.close();
  }
}

Widget host(HomeDeskConsoleApi? api,
        {void Function(BuildContext, String)? onConnect,
        String Function(String)? readOption,
        HomeDeskConsoleApi Function(String url, String token,
                {bool Function()? isAllowed})?
            apiBuilder,
        double scale = 1}) =>
    MaterialApp(
        home: Scaffold(
            body: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(scale)),
      child: SizedBox(
          width: 600,
          height: 580,
          child: HomeDeskDevices(
              api: api,
              apiBuilder: apiBuilder,
              onConnect: onConnect,
              readOption: readOption)),
    )));

void main() {
  testWidgets('连接使用所选设备 ID，组件释放时关闭客户端', (tester) async {
    final api = FakeConsole();
    String? connected;
    await tester.pumpWidget(host(api, onConnect: (_, id) {
      connected = id;
    }));
    await tester.pump();
    expect(find.text('书房电脑'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, '尝试连接'));
    expect(connected, '123456');
    await tester.pumpWidget(const SizedBox());
    expect(api.closed, isTrue);
  });
  testWidgets('唤醒等待状态在设备上线后收敛', (tester) async {
    final api = FakeConsole();
    await tester.pumpWidget(host(api));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '远程开机'));
    await tester.pump();
    expect(api.woken, '123456');
    expect(find.text('等待上线'), findsOneWidget);
    api.online = true;
    await tester.pump(const Duration(seconds: 10));
    await tester.pump();
    expect(find.text('等待上线'), findsNothing);
    expect(find.text('● 在线'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 30));
  });
  testWidgets('双倍字体无溢出，管理台故障提示保留手动连接', (tester) async {
    final api = FakeConsole();
    await tester.pumpWidget(host(api, scale: 2));
    await tester.pump();
    expect(tester.takeException(), isNull);
    api.fail = true;
    await tester.pump(const Duration(seconds: 10));
    await tester.pump();
    expect(find.text('设备状态暂未更新，你仍可尝试连接或手动连接。'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('撤销许可会关闭客户端并保留设备 ID 入口', (tester) async {
    final api = FakeConsole();
    var allowed = true;
    await tester.pumpWidget(host(api,
        readOption: (key) =>
            key == 'homedesk-console-allowed' ? (allowed ? 'Y' : 'N') : ''));
    await tester.pump();
    expect(find.text('书房电脑'), findsOneWidget);
    allowed = false;
    await tester.pump(const Duration(seconds: 10));
    await tester.pump();
    expect(api.closed, isTrue);
    expect(find.text('设备中心当前不可达，可通过设备 ID 连接。'), findsOneWidget);
    expect(find.text('从连接第一台电脑开始'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('请求进行中撤销许可不会恢复旧设备列表', (tester) async {
    final api = FakeConsole();
    var allowed = true;
    await tester.pumpWidget(host(api,
        readOption: (key) =>
            key == 'homedesk-console-allowed' ? (allowed ? 'Y' : 'N') : ''));
    await tester.pump();
    expect(find.text('书房电脑'), findsOneWidget);
    final pending = Completer<List<Map<String, dynamic>>>();
    api.pendingDevices = pending;
    await tester.pump(const Duration(seconds: 10));
    allowed = false;
    await tester.pump(const Duration(seconds: 10));
    expect(api.closed, isTrue);
    pending.complete([
      {'id': 'old', 'name': '旧设备', 'online': true}
    ]);
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.text('旧设备'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('恢复许可按当前配置重建客户端，不复用旧 Token', (tester) async {
    var allowed = true;
    var url = 'http://192.168.50.10:8080';
    var token = 'old-token';
    final created = <ConfigConsole>[];
    await tester.pumpWidget(host(null, readOption: (key) {
      switch (key) {
        case 'homedesk-console-allowed':
          return allowed ? 'Y' : 'N';
        case 'homedesk-console-url':
          return url;
        case 'homedesk-console-token':
          return token;
      }
      return '';
    }, apiBuilder: (url, token, {isAllowed}) {
      final api = ConfigConsole(url, token, isAllowed: isAllowed);
      created.add(api);
      return api;
    }));
    await tester.pump();
    expect(find.text('old-token'), findsOneWidget);
    allowed = false;
    await tester.pump(const Duration(seconds: 10));
    expect(created.single.closed, isTrue);
    url = 'http://192.168.50.11:8080';
    token = 'new-token';
    allowed = true;
    await tester.pump(const Duration(seconds: 10));
    await tester.pump();
    expect(created, hasLength(2));
    expect(created.first.closed, isTrue);
    expect(find.text('new-token'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
