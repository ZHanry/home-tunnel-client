// HOMEDESK: 高级模式状态独立于上游设置页，便于后续合并安全更新。
import 'package:get/get.dart';

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
  final address = octets.fold<int>(
      0, (result, octet) => (result << 8) | octet!);
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
