// HOMEDESK: 家庭设备和服务共享一个经过校验的账号会话，不保存或复制访问令牌。
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'homedesk_tunnel_api.dart';

class HomeDeskAccount extends ChangeNotifier {
  HomeTunnelApi? _api;
  HomeTunnelCatalog? _catalog;
  String _localDeviceId = '';
  Map<String, HomeDeskRemoteBinding> _bindings = {};
  bool _disposed = false;
  bool _loading = false;
  bool _queued = false;
  String _message = '';
  int _generation = 0;
  Timer? _timer;
  Future<void> Function(HomeTunnelDevice)? editDevice;
  void Function(HomeTunnelCatalog)? acceptCatalog;

  HomeTunnelApi? get api => _api;
  HomeTunnelCatalog? get catalog => signedIn ? _catalog : null;
  bool get signedIn => !_disposed && _api?.isSignedIn == true;
  String get displayName => _api?.displayName ?? '';
  String get localDeviceId => _localDeviceId;
  Map<String, HomeDeskRemoteBinding> get bindings =>
      signedIn ? Map.unmodifiable(_bindings) : const {};
  bool get loading => _loading;
  String get message => _message;

  void publish(HomeTunnelApi api, HomeTunnelCatalog? catalog,
      String localDeviceId, Future<void> Function(HomeTunnelDevice) onEdit,
      {void Function(HomeTunnelCatalog)? onCatalog}) {
    if (_disposed || !api.isSignedIn) return;
    final changed = !identical(_api, api);
    final catalogChanged = !identical(_catalog, catalog);
    final localChanged = _localDeviceId != localDeviceId;
    if (changed) {
      _generation++;
      _bindings = {};
      _message = '';
      _loading = false;
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 10), (_) => refresh());
    }
    _api = api;
    _catalog = catalog;
    _localDeviceId = localDeviceId;
    editDevice = onEdit;
    acceptCatalog = onCatalog;
    if (changed || catalogChanged || localChanged) {
      notifyListeners();
      _scheduleRefresh();
    }
  }

  void _scheduleRefresh() {
    if (_queued) return;
    _queued = true;
    scheduleMicrotask(() {
      _queued = false;
      if (!_disposed) refresh();
    });
  }

  void clear(HomeTunnelApi? owner) {
    if (_disposed || !identical(_api, owner)) return;
    _generation++;
    _timer?.cancel();
    _api = null;
    _catalog = null;
    _bindings = {};
    _localDeviceId = '';
    _message = '';
    _loading = false;
    editDevice = null;
    acceptCatalog = null;
    notifyListeners();
  }

  Future<void> refresh() async {
    final owner = _api;
    if (_disposed || _loading || owner == null) return;
    if (!owner.isSignedIn) {
      clear(owner);
      return;
    }
    final generation = _generation;
    _loading = true;
    notifyListeners();
    try {
      final latest = await owner.catalog();
      if (_disposed || generation != _generation || !identical(owner, _api)) {
        return;
      }
      _catalog = latest;
      acceptCatalog?.call(latest);
      final result = await owner.remoteBindings();
      if (_disposed || generation != _generation || !identical(owner, _api)) {
        return;
      }
      if (!owner.isSignedIn) {
        clear(owner);
        return;
      }
      final ids = _catalog?.devices.map((d) => d.id).toSet() ?? <String>{};
      _bindings = {
        for (final value in result)
          if (ids.contains(value.deviceId)) value.deviceId: value
      };
      _message = '';
    } catch (_) {
      if (!_disposed && generation == _generation && identical(owner, _api)) {
        if (!owner.isSignedIn) {
          clear(owner);
          return;
        }
        _message = '远控信息暂未同步，请稍后刷新。';
      }
    } finally {
      if (!_disposed && generation == _generation && identical(owner, _api)) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _timer?.cancel();
    _api = null;
    _catalog = null;
    _bindings = {};
    super.dispose();
  }
}
