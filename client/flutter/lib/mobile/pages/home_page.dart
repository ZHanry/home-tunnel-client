import 'package:flutter/material.dart';
import 'package:flutter_hbb/mobile/pages/server_page.dart';
import 'package:flutter_hbb/mobile/pages/settings_page.dart';
import 'package:get/get.dart';
import '../../common.dart';
import '../../models/platform_model.dart';
import '../../models/state_model.dart';
import 'connection_page.dart'; // HOMEDESK: Keep upstream web preview imports valid.
import '../../web/settings_page.dart';
import '../../homedesk_account.dart'; // HOMEDESK: Same scoped management model as desktop.
import '../../homedesk_services.dart';
import '../../homedesk_family_devices.dart';
import '../../homedesk_advanced.dart';
import '../../homedesk_mobile_shell.dart';
import '../../homedesk_dashboard.dart';
import '../../homedesk_recent.dart';

abstract class PageShape extends Widget {
  final String title = "";
  final Widget icon = Icon(null);
  final List<Widget> appBarActions = [];
}

class HomePage extends StatefulWidget {
  static final homeKey = GlobalKey<HomePageState>();

  HomePage() : super(key: homeKey);

  @override
  HomePageState createState() => HomePageState();
}

class HomePageState extends State<HomePage> {
  final _account =
      HomeDeskAccount(); // HOMEDESK: One active account per window.
  var _selectedIndex = 0;
  int get selectedIndex => _selectedIndex;
  final List<PageShape> _pages = [];
  int _chatPageTabIndex = -1;
  bool get isChatPageCurrentTab => isAndroid
      ? _selectedIndex == _chatPageTabIndex
      : false; // change this when ios have chat page

  void refreshPages() {
    setState(() {
      initPages();
    });
  }

  @override
  void initState() {
    super.initState();
    initPages();
  }

  void initPages() {
    _pages.clear();
    _chatPageTabIndex = -1;
    if (!bind.isIncomingOnly()) {
      _pages.add(_HomeDeskPage(
          '家庭设备',
          Icons.devices_rounded,
          HomeDeskFamilyDevices(
              account: _account,
              onLogin: () => setState(() => _selectedIndex = 1),
              onConnect: (id) => connect(context, id),
              readOption: (key) => bind.mainGetLocalOption(key: key))));
      _pages.add(_HomeDeskPage(
          '家庭服务',
          Icons.hub_rounded,
          HomeDeskServices(
              account: _account,
              onNetworkSettings: () => showHomeDeskNetworkSettings(context))));
    }
    if (isAndroid && !bind.isOutgoingOnly()) _pages.add(ServerPage());
    _pages.add(SettingsPage());
    if (_selectedIndex >= _pages.length) _selectedIndex = 0;
  }

  Future<void> _manualConnect() async {
    final controller = TextEditingController();
    final id = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
                title: const Text('连接家庭设备'),
                content: TextField(
                    controller: controller,
                    autofocus: true,
                    decoration: const InputDecoration(
                        labelText: '设备 ID',
                        helperText: '远控必须 P2P 直连；失败时不会使用中继。'),
                    onSubmitted: (value) =>
                        Navigator.of(dialogContext).pop(value.trim())),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: const Text('取消')),
                  FilledButton(
                      onPressed: () => Navigator.of(dialogContext)
                          .pop(controller.text.trim()),
                      child: const Text('连接'))
                ]));
    // Keep the controller alive until the dialog's closing animation completes.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    controller.dispose();
    if (id != null && RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(id) && mounted)
      connect(context, id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: SafeArea(child: HomeDeskDashboard(brandName: 'nestlink', initializeAccount: true,
      devicesBuilder: (_) => HomeDeskFamilyDevices(account: _account,
          onLogin: () => HomeDeskDashboard.navigate('account'), onConnect: (id) => connect(context, id),
          readOption: (key) => bind.mainGetLocalOption(key: key)),
      recentBuilder: (_) => const HomeDeskRecent(summary: true),
      servicesBuilder: (_) => HomeDeskServices(account: _account),
      localBuilder: (_) => ServerPage(), statusBuilder: (_) => const SizedBox.shrink(),
      onSettings: () => HomeDeskDashboard.navigate('settings'), onConnect: (id) => connect(context, id))));
  }

  Widget buildLegacy(BuildContext context) {
    return WillPopScope(
        onWillPop: () async {
          if (_selectedIndex != 0) {
            setState(() {
              _selectedIndex = 0;
            });
          } else {
            return true;
          }
          return false;
        },
        child: HomeDeskMobileShell(
          title: appName,
          selectedIndex: _selectedIndex,
          pages: _pages,
          destinations: _pages
              .map((page) =>
                  NavigationDestination(icon: page.icon, label: page.title))
              .toList(),
          onSelected: (index) => setState(() => _selectedIndex = index),
          onConnect: _manualConnect,
          onNetworkSettings: () => showHomeDeskNetworkSettings(context),
        ));
  }

  Widget appTitle() {
    final currentUser = gFFI.chatModel.currentUser;
    final currentKey = gFFI.chatModel.currentKey;
    if (isChatPageCurrentTab &&
        currentUser != null &&
        currentKey.peerId.isNotEmpty) {
      final connected =
          gFFI.serverModel.clients.any((e) => e.id == currentKey.connId);
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Tooltip(
            message: currentKey.isOut
                ? translate('Outgoing connection')
                : translate('Incoming connection'),
            child: Icon(
              currentKey.isOut
                  ? Icons.call_made_rounded
                  : Icons.call_received_rounded,
            ),
          ),
          Expanded(
            child: Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    "${currentUser.firstName}   ${currentUser.id}",
                  ),
                  if (connected)
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color.fromARGB(255, 133, 246, 199)),
                    ).marginSymmetric(horizontal: 2),
                ],
              ),
            ),
          ),
        ],
      );
    }
    return Text(bind.mainGetAppNameSync());
  }
}

class WebHomePage extends StatelessWidget {
  final connectionPage =
      ConnectionPage(appBarActions: <Widget>[const WebSettingsPage()]);

  @override
  Widget build(BuildContext context) {
    stateGlobal.isInMainPage = true;
    handleUnilink(context);
    return Scaffold(
      // backgroundColor: MyTheme.grayBg,
      appBar: AppBar(
        centerTitle: true,
        title: Text("${bind.mainGetAppNameSync()} (Preview)"),
        actions: connectionPage.appBarActions,
      ),
      body: connectionPage,
    );
  }

  handleUnilink(BuildContext context) {
    if (webInitialLink.isEmpty) {
      return;
    }
    final link = webInitialLink;
    webInitialLink = '';
    final splitter = ["/#/", "/#", "#/", "#"];
    var fakelink = '';
    for (var s in splitter) {
      if (link.contains(s)) {
        var list = link.split(s);
        if (list.length < 2 || list[1].isEmpty) {
          return;
        }
        list.removeAt(0);
        fakelink = "rustdesk://${list.join(s)}";
        break;
      }
    }
    if (fakelink.isEmpty) {
      return;
    }
    final uri = Uri.tryParse(fakelink);
    if (uri == null) {
      return;
    }
    final args = urlLinkToCmdArgs(uri);
    if (args == null || args.isEmpty) {
      return;
    }
    bool isFileTransfer = false;
    bool isViewCamera = false;
    bool isTerminal = false;
    String? id;
    String? password;
    for (int i = 0; i < args.length; i++) {
      switch (args[i]) {
        case '--connect':
        case '--play':
          id = args[i + 1];
          i++;
          break;
        case '--file-transfer':
          isFileTransfer = true;
          id = args[i + 1];
          i++;
          break;
        case '--view-camera':
          isViewCamera = true;
          id = args[i + 1];
          i++;
          break;
        case '--terminal':
          isTerminal = true;
          id = args[i + 1];
          i++;
          break;
        case '--terminal-admin':
          setEnvTerminalAdmin();
          isTerminal = true;
          id = args[i + 1];
          i++;
          break;
        case '--password':
          password = args[i + 1];
          i++;
          break;
        default:
          break;
      }
    }
    if (id != null) {
      connect(context, id,
          isFileTransfer: isFileTransfer,
          isViewCamera: isViewCamera,
          isTerminal: isTerminal,
          password: password);
    }
  }
}

// HOMEDESK: PageShape compatibility keeps the upstream mobile host/settings pages.
class _HomeDeskPage extends StatelessWidget implements PageShape {
  @override
  final String title;
  @override
  final Widget icon;
  @override
  final List<Widget> appBarActions = const [];
  final Widget child;
  _HomeDeskPage(this.title, IconData glyph, this.child) : icon = Icon(glyph);
  @override
  Widget build(BuildContext context) => child;
}
