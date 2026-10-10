import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'dart:async';
import 'dart:io';
import 'homedesk_theme.dart';
import 'homedesk_navigation.dart';
import 'homedesk_family_devices.dart';
import 'homedesk_account.dart';
import 'homedesk_tunnel_api.dart';
import 'nestlink_workspace.dart';
import 'nestlink_locale.dart';
import 'nestlink_account_page.dart';
import 'nestlink_dialog.dart';

enum _DashboardPage { remote, services, devices, account }

class HomeDeskDashboard extends StatefulWidget {
  final String brandName;
  final WidgetBuilder devicesBuilder, recentBuilder, statusBuilder;
  final WidgetBuilder? servicesBuilder,
      recentSummaryBuilder,
      remoteCredentialsBuilder,
      remoteSettingsBuilder,
      localBuilder;
  final VoidCallback? onSettings;
  final VoidCallback? onNetworkSettings;
  final ValueChanged<String> onConnect;
  final bool initializeAccount;
  final bool mobilePlatform;
  final dynamic statusData;
  static HomeDeskDashboardState? active;
  static void navigate(String destination) => active?._navigate(destination);
  const HomeDeskDashboard(
      {super.key,
      required this.brandName,
      required this.devicesBuilder,
      required this.recentBuilder,
      this.localBuilder,
      required this.statusBuilder,
      this.onSettings,
      required this.onConnect,
      this.onNetworkSettings,
      this.remoteCredentialsBuilder,
      this.remoteSettingsBuilder,
      this.servicesBuilder,
      this.initializeAccount = false,
      this.mobilePlatform = false,
      this.statusData,
      this.recentSummaryBuilder});
  @override
  State<HomeDeskDashboard> createState() => HomeDeskDashboardState();
}

class HomeDeskDashboardState extends State<HomeDeskDashboard> {
  final _remoteKey = GlobalKey<NestLinkRemoteWorkspaceState>();
  _DashboardPage _page = _DashboardPage.devices;
  HomeDeskAccount? navigationAccount;
  HomeTunnelApi? _versionOwner;
  bool _servicesInitialized = false;
  @override
  void initState() {
    super.initState();
    // The foreground session owner must survive the transition from login to remote workspace.
    _servicesInitialized = widget.initializeAccount;
    HomeDeskDashboard.active = this;
  }

  @override
  void dispose() {
    if (identical(HomeDeskDashboard.active, this)) {
      HomeDeskDashboard.active = null;
    }
    super.dispose();
  }

  void _navigate(String destination) {
    setState(() {
      if (destination == 'services') _servicesInitialized = true;
      _page = switch (destination) {
        'services' => _DashboardPage.services,
        'account' => _DashboardPage.account,
        'devices' => _DashboardPage.devices,
        'settings' => _DashboardPage.account,
        _ => _DashboardPage.remote,
      };
    });
  }

  void showAccount() =>
      _navigate(navigationAccount?.signedIn == true ? 'account' : 'services');
  void showRemoteSettings() {
    if (navigationAccount != null && !navigationAccount!.signedIn) {
      showAccount();
      return;
    }
    _navigate('remote');
    _remoteKey.currentState?.showSettings();
  }

  Future<void> showManualConnection() async {
    final account = navigationAccount;
    final owner = account?.api;
    if (account != null && !account.signedIn) {
      showAccount();
      return;
    }
    final id = await showDialog<String>(
        context: context, builder: (_) => const _ManualConnectionDialog());
    if (id == null || !mounted) return;
    if (account != null &&
        (!identical(account, navigationAccount) ||
            !identical(owner, account.api) ||
            !account.signedIn)) return;
    widget.onConnect(id);
  }

  Widget _body(BuildContext context, Widget devices, HomeDeskAccount? account) {
    final t = HomeDeskTokens.of(context);
    final signedIn = account == null || account.signedIn;
    // The sign-in page owns the foreground session and must remain mounted
    // when the directory becomes visible after the first login.
    if (!signedIn) _servicesInitialized = true;
    navigationAccount = account;
    if (!identical(_versionOwner, account?.api)) {
      _versionOwner = account?.api;
      _page = _DashboardPage.devices;
      unawaited(checkNestLinkVersion(_versionOwner));
    }
    final index = signedIn ? _page.index : _DashboardPage.services.index;
    final title = [
      nl('远程协助', 'Remote assistance'),
      nl('内网穿透', 'Tunnels'),
      nl('设备管理', 'Device management'),
      nl('账号与设置', 'Account and settings'),
    ][index];
    return HomeDeskHomeActions(
        onRecent: () => _navigate('remote'),
        onManualConnect: showManualConnection,
        recentSummary: widget.recentSummaryBuilder ?? widget.recentBuilder,
        status: widget.statusBuilder,
        child: ScrollConfiguration(
            behavior: const NestLinkScrollBehavior(),
            child: ColoredBox(
                color: t.background,
                child: LayoutBuilder(builder: (context, constraints) {
                  final mobile = widget.mobilePlatform ||
                      Platform.isAndroid ||
                      Platform.isIOS;
                  final compact = constraints.maxWidth < 760;
                  final phone = mobile && compact;
                  final pages = IndexedStack(index: index, children: [
                    TickerMode(
                        enabled: signedIn && index == 0,
                        child: NestLinkRemoteWorkspace(
                            key: _remoteKey,
                            account: account,
                            mobilePlatform: mobile,
                            remoteSettingsBuilder: widget.remoteSettingsBuilder,
                            onConnect: widget.onConnect,
                            localCredentials:
                                widget.remoteCredentialsBuilder?.call(context),
                            localHost: mobile && signedIn
                                ? widget.localBuilder?.call(context)
                                : null,
                            onManageDevices: () => _navigate('devices'),
                            recent: widget.recentBuilder(context),
                            status: widget.statusBuilder(context))),
                    _servicesInitialized || !signedIn
                        ? widget.servicesBuilder?.call(context) ??
                            const SizedBox.shrink()
                        : const SizedBox.shrink(),
                    TickerMode(enabled: signedIn && index == 2, child: devices),
                    NestLinkAccountPage(
                        account: account,
                        onLogin: () => _navigate('services'),
                        settingsBuilder: (_) => NestLinkSettings(
                            account: account,
                            embedded: true,
                            onNetworkSettings: widget.onNetworkSettings)),
                  ]);
                  return Column(children: [
                    Expanded(
                        child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                          if (signedIn && !phone)
                            HomeDeskNavigation(
                                brand: 'NestLink',
                                compact: mobile
                                    ? constraints.maxWidth < 1000
                                    : compact,
                                selected: _page.name,
                                onSelected: _navigate,
                                services: widget.servicesBuilder != null,
                                account: account),
                          Expanded(
                              child: Container(
                                  decoration: BoxDecoration(
                                      color: t.background,
                                      borderRadius: const BorderRadius.only(
                                          topLeft: Radius.circular(12)),
                                      border: Border(
                                          left: BorderSide(color: t.border),
                                          top: BorderSide(color: t.border))),
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        if (signedIn && phone)
                                          Padding(
                                              padding:
                                                  const EdgeInsets.fromLTRB(
                                                      16, 8, 8, 8),
                                              child: Row(children: [
                                                SvgPicture.asset(
                                                    'assets/icon.svg',
                                                    width: 28,
                                                    height: 28),
                                                const SizedBox(width: 10),
                                                Expanded(
                                                    child: Text('NestLink',
                                                        style: t.sectionStyle)),
                                                IconButton(
                                                    key: const ValueKey(
                                                        'mobile-account'),
                                                    tooltip: nl(
                                                        '账号与设置', 'Account and settings'),
                                                    onPressed: showAccount,
                                                    icon: CircleAvatar(
                                                        radius: 16,
                                                        backgroundColor:
                                                            t.accentSoft,
                                                        child: account?.displayName.trim().isNotEmpty == true
                                                            ? Text(
                                                                account!.displayName
                                                                    .trim()
                                                                    .characters
                                                                    .first,
                                                                textScaler: TextScaler
                                                                    .noScaling,
                                                                style: TextStyle(
                                                                    color: t
                                                                        .accentText,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w600))
                                                            : Icon(Icons.person_outline_rounded,
                                                                size: 20,
                                                                color: t.accentText))),
                                              ])),
                                        if ((signedIn ||
                                                index ==
                                                    _DashboardPage
                                                        .account.index) &&
                                            index !=
                                                _DashboardPage.services.index &&
                                            !(index ==
                                                    _DashboardPage
                                                        .devices.index &&
                                                devices
                                                    is HomeDeskFamilyDevices &&
                                                devices.listLayout))
                                          Padding(
                                              padding:
                                                  phone
                                                      ? const EdgeInsets
                                                          .fromLTRB(
                                                          16, 8, 16, 16)
                                                      : const EdgeInsets
                                                          .fromLTRB(
                                                          32, 28, 28, 20),
                                              child: Row(children: [
                                                Expanded(
                                                    child: Text(title,
                                                        style: t.titleStyle)),
                                              ])),
                                        Expanded(
                                            child: Padding(
                                                padding: EdgeInsets.symmetric(
                                                    horizontal: signedIn
                                                        ? (compact ? 16 : 24)
                                                        : 0),
                                                child: pages)),
                                      ]))),
                        ])),
                    if (signedIn && phone)
                      NavigationBar(
                          key: const ValueKey('mobile-navigation'),
                          height: 64 +
                              (MediaQuery.textScalerOf(context).scale(14) - 14)
                                  .clamp(0, 28),
                          selectedIndex: _page == _DashboardPage.services
                              ? 2
                              : _page == _DashboardPage.remote
                                  ? 1
                                  : 0,
                          onDestinationSelected: (i) => _navigate([
                                _DashboardPage.devices,
                                _DashboardPage.remote,
                                _DashboardPage.services
                              ][i]
                                  .name),
                          destinations: [
                            NavigationDestination(
                                icon: const Icon(Icons.apps_rounded),
                                label: nl('设备管理', 'Device management')),
                            NavigationDestination(
                                icon: const Icon(Icons.screen_share_outlined),
                                label: nl('远程协助', 'Remote assistance')),
                            NavigationDestination(
                                icon: const Icon(Icons.hub_outlined),
                                label: nl('内网穿透', 'Tunnels')),
                          ]),
                  ]);
                }))));
  }

  @override
  Widget build(BuildContext context) {
    final devices = widget.devicesBuilder(context);
    final account = devices is HomeDeskFamilyDevices ? devices.account : null;
    return ValueListenableBuilder<String>(
        valueListenable: nestlinkLanguage,
        builder: (context, _, __) => Theme(
            data: homeDeskTheme(Theme.of(context)),
            child: account == null
                ? _body(context, devices, null)
                : HomeDeskAccountView(
                    account: account,
                    builder: (context) => _body(context, devices, account))));
  }
}

class _ManualConnectionDialog extends StatefulWidget {
  const _ManualConnectionDialog();
  @override
  State<_ManualConnectionDialog> createState() =>
      _ManualConnectionDialogState();
}

class _ManualConnectionDialogState extends State<_ManualConnectionDialog> {
  final _controller = TextEditingController();
  String? _error;
  void _submit() {
    final id = _controller.text.trim();
    if (!RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(id)) {
      setState(() => _error = '请输入设备 ID');
      return;
    }
    Navigator.pop(context, id);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => NestLinkDialog(
        width: 420,
        title: const Text('连接一台设备'),
        content: SizedBox(
            width: 380,
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('在另一台电脑上打开客户端，输入它的设备 ID。'),
                  const SizedBox(height: 20),
                  HomeDeskFieldLabel('设备 ID',
                      child: TextField(
                          controller: _controller,
                          autofocus: true,
                          onSubmitted: (_) => _submit(),
                          decoration: InputDecoration(
                              errorText: _error, hintText: '输入设备 ID'))),
                ])),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(onPressed: _submit, child: const Text('连接设备'))
        ],
      );
}
