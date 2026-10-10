import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/common.dart' show CustomAlertDialog;
import 'package:flutter_hbb/homedesk_theme.dart';
import 'package:flutter_hbb/homedesk_service_editor.dart';
import 'package:flutter_hbb/nestlink_dialog.dart';

void main() {
  Future<void> mouseDrag(WidgetTester tester, Offset delta) async {
    final mouse = await tester.startGesture(
      tester
          .getCenter(find.byKey(const ValueKey('nestlink-dialog-title-drag'))),
      kind: PointerDeviceKind.mouse,
    );
    await mouse.moveBy(const Offset(24, 0));
    await tester.pump();
    await mouse.moveBy(delta);
    await tester.pump();
    await mouse.up();
    await tester.pumpAndSettle();
  }

  testWidgets(
      'an informational dialog closes through its footer and pops its route',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(builder: (context) {
        return TextButton(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => const NestLinkDialog(
              title: Text('本机共享'),
              content: Text('连接信息'),
            ),
          ),
          child: const Text('打开弹窗'),
        );
      })),
    ));
    await tester.tap(find.text('打开弹窗'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.close_rounded), findsNothing);
    final close = find.byKey(const ValueKey('nestlink-dialog-default-close'));
    expect(close.hitTestable(), findsOneWidget);
    await tester.tap(close);
    await tester.pumpAndSettle();
    expect(find.byType(NestLinkDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'noncancellable shared dialogs do not acquire a default closing action',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
          body: CustomAlertDialog(
        title: Text('正在建立连接'),
        content: Text('请稍候'),
      )),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('nestlink-dialog-default-close')),
        findsNothing);
    expect(find.byIcon(Icons.close_rounded), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.text('请稍候'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'mouse dragging moves the whole dialog without resizing its fields or actions',
      (tester) async {
    tester.view.physicalSize = const Size(900, 680);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var closes = 0, saves = 0;
    await tester.pumpWidget(MaterialApp(
      theme: homeDeskTheme(ThemeData.light()),
      home: Scaffold(
          body: NestLinkDialog(
        width: 420,
        title: const Text('编辑设备'),
        onClose: () => closes++,
        content: const TextField(key: ValueKey('drag-field')),
        actions: [
          FilledButton(
            key: const ValueKey('drag-save'),
            onPressed: () => saves++,
            child: const Text('保存'),
          ),
          TextButton(
              key: const ValueKey('explicit-close'),
              onPressed: () => closes++,
              child: const Text('关闭'))
        ],
      )),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('nestlink-dialog-close')), findsNothing);
    expect(find.byKey(const ValueKey('nestlink-dialog-default-close')),
        findsNothing);
    final frame = find.byKey(const ValueKey('nestlink-dialog-frame'));
    final titleRegion = find
        .ancestor(
            of: find.byKey(const ValueKey('nestlink-dialog-title-drag')),
            matching: find.byType(MouseRegion))
        .first;
    expect(tester.widget<MouseRegion>(titleRegion).cursor,
        SystemMouseCursors.basic);
    final before = tester.getRect(frame);
    final fieldSize = tester.getSize(find.byKey(const ValueKey('drag-field')));
    final actionSize = tester.getSize(find.byKey(const ValueKey('drag-save')));
    await mouseDrag(tester, const Offset(90, 50));
    final moved = tester.getRect(frame);
    expect(moved.left, greaterThan(before.left + 70));
    expect(moved.top, greaterThan(before.top + 40));
    expect(moved.size, before.size);
    expect(tester.getSize(find.byKey(const ValueKey('drag-field'))), fieldSize);
    expect(tester.getSize(find.byKey(const ValueKey('drag-save'))), actionSize);
    await tester.enterText(find.byKey(const ValueKey('drag-field')), '书房');
    await tester.tap(find.byKey(const ValueKey('drag-save')));
    expect(saves, 1);
    await tester.tap(find.byKey(const ValueKey('explicit-close')));
    expect(closes, 1);
    expect(tester.getRect(frame), moved);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'drag bounds and viewport changes keep the default footer close reachable',
      (tester) async {
    tester.view.physicalSize = const Size(900, 680);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final insets = ValueNotifier<EdgeInsets>(EdgeInsets.zero);
    addTearDown(insets.dispose);
    var closes = 0;
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => ValueListenableBuilder<EdgeInsets>(
        valueListenable: insets,
        builder: (context, value, _) => MediaQuery(
          data: MediaQuery.of(context).copyWith(viewInsets: value),
          child: child!,
        ),
      ),
      home: Scaffold(
          body: NestLinkDialog(
        width: 380,
        title: const SizedBox.shrink(),
        onClose: () => closes++,
        content: const Text('连接信息'),
      )),
    ));
    await tester.pumpAndSettle();
    final frame = find.byKey(const ValueKey('nestlink-dialog-frame'));
    final size = tester.getSize(frame);
    expect(
        tester
            .getSize(find.byKey(const ValueKey('nestlink-dialog-title-drag')))
            .height,
        greaterThanOrEqualTo(40));
    await mouseDrag(tester, const Offset(3000, 3000));
    final rightBottom = tester.getRect(frame);
    expect(rightBottom.right, lessThanOrEqualTo(892));
    expect(rightBottom.bottom, lessThanOrEqualTo(672));
    expect(rightBottom.size, size);
    expect(
        find
            .byKey(const ValueKey('nestlink-dialog-default-close'))
            .hitTestable(),
        findsOneWidget);
    await mouseDrag(tester, const Offset(-3000, -3000));
    final leftTop = tester.getRect(frame);
    expect(leftTop.left, greaterThanOrEqualTo(8));
    expect(leftTop.top, greaterThanOrEqualTo(8));
    expect(leftTop.size, size);
    await mouseDrag(tester, const Offset(3000, 3000));
    tester.view.physicalSize = const Size(480, 440);
    await tester.pumpAndSettle();
    var recovered = tester.getRect(frame);
    expect(recovered.left, greaterThanOrEqualTo(8));
    expect(recovered.right, lessThanOrEqualTo(472));
    expect(recovered.bottom, lessThanOrEqualTo(432));
    insets.value = const EdgeInsets.only(bottom: 150);
    await tester.pumpAndSettle();
    recovered = tester.getRect(frame);
    expect(recovered.bottom, lessThanOrEqualTo(282));
    expect(
        find
            .byKey(const ValueKey('nestlink-dialog-default-close'))
            .hitTestable(),
        findsOneWidget);
    await tester
        .tap(find.byKey(const ValueKey('nestlink-dialog-default-close')));
    expect(closes, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dialog wraps its title and actions while only the body scrolls',
      (tester) async {
    tester.view.physicalSize = const Size(340, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: homeDeskTheme(ThemeData.light()),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(2)),
        child: child!,
      ),
      home: Scaffold(
        body: NestLinkDialog(
          title: const Row(children: [
            Icon(Icons.warning_rounded),
            SizedBox(width: 10),
            Expanded(child: Text('Confirm replacing an existing file')),
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < 16; i++) Text('设备信息 $i'),
            ],
          ),
          actions: [
            OutlinedButton(onPressed: () {}, child: const Text('取消当前操作')),
            FilledButton(
              key: const ValueKey('fixed-save'),
              onPressed: () {},
              child: const Text('确认并保存设置'),
            ),
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final save = find.byKey(const ValueKey('fixed-save'));
    expect(save.hitTestable(), findsOneWidget);
    final before = tester.getRect(save);
    await tester.drag(
        find.byType(SingleChildScrollView), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(tester.getRect(save), before);
    expect(before.bottom, lessThanOrEqualTo(540));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'shared dialog supports reverse Tab and activates focused buttons once',
      (tester) async {
    final first = FocusNode(), second = FocusNode(), save = FocusNode();
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    addTearDown(save.dispose);
    var submits = 0, saves = 0, cancels = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CustomAlertDialog(
          title: const Text('连接设置'),
          onSubmit: () => submits++,
          onCancel: () => cancels++,
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(focusNode: first, autofocus: true),
            TextField(focusNode: second),
          ]),
          actions: [
            FilledButton(
              focusNode: save,
              onPressed: () => saves++,
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(first.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(second.hasFocus, isTrue);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(first.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(submits, 1);
    save.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(saves, 1);
    expect(submits, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(cancels, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('multiline fields and modified Enter keep their editing behavior',
      (tester) async {
    var submits = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CustomAlertDialog(
          title: const Text('网络白名单'),
          onSubmit: () => submits++,
          content: const TextField(autofocus: true, maxLines: 4),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(submits, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'device tag review keeps server compatibility metadata without a favorite control',
      (tester) async {
    HomeDeskDeviceDraft? saved;
    await tester.pumpWidget(MaterialApp(
      theme: homeDeskTheme(ThemeData.light()),
      home: Scaffold(
        body: HomeDeskDeviceEditor(
          deviceName: '书房电脑',
          initial: const HomeDeskDeviceDraft(
            tags: ['旧标签'],
            favorite: false,
            expectedMetadataVersion: 1,
          ),
          needsReview: true,
          isAllowed: () => true,
          onReview: () async => const HomeDeskDeviceDraft(
            tags: ['服务器标签'],
            favorite: true,
            expectedMetadataVersion: 2,
          ),
          onSave: (draft) async => saved = draft,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('device-favorite')), findsNothing);
    expect(find.textContaining('收藏'), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('device-tags')), '新标签');
    await tester.tap(find.byKey(const ValueKey('device-review')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('device-reviewed')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('device-save')));
    await tester.pumpAndSettle();
    expect(saved?.tags, ['新标签']);
    expect(saved?.favorite, isTrue);
    expect(saved?.expectedMetadataVersion, 2);
    expect(tester.takeException(), isNull);
  });
}
