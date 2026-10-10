import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_hbb/nestlink_remote_settings.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/homedesk_account.dart';
import 'package:flutter_hbb/homedesk_dashboard.dart';
import 'package:flutter_hbb/homedesk_family_devices.dart';
import 'package:flutter_hbb/homedesk_theme.dart';
import 'package:flutter_hbb/homedesk_title_bar.dart';
import 'package:flutter_hbb/homedesk_tunnel_api.dart';
import 'package:flutter_hbb/nestlink_dialog.dart';
import 'homedesk_family_devices_test.dart' as family;

const phone = '20000000-0000-4000-8000-000000000003';
const offline = '20000000-0000-4000-8000-000000000004';
HomeTunnelCatalog directory() => HomeTunnelCatalog(devices: const [
      HomeTunnelDevice(
          id: family.one, name: '我的电脑', platform: 'Windows', online: true),
      HomeTunnelDevice(
          id: family.two,
          name: '书房电脑',
          platform: 'Windows',
          online: true,
          favorite: true),
      HomeTunnelDevice(
          id: offline, name: '工作笔记本', platform: 'Linux', online: false),
      HomeTunnelDevice(
          id: phone, name: '我的手机', platform: 'Android', online: true),
    ], services: []);

class DesktopApi extends family.FamilyApi {
  DesktopApi() {
    result = directory();
    signedIn = true;
    bindings = [
      ...bindings,
      HomeDeskRemoteBinding(
          deviceId: offline,
          remoteId: '555555555',
          server: 'relay.example.com:21116',
          keySHA256: 'a' * 64,
          platform: 'Linux',
          online: false),
      HomeDeskRemoteBinding(
          deviceId: phone,
          remoteId: '246813579',
          server: 'relay.example.com:21116',
          keySHA256: 'a' * 64,
          platform: 'Android',
          online: true),
    ];
  }
}

Widget app(HomeDeskAccount account,
        {ValueChanged<String>? onConnect,
        GlobalKey? paint,
        double scale = 1,
        bool dark = false,
        bool preview = false}) =>
    MaterialApp(
        theme: homeDeskTheme(ThemeData(
            brightness: dark ? Brightness.dark : Brightness.light,
            fontFamily: preview ? 'NestLinkPreview' : null)),
        home: Scaffold(
            body: MediaQuery(
                data: MediaQueryData.fromView(
                        WidgetsBinding.instance.platformDispatcher.views.first)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: RepaintBoundary(
                    key: paint,
                    child: Column(children: [
                      HomeDeskTitleBar(
                          brand: 'NestLink',
                          inSettings: false,
                          maximized: false,
                          canMaximize: false,
                          onHome: () => HomeDeskDashboard.navigate('devices'),
                          onDrag: () {},
                          onMaximize: () {},
                          onMinimize: () {},
                          onClose: () {}),
                      Expanded(
                          child: HomeDeskDashboard(
                              brandName: 'NestLink',
                              devicesBuilder: (_) => HomeDeskFamilyDevices(
                                  account: account,
                                  listLayout: true,
                                  onLogin: () {},
                                  onConnect: onConnect ?? (_) {},
                                  readOption: family.option),
                              recentBuilder: (_) => const SizedBox(),
                              servicesBuilder: (_) => const SizedBox(),
                              remoteSettingsBuilder: (_) =>
                                  NestLinkRemoteSettings(
                                      readOption: (_) => '',
                                      remoteReady: () => true,
                                      hasRemotePassword: () async => false,
                                      initiallyLocked: false),
                              remoteCredentialsBuilder: (_) =>
                                  const Text('合成一次性密码 demo42'),
                              statusBuilder: (_) => const SizedBox(),
                              onSettings: () {},
                              onConnect: (_) {})),
                    ])))));

void main() {
  testWidgets(
      'desktop keeps three tabs and bottom account; credentials and settings are inline',
      (tester) async {
    tester.view.physicalSize = const Size(1120, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final account = HomeDeskAccount(), api = DesktopApi();
    account.publish(api, directory(), family.one, (_) async {});
    String? connected;
    await tester.pumpWidget(app(account, onConnect: (id) => connected = id));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('device-group-computer')), findsOneWidget);
    final searchRect =
        tester.getRect(find.byKey(const ValueKey('device-search')));
    final refreshRect =
        tester.getRect(find.byKey(const ValueKey('family-refresh')));
    expect(searchRect.top, closeTo(refreshRect.top, .1));
    expect(searchRect.bottom, closeTo(refreshRect.bottom, .1));
    expect(
        find
            .descendant(
                of: find.byKey(const ValueKey('nav-services')),
                matching: find.byType(Text))
            .evaluate()
            .map((e) => (e.widget as Text).data)
            .toList(),
        ['内网穿透']);
    expect(find.byKey(const ValueKey('device-group-mobile')), findsOneWidget);
    expect(find.byKey(const ValueKey('family-connect-${family.one}')),
        findsNothing);
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('family-connect-$offline')))
            .onPressed,
        isNull);
    await tester
        .tap(find.byKey(const ValueKey('family-connect-${family.two}')));
    expect(connected, '987654321');
    await tester.enterText(
        find.byKey(const ValueKey('device-search')), '246813');
    await tester.pump();
    expect(find.byKey(const ValueKey('device-row-$phone')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('device-row-${family.two}')), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('device-search')), '');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('device-group-computer')));
    await tester.pump();
    expect(
        find.byKey(const ValueKey('device-row-${family.two}')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('device-group-computer')));
    await tester.pump();
    expect(find.text('我的设备'), findsNothing);
    expect(find.byKey(const ValueKey('nav-local')), findsNothing);
    expect(find.byKey(const ValueKey('nav-favorites')), findsNothing);
    expect(find.byIcon(Icons.star_rounded), findsNothing);
    expect(find.text('全部设备'), findsNothing);
    expect(find.text('开始协助'), findsNothing);
    expect(find.text('连接服务'), findsNothing);
    final nav = find.byKey(const ValueKey('nav-main-scroll'));
    expect(find.descendant(of: nav, matching: find.byType(TextButton)),
        findsNWidgets(3));
    expect(
        tester.getTopLeft(find.byKey(const ValueKey('nav-devices'))).dy,
        lessThan(
            tester.getTopLeft(find.byKey(const ValueKey('nav-remote'))).dy));
    expect(
        tester.getTopLeft(find.byKey(const ValueKey('nav-remote'))).dy,
        lessThan(
            tester.getTopLeft(find.byKey(const ValueKey('nav-services'))).dy));
    expect(find.byKey(const ValueKey('nav-account')).hitTestable(),
        findsOneWidget);
    expect(
        tester.getTopLeft(find.byKey(const ValueKey('nav-account'))).dy,
        greaterThan(tester
            .getBottomLeft(find.byKey(const ValueKey('nav-services')))
            .dy));
    expect(find.byKey(const ValueKey('nav-settings')), findsNothing);
    expect(
        find.byKey(const ValueKey('device-row-${family.two}')), findsOneWidget);
    expect(find.byKey(const ValueKey('device-row-$phone')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('device-info-${family.one}')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('device-sharing-${family.one}')),
        findsNothing);
    await tester.tap(find.widgetWithText(TextButton, '关闭'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nav-remote')));
    await tester.pumpAndSettle();
    expect(find.text('合成一次性密码 demo42'), findsOneWidget);
    expect(find.text('共享与授权'), findsNothing);
    expect(find.byKey(const ValueKey('title-settings')), findsNothing);
    expect(find.byKey(const ValueKey('title-account')), findsNothing);
    final idRect =
        tester.getRect(find.byKey(const ValueKey('remote-device-id')));
    final connectRect =
        tester.getRect(find.byKey(const ValueKey('remote-connect')));
    expect(idRect.top, closeTo(connectRect.top, .1));
    expect(idRect.bottom, closeTo(connectRect.bottom, .1));
    expect(
        find.byKey(const ValueKey('settings-remote-password')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('remote-settings-toggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('settings-edit-remote-password')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('settings-host-authorization')),
        findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('nav-account')));
    await tester.pumpAndSettle();
    expect(find.text('账号与设置'), findsOneWidget);
    expect(
        find.byKey(const ValueKey('settings-remote-password')), findsNothing);
    expect(find.byKey(const ValueKey('settings-host-authorization')),
        findsNothing);
    expect(find.byKey(const ValueKey('account-sign-out')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    account.dispose();
    api.close();
  });

  testWidgets('manual connection cannot submit for a replaced account',
      (tester) async {
    final account = HomeDeskAccount(), api = DesktopApi(), next = DesktopApi();
    account.publish(api, directory(), family.one, (_) async {});
    var connections = 0;
    await tester.pumpWidget(app(account, onConnect: (_) => connections++));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('device-manual-connect')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.descendant(
            of: find.byType(NestLinkDialog), matching: find.byType(TextField)),
        '123456789');
    account.publish(next, directory(), family.one, (_) async {});
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '连接设备'));
    await tester.pumpAndSettle();
    expect(connections, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    account.dispose();
    api.close();
    next.close();
  });

  testWidgets('a saved row action cannot connect after account replacement',
      (tester) async {
    tester.view.physicalSize = const Size(1120, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final account = HomeDeskAccount(), api = DesktopApi();
    account.publish(api, directory(), family.one, (_) async {});
    var connections = 0;
    await tester.pumpWidget(app(account, onConnect: (_) => connections++));
    await tester.pumpAndSettle();
    final staleAction = tester
        .widget<FilledButton>(
            find.byKey(const ValueKey('family-connect-${family.two}')))
        .onPressed;
    account.clear(api);
    final next = DesktopApi()
      ..result = HomeTunnelCatalog(devices: [], services: [])
      ..bindings = [];
    account.publish(next, next.result, '', (_) async {});
    staleAction!();
    expect(connections, 0);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    account.dispose();
    api.close();
    next.close();
  });

  testWidgets('directory remains usable at narrow width with double-sized text',
      (tester) async {
    tester.view.physicalSize = const Size(560, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final account = HomeDeskAccount(), api = DesktopApi();
    account.publish(api, directory(), family.one, (_) async {});
    await tester.pumpWidget(app(account, scale: 2));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('device-row-$phone')), 140,
        scrollable: find.byType(Scrollable).first);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    account.dispose();
    api.close();
  });

  if (Platform.environment.containsKey('NESTLINK_UI_PREVIEW')) {
    testWidgets(
        'export the actual desktop widgets using synthetic account data',
        (tester) async {
      tester.view.physicalSize = const Size(1120, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final font = FontLoader('NestLinkPreview')
        ..addFont(Future.value(ByteData.sublistView(
            File('C:/Windows/Fonts/msyh.ttc').readAsBytesSync())));
      await font.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(Future.value(ByteData.sublistView(File(
                'R:/toolchains/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf')
            .readAsBytesSync())));
      await icons.load();
      for (final dark in [false, true]) {
        final account = HomeDeskAccount(),
            api = DesktopApi(),
            paint = GlobalKey();
        account.publish(api, directory(), family.one, (_) async {});
        await tester
            .pumpWidget(app(account, dark: dark, paint: paint, preview: true));
        await tester.pumpAndSettle();
        final boundary =
            paint.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final output = Directory(Platform.environment['NESTLINK_UI_PREVIEW']!)
            ..createSync(recursive: true);
          File('${output.path}/desktop-${dark ? 'dark' : 'light'}.png')
              .writeAsBytesSync(bytes!.buffer.asUint8List());
          image.dispose();
        });
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        account.dispose();
        api.close();
      }
    });
  }
}
