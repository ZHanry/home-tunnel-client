// HOMEDESK: 检查主导航与窗口动作互不冲突，以及托盘失败时窗口仍可访问。
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/homedesk_theme.dart';
import 'package:flutter_hbb/homedesk_settings_shell.dart';
import 'package:flutter_hbb/homedesk_title_bar.dart';
import 'package:flutter_hbb/homedesk_window.dart';
import 'package:flutter_hbb/nestlink_locale.dart';
import 'package:flutter_hbb/nestlink_dialog.dart';
import 'package:flutter_hbb/homedesk_account.dart';
import 'package:flutter_hbb/homedesk_navigation.dart';
import 'homedesk_services_test.dart' as portal;

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
      await tester.tap(find.byKey(const ValueKey('nav-devices')));
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
    expect(find.byKey(const ValueKey('title-account')), findsNothing);
    expect(find.byKey(const ValueKey('title-settings')), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('标题栏无需登录即可切换外观、语言并查看版本', (tester) async {
    tester.view.physicalSize = const Size(1120, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final savedLanguage = nestlinkLanguage.value;
    nestlinkLanguage.value = 'zh-cn';
    addTearDown(() => nestlinkLanguage.value = savedLanguage);
    var dark = false;
    await tester.pumpWidget(StatefulBuilder(
        builder: (context, update) => MaterialApp(
            theme: homeDeskTheme(dark ? ThemeData.dark() : ThemeData.light()),
            home: Scaffold(
                body: HomeDeskTitleBar(
                    brand: 'NestLink',
                    inSettings: false,
                    maximized: false,
                    onHome: () {},
                    onDrag: () {},
                    onMaximize: () {},
                    onMinimize: () {},
                    onClose: () {},
                    onTheme: () => update(() => dark = !dark),
                    onLanguage: () => nestlinkLanguage.value =
                        nestlinkEnglish ? 'zh-cn' : 'en')))));
    expect(find.text('14.0.0'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('title-theme')));
    await tester.pumpAndSettle();
    expect(Theme.of(tester.element(find.byType(HomeDeskTitleBar))).brightness,
        Brightness.dark);
    await tester.tap(find.byKey(const ValueKey('title-language')));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Change theme'), findsOneWidget);
    expect(find.byTooltip('简体中文'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('title-version')));
    await tester.pumpAndSettle();
    expect(find.byType(NestLinkDialog), findsOneWidget);
    expect(find.widgetWithText(SelectableText, '14.0.0'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Close'));
    await tester.pumpAndSettle();
    expect(find.byType(NestLinkDialog), findsNothing);
    expect(find.text('14.0.0'), findsNothing);
    tester.view.physicalSize = const Size(360, 300);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('title-theme')), findsOneWidget);
    expect(find.byKey(const ValueKey('title-language')), findsOneWidget);
    expect(find.byKey(const ValueKey('title-version')), findsOneWidget);
    expect(find.byKey(const ValueKey('title-account')), findsNothing);
    expect(find.byKey(const ValueKey('title-settings')), findsNothing);
    expect(tester.takeException(), isNull);
  });
  for (final compact in [false, true]) {
    testWidgets('${compact ? '紧凑' : '普通'}侧栏账号固定在底部，双倍字号主导航可滚动', (tester) async {
      tester.view.physicalSize = const Size(400, 260);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final account = HomeDeskAccount();
      final api = portal.PortalFixtureApi()..signedIn = true;
      account.publish(api, portal.sampleCatalog(), '', (_) async {});
      final calls = <String>[];
      await tester.pumpWidget(MaterialApp(
          theme: homeDeskTheme(ThemeData.light()),
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: child!),
          home: Scaffold(
              body: Align(
                  alignment: Alignment.centerLeft,
                  child: HomeDeskNavigation(
                      brand: 'NestLink',
                      selected: 'devices',
                      compact: compact,
                      account: account,
                      onSelected: calls.add)))));
      await tester.pumpAndSettle();
      final navigation = find.byType(HomeDeskNavigation);
      final tabs = find.descendant(
          of: find.byKey(const ValueKey('nav-main-scroll')),
          matching: find.byType(TextButton));
      expect(tabs, findsNWidgets(3));
      expect(tester.widgetList<TextButton>(tabs).map((button) => button.key), [
        const ValueKey('nav-devices'),
        const ValueKey('nav-remote'),
        const ValueKey('nav-services'),
      ]);
      expect(
          tester
              .widget<Text>(find.descendant(
                  of: find.byKey(const ValueKey('nav-devices')),
                  matching: find.text('设备管理')))
              .style
              ?.fontSize,
          compact ? 12 : 15);
      final entry = find.byKey(const ValueKey('nav-account'));
      expect(entry.hitTestable(), findsOneWidget);
      expect(find.byKey(const ValueKey('nav-account-avatar')), findsOneWidget);
      expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('nav-account-name')))
              .data,
          '我的家庭');
      final footerBefore = tester.getRect(entry);
      expect(footerBefore.bottom,
          closeTo(tester.getRect(navigation).bottom - 12, 0.1));
      expect(
          tester.getRect(find.byKey(const ValueKey('nav-main-scroll'))).bottom,
          lessThanOrEqualTo(footerBefore.top));
      final scrollable = tester.state<ScrollableState>(find.descendant(
          of: find.byKey(const ValueKey('nav-main-scroll')),
          matching: find.byType(Scrollable)));
      expect(scrollable.position.maxScrollExtent, greaterThan(0));
      await tester.ensureVisible(find.byKey(const ValueKey('nav-services')));
      await tester.pumpAndSettle();
      expect(scrollable.position.pixels, greaterThan(0));
      expect(tester.getRect(entry), footerBefore);
      await tester.tap(find.byKey(const ValueKey('nav-services')));
      await tester.tap(entry);
      expect(calls, ['services', 'account']);
      account.clear(api);
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('nav-account-name')))
              .data,
          '未登录');
      expect(find.byIcon(Icons.person_outline_rounded), findsOneWidget);
      await tester.tap(entry);
      expect(calls.last, 'account');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      account.dispose();
      api.close();
    });
  }
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
