// HOMEDESK: 桌面服务门户独立于 RustDesk 会话与家庭 Console。
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'homedesk_credentials.dart';
import 'homedesk_theme.dart';
import 'homedesk_account.dart';
import 'homedesk_device_label.dart';
import 'homedesk_local_agent.dart';
import 'homedesk_service_editor.dart';
import 'homedesk_tunnel_api.dart';
import 'homedesk_tunnel_session.dart';
import 'nestlink_native_session.dart';
import 'nestlink_locale.dart';
import 'models/platform_model.dart';

typedef HomeTunnelApiBuilder = HomeTunnelApi Function(String origin,
    {required bool Function() isAllowed,
    HomeDeskCredentialStorage? credentialStorage});

class HomeDeskServices extends StatefulWidget {
  final VoidCallback? onNetworkSettings;
  final String Function(String)? readOption;
  final HomeTunnelApiBuilder? apiBuilder;
  final Future<bool> Function(Uri)? onOpenUrl;
  final Future<void> Function(String)? onCopy;
  final Future<void> Function(String)? saveOrigin;
  final HomeDeskCredentialStorage Function()? credentialStoreFactory;
  final HomeDeskAccount? account;
  // 仅用于组件注入；生产继续使用已有受管 Agent 和接入入口。
  final HomeDeskLocalAgent? localAgent;
  final Future<void> Function(HomeTunnelApi api, int generation)? onRetryLocal;

  const HomeDeskServices(
      {super.key,
      this.onNetworkSettings,
      this.readOption,
      this.apiBuilder,
      this.onOpenUrl,
      this.onCopy,
      this.saveOrigin,
      this.credentialStoreFactory,
      this.account,
      this.localAgent,
      this.onRetryLocal});

  @override
  State<HomeDeskServices> createState() => _HomeDeskServicesState();
}

class _HomeDeskServicesState extends State<HomeDeskServices> {
  DialogRoute<void>? _noticeRoute;
  NavigatorState? _noticeNavigator;
  HomeTunnelApi? _noticeOwner;
  int? _noticeGeneration;
  StateSetter? _noticeUpdater;
  bool _noticeUpdateQueued = false;
  String _noticeHint = '';
  bool _accountQueued = false;
  HomeTunnelApi? _publishedApi;
  void _changeState(VoidCallback action) {
    super.setState(action);
    _queueNoticeUpdate();
    if (widget.account == null || _accountQueued) return;
    _accountQueued = true;
    scheduleMicrotask(() {
      _accountQueued = false;
      if (!mounted) return;
      final api = _api;
      if (api != null && api.isSignedIn) {
        _publishedApi = api;
        final generation = _generation;
        widget.account!
            .publish(api, _catalog, api.guiDeviceId.isNotEmpty ? api.guiDeviceId : (_localAgent?.deviceId ?? ''), _editDevice,
                onCatalog: (value) {
          if (_current(api, generation)) {
            _changeState(() => _applyCatalog(value));
          }
        });
      } else {
        widget.account!.clear(_publishedApi);
        _publishedApi = null;
      }
    });
  }

  final _origin = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  NestLinkNativeSession? _nativeSession;
  HomeTunnelApi? _api;
  HomeTunnelCatalog? _catalog;
  HomeDeskLocalAgent? _localAgent;
  Timer? _timer;
  late final HomeDeskCredentialStorage _credentialStore;
  final Map<String, HomeDeskServiceDraft> _serviceDrafts = {};
  final Map<String, HomeDeskDeviceDraft> _deviceDrafts = {};
  final Set<String> _entityBusy = {};
  final Set<String> _needsReview = {};
  String? _draftOwner;
  bool _rememberLogin = false;
  bool _allowed = false;
  bool _busy = false;
  String _message = '';
  String _deviceId = '';
  int _serviceType = 0; // 仅影响当前目录的显示筛选。
  String? _apiPermission;
  int _generation = 0;
  int _ticks = 0;

  bool _readAllowed() {
    try {
      return (widget.readOption ?? (key) => bind.mainGetLocalOption(key: key))(
              'homedesk-home-tunnel-allowed') ==
          'Y';
    } catch (_) {
      return false;
    }
  }

  String _readPermission() {
    try {
      return (widget.readOption ?? (key) => bind.mainGetLocalOption(key: key))(
          'homedesk-home-tunnel-permission');
    } catch (_) {
      return '';
    }
  }

  void _clearSecrets() {
    _password.clear();
  }

  void _revoke() {
    final api = _api;
    if (_localAgent != null) unawaited(_localAgent!.stop());
    _localAgent = null;
    _generation++;
    if (api != null) unawaited(_revokeApi(api, _generation));
    _api = null;
    _apiPermission = null;
    _catalog = null;
    _deviceId = '';
    _busy = false;
    _rememberLogin = false;
    _entityBusy.clear();
    _clearSecrets();
    _origin.text = _approvedOrigin() ?? '';
    _message = '管理台授权地址已变化，请确认地址后重新登录。';
  }

  Future<void> _revokeApi(HomeTunnelApi api, int generation) async {
    try {
      await api.revoke();
    } catch (_) {
      if (mounted && generation == _generation) {
        _changeState(() => _message = '网络会话已关闭，但无法确认清除该会话保存的登录。请检查本机安全存储。');
      }
    }
  }

  bool _ensureAllowed() {
    final allowed = _readAllowed();
    final changed = _api != null && _apiPermission != _readPermission();
    if (allowed != _allowed || changed) {
      if (mounted) {
        _changeState(() {
          _allowed = allowed;
          if (!allowed || changed) _revoke();
        });
      } else {
        _allowed = allowed;
        if (!allowed || changed) _revoke();
      }
    }
    return allowed && !changed;
  }

  bool _current(HomeTunnelApi api, int generation) =>
      mounted &&
      _ensureAllowed() &&
      identical(_api, api) &&
      _generation == generation;

  HomeTunnelApi _createApi({String? permission, String? origin}) {
    final pinned = permission ?? _readPermission();
    bool allowed() =>
        pinned.isNotEmpty && _readAllowed() && _readPermission() == pinned;
    return widget.apiBuilder?.call(origin ?? _origin.text.trim(),
            isAllowed: allowed, credentialStorage: _credentialStore) ??
        HomeTunnelApi(origin ?? _origin.text.trim(),
            isAllowed: allowed, credentialStorage: _credentialStore);
  }

  String? _approvedOrigin() {
    try {
      final value = (widget.readOption ??
          (key) =>
              bind.mainGetLocalOption(key: key))('homedesk-home-tunnel-origin');
      return value.isEmpty ? null : homeTunnelOrigin(value);
    } catch (_) {
      return null;
    }
  }

  Future<void> _restoreRemembered() async {
    if (!_credentialStore.supported) return;
    if (!_allowed) return;
    final initialGeneration = _generation;
    final permission = _readPermission();
    _changeState(() => _busy = true);
    HomeTunnelApi? api;
    var generation = initialGeneration;
    try {
      final account = await _credentialStore.peekAccount();
      if (!mounted || initialGeneration != _generation) return;
      if (!_readAllowed() || _readPermission() != permission) {
        _revoke();
        return;
      }
      if (account == null) return;
      final approved = _approvedOrigin();
      if (approved == null || homeTunnelOrigin(account.origin) != approved) {
        if (mounted) {
          _changeState(() => _message = '保存的账号与本机批准地址不一致，未恢复登录。请手动登录。');
        }
        return;
      }
      _origin.text = approved;
      _username.text = account.username;
      _selectDraftOwner(approved, account.username);
      api = _createApi(permission: permission, origin: approved);
      _api = api;
      _apiPermission = permission;
      generation = ++_generation;
      _changeState(() {
        _rememberLogin = true;
        _message = '正在恢复记住的登录…';
      });
      final restored = await api.restore();
      if (!_current(api, generation)) return;
      if (!restored) {
        _changeState(() {
          _rememberLogin = false;
          _message = '没有可以恢复的登录，请重新输入密码。';
        });
        return;
      }
      final catalog = await api.catalog();
      if (!_current(api, generation)) return;
      _changeState(() {
        _catalog = catalog;
        _message = '已恢复记住的登录。';
      });
      await _attachLocal(api, generation);
    } catch (error) {
      if (!mounted || generation != _generation) return;
      api?.close();
      _api = null;
      _apiPermission = null;
      if (mounted && generation == _generation) {
        _changeState(() {
          _rememberLogin = false;
          _message = '保存的登录未能恢复，请重新登录。${_errorMessage(error)}';
        });
      }
    } finally {
      if (mounted && generation == _generation) {
        _changeState(() => _busy = false);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _credentialStore = widget.credentialStoreFactory?.call() ??
        HomeDeskCredentialStore(applicationSupportDirectory: () async {
          final approved =
              bind.mainGetLocalOption(key: 'homedesk-credential-support');
          if (approved.isEmpty) return await getApplicationSupportDirectory();
          return Directory(approved);
        }); // HOMEDESK: 显示品牌更名后仍由原生批准旧身份目录。
    _allowed = _readAllowed();
    final approved = _approvedOrigin();
    if (approved != null) _origin.text = approved;
    // 页面由用户首次进入才创建；冷恢复只使用已批准 origin 和已加密的账号。
    unawaited(_restoreRemembered());
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_ensureAllowed()) return;
      if (_localAgent != null) {
        final before = _localAgent!.description;
        _localAgent!.poll();
        if (mounted && before != _localAgent!.description) _changeState(() {});
      }
      _ticks++;
      if (_ticks % 30 == 0 && _api?.isSignedIn == true && _entityBusy.isEmpty) {
        _refresh();
      }
    });
  }

  Future<void> _login() async {
    if (_busy || !_ensureAllowed()) return;
    if (_username.text.trim().isEmpty || _password.text.isEmpty) {
      _changeState(() => _message = '请输入账号和密码。');
      return;
    }
    String origin;
    try {
      origin = homeTunnelOrigin(_origin.text.trim());
    } catch (_) {
      _changeState(() => _message = '请输入有效的 HTTPS 服务端地址，不包含路径或账号信息。');
      return;
    }
    _selectDraftOwner(origin, _username.text.trim());
    final previousAgent = _localAgent;
    _localAgent = null;
    _api?.close();
    _api = null;
    _apiPermission = null;
    final generation = ++_generation;
    HomeTunnelApi? api;
    _changeState(() {
      _busy = true;
      _message = '';
      _catalog = null;
      _deviceId = '';
    });
    try {
      if (previousAgent != null) await previousAgent.stop();
      if (!mounted || generation != _generation) return;
      // 本机明确批准的 origin 独立保存；写入会变更许可代次，随后再固定新代次。
      await _credentialStore.clear();
      await (widget.saveOrigin?.call(origin) ??
          bind.mainSetLocalOption(
              key: 'homedesk-home-tunnel-origin', value: origin));
      if (!mounted || generation != _generation) return;
      if (!_readAllowed() || _approvedOrigin() != origin) {
        throw const HomeTunnelApiException(
            '本机尚未确认这个服务端地址，请重新核对网络设置。', 'ORIGIN_NOT_APPROVED');
      }
      final permission = _readPermission();
      if (permission.isEmpty) {
        throw const HomeTunnelApiException(
            '网络许可尚未确认，请稍后重新登录。', 'PERMISSION_CHANGED');
      }
      api = _createApi(permission: permission, origin: origin);
      _api = api;
      _apiPermission = permission;
      _origin.text = origin;
      await api.login(
          username: _username.text.trim(),
          password: _password.text,
          rememberLogin: _rememberLogin && _credentialStore.supported);
      if (!_current(api, generation)) return;
      _changeState(_clearSecrets);
      final catalog = await api.catalog();
      if (!_current(api, generation)) return;
      _changeState(() => _catalog = catalog);
      await _attachLocal(api, generation);
    } catch (error) {
      if (!mounted || generation != _generation) return;
      if (api != null && !_current(api, generation)) return;
      _changeState(() {
        _message = _errorMessage(error);
        _password.clear();
      });
    } finally {
      if (mounted && _generation == generation) {
        _changeState(() => _busy = false);
      }
    }
  }

  String _errorMessage(Object error) => error is HomeTunnelApiException
      ? error.message
      : error is HomeDeskCredentialException
          ? error.message
          : '服务暂时无法连接，请检查地址、证书和网络后重试。';

  Future<void> _attachLocal(HomeTunnelApi api, int generation) async {
    if (widget.apiBuilder == null && widget.readOption == null && _current(api, generation)) {
      if (_nativeSession == null) {
        final native = NestLinkNativeSession(api);
        _nativeSession = native;
        api.onSessionClosed = () { native.close(); if (identical(_nativeSession, native)) _nativeSession = null; };
        try { await native.start(); } catch (_) { _message = '设备登记未完成，请稍后重试。'; }
      }
    }
    // 合成预览/组件注入保持无真实后台进程；生产仅在许可有效且身份已校验后接入。
    if (widget.apiBuilder != null ||
        widget.readOption != null ||
        !_current(api, generation) ||
        _catalog == null) return;
    if (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) return;
    _localAgent ??= HomeDeskLocalAgent(
        send: (value) => bind.mainSetLocalOption(
            key: 'homedesk-tunnel-agent-command', value: value),
        read: () => bind.mainGetLocalOption(key: 'homedesk-tunnel-agent-state'),
        permission: _readPermission,
        isAllowed: () => _current(api, generation),
        name: '${Platform.localHostname} · ${bind.mainGetAppNameSync()}');
    try {
      final catalog = await _localAgent!.attach(api, _catalog!);
      if (_current(api, generation) && mounted) {
        _changeState(() => _catalog = catalog);
      }
    } on HomeDeskAgentException catch (_) {
      if (mounted && _current(api, generation)) _changeState(() {});
    } catch (_) {
      if (_localAgent != null) {
        _localAgent!.error = const HomeDeskAgentException('RUNTIME_FAILED');
        if (mounted) _changeState(() {});
      }
    }
  }

  void _selectDraftOwner(String origin, String username) {
    final owner = '$origin\u0000$username';
    if (_draftOwner != owner) {
      _serviceDrafts.clear();
      _deviceDrafts.clear();
      _needsReview.clear();
      _draftOwner = owner;
    }
  }

  void _applyCatalog(HomeTunnelCatalog catalog) {
    _catalog = catalog;
    if (!catalog.devices.any((device) => device.id == _deviceId)) {
      _deviceId = '';
    }
    _needsReview.removeWhere((key) =>
        !_serviceDrafts.containsKey(key) && !_deviceDrafts.containsKey(key));
  }

  Future<void> _refresh() async {
    if (_busy || _entityBusy.isNotEmpty || !_ensureAllowed()) return;
    final api = _api;
    if (api == null || !api.isSignedIn) return;
    final generation = _generation;
    _changeState(() {
      _busy = true;
      _message = '';
    });
    try {
      final catalog = await api.catalog();
      if (!_current(api, generation)) return;
      _changeState(() {
        _applyCatalog(catalog);
      });
    } catch (error) {
      if (!_current(api, generation)) return;
      _changeState(() {
        _message = _errorMessage(error);
        if (!api.isSignedIn) {
          _catalog = null;
          _deviceId = '';
          _rememberLogin = false;
        }
      });
    } finally {
      if (mounted && identical(_api, api) && _generation == generation) {
        _changeState(() => _busy = false);
      }
    }
  }

  Future<void> _logout() async {
    final api = _api;
    final localAgent = _localAgent;
    _localAgent = null;
    _changeState(() {
      _generation++;
      _api = null;
      _apiPermission = null;
      _catalog = null;
      _deviceId = '';
      _busy = false;
      _rememberLogin = false;
      _entityBusy.clear();
      _serviceDrafts.clear();
      _deviceDrafts.clear();
      _needsReview.clear();
      _draftOwner = null;
      _clearSecrets();
      _message = '';
    });
    final generation = _generation;
    if (localAgent != null) await localAgent.stop();
    if (api == null) {
      return;
    }
    try {
      await api.logout();
    } catch (error) {
      // 网络失败不重试旧凭据；安全存储未失效必须向用户准确说明。
      if (mounted &&
          generation == _generation &&
          ((error is HomeTunnelApiException &&
                  error.code == 'SECURE_STORE_ERROR') ||
              error is HomeDeskCredentialException)) {
        _changeState(() => _message = '本次会话已关闭，但无法确认清除保存的登录。请检查本机安全存储后再试。');
      }
    } finally {
      api.close();
    }
  }

  Future<void> _forgetRemembered() async {
    final api = _api;
    if (api == null || _busy || !_ensureAllowed()) return;
    final generation = _generation;
    _changeState(() => _busy = true);
    try {
      await api.forgetRememberedLogin();
      if (_current(api, generation)) {
        _changeState(() {
          _rememberLogin = false;
          _message = '已取消记住登录。本次会话仍可继续使用。';
        });
      }
    } catch (error) {
      if (_current(api, generation)) {
        _changeState(() => _message = _errorMessage(error));
      }
    } finally {
      if (mounted && generation == _generation) {
        _changeState(() => _busy = false);
      }
    }
  }

  Future<T> _operate<T>(String key, HomeTunnelApi api, int generation,
      Future<T> Function() action) async {
    if (_busy || _entityBusy.contains(key)) {
      throw const HomeTunnelApiException('这项操作正在进行，请稍候。', 'OPERATION_BUSY');
    }
    if (!_current(api, generation)) {
      throw const HomeTunnelApiException(
          '网络许可已变化，请重新登录。', 'PERMISSION_CHANGED');
    }
    _changeState(() => _entityBusy.add(key));
    try {
      return await action();
    } finally {
      if (mounted && generation == _generation) {
        _changeState(() => _entityBusy.remove(key));
      }
    }
  }

  Future<void> _reloadAfterMutation(HomeTunnelApi api, int generation) async {
    try {
      final catalog = await api.catalog();
      if (_current(api, generation)) {
        _changeState(() {
          _applyCatalog(catalog);
          _message = '操作已完成。';
        });
      }
    } catch (error) {
      if (_current(api, generation)) {
        _changeState(() {
          _message = '操作已完成，但列表暂未刷新。请刷新查看当前设置。';
          if (!api.isSignedIn) {
            _catalog = null;
            _rememberLogin = false;
          }
        });
      }
    }
  }

  void _mutationFailed(String key, Object error) {
    final code = error is HomeTunnelApiException ? error.code : '';
    if (!mounted) return;
    _changeState(() {
      if (code == 'MUTATION_UNKNOWN' || code.contains('VERSION_CONFLICT')) {
        _needsReview.add(key);
      }
      _message = code == 'MUTATION_UNKNOWN'
          ? '结果未确认，刷新核对后再操作，不会自动重试。'
          : code.contains('VERSION_CONFLICT')
              ? '服务器上的设置已经变化，请刷新核对后再操作。'
              : _errorMessage(error);
    });
  }

  HomeDeskServiceDraft _draftOf(HomeTunnelService service) =>
      HomeDeskServiceDraft(
          serviceId: service.id,
          deviceId: service.deviceId,
          name: service.name,
          proxyType: service.proxyType,
          localScheme: service.localScheme,
          localHost: service.localHost,
          localPort: service.localPort,
          subdomain: service.subdomain,
          applicationProtocol: service.applicationProtocol,
          enabled: service.enabled,
          expectedVersion: service.version);

  Set<String> get _creatableTypes {
    final capabilities = _catalog?.capabilities;
    return {
      'http',
      if (capabilities?.tcpEnabled == true &&
          capabilities?.tcpCanCreate == true)
        'tcp',
      if (capabilities?.udpEnabled == true &&
          capabilities?.udpCanCreate == true)
        'udp',
    };
  }

  Future<void> _editService(
      {HomeTunnelService? service, String? deviceId}) async {
    final api = _api;
    final catalog = _catalog;
    if (api == null || catalog == null || _busy || !_ensureAllowed()) return;
    final generation = _generation;
    final selected =
        deviceId ?? service?.deviceId ?? catalog.devices.firstOrNull?.id;
    if (selected == null ||
        !catalog.devices.any((device) => device.id == selected)) return;
    final key = service?.id ?? 'new:$selected';
    if (_entityBusy.contains(key)) return;
    final initial = _serviceDrafts[key] ??
        (service == null
            ? HomeDeskServiceDraft(deviceId: selected)
            : _draftOf(service));
    await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => HomeDeskServiceEditor(
            initial: initial,
            devices: catalog.devices,
            supportedTypes: _creatableTypes,
            remoteEndpoint: service?.endpoint,
            needsReview: _needsReview.contains(key),
            isAllowed: () => _current(api, generation),
            onDraftChanged: (draft) => _serviceDrafts[key] = draft,
            onReviewConfirmed: () {
              if (_current(api, generation)) {
                _changeState(() => _needsReview.remove(key));
              }
            },
            onReview: () => _operate(key, api, generation, () async {
                  final latest = await api.catalog();
                  if (!_current(api, generation)) {
                    throw const HomeTunnelApiException(
                        '网络许可已变化，请重新登录。', 'PERMISSION_CHANGED');
                  }
                  _changeState(() => _applyCatalog(latest));
                  if (service == null) {
                    final target =
                        _serviceDrafts[key]?.deviceId ?? initial.deviceId;
                    final summary = latest.services
                        .where((item) => item.deviceId == target)
                        .map((item) => _draftOf(item).summary)
                        .join('\n');
                    return HomeDeskServiceReview(
                        summary: summary.isEmpty ? '这台设备目前没有服务。' : summary);
                  }
                  final matches =
                      latest.services.where((item) => item.id == service.id);
                  return matches.isEmpty
                      ? const HomeDeskServiceReview(
                          summary: '服务已不存在。', exists: false)
                      : HomeDeskServiceReview(
                          summary: _draftOf(matches.first).summary,
                          version: matches.first.version);
                }),
            onSave: (draft) => _operate(key, api, generation, () async {
                  _serviceDrafts[key] = draft;
                  try {
                    if (draft.serviceId == null &&
                        !_creatableTypes.contains(draft.proxyType)) {
                      throw const HomeTunnelApiException(
                          '服务端暂不允许创建这种连接，请刷新查看可用能力。', 'CAPABILITY_DISABLED');
                    }
                    if (draft.proxyType == 'http') {
                      final available = await api.checkSubdomain(
                          draft.subdomain,
                          connectionId: draft.serviceId);
                      if (!available.available) {
                        throw HomeTunnelApiException(
                            '这个访问名称不可用。${available.suggestions.isEmpty ? '' : '可尝试：${available.suggestions.join('、')}。'}',
                            'SUBDOMAIN_UNAVAILABLE');
                      }
                    }
                    if (draft.serviceId == null) {
                      await api.createService(draft.toValues());
                    } else {
                      await api.updateService(
                          draft.serviceId!, draft.toValues(),
                          expectedVersion: draft.expectedVersion!);
                    }
                    if (!_current(api, generation)) {
                      throw const HomeTunnelApiException(
                          '网络许可已变化，请重新登录。', 'PERMISSION_CHANGED');
                    }
                    _serviceDrafts.remove(key);
                    _needsReview.remove(key);
                    await _reloadAfterMutation(api, generation);
                  } catch (error) {
                    if (_current(api, generation)) _mutationFailed(key, error);
                    rethrow;
                  }
                })));
  }

  Future<void> _toggleService(HomeTunnelService service) async {
    final api = _api;
    if (api == null || _needsReview.contains(service.id) || !_ensureAllowed()) {
      return;
    }
    final generation = _generation;
    try {
      await _operate(service.id, api, generation, () async {
        await api.setServiceEnabled(service.id, !service.enabled,
            expectedVersion: service.version);
        if (!_current(api, generation)) return;
        await _reloadAfterMutation(api, generation);
      });
    } catch (error) {
      if (_current(api, generation)) _mutationFailed(service.id, error);
    }
  }

  Future<void> _deleteService(HomeTunnelService service) async {
    final api = _api;
    if (api == null ||
        _busy ||
        _entityBusy.contains(service.id) ||
        _needsReview.contains(service.id) ||
        !_ensureAllowed()) return;
    final generation = _generation;
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('删除内网穿透？'),
                content: Text('删除“${service.name}”后，其访问地址将停止工作。可以随后重新创建服务。'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('取消')),
                  FilledButton(
                      key: ValueKey('confirm-delete-${service.id}'),
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('删除')),
                ]));
    if (confirmed != true || !_current(api, generation)) return;
    try {
      await _operate(service.id, api, generation, () async {
        await api.deleteService(service.id, expectedVersion: service.version);
        if (!_current(api, generation)) return;
        _serviceDrafts.remove(service.id);
        await _reloadAfterMutation(api, generation);
      });
    } catch (error) {
      if (_current(api, generation)) _mutationFailed(service.id, error);
    }
  }

  Future<void> _editDevice(HomeTunnelDevice device) async {
    final api = _api;
    if (api == null ||
        _busy ||
        _entityBusy.contains(device.id) ||
        !_ensureAllowed()) return;
    final generation = _generation;
    final initial = _deviceDrafts[device.id] ??
        HomeDeskDeviceDraft(
            tags: device.tags,
            favorite: device.favorite,
            expectedMetadataVersion: device.metadataVersion);
    await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => HomeDeskDeviceEditor(
            deviceName: device.name,
            initial: initial,
            needsReview: _needsReview.contains(device.id),
            isAllowed: () => _current(api, generation),
            onDraftChanged: (draft) => _deviceDrafts[device.id] = draft,
            onReviewConfirmed: () {
              if (_current(api, generation)) {
                _changeState(() => _needsReview.remove(device.id));
              }
            },
            onReview: () => _operate(device.id, api, generation, () async {
                  final latest = await api.catalog();
                  if (!_current(api, generation)) {
                    throw const HomeTunnelApiException(
                        '网络许可已变化，请重新登录。', 'PERMISSION_CHANGED');
                  }
                  _changeState(() => _applyCatalog(latest));
                  final matches =
                      latest.devices.where((item) => item.id == device.id);
                  if (matches.isEmpty) {
                    throw const HomeTunnelApiException(
                        '这台设备已不在账号中，不能覆盖保存。', 'NOT_FOUND');
                  }
                  final current = matches.first;
                  return HomeDeskDeviceDraft(
                      tags: current.tags,
                      favorite: current.favorite,
                      expectedMetadataVersion: current.metadataVersion);
                }),
            onSave: (draft) => _operate(device.id, api, generation, () async {
                  _deviceDrafts[device.id] = draft;
                  try {
                    await api.updateDevice(device.id,
                        tags: draft.tags,
                        favorite: draft.favorite,
                        expectedMetadataVersion: draft.expectedMetadataVersion);
                    if (!_current(api, generation)) {
                      throw const HomeTunnelApiException(
                          '网络许可已变化，请重新登录。', 'PERMISSION_CHANGED');
                    }
                    _deviceDrafts.remove(device.id);
                    _needsReview.remove(device.id);
                    await _reloadAfterMutation(api, generation);
                  } catch (error) {
                    if (_current(api, generation)) {
                      _mutationFailed(device.id, error);
                    }
                    rethrow;
                  }
                })));
  }

  Future<void> _open(Uri uri) async {
    if (!_ensureAllowed()) return;
    if (homeTunnelWebUrl(uri.toString()) == null) {
      _changeState(() => _message = '这个服务没有可打开的网页地址。');
      return;
    }
    final generation = _generation;
    try {
      // 仅交给浏览器地址，不携带门户登录凭据，也不生成自动登录链接。
      final opened = await (widget.onOpenUrl?.call(uri) ??
          launchUrl(uri, mode: LaunchMode.externalApplication));
      if (!mounted || !_ensureAllowed() || generation != _generation) return;
      if (!opened) _changeState(() => _message = '浏览器未能打开地址，请稍后重试。');
    } catch (_) {
      if (mounted && _ensureAllowed() && generation == _generation) {
        _changeState(() => _message = '浏览器未能打开地址，请稍后重试。');
      }
    }
  }

  Future<void> _openManagement() async {
    if (!_ensureAllowed()) return;
    if (_api != null) return _open(_api!.base);
    try {
      final api = _createApi();
      final base = api.base;
      api.close();
      await _open(base);
    } catch (_) {
      if (mounted) {
        _changeState(() => _message = '请先填写有效的 HTTPS 服务端地址。');
      }
    }
  }

  Future<void> _copy(String endpoint) async {
    if (!_ensureAllowed()) return;
    final generation = _generation;
    try {
      await (widget.onCopy?.call(endpoint) ??
          Clipboard.setData(ClipboardData(text: endpoint)));
      if (mounted && _ensureAllowed() && generation == _generation) {
        _changeState(() => _message = '访问地址已复制。');
      }
    } catch (_) {
      if (mounted && _ensureAllowed() && generation == _generation) {
        _changeState(() => _message = '无法写入剪贴板，可以手动选择并复制访问地址。');
      }
    }
  }

  @override
  void dispose() {
    final route = _noticeRoute, navigator = _noticeNavigator;
    if (route != null && navigator != null) {
      scheduleMicrotask(() {
        if (navigator.mounted && route.isActive) {
          navigator.removeRoute(route);
        }
      });
    }
    widget.account?.clear(_publishedApi);
    _generation++;
    _timer?.cancel();
    _api?.close();
    _clearSecrets();
    for (final controller in [_origin, _username, _password]) {
      controller.dispose();
    }
    super.dispose();
  }

  Widget _messageBox() {
    final colors = Theme.of(context).colorScheme;
    final informational = _message == '访问地址已复制。' ||
        _message == '操作已完成。' ||
        _message == '已恢复记住的登录。' ||
        _message.startsWith('已取消记住登录');
    return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(_message,
            style: TextStyle(
                color:
                    informational ? colors.onSurfaceVariant : colors.error)));
  }

  Widget _loginFormContent() => SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
      child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Card(
                  child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Center(child: SvgPicture.asset('assets/icon.svg', width: 52, height: 52)),
                            const SizedBox(height: 14),
                            Text(nl('登录栖云桥', 'Sign in to NestLink'),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 10),
                            Text(nl('连接你的自建服务，管理设备、远控与内网穿透。',
                                'Connect to your own service for devices, remote control and tunnels.'), textAlign: TextAlign.center),
                            const SizedBox(height: 20),
                            if (!_allowed) ...[
                              const Text('请确认内网穿透的 HTTPS 地址和账号授权。穿透服务独立于 P2P 远控设置。'),
                              if (widget.onNetworkSettings != null)
                                Align(
                                    alignment: Alignment.centerLeft,
                                    child: TextButton.icon(
                                        onPressed: widget.onNetworkSettings,
                                        icon: const Icon(Icons.tune_rounded),
                                        label: const Text('打开网络设置'))),
                              const SizedBox(height: 12),
                            ],
                            HomeDeskFieldLabel(nl('服务端 HTTPS 地址', 'HTTPS service address'),
                                child: TextField(
                                    key: const ValueKey('tunnel-origin'),
                                    controller: _origin,
                                    enabled: !_busy && _allowed,
                                    keyboardType: TextInputType.url,
                                    autocorrect: false,
                                    decoration: const InputDecoration(
                                        hintText: 'https://console.example.com',
                                        border: null))),
                            const SizedBox(height: 14),
                            HomeDeskFieldLabel(nl('账号', 'Account'),
                                child: TextField(
                                    key: const ValueKey('tunnel-username'),
                                    controller: _username,
                                    enabled: !_busy && _allowed,
                                    autocorrect: false,
                                    decoration:
                                        const InputDecoration(border: null))),
                            const SizedBox(height: 14),
                            HomeDeskFieldLabel(nl('密码', 'Password'),
                                child: TextField(
                                    key: const ValueKey('tunnel-password'),
                                    controller: _password,
                                    enabled: !_busy && _allowed,
                                    obscureText: true,
                                    enableSuggestions: false,
                                    autocorrect: false,
                                    onSubmitted: (_) => _login(),
                                    decoration:
                                        const InputDecoration(border: null))),
                            const SizedBox(height: 16),
                            CheckboxListTile(
                                key: const ValueKey('tunnel-remember'),
                                contentPadding: EdgeInsets.zero,
                                title: Text(nl('记住登录', 'Remember me')),
                                subtitle: Text(_credentialStore.supported
                                    ? nl('使用本机系统安全存储，下次启动时恢复。', 'Restore with this device’s protected storage.')
                                    : nl('当前平台未启用安全存储，本次登录仅保留在内存中。', 'Protected storage is unavailable; this login is kept in memory.')),
                                value: _rememberLogin,
                                onChanged: !_busy &&
                                        _allowed &&
                                        _credentialStore.supported
                                    ? (value) => _changeState(
                                        () => _rememberLogin = value ?? false)
                                    : null),
                            if (_message.isNotEmpty) _messageBox(),
                            FilledButton.icon(
                                key: const ValueKey('tunnel-login'),
                                onPressed: !_busy && _allowed ? _login : null,
                                icon: const Icon(Icons.login_rounded, size: 20),
                                label: Text(_busy ? nl('正在登录…', 'Signing in…') : nl('登录并查看', 'Sign in'))),
                            const SizedBox(height: 8),
                            TextButton(
                                onPressed:
                                    !_busy && _allowed ? _openManagement : null,
                                child: Text(nl('打开管理台', 'Open console'))),
                            const SizedBox(height: 8),
                            Text(nl('密码不会保存。管理台会在浏览器中单独登录。', 'Your password is never saved. The console has its own browser session.'),
                                style: TextStyle(fontSize: 12)),
                          ]))))));

  List<_ServiceGroup> _groups() {
    final catalog = _catalog;
    if (catalog == null) return [];
    final groups = <String, _ServiceGroup>{
      for (final device in catalog.devices)
        device.id: _ServiceGroup(
            device.id, homeDeskDeviceLabel(device.name), device.online,
            device: device)
    };
    for (final service in catalog.services) {
      (groups[service.deviceId] ??=
              _ServiceGroup(service.deviceId, '未返回的设备', null))
          .services
          .add(service);
    }
    final visible = groups.values
        .where((group) => _deviceId.isEmpty || group.id == _deviceId)
        .toList();
    visible.sort((left, right) => (right.device?.favorite == true ? 1 : 0)
        .compareTo(left.device?.favorite == true ? 1 : 0));
    return visible;
  }

  String _status(HomeTunnelService service) {
    if (!service.enabled) return '已暂停';
    switch (service.status) {
      case 'Online':
        return '服务在线';
      case 'Pending':
        return '等待配置';
      case 'Applying':
        return '正在配置';
      case 'Degraded':
        return '连接异常';
      case 'Offline':
        return '服务离线';
      case 'Error':
        return '连接失败';
      case 'Disabled':
        return '已暂停';
      default:
        return '状态未知';
    }
  }

  Widget _serviceTile(HomeTunnelService service) {
    final t = HomeDeskTokens.of(context);
    final address = service.webUrl?.toString() ?? service.endpoint;
    final attention = service.enabled &&
        (service.status == 'Error' || service.status == 'Degraded');
    final waiting = service.enabled &&
        (service.status == 'Pending' || service.status == 'Applying');
    final disabled = _busy || _entityBusy.contains(service.id);
    final guarded = disabled || _needsReview.contains(service.id);
    final web = service.proxyType == 'http' || service.proxyType == 'https';
    return Container(
        padding: const EdgeInsets.all(HomeDeskTokens.cardPadding),
        decoration: BoxDecoration(
            color: t.surface,
            border: Border.all(color: t.border),
            borderRadius: BorderRadius.circular(HomeDeskTokens.cardRadius)),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                    color: t.sunken,
                    borderRadius:
                        BorderRadius.circular(HomeDeskTokens.controlRadius)),
                child: Icon(web ? Icons.language_rounded : Icons.cable_rounded,
                    color: t.secondary, size: 20)),
            const SizedBox(width: 10),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(service.name.isEmpty ? '未命名服务' : service.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.sectionStyle),
                  Text(
                      web
                          ? '网页服务'
                          : service.proxyType == 'tcp'
                              ? 'TCP 端口'
                              : service.proxyType == 'udp'
                                  ? 'UDP 端口'
                                  : '其他服务',
                      style: t.auxiliaryStyle),
                ])),
            const SizedBox(width: 8),
            HomeDeskBadge(_status(service),
                tone: attention
                    ? HomeDeskTone.danger
                    : waiting
                        ? HomeDeskTone.warning
                        : !service.enabled || service.status == 'Disabled'
                            ? HomeDeskTone.neutral
                            : service.status == 'Online'
                                ? HomeDeskTone.success
                                : HomeDeskTone.neutral),
          ]),
          const SizedBox(height: 12),
          if (attention || waiting)
            Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: attention ? t.dangerSoft : t.warningSoft,
                    borderRadius:
                        BorderRadius.circular(HomeDeskTokens.smallRadius)),
                child: Text(_status(service),
                    style: TextStyle(
                        color: attention ? t.danger : t.warning,
                        fontSize: HomeDeskTokens.auxiliary)))
          else
            SelectableText(address ?? '访问地址尚未分配',
                maxLines: 2,
                style: TextStyle(
                    color: t.accentText, fontSize: HomeDeskTokens.auxiliary)),
          const SizedBox(height: 8),
          Text(
              service.localHost.isEmpty || service.localPort == 0
                  ? '本地目标未返回'
                  : '本地：${web ? '${service.localScheme}://' : ''}${service.localHost}:${service.localPort}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.auxiliaryStyle),
          const SizedBox(height: 12),
          Wrap(
              spacing: 4,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (service.webUrl != null)
                  FilledButton.icon(
                      onPressed: _allowed ? () => _open(service.webUrl!) : null,
                      icon: const Icon(Icons.open_in_new_rounded, size: 16),
                      label: const Text('打开'))
                else if (service.endpoint != null)
                  FilledButton(
                      onPressed:
                          _allowed ? () => _copy(service.endpoint!) : null,
                      child: const Text('复制地址')),
                if (address != null)
                  IconButton(
                      tooltip: '复制地址',
                      onPressed: _allowed ? () => _copy(address) : null,
                      icon: const Icon(Icons.copy_rounded, size: 18)),
                IconButton(
                    key: ValueKey('edit-service-${service.id}'),
                    tooltip: '编辑服务',
                    onPressed:
                        disabled ? null : () => _editService(service: service),
                    icon: const Icon(Icons.edit_outlined, size: 18)),
                PopupMenuButton<String>(
                    key: ValueKey('more-service-${service.id}'),
                    tooltip: '更多服务操作',
                    enabled: !disabled,
                    onSelected: (action) {
                      if (action == 'toggle') _toggleService(service);
                      if (action == 'delete') _deleteService(service);
                    },
                    itemBuilder: (_) => [
                          PopupMenuItem(
                              key: ValueKey('toggle-service-${service.id}'),
                              value: 'toggle',
                              enabled: !guarded,
                              child: Text(service.enabled ? '暂停' : '恢复')),
                          PopupMenuItem(
                              key: ValueKey('delete-service-${service.id}'),
                              value: 'delete',
                              enabled: !guarded,
                              child: const Text('删除')),
                        ],
                    child: const SizedBox(
                        width: 40,
                        height: 40,
                        child: Icon(Icons.more_horiz_rounded, size: 18))),
              ]),
          if (_entityBusy.contains(service.id)) const LinearProgressIndicator(),
        ]));
  }

  Widget _badge(String label, {bool attention = false}) => HomeDeskBadge(label,
      dot: false, tone: attention ? HomeDeskTone.danger : HomeDeskTone.neutral);

  Widget _groupCard(_ServiceGroup group) {
    final t = HomeDeskTokens.of(context);
    final local = _localAgent?.deviceId == group.id;
    final visible = group.services
        .where((service) => switch (_serviceType) {
              1 => service.proxyType == 'http' || service.proxyType == 'https',
              2 => service.proxyType == 'tcp',
              3 => service.proxyType == 'udp',
              _ => true,
            })
        .toList();
    return Padding(
        padding: const EdgeInsets.only(bottom: HomeDeskTokens.moduleGap),
        child: Container(
            padding: const EdgeInsets.all(HomeDeskTokens.cardPadding),
            decoration: BoxDecoration(
                color: t.surface2,
                border: Border.all(color: t.border),
                borderRadius: BorderRadius.circular(HomeDeskTokens.cardRadius)),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    Icon(Icons.dns_outlined, size: 22, color: t.accent),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Text(group.name.isEmpty ? '未命名设备' : group.name,
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.ellipsis,
                            style: t.sectionStyle)),
                    if (group.device != null)
                      IconButton(
                          key: ValueKey('edit-device-${group.id}'),
                          tooltip: '管理设备',
                          onPressed: _busy || _entityBusy.contains(group.id)
                              ? null
                              : () => _editDevice(group.device!),
                          icon: const Icon(Icons.tune_rounded, size: 18))
                  ]),
                  Wrap(spacing: 8, runSpacing: 6, children: [
                    if (local)
                      const HomeDeskBadge('本机', tone: HomeDeskTone.accent),
                    HomeDeskBadge(
                        group.online == null
                            ? '心跳未知'
                            : group.online!
                                ? '设备心跳在线'
                                : '设备心跳离线',
                        tone: group.online == true
                            ? HomeDeskTone.success
                            : HomeDeskTone.neutral),
                    _badge('${group.services.length} 项服务'),
                    if (group.device?.favorite == true)
                      const Icon(Icons.star_rounded, size: 18),
                    for (final tag in group.device?.tags ?? <String>[])
                      _badge(tag),
                  ]),
                  const SizedBox(height: 16),
                  if (visible.isEmpty)
                    Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                  group.services.isEmpty
                                      ? '还没有发布服务'
                                      : '当前类型下暂无服务',
                                  style: t.sectionStyle),
                              if (group.services.isEmpty) ...[
                                const SizedBox(height: 6),
                                Text('点击“添加服务”，选择要访问的网页或端口。',
                                    style: t.auxiliaryStyle)
                              ],
                            ]))
                  else
                    LayoutBuilder(builder: (context, c) {
                      final scale = MediaQuery.textScalerOf(context).scale(1);
                      final columns = scale > 1.5
                          ? 1
                          : ((c.maxWidth + 16) / 296).floor().clamp(1, 3);
                      final width = (c.maxWidth - 16 * (columns - 1)) / columns;
                      return Wrap(spacing: 16, runSpacing: 16, children: [
                        for (final service in visible)
                          SizedBox(width: width, child: _serviceTile(service))
                      ]);
                    }),
                ])));
  }

  Widget _accountHeader(HomeTunnelApi api) {
    final t = HomeDeskTokens.of(context);
    final information = Wrap(
        spacing: 12,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          HomeDeskBadge('账号已登录 · ${api.displayName}',
              tone: HomeDeskTone.success),
          Text(api.base.host,
              key: const ValueKey('tunnel-server-host'),
              style: t.auxiliaryStyle),
          _connectionNotice(),
        ]);
    final actions = Row(mainAxisSize: MainAxisSize.min, children: [
      IconButton(
          key: const ValueKey('tunnel-refresh'),
          tooltip: _busy ? '正在刷新…' : '刷新',
          onPressed: _busy ? null : _refresh,
          icon: const Icon(Icons.refresh_rounded, size: 20)),
      PopupMenuButton<String>(
          key: const ValueKey('tunnel-account-menu'),
          tooltip: '账号操作',
          enabled: !_busy,
          onSelected: (action) {
            if (action == 'management') _openManagement();
            if (action == 'forget') _forgetRemembered();
            if (action == 'logout') _logout();
          },
          itemBuilder: (_) => [
                const PopupMenuItem(value: 'management', child: Text('打开管理台')),
                if (api.rememberedLogin)
                  const PopupMenuItem(
                      key: ValueKey('tunnel-forget'),
                      value: 'forget',
                      child: Text('取消记住登录')),
                const PopupMenuItem(value: 'logout', child: Text('退出登录'))
              ],
          icon: const Icon(Icons.more_horiz_rounded)),
    ]);
    return Container(
        key: const ValueKey('tunnel-account-status'),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
            color: t.surface2,
            border: Border.all(color: t.border),
            borderRadius: BorderRadius.circular(HomeDeskTokens.blockRadius)),
        child: LayoutBuilder(builder: (context, c) {
          if (c.maxWidth < 420 ||
              MediaQuery.textScalerOf(context).scale(1) > 1.5) {
            return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  information,
                  const SizedBox(height: 6),
                  Align(alignment: Alignment.centerRight, child: actions)
                ]);
          }
          return Row(children: [
            Expanded(child: information),
            const SizedBox(width: 12),
            actions
          ]);
        }));
  }

  bool _noticeValid() =>
      mounted &&
      _api != null &&
      identical(_api, _noticeOwner) &&
      _generation == _noticeGeneration &&
      _readAllowed() &&
      _apiPermission == _readPermission();
  void _queueNoticeUpdate() {
    if (_noticeUpdateQueued || _noticeRoute == null) {
      return;
    }
    _noticeUpdateQueued = true;
    scheduleMicrotask(() {
      _noticeUpdateQueued = false;
      final route = _noticeRoute, navigator = _noticeNavigator;
      if (route == null ||
          navigator == null ||
          !navigator.mounted ||
          !route.isActive) {
        return;
      }
      if (!_noticeValid()) {
        navigator.removeRoute(route);
      } else {
        _noticeUpdater?.call(() {});
      }
    });
  }

  void _noticeMessage(String message) {
    _noticeHint = message;
    if (_noticeRoute?.isActive == true) {
      _noticeUpdater?.call(() {});
    } else if (mounted) {
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _retryLocal(HomeTunnelApi owner, int openedGeneration) async {
    if (!mounted) {
      return;
    }
    if (_busy) {
      _noticeMessage('已有操作正在进行，请稍后重试。');
      return;
    }
    final api = _api, generation = _generation;
    if (api == null ||
        !identical(api, owner) ||
        generation != openedGeneration ||
        !_current(api, generation)) {
      _noticeMessage('本机接入信息已失效，请重新登录后打开。');
      _queueNoticeUpdate();
      return;
    }
    _noticeHint = '';
    _changeState(() => _busy = true);
    try {
      await (widget.onRetryLocal?.call(api, generation) ??
          _attachLocal(api, generation));
    } catch (_) {
      if (mounted && identical(_api, api) && _generation == generation) {
        _noticeMessage('本机接入未完成，请检查后重试。');
      }
    } finally {
      // 只复位本次操作拥有的忙状态；撤权已复位，新的登录代次由新操作负责。
      if (mounted && identical(_api, api) && _generation == generation) {
        _changeState(() => _busy = false);
      }
    }
  }

  String _noticeTitle(HomeDeskLocalAgent agent) => agent.error != null
      ? '本机接入未完成'
      : agent.agentState == 'Degraded' || agent.agentState == 'Error'
          ? '服务隧道待连接'
          : agent.isAttaching
              ? '正在接入本机…'
              : '本机已登记';
  Future<void> _showConnectionNotice() async {
    final api = _api, generation = _generation;
    if (api == null || !_current(api, generation) || _noticeRoute != null) {
      return;
    }
    _noticeOwner = api;
    _noticeGeneration = generation;
    _noticeHint = '';
    final navigator = Navigator.of(context);
    final route = DialogRoute<void>(
        context: context,
        builder: (dialogContext) =>
            StatefulBuilder(builder: (dialogContext, update) {
              _noticeUpdater = update;
              final agent = _localAgent ?? widget.localAgent;
              final valid = _noticeValid();
              final pending = agent?.agentState == 'Degraded' ||
                  agent?.agentState == 'Error';
              return AlertDialog(
                  title: Text(agent == null ? '本机接入信息' : _noticeTitle(agent)),
                  content: SingleChildScrollView(
                      child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(valid && agent != null
                            ? agent.description
                            : '当前账号或网络许可已变化，请重新登录。'),
                        if (pending)
                          const Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: Text(
                                  '请确认服务器的 FRPS 入站端口已开放。设备心跳在线仅代表管理连接可用。')),
                        if (_noticeHint.isNotEmpty)
                          Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(_noticeHint)),
                        if (agent?.error != null)
                          TextButton(
                              key: const ValueKey('tunnel-retry-local'),
                              onPressed: !valid || _busy
                                  ? null
                                  : () => _retryLocal(api, generation),
                              child: Text(_busy ? '正在接入…' : '重试本机接入')),
                      ])),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        child: const Text('关闭'))
                  ]);
            }));
    _noticeNavigator = navigator;
    _noticeRoute = route;
    try {
      // Flutter 3.24 的 removeRoute 不完成 push Future，completed 在实际销毁后完成。
      unawaited(navigator.push(route));
      await route.completed;
    } finally {
      if (identical(_noticeRoute, route)) {
        _noticeRoute = null;
        _noticeNavigator = null;
        _noticeUpdater = null;
        _noticeOwner = null;
        _noticeGeneration = null;
      }
    }
  }

  Widget _connectionNotice() {
    final agent = _localAgent ?? widget.localAgent;
    if (agent == null) {
      return const SizedBox.shrink();
    }
    final attention = agent.error != null ||
        agent.agentState == 'Degraded' ||
        agent.agentState == 'Error';
    return TextButton(
        key: const ValueKey('tunnel-connection-notice'),
        onPressed: _showConnectionNotice,
        child: HomeDeskBadge(_noticeTitle(agent),
            tone: attention
                ? HomeDeskTone.warning
                : agent.isAttaching
                    ? HomeDeskTone.neutral
                    : HomeDeskTone.success));
  }

  Widget _catalogToolbar(HomeTunnelCatalog? catalog) {
    final t = HomeDeskTokens.of(context);
    final heading =
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('内网穿透', style: t.titleStyle),
      const SizedBox(height: 4),
      Text(
          '${catalog?.devices.length ?? 0} 台设备 · ${catalog?.services.length ?? 0} 项服务',
          style: t.auxiliaryStyle)
    ]);
    final filter = catalog != null && catalog.devices.length > 1
        ? SizedBox(
            width: 184,
            height: HomeDeskTokens.buttonHeight *
                MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0),
            child: DropdownButtonFormField<String>(
                key: const ValueKey('tunnel-device-filter'),
                value: _deviceId,
                isExpanded: true,
                decoration: const InputDecoration(
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                items: [
                  const DropdownMenuItem(value: '', child: Text('全部设备')),
                  for (final device in catalog.devices)
                    DropdownMenuItem(
                        value: device.id,
                        child: Text(
                            device.name.isEmpty
                                ? '未命名设备'
                                : homeDeskDeviceLabel(device.name),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis))
                ],
                onChanged: (value) =>
                    _changeState(() => _deviceId = value ?? '')))
        : null;
    final add = catalog == null || catalog.devices.isEmpty
        ? null
        : FilledButton.icon(
            key: const ValueKey('tunnel-add-service'),
            onPressed: _busy
                ? null
                : () => _editService(
                    deviceId: _deviceId.isEmpty ? null : _deviceId),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('添加服务'));
    return LayoutBuilder(builder: (context, c) {
      final controls = Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [if (filter != null) filter, if (add != null) add]);
      if (c.maxWidth >= 620 &&
          MediaQuery.textScalerOf(context).scale(1) <= 1.5) {
        return Row(children: [
          Expanded(child: heading),
          const SizedBox(width: 12),
          controls
        ]);
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        heading,
        if (filter != null || add != null) ...[
          const SizedBox(height: 12),
          controls
        ]
      ]);
    });
  }

  Widget _catalogView() {
    final api = _api!, catalog = _catalog, groups = _groups();
    final t = HomeDeskTokens.of(context);
    return CustomScrollView(slivers: [
      SliverToBoxAdapter(
          child: Padding(
              padding: const EdgeInsets.only(
                  top: 24, bottom: HomeDeskTokens.moduleGap),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _catalogToolbar(catalog),
                    const SizedBox(height: 16),
                    _accountHeader(api),
                    const SizedBox(height: 16),
                    HomeDeskSegments(
                        labels: const ['全部', '网页', 'TCP 端口', 'UDP 端口'],
                        selected: _serviceType,
                        onSelected: (i) => setState(() => _serviceType = i),
                        keyPrefix: 'service-type'),
                    if (catalog != null &&
                        !catalog.capabilities.tcpCanCreate &&
                        !catalog.capabilities.udpCanCreate)
                      Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text('TCP / UDP 新建能力尚未由服务端开放，当前可添加网页服务。',
                              style: t.auxiliaryStyle)),
                    if (_message.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _messageBox()
                    ],
                    if (_busy || _entityBusy.isNotEmpty)
                      const Padding(
                          padding: EdgeInsets.only(top: 12),
                          child: LinearProgressIndicator()),
                    if (catalog != null && groups.isEmpty)
                      Padding(
                          padding: const EdgeInsets.only(top: 20),
                          child: Text(
                              '当前账号尚无接入设备。登录后会自动接入本机；其他设备使用自己的账号登录。默认不发布服务。',
                              style: t.auxiliaryStyle)),
                  ]))),
      SliverList(
          delegate: SliverChildBuilderDelegate(
              (context, i) => _groupCard(groups[i]),
              childCount: groups.length)),
      SliverToBoxAdapter(
          child:
              Text('内网穿透用于网页和端口转发。远程桌面请使用设备 ID 连接。', style: t.auxiliaryStyle)),
      const SliverToBoxAdapter(child: SizedBox(height: 24)),
    ]);
  }

  Widget _loginForm() => _loginFormContent();

  @override
  Widget build(BuildContext context) =>
      _api?.isSignedIn == true && _allowed ? _catalogView() : _loginForm();
}

class _ServiceGroup {
  final String id;
  final String name;
  final bool? online;
  final HomeTunnelDevice? device;
  final List<HomeTunnelService> services = [];
  _ServiceGroup(this.id, this.name, this.online, {this.device});
}
