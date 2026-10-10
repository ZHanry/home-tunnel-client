// HOMEDESK: 仅使用合成设备验证主布局，不读取本机 ID、密码或其他用户数据。
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/homedesk_console_api.dart';
import 'package:flutter_hbb/homedesk_dashboard.dart';
import 'package:flutter_hbb/homedesk_navigation.dart';
import 'package:flutter_hbb/homedesk_devices.dart';
import 'package:flutter_hbb/homedesk_account.dart';
import 'package:flutter_hbb/homedesk_tunnel_api.dart';
import 'package:flutter_hbb/homedesk_family_devices.dart';
import 'package:flutter_hbb/homedesk_services.dart';
import 'homedesk_services_test.dart' as portal;
import 'homedesk_family_devices_test.dart' as family;
import 'package:flutter_hbb/homedesk_recent.dart';
import 'package:flutter_hbb/homedesk_window.dart';
import 'package:flutter_hbb/homedesk_title_bar.dart';
import 'package:flutter_hbb/homedesk_theme.dart';
import 'package:flutter_hbb/models/peer_model.dart';

class PreviewConsole extends HomeDeskConsoleApi {
  final bool empty;
  PreviewConsole({this.empty = false})
      : super('http://192.168.50.10:8080', 'test-only-token');
  @override
  Future<List<Map<String, dynamic>>> devices() async => empty
      ? []
      : [
          {
            'id': 'demo-study',
            'name': '书房电脑',
            'room': '书房',
            'owner': '我的电脑',
            'platform': 'windows',
            'arch': 'x86_64',
            'online': true,
            'wol_configured': true
          },
          {
            'id': 'demo-living',
            'name': '客厅电脑',
            'room': '客厅',
            'owner': '家人共用',
            'platform': 'linux',
            'arch': 'aarch64',
            'online': false,
            'wol_configured': true
          },
        ];
  @override
  Future<void> wake(String id) async {}
}

class _ServiceProbe extends StatefulWidget {
  final VoidCallback onInitialized;
  final VoidCallback onDisposed;
  const _ServiceProbe({required this.onInitialized, required this.onDisposed});

  @override
  State<_ServiceProbe> createState() => _ServiceProbeState();
}

class _ServiceProbeState extends State<_ServiceProbe> {
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.onInitialized();
  }

  @override
  void dispose() {
    widget.onDisposed();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Center(
      child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: TextField(
              controller: _controller,
              decoration: const InputDecoration(labelText: '测试服务会话'))));
}

Widget host(
    {required PreviewConsole? api,
    required GlobalKey<HomeDeskDashboardState> dashboard,
    GlobalKey? paintKey,
    bool dark = false,
    double scale = 1,
    WidgetBuilder? servicesBuilder,
    ValueChanged<String>? onConnect}) {
  return MaterialApp(
    theme: ThemeData(
        brightness: dark ? Brightness.dark : Brightness.light,
        fontFamily: Platform.environment.containsKey('HOMEDESK_UI_PREVIEW')
            ? 'HomeDeskPreview'
            : null),
    home: Scaffold(
        body: MediaQuery(
      data: MediaQueryData.fromView(
              WidgetsBinding.instance.platformDispatcher.views.first)
          .copyWith(textScaler: TextScaler.linear(scale)),
      child: RepaintBoundary(
          key: paintKey,
          child: HomeDeskDashboard(
            key: dashboard,
            brandName: 'HomeDesk',
            devicesBuilder: (_) => HomeDeskDevices(
                api: api,
                readOption: (key) => key == 'homedesk-console-allowed'
                    ? 'Y'
                    : '', // HOMEDESK: 注入设备 API 的布局测试显式授权管理台。
                onConnect: (_, id) => onConnect?.call(id),
                onManualConnect: () =>
                    dashboard.currentState?.showManualConnection()),
            recentBuilder: (_) => const Center(child: Text('最近连接内容')),
            servicesBuilder: servicesBuilder,
            remoteCredentialsBuilder: (_) => const Text('合成一次性密码 demo42'),
            statusBuilder: (_) => const Padding(
                padding: EdgeInsets.all(14),
                child: Row(children: [
                  Icon(Icons.circle, size: 8, color: Color(0xFFE04F5F)),
                  SizedBox(width: 10),
                  Expanded(child: Text('家庭连接服务未就绪，请检查网络设置', maxLines: 2))
                ])),
            onSettings: () {},
            onConnect: onConnect ?? (_) {},
          )),
    )),
  );
}

void main() {
  test('fixed workspace fits laptop and scaled desktop work areas', () {
    expect(
        nestLinkWorkspaceSize(const Size(1920, 1040)), const Size(1120, 760));
    expect(nestLinkWorkspaceSize(const Size(1366, 728)), const Size(1120, 696));
    expect(nestLinkWorkspaceSize(const Size(960, 520)), const Size(928, 488));
  });
  testWidgets(
      'fixed title bar keeps minimize and close without maximize or double-click resize',
      (tester) async {
    var minimized = 0, maximized = 0;
    await tester.pumpWidget(MaterialApp(
        theme: homeDeskTheme(ThemeData()),
        home: Scaffold(
            body: HomeDeskTitleBar(
                brand: 'nestlink',
                inSettings: false,
                maximized: false,
                canMaximize: false,
                onHome: () {},
                onDrag: () {},
                onMaximize: () => maximized++,
                onMinimize: () => minimized++,
                onClose: () {}))));
    expect(find.byTooltip('最大化窗口'), findsNothing);
    await tester.tap(find.byTooltip('最小化到系统托盘'));
    expect(minimized, 1);
    await tester.tap(find.text('NestLink'));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(find.text('NestLink'));
    expect(maximized, 0);
    expect(find.byTooltip('关闭窗口'), findsOneWidget);
  });
  testWidgets('未登录隐藏侧栏，登录显示，账号页退出回到登录并保留会话所有者', (tester) async {
    final account = HomeDeskAccount();
    final api = portal.PortalFixtureApi();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: HomeDeskDashboard(
      brandName: 'NestLink',
      initializeAccount: true,
      devicesBuilder: (_) => HomeDeskFamilyDevices(
          account: account,
          onLogin: () {},
          onConnect: (_) {},
          readOption: portal.portalOption),
      servicesBuilder: (_) => HomeDeskServices(
          account: account,
          readOption: portal.portalOption,
          saveOrigin: (_) async {},
          credentialStoreFactory: () => portal.FixtureCredentialStore(),
          apiBuilder: (_, {required isAllowed, credentialStorage}) => api),
      recentBuilder: (_) => const SizedBox(),
      localBuilder: (_) => const SizedBox(),
      statusBuilder: (_) => const SizedBox(),
      onSettings: () {},
      onConnect: (_) {},
    ))));
    await tester.pumpAndSettle();
    expect(account.signedIn, isFalse);
    expect(find.byType(HomeDeskNavigation, skipOffstage: false), findsNothing);
    HomeDeskDashboard.navigate('account');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('account-settings-scroll')), findsNothing);
    expect(find.byKey(const ValueKey('tunnel-login')), findsOneWidget);
    await portal.enterCredentials(tester);
    await tester.pumpAndSettle();
    expect(account.signedIn, isTrue);
    expect(api.closed, isFalse);
    expect(find.byKey(const ValueKey('nav-account')).hitTestable(),
        findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('nav-remote')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('remote-device-id')), findsOneWidget);
    expect(find.byType(HomeDeskServices, skipOffstage: false), findsOneWidget);
    await tester.pump(const Duration(seconds: 12));
    expect(account.signedIn, isTrue);
    expect(api.closed, isFalse);
    await tester.tap(find.byKey(const ValueKey('nav-account')));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('account-settings-scroll')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('account-sign-out')));
    await tester.pumpAndSettle();
    expect(account.signedIn, isFalse);
    expect(find.byType(HomeDeskNavigation, skipOffstage: false), findsNothing);
    expect(find.byKey(const ValueKey('tunnel-login')).hitTestable(),
        findsOneWidget);
    expect(find.byKey(const ValueKey('account-settings-scroll')), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    account.dispose();
    expect(api.closed, isTrue);
  });

  testWidgets('远控首页校验设备ID并直接显示凭据，无共享弹窗', (tester) async {
    tester.view.physicalSize = const Size(1080, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey<HomeDeskDashboardState>();
    String? connected;
    await tester.pumpWidget(host(
        api: PreviewConsole(),
        dashboard: key,
        onConnect: (id) => connected = id));
    await tester.pump();
    expect(find.text('合成一次性密码 demo42'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('nav-remote')));
    await tester.pump();
    expect(find.text('家庭连接服务未就绪，请检查网络设置'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('remote-connect')));
    await tester.pump();
    expect(connected, isNull);
    expect(find.text('请输入有效的设备 ID'), findsOneWidget);
    await tester.enterText(
        find.byKey(const ValueKey('remote-device-id')), '123456');
    await tester.tap(find.byKey(const ValueKey('remote-connect')));
    await tester.pumpAndSettle();
    expect(connected, '123456');
    expect(find.text('合成一次性密码 demo42'), findsOneWidget);
    expect(find.text('共享与授权'), findsNothing);
    expect(find.byTooltip('本机共享'), findsNothing);
    HomeDeskDashboard.navigate('local');
    await tester.pumpAndSettle();
    expect(find.text('最近连接内容'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('移动导航设备空状态居中且保留连接入口，双倍字体可用', (tester) async {
    tester.view.physicalSize = const Size(560, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(host(
        api: PreviewConsole(empty: true),
        dashboard: GlobalKey<HomeDeskDashboardState>(),
        scale: 2));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('nav-devices')));
    await tester.pumpAndSettle();
    expect(find.text('从连接第一台电脑开始'), findsOneWidget);
    expect(find.text('手动连接'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('设备目录按房间筛选', (tester) async {
    tester.view.physicalSize = const Size(1080, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(host(
        api: PreviewConsole(), dashboard: GlobalKey<HomeDeskDashboardState>()));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('nav-devices')));
    await tester.pump();
    await tester.tap(find.widgetWithText(ChoiceChip, '书房'));
    await tester.pump();
    expect(find.text('书房电脑'), findsOneWidget);
    expect(find.text('客厅电脑'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('穿透页按需初始化，导航切换保留会话和设备筛选', (tester) async {
    tester.view.physicalSize = const Size(1080, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var initialized = 0;
    var disposed = 0;
    await tester.pumpWidget(host(
        api: PreviewConsole(),
        dashboard: GlobalKey<HomeDeskDashboardState>(),
        servicesBuilder: (_) => _ServiceProbe(
            onInitialized: () => initialized++, onDisposed: () => disposed++)));
    await tester.pump();
    expect(initialized, 0);
    await tester.tap(find.byKey(const ValueKey('nav-devices')));
    await tester.pump();
    final deviceState = tester.state(find.byType(HomeDeskDevices));
    await tester.tap(find.widgetWithText(ChoiceChip, '书房'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('nav-services')));
    await tester.pumpAndSettle();
    expect(initialized, 1);
    expect(find.text('家庭连接服务未就绪，请检查网络设置'), findsNothing);
    await tester.enterText(find.byType(TextField), '测试会话保留');
    await tester.tap(find.byKey(const ValueKey('nav-devices')));
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(HomeDeskDevices)), same(deviceState));
    expect(find.text('书房电脑'), findsOneWidget);
    expect(find.text('客厅电脑'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('nav-remote')));
    await tester.pumpAndSettle();
    expect(find.text('最近连接内容'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('nav-services')));
    await tester.pumpAndSettle();
    expect(find.text('测试会话保留'), findsOneWidget);
    expect(initialized, 1);
    expect(disposed, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    expect(disposed, 1);
  });

  testWidgets('穿透页窄窗口双倍字体可用', (tester) async {
    tester.view.physicalSize = const Size(560, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(host(
        api: PreviewConsole(empty: true),
        dashboard: GlobalKey<HomeDeskDashboardState>(),
        scale: 2,
        servicesBuilder: (_) => const Center(child: Text('合成穿透服务'))));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('nav-services')));
    await tester.pumpAndSettle();
    expect(find.text('合成穿透服务'), findsOneWidget);
    expect(find.byKey(const ValueKey('remote-device-id')), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  if (Platform.environment.containsKey('HOMEDESK_UI_PREVIEW')) {
    testWidgets('导出合成设备的深浅色预览', (tester) async {
      tester.view.physicalSize = const Size(1120, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final loader = FontLoader('HomeDeskPreview');
      loader.addFont(Future.value(ByteData.sublistView(
          File('C:/Windows/Fonts/msyh.ttc').readAsBytesSync())));
      await loader.load();
      final icons = FontLoader('MaterialIcons');
      icons.addFont(Future.value(ByteData.sublistView(File(
              'R:/toolchains/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf')
          .readAsBytesSync())));
      await icons.load();
      for (final sample in ['light', 'dark', 'empty']) {
        final dark = sample != 'light';
        final key = GlobalKey<HomeDeskDashboardState>();
        final paint = GlobalKey();
        final account = HomeDeskAccount();
        final api = family.FamilyApi()..signedIn = true;
        if (sample == 'empty') {
          api.result = HomeTunnelCatalog(devices: [], services: []);
          api.bindings = [];
        }
        account.publish(api, api.result, family.one, (_) async {});
        await tester.pumpWidget(MaterialApp(
            theme: ThemeData(
                brightness: dark ? Brightness.dark : Brightness.light,
                fontFamily: 'HomeDeskPreview'),
            home: Scaffold(
                body: RepaintBoundary(
                    key: paint,
                    child: HomeDeskDashboard(
                      key: key,
                      brandName: 'nestlink',
                      devicesBuilder: (_) => HomeDeskFamilyDevices(
                          account: account,
                          onLogin: () {},
                          onConnect: (_) {},
                          readOption: family.option),
                      recentBuilder: (_) => HomeDeskRecent(
                          recent: sample == 'empty'
                              ? []
                              : [
                                  Peer.fromJson({
                                    'id': '987654321',
                                    'alias': '书房电脑',
                                    'platform': 'Windows',
                                    'online': true
                                  }),
                                  Peer.fromJson({
                                    'id': '246813579',
                                    'alias': 'Linux 工作站',
                                    'platform': 'Linux',
                                    'online': false
                                  })
                                ],
                          onLoad: (_) {},
                          onQueryOnline: (_) {}),
                      servicesBuilder: (_) => const SizedBox.shrink(),
                      localBuilder: (_) => const SizedBox.shrink(),
                      statusBuilder: (_) => const SizedBox.shrink(),
                      onSettings: () {},
                      onConnect: (_) {},
                    )))));
        await tester.pumpAndSettle();
        final boundary =
            paint.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final root = Directory(Platform.environment['HOMEDESK_UI_PREVIEW']!)
            ..createSync(recursive: true);
          File('${root.path}/dashboard-$sample.png')
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
