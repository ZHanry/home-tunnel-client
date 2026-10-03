// HOMEDESK: 只有主窗口使用托盘；原生添加图标成功后才隐藏窗口，失败则普通最小化。
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

const _channel = MethodChannel('org.rustdesk.rustdesk/host');

Future<void> homeDeskEnableTray() async {
  if (defaultTargetPlatform != TargetPlatform.windows) return;
  try {
    await _channel.invokeMethod<bool>('homedeskEnableTray');
  } catch (_) {}
}

Future<void> homeDeskMinimizeToTray() async {
  if (defaultTargetPlatform == TargetPlatform.windows) {
    try {
      if (await _channel.invokeMethod<bool>('homedeskMinimizeToTray') == true) {
        return;
      }
    } catch (_) {}
  }
  await windowManager.minimize();
}
