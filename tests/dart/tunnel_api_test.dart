// HOMEDESK: 直接测试生产 API，仅将明确的测试 HTTPS origin 映射到回环服务。
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../../client/flutter/lib/homedesk_tunnel_api.dart';
import '../../client/flutter/lib/homedesk_tunnel_session.dart';

const origin = 'https://control.example.invalid';
const oldAccess = 'fixture-old-access-token';
const oldRefresh = 'fixture-old-refresh-token';
const nextAccess = 'fixture-next-access-token';
const nextRefresh = 'fixture-next-refresh-token';

void expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> rejects(Future<void> Function() action, String code) async {
  try {
    await action();
  } on HomeTunnelApiException catch (error) {
    expect(error.code == code, '预期 $code，实际 ${error.code}');
    expect(!error.message.contains('server-secret'), '错误不能回显服务端任意内容');
    return;
  }
  throw StateError('应拒绝请求：$code');
}

String uuid(int value) =>
    '11111111-1111-4111-8111-${value.toString().padLeft(12, '0')}';

Map<String, Object?> page(List<Object?> items, {int current = 1, int? total}) {
  final count = total ?? items.length;
  return {
    'page': current,
    'page_size': 100,
    'total': count,
    'total_pages': count == 0 ? 1 : (count / 100).ceil(),
    'items': items,
  };
}

Map<String, Object?> device(int number) => {
      'id': uuid(number),
      'name': '家庭设备 $number',
      'status': 'active',
      'online': number.isOdd,
      'tags': [],
      'favorite': false,
      'metadata_version': 1,
    };

Map<String, Object?> service(int number, String type) => {
      'id': uuid(10000 + number),
      'device_id': uuid(1),
      'name': '家庭服务 $number',
      'proxy_type': type,
      'enabled': true,
      'state': 'Online',
      'version': 3,
      'access_policy_version': 2,
      'local_scheme': 'http',
      'local_host': '127.0.0.1',
      'local_port': 8080,
      'subdomain': 'demo-service-$number',
      'remote_port': type == 'http' ? null : 10000,
      'public_url': type == 'http' ? 'https://album.example.invalid' : null,
      'public_endpoint': type == 'http' ? null : 'edge.example.invalid:10000',
    };

Map<String, dynamic> httpDraft() => {
      'device_id': uuid(1),
      'name': '家庭相册',
      'proxy_type': 'http',
      'local_scheme': 'http',
      'local_host': '127.0.0.1',
      'local_port': 2283,
      'subdomain': 'demo-album',
      'enabled': true,
    };

const rawCapabilities = {
  'supported': true,
  'automatic_ports': true,
  'tcp': {
    'enabled': true,
    'can_create': true,
    'port_start': 10000,
    'port_end': 10009
  },
  'udp': {
    'enabled': true,
    'can_create': true,
    'port_start': 10000,
    'port_end': 10009
  },
};

Map<String, Object?> loginReply({bool mustChange = false}) => {
      'user': {
        'id': uuid(99999),
        'username': 'demo',
        'display_name': '家庭账号',
        'role': 'user',
        'password_state': mustChange ? 'must_change' : 'normal',
      },
      'password_change_required': mustChange,
      'access_token': oldAccess,
      'refresh_token': oldRefresh,
      'csrf_token': 'fixture-csrf',
      'access_expires_at': '2030-01-01T00:00:00Z',
      'refresh_expires_at': '2030-02-01T00:00:00Z',
    };

Map<String, Object?> refreshReply() => {
      'access_token': nextAccess,
      'refresh_token': nextRefresh,
      'refresh_expires_at': '2030-02-01T00:00:00Z',
    };

class MemorySecureStore extends HomeDeskCredentialStorage {
  @override
  bool get supported => true;
  HomeDeskPortalCredential? record;
  String generation = '0';
  int changes = 0;
  bool failSave = false;
  bool failAfterSave = false;
  bool failDiscard = false;
  Future<void> Function()? beforeSave;
  final List<String> events = [];
  CredentialTransaction rotate() =>
      CredentialTransaction(generation = '${++changes}');
  @override
  Future<HomeDeskRememberedAccount?> peekAccount() async => record == null
      ? null
      : HomeDeskRememberedAccount(
          origin: record!.origin,
          userId: record!.userId,
          username: record!.username,
          displayName: record!.displayName);
  @override
  Future<CredentialTransaction> begin() async {
    events.add('begin');
    record = null;
    return rotate();
  }

  @override
  Future<CredentialLease?> consume() async {
    events.add('consume');
    final current = record;
    if (current == null) return null;
    record = null;
    return CredentialLease(record: current, transaction: rotate());
  }

  @override
  Future<void> save(
      HomeDeskPortalCredential value, CredentialTransaction transaction) async {
    events.add('save-start');
    await beforeSave?.call();
    if (failSave || generation != transaction.generation)
      throw StateError('保存拒绝');
    record = value;
    if (failAfterSave) throw StateError('落盘后回报失败');
    events.add('save-done');
  }

  @override
  Future<void> clear() async {
    events.add('clear');
    rotate();
    record = null;
  }

  @override
  Future<void> discard(CredentialTransaction transaction) async {
    if (generation != transaction.generation) {
      events.add('discard-stale');
      return;
    }
    if (failDiscard) throw StateError('本机清理拒绝');
    events.add('discard');
    rotate();
    record = null;
  }
}

HomeDeskPortalCredential remembered(
        {String savedOrigin = origin, String? userId}) =>
    HomeDeskPortalCredential(
        origin: savedOrigin,
        userId: userId ?? uuid(99999),
        username: 'demo',
        displayName: '家庭账号',
        refreshToken: oldRefresh,
        refreshExpiresAt: DateTime.utc(2030, 2, 1));

Future<void> jsonResponse(HttpRequest request, Object? value,
    {int status = 200}) async {
  request.response.statusCode = status;
  request.response.headers.contentType = ContentType.json;
  request.response.write(jsonEncode(value));
  await request.response.close();
}

class LocalTransport implements HttpClient {
  final HttpClient inner = HttpClient();
  final Uri local;
  void Function()? afterOpen;
  void Function()? onChunk;
  void Function()? onDone;
  bool forceClosed = false;
  String? selectedProxy;
  final List<Uri> targets = [];
  LocalTransport(this.local);

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    targets.add(url);
    expect(url.scheme == 'https' && url.origin == origin,
        '所有 API 凭据只能发送到固定 origin');
    final target = local.replace(path: url.path, query: url.query);
    final request = await inner.openUrl(method, target);
    afterOpen?.call();
    return ObservedRequest(request, this);
  }

  @override
  set findProxy(String Function(Uri)? value) {
    selectedProxy = value?.call(Uri.parse(origin));
    inner.findProxy = value;
  }

  @override
  set connectionTimeout(Duration? value) => inner.connectionTimeout = value;
  @override
  void close({bool force = false}) {
    forceClosed = forceClosed || force;
    inner.close(force: force);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class ObservedRequest implements HttpClientRequest {
  final HttpClientRequest inner;
  final LocalTransport transport;
  ObservedRequest(this.inner, this.transport);
  @override
  HttpHeaders get headers => inner.headers;
  @override
  set followRedirects(bool value) => inner.followRedirects = value;
  @override
  set maxRedirects(int value) => inner.maxRedirects = value;
  @override
  set contentLength(int value) => inner.contentLength = value;
  @override
  void add(List<int> data) => inner.add(data);
  @override
  void abort([Object? exception, StackTrace? stackTrace]) =>
      inner.abort(exception, stackTrace);
  @override
  Future<HttpClientResponse> close() async =>
      ObservedResponse(await inner.close(), transport);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class ObservedResponse extends Stream<List<int>> implements HttpClientResponse {
  final HttpClientResponse inner;
  final LocalTransport transport;
  ObservedResponse(this.inner, this.transport);
  @override
  int get statusCode => inner.statusCode;
  @override
  int get contentLength => inner.contentLength;
  @override
  StreamSubscription<List<int>> listen(void Function(List<int>)? onData,
      {Function? onError, void Function()? onDone, bool? cancelOnError}) {
    return inner.listen(
        (chunk) {
          transport.onChunk?.call();
          onData?.call(chunk);
        },
        onError: onError,
        onDone: () {
          transport.onDone?.call();
          onDone?.call();
        },
        cancelOnError: cancelOnError);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Harness {
  final HttpServer server;
  final List<Map<String, Object?>> seen = [];
  final List<LocalTransport> transports = [];
  final List<HomeTunnelApi> clients = [];
  final Map<String, Future<void> Function(HttpRequest, Map<String, dynamic>)>
      overrides = {};
  StreamSubscription<HttpRequest>? subscription;
  Harness(this.server);

  static Future<Harness> start() async {
    final harness =
        Harness(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));
    harness.subscription = harness.server.listen((request) async {
      try {
        final raw = await utf8.decoder.bind(request).join();
        final body = raw.isEmpty
            ? <String, dynamic>{}
            : jsonDecode(raw) as Map<String, dynamic>;
        harness.seen.add({
          'path': request.uri.path,
          'page': request.uri.queryParameters['page'],
          'method': request.method,
          'token': request.headers.value(HttpHeaders.authorizationHeader) ?? '',
          'body': body,
        });
        final override = harness.overrides[request.uri.path];
        if (override != null) {
          await override(request, body);
        } else {
          await harness.standard(request, body);
        }
      } catch (_) {
        try {
          await request.response.close();
        } catch (_) {}
      }
    });
    return harness;
  }

  Future<void> standard(HttpRequest request, Map<String, dynamic> body) async {
    switch (request.uri.path) {
      case '/api/v1/auth/login':
        await jsonResponse(request, loginReply());
        break;
      case '/api/v1/auth/me':
        await jsonResponse(request, {
          'id': uuid(99999),
          'username': 'demo',
          'display_name': '家庭账号',
          'role': 'user',
          'password_state': 'normal',
          'device_id': null,
          'native_remote': false,
        });
        break;
      case '/api/v1/client/devices':
        await jsonResponse(request, page([device(1), device(2)]));
        break;
      case '/api/v1/client/connections':
        await jsonResponse(request,
            page([service(1, 'http'), service(2, 'tcp'), service(3, 'udp')]));
        break;
      case '/api/v1/client/subdomains/availability':
        await jsonResponse(request, {
          'name': request.uri.queryParameters['name'],
          'available': true,
          'reason': 'ok',
          'suggestions': <String>[]
        });
        break;
      case '/api/v1/auth/refresh':
        await jsonResponse(request, refreshReply());
        break;
      case '/api/v1/auth/session/close':
        request.response.statusCode = 204;
        await request.response.close();
        break;
      default:
        throw StateError('出现范围外的 API 路径');
    }
  }

  HomeTunnelApi api(
      {bool Function()? isAllowed,
      Duration timeout = const Duration(seconds: 2),
      int maxBytes = 1024 * 1024,
      HomeDeskCredentialStorage? storage}) {
    final transport =
        LocalTransport(Uri.parse('http://127.0.0.1:${server.port}'));
    transports.add(transport);
    final api = HomeTunnelApi(origin,
        isAllowed: isAllowed ?? () => true,
        httpClientFactory: () => transport,
        credentialStorage: storage,
        requestTimeout: timeout,
        maxResponseBytes: maxBytes);
    clients.add(api);
    return api;
  }

  Future<void> close() async {
    for (final api in clients) {
      api.close();
    }
    await subscription?.cancel();
    await server.close(force: true);
  }
}

Future<void> main() async {
  var passed = 0;
  Future<void> test(String name, Future<void> Function(Harness) run) async {
    final harness = await Harness.start();
    try {
      await run(harness);
      passed++;
      print('通过：$name');
    } finally {
      await harness.close();
    }
  }

  for (final invalid in [
    'http://control.example.invalid',
    'https://u:p@control.example.invalid',
    'https://control.example.invalid/path',
    'https://control.example.invalid?token=x',
    'https://control.example.invalid#fragment',
    'https://control.example.invalid:0',
    'https://control.example.invalid:70000',
    'https://control.example.invalid%0a',
    'https://control.example.invalid\\evil',
  ]) {
    await rejects(() async {
      HomeTunnelApi(invalid, isAllowed: () => true).close();
    }, 'ORIGIN_INVALID');
  }
  for (final invalid in [
    'javascript:alert(1)',
    'file:///private/file',
    'https://u:p@service.example.invalid',
    'https://service.example.invalid/%0aheader',
    'https://service.example.invalid:0',
    'https://service.example.invalid\n',
  ]) {
    expect(homeTunnelWebUrl(invalid) == null, '不安全的服务地址必须被拒绝');
  }
  expect(homeTunnelWebUrl('https://service.example.invalid/a?b=c') != null,
      '正常 HTTPS 地址应可打开');

  await test('账号登录、完整目录、DIRECT、原始端口边界和独立退出', (h) async {
    final api = h.api();
    await api.login(username: 'demo', password: 'fixture-password');
    expect(api.isSignedIn && api.displayName == '家庭账号', '应保留账号管理会话');
    final catalog = await api.catalog();
    expect(catalog.devices.length == 2 && catalog.services.length == 3,
        '设备与服务应全量返回');
    expect(catalog.devices.every((d) => d.platform.isEmpty), '不能推测设备系统');
    expect(catalog.services[0].webUrl != null, 'HTTP 服务应保留访问地址');
    expect(catalog.services.skip(1).every((s) => s.webUrl == null),
        'TCP/UDP 服务不能伪造 HTTP 地址');
    expect(catalog.services[1].endpoint == 'edge.example.invalid:10000',
        '原始端口只作为端点提供');
    expect(h.transports.single.selectedProxy == 'DIRECT', '禁止系统代理');
    final login = h.seen.first['body'] as Map;
    final platform = Platform.isWindows
        ? 'windows'
        : Platform.isMacOS
            ? 'macos'
            : 'linux';
    expect(login['client_type'] == platform, '应使用真实桌面平台');
    expect(h.seen.first['token'] == '', '登录不能携带其他会话的令牌');
    expect(h.seen.skip(1).every((r) => r['token'] == 'Bearer $oldAccess'),
        '目录只能携带当前账号令牌');
    await api.logout();
    expect(!api.isSignedIn && api.displayName.isEmpty, '退出后必须清除会话');
    expect(
        h.seen.last['path'] == '/api/v1/auth/session/close', '退出不能旋转 FRP 设备凭据');
  });

  await test('MFA 仅由用户手动提交，不自动重试', (h) async {
    var attempts = 0;
    h.overrides['/api/v1/auth/login'] = (request, body) async {
      attempts++;
      if (body['mfa_code'] == null) {
        await jsonResponse(
            request, {'error_code': 'MFA_REQUIRED', 'message': 'server-secret'},
            status: 401);
      } else {
        expect(body['mfa_code'] == '123456', '应发送用户明确输入的验证码');
        await jsonResponse(request, loginReply());
      }
    };
    final api = h.api();
    await rejects(
        () => api.login(username: 'demo', password: 'fixture-password'),
        'MFA_REQUIRED');
    expect(attempts == 1 && !api.isSignedIn, 'MFA 不能自动重放');
    await api.login(
        username: 'demo', password: 'fixture-password', mfaCode: '123456');
    expect(attempts == 2 && api.isSignedIn, '用户可手动重新提交 MFA');
  });

  await test('首次改密与设备绑定会话显式拒绝', (h) async {
    final api = h.api();
    h.overrides['/api/v1/auth/login'] =
        (request, _) => jsonResponse(request, loginReply(mustChange: true));
    await rejects(
        () => api.login(username: 'demo', password: 'fixture-password'),
        'PASSWORD_CHANGE_REQUIRED');
    expect(!api.isSignedIn && h.seen.length == 1, '改密前不能读取目录');
    h.overrides.remove('/api/v1/auth/login');
    h.overrides['/api/v1/auth/me'] = (request, _) => jsonResponse(request, {
          'display_name': '设备会话',
          'device_id': uuid(1),
          'password_state': 'normal',
        });
    await rejects(
        () => api.login(username: 'demo', password: 'fixture-password'),
        'ACCOUNT_SESSION_REQUIRED');
    expect(!api.isSignedIn, '不能接收 FRP 设备范围会话');
  });

  await test('分页读取 101 台设备，服务名称不依赖管理专用字段', (h) async {
    h.overrides['/api/v1/client/devices'] = (request, _) async {
      final current = int.parse(request.uri.queryParameters['page']!);
      final items = current == 1
          ? List.generate(100, (index) => device(index + 1))
          : [device(101)];
      await jsonResponse(request, page(items, current: current, total: 101));
    };
    final api = h.api();
    await api.login(username: 'demo', password: 'fixture-password');
    final catalog = await api.catalog();
    expect(catalog.devices.length == 101, '不能只读取第一页');
    expect(
        h.seen.where((r) => r['path'] == '/api/v1/client/devices').length == 2,
        '应读取全部两页');
    expect(catalog.services.first.deviceId == catalog.devices.first.id,
        '服务应通过 UUID 与设备关联');
  });

  await test('超过 1000 项和分页中变化不能返回截断或部分目录', (h) async {
    final api = h.api();
    await api.login(username: 'demo', password: 'fixture-password');
    h.overrides['/api/v1/client/devices'] =
        (request, _) => jsonResponse(request, page([], total: 1001));
    await rejects(() async => api.catalog(), 'RESOURCE_LIMIT');
    h.overrides['/api/v1/client/devices'] = (request, _) async {
      final current = int.parse(request.uri.queryParameters['page']!);
      await jsonResponse(
          request,
          page(current == 1 ? List.generate(100, (i) => device(i + 1)) : [],
              current: current, total: current == 1 ? 101 : 100));
    };
    await rejects(() async => api.catalog(), 'CATALOG_CHANGED');
  });

  await test('两个目录同时 401 只刷新一次，并最多重试一次 GET', (h) async {
    var refreshes = 0;
    final refreshStarted = Completer<void>();
    final allowRefresh = Completer<void>();
    h.overrides['/api/v1/auth/refresh'] = (request, body) async {
      refreshes++;
      expect(body['refresh_token'] == oldRefresh, '只消费原始刷新令牌一次');
      refreshStarted.complete();
      await allowRefresh.future;
      await jsonResponse(request, {
        'access_token': nextAccess,
        'refresh_token': nextRefresh,
        'refresh_expires_at': '2030-02-01T00:00:00Z',
      });
    };
    for (final path in [
      '/api/v1/client/devices',
      '/api/v1/client/connections'
    ]) {
      h.overrides[path] = (request, body) async {
        if (request.headers.value(HttpHeaders.authorizationHeader) ==
            'Bearer $oldAccess') {
          await jsonResponse(request,
              {'error_code': 'SESSION_REVOKED', 'message': 'server-secret'},
              status: 401);
        } else {
          await h.standard(request, body);
        }
      };
    }
    final api = h.api();
    await api.login(username: 'demo', password: 'fixture-password');
    final pendingCatalog = api.catalog();
    await refreshStarted.future;
    expect(api.isSignedIn && api.displayName == '家庭账号',
        '刷新在途时仍属于已有登录，不能让界面切回登录表单');
    allowRefresh.complete();
    final catalog = await pendingCatalog;
    expect(refreshes == 1 && api.isSignedIn && catalog.devices.length == 2,
        '并发 401 必须合并为同一次刷新');
    expect(
        h.seen
                .where((r) => r['path'] == '/api/v1/auth/refresh')
                .single['token'] ==
            '',
        '刷新不发送过期 access token');
    for (final path in [
      '/api/v1/client/devices',
      '/api/v1/client/connections'
    ]) {
      expect(h.seen.where((r) => r['path'] == path).length == 2, 'GET 只能重试一次');
    }
  });

  await test('刷新成功后仍 401 不循环重试并清除会话', (h) async {
    var refreshes = 0;
    h.overrides['/api/v1/client/connections'] = (request, _) => jsonResponse(
        request, {'error_code': 'SESSION_REVOKED', 'message': 'server-secret'},
        status: 401);
    h.overrides['/api/v1/auth/refresh'] = (request, _) async {
      refreshes++;
      await jsonResponse(request, {
        'access_token': nextAccess,
        'refresh_token': nextRefresh,
        'refresh_expires_at': '2030-02-01T00:00:00Z',
      });
    };
    final api = h.api();
    await api.login(username: 'demo', password: 'fixture-password');
    await rejects(() async => api.catalog(), 'SESSION_EXPIRED');
    expect(!api.isSignedIn && refreshes == 1, '重复 401 应要求重新登录');
    expect(
        h.seen.where((r) => r['path'] == '/api/v1/client/connections').length ==
            2,
        '刷新后只能重试 GET 一次');
  });

  await test('刷新响应丢失清除会话，不重用已消费刷新令牌', (h) async {
    var refreshes = 0;
    h.overrides['/api/v1/client/devices'] = (request, _) => jsonResponse(
        request, {'error_code': 'SESSION_REVOKED', 'message': 'server-secret'},
        status: 401);
    h.overrides['/api/v1/auth/refresh'] = (request, _) async {
      refreshes++;
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await jsonResponse(request, {
        'access_token': nextAccess,
        'refresh_token': nextRefresh,
        'refresh_expires_at': '2030-02-01T00:00:00Z',
      });
    };
    final api = h.api(timeout: const Duration(milliseconds: 150));
    await api.login(username: 'demo', password: 'fixture-password');
    await rejects(() async => api.catalog(), 'SESSION_EXPIRED');
    expect(!api.isSignedIn && refreshes == 1, '丢失响应不能保留原始令牌');
    final requests = h.seen.length;
    await rejects(() async => api.catalog(), 'AUTH_REQUIRED');
    expect(h.seen.length == requests, '重新登录前不能再发送刷新请求');
  });

  await test('重定向、分块超限和慢响应被拒绝', (h) async {
    h.overrides['/api/v1/auth/login'] = (request, _) async {
      request.response.statusCode = 302;
      request.response.headers.set('location', 'https://other.example.invalid');
      await request.response.close();
    };
    final api = h.api();
    await rejects(
        () => api.login(username: 'demo', password: 'fixture-password'),
        'REDIRECT_BLOCKED');
    expect(h.seen.length == 1, '不得访问重定向目标');
    h.overrides.remove('/api/v1/auth/login');
    final bounded = h.api(maxBytes: 1024);
    await bounded.login(username: 'demo', password: 'fixture-password');
    h.overrides['/api/v1/client/devices'] = (request, _) async {
      request.response.write(' ' * 600);
      await request.response.flush();
      request.response.write(' ' * 600);
      await request.response.close();
    };
    await rejects(() async => bounded.catalog(), 'RESPONSE_TOO_LARGE');
    h.overrides['/api/v1/auth/login'] = (request, _) async {
      request.response.write(' ');
      await request.response.flush();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await jsonResponse(request, loginReply());
    };
    final timed = h.api(timeout: const Duration(milliseconds: 100));
    await rejects(
        () => timed.login(username: 'demo', password: 'fixture-password'),
        'REQUEST_TIMEOUT');
    expect(!timed.isSignedIn, '超时登录不能留下会话');
  });

  await test('撤销授权后强制关闭，openUrl 等待中不发送凭据', (h) async {
    var allowed = false;
    final blocked = h.api(isAllowed: () => allowed);
    await rejects(
        () => blocked.login(username: 'demo', password: 'fixture-password'),
        'ACCESS_REVOKED');
    expect(h.seen.isEmpty && h.transports.last.forceClosed, '初始未授权必须零请求并关闭传输');
    allowed = true;
    final duringOpen = h.api(isAllowed: () => allowed);
    h.transports.last.afterOpen = () => allowed = false;
    await rejects(
        () => duringOpen.login(username: 'demo', password: 'fixture-password'),
        'ACCESS_REVOKED');
    expect(h.seen.isEmpty && h.transports.last.forceClosed,
        'openUrl 返回后撤销时不能写入用户名、密码或 Bearer');
  });

  await test('读流每块与结果提交前均检查撤权并清除令牌', (h) async {
    var allowed = true;
    final duringRead = h.api(isAllowed: () => allowed);
    await duringRead.login(username: 'demo', password: 'fixture-password');
    h.transports.last.onChunk = () => allowed = false;
    await rejects(() async => duringRead.catalog(), 'ACCESS_REVOKED');
    expect(!duringRead.isSignedIn && h.transports.last.forceClosed,
        '读流期间撤权必须关闭全部连接');
    allowed = true;
    final beforeCommit = h.api(isAllowed: () => allowed);
    await beforeCommit.login(username: 'demo', password: 'fixture-password');
    h.transports.last.onDone = () => allowed = false;
    await rejects(() async => beforeCommit.catalog(), 'ACCESS_REVOKED');
    expect(!beforeCommit.isSignedIn && h.transports.last.forceClosed,
        '流结束后撤权不能提交旧目录');
  });

  await test('服务创建、编辑、启停、删除和设备元数据均使用真实账号路由与版本', (h) async {
    final id = uuid(10001);
    final deviceId = uuid(1);
    var writes = 0;
    h.overrides['/api/v1/client/connections'] = (request, body) async {
      if (request.method == 'GET') {
        await jsonResponse(request,
            page([service(1, 'http')])..['capabilities'] = rawCapabilities);
        return;
      }
      expect(request.method == 'POST', '创建应使用 POST');
      expect(
          !body.containsKey('remote_port') &&
              !body.containsKey('tcp_remote_port'),
          '账号不能指派公网端口');
      expect(body['device_id'] == deviceId, '创建必须指定账号所属设备 UUID');
      if (body['proxy_type'] == 'udp')
        expect(!body.containsKey('subdomain'), 'raw 子域由服务端生成');
      writes++;
      await jsonResponse(request,
          service(20 + writes, body['proxy_type'] as String)..addAll(body),
          status: 201);
    };
    h.overrides['/api/v1/client/connections/$id'] = (request, body) async {
      expect(
          !body.containsKey('proxy_type') && !body.containsKey('remote_port'),
          'PATCH 不能变更传输或公网端口');
      final expected = writes == 2
          ? 3
          : writes == 3
              ? 4
              : 5;
      expect(body['expected_version'] == expected, '必须提交读取版本');
      writes++;
      if (request.method == 'DELETE') {
        request.response.statusCode = 204;
        await request.response.close();
      } else {
        await jsonResponse(
            request,
            service(1, 'http')
              ..addAll(body)
              ..['version'] = expected + 1);
      }
    };
    h.overrides['/api/v1/client/devices/$deviceId/metadata'] =
        (request, body) async {
      expect(
          request.method == 'PATCH' && body['expected_metadata_version'] == 1,
          '元数据必须携带独立版本');
      expect(
          !body.containsKey('name') &&
              (body['tags'] as List).join(',') == 'NAS,家庭',
          '标签去重并排序，不能假写设备名称');
      await jsonResponse(request, {
        'id': deviceId,
        'metadata_version': 2,
        'favorite': body['favorite'],
        'tags': body['tags']
      });
    };
    final api = h.api();
    await api.login(username: 'demo', password: 'fixture-password');
    final catalog = await api.catalog();
    expect(catalog.capabilities.tcpCanCreate && catalog.capabilities.udpEnabled,
        '服务端能力应传递给编辑器');
    expect(
        catalog.services.single.version == 3 &&
            catalog.services.single.localPort == 8080,
        '必须保留本地目标与版本');
    final availability = await api.checkSubdomain('demo-album');
    expect(
        availability.available && availability.reason == 'ok', '可用性应使用正式 API');
    final created = await api.createService(httpDraft());
    expect(created.name == '家庭相册', '创建响应应是 typed 服务');
    await api.createService(
        {...httpDraft(), 'proxy_type': 'udp'}..remove('subdomain'));
    final updated = await api.updateService(
        id, {'name': '新名称', 'local_port': 9000},
        expectedVersion: 3);
    expect(updated.version == 4 && updated.localPort == 9000, '编辑后使用服务端新版本');
    await api.setServiceEnabled(id, false, expectedVersion: 4);
    await api.deleteService(id, expectedVersion: 5);
    await api.updateDevice(deviceId,
        tags: ['家庭', 'NAS', 'NAS'], favorite: true, expectedMetadataVersion: 1);
    expect(
        writes == 5 &&
            h.seen.every((r) => !(r['path'] as String).contains('/admin')),
        '只能使用账号资源路由');
  });

  await test('权限拒绝与版本冲突保留草稿，不刷新或重放写操作', (h) async {
    final api = h.api();
    await api.login(username: 'demo', password: 'fixture-password');
    await api.catalog();
    await rejects(
        () async => api.createService({...httpDraft(), 'proxy_type': 'udp'}),
        'FORBIDDEN');
    var creates = 0;
    h.overrides['/api/v1/client/connections'] = (request, _) async {
      creates++;
      await jsonResponse(
          request, {'error_code': 'FORBIDDEN', 'message': 'server-secret'},
          status: 403);
    };
    await rejects(() async => api.createService(httpDraft()), 'FORBIDDEN');
    expect(creates == 1, '403 不得自动刷新和重发');
    final id = uuid(10001);
    h.overrides['/api/v1/client/connections/$id'] =
        (request, _) => jsonResponse(
            request,
            {
              'error_code': 'VERSION_CONFLICT',
              'message': 'server-secret',
              'current_version': 9
            },
            status: 409);
    final draft = {'name': '尚未保存的草稿'};
    try {
      await api.updateService(id, draft, expectedVersion: 3);
      throw StateError('冲突不能成功');
    } on HomeTunnelApiException catch (error) {
      expect(
          error.isConflict && error.currentVersion == 9, '必须提供 typed 冲突与当前版本');
    }
    expect(draft.length == 1 && draft['name'] == '尚未保存的草稿', 'API 不能重写编辑器草稿');
    await rejects(
        () async =>
            api.updateService(id, {'proxy_type': 'udp'}, expectedVersion: 3),
        'INPUT_INVALID');
    await rejects(
        () async => api.updateDevice(uuid(1),
            tags: List.filled(13, '标签'),
            favorite: true,
            expectedMetadataVersion: 1),
        'INPUT_INVALID');
    expect(!h.seen.any((r) => r['path'] == '/api/v1/auth/refresh'),
        '403/409 不能触发刷新');
  });

  await test('已明确被认证拒绝的写请求只重发一次，网络结果未知则不重放', (h) async {
    var patches = 0;
    final id = uuid(10001);
    h.overrides['/api/v1/client/connections/$id'] = (request, body) async {
      patches++;
      if (patches == 1) {
        await jsonResponse(request, {'error_code': 'SESSION_REVOKED'},
            status: 401);
      } else {
        expect(body['expected_version'] == 3, '认证重发必须保持原版本');
        await jsonResponse(
            request,
            service(1, 'http')
              ..addAll(body)
              ..['version'] = 4);
      }
    };
    final api = h.api();
    await api.login(username: 'demo', password: 'fixture-password');
    await api.updateService(id, {'name': '明确重发'}, expectedVersion: 3);
    expect(
        patches == 2 &&
            h.seen.where((r) => r['path'] == '/api/v1/auth/refresh').length ==
                1,
        '认证拒绝可单次刷新重发');
    var creates = 0;
    var created = false;
    h.overrides['/api/v1/client/connections'] = (request, body) async {
      if (request.method == 'GET') {
        await jsonResponse(request, page(created ? [service(22, 'http')] : []));
      } else {
        creates++;
        created = true;
        await Future<void>.delayed(const Duration(milliseconds: 400));
        await jsonResponse(request, service(22, 'http')..addAll(body),
            status: 201);
      }
    };
    final timed = h.api(timeout: const Duration(milliseconds: 150));
    await timed.login(username: 'demo', password: 'fixture-password');
    await rejects(
        () async => timed.createService(httpDraft()), 'MUTATION_UNKNOWN');
    final after = await timed.catalog();
    expect(creates == 1 && after.services.length == 1, '失响应后只读取核对，不能重复创建');
  });

  await test('同一资源并发写被互斥，自动端口和目标字段不能绕过校验', (h) async {
    final started = Completer<void>();
    final finish = Completer<void>();
    final id = uuid(10001);
    h.overrides['/api/v1/client/connections/$id'] = (request, body) async {
      started.complete();
      await finish.future;
      await jsonResponse(request, service(1, 'http')..addAll(body));
    };
    final api = h.api();
    await api.login(username: 'demo', password: 'fixture-password');
    final pending = api.updateService(id, {'name': '第一份'}, expectedVersion: 3);
    await started.future;
    await rejects(
        () async => api.setServiceEnabled(id, false, expectedVersion: 3),
        'OPERATION_BUSY');
    finish.complete();
    await pending;
    await rejects(
        () async => api.createService({...httpDraft(), 'remote_port': 21116}),
        'INPUT_INVALID');
    await rejects(
        () async => api.createService(
            {...httpDraft(), 'local_host': 'https://wrong.invalid'}),
        'INPUT_INVALID');
    await rejects(
        () async => api.createService({...httpDraft(), 'local_port': 0}),
        'INPUT_INVALID');
    expect(
        h.seen
                .where((r) => r['path'] == '/api/v1/client/connections/$id')
                .length ==
            1,
        '并发点击不能产生第二次写请求');
  });

  await test('记住登录仅保存刷新凭据，普通关闭保留，恢复先consume再刷新再save', (h) async {
    final store = MemorySecureStore();
    final api = h.api(storage: store);
    await api.login(
        username: 'demo', password: 'fixture-password', rememberLogin: true);
    expect(api.rememberedLogin && store.record?.refreshToken == oldRefresh,
        '应保存安全接口记录');
    final serialized = jsonEncode(store.record!.toJson());
    expect(
        !serialized.contains(oldAccess) &&
            !serialized.contains('fixture-password') &&
            !serialized.contains('mfa_code') &&
            !serialized.contains('access_token'),
        '不能保存密码、MFA或access');
    api.close();
    expect(store.record != null, '普通关闭必须保留未消费记录');
    final restored = h.api(storage: store);
    h.overrides['/api/v1/auth/refresh'] = (request, body) async {
      expect(store.record == null && body['refresh_token'] == oldRefresh,
          '联网前旧记录必须被原子销毁');
      await jsonResponse(request, refreshReply());
    };
    store.beforeSave = () async {
      expect(!restored.isSignedIn, '恢复必须等新Token保存完成再交付会话');
    };
    expect(await restored.restore(), '有效记录应恢复实际账号');
    expect(restored.isSignedIn && store.record?.refreshToken == nextRefresh,
        '只能留下新的刷新令牌');
    expect(
        store.record!.origin ==
            homeTunnelOrigin('https://CONTROL.EXAMPLE.INVALID:443/'),
        '存储与批准origin必须统一canonical');
  });

  await test('记住会话并发401只消费一次，保存新Token前不能发送重试目录', (h) async {
    final store = MemorySecureStore();
    final api = h.api(storage: store);
    await api.login(
        username: 'demo', password: 'fixture-password', rememberLogin: true);
    for (final path in [
      '/api/v1/client/devices',
      '/api/v1/client/connections'
    ]) {
      h.overrides[path] = (request, body) async {
        if (request.headers.value(HttpHeaders.authorizationHeader) ==
            'Bearer $oldAccess') {
          await jsonResponse(request, {'error_code': 'SESSION_REVOKED'},
              status: 401);
        } else {
          await h.standard(request, body);
        }
      };
    }
    final saving = Completer<void>();
    final finish = Completer<void>();
    store.beforeSave = () async {
      saving.complete();
      await finish.future;
    };
    final pending = api.catalog();
    await saving.future;
    expect(store.record == null && api.isSignedIn, '刷新时旧记录已消费但UI仍为原登录');
    expect(
        !h.seen.any((r) =>
            (r['path'] as String).startsWith('/api/v1/client/') &&
            r['token'] == 'Bearer $nextAccess'),
        '保存前不交付新access');
    finish.complete();
    await pending;
    expect(
        store.events.where((e) => e == 'consume').length == 1 &&
            store.record?.refreshToken == nextRefresh,
        '并发目录只能消费和保存一份轮换');
  });

  await test('恢复origin或身份不符不伪造登录，保存失败也不降级记住', (h) async {
    final store = MemorySecureStore()
      ..record = remembered(savedOrigin: 'https://other.example.invalid');
    final wrongOrigin = h.api(storage: store);
    await rejects(() async => wrongOrigin.restore(), 'ORIGIN_MISMATCH');
    expect(h.seen.isEmpty && store.record == null, '不能把凭据发到别的origin');
    store.record = remembered(userId: uuid(88888));
    final wrongIdentity = h.api(storage: store);
    await rejects(() async => wrongIdentity.restore(), 'IDENTITY_MISMATCH');
    expect(
        !wrongIdentity.isSignedIn && store.record == null, '必须核对服务器实际userId');
    store.failSave = true;
    final failing = h.api(storage: store);
    await rejects(
        () => failing.login(
            username: 'demo',
            password: 'fixture-password',
            rememberLogin: true),
        'SECURE_STORE_ERROR');
    expect(!failing.isSignedIn && store.record == null, '写失败应失效会话而不是保留旧Token');
    store.failSave = false;
    store.failAfterSave = true;
    final afterWrite = h.api(storage: store);
    await rejects(
        () => afterWrite.login(
            username: 'demo',
            password: 'fixture-password',
            rememberLogin: true),
        'SECURE_STORE_ERROR');
    expect(!afterWrite.isSignedIn && store.record == null,
        '即使新记录已落盘但save回报失败，也只能销毁本次拥有的记录');
  });

  await test('记住会话刷新丢响应后旧记录已销毁，下一实例不能重放恢复', (h) async {
    final store = MemorySecureStore();
    final api =
        h.api(storage: store, timeout: const Duration(milliseconds: 150));
    await api.login(
        username: 'demo', password: 'fixture-password', rememberLogin: true);
    var refreshes = 0;
    h.overrides['/api/v1/client/devices'] = (request, _) =>
        jsonResponse(request, {'error_code': 'SESSION_REVOKED'}, status: 401);
    h.overrides['/api/v1/auth/refresh'] = (request, body) async {
      refreshes++;
      expect(store.record == null && body['refresh_token'] == oldRefresh,
          '旧记录必须在单次native刷新前消费');
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await jsonResponse(request, refreshReply());
    };
    await rejects(() async => api.catalog(), 'SESSION_EXPIRED');
    expect(!api.isSignedIn && store.record == null && refreshes == 1,
        '刷新丢响应后不能保存或恢复旧refresh');
    final requests = h.seen.length;
    final nextInstance = h.api(storage: store);
    expect(!await nextInstance.restore() && h.seen.length == requests,
        '下一次进入门户必须人工登录，不能重新发送已消费的旧Token');
  });

  await test('旧实例保存失败只discard旧事务，不删除新实例记住的登录', (h) async {
    final store = MemorySecureStore()..record = remembered();
    final paused = Completer<void>();
    final finish = Completer<void>();
    store.beforeSave = () async {
      if (!paused.isCompleted) {
        paused.complete();
        await finish.future;
      }
    };
    final old = h.api(storage: store);
    final oldRestore = old.restore();
    await paused.future;
    h.overrides['/api/v1/auth/login'] = (request, _) => jsonResponse(
        request,
        loginReply()
          ..['access_token'] = 'fixture-new-instance-access'
          ..['refresh_token'] = 'fixture-new-instance-refresh');
    final newer = h.api(storage: store);
    await newer.login(
        username: 'demo', password: 'fixture-password', rememberLogin: true);
    finish.complete();
    await rejects(() async => oldRestore, 'SECURE_STORE_ERROR');
    expect(
        newer.isSignedIn &&
            store.record?.refreshToken == 'fixture-new-instance-refresh',
        '旧保存的条件清理不能删除新登录');
    final lease = await store.consume();
    expect(lease?.record.refreshToken == 'fixture-new-instance-refresh',
        '新实例记录应仍能被安全消费');
  });

  await test('保存轮换在途退出使pending事务失效，迟保存不能复活记住记录', (h) async {
    final store = MemorySecureStore();
    final api = h.api(storage: store);
    await api.login(
        username: 'demo', password: 'fixture-password', rememberLogin: true);
    h.overrides['/api/v1/client/devices'] = (request, _) =>
        jsonResponse(request, {'error_code': 'SESSION_REVOKED'}, status: 401);
    final saving = Completer<void>();
    final finish = Completer<void>();
    store.beforeSave = () async {
      saving.complete();
      await finish.future;
    };
    final pending = api.catalog();
    await saving.future;
    await api.logout();
    expect(!api.isSignedIn && store.record == null, '退出必须失效刷新中的新事务');
    finish.complete();
    await rejects(() async => pending, 'SECURE_STORE_ERROR');
    expect(store.record == null, '晚到的G2保存不得复活账号');
  });

  await test('旧epoch撤权只删除自身记录，cold未许可不能消费另实例凭据', (h) async {
    final store = MemorySecureStore();
    var allowed = true;
    final old = h.api(storage: store, isAllowed: () => allowed);
    await old.login(
        username: 'demo', password: 'fixture-password', rememberLogin: true);
    final newer = h.api(storage: store);
    await newer.login(
        username: 'demo', password: 'fixture-password', rememberLogin: true);
    final generation = store.generation;
    allowed = false;
    await old.revoke();
    expect(
        newer.isSignedIn &&
            store.record != null &&
            store.generation == generation,
        '旧epoch观察者不能清除新epoch的明确登录');
    final seen = h.seen.length;
    final events = store.events.length;
    final cold = h.api(storage: store, isAllowed: () => false);
    await rejects(() async => cold.restore(), 'ACCESS_REVOKED');
    expect(h.seen.length == seen && store.events.length == events,
        'cold未许可不读、消费或删除保存凭据');
    await newer.revoke();
    expect(store.record == null, '当前实例撤权必须销毁自己保存的记录');
  });

  await test('忘记登录等待现有轮换完成，清密文后当前内存会话继续', (h) async {
    final store = MemorySecureStore();
    final api = h.api(storage: store);
    await api.login(
        username: 'demo', password: 'fixture-password', rememberLogin: true);
    h.overrides['/api/v1/client/devices'] = (request, body) async {
      if (request.headers.value(HttpHeaders.authorizationHeader) ==
          'Bearer $oldAccess') {
        await jsonResponse(request, {'error_code': 'SESSION_REVOKED'},
            status: 401);
      } else {
        await h.standard(request, body);
      }
    };
    final saving = Completer<void>();
    final finish = Completer<void>();
    store.beforeSave = () async {
      saving.complete();
      await finish.future;
    };
    final pending = api.catalog();
    await saving.future;
    final forget = api.forgetRememberedLogin();
    finish.complete();
    await pending;
    await forget;
    expect(api.isSignedIn && !api.rememberedLogin && store.record == null,
        '忘记不能让已在途刷新因stale save异常退出');
  });

  await test('本机退出删除失败仍尝试远端撤销，并准确报安全存储错误', (h) async {
    final store = MemorySecureStore();
    final api = h.api(storage: store);
    await api.login(
        username: 'demo', password: 'fixture-password', rememberLogin: true);
    store.failDiscard = true;
    await rejects(() => api.logout(), 'SECURE_STORE_ERROR');
    expect(
        !api.isSignedIn && h.seen.last['path'] == '/api/v1/auth/session/close',
        '本机清理失败时也要尽力使服务端刷新令牌失效');
  });

  await test('设备metadata真实409与未来未知403/409均准确分类而不重放', (h) async {
    final api = h.api();
    await api.login(username: 'demo', password: 'fixture-password');
    var mode = 0;
    var writes = 0;
    final id = uuid(1);
    h.overrides['/api/v1/client/devices/$id/metadata'] = (request, body) async {
      writes++;
      expect(body['expected_metadata_version'] == 3, '冲突前必须保留原metadata版本');
      await jsonResponse(
          request,
          {
            'error_code':
                mode == 0 ? 'VERSION_CONFLICT' : 'FUTURE_SERVER_POLICY',
            'message': 'server-secret'
          },
          status: mode == 2 ? 403 : 409);
    };
    for (mode = 0; mode < 3; mode++) {
      await rejects(
          () => api.updateDevice(id,
              tags: ['草稿'], favorite: true, expectedMetadataVersion: 3),
          mode == 2 ? 'FORBIDDEN' : 'VERSION_CONFLICT');
    }
    expect(
        writes == 3 && !h.seen.any((r) => r['path'] == '/api/v1/auth/refresh'),
        '409/403只提示刷新或权限，不自动重试写操作');
  });

  print('全部通过：$passed 组 HomeTunnel 行为检查。');
}
