// HOMEDESK: 本机信息的展示组件；凭据和操作由既有服务模型提供。
import 'package:flutter/material.dart';
import 'homedesk_theme.dart';

class HomeDeskLocalInfo extends StatefulWidget {
  final TextEditingController id;
  final TextEditingController password;
  final bool incomingEnabled;
  final bool showTemporaryPassword;
  final String passwordHint;
  final VoidCallback onCopyId;
  final VoidCallback? onRefreshPassword;
  final VoidCallback? onPasswordSettings;
  final VoidCallback? onInstall;
  final Widget? warning;
  final Widget? additionalHelp;
  final Widget? pluginEntry;
  final Widget status;

  const HomeDeskLocalInfo(
      {super.key,
      required this.id,
      required this.password,
      required this.incomingEnabled,
      required this.showTemporaryPassword,
      required this.passwordHint,
      required this.onCopyId,
      required this.status,
      this.onRefreshPassword,
      this.onPasswordSettings,
      this.onInstall,
      this.warning,
      this.additionalHelp,
      this.pluginEntry});

  @override
  State<HomeDeskLocalInfo> createState() => _HomeDeskLocalInfoState();
}

class _HomeDeskLocalInfoState extends State<HomeDeskLocalInfo> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Widget _credential(
      {required String label,
      required Key key,
      TextEditingController? controller,
      String? text,
      required List<Widget> actions,
      double fontSize = 22}) {
    final colors = Theme.of(context).colorScheme;
    return Container(
        key: key,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
        decoration: BoxDecoration(
            color: HomeDeskTokens.of(context).sunken,
            border: Border.all(color: colors.outlineVariant),
            borderRadius: BorderRadius.circular(HomeDeskTokens.blockRadius)),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
                child: Text(label,
                    style: TextStyle(
                        fontSize: 13, color: colors.onSurfaceVariant))),
            ...actions,
          ]),
          if (controller != null)
            TextField(
                controller: controller,
                readOnly: true,
                enableSuggestions: false,
                autocorrect: false,
                style: TextStyle(
                    fontSize: fontSize,
                    fontWeight: FontWeight.w600,
                    color: colors.onSurface),
                decoration: const InputDecoration(
                    isDense: true,
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 8)))
          else
            Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(text ?? '',
                    style: TextStyle(fontSize: 16, color: colors.onSurface))),
        ]));
  }

  Widget _credentials(BuildContext context) {
    final id = _credential(
        label: '设备 ID',
        key: const ValueKey('local-info-id'),
        controller: widget.id,
        actions: [
          ValueListenableBuilder<TextEditingValue>(
              valueListenable: widget.id,
              builder: (context, value, _) => IconButton(
                  key: const ValueKey('local-info-copy-id'),
                  tooltip: '复制设备 ID',
                  onPressed: value.text.trim().isEmpty ? null : widget.onCopyId,
                  icon: const Icon(Icons.copy_rounded, size: 18)))
        ]);
    final password = _credential(
        key: const ValueKey('local-info-password'),
        label: widget.showTemporaryPassword ? '一次性密码' : '连接验证',
        controller: widget.showTemporaryPassword ? widget.password : null,
        text: widget.passwordHint,
        fontSize: 20,
        actions: [
          if (widget.showTemporaryPassword && widget.onRefreshPassword != null)
            IconButton(
                key: const ValueKey('local-info-refresh-password'),
                tooltip: '刷新一次性密码',
                onPressed: widget.onRefreshPassword,
                icon: const Icon(Icons.refresh_rounded, size: 21)),
          if (widget.onPasswordSettings != null)
            IconButton(
                key: const ValueKey('local-info-password-settings'),
                tooltip: '密码与连接权限',
                onPressed: widget.onPasswordSettings,
                icon: const Icon(Icons.tune_rounded, size: 20)),
        ]);
    return LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth >= 480 &&
          MediaQuery.textScalerOf(context).scale(14) <= 20) {
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: id),
          const SizedBox(width: 12),
          Expanded(child: password),
        ]);
      }
      return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [id, const SizedBox(height: 12), password]);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scrollbar(
        controller: _scroll,
        thumbVisibility: true,
        child: SingleChildScrollView(
            key: const ValueKey('local-info-scroll'),
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(HomeDeskTokens.dialogPadding, 4,
                HomeDeskTokens.dialogPadding, HomeDeskTokens.dialogPadding),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.warning != null) widget.warning!,
                  Text(
                      widget.incomingEnabled
                          ? '在另一台电脑输入下方设备 ID，即可发起远程连接。'
                          : '此客户端仅用于连接其他电脑，不接受远程连接。',
                      style: TextStyle(
                          color: colors.onSurfaceVariant, fontSize: 13)),
                  if (widget.incomingEnabled) ...[
                    const SizedBox(height: 16),
                    _credentials(context),
                  ],
                  const SizedBox(height: 12),
                  widget.status,
                  if (widget.onInstall != null) ...[
                    const SizedBox(height: 12),
                    Container(
                        key: const ValueKey('local-info-portable'),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                            color: HomeDeskTokens.of(context).accentSoft,
                            borderRadius: BorderRadius.circular(
                                HomeDeskTokens.blockRadius),
                            border: Border.all(color: colors.outlineVariant)),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Icon(Icons.info_outline_rounded,
                                    size: 18, color: colors.primary),
                                const SizedBox(width: 8),
                                const Expanded(
                                    child: Text('便携运行',
                                        style: TextStyle(
                                            fontWeight: FontWeight.w600))),
                              ]),
                              const SizedBox(height: 8),
                              Text(
                                  widget.incomingEnabled
                                      ? '便携版在系统权限窗口或管理员程序中可能无法操作。长期作为被控端，建议安装到系统。'
                                      : '无需安装即可主动连接其他电脑，也可以安装到系统后使用。',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: colors.onSurfaceVariant)),
                              const SizedBox(height: 10),
                              OutlinedButton.icon(
                                  key: const ValueKey('local-info-install'),
                                  onPressed: widget.onInstall,
                                  icon: const Icon(
                                      Icons.install_desktop_rounded,
                                      size: 18),
                                  label: const Text('安装到系统')),
                            ])),
                  ],
                  if (widget.additionalHelp != null) widget.additionalHelp!,
                  if (widget.pluginEntry != null) widget.pluginEntry!,
                ])));
  }
}
