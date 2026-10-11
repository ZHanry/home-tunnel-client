import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/homedesk_account.dart';
import 'package:flutter_hbb/homedesk_dashboard.dart';
import 'package:flutter_hbb/homedesk_family_devices.dart';
import 'package:flutter_hbb/homedesk_title_bar.dart';
import 'package:flutter_hbb/nestlink_dialog.dart';
import 'package:flutter_hbb/nestlink_locale.dart';
import 'package:flutter_hbb/nestlink_workspace.dart';

import 'homedesk_family_devices_test.dart' as family;

class _UpdateApi extends family.FamilyApi {
  final updateComponents = <String>[];

  @override
  Future<Map<String, dynamic>> releaseUpdate(String component) async {
    updateComponents.add(component);
    return {
      'version': nestlinkVersion,
      'notes': 'Synthetic release notes from the signed-in account.',
      'url':
          'https://github.com/ZHanry/home-tunnel-client/releases/tag/v$nestlinkVersion',
    };
  }
}

void main() {
  testWidgets(
      'Linux desktop opens version from its production dashboard menu when signed out and signed in',
      (tester) async {
    expect(Platform.isLinux, isTrue);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1120, 760);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(() => nestlinkRelease.value = null);
    addTearDown(() => nestlinkLanguage.value = 'zh-cn');

    for (final signedIn in [false, true]) {
      for (final english in [false, true]) {
        nestlinkLanguage.value = english ? 'en' : 'zh-cn';
        nestlinkRelease.value = null;
        final account = HomeDeskAccount();
        final api = _UpdateApi()..signedIn = signedIn;
        if (signedIn) {
          account.publish(api, family.catalog(), family.one, (_) async {});
        }
        await tester.pumpWidget(MaterialApp(
            theme: ThemeData(platform: TargetPlatform.linux),
            home: Scaffold(
                body: HomeDeskDashboard(
                    brandName: 'NestLink',
                    devicesBuilder: (_) => HomeDeskFamilyDevices(
                        account: account,
                        listLayout: true,
                        onLogin: () {},
                        onConnect: (_) {},
                        readOption: family.option),
                    recentBuilder: (_) => const SizedBox(),
                    servicesBuilder: (_) => const Text('Synthetic login'),
                    statusBuilder: (_) => const SizedBox(),
                    onConnect: (_) {}))));
        await tester.pumpAndSettle();

        // The Linux production shell does not add the Windows title bar.
        expect(find.byType(HomeDeskTitleBar), findsNothing);
        expect(find.byKey(const ValueKey('mobile-account')), findsNothing);
        expect(find.byKey(const ValueKey('mobile-navigation')), findsNothing);
        final menu =
            find.byTooltip(english ? 'Preferences and version' : '偏好与版本');
        expect(menu.hitTestable(), findsOneWidget);
        await tester.tap(menu);
        await tester.pumpAndSettle();
        final version = find.text(english ? 'Version and downloads' : '版本与下载');
        expect(version.hitTestable(), findsOneWidget);
        await tester.tap(version);
        await tester.pumpAndSettle();

        expect(find.byType(NestLinkDialog), findsOneWidget);
        expect(find.text(nestlinkVersion), findsOneWidget);
        expect(
            find
                .text(english ? 'Release notes and download' : '版本与下载')
                .hitTestable(),
            findsOneWidget);
        expect(api.updateComponents, signedIn ? ['client'] : isEmpty);
        if (signedIn) {
          expect(
              find.text(english
                  ? 'Available version: $nestlinkVersion'
                  : '可用版本: $nestlinkVersion'),
              findsOneWidget);
          expect(
              find.text('Synthetic release notes from the signed-in account.'),
              findsOneWidget);
        }
        await tester.tap(find.text(english ? 'Close' : '关闭'));
        await tester.pumpAndSettle();
        expect(find.byType(NestLinkDialog), findsNothing);
        expect(menu.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox());
        account.dispose();
        api.close();
      }
    }
  }, skip: !Platform.isLinux);
}
