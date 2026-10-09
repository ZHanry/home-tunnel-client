// HOMEDESK: 真实回环 HTTPS 验证证书/主机名边界，只用运行时生成的测试证书。
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../client/flutter/lib/homedesk_tunnel_api.dart';

const _user = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _device = '11111111-1111-4111-8111-111111111111';
const _service = '22222222-2222-4222-8222-222222222222';
const _access = 'fixture_access_token_for_https_0001';
const _refresh = 'fixture_refresh_token_for_https_0001';

Future<void> main() async {
  final scratchRoot = Directory('client/target/portal-tls-tests').absolute;
  await scratchRoot.create(recursive: true);
  final scratch = await scratchRoot.createTemp('https-');
  HttpServer? server;
  StreamSubscription<HttpRequest>? listener;
  final apis = <HomeTunnelApi>[];
  try {
    final cert = File('${scratch.path}/certificate.pem');
    final key = File('${scratch.path}/private-key.pem');
    final openssl = Platform.isWindows
        ? Platform.environment['HOMEDESK_TEST_OPENSSL'] ?? 'openssl.exe'
        : 'openssl';
    final generated = await Process.run(openssl, [
      'req',
      '-x509',
      '-newkey',
      'rsa:2048',
      '-nodes',
      '-keyout',
      key.path,
      '-out',
      cert.path,
      '-subj',
      '/CN=localhost',
      '-addext',
      'subjectAltName=DNS:localhost',
      '-days',
      '1',
    ]);
    if (generated.exitCode != 0) {
      throw StateError('无法生成本地测试证书，请检查测试 OpenSSL 路径。');
    }
    final serverContext = SecurityContext()
      ..useCertificateChain(cert.path)
      ..usePrivateKey(key.path);
    server = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4, 0, serverContext);
    final accepted = <String>[];
    listener = server.listen((request) async {
      accepted.add('${request.method} ${request.uri.path}');
      final response = request.response;
      response.headers.contentType = ContentType.json;
      final auth = request.headers.value(HttpHeaders.authorizationHeader);
      Object? payload;
      if (request.uri.path == '/api/v2/auth/login') {
        final login =
            jsonDecode(await utf8.decoder.bind(request).join()) as Map;
        assert(login['username'] == 'fixture-user');
        assert(login['client_type'] != 'web');
        assert(auth == null);
        payload = {
          'user': {
            'id': _user,
            'username': 'fixture-user',
            'display_name': '测试账号',
            'password_state': 'normal'
          },
          'password_change_required': false,
          'access_token': _access,
          'refresh_token': _refresh,
          'access_expires_at': DateTime.now()
              .toUtc()
              .add(const Duration(minutes: 15))
              .toIso8601String(),
          'refresh_expires_at': DateTime.now()
              .toUtc()
              .add(const Duration(days: 30))
              .toIso8601String(),
        };
      } else {
        assert(auth == 'Bearer $_access');
        if (request.uri.path == '/api/v2/auth/me') {
          payload = {
            'id': _user,
            'username': 'fixture-user',
            'display_name': '测试账号',
            'device_id': null,
            'native_remote': false,
            'password_state': 'normal'
          };
        } else if (request.uri.path == '/api/v1/client/devices') {
          payload = {
            'page': 1,
            'page_size': 100,
            'total': 1,
            'total_pages': 1,
            'items': [
              {
                'id': _device,
                'name': '测试 NAS',
                'online': true,
                'tags': [],
                'favorite': false,
                'metadata_version': 1
              },
            ]
          };
        } else if (request.uri.path == '/api/v1/client/connections') {
          payload = {
            'page': 1,
            'page_size': 100,
            'total': 1,
            'total_pages': 1,
            'capabilities': {'supported': true},
            'items': [
              {
                'id': _service,
                'device_id': _device,
                'name': '测试相册',
                'proxy_type': 'http',
                'state': 'Online',
                'enabled': true,
                'public_url': 'https://album.example.invalid',
                'public_endpoint': null,
                'local_scheme': 'http',
                'local_host': '127.0.0.1',
                'local_port': 2283,
                'subdomain': 'album',
                'version': 1
              },
            ]
          };
        } else if (request.uri.path == '/api/v2/auth/session/close') {
          response.statusCode = HttpStatus.noContent;
          await response.close();
          return;
        } else {
          response.statusCode = HttpStatus.notFound;
          payload = {'error_code': 'NOT_FOUND'};
        }
      }
      response.write(jsonEncode(payload));
      await response.close();
    }, onError: (Object _) {});

    Future<void> rejected(HomeTunnelApi api) async {
      apis.add(api);
      var denied = false;
      try {
        await api.login(username: 'fixture-user', password: 'fixture-password');
      } on HomeTunnelApiException {
        denied = true;
      }
      assert(denied && !api.isSignedIn, '无可信 TLS 握手不能交付账号登录。');
    }

    await rejected(HomeTunnelApi('https://localhost:${server.port}',
        isAllowed: () => true));
    assert(accepted.isEmpty, '不可信证书被拒绝前不能发送登录正文。');

    HttpClient trustedClient() => HttpClient(
        context: SecurityContext(withTrustedRoots: false)
          ..setTrustedCertificates(cert.path));
    await rejected(HomeTunnelApi('https://127.0.0.1:${server.port}',
        isAllowed: () => true, httpClientFactory: trustedClient));
    assert(accepted.isEmpty, '主机名不符的 TLS 不能发送登录正文。');

    final trusted = HomeTunnelApi('https://localhost:${server.port}',
        isAllowed: () => true, httpClientFactory: trustedClient);
    apis.add(trusted);
    await trusted.login(username: 'fixture-user', password: 'fixture-password');
    final catalog = await trusted.catalog();
    assert(trusted.isSignedIn && catalog.devices.single.id == _device);
    assert(catalog.services.single.webUrl.toString() ==
        'https://album.example.invalid');
    await trusted.logout();
    assert(!trusted.isSignedIn && accepted.length == 5);
    print('通过：真实 HTTPS 验证拒绝不可信证书/错误主机名，可信回环登录、目录与独立退出成功。');
  } finally {
    for (final api in apis) {
      api.close();
    }
    await listener?.cancel();
    await server?.close(force: true);
    final rootPath = await scratchRoot.resolveSymbolicLinks();
    final targetPath = await scratch.resolveSymbolicLinks();
    if (!targetPath.startsWith('$rootPath${Platform.pathSeparator}') ||
        !scratch.path.split(Platform.pathSeparator).last.startsWith('https-')) {
      throw StateError('测试目录超出预期边界，保留测试文件。');
    }
    await scratch.delete(recursive: true);
  }
}
