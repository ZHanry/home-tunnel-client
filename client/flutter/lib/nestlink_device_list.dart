import 'dart:convert';
import 'package:flutter/material.dart';
import 'homedesk_account.dart';
import 'homedesk_device_label.dart';
import 'homedesk_theme.dart';
import 'homedesk_tunnel_api.dart';
import 'nestlink_locale.dart';
import 'nestlink_dialog.dart';

/// The desktop directory uses account bindings; display names never become
/// connection addresses. Every action rechecks the current session owner.
class NestLinkDeviceList extends StatefulWidget {
  final HomeDeskAccount account;
  final ValueChanged<String> onConnect;
  final VoidCallback? onManualConnect;
  final String Function(String) readOption;
  const NestLinkDeviceList(
      {super.key,
      required this.account,
      required this.onConnect,
      this.onManualConnect,
      required this.readOption});
  @override
  State<NestLinkDeviceList> createState() => _NestLinkDeviceListState();
}

class _NestLinkDeviceListState extends State<NestLinkDeviceList> {
  final _search = TextEditingController();
  final _collapsed = <String>{};
  int _filter = 0;
  HomeDeskAccount get account => widget.account;
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matching(HomeDeskRemoteBinding binding) {
    try {
      final profile = jsonDecode(widget.readOption('homedesk-remote-profile'));
      return profile is Map &&
          profile['server'] == binding.server &&
          profile['key_sha256'] == binding.keySHA256;
    } catch (_) {
      return false;
    }
  }

  HomeDeskRemoteBinding? _binding(HomeTunnelDevice device) =>
      device.remoteDeviceId.isEmpty ? null : account.bindings[device.id];
  bool _online(HomeTunnelDevice device) =>
      _binding(device)?.online == true || device.online;
  int _serviceCount(String id) =>
      account.catalog?.services
          .where((service) => service.deviceId == id)
          .length ??
      0;
  bool _canConnect(HomeTunnelDevice device) {
    final current = _current(account.api, device.id);
    final binding = current == null ? null : _binding(current);
    return account.signedIn &&
        current != null &&
        current.id != account.localDeviceId &&
        binding != null &&
        binding.online &&
        _matching(binding);
  }

  String _name(HomeTunnelDevice device) => device.name.isEmpty
      ? nl('未命名设备', 'Unnamed device')
      : homeDeskDeviceLabel(device.name);
  String _group(HomeTunnelDevice device) {
    final platform = (device.platform.isEmpty
            ? _binding(device)?.platform ?? ''
            : device.platform)
        .toLowerCase();
    if (['android', 'ios', 'ipados'].contains(platform)) return 'mobile';
    if (['windows', 'linux', 'macos', 'mac os', 'osx'].contains(platform)) {
      return 'computer';
    }
    return 'other';
  }

  IconData _icon(HomeTunnelDevice device) => _group(device) == 'mobile'
      ? Icons.smartphone_rounded
      : Icons.desktop_windows_rounded;

  HomeTunnelDevice? _current(HomeTunnelApi? owner, String id) {
    if (owner == null || !identical(account.api, owner) || !account.signedIn) {
      return null;
    }
    for (final device in account.catalog?.devices ?? <HomeTunnelDevice>[]) {
      if (device.id == id) return device;
    }
    return null;
  }

  Future<void> _manage(HomeTunnelApi? owner, String id,
      Future<void> Function(HomeTunnelDevice)? operation) async {
    final current = _current(owner, id);
    if (current == null || operation == null) return;
    try {
      await operation(current);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
            content: Text(error is HomeTunnelApiException
                ? error.message
                : nl('设备操作未完成，请刷新后重试。',
                    'The device action failed. Refresh and retry.'))));
      }
    }
  }

  Future<void> _confirmDelete(HomeTunnelApi? owner, String id) async {
    final device = _current(owner, id);
    if (device == null || account.deleteDevice == null) return;
    var busy = false;
    var needsReview = account.needsDeviceDeletionReview(owner, id);
    var error = needsReview
        ? nl('上次删除的结果尚未核对，请先刷新核对。',
            'Review the previous deletion outcome before trying again.')
        : '';
    await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
            builder: (dialogContext, update) => PopScope(
                canPop: !busy,
                child: NestLinkDialog(
                    title: Text(nl('删除设备？', 'Delete device?')),
                    content: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(nl(
                              '删除“${_name(device)}”后，这台设备的远程连接与内网穿透访问将停止。需要重新登录或登记设备才能再次使用。',
                              'Deleting “${_name(device)}” stops its remote connections and tunnel access. Sign in or register the device again to use it.')),
                          if (error.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Text(error,
                                key: ValueKey('device-delete-error-$id'),
                                style: TextStyle(
                                    color: Theme.of(dialogContext)
                                        .colorScheme
                                        .error)),
                          ],
                          if (needsReview)
                            TextButton.icon(
                                key: ValueKey('device-delete-review-$id'),
                                onPressed: busy
                                    ? null
                                    : () async {
                                        if (!dialogContext.mounted || busy) {
                                          return;
                                        }
                                        if (!identical(account.api, owner) ||
                                            !account.signedIn) {
                                          update(() => error = nl(
                                              '账号已变化，请关闭并重新查看设备。',
                                              'The account changed. Close and open the device again.'));
                                          return;
                                        }
                                        if (account.loading) {
                                          update(() => error = nl(
                                              '设备目录正在刷新，请稍后再核对。',
                                              'The device catalog is refreshing. Review it again shortly.'));
                                          return;
                                        }
                                        update(() => busy = true);
                                        await account.refresh();
                                        if (!dialogContext.mounted) return;
                                        if (!identical(account.api, owner) ||
                                            !account.signedIn) {
                                          update(() {
                                            busy = false;
                                            error = nl('账号已变化，请关闭并重新查看设备。',
                                                'The account changed. Close and open the device again.');
                                          });
                                        } else if (account.message.isNotEmpty) {
                                          update(() {
                                            busy = false;
                                            error = account.message;
                                          });
                                        } else {
                                          account.completeDeviceDeletionReview(
                                              owner, id);
                                          if (_current(owner, id) == null) {
                                            Navigator.pop(dialogContext);
                                          } else {
                                            update(() {
                                              busy = false;
                                              needsReview = false;
                                              error = nl(
                                                  '已刷新核对，设备仍在账号中。可重新确认删除。',
                                                  'The refreshed catalog still contains this device. Confirm deletion again if needed.');
                                            });
                                          }
                                        }
                                      },
                                icon: const Icon(Icons.refresh_rounded),
                                label: Text(nl('刷新核对', 'Refresh and review'))),
                          if (busy)
                            const Padding(
                                padding: EdgeInsets.only(top: 12),
                                child: LinearProgressIndicator()),
                        ]),
                    actions: [
                      TextButton(
                          onPressed:
                              busy ? null : () => Navigator.pop(dialogContext),
                          child: Text(nl('取消', 'Cancel'))),
                      FilledButton(
                          key: ValueKey('device-confirm-delete-$id'),
                          style: FilledButton.styleFrom(
                              backgroundColor:
                                  Theme.of(dialogContext).colorScheme.error,
                              foregroundColor:
                                  Theme.of(dialogContext).colorScheme.onError),
                          onPressed: busy || needsReview
                              ? null
                              : () async {
                                  if (!dialogContext.mounted || busy) return;
                                  final current = _current(owner, id);
                                  final remove = account.deleteDevice;
                                  if (current == null || remove == null) {
                                    update(() => error = nl(
                                        '账号或设备已变化，请关闭并刷新设备列表。',
                                        'The account or device changed. Close and refresh the device list.'));
                                    return;
                                  }
                                  if (account.needsDeviceDeletionReview(
                                      owner, id)) {
                                    update(() {
                                      needsReview = true;
                                      error = nl('上次删除的结果尚未核对，请先刷新核对。',
                                          'Review the previous deletion outcome before trying again.');
                                    });
                                    return;
                                  }
                                  update(() {
                                    busy = true;
                                    error = '';
                                  });
                                  try {
                                    await remove(current);
                                    if (dialogContext.mounted) {
                                      Navigator.pop(dialogContext);
                                    }
                                  } catch (failure) {
                                    if (failure is HomeTunnelApiException &&
                                        failure.outcomeUnknown) {
                                      account.markDeviceDeletionForReview(
                                          owner, id);
                                    }
                                    if (dialogContext.mounted) {
                                      update(() {
                                        busy = false;
                                        needsReview =
                                            account.needsDeviceDeletionReview(
                                                owner, id);
                                        error = failure
                                                is HomeTunnelApiException
                                            ? failure.message
                                            : nl('删除未完成，请刷新后重试。',
                                                'Deletion failed. Refresh and retry.');
                                      });
                                    }
                                  }
                                },
                          child: Text(busy
                              ? nl('正在删除…', 'Deleting…')
                              : nl('删除设备', 'Delete device'))),
                    ]))));
  }

  void _details(HomeTunnelDevice device) {
    final owner = account.api;
    if (_current(owner, device.id) == null) return;
    showDialog<void>(
        context: context,
        builder: (dialogContext) => ListenableBuilder(
            listenable: account,
            builder: (dialogContext, _) {
              final current = _current(owner, device.id);
              final binding = current == null ? null : _binding(current);
              final local = current?.id == account.localDeviceId;
              final services = _serviceCount(device.id);
              final platform = current?.platform.isNotEmpty == true
                  ? current!.platform
                  : binding?.platform ?? nl('未提供', 'Not provided');
              void run(Future<void> Function(HomeTunnelDevice)? operation) {
                Navigator.pop(dialogContext);
                _manage(owner, device.id, operation);
              }

              return NestLinkDialog(
                  width: 520,
                  title: Text(nl('管理设备', 'Manage device')),
                  content: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (current == null)
                          Text(nl('账号或设备已变化，请刷新设备列表。',
                              'The account or device changed. Refresh the device list.'))
                        else ...[
                          Text(_name(current),
                              style: HomeDeskTokens.of(dialogContext)
                                  .sectionStyle),
                          const SizedBox(height: 12),
                          Text('${nl('系统', 'Platform')}：$platform'),
                          const SizedBox(height: 8),
                          Text(local
                              ? nl('这是当前电脑', 'This is your computer')
                              : _online(current)
                                  ? nl('设备在线', 'Device is online')
                                  : nl('设备离线', 'Device is offline')),
                          const SizedBox(height: 12),
                          SelectableText(binding == null
                              ? nl('远控：尚未接入', 'Remote: not registered')
                              : '${nl('远控 ID', 'Remote ID')}：${binding.remoteId}'),
                          if (binding != null) ...[
                            const SizedBox(height: 8),
                            Text(binding.online
                                ? nl('远控：在线', 'Remote control: online')
                                : nl('远控：离线', 'Remote control: offline')),
                          ],
                          const SizedBox(height: 8),
                          Text(current.tunnelOnline
                              ? nl('穿透心跳：在线', 'Tunnel heartbeat: online')
                              : nl('穿透心跳：离线', 'Tunnel heartbeat: offline')),
                          const SizedBox(height: 8),
                          Text(nl('内网穿透：$services 项服务',
                              'Tunnels: $services services')),
                          if (current.tags.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                                '${nl('标签', 'Tags')}：${current.tags.join(' · ')}'),
                          ],
                          if (binding != null && !local && !_matching(binding))
                            Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: Text(
                                    nl('远控服务器配置不同，请在设置中核对连接服务。',
                                        'The remote server configuration differs. Check your connection settings.'),
                                    style: TextStyle(
                                        color: HomeDeskTokens.of(dialogContext)
                                            .warning))),
                          const SizedBox(height: 20),
                          Wrap(spacing: 10, runSpacing: 10, children: [
                            if (account.editDevice != null)
                              OutlinedButton(
                                  key: ValueKey('device-edit-${device.id}'),
                                  onPressed: () => run(account.editDevice),
                                  child: Text(nl('编辑标签', 'Edit tags'))),
                            if (account.manageDeviceServices != null)
                              OutlinedButton(
                                  key: ValueKey('device-tunnels-${device.id}'),
                                  onPressed: () =>
                                      run(account.manageDeviceServices),
                                  child: Text(nl('管理穿透服务', 'Manage tunnels'))),
                            if (!local)
                              FilledButton(
                                  key: ValueKey('device-connect-${device.id}'),
                                  onPressed: !_canConnect(current)
                                      ? null
                                      : () {
                                          final latest =
                                              _current(owner, device.id);
                                          final remote =
                                              account.bindings[device.id];
                                          if (latest != null &&
                                              _canConnect(latest) &&
                                              remote?.remoteId ==
                                                  binding?.remoteId) {
                                            Navigator.pop(dialogContext);
                                            widget.onConnect(remote!.remoteId);
                                          }
                                        },
                                  child: Text(nl('远程连接', 'Remote connect'))),
                          ]),
                        ],
                      ]),
                  actions: [
                    if (current != null && account.deleteDevice != null)
                      TextButton(
                          key: ValueKey('device-delete-${device.id}'),
                          style: TextButton.styleFrom(
                              foregroundColor:
                                  Theme.of(dialogContext).colorScheme.error),
                          onPressed: () {
                            Navigator.pop(dialogContext);
                            _confirmDelete(owner, device.id);
                          },
                          child: Text(nl('删除设备', 'Delete device'))),
                    TextButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        child: Text(nl('关闭', 'Close'))),
                  ]);
            }));
  }

  Widget _row(BuildContext context, HomeTunnelDevice device) {
    final t = HomeDeskTokens.of(context);
    final owner = account.api;
    final binding = _binding(device);
    final local = device.id == account.localDeviceId;
    final online = _online(device);
    final available = _canConnect(device);
    final status = Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
              color: online ? t.success : t.muted, shape: BoxShape.circle)),
      const SizedBox(width: 6),
      Text(online ? nl('在线', 'Online') : nl('离线', 'Offline'),
          style:
              TextStyle(fontSize: 12, color: online ? t.success : t.secondary)),
    ]);
    final identity = Row(children: [
      Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
              color: t.accent, borderRadius: BorderRadius.circular(8)),
          child: Icon(_icon(device), color: t.onAccent, size: 21)),
      const SizedBox(width: 14),
      Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Flexible(
              child: Tooltip(
                  message: _name(device),
                  child: Text(_name(device),
                      key: ValueKey('family-name-${device.id}'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: t.text)))),
          if (local) ...[
            const SizedBox(width: 8),
            Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                    color: t.accentSoft,
                    borderRadius: BorderRadius.circular(4)),
                child: Text(nl('本机', 'This device'),
                    style: TextStyle(fontSize: 11, color: t.accentText)))
          ],
        ]),
        if (device.platform.isNotEmpty || binding != null) ...[
          const SizedBox(height: 4),
          Text(
              [
                if (device.platform.isNotEmpty) device.platform,
                if (binding != null) binding.remoteId,
              ].join('   '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: t.secondary)),
        ],
        const SizedBox(height: 4),
        Wrap(spacing: 12, runSpacing: 4, children: [
          Text(
              binding == null
                  ? nl('远程协助：未接入', 'Remote assistance: not registered')
                  : binding.online
                      ? nl('远程协助：在线', 'Remote assistance: online')
                      : nl('远程协助：离线', 'Remote assistance: offline'),
              key: ValueKey('device-remote-status-${device.id}'),
              style: TextStyle(fontSize: 12, color: t.secondary)),
          Tooltip(
              message: nl('设备心跳状态；各项穿透服务的状态请在内网穿透页面查看。',
                  'Device heartbeat status. See Tunnels for each service status.'),
              child: Text(
                  device.tunnelOnline
                      ? nl('内网穿透：在线', 'Tunnels: online')
                      : nl('内网穿透：离线', 'Tunnels: offline'),
                  key: ValueKey('device-tunnel-status-${device.id}'),
                  style: TextStyle(fontSize: 12, color: t.secondary))),
          Text(
              nl('${_serviceCount(device.id)} 项服务',
                  '${_serviceCount(device.id)} services'),
              style: TextStyle(fontSize: 12, color: t.secondary)),
        ]),
      ])),
    ]);
    final info = IconButton(
        key: ValueKey('device-info-${device.id}'),
        tooltip: nl('管理设备', 'Manage device'),
        onPressed: () => _details(device),
        icon: Icon(Icons.info_outline_rounded, size: 19, color: t.secondary));
    final connect = local
        ? null
        : Tooltip(
            message: available
                ? nl('连接这台设备', 'Connect to this device')
                : binding == null
                    ? nl('这台设备尚未接入远控，可管理穿透服务。',
                        'Remote control is not registered. Manage its tunnel services.')
                    : !binding.online
                        ? nl('远控离线，暂时无法连接', 'Remote control is offline')
                        : nl('查看设备信息，核对远控配置',
                            'Check the remote configuration in device information'),
            child: FilledButton(
                key: ValueKey('family-connect-${device.id}'),
                style: FilledButton.styleFrom(
                    minimumSize: const Size(76, 34),
                    padding: const EdgeInsets.symmetric(horizontal: 14)),
                onPressed: !available
                    ? null
                    : () {
                        final current = account.bindings[device.id];
                        if (identical(account.api, owner) &&
                            _canConnect(device) &&
                            current != null &&
                            current.remoteId == binding?.remoteId &&
                            account.catalog?.devices
                                    .any((d) => d.id == device.id) ==
                                true) {
                          widget.onConnect(current.remoteId);
                        }
                      },
                child: Text(nl('连接', 'Connect'))));
    return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Container(
            key: ValueKey('device-row-${device.id}'),
            decoration: BoxDecoration(
                color: t.surface,
                border: Border.all(color: t.border),
                borderRadius: BorderRadius.circular(8)),
            child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
                child: LayoutBuilder(builder: (context, c) {
                  final narrow = c.maxWidth < 480 ||
                      MediaQuery.textScalerOf(context).scale(1) > 1.5;
                  if (narrow) {
                    return Column(children: [
                      Row(children: [Expanded(child: identity), info]),
                      const SizedBox(height: 10),
                      Row(children: [
                        status,
                        const Spacer(),
                        if (connect != null) connect
                      ]),
                    ]);
                  }
                  return Row(children: [
                    Expanded(child: identity),
                    const SizedBox(width: 20),
                    status,
                    const SizedBox(width: 12),
                    info,
                    if (connect != null) ...[
                      const SizedBox(width: 8),
                      connect
                    ] else
                      const SizedBox(width: 84)
                  ]);
                }))));
  }

  Widget _section(BuildContext context, String key, String title,
      List<HomeTunnelDevice> devices) {
    final t = HomeDeskTokens.of(context);
    final collapsed = _collapsed.contains(key);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 8),
          child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                  key: ValueKey('device-group-$key'),
                  style: TextButton.styleFrom(
                      foregroundColor: t.text,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 2, vertical: 8)),
                  onPressed: () => setState(() =>
                      collapsed ? _collapsed.remove(key) : _collapsed.add(key)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(
                        collapsed
                            ? Icons.chevron_right_rounded
                            : Icons.expand_more_rounded,
                        size: 20),
                    const SizedBox(width: 10),
                    Text(title),
                    const SizedBox(width: 8),
                    Text('${devices.length}',
                        style: TextStyle(color: t.secondary, fontSize: 12)),
                  ])))),
      if (!collapsed) ...devices.map((device) => _row(context, device)),
    ]);
  }

  Widget _header(BuildContext context) {
    final t = HomeDeskTokens.of(context);
    final controlHeight = homeDeskControlHeight(context);
    final owner = account.api;
    final title = Text(nl('设备管理', 'Device management'), style: t.titleStyle);
    final search = TextField(
        key: const ValueKey('device-search'),
        controller: _search,
        textAlignVertical: TextAlignVertical.center,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
            hintText: nl('搜索名称或设备 ID', 'Search name or device ID'),
            prefixIcon: const Icon(Icons.search_rounded, size: 19),
            prefixIconConstraints: BoxConstraints.tightFor(
                width: controlHeight, height: controlHeight),
            isDense: true,
            constraints: BoxConstraints.tightFor(height: controlHeight),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12)));
    final tools = Row(mainAxisSize: MainAxisSize.min, children: [
      SizedBox.square(
          dimension: controlHeight,
          child: IconButton(
              key: const ValueKey('device-manual-connect'),
              tooltip: nl('连接一台设备', 'Connect to a device'),
              style: IconButton.styleFrom(
                  minimumSize: const Size(40, 40),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap),
              onPressed: widget.onManualConnect == null || !account.signedIn
                  ? null
                  : () {
                      if (account.signedIn && identical(account.api, owner)) {
                        widget.onManualConnect!();
                      }
                    },
              icon: Icon(Icons.desktop_windows_outlined,
                  size: 20, color: t.secondary))),
      SizedBox(
          width: controlHeight,
          height: controlHeight,
          child: PopupMenuButton<int>(
              key: const ValueKey('device-filter'),
              tooltip: nl('筛选设备', 'Filter devices'),
              padding: const EdgeInsets.all(8),
              icon:
                  Icon(Icons.filter_list_rounded, size: 20, color: t.secondary),
              initialValue: _filter,
              onSelected: (i) => setState(() => _filter = i),
              itemBuilder: (_) => [
                    for (final item in [
                      (0, nl('全部', 'All')),
                      (1, nl('在线', 'Online')),
                      (2, nl('离线', 'Offline'))
                    ])
                      CheckedPopupMenuItem(
                          value: item.$1,
                          checked: _filter == item.$1,
                          child: Text(item.$2))
                  ])),
      SizedBox.square(
          dimension: controlHeight,
          child: IconButton(
              key: const ValueKey('family-refresh'),
              tooltip: nl('刷新设备', 'Refresh devices'),
              style: IconButton.styleFrom(
                  minimumSize: const Size(40, 40),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap),
              onPressed: account.loading ? null : account.refresh,
              icon: account.loading
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(Icons.refresh_rounded, size: 20, color: t.secondary))),
    ]);
    return Padding(
        key: const ValueKey('device-title-tools'),
        padding: const EdgeInsets.fromLTRB(8, 28, 4, 20),
        child: LayoutBuilder(builder: (context, c) {
          if (c.maxWidth >= 620 &&
              MediaQuery.textScalerOf(context).scale(1) <= 1.5) {
            return Row(children: [
              Expanded(child: title),
              const SizedBox(width: 16),
              SizedBox(width: 240, child: search),
              const SizedBox(width: 8),
              tools,
            ]);
          }
          return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                title,
                const SizedBox(height: 16),
                if (c.maxWidth >= 360)
                  Row(children: [
                    Expanded(child: search),
                    const SizedBox(width: 8),
                    tools,
                  ])
                else ...[
                  search,
                  const SizedBox(height: 8),
                  Align(alignment: Alignment.centerRight, child: tools),
                ],
              ]);
        }));
  }

  @override
  Widget build(BuildContext context) {
    final t = HomeDeskTokens.of(context);
    final query = _search.text.trim().toLowerCase();
    final devices = [...?account.catalog?.devices].where((d) {
      if (_filter == 1 && !_online(d) || _filter == 2 && _online(d)) {
        return false;
      }
      return query.isEmpty ||
          '${_name(d)} ${d.id} ${d.platform} ${d.tags.join(' ')} ${_binding(d)?.remoteId ?? ''}'
              .toLowerCase()
              .contains(query);
    }).toList()
      ..sort((a, b) {
        if (a.id == account.localDeviceId) return -1;
        if (b.id == account.localDeviceId) return 1;
        return _name(a).compareTo(_name(b));
      });
    final directory =
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (account.message.isNotEmpty)
        Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(account.message, style: t.auxiliaryStyle)),
      for (final group in [
        ('computer', nl('电脑', 'Computers')),
        ('mobile', nl('手机 / 平板', 'Phones / tablets')),
        ('other', nl('其他设备', 'Other devices'))
      ])
        if (devices.any((d) => _group(d) == group.$1))
          _section(context, group.$1, group.$2,
              devices.where((d) => _group(d) == group.$1).toList()),
      if (devices.isEmpty)
        Padding(
            padding: const EdgeInsets.symmetric(vertical: 72, horizontal: 24),
            child: Column(children: [
              Icon(Icons.devices_outlined, size: 40, color: t.accentText),
              const SizedBox(height: 16),
              Text(
                  query.isNotEmpty || _filter != 0
                      ? nl('没有找到匹配的设备', 'No matching devices')
                      : nl('等待设备加入', 'Waiting for devices'),
                  style: t.sectionStyle),
              const SizedBox(height: 8),
              Text(
                  nl('其他设备登录同一账号后，会自动出现在这里。',
                      'Devices appear here after signing in to the same account.'),
                  textAlign: TextAlign.center,
                  style: t.auxiliaryStyle)
            ])),
      const SizedBox(height: 24),
    ]);
    return LayoutBuilder(builder: (context, constraints) {
      // Keep the search element in the same tree when the keyboard opens.
      // In short viewports the outer scroll view includes the page header;
      // otherwise the directory scrolls below the stationary header.
      final short = constraints.maxHeight < 420;
      return SingleChildScrollView(
          key: const ValueKey('device-page-scroll'),
          child: SizedBox(
              height: short ? null : constraints.maxHeight,
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _header(context),
                    Flexible(
                        flex: short ? 0 : 1,
                        fit: FlexFit.loose,
                        child: SingleChildScrollView(
                            key: const ValueKey('device-directory-scroll'),
                            child: directory)),
                  ])));
    });
  }
}
