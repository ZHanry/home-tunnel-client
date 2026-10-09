// HOMEDESK: 高级模式状态独立于上游设置页，便于后续合并安全更新。
import 'dart:convert';

import 'package:get/get.dart';
import 'package:flutter/material.dart';

import 'models/platform_model.dart';
import 'homedesk_theme.dart';

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
  if (relay.isNotEmpty) return '远控固定 P2P，不能配置中继';
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

// Connection settings are issued by the authenticated self-hosted service.
Future<void> showHomeDeskNetworkSettings(BuildContext context,
    {String Function(String)? readOption,
    HomeDeskNetworkSaver? saveProfile}) async {
  final read = readOption ?? (String key) => bind.mainGetOptionSync(key: key);
  await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
            title: const Text('自建服务连接'),
            content: SizedBox(
                width: 480,
                child: SingleChildScrollView(
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      const Text('登录后自动获取远控服务配置。切换服务请先退出当前账号，再登录新的自建服务。'),
                      const SizedBox(height: 20),
                      const Text('信令服务器'),
                      SelectableText(read('custom-rendezvous-server')),
                      const SizedBox(height: 20),
                      const Text('远控策略：加密 P2P 直连；直连失败时结束。'),
                    ]))),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('关闭'))
            ],
          ));
}
