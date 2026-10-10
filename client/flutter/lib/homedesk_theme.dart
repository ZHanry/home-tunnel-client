// HOMEDESK: NestLink的颜色、字号、圆角和间距集中定义，沿用现有字体。
import 'package:flutter/material.dart';
import 'common.dart' show ColorThemeExtension;

@immutable
class HomeDeskTokens extends ThemeExtension<HomeDeskTokens> {
  final Color background, chrome, surface, surface2, sunken, border, strong;
  final Color text, secondary, muted, accent, accentText, accentSoft, onAccent;
  final Color success, warning, danger, successSoft, warningSoft, dangerSoft;
  const HomeDeskTokens(
      {required this.background,
      required this.chrome,
      required this.surface,
      required this.surface2,
      required this.sunken,
      required this.border,
      required this.strong,
      required this.text,
      required this.secondary,
      required this.muted,
      required this.accent,
      required this.accentText,
      required this.accentSoft,
      required this.onAccent,
      required this.success,
      required this.warning,
      required this.danger,
      required this.successSoft,
      required this.warningSoft,
      required this.dangerSoft});
  static const light = HomeDeskTokens(
      background: Color(0xFFFAF9FD),
      chrome: Color(0xFFF2EFF9),
      surface: Color(0xFFFFFFFF),
      surface2: Color(0xFFF8F6FC),
      sunken: Color(0xFFF0ECF7),
      border: Color(0xFFE6E1EE),
      strong: Color(0xFFCFC5DF),
      text: Color(0xFF282235),
      secondary: Color(0xFF70677F),
      muted: Color(0xFF70677F),
      accent: Color(0xFF7955CF),
      accentText: Color(0xFF6842BB),
      accentSoft: Color(0xFFE8DFF7),
      onAccent: Color(0xFFFFFFFF),
      success: Color(0xFF276F46),
      warning: Color(0xFF85570E),
      danger: Color(0xFFBC3A2B),
      successSoft: Color(0xFFE3F1E7),
      warningSoft: Color(0xFFFAEFD7),
      dangerSoft: Color(0xFFFBE5E1));
  static const dark = HomeDeskTokens(
      background: Color(0xFF1B1724),
      chrome: Color(0xFF211B2D),
      surface: Color(0xFF282132),
      surface2: Color(0xFF30273C),
      sunken: Color(0xFF241D30),
      border: Color(0xFF40354E),
      strong: Color(0xFF625371),
      text: Color(0xFFF4EEFC),
      secondary: Color(0xFFC8BCD8),
      muted: Color(0xFFAE9DBF),
      accent: Color(0xFFB89AEA),
      accentText: Color(0xFFC5AAF1),
      accentSoft: Color(0xFF423057),
      onAccent: Color(0xFF21162F),
      success: Color(0xFF6DCB91),
      warning: Color(0xFFE6B566),
      danger: Color(0xFFF08B7D),
      successSoft: Color(0xFF1F3326),
      warningSoft: Color(0xFF3A2F18),
      dangerSoft: Color(0xFF3E231E));
  static HomeDeskTokens of(BuildContext context) =>
      Theme.of(context).extension<HomeDeskTokens>() ??
      (Theme.of(context).brightness == Brightness.dark ? dark : light);
  static const pageTitle = 24.0,
      sectionTitle = 16.0,
      body = 14.0,
      auxiliary = 13.0,
      caption = 12.0;
  static const cardRadius = 10.0,
      blockRadius = 8.0,
      controlRadius = 8.0,
      smallRadius = 8.0,
      dialogRadius = 20.0;
  static const gap = 16.0,
      moduleGap = 20.0,
      pagePadding = 28.0,
      narrowPadding = 24.0;
  static const cardPadding = 16.0,
      dialogPadding = 24.0,
      buttonHeight = 40.0,
      minDeviceWidth = 280.0;
  TextStyle get titleStyle => TextStyle(
      fontSize: pageTitle,
      height: 32 / 24,
      fontWeight: FontWeight.w600,
      color: text);
  TextStyle get sectionStyle => TextStyle(
      fontSize: sectionTitle, fontWeight: FontWeight.w600, color: text);
  TextStyle get auxiliaryStyle =>
      TextStyle(fontSize: auxiliary, color: secondary);
  @override
  HomeDeskTokens copyWith() => this;
  @override
  HomeDeskTokens lerp(covariant HomeDeskTokens? other, double t) =>
      t < .5 ? this : other ?? this;
}

double homeDeskControlHeight(BuildContext context,
        {double minimum = HomeDeskTokens.buttonHeight}) =>
    minimum * MediaQuery.textScalerOf(context).scale(1).clamp(1, 2);

ThemeData homeDeskTheme(ThemeData base) {
  final t = base.brightness == Brightness.dark
      ? HomeDeskTokens.dark
      : HomeDeskTokens.light;
  final colors = ColorScheme(
      brightness: base.brightness,
      primary: t.accent,
      onPrimary: t.onAccent,
      primaryContainer: t.accentSoft,
      onPrimaryContainer: t.accentText,
      secondary: t.accentText,
      onSecondary: t.onAccent,
      secondaryContainer: t.sunken,
      onSecondaryContainer: t.secondary,
      error: t.danger,
      onError: t.surface,
      errorContainer: t.dangerSoft,
      onErrorContainer: t.danger,
      surface: t.surface,
      onSurface: t.text,
      onSurfaceVariant: t.secondary,
      outline: t.strong,
      outlineVariant: t.border,
      surfaceTint: t.surface);
  final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(HomeDeskTokens.controlRadius));
  final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(HomeDeskTokens.controlRadius),
      borderSide: BorderSide(color: t.border));
  return base.copyWith(
    scrollbarTheme: const ScrollbarThemeData(
        thickness: WidgetStatePropertyAll(0),
        thumbVisibility: WidgetStatePropertyAll(false),
        trackVisibility: WidgetStatePropertyAll(false)),
    extensions: [
      ...base.extensions.values
          .where((e) => e is! HomeDeskTokens && e is! ColorThemeExtension),
      ColorThemeExtension(
          border: t.border,
          border2: t.strong,
          border3: t.border,
          highlight: t.sunken,
          drag_indicator: t.accent,
          shadow: t.text.withOpacity(.08),
          errorBannerBg: t.dangerSoft,
          me: t.success,
          toastBg: t.surface,
          toastText: t.text,
          divider: t.border),
      t
    ],
    colorScheme: colors,
    primaryColor: t.accent,
    scaffoldBackgroundColor: t.background,
    canvasColor: t.surface,
    cardColor: t.surface,
    dialogBackgroundColor: t.surface,
    dividerColor: t.border,
    hoverColor: t.accentSoft,
    textTheme: base.textTheme
        .apply(bodyColor: t.text, displayColor: t.text)
        .copyWith(
            bodySmall: base.textTheme.bodySmall
                ?.copyWith(fontSize: HomeDeskTokens.body, color: t.secondary),
            bodyMedium: base.textTheme.bodyMedium?.copyWith(
                fontSize: HomeDeskTokens.body, height: 1.5, color: t.text),
            titleLarge: base.textTheme.titleLarge?.copyWith(
                fontSize: HomeDeskTokens.pageTitle,
                fontWeight: FontWeight.w600,
                color: t.text),
            titleMedium: base.textTheme.titleMedium?.copyWith(
                fontSize: HomeDeskTokens.sectionTitle,
                fontWeight: FontWeight.w600,
                color: t.text)),
    cardTheme: CardTheme(
        color: t.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(HomeDeskTokens.cardRadius),
            side: BorderSide(color: t.border))),
    dialogTheme: DialogTheme(
        backgroundColor: t.surface,
        elevation: 0,
        titleTextStyle:
            TextStyle(color: t.text, fontSize: 18, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(HomeDeskTokens.dialogRadius),
            side: BorderSide(color: t.border))),
    elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
            backgroundColor: t.accent,
            foregroundColor: t.onAccent,
            minimumSize: const Size(0, HomeDeskTokens.buttonHeight),
            elevation: 0,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: shape)),
    filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
            backgroundColor: t.accent,
            foregroundColor: t.onAccent,
            minimumSize: const Size(0, HomeDeskTokens.buttonHeight),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: shape)),
    outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
            foregroundColor: t.secondary,
            backgroundColor: t.surface,
            minimumSize: const Size(0, HomeDeskTokens.buttonHeight),
            side: BorderSide(color: t.strong),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: shape)),
    textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
            foregroundColor: t.accentText,
            minimumSize: const Size(0, HomeDeskTokens.buttonHeight),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: shape)),
    iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
            minimumSize: const Size(40, 40),
            padding: EdgeInsets.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap)),
    iconTheme: IconThemeData(color: t.secondary, size: 20),
    inputDecorationTheme: InputDecorationTheme(
        constraints:
            const BoxConstraints(minHeight: HomeDeskTokens.buttonHeight),
        filled: true,
        fillColor: t.sunken,
        hoverColor: Colors.transparent,
        isDense: true,
        floatingLabelBehavior: FloatingLabelBehavior.always,
        alignLabelWithHint: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: border,
        enabledBorder: border,
        focusedBorder: border.copyWith(
            borderSide: BorderSide(color: t.accent, width: 1.5)),
        hintStyle: base.textTheme.bodyMedium?.copyWith(
            color: t.secondary,
            fontSize: HomeDeskTokens.body,
            fontWeight: FontWeight.w400),
        labelStyle:
            TextStyle(color: t.secondary, fontSize: HomeDeskTokens.body)),
    chipTheme: base.chipTheme.copyWith(
        backgroundColor: t.sunken,
        selectedColor: t.accentSoft,
        side: BorderSide.none,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(HomeDeskTokens.smallRadius)),
        labelStyle:
            TextStyle(fontSize: HomeDeskTokens.auxiliary, color: t.secondary),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
    checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.disabled)
                ? t.muted
                : s.contains(WidgetState.selected)
                    ? t.accent
                    : null),
        checkColor: WidgetStatePropertyAll(t.onAccent),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4))),
    radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? t.accent : t.secondary)),
    switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? t.accent : t.secondary),
        trackColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? t.accentSoft : t.strong)),
    popupMenuTheme: PopupMenuThemeData(
        color: t.surface,
        textStyle: base.textTheme.bodyMedium
            ?.copyWith(color: t.text, fontSize: HomeDeskTokens.body),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(HomeDeskTokens.blockRadius),
            side: BorderSide(color: t.border))),
  );
}

enum HomeDeskTone { neutral, accent, success, warning, danger }

class HomeDeskBadge extends StatelessWidget {
  final String label;
  final HomeDeskTone tone;
  final bool dot;
  const HomeDeskBadge(this.label,
      {super.key, this.tone = HomeDeskTone.neutral, this.dot = true});
  @override
  Widget build(BuildContext context) {
    final t = HomeDeskTokens.of(context);
    final (fg, bg) = switch (tone) {
      HomeDeskTone.accent => (t.accentText, t.accentSoft),
      HomeDeskTone.success => (t.success, t.successSoft),
      HomeDeskTone.warning => (t.warning, t.warningSoft),
      HomeDeskTone.danger => (t.danger, t.dangerSoft),
      HomeDeskTone.neutral => (t.secondary, t.sunken),
    };
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
        child: Text('${dot ? '● ' : ''}$label',
            style: TextStyle(color: fg, fontSize: HomeDeskTokens.caption)));
  }
}

class HomeDeskSegments extends StatelessWidget {
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelected;
  final String keyPrefix;
  const HomeDeskSegments(
      {super.key,
      required this.labels,
      required this.selected,
      required this.onSelected,
      this.keyPrefix = 'segment'});
  @override
  Widget build(BuildContext context) {
    final t = HomeDeskTokens.of(context);
    return Wrap(
        spacing: 4,
        runSpacing: 4,
        children: List.generate(
            labels.length,
            (i) => Semantics(
                selected: i == selected,
                child: TextButton(
                    key: ValueKey('$keyPrefix-$i'),
                    style: TextButton.styleFrom(
                        backgroundColor:
                            i == selected ? t.accentSoft : t.sunken,
                        foregroundColor:
                            i == selected ? t.accentText : t.secondary),
                    onPressed: () => onSelected(i),
                    child: Text(labels[i])))));
  }
}

// 标签放在输入框上方，输入控件的校验和提交回调保持不变。
class HomeDeskFieldLabel extends StatelessWidget {
  final String label;
  final Widget child;
  const HomeDeskFieldLabel(this.label, {super.key, required this.child});
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: HomeDeskTokens.of(context)
                .auxiliaryStyle
                .copyWith(height: 1.2)),
        const SizedBox(height: 4),
        child
      ]);
}
