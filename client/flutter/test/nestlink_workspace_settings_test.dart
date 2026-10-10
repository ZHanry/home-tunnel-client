import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/homedesk_account.dart';
import 'package:flutter_hbb/homedesk_navigation.dart';
import 'package:flutter_hbb/homedesk_theme.dart';
import 'package:flutter_hbb/nestlink_account_page.dart';
import 'package:flutter_hbb/nestlink_dialog.dart';
import 'package:flutter_hbb/nestlink_workspace.dart';
import 'homedesk_services_test.dart' as portal;

class AccountFixtureApi extends portal.PortalFixtureApi {
  List<Map<String, dynamic>> sessions = [];
  final revoked = <String>[];

  @override
  Future<Map<String, dynamic>> accountSummary() async => {
        'month_to_date_bytes': 1048576,
        'monthly_quota_bytes': 1073741824,
      };

  @override
  Future<List<Map<String, dynamic>>> managementSessions() async => sessions;

  @override
  Future<void> revokeManagementSession(String sessionId) async {
    revoked.add(sessionId);
  }
}

Finder _verticalScrollables() => find.byWidgetPredicate((widget) =>
    widget is Scrollable &&
    (widget.axisDirection == AxisDirection.down ||
        widget.axisDirection == AxisDirection.up));

Widget _workspace(
    {HomeDeskAccount? account, required WidgetBuilder settingsBuilder}) {
  Widget build(BuildContext context) => NestLinkRemoteWorkspace(
      account: account,
      onConnect: (_) {},
      recent: const SizedBox(),
      status: const SizedBox(),
      remoteSettingsBuilder: settingsBuilder);
  return account == null
      ? Builder(builder: build)
      : HomeDeskAccountView(account: account, builder: build);
}

void main() {
  testWidgets(
      'signed-out account and local settings share one scroll area with login and network actions',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var login = 0, network = 0;
    await tester.pumpWidget(MaterialApp(
        theme: homeDeskTheme(ThemeData()),
        home: Scaffold(
            body: NestLinkAccountPage(
                onLogin: () => login++,
                settingsBuilder: (_) => NestLinkSettings(
                    embedded: true, onNetworkSettings: () => network++)))));
    expect(find.text('外观'), findsNothing);
    expect(find.text('语言'), findsNothing);
    expect(find.text('版本'), findsNothing);
    expect(find.text('跟随系统'), findsNothing);
    expect(find.text('网络配置'), findsOneWidget);
    expect(
        find.byKey(const ValueKey('settings-remote-password')), findsNothing);
    expect(find.byKey(const ValueKey('settings-host-authorization')),
        findsNothing);
    expect(find.text('账号'), findsOneWidget);
    expect(find.text('本机共享与授权'), findsNothing);
    expect(find.text('密码、额度与会话'), findsNothing);
    expect(find.byKey(const ValueKey('account-sign-out')), findsNothing);
    expect(find.byKey(const ValueKey('account-new-password')), findsNothing);
    expect(_verticalScrollables(), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('account-login')));
    await tester.tap(find.byKey(const ValueKey('settings-network')));
    expect([login, network], [1, 1]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('local authorization and remote password retain readiness gates',
      (tester) async {
    var ready = false;
    final saved = <String>[];
    var passwords = 0;
    var pendingPassword = Completer<bool>();
    await tester.pumpWidget(MaterialApp(
        theme: homeDeskTheme(ThemeData()),
        home: Scaffold(
            body: _workspace(
                settingsBuilder: (_) => NestLinkRemoteSettings(
                    readOption: (_) => 'click',
                    remoteReady: () => ready,
                    saveOption: (key, value) async => saved.add('$key:$value'),
                    saveRemotePassword: (_) {
                      passwords++;
                      return pendingPassword.future;
                    })))));
    await tester.tap(find.byKey(const ValueKey('remote-settings-toggle')));
    await tester.pumpAndSettle();
    final authorization = tester.widget<DropdownButtonFormField<String>>(
        find.byKey(const ValueKey('settings-host-authorization')));
    authorization.onChanged!('password');
    await tester.pumpAndSettle();
    await tester.ensureVisible(
        find.byKey(const ValueKey('settings-edit-remote-password')));
    await tester
        .tap(find.byKey(const ValueKey('settings-edit-remote-password')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('settings-remote-password')),
        'synthetic-password');
    await tester.enterText(
        find.byKey(const ValueKey('settings-confirm-remote-password')),
        'synthetic-password');
    await tester.ensureVisible(
        find.byKey(const ValueKey('settings-save-remote-password')));
    await tester
        .tap(find.byKey(const ValueKey('settings-save-remote-password')));
    await tester.pumpAndSettle();
    expect(saved, isEmpty);
    expect(passwords, 0);
    expect(
        find.descendant(
            of: find.byType(NestLinkDialog), matching: find.text('请等待远控服务就绪')),
        findsOneWidget);
    ready = true;
    authorization.onChanged!('password');
    await tester.pumpAndSettle();
    expect(saved, ['approve-mode:password']);
    final savePassword = tester
        .widget<FilledButton>(
            find.byKey(const ValueKey('settings-save-remote-password')))
        .onPressed!;
    savePassword();
    await tester.pump();
    savePassword();
    expect(passwords, 1);
    pendingPassword.complete(false);
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextField>(
                find.byKey(const ValueKey('settings-remote-password')))
            .controller!
            .text,
        'synthetic-password');
    pendingPassword = Completer<bool>();
    await tester
        .tap(find.byKey(const ValueKey('settings-save-remote-password')));
    pendingPassword.complete(true);
    await tester.pumpAndSettle();
    expect(passwords, 2);
    expect(
        find.byKey(const ValueKey('settings-remote-password')), findsNothing);
    expect(find.text('远控密码已保存'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'replacement account discards remote password drafts and pending save feedback',
      (tester) async {
    final account = HomeDeskAccount();
    final old = AccountFixtureApi()..signedIn = true;
    final replacement = AccountFixtureApi()..signedIn = true;
    final pendingPassword = Completer<bool>();
    final saved = <String>[];
    account.publish(old, old.result, '', (_) async {});
    await tester.pumpWidget(MaterialApp(
        theme: homeDeskTheme(ThemeData()),
        home: Scaffold(
            body: _workspace(
                account: account,
                settingsBuilder: (_) => NestLinkRemoteSettings(
                    account: account,
                    readOption: (_) => 'click',
                    remoteReady: () => true,
                    saveRemotePassword: (password) {
                      saved.add(password);
                      return pendingPassword.future;
                    })))));
    await tester.tap(find.byKey(const ValueKey('remote-settings-toggle')));
    await tester.pumpAndSettle();
    final passwordField =
        find.byKey(const ValueKey('settings-remote-password'));
    final saveButton =
        find.byKey(const ValueKey('settings-save-remote-password'));
    final editPassword =
        find.byKey(const ValueKey('settings-edit-remote-password'));
    await tester.ensureVisible(editPassword);
    await tester.tap(editPassword);
    await tester.pumpAndSettle();
    await tester.enterText(passwordField, 'account-a-password');
    await tester.enterText(
        find.byKey(const ValueKey('settings-confirm-remote-password')),
        'account-a-password');
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pump();
    expect(saved, ['account-a-password']);
    expect(tester.widget<FilledButton>(saveButton).onPressed, isNull);

    account.publish(replacement, replacement.result, '', (_) async {});
    await tester.pumpAndSettle();
    expect(find.byType(NestLinkDialog), findsNothing);
    await tester.ensureVisible(editPassword);
    await tester.tap(editPassword);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(passwordField).controller!.text, isEmpty);
    expect(tester.widget<FilledButton>(saveButton).onPressed, isNotNull);
    await tester.enterText(passwordField, 'account-b-draft');

    pendingPassword.complete(true);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(passwordField).controller!.text,
        'account-b-draft');
    expect(find.text('远控密码已保存'), findsNothing);
    expect(saved, ['account-a-password']);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    account.dispose();
    old.close();
    replacement.close();
  });

  testWidgets('saved sign-out cannot act on a replacement account',
      (tester) async {
    final account = HomeDeskAccount();
    final old = AccountFixtureApi()..signedIn = true;
    var oldSignOuts = 0, newSignOuts = 0;
    account.publish(old, old.result, '', (_) async {},
        onSignOut: () async => oldSignOuts++);
    await tester.pumpWidget(MaterialApp(
        theme: homeDeskTheme(ThemeData()),
        home: Scaffold(
            body: NestLinkAccountPage(
                account: account,
                onLogin: () {},
                settingsBuilder: (_) => const SizedBox()))));
    await tester.pumpAndSettle();
    final stale = tester
        .widget<OutlinedButton>(find.byKey(const ValueKey('account-sign-out')))
        .onPressed!;
    final replacement = AccountFixtureApi()..signedIn = true;
    account.publish(replacement, replacement.result, '', (_) async {},
        onSignOut: () async => newSignOuts++);
    await tester.pumpAndSettle();
    stale();
    await tester.pumpAndSettle();
    expect([oldSignOuts, newSignOuts], [0, 0]);
    expect(account.signedIn, isTrue);
    final current = tester
        .widget<OutlinedButton>(find.byKey(const ValueKey('account-sign-out')))
        .onPressed!;
    current();
    current();
    await tester.pumpAndSettle();
    expect([oldSignOuts, newSignOuts], [0, 1]);
    expect(account.signedIn, isFalse);
    expect(find.byKey(const ValueKey('account-login')), findsOneWidget);
    expect(find.byKey(const ValueKey('account-new-password')), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    account.dispose();
    old.close();
    replacement.close();
  });

  testWidgets(
      'revoking the current management session uses full account cleanup',
      (tester) async {
    final account = HomeDeskAccount();
    final api = AccountFixtureApi()
      ..signedIn = true
      ..sessions = [
        {
          'id': '40000000-0000-4000-8000-000000000001',
          'client_type': 'desktop',
          'created_at': '2026-10-10 12:00:00',
          'current': true,
        }
      ];
    var signOuts = 0;
    account.publish(api, api.result, '', (_) async {},
        onSignOut: () async => signOuts++);
    await tester.pumpWidget(MaterialApp(
        theme: homeDeskTheme(ThemeData()),
        home: Scaffold(
            body: NestLinkAccountPage(
                account: account,
                onLogin: () {},
                settingsBuilder: (_) => const SizedBox()))));
    await tester.pumpAndSettle();
    final revokeButton = find.widgetWithText(TextButton, '退出会话');
    await tester.ensureVisible(revokeButton);
    await tester.pumpAndSettle();
    expect(revokeButton.hitTestable(), findsOneWidget);
    await tester.tap(revokeButton);
    await tester.pumpAndSettle();
    expect(api.revoked, ['40000000-0000-4000-8000-000000000001']);
    expect(signOuts, 1);
    expect(account.signedIn, isFalse);
    expect(find.byKey(const ValueKey('account-login')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    account.dispose();
    api.close();
  });

  testWidgets(
      'merged settings remain scrollable in a narrow window with large text',
      (tester) async {
    tester.view.physicalSize = const Size(360, 560);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var network = 0;
    await tester.pumpWidget(MaterialApp(
        theme: homeDeskTheme(ThemeData()),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!),
        home: Scaffold(
            body: NestLinkAccountPage(
                onLogin: () {},
                settingsBuilder: (_) => NestLinkSettings(
                    embedded: true, onNetworkSettings: () => network++)))));
    await tester.pumpAndSettle();
    expect(_verticalScrollables(), findsOneWidget);
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('settings-network')), 160,
        scrollable: _verticalScrollables());
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('settings-network')).hitTestable(),
        findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('settings-network')));
    expect(network, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'version dialog scrolls long notes on a narrow window and keeps actions visible',
      (tester) async {
    tester.view.physicalSize = const Size(360, 560);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    nestlinkRelease.value = {
      'version': '14.0.1',
      'notes': List.filled(30, '这是用于验证长版本说明的合成内容。').join('\n'),
      'url': 'https://example.com/releases',
    };
    addTearDown(() => nestlinkRelease.value = null);
    await tester.pumpWidget(MaterialApp(
        theme: homeDeskTheme(ThemeData()),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!),
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    onPressed: () => showNestLinkVersion(context),
                    child: const Text('版本入口'))))));
    await tester.tap(find.text('版本入口'));
    await tester.pumpAndSettle();
    expect(find.byType(NestLinkDialog), findsOneWidget);
    expect(find.text(nestlinkVersion), findsOneWidget);
    expect(find.text('版本与下载').hitTestable(), findsOneWidget);
    expect(find.text('关闭').hitTestable(), findsOneWidget);
    await tester.drag(
        find.byType(SingleChildScrollView), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(find.text('关闭').hitTestable(), findsOneWidget);
    expect(find.byKey(const ValueKey('nestlink-dialog-close')), findsNothing);
    expect(
        find.descendant(
            of: find.byType(NestLinkDialog),
            matching: find.byIcon(Icons.close_rounded)),
        findsNothing);
    expect(tester.getRect(find.text('关闭')).bottom, lessThanOrEqualTo(560));
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(find.byType(NestLinkDialog), findsNothing);
  });
}
