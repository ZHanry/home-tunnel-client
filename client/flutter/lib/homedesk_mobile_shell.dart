// HOMEDESK: Compact navigation shares the desktop tokens without fixed desktop widths.
import 'package:flutter/material.dart';
import 'homedesk_theme.dart';
import 'homedesk_account.dart';
import 'homedesk_dashboard.dart';
import 'homedesk_family_devices.dart';

/// The production mobile entry reuses the desktop directory and account owner.
/// Native screen capture controls remain supplied by the Android host page.
class NestLinkMobileHome extends StatelessWidget {
  final HomeDeskAccount account;
  final String Function(String) readOption;
  final ValueChanged<String> onConnect;
  final WidgetBuilder servicesBuilder, recentBuilder;
  final WidgetBuilder? localBuilder;
  final WidgetBuilder? devicePreferencesBuilder;
  final VoidCallback? onNetworkSettings;
  final ValueChanged<ThemeMode>? onTheme;
  final ValueChanged<String>? onLanguage;
  final VoidCallback? onVersion;
  const NestLinkMobileHome({
    super.key,
    required this.account,
    required this.readOption,
    required this.onConnect,
    required this.servicesBuilder,
    required this.recentBuilder,
    this.localBuilder,
    this.devicePreferencesBuilder,
    this.onNetworkSettings,
    this.onTheme,
    this.onLanguage,
    this.onVersion,
  });

  @override
  Widget build(BuildContext context) => Scaffold(
      body: SafeArea(
          child: HomeDeskDashboard(
              brandName: 'NestLink',
              initializeAccount: true,
              mobilePlatform: true,
              devicesBuilder: (_) => HomeDeskFamilyDevices(
                  account: account,
                  listLayout: true,
                  onLogin: () => HomeDeskDashboard.navigate('account'),
                  onConnect: onConnect,
                  readOption: readOption),
              recentBuilder: recentBuilder,
              servicesBuilder: servicesBuilder,
              localBuilder: localBuilder,
              devicePreferencesBuilder: devicePreferencesBuilder,
              statusBuilder: (_) => const SizedBox.shrink(),
              onNetworkSettings: onNetworkSettings,
              onTheme: onTheme,
              onLanguage: onLanguage,
              onVersion: onVersion,
              onConnect: onConnect)));
}

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
