// HOMEDESK: 桌面服务门户独立于 RustDesk 会话与家庭 Console。
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'homedesk_credentials.dart';
import 'homedesk_local_agent.dart';
import 'homedesk_service_editor.dart';
import 'homedesk_tunnel_api.dart';
import 'homedesk_tunnel_session.dart';
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

  const HomeDeskServices(
      {super.key,
      this.onNetworkSettings,
      this.readOption,
      this.apiBuilder,
      this.onOpenUrl,
      this.onCopy,
      this.saveOrigin,
      this.credentialStoreFactory});

  @override
  State<HomeDeskServices> createState() => _HomeDeskServicesState();
}

class _HomeDeskServicesState extends State<HomeDeskServices> {
  final _origin = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _mfa = TextEditingController();
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
  bool _needsMfa = false;
  String _message = '';
  String _deviceId = '';
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
    _mfa.clear();
    _needsMfa = false;
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
    _message = '网络配置或许可已变化，请确认自建公网模式后重新登录。';
  }

  Future<void> _revokeApi(HomeTunnelApi api, int generation) async {
    try {
      await api.revoke();
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _message = '网络会话已关闭，但无法确认清除该会话保存的登录。请检查本机安全存储。');
      }
    }
  }

  bool _ensureAllowed() {
    final allowed = _readAllowed();
    final changed = _api != null && _apiPermission != _readPermission();
    if (allowed != _allowed || changed) {
      if (mounted) {
        setState(() {
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
    setState(() => _busy = true);
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
          setState(() => _message = '保存的账号与本机批准地址不一致，未恢复登录。请手动登录。');
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
      setState(() {
        _rememberLogin = true;
        _message = '正在恢复记住的登录…';
      });
      final restored = await api.restore();
      if (!_current(api, generation)) return;
      if (!restored) {
        setState(() {
          _rememberLogin = false;
          _message = '没有可以恢复的登录，请重新输入密码。';
        });
        return;
      }
      final catalog = await api.catalog();
      if (!_current(api, generation)) return;
      setState(() {
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
        setState(() {
          _rememberLogin = false;
          _message = '保存的登录未能恢复，请重新登录。${_errorMessage(error)}';
        });
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _credentialStore = widget.credentialStoreFactory?.call() ??
        HomeDeskCredentialStore(
            applicationSupportDirectory: getApplicationSupportDirectory);
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
        if (mounted && before != _localAgent!.description) setState(() {});
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
      setState(() => _message = '请输入账号和密码。');
      return;
    }
    String origin;
    try {
      origin = homeTunnelOrigin(_origin.text.trim());
    } catch (_) {
      setState(() => _message = '请输入有效的 HTTPS 服务端地址，不包含路径或账号信息。');
      return;
    }
    _selectDraftOwner(origin, _username.text.trim());
    if (_localAgent != null) await _localAgent!.stop();
    _localAgent = null;
    _api?.close();
    _api = null;
    _apiPermission = null;
    final generation = ++_generation;
    HomeTunnelApi? api;
    setState(() {
      _busy = true;
      _message = '';
      _catalog = null;
      _deviceId = '';
    });
    try {
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
          mfaCode: _mfa.text.trim().isEmpty ? null : _mfa.text.trim(),
          rememberLogin: _rememberLogin && _credentialStore.supported);
      if (!_current(api, generation)) return;
      setState(_clearSecrets);
      final catalog = await api.catalog();
      if (!_current(api, generation)) return;
      setState(() => _catalog = catalog);
      await _attachLocal(api, generation);
    } catch (error) {
      if (!mounted || generation != _generation) return;
      if (api != null && !_current(api, generation)) return;
      setState(() {
        _message = _errorMessage(error);
        final code = error is HomeTunnelApiException ? error.code : '';
        _needsMfa = code == 'MFA_REQUIRED' || code == 'MFA_INVALID';
        _mfa.clear();
        if (!_needsMfa) _password.clear();
      });
    } finally {
      if (mounted && _generation == generation) {
        setState(() => _busy = false);
      }
    }
  }

  String _errorMessage(Object error) => error is HomeTunnelApiException
      ? error.message
      : error is HomeDeskCredentialException
          ? error.message
          : '服务暂时无法连接，请检查地址、证书和网络后重试。';

  Future<void> _attachLocal(HomeTunnelApi api, int generation) async {
    // 合成预览/组件注入保持无真实后台进程；生产仅在许可有效且身份已校验后接入。
    if (widget.apiBuilder != null ||
        widget.readOption != null ||
        !_current(api, generation) ||
        _catalog == null) return;
    if (!Platform.isWindows) return;
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
        setState(() => _catalog = catalog);
      }
    } on HomeDeskAgentException catch (_) {
      if (mounted && _current(api, generation)) setState(() {});
    } catch (_) {
      if (_localAgent != null) {
        _localAgent!.error = const HomeDeskAgentException('RUNTIME_FAILED');
        if (mounted) setState(() {});
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
    setState(() {
      _busy = true;
      _message = '';
    });
    try {
      final catalog = await api.catalog();
      if (!_current(api, generation)) return;
      setState(() {
        _applyCatalog(catalog);
      });
    } catch (error) {
      if (!_current(api, generation)) return;
      setState(() {
        _message = _errorMessage(error);
        if (!api.isSignedIn) {
          _catalog = null;
          _deviceId = '';
          _rememberLogin = false;
        }
      });
    } finally {
      if (mounted && identical(_api, api) && _generation == generation) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _logout() async {
    final api = _api;
    final localAgent = _localAgent;
    _localAgent = null;
    setState(() {
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
        setState(() => _message = '本次会话已关闭，但无法确认清除保存的登录。请检查本机安全存储后再试。');
      }
    } finally {
      api.close();
    }
  }

  Future<void> _forgetRemembered() async {
    final api = _api;
    if (api == null || _busy || !_ensureAllowed()) return;
    final generation = _generation;
    setState(() => _busy = true);
    try {
      await api.forgetRememberedLogin();
      if (_current(api, generation)) {
        setState(() {
          _rememberLogin = false;
          _message = '已取消记住登录。本次会话仍可继续使用。';
        });
      }
    } catch (error) {
      if (_current(api, generation)) {
        setState(() => _message = _errorMessage(error));
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
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
    setState(() => _entityBusy.add(key));
    try {
      return await action();
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _entityBusy.remove(key));
      }
    }
  }

  Future<void> _reloadAfterMutation(HomeTunnelApi api, int generation) async {
    try {
      final catalog = await api.catalog();
      if (_current(api, generation)) {
        setState(() {
          _applyCatalog(catalog);
          _message = '操作已完成。';
        });
      }
    } catch (error) {
      if (_current(api, generation)) {
        setState(() {
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
    setState(() {
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
                setState(() => _needsReview.remove(key));
              }
            },
            onReview: () => _operate(key, api, generation, () async {
                  final latest = await api.catalog();
                  if (!_current(api, generation)) {
                    throw const HomeTunnelApiException(
                        '网络许可已变化，请重新登录。', 'PERMISSION_CHANGED');
                  }
                  setState(() => _applyCatalog(latest));
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
                title: const Text('删除家庭服务？'),
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
                setState(() => _needsReview.remove(device.id));
              }
            },
            onReview: () => _operate(device.id, api, generation, () async {
                  final latest = await api.catalog();
                  if (!_current(api, generation)) {
                    throw const HomeTunnelApiException(
                        '网络许可已变化，请重新登录。', 'PERMISSION_CHANGED');
                  }
                  setState(() => _applyCatalog(latest));
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
      setState(() => _message = '这个服务没有可打开的网页地址。');
      return;
    }
    final generation = _generation;
    try {
      // 仅交给浏览器地址，不携带门户登录凭据，也不生成自动登录链接。
      final opened = await (widget.onOpenUrl?.call(uri) ??
          launchUrl(uri, mode: LaunchMode.externalApplication));
      if (!mounted || !_ensureAllowed() || generation != _generation) return;
      if (!opened) setState(() => _message = '浏览器未能打开地址，请稍后重试。');
    } catch (_) {
      if (mounted && _ensureAllowed() && generation == _generation) {
        setState(() => _message = '浏览器未能打开地址，请稍后重试。');
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
        setState(() => _message = '请先填写有效的 HTTPS 服务端地址。');
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
        setState(() => _message = '访问地址已复制。');
      }
    } catch (_) {
      if (mounted && _ensureAllowed() && generation == _generation) {
        setState(() => _message = '无法写入剪贴板，可以手动选择并复制访问地址。');
      }
    }
  }

  @override
  void dispose() {
    _generation++;
    _timer?.cancel();
    _api?.close();
    _clearSecrets();
    for (final controller in [_origin, _username, _password, _mfa]) {
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

  Widget _loginForm() => SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 24),
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
                            const Icon(Icons.home_work_outlined, size: 38),
                            const SizedBox(height: 14),
                            const Text('连接你的家庭服务',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    fontSize: 20, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 10),
                            const Text(
                                '使用 home-tunnel 账号查看设备上的服务。服务连接由各设备上的客户端提供。'),
                            const SizedBox(height: 20),
                            if (!_allowed) ...[
                              const Text('当前为纯内网模式或网络配置尚未确认，请先在网络设置中启用自建公网。'),
                              if (widget.onNetworkSettings != null)
                                Align(
                                    alignment: Alignment.centerLeft,
                                    child: TextButton.icon(
                                        onPressed: widget.onNetworkSettings,
                                        icon: const Icon(Icons.tune_rounded),
                                        label: const Text('打开网络设置'))),
                              const SizedBox(height: 12),
                            ],
                            TextField(
                                key: const ValueKey('tunnel-origin'),
                                controller: _origin,
                                enabled: !_busy && _allowed,
                                keyboardType: TextInputType.url,
                                autocorrect: false,
                                decoration: const InputDecoration(
                                    labelText: '服务端 HTTPS 地址',
                                    hintText: 'https://console.example.com',
                                    border: OutlineInputBorder())),
                            const SizedBox(height: 14),
                            TextField(
                                key: const ValueKey('tunnel-username'),
                                controller: _username,
                                enabled: !_busy && _allowed,
                                autocorrect: false,
                                decoration: const InputDecoration(
                                    labelText: '账号',
                                    border: OutlineInputBorder())),
                            const SizedBox(height: 14),
                            TextField(
                                key: const ValueKey('tunnel-password'),
                                controller: _password,
                                enabled: !_busy && _allowed,
                                obscureText: true,
                                enableSuggestions: false,
                                autocorrect: false,
                                onSubmitted: (_) => _login(),
                                decoration: const InputDecoration(
                                    labelText: '密码',
                                    border: OutlineInputBorder())),
                            if (_needsMfa) ...[
                              const SizedBox(height: 14),
                              TextField(
                                  key: const ValueKey('tunnel-mfa'),
                                  controller: _mfa,
                                  enabled: !_busy && _allowed,
                                  obscureText: true,
                                  enableSuggestions: false,
                                  autocorrect: false,
                                  onSubmitted: (_) => _login(),
                                  decoration: const InputDecoration(
                                      labelText: '动态码或恢复码',
                                      border: OutlineInputBorder())),
                            ],
                            const SizedBox(height: 16),
                            CheckboxListTile(
                                key: const ValueKey('tunnel-remember'),
                                contentPadding: EdgeInsets.zero,
                                title: const Text('记住登录'),
                                subtitle: Text(_credentialStore.supported
                                    ? '使用本机系统安全存储，下次进入家庭服务时恢复。'
                                    : '当前平台未启用安全存储，本次登录仅保留在内存中。'),
                                value: _rememberLogin,
                                onChanged: !_busy &&
                                        _allowed &&
                                        _credentialStore.supported
                                    ? (value) => setState(
                                        () => _rememberLogin = value ?? false)
                                    : null),
                            if (_message.isNotEmpty) _messageBox(),
                            FilledButton.icon(
                                key: const ValueKey('tunnel-login'),
                                onPressed: !_busy && _allowed ? _login : null,
                                icon: const Icon(Icons.login_rounded, size: 20),
                                label: Text(_busy ? '正在登录…' : '登录并查看')),
                            const SizedBox(height: 8),
                            TextButton(
                                onPressed:
                                    !_busy && _allowed ? _openManagement : null,
                                child: const Text('打开管理台')),
                            const SizedBox(height: 8),
                            const Text('密码和动态码不会保存。管理台会在浏览器中单独登录。',
                                style: TextStyle(fontSize: 12)),
                          ]))))));

  List<_ServiceGroup> _groups() {
    final catalog = _catalog;
    if (catalog == null) return [];
    final groups = <String, _ServiceGroup>{
      for (final device in catalog.devices)
        device.id:
            _ServiceGroup(device.id, device.name, device.online, device: device)
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
    final colors = Theme.of(context).colorScheme;
    final address = service.webUrl?.toString() ?? service.endpoint;
    return Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: colors.onSurface.withOpacity(0.025),
            border: Border.all(color: colors.outlineVariant),
            borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(
              spacing: 10,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(service.name.isEmpty ? '未命名服务' : service.name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 15)),
                _badge(service.proxyType.toUpperCase()),
                _badge(_status(service),
                    attention: service.enabled &&
                        (service.status == 'Error' ||
                            service.status == 'Degraded')),
              ]),
          const SizedBox(height: 6),
          SelectableText(address ?? '访问地址尚未分配',
              style: TextStyle(color: colors.onSurfaceVariant)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (service.webUrl != null)
              OutlinedButton.icon(
                  onPressed: _allowed ? () => _open(service.webUrl!) : null,
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: const Text('打开服务'))
            else if (service.endpoint != null)
              OutlinedButton.icon(
                  onPressed: _allowed ? () => _copy(service.endpoint!) : null,
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: const Text('复制访问地址')),
            TextButton.icon(
                key: ValueKey('edit-service-${service.id}'),
                onPressed: _busy || _entityBusy.contains(service.id)
                    ? null
                    : () => _editService(service: service),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('编辑')),
            TextButton(
                key: ValueKey('toggle-service-${service.id}'),
                onPressed: _busy ||
                        _entityBusy.contains(service.id) ||
                        _needsReview.contains(service.id)
                    ? null
                    : () => _toggleService(service),
                child: Text(service.enabled ? '暂停' : '恢复')),
            TextButton.icon(
                key: ValueKey('delete-service-${service.id}'),
                onPressed: _busy ||
                        _entityBusy.contains(service.id) ||
                        _needsReview.contains(service.id)
                    ? null
                    : () => _deleteService(service),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('删除')),
          ]),
          if (_entityBusy.contains(service.id)) const LinearProgressIndicator(),
        ]));
  }

  Widget _badge(String label, {bool attention = false}) {
    final colors = Theme.of(context).colorScheme;
    final color = attention ? colors.error : colors.onSurfaceVariant;
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
            color: color.withOpacity(0.09),
            borderRadius: BorderRadius.circular(7)),
        child: Text(label, style: TextStyle(color: color, fontSize: 12)));
  }

  Widget _groupCard(_ServiceGroup group) {
    final colors = Theme.of(context).colorScheme;
    final local = _localAgent?.deviceId == group.id;
    return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Card(
            child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                                padding: const EdgeInsets.only(top: 3),
                                child: Icon(Icons.dns_outlined,
                                    size: 22, color: colors.primary)),
                            const SizedBox(width: 12),
                            Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                  Text(
                                      group.name.isEmpty ? '未命名设备' : group.name,
                                      style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 8),
                                  Wrap(spacing: 8, runSpacing: 6, children: [
                                    if (local) _badge('本机'),
                                    _badge(group.online == null
                                        ? '心跳未知'
                                        : group.online!
                                            ? '设备心跳在线'
                                            : '设备心跳离线'),
                                    _badge('${group.services.length} 项服务'),
                                    if (group.device?.favorite == true)
                                      const Icon(Icons.star_rounded, size: 18),
                                  ]),
                                ])),
                            if (group.device != null)
                              IconButton(
                                  key: ValueKey('edit-device-${group.id}'),
                                  tooltip: '管理设备',
                                  onPressed:
                                      _busy || _entityBusy.contains(group.id)
                                          ? null
                                          : () => _editDevice(group.device!),
                                  icon:
                                      const Icon(Icons.tune_rounded, size: 20)),
                          ]),
                      if (group.device?.tags.isNotEmpty == true)
                        Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Wrap(spacing: 6, runSpacing: 6, children: [
                              for (final tag in group.device!.tags) _badge(tag),
                            ])),
                      if (group.services.isEmpty)
                        Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(top: 20),
                            padding: const EdgeInsets.symmetric(
                                vertical: 24, horizontal: 16),
                            decoration: BoxDecoration(
                                color: colors.onSurface.withOpacity(0.025),
                                borderRadius: BorderRadius.circular(12)),
                            child: Column(children: [
                              Icon(Icons.widgets_outlined,
                                  size: 30, color: colors.onSurfaceVariant),
                              const SizedBox(height: 10),
                              const Text('还没有发布服务',
                                  textAlign: TextAlign.center,
                                  style:
                                      TextStyle(fontWeight: FontWeight.w600)),
                              const SizedBox(height: 6),
                              Text('点击“添加服务”，选择要访问的网页或端口。',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      color: colors.onSurfaceVariant,
                                      fontSize: 12)),
                            ])),
                      for (final service in group.services)
                        _serviceTile(service),
                    ]))));
  }

  Widget _accountHeader(HomeTunnelApi api) {
    final colors = Theme.of(context).colorScheme;
    return Row(children: [
      CircleAvatar(
          radius: 20,
          backgroundColor: colors.primary.withOpacity(0.12),
          child: Icon(Icons.person_outline_rounded,
              color: colors.primary, size: 22)),
      const SizedBox(width: 12),
      Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(api.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 3),
        Text(api.base.host,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12)),
      ])),
      IconButton(
          key: const ValueKey('tunnel-refresh'),
          tooltip: _busy ? '正在刷新…' : '刷新',
          onPressed: _busy ? null : _refresh,
          icon: const Icon(Icons.refresh_rounded, size: 22)),
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
                const PopupMenuItem(value: 'logout', child: Text('退出登录')),
              ],
          icon: const Icon(Icons.more_horiz_rounded)),
    ]);
  }

  Widget _connectionNotice() {
    final agent = _localAgent;
    if (agent == null) return const SizedBox();
    final colors = Theme.of(context).colorScheme;
    final failed = agent.error != null;
    final pending =
        agent.agentState == 'Degraded' || agent.agentState == 'Error';
    final attention = failed || pending;
    final title = failed
        ? '本机接入未完成'
        : pending
            ? '服务隧道待连接'
            : agent.isAttaching
                ? '正在接入本机…'
                : '本机接入已启动';
    return Container(
        margin: const EdgeInsets.only(top: 16),
        decoration: BoxDecoration(
            color:
                (attention ? colors.error : colors.primary).withOpacity(0.06),
            border: Border.all(
                color: (attention ? colors.error : colors.primary)
                    .withOpacity(0.2)),
            borderRadius: BorderRadius.circular(12)),
        child: ExpansionTile(
            key: const ValueKey('tunnel-connection-notice'),
            shape: const Border(),
            collapsedShape: const Border(),
            leading: Icon(
                attention ? Icons.info_outline_rounded : Icons.link_rounded,
                color: attention ? colors.error : colors.primary,
                size: 22),
            title: Text(title,
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            subtitle: attention
                ? Text(
                    '账号已登录${agent.deviceId.isNotEmpty ? '，本机已登记' : ''}。展开查看连接说明。',
                    style:
                        TextStyle(color: colors.onSurfaceVariant, fontSize: 12))
                : null,
            children: [
              Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(agent.description,
                            style: TextStyle(color: colors.onSurfaceVariant)),
                        if (pending)
                          const Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: Text(
                                  '请确认服务器的 FRPS 入站端口已开放。设备心跳在线仅代表管理连接可用。',
                                  style: TextStyle(fontSize: 12))),
                        if (failed)
                          TextButton(
                              onPressed: _busy
                                  ? null
                                  : () async {
                                      setState(() => _busy = true);
                                      await _attachLocal(_api!, _generation);
                                      if (mounted) {
                                        setState(() => _busy = false);
                                      }
                                    },
                              child: const Text('重试本机接入')),
                      ])),
            ]));
  }

  Widget _catalogToolbar(HomeTunnelCatalog? catalog) =>
      LayoutBuilder(builder: (context, constraints) {
        final heading = Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text('我的服务',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              Text(
                  '${catalog?.devices.length ?? 0} 台设备 · ${catalog?.services.length ?? 0} 项服务',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12)),
            ]);
        if (catalog == null || catalog.devices.isEmpty) return heading;
        final add = FilledButton.icon(
            key: const ValueKey('tunnel-add-service'),
            onPressed: _busy
                ? null
                : () => _editService(
                    deviceId: _deviceId.isEmpty ? null : _deviceId),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('添加服务'));
        if (constraints.maxWidth >= 440 &&
            MediaQuery.textScalerOf(context).scale(14) <= 20) {
          return Row(children: [
            Expanded(child: heading),
            const SizedBox(width: 12),
            add
          ]);
        }
        return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [heading, const SizedBox(height: 12), add]);
      });

  Widget _catalogView() {
    final api = _api!;
    final catalog = _catalog;
    final groups = _groups();
    return Column(children: [
      _accountHeader(api),
      const SizedBox(height: 8),
      Expanded(
          child: CustomScrollView(slivers: [
        SliverToBoxAdapter(
            child: Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _connectionNotice(),
                      const SizedBox(height: 24),
                      _catalogToolbar(catalog),
                      if (catalog != null &&
                          !catalog.capabilities.tcpCanCreate &&
                          !catalog.capabilities.udpCanCreate)
                        const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Text('TCP / UDP 新建能力尚未由服务端开放，当前可添加网页服务。',
                                style: TextStyle(fontSize: 12))),
                      if (catalog != null && catalog.devices.length > 1) ...[
                        const SizedBox(height: 16),
                        ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 320),
                            child: DropdownButtonFormField<String>(
                                key: const ValueKey('tunnel-device-filter'),
                                value: _deviceId,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                    labelText: '查看设备',
                                    border: OutlineInputBorder()),
                                items: [
                                  const DropdownMenuItem(
                                      value: '', child: Text('全部设备')),
                                  for (final device in catalog.devices)
                                    DropdownMenuItem(
                                        value: device.id,
                                        child: Text(
                                            device.name.isEmpty
                                                ? '未命名设备'
                                                : device.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis)),
                                ],
                                onChanged: (value) =>
                                    setState(() => _deviceId = value ?? ''))),
                      ],
                      if (_message.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        _messageBox()
                      ],
                      if (_busy || _entityBusy.isNotEmpty)
                        const Padding(
                            padding: EdgeInsets.only(top: 12),
                            child: LinearProgressIndicator()),
                      if (catalog != null && groups.isEmpty)
                        const Padding(
                            padding: EdgeInsets.only(top: 20),
                            child: Text(
                                '当前账号尚无接入设备。登录后会自动接入本机；其他设备也可使用接入码登记。默认不发布服务。')),
                    ]))),
        SliverList(
            delegate: SliverChildBuilderDelegate(
                (context, index) => _groupCard(groups[index]),
                childCount: groups.length)),
        SliverToBoxAdapter(
            child: Text('家庭服务用于网页和端口转发。远程桌面请使用设备 ID 连接。',
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12))),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ])),
    ]);
  }

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
