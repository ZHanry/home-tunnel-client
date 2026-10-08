// HOMEDESK: Compact navigation shares the desktop tokens without fixed desktop widths.
import 'package:flutter/material.dart';
import 'homedesk_theme.dart';

class HomeDeskMobileShell extends StatelessWidget {
  final String title;
  final List<Widget> pages;
  final List<NavigationDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final VoidCallback onConnect;
  final VoidCallback onNetworkSettings;
  const HomeDeskMobileShell(
      {super.key,
      required this.title,
      required this.pages,
      required this.destinations,
      required this.selectedIndex,
      required this.onSelected,
      required this.onConnect,
      required this.onNetworkSettings});

  @override
  Widget build(BuildContext context) {
    final tokens = HomeDeskTokens.of(context);
    return Scaffold(
      backgroundColor: tokens.background,
      appBar: AppBar(
        title: Text(title, style: tokens.titleStyle),
        centerTitle: false,
        backgroundColor: tokens.background,
        actions: [
          IconButton(
              tooltip: '配置 P2P 远控',
              onPressed: onNetworkSettings,
              icon: const Icon(Icons.settings_ethernet_rounded)),
          IconButton(
              tooltip: '通过设备 ID 连接',
              onPressed: onConnect,
              icon: const Icon(Icons.add_to_queue_rounded)),
        ],
      ),
      body: SafeArea(
          top: false,
          child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: IndexedStack(index: selectedIndex, children: pages))),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        destinations: destinations,
        onDestinationSelected: onSelected,
        backgroundColor: tokens.chrome,
        indicatorColor: tokens.accentSoft,
      ),
    );
  }
}
