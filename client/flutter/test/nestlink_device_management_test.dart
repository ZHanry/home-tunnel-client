import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/homedesk_account.dart';
import 'package:flutter_hbb/homedesk_family_devices.dart';
import 'package:flutter_hbb/homedesk_theme.dart';
import 'package:flutter_hbb/homedesk_tunnel_api.dart';
import 'homedesk_family_devices_test.dart' as family;

const nas = '20000000-0000-4000-8000-000000000003';
HomeTunnelCatalog directory({bool includeNas = true}) => HomeTunnelCatalog(
        devices: [
          ...family.catalog().devices,
          if (includeNas)
            const HomeTunnelDevice(
                id: nas,
                name: '只有穿透的 NAS',
                platform: 'nas',
                online: true,
                tags: ['存储']),
        ],
        services: includeNas
            ? [
                HomeTunnelService(
                    id: '30000000-0000-4000-8000-000000000001',
                    deviceId: nas,
                    name: '合成相册',
                    proxyType: 'http',
                    status: 'Online',
                    webUrl: Uri.parse('https://album.example.invalid'),
                    endpoint: null,
                    enabled: true),
              ]
            : []);

Widget host(HomeDeskAccount account,
        {double scale = 1, ValueChanged<String>? connect}) =>
    MaterialApp(
        theme: homeDeskTheme(ThemeData()),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!),
        home: Scaffold(
            body: HomeDeskFamilyDevices(
                account: account,
                listLayout: true,
                onLogin: () {},
                onConnect: connect ?? (_) {},
                readOption: family.option)));

class ReviewApi extends family.FamilyApi {
  int catalogReads = 0;
  bool failCatalog = false;

  @override
  Future<HomeTunnelCatalog> catalog() async {
    catalogReads++;
    if (failCatalog) {
      throw const HomeTunnelApiException('合成目录暂不可用', 'NETWORK_ERROR');
    }
    return super.catalog();
  }
}

class StaleBindingAccount extends HomeDeskAccount {
  Map<String, HomeDeskRemoteBinding> staleBindings = {};
  @override
  Map<String, HomeDeskRemoteBinding> get bindings =>
      signedIn ? staleBindings : const {};
}

Future<void> openDeletion(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('device-info-$nas')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('device-delete-$nas')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('revoked remote capability ignores a stale online binding',
      (tester) async {
    final api = family.FamilyApi()..signedIn = true;
    final account = StaleBindingAccount()
      ..staleBindings = {
        for (final binding in api.bindings) binding.deviceId: binding
      };
    account.publish(api, family.catalog(), family.one, (_) async {});
    var connections = 0;
    await tester.pumpWidget(host(account, connect: (_) => connections++));
    await tester.pumpAndSettle();
    final staleConnect = tester
        .widget<FilledButton>(
            find.byKey(const ValueKey('family-connect-${family.two}')))
        .onPressed!;
    final surviving = HomeTunnelCatalog(devices: [
      family.catalog().devices.first,
      const HomeTunnelDevice(
          id: family.two,
          name: '卧室电脑',
          platform: '',
          online: true,
          remoteDeviceId: '',
          tunnelDeviceId: nas,
          tunnelOnline: true),
    ], services: []);
    api.result = surviving;
    account.publish(api, surviving, family.one, (_) async {});
    staleConnect();
    await tester.pumpAndSettle();
    expect(connections, 0);
    expect(account.bindings[family.two]?.online, isTrue);
    final row = find.byKey(const ValueKey('device-row-${family.two}'));
    expect(find.descendant(of: row, matching: find.text('远程协助：未接入')),
        findsOneWidget);
    expect(find.descendant(of: row, matching: find.text('内网穿透：在线')),
        findsOneWidget);
    expect(find.textContaining('987654321'), findsNothing);
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('family-connect-${family.two}')))
            .onPressed,
        isNull);
    await tester.tap(find.byKey(const ValueKey('device-info-${family.two}')));
    await tester.pumpAndSettle();
    expect(find.text('远控：尚未接入'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('device-connect-${family.two}')))
            .onPressed,
        isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    account.dispose();
    api.close();
  });

  testWidgets(
      'one device shows remote and tunnel capabilities with separate states',
      (tester) async {
    final catalog = HomeTunnelCatalog(devices: const [
      HomeTunnelDevice(
          id: family.one,
          name: '当前电脑',
          platform: 'windows',
          online: true,
          tunnelOnline: false),
    ], services: [
      HomeTunnelService(
          id: '30000000-0000-4000-8000-000000000002',
          deviceId: family.one,
          name: '本机相册',
          proxyType: 'http',
          status: 'Offline',
          webUrl: Uri.parse('https://local.example.invalid'),
          endpoint: null,
          enabled: true),
    ]);
    final account = HomeDeskAccount();
    final api = family.FamilyApi()
      ..signedIn = true
      ..result = catalog;
    api.bindings.removeWhere((binding) => binding.deviceId != family.one);
    account.publish(api, catalog, family.one, (_) async {});
    await tester.pumpWidget(host(account));
    await tester.pumpAndSettle();
    final row = find.byKey(const ValueKey('device-row-${family.one}'));
    expect(row, findsOneWidget);
    expect(
        find.byKey(const ValueKey('device-row-${family.two}')), findsNothing);
    expect(find.descendant(of: row, matching: find.text('本机')), findsOneWidget);
    expect(find.descendant(of: row, matching: find.text('远程协助：在线')),
        findsOneWidget);
    expect(find.descendant(of: row, matching: find.text('内网穿透：离线')),
        findsOneWidget);
    expect(
        find.descendant(of: row, matching: find.text('1 项服务')), findsOneWidget);
    expect(find.descendant(of: row, matching: find.text('在线')), findsOneWidget);
    expect(find.byKey(const ValueKey('family-connect-${family.one}')),
        findsNothing);
    await tester.tap(find.byKey(const ValueKey('device-info-${family.one}')));
    await tester.pumpAndSettle();
    expect(find.text('穿透心跳：离线'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    account.dispose();
    api.close();
  });

  testWidgets(
      'device management includes tunnel-only devices and routes tags and services',
      (tester) async {
    final account = HomeDeskAccount();
    final api = family.FamilyApi()
      ..signedIn = true
      ..result = directory();
    String? edited, managed;
    account.publish(
        api, directory(), family.one, (device) async => edited = device.id,
        onManageServices: (device) async => managed = device.id);
    await tester.pumpWidget(host(account));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('device-row-$nas')), findsOneWidget);
    final row = find.byKey(const ValueKey('device-row-$nas'));
    expect(find.descendant(of: row, matching: find.text('远程协助：未接入')),
        findsOneWidget);
    expect(find.descendant(of: row, matching: find.text('内网穿透：在线')),
        findsOneWidget);
    expect(find.textContaining('穿透设备 ·'), findsNothing);
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('family-connect-$nas')))
            .onPressed,
        isNull);
    await tester.tap(find.byKey(const ValueKey('device-info-$nas')));
    await tester.pumpAndSettle();
    expect(find.text('远控：尚未接入'), findsOneWidget);
    expect(find.text('内网穿透：1 项服务'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('device-connect-$nas')))
            .onPressed,
        isNull);
    await tester.tap(find.byKey(const ValueKey('device-tunnels-$nas')));
    await tester.pumpAndSettle();
    expect(managed, nas);
    await tester.tap(find.byKey(const ValueKey('device-info-$nas')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('device-edit-$nas')));
    await tester.pumpAndSettle();
    expect(edited, nas);
    await tester.pumpWidget(const SizedBox());
    account.dispose();
    api.close();
  });

  testWidgets(
      'failed deletion remains visible; explicit retry refreshes the real catalog',
      (tester) async {
    final account = HomeDeskAccount();
    final api = family.FamilyApi()
      ..signedIn = true
      ..result = directory();
    var attempts = 0;
    Future<void> remove(HomeTunnelDevice device) async {
      attempts++;
      if (attempts == 1) {
        throw const HomeTunnelApiException('合成权限拒绝', 'FORBIDDEN');
      }
      api.result = directory(includeNas: false);
      await account.refresh();
    }

    account.publish(api, directory(), family.one, (_) async {},
        onDelete: remove);
    await tester.pumpWidget(host(account));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('device-info-$nas')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('device-delete-$nas')));
    await tester.pumpAndSettle();
    expect(attempts, 0);
    expect(find.textContaining('远程连接与内网穿透访问将停止'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('device-confirm-delete-$nas')));
    await tester.pumpAndSettle();
    expect(attempts, 1);
    expect(find.text('合成权限拒绝'), findsOneWidget);
    expect(account.catalog!.devices.any((device) => device.id == nas), isTrue);
    await tester.tap(find.byKey(const ValueKey('device-confirm-delete-$nas')));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.byKey(const ValueKey('device-row-$nas')), findsNothing);
    expect(account.catalog!.devices.any((device) => device.id == nas), isFalse);
    await tester.pumpWidget(const SizedBox());
    account.dispose();
    api.close();
  });

  testWidgets(
      'tunnel heartbeat keeps a device online while remote authorization remains offline',
      (tester) async {
    final account = HomeDeskAccount();
    final api = family.FamilyApi()
      ..signedIn = true
      ..result = directory();
    final old = api.bindings.last;
    api.bindings[1] = HomeDeskRemoteBinding(
        deviceId: old.deviceId,
        remoteId: old.remoteId,
        server: old.server,
        keySHA256: old.keySHA256,
        platform: old.platform,
        online: false);
    account.publish(api, directory(), family.one, (_) async {},
        onManageServices: (_) async {});
    var connected = 0;
    await tester.pumpWidget(host(account, connect: (_) => connected++));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('family-connect-${family.two}')))
            .onPressed,
        isNull);
    final row = find.byKey(const ValueKey('device-row-${family.two}'));
    expect(find.descendant(of: row, matching: find.text('在线')), findsOneWidget);
    expect(find.descendant(of: row, matching: find.text('远程协助：离线')),
        findsOneWidget);
    expect(find.descendant(of: row, matching: find.text('内网穿透：在线')),
        findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('device-info-${family.two}')));
    await tester.pumpAndSettle();
    expect(find.text('远控：离线'), findsOneWidget);
    expect(find.text('穿透心跳：在线'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('device-connect-${family.two}')))
            .onPressed,
        isNull);
    expect(connected, 0);
    await tester.pumpWidget(const SizedBox());
    account.dispose();
    api.close();
  });

  testWidgets(
      'unknown deletion outcomes require catalog review without replaying deletion',
      (tester) async {
    final account = HomeDeskAccount();
    final api = family.FamilyApi()
      ..signedIn = true
      ..result = directory();
    var attempts = 0;
    account.publish(api, directory(), family.one, (_) async {},
        onDelete: (_) async {
      attempts++;
      throw const HomeTunnelApiException('合成结果未知，请刷新核对。', 'MUTATION_UNKNOWN');
    });
    await tester.pumpWidget(host(account));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('device-info-$nas')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('device-delete-$nas')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('device-confirm-delete-$nas')));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('device-confirm-delete-$nas')))
            .onPressed,
        isNull);
    expect(attempts, 1);
    expect(account.catalog!.devices.any((device) => device.id == nas), isTrue);
    api.result = directory(includeNas: false);
    await tester.tap(find.byKey(const ValueKey('device-delete-review-$nas')));
    await tester.pumpAndSettle();
    expect(attempts, 1);
    expect(
        find.byKey(const ValueKey('device-confirm-delete-$nas')), findsNothing);
    expect(find.byKey(const ValueKey('device-row-$nas')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    account.dispose();
    api.close();
  });

  testWidgets('stale deletion confirmation cannot call a replacement account',
      (tester) async {
    final account = HomeDeskAccount();
    final api = family.FamilyApi()
      ..signedIn = true
      ..result = directory();
    var deletions = 0;
    account.publish(api, directory(), family.one, (_) async {},
        onDelete: (_) async => deletions++);
    await tester.pumpWidget(host(account));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('device-info-$nas')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('device-delete-$nas')));
    await tester.pumpAndSettle();
    final stale = tester
        .widget<FilledButton>(
            find.byKey(const ValueKey('device-confirm-delete-$nas')))
        .onPressed!;
    account.clear(api);
    final replacement = family.FamilyApi()
      ..signedIn = true
      ..result = directory();
    account.publish(replacement, directory(), family.one, (_) async {},
        onDelete: (_) async => deletions++);
    stale();
    await tester.pumpAndSettle();
    expect(deletions, 0);
    expect(find.textContaining('账号或设备已变化'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    account.dispose();
    api.close();
    replacement.close();
  });

  testWidgets(
      'unknown deletion survives cancellation and list recreation; saved callbacks cannot replay',
      (tester) async {
    final account = HomeDeskAccount();
    final api = ReviewApi()
      ..signedIn = true
      ..result = directory();
    var attempts = 0;
    account.publish(api, directory(), family.one, (_) async {},
        onDelete: (_) async {
      attempts++;
      if (attempts == 1) {
        throw const HomeTunnelApiException('合成结果未知', 'MUTATION_UNKNOWN');
      }
      api.result = directory(includeNas: false);
      await account.refresh();
    });
    await tester.pumpWidget(host(account));
    await tester.pumpAndSettle();
    await openDeletion(tester);
    final original = tester
        .widget<FilledButton>(
            find.byKey(const ValueKey('device-confirm-delete-$nas')))
        .onPressed!;
    original();
    await tester.pumpAndSettle();
    expect(account.needsDeviceDeletionReview(api, nas), isTrue);
    original();
    await tester.pumpAndSettle();
    expect(attempts, 1);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await openDeletion(tester);
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('device-confirm-delete-$nas')))
            .onPressed,
        isNull);
    expect(find.byKey(const ValueKey('device-delete-review-$nas')),
        findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(host(account));
    await tester.pumpAndSettle();
    await openDeletion(tester);
    expect(account.needsDeviceDeletionReview(api, nas), isTrue);
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('device-confirm-delete-$nas')))
            .onPressed,
        isNull);
    original();
    await tester.pumpAndSettle();
    expect(attempts, 1);
    await tester.tap(find.byKey(const ValueKey('device-delete-review-$nas')));
    await tester.pumpAndSettle();
    expect(account.needsDeviceDeletionReview(api, nas), isFalse);
    expect(attempts, 1);
    await tester.tap(find.byKey(const ValueKey('device-confirm-delete-$nas')));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.byKey(const ValueKey('device-row-$nas')), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    account.dispose();
    api.close();
  });

  testWidgets(
      'polling and failed review never unlock unknown deletion; a new successful review does',
      (tester) async {
    final account = HomeDeskAccount();
    final api = ReviewApi()
      ..signedIn = true
      ..result = directory();
    var attempts = 0;
    account.publish(api, directory(), family.one, (_) async {},
        onDelete: (_) async {
      attempts++;
      throw const HomeTunnelApiException('合成结果未知', 'MUTATION_UNKNOWN');
    });
    await tester.pumpWidget(host(account));
    await tester.pumpAndSettle();
    await openDeletion(tester);
    await tester.tap(find.byKey(const ValueKey('device-confirm-delete-$nas')));
    await tester.pumpAndSettle();
    api.pending = Completer<List<HomeDeskRemoteBinding>>();
    final polling = account.refresh();
    await tester.pump();
    expect(account.loading, isTrue);
    final catalogReads = api.catalogReads;
    await tester.tap(find.byKey(const ValueKey('device-delete-review-$nas')));
    await tester.pump();
    expect(find.text('设备目录正在刷新，请稍后再核对。'), findsOneWidget);
    expect(api.catalogReads, catalogReads);
    expect(account.needsDeviceDeletionReview(api, nas), isTrue);
    api.pending!.complete(api.bindings);
    await polling;
    api.pending = null;
    await tester.pumpAndSettle();
    expect(account.needsDeviceDeletionReview(api, nas), isTrue);
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('device-confirm-delete-$nas')))
            .onPressed,
        isNull);
    api.failCatalog = true;
    await tester.tap(find.byKey(const ValueKey('device-delete-review-$nas')));
    await tester.pumpAndSettle();
    expect(account.message, isNotEmpty);
    expect(account.needsDeviceDeletionReview(api, nas), isTrue);
    api.failCatalog = false;
    await tester.tap(find.byKey(const ValueKey('device-delete-review-$nas')));
    await tester.pumpAndSettle();
    expect(api.catalogReads, catalogReads + 2);
    expect(account.needsDeviceDeletionReview(api, nas), isFalse);
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('device-confirm-delete-$nas')))
            .onPressed,
        isNotNull);
    expect(attempts, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    account.dispose();
    api.close();
  });

  testWidgets(
      'late unknown deletion and stale review cannot affect a new owner',
      (tester) async {
    final account = HomeDeskAccount();
    final old = ReviewApi()
      ..signedIn = true
      ..result = directory();
    final pendingDeletion = Completer<void>();
    var attempts = 0;
    account.publish(old, directory(), family.one, (_) async {}, onDelete: (_) {
      attempts++;
      return pendingDeletion.future;
    });
    await tester.pumpWidget(host(account));
    await tester.pumpAndSettle();
    await openDeletion(tester);
    final saved = tester
        .widget<FilledButton>(
            find.byKey(const ValueKey('device-confirm-delete-$nas')))
        .onPressed!;
    saved();
    await tester.pump();
    saved();
    expect(attempts, 1);
    account.markDeviceDeletionForReview(old, family.two);
    final replacement = ReviewApi()
      ..signedIn = true
      ..result = directory();
    account.publish(replacement, directory(), family.one, (_) async {},
        onDelete: (_) async => attempts++);
    expect(account.needsDeviceDeletionReview(replacement, family.two), isFalse);
    account.markDeviceDeletionForReview(replacement, family.two);
    pendingDeletion.completeError(
        const HomeTunnelApiException('旧账号删除结果未知', 'MUTATION_UNKNOWN'));
    await tester.pumpAndSettle();
    expect(account.needsDeviceDeletionReview(replacement, nas), isFalse);
    account.completeDeviceDeletionReview(old, family.two);
    account.markDeviceDeletionForReview(old, nas);
    expect(account.needsDeviceDeletionReview(replacement, family.two), isTrue);
    expect(account.needsDeviceDeletionReview(replacement, nas), isFalse);
    saved();
    await tester.pumpAndSettle();
    expect(attempts, 1);
    account.clear(replacement);
    expect(account.needsDeviceDeletionReview(replacement, family.two), isFalse);
    await tester.pumpWidget(const SizedBox());
    account.dispose();
    old.close();
    replacement.close();
  });

  testWidgets(
      'saved review action cannot refresh or unlock a replacement owner',
      (tester) async {
    final account = HomeDeskAccount();
    final old = ReviewApi()
      ..signedIn = true
      ..result = directory();
    account.publish(old, directory(), family.one, (_) async {},
        onDelete: (_) async =>
            throw const HomeTunnelApiException('合成结果未知', 'MUTATION_UNKNOWN'));
    await tester.pumpWidget(host(account));
    await tester.pumpAndSettle();
    await openDeletion(tester);
    await tester.tap(find.byKey(const ValueKey('device-confirm-delete-$nas')));
    await tester.pumpAndSettle();
    final saved = tester
        .widget<TextButton>(
            find.byKey(const ValueKey('device-delete-review-$nas')))
        .onPressed!;
    final replacement = ReviewApi()
      ..signedIn = true
      ..result = directory();
    account.publish(replacement, directory(), family.one, (_) async {},
        onDelete: (_) async {});
    account.markDeviceDeletionForReview(replacement, nas);
    await tester.pumpAndSettle();
    final reads = replacement.catalogReads;
    saved();
    await tester.pumpAndSettle();
    expect(replacement.catalogReads, reads);
    expect(account.needsDeviceDeletionReview(replacement, nas), isTrue);
    expect(find.textContaining('账号已变化'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    account.dispose();
    old.close();
    replacement.close();
  });

  testWidgets('management and deletion fit narrow windows with large text',
      (tester) async {
    tester.view.physicalSize = const Size(360, 560);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final account = HomeDeskAccount();
    final api = family.FamilyApi()
      ..signedIn = true
      ..result = directory();
    account.publish(api, directory(), family.one, (_) async {},
        onManageServices: (_) async {}, onDelete: (_) async {});
    await tester.pumpWidget(host(account, scale: 2));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('device-info-$nas')));
    await tester.tap(find.byKey(const ValueKey('device-info-$nas')));
    await tester.pumpAndSettle();
    expect(find.text('关闭').hitTestable(), findsOneWidget);
    expect(find.byKey(const ValueKey('device-delete-$nas')).hitTestable(),
        findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('device-delete-$nas')));
    await tester.pumpAndSettle();
    expect(find.text('取消').hitTestable(), findsOneWidget);
    expect(
        find.byKey(const ValueKey('device-confirm-delete-$nas')).hitTestable(),
        findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    account.dispose();
    api.close();
  });
}
