// HOMEDESK: 独立账号目录与一次性本机接入码客户端；管理会话保持未绑定，租约由 Agent 处理。
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'homedesk_tunnel_session.dart';

class HomeTunnelApiException implements Exception {
  final String message;
  final String code;
  final int? currentVersion;
  final int? currentAccessPolicyVersion;
  const HomeTunnelApiException(this.message, this.code,
      {this.currentVersion, this.currentAccessPolicyVersion});
  bool get outcomeUnknown => code == 'MUTATION_UNKNOWN';
  bool get isConflict =>
      code == 'VERSION_CONFLICT' ||
      code == 'METADATA_VERSION_CONFLICT' ||
      code == 'ACCESS_POLICY_VERSION_CONFLICT';
  @override
  String toString() => message;
}

bool _hasUnsafeCharacters(String value) =>
    RegExp(r'[\x00-\x20\x7f\\]|%(?:0[0-9a-f]|1[0-9a-f]|7f)',
            caseSensitive: false)
        .hasMatch(value);

bool _validHost(String host) {
  if (host.isEmpty || host.length > 253 || _hasUnsafeCharacters(host)) {
    return false;
  }
  if (InternetAddress.tryParse(host) != null) return true;
  return host.split('.').every((part) =>
      RegExp(r'^[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$')
          .hasMatch(part));
}

/// 只接受可交给系统浏览器的 HTTP(S) 地址，不接受凭据或控制字符。
Uri? homeTunnelWebUrl(Object? value) {
  if (value is! String || value.length > 4096 || _hasUnsafeCharacters(value)) {
    return null;
  }
  final uri = Uri.tryParse(value);
  if (uri == null ||
      !['http', 'https'].contains(uri.scheme) ||
      !_validHost(uri.host) ||
      uri.userInfo.isNotEmpty ||
      uri.port < 1 ||
      uri.port > 65535) {
    return null;
  }
  return uri;
}

String homeTunnelOrigin(String value) => HomeTunnelApi._origin(value).origin;

String? _endpoint(Object? value) {
  if (value is! String || value.length > 512 || _hasUnsafeCharacters(value)) {
    return null;
  }
  if (!RegExp(r':\d{1,5}$').hasMatch(value)) return null;
  final uri = Uri.tryParse('tcp://$value');
  if (uri == null ||
      !_validHost(uri.host) ||
      uri.userInfo.isNotEmpty ||
      uri.path.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      uri.port < 1 ||
      uri.port > 65535) {
    return null;
  }
  return value;
}

class HomeTunnelDevice {
  final String id;
  final String name;
  final String platform;
  final bool online;
  final List<String> tags;
  final bool favorite;
  final int metadataVersion;
  const HomeTunnelDevice(
      {required this.id,
      required this.name,
      required this.platform,
      required this.online,
      this.tags = const [],
      this.favorite = false,
      this.metadataVersion = 1});
}

class HomeDeskRemoteBinding {
  final String deviceId;
  final String remoteId;
  final String server;
  final String keySHA256;
  final String platform;
  final bool online;
  const HomeDeskRemoteBinding(
      {required this.deviceId,
      required this.remoteId,
      required this.server,
      required this.keySHA256,
      required this.platform,
      required this.online});
}

class HomeTunnelService {
  final String id;
  final String deviceId;
  final String name;
  final String proxyType;
  final String status;
  final Uri? webUrl;
  final String? endpoint;
  final bool enabled;
  final int version;
  final int accessPolicyVersion;
  final String localScheme;
  final String localHost;
  final int localPort;
  final String subdomain;
  final int? remotePort;
  final String? applicationProtocol;
  const HomeTunnelService(
      {required this.id,
      required this.deviceId,
      required this.name,
      required this.proxyType,
      required this.status,
      required this.webUrl,
      required this.endpoint,
      required this.enabled,
      this.version = 1,
      this.accessPolicyVersion = 1,
      this.localScheme = 'http',
      this.localHost = '',
      this.localPort = 0,
      this.subdomain = '',
      this.remotePort,
      this.applicationProtocol});
}

class HomeTunnelCapabilities {
  final bool tcpEnabled;
  final bool tcpCanCreate;
  final bool udpEnabled;
  final bool udpCanCreate;
  final bool automaticPorts;
  const HomeTunnelCapabilities(
      {this.tcpEnabled = false,
      this.tcpCanCreate = false,
      this.udpEnabled = false,
      this.udpCanCreate = false,
      this.automaticPorts = false});
}

class HomeTunnelSubdomainAvailability {
  final String name;
  final bool available;
  final String reason;
  final List<String> suggestions;
  const HomeTunnelSubdomainAvailability(
      {required this.name,
      required this.available,
      required this.reason,
      required this.suggestions});
}

class HomeTunnelCatalog {
  final List<HomeTunnelDevice> devices;
  final List<HomeTunnelService> services;
  final HomeTunnelCapabilities capabilities;
  HomeTunnelCatalog(
      {required List<HomeTunnelDevice> devices,
      required List<HomeTunnelService> services,
      this.capabilities = const HomeTunnelCapabilities()})
      : devices = List.unmodifiable(devices),
        services = List.unmodifiable(services);
}

class _Reply {
  final int status;
  final Object? value;
  _Reply(this.status, this.value);
}

class _Operation {
  HttpClientRequest? request;
  bool cancelled = false;
  bool sent = false;
  void abort() {
    cancelled = true;
    request?.abort();
  }
}

class HomeTunnelApi {
  final Uri base;
  final bool Function() _isAllowed;
  final HttpClient _http;
  final Duration _requestTimeout;
  final int _maxResponseBytes;
  final HomeDeskCredentialStorage? _credentialStorage;
  final Set<_Operation> _operations = {};
  String? _accessToken;
  String? _refreshToken;
  String _displayName = '';
  int _generation = 0;
  bool _closed = false;
  bool _loginBusy = false;
  Future<void>? _refreshing;
  HomeDeskPortalCredential? _credential;
  CredentialTransaction? _credentialTransaction;
  final Set<CredentialTransaction> _pendingCredentialTransactions = {};
  bool _rememberLogin = false;
  Future<void>? _revocationClear;
  final Set<String> _mutating = {};
  HomeTunnelCapabilities _capabilities = const HomeTunnelCapabilities();
  final Map<String, HomeTunnelService> _knownServices = {};

  HomeTunnelApi(String origin,
      {required bool Function() isAllowed,
      HttpClient Function()? httpClientFactory,
      HomeDeskCredentialStorage? credentialStorage,
      Duration requestTimeout = const Duration(seconds: 10),
      int maxResponseBytes = 1024 * 1024})
      : base = _origin(origin),
        _isAllowed = isAllowed,
        _http = (httpClientFactory ?? (() => HttpClient()))(),
        _requestTimeout = requestTimeout,
        _credentialStorage = credentialStorage,
        _maxResponseBytes = maxResponseBytes {
    if (requestTimeout <= Duration.zero || maxResponseBytes < 1) {
      _http.close(force: true);
      throw const HomeTunnelApiException(
          'HomeTunnel 请求配置无效。', 'CONFIG_INVALID');
    }
    _http.findProxy = (_) => 'DIRECT';
    _http.connectionTimeout = requestTimeout;
    // 不设置 badCertificateCallback，保留系统 TLS 证书与主机名校验。
  }

  static Uri _origin(String value) {
    final uri = homeTunnelWebUrl(value);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      throw const HomeTunnelApiException(
          '请输入不含路径和凭据的 HomeTunnel HTTPS 地址。', 'ORIGIN_INVALID');
    }
    return Uri(
        scheme: 'https',
        host: uri.host,
        port: uri.port == 443 ? null : uri.port);
  }

  bool get isSignedIn {
    if (_closed) return false;
    if (!_allowed()) {
      _revokeSavedLogin();
      close();
      return false;
    }
    return _accessToken != null &&
        (_refreshToken != null || _refreshing != null);
  }

  String get displayName => _displayName;
  String get userId => _credential?.userId ?? '';
  bool get canRememberLogin => _credentialStorage?.supported == true;
  bool get rememberedLogin => _rememberLogin && isSignedIn;

  bool _allowed() {
    try {
      return _isAllowed();
    } catch (_) {
      return false;
    }
  }

  void _ensureAllowed() {
    if (_closed || !_allowed()) {
      if (!_closed) _revokeSavedLogin();
      close();
      throw const HomeTunnelApiException(
          'HomeTunnel 连接已关闭或本机授权已撤销。', 'ACCESS_REVOKED');
    }
  }

  void _revokeSavedLogin() {
    _revocationClear ??= _discardOwnedCredentials();
    // 同步网络入口立即关闭；UI 可 await revoke 确认本实例事务的条件清理。
    unawaited(_revocationClear!.catchError((_) {}));
  }

  Future<void> _discardOwnedCredentials() async {
    final transactions = {
      ..._pendingCredentialTransactions,
      if (_credentialTransaction != null) _credentialTransaction!
    };
    for (final transaction in transactions) {
      await _discardCredential(transaction);
    }
  }

  Future<void> revoke() {
    _revocationClear ??= _discardOwnedCredentials();
    close();
    return _revocationClear!;
  }

  void _checkGeneration(int generation) {
    _ensureAllowed();
    if (generation != _generation) {
      throw const HomeTunnelApiException(
          'HomeTunnel 登录已变更，请重新读取目录。', 'SESSION_CHANGED');
    }
  }

  void _clearSession() {
    _accessToken = null;
    _refreshToken = null;
    _displayName = '';
    _credential = null;
    _credentialTransaction = null;
    _pendingCredentialTransactions.clear();
    _rememberLogin = false;
    _capabilities = const HomeTunnelCapabilities();
    _knownServices.clear();
    _refreshing = null;
    _generation++;
    for (final operation in _operations.toList()) {
      operation.abort();
    }
  }

  void _checkOperation(_Operation operation, int generation) {
    _checkGeneration(generation);
    if (operation.cancelled) {
      throw const HomeTunnelApiException(
          'HomeTunnel 请求已取消。', 'REQUEST_CANCELLED');
    }
  }

  Future<_Reply> _request(String method, String path,
      {required int generation,
      String? token,
      Map<String, Object?>? body,
      Map<String, String>? query,
      bool mutation = false}) async {
    _checkGeneration(generation);
    final bytes = body == null ? null : utf8.encode(jsonEncode(body));
    if (bytes != null && bytes.length > 16 * 1024) {
      throw const HomeTunnelApiException(
          'HomeTunnel 请求内容过大。', 'REQUEST_TOO_LARGE');
    }
    final uri = base.replace(path: '/api/v1$path', queryParameters: query);
    final operation = _Operation();
    _operations.add(operation);
    try {
      return await _performRequest(
              operation, method, uri, generation, token, bytes)
          .timeout(_requestTimeout, onTimeout: () {
        operation.abort();
        throw const HomeTunnelApiException(
            'HomeTunnel 请求超时，请稍后重新登录或刷新。', 'REQUEST_TIMEOUT');
      });
    } on HomeTunnelApiException catch (error) {
      _checkGeneration(generation);
      if (mutation &&
          operation.sent &&
          [
            'REQUEST_TIMEOUT',
            'RESPONSE_INVALID',
            'RESPONSE_TOO_LARGE',
            'REQUEST_CANCELLED'
          ].contains(error.code)) {
        throw _unknownMutation();
      }
      rethrow;
    } on HandshakeException {
      _checkGeneration(generation);
      throw const HomeTunnelApiException(
          'HomeTunnel HTTPS 证书验证失败。', 'TLS_ERROR');
    } on FormatException {
      _checkGeneration(generation);
      if (mutation && operation.sent) throw _unknownMutation();
      throw const HomeTunnelApiException(
          'HomeTunnel 返回的数据格式无效。', 'RESPONSE_INVALID');
    } catch (_) {
      _checkGeneration(generation);
      if (mutation && operation.sent) throw _unknownMutation();
      throw const HomeTunnelApiException(
          '无法连接 HomeTunnel，请检查服务器地址和网络。', 'NETWORK_ERROR');
    } finally {
      operation.abort();
      _operations.remove(operation);
    }
  }

  Future<_Reply> _performRequest(_Operation operation, String method, Uri uri,
      int generation, String? token, List<int>? bytes) async {
    _checkOperation(operation, generation);
    final request = await _http.openUrl(method, uri);
    operation.request = request;
    // openUrl 可能等待 DNS、连接池或握手；写入任何凭据前再次检查本机授权。
    try {
      _checkOperation(operation, generation);
      request.followRedirects = false;
      request.maxRedirects = 0;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (token != null) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }
      if (bytes != null) {
        request.headers.contentType = ContentType.json;
        request.contentLength = bytes.length;
        _checkOperation(operation, generation);
        operation.sent = true;
        request.add(bytes);
      }
      _checkOperation(operation, generation);
      operation.sent = true;
      final response = await request.close();
      _checkOperation(operation, generation);
      if (response.statusCode >= 300 && response.statusCode < 400) {
        throw const HomeTunnelApiException(
            'HomeTunnel 返回了重定向，请核对原始服务器地址。', 'REDIRECT_BLOCKED');
      }
      if (response.contentLength > _maxResponseBytes) {
        throw const HomeTunnelApiException(
            'HomeTunnel 返回的数据过大。', 'RESPONSE_TOO_LARGE');
      }
      final collected = <int>[];
      await for (final chunk in response) {
        _checkOperation(operation, generation);
        if (collected.length + chunk.length > _maxResponseBytes) {
          throw const HomeTunnelApiException(
              'HomeTunnel 返回的数据过大。', 'RESPONSE_TOO_LARGE');
        }
        collected.addAll(chunk);
      }
      _checkOperation(operation, generation);
      final value =
          collected.isEmpty ? null : jsonDecode(utf8.decode(collected));
      _checkOperation(operation, generation);
      return _Reply(response.statusCode, value);
    } catch (_) {
      request.abort();
      rethrow;
    }
  }

  HomeTunnelApiException _failure(_Reply reply) {
    final candidate =
        reply.value is Map ? (reply.value as Map)['error_code'] : null;
    const messages = {
      'MFA_REQUIRED': '请输入 HomeTunnel 的动态验证码或恢复码。',
      'MFA_INVALID': '验证码无效、已使用或已过期。',
      'AUTH_INVALID': 'HomeTunnel 用户名或密码不正确。',
      'AUTH_REQUIRED': '请先登录 HomeTunnel。',
      'SESSION_REVOKED': 'HomeTunnel 登录已过期，请重新登录。',
      'PASSWORD_CHANGE_REQUIRED': '请先在 HomeTunnel 管理台修改初始密码。',
      'TEMPORARY_PASSWORD_EXPIRED': 'HomeTunnel 临时密码已过期，请联系管理员。',
      'USER_DISABLED': 'HomeTunnel 账号已停用。',
      'RATE_LIMITED': 'HomeTunnel 请求过于频繁，请稍后重试。',
      'VALIDATION_ERROR': 'HomeTunnel 请求参数无效，请检查输入。',
      'FORBIDDEN': 'HomeTunnel 拒绝访问，请检查账号权限。',
      'VERSION_CONFLICT': '该资源已被其他操作修改，请保留草稿并刷新核对。',
      'METADATA_VERSION_CONFLICT': '设备标签或收藏已变更，请保留草稿并刷新核对。',
      'ACCESS_POLICY_VERSION_CONFLICT': '访问策略已变更，请保留草稿并刷新核对。',
      'CLIENT_RAW_TUNNELS_DISABLED': '管理员尚未允许账号创建 TCP/UDP 服务。',
      'TCP_TUNNELS_DISABLED': '服务器尚未开放 TCP 服务。',
      'UDP_TUNNELS_DISABLED': '服务器尚未开放 UDP 服务。',
      'PORT_POOL_EXHAUSTED': '服务器可用端口已用完，请联系管理员。',
      'RESOURCE_LIMIT': '账号设备或服务数量已达到服务器上限。',
      'SUBDOMAIN_CONFLICT': '该子域名已被使用，请修改后重新检查。',
      'SUBDOMAIN_RESERVED': '该子域名由服务器保留，请使用其他名称。',
      'SUBDOMAIN_PREFIX_REQUIRED': '子域名不符合账号命名要求，请先检查可用性。',
      'OWNERSHIP_MISMATCH': '设备或服务已不存在，或不属于当前账号。',
      'DEVICE_REVOKED': '设备已撤销，请刷新设备目录。',
    };
    if (candidate is String && messages.containsKey(candidate)) {
      final object = reply.value as Map;
      return HomeTunnelApiException(messages[candidate]!, candidate,
          currentVersion: object['current_version'] is int
              ? object['current_version'] as int
              : null,
          currentAccessPolicyVersion:
              object['current_access_policy_version'] is int
                  ? object['current_access_policy_version'] as int
                  : null);
    }
    if (reply.status == 409) {
      return const HomeTunnelApiException(
          '资源发生冲突，请保留草稿并刷新核对后再提交。', 'VERSION_CONFLICT');
    }
    if (reply.status == 403) {
      return const HomeTunnelApiException(
          'HomeTunnel 拒绝访问，请检查账号权限。', 'FORBIDDEN');
    }
    return const HomeTunnelApiException(
        'HomeTunnel 请求失败，请检查服务器和账号权限。', 'HTTP_ERROR');
  }

  Map<String, dynamic> _object(Object? value) {
    if (value is Map<String, dynamic>) return value;
    throw const HomeTunnelApiException(
        'HomeTunnel 返回的数据格式无效。', 'RESPONSE_INVALID');
  }

  Map<String, dynamic> _success(_Reply reply) {
    if (reply.status < 200 || reply.status >= 300) throw _failure(reply);
    return _object(reply.value);
  }

  String _token(Object? value) {
    if (value is! String ||
        !RegExp(r'^[a-zA-Z0-9_-]{16,1024}$').hasMatch(value)) {
      throw const HomeTunnelApiException(
          'HomeTunnel 登录响应无效，请重新登录。', 'RESPONSE_INVALID');
    }
    return value;
  }

  String _text(Object? value, {int maxLength = 120}) {
    if (value is! String ||
        value.isEmpty ||
        value.length > maxLength ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(value)) {
      throw const HomeTunnelApiException(
          'HomeTunnel 返回的数据格式无效。', 'RESPONSE_INVALID');
    }
    return value;
  }

  String _id(Object? value) {
    final text = _text(value, maxLength: 36);
    if (!RegExp(r'^[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')
        .hasMatch(text)) {
      throw const HomeTunnelApiException(
          'HomeTunnel 设备或服务标识无效。', 'RESPONSE_INVALID');
    }
    return text;
  }

  bool _boolean(Object? value) {
    if (value is bool) return value;
    throw const HomeTunnelApiException(
        'HomeTunnel 返回的数据格式无效。', 'RESPONSE_INVALID');
  }

  String get _clientType => Platform.isWindows
      ? 'windows'
      : Platform.isMacOS
          ? 'macos'
          : 'linux';

  Future<void> _eraseRemembered() async {
    final storage = _credentialStorage;
    if (storage == null || !storage.supported) return;
    try {
      await storage.clear();
    } catch (_) {
      throw const HomeTunnelApiException(
          '无法清除安全保存的 HomeTunnel 登录，请检查本机凭据存储。', 'SECURE_STORE_ERROR');
    }
  }

  Future<void> forgetRememberedLogin() async {
    final generation = _generation;
    final refreshing = _refreshing;
    if (refreshing != null) {
      await refreshing;
      _checkGeneration(generation);
    }
    _rememberLogin = false;
    final pending = _revocationClear;
    if (pending != null) {
      await pending;
    }
    await _eraseRemembered();
  }

  Future<CredentialTransaction?> _beginCredentials(bool remember) async {
    if (remember && !canRememberLogin) {
      throw const HomeTunnelApiException(
          '本机未提供可用的安全凭据存储，不能记住登录。', 'SECURE_STORE_UNAVAILABLE');
    }
    if (!canRememberLogin) return null;
    try {
      return await _credentialStorage!.begin();
    } catch (_) {
      throw const HomeTunnelApiException(
          '无法初始化安全凭据存储，本次登录未保存。', 'SECURE_STORE_ERROR');
    }
  }

  DateTime _expiry(Object? value) {
    final parsed = value is String ? DateTime.tryParse(value) : null;
    if (parsed == null || !parsed.isAfter(DateTime.now())) {
      throw const HomeTunnelApiException(
          'HomeTunnel 返回的会话有效期无效，请重新登录。', 'SESSION_EXPIRED');
    }
    return parsed.toUtc();
  }

  Future<void> _acceptSession(Map<String, dynamic> result, int generation,
      {required bool remember,
      CredentialTransaction? transaction,
      String? expectedUserId}) async {
    final access = _token(result['access_token']);
    final refresh = _token(result['refresh_token']);
    final identity = _success(await _request('GET', '/auth/me',
        generation: generation, token: access));
    if (identity['device_id'] != null || identity['native_remote'] == true) {
      throw const HomeTunnelApiException(
          'HomeTunnel 需要独立的账号管理登录。', 'ACCOUNT_SESSION_REQUIRED');
    }
    if (identity['password_state'] == 'must_change') {
      throw const HomeTunnelApiException(
          '请先在 HomeTunnel 管理台修改初始密码。', 'PASSWORD_CHANGE_REQUIRED');
    }
    final userId = _id(identity['id']);
    if (expectedUserId != null && userId != expectedUserId) {
      throw const HomeTunnelApiException(
          'HomeTunnel 恢复的账号身份不匹配，请重新登录。', 'IDENTITY_MISMATCH');
    }
    final record = HomeDeskPortalCredential(
        origin: base.origin,
        userId: userId,
        username: _text(identity['username'], maxLength: 128),
        displayName: _text(identity['display_name'] ?? identity['username']),
        refreshToken: refresh,
        refreshExpiresAt: _expiry(result['refresh_expires_at']));
    _checkGeneration(generation);
    if (remember) {
      if (transaction == null || !canRememberLogin) {
        throw const HomeTunnelApiException(
            '安全会话事务已失效，请重新登录。', 'SECURE_STORE_ERROR');
      }
      try {
        await _credentialStorage!.save(record, transaction);
      } catch (_) {
        throw const HomeTunnelApiException(
            '无法安全保存新的登录令牌，会话已失效，请重新登录。', 'SECURE_STORE_ERROR');
      }
    }
    _checkGeneration(generation);
    _expiry(record.refreshExpiresAt.toIso8601String());
    _accessToken = access;
    _refreshToken = refresh;
    _displayName = record.displayName;
    _credential = record;
    _credentialTransaction = transaction;
    _pendingCredentialTransactions.remove(transaction);
    _rememberLogin = remember;
  }

  Future<void> _discardCredential(CredentialTransaction? transaction) async {
    if (transaction == null || !canRememberLogin) return;
    try {
      await _credentialStorage!.discard(transaction);
    } catch (_) {
      throw const HomeTunnelApiException(
          '无法失效本次安全登录事务，请检查本机凭据存储。', 'SECURE_STORE_ERROR');
    }
  }

  void _trackCredential(CredentialTransaction? transaction, int generation) {
    _checkGeneration(generation);
    if (transaction == null) return;
    _credentialTransaction = transaction;
    _pendingCredentialTransactions.add(transaction);
  }

  Future<void> _failedAuthentication(int generation,
      {CredentialTransaction? transaction}) async {
    if (_generation != generation) return;
    final owned = transaction ?? _credentialTransaction;
    _clearSession();
    await _discardCredential(owned);
  }

  Future<void> login(
      {required String username,
      required String password,
      String? mfaCode,
      bool rememberLogin = false}) async {
    _ensureAllowed();
    if (_loginBusy) {
      throw const HomeTunnelApiException(
          'HomeTunnel 正在登录，请等待当前请求完成。', 'OPERATION_BUSY');
    }
    if (username.trim().isEmpty ||
        username.length > 128 ||
        password.isEmpty ||
        password.length > 256 ||
        (mfaCode?.length ?? 0) > 128) {
      throw const HomeTunnelApiException(
          '请输入有效的 HomeTunnel 账号、密码和验证码。', 'INPUT_INVALID');
    }
    _loginBusy = true;
    _clearSession();
    final generation = _generation;
    CredentialTransaction? transaction;
    try {
      transaction = await _beginCredentials(rememberLogin);
      _trackCredential(transaction, generation);
      final session = _success(
          await _request('POST', '/auth/login', generation: generation, body: {
        'username': username.trim(),
        'password': password,
        'client_type': _clientType,
        if (mfaCode != null && mfaCode.isNotEmpty) 'mfa_code': mfaCode,
      }));
      final user = _object(session['user']);
      if (session['password_change_required'] == true ||
          user['password_state'] == 'must_change') {
        throw const HomeTunnelApiException(
            '请先在 HomeTunnel 管理台修改初始密码。', 'PASSWORD_CHANGE_REQUIRED');
      }
      await _acceptSession(session, generation,
          remember: rememberLogin,
          transaction: transaction,
          expectedUserId: _id(user['id']));
    } catch (_) {
      await _failedAuthentication(generation, transaction: transaction);
      rethrow;
    } finally {
      _loginBusy = false;
    }
  }

  Future<bool> restore() async {
    _ensureAllowed();
    if (!canRememberLogin) return false;
    if (_loginBusy) {
      throw const HomeTunnelApiException(
          'HomeTunnel 正在登录，请等待当前请求完成。', 'OPERATION_BUSY');
    }
    _loginBusy = true;
    _clearSession();
    final generation = _generation;
    CredentialTransaction? transaction;
    try {
      CredentialLease? lease;
      try {
        lease = await _credentialStorage!.consume();
      } catch (_) {
        throw const HomeTunnelApiException(
            '保存的 HomeTunnel 登录无法安全读取，请重新登录。', 'SECURE_STORE_ERROR');
      }
      if (lease == null) return false;
      transaction = lease.transaction;
      final record = lease.record;
      _trackCredential(transaction, generation);
      if (record.origin != base.origin) {
        throw const HomeTunnelApiException(
            '保存的 HomeTunnel 地址与本机批准地址不匹配，请重新登录。', 'ORIGIN_MISMATCH');
      }
      _expiry(record.refreshExpiresAt.toIso8601String());
      final result = _success(await _request('POST', '/auth/refresh',
          generation: generation,
          body: {
            'refresh_token': _token(record.refreshToken),
            'client_type': _clientType
          }));
      await _acceptSession(result, generation,
          remember: true,
          transaction: lease.transaction,
          expectedUserId: record.userId);
      return true;
    } catch (_) {
      await _failedAuthentication(generation, transaction: transaction);
      rethrow;
    } finally {
      _loginBusy = false;
    }
  }

  Future<void> resume(String refreshToken, {bool rememberLogin = false}) async {
    _ensureAllowed();
    if (_loginBusy) {
      throw const HomeTunnelApiException(
          'HomeTunnel 正在登录，请等待当前请求完成。', 'OPERATION_BUSY');
    }
    _loginBusy = true;
    _clearSession();
    final generation = _generation;
    CredentialTransaction? transaction;
    try {
      final token = _token(refreshToken);
      transaction = await _beginCredentials(rememberLogin);
      _trackCredential(transaction, generation);
      final result = _success(await _request('POST', '/auth/refresh',
          generation: generation,
          body: {'refresh_token': token, 'client_type': _clientType}));
      await _acceptSession(result, generation,
          remember: rememberLogin, transaction: transaction);
    } catch (_) {
      await _failedAuthentication(generation, transaction: transaction);
      rethrow;
    } finally {
      _loginBusy = false;
    }
  }

  Future<void> _refreshSession(String oldAccess, int generation) async {
    _checkGeneration(generation);
    if (_accessToken != null && _accessToken != oldAccess) return;
    final existing = _refreshing;
    if (existing != null) return existing;
    final refresh = _refreshToken;
    if (refresh == null) {
      _clearSession();
      throw const HomeTunnelApiException(
          'HomeTunnel 登录已过期，请重新登录。', 'SESSION_EXPIRED');
    }
    // native refresh 严格单次消费；无论失败还是丢失响应，都不再使用旧令牌。
    _refreshToken = null;
    final pending = _performRefresh(refresh, generation);
    _refreshing = pending;
    try {
      await pending;
    } finally {
      if (identical(_refreshing, pending)) _refreshing = null;
    }
  }

  Future<void> _performRefresh(String refresh, int generation) async {
    final remember = _rememberLogin;
    final expectedUserId = _credential?.userId;
    CredentialTransaction? transaction;
    try {
      if (remember) {
        final lease = await _credentialStorage!.consume();
        if (lease == null) {
          throw const HomeTunnelApiException(
              '保存的登录已被其他恢复操作消费，请重新登录。', 'SESSION_EXPIRED');
        }
        transaction = lease.transaction;
        _trackCredential(transaction, generation);
        if (lease.record.origin != base.origin ||
            lease.record.userId != expectedUserId ||
            lease.record.refreshToken != refresh) {
          throw const HomeTunnelApiException(
              '保存的 HomeTunnel 身份已改变，请重新登录。', 'IDENTITY_MISMATCH');
        }
      }
      _checkGeneration(generation);
      final result = _success(await _request('POST', '/auth/refresh',
          generation: generation,
          body: {'refresh_token': refresh, 'client_type': _clientType}));
      await _acceptSession(result, generation,
          remember: remember,
          transaction: transaction,
          expectedUserId: expectedUserId);
    } catch (error) {
      await _failedAuthentication(generation, transaction: transaction);
      _ensureAllowed();
      if (error is HomeTunnelApiException &&
          ['SECURE_STORE_ERROR', 'IDENTITY_MISMATCH'].contains(error.code)) {
        rethrow;
      }
      throw const HomeTunnelApiException(
          'HomeTunnel 会话刷新失败，请重新登录。', 'SESSION_EXPIRED');
    }
  }

  Future<Map<String, dynamic>> _get(
      String path, int generation, Map<String, String> query) async {
    _checkGeneration(generation);
    final oldAccess = _accessToken;
    if (oldAccess == null) {
      throw const HomeTunnelApiException('请先登录 HomeTunnel。', 'AUTH_REQUIRED');
    }
    return _success(await _authenticated('GET', path,
        generation: generation, query: query));
  }

  bool _authRejected(_Reply reply) =>
      reply.status == 401 &&
      reply.value is Map &&
      ['AUTH_REQUIRED', 'SESSION_REVOKED']
          .contains((reply.value as Map)['error_code']);

  Future<_Reply> _authenticated(String method, String path,
      {required int generation,
      Map<String, String>? query,
      Map<String, Object?>? body,
      bool mutation = false}) async {
    _checkGeneration(generation);
    final oldAccess = _accessToken;
    if (oldAccess == null) {
      throw const HomeTunnelApiException('请先登录 HomeTunnel。', 'AUTH_REQUIRED');
    }
    var reply = await _request(method, path,
        generation: generation,
        token: oldAccess,
        query: query,
        body: body,
        mutation: mutation);
    if (_authRejected(reply)) {
      await _refreshSession(oldAccess, generation);
      _checkGeneration(generation);
      reply = await _request(method, path,
          generation: generation,
          token: _accessToken,
          query: query,
          body: body,
          mutation: mutation);
      if (reply.status == 401) {
        await _failedAuthentication(generation);
        throw const HomeTunnelApiException(
            'HomeTunnel 登录已过期，请重新登录。', 'SESSION_EXPIRED');
      }
    }
    if (mutation && reply.status >= 500) throw _unknownMutation();
    return reply;
  }

  Future<List<Map<String, dynamic>>> _pages(String path, int generation,
      {void Function(Map<String, dynamic>)? onPage}) async {
    final result = <Map<String, dynamic>>[];
    final ids = <String>{};
    int? expectedTotal;
    int? expectedPages;
    for (var page = 1; page <= (expectedPages ?? 1); page++) {
      final value =
          await _get(path, generation, {'page': '$page', 'page_size': '100'});
      onPage?.call(value);
      final items = value['items'];
      final total = value['total'];
      final pages = value['total_pages'];
      if (total is int && total > 1000) {
        throw const HomeTunnelApiException(
            'HomeTunnel 目录超过当前支持的 1000 项，未返回截断结果。', 'RESOURCE_LIMIT');
      }
      if (items is! List ||
          items.length > 100 ||
          total is! int ||
          total < 0 ||
          pages is! int ||
          pages < 1 ||
          pages > 10 ||
          pages != (total == 0 ? 1 : (total / 100).ceil()) ||
          value['page'] != page ||
          value['page_size'] != 100) {
        throw const HomeTunnelApiException(
            'HomeTunnel 分页响应无效，未返回部分目录。', 'RESPONSE_INVALID');
      }
      expectedTotal ??= total;
      expectedPages ??= pages;
      if (expectedTotal != total || expectedPages != pages) {
        throw const HomeTunnelApiException(
            'HomeTunnel 目录在读取时发生变化，请重新刷新。', 'CATALOG_CHANGED');
      }
      for (final item in items) {
        final object = _object(item);
        if (!ids.add(_id(object['id']))) {
          throw const HomeTunnelApiException(
              'HomeTunnel 目录在读取时发生变化，请重新刷新。', 'CATALOG_CHANGED');
        }
        result.add(object);
      }
      _checkGeneration(generation);
    }
    if (result.length != expectedTotal) {
      throw const HomeTunnelApiException(
          'HomeTunnel 目录不完整，请重新刷新。', 'CATALOG_CHANGED');
    }
    return result;
  }

  Future<HomeTunnelCatalog> catalog() async {
    _ensureAllowed();
    if (_accessToken == null) {
      throw const HomeTunnelApiException('请先登录 HomeTunnel。', 'AUTH_REQUIRED');
    }
    final generation = _generation;
    var capabilities = const HomeTunnelCapabilities();
    final lists = await Future.wait([
      _pages('/client/devices', generation),
      _pages('/client/connections', generation, onPage: (value) {
        capabilities = _parseCapabilities(value['capabilities']);
      }),
    ]);
    final devices = lists[0]
        .map((item) => HomeTunnelDevice(
            id: _id(item['id']),
            name: _text(item['name']),
            platform: item['platform'] is String
                ? _text(item['platform'], maxLength: 64)
                : '',
            online: _boolean(item['online']),
            tags: _tags(item['tags'] ?? const []),
            favorite: _boolean(item['favorite'] ?? false),
            metadataVersion: _version(item['metadata_version'])))
        .toList();
    final services = lists[1].map(_service).toList();
    _checkGeneration(generation);
    _capabilities = capabilities;
    _knownServices
      ..clear()
      ..addEntries(services.map((service) => MapEntry(service.id, service)));
    return HomeTunnelCatalog(
        devices: devices, services: services, capabilities: capabilities);
  }

  Future<List<HomeDeskRemoteBinding>> remoteBindings() async {
    _ensureAllowed();
    final generation = _generation;
    final value = _success(await _authenticated('GET', '/homedesk/devices',
        generation: generation));
    final items = value['items'];
    if (items is! List || items.length > 5000) {
      throw const HomeTunnelApiException('家庭设备目录响应无效。', 'RESPONSE_INVALID');
    }
    final seen = <String>{};
    final bindings = <HomeDeskRemoteBinding>[];
    for (final raw in items) {
      final item = _object(raw);
      final id = _id(item['device_id']);
      final remote = _text(item['remote_id'], maxLength: 64);
      final key = _text(item['key_sha256'], maxLength: 64);
      final server = _endpoint(item['server']);
      if (!seen.add(id) ||
          !RegExp(r'^[a-zA-Z0-9_-]{1,64}$').hasMatch(remote) ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(key) ||
          server == null) {
        throw const HomeTunnelApiException('家庭设备远控信息无效。', 'RESPONSE_INVALID');
      }
      bindings.add(HomeDeskRemoteBinding(
          deviceId: id,
          remoteId: remote,
          server: server.toLowerCase(),
          keySHA256: key,
          platform: _text(item['platform'], maxLength: 32),
          online: _boolean(item['online'])));
    }
    _checkGeneration(generation);
    return List.unmodifiable(bindings);
  }

  // HOMEDESK: 本机接入只创建短期一次性代码，不绑定管理会话或创建服务。
  Future<String> createEnrollmentCode(String name) async {
    if (name.trim().isEmpty ||
        name.length > 120 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(name)) throw _invalidInput();
    return _mutate('local-device-enrollment', (generation) async {
      final reply = await _authenticated('POST', '/client/enrollment-codes',
          generation: generation, body: {'name': name.trim()}, mutation: true);
      final result = _success(reply);
      final code = result['code'];
      if (code is! String ||
          code.length < 16 ||
          code.length > 256 ||
          RegExp(r'[\s\x00-\x1f\x7f]').hasMatch(code)) {
        throw const HomeTunnelApiException(
            '接入码响应无效，请刷新核对后再接入。', 'MUTATION_RESULT_UNKNOWN');
      }
      _expiry(result['expires_at']);
      return code;
    });
  }

  int _version(Object? value) {
    if (value == null) return 1;
    if (value is int && value > 0) return value;
    throw const HomeTunnelApiException(
        'HomeTunnel 返回的资源版本无效。', 'RESPONSE_INVALID');
  }

  List<String> _tags(Object? value) {
    if (value is! List || value.length > 12) {
      throw const HomeTunnelApiException('设备标签格式无效。', 'RESPONSE_INVALID');
    }
    return List.unmodifiable(value.map((tag) => _text(tag, maxLength: 32)));
  }

  HomeTunnelCapabilities _parseCapabilities(Object? value) {
    if (value is! Map) return const HomeTunnelCapabilities();
    final tcp = value['tcp'];
    final udp = value['udp'];
    return HomeTunnelCapabilities(
        tcpEnabled: tcp is Map && tcp['enabled'] == true,
        tcpCanCreate: tcp is Map && tcp['can_create'] == true,
        udpEnabled: udp is Map && udp['enabled'] == true,
        udpCanCreate: udp is Map && udp['can_create'] == true,
        automaticPorts: value['automatic_ports'] == true);
  }

  HomeTunnelService _service(Map<String, dynamic> item) {
    final type = _text(item['proxy_type'], maxLength: 32);
    final enabled = _boolean(item['enabled']);
    return HomeTunnelService(
        id: _id(item['id']),
        deviceId: _id(item['device_id']),
        name: _text(item['name']),
        proxyType: type,
        status: _text(item['state'] ?? (enabled ? 'Pending' : 'Disabled'),
            maxLength: 32),
        webUrl: type == 'http' ? homeTunnelWebUrl(item['public_url']) : null,
        endpoint: ['tcp', 'udp'].contains(type)
            ? _endpoint(item['public_endpoint'])
            : null,
        enabled: enabled,
        version: _version(item['version']),
        accessPolicyVersion: _version(item['access_policy_version']),
        localScheme: item['local_scheme'] is String
            ? _text(item['local_scheme'], maxLength: 16)
            : 'http',
        localHost: item['local_host'] is String
            ? _text(item['local_host'], maxLength: 255)
            : '',
        localPort: item['local_port'] is int ? item['local_port'] as int : 0,
        subdomain: item['subdomain'] is String
            ? _text(item['subdomain'], maxLength: 63)
            : '',
        remotePort:
            item['remote_port'] is int ? item['remote_port'] as int : null,
        applicationProtocol: item['application_protocol'] is String
            ? _text(item['application_protocol'], maxLength: 16)
            : null);
  }

  HomeTunnelApiException _unknownMutation() => const HomeTunnelApiException(
      '本次操作的结果未知，请保留草稿并刷新核对，不要直接重复提交。', 'MUTATION_UNKNOWN');

  Map<String, dynamic> _mutationObject(_Reply reply) {
    if (reply.status < 200 || reply.status >= 300) throw _failure(reply);
    try {
      return _object(reply.value);
    } on HomeTunnelApiException {
      throw _unknownMutation();
    }
  }

  HomeTunnelApiException _invalidInput() => const HomeTunnelApiException(
      '服务或设备信息不符合要求，请检查名称、本地地址、端口和标签。', 'INPUT_INVALID');

  bool _validSubdomain(String name) =>
      name.length <= 63 &&
      RegExp(r'^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$').hasMatch(name);

  Map<String, Object?> _serviceValues(Map<String, dynamic> values,
      {required bool creating}) {
    const mutable = {
      'name',
      'local_scheme',
      'local_host',
      'local_port',
      'enabled',
      'subdomain',
      'application_protocol'
    };
    final allowed = {
      ...mutable,
      if (creating) 'device_id',
      if (creating) 'proxy_type'
    };
    if (values.isEmpty || values.keys.any((key) => !allowed.contains(key))) {
      throw _invalidInput();
    }
    final result = Map<String, Object?>.from(values);
    if (creating && !['http', 'tcp', 'udp'].contains(result['proxy_type'])) {
      throw _invalidInput();
    }
    try {
      if (creating) result['device_id'] = _id(result['device_id']);
      for (final field in ['name', 'local_host']) {
        if (creating || result.containsKey(field)) {
          result[field] =
              _text(result[field], maxLength: field == 'name' ? 120 : 255)
                  .trim();
          if ((result[field] as String).isEmpty) throw _invalidInput();
        }
      }
    } on HomeTunnelApiException {
      throw _invalidInput();
    }
    if (result.containsKey('local_host') &&
        !_validHost(result['local_host'] as String)) {
      throw _invalidInput();
    }
    if ((creating || result.containsKey('local_scheme')) &&
        !['http', 'https'].contains(result['local_scheme'])) {
      throw _invalidInput();
    }
    final port = result['local_port'];
    if ((creating || result.containsKey('local_port')) &&
        (port is! int || port < 1 || port > 65535)) throw _invalidInput();
    if (result.containsKey('enabled') && result['enabled'] is! bool) {
      throw _invalidInput();
    }
    if (creating) result.putIfAbsent('enabled', () => true);
    if (result.containsKey('subdomain')) {
      final name = result['subdomain'];
      if (name is! String || !_validSubdomain(name.trim().toLowerCase())) {
        throw _invalidInput();
      }
      result['subdomain'] = name.trim().toLowerCase();
    }
    final preset = result['application_protocol'];
    if (preset != null && !['ssh', 'rdp', 'rtsp'].contains(preset)) {
      throw _invalidInput();
    }
    if (creating && result['proxy_type'] != 'tcp' && preset != null) {
      throw _invalidInput();
    }
    if (creating &&
        result['proxy_type'] == 'http' &&
        !result.containsKey('subdomain')) throw _invalidInput();
    if (creating && result['proxy_type'] != 'http') result.remove('subdomain');
    return result;
  }

  Future<T> _mutate<T>(String key, Future<T> Function(int) operation) async {
    _ensureAllowed();
    if (_accessToken == null) {
      throw const HomeTunnelApiException('请先登录 HomeTunnel。', 'AUTH_REQUIRED');
    }
    if (!_mutating.add(key)) {
      throw const HomeTunnelApiException(
          '该资源正在处理，请等待当前操作完成。', 'OPERATION_BUSY');
    }
    final generation = _generation;
    try {
      final result = await operation(generation);
      _checkGeneration(generation);
      return result;
    } finally {
      _mutating.remove(key);
    }
  }

  Future<HomeTunnelSubdomainAvailability> checkSubdomain(String name,
      {String? connectionId}) async {
    _ensureAllowed();
    final normalized = name.trim().toLowerCase();
    if (!_validSubdomain(normalized)) throw _invalidInput();
    final value = await _get('/client/subdomains/availability', _generation, {
      'name': normalized,
      if (connectionId != null) 'connection_id': _id(connectionId)
    });
    final returned = value['name'];
    if (returned is! String || !_validSubdomain(returned)) {
      throw const HomeTunnelApiException('服务器返回的子域检查结果无效。', 'RESPONSE_INVALID');
    }
    final suggestions = value['suggestions'];
    final result = HomeTunnelSubdomainAvailability(
        name: returned,
        available: _boolean(value['available']),
        reason: _text(value['reason'], maxLength: 32),
        suggestions: List.unmodifiable(suggestions is List
            ? suggestions.whereType<String>().where(_validSubdomain).take(3)
            : <String>[]));
    _ensureAllowed();
    return result;
  }

  Future<HomeTunnelService> createService(Map<String, dynamic> values) async {
    _ensureAllowed();
    final body = _serviceValues(values, creating: true);
    final type = body['proxy_type'];
    if ((type == 'tcp' &&
            (!_capabilities.tcpEnabled || !_capabilities.tcpCanCreate)) ||
        (type == 'udp' &&
            (!_capabilities.udpEnabled || !_capabilities.udpCanCreate))) {
      throw const HomeTunnelApiException(
          '服务器尚未允许当前账号创建这种服务，请刷新能力或联系管理员。', 'FORBIDDEN');
    }
    return _mutate('create:${body['device_id']}', (generation) async {
      if (type == 'http') {
        final availability = await checkSubdomain(body['subdomain'] as String);
        if (!availability.available) {
          throw const HomeTunnelApiException(
              '子域名不可用，请保留草稿并选择可用名称。', 'SUBDOMAIN_UNAVAILABLE');
        }
      }
      final reply = await _authenticated('POST', '/client/connections',
          generation: generation, body: body, mutation: true);
      final value = _mutationObject(reply);
      try {
        final service = _service(value);
        _knownServices[service.id] = service;
        return service;
      } on HomeTunnelApiException {
        throw _unknownMutation();
      }
    });
  }

  Future<HomeTunnelService> updateService(
      String id, Map<String, dynamic> values,
      {required int expectedVersion}) async {
    _ensureAllowed();
    final serviceId = _id(id);
    if (expectedVersion < 1) throw _invalidInput();
    final body = _serviceValues(values, creating: false)
      ..['expected_version'] = expectedVersion;
    return _mutate(serviceId, (generation) async {
      if (body.containsKey('subdomain')) {
        final availability = await checkSubdomain(body['subdomain'] as String,
            connectionId: serviceId);
        if (!availability.available) {
          throw const HomeTunnelApiException(
              '子域名不可用，请保留草稿并选择可用名称。', 'SUBDOMAIN_UNAVAILABLE');
        }
      }
      final reply = await _authenticated(
          'PATCH', '/client/connections/$serviceId',
          generation: generation, body: body, mutation: true);
      final value = _mutationObject(reply);
      try {
        final service = _service(value);
        if (service.id != serviceId) throw _unknownMutation();
        _knownServices[service.id] = service;
        return service;
      } on HomeTunnelApiException {
        throw _unknownMutation();
      }
    });
  }

  Future<HomeTunnelService> setServiceEnabled(String id, bool enabled,
          {required int expectedVersion}) =>
      updateService(id, {'enabled': enabled}, expectedVersion: expectedVersion);

  Future<void> deleteService(String id, {required int expectedVersion}) async {
    _ensureAllowed();
    final serviceId = _id(id);
    if (expectedVersion < 1) throw _invalidInput();
    await _mutate(serviceId, (generation) async {
      final reply = await _authenticated(
          'DELETE', '/client/connections/$serviceId',
          generation: generation,
          body: {'expected_version': expectedVersion},
          mutation: true);
      if (reply.status < 200 || reply.status >= 300) throw _failure(reply);
      if (reply.status != 204) throw _unknownMutation();
      _knownServices.remove(serviceId);
    });
  }

  Future<void> updateDevice(String id,
      {required List<String> tags,
      required bool favorite,
      required int expectedMetadataVersion}) async {
    _ensureAllowed();
    final deviceId = _id(id);
    if (expectedMetadataVersion < 1 ||
        tags.length > 12 ||
        tags.any((tag) =>
            tag.trim().isEmpty ||
            tag.length > 32 ||
            RegExp(r'[\x00-\x1f\x7f]').hasMatch(tag))) throw _invalidInput();
    final normalized = tags.map((tag) => tag.trim()).toSet().toList()..sort();
    await _mutate('device:$deviceId', (generation) async {
      final reply =
          await _authenticated('PATCH', '/client/devices/$deviceId/metadata',
              generation: generation,
              body: {
                'tags': normalized,
                'favorite': favorite,
                'expected_metadata_version': expectedMetadataVersion
              },
              mutation: true);
      final value = _mutationObject(reply);
      if (value['id'] != deviceId || value['metadata_version'] is! int) {
        throw _unknownMutation();
      }
    });
  }

  Future<void> logout() async {
    _ensureAllowed();
    final access = _accessToken;
    final transactions = {
      ..._pendingCredentialTransactions,
      if (_credentialTransaction != null) _credentialTransaction!
    };
    _clearSession();
    final generation = _generation;
    HomeTunnelApiException? storageError;
    for (final transaction in transactions) {
      try {
        await _discardCredential(transaction);
      } on HomeTunnelApiException catch (error) {
        storageError = error;
      }
    }
    _checkGeneration(generation);
    if (access == null) {
      if (storageError != null) throw storageError;
      return;
    }
    try {
      final reply = await _request('POST', '/auth/session/close',
          generation: generation, token: access, body: {});
      if (reply.status != 204 && reply.status != 401) throw _failure(reply);
    } catch (_) {
      if (storageError != null) throw storageError;
      rethrow;
    } finally {
      if (_generation == generation) _clearSession();
    }
    if (storageError != null) throw storageError;
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _clearSession();
    _http.close(force: true);
  }
}
