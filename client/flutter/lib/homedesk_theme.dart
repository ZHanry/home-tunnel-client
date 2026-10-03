// HOMEDESK: 首页、设置、会话与弹窗共用同一套颜色及控件样式。
import 'package:flutter/material.dart';

ThemeData homeDeskTheme(ThemeData base) {
  final dark = base.brightness == Brightness.dark;
  final colors = ColorScheme.fromSeed(
          seedColor: const Color(0xFF4C6FFF), brightness: base.brightness)
      .copyWith(
    surface: dark ? const Color(0xFF1B2230) : Colors.white,
    onSurface: dark ? const Color(0xFFE8EEF8) : const Color(0xFF202C40),
    onSurfaceVariant: dark ? const Color(0xFFA8B5CB) : const Color(0xFF65748C),
    outlineVariant: dark ? const Color(0xFF303B50) : const Color(0xFFE0E6F0),
  );
  final background = dark ? const Color(0xFF131923) : const Color(0xFFF4F6FB);
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(11));
  final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(11),
      borderSide: BorderSide(color: colors.outlineVariant));
  return base.copyWith(
    colorScheme: colors,
    primaryColor: colors.primary,
    scaffoldBackgroundColor: background,
    canvasColor: colors.surface,
    cardColor: colors.surface,
    dialogBackgroundColor: colors.surface,
    dividerColor: colors.outlineVariant,
    hoverColor: colors.primary.withOpacity(.09),
    textTheme: base.textTheme
        .apply(bodyColor: colors.onSurface, displayColor: colors.onSurface),
    cardTheme: CardTheme(
        color: colors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: colors.outlineVariant))),
    dialogTheme: DialogTheme(
        backgroundColor: colors.surface,
        elevation: 12,
        titleTextStyle: TextStyle(
            color: colors.onSurface, fontSize: 21, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: colors.outlineVariant))),
    elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
            backgroundColor: colors.primary,
            foregroundColor: colors.onPrimary,
            minimumSize: const Size(0, 40),
            elevation: 0,
            shape: shape)),
    filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
            backgroundColor: colors.primary,
            foregroundColor: colors.onPrimary,
            minimumSize: const Size(0, 40),
            shape: shape)),
    outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
            foregroundColor: colors.primary,
            minimumSize: const Size(0, 40),
            side: BorderSide(color: colors.outlineVariant),
            shape: shape)),
    textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
            foregroundColor: colors.primary,
            minimumSize: const Size(0, 40),
            shape: shape)),
    iconTheme: IconThemeData(color: colors.onSurfaceVariant, size: 20),
    inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: background,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        border: inputBorder,
        enabledBorder: inputBorder,
        focusedBorder: inputBorder.copyWith(
            borderSide: BorderSide(color: colors.primary, width: 1.5)),
        labelStyle: TextStyle(color: colors.onSurfaceVariant)),
    checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.disabled)
                ? colors.onSurface.withOpacity(.2)
                : s.contains(WidgetState.selected)
                    ? colors.primary
                    : null),
        checkColor: WidgetStatePropertyAll(colors.onPrimary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4))),
    radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected)
                ? colors.primary
                : colors.onSurfaceVariant)),
    switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected)
                ? colors.primary
                : colors.onSurfaceVariant),
        trackColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected)
                ? colors.primary.withOpacity(.32)
                : colors.onSurface.withOpacity(.16))),
    popupMenuTheme: PopupMenuThemeData(
        color: colors.surface,
        textStyle: TextStyle(color: colors.onSurface),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: colors.outlineVariant))),
  );
}
