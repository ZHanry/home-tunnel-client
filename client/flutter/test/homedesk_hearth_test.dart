// HOMEDESK: 暖居响应式检查与 HOMEDESK_UI_PREVIEW 导出均使用合成数据。
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/homedesk_account.dart';
import 'package:flutter_hbb/homedesk_dashboard.dart';
import 'package:flutter_hbb/homedesk_family_devices.dart';
import 'package:flutter_hbb/homedesk_recent.dart';
import 'package:flutter_hbb/homedesk_services.dart';
import 'package:flutter_hbb/homedesk_settings_shell.dart';
import 'package:flutter_hbb/homedesk_status.dart';
import 'package:flutter_hbb/homedesk_theme.dart';
import 'package:flutter_hbb/homedesk_title_bar.dart';
import 'package:flutter_hbb/homedesk_tunnel_api.dart';
import 'package:flutter_hbb/models/peer_model.dart';
import 'package:flutter_hbb/models/peer_tab_model.dart';
import 'package:flutter_hbb/desktop/widgets/material_mod_popup_menu.dart'
    as peer_menu;
import 'homedesk_family_devices_test.dart' as family;
import 'homedesk_services_test.dart' as portal;

const third = '20000000-0000-4000-8000-000000000003';
const fourth = '20000000-0000-4000-8000-000000000004';
HomeTunnelCatalog hearthCatalog() => HomeTunnelCatalog(
        devices: const [
          HomeTunnelDevice(
              id: family.one, name: '书房电脑', platform: 'windows', online: true),
          HomeTunnelDevice(
              id: family.two, name: '儿童房电脑', platform: 'windows', online: true),
          HomeTunnelDevice(
              id: third, name: '客厅电脑', platform: 'linux', online: false),
          HomeTunnelDevice(
              id: fourth, name: '家庭 NAS', platform: 'linux', online: true),
        ],
        services: [
          HomeTunnelService(
              id: 'hearth-web',
              deviceId: family.one,
              name: '家庭相册',
              proxyType: 'http',
              status: 'Online',
              webUrl: Uri.parse('https://album.example.com'),
              endpoint: null,
              enabled: true,
              localHost: '127.0.0.1',
              localPort: 8080),
          const HomeTunnelService(
              id: 'hearth-tcp',
              deviceId: family.one,
              name: '文件共享',
              proxyType: 'tcp',
              status: 'Online',
              webUrl: null,
              endpoint: 'edge.example.com:10000',
              enabled: true,
              localHost: '127.0.0.1',
              localPort: 445),
          HomeTunnelService(
              id: 'hearth-paused',
              deviceId: fourth,
              name: '媒体中心',
              proxyType: 'https',
              status: 'Disabled',
              webUrl: Uri.parse('https://media.example.com'),
              endpoint: null,
              enabled: false,
              localHost: '127.0.0.1',
              localPort: 8096),
          const HomeTunnelService(
              id: 'hearth-error',
              deviceId: fourth,
              name: '终端服务',
              proxyType: 'tcp',
              status: 'Error',
              webUrl: null,
              endpoint: null,
              enabled: true,
              localHost: '127.0.0.1',
              localPort: 22),
        ],
        capabilities: const HomeTunnelCapabilities(
            tcpCanCreate: true, udpCanCreate: true));

class HearthApi extends family.FamilyApi {
  HearthApi() {
    result = hearthCatalog();
    bindings = [
      ...bindings,
      HomeDeskRemoteBinding(
          deviceId: third,
          remoteId: '327418605',
          server: 'relay.example.com:21116',
          keySHA256: 'a' * 64,
          platform: 'linux',
          online: false)
    ];
  }
}

List<Peer> recentFixture() => [
      Peer.fromJson(
          {'id': '987654321', 'alias': '儿童房电脑', 'platform': 'Windows'})
        ..online = true,
      Peer.fromJson({'id': '327418605', 'alias': '客厅电脑', 'platform': 'Linux'}),
    ];
Future<List<peer_menu.PopupMenuEntry<String>>> previewPeerMenu(
        BuildContext context, Peer peer, PeerTabIndex tab) async =>
    ['文件传输', '终端', 'TCP 隧道', 'RDP', '重命名', '忘记密码', '删除记录']
        .map((label) => peer_menu.PopupMenuItem<String>(
            value: label, onTap: () {}, child: Text(label)))
        .toList();
Widget settingsFixture(HomeDeskAccount account) => HomeDeskSettingsShell(
    brandName: 'HomeDesk',
    account: account,
    statusData: const HomeDeskStatusData(
        mode: '自建公网模式', server: '远控服务器已连接', tone: HomeDeskTone.success),
    labels: const ['常规', '安全', '网络', '关于'],
    icons: const [Icons.tune, Icons.lock, Icons.link, Icons.info],
    selected: 0,
    onSelected: (_) {},
    onBack: () {},
    child: ListView(children: [
      HomeDeskSettingsCard(title: '服务', serviceStopped: false, children: [
        Row(children: [
          ElevatedButton(onPressed: () {}, child: const Text('停止'))
        ])
      ]),
      HomeDeskSettingsCard(title: '显示语言', children: [
        DropdownButtonFormField<String>(
            value: 'zh-cn',
            isExpanded: true,
            style: TextStyle(
                fontSize: 15,
                fontFamily:
                    Platform.environment.containsKey('HOMEDESK_UI_PREVIEW')
                        ? 'HomeDeskPreview'
                        : null),
            items: const [
              DropdownMenuItem(value: 'zh-cn', child: Text('简体中文')),
              DropdownMenuItem(value: 'en', child: Text('英语'))
            ],
            onChanged: (_) {})
      ]),
      HomeDeskSettingsCard(title: '主题', children: [
        for (final label in ['浅色', '深色', '跟随系统'])
          Row(children: [
            Radio<String>(value: label, groupValue: '跟随系统', onChanged: (_) {}),
            Text(label)
          ]),
      ]),
      HomeDeskSettingsCard(title: '连接偏好', children: [
        CheckboxListTile(
            value: true, onChanged: (_) {}, title: const Text('关闭多个会话前确认'))
      ]),
    ]));
Widget hearthHost(
    {required HomeDeskAccount account,
    required HearthApi api,
    required bool dark,
    required GlobalKey<HomeDeskDashboardState> dashboard,
    GlobalKey? paint,
    bool settings = false}) {
  final preview = Platform.environment.containsKey('HOMEDESK_UI_PREVIEW');
  final theme = homeDeskTheme(ThemeData(
      brightness: dark ? Brightness.dark : Brightness.light,
      fontFamily: preview ? 'HomeDeskPreview' : null));
  return MaterialApp(
      theme: theme,
      builder: (context, child) => RepaintBoundary(key: paint, child: child!),
      home: Scaffold(
          body: Column(children: [
        HomeDeskTitleBar(
            brand: 'HomeDesk',
            inSettings: settings,
            maximized: false,
            onHome: () {},
            onDrag: () {},
            onMaximize: () {},
            onMinimize: () {},
            onClose: () {}),
        Expanded(
            child: settings
                ? settingsFixture(account)
                : HomeDeskDashboard(
                    key: dashboard,
                    brandName: 'HomeDesk',
                    devicesBuilder: (_) => HomeDeskFamilyDevices(
                        account: account,
                        onLogin: () => dashboard.currentState?.showAccount(),
                        onConnect: (_) {},
                        readOption: family.option),
                    recentBuilder: (_) => HomeDeskRecent(
                        recent: recentFixture(),
                        menuBuilder: previewPeerMenu,
                        onConnect: (_) {}),
                    recentSummaryBuilder: (_) => HomeDeskRecent(
                        summary: true,
                        recent: recentFixture(),
                        onConnect: (_) {}),
                    servicesBuilder: (_) => HomeDeskServices(
                        account: account,
                        readOption: portal.portalOption,
                        saveOrigin: (_) async {},
                        credentialStoreFactory: () =>
                            portal.FixtureCredentialStore(),
                        apiBuilder: (origin,
                                {required isAllowed, credentialStorage}) =>
                            api),
                    localBuilder: (_) => const Text('合成设备凭据仅用于布局预览'),
                    statusBuilder: (_) => const SizedBox.shrink(),
                    statusData: const HomeDeskStatusData(
                        mode: '自建公网模式',
                        server: '远控服务器已连接',
                        tone: HomeDeskTone.success),
                    onSettings: () {},
                    onConnect: (_) {})),
      ])));
}

Future<void> export(WidgetTester tester, GlobalKey paint, String name) async {
  final path = Platform.environment['HOMEDESK_UI_PREVIEW'];
  if (path == null) return;
  await tester.runAsync(() async {
    final boundary =
        paint.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory(path).createSync(recursive: true);
    File('$path/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  if (Platform.environment.containsKey('HOMEDESK_UI_PREVIEW')) {
    setUpAll(() async {
      final loader = FontLoader('HomeDeskPreview');
      loader.addFont(Future.value(ByteData.sublistView(
          File('C:/Windows/Fonts/msyh.ttc').readAsBytesSync())));
      await loader.load();
      final icons = FontLoader('MaterialIcons');
      icons.addFont(Future.value(ByteData.sublistView(File(
              '../target/toolchains/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf')
          .readAsBytesSync())));
      await icons.load();
    });
  }
  for (final size in [const Size(800, 600), const Size(1280, 800)]) {
    for (final dark in [false, true]) {
      testWidgets(
          '${size.width.toInt()}×${size.height.toInt()} ${dark ? '深色' : '浅色'}四页无溢出，设备名称单行',
          (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final account = HomeDeskAccount(), api = HearthApi()..signedIn = true;
        account.publish(api, hearthCatalog(), family.one, (_) async {});
        final dashboard = GlobalKey<HomeDeskDashboardState>(),
            paint = GlobalKey();
        final suffix =
            '${size.width.toInt()}x${size.height.toInt()}-${dark ? 'dark' : 'light'}';
        await tester.pumpWidget(hearthHost(
            account: account,
            api: api,
            dark: dark,
            dashboard: dashboard,
            paint: paint));
        await tester.pumpAndSettle();
        for (final id in [family.one, family.two, third, fourth]) {
          final title = find.byKey(ValueKey('family-name-$id'));
          final text = tester.widget<Text>(title);
          expect(text.maxLines, 1);
          expect(text.softWrap, isFalse);
          if (size.width == 1280) {
            final paragraph = tester.renderObject<RenderParagraph>(title);
            expect(paragraph.didExceedMaxLines, isFalse,
                reason: '1280 宽下设备名完整呈现');
            expect(tester.getSize(title).height, lessThan(32));
          }
        }
        expect(tester.takeException(), isNull);
        await export(tester, paint, 'home-$suffix');
        await tester.tap(find.byKey(const ValueKey('nav-services')));
        await tester.pumpAndSettle();
        // 登录仍通过原有表单和 fixture API，不注入生产会话或读取用户凭据。
        await portal.enterCredentials(tester);
        await tester.pumpAndSettle();
        expect(find.text('家庭相册'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await export(tester, paint, 'services-$suffix');
        await tester.tap(find.byKey(const ValueKey('service-type-1')));
        await tester.pumpAndSettle();
        expect(find.text('文件共享'), findsNothing);
        expect(find.text('家庭相册'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('nav-remote')));
        await tester.pumpAndSettle();
        expect(find.textContaining('暂无记录'), findsNothing);
        expect(find.byKey(const ValueKey('recent-search')), findsOneWidget);
        expect(find.byKey(const ValueKey('recent-more-987654321')),
            findsOneWidget);
        expect(tester.takeException(), isNull);
        await export(tester, paint, 'recent-$suffix');
        if (size.width == 800 && dark) {
          await tester.ensureVisible(
              find.byKey(const ValueKey('recent-more-987654321')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('recent-more-987654321')));
          await tester.pumpAndSettle();
          expect(find.text('忘记密码'), findsOneWidget);
          await export(tester, paint, 'recent-menu-800x600-dark');
          await tester.tap(find.text('重命名'));
          await tester.pumpAndSettle();
        }
        expect(find.byKey(const ValueKey('recent-filter-1')), findsNothing);
        await tester.enterText(
            find.byKey(const ValueKey('recent-search')), '儿童房');
        await tester.pumpAndSettle();
        expect(find.text('儿童房电脑'), findsOneWidget);
        expect(find.text('客厅电脑'), findsNothing);
        expect(find.byKey(const ValueKey('recent-filter-2')), findsNothing);
        final settingsAccount = HomeDeskAccount(),
            settingsApi = HearthApi()..signedIn = true;
        settingsAccount.publish(
            settingsApi, hearthCatalog(), family.one, (_) async {});
        await tester.pumpWidget(hearthHost(
            account: settingsAccount,
            api: settingsApi,
            dark: dark,
            dashboard: dashboard,
            paint: paint,
            settings: true));
        await tester.pumpAndSettle();
        expect(find.text('后台服务 · 运行中'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await export(tester, paint, 'settings-$suffix');
        await tester.pumpWidget(const SizedBox());
        account.dispose();
        api.close();
        settingsAccount.dispose();
        settingsApi.close();
      });
    }
  }
  testWidgets('最近连接继续提交真实设备，缺失历史和强制中继选项均不伪造路径', (tester) async {
    final peer = Peer.fromJson(
        {'id': '123456789', 'alias': '卧室电脑', 'forceAlwaysRelay': 'true'});
    Peer? connected;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: HomeDeskRecent(
                recent: [peer], onConnect: (p) => connected = p))));
    expect(find.textContaining('连接路径'), findsNothing);
    expect(find.textContaining('暂无记录'), findsNothing);
    expect(find.text('中继转发'), findsNothing);
    await tester.tap(find.text('连接'));
    expect(connected, same(peer));
    expect(tester.takeException(), isNull);
  });
}
