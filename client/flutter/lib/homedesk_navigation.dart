// The desktop has three main destinations and a fixed account entry below them.
import 'dart:async';
import 'package:flutter/material.dart';
import 'homedesk_account.dart';
import 'homedesk_theme.dart';
import 'nestlink_locale.dart';

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

  Widget _item(
      BuildContext context, String value, String label, IconData icon) {
    final t = HomeDeskTokens.of(context);
    final active = selected == value;
    return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Tooltip(
            message: label,
            child: TextButton(
                key: ValueKey('nav-$value'),
                onPressed: () => onSelected(value),
                style: TextButton.styleFrom(
                    foregroundColor: active ? t.accentText : t.text,
                    backgroundColor: active ? t.accentSoft : Colors.transparent,
                    padding: EdgeInsets.symmetric(
                        horizontal: compact ? 4 : 14,
                        vertical: compact ? 8 : 10),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6))),
                child: compact
                    ? Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(icon, size: 21),
                        const SizedBox(height: 4),
                        Text(label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12)),
                      ])
                    : Row(children: [
                        Icon(icon,
                            size: 20, color: active ? t.accentText : t.accent),
                        const SizedBox(width: 12),
                        Expanded(
                            child: Text(label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: active
                                        ? FontWeight.w600
                                        : FontWeight.w400))),
                      ]))));
  }

  Widget _accountEntry(BuildContext context) {
    final t = HomeDeskTokens.of(context);
    final signedIn = account?.signedIn == true;
    final name = signedIn
        ? account!.displayName.trim().isEmpty
            ? nl('账号', 'Account')
            : account!.displayName.trim()
        : nl('未登录', 'Not signed in');
    final avatar = Container(
        key: const ValueKey('nav-account-avatar'),
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: t.accentSoft, shape: BoxShape.circle),
        child: signedIn
            ? Text(name.characters.first,
                textScaler: TextScaler.noScaling,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: t.accentText))
            : Icon(Icons.person_outline_rounded,
                size: 20, color: t.accentText));
    final label = Text(name,
        key: const ValueKey('nav-account-name'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: compact ? 12 : 15));
    return Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 12),
        child: Tooltip(
            message: nl('账号与设置', 'Account & settings'),
            child: TextButton(
                key: const ValueKey('nav-account'),
                onPressed: () => onSelected('account'),
                style: TextButton.styleFrom(
                    foregroundColor: t.text,
                    backgroundColor: selected == 'account'
                        ? t.accentSoft
                        : Colors.transparent,
                    padding: EdgeInsets.symmetric(
                        horizontal: compact ? 4 : 10, vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6))),
                child: compact
                    ? Column(mainAxisSize: MainAxisSize.min, children: [
                        avatar,
                        const SizedBox(height: 6),
                        label,
                      ])
                    : Row(children: [
                        avatar,
                        const SizedBox(width: 12),
                        Expanded(child: label),
                      ]))));
  }

  Widget _body(BuildContext context) {
    final t = HomeDeskTokens.of(context);
    final content = <Widget>[
      const SizedBox(height: 16),
      _item(context, 'devices', nl('设备管理', 'Device management'),
          Icons.apps_rounded),
      _item(context, 'remote', nl('远程协助', 'Remote assistance'),
          Icons.screen_share_outlined),
      if (services)
        _item(context, 'services', nl('内网穿透', 'Tunnels'), Icons.hub_outlined),
      const SizedBox(height: 14),
    ];
    return Container(
        width: compact ? 84 : 220,
        padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 10),
        color: t.chrome,
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
              child: SingleChildScrollView(
                  key: const ValueKey('nav-main-scroll'),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: content))),
          _accountEntry(context),
        ]));
  }

  @override
  Widget build(BuildContext context) => account == null
      ? _body(context)
      : HomeDeskAccountView(account: account!, builder: _body);
}

// Device pages share recent connections and connection status through the shell.
class HomeDeskHomeActions extends InheritedWidget {
  final VoidCallback onRecent;
  final VoidCallback? onManualConnect;
  final WidgetBuilder recentSummary;
  final WidgetBuilder status;
  const HomeDeskHomeActions(
      {super.key,
      required super.child,
      required this.onRecent,
      this.onManualConnect,
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
    return Padding(
        padding: const EdgeInsets.only(
            top: HomeDeskTokens.moduleGap, bottom: HomeDeskTokens.moduleGap),
        child: recent);
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
