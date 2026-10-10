import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/homedesk_account.dart';
import 'package:flutter_hbb/homedesk_theme.dart';
import 'package:flutter_hbb/homedesk_tunnel_api.dart';
import 'package:flutter_hbb/nestlink_workspace.dart';
import 'homedesk_family_devices_test.dart' as family;
import 'homedesk_services_test.dart' as portal;
import 'nestlink_desktop_14_test.dart' as desktop;

Finder control(String key) => find.byKey(ValueKey(key));

Rect fieldBorder(WidgetTester tester, Finder field) {
  final editable =
      find.descendant(of: field, matching: find.byType(EditableText));
  final box = InputDecorator.containerOf(tester.element(editable))!;
  return box.localToGlobal(Offset.zero) & box.size;
}

Rect filterBorder(WidgetTester tester) {
  final selected = find
      .descendant(
          of: control('tunnel-device-filter'), matching: find.text('全部设备'))
      .first;
  final box = InputDecorator.containerOf(tester.element(selected))!;
  return box.localToGlobal(Offset.zero) & box.size;
}

void main() {
  for (final scale in [1.0, 1.25, 2.0]) {
    testWidgets('remote controls have equal height at $scale text scale',
        (tester) async {
      tester.view.physicalSize = const Size(800, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
          theme: homeDeskTheme(ThemeData()),
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!),
          home: Scaffold(
              body: NestLinkRemoteWorkspace(
                  onConnect: (_) {},
                  recent: const SizedBox(),
                  status: const SizedBox()))));
      await tester.ensureVisible(control('remote-connect'));
      final field = tester.getRect(control('remote-device-id'));
      final border = fieldBorder(tester, control('remote-device-id'));
      final button = tester.getRect(control('remote-connect'));
      expect(field.height, closeTo(button.height, .1));
      expect(border.height, closeTo(button.height, .1));
      if (scale <= 1.35) {
        expect(field.top, closeTo(button.top, .1));
        expect(field.bottom, closeTo(button.bottom, .1));
        expect(border.top, closeTo(button.top, .1));
        expect(border.bottom, closeTo(button.bottom, .1));
      }
      await tester.tap(control('remote-connect'));
      await tester.pump();
      expect(find.text('请输入有效的设备 ID'), findsOneWidget);
      expect(tester.getRect(control('remote-device-id')), field);
      expect(tester.getRect(control('remote-connect')), button);
      expect(tester.takeException(), isNull);
    });
  }

  for (final scale in [1.0, 1.25, 2.0]) {
    testWidgets(
        'device refresh preserves existing rows and positions at $scale text scale',
        (tester) async {
      tester.view.physicalSize = const Size(1120, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final account = HomeDeskAccount(), api = desktop.DesktopApi();
      account.publish(api, desktop.directory(), family.one, (_) async {});
      await tester.pumpWidget(desktop.app(account, scale: scale));
      await tester.pumpAndSettle();
      final before = {
        for (final key in [
          'device-title-tools',
          'device-group-computer',
          'device-row-${family.two}'
        ])
          key: tester.getRect(control(key))
      };
      final search = fieldBorder(tester, control('device-search'));
      final refresh = tester.getRect(control('family-refresh'));
      expect(search.top, closeTo(refresh.top, .1));
      expect(search.bottom, closeTo(refresh.bottom, .1));
      final pending = Completer<HomeTunnelCatalog>();
      api.pendingCatalog = pending;
      await tester.tap(control('family-refresh'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(account.loading, isTrue);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      for (final entry in before.entries) {
        expect(tester.getRect(control(entry.key)), entry.value);
      }
      pending.complete(api.result);
      await tester.pumpAndSettle();
      expect(account.loading, isFalse);
      for (final entry in before.entries) {
        expect(tester.getRect(control(entry.key)), entry.value);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      account.dispose();
      api.close();
    });

    testWidgets(
        'tunnel refresh keeps toolbar and service cards in place at $scale text scale',
        (tester) async {
      tester.view.physicalSize = const Size(1120, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = portal.PortalFixtureApi();
      await tester.pumpWidget(MaterialApp(
          theme: homeDeskTheme(ThemeData()),
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!),
          home: Scaffold(
              body: Padding(
                  padding: const EdgeInsets.all(24),
                  child: portal.fixturePage(api)))));
      await portal.enterCredentials(tester);
      final card = find
          .ancestor(
              of: find.text(api.result.services.first.name),
              matching: find.byType(Container))
          .first;
      expect(card, findsOneWidget);
      final beforeToolbar = tester.getRect(control('tunnel-title-tools'));
      final beforeCard = tester.getRect(card);
      final filter = filterBorder(tester);
      final add = tester.getRect(control('tunnel-add-service'));
      expect(filter.top, closeTo(add.top, .1));
      expect(filter.bottom, closeTo(add.bottom, .1));
      final pending = Completer<HomeTunnelCatalog>();
      api.pendingCatalog = pending;
      await tester.tap(control('tunnel-refresh'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(tester.getRect(control('tunnel-title-tools')), beforeToolbar);
      expect(tester.getRect(card), beforeCard);
      pending.complete(api.result);
      await tester.pumpAndSettle();
      expect(tester.getRect(control('tunnel-title-tools')), beforeToolbar);
      expect(tester.getRect(card), beforeCard);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      api.close();
    });
  }
}
