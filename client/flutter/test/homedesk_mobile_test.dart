// HOMEDESK: Phone navigation retains page state and accommodates large text.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/homedesk_mobile_shell.dart';
import 'package:flutter_hbb/homedesk_theme.dart';

void main() {
  testWidgets('phone navigation and P2P settings work at 320px',
      (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var selected = 0;
    var settings = 0;
    await tester.pumpWidget(MaterialApp(
      theme: homeDeskTheme(ThemeData(useMaterial3: true)),
      home: StatefulBuilder(
          builder: (context, update) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(1.5)),
                child: HomeDeskMobileShell(
                  title: 'HomeDesk',
                  selectedIndex: selected,
                  pages: const [
                    Center(child: Text('设备目录')),
                    Center(child: Text('服务列表')),
                    Center(child: Text('被控设置')),
                    Center(child: Text('应用设置'))
                  ],
                  destinations: const [
                    NavigationDestination(
                        icon: Icon(Icons.devices), label: '家庭设备'),
                    NavigationDestination(icon: Icon(Icons.hub), label: '家庭服务'),
                    NavigationDestination(
                        icon: Icon(Icons.screen_share), label: '共享屏幕'),
                    NavigationDestination(
                        icon: Icon(Icons.settings), label: '设置')
                  ],
                  onSelected: (index) => update(() => selected = index),
                  onConnect: () {},
                  onNetworkSettings: () => settings++,
                ),
              )),
    ));
    await tester.tap(find.text('家庭服务'));
    await tester.pumpAndSettle();
    expect(selected, 1);
    expect(find.text('服务列表'), findsOneWidget);
    await tester.tap(find.byTooltip('配置 P2P 远控'));
    expect(settings, 1);
    expect(tester.takeException(), isNull);
  });
}
