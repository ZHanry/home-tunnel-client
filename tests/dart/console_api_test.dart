// 直接测试生产 Dart HTTP 客户端，仅在传输层把测试内网地址映射到回环 mock。
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../../client/flutter/lib/homedesk_console_api.dart';

class LocalTransport implements HttpClient {
  final HttpClient inner;
  final Uri local;
  void Function()? afterOpen;
  LocalTransport(this.inner, this.local);
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    final request = await inner.openUrl(method, local.resolve(url.path));
    afterOpen?.call();
    return request;
  }

  @override
  set findProxy(String Function(Uri)? value) {
    inner.findProxy = value;
  }

  @override
  set connectionTimeout(Duration? value) {
    inner.connectionTimeout = value;
  }

  @override
  // 各逻辑客户端共享此测试传输；底层连接由测试结束时统一关闭。
  void close({bool force = false}) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> main() async {
  int rejected = 0;
  for (final url in [
    'http://example.com:8080',
    'http://8.8.8.8:8080',
    'https://192.168.50.10:8080',
    'http://u:p@192.168.50.10:8080',
    'http://192.168.50.10:8080/path',
    'http://192.168.50.10:8080?token=x',
    'http://+192.168.50.10:8080',
    'http://0x0a.0.0.1:8080',
    'http://192.168.50.10:0',
    'http://192.168.50.10:70000',
    'http://192.168.50.10'
  ]) {
    try {
      HomeDeskConsoleApi(url, 'test-only-token').close();
    } on FormatException {
      rejected++;
    }
  }
  assert(rejected == 11);
  HomeDeskConsoleApi('http://192.168.50.10:80', 'test-only-token').close();
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final local = Uri.parse('http://127.0.0.1:${server.port}');
  final inner = HttpClient();
  LocalTransport? latestTransport;
  int requests = 0, mode = 0;
  final seen = <String>[];
  final seenTokens = <String>[];
  final subscription = server.listen((request) async {
    requests++;
    seenTokens
        .add(request.headers.value(HttpHeaders.authorizationHeader) ?? '');
    seen.add(request.uri.path);
    request.response.headers.contentType = ContentType.json;
    if (mode == 1) {
      request.response.statusCode = 302;
      request.response.headers
          .set('location', '/redirect-must-not-be-followed');
      request.response.write('{}');
    } else if (mode == 2) {
      request.response.statusCode = 401;
      request.response.write('{}');
    } else if (request.uri.path.endsWith('/wol')) {
      final body = jsonDecode(await utf8.decoder.bind(request).join());
      assert(body['device_id'] == '123456');
      request.response.write('{"ok":true}');
    } else {
      request.response.write(jsonEncode([
        {'id': '123456', 'name': '测试电脑', 'online': true},
        {'id': '123456@public', 'name': '不能注入外部服务器'},
        {'id': '123456/r', 'name': '不能注入中继标志'},
      ]));
    }
    await request.response.close();
  });
  await HttpOverrides.runZoned(() async {
    final api =
        HomeDeskConsoleApi('http://192.168.50.10:8080', 'test-only-token');
    final devices = await api.devices();
    assert(devices.length == 1 && devices.single['id'] == '123456');
    await api.wake('123456');
    assert(seen.join(',') == '/api/v1/devices,/api/v1/wol');
    mode = 1;
    bool redirectRejected = false;
    try {
      await api.devices();
    } on FormatException {
      redirectRejected = true;
    }
    assert(redirectRejected && requests == 3);
    mode = 2;
    bool unauthorized = false;
    try {
      await api.devices();
    } on FormatException {
      unauthorized = true;
    }
    assert(unauthorized);
    api.close();
    mode = 0;

    // 许可撤销后，轮询/WOL 不得继续携带旧 Token 发请求。
    var allowed = true;
    final blocked = HomeDeskConsoleApi('http://192.168.50.10:8080', 'old-token',
        isAllowed: () => allowed);
    allowed = false;
    var denied = false;
    try {
      await blocked.devices();
    } on FormatException {
      denied = true;
    }
    assert(denied && requests == 4);
    final blockedWake = HomeDeskConsoleApi(
        'http://192.168.50.10:8080', 'old-token',
        isAllowed: () => allowed);
    denied = false;
    try {
      await blockedWake.wake('123456');
    } on FormatException {
      denied = true;
    }
    assert(denied && requests == 4);

    // openUrl 返回后撤销许可时，授权头和请求体都不能发送。
    allowed = true;
    final duringOpen = HomeDeskConsoleApi(
        'http://192.168.50.10:8080', 'during-open-token',
        isAllowed: () => allowed);
    latestTransport!.afterOpen = () => allowed = false;
    denied = false;
    try {
      await duringOpen.devices();
    } on FormatException {
      denied = true;
    }
    assert(denied && requests == 4);

    // 恢复后必须新建客户端并使用新配置，而不是恢复旧 Token。
    allowed = true;
    final restored = HomeDeskConsoleApi(
        'http://192.168.50.10:8080', 'new-token',
        isAllowed: () => allowed);
    await restored.devices();
    assert(requests == 5 && seenTokens.last == 'Bearer new-token');
    restored.close();
  }, createHttpClient: (_) {
    final transport = LocalTransport(inner, local);
    latestTransport = transport;
    return transport;
  });
  await subscription.cancel();
  await server.close(force: true);
  inner.close(force: true);
  print('通过：地址限制、设备 ID 过滤、Bearer、设备读取、WOL 请求、禁止重定向、401 错误。');
}
