// HOMEDESK: 合成本机信息验证排版和动作；不读取真实 ID、密码或系统安装状态。
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/homedesk_dashboard.dart';
import 'package:flutter_hbb/homedesk_local_info.dart';

Widget host(
        {required TextEditingController id,
        required TextEditingController password,
        double scale = 1,
        bool dark = false,
        bool incoming = true,
        bool temporary = true,
        VoidCallback? copy,
        VoidCallback? refresh,
        VoidCallback? settings,
        VoidCallback? install,
        GlobalKey? paint}) =>
    MaterialApp(
        theme: ThemeData(
            brightness: dark ? Brightness.dark : Brightness.light,
            fontFamily:
                Platform.environment.containsKey('HOMEDESK_LOCAL_INFO_PREVIEW')
                    ? 'HomeDeskPreview'
                    : null),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: RepaintBoundary(key: paint, child: child!)),
        home: Scaffold(
            body: HomeDeskDashboard(
                brandName: 'HomeDesk',
                devicesBuilder: (_) => const SizedBox(),
                recentBuilder: (_) => const SizedBox(),
                statusBuilder: (_) => const SizedBox(),
                onSettings: () {},
                onConnect: (_) {},
                localBuilder: (_) => HomeDeskLocalInfo(
                    id: id,
                    password: password,
                    incomingEnabled: incoming,
                    showTemporaryPassword: temporary,
                    passwordHint: '使用固定密码',
                    onCopyId: copy ?? () {},
                    onRefreshPassword: refresh,
                    onPasswordSettings: settings,
                    onInstall: install,
                    status: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text('连接服务已就绪（合成状态）'))))));

void main() {
  testWidgets('本机信息充分使用弹窗宽度，凭据与便携操作在普通窗口中可见', (tester) async {
    tester.view.physicalSize = const Size(780, 590);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final id = TextEditingController(text: '123 456 789');
    final password = TextEditingController(text: 'demo42');
    var copies = 0, refreshes = 0, settings = 0, installs = 0;
    await tester.pumpWidget(host(
        id: id,
        password: password,
        copy: () => copies++,
        refresh: () => refreshes++,
        settings: () => settings++,
        install: () => installs++));
    expect(find.byKey(const ValueKey('local-info-id')), findsNothing);
    await tester.tap(find.byTooltip('本机信息'));
    await tester.pumpAndSettle();
    expect(
        tester.getSize(find.byKey(const ValueKey('local-info-scroll'))).width,
        greaterThan(480));
    expect(find.byKey(const ValueKey('local-info-install')).hitTestable(),
        findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('local-info-copy-id')));
    await tester.tap(find.byKey(const ValueKey('local-info-refresh-password')));
    await tester
        .tap(find.byKey(const ValueKey('local-info-password-settings')));
    expect([copies, refreshes, settings, installs], [1, 1, 1, 0]);
    id.text = '987 654 321';
    await tester.pump();
    expect(find.text('987 654 321'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('关闭本机信息'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('local-info-id')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    id.dispose();
    password.dispose();
  });

  testWidgets('固定密码与仅主控模式不显示旧临时密码，也不提供刷新入口', (tester) async {
    final id = TextEditingController(text: '123 456 789');
    final password = TextEditingController(text: 'stale-demo');
    for (final incoming in [true, false]) {
      await tester.pumpWidget(host(
          id: id,
          password: password,
          incoming: incoming,
          temporary: false,
          refresh: () {},
          settings: null));
      await tester.tap(find.byTooltip('本机信息'));
      await tester.pumpAndSettle();
      expect(find.text('stale-demo'), findsNothing);
      expect(find.byKey(const ValueKey('local-info-refresh-password')),
          findsNothing);
      expect(find.byKey(const ValueKey('local-info-password-settings')),
          findsNothing);
      if (incoming) {
        expect(find.text('使用固定密码'), findsOneWidget);
      } else {
        expect(find.byKey(const ValueKey('local-info-id')), findsNothing);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }
    id.dispose();
    password.dispose();
  });

  testWidgets('本机弹窗在窄窗口双倍字体下可滚动，关闭按钮始终可见', (tester) async {
    tester.view.physicalSize = const Size(360, 560);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final id = TextEditingController(text: '123 456 789');
    final password = TextEditingController(text: 'demo42');
    await tester.pumpWidget(host(
        id: id,
        password: password,
        scale: 2,
        refresh: () {},
        settings: () {},
        install: () {}));
    await tester.tap(find.byTooltip('本机信息'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('关闭本机信息').hitTestable(), findsOneWidget);
    await tester
        .ensureVisible(find.byKey(const ValueKey('local-info-install')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('local-info-install')).hitTestable(),
        findsOneWidget);
    expect(find.byTooltip('关闭本机信息').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    id.dispose();
    password.dispose();
  });

  if (Platform.environment.containsKey('HOMEDESK_LOCAL_INFO_PREVIEW')) {
    testWidgets('导出本机信息合成预览', (tester) async {
      tester.view.physicalSize = const Size(780, 590);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final font = FontLoader('HomeDeskPreview')
        ..addFont(Future.value(ByteData.sublistView(
            File('C:/Windows/Fonts/msyh.ttc').readAsBytesSync())));
      await font.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(Future.value(ByteData.sublistView(File(
                '../target/toolchains/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf')
            .readAsBytesSync())));
      await icons.load();
      final id = TextEditingController(text: '123 456 789');
      final password = TextEditingController(text: 'demo42');
      for (final dark in [false, true]) {
        final paint = GlobalKey();
        await tester.pumpWidget(host(
            id: id,
            password: password,
            dark: dark,
            paint: paint,
            refresh: () {},
            settings: () {},
            install: () {}));
        await tester.tap(find.byTooltip('本机信息'));
        await tester.pumpAndSettle();
        final boundary =
            paint.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          final output =
              Directory(Platform.environment['HOMEDESK_LOCAL_INFO_PREVIEW']!)
                ..createSync(recursive: true);
          File('${output.path}/local-info-${dark ? 'dark' : 'light'}.png')
              .writeAsBytesSync(data!.buffer.asUint8List());
          image.dispose();
        });
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }
      id.dispose();
      password.dispose();
    });
  }
}
