// HOMEDESK: 主窗口保留拖动和系统按钮，窗口尺寸由工作台统一管理。
import 'package:flutter/material.dart';
import 'homedesk_theme.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'common.dart' show MyTheme;
import 'nestlink_locale.dart';
import 'nestlink_workspace.dart' show showNestLinkVersion;

class HomeDeskTitleBar extends StatelessWidget {
  final String brand;
  final bool inSettings, maximized, canMaximize;
  final VoidCallback onHome, onDrag, onMaximize, onMinimize, onClose;
  final VoidCallback? onTheme, onLanguage;
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
      this.onTheme,
      this.onLanguage,
      this.canMaximize = true});

  Widget _utility(BuildContext context, String key, String label, IconData icon,
          VoidCallback action) =>
      SizedBox(
          width: MediaQuery.sizeOf(context).width < 440 ? 28 : 36,
          height: 40,
          child: Tooltip(
              message: label,
              child: IconButton(
                  key: ValueKey(key),
                  onPressed: action,
                  padding: EdgeInsets.zero,
                  icon: Icon(icon, size: 18, semanticLabel: label),
                  color: HomeDeskTokens.of(context).secondary)));

  Widget _button(
      BuildContext context, String label, IconData icon, VoidCallback? action,
      {bool close = false}) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
        width: MediaQuery.sizeOf(context).width < 440 ? 36 : 44,
        height: 48,
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

  Widget _body(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final compact = MediaQuery.sizeOf(context).width < 440;
    return Container(
        height: 44,
        decoration: BoxDecoration(
            color: HomeDeskTokens.of(context).chrome,
            border: Border(bottom: BorderSide(color: colors.outlineVariant))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          const SizedBox(width: 10),
          SizedBox(
              width: compact ? 32 : 40,
              height: 40,
              child: Tooltip(
                  message: nl('返回主页', 'Home'),
                  child: IconButton(
                      onPressed: onHome,
                      padding: EdgeInsets.all(compact ? 6 : 10),
                      icon: SvgPicture.asset('assets/icon.svg',
                          width: 20, height: 20)))),
          const SizedBox(width: 4),
          Expanded(
              child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (_) => onDrag(),
                  onDoubleTap: canMaximize ? onMaximize : null,
                  child: SizedBox(
                      height: 40,
                      child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text.rich(
                              TextSpan(children: [
                                const TextSpan(text: 'NestLink'),
                                if (inSettings)
                                  TextSpan(
                                      text: nl('  /  设置', '  /  Settings'),
                                      style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                          letterSpacing: 0,
                                          color: HomeDeskTokens.of(context)
                                              .secondary)),
                              ]),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  height: 1,
                                  color: colors.onSurface)))))),
          _utility(
              context,
              'title-theme',
              nl('切换主题', 'Change theme'),
              Theme.of(context).brightness == Brightness.dark
                  ? Icons.light_mode_outlined
                  : Icons.dark_mode_outlined,
              onTheme ??
                  () => MyTheme.changeDarkMode(
                      Theme.of(context).brightness == Brightness.dark
                          ? ThemeMode.light
                          : ThemeMode.dark)),
          _utility(
              context,
              'title-language',
              nestlinkEnglish ? '简体中文' : 'English',
              Icons.language_outlined,
              onLanguage ??
                  () => setNestLinkLanguage(nestlinkEnglish ? 'zh-cn' : 'en')),
          _utility(context, 'title-version', nl('版本', 'Version'),
              Icons.info_outline_rounded, () => showNestLinkVersion(context)),
          Container(
              width: 1,
              height: 16,
              margin: const EdgeInsets.symmetric(horizontal: 8),
              color: colors.outlineVariant),
          _button(context, nl('最小化到系统托盘', 'Minimize to tray'),
              Icons.horizontal_rule_rounded, onMinimize),
          if (canMaximize)
            _button(
                context,
                maximized
                    ? nl('还原窗口', 'Restore window')
                    : nl('最大化窗口', 'Maximize window'),
                maximized
                    ? Icons.filter_none_rounded
                    : Icons.crop_square_rounded,
                canMaximize ? onMaximize : null),
          _button(
              context, nl('关闭窗口', 'Close window'), Icons.close_rounded, onClose,
              close: true),
        ]));
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<String>(
      valueListenable: nestlinkLanguage,
      builder: (context, _, __) => _body(context));
}
