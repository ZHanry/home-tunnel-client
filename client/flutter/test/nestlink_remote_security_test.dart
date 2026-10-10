import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/homedesk_theme.dart';
import 'package:flutter_hbb/models/server_model.dart';
import 'package:flutter_hbb/nestlink_dialog.dart';
import 'package:flutter_hbb/nestlink_workspace.dart';

Finder control(String key) => find.byKey(ValueKey(key));

Widget host(Widget child, {double scale = 1}) => MaterialApp(
    theme: homeDeskTheme(ThemeData()),
    builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!),
    home: Scaffold(
        body: ListView(padding: const EdgeInsets.all(24), children: [child])));

Future<void> press(WidgetTester tester, String key) async {
  await tester.ensureVisible(control(key));
  await tester.tap(control(key));
  await tester.pumpAndSettle();
}

Future<void> passwordPair(WidgetTester tester, String password) async {
  await tester.enterText(control('settings-remote-password'), password);
  await tester.enterText(control('settings-confirm-remote-password'), password);
}

void main() {
  testWidgets(
      'active remote configuration restrictions gate options and password dialogs',
      (tester) async {
    var blocked = true, ready = true;
    final saved = <String>[];
    Completer<bool>? pending;
    await tester.pumpWidget(host(NestLinkRemoteSettings(
      readOption: (_) => '',
      remoteReady: () => ready,
      initiallyLocked: false,
      hasRemotePassword: () async => false,
      remoteConfigBlocked: () => pending?.future ?? Future.value(blocked),
      saveOption: (key, value) async => saved.add('$key:$value'),
      saveRemotePassword: (_) async {
        saved.add('password');
        return true;
      },
    )));
    await tester.pumpAndSettle();
    tester
        .widget<DropdownButtonFormField<String>>(
            control('settings-host-authorization'))
        .onChanged!('password');
    await tester.pumpAndSettle();
    expect(saved, isEmpty);
    expect(find.text('当前远控会话不允许修改本机安全设置'), findsOneWidget);
    await press(tester, 'settings-edit-remote-password');
    await passwordPair(tester, 'synthetic-password');
    await press(tester, 'settings-save-remote-password');
    expect(saved, isEmpty);
    expect(
        tester
            .widget<TextField>(control('settings-remote-password'))
            .controller!
            .text,
        'synthetic-password');
    blocked = false;
    pending = Completer<bool>();
    tester
        .widget<FilledButton>(control('settings-save-remote-password'))
        .onPressed!();
    await tester.pump();
    ready = false;
    pending.complete(false);
    await tester.pumpAndSettle();
    expect(saved, isEmpty);
    expect(
        find.descendant(
            of: find.byType(NestLinkDialog), matching: find.text('请等待远控服务就绪')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'password-only approval cannot activate an unset permanent password',
      (tester) async {
    final saved = <String>[];
    await tester.pumpWidget(host(NestLinkRemoteSettings(
      readOption: (key) => key == kOptionVerificationMethod
          ? kUsePermanentPassword
          : key == kOptionApproveMode
              ? 'click'
              : '',
      remoteReady: () => true,
      initiallyLocked: false,
      hasRemotePassword: () async => false,
      saveOption: (key, value) async => saved.add('$key:$value'),
      saveRemotePassword: (_) async => true,
    )));
    await tester.pumpAndSettle();
    tester
        .widget<DropdownButtonFormField<String>>(
            control('settings-host-authorization'))
        .onChanged!('password');
    await tester.pumpAndSettle();
    expect(find.byType(NestLinkDialog), findsOneWidget);
    expect(saved, isEmpty);
    await passwordPair(tester, 'synthetic-password');
    await press(tester, 'settings-save-remote-password');
    expect(saved, ['approve-mode:password']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('whitelist validates and normalizes entries before saving',
      (tester) async {
    final saved = <String>[];
    await tester.pumpWidget(host(NestLinkRemoteSettings(
      readOption: (_) => '',
      remoteReady: () => true,
      initiallyLocked: false,
      hasRemotePassword: () async => false,
      saveOption: (key, value) async => saved.add('$key:$value'),
    )));
    await tester.pumpAndSettle();
    await press(tester, 'settings-tab-2');
    await press(tester, 'settings-whitelist');
    await tester.enterText(
        control('settings-edit-whitelist'), '192.168.2.0/99');
    await press(tester, 'settings-save-whitelist');
    expect(saved, isEmpty);
    expect(find.text('请输入有效的 IP 地址或 CIDR 网段'), findsOneWidget);
    await tester.enterText(
        control('settings-edit-whitelist'), '192.168.2.0/24\n10.1.2.3');
    await press(tester, 'settings-save-whitelist');
    expect(saved, ['whitelist:192.168.2.0/24,10.1.2.3']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('default authorization matches the native password-or-click mode',
      (tester) async {
    final saved = <String>[];
    await tester.pumpWidget(host(NestLinkRemoteSettings(
      readOption: (_) => '',
      remoteReady: () => true,
      initiallyLocked: false,
      hasRemotePassword: () async => false,
      saveOption: (key, value) async => saved.add('$key:$value'),
    )));
    await tester.pumpAndSettle();
    final mode = tester.widget<DropdownButtonFormField<String>>(
        control('settings-host-authorization'));
    expect(mode.initialValue, 'both');
    mode.onChanged!('both');
    await tester.pumpAndSettle();
    expect(saved, ['approve-mode:password-click']);
    expect(find.text('验证密码或由本机点击允许，任一方式均可连接。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'presets show effective native permissions without overwriting custom values',
      (tester) async {
    final options = <String, String>{
      kOptionEnableKeyboard: 'N',
      kOptionEnableClipboard: 'Y'
    };
    final saved = <String>[];
    await tester.pumpWidget(host(NestLinkRemoteSettings(
      readOption: (key) => options[key] ?? '',
      remoteReady: () => true,
      initiallyLocked: false,
      privacyModeSupported: true,
      hasRemotePassword: () async => true,
      saveOption: (key, value) async {
        options[key] = value;
        saved.add('$key:$value');
      },
    )));
    await tester.pumpAndSettle();
    await press(tester, 'settings-tab-1');
    Switch keyboard() =>
        tester.widget<Switch>(control('settings-enable-keyboard'));
    expect(keyboard().value, isFalse);
    keyboard().onChanged!(true);
    await tester.pumpAndSettle();
    expect(saved, ['enable-keyboard:Y']);
    void setMode(String mode) => tester
        .widget<DropdownButtonFormField<String>>(
            control('settings-access-mode'))
        .onChanged!(mode);
    setMode('full');
    await tester.pumpAndSettle();
    expect(keyboard().value, isTrue);
    expect(keyboard().onChanged, isNull);
    expect(
        tester
            .widget<Switch>(
                control('settings-allow-remote-config-modification'))
            .value,
        isTrue);
    setMode('view');
    await tester.pumpAndSettle();
    for (final toggle in tester.widgetList<Switch>(find.byType(Switch))) {
      expect(toggle.value, isFalse);
      expect(toggle.onChanged, isNull);
    }
    setMode('custom');
    await tester.pumpAndSettle();
    expect(keyboard().value, isTrue);
    expect(keyboard().onChanged, isNotNull);
    expect(options[kOptionEnableClipboard], 'Y');
    expect(saved, [
      'enable-keyboard:Y',
      'access-mode:full',
      'access-mode:view',
      'access-mode:custom'
    ]);
    for (final key in [
      kOptionEnableKeyboard,
      kOptionEnableClipboard,
      kOptionEnableFileTransfer,
      kOptionEnableAudio,
      kOptionEnableCamera,
      kOptionEnableTerminal,
      kOptionEnableTunnel,
      kOptionEnableRemoteRestart,
      kOptionEnableRecordSession,
      if (Platform.isWindows) kOptionEnableRemotePrinter,
      if (Platform.isWindows) kOptionEnableBlockInput,
      kOptionEnablePrivacyMode,
      kOptionAllowRemoteConfigModification
    ]) {
      expect(control('settings-$key'), findsOneWidget);
    }
    if (!Platform.isWindows) {
      expect(control('settings-$kOptionEnableRemotePrinter'), findsNothing);
      expect(control('settings-$kOptionEnableBlockInput'), findsNothing);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'locked settings and fixed policy cannot be bypassed by stale callbacks',
      (tester) async {
    var unlock = false;
    final saved = <String>[];
    await tester.pumpWidget(host(NestLinkRemoteSettings(
      readOption: (_) => '',
      remoteReady: () => true,
      initiallyLocked: true,
      unlockSettings: () async => unlock,
      isOptionFixed: (key) => key == kOptionEnableCamera,
      hasRemotePassword: () async => false,
      saveOption: (key, value) async => saved.add('$key:$value'),
    )));
    await tester.pumpAndSettle();
    await press(tester, 'settings-tab-1');
    expect(tester.widget<Switch>(control('settings-enable-keyboard')).onChanged,
        isNull);
    await press(tester, 'settings-unlock');
    expect(tester.widget<Switch>(control('settings-enable-keyboard')).onChanged,
        isNull);
    unlock = true;
    await press(tester, 'settings-unlock');
    expect(tester.widget<Switch>(control('settings-enable-keyboard')).onChanged,
        isNotNull);
    expect(tester.widget<Switch>(control('settings-enable-camera')).onChanged,
        isNull);
    expect(saved, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'permission writes retain account readiness and failures retain current state',
      (tester) async {
    var ready = false, fail = false;
    var writes = 0;
    await tester.pumpWidget(host(NestLinkRemoteSettings(
      readOption: (_) => '',
      remoteReady: () => ready,
      initiallyLocked: false,
      hasRemotePassword: () async => false,
      saveOption: (_, __) async {
        writes++;
        if (fail) throw StateError('synthetic failure');
      },
    )));
    await tester.pumpAndSettle();
    await press(tester, 'settings-tab-1');
    void disable() => tester
        .widget<Switch>(control('settings-enable-keyboard'))
        .onChanged!(false);
    disable();
    await tester.pumpAndSettle();
    expect(writes, 0);
    expect(find.text('请等待远控服务就绪'), findsOneWidget);
    ready = true;
    fail = true;
    disable();
    await tester.pumpAndSettle();
    expect(writes, 1);
    expect(tester.widget<Switch>(control('settings-enable-keyboard')).value,
        isTrue);
    expect(find.text('设置未保存，请重试或检查此设备的设置策略。'), findsOneWidget);
    fail = false;
    disable();
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(control('settings-enable-keyboard')).value,
        isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'cancelled password setup restores the actual selected verification method',
      (tester) async {
    final saved = <String>[];
    await tester.pumpWidget(host(NestLinkRemoteSettings(
      readOption: (key) =>
          key == kOptionVerificationMethod ? kUseTemporaryPassword : '',
      remoteReady: () => true,
      initiallyLocked: false,
      hasRemotePassword: () async => false,
      saveOption: (key, value) async => saved.add('$key:$value'),
    )));
    await tester.pumpAndSettle();
    await press(tester, 'settings-password-verification');
    await tester.tap(find.text('仅固定密码').last);
    await tester.pumpAndSettle();
    expect(find.byType(NestLinkDialog), findsOneWidget);
    expect(saved, isEmpty);
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();
    final selected = tester.widget<DropdownButton<String>>(find.descendant(
        of: control('settings-password-verification'),
        matching: find.byType(DropdownButton<String>)));
    expect(selected.value, kUseTemporaryPassword);
    expect(saved, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'permanent-only activation follows confirmed password success and blocks repeated save',
      (tester) async {
    final saved = <String>[];
    var pending = Completer<bool>();
    var writes = 0;
    await tester.pumpWidget(host(NestLinkRemoteSettings(
      readOption: (key) =>
          key == kOptionVerificationMethod ? kUseTemporaryPassword : '',
      remoteReady: () => true,
      initiallyLocked: false,
      hasRemotePassword: () async => false,
      saveOption: (key, value) async => saved.add('$key:$value'),
      saveRemotePassword: (_) {
        writes++;
        return pending.future;
      },
    )));
    await tester.pumpAndSettle();
    tester
        .widget<DropdownButtonFormField<String>>(
            control('settings-password-verification'))
        .onChanged!(kUsePermanentPassword);
    await tester.pumpAndSettle();
    await tester.enterText(
        control('settings-remote-password'), 'synthetic-password');
    await tester.enterText(
        control('settings-confirm-remote-password'), 'different-password');
    await press(tester, 'settings-save-remote-password');
    expect(find.text('两次输入不一致'), findsOneWidget);
    expect(writes, 0);
    await passwordPair(tester, 'synthetic-password');
    final save = tester
        .widget<FilledButton>(control('settings-save-remote-password'))
        .onPressed!;
    save();
    await tester.pump();
    save();
    expect(writes, 1);
    expect(saved, isEmpty);
    expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, '取消'))
            .onPressed,
        isNull);
    pending.complete(false);
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextField>(control('settings-remote-password'))
            .controller!
            .text,
        'synthetic-password');
    expect(saved, isEmpty);
    pending = Completer<bool>();
    tester
        .widget<FilledButton>(control('settings-save-remote-password'))
        .onPressed!();
    pending.complete(true);
    await tester.pumpAndSettle();
    expect(saved, ['verification-method:$kUsePermanentPassword']);
    expect(find.byType(NestLinkDialog), findsNothing);
    expect(find.text('修改密码'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'session and connection protection options and validated ports remain available',
      (tester) async {
    final saved = <String>[];
    await tester.pumpWidget(host(NestLinkRemoteSettings(
      readOption: (_) => '',
      remoteReady: () => true,
      initiallyLocked: false,
      hasRemotePassword: () async => false,
      saveOption: (key, value) async => saved.add('$key:$value'),
    )));
    await tester.pumpAndSettle();
    await press(tester, 'settings-tab-2');
    expect(control('settings-keep-awake-during-incoming-sessions'),
        findsOneWidget);
    expect(control('settings-enable-lan-discovery'), findsOneWidget);
    expect(control('settings-whitelist'), findsOneWidget);
    tester.widget<Switch>(control('settings-direct-server')).onChanged!(true);
    await tester.pumpAndSettle();
    await press(tester, 'settings-direct-port');
    await tester.enterText(
        control('settings-edit-direct-access-port'), '65536');
    await press(tester, 'settings-save-direct-access-port');
    expect(find.text('请输入 1 到 65535 的整数'), findsOneWidget);
    expect(saved, ['direct-server:Y']);
    await tester.enterText(
        control('settings-edit-direct-access-port'), '21119');
    await press(tester, 'settings-save-direct-access-port');
    expect(saved.last, 'direct-access-port:21119');
    tester
        .widget<Switch>(control('settings-allow-auto-disconnect'))
        .onChanged!(true);
    await tester.pumpAndSettle();
    expect(control('settings-idle-timeout'), findsOneWidget);
    expect(find.text('停止服务'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
