// HOMEDESK: 家庭设备中心布局独立于远控协议和上游页面逻辑。
import 'package:flutter/material.dart';

class HomeDeskDashboard extends StatefulWidget {
  final String brandName;
  final WidgetBuilder devicesBuilder;
  final WidgetBuilder recentBuilder;
  final WidgetBuilder localBuilder;
  final WidgetBuilder statusBuilder;
  final VoidCallback onSettings;
  final VoidCallback? onNetworkSettings;
  final ValueChanged<String> onConnect;
  const HomeDeskDashboard(
      {super.key,
      required this.brandName,
      required this.devicesBuilder,
      required this.recentBuilder,
      required this.localBuilder,
      required this.statusBuilder,
      required this.onSettings,
      required this.onConnect,
      this.onNetworkSettings});

  @override
  State<HomeDeskDashboard> createState() => HomeDeskDashboardState();
}

class HomeDeskDashboardState extends State<HomeDeskDashboard> {
  bool _recent = false;
  ThemeData? _dialogTheme;

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
        builder: (context) => Dialog(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                    maxWidth: 360,
                    maxHeight: MediaQuery.sizeOf(context).height * .85),
                child: Column(children: [
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
                  Expanded(child: Center(child: widget.localBuilder(context))),
                ]),
              ),
            ));
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
    final colors = ColorScheme.fromSeed(
            seedColor: const Color(0xFF4C6FFF),
            brightness: dark ? Brightness.dark : Brightness.light)
        .copyWith(
      surface: dark ? const Color(0xFF1B2230) : Colors.white,
      onSurface: dark ? const Color(0xFFE8EEF8) : const Color(0xFF202C40),
      onSurfaceVariant:
          dark ? const Color(0xFFA8B5CB) : const Color(0xFF65748C),
      outlineVariant: dark ? const Color(0xFF303B50) : const Color(0xFFE0E6F0),
    );
    final theme = Theme.of(context).copyWith(
      colorScheme: colors,
      cardTheme: CardTheme(
          color: colors.surface,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(color: colors.outlineVariant))),
      filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
              minimumSize: const Size(0, 44),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(11)))),
      outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 44),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(11)))),
    );
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
                            _nav(context, Icons.devices_rounded, '家庭设备',
                                () => setState(() => _recent = false), compact,
                                selected: !_recent),
                            _nav(context, Icons.history_rounded, '最近连接',
                                () => setState(() => _recent = true), compact,
                                selected: _recent),
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
                                      Text(_recent ? '最近连接' : '家庭设备',
                                          style: const TextStyle(
                                              fontSize: 26,
                                              fontWeight: FontWeight.w700)),
                                      const SizedBox(height: 6),
                                      Text(
                                          _recent
                                              ? '快速回到上次使用的电脑'
                                              : '家里的电脑，在这里轻松连接',
                                          style: TextStyle(
                                              fontSize: 13,
                                              color: colors.onSurfaceVariant)),
                                    ]);
                                final action = OutlinedButton.icon(
                                    onPressed: showManualConnection,
                                    icon:
                                        const Icon(Icons.add_rounded, size: 20),
                                    label: const Text('手动连接'));
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
                                  child: _recent
                                      ? widget.recentBuilder(context)
                                      : widget.devicesBuilder(context))),
                          if (!_recent)
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
