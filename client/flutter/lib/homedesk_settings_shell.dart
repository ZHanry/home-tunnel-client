// HOMEDESK: 设置使用主页的卡片与响应式内容区，原设置业务逻辑继续由上游管理。
import 'package:flutter/material.dart';

class HomeDeskSettingsShell extends StatelessWidget {
  final List<String> labels;
  final List<IconData> icons;
  final int selected;
  final ValueChanged<int> onSelected;
  final VoidCallback onBack;
  final Widget child;
  const HomeDeskSettingsShell(
      {super.key,
      required this.labels,
      required this.icons,
      required this.selected,
      required this.onSelected,
      required this.onBack,
      required this.child});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ColoredBox(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1040),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                          padding: const EdgeInsets.fromLTRB(18, 22, 18, 12),
                          child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                IconButton(
                                    tooltip: '返回主页',
                                    onPressed: onBack,
                                    icon: const Icon(Icons.arrow_back_rounded)),
                                const SizedBox(width: 12),
                                Expanded(
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                      const Text('设置',
                                          style: TextStyle(
                                              fontSize: 28,
                                              fontWeight: FontWeight.w700)),
                                      const SizedBox(height: 5),
                                      Text('管理这台设备的连接与偏好',
                                          style: TextStyle(
                                              color: colors.onSurfaceVariant)),
                                    ])),
                              ])),
                      SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
                          child: Row(
                              children: List.generate(labels.length, (index) {
                            final active = selected == index;
                            return Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: Semantics(
                                    selected: active,
                                    child: OutlinedButton.icon(
                                        key:
                                            ValueKey('settings-section-$index'),
                                        onPressed: () => onSelected(index),
                                        style: OutlinedButton.styleFrom(
                                            backgroundColor: active
                                                ? colors.primaryContainer
                                                : colors.surface,
                                            foregroundColor: active
                                                ? colors.onPrimaryContainer
                                                : colors.onSurfaceVariant,
                                            side: BorderSide(
                                                color: active
                                                    ? colors.primary
                                                        .withOpacity(.35)
                                                    : colors.outlineVariant),
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 18, vertical: 12)),
                                        icon: Icon(icons[index], size: 19),
                                        label: Text(labels[index]))));
                          }))),
                      Expanded(child: child),
                    ]))));
  }
}

class HomeDeskSettingsCard extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final List<Widget>? titleSuffix;
  const HomeDeskSettingsCard(
      {super.key,
      required this.title,
      required this.children,
      this.titleSuffix});
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
      child: Card(
          child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 18, 4, 18),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                        child: Row(children: [
                          Expanded(
                              child: Text(title,
                                  style: const TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w600))),
                          ...?titleSuffix,
                        ])),
                    ...children.map((child) => Padding(
                        padding: const EdgeInsets.only(top: 4, right: 16),
                        child: child)),
                  ]))));
}
