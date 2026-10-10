// Account-only recent connections reuse native peer records.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'common.dart' hide Dialog;
import 'common/widgets/peer_card.dart';
import 'desktop/widgets/material_mod_popup_menu.dart' as peer_menu;
import 'models/peer_tab_model.dart';
import 'models/platform_model.dart';
import 'models/peer_model.dart';
import 'homedesk_device_label.dart';
import 'homedesk_peer_menu.dart';
import 'homedesk_theme.dart';
import 'nestlink_locale.dart';

class HomeDeskRecent extends StatefulWidget {
  final List<Peer>? recent;
  final ValueChanged<Peer>? onConnect;
  final HomeDeskPeerMenuBuilder? menuBuilder;
  final ValueChanged<PeerTabIndex>? onLoad;
  final ValueChanged<List<String>>? onQueryOnline;
  final bool summary, compact;
  const HomeDeskRecent(
      {super.key,
      this.recent,
      this.onConnect,
      this.menuBuilder,
      this.onLoad,
      this.onQueryOnline,
      this.summary = false,
      this.compact = false});
  @override
  State<HomeDeskRecent> createState() => HomeDeskRecentState();
}

class HomeDeskRecentState extends State<HomeDeskRecent>
    with WindowListener, WidgetsBindingObserver {
  List<Peers> _models = [];
  Timer? _onlineTimer;
  final _search = TextEditingController();
  bool _visible = false,
      _active = true,
      _minimized = false,
      _reloadQueued = false;
  DateTime? _restoredAt;
  PeerTabIndex get _tab => PeerTabIndex.recent;
  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    WidgetsBinding.instance.addObserver(this);
    if (widget.recent == null) {
      try {
        _models = [gFFI.recentPeersModel];
      } catch (_) {/* 原生桥接不可用时显示空态。 */}
    }
    if (_models.isNotEmpty || widget.onQueryOnline != null) {
      _onlineTimer =
          Timer.periodic(const Duration(seconds: 6), (_) => _queryOnline());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = TickerMode.of(context);
    if (visible && !_visible) {
      _scheduleReload();
    }
    _visible = visible;
  }

  List<Peer> get _peers =>
      widget.recent ?? (_models.isEmpty ? <Peer>[] : _models.first.peers);
  List<Peer> get _filtered {
    final query = _search.text.trim().toLowerCase();
    return _peers
        .where((p) =>
            p.id != '...' &&
            (query.isEmpty ||
                p.id.toLowerCase().contains(query) ||
                p.alias.toLowerCase().contains(query) ||
                p.hostname.toLowerCase().contains(query)))
        .toList();
  }

  void _scheduleReload() {
    if (_reloadQueued) {
      return;
    }
    _reloadQueued = true;
    scheduleMicrotask(() {
      _reloadQueued = false;
      if (mounted && _visible && _active && !_minimized) {
        _reload();
        _queryOnline();
      }
    });
  }

  void _reload() {
    if (widget.onLoad != null) {
      widget.onLoad!(_tab);
      return;
    }
    if (_models.isEmpty) {
      return;
    }
    bind.mainLoadRecentPeers();
  }

  void _queryOnline() {
    if (!mounted || !_visible || !_active || _minimized) {
      return;
    }
    final peers = widget.summary ? _filtered.take(2) : _filtered;
    final ids = peers.map((p) => p.id).toList();
    if (ids.isEmpty) {
      return;
    }
    if (widget.onQueryOnline != null) {
      widget.onQueryOnline!(ids);
    } else if (_models.isNotEmpty) {
      bind.queryOnlines(ids: ids);
    }
  }

  @override
  void onWindowFocus() {
    _active = true;
    _minimized = false;
    _scheduleReload();
  }

  @override
  void onWindowBlur() {
    // Windows 恢复窗口后可能立即发 blur，沿用上游的 300ms 保护。
    if (isWindows &&
        _restoredAt != null &&
        DateTime.now().difference(_restoredAt!) <
            const Duration(milliseconds: 300)) {
      return;
    }
    _active = false;
  }

  @override
  void onWindowRestore() {
    _restoredAt = DateTime.now();
    onWindowFocus();
  }

  @override
  void onWindowMinimize() {
    _active = false;
    _minimized = true;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      onWindowFocus();
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _active = false;
    }
  }

  Future<void> _showMenu(BuildContext anchor, Peer peer) async {
    try {
      final items =
          await (widget.menuBuilder ?? homeDeskPeerMenu)(context, peer, _tab);
      if (!mounted || !anchor.mounted) {
        return;
      }
      final box = anchor.findRenderObject()! as RenderBox;
      final overlay =
          Overlay.of(context).context.findRenderObject()! as RenderBox;
      final rect = Rect.fromPoints(
          box.localToGlobal(Offset.zero, ancestor: overlay),
          box.localToGlobal(box.size.bottomRight(Offset.zero),
              ancestor: overlay));
      await peer_menu.showMenu<String>(
          context: context,
          position: RelativeRect.fromRect(rect, Offset.zero & overlay.size),
          items: items,
          elevation: 0,
          color: HomeDeskTokens.of(context).surface,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(HomeDeskTokens.blockRadius),
              side: BorderSide(color: HomeDeskTokens.of(context).border)),
          constraints: BoxConstraints(
              minWidth: 220,
              maxWidth: 320,
              maxHeight: MediaQuery.sizeOf(context).height - 32));
      if (mounted) {
        _scheduleReload();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
            content: Text(nl('设备操作暂不可用，请稍后重试。',
                'Device actions are unavailable. Try again.'))));
      }
    }
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    WidgetsBinding.instance.removeObserver(this);
    _onlineTimer?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _connectPeer(Peer peer) {
    if (widget.onConnect != null) {
      widget.onConnect!(peer);
    } else {
      connectInPeerTab(context, peer, _tab);
    }
  }

  Widget _row(BuildContext context, Peer peer) => Builder(builder: (context) {
        final t = HomeDeskTokens.of(context);
        final name = peer.alias.isNotEmpty
            ? peer.alias
            : peer.hostname.isNotEmpty
                ? peer.hostname
                : peer.id;
        final detail =
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Flexible(
                child: Text(homeDeskDeviceLabel(name),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.sectionStyle)),
          ]),
          const SizedBox(height: 4),
          Text(
              '${nl('设备 ID', 'Device ID')}: ${peer.id}${peer.platform.isEmpty ? '' : ' · ${peer.platform}'}',
              style: t.auxiliaryStyle),
          const SizedBox(height: 6),
          HomeDeskBadge(peer.online ? nl('在线', 'Online') : nl('离线', 'Offline'),
              tone: peer.online ? HomeDeskTone.success : HomeDeskTone.neutral),
        ]);
        final actions = Row(mainAxisSize: MainAxisSize.min, children: [
          OutlinedButton(
              onPressed: () => _connectPeer(peer),
              child: Text(nl('连接', 'Connect'))),
          const SizedBox(width: 4),
          Builder(
              builder: (anchor) => IconButton(
                  key: ValueKey('recent-more-${peer.id}'),
                  tooltip: nl('更多设备操作', 'More device actions'),
                  onPressed: () => _showMenu(anchor, peer),
                  icon: const Icon(Icons.more_horiz_rounded)))
        ]);
        return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Card(
                child: Padding(
                    padding: const EdgeInsets.all(HomeDeskTokens.cardPadding),
                    child: LayoutBuilder(builder: (context, c) {
                      if (c.maxWidth < 380 ||
                          MediaQuery.textScalerOf(context).scale(1) > 1.5) {
                        return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              detail,
                              const SizedBox(height: 12),
                              actions
                            ]);
                      }
                      return Row(children: [
                        Icon(Icons.computer_rounded,
                            color: t.secondary, size: 28),
                        const SizedBox(width: 12),
                        Expanded(child: detail),
                        const SizedBox(width: 12),
                        actions
                      ]);
                    }))));
      });

  Widget _body(BuildContext context) {
    final peers = _filtered;
    if (widget.compact) {
      final t = HomeDeskTokens.of(context);
      if (peers.isEmpty) {
        return Align(
            alignment: Alignment.topLeft,
            child: Text(nl('还没有最近连接', 'No recent connections'),
                style: t.auxiliaryStyle));
      }
      return LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
              child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: peers.map((peer) {
                    final name =
                        peer.alias.isNotEmpty ? peer.alias : peer.hostname;
                    return SizedBox(
                        width: constraints.maxWidth.clamp(0, 236).toDouble(),
                        child: Material(
                            color: t.surface,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                    HomeDeskTokens.controlRadius),
                                side: BorderSide(color: t.border)),
                            clipBehavior: Clip.antiAlias,
                            child: Row(children: [
                              Expanded(
                                  child: InkWell(
                                      key:
                                          ValueKey('recent-connect-${peer.id}'),
                                      onTap: () => _connectPeer(peer),
                                      child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 10),
                                          child: Row(children: [
                                            Container(
                                                width: 6,
                                                height: 6,
                                                decoration: BoxDecoration(
                                                    shape: BoxShape.circle,
                                                    color: peer.online
                                                        ? t.success
                                                        : t.muted)),
                                            const SizedBox(width: 8),
                                            Expanded(
                                                child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                  if (name.isNotEmpty)
                                                    Text(
                                                        homeDeskDeviceLabel(
                                                            name),
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: TextStyle(
                                                            color: t.text,
                                                            fontSize: 13)),
                                                  Text(peer.id,
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: t.auxiliaryStyle),
                                                ])),
                                          ])))),
                              Builder(
                                  builder: (anchor) => IconButton(
                                      key: ValueKey('recent-more-${peer.id}'),
                                      tooltip:
                                          nl('更多设备操作', 'More device actions'),
                                      onPressed: () => _showMenu(anchor, peer),
                                      icon: Icon(Icons.more_horiz_rounded,
                                          color: t.secondary, size: 18))),
                            ])));
                  }).toList())));
    }
    if (widget.summary) {
      return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: peers.isEmpty
              ? [
                  Text(nl('还没有最近连接记录。', 'No recent connections.'),
                      style: HomeDeskTokens.of(context).auxiliaryStyle)
                ]
              : peers.take(2).map((p) => _row(context, p)).toList());
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(
          key: const ValueKey('recent-search'),
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
              hintText: nl('搜索设备名称或 ID', 'Search by name or ID'),
              prefixIcon: Icon(Icons.search_rounded))),
      const SizedBox(height: HomeDeskTokens.moduleGap),
      Expanded(
          child: peers.isEmpty
              ? LayoutBuilder(
                  builder: (context, constraints) => Center(
                      child: Padding(
                          padding: const EdgeInsets.all(8),
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                            if (constraints.maxHeight >= 130) ...[
                              Icon(Icons.desktop_windows_outlined,
                                  size: 32,
                                  color: HomeDeskTokens.of(context).muted),
                              const SizedBox(height: 12),
                            ],
                            Text(
                                _search.text.trim().isNotEmpty
                                    ? nl('没有找到匹配的设备', 'No matching devices')
                                    : nl('还没有最近连接', 'No recent connections'),
                                style: HomeDeskTokens.of(context).sectionStyle),
                            const SizedBox(height: 6),
                            Text(
                                nl('输入设备 ID，开始第一次连接。',
                                    'Enter a device ID to start connecting.'),
                                textAlign: TextAlign.center,
                                style:
                                    HomeDeskTokens.of(context).auxiliaryStyle)
                          ]))))
              : ListView.builder(
                  itemCount: peers.length,
                  itemBuilder: (context, i) => _row(context, peers[i]))),
    ]);
  }

  @override
  Widget build(BuildContext context) => _models.isEmpty
      ? _body(context)
      : ListenableBuilder(
          listenable: Listenable.merge(_models),
          builder: (context, _) => _body(context));
}
