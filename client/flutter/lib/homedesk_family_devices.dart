// HOMEDESK: 同账号设备目录使用设备 UUID 关联远控 ID，继续调用既有远控连接入口。
import 'dart:convert';
import 'package:flutter/material.dart';
import 'homedesk_account.dart';
import 'homedesk_tunnel_api.dart';
import 'homedesk_device_label.dart';
import 'homedesk_theme.dart';
import 'homedesk_navigation.dart';
import 'nestlink_device_list.dart';

class HomeDeskFamilyDevices extends StatefulWidget {
  final HomeDeskAccount account;
  final VoidCallback onLogin;
  final ValueChanged<String> onConnect;
  final VoidCallback? onManualConnect;
  final String Function(String) readOption;
  final WidgetBuilder? lanBuilder;
  final bool listLayout;
  const HomeDeskFamilyDevices(
      {super.key,
      required this.account,
      required this.onLogin,
      required this.onConnect,
      required this.readOption,
      this.onManualConnect,
      this.lanBuilder,
      this.listLayout = false});

  @override
  State<HomeDeskFamilyDevices> createState() => _HomeDeskFamilyDevicesState();
}

class _HomeDeskFamilyDevicesState extends State<HomeDeskFamilyDevices> {
  int _filter = 0;
  HomeDeskAccount get account => widget.account;
  String Function(String) get readOption => widget.readOption;
  bool _matching(HomeDeskRemoteBinding binding) {
    try {
      final profile = jsonDecode(readOption('homedesk-remote-profile'));
      return profile is Map &&
          profile['server'] == binding.server &&
          profile['key_sha256'] == binding.keySHA256;
    } catch (_) {
      return false;
    }
  }

  bool _online(HomeTunnelDevice device) =>
      account.bindings[device.id]?.online == true || device.online;
  bool _needsAttention(HomeTunnelDevice device) =>
      device.id != account.localDeviceId &&
      (account.bindings[device.id] == null ||
          !_matching(account.bindings[device.id]!));
  Widget _card(BuildContext context, HomeTunnelDevice device, double height) {
    final t = HomeDeskTokens.of(context);
    final owner = account.api;
    final binding = account.bindings[device.id];
    final local = account.localDeviceId == device.id;
    final matching = binding != null && _matching(binding);
    final available = binding != null && !local && matching;
    final name =
        device.name.isEmpty ? '未命名设备' : homeDeskDeviceLabel(device.name);
    return SizedBox(
        height: height,
        child: Card(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(HomeDeskTokens.cardRadius),
                side: BorderSide(color: local ? t.accent : t.border)),
            child: Padding(
                padding: const EdgeInsets.all(HomeDeskTokens.cardPadding),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LayoutBuilder(builder: (context, c) {
                        final identity = Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Tooltip(
                                  message: name,
                                  child: Text(name,
                                      key: ValueKey('family-name-${device.id}'),
                                      maxLines: 1,
                                      softWrap: false,
                                      overflow: TextOverflow.ellipsis,
                                      style: t.sectionStyle)),
                              const SizedBox(height: 4),
                              Text(
                                  [
                                    if (device.platform.isNotEmpty)
                                      device.platform.toLowerCase() == 'windows'
                                          ? 'Windows'
                                          : device.platform.toLowerCase() ==
                                                  'linux'
                                              ? 'Linux'
                                              : device.platform,
                                    if (device.tags.isNotEmpty)
                                      device.tags.join(' · ')
                                  ].join(' · '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: t.auxiliaryStyle),
                            ]);
                        final icon = Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                                color: local ? t.accentSoft : t.sunken,
                                borderRadius: BorderRadius.circular(
                                    HomeDeskTokens.blockRadius)),
                            child: Icon(Icons.computer_rounded,
                                color: local ? t.accent : t.secondary));
                        final badge = HomeDeskBadge(
                            local
                                ? '本机'
                                : binding == null
                                    ? '待同步'
                                    : binding.online
                                        ? '账号在线'
                                        : '离线',
                            tone: local
                                ? HomeDeskTone.accent
                                : binding == null
                                    ? HomeDeskTone.warning
                                    : binding.online
                                        ? HomeDeskTone.success
                                        : HomeDeskTone.neutral);
                        if (MediaQuery.textScalerOf(context).scale(1) > 1.5) {
                          return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(children: [icon, const Spacer(), badge]),
                                const SizedBox(height: 12),
                                identity
                              ]);
                        }
                        return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              icon,
                              const SizedBox(width: 12),
                              Expanded(child: identity),
                              const SizedBox(width: 8),
                              badge
                            ]);
                      }),
                      const SizedBox(height: 16),
                      Text(
                          binding == null
                              ? local
                                  ? '本机设备 ID 尚未同步。'
                                  : '远控 ID 尚未同步，请在该设备上运行新版客户端。'
                              : '设备 ID：${binding.remoteId}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: HomeDeskTokens.caption,
                              color: binding == null && !local
                                  ? t.warning
                                  : t.secondary)),
                      if (account.displayName.isNotEmpty)
                        Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text('所属账号：${account.displayName}',
                                key: ValueKey('family-account-${device.id}'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: t.auxiliaryStyle)),
                      if (binding != null && !matching)
                        Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text('这台设备使用不同的远控服务器，请核对网络配置。',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: HomeDeskTokens.caption,
                                    color: t.warning))),
                      const Spacer(),
                      Row(children: [
                        if (local)
                          const Spacer()
                        else
                          Expanded(
                              child: FilledButton(
                                  key: ValueKey('family-connect-${device.id}'),
                                  onPressed: !available
                                      ? null
                                      : () {
                                          final current =
                                              account.bindings[device.id];
                                          if (identical(account.api, owner) &&
                                              account.signedIn &&
                                              current != null &&
                                              current.remoteId ==
                                                  binding.remoteId &&
                                              account.catalog?.devices.any(
                                                      (d) =>
                                                          d.id == device.id) ==
                                                  true &&
                                              _matching(current)) {
                                            widget.onConnect(current.remoteId);
                                          }
                                        },
                                  child: Text(binding != null && !binding.online
                                      ? '尝试连接'
                                      : '连接电脑'))),
                        const SizedBox(width: 8),
                        IconButton(
                            key: ValueKey('family-manage-${device.id}'),
                            tooltip: '管理设备',
                            onPressed: account.editDevice == null
                                ? null
                                : () {
                                    if (identical(account.api, owner) &&
                                        account.signedIn &&
                                        account.catalog?.devices.any(
                                                (d) => d.id == device.id) ==
                                            true) account.editDevice!(device);
                                  },
                            icon:
                                const Icon(Icons.more_horiz_rounded, size: 20)),
                      ]),
                    ]))));
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: account,
      builder: (context, _) {
        final t = HomeDeskTokens.of(context);
        final actions = HomeDeskHomeActions.of(context);
        if (!account.signedIn) {
          if (widget.lanBuilder != null &&
              readOption('homedesk-console-allowed') == 'Y') {
            return widget.lanBuilder!(context);
          }
          return ListView(children: [
            if (actions != null) ...[actions.status(context)],
            Card(
                child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.devices_rounded,
                              size: 40, color: t.accent),
                          const SizedBox(height: 16),
                          Text('登录账号，查看家庭设备', style: t.sectionStyle),
                          const SizedBox(height: 12),
                          Text('同一账号登录的电脑会自动出现在这里，登录一次即可使用家庭设备和家庭服务。',
                              style: t.auxiliaryStyle),
                          const SizedBox(height: 20),
                          FilledButton.icon(
                              key: const ValueKey('family-login'),
                              onPressed: widget.onLogin,
                              icon: const Icon(Icons.login_rounded),
                              label: const Text('登录账号'))
                        ]))),
            const HomeDeskHomePanels(),
          ]);
        }
        if (widget.listLayout) {
          return NestLinkDeviceList(
              account: account,
              onConnect: widget.onConnect,
              onManualConnect:
                  widget.onManualConnect ?? actions?.onManualConnect,
              readOption: readOption);
        }
        final devices = [...?account.catalog?.devices];
        final visible = devices
            .where((d) => switch (_filter) {
                  1 => _online(d),
                  2 => !_online(d),
                  3 => _needsAttention(d),
                  _ => true,
                })
            .toList();
        return LayoutBuilder(builder: (context, c) {
          final scale = MediaQuery.textScalerOf(context).scale(1);
          final columns = scale > 1.5
              ? 1
              : ((c.maxWidth + HomeDeskTokens.gap) /
                      (HomeDeskTokens.minDeviceWidth + HomeDeskTokens.gap))
                  .floor()
                  .clamp(1, 4);
          final width =
              (c.maxWidth - HomeDeskTokens.gap * (columns - 1)) / columns;
          final height = (scale > 1.5
                  ? 280.0
                  : devices.any((d) =>
                          account.bindings[d.id] != null &&
                          !_matching(account.bindings[d.id]!))
                      ? 240.0
                      : devices.any((d) =>
                              d.id != account.localDeviceId &&
                              account.bindings[d.id] == null)
                          ? 216.0
                          : 200.0) +
              (scale - 1).clamp(0.0, 3.0) * 200;
          return SingleChildScrollView(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                if (actions != null) ...[actions.status(context)],
                if (devices.any((d) =>
                    d.id != account.localDeviceId &&
                    account.bindings[d.id] == null))
                  Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                              color: t.warningSoft,
                              borderRadius: BorderRadius.circular(
                                  HomeDeskTokens.blockRadius)),
                          child: Wrap(
                              spacing: 12,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text('部分设备尚未同步远控 ID。',
                                    style: TextStyle(
                                        color: t.warning,
                                        fontSize: HomeDeskTokens.auxiliary)),
                                TextButton(
                                    onPressed: () =>
                                        setState(() => _filter = 3),
                                    child: const Text('查看需处理设备'))
                              ]))),
                LayoutBuilder(builder: (context, c) {
                  final heading =
                      Text('我的设备 · ${devices.length} 台', style: t.sectionStyle);
                  final filters = HomeDeskSegments(
                      labels: const ['全部', '在线', '离线', '需处理'],
                      selected: _filter,
                      onSelected: (i) => setState(() => _filter = i),
                      keyPrefix: 'family-filter');
                  final refresh = IconButton(
                      key: const ValueKey('family-refresh'),
                      tooltip: '刷新家庭设备',
                      onPressed: account.loading ? null : account.refresh,
                      icon: account.loading
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.refresh_rounded));
                  if (c.maxWidth >= 600 && scale <= 1.5) {
                    return Row(children: [
                      Expanded(child: heading),
                      filters,
                      const SizedBox(width: 12),
                      refresh
                    ]);
                  }
                  return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [Expanded(child: heading), refresh]),
                        const SizedBox(height: 8),
                        filters
                      ]);
                }),
                const SizedBox(height: 16),
                if (account.message.isNotEmpty)
                  Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(account.message, style: t.auxiliaryStyle)),
                if (devices.isEmpty)
                  Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text('正在接入本机…\n其他电脑登录同一账号后会自动加入。',
                          style: t.auxiliaryStyle))
                else if (visible.isEmpty)
                  Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Text('这个筛选下暂无设备。', style: t.auxiliaryStyle))
                else
                  Wrap(
                      spacing: HomeDeskTokens.gap,
                      runSpacing: HomeDeskTokens.gap,
                      children: [
                        for (final d in visible)
                          SizedBox(
                              width: width, child: _card(context, d, height))
                      ]),
                const HomeDeskHomePanels(),
                const SizedBox(height: 20),
              ]));
        });
      });
}
