// HOMEDESK: 家庭设备目录和服务共用批准的 HTTPS 地址；保存地址不发起联网。
import 'package:flutter/material.dart';
import 'homedesk_tunnel_api.dart';
import 'models/platform_model.dart';

class HomeDeskServiceAddress extends StatefulWidget {
  final String Function()? read;
  final Future<void> Function(String)? save;
  const HomeDeskServiceAddress({super.key, this.read, this.save});
  @override
  State<HomeDeskServiceAddress> createState() => _HomeDeskServiceAddressState();
}

class _HomeDeskServiceAddressState extends State<HomeDeskServiceAddress> {
  late final TextEditingController _address;
  bool _saving = false;
  String _message = '';
  bool _error = false;
  String _read() =>
      widget.read?.call() ??
      bind.mainGetLocalOption(key: 'homedesk-home-tunnel-origin');
  @override
  void initState() {
    super.initState();
    _address = TextEditingController(text: _read());
  }

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    String origin;
    try {
      origin = homeTunnelOrigin(_address.text.trim());
    } catch (_) {
      setState(() {
        _message = '请填写 HTTPS 地址，不包含路径、账号信息或查询参数。';
        _error = true;
      });
      return;
    }
    final changed = _read().trim() != origin;
    setState(() {
      _saving = true;
      _message = '';
      _error = false;
    });
    try {
      await (widget.save?.call(origin) ??
          bind.mainSetLocalOption(
              key: 'homedesk-home-tunnel-origin', value: origin));
      if (!mounted) return;
      if (homeTunnelOrigin(_read()) != origin) {
        throw const FormatException();
      }
      setState(() {
        _address.text = origin;
        _message = changed ? '地址已保存，请重新登录家庭账号。' : '地址已保存。';
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _message = '地址未能保存，请检查后重试。';
          _error = true;
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('家庭账号与服务',
                      style:
                          TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 10),
                  Text('家庭设备和家庭服务共用此地址。修改地址后需要重新登录；访问服务前请在网络模式中启用自建公网。',
                      style: TextStyle(
                          color: colors.onSurfaceVariant, fontSize: 12)),
                  const SizedBox(height: 16),
                  TextField(
                      key: const ValueKey('network-service-address'),
                      controller: _address,
                      enabled: !_saving,
                      autocorrect: false,
                      keyboardType: TextInputType.url,
                      decoration: const InputDecoration(
                          labelText: '家庭服务 HTTPS 地址',
                          hintText: 'https://console.example.com',
                          border: OutlineInputBorder())),
                  const SizedBox(height: 12),
                  Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.icon(
                          key: const ValueKey('network-save-service-address'),
                          onPressed: _saving ? null : _save,
                          icon: const Icon(Icons.save_outlined, size: 18),
                          label: Text(_saving ? '正在保存…' : '保存地址'))),
                  if (_message.isNotEmpty)
                    Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(_message,
                            style: TextStyle(
                                color: _error
                                    ? colors.error
                                    : colors.onSurfaceVariant))),
                ])));
  }
}
