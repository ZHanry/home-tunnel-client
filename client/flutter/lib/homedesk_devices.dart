// HOMEDESK: 家庭设备墙独立于最近连接列表；管理台故障时保留手动连接。
import 'dart:async';
import 'package:flutter/material.dart';
import 'common.dart';
import 'homedesk_console_api.dart';
import 'models/platform_model.dart';

class HomeDeskDevices extends StatefulWidget {
  final HomeDeskConsoleApi? api;
  final HomeDeskConsoleApi Function(String url, String token,
      {bool Function()? isAllowed})? apiBuilder;
  final void Function(BuildContext, String)? onConnect;
  final VoidCallback? onManualConnect;
  final String Function(String)? readOption;
  const HomeDeskDevices(
      {Key? key,
      this.api,
      this.apiBuilder,
      this.onConnect,
      this.onManualConnect,
      this.readOption})
      : super(key: key);
  @override
  State<HomeDeskDevices> createState() => _HomeDeskDevicesState();
}

class _HomeDeskDevicesState extends State<HomeDeskDevices> {
  HomeDeskConsoleApi? _api;
  Timer? _timer;
  List<Map<String, dynamic>> _devices = [];
  final Set<String> _waking = {};
  bool _loading = false;
  String _message = '';
  String _room = '全部';
  String? _apiFingerprint;
  int _apiGeneration = 0;

  String _readOption(String key) => (widget.readOption ??
      (String key) => bind.mainGetLocalOption(key: key))(key);

  bool get _isConsoleAllowed {
    // 注入 API 保持既有预览和 widget 测试兼容；生产路径必须读取 Rust 的动态许可。
    if (widget.api != null && widget.readOption == null) return true;
    final allowed = _readOption('homedesk-console-allowed');
    return (widget.api != null && allowed.isEmpty) || allowed == 'Y';
  }

  void _revokeConsole() {
    _api?.close();
    _api = null;
    _apiFingerprint = null;
    _apiGeneration++;
    _devices = [];
    _waking.clear();
    _message = '设备中心当前不可达，可通过设备 ID 连接。';
  }

  bool _ensureConsole() {
    if (!_isConsoleAllowed) {
      if (_api != null || _devices.isNotEmpty || _message.isEmpty) {
        if (mounted) {
          setState(_revokeConsole);
        } else {
          _revokeConsole();
        }
      }
      return false;
    }
    if (widget.api != null) {
      if (_api == null) {
        _api = widget.api;
        _apiGeneration++;
      }
      return true;
    }
    try {
      final url = _readOption('homedesk-console-url');
      final token = _readOption('homedesk-console-token');
      final fingerprint = '$url\u0000$token';
      if (url.isEmpty) {
        if (_api != null) _revokeConsole();
        _message = '家庭设备服务尚未连接，你仍可通过设备 ID 连接。';
        return false;
      }
      if (_api != null && _apiFingerprint == fingerprint) return true;
      if (_api != null) {
        _api!.close();
        _api = null;
        _devices = [];
        _waking.clear();
        _apiGeneration++;
      }
      _api = widget.apiBuilder
              ?.call(url, token, isAllowed: () => _isConsoleAllowed) ??
          HomeDeskConsoleApi(url, token, isAllowed: () => _isConsoleAllowed);
      _apiFingerprint = fingerprint;
      _apiGeneration++;
      return true;
    } catch (_) {
      _message = '家庭设备服务配置有误，你仍可使用手动连接。';
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    try {
      _refresh();
      _timer = Timer.periodic(const Duration(seconds: 10), (_) => _refresh());
    } catch (_) {
      _message = '家庭设备服务配置有误，你仍可使用手动连接。';
    }
  }

  Future<void> _refresh() async {
    if (!_ensureConsole() || _api == null || _loading) return;
    final api = _api!;
    final generation = _apiGeneration;
    _loading = true;
    try {
      final result = await api.devices();
      if (!mounted ||
          !_ensureConsole() ||
          _api != api ||
          _apiGeneration != generation) return;
      setState(() {
        _devices = result;
        _waking.removeWhere(
            (id) => result.any((d) => d['id'] == id && d['online'] == true));
        _message = result.isEmpty ? '打开其他电脑上的客户端，接入家庭设备服务后，它们就会出现在这里。' : '';
      });
    } catch (_) {
      if (mounted &&
          _ensureConsole() &&
          _api == api &&
          _apiGeneration == generation) {
        setState(() {
          _message = '设备状态暂未更新，你仍可尝试连接或手动连接。';
        });
      }
    } finally {
      _loading = false;
      if (mounted && _api != api && _isConsoleAllowed) _refresh();
    }
  }

  Future<void> _wake(String id) async {
    if (!_ensureConsole() || _api == null || _waking.contains(id)) return;
    final api = _api!;
    final generation = _apiGeneration;
    setState(() => _waking.add(id));
    try {
      await api.wake(id);
      if (mounted &&
          _ensureConsole() &&
          _api == api &&
          _apiGeneration == generation) {
        setState(() => _message = '已发送唤醒，等待设备上线');
      }
    } catch (_) {
      if (mounted &&
          _ensureConsole() &&
          _api == api &&
          _apiGeneration == generation) {
        setState(() {
          _waking.remove(id);
          _message = '唤醒失败，请检查有线网卡配置';
        });
      }
    }
    // 离线设备未响应时允许重新尝试，避免按钮永久不可用。
    await Future<void>.delayed(const Duration(seconds: 30));
    if (mounted && _apiGeneration == generation) {
      setState(() => _waking.remove(id));
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _api?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final rooms = _devices.map(_roomOf).toSet().toList()..sort();
    final room = rooms.contains(_room) ? _room : '全部';
    final visible =
        _devices.where((d) => room == '全部' || _roomOf(d) == room).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
            child: Text(
                '${_devices.length} 台设备 · ${_devices.where((d) => d['online'] == true).length} 台在线',
                style:
                    TextStyle(fontSize: 13, color: colors.onSurfaceVariant))),
        IconButton(
            tooltip: '刷新设备',
            onPressed: _isConsoleAllowed ? _refresh : null,
            icon: const Icon(Icons.refresh_rounded, size: 20)),
      ]),
      if (rooms.isNotEmpty)
        Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ['全部', ...rooms]
                    .map(
                      (value) => ChoiceChip(
                          label: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 140),
                              child: Text(value,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis)),
                          selected: room == value,
                          onSelected: (_) => setState(() => _room = value)),
                    )
                    .toList())),
      if (_message.isNotEmpty && _devices.isNotEmpty)
        Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(_message,
                style:
                    TextStyle(color: colors.onSurfaceVariant, fontSize: 13))),
      Expanded(
          child: _devices.isEmpty
              ? _empty(context)
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final scale = MediaQuery.textScalerOf(context).scale(1);
                    final columns = scale > 1.4
                        ? 1
                        : (constraints.maxWidth / 300).floor().clamp(1, 3);
                    final tileWidth =
                        (constraints.maxWidth - 16 * (columns - 1)) / columns;
                    final stacked = tileWidth < 280;
                    return GridView.builder(
                        padding: const EdgeInsets.only(bottom: 8),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: columns,
                            crossAxisSpacing: 16,
                            mainAxisSpacing: 16,
                            mainAxisExtent: 260 +
                                (scale > 1 ? scale - 1 : 0) * 130 +
                                (stacked ? 52 : 0)),
                        itemCount: visible.length,
                        itemBuilder: (_, index) =>
                            _card(context, visible[index], stacked));
                  },
                )),
    ]);
  }

  String _roomOf(Map<String, dynamic> d) {
    final room = d['room']?.toString().trim() ?? '';
    return room.isEmpty ? '未分组' : room;
  }

  String _detailOf(Map<String, dynamic> d) {
    if (d['online'] != true) {
      final stamp = d['online_at'];
      if (stamp is! num || stamp <= 0) return '尚无上线记录';
      final at = DateTime.fromMillisecondsSinceEpoch(stamp.toInt() * 1000);
      final age = DateTime.now().difference(at);
      if (age.inMinutes < 1) return '最近在线：刚刚';
      if (age.inMinutes < 60) return '最近在线：${age.inMinutes} 分钟前';
      if (age.inHours < 24) return '最近在线：${age.inHours} 小时前';
      return '最近在线：${at.month} 月 ${at.day} 日';
    }
    final raw = d['platform']?.toString().toLowerCase() ?? '';
    final platform =
        {'windows': 'Windows', 'linux': 'Linux', 'macos': 'macOS'}[raw] ?? '电脑';
    final rawArch = d['arch']?.toString() ?? '';
    final arch = {
          'x86_64': 'x64',
          'amd64': 'x64',
          'aarch64': 'ARM64',
          'arm64': 'ARM64'
        }[rawArch] ??
        rawArch;
    return arch.isEmpty ? platform : '$platform · $arch';
  }

  Widget _empty(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
        child: SingleChildScrollView(
            child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: Card(
          child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(24)),
              child: Icon(Icons.devices_rounded,
                  size: 36, color: colors.onPrimaryContainer)),
          const SizedBox(height: 24),
          Text(_loading ? '正在查找家庭设备' : '从连接第一台电脑开始',
              textAlign: TextAlign.center,
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Text(_loading ? '正在获取最新设备状态…' : _message,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 14, height: 1.6, color: colors.onSurfaceVariant)),
          if (widget.onManualConnect != null) ...[
            const SizedBox(height: 24),
            FilledButton.icon(
                onPressed: widget.onManualConnect,
                icon: const Icon(Icons.add_rounded),
                label: const Text('手动连接'))
          ],
        ]),
      )),
    )));
  }

  Widget _card(BuildContext context, Map<String, dynamic> d, bool stacked) {
    final colors = Theme.of(context).colorScheme;
    final id = d['id'].toString();
    final online = d['online'] == true;
    final owner = d['owner']?.toString().trim() ?? '';
    final statusColor = online
        ? (colors.brightness == Brightness.dark
            ? const Color(0xFF6DE2B6)
            : const Color(0xFF127C60))
        : colors.onSurfaceVariant;
    void open() {
      if (widget.onConnect != null) {
        widget.onConnect!(context, id);
      } else {
        connect(context, id);
      }
    }

    final connectButton =
        OutlinedButton(onPressed: open, child: Text(online ? '连接设备' : '尝试连接'));
    final wakeButton = FilledButton(
        onPressed: _waking.contains(id) ? null : () => _wake(id),
        child: Text(_waking.contains(id) ? '等待上线' : '远程开机'));
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                          color: colors.primaryContainer.withOpacity(.55),
                          borderRadius: BorderRadius.circular(13)),
                      child: Icon(Icons.desktop_windows_rounded,
                          color: colors.primary, size: 23)),
                  const Spacer(),
                  Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 5),
                      decoration: BoxDecoration(
                          color: statusColor.withOpacity(.09),
                          borderRadius: BorderRadius.circular(20)),
                      child: Text(online ? '● 在线' : '○ 离线',
                          style: TextStyle(color: statusColor, fontSize: 12))),
                ]),
                const SizedBox(height: 14),
                Text(d['name']?.toString() ?? id,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w600)),
                const SizedBox(height: 7),
                Text('${_roomOf(d)}${owner.isEmpty ? '' : ' · $owner'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: colors.onSurfaceVariant, fontSize: 13)),
                const SizedBox(height: 7),
                Text(_detailOf(d),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: colors.onSurfaceVariant, fontSize: 12)),
                const Spacer(),
                if (!online && d['wol_configured'] == true)
                  stacked
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                              wakeButton,
                              const SizedBox(height: 8),
                              connectButton
                            ])
                      : Row(children: [
                          Expanded(child: connectButton),
                          const SizedBox(width: 8),
                          Expanded(child: wakeButton)
                        ])
                else
                  SizedBox(
                      width: double.infinity,
                      child: online
                          ? FilledButton(
                              onPressed: open, child: const Text('连接设备'))
                          : connectButton),
              ],
            )));
  }
}
