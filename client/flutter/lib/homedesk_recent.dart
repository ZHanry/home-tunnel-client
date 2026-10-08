// HOMEDESK: 消费上游最近、收藏和局域网模型，复用对端菜单和经典视图。
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'common.dart' hide Dialog;
import 'common/widgets/peer_card.dart';
import 'desktop/pages/connection_page.dart';
import 'desktop/widgets/material_mod_popup_menu.dart' as peer_menu;
import 'models/peer_tab_model.dart';
import 'models/platform_model.dart';
import 'models/peer_model.dart';
import 'homedesk_device_label.dart';
import 'homedesk_peer_menu.dart';
import 'homedesk_theme.dart';

class HomeDeskRecent extends StatefulWidget {
  final List<Peer>? recent, favorites, discovered;
  final ValueChanged<Peer>? onConnect;
  final HomeDeskPeerMenuBuilder? menuBuilder;
  final ValueChanged<PeerTabIndex>? onLoad;
  final ValueChanged<List<String>>? onQueryOnline;
  final WidgetBuilder? classicBuilder;
  final bool summary;
  const HomeDeskRecent(
      {super.key,
      this.recent,
      this.favorites,
      this.discovered,
      this.onConnect,
      this.menuBuilder,
      this.onLoad,
      this.onQueryOnline,
      this.classicBuilder,
      this.summary = false});
  @override
  State<HomeDeskRecent> createState() => HomeDeskRecentState();
}

class HomeDeskRecentState extends State<HomeDeskRecent>
    with WindowListener, WidgetsBindingObserver {
  int _selected = 0;
  List<Peers> _models = [];
  Timer? _onlineTimer;
  final _search = TextEditingController();
  bool _visible = false,
      _active = true,
      _minimized = false,
      _reloadQueued = false;
  DateTime? _restoredAt;
  PeerTabIndex get _tab =>
      [PeerTabIndex.recent, PeerTabIndex.fav, PeerTabIndex.lan][_selected];
  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    WidgetsBinding.instance.addObserver(this);
    if (widget.recent == null) {
      try {
        _models = [
          gFFI.recentPeersModel,
          gFFI.favoritePeersModel,
          gFFI.lanPeersModel
        ];
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

  List<Peer> get _peers => widget.recent != null
      ? [
          widget.recent!,
          widget.favorites ?? <Peer>[],
          widget.discovered ?? <Peer>[]
        ][_selected]
      : _models.isEmpty
          ? []
          : _models[_selected].peers;
  bool _favorite(Peer peer) =>
      _selected == 1 ||
      (widget.favorites ?? (_models.isEmpty ? <Peer>[] : _models[1].peers))
          .any((p) => p.id == peer.id);
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
    switch (_tab) {
      case PeerTabIndex.recent:
        bind.mainLoadRecentPeers();
      case PeerTabIndex.fav:
        bind.mainLoadFavPeers();
      case PeerTabIndex.lan:
        bind.mainLoadLanPeers();
        bind.mainDiscover();
      default:
        break;
    }
    // 最近记录和发现设备的收藏标记也消费已有收藏模型。
    if (_tab != PeerTabIndex.fav) {
      bind.mainLoadFavPeers();
    }
  }

  void _select(int value) {
    setState(() => _selected = value);
    _scheduleReload();
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
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            const SnackBar(content: Text('对端操作暂不可用，请打开经典视图重试。')));
      }
    }
  }

  Future<void> _classic() async {
    await showDialog<void>(
        context: context,
        builder: (context) => Dialog(
            insetPadding: const EdgeInsets.all(16),
            child: SizedBox(
                width: 1100,
                height: MediaQuery.sizeOf(context).height - 32,
                child: Column(children: [
                  Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
                      child: Row(children: [
                        const Expanded(child: Text('经典视图')),
                        IconButton(
                            tooltip: '关闭经典视图',
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close_rounded))
                      ])),
                  Expanded(
                      child: widget.classicBuilder?.call(context) ??
                          const ConnectionPage())
                ]))));
    if (mounted) {
      _scheduleReload();
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

  Widget _row(BuildContext context, Peer peer) {
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
        if (_favorite(peer)) ...[
          const SizedBox(width: 6),
          Icon(Icons.star_rounded, color: t.accent, size: 16)
        ]
      ]),
      const SizedBox(height: 4),
      Text(
          '设备 ID：${peer.id}${peer.platform.isEmpty ? '' : ' · ${peer.platform}'}',
          style: t.auxiliaryStyle),
      const SizedBox(height: 6),
      HomeDeskBadge(peer.online ? '在线' : '离线',
          tone: peer.online ? HomeDeskTone.success : HomeDeskTone.neutral),
    ]);
    final actions = Row(mainAxisSize: MainAxisSize.min, children: [
      OutlinedButton(
          onPressed: () {
            if (widget.onConnect != null) {
              widget.onConnect!(peer);
            } else {
              connectInPeerTab(context, peer, _tab);
            }
          },
          child: const Text('连接')),
      const SizedBox(width: 4),
      Builder(
          builder: (anchor) => IconButton(
              key: ValueKey('recent-more-${peer.id}'),
              tooltip: '更多对端操作',
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
                    Icon(Icons.computer_rounded, color: t.secondary, size: 28),
                    const SizedBox(width: 12),
                    Expanded(child: detail),
                    const SizedBox(width: 12),
                    actions
                  ]);
                }))));
  }

  Widget _body(BuildContext context) {
    final peers = _filtered;
    if (widget.summary) {
      return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: peers.isEmpty
              ? [
                  Text('还没有最近连接记录。',
                      style: HomeDeskTokens.of(context).auxiliaryStyle)
                ]
              : peers.take(2).map((p) => _row(context, p)).toList());
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(
            child: HomeDeskSegments(
                labels: const ['最近', '收藏', '局域网发现'],
                selected: _selected,
                onSelected: _select,
                keyPrefix: 'recent-filter')),
        TextButton(onPressed: _classic, child: const Text('经典视图'))
      ]),
      const SizedBox(height: 12),
      TextField(
          key: const ValueKey('recent-search'),
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
              hintText: '搜索设备名称或 ID', prefixIcon: Icon(Icons.search_rounded))),
      const SizedBox(height: HomeDeskTokens.moduleGap),
      Expanded(
          child: peers.isEmpty
              ? Align(
                  alignment: Alignment.topLeft,
                  child: Card(
                      child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(_search.text.trim().isNotEmpty
                              ? '没有找到匹配的设备。'
                              : [
                                  '还没有最近连接记录，可使用“手动连接”开始。',
                                  '还没有收藏的设备。',
                                  '暂未发现局域网设备，请确认设备发现已启用。'
                                ][_selected]))))
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
