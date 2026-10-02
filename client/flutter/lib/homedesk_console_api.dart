// HOMEDESK: 独立内网管理台客户端，不使用公网代理、域名或自动重定向。
import 'dart:async';
import 'dart:convert';
import 'dart:io';

class HomeDeskConsoleApi {
  final Uri base;
  final String _token;
  final HttpClient _http;
  final bool Function()? _isAllowed;
  bool _closed = false;

  HomeDeskConsoleApi(String url, this._token, {bool Function()? isAllowed})
      : base = Uri.parse(url),
        _http = HttpClient(),
        _isAllowed = isAllowed {
    final octets = base.host.split('.').map(int.tryParse).toList();
    final decimalHost =
        RegExp(r'^(0|[1-9][0-9]{0,2})(\.(0|[1-9][0-9]{0,2})){3}$')
            .hasMatch(base.host);
    final portMatch = RegExp(r'^http://[^/:]+:([0-9]{1,5})/?$').firstMatch(url);
    final explicitPort = int.tryParse(portMatch?.group(1) ?? '') ?? 0;
    final valid = decimalHost &&
        octets.length == 4 &&
        octets.every((v) => v != null && v >= 0 && v <= 255) &&
        (octets[0] == 10 ||
            (octets[0] == 172 && octets[1]! >= 16 && octets[1]! <= 31) ||
            (octets[0] == 192 && octets[1] == 168));
    if (!valid ||
        base.scheme != 'http' ||
        explicitPort < 1 ||
        explicitPort > 65535 ||
        base.userInfo.isNotEmpty ||
        base.hasQuery ||
        base.hasFragment ||
        (base.path.isNotEmpty && base.path != '/') ||
        _token.isEmpty) {
      _http.close(force: true);
      throw const FormatException('管理台需要有效的内网地址和访问口令');
    }
    _http.findProxy = (_) => 'DIRECT';
    _http.connectionTimeout = const Duration(seconds: 5);
  }

  void _ensureAllowed() {
    if (_closed || (_isAllowed != null && !_isAllowed!())) {
      close();
      throw const FormatException('设备中心当前不可达，可通过设备 ID 连接。');
    }
  }

  Future<dynamic> _request(String path, [Map<String, dynamic>? body]) async {
    _ensureAllowed();
    final request = await _http
        .openUrl(body == null ? 'GET' : 'POST', base.resolve(path))
        .timeout(const Duration(seconds: 5));
    // openUrl 期间网络模式可能已切换；在写入 Token 前重新确认许可。
    _ensureAllowed();
    request.followRedirects = false;
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_token');
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }
    // request.close 才会实际发送请求，禁止使用已撤销模式下的缓存 Token。
    _ensureAllowed();
    final response = await request.close().timeout(const Duration(seconds: 5));
    final bytes = <int>[];
    await for (final chunk in response.timeout(const Duration(seconds: 5))) {
      bytes.addAll(chunk);
      if (bytes.length > 1024 * 1024) {
        throw const FormatException('管理台返回的数据过大');
      }
    }
    if (response.statusCode == 401) {
      throw const FormatException('管理台访问口令已变更，请更新客户端配置');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw const FormatException('管理台请求失败，请检查服务和家庭网段');
    }
    return jsonDecode(utf8.decode(bytes));
  }

  Future<List<Map<String, dynamic>>> devices() async {
    final value = await _request('/api/v1/devices');
    if (value is! List) throw const FormatException('设备列表格式无效');
    final devices =
        value.map((d) => Map<String, dynamic>.from(d as Map)).toList();
    // 设备 ID 最终传给上游连接入口，禁止注入 @public、/r 或其他服务器选择语法。
    return devices
        .where((d) => RegExp(r'^[a-zA-Z0-9_.-]{1,128}$')
            .hasMatch(d['id']?.toString() ?? ''))
        .toList();
  }

  Future<void> wake(String id) async {
    await _request('/api/v1/wol', {'device_id': id});
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _http.close(force: true);
  }
}
