import 'package:flutter/material.dart';
import 'homedesk_theme.dart';
import 'nestlink_locale.dart';

/// Inline credentials supplied by the existing native server model.
/// Unavailable authorization states never attach the old password controller.
class NestLinkRemoteCredentials extends StatelessWidget {
  final TextEditingController id, password;
  final bool incomingEnabled,
      showTemporaryPassword,
      serviceStopped,
      accountReady;
  final String passwordHint;
  final VoidCallback onCopyId;
  final VoidCallback? onRefreshPassword;
  final Widget? status, warning;

  const NestLinkRemoteCredentials({
    super.key,
    required this.id,
    required this.password,
    required this.incomingEnabled,
    required this.showTemporaryPassword,
    required this.passwordHint,
    required this.onCopyId,
    this.serviceStopped = false,
    this.accountReady = true,
    this.onRefreshPassword,
    this.status,
    this.warning,
  });

  Widget _block(
    BuildContext context, {
    required Key key,
    required String label,
    required Widget value,
    Widget? action,
  }) {
    return Container(
      key: key,
      padding: const EdgeInsets.only(right: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
              child: Text(label,
                  style: HomeDeskTokens.of(context).auxiliaryStyle)),
          if (action != null) action,
        ]),
        value,
      ]),
    );
  }

  Widget _value(
      BuildContext context, TextEditingController controller, bool available,
      {double fontSize = 22}) {
    final t = HomeDeskTokens.of(context);
    if (!available) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(nl('正在获取…', 'Getting credentials…'),
            style: TextStyle(fontSize: 16, color: t.secondary)),
      );
    }
    return TextField(
      controller: controller,
      readOnly: true,
      enableSuggestions: false,
      autocorrect: false,
      style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          color: t.text,
          letterSpacing: 1),
      decoration: const InputDecoration(
        isDense: true,
        filled: false,
        hoverColor: Colors.transparent,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        contentPadding: EdgeInsets.symmetric(vertical: 8),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = HomeDeskTokens.of(context);
    final temporary = showTemporaryPassword && !serviceStopped && accountReady;
    final hint = serviceStopped
        ? nl('远控服务已停止', 'Remote service is stopped')
        : !accountReady
            ? nl('远控尚未就绪', 'Remote control is not ready')
            : passwordHint;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (warning != null) ...[warning!, const SizedBox(height: 12)],
      if (!incomingEnabled)
        Text(
            nl('此客户端不接受远程连接。',
                'This client does not accept remote connections.'),
            style: t.auxiliaryStyle)
      else
        LayoutBuilder(builder: (context, constraints) {
          final device = ValueListenableBuilder<TextEditingValue>(
            valueListenable: id,
            builder: (context, value, _) {
              final available = RegExp(r'^[A-Za-z0-9_-]{1,64}$')
                  .hasMatch(value.text.replaceAll(RegExp(r'\s'), ''));
              return _block(
                context,
                key: const ValueKey('remote-credentials-id'),
                label: nl('本机设备 ID', 'Your device ID'),
                value: _value(context, id, available),
                action: IconButton(
                  key: const ValueKey('remote-credentials-copy-id'),
                  tooltip: nl('复制设备 ID', 'Copy device ID'),
                  onPressed: available ? onCopyId : null,
                  icon: Icon(Icons.copy_outlined, size: 18, color: t.secondary),
                ),
              );
            },
          );
          final verification = temporary
              ? ValueListenableBuilder<TextEditingValue>(
                  valueListenable: password,
                  builder: (context, value, _) => _block(
                    context,
                    key: const ValueKey('remote-credentials-password'),
                    label: nl('一次性密码', 'One-time password'),
                    // Native OTPs contain 6, 8 or 10 letters/digits. Initial model
                    // placeholders and the disabled '-' value are not passwords.
                    value: _value(
                        context,
                        password,
                        RegExp(r'^(?:[A-Za-z0-9]{6}|[A-Za-z0-9]{8}|[A-Za-z0-9]{10})$')
                            .hasMatch(value.text),
                        fontSize: 20),
                    action: onRefreshPassword == null
                        ? null
                        : IconButton(
                            key: const ValueKey(
                                'remote-credentials-refresh-password'),
                            tooltip: nl('刷新一次性密码', 'Refresh one-time password'),
                            onPressed: onRefreshPassword,
                            icon: Icon(Icons.refresh_rounded,
                                size: 21, color: t.secondary),
                          ),
                  ),
                )
              : _block(
                  context,
                  key: const ValueKey('remote-credentials-verification'),
                  label: nl('连接验证', 'Connection verification'),
                  value: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(hint,
                        style: TextStyle(fontSize: 16, color: t.text)),
                  ),
                );
          if (constraints.maxWidth >= 540 &&
              MediaQuery.textScalerOf(context).scale(1) <= 1.35) {
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: device),
              const SizedBox(width: 32),
              Expanded(child: verification),
            ]);
          }
          return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                device,
                const SizedBox(height: 12),
                verification,
              ]);
        }),
      if (status != null) ...[const SizedBox(height: 12), status!],
    ]);
  }
}
