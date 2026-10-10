// Synthetic controllers exercise the inline UI without native IDs or credentials.
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/homedesk_theme.dart';
import 'package:flutter_hbb/nestlink_remote_credentials.dart';

Widget host({
  required TextEditingController id,
  required TextEditingController password,
  double scale = 1,
  bool dark = false,
  bool incoming = true,
  bool temporary = true,
  bool stopped = false,
  bool ready = true,
  String hint = '使用固定密码',
  VoidCallback? copy,
  VoidCallback? refresh,
  GlobalKey? paint,
}) =>
    MaterialApp(
      theme: homeDeskTheme(ThemeData(
        brightness: dark ? Brightness.dark : Brightness.light,
        fontFamily:
            Platform.environment.containsKey('HOMEDESK_LOCAL_INFO_PREVIEW')
                ? 'HomeDeskPreview'
                : null,
      )),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: RepaintBoundary(key: paint, child: child!),
      ),
      home: Scaffold(
          body: SingleChildScrollView(
        key: const ValueKey('remote-page-scroll'),
        padding: const EdgeInsets.all(24),
        child: Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(
                  child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('这台设备'),
                      const SizedBox(height: 16),
                      NestLinkRemoteCredentials(
                        id: id,
                        password: password,
                        incomingEnabled: incoming,
                        showTemporaryPassword: temporary,
                        serviceStopped: stopped,
                        accountReady: ready,
                        passwordHint: hint,
                        onCopyId: copy ?? () {},
                        onRefreshPassword: refresh,
                      ),
                    ]),
              )),
            )),
      )),
    );

void main() {
  testWidgets('远协页直接显示原生controller凭据，复制刷新且实时更新', (tester) async {
    final id = TextEditingController(text: '123 456 789');
    final password = TextEditingController(text: 'demo42');
    var copies = 0, refreshes = 0;
    await tester.pumpWidget(host(
        id: id,
        password: password,
        copy: () => copies++,
        refresh: () => refreshes++));
    expect(find.text('123 456 789'), findsOneWidget);
    expect(find.text('demo42'), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    expect(find.text('共享与授权'), findsNothing);
    expect(find.text('便携运行'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('remote-credentials-copy-id')));
    await tester
        .tap(find.byKey(const ValueKey('remote-credentials-refresh-password')));
    expect([copies, refreshes], [1, 1]);
    id.text = '987 654 321';
    password.text = 'fresh123';
    await tester.pump();
    expect(find.text('987 654 321'), findsOneWidget);
    expect(find.text('fresh123'), findsOneWidget);
    expect(find.text('demo42'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    id.dispose();
    password.dispose();
  });

  testWidgets('固定密码、本机确认、服务停止与账号未就绪均不绑定旧OTP', (tester) async {
    final id = TextEditingController(text: '123 456 789');
    final password = TextEditingController(text: 'stale123');
    for (final state in [
      (false, false, true, '使用固定密码', '使用固定密码'),
      (false, false, true, '连接时由本机确认', '连接时由本机确认'),
      (true, true, true, '使用固定密码', '远控服务已停止'),
      (true, false, false, '使用固定密码', '远控尚未就绪'),
    ]) {
      await tester.pumpWidget(host(
          id: id,
          password: password,
          temporary: state.$1,
          stopped: state.$2,
          ready: state.$3,
          hint: state.$4,
          refresh: () {}));
      expect(find.text(state.$5), findsOneWidget);
      expect(find.text('stale123'), findsNothing);
      expect(
          find.byWidgetPredicate(
              (w) => w is TextField && identical(w.controller, password)),
          findsNothing);
      expect(find.byKey(const ValueKey('remote-credentials-refresh-password')),
          findsNothing);
      expect(find.text('123 456 789'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(
        host(id: id, password: password, incoming: false, refresh: () {}));
    expect(find.byType(TextField), findsNothing);
    expect(
        find.byKey(const ValueKey('remote-credentials-copy-id')), findsNothing);
    expect(find.byKey(const ValueKey('remote-credentials-refresh-password')),
        findsNothing);
    await tester.pumpWidget(const SizedBox());
    id.dispose();
    password.dispose();
  });

  testWidgets('退出或停止后即使controller更新也不会再次显示OTP', (tester) async {
    final id = TextEditingController(text: '123 456 789');
    final password = TextEditingController(text: 'demo42');
    for (final stopped in [false, true]) {
      await tester.pumpWidget(host(id: id, password: password, refresh: () {}));
      expect(
          find.byWidgetPredicate(
              (w) => w is TextField && identical(w.controller, password)),
          findsOneWidget);
      await tester.pumpWidget(host(
          id: id,
          password: password,
          stopped: stopped,
          ready: stopped,
          refresh: () {}));
      password.text = stopped ? 'late1234' : 'old12345';
      await tester.pump();
      expect(find.text(password.text), findsNothing);
      expect(
          find.byWidgetPredicate(
              (w) => w is TextField && identical(w.controller, password)),
          findsNothing);
      expect(find.byKey(const ValueKey('remote-credentials-refresh-password')),
          findsNothing);
    }
    await tester.pumpWidget(const SizedBox());
    id.dispose();
    password.dispose();
  });

  testWidgets('未获取ID禁用复制，原生生成中和禁用占位不冒充密码', (tester) async {
    final id = TextEditingController();
    final password = TextEditingController(text: 'Generating ...');
    await tester.pumpWidget(host(id: id, password: password, refresh: () {}));
    final copy = find.byKey(const ValueKey('remote-credentials-copy-id'));
    expect(tester.widget<IconButton>(copy).onPressed, isNull);
    expect(find.text('Generating ...'), findsNothing);
    expect(find.byType(TextField), findsNothing);
    id.text = '正在生成…';
    password.text = '-';
    await tester.pump();
    expect(tester.widget<IconButton>(copy).onPressed, isNull);
    expect(find.text('-'), findsNothing);
    id.text = '123 456 789';
    password.text = 'demo42';
    await tester.pump();
    expect(tester.widget<IconButton>(copy).onPressed, isNotNull);
    expect(find.text('demo42'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    id.dispose();
    password.dispose();
  });

  testWidgets('窄窗双倍字体由远协页面滚动，两个凭据块竖排无弹窗', (tester) async {
    tester.view.physicalSize = const Size(320, 260);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final id = TextEditingController(text: '123 456 789');
    final password = TextEditingController(text: 'demo42');
    await tester
        .pumpWidget(host(id: id, password: password, scale: 2, refresh: () {}));
    final idBlock = find.byKey(const ValueKey('remote-credentials-id'));
    final passwordBlock =
        find.byKey(const ValueKey('remote-credentials-password'));
    expect(tester.getTopLeft(passwordBlock).dy,
        greaterThan(tester.getBottomLeft(idBlock).dy));
    expect(tester.getTopLeft(passwordBlock).dx, tester.getTopLeft(idBlock).dx);
    expect(find.byType(Dialog), findsNothing);
    await tester.ensureVisible(
        find.byKey(const ValueKey('remote-credentials-refresh-password')));
    await tester.pumpAndSettle();
    expect(
        find
            .byKey(const ValueKey('remote-credentials-refresh-password'))
            .hitTestable(),
        findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    id.dispose();
    password.dispose();
  });

  if (Platform.environment.containsKey('HOMEDESK_LOCAL_INFO_PREVIEW')) {
    testWidgets('导出远协页本机凭据合成预览', (tester) async {
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
                'R:/toolchains/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf')
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
            refresh: () {}));
        await tester.pumpAndSettle();
        final boundary =
            paint.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          final output =
              Directory(Platform.environment['HOMEDESK_LOCAL_INFO_PREVIEW']!)
                ..createSync(recursive: true);
          File(output.path +
                  '/remote-credentials-' +
                  (dark ? 'dark' : 'light') +
                  '.png')
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
