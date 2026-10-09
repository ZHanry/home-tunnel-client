import 'package:flutter/material.dart';
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

enum _DashboardPage { remote, services, devices, settings, account }

class HomeDeskDashboard extends StatefulWidget {
  final String brandName;
  final WidgetBuilder devicesBuilder,
      recentBuilder,
      localBuilder,
      statusBuilder;
  final WidgetBuilder? servicesBuilder, recentSummaryBuilder;
  final VoidCallback onSettings;
  final VoidCallback? onNetworkSettings;
  final ValueChanged<String> onConnect;
  final bool initializeAccount;
  final dynamic statusData;
  static HomeDeskDashboardState? active;
  static void navigate(String destination) => active?._navigate(destination);
  const HomeDeskDashboard(
      {super.key,
      required this.brandName,
      required this.devicesBuilder,
      required this.recentBuilder,
      required this.localBuilder,
      required this.statusBuilder,
      required this.onSettings,
      required this.onConnect,
      this.onNetworkSettings,
      this.servicesBuilder,
      this.initializeAccount = false,
      this.statusData,
      this.recentSummaryBuilder});
  @override
  State<HomeDeskDashboard> createState() => HomeDeskDashboardState();
}

class HomeDeskDashboardState extends State<HomeDeskDashboard> {
  _DashboardPage _page = _DashboardPage.remote;
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
    if (identical(HomeDeskDashboard.active, this))
      HomeDeskDashboard.active = null;
    super.dispose();
  }

  void _navigate(String destination) {
    if (destination == 'local') {
      _showLocal();
      return;
    }
    setState(() {
      if (destination == 'services') _servicesInitialized = true;
      _page = switch (destination) {
        'services' => _DashboardPage.services,
        'account' => _DashboardPage.account,
        'devices' => _DashboardPage.devices,
        'settings' => _DashboardPage.settings,
        _ => _DashboardPage.remote,
      };
    });
  }

  void showAccount() =>
      _navigate(navigationAccount?.signedIn == true ? 'account' : 'services');
  Future<void> showManualConnection() async {
    if (navigationAccount != null && !navigationAccount!.signedIn) {
      showAccount();
      return;
    }
    final id = await showDialog<String>(
        context: context, builder: (_) => const _ManualConnectionDialog());
    if (id != null && mounted) widget.onConnect(id);
  }

  void _showLocal() {
    if (navigationAccount != null && !navigationAccount!.signedIn) {
      showAccount();
      return;
    }
    showDialog<void>(
        context: context,
        builder: (context) => Dialog(
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                  constraints: BoxConstraints(
                      maxWidth: 620,
                      maxHeight: MediaQuery.sizeOf(context).height - 48),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Padding(
                        padding: const EdgeInsets.fromLTRB(24, 16, 8, 8),
                        child: Row(children: [
                          Expanded(
                              child: Text(nl('本机共享', 'Share this device'),
                                  style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w600))),
                          IconButton(
                              onPressed: () => Navigator.pop(context),
                              tooltip: nl('关闭', 'Close'),
                              icon: const Icon(Icons.close)),
                        ])),
                    Flexible(child: widget.localBuilder(context)),
                  ])),
            ));
  }

  Widget _body(BuildContext context, Widget devices, HomeDeskAccount? account) {
    final t = HomeDeskTokens.of(context);
    final signedIn = account == null || account.signedIn;
    navigationAccount = account;
    if (!identical(_versionOwner, account?.api)) {
      _versionOwner = account?.api;
      unawaited(checkNestLinkVersion(_versionOwner));
    }
    final index = signedIn ? _page.index : _DashboardPage.services.index;
    final title = [
      nl('远程控制', 'Remote control'),
      nl('内网穿透', 'Tunnels'),
      nl('设备', 'Devices'),
      nl('设置', 'Settings'),
      nl('账号', 'Account')
    ][index];
    return ScrollConfiguration(
        behavior: const NestLinkScrollBehavior(),
        child: ColoredBox(
            color: t.background,
            child: LayoutBuilder(builder: (context, constraints) {
              final mobile = Platform.isAndroid ||
                  Platform.isIOS ||
                  constraints.maxWidth < 620;
              final compact = mobile || constraints.maxWidth < 1000;
              final pages = IndexedStack(index: index, children: [
                TickerMode(
                    enabled: signedIn && index == 0,
                    child: NestLinkRemoteWorkspace(
                        account: account,
                        onConnect: widget.onConnect,
                        onLocal: _showLocal,
                        onManageDevices: () => _navigate('devices'),
                        recent: widget.recentBuilder(context),
                        status: widget.statusBuilder(context))),
                _servicesInitialized || !signedIn
                    ? widget.servicesBuilder?.call(context) ??
                        const SizedBox.shrink()
                    : const SizedBox.shrink(),
                TickerMode(enabled: signedIn && index == 2, child: devices),
                NestLinkSettings(
                    account: account,
                    onSharing: _showLocal,
                    onAccount: showAccount),
                NestLinkAccountPage(account: account),
              ]);
              return Column(children: [
                Expanded(
                    child: Row(children: [
                  Offstage(
                      offstage: !signedIn || mobile,
                      child: HomeDeskNavigation(
                          brand: 'nestlink',
                          compact: compact,
                          selected: _page.name,
                          onSelected: _navigate,
                          services: widget.servicesBuilder != null,
                          account: account)),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                        if (signedIn)
                          Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(24, 22, 24, 20),
                              child: Row(children: [
                                Expanded(
                                    child: Text(title, style: t.titleStyle)),
                                if (!Platform.isAndroid && !Platform.isIOS)
                                  IconButton(
                                      tooltip: nl('本机共享', 'Share this device'),
                                      onPressed: _showLocal,
                                      icon: const Icon(
                                          Icons.screen_share_outlined)),
                                if (compact)
                                  IconButton(
                                      tooltip: nl('版本', 'Version'),
                                      onPressed: () =>
                                          showNestLinkVersion(context),
                                      icon: const Icon(Icons.info_outline)),
                              ])),
                        Expanded(
                            child: Padding(
                                padding: EdgeInsets.symmetric(
                                    horizontal:
                                        signedIn ? (compact ? 16 : 24) : 0),
                                child: pages)),
                      ])),
                ])),
                if (signedIn && mobile)
                  NavigationBar(
                      selectedIndex: _page.index.clamp(0, 3),
                      onDestinationSelected: (i) =>
                          _navigate(_DashboardPage.values[i].name),
                      destinations: [
                        NavigationDestination(
                            icon: const Icon(Icons.desktop_windows_outlined),
                            label: nl('远控', 'Remote')),
                        NavigationDestination(
                            icon: const Icon(Icons.hub_outlined),
                            label: nl('穿透', 'Tunnels')),
                        NavigationDestination(
                            icon: const Icon(Icons.devices_outlined),
                            label: nl('设备', 'Devices')),
                        NavigationDestination(
                            icon: const Icon(Icons.settings_outlined),
                            label: nl('设置', 'Settings'))
                      ]),
              ]);
            })));
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
  Widget build(BuildContext context) => AlertDialog(
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
