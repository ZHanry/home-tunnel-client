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
  testWidgets('主页默认隐藏本机凭据，手动连接提交设备 ID', (tester) async {
    tester.view.physicalSize = const Size(960, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey<HomeDeskDashboardState>();
    final api = PreviewConsole();
    String? connected;
    await tester.pumpWidget(
        host(api: api, dashboard: key, onConnect: (id) => connected = id));
    await tester.pump();
    expect(find.text('测试凭据：默认不可见'), findsNothing);
    expect(find.byTooltip('家庭服务'), findsNothing);
    expect(find.text('书房电脑'), findsOneWidget);
    await tester.tap(find.text('手动连接'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '123456');
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog), matching: find.text('连接设备')));
    await tester.pumpAndSettle();
    expect(connected, '123456');
    await tester.tap(find.byTooltip('本机信息'));
    await tester.pumpAndSettle();
    expect(find.text('测试凭据：默认不可见'), findsOneWidget);
    await tester.tap(find.byTooltip('关闭本机信息'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('最近连接'));
    await tester.pumpAndSettle();
    expect(find.text('最近连接内容'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('窄窗口和双倍字体可用，空状态保留连接入口', (tester) async {
    tester.view.physicalSize = const Size(560, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey<HomeDeskDashboardState>();
    final api = PreviewConsole(empty: true);
    await tester.pumpWidget(host(api: api, dashboard: key, scale: 2));
    await tester.pump();
    expect(find.text('从连接第一台电脑开始'), findsOneWidget);
    expect(find.text('手动连接'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('房间筛选只显示对应设备', (tester) async {
    tester.view.physicalSize = const Size(960, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey<HomeDeskDashboardState>();
    final api = PreviewConsole();
    await tester.pumpWidget(host(api: api, dashboard: key));
    await tester.pump();
    await tester.tap(find.widgetWithText(ChoiceChip, '书房'));
    await tester.pump();
    expect(find.text('书房电脑'), findsOneWidget);
    expect(find.text('客厅电脑'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('服务页按需初始化，导航切换保留会话和设备筛选', (tester) async {
    tester.view.physicalSize = const Size(960, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey<HomeDeskDashboardState>();
    var initialized = 0;
    var disposed = 0;
    await tester.pumpWidget(host(
        api: PreviewConsole(),
        dashboard: key,
        servicesBuilder: (_) => _ServiceProbe(
            onInitialized: () => initialized++, onDisposed: () => disposed++)));
    await tester.pump();
    expect(initialized, 0);
    final deviceState = tester.state(find.byType(HomeDeskDevices));
    await tester.tap(find.widgetWithText(ChoiceChip, '书房'));
    await tester.pump();
    await tester.tap(find.byTooltip('家庭服务'));
    await tester.pumpAndSettle();
    expect(initialized, 1);
    expect(find.text('查看设备上的服务，打开你的访问地址'), findsOneWidget);
    expect(find.text('手动连接'), findsNothing);
    expect(find.text('家庭连接服务未就绪，请检查网络设置'), findsNothing);
    await tester.enterText(find.byType(TextField), '测试会话保留');
    await tester.tap(find.byTooltip('家庭设备'));
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(HomeDeskDevices)), same(deviceState));
    expect(find.text('书房电脑'), findsOneWidget);
    expect(find.text('客厅电脑'), findsNothing);
    await tester.tap(find.byTooltip('最近连接'));
    await tester.pumpAndSettle();
    expect(find.text('最近连接内容'), findsOneWidget);
    expect(find.text('手动连接'), findsOneWidget);
    await tester.tap(find.byTooltip('家庭服务'));
    await tester.pumpAndSettle();
    expect(find.text('测试会话保留'), findsOneWidget);
    expect(initialized, 1);
    expect(disposed, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    expect(disposed, 1);
  });

  testWidgets('服务页窄窗口双倍字体不溢出', (tester) async {
    tester.view.physicalSize = const Size(560, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(host(
        api: PreviewConsole(empty: true),
        dashboard: GlobalKey<HomeDeskDashboardState>(),
        scale: 2,
        servicesBuilder: (_) => const Center(child: Text('合成家庭服务'))));
    await tester.pump();
    await tester.tap(find.byTooltip('家庭服务'));
    await tester.pumpAndSettle();
    expect(find.text('合成家庭服务'), findsOneWidget);
    expect(find.text('手动连接'), findsNothing);
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
              '../target/toolchains/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf')
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
