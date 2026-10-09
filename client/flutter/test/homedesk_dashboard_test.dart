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
import 'package:flutter_hbb/homedesk_devices.dart';

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
      data: MediaQueryData(textScaler: TextScaler.linear(scale)),
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
            localBuilder: (_) => const Center(child: Text('测试凭据：默认不可见')),
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
  testWidgets('远控首页校验设备ID，凭据只在主动查看共享时展示', (tester) async {
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
    expect(find.text('测试凭据：默认不可见'), findsNothing);
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
    await tester.ensureVisible(find.text('查看本机共享'));
    await tester.tap(find.text('查看本机共享'));
    await tester.pumpAndSettle();
    expect(find.text('测试凭据：默认不可见'), findsOneWidget);
    await tester.tap(find.byTooltip('关闭'));
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
    await tester.tap(find.descendant(
        of: find.byType(NavigationBar), matching: find.text('设备')));
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
    await tester.tap(find.descendant(
        of: find.byType(NavigationBar), matching: find.text('穿透')));
    await tester.pumpAndSettle();
    expect(find.text('合成穿透服务'), findsOneWidget);
    expect(find.byKey(const ValueKey('remote-device-id')), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  if (Platform.environment.containsKey('HOMEDESK_UI_PREVIEW')) {
    testWidgets('导出合成设备的深浅色预览', (tester) async {
      tester.view.physicalSize = const Size(960, 720);
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
        final api = sample == 'empty' ? null : PreviewConsole();
        await tester.pumpWidget(
            host(api: api, dashboard: key, paintKey: paint, dark: dark));
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
      }
    });
  }
}
