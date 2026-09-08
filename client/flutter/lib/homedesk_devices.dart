// HOMEDESK: 家庭设备墙独立于最近连接列表；管理台故障时保留手动连接。
import 'dart:async';
import 'package:flutter/material.dart';
import 'common.dart';
import 'homedesk_console_api.dart';
import 'models/platform_model.dart';

class HomeDeskDevices extends StatefulWidget {
  static double heightForTextScale(double scale) =>
      194.0 + (scale > 1 ? scale - 1 : 0.0) * 80.0;
  final HomeDeskConsoleApi? api;
  final void Function(BuildContext, String)? onConnect;
  const HomeDeskDevices({Key? key, this.api, this.onConnect}) : super(key: key);
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

  @override
  void initState() {
    super.initState();
    try {
      _api = widget.api;
      if (_api == null) {
        final url = bind.mainGetLocalOption(key: 'homedesk-console-url');
        if (url.isEmpty) return;
        _api = HomeDeskConsoleApi(
            url, bind.mainGetLocalOption(key: 'homedesk-console-token'));
      }
      _refresh();
      _timer = Timer.periodic(const Duration(seconds: 10), (_) => _refresh());
    } catch (_) {
      _message = '管理台配置无效，仍可使用下方设备 ID 连接';
    }
  }

  Future<void> _refresh() async {
    if (_loading || _api == null) return;
    _loading = true;
    try {
      final result = await _api!.devices();
      if (!mounted) return;
      setState(() {
        _devices = result;
        _waking.removeWhere(
            (id) => result.any((d) => d['id'] == id && d['online'] == true));
        _message = result.isEmpty ? '还没有设备，请启用被控端的管理台上报' : '';
      });
    } catch (_) {
      if (mounted) setState(() => _message = '管理台暂不可用，仍可使用下方设备 ID 连接');
    } finally {
      _loading = false;
    }
  }

  Future<void> _wake(String id) async {
    if (_api == null || _waking.contains(id)) return;
    setState(() => _waking.add(id));
    try {
      await _api!.wake(id);
      if (mounted) setState(() => _message = '已发送唤醒，等待设备上线');
    } catch (_) {
      if (mounted) {
        setState(() {
          _waking.remove(id);
          _message = '唤醒失败，请检查有线网卡配置';
        });
      }
    }
    // 离线设备未响应时允许重新尝试，避免按钮永久不可用。
    await Future<void>.delayed(const Duration(seconds: 30));
    if (mounted) setState(() => _waking.remove(id));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _api?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_api == null && _message.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('我的设备', style: TextStyle(fontWeight: FontWeight.bold)),
          const Spacer(),
          IconButton(
              tooltip: '刷新设备',
              onPressed: _refresh,
              icon: const Icon(Icons.refresh, size: 18)),
        ]),
        if (_message.isNotEmpty)
          Text(_message,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12)),
        if (_devices.isNotEmpty)
          Expanded(
              child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _devices.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final d = _devices[index], id = d['id'].toString();
              final online = d['online'] == true;
              final room = d['room']?.toString() ?? '';
              return SizedBox(
                  width: 210,
                  child: Card(
                      child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(d['name']?.toString() ?? id,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                          Text(
                              '${room.isEmpty ? '未分组' : room} · ${online ? '在线' : '离线'}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12)),
                          Row(children: [
                            TextButton(
                                onPressed: () {
                                  if (widget.onConnect != null) {
                                    widget.onConnect!(context, id);
                                  } else {
                                    connect(context, id);
                                  }
                                },
                                child: const Text('连接')),
                            if (!online && d['wol_configured'] == true)
                              TextButton(
                                  onPressed: _waking.contains(id)
                                      ? null
                                      : () => _wake(id),
                                  child: Text(
                                      _waking.contains(id) ? '等待上线' : '开机')),
                          ]),
                        ]),
                  )));
            },
          )),
      ]),
    );
  }
}
