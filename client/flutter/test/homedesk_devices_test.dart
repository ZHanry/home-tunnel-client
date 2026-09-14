// HOMEDESK: 验证真实设备墙的连接、唤醒、故障和放大字体布局。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/homedesk_console_api.dart';
import 'package:flutter_hbb/homedesk_devices.dart';

class FakeConsole extends HomeDeskConsoleApi {
  bool fail = false, closed = false, online = false;
  String? woken;
  FakeConsole() : super('http://192.168.50.10:8080', 'test-only-token');
  @override
  Future<List<Map<String, dynamic>>> devices() async {
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

Widget host(FakeConsole api,
        {void Function(BuildContext, String)? onConnect, double scale = 1}) =>
    MaterialApp(
        home: Scaffold(
            body: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(scale)),
      child: SizedBox(
          width: 600,
          height: 580,
          child: HomeDeskDevices(api: api, onConnect: onConnect)),
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
}
