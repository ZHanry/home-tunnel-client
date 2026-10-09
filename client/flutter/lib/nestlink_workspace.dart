import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';
import 'common.dart' show MyTheme;
import 'models/platform_model.dart';
import 'homedesk_account.dart';
import 'homedesk_theme.dart';
import 'homedesk_tunnel_api.dart';
import 'nestlink_locale.dart';
import 'nestlink_browser_host.dart';

const nestlinkVersion = '13.0.0';
final nestlinkRelease = ValueNotifier<Map<String, dynamic>?>(null);

Future<void> checkNestLinkVersion(HomeTunnelApi? api) async {
  if (api == null || !api.isSignedIn) return;
  try {
    final update =
        await api.releaseUpdate(Platform.isAndroid ? 'android' : 'client');
    if (api.isSignedIn) nestlinkRelease.value = update;
  } catch (_) {
    /* The installed version remains usable when a check is unavailable. */
  }
}

class NestLinkScrollBehavior extends MaterialScrollBehavior {
  const NestLinkScrollBehavior();
  @override
  Widget buildScrollbar(
          BuildContext context, Widget child, ScrollableDetails details) =>
      child;
}

class NestLinkRemoteWorkspace extends StatefulWidget {
  final HomeDeskAccount? account;
  final ValueChanged<String> onConnect;
  final VoidCallback onLocal;
  final VoidCallback? onManageDevices;
  final Widget recent, status;
  const NestLinkRemoteWorkspace(
      {super.key,
      this.account,
      required this.onConnect,
      required this.onLocal,
      this.onManageDevices,
      required this.recent,
      required this.status});
  @override
  State<NestLinkRemoteWorkspace> createState() =>
      _NestLinkRemoteWorkspaceState();
}

class _NestLinkRemoteWorkspaceState extends State<NestLinkRemoteWorkspace> {
  final _id = TextEditingController();
  final _focus = FocusNode();
  String _error = '';
  void _connect() {
    final id = _id.text.trim();
    if (!RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(id)) {
      setState(() => _error = nl('请输入有效的设备 ID', 'Enter a valid device ID'));
      return;
    }
    if (widget.account != null && !widget.account!.signedIn) {
      setState(() => _error = nl('请先登录自建服务', 'Sign in to your server first'));
      return;
    }
    setState(() => _error = '');
    widget.onConnect(id);
  }

  @override
  void dispose() {
    _id.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = HomeDeskTokens.of(context);
    final localBinding =
        widget.account?.bindings[widget.account?.localDeviceId];
    final localId = localBinding?.remoteId ?? '';
    final mobile = Platform.isAndroid || Platform.isIOS;
    final connect = Card(
        child: Padding(
            padding: const EdgeInsets.all(24),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.desktop_windows_outlined,
                    color: t.accentText, size: 24),
                const SizedBox(width: 12),
                Expanded(
                    child: Text(nl('连接一台设备', 'Connect to a device'),
                        style: t.sectionStyle)),
              ]),
              const SizedBox(height: 8),
              Text(
                  nl('输入设备 ID。同一服务下，也可以协助其他账号的设备。',
                      'Enter a device ID to connect or assist another account on this server.'),
                  style: t.auxiliaryStyle),
              const SizedBox(height: 24),
              TextField(
                  key: const ValueKey('remote-device-id'),
                  controller: _id,
                  focusNode: _focus,
                  autocorrect: false,
                  enableSuggestions: false,
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 1,
                      color: t.text),
                  onSubmitted: (_) => _connect(),
                  decoration: InputDecoration(
                      labelText: nl('设备 ID', 'Device ID'),
                      hintText: nl('输入对方的设备 ID', 'Enter their device ID'),
                      errorText: _error.isEmpty ? null : _error)),
              const SizedBox(height: 20),
              SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                      key: const ValueKey('remote-connect'),
                      onPressed: _connect,
                      icon: const Icon(Icons.link_rounded),
                      label: Text(nl('发起连接', 'Connect')))),
              const SizedBox(height: 16),
              Text(
                  nl('连接需要对方批准或验证远控密码。',
                      'The host must approve or verify a remote password.'),
                  style: t.auxiliaryStyle),
            ])));
    final local = Card(
        child: Padding(
            padding: const EdgeInsets.all(24),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.screen_share_outlined,
                    color: t.accentText, size: 24),
                const SizedBox(width: 12),
                Expanded(
                    child:
                        Text(nl('这台设备', 'This device'), style: t.sectionStyle)),
                HomeDeskBadge(
                    localBinding?.online == true
                        ? nl('在线', 'Online')
                        : nl('登记中', 'Registering'),
                    tone: localBinding?.online == true
                        ? HomeDeskTone.success
                        : HomeDeskTone.neutral),
              ]),
              const SizedBox(height: 8),
              Text(
                  nl('将设备 ID 发给对方，再批准连接。',
                      'Share your device ID, then approve the connection.'),
                  style: t.auxiliaryStyle),
              const SizedBox(height: 24),
              Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                      color: t.sunken, borderRadius: BorderRadius.circular(10)),
                  child: Row(children: [
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(nl('本机设备 ID', 'Your device ID'),
                              style: t.auxiliaryStyle),
                          const SizedBox(height: 4),
                          SelectableText(
                              localId.isEmpty
                                  ? nl('正在获取…', 'Getting ID…')
                                  : localId,
                              key: const ValueKey('workspace-local-id'),
                              style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 1.2,
                                  color: t.text)),
                        ])),
                    IconButton(
                        key: const ValueKey('workspace-copy-id'),
                        tooltip: nl('复制设备 ID', 'Copy device ID'),
                        onPressed: localId.isEmpty
                            ? null
                            : () async {
                                await Clipboard.setData(
                                    ClipboardData(text: localId));
                                if (context.mounted)
                                  ScaffoldMessenger.maybeOf(context)
                                      ?.showSnackBar(SnackBar(
                                          content: Text(nl('设备 ID 已复制',
                                              'Device ID copied'))));
                              },
                        icon: const Icon(Icons.copy_outlined, size: 18)),
                  ])),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                  onPressed: widget.onLocal,
                  icon: const Icon(Icons.screen_share_outlined),
                  label: Text(nl('共享与授权', 'Sharing and permissions'))),
              const SizedBox(height: 16),
              Row(children: [
                Icon(Icons.verified_user_outlined, color: t.success, size: 18),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(
                        nl('远控使用加密 P2P 直连', 'Encrypted P2P remote control'),
                        style: t.auxiliaryStyle))
              ]),
              const SizedBox(height: 12),
              widget.status,
              ValueListenableBuilder<String>(
                  valueListenable: nestlinkBrowserStatus,
                  builder: (context, status, _) => status.isEmpty
                      ? const SizedBox.shrink()
                      : Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Wrap(
                              spacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(status, style: t.auxiliaryStyle),
                                if (status ==
                                        nl('浏览器已连接', 'Browser connected') ||
                                    status ==
                                        nl('浏览器正在连接', 'Browser connecting'))
                                  TextButton(
                                      onPressed: () => NestLinkBrowserHost
                                          .active
                                          ?.disconnect(),
                                      child:
                                          Text(nl('结束连接', 'End connection'))),
                              ]))),
            ])));
    final recent = Card(
        child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(nl('最近连接', 'Recent connections'), style: t.sectionStyle),
                  const SizedBox(height: 16),
                  Expanded(child: widget.recent),
                ])));
    return Shortcuts(
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.keyL, control: true):
              _FocusDeviceIntent()
        },
        child: Actions(
            actions: {
              _FocusDeviceIntent:
                  CallbackAction<_FocusDeviceIntent>(onInvoke: (_) {
                _focus.requestFocus();
                _id.selection =
                    TextSelection(baseOffset: 0, extentOffset: _id.text.length);
                return null;
              })
            },
            child: LayoutBuilder(builder: (context, c) {
              final wide = !mobile &&
                  c.maxWidth >= 720 &&
                  MediaQuery.textScalerOf(context).scale(1) <= 1.35;
              final panels = wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                          Expanded(flex: 6, child: connect),
                          const SizedBox(width: 20),
                          Expanded(flex: 5, child: local),
                        ])
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                          connect,
                          if (!mobile) ...[
                            const SizedBox(height: 16),
                            local
                          ] else if (widget.onManageDevices != null)
                            Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: OutlinedButton.icon(
                                    onPressed: widget.onManageDevices,
                                    icon: const Icon(Icons.devices_outlined),
                                    label: Text(
                                        nl('管理我的设备', 'Manage my devices'))))
                        ]);
              // At normal desktop sizes the recent list owns scrolling; short windows retain all controls.
              if (wide && c.maxHeight >= 620) {
                return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      panels,
                      const SizedBox(height: 16),
                      Expanded(child: recent),
                      const SizedBox(height: 16)
                    ]);
              }
              return SingleChildScrollView(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                    panels,
                    const SizedBox(height: 20),
                    SizedBox(
                        height: wide
                            ? (c.maxHeight - 365).clamp(260.0, 520.0)
                            : 350,
                        child: recent),
                    const SizedBox(height: 20),
                  ]));
            })));
  }
}

class _FocusDeviceIntent extends Intent {
  const _FocusDeviceIntent();
}

Future<void> showNestLinkVersion(BuildContext context) => showDialog<void>(
    context: context,
    builder: (context) => ValueListenableBuilder<Map<String, dynamic>?>(
        valueListenable: nestlinkRelease,
        builder: (context, release, _) => AlertDialog(
              title: Row(children: [
                SvgPicture.asset('assets/icon.svg', width: 32, height: 32),
                const SizedBox(width: 12),
                const Expanded(child: Text('nestlink'))
              ]),
              content: SizedBox(
                  width: 420,
                  child: SingleChildScrollView(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                        const SelectableText(nestlinkVersion),
                        const SizedBox(height: 16),
                        Text(nl('统一的设备工作台，支持内网穿透与加密 P2P 远控。',
                            'Your device workspace for tunneling and encrypted P2P remote control.')),
                        const SizedBox(height: 16),
                        if (release != null) ...[
                          Text(
                              '${nl('可用版本', 'Available version')}: ${release['version']}'),
                          const SizedBox(height: 12),
                          SelectableText(release['notes'] as String)
                        ] else
                          Text(nl('暂时无法检查更新。可在发行页面查看版本说明。',
                              'Updates are unavailable. View release notes on the release page.')),
                      ]))),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(nl('关闭', 'Close'))),
                FilledButton(
                    onPressed: () => launchUrl(
                        Uri.parse(release?['url'] as String? ??
                            'https://github.com/ZHanry/${Platform.isAndroid ? 'home-tunnel-android' : 'home-tunnel-client'}/releases'),
                        mode: LaunchMode.externalApplication),
                    child: Text(nl('版本与下载', 'Release notes and download')))
              ],
            )));

class NestLinkSettings extends StatefulWidget {
  final HomeDeskAccount? account;
  final VoidCallback onSharing;
  final VoidCallback onAccount;
  const NestLinkSettings(
      {super.key,
      this.account,
      required this.onSharing,
      required this.onAccount});
  @override
  State<NestLinkSettings> createState() => _NestLinkSettingsState();
}

class _NestLinkSettingsState extends State<NestLinkSettings> {
  final _password = TextEditingController();
  bool _busy = false;
  String _message = '';
  String _approval = 'click';
  @override
  void initState() {
    super.initState();
    if (widget.account?.signedIn == true) {
      try {
        final value = bind.mainGetOptionSync(key: 'approve-mode');
        if (['click', 'password', 'both'].contains(value)) _approval = value;
      } catch (_) {
        /* The initial login may still be registering the native core. */
      }
    }
  }

  Future<void> _saveApproval(String? value) async {
    if (value == null || _busy) return;
    if (!bind.mainNestlinkAccountReady()) {
      setState(() => _message =
          nl('请等待远控服务就绪', 'Wait for remote authorization to be ready'));
      return;
    }
    setState(() => _busy = true);
    try {
      await bind.mainSetOption(key: 'approve-mode', value: value);
      if (mounted)
        setState(() {
          _approval = value;
          _message = '';
        });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _savePassword() async {
    if (_password.text.length < 6 || _password.text.length > 128) {
      setState(() => _message = '远控密码需要 6 到 128 个字符');
      return;
    }
    setState(() => _busy = true);
    try {
      final ok = await bind.mainSetPermanentPasswordWithResult(
          password: _password.text);
      if (!mounted) return;
      setState(() => _message = ok ? '远控密码已保存' : '远控密码保存失败，请稍后重试');
      _password.clear();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = HomeDeskTokens.of(context);
    Widget section(String title, List<Widget> content) => Card(
        child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(title, style: t.sectionStyle),
                  const SizedBox(height: 16),
                  ...content,
                ])));
    return ListView(children: [
      section(nl('连接与共享', 'Connections and sharing'), [
        Text(
            nl('每次远控都需要账号登录、短期连接许可和被控端授权。',
                'Every remote connection requires account login, a short-lived permit and host authorization.'),
            style: t.auxiliaryStyle),
        const SizedBox(height: 16),
        Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
                onPressed: widget.onSharing,
                icon: const Icon(Icons.screen_share_outlined),
                label: Text(nl('本机共享与授权', 'Sharing and permissions')))),
        const SizedBox(height: 20),
        DropdownButtonFormField<String>(
            value: _approval,
            decoration:
                InputDecoration(labelText: nl('被控端授权方式', 'Host authorization')),
            items: [
              DropdownMenuItem(
                  value: 'click',
                  child: Text(nl('每次由本机批准', 'Approve on this device'))),
              DropdownMenuItem(
                  value: 'password',
                  child: Text(nl('验证远控密码', 'Verify remote password'))),
              DropdownMenuItem(
                  value: 'both',
                  child: Text(nl('本机批准或验证密码', 'Approve or verify password')))
            ],
            onChanged: _busy ? null : _saveApproval),
        const SizedBox(height: 20),
        TextField(
            controller: _password,
            obscureText: true,
            enableSuggestions: false,
            autocorrect: false,
            decoration: InputDecoration(
                labelText: nl('设置远控密码', 'Set remote password'))),
        const SizedBox(height: 16),
        Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
                onPressed: _busy ? null : _savePassword,
                child: Text(nl('保存远控密码', 'Save remote password')))),
        if (_message.isNotEmpty)
          Padding(
              padding: const EdgeInsets.only(top: 12), child: Text(_message)),
      ]),
      const SizedBox(height: 20),
      section(nl('外观', 'Appearance'), [
        Wrap(spacing: 12, runSpacing: 12, children: [
          OutlinedButton.icon(
              onPressed: () => MyTheme.changeDarkMode(ThemeMode.light),
              icon: const Icon(Icons.light_mode_outlined),
              label: Text(nl('浅色', 'Light'))),
          OutlinedButton.icon(
              onPressed: () => MyTheme.changeDarkMode(ThemeMode.dark),
              icon: const Icon(Icons.dark_mode_outlined),
              label: Text(nl('深色', 'Dark'))),
          OutlinedButton.icon(
              onPressed: () => MyTheme.changeDarkMode(ThemeMode.system),
              icon: const Icon(Icons.brightness_auto_outlined),
              label: Text(nl('跟随系统', 'System'))),
        ])
      ]),
      const SizedBox(height: 20),
      section(nl('账号', 'Account'), [
        Text(
            widget.account?.displayName ?? nl('自建服务账号', 'Self-hosted account')),
        const SizedBox(height: 8),
        if (widget.account?.api != null)
          SelectableText(widget.account!.api!.base.origin),
        const SizedBox(height: 16),
        Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
                onPressed: widget.onAccount,
                child: Text(nl('密码、额度与会话', 'Password, quota and sessions')))),
      ]),
      const SizedBox(height: 20),
      section(nl('语言', 'Language'), [
        DropdownButtonFormField<String>(
            value: nestlinkLanguage.value,
            items: const [
              DropdownMenuItem(value: 'zh-cn', child: Text('简体中文')),
              DropdownMenuItem(value: 'en', child: Text('English'))
            ],
            onChanged: (value) {
              if (value != null) setNestLinkLanguage(value);
            })
      ]),
      const SizedBox(height: 20),
      section(nl('版本', 'Version'), [
        ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('nestlink'),
            subtitle: const Text(nestlinkVersion),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => showNestLinkVersion(context))
      ]),
      const SizedBox(height: 24),
    ]);
  }
}
