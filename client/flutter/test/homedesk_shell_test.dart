// HOMEDESK: 检查主导航与窗口动作互不冲突，以及托盘失败时窗口仍可访问。
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/homedesk_theme.dart';
import 'package:flutter_hbb/homedesk_settings_shell.dart';
import 'package:flutter_hbb/homedesk_title_bar.dart';
import 'package:flutter_hbb/homedesk_window.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final dark in [false, true]) {
    testWidgets('设置在${dark ? '深色' : '浅色'}窄窗口双倍字体下可导航且没有溢出', (tester) async {
      tester.view.physicalSize = const Size(600, 520);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var selected = 0;
      var backed = false;
      await tester.pumpWidget(MaterialApp(
          theme: homeDeskTheme(dark ? ThemeData.dark() : ThemeData.light()),
          home: Scaffold(
              body: MediaQuery(
                  data: const MediaQueryData(textScaler: TextScaler.linear(2)),
                  child: StatefulBuilder(
                      builder: (context, update) => HomeDeskSettingsShell(
                            labels: const ['常规', '安全', '网络', '关于'],
                            icons: const [
                              Icons.tune,
                              Icons.lock,
                              Icons.link,
                              Icons.info
                            ],
                            selected: selected,
                            onSelected: (index) =>
                                update(() => selected = index),
                            onBack: () => backed = true,
                            child: ListView(children: [
                              HomeDeskSettingsCard(
                                  title: '当前页面 $selected',
                                  children: [
                                    const Padding(
                                        padding: EdgeInsets.all(16),
                                        child: Text('连接配置与输入内容')),
                                  ])
                            ]),
                          ))))));
      await tester
          .ensureVisible(find.byKey(const ValueKey('settings-section-2')));
      await tester.tap(find.byKey(const ValueKey('settings-section-2')));
      await tester.pumpAndSettle();
      expect(selected, 2);
      expect(find.text('当前页面 2'), findsOneWidget);
      await tester.tap(find.byTooltip('家庭设备'));
      expect(backed, isTrue);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('标题栏窄窗口保持最小化、缩放、关闭和返回入口相互独立', (tester) async {
    tester.view.physicalSize = const Size(360, 300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final calls = <String>[];
    await tester.pumpWidget(MaterialApp(
        theme: homeDeskTheme(ThemeData.dark()),
        home: Scaffold(
            body: HomeDeskTitleBar(
                brand: 'HomeDesk',
                inSettings: true,
                maximized: false,
                onHome: () => calls.add('home'),
                onDrag: () => calls.add('drag'),
                onMaximize: () => calls.add('max'),
                onMinimize: () => calls.add('tray'),
                onClose: () => calls.add('close')))));
    for (final label in ['最小化到系统托盘', '最大化窗口', '关闭窗口', '返回主页']) {
      await tester.tap(find.byTooltip(label));
    }
    expect(calls, ['tray', 'max', 'close', 'home']);
    expect(tester.takeException(), isNull);
  });
  test('只有原生确认图标可用才隐藏到托盘，失败或插件不可用则普通最小化', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    const host = MethodChannel('org.rustdesk.rustdesk/host');
    const windows = MethodChannel('window_manager');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    var fallbacks = 0;
    messenger.setMockMethodCallHandler(windows, (call) async {
      if (call.method == 'minimize') fallbacks++;
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(host, null);
      messenger.setMockMethodCallHandler(windows, null);
    });
    messenger.setMockMethodCallHandler(host, (call) async => true);
    await homeDeskEnableTray();
    await homeDeskMinimizeToTray();
    expect(fallbacks, 0);
    messenger.setMockMethodCallHandler(host, (call) async => false);
    await homeDeskMinimizeToTray();
    expect(fallbacks, 1);
    messenger.setMockMethodCallHandler(host, null);
    await homeDeskMinimizeToTray();
    expect(fallbacks, 2);
  });
}
