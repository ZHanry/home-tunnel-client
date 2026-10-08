// HOMEDESK: 家庭设备中心布局独立于远控协议和上游页面逻辑。
import 'package:flutter/material.dart';
import 'homedesk_theme.dart';
import 'homedesk_navigation.dart';
import 'homedesk_family_devices.dart';
import 'homedesk_services.dart';
import 'homedesk_recent.dart';
import 'homedesk_status.dart';
import 'homedesk_account.dart';

enum _DashboardPage { devices, recent, services }

class HomeDeskDashboard extends StatefulWidget {
  final String brandName;
  final WidgetBuilder devicesBuilder;
  final WidgetBuilder recentBuilder;
  final WidgetBuilder? servicesBuilder;
  final WidgetBuilder localBuilder;
  final WidgetBuilder statusBuilder;
  final VoidCallback onSettings;
  final VoidCallback? onNetworkSettings;
  final ValueChanged<String> onConnect;
  final bool initializeAccount;
  final HomeDeskStatusData? statusData;
  final WidgetBuilder? recentSummaryBuilder;
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
  _DashboardPage _page = _DashboardPage.devices;
  final Set<_DashboardPage> _initializedPages = {_DashboardPage.devices};
  ThemeData? _dialogTheme;
  HomeDeskAccount? navigationAccount;

  @override
  void initState() {
    super.initState();
    HomeDeskDashboard.active = this;
    if (widget.initializeAccount && widget.servicesBuilder != null) {
      _initializedPages.add(_DashboardPage.services);
    }
  }

  @override
  void dispose() {
    if (identical(HomeDeskDashboard.active, this)) {
      HomeDeskDashboard.active = null;
    }
    super.dispose();
  }

  void _navigate(String destination) {
    switch (destination) {
      case 'devices':
        _selectPage(_DashboardPage.devices);
      case 'recent':
        _selectPage(_DashboardPage.recent);
      case 'services':
      case 'account':
        if (widget.servicesBuilder != null) showAccount();
      case 'local':
        _showLocal();
      case 'settings':
        widget.onSettings();
    }
  }

  void showAccount() => _selectPage(_DashboardPage.services);

  void _selectPage(_DashboardPage page) {
    setState(() {
      _page = page;
      _initializedPages.add(page);
    });
  }

  @override
  void didUpdateWidget(covariant HomeDeskDashboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.servicesBuilder == null) {
      _initializedPages.remove(_DashboardPage.services);
      if (_page == _DashboardPage.services) _page = _DashboardPage.devices;
    }
  }

  Widget _buildPage(
      BuildContext context, _DashboardPage page, WidgetBuilder? builder,
      {Widget? built}) {
    // 未记住登录时不请求账号 API；生产首页可恢复此前明确保存的会话。
    if (!_initializedPages.contains(page) || builder == null) {
      return const SizedBox.shrink();
    }
    return TickerMode(
        enabled: _page == page,
        child: KeyedSubtree(
            key: ValueKey(page), child: built ?? builder(context)));
  }

  Future<void> showManualConnection() async {
    final id = await showDialog<String>(
        context: context,
        builder: (dialogContext) => Theme(
            data: _dialogTheme ?? Theme.of(dialogContext),
            child: const _ManualConnectionDialog()));
    if (id != null && id.isNotEmpty && mounted) widget.onConnect(id);
  }

  void _showLocal() {
    showDialog<void>(
        context: context,
        builder: (context) => Theme(
            data: _dialogTheme ?? Theme.of(context),
            child: Dialog(
              insetPadding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                    maxWidth: 560,
                    maxHeight: MediaQuery.sizeOf(context).height - 36),
                child: SizedBox(
                    width: 560,
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                              padding: const EdgeInsets.fromLTRB(20, 12, 8, 8),
                              child: Row(children: [
                                const Expanded(
                                    child: Text('本机信息',
                                        style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w600))),
                                IconButton(
                                    tooltip: '关闭本机信息',
                                    onPressed: () => Navigator.pop(context),
                                    icon: const Icon(Icons.close)),
                              ])),
                          Flexible(child: widget.localBuilder(context)),
                        ])),
              ),
            )));
  }

  @override
  Widget build(BuildContext context) {
    final theme = homeDeskTheme(Theme.of(context));
    _dialogTheme = theme;
    return Theme(
        data: theme,
        child: Builder(builder: (context) {
          final t = HomeDeskTokens.of(context);
          final devices = widget.devicesBuilder(context);
          final services = widget.servicesBuilder?.call(context);
          final account =
              devices is HomeDeskFamilyDevices ? devices.account : null;
          navigationAccount = account;
          Widget status(bool footer) => HomeDeskStatus(
              account: account,
              data: widget.statusData,
              live: widget.initializeAccount,
              footer: footer,
              exceptionOnly: !footer,
              onNetwork: widget.onNetworkSettings ?? widget.onSettings);
          return LayoutBuilder(builder: (context, constraints) {
            final compact = constraints.maxWidth < 960 ||
                MediaQuery.textScalerOf(context).scale(1) > 1.5;
            final inset = compact
                ? HomeDeskTokens.narrowPadding
                : HomeDeskTokens.pagePadding;
            final title = switch (_page) {
              _DashboardPage.devices => '家庭设备',
              _DashboardPage.recent => '最近连接',
              _DashboardPage.services => '家庭服务'
            };
            final subtitle = switch (_page) {
              _DashboardPage.devices => '家里的电脑，在这里轻松连接',
              _DashboardPage.recent => '快速回到上次使用的电脑',
              _DashboardPage.services => '查看设备上的服务，打开你的访问地址'
            };
            return HomeDeskHomeActions(
                onLocal: _showLocal,
                onRecent: () => _selectPage(_DashboardPage.recent),
                recentSummary: widget.recentSummaryBuilder ??
                    (_) => const HomeDeskRecent(summary: true),
                status: (_) => status(false),
                child: ColoredBox(
                    color: t.background,
                    child: Column(children: [
                      Expanded(
                          child: Row(children: [
                        HomeDeskNavigation(
                            brand: widget.brandName,
                            compact: compact,
                            selected: _page.name,
                            onSelected: _navigate,
                            services: widget.servicesBuilder != null,
                            account: account),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                              if (!(_page == _DashboardPage.services &&
                                  services is HomeDeskServices))
                                Padding(
                                    padding: EdgeInsets.fromLTRB(inset, 24,
                                        inset, HomeDeskTokens.moduleGap),
                                    child: LayoutBuilder(builder: (context, c) {
                                      final heading = Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(title, style: t.titleStyle),
                                            const SizedBox(height: 4),
                                            Text(subtitle,
                                                style: t.auxiliaryStyle)
                                          ]);
                                      final action = OutlinedButton.icon(
                                          onPressed: showManualConnection,
                                          icon: const Icon(Icons.add_rounded,
                                              size: 18),
                                          label: const Text('手动连接'));
                                      if (_page == _DashboardPage.services) {
                                        return Align(
                                            alignment: Alignment.centerLeft,
                                            child: heading);
                                      }
                                      if (c.maxWidth < 400 ||
                                          MediaQuery.textScalerOf(context)
                                                  .scale(1) >
                                              1.5) {
                                        return Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              heading,
                                              const SizedBox(height: 12),
                                              action
                                            ]);
                                      }
                                      return Row(children: [
                                        Expanded(child: heading),
                                        const SizedBox(width: 16),
                                        action
                                      ]);
                                    })),
                              Expanded(
                                  child: Padding(
                                      padding: EdgeInsets.symmetric(
                                          horizontal: inset),
                                      child: IndexedStack(
                                          index: _page.index,
                                          children: [
                                            _buildPage(
                                                context,
                                                _DashboardPage.devices,
                                                widget.devicesBuilder,
                                                built: devices),
                                            _buildPage(
                                                context,
                                                _DashboardPage.recent,
                                                widget.recentBuilder),
                                            _buildPage(
                                                context,
                                                _DashboardPage.services,
                                                widget.servicesBuilder,
                                                built: services),
                                          ]))),
                            ])),
                      ])),
                      // 原状态组件继续执行已有状态更新；可见文字使用明确的中文状态栏。
                      Offstage(
                          offstage: true, child: widget.statusBuilder(context)),
                      status(true),
                    ])));
          });
        }));
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
    if (id.isEmpty) {
      setState(() => _error = '请输入设备 ID 或内网 IP');
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
                  const Text('在另一台电脑上打开客户端，输入它的设备 ID 或内网 IP。'),
                  const SizedBox(height: 20),
                  HomeDeskFieldLabel('设备 ID / 内网 IP',
                      child: TextField(
                          controller: _controller,
                          autofocus: true,
                          onSubmitted: (_) => _submit(),
                          decoration: InputDecoration(
                              errorText: _error, hintText: '输入设备 ID 或内网 IP'))),
                ])),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(onPressed: _submit, child: const Text('连接设备'))
        ],
      );
}
