// HOMEDESK: 合成账号设备验证自动目录与跨账号隔离，不连接真实设备。
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/homedesk_account.dart';
import 'package:flutter_hbb/homedesk_dashboard.dart';
import 'package:flutter_hbb/homedesk_family_devices.dart';
import 'package:flutter_hbb/homedesk_services.dart';
import 'package:flutter_hbb/homedesk_tunnel_api.dart';
import 'homedesk_services_test.dart' as portal;

const one = '20000000-0000-4000-8000-000000000001';
const two = '20000000-0000-4000-8000-000000000002';
HomeTunnelCatalog catalog() => HomeTunnelCatalog(devices: const [
      HomeTunnelDevice(
          id: one, name: '我的电脑', platform: 'windows', online: true),
      HomeTunnelDevice(
          id: two, name: '卧室电脑', platform: 'windows', online: true),
    ], services: []);

class FamilyApi extends portal.PortalFixtureApi {
  Completer<List<HomeDeskRemoteBinding>>? pending;
  List<HomeDeskRemoteBinding> bindings = [
    HomeDeskRemoteBinding(
        deviceId: one,
        remoteId: '123456789',
        server: 'relay.example.com:21116',
        keySHA256: 'a' * 64,
        platform: 'windows',
        online: true),
    HomeDeskRemoteBinding(
        deviceId: two,
        remoteId: '987654321',
        server: 'relay.example.com:21116',
        keySHA256: 'a' * 64,
        platform: 'windows',
        online: true),
  ];
  FamilyApi() {
    result = catalog();
  }
  @override
  Future<List<HomeDeskRemoteBinding>> remoteBindings() async {
    if (pending != null) return pending!.future;
    return bindings;
  }
}

String option(String key) => key == 'homedesk-remote-profile'
    ? jsonEncode({'server': 'relay.example.com:21116', 'key_sha256': 'a' * 64})
    : 'N';

Widget familyHost(HomeDeskAccount state, ValueChanged<String> connect,
        {double scale = 1}) =>
    MaterialApp(
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!),
        home: Scaffold(
            body: Padding(
                padding: const EdgeInsets.all(16),
                child: HomeDeskFamilyDevices(
                    account: state,
                    onLogin: () {},
                    onConnect: connect,
                    readOption: option))));

void main() {
  testWidgets('同账号两台设备自动出现，按关联远控ID连接，本机不提供连接按钮', (tester) async {
    final state = HomeDeskAccount(), api = FamilyApi()..signedIn = true;
    state.publish(api, catalog(), one, (_) async {});
    String? connected;
    await tester.pumpWidget(familyHost(state, (id) => connected = id));
    await tester.pumpAndSettle();
    expect(find.text('我的电脑'), findsOneWidget);
    expect(find.text('卧室电脑'), findsOneWidget);
    expect(find.byKey(const ValueKey('family-connect-$one')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('family-connect-$two')));
    expect(connected, '987654321');
    expect(connected, isNot(two));
    await tester.pumpWidget(const SizedBox());
    state.dispose();
    api.close();
  });

  testWidgets('退出或切换账号后迟到目录不恢复，旧按钮不能连接旧账号设备', (tester) async {
    final state = HomeDeskAccount(), old = FamilyApi()..signedIn = true;
    state.publish(old, catalog(), one, (_) async {});
    var connected = 0;
    await tester.pumpWidget(familyHost(state, (_) => connected++));
    await tester.pumpAndSettle();
    final staleAction = tester
        .widget<FilledButton>(find.byKey(const ValueKey('family-connect-$two')))
        .onPressed;
    old.pending = Completer<List<HomeDeskRemoteBinding>>();
    final loading = state.refresh();
    await tester.pump();
    state.clear(old);
    final newer = FamilyApi()
      ..signedIn = true
      ..bindings = []
      ..result = HomeTunnelCatalog(devices: [], services: []);
    state.publish(
        newer, HomeTunnelCatalog(devices: [], services: []), '', (_) async {});
    staleAction!();
    expect(connected, 0);
    old.pending!.complete(old.bindings);
    await loading;
    await tester.pumpAndSettle();
    expect(state.bindings, isEmpty);
    expect(find.text('卧室电脑'), findsNothing);
    state.clear(newer);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('family-login')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    state.dispose();
    old.close();
    newer.close();
  });

  testWidgets('登录服务页后家庭设备共享会话，退出后目录立即清空', (tester) async {
    final state = HomeDeskAccount(), api = FamilyApi();
    final dashboard = GlobalKey<HomeDeskDashboardState>();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: HomeDeskDashboard(
                key: dashboard,
                brandName: 'HomeDesk',
                devicesBuilder: (_) => HomeDeskFamilyDevices(
                    account: state,
                    onLogin: () => dashboard.currentState!.showAccount(),
                    onConnect: (_) {},
                    readOption: option),
                recentBuilder: (_) => const SizedBox(),
                localBuilder: (_) => const SizedBox(),
                statusBuilder: (_) => const SizedBox(),
                onSettings: () {},
                onConnect: (_) {},
                servicesBuilder: (_) => HomeDeskServices(
                    account: state,
                    readOption: portal.portalOption,
                    saveOrigin: (_) async {},
                    credentialStoreFactory: () =>
                        portal.FixtureCredentialStore(),
                    apiBuilder: (origin,
                            {required isAllowed, credentialStorage}) =>
                        api)))));
    await tester.tap(find.byKey(const ValueKey('family-login')));
    await tester.pumpAndSettle();
    await portal.enterCredentials(tester);
    await tester.tap(find.byTooltip('家庭设备'));
    await tester.pumpAndSettle();
    expect(find.text('卧室电脑'), findsOneWidget);
    expect(api.logins, 1);
    await tester.tap(find.byTooltip('家庭服务'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tunnel-account-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('退出登录'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('家庭设备'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('family-login')), findsOneWidget);
    expect(find.text('卧室电脑'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    state.dispose();
  });

  testWidgets('不同服务器配置禁止直接连接，窄窗口双倍字体不溢出', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = HomeDeskAccount(), api = FamilyApi()..signedIn = true;
    api.bindings = [
      const HomeDeskRemoteBinding(
          deviceId: two,
          remoteId: '987654321',
          server: 'other.example.com:21116',
          keySHA256:
              'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
          platform: 'windows',
          online: true)
    ];
    state.publish(api, catalog(), one, (_) async {});
    await tester.pumpWidget(familyHost(state, (_) {}, scale: 2));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('family-connect-$two')), 160,
        scrollable: find.byType(Scrollable).first);
    final button = tester.widget<FilledButton>(
        find.byKey(const ValueKey('family-connect-$two')));
    expect(button.onPressed, isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    state.dispose();
    api.close();
  });

  testWidgets('首页只恢复已记住的账号，恢复后自动显示家庭设备', (tester) async {
    final state = HomeDeskAccount(), api = FamilyApi();
    final store = portal.FixtureCredentialStore(
        supported: true, record: portal.rememberedFixture());
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: HomeDeskDashboard(
                initializeAccount: true,
                brandName: 'HomeDesk',
                devicesBuilder: (_) => HomeDeskFamilyDevices(
                    account: state,
                    onLogin: () {},
                    onConnect: (_) {},
                    readOption: option),
                recentBuilder: (_) => const SizedBox(),
                localBuilder: (_) => const SizedBox(),
                statusBuilder: (_) => const SizedBox(),
                onSettings: () {},
                onConnect: (_) {},
                servicesBuilder: (_) => HomeDeskServices(
                    account: state,
                    readOption: portal.portalOption,
                    credentialStoreFactory: () => store,
                    saveOrigin: (_) async {},
                    apiBuilder: (origin,
                            {required isAllowed, credentialStorage}) =>
                        api)))));
    await tester.pumpAndSettle();
    expect(api.restores, 1);
    expect(api.logins, 0);
    expect(find.text('卧室电脑'), findsOneWidget);
    expect(state.signedIn, isTrue);
    await tester.pumpWidget(const SizedBox());
    state.dispose();
  });
}
