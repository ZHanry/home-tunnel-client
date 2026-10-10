import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/homedesk_account.dart';
import 'package:flutter_hbb/homedesk_dashboard.dart';
import 'package:flutter_hbb/homedesk_mobile_shell.dart';
import 'package:flutter_hbb/homedesk_services.dart';
import 'package:flutter_hbb/homedesk_theme.dart';
import 'package:flutter_hbb/nestlink_remote_credentials.dart';
import 'package:flutter_hbb/nestlink_remote_settings.dart';

import 'homedesk_family_devices_test.dart' as family;
import 'homedesk_services_test.dart' as portal;

class MobileApi extends family.FamilyApi {
  MobileApi() {
    signedIn = true;
  }
  @override
  Future<Map<String, dynamic>> accountSummary() async => {};
  @override
  Future<List<Map<String, dynamic>>> managementSessions() async => [];
  @override
  Future<Map<String, dynamic>> releaseUpdate(String component) async => {};
}

Widget mobileHome(
  HomeDeskAccount account, {
  required TextEditingController id,
  required TextEditingController password,
  GlobalKey? paint,
  ValueChanged<String>? onConnect,
  WidgetBuilder? services,
  double scale = 1,
  double keyboard = 0,
  bool dark = false,
}) =>
    MaterialApp(
        theme: homeDeskTheme(ThemeData(
            platform: TargetPlatform.android,
            brightness: dark ? Brightness.dark : Brightness.light,
            fontFamily: const bool.fromEnvironment('NESTLINK_MOBILE_PREVIEW')
                ? 'NestLinkPreview'
                : null)),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(scale),
                viewInsets: EdgeInsets.only(bottom: keyboard)),
            child: child!),
        home: RepaintBoundary(
            key: paint,
            child: NestLinkMobileHome(
              account: account,
              readOption: family.option,
              onConnect: onConnect ?? (_) {},
              servicesBuilder:
                  services ?? (_) => const Center(child: Text('测试设备上的穿透服务')),
              recentBuilder: (_) => const Text('最近连接：书房电脑'),
              localBuilder: (_) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    NestLinkRemoteCredentials(
                        id: id,
                        password: password,
                        incomingEnabled: true,
                        showTemporaryPassword: true,
                        passwordHint: '连接时由本机确认',
                        onCopyId: () {},
                        onRefreshPassword: () {}),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                        style: FilledButton.styleFrom(
                            minimumSize: Size.fromHeight(
                                homeDeskControlHeight(_, minimum: 48))),
                        onPressed: () {},
                        icon: const Icon(Icons.mobile_screen_share_outlined),
                        label: const Text('共享本机屏幕')),
                    const Text('共享前需确认 Android 系统屏幕录制授权。'),
                  ]),
            )));

Future<void> capture(WidgetTester tester, GlobalKey paint, String name) async {
  if (!const bool.fromEnvironment('NESTLINK_MOBILE_PREVIEW')) return;
  await tester.runAsync(() async {
    final boundary =
        paint.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final folder = Directory('../../outputs/mobile14')
      ..createSync(recursive: true);
    await File('${folder.path}/$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

Future<void> press(WidgetTester tester, String key) async {
  final target = find.byKey(ValueKey(key));
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'production mobile home keeps device directory, account and native controls across widths',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    if (const bool.fromEnvironment('NESTLINK_MOBILE_PREVIEW')) {
      await (FontLoader('NestLinkPreview')
            ..addFont(Future.value(ByteData.sublistView(
                File('C:/Windows/Fonts/msyh.ttc').readAsBytesSync()))))
          .load();
      await (FontLoader('MaterialIcons')
            ..addFont(Future.value(ByteData.sublistView(File(
                    'D:/代码/远程控制/.work/12.0.0-RC1/toolchains/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf')
                .readAsBytesSync()))))
          .load();
    }
    for (final size in [
      const Size(320, 800),
      const Size(360, 780),
      const Size(412, 900),
      const Size(760, 1024),
      const Size(1024, 768)
    ]) {
      for (final dark in [false, true]) {
        tester.view.physicalSize = size;
        final account = HomeDeskAccount(), api = MobileApi();
        final id = TextEditingController(text: '123456789'),
            otp = TextEditingController(text: 'demo42');
        final paint = GlobalKey();
        account.publish(api, family.catalog(), family.one, (_) async {});
        await tester.pumpWidget(mobileHome(account,
            id: id,
            password: otp,
            paint: paint,
            scale: size.width == 360 ? 2 : 1,
            dark: dark));
        await tester.pumpAndSettle();
        expect(
            find.byKey(ValueKey('device-row-${family.two}')), findsOneWidget);
        expect(find.byKey(const ValueKey('mobile-navigation')),
            size.width < 760 ? findsOneWidget : findsNothing);
        expect(find.byKey(const ValueKey('nav-account')),
            size.width >= 760 ? findsOneWidget : findsNothing);
        expect(tester.takeException(), isNull);
        final suffix = '${size.width.toInt()}-${dark ? 'dark' : 'light'}';
        await capture(tester, paint, 'devices-$suffix');
        HomeDeskDashboard.navigate('remote');
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('remote-credentials-id')),
            findsOneWidget);
        expect(find.byKey(const ValueKey('remote-credentials-password')),
            findsOneWidget);
        expect(find.text('共享本机屏幕'), findsOneWidget);
        await capture(tester, paint, 'remote-$suffix');
        await press(
            tester, size.width < 760 ? 'mobile-account' : 'nav-account');
        expect(find.byKey(const ValueKey('account-sign-out')), findsOneWidget);
        expect(tester.takeException(), isNull);
        await capture(tester, paint, 'account-$suffix');
        await tester.pumpWidget(const SizedBox());
        account.dispose();
        api.close();
        id.dispose();
        otp.dispose();
      }
    }
  });

  testWidgets(
      'phone keyboard and account changes cannot reuse a remote ID draft',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final account = HomeDeskAccount(),
        first = MobileApi(),
        second = MobileApi();
    final id = TextEditingController(text: '123456789'),
        otp = TextEditingController(text: 'demo42');
    account.publish(first, family.catalog(), family.one, (_) async {});
    var connections = 0;
    await tester.pumpWidget(mobileHome(account,
        id: id, password: otp, keyboard: 280, onConnect: (_) => connections++));
    await tester.pumpAndSettle();
    HomeDeskDashboard.navigate('remote');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('remote-device-id')));
    await tester.enterText(
        find.byKey(const ValueKey('remote-device-id')), '987654321');
    await press(tester, 'remote-connect');
    expect(connections, 1);
    account.publish(second, family.catalog(), family.one, (_) async {});
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('device-row-${family.two}')), findsOneWidget);
    HomeDeskDashboard.navigate('remote');
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('remote-device-id')))
            .controller!
            .text,
        isEmpty);
    await press(tester, 'remote-connect');
    expect(connections, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    account.dispose();
    first.close();
    second.close();
    id.dispose();
    otp.dispose();
  });

  testWidgets(
      'phone login remains reachable above keyboard and then opens device management',
      (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final account = HomeDeskAccount(), api = MobileApi()..signedIn = false;
    final id = TextEditingController(), otp = TextEditingController();
    await tester.pumpWidget(mobileHome(account,
        id: id,
        password: otp,
        keyboard: 250,
        services: (_) => HomeDeskServices(
            account: account,
            readOption: portal.portalOption,
            saveOrigin: (_) async {},
            apiBuilder: (origin, {required isAllowed, credentialStorage}) =>
                api,
            credentialStoreFactory: () => portal.FixtureCredentialStore())));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mobile-navigation')), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('tunnel-origin')),
        'https://console.example.com');
    await tester.enterText(
        find.byKey(const ValueKey('tunnel-username')), 'fixture-user');
    await tester.enterText(
        find.byKey(const ValueKey('tunnel-password')), 'synthetic-password');
    await press(tester, 'tunnel-login');
    expect(api.logins, 1);
    expect(find.byKey(const ValueKey('mobile-navigation')), findsOneWidget);
    expect(find.byKey(ValueKey('device-row-${family.two}')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    account.dispose();
    api.close();
    id.dispose();
    otp.dispose();
  });

  testWidgets(
      'Android security exposes supported host permissions and retains password authorization',
      (tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final writes = <String>[];
    await tester.pumpWidget(MaterialApp(
        theme: homeDeskTheme(ThemeData(platform: TargetPlatform.android)),
        home: Scaffold(
            body: ListView(padding: const EdgeInsets.all(16), children: [
          NestLinkRemoteSettings(
              mobilePlatform: true,
              readOption: (_) => '',
              remoteReady: () => true,
              initiallyLocked: false,
              isOptionFixed: (_) => false,
              hasRemotePassword: () async => false,
              saveOption: (key, value) async => writes.add('$key:$value')),
        ]))));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('settings-edit-remote-password')),
        findsOneWidget);
    await press(tester, 'settings-tab-1');
    expect(find.byKey(ValueKey('settings-$kOptionEnableKeyboard')),
        findsOneWidget);
    expect(find.byKey(ValueKey('settings-$kOptionEnableClipboard')),
        findsOneWidget);
    expect(
        find.byKey(ValueKey('settings-$kOptionEnableTerminal')), findsNothing);
    expect(find.byKey(ValueKey('settings-$kOptionEnableRemotePrinter')),
        findsNothing);
    expect(find.byKey(ValueKey('settings-$kOptionEnableRemoteRestart')),
        findsNothing);
    await press(tester, 'settings-$kOptionEnableClipboard');
    expect(writes, ['$kOptionEnableClipboard:N']);
    await press(tester, 'settings-tab-2');
    expect(find.byKey(const ValueKey('settings-edit-pin')), findsNothing);
    expect(find.text('RDP 会话共享'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'phone password editor keeps confirmation and save visible above keyboard',
      (tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    var saved = 0;
    await tester.pumpWidget(MaterialApp(
        theme: homeDeskTheme(ThemeData()),
        home: Scaffold(
            body: ListView(padding: const EdgeInsets.all(16), children: [
          NestLinkRemoteSettings(
              mobilePlatform: true,
              readOption: (_) => '',
              remoteReady: () => true,
              initiallyLocked: false,
              remoteConfigBlocked: () async => false,
              hasRemotePassword: () async => false,
              saveRemotePassword: (_) async {
                saved++;
                return true;
              }),
        ]))));
    await tester.pumpAndSettle();
    await press(tester, 'settings-edit-remote-password');
    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('settings-remote-password')),
        'synthetic-password');
    await tester.enterText(
        find.byKey(const ValueKey('settings-confirm-remote-password')),
        'synthetic-password');
    final save = find.byKey(const ValueKey('settings-save-remote-password'));
    await tester.ensureVisible(save);
    expect(tester.getRect(save).bottom, lessThanOrEqualTo(460));
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(saved, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
