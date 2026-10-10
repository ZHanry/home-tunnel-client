// HOMEDESK: 复用上游卡片提供的公开菜单 builder，动作、确认和可用条件仍由上游负责。
import 'package:flutter/material.dart';
import 'common/widgets/peer_card.dart';
import 'models/peer_model.dart';
import 'models/peer_tab_model.dart';
import 'desktop/widgets/material_mod_popup_menu.dart' as peer_menu;

typedef HomeDeskPeerMenuBuilder = Future<List<peer_menu.PopupMenuEntry<String>>>
    Function(BuildContext context, Peer peer, PeerTabIndex tab);

PopupMenuEntryBuilder homeDeskUpstreamMenuBuilder(Widget card) {
  // 上游的内部 widget 类型未导出，公开字段 popupMenuEntryBuilder 是它的菜单接线。
  // 动态访问仅集中在这一处；不复制动作实现，也不改 PeerTabPage/peer_card。
  final PopupMenuEntryBuilder builder = (card as dynamic).popupMenuEntryBuilder;
  return builder;
}

Future<List<peer_menu.PopupMenuEntry<String>>> homeDeskPeerMenu(
    BuildContext context, Peer peer, PeerTabIndex tab) {
  final BasePeerCard card = switch (tab) {
    PeerTabIndex.lan => DiscoveredPeerCard(peer: peer, showFavorites: false),
    _ => RecentPeerCard(peer: peer, showFavorites: false),
  };
  return homeDeskUpstreamMenuBuilder(card.build(context))(context);
}
