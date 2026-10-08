// HOMEDESK: 合成账号目录验证服务门户，不访问公网、真实账号或系统剪贴板。
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/homedesk_dashboard.dart';
import 'package:flutter_hbb/homedesk_services.dart';
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
  bool needsMfa;
  int logins = 0;
  int loads = 0;
  int logouts = 0;
  int restores = 0;
  int creates = 0;
  int updates = 0;
  int toggles = 0;
  int deletes = 0;
  int deviceUpdates = 0;
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

  PortalFixtureApi({this.needsMfa = false})
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
      String? mfaCode,
      bool rememberLogin = false}) async {
    logins++;
    if (needsMfa && mfaCode == null) {
      throw const HomeTunnelApiException('请输入动态码或恢复码。', 'MFA_REQUIRED');
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
    if (logoutError != null) throw logoutError!;
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
        theme: ThemeData(
            brightness: dark ? Brightness.dark : Brightness.light,
            fontFamily:
                Platform.environment.containsKey('HOMEDESK_SERVICES_PREVIEW')
                    ? 'HomeDeskPreview'
                    : null),
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
        String Function(String)? readOption,
        Future<void> Function(String)? saveOrigin}) =>
    HomeDeskServices(
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

void main() {
  testWidgets('首次进入不请求，纯内网禁用登录与公网入口', (tester) async {
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
    expect(find.textContaining('当前为纯内网模式'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('登录显示设备与服务，网页打开和原始端点复制不传凭据', (tester) async {
    final api = PortalFixtureApi();
    final opened = <Uri>[];
    final copied = <String>[];
    await tester.pumpWidget(portalHost(
        page: HomeDeskServices(
      credentialStoreFactory: () => FixtureCredentialStore(),
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
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('tunnel-account-menu')), -180,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tunnel-account-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开管理台'));
    await tester.pumpAndSettle();
    expect(opened.last.toString(), 'https://console.example.com');
    await tester.tap(find.byKey(const ValueKey('tunnel-account-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('退出登录'));
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

  testWidgets('MFA 必须由用户再次提交，不自动重发登录', (tester) async {
    final apis = <PortalFixtureApi>[];
    await tester.pumpWidget(portalHost(
        page: HomeDeskServices(
      credentialStoreFactory: () => FixtureCredentialStore(),
      saveOrigin: (_) async {},
      readOption: portalOption,
      apiBuilder: (origin, {required isAllowed, credentialStorage}) {
        final api = PortalFixtureApi(needsMfa: true);
        apis.add(api);
        return api;
      },
    )));
    await enterCredentials(tester);
    await tester.pump(const Duration(seconds: 2));
    expect(apis.length, 1);
    expect(apis.first.logins, 1);
    expect(find.byKey(const ValueKey('tunnel-mfa')), findsOneWidget);
    await tester.enterText(
        find.byKey(const ValueKey('tunnel-mfa')), 'fixture-recovery');
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
    expect(find.text('登录并查看'), findsOneWidget);
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

  testWidgets('设备管理只编辑标签和收藏，不伪造设备改名', (tester) async {
    final api = PortalFixtureApi();
    await tester.pumpWidget(portalHost(page: fixturePage(api)));
    await enterCredentials(tester);
    await tester
        .ensureVisible(find.byKey(const ValueKey('edit-device-fixture-nas')));
    await tester.tap(find.byKey(const ValueKey('edit-device-fixture-nas')));
    await tester.pumpAndSettle();
    expect(find.text('设备名称由该设备上的 home-tunnel 客户端修改。'), findsOneWidget);
    await tester.enterText(
        find.byKey(const ValueKey('device-tags')), '书房, 常开, 书房');
    await tester.tap(find.byKey(const ValueKey('device-favorite')));
    await tester.tap(find.byKey(const ValueKey('device-save')));
    await tester.pumpAndSettle();
    expect(api.deviceUpdates, 1);
    expect(api.lastVersion, 1);
    expect(api.lastTags, ['书房', '常开']);
    expect(api.lastFavorite, isTrue);
    expect(find.text('书房'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('记住登录默认不勾选，人工勾选才传给账号API', (tester) async {
    final api = PortalFixtureApi();
    await tester.pumpWidget(portalHost(
        page:
            fixturePage(api, store: FixtureCredentialStore(supported: true))));
    await tester.pumpAndSettle();
    final remember = find.byKey(const ValueKey('tunnel-remember'));
    expect(tester.widget<CheckboxListTile>(remember).value, isFalse);
    await tester.ensureVisible(remember);
    await tester.tap(remember);
    await tester.pumpAndSettle();
    await enterCredentials(tester);
    expect(api.rememberRequested, isTrue);
    await tester.tap(find.byKey(const ValueKey('tunnel-account-menu')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tunnel-forget')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tunnel-forget')));
    await tester.pumpAndSettle();
    expect(api.isSignedIn, isTrue);
    expect(api.rememberedLogin, isFalse);
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
    await tester.pumpWidget(portalHost(page: fixturePage(api)));
    await enterCredentials(tester);
    await tester.tap(find.byKey(const ValueKey('tunnel-account-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('退出登录'));
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
    await tester.ensureVisible(find.byKey(const ValueKey('device-favorite')));
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
              '../target/toolchains/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf')
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
            brandName: 'HomeDesk',
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
        await tester.tap(find.byTooltip('家庭服务'));
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
              name: '书房电脑 · HomeDesk',
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
