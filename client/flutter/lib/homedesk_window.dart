// HOMEDESK: 只有主窗口使用托盘；原生添加图标成功后才隐藏窗口，失败则普通最小化。
import 'package:flutter/foundation.dart';
import 'dart:math' as math;
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import 'package:window_size/window_size.dart' as window_size;

const _channel = MethodChannel('org.rustdesk.rustdesk/host');

Size nestLinkWorkspaceSize(Size available) => Size(
    math.min(1120, math.max(1, available.width - 32)).toDouble(),
    math.min(760, math.max(1, available.height - 32)).toDouble());

/// Main workspace uses a fixed frame. Remote viewers retain their fullscreen controls.
Future<void> nestLinkFixWorkspaceWindow() async {
  var screen = (await window_size.getWindowInfo()).screen;
  if (screen == null) {
    final screens = await window_size.getScreenList();
    if (screens.isNotEmpty) screen = screens.first;
  }
  final scale = defaultTargetPlatform == TargetPlatform.windows
      ? (screen?.scaleFactor ?? 1.0)
      : 1.0;
  final size = screen == null
      ? const Size(1120, 760)
      : nestLinkWorkspaceSize(screen.visibleFrame.size / scale);
  if (await windowManager.isFullScreen()) await windowManager.setFullScreen(false);
  if (await windowManager.isMaximized()) await windowManager.unmaximize();
  await windowManager.setMaximizable(false);
  await windowManager.setResizable(false);
  await windowManager.setMinimumSize(size);
  await windowManager.setMaximumSize(size);
  await windowManager.setSize(size);
  if (screen == null) {
    await windowManager.center();
  } else {
    await windowManager.setPosition(
        screen.visibleFrame.center - Offset(size.width * scale / 2, size.height * scale / 2),
        ignoreDevicePixelRatio: defaultTargetPlatform == TargetPlatform.windows);
  }
}

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
