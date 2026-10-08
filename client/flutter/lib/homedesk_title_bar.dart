// HOMEDESK: 主窗口标题栏保留拖动、缩放和系统按钮，取消重复的主页/设置页签。
import 'package:flutter/material.dart';
import 'homedesk_theme.dart';

class HomeDeskTitleBar extends StatelessWidget {
  final String brand;
  final bool inSettings, maximized, canMaximize;
  final VoidCallback onHome, onDrag, onMaximize, onMinimize, onClose;
  const HomeDeskTitleBar(
      {super.key,
      required this.brand,
      required this.inSettings,
      required this.maximized,
      required this.onHome,
      required this.onDrag,
      required this.onMaximize,
      required this.onMinimize,
      required this.onClose,
      this.canMaximize = true});

  Widget _button(
      BuildContext context, String label, IconData icon, VoidCallback? action,
      {bool close = false}) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
        width: 44,
        height: 44,
        child: Tooltip(
            message: label,
            child: TextButton(
                style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        foregroundColor: colors.onSurfaceVariant,
                        shape: const RoundedRectangleBorder())
                    .copyWith(
                        overlayColor: WidgetStatePropertyAll(close
                            ? colors.error.withOpacity(.24)
                            : colors.primary.withOpacity(.12))),
                onPressed: action,
                child: Icon(icon, size: 18, semanticLabel: label))));
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
        height: 44,
        decoration: BoxDecoration(
            color: HomeDeskTokens.of(context).chrome,
            border: Border(bottom: BorderSide(color: colors.outlineVariant))),
        child: Row(children: [
          _button(context, '返回主页', Icons.home_rounded, onHome),
          Expanded(
              child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (_) => onDrag(),
                  onDoubleTap: canMaximize ? onMaximize : null,
                  child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(inSettings ? '$brand  /  设置' : brand,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: colors.onSurface))))),
          _button(
              context, '最小化到系统托盘', Icons.horizontal_rule_rounded, onMinimize),
          _button(
              context,
              maximized ? '还原窗口' : '最大化窗口',
              maximized ? Icons.filter_none_rounded : Icons.crop_square_rounded,
              canMaximize ? onMaximize : null),
          _button(context, '关闭窗口', Icons.close_rounded, onClose, close: true),
        ]));
  }
}
