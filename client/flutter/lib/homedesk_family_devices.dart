// HOMEDESK: 同账号设备目录使用设备 UUID 关联远控 ID，继续调用既有远控连接入口。
import 'dart:convert';
import 'package:flutter/material.dart';
import 'homedesk_account.dart';
import 'homedesk_tunnel_api.dart';
import 'homedesk_device_label.dart';

class HomeDeskFamilyDevices extends StatelessWidget {
  final HomeDeskAccount account;
  final VoidCallback onLogin;
  final ValueChanged<String> onConnect;
  final String Function(String) readOption;
  final WidgetBuilder? lanBuilder;
  const HomeDeskFamilyDevices(
      {super.key,
      required this.account,
      required this.onLogin,
      required this.onConnect,
      required this.readOption,
      this.lanBuilder});

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

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: account,
      builder: (context, _) {
        final colors = Theme.of(context).colorScheme;
        if (!account.signedIn) {
          if (lanBuilder != null &&
              readOption('homedesk-console-allowed') == 'Y') {
            return lanBuilder!(context);
          }
          return Center(
              child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 500),
                  child: SingleChildScrollView(
                      child: Card(
                          child: Padding(
                              padding: const EdgeInsets.all(28),
                              child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.devices_rounded,
                                        size: 48, color: colors.primary),
                                    const SizedBox(height: 18),
                                    const Text('登录账号，查看家庭设备',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.w700)),
                                    const SizedBox(height: 12),
                                    Text('同一账号登录的电脑会自动出现在这里，登录一次即可使用家庭设备和家庭服务。',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                            color: colors.onSurfaceVariant)),
                                    const SizedBox(height: 20),
                                    FilledButton.icon(
                                        key: const ValueKey('family-login'),
                                        onPressed: onLogin,
                                        icon: const Icon(Icons.login_rounded),
                                        label: const Text('登录账号')),
                                  ]))))));
        }
        final devices = [...?account.catalog?.devices];
        final owner = account.api;
        devices
            .sort((a, b) => (b.favorite ? 1 : 0).compareTo(a.favorite ? 1 : 0));
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Expanded(
                    child: Text(
                        '${account.displayName} · ${devices.length} 台家庭设备',
                        style: TextStyle(color: colors.onSurfaceVariant))),
                IconButton(
                    key: const ValueKey('family-refresh'),
                    tooltip: '刷新家庭设备',
                    onPressed: account.loading ? null : account.refresh,
                    icon: const Icon(Icons.refresh_rounded)),
              ]),
              if (account.message.isNotEmpty)
                Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(account.message,
                        style: TextStyle(color: colors.onSurfaceVariant))),
              if (account.loading) const LinearProgressIndicator(),
              Expanded(
                  child: devices.isEmpty
                      ? Center(
                          child: Text('正在接入本机…\n其他电脑登录同一账号后会自动加入。',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: colors.onSurfaceVariant)))
                      : ListView.separated(
                          padding: const EdgeInsets.only(top: 12, bottom: 20),
                          itemCount: devices.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final device = devices[index];
                            final binding = account.bindings[device.id];
                            final local = account.localDeviceId == device.id;
                            final matching =
                                binding != null && _matching(binding);
                            final available =
                                binding != null && !local && matching;
                            return Card(
                                child: Padding(
                                    padding: const EdgeInsets.all(20),
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Icon(Icons.computer_rounded,
                                                    size: 28,
                                                    color: colors.primary),
                                                const SizedBox(width: 12),
                                                Expanded(
                                                    child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                      Text(
                                                          device.name.isEmpty
                                                              ? '未命名设备'
                                                              : homeDeskDeviceLabel(device.name),
                                                          style: const TextStyle(
                                                              fontSize: 17,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w700)),
                                                      const SizedBox(height: 7),
                                                      Text(
                                                          local
                                                              ? '本机'
                                                              : binding?.online ==
                                                                      true
                                                                  ? '账号在线'
                                                                  : '离线或尚未同步',
                                                          style: TextStyle(
                                                              fontSize: 12,
                                                              color: colors
                                                                  .onSurfaceVariant)),
                                                    ])),
                                                if (device.favorite)
                                                  const Icon(Icons.star_rounded,
                                                      size: 20),
                                                IconButton(
                                                    key: ValueKey(
                                                        'family-manage-${device.id}'),
                                                    tooltip: '管理设备',
                                                    onPressed:
                                                        account.editDevice ==
                                                                null
                                                            ? null
                                                            : () {
                                                                if (identical(
                                                                        account
                                                                            .api,
                                                                        owner) &&
                                                                    account
                                                                        .signedIn &&
                                                                    account.catalog?.devices.any((d) =>
                                                                            d.id ==
                                                                            device.id) ==
                                                                        true) {
                                                                  account.editDevice!(
                                                                      device);
                                                                }
                                                              },
                                                    icon: const Icon(
                                                        Icons.tune_rounded,
                                                        size: 20)),
                                              ]),
                                          if (device.tags.isNotEmpty)
                                            Padding(
                                                padding: const EdgeInsets.only(
                                                    top: 12),
                                                child: Wrap(
                                                    spacing: 6,
                                                    runSpacing: 6,
                                                    children: [
                                                      for (final tag
                                                          in device.tags)
                                                        Chip(label: Text(tag)),
                                                    ])),
                                          const SizedBox(height: 14),
                                          Text(
                                              binding == null
                                                  ? '远控 ID 尚未同步，请在该设备上运行新版客户端。'
                                                  : '设备 ID：${binding.remoteId}',
                                              style: TextStyle(
                                                  color:
                                                      colors.onSurfaceVariant)),
                                          if (binding != null && !matching)
                                            const Padding(
                                                padding:
                                                    EdgeInsets.only(top: 6),
                                                child: Text(
                                                    '这台设备使用不同的远控服务器，请核对网络配置。',
                                                    style: TextStyle(
                                                        fontSize: 12))),
                                          if (!local)
                                            Padding(
                                                padding: const EdgeInsets.only(
                                                    top: 12),
                                                child: FilledButton.icon(
                                                    key: ValueKey(
                                                        'family-connect-${device.id}'),
                                                    onPressed: !available
                                                        ? null
                                                        : () {
                                                            final current =
                                                                account.bindings[
                                                                    device.id];
                                                            if (identical(
                                                                    account.api,
                                                                    owner) &&
                                                                account
                                                                    .signedIn &&
                                                                current !=
                                                                    null &&
                                                                current.remoteId ==
                                                                    binding
                                                                        .remoteId &&
                                                                account.catalog
                                                                        ?.devices
                                                                        .any((d) =>
                                                                            d.id ==
                                                                            device
                                                                                .id) ==
                                                                    true &&
                                                                _matching(
                                                                    current)) {
                                                              onConnect(current
                                                                  .remoteId);
                                                            }
                                                          },
                                                    icon: const Icon(
                                                        Icons
                                                            .desktop_windows_rounded,
                                                        size: 19),
                                                    label: const Text('连接电脑'))),
                                        ])));
                          })),
            ]);
      });
}
