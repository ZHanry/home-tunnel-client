// HOMEDESK: 返工回归全部使用合成数据和注入动作，不读取用户状态。
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:flutter_hbb/common/widgets/peer_card.dart';
import 'package:flutter_hbb/desktop/widgets/material_mod_popup_menu.dart'
    as peer_menu;
import 'package:flutter_hbb/homedesk_account.dart';
import 'package:flutter_hbb/homedesk_dashboard.dart';
import 'package:flutter_hbb/homedesk_local_agent.dart';
import 'package:flutter_hbb/homedesk_peer_menu.dart';
import 'package:flutter_hbb/homedesk_recent.dart';
import 'package:flutter_hbb/homedesk_services.dart';
import 'package:flutter_hbb/homedesk_settings_shell.dart';
import 'package:flutter_hbb/homedesk_status.dart';
import 'package:flutter_hbb/homedesk_theme.dart';
import 'package:flutter_hbb/homedesk_tunnel_api.dart';
import 'package:flutter_hbb/models/peer_model.dart';
import 'package:flutter_hbb/models/peer_tab_model.dart';
import 'homedesk_family_devices_test.dart' as family;
import 'homedesk_services_test.dart' as portal;
import 'homedesk_hearth_test.dart' as hearth;

Widget host(Widget child) => MaterialApp(
    theme: homeDeskTheme(ThemeData.light()), home: Scaffold(body: child));
Peer device(String id, String name) =>
    Peer.fromJson({'id': id, 'alias': name, 'platform': 'Windows'});
HomeDeskLocalAgent failedAgent() => HomeDeskLocalAgent(
    send: (_) async {},
    read: () => '{}',
    permission: () => 'fixture',
    isAllowed: () => true,
    name: '合成设备')
  ..error = const HomeDeskAgentException('RUNTIME_FAILED');
void main() {
  testWidgets('上游三个对端卡片的公开菜单接线可复用，无需修改上游', (tester) async {
    final peer = device('123456789', '书房电脑');
    await tester.pumpWidget(host(Builder(builder: (context) {
      for (final card in [
        RecentPeerCard(peer: peer),
        FavoritePeerCard(peer: peer),
        DiscoveredPeerCard(peer: peer)
      ]) {
        expect(homeDeskUpstreamMenuBuilder(card.build(context)),
            isA<PopupMenuEntryBuilder>());
      }
      return const SizedBox.shrink();
    })));
    expect(tester.takeException(), isNull);
  });
  testWidgets('对端菜单动作可达并调用注入动作，搜索按名称和ID过滤，仅保留账号设备入口', (tester) async {
    final peer = device('123456789', '书房电脑'),
        other = device('987654321', '客厅电脑');
    final calls = <String>[];
    final labels = [
      '加入收藏',
      '删除记录',
      '忘记密码',
      '重命名',
      '文件传输',
      '终端',
      'TCP 隧道',
      'RDP'
    ];
    final tabs = <PeerTabIndex>[];
    await tester.pumpWidget(host(HomeDeskRecent(
        recent: [peer, other],
        favorites: [peer],
        menuBuilder: (context, p, tab) async {
          expect(p.id, peer.id);
          tabs.add(tab);
          return [
            ...labels,
            if (tab == PeerTabIndex.fav) '取消收藏',
            if (tab == PeerTabIndex.lan) '远程开机'
          ]
              .map((label) => peer_menu.PopupMenuItem<String>(
                  value: label,
                  child: Text(label),
                  onTap: () => calls.add(label)))
              .toList();
        })));
    for (final label in labels) {
      await tester.tap(find.byKey(const ValueKey('recent-more-123456789')));
      await tester.pumpAndSettle();
      expect(find.text(label), findsOneWidget);
      await tester.ensureVisible(find.text(label));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(calls.last, label);
    }
    await tester.enterText(find.byKey(const ValueKey('recent-search')), '书房');
    await tester.pump();
    expect(find.text('书房电脑'), findsOneWidget);
    expect(find.text('客厅电脑'), findsNothing);
    await tester.enterText(
        find.byKey(const ValueKey('recent-search')), '987654');
    await tester.pump();
    expect(find.text('客厅电脑'), findsOneWidget);
    expect(find.text('书房电脑'), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('recent-search')), '');
    await tester.pump();
    for (final pair in [(1, '取消收藏')]) {
      await tester.tap(find.byKey(ValueKey('recent-filter-${pair.$1}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('recent-more-123456789')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text(pair.$2));
      await tester.pumpAndSettle();
      await tester.tap(find.text(pair.$2));
      await tester.pumpAndSettle();
      expect(calls.last, pair.$2);
    }
    expect(tabs, containsAll([PeerTabIndex.recent, PeerTabIndex.fav]));
    expect(find.text('经典视图'), findsNothing);
    expect(find.text('局域网发现'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('最近页和首页摘要导航重新可见时重载，远控返回窗口时重载当前分段', (tester) async {
    final peer = device('123456789', '书房电脑'), loads = <String>[];
    final summaryKey = GlobalKey<HomeDeskRecentState>(),
        recentKey = GlobalKey<HomeDeskRecentState>();
    await tester.pumpWidget(host(HomeDeskDashboard(
        brandName: '合成品牌',
        devicesBuilder: (_) => HomeDeskRecent(
            key: summaryKey,
            summary: true,
            recent: [peer],
            onLoad: (tab) => loads.add('summary:$tab')),
        recentBuilder: (_) => HomeDeskRecent(
            key: recentKey,
            recent: [peer],
            favorites: [peer],
            onLoad: (tab) => loads.add('recent:$tab')),
        localBuilder: (_) => const SizedBox(),
        statusBuilder: (_) => const SizedBox(),
        onSettings: () {},
        onConnect: (_) {})));
    await tester.pumpAndSettle();
    expect(loads.where((s) => s.startsWith('summary:')).length, 1);
    await tester.tap(find.byTooltip('最近连接'));
    await tester.pumpAndSettle();
    expect(loads.last, 'recent:PeerTabIndex.recent');
    await tester.tap(find.byKey(const ValueKey('recent-filter-1')));
    await tester.pumpAndSettle();
    expect(loads.last, 'recent:PeerTabIndex.fav');
    await tester.tap(find.byTooltip('家庭设备'));
    await tester.pumpAndSettle();
    expect(loads.where((s) => s.startsWith('summary:')).length, 2);
    await tester.tap(find.byTooltip('最近连接'));
    await tester.pumpAndSettle();
    final before = loads.length;
    summaryKey.currentState!.onWindowFocus();
    recentKey.currentState!.onWindowFocus();
    await tester.pumpAndSettle();
    expect(loads.length, before + 1);
    expect(loads.last, 'recent:PeerTabIndex.fav');
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
  testWidgets('在线状态可见；失焦、最小化和页面隐藏时暂停查询，恢复后重新加载', (tester) async {
    final key = GlobalKey<HomeDeskRecentState>();
    final peer = device('123456789', '书房电脑')..online = true;
    final queries = <List<String>>[], loads = <PeerTabIndex>[];
    final visible = ValueNotifier(true);
    await tester.pumpWidget(host(ValueListenableBuilder<bool>(
        valueListenable: visible,
        builder: (context, value, _) => TickerMode(
            enabled: value,
            child: HomeDeskRecent(
                key: key,
                recent: [peer],
                onLoad: loads.add,
                onQueryOnline: queries.add)))));
    await tester.pumpAndSettle();
    expect(find.text('● 在线'), findsOneWidget);
    queries.clear();
    key.currentState!.onWindowBlur();
    await tester.pump(const Duration(seconds: 6));
    expect(queries, isEmpty);
    key.currentState!.onWindowFocus();
    await tester.pumpAndSettle();
    expect(queries.single, [peer.id]);
    queries.clear();
    key.currentState!.onWindowMinimize();
    await tester.pump(const Duration(seconds: 6));
    expect(queries, isEmpty);
    key.currentState!.onWindowRestore();
    await tester.pumpAndSettle();
    expect(queries.single, [peer.id]);
    queries.clear();
    visible.value = false;
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 6));
    expect(queries, isEmpty);
    final before = loads.length;
    visible.value = true;
    await tester.pumpAndSettle();
    expect(loads.length, before + 1);
    await tester.pumpWidget(const SizedBox());
    visible.dispose();
    expect(tester.takeException(), isNull);
  });
  for (final epochOnly in [false, true]) {
    testWidgets('接入对话框${epochOnly ? '代次变化' : '撤权'}后关闭，旧重试回调不请求也不锁死',
        (tester) async {
      final api = portal.PortalFixtureApi();
      var allowed = true, permission = 'permit-before', retries = 0;
      var owner = api;
      final page = HomeDeskServices(
          readOption: (key) => portal.portalOption(key,
              allowed: allowed, permission: permission),
          saveOrigin: (_) async {},
          credentialStoreFactory: () => portal.FixtureCredentialStore(),
          apiBuilder: (origin, {required isAllowed, credentialStorage}) =>
              owner,
          localAgent: failedAgent(),
          onRetryLocal: (owner, generation) async {
            retries++;
          });
      await tester.pumpWidget(portal.portalHost(page: page));
      await portal.enterCredentials(tester);
      await tester.tap(find.byKey(const ValueKey('tunnel-connection-notice')));
      await tester.pumpAndSettle();
      final stale = tester
          .widget<TextButton>(find.byKey(const ValueKey('tunnel-retry-local')))
          .onPressed;
      if (epochOnly) {
        permission = 'permit-after';
      } else {
        allowed = false;
      }
      // 在轮询之前模拟已经分发、仍握有旧按钮的事件，验证点击时重新读取许可。
      stale!();
      await tester.pumpAndSettle();
      expect(retries, 0);
      expect(api.closed, isTrue);
      expect(find.byType(AlertDialog), findsNothing);
      allowed = true;
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<FilledButton>(find.byKey(const ValueKey('tunnel-login')))
              .onPressed,
          isNotNull);
      owner = portal.PortalFixtureApi();
      await portal.enterCredentials(tester);
      await tester.tap(find.byKey(const ValueKey('tunnel-connection-notice')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('tunnel-retry-local')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('tunnel-retry-local')));
      await tester.pumpAndSettle();
      expect(retries, 1);
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets('重试接入在途互斥，抛异常后finally释放忙状态', (tester) async {
    final api = portal.PortalFixtureApi(), pending = Completer<void>();
    var retries = 0;
    await tester.pumpWidget(portal.portalHost(
        page: HomeDeskServices(
            readOption: portal.portalOption,
            saveOrigin: (_) async {},
            credentialStoreFactory: () => portal.FixtureCredentialStore(),
            apiBuilder: (origin, {required isAllowed, credentialStorage}) =>
                api,
            localAgent: failedAgent(),
            onRetryLocal: (owner, generation) {
              expect(owner, same(api));
              retries++;
              return pending.future;
            })));
    await portal.enterCredentials(tester);
    await tester.tap(find.byKey(const ValueKey('tunnel-connection-notice')));
    await tester.pumpAndSettle();
    final retry = find.byKey(const ValueKey('tunnel-retry-local'));
    final action = tester.widget<TextButton>(retry).onPressed;
    action!();
    await tester.pump();
    expect(retries, 1);
    expect(tester.widget<TextButton>(retry).onPressed, isNull);
    action();
    await tester.pump();
    expect(retries, 1);
    expect(find.text('已有操作正在进行，请稍后重试。'), findsOneWidget);
    pending.completeError(const FormatException('合成接入失败'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextButton>(retry).onPressed, isNotNull);
    expect(find.text('本机接入未完成，请检查后重试。'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('服务状态工具右对齐并显示主机，页头设备筛选与添加按钮等高', (tester) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = portal.PortalFixtureApi();
    await tester.pumpWidget(host(Padding(
        padding: const EdgeInsets.all(24), child: portal.fixturePage(api))));
    await portal.enterCredentials(tester);
    expect(find.text('console.example.com'), findsOneWidget);
    final strip =
        tester.getRect(find.byKey(const ValueKey('tunnel-account-status')));
    final menu =
        tester.getRect(find.byKey(const ValueKey('tunnel-account-menu')));
    expect(menu.right, closeTo(strip.right - 13, .5));
    final filter =
        tester.getSize(find.byKey(const ValueKey('tunnel-device-filter')));
    final add =
        tester.getSize(find.byKey(const ValueKey('tunnel-add-service')));
    expect(filter.height, closeTo(add.height, .5));
    expect(add.height, greaterThanOrEqualTo(40));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('需处理排除未同步本机；离线包含未同步的离线设备', (tester) async {
    final api = family.FamilyApi()..signedIn = true,
        account = HomeDeskAccount();
    final catalog = HomeTunnelCatalog(devices: const [
      HomeTunnelDevice(
          id: family.one, name: '未同步本机', platform: 'windows', online: true),
      HomeTunnelDevice(
          id: family.two, name: '在线电脑', platform: 'windows', online: true),
      HomeTunnelDevice(
          id: hearth.third, name: '离线待同步电脑', platform: 'linux', online: false),
      HomeTunnelDevice(
          id: hearth.fourth, name: '在线待同步电脑', platform: 'linux', online: true),
    ], services: []);
    api.result = catalog;
    api.bindings = [api.bindings.last];
    account.publish(api, catalog, family.one, (_) async {});
    await tester.pumpWidget(family.familyHost(account, (_) {}));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('family-filter-3')));
    await tester.pumpAndSettle();
    expect(find.text('未同步本机'), findsNothing);
    expect(find.text('离线待同步电脑'), findsOneWidget);
    expect(find.text('在线待同步电脑'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('family-filter-2')));
    await tester.pumpAndSettle();
    expect(find.text('离线待同步电脑'), findsOneWidget);
    expect(find.text('在线待同步电脑'), findsNothing);
    expect(find.text('在线电脑'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    account.dispose();
    api.close();
    expect(tester.takeException(), isNull);
  });
  testWidgets('800×600窄栏全部导航项完整可见，家庭账号不被底栏遮挡', (tester) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final account = HomeDeskAccount(),
        api = hearth.HearthApi()..signedIn = true;
    account.publish(api, hearth.hearthCatalog(), family.one, (_) async {});
    await tester.pumpWidget(hearth.hearthHost(
        account: account,
        api: api,
        dark: true,
        dashboard: GlobalKey<HomeDeskDashboardState>()));
    await tester.pumpAndSettle();
    final footer = tester.getRect(
        find.byWidgetPredicate((w) => w is HomeDeskStatus && w.footer));
    for (final value in [
      'devices',
      'recent',
      'services',
      'local',
      'settings',
      'account'
    ]) {
      final item = find.byKey(ValueKey('nav-$value'));
      expect(item.hitTestable(), findsOneWidget);
      final rect = tester.getRect(item);
      expect(rect.top, greaterThanOrEqualTo(44));
      expect(rect.bottom, lessThanOrEqualTo(footer.top));
    }
    await tester.pumpWidget(const SizedBox());
    account.dispose();
    api.close();
    expect(tester.takeException(), isNull);
  });
  testWidgets('正常状态只在底栏显示，停止服务提示复用启动回调', (tester) async {
    var starts = 0;
    await tester.pumpWidget(host(const HomeDeskStatus(
        exceptionOnly: true,
        data: HomeDeskStatusData(
            mode: '纯内网模式', server: '远控服务器已连接', tone: HomeDeskTone.success))));
    expect(find.textContaining('远控服务器'), findsNothing);
    await tester.pumpWidget(host(HomeDeskStatus(
        exceptionOnly: true,
        data:
            const HomeDeskStatusData(server: '远控后台服务已停止', serviceStopped: true),
        onStartService: () async {
          starts++;
        })));
    await tester.tap(find.byKey(const ValueKey('status-start-service')));
    await tester.pumpAndSettle();
    expect(starts, 1);
    expect(tester.takeException(), isNull);
  });
  testWidgets('后台服务取上游状态，停止为描边而启动保留主色，取不到状态不猜测', (tester) async {
    final stopped = false.obs;
    Get.put<RxBool>(stopped, tag: 'stop-service');
    addTearDown(() => Get.delete<RxBool>(tag: 'stop-service'));
    var invoked = 0;
    await tester.pumpWidget(host(HomeDeskSettingsCard(title: '服务', children: [
      ElevatedButton(onPressed: () => invoked++, child: const Text('任意操作文字'))
    ])));
    expect(find.text('后台服务 · 运行中'), findsOneWidget);
    expect(find.byType(OutlinedButton), findsOneWidget);
    await tester.tap(find.byType(OutlinedButton));
    expect(invoked, 1);
    stopped.value = true;
    await tester.pumpAndSettle();
    expect(find.text('后台服务 · 已停止'), findsOneWidget);
    expect(find.byType(ElevatedButton), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    Get.delete<RxBool>(tag: 'stop-service');
    await tester.pumpWidget(host(HomeDeskSettingsCard(title: '服务', children: [
      ElevatedButton(onPressed: () {}, child: const Text('停止'))
    ])));
    expect(find.text('后台服务'), findsOneWidget);
    expect(find.textContaining('状态见右侧'), findsNothing);
  });
  testWidgets('主题下拉转发上游单选值和回调，固定选项继续禁用', (tester) async {
    String? chosen;
    Widget card(bool enabled) => HomeDeskSettingsCard(title: '主题', children: [
          for (final pair in [
            ('light', '浅色'),
            ('dark', '深色'),
            ('system', '跟随系统')
          ])
            GestureDetector(
                child: Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: Row(children: [
                      Radio<String>(
                          value: pair.$1,
                          groupValue: 'system',
                          onChanged:
                              enabled ? (value) => chosen = value : null),
                      Expanded(child: Text(pair.$2)),
                    ]))),
        ]);
    await tester.pumpWidget(host(card(true)));
    final field = find.byKey(const ValueKey('settings-theme-choice'));
    expect(field, findsOneWidget);
    await tester.tap(field);
    await tester.pumpAndSettle();
    await tester.tap(find.text('深色').last);
    await tester.pumpAndSettle();
    expect(chosen, 'dark');
    await tester.pumpWidget(host(card(false)));
    expect(tester.widget<DropdownButtonFormField<String>>(field).onChanged,
        isNull);
    expect(tester.takeException(), isNull);
  });
  test('浅深色的小字号前景与对应背景对比度不低于4.5，图标点击区域不限制为32', () {
    double contrast(Color a, Color b) {
      final x = a.computeLuminance(), y = b.computeLuminance();
      return ((x > y ? x : y) + .05) / ((x > y ? y : x) + .05);
    }

    for (final t in [HomeDeskTokens.light, HomeDeskTokens.dark]) {
      for (final bg in [
        t.background,
        t.chrome,
        t.surface,
        t.surface2,
        t.sunken
      ]) {
        expect(contrast(t.muted, bg), greaterThanOrEqualTo(4.5));
      }
      for (final pair in [
        (t.success, t.successSoft),
        (t.warning, t.warningSoft),
        (t.danger, t.dangerSoft),
        (t.secondary, t.sunken),
        (t.accentText, t.accentSoft)
      ]) {
        expect(contrast(pair.$1, pair.$2), greaterThanOrEqualTo(4.5));
      }
    }
    final style = homeDeskTheme(ThemeData.light()).iconButtonTheme.style!;
    expect(style.minimumSize!.resolve({})!.width, greaterThanOrEqualTo(40));
    expect(style.maximumSize, isNull);
  });
}
