// HOMEDESK: 家庭设备中心布局独立于远控协议和上游页面逻辑。
import 'package:flutter/material.dart';
import 'homedesk_theme.dart';

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
      this.initializeAccount = false});

  @override
  State<HomeDeskDashboard> createState() => HomeDeskDashboardState();
}

class HomeDeskDashboardState extends State<HomeDeskDashboard> {
  _DashboardPage _page = _DashboardPage.devices;
  final Set<_DashboardPage> _initializedPages = {_DashboardPage.devices};
  ThemeData? _dialogTheme;

  @override
  void initState() {
    super.initState();
    if (widget.initializeAccount && widget.servicesBuilder != null) {
      _initializedPages.add(_DashboardPage.services);
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
      BuildContext context, _DashboardPage page, WidgetBuilder? builder) {
    // 未记住登录时不请求账号 API；生产首页可恢复此前明确保存的会话。
    if (!_initializedPages.contains(page) || builder == null) {
      return const SizedBox.shrink();
    }
    return TickerMode(
        enabled: _page == page,
        child: KeyedSubtree(key: ValueKey(page), child: builder(context)));
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
                                            fontSize: 20,
                                            fontWeight: FontWeight.w700))),
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

  Widget _nav(BuildContext context, IconData icon, String label,
      VoidCallback onPressed, bool compact,
      {bool selected = false}) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Tooltip(
          message: label,
          child: TextButton(
            style: TextButton.styleFrom(
              foregroundColor: selected
                  ? colors.onPrimaryContainer
                  : colors.onSurfaceVariant,
              backgroundColor:
                  selected ? colors.primaryContainer : Colors.transparent,
              minimumSize: const Size(double.infinity, 48),
              padding: EdgeInsets.symmetric(
                  horizontal: compact ? 8 : 14, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: onPressed,
            child: Row(
                mainAxisAlignment: compact
                    ? MainAxisAlignment.center
                    : MainAxisAlignment.start,
                children: [
                  Icon(icon, size: 22),
                  if (!compact) ...[
                    const SizedBox(width: 12),
                    Flexible(
                        child: Text(label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 14))),
                  ]
                ]),
          ),
        ));
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final theme = homeDeskTheme(Theme.of(context));
    final colors = theme.colorScheme;
    _dialogTheme = theme;
    return Theme(
        data: theme,
        child: Builder(
            builder: (context) => LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 840 ||
                        MediaQuery.textScalerOf(context).scale(1) > 1.5;
                    final railWidth = compact ? 72.0 : 188.0;
                    return ColoredBox(
                      color: dark
                          ? const Color(0xFF131923)
                          : const Color(0xFFF4F6FB),
                      child: Row(children: [
                        Container(
                          width: railWidth,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                              color: colors.surface,
                              border: Border(
                                  right: BorderSide(
                                      color: colors.outlineVariant))),
                          child: Column(children: [
                            Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 18),
                                child: Row(
                                  mainAxisAlignment: compact
                                      ? MainAxisAlignment.center
                                      : MainAxisAlignment.start,
                                  children: [
                                    Container(
                                        width: 38,
                                        height: 38,
                                        decoration: BoxDecoration(
                                            color: colors.primary,
                                            borderRadius:
                                                BorderRadius.circular(12)),
                                        child: Icon(Icons.home_rounded,
                                            color: colors.onPrimary, size: 24)),
                                    if (!compact) ...[
                                      const SizedBox(width: 10),
                                      Expanded(
                                          child: Text(widget.brandName,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.w700)))
                                    ],
                                  ],
                                )),
                            const SizedBox(height: 22),
                            _nav(
                                context,
                                Icons.devices_rounded,
                                '家庭设备',
                                () => _selectPage(_DashboardPage.devices),
                                compact,
                                selected: _page == _DashboardPage.devices),
                            _nav(
                                context,
                                Icons.history_rounded,
                                '最近连接',
                                () => _selectPage(_DashboardPage.recent),
                                compact,
                                selected: _page == _DashboardPage.recent),
                            if (widget.servicesBuilder != null)
                              _nav(
                                  context,
                                  Icons.apps_rounded,
                                  '家庭服务',
                                  () => _selectPage(_DashboardPage.services),
                                  compact,
                                  selected: _page == _DashboardPage.services),
                            const Spacer(),
                            _nav(context, Icons.computer_rounded, '本机信息',
                                _showLocal, compact),
                            _nav(context, Icons.settings_outlined, '设置',
                                widget.onSettings, compact),
                            const SizedBox(height: 10),
                          ]),
                        ),
                        Expanded(
                            child: Column(children: [
                          Padding(
                              padding: EdgeInsets.fromLTRB(
                                  compact ? 18 : 28, 22, compact ? 18 : 28, 18),
                              child: LayoutBuilder(builder: (context, header) {
                                final title = Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                          switch (_page) {
                                            _DashboardPage.devices => '家庭设备',
                                            _DashboardPage.recent => '最近连接',
                                            _DashboardPage.services => '家庭服务',
                                          },
                                          style: const TextStyle(
                                              fontSize: 26,
                                              fontWeight: FontWeight.w700)),
                                      const SizedBox(height: 6),
                                      Text(
                                          switch (_page) {
                                            _DashboardPage.devices =>
                                              '家里的电脑，在这里轻松连接',
                                            _DashboardPage.recent =>
                                              '快速回到上次使用的电脑',
                                            _DashboardPage.services =>
                                              '查看设备上的服务，打开你的访问地址',
                                          },
                                          style: TextStyle(
                                              fontSize: 13,
                                              color: colors.onSurfaceVariant)),
                                    ]);
                                final action = OutlinedButton.icon(
                                    onPressed: showManualConnection,
                                    icon:
                                        const Icon(Icons.add_rounded, size: 20),
                                    label: const Text('手动连接'));
                                if (_page == _DashboardPage.services) {
                                  return Align(
                                      alignment: Alignment.centerLeft,
                                      child: title);
                                }
                                if (header.maxWidth < 530 ||
                                    MediaQuery.textScalerOf(context).scale(1) >
                                        1.5) {
                                  return Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        title,
                                        const SizedBox(height: 14),
                                        action
                                      ]);
                                }
                                return Row(children: [
                                  Expanded(child: title),
                                  const SizedBox(width: 16),
                                  action
                                ]);
                              })),
                          Expanded(
                              child: Padding(
                                  padding: EdgeInsets.symmetric(
                                      horizontal: compact ? 18 : 28),
                                  child: IndexedStack(
                                    index: _page.index,
                                    children: [
                                      _buildPage(
                                          context,
                                          _DashboardPage.devices,
                                          widget.devicesBuilder),
                                      _buildPage(context, _DashboardPage.recent,
                                          widget.recentBuilder),
                                      _buildPage(
                                          context,
                                          _DashboardPage.services,
                                          widget.servicesBuilder),
                                    ],
                                  ))),
                          if (_page == _DashboardPage.devices)
                            Container(
                                margin:
                                    const EdgeInsets.fromLTRB(18, 12, 18, 12),
                                decoration: BoxDecoration(
                                    color: colors.surface,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                        color: colors.outlineVariant)),
                                child: Row(children: [
                                  Expanded(
                                      child: widget.statusBuilder(context)),
                                  if (!compact)
                                    TextButton.icon(
                                        onPressed: widget.onNetworkSettings ??
                                            widget.onSettings,
                                        icon: const Icon(Icons.tune_rounded,
                                            size: 18),
                                        label: const Text('网络设置'))
                                  else
                                    IconButton(
                                        tooltip: '检查网络设置',
                                        onPressed: widget.onNetworkSettings ??
                                            widget.onSettings,
                                        icon: const Icon(Icons.tune_rounded,
                                            size: 19)),
                                ])),
                        ])),
                      ]),
                    );
                  },
                )));
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
                  TextField(
                      controller: _controller,
                      autofocus: true,
                      onSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                          labelText: '设备 ID / 内网 IP',
                          errorText: _error,
                          border: const OutlineInputBorder())),
                ])),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(onPressed: _submit, child: const Text('连接设备'))
        ],
      );
}
