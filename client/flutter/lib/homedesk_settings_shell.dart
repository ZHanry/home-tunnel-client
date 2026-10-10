// HOMEDESK: 设置保留主导航，分类和卡片沿用暖居 token，业务仍由上游控制。
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'homedesk_theme.dart';
import 'homedesk_navigation.dart';
import 'homedesk_dashboard.dart';
import 'homedesk_status.dart';
import 'homedesk_account.dart';
import 'common.dart' show appName;

class HomeDeskSettingsShell extends StatelessWidget {
  final List<String> labels;
  final List<IconData> icons;
  final int selected;
  final ValueChanged<int> onSelected;
  final VoidCallback onBack;
  final Widget child;
  final String? brandName;
  final HomeDeskStatusData? statusData;
  final HomeDeskAccount? account;
  const HomeDeskSettingsShell(
      {super.key,
      required this.labels,
      required this.icons,
      required this.selected,
      required this.onSelected,
      required this.onBack,
      required this.child,
      this.brandName,
      this.statusData,
      this.account});
  String _brand() {
    if (brandName != null) return brandName!;
    if (HomeDeskDashboard.active != null) {
      return HomeDeskDashboard.active!.widget.brandName;
    }
    try {
      return appName;
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = homeDeskTheme(Theme.of(context));
    return Theme(
        data: theme,
        child: Builder(builder: (context) {
          final t = HomeDeskTokens.of(context);
          return LayoutBuilder(builder: (context, c) {
            final compact = c.maxWidth < 960 ||
                MediaQuery.textScalerOf(context).scale(1) > 1.5;
            final inset = compact
                ? HomeDeskTokens.narrowPadding
                : HomeDeskTokens.pagePadding;
            return ColoredBox(
                color: t.background,
                child: Column(children: [
                  Expanded(
                      child: Row(children: [
                    HomeDeskNavigation(
                        brand: _brand(),
                        selected: 'settings',
                        compact: compact,
                        account: account ??
                            HomeDeskDashboard.active?.navigationAccount,
                        onSelected: (value) {
                          if (value == 'settings') return;
                          onBack();
                          HomeDeskDashboard.navigate(value);
                        }),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                          Padding(
                              padding:
                                  EdgeInsets.fromLTRB(inset, 24, inset, 16),
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('设置', style: t.titleStyle),
                                    const SizedBox(height: 4),
                                    Text('管理这台设备的连接与偏好',
                                        style: t.auxiliaryStyle)
                                  ])),
                          Padding(
                              padding: EdgeInsets.fromLTRB(inset, 0, inset, 16),
                              child: HomeDeskSegments(
                                  labels: labels,
                                  selected: selected,
                                  onSelected: onSelected,
                                  keyPrefix: 'settings-section')),
                          Expanded(
                              child: Padding(
                                  padding:
                                      EdgeInsets.symmetric(horizontal: inset),
                                  child: child)),
                        ])),
                  ])),
                ]));
          });
        }));
  }
}

class HomeDeskSettingsCard extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final List<Widget>? titleSuffix;
  final bool? serviceStopped;
  const HomeDeskSettingsCard(
      {super.key,
      required this.title,
      required this.children,
      this.titleSuffix,
      this.serviceStopped});
  Widget? _action(Widget child) {
    if (child is ElevatedButton ||
        child is FilledButton ||
        child is OutlinedButton ||
        child is TextButton) return child;
    if (child is Padding) return _action(child.child!);
    if (child is Container && child.child != null) return _action(child.child!);
    if (child is Align && child.child != null) return _action(child.child!);
    if (child is SizedBox && child.child != null) return _action(child.child!);
    if (child is Row && child.children.length == 1) {
      return _action(child.children.single);
    }
    if (child is Column && child.children.length == 1) {
      return _action(child.children.single);
    }
    // 保留按钮的提示组件。
    if (child is Tooltip &&
        child.child != null &&
        _action(child.child!) != null) return child;
    return null;
  }

  Widget _secondary(Widget action) {
    if (action is Tooltip && action.child != null) {
      return Tooltip(message: action.message, child: _secondary(action.child!));
    }
    if (action is ButtonStyleButton) {
      return OutlinedButton(
          key: action.key,
          onPressed: action.onPressed,
          onLongPress: action.onLongPress,
          onHover: action.onHover,
          onFocusChange: action.onFocusChange,
          focusNode: action.focusNode,
          autofocus: action.autofocus,
          child: action.child!);
    }
    return action;
  }

  Iterable<Widget> _descendants(Widget widget) sync* {
    yield widget;
    final Widget? child = switch (widget) {
      Padding w => w.child,
      Align w => w.child,
      Container w => w.child,
      GestureDetector w => w.child,
      Flexible w => w.child,
      SizedBox w => w.child,
      _ => null,
    };
    if (child != null) {
      yield* _descendants(child);
    }
    if (widget is Row) {
      for (final child in widget.children) {
        yield* _descendants(child);
      }
    }
    if (widget is Column) {
      for (final child in widget.children) {
        yield* _descendants(child);
      }
    }
  }

  Widget? _themePicker(BuildContext context) {
    if (title != '主题' && title != 'Theme') {
      return null;
    }
    final choices = <(Radio<String>, String)>[];
    for (final child in children) {
      final nodes = _descendants(child).toList();
      final radios = nodes.whereType<Radio<String>>().toList();
      final labels =
          nodes.whereType<Text>().where((text) => text.data != null).toList();
      if (radios.length != 1 || labels.length != 1) {
        return null;
      }
      choices.add((radios.single, labels.single.data!));
    }
    if (choices.isEmpty) {
      return null;
    }
    final value = choices.first.$1.groupValue;
    return DropdownButtonFormField<String>(
        key: const ValueKey('settings-theme-choice'),
        value: choices.any((c) => c.$1.value == value) ? value : null,
        isExpanded: true,
        style: Theme.of(context).textTheme.bodyMedium,
        decoration: const InputDecoration(
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
        items: [
          for (final choice in choices)
            DropdownMenuItem(
                value: choice.$1.value,
                enabled: choice.$1.onChanged != null,
                child: Text(choice.$2))
        ],
        // 只转发原单选项的回调，主题持久化和更新仍由上游执行。
        onChanged: choices.any((c) => c.$1.onChanged != null)
            ? (value) {
                if (value != null) {
                  choices
                      .firstWhere((c) => c.$1.value == value)
                      .$1
                      .onChanged
                      ?.call(value);
                }
              }
            : null);
  }

  @override
  Widget build(BuildContext context) {
    final service = title == '服务' || title == '后台服务';
    if (service &&
        serviceStopped == null &&
        Get.isRegistered<RxBool>(tag: 'stop-service')) {
      final state = Get.find<RxBool>(tag: 'stop-service');
      return Obx(() => _body(context, state.value));
    }
    return _body(context, serviceStopped);
  }

  Widget _body(BuildContext context, bool? stopped) {
    final t = HomeDeskTokens.of(context);
    final picker = _themePicker(context);
    final originalAction =
        children.length == 1 ? _action(children.single) : null;
    final action = (title == '服务' || title == '后台服务') &&
            stopped != true &&
            originalAction != null
        ? _secondary(originalAction)
        : originalAction;
    final service = title == '服务' || title == '后台服务';
    final heading = service && action != null
        ? stopped == null
            ? '后台服务'
            : '后台服务 · ${stopped ? '已停止' : '运行中'}'
        : title;
    return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Card(
            child: Padding(
                padding: const EdgeInsets.all(HomeDeskTokens.cardPadding),
                child: LayoutBuilder(builder: (context, c) {
                  if (picker != null) {
                    if (c.maxWidth >= 360 &&
                        MediaQuery.textScalerOf(context).scale(1) <= 1.5) {
                      return Row(children: [
                        Expanded(child: Text(title, style: t.sectionStyle)),
                        const SizedBox(width: 12),
                        SizedBox(width: 184, child: picker)
                      ]);
                    }
                    return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(title, style: t.sectionStyle),
                          const SizedBox(height: 12),
                          picker
                        ]);
                  }
                  if (action != null) {
                    if (c.maxWidth < 360 ||
                        MediaQuery.textScalerOf(context).scale(1) > 1.5) {
                      return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(heading, style: t.sectionStyle),
                            const SizedBox(height: 12),
                            action
                          ]);
                    }
                    return Row(children: [
                      Expanded(child: Text(heading, style: t.sectionStyle)),
                      ...?titleSuffix,
                      const SizedBox(width: 12),
                      action
                    ]);
                  }
                  return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(children: [
                          Expanded(child: Text(title, style: t.sectionStyle)),
                          ...?titleSuffix
                        ]),
                        const SizedBox(height: 12),
                        ...children.map((child) => Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: child)),
                      ]);
                }))));
  }
}
