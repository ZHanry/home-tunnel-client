// HOMEDESK: 合成账号目录验证服务门户，不访问公网、真实账号或系统剪贴板。
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/homedesk_dashboard.dart';
import 'package:flutter_hbb/homedesk_account.dart';
import 'package:flutter_hbb/homedesk_local_agent.dart';
import 'package:flutter_hbb/homedesk_services.dart';
import 'package:flutter_hbb/homedesk_theme.dart';
import 'package:flutter_hbb/homedesk_service_editor.dart';
import 'package:flutter_hbb/homedesk_tunnel_api.dart';
import 'package:flutter_hbb/homedesk_tunnel_session.dart';

String portalOption(String key,
    {bool allowed = true,
    String permission = 'permit-fixture',
    String origin = 'https://console.example.com'}) {
  if (key == 'homedesk-home-tunnel-origin') return origin;
  return key == 'homedesk-home-tunnel-allowed'
      ? allowed
          ? 'Y'
          : 'N'
      : permission;
}

class FixtureCredentialStore implements HomeDeskCredentialStorage {
  @override
  final bool supported;
  HomeDeskPortalCredential? record;
  int clears = 0;
  int generation = 0;
  int peeks = 0;
  bool clearFails = false;
  Completer<void>? pendingClear;
  FixtureCredentialStore({this.supported = false, this.record});

  @override
  Future<HomeDeskRememberedAccount?> peekAccount() async {
    peeks++;
    return record == null
        ? null
        : HomeDeskRememberedAccount(
            origin: record!.origin,
            userId: record!.userId,
            username: record!.username,
            displayName: record!.displayName);
  }

  @override
  Future<CredentialTransaction> begin() async {
    record = null;
    return CredentialTransaction('${++generation}');
  }

  @override
  Future<CredentialLease?> consume() async {
    final value = record;
    record = null;
    return value == null
        ? null
        : CredentialLease(
            record: value,
            transaction: CredentialTransaction('${++generation}'));
  }

  @override
  Future<void> save(HomeDeskPortalCredential record,
      CredentialTransaction transaction) async {
    if (transaction.generation != '$generation') {
      throw const FormatException('旧事务');
    }
    this.record = record;
  }

  @override
  Future<void> discard(CredentialTransaction transaction) async {
    if (transaction.generation == '$generation') await clear();
  }

  @override
  Future<void> clear() async {
    clears++;
    if (pendingClear != null) await pendingClear!.future;
    if (clearFails) throw StateError('fixture credential erase failed');
    generation++;
    record = null;
  }
}

HomeTunnelCatalog sampleCatalog() => HomeTunnelCatalog(devices: const [
      HomeTunnelDevice(
          id: 'fixture-nas', name: '家庭 NAS', platform: '', online: true),
      HomeTunnelDevice(
          id: 'fixture-offline', name: '离线电脑', platform: '', online: false),
    ], services: [
      HomeTunnelService(
          id: 'fixture-web',
          deviceId: 'fixture-nas',
          name: '家庭相册',
          proxyType: 'http',
          status: 'Online',
          webUrl: Uri.parse('https://album.example.com'),
          endpoint: null,
          enabled: true,
          localHost: '127.0.0.1',
          localPort: 8080,
          subdomain: 'album'),
      const HomeTunnelService(
          id: 'fixture-tcp',
          deviceId: 'fixture-nas',
          name: 'SSH 连接',
          proxyType: 'tcp',
          status: 'Online',
          webUrl: null,
          endpoint: 'edge.example.com:10000',
          enabled: true,
          localHost: '127.0.0.1',
          localPort: 22),
    ]);

class PortalFixtureApi extends HomeTunnelApi {
  bool signedIn = false;
  bool closed = false;
  bool rejectPassword;
  int logins = 0;
  int loads = 0;
  int logouts = 0;
  int restores = 0;
  int creates = 0;
  int updates = 0;
  int toggles = 0;
  int deletes = 0;
  int deviceUpdates = 0;
  int deviceDeletes = 0;
  bool keepDeletedDeviceInCatalog = false;
  String? lastDeletedDevice;
  Completer<void>? pendingDeviceDelete;
  Completer<void>? pendingLogout;
  bool rememberRequested = false;
  bool remembered = false;
  bool restoreFails = false;
  HomeTunnelApiException? mutationError;
  HomeTunnelApiException? logoutError;
  Completer<HomeTunnelService>? pendingMutation;
  Map<String, dynamic>? lastValues;
  List<String>? lastTags;
  bool? lastFavorite;
  int? lastVersion;
  Completer<HomeTunnelCatalog>? pendingCatalog;
  HomeTunnelCatalog result = sampleCatalog();

  PortalFixtureApi({this.rejectPassword = false})
      : super('https://console.example.com', isAllowed: () => true);

  @override
  bool get isSignedIn => signedIn;
  @override
  String get displayName => '我的家庭';
  @override
  bool get rememberedLogin => remembered && signedIn;
  @override
  Future<bool> restore() async {
    restores++;
    if (restoreFails) {
      throw const HomeTunnelApiException('保存的登录已过期。', 'SESSION_EXPIRED');
    }
    signedIn = true;
    remembered = true;
    return true;
  }

  @override
  Future<void> forgetRememberedLogin() async {
    remembered = false;
  }

  @override
  Future<void> login(
      {required String username,
      required String password,
      bool rememberLogin = false}) async {
    logins++;
    if (rejectPassword) {
      throw const HomeTunnelApiException('账号或密码错误。', 'INVALID_CREDENTIALS');
    }
    signedIn = true;
    rememberRequested = rememberLogin;
    remembered = rememberLogin;
  }

  @override
  Future<HomeTunnelCatalog> catalog() async {
    loads++;
    if (pendingCatalog != null) return pendingCatalog!.future;
    return result;
  }

  @override
  Future<void> logout() async {
    logouts++;
    signedIn = false;
    if (pendingLogout != null) await pendingLogout!.future;
    if (logoutError != null) throw logoutError!;
  }

  @override
  Future<List<HomeDeskRemoteBinding>> remoteBindings() async => [];

  @override
  Future<void> deleteDevice(String id) async {
    deviceDeletes++;
    lastDeletedDevice = id;
    if (pendingDeviceDelete != null) await pendingDeviceDelete!.future;
    if (mutationError != null) throw mutationError!;
    if (!keepDeletedDeviceInCatalog) {
      result = HomeTunnelCatalog(
          devices: result.devices.where((device) => device.id != id).toList(),
          services: result.services,
          capabilities: result.capabilities);
    }
  }

  @override
  Future<HomeTunnelSubdomainAvailability> checkSubdomain(String name,
          {String? connectionId}) async =>
      HomeTunnelSubdomainAvailability(
          name: name, available: true, reason: '', suggestions: const []);

  HomeTunnelService _service(Map<String, dynamic> values,
          {String id = 'fixture-created',
          String deviceId = 'fixture-nas',
          int version = 2}) =>
      HomeTunnelService(
          id: id,
          deviceId: values['device_id'] as String? ?? deviceId,
          name: values['name'] as String? ?? '家庭相册',
          proxyType: values['proxy_type'] as String? ?? 'http',
          status: 'Online',
          webUrl: values['proxy_type'] == 'tcp' || values['proxy_type'] == 'udp'
              ? null
              : Uri.parse('https://album.example.com'),
          endpoint:
              values['proxy_type'] == 'tcp' || values['proxy_type'] == 'udp'
                  ? 'edge.example.com:10001'
                  : null,
          enabled: values['enabled'] as bool? ?? true,
          version: version,
          localScheme: values['local_scheme'] as String? ?? 'http',
          localHost: values['local_host'] as String? ?? '127.0.0.1',
          localPort: values['local_port'] as int? ?? 8080,
          subdomain: values['subdomain'] as String? ?? 'album');

  @override
  Future<HomeTunnelService> createService(Map<String, dynamic> values) async {
    creates++;
    lastValues = values;
    if (mutationError != null) throw mutationError!;
    final service = _service(values, id: 'fixture-created-$creates');
    result = HomeTunnelCatalog(
        devices: result.devices,
        services: [...result.services, service],
        capabilities: result.capabilities);
    return service;
  }

  @override
  Future<HomeTunnelService> updateService(
      String id, Map<String, dynamic> values,
      {required int expectedVersion}) async {
    updates++;
    lastValues = values;
    lastVersion = expectedVersion;
    if (mutationError != null) throw mutationError!;
    final service = pendingMutation == null
        ? _service(values, id: id)
        : await pendingMutation!.future;
    result = HomeTunnelCatalog(
        devices: result.devices,
        services: [
          for (final item in result.services)
            if (item.id == id) service else item
        ],
        capabilities: result.capabilities);
    return service;
  }

  @override
  Future<HomeTunnelService> setServiceEnabled(String id, bool enabled,
      {required int expectedVersion}) async {
    toggles++;
    lastVersion = expectedVersion;
    if (mutationError != null) throw mutationError!;
    final old = result.services.firstWhere((item) => item.id == id);
    final service = _service({'name': old.name, 'enabled': enabled},
        id: id, version: old.version + 1);
    result = HomeTunnelCatalog(
        devices: result.devices,
        services: [
          for (final item in result.services)
            if (item.id == id) service else item
        ],
        capabilities: result.capabilities);
    return service;
  }

  @override
  Future<void> deleteService(String id, {required int expectedVersion}) async {
    deletes++;
    lastVersion = expectedVersion;
    if (mutationError != null) throw mutationError!;
    result = HomeTunnelCatalog(
        devices: result.devices,
        services: result.services.where((item) => item.id != id).toList(),
        capabilities: result.capabilities);
  }

  @override
  Future<void> updateDevice(String id,
      {required List<String> tags,
      required bool favorite,
      required int expectedMetadataVersion}) async {
    deviceUpdates++;
    lastTags = tags;
    lastFavorite = favorite;
    lastVersion = expectedMetadataVersion;
    if (mutationError != null) throw mutationError!;
    result = HomeTunnelCatalog(devices: [
      for (final device in result.devices)
        if (device.id == id)
          HomeTunnelDevice(
              id: id,
              name: device.name,
              platform: device.platform,
              online: device.online,
              tags: tags,
              favorite: favorite,
              metadataVersion: expectedMetadataVersion + 1)
        else
          device
    ], services: result.services, capabilities: result.capabilities);
  }

  @override
  void close() {
    closed = true;
    signedIn = false;
    super.close();
  }
}

Widget portalHost(
        {required HomeDeskServices page,
        double scale = 1,
        bool dark = false,
        GlobalKey? paint}) =>
    MaterialApp(
        theme: homeDeskTheme(ThemeData(
            brightness: dark ? Brightness.dark : Brightness.light,
            fontFamily:
                Platform.environment.containsKey('HOMEDESK_SERVICES_PREVIEW')
                    ? 'HomeDeskPreview'
                    : null)),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!),
        home: Scaffold(
            body: RepaintBoundary(
                key: paint,
                child:
                    Padding(padding: const EdgeInsets.all(16), child: page))));

Future<void> enterCredentials(WidgetTester tester) async {
  await tester.enterText(find.byKey(const ValueKey('tunnel-origin')),
      'https://console.example.com');
  await tester.enterText(
      find.byKey(const ValueKey('tunnel-username')), 'fixture-user');
  await tester.enterText(
      find.byKey(const ValueKey('tunnel-password')), 'fixture-password');
  await tester.ensureVisible(find.byKey(const ValueKey('tunnel-login')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('tunnel-login')));
  await tester.pumpAndSettle();
}

HomeDeskServices fixturePage(PortalFixtureApi api,
        {FixtureCredentialStore? store,
        HomeDeskAccount? account,
        HomeDeskLocalAgent? localAgent,
        Future<void> Function(HomeTunnelApi, int)? onRetryLocal,
        String Function(String)? readOption,
        Future<void> Function(String)? saveOrigin}) =>
    HomeDeskServices(
        account: account,
        localAgent: localAgent,
        onRetryLocal: onRetryLocal,
        readOption: readOption ?? portalOption,
        saveOrigin: saveOrigin ?? (_) async {},
        credentialStoreFactory: () => store ?? FixtureCredentialStore(),
        apiBuilder: (origin, {required isAllowed, credentialStorage}) => api);

HomeDeskPortalCredential rememberedFixture(
        {String origin = 'https://console.example.com'}) =>
    HomeDeskPortalCredential(
        origin: origin,
        userId: '10000000-0000-4000-8000-000000000001',
        username: 'fixture-user',
        displayName: '合成家庭',
        refreshToken: 'fixture_refresh_token_0001',
        refreshExpiresAt: DateTime.utc(2100));

class FixtureLocalAgent extends HomeDeskLocalAgent {
  int stops = 0;
  String status = '';
  String connectionPhase = 'running';
  bool attaching = false;
  FixtureLocalAgent()
      : super(
            send: (_) async {},
            read: () => '{}',
            permission: () => 'permit-fixture',
            isAllowed: () => true,
            name: '合成本机');
  @override
  String get deviceId => 'fixture-nas';
  @override
  String get phase => connectionPhase;
  @override
  String get agentState => status;
  @override
  bool get isAttaching => attaching;
  @override
  Future<void> stop() async {
    stops++;
  }
}

class LocalDeviceFixtureApi extends PortalFixtureApi {
  @override
  String get guiDeviceId => 'fixture-local';
}

void main() {
  testWidgets('穿透标题保留刷新，正常状态不显示角标或重复状态条', (tester) async {
    final api = PortalFixtureApi(), agent = FixtureLocalAgent();
    await tester
        .pumpWidget(portalHost(page: fixturePage(api, localAgent: agent)));
    await enterCredentials(tester);
    expect(find.text('内网穿透'), findsOneWidget);
    expect(find.byKey(const ValueKey('tunnel-account-status')), findsNothing);
    expect(find.byKey(const ValueKey('tunnel-server-host')), findsNothing);
    expect(find.text('console.example.com'), findsNothing);
    expect(find.text('当前可新建网页服务'), findsNothing);
    expect(find.textContaining(RegExp(r'^\d+ 台设备 · \d+ 项服务$')), findsNothing);
    expect(
        find.byKey(const ValueKey('tunnel-connection-warning')), findsNothing);
    final title =
        tester.getRect(find.byKey(const ValueKey('tunnel-title-tools')));
    final refresh =
        tester.getRect(find.byKey(const ValueKey('tunnel-refresh')));
    expect(refresh.right, closeTo(title.right, .5));
    expect(refresh.center.dy, closeTo(title.center.dy, .5));
    final reads = api.loads;
    agent.connectionPhase = 'stopped';
    agent.attaching = true;
    await tester.tap(find.byKey(const ValueKey('tunnel-refresh')));
    await tester.pumpAndSettle();
    expect(api.loads, reads + 1);
    expect(
        find.byKey(const ValueKey('tunnel-connection-warning')), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('本机接入异常角标悬停显示具体原因，点击保留安全重试入口', (tester) async {
    final api = PortalFixtureApi();
    final agent = FixtureLocalAgent()
      ..error = const HomeDeskAgentException('RUNTIME_MISSING');
    await tester
        .pumpWidget(portalHost(page: fixturePage(api, localAgent: agent)));
    await enterCredentials(tester);
    final badge = find.byKey(const ValueKey('tunnel-connection-notice'));
    expect(find.byKey(const ValueKey('tunnel-connection-warning')),
        findsOneWidget);
    expect(tester.widget<IconButton>(badge).tooltip, agent.error!.message);
    final title = find.text('内网穿透');
    expect(tester.getRect(badge).left,
        greaterThanOrEqualTo(tester.getRect(title).right));
    final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(badge));
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();
    expect(find.text(agent.error!.message), findsOneWidget);
    await mouse.removePointer();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    await tester.tap(badge);
    await tester.pumpAndSettle();
    expect(find.text(agent.error!.message), findsOneWidget);
    expect(find.byKey(const ValueKey('tunnel-retry-local')), findsOneWidget);
    expect(find.byKey(const ValueKey('tunnel-account-status')), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('隧道退化角标说明FRPS连接问题，恢复后移除角标', (tester) async {
    final api = PortalFixtureApi();
    final agent = FixtureLocalAgent()..status = 'Degraded';
    await tester
        .pumpWidget(portalHost(page: fixturePage(api, localAgent: agent)));
    await enterCredentials(tester);
    final badge = find.byKey(const ValueKey('tunnel-connection-notice'));
    expect(tester.widget<IconButton>(badge).tooltip, contains('FRPS'));
    expect(tester.widget<IconButton>(badge).tooltip, agent.description);
    agent.status = 'Online';
    await tester.tap(find.byKey(const ValueKey('tunnel-refresh')));
    await tester.pumpAndSettle();
    expect(badge, findsNothing);
    expect(
        find.byKey(const ValueKey('tunnel-connection-warning')), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('登录字段按 Tab 和 Shift+Tab 顺序导航，密码显隐不打断字段导航', (tester) async {
    final api = PortalFixtureApi();
    await tester.pumpWidget(portalHost(page: fixturePage(api)));
    await tester.pumpAndSettle();
    bool focused(String key) =>
        tester.widget<TextField>(find.byKey(ValueKey(key))).focusNode!.hasFocus;
    expect(focused('tunnel-origin'), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(focused('tunnel-username'), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(focused('tunnel-password'), isTrue);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(focused('tunnel-username'), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(focused('tunnel-password'), isFalse);
    final buttonFocus =
        Focus.of(tester.element(find.text('登录')), scopeOk: true);
    expect(buttonFocus.hasFocus, isTrue);
    expect(api.logins, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('每个登录字段支持回车和数字键盘回车，忙时不重复提交', (tester) async {
    for (final key in [
      LogicalKeyboardKey.enter,
      LogicalKeyboardKey.numpadEnter
    ]) {
      for (final field in [
        'tunnel-origin',
        'tunnel-username',
        'tunnel-password'
      ]) {
        final api = PortalFixtureApi()
          ..pendingCatalog = Completer<HomeTunnelCatalog>();
        await tester.pumpWidget(portalHost(page: fixturePage(api)));
        await tester.pumpAndSettle();
        await tester.enterText(
            find.byKey(const ValueKey('tunnel-username')), 'fixture-user');
        await tester.enterText(
            find.byKey(const ValueKey('tunnel-password')), 'fixture-password');
        final node =
            tester.widget<TextField>(find.byKey(ValueKey(field))).focusNode!;
        node.requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(key);
        await tester.sendKeyEvent(key);
        await tester.pump();
        expect(api.logins, 1, reason: '$field / $key');
        expect(api.loads, 1);
        api.pendingCatalog!.complete(sampleCatalog());
        await tester.pumpAndSettle();
        expect(find.text('家庭相册'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }
    }
  });

  testWidgets('输入框鼠标悬停填充色不变，键盘焦点边框保持可见', (tester) async {
    final paint = GlobalKey();
    await tester.pumpWidget(
        portalHost(paint: paint, page: fixturePage(PortalFixtureApi())));
    await tester.pumpAndSettle();
    final target = find.byKey(const ValueKey('tunnel-username'));
    final boundary =
        paint.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final point = boundary.globalToLocal(
        tester.getRect(target).bottomRight - const Offset(12, 12));
    Future<int> fillPixel() async {
      final image = await boundary.toImage(pixelRatio: 1);
      final pixels = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final index = (point.dy.floor() * image.width + point.dx.floor()) * 4;
      final value = pixels!.getUint32(index);
      image.dispose();
      return value;
    }

    final before = await tester.runAsync(fillPixel);
    final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(1, 1));
    await mouse.moveTo(tester.getCenter(target));
    await tester.pumpAndSettle();
    final after = await tester.runAsync(fillPixel);
    expect(after, before);
    final decoration = Theme.of(tester.element(target)).inputDecorationTheme;
    expect(decoration.focusedBorder!.borderSide.color,
        isNot(decoration.enabledBorder!.borderSide.color));
    await mouse.removePointer();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('键盘登录仍校验 HTTPS 地址和当前网络许可', (tester) async {
    var allowed = true, builds = 0, saves = 0;
    await tester.pumpWidget(portalHost(
        page: HomeDeskServices(
      readOption: (key) => portalOption(key, allowed: allowed),
      saveOrigin: (_) async => saves++,
      credentialStoreFactory: () => FixtureCredentialStore(),
      apiBuilder: (origin, {required isAllowed, credentialStorage}) {
        builds++;
        return PortalFixtureApi();
      },
    )));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('tunnel-origin')),
        'http://unapproved.example.com');
    await tester.enterText(
        find.byKey(const ValueKey('tunnel-username')), 'fixture-user');
    await tester.enterText(
        find.byKey(const ValueKey('tunnel-password')), 'fixture-password');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.textContaining('请输入有效的 HTTPS'), findsOneWidget);
    expect(builds, 0);
    expect(saves, 0);
    await tester.enterText(find.byKey(const ValueKey('tunnel-origin')),
        'https://console.example.com');
    allowed = false;
    await tester.sendKeyEvent(LogicalKeyboardKey.numpadEnter);
    await tester.pump();
    expect(builds, 0);
    expect(saves, 0);
    expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('tunnel-login')))
            .onPressed,
        isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('首次进入不请求，未批准家庭服务地址时禁用登录', (tester) async {
    var built = 0;
    await tester.pumpWidget(portalHost(
        page: HomeDeskServices(
      credentialStoreFactory: () => FixtureCredentialStore(),
      saveOrigin: (_) async {},
      readOption: (key) => portalOption(key, allowed: false),
      apiBuilder: (origin, {required isAllowed, credentialStorage}) {
        built++;
        return PortalFixtureApi();
      },
    )));
    await tester.pump(const Duration(seconds: 2));
    expect(built, 0);
    final button =
        tester.widget<FilledButton>(find.byKey(const ValueKey('tunnel-login')));
    expect(button.onPressed, isNull);
    expect(find.textContaining('同一台设备支持远程协助和内网穿透'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('登录显示设备与服务，网页打开和原始端点复制不传凭据', (tester) async {
    final api = PortalFixtureApi();
    final account = HomeDeskAccount();
    addTearDown(account.dispose);
    final opened = <Uri>[];
    final copied = <String>[];
    await tester.pumpWidget(portalHost(
        page: HomeDeskServices(
      credentialStoreFactory: () => FixtureCredentialStore(),
      account: account,
      saveOrigin: (_) async {},
      readOption: portalOption,
      apiBuilder: (origin, {required isAllowed, credentialStorage}) => api,
      onOpenUrl: (uri) async {
        opened.add(uri);
        return true;
      },
      onCopy: (value) async {
        copied.add(value);
      },
    )));
    expect(api.logins, 0);
    await enterCredentials(tester);
    expect(api.logins, 1);
    expect(find.text('家庭 NAS'), findsWidgets);
    expect(find.text('家庭相册'), findsOneWidget);
    expect(find.text('● 设备心跳在线'), findsOneWidget);
    await tester.ensureVisible(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('复制地址'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('复制地址'));
    await tester.pumpAndSettle();
    expect(opened.single.toString(), 'https://album.example.com');
    expect(copied.single, 'edge.example.com:10000');
    expect(find.byKey(const ValueKey('tunnel-account-menu')), findsNothing);
    expect(find.text('打开管理台'), findsNothing);
    expect(find.text('退出登录'), findsNothing);
    expect(find.text('取消记住登录'), findsNothing);
    await account.signOut();
    await tester.pumpAndSettle();
    expect(api.logouts, 1);
    expect(api.closed, isTrue);
    expect(find.text('家庭相册'), findsNothing);
    expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('tunnel-password')))
            .controller!
            .text,
        isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('密码错误后不自动重发，修改密码后可手动重新登录', (tester) async {
    final apis = <PortalFixtureApi>[];
    await tester.pumpWidget(portalHost(
        page: HomeDeskServices(
      credentialStoreFactory: () => FixtureCredentialStore(),
      saveOrigin: (_) async {},
      readOption: portalOption,
      apiBuilder: (origin, {required isAllowed, credentialStorage}) {
        final api = PortalFixtureApi(rejectPassword: apis.isEmpty);
        apis.add(api);
        return api;
      },
    )));
    await enterCredentials(tester);
    await tester.pump(const Duration(seconds: 2));
    expect(apis.length, 1);
    expect(apis.first.logins, 1);
    expect(find.byKey(const ValueKey('tunnel-mfa')), findsNothing);
    expect(find.text('账号或密码错误。'), findsOneWidget);
    await tester.enterText(
        find.byKey(const ValueKey('tunnel-password')), 'correct-password');
    await tester.ensureVisible(find.byKey(const ValueKey('tunnel-login')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tunnel-login')));
    await tester.pumpAndSettle();
    expect(apis.length, 2);
    expect(apis.first.closed, isTrue);
    expect(find.text('家庭相册'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('切回纯内网清空会话，迟到目录不恢复旧数据', (tester) async {
    var allowed = true;
    final api = PortalFixtureApi();
    await tester.pumpWidget(portalHost(
        page: HomeDeskServices(
      credentialStoreFactory: () => FixtureCredentialStore(),
      saveOrigin: (_) async {},
      readOption: (key) => portalOption(key, allowed: allowed),
      apiBuilder: (origin, {required isAllowed, credentialStorage}) => api,
    )));
    await enterCredentials(tester);
    final pending = Completer<HomeTunnelCatalog>();
    api.pendingCatalog = pending;
    await tester.tap(find.byKey(const ValueKey('tunnel-refresh')));
    await tester.pump();
    allowed = false;
    await tester.pump(const Duration(seconds: 1));
    expect(api.closed, isTrue);
    expect(find.text('家庭相册'), findsNothing);
    pending.complete(sampleCatalog());
    await tester.pumpAndSettle();
    expect(find.text('家庭相册'), findsNothing);
    expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('tunnel-login')))
            .onPressed,
        isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('单台设备空服务只保留一个新增入口，长名称在大字体下不溢出', (tester) async {
    tester.view.physicalSize = const Size(420, 620);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = PortalFixtureApi()
      ..result = HomeTunnelCatalog(devices: const [
        HomeTunnelDevice(
            id: 'fixture-local',
            name: '书房电脑 · 一个较长的家庭设备名称',
            platform: 'windows',
            online: true),
      ], services: []);
    await tester.pumpWidget(portalHost(page: fixturePage(api), scale: 2));
    await enterCredentials(tester);
    expect(find.byKey(const ValueKey('tunnel-device-filter')), findsNothing);
    expect(find.text('添加服务'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('还没有发布服务'), 160,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('● 设备心跳在线'), findsOneWidget);
    expect(find.text('隧道设备已连接'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('空服务设备使用紧凑布局，旧收藏数据不显示也不改变设备顺序', (tester) async {
    final api = PortalFixtureApi()
      ..result = HomeTunnelCatalog(devices: const [
        HomeTunnelDevice(
            id: 'fixture-first', name: '第一台设备', platform: '', online: false),
        HomeTunnelDevice(
            id: 'fixture-legacy',
            name: '旧收藏设备',
            platform: '',
            online: true,
            favorite: true),
      ], services: []);
    await tester.pumpWidget(portalHost(page: fixturePage(api)));
    await enterCredentials(tester);
    final first = find.byKey(const ValueKey('tunnel-device-fixture-first'));
    final legacy = find.byKey(const ValueKey('tunnel-device-fixture-legacy'));
    await tester.ensureVisible(legacy);
    await tester.pumpAndSettle();
    expect(tester.getRect(first).top, lessThan(tester.getRect(legacy).top));
    expect(tester.getSize(first).height, lessThanOrEqualTo(150));
    expect(tester.getSize(legacy).height, lessThanOrEqualTo(150));
    expect(find.byIcon(Icons.star_rounded), findsNothing);
    expect(find.text('添加服务'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('窄窗口和双倍字体登录及目录可滚动', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = PortalFixtureApi();
    await tester.pumpWidget(portalHost(
        scale: 2,
        page: HomeDeskServices(
          credentialStoreFactory: () => FixtureCredentialStore(),
          saveOrigin: (_) async {},
          readOption: portalOption,
          apiBuilder: (origin, {required isAllowed, credentialStorage}) => api,
        )));
    expect(tester.takeException(), isNull);
    await enterCredentials(tester);
    await tester.scrollUntilVisible(find.text('复制地址'), 180,
        scrollable: find.byType(Scrollable).last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('许可迅速恢复为允许时，旧代次响应与会话仍被丢弃', (tester) async {
    var permission = 'permit-before';
    final api = PortalFixtureApi();
    late bool Function() pinnedAllowed;
    await tester.pumpWidget(portalHost(
        page: HomeDeskServices(
      credentialStoreFactory: () => FixtureCredentialStore(),
      saveOrigin: (_) async {},
      readOption: (key) => portalOption(key, permission: permission),
      apiBuilder: (origin, {required isAllowed, credentialStorage}) {
        pinnedAllowed = isAllowed;
        return api;
      },
    )));
    await enterCredentials(tester);
    expect(pinnedAllowed(), isTrue);
    final pending = Completer<HomeTunnelCatalog>();
    api.pendingCatalog = pending;
    await tester.tap(find.byKey(const ValueKey('tunnel-refresh')));
    await tester.pump();
    // 采样到的布尔值始终为 Y，真实后台已经历撤权与恢复。
    permission = 'permit-after';
    expect(pinnedAllowed(), isFalse);
    pending.complete(sampleCatalog());
    await tester.pumpAndSettle();
    expect(api.closed, isTrue);
    expect(find.text('家庭相册'), findsNothing);
    expect(find.text('登录'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('许可代次变化后的首次旧按钮点击不会打开或复制旧地址', (tester) async {
    for (final action in ['打开', '复制地址']) {
      var permission = 'permit-before';
      final api = PortalFixtureApi();
      var opened = 0;
      var copied = 0;
      await tester.pumpWidget(portalHost(
          page: HomeDeskServices(
        credentialStoreFactory: () => FixtureCredentialStore(),
        saveOrigin: (_) async {},
        key: UniqueKey(),
        readOption: (key) => portalOption(key, permission: permission),
        apiBuilder: (origin, {required isAllowed, credentialStorage}) => api,
        onOpenUrl: (_) async {
          opened++;
          return true;
        },
        onCopy: (_) async {
          copied++;
        },
      )));
      await enterCredentials(tester);
      await tester.ensureVisible(find.text(action));
      await tester.pumpAndSettle();
      permission = 'permit-after';
      // 不推进定时器，让旧目录上的按钮直接观察新的许可代次。
      await tester.tap(find.text(action));
      await tester.pumpAndSettle();
      expect(opened, 0);
      expect(copied, 0);
      expect(api.closed, isTrue);
      expect(find.text('家庭相册'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('新增服务默认选本机，显式设备筛选与原服务设备保持优先', (tester) async {
    final api = LocalDeviceFixtureApi()
      ..result = HomeTunnelCatalog(devices: [
        ...sampleCatalog().devices,
        const HomeTunnelDevice(
            id: 'fixture-local',
            name: '当前电脑',
            platform: 'windows',
            online: true),
      ], services: sampleCatalog().services);
    final account = HomeDeskAccount();
    addTearDown(account.dispose);
    await tester
        .pumpWidget(portalHost(page: fixturePage(api, account: account)));
    await enterCredentials(tester);
    expect(account.localDeviceId, 'fixture-local');
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('tunnel-device-fixture-local')), 140,
        scrollable: find.byType(Scrollable).first);
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('tunnel-device-fixture-local')),
            matching: find.text('● 本机')),
        findsOneWidget);
    tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .jumpTo(0);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tunnel-add-service')));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<HomeDeskServiceEditor>(find.byType(HomeDeskServiceEditor))
            .initial
            .deviceId,
        'fixture-local');
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await account.manageDeviceServices!(account.catalog!.devices.first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tunnel-add-service')));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<HomeDeskServiceEditor>(find.byType(HomeDeskServiceEditor))
            .initial
            .deviceId,
        'fixture-nas');
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find
        .byKey(ValueKey('edit-service-${sampleCatalog().services.first.id}')));
    await tester.tap(find
        .byKey(ValueKey('edit-service-${sampleCatalog().services.first.id}')));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<HomeDeskServiceEditor>(find.byType(HomeDeskServiceEditor))
            .initial
            .deviceId,
        'fixture-nas');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('穿透身份映射到同一设备后，本机标识和新增服务使用统一设备 ID', (tester) async {
    final api = PortalFixtureApi()
      ..result = HomeTunnelCatalog(devices: const [
        HomeTunnelDevice(
            id: 'fixture-other',
            name: '另一台设备',
            platform: 'windows',
            online: true),
        HomeTunnelDevice(
            id: 'fixture-local',
            name: '当前电脑',
            platform: 'windows',
            online: true,
            tunnelDeviceId: 'fixture-nas'),
      ], services: []);
    final account = HomeDeskAccount();
    addTearDown(account.dispose);
    await tester.pumpWidget(portalHost(
        page: fixturePage(api,
            account: account, localAgent: FixtureLocalAgent())));
    await enterCredentials(tester);
    expect(account.localDeviceId, 'fixture-local');
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('tunnel-device-fixture-local')), 140,
        scrollable: find.byType(Scrollable).first);
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('tunnel-device-fixture-local')),
            matching: find.text('● 本机')),
        findsOneWidget);
    tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .jumpTo(0);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tunnel-add-service')));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<HomeDeskServiceEditor>(find.byType(HomeDeskServiceEditor))
            .initial
            .deviceId,
        'fixture-local');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('创建网页服务先本地校验，HTTPS作为本地协议提交', (tester) async {
    final api = PortalFixtureApi();
    await tester.pumpWidget(portalHost(page: fixturePage(api)));
    await enterCredentials(tester);
    await tester.tap(find.byKey(const ValueKey('tunnel-add-service')));
    await tester.pumpAndSettle();
    expect(find.byType(HomeDeskServiceEditor), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('service-save')));
    await tester.pumpAndSettle();
    expect(api.creates, 0);
    expect(find.text('请输入服务名称。'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('service-name')), '家庭影音');
    await tester.enterText(
        find.byKey(const ValueKey('service-local-port')), '8096');
    await tester.enterText(
        find.byKey(const ValueKey('service-subdomain')), 'media');
    await tester
        .ensureVisible(find.byKey(const ValueKey('service-local-scheme')));
    await tester.tap(find.byKey(const ValueKey('service-local-scheme')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('HTTPS').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('service-save')));
    await tester.pumpAndSettle();
    expect(api.creates, 1);
    expect(api.lastValues!['proxy_type'], 'http');
    expect(api.lastValues!['local_scheme'], 'https');
    expect(api.lastValues!['local_port'], 8096);
    expect(api.lastValues!.containsKey('remote_port'), isFalse);
    expect(find.byType(HomeDeskServiceEditor), findsNothing);
    expect(find.text('家庭影音'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('编辑按当前版本保存，在途保存不能双击重发', (tester) async {
    final api = PortalFixtureApi();
    final pending = Completer<HomeTunnelService>();
    api.pendingMutation = pending;
    await tester.pumpWidget(portalHost(page: fixturePage(api)));
    await enterCredentials(tester);
    await tester
        .ensureVisible(find.byKey(const ValueKey('edit-service-fixture-web')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('edit-service-fixture-web')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('service-name')), '新的相册名称');
    await tester.tap(find.byKey(const ValueKey('service-save')));
    await tester.pump();
    expect(api.updates, 1);
    expect(api.lastVersion, 1);
    expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('service-save')))
            .onPressed,
        isNull);
    await tester.tap(find.byKey(const ValueKey('service-save')));
    await tester.pump();
    expect(api.updates, 1);
    pending.complete(api._service({'name': '新的相册名称'}, id: 'fixture-web'));
    await tester.pumpAndSettle();
    expect(find.text('新的相册名称'), findsOneWidget);
    expect(api.lastValues!.containsKey('proxy_type'), isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('409保留草稿，刷新核对确认后使用新版本手动保存', (tester) async {
    final api = PortalFixtureApi();
    api.mutationError =
        const HomeTunnelApiException('设置已变化。', 'VERSION_CONFLICT');
    await tester.pumpWidget(portalHost(page: fixturePage(api)));
    await enterCredentials(tester);
    await tester
        .ensureVisible(find.byKey(const ValueKey('edit-service-fixture-web')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('edit-service-fixture-web')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('service-name')), '保留的草稿名称');
    await tester.tap(find.byKey(const ValueKey('service-save')));
    await tester.pumpAndSettle();
    expect(api.updates, 1);
    expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('service-name')))
            .controller!
            .text,
        '保留的草稿名称');
    expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('service-save')))
            .onPressed,
        isNull);
    api.mutationError = null;
    api.result = HomeTunnelCatalog(devices: api.result.devices, services: [
      api._service({'name': '另一端的新名称'}, id: 'fixture-web', version: 3)
    ]);
    await tester.ensureVisible(find.byKey(const ValueKey('service-review')));
    await tester.tap(find.byKey(const ValueKey('service-review')));
    await tester.pumpAndSettle();
    expect(find.textContaining('另一端的新名称'), findsWidgets);
    expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('service-name')))
            .controller!
            .text,
        '保留的草稿名称');
    expect(api.updates, 1);
    await tester.ensureVisible(find.byKey(const ValueKey('service-reviewed')));
    await tester.tap(find.byKey(const ValueKey('service-reviewed')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('service-save')));
    await tester.pumpAndSettle();
    expect(api.updates, 2);
    expect(api.lastVersion, 3);
    expect(find.byType(HomeDeskServiceEditor), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('写结果未知不自动重放，关闭重开仍保留草稿和核对要求', (tester) async {
    final api = PortalFixtureApi();
    api.mutationError =
        const HomeTunnelApiException('结果未知。', 'MUTATION_UNKNOWN');
    await tester.pumpWidget(portalHost(page: fixturePage(api)));
    await enterCredentials(tester);
    await tester.tap(find.byKey(const ValueKey('tunnel-add-service')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('service-name')), '待核对的服务');
    await tester.enterText(
        find.byKey(const ValueKey('service-subdomain')), 'pending-service');
    await tester.tap(find.byKey(const ValueKey('service-save')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 31));
    await tester.pumpAndSettle();
    expect(api.creates, 1);
    expect(find.textContaining('结果未确认'), findsWidgets);
    expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('service-save')))
            .onPressed,
        isNull);
    await tester.tap(find.text('取消').last);
    await tester.pumpAndSettle();
    await tester
        .ensureVisible(find.byKey(const ValueKey('tunnel-add-service')));
    await tester.tap(find.byKey(const ValueKey('tunnel-add-service')));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('service-name')))
            .controller!
            .text,
        '待核对的服务');
    expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('service-save')))
            .onPressed,
        isNull);
    expect(api.creates, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('暂停和删除均提交版本，删除需要应用内确认', (tester) async {
    final api = PortalFixtureApi();
    await tester.pumpWidget(portalHost(page: fixturePage(api)));
    await enterCredentials(tester);
    final more = find.byKey(const ValueKey('more-service-fixture-web'));
    await tester.ensureVisible(more);
    await tester.pumpAndSettle();
    await tester.tap(more);
    await tester.pumpAndSettle();
    final toggle = find.byKey(const ValueKey('toggle-service-fixture-web'));
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(api.toggles, 1);
    expect(
        api.result.services
            .firstWhere((item) => item.id == 'fixture-web')
            .enabled,
        isFalse);
    await tester.ensureVisible(more);
    await tester.pumpAndSettle();
    await tester.tap(more);
    await tester.pumpAndSettle();
    final delete = find.byKey(const ValueKey('delete-service-fixture-web'));
    await tester.ensureVisible(delete);
    await tester.tap(delete);
    await tester.pumpAndSettle();
    expect(api.deletes, 0);
    await tester.tap(find.text('取消').last);
    await tester.pumpAndSettle();
    expect(api.deletes, 0);
    await tester.tap(more);
    await tester.pumpAndSettle();
    await tester.tap(delete);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm-delete-fixture-web')));
    await tester.pumpAndSettle();
    expect(api.deletes, 1);
    expect(api.lastVersion, 2);
    expect(find.text('家庭相册'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('设备管理只编辑标签，无收藏入口且不伪造设备改名', (tester) async {
    final api = PortalFixtureApi();
    await tester.pumpWidget(portalHost(page: fixturePage(api)));
    await enterCredentials(tester);
    await tester
        .ensureVisible(find.byKey(const ValueKey('edit-device-fixture-nas')));
    await tester.tap(find.byKey(const ValueKey('edit-device-fixture-nas')));
    await tester.pumpAndSettle();
    expect(find.text('设备名称由该设备上的 NestLink 客户端修改。'), findsOneWidget);
    await tester.enterText(
        find.byKey(const ValueKey('device-tags')), '书房, 常开, 书房');
    expect(find.byKey(const ValueKey('device-favorite')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('device-save')));
    await tester.pumpAndSettle();
    expect(api.deviceUpdates, 1);
    expect(api.lastVersion, 1);
    expect(api.lastTags, ['书房', '常开']);
    expect(api.lastFavorite, isFalse);
    expect(find.text('书房'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('登录默认安全记住会话，穿透菜单不提供退出或取消自动登录入口', (tester) async {
    tester.view.physicalSize = const Size(1120, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = PortalFixtureApi();
    await tester.pumpWidget(portalHost(
        page:
            fixturePage(api, store: FixtureCredentialStore(supported: true))));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tunnel-remember')), findsNothing);
    expect(find.text('打开管理台'), findsNothing);
    expect(find.text('登录并查看'), findsNothing);
    expect(find.text('登录'), findsOneWidget);
    expect(
        tester
            .getRect(find.byKey(const ValueKey('nestlink-login-brand')))
            .right,
        lessThan(tester
            .getRect(find.byKey(const ValueKey('nestlink-login-form')))
            .left));
    await enterCredentials(tester);
    expect(api.rememberRequested, isTrue);
    expect(find.byKey(const ValueKey('tunnel-account-menu')), findsNothing);
    expect(find.text('打开管理台'), findsNothing);
    expect(find.byKey(const ValueKey('tunnel-forget')), findsNothing);
    expect(find.text('退出登录'), findsNothing);
    expect(find.text('取消自动登录'), findsNothing);
    expect(find.text('取消记住登录'), findsNothing);
    expect(api.isSignedIn, isTrue);
    expect(api.rememberedLogin, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('仅已批准origin的记住账号可恢复，关闭页面保留密文', (tester) async {
    final store =
        FixtureCredentialStore(supported: true, record: rememberedFixture());
    final api = PortalFixtureApi();
    await tester.pumpWidget(portalHost(page: fixturePage(api, store: store)));
    await tester.pumpAndSettle();
    expect(api.restores, 1);
    expect(api.logins, 0);
    expect(find.text('家庭相册'), findsOneWidget);
    expect(find.text('已恢复记住的登录。'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    expect(api.closed, isTrue);
    expect(store.record, isNotNull);
    expect(store.clears, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('统一账号退出等待安全存储清除，重复点击只退出一次且下次不自动恢复', (tester) async {
    final store =
        FixtureCredentialStore(supported: true, record: rememberedFixture());
    final account = HomeDeskAccount();
    final api = PortalFixtureApi();
    addTearDown(account.dispose);
    await tester.pumpWidget(
        portalHost(page: fixturePage(api, store: store, account: account)));
    await tester.pumpAndSettle();
    expect(api.restores, 1);
    expect(account.signedIn, isTrue);
    store.pendingClear = Completer<void>();
    final first = account.signOut();
    final duplicate = account.signOut();
    expect(identical(first, duplicate), isTrue);
    await tester.pump();
    expect(api.logouts, 1);
    expect(account.signedIn, isFalse);
    expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('tunnel-login')))
            .onPressed,
        isNull);
    expect(store.record, isNotNull);
    store.pendingClear!.complete();
    await first;
    await tester.pumpAndSettle();
    expect(store.record, isNull);
    expect(api.closed, isTrue);
    expect(find.text('家庭相册'), findsNothing);
    await tester.pump(const Duration(seconds: 10));
    expect(api.restores, 1);
    await tester.pumpWidget(const SizedBox());
    final restarted = PortalFixtureApi();
    await tester.pumpWidget(portalHost(
        page: fixturePage(restarted, store: store, account: account)));
    await tester.pumpAndSettle();
    expect(restarted.restores, 0);
    expect(restarted.logins, 0);
    expect(find.text('登录'), findsOneWidget);
    await enterCredentials(tester);
    expect(restarted.logins, 1);
    expect(restarted.rememberRequested, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('账号无owner回调时退出兼容调用API并关闭会话', (tester) async {
    final account = HomeDeskAccount();
    final api = PortalFixtureApi()..signedIn = true;
    addTearDown(account.dispose);
    account.publish(api, sampleCatalog(), '', (_) async {});
    await account.signOut();
    expect(account.api, isNull);
    expect(api.logouts, 1);
    expect(api.closed, isTrue);
  });

  testWidgets('统一退出遇到网络错误仍清除本机恢复凭据', (tester) async {
    final store =
        FixtureCredentialStore(supported: true, record: rememberedFixture());
    final api = PortalFixtureApi()
      ..logoutError = const HomeTunnelApiException('服务暂时离线。', 'NETWORK_ERROR');
    final account = HomeDeskAccount();
    addTearDown(account.dispose);
    await tester.pumpWidget(
        portalHost(page: fixturePage(api, store: store, account: account)));
    await tester.pumpAndSettle();
    await account.signOut();
    await tester.pumpAndSettle();
    expect(store.record, isNull);
    expect(api.closed, isTrue);
    expect(account.signedIn, isFalse);
    expect(find.text('已退出本机登录，但服务端会话暂未能关闭。'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('共享设备管理选择穿透筛选，确认删除后隐藏撤销设备及其遗留服务', (tester) async {
    final account = HomeDeskAccount();
    final api = PortalFixtureApi();
    addTearDown(account.dispose);
    await tester
        .pumpWidget(portalHost(page: fixturePage(api, account: account)));
    await enterCredentials(tester);
    final device = account.catalog!.devices.first;
    final manage = account.manageDeviceServices!;
    final remove = account.deleteDevice!;
    await manage(device);
    await tester.pumpAndSettle();
    final filter = tester.widget<DropdownButtonFormField<String>>(
        find.byKey(const ValueKey('tunnel-device-filter')));
    expect(filter.initialValue, device.id);
    expect(find.byKey(const ValueKey('tunnel-device-fixture-offline')),
        findsNothing);
    api.pendingDeviceDelete = Completer<void>();
    api.keepDeletedDeviceInCatalog = true;
    final deleting = remove(device);
    await tester.pump();
    expect(find.text('家庭相册'), findsOneWidget);
    expect(api.deviceDeletes, 1);
    api.pendingDeviceDelete!.complete();
    await deleting;
    await tester.pumpAndSettle();
    expect(account.catalog!.devices.any((entry) => entry.id == device.id),
        isFalse);
    expect(find.text('家庭相册'), findsNothing);
    expect(find.text('SSH 连接'), findsNothing);
    expect(find.text('未返回的设备'), findsNothing);
    expect(find.text('1 台设备 · 0 项服务'), findsNothing);
    expect(account.catalog!.devices.single.id, 'fixture-offline');
    expect(api.loads, lessThan(10));
    await expectLater(remove(device), throwsA(isA<HomeTunnelApiException>()));
    expect(api.deviceDeletes, 1);
    await account.signOut();
    await expectLater(manage(device), throwsA(isA<HomeTunnelApiException>()));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('设备撤销失败保留原目录，不把孤儿服务伪造成可操作设备', (tester) async {
    final account = HomeDeskAccount();
    final api = PortalFixtureApi();
    addTearDown(account.dispose);
    await tester
        .pumpWidget(portalHost(page: fixturePage(api, account: account)));
    await enterCredentials(tester);
    final device = account.catalog!.devices.first;
    api.mutationError =
        const HomeTunnelApiException('本次撤销结果未确认，请刷新目录。', 'MUTATION_UNKNOWN');
    await expectLater(
        account.deleteDevice!(device), throwsA(isA<HomeTunnelApiException>()));
    await tester.pumpAndSettle();
    expect(find.text('家庭相册'), findsOneWidget);
    expect(
        account.catalog!.devices.any((entry) => entry.id == device.id), isTrue);
    api.mutationError = null;
    api.result = HomeTunnelCatalog(
        devices:
            api.result.devices.where((entry) => entry.id != device.id).toList(),
        services: api.result.services);
    await tester.tap(find.byKey(const ValueKey('tunnel-refresh')));
    await tester.pumpAndSettle();
    expect(find.text('家庭相册'), findsNothing);
    expect(find.text('未返回的设备'), findsNothing);
    expect(
        find.byKey(const ValueKey('edit-service-fixture-web')), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('删除本机停止接入，刷新或重试不重新登记，旧回调撤权后不可调用', (tester) async {
    final account = HomeDeskAccount();
    final api = PortalFixtureApi();
    final agent = FixtureLocalAgent();
    var retries = 0;
    var allowed = true;
    addTearDown(account.dispose);
    await tester.pumpWidget(portalHost(
        page: fixturePage(api,
            account: account,
            localAgent: agent,
            readOption: (key) => portalOption(key, allowed: allowed),
            onRetryLocal: (_, __) async {
              retries++;
            })));
    await enterCredentials(tester);
    final device = account.catalog!.devices.first;
    final remove = account.deleteDevice!;
    await remove(device);
    await tester.pumpAndSettle();
    expect(agent.stops, 1);
    expect(api.deviceDeletes, 1);
    await tester.tap(find.byKey(const ValueKey('tunnel-refresh')));
    await tester.pumpAndSettle();
    expect(agent.stops, 1);
    expect(retries, 0);
    agent.error = const HomeDeskAgentException('DEVICE_OUTSIDE_ACCOUNT');
    await tester.tap(find.byKey(const ValueKey('tunnel-refresh')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tunnel-connection-notice')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tunnel-retry-local')));
    await tester.pumpAndSettle();
    expect(find.text('本机设备已删除，请重新登录后再登记。'), findsOneWidget);
    expect(retries, 0);
    final close = find.widgetWithText(TextButton, '关闭');
    expect(close.hitTestable(), findsOneWidget);
    await tester.tap(close);
    await tester.pumpAndSettle();
    allowed = false;
    await expectLater(remove(device), throwsA(isA<HomeTunnelApiException>()));
    expect(api.deviceDeletes, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('纯内网不读取恢复凭据，origin不匹配不联网或误删别的账号', (tester) async {
    final lanStore =
        FixtureCredentialStore(supported: true, record: rememberedFixture());
    final lanApi = PortalFixtureApi();
    await tester.pumpWidget(portalHost(
        page: fixturePage(lanApi,
            store: lanStore,
            readOption: (key) => portalOption(key, allowed: false))));
    await tester.pumpAndSettle();
    expect(lanStore.peeks, 0);
    expect(lanStore.clears, 0);
    expect(lanApi.restores, 0);
    await tester.pumpWidget(const SizedBox());
    final otherStore = FixtureCredentialStore(
        supported: true,
        record: rememberedFixture(origin: 'https://other.example.com'));
    final otherApi = PortalFixtureApi();
    await tester
        .pumpWidget(portalHost(page: fixturePage(otherApi, store: otherStore)));
    await tester.pumpAndSettle();
    expect(otherApi.restores, 0);
    expect(otherStore.clears, 0);
    expect(find.textContaining('未恢复登录'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('批准origin后才固定许可，保存带来的epoch变化不误撤登录', (tester) async {
    var origin = '';
    var permission = 'permit-before-save';
    final api = PortalFixtureApi();
    late bool Function() pinned;
    await tester.pumpWidget(portalHost(
        page: HomeDeskServices(
            credentialStoreFactory: () => FixtureCredentialStore(),
            readOption: (key) =>
                portalOption(key, origin: origin, permission: permission),
            saveOrigin: (value) async {
              origin = value;
              permission = 'permit-after-save';
            },
            apiBuilder: (value, {required isAllowed, credentialStorage}) {
              pinned = isAllowed;
              return api;
            })));
    await enterCredentials(tester);
    expect(origin, 'https://console.example.com');
    expect(pinned(), isTrue);
    expect(api.logins, 1);
    expect(api.closed, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('原始连接新建遵循服务端能力，公网端口不由客户端指定', (tester) async {
    final api = PortalFixtureApi();
    await tester.pumpWidget(portalHost(page: fixturePage(api)));
    await enterCredentials(tester);
    await tester.tap(find.byKey(const ValueKey('tunnel-add-service')));
    await tester.pumpAndSettle();
    final dropdown = tester.widget<DropdownButton<String>>(find.descendant(
        of: find.byKey(const ValueKey('service-type')),
        matching: find.byType(DropdownButton<String>)));
    expect(dropdown.items!.map((item) => item.value).toList(), ['http']);
    await tester.tap(find.text('取消').last);
    await tester.pumpAndSettle();
    api.result = HomeTunnelCatalog(
        devices: api.result.devices,
        services: api.result.services,
        capabilities: const HomeTunnelCapabilities(
            tcpEnabled: true,
            tcpCanCreate: true,
            udpEnabled: true,
            udpCanCreate: true,
            automaticPorts: true));
    await tester.tap(find.byKey(const ValueKey('tunnel-refresh')));
    await tester.pumpAndSettle();
    for (final type in ['tcp', 'udp']) {
      await tester
          .ensureVisible(find.byKey(const ValueKey('tunnel-add-service')));
      await tester.tap(find.byKey(const ValueKey('tunnel-add-service')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('service-name')),
          '合成${type.toUpperCase()}服务');
      await tester.tap(find.byKey(const ValueKey('service-type')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(type.toUpperCase()).last);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('service-local-scheme')), findsNothing);
      expect(find.byKey(const ValueKey('service-subdomain')), findsNothing);
      await tester.enterText(find.byKey(const ValueKey('service-local-port')),
          type == 'tcp' ? '22' : '5353');
      await tester.tap(find.byKey(const ValueKey('service-save')));
      await tester.pumpAndSettle();
      expect(api.lastValues!['proxy_type'], type);
      expect(api.lastValues!.containsKey('remote_port'), isFalse);
      expect(api.lastValues!.containsKey('tcp_remote_port'), isFalse);
      expect(api.lastValues!.containsKey('subdomain'), isFalse);
    }
    expect(api.creates, 2);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('设备元数据冲突保留标签草稿，核对后使用新版本', (tester) async {
    final api = PortalFixtureApi();
    api.mutationError =
        const HomeTunnelApiException('设置已变化。', 'VERSION_CONFLICT');
    await tester.pumpWidget(portalHost(page: fixturePage(api)));
    await enterCredentials(tester);
    await tester
        .ensureVisible(find.byKey(const ValueKey('edit-device-fixture-nas')));
    await tester.tap(find.byKey(const ValueKey('edit-device-fixture-nas')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('device-tags')), '保留草稿');
    await tester.tap(find.byKey(const ValueKey('device-save')));
    await tester.pumpAndSettle();
    expect(api.deviceUpdates, 1);
    expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('device-save')))
            .onPressed,
        isNull);
    api.mutationError = null;
    api.result = HomeTunnelCatalog(devices: const [
      HomeTunnelDevice(
          id: 'fixture-nas',
          name: '家庭 NAS',
          platform: '',
          online: true,
          tags: ['另一端设置'],
          metadataVersion: 4)
    ], services: api.result.services);
    await tester.ensureVisible(find.byKey(const ValueKey('device-review')));
    await tester.tap(find.byKey(const ValueKey('device-review')));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('device-tags')))
            .controller!
            .text,
        '保留草稿');
    await tester.ensureVisible(find.byKey(const ValueKey('device-reviewed')));
    await tester.tap(find.byKey(const ValueKey('device-reviewed')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('device-save')));
    await tester.pumpAndSettle();
    expect(api.deviceUpdates, 2);
    expect(api.lastVersion, 4);
    expect(api.lastTags, ['保留草稿']);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('恢复失败不通过UI全局删除新记录，退出清理失败准确提示', (tester) async {
    final store =
        FixtureCredentialStore(supported: true, record: rememberedFixture());
    final failed = PortalFixtureApi()..restoreFails = true;
    await tester
        .pumpWidget(portalHost(page: fixturePage(failed, store: store)));
    await tester.pumpAndSettle();
    expect(failed.restores, 1);
    expect(failed.closed, isTrue);
    expect(store.clears, 0);
    expect(find.textContaining('保存的登录未能恢复'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    final api = PortalFixtureApi()
      ..logoutError =
          const HomeTunnelApiException('无法清除安全存储。', 'SECURE_STORE_ERROR');
    final account = HomeDeskAccount();
    final failedStore = FixtureCredentialStore(supported: true);
    addTearDown(account.dispose);
    await tester.pumpWidget(portalHost(
        page: fixturePage(api, account: account, store: failedStore)));
    await enterCredentials(tester);
    failedStore.clearFails = true;
    await account.signOut();
    await tester.pumpAndSettle();
    expect(api.closed, isTrue);
    expect(find.textContaining('无法确认清除保存的登录'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('普通窗口服务弹窗全部字段可见，校验后保存按钮仍可见', (tester) async {
    tester.view.physicalSize = const Size(780, 560);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = PortalFixtureApi();
    await tester.pumpWidget(portalHost(page: fixturePage(api)));
    await enterCredentials(tester);
    await tester.tap(find.byKey(const ValueKey('tunnel-add-service')));
    await tester.pumpAndSettle();
    final viewport =
        tester.getRect(find.byKey(const ValueKey('service-form-scroll')));
    for (final key in [
      'service-device',
      'service-name',
      'service-type',
      'service-local-host',
      'service-local-port',
      'service-local-scheme',
      'service-subdomain',
      'service-enabled'
    ]) {
      final field = tester.getRect(find.byKey(ValueKey(key)));
      expect(field.top, greaterThanOrEqualTo(viewport.top));
      expect(field.bottom, lessThanOrEqualTo(viewport.bottom));
    }
    final scroll = tester.widget<SingleChildScrollView>(
        find.byKey(const ValueKey('service-form-scroll')));
    expect(scroll.controller!.position.maxScrollExtent, lessThanOrEqualTo(0.5));
    final save = find.byKey(const ValueKey('service-save'));
    expect(save.hitTestable(), findsOneWidget);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(api.creates, 0);
    expect(find.text('请输入服务名称。'), findsOneWidget);
    expect(save.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('服务弹窗收窄并放大字体后保留草稿，底部按钮固定可操作', (tester) async {
    tester.view.physicalSize = const Size(780, 560);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = PortalFixtureApi();
    await tester.pumpWidget(portalHost(page: fixturePage(api)));
    await enterCredentials(tester);
    await tester.tap(find.byKey(const ValueKey('tunnel-add-service')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('service-name')), '窗口草稿');
    await tester.enterText(
        find.byKey(const ValueKey('service-subdomain')), 'draft');
    await tester.enterText(
        find.byKey(const ValueKey('service-local-port')), '8080');
    tester.view.physicalSize = const Size(360, 560);
    await tester.pumpWidget(portalHost(page: fixturePage(api), scale: 2));
    await tester.pumpAndSettle();
    for (final key in [
      'service-name',
      'service-subdomain',
      'service-local-port'
    ]) {
      expect(
          tester
              .widget<TextFormField>(find.byKey(ValueKey(key)))
              .controller!
              .text,
          key == 'service-name'
              ? '窗口草稿'
              : key == 'service-subdomain'
                  ? 'draft'
                  : '8080');
    }
    final editorContext = tester.element(find.byType(HomeDeskServiceEditor));
    expect(MediaQuery.textScalerOf(editorContext).scale(14), 28);
    final save = find.byKey(const ValueKey('service-save'));
    expect(save.hitTestable(), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('service-subdomain')));
    await tester.pumpAndSettle();
    expect(save.hitTestable(), findsOneWidget);
    expect(api.creates, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('完整服务和设备编辑器在窄窗口双倍字体下可滚动且不溢出', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = PortalFixtureApi();
    await tester.pumpWidget(portalHost(scale: 2, page: fixturePage(api)));
    await enterCredentials(tester);
    final edit = find.byKey(const ValueKey('edit-service-fixture-web'));
    await tester.scrollUntilVisible(edit, 160,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(edit);
    await tester.pumpAndSettle();
    expect(find.byType(HomeDeskServiceEditor), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('service-subdomain')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('取消').last);
    await tester.pumpAndSettle();
    final metadata = find.byKey(const ValueKey('edit-device-fixture-nas'));
    await tester.ensureVisible(metadata);
    await tester.pumpAndSettle();
    await tester.tap(metadata);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('device-tags')));
    await tester.pumpAndSettle();
    expect(find.byType(HomeDeskDeviceEditor), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  if (Platform.environment.containsKey('HOMEDESK_SERVICES_PREVIEW')) {
    testWidgets('导出合成服务门户预览', (tester) async {
      tester.view.physicalSize = const Size(780, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fonts = FontLoader('HomeDeskPreview');
      fonts.addFont(Future.value(ByteData.sublistView(
          File('C:/Windows/Fonts/msyh.ttc').readAsBytesSync())));
      await fonts.load();
      final icons = FontLoader('MaterialIcons');
      icons.addFont(Future.value(ByteData.sublistView(File(
              'R:/toolchains/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf')
          .readAsBytesSync())));
      await icons.load();
      for (final dark in [false, true]) {
        final api = PortalFixtureApi();
        final paint = GlobalKey();
        await tester.pumpWidget(MaterialApp(
          theme: ThemeData(
              brightness: dark ? Brightness.dark : Brightness.light,
              fontFamily: 'HomeDeskPreview'),
          builder: (context, child) =>
              RepaintBoundary(key: paint, child: child!),
          home: Scaffold(
              body: HomeDeskDashboard(
            brandName: 'NestLink',
            devicesBuilder: (_) => const Center(child: Text('家庭设备')),
            recentBuilder: (_) => const Center(child: Text('最近连接')),
            servicesBuilder: (_) => HomeDeskServices(
                credentialStoreFactory: () => FixtureCredentialStore(),
                saveOrigin: (_) async {},
                readOption: portalOption,
                apiBuilder: (origin, {required isAllowed, credentialStorage}) =>
                    api),
            localBuilder: (_) => const SizedBox(),
            statusBuilder: (_) => const SizedBox(),
            onSettings: () {},
            onConnect: (_) {},
          )),
        ));
        await tester.tap(find.byTooltip('内网穿透'));
        await tester.pumpAndSettle();
        await enterCredentials(tester);
        final boundary =
            paint.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final output =
              Directory(Platform.environment['HOMEDESK_SERVICES_PREVIEW']!)
                ..createSync(recursive: true);
          File('${output.path}/services-${dark ? 'dark' : 'light'}.png')
              .writeAsBytesSync(bytes!.buffer.asUint8List());
          image.dispose();
        });
        api.result = HomeTunnelCatalog(devices: const [
          HomeTunnelDevice(
              id: 'fixture-local',
              name: '书房电脑 · NestLink',
              platform: 'windows',
              online: true),
        ], services: []);
        await tester.tap(find.byKey(const ValueKey('tunnel-refresh')));
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final output =
              Directory(Platform.environment['HOMEDESK_SERVICES_PREVIEW']!);
          File('${output.path}/services-${dark ? 'dark' : 'light'}-empty.png')
              .writeAsBytesSync(bytes!.buffer.asUint8List());
          image.dispose();
        });
        await tester.tap(find.byKey(const ValueKey('tunnel-add-service')));
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final output =
              Directory(Platform.environment['HOMEDESK_SERVICES_PREVIEW']!);
          File('${output.path}/service-editor-${dark ? 'dark' : 'light'}.png')
              .writeAsBytesSync(bytes!.buffer.asUint8List());
          image.dispose();
        });
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }
    });
  }
}
