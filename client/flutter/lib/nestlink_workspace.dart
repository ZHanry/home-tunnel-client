import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';
import 'homedesk_account.dart';
import 'homedesk_theme.dart';
import 'homedesk_tunnel_api.dart';
import 'nestlink_locale.dart';
import 'nestlink_browser_host.dart';
import 'nestlink_dialog.dart';
import 'nestlink_remote_settings.dart';

export 'nestlink_remote_settings.dart' show NestLinkRemoteSettings;

const nestlinkVersion = '14.0.0';
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
  final Widget? localCredentials;
  final Widget? localHost;
  final bool? mobilePlatform;
  final WidgetBuilder? remoteSettingsBuilder;
  final VoidCallback? onManageDevices;
  final Widget recent, status;
  const NestLinkRemoteWorkspace(
      {super.key,
      this.account,
      required this.onConnect,
      this.localCredentials,
      this.localHost,
      this.mobilePlatform,
      this.remoteSettingsBuilder,
      this.onManageDevices,
      required this.recent,
      required this.status});
  @override
  State<NestLinkRemoteWorkspace> createState() =>
      NestLinkRemoteWorkspaceState();
}

class NestLinkRemoteWorkspaceState extends State<NestLinkRemoteWorkspace> {
  final _id = TextEditingController();
  final _focus = FocusNode();
  final _settingsKey = GlobalKey();
  bool _showSettings = false;
  String _error = '';
  Object? _owner;

  @override
  void initState() {
    super.initState();
    _owner = widget.account?.api;
  }

  @override
  void didUpdateWidget(covariant NestLinkRemoteWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(_owner, widget.account?.api)) {
      _owner = widget.account?.api;
      _id.clear();
      _error = '';
      _showSettings = false;
    }
  }

  void showSettings() {
    setState(() => _showSettings = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _settingsKey.currentContext;
      if (mounted && target != null) Scrollable.ensureVisible(target);
    });
  }

  Widget _settings() => Padding(
      key: _settingsKey,
      padding: const EdgeInsets.only(top: 20),
      child: KeyedSubtree(
          // A new session must never inherit password drafts or save feedback.
          key: ObjectKey(widget.account?.api),
          child: widget.remoteSettingsBuilder?.call(context) ??
              NestLinkRemoteSettings(
                  account: widget.account,
                  mobilePlatform: widget.mobilePlatform)));

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

  Widget _panel(BuildContext context,
      {required Key key,
      required String title,
      String? description,
      Widget? trailing,
      required Widget child}) {
    final t = HomeDeskTokens.of(context);
    return Card(
        key: key,
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(child: Text(title, style: t.sectionStyle)),
                      if (trailing != null) trailing,
                    ]),
                    if (description != null) ...[
                      const SizedBox(height: 6),
                      Text(description, style: t.auxiliaryStyle),
                    ],
                  ])),
          Divider(height: 1, color: t.border),
          Padding(padding: const EdgeInsets.all(20), child: child),
        ]));
  }

  @override
  Widget build(BuildContext context) {
    final t = HomeDeskTokens.of(context);
    final localBinding =
        widget.account?.bindings[widget.account?.localDeviceId];
    final localId = localBinding?.remoteId ?? '';
    final mobile =
        widget.mobilePlatform ?? (Platform.isAndroid || Platform.isIOS);
    final connect = _panel(context,
        key: const ValueKey('remote-partner-panel'),
        title: nl('远控伙伴设备', 'Connect to a partner device'),
        description: nl('输入对方的设备 ID，发起远程连接。',
            'Enter their device ID to start a remote connection.'),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          LayoutBuilder(builder: (context, constraints) {
            final controlHeight = homeDeskControlHeight(context, minimum: 48);
            final field = TextField(
                key: const ValueKey('remote-device-id'),
                controller: _id,
                focusNode: _focus,
                autocorrect: false,
                enableSuggestions: false,
                textAlignVertical: TextAlignVertical.center,
                style: TextStyle(
                    fontSize: 16,
                    height: 1.5,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 1,
                    color: t.text),
                onSubmitted: (_) => _connect(),
                onChanged: (_) {
                  if (_error.isNotEmpty) setState(() => _error = '');
                },
                decoration: InputDecoration(
                  constraints: BoxConstraints.tightFor(height: controlHeight),
                  contentPadding: EdgeInsets.symmetric(
                      horizontal: 12, vertical: controlHeight / 4),
                  hintStyle:
                      TextStyle(fontSize: 16, height: 1.5, color: t.secondary),
                  hintText: nl('输入对方的设备 ID', 'Enter their device ID'),
                ));
            final button = FilledButton(
                key: const ValueKey('remote-connect'),
                onPressed: _connect,
                child: Text(nl('连接', 'Connect')));
            if (constraints.maxWidth >= 500 &&
                MediaQuery.textScalerOf(context).scale(1) <= 1.35) {
              return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 320, child: field),
                    const SizedBox(width: 12),
                    SizedBox(width: 124, height: controlHeight, child: button),
                  ]);
            }
            return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  field,
                  const SizedBox(height: 12),
                  SizedBox(height: controlHeight, child: button),
                ]);
          }),
          if (_error.isNotEmpty)
            Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error))),
          const SizedBox(height: 20),
          Divider(height: 1, color: t.border),
          const SizedBox(height: 16),
          Text(nl('最近连接', 'Recent connections'), style: t.auxiliaryStyle),
          const SizedBox(height: 12),
          SizedBox(
              height:
                  112 * MediaQuery.textScalerOf(context).scale(1).clamp(1, 2),
              child: widget.recent),
        ]));
    final local = _panel(context,
        key: const ValueKey('remote-local-panel'),
        title: nl('本设备', 'This device'),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          HomeDeskBadge(
              localBinding?.online == true
                  ? nl('在线', 'Online')
                  : nl('登记中', 'Registering'),
              tone: localBinding?.online == true
                  ? HomeDeskTone.success
                  : HomeDeskTone.neutral),
          IconButton(
              key: const ValueKey('remote-settings-toggle'),
              tooltip: nl('远控安全设置', 'Remote security settings'),
              onPressed: () {
                if (_showSettings) {
                  setState(() => _showSettings = false);
                } else {
                  showSettings();
                }
              },
              icon: Icon(
                  _showSettings
                      ? Icons.expand_less_rounded
                      : Icons.settings_outlined,
                  size: 20)),
        ]),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (widget.localHost != null)
            widget.localHost!
          else if (widget.localCredentials != null)
            widget.localCredentials!
          else
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
                              if (context.mounted) {
                                ScaffoldMessenger.maybeOf(context)
                                    ?.showSnackBar(SnackBar(
                                        content: Text(nl(
                                            '设备 ID 已复制', 'Device ID copied'))));
                              }
                            },
                      icon: const Icon(Icons.copy_outlined, size: 18)),
                ])),
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
                            if (status == nl('浏览器已连接', 'Browser connected') ||
                                status == nl('浏览器正在连接', 'Browser connecting'))
                              TextButton(
                                  onPressed: () =>
                                      NestLinkBrowserHost.active?.disconnect(),
                                  child: Text(nl('结束连接', 'End connection'))),
                          ]))),
          if (_showSettings) _settings(),
        ]));
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
            child: SingleChildScrollView(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                  if (!mobile || widget.localHost != null) ...[
                    local,
                    const SizedBox(height: 16),
                  ],
                  connect,
                  if (mobile && widget.localHost == null) ...[
                    TextButton.icon(
                        onPressed: showSettings,
                        icon: const Icon(Icons.settings_outlined),
                        label: Text(nl(
                            '远控密码与授权', 'Remote password and authorization'))),
                    if (_showSettings) _settings(),
                  ],
                  if (mobile && widget.onManageDevices != null)
                    Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: OutlinedButton.icon(
                            onPressed: widget.onManageDevices,
                            icon: const Icon(Icons.devices_outlined),
                            label: Text(nl('管理我的设备', 'Manage my devices')))),
                  const SizedBox(height: 24),
                ]))));
  }
}

class _FocusDeviceIntent extends Intent {
  const _FocusDeviceIntent();
}

Future<void> showNestLinkVersion(BuildContext context) => showDialog<void>(
    context: context,
    builder: (context) => ValueListenableBuilder<Map<String, dynamic>?>(
        valueListenable: nestlinkRelease,
        builder: (context, release, _) => NestLinkDialog(
              title: Row(children: [
                SvgPicture.asset('assets/icon.svg', width: 32, height: 32),
                const SizedBox(width: 12),
                const Expanded(child: Text('NestLink'))
              ]),
              content: Column(
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
                  ]),
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

class NestLinkSettings extends StatelessWidget {
  final HomeDeskAccount? account;
  final VoidCallback? onNetworkSettings;
  final bool embedded;
  const NestLinkSettings(
      {super.key, this.account, this.onNetworkSettings, this.embedded = false});

  @override
  Widget build(BuildContext context) {
    if (onNetworkSettings == null) return const SizedBox.shrink();
    final section = Card(
        child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(nl('网络配置', 'Network configuration'),
                      style: HomeDeskTokens.of(context).sectionStyle),
                  const SizedBox(height: 16),
                  Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                          key: const ValueKey('settings-network'),
                          onPressed: onNetworkSettings,
                          icon: const Icon(Icons.dns_outlined),
                          label: Text(nl('自建服务连接', 'Self-hosted connection')))),
                ])));
    return embedded ? section : ListView(children: [section]);
  }
}
