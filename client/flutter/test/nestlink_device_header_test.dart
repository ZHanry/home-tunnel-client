import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/homedesk_account.dart';
import 'package:flutter_hbb/homedesk_family_devices.dart';
import 'package:flutter_hbb/homedesk_theme.dart';
import 'package:flutter_hbb/homedesk_tunnel_api.dart';
import 'package:flutter_hbb/nestlink_device_list.dart';
import 'homedesk_family_devices_test.dart' as family;
import 'nestlink_desktop_14_test.dart' as desktop;

class HeaderApi extends desktop.DesktopApi {
  int catalogRequests = 0;
  @override
  Future<HomeTunnelCatalog> catalog() async {
    catalogRequests++;
    return super.catalog();
  }
}

Finder control(String key) => find.byKey(ValueKey(key));

void main() {
  testWidgets('宽窗标题右侧同时容纳搜索、远程连接、筛选、刷新且不显示总数', (tester) async {
    tester.view.physicalSize = const Size(1120, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final account = HomeDeskAccount(), api = HeaderApi();
    account.publish(api, desktop.directory(), family.one, (_) async {});
    await tester.pumpWidget(desktop.app(account));
    await tester.pumpAndSettle();
    final header = control('device-title-tools');
    final title = find.descendant(of: header, matching: find.text('设备管理'));
    final search = control('device-search');
    expect(title, findsOneWidget);
    expect(
        find.byWidgetPredicate((w) =>
            w is Text &&
            w.data == '设备管理' &&
            w.style?.fontSize == HomeDeskTokens.pageTitle),
        findsOneWidget);
    expect(find.textContaining(RegExp(r'^共 \d+ 台设备$')), findsNothing);
    expect(tester.getCenter(search).dy, closeTo(tester.getCenter(title).dy, 1));
    var previousRight = tester.getRect(search).right;
    for (final key in [
      'device-manual-connect',
      'device-filter',
      'family-refresh'
    ]) {
      final action = control(key);
      expect(find.descendant(of: header, matching: action), findsOneWidget);
      expect(action.hitTestable(), findsOneWidget);
      expect(
          tester.getCenter(action).dy, closeTo(tester.getCenter(search).dy, 1));
      expect(tester.getRect(action).left, greaterThanOrEqualTo(previousRight));
      previousRight = tester.getRect(action).right;
    }
    await tester.tap(control('device-manual-connect'));
    await tester.pumpAndSettle();
    expect(find.text('连接一台设备'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '连接设备'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();
    await tester.enterText(search, '工作');
    await tester.pump();
    expect(control('device-row-${desktop.offline}'), findsOneWidget);
    expect(control('device-row-${family.two}'), findsNothing);
    await tester.enterText(search, '');
    await tester.pump();
    await tester.tap(control('device-filter'));
    await tester.pumpAndSettle();
    await tester.tap(find.byWidgetPredicate(
        (widget) => widget is CheckedPopupMenuItem<int> && widget.value == 2));
    await tester.pumpAndSettle();
    expect(control('device-row-${desktop.offline}'), findsOneWidget);
    expect(control('device-row-${family.two}'), findsNothing);
    final beforeRefresh = api.catalogRequests;
    await tester.tap(control('family-refresh'));
    await tester.pumpAndSettle();
    expect(api.catalogRequests, beforeRefresh + 1);
    expect(find.textContaining(RegExp(r'^共 \d+ 台设备$')), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    account.dispose();
    api.close();
  });

  for (final config in [
    (const Size(780, 600), 1.0),
    (const Size(560, 900), 2.0),
  ]) {
    testWidgets('设备标题工具栏在 ${config.$1.width} 像素、${config.$2} 倍字体下可操作',
        (tester) async {
      tester.view.physicalSize = config.$1;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final account = HomeDeskAccount(), api = HeaderApi();
      account.publish(api, desktop.directory(), family.one, (_) async {});
      await tester.pumpWidget(desktop.app(account, scale: config.$2));
      await tester.pumpAndSettle();
      final header = control('device-title-tools');
      for (final key in [
        'device-search',
        'device-manual-connect',
        'device-filter',
        'family-refresh'
      ]) {
        expect(find.descendant(of: header, matching: control(key)),
            findsOneWidget);
        expect(control(key).hitTestable(), findsOneWidget);
        final rect = tester.getRect(control(key));
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(config.$1.width));
      }
      expect(find.textContaining(RegExp(r'^共 \d+ 台设备$')), findsNothing);
      final beforeScroll = tester.getRect(header);
      final body = find.descendant(
          of: find.byType(NestLinkDeviceList),
          matching: find.byType(SingleChildScrollView));
      await tester.drag(body, const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(tester.getRect(header), beforeScroll);
      expect(control('device-filter').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      account.dispose();
      api.close();
    });
  }

  testWidgets('独立设备列表可以注入远程连接回调，旧账号按钮不能再次调用', (tester) async {
    final account = HomeDeskAccount(), api = HeaderApi();
    account.publish(api, desktop.directory(), family.one, (_) async {});
    var manualConnections = 0;
    await tester.pumpWidget(MaterialApp(
        theme: homeDeskTheme(ThemeData()),
        home: Scaffold(
            body: HomeDeskFamilyDevices(
                account: account,
                listLayout: true,
                onLogin: () {},
                onConnect: (_) {},
                onManualConnect: () => manualConnections++,
                readOption: family.option))));
    await tester.pumpAndSettle();
    final stale =
        tester.widget<IconButton>(control('device-manual-connect')).onPressed;
    await tester.tap(control('device-manual-connect'));
    expect(manualConnections, 1);
    account.clear(api);
    stale!();
    expect(manualConnections, 1);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    account.dispose();
    api.close();
  });
}
