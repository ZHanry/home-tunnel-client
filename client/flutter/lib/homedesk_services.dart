// HOMEDESK: 桌面服务门户独立于 RustDesk 会话与家庭 Console。
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'homedesk_credentials.dart';
import 'homedesk_theme.dart';
import 'homedesk_account.dart';
import 'homedesk_dashboard.dart';
import 'homedesk_device_label.dart';
import 'homedesk_local_agent.dart';
import 'homedesk_service_editor.dart';
import 'homedesk_tunnel_api.dart';
import 'homedesk_tunnel_session.dart';
import 'nestlink_native_session.dart';
import 'nestlink_locale.dart';
import 'nestlink_error_messages.dart';
import 'nestlink_login.dart';
import 'nestlink_dialog.dart';
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
        widget.account!.publish(api, _catalog, _localDeviceId, _editDevice,
            onSignOut: () => _signOut(api),
            onManageServices: (device) =>
                _manageDeviceServices(api, generation, device),
            onDelete: (device) => _deleteDevice(api, generation, device),
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
  late final _originFocus = FocusNode(onKeyEvent: _loginFieldKey);
  late final _usernameFocus = FocusNode(onKeyEvent: _loginFieldKey);
  late final _passwordFocus = FocusNode(onKeyEvent: _loginFieldKey);

  KeyEventResult _loginFieldKey(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (event is KeyDownEvent) unawaited(_login());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.tab) {
      if (event is KeyDownEvent) {
        if (HardwareKeyboard.instance.isShiftPressed) {
          node.previousFocus();
        } else {
          node.nextFocus();
        }
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

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
  final Set<String> _revokedDevices = {};
  bool _localDeviceRevoked = false;
  String? _draftOwner;
  bool _obscurePassword = true;
  bool _allowed = false;
  bool _busy = false;
  String _message = '';
  String _deviceId = '';
  int _serviceType = 0; // 仅影响当前目录的显示筛选。
  String? _apiPermission;
  int _generation = 0;
  int _ticks = 0;

  String get _localDeviceId {
    final guiId = _api?.guiDeviceId ?? '';
    final agentId = (_localAgent ?? widget.localAgent)?.deviceId ?? '';
    final devices = _catalog?.devices ?? const <HomeTunnelDevice>[];
    for (final device in devices) {
      if (guiId.isNotEmpty &&
          (device.id == guiId || device.remoteDeviceId == guiId)) {
        return device.id;
      }
    }
    for (final device in devices) {
      if (agentId.isNotEmpty &&
          (device.id == agentId || device.tunnelDeviceId == agentId)) {
        return device.id;
      }
    }
    return guiId.isNotEmpty ? guiId : agentId;
  }

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
    _entityBusy.clear();
    _clearSecrets();
    _origin.text = _approvedOrigin() ?? '';
    _message = nl('管理台授权地址已变化，请确认地址后重新登录。',
        'The authorized server address changed. Confirm the address and sign in again.');
  }

  Future<void> _revokeApi(HomeTunnelApi api, int generation) async {
    try {
      await api.revoke();
    } catch (_) {
      if (mounted && generation == _generation) {
        _changeState(() => _message = nl('网络会话已关闭，但无法确认清除该会话保存的登录。请检查本机安全存储。',
            'The network session was closed, but erasing its saved login could not be confirmed. Check secure storage on this device.'));
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
          _changeState(() => _message = nl('保存的账号与本机批准地址不一致，未恢复登录。请手动登录。',
              'The saved account does not match the approved address. Sign in manually.'));
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
        _message = nl('正在恢复记住的登录…', 'Restoring saved login…');
      });
      final restored = await api.restore();
      if (!_current(api, generation)) return;
      if (!restored) {
        _changeState(() {
          _message = nl('没有可以恢复的登录，请重新输入密码。',
              'No saved login is available. Enter your password again.');
        });
        return;
      }
      final catalog = await api.catalog();
      if (!_current(api, generation)) return;
      _changeState(() {
        _applyCatalog(catalog);
        _message = nl('已恢复记住的登录。', 'Saved login restored.');
      });
      await _attachLocal(api, generation);
    } catch (error) {
      if (!mounted || generation != _generation) return;
      api?.close();
      _api = null;
      _apiPermission = null;
      if (mounted && generation == _generation) {
        _changeState(() {
          _message = nl('保存的登录未能恢复，请重新登录。${_errorMessage(error)}',
              'Saved login could not be restored. Sign in again. ${_errorMessage(error)}');
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
      _changeState(() =>
          _message = nl('请输入账号和密码。', 'Enter your username and password.'));
      return;
    }
    String origin;
    try {
      origin = homeTunnelOrigin(_origin.text.trim());
    } catch (_) {
      _changeState(() => _message = nl('请输入有效的 HTTPS 服务端地址，不包含路径或账号信息。',
          'Enter a valid HTTPS server address without a path or account information.'));
      return;
    }
    _selectDraftOwner(origin, _username.text.trim());
    _revokedDevices.clear();
    _localDeviceRevoked = false;
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
        throw HomeTunnelApiException(
            nl('本机尚未确认这个服务端地址，请重新核对网络设置。',
                'This device has not approved the server address. Review your network settings.'),
            'ORIGIN_NOT_APPROVED');
      }
      final permission = _readPermission();
      if (permission.isEmpty) {
        throw HomeTunnelApiException(
            nl('网络许可尚未确认，请稍后重新登录。',
                'Network authorization is not confirmed. Try signing in again later.'),
            'PERMISSION_CHANGED');
      }
      api = _createApi(permission: permission, origin: origin);
      _api = api;
      _apiPermission = permission;
      _origin.text = origin;
      await api.login(
          username: _username.text.trim(),
          password: _password.text,
          rememberLogin: _credentialStore.supported);
      if (!_current(api, generation)) return;
      _changeState(_clearSecrets);
      final catalog = await api.catalog();
      if (!_current(api, generation)) return;
      _changeState(() => _applyCatalog(catalog));
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

  String _errorMessage(Object error) => nestlinkErrorMessage(error);

  Future<void> _attachLocal(HomeTunnelApi api, int generation) async {
    if (_localDeviceRevoked) return;
    if (widget.apiBuilder == null &&
        widget.readOption == null &&
        _current(api, generation)) {
      if (_nativeSession == null) {
        final native = NestLinkNativeSession(api);
        _nativeSession = native;
        api.onSessionClosed = () {
          native.close();
          if (identical(_nativeSession, native)) _nativeSession = null;
        };
        try {
          await native.start();
        } catch (_) {
          _message = nl('设备登记未完成，请稍后重试。',
              'Device registration did not finish. Try again later.');
        }
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
    final attachingAgent = _localAgent!;
    try {
      var catalog = await attachingAgent.attach(api, _catalog!);
      if (_current(api, generation) && api.guiDeviceId.isNotEmpty) {
        catalog = await api.associateLocalDevice(attachingAgent.deviceId);
      }
      if (_current(api, generation) && mounted) {
        _changeState(() => _applyCatalog(catalog));
      }
    } on HomeDeskAgentException catch (_) {
      if (mounted && _current(api, generation)) _changeState(() {});
    } on HomeTunnelApiException catch (error) {
      if (mounted && _current(api, generation)) {
        _changeState(() => _message = _errorMessage(error));
      }
    } catch (_) {
      if (_current(api, generation) && identical(_localAgent, attachingAgent)) {
        attachingAgent.error = const HomeDeskAgentException('RUNTIME_FAILED');
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
    final devices = catalog.devices
        .where((device) => !_revokedDevices.contains(device.id))
        .toList();
    final ids = devices.map((device) => device.id).toSet();
    final services = catalog.services
        .where((service) => ids.contains(service.deviceId))
        .toList();
    if (devices.length != catalog.devices.length ||
        services.length != catalog.services.length) {
      catalog = HomeTunnelCatalog(
          devices: devices,
          services: services,
          capabilities: catalog.capabilities);
    }
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
      var catalog = await api.catalog();
      final agent = _localAgent;
      if (_current(api, generation) &&
          agent?.phase == 'running' &&
          api.guiDeviceId.isNotEmpty &&
          !catalog.devices.any((device) =>
              device.id == api.guiDeviceId &&
              device.tunnelDeviceId == agent!.deviceId)) {
        catalog = await api.associateLocalDevice(agent!.deviceId);
      }
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
        }
      });
    } finally {
      if (mounted && identical(_api, api) && _generation == generation) {
        _changeState(() => _busy = false);
      }
    }
  }

  Future<void> _signOut(HomeTunnelApi api) async {
    if (!identical(api, _api)) return;
    final localAgent = _localAgent ?? widget.localAgent;
    _localAgent = null;
    _changeState(() {
      _generation++;
      _api = null;
      _apiPermission = null;
      _catalog = null;
      _deviceId = '';
      _busy = true;
      _entityBusy.clear();
      _serviceDrafts.clear();
      _deviceDrafts.clear();
      _needsReview.clear();
      _revokedDevices.clear();
      _localDeviceRevoked = false;
      _draftOwner = null;
      _clearSecrets();
      _message = '';
    });
    final generation = _generation;
    try {
      try {
        if (localAgent != null) await localAgent.stop();
      } catch (_) {
        // Logging out must still clear the account if stopping the runtime fails.
      }
      Object? logoutError;
      try {
        await api.logout();
      } catch (error) {
        logoutError = error;
      }
      // The shared account action owns the entire local session, including
      // startup restoration. Keep sign-in disabled until this erase finishes.
      try {
        await _credentialStore.clear();
      } catch (_) {
        if (mounted && generation == _generation) {
          _changeState(() => _message = nl('本次会话已关闭，但无法确认清除保存的登录。请检查本机安全存储后再试。',
              'The session was closed, but erasing the saved login could not be confirmed. Check secure storage on this device and retry.'));
        }
        return;
      }
      if (logoutError != null &&
          !(logoutError is HomeTunnelApiException &&
              logoutError.code == 'SECURE_STORE_ERROR') &&
          logoutError is! HomeDeskCredentialException &&
          mounted &&
          generation == _generation) {
        _changeState(() => _message = nl('已退出本机登录，但服务端会话暂未能关闭。',
            'Signed out on this device, but the server session could not be closed yet.'));
      }
    } finally {
      api.close();
      if (mounted && generation == _generation) {
        _changeState(() => _busy = false);
      }
    }
  }

  Future<void> _manageDeviceServices(
      HomeTunnelApi api, int generation, HomeTunnelDevice device) async {
    if (!_current(api, generation) ||
        _catalog == null ||
        !_catalog!.devices.any((entry) => entry.id == device.id)) {
      throw HomeTunnelApiException(
          nl('设备目录已变化，请刷新后重试。',
              'The device directory changed. Refresh it and retry.'),
          'DEVICE_NOT_FOUND');
    }
    _changeState(() {
      _deviceId = device.id;
      _serviceType = 0;
    });
    HomeDeskDashboard.navigate('services');
  }

  Future<void> _deleteDevice(
      HomeTunnelApi api, int generation, HomeTunnelDevice device) async {
    if (!_current(api, generation) ||
        _catalog == null ||
        !_catalog!.devices.any((entry) => entry.id == device.id)) {
      throw HomeTunnelApiException(
          nl('设备目录已变化，请刷新后重试。',
              'The device directory changed. Refresh it and retry.'),
          'DEVICE_NOT_FOUND');
    }
    await _operate(device.id, api, generation, () async {
      await api.deleteDevice(device.id);
      if (!_current(api, generation)) return;
      _deviceDrafts.remove(device.id);
      for (final service
          in _catalog!.services.where((entry) => entry.deviceId == device.id)) {
        _serviceDrafts.remove(service.id);
        _needsReview.remove(service.id);
      }
      _changeState(() {
        _revokedDevices.add(device.id);
        _needsReview.remove(device.id);
        _applyCatalog(_catalog!);
      });
      final agent = _localAgent ?? widget.localAgent;
      if (agent?.deviceId == device.id || api.guiDeviceId == device.id) {
        _localDeviceRevoked = true;
        _localAgent = null;
        try {
          await agent?.stop();
        } catch (_) {
          // A completed server revocation must not be replayed if runtime cleanup fails.
        }
        _nativeSession?.close();
        _nativeSession = null;
      }
      await _reloadAfterMutation(api, generation);
    });
  }

  Future<T> _operate<T>(String key, HomeTunnelApi api, int generation,
      Future<T> Function() action) async {
    if (_busy || _entityBusy.contains(key)) {
      throw HomeTunnelApiException(
          nl('这项操作正在进行，请稍候。', 'This operation is in progress. Please wait.'),
          'OPERATION_BUSY');
    }
    if (!_current(api, generation)) {
      throw HomeTunnelApiException(
          nl('网络许可已变化，请重新登录。', 'Network authorization changed. Sign in again.'),
          'PERMISSION_CHANGED');
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
          _message = nl('操作已完成。', 'Operation completed.');
        });
      }
    } catch (error) {
      if (_current(api, generation)) {
        _changeState(() {
          _message = nl('操作已完成，但列表暂未刷新。请刷新查看当前设置。',
              'The operation completed, but refreshing the list failed. Refresh to see the current settings.');
          if (!api.isSignedIn) {
            _catalog = null;
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
          ? nl('结果未确认，刷新核对后再操作，不会自动重试。',
              'The result is unknown. Refresh and review it before proceeding. This operation will not retry automatically.')
          : code.contains('VERSION_CONFLICT')
              ? nl('服务器上的设置已经变化，请刷新核对后再操作。',
                  'Server settings changed. Refresh and review them before proceeding.')
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
    final localId = _localDeviceId;
    final selected = deviceId ??
        service?.deviceId ??
        (catalog.devices.any((device) => device.id == localId)
            ? localId
            : catalog.devices.firstOrNull?.id);
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
                    throw HomeTunnelApiException(
                        nl('网络许可已变化，请重新登录。',
                            'Network authorization changed. Sign in again.'),
                        'PERMISSION_CHANGED');
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
                        summary: summary.isEmpty
                            ? nl('这台设备目前没有服务。', 'This device has no services.')
                            : summary);
                  }
                  final matches =
                      latest.services.where((item) => item.id == service.id);
                  return matches.isEmpty
                      ? HomeDeskServiceReview(
                          summary:
                              nl('服务已不存在。', 'The service no longer exists.'),
                          exists: false)
                      : HomeDeskServiceReview(
                          summary: _draftOf(matches.first).summary,
                          version: matches.first.version);
                }),
            onSave: (draft) => _operate(key, api, generation, () async {
                  _serviceDrafts[key] = draft;
                  try {
                    if (draft.serviceId == null &&
                        !_creatableTypes.contains(draft.proxyType)) {
                      throw HomeTunnelApiException(
                          nl('服务端暂不允许创建这种连接，请刷新查看可用能力。',
                              'The server does not allow this connection type currently. Refresh to see available capabilities.'),
                          'CAPABILITY_DISABLED');
                    }
                    if (draft.proxyType == 'http') {
                      final available = await api.checkSubdomain(
                          draft.subdomain,
                          connectionId: draft.serviceId);
                      if (!available.available) {
                        throw HomeTunnelApiException(
                            nl('这个访问名称不可用。',
                                    'This public name is unavailable.') +
                                (available.suggestions.isEmpty
                                    ? ''
                                    : nl(
                                        '可尝试：${available.suggestions.join('、')}。',
                                        'Try: ${available.suggestions.join(', ')}.')),
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
                      throw HomeTunnelApiException(
                          nl('网络许可已变化，请重新登录。',
                              'Network authorization changed. Sign in again.'),
                          'PERMISSION_CHANGED');
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
        builder: (context) => NestLinkDialog(
                title: Text(nl('删除服务？', 'Delete service?')),
                content: Text(nl('删除“${service.name}”后，其访问地址将停止工作。可以随后重新创建服务。',
                    'Deleting “${service.name}” will stop its public address from working. You can create the service again later.')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text(nl('取消', 'Cancel'))),
                  FilledButton(
                      key: ValueKey('confirm-delete-${service.id}'),
                      onPressed: () => Navigator.pop(context, true),
                      child: Text(nl('删除', 'Delete'))),
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
                    throw HomeTunnelApiException(
                        nl('网络许可已变化，请重新登录。',
                            'Network authorization changed. Sign in again.'),
                        'PERMISSION_CHANGED');
                  }
                  _changeState(() => _applyCatalog(latest));
                  final matches =
                      latest.devices.where((item) => item.id == device.id);
                  if (matches.isEmpty) {
                    throw HomeTunnelApiException(
                        nl('这台设备已不在账号中，不能覆盖保存。',
                            'This device is no longer in the account and cannot be overwritten.'),
                        'NOT_FOUND');
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
                      throw HomeTunnelApiException(
                          nl('网络许可已变化，请重新登录。',
                              'Network authorization changed. Sign in again.'),
                          'PERMISSION_CHANGED');
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
      _changeState(() => _message =
          nl('这个服务没有可打开的网页地址。', 'This service has no web address to open.'));
      return;
    }
    final generation = _generation;
    try {
      // 仅交给浏览器地址，不携带门户登录凭据，也不生成自动登录链接。
      final opened = await (widget.onOpenUrl?.call(uri) ??
          launchUrl(uri, mode: LaunchMode.externalApplication));
      if (!mounted || !_ensureAllowed() || generation != _generation) return;
      if (!opened) {
        _changeState(() => _message = nl('浏览器未能打开地址，请稍后重试。',
            'The browser could not open the address. Try again later.'));
      }
    } catch (_) {
      if (mounted && _ensureAllowed() && generation == _generation) {
        _changeState(() => _message = nl('浏览器未能打开地址，请稍后重试。',
            'The browser could not open the address. Try again later.'));
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
        _changeState(() => _message = nl('访问地址已复制。', 'Public address copied.'));
      }
    } catch (_) {
      if (mounted && _ensureAllowed() && generation == _generation) {
        _changeState(() => _message = nl('无法写入剪贴板，可以手动选择并复制访问地址。',
            'The clipboard is unavailable. Select and copy the public address manually.'));
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
    for (final node in [_originFocus, _usernameFocus, _passwordFocus]) {
      node.dispose();
    }
    super.dispose();
  }

  Widget _messageBox() {
    final colors = Theme.of(context).colorScheme;
    final informational =
        _message == nl('访问地址已复制。', 'Public address copied.') ||
            _message == nl('操作已完成。', 'Operation completed.') ||
            _message == nl('已恢复记住的登录。', 'Saved login restored.') ||
            _message.startsWith(nl('已退出本机登录', 'Signed out on this device'));
    return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(_message,
            style: TextStyle(
                color:
                    informational ? colors.onSurfaceVariant : colors.error)));
  }

  Widget _loginFormContent() {
    final t = HomeDeskTokens.of(context);
    return NestLinkLoginLayout(
        form: FocusTraversalGroup(
            policy: OrderedTraversalPolicy(),
            child: Column(
                key: const ValueKey('nestlink-login-form'),
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(nl('登录 NestLink', 'Sign in to NestLink'),
                      style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w600,
                          color: t.text)),
                  const SizedBox(height: 32),
                  if (!_allowed) ...[
                    Text(nl('请确认内网穿透的 HTTPS 地址和账号授权。同一台设备支持远程协助和内网穿透，登录一次即可使用。',
                        'Confirm your HTTPS server address and account authorization. One sign-in enables remote assistance and tunnels on the same device.')),
                    if (widget.onNetworkSettings != null)
                      Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                              onPressed: widget.onNetworkSettings,
                              icon: const Icon(Icons.tune_rounded),
                              label:
                                  Text(nl('打开网络设置', 'Open network settings')))),
                    const SizedBox(height: 12),
                  ],
                  HomeDeskFieldLabel(
                      nl('服务端 HTTPS 地址', 'HTTPS service address'),
                      child: FocusTraversalOrder(
                          order: const NumericFocusOrder(1),
                          child: TextField(
                              key: const ValueKey('tunnel-origin'),
                              controller: _origin,
                              focusNode: _originFocus,
                              autofocus: true,
                              enabled: !_busy && _allowed,
                              keyboardType: TextInputType.url,
                              textInputAction: TextInputAction.next,
                              autocorrect: false,
                              decoration: InputDecoration(
                                  prefixIcon:
                                      Icon(Icons.link_rounded, size: 20),
                                  hintText: 'https://console.example.com',
                                  border: null)))),
                  const SizedBox(height: 20),
                  HomeDeskFieldLabel(nl('账号', 'Account'),
                      child: FocusTraversalOrder(
                          order: const NumericFocusOrder(2),
                          child: TextField(
                              key: const ValueKey('tunnel-username'),
                              controller: _username,
                              focusNode: _usernameFocus,
                              enabled: !_busy && _allowed,
                              textInputAction: TextInputAction.next,
                              autocorrect: false,
                              decoration: InputDecoration(
                                  prefixIcon: const Icon(
                                      Icons.person_outline_rounded,
                                      size: 20),
                                  hintText: nl('请输入账号', 'Enter your account'),
                                  border: null)))),
                  const SizedBox(height: 20),
                  HomeDeskFieldLabel(nl('密码', 'Password'),
                      child: FocusTraversalOrder(
                          order: const NumericFocusOrder(3),
                          child: TextField(
                              key: const ValueKey('tunnel-password'),
                              controller: _password,
                              focusNode: _passwordFocus,
                              enabled: !_busy && _allowed,
                              obscureText: _obscurePassword,
                              enableSuggestions: false,
                              autocorrect: false,
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) => _login(),
                              decoration: InputDecoration(
                                  prefixIcon: const Icon(
                                      Icons.lock_outline_rounded,
                                      size: 20),
                                  hintText: nl('请输入密码', 'Enter your password'),
                                  suffixIcon: Focus(
                                      skipTraversal: true,
                                      descendantsAreTraversable: false,
                                      child: IconButton(
                                          tooltip: _obscurePassword
                                              ? nl('显示密码', 'Show password')
                                              : nl('隐藏密码', 'Hide password'),
                                          onPressed: _busy
                                              ? null
                                              : () => _changeState(() =>
                                                  _obscurePassword =
                                                      !_obscurePassword),
                                          icon: Icon(
                                              _obscurePassword
                                                  ? Icons
                                                      .visibility_off_outlined
                                                  : Icons.visibility_outlined,
                                              size: 20))),
                                  border: null)))),
                  const SizedBox(height: 28),
                  if (_message.isNotEmpty) _messageBox(),
                  FocusTraversalOrder(
                      order: const NumericFocusOrder(4),
                      child: FilledButton(
                          key: const ValueKey('tunnel-login'),
                          style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(46)),
                          onPressed: !_busy && _allowed ? _login : null,
                          child: Text(_busy
                              ? nl('正在登录…', 'Signing in…')
                              : nl('登录', 'Sign in')))),
                ])));
  }

  List<_ServiceGroup> _groups() {
    final catalog = _catalog;
    if (catalog == null) return [];
    final groups = <String, _ServiceGroup>{
      for (final device in catalog.devices)
        device.id: _ServiceGroup(
            device.id, homeDeskDeviceLabel(device.name), device.tunnelOnline,
            device: device)
    };
    for (final service in catalog.services) {
      groups[service.deviceId]?.services.add(service);
    }
    final visible = groups.values
        .where((group) => _deviceId.isEmpty || group.id == _deviceId)
        .toList();
    return visible;
  }

  String _status(HomeTunnelService service) {
    if (!service.enabled) return nl('已暂停', 'Paused');
    switch (service.status) {
      case 'Online':
        return nl('服务在线', 'Service online');
      case 'Pending':
        return nl('等待配置', 'Pending configuration');
      case 'Applying':
        return nl('正在配置', 'Applying configuration');
      case 'Degraded':
        return nl('连接异常', 'Connection degraded');
      case 'Offline':
        return nl('服务离线', 'Service offline');
      case 'Error':
        return nl('连接失败', 'Connection failed');
      case 'Disabled':
        return nl('已暂停', 'Paused');
      default:
        return nl('状态未知', 'Status unknown');
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
                  Text(
                      service.name.isEmpty
                          ? nl('未命名服务', 'Unnamed service')
                          : service.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.sectionStyle),
                  Text(
                      web
                          ? nl('网页服务', 'Web service')
                          : service.proxyType == 'tcp'
                              ? nl('TCP 端口', 'TCP port')
                              : service.proxyType == 'udp'
                                  ? nl('UDP 端口', 'UDP port')
                                  : nl('其他服务', 'Other service'),
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
            SelectableText(
                address ?? nl('访问地址尚未分配', 'Public address not assigned'),
                maxLines: 2,
                style: TextStyle(
                    color: t.accentText, fontSize: HomeDeskTokens.auxiliary)),
          const SizedBox(height: 8),
          Text(
              service.localHost.isEmpty || service.localPort == 0
                  ? nl('本地目标未返回', 'Local target unavailable')
                  : '${nl('本地', 'Local')}: ${web ? '${service.localScheme}://' : ''}${service.localHost}:${service.localPort}',
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
                      label: Text(nl('打开', 'Open')))
                else if (service.endpoint != null)
                  FilledButton(
                      onPressed:
                          _allowed ? () => _copy(service.endpoint!) : null,
                      child: Text(nl('复制地址', 'Copy address'))),
                if (address != null)
                  IconButton(
                      tooltip: nl('复制地址', 'Copy address'),
                      onPressed: _allowed ? () => _copy(address) : null,
                      icon: const Icon(Icons.copy_rounded, size: 18)),
                IconButton(
                    key: ValueKey('edit-service-${service.id}'),
                    tooltip: nl('编辑服务', 'Edit service'),
                    onPressed:
                        disabled ? null : () => _editService(service: service),
                    icon: const Icon(Icons.edit_outlined, size: 18)),
                PopupMenuButton<String>(
                    key: ValueKey('more-service-${service.id}'),
                    tooltip: nl('更多服务操作', 'More service actions'),
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
                              child: Text(service.enabled
                                  ? nl('暂停', 'Pause')
                                  : nl('恢复', 'Resume'))),
                          PopupMenuItem(
                              key: ValueKey('delete-service-${service.id}'),
                              value: 'delete',
                              enabled: !guarded,
                              child: Text(nl('删除', 'Delete'))),
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
    final local = _localDeviceId == group.id;
    final visible = group.services
        .where((service) => switch (_serviceType) {
              1 => service.proxyType == 'http' || service.proxyType == 'https',
              2 => service.proxyType == 'tcp',
              3 => service.proxyType == 'udp',
              _ => true,
            })
        .toList();
    return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Container(
            key: ValueKey('tunnel-device-${group.id}'),
            padding: const EdgeInsets.all(HomeDeskTokens.cardPadding),
            decoration: BoxDecoration(
                color: t.surface,
                border: Border.all(color: t.border),
                borderRadius: BorderRadius.circular(HomeDeskTokens.cardRadius)),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    Icon(Icons.dns_outlined, size: 22, color: t.accent),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Text(
                            group.name.isEmpty
                                ? nl('未命名设备', 'Unnamed device')
                                : group.name,
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.ellipsis,
                            style: t.sectionStyle)),
                    if (group.device != null)
                      IconButton(
                          key: ValueKey('edit-device-${group.id}'),
                          tooltip: nl('编辑标签', 'Edit tags'),
                          onPressed: _busy || _entityBusy.contains(group.id)
                              ? null
                              : () => _editDevice(group.device!),
                          icon: const Icon(Icons.tune_rounded, size: 18))
                  ]),
                  Wrap(spacing: 8, runSpacing: 6, children: [
                    if (local)
                      HomeDeskBadge(nl('本机', 'This device'),
                          tone: HomeDeskTone.accent),
                    HomeDeskBadge(
                        group.online == null
                            ? nl('心跳未知', 'Heartbeat unknown')
                            : group.online!
                                ? nl('设备心跳在线', 'Device heartbeat online')
                                : nl('设备心跳离线', 'Device heartbeat offline'),
                        tone: group.online == true
                            ? HomeDeskTone.success
                            : HomeDeskTone.neutral),
                    _badge(nl('${group.services.length} 项服务',
                        '${group.services.length} services')),
                    for (final tag in group.device?.tags ?? <String>[])
                      _badge(tag),
                  ]),
                  const SizedBox(height: 10),
                  if (visible.isEmpty)
                    Text(
                        group.services.isEmpty
                            ? nl('还没有发布服务', 'No services published')
                            : nl('当前类型下暂无服务', 'No services of this type'),
                        style: t.auxiliaryStyle)
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
      _noticeMessage(nl('已有操作正在进行，请稍后重试。',
          'An operation is already in progress. Try again later.'));
      return;
    }
    if (_localDeviceRevoked) {
      _noticeMessage(nl('本机设备已删除，请重新登录后再登记。',
          'This device was deleted. Sign in again to register it.'));
      return;
    }
    final api = _api, generation = _generation;
    if (api == null ||
        !identical(api, owner) ||
        generation != openedGeneration ||
        !_current(api, generation)) {
      _noticeMessage(nl('本机接入信息已失效，请重新登录后打开。',
          'Local registration details expired. Sign in again to open them.'));
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
        _noticeMessage(nl('本机接入未完成，请检查后重试。',
            'Local registration did not finish. Check it and retry.'));
      }
    } finally {
      // 只复位本次操作拥有的忙状态；撤权已复位，新的登录代次由新操作负责。
      if (mounted && identical(_api, api) && _generation == generation) {
        _changeState(() => _busy = false);
      }
    }
  }

  String _noticeTitle(HomeDeskLocalAgent agent) => agent.error != null
      ? nl('本机接入未完成', 'Local registration incomplete')
      : agent.agentState == 'Degraded' || agent.agentState == 'Error'
          ? nl('内网穿透待连接', 'Tunnel connection pending')
          : agent.isAttaching
              ? nl('正在接入本机…', 'Registering this device…')
              : nl('本机已登记', 'This device is registered');
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
              return NestLinkDialog(
                  title: Text(agent == null
                      ? nl('本机接入信息', 'Local registration details')
                      : _noticeTitle(agent)),
                  content: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(valid && agent != null
                            ? agent.description
                            : nl('当前账号或网络许可已变化，请重新登录。',
                                'The account or network authorization changed. Sign in again.')),
                        if (pending)
                          Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(nl(
                                  '请确认服务器的 FRPS 入站端口已开放。设备心跳在线仅代表管理连接可用。',
                                  'Confirm that the server allows inbound traffic to its FRPS port. An online device heartbeat only confirms the management connection.'))),
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
                              child: Text(_busy
                                  ? nl('正在接入…', 'Registering…')
                                  : nl('重试本机接入', 'Retry local registration'))),
                      ]),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        child: Text(nl('关闭', 'Close')))
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
    if (agent == null ||
        (agent.error == null &&
            agent.agentState != 'Degraded' &&
            agent.agentState != 'Error' &&
            (agent.isAttaching || agent.phase == 'running'))) {
      return const SizedBox.shrink();
    }
    final problem = agent.error?.message ?? agent.description;
    return SizedBox(
        width: 32,
        height: 32,
        child: IconButton(
            key: const ValueKey('tunnel-connection-notice'),
            tooltip: problem,
            padding: EdgeInsets.zero,
            color: Theme.of(context).colorScheme.error,
            onPressed: _showConnectionNotice,
            icon: const Icon(Icons.error_outline_rounded,
                key: ValueKey('tunnel-connection-warning'), size: 20)));
  }

  Widget _catalogToolbar(HomeTunnelCatalog? catalog) {
    final t = HomeDeskTokens.of(context);
    final controlHeight = homeDeskControlHeight(context);
    final dropdownTextHeight = MediaQuery.textScalerOf(context)
        .scale(Theme.of(context).textTheme.titleMedium?.fontSize ?? 16)
        .clamp(24.0, controlHeight);
    final heading = Row(mainAxisSize: MainAxisSize.min, children: [
      Flexible(child: Text(nl('内网穿透', 'Tunnels'), style: t.titleStyle)),
      _connectionNotice(),
    ]);
    final refresh = SizedBox.square(
        dimension: controlHeight,
        child: IconButton(
            key: const ValueKey('tunnel-refresh'),
            tooltip: _busy ? nl('正在刷新…', 'Refreshing…') : nl('刷新', 'Refresh'),
            onPressed: _busy ? null : _refresh,
            icon: _busy || _entityBusy.isNotEmpty
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh_rounded, size: 20)));
    final filter = catalog != null && catalog.devices.length > 1
        ? SizedBox(
            width: 184,
            height: controlHeight,
            child: DropdownButtonFormField<String>(
                key: const ValueKey('tunnel-device-filter'),
                value: _deviceId,
                isExpanded: true,
                decoration: InputDecoration(
                    contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: (controlHeight - dropdownTextHeight) / 2)),
                items: [
                  DropdownMenuItem(
                      value: '', child: Text(nl('全部设备', 'All devices'))),
                  for (final device in catalog.devices)
                    DropdownMenuItem(
                        value: device.id,
                        child: Text(
                            device.name.isEmpty
                                ? nl('未命名设备', 'Unnamed device')
                                : homeDeskDeviceLabel(device.name),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis))
                ],
                onChanged: (value) =>
                    _changeState(() => _deviceId = value ?? '')))
        : null;
    final add = catalog == null || catalog.devices.isEmpty
        ? null
        : SizedBox(
            height: controlHeight,
            child: FilledButton.icon(
                key: const ValueKey('tunnel-add-service'),
                onPressed: _busy
                    ? null
                    : () => _editService(
                        deviceId: _deviceId.isEmpty ? null : _deviceId),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(nl('添加服务', 'Add service'))));
    return LayoutBuilder(builder: (context, c) {
      final controls = Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [if (filter != null) filter, if (add != null) add]);
      if (c.maxWidth >= 560 &&
          MediaQuery.textScalerOf(context).scale(1) <= 1.5) {
        return Row(key: const ValueKey('tunnel-title-tools'), children: [
          Expanded(child: heading),
          const SizedBox(width: 12),
          controls,
          const SizedBox(width: 12),
          refresh,
        ]);
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(key: const ValueKey('tunnel-title-tools'), children: [
          Expanded(child: heading),
          refresh,
        ]),
        if (filter != null || add != null) ...[
          const SizedBox(height: 12),
          controls
        ]
      ]);
    });
  }

  Widget _catalogView() {
    final catalog = _catalog, groups = _groups();
    final t = HomeDeskTokens.of(context);
    return CustomScrollView(slivers: [
      SliverToBoxAdapter(
          child: Padding(
              padding: const EdgeInsets.only(top: 16, bottom: 16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _catalogToolbar(catalog),
                    const SizedBox(height: 16),
                    Wrap(
                        spacing: 16,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          HomeDeskSegments(
                              labels: [
                                nl('全部', 'All'),
                                nl('网页', 'Web'),
                                nl('TCP 端口', 'TCP port'),
                                nl('UDP 端口', 'UDP port')
                              ],
                              selected: _serviceType,
                              onSelected: (i) =>
                                  setState(() => _serviceType = i),
                              keyPrefix: 'service-type'),
                        ]),
                    if (_message.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _messageBox()
                    ],
                    if (catalog != null && groups.isEmpty)
                      Padding(
                          padding: const EdgeInsets.only(top: 20),
                          child: Text(
                              nl('当前账号尚无接入设备。登录后会自动接入本机；其他设备使用自己的账号登录。默认不发布服务。',
                                  'This account has no registered devices. Signing in registers this device; other devices use their own accounts. No services are published by default.'),
                              style: t.auxiliaryStyle)),
                  ]))),
      SliverList(
          delegate: SliverChildBuilderDelegate(
              (context, i) => _groupCard(groups[i]),
              childCount: groups.length)),
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
