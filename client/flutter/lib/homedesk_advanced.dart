// HOMEDESK: 高级模式状态独立于上游设置页，便于后续合并安全更新。
import 'dart:convert';

import 'package:get/get.dart';
import 'package:flutter/material.dart';

import 'models/platform_model.dart';

const _advancedModeKey = 'homedesk-advanced-mode';
final RxBool homedeskAdvancedMode = false.obs;
bool _advancedModeLoaded = false;

void loadHomeDeskAdvancedMode() {
  if (_advancedModeLoaded) return;
  _advancedModeLoaded = true;
  homedeskAdvancedMode.value =
      bind.mainGetLocalOption(key: _advancedModeKey) == 'Y';
}

Future<void> unlockHomeDeskAdvancedMode() async {
  loadHomeDeskAdvancedMode();
  await bind.mainSetLocalOption(key: _advancedModeKey, value: 'Y');
  homedeskAdvancedMode.value = true;
}

bool isHomeDeskPrivateServer(String value) {
  final parts = value.trim().split(':');
  if (parts.length > 2 || parts.first.isEmpty) return false;
  if (parts.length == 2) {
    final port = int.tryParse(parts[1]);
    if (port == null || port < 1 || port > 65535) return false;
  }
  final octets = parts.first.split('.').map(int.tryParse).toList();
  if (octets.length != 4 ||
      octets.any((value) => value == null || value < 0 || value > 255)) {
    return false;
  }
  final first = octets[0]!;
  final second = octets[1]!;
  return first == 10 ||
      (first == 172 && second >= 16 && second <= 31) ||
      (first == 192 && second == 168);
}

bool isHomeDeskPrivateWhitelistEntry(String value) {
  final cidr = value.trim().split('/');
  if (cidr.length > 2 || cidr.first.isEmpty) return false;
  final octets = cidr.first.split('.').map(int.tryParse).toList();
  if (octets.length != 4 ||
      octets.any((value) => value == null || value < 0 || value > 255)) {
    return false;
  }
  final prefix = cidr.length == 2 ? int.tryParse(cidr[1]) : 32;
  if (prefix == null || prefix < 0 || prefix > 32) return false;
  final address =
      octets.fold<int>(0, (result, octet) => (result << 8) | octet!);
  final mask = prefix == 0 ? 0 : (0xffffffff << (32 - prefix)) & 0xffffffff;
  final network = address & mask;
  final broadcast = network | (~mask & 0xffffffff);

  int privateBlock(int rawAddress) {
    final first = (rawAddress >> 24) & 0xff;
    final second = (rawAddress >> 16) & 0xff;
    if (first == 10) return 10;
    if (first == 172 && second >= 16 && second <= 31) return 172;
    if (first == 192 && second == 168) return 192;
    return 0;
  }

  final block = privateBlock(network);
  return block != 0 && block == privateBlock(broadcast);
}

String validateHomeDeskNetworkDraft({
  required String mode,
  required String server,
  required String relay,
  required String key,
  required String familyCidr,
  required String sourceCidr,
}) {
  bool endpoint(String value) {
    final parts = value.trim().split(':');
    if (parts.length > 2 || parts.first.isEmpty) return false;
    if (parts.length == 2) {
      final port = int.tryParse(parts[1]);
      if (port == null || port < 1 || port > 65535) return false;
    }
    if (isHomeDeskPrivateServer(value)) return true;
    if (mode != 'self_hosted') return false;
    final host = parts.first;
    if (RegExp(r'^[0-9.]+$').hasMatch(host)) {
      final octets = host.split('.').map(int.tryParse).toList();
      if (octets.length != 4 ||
          octets.any((v) => v == null || v < 0 || v > 255)) return false;
      final first = octets.first!;
      final second = octets[1]!;
      return first != 0 &&
          first != 127 &&
          first < 224 &&
          !(first == 100 && second >= 64 && second <= 127) &&
          !(first == 169 && second == 254);
    }
    if (!host.contains('.')) return false;
    final labels = host.split('.');
    return labels.isNotEmpty &&
        !RegExp(r'^\d+$').hasMatch(labels.last) &&
        labels.every((label) =>
            RegExp(r'^[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?$')
                .hasMatch(label));
  }

  if (mode != 'lan_only' && mode != 'self_hosted') return '网络模式无效';
  if (!endpoint(server)) return 'ID 服务器不符合当前网络模式';
  if (!endpoint(relay)) return '中继服务器不符合当前网络模式';
  try {
    if (base64.decode(base64.normalize(key)).length != 32) return '服务器公钥格式无效';
  } catch (_) {
    return '服务器公钥格式无效';
  }
  final families =
      familyCidr.split(RegExp(r'[,;\s]+')).where((item) => item.isNotEmpty);
  if (families.isEmpty || !families.every(isHomeDeskPrivateWhitelistEntry)) {
    return '家庭 CIDR 无效';
  }
  if (sourceCidr.isNotEmpty) {
    final cidr = sourceCidr.split('/');
    final octets = cidr.first.split('.').map(int.tryParse).toList();
    final prefix = cidr.length == 2 ? int.tryParse(cidr[1]) : 32;
    if (cidr.length > 2 ||
        octets.length != 4 ||
        octets.any((v) => v == null || v < 0 || v > 255) ||
        prefix == null ||
        prefix < 1 ||
        prefix > 32) {
      return '公网来源限制无效';
    }
  }
  return '';
}

typedef HomeDeskNetworkSaver = Future<String> Function(
    String mode,
    String server,
    String relay,
    String key,
    String familyCidr,
    String sourceCidr);

// HOMEDESK: 双模式高级设置只提交完整原子组；Rust 再做同类校验并一次落盘。
Future<void> showHomeDeskNetworkSettings(BuildContext context,
    {String Function(String)? readOption,
    HomeDeskNetworkSaver? saveProfile}) async {
  final read = readOption ?? (String key) => bind.mainGetOptionSync(key: key);
  final save = saveProfile ??
      (mode, server, relay, key, familyCidr, sourceCidr) =>
          bind.mainSaveHomedeskNetworkProfile(
              mode: mode,
              server: server,
              relay: relay,
              key: key,
              familyCidr: familyCidr,
              sourceCidr: sourceCidr);
  var mode = read('homedesk-net-mode');
  if (mode != 'self_hosted') mode = 'lan_only';
  late TextEditingController server;
  late TextEditingController relay;
  late TextEditingController key;
  late TextEditingController familyCidr;
  late TextEditingController sourceCidr;
  final controllersToDispose = <TextEditingController>[];

  void loadProfile(String value) {
    String profile(String field) => read('homedesk-profile-$value-$field');
    server = TextEditingController(text: profile('server'));
    relay = TextEditingController(text: profile('relay'));
    key = TextEditingController(text: profile('key'));
    familyCidr = TextEditingController(text: profile('family-cidr'));
    sourceCidr = TextEditingController(text: profile('source-cidr'));
    controllersToDispose.addAll([server, relay, key, familyCidr, sourceCidr]);
  }

  loadProfile(mode);
  String error = '';
  bool saving = false;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(builder: (context, setState) {
      Widget field(String label, TextEditingController controller,
              {String? hint}) =>
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: TextField(
              controller: controller,
              enabled: !saving,
              decoration: InputDecoration(labelText: label, hintText: hint),
            ),
          );
      return AlertDialog(
        title: const Text('HomeDesk 网络模式'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<String>(
                value: mode,
                decoration: const InputDecoration(labelText: '模式'),
                items: const [
                  DropdownMenuItem(value: 'lan_only', child: Text('纯内网')),
                  DropdownMenuItem(value: 'self_hosted', child: Text('自建公网')),
                ],
                onChanged: saving
                    ? null
                    : (value) {
                        if (value == null || value == mode) return;
                        setState(() {
                          mode = value;
                          loadProfile(value);
                          error = '';
                        });
                      },
              ),
              field('ID 服务器', server,
                  hint: mode == 'lan_only'
                      ? '192.168.50.10:21116'
                      : 'remote.example.com:21116'),
              field('中继服务器', relay,
                  hint: mode == 'lan_only'
                      ? '192.168.50.10:21117'
                      : 'relay.example.com:21117'),
              field('服务器公钥', key),
              field('家庭 CIDR', familyCidr, hint: '192.168.50.0/24'),
              if (mode == 'self_hosted')
                field('公网来源限制（可选）', sourceCidr, hint: '203.0.113.0/24'),
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text('请先断开现有会话。保存后会重启连接服务；UDP/KCP、IPv6 和公共 STUN 尚未启用。'),
              ),
              if (error.isNotEmpty)
                Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child:
                        Text(error, style: const TextStyle(color: Colors.red))),
              if (saving)
                const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: LinearProgressIndicator()),
            ]),
          ),
        ),
        actions: [
          TextButton(
              onPressed:
                  saving ? null : () => Navigator.of(dialogContext).pop(),
              child: const Text('取消')),
          FilledButton(
            onPressed: saving
                ? null
                : () async {
                    final localError = validateHomeDeskNetworkDraft(
                      mode: mode,
                      server: server.text.trim(),
                      relay: relay.text.trim(),
                      key: key.text.trim(),
                      familyCidr: familyCidr.text.trim(),
                      sourceCidr:
                          mode == 'self_hosted' ? sourceCidr.text.trim() : '',
                    );
                    if (localError.isNotEmpty) {
                      setState(() => error = localError);
                      return;
                    }
                    setState(() {
                      saving = true;
                      error = '';
                    });
                    final result = await save(
                        mode,
                        server.text.trim(),
                        relay.text.trim(),
                        key.text.trim(),
                        familyCidr.text.trim(),
                        mode == 'self_hosted' ? sourceCidr.text.trim() : '');
                    if (result.isEmpty) {
                      Navigator.of(dialogContext).pop();
                    } else {
                      setState(() {
                        saving = false;
                        error = result;
                      });
                    }
                  },
            child: const Text('保存并重启服务'),
          ),
        ],
      );
    }),
  );
  for (final controller in controllersToDispose) {
    controller.dispose();
  }
}
