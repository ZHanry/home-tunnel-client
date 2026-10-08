// HOMEDESK: 主界面与设置共享带文字的响应式导航，只分派已有入口。
import 'dart:async';
import 'package:flutter/material.dart';
import 'homedesk_account.dart';
import 'homedesk_theme.dart';

class HomeDeskNavigation extends StatelessWidget {
  final String brand, selected;
  final bool compact, services;
  final ValueChanged<String> onSelected;
  final HomeDeskAccount? account;
  const HomeDeskNavigation(
      {super.key,
      required this.brand,
      required this.selected,
      required this.compact,
      required this.onSelected,
      this.services = true,
      this.account});
  Widget _item(BuildContext context, String value, String label, IconData icon,
      {String? count}) {
    final t = HomeDeskTokens.of(context);
    final active = selected == value;
    final text = Text(label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
            fontSize: compact ? HomeDeskTokens.caption : HomeDeskTokens.body));
    return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Tooltip(
            message: label,
            child: TextButton(
                key: ValueKey('nav-$value'),
                onPressed: () => onSelected(value),
                style: TextButton.styleFrom(
                    foregroundColor: active ? t.accentText : t.secondary,
                    backgroundColor: active ? t.accentSoft : null,
                    padding: EdgeInsets.symmetric(
                        horizontal: compact ? 2 : 12,
                        vertical: compact ? 6 : 10)),
                child: compact
                    ? Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(icon, size: 22),
                        const SizedBox(height: 4),
                        text
                      ])
                    : Row(children: [
                        Icon(icon, size: 20),
                        const SizedBox(width: 12),
                        Expanded(child: text),
                        if (count != null)
                          Text(count,
                              style: TextStyle(fontSize: 12, color: t.muted))
                      ]))));
  }

  Widget _body(BuildContext context) {
    final t = HomeDeskTokens.of(context);
    final content = <Widget>[
      Padding(
          padding: EdgeInsets.symmetric(vertical: compact ? 12 : 16),
          child: Row(
              mainAxisAlignment:
                  compact ? MainAxisAlignment.center : MainAxisAlignment.start,
              children: [
                Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                        color: t.accent,
                        borderRadius:
                            BorderRadius.circular(HomeDeskTokens.blockRadius)),
                    child:
                        Icon(Icons.home_rounded, color: t.onAccent, size: 23)),
                if (!compact) ...[
                  const SizedBox(width: 10),
                  Expanded(
                      child: Text(brand,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.sectionStyle))
                ]
              ])),
      const SizedBox(height: 12),
      _item(context, 'devices', '家庭设备', Icons.devices_rounded,
          count: account?.catalog?.devices.length.toString()),
      _item(context, 'recent', '最近连接', Icons.history_rounded),
      if (services)
        _item(context, 'services', '家庭服务', Icons.apps_rounded,
            count: account?.catalog?.services.length.toString()),
    ];
    final lower = <Widget>[
      _item(context, 'local', '本机信息', Icons.computer_rounded),
      _item(context, 'settings', '设置', Icons.settings_outlined),
      const SizedBox(height: 8),
      Divider(color: t.border, height: 12),
      _item(
          context,
          'account',
          compact
              ? '家庭账号'
              : account?.signedIn == true
                  ? account!.displayName
                  : '登录家庭账号',
          Icons.person_outline_rounded),
      if (!compact)
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(account?.signedIn == true ? '家庭账号已登录' : '登录后同步家庭设备',
                style: t.auxiliaryStyle)),
      const SizedBox(height: 12),
    ];
    return Container(
        width: compact ? 84 : 220,
        padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 12),
        decoration: BoxDecoration(
            color: t.chrome,
            border: Border(right: BorderSide(color: t.border))),
        child: LayoutBuilder(builder: (context, c) {
          // 大字体或矮窗口时允许导航滚动，所有入口仍保留文字。
          if (c.maxHeight < 480 ||
              MediaQuery.textScalerOf(context).scale(1) > 1.5) {
            return SingleChildScrollView(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                  ...content,
                  const SizedBox(height: 8),
                  ...lower
                ]));
          }
          return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [...content, const Spacer(), ...lower]);
        }));
  }

  @override
  Widget build(BuildContext context) => account == null
      ? _body(context)
      : HomeDeskAccountView(account: account!, builder: _body);
}

// 首页设备模块通过外壳请求本机信息和最近连接，凭据只在主动查看后展示。
class HomeDeskHomeActions extends InheritedWidget {
  final VoidCallback onLocal, onRecent;
  final WidgetBuilder recentSummary;
  final WidgetBuilder status;
  const HomeDeskHomeActions(
      {super.key,
      required super.child,
      required this.onLocal,
      required this.onRecent,
      required this.recentSummary,
      required this.status});
  static HomeDeskHomeActions? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<HomeDeskHomeActions>();
  @override
  bool updateShouldNotify(HomeDeskHomeActions oldWidget) => true;
}

class HomeDeskHomePanels extends StatelessWidget {
  const HomeDeskHomePanels({super.key});
  @override
  Widget build(BuildContext context) {
    final actions = HomeDeskHomeActions.of(context);
    if (actions == null) return const SizedBox.shrink();
    final t = HomeDeskTokens.of(context);
    Widget panel(String title, Widget child, {Widget? action}) => Card(
        child: Padding(
            padding: const EdgeInsets.all(HomeDeskTokens.cardPadding),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(title, style: t.sectionStyle)),
                if (action != null) action
              ]),
              const SizedBox(height: 12),
              child
            ])));
    final recent = panel('最近连接', actions.recentSummary(context),
        action:
            TextButton(onPressed: actions.onRecent, child: const Text('查看全部')));
    final local = panel(
        '让家人连接这台电脑',
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('打开连接码，查看设备 ID 和本机允许的连接方式。', style: t.auxiliaryStyle),
          const SizedBox(height: 12),
          OutlinedButton.icon(
              onPressed: actions.onLocal,
              icon: const Icon(Icons.key_rounded, size: 18),
              label: const Text('查看连接码')),
          const SizedBox(height: 8),
          Text('固定密码和本机确认可在“设置 · 安全”中管理。', style: t.auxiliaryStyle)
        ]));
    return Padding(
        padding: const EdgeInsets.only(
            top: HomeDeskTokens.moduleGap, bottom: HomeDeskTokens.moduleGap),
        child: LayoutBuilder(
            builder: (context, c) => c.maxWidth >= 760 &&
                    MediaQuery.textScalerOf(context).scale(1) <= 1.5
                ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: recent),
                    const SizedBox(width: 16),
                    Expanded(child: local)
                  ])
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [recent, const SizedBox(height: 16), local])));
  }
}

// 账号在旧页面卸载时也会通知；把纯展示刷新安排到帧结束后，避免导航期间锁树。
class HomeDeskAccountView extends StatefulWidget {
  final HomeDeskAccount account;
  final WidgetBuilder builder;
  const HomeDeskAccountView(
      {super.key, required this.account, required this.builder});
  @override
  State<HomeDeskAccountView> createState() => _HomeDeskAccountViewState();
}

class _HomeDeskAccountViewState extends State<HomeDeskAccountView> {
  bool _queued = false;
  void _changed() {
    if (_queued) {
      return;
    }
    _queued = true;
    scheduleMicrotask(() {
      _queued = false;
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void initState() {
    super.initState();
    widget.account.addListener(_changed);
  }

  @override
  void didUpdateWidget(covariant HomeDeskAccountView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.account, oldWidget.account)) {
      oldWidget.account.removeListener(_changed);
      widget.account.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.account.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}
