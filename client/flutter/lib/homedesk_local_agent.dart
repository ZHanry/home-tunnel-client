// HOMEDESK: 账号管理保持未绑定会话，本机登记与受管进程走独立原生通道。
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'homedesk_tunnel_api.dart';

class HomeDeskAgentException implements Exception {
  final String code;
  const HomeDeskAgentException(this.code);
  String get message => switch (code) {
    'RUNTIME_MISSING' => '程序包缺少本机接入组件，请使用包含 Agent 的完整包。',
    'INTEGRITY_FAILED' => '本机接入组件摘要不匹配，已拒绝启动。',
    'STATE_DAMAGED' => '本机设备状态损坏，已停止自动接入，请核对后恢复。',
    'ENROLLMENT_RESULT_UNKNOWN' => '本机登记结果未知，请先刷新网页设备列表核对，未自动重放。',
    'DEVICE_OUTSIDE_ACCOUNT' => '本机登记已撤销或不属于当前账号，未自动重新登记。',
    'PERMISSION_CHANGED' => '本机网络许可已变化，Agent 已停止。',
    'PLATFORM_UNSUPPORTED' => '当前平台尚未打包本机 Agent。',
    _ => '本机接入未完成，请核对服务器状态后重试。',
  };
}

class HomeDeskLocalAgent {
  final Future<void> Function(String) send;
  final String Function() read;
  final String Function() permission;
  final bool Function() isAllowed;
  final String name;
  static String _newOwner() => List.generate(16, (_) => Random.secure().nextInt(256))
      .map((value) => value.toRadixString(16).padLeft(2, '0')).join();
  String _owner = _newOwner();
  Map<String, dynamic> _view = {};
  String _origin = '';
  String _userId = '';
  String _permission = '';
  bool _attaching = false;
  bool _attached = false;
  HomeDeskAgentException? error;

  HomeDeskLocalAgent({required this.send, required this.read,
    required this.permission, required this.isAllowed, required this.name});

  String get deviceId => _view['device_id'] as String? ?? '';
  String get phase => _view['phase'] as String? ?? 'stopped';
  String get agentState => _view['agent_state'] as String? ?? '';
  bool get isAttaching => _attaching;

  bool _valid() => isAllowed() && _permission.isNotEmpty && permission() == _permission;
  void poll() {
    try {
      final next = jsonDecode(read());
      if (next is Map<String, dynamic> && next['owner'] == _owner) {
        _view = next;
        if (phase == 'error') {
          error = HomeDeskAgentException(_view['code'] as String? ?? 'RUNTIME_FAILED');
          _attached = false;
        }
      }
    } catch (_) { }
  }

  Future<Map<String, dynamic>> _command(String action, {String registration = ''}) async {
    if (!_valid()) throw const HomeDeskAgentException('PERMISSION_CHANGED');
    await send(jsonEncode({'action':action, 'owner':_owner, 'origin':_origin,
      'user_id':_userId, 'permission':_permission, 'name':name, 'registration':registration}));
    final deadline = DateTime.now().add(Duration(seconds: action == 'register' ? 55 : 15));
    while (DateTime.now().isBefore(deadline)) {
      if (!_valid()) throw const HomeDeskAgentException('PERMISSION_CHANGED');
      poll();
      if (_view['owner'] == _owner && phase != 'working' && phase != 'stopped') {
        if (phase == 'error') throw HomeDeskAgentException(_view['code'] as String? ?? 'RUNTIME_FAILED');
        return _view;
      }
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    throw HomeDeskAgentException(action == 'register' ? 'ENROLLMENT_RESULT_UNKNOWN' : 'RUNTIME_FAILED');
  }

  Future<HomeTunnelCatalog> attach(HomeTunnelApi api, HomeTunnelCatalog catalog) async {
    if (_attaching || _attached) return catalog;
    _attaching = true;
    _owner = _newOwner();
    _view = {};
    error = null;
    _origin = api.base.origin;
    _userId = api.userId;
    _permission = permission();
    try {
      final inspected = await _command('inspect');
      if (inspected['phase'] == 'registered') {
        if (!catalog.devices.any((device) => device.id == deviceId)) {
          throw const HomeDeskAgentException('DEVICE_OUTSIDE_ACCOUNT');
        }
      } else if (inspected['phase'] == 'needs_registration') {
        final registration = await api.registerBackgroundDevice(name, inspected['install_id'] as String, inspected['fingerprint_hash'] as String);
        await _command('register', registration: jsonEncode(registration));
        catalog = await api.catalog();
        if (!catalog.devices.any((device) => device.id == deviceId)) {
          throw const HomeDeskAgentException('DEVICE_OUTSIDE_ACCOUNT');
        }
      } else {
        throw const HomeDeskAgentException('RUNTIME_FAILED');
      }
      if (!_valid()) throw const HomeDeskAgentException('PERMISSION_CHANGED');
      await _command('run');
      _attached = true;
      return catalog;
    } on HomeDeskAgentException catch (failure) {
      error = failure;
      await stop();
      rethrow;
    } finally {
      _attaching = false;
    }
  }

  Future<void> stop() async {
    _attached = false;
    await send(jsonEncode({'action':'stop','owner':_owner}));
  }

  String get description {
    if (error != null) return error!.message;
    if (_attaching) return '正在自动接入本机…';
    if (phase == 'running') {
      if (agentState == 'Degraded' || agentState == 'Error') {
        return '本机已登记，隧道连接尚未就绪。请核对 FRPS 端口和服务器状态。';
      }
      return '这台电脑已加入设备列表，可在下方添加和管理服务。';
    }
    if (phase == 'error') return const HomeDeskAgentException('RUNTIME_FAILED').message;
    return '本机服务连接已停止。';
  }
}
