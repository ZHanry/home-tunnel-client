import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/homedesk_account.dart';
import 'package:flutter_hbb/homedesk_navigation.dart';
import 'package:flutter_hbb/homedesk_theme.dart';
import 'package:flutter_hbb/nestlink_error_messages.dart';
import 'package:flutter_hbb/nestlink_locale.dart';
import 'package:flutter_hbb/nestlink_native_status.dart';
import 'package:flutter_hbb/nestlink_workspace.dart';
import 'homedesk_services_test.dart' as portal;

void main() {
  testWidgets(
      'phone and desktop remote entry show safe guidance and clear old owner',
      (tester) async {
    final language = nestlinkLanguage.value;
    addTearDown(() => nestlinkLanguage.value = language);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final mobile in [true, false]) {
      for (final english in [false, true]) {
        for (final dark in [false, true]) {
          tester.view.physicalSize =
              mobile ? const Size(320, 800) : const Size(1024, 900);
          nestlinkLanguage.value = english ? 'en' : 'zh-cn';
          final account = HomeDeskAccount();
          final old = portal.PortalFixtureApi()..signedIn = true;
          final current = portal.PortalFixtureApi()..signedIn = true;
          account.publish(old, old.result, '', (_) async {});
          account.publishNativeStatus(old, NestLinkNativeStatus.network);
          await tester.pumpWidget(MaterialApp(
              theme: homeDeskTheme(ThemeData(
                  brightness: dark ? Brightness.dark : Brightness.light)),
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(mobile ? 2 : 1)),
                  child: child!),
              home: Scaffold(
                  body: HomeDeskAccountView(
                      account: account,
                      builder: (_) => NestLinkRemoteWorkspace(
                          account: account,
                          mobilePlatform: mobile,
                          onConnect: (_) {},
                          remoteSettingsBuilder: (_) => const SizedBox(),
                          localHost: mobile
                              ? const Text('Android share controls')
                              : null,
                          recent: const SizedBox(),
                          status: const SizedBox())))));
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('remote-native-status')),
              findsOneWidget);
          expect(find.text(NestLinkNativeStatus.network.title(english)),
              findsOneWidget);
          expect(find.text(NestLinkNativeStatus.network.advice(english)),
              findsOneWidget);
          expect(tester.takeException(), isNull);
          account.publish(current, current.result, '', (_) async {});
          account.publishNativeStatus(
              old, NestLinkNativeStatus.certificateRejected);
          await tester.pumpAndSettle();
          expect(account.nativeStatus, NestLinkNativeStatus.idle);
          expect(
              find.byKey(const ValueKey('remote-native-status')), findsNothing);
          account.publishNativeStatus(current, NestLinkNativeStatus.http403);
          await tester.pumpAndSettle();
          expect(find.text(NestLinkNativeStatus.http403.title(english)),
              findsOneWidget);
          account.clear(current);
          account.publishNativeStatus(current, NestLinkNativeStatus.network);
          await tester.pumpAndSettle();
          expect(
              find.byKey(const ValueKey('remote-native-status')), findsNothing);
          expect(account.nativeStatus, NestLinkNativeStatus.idle);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          account.dispose();
          old.close();
          current.close();
        }
      }
    }
  });

  test('other exception presentation translates only fixed native status', () {
    final language = nestlinkLanguage.value;
    addTearDown(() => nestlinkLanguage.value = language);
    for (final english in [false, true]) {
      nestlinkLanguage.value = english ? 'en' : 'zh-cn';
      final failure = NestLinkNativeException(NestLinkNativeStatus.unknown);
      final text = nestlinkErrorMessage(failure);
      expect(text, contains(NestLinkNativeStatus.unknown.title(english)));
      expect(text, contains(NestLinkNativeStatus.unknown.advice(english)));
      expect(text, isNot(contains('NESTLINK_NATIVE_AUTH')));
    }
  });
}
